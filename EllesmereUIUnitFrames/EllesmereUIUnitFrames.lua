if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local addonName, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS[addonName] = ns  -- LOD options files read this module ns via the registry

local math_floor, math_ceil, math_max, math_min, math_abs =
    math.floor, math.ceil, math.max, math.min, math.abs
local string_format = string.format
local issecretvalue = issecretvalue

local PP = EllesmereUI.PP

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
    local regenWatcher = CreateFrame("Frame")
    regenWatcher:SetScript("OnEvent", function(self)
        if InCombatLockdown() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        for f in pairs(looseFrames) do f:SetParent(hiddenParent) end
        wipe(looseFrames)
    end)

    local function ApplyHiddenParent(frame)
        pendingParent[frame] = nil
        if frame:GetParent() == hiddenParent then return end
        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
            pendingParent[frame] = true
            C_Timer.After(0.25, function() ApplyHiddenParent(frame) end)
        elseif InCombatLockdown() and frame:IsProtected() then
            looseFrames[frame] = true
            regenWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
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


-- Portrait UNIT_MODEL_CHANGED on eventless frames (TargetTarget) triggers UnitIsUnit,
-- which returns secret booleans in protected instances; we unregister that event after
-- oUF sets up eventless frames instead of patching the global. See PostCreateTargetTarget.

-- External lookup for portrait side per frame (writing custom props onto oUF frames would taint their secure execution chain).
EllesmereUI._ufPortraitSide = EllesmereUI._ufPortraitSide or setmetatable({}, { __mode = "k" })

