if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
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
--  Activation sound catalogue
--  Same built-in files as the chat whisper alert, plus LibSharedMedia
--  sounds. Built lazily on first request (options page open or first
--  activation): both happen well after login, so sound packs other addons
--  register with SharedMedia at their own load time are all present.
-------------------------------------------------------------------------------
local _soundPaths, _soundNames, _soundOrder
local function GetSoundTables()
    if not _soundPaths then
        local EUI = _G.EllesmereUI
        _soundPaths, _soundNames, _soundOrder = EUI.BuildAlertSoundTables()
        EUI.AppendSharedMediaSounds(_soundPaths, _soundNames, _soundOrder)
    end
    return _soundPaths, _soundNames, _soundOrder
end

-- Options page reads the catalogue through this accessor.
function EllesmereUI_GetPartyModeSounds()
    return GetSoundTables()
end

-------------------------------------------------------------------------------
--  Global API
-------------------------------------------------------------------------------
function EllesmereUI_StartPartyMode()
    CreateOverlay()
    -- Activation sound: only on the actual off->on edge, so re-entrant
    -- Start calls while the overlay is already visible stay silent.
    if not container:IsShown() then
        local key = EllesmereUIDB and EllesmereUIDB.partyModeSoundKey
        if key and key ~= "none" then
            local paths = GetSoundTables()
            local path = paths[key]
            if path then PlaySoundFile(path, "Master") end
        end
    end
    container:Show()
    -- Dim the lights if enabled (defaults to on)
    if EllesmereUIDB and (EllesmereUIDB.partyModeDimLights ~= false) then
        EllesmereUI_ApplyDimLights()
    end
    -- Party Mode visibility lanes (Visibility > Party Mode) have no game event.
    if EllesmereUI.FireVisEdge then EllesmereUI.FireVisEdge() end
end

function EllesmereUI_StopPartyMode()
    if container then container:Hide() end
    EllesmereUI_RestoreDimLights()
    if EllesmereUI.FireVisEdge then EllesmereUI.FireVisEdge() end
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
-- (The lust BUFF itself is secret-flagged on 12.1 -- presence reads absent in
-- restricted combat -- so detection rides the READABLE Sated debuff edge.)
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

-- Register PLAYER_LEVEL_UP only while the Level Up trigger is enabled, so users
-- who never turn it on pay nothing. Global so the options checkbox can toggle
-- it live, mirroring EllesmereUI_UpdatePartyModeLustListener.
function EllesmereUI_UpdatePartyModeLevelUpListener()
    if EllesmereUIDB and EllesmereUIDB.partyModeTriggerLevelUp then
        pmInit:RegisterEvent("PLAYER_LEVEL_UP")
    else
        pmInit:UnregisterEvent("PLAYER_LEVEL_UP")
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
        -- Start Level Up listener if enabled
        EllesmereUI_UpdatePartyModeLevelUpListener()

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

    elseif event == "PLAYER_LEVEL_UP" then
        if not (EllesmereUIDB and EllesmereUIDB.partyModeTriggerLevelUp) then return end
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
        -- An automatic celebration only lives as long as its timer, so never save
        -- it as on: the next login would start Party Mode with nothing to stop it.
        -- A session the user turned on by hand has no timer and stays saved.
        if celebrationTimer and EllesmereUIDB then EllesmereUIDB.partyMode = false end
        EllesmereUI_RestoreDimLights()
    end
end)

-------------------------------------------------------------------------------
--  Party Mode spin engine. EllesmereUI.PartySpin_Create(opts) -> refresh()
--  opts: target (one key of the Spinning setting, read through
--  EllesmereUI.PartySpinOn; every target turns at partyModeSpinSpeed, deg/s,
--  default 120), collect() -> { { pivot = frame, frames = {...} }, ... }
--  (runs about once a second while spinning, so it reuses its tables), and
--  optional onClaim() (idempotent, same cadence) and onRestore().
--  EllesmereUI.PartySpin_RefreshAll() re-applies every engine.
--  A SetPoint post-hook marks a member dirty when its module re-anchors it.
--  Pauses in combat and while Unlock Mode is open (members go home to drag).
-------------------------------------------------------------------------------
do
local SPIN_TARGETS = { "actionBars", "dataBars", "unitFrames", "resource", "power" }

