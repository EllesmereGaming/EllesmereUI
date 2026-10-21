if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Explicit point relationships. Legacy side anchors keep their existing math.
local _, ns = ...
ns = ns.__euiCoreNS or ns
local PA = {}
ns.PointAnchors = PA

local POINTS = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
PA.order = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

function PA.Description(info)
    local labels = { TOPLEFT = "Top Left", TOP = "Top", TOPRIGHT = "Top Right", LEFT = "Left",
        CENTER = "Center", RIGHT = "Right", BOTTOMLEFT = "Bottom Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom Right" }
    return EllesmereUI.Lf("Point: %1$s to %2$s", EllesmereUI.L(labels[info.sourcePoint] or "?"),
        EllesmereUI.L(labels[info.targetPoint] or "?"))
end

local function Number(v)
    return not (issecretvalue and issecretvalue(v)) and type(v) == "number"
        and v == v and v > -math.huge and v < math.huge
end

function PA.Is(info)
    return type(info) == "table" and info.mode == "POINT"
end

function PA.Valid(info)
    return PA.Is(info) and type(info.target) == "string"
        and POINTS[info.sourcePoint] ~= nil and POINTS[info.targetPoint] ~= nil
        and Number(info.offsetX) and Number(info.offsetY)
end

function EllesmereUI.GetUnlockAnchorSide(info)
    if not PA.Is(info) then return info and info.side end
    if not PA.Valid(info) then return end
    local s, t = POINTS[info.sourcePoint], POINTS[info.targetPoint]
    if not s or not t then return end
    if s[1] == t[1] then
        if s[2] == 0 and t[2] == 1 then return "TOP" end
        if s[2] == 1 and t[2] == 0 then return "BOTTOM" end
    end
    if s[2] == t[2] then
        if s[1] == 0 and t[1] == 1 then return "RIGHT" end
        if s[1] == 1 and t[1] == 0 then return "LEFT" end
    end
end

function EllesmereUI.IsPointAnchored(key)
    local db = EllesmereUIDB and EllesmereUIDB.unlockAnchors
    return db and PA.Is(db[key]) or false
end

function EllesmereUI.SetPointAnchorHandles(enabled)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    EllesmereUIDB.unlockPointHandles = enabled and true or nil
    if not enabled and PA.cancelPicker then PA.cancelPicker() end
end

function PA.Frame(key)
    local elem = EllesmereUI._unlockRegisteredElements[key]
    return elem and elem.getFrame and elem.getFrame(key)
end

local function Insets(key, frame)
    local elem = EllesmereUI._unlockRegisteredElements[key]
    local l, r, t, b = 0, 0, 0, 0
    if elem and elem.getInsets then
        l, r, t, b = elem.getInsets(key)
        l, r, t, b = l or 0, r or 0, t or 0, b or 0
    end
    local extra = elem and elem.getBottomExtra and elem.getBottomExtra(key) or 0
    if not (Number(l) and Number(r) and Number(t) and Number(b) and Number(extra)) then return end
    return l, r, t, b - extra
end

local function Bounds(frame)
    return frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom(), frame:GetEffectiveScale()
end

local function Dimensions(frame)
    return frame:GetWidth(), frame:GetHeight(), frame:GetEffectiveScale()
end

local function Extent(key, side, fallback)
    local ok, value = pcall(EllesmereUI._GetAnchorTargetExtent, key, side)
    if not ok then return end
    if issecretvalue and issecretvalue(value) then return end
    if value == nil then return fallback end
    if Number(value) then return value end
end

function PA.Rect(key, frame, target)
    if not frame then return end
    local ok, l, r, t, b, scale = pcall(Bounds, frame)
    if not ok or not (Number(l) and Number(r) and Number(t) and Number(b)
        and Number(scale) and scale > 0) then return end
    local safe, il, ir, it, ib = pcall(Insets, key, frame)
    if not safe or not il then return end
    local ratio = scale / UIParent:GetEffectiveScale()
    l, r, t, b = (l + il) * ratio, (r - ir) * ratio, (t - it) * ratio, (b + ib) * ratio
    if target and EllesmereUI._GetAnchorTargetExtent then
        l, r = Extent(key, "LEFT", l), Extent(key, "RIGHT", r)
        t, b = Extent(key, "TOP", t), Extent(key, "BOTTOM", b)
    end
    if not (Number(l) and Number(r) and Number(t) and Number(b)) or r <= l or t <= b then return end
    return l, r, t, b
end

function PA.Point(key, frame, point, target)
    local p = POINTS[point]
    if not p then return end
    local l, r, t, b = PA.Rect(key, frame, target)
    if not l then return end
    return l + (r - l) * p[1], b + (t - b) * p[2]
end

function PA.Center(childKey, child, info, target, w, h)
    if not PA.Valid(info) then return end
    -- Contradictory imported chains must not keep scheduling position changes.
    local key = info.target
    local db = EllesmereUIDB and EllesmereUIDB.unlockAnchors
    for i = 1, 100 do
        if key == childKey then return end
        local parent = db and db[key]
        if not parent or not parent.target then break end
        key = parent.target
        if i == 100 then return end
    end
    local tx, ty = PA.Point(info.target, target, info.targetPoint, true)
    if not tx then return end
    local ok, fw, fh, scale = pcall(Dimensions, child)
    if not ok or not (Number(scale) and scale > 0) then return end
    local ratio = scale / UIParent:GetEffectiveScale()
    if not w or not h then
        if not (Number(fw) and Number(fh)) then return end
        w, h = fw * ratio, fh * ratio
    end
    if not (Number(w) and Number(h)) or w <= 0 or h <= 0 then return end
    local l, r, t, b = Insets(childKey, child)
    if not l then return end
    l, r, t, b = -w / 2 + l * ratio, w / 2 - r * ratio, h / 2 - t * ratio, -h / 2 + b * ratio
    local p = POINTS[info.sourcePoint]
    return tx + info.offsetX - (l + (r - l) * p[1]),
        ty + info.offsetY - (b + (t - b) * p[2])
