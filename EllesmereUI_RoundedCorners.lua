if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_RoundedCorners.lua
--
--  Shared rounded corners for bar frames (unit frames, power bars, raid and
--  party cells, swing timer, nameplates). EllesmereUI.RoundCorners(owner,
--  radius, opts):
--    owner         the frame that keeps the state and hosts the body mask;
--                  an ancestor of every body texture
--    radius        0..16, 0 removes everything this owner added; never more
--                  than (the shape's short side - 1) / 2
--    opts.style    the border style key; only Solid, Glow and Shadow round
--                  (EllesmereUI.RoundedStyleOK), any other style removes it
--    opts.roots    up to 6 frames whose Texture regions (recursively) form
--                  the body; nil slots are fine
--    opts.textures up to 8 single textures of the body; nil slots are fine
--    opts.border   the frame EllesmereUI.ApplyBorderStyle draws on (optional)
--    opts.clip     a SetClipsChildren frame to switch off while rounded
--    opts.rect     the region whose rect is the rounded shape (default owner)
--    opts.corners  the corners that round, as bits (1 top left, 2 top right,
--                  4 bottom left, 8 bottom right); nil = all, 0 = none
--                  (EllesmereUI.RoundedJoinCorners splits them between two
--                  bars that join one above the other)
--  The opts tables are only read during the call, so callers may reuse them;
--  at radius 0 no opts are needed.
--  EllesmereUI.RoundedBorderColor(border, r, g, b, a) recolours the ring of a
--  border painted without EllesmereUI.SetBorderStyleColor (which recolours it
--  on its own).
--
--  Masks: rounded-<r>.tga / rounded-inv-<r>.tga, (2r + 1) texels square
--  (.tools/rounded-glow/make_rounded_masks.py), sliced at r texels; no larger,
--  since the client shrinks the corners of a sliced texture bigger than its
--  region. rounded-<r>-<c>.tga / rounded-inv-<r>-<c>.tga: the same with only
--  the corners in c round, the rest square.
--  Body: a texture takes at most 3 masks, so each body texture gets ONE
--  nine-sliced rounded-rect mask, hosted on the owner (an ancestor of every
--  body texture, so it reaches into SetClipsChildren frames too). The bar
--  clip in opts.clip is switched off while rounded (the inset mask does its
--  job).
--  Solid: the body mask sits inside the border strips; the border is a
--  rounded fill in the border color with the body's exact inverse (same
--  nine-slice, same anchors) cut out, so body and border meet without a gap
--  and the fill never sits behind the body. The square strips are masked out.
--  One set of these parts per border container, so a border that moves
--  between frames (nameplate Basic <-> Custom) reuses its parts.
--  Glow / Shadow: the stock nine-slice glow is faded out and redrawn round:
--  its own edge art along the sides plus round corners generated from that
--  edge art (.tools/rounded-glow/make_glow_corners.py), its peak on the
--  rounded outline. Below half the glow width a corner piece spans the whole
--  band and the sides start past it, so they never overlap.
--  Pieces drawn outside the body stay square: the Raid Frames aggro and
--  dispel borders and party portrait, the Unit Frames threat border.
--
--  Cost: nothing until a radius above 0 is set (no masks, no hook). On: a
--  settings pass seats the body's new textures and redraws the border only
--  when one of its inputs moved; the recolor hook is a lookup. The pixel grid
--  watcher (EllesmereUI.RegisterPxReapply) re-fits the strip width and glow
--  edge of every rounded owner after a UI scale change.
-------------------------------------------------------------------------------
if not EllesmereUI then return end

