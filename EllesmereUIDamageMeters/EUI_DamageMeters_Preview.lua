if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_DamageMeters_Preview.lua
--  Test Bars: sample rows W.Refresh paints instead of the session while the
--  options button has them on. Not saved; they outlive the options panel in
--  every window its visibility rules show, and end on combat start. Each show
--  rolls new values and a new order. Row click and hover do nothing.
-------------------------------------------------------------------------------
local _, ns = ...

local ROWS = 8  -- the player plus seven roster members
local SHARES = { 1, 0.91, 0.84, 0.77, 0.69, 0.6, 0.45, 0.3 }
local DURATION = 185  -- seconds the sample amounts are spread over

-- Spec icon per roster class and role (EllesmereUI.PREVIEW_ROSTER carries no spec).
local SPEC_BY_ROLE = {
    ["MONK:TANK"] = 268, ["MONK:HEALER"] = 270, ["WARRIOR:TANK"] = 73,
    ["PALADIN:HEALER"] = 65, ["DRUID:HEALER"] = 105, ["DRUID:DAMAGER"] = 102,
    ["PRIEST:DAMAGER"] = 258, ["SHAMAN:DAMAGER"] = 262, ["HUNTER:DAMAGER"] = 253,
    ["DEATHKNIGHT:DAMAGER"] = 251, ["DEMONHUNTER:DAMAGER"] = 577, ["EVOKER:DAMAGER"] = 1467,
    ["MAGE:DAMAGER"] = 63, ["ROGUE:DAMAGER"] = 259, ["WARLOCK:DAMAGER"] = 267,
}
-- Enemy Damage Taken lists mobs: no class, so the window's own mob look applies.
-- Translated on the first use (the locale is fixed for the session).
local MOBS
local function Mobs()
    if not MOBS then
        MOBS = {
            EllesmereUI.L("Training Dummy"), EllesmereUI.L("Shadowguard Brute"),
            EllesmereUI.L("Void Ravager"), EllesmereUI.L("Ember Hound"),
            EllesmereUI.L("Cultist Adept"), EllesmereUI.L("Gilded Sentinel"),
            EllesmereUI.L("Rift Stalker"), EllesmereUI.L("Bog Lurker"),
        }
    end
    return MOBS
end

local _sessions = {}

-- WoW Forever keeps specIconID secret, so its meter shows class icons: so do the samples.
local function SpecIcon(specID)
    if EllesmereUI.IS_FOREVER or not (specID and GetSpecializationInfoByID) then return nil end
    local _, _, _, icon = GetSpecializationInfoByID(specID)
    return icon
end

local function OwnSpecIcon()
    if EllesmereUI.IS_FOREVER then return nil end
    local idx = C_SpecializationInfo.GetSpecialization()
    if not idx then return nil end
    local _, _, _, icon = C_SpecializationInfo.GetSpecializationInfo(idx)
    return icon
end

local function Shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function Desc(a, b) return a > b end

local function Build(dmType)
    local T, random = Enum.DamageMeterType, math.random
    local isDeaths = dmType == T.Deaths
    local isCount = dmType == T.Interrupts or dmType == T.Dispels
    local isEnemy = dmType == T.EnemyDamageTaken
    local isThreat = dmType == "threat"  -- WoW Forever: rows bring their own rank and value text
    local base = (dmType == T.HealingDone) and 3100000
        or (dmType == T.DamageTaken or dmType == T.AvoidableDamageTaken) and 1400000
        or 4600000
    base = base * (0.75 + random() * 0.5)
    -- Who appears in which slot: seven random roster members and the player (slot 0),
    -- or the mob names; shares slightly varied and kept descending.
    local roster = EllesmereUI.PREVIEW_ROSTER
    local mobs = isEnemy and Mobs()
    local pick = {}
    if isEnemy then
        for i = 1, #mobs do pick[i] = i end
    else
        for i = 1, #roster do pick[i] = i end
        Shuffle(pick)
        for i = #pick, ROWS, -1 do pick[i] = nil end
        pick[#pick + 1] = 0
    end
    Shuffle(pick)
    local shares = {}
    for i = 1, ROWS do shares[i] = SHARES[i] * (0.85 + random() * 0.3) end
    table.sort(shares, Desc)
    local rows = {}
    local n = math.min(isDeaths and 3 or ROWS, #pick)
    -- Deaths come most recent first, as the API hands them over (RefreshUI reverses).
    local t = 20 + 70 * n + random(0, 60)
    for i = 1, n do
        local p, row = pick[i], {}
        if isEnemy then
            row.name = mobs[p]
        elseif p == 0 then
            local _, classFile = UnitClass("player")
            row.name, row.classFilename = UnitName("player"), classFile
            row.specIconID, row.isLocalPlayer = OwnSpecIcon(), true
        else
            local r = roster[p]
            row.name, row.classFilename = r.name, r.class
            row.specIconID = SpecIcon(SPEC_BY_ROLE[r.class .. ":" .. (r.role or "")])
        end
        if isDeaths then
            -- Positive recap IDs keep the rows past the Deaths filter in RefreshUI.
            row.deathRecapID, row.deathTimeSeconds = i, t
            t = t - random(15, 70)
        elseif isThreat then
            row.totalAmount = math.floor(shares[i] / shares[1] * 100 + 0.5)
            row.threatScaled = row.totalAmount  -- the Value Gradient's threat share
            row.rankText, row.threatText = i .. ".", row.totalAmount .. "%"
        elseif isCount then
            row.totalAmount = math.max(1, math.floor(10 * shares[i] + 0.5))
        else
            row.totalAmount = math.floor(base * shares[i])
            row.amountPerSecond = row.totalAmount / DURATION
        end
        rows[i] = row
    end
    return { combatSources = rows }
end

-- The sample session one meter type paints; built on first use per show.
function ns.DMPreviewSession(dmType)
    local s = _sessions[dmType]
    if not s then s = Build(dmType); _sessions[dmType] = s end
    return s
end

-- Switches the Test Bars on or off and repaints every window. On also leaves the
-- Home grid and any open breakdown, which would cover the rows.
function ns.SetDMPreview(on)
    on = on and true or false
    if (ns._dmPreview or false) == on then return end
    ns._dmPreview = on
    -- New values per show, and the own row reads name, class and spec at build time.
    wipe(_sessions)
    if on then
        for _, w in ipairs(ns._windows or {}) do
            if w.HideHome then w.HideHome() end
            if w.sourceOpen and w.CloseSource then w.CloseSource() end
        end
    end
    if ns.RefreshMeter then ns.RefreshMeter() end
end
