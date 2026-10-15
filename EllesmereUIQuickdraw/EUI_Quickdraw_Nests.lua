if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Quickdraw_Nests.lua
--
--  The grid, the perimeter helpers and the nests of the block layouts:
--  metrics, perimeter, halo, strip, cell child geometry, the nest hit test.
--  Reads the earlier Quickdraw files through ns and ns._qdInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._qdInternals
-- EllesmereUIQuickdraw.lua or an earlier Quickdraw file failed to load.
if not I or I.broken then return end
I.broken = true

local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
local sin, cos, atan2, sqrt, pi = math.sin, math.cos, math.atan2, math.sqrt, math.pi
local tsort = table.sort

local MAX_SLOTS, NEST_BAND_DEFAULT = I.MAX_SLOTS, I.NEST_BAND_DEFAULT
local PaletteView, AddRegion, CorridorBox = I.PaletteView, I.AddRegion, I.CorridorBox
local EdgeBox, GraceBox, NestBBox = I.EdgeBox, I.GraceBox, I.NestBBox
local ParentHoles, RunReach = I.ParentHoles, I.RunReach

-------------------------------------------------------------------------------
--  Grid
--
--  Every entry at a fixed cell, the one nearest the pointer zoomed, everything
--  else falling off by distance. A pointer-steered FAN is this same layout one
--  entry deep -- a single row when it runs horizontally, a single column when
--  it runs vertically -- so it routes here rather than into a parallel 1D
--  implementation. This is the mode that scales -- pointer travel to the worst
--  entry grows with the SQUARE ROOT of the count rather than linearly, and a
--  fixed 2D arrangement is far easier to build muscle memory against than a
--  position along a line.
--
--  Rows are centred individually, so a short final row sits under the middle of
--  the one above it instead of hanging off the left edge.
-------------------------------------------------------------------------------

-- How far from EVERY entry, in cells, the pointer may stray before the grid
-- deselects. This is the grid's cancel: it has no dead zone to release inside.
local GRID_REACH = 1.0

-- What the block behind an open nest is pushed back to, for the styles that put
-- their children over it. Enough to read as "that layer is not the one you are
-- on" while still showing the shape of what you came from.
--
-- The dim only lands once the nest's gate is actually armed (see ArmedClaim),
-- meaning the cursor has gone through the parent entry itself -- which is
-- worth a clearer break between "the nest you are in" and "the palette
-- behind it".
local NEST_DIM_ALPHA = 0.15
local NEST_DIM_SCALE = 0.7

-- What an UNARMED nest is drawn at while the selection sits on its parent. Its
-- children are placed and visible, so the palette still says that this entry
-- opens a nest and where that nest will appear -- but none of them can be fired
-- until a gate arms the claim, so they are drawn as something that has not
-- happened yet. Drawn at full strength they promised a live nest and then
-- answered nothing, which read as the sub-palette being broken.
--
-- The margin, in pitches, around a scroll-steered strip that the pointer may
-- travel inside before it deselects. This is that layout's cancel, and it is
-- the same gesture the grid cancels with -- throw the pointer clear of the
-- icons -- rather than a rule of its own to learn.
--
-- Clear in ANY direction, but not the same distance in each: the box is this
-- margin across the strip and the strip's own drawn length plus the margin
-- along it. A strip is long one way and thin the other, and leaving it means
-- passing its edge, wherever that edge happens to be.
--
-- Measured from where the pointer was when the palette opened, not from the
-- strip, so it means the same thing in Fixed Position mode, where the strip is
-- somewhere else on the screen entirely.
--
-- Note what this does NOT cover: while the right button holds the camera the
-- cursor is frozen, so it cannot travel and the strip cannot be cancelled --
-- and camera steering is the case this layout exists for. A player who wants
-- out of a strip opened mid-turn has to let the camera go first.
local FAN_CANCEL_REACH = 2.25

-- Columns for a grid the user has not pinned. Near-square, because the whole
-- point of a grid is to shorten the WORST pointer travel, and that is minimised
-- when the two axes are balanced: nine entries want 3x3, not 4 + 4 + 1.
--
-- The remainder check is the one refinement on ceil(sqrt). A final row holding a
-- single entry reads as a mistake rather than a layout, and widening by one
-- column always absorbs it -- 3 becomes one row of three, 7 becomes 4 + 3.
local function AutoGridColumns(shown)
    local cols = ceil(sqrt(shown))
    if cols < shown and shown % cols == 1 then cols = cols + 1 end
    return min(MAX_SLOTS, max(1, cols))
end

-- A pointer-steered fan IS a grid one entry deep, so it resolves here rather
-- than in a parallel 1D implementation: a horizontal strip is a single row, a
-- vertical one a single column. Only the scroll-steered fan needs geometry of
-- its own, because it cycles a compressed window rather than showing fixed
-- positions.
-- shownOverride lets a caller ask what the grid WOULD be for some other entry
-- count. PushPalette needs exactly that: it runs while the palette is closed,
-- when shownCount still describes whatever was drawn last.
function PaletteView:GridDims(shownOverride)
    local p = self:P()
    local shown = max(1, shownOverride or self.shownCount)

    local mode = self:LayoutMode()
    if mode == "FAN" then
        if self:FanHoriz() then return shown, 1 end
        return 1, shown
    end

    local cols
    if not p or p.gridAutoColumns ~= false then
        -- Counted from the REAL entries, not from `shown`. An interactive view
        -- draws one extra entry for the trailing "+", and letting that tip the
        -- column count would make the editor lay a palette out differently from
        -- the way it is played -- six actions previewing as 4 + 3 while the
        -- live palette drew 3 + 3.
        cols = AutoGridColumns(max(1, shownOverride or self.slotCount or shown))
    else
        cols = min(MAX_SLOTS, max(1, floor(p.gridColumns or 4)))
    end
    if cols > shown then cols = shown end
    return cols, ceil(shown / cols)