local db
local defaults = {
    profile = {
        playerAuraBars = {
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
        darkTheme = false,
        -- One decimal on abbreviated values (240.5k) and percents (77.3%); global, read by text tags via _G flags.
        showDecimalOnText = false,
        -- With decimals on, boss frames use two (240.55k / 77.30%); inline cog on "Show Decimal on Health Text".
        showDecimalBoss2 = true,
        -- With decimals on, "Only Show for % Health" keeps the decimal on PERCENT (77.3%) but leaves VALUES whole (240k); same inline cog.
        showDecimalPercentOnly = false,
        -- Player Threat (Non-Tank): additive "Shadow" border on the PLAYER frame while
        -- pulling/holding aggro, instanced content only; global, default off (zero cost
        -- until enabled). Colors mirror the nameplate non-tank threat defaults (has/near aggro).
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
            auraBorderTexture = "solid",
            auraBorderSize = 1,
            auraBorderR = 0, auraBorderG = 0, auraBorderB = 0, auraBorderA = 1,
            auraBorderBehind = false,
            auraBorderBehindUnitFrame = false,
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
            auraBorderTexture = "solid",
            auraBorderSize = 1,
            auraBorderR = 0, auraBorderG = 0, auraBorderB = 0, auraBorderA = 1,
            auraBorderBehind = false,
            auraBorderBehindUnitFrame = false,
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
            eliteIndicatorEnabled = false,
            eliteIndicatorSize = 16,
            eliteIndicatorPosition = "topleft",
            eliteIndicatorX = 0,
            eliteIndicatorY = 0,
            eliteIndicatorShowInInstances = false,
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
  -- Drop shadows only render from a FontObject; prime before SetFont.
  if EllesmereUI and EllesmereUI.PrimeFontShadow then
    EllesmereUI.PrimeFontShadow(fs, f == "")
  end
  fs:SetFont(GetSelectedFont(), size or 12, f)
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
end

-- Resolve a unit's effective health bar texture KEY. Main frames use their own key
-- (falling back to the global default); mini frames (pet, ToT, focus target, boss)
-- inherit the donor frame's texture (focus > target > player) unless their own key is
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
    elseif element.colorTapping and not UnitPlayerControlled(unit) and UnitIsTapDenied(unit) then
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

-------------------------------------------------------------------------------
--  Engine painters (oUF extraction). ns.Colors carries the exact color table
--  the shared color chains read through frame.colors: same value sources and
--  shapes as before, so every existing color decision lands on identical
--  numbers. Class entries are overwritten by the suite palette sync (the same
--  flow that used to write the library's table); reaction entries by the
--  module's own reaction sync. Published as EllesmereUI._UFColors so the
--  parent's color chokepoint can reach it.
-------------------------------------------------------------------------------
do
    local CreateColor = _G.CreateColor
    local colors = {
        health       = CreateColor(49 / 255, 207 / 255, 37 / 255),
        disconnected = CreateColor(0.6, 0.6, 0.6),
        tapped       = CreateColor(0.6, 0.6, 0.6),
        class    = {},
        reaction = {},
        threat   = {},
        power    = {},
    }
    for token, c in pairs(RAID_CLASS_COLORS) do
        colors.class[token] = CreateColor(c.r, c.g, c.b)
    end
    for idx, c in pairs(FACTION_BAR_COLORS) do
        colors.reaction[idx] = CreateColor(c.r, c.g, c.b)
    end
    for i = 0, 3 do
        colors.threat[i] = CreateColor(GetThreatStatusColor(i))
    end
    -- Both key forms land: Blizzard's table carries string tokens plus numeric
    -- aliases, and the painter looks up number-first, token-second.
    for key, c in pairs(PowerBarColor) do
        if type(c) == "table" and c.r then
            colors.power[key] = CreateColor(c.r, c.g, c.b)
        end
    end
    -- Dispel colors keyed by the game's dispel-type indices (the aura rows'
    -- type overlay reads these through a step curve). Blizzard's shared color
    -- objects are referenced directly; Enrage has no stock color.
    colors.dispel = {
        [0]  = _G.DEBUFF_TYPE_NONE_COLOR,
        [1]  = _G.DEBUFF_TYPE_MAGIC_COLOR,
        [2]  = _G.DEBUFF_TYPE_CURSE_COLOR,
        [3]  = _G.DEBUFF_TYPE_DISEASE_COLOR,
        [4]  = _G.DEBUFF_TYPE_POISON_COLOR,
        [9]  = CreateColor(243 / 255, 95 / 255, 245 / 255),
        [11] = _G.DEBUFF_TYPE_BLEED_COLOR,
    }
    ns.Colors = colors
    EllesmereUI._UFColors = colors

    -- Health value pass: min/max plus current (offline paints a full bar, the
    -- behavior users already see), native interpolation via the bar's own
    -- .smoothing, then the shared secret-safe color chain.
    local function PaintHealth(frame, unit, event)
        local element = frame.Health
        if not element or not unit or not UnitExists(unit) then return end
        if not ns.Engine.ElementOn(frame, "Health") then return end
        -- Bar bounds ride the max-health/identity events (Blizzard's own
        -- contract); a pure UNIT_HEALTH value tick pushes only the value.
        if event ~= "UNIT_HEALTH" or not element._maxSet then
            element._maxSet = true
            element:SetMinMaxValues(0, UnitHealthMax(unit))
        end
        if UnitIsConnected(unit) then
            element:SetValue(UnitHealth(unit), element.smoothing)
        else
            element:SetValue(UnitHealthMax(unit), element.smoothing)
        end
        -- Color inputs (class/reaction/dark/disconnect/tap) change via their
        -- own events or identity repaints -- a pure health tick re-runs the
        -- color chain only for modes whose color follows health/combat state
        -- per tick (dynamic curve, threat, tap coloring). The color* flags are
        -- never set by this engine; the dynamic modes live in PostUpdateColor
        -- (ns.UF_DynamicHealthColor) behind the unit's healthColorMode, so that
        -- setting is the gate that keeps a dynamic bar tracking every tick.
        local unitKey = element._euiUnitKey
        local unitColorMode = unitKey and db.profile[unitKey]
        unitColorMode = unitColorMode and unitColorMode.healthColorMode
        if event ~= "UNIT_HEALTH" or element.colorSmooth or element.colorThreat
           or element.colorTapping or (unitColorMode and unitColorMode ~= "none") then
            UF_SecretSafeHealthColor(frame, event, unit)
        end
    end
    ns.Engine.SetPainter("health", PaintHealth)

    -- Power value pass: display-power resolution first (the player bar's
    -- spec-override hook publishes the resolved type for the text formatters),
    -- then min/max/value with offline painting full, then the base power-type
    -- color with the bar's own PostUpdateColor/PostUpdate layered on top in
    -- the same order as before.
    local function PaintPower(frame, unit, event)
        local element = frame.Power
        if not element or not unit or not UnitExists(unit) then return end
        if not ns.Engine.ElementOn(frame, "Power") then return end
        local ptype
        if element.displayAltPower and element.GetDisplayPower then
            ptype = element:GetDisplayPower(unit)
        end
        element.displayType = ptype
        local pnum, ptoken
        if ptype then pnum = ptype else pnum, ptoken = UnitPowerType(unit) end
        local max = UnitPowerMax(unit, pnum)
        element:SetMinMaxValues(0, max)
        local cur
        if UnitIsConnected(unit) then
            cur = UnitPower(unit, pnum)
            element:SetValue(cur, element.smoothing)
        else
            cur = max
            element:SetValue(max, element.smoothing)
        end
        if element.colorPower then
            local color = ns.Colors.power[pnum] or (ptoken and ns.Colors.power[ptoken])
            if color then element:SetStatusBarColor(color:GetRGB()) end
        end
        if element.PostUpdateColor then element:PostUpdateColor(unit) end
        if element.PostUpdate then element:PostUpdate(unit, cur, 0, max) end
    end
    ns.Engine.SetPainter("power", PaintPower)

    -- Absorbs: the HealthPrediction Override was always our own complete
    -- painter (bars, clips, text gates); the engine simply becomes its event
    -- source. Identity repaints arrive as pseudo-events, which the Override
    -- already treats as gate-refresh triggers.
    local function PaintAbsorb(frame, unit, event)
        if not ns.Engine.ElementOn(frame, "HealthPrediction") then return end
        local hp = frame.HealthPrediction
        if hp and hp.Override then hp.Override(frame, event or "ForceUpdate", unit) end
    end
    ns.Engine.SetPainter("absorb", PaintAbsorb)
end

-- Global Dark Mode master: exposes darkTheme so the parent addon's master toggle can
-- flip it with other modules. setOn mirrors the individual toggle (write flag + reload).
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

-- Smart power text: percent for healers/prot pally/arcane mage, numeric for the rest.
-- Shared by the oUF tag and the resource bars renderer. `displayedPowerType` (optional
-- Enum.PowerType) is the power the caller's bar actually shows; for form/spec-shifting
-- classes (Druid, Monk) the decision MUST follow the displayed power, not UnitPowerType --
-- a Balance druid's UnitPowerType is Astral Power even while the bar shows Mana, so the
-- mana number would render raw instead of percent otherwise.
local function EUI_IsSmartPowerPercent(displayedPowerType)
    local _, cls = UnitClass("player")
    if not cls then return false end
    -- Druid/Monk shift displayed power with form/spec: percent only while the bar shows
    -- Mana (Druid caster/Tree/travel + Mistweaver); raw otherwise (Cat=Energy, Bear=Rage,
    -- Moonkin=Astral, WW/BRM=Energy, incl. Restoration weaving Cat/Bear). Prefer the
    -- caller-supplied displayed power, else the live primary power type.
    if cls == "DRUID" or cls == "MONK" then
        local pt = displayedPowerType or UnitPowerType("player")
        return pt == Enum.PowerType.Mana
    end
    if cls == "PRIEST" or cls == "SHAMAN" then
        return true
    end
    -- Paladin: Holy and Protection (mana-based specs).
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

-- Show Decimal on Text (global): AbbreviateNumbers config emitting one decimal per
-- magnitude band (240500 -> "240.5k", 2405000 -> "2.4m"). AbbreviateNumbers runs in
-- Blizzard's secure context, so a secret value plus this config stays secret-safe
-- (like the no-config call on secret health/power). Tags read two _G flags:
--   _G._EUI_AbbrevDecimalCfg = this table when on, nil when off
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
        -- "Only Show for % Health": decimal on PERCENT, health/absorb VALUES whole --
        -- withhold the abbreviate configs (values fall back to plain AbbreviateNumbers)
        -- while _EUI_TextDecimals stays true for percents.
        local percentOnly = db.profile.showDecimalPercentOnly
        _G._EUI_AbbrevDecimalCfg = ns._decimalAbbrevConfig
        if percentOnly then _G._EUI_AbbrevDecimalCfg = nil end
        -- Boss frames get a second decimal place. Tags use the 1-decimal path
        -- for non-boss units when the flag is set, and ignore it when nil.
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

-- Shared text-piece functions consumed by the zone formatter table below.
local TagFns = {}

do
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

  TagFns.curhpshort = AbbrevHP
end

do
  TagFns.perhpnosign = function(unit)
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
end

-- Resolved power type per unit. Updated by the GetDisplayPower override so the
-- power text matches the power bar when powerTypeOverride is active (e.g.
-- Balance Druid showing Mana instead of Astral Power).
_G._EUI_ResolvedPowerType = _G._EUI_ResolvedPowerType or {}

local PLAYER_POWER_DEFAULT = {
    PRIEST = { [3] = 0 },   -- Shadow: default to Mana
}
local PLAYER_POWER_ALT = {
    DRUID  = { [1] = 0, [2] = 0, [3] = 0 },  -- Balance/Feral/Guardian -> Mana
    PRIEST = { [3] = nil },                     -- Shadow alt -> Insanity (UnitPowerType)
    SHAMAN = { [1] = 0 },                       -- Elemental -> Mana
}

-- Forced display power type for the player (number = Enum.PowerType, nil =
-- UnitPowerType decides). Shared by the bar's GetDisplayPower, the color
-- resolver and the options preview so all three agree.
function EllesmereUI.GetPlayerPowerOverride()
    if not (db and db.profile) then return nil end
    local _, classFile = UnitClass("player")
    local classDef = PLAYER_POWER_DEFAULT[classFile]
    local classAlt = PLAYER_POWER_ALT[classFile]
    if not (classDef or classAlt) then return nil end
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return nil end
    -- powerTypeOverride is keyed by SPEC ID, never the GetSpecialization() index:
    -- the set is profile-wide, so an index key collides across classes (slot 3 is
    -- Guardian, Shadow AND Augmentation). classAlt/classDef stay index-keyed --
    -- they are nested per class already, so they cannot collide. Resource Bars may
    -- be disabled, hence the direct fallback.
    local sid = (_G._ERB_ResolveSpecIDCached and _G._ERB_ResolveSpecIDCached())
        or (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(spec))
        or nil
    local ov = db.profile.player and db.profile.player.powerTypeOverride
    if sid and ov and ov[sid] and classAlt then
        return classAlt[spec]
    elseif classDef and classDef[spec] ~= nil then
        return classDef[spec]
    end
    return nil
end

-- (The perpp/curpp/absorb piece functions live in the zone-formatter block
-- below; they read the _EUI_ globals above.)

-- Effective level (scaling-aware), "??" when unknowable (skull bosses). A
-- SECRET level is returned RAW -- display-safe as a %s arg through
-- SetFormattedText, never compared/formatted in Lua (same rule as the secret
-- name in the target-name piece).
TagFns.level = function(u)
    if not u or not UnitExists(u) then return "" end
    local l = UnitEffectiveLevel(u)
    if UnitIsWildBattlePet(u) or UnitIsBattlePetCompanion(u) then
        l = UnitBattlePetLevel(u)
    end
    if l and issecretvalue and issecretvalue(l) then return l end
    if not l or l <= 0 then return "??" end
    return l
end

-- Class/reaction color for a unit's NAME, enemy-aware: players (and AI party members)
-- get class color; NPCs use reaction color (hostile red, neutral yellow, friendly
-- green, tap-denied gray). Custom Enemy Colors override is honored via oUF.colors.reaction.
-- Returns r,g,b (0-1) or nil (caller's own default); secret-safe for uninspectable units.
-- On ns for the local cap; shared by ApplyClassColor and eui-tgtname so "Name > Target"
-- colors like the unit frame name.
ns.ResolveUnitNameColor = function(unit)
    if not unit then return nil end
    if UnitIsPlayer(unit) or (UnitInPartyIsAI and UnitInPartyIsAI(unit)) then
        local _, class = UnitClass(unit)
        if not issecretvalue(class) and class then
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
            local c = (ns.Colors and ns.Colors.reaction and ns.Colors.reaction[reaction])
                or FACTION_BAR_COLORS[reaction]
            if c then return c.r, c.g, c.b end
        end
    end
    return nil
end

-- Shared secret-class-color recovery for identity-restricted units (ToT, focus-target):
-- the user's custom color for a matching group member, else Blizzard's shade. Used by
-- ResolveBgClassColor and ApplyClassColor; ResolveUnitNameColor does NOT use this, since
-- its result also feeds the [eui-tgtcol] hex-escape tag, which cannot accept a secret.
-- Returns ok, r, g, b -- ok is a PLAIN boolean, r/g/b may be SECRET, only safe as setter args.
local function ResolveRestrictedClassColor(unit, class)
    local ok, r, g, b = EllesmereUI.GetClassColorForRestrictedUnit(unit, class)
    if ok then return true, r, g, b end
    if C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(class)
        if c then return true, c.r, c.g, c.b end
    end
    return false
end

-- Background class-color source, enemy-aware. UnitClass() reports WARRIOR for NPCs
-- rather than nil, so a bare lookup paints every mob Warrior tan. Players (and AI
-- party members) keep EllesmereUI.GetClassColor (custom colors + Class Color Darken
-- baked in); NPCs fall through to the reaction color, matching the unit name, the
-- border and the custom Enemy Colors override. On ns for the local cap.
-- Returns ok, r, g, b -- ok is a PLAIN boolean, r/g/b may be SECRET numbers on an
-- identity-restricted unit (ToT/focus-target): callers must branch on ok, never on
-- the truthiness of r, and may only ever hand r/g/b to a setter like SetColorTexture.
ns.ResolveBgClassColor = function(classUnit)
    if not classUnit then return false end
    if UnitIsPlayer(classUnit) or (UnitInPartyIsAI and UnitInPartyIsAI(classUnit)) then
        local _, ct = UnitClass(classUnit)
        if issecretvalue(ct) then
            return ResolveRestrictedClassColor(classUnit, ct)
        end
        local cc = ct and EllesmereUI.GetClassColor(ct)
        if cc then return true, cc.r, cc.g, cc.b end
        return false
    end
    local r, g, b = ns.ResolveUnitNameColor(classUnit)
    return r ~= nil, r, g, b
end

-- External nickname providers key us by this addon name. Suite = "EllesmereUI" (the
-- registered brand) so one provider checkbox controls every EUI module; standalone =
-- our renamed folder name, which always contains "Standalone" (rename-immune token).
-- On ns for the Lua 5.1 200-local ceiling.
ns.NICK_ADDON = addonName:find("Standalone") and addonName or "EllesmereUI"

-- Resolve a unit's display name through MethodInternal's authoritative surface
-- choice for known Method players, then the normal provider order: NSAPI ->
-- TimelineReminders -> LiquidAPI, then the raw unit name. Each
-- external call is pcall-wrapped so a misbehaving API can never break names.
--
-- SECRET-SAFE: an enemy unit's UnitName is secret in protected content and any Lua op
-- on it (==, .., format) throws. Nicknames only apply to your own group, so: non-players
-- short-circuit to the raw name; name-keyed providers (NSAPI, LiquidAPI) are skipped
-- when the name is secret; TimelineReminders is UNIT-keyed (GetNickname(unit)), safe to
-- consult regardless (result still re-validated as a clean string). The final return
-- may be the raw (possibly secret) name -- display-safe since oUF feeds tag returns to
-- SetFormattedText as a %s arg without inspecting them.
function ns.ResolveUnitNickname(unit)
    local name = UnitName(unit)
    if not name then return "" end
    -- Nicknames are player-only; NPCs (bosses, etc.) keep their name.
    if not UnitIsPlayer(unit) then return name end
    local nameSecret = issecretvalue and issecretvalue(name)
    local display
    -- MethodInternal's surface choice is authoritative for known Method players,
    -- including Character Name (which deliberately equals the raw name). It sits
    -- ahead of the EUI master toggle so the MethodInternal-owned setting works on
    -- its selected surface; unknown players continue through EUI's normal chain.
    if EasyNicknameAPI and EasyNicknameAPI.GetNicknameForUnitForSurface then
        local ok, dn, handled = pcall(
            EasyNicknameAPI.GetNicknameForUnitForSurface, unit, "unitFrames")
        if ok and handled == true then
            if type(dn) == "string"
               and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
                return dn
            end
            return name
        end
    end
    -- Master toggle (Unit Frames > main frames > Display, default OFF): when off,
    -- skip the remaining provider lookups and show the raw unit name (display-safe).
    if not (db and db.profile and db.profile.showNicknames) then return name end
    if not nameSecret and NSAPI and NSAPI.GetName then
        local ok, dn = pcall(NSAPI.GetName, NSAPI, name, "EUI")
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
-- the nickname when one applies, else the raw unit name.
TagFns.name = function(unit)
    -- Truncation is width-based (per-slot Width % clamp), never character-based:
    -- FontString width boxes ellipsize in the renderer, which also works on SECRET
    -- enemy names Lua cannot measure or substring.
    return ns.ResolveUnitNickname(unit)
end

-- Live name refresh: repaint every frame's text zones so added/removed
-- nicknames (or a flipped provider checkbox) apply without a /reload. Fired by
-- the provider callbacks below; cheap (a handful of frames).
function ns.RefreshAllUnitNames()
    for _, f in pairs(frames) do
        if type(f) == "table" and f._euiTextZones then
            ns.UF_PaintText(f, f._euiUnit)
        end
    end
end
-- Name text only re-renders on name events or via the refresh above, so a raw
-- db restore (Spec Overrides apply, profile swap) needs this exported.
_G._EUF_RefreshUnitNames = ns.RefreshAllUnitNames

-- Cold-login text repaint: on a first (uncached) login a fontstring can hold the
-- correct string yet render blank until /reload, since it only repaints on a text
-- CHANGE and repainting sets the same string (a no-op). Force a "" -> value
-- transition on every zone fontstring shortly after login, repeated since timing
-- varies; the zone repaint restores the real strings synchronously, no flicker.
do
    local function ForceTextRepaint()
        for _, f in pairs(frames) do
            if type(f) == "table" and f._euiTextZones then
                local zones = f._euiTextZones
                for i = 1, #zones do
                    local fs = zones[i].fs
                    if fs and fs.SetText then fs:SetText("") end
                end
                if #zones > 0 then ns.UF_PaintText(f, f._euiUnit) end
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

-- Provider callbacks. MethodInternal uses the addon-loaded callback; NSAPI and
-- TimelineReminders retry on PLAYER_LOGIN/PLAYER_ENTERING_WORLD. Registrant key MUST
-- be "EllesmereUIUnitFrames", not "EllesmereUI": Raid Frames owns that key and
-- CallbackHandler keys registrations by it, so reuse would clobber one module. The
-- provider CHECKBOX key stays shared (ns.NICK_ADDON/"EUI") so one toggle drives raid AND unit frames.
do
    local function RefreshNames() if ns.RefreshAllUnitNames then ns.RefreshAllUnitNames() end end
    local function RegisterMethodInternal()
        if ns._methodInternalSurfaceNickHooked then return end
        if EasyNicknameAPI and EasyNicknameAPI.RegisterCallback then
            EasyNicknameAPI.RegisterCallback(
                "SurfaceNicknamesChanged", RefreshNames, "EllesmereUIUnitFrames")
            ns._methodInternalSurfaceNickHooked = true
        end
    end
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
    EventUtil.ContinueOnAddOnLoaded("MethodInternal", RegisterMethodInternal)
end

-- "Name > Target" is built from FOUR tags so the (possibly SECRET) target name is never
-- compared/concatenated/formatted in Lua -- oUF joins tag returns via SetFormattedText,
-- where the name is only a %s display arg. ContentToTag maps "nametotarget" to
-- "[name][eui-tgtsep(...)][eui-tgtcol][eui-tgtname]": [name] = unit's own name (stock
-- oUF tag); [eui-tgtsep] = indicator shown only when the unit has a target (per-slot
-- separator/color ride in tag ARGS, see BuildTgtSepTag; no args = " > "); [eui-tgtcol] =
-- target's class/reaction COLOR escape (no name involved); [eui-tgtname] = target's name,
-- returned RAW. The colour escape precedes the raw name and runs to end of string, so
-- the target name colours IDENTICALLY to the ToT frame name (both via
-- ns.ResolveUnitNameColor) -- works for a SECRET name only because colour and name are
-- SEPARATE tags joined by SetFormattedText, never touched together in Lua.
--
-- PLAYER_TARGET_CHANGED is unitless in oUF (refreshes every frame), covering the player
-- frame's target; UNIT_TARGET covers target/focus frames' own target.

-- Separator/indicator between the names, shown only when the unit has a target. Plain
-- literal plus color escapes; no secret is touched. Args: sepHex = separator string,
-- hex-encoded per byte (safe inside tag brackets), rendered space-padded like " > ";
-- colorSpec = "class" for the TARGET's class/reaction color (same resolver as the
-- target name), else a fixed "rrggbb" hex, closed with |r so a missing [eui-tgtcol]
-- can't inherit it. Decoded separators/escapes are cached: fires on every target
-- change, must not allocate after warmup.
-- (The separator between "Name > Target" is built per-zone by
-- ns.MakeTgtSepPiece in the formatter block below; it closes over the decoded
-- separator and color mode from settings and recolors class-mode per call.)

-- The target's class/reaction colour escape (e.g. "|cffc41f3b"), or "". Uses
-- ns.ResolveUnitNameColor, the SAME resolver ApplyClassColor uses for the Target
-- of Target name. No unit NAME is touched, so it is fully secret-safe.
TagFns.tgtcol = function(unit)
    local tunit = unit and (unit .. "target")
    if not tunit or not UnitExists(tunit) then return "" end
    local r, g, b = ns.ResolveUnitNameColor(tunit)
    if not r then return "" end
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- The unit's target NAME (nickname-aware via ResolveUnitNickname; otherwise the
-- raw, possibly secret name -- display-safe via SetFormattedText, never
-- inspected). Colour comes from [eui-tgtcol] in front of it.
TagFns.tgtname = function(unit)
    local tunit = unit and (unit .. "target")
    if not tunit or not UnitExists(tunit) then return "" end
    return ns.ResolveUnitNickname(tunit)
end

-------------------------------------------------------------------------------
--  Text pieces + zone formatters (oUF extraction). Each options content key
--  maps to a format string plus piece functions; the engine's text painter
--  renders a zone with SetFormattedText(fmt, piece1(u), piece2(u), ...).
--  Secret rule: name/level/target-name pieces may return RAW secret values by
--  design; they are never concatenated or inspected in Lua -- the format-arg
--  lane is the only thing that touches them, exactly as the tag engine did,
--  so restricted-content rendering is unchanged.
-------------------------------------------------------------------------------
do
    local sf = string.format
    local P = {}
    ns.TextPieces = P

    -- Function-registered tag methods are shared directly: one body, no drift.
    P.curhpshort  = TagFns.curhpshort
    P.perhpnosign = TagFns.perhpnosign
    P.level       = TagFns.level
    P.name        = TagFns.name
    P.tgtcol      = TagFns.tgtcol
    P.tgtname     = TagFns.tgtname

    -- String-compiled tag methods get real equivalents (same logic, same
    -- _EUI_ globals; the compiled strings stay registered only while the tag
    -- engine still runs).
    P.perhp = function(u)
        local fmt = _G._EUI_TextDecimals and "%.1f" or "%d"
        if _G._EUI_BossExtraDecimal and string.sub(u, 1, 4) == "boss" then fmt = "%.2f" end
        return sf(fmt, UnitHealthPercent(u, true, CurveConstants.ScaleTo100))
    end
    P.perpp = function(u)
        local pType = _G._EUI_ResolvedPowerType[u] or UnitPowerType(u)
        return sf("%d", UnitPowerPercent(u, pType, true, CurveConstants.ScaleTo100))
    end
    P.curpp = function(u)
        local pType = _G._EUI_ResolvedPowerType[u] or UnitPowerType(u)
        return AbbreviateNumbers(UnitPower(u, pType))
    end
    P.absorb = function(u)
        if not u or not UnitExists(u) then return "" end
        return sf("%s", C_StringUtil.TruncateWhenZero(UnitGetTotalAbsorbs(u) or 0))
    end
    P.absorbshort = function(u)
        if not u or not UnitExists(u) then return "" end
        local cfg = _G._EUI_AbbrevDecimalCfg
        return cfg and AbbreviateNumbers(UnitGetTotalAbsorbs(u) or 0, cfg)
            or AbbreviateNumbers(UnitGetTotalAbsorbs(u) or 0)
    end
    P.healabsorb = function(u)
        if not u or not UnitExists(u) then return "" end
        return sf("%s", C_StringUtil.TruncateWhenZero(UnitGetTotalHealAbsorbs(u) or 0))
    end
    P.healabsorbshort = function(u)
        if not u or not UnitExists(u) then return "" end
        local cfg = _G._EUI_AbbrevDecimalCfg
        return cfg and AbbreviateNumbers(UnitGetTotalHealAbsorbs(u) or 0, cfg)
            or AbbreviateNumbers(UnitGetTotalHealAbsorbs(u) or 0)
    end
    P.group = function(u)
        if not IsInRaid() then return "" end
        local idx = UnitInRaid(u)
        if idx then
            local _, _, subgroup = GetRaidRosterInfo(idx)
            return subgroup or ""
        end
        return ""
    end

    -- Separator piece for "Name > Target": resolved from settings at apply
    -- time (re-applied whenever settings change, like everything else on the
    -- page), closing over the decoded separator and its color mode. Class
    -- mode recolors per call so the indicator tracks the target's reaction.
    function ns.MakeTgtSepPiece(prefix, settings)
        local sep = settings[prefix .. "TargetSep"]
        if type(sep) ~= "string" or sep == "" then sep = ">" end
        sep = " " .. sep .. " "
        if settings[prefix .. "TargetSepClassColor"] then
            return function(u)
                if not (u and UnitExists(u .. "target")) then return "" end
                local r, g, b = ns.ResolveUnitNameColor(u .. "target")
                if r then
                    return sf("|cff%02x%02x%02x%s|r",
                        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
                        math.floor(b * 255 + 0.5), sep)
                end
                return sep
            end
        end
        local c = settings[prefix .. "TargetSepColor"]
        local esc
        if type(c) == "table" then
            esc = sf("|cff%02x%02x%02x", math.floor((c.r or 1) * 255 + 0.5),
                math.floor((c.g or 1) * 255 + 0.5), math.floor((c.b or 1) * 255 + 0.5))
        else
            esc = "|cffffffff"
        end
        local colored = esc .. sep .. "|r"
        return function(u)
            if not (u and UnitExists(u .. "target")) then return "" end
            return colored
        end
    end

    -- Content key -> zone definition. Mirrors ContentToTag's output shapes
    -- one-for-one so rendered text is byte-identical.
    local ZONE_STATIC = {
        name         = { "%s", "name" },
        levelname    = { "%s | %s", "level", "name" },
        namelevel    = { "%s | %s", "name", "level" },
        level        = { "%s", "level" },
        both         = { "%s | %s%%", "curhpshort", "perhp" },
        bothdash     = { "%s - %s%%", "curhpshort", "perhp" },
        perhpnum     = { "%s%% | %s", "perhp", "curhpshort" },
        perhpnumdash = { "%s%% - %s", "perhp", "curhpshort" },
        curhpshort   = { "%s", "curhpshort" },
        perhp        = { "%s%%", "perhp" },
        perhpnosign  = { "%s", "perhpnosign" },
        perpp        = { "%s%%", "perpp" },
        curpp        = { "%s", "curpp" },
        curhp_curpp  = { "%s | %s", "curhpshort", "curpp" },
        perhp_perpp  = { "%s%% | %s%%", "perhp", "perpp" },
        absorb       = { "%s", "absorb" },
        absorbshort  = { "%s", "absorbshort" },
        healabsorb   = { "%s", "healabsorb" },
        healabsorbshort = { "%s", "healabsorbshort" },
        group        = { "%s", "group" },
    }
    -- Identity-only zones: their pieces read name/level, which change only on
    -- identity edges (UNIT_NAME_UPDATE, UNIT_LEVEL, repoints, provider
    -- callbacks) -- Blizzard paints names on UNIT_NAME_UPDATE alone. Not
    -- listed: nametotarget (target names churn) and group (roster-driven,
    -- repainted by the value ticks it always rode).
    local ZONE_IDENTITY = { name = true, levelname = true, namelevel = true, level = true }
    -- Value-class events: a static zone skips these and repaints on anything
    -- else (identity events, ForceUpdate, UnitChanged, PEW, nil = repaint all).
    local VALUE_EVENTS = {
        UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_MAX_HEALTH_MODIFIERS_CHANGED = true,
        UNIT_POWER_UPDATE = true, UNIT_MAXPOWER = true, UNIT_DISPLAYPOWER = true,
        UNIT_ABSORB_AMOUNT_CHANGED = true, UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true,
        Resettle = true, EUI_AbsorbEnd = true, EUI_AbsorbBelt = true,
    }

    --- Resolves a content key to (fmt, piecesArray, static) for a zone, or nil
    --- for "none"/unknown. nametotarget builds its settings-closure separator.
    function ns.ContentToZone(content, prefix, settings)
        if content == "nametotarget" then
            return "%s%s%s%s", { P.name, ns.MakeTgtSepPiece(prefix, settings), P.tgtcol, P.tgtname }
        end
        local def = ZONE_STATIC[content]
        if not def then return nil end
        local pieces = { }
        for i = 2, #def do pieces[#pieces + 1] = P[def[i]] end
        return def[1], pieces, ZONE_IDENTITY[content] or nil
    end

    -- The text painter: renders every registered zone on the frame. Piece
    -- returns route through a scratch table + unpack (tables carry secrets
    -- fine; nothing inspects them). Identity-only zones (name/level) are
    -- skipped on value-class events: the nickname provider chain behind the
    -- name piece was running on every health tick.
    local scratch = {}
    local function PaintText(frame, unit, event)
        local zones = frame._euiTextZones
        if not zones then return end
        local valueOnly = event ~= nil and VALUE_EVENTS[event]
        for i = 1, #zones do
            local z = zones[i]
            if not (valueOnly and z.static) then
                local pieces = z.pieces
                local n = #pieces
                for k = 1, n do scratch[k] = pieces[k](unit) end
                z.fs:SetFormattedText(z.fmt, unpack(scratch, 1, n))
            end
        end
    end
    ns.UF_PaintText = PaintText
    ns.Engine.SetPainter("text", PaintText)

    --- Registers/updates one text zone on a frame: resolves the content key
    --- and stores the def the text painter renders. nil/none content removes
    --- the zone (the position code hides the fontstring separately, as
    --- before). Zones are keyed by fontstring; re-apply replaces in place.
    function ns.SetTextZone(frame, fs, content, prefix, settings)
        local zones = frame._euiTextZones
        if not zones then zones = {}; frame._euiTextZones = zones end
        local fmt, pieces, static
        if content then fmt, pieces, static = ns.ContentToZone(content, prefix, settings) end
        for i = #zones, 1, -1 do
            if zones[i].fs == fs then table.remove(zones, i) end
        end
        if fmt then
            zones[#zones + 1] = { fs = fs, fmt = fmt, pieces = pieces, static = static }
        else
            fs:SetText("")
        end
    end

    --- Raw-zone variant for callers that assemble their own format (the power
    --- percent text's curpp/perpp/smart combinations). nil fmt removes.
    function ns.SetTextZoneRaw(frame, fs, fmt, pieces)
        local zones = frame._euiTextZones
        if not zones then zones = {}; frame._euiTextZones = zones end
        for i = #zones, 1, -1 do
            if zones[i].fs == fs then table.remove(zones, i) end
        end
        if fmt then
            zones[#zones + 1] = { fs = fs, fmt = fmt, pieces = pieces }
        else
            fs:SetText("")
        end
    end
end

local optionsFrame
local optionsCategoryID

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

-- Per-unit frame source resolver. Returns "eui" (spawn skinned frame, default),
-- "blizzard" (don't spawn, leave Blizzard's default in place), or "hidden" (don't
-- spawn, actively disable Blizzard's too). "hidden" has highest precedence so a
-- legacy disabled frame (enabledFrames[unit]==false: Visibility "never" or an
-- "Enable X Frame" toggle off) keeps meaning "no frame at all".
function ns.GetUnitFrameSource(unit)
    if not db or not db.profile then return "eui" end
    if db.profile.enabledFrames[unit] == false then return "hidden" end
    local fs = db.profile.frameSource and db.profile.frameSource[unit]
    if fs == "blizzard" then
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

-- Write a unit's frame source, keeping the legacy enabledFrames flag and per-unit
-- "never" visibility in sync so existing readers stay correct. Only takes full effect
-- after a UI reload (oUF permanently disables the Blizzard frame at spawn, and secure
-- frames can't be created/torn down in combat) -- callers should also prompt a reload.
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
            -- Stash the visible mode so hidden->visible keeps an "in_combat"/"mouseover"
            -- preference. Multi-selection sets stash the same way and MUST also clear,
            -- or they stay authoritative over the forced "never" and the frame keeps showing.
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

-- Cast-bar icon "part of the bar" resolver. True = icon counts inside the cast bar's
-- width (icon inside footprint, fill inset to its right, like Resource Bars). False =
-- icon outside the width. Requires the icon shown; a hidden icon is never "in width".
local function CastIconInWidth(unit, s)
    s = s or GetSettingsForUnit(unit)
    if not s then return true end
    if unit == "player" then
        return s.showPlayerCastIcon ~= false and s.playerCastbarIconInWidth ~= false
    end
    return s.showCastIcon ~= false and s.castbarIconInWidth ~= false
end

-- Whether the cast spell icon is shown at all. Independent of "part of the
-- bar" (CastIconInWidth folds this in already for its own purposes, but
-- LayoutCastbarIcon needs the shown state on its own to know whether a
-- disabled icon should suppress the bar's facing border).
local function CastIconShown(unit, s)
    s = s or GetSettingsForUnit(unit)
    if not s then return true end
    if unit == "player" then
        return s.showPlayerCastIcon ~= false
    end
    return s.showCastIcon ~= false
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

-- Additive X/Y nudge for the cast spell icon. Applies to the icon frame's anchors
-- only -- the bar fill and footprint never move.
local function CastIconOffsets(unit, s)
    s = s or GetSettingsForUnit(unit)
    if not s then return 0, 0 end
    if unit == "player" then
        return s.playerCastIconOffsetX or 0, s.playerCastIconOffsetY or 0
    end
    return s.castIconOffsetX or 0, s.castIconOffsetY or 0
end

-- Anchor the cast spell icon and inset the fill based on whether the icon is part of
-- the bar width. inWidth=true -> icon at the bar's edge, fill inset by icon width
-- (castbarBg becomes the full footprint, so unlock mode/width matching count the icon
-- for free). inWidth=false -> icon hangs outside the bar width.
--
-- Icon HEIGHT anchors to the bar bg's top AND bottom so it always equals the bar
-- height: a live bg:GetHeight() read is unreliable during creation/login (bg not yet
-- at final height/scale). iconH is the configured cast bar height (castbarHeight/
-- playerCastbarHeight), used only for the square WIDTH and matching fill inset so
-- those stay deterministic; falls back to bg:GetHeight().
local function LayoutCastbarIcon(castbar, inWidth, iconH, onRight, offX, offY, iconShown)
    if not castbar then return end
    local bg = castbar:GetParent()
    if not bg then return end
    local side = iconH or bg:GetHeight()
    local iconFrame = castbar._iconFrame
    offX, offY = offX or 0, offY or 0
    if iconFrame then
        iconFrame:ClearAllPoints()
        if inWidth then
            -- Icon inside the footprint, flush with the chosen edge.
            if onRight then
                PP.Point(iconFrame, "TOPRIGHT", bg, "TOPRIGHT", offX, offY)
                PP.Point(iconFrame, "BOTTOMRIGHT", bg, "BOTTOMRIGHT", offX, offY)
            else
                PP.Point(iconFrame, "TOPLEFT", bg, "TOPLEFT", offX, offY)
                PP.Point(iconFrame, "BOTTOMLEFT", bg, "BOTTOMLEFT", offX, offY)
            end
        else
            -- Icon hangs outside the bar, off the chosen edge.
            if onRight then
                PP.Point(iconFrame, "TOPLEFT", bg, "TOPRIGHT", offX, offY)
                PP.Point(iconFrame, "BOTTOMLEFT", bg, "BOTTOMRIGHT", offX, offY)
            else
                PP.Point(iconFrame, "TOPRIGHT", bg, "TOPLEFT", offX, offY)
                PP.Point(iconFrame, "BOTTOMRIGHT", bg, "BOTTOMLEFT", offX, offY)
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

    -- Icon and bar are separate frames, each with its own full 1px border
    -- (PP.CreateBorder at creation, on iconFrame and on castbar). In every
    -- inWidth/onRight combination above they sit flush against each other,
    -- so both draw a strip at the shared seam -- doubling it to 2px. Suppress
    -- the facing edge on each side, same _hideLeft/_hideRight pattern as the
    -- health/power seam elsewhere in this file. Only when truly flush (no
    -- configured icon offset): with an offset there's a real gap, and hiding
    -- both edges would leave it with no border on either side. And only when
    -- the icon is actually shown -- a disabled icon still owns a (hidden)
    -- iconFrame, so blindly suppressing the bar's facing edge here left the
    -- bar with no border at all on that side while the icon is off.
    if iconFrame then
        local iconEdges = PP.GetBorders(iconFrame)
        local barEdges = PP.GetBorders(castbar)
        if iconEdges and barEdges then
            if iconShown and offX == 0 and offY == 0 then
                iconEdges._hideRight = (not onRight) or nil
                iconEdges._hideLeft  = onRight or nil
                barEdges._hideLeft   = (not onRight) or nil
                barEdges._hideRight  = onRight or nil
            else
                iconEdges._hideLeft, iconEdges._hideRight = nil, nil
                barEdges._hideLeft, barEdges._hideRight = nil, nil
            end
            PP.SetBorderSize(iconFrame, 1)
            PP.SetBorderSize(castbar, 1)
        end
    end
end

-- Donor settings table for mini frames (focus > target > player); source of
-- inherited border, texture and font settings.
local function GetMiniDonorSettings()
    local ef = db.profile.enabledFrames
    if ef.focus ~= false and db.profile.focus then return db.profile.focus end
    if ef.target ~= false and db.profile.target then return db.profile.target end
    return db.profile.player
end

-- Boss "Simple Debuff Display" mode: "none"|"left"|"right". Tolerates legacy booleans
-- (true/nil="left", false="none") so existing/imported profiles read correctly with no
-- migration pass. "left"/"right" both force the frame-height-matched single column;
-- only the side differs.
function ns.GetBossSimpleDebuffMode(s)
    local v = s and s.simpleDebuffs
    if v == "none" or v == "left" or v == "right" then return v end
    if v == false then return "none" end
    return "left"  -- nil or legacy true
end

-- Boss Simple Debuff Display X/Y offsets: dedicated simpleDebuffOffsetX/Y if set, else
-- the regular debuff offsets, so existing offsets carry over as simple-mode defaults
-- (zero-migration view; import-safe). Once the cog is edited, dedicated keys take over.
function ns.GetBossSimpleDebuffOffset(s)
    if not s then return 0, 0 end
    local x = s.simpleDebuffOffsetX
    if x == nil then x = s.debuffOffsetX or 0 end
    local y = s.simpleDebuffOffsetY
    if y == nil then y = s.debuffOffsetY or 0 end
    return x, y
end

-- Boss "Simple Buff Display" mode: "none"|"left"|"right". Defaults OFF
-- (nil/false/unknown -> "none"); a stray boolean true reads as "left" (symmetry with the debuff resolver).
function ns.GetBossSimpleBuffMode(s)
    local v = s and s.simpleBuffs
    if v == "none" or v == "left" or v == "right" then return v end
    if v == true then return "left" end
    return "none"
end

-- Boss Simple Buff Display X/Y offsets. Mirrors ns.GetBossSimpleDebuffOffset
-- (simpleBuffOffsetX/Y if set, else regular buff offsets; zero-migration, import-safe).
function ns.GetBossSimpleBuffOffset(s)
    if not s then return 0, 0 end
    local x = s.simpleBuffOffsetX
    if x == nil then x = s.buffOffsetX or 0 end
    local y = s.simpleBuffOffsetY
    if y == nil then y = s.buffOffsetY or 0 end
    return x, y
end

-- Boss aura icon spacing, in PHYSICAL pixels. Simple modes use dedicated keys
-- (simpleBuffSpacing/simpleDebuffSpacing); regular auras use buffSpacing/debuffSpacing.
-- No legacy equivalent, so every variant defaults to 1 independently. Callers convert
-- to coordinate space with PP.FromPixels for physical-pixel-perfect gaps at any scale.
-- (0 and negatives are truthy in Lua, so `or 1` only fills nil.)
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

-- Per-slot Width % of the slot's computed clamp width (100 = normal truncation,
-- above 100 grants extra room). Applied by the position code to the slot
-- FontString's width box.
local function SlotWidthMul(settings, prefix)
    return (settings[prefix .. "WidthPct"] or 100) / 100
end

-- Build the per-slot "Name > Target" indicator tag. The separator is hex-encoded
-- per byte so any user-typed character (commas, parens, multibyte symbols)
-- survives the tag brackets; color rides as "class" or rrggbb hex (default white).
-- (The old content-key -> tag-string mapping lived here; text zones now
-- resolve through ns.ContentToZone and the engine text painter.)

-- Estimated pixel width per text content type, for name truncation. Flat
-- assumptions matching the nameplate system.
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
    level       = 24,  -- "80" / "??"
}
local function EstimateUFTextWidth(content)
    return (ufTextWidths[content] or 0) + UF_TEXT_PADDING
end

-- Apply class color to a FontString based on the unit.
local function ApplyClassColor(fs, unit, useClassColor, customR, customG, customB)
    if not fs then return end
    if useClassColor and unit then
        -- Class color for players (and AI party members), reaction color for NPCs,
        -- matching the health bar and the custom Enemy Colors override. Shared
        -- with the eui-tgtname tag via ns.ResolveUnitNameColor.
        local r, g, b = ns.ResolveUnitNameColor(unit)
        if r then fs:SetTextColor(r, g, b); return end
        -- ResolveUnitNameColor returns nil for a SECRET class token (identity-restricted
        -- units: focus-target, ToT) since it can't be used as a table key or formatted by
        -- the [eui-tgtcol] hex-escape tag it also feeds. SetTextColor accepts secrets
        -- directly, so recover the real color here the same way the health bar does:
        -- the user's custom color when the unit matches a group member, else Blizzard's.
        if UnitIsPlayer(unit) or (UnitInPartyIsAI and UnitInPartyIsAI(unit)) then
            local _, class = UnitClass(unit)
            if issecretvalue(class) then
                local ok, sr, sg, sb = ResolveRestrictedClassColor(unit, class)
                if ok then fs:SetTextColor(sr, sg, sb); return end
            end
        end
    end
    fs:SetTextColor(customR or 1, customG or 1, customB or 1)
end

local UF_ICONS_PATH = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
local CLASS_FULL_SPRITE_BASE = UF_ICONS_PATH .. "class-full\\"
local CLASS_FULL_COORDS = EllesmereUI.CLASS_ICON_SPRITE_COORDS

-- Apply a class icon from the sprite sheet.
local function ApplyClassIconTexture(tex, classToken, style)
    local coords = CLASS_FULL_COORDS[classToken]
    if not coords then return false end
    tex:SetTexture(CLASS_FULL_SPRITE_BASE .. style .. ".tga")
    tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    return true
end


-- Shared portrait element Override (2D texture and 3D model objects; class texture
-- keeps its own). The vendored oUF Update only guid-gates the eventless OnUpdate poll,
-- so every other trigger (onShow, target-changed sweeps, any unit event) repaints
-- unconditionally, re-running SetPortraitTexture + the re-anchor PostUpdate for the
-- SAME unit in heavy combat. This Override repaints only when identity/availability
-- changed, on real appearance events (same-guid model/portrait-file changes), or on an
-- explicit ForceUpdate (mode swaps). Secret guids (instanced-PvP identities) can't be
-- compared, so they fail open to repainting. No unitIsUnit head-check (secret booleans
-- on eventless frames; the gate keeps repaint-on-any-event dispatch cheap). PostUpdate
-- runs only after a real repaint: 2D heals what SetPortraitTexture resets, 3D
-- re-applies zoom after SetUnit -- nothing to heal without a repaint.
local PortraitOverride  -- forward declaration; painter registrations below the definition
function PortraitOverride(self, event, evtUnit)
    local element = self.Portrait
    if not element then return end
    local u = self._euiUnit
    if not u then return end
    if element.PreUpdate then element:PreUpdate(u) end
    local isAvailable = UnitIsConnected(u) and UnitIsVisible(u)
    local guid = UnitGUID(u)
    local changed
    if issecretvalue(guid) or issecretvalue(element.guid) then
        changed = true
    else
        changed = element.guid ~= guid
    end
    local isModel = element:IsObjectType("PlayerModel")
    local hasStateChanged = changed
        or element.state ~= isAvailable
        or event == "UNIT_PORTRAIT_UPDATE"
        -- Model changes only matter to a 3D PlayerModel portrait (its SetUnit
        -- must reload). 2D art follows UNIT_PORTRAIT_UPDATE / PORTRAITS_UPDATED,
        -- the only portrait events Blizzard's own unit frames listen to.
        or (event == "UNIT_MODEL_CHANGED" and isModel)
        or event == "ForceUpdate"
        -- Unit swaps (vehicle enter/exit) always repaint: the swap moment can
        -- paint before the new unit's art/model streams in, and nothing with
        -- a changed guid follows.
        or event == "UnitChanged"
        -- World transitions can reset PlayerModel widget state at the same guid;
        -- repaint once per zone so 3D portraits never come back blank.
        or event == "PLAYER_ENTERING_WORLD"
        -- The repaint above runs mid-loading-screen, where SetPortraitTexture
        -- has no portrait art to hand back yet and paints a blank one. The
        -- client fires PORTRAITS_UPDATED once that art is ready, and it is the
        -- only trigger that follows: the guid and the availability state both
        -- come back unchanged, so without this the blank is what the gate
        -- caches until the next reload. Blizzard's own player portrait (the
        -- character micro button) re-runs SetPortraitTexture on the same event
        -- for the same reason. 2D only: the event says portrait ART is ready,
        -- which the model path does not read, and repainting it would mean a
        -- ClearModel + SetUnit reload every time the client streams a batch.
        or (event == "PORTRAITS_UPDATED" and not isModel)
        -- Frame re-show: PlayerModel widgets DROP their model while hidden
        -- (loading screens hide the unit frames; the PEW fan-out skips hidden
        -- frames, so the re-show is the one trigger that reliably follows --
        -- with guid and availability both reading unchanged, field-traced).
        -- Models only: 2D textures survive Hide/Show.
        or (event == "Show" and isModel)
        -- Blank-model heal: the Show repaint can run before the unit's model
        -- data streams -- SetUnit lands NOTHING (fid nil, field-traced) and no
        -- model event follows. PORTRAITS_UPDATED is the client's "portrait
        -- assets finished streaming" signal and reliably follows; use it to
        -- re-SetUnit ONLY a still-blank model, so loaded models never churn
        -- (the reason the plain-model exclusion above exists).
        or (event == "PORTRAITS_UPDATED" and isModel
            and element.GetModelFileID and element:GetModelFileID() == nil)
    if hasStateChanged then
        if isModel then
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
                element:ClearModel()
                element:SetUnit(u)
                element:SetPortraitZoom(1)
                element:SetPosition(0, 0, 0)
                element:SetCamDistanceScale(camScale)
            end
        elseif element.isClass then
            -- Class sprite lane: the engine painter is the single portrait
            -- dispatch, so class mode paints here too. SetPortraitTexture on
            -- this element would stamp portrait art through the sprite
            -- cell's texcoords (the field-reported weird-colored square);
            -- ApplyClassIconTexture instead re-asserts file + coords, and
            -- re-reading the style here lets art-style changes ride any
            -- repaint. Unit swaps (target changes) land through the same
            -- guid gate as every other portrait mode.
            if isAvailable then
                local _, ct = UnitClass(u)
                if issecretvalue(ct) then ct = nil end
                local uKeyC = UnitToSettingsKey(u)
                local uSC = uKeyC and db.profile[uKeyC]
                ApplyClassIconTexture(element, ct or "WARRIOR",
                    (uSC and uSC.classThemeStyle) or "modern")
            else
                element:SetTexCoord(0.15, 0.85, 0.15, 0.85)
                element:SetTexture([[Interface\Icons\INV_Misc_QuestionMark]])
            end
        else
            if isAvailable then
                SetPortraitTexture(element, u)
            else
                element:SetTexture([[Interface\Icons\INV_Misc_QuestionMark]])
            end
        end
        -- Recovery-preserving stamp: an UNAVAILABLE paint (fallback art --
        -- transition windows, streaming models) must not cache its guid, or
        -- the gate skips every later same-guid trigger and the fallback is
        -- what sticks (vehicle swaps lost the portrait this way). Leaving
        -- the guid unstamped makes the next trigger a guid-change repaint.
        element.guid = isAvailable and guid or nil
        element.state = isAvailable
    end
    if hasStateChanged and element.PostUpdate then
        return element:PostUpdate(u, hasStateChanged)
    end
end

-- Portraits: PortraitOverride was already the complete painter (GUID/state
-- gated 2D/3D handling); the engine becomes its event source. Raid target
-- icon: index lookup straight onto the icon texture.
ns.Engine.SetPainter("portrait", function(frame, unit, event)
    if frame.Portrait and ns.Engine.ElementOn(frame, "Portrait") then
        PortraitOverride(frame, event or "ForceUpdate", unit)
    end
end)
-- Element ForceUpdate stamp: the settings code refreshes portraits through
-- frame.Portrait:ForceUpdate(), and mode swaps replace the Portrait object,
-- so the stamp is re-applied wherever the field is reassigned.
function ns.UF_StampPortraitForceUpdate(frame)
    local p = frame.Portrait
    if not p or p.ForceUpdate then return end
    p.ForceUpdate = function()
        if ns.Engine.ElementOn(frame, "Portrait") then
            PortraitOverride(frame, "ForceUpdate", frame._euiUnit)
        end
    end
end
ns.Engine.SetPainter("raidicon", function(frame, unit)
    if not ns.Engine.ElementOn(frame, "RaidTargetIndicator") then return end
    local element = frame.RaidTargetIndicator
    if not element then return end
    -- The styles create the icon as a bare texture; the marker SHEET must be
    -- assigned before SetRaidTargetIconTexture's texcoords can render (the
    -- old element wiring auto-assigned it on enable -- same file the
    -- nameplate markers use).
    if not element:GetTexture() then
        element:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    end
    local index = UnitExists(unit) and GetRaidTargetIndex(unit) or nil
    if index then
        SetRaidTargetIconTexture(element, index)
        element:Show()
    else
        element:Hide()
    end
end)

-- One-stop engine wiring for a freshly spawned frame: the shared colors
-- table, the castbar owner backref, the channel set derived from the widgets
-- the style actually built, the matching Blizzard-frame suppression, and the
-- first full paint.
function ns.UF_AttachEngineFrame(frame, unit, polled)
    frame.colors = ns.Colors
    -- Smoothing defaults the old element wiring seeded on enable: painters
    -- pass element.smoothing into every SetValue/SetTimerDuration, and the
    -- old build guaranteed Immediate until settings stamped otherwise
    -- (ReloadFrames overrides Health's; Power and Castbar keep this).
    local IMMEDIATE = Enum and Enum.StatusBarInterpolation
        and Enum.StatusBarInterpolation.Immediate
    if frame.Health and not frame.Health.smoothing then
        frame.Health.smoothing = IMMEDIATE
    end
    if frame.Power and not frame.Power.smoothing then
        frame.Power.smoothing = IMMEDIATE
    end
    if frame.Castbar and not frame.Castbar.smoothing then
        frame.Castbar.smoothing = IMMEDIATE
    end
    local channels = {}
    if frame.Health then channels[#channels + 1] = "health" end
    if frame.Power then channels[#channels + 1] = "power" end
    channels[#channels + 1] = "text"
    if frame.HealthPrediction then channels[#channels + 1] = "absorb" end
    if frame.Portrait then
        channels[#channels + 1] = "portrait"
        ns.UF_StampPortraitForceUpdate(frame)
    end
    if frame.Castbar then
        frame.Castbar.__owner = frame
        channels[#channels + 1] = "castbar"
    end
    if frame.RaidTargetIndicator then channels[#channels + 1] = "raidicon" end
    if polled then
        ns.Engine.AttachPolled(frame, unit, channels)
    else
        ns.Engine.Attach(frame, unit, channels)
    end
    ns.Engine.HideBlizzardUnitFrame(unit)
    ns.Engine.RepaintAll(frame, "Spawn")
end

-- Mask and border paths for detached portrait shapes.
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

-- Shared with EllesmereUIUnitFrames_PlayerAuraBars.lua (same addon/ns), which reuses
-- this shape media set for Player Aura Bars' iconShape feature.
ns.PORTRAIT_MASKS   = PORTRAIT_MASKS
ns.PORTRAIT_BORDERS = PORTRAIT_BORDERS
ns.MASK_INSETS      = MASK_INSETS

-- Apply a detached portrait shape (mask + border overlay) to a portrait backdrop;
-- creates the mask/border textures on first call, then updates them.
--   backdrop  : the portrait backdrop frame
--   uSettings : per-unit DB table
--   unitToken : the unit this portrait belongs to ("player", "target", ...)
local function ApplyDetachedPortraitShape(backdrop, uSettings, unitToken)
    -- Mini frames never use detached portraits.
    local isMini = unitToken and (unitToken == "pet" or unitToken == "targettarget" or unitToken == "focustarget" or unitToken:match("^boss%d$"))
    local isDetached = not isMini and ((uSettings and uSettings.portraitStyle) or db.profile.portraitStyle or "attached") == "detached"
    local shape = (uSettings and uSettings.detachedPortraitShape) or "portrait"
    local showBorder = true
    local borderOpacity = ((uSettings and uSettings.detachedPortraitBorderOpacity) or 100) / 100
    local borderColor = (uSettings and uSettings.detachedPortraitBorderColor) or { r = 0, g = 0, b = 0 }
    local useClassColor = (uSettings and uSettings.detachedPortraitClassColor) or false
    local rawBorderSize = (uSettings and uSettings.detachedPortraitBorderSize) or 7
    -- Border art is natively 7px. Scale UP by (7 - rawBorderSize) so the mask
    -- clips the inner portion, leaving rawBorderSize px visible.
    local bExp = 7 - rawBorderSize

    -- Border color; class color overrides the manual color.
    local bR, bG, bB = borderColor.r, borderColor.g, borderColor.b
    if useClassColor then
        local isDark = db and db.profile and db.profile.darkTheme
        if isDark then
            -- Dark mode: always the player's own class color.
            local _, classToken = UnitClass("player")
            if classToken then
                local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken]
                if c then bR, bG, bB = c.r, c.g, c.b end
            end
        elseif unitToken and UnitExists(unitToken) then
            -- Non-dark: the unit's health bar color (class for players, reaction
            -- for NPCs, tapped grey).
            local _, classToken = UnitClass(unitToken)
            if UnitIsPlayer(unitToken) and not issecretvalue(classToken) and classToken then
                local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken]
                if c then bR, bG, bB = c.r, c.g, c.b end
            elseif UnitIsTapDenied and UnitIsTapDenied(unitToken) then
                bR, bG, bB = 0.6, 0.6, 0.6
            else
                local reaction = UnitReaction(unitToken, "player")
                if reaction then
                    -- Prefer oUF's reaction table (carries the custom Enemy Colors
                    -- override) so the border matches the health bar.
                    local c = (ns.Colors and ns.Colors.reaction and ns.Colors.reaction[reaction])
                        or FACTION_BAR_COLORS[reaction]
                    if c then bR, bG, bB = c.r, c.g, c.b end
                end
            end
        else
            -- Fallback: player class color.
            local _, classToken = UnitClass("player")
            if classToken then
                local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken]
                if c then bR, bG, bB = c.r, c.g, c.b end
            end
        end
    end

    -- Not detached: drop the mask and reset texture positions.
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
        -- Detached mode expands these for mask fill; reset to default.
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
        -- Drop mask, border and background.
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
        -- Reset content to fill the backdrop.
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
        -- Inset the mask 1px when the border is visible so scaling cannot make
        -- the mask edge poke out from behind the border art.
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

    -- Hide legacy square border textures if this frame has them.
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
    -- Mask the border too so its inner edge is clipped.
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
    -- Scale the portrait so its visible area fills the mask opening.
    -- MASK_INSETS[shape] = px from mask edge to visible area in the 128px mask.
    -- Content expands to fill the mask; border size does not affect content.
    local insetPx = MASK_INSETS[shape] or 17
    local bw = backdrop:GetWidth()
    local bh2 = backdrop:GetHeight()
    if bw < 1 then bw = 46 end
    if bh2 < 1 then bh2 = 46 end
    local visRatio = (128 - 2 * insetPx) / 128
    local cScale = 1 / visRatio
    -- User art scale, stored as a percentage (100 = default).
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
        -- 3D models ignore SetClipsChildren, so keep them inside the backdrop
        -- bounds. Art scale is not applied to 3D (camera zoom is fixed).
        backdrop._3d:ClearAllPoints()
        PP.Point(backdrop._3d, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
        PP.Point(backdrop._3d, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
    end
end
-- Bottom text bar frame: below the health+power area, above the castbar.
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

    -- Text overlay, above the unified border at frame+10.
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

    local function ApplyBTBTextTags(lc, rc, cc)
        ns.SetTextZone(frame, leftFS, lc, "btbLeft", settings)
        ns.SetTextZone(frame, rightFS, rc, "btbRight", settings)
        ns.SetTextZone(frame, centerFS, cc, "btbCenter", settings)
        ns.UF_PaintText(frame, frame._euiUnit or unit)
    end

    -- Power-color override for power-content text. Mirrors the power bar text
    -- logic: the unit's own power type, white when the token cannot resolve.
    -- ApplyBTBPowerColors re-applies all three slots; it runs at layout time AND
    -- continuously from the power element's PostUpdateColor, so the color survives
    -- tag updates and power-type changes. The per-slot early-out (no power-color
    -- flag) keeps it ~free when unused.
    local function ApplyBTBPowerColor(fs, contentKey, usePowerColor)
        if not fs or not usePowerColor then return end
        if contentKey == "perpp" or contentKey == "curpp" or contentKey == "curhp_curpp" or contentKey == "perhp_perpp" then
            -- Secret-safe per-unit power color: player resolves via the clean
            -- string token; non-player units recover it from the clean integer
            -- power type instead of falling back to white.
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
            PP.Width(leftFS, totalWidth * 0.9 * SlotWidthMul(s, "btbLeft"))
            leftFS:Show()
        else leftFS:Hide() end

        SetFSFont(rightFS, rsz)
        rightFS:ClearAllPoints()
        if rc ~= "none" then
            rightFS:SetJustifyH("RIGHT")
            PP.Point(rightFS, "RIGHT", textOvr, "RIGHT", -5 + (s.btbRightX or 0), s.btbRightY or 0)
            PP.Width(rightFS, totalWidth * 0.9 * SlotWidthMul(s, "btbRight"))
            rightFS:Show()
        else rightFS:Hide() end

        SetFSFont(centerFS, csz)
        centerFS:ClearAllPoints()
        if cc ~= "none" then
            centerFS:SetJustifyH("CENTER")
            PP.Point(centerFS, "CENTER", textOvr, "CENTER", s.btbCenterX or 0, s.btbCenterY or 0)
            PP.Width(centerFS, totalWidth * 0.9 * SlotWidthMul(s, "btbCenter"))
            centerFS:Show()
        else centerFS:Hide() end

        ApplyClassColor(leftFS, unit, s.btbLeftClassColor, s.btbLeftColorR, s.btbLeftColorG, s.btbLeftColorB)
        ApplyClassColor(rightFS, unit, s.btbRightClassColor, s.btbRightColorR, s.btbRightColorG, s.btbRightColorB)
        ApplyClassColor(centerFS, unit, s.btbCenterClassColor, s.btbCenterColorR, s.btbCenterColorG, s.btbCenterColorB)
        -- Power color: after class color, and re-applied continuously from the
        -- power element's PostUpdateColor (btb._applyBTBPowerColors).
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

    -- Class icon overlay on a high-level frame so it renders above the border.
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
        if issecretvalue(classToken) or not classToken then classIconTex:Hide(); return end
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

-- Positioning is handled by Unlock Mode.

local function ApplyFramePosition(frame, unit)
    if not frame or not db.profile.positions[unit] then return end
    local pos = db.profile.positions[unit]
    local x, y = pos.x, pos.y
    -- Snap to the physical pixel grid for deterministic positions across reloads.
    -- CENTER-anchored frames use SnapCenterForDim with actual width/height (preserves
    -- the +0.5 center offset odd-pixel-dimension frames need for whole-pixel edges);
    -- plain SnapForES rounds the center to whole pixels, forcing edges to half pixels
    -- and causing 1px drift on save/exit, spec swap, or profile change.
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

-- Clip container for health + power bars: prevents sub-pixel overflow at UI scales
-- where independent pixel-snapping pushes edges 1px out. Inset by the border
-- thickness so the GPU cannot render bar pixels outside the border.
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
            -- Detached bars reparent onto `frame` itself (not the bar clip), which also
            -- holds the border at frame:GetFrameLevel()+10 (CreateUnifiedBorder/
            -- UpdatePowerBorder). hpLevel+2 would sit under that and let the border
            -- render over a detached power bar dragged onto its edge, so match
            -- CreatePowerBar's detached offset instead.
            frame.Power:SetFrameLevel(frame:GetFrameLevel() + 12)
        else
            -- Power bar must render above the absorb overlay (health level + 1).
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


-- Recalculate every element size after a frame scale change so the stack stays
-- pixel-perfect inside the border. PixelUtil rounds each element independently, so
-- their sum can exceed the frame's snapped total by 1px at some scales; overflow is
-- trimmed off the last element after re-snapping.
local function UpdateBordersForScale(frame, unit)
    if not frame then return end
    local settings = GetSettingsForUnit(unit)
    if not settings then return end
    local borderSize = settings.borderSize or 1

    -- 1) Main frame border textures.
    if frame.unifiedBorder then
        local bc = settings.borderColor or { r = 0, g = 0, b = 0 }
        local textureKey = settings.borderTexture or "solid"
        EllesmereUI.ApplyBorderStyle(frame.unifiedBorder, borderSize, bc.r, bc.g, bc.b, settings.borderAlpha or 1, textureKey, settings.borderTextureOffset, settings.borderTextureOffsetY, settings.borderTextureShiftX, settings.borderTextureShiftY, "unitframes", borderSize)
    end

    -- 2) Gather layout info.
    local ppPos = settings.powerPosition or "below"
    local ppIsAtt = (ppPos == "below" or ppPos == "above")
    local ppIsDet = (ppPos == "detached_top" or ppPos == "detached_bottom")
    local ph = settings.powerHeight or 6
    -- Mini frames (pet/tot/focustarget) have no power bar: no power height.
    local isMini = (unit == "pet" or unit == "targettarget" or unit == "focustarget")
    local powerH = (ppIsAtt and not isMini) and ph or 0

    local btbPos = settings.btbPosition or "bottom"
    local btbIsAtt = (btbPos == "top" or btbPos == "bottom")
    local btbH = (settings.bottomTextBar and btbIsAtt) and (settings.bottomTextBarHeight or 16) or 0

    local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
    if isMini and pStyle == "detached" then pStyle = "attached" end
    local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
    local isAttached = pStyle == "attached"
    -- Use the side the frame was actually built with, so frames like the pet that
    -- hard-code "left" are not treated as "right".
    local pSide = EllesmereUI._ufPortraitSide[frame] or settings.portraitSide or "right"
    local effectiveSide = pSide
    if isAttached and pSide == "top" then effectiveSide = "right" end

    -- Class power above adds height (player only, only if the spec has a resource).
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

    -- 3) Re-snap the frame itself.
    PP.Size(frame, expectedFrameW, expectedFrameH)
    local snappedFrameW = frame:GetWidth()
    local snappedFrameH = frame:GetHeight()

    -- 4) Re-snap portrait and health bar (width axis).
    local healthTargetW = settings.frameWidth
    if frame.Portrait and frame.Portrait.backdrop and showPortrait and isAttached and not isInsideSnap then
        PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
        local snappedPortW = frame.Portrait.backdrop:GetWidth()
        local snappedPortH = frame.Portrait.backdrop:GetHeight()
        -- Trim portrait width if it + health would exceed the frame.
        if snappedPortW + healthTargetW > snappedFrameW + 0.01 then
            PP.Width(frame.Portrait.backdrop, snappedFrameW - healthTargetW)
            snappedPortW = frame.Portrait.backdrop:GetWidth()
        end
        -- Trim portrait height to frame height on overflow.
        if snappedPortH > snappedFrameH + 0.01 then
            PP.Height(frame.Portrait.backdrop, snappedFrameH)
        end
    end

    -- 5) Re-snap health bar height and re-anchor to the snapped portrait width.
    if frame.Health then
        PP.Height(frame.Health, settings.healthHeight)
        -- Keep the health bar flush against the snapped portrait edge.
        if showPortrait and isAttached and frame.Portrait and frame.Portrait.backdrop then
            local snappedPortW = frame.Portrait.backdrop:GetWidth()
            local newXOff = (effectiveSide == "left") and snappedPortW or 0
            local newRightInset = (effectiveSide == "right") and snappedPortW or 0
            frame.Health._xOffset = newXOff
            frame.Health._rightInset = newRightInset
        end
    end

    -- 6) Re-snap power bar.
    if frame.Power and ppPos ~= "none" then
        local pw = settings.frameWidth
        if ppIsDet and (settings.powerWidth or 0) > 0 then
            pw = settings.powerWidth
        end
        PP.Size(frame.Power, pw, ph)
        if ppIsAtt and frame.Health then
            -- Height: health + power must not exceed the bar area.
            local snappedHealthH = frame.Health:GetHeight()
            local snappedPowerH = frame.Power:GetHeight()
            local expectedBarH = settings.healthHeight + ph
            if snappedHealthH + snappedPowerH > expectedBarH + 0.01 then
                PP.Height(frame.Power, snappedPowerH - (snappedHealthH + snappedPowerH - expectedBarH))
            end
            -- Width: match the health bar exactly.
            local snappedHealthW = frame.Health:GetWidth()
            local snappedPowerW = frame.Power:GetWidth()
            if math.abs(snappedPowerW - snappedHealthW) > 0.01 then
                PP.Width(frame.Power, snappedHealthW)
            end
        elseif not ppIsDet then
            -- Non-attached non-detached should not happen; trim width to frame.
            local snappedPowerW = frame.Power:GetWidth()
            if snappedPowerW > snappedFrameW + 0.01 then
                PP.Width(frame.Power, snappedFrameW)
            end
        end
    end

    -- 7) Re-snap BTB.
    if frame.BottomTextBar and settings.bottomTextBar and btbIsAtt then
        PP.Size(frame.BottomTextBar, expectedFrameW, settings.bottomTextBarHeight or 16)
        local snappedBtbW = frame.BottomTextBar:GetWidth()
        local snappedBtbH = frame.BottomTextBar:GetHeight()
        -- Width: trim to frame width.
        if snappedBtbW > snappedFrameW + 0.01 then
            PP.Width(frame.BottomTextBar, snappedFrameW)
        end
        -- Height: the full stack must fit inside the frame height.
        local usedH = cpAboveH
        if frame.Health then usedH = usedH + frame.Health:GetHeight() end
        if frame.Power and ppIsAtt then usedH = usedH + frame.Power:GetHeight() end
        if usedH + snappedBtbH > snappedFrameH + 0.01 then
            PP.Height(frame.BottomTextBar, snappedBtbH - (usedH + snappedBtbH - snappedFrameH))
        end
    end

    -- 8) Castbar: re-snap background width + border textures.
    if frame.Castbar then
        local castbarBg = frame.Castbar:GetParent()
        if castbarBg then
            -- Trim castbar bg width to the frame width, only when the user has no
            -- custom width (castbarWidth > 0 = custom). Use the settings resolved
            -- from this function's unit parameter, NOT frame._euiUnit: boss preview
            -- swaps frame._euiUnit to "player", which has no castbarWidth, and the
            -- trim would eat the boss castbar's custom width while previewing.
            local cbW = castbarBg:GetWidth()
            local hasCustomW = (settings.castbarWidth or 0) > 0
            if not hasCustomW and cbW > snappedFrameW + 0.01 then
                PP.Width(castbarBg, snappedFrameW)
            end
            -- Re-snap border textures.
            if PP.GetBorders(castbarBg) then
                PP.SetBorderSize(castbarBg, 1)
                frame.Castbar:ClearAllPoints()
                PP.Point(frame.Castbar, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
                PP.Point(frame.Castbar, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)
            end
        end
    end

    -- 9) Inset the clip container by half a physical pixel (sub-pixel, invisible),
    -- guaranteeing the GPU clips any StatusBar texture rounding past the frame edge.
    -- Skip the inset on the portrait side so the health bar stays flush with the
    -- portrait (which anchors to the frame, not _barClip).
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
        -- Re-anchor the health bar to the clip so coordinates stay consistent.
        local xOff = frame.Health._xOffset or 0
        local rInset = frame.Health._rightInset or 0
        local topOff = frame.Health._topOffset or 0
        frame.Health:ClearAllPoints()
        frame.Health:SetPoint("TOPLEFT", frame._barClip, "TOPLEFT", xOff, PP.Scale(-topOff))
        frame.Health:SetPoint("RIGHT", frame._barClip, "RIGHT", -rInset, 0)
        PP.Height(frame.Health, settings.healthHeight)
    end
