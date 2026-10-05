if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_ForeverExtras.lua
--
--  WoW Forever extras on the unit frames: the pet happiness icon beside the
--  pet frame and the combo point arc round the target portrait. Both apply
--  functions return at once off WoW Forever. Reads the main file through ns
--  and ns._internals; db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, ns = ...

local issecretvalue = issecretvalue

local I = ns._internals
local frames = I.frames
local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-- Pet happiness (WoW Forever): the stock pet frame's mood icon, carried
-- beside our pet frame under Blizzard's own rule -- shown only for a hunter
-- pet whose happiness reads 1..3, with that state's atlas. The icon frame is
-- also the event receiver; it is built the first time the feature is on for
-- a hunter and drops every event while off, so it costs nothing otherwise.
function ns.UF_RefreshPetHappiness(h)
    local happiness = C_PetInfo.GetPetHappiness()
    local _, isHunterPet = HasPetUI()
    local atlas = isHunterPet and ((happiness == 1 and "UI-PetMad")
        or (happiness == 2 and "UI-PetNeutral")
        or (happiness == 3 and "UI-PetHappiness")) or nil
    if atlas then
        -- Paint only a real mood change (the texture is set nowhere else).
        if h._atlas ~= atlas then
            h._atlas = atlas
            h._tex:SetAtlas(atlas)
        end
        h:Show()
    else
        h:Hide()
    end
end

-- Hover text, read fresh: state, damage share, loyalty trend and diet.
function ns.UF_PetHappinessOnEnter(self)
    -- Faded out with its frame (the pet mirrors the player frame's alpha and
    -- mouseover mode rests at 0): an unseen icon shows no tooltip.
    local a = self:GetEffectiveAlpha()
    if not issecretvalue(a) and a < 0.05 then return end
    local happiness, dmg, loyalty = C_PetInfo.GetPetHappiness()
    local text = (happiness == 1 and PET_HAPPINESS1) or (happiness == 2 and PET_HAPPINESS2)
        or (happiness == 3 and PET_HAPPINESS3)
    if not text then return end
    if dmg then text = text .. "\n" .. PET_DAMAGE_PERCENTAGE:format(dmg) end
    if loyalty and loyalty < 0 then
        text = text .. "\n" .. LOSING_LOYALTY
    elseif loyalty and loyalty > 0 then
        text = text .. "\n" .. GAINING_LOYALTY
    end
    local diet = C_PetInfo.GetPetFoodTypes()
    if diet and #diet > 0 then
        text = text .. "\n" .. PET_DIET_TEMPLATE:format(table.concat(diet, PET_FOOD_DELIMIT))
    end
    EllesmereUI.ShowWidgetTooltip(self, text)
end

function ns.UF_PetHappinessOnLeave()
    EllesmereUI.HideWidgetTooltip()
end

-- Settings apply: builds the icon on first use, re-seats size, side and
-- offsets, and arms or drops its events. Every reload pass runs it (the
-- options setters reach it through ReloadAndUpdate) and it is safe to call
-- directly; it returns at once off WoW Forever.
function ns.UF_ApplyPetHappiness()
    if EllesmereUI.IS_FOREVER ~= true then return end
    local pf = frames.pet
    local s = db.profile.pet
    local h = pf and pf._petHappy
    -- Only hunter pets carry happiness: every other class never builds it.
    local on = pf and s and s.happinessEnabled ~= false
        and not ns.VisUnitDisabled(db.profile, "pet")
        and select(2, UnitClass("player")) == "HUNTER"
    if not on then
        if h then
            h:UnregisterAllEvents()
            h:Hide()
        end
        return
    end
    if not h then
        h = CreateFrame("Frame", nil, pf)
        -- Hover only: clicks fall through to the unit button underneath.
        h:EnableMouseMotion(true)
        h._tex = h:CreateTexture(nil, "OVERLAY")
        h._tex:SetAllPoints()
        h:SetScript("OnEvent", ns.UF_RefreshPetHappiness)
        h:SetScript("OnEnter", ns.UF_PetHappinessOnEnter)
        h:SetScript("OnLeave", ns.UF_PetHappinessOnLeave)
        h:Hide()
        pf._petHappy = h
    end
    local sz = s.happinessSize or 20
    local align = s.happinessAlign or "right"
    local x, y = s.happinessX or 0, s.happinessY or 0
    h:SetSize(sz, sz)
    h:ClearAllPoints()
    if align == "left" then
        h:SetPoint("RIGHT", pf, "LEFT", x, y)
    elseif align == "top" then
        h:SetPoint("BOTTOM", pf, "TOP", x, y)
    else
        h:SetPoint("LEFT", pf, "RIGHT", x, y)
    end
    -- Above the border and the name/health text (the strata pass re-stacks).
    if pf._textOverlay then h:SetFrameLevel(pf._textOverlay:GetFrameLevel() + 5) end
    h:RegisterUnitEvent("UNIT_HAPPINESS", "pet")
    h:RegisterUnitEvent("UNIT_PET", "player")
    -- The pet's state may not read yet at login: the zone-in edge repaints.
    h:RegisterEvent("PLAYER_ENTERING_WORLD")
    ns.UF_RefreshPetHappiness(h)
