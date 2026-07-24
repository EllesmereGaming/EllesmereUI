-------------------------------------------------------------------------------
--  EllesmereUI_PartyMode.lua
--  Full-screen disco spotlight overlay — toggled from Global Settings.
--  Cone-shaped beams shine down from the top of the screen like stage
--  spotlights. Each beam uses 3 overlapping layers (wide dim outer,
--  medium mid, narrow bright core) to create the cone/spotlight look.
--
--  Uses texture:SetRotation() for angled beams.
--  Gradient is flipped via SetTexCoord so bright end is at top.
--  Beams are extra tall so edges never show at screen bottom.
--
--  Performance:
--    • Zero CPU when disabled — container hidden, OnUpdate doesn't fire.
--    • OnUpdate throttled to ~30fps.
--    • Screen dimensions cached; refreshed on resize.
--
--  Shared across all EllesmereUI addons — only the first to load runs.
-------------------------------------------------------------------------------
if _G._EllesmereUIPartyModeLoaded then return end
_G._EllesmereUIPartyModeLoaded = true

local ADDON_NAME = ...
local GRADIENT_TEX = "Interface\\AddOns\\EllesmereUI\\media\\party.png"

local BASE_OVERLAY_ALPHA = 0.30
local function OVERLAY_ALPHA()
    local db = EllesmereUIDB
    local bri = db and db.partyModeBrightness
    if bri == nil then bri = 0.65 end
    return BASE_OVERLAY_ALPHA * (bri / 0.65)
end
local HUE_CYCLE_SPEED  = 0.06
local GLOBAL_HUE_SHIFT = 0.03
local SATURATION       = 0.85
local BRIGHTNESS       = 0.85
local THROTTLE         = 0.033

local math_floor  = math.floor
local math_sin    = math.sin
local math_random = math.random
local math_pi     = math.pi
local math_rad    = math.rad

-------------------------------------------------------------------------------
--  Keybind registration (pure Lua — no Bindings.xml needed)
--  Uses a hidden button + SetOverrideBindingClick. Only the first addon
--  to load creates the button; subsequent addons skip if it already exists.
--  The bound key is saved in EllesmereUIDB.partyModeKey (nil = unbound).
-------------------------------------------------------------------------------
if not _G["EllesmereUIPartyModeBindBtn"] then
    local btn = CreateFrame("Button", "EllesmereUIPartyModeBindBtn", UIParent)
    btn:Hide()
    btn:SetScript("OnClick", function()
        EllesmereUI_TogglePartyMode()
    end)
end

-------------------------------------------------------------------------------
--  Celebration / dim-lights state
-------------------------------------------------------------------------------
local celebrationTimer = nil
local randomTimer = nil
local randomScheduledTimer = nil
local randomCooldownTimer = nil
local dimLightsActive = false
local savedContrast = nil
local savedBrightness = nil

-------------------------------------------------------------------------------
--  Dim lights helpers (for live toggle from options)
-------------------------------------------------------------------------------
function EllesmereUI_IsDimLightsActive()
    return dimLightsActive
end

function EllesmereUI_ApplyDimLights()
    if dimLightsActive then return end
    savedContrast = tonumber(GetCVar("contrast")) or 50
    savedBrightness = tonumber(GetCVar("brightness")) or 50
    SetCVar("contrast", math.max(0, math.min(100, savedContrast + 14)))
    SetCVar("brightness", math.max(0, savedBrightness - (savedBrightness - 10) * 0.7))
    dimLightsActive = true
end

function EllesmereUI_RestoreDimLights()
    if not dimLightsActive then return end
    SetCVar("contrast", savedContrast)
    SetCVar("brightness", savedBrightness)
    dimLightsActive = false
end

