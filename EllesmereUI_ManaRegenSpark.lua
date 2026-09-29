if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EllesmereUI_ManaRegenSpark.lua
-- WoW FOREVER ONLY: mana regen spark on mana power bars.
--
-- The five second rule: Spirit regen stops when a spell that costs mana
-- finishes casting and resumes five seconds later. A completed cast of a
-- spell that costs mana starts one 5s sweep, and another such cast restarts
-- it; when it ends the spark hides and nothing runs until the next one. Mana
-- is SECRET, so nothing here reads or compares a mana value: the signals are
-- the cast event and the spell's cost type.
--
-- Hosts ("erb" Resource Bars power bar, "uf" Unit Frames player power bar)
-- Attach their StatusBar while their option is on and the bar can draw, and
-- Detach it otherwise. Attach also lays the spark out, so hosts call it on
-- every rebuild, after the bar's orientation and reverse fill are set.
-- SetMana reports whether the bar shows mana, attached or not. The spark
-- rides an overlay StatusBar, shown only while the sweep draws on it, whose
-- fill the engine animates (SetTimerDuration); one reused animation group
-- times the sweep, so no Lua runs per frame and no sweep creates a timer.
-- Cost: the cast event is registered only while an attached host bar is
-- visible (OnShow/OnHide of our own bars). A bar showing Energy or Rage (a
-- druid in a form) keeps it, so a cast there still starts the sweep and the
-- spark joins it on the return to mana. Off, only the unregistered event
-- frame, its animation group and one duration object exist; warriors and
-- rogues, who have no mana, get nothing at all.
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
local _, PLAYER_CLASS = UnitClass("player")
if PLAYER_CLASS == "WARRIOR" or PLAYER_CLASS == "ROGUE" then return end

local MANA = Enum.PowerType.Mana
local WINDOW = 5   -- five second rule
local SPARK_W = 8  -- spark thickness along the fill direction
local SPARK_TEX = "Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga"
local IMMEDIATE = Enum.StatusBarInterpolation.Immediate
local ELAPSED = Enum.StatusBarTimerDirection.ElapsedTime

local hosts = {}   -- key -> host record while attached
local built = {}   -- bar -> host record (kept across detach)
local mana = {}    -- key -> true while that host's bar shows mana
local listening = false
local sweeping = false   -- true while the sweep runs
local dur = C_DurationUtil.CreateDuration()
local ev = CreateFrame("Frame")
local timer = ev:CreateAnimationGroup()   -- one-shot, one sweep long
local timerSpan = timer:CreateAnimation("Animation")
timerSpan:SetDuration(WINDOW)

-- True when the spell's cost includes mana. A secret amount counts as a cost;
-- only a plain 0 is free.
local function CostsMana(spellID)
    if issecretvalue(spellID) or not spellID then return false end
    local costs = C_Spell.GetSpellPowerCost(spellID)
    if not costs then return false end
    for i = 1, #costs do
        local c = costs[i]
        if not issecretvalue(c.type) and c.type == MANA then
            local amt = c.cost
            return issecretvalue(amt) or (type(amt) == "number" and amt > 0)
        end
    end
    return false
end

-- Lays the spark on the overlay's fill edge in the host bar's orientation.
-- Two points span the bar's thickness, so resizes follow with no Lua. The
-- inputs are the bar's orientation and reverse fill (the overlay's fill
-- texture is set once, at build); while they hold, the anchors stand.
local function Layout(h)
    local bar = h.bar
    local vert = bar:GetOrientation() == "VERTICAL"
    local rev = bar:GetReverseFill() and true or false
    if h.vert == vert and h.rev == rev then return end
    h.vert, h.rev = vert, rev
    local o, s = h.overlay, h.spark
    o:SetOrientation(vert and "VERTICAL" or "HORIZONTAL")
    o:SetReverseFill(rev)
    local ft = o:GetStatusBarTexture()
    s:ClearAllPoints()
    if vert then
        -- The spark texture transposed into a horizontal line.
        s:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
        s:SetPoint("LEFT", ft, rev and "BOTTOMLEFT" or "TOPLEFT")
        s:SetPoint("RIGHT", ft, rev and "BOTTOMRIGHT" or "TOPRIGHT")
        s:SetHeight(SPARK_W)
    else
        s:SetTexCoord(0, 1, 0, 1)
        s:SetPoint("TOP", ft, rev and "TOPLEFT" or "TOPRIGHT")
        s:SetPoint("BOTTOM", ft, rev and "BOTTOMLEFT" or "BOTTOMRIGHT")
        s:SetWidth(SPARK_W)
    end