-- EllesmereUIDB.partyModeSpinBars: nil / false = nothing spins, true = Action
-- Bars only, a table = one boolean per target. Every reader comes through
-- here: a plain truthiness test would take a table for "on". settingOnly
-- skips the Party Mode check (the options checkmarks).
local function SpinOn(target, settingOnly)
    local db = EllesmereUIDB
    if not (db and (settingOnly or db.partyMode)) then return false end
    local v = db.partyModeSpinBars
    if type(v) == "table" then return v[target] == true end
    return v == true and target == "actionBars"
end
EllesmereUI.PartySpinOn = SpinOn

-- The options writer: a boolean store becomes the per-target table on its
-- first write, keeping its Action Bars meaning.
function EllesmereUI.PartySpinSet(target, on)
    local db = EllesmereUIDB
    if not db then return end
    local v = db.partyModeSpinBars
    if type(v) ~= "table" then
        local ab = (v == true)
        v = {}
        for i = 1, #SPIN_TARGETS do v[SPIN_TARGETS[i]] = false end
        v.actionBars = ab
        db.partyModeSpinBars = v
    end
    v[target] = on and true or false
end

local function Speed()
    local v = EllesmereUIDB and EllesmereUIDB.partyModeSpinSpeed
    if v == nil then v = 120 end
    return v
end

-- Per-frame records live here, never on the frame: some members are
-- Blizzard-owned (stance and pet buttons). A record outlives its membership,
-- so a re-claim reuses its tables and the one SetPoint hook.
local recOf = setmetatable({}, { __mode = "k" })
local guardDepth = 0
local refreshers = {}
local EMPTY = {}

local function OnMemberSetPoint(self)
    if guardDepth > 0 then return end
    local r = recOf[self]
    if r then r.dirty = true end
end

local function Measure(f, rec)
    local pts, n = rec.points, 0
    for i = 1, f:GetNumPoints() do
        local a, rel, b, x, y = f:GetPoint(i)
        -- Skip our own orbit point if the module anchored without clearing it.
        if not (rec.ox and a == "CENTER" and rel == UIParent and b == "BOTTOMLEFT"
                and x == rec.ox and y == rec.oy) then
            n = n + 1
            local p = pts[n]
            if not p then p = {}; pts[n] = p end
            p[1], p[2], p[3], p[4], p[5] = a, rel, b, x, y
        end
    end
    for i = n + 1, #pts do pts[i] = nil end
    rec.n = n
    -- A member sized by two or more anchors (SetAllPoints) loses its size
    -- under a single orbit point, so its rest size is carried explicitly.
    rec.multi = n > 1
    rec.w, rec.h = f:GetWidth(), f:GetHeight()
    local cx, cy = f:GetCenter()
    local px, py = rec.pivot:GetCenter()
    if not (cx and px) then rec.dx = nil; return end
    local fs, ps = f:GetEffectiveScale(), rec.pivot:GetEffectiveScale()
    rec.dx, rec.dy = cx * fs - px * ps, cy * fs - py * ps
    rec.dirty = false
end

-- Back onto the captured rest anchors. A member its module re-anchored since
-- the last tick is re-measured first, so that newer anchor is the one kept.
local function Restore(f, rec)
    if rec.dirty then Measure(f, rec) end
    local n = rec.n or 0
    if n == 0 then return end
    guardDepth = guardDepth + 1
    f:ClearAllPoints()
    local pts = rec.points
    for i = 1, n do
        local p = pts[i]
        f:SetPoint(p[1], p[2], p[3], p[4], p[5])
    end
    guardDepth = guardDepth - 1
    rec.ox, rec.oy = nil, nil
end

local function RefreshAll()
    for i = 1, #refreshers do refreshers[i]() end
end
EllesmereUI.PartySpin_RefreshAll = RefreshAll