end

-- Centre-relative position of slot i, in the frame's own units.
function PaletteView:GridBase(i, cols, rows, pitch, shownOverride)
    local r = floor((i - 1) / cols)
    local c = (i - 1) % cols
    local inRow = min(cols, (shownOverride or self.shownCount) - r * cols)
    return (c - (inRow - 1) * 0.5) * pitch, -(r - (rows - 1) * 0.5) * pitch
end

-------------------------------------------------------------------------------
--  Nested cells for a block layout
--
--  Every nested cell owns a BOX. Inside it, that child; outside every box, the
--  palette's own nearest-cell search, exactly as if the nest were not there.
--  That one rule is what makes a nest behave like a thing you are IN: leave the
--  run in ANY direction -- along it, across it, back over the parent -- and you
--  are out of it, because you are outside its boxes. Boxes are also what let a
--  nest sit over ground the block is using, which the styles below need and a
--  nearest-centre rule could never allow.
--
--  Boxes are tested in cell order and the FIRST hit wins, so two that overlap
--  still have exactly one answer. The drawing and the snippet walk them in the
--  same order, which is the whole requirement -- they need to agree, not to be
--  disjoint.
-------------------------------------------------------------------------------

-- Clockwise from straight up: the eight positions around a cell.
local HALO_DIRS = {
    { 0, 1 }, { 1, 1 }, { 1, 0 }, { 1, -1 },
    { 0, -1 }, { -1, -1 }, { -1, 0 }, { -1, 1 },
}

-- A point on the band that hugs the block, clockwise from the left end of its
-- top edge. Returns the point, the axis the run travels along there, and which
-- side of the block it is (+1 up/right). Wrapping a run around a corner costs
-- nothing in this form: it is one coordinate, and a corner is just a place where
-- the axis changes.
--
-- The corners are ROUNDED, and not for looks. Cells are spaced evenly along the
-- path, and around a square corner the straight-line distance between two of
-- them is shorter than the path between them by up to a third. An arc of the
-- same radius as the band is deep spends the path length the turn needs, so a
-- run keeps the spacing it asked for as it wraps instead of bunching at the
-- bend. That is all the rounding buys: the icons drawn on those cells can still
-- run into each other across a turn, and PerimeterNest is where they are sized
-- down until they do not.
local function PerimeterSpan(HX, HY, R)
    local sx, sy = HX * 2 - R * 2, HY * 2 - R * 2
    local arc = pi * 0.5 * R
    return sx, sy, arc, 2 * (sx + sy) + 4 * arc
end

-- Also returns the OUTWARD normal, which is how a nest deep enough to need a
-- second row finds where to put it: one row further out along the normal keeps
-- the rows square with each other on a straight edge and fanned around a corner.
local function PerimeterPoint(t, HX, HY, R)
    local sx, sy, arc, L = PerimeterSpan(HX, HY, R)
    t = t % L
    if t < sx then return -HX + R + t, HY, "X", 1, 0, 1 end
    t = t - sx
    if t < arc then
        local a = t / R
        -- Half a turn each: a cell more than halfway round a corner belongs to
        -- the side it is heading onto, so its box lies across the run it is
        -- about to join rather than across the one it has left.
        local ax = (a >= pi * 0.25) and "Y" or "X"
        return HX - R + R * sin(a), HY - R + R * cos(a), ax, 1, sin(a), cos(a)
    end
    t = t - arc
    if t < sy then return HX, HY - R - t, "Y", 1, 1, 0 end
    t = t - sy
    if t < arc then
        local a = t / R
        local ax, sg = "Y", 1
        if a >= pi * 0.25 then ax, sg = "X", -1 end
        return HX - R + R * cos(a), -HY + R - R * sin(a), ax, sg, cos(a), -sin(a)
    end
    t = t - arc
    if t < sx then return HX - R - t, -HY, "X", -1, 0, -1 end
    t = t - sx
    if t < arc then
        local a = t / R
        local ax = (a >= pi * 0.25) and "Y" or "X"
        return -HX + R - R * sin(a), -HY + R - R * cos(a), ax, -1, -sin(a), -cos(a)
    end
    t = t - arc
    if t < sy then return -HX, -HY + R + t, "Y", -1, -1, 0 end
    t = t - sy
    local a = t / R
    local ax, sg = "Y", -1
    if a >= pi * 0.25 then ax, sg = "X", 1 end
    return -HX + R - R * cos(a), HY - R + R * sin(a), ax, sg, -cos(a), sin(a)
end

