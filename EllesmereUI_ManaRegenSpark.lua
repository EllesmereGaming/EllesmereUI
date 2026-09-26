if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EllesmereUI_ManaRegenSpark.lua
-- WoW FOREVER ONLY: mana regen spark on mana power bars.
--
-- Mana regenerates in ticks every 2 seconds, and Spirit regen stops when a
-- spell finishes casting, resuming five seconds after the last cast
-- (warcraft.wiki.gg/wiki/Mana_regeneration). The spark shows both:
--   * a completed cast of a spell that costs mana starts a 5s sweep
--   * when it ends (or mana starts changing while idle) 2s sweeps free-run,
--     never reset mid-sweep; a sweep with no mana update during it ends the
--     cycle (mana full, the event only fires on a change)
-- Mana itself is SECRET: nothing here reads or compares a mana value. The
-- signals are the cast event, the spell's cost type and UNIT_POWER_UPDATE as a
-- keep-alive. UNIT_POWER_FREQUENT is unusable: it fires many times per tick.
--
-- Hosts ("erb" ResourceBars power bar, "uf" Unit Frames player power bar)
-- Attach their StatusBar while their option is on, Detach when off, and report
-- whether the bar currently shows mana via SetMana. The spark rides an
-- invisible overlay StatusBar whose fill the engine animates (SetTimerDuration),
-- so no Lua runs per frame. Events are registered only while at least one host
-- is attached; off = no frames beyond the event shell.
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER and C_DurationUtil and C_DurationUtil.CreateDuration
    and Enum.StatusBarTimerDirection and Enum.StatusBarInterpolation) then return end

local MANA = Enum.PowerType.Mana
local WINDOW = 5   -- five second rule
local TICK = 2     -- regen tick interval
local SPARK_TEX = "Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga"
local IMMEDIATE = Enum.StatusBarInterpolation.Immediate
local ELAPSED = Enum.StatusBarTimerDirection.ElapsedTime

local hosts = {}   -- key -> host record (attached)
local built = {}   -- bar -> host record (kept across detach)
local count = 0
local sweepTimer
local inWindow = false   -- true while the 5s sweep runs
local regenSeen = false  -- mana update seen during the current tick sweep
local dur = C_DurationUtil.CreateDuration()
local ev = CreateFrame("Frame")

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

-- True when the spell's cost includes mana. A secret amount counts as a cost;
-- only a plain 0 is free.
local function CostsMana(spellID)
    if not spellID or Secret(spellID) then return false end
    local costs = C_Spell and C_Spell.GetSpellPowerCost and C_Spell.GetSpellPowerCost(spellID)
    if not costs then return false end
    for _, c in ipairs(costs) do
        if not Secret(c.type) and c.type == MANA then
            local amt = c.cost
            return Secret(amt) or (type(amt) == "number" and amt > 0)
        end
    end
    return false
end

-- Spark follows the overlay's fill edge in the host's orientation. Vertical
-- bars get the spark texture transposed into a horizontal line.
local function Layout(h)
    local bar, o, s = h.bar, h.overlay, h.spark
    local vert = bar:GetOrientation() == "VERTICAL"
    local rev = bar:GetReverseFill()
    o:SetOrientation(vert and "VERTICAL" or "HORIZONTAL")
    o:SetReverseFill(rev)
    local ft = o:GetStatusBarTexture()
    s:ClearAllPoints()
    if vert then
        s:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
        s:SetSize(bar:GetWidth(), 8)
        s:SetPoint("CENTER", ft, rev and "BOTTOM" or "TOP", 0, 0)
    else
        s:SetTexCoord(0, 1, 0, 1)
        s:SetSize(8, bar:GetHeight())
        s:SetPoint("CENTER", ft, rev and "LEFT" or "RIGHT", 0, 0)
    end
end

local function Idle()
    if sweepTimer then sweepTimer:Cancel() end
    sweepTimer = nil
    inWindow = false
    regenSeen = false
    for _, h in pairs(hosts) do h.spark:Hide() end
end

local OnSweepEnd

local function Sweep(len)
    dur:SetTimeFromStart(GetTime(), len)
    for _, h in pairs(hosts) do
        Layout(h)
        h.overlay:SetTimerDuration(dur, IMMEDIATE, ELAPSED)
        h.spark:SetShown(h.mana)
    end
    if sweepTimer then sweepTimer:Cancel() end
    sweepTimer = C_Timer.NewTimer(len, OnSweepEnd)
end

-- not the server tick; no non-secret tick signal exists.
OnSweepEnd = function()
    sweepTimer = nil
    if inWindow or regenSeen then
        inWindow = false
        regenSeen = false
        Sweep(TICK)
    else
        Idle()
    end
end

ev:SetScript("OnEvent", function(_, event, _, arg2, arg3)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if CostsMana(arg3) then
            inWindow = true
            regenSeen = false
            Sweep(WINDOW)
        end
    elseif arg2 == "MANA" and not inWindow then
        if sweepTimer then regenSeen = true else Sweep(TICK) end
    end
end)

EllesmereUI.ManaRegenSpark = {}

function EllesmereUI.ManaRegenSpark.Attach(key, bar)
    if not bar then return end
    local h = built[bar]
    if h and hosts[key] == h then return end
    if not h then
        local o = CreateFrame("StatusBar", nil, bar)
        o:SetAllPoints(bar)
        o:SetFrameLevel(bar:GetFrameLevel() + 2)
        o:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        o:GetStatusBarTexture():SetAlpha(0)
        o:SetMinMaxValues(0, 1)
        o:SetValue(0)
        local s = o:CreateTexture(nil, "OVERLAY", nil, 1)
        s:SetTexture(SPARK_TEX)
        s:SetBlendMode("ADD")
        s:Hide()
        h = { bar = bar, overlay = o, spark = s, mana = false }
        built[bar] = h
    end
    local old = hosts[key]
    if old then old.spark:Hide() else count = count + 1 end
    hosts[key] = h
    if count == 1 and not old then
        ev:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    end
end

function EllesmereUI.ManaRegenSpark.Detach(key)
    local h = hosts[key]
    if not h then return end
    h.spark:Hide()
    hosts[key] = nil
    count = count - 1
    if count == 0 then
        ev:UnregisterAllEvents()
        Idle()
    end
end

-- Host reports whether its bar shows mana right now; spark only draws on mana.
function EllesmereUI.ManaRegenSpark.SetMana(key, isMana)
    local h = hosts[key]
    if not h or h.mana == isMana then return end
    h.mana = isMana
    h.spark:SetShown(isMana and sweepTimer ~= nil)
end