end

-- Combo point arc (WoW Forever style): the stock target frame's combo points,
-- the vanilla pip file plotted in an arc round the portrait, drawn as the
-- "Blizzard" class resource under that look (Forever has no other class
-- resource display). Built on our target frame for a rogue or druid; its
-- events arrive through one receiver born in this main chunk (so they bill
-- to this module), which drops every event while the arc is off, so it costs
-- nothing otherwise. The count can read secret, so visibility never compares
-- it in Lua: each pip rides a one-point StatusBar gate (SetMinMaxValues(i-1,
-- i) + SetValue does the compare C-side) whose mask, pinned to the fill's
-- right edge, bounds the pip's textures, and a one-point gate over the whole
-- arc hides it while empty. A plain count also plays the stock fill flash.
ns.UF_COMBO_FILE = "Interface\\ComboFrame\\ComboPoint"
-- Each slot's TOPRIGHT from the target box's TOPRIGHT (the stock container
-- offset folded in); slots 7-9 are the extra points, at 0.6 alpha.
ns.UF_COMBO_SLOTS = {
    { -65, -6 }, { -52.5, -5 }, { -40, -6 }, { -28.5, -11.5 }, { -19.5, -20 },
    { -14, -31.5 }, { -12, -43 }, { -14, -54 }, { -2, -46 },
}
-- A w x h gate and its mask: the mask is the gate's size and rides the fill's
-- right edge, so an empty fill parks it a full width clear of the payload.
function ns.UF_ComboGate(parent, w, h)
    local g = CreateFrame("StatusBar", nil, parent)
    g:SetSize(w, h)
    g:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local fill = g:GetStatusBarTexture()
    fill:SetAlpha(0)
    g:SetMinMaxValues(0, 1)
    g:SetValue(0)
    local m = g:CreateMaskTexture()
    m:SetTexture("Interface\\Buttons\\WHITE8x8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    m:SetSize(w, h)
    m:SetPoint("RIGHT", fill, "RIGHT", 0, 0)
    return g, m
end
function ns.UF_BuildComboArc(tf)
    local arc = CreateFrame("Frame", nil, tf)
    -- Spans every slot's textures (the arc gate's payload).
    arc:SetSize(82, 72)
    arc._gate, arc._mask = ns.UF_ComboGate(arc, 82, 72)
    arc._gate:SetPoint("TOPLEFT", arc, "TOPLEFT", 0, 0)
    local file = ns.UF_COMBO_FILE
    local pips, gates = {}, {}
    for k = 1, 9 do
        local pip = CreateFrame("Frame", nil, arc)
        pip:SetSize(12, 12)
        if k >= 7 then pip:SetAlpha(0.6) end
        local base = pip:CreateTexture(nil, "BACKGROUND")
        base:SetTexture(file)
        base:SetTexCoord(0, 0.375, 0, 1)
        base:SetSize(12, 16)
        base:SetPoint("TOPLEFT", pip, "TOPLEFT", 0, 0)
        local hl = pip:CreateTexture(nil, "ARTWORK")
        hl:SetTexture(file)
        hl:SetTexCoord(0.375, 0.5625, 0, 1)
        hl:SetSize(8, 16)
        hl:SetPoint("TOPLEFT", pip, "TOPLEFT", 2, 0)
        hl:SetAlpha(0)
        local shine = pip:CreateTexture(nil, "OVERLAY")
        shine:SetTexture(file)
        shine:SetTexCoord(0.5625, 1, 0, 1)
        shine:SetSize(14, 16)
        shine:SetPoint("TOPLEFT", pip, "TOPLEFT", 0, 4)
        shine:SetBlendMode("ADD")
        shine:SetAlpha(0)
        -- The pip's own gate spans its three textures (the shine rides 4 up).
        local g, m = ns.UF_ComboGate(pip, 14, 20)
        g:SetPoint("TOPLEFT", pip, "TOPLEFT", 0, 4)
        hl:AddMaskTexture(m)
        shine:AddMaskTexture(m)
        -- A newly filled point: the highlight fades in, then the shine flashes.
        local ag = pip:CreateAnimationGroup()
        ag:SetToFinalAlpha(true)
        local a = ag:CreateAnimation("Alpha")
        a:SetTarget(hl); a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.4); a:SetOrder(1)
        a = ag:CreateAnimation("Alpha")
        a:SetTarget(shine); a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.3); a:SetOrder(2)
        a = ag:CreateAnimation("Alpha")
        a:SetTarget(shine); a:SetFromAlpha(1); a:SetToAlpha(0); a:SetDuration(0.4); a:SetOrder(3)
        pip._base, pip._hl, pip._shine, pip._mask, pip._anim = base, hl, shine, m, ag
        pips[k], gates[k] = pip, g
    end
    arc._pips, arc._gates = pips, gates
    -- The arc fades in when its first point lands.
    local fade = arc:CreateAnimationGroup()
    fade:SetToFinalAlpha(true)
    local fa = fade:CreateAnimation("Alpha")
    fa:SetFromAlpha(0); fa:SetToAlpha(1); fa:SetDuration(0.3)
    arc._fade = fade
    tf._foreverCombo = arc
    return arc
