if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_ForeverSwingSweep.lua -- WoW FOREVER ONLY: the Swing Timer swipe.
--
--  On-next-swing attacks (EllesmereUI.FOREVER_NEXT_SWING: Heroic Strike,
--  Cleave, Maul, Raptor Strike) show no cooldown while they wait for the swing
--  (Raptor Strike has one of its own, which its icon's own swipe shows). Per
--  spell (showSwingTimer, off by default) the icon shows the weapon swing the
--  attack rides instead: each swing of that hand starts a swipe for the
--  swing's duration, as the Resource Bars swing timer starts its row
--  (EUI_ResourceBars_SwingTimer.lua). The attack lookup is the parent's
--  (EllesmereUI.ForeverNextSwingOf), the swings the module's one source
--  (ns.CDM_Swing, EUI_CDM_ForeverSwing.lua).
--
--  The swipe is a Cooldown of our own over the icon, never the icon's: the
--  viewer rewrites that one on every cooldown event, and a real cooldown keeps
--  it. The engine animates it; Lua runs at a swing's start and after a
--  reanchor (ns.CDM_SwingSweepSync, nil-guarded at its callers), which dresses
--  an icon again only when one of its style inputs moved and sets the swipe
--  only when it changes.
--
--  Cost: nothing until some saved spell has the setting. ns._cdmAnySwingSweep
--  is set once by ns.RescanSwingSweepFlag at setup, or by the menu on first
--  use (monotonic, like the other per-spell gates). The swing source is
--  watched only while an icon on the bars shows the swipe.
-------------------------------------------------------------------------------
local _, ns = ...

-- The swing API is the Forever client's; a class with no such attack has
-- nothing to show. Neither the menu rows nor the gate exist past this point.
local Swing = ns.CDM_Swing
if not Swing or EllesmereUI.ForeverNextSwingNames() == false then return end

local GetTime = GetTime
local SwingOf = EllesmereUI.ForeverNextSwingOf
local IsSecret = EllesmereUI.IsSecret
local cdmBarIcons, barDataByKey, _ecmeFC = ns.cdmBarIcons, ns.barDataByKey, ns._ecmeFC
local I = ns._hookInternals

local sweeps = setmetatable({}, { __mode = "k" })   -- [icon] = our Cooldown over it
local stamps = setmetatable({}, { __mode = "k" })   -- [icon] = the style inputs it was dressed with
local armed = setmetatable({}, { __mode = "k" })    -- [icon] = the swing start the swipe was set for
local shownSid, shownSwing, shownCd = {}, {}, {}    -- [icon] = its spell / swing / cooldownID (false: unknown)
local seen = {}
local watching = false
local scanned = false

-- The menu shows its row for these spells only.
function ns.CDM_IsSwingSweepSpell(sid)
    return SwingOf(sid) ~= false
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

-- The icon's plain cooldownID, false while it has none or it reads secret.
local function CdOf(icon)
    local id = icon.cooldownID
    if type(id) == "number" and not IsSecret(id) then return id end
    return false
end

-- Our Cooldown, dressed as the icon's own: its level, the bar's swipe and
-- edge, the spell's Reverse Swipe and the icon's shape. Dressed again only
-- when one of those inputs moved (the stamp names every one of them; the
-- swipe file follows the icon style, latched for the session).
local function Style(icon, bd, barKey)
    local cd = sweeps[icon]
    if not cd then
        cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:SetDrawBling(false)
        cd:SetHideCountdownNumbers(true)
        cd:EnableMouse(false)
        sweeps[icon] = cd
        stamps[icon] = {}
    end
    local own = icon.Cooldown or icon._cooldown
    local level = own and own:GetFrameLevel() or (icon:GetFrameLevel() + 1)
    local alpha = bd.swipeAlpha or 0.7
    local reverse = ns.EffectiveReverseSwipe(icon, barKey, false) and true or false
    local fc = _ecmeFC[icon]
    local mask = fc and fc.shapeMask or false
    local applied = (fc and fc.shapeApplied) and true or false
    local shapeName = fc and fc.shapeName or false
    local edge = bd.showCooldownEdge and true or false
    local barShape = bd.iconShape or false
    local st = stamps[icon]
    if st.barKey == barKey and st.level == level and st.alpha == alpha and st.reverse == reverse
       and st.mask == mask and st.applied == applied and st.shapeName == shapeName
       and st.edge == edge and st.barShape == barShape then
        return
    end
    st.barKey, st.level, st.alpha, st.reverse = barKey, level, alpha, reverse
    st.mask, st.applied, st.shapeName, st.edge, st.barShape = mask, applied, shapeName, edge, barShape
    cd:SetFrameLevel(level)
    cd:SetSwipeColor(0, 0, 0, alpha)
    cd:SetReverse(reverse)
    ns.ApplyShapeToOverlay(icon, nil, cd, bd)
    if not applied then cd:SetSwipeTexture(ns.CdmSwipeFile()) end
    if edge and I and I.ApplyCdmEdge then
        I.ApplyCdmEdge(cd, barKey)
    else
        cd:SetDrawEdge(false)
    end
end

-- The running swing on one icon, or nothing: none running, or the spell is on
-- a cooldown of its own, which the icon's own swipe shows. The swipe is set
-- or cleared only when that changes.
local function Paint(icon, now)
    local start, d = Swing.Last(shownSwing[icon])
    if start and now < start + d
       and not ns.CdmOnRealCD(icon, C_Spell.GetSpellCooldown(shownSid[icon])) then
        if armed[icon] ~= start then
            armed[icon] = start
            sweeps[icon]:SetCooldown(start, d)
        end
    elseif armed[icon] then
        armed[icon] = nil
        sweeps[icon]:Clear()
    end
end

local function Drop(icon)
    shownSid[icon], shownSwing[icon], shownCd[icon] = nil, nil, nil
    if armed[icon] then
        armed[icon] = nil
        sweeps[icon]:Clear()
    end
end

-- A swing started: paint the icons that ride it. A pooled frame can take
-- another cooldown before the next reanchor; its cooldownID tells.
local function OnSwing(swing, now)
    for icon, s in pairs(shownSwing) do
        if s == swing then
            local was = shownCd[icon]
            local cur = CdOf(icon)
            if was and cur and cur ~= was then
                if armed[icon] then
                    armed[icon] = nil
                    sweeps[icon]:Clear()
                end
            else
                Paint(icon, now)
            end
        end
    end
end

local function Watch(on)
    if on == watching then return end
    watching = on
    if on then Swing.Watch("sweep", OnSwing) else Swing.Unwatch("sweep") end
end

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
                local swing = SwingOf(sid)
                if swing and Wants(icon, sid, barKey) then
                    seen[icon] = true
                    shownSid[icon], shownSwing[icon], shownCd[icon] = sid, swing, CdOf(icon)
                    Style(icon, bd, barKey)
                    Paint(icon, now)
                end
            end
        end
    end
    for icon in pairs(shownSwing) do
        if not seen[icon] then Drop(icon) end
    end
    Watch(next(shownSwing) ~= nil)
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
