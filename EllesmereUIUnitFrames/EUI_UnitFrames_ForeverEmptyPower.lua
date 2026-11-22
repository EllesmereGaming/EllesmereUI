if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_ForeverEmptyPower.lua  (WoW Forever only; target and focus)
--
--  Hide Empty Power Bar (s.hideEmptyPower, opt-in): while the unit has no
--  power (its power maximum is 0) the attached power bar is hidden and the
--  health bar is drawn over its row. The frame keeps its size.
--
--  A unit's power maximum is SECRET for every unit the player does not
--  control, a 0 included, so nothing here reads it. It only feeds a gate: an
--  undrawn StatusBar with a 0-1 range laid over the health bar and the power
--  bar's row, whose fill is full with any power and empty with none (the
--  Absorb Short, absorb glow and combo point gates' technique). Riding that
--  fill:
--    bar clip  (the fill)        the power bar, its border and background
--    text clip (the fill)        the power text
--    seam clip (the fill)        the Power Bar Seam
--    gap clip  (past the fill)   a second, taller health bar: health + row
--    mask      (slides with the fill's end, as the combo gate's does)
--                                the health bar's own fill and background
--  With power the fill spans the bars: the clips on it clip nothing, the mask
--  covers the health bar and the gap clip is zero wide, so the frame draws as
--  it always has. Without power the fill is zero wide: the power bar and its
--  text are clipped away, the mask has slid off the health bar, and the gap
--  clip spans the bars, so the taller health bar is what draws: one fill, one
--  texture, over the whole height. The gate reaches past both ends of the
--  bar, so the sliver a fill can leave at a pixel boundary falls outside
--  anything that is drawn.
--
--  The taller health bar is a real health-like StatusBar: it takes the
--  frame's own painters (ApplyHealthBarTexture, ApplyHealthBarAlpha,
--  ApplyDarkTheme and the PostUpdateColor it installs), so every colour mode
--  matches the health bar by construction. Its value, bounds and flat colour
--  follow the health bar through hooks on that one bar. The health bar itself
--  is never resized, re-anchored or re-parented: its geometry stays plain,
--  and so do the absorb and layout passes that read it. Only its fill and
--  background stop drawing; its child overlays keep drawing over the taller
--  bar.
--
--  Not drawn into the row: the absorb and heal prediction overlays (they
--  keep the health bar's height), and the health text keeps its place.
--  Stands down (and puts everything back) with a detached or hidden power
--  bar, Power Bar Height 0, a vertical health fill, or a stock style.
--
--  Called from ReparentBarsToClip (the tail of every build and reload pass)
--  and from ApplyDarkTheme (the health bar's paint chokepoint).
--  Cost: off and never on = one settings test per layout pass, no frames, no
--  hooks. On: no events of its own; one SetValue per power bounds update and
--  one mirrored call per health update on that frame.
-------------------------------------------------------------------------------
local _, ns = ...
local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end

local I = ns._internals
local GetSettingsForUnit, UnsnapTex = I.GetSettingsForUnit, I.UnsnapTex

local WHITE = "Interface\\Buttons\\WHITE8X8"
-- How far the gate runs past each end of the power bar, and how far the two
-- fill clips reach above and below it: room for power text moved off the bar.
local GATE_REACH, CLIP_REACH = 400, 200
-- The mask's box: wider than any bar plus the gate's reach, so it covers the
-- health bar from the fill's full end and is clear of it from the empty end.
local MASK_SIZE = 4096

-- The option applies: on, an EllesmereUI-look target or focus frame, and an
-- attached power bar with a height beside a horizontal health fill.
local function Wanted(frame, s)
    if not (s and s.hideEmptyPower == true) then return false end
    local base = frame._euiBaseUnit
    if base ~= "target" and base ~= "focus" then return false end
    if ns.UF_Blizz() or s.healthVerticalFill then return false end
    local pos = ns.UF_PowerPos(s)
    if (pos ~= "below" and pos ~= "above") or (s.powerHeight or 6) <= 0 then return false end
    return (frame.Health and frame.Power and frame._barClip) and true or false
end

local function NewClip(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetClipsChildren(true)
    c:EnableMouse(false)
    return c
end

-- Built once per frame, on first enable.
local function Build(frame)
    local ep = {}
    local gate = CreateFrame("StatusBar", nil, frame)
    gate:SetStatusBarTexture(WHITE)
    gate:SetStatusBarColor(1, 1, 1, 0)  -- geometry only; never drawn
    gate:SetMinMaxValues(0, 1)
    gate:SetValue(1)                    -- "has power" until a unit feeds it
    local fill = gate:GetStatusBarTexture()
    if fill then UnsnapTex(fill) end
    ep.gate = gate
    ep.barClip = NewClip(frame._barClip)
    ep.textClip = NewClip(frame)
    ep.seamClip = NewClip(frame)
    ep.gapClip = NewClip(frame._barClip)
    -- The taller health bar, as CreateHealthBar builds the first.
    local m = CreateFrame("StatusBar", nil, ep.gapClip)
    m:SetStatusBarTexture(WHITE)
    m:GetStatusBarTexture():SetHorizTile(false)
    local bg = m:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(m)
    bg:SetColorTexture(0, 0, 0, 0.5)
    m.bg = bg
    ep.mirror = m
    frame._epParts = ep
    return ep
end

-- Hooks on this frame's own bars (installed once, on first enable; they read
-- one field and return while the option is off). Every argument goes straight
-- through to the same setter: values, bounds and colours may be secret.
local function MirrorValue(self, ...)
    local m = self._epMirror
    if m then m:SetValue(...) end
end
local function MirrorBounds(self, ...)
    local m = self._epMirror
    if m then m:SetMinMaxValues(...) end
end
local function MirrorColor(self, ...)
    local m = self._epMirror
    if m then m:SetStatusBarColor(...) end
end
-- The power painter's SetMinMaxValues(0, max): the max is all the gate needs.
local function FeedGate(self, _, max)
    local g = self._epGate
    if g then g:SetValue(max) end
end

-- The health bar's own fill and backgrounds draw only under the mask. A
-- texture swap replaces the fill object, so the mask is seated again on every
-- paint; off, it comes off whatever it was last on.
local function SeatMask(health, on)
    local mask = health._epMask
    if not mask then return end
    local list = health._epMasked
    if list then
        for i = #list, 1, -1 do
            pcall(list[i].RemoveMaskTexture, list[i], mask)
            list[i] = nil
        end
    end
    if not on then return end
    list = list or {}
    health._epMasked = list
    list[1] = health:GetStatusBarTexture()
    if health.bg then list[#list + 1] = health.bg end
    if health._euiBgTex then list[#list + 1] = health._euiBgTex end
    -- A texture takes at most three masks (rounded corners may hold some).
    for i = 1, #list do pcall(list[i].AddMaskTexture, list[i], mask) end
end

-- The power text overlay's level, as CreatePowerBar and UpdatePowerBorder
-- place it: clear of a shown power border, else frame + 15. SetParent resets
-- the level and UpdatePowerBorder re-derives it only while the bar has a
-- border (it returns early without one), so it is set again after each move.
-- A clip frame draws what it holds at its OWN level, so each clip also takes
-- the level of what it holds: left at the frame's level, the text drew under
-- the health bar's background.
local function SeatText(frame, power, clip)
    local ovr = power._ppTextOvr
    if not ovr then return end
    local border = power._pbBorder
    local level = (border and border:IsShown()) and (border:GetFrameLevel() + 5)
        or (frame:GetFrameLevel() + 15)
    if clip then clip:SetFrameLevel(level) end
    ovr:SetFrameStrata(power:GetFrameStrata())
    ovr:SetFrameLevel(level)
end

-- Paints the taller health bar as the health bar is painted and chains its
-- PostUpdateColor behind the health bar's (the main file's shared painter),
-- then seats the mask. From ApplyDarkTheme's tail (which has just installed a
-- fresh PostUpdateColor) and from each apply below.
function ns.UF_EmptyPowerPaint(health, unit)
    if not ns.UF_PaintHealthMirror(health, unit, "_epMirror", "_epChain") then return end
    SeatMask(health, true)
    -- A gradient built on the class / reaction colour exists only inside a
    -- real colour pass (PostUpdateColor's color argument): the engine repaint
    -- that closes every reload pass, and each new unit, runs one through the
    -- chain.
end

-- Puts the power bar, its text and its seam back where the frame keeps them.
local function Release(frame, ep, s)
    ep.on = false
    local power, health = frame.Power, frame.Health
    if health then
        health._epMirror = nil
        SeatMask(health, false)
    end
    if power then
        power._epHost, power._epGate = nil, nil
        -- ReparentBarsToClip has already moved an attached bar back to the
        -- bar clip; a bar that went detached is still in ours.
        if power:GetParent() == ep.barClip then
            local pos = s and ns.UF_PowerPos(s)
            local level = power:GetFrameLevel()
            power:SetParent((pos == "detached_top" or pos == "detached_bottom") and frame or frame._barClip)
            power:SetFrameLevel(level)
        end
        local ovr = power._ppTextOvr
        if ovr and ovr:GetParent() == ep.textClip then ovr:SetParent(frame) end
        -- Border and seam levels, and the seam's parent; then the text's.
        if s then ns.UpdatePowerBorder(power, s) end
        SeatText(frame, power)
    end
    ep.gate:Hide()
    ep.barClip:Hide()
    ep.textClip:Hide()
    ep.seamClip:Hide()
    ep.gapClip:Hide()
end

-- The tail of ReparentBarsToClip: the bars have their final parents, levels
-- and sizes. settings may be nil (read from the frame's unit then).
function ns.UF_EmptyPower(frame, s)
    local ep = frame._epParts
    s = s or GetSettingsForUnit(frame._euiBaseUnit)
    if not Wanted(frame, s) then
        if ep and ep.on then Release(frame, ep, s) end
        return
    end
    ep = ep or Build(frame)
    local health, power, clip = frame.Health, frame.Power, frame._barClip
    if not health._epHooked then
        health._epHooked = true
        hooksecurefunc(health, "SetValue", MirrorValue)
        hooksecurefunc(health, "SetMinMaxValues", MirrorBounds)
        hooksecurefunc(health, "SetStatusBarColor", MirrorColor)
    end
    if not power._epHooked then
        power._epHooked = true
        hooksecurefunc(power, "SetMinMaxValues", FeedGate)
    end

    -- 1) The gate over health + power row, shown and valued before anything
    --    is anchored to its fill.
    local above = ns.UF_PowerPos(s) == "above"
    local top, bottom = above and power or health, above and health or power
    local gate = ep.gate
    local fill = gate:GetStatusBarTexture()
    gate:ClearAllPoints()
    gate:SetPoint("TOPLEFT", top, "TOPLEFT", -GATE_REACH, 0)
    gate:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", GATE_REACH, 0)
    gate:Show()
    local _, powerMax = power:GetMinMaxValues()
    gate:SetValue(powerMax)

    -- 2) The clips on the fill. Each takes the level of what it holds (see
    --    SeatText).
    local barClip, textClip, seamClip, gapClip = ep.barClip, ep.textClip, ep.seamClip, ep.gapClip
    local fillClips = ep.fillClips
    if not fillClips then
        fillClips = { barClip, textClip, seamClip }
        ep.fillClips = fillClips
    end
    for i = 1, #fillClips do
        local c = fillClips[i]
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, CLIP_REACH)
        c:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, -CLIP_REACH)
        c:Show()
    end
    gapClip:ClearAllPoints()
    gapClip:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    gapClip:SetPoint("BOTTOMRIGHT", gate, "BOTTOMRIGHT", 0, 0)
    gapClip:SetFrameLevel(health:GetFrameLevel())
    gapClip:Show()

    -- 3) The power bar, its text and its seam under the fill clips. SetParent
    --    resets the frame level; UpdatePowerBorder re-derives the border's
    --    and the seam's.
    local powerLevel = power:GetFrameLevel()
    barClip:SetFrameLevel(powerLevel)
    if power:GetParent() ~= barClip then power:SetParent(barClip) end
    power:SetFrameLevel(powerLevel)
    local ovr = power._ppTextOvr
    if ovr and ovr:GetParent() ~= textClip then ovr:SetParent(textClip) end
    power._epHost, power._epGate = seamClip, gate
    ns.UpdatePowerBorder(power, s)
    SeatText(frame, power, textClip)
    local seam = power._pbSeam
    if seam and seam:GetParent() == seamClip then
        local level = seam:GetFrameLevel()
        seamClip:SetFrameLevel(level)
        seam:SetFrameLevel(level)
    end

    -- 4) The mask for the health bar's own fill: a box whose end rides the
    --    fill's end (seated on the textures by the paint below).
    local mask = health._epMask
    if not mask then
        mask = health:CreateMaskTexture()
        mask:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
        mask:SetSize(MASK_SIZE, MASK_SIZE)
        health._epMask = mask
    end
    mask:ClearAllPoints()
    mask:SetPoint("RIGHT", fill, "RIGHT", 0, 0)

    -- 5) The taller health bar over health + power row, under the gap clip.
    local m = ep.mirror
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", top, "TOPLEFT", 0, 0)
    m:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", 0, 0)
    m:SetFrameLevel(health:GetFrameLevel())
    m:SetMinMaxValues(health:GetMinMaxValues())
    m:SetValue(health:GetValue())
    m:Show()
    health._epMirror = m
    ep.on = true
    ns.UF_EmptyPowerPaint(health, frame._euiUnit)
end