-- The parameter that advances a run one child pitch of GROUND from ta, not one
-- child pitch of path. The two agree along a straight edge. Around a turn the
-- straight line between two cells is shorter than the path between them, so a
-- run spaced by path alone lands the pair straddling the corner nearer each
-- other than it asked -- near enough, at the radius this band can afford, that
-- their icons collide and the shrink pass at the bottom of PerimeterNest takes
-- the whole run down with them. The step is measured the way overlap is --
-- the wider axis of the two -- so the icons it separates clear at full size
-- however the turn lies between them.
local function PerimeterStep(ta, HX, HY, R, pitch)
    local ax, ay = PerimeterPoint(ta, HX, HY, R)
    local dt = pitch
    -- The point never outruns the parameter, so growing the guess by the
    -- shortfall cannot overshoot, and each round closes most of what is left:
    -- a straight edge is exact on the first try, a turn settles within a
    -- fraction of a pixel well inside the bound.
    for _ = 1, 8 do
        local bx, by = PerimeterPoint(ta + dt, HX, HY, R)
        local sep = max(abs(bx - ax), abs(by - ay))
        if sep >= pitch - 0.5 then break end
        dt = dt + (pitch - sep)
    end
    return dt
end

-- The parameter of the point on that same band NEAREST (px, py): PerimeterPoint
-- read backwards. A lane centres its run here, which is what puts a nest
-- opposite the entry that opens it however that entry sits in the block.
--
-- Worked out per side and per corner arc rather than by walking the path: a
-- scan fine enough to place a run would cost more than the run does, and a
-- coarse one would answer a different parameter to the drawing than to the
-- push.
--
-- positive is the tie-break side (fixed at above/right now), answering
-- wherever the projection genuinely ties, and ties are the ordinary case
-- rather than the awkward one. The band stands
-- the same distance off every edge, so a CORNER cell is exactly as far from
-- both of the edges that meet there: two ADJACENT sides tie, and the answer is
-- the corner between them -- a run centred there wraps its L around it. Two
-- OPPOSITE sides tie for a cell on the block's own middle line, and all four
-- tie for a cell dead centre, where there is no lean to read at all and the
-- run belongs on the middle of the positive edge.
--
-- axisOnly keeps a degenerate one-row or one-column block breaking out ACROSS
-- itself and only across itself: the sides in line with it are left out of the
-- projection altogether rather than merely losing a tie-break.
local function PerimeterNearest(px, py, HX, HY, R, positive, axisOnly)
    local sx, sy, arc, L = PerimeterSpan(HX, HY, R)
    -- Where the corner arcs are centred, and so also the corners of the region
    -- in which some straight side is the nearest part of the path at all.
    local cx, cy = HX - R, HY - R

    -- Diagonally past one of those centres no straight side can answer, and the
    -- nearest point is on that corner's own arc, at the angle the offset points
    -- in. Nothing inside a block ever lands here -- the band stands off further
    -- than it turns -- but an inverse that held only where the caller happens to
    -- ask is a trap for the next caller.
    if not axisOnly and abs(px) > cx and abs(py) > cy then
        local dx = px - ((px > 0) and cx or -cx)
        local dy = py - ((py > 0) and cy or -cy)
        -- Each arc measured from its own start, the way PerimeterPoint runs it,
        -- and the argument order per arc is that arc's own sin/cos pair there.
        if px > 0 and py > 0 then return sx + atan2(dx, dy) * R end
        if px > 0 then return sx + sy + arc + atan2(-dy, dx) * R end
        if py < 0 then return 2 * sx + sy + 2 * arc + atan2(-dx, -dy) * R end
        return 2 * sx + 2 * sy + 3 * arc + atan2(dy, -dx) * R
    end

    -- Distance to each side's straight run in path order -- top, right, bottom,
    -- left -- with the parameter of the projected point alongside, and the
    -- middle of the arc FOLLOWING each side, which is the answer whenever that
    -- side and the next one tie. A side the caller ruled out is never nearest.
    local far = L * 2
    local acrossX = (not axisOnly) or axisOnly == "X"
    local acrossY = (not axisOnly) or axisOnly == "Y"
    local d = { acrossX and (HY - py) or far, acrossY and (HX - px) or far,
                acrossX and (py + HY) or far, acrossY and (px + HX) or far }
    local t = { px + cx,
                sx + arc + (cy - py),
                sx + sy + 2 * arc + (cx - px),
                2 * sx + sy + 3 * arc + (py + cy) }
    local mid = { sx + arc * 0.5,
                  sx + sy + arc * 1.5,
                  2 * sx + sy + 2 * arc + arc * 0.5,
                  2 * sx + 2 * sy + 3 * arc + arc * 0.5 }

    -- Exact wherever it decides anything -- every cell of a row stands the same
    -- distance off the edge it is on -- but compared with a tolerance anyway,
    -- the two distances arriving by different arithmetic.
    local best = min(d[1], d[2], d[3], d[4])
    local tie = {}
    for si = 1, 4 do tie[si] = (d[si] - best) <= 1e-4 end

    if tie[1] and tie[2] and tie[3] and tie[4] then
        -- No lean in any direction: the positive tie-break picks the edge
        -- and the run sits on the middle of it.
        if positive then return sx * 0.5 end
        return sx * 1.5 + sy + 2 * arc
    end
    -- An opposite pair is the tie-break's other question, and answering it here
    -- leaves at most two sides standing, which can then only be adjacent.
    if tie[1] and tie[3] then tie[positive and 3 or 1] = false end
    if tie[2] and tie[4] then tie[positive and 4 or 2] = false end
    for si = 1, 4 do
        if tie[si] and tie[(si % 4) + 1] then return mid[si] end
    end
    for si = 1, 4 do
        if tie[si] then return t[si] end
    end
