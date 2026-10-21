if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Shared dot art and passive connection endpoints. Nothing is built until used.
local _, ns = ...
ns = ns.__euiCoreNS or ns
local visuals = {}
ns.PointVisuals = visuals
local DOT_FILL = "Interface\\AddOns\\EllesmereUI\\media\\basics\\point_anchor_fill.tga"
local DOT_BORDER = "Interface\\AddOns\\EllesmereUI\\media\\basics\\point_anchor_border.tga"
visuals.idleSize, visuals.hoverSize = 8, 12
local defaults = { point = {1, 1, 1, 1}, border = {0, 0, 0, 1}, line = {1, 0.2, 0.2, 1} }
local dots

function EllesmereUI.GetPointAnchorColor(kind)
    local colors = EllesmereUIDB and EllesmereUIDB.unlockPointColors
    local color = colors and colors[kind] or defaults[kind]
    return unpack(color)
end

function visuals.ColorDot(art, alpha)
    art.colorAlpha = alpha
    local r, g, b, a = EllesmereUI.GetPointAnchorColor("point")
    art.fill:SetVertexColor(r, g, b, a * alpha)
    r, g, b, a = EllesmereUI.GetPointAnchorColor("border")
    art.border:SetVertexColor(r, g, b, a * alpha)
end

function EllesmereUI.SetPointAnchorColor(kind, r, g, b, a)
    if not defaults[kind] then return end
    EllesmereUIDB = EllesmereUIDB or {}
    EllesmereUIDB.unlockPointColors = EllesmereUIDB.unlockPointColors or {}
    EllesmereUIDB.unlockPointColors[kind] = {r, g, b, a}
    if dots and kind ~= "line" then
        for i = 1, #dots do visuals.ColorDot(dots[i], dots[i].colorAlpha) end
    end
end

function visuals.SizeDot(art, size)
    local pp = EllesmereUI.PP
    local px = ((pp and pp.perfect) or 1) / art:GetEffectiveScale()
    if art.dotSize == size and art.pixelSize == px then return end
    art.dotSize, art.pixelSize = size, px
    art:SetSize(size, size)
    -- Matched cells prefilter both edges at their displayed pixel size.
    local diameter = math.max(1, math.min(16, math.floor(size / px + 0.5)))
    local cell = diameter - 1
    local x, y = (cell % 4) * 64, math.floor(cell / 4) * 64
    local padded = size * (diameter + 2) / diameter
    art.fill:SetSize(padded, padded)
    art.border:SetSize(padded, padded)
    art.fill:SetTexCoord(x / 256, (x + 64) / 256, y / 256, (y + 64) / 256)
    art.border:SetTexCoord(x / 256, (x + 64) / 256, y / 256, (y + 64) / 256)
end

function visuals.CreateDot(parent)
    local art = CreateFrame("Frame", nil, parent)
    art:EnableMouse(false)
    local border = art:CreateTexture(nil, "OVERLAY")
    border:SetPoint("CENTER", art, "CENTER")
    border:SetTexture(DOT_BORDER, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
    border:SetSnapToPixelGrid(false)
    border:SetTexelSnappingBias(0)
    local fill = art:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("CENTER", art, "CENTER")
    fill:SetTexture(DOT_FILL, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
    fill:SetSnapToPixelGrid(false)
    fill:SetTexelSnappingBias(0)
    art.fill, art.border = fill, border
    visuals.ColorDot(art, 1)
    dots = dots or {}
    dots[#dots + 1] = art
    return art
end

function visuals.RaiseAboveMover(frame, mover)
    local level = mover:GetFrameLevel()
    if mover._raisedLevel then level = math.max(level, mover._raisedLevel + 100) end
    if mover._cogBtn then level = math.max(level, mover._cogBtn:GetFrameLevel()) end
    level = level + 30
    if frame:GetFrameLevel() == level then return end
    -- Fixed frames ignore SetFrameLevel until their level is unlocked.
    frame:SetFixedFrameLevel(false)
    frame:SetFrameLevel(level)
    frame:SetFixedFrameLevel(true)
end

local markers
local function ShowPoint(index, mover, point, alpha)
    local marker = markers[index]
    if not marker then
        marker = visuals.CreateDot(mover)
        markers[index] = marker
    end
    if marker:GetParent() ~= mover then marker:SetParent(mover) end
    visuals.RaiseAboveMover(marker, mover)
    if marker.point ~= point or marker.mover ~= mover then
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", mover, point)
        marker.point, marker.mover = point, mover
    end
    local pp = EllesmereUI.PP
    local size = visuals.idleSize * ((pp and pp.perfect) or 1) / marker:GetEffectiveScale()
    visuals.SizeDot(marker, size)
    marker:SetAlpha(alpha)
    marker:Show()
end

function visuals.Connection(index, source, sourcePoint, target, targetPoint, alpha)
    markers = markers or {}
    ShowPoint(index * 2 - 1, source, sourcePoint, alpha)
    ShowPoint(index * 2, target, targetPoint, alpha)
end

function visuals.TrimConnections(count)
    if not markers then return end
    for i = count * 2 + 1, #markers do markers[i]:Hide() end
end
