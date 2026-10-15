if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not EllesmereUI or EllesmereUI.IS_FOREVER then return end
-------------------------------------------------------------------------------
--  EllesmereUIABR_BeaconMPlus.lua
--  Beacon M+ Reminders (retail, Holy Paladin; CORE > Beacon M+ Reminders, off
--  by default): during a Mythic+ boss encounter, a glowing red Beacon icon on
--  the tank's Raid Frames frame while the tank carries the player's Beacon of
--  Light or Beacon of Faith.
--
--  Auras are secret in M+, so Lua never reads them: one engine aura container
--  on the tank's unit draws the icon only while that aura is up (HELPFUL|PLAYER
--  plus the two spell IDs), and its button carries the glow. The container is
--  shown only between ENCOUNTER_START and ENCOUNTER_END inside a key, so it
--  listens to nothing outside boss fights. Raid frames do not move once a key
--  has started, so the host is placed once per encounter and never follows.
--  Other classes stop here at load; a paladin with the option off, or on
--  another spec, registers no gameplay events, and an armed one follows the
--  roster only while a key runs.
-------------------------------------------------------------------------------
if select(2, UnitClass("player")) ~= "PALADIN" then return end

local BEACON_IDS = { [53563] = true, [156910] = true } -- Beacon of Light, Beacon of Faith
local PARTY = { "party1", "party2", "party3", "party4" }
local HOLY_SPEC = 65
local ICON_SIZE = 30
local STYLE_KEY = "abrBeaconMPlus"
local GLOW_SPEC = { style = 2, r = 1, g = 0.15, b = 0.15 } -- Action Button Glow, red

local ev = CreateFrame("Frame")
local started = false   -- the first PLAYER_ENTERING_WORLD ran the initial sync
local level = -1        -- 0 off, 1 option on but not Holy, 2 armed (Holy)
local tankUnit          -- cached out of the encounter; roles can read secret in M+
local host, container, containerUnit

local function Enabled()
    local db = _G._EABR_AceDB
    local d = db and db.profile and db.profile.display
    return d and d.beaconMPlus == true
end

local function IsHoly()
    local spec = C_SpecializationInfo.GetSpecialization()
    return spec and C_SpecializationInfo.GetSpecializationInfo(spec) == HOLY_SPEC
end

local function RefreshTank()
    for i = 1, 4 do
        local u = PARTY[i]
        if UnitExists(u) then
            local role = UnitGroupRolesAssigned(u)
            if issecretvalue and issecretvalue(role) then return end -- keep the cached tank
            if role == "TANK" then tankUnit = u; return end
        end
    end
    tankUnit = nil
end

local function FindIn(list, unit)
    if not list then return end
    for i = 1, #list do
        local b = list[i]
        if b and b:IsVisible() and b:GetAttribute("unit") == unit then return b end
    end
end

-- The tank's Raid Frames button: the party frames, or the raid frames when the
-- party is shown on them.
local function TankButton(unit)
    local rf = EllesmereUI._ModuleNS["EllesmereUIRaidFrames"]
    if not rf then return end
    return FindIn(rf._partyAllButtons, unit) or FindIn(rf._allButtons, unit)
end

-- Built once per engine button, the only window where the button may be
-- decorated: the aura icon, no mouse (the tank's frame keeps its clicks and
-- mouseover casts), and the red glow on a child host, whose C-side animation
-- runs the same in and out of restricted content.
local function InitButton(button)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button:SetIcon(icon)
    pcall(button.EnableMouse, button, false)
    local glow = CreateFrame("Frame", nil, button)
    glow:SetAllPoints(button)
    glow:SetFrameLevel(button:GetFrameLevel() + 2)
    glow:EnableMouse(false)
    local Glows = EllesmereUI.Glows
    Glows.PrewarmEngineHost(glow, ICON_SIZE, ICON_SIZE, nil)
    Glows.StartSpecGlow(glow, GLOW_SPEC, ICON_SIZE, ICON_SIZE, "engine")
end