end
-- The arc's event receiver (the Forever client only; armed by
-- ns.UF_ApplyForeverComboArc).
if EllesmereUI.IS_FOREVER == true then
    ns._ufComboEv = CreateFrame("Frame")
    ns._ufComboEv:SetScript("OnEvent", function(_, ...)
        local tf = frames.target
        local arc = tf and tf._foreverCombo
        if arc then ns.UF_ComboArcRefresh(arc, ...) end
    end)
end
-- Which slots the arc uses (from the point cap, as the stock frame lays it
-- out) and which empty pips show with the arc; re-run only on a cap or
-- colourblind change. A secret cap keeps the last layout.
function ns.UF_ComboArcLayout(arc)
    local mx = UnitPowerMax("player", Enum.PowerType.ComboPoints)
    if issecretvalue(mx) then
        if arc._max then return end
        mx = 5
    end
    if not mx or mx <= 0 then mx = 5 end
    local cb = C_CVar.GetCVarBool("colorblindMode") and true or false
    if arc._max == mx and arc._cb == cb then return end
    -- A cap of 6 or 9 starts on the first slot with six in the arc; any other
    -- starts one slot in with five. Points past those show only while filled.
    local start, extra = 2, 6
    if mx == 6 or mx == 9 then start, extra = 1, 7 end
    arc._max, arc._start, arc._cb = mx, start, cb
    local pips, gates = arc._pips, arc._gates
    for k = 1, 9 do
        local pip = pips[k]
        local i = k - start + 1
        if i >= 1 and i <= mx then
            gates[k]:SetMinMaxValues(i - 1, i)
            -- The empty pip shows with the arc, or only while filled (the
            -- extra points; every point in colourblind mode).
            local want = (cb or i >= extra) and pip._mask or arc._mask
            if pip._baseMask ~= want then
                if pip._baseMask then pip._base:RemoveMaskTexture(pip._baseMask) end
                pip._base:AddMaskTexture(want)
                pip._baseMask = want
            end
            pip:Show()
        else
            pip:Hide()
        end
    end
