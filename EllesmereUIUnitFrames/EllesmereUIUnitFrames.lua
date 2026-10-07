if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local GetSpecialization = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
local addonName, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.NewCombatQueue) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS[addonName] = ns  -- LOD options files read this module ns via the registry

local math_floor, math_ceil, math_max, math_min, math_abs =
    math.floor, math.ceil, math.max, math.min, math.abs
local string_format = string.format
local issecretvalue = issecretvalue
-- WoW Forever: no number under 10,000 abbreviates (EllesmereUI_NumberFormat.lua).
-- Also on ns for the options preview, whose builder is near its upvalue cap.
local AbbreviateNumbers = (EllesmereUI.IS_FOREVER and EllesmereUI.ForeverAbbreviateNumbers) or AbbreviateNumbers
ns.AbbreviateNumbers = AbbreviateNumbers

local PP = EllesmereUI.PP

-- "Run once after combat" for the combat-gated deferrals of this addon (all files).
-- The frame is created in the main chunk, so drained work bills UnitFrames. Keys are
-- per purpose; PlayerAuraBars prefixes its own with "PAB:".
ns.CombatQueue = EllesmereUI.NewCombatQueue(CreateFrame("Frame"))

-- Taint-safe DisableBlizzard override. Stock lib reparents inline via a SetParent
-- hooksecurefunc; Edit Mode's layout pass calls SetParent on managed containers
-- (BossTargetFrameContainer->UIParent) every enter/exit, so that inline reparent runs
-- in Blizzard's secure execution and taints secret-value reads (CompactUnitFrame
-- compares, encounter warnings, SecureUtil arithmetic), poisoning party frames for the
-- session. Fix: defer reparent to a timer and postpone while Edit Mode is open (SetParent
-- runs synchronous layout handlers in the caller's context). Unlisted units use stock.
do
    local hiddenParent = CreateFrame("Frame", nil, UIParent)
    hiddenParent:Hide()
    local pendingParent, looseFrames, hookedFrames = {}, {}, {}
    local bossHandled = false

    -- Combat fallback: protected frames can't reparent in lockdown; park here, sweep at regen (mirrors stock lib).
    local SweepLooseFrames
    SweepLooseFrames = function()
        if InCombatLockdown() then
            ns.CombatQueue.Defer("HiddenParentSweep", SweepLooseFrames)
            return
        end
        for f in pairs(looseFrames) do f:SetParent(hiddenParent) end
        wipe(looseFrames)
    end

    local function ApplyHiddenParent(frame)
        pendingParent[frame] = nil
        if frame:GetParent() == hiddenParent then return end
        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
            pendingParent[frame] = true
            C_Timer.After(0.25, function() ApplyHiddenParent(frame) end)
        elseif InCombatLockdown() and frame:IsProtected() then
            looseFrames[frame] = true
            ns.CombatQueue.Defer("HiddenParentSweep", SweepLooseFrames)
        else
            frame:SetParent(hiddenParent)
        end
    end

    local function Unreg(child)
        if child then child:UnregisterAllEvents() end
    end

    local function HandleFrame(frame, doNotReparent)
        if type(frame) == "string" then frame = _G[frame] end
        if not frame then return end
        frame:UnregisterAllEvents()
        frame:Hide()
        if not doNotReparent then
            frame:SetParent(hiddenParent)
            if not hookedFrames[frame] then
                hookedFrames[frame] = true
                hooksecurefunc(frame, "SetParent", function(self, parent)
                    if parent ~= hiddenParent and not pendingParent[self] then
                        pendingParent[self] = true
                        C_Timer.After(0, function() ApplyHiddenParent(self) end)
                    end
                end)
            end
        end
        Unreg(frame.healthBar or frame.healthbar or frame.HealthBar
            or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar))
        Unreg(frame.manabar or frame.ManaBar)
        Unreg(frame.castBar or frame.spellbar or frame.CastingBarFrame)
        Unreg(frame.powerBarAlt or frame.PowerBarAlt)
        Unreg(frame.BuffFrame or frame.AurasFrame)
        Unreg(frame.petFrame or frame.PetFrame)
        Unreg(frame.totFrame)
        Unreg(frame.CcRemoverFrame)
        Unreg(frame.DebuffFrame)
    end

    -- Standalone Midnight player alt-power bars live under PlayerFrameAlternatePowerBarArea
    -- (a PlayerFrame child), so reparenting PlayerFrame makes them descendants of an
    -- insecure frame. 12.1 build 68824 made aura access a hard-error API (RequiresUnitAuraAccess): these bars
    -- self-register power/spec/PEW events (independent of PlayerFrame's now-dead ones) and
    -- drive AttachBarToUnitUI -> PlayerFrame_OnAlternatePowerBarEnabled -> PlayerFrame_ToPlayerArt
    -- -> BuffFrame:Update() -> GetAuraSlots, throwing "Auras cannot be accessed when secret
    -- while tainted". Fix: unregister events only (taint-clean, combat-legal) -- do NOT
    -- reparent (Edit-Mode-managed; risks the same taint the timers avoid). Globals may be
    -- absent on some clients; Unreg nil-guards each.
    local ALT_POWER_BARS = {
        "AlternatePowerBar", "MonkStaggerBar",
        "EvokerEbonMightBar", "DemonHunterSoulFragmentsBar",
    }
    local function DisableAltPowerBars()
        for i = 1, #ALT_POWER_BARS do
            Unreg(_G[ALT_POWER_BARS[i]])
        end
    end

    -- One Blizzard frame on its own, the same treatment (Forever's classic
    -- ComboFrame, see InitializeFrames).
    ns.UF_HideBlizzardFrame = HandleFrame

    function ns.UF_HideBlizzard(unit)
        if not unit then return end
        if unit == "player" then
            HandleFrame(PlayerFrame)
            DisableAltPowerBars()
        elseif unit == "pet" then
            HandleFrame(PetFrame)
        elseif unit == "target" then
            HandleFrame(TargetFrame)
        elseif unit == "focus" then
            HandleFrame(FocusFrame)
        elseif unit:match("boss%d?$") then
            if not bossHandled then
                bossHandled = true
                -- Container is reparented (Edit Mode can revive it); individual boss frames are
                -- container-managed and must NOT be reparented or layout code breaks their sizes.
                HandleFrame(BossTargetFrameContainer)
                for i = 1, (_G.MAX_BOSS_FRAMES or 5) do
                    HandleFrame("Boss" .. i .. "TargetFrame", true)
                end
            end
        end
        -- Unmapped units (tot/fot ride their parents' children) are no-ops.
    end
end

-- Per-addon border texture defaults (size key = borderSize 0-4)
EllesmereUI.RegisterBorderDefaults("unitframes", EllesmereUI.BORDER_DEFAULTS_FRAMES)


-- Portrait UNIT_MODEL_CHANGED on eventless frames (TargetTarget) triggers UnitIsUnit,
-- which returns secret booleans in protected instances; we unregister that event after
-- oUF sets up eventless frames instead of patching the global. See PostCreateTargetTarget.

-- External lookup for portrait side per frame (writing custom props onto oUF frames would taint their secure execution chain).
EllesmereUI._ufPortraitSide = EllesmereUI._ufPortraitSide or setmetatable({}, { __mode = "k" })

local db
local defaults = {
    profile = {
        playerAuraBars = {
            -- Stock styles (Global Settings > Style): the stock aura borders
            -- on every bar. Reload-gated; read once per session (ns.PAB_Style).
            useBlizzardStyle = false,
            useClassicStyle = false,
            iconSize = 32,
            showText = true,
            durationPosition = "CENTER",
            durationTextSize = 11,
            durationOffsetX = 0,
            durationOffsetY = 0,
            stackPosition = "BOTTOMRIGHT",
            stackTextSize = 11,
            stackOffsetX = 0,
            stackOffsetY = 0,
            buffIconZoom = 0.055,
            debuffIconZoom = 0.055,
            buffBorderSize = 1,
            debuffBorderSize = 1,
            buffBorderR = 0, buffBorderG = 0, buffBorderB = 0, buffBorderA = 1,
            debuffBorderR = 0, debuffBorderG = 0, debuffBorderB = 0, debuffBorderA = 1,
            dispelColorMagic = { r = 0.349, g = 0.475, b = 1.0 },
            dispelColorCurse = { r = 0.636, g = 0.0, b = 0.64 },
            dispelColorDisease = { r = 0.671, g = 0.384, b = 0.098 },
            dispelColorPoison = { r = 0.0, g = 0.706, b = 0.286 },
            dispelColorBleed = { r = 0.75, g = 0.15, b = 0.15 },
            paddingBuffs = 5,
            paddingDebuffs = 5,
            iconsPerRowBuffs = 11,
            iconsPerRowDebuffs = 8,
            maxRowsBuffs = 3,
            maxRowsDebuffs = 2,
            maxBuffs = 32,
            maxDebuffs = 16,
        },
        -- No playerAuras/externalDefensives defaults: those keys are one-time migration
        -- SOURCES read from a saved profile (EllesmereUIUnitFrames_PlayerAuraBars.lua
        -- MigratePlayerAuraStyle/MigrateExternalDefensives), independent of this table --
        -- a new profile has nothing to migrate and starts at PAB's fallbacks.
        castbarOpacity = 1.0,
        castbarColor = { r = 0.114, g = 0.655, b = 0.514 },
        portraitMode = "2d",
        portraitStyle = "attached",
        healthBarTexture = "none",
        -- Cast bars follow the health bar texture ("inherit") unless this
        -- names one of their own ("blizzard" = the vanilla cast fill).
        castBarTexture = "inherit",
        darkTheme = false,
        -- One decimal on abbreviated values (240.5k) and percents (77.3%); global, read by text tags via _G flags.
        showDecimalOnText = false,
        -- With decimals on, boss frames use two (240.55k / 77.30%); inline cog on "Show Decimal on Health Text".
        showDecimalBoss2 = true,
        -- With decimals on, "Only Show for % Health" keeps the decimal on PERCENT (77.3%) but leaves VALUES whole (240k); same inline cog.
        showDecimalPercentOnly = false,
        -- With decimals on, "Hide Trailing Zeros" drops a zero decimal from the PERCENT (100.0% -> 100%, 99.5% unchanged); same inline cog.
        showDecimalTrimZeros = false,
        -- Player Threat (Non-Tank): additive "Shadow" border on the PLAYER frame while
        -- pulling/holding aggro, instanced content only; global, default off (zero cost
        -- until enabled). Colors mirror the nameplate non-tank threat defaults (has/near aggro).
        playerThreatBorderEnabled  = false,
        playerThreatHasAggroColor  = { r = 1.00, g = 0.50, b = 0.00 },
        playerThreatNearAggroColor = { r = 0.81, g = 0.72, b = 0.19 },
        -- Threat % text on the target and focus frames (WoW Forever only).
        threatPctEnabled  = false,
        threatPctFocus    = false,
        threatPctPosition = "CENTER",
        threatPctColorByThreat = true,
        threatPctSize     = 12,
        threatPctXOffset  = 0,
        threatPctYOffset  = 0,
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
            manaRegenSpark = false,  -- WoW Forever: mana regen spark while the bar shows mana; manaRegenSparkMode "ticks" = Regen Ticks, nil = 5-Second Rule
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
            auraBorderTexture = "solid",
            auraBorderSize = 1,
            auraBorderR = 0, auraBorderG = 0, auraBorderB = 0, auraBorderA = 1,
            auraBorderBehind = false,
            auraBorderBehindUnitFrame = false,
            -- Textured Dispel Ring: the dispel ring drawn in the aura border's art.
            auraBorderDispelTextured = false,
            buffShowCooldownText = false,
            buffCooldownTextSize = 10,
            debuffAnchor = "none",
            debuffGrowth = "auto",
            maxDebuffs = 10,
            debuffSize = 22,
            debuffOffsetX = 0,
            debuffOffsetY = 0,
            -- Use Dispel Colors: Dispel Type Borders tinted from the Dispel Colors palette.
            debuffDispelUsePalette = false,
            debuffShowCooldownText = false,
            debuffCooldownTextSize = 10,
            namePosition = "left",
            healthTextPosition = "right",
            leftTextContent = "name",
            rightTextContent = (EllesmereUI.IS_FOREVER == true) and "perhp" or "both",  -- WoW Forever: Health % (retail: Health # | %)
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
            portraitNonPlayer = "2d",
            classThemeStyle = "modern",
            portraitSide = "left",
            portraitSize = 0,
            portraitX = 0,
            portraitY = 0,
            portraitMirror = false,
            detachedPortraitShape = "portrait",
            detachedPortraitBorderColor = { r = 0, g = 0, b = 0 },
            detachedPortraitClassColor = true,
            detachedPortraitBorder = true,
            detachedPortraitBorderOpacity = 100,
            detachedPortraitBorderSize = 7,
            detachedPortraitUnitColorDark = false,
            detachedPortraitOuterRing = "none",
            detachedPortraitInnerShadow = false,
            -- Portrait Dragon (Player Frame Dragon): read through ns.UF_DragonSettings.
            detachedPortraitWinglessDragon = false,
            detachedPortraitWinglessDragonClassColor = false,
            detachedPortraitWinglessDragonScale = 100,
            detachedPortraitWinglessDragonX = 0,
            detachedPortraitWinglessDragonY = 0,
            detachedPortraitWinglessDragonFlip = false,
            detachedPortraitWinglessDragonStrata = "inherit",
            detachedPortraitWinglessDragonLevel = 2,
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
            -- Blizzard Glow Line (opt-in) and its art: "blizzard" | "pixelsGlow" | "pixelsOvershield".
            absorbGlowLine = false,
            absorbGlowLineTexture = "blizzard",
            showPlayerCastbar = false,
            -- Global Settings > Gamepad: stand this cast bar down while a
            -- controller is connected (ns.UF_ApplyGamepadCastbar).
            castbarGamepadHide = false,
            showPlayerCastIcon = true,
            playerCastbarIconInWidth = true,
            castReverseFill = false,
            castFillOpacity = 100,  -- 0-100; below 100 the world shows through the fill
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
            -- Player-only: the spell target never rendered here before the
            -- display fix, so it defaults OFF to keep the frame unchanged;
            -- users opt in via the Spell Target side dropdown. Existing
            -- profiles are pinned to None by uf_player_cast_target_none_v1.
            showCastTarget = false,
            castbarFillColor = { r = 0.863, g = 0.820, b = 0.639 },
            castbarClassColored = false,
            -- Cast Icon cog "Show Icon on Portrait" (opt-in).
            playerCastbarIconOnPortrait = false,
            -- Cast Bar cog "Custom Border Style" (opt-in). The border keys are
            -- read only while it is on; castBorderOffsetX/Y and
            -- castBorderShiftX/Y (nil = the style's default) and the exact
            -- size castBorderSizePx are never seeded.
            castBorderCustom = false,
            castBorderStyle = "solid",
            castBorderSize = 1,
            castBorderColor = { r = 0, g = 0, b = 0 },
            castBorderAlpha = 1,
            castBorderBehind = false,
            -- WoW Forever: the class resource is ON (modern pips above the health
            -- bar, 16) because the client's own combo point art is stood down
            -- there (Forever combo points belong to the target and Blizzard's
            -- classic ComboFrame cannot follow our target frame); the 8 default
            -- lands at a 3px sliver. Per-client defaults, never seeded.
            showClassPowerBar = (EllesmereUI.IS_FOREVER == true) and true or false,
            lockClassPowerToFrame = true,
            classPowerStyle = (EllesmereUI.IS_FOREVER == true) and "modern" or "none",
            classPowerPosition = (EllesmereUI.IS_FOREVER == true) and "above" or "top",
            classPowerBarX = 0,
            classPowerBarY = 0,
            classPowerSize = (EllesmereUI.IS_FOREVER == true) and 16 or 8,
            classPowerSpacing = 2,
            classPowerClassColor = true,
            classPowerCustomColor = { r = 1, g = 0.82, b = 0 },
            classPowerBgColor = { r = 0.082, g = 0.082, b = 0.082, a = 1.0 },
            classPowerEmptyColor = { r = 0.2, g = 0.2, b = 0.2, a = 1.0 },
            -- WoW Forever: where the WoW Forever style's "Blizzard" class
            -- resource (the combo point arc) shows -- "target" (the stock
            -- spot), "player" or "never". Player only; nil on every other
            -- client.
            foreverComboLocation = (EllesmereUI.IS_FOREVER == true) and "target" or nil,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            borderTexture = "solid",
            borderPowerSeam = false,  -- Border Options cog "Power Bar Seam" (opt-in)
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
            showWhenHealthMissing = false,
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
            leaderIndicatorStyle = "blizzard",  -- "blizzard" | "pixels"
            factionIndicatorMode = "off",
            factionIndicatorStyle = "pvp",
            factionIndicatorPvP = "only",
            factionIndicatorSize = 18,
            factionIndicatorPosition = "topright",
            factionIndicatorX = 0,
            factionIndicatorY = 0,
            healthReverseFill = false,
            healthVerticalFill = false,
            smoothBars = false,
            powerReverseFill = false,
        },
        target = {
            frameWidth = 181,
            -- Combat indicator: same option set as the player frame but opt-in
            -- ("none" until the user picks a style).
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
            castCombineNameTarget = false,  -- render "Spell Name - Target" as one string in the target slot
            castReverseFill = false,
            castFillOpacity = 100,  -- 0-100; below 100 the world shows through the fill
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
            castbarImportantGlow = false,
            castbarImportantGlowStyle = 1,
            castbarImportantGlowColor = { r = 1, g = 0.2, b = 0.2 },
            castbarImportantGlowLines = 8,
            castbarImportantGlowThickness = 2,
            castbarImportantGlowSpeed = 4,
            castbarClassColored = false,
            -- Cast Icon cog "Show Icon on Portrait" (opt-in).
            castbarIconOnPortrait = false,
            -- Cast Bar cog "Custom Border Style" (opt-in); see the player block.
            castBorderCustom = false,
            castBorderStyle = "solid",
            castBorderSize = 1,
            castBorderColor = { r = 0, g = 0, b = 0 },
            castBorderAlpha = 1,
            castBorderBehind = false,
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
            auraBorderTexture = "solid",
            auraBorderSize = 1,
            auraBorderR = 0, auraBorderG = 0, auraBorderB = 0, auraBorderA = 1,
            auraBorderBehind = false,
            auraBorderBehindUnitFrame = false,
            -- Textured Dispel Ring: the dispel ring drawn in the aura border's art.
            auraBorderDispelTextured = false,
            buffShowCooldownText = false,
            buffCooldownTextSize = 10,
            debuffSize = 22,
            debuffOffsetX = 0,
            debuffOffsetY = 0,
            debuffShowCooldownText = false,
            debuffCooldownTextSize = 10,
            namePosition = "left",
            healthTextPosition = "right",
            -- WoW Forever shows level and name on the left (retail: name only).
            leftTextContent = (EllesmereUI.IS_FOREVER == true) and "levelname" or "name",
            rightTextContent = (EllesmereUI.IS_FOREVER == true) and "perhp" or "both",  -- WoW Forever: Health % (retail: Health # | %)
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
            portraitNonPlayer = "2d",
            classThemeStyle = "modern",
            portraitSide = "right",
            portraitSize = 0,
            portraitX = 0,
            portraitY = 0,
            portraitMirror = false,
            detachedPortraitShape = "portrait",
            detachedPortraitBorderColor = { r = 0, g = 0, b = 0 },
            detachedPortraitClassColor = true,
            detachedPortraitBorder = true,
            detachedPortraitBorderOpacity = 100,
            detachedPortraitBorderSize = 7,
            detachedPortraitUnitColorDark = false,
            detachedPortraitOuterRing = "none",
            detachedPortraitInnerShadow = false,
            -- Portrait Dragon (Elite Enemy Dragon): read through ns.UF_DragonSettings.
            detachedPortraitWinglessDragon = false,
            detachedPortraitWinglessDragonClassColor = false,
            detachedPortraitWinglessDragonScale = 100,
            detachedPortraitWinglessDragonX = 0,
            detachedPortraitWinglessDragonY = 0,
            detachedPortraitWinglessDragonFlip = false,
            detachedPortraitWinglessDragonStrata = "inherit",
            detachedPortraitWinglessDragonLevel = 2,
            detachedPortraitWinglessDragonInstances = false,
            healthBarOpacity = 90,
            powerBarOpacity = 100,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            borderTexture = "solid",
            borderPowerSeam = false,  -- Border Options cog "Power Bar Seam" (opt-in)
            highlightColor = { r = 1, g = 1, b = 1 },
            textSize = 12,
            showInRaid = true,
            showInParty = true,
            showSolo = true,
            barVisibility = "always",
            showWhenHealthMissing = false,
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
            leaderIndicatorStyle = "blizzard",  -- "blizzard" | "pixels"
            eliteIndicatorEnabled = false,
            eliteIndicatorSize = 16,
            eliteIndicatorPosition = "topleft",
            eliteIndicatorX = 0,
            eliteIndicatorY = 0,
            eliteIndicatorShowInInstances = false,
            eliteIndicatorStyle = "badge",  -- "badge" | "pixelsDragon"
            -- A saved "wingless" style and these five keys read as the Portrait
            -- Dragon (ns.UF_DragonSettings) until a setter pins them over.
            eliteIndicatorWinglessClassColor = false,
            eliteIndicatorWinglessScale = 100,
            eliteIndicatorWinglessFlip = false,
            eliteIndicatorWinglessStrata = "inherit",
            eliteIndicatorWinglessLevel = 1,
            factionIndicatorMode = "off",
            factionIndicatorStyle = "pvp",
            factionIndicatorPlayersOnly = false,
            factionIndicatorPvP = "dim",
            factionIndicatorSize = 18,
            factionIndicatorPosition = "topright",
            factionIndicatorX = 0,
            factionIndicatorY = 0,
            healthReverseFill = false,
            healthVerticalFill = false,
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
            -- Blizzard Glow Line (opt-in) and its art: "blizzard" | "pixelsGlow" | "pixelsOvershield".
            absorbGlowLine = false,
            absorbGlowLineTexture = "blizzard",
            showPlayerCastbar = false,
            showClassPowerBar = false,
            classPowerBarX = 0,
            classPowerBarY = 0,
            playerCastbarX = 0,
            playerCastbarY = 0,
            playerCastbarWidth = 181,
            playerCastbarHeight = 14,
            healthReverseFill = false,
            healthVerticalFill = false,
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
            portraitNonPlayer = "2d",
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
            healthVerticalFill = false,
            smoothBars = false,
        },
        -- Focus Target: independent clone of Target of Target defaults. MUST stay
        -- byte-identical to the targettarget block above (old shared totPet migrates
        -- into BOTH tables); StripDefaults/DeepMergeDefaults rely on the match.
        focustarget = {
            frameWidth = 101,
            healthHeight = 25,
            healthClassColored = false,
            customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
            bgClassColored = false,
            showPortrait = false,
            portraitSide = "left",
            portraitMode = "2d",
            portraitNonPlayer = "2d",
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
            healthVerticalFill = false,
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
            portraitNonPlayer = "2d",
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
            -- WoW Forever pets have power (hunter pet focus, warlock pet mana), so
            -- the pet frame carries a power bar there (retail: none).
            powerPosition = (EllesmereUI.IS_FOREVER == true) and "below" or "none",
            powerHeight = 6,
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
            powerBarOpacity = 100,
            powerReverseFill = false,
            -- Pet happiness icon (WoW Forever hunter pets).
            happinessEnabled = true,
            happinessSize = 20,
            happinessAlign = "right",
            happinessX = 0,
            happinessY = 0,
            healthReverseFill = false,
            healthVerticalFill = false,
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
            castCombineNameTarget = false,  -- render "Spell Name - Target" as one string in the target slot
            castReverseFill = false,
            castFillOpacity = 100,  -- 0-100; below 100 the world shows through the fill
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
            castbarImportantGlow = false,
            castbarImportantGlowStyle = 1,
            castbarImportantGlowColor = { r = 1, g = 0.2, b = 0.2 },
            castbarImportantGlowLines = 8,
            castbarImportantGlowThickness = 2,
            castbarImportantGlowSpeed = 4,
            castbarClassColored = false,
            -- Cast Icon cog "Show Icon on Portrait" (opt-in).
            castbarIconOnPortrait = false,
            -- Cast Bar cog "Custom Border Style" (opt-in); see the player block.
            castBorderCustom = false,
            castBorderStyle = "solid",
            castBorderSize = 1,
            castBorderColor = { r = 0, g = 0, b = 0 },
            castBorderAlpha = 1,
            castBorderBehind = false,
            healthDisplay = "perhp",
            -- WoW Forever shows level and name on the left (retail: name only).
            leftTextContent = (EllesmereUI.IS_FOREVER == true) and "levelname" or "name",
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
            portraitNonPlayer = "2d",
            classThemeStyle = "modern",
            portraitSide = "right",
            portraitSize = 0,
            portraitX = 0,
            portraitY = 0,
            portraitMirror = false,
            detachedPortraitShape = "portrait",
            detachedPortraitBorderColor = { r = 0, g = 0, b = 0 },
            detachedPortraitClassColor = true,
            detachedPortraitBorder = true,
            detachedPortraitBorderOpacity = 100,
            detachedPortraitBorderSize = 7,
            detachedPortraitUnitColorDark = false,
            detachedPortraitOuterRing = "none",
            detachedPortraitInnerShadow = false,
            -- Portrait Dragon (Elite Enemy Dragon): read through ns.UF_DragonSettings.
            detachedPortraitWinglessDragon = false,
            detachedPortraitWinglessDragonClassColor = false,
            detachedPortraitWinglessDragonScale = 100,
            detachedPortraitWinglessDragonX = 0,
            detachedPortraitWinglessDragonY = 0,
            detachedPortraitWinglessDragonFlip = false,
            detachedPortraitWinglessDragonStrata = "inherit",
            detachedPortraitWinglessDragonLevel = 2,
            detachedPortraitWinglessDragonInstances = false,
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
            -- Blizzard Glow Line (opt-in) and its art: "blizzard" | "pixelsGlow" | "pixelsOvershield".
            absorbGlowLine = false,
            absorbGlowLineTexture = "blizzard",
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
            auraBorderTexture = "solid",
            auraBorderSize = 1,
            auraBorderR = 0, auraBorderG = 0, auraBorderB = 0, auraBorderA = 1,
            auraBorderBehind = false,
            auraBorderBehindUnitFrame = false,
            auraBorderDispelTextured = false,
            debuffSize = 22,
            debuffOffsetX = 0,
            debuffOffsetY = 0,
            textSize = 12,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            borderTexture = "solid",
            borderPowerSeam = false,  -- Border Options cog "Power Bar Seam" (opt-in)
            highlightColor = { r = 1, g = 1, b = 1 },
            showInRaid = true,
            showInParty = true,
            showSolo = true,
            barVisibility = "always",
            showWhenHealthMissing = false,
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
            healthVerticalFill = false,
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
            castFillOpacity = 100,
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
            castbarInterruptReadyColor = { r = 0.92, g = 0.35, b = 0.20 },
            castbarKickTickEnabled = true,
            castbarInterruptMidCastEnabled = false,
            castbarInterruptMidCastColor = { r = 0.318, g = 0.820, b = 0.357 },
            castbarUninterruptibleColor = { r = 0.5, g = 0.5, b = 0.5 },
            castbarClassColored = false,
            -- Cast Bar cog "Custom Border Style" (opt-in; boss1-5 share it);
            -- see the player block.
            castBorderCustom = false,
            castBorderStyle = "solid",
            castBorderSize = 1,
            castBorderColor = { r = 0, g = 0, b = 0 },
            castBorderAlpha = 1,
            castBorderBehind = false,
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
            auraBorderTexture = "solid",
            auraBorderSize = 1,
            auraBorderR = 0, auraBorderG = 0, auraBorderB = 0, auraBorderA = 1,
            auraBorderBehind = false,
            auraBorderBehindUnitFrame = false,
            simpleBuffShowCooldownText = false,
            simpleBuffCooldownTextSize = 14,
            buffSpacing = 1,
            debuffSpacing = 1,
            simpleBuffSpacing = 1,
            simpleDebuffSpacing = 1,
            textSize = 12,
            extraTextContent = "none",
            extraTextSize = 12,
            extraTextClassColor = false,
            extraTextColorR = 1, extraTextColorG = 1, extraTextColorB = 1,
            extraTextX = 0, extraTextY = 0,
            extraTextAlign = "left",
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
            -- Boss Frames DISPLAY "Border Style": "Inherit (Main Frames)" (false)
            -- wears the mini frame donor's border, as always; any other pick sets
            -- true and the border keys below paint every boss frame
            -- (ns.UF_BossBorderSettings).
            borderCustom = false,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            borderTexture = "solid",
            highlightColor = { r = 1, g = 1, b = 1 },
            -- Boss Hover / Target border recolor (mirrors Raid Frames "Hover
            -- Borders"): recolors the existing border; hover beats target.
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
            healthVerticalFill = false,
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
        -- Per-unit frame source: "eui" (skinned), "blizzard" (leave Blizzard's frame), or
        -- "hidden". Resolved via ns.GetUnitFrameSource, which also honors legacy enabledFrames=false => "hidden".
        frameSource = {},
        -- Stock styles (Global Settings > Style): Blizzard's current unit
        -- frame art or the classic frames, portrait masks and bar placement on
        -- our own frames with every EUI feature intact. Default OFF;
        -- reload-gated; the Classic flag wins when both are set.
        useBlizzardStyle = false,
        useClassicStyle = false,
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
        dispelCustomBorder   = false,    -- Color Custom Borders: the frame border copied in the dispel type color
        showDispelIcons      = false,    -- Type Icon Position: the type's icon on a health bar corner
        dispelIconPosition   = "right",
        dispelIconSize       = 16,
        dispelIconOffsetX    = 0,
        dispelIconOffsetY    = 0,
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

-- Bar gradients reuse two shared color objects to avoid per-call allocation (CreateColor
-- would allocate two tables each time). oUF re-flattens bar color every health/power
-- event so PostUpdateColor must repaint the gradient each time; SetGradient copies
-- values at call time, so one shared pair is safe across all frames.
local _gradColorA = CreateColor(1, 1, 1, 1)
local _gradColorB = CreateColor(1, 1, 1, 1)

local function ApplyBarGradient(ft, dir, br, bg, bb, ba, er, eg, eb, ea)
    ft:SetVertexColor(1, 1, 1, 1)
    _gradColorA:SetRGBA(br, bg, bb, ba)
    _gradColorB:SetRGBA(er, eg, eb, ea)
    ft:SetGradient(dir, _gradColorA, _gradColorB)
end

local SOLID_BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8" }

-- Routes through shared EllesmereUI.GetFontPath("unitFrames"), which already handles
-- glyph-restricted locales (CJK/Cyrillic): keeps a SharedMedia font if it can render the
-- locale's glyphs, else falls back to the system font. Do NOT re-decide locale fallback
-- locally or locale clients could never use a custom font here.
local cachedFontPath = (EllesmereUI.GetFontPath("unitFrames"))
    or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local cachedFontPaths = {}  -- per-unit font cache
local function ResolveFontPath(unitKey)
    local gPath = EllesmereUI.GetFontPath("unitFrames")
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

local function SetFSFont(fs, size, flags)
  EllesmereUI.ApplyModuleFont(fs, GetSelectedFont(), size or 12, "unitFrames", flags)
end

-- Shared cast-bar text anchoring (mirrors the nameplate cast text system). Three
-- elements (spell name, spell target, duration), each on a side. The duration
-- reserves a fixed width slot on its side; a non-center element sharing that side
-- shifts inward by it. Center elements anchor to bar center and never shift.
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

-- WoW does not re-layout a FontString when only SetJustifyH changes; clearing then
-- re-setting the text forces it (must be a real change -- identical text is deduped).
-- GetText may return a secret (cast name/target); SetText accepts secrets untouched.
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
local healthBarTextures, healthBarTextureNames, healthBarTextureOrder =
    EllesmereUI.BuildBarTextureTables(true)
ns.healthBarTextures = healthBarTextures
ns.healthBarTextureOrder = healthBarTextureOrder
ns.healthBarTextureNames = healthBarTextureNames

-- Map a unit ID ("player", "boss1", "targettarget", ...) to its db.profile key.
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
    -- The swap replaced the fill object; re-derive rotation for the bar's axis.
    ns.ApplyFillRotation(health)

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
    -- Blizzard Style: the swaps above replaced the fill objects, so the stock
    -- masks are seated again on the new fills. The textures themselves stay
    -- the user's choice, so every colour renders exactly as picked.
    if frame and frame.Health == health and ns.UF_Blizz() then ns.UF_ApplyBlizzBarArt(frame) end
end

-- Resolve a unit's effective health bar texture KEY. Main frames use their own key
-- (falling back to the global default); mini frames (pet, ToT, focus target, boss)
-- inherit their donor frame's texture (ns.GetMiniDonorSettings) unless their own key is
-- non-nil/non-"inherit". Shared by the live frames and the options preview to match.
ns.ResolveHealthBarTextureKey = function(ownSettings, donorSettings)
    local own = ownSettings and ownSettings.healthBarTexture
    if own and own ~= "inherit" then return own end
    if donorSettings then
        local d = donorSettings.healthBarTexture
        if d and d ~= "inherit" then return d end
    end
    return db.profile.healthBarTexture or "none"
end

-- Cast bars reuse the unit's health bar texture. The cast bar stacks three textures
-- over the fill bounds (base fill + cast tint + shielded tint, all WHITE8X8 by
-- default), so apply to each. On ns to avoid the Lua 200-local cap.
ns.ApplyCastBarTexture = function(castbar, texKey)
    if not castbar then return end
    -- Blizzard Style: the stock cast fill art stays (set by the post-pass).
    if castbar._blizzCast then
        ns.UF_SetBlizzCastFill(castbar, castbar.channeling and "channel" or "cast")
        return
    end
    -- A cast bar texture of its own (the Textures page row) overrides the
    -- health bar's; "inherit" follows the health bar as before.
    local own = db.profile.castBarTexture
    if own and own ~= "inherit" then texKey = own end
    if texKey == "blizzard" then
        -- The "Blizzard" fill: the vanilla cast bar's own texture (the same
        -- entry the Resource Bars cast bar offers), tinted by the bar's
        -- colours like any file; the cast tint rides the same art.
        castbar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local fill = castbar:GetStatusBarTexture()
        if fill then
            fill:SetAtlas("UI-CastingBar-Fill", true)
            fill:SetHorizTile(false)
            UnsnapTex(fill)
        end
        if castbar.castTintLayer then castbar.castTintLayer:SetAtlas("UI-CastingBar-Fill", true) end
        return
    end
    local path = EllesmereUI.ResolveTexturePath(healthBarTextures, texKey or "none", "Interface\\Buttons\\WHITE8X8")
    castbar:SetStatusBarTexture(path)
    local fill = castbar:GetStatusBarTexture()
    if fill then
        fill:SetHorizTile(false)
        UnsnapTex(fill)
    end
    if castbar.castTintLayer then castbar.castTintLayer:SetTexture(path) end
    -- The shield tint keeps its creation WHITE8X8: 12.1 renders the loose
    -- statusbar art BLANK on plain overlay textures (negative synthetic
    -- fileID, healthy alpha/rect/shown readbacks -- measured in-game
    -- 2026-08-12, the invisible-interrupt-shield report), so re-pointing it
    -- at the art killed the shield entirely. A flat wash tints the textured
    -- fill below it; SetAlphaFromBoolean keeps driving it secret-safe.
end

-- Cast bar Fill Opacity (player/target/focus). Below 100 the active-cast tint layer
-- turns translucent via castbar._fillOp (consumed by PostCastStart and the shielded-tint
-- toggle), and the bg texture re-anchors to cover ONLY the empty portion (reverse-fill
-- aware) so the world shows through the fill instead of the bg. The base StatusBar fill
-- under the tint goes to alpha 0 at the SetStatusBarColor call sites so it can't bleed
-- through. Inert at 100 unless previously applied (_fillOpApplied). Value-blind
-- (relational anchors + plain alphas only), so secret cast states render identically.
-- castbar._castTintOn mirrors "the last alpha we wrote to castTintLayer was
-- above zero". It exists because castTintLayer:GetAlpha() cannot be trusted to
-- return a plain number: this castbar also drives _shieldedTint's alpha from
-- the SECRET notInterruptible flag (SetAlphaFromBoolean), and once secrecy is
-- in a castbar's render state an alpha read comes back secret. Comparing that
-- inside our own (tainted) execution throws "attempt to compare a secret number
-- value", which aborts the whole styling pass mid-way and leaves the cast bar
-- unanchored at screen centre. We write every one of these alphas ourselves, so
-- owning the state costs one boolean and removes the comparison entirely.
ns.ApplyCastFillOpacity = function(castbar, settings)
    local op = (settings and settings.castFillOpacity) or 100
    local bgHost = castbar:GetParent()
    local bgTex = bgHost and bgHost._bgTex
    if op >= 100 then
        if castbar._fillOpApplied then
            castbar._fillOpApplied = nil
            castbar._fillOp = nil
            if bgTex then
                bgTex:ClearAllPoints()
                bgTex:SetAllPoints(bgHost)
            end
            -- Mid-cast restore: the tint's active/idle state comes from our own
            -- flag, never from reading the widget back (see _castTintOn).
            if castbar.castTintLayer and castbar._castTintOn then
                castbar.castTintLayer:SetAlpha(1)
            end
        end
        return
    end
    castbar._fillOpApplied = true
    castbar._fillOp = op / 100
    local tex = castbar:GetStatusBarTexture()
    if bgTex and tex then
        bgTex:ClearAllPoints()
        if castbar.GetReverseFill and castbar:GetReverseFill() then
            bgTex:SetPoint("TOPLEFT", bgHost, "TOPLEFT", 0, 0)
            bgTex:SetPoint("BOTTOMRIGHT", tex, "BOTTOMLEFT", 0, 0)
        else
            bgTex:SetPoint("TOPLEFT", tex, "TOPRIGHT", 0, 0)
            bgTex:SetPoint("BOTTOMRIGHT", bgHost, "BOTTOMRIGHT", 0, 0)
        end
    end
    -- Mid-cast application: retune the tint if it is currently active.
    if castbar.castTintLayer and castbar._castTintOn then
        castbar.castTintLayer:SetAlpha(op / 100)
    end
end

-------------------------------------------------------------------------------
--  Health Bar Opacity -- controls the overall alpha of the health bar fill
-------------------------------------------------------------------------------
local function ApplyHealthBarAlpha(health, unitKey)
    if not health then return end
    local s = unitKey and db.profile[unitKey]
    local opacity = s and (s.healthBarOpacity or 90) or 90
    -- Old profiles stored opacity as a 0-1 float instead of a 0-100 int.
    if opacity <= 1.0 then opacity = opacity * 100 end
    local fillA = opacity / 100
    local fillTex = health:GetStatusBarTexture()
    -- With a gradient active the opacity is baked into the gradient endpoints,
    -- so region alpha must stay 1 to avoid double-dimming.
    if fillTex then fillTex:SetAlpha((s and s.gradientEnabled) and 1 or fillA) end
    if health.bg then health.bg:SetAlpha((s and (s.customBgAlpha or 100) or 100) / 100) end
end

-------------------------------------------------------------------------------
--  Power Bar Opacity -- controls the overall alpha of the power bar
-------------------------------------------------------------------------------
-- Power bar analog of AnchorHealthBg, gated on Fill Opacity: below 100 the bg covers
-- ONLY the empty portion (reverse-fill aware) so the translucent fill shows the world.
-- At 100 it returns to full-size only if previously re-anchored (_bgOpAnchored), so
-- untouched profiles never see an anchor write.
ns.AnchorPowerBg = function(power, opacity)
    local bg = power and power.bg
    local tex = power and power.GetStatusBarTexture and power:GetStatusBarTexture()
    if not bg or not tex then return end
    if (opacity or 100) >= 100 then
        if power._bgOpAnchored then
            power._bgOpAnchored = nil
            bg:ClearAllPoints()
            PP.Point(bg, "TOPLEFT", power, "TOPLEFT", 0, 0)
            PP.Point(bg, "BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
        end
        return
    end
    power._bgOpAnchored = true
    bg:ClearAllPoints()
    if power.GetReverseFill and power:GetReverseFill() then
        bg:SetPoint("TOPLEFT", power, "TOPLEFT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", tex, "BOTTOMLEFT", 0, 0)
    else
        bg:SetPoint("TOPLEFT", tex, "TOPRIGHT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
    end
end

local function ApplyPowerBarAlpha(power, unitKey)
    if not power then return end
    local s = unitKey and db.profile[unitKey]
    local opacity = s and (s.powerBarOpacity or 100) or 100
    -- Old profiles stored opacity as a 0-1 float instead of a 0-100 int.
    if opacity <= 1.0 then opacity = opacity * 100 end
    local fillA = opacity / 100
    local fillTex = power:GetStatusBarTexture()
    -- Gradient bakes opacity into its endpoints, so keep region alpha at 1 then.
    if fillTex then fillTex:SetAlpha((s and s.powerGradientEnabled) and 1 or fillA) end
    if power.bg then power.bg:SetAlpha((s and (s.customPowerBgAlpha or 100) or 100) / 100) end
    -- Below 100 the bg retreats to the empty portion so the translucent fill
    -- shows the world (matches the health/cast bar Fill Opacity model).
    ns.AnchorPowerBg(power, opacity)
end

-------------------------------------------------------------------------------
--  Dark Mode -- flat dark health bar with gray background
-------------------------------------------------------------------------------
-- Fallback bg colour (#111) when no class/custom colour source exists. Dark Mode
-- fill/bg come from the global per-profile palette via GetDarkModeFill()/GetDarkModeBg().
local DARK_HEALTH_R, DARK_HEALTH_G, DARK_HEALTH_B = 0x11/255, 0x11/255, 0x11/255  -- #111111

-- Anchor the health bg to cover ONLY the empty (missing-health) portion so reduced
-- fill opacity never reveals the bg behind the filled section. The empty side flips
-- with reverse fill (normal empties RIGHT, reverse empties LEFT) -- anchoring the
-- wrong side collapses the bg to zero width whenever the bar isn't full. Relational
-- anchor, so the edge tracks the fill as health changes.
local function AnchorHealthBg(health)
    local bg = health and health.bg
    local tex = health and health.GetStatusBarTexture and health:GetStatusBarTexture()
    if not bg or not tex then return end
    local reversed = health.GetReverseFill and health:GetReverseFill()
    -- Vertical fill empties at the TOP (BOTTOM when reversed); read the axis off
    -- the bar itself so this needs no settings lookup.
    local vert = health.GetOrientation and health:GetOrientation() == "VERTICAL"
    -- The anchors bind to the fill texture's EDGE, which the engine moves with
    -- every SetValue -- they are live and never need re-pushing per paint
    -- (this ran per health event). Re-anchor only when an actual input moved:
    -- the texture OBJECT (retexture replaces it) or the axis/direction.
    local aKey = (vert and "V" or "H") .. (reversed and "R" or "N")
    if health._bgAnchorTex == tex and health._bgAnchorKey == aKey then
        return
    end
    health._bgAnchorTex = tex
    health._bgAnchorKey = aKey
    bg:ClearAllPoints()
    if vert then
        if reversed then
            bg:SetPoint("TOPLEFT", tex, "BOTTOMLEFT", 0, 0)
            bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
        else
            bg:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
            bg:SetPoint("BOTTOMRIGHT", tex, "TOPRIGHT", 0, 0)
        end
    elseif reversed then
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

-------------------------------------------------------------------------------
--  Health-percent fill colors ("Dynamic Health Color")
--
--  The fill color follows how wounded the unit is: full health reads as one
--  color and bleeds toward another as health drops. Deliberately a PORT of the
--  Raid Frames implementation (GetClassicHealthCurve / GetCustomDynamicCurve /
--  GetClassReactiveCurve there) rather than a fresh model, so a unit frame and
--  a party frame set to the same mode paint the same color at the same health.
--  Keep the two in step if either side's stops or curve shape ever change.
--
--  Secret-value safe by construction: the curve is handed to UnitHealthPercent
--  and evaluated ENGINE-side, so a restricted unit's health never reaches Lua.
--  The returned ColorMixin's channels may themselves be secret -- they are only
--  ever passed to a setter, never inspected or arithmetic'd.
--
--  Per-unit settings (all nil-defaulted, so an untouched profile keeps the
--  existing flat class/custom fill):
--    healthColorMode  "none" | "classic" | "customDynamic" | "classReactive"
--    dynamicColor100 / dynamicColor50 / dynamicColor0   gradient stops
--
--  Wrapped in do/end: the caches are state these functions own, and the block
--  releases its registers at the close so the main chunk pays nothing.
-------------------------------------------------------------------------------
do
    -- Stop defaults, shared with the options page's swatch fallbacks. Same
    -- values the Raid Frames module uses.
    local DEF100 = { r = 0, g = 1, b = 0 }
    local DEF50  = { r = 0xEC/255, g = 0xEC/255, b = 0x32/255 }
    local DEF0   = { r = 0xE3/255, g = 0x30/255, b = 0x30/255 }
    ns.UF_DYN_DEF100, ns.UF_DYN_DEF50, ns.UF_DYN_DEF0 = DEF100, DEF50, DEF0

    -- Classic: red (dead) -> yellow (mid) -> green (full). One curve, forever.
    local classicCurve
    local function GetClassicCurve()
        if classicCurve then return classicCurve end
        local curve = C_CurveUtil.CreateColorCurve()
        curve:SetType(Enum.LuaCurveType.Linear)
        curve:AddPoint(0, CreateColor(1, 0, 0, 1))
        curve:AddPoint(0.5, CreateColor(1, 1, 0, 1))
        curve:AddPoint(1, CreateColor(0, 1, 0, 1))
        classicCurve = curve
        return curve
    end

    -- Custom Dynamic: the Classic path with the unit's three chosen stops.
    -- ONE cached curve keyed by the stop colors, not by unit: unit frames are
    -- repainted one at a time, and a rebuild is only the cost of three AddPoint
    -- calls. Frames configured differently therefore rebuild as they alternate;
    -- that is bounded by the number of DISTINCT palettes in use (nearly always
    -- one), not by the paint rate.
    local dynCurve
    local d0r, d0g, d0b, d50r, d50g, d50b, d100r, d100g, d100b
    local function GetDynamicCurve(s)
        local c0   = s.dynamicColor0   or DEF0
        local c50  = s.dynamicColor50  or DEF50
        local c100 = s.dynamicColor100 or DEF100
        if not (dynCurve
            and d0r   == c0.r   and d0g   == c0.g   and d0b   == c0.b
            and d50r  == c50.r  and d50g  == c50.g  and d50b  == c50.b
            and d100r == c100.r and d100g == c100.g and d100b == c100.b) then
            dynCurve = C_CurveUtil.CreateColorCurve()
            dynCurve:SetType(Enum.LuaCurveType.Linear)
            dynCurve:AddPoint(0,   CreateColor(c0.r,   c0.g,   c0.b,   1))
            dynCurve:AddPoint(0.5, CreateColor(c50.r,  c50.g,  c50.b,  1))
            dynCurve:AddPoint(1,   CreateColor(c100.r, c100.g, c100.b, 1))
            d0r, d0g, d0b       = c0.r, c0.g, c0.b
            d50r, d50g, d50b    = c50.r, c50.g, c50.b
            d100r, d100g, d100b = c100.r, c100.g, c100.b
        end
        return dynCurve
    end

    -- Class Color Reactive: the same gradient whose 100% stop is the unit's
    -- CLASS color, so full health reads as class identity and wounds bleed into
    -- the reactive palette (fully reactive by 40%). Cached per class token; the
    -- fingerprint names every input, so a Custom Class Colors edit rebuilds too.
    local GRAY = { r = 0.5, g = 0.5, b = 0.5 }
    local reactiveCurves = {}   -- classToken -> { curve, r, g, b } (class color used)
    local r0r, r0g, r0b, r50r, r50g, r50b
    local function GetClassReactiveCurve(s, classToken)
        local c0  = s.dynamicColor0  or DEF0
        local c50 = s.dynamicColor50 or DEF50
        if not (r0r == c0.r and r0g == c0.g and r0b == c0.b
            and r50r == c50.r and r50g == c50.g and r50b == c50.b) then
            wipe(reactiveCurves)
            r0r, r0g, r0b    = c0.r, c0.g, c0.b
            r50r, r50g, r50b = c50.r, c50.g, c50.b
        end
        local cc = EllesmereUI.GetClassColor(classToken) or GRAY
        local e = reactiveCurves[classToken]
        if not (e and e.r == cc.r and e.g == cc.g and e.b == cc.b) then
            local curve = C_CurveUtil.CreateColorCurve()
            curve:SetType(Enum.LuaCurveType.Linear)
            -- Front-loaded class return: fully reactive at 40% health, and the
            -- 0.75 stop already carries 75% class weight so identity snaps back
            -- quickly (40->75% climbs 0->75% class, 75->100% eases in the rest).
            curve:AddPoint(0,    CreateColor(c0.r,  c0.g,  c0.b,  1))
            curve:AddPoint(0.4,  CreateColor(c50.r, c50.g, c50.b, 1))
            curve:AddPoint(0.75, CreateColor(
                c50.r + (cc.r - c50.r) * 0.75,
                c50.g + (cc.g - c50.g) * 0.75,
                c50.b + (cc.b - c50.b) * 0.75, 1))
            curve:AddPoint(1,    CreateColor(cc.r,  cc.g,  cc.b,  1))
            e = { curve = curve, r = cc.r, g = cc.g, b = cc.b }
            reactiveCurves[classToken] = e
        end
        return e.curve
    end

    -- Resolved fill color for a unit under the settings table `s`.
    -- Returns  ok, r, g, b, secret  -- ok false means "not on a dynamic mode"
    -- (or the mode could not resolve) and the caller keeps whatever it had.
    --
    -- `ok` and `secret` are PLAIN booleans on purpose: on an identity-restricted
    -- unit r/g/b are SECRET numbers, and both truthiness-testing and comparing
    -- one throw. They may only ever be handed to a setter -- and `secret` marks
    -- exactly that case, because SetGradient refuses secrets where
    -- SetStatusBarColor accepts them.
    --
    -- classReactive needs a readable class token; a restricted unit has none, so
    -- it declines and the flat class/reaction fill already on the bar stands.
    -- (The Raid Frames twin greys out instead; keeping the real color is
    -- strictly better here, and only differs on focus/ToT-style units.)
    function ns.UF_DynamicHealthColor(unit, s)
        local mode = s and s.healthColorMode
        if not mode or mode == "none" or not unit then return false end
        if not (C_CurveUtil and UnitHealthPercent) then return false end
        local curve
        if mode == "classic" then
            curve = GetClassicCurve()
        elseif mode == "customDynamic" then
            curve = GetDynamicCurve(s)
        elseif mode == "classReactive" then
            local _, classToken = UnitClass(unit)
            if not classToken or issecretvalue(classToken) then return false end
            curve = GetClassReactiveCurve(s, classToken)
        else
            return false
        end
        local color = UnitHealthPercent(unit, true, curve)
        if not (color and color.GetRGB) then return false end
        local r, g, b = color:GetRGB()
        return true, r, g, b, issecretvalue(r)
    end

    -- Clean-number twins for the options previews, where the health percent is a
    -- known fake (0-1) rather than a secret. These MUST match the curves above
    -- or the designer teaches a color the live bar never shows.
    function ns.UF_ResolveDynamicColor(s, pct01)
        local c0   = s.dynamicColor0   or DEF0
        local c50  = s.dynamicColor50  or DEF50
        local c100 = s.dynamicColor100 or DEF100
        if pct01 >= 0.5 then
            local t = (pct01 - 0.5) * 2
            return c50.r + (c100.r - c50.r) * t,
                   c50.g + (c100.g - c50.g) * t,
                   c50.b + (c100.b - c50.b) * t
        end
        local t = pct01 * 2
        return c0.r + (c50.r - c0.r) * t,
               c0.g + (c50.g - c0.g) * t,
               c0.b + (c50.b - c0.b) * t
    end

    function ns.UF_ResolveClassicColor(pct01)
        if pct01 >= 0.5 then
            local t = (pct01 - 0.5) * 2
            return 1 - t, 1, 0
        end
        return 1, pct01 * 2, 0
    end

    function ns.UF_ResolveClassReactiveColor(s, classToken, pct01)
        local cc = (classToken and EllesmereUI.GetClassColor(classToken)) or GRAY
        local c0  = s.dynamicColor0  or DEF0
        local c50 = s.dynamicColor50 or DEF50
        if pct01 >= 0.4 then
            local w
            if pct01 >= 0.75 then
                w = 0.75 + (pct01 - 0.75)
            else
                w = (pct01 - 0.4) / 0.35 * 0.75
            end
            return c50.r + (cc.r - c50.r) * w,
                   c50.g + (cc.g - c50.g) * w,
                   c50.b + (cc.b - c50.b) * w
        end
        local t = pct01 / 0.4
        return c0.r + (c50.r - c0.r) * t,
               c0.g + (c50.g - c0.g) * t,
               c0.b + (c50.b - c0.b) * t
    end

    -- One entry point for every preview surface: resolves whichever dynamic mode
    -- `s` is on at a FAKE percent, or nil when the unit is on a flat fill.
    function ns.UF_PreviewDynamicColor(s, pct01)
        local mode = s and s.healthColorMode
        if not mode or mode == "none" then return nil end
        if mode == "classic" then
            return ns.UF_ResolveClassicColor(pct01)
        elseif mode == "customDynamic" then
            return ns.UF_ResolveDynamicColor(s, pct01)
        elseif mode == "classReactive" then
            local _, ct = UnitClass("player")
            return ns.UF_ResolveClassReactiveColor(s, ct, pct01)
        end
        return nil
    end
end

-- Carrier for a resolved-but-secret class color. Reused: it is written and consumed inside one
-- UpdateColor pass (SetStatusBarColor, then PostUpdateColor), and nothing stores it.
local SECRET_CLASS_COLOR = CreateColor(1, 1, 1, 1)

-- TEMPORARY oUF SHIM -- remove when upstream oUF ships secret-safe class coloring
-- (check during the standing per-bump lib re-diff). 12.1 build 68914 made UnitClass return a SECRET token
-- for identity-restricted units; the vendored health element's UpdateColor indexes
-- colors.class with it and secret table keys error (storms on ToT frames). Vendored-lib
-- edits aren't an option (packager re-pulls oUF tag:latest at release), so this rides
-- the documented Health.UpdateColor override hook: a faithful copy of the lib function
-- with ONLY the class tier guarded (unreadable class degrades to reaction/health tiers).
-- Installed via ApplyDarkTheme, the one chokepoint every health element passes at
-- creation. colorSelection is not carried over (needs oUF-private unitSelectionType;
-- no EUI health element enables it).
local function UF_SecretSafeHealthColor(self, event, unit)
    if not unit or self._euiUnit ~= unit then return end
    local element = self.Health

    local color
    if element.colorDisconnected and not UnitIsConnected(unit) then
        color = self.colors.disconnected
    elseif element.colorTapped and not UnitPlayerControlled(unit) and UnitIsTapDenied(unit) then
        color = self.colors.tapped
    elseif element.colorThreat and not UnitPlayerControlled(unit) and UnitThreatSituation("player", unit) then
        color = self.colors.threat[UnitThreatSituation("player", unit)]
    elseif (element.colorClass and (UnitIsPlayer(unit) or UnitInPartyIsAI(unit)))
        or (element.colorClassNPC and not (UnitIsPlayer(unit) or UnitInPartyIsAI(unit)))
        or (element.colorClassPet and UnitPlayerControlled(unit) and not UnitIsPlayer(unit)) then
        local _, class = UnitClass(unit)
        if issecretvalue(class) then
            -- 12.1 (68914): UnitClass is SecretWhenUnitIdentityRestricted (focus/focus-target/ToT):
            -- token can't be read or used as a table key. C_ClassColor.GetClassColor and
            -- SetStatusBarColor are both SecretArguments="AllowedWhenTainted", so the real
            -- color still reaches the bar without Lua inspecting it -- but only ever in
            -- Blizzard's shade. GetClassColorForRestrictedUnit recovers the user's custom
            -- class color for group members with the compare done in C; its r/g/b are secret,
            -- so they go into a scratch ColorMixin (plain field writes) and are never read.
            local ok, r, g, b = EllesmereUI.GetClassColorForRestrictedUnit(unit, class)
            if ok then
                SECRET_CLASS_COLOR:SetRGB(r, g, b)
                color = SECRET_CLASS_COLOR
            elseif C_ClassColor and C_ClassColor.GetClassColor then
                color = C_ClassColor.GetClassColor(class)
            end
        else
            color = class and self.colors.class[class]
        end
        if not color then
            -- Unreadable class: fall to the tiers the lib chain would have hit
            -- had the class branch not matched.
            if element.colorReaction and UnitReaction(unit, "player") then
                color = self.colors.reaction[UnitReaction(unit, "player")]
            elseif element.colorHealth then
                color = self.colors.health
            end
        end
    elseif element.colorReaction and UnitReaction(unit, "player") then
        color = self.colors.reaction[UnitReaction(unit, "player")]
    elseif element.colorSmooth and element.values and self.colors.health:GetCurve() then
        color = element.values:EvaluateCurrentHealthPercent(self.colors.health:GetCurve())
    elseif element.colorHealth then
        color = self.colors.health
    end

    if color then
        element:SetStatusBarColor(color:GetRGB())
    end

    if element.PostUpdateColor then
        element:PostUpdateColor(unit, color)
    end
end

-- `unit` is optional and used only to converge the setup paint with the repaint
-- paint (see the PostUpdateColor call at the tail of the non-dark branch). It is
-- passed by every caller that has it; Health elements never get `__owner`
-- (only aura elements do), so there is no fallback to recover it from.
local function ApplyDarkTheme(health, unit)
    if not health then return end
    -- TEMPORARY (see UF_SecretSafeHealthColor). Idempotent: this function
    -- re-runs on settings changes and re-assigning is harmless.
        health.UpdateColor = UF_SecretSafeHealthColor
    local isDark = db and db.profile and db.profile.darkTheme
    if isDark then
        health.colorClass = false
        health.colorClassPet = false
        health.colorReaction = false
        health.colorTapped = false
        health.colorDisconnected = false
        -- Fill/background from the global per-profile Dark Mode palette.
        local dfr, dfg, dfb, dfa = EllesmereUI.GetDarkModeFill()
        local dbr, dbg, dbb, dba = EllesmereUI.GetDarkModeBg()
        health:SetStatusBarColor(dfr, dfg, dfb)
        local darkFillTex = health:GetStatusBarTexture()
        if darkFillTex then darkFillTex:SetAlpha(dfa) end
        if health.bg then
            AnchorHealthBg(health)
            -- Background opacity rides the texture alpha; region alpha stays 1 so
            -- the two never multiply into a double-darkened background.
            health.bg:SetColorTexture(dbr, dbg, dbb, dba)
            health.bg:SetAlpha(1)
        end
        -- Re-apply dark color after oUF's class-color attempt and re-anchor bg to the
        -- fill edge. Alpha is NOT re-applied: SetStatusBarColor(r,g,b) with 3 args
        -- preserves texture alpha, so ApplyHealthBarAlpha's value survives oUF recolors.
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
            -- Custom fill overrides class coloring; skipped when class color is on.
            if not (unitSettings and unitSettings.healthClassColored) then
                health.colorClass = false
                health.colorReaction = false
                health.colorTapped = false
                health.colorDisconnected = false
                health:SetStatusBarColor(customFill.r, customFill.g, customFill.b)
            end
        end
        -- Tint bg to 20% of the class/reaction color, or use the custom bg color.
        -- Alpha is NOT re-applied: SetStatusBarColor(r,g,b) preserves texture
        -- alpha through oUF recolors.
        health.PostUpdateColor = function(self, unit, color)
            local uKey = self._euiUnitKey
            local uSettings = uKey and db.profile[uKey]
            local cFill = uSettings and uSettings.customFillColor
            local cBg   = uSettings and uSettings.customBgColor
            local classColored = uSettings and uSettings.healthClassColored
            local bgClassColored = uSettings and uSettings.bgClassColored
            -- Base fill color (custom, or oUF's class/reaction color); gradient
            -- applies additively when enabled, otherwise flat.
            -- haveBase/baseSecret are PLAIN booleans standing in for bR: on an
            -- identity-restricted unit bR is a secret number, and truthiness-testing one
            -- errors, so it may only ever be handed to a setter.
            local bR, bG, bB
            local haveBase, baseSecret = false, false
            -- Dynamic Health Color outranks every FLAT source (custom fill, class,
            -- reaction): the whole point is that the fill tracks damage taken. It
            -- does not displace the spatial Gradient below -- it becomes that
            -- gradient's start color, so the two compose.
            local haveDyn, dR, dG, dB, dSecret = ns.UF_DynamicHealthColor(unit, uSettings)
            if haveDyn then
                bR, bG, bB = dR, dG, dB
                haveBase, baseSecret = true, dSecret
            elseif cFill and not classColored then
                bR, bG, bB = cFill.r, cFill.g, cFill.b
                haveBase = true
            elseif classColored and uKey == "pet" then
                local _, ct = UnitClass("player")
                local cc = ct and not issecretvalue(ct) and EllesmereUI.GetClassColor(ct)
                if cc then bR, bG, bB = cc.r, cc.g, cc.b; haveBase = true end
            elseif color and color.GetRGB then
                bR, bG, bB = color:GetRGB()
                haveBase = true
                baseSecret = issecretvalue(bR)
            end
            -- Texture:SetGradient is SecretArguments="AllowedWhenUntainted", so a secret
            -- color cannot go through it from here at all. The flat color the health
            -- element already applied is correct, so a restricted unit keeps a flat bar.
            if uSettings and uSettings.gradientEnabled and haveBase and not baseSecret then
                local gc = uSettings.gradientColor
                -- A gradient overrides region alpha, so Bar Opacity is baked into
                -- the gradient endpoint alphas instead of SetAlpha.
                local ga = uSettings.healthBarOpacity or 90
                if ga > 1.0 then ga = ga / 100 end
                ApplyBarGradient(self:GetStatusBarTexture(), uSettings.gradientDir or "HORIZONTAL",
                    bR, bG, bB, ga,
                    gc and gc.r or 0.20, gc and gc.g or 0.20, gc and gc.b or 0.80, ga)
            elseif haveDyn then
                -- Must be written explicitly: the health element painted the flat
                -- class/reaction color a moment ago, and unlike the pet/custom
                -- branches below there is no earlier setup pass that pre-applied
                -- this one. SetStatusBarColor takes secrets, so a restricted unit
                -- still gets its real curve color here.
                self:SetStatusBarColor(bR, bG, bB)
            elseif classColored and uKey == "pet" and haveBase then
                self:SetStatusBarColor(bR, bG, bB)
            elseif cFill and not classColored then
                self:SetStatusBarColor(cFill.r, cFill.g, cFill.b)
            end
            if self.bg then
                AnchorHealthBg(self)
                local bgClassOk, bgClassR, bgClassG, bgClassB
                if bgClassColored then
                    local classUnit = ClassColorSourceUnit(uKey, unit or self._euiUnit or uKey)
                    bgClassOk, bgClassR, bgClassG, bgClassB = ns.ResolveBgClassColor(classUnit)
                end
                if bgClassOk then
                    -- Full class color; opacity comes from customBgAlpha (SetAlpha).
                    self.bg:SetColorTexture(bgClassR, bgClassG, bgClassB, 1)
                elseif cBg then
                    self.bg:SetColorTexture(cBg.r, cBg.g, cBg.b, 1)
                elseif cFill and not classColored then
                    self.bg:SetColorTexture(cFill.r * 0.2, cFill.g * 0.2, cFill.b * 0.2, 1)
                elseif color and color.GetRGB then
                    local r, g, b = color:GetRGB()
                    -- SetColorTexture takes secrets; the multiply does not, and there is no
                    -- C-side blend to darken one with. So a restricted unit's background
                    -- degrades to the default dark rather than throwing on the tint.
                    if issecretvalue(r) then
                        self.bg:SetColorTexture(DARK_HEALTH_R, DARK_HEALTH_G, DARK_HEALTH_B, 1)
                    else
                        self.bg:SetColorTexture(r * 0.2, g * 0.2, b * 0.2, 1)
                    end
                else
                    -- No color source (e.g. no target): default bg.
                    self.bg:SetColorTexture(DARK_HEALTH_R, DARK_HEALTH_G, DARK_HEALTH_B, 1)
                end
            end
        end
        if health.bg then
            -- PostUpdateColor re-applies this so it survives texture swaps.
            AnchorHealthBg(health)
            local bgClassColored = unitSettings and unitSettings.bgClassColored
            local bgClassOk, bgClassR, bgClassG, bgClassB
            if bgClassColored then
                local classUnit = ClassColorSourceUnit(unitKey, unitKey or (health.__owner and health.__owner._euiUnit))
                bgClassOk, bgClassR, bgClassG, bgClassB = ns.ResolveBgClassColor(classUnit)
            end
            if bgClassOk then
                -- Full class color; PostUpdateColor keeps it correct on updates.
                health.bg:SetColorTexture(bgClassR, bgClassG, bgClassB, 1)
            elseif customBg then
                health.bg:SetColorTexture(customBg.r, customBg.g, customBg.b, 1)
            elseif customFill then
                health.bg:SetColorTexture(customFill.r * 0.2, customFill.g * 0.2, customFill.b * 0.2, 1)
            else
                -- No custom colors: default dark bg (#111).
                health.bg:SetColorTexture(DARK_HEALTH_R, DARK_HEALTH_G, DARK_HEALTH_B, 1)
            end
        end
        -- Converge the SETUP paint with the REPAINT paint. Everything above only
        -- writes the flat class/custom color and then INSTALLS PostUpdateColor
        -- without ever running it, so any color that PostUpdateColor owns was
        -- lost until the next health event. That is invisible for a flat fill
        -- (setup already painted it) but not for Dynamic Health Color, which is
        -- resolved from the health percent and lives only in PostUpdateColor:
        -- the bar sat on the class/custom color until the unit was damaged.
        -- ReloadFrames makes this reachable on every settings change too -- it
        -- repaints via Engine.ForceAll FIRST and re-runs ApplyDarkTheme after,
        -- so the setup pass clobbered the correct color a moment after it landed.
        -- Idempotent by construction: PostUpdateColor is built to run on every
        -- health event, so one extra call here is free. A nil `color` just means
        -- the class/reaction tier contributes nothing, which is right at setup --
        -- the element has not resolved one yet.
        if health.PostUpdateColor then health:PostUpdateColor(unit, nil) end
    end
end
ns.ApplyDarkTheme = ApplyDarkTheme

-- Re-apply dark theme to every frame when the global Dark Mode palette changes
-- (fill/bg colour + opacity). Class/power darken propagates via ApplyColorsToOUF,
-- which RefreshDarkMode() calls right after these refreshers.
if EllesmereUI.RegisterDarkModeRefresh then
    EllesmereUI.RegisterDarkModeRefresh(function()
        for _, obj in pairs(frames) do
            if type(obj) == "table" and obj.Health then ApplyDarkTheme(obj.Health, obj._euiUnit) end
        end
        -- Boss "Activate Preview" fake frames need their red class-color
        -- substitute re-applied after the dark repaint above.
        if ns._bossPreviewActive and ns._ReapplyBossPreviewColor then
            ns._ReapplyBossPreviewColor()
        end
    end)
end

local optionsFrame
local optionsCategoryID

-- Unit token -> its settings key in the profile. The settings table itself is
-- read live on every call: a profile switch, import or reset (or a layer
-- paint) can replace db.profile or its unit tables between frame reloads.
local unitSettingsKey = {
    player = "player", target = "target", targettarget = "targettarget",
    pet = "pet", focus = "focus", focustarget = "focustarget",
    boss1 = "boss", boss2 = "boss", boss3 = "boss", boss4 = "boss", boss5 = "boss",
}
local function GetSettingsForUnit(unit)
    local p = db.profile
    local k = unitSettingsKey[unit]
    return (k and p[k]) or p.player
end

-- Per-unit frame source resolver. Returns "eui" (spawn skinned frame, default),
-- "blizzard" (don't spawn, leave Blizzard's default in place), or "hidden" (don't
-- spawn, actively disable Blizzard's too). "hidden" has highest precedence so a
-- disabled frame (enabledFrames[unit]==false, the "Enable X Frame" toggles) keeps
-- meaning "no frame at all". Visibility "never" is NOT one of these: it hides our
-- frame at runtime and the frame stays built, so a Spec Override can lift it again
-- without a /reload.

--- The Visibility mode actually in force for a settings table. An applied override
--- REPLACES the whole shared setting, "never" included, so every reader that acts on
--- "never" alone resolves it here instead of off the stored scalar. On ns for the
--- 200-locals cap.
function ns.VisEffective(s)
    if not s then return nil end
    return (EllesmereUI.VisOverrideValue(s)) or s.barVisibility
end

--- True when the unit has no EllesmereUI frame at all -- the enabledFrames flag, which
--- only the "Enable X Frame" toggles write now that Visibility no longer touches it.
--- On ns for the 200-locals cap.
function ns.VisUnitDisabled(profile, unitKey)
    local ef = profile and profile.enabledFrames
    return (ef and ef[unitKey] == false) or false
end

function ns.GetUnitFrameSource(unit)
    if not db or not db.profile then return "eui" end
    if ns.VisUnitDisabled(db.profile, unit) then return "hidden" end
    local fs = db.profile.frameSource and db.profile.frameSource[unit]
    if fs == "blizzard" then
        -- Visibility "never" over Blizzard's frame: we spawn nothing of our own to
        -- hide, so suppressing Blizzard's is the only way to honor it.
        if ns.VisEffective(db.profile[unit]) == "never" then return "hidden" end
        -- ToT/focus-target have no standalone Blizzard frame (native one is a child
        -- of TargetFrame/FocusFrame, lives only while that parent does), so
        -- "blizzard" is honored for them ONLY when the parent is itself on
        -- Blizzard's frame; else fall back to the EllesmereUI frame.
        if unit == "targettarget" then
            return ns.GetUnitFrameSource("target") == "blizzard" and "blizzard" or "eui"
        elseif unit == "focustarget" then
            return ns.GetUnitFrameSource("focus") == "blizzard" and "blizzard" or "eui"
        end
        return "blizzard"
    end
    return "eui"
end

--- True when this profile has Unit Frames re-host Blizzard's class resource frame
--- (the "Blizzard" class resource style on the EllesmereUI player frame). Resource
--- Bars' Blizzard Class Resource Art reads it through the module registry and never
--- claims that frame while it holds: one owner, and Unit Frames wins a tie from an
--- import or spec override. Config plus the runtime mirror (ns._ufBlizzCPHeld), so
--- it answers before InitializeFrames and while a change waits to apply.
--- On ns for the 200-locals cap.
function ns.UF_OwnsBlizzClassPower()
    if EllesmereUI.IS_FOREVER == true then return false end
    -- Held right now (runtime), even while the config says otherwise: a style or
    -- source change not applied yet (combat, a pending reload) keeps it ours.
    if ns._ufBlizzCPHeld then return true end
    local p = db and db.profile
    if not (p and p.player and p.player.classPowerStyle == "blizzard") then return false end
    return ns.GetUnitFrameSource("player") == "eui"
end

-- Write a unit's frame source, keeping the legacy enabledFrames flag in sync so
-- existing readers stay correct (and so the cog is the way back for a frame an old
-- profile left disabled). Only takes full effect after a UI reload -- the spawn
-- permanently disables the Blizzard frame, and secure frames can't be created or
-- torn down in combat -- so callers should also prompt a reload.
function ns.SetUnitFrameSource(unit, source)
    if not db or not db.profile then return end
    db.profile.frameSource = db.profile.frameSource or {}
    db.profile.frameSource[unit] = source
    db.profile.enabledFrames[unit] = (source ~= "hidden")
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
                    [71]  = { "SWEEPING_STRIKES", 18 } },  -- 12.1 cap: 12 + 6 Broad Strokes
}

-- Vanilla content has no specializations, so every spec-keyed entry above fails to
-- resolve on Forever, and the flat ones name resources that client does not have --
-- a paladin there would draw five Holy Power pips that can never fill. This is the
-- whole set that exists on Forever; a class missing from it has no class resource.
local FOREVER_CLASS_POWER = {
    ROGUE = Enum.PowerType.ComboPoints,
    DRUID = Enum.PowerType.ComboPoints,
}

local function ClassPowerEntry(playerClass)
    if EllesmereUI.IS_FOREVER == true then return FOREVER_CLASS_POWER[playerClass] end
    return CLASS_POWER_TYPES[playerClass]
end

-- Combo points exist only in cat form for Guardian and Resto on retail, and for
-- every druid on Forever, where there are no specs to tell them apart.
local function DruidNeedsCatForm(playerClass, powerType)
    if playerClass ~= "DRUID" or powerType ~= Enum.PowerType.ComboPoints then
        return false
    end
    if EllesmereUI.IS_FOREVER == true then return true end
    local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
    local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec)
    return specID == 104 or specID == 105
end

-- Blizzard defines DRUID_CAT_FORM on every flavour; the literal is the fallback.
local function InCatForm()
    local form = GetShapeshiftFormID and GetShapeshiftFormID() or 0
    return form == (DRUID_CAT_FORM or 1)
end

-- Returns true if the player's current spec has a class resource in CLASS_POWER_TYPES
SpecHasClassPower = function()
    local _, playerClass = UnitClass("player")
    local entry = ClassPowerEntry(playerClass)
    if not entry then return false end
    if type(entry) ~= "table" then return true end
    if entry[1] ~= nil then return true end
    local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
    local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec)
    return specID and entry[specID] ~= nil
end

-- Main-chunk locals the other EUI_UnitFrames_*.lua files re-import by name.
-- dbSetters: a file that reads db keeps its own local and adds a setter here,
-- this file first; EllesmereUF:OnInitialize (EUI_UnitFrames_Lifecycle.lua)
-- assigns its own db, then runs the list.
ns._internals = {
    frames = frames, GetSettingsForUnit = GetSettingsForUnit, UnsnapTex = UnsnapTex,
    unitSettingsKey = unitSettingsKey, UnitToSettingsKey = UnitToSettingsKey,
    ResolveFontPath = ResolveFontPath, ApplyDarkTheme = ApplyDarkTheme,
    defaults = defaults, healthBarTextures = healthBarTextures,
    healthBarTextureNames = healthBarTextureNames, healthBarTextureOrder = healthBarTextureOrder,
    GetSelectedFont = GetSelectedFont, SetFSFont = SetFSFont,
    AbbreviateNumbers = AbbreviateNumbers, GetCastbarColor = GetCastbarColor,
    ClassPowerEntry = ClassPowerEntry, DruidNeedsCatForm = DruidNeedsCatForm, InCatForm = InCatForm,
    ApplyBarGradient = ApplyBarGradient, ApplyHealthBarTexture = ApplyHealthBarTexture,
    ApplyHealthBarAlpha = ApplyHealthBarAlpha, ApplyPowerBarAlpha = ApplyPowerBarAlpha,
    SpecHasClassPower = SpecHasClassPower, UF_SecretSafeHealthColor = UF_SecretSafeHealthColor,
    dbSetters = { function(v) db = v end },
}
-- A re-import of a name this table lacks fails where the part file loads,
-- not later as a nil upvalue inside one of its functions.
setmetatable(ns._internals, { __index = function(_, k)
    error("ns._internals has no entry " .. tostring(k), 2)
end })
