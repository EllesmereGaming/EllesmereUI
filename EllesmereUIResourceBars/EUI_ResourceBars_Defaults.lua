if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ResourceBars_Defaults.lua
--
--  The druid hide-per-form checks and the DEFAULTS table.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local UnitClass, GetShapeshiftFormID = UnitClass, GetShapeshiftFormID

-- per-element scale, border, colors, text, alerts
-------------------------------------------------------------------------------
local _, playerClassFile = UnitClass("player")

-- Druid "hide bar text per form", the same buckets on every bar: Cat (1),
-- Bear (5) and Moonkin (31/35) each have their own; any other form, or none,
-- is "Caster" ("mana").
_G._ERB_TextHiddenByForm = function(cfg)
    if playerClassFile ~= "DRUID" then return false end
    local df = cfg and cfg.textDisabledForms
    if not df then return false end
    local f = GetShapeshiftFormID()
    local key = (f == 1) and "energy" or (f == 5) and "rage" or (f == 31 or f == 35) and "moonkin" or "mana"
    return df[key] and true or false
end
-- Druid "hide whole bar per form": the same buckets as above, driven by
-- cfg.barDisabledForms. Alpha-based hide, safe to flip mid-combat.
_G._ERB_BarHiddenByForm = function(cfg)
    if playerClassFile ~= "DRUID" then return false end
    local df = cfg and cfg.barDisabledForms
    if not df then return false end
    local f = GetShapeshiftFormID()
    local key = (f == 1) and "energy" or (f == 5) and "rage" or (f == 31 or f == 35) and "moonkin" or "mana"
    return df[key] and true or false
end
-- Static neutral defaults for custom fill colors; used only as the initial custom
-- color when the user first enables "Custom Colored" (class/power colors apply
-- at runtime when customColored=false). NEVER use class-specific values:
-- StripDefaults on logout nils any channel matching the current class default,
-- then DeepMergeDefaults on a different class refills it with the wrong color.
local CUSTOM_FILL_DEFAULT = { 1, 1, 1 }