end
function ns.UF_ComboArcRefresh(arc, event, _, powerType)
    if event == "UNIT_POWER_UPDATE" and powerType ~= "COMBO_POINTS" then return end
    if arc._cb == nil or event == "UNIT_MAXPOWER" or event == "PLAYER_ENTERING_WORLD" then
        ns.UF_ComboArcLayout(arc)
    end
    -- The target's count (the stock frame's read: the power value lags a
    -- target swap). Fed to every gate as it comes, secret or not.
    local n = GetComboPoints("player", "target")
    arc._gate:SetValue(n)
    local gates, pips = arc._gates, arc._pips
    for k = 1, 9 do gates[k]:SetValue(n) end
    if issecretvalue(n) then
        -- No compare: the gates alone show the filled points, at full
        -- highlight, with no flash.
        if not arc._secret then
            arc._secret = true
            arc._fade:Stop()
            arc:SetAlpha(1)
            for k = 1, 9 do
                local pip = pips[k]
                pip._anim:Stop()
                pip._hl:SetAlpha(1)
                pip._shine:SetAlpha(0)
            end
        end
        return
    end
    -- Back from a secret stretch: settle on the count without replaying it.
    local last = arc._secret and n or (arc._last or 0)
    arc._secret = nil
    arc._last = n
    if n > 0 and last == 0 then
        arc._fade:Stop()
        arc._fade:Play()
    end
    local start = arc._start
    for i = 1, arc._max do
        local pip = pips[start + i - 1]
        if not pip then break end
        if i > n then
            pip._anim:Stop()
            pip._hl:SetAlpha(0)
            pip._shine:SetAlpha(0)
        elseif i > last then
            pip._anim:Stop()
            pip._hl:SetAlpha(0)
            pip._shine:SetAlpha(0)
            pip._anim:Play()
        end
    end
end
-- Settings apply: on only under the WoW Forever style with the "Blizzard"
-- class resource, for a rogue or druid with our target frame; builds the arc
-- on first use, places it round the portrait (mirrored onto a portrait on the
-- left) and arms its events, else drops them. Every reload pass and the class
-- resource toggle run it; it returns at once off that style.
function ns.UF_ApplyForeverComboArc()
    if EllesmereUI.IS_FOREVER ~= true then return end
    local tf = frames.target
    local arc = tf and tf._foreverCombo
    local ev = ns._ufComboEv
    local on = tf and ns.UF_Forever()
        and db.profile.player.classPowerStyle == "blizzard"
    if on then
        local _, cls = UnitClass("player")
        on = cls == "ROGUE" or cls == "DRUID"
    end
    if not on then
        ev:UnregisterAllEvents()
        if arc then arc:Hide() end
        return
    end
    arc = arc or ns.UF_BuildComboArc(tf)
    local G = ns.UF_BlizzGeom(tf)
    local mirror = (G and G.side == "left") or nil
    arc:ClearAllPoints()
    ns.UF_BlizzPoint(arc, "TOPRIGHT", tf, "TOPRIGHT", 2, 0, mirror)
    local slots, pips = ns.UF_COMBO_SLOTS, arc._pips
    for k = 1, 9 do
        pips[k]:ClearAllPoints()
        ns.UF_BlizzPoint(pips[k], "TOPRIGHT", tf, "TOPRIGHT", slots[k][1], slots[k][2], mirror)
    end
    -- Over the art, portrait and bars, beside the level badge.
    local clip = tf._barClip
    arc:SetFrameStrata((clip and clip:GetFrameStrata()) or tf:GetFrameStrata())
    arc:SetFrameLevel(((clip and clip:GetFrameLevel()) or tf:GetFrameLevel()) + 12)
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    ev:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    -- Re-lay the slots (a colourblind change has no event of its own).
    arc._cb = nil
    arc:Show()
    ns.UF_ComboArcRefresh(arc)
end