local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\rounded\\"
local GLOW_EDGE = "Interface\\AddOns\\EllesmereUI\\media\\borders\\glow-border"
local MAX_RADIUS = 16 -- rounded-1.tga .. rounded-16.tga
local ALL_CORNERS = 15
-- Glow corner art (the generator's constants match these): glow-corner-1..NA
-- for a radius of at least half the glow width E, by f = band width / radius
-- in even log steps from FMIN to 2; glow-tight-1..NB below that, by
-- k = S / E in even steps between 0.5 and 1 (S: the glow's outer corner to
-- the arc center).
local GLOW_FMIN, GLOW_NA, GLOW_NB = 0.03, 32, 12
local GLOW_LOGSTEP = math.log(2 / GLOW_FMIN) / (GLOW_NA - 1)
local STRETCHED = Enum.UITextureSliceMode.Stretched
local floor, min, max, log, exp = math.floor, math.min, math.max, math.log, math.exp
local pairs, select, pcall = pairs, select, pcall

-- Media paths by number, built on first use.
local function Paths(fmt)
    return setmetatable({}, { __index = function(t, n)
        local v = MEDIA .. fmt:format(n)
        t[n] = v
        return v
    end })
end
-- Masks by radius * 16 + round corners, built on first use.
local function MaskPaths(prefix)
    return setmetatable({}, { __index = function(t, k)
        local n, c = floor(k / 16), k % 16
        local v = c == ALL_CORNERS and ("%s%s-%d.tga"):format(MEDIA, prefix, n)
            or ("%s%s-%d-%d.tga"):format(MEDIA, prefix, n, c)
        t[k] = v
        return v
    end })
end
local ROUNDED = MaskPaths("rounded")
local ROUNDED_INV = MaskPaths("rounded-inv")
local GLOW_CORNER = Paths("glow-corner-%d.tga")
local GLOW_TIGHT = Paths("glow-tight-%d.tga")

-- dx, dy: the inward direction from each corner.
local CORNERS = {
    { p = "TOPLEFT",     tc = { 0, 1, 0, 1 }, dx = 1,  dy = -1, bit = 1 },
    { p = "TOPRIGHT",    tc = { 1, 0, 0, 1 }, dx = -1, dy = -1, bit = 2 },
    { p = "BOTTOMLEFT",  tc = { 0, 1, 1, 0 }, dx = 1,  dy = 1,  bit = 4 },
    { p = "BOTTOMRIGHT", tc = { 1, 0, 1, 0 }, dx = -1, dy = 1,  bit = 8 },
}
local STRIPS = { "_top", "_bottom", "_left", "_right" }
local STYLE_OK = { solid = true, glow = true, shadow = true }
local EMPTY = {}

local state = setmetatable({}, { __mode = "k" })       -- owner -> rounding state
local byBorder = setmetatable({}, { __mode = "k" })    -- border frame -> state
local ownTex = setmetatable({}, { __mode = "k" })      -- our pieces, never masked
local hooked = false

EllesmereUI.ROUNDED_MAX_RADIUS = MAX_RADIUS
function EllesmereUI.RoundedStyleOK(style)
    return STYLE_OK[style or "solid"] == true
end

-- Options: appends the four corner toggles of a Corner Radius cog to rows.
-- get / set read and write the round corners bits (nil reads as all).
local CORNER_LABELS = { "Top Left", "Top Right", "Bottom Left", "Bottom Right" }
function EllesmereUI.RoundedCornerRows(rows, get, set)
    for i = 1, 4 do
        local b = CORNERS[i].bit
        rows[#rows + 1] = { type = "toggle", label = CORNER_LABELS[i],
            get = function() return bit.band(get() or ALL_CORNERS, b) ~= 0 end,
            set = function(v)
                local m = get() or ALL_CORNERS
                set(v and bit.bor(m, b) or bit.band(m, ALL_CORNERS - b))
            end }
    end
    return rows
end

-- Options: the Join toggle for a bar that can sit right above or below its
-- partner (a detached power bar, a nameplate cast bar). applies() returns
-- true while the toggle applies; nil = always.
function EllesmereUI.RoundedJoinRow(rows, label, tooltip, get, set, applies, need)
    rows[#rows + 1] = { type = "toggle", label = label, tooltip = tooltip,
        get = function() return get() == true end, set = set,
        disabled = applies and function() return not applies() end or nil,
        disabledTooltip = need }
    return rows
end

-- Two bars joined one above the other share one outline: the upper bar takes
-- the top corners, the lower one the bottom corners. Returns upper, lower.
function EllesmereUI.RoundedJoinCorners(corners)
    local m = corners or ALL_CORNERS
    return bit.band(m, 3), bit.band(m, 12)
end

-- Guarded: a texture takes at most 3 masks; a full one stays square.
local function AddMask(tex, m)
    return (pcall(tex.AddMaskTexture, tex, m))
end
-- Guarded the same way: the texture may no longer carry the mask.
local function RemoveMask(tex, m)
    pcall(tex.RemoveMaskTexture, tex, m)
end

local function SetRounded(obj, radius, corners, wrap)
    obj:SetTexture(ROUNDED[radius * 16 + corners], wrap, wrap)
    obj:SetTextureSliceMargins(radius, radius, radius, radius)
    obj:SetTextureSliceMode(STRETCHED)
end

-- Half a region's short side, or nil while it is unsized or secret.
local function HalfSide(region)
    local w, h = region:GetSize()
    if issecretvalue(w) or issecretvalue(h) then return nil end
    local half = min(w, h) / 2
    if half > 0 then return half end
end

-------------------------------------------------------------------------------
--  Body
-------------------------------------------------------------------------------
-- The pass being walked (MaskBody sets these; walks never nest). A seated
-- texture carries the number of the last pass that found it, so the ones
-- left with an older number have left the body.
local wMasked, wMask, wGen, wSkip

local function Seat(tex)
    if wMasked[tex] or AddMask(tex, wMask) then wMasked[tex] = wGen end
end

local function SeatRegions(...)
    for i = 1, select("#", ...) do
        local r = select(i, ...)
        if r:GetObjectType() == "Texture" and not ownTex[r] then Seat(r) end
    end
end

local Walk
local function WalkChildren(...)
    for i = 1, select("#", ...) do Walk((select(i, ...))) end
end
-- wSkip: the border frame (handled apart).
Walk = function(root)
    if root == wSkip then return end
    SeatRegions(root:GetRegions())
    WalkChildren(root:GetChildren())
end

-- Shape and place the body mask: inside the border strips' inner corners (they
-- follow every re-snap and a scale-decoupled border), else the shape rect.
-- Only while detached: a mask must carry its texture before it is added.
local function ShapeMask(st, m, radius, cont)
    SetRounded(m, radius, st.corners, "CLAMPTOBLACKADDITIVE")
    m:ClearAllPoints()
    if cont then
        m:SetPoint("TOPLEFT", cont._left, "TOPRIGHT", 0, 0)
        m:SetPoint("BOTTOMRIGHT", cont._right, "BOTTOMLEFT", 0, 0)
    else
        m:SetAllPoints(st.rect)
    end