function EllesmereUI.PartySpin_Create(opts)
    local target = opts.target
    local driver, deferF
    local angle, held, since, claimed = 0, false, 0, false
    local members = {}     -- frame -> its recOf record
    local order = {}       -- array of frames (stable iteration)
    local seen = {}        -- Claim scratch, wiped after each pass

    local function On() return SpinOn(target) end

    local function RestoreAll()
        for i = 1, #order do
            local f = order[i]
            Restore(f, members[f])
        end
        wipe(members); wipe(order)
        claimed = false
        if opts.onRestore then opts.onRestore() end
    end

    local function Claim()
        claimed = true
        local groups = opts.collect() or EMPTY
        for g = 1, #groups do
            local grp = groups[g]
            local pivot, list = grp.pivot, grp.frames
            if pivot and list then
                for i = 1, #list do
                    local f = list[i]
                    if f and f.GetCenter and not seen[f] then
                        seen[f] = true
                        if not members[f] then
                            local rec = recOf[f]
                            if not rec then
                                rec = { points = {} }
                                recOf[f] = rec
                                hooksecurefunc(f, "SetPoint", OnMemberSetPoint)
                            end
                            rec.pivot = pivot
                            members[f] = rec
                            order[#order + 1] = f
                            Measure(f, rec)
                        end
                    end
                end
            end
        end
        -- Members that left the collection (block removed, frame gone) go home.
        for i = #order, 1, -1 do
            local f = order[i]
            if not seen[f] then
                Restore(f, members[f])
                members[f] = nil
                table.remove(order, i)
            end
        end
        wipe(seen)
        if opts.onClaim then opts.onClaim() end
    end

    local function Tick(c, s)
        guardDepth = guardDepth + 1
        -- Members come grouped by pivot, so each pivot is read once a tick.
        local lastPivot, px, py, ps
        for i = 1, #order do
            local f = order[i]
            local rec = members[f]
            -- The module just re-anchored it: that IS rest.
            if rec.dirty or not rec.dx then Measure(f, rec) end
            local pivot = rec.pivot
            if pivot ~= lastPivot then
                lastPivot = pivot
                px, py = pivot:GetCenter()
                ps = pivot:GetEffectiveScale()
            end
            if rec.dx and px then
                local fs = f:GetEffectiveScale()
                if fs and fs > 0 then
                    local x = px * ps + rec.dx * c - rec.dy * s
                    local y = py * ps + rec.dx * s + rec.dy * c
                    rec.ox, rec.oy = x / fs, y / fs
                    f:ClearAllPoints()
                    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", rec.ox, rec.oy)
                    if rec.multi then f:SetSize(rec.w, rec.h) end
                end
            end
        end
        guardDepth = guardDepth - 1
    end

    local refresh
    refresh = function()
        local on = On()
        -- Off with nothing claimed: nothing to put back, so nothing runs.
        if not on and not claimed then
            if driver then driver:Hide() end
            angle, held = 0, false
            return
        end
        -- Moving a protected member is blocked in combat, so only the safe
        -- half (Show/Hide of our own driver) runs there; the rest re-runs on
        -- PLAYER_REGEN_ENABLED with the member table left intact.
        if InCombatLockdown() then
            if not deferF then
                deferF = CreateFrame("Frame")
                deferF:SetScript("OnEvent", function(self)
                    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    refresh()
                end)
            end
            deferF:RegisterEvent("PLAYER_REGEN_ENABLED")
            if not on then
                if driver then driver:Hide() end
                angle = 0
            elseif driver then
                driver:Show()
            end
            return
        end
        if not on then
            if driver then driver:Hide() end
            angle, held = 0, false
            RestoreAll()
            return
        end
        if not driver then
            driver = CreateFrame("Frame")
            driver:Hide()
            driver:SetScript("OnUpdate", function(_, elapsed)
                if not On() then refresh(); return end
                if InCombatLockdown() then return end
                if EllesmereUI._unlockActive then
                    if not held then held = true; RestoreAll() end
                    return
                end
                if held then held = false; Claim() end
                -- Pick up late spawns / added blocks about once a second.
                since = since + elapsed
                if since > 1 then since = 0; Claim() end
                angle = (angle + math.rad(Speed()) * elapsed) % (math.pi * 2)
                if #order > 0 then Tick(math.cos(angle), math.sin(angle)) end
            end)
        end
        Claim()
        driver:Show()
    end

    refreshers[#refreshers + 1] = refresh
    return refresh
end

-- Party Mode starts from the options page, a keybind, a random timer or
-- Bloodlust; its two public entry points catch all of them.
hooksecurefunc("EllesmereUI_StartPartyMode", RefreshAll)
hooksecurefunc("EllesmereUI_StopPartyMode", RefreshAll)
end