-------------------------------------------------------------------------------
--  Beam definitions — 12 beams
--  Each beam gets 3 layers: wide outer glow, medium mid, narrow core
--  This creates the cone/spotlight spread effect
--
--  originX: horizontal origin (fraction of screen, 0=center)
--  baseAngle: resting angle degrees (neg=lean left, pos=lean right)
--  sweepDeg: oscillation range in degrees
--  sweepSpeed: oscillation speed (rad/s)
--  width: base width as fraction of screen (core layer uses this,
--         mid layer 2.5x, outer layer 5x)
--  brightness, hue, phaseOff: visual tuning
-------------------------------------------------------------------------------
local BEAM_DEFS = {
    -- Far left edge — steep inward angle
    { originX=-0.65, baseAngle=-60, sweepDeg=20, sweepSpeed=1.6, width=0.10, brightness=0.90, hue=0.00, phaseOff=0.0 },
    -- Left — moderate inward
    { originX=-0.40, baseAngle=-35, sweepDeg=22, sweepSpeed=2.0, width=0.10, brightness=0.85, hue=0.12, phaseOff=1.8 },
    -- Left-center
    { originX=-0.20, baseAngle=-18, sweepDeg=18, sweepSpeed=1.8, width=0.10, brightness=0.90, hue=0.25, phaseOff=3.5 },
    -- Center-left
    { originX=-0.05, baseAngle=-5,  sweepDeg=15, sweepSpeed=2.2, width=0.10, brightness=1.00, hue=0.38, phaseOff=5.2 },
    -- Center
    { originX= 0.05, baseAngle= 5,  sweepDeg=15, sweepSpeed=1.7, width=0.10, brightness=0.95, hue=0.50, phaseOff=0.7 },
    -- Center-right
    { originX= 0.15, baseAngle= 12, sweepDeg=18, sweepSpeed=2.1, width=0.10, brightness=0.90, hue=0.62, phaseOff=2.4 },
    -- Right-center
    { originX= 0.25, baseAngle= 20, sweepDeg=20, sweepSpeed=1.9, width=0.10, brightness=0.85, hue=0.72, phaseOff=4.1 },
    -- Right
    { originX= 0.40, baseAngle= 35, sweepDeg=22, sweepSpeed=2.3, width=0.10, brightness=0.85, hue=0.82, phaseOff=5.8 },
    -- Far right edge — steep inward angle
    { originX= 0.65, baseAngle= 60, sweepDeg=20, sweepSpeed=1.6, width=0.10, brightness=0.90, hue=0.92, phaseOff=1.3 },
    -- Extra center fill
    { originX=-0.10, baseAngle=-10, sweepDeg=16, sweepSpeed=2.4, width=0.10, brightness=0.80, hue=0.45, phaseOff=3.0 },
    -- Far top-left gap filler — steep inward
    { originX=-0.50, baseAngle=-48, sweepDeg=18, sweepSpeed=1.8, width=0.10, brightness=0.88, hue=0.06, phaseOff=4.6 },
    -- Far top-right gap filler — steep inward
    { originX= 0.50, baseAngle= 48, sweepDeg=18, sweepSpeed=1.8, width=0.10, brightness=0.88, hue=0.88, phaseOff=2.0 },
}
local NUM_BEAMS = #BEAM_DEFS

local function HSVtoRGB(h, s, v)
    h = h % 1
    local i = math_floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    local rem = i % 6
    if     rem == 0 then return v, t, p
    elseif rem == 1 then return q, v, p
    elseif rem == 2 then return p, v, t
    elseif rem == 3 then return p, q, v
    elseif rem == 4 then return t, p, v
    else                 return v, p, q end
end

-------------------------------------------------------------------------------
--  State
-------------------------------------------------------------------------------
local container, beams, globalHueOffset, accumulator, globalTime
local cachedSW, cachedSH

-- Layer multipliers: [width_mult, alpha_mult]
-- outer = wide dim glow, mid = medium, core = narrow bright
local LAYER_DEFS = {
    { wMul = 5.0, aMul = 0.25 },  -- outer glow
    { wMul = 2.5, aMul = 0.50 },  -- mid
    { wMul = 1.0, aMul = 0.35 },  -- core (subtle, no harsh center beam)
}
local NUM_LAYERS = #LAYER_DEFS