end

-- A shape change detaches the mask from every body texture, reshapes it and
-- seats it again.
local function ReseatMask(st, radius, cont)
    local c = cont or false
    if st.kRadius == radius and st.kCont == c and st.kCorners == st.corners then return end
    st.kRadius, st.kCont, st.kCorners = radius, c, st.corners
    local m, masked = st.mask, st.masked
    for tex in pairs(masked) do RemoveMask(tex, m) end
    ShapeMask(st, m, radius, cont)
    for tex in pairs(masked) do
        if not AddMask(tex, m) then masked[tex] = nil end
    end
end

local function MaskBody(st, roots, singles, radius, cont, skip)
    local m = st.mask
    if not m then
        m = st.owner:CreateMaskTexture()
        st.mask = m
        st.kRadius = nil
    end
    ReseatMask(st, radius, cont)
    local gen = st.gen + 1
    st.gen = gen
    local masked = st.masked
    wMasked, wMask, wGen, wSkip = masked, m, gen, skip
    for i = 1, 6 do -- fixed slots: roots may hold nils
        local root = roots[i]
        if root then Walk(root) end
    end
    for i = 1, 8 do
        local tex = singles[i]
        if tex then Seat(tex) end
    end
    wMasked, wMask, wSkip = nil, nil, nil
    -- Release textures that left the body (a bar moved out, e.g. detached).
    for tex, g in pairs(masked) do
        if g ~= gen then
            RemoveMask(tex, m)
            masked[tex] = nil
        end
    end
