if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_ForeverSwingSweep.lua -- WoW FOREVER ONLY: the Swing Timer swipe.
--
--  On-next-swing attacks (EllesmereUI.FOREVER_NEXT_SWING: Heroic Strike,
--  Cleave, Maul, Raptor Strike) have no cooldown, so their icons show no
--  swipe. Per spell (showSwingTimer, off by default) the icon shows the weapon
--  swing the attack rides instead: each PLAYER_SWING of that hand starts a
--  swipe for the swing's duration, as the Resource Bars swing timer starts its
--  row (EUI_ResourceBars_SwingTimer.lua).
--
--  The swipe is a Cooldown of our own over the icon, never the icon's: the
--  viewer rewrites that one on every cooldown event, and a real cooldown keeps
--  it. The engine animates it; Lua runs at a swing's start and after a
--  reanchor (ns.CDM_SwingSweepSync, nil-guarded at its callers).
--
--  Cost: nothing until some saved spell has the setting. ns._cdmAnySwingSweep
--  is set once by ns.RescanSwingSweepFlag at setup, or by the menu on first
--  use (monotonic, like the other per-spell gates). PLAYER_SWING is registered
--  only while an icon on the bars shows the swipe.
-------------------------------------------------------------------------------
local _, ns = ...

-- The swing API is the Forever client's; a class with no such attack has
-- nothing to show. Neither the menu rows nor the gate exist past this point.
local SWING = Enum.PlayerSwingType
if not (C_SwingTimer and SWING) then return end
local _, classFile = UnitClass("player")
local attackIDs = EllesmereUI.FOREVER_NEXT_SWING and EllesmereUI.FOREVER_NEXT_SWING[classFile]
if not attackIDs then return end

local GetTime = GetTime
local PlainString = EllesmereUI.PlainString
local cdmBarIcons, barDataByKey, _ecmeFC = ns.cdmBarIcons, ns.barDataByKey, ns._ecmeFC
local I = ns._hookInternals

local nameSwing = {}                    -- [attack name] = the swing it rides
local namesDone = false
local sidSwing = {}                     -- [spellID] = its swing, false = no such attack
local sweeps = setmetatable({}, { __mode = "k" })   -- [icon] = our Cooldown over it
local shownSid, shownSwing = {}, {}     -- [icon] = its spell / swing while the swipe is on
local seen = {}
local swingStart, swingDur = {}, {}     -- [swing] = the swing running now
local listening = false
local scanned = false
local ev = ns.TakeShell()

-- Every rank shares its attack's name, the way the swing timer and the queued
-- highlight match them. All of them ride the Main Hand swing, the row the
-- swing timer shows a queued attack on.
local function ResolveNames()
    namesDone = true
    for i = 1, #attackIDs do
        local n = PlainString(C_Spell.GetSpellName(attackIDs[i]))
        if n then nameSwing[n] = SWING.MainHand else namesDone = false end
    end
end

local function SwingOf(sid)
    local s = sidSwing[sid]
    if s ~= nil then return s end
    if not namesDone then ResolveNames() end
    local n = PlainString(C_Spell.GetSpellName(sid))
    s = n and nameSwing[n] or false
    if n and namesDone then sidSwing[sid] = s end
    return s
end

-- The menu shows its row for these spells only.
function ns.CDM_IsSwingSweepSpell(sid)
    return type(sid) == "number" and sid > 0 and SwingOf(sid) ~= false
end

-- A frame we inject keeps its settings in customActiveStates, a viewer frame
-- in the per-spell store and the bar tiers (as the Stance Bar setting reads).
local function Wants(icon, sid, barKey)
    local s
    if ns.CdmIsInjectedFrame(icon) then
        s = ns.GetEffectiveCustomActiveState(sid)
    else
        s = ns.ResolveSpellSettings(icon, sid, false, barKey)
    end
    return (s and s.showSwingTimer) and true or false
end

