if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Quickdraw_Pointer.lua
--
--  The selection needle, the slam-open, the pointer, the hit test,
--  AdvanceArc and SteerUnchanged.
--  Reads the earlier Quickdraw files through ns and ns._qdInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._qdInternals
-- EllesmereUIQuickdraw.lua or an earlier Quickdraw file failed to load.
if not I or I.broken then return end
I.broken = true

local floor, max, abs = math.floor, math.max, math.abs
local sin, cos, atan2, sqrt, pi = math.sin, math.cos, math.atan2, math.sqrt, math.pi
local GetCursorPosition = GetCursorPosition
local GetTime = GetTime

local SelectColor, TWO_PI, PaletteView = I.SelectColor, I.TWO_PI, I.PaletteView
local SelectedZoom, FalloffK, FalloffRatios = I.SelectedZoom, I.FalloffK, I.FalloffRatios

local scrollCatcher
I.scrollCatcherSetters[#I.scrollCatcherSetters + 1] = function(v) scrollCatcher = v end

-------------------------------------------------------------------------------
--  Selection connector line -- the unlock-mode anchor line's exact look: a
--  soft-textured 3px line from the hub to the chosen entry that grows out
--  over half a second (ease-out, alpha riding the ease), with a warm streak
--  sweeping hub-to-entry on a 2.5s cycle once the grow has landed.
--
--  Region and driver are both lazy. The two Line regions exist only after a
--  line has actually been asked for, and the animation runs off the live
--  view's own open-palette OnUpdate -- a view with no OnUpdate of its own
--  (the options preview) installs one on its frame ONLY while a line is
--  shown and drops it with the line, so an idle page ticks nothing.
--
--  Drawn on the view's own frame at ARTWORK: the entries are child frames,
--  so the line passes under every icon and ends visually at the icon's edge
--  rather than crossing it; the hub's own art covers the line's root.
-------------------------------------------------------------------------------
function PaletteView:EnsureNeedle()
    local hub = self.hub
    if hub.needle then return end
    local line = self.frame:CreateLine(nil, "ARTWORK", nil, 1)
    line:SetThickness(3)
    line:SetSnapToPixelGrid(false)
    line:SetTexelSnappingBias(0)
    line:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\textures\\soft-line")
    line:Hide()
    hub.needle = line

    local pulse = self.frame:CreateLine(nil, "ARTWORK", nil, 2)
    pulse:SetThickness(3)
    pulse:SetSnapToPixelGrid(false)
    pulse:SetTexelSnappingBias(0)
    pulse:SetTexture("Interface\\AnimaChannelingDevice\\AnimaChannelingDeviceLineVerticalMask")
    pulse:Hide()
    hub.pulse = pulse
end

function PaletteView:ShowNeedle(index)
    self:EnsureNeedle()
    -- The line stands off both of its ends: 2/3 of the hub logo's height at
    -- the hub, 1/3 of it at the entry. Measured at this view's own geometry
    -- scale (the same recovery Layout makes for the logo itself), so the
    -- options preview's fitted palette trims proportionally. Stashed here
    -- rather than derived per frame: the geometry cannot move under a shown
    -- line -- any relayout goes through Layout, which hides it, and the
    -- reselect that follows lands back here.
    local p = self:P()
    local _, viewIcon = self:Geom()
    local base = (p and p.iconSize) or 40
    local k = (base > 0) and (viewIcon / base) or 1
    local logo = max(8, 40 * k)  -- the hub logo's hardcoded height
    self._needleTrimS = logo * (2 / 3)
    self._needleTrimE = logo * (1 / 3)
    -- A NEW target grows in from the hub again; the same target keeps its
    -- animation state across repaints.
    if self._needleTarget ~= index then
        self._needleTarget = index
        self._needleT0 = GetTime()
    end
    if not self.opts.live then
        -- One closure per view, made once: the ticker is installed and
        -- removed with the line, never rebuilt per show.
        if not self._needleTicker then
            local view = self
            self._needleTicker = function() view:AdvanceNeedle(GetTime()) end
        end
        self.frame:SetScript("OnUpdate", self._needleTicker)
    end
    self:AdvanceNeedle(GetTime())
end

function PaletteView:HideNeedle()
    self._needleTarget = nil
    local hub = self.hub
    if hub.needle then hub.needle:Hide() end
    if hub.pulse then hub.pulse:Hide() end
    if not self.opts.live and self.frame:GetScript("OnUpdate") == self._needleTicker then
        self.frame:SetScript("OnUpdate", nil)
    end
end

-- One animation step. The live view calls this from its open-palette
-- OnUpdate OUTSIDE the steer skip: the grow-in and the sweep both keep
-- moving under a cursor that is holding still.
function PaletteView:AdvanceNeedle(now)
    local index = self._needleTarget
    local hub = self.hub
    local line = index and hub.needle
    if not line then return end

    local w = self.widgets[index]
    local fx, fy = self.frame:GetCenter()
    local wx, wy
    if w and w:IsShown() then wx, wy = w:GetCenter() end
    if not fx or not wx then
        line:Hide()
        hub.pulse:Hide()
        return
    end
    local dx, dy = wx - fx, wy - fy

    -- Trim both ends by the stand-offs ShowNeedle stashed. A gap too small
    -- to hold both trims draws nothing rather than a backwards sliver.
    local dist = sqrt(dx * dx + dy * dy)
    local trimS = self._needleTrimS or 0
    local trimE = self._needleTrimE or 0
    if dist <= trimS + trimE + 1 then
        line:Hide()
        hub.pulse:Hide()
        return
    end
    local ux, uy = dx / dist, dy / dist
    local sx, sy = ux * trimS, uy * trimS
    local ex, ey = dx - ux * trimE, dy - uy * trimE

    -- 0.25s ease-out grow, the alpha riding the ease. Colored by the
    -- selection color -- lifted toward white for the streak, the same lift
    -- the armed border uses -- so the line and the entry it lands on agree.
    local r, g, b = SelectColor(self:P())
    local t = (now - (self._needleT0 or now)) / 0.25
    if t > 1 then t = 1 end
    local ease = 1 - (1 - t) * (1 - t)
    line:SetStartPoint("CENTER", self.frame, sx, sy)
    line:SetEndPoint("CENTER", self.frame, sx + (ex - sx) * ease, sy + (ey - sy) * ease)
    line:SetVertexColor(r, g, b, 0.75 * ease)
    line:Show()

    local pulse = hub.pulse
    if ease >= 1 then
        -- Streak: a 1.5s cycle, the first 56% of it sweeping (the rest is
        -- pause), smooth ease-in-out motion overshooting to twice the line so
        -- the tail chases the head off the far end.
        local pulseAge = now - self._needleT0 - 0.3
        local cycleT = (pulseAge % 1.5) / 1.5
        if cycleT <= 0.56 then
            local st = cycleT / 0.56
            local smoothT = st * st * (3 - 2 * st)
            local headT = smoothT * 2.0
            local tailT = headT - 1.0
            if tailT < 0 then tailT = 0 end
            local clampHead = (headT < 1) and headT or 1
            local clampTail = (tailT < 1) and tailT or 1
            local fadeA = 1
            if smoothT < 0.1 then
                fadeA = smoothT / 0.1
            elseif smoothT > 0.7 then
                fadeA = (1 - smoothT) / 0.3
            end
            if fadeA < 0 then fadeA = 0 end
            if clampHead <= clampTail then
                pulse:Hide()
            else
                pulse:SetStartPoint("CENTER", self.frame,
                    sx + (ex - sx) * clampTail, sy + (ey - sy) * clampTail)
                pulse:SetEndPoint("CENTER", self.frame,
                    sx + (ex - sx) * clampHead, sy + (ey - sy) * clampHead)
                pulse:SetVertexColor(r + (1 - r) * 0.55, g + (1 - g) * 0.55,
                    b + (1 - b) * 0.55, 0.5 * fadeA)
                pulse:Show()
            end
        else
            pulse:Hide()
        end
    else
        pulse:Hide()
    end
end

-------------------------------------------------------------------------------
--  Slam-open -- the arc's opening animation, live menu only. The entries are
--  visible from the very first frame at 50% alpha, launch from just past the
--  hub, and land on the ring over the (fast) window below, fading to full as
--  they go; the logo pops in over the same window, scaling up from half size
--  with the same fade. Driven from the open palette's own OnUpdate, outside
--  the steer skip; costs one table read per frame once landed. Steering,
--  selection and the connector line all run live throughout -- the line even
--  tracks the moving icons, since it reads their centres per frame.
-------------------------------------------------------------------------------
function PaletteView:AdvanceSlam(now)
    local t0 = self._slamT0
    if not t0 then return end
    local t = (now - t0) / 0.12
    if t >= 1 then
        self._slamT0 = nil
        t = 1
    end
    local ease = 1 - (1 - t) * (1 - t)
    local travel = 0.55 + 0.45 * ease
    local alpha = 0.5 + 0.5 * ease

    local radius = self:Geom()
    local step, arcStart = self:ArcGeom(self.shownCount)
    local frame = self.frame
    for i = 1, self.shownCount do
        local w = self.widgets[i]
        local a = arcStart + (i - 1) * step
        w:ClearAllPoints()
        w:SetPoint("CENTER", frame, "CENTER",
            radius * travel * sin(a), radius * travel * cos(a))
        w:SetAlpha(alpha)
    end

    local hub = self.hub
    local sz = self._slamLogoSize
    if sz and hub.logo:IsShown() then
        local s = sz * (0.5 + 0.5 * ease)
        hub.logo:SetSize(s, s)
        -- SetAlpha, not the vertex slot: it lands on the same unified
        -- channel, and the tint Layout wrote stays put.
        hub.logo:SetAlpha(alpha)
    end
end

-- Baseline for the movement gate in HitTest. Read AFTER the frame is placed so
-- the scale used here is the one the hit test will use.
function PaletteView:ArmMovementGate()
    local es = self.frame:GetEffectiveScale()
    local x, y = GetCursorPosition()
    self._gateX, self._gateY = x / es, y / es
    self._steered = false
end

-- Where the cursor is in the arc's own terms: the angle clockwise from straight
-- up, and the distance from the centre, both in the frame's units. nil while the
-- movement gate is still armed, or before the frame has been placed.
--
-- One copy, read by the hit test and by the falloff alike, so what the arc DRAWS
-- as nearest and what a release actually FIRES cannot part company.
function PaletteView:PointerPolar()
    local frame = self.frame
    local es = frame:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    mx, my = mx / es, my / es

    if not self._steered then
        if abs(mx - self._gateX) < 1 and abs(my - self._gateY) < 1 then return nil end
        self._steered = true
    end

    local cx, cy = frame:GetCenter()
    if not cx then return nil end

    local dx, dy = mx - cx, my - cy
    -- atan2(dx, dy) measures clockwise from straight up, matching the layout
    -- (slot 1 at 12 o'clock, index increasing clockwise).
    local theta = atan2(dx, dy)
    if theta < 0 then theta = theta + TWO_PI end
    return theta, sqrt(dx * dx + dy * dy)
end

-- Cursor -> entry index. nil inside the dead zone, and -- while the movement
-- gate is armed -- until the cursor has actually moved. The gate is what makes
-- "open and release without moving" a cancel in FIXED-POSITION mode, where the
-- cursor starts at some arbitrary point on the palette rather than at the center
-- and would otherwise have a slot pre-selected the instant the palette opens.
--
-- theta/dist may be handed in by a caller that has already read the cursor for
-- the same frame; without them the cursor is read here, so this stays callable
-- on its own.
function PaletteView:HitTest(theta, dist)
    local shown = self.shownCount
    if shown < 1 then return nil end
    local _, _, deadZone = self:Geom()

    if not theta then theta, dist = self:PointerPolar() end
    if not theta then return nil end

    -- The armed claim's rings, and no other's. A child sector reaches past its
    -- parent entry's own, so answering the parent first
    -- would settle the question before the child was ever considered -- but
    -- that only matters for the ONE claim the cursor has actually armed by
    -- passing through its parent entry; every other claim's ground answers as
    -- though it held no nest at all. See ArmedClaim.
    local claims = self.claims
    local armed = self:ArmedClaim()
    local c = armed and claims and claims[armed]
    if c and c.base and dist >= c.band then
        -- Which ring dist falls in -- lo/hi are set so consecutive rings
        -- share a boundary at their midpoint radius, and the last ring's
        -- hi is nil, i.e. everything past the second-to-last ring's
        -- midpoint. A miss here (angularly outside the ring it landed in)
        -- falls out of the claim entirely rather than trying another
        -- ring: the rings partition the RADIUS, not the angle.
        for r = 1, #c.rows do
            local row = c.rows[r]
            if dist >= row.lo and (not row.hi or dist < row.hi) then
                if row.step > 0 then
                    local rel = (theta - row.start + row.step * 0.5) % TWO_PI
                    if rel < row.n * row.step then
                        return c.base + row.base + floor(rel / row.step) + 1
                    end
                end
                break
            end
        end
    end

    if dist < deadZone then return nil end

    local step, arcStart, full = self:ArcGeom(shown)
    if step == 0 then return 1 end

    local rel = theta - arcStart
    if full then return (floor(rel / step + 0.5) % shown) + 1 end

    -- Resolved into [0, TWO_PI) from the arc's start, NOT into (-pi, pi]: an arc
    -- may span up to a full turn, so an offset of more than half a turn is a
    -- legitimate position near its end rather than a negative one near its
    -- start. Folding it would silently amputate everything past 180 degrees.
    rel = rel % TWO_PI

    -- The arc owns half a step past its last entry, the same width every
    -- interior entry gets. Beyond that is a miss, not a clamp: outside the arc
    -- is the only place its cancel can live once the dead zone has been left.
    if rel > (shown - 1) * step + step * 0.5 then return nil end

    local idx = floor(rel / step + 0.5) + 1
    if idx < 1 or idx > shown then return nil end
    return idx
end

-- Lay the falloff over the ring and select the entry the cursor points at. The
-- arc's answer to AdvanceGrid, and it reads the same two settings: an entry one
-- step off the cursor is drawn at the same fraction of full size and full alpha
-- whichever layout it is standing in.
--
-- Nearness on a ring is an ANGLE, not a distance -- every entry is the same
-- distance out, so a radial measure would say nothing -- and it is counted in
-- STEPS, which is what makes the falloff mean "each entry along from the one
-- under the cursor" here as it does everywhere else.
--
-- Positions are left exactly where Layout put them. Only size and alpha move:
-- an entry that also slid along the ring would drag itself out from under the
-- cursor that had just reached it.
function PaletteView:AdvanceArc()
    local p = self:P()
    local shown = self.shownCount
    if not p or shown < 1 then
        self:SetSelection(nil)
        return
    end

    -- One read of the cursor for the whole pass, handed to the hit test and
    -- used for the falloff below: what the ring DRAWS as nearest and what a
    -- release actually FIRES have to come from the same position.
    local theta, dist = self:PointerPolar()
    local best = self:HitTest(theta, dist)

    local _, iconSize, deadZone = self:Geom()
    local decay, aDecay = FalloffRatios(p)
    local minS   = p.fanMinScale or 0.30
    local minA   = p.fanMinAlpha or 0.12

    local step, arcStart = self:ArcGeom(shown)
    -- Inside the dead zone the cursor is not pointing anywhere yet: an angle
    -- read a pixel from the centre swings wildly on the smallest movement, and
    -- the ring would strobe under a hand that had barely left the middle. The
    -- palette is drawn evenly there, which is also what it opens as.
    local steer = theta and step > 0 and dist >= deadZone

    local zoom = SelectedZoom()
    for i = 1, shown do
        local w = self.widgets[i]
        local s, a = 1, 1
        if steer then
            -- Shortest way round, so an entry just anticlockwise of slot 1 is
            -- one step from it rather than a whole turn away. Flattened over
            -- the entry's own sector -- see FalloffK -- so the entry the cursor
            -- is on holds still while the cursor moves about inside it.
            local d = (theta - (arcStart + (i - 1) * step)) % TWO_PI
            if d > pi then d = TWO_PI - d end
            local k = FalloffK(d / step)
            s = max(minS, decay ^ k)
            a = max(minA, aDecay ^ k)
        end

        -- Magnified here rather than left to the selection paint: these sizes
        -- are rewritten every frame and would erase a zoom applied only where
        -- the selection changed. Same reason the strip and the grid do it.
        local z = (i == best) and zoom or 1
        w:SetAlpha(a)
        w.baseSize = iconSize * s
        w:SetSize(iconSize * s * z, iconSize * s * z)
    end

    self:SetSelection(best)
end

-- Has anything the steering passes read moved since the last frame?
--
-- All three of them are pure functions of the geometry Layout worked out and
-- of four running inputs: where the cursor is, which claim the gates have
-- armed, where the wheel has left the strip, and whether the strip is still
-- sliding toward it. Given the same four they rewrite every entry's point,
-- size and alpha to exactly what is already on screen -- so a frame that
-- brings none of them in new can skip the pass outright. A hold lasts many
-- frames and the hand is still on most of them, which is what makes this
-- worth asking.
--
-- Not the alpha, though: the flick-ahead fade is time-based, so
-- UpdatePaletteAlpha runs on every frame regardless.
--
-- The snapshot is cleared by Layout, the one place the geometry underneath it
-- can change while the palette is open.
function PaletteView:SteerUnchanged()
    local x, y = GetCursorPosition()
    local armed = self:ArmedClaim()
    -- Read the same way AdvanceFan reads it, so a wheel tick the pass has not
    -- picked up yet still counts as a change.
    local wheel = self.opts.live and scrollCatcher
                  and scrollCatcher:GetAttribute("eqdFanTarget") or nil
    -- Mid-settle the strip's geometry moves on its own. Both are nil on the
    -- layouts that have no settle at all, which compares equal -- which is why
    -- ns.Close has to clear the pair rather than just the target.
    local settling = self.fanVisual ~= self.fanTarget

    local same = not settling
             and x == self._steerX and y == self._steerY
             and armed == self._steerArmed and wheel == self._steerWheel
    self._steerX, self._steerY = x, y
    self._steerArmed, self._steerWheel = armed, wheel
    return same
end

I.broken = false