end

local function WritePoint(frame, point, rel, rp, x, y)
    EllesmereUI.ClearFramePoints(frame)
    EllesmereUI.SetFramePoint(frame, point, rel, rp, x, y)
end

function PA.Capture(childKey, info, child, target)
    if not PA.Valid(info) then return end
    child, target = child or PA.Frame(childKey), target or PA.Frame(info.target)
    local cx, cy = PA.Point(childKey, child, info.sourcePoint)
    local tx, ty = PA.Point(info.target, target, info.targetPoint, true)
    if not cx or not tx then return end
    local ex, ey = 0, 0
    if EllesmereUI._ExtraAnchorOffset then ex, ey = EllesmereUI._ExtraAnchorOffset(childKey) end
    local ratio = child:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return cx - tx - ex * ratio, cy - ty - ey * ratio
end

-- Keep the selected native point fixed between resize notifications as well.
function PA.Place(childKey, child, info, cx, cy, w, h)
    local pp = EllesmereUI.PP
    local scale = child:GetEffectiveScale()
    local ratio = UIParent:GetEffectiveScale() / scale
    local bx, by = cx * ratio, cy * ratio
    if pp and pp.SnapCenterForDim then
        bx, by = pp.SnapCenterForDim(bx, w, scale), pp.SnapCenterForDim(by, h, scale)
    end
    local ex, ey = 0, 0
    if EllesmereUI._ExtraAnchorOffset then ex, ey = EllesmereUI._ExtraAnchorOffset(childKey) end
    bx, by = bx + ex, by + ey
    local p = POINTS[info.sourcePoint]
    local x, y = bx + (p[1] - 0.5) * w, by + (p[2] - 0.5) * h
    local rel, rp = UIParent, "CENTER"
    if p and POINTS[info.targetPoint][2] == 0 and EllesmereUI._GetAnchorFollowFrame then
        local follow = EllesmereUI._GetAnchorFollowFrame(childKey, info.target, "BOTTOM")
        local tx, ty = PA.Point(info.target, PA.Frame(info.target), info.targetPoint, true)
        if follow and tx then
            rel, rp = follow, info.targetPoint
            x = x - (tx - UIParent:GetWidth() / 2) * ratio
            y = y - (ty - UIParent:GetHeight() / 2) * ratio
        end
    end
    local ok, pt, rt, rpt, px, py = pcall(child.GetPoint, child, 1)
    local plain = ok and not (issecretvalue and (issecretvalue(pt) or issecretvalue(rt) or issecretvalue(rpt)
        or issecretvalue(px) or issecretvalue(py)))
    local tolerance = ((pp and pp.perfect) or 1) / scale * 0.25
    local same = plain and child:GetNumPoints() == 1 and pt == info.sourcePoint and rt == rel and rpt == rp
        and Number(px) and Number(py) and math.abs(px - x) <= tolerance and math.abs(py - y) <= tolerance
    if not plain and PA.followPins then
        local last = PA.followPins[child]
        same = last and last.info == info and last.rel == rel and last.point == info.sourcePoint
            and last.rp == rp and math.abs(last.x - x) <= tolerance and math.abs(last.y - y) <= tolerance
    end
    if not same then
        local placed = pcall(WritePoint, child, info.sourcePoint, rel, rp, x, y)
        if not placed then return end
        if rel ~= UIParent then
            PA.followPins = PA.followPins or setmetatable({}, { __mode = "k" })
            PA.followPins[child] = { info = info, rel = rel, point = info.sourcePoint, rp = rp, x = x, y = y }
        elseif PA.followPins then
            PA.followPins[child] = nil
        end
    end
    return bx, by, not same
end

function PA.EarlyApply(key, info, child, target)
    if not PA.Valid(info) or (InCombatLockdown() and child:IsProtected()) then return end
    local cx, cy = PA.Center(key, child, info, target)
    if not cx then return end
    PA.Place(key, child, info, cx - UIParent:GetWidth() / 2, cy - UIParent:GetHeight() / 2,
        child:GetWidth(), child:GetHeight())
end

function PA.Recenter(key, UM)
    local info = UM.GetAnchorInfo(key)
    if not PA.Is(info) then return false end
    local mover = UM.movers[key]
    if not (mover and mover._dragging) then UM.ApplyAnchorPosition(key, info.target, nil, true) end
    return true
end

-- Old builds reject version 4 rather than silently reading point links as sides.
function EllesmereUI.LayoutExportVersion(value, seen)
    if type(value) ~= "table" then return 3 end
    if PA.Is(value) then return 4 end
    seen = seen or {}
    if seen[value] then return 3 end
    seen[value] = true
    for _, v in pairs(value) do
        if type(v) == "table" and EllesmereUI.LayoutExportVersion(v, seen) == 4 then return 4 end
    end
    return 3
end
