if EUI_CLIENT_BLOCKED then return end
-- Shared opt-in shield glow. Callers own settings, event registration and visibility.
local PP = EllesmereUI.PP
local Glow = {}
EllesmereUI.AbsorbGlow = Glow

-- Glow Line Texture art: { file, blend mode, width, width in whole pixels }.
Glow.art = {
    blizzard         = { "Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga", "ADD", 16 },
    pixelsGlow       = { "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\pixels-glowline.tga", "ADD", 16 },
    pixelsOvershield = { "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\pixels-overshield-line.tga", "BLEND", 2, true },
}
function Glow.Width(art)
    return art[4] and PP.Scale(art[3]) or art[3]
end

function Glow.Build(ab)
    local hp = ab._hpBar
    -- Own clip host above the shield bars: the health-side half of the line
    -- would otherwise be cut by the missing-health clip.
    local host = CreateFrame("Frame", nil, hp)
    host:SetAllPoints(hp)
    host:SetClipsChildren(true)
    host:SetFrameLevel(hp:GetFrameLevel() + 4)
    -- Each line sits on its own frame: boolean alpha works on frames (on a
    -- texture it renders nothing on this client).
    local edgeHost = CreateFrame("Frame", nil, host)
    edgeHost:SetAllPoints(host)
    -- Invisible gate bar on the edge: fed the absorb over a 0-1 range, its
    -- fill is full with ANY shield and empty without one, so the line drawn
    -- over the fill needs no boolean read of the secret amount.
    local gate = CreateFrame("StatusBar", nil, edgeHost)
    gate:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    gate:SetStatusBarColor(1, 1, 1, 0)
    gate:SetMinMaxValues(0, 1)
    gate:SetValue(0)
    local edge = edgeHost:CreateTexture(nil, "OVERLAY")
    edge:SetAllPoints(gate:GetStatusBarTexture())
    local bfHost = CreateFrame("Frame", nil, host)
    bfHost:SetAllPoints(host)
    local bf = bfHost:CreateTexture(nil, "OVERLAY")
    local g = { host = host, edgeHost = edgeHost, gate = gate, edge = edge, bfHost = bfHost, bf = bf }
    if CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction then
        local calc = CreateUnitHealPredictionCalculator()
        -- Configured once: the Missing Health clamp makes GetDamageAbsorbs'
        -- second return the overshield boolean (shield exceeds empty health).
        if calc.SetMaximumHealthMode and Enum.UnitMaximumHealthMode then
            calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
        end
        if calc.SetDamageAbsorbClampMode and Enum.UnitDamageAbsorbClampMode then
            calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)
        end
        g.calc = calc
    end
    ab._glow = g
    return g
end

-- Seats both lines for the stamped placement and fill direction. Runs from
-- the settings pass and after a retexture (a new shield fill object).
function Glow.Anchor(ab)
    local g = ab._glow
    if not (g and g.ge) then return end
    local rev = g.rev
    local near, far = rev and "RIGHT" or "LEFT", rev and "LEFT" or "RIGHT"
    local off = rev and 1 or -1
    local fill = ab:GetStatusBarTexture()
    local gate, bf = g.gate, g.bf
    gate:ClearAllPoints()
    if g.ge >= 3 then
        gate:SetPoint("CENTER", fill, near, off, 0)
    else
        gate:SetPoint("CENTER", ab._forward, near, off, 0)
    end
    bf:ClearAllPoints()
    if g.anc == 1 then
        bf:SetPoint("CENTER", fill, near, off, 0)
    elseif g.anc == 2 then
        bf:SetPoint("CENTER", fill, far, -off, 0)
    else
        bf:SetPoint("CENTER", ab, far, off, 0)
    end
end

-- The overshield flip. Placements 1-2: the seam line hides while
-- overshielding and the overshield line shows only then; 5: the line shows
-- only while the shield reaches current health. The boolean only ever
-- reaches SetAlphaFromBoolean.
function Glow.Flip(ab, unit)
    local g = ab._glow
    local ge = g.ge
    if ge == 3 then return end
    local eh, bh = g.edgeHost, g.bfHost
    local calc = g.calc
    if not (calc and eh.SetAlphaFromBoolean) then
        -- No calculator on this client: the seam line alone.
        eh:SetAlpha(ge == 5 and 0 or 1)
        bh:SetAlpha(0)
        return
    end
    UnitGetDetailedHealPrediction(unit, nil, calc)
    local _, clamped = calc:GetDamageAbsorbs()
    if ge == 5 then
        eh:SetAlphaFromBoolean(clamped, 1, 0)
    else
        eh:SetAlphaFromBoolean(clamped, 0, 1)
        bh:SetAlphaFromBoolean(clamped, 1, 0)
    end
end

-- Value pass, from the absorb painter while the line is on: the gate takes
-- the raw absorb, sizes follow the bar height and the pixel grid (a
-- whole-pixel width moves with it; size-gated), then the flip.
function Glow.Paint(ab, unit, absorbAmt, hpH)
    local g = ab._glow
    if g.szH ~= hpH or g.szM ~= PP.mult then
        g.szH, g.szM = hpH, PP.mult
        local w = Glow.Width(g.art)
        g.gate:SetSize(w, hpH)
        g.bf:SetSize(w, hpH)
    end
    g.gate:SetValue(absorbAmt)
    Glow.Flip(ab, unit)
end