end

-- Puts an attached host's spark into the running sweep, at its current
-- position, or hides it: it draws only while the sweep runs, the bar shows
-- mana and the bar is visible.
local function Arm(h)
    local o = h.overlay
    if sweeping and mana[h.key] and h.bar:IsVisible() then
        o:Show()
        o:SetTimerDuration(dur, IMMEDIATE, ELAPSED)
    else
        o:Hide()
    end
end

local function Idle()
    timer:Stop()
    sweeping = false
    for _, h in pairs(hosts) do h.overlay:Hide() end
end

-- Starts the 5s sweep on every host from now; a sweep already running
-- starts over.
local function Sweep()
    sweeping = true
    dur:SetTimeFromStart(GetTime(), WINDOW)
    for _, h in pairs(hosts) do Arm(h) end
    timer:Stop()
    timer:Play()
end

-- The sweep ran out: regen has resumed.
timer:SetScript("OnFinished", Idle)

-- UNIT_SPELLCAST_SUCCEEDED, the one event heard.
ev:SetScript("OnEvent", function(_, _, _, _, spellID)
    if CostsMana(spellID) then Sweep() end
end)

-- The event is heard while at least one attached host bar is visible; when
-- the last one hides or detaches it is dropped and the sweep ends.
local function Listen()
    local on = false
    for _, h in pairs(hosts) do
        if h.bar:IsVisible() then on = true; break end
    end
    if on == listening then return end
    listening = on
    if on then
        ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        ev:UnregisterAllEvents()
        Idle()
    end
end

-- Hooked once on each host bar (our own StatusBars). A bar that is not
-- attached returns at once; a shown bar joins the running sweep.
local function OnHostShow(bar)
    local h = built[bar]
    if hosts[h.key] == h then
        Listen()
        Arm(h)
    end
end

local function OnHostHide(bar)
    local h = built[bar]
    if hosts[h.key] == h then Listen() end
end

local MRS = {}
EllesmereUI.ManaRegenSpark = MRS

-- The host's option is on and its bar can draw. Lays the spark out on every
-- call, so hosts call it on every rebuild.
function MRS.Attach(key, bar)
    local h = built[bar]
    if not h then
        local o = CreateFrame("StatusBar", nil, bar)
        o:SetAllPoints(bar)
        o:SetFrameLevel(bar:GetFrameLevel() + 2)
        o:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        o:GetStatusBarTexture():SetAlpha(0)
        o:SetMinMaxValues(0, 1)
        o:SetValue(0)
        o:Hide()
        local s = o:CreateTexture(nil, "OVERLAY", nil, 1)
        s:SetTexture(SPARK_TEX)
        s:SetBlendMode("ADD")
        h = { bar = bar, overlay = o, spark = s }
        built[bar] = h
        bar:HookScript("OnShow", OnHostShow)
        bar:HookScript("OnHide", OnHostHide)
    end
    Layout(h)
    local old = hosts[key]
    if old == h then return end
    if old then old.overlay:Hide() end
    h.key = key
    hosts[key] = h
    Listen()
    Arm(h)
end

function MRS.Detach(key)
    local h = hosts[key]
    if not h then return end
    hosts[key] = nil
    h.overlay:Hide()
    Listen()
end

-- The host reports whether its bar shows mana. Kept while detached, so an
-- attach starts from the last report; on the edge to mana a running sweep
-- shows at once, at its current position.
function MRS.SetMana(key, isMana)
    if mana[key] == isMana then return end
    mana[key] = isMana
    local h = hosts[key]
    if h then
        if isMana then Layout(h) end
        Arm(h)
    end
end