end

-- All sizing is width/height based; positioning is owned by Unlock Mode.

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
    -- Snap returned dimensions to the physical pixel grid so width-matching and
    -- the cog display agree with the rendered frame size.
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

-- Fill-texture rotation, DERIVED -- never set on its own, so it cannot go stale against
-- the bar's axis or a texture swap. Two texture families need opposite treatment on a
-- vertical bar: stretch textures (shield.tga, striped3, blizzard, WHITE8X8, every
-- health texture) are one image scaled to the fill rect, authored wide-and-short, so on
-- a tall bar they must be ROTATED or they smear; tiled textures (stripedReversed, the
-- large* stripe sets, striped-maxhp, modern absorb) repeat at native pixel size on both
-- axes and already read correctly at any bar shape, so rotating them fights the tiling
-- and must NOT happen. Tiling is read back off the live fill texture rather than passed
-- in, so this stays correct no matter which style function last touched the bar.
function ns.ApplyFillRotation(bar)
    if not (bar and bar.SetRotatesTexture) then return end
    local vert = bar.GetOrientation and bar:GetOrientation() == "VERTICAL"
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local tiled = fill and ((fill.GetHorizTile and fill:GetHorizTile())
                         or (fill.GetVertTile and fill:GetVertTile()))
    bar:SetRotatesTexture((vert and not tiled) and true or false)
end

-- Vertical health fill. SetOrientation drives the fill AXIS; healthReverseFill still
-- flips direction WITHIN that axis (horizontal: left-right/right-left; vertical:
-- bottom-top/top-bottom). On ns so the options preview paints the same way.
function ns.ApplyHealthOrientation(bar, settings)
    if not bar then return end
    local vert = (settings and settings.healthVerticalFill) and true or false
    bar:SetOrientation(vert and "VERTICAL" or "HORIZONTAL")
    ns.ApplyFillRotation(bar)
    return vert
end

local function CreateHealthBar(frame, unit, height, xOffset, settings, rightInset)
    height = height or settings.healthHeight
    xOffset = xOffset or 0
    rightInset = rightInset or 0

    -- Power bar "above" pushes the health bar down by the power bar height.
    local ppPos = settings.powerPosition or "below"
    local powerAboveOff = (ppPos == "above") and (settings.powerHeight or 0) or 0

    local health = CreateFrame("StatusBar", nil, frame)
    health:SetFrameStrata(frame:GetFrameStrata())
    health:SetFrameLevel(frame:GetFrameLevel() + 2)
    -- Two-point horizontal anchoring: width derives from the frame, so it can
    -- never exceed the frame boundary regardless of pixel-snapping rounding.
    PP.Point(health, "TOPLEFT", frame, "TOPLEFT", xOffset, -powerAboveOff)
    PP.Point(health, "RIGHT", frame, "RIGHT", -rightInset, 0)
    PP.Height(health, height)
    health._xOffset = xOffset  -- class power repositioning
    health._rightInset = rightInset  -- class power repositioning
    health._topOffset = powerAboveOff  -- SnapLayout re-anchoring
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
    ns.ApplyHealthOrientation(health, settings)
    ApplyDarkTheme(health, unit)

    -- Smooth bar interpolation (opt-in).
    if settings.smoothBars then
        health.smoothing = Enum and Enum.StatusBarInterpolation
            and Enum.StatusBarInterpolation.ExponentialEaseOut
    end

    return health
end

-- Shield texture. DO NOT change this path; it is the one that resolves.
local ABSORB_SHIELD_TEX = "Interface\\AddOns\\EllesmereUIUnitFrames\\Media\\shield.tga"