end

-------------------------------------------------------------------------------
--  Solid: a rounded fill with the body's exact inverse cut out of it
-------------------------------------------------------------------------------
local function SolidOff(st)
    local sd = st.solid
    if not sd or not sd.on then return end
    for i = 1, 4 do RemoveMask(sd.cont[STRIPS[i]], sd.hide) end
    sd.fill:Hide()
    sd.on = nil
end

local function SolidParts(st, cont)
    local sd = st.solids[cont]
    if sd then return sd end
    sd = { cont = cont }
    -- The fill and its hole draw their slice corners in their frame's units,
    -- as the body mask does in the owner's. A scale-decoupled container
    -- (nameplates: its strips keep whole pixels whatever the plate's scale)
    -- runs other units, so there they take a layer of their own on the border
    -- frame, at the body's scale.
    local host = cont
    if cont.IsIgnoringParentScale and cont:IsIgnoringParentScale() then
        host = CreateFrame("Frame", nil, cont:GetParent())
        host:SetAllPoints(cont)
        host:EnableMouse(false)
        sd.layer = host
    end
    local fill = host:CreateTexture(nil, "OVERLAY", nil, 7)
    ownTex[fill] = true
    sd.fill = fill
    local hole = host:CreateMaskTexture()
    hole:SetPoint("TOPLEFT", cont._left, "TOPRIGHT", 0, 0)
    hole:SetPoint("BOTTOMRIGHT", cont._right, "BOTTOMLEFT", 0, 0)
    sd.hole = hole
    local hide = cont:CreateMaskTexture()
    hide:SetTexture(MEDIA .. "hide.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    sd.hide = hide
    st.solids[cont] = sd
    return sd
end

-- radius: outer radius; inner: the body mask's radius (the hole is the same
-- nine-slice shape at the same anchors, so body and border always meet
-- without a gap, whatever size the client draws slice corners at).
local function SolidOn(st, cont, radius, inner)
    local sd = SolidParts(st, cont)
    if st.solid ~= sd then
        -- The border moved to another container: its old strips get their
        -- own look back and its fill goes.
        SolidOff(st)
        st.solid = sd
    end
    local rect = st.rect
    if sd.rect ~= rect then
        sd.fill:ClearAllPoints()
        sd.fill:SetAllPoints(rect)
        sd.hide:ClearAllPoints()
        sd.hide:SetAllPoints(rect)
        sd.rect = rect
    end
    -- The hole is reshaped only while detached (it must carry its texture
    -- before it is added).
    local corners = st.corners
    local innerKey = inner * 16 + corners
    if sd.inner ~= innerKey then
        if sd.inner then RemoveMask(sd.fill, sd.hole) end
        sd.hole:SetTexture(ROUNDED_INV[innerKey], "CLAMPTOWHITE", "CLAMPTOWHITE")
        sd.hole:SetTextureSliceMargins(inner, inner, inner, inner)
        sd.hole:SetTextureSliceMode(STRETCHED)
        AddMask(sd.fill, sd.hole)
        sd.inner = innerKey
    end
    if not sd.on then
        for i = 1, 4 do AddMask(cont[STRIPS[i]], sd.hide) end
        sd.on = true
    end
    if sd.radius ~= radius or sd.corners ~= corners then
        SetRounded(sd.fill, radius, corners)
        sd.radius, sd.corners = radius, corners
    end
    -- The layer draws where the container does.
    local layer = sd.layer
    if layer then
        local lvl = cont:GetFrameLevel()
        if layer:GetFrameLevel() ~= lvl then layer:SetFrameLevel(lvl) end
    end
    sd.fill:SetVertexColor(cont._top:GetVertexColor())
    sd.fill:Show()
end

-------------------------------------------------------------------------------
--  Glow / Shadow: the stock glow redrawn round
-------------------------------------------------------------------------------
local function GlowOff(st)
    local gl = st.glow
    if not gl or not gl.on then return end
    gl.bd:SetAlpha(1)
    gl.frame:Hide()
    gl.on = nil
end

local function GlowParts(st, border)
    local gl = st.glow
    if gl then return gl end
    local f = CreateFrame("Frame", nil, border)
    f:EnableMouse(false)
    gl = { frame = f, corner = {}, edge = {} }
    -- Corner pieces: art, size, place and crop are set per shape by GlowOn.
    for i = 1, 4 do
        local t = f:CreateTexture(nil, "BORDER")
        ownTex[t] = true
        gl.corner[i] = t
    end
    -- The edge file's left cell (outer side at u = 0) on every side: rotated
    -- for top and bottom, and turned round for the right and bottom edges so
    -- their outer side faces out too.
    for i = 1, 4 do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetTexture(GLOW_EDGE)
        ownTex[t] = true
        gl.edge[i] = t
    end
    local e = gl.edge
    e[1]:SetTexCoord(0, 0, 0.125, 0, 0, 1, 0.125, 1)     -- top
    e[2]:SetTexCoord(0.125, 0, 0, 0, 0.125, 1, 0, 1)     -- bottom
    e[3]:SetTexCoord(0, 0.125, 0, 1)                     -- left
    e[4]:SetTexCoord(0.125, 0, 0, 1)                     -- right
    st.glow = gl
    return gl
end

-- One corner piece for S (the glow's outer corner to the arc center):
-- size: the piece's side; inset: its outer corner in from the glow's; crop:
-- the share of the art shown; run: where the sides start; band: the width
-- every piece draws the glow at, centered on the outline.
local function GlowPiece(S, E, half)
    if S >= E then
        -- The band fits between the outer corner and the arc center: the
        -- nearest step's piece, sized so its outline lands on this radius
        -- round this arc center. Its band is within a few percent of the
        -- border's, and the sides take the same width, so they meet it.
        local r = S - E / 2
        local n = Clamp(floor(log(E / r / GLOW_FMIN) / GLOW_LOGSTEP + 0.5) + 1, 1, GLOW_NA)
        local fn = GLOW_FMIN * exp((n - 1) * GLOW_LOGSTEP)
        local size = r * (1 + fn / 2)
        return GLOW_CORNER[n], size, S - size, 1, S, fn * r
    end
    -- A radius under half the band: the piece spans the whole band (at most
    -- half the short side, the art cut to match), its straight parts on the
    -- sides' own line, and the sides start past it.
    local size = (half and half < E) and half or E
    return GLOW_TIGHT[Clamp(floor((S / E - 0.5) * 2 * GLOW_NB) + 1, 1, GLOW_NB)],
        size, 0, size / E, size, E
end

local function GlowOn(st, border, bd, radius)
    -- The edge size from the backdrop's own info (GetBackdrop copies it).
    local E = bd.backdropInfo and bd:GetEdgeSize()
    if not E or E <= 0 then GlowOff(st); return end
    local gl = GlowParts(st, border)
    local f = gl.frame
    -- A new border or backdrop: the old one gets its alpha back.
    if gl.bd ~= bd then
        if gl.bd then gl.bd:SetAlpha(1) end
        gl.bd = bd
        gl.S = nil
    end
    if f:GetParent() ~= border then
        f:SetParent(border)
        gl.S = nil
    end
    -- S: from the glow's outer corner to the arc center, at most half the
    -- glow's short side. A square corner takes radius 0.
    local half = HalfSide(bd)
    local S = E / 2 + radius
    if half and S > half then S = half end
    local corners = st.corners
    local lvl = bd:GetFrameLevel()
    if gl.S ~= S or gl.E ~= E or gl.half ~= half or gl.lvl ~= lvl or gl.corners ~= corners then
        gl.S, gl.E, gl.half, gl.lvl, gl.corners = S, E, half, lvl, corners
        f:ClearAllPoints()
        f:SetAllPoints(bd)
        f:SetFrameLevel(lvl)
        local path, size, inset, crop, run, band = GlowPiece(S, E, half)
        local sPath, sSize, sInset, sCrop, sRun
        if corners ~= ALL_CORNERS then
            local sS = E / 2
            if half and sS > half then sS = half end
            sPath, sSize, sInset, sCrop, sRun = GlowPiece(sS, E, half)
        end
        local runs = gl.runs
        if not runs then runs = {}; gl.runs = runs end
        for i = 1, 4 do
            local c, t = CORNERS[i], gl.corner[i]
            local p, sz, ins, cr = path, size, inset, crop
            runs[i] = run
            if bit.band(corners, c.bit) == 0 then
                p, sz, ins, cr = sPath, sSize, sInset, sCrop
                runs[i] = sRun
            end
            local tc = c.tc
            t:SetTexture(p)
            t:SetTexCoord(tc[1] * cr, tc[2] * cr, tc[3] * cr, tc[4] * cr)
            t:SetSize(sz, sz)
            t:ClearAllPoints()
            t:SetPoint(c.p, f, c.p, c.dx * ins, c.dy * ins)
        end
        -- The sides: band wide, centered on the outline (E / 2 in from the
        -- glow's edge), from one corner's run to the other's.
        local e, o = gl.edge, (E - band) / 2
        local top, bottom, left, right = e[1], e[2], e[3], e[4]
        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", f, "TOPLEFT", runs[1], -o)
        top:SetPoint("TOPRIGHT", f, "TOPRIGHT", -runs[2], -o)
        top:SetHeight(band)
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", runs[3], o)
        bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -runs[4], o)
        bottom:SetHeight(band)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", f, "TOPLEFT", o, -runs[1])
        left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", o, runs[3])
        left:SetWidth(band)
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -o, -runs[2])
        right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -o, runs[4])
        right:SetWidth(band)
    end
    local r, g, b, a = bd:GetBackdropBorderColor()
    for i = 1, 4 do
        gl.corner[i]:SetVertexColor(r, g, b, a)
        gl.edge[i]:SetVertexColor(r, g, b, a)
    end
    bd:SetAlpha(0)
    f:Show()
    gl.on = true