-- Our Cooldown, dressed as the icon's own: its level, the bar's swipe and
-- edge, the spell's Reverse Swipe and the icon's shape.
local function Style(icon, bd, barKey)
    local cd = sweeps[icon]
    if not cd then
        cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:SetDrawBling(false)
        cd:SetHideCountdownNumbers(true)
        cd:EnableMouse(false)
        sweeps[icon] = cd
    end
    local own = icon.Cooldown or icon._cooldown
    cd:SetFrameLevel(own and own:GetFrameLevel() or (icon:GetFrameLevel() + 1))
    cd:SetSwipeColor(0, 0, 0, bd.swipeAlpha or 0.7)
    cd:SetReverse(ns.EffectiveReverseSwipe(icon, barKey, false))
    ns.ApplyShapeToOverlay(icon, nil, cd, bd)
    local fc = _ecmeFC[icon]
    if not (fc and fc.shapeApplied) then cd:SetSwipeTexture(ns.CdmSwipeFile()) end
    if bd.showCooldownEdge and I and I.ApplyCdmEdge then
        I.ApplyCdmEdge(cd, barKey)
    else
        cd:SetDrawEdge(false)
    end
end

-- The running swing on one icon, or nothing: none running, or the spell is on
-- a cooldown of its own, which the icon's own swipe shows.
local function Paint(icon, now)
    local swing = shownSwing[icon]
    local start, dur = swingStart[swing], swingDur[swing]
    if start and now < start + dur
       and not ns.CdmOnRealCD(icon, C_Spell.GetSpellCooldown(shownSid[icon])) then
        sweeps[icon]:SetCooldown(start, dur)
    else
        sweeps[icon]:Clear()
    end
end

local function Listen(on)
    if on == listening then return end
    listening = on
    if on then
        ev:RegisterEvent("PLAYER_SWING")
    else
        ev:UnregisterEvent("PLAYER_SWING")
        wipe(swingStart)
        wipe(swingDur)
    end
end

ev:SetScript("OnEvent", function(_, _, dur, swing)
    if issecretvalue(dur) or issecretvalue(swing) or swing == nil then return end
    if type(dur) ~= "number" or dur ~= dur or dur <= 0 or dur == math.huge then return end
    local now = GetTime()
    swingStart[swing], swingDur[swing] = now, dur
    for icon, s in pairs(shownSwing) do
        if s == swing then
            -- A pooled frame can take another spell before the next reanchor.
            local fc = _ecmeFC[icon]
            local sid = fc and fc.spellID
            if not issecretvalue(sid) and sid == shownSid[icon] then
                Paint(icon, now)
            else
                sweeps[icon]:Clear()
            end
        end
    end
end)

-- After every reanchor, and from the menu: the icons that show the swipe now.
-- A swing already running is painted on the icons this pass placed.
function ns.CDM_SwingSweepSync()
    if not ns._cdmAnySwingSweep then return end
    wipe(seen)
    local now = GetTime()
    for barKey, list in pairs(cdmBarIcons) do
        local bd = barDataByKey[barKey]
        if bd and not bd.isGhostBar and not ns.IsBarBuffFamily(bd) then
            for i = 1, #list do
                local icon = list[i]
                local fc = icon and _ecmeFC[icon]
                local sid = fc and fc.spellID
                if type(sid) == "number" and not issecretvalue(sid) and sid > 0 then
                    local swing = SwingOf(sid)
                    if swing and Wants(icon, sid, barKey) then
                        seen[icon] = true
                        shownSid[icon], shownSwing[icon] = sid, swing
                        Style(icon, bd, barKey)
                        Paint(icon, now)
                    end
                end
            end
        end
    end
    for icon in pairs(shownSwing) do
        if not seen[icon] then
            shownSid[icon], shownSwing[icon] = nil, nil
            sweeps[icon]:Clear()
        end
    end
    Listen(next(shownSwing) ~= nil)
end

-- Swing Timer gate: set ns._cdmAnySwingSweep once if any saved spell (any
-- spec), bar tier or custom spell has the setting. Same monotonic,
-- scanned-once contract as the Stance Bar gate.
function ns.RescanSwingSweepFlag()
    if ns._cdmAnySwingSweep or scanned then return end
    if not EllesmereUIDB then return end
    scanned = true
    local function Has(ss)
        if rawget(ss, "showSwingTimer") then
            ns._cdmAnySwingSweep = true
            return true
        end
    end
    if ns.ForEachSavedSettingsBlock(Has) then return end
    local cas = ns.GetCustomActiveStates()
    if cas then
        for _, e in pairs(cas) do
            if type(e) == "table" and Has(e) then return end
        end
    end
end