-- Absorb bar style textures and alpha values.
local ABSORB_STYLE_TEX = {
    striped         = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped3.tga",
    stripedReversed = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-5-reversed.png",
    stripedThick    = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-thick.png",
    stripedThickR   = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-thick-r.png",
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

-- Absorb-style key -> texture path. Built-ins come from ABSORB_STYLE_TEX; "sm:"
-- SharedMedia keys (shared with the Bar Texture dropdown, appended into
-- healthBarTextures by AppendSharedMediaTextures) fall through to the health-bar
-- lookup. Shared by the live render and the options preview so an SM key paints identically.
function ns.ResolveAbsorbStyleTex(style, fallback)
    return ABSORB_STYLE_TEX[style]
        or (EllesmereUI.ResolveTexturePath and EllesmereUI.ResolveTexturePath(healthBarTextures, style, fallback))
        or fallback
end

-- Effective absorb opacity: per-unit absorbOpacity once set, else legacy behavior
-- (clean uses absorbCleanAlpha, other styles a fixed 0.8). Read-time fallback, no migration.
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
    -- These styles are repeating tiles; striped3 is a stretch texture (do NOT
    -- change how it renders).
    local tiled = (style == "stripedReversed" or style == "stripedThick" or style == "stripedThickR" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR")
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
    -- New fill object + tiling state: re-derive rotation (stretch styles rotate
    -- on a vertical bar, tiled ones must not).
    ns.ApplyFillRotation(absorbBar)
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
        ns.ApplyFillRotation(fw)
    end
end

-- Heal absorb styling (mirrors the raid frames Absorbs section). Defaults are
-- clean white8x8, red, 0.65 alpha.
local function ApplyHealAbsorbStyle(haBar, style, settings)
    if not haBar then return end
    local tex = ns.ResolveAbsorbStyleTex(style, "Interface\\Buttons\\WHITE8X8")
    local alpha = ((settings and settings.healAbsorbOpacity) or 65) / 100
    local hc = (settings and settings.healAbsorbColor) or { r = 0.8, g = 0.15, b = 0.15 }
    -- The "Large Outlined Stripes" styles are pre-colored; render them untinted.
    if style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" then hc = { r = 1, g = 1, b = 1 } end
    local tiled = (style == "stripedReversed" or style == "stripedThick" or style == "stripedThickR" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR")
    local mask = haBar._absorbMask
    haBar:SetStatusBarTexture(tex)
    haBar:SetStatusBarColor(hc.r or 0.8, hc.g or 0.15, hc.b or 0.15, alpha)
    local fill = haBar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 2)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
        if mask then fill:AddMaskTexture(mask) end
    end
    ns.ApplyFillRotation(haBar)
end

-- Two-segment absorb rendering via dynamic clip frames, works with secret-valued
-- absorbs: the value can't be split in Lua (min/subtract on secrets is blocked), so
-- STATUSBAR CLIPPING does the math visually. curClip bounds hpBar.LEFT->healthTexture.RIGHT
-- (dynamic); missClip bounds healthTexture.RIGHT->hpBar.RIGHT (dynamic). The shield
-- fills RIGHTWARD first (into missing health) and only backfills into the filled
-- portion once absorb exceeds missing health.
--   forward bar (primary): child of missClip, forward fill, TOPLEFT at
--     healthTexture.TOPRIGHT, width = hpBar width. Fills rightward by
--     (absorbAmt/maxHealth)*hpWidth; missClip cuts past hpBar.RIGHT, so visible width
--     is exactly min(absorb, missing).
--   backfill bar (overflow): child of curClip, reverse fill, TOPRIGHT at hpBar.TOPRIGHT,
--     width = hpBar width. Fills leftward from hpBar.RIGHT; curClip cuts past
--     healthTexture.RIGHT, so visible width is exactly max(0, absorb-missing) -- only
--     shows on overflow.
-- Both bars get the raw (secret-safe) absorbAmt via SetValue; no Lua arithmetic on it
-- ever happens. Wired into oUF via HealthPrediction.Override so oUF keeps event
-- registration (UNIT_HEALTH, UNIT_ABSORB_AMOUNT_CHANGED, ...) and enable/disable.

-- Re-anchor existing absorb bars for the current fill state (reverse + axis).
-- Called from the live-update path on a reverse/vertical fill toggle.
-- `settingsOverride` lets the creation path pass the settings table it already
-- holds, for frames whose ._euiUnit is not resolvable yet.
local function UpdateAbsorbBarReverseFill(frame, isReversed, settingsOverride)
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

    -- Placement (mirrors the raid frames Absorbs section):
    --   overlay = backfill into the filled health from the HP edge (default)
    --   right   = full bar, fill from the frame's right edge
    --   left    = full bar, fill from the frame's left edge
    local s = settingsOverride or GetSettingsForUnit(frame._euiUnit)
    local absorbMode = (s and s.absorbEdgeMode) or "overlay"
    local healMode = (s and s.healAbsorbEdgeMode) or "overlay"
    -- Overshield "From Left" (overlay placement only): the excess grows from
    -- the bar's ORIGIN edge (left; right when reverse-filled; bottom/top on
    -- the vertical axis) instead of hanging off the fill edge. Mechanism:
    -- the Overlay Reverse fill-texture anchors with the OPPOSITE fill
    -- direction -- the bar's origin end sits one bar-length before the fill
    -- edge, so the clip shows exactly the absorb exceeding missing health,
    -- emerging from the frame's origin edge. nil overshieldMode falls back
    -- to the legacy showOvershield boolean (saved toggles keep meaning).
    local osm = s and s.overshieldMode
    if osm == nil then osm = (s and s.showOvershield == false) and "never" or "always" end
    local osFromLeft = osm == "fromleft"

    -- Vertical fill: the whole HP cluster rotates with the health bar. Every anchor
    -- below is the horizontal layout with its axis swapped -- the health fill's RIGHT
    -- edge (the "HP edge" shields/heal absorb hang off) becomes its TOP edge, reverse
    -- fill flips it to BOTTOM. Edge modes keep their key names: "right" = far edge of
    -- the fill axis (top when vertical), "left" = near edge (bottom when vertical).
    local isVert = (s and s.healthVerticalFill) and true or false
    ab._isVert = isVert
    local ha = ab._healAbsorb
    local healClip = ab._healClip
    -- Indexed, not ipairs: ha can be nil and ipairs would stop at the hole.
    local axisBars = { ab, fw, ha }
    for i = 1, 3 do
        local bar = axisBars[i]
        if bar then
            bar:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
            ns.ApplyFillRotation(bar)  -- rotate stretch styles only
        end
    end

    curClip:ClearAllPoints()
    missClip:ClearAllPoints()
    ab:ClearAllPoints()
    fw:ClearAllPoints()

    if isVert then
        -- missClip + forward bar always use the overlay layout; in the edge modes the
        -- full-bar backfill shows the whole absorb and the Override hides fw.
        if isReversed then
            missClip:SetPoint("TOPLEFT",     hpTex, "BOTTOMLEFT",  0, 1)
            missClip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
            fw:SetReverseFill(true)
            fw:SetPoint("TOPLEFT",  hpTex, "BOTTOMLEFT",  0, 0)
            fw:SetPoint("TOPRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
        else
            missClip:SetPoint("BOTTOMLEFT", hpTex, "TOPLEFT",  0, -1)
            missClip:SetPoint("TOPRIGHT",   hpBar, "TOPRIGHT", 0, 0)
            fw:SetReverseFill(false)
            fw:SetPoint("BOTTOMLEFT",  hpTex, "TOPLEFT",  0, 0)
            fw:SetPoint("BOTTOMRIGHT", hpTex, "TOPRIGHT", 0, 0)
        end

        -- Shield absorb placement.
        if absorbMode == "right" or absorbMode == "left" then
            curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",     0, 0)
            curClip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
            if absorbMode == "left" then
                ab:SetReverseFill(false)
                ab:SetPoint("BOTTOMLEFT",  hpBar, "BOTTOMLEFT",  0, 0)
                ab:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
            else
                ab:SetReverseFill(true)
                ab:SetPoint("TOPLEFT",  hpBar, "TOPLEFT",  0, 0)
                ab:SetPoint("TOPRIGHT", hpBar, "TOPRIGHT", 0, 0)
            end
        elseif absorbMode == "overlayReverse" then
            -- Overlay Reverse: the WHOLE absorb fills from the health fill's
            -- leading edge back INTO the fill; the filled-region clip masks
            -- any excess past empty, so shields larger than current health
            -- never escape the fill (fw hidden by the Override, like the edge
            -- modes). Axis-swapped for vertical, mirrored for reversed fill.
            if isReversed then
                curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",     0, 0)
                curClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
                ab:SetReverseFill(false)
                ab:SetPoint("BOTTOMLEFT",  hpTex, "BOTTOMLEFT",  0, 0)
                ab:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
            else
                curClip:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
                curClip:SetPoint("TOPRIGHT",   hpTex, "TOPRIGHT",   0, 0)
                ab:SetReverseFill(true)
                ab:SetPoint("TOPLEFT",  hpTex, "TOPLEFT",  0, 0)
                ab:SetPoint("TOPRIGHT", hpTex, "TOPRIGHT", 0, 0)
            end
        elseif isReversed then
            curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",       0, 0)
            curClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT",   0, 0)
            if osFromLeft then
                ab:SetReverseFill(true)
                ab:SetPoint("BOTTOMLEFT",  hpTex, "BOTTOMLEFT",  0, 0)
                ab:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
            else
                ab:SetReverseFill(false)
                ab:SetPoint("BOTTOMLEFT",  hpBar, "BOTTOMLEFT",  0, 0)
                ab:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
            end
        else
            curClip:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
            curClip:SetPoint("TOPRIGHT",   hpTex, "TOPRIGHT",   0, 0)
            if osFromLeft then
                ab:SetReverseFill(false)
                ab:SetPoint("TOPLEFT",  hpTex, "TOPLEFT",  0, 0)
                ab:SetPoint("TOPRIGHT", hpTex, "TOPRIGHT", 0, 0)
            else
                ab:SetReverseFill(true)
                ab:SetPoint("TOPLEFT",  hpBar, "TOPLEFT",  0, 0)
                ab:SetPoint("TOPRIGHT", hpBar, "TOPRIGHT", 0, 0)
            end
        end

        -- Heal absorb placement (own clip frame, same rules).
        if healClip then
            healClip:ClearAllPoints()
            if healMode == "right" or healMode == "left" then
                healClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",     0, 0)
                healClip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
            elseif isReversed then
                healClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",     0, 0)
                healClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
            else
                healClip:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
                healClip:SetPoint("TOPRIGHT",   hpTex, "TOPRIGHT",   0, 0)
            end
        end
        if ha then
            ha:ClearAllPoints()
            if healMode == "right" then
                ha:SetReverseFill(true)
                ha:SetPoint("TOPLEFT",  hpBar, "TOPLEFT",  0, 0)
                ha:SetPoint("TOPRIGHT", hpBar, "TOPRIGHT", 0, 0)
            elseif healMode == "left" then
                ha:SetReverseFill(false)
                ha:SetPoint("BOTTOMLEFT",  hpBar, "BOTTOMLEFT",  0, 0)
                ha:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
            elseif isReversed then
                ha:SetReverseFill(false)
                ha:SetPoint("BOTTOMLEFT",  hpTex, "BOTTOMLEFT",  0, 0)
                ha:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
            else
                ha:SetReverseFill(true)
                ha:SetPoint("TOPLEFT",  hpTex, "TOPLEFT",  0, 0)
                ha:SetPoint("TOPRIGHT", hpTex, "TOPRIGHT", 0, 0)
            end
        end
        return
    end

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
    elseif absorbMode == "overlayReverse" then
        -- Overlay Reverse: the WHOLE absorb fills from the health fill's
        -- leading edge back INTO the fill; the filled-region clip masks any
        -- excess past empty (fw hidden by the Override, like the edge modes).
        if isReversed then
            curClip:SetPoint("TOPRIGHT",   hpBar, "TOPRIGHT",   0, 0)
            curClip:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMLEFT", 0, 0)
            ab:SetReverseFill(false)
            ab:SetPoint("TOPLEFT",    hpTex, "TOPLEFT",    0, 0)
            ab:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMLEFT", 0, 0)
        else
            curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",     0, 0)
            curClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
            ab:SetReverseFill(true)
            ab:SetPoint("TOPRIGHT",    hpTex, "TOPRIGHT",    0, 0)
            ab:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
        end
    elseif isReversed then
        curClip:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT", 0, 0)
        curClip:SetPoint("BOTTOMLEFT",  hpTex, "BOTTOMLEFT", 0, 0)
        if osFromLeft then
            ab:SetReverseFill(true)
            ab:SetPoint("TOPLEFT",    hpTex, "TOPLEFT",    0, 0)
            ab:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMLEFT", 0, 0)
        else
            ab:SetReverseFill(false)
            ab:SetPoint("TOPLEFT",    hpBar, "TOPLEFT",    0, 0)
            ab:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
        end
    else
        curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",  0, 0)
        curClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
        if osFromLeft then
            ab:SetReverseFill(false)
            ab:SetPoint("TOPRIGHT",    hpTex, "TOPRIGHT",    0, 0)
            ab:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
        else
            ab:SetReverseFill(true)
            ab:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT",    0, 0)
            ab:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- Heal absorb placement, independent of shield absorb. It has its OWN clip
    -- frame (ab._healClip) so right/left span the full bar (filled + missing
    -- health) while overlay stays clipped to filled health.
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
            -- Overlay: eat into the filled health from the HP edge, mirrored for
            -- reverse-filled health bars.
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
-- of the health bar; "top*"/"bottom*" sit inside at the matching edge, drawn just
-- above the absorb texture; "aboveAbsorb"/"belowAbsorb" (heal bar only) sit flush
-- against the Absorb Bar, derived from its POSITION (not its live visibility, so
-- they never shift). "*Right" fills from the right edge. `absorbLevel` is the
-- absorb-overlay frame level (inside strips render at +1).
ns.UF_ApplyStripBarLayout = function(stripBar, hp, position, height, absorbLevel, absorbPos, absorbHeight)
    if not stripBar or not hp then return end
    stripBar:ClearAllPoints()
    stripBar:SetHeight(PP.Scale(height or 4))
    local insideLevel = (absorbLevel or (hp:GetFrameLevel() + 1)) + 1
    if position == "aboveAbsorb" then
        absorbPos = absorbPos or "none"
        local leftPoint, rightPoint, yOff = "TOPLEFT", "TOPRIGHT", 0
        if absorbPos == "aboveRight" or absorbPos == "aboveLeft" then
            yOff = PP.Scale(absorbHeight or 4)
        elseif absorbPos == "bottomRight" or absorbPos == "bottomLeft" then
            leftPoint, rightPoint = "BOTTOMLEFT", "BOTTOMRIGHT"
            yOff = PP.Scale(absorbHeight or 4)
        end
        stripBar:SetReverseFill(absorbPos ~= "aboveLeft" and absorbPos ~= "topLeft" and absorbPos ~= "bottomLeft")
        stripBar:SetPoint("BOTTOMLEFT", hp, leftPoint, 0, yOff)
        stripBar:SetPoint("BOTTOMRIGHT", hp, rightPoint, 0, yOff)
        stripBar:SetFrameLevel(insideLevel)
    elseif position == "belowAbsorb" then
        absorbPos = absorbPos or "none"
        if absorbPos == "bottomRight" or absorbPos == "bottomLeft" then
            stripBar:SetReverseFill(absorbPos == "bottomRight")
            stripBar:SetPoint("TOPLEFT",  hp, "BOTTOMLEFT",  0, 0)
            stripBar:SetPoint("TOPRIGHT", hp, "BOTTOMRIGHT", 0, 0)
            stripBar:SetFrameLevel(insideLevel)
            return
        end
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
    elseif position == "bottomRight" or position == "bottomLeft" then
        stripBar:SetReverseFill(position == "bottomRight")
        stripBar:SetPoint("BOTTOMLEFT",  hp, "BOTTOMLEFT",  0, 0)
        stripBar:SetPoint("BOTTOMRIGHT", hp, "BOTTOMRIGHT", 0, 0)
        stripBar:SetFrameLevel(insideLevel)
    else
        stripBar:SetReverseFill(position == "aboveRight")
        stripBar:SetPoint("BOTTOMLEFT",  hp, "TOPLEFT",  0, 0)
        stripBar:SetPoint("BOTTOMRIGHT", hp, "TOPRIGHT", 0, 0)
        stripBar:SetFrameLevel(hp:GetFrameLevel() + 3)
    end
end

-- Armed-frames absorb belt (mirror of the Raid Frames one): covers the ONE
-- absorb transition with no event at all -- an aura-granted shield expiring
-- on its TIMER on an unhit, topped unit (VDH Infernal Strike field class).
-- One shared 0.5s ticker exists only while some hosted frame is armed; each
-- sweep repaints only stale-painted armed frames and cancels itself when the
-- set empties. Zero event registrations, zero cost with no shields up.
do
    local armed = {}
    local belt
    function ns.UF_AbArm(frame)
        frame._absActive = true
        armed[frame] = true
        if not belt and C_Timer then
            belt = C_Timer.NewTicker(0.5, function()
                local now = GetTime()
                local any = false
                for f in pairs(armed) do
                    any = true
                    if (now - (f._absPaintAt or 0)) > 0.45 then
                        local hp = f.HealthPrediction
                        local ov = hp and hp.Override
                        if ov then ov(f, "EUI_AbsorbBelt", f._euiUnit) end
                    end
                end
                if not any then belt:Cancel(); belt = nil end
            end)
        end
    end
    function ns.UF_AbDisarm(frame)
        -- Armed -> clear is the moment a shield ended; if it ended with no
        -- absorb event (the timer-expiry class this belt exists for), any
        -- long-form Absorb text zone is showing the dead amount. One text
        -- recompose here keeps those zones honest WITHOUT the text channel
        -- riding UNIT_AURA. No-op frames early-return on their zone list.
        if frame._absActive and ns.UF_PaintText then
            ns.UF_PaintText(frame, frame._euiUnit, "EUI_AbsorbEnd")
        end
        frame._absActive = false
        armed[frame] = nil
    end
end

local function CreateAbsorbBar(frame, unit, settings)
    if not frame.Health then return end

    local hpBar = frame.Health

    -- Mask texture: constrains absorb rendering to exact health bar bounds at the
    -- GPU level, preventing the subpixel bleed where absorb textures extend 1px
    -- outside the health bar at some frame positions.
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

    -- Heal absorb bar: overlays filled-health in red, reverse-filling from the health
    -- texture edge inward. Has its OWN clip frame (not the shield's curClip) so
    -- placement is independent: overlay clips to filled health, right/left span the
    -- FULL bar. Bounds set per healAbsorbEdgeMode in UpdateAbsorbBarReverseFill.
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

    -- Black backing behind the heal-absorb texture (opacity via healAbsorbBgOpacity),
    -- drawn UNDER the fill (ARTWORK sublevel 1 < fill's 2), masked + SetAllPoints'd to
    -- the fill rect each update so it tracks the secret heal-absorb amount.
    local haBg = healAbsorbBar:CreateTexture(nil, "ARTWORK", nil, 1)
    haBg:SetColorTexture(0, 0, 0, 0.15)
    if absorbMask then haBg:AddMaskTexture(absorbMask) end
    haBg:Hide()
    healAbsorbBar._bg = haBg

    -- Absorb Bar + Heal Absorb Bar: separate strips (mirrors Raid Frames) at a
    -- configurable position, parented to the frame so "above" positions can sit
    -- outside the health bar. Created hidden; the Override drives them.
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

    -- Attach extras to the backfill (main) bar so anything referencing
    -- HealthPrediction.damageAbsorb can hide/show both segments together.
    backfillBar._forward      = forwardBar
    backfillBar._healAbsorb   = healAbsorbBar
    backfillBar._topBar       = absorbTopBar
    backfillBar._healTopBar   = healAbsorbTopBar
    backfillBar._hpBar        = hpBar
    backfillBar._curClip      = curClip
    backfillBar._healClip     = healClip
    backfillBar._missClip     = missClip
    backfillBar._absorbMask   = absorbMask
    backfillBar._isReversed   = isReversed

    -- Raise the power bar above the absorb overlay.
    local power = frame and frame.Power
    if power then
        power:SetFrameLevel(math.max(power:GetFrameLevel(), hpBar:GetFrameLevel() + 2))
    end

    backfillBar:HookScript("OnHide", function()
        forwardBar:Hide()
        healAbsorbBar:Hide()
    end)

    -- Named local so profilers attribute this hot painter (it traced as the
    -- "(anonymous) :5228" row); assigned into HealthPrediction below.
    local UF_AbsorbOverride
    UF_AbsorbOverride = function(self, event, updUnit)
            if self._euiUnit ~= updUnit then return end

            -- Incoming-heal prediction is never rendered on unit frames, so its frequent
            -- healer-cast-driven events change nothing we paint; absorb/health changes
            -- always arrive via their own events, so skipping cannot strand state.
            if event == "UNIT_HEAL_PREDICTION" then return end

            -- Arm on the dedicated absorb events (plainly observable even
            -- while values are secret). Value-only health chatter is not
            -- delivered to this channel at all (engine list); max changes
            -- repaint ONLY while a shield/heal-absorb is known active --
            -- with no absorb, a range change moves nothing visible.
            -- Repoints, ForceUpdate and the belt always paint and re-derive
            -- the flag below. Mirror of the RF gate.
            if event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
                ns.UF_AbArm(self)
            elseif event == "UNIT_MAXHEALTH" and not self._absActive then
                return
            end

            -- Drive the "Absorb Short" health-text gate(s): feed the raw absorb so the
            -- clip reveals/collapses, AND refresh the text in LOCKSTEP so it never
            -- flashes a stale "0" (oUF tags update on a throttled cycle, lagging the
            -- synchronous clip reveal by a frame). Runs before the bar-style early
            -- return so it works with the absorb BAR disabled. The gate must move on
            -- EVERY update, not only absorb events: volatile units (target/focus/boss/
            -- pet) get re-pointed with no absorb event at all (target switch, OnShow,
            -- ForceUpdate), and a dying unit drops its shield without one either -- the
            -- TAG re-evaluates on those paths and lands on "0", so a gate still held
            -- open by the PREVIOUS unit's shield would leave a stuck "0". Max-health
            -- events skip the text refresh (absorb text only changes on an absorb event,
            -- which does its own lockstep SetText). Secret-safe: absorb only reaches SetValue
            -- and AbbreviateNumbers, never a zero comparison. Each gate feeds its own
            -- source: shield gates use total absorbs, heal gates (g._euiHealGate) total
            -- heal absorbs, fetched lazily once.
            local shieldAmt, healAmt
            if self._absGate then
                local syncText = (event ~= "UNIT_MAXHEALTH")
                local fsZone
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
                        if syncText then
                            fsZone = fsZone or { left = self.LeftText, right = self.RightText, center = self.CenterText, extra = self.ExtraText }
                            local fs = fsZone[zone]
                            if fs then
                                local cfg = _G._EUI_AbbrevDecimalCfg
                                fs:SetText(cfg and AbbreviateNumbers(amt, cfg) or AbbreviateNumbers(amt))
                            end
                        end
                    end
                end
            end

            local element = self.HealthPrediction
            local ab = element.damageAbsorb
            if not ab then return end
            local fw   = ab._forward
            local hp   = ab._hpBar
            if not hp then return end

            -- Heal absorb renders independently of shield absorb: shield "none" hides
            -- only the shield segments, and the whole update is skipped only when BOTH
            -- are off, so unit events can't re-Show() bars ReloadFrames hid. (Heal
            -- Absorb Style defaults to "clean", so it shows even with shield "none".)
            local s = GetSettingsForUnit(updUnit)
            -- Boss frames have no absorb settings of their own: render with the TARGET
            -- frame's styling (donor convention), behind "Show on Boss Frames" in the
            -- absorb cog (nil = enabled).
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

            -- Direct pair, matching PaintHealth's scale: the health bar runs raw
            -- UnitHealthMax, and every absorb sink below is a StatusBar with a
            -- (0, maxHealth) range that clamps oversized shields visually, so a
            -- detailed-prediction calculator adds fetches without changing a pixel.
            -- The gate block above may have fetched the shield total already.
            local maxHealth = UnitHealthMax(updUnit) or 0
            local absorbAmt = shieldAmt or (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(updUnit)) or 0

            -- Lean-flag derivation + belt stamp (mirror of Raid Frames): a
            -- fresh PLAIN all-zero read disarms the head gate; secret reads
            -- keep it armed (fail-open to today's always-paint in combat).
            self._absPaintAt = GetTime()
            local haAmtD = healAmt or (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(updUnit)) or 0
            local isSecD = issecretvalue
            if (isSecD and (isSecD(absorbAmt) or isSecD(haAmtD)))
               or (absorbAmt or 0) > 0 or (haAmtD or 0) > 0 then
                if not self._absActive then ns.UF_AbArm(self) end
            else
                ns.UF_AbDisarm(self)
            end

            local hpW, hpH = hp:GetWidth(), hp:GetHeight()
            -- Identical-state short-circuit (RF's memo, ported): chatter
            -- events with unchanged values skip the whole paint below.
            -- Identity/settings/belt paints bypass the skip; any secret input
            -- fails open to painting and poisons the memo for the next plain
            -- pass (exactly the RF contract).
            if isSecD and (isSecD(absorbAmt) or isSecD(maxHealth) or isSecD(haAmtD)) then
                ab._mAbs = nil
            elseif event ~= "ForceUpdate" and event ~= "Resettle" and event ~= "EUI_AbsorbBelt"
               and ab._mAbs == absorbAmt and ab._mHeal == haAmtD
               and ab._mMax == maxHealth and ab._mW == hpW and ab._mH == hpH then
                return
            else
                ab._mAbs, ab._mHeal, ab._mMax = absorbAmt, haAmtD, maxHealth
                ab._mW, ab._mH = hpW, hpH
            end
            -- Bars track the health-bar size; size-gated (sizes never secret).
            if ab._szW ~= hpW or ab._szH ~= hpH then
                ab._szW = hpW; ab._szH = hpH
                ab:SetWidth(hpW); ab:SetHeight(hpH)
                if fw then fw:SetWidth(hpW); fw:SetHeight(hpH) end
            end

            -- Strip bars (mirrors Raid Frames): independent of the overlay styles.
            if topBar then
                if barOn then
                    local bc = (s and s.absorbBarColor) or { r = 1, g = 1, b = 1 }
                    local bh = (s and s.absorbBarHeight) or 4
                    -- Re-layout only on position/height change (no SetPoint churn).
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
                    healTopBar:SetValue(haAmtD)
                    healTopBar:Show()
                else
                    healTopBar:Hide()
                end
            end

            -- Re-anchor when placement settings change. Key starts nil, so this also
            -- applies the saved placement on the first update. Fill AXIS belongs in the
            -- key too: the settings-apply path already re-anchors on a Vertical Fill
            -- toggle, but this keeps it self-healing if the axis changes another way.
            local absorbMode = (s and s.absorbEdgeMode) or "overlay"
            -- Overshield mode (three-way; nil falls back to the legacy
            -- showOvershield boolean). Joins the edge key: "fromleft"
            -- re-anchors the backfill in UpdateAbsorbBarReverseFill.
            local osMode = s and s.overshieldMode
            if osMode == nil then osMode = (s and s.showOvershield == false) and "never" or "always" end
            -- Component compares instead of a concatenated key: same change
            -- detection, zero string allocation on the per-event path. Fields
            -- start nil, so the first update always anchors.
            local healEdgeMode = (s and s.healAbsorbEdgeMode) or "overlay"
            local vertFill = (s and s.healthVerticalFill) and true or false
            if ab._ekAbs ~= absorbMode or ab._ekHeal ~= healEdgeMode
               or ab._ekVert ~= vertFill or ab._ekOs ~= osMode then
                ab._ekAbs, ab._ekHeal = absorbMode, healEdgeMode
                ab._ekVert, ab._ekOs = vertFill, osMode
                UpdateAbsorbBarReverseFill(self, ab._isReversed)
            end

            -- Shield (damage) absorb segments render only when enabled; style
            -- "none" hides them and falls through to the independent heal absorb.
            if shieldOff then
                ab:Hide()
                if fw then fw:Hide() end
            else
                -- Re-apply the absorb style only when the setting changes, never on
                -- every health event: SetStatusBarTexture per update flashes the
                -- bar visible even at zero absorb. Opacity/color edits re-apply via
                -- ReloadFrames' direct call.
                local absStyle = s and s.showPlayerAbsorb
                if absStyle and absStyle ~= "none" and ab._lastAbsStyle ~= absStyle then
                    ab._lastAbsStyle = absStyle
                    ApplyAbsorbStyle(ab, absStyle, s)
                end

                -- Show Overshield (three-way, resolved above as osMode):
                -- "never" (overlay mode only) feeds backfill 0 so only empty
                -- health fills, while the forward bar still caps at the right
                -- edge; "always"/"fromleft" draw the excess (placement decided
                -- by the anchor pass). Right/left edge modes draw the WHOLE
                -- absorb through ab (fw hidden below) and are untouched.
                local abValue = absorbAmt
                if osMode == "never" and absorbMode == "overlay" then abValue = 0 end

                -- Both bars get the raw absorb value and the normal maxHealth; the clip
                -- frames do "min(absorb,curHealth)" and "max(0,absorb-curHealth)"
                -- visually, so no Lua arithmetic touches the (possibly secret) absorb.
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

            -- Heal absorb: overlay eating into filled health. The value can be a secret
            -- number in 12.0+, so never compare it in Lua. Feed it directly to
            -- StatusBar:SetValue and let the bar render zero width when the value is 0.
            if ha then
                local haStyle = (s and s.healAbsorbStyle) or "clean"
                if haStyle == "none" then
                    ha:Hide()
                else
                    local hc = (s and s.healAbsorbColor) or { r = 0.8, g = 0.15, b = 0.15 }
                    local hcR, hcG, hcB = hc.r or 0.8, hc.g or 0.15, hc.b or 0.15
                    local haKey = haStyle .. ((s and s.healAbsorbOpacity) or 65) .. hcR .. hcG .. hcB
                    if ha._lastHaKey ~= haKey then
                        ha._lastHaKey = haKey
                        ApplyHealAbsorbStyle(ha, haStyle, s)
                    end
                    local healAbsorbAmt = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(updUnit) or 0
                    ha:SetWidth(hpW); ha:SetHeight(hpH)
                    ha:SetMinMaxValues(0, maxHealth)
                    ha:SetValue(healAbsorbAmt)
                    ha:Show()
                    -- Black backing tracks the fill rect; opacity from settings.
                    local hbg = ha._bg
                    if hbg then
                        hbg:SetColorTexture(0, 0, 0, ((s and s.healAbsorbBgOpacity) or 15) / 100)
                        hbg:SetAllPoints(ha:GetStatusBarTexture())
                        hbg:Show()
                    end
                end
            end
    end
    frame.HealthPrediction = {
        damageAbsorb = backfillBar,
        Override = UF_AbsorbOverride,
    }

    -- The anchors above are the horizontal layout; hand the cluster to the shared
    -- re-anchor pass so a vertical-fill frame starts correct without waiting for
    -- the first settings apply. `settings` is passed through because frame._euiUnit is
    -- not resolvable this early on every frame.
    UpdateAbsorbBarReverseFill(frame, isReversed, settings)

    return backfillBar
end

-- Power bar border: detached bars use the selected full border style; attached bars
-- use a solid divider only along the edge shared with the health bar. Lazy creation
-- lets a newly detached/attached bar (or Border Size raised from 0) gain its border
-- live. Shared by the creation path and player/target/focus refresh branches. On ns
-- for the Lua 5.1 200-local ceiling.
function ns.UpdatePowerBorder(power, settings)
    if not power or not settings then return end
    local pos = settings.powerPosition or "below"
    local isDet = (pos == "detached_top" or pos == "detached_bottom")
    local isAttached = (pos == "above" or pos == "below")
    local size = settings.powerBorderSize or 0
    local border = power._pbBorder
    if not border then
        -- Nothing to render and nothing to hide: stay lazy.
        if not ((isDet or isAttached) and size > 0) then return end
        border = CreateFrame("Frame", nil, power)
        power._pbBorder = border
    end
    -- Re-anchored every pass: a pass that lands while the power bar is zero-height
    -- (Power Bar Height 0 before a Spec Override raises it) leaves the anchors set but
    -- no resolved rect, and nothing recomputes it; re-setting both points restores it.
    border:ClearAllPoints()
    PP.Point(border, "TOPLEFT", power, "TOPLEFT", 0, 0)
    PP.Point(border, "BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
    local c = settings.powerBorderColor or { r = 0, g = 0, b = 0 }
    local alpha = settings.powerBorderAlpha or 1
    -- Attached bars are always Solid; their unused edges are hidden below so only
    -- the health/power seam stays visible.
    local style = isAttached and "solid" or (settings.powerBorderStyle or "solid")
    EllesmereUI.ApplyBorderStyle(border, size, c.r, c.g, c.b, alpha, style,
        settings.powerBorderOffsetX, settings.powerBorderOffsetY,
        settings.powerBorderShiftX, settings.powerBorderShiftY, "unitframes", size)
    local edges = PP.GetBorders(border)
    if edges then
        edges._hideLeft = isAttached or nil
        edges._hideRight = isAttached or nil
        edges._hideTop = (isAttached and pos == "above") or nil
        edges._hideBottom = (isAttached and pos == "below") or nil
        PP.SetBorderSize(border, size)
    end
    local borderLevel = settings.powerBorderBehind
        and math.max(0, power:GetFrameLevel() - 1) or (power:GetFrameLevel() + 5)
    border:SetFrameLevel(borderLevel)
    local showBorder = (isDet or isAttached) and size > 0
    if showBorder then border:Show() else border:Hide() end

    -- The power text overlay must clear the border: the border shares the bar's strata
    -- and can outrank the overlay's default level, so match strata and lift past it.
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
        -- Custom strata when enabled, otherwise MEDIUM.
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

    -- Same bar texture as health; WHITE8X8 when none is configured.
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

    -- Fill color is driven by the powerPercentPowerColor toggle; the gradient
    -- layers additively on top of the resolved custom/power-type color.
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
            -- Secret-safe: player via the clean token, non-player via the clean integer
            -- power type, so the custom color applies on EVERY unit without depending
            -- on oUF's colors.power sync. Unmapped power types return nil (keep oUF's).
            bR, bG, bB = EllesmereUI.ResolveUnitPowerColor(unit)
        end
        if s2.powerGradientEnabled and bR then
            local gc = s2.powerGradientColor
            -- Bake Bar Opacity into the gradient endpoint alphas (a gradient
            -- overrides region alpha).
            local ga = s2.powerBarOpacity or 100
            if ga > 1.0 then ga = ga / 100 end
            ApplyBarGradient(self:GetStatusBarTexture(), s2.powerGradientDir or "HORIZONTAL",
                bR, bG, bB, ga,
                gc and gc.r or 0.20, gc and gc.g or 0.20, gc and gc.b or 0.80, ga)
        elseif not useP then
            local cf = s2.customPowerFillColor
            if cf then self:SetStatusBarColor(cf.r, cf.g, cf.b) else self:SetStatusBarColor(0, 0, 1) end
        elseif bR then
            -- Power-color mode without gradient: apply EUI's GLOBAL power color.
            -- oUF.colors.power is not overridden, so oUF would otherwise leave the
            -- bar on its built-in default instead of the user's.
            self:SetStatusBarColor(bR, bG, bB)
        end
        -- Power-colored bg tracks this unit's power color each update, following
        -- target/power-type changes (mirrors the fill). Opacity stays on
        -- customPowerBgAlpha; gated off = zero cost (custom/dark bg stands unchanged).
        if s2.powerBgPowerColored and self.bg then
            local pr, pg, pb = EllesmereUI.ResolveUnitPowerColor(unit)
            if pr then
                local f = EllesmereUI.GetPowerBgDarkenFactor()
                self.bg:SetColorTexture(pr * f, pg * f, pb * f, 1)
            end
        end
        -- Keep power-percent text color in sync with THIS unit (fires on target/focus
        -- change + UNIT_DISPLAYPOWER, following the unit rather than creation-time
        -- color). Gated on power-colored AND text shown: no cost on other frames.
        if s2.powerPercentTextPowerColor and (s2.powerPercentText or "none") ~= "none" and self._applyPowerTextColor then
            self._applyPowerTextColor(s2)
        end
        -- Same for the Bottom Text Bar's power-colored text (per-slot early-out
        -- keeps it ~free when no slot uses power color).
        local btb = frame.BottomTextBar
        if btb and btb._applyBTBPowerColors then btb._applyBTBPowerColors(s2) end
    end

    local customBg = settings.customPowerBgColor
    if customBg then
        bg:SetColorTexture(customBg.r, customBg.g, customBg.b, 1)
    end

    power:SetReverseFill(settings.powerReverseFill and true or false)

    -- Power percent text overlay, parented to the frame (not power) so the bar
    -- clip container cannot clip it.
    local ppTextOvr = CreateFrame("Frame", nil, frame)
    ppTextOvr:SetAllPoints(power)
    ppTextOvr:SetFrameLevel(frame:GetFrameLevel() + 15)
    local ppFS = ppTextOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(ppFS, settings.powerPercentSize or 9)
    ppFS:Hide()
    power._ppFS = ppFS
    power._ppTextOvr = ppTextOvr

    -- Power-percent text color for the CURRENT unit, so target/focus follow the unit
    -- rather than the player. Power-color mode resolves the unit's own power type;
    -- enemies returning a secret token that can't map to a color fall back to white.
    -- No-power units are NOT special-cased and keep showing 0%.
    local function ApplyPowerTextColor(s)
        if s.powerPercentTextPowerColor then
            -- Secret-safe per-unit color: player keeps the exact token color,
            -- non-player recovers it from the clean integer power type.
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

        -- Power Bar Height 0 collapses the bar to a ZERO-HEIGHT frame, and WoW does not
        -- resolve a zero-height frame's rect (GetLeft() returns nil), so any overlay
        -- anchored to it becomes a 0-width unpositioned strip and text never renders.
        -- Anchor the text overlay to the HEALTH bar instead (always resolved), giving
        -- it real height in the row the power bar would occupy. _euiHeight0 leaves
        -- frames that never hit height 0 untouched; a positive height restores SetAllPoints.
        if (s.powerHeight or 6) <= 0 then
            local pPos = s.powerPosition or "below"
            local anchorTo = frame.Health or power
            ppTextOvr:ClearAllPoints()
            if pPos == "above" or pPos == "detached_top" then
                -- Power row above health: text strip sits above the health bar.
                ppTextOvr:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", 0, 0)
                ppTextOvr:SetPoint("BOTTOMRIGHT", anchorTo, "TOPRIGHT", 0, 0)
            else
                -- "below"/"detached_bottom": strip sits below the health bar.
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
            ns.SetTextZoneRaw(frame, ppFS, nil)
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

        local showPct = s.powerShowPercent ~= false
        local pctSuffix = showPct and "%%" or ""
        local fmt = s.powerTextFormat or "perpp"
        local TP = ns.TextPieces
        if fmt == "curpp" then
            ns.SetTextZoneRaw(frame, ppFS, "%s", { TP.curpp })
        elseif fmt == "both" then
            ns.SetTextZoneRaw(frame, ppFS, "%s | %s" .. pctSuffix, { TP.curpp, TP.perpp })
        elseif fmt == "smart" then
            -- Percent for mana-based specs, numeric otherwise; resolved at apply
            -- time and re-applied on spec change via ReloadAndUpdate.
            local isPercent = EUI_IsSmartPowerPercent()
            if isPercent then
                ns.SetTextZoneRaw(frame, ppFS, "%s" .. pctSuffix, { TP.perpp })
            else
                ns.SetTextZoneRaw(frame, ppFS, "%s", { TP.curpp })
            end
        else -- "perpp" default
            ns.SetTextZoneRaw(frame, ppFS, "%s" .. pctSuffix, { TP.perpp })
        end
        ns.UF_PaintText(frame, frame._euiUnit or unit)

        -- Priority: power-colored (per-unit) > custom color > white.
        ApplyPowerTextColor(s)
        ppFS:Show()
    end

    ApplyPowerPercentText(settings)
    power._applyPowerPercentText = ApplyPowerPercentText

    ApplyPowerBarAlpha(power, UnitToSettingsKey(unit))

    -- Gray out the power bar for enemy NPCs with no real power (melee mobs); keep
    -- it for player, friendly units, enemy players, bosses, minibosses, casters.
    power._grayedOut = false
    power.PostUpdate = function(self, u, cur, min, max)
        local s = GetSettingsForUnit(u)
        if not s then return end

        local pp = s.powerPosition or "below"
        if pp == "none" or pp == "detached_top" or pp == "detached_bottom" then return end

        -- Classification check: generic melee NPCs get the gray bar.
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
            local uCls = UnitClassBase and UnitClassBase(u)
            if issecretvalue(uCls) then uCls = nil end
            if uCls == "PALADIN" then return false end
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
                -- Restore this unit's power color (mirrors the fill); the next
                -- PostUpdateColor keeps it tracking thereafter.
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
            -- Bg alpha comes from customPowerBgAlpha (matching ApplyPowerBarAlpha),
            -- NOT powerBarOpacity, which is the FILL opacity.
            if self.bg then
                self.bg:SetAlpha((s and (s.customPowerBgAlpha or 100) or 100) / 100)
            end
        end
    end

    -- Per-spec power type override: an alternate power type on the player power bar
    -- (e.g. Balance Druid: Astral Power vs Mana). Shadow Priest defaults to Mana;
    -- other specs default to UnitPowerType.
    if unit == "player" then
        local _, classFile = UnitClass("player")
        if PLAYER_POWER_DEFAULT[classFile] or PLAYER_POWER_ALT[classFile] then
            power.displayAltPower = true
            power.GetDisplayPower = function(self, u)
                local resolved = EllesmereUI.GetPlayerPowerOverride()
                -- Publish for tags so the text matches the bar.
                _G._EUI_ResolvedPowerType[u or "player"] = resolved
                return resolved
            end
        end
    end

    -- Power bar border: full when detached, divider when attached; lazy.
    ns.UpdatePowerBorder(power, settings)

    return power
end

local function CreatePortrait(frame, side, frameHeight, unit)
    local portraitHeight = frameHeight or 46
    local uKey = UnitToSettingsKey(unit)
    local uSettings = uKey and db.profile[uKey]
    local portraitStyle = (uSettings and uSettings.portraitStyle) or db.profile.portraitStyle or "attached"
    -- Mini frames never use detached portraits.
    local isMiniP = unit and (unit == "pet" or unit == "targettarget" or unit == "focustarget" or unit:match("^boss%d$"))
    if isMiniP and portraitStyle == "detached" then portraitStyle = "attached" end
    local isAttached = (portraitStyle == "attached")

    -- Per-unit size/offset adjustments.
    local pSizeAdj = (uSettings and uSettings.portraitSize) or 0
    local pXOff = (uSettings and uSettings.portraitX) or 0
    local pYOff = (uSettings and uSettings.portraitY) or 0
    local baseHeight = portraitHeight
    if not isAttached and not isInside and portraitStyle ~= "none" then pSizeAdj = pSizeAdj + 10; pYOff = pYOff + 5 end
    local adjustedHeight = baseHeight + pSizeAdj
    if adjustedHeight < 8 then adjustedHeight = 8 end

    -- Attached: "top" and "inside*" fall back to the default side.
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
        -- Inside: portrait fills frame height, width = adjusted portrait size.
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
        -- Disabled: anchor the (hidden) backdrop to the frame corner, avoiding any
        -- dependency on frame.Health which may not exist yet.
        PP.Point(backdrop, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    elseif isInside then
        -- Inside: overlays the health bar. Anchored to the frame initially;
        -- ReloadFrames re-anchors to frame.Health once layout resolves.
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
        -- Detached: float outside the health bar edge.
        if effectiveSide == "top" then
            backdrop:SetPoint("BOTTOM", frame.Health or frame, "TOP", pXOff, 15 + pYOff)
        elseif effectiveSide == "left" then
            backdrop:SetPoint("TOPRIGHT", frame.Health or frame, "TOPLEFT", -15 + pXOff, pYOff)
        else
            backdrop:SetPoint("TOPLEFT", frame.Health or frame, "TOPRIGHT", 15 + pXOff, pYOff)
        end
        -- Raise a detached portrait above border/text/power.
        backdrop:SetFrameLevel(frame:GetFrameLevel() + 15)
    end

    -- 2D and class theme textures are eager; the 3D PlayerModel is deferred until
    -- mode == "3d" to avoid its GPU/memory cost when unused.
    local model3D = nil

    local function EnsureModel3D()
        if model3D then return model3D end
        model3D = CreateFrame("PlayerModel", nil, backdrop)
        PP.Point(model3D, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
        PP.Point(model3D, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
        model3D:SetCamera(0)
        local camScale = ((uSettings and uSettings.portrait3dZoom) or 100) / 100
        model3D:SetCamDistanceScale(camScale)
        -- Re-apply zoom after oUF's SetUnit, which resets the camera.
        model3D.PostUpdate = function(self)
            local u = self.__owner and self.__owner._euiUnit
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

    -- Class theme icon: painted by the engine portrait painter's class lane
    -- (element.isClass); this creation-time paint only seeds art before the
    -- first dispatch.
    local texClass = backdrop:CreateTexture(nil, "ARTWORK")
    local classInset = math.floor(portraitHeight * 0.08)
    PP.Point(texClass, "TOPLEFT", backdrop, "TOPLEFT", classInset, -classInset)
    PP.Point(texClass, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -classInset, classInset)
    texClass:SetAlpha(0.8)
    local _, classToken = UnitClass(unit)
    if issecretvalue(classToken) then classToken = nil end
    local classStyle = (uSettings and uSettings.classThemeStyle) or "modern"
    ApplyClassIconTexture(texClass, classToken or "WARRIOR", classStyle)
    texClass:Hide()

    backdrop._3d = model3D
    backdrop._2d = tex2D
    backdrop._class = texClass

    local mode
    do
        mode = (uSettings and uSettings.portraitMode) or db.profile.portraitMode or "2d"
    end
    -- portraitStyle/portraitMode "none" hides the backdrop but keeps the structure
    -- alive so ReloadFrames can show it again without a /reload.
    if portraitStyle == "none" or mode == "none" then
        backdrop:Hide()
        -- tex2D is a minimal placeholder so frame.Portrait is non-nil and carries a
        -- backdrop reference; it stays hidden with the backdrop.
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

    -- SetPortraitTexture resets snapping and anchor points, so re-disable pixel
    -- snap and re-anchor after every oUF portrait update.
    tex2D.PostUpdate = function(self)
        UnsnapTex(self)
        self:ClearAllPoints()
        -- When detached, ApplyDetachedPortraitShape uses expanded offsets for mask
        -- fill; re-apply those instead of resetting to default.
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

    ApplyDetachedPortraitShape(backdrop, uSettings, unit)

    return active
end

-- Unlock position key for a unit's castbar, or nil.
local function CastbarUnlockKey(unit)
    if unit == "player" then return "playerCastbar"
    elseif unit == "target" then return "targetCastbar"
    elseif unit == "focus" then return "focusCastbar"
    end
end

-- Cast bar positioning is owned by the centralized unlock/anchor system
-- (ApplySavedPositions).

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
    return unit == "target" or unit == "focus" or (unit and unit:match("^boss") ~= nil)
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
-- Hoisted defaults for the zero-alloc paint below: as inline literals these would
-- allocate on EVERY call when the setting was absent (the common case).
local UF_KICK_READY_TINT = { r = 0.92, g = 0.35, b = 0.20 }
local UF_UNINTERRUPT_GREY = { r = 0.5, g = 0.5, b = 0.5 }
local function ApplyUnitFrameCastColor(castbar)
    if not castbar or not castbar.castTintLayer then return end
    local settings = castbar._eufSettings
    local ownerUnit = castbar.__owner and castbar.__owner._euiUnit
    -- Zero-alloc: values flow as scalars instead of building up to three throwaway
    -- color tables per call (two default literals + the blended kick tint).
    local r, g, b
    if settings and settings.castbarClassColored and ownerUnit == "player" then
        local _, classToken = UnitClass(ownerUnit)
        if issecretvalue(classToken) then classToken = nil end
        if classToken and EllesmereUI.GetClassColor then
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then r, g, b = cc.r, cc.g, cc.b end
        end
    end
    if not r then
        local baseTint = (settings and settings.castbarFillColor) or GetCastbarColor()
        if IsKickCastbarUnit(ownerUnit) then
            local readyTint = (settings and settings.castbarInterruptReadyColor) or UF_KICK_READY_TINT
            r, g, b = ComputeCastBarTint(readyTint, baseTint)
        else
            r, g, b = baseTint.r, baseTint.g, baseTint.b
        end
    end
    castbar.castTintLayer:SetVertexColor(r, g, b)
    if castbar._shieldedTint then
        -- Uninterruptible overlay colour (defaults to grey). Its alpha is toggled
        -- from the secret "not interruptible" flag, so the colour is always set and
        -- only becomes visible on uninterruptible casts.
        local uc = (settings and settings.castbarUninterruptibleColor) or UF_UNINTERRUPT_GREY
        -- Explicit vertex alpha: Midnight's 3-arg SetVertexColor leaves the
        -- vertex alpha at an unexpected value (measured 0.5 with the gray
        -- default -- GetVertexColor returned a=r), and the composite with the
        -- region alpha rendered the shield faint-to-invisible. Visibility
        -- stays owned by SetAlphaFromBoolean below on the region slot.
        castbar._shieldedTint:SetVertexColor(uc.r, uc.g, uc.b, 1)
        local uninterruptible = GetCastbarUninterruptible(castbar)
        -- Visible alpha honors Fill Opacity (castbar._fillOp, nil at 100); both
        -- branches pass it as a plain number, never touching the secret. The
        -- boolean alpha drives the HOST FRAME -- texture SetAlphaFromBoolean
        -- renders 0 on Midnight despite healthy readbacks (see creation).
        local shieldTarget = castbar._shieldHost or castbar._shieldedTint
        if shieldTarget.SetAlphaFromBoolean then
            shieldTarget:SetAlphaFromBoolean(uninterruptible, castbar._fillOp or 1, 0)
        else
            shieldTarget:SetAlpha(uninterruptible and (castbar._fillOp or 1) or 0)
        end
    end
end
local function UpdateUnitFrameKickTick(castbar)
    if not castbar or not castbar.kickPositioner then return end
    local settings = castbar._eufSettings
    local ownerUnit = castbar.__owner and castbar.__owner._euiUnit
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
        -- Transient read miss during an ongoing cast: skip, do NOT hide (a Hide/re-Show
        -- cycle on every SPELL_UPDATE_COOLDOWN would blink the tick during rotation).
        -- Cast end is handled by the cast-stop path.
        return
    end
    -- Cache cast identity so the light per-event refresh re-pins bar values from it
    -- without re-deriving channel/empower or re-minting fill geometry.
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
        -- LOAD-BEARING: SetFillStyle resets the inner fill to snap-ON and the global
        -- hook does not re-fire on a cached bar. Re-disable snap so the summed
        -- elapsed+remaining edge stays an exact float.
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
        -- Reverse fill (draining channel): kick-ready point is the marker texture LEFT
        -- edge; the available window runs from the channel end (bar left) to it.
        -- Not-in-time pushes that edge past the left edge, crossing anchors to zero width.
        castbar.kickReadyFill:ClearAllPoints()
        castbar.kickReadyFill:SetPoint("TOP", castbar, "TOP", 0, 0)
        castbar.kickReadyFill:SetPoint("BOTTOM", castbar, "BOTTOM", 0, 0)
        castbar.kickReadyFill:SetPoint("LEFT", castbar, "LEFT", 0, 0)
        castbar.kickReadyFill:SetPoint("RIGHT", castbar.kickMarker:GetStatusBarTexture(), "LEFT")
    else
        castbar.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Standard)
        castbar.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Standard)
        -- LOAD-BEARING: re-disable snap on the re-minted fill textures (see the
        -- reverse branch) so the tick stays stationary across every re-pin.
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
        -- Standard fill (cast/empowered channel): kick-ready point is the marker
        -- texture RIGHT edge; the window runs from it to the cast end (bar right).
        -- Not-in-time pushes that edge past the right edge, crossing anchors to zero width.
        castbar.kickReadyFill:ClearAllPoints()
        castbar.kickReadyFill:SetPoint("TOP", castbar, "TOP", 0, 0)
        castbar.kickReadyFill:SetPoint("BOTTOM", castbar, "BOTTOM", 0, 0)
        castbar.kickReadyFill:SetPoint("LEFT", castbar.kickMarker:GetStatusBarTexture(), "RIGHT")
        castbar.kickReadyFill:SetPoint("RIGHT", castbar, "RIGHT", 0, 0)
    end
    castbar.kickPositioner:Show()
    castbar.kickMarker:Show()
    -- Mid-cast fill: CLEAN DB color tint + CLEAN per-toggle visibility; its alpha (the
    -- SECRET on-CD x interruptible gate) is applied with the tick alpha below. Geometry
    -- above runs whenever the tick OR fill is enabled; SetShown gates each element to
    -- its own toggle so one never forces the other.
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

-- Light per-cooldown-event refresh: bar values + tick alpha only. Geometry (SetSize,
-- anchors, SetFillStyle, color) is cast-identity work done once by
-- UpdateUnitFrameKickTick. Re-pin positioner(elapsed) and marker(remaining) together to
-- keep the tick stationary; NEVER re-pin one without the other.
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
    local ownerUnit = castbar.__owner and castbar.__owner._euiUnit
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
            if cb:IsShown() and cb.__owner and cb.__owner._euiUnit then
                ApplyUnitFrameCastColor(cb)
                -- Light refresh once the kick bars are set up; re-run the full geometry/
                -- fill setup only when not shown (kick learned mid-cast, CD info late,
                -- toggle flipped on). Stops SetFillStyle from re-minting the inner fill
                -- textures every cooldown event, which re-snapped them to the pixel grid.
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
    if not IsKickCastbarUnit(castbar.__owner._euiUnit) then return end
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
    
    -- Standalone element parented to the oUF frame for compatibility, but sized
    -- and positioned independently.
    local castbarBg = CreateFrame("Frame", nil, frame)

    -- Width/height always come from settings; nothing is auto-derived.
    local cbWidth, cbHeight
    if unit == "player" then
        cbWidth = db.profile.player.playerCastbarWidth or 181
        cbHeight = db.profile.player.playerCastbarHeight or 14
    else
        -- castbarWidth 0 = auto (boss frames match frame width; the boss update
        -- pass re-sizes to the live frame width right after creation).
        local cbw = settings.castbarWidth or 0
        cbWidth = cbw > 0 and cbw or 181
        cbHeight = settings.castbarHeight or 14
    end
    PP.Size(castbarBg, cbWidth, cbHeight)

    -- Position is owned by the centralized unlock system; this temporary anchor
    -- just gives the frame valid bounds until ApplySavedPositions runs at login
    -- (unlock default: BOTTOM of the parent unit frame).
    castbarBg:SetPoint("TOP", frame, "BOTTOM", 0, 0)

    local bgTex = castbarBg:CreateTexture(nil, "BACKGROUND")
    PP.Point(bgTex, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
    PP.Point(bgTex, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)
    -- Background color/alpha default to black 0.5 unless castBgColor/castBgAlpha
    -- are set.
    local _cbgC = settings.castBgColor
    bgTex:SetColorTexture(_cbgC and _cbgC.r or 0, _cbgC and _cbgC.g or 0, _cbgC and _cbgC.b or 0, settings.castBgAlpha or 0.5)
    castbarBg._bgTex = bgTex

    local castbar = CreateFrame("StatusBar", nil, castbarBg)
    PP.Point(castbar, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
    PP.Point(castbar, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)
    castbar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    castbar:GetStatusBarTexture():SetHorizTile(false)
    castbar:SetReverseFill(settings.castReverseFill and true or false)

    -- Borders draw on the castbar itself (same frame level as the fill texture) so
    -- the OVERLAY border sits above the ARTWORK fill. On castbarBg they would land
    -- BEHIND the fill, since castbar is its child and draws above it.
    PP.CreateBorder(castbar, 0, 0, 0, 1, 1, "OVERLAY", 0)


    -- Three-zone cast bar text layout matching nameplates: [spell name LEFT 42%]
    -- [target RIGHT-of-center 42%] [timer RIGHT]. All zones ellipsize (WordWrap off,
    -- MaxLines 1); text overlay sits above the unified border (frame +10).
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
    -- element has a side; duration reserves its slot and pushes whichever non-center
    -- element shares that side (center is never pushed). Spell name hides on side
    -- "none"; target/duration visibility rides _showTarget/_showDuration (their
    -- dropdown "None" clears those flags).
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
        -- The 42% reserves the opposite half for the cast target. When this unit never
        -- shows a target (boss frames: showCastTarget false with no UI to enable it)
        -- the name owns the row and gets 80% before truncating.
        local nameW = (cb._showTarget == false) and (barW * 0.80) or textW
        -- Combine Spell Name and Target suppresses the target element, so the combined
        -- name owns the row and gets the wide budget.
        cb.Text:ClearAllPoints()
        if nameSide == "none" then
            cb.Text:Hide()
        else
            local pt, xb, jh = ns.GetCastTextAnchor(nameSide, showDur and durSide == nameSide, timerW, false)
            cb.Text:SetWidth(cb._combineNT and (barW * 0.80) or nameW)
            cb.Text:SetJustifyH(jh)
            cb.Text:SetPoint(pt, cb, pt, xb + (cb._nameOX or 0), 1 + (cb._nameOY or 0))
            cb.Text:Show()
        end
        -- Spell target; visibility is handled by _showTarget / hasTarget elsewhere.
        do
            local pt, xb, jh = ns.GetCastTextAnchor(tgtSide, showDur and durSide == tgtSide, timerW, false)
            cb.Target:ClearAllPoints()
            cb.Target:SetWidth(textW)
            cb.Target:SetJustifyH(jh)
            cb.Target:SetPoint(pt, cb, pt, xb + (cb._tgtOX or 0), (cb._tgtOY or 0))
        end
        -- Duration/timer: side is only "left"/"right"; visibility via _showDuration.
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

    local castTintLayer = castbar:CreateTexture(nil, "ARTWORK", nil, 1)
    castTintLayer:SetPoint("TOPLEFT", castbar:GetStatusBarTexture(), "TOPLEFT")
    castTintLayer:SetPoint("BOTTOMRIGHT", castbar:GetStatusBarTexture(), "BOTTOMRIGHT")
    castTintLayer:SetTexture("Interface\\Buttons\\WHITE8X8")
    local c = GetCastbarColor()
    castTintLayer:SetVertexColor(c.r, c.g, c.b)
    castTintLayer:SetAlpha(0)
    castbar.castTintLayer = castTintLayer
    castbar._castTintOn = nil

    -- The shield tint lives on its own child FRAME: the secret-safe show/hide
    -- rides SetAlphaFromBoolean, and on Midnight that API renders 0 on
    -- TEXTURES while GetAlpha reads back the true-branch value (measured
    -- 2026-08-12 -- perfect state readbacks, nothing painted). Frame alpha is
    -- the proven boolean lane (range fading uses it suite-wide).
    local shieldHost = CreateFrame("Frame", nil, castbar)
    shieldHost:SetAllPoints(castbar)
    shieldHost:SetAlpha(0)
    local shieldedTint = shieldHost:CreateTexture(nil, "ARTWORK", nil, 2)
    shieldedTint:SetPoint("TOPLEFT", castbar:GetStatusBarTexture(), "TOPLEFT")
    shieldedTint:SetPoint("BOTTOMRIGHT", castbar:GetStatusBarTexture(), "BOTTOMRIGHT")
    shieldedTint:SetTexture("Interface\\Buttons\\WHITE8X8")
    shieldedTint:SetVertexColor(0.5, 0.5, 0.5, 1)
    castbar._shieldedTint = shieldedTint
    castbar._shieldHost = shieldHost

    -- Cast bar reuses the unit's health bar texture (overridden donor-aware in ReloadFrames).
    ns.ApplyCastBarTexture(castbar, (settings and settings.healthBarTexture) or db.profile.healthBarTexture or "none")
    ns.ApplyCastFillOpacity(castbar, settings)

    local function OnCastbarCastActive(self)
        if self.castTintLayer then
            -- _fillOp is nil unless Fill Opacity is below 100 (see
            -- ns.ApplyCastFillOpacity), so the default path is unchanged.
            self.castTintLayer:SetAlpha(self._fillOp or 1)
            self._castTintOn = true
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
        -- Interrupt-ready mid-cast fill: colors the cast-bar segment from the "kick
        -- ready here" point to the cast end (the window during which the interrupt will
        -- be available) when the kick is on cooldown now but comes off before the cast
        -- finishes. Rides the SAME kickMarker geometry as the tick; the "ready in time"
        -- two-secret test resolves by where the marker texture edge lands -- when the
        -- kick will NOT be ready in time the fill anchors cross to zero width and it
        -- self-hides with no Lua branch on a secret. ARTWORK sublevel 1 (created after
        -- castTintLayer so it draws above the fill colour) sits below the cast text
        -- (OVERLAY) and the uninterruptible grey (sublevel 2). Anchors are (re)applied
        -- per cast in UpdateUnitFrameKickTick.
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
            self._timeBucket = nil
            return
        end
        self.Time:Show()
        if durationObject then
            -- oUF calls this per RENDER FRAME, but the displayed value has %.1f
            -- precision -- format + SetText only when the displayed tenth actually
            -- changes (~6x fewer at 60fps, more uncapped). Secret durations (other
            -- units' casts in combat) can't be floored: fail open to formatting every
            -- call (SetFormattedText accepts secrets). The delay branch is rare
            -- (pushback) and stays unmemoized.
            local duration = durationObject:GetRemainingDuration()
            if self.delay and self.delay ~= 0 then
                self._timeBucket = nil
                self.Time:SetFormattedText('%.1f|cffff0000%s%.2f|r', duration, self.channeling and '-' or '+', self.delay)
            elseif issecretvalue and issecretvalue(duration) then
                self._timeBucket = nil
                self.Time:SetFormattedText('%.1f', duration)
            else
                local bucket = math.floor(duration * 10)
                if bucket ~= self._timeBucket then
                    self._timeBucket = bucket
                    self.Time:SetFormattedText('%.1f', duration)
                end
            end
        end
    end
    castbar.CustomDelayText = castbar.CustomTimeText

    -- Cast spell icon (oUF sets castbar.Icon texture automatically). Size from the
    -- CONFIGURED height (cbHeight), not a live castbarBg:GetHeight() which is
    -- unreliable this early; LayoutCastbarIcon anchors height to the bar regardless,
    -- this is just the initial square.
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
    do
        local offX, offY = CastIconOffsets(unit, settings)
        LayoutCastbarIcon(castbar, CastIconInWidth(unit, settings), cbHeight, CastIconOnRight(unit, settings), offX, offY, CastIconShown(unit, settings))
    end

    return castbar
end

local function SetupShowOnCastBar(frame, unit)
    local castbar = frame.Castbar
    local castbarBg = castbar:GetParent()
    local iconFrame = castbar._iconFrame

    -- Read the hide-when-inactive flag dynamically so closures always reflect the
    -- current setting rather than a value captured at frame-creation time.
    local function shouldHideWhenInactive()
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
            -- Boss: re-assert the configured width (castbarWidth>0=custom, 0=match
            -- frame width) at cast start, so a live cast always shows the right width
            -- even if no settings pass ran since the frame was resized.
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
            local ownerUnit = self.__owner and self.__owner._euiUnit
            -- Channels are excluded: UnitSpellTargetName tracks the last CAST
            -- and keeps returning the previous hard-cast's target for the
            -- whole channel (field-verified stale), and no channel-target API
            -- exists -- so channels show no target name rather than a wrong
            -- one. Empowered casts read correctly and keep theirs.
            if ownerUnit and not self.channeling
               and UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(ownerUnit) then
                local rawTarget = UnitSpellTargetName and UnitSpellTargetName(ownerUnit)
                if rawTarget then
                    spellTarget = rawTarget
                    spellTargetClass = UnitSpellTargetClass and UnitSpellTargetClass(ownerUnit)
                end
            end
            local hasTarget = spellTarget and true or false
            local sOwn = ownerUnit and db and db.profile and GetSettingsForUnit(ownerUnit)
            -- Combine Spell Name and Target (target/focus): one string in the TARGET
            -- slot ("Spell Name - Target", target class colored); the separate Spell
            -- Name element is suppressed via _combineNT in LayoutCastTextZones. Color
            -- code lives in the clean FORMAT string; (possibly secret) names ride
            -- through SetFormattedText -- never Lua-concatenated.
            local combine = sOwn and sOwn.castCombineNameTarget == true
                and (ownerUnit == "target" or ownerUnit == "focus")
            self._combineNT = combine or nil
            if combine then
                -- The separate target element is fully suppressed; the target
                -- rides appended to the spell NAME element instead.
                self.Target:SetText("")
                self.Target:Hide()
                if self.Text and hasTarget then
                    local spellName = UnitCastingInfo(ownerUnit)
                    if not spellName then spellName = UnitChannelInfo(ownerUnit) end
                    local hex
                    if spellTargetClass and C_ClassColor then
                        local c = C_ClassColor.GetClassColor(spellTargetClass)
                        if c and c.GenerateHexColor then hex = c:GenerateHexColor() end
                    end
                    if spellName then
                        if hex then
                            self.Text:SetFormattedText("%s - |c" .. hex .. "%s|r", spellName, spellTarget)
                        else
                            self.Text:SetFormattedText("%s - %s", spellName, spellTarget)
                        end
                    end
                end
                -- No cast target: oUF's plain spell name in the Text element
                -- stands untouched.
            else
                self.Target:SetText(spellTarget or "")
                self.Target:SetShown(hasTarget and self._showTarget ~= false)
                -- Class color the target name
                if hasTarget and spellTargetClass and C_ClassColor then
                    local c = C_ClassColor.GetClassColor(spellTargetClass)
                    if c then
                        self.Target:SetTextColor(c:GetRGB())
                    else
                        local tc = (sOwn and sOwn.castSpellTargetColor) or { r=1, g=1, b=1 }
                        self.Target:SetTextColor(tc.r, tc.g, tc.b)
                    end
                elseif hasTarget then
                    local tc = (sOwn and sOwn.castSpellTargetColor) or { r=1, g=1, b=1 }
                    self.Target:SetTextColor(tc.r, tc.g, tc.b)
                end
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

    -- Catch-all: hide the icon AND background whenever the castbar hides for any
    -- reason (oUF holdTime expiry, target/focus switch, etc.) so neither gets stuck.
    -- Key case: target/focus switching mid-cast -- oUF's CastStart hides the castbar
    -- but never fires PostCastStop, so dismissCastBar never runs and the background
    -- frame would otherwise remain visible as a black rectangle.
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


-- Boss frames have an independent Hover / Target border recolor (mirrors Raid Frames
-- "Hover Borders"); both default OFF. Priority: hover (moused over) > target (current
-- target) > the frame's normal border color. Recolors the existing unified border in
-- place. _hovered is maintained by OnEnter/OnLeave hooks; _isTarget by the boss target
-- updater. On ns to avoid the Lua 200-local cap.
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
    local unit = self._euiUnit or "player"
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
    local unit = self._euiUnit or "player"
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
--  Zero cost unless enabled: no frame created, no event registered until the
--  option is on. When on, watches ONLY the player's own threat (RegisterUnitEvent
--  ... "player") plus minimal combat/zone boundaries to clear it; shows only in
--  instanced content (party/raid/delve) while grouped -- mirrors nameplate non-tank logic.
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


-- Cropped aura icons: the button becomes a rectangle (height = 80% of width) and the
-- texture is trimmed top/bottom so the visible art keeps its aspect ratio (no vertical
-- squish), matching the action bar "cropped" shape. Horizontal keeps the normal 0.07
-- zoom (span 0.86); vertical span derives from the button's ACTUAL width/height
-- (height = uSpan * h/w, centered) so texture width:height always equals the frame's
-- exactly, even after height rounds to whole pixels.
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
ns.SetAuraIconCrop = SetAuraIconCrop
function ns.GetAuraCropHeight(cropped, w)
    if cropped then return math_floor(w * AURA_CROP_HEIGHT + 0.5) end
    return w
end

-- Anchor a stack-count FontString per the "Position" setting. Default anchor is the
-- classic aura-button corner (BOTTOMRIGHT -1,0); corner anchors tuck the number inside
-- the icon edge, center sits dead-center. User X/Y offset adds on top. On ns for the
-- 200-local cap.
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

-- 12.1 aura containers own every unit frame's buff/debuff rows
-- (EUI_UnitFrames_AuraContainers.lua): hand the container file its
-- always-fresh settings access and build the unit's containers.
local function CreateTargetAuras(frame, unit)
    ns.UF_GetSettings = GetSettingsForUnit
    ns.UF_GetProfile = ns.UF_GetProfile or function() return db and db.profile end
    return ns.UF_CreateAuraContainers(frame, unit or "target")
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
    -- anchors per extraTextAlign, capped at 95% of the bar width (ellipsis truncation).
    local extraText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(extraText, ets)
    extraText:SetWordWrap(false)
    extraText:SetTextColor(1, 1, 1)
    frame.ExtraText = extraText

    -- Shorthand aliases for font/tag application code
    frame.NameText = leftText
    frame.HealthValue = rightText

    -- "Absorb Short" zero-hide: a binary StatusBar gate (max 1) fed the raw absorb clips
    -- the abbreviated absorb text away at zero shield, secret-safely (absorb only feeds
    -- SetValue, never compared to zero). The clip frame tracks the gate's fill texture;
    -- the zone FontString is reparented into it. Driven every absorb update by the
    -- HealthPrediction Override. Lazy: _absGate/_absClip stay nil until a zone is set to
    -- Absorb Short, so unused frames pay ZERO cost (Override skips when self._absGate is
    -- nil). content is the zone's resolved key: "absorbshort" gates shield absorbs,
    -- "healabsorbshort" gates heal absorbs (g._euiHealGate marks the source so the
    -- Override feeds the right amount). Anything else tears the gate down.
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

    -- Apply tags based on content. Extra Text is handled identically to the other
    -- zones (same ContentToTag + absorb gate); only positioning differs (alignment-
    -- based anchor, 95%-of-bar-width clamp with ellipsis truncation).
    local function ApplyTextTags(lc, rc, cc, ec)
        ec = ec or (settings.extraTextContent or "none")
        ns.SetTextZone(frame, leftText, lc, "leftText", settings)
        ns.SetTextZone(frame, rightText, rc, "rightText", settings)
        ns.SetTextZone(frame, centerText, cc, "centerText", settings)
        ns.SetTextZone(frame, extraText, ec, "extraText", settings)
        ApplyAbsorbGate("left", leftText, lc)
        ApplyAbsorbGate("right", rightText, rc)
        ApplyAbsorbGate("center", centerText, cc)
        ApplyAbsorbGate("extra", extraText, ec)
        ns.UF_PaintText(frame, frame._euiUnit or unit)
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

        -- Extra Text: anchored per extraTextAlign (left/right/center); ellipsis-
        -- truncated past 95% of health bar width (SetWordWrap(false) + capped width below).
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
            PP.Width(extraText, barW * 0.95 * SlotWidthMul(s, "extraText"))
            extraText:Show()
            ApplyClassColor(extraText, unit, s.extraTextClassColor, s.extraTextColorR, s.extraTextColorG, s.extraTextColorB)
        else extraText:Hide() end

        -- Each text position renders independently; Center no longer hides Left/Right.
        SetFSFont(centerText, csz)
        centerText:ClearAllPoints()
        if cc ~= "none" then
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            PP.Width(centerText, barW * 0.9 * SlotWidthMul(s, "centerText"))
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
                PP.Width(leftText, math.max(barW - rightUsed - 10, 20) * SlotWidthMul(s, "leftText"))
            else
                PP.Width(leftText, barW * 0.9 * SlotWidthMul(s, "leftText"))
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
                PP.Width(rightText, math.max(barW - leftUsed - 10, 20) * SlotWidthMul(s, "rightText"))
            else
                PP.Width(rightText, barW * 0.9 * SlotWidthMul(s, "rightText"))
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
    -- anchors per extraTextAlign, capped at 95% of the bar width (ellipsis truncation).
    local extraText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(extraText, ets)
    extraText:SetWordWrap(false)
    extraText:SetTextColor(1, 1, 1)
    frame.ExtraText = extraText

    -- Shorthand aliases for font/tag application code
    frame.NameText = leftText
    frame.HealthValue = rightText

    -- "Absorb Short" zero-hide: a binary StatusBar gate (max 1) fed the raw absorb clips
    -- the abbreviated absorb text away at zero shield, secret-safely (absorb only feeds
    -- SetValue, never compared to zero). The clip frame tracks the gate's fill texture;
    -- the zone FontString is reparented into it. Driven every absorb update by the
    -- HealthPrediction Override. Lazy: _absGate/_absClip stay nil until a zone is set to
    -- Absorb Short, so unused frames pay ZERO cost (Override skips when self._absGate is
    -- nil). content is the zone's resolved key: "absorbshort" gates shield absorbs,
    -- "healabsorbshort" gates heal absorbs (g._euiHealGate marks the source so the
    -- Override feeds the right amount). Anything else tears the gate down.
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

    -- Apply tags based on content. Extra Text is handled identically to the other
    -- zones (same ContentToTag + absorb gate); only positioning differs (alignment-
    -- based anchor, 95%-of-bar-width clamp with ellipsis truncation).
    local function ApplyTextTags(lc, rc, cc, ec)
        ec = ec or (settings.extraTextContent or "none")
        ns.SetTextZone(frame, leftText, lc, "leftText", settings)
        ns.SetTextZone(frame, rightText, rc, "rightText", settings)
        ns.SetTextZone(frame, centerText, cc, "centerText", settings)
        ns.SetTextZone(frame, extraText, ec, "extraText", settings)
        ApplyAbsorbGate("left", leftText, lc)
        ApplyAbsorbGate("right", rightText, rc)
        ApplyAbsorbGate("center", centerText, cc)
        ApplyAbsorbGate("extra", extraText, ec)
        ns.UF_PaintText(frame, frame._euiUnit or unit)
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

        -- Extra Text: anchored per extraTextAlign (left/right/center); ellipsis-
        -- truncated past 95% of health bar width (SetWordWrap(false) + capped width below).
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
            PP.Width(extraText, barW * 0.95 * SlotWidthMul(s, "extraText"))
            extraText:Show()
            ApplyClassColor(extraText, unit, s.extraTextClassColor, s.extraTextColorR, s.extraTextColorG, s.extraTextColorB)
        else extraText:Hide() end

        -- Each text position renders independently; Center no longer hides Left/Right.
        SetFSFont(centerText, csz)
        centerText:ClearAllPoints()
        if cc ~= "none" then
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            PP.Width(centerText, barW * 0.9 * SlotWidthMul(s, "centerText"))
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
                PP.Width(leftText, math.max(barW - rightUsed - 10, 20) * SlotWidthMul(s, "leftText"))
            else
                PP.Width(leftText, barW * 0.9 * SlotWidthMul(s, "leftText"))
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
                PP.Width(rightText, math.max(barW - leftUsed - 10, 20) * SlotWidthMul(s, "rightText"))
            else
                PP.Width(rightText, barW * 0.9 * SlotWidthMul(s, "rightText"))
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
    ns.ApplyHealthOrientation(health, settings)
    ApplyDarkTheme(health, unit)

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

    -- "Absorb Short" zero-hide: the [eui-absorbshort] tag shows the abbreviated absorb
    -- but cannot blank at zero (no has-absorb boolean exists), so we clip the text away
    -- when there is no shield, secret-safely: a binary StatusBar gate (max 1) is fed the
    -- raw absorb so its fill texture is full width with any shield and zero width with
    -- none; a clip frame tracks that fill rect and the zone FontString is reparented
    -- into it, clipping the text to nothing at zero absorb. Absorb is never compared to
    -- zero in Lua -- only fed to SetValue (accepts secrets natively). Driven every
    -- absorb update by the HealthPrediction Override. Lazy: _absGate/_absClip stay nil
    -- until a zone is set to Absorb Short, so unused frames pay ZERO cost. content is the
    -- zone's resolved key: "absorbshort" gates shield absorbs, "healabsorbshort" gates
    -- heal absorbs (g._euiHealGate marks the source for the Override).
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
        ns.SetTextZone(frame, leftText, lc, "leftText", settings)
        ns.SetTextZone(frame, rightText, rc, "rightText", settings)
        ns.SetTextZone(frame, centerText, cc, "centerText", settings)
        ApplyAbsorbGate("left", leftText, lc)
        ApplyAbsorbGate("right", rightText, rc)
        ApplyAbsorbGate("center", centerText, cc)
        ns.UF_PaintText(frame, frame._euiUnit or unit)
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
            PP.Width(centerText, barW * 0.9 * SlotWidthMul(s, "centerText"))
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
                PP.Width(leftText, math.max(barW - rightUsed - 10, 20) * SlotWidthMul(s, "leftText"))
            else
                PP.Width(leftText, barW * 0.9 * SlotWidthMul(s, "leftText"))
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
                PP.Width(rightText, math.max(barW - leftUsed - 10, 20) * SlotWidthMul(s, "rightText"))
            else
                PP.Width(rightText, barW * 0.9 * SlotWidthMul(s, "rightText"))
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
    ns.ApplyHealthOrientation(health, settings)
    ApplyDarkTheme(health, unit)

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

    -- "Absorb Short" zero-hide: the [eui-absorbshort] tag shows the abbreviated absorb
    -- but cannot blank at zero (no has-absorb boolean exists), so we clip the text away
    -- when there is no shield, secret-safely: a binary StatusBar gate (max 1) is fed the
    -- raw absorb so its fill texture is full width with any shield and zero width with
    -- none; a clip frame tracks that fill rect and the zone FontString is reparented
    -- into it, clipping the text to nothing at zero absorb. Absorb is never compared to
    -- zero in Lua -- only fed to SetValue (accepts secrets natively). Driven every
    -- absorb update by the HealthPrediction Override. Lazy: _absGate/_absClip stay nil
    -- until a zone is set to Absorb Short, so unused frames pay ZERO cost. content is the
    -- zone's resolved key: "absorbshort" gates shield absorbs, "healabsorbshort" gates
    -- heal absorbs (g._euiHealGate marks the source for the Override).
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
        ns.SetTextZone(frame, leftText, lc, "leftText", settings)
        ns.SetTextZone(frame, rightText, rc, "rightText", settings)
        ns.SetTextZone(frame, centerText, cc, "centerText", settings)
        ApplyAbsorbGate("left", leftText, lc)
        ApplyAbsorbGate("right", rightText, rc)
        ApplyAbsorbGate("center", centerText, cc)
        ns.UF_PaintText(frame, frame._euiUnit or unit)
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
            PP.Width(centerText, barW * 0.9 * SlotWidthMul(s, "centerText"))
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
                PP.Width(leftText, math.max(barW - rightUsed - 10, 20) * SlotWidthMul(s, "leftText"))
            else
                PP.Width(leftText, barW * 0.9 * SlotWidthMul(s, "leftText"))
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
                PP.Width(rightText, math.max(barW - leftUsed - 10, 20) * SlotWidthMul(s, "rightText"))
            else
                PP.Width(rightText, barW * 0.9 * SlotWidthMul(s, "rightText"))
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
    -- Always create the absorb bar (visibility gated at render time). Boss frames
    -- carry no absorb settings of their own: they render with the TARGET frame's
    -- styling (donor convention, like textures) behind "Show on Boss Frames" in the
    -- absorb cog. Geometry (reverse fill) still comes from the boss block via `settings`.
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
    local extraContent = settings.extraTextContent or "none"

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

    -- Extra Text: a 4th text zone, identical to the others (same tags + absorb
    -- gate); it only anchors per extraTextAlign and is capped at 95% of the bar
    -- width (ellipsis truncation). Mirrors the Main Frames implementation.
    local extraText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(extraText, settings.extraTextSize or settings.textSize or 12)
    extraText:SetWordWrap(false)
    extraText:SetTextColor(1, 1, 1)
    frame.ExtraText = extraText

    frame.NameText = leftText
    frame.HealthValue = rightText

    -- "Absorb Short" zero-hide: the [eui-absorbshort] tag shows the abbreviated absorb
    -- but cannot blank at zero (no has-absorb boolean exists), so we clip the text away
    -- when there is no shield, secret-safely: a binary StatusBar gate (max 1) is fed the
    -- raw absorb so its fill texture is full width with any shield and zero width with
    -- none; a clip frame tracks that fill rect and the zone FontString is reparented
    -- into it, clipping the text to nothing at zero absorb. Absorb is never compared to
    -- zero in Lua -- only fed to SetValue (accepts secrets natively). Driven every
    -- absorb update by the HealthPrediction Override. Lazy: _absGate/_absClip stay nil
    -- until a zone is set to Absorb Short, so unused frames pay ZERO cost. content is the
    -- zone's resolved key: "absorbshort" gates shield absorbs, "healabsorbshort" gates
    -- heal absorbs (g._euiHealGate marks the source for the Override).
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

    local function ApplyTextTags(lc, rc, cc, ec)
        -- Callers that predate the Extra Text zone pass 3 args; fall back to
        -- the stored content so those sites keep working (same as Main Frames).
        ec = ec or (settings.extraTextContent or "none")
        ns.SetTextZone(frame, leftText, lc, "leftText", settings)
        ns.SetTextZone(frame, rightText, rc, "rightText", settings)
        ns.SetTextZone(frame, centerText, cc, "centerText", settings)
        ns.SetTextZone(frame, extraText, ec, "extraText", settings)
        ApplyAbsorbGate("left", leftText, lc)
        ApplyAbsorbGate("right", rightText, rc)
        ApplyAbsorbGate("center", centerText, cc)
        ApplyAbsorbGate("extra", extraText, ec)
        ns.UF_PaintText(frame, frame._euiUnit or unit)
    end
    ApplyTextTags(leftContent, rightContent, centerContent, extraContent)
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
        -- Extra Text: anchored per extraTextAlign (left/right/center); ellipsis-
        -- truncated past 95% of health bar width (SetWordWrap(false) + capped width below), matching Main Frames.
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
            PP.Width(extraText, barW * 0.95 * SlotWidthMul(s, "extraText"))
            extraText:Show()
            ApplyClassColor(extraText, unit, s.extraTextClassColor, s.extraTextColorR, s.extraTextColorG, s.extraTextColorB)
        else extraText:Hide() end
        -- Each text position renders independently; Center no longer hides Left/Right.
        SetFSFont(centerText, csz)
        centerText:ClearAllPoints()
        if cc ~= "none" then
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            PP.Width(centerText, barW * 0.9 * SlotWidthMul(s, "centerText"))
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
                PP.Width(leftText, math.max(barW - rightUsed - 10, 20) * SlotWidthMul(s, "leftText"))
            else
                PP.Width(leftText, barW * 0.9 * SlotWidthMul(s, "leftText"))
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
                PP.Width(rightText, math.max(barW - leftUsed - 10, 20) * SlotWidthMul(s, "rightText"))
            else
                PP.Width(rightText, barW * 0.9 * SlotWidthMul(s, "rightText"))
            end
            rightText:Show()
            ApplyClassColor(rightText, unit, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
        else rightText:Hide() end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions
end


-- (Styles are no longer registered anywhere: the spawn sites call
-- StyleFullFrame/StyleFocusFrame/StylePetFrame/StyleSimpleFrame/StyleBossFrame
-- directly, and the engine's portrait painter always routes through the shared
-- gated PortraitOverride.)


-- Swap portrait mode (3D/2D/class theme) without recreating frames: 2D and class
-- textures already exist on the backdrop, 3D PlayerModel is lazy-created on first use;
-- this just shows/hides and reassigns frame.Portrait.
local function SwapPortraitMode(frame)
    local portrait = frame.Portrait
    if not portrait or not portrait.backdrop then return end
    local bd = portrait.backdrop
    if not bd._2d then return end

    local wantMode
    do
        local unit2 = frame._euiUnit or frame:GetAttribute("unit")
        local uKey = UnitToSettingsKey(unit2)
        local s = uKey and db.profile[uKey]
        wantMode = (s and s.portraitMode) or db.profile.portraitMode or "2d"
    end

    local unit = frame._euiUnit or frame:GetAttribute("unit")

    local curMode
    if portrait.isClass then curMode = "class"
    elseif portrait.is2D then curMode = "2d"
    else curMode = "3d" end

    if wantMode == curMode then return end

    -- (No event surgery needed on a mode swap: the engine's portrait painter
    -- targets whatever frame.Portrait currently is.)

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
        if issecretvalue(ct) then ct = nil end
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

    -- Repaint through the new object immediately.
    if frame.EnableElement then frame:EnableElement("Portrait") end
    ns.UF_StampPortraitForceUpdate(frame)
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

-- Fixed child-born shells for the class-power event driver and castbar watcher. The
-- class-power bar is destroyed/rebuilt on spec switches through the profile system,
-- whose dispatch runs under the PARENT addon's execution context -- and the engine
-- bills a handler's entire call tree to the addon whose context created the frame, so
-- drivers recreated there would bill the parent's CPU row. Creating them ONCE here
-- (child main chunk) and reconfiguring per build keeps every rebuild attribution-safe.
ns._cpDriver = CreateFrame("Frame")
ns._cpDriver:Hide()
ns._cpCastWatcher = CreateFrame("Frame")
ns._cpCastWatcher:Hide()

-- 10 Hz anim tickers for the two class-power polls. A per-frame OnUpdate that
-- early-outs to a 0.1s cadence still pays a full Lua entry every render frame (pure
-- dispatch tax at high fps); a looping Animation fires the body at the real cadence and
-- the C engine sleeps between fires. Created HERE (child main chunk) since the
-- AnimationGroup is the engine's entry object and bills its creation context. Bodies
-- read a swappable ns function so per-build closures stay per-build; a ticker runs only
-- between Start()/Stop() and pauses while its host is hidden.
ns._cpDriverTick = EllesmereUI.Tick.NewAnimTicker(ns._cpDriver, function()
    local fn = ns._cpTickFn
    if fn then fn() end
    return true
end, 0.1)
ns._cpWatchTick = EllesmereUI.Tick.NewAnimTicker(ns._cpCastWatcher, function()
    local fn = ns._cpWatchFn
    if fn then fn() end
    return true
end, 0.1)

local function DestroyCustomClassPower()
    ns._cpTickFn = nil
    ns._cpDriverTick.Stop()
    ns._cpWatchFn = nil
    ns._cpWatchTick.Stop()
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
    -- For bar-mode resources (stagger), "maxPower" is a raw game value (e.g. player max
    -- HP) and doesn't drive layout width. Use a 5-pip equivalent so the bar matches the
    -- visual footprint of Chi / Combo Points etc.
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
    -- Tracks how many pips are CURRENTLY shown, separate from #pips: pip frames
    -- are only ever Hide()'d when the resource max drops (never removed from the
    -- table), so #pips is a high-water mark that stops matching a shrunk-then-
    -- regrown max and silently skips the rebuild below.
    local shownPipCount = 0
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
        shownPipCount = maxPower
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

        -- Rebuild pips if max changed. Compare against shownPipCount, not #pips:
        -- #pips only ever grows (hidden pips stay in the table), so it stops
        -- matching once max shrinks and regrows to a previously-seen value,
        -- leaving the high pips stuck hidden and the container stuck narrow.
        if max ~= shownPipCount and max > 0 then
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
            shownPipCount = max
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

    -- Event driver: the shared child-born shell (see ns._cpDriver above), fully reset
    -- here since the previous spec's build may have left registrations or a poll on it.
    local eventFrame = ns._cpDriver
    eventFrame:UnregisterAllEvents()
    eventFrame:SetScript("OnEvent", nil)
    ns._cpTickFn = nil
    ns._cpDriverTick.Stop()
    eventFrame:SetParent(container)
    eventFrame:Show()
    if isCustom then
        -- Per-resource event registration: only register what each resource actually
        -- needs. Icicles and Maelstrom Weapon are aura-driven; everything else polls
        -- via OnUpdate (either Lua API changes mid-combat, or no reliable event exists).
        local auraDriven    = (powerType == "MAELSTROM_WEAPON" or powerType == "ICICLES")
        local needsOnUpdate = not auraDriven
        local needsAura     = auraDriven
        local needsCasts    = (powerType == "TIP_OF_THE_SPEAR" or powerType == "WHIRLWIND_STACKS"
                               or powerType == "SWEEPING_STRIKES")

        if needsOnUpdate then
            -- 10 Hz poll on the shared anim ticker (see ns._cpDriverTick):
            -- same cadence as the old OnUpdate accumulator without the
            -- per-render-frame entry tax.
            ns._cpTickFn = UpdatePips
            ns._cpDriverTick.Start()
        end

        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- PLAYER_SPECIALIZATION_CHANGED is deliberately NOT registered here. It is owned
        -- by cpSpecWatcher (see InitializeFrames), which lives OUTSIDE the container,
        -- filters unit == "player", and rebuilds after tearing down. A copy of that
        -- handler on this driver could only ever destroy WITHOUT rebuilding (the
        -- teardown unregisters the driver mid-dispatch), and -- lacking the unit filter
        -- -- would fire on any GROUP MEMBER's spec event, silently killing the bar until
        -- the next /reload.
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
            if event == "UNIT_SPELLCAST_SUCCEEDED" then
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

-- Custom enemy reaction colors: override the shared reaction/tapped color table from
-- db.profile.enemyColors, then repaint live frames. Each entry defaults to Blizzard
-- FACTION_BAR_COLORS when unset, so this is idempotent and reset-safe (re-applies the
-- active profile's colors on profile swap). Hostile = reactions 1-3, Neutral = 4, Friendly = 5-8.
local function ApplyEnemyColors()
    if not (ns.Colors and ns.Colors.reaction and FACTION_BAR_COLORS) then return end
    local ec = (db and db.profile and db.profile.enemyColors) or {}
    local function setIdx(idx, custom)
        local f = FACTION_BAR_COLORS[idx]
        local r = (custom and custom.r) or (f and f.r) or 1
        local g = (custom and custom.g) or (f and f.g) or 1
        local b = (custom and custom.b) or (f and f.b) or 1
        ns.Colors.reaction[idx] = CreateColor(r, g, b)
    end
    for i = 1, 3 do setIdx(i, ec.hostile)  end
    setIdx(4, ec.neutral)
    for i = 5, 8 do setIdx(i, ec.friendly) end
    local tc = ec.tapped
    ns.Colors.tapped = CreateColor((tc and tc.r) or 0.6, (tc and tc.g) or 0.6, (tc and tc.b) or 0.6)
    ns.Engine.ForceAll("OnShow")
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
            -- Any unit with its own settings table can override the global
            -- strata; nil (the default) means "follow the global value".
            -- GetSettingsForUnit maps boss1..boss5 onto the shared boss table
            -- and falls back to the player's settings, which is what the
            -- non-unit entries in `frames` (the class power bar above all)
            -- should ride with anyway.
            local strata = ufStrata
            local us = GetSettingsForUnit(unitKey)
            if us and us.frameStrata then strata = us.frameStrata end
            frame:SetFrameStrata(strata)
            -- Re-apply or reset custom strata for detached bars
            if frame.BottomTextBar and frame.BottomTextBar._isDetached then
                if profile.enableCustomBarStratas then
                    frame.BottomTextBar:SetFrameStrata(profile.detachedTextBarStrata or "DIALOG")
                else
                    frame.BottomTextBar:SetFrameStrata(strata)
                end
            end
            -- Same re-lift for a detached power bar: frame:SetFrameStrata above just
            -- reset it to the frame's strata (same reason the cast bar needs re-lifting
            -- below), so without this it silently falls back to the frame's strata and
            -- can end up behind the frame's own border, however "Detached Power Bar" strata is configured.
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
            -- The cast bar is a child of the frame, so SetFrameStrata above reset it to
            -- the frame's strata. Lift to HIGH so it never hides behind other MEDIUM-
            -- strata frames, unless "Raise Cast Bar Strata (All)" is off, in which case
            -- it's explicitly left at the frame's strata.
            if frame.Castbar and (unitKey == "player" or IsKickCastbarUnit(unitKey)) then
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
            -- A secure condition driver owns this frame's Show/Hide (group gating
            -- included); manual toggling here would de-sync it until the next driver
            -- re-evaluation. The visibility pass converts the driver when disabled.
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
                -- The engine repaints in full on show (OnShow hook) and drops
                -- events for hidden frames at dispatch, so nothing needs
                -- re-enabling; one explicit pass covers the pre-show window.
                ns.Engine.RepaintAll(frame, "ToggleFrame")
            end
        else
            if frame:IsShown() then
                -- Hidden frames already cost nothing: the engine drops their
                -- events at dispatch and the poller skips them.
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

            -- Keep the cached portrait side in sync with user-edited settings. Downstream
            -- re-snap code (SnapLayout, health anchor math) reads this lookup, so without
            -- it the side toggle wouldn't flip until a full UI reload.
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
                    if issecretvalue(ct) then ct = nil end
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
                                local isCst = UnitClassBase and UnitClassBase(unit); if issecretvalue(isCst) then isCst = nil end; isCst = (isCst == "PALADIN")
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
                            ns.SetCastbarElement(frame, true)
                            if castbarBg then
                                local cbW = db.profile.player.playerCastbarWidth or 181
                                local cbH = db.profile.player.playerCastbarHeight or 14
                                PP.Size(castbarBg, cbW, cbH)
                                if castbarBg._bgTex then
                                    local cbg = settings.castBgColor
                                    castbarBg._bgTex:SetColorTexture(cbg and cbg.r or 0, cbg and cbg.g or 0, cbg and cbg.b or 0, settings.castBgAlpha or 0.5)
                                end
                                local pIconOffX, pIconOffY = CastIconOffsets("player", settings)
                                LayoutCastbarIcon(frame.Castbar, CastIconInWidth("player", settings), nil, CastIconOnRight("player", settings), pIconOffX, pIconOffY, CastIconShown("player", settings))
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
                            -- Fill Opacity below 100: the tint layer is the visible
                            -- fill at that opacity; zero the base fill so it cannot
                            -- bleed through the translucent tint.
                            frame.Castbar:SetStatusBarColor(pCbColor.r, pCbColor.g, pCbColor.b,
                                ((settings.castFillOpacity or 100) < 100) and 0 or castbarOpacity)
                            ns.ApplyCastFillOpacity(frame.Castbar, settings)
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
                                if frame.Castbar._syncOffsetsAndLayout then
                                    frame.Castbar:_syncOffsetsAndLayout(settings)
                                end
                            end
                        else
                            ns.SetCastbarElement(frame, false)
                            frame.Castbar:Hide()
                            if castbarBg then castbarBg:Hide() end
                        end
                    end

                    -- Live toggle + style player absorbs. Never Enable/Disable the oUF
                    -- HealthPrediction element here: tearing it down unregisters events
                    -- and resets the calculator, which goes stale on the player frame
                    -- specifically (target/focus don't do this toggle and stay accurate).
                    -- Just Show/Hide the bar -- the element keeps running in the
                    -- background and the value stays live either way.
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
                                local isCst = UnitClassBase and UnitClassBase(unit); if issecretvalue(isCst) then isCst = nil end; isCst = (isCst == "PALADIN")
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
                                local tIconOffX, tIconOffY = CastIconOffsets("target", settings)
                                LayoutCastbarIcon(frame.Castbar, CastIconInWidth("target", settings), nil, CastIconOnRight("target", settings), tIconOffX, tIconOffY, CastIconShown("target", settings))
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
                        -- Fill Opacity below 100: tint layer carries the visible
                        -- fill; zero the base so it cannot bleed through.
                        frame.Castbar:SetStatusBarColor(tCbColor.r, tCbColor.g, tCbColor.b,
                            ((settings.castFillOpacity or 100) < 100) and 0 or castbarOpacity)
                        ns.ApplyCastFillOpacity(frame.Castbar, settings)
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
                            local fIconOffX, fIconOffY = CastIconOffsets("focus", settings)
                            LayoutCastbarIcon(frame.Castbar, CastIconInWidth("focus", settings), nil, CastIconOnRight("focus", settings), fIconOffX, fIconOffY, CastIconShown("focus", settings))
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
                    -- Fill Opacity below 100: tint layer carries the visible
                    -- fill; zero the base so it cannot bleed through.
                    frame.Castbar:SetStatusBarColor(fCbColor.r, fCbColor.g, fCbColor.b,
                        ((settings.castFillOpacity or 100) < 100) and 0 or castbarOpacity)
                    ns.ApplyCastFillOpacity(frame.Castbar, settings)
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
                            local isCst = UnitClassBase and UnitClassBase(unit); if issecretvalue(isCst) then isCst = nil end; isCst = (isCst == "PALADIN")
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
                            local bIconOffX, bIconOffY = CastIconOffsets("boss1", settings)
                            LayoutCastbarIcon(frame.Castbar, CastIconInWidth("boss1", settings), nil, CastIconOnRight("boss1", settings), bIconOffX, bIconOffY, CastIconShown("boss1", settings))
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
                            -- bar's bottom: health/power bars live in the half-pixel-inset bar
                            -- clip, which left a ~1px gap below the frame. Cast bar is full
                            -- frame width, so frame bottom-center keeps it centered + flush.
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
                    frame.Castbar:SetStatusBarColor(bCbColor.r, bCbColor.g, bCbColor.b,
                        ((settings.castFillOpacity or 100) < 100) and 0 or castbarOpacity)
                    ns.ApplyCastFillOpacity(frame.Castbar, settings)
                    if frame.Castbar:IsShown() then
                        ApplyUnitFrameCastColor(frame.Castbar)
                        UpdateUnitFrameKickTick(frame.Castbar)
                    end
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
                frame._isTarget = (not issecretvalue(isT) and isT) and true or false
                ns.ApplyBossBorderState(frame)
            end
            frame.Health:SetReverseFill(settings.healthReverseFill and true or false)
            ns.ApplyHealthOrientation(frame.Health, settings)
            ApplyDarkTheme(frame.Health, unit)  -- re-anchors health.bg for the new axis
            UpdateAbsorbBarReverseFill(frame, settings.healthReverseFill and true or false, settings)
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
                        -- Power-color mode (no gradient): explicitly paint the bar so it
                        -- doesn't depend on oUF's colors.power being synced.
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
                -- Reverse-fill direction is only final here; re-derive Fill Opacity state
                -- (ApplyPowerBarAlpha above ran before this SetReverseFill, so a direction
                -- change would otherwise leave the bg anchored to the wrong side).
                ApplyPowerBarAlpha(frame.Power, UnitToSettingsKey(unit))
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
                -- (colors/show/sides/bg). Two gaps remain: the donor-font line just above
                -- set boss cast text to the DONOR size, and that branch re-runs layout from
                -- CACHED offsets. Re-apply the size from boss settings (keeping the donor
                -- typeface) and sync X/Y offsets + side layout so live boss frames update
                -- on every cast-text option change.
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

    -- Refresh elite/rare indicator on the target frame after settings change
    if frames.target and frames.target._applyEliteIndicator then
        frames.target._applyEliteIndicator()
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

    -- Portrait settings (3D zoom, class style) used to live-apply through the ungated
    -- ambient repaints; the gated Override skips same-unit repaints, so settings
    -- changes now force one explicit portrait update per frame instead.
    for _, frame in pairs(frames) do
        if type(frame) == "table" and frame.Portrait and frame.Portrait.ForceUpdate then
            frame.Portrait:ForceUpdate()
        end
    end

    -- Player Aura Bars resolve font path and outline flag at style-build time; every
    -- settings path landing here (fonts, profiles, options) forces one explicit
    -- re-skin of the default and custom bars, both change-guarded no-ops when nothing changed.
    if ns.PAB_Restyle then ns.PAB_Restyle() end
    -- Profile-grade resync: enable/useBlizzard modes, native frames, default
    -- movers, and a late build when a swap lands on an enabled profile from
    -- a disabled-at-login session. Cheap no-op when nothing changed.
    if ns.PAB_ProfileResync then ns.PAB_ProfileResync() end
    -- Reload-all also SWEEPS stale bar ids (a previous profile's bars must
    -- park on swap -- field report).
    if ns.PAB_ReloadAllCustomBars then ns.PAB_ReloadAllCustomBars() end
end

-- Toggle a frame's oUF Castbar element without rewriting Blizzard's cast bar event
-- registration. oUF silences PlayerCastingBarFrame/PetCastingBarFrame when the element
-- enables on the player frame and re-arms them when it disables; the shared helpers
-- keep whatever a standalone cast bar addon set. On ns for the 200-locals cap.
function ns.SetCastbarElement(frame, enable)
    if not frame or not frame.Castbar then return end
    if (frame:IsElementEnabled("Castbar") and true or false) == (enable and true or false) then return end
    EllesmereUI.CaptureBlizzCastBarEvents()
    if enable then
        frame:EnableElement("Castbar")
    else
        frame:DisableElement("Castbar")
    end
    EllesmereUI.RestoreBlizzCastBarEvents()
end

-- Manage Blizzard's player cast bar ownership based on whether UnitFrames renders its
-- own player cast bar. oUF already handles event plumbing for its own castbar element;
-- this helper only coordinates suppression with other EUI modules and releases control
-- cleanly for external addons.
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

-- Effective whole-frame alpha for a unit frame. When "Fade Out of Combat" is enabled
-- and the player is out of combat, shows at oocAlpha; otherwise full opacity (off by
-- default, existing setups unchanged). Every "shown" SetAlpha site (visibility loop +
-- mouseover hover) routes through this so a combat transition or hover can't clobber
-- the fade. Combat state comes from the caller (the visibility loop's event-tracked
-- _ufInCombat, which leads InCombatLockdown() on regen events). On ns for the 200-locals cap.
function ns.ResolveFrameAlpha(s, inCombat)
    if s and s.oocFadeEnabled and not inCombat then
        return s.oocAlpha or 0.5
    end
    return 1
end

local function UnitFrame_OnEnter(self)
    local unit = self._euiUnit
    if not unit then return end
    local unitKey = unit:match("^boss%d$") and "boss" or unit
    local s = db and db.profile and db.profile[unitKey]
    if s and (s.barVisibility or "always") == "mouseover" then
        -- Hover-gated sets only reveal while their conditions pass; a
        -- legacy single "mouseover" reveals unconditionally as before.
        local eligible = true
        if EllesmereUI.VisWantsMouseover then
            eligible = EllesmereUI.VisWantsMouseover(s, "barVisibility", nil, EllesmereUI.VIS_CAPS_DEFAULT)
        end
        if eligible then
            local a = ns.ResolveFrameAlpha(s, InCombatLockdown())
            ;(self._visWrap or self):SetAlpha(a)
            -- 3D models don't inherit parent alpha: reveal the portrait too
            local bd3d = self.Portrait and self.Portrait.backdrop and self.Portrait.backdrop._3d
            if bd3d then bd3d:SetAlpha(a) end
            -- Mini-frame inheritance: the companion frame reveals with us.
            -- Always Show Pet Frame opts the pet out (it is already visible
            -- and must not pick up the player's fade alpha).
            local mini = ns.UF_MINI_OF and frames[ns.UF_MINI_OF[unitKey]]
            if mini and not (unitKey == "player" and db.profile.pet and db.profile.pet.alwaysShow) then
                mini:SetAlpha(a)
            end
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
                if GameTooltip:SetUnit(self._euiUnit) then
                    GameTooltip:Show()
                end
            end)
        end
    end
end

local function UnitFrame_OnLeave(self)
    local unit = self._euiUnit
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
            -- Shared walk over every option lane: a hand-written subset here left a frame
            -- fading out on mouse leave whenever it used a lane the list had not caught up to.
            local hasAnyHideOpt = EllesmereUI and EllesmereUI.VisHasAnyOption
                               and EllesmereUI.VisHasAnyOption(s)
            local keepShown = (not hiddenByOpts) and hasAnyHideOpt
            leaveAlpha = keepShown and ns.ResolveFrameAlpha(s, InCombatLockdown()) or 0
        end
        ;(self._visWrap or self):SetAlpha(leaveAlpha)
        -- 3D models don't inherit parent alpha: hide/dim the portrait too
        local bd3d = self.Portrait and self.Portrait.backdrop and self.Portrait.backdrop._3d
        if bd3d then bd3d:SetAlpha(leaveAlpha) end
        -- Mini-frame inheritance: the companion frame hides/dims with us.
        -- Always Show Pet Frame opts the pet out (a leave alpha of 0 would
        -- hide a pet frame that must stay visible).
        local mini = ns.UF_MINI_OF and frames[ns.UF_MINI_OF[unitKey]]
        if mini and not (unitKey == "player" and db.profile.pet and db.profile.pet.alwaysShow) then
            mini:SetAlpha(leaveAlpha)
        end
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

    local classPowerStyle = db.profile.player.classPowerStyle or "none"
    -- Per-unit frame source, resolved once for this build. When a unit is set to
    -- "blizzard" (leave Blizzard's default frame) or "hidden", the EllesmereUI frame is
    -- not spawned at all -- the ONLY way to keep Blizzard's own frame alive, since
    -- oUF:Spawn() permanently disables it.
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

    local function SetupUnitMenu(frame, unit)
        -- Register ALL mouse buttons (matches raid/party's "AnyUp"), not just
        -- left/right. These frames bind nothing to middle/thumb themselves, so
        -- an unbound middle/thumb click still does nothing here -- but Blizzard's
        -- built-in click-casting (and Clique) sets its own type3/type4/type5
        -- attributes on frames registered in ClickCastFrames, and needs the
        -- click event to actually be delivered to fire. Left-button-only
        -- registration silently ate those clicks whenever EUI's own click-cast
        -- engine wasn't the one driving RegisterForClicks (i.e. EUI's engine
        -- disabled, native/Clique click-casting relied on instead).
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
        -- Expose to click-casting via the standard global table. EUI unit frames
        -- replace the Blizzard ones, which the click-cast engine registers by name --
        -- but those are hidden, so the engine never reaches the visible frames.
        -- Registering ours here lets click-casting (EUI's engine when "All Unit
        -- Frames" is on, or Clique otherwise) apply the same bindings + unbound-click
        -- suppression it uses on raid/party. The engine captures/restores each
        -- frame's native click attrs, so these keep their own defaults (no forced
        -- left-click target) when click-cast is off.
        if type(ClickCastFrames) ~= "table" then ClickCastFrames = {} end
        ClickCastFrames[frame] = true
        -- NO ping mixin here, deliberately (three field rounds, 2026-08-24):
        -- an addon-installed PingableType mixin CANNOT serve secret-content
        -- units. Reading our tainted GetIsPingable inside PingManager's
        -- securecalled helper taints that execution, every unit value
        -- Blizzard's own mixin then fetches comes back tainted-restricted,
        -- and the secure caller's securecopy of the GetTargetInfo table
        -- hard-errors ("inaccessible secret") -- even with our getter
        -- returning nil. The reported enemy-target-frame ping error also
        -- reproduces with NO EUI receiver in the path (pre-mixin trace, No
        -- Lua Taint) and is upstream. Do not re-attempt.
    end

    -- Spawn each unit's EllesmereUI frame only when its source is "eui". A unit set to
    -- "blizzard" keeps Blizzard's own frame (we never spawn or suppress for it);
    -- "hidden" removes Blizzard's frame too.
    if playerFrameSource == "eui" then
        -- Spawning enables the Castbar element, which silences Blizzard's
        -- player/pet cast bars. Keep whatever a standalone cast bar addon set.
        EllesmereUI.CaptureBlizzCastBarEvents()
        frames.player = ns.Engine.SpawnUnitFrame("player", "EllesmereUIUnitFrames_Player")
        StyleFullFrame(frames.player, "player")
        ns.UF_AttachEngineFrame(frames.player, "player")
        EllesmereUI.RestoreBlizzCastBarEvents()
    elseif playerFrameSource == "hidden" then
        -- Wrapped for the same reason as the spawn above: the suppression
        -- unregisters PlayerFrame's cast bar child, and an unregister seen
        -- outside a capture window reads as a third-party addon claiming the
        -- frame -- EUI would mark its own silence as somebody else's and
        -- never hand the bar back.
        EllesmereUI.CaptureBlizzCastBarEvents()
        ns.Engine.HideBlizzardUnitFrame("player")
        EllesmereUI.RestoreBlizzCastBarEvents()
    end

    -- Visibility wrapper for the player frame only. Parent the player frame to a
    -- non-secure wrapper and drive visibility via the wrapper's alpha instead of the
    -- frame's own: alpha inherits multiplicatively down the parent chain, so the
    -- wrapper's alpha wins regardless of anything touching the inner frame's alpha
    -- directly (oUF elements, combat transitions, etc.). Target/focus/pet don't need
    -- this since RegisterUnitWatch already handles their visibility via unit
    -- existence. The wrapper is inserted between the player frame and whatever parent
    -- oUF originally gave it (PetBattleFrameHider), so the pet-battle state driver
    -- chain continues to work.
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
            -- Deferred: EDIT_MODE_LAYOUTS_UPDATED dispatches from inside Edit Mode's own
            -- operations; applying suppression state there writes cast bar state
            -- mid-pass (same taint mechanism as the DisableBlizzard override above).
            C_Timer.After(0, ApplyBlizzCastbarState)
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

    -- The expected parent for the Blizzard class power bar after positioning, set by
    -- PositionClassPowerBar so the SetParent hook knows what's correct. MUST be
    -- declared before PositionClassPowerBar, or the function assigns a global while
    -- the hook reads this always-nil local (falling back to frames.player even for
    -- UIParent-parented bars).
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
            ns._cpWatchFn = nil
            ns._cpWatchTick.Stop()
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
                    -- Shared child-born shell (see ns._cpCastWatcher): a frame created
                    -- here would be born in whatever context triggered this rebuild and
                    -- could bill the parent for the 10 Hz poll below.
                    bar._castbarWatcher = ns._cpCastWatcher
                    bar._castbarWatcher:SetParent(bar)
                end
                local playerFrame = frames.player
                -- 10 Hz body on the shared anim ticker (see ns._cpWatchTick).
                ns._cpWatchFn = function()
                    local cb = playerFrame and playerFrame.Castbar
                    local castbarBg = cb and cb:GetParent()
                    local nowVis = castbarBg and castbarBg:IsShown() and db.profile.player.showPlayerCastbar
                    if nowVis ~= bar._lastCastVis then
                        bar._lastCastVis = nowVis
                        AnchorBottom()
                    end
                end
                bar._castbarWatcher:Show()
                ns._cpWatchTick.Start()
            end
            ResizeFrameForClassPower(0)
        end
        bar:SetFrameStrata(frames.player:GetFrameStrata())
        bar:SetFrameLevel(frames.player:GetFrameLevel() + 5)
        bar:Show()
    end

    -- Hook Blizzard class power bar so form/spec changes can't steal it back. Hooks
    -- SetParent to re-assert our parent, Show/Hide to keep it visible, and
    -- ClearAllPoints to catch anchors getting stripped without a reparent (seen
    -- during in-engine cutscenes/UI transitions -- parent and IsShown() stay
    -- correct, but GetNumPoints() drops to 0 and the frame renders nowhere).
    -- Only active while classPowerStyle == "blizzard".
    local _blizzCPHooked = false
    local _blizzCPActive = false  -- true while we own the bar

    local function HookBlizzardClassPower(cpFrame)
        if _blizzCPHooked then return end
        _blizzCPHooked = true
        local _cpSetParentGuard = false
        -- All hooks defer their re-assert work: they can fire inside Blizzard's
        -- secure Edit Mode layout pass (same taint mechanism as the DisableBlizzard
        -- override above), and wait for the manager to close before re-asserting.
        local _cpReassertQueued = false
        local ReassertClassPower
        ReassertClassPower = function(self)
            _cpReassertQueued = false
            if not _blizzCPActive then return end
            if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
                _cpReassertQueued = true
                C_Timer.After(0.25, function() ReassertClassPower(self) end)
                return
            end
            local wanted = _cpExpectedParent or frames.player or UIParent
            if self:GetParent() ~= wanted or (self:GetNumPoints() or 0) == 0 then
                _cpSetParentGuard = true
                PositionClassPowerBar(self)
                -- Blizzard may have re-stolen during PositionClassPowerBar.
                -- The anchor is already correct, so just fix the parent directly.
                if self:GetParent() ~= wanted then
                    self:SetParent(wanted)
                end
                _cpSetParentGuard = false
            end
            if not self:IsShown() and not InCombatLockdown() then self:Show() end
        end
        -- Re-assert position when Blizzard reparents (form/spec changes).
        hooksecurefunc(cpFrame, "SetParent", function(self, newParent)
            if not _blizzCPActive or _cpSetParentGuard or _cpReassertQueued then return end
            local wanted = _cpExpectedParent or frames.player or UIParent
            if newParent ~= wanted then
                _cpReassertQueued = true
                C_Timer.After(0, function() ReassertClassPower(self) end)
            end
        end)
        hooksecurefunc(cpFrame, "Hide", function(self)
            if not _blizzCPActive or _cpReassertQueued then return end
            _cpReassertQueued = true
            C_Timer.After(0, function() ReassertClassPower(self) end)
        end)
        -- Re-assert anchors when something strips them without a reparent (the
        -- cutscene case above). Guarded by _cpSetParentGuard the same way as
        -- SetParent so our own PositionClassPowerBar's internal ClearAllPoints
        -- doesn't recurse back into itself.
        hooksecurefunc(cpFrame, "ClearAllPoints", function(self)
            if not _blizzCPActive or _cpSetParentGuard or _cpReassertQueued then return end
            _cpReassertQueued = true
            C_Timer.After(0, function() ReassertClassPower(self) end)
        end)
    end

    -- Seed the built-style marker so the first reload does not mistake a nil
    -- marker for a change. Written ONLY at build sites (here and the toggle):
    -- PositionClassPowerBar is repositioning, called by ReassertClassPower from
    -- Blizzard's SetParent/Hide hooks with no rebuild behind it, and stamping
    -- there would suppress the rebuild this exists to trigger. frames.player
    -- guard matches _toggleClassPower.
    if frames.player then frames._classPowerBuiltStyle = classPowerStyle end
    if classPowerStyle ~= "none" and frames.player then
        if classPowerStyle == "blizzard" then
            if savedClassPowerBar then
                _blizzCPActive = true
                savedClassPowerBar.ignoreFramePositionManager = true
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
        -- What is actually BUILT right now. Read by the reload pass below to
        -- notice a style that changed through a path which never calls this
        -- function (see the reload hook).
        frames._classPowerBuiltStyle = style
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
            frames._classPowerBar.ignoreFramePositionManager = nil
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
                cpFrame.ignoreFramePositionManager = true
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
        if frames._classPowerBar then
            frames._classPowerBar.ignoreFramePositionManager = nil
        end
        frames._classPowerBar = nil
        C_Timer.After(0.1, function()
            if ns.ReloadFrames then ns.ReloadFrames() end
            if frames._toggleClassPower then
                frames._toggleClassPower()
            end
        end)
    end)

    -- Durably suppress a live Blizzard child frame (target-of-target/focus-target).
    -- These are PROTECTED CHILDREN of TargetFrame/FocusFrame: when the parent uses
    -- Blizzard's source it stays alive and re-drives the child (TargetOfTargetMixin:
    -- Update) on every target change, undoing a one-shot Hide. We unregister its
    -- events and re-hide on OnShow.
    --
    -- KNOWN LIMITATION (in-combat double frame): the child is protected, so Hide() is
    -- blocked in combat. If the player changes target mid-combat, Blizzard (secure)
    -- re-Shows the native child and our OnShow re-hide can't fire until
    -- PLAYER_REGEN_ENABLED -- so with the parent on Blizzard Default and this mini
    -- frame on EllesmereUI/Hidden, the native child stays visible for the WHOLE combat
    -- (not just a flash), sitting alongside the EllesmereUI frame (or showing despite
    -- "Hidden"). Not fixable without reparenting/overriding a secure frame in combat,
    -- so it's surfaced in the mini-frame "Frame Source" tooltip (BuildFoTToTOptions),
    -- which recommends matching the parent's source instead of mixing them.
    local _suppressedChildren, _suppressWatcher, _rehidePending
    -- Deferred re-hide: OnShow fires inside whatever secure execution showed the parent
    -- (target swaps, Edit Mode's preview pass on a Blizzard-source TargetFrame/
    -- FocusFrame); hiding inline there taints the rest of that execution (same
    -- mechanism as the DisableBlizzard override above). While Edit Mode is open the
    -- re-hide waits for it to close.
    local _DeferredRehide
    _DeferredRehide = function(frame)
        _rehidePending[frame] = nil
        if not frame:IsShown() then return end
        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
            _rehidePending[frame] = true
            C_Timer.After(0.25, function() _DeferredRehide(frame) end)
        elseif InCombatLockdown() then
            _suppressWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            frame:Hide()
        end
    end
    local function SuppressBlizzardChildFrame(frame)
        if not frame then return end
        frame:UnregisterAllEvents()
        if not InCombatLockdown() then frame:Hide() end
        _suppressedChildren = _suppressedChildren or {}
        _rehidePending = _rehidePending or {}
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
                if not _rehidePending[self] then
                    _rehidePending[self] = true
                    C_Timer.After(0, function() _DeferredRehide(self) end)
                end
            end)
        end
    end

    local targetFrameSource = ns.GetUnitFrameSource("target")
    if targetFrameSource == "eui" then
        frames.target = ns.Engine.SpawnUnitFrame("target", "EllesmereUIUnitFrames_Target")
        StyleFullFrame(frames.target, "target")
        ns.UF_AttachEngineFrame(frames.target, "target")
        ApplyFramePosition(frames.target, "target")
        SetupUnitMenu(frames.target, "target")
    elseif targetFrameSource == "hidden" then
        ns.Engine.HideBlizzardUnitFrame("target")
    end

    local focusFrameSource = ns.GetUnitFrameSource("focus")
    if focusFrameSource == "eui" then
        frames.focus = ns.Engine.SpawnUnitFrame("focus", "EllesmereUIUnitFrames_Focus")
        StyleFocusFrame(frames.focus, "focus")
        ns.UF_AttachEngineFrame(frames.focus, "focus")
        ApplyFramePosition(frames.focus, "focus")
        SetupUnitMenu(frames.focus, "focus")
    elseif focusFrameSource == "hidden" then
        ns.Engine.HideBlizzardUnitFrame("focus")
    end

    -- Combat indicator overlay on the player + target frames. Each shows its OWN
    -- unit's combat state: player via the exact regen events, target via UNIT_FLAGS
    -- (combat flag changes) + PLAYER_TARGET_CHANGED re-evaluation. Target defaults to
    -- "none" (opt-in); player keeps its legacy default. Must run after the target
    -- frame is spawned (right above).
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
            if issecretvalue(classToken) then classToken = nil end
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

    -- Leader indicator (crown when unit is group/raid leader). oUF doesn't attach
    -- LeaderIndicator dynamically after Spawn(), so we drive the texture ourselves: own
    -- events, own UnitIsGroupLeader check, own show/hide. Must run after the target
    -- frame is spawned (above) so the texture can be parented to it.
    do
        local _leaderUnits = {}

        local function _leaderRefresh(uf)
            local s = uf and uf._leaderSettings
            if not (uf and uf._leaderIndicator and s) then return end
            local tex = uf._leaderIndicator
            if s.leaderIndicatorEnabled == false then tex:Hide(); return end
            -- The oUF unit token can still be unassigned when the setup-time
            -- refresh runs (login/reload timing), and the API rejects a nil
            -- unit outright. Hide and stand down: the leader/roster/target
            -- events below re-run this refresh once the unit exists.
            local unit = uf._euiUnit
            if not unit or (issecretvalue and issecretvalue(unit)) then tex:Hide(); return end
            local isLeader = UnitIsGroupLeader(unit)
            local isAssist = UnitIsGroupAssistant(unit)
            -- Secrecy check MUST run before any truthiness test: boolean-testing
            -- a secret errors, so "value and not issecretvalue(value)" crashes.
            if not issecretvalue(isLeader) and isLeader then
                tex:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
                tex:Show()
            elseif not issecretvalue(isAssist) and isAssist then
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

    -- Elite/Rare indicator (classification badge on the target frame), driven like the
    -- leader indicator above: own events, own refresh, own show/hide. Atlas mapping
    -- matches the nameplates classification badges exactly, so the two features read
    -- as one system. Show in Instances (default off) keeps it quiet in dungeons/raids, where most enemies are elite.
    do
        local function _eliteAtlas(c)
            if c == "elite" or c == "worldboss" then
                return "nameplates-icon-elite-gold"
            elseif c == "rareelite" then
                return "nameplates-icon-elite-silver"
            elseif c == "rare" then
                return "nameplates-icon-rareelite"
            end
        end

        local _eliteFrames = {}
        local eliteEvents

        local function _eliteRefresh(uf)
            local s = uf and uf._eliteSettings
            if not (uf and uf._eliteIndicator and s) then return end
            local tex = uf._eliteIndicator
            if s.eliteIndicatorEnabled ~= true then tex:Hide(); return end
            if not s.eliteIndicatorShowInInstances and IsInInstance() then
                tex:Hide(); return
            end
            local c = UnitClassification(uf._euiUnit)
            -- Secrecy check MUST run before any comparison, same rule as the
            -- leader checks above.
            local atlas = (not issecretvalue(c)) and _eliteAtlas(c) or nil
            if atlas then
                tex:SetAtlas(atlas)
                tex:Show()
            else
                tex:Hide()
            end
        end

        -- Events are registered only while the feature is enabled somewhere
        -- (zero cost while off) and re-armed from every settings apply.
        local function _eliteArmEvents()
            local on = false
            for i = 1, #_eliteFrames do
                local s = _eliteFrames[i]._eliteSettings
                if s and s.eliteIndicatorEnabled == true then on = true; break end
            end
            if on then
                if not eliteEvents then
                    eliteEvents = CreateFrame("Frame")
                    eliteEvents:SetScript("OnEvent", function()
                        for i = 1, #_eliteFrames do _eliteRefresh(_eliteFrames[i]) end
                    end)
                end
                eliteEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
                eliteEvents:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", "target")
                eliteEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
            elseif eliteEvents then
                eliteEvents:UnregisterAllEvents()
            end
        end

        local function _setupEliteIndicator(uf, settings)
            if not (uf and uf.Health and settings) then return end
            if not uf._eliteIndicator then
                -- Same parent and layer choice as the leader crown above.
                local par = uf._textOverlay or uf
                local tex = par:CreateTexture(nil, "OVERLAY", nil, 7)
                tex:Hide()
                uf._eliteIndicator = tex
                _eliteFrames[#_eliteFrames + 1] = uf
            end
            uf._eliteSettings = settings

            local function ApplyEliteIndicator()
                local sz  = settings.eliteIndicatorSize or 16
                local pos = settings.eliteIndicatorPosition or "topleft"
                local ox  = settings.eliteIndicatorX or 0
                local oy  = settings.eliteIndicatorY or 0
                local tex = uf._eliteIndicator
                tex:SetSize(sz, sz)
                tex:ClearAllPoints()
                if pos == "portrait" and uf.Portrait and uf.Portrait.backdrop then
                    tex:SetPoint("CENTER", uf.Portrait.backdrop, "CENTER", ox, oy)
                else
                    local anchor =
                        (pos == "topright"    and "TOPRIGHT")    or
                        (pos == "bottomleft"  and "BOTTOMLEFT")  or
                        (pos == "bottomright" and "BOTTOMRIGHT") or
                        "TOPLEFT"
                    tex:SetPoint(anchor, uf.Health or uf, anchor, ox, oy)
                end
                _eliteArmEvents()
                _eliteRefresh(uf)
            end
            uf._applyEliteIndicator = ApplyEliteIndicator
            ApplyEliteIndicator()
        end

        _setupEliteIndicator(frames.target, db.profile.target)
    end

    local petFrameSource = ns.GetUnitFrameSource("pet")
    if petFrameSource == "eui" then
        frames.pet = ns.Engine.SpawnUnitFrame("pet", "EllesmereUIUnitFrames_Pet")
        StylePetFrame(frames.pet, "pet")
        ns.UF_AttachEngineFrame(frames.pet, "pet")
        ApplyFramePosition(frames.pet, "pet")
        SetupUnitMenu(frames.pet, "pet")
    elseif petFrameSource == "hidden" then
        ns.Engine.HideBlizzardUnitFrame("pet")
    end

    local totFrameSource = ns.GetUnitFrameSource("targettarget")
    if totFrameSource == "eui" then
        frames.targettarget = ns.Engine.SpawnUnitFrame("targettarget", "EllesmereUIUnitFrames_TargetTarget")
        StyleSimpleFrame(frames.targettarget, "targettarget")
        ns.UF_AttachEngineFrame(frames.targettarget, "targettarget", true)
        ApplyFramePosition(frames.targettarget, "targettarget")
        SetupUnitMenu(frames.targettarget, "targettarget")
    end
    -- Blizzard's target-of-target is a child of TargetFrame. When the target frame
    -- itself is EUI or hidden, TargetFrame is already disabled so the child is gone
    -- with it. Only needs suppressing when the target uses Blizzard's live frame but
    -- the user does NOT want Blizzard's ToT (EUI or hidden) -- else both would show.
    if totFrameSource ~= "blizzard" and targetFrameSource == "blizzard" then
        SuppressBlizzardChildFrame(TargetFrame and TargetFrame.totFrame)
    end

    local ftFrameSource = ns.GetUnitFrameSource("focustarget")
    if ftFrameSource == "eui" then
        frames.focustarget = ns.Engine.SpawnUnitFrame("focustarget", "EllesmereUIUnitFrames_FocusTarget")
        StyleSimpleFrame(frames.focustarget, "focustarget")
        ns.UF_AttachEngineFrame(frames.focustarget, "focustarget", true)
        ApplyFramePosition(frames.focustarget, "focustarget")
        SetupUnitMenu(frames.focustarget, "focustarget")
    end
    -- Same as target-of-target: FocusFrame's native focus-target is a child of
    -- FocusFrame, so it only needs suppressing when focus uses Blizzard's live frame
    -- and the user does not want the native focus-target.
    if ftFrameSource ~= "blizzard" and focusFrameSource == "blizzard" then
        SuppressBlizzardChildFrame(FocusFrame and FocusFrame.totFrame)
    end

    local bossFrameSource = ns.GetUnitFrameSource("boss")
    if bossFrameSource == "eui" then
    local bossPos = db.profile.positions.boss

    local bossSettings = db.profile.boss or {}
    local barHeight = (bossSettings.healthHeight or 34) + (bossSettings.powerHeight or 6) + (bossSettings.castbarHeight or 14)
    local gap = 10
    local spacing = db.profile.bossSpacing or (barHeight + gap)
    local bossStackDir = db.profile.boss and db.profile.boss.bossStackDirection or "down"
    for i = 1, 5 do
        local bossUnit = "boss" .. i
        local bossFrame = ns.Engine.SpawnUnitFrame(bossUnit, "EllesmereUIUnitFrames_Boss" .. i)
        StyleBossFrame(bossFrame, bossUnit)
        ns.UF_AttachEngineFrame(bossFrame, bossUnit)
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
        -- Suppressing boss1 takes the whole BossTargetFrameContainer with it
        -- (and all five Boss*TargetFrame children).
        ns.Engine.HideBlizzardUnitFrame("boss1")
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
            -- Any unit with its own settings table can override the global
            -- strata; nil (the default) means "follow the global value". See
            -- the matching comment in the other frameStrata-apply pass for why
            -- this resolves through GetSettingsForUnit.
            local strata = ufStrata
            local us = GetSettingsForUnit(unitKey)
            if us and us.frameStrata then strata = us.frameStrata end
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
            -- The cast bar is a child of the frame, so SetFrameStrata above reset it to
            -- the frame's strata. Lift to HIGH so it never hides behind other MEDIUM-
            -- strata frames, unless "Raise Cast Bar Strata (All)" is off, in which case
            -- it's explicitly left at the frame's strata.
            if frame.Castbar and (unitKey == "player" or IsKickCastbarUnit(unitKey)) then
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

    -- Player castbar: disable oUF element if not wanted (always created now)
    if frames.player and frames.player.Castbar then
        if not db.profile.player.showPlayerCastbar then
            ns.SetCastbarElement(frames.player, false)
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
    -- Companion mini frame for each main frame: the mini inherits its parent's FULL
    -- effective visibility (modes, multi-selections, hide options, fade, mouseover
    -- reveals, Never/disabled).
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
                    and EllesmereUI.EvalVisibilityExtended(s, "barVisibility", visState, EllesmereUI.VIS_CAPS_DEFAULT)

                -- Secure condition driver: an engine-owned selection compiles into a
                -- state-visibility driver (the action bar mechanism), replacing the
                -- frame's unit watch. A driver-hidden frame is TRULY hidden -- absorbs
                -- no clicks -- and the secure engine flips it mid-combat natively.
                -- Mouseover sets keep the frame shown while conditions pass (compiler
                -- ignores the mouseover key); the alpha bucket + hover handlers do the
                -- revealing. Registration is out-of-combat only; a selection changed
                -- during combat rides on alpha until the regen pass registers the driver.
                local drvSet = EllesmereUI.GetActiveVisibilityModes
                    and EllesmereUI.GetActiveVisibilityModes(s, "barVisibility")
                -- Condition scalars ride the driver too: dragonriding (engine owns it
                -- everywhere) and the combat pair, whose legacy alpha-hide left an
                -- invisible click-absorbing frame out of combat. Visibility is
                -- unchanged; the driver just hides for real and flips exactly at the combat edge.
                if not drvSet and (vis == "show_dragonriding" or vis == "show_not_dragonriding"
                    or vis == "in_combat" or vis == "out_of_combat") then
                    drvSet = { [vis] = true }
                end
                -- Tail built once and reused by the mini frame below (both compilers only
                -- PREPEND their prefix).
                local visTail
                if s.visibilityMatch == "any" and EllesmereUI.BuildAnyMatchTail then
                    local tail, _, liveAxes = EllesmereUI.BuildAnyMatchTail(s, "barVisibility", drvSet)
                    -- Gated on liveAxes: with no soft-target edge here, target/enemy axes
                    -- resolve in Lua, and a driver compiled from those alone would be a
                    -- frozen constant. Zero live axes keeps the frame on the live ext/alpha path.
                    if liveAxes > 0 then visTail = tail end
                elseif drvSet and EllesmereUI.BuildVisibilityDriverString then
                    visTail = EllesmereUI.BuildVisibilityDriverString("", drvSet)
                end
                local wantDriver
                if visTail then
                    wantDriver = "[@" .. unitKey .. ",noexists] hide; " .. visTail
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

                -- Whole-frame out-of-combat fade: the alpha to use whenever the frame is
                -- "shown" below. 1 unless "Fade Out of Combat" is on and we're out of
                -- combat, in which case the chosen oocAlpha. Uses the event-tracked
                -- _ufInCombat (authoritative on regen transitions, which lead
                -- InCombatLockdown()) so the fade flips instantly.
                local shownAlpha = ns.ResolveFrameAlpha(s, _ufInCombat)

                -- Combat-sensitive and mouseover modes use SetAlpha to show/hide
                -- (not a restricted API); the frame stays technically shown so it can
                -- transition instantly, alpha controls visibility. For the player frame
                -- we drive alpha on a non-secure wrapper (_visWrap) so nothing touching
                -- the inner frame's alpha (oUF updates, secure templates) can fight us --
                -- alpha inherits down the parent chain so wrapper alpha 0 always wins.
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
                    -- Mouseover: hidden by default; hover toggles alpha. But when the user
                    -- has configured any positive "Hide if" override (no target, no enemy,
                    -- mounted, etc.) and it's NOT currently triggering, treat the frame as
                    -- a positive-show so it doesn't require hover to see (fixes "dismount
                    -- in combat keeps frame hidden" / "hide if no target inverted").
                    local hasAnyHideOpt = EllesmereUI and EllesmereUI.VisHasAnyOption
                                       and EllesmereUI.VisHasAnyOption(s)
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

                -- Alpha-only hide for the "visHide*" overrides (mounted, no target,
                -- housing, etc). Force alpha 0 now so the frame still looks hidden, but
                -- leave the secure Show/Hide state alone below -- otherwise a dismount
                -- landing inside a combat lockdown would leave the frame permanently
                -- hidden (Show/SetAttribute are restricted in combat).
                if hiddenByOpts then
                    bodyAlpha = 0
                end
                alphaTarget:SetAlpha(bodyAlpha)

                -- 3D PlayerModel frames don't inherit parent alpha, so the model must
                -- mirror the EXACT body alpha computed above -- every alpha-hidden state
                -- (engine-owned, in_combat, out_of_combat, mouseover, hide-opts) would
                -- otherwise leave a floating portrait over an invisible frame. Hover
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
                        shouldShow = inParty
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
                            -- Re-enable the engine elements that were disabled on hide.
                            -- Castbar is handled separately below to respect the
                            -- user's show/hide setting -- never blindly re-enable it.
                            for _, elem in ipairs({"Health", "Power", "Portrait", "HealthPrediction"}) do
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
                                    ns.SetCastbarElement(frame, true)
                                else
                                    ns.SetCastbarElement(frame, false)
                                    frame.Castbar:Hide()
                                    local castbarBg = frame.Castbar:GetParent()
                                    if castbarBg then castbarBg:Hide() end
                                end
                            end
                            frame:Show()
                            -- Full engine repaint: the SetAttribute above reuses
                            -- the same unit token, so the attribute hook sees no
                            -- change and never repaints on its own.
                            ns.Engine.RepaintAll(frame, "GroupVisibility")
                        end
                    else
                        if frame:IsShown() then
                            -- Disable the engine elements before hiding to prevent a
                            -- single-frame flash when the unit attribute is cleared
                            for _, elem in ipairs({"Health", "Power", "Portrait", "HealthPrediction"}) do
                                if frame[elem] and frame:IsElementEnabled(elem) then
                                    frame:DisableElement(elem)
                                end
                            end
                            ns.SetCastbarElement(frame, false)
                            frame:Hide()
                            frame:SetAttribute("unit", nil)
                        end
                    end
                end

                local mini = frames[ns.UF_MINI_OF[unitKey]]
                -- Always Show Pet Frame: the pet opts out of every parent
                -- visibility inheritance in this pass -- its own unit watch
                -- alone owns Show/Hide (visible whenever a pet exists).
                local miniAlways = (unitKey == "player") and db.profile.pet
                    and db.profile.pet.alwaysShow

                -- The companion mini frame gets its own condition driver
                -- (parent conditions + its own unit existence), so a
                -- condition-hidden mini absorbs no clicks either.
                if mini then
                    local miniWant
                    if (not miniAlways) and visTail then
                        miniWant = "[@" .. ns.UF_MINI_OF[unitKey] .. ",noexists] hide; " .. visTail
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

                -- Mini-frame visibility inheritance: pet follows player, target-of-target
                -- follows target, focus-target follows focus. The mini mirrors the
                -- parent's effective state -- body alpha computed above (modes, multi-
                -- selections, hide options, ooc fade, mouseover default) plus the secure
                -- Show/Hide bucket via IsShown() -- so every way the parent hides takes
                -- its mini along. RegisterUnitWatch keeps owning the mini's own Show/Hide
                -- (unit existence); alpha never conflicts with it. Hover reveals mirror
                -- in the OnEnter/OnLeave handlers.
                if mini then
                    mini:SetAlpha(miniAlways and 1 or (frame:IsShown() and bodyAlpha or 0))
                end
            elseif frame then
                -- Parent disabled ("Never" clears enabledFrames): a leftover condition
                -- driver must not keep re-showing the frame, so pin it to a constant
                -- hide. Frames that never had a driver keep the legacy disabled path
                -- untouched. The mini inherits both.
                if not isLocked and frame._euiVisDriver and frame._euiVisDriver ~= "hide" then
                    RegisterAttributeDriver(frame, "state-visibility", "hide")
                    frame._euiVisDriver = "hide"
                end
                local mini = frames[ns.UF_MINI_OF[unitKey]]
                if mini then
                    local miniAlways = (unitKey == "player") and db.profile.pet
                        and db.profile.pet.alwaysShow
                    if miniAlways then
                        -- Always Show Pet Frame survives a disabled player
                        -- frame: unpin any driver so the pet's own unit
                        -- watch shows it whenever a pet exists.
                        if not isLocked and mini._euiVisDriver then
                            UnregisterAttributeDriver(mini, "state-visibility")
                            RegisterUnitWatch(mini)
                            mini._euiVisDriver = nil
                        end
                        mini:SetAlpha(1)
                    else
                        if not isLocked and mini._euiVisDriver and mini._euiVisDriver ~= "hide" then
                            RegisterAttributeDriver(mini, "state-visibility", "hide")
                            mini._euiVisDriver = "hide"
                        end
                        mini:SetAlpha(0)
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
            if issecretvalue(ct) then ct = nil end
            if ct then
                local classStyle = (uSettings and uSettings.classThemeStyle) or "modern"
                ApplyClassIconTexture(backdrop._class, ct, classStyle)
            end
        end
    end)

    ---------------------------------------------------------------------------
    --  Portrait art readiness for the OnUpdate-polled frames (Target of Target
    --  / Focus Target). PORTRAITS_UPDATED is how the client says portrait art
    --  finished loading, and PortraitOverride acts on it -- but the event is
    --  never registered on these frames: once __eventless is set, the unit
    --  frame library's RegisterEvent drops everything except
    --  UNIT_PORTRAIT_UPDATE and UNIT_MODEL_CHANGED. PLAYER_ENTERING_WORLD
    --  still reaches them (UpdateAllElements pushes it to every element), so
    --  they take the mid-loading blank paint with nothing to heal it: the poll
    --  just re-runs the same guid-gated Override. ForceUpdate is the trigger
    --  that gate always honors. 2D only -- a PlayerModel does not read portrait
    --  art, and repainting one costs a ClearModel + SetUnit reload.
    ---------------------------------------------------------------------------
    if not frames._portraitArtUpdater then
        frames._portraitArtUpdater = CreateFrame("Frame")
        frames._portraitArtUpdater:RegisterEvent("PORTRAITS_UPDATED")
    end
    frames._portraitArtUpdater:SetScript("OnEvent", function()
        for _, frame in pairs(frames) do
            if type(frame) == "table" and frame.__eventless and frame.IsElementEnabled then
                local p = frame.Portrait
                if p and p.ForceUpdate and not p:IsObjectType("PlayerModel")
                    and frame:IsElementEnabled("Portrait") then
                    p:ForceUpdate()
                end
            end
        end
    end)

    -- Target-of-target/focus-target/pet text class colors must re-apply when their unit
    -- changes or first becomes available (login/reload). Unlike target/focus, mini
    -- frames have no PLAYER_*_CHANGED of their own, so a class color set at style
    -- time -- when "targettarget"/"focustarget"/"pet" was not yet a resolvable unit --
    -- falls back to white/reaction-nil and never recovers. Re-apply on the parent's
    -- target change and on its UNIT_TARGET, and on UNIT_PET for the pet frame.
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
        frames._miniTextClassUpdater:RegisterUnitEvent("UNIT_PET", "player")
    end
    frames._miniTextClassUpdater:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_TARGET_CHANGED" then
            ReapplyFrameTextClassColors("targettarget")
        elseif event == "PLAYER_FOCUS_CHANGED" then
            ReapplyFrameTextClassColors("focustarget")
        elseif event == "UNIT_PET" then
            ReapplyFrameTextClassColors("pet")
        elseif arg1 == "target" then
            ReapplyFrameTextClassColors("targettarget")
        elseif arg1 == "focus" then
            ReapplyFrameTextClassColors("focustarget")
        end
    end)

    -- Boss Hover/Target border: refresh each boss frame's target state when the
    -- player's target changes or boss units (dis)appear. Hover is handled by the
    -- OnEnter/OnLeave hooks; this only tracks target. Both borders default off, so
    -- this is a cheap no-op unless the user enabled one. On ns for the 200-local cap.
    ns.UpdateBossTargetBorders = function()
        local s = db.profile.boss
        for i = 1, 5 do
            local bUnit = "boss" .. i
            local f = frames[bUnit]
            if f then
                if f.unifiedBorder then
                    local isT = UnitIsUnit(bUnit, "target")
                    f._isTarget = (not issecretvalue(isT) and isT) and true or false
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
    -- for dynamic units (target, focus) since no unit is selected yet on login/reload,
    -- causing the WARRIOR fallback. Re-apply the correct class icon once the client
    -- has finished loading and unit data is available.
    C_Timer.After(0, function()
        for _, unitKey in ipairs({"player", "target", "focus"}) do
            local frame = frames[unitKey]
            if frame and frame.Portrait then
                local backdrop = frame.Portrait.backdrop
                if backdrop and backdrop._class then
                    local uSettings = db.profile[unitKey]
                    if uSettings and (uSettings.portraitMode or "2d") == "class" then
                        local _, ct = UnitClass(unitKey)
                        if issecretvalue(ct) then ct = nil end
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

    -- Live Enable Boss Frames for the EUI source. The boss frames spawn at login
    -- only, so the enable toggle used to be a silent no-op in the ON->OFF
    -- direction: PromptReloadIfUnspawned only prompts when frames are MISSING,
    -- and nothing hid the live frames -- they kept showing on every boss for the
    -- rest of the session (field report 2026-08-13; Blizzard source toggled live,
    -- hence "only works on Blizzard default"). The unit watch is the show/hide
    -- authority (RegisterUnitWatch at spawn), so toggling it IS the live enable/
    -- disable; frames never spawned this session still fall through to the
    -- reload prompt in the options setter. Watch/Hide writes on these secure
    -- frames are lockdown-blocked: in combat, park a one-shot that re-applies
    -- the CURRENT setting at regen (reads the profile at fire time, so the last
    -- click wins and stacked toggles collapse to one apply).
    function ns.UF_SetBossFramesActive(on)
        if InCombatLockdown() then
            local w = ns._bossToggleRegen
            if not w then
                w = CreateFrame("Frame")
                w:SetScript("OnEvent", function(self)
                    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    ns.UF_SetBossFramesActive(db.profile.enabledFrames.boss ~= false)
                end)
                ns._bossToggleRegen = w
            end
            w:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        for i = 1, 5 do
            local f = frames["boss" .. i]
            if f then
                if on then
                    RegisterUnitWatch(f)
                else
                    UnregisterUnitWatch(f)
                    f:Hide()
                end
            end
        end
    end
    ns.ApplyFramePosition = ApplyFramePosition
    ns.GetFrameDimensions = GetFrameDimensions
    local reloadPending = false
    local reloadThrottle = CreateFrame("Frame")
    reloadThrottle:Hide()
    -- Realise a classPowerStyle that changed through a path which never calls
    -- _toggleClassPower (a Spec Override applying at login, a profile switch, an
    -- import). Gated on an actual change because the toggle is a full teardown
    -- and rebuild; running it every reload would thrash the bar.
    local cpRegen = CreateFrame("Frame")
    local function RealiseClassPowerStyle()
        if not frames._toggleClassPower then return end
        local wantCP = db.profile.player.classPowerStyle or "none"
        if wantCP == frames._classPowerBuiltStyle then return end
        -- The toggle reparents Blizzard's class power frame and re-anchors the
        -- health bar. The throttle body keeps running after ReloadFrames()'s
        -- lockdown return (same shape as the UpdateFrameVisibility note above),
        -- so this needs its own guard plus a regen re-run to re-arm the pass.
        if InCombatLockdown() then
            cpRegen:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        frames._toggleClassPower(wantCP)
    end
    cpRegen:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        RealiseClassPowerStyle()
    end)
    reloadThrottle:SetScript("OnUpdate", function(self)
        self:Hide()
        reloadPending = false
        ReloadFrames()
        ApplyBlizzCastbarState()
        -- A reload restyles the boss frames and re-colors their health to the
        -- player's class color (preview rides on unit="player") + re-tags the name.
        -- Re-assert the preview (red color + fake name) so a settings change doesn't
        -- revert it. Secret-safe: no health values are read.
        if ns._bossPreviewActive and ns.SetBossPreview then ns.SetBossPreview(true) end
        -- ReloadFrames rebuilds frames but never touches the top-level wrapper/3D-
        -- portrait alpha, so recompute the out-of-combat fade here. Without this, a
        -- profile/spec swap (or first switch to a 3D portrait, whose PlayerModel is
        -- created at alpha 1) leaves player/target/focus stuck at the old opacity
        -- until the next combat/target/zone event. Safe from the throttle:
        -- UpdateFrameVisibility guards its restricted Show/Hide behind
        -- InCombatLockdown, and SetAlpha is unrestricted.
        if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
        -- 12.1 aura containers reload with every real pass (direct call --
        -- ns.ReloadFrames is just the throttle-arming stub, so wrapping it
        -- from the container file is timing-unreliable).
        if ns.UF_ReloadAllAuraContainers then ns.UF_ReloadAllAuraContainers() end
        -- Class power: _toggleClassPower is the only thing that honours a
        -- classPowerStyle change, and options + the spec watcher are its only
        -- other callers -- styles changed by overrides, profile switch, or
        -- import land here.
        RealiseClassPowerStyle()
    end)
    ns.ReloadFrames = function()
        if not reloadPending then
            reloadPending = true
            reloadThrottle:Show()
        end
    end
    _G._EUF_ReloadFrames = ns.ReloadFrames

    -- Fake debuff icons for the boss preview. Three square icons anchored where the
    -- real Debuffs frame would live, sized to match the Simple Debuff Display layout
    -- (frame bar height, growing right-to-left off the frame's left edge). Created on
    -- demand and torn down on preview disable.
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
            -- Static fake cooldown swipe: a huge duration parked at a fixed fraction so
            -- the wedge never visibly moves. Native countdown numbers stay hidden; the
            -- duration text below is a manual static FontString instead.
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
            if castbar.castTintLayer then
                castbar.castTintLayer:SetAlpha(0)
                castbar._castTintOn = nil
            end
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
            castbar.castTintLayer:SetAlpha(castbar._fillOp or 1)
            castbar._castTintOn = true
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

    -- Refresh the in-game boss preview's fake auras when boss settings that affect them
    -- (simpleDebuffs, debuffAnchor, debuffSize, buffAnchor, etc.) change.
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

    -- Override the name fontstring with a fake boss name. Its text zone is
    -- parked so the engine's text painter stops overwriting it; SetText with a
    -- literal string is secret-safe. Restored on clear.
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
        local zones = f._euiTextZones
        if zones and not fs._previewSavedZone then
            for i = #zones, 1, -1 do
                if zones[i].fs == fs then
                    fs._previewSavedZone = table.remove(zones, i)
                    break
                end
            end
        end
        fs:SetText(name)
    end
    local function ClearBossPreviewName(f)
        local fs = f._previewNameFS
        if not fs then return end
        if fs._previewSavedZone then
            local zones = f._euiTextZones
            if not zones then zones = {}; f._euiTextZones = zones end
            zones[#zones + 1] = fs._previewSavedZone
            fs._previewSavedZone = nil
        end
        f._previewNameFS = nil
        if ns.UF_PaintText then ns.UF_PaintText(f, f._euiUnit) end
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
        -- unit is the player with no boss classification -- substitute the red
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
--  Register unit frame elements with Unlock Mode. Called synchronously from
--  OnEnable (right after InitializeFrames) so registration lands inside the
--  PLAYER_LOGIN pre-lockdown window on a combat reload -- timers never fire
--  during the loading screen, so a deferred registration would land after
--  combat lockdown re-engaged, leaving anchored unit frames unpositionable
--  until combat dropped.
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
                    -- Unlock-anchored elements: the anchor system is the position
                    -- authority. Only bootstrap from the saved standalone position
                    -- while the frame has no bounds yet (first placement); otherwise
                    -- leave it alone so the anchor position is never clobbered.
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
            -- Boss is a stack of 5 chained frames; resize / match actions don't make
            -- sense on the aggregate element. Boss can still anchor to other elements;
            -- it just can't be used as an anchor target.
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

        -- Seed default anchor + width-match for castbars so they start anchored to
        -- their parent frame with matched width out of the box. Only seed if the user
        -- has NEVER configured this castbar in unlock mode (tracked by
        -- _castbarUnlockSeeded); once they have, stop overwriting their choices.
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

-- Enable-body router. OnEnable runs under the parent addon's lifecycle dispatch, and
-- the engine bills a script handler's whole call tree to the addon whose execution
-- context created the entry frame -- so every frame born inside the build (oUF
-- buttons, event drivers, castbar watchers) would bill the PARENT's CPU row forever.
-- Routing the body through this file-scope frame's PLAYER_LOGIN handler runs the
-- build in this child's context instead. Ordering is safe: the parent's lifecycle
-- frame registered PLAYER_LOGIN first (parent loads before children), so OnEnable has
-- always set the pending flag by the time this frame's handler fires -- within the
-- SAME event dispatch, still inside the combat-reload pre-lockdown window.
local function EnableBody()
    -- Consumed by PlayerAuraBars' login retry: absent = the module never enabled
    -- this session, so ns.db will never arrive and PAB must stand down silently.
    ns._eufEnabled = true
    InitializeFrames()
    -- Register with unlock mode synchronously: on a combat reload this runs
    -- inside the pre-lockdown window, so the login position pass can resolve
    -- and place anchored unit frames before SetPoint gets blocked.
    RegisterUFUnlockElements()
    -- The parent's synchronous PLAYER_LOGIN position pass (EUI_UnlockMode) fires BEFORE
    -- this router drains, so unit frame elements were not yet registered when it ran.
    -- Re-fire it now -- still inside the same PLAYER_LOGIN dispatch, so anchored unit
    -- frames are placed within the combat-reload pre-lockdown window. The pass is
    -- re-entrant by design (CDM and the PEW fallback both re-fire it).
    if EllesmereUI and EllesmereUI._applySavedPositions then
        EllesmereUI._applySavedPositions()
    end
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
    end)
end

do
    local loginFired = false
    local router = CreateFrame("Frame")
    router:RegisterEvent("PLAYER_LOGIN")
    -- Backstop only: PLAYER_LOGIN always fires for a startup-loaded addon,
    -- but if it were ever missed the next world entry drains the flag.
    router:RegisterEvent("PLAYER_ENTERING_WORLD")
    router:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        loginFired = true
        if ns._eufEnablePending then
            ns._eufEnablePending = nil
            EnableBody()
        end
    end)

    function EllesmereUF:OnEnable()
        if loginFired then
            -- Runtime re-enable long after login: run directly (rare; any
            -- parent-context billing lasts only until the next reload).
            EnableBody()
        else
            ns._eufEnablePending = true
        end
        -- Incompatible addon detection is handled globally by EllesmereUI
    end
end

-- Called by EUI_UnlockMode.lua's Grow Direction dropdown for barKey ==
-- "PAB_Buffs" / "PAB_Debuffs". Thin delegation to
-- EllesmereUIUnitFrames_PlayerAuraBars.lua's ns.PAB_Get/SetGrowDirection so
-- the settings field names stay defined in exactly one file.

function EllesmereUF:GetGrowDirectionForBar(barKey)
    return ns.PAB_GetGrowDirection and ns.PAB_GetGrowDirection(barKey)
end

function EllesmereUF:SetGrowDirectionForBar(barKey, dir)
    if ns.PAB_SetGrowDirection then
        ns.PAB_SetGrowDirection(barKey, dir)
    end
end

-------------------------------------------------------------------------------
--  Boss Frame Range Dimming. Boss units sit outside UnitInRange's group-member
--  domain, so range is measured against a known spell instead: a harm spell for
--  attackable bosses (all specs, first known spell in the class chain wins), or
--  the class baseline heal for friendly bosses (healer specs only). Whole-frame
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
--  Player Dispel Overlay (player frame only, health bar only). The 12.1
--  container dispel slots render it (EUI_UnitFrames_AuraContainers.lua); this
--  block keeps what the slots ask this file for: the racial / talent dispel
--  knowledge the RAID_PLAYER_DISPELLABLE token is blind to, and the
--  options-side poke that re-drives the slots after a color or toggle edit.
--  (do-block: zero persistent main-chunk locals.)
-------------------------------------------------------------------------------
do

    -- RAID_PLAYER_DISPELLABLE only knows class and spec dispels, so it answers no for
    -- every bleed: nothing a class learns removes one, only the dwarf racial does.
    -- Without this, "Only Dispellable by You" can never light up for a bleed, for
    -- anyone. A racial cleans its own caster, so this is the player frame's business
    -- alone. Bleed only, deliberately: Stoneform also clears poison/disease/curse, but
    -- a class that dispels those already passes the token, and treating a two-minute
    -- racial as a dispel would overlay most of what a dwarf ever catches.
    local RACIAL_DISPEL_TYPES = {
        bleed = { Dwarf = true },  -- Stoneform
    }
    -- The token is equally blind to talent dispels: a shaman's poison removal is
    -- Poison Cleansing Totem, so Poison never passes for them. Raid Frames applies
    -- the same rule to its group-wide dispel slots (EUI_RaidFrames_AuraContainers.lua).
    -- Cached: IsPlayerSpell can lag both addon load and the trait event that
    -- announces a change; the shaman watcher in EUI_UnitFrames_AuraContainers.lua
    -- calls UF_RefreshPoisonTotem on trait and spellbook events and reloads the
    -- dispel slots when it reports a flip.
    local POISON_CLEANSING_TOTEM = 383013
    local _, ufPlayerClass = UnitClass("player")
    local poisonTotemKnown = ufPlayerClass == "SHAMAN"
        and IsPlayerSpell(POISON_CLEANSING_TOTEM) or false
    function ns.UF_RefreshPoisonTotem()
        local known = ufPlayerClass == "SHAMAN"
            and IsPlayerSpell(POISON_CLEANSING_TOTEM) or false
        if known == poisonTotemKnown then return false end
        poisonTotemKnown = known
        return true
    end
    -- Shared with the 12.1 container slots (EUI_UnitFrames_AuraContainers.lua),
    -- which apply the same rule by choosing which slot style stays visible.
    function ns.UF_TokenBlindDispel(typeKey)
        local races = RACIAL_DISPEL_TYPES[typeKey]
        if races then
            local _, raceToken = UnitRace("player")
            return raceToken ~= nil and races[raceToken] == true
        end
        if typeKey == "poison" then
            return poisonTotemKnown
        end
        return false
    end

    ns.UpdatePlayerDispelOverlay = function()
        -- The container dispel slots own the overlay; poke their fingerprinted
        -- reload so dropdown/cog edits apply live instead of waiting for the
        -- next full container pass.
        if ns.UF_ReloadPlayerDispelSlots then
            ns.UF_ReloadPlayerDispelSlots()
        end
    end
end