local DEFAULTS = {
    profile = {
        -- Blizzard Style (Global Settings > Style) for the health, power and
        -- class resource bars: the personal resource display's bar frame in
        -- place of the EUI full-bar border. Default OFF; reload-gated.
        useBlizzardStyleBars = false,
        -- Classic WoW UI (Global Settings > Style): the vanilla cast bar
        -- frame round the health, power and class resource bars in place of
        -- the EUI full-bar border. Default OFF; reload-gated.
        useClassicStyleBars = false,
        health = {
            enabled     = false,
            smoothBars  = false,
            width       = 214,
            height      = 16,
            borderSize  = 0,
            borderR     = 0, borderG = 0, borderB = 0, borderA = 1,
            borderTexture = "solid",
            darkTheme   = false,
            customColored = false,
            fillR       = CUSTOM_FILL_DEFAULT[1], fillG = CUSTOM_FILL_DEFAULT[2], fillB = CUSTOM_FILL_DEFAULT[3], fillA = 1,
            fillOpacity = 100,  -- 0-100; below 100 the world shows through the fill
            bgR         = 0x11/255, bgG = 0x11/255, bgB = 0x11/255, bgA = 0.75,
            textFormat  = "none",  -- "none","both","curhpshort","curmaxhp","perhp"
            textSize    = 11,
            textXOffset = 0,
            textYOffset = 0,
            textAnchor  = "CENTER",  -- "LEFT" | "CENTER" | "RIGHT": inner-bar text anchor (offsets apply from here)
            textCustomColored = true,  -- text color: true = custom, false = class color
            textFillR   = 1, textFillG = 1, textFillB = 1, textFillA = 1,
            gradientEnabled = false,  -- additive: gradient fill (custom/class base -> end). Off = existing behavior.
            gradientR     = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
            gradientDir   = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL"
            offsetX     = 0,
            offsetY     = -64,
            barAlpha    = 1.0,
            oocFadeEnabled = false,  -- "Fade Out of Combat" toggle (off by default)
            oocAlpha    = 0.5,       -- alpha the bar fades to while out of combat
            showWhenMissing = false,  -- reveal a hidden bar while below full (off by default)
            visibility  = "always",  -- "always","combat","target","mouseover","never","in_combat","in_raid","in_party","solo"
            visHideHousing = false,
            visOnlyInstances = false,
            visHideMounted = false,
            visHideDragonriding = false,
            visHideNoTarget = false,
            visHideNoEnemy = false,
            orientation = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL_UP","VERTICAL_DOWN"
            thresholdEnabled = false,
            thresholdPct     = 30,
            thresholdR = 1.0, thresholdG = 0.2, thresholdB = 0.2, thresholdA = 1,
            thresholdSpecs = {},
            thresholdTextInstead = false,
            -- Multi-band coloring
            multiBandEnabled = false,
            bandMode = "percent",  -- "percent" | "value" (bar/health/power only)
            bandReverse = false,
            bands = {},            -- ordered ascending by `to`: { { to=N, r,g,b,a }, ... }
            hashEnabled = false,
            hashValues  = "",          -- e.g. "25, 50, 75"
            hashMode    = "percent",
            hashWidth   = 1,
            hashColorR  = 1, hashColorG = 1, hashColorB = 1, hashColorA = 0.7,
        },
        primary = {
            -- Off by default on WoW Forever (vanilla content), on everywhere else.
            enabled     = (EllesmereUI.IS_FOREVER ~= true),
            smoothBars  = false,
            width       = 214,
            height      = 14,
            borderSize  = 1,
            borderR     = 0, borderG = 0, borderB = 0, borderA = 1,
            borderTexture = "solid",
            -- Border extensions (textured styles only): UI units past each
            -- screen edge. 0 = off (ns.ERB_BorderExtents).
            borderExtendTop = 0, borderExtendBottom = 0, borderExtendLeft = 0, borderExtendRight = 0,
            -- Bottom Separator (Border Options cog, textured styles only): edgeSep
            -- off = None; on = the companion strip along the bottom edge, art
            -- edgeSepArt ("match" = the bar's own style, else a border key),
            -- moved edgeSepY units. Values stored explicitly (never nil).
            edgeSep = false, edgeSepY = 0, edgeSepArt = "match",
            -- Draw Above GCD Bar (Border Options cog): the border over a GCD bar
            -- that overlaps this bar (ns.ERB_PowerLift).
            borderAboveGCD = false,
            darkTheme   = false,
            customColored = false,
            fillR       = CUSTOM_FILL_DEFAULT[1], fillG = CUSTOM_FILL_DEFAULT[2], fillB = CUSTOM_FILL_DEFAULT[3], fillA = 1,
            fillOpacity = 100,  -- 0-100; below 100 the world shows through the fill
            bgR         = 0x11/255, bgG = 0x11/255, bgB = 0x11/255, bgA = 0.75,
            textFormat  = "perpp",  -- "none","smart","curpp","curmaxpp","perpp","both"
            showPercent = true,
            textSize    = 10,
            textXOffset = 0,
            textYOffset = 0,
            textAnchor  = "CENTER",
            textCustomColored = true,  -- text color: true = custom, false = power-type color
            textFillR   = 1, textFillG = 1, textFillB = 1, textFillA = 1,
            gradientEnabled = false,  -- additive: gradient fill (custom/power base -> end). Off = existing behavior.
            gradientR     = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
            gradientDir   = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL"
            offsetX     = 0,
            offsetY     = -54,
            barAlpha    = 1.0,
            oocFadeEnabled = false,  -- "Fade Out of Combat" toggle (off by default)
            oocAlpha    = 0.5,       -- alpha the bar fades to while out of combat
            showWhenMissing = false,  -- reveal a hidden bar while below full (off by default)
            showManaWhenMissing = false,
            visibility  = "always",  -- "always","combat","target","mouseover","never","in_combat","in_raid","in_party","solo"
            visHideHousing = false,
            visOnlyInstances = false,
            visHideMounted = false,
            visHideDragonriding = false,
            visHideNoTarget = false,
            visHideNoEnemy = false,
            orientation = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL_UP","VERTICAL_DOWN"
            thresholdEnabled = false,
            thresholdPct     = 30,
            thresholdPartialOnly = false,
            thresholdR = 1.0, thresholdG = 0.2, thresholdB = 0.2, thresholdA = 1,
            thresholdSpecs = {},
            thresholdTextInstead = false,
            -- Multi-band coloring
            multiBandEnabled = false,
            bandMode = "percent",
            bandReverse = false,
            bands = {},
            -- User hash lines (opt-in). See health.hashEnabled for semantics.
            hashEnabled = false,
            hashValues  = "",
            hashMode    = "percent",
            hashWidth   = 1,
            hashColorR  = 1, hashColorG = 1, hashColorB = 1, hashColorA = 0.7,
            expandIfNoResource = false,
            -- Shift elements anchored to the power bar when the spec has no primary
            -- power (e.g. BM/MM Hunter, Focus shows as class resource). "None"/"Up"/
            -- "Down", visual-only.
            shiftElementsIfNoPower = "None",
            manaRegenSpark = false,  -- WoW Forever: mana regen spark while the bar shows mana; manaRegenSparkMode "ticks" = Regen Ticks, nil = 5-Second Rule
            -- WoW Forever: Spell Cost Prediction (powerCostPrediction, opt-in;
            -- powerCostColor, nil = Blizzard's mana prediction color). No
            -- defaults: nil is off, so retail profiles stay unchanged.
            -- WoW Forever, Druid: Mana Bar while Shapeshifted
            -- (EUI_ResourceBars_ForeverDruidMana.lua). Exists only on Forever,
            -- so retail profiles stay unchanged. gap: space between the two
            -- bars (not used Inside); the text keys mirror the Power Bar's own.
            foreverDruidMana = (EllesmereUI.IS_FOREVER == true) and {
                enabled     = false,
                position    = "below",  -- "below","above","inside"
                gap         = 2,
                height      = 6,
                offsetX     = 0,
                offsetY     = 0,
                textFormat  = "none",   -- "none","smart","curpp","curmaxpp","perpp","both"
                showPercent = true,
                textSize    = 8,
                textXOffset = 0,
                textYOffset = 0,
                textAnchor  = "CENTER",
                textCustomColored = true,  -- text color: true = custom, false = mana color
                textFillR   = 1, textFillG = 1, textFillB = 1, textFillA = 1,
            } or nil,
        },
        secondary = {
            -- Off by default on WoW Forever (vanilla content), on everywhere else.
            enabled     = (EllesmereUI.IS_FOREVER ~= true),
            smoothBars  = false,
            pipWidth    = 214,
            pipHeight   = 20,
            pipSpacing  = 1,
            pipOrientation = "HORIZONTAL",
            borderSize  = 1,
            borderR     = 0, borderG = 0, borderB = 0, borderA = 1,
            borderTexture = "solid",
            borderExtendTop = 0, borderExtendBottom = 0, borderExtendLeft = 0, borderExtendRight = 0,  -- full-bar border only, never per-pip
            -- Separators (Border Options cog): edgeSep = the dropdown's on/off (None
            -- = false), edgeSepH = the bottom-edge line, edgeSepV = one line per gap
            -- between pips and runes; edgeSepArt / edgeSepY as on the power bar.
            edgeSep = false, edgeSepH = true, edgeSepY = 0, edgeSepV = true, edgeSepArt = "match",
            pipBgOnPips = false,  -- Background on individual pips (Pip Border cog)
            raiseLevel  = false,  -- Draw Above Other Bars (Class Resource cog)
            darkTheme   = false,
            useBlizzardAtlas = false,  -- bar-style class resources use Blizzard's player-frame power atlas as the fill
            blizzardClassArt = false,  -- Blizzard's own class resource frame replaces this bar (specs that have one)
            blizzardClassArtScale = 1,
            classColored = true,
            resourceColored = false,  -- "Class Resource Color" fill mode (per-spec resource/power color); takes precedence over classColored when on
            fillR       = 0.95, fillG = 0.90, fillB = 0.60, fillA = 1,
            fillOpacity = 100,  -- 0-100; below 100 the world shows through the fill
            darkenPartialPips = true,  -- fractional Soul Shards/Essence use a darker fill while incomplete
            bgR         = 1, bgG = 1, bgB = 1, bgA = 0.1,
            showText    = true,
            showTextOnlyIfNoPower = false,  -- only show the resource text while the power bar is hidden (see IsPowerBarHidden)
            showPercent = false,  -- secondary "Show %": OFF (default) = current / max, ON = percent (Maelstrom/Insanity/Focus/Astral Power bars).
            showMaxStacks = true,
            textSize    = 11,
            textR       = 1, textG = 1, textB = 1,
            textXOffset = 0,
            textYOffset = 0,
            textAnchor  = "CENTER",
            barBgR      = 0, barBgG = 0, barBgB = 0, barBgA = 0.5,
            -- Opt-in gap color (color of the spacing between pips). Off by
            -- default -> the gap-fill layer is never drawn and the bar is
            -- unchanged. Only consulted when gapColorEnabled is true.
            gapColorEnabled = false,
            gapR        = 0, gapG = 0, gapB = 0, gapA = 1,
            barAlpha    = 1.0,
            thresholdEnabled = false,
            thresholdCount   = 3,
            thresholdPartialOnly = false,
            thresholdReverse = false,  -- bar-type only: threshold color below the value (spenders)
            thresholdR = 0x0c/255, thresholdG = 0xd2/255, thresholdB = 0x9d/255, thresholdA = 1,
            tickValues  = "",   -- comma-separated absolute resource values for tick marks (bar-type only)
            thresholdSpecs = {},  -- per-spec threshold/hash entries: { specIDs={0}, hashValues="", thresholdCount=3, thresholdPartialOnly=false }
            thresholdTextInstead = false,
            -- Multi-band coloring
            multiBandEnabled = false,
            bandMode = "percent",
            bandReverse = false,
            bands = {},
            staggerCeilingPercent = 100,   -- % required for bar to fill up
            -- Brewmaster Extended Stagger (opt-in): the bar spans Scale steps of 100% max
            -- health, one fill color and divider per step. Off: nothing below is read.
            brewExtendedStaggerBar = false,
            brewExtendedStaggerScale = 4,        -- 2-6
            brewExtendedStaggerColors = {},      -- per-step {r,g,b}; missing steps use ns.EXT_STAGGER_COLORS
            brewExtendedStaggerDividers = true,
            brewExtendedStaggerDividerWidth = 1,
            brewExtendedStaggerDividerR = 0, brewExtendedStaggerDividerG = 0, brewExtendedStaggerDividerB = 0, brewExtendedStaggerDividerA = 1,
            guardianIronfurBar = true,     -- Guardian Druid: Ironfur duration bar (moving hash lines). New-user default; existing profiles pinned off by migration "resourcebars_guardian_ironfur_existing_off_v1".
            guardianShowHashLines = true,  -- Guardian Ironfur: draw the moving per-cast hash lines
            protIgnorePainBar = true,      -- Prot Warrior: Ignore Pain bar (absorbs vs the IP cap = 30% max health; aura stacks are secret). New-user default; existing profiles pinned off by migration "resourcebars_protwar_ignorepain_existing_off_v1".
            protIgnorePainHashLine = true, -- Prot Ignore Pain: draw the moving duration hash line (resets on cast)
            armsSweepingStrikesBar = false, -- Arms Warrior: Sweeping Strikes charge pips on the resource bar (opt-in, default off). Unit Frames + personal Nameplate show them regardless.
            runesSimple = false,  -- DK: treat runes as flat pips (no recharge animation/timer)
            runesCustomRecharge = false,  -- DK: use a custom color for recharging runes instead of a dimmed version of the rune color
            runesRechargeR = 0.5, runesRechargeG = 0.5, runesRechargeB = 0.5, runesRechargeA = 1,
            chargedR = 0.44, chargedG = 0.77, chargedB = 1.00, chargedA = 1,
            enhanceFiveBar = true,  -- Enhance Shaman: show 5 pips with overflow coloring
            enhanceOverflowR = 1, enhanceOverflowG = 0.6, enhanceOverflowB = 0.2,
            visibility  = "always",  -- "always","combat","target","mouseover","never","in_combat","in_raid","in_party","solo"
            visHideHousing = false,
            visOnlyInstances = false,
            visHideMounted = false,
            visHideDragonriding = false,
            visHideNoTarget = false,
            visHideNoEnemy = false,
            oocFadeEnabled = false,  -- "Fade Out of Combat" toggle (off by default)
            oocAlpha    = 0.5,       -- alpha the bar fades to while out of combat
            offsetX     = 0,
            offsetY     = -38,
            -- Shift elements anchored to the class resource bar when the spec has
            -- no class resource. "None"/"Up"/"Down", visual-only.
            shiftElementsIfNoResource = "None",
        },
        castBar = {
            enabled       = true,
            -- Global Settings > Gamepad: stand this bar down while a controller
            -- is connected (ns.RB_ApplyGamepadCastbar).
            gamepadHide   = false,
            -- Blizzard Style (Global Settings > Style): the stock cast bar art
            -- (background, frame, text box, cast/channel fills, pip) on this
            -- bar with every feature intact. Default OFF; reload-gated.
            useBlizzardStyle = false,
            -- Classic WoW UI (Global Settings > Style): the vanilla cast bar
            -- frame and spark round the user's fill. Default OFF; reload-gated.
            useClassicStyle = false,
            alwaysShow    = false,  -- keep the bar on screen (sitting empty) while nothing is being cast
            showIcon      = true,
            iconOnPortrait = false,
            iconOnRight   = false,  -- attach the spell icon to the right of the bar instead of the left
            showIconDivider = false,  -- draw a 1px divider at the icon/bar seam (interior seam has no border otherwise)
            iconSize      = 0,  -- 0 = the bar height
            iconOffsetX   = 0,
            iconOffsetY   = 0,
            width         = 220,
            height        = 20,
            anchorX       = 0,
            anchorY       = -54,
            classColored  = false,
            fillR         = 0.898, fillG = 0.729, fillB = 0.267, fillA = 1,
            fillOpacity   = 100,  -- 0-100; below 100 the world shows through the fill
            gradientEnabled = false,
            gradientR     = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
            gradientDir   = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL"
            texture       = "none",
            textureBg     = false,  -- Textured Background (Texture Settings cog)
            showSpark     = true,
            borderSize    = 1,
            borderR       = 0, borderG = 0, borderB = 0, borderA = 1,
            borderTexture = "solid",
            borderExtendTop = 0, borderExtendBottom = 0, borderExtendLeft = 0, borderExtendRight = 0,  -- border host is bar + icon
            edgeSep = false, edgeSepY = 0, edgeSepArt = "match",  -- Bottom Separator (Border Options cog)
            iconDividerArt = false,  -- Border Art Divider (Spell Icon Settings cog)
            bgR           = 0, bgG = 0, bgB = 0, bgA = 0.7,
            showTimer     = true,
            timerSize     = 11,
            timerX        = 0,
            timerY        = 0,
            timerSide     = "right",  -- "left" | "right" (duration position; "None" = showTimer false)
            timerR = 1, timerG = 1, timerB = 1, timerA = 1,  -- Duration Text colour (white = untinted)
            showSpellText = true,
            showSpellRank = false,
            spellTextSize = 11,
            spellTextX    = 0,
            spellTextY    = 0,
            spellTextSide = "left",   -- "left" | "right" | "center" (spell text position; "None" = showSpellText false)
            spellTextR = 1, spellTextG = 1, spellTextB = 1, spellTextA = 1,  -- Spell Text colour (white = untinted)
            unlockPos     = nil,
            showChannelTicks  = true,
            showTickMarks     = true,
            tickMarksR = 1.0, tickMarksG = 1.0, tickMarksB = 1.0, tickMarksA = 0.7,
            showLastTick      = false,
            lastTickR = 1.0, lastTickG = 0.82, lastTickB = 0.0, lastTickA = 0.95,
            showGCDBoundary   = false,
            gcdBoundaryR = 1.0, gcdBoundaryG = 0.82, gcdBoundaryB = 0.0, gcdBoundaryA = 0.95,
            coloredEmpowerStages = false,  -- Color empowered spells from red to green per stage
            outOfRangeGray = false,  -- Gray fill while the target is out of the cast's range
            channelOverride = false,  -- Own fill color for channeled spells
            channelR = 0.3, channelG = 0.8, channelB = 0.3,
            uninterruptibleOverride = false,  -- Own fill color for casts that cannot be interrupted
            uninterruptibleR = 0.5, uninterruptibleG = 0.5, uninterruptibleB = 0.5,
            showTotalDuration = false,
            latencyEnabled    = false,
            latencyShowText   = false,
            latencyR = 0.835, latencyG = 0.290, latencyB = 0.290, latencyA = 1.0,
        },
        gcdBar = {
            enabled       = false,
            width         = 220,
            height        = 12,
            anchorX       = 0,
            anchorY       = -78,  -- below the cast bar's default (-54); matches reset/clear
            orientation   = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL_UP","VERTICAL_DOWN"
            classColored  = false,
            fillR         = 0.267, fillG = 0.729, fillB = 0.898, fillA = 1,
            gradientEnabled = false,
            gradientR     = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
            gradientDir   = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL"
            texture       = "none",
            textureBg     = false,  -- Textured Background (Texture Settings cog)
            showSpark     = false,
            depleteFill   = false,  -- start full and deplete instead of filling up
            borderSize    = 1,
            borderR       = 0, borderG = 0, borderB = 0, borderA = 1,
            borderTexture = "solid",
            borderExtendTop = 0, borderExtendBottom = 0, borderExtendLeft = 0, borderExtendRight = 0,
            edgeSep = false, edgeSepY = 0, edgeSepArt = "match",  -- Bottom Separator (Border Options cog)
            bgR           = 0, bgG = 0, bgB = 0, bgA = 0.7,
            frameStrata   = "MEDIUM",
            instanceOnly  = false,
            instantOnly   = false,
            alwaysShow    = false,
            unlockPos     = nil,
        },
        -- WoW Forever swing timer (EUI_ResourceBars_SwingTimer.lua): one row per
        -- weapon slot that can swing (Main Hand / Off Hand / Ranged), driven by the
        -- client's native PLAYER_SWING event. Flat colour keys per module
        -- convention; OFF by default, and nothing is built or registered until it
        -- is turned on. Ignored entirely on clients without C_SwingTimer.
        swingTimer = {
            enabled       = false,
            width         = 220,
            height        = 12,      -- per row
            rowSpacing    = 2,
            anchorX       = 0,
            anchorY       = -130,
            classColored  = false,
            mhR = 0.898, mhG = 0.702, mhB = 0.267, mhA = 1,   -- Main Hand
            ohR = 0.898, ohG = 0.451, ohB = 0.267, ohA = 1,   -- Off Hand
            rR  = 0.267, rG  = 0.729, rB  = 0.898, rA  = 1,   -- Ranged
            gradientEnabled = false,
            gradientR     = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
            gradientDir   = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL"
            texture       = "none",
            showSpark     = false,
            sparkWidth    = 8,
            sparkOverhang = 0,      -- how far the spark reaches past the bar's top and bottom
            -- Spark colours (mhSparkR/G/B/A, ohSpark.., rSpark..) are unset by default:
            -- white, and a combined off hand's spark its fill colour.
            depleteFill   = true,   -- start full and deplete instead of filling up
            idleShowFill  = nil,    -- true = idle row sits full of its fill colour
            hideWhenIdle  = false,  -- hide the whole bar while no swing is running
            showTime      = true,   -- remaining seconds on each row
            showLabel     = true,   -- MH / OH / R tag on each row
            showMH        = true,   -- per-row toggles (a row also needs a weapon in the slot)
            showOH        = true,
            showR         = true,
            alwaysShowRows = false, -- true = every row whose toggle is on shows, with or without a weapon in the slot
            hideLabelNoWeapon = false, -- true = with Always Show Rows, a row with no weapon in its slot shows no label
            shieldRow     = false, -- true = an equipped shield shows the Off Hand row, labelled Shield
            queueMainHandOnly = false, -- true = a queued attack shows on the Main Hand row only
            combineHands  = false,  -- off hand as a spark on the Main Hand bar instead of its own row
            textSize      = 11,
            rangeCheck    = true,   -- dim rows whose target is out of auto-attack range
            outOfRangeAlpha = 0.4,
            -- Attack State: "off" | "queued" (melee rows take the queued attack's colour + name)
            -- | "full" (also On while the attack is on, Waiting while it is on with nothing swinging)
            attackState   = "queued",
            queueR = 1, queueG = 0.70, queueB = 0.20, queueA = 1,   -- Queued: shared fallback for Heroic Strike / Maul / Raptor Strike
            -- Per-attack colours (queueHSR/G/B/A, queueRaptor..., queueMaul...) are unset by default: they inherit the shared Queued colour above.
            queueCleaveR = 0.95, queueCleaveG = 0.35, queueCleaveB = 0.25, queueCleaveA = 1,   -- Queued: Cleave
            activeR = 0.047, activeG = 0.824, activeB = 0.616, activeA = 1,   -- On: EUI teal #0CD29D
            pendingR = 0.659, pendingG = 0.502, pendingB = 0.949, pendingA = 1,   -- Waiting: violet #A880F2
            -- Movement Guide: "off" | "segments" | "windup". GO (the last latency of each swing) on
            -- every row; STILL (the 0.5s a wand / Auto Shot needs the player still, latency earlier)
            -- on their Ranged row, as a segment or its own fill. Smooths swing timing while on.
            moveGuide     = "off",
            moveCue       = false,  -- the Ranged row's time reads Move x.x / Still / Go
            latencyR = 0.949, latencyG = 0.957, latencyB = 0.969, latencyA = 0.9,   -- GO: white
            aimR = 1, aimG = 0.82, aimB = 0.25, aimA = 0.6,   -- STILL: amber, translucent so the fill shows through
            borderSize    = 1,
            borderR       = 0, borderG = 0, borderB = 0, borderA = 1,
            borderTexture = "solid",
            bgR           = 0, bgG = 0, bgB = 0, bgA = 0.7,
            frameStrata   = "MEDIUM",
            visibility    = "in_combat",   -- swing_timer_visibility_in_combat_v1 moves old "always" profiles
            visHideHousing = false,
            visOnlyInstances = false,
            visHideMounted = false,
            visHideDragonriding = false,
            visHideNoTarget = false,
            visHideNoEnemy = false,
            unlockPos     = nil,
        },
        -- Sunfury Arcane Mage Arcane Soul callout (EUI_ResourceBars_ArcaneSoul.lua).
        -- Flat colour keys per module convention; OFF by default, and nothing at
        -- all is built or registered until it is turned on.
        arcaneSoul = {
            enabled     = false,
            threshold   = 5,          -- seconds of Arcane Surge left before "Soul in" shows
            countMode   = "seconds",  -- "seconds" | "gcd" | "secondsGcd" (tenths pre-Soul, GCDs in Soul)
            font        = "__global",
            outlineMode = "__global", -- "__global","none","outline","thick"
            textSize    = 24,
            preR = 0.64, preG = 0.21, preB = 0.93,
            soulR = 0.64, soulG = 0.21, soulB = 0.93,
            lastR = 1.0, lastG = 0.25, lastB = 0.25,
            unlockPos   = nil,
        },
        totemBar = {
            iconSize      = 30,
            spacing       = 2,
            showTimer     = true,
            timerSize     = 11,
            orientation   = "HORIZONTAL",  -- "HORIZONTAL" or "VERTICAL"
            borderSize    = 1,
            borderR       = 0, borderG = 0, borderB = 0, borderA = 1,
            borderTexture = "solid",
            unlockPos     = nil,
            enabledClasses = nil,  -- nil = disabled; { SHAMAN = true, ... } = enabled for listed classes
        },
        -- WoW Forever: Blizzard's call totem bar in the Totem Bar look
        -- (EUI_ResourceBars_CallTotemBar.lua). Off by default; the table exists
        -- only on that client, so retail profiles never gain the key.
        callTotemBar = (EllesmereUI.IS_FOREVER == true) and {
            enabled       = false,
            iconSize      = 30,
            spacing       = 2,
            showTimer     = true,
            timerSize     = 11,
            orientation   = "HORIZONTAL",  -- "HORIZONTAL" or "VERTICAL"
            borderSize    = 1,
            borderR       = 0, borderG = 0, borderB = 0, borderA = 1,
            borderTexture = "solid",
            unlockPos     = nil,
        } or nil,
        general = {
            anchorX     = 0,
            anchorY     = -100,
            orientation = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL_UP","VERTICAL_DOWN"
            barTexture  = "none",
            barTextureBg = false,  -- Textured Background (Texture cog)
            -- Classic WoW UI: one frame round the resource bars as a group,
            -- with a separator line (physical pixels, 0 = none) between bars.
            classicBorderAll = false,
            classicBorderAllSepSize = 1,
            classicBorderAllSepR = 0, classicBorderAllSepG = 0, classicBorderAllSepB = 0,
        },
    },
}

I.DEFAULTS = DEFAULTS
I.broken = false