end

-- Everything the three styles measure from. Sizes are scaled by whatever this
-- view scaled its geometry by, recovered from the icon size Geom handed back --
-- the options preview fits a palette to its panel, and a band read at its
-- literal profile size would draw nests at full distance around a shrunken one.
function PaletteView:NestMetrics(shown)
    local p = self:P()
    local _, iconSize = self:Geom()
    local pitch = self:Pitch()
    local base = p.iconSize or 40
    local k = (base > 0) and (iconSize / base) or 1
    local cols, rows = self:GridDims(shown)

    local m = {
        icon  = iconSize,
        pitch = pitch,
        cols  = cols,
        rows  = rows,
        band  = max(0, p.nestBand or NEST_BAND_DEFAULT) * k,
        gap   = (p.fanGap or 10) * k,
        -- FIXED true -- nests break out above/right wherever the sides tie
        -- (the Nest Side setting was removed); a nestSide key left in stored
        -- profiles is never read.
        positive = true,
        -- Everything that is not a halo is a lane. That includes the retired
        -- POPOUT value a stored profile may still carry: its detached block
        -- came to answer arming exactly the way the lane does, and the lane is
        -- what it folded into.
        style = (p.gridNestStyle == "HALO") and "HALO" or "PERIMETER",
    }
    m.halfX = (cols - 1) * 0.5 * pitch
    m.halfY = (rows - 1) * 0.5 * pitch
    -- Nested entries are drawn smaller than the palette's own, so a nest reads
    -- as subordinate to the entry it hangs off rather than as a second block of
    -- equals.
    m.childIcon  = iconSize * min(1, max(0.4, p.nestScale or 0.8))
    m.childPitch = m.childIcon + m.gap
    -- Across the run: how thick the band of boxes is. One icon plus the gap
    -- either side of it, so the box reaches back to the block's own edge and a
    -- pointer leaving the parent enters the nest without crossing dead ground.
    -- The lane works its own out, its children standing off by a gap rather
    -- than by a band -- see PerimeterNest.
    m.depth = m.childIcon + m.band
    -- Whatever Nest Distance was asked for BEYOND the value the profile ships
    -- with. The lane hugs the block at the default and reads the slider as
    -- extra clearance on top of that, so the two answers agree wherever the
    -- user has moved it and the snug read is what an untouched profile gets.
    m.bandExtra = max(0, (p.nestBand or NEST_BAND_DEFAULT) - NEST_BAND_DEFAULT) * k
    -- A strip has no interior to displace and no corner to wrap, so the styles
    -- that rearrange a block have nothing to rearrange: it is always a small
    -- block of its own, centred on the parent and broken out perpendicular to
    -- the strip, whatever gridNestStyle asks for.
    if cols <= 1 or rows <= 1 then m.style = "STRIP" end
    return m
end

-- Box for one cell of a run travelling on `axis`.
local function RunBox(x, y, axis, along, across)
    if axis == "X" then
        return { x = x, y = y, hw = along * 0.5, hh = across * 0.5 }
    end
    return { x = x, y = y, hw = across * 0.5, hh = along * 0.5 }
end