end

-------------------------------------------------------------------------------
--  Passes
-------------------------------------------------------------------------------
local Refit

-- Everything this owner added comes off; the state stays for the next time.
local function Clear(st)
    local m, masked = st.mask, st.masked
    for tex in pairs(masked) do RemoveMask(tex, m) end
    wipe(masked)
    st.kRadius = nil
    SolidOff(st)
    GlowOff(st)
    if st.border then byBorder[st.border] = nil end
    if st.clip then st.clip:SetClipsChildren(true); st.clip = nil end
    st.on = nil
    EllesmereUI.RegisterPxReapply(st.owner, nil)
end

local function OnBorderColor(borderFrame, r, g, b, a)
    local st = byBorder[borderFrame]
    if not st then return end
    a = a or 1
    local sd = st.solid
    if sd and sd.on then sd.fill:SetVertexColor(r, g, b, a) end
    local gl = st.glow
    if gl and gl.on then
        for i = 1, 4 do
            gl.corner[i]:SetVertexColor(r, g, b, a)
            gl.edge[i]:SetVertexColor(r, g, b, a)
        end
    end
end
EllesmereUI.RoundedBorderColor = OnBorderColor

-- The scale-dependent half of a pass: the radius the shape allows, what the
-- border draws now (Solid strips, a glow backdrop, or nothing) and the body
-- mask's radius inside the strips.
local function Fit(st)
    local border, rect = st.border, st.rect
    local radius = st.radius
    -- A radius-r mask is 2r + 1 texels square, and the client shrinks a sliced
    -- texture's corners on a region smaller than the texture: the radius stays
    -- at most (short side - 1) / 2, so the region always holds its mask.
    local half = HalfSide(rect)
    if half and half >= 1 then
        local cap = max(1, floor(half - 0.5))
        if radius > cap then radius = cap end
    end
    -- A border frame that is the owner itself hides along with the body, so
    -- its own shown flag says nothing (a nameplate cast bar between casts).
    local cont = border and (border == st.owner or border:IsShown())
        and EllesmereUI.PP.GetBorders(border)
    local edge = cont and cont._top and cont:IsShown()
        and cont._top:IsShown() and cont._snapEdge or 0
    local inner = radius
    if edge > 0 then
        -- Strip width in shape units (the container may run its own scale).
        local cs, rs = cont:GetEffectiveScale(), rect:GetEffectiveScale()
        if rs > 0 then edge = edge * cs / rs end
        inner = max(1, floor(radius - edge + 0.5))
        -- The inner rect holds the hole's and the body's masks the same way:
        -- past it their corners shrink or overlap and square their ends off,
        -- so a thin bar's body would poke out past the ring.
        if half then
            local cap = floor(half - edge - 0.5)
            if cap >= 1 and inner > cap then inner = cap end
        end
        return radius, inner, cont, nil
    end
    local bd = border and EllesmereUI._bdBorderData[border]
    local glow = st.glowStyle and bd and bd:IsShown() and bd or nil
    return radius, inner, nil, glow