local function CreateOverlay()
    if container then return end
    container = CreateFrame("Frame", "EllesmereUIPartyModeFrame", UIParent)
    container:SetFrameStrata("TOOLTIP")
    container:SetFrameLevel(9999)
    container:SetAllPoints(UIParent)
    container:EnableMouse(false)
    container:Hide()

    beams = {}
    globalHueOffset = 0
    globalTime = 0
    accumulator = 0

    cachedSW = GetScreenWidth()
    cachedSH = GetScreenHeight()

    for i = 1, NUM_BEAMS do
        local def = BEAM_DEFS[i]

        local beam = {
            def = def,
            layers = {},
            bri = BRIGHTNESS * (def.brightness or 0.8),
            hueOffset = 0,
            sweepPhase = def.phaseOff or (math_random() * math_pi * 2),
        }

        local baseW = cachedSW * def.width
        -- Extra tall: screen height * 5 so bottom edges are never visible
        local baseH = cachedSH * 5

        for layer = 1, NUM_LAYERS do
            local ld = LAYER_DEFS[layer]
            local tex = container:CreateTexture(nil, "ARTWORK", nil, layer)
            tex:SetTexture(GRADIENT_TEX)
            tex:SetTexCoord(0, 1, 1, 0)  -- flip vertically: bright at top
            tex:SetBlendMode("ADD")
            tex._beamW = baseW * ld.wMul
            tex._beamH = baseH
            tex._aMul = ld.aMul
            beam.layers[layer] = tex
        end

        beams[i] = beam
    end

    container:RegisterEvent("DISPLAY_SIZE_CHANGED")
    container:SetScript("OnEvent", function()
        cachedSW = GetScreenWidth()
        cachedSH = GetScreenHeight()
    end)

    container:SetScript("OnUpdate", function(self, elapsed)
        if elapsed > 0.1 then elapsed = 0.1 end
        accumulator = accumulator + elapsed
        if accumulator < THROTTLE then return end
        local dt = accumulator
        accumulator = 0

        globalTime = globalTime + dt
        globalHueOffset = globalHueOffset + GLOBAL_HUE_SHIFT * dt

        for i = 1, NUM_BEAMS do
            local beam = beams[i]
            local def = beam.def

            -- Sweep angle
            beam.sweepPhase = beam.sweepPhase + def.sweepSpeed * dt
            local currentAngle = def.baseAngle + math_sin(beam.sweepPhase) * (def.sweepDeg or 20)
            local rotRad = math_rad(-currentAngle)

            -- Anchor: pushed 500px above screen top so origin is hidden
            local anchorX = def.originX * cachedSW

            -- Hue rotation
            beam.hueOffset = beam.hueOffset + HUE_CYCLE_SPEED * dt
            local r, g, b = HSVtoRGB((def.hue + beam.hueOffset + globalHueOffset) % 1, SATURATION, beam.bri)

            for layer = 1, NUM_LAYERS do
                local tex = beam.layers[layer]
                tex:ClearAllPoints()
                tex:SetSize(tex._beamW, tex._beamH)
                -- Anchor at CENTER so SetRotation pivots around the beam origin.
                -- Position center above screen top: half screen height + 300px above top edge.
                tex:SetPoint("CENTER", container, "TOP", anchorX, 600)
                tex:SetRotation(rotRad)
                tex:SetVertexColor(r, g, b, OVERLAY_ALPHA() * tex._aMul)
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Global API
-------------------------------------------------------------------------------
function EllesmereUI_StartPartyMode()
    CreateOverlay()
    container:Show()
    -- Dim the lights if enabled (defaults to on)
    if EllesmereUIDB and (EllesmereUIDB.partyModeDimLights ~= false) then
        EllesmereUI_ApplyDimLights()
    end
end

function EllesmereUI_StopPartyMode()
    if container then container:Hide() end
    EllesmereUI_RestoreDimLights()
end

-------------------------------------------------------------------------------
--  Keybind toggle function
-------------------------------------------------------------------------------
function EllesmereUI_TogglePartyMode()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if EllesmereUIDB.partyMode then
        EllesmereUIDB.partyMode = false
        EllesmereUI_StopPartyMode()
    else
        EllesmereUIDB.partyMode = true
        EllesmereUI_StartPartyMode()
    end
end

-------------------------------------------------------------------------------
--  Random trigger helpers
--  New behavior: pick a random time within a 15-minute window, fire once,
--  then 10-minute cooldown, then new 15-minute window.
-------------------------------------------------------------------------------
local RANDOM_WINDOW = 900   -- 15 minutes in seconds

local function GetRandomCooldown()
    return ((EllesmereUIDB and EllesmereUIDB.partyModeRandomCooldown) or 10) * 60
end

local function ScheduleRandomActivation()
    if randomScheduledTimer then return end
    local delay = math_random(0, RANDOM_WINDOW)
    randomScheduledTimer = C_Timer.NewTimer(delay, function()
        randomScheduledTimer = nil
        if not (EllesmereUIDB and EllesmereUIDB.partyModeTriggerRandom) then return end
        if EllesmereUIDB.partyMode then
            -- Already active, try again after cooldown
            randomCooldownTimer = C_Timer.NewTimer(GetRandomCooldown(), function()
                randomCooldownTimer = nil
                ScheduleRandomActivation()
            end)
            return
        end
        EllesmereUIDB.partyMode = true
        EllesmereUI_StartPartyMode()
        if celebrationTimer then celebrationTimer:Cancel() end
        local duration = (EllesmereUIDB and EllesmereUIDB.partyModeMPlusDuration) or 30
        celebrationTimer = C_Timer.NewTimer(duration, function()
            celebrationTimer = nil
            if EllesmereUIDB then EllesmereUIDB.partyMode = false end
            EllesmereUI_StopPartyMode()
            -- Start cooldown, then schedule next random window
            randomCooldownTimer = C_Timer.NewTimer(GetRandomCooldown(), function()
                randomCooldownTimer = nil
                ScheduleRandomActivation()
            end)
        end)
    end)
end

function EllesmereUI_StartRandomTrigger()
    if randomTimer or randomScheduledTimer or randomCooldownTimer then return end
    ScheduleRandomActivation()
end

function EllesmereUI_StopRandomTrigger()
    if randomTimer then randomTimer:Cancel(); randomTimer = nil end
    if randomScheduledTimer then randomScheduledTimer:Cancel(); randomScheduledTimer = nil end
    if randomCooldownTimer then randomCooldownTimer:Cancel(); randomCooldownTimer = nil end
end

-------------------------------------------------------------------------------
--  Pause random trigger while EUI settings panel is open
-------------------------------------------------------------------------------
local function OnSettingsOpen()
    -- Cancel any pending random activation / cooldown
    EllesmereUI_StopRandomTrigger()
    -- If party mode is running from a celebration timer (auto-triggered), stop it
    if celebrationTimer then
        celebrationTimer:Cancel()
        celebrationTimer = nil
        if EllesmereUIDB then EllesmereUIDB.partyMode = false end
        EllesmereUI_StopPartyMode()
    end
end

local function OnSettingsClose()
    -- Resume random trigger if enabled
    if EllesmereUIDB and EllesmereUIDB.partyModeTriggerRandom then
        EllesmereUI_StartRandomTrigger()
    end
end

EllesmereUI:RegisterOnShow(OnSettingsOpen)
EllesmereUI:RegisterOnHide(OnSettingsClose)

-------------------------------------------------------------------------------
--  Init frame — handles PLAYER_LOGIN, events, PLAYER_LOGOUT
-------------------------------------------------------------------------------
-- Bloodlust celebration trigger: same player-only Sated/Exhaustion debuff edge
-- detection used by the CDM lust bar. Fires a celebration the instant lust goes
-- out (the debuff is applied at that moment). Hardcoded 40s celebration -- it
-- deliberately ignores the Auto Celebration Duration slider.
local PM_SATED_DEBUFFS = { 57723, 57724, 80354, 95809, 160455, 264689, 390435 }
local _pmSatedPresent = false
local function _pmPlayerHasSated()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
    for i = 1, #PM_SATED_DEBUFFS do
        if C_UnitAuras.GetPlayerAuraBySpellID(PM_SATED_DEBUFFS[i]) then return true end
    end
    return false
end

local pmInit = CreateFrame("Frame")
pmInit:RegisterEvent("PLAYER_LOGIN")
pmInit:RegisterEvent("PLAYER_LOGOUT")

-- Register the player-only UNIT_AURA listener only while the Bloodlust trigger
-- is enabled (UNIT_AURA is high-frequency). Global so the options checkbox can
-- toggle it live, mirroring EllesmereUI_StartRandomTrigger.
function EllesmereUI_UpdatePartyModeLustListener()
    if EllesmereUIDB and EllesmereUIDB.partyModeTriggerBloodlust then
        _pmSatedPresent = _pmPlayerHasSated()  -- baseline so only NEW edges fire
        pmInit:RegisterUnitEvent("UNIT_AURA", "player")
    else
        pmInit:UnregisterEvent("UNIT_AURA")
    end
end

pmInit:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        -- Restore saved keybind for party mode toggle
        if EllesmereUIDB and EllesmereUIDB.partyModeKey then
            SetOverrideBindingClick(EllesmereUIPartyModeBindBtn, true, EllesmereUIDB.partyModeKey, "EllesmereUIPartyModeBindBtn")
        end
        -- Start party mode if saved on
        if EllesmereUIDB and EllesmereUIDB.partyMode then
            EllesmereUI_StartPartyMode()
        end
        -- Register events
        self:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        self:RegisterEvent("ENCOUNTER_END")
        self:RegisterEvent("PVP_MATCH_COMPLETE")
        -- Start random trigger if enabled
        if EllesmereUIDB and EllesmereUIDB.partyModeTriggerRandom then
            EllesmereUI_StartRandomTrigger()
        end
        -- Start Bloodlust debuff listener if enabled
        EllesmereUI_UpdatePartyModeLustListener()

    elseif event == "UNIT_AURA" then
        if not (EllesmereUIDB and EllesmereUIDB.partyModeTriggerBloodlust) then return end
        local present = _pmPlayerHasSated()
        if present and not _pmSatedPresent then
            -- Rising edge: lust just went out. Hardcoded 40s (NOT the slider),
            -- and this trigger never enables the Auto Celebration Duration setting.
            EllesmereUIDB.partyMode = true
            EllesmereUI_StartPartyMode()
            if celebrationTimer then celebrationTimer:Cancel() end
            celebrationTimer = C_Timer.NewTimer(40, function()
                celebrationTimer = nil
                if EllesmereUIDB then EllesmereUIDB.partyMode = false end
                EllesmereUI_StopPartyMode()
            end)
        end
        _pmSatedPresent = present

    elseif event == "CHALLENGE_MODE_COMPLETED" then
        if not EllesmereUIDB or not EllesmereUIDB.partyModeTriggerKeystone then return end
        -- Only trigger for timed keystones
        local onTime = false
        if C_ChallengeMode.GetChallengeCompletionInfo then
            local info = C_ChallengeMode.GetChallengeCompletionInfo()
            onTime = info and info.onTime
        elseif C_ChallengeMode.GetCompletionInfo then
            local _, _, _, ot = C_ChallengeMode.GetCompletionInfo()
            onTime = ot
        end
        if not onTime then return end
        EllesmereUIDB.partyMode = true
        EllesmereUI_StartPartyMode()
        if celebrationTimer then celebrationTimer:Cancel() end
        local duration = (EllesmereUIDB and EllesmereUIDB.partyModeMPlusDuration) or 30
        celebrationTimer = C_Timer.NewTimer(duration, function()
            celebrationTimer = nil
            if EllesmereUIDB then EllesmereUIDB.partyMode = false end
            EllesmereUI_StopPartyMode()
        end)

    elseif event == "ENCOUNTER_END" then
        local encounterID, encounterName, difficultyID, groupSize, success = ...
        if success ~= 1 then return end
        local diffMap = {
            [16]  = "partyModeTriggerMythicBoss",
            [233] = "partyModeTriggerMythicBoss",  -- flex Mythic (RaidMythicFlexible)
            [15]  = "partyModeTriggerHeroicBoss",
            [14]  = "partyModeTriggerNormalBoss",
            [17]  = "partyModeTriggerLFRBoss",
            [23]  = "partyModeTriggerMythic0",
        }
        local key = diffMap[difficultyID]
        if not key then return end
        if not (EllesmereUIDB and EllesmereUIDB[key]) then return end
        EllesmereUIDB.partyMode = true
        EllesmereUI_StartPartyMode()
        if celebrationTimer then celebrationTimer:Cancel() end
        local duration = (EllesmereUIDB and EllesmereUIDB.partyModeMPlusDuration) or 30
        celebrationTimer = C_Timer.NewTimer(duration, function()
            celebrationTimer = nil
            if EllesmereUIDB then EllesmereUIDB.partyMode = false end
            EllesmereUI_StopPartyMode()
        end)

    elseif event == "PVP_MATCH_COMPLETE" then
        local winner = ...
        if not EllesmereUIDB then return end
        -- Determine if the player's faction won
        local playerFaction = UnitFactionGroup("player")
        local playerWon = false
        if playerFaction == "Horde" and winner == 0 then playerWon = true end
        if playerFaction == "Alliance" and winner == 1 then playerWon = true end
        if not playerWon then return end
        -- Check which type of rated PvP
        local triggered = false
        if C_PvP and C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground() and EllesmereUIDB.partyModeTriggerRatedBG then
            triggered = true
        end
        if C_PvP and C_PvP.IsRatedArena and C_PvP.IsRatedArena() and EllesmereUIDB.partyModeTriggerRatedArena then
            triggered = true
        end
        if not triggered then return end
        EllesmereUIDB.partyMode = true
        EllesmereUI_StartPartyMode()
        if celebrationTimer then celebrationTimer:Cancel() end
        local duration = (EllesmereUIDB and EllesmereUIDB.partyModeMPlusDuration) or 30
        celebrationTimer = C_Timer.NewTimer(duration, function()
            celebrationTimer = nil
            if EllesmereUIDB then EllesmereUIDB.partyMode = false end
            EllesmereUI_StopPartyMode()
        end)

    elseif event == "PLAYER_LOGOUT" then
        EllesmereUI_RestoreDimLights()
    end
end)