local function EnsureContainer(unit)
    if container then
        if containerUnit ~= unit then container:SetUnit(unit); containerUnit = unit end
        return
    end
    local AK = EllesmereUI.AuraKit
    AK.styles[STYLE_KEY] = AK.styles[STYLE_KEY] or { noRegions = true, width = ICON_SIZE, height = ICON_SIZE }
    host = CreateFrame("Frame", nil, UIParent)
    host:SetSize(ICON_SIZE, ICON_SIZE)
    host:SetFrameStrata("HIGH")
    host:Hide()
    container = AK.CreateContainer(host, unit, {
        point = { "CENTER", host, "CENTER" },
        layout = { anchorPoint = "CENTER" },
        groups = { {
            key = "beacon", filter = { "HELPFUL", "PLAYER" }, maxFrameCount = 1,
            candidateFilters = { includeSpellIDs = BEACON_IDS },
            style = STYLE_KEY, extraInit = InitButton,
        } },
    })
    containerUnit = unit
end

-- Engine aura hosts stay UIParent-anchored (an engine subtree must never join
-- another frame's anchor family), so the host takes the button's centre as a
-- number.
local function PlaceOver(button)
    local x, y = button:GetCenter()
    if not x or (issecretvalue and (issecretvalue(x) or issecretvalue(y))) then return false end
    local s = button:GetEffectiveScale() / UIParent:GetEffectiveScale()
    host:ClearAllPoints()
    host:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * s, y * s)
    return true
end

local function Disarm()
    if host then host:Hide() end
end

-- The tank is read only inside a key, so the roster events are registered from
-- CHALLENGE_MODE_START (or arming, or a PLAYER_ENTERING_WORLD, inside a key) to
-- the key's end; each of those starts looks the tank up again.
local function WatchRoster(on)
    if on then
        ev:RegisterEvent("GROUP_ROSTER_UPDATE")
        ev:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    else
        ev:UnregisterEvent("GROUP_ROSTER_UPDATE")
        ev:UnregisterEvent("PLAYER_ROLES_ASSIGNED")
    end
end

-- Built while the key's countdown runs (out of combat), so the first pull does
-- no engine construction; Arm still builds it if a key began before the option.
local function Prebuild()
    if level == 2 and tankUnit and C_ChallengeMode.IsChallengeModeActive() then
        EnsureContainer(tankUnit)
    end
end

local function Arm()
    if level ~= 2 or not C_ChallengeMode.IsChallengeModeActive() then return end
    local unit = tankUnit
    local button = unit and TankButton(unit)
    if not button then return end
    EnsureContainer(unit)
    if PlaceOver(button) then host:Show() end
end

local function Sync()
    local want = 0
    if Enabled() then want = IsHoly() and 2 or 1 end
    if want == level then return end
    level = want
    ev:UnregisterAllEvents()
    Disarm()
    if want == 0 then return end
    ev:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    if want == 2 then
        ev:RegisterEvent("ENCOUNTER_START")
        ev:RegisterEvent("ENCOUNTER_END")
        ev:RegisterEvent("CHALLENGE_MODE_START")
        ev:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        ev:RegisterEvent("CHALLENGE_MODE_RESET")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        WatchRoster(C_ChallengeMode.IsChallengeModeActive())
        RefreshTank()
        if IsEncounterInProgress() then Arm() else Prebuild() end
    end
end

ev:SetScript("OnEvent", function(_, event)
    if event == "ENCOUNTER_START" then
        Arm()
    elseif event == "CHALLENGE_MODE_START" then
        WatchRoster(true)
        RefreshTank()
        Prebuild()
    elseif event == "ENCOUNTER_END" then
        Disarm()
    elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET" then
        WatchRoster(false)
        Disarm()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
        RefreshTank()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not started then
            -- After every module's OnEnable, so ABR's DB and refresh exist. The
            -- options page and profile switches both go through that refresh.
            started = true
            if _G._EABR_RequestRefresh then hooksecurefunc("_EABR_RequestRefresh", Sync) end
            Sync()
            return
        end
        Disarm()
        WatchRoster(C_ChallengeMode.IsChallengeModeActive())
        RefreshTank()
        if IsEncounterInProgress() then Arm() else Prebuild() end
    else -- PLAYER_SPECIALIZATION_CHANGED
        Sync()
    end
end)
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