end

local function Paint(st, radius, inner, cont, glow)
    if cont then SolidOn(st, cont, radius, inner) else SolidOff(st) end
    if glow then GlowOn(st, st.border, glow, radius) else GlowOff(st) end
end

-- The pixel grid moved: the strips and the glow edge took new sizes, the
-- body textures stay the same.
Refit = function(owner)
    local st = state[owner]
    if not (st and st.on) then return end
    local radius, inner, cont, glow = Fit(st)
    ReseatMask(st, inner, cont)
    Paint(st, radius, inner, cont, glow)
end

function EllesmereUI.RoundCorners(owner, radius, opts)
    if not owner then return end
    local st = state[owner]
    radius = min(floor(tonumber(radius) or 0), MAX_RADIUS)
    opts = opts or EMPTY
    local style = opts.style or "solid"
    if radius > 0 and not STYLE_OK[style] then radius = 0 end
    local corners = opts.corners and floor(tonumber(opts.corners) or ALL_CORNERS) % 16 or ALL_CORNERS
    if corners == 0 then radius = 0 end
    if radius <= 0 then
        if st and st.on then Clear(st) end
        return
    end
    if not st then
        st = { owner = owner, masked = {}, solids = {}, gen = 0 }
        state[owner] = st
    end
    if not hooked then
        hooked = true
        hooksecurefunc(EllesmereUI, "SetBorderStyleColor", OnBorderColor)
    end
    st.radius, st.corners = radius, corners
    st.glowStyle = style == "glow" or style == "shadow"
    local rect = opts.rect or owner
    if st.rect ~= rect then
        st.rect = rect
        st.kRadius = nil
    end
    local border = opts.border
    if st.border ~= border then
        if st.border then byBorder[st.border] = nil end
        st.border = border
        st.kRadius = nil
    end
    if border then byBorder[border] = st end
    local clip = opts.clip
    if st.clip ~= clip then
        if st.clip then st.clip:SetClipsChildren(true) end
        if clip then clip:SetClipsChildren(false) end
        st.clip = clip
    end
    local roots = opts.roots
    if not roots then
        roots = st.ownRoots
        if not roots then
            roots = { owner }
            st.ownRoots = roots
        end
    end
    local r, inner, cont, glow = Fit(st)
    MaskBody(st, roots, opts.textures or EMPTY, inner, cont, border)
    Paint(st, r, inner, cont, glow)
    if not st.on then
        st.on = true
        EllesmereUI.RegisterPxReapply(owner, Refit)
    end
end