-- (A) A halo hugging the block's own perimeter: one run of children, centred on
-- the point of that perimeter NEAREST the entry they hang off, wrapping the
-- corners when the run is long. A parent on the middle of an edge is served by
-- the stretch of lane just outside it, a parent in the middle of the block by
-- the middle of the positive edge, and a corner parent by the corner itself --
-- the L around it, half the run down each of the two edges that meet there.
--
-- The band is ONE lane: two nests near each other sit side by side along it
-- rather than stacking outward, which is what the eye expects when only one of
-- them is ever drawn. Runs are packed along the perimeter as a single circular
-- coordinate, so a run longer than the edge it started on wraps around the
-- corner instead of shooting off into space.
function PaletteView:PerimeterNest(claims, shown, m)
    -- Snug against the block, which is the whole read of this style: the
    -- children's inner edges stand one gap outside the block's own outer edge,
    -- so the lane looks like a halo ON the grid rather than a second block of
    -- entries floating off it. Nest Distance is honoured as clearance BEYOND
    -- that, so a user who wants the children held further out can still say so.
    local clear = m.gap + m.bandExtra
    local standoff = m.icon * 0.5 + clear + m.childIcon * 0.5
    -- Across the run: from the block's own outer edge to as far past the child
    -- icon as the child icon is from the block. A pointer leaving the parent
    -- enters the nest without crossing dead ground, and one that overruns an
    -- icon on the way out is still inside its box.
    local depth = m.childIcon + clear * 2
    local HX, HY = m.halfX + standoff, m.halfY + standoff
    -- The turn's radius, balanced between the two things it trades off. Too
    -- small and two icons either side of it crowd, the straight line between
    -- them being shorter than the path by up to a third around a square corner
    -- (see PerimeterSpan); too large and the turn itself cuts diagonally in
    -- across the block's own corner entry, which a lane this snug is close
    -- enough in to do. Both are straight lines measured against the same floor
    -- of one child icon, and this is the radius where the two meet. That floor
    -- shapes the turn; it does not clear the icons on it. Two square icons
    -- straddling a corner can sit a whole icon apart in a straight line and
    -- still be short of one on BOTH axes, which is what overlap actually asks,
    -- so the cells are SPACED by that same measure -- see PerimeterStep --
    -- and a turn costs the run extra path rather than ground.
    local turn = (standoff - m.childPitch * 0.5) * sqrt(2)
                 / (2 * sqrt(2) + 1 - sqrt(2) * pi * 0.25)
    local R = min(depth * 0.5, min(HX, HY) * 0.5, max(0, turn))
    local sx, sy, arc, L = PerimeterSpan(HX, HY, R)

    local childPitch, childIcon = m.childPitch, m.childIcon
    -- A strip breaks out ACROSS itself and only across itself: a row of entries
    -- has an edge at both ends, and a nest hung off one of those would run in
    -- line with the palette rather than out of it. NestMetrics sends those
    -- shapes to STRIP before they reach this at all, so this only holds the rule
    -- for a caller that arrives here anyway.
    local axisOnly = (m.rows <= 1 and "X") or (m.cols <= 1 and "Y") or nil

    for i = 1, #claims do
        local c = claims[i]
        local bx, by = self:GridBase(c.parent, m.cols, m.rows, m.pitch, shown)
        -- c.icon is not set here: what this style may draw a child at depends
        -- on how tightly that run ends up packed, which is not known until its
        -- cells are placed below.
        -- Along the lane, a caption is drawn at CHILD pitch rather than at the
        -- pitch the palette's own entries get, so two neighbouring captions
        -- overlap long before their icons do. Unlabelled, like every other
        -- style's nest.
        c.label = false
        c._bx, c._by = bx, by
        -- The clear distance this style actually held its children out by, which
        -- is what CellChildGeom sizes the arming grace from. Nest Distance is
        -- only part of it here, and at the bottom of that slider's travel none
        -- of it -- a grace read off the slider instead would go on shrinking
        -- after the children had stopped moving.
        c.standoff = clear
        -- The nearest point of the lane, from the parent's own CELL rather than
        -- from anywhere on the screen: the push runs long before the open that
        -- will use it, and the two have to agree.
        c.t0 = PerimeterNearest(bx, by, HX, HY, R, m.positive, axisOnly)
    end

    -- How much of the lane each nest may take: the WHOLE of it. Only one nest is
    -- ever open, and only one is ever armed, so two runs overlapping on the lane
    -- is not an ambiguity -- the cursor can only be inside the armed claim's
    -- cells, and the unarmed one is neither drawn nor answerable. Sharing the
    -- lane out between the claims instead left two nests in neighbouring cells
    -- with three quarters of a pitch each, which collapses cols to one or two
    -- and stacks the run outward into rows: the user asked for a run round the
    -- block and got a cluster hanging off the entry.
    --
    -- L is the bound that remains, and it is a real one: a run longer than the
    -- lane would wrap past its own first cell and put two children on the same
    -- ground.
    for i = 1, #claims do
        local c = claims[i]
        -- A crowded nest EXTENDS along the perimeter first, as far as the lane
        -- goes: wrapping further round the block costs the user nothing, and one
        -- long run is the shape this style is for. Only a nest whose children do
        -- not all fit on the lane spills the rest into a second row further out.
        --
        -- How many fit is WALKED rather than divided out of L: a step spends
        -- more than a pitch of path at a turn, so a row sized by L / pitch
        -- could wrap past its own first cell exactly when the lane is full
        -- enough for it to matter.
        local room, walked = 1, 0
        while room < c.n do
            local step = PerimeterStep(c.t0 + walked, HX, HY, R, childPitch)
            if walked + step > L - childPitch then break end
            walked, room = walked + step, room + 1
        end
        local cols = room
        -- One row of parameters per row of cells, each row centred on t0 the
        -- way the even spacing was: walked once from a guessed start to learn
        -- the path length it really spends, then again from the start that
        -- puts half of that either side of t0.
        local rowTs = {}
        for cr = 0, ceil(c.n / cols) - 1 do
            local inRow = min(cols, c.n - cr * cols)
            local start = c.t0 - (inRow - 1) * 0.5 * childPitch
            local row
            for _ = 1, 2 do
                row = { start }
                for jr = 2, inRow do
                    row[jr] = row[jr - 1]
                              + PerimeterStep(row[jr - 1], HX, HY, R, childPitch)
                end
                start = c.t0 - (row[inRow] - row[1]) * 0.5
            end
            rowTs[cr + 1] = row
        end
        c.cells = {}
        -- The sides the run came down on, in the order it reached them. A run
        -- that wrapped a corner has cells on two of them, and its regions are
        -- one tight box per side rather than one across the L -- see
        -- CellChildGeom, which is where that matters.
        local groups, bySide = {}, {}
        for j = 1, c.n do
            local cr  = floor((j - 1) / cols)
            local cc  = (j - 1) % cols
            local t = rowTs[cr + 1][cc + 1]
            local x, y, axis, sign, nx, ny = PerimeterPoint(t, HX, HY, R)
            -- Rows past the first sit one row further out along the outward
            -- normal, which keeps them square on a straight edge and fanned
            -- around a corner.
            local outw = cr * (childIcon + m.gap)
            local box = RunBox(x + nx * outw, y + ny * outw,
                               axis, childPitch, depth)
            c.cells[j] = box
            -- PerimeterPoint hands a cell more than halfway round a corner to
            -- the side it is heading onto, so these come out as the runs the eye
            -- actually reads rather than as a split at the corner's own edge.
            local key = axis .. sign
            local g = bySide[key]
            if not g then
                g = { axis = axis, sign = sign, cells = {}, order = #groups + 1 }
                bySide[key], groups[#groups + 1] = g, g
            end
            g.cells[#g.cells + 1] = box
        end

        -- The walk above holds every CONSECUTIVE pair a whole pitch apart, but
        -- it says nothing about the pairs it never measured: a run that fills
        -- the lane meets its own first cell across the seam, and a spilled row
        -- crosses back over the one under it wherever the fan folds. So this
        -- run's icons come down to the tightest pair it actually has. The
        -- BOXES keep their pitch -- the run holds its length, its regions and
        -- its gates, and the hit test answers exactly what it did -- and an
        -- ordinary run has no pair nearer than a pitch, so it comes out at
        -- the size it asks for. nestScale is the ceiling either way: this only
        -- ever takes size away.
        local tight = childIcon
        for ja = 1, c.n - 1 do
            for jb = ja + 1, c.n do
                local pa, pb = c.cells[ja], c.cells[jb]
                -- Square icons drawn on the cell centres, so a pair clears as
                -- soon as ONE axis separates them by a whole icon.
                local sep = max(abs(pa.x - pb.x), abs(pa.y - pb.y))
                if sep < tight then tight = sep end
            end
        end
        c.icon = tight

        -- Nearest side first, measured to the nearest cell on it: that is the
        -- side the claim reports as its own axis, and a run long enough to wrap
        -- onto more sides than there are region gates for then loses the
        -- FURTHEST of them rather than the one the reach actually crosses.
        for gi = 1, #groups do
            local near = math.huge
            local cells = groups[gi].cells
            for ci = 1, #cells do
                local dx, dy = cells[ci].x - c._bx, cells[ci].y - c._by
                near = min(near, dx * dx + dy * dy)
            end
            groups[gi].near = near
        end
        tsort(groups, function(g1, g2)
            if g1.near ~= g2.near then return g1.near < g2.near end
            return g1.order < g2.order
        end)
        c.groups = groups
        c.axis, c.sign = groups[1].axis, groups[1].sign
    end
    return claims
end

-- (B) The eight positions around the parent's own cell, the block behind them
-- faded and shrunk. The neighbours keep their centres -- the halo is drawn tight
-- enough that they stay outside it -- so what they lose is the ground a pointer
-- could have approached them across, not the entries themselves.
function PaletteView:HaloNest(claims, shown, m)
    -- Three boxes across must stay inside one pitch either side, or a
    -- neighbouring entry's own centre would fall inside the halo and become
    -- unselectable while the halo is up. That caps the ring at two thirds of a
    -- pitch, and the ring is pushed right out to it: the parent icon sits in the
    -- middle at full size and a ring any tighter has its children touching it.
    local hp = m.pitch * 0.62
    -- Small enough that a full-size parent still has clear ground around it,
    -- which is the whole read of this style -- children AROUND an entry, not
    -- crowding it.
    local icon = min(m.childIcon, hp * 0.62)
    for i = 1, #claims do
        local c = claims[i]
        local bx, by = self:GridBase(c.parent, m.cols, m.rows, m.pitch, shown)
        -- No axis and no side: a halo surrounds its parent rather than coming
        -- out of one edge of the block, so there is no "other side" for the hub
        -- caption to move to and it keeps the placement it would have had.
        c.icon, c.dim = icon, true
        -- The parent draws back to leave the ring somewhere to be. It keeps its
        -- full colour, unlike the rest of the block: it is what the ring is
        -- about, and dimming it would leave nothing saying which entry opened.
        c.parentScale = 0.6
        -- Eight captions around one icon are eight captions on top of each
        -- other. At this size the icon is the whole of what can be read.
        c.label = false
        c.cells = {}
        for j = 1, min(c.n, #HALO_DIRS) do
            local d = HALO_DIRS[j]
            c.cells[j] = { x = bx + d[1] * hp, y = by + d[2] * hp,
                           hw = hp * 0.5, hh = hp * 0.5 }
        end
        -- The centre is left to the parent, which fires nothing: a pointer that
        -- comes to rest back on the entry it opened does nothing, rather than
        -- picking whichever child happened to be nearest.
        c.n = #c.cells
    end
    return claims
end

-- (C) A single row or column's nest: a small block of its own, centred on the
-- parent's own place along the strip and broken out perpendicular to it. A
-- strip has only the one line every parent already sits on, so there is no
-- interior for PERIMETER's lane to run around -- the crowding that style
-- solves by wrapping corners never arises here, because every claim already
-- owns a stretch of the line to itself the moment it owns a parent cell.
-- The positive side answers the side question -- a line has no lean to read.
function PaletteView:StripCellNest(claims, shown, m)
    -- rows <= 1 means the strip runs along X, so its nests break out along Y;
    -- cols <= 1 is the other way round. NestMetrics only reaches this style
    -- when one of the two is true.
    local axis = (m.rows <= 1) and "X" or "Y"
    local sign = m.positive and 1 or -1
    local out  = m.icon * 0.5 + m.band + m.childIcon * 0.5

    for i = 1, #claims do
        local c = claims[i]
        local bx, by = self:GridBase(c.parent, m.cols, m.rows, m.pitch, shown)
        c.icon = m.childIcon
        -- Packed at child pitch like every other nest style's captions, a run
        -- of them along a strip collides just as readily as PERIMETER's lane
        -- does, so this style goes unlabelled too.
        c.label = false
        c.axis, c.sign = axis, sign
        c._bx, c._by = bx, by
        -- Position along the strip's own axis, so two claims that are close
        -- together can be told apart from two that are not.
        c.t0 = (axis == "X") and bx or by
    end

    for i = 1, #claims do
        local c = claims[i]
        -- Half the room this claim's block may spread into along the strip:
        -- out to the midpoint with the nearest OTHER nest's own parent. A
        -- strip is a straight line, not PERIMETER's closed loop, so this is a
        -- plain distance rather than a distance around a wrap -- but the
        -- answer it feeds into cols is the same one: a crowded nest gives up
        -- columns and grows another row instead of colliding with its
        -- neighbour.
        local room = math.huge
        for j = 1, #claims do
            if j ~= i then room = min(room, abs(claims[j].t0 - c.t0) * 0.5) end
        end
        local ccols = min(MAX_SLOTS, max(1, ceil(sqrt(c.n))))
        if room < math.huge then
            ccols = min(ccols, max(1, floor(room * 2 / m.childPitch)))
        end

        c.cells = {}
        for j = 1, c.n do
            local cr  = floor((j - 1) / ccols)
            local cc  = (j - 1) % ccols
            local row = min(ccols, c.n - cr * ccols)
            local a = (cc - (row - 1) * 0.5) * m.childPitch
            local d = out + cr * m.childPitch
            local x, y
            if axis == "X" then x, y = c._bx + a, c._by + sign * d
            else x, y = c._bx + sign * d, c._by + a end
            c.cells[j] = { x = x, y = y,
                           hw = m.childPitch * 0.5, hh = m.childPitch * 0.5 }
        end
    end
    return claims
end

-- A scroll-steered strip's nest. The wheel decides which entry is selected and
-- that entry is always the one drawn at the CENTRE, so its children break out
-- across the strip from there -- the same perpendicular row a pointer-steered
-- strip gets, at the one place this layout can put it.
--
-- Every nest is built at that same centre; the drawing and the hit tests
-- shift a claim's cells to its parent's own fold offset when the hover
-- channel is on. Nothing is lost by it: only one nest is ever live -- the
-- wheel's entry's under wheel-only steering, the ARMED claim's under the
-- hover channel -- so two nests can no more be reached at once than two
-- entries can.
--
-- Measured from where the palette was OPENED rather than from where the strip is
-- drawn, because that is what this layout's cancel is measured from and the two
-- have to be one geometry. The drawing takes the difference out again.
function PaletteView:StripNest(claims, shown)
    local m = self:NestMetrics(shown)
    local horiz = self:FanHoriz()
    local axis = horiz and "X" or "Y"
    local sign = m.positive and 1 or -1
    local out = m.icon * 0.5 + m.band + m.childIcon * 0.5

    for i = 1, #claims do
        local c = claims[i]
        c.icon = m.childIcon
        c.axis, c.sign = axis, sign
        -- Unlabelled, like the strip's own entries: at strip spacing the
        -- captions of neighbouring icons collide, and a nest is drawn at the
        -- same spacing or tighter.
        c.label = false
        c.cells = {}
        for j = 1, c.n do
            local a = (j - (c.n + 1) * 0.5) * m.childPitch
            local x, y
            if horiz then x, y = a, sign * out else x, y = sign * out, a end
            c.cells[j] = RunBox(x, y, axis, m.childPitch, m.depth)
        end
        -- How far across the strip the pointer may travel toward this nest
        -- before it counts as thrown clear. Without it the strip's own cancel
        -- sits in the gap between an entry and its children, and reaching for
        -- one of them closes the palette instead.
        c.across = out + m.depth * 0.5
    end
    return claims
end

-- Nested cells for a block layout: the grid, and a pointer-steered strip, which
-- is a grid one entry deep.
function PaletteView:CellChildGeom(claims, shown)
    local m = self:NestMetrics(shown)
    if m.style == "STRIP" then
        self:StripCellNest(claims, shown, m)
    elseif m.style == "HALO" then
        self:HaloNest(claims, shown, m)
    else
        self:PerimeterNest(claims, shown, m)
    end

    -- The ground between a parent and its children, so that crossing it keeps
    -- the nest on screen. A nest sitting clear of the block has a gap in front
    -- of it that belongs to no cell of its own, and a nest that vanished halfway
    -- through the reach for it could not be reached at all.
    --
    -- c.regions also doubles as the claim's REGION gates (see EnsureGates):
    -- the rects a secure OnLeave watches, geometrically, to know the cursor
    -- has actually left this nest's ground, parent cell and all. c.parentBox
    -- is the other one, the claim's own cell alone -- the gate whose OnEnter
    -- arms it in the first place. Nothing here decides what a release FIRES,
    -- only what is drawn and what is armable: an entry under either box stays
    -- exactly as selectable as it was.
    --
    -- HALO sets neither axis nor sign -- its ring surrounds the parent on
    -- every side, so there is no one direction to run a corridor in, and the
    -- old single bounding box (parent cell plus every ring position) is
    -- already close enough to the true shape that a second rect buys
    -- nothing: the neighbour centres HaloNest leaves clear of the ring stay
    -- clear of this box too. Every other style hangs its nest off ONE side
    -- of the parent, so a box across the two would swallow whatever plain
    -- ground of the block lies between them -- the dim-never-backs-out
    -- complaint. Those get the true union instead: the parent's own cell,
    -- the nest's own tight box, and a corridor one child cell wide
    -- connecting them, so standing on the block's own ground either side of
    -- that corridor is standing outside the nest. Those also get the
    -- overshoot grace (see GraceBox); the halo's box does NOT, because it
    -- already reaches to just short of its neighbours' centres and a grace on
    -- top of that would swallow one, leaving that entry unselectable while
    -- the ring is up.
    --
    -- A lane brings the same complaint back in a second shape: a run that
    -- wrapped a corner has cells on two edges of the block, and ONE box
    -- around those swallows the block's own corner ground between them. So a
    -- run that carries its sides (c.groups) gets one box per side, each with
    -- its own way back to the parent folded in -- see RunReach.
    -- Every parent cell first: the regions below take the OTHER claims' cells
    -- out of their own coverage (see ParentHoles), so they all have to exist
    -- before the first of them is built.
    for i = 1, #claims do
        local c = claims[i]
        local bx, by = self:GridBase(c.parent, m.cols, m.rows, m.pitch, shown)
        c.parentBox = { x = bx, y = by, hw = m.pitch * 0.5, hh = m.pitch * 0.5 }
    end

    for i = 1, #claims do
        local c = claims[i]
        local holes = ParentHoles(claims, i)

        if c.axis then
            -- How far a claim's ground reaches past its own edges. c.standoff
            -- is a lane saying how far out it actually put its children, which
            -- for that style is not the Nest Distance at all -- it hugs the
            -- block, and the slider only adds to that -- and a grace read off
            -- the slider there would leave the bottom of its travel moving
            -- nothing but invisible slack.
            local grace = max(c.standoff or m.band, 0.75 * m.childPitch)
            local sides = c.groups
            c.regions = { c.parentBox }
            if sides then
                -- Nearest side first, PerimeterNest having ordered them: a run
                -- that reached more sides than there are region gates for then
                -- drops the far ones rather than the one the reach crosses.
                for gi = 1, #sides do
                    local run = RunReach(c.parentBox, NestBBox(sides[gi].cells))
                    AddRegion(c, GraceBox(run, grace, sides[gi].axis, sides[gi].sign),
                              sides[gi].axis, holes)
                end
            else
                local nest = NestBBox(c.cells)
                -- Measured from the TIGHT box, before the grace widens it: the
                -- corridor is as wide as the nest it leads to, and inflating
                -- the nest first would spread the corridor sideways across the
                -- block's own ground as well.
                local corridor = CorridorBox(c.parentBox, nest, c.axis, c.sign,
                                             m.childPitch)
                AddRegion(c, GraceBox(nest, grace, c.axis, c.sign), c.axis, holes)
                AddRegion(c, corridor, c.axis, holes)
            end
        else
            local pb = c.parentBox
            local x0, x1 = pb.x - m.pitch * 0.5, pb.x + m.pitch * 0.5
            local y0, y1 = pb.y - m.pitch * 0.5, pb.y + m.pitch * 0.5
            for j = 1, c.n do
                local b = c.cells[j]
                x0, x1 = min(x0, b.x - b.hw), max(x1, b.x + b.hw)
                y0, y1 = min(y0, b.y - b.hh), max(y1, b.y + b.hh)
            end
            c.regions = {}
            AddRegion(c, EdgeBox(x0, x1, y0, y1), c.axis, holes)
        end
    end
    return claims
end

-- The nested cell whose box holds this offset, WITHIN THE ARMED CLAIM only.
-- Read by the drawing; the snippet carries the same test over the same
-- numbers, gated the same way -- see ArmedClaim and the release branch of
-- SNIPPET_PRE. An unarmed claim answers nothing here at all: the whole point
-- of arming is that a nest's ground is not live until the cursor has actually
-- passed through the entry that opens it.
function PaletteView:NestHit(dx, dy, armed)
    local c = armed and self.claims and self.claims[armed]
    if not c or not c.cells then return end
    for j = 1, c.n do
        local b = c.cells[j]
        if abs(dx - b.x) <= b.hw and abs(dy - b.y) <= b.hh then
            return c.base + j, c
        end
    end
end

I.FAN_CANCEL_REACH, I.GRID_REACH = FAN_CANCEL_REACH, GRID_REACH
I.NEST_DIM_ALPHA, I.NEST_DIM_SCALE = NEST_DIM_ALPHA, NEST_DIM_SCALE
I.broken = false
