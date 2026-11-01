if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_RetailAtlas.lua
--
--  Stock atlas painting for the Blizzard Style kits.
--    EllesmereUI.StockAtlas(tex, name, ...)  in place of tex:SetAtlas(name, ...)
--    EllesmereUI.StockAtlasInfo(name)        in place of C_Texture.GetAtlasInfo
--    EllesmereUI.StockMask(mask, name, useSize)  in place of mask:SetAtlas for
--        the stock bar and portrait masks (see MASK_FILES below)
--  Retail: exactly those calls.
--
--  WoW Forever swaps many retail atlas names for its own "-c60" art, so
--  SetAtlas draws Forever art there, but the retail sheets still ship with
--  that client. A name listed below that the client swapped (its art lives
--  in another file) is drawn from its retail sheet instead: SetTexture(file)
--  + SetTexCoord(box), SetSize when the caller asked for the atlas size. The
--  sheet tier (1x / 2x) follows the client's own pick. StockAtlasInfo hands
--  back the same retail info (shared table, read-only), so mirrored art keeps
--  the file + reversed coords recipe. Everything is resolved once per name.
--
--  Callers: plain Textures only (never a MaskTexture or a StatusBar fill), and
--  every SetAtlas on a texture that can take a listed name goes through
--  StockAtlas: a sheet draw leaves texcoords behind that only StockAtlas
--  clears (a direct SetAtlas or SetTexture would sample the wrong region).
--  The WoW Forever look keeps the native frame art (its frame paths never
--  call these); its cast bar backgrounds and the nameplates'
--  uninterruptible fill come here as they do under Blizzard Style.
--
--  Also here: the WoW Forever look's window border (EllesmereUI.
--  ForeverBorder, below: our shipped flat line, or Blizzard's live art for
--  the Slim Textured Border Style), shared by the chat panel, tabs and
--  sidebar plates, the Damage Meters windows, the threat meter, the XP
--  bar's Forever style and Blizzard Style's square minimap on the Forever
--  client; its heavy sibling (EllesmereUI.ForeverHeavy: the
--  bronze frame of WoW Forever's own windows), the Heavy Bronze Border Style
--  of the chat, the Damage Meters windows and the threat meter (which wears
--  the Damage Meters windows' style), and the minimap's Forever Square; and
--  the Border Style a saved value draws on this client
--  (EllesmereUI.ForeverBorderKind).
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

-------------------------------------------------------------------------------
--  Forever border: the bronze line of the micro menu's box on the Forever
--  client ("UI-HUD-ActionBar-Frame", Forever's art: a 55-unit square sliced
--  24 a side), round any frame of ours. The art comes from one of two
--  sources with the same box and geometry:
--    - shipped (the default): our own copy of that box with a flat, even
--      bronze line (media\borders\forever-slim.blp, 128 pixels a side, the
--      box at pixels 1..111 on both axes), always there on the Forever
--      client
--    - "textured": Blizzard's live atlas, whatever art the client ships
--      for it (a weathered line with scratches, a crack and a notch); the
--      shipped file stands in where the client has no such atlas
--  That art is a FILLED box (a 60% black body inside the line), so it is
--  cut from its sheet into a hollow ring drawn at the art's own size (the
--  micro menu box's weight on every frame): four 12-unit corners, each
--  holding its whole chamfer up to where the line runs straight again (the
--  art's own corners, as the action bars draw them), the body inside the
--  chamfer hidden by a mask (media\borders\forever-slim-mask.tga, built by
--  .tools\forever-border\make_slim_mask.py); and between them four edges 6
--  units deep (1.5 clear, the 1.5-unit outer shadow, the 2-unit line and 1
--  unit of its inner shadow), the depth the mask keeps along the corners'
--  sides. Each edge is one piece stretched between its corners, as
--  Blizzard's own frame stretches this art: the shipped art's from the
--  middle of its side, the live art's from a stretch of its side clear of
--  its marks (the crack, the notch and the dark scratches; its sides are
--  also lit on a slope, so a repeated stretch would step at every repeat).
--  The ring's box is a frame of ours: whenever it changes size, a box too
--  small for two corners on an axis cuts them at its middle and drops the
--  edges between them. A frame's own body starts FOREVER_BORDER.fill in
--  from the line's outer edge (under the line's inner shadow), its square
--  corners inside the chamfers.
--    EllesmereUI.ForeverBorderOK()          the ring can be drawn (Forever
--        only; ForeverBorderKind("textured") reads "textured" only while
--        the live art exists)
--    EllesmereUI.ForeverBorder(frame, layer, sub, add, src)   the pieces,
--        on a frame of ours (add: an additive copy, where only the line
--        shows: its black body adds nothing, so its corners take no mask;
--        src "textured": Blizzard's live art, anything else the shipped
--        file)
--    EllesmereUI.ForeverBorderSeat(ring, rel, tp, x1, y1, x2, y2)   the
--        line's OUTER edge: top-left off rel's point tp (TOPLEFT when nil),
--        bottom-right off rel's BOTTOMRIGHT
--    EllesmereUI.ForeverBorderPaint(ring, r, g, b, a, desat)
--    EllesmereUI.ForeverBorderShown(ring, shown)
--    EllesmereUI.ForeverBorderDivider(frame, layer, sub)   one straight
--        piece of the shipped line, for a box split in two under one ring
--  Callers build a ring once per frame; a repaint is colour or shown only.
-------------------------------------------------------------------------------
local RING_ATLAS = "UI-HUD-ActionBar-Frame"
-- The shipped art: its file and its box's edges as texcoords (the same on
-- both axes).
local RING_FILE = "Interface\\AddOns\\EllesmereUI\\media\\borders\\forever-slim.blp"
local RING_LO, RING_HI = 1 / 128, 111 / 128
-- The corners' mask: a square two corners a side holding all four, one a
-- quadrant, so each corner's mask is that square hung from the ring box's
-- matching corner (a mask ignores texcoords: one corner could not be
-- turned into the others).
local RING_MASK = "Interface\\AddOns\\EllesmereUI\\media\\borders\\forever-slim-mask.tga"
-- In the art's units (55 a side): the line's outer edge RM in from the
-- art's edge, the corner pieces RC square (the chamfer, its tail under the
-- line and the fade of its inner shadow all end inside it), the edge pieces
-- RD deep. The shipped art's edges sample its middle, from RC in to RC from
-- its far side (the live art's sample LIVE_RUN below instead).
local RS, RM, RC, RD = 55, 3, 12, 6
EllesmereUI.FOREVER_BORDER = {
    line   = 2,         -- the line's thickness
    outer  = 1.5,       -- its outer shadow's reach past the line
    shade  = RD - RM,   -- the edges' reach inside the line's outer edge
    corner = RC - RM,   -- the corners' reach inside it (the chamfers)
    -- A body's inset from the line's outer edge: the chamfer's bronze cuts
    -- 5 units deep, so a square body corner any further out shows past it.
    fill   = 2.75,
}
-- Per edge (top, bottom, left, right), the stretch of the live art's side
-- it draws, in the art's units along that side: clear of the dark scratches
-- near the top and bottom corners, the crack high on the left side and the
-- notch low on the right, ends included, since a mark at an end would smear
-- along the whole edge (measured on Blizzard's art of build 70291 on).
local LIVE_RUN = { [5] = { 16, 39 }, [6] = { 16, 40 }, [7] = { 19, 43 }, [8] = { 12, 36 } }
-- Each piece's anchors on the ring's box (point, x, y, and a second point
-- for an edge): the corners TL, TR, BL, BR (their size and cut set by
-- CutCorners), then the top, bottom, left and right edges, each with its
-- cut as fractions of the art box (u1, u2, v1, v2), the shipped art's
-- (RING_CUT) or the live art's (LIVE_CUT).
local RING_AT, RING_CUT, LIVE_CUT
do
    local c, d = RC / RS, RD / RS
    RING_AT = {
        { "TOPLEFT", 0, 0 }, { "TOPRIGHT", 0, 0 }, { "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", 0, 0 },
        { "TOPLEFT", RC, 0, "TOPRIGHT", -RC, 0 },
        { "BOTTOMLEFT", RC, 0, "BOTTOMRIGHT", -RC, 0 },
        { "TOPLEFT", 0, -RC, "BOTTOMLEFT", 0, RC },
        { "TOPRIGHT", 0, -RC, "BOTTOMRIGHT", 0, RC },
    }
    RING_CUT = {
        [5] = { c, 1 - c, 0, d }, [6] = { c, 1 - c, 1 - d, 1 },
        [7] = { 0, d, c, 1 - c }, [8] = { 1 - d, 1, c, 1 - c },
    }
    LIVE_CUT = {}
    for i = 5, 8 do
        local cut, a, b = RING_CUT[i], LIVE_RUN[i][1] / RS, LIVE_RUN[i][2] / RS
        LIVE_CUT[i] = i <= 6 and { a, b, cut[3], cut[4] } or { cut[1], cut[2], a, b }
    end
end
local EPS, min = 0.01, math.min   -- an edge needs more than EPS of room

-- Blizzard's live atlas info, probed once (false: not the Forever client, or
-- the atlas is missing).
local liveInfo
local function LiveInfo()
    if liveInfo == nil then
        liveInfo = EllesmereUI.IS_FOREVER == true and C_Texture.GetAtlasInfo(RING_ATLAS) or false
    end
    return liveInfo
end

-- The shipped art makes the ring drawable on every Forever client.
function EllesmereUI.ForeverBorderOK()
    return EllesmereUI.IS_FOREVER == true
end

-- The corners cw x ch units: each the art's own corner, all of it (RC) or,
-- in a box too small for two, the part up to the box's middle (its mask
-- stays hung from the box's corner, so the cut keeps its shape).
local function CutCorners(ring, cw, ch)
    local L, T, W, H = ring.L, ring.T, ring.W, ring.H
    local u, v = cw / RS, ch / RS
    for i = 1, 4 do
        local u1 = (i == 2 or i == 4) and 1 - u or 0
        local v1 = i >= 3 and 1 - v or 0
        local t = ring[i]
        t:SetSize(cw, ch)
        t:SetTexCoord(L + W * u1, L + W * (u1 + u), T + H * v1, T + H * (v1 + v))
    end
    ring.cw, ring.ch = cw, ch
end

-- Each piece shown while the ring is on and its box has taken a size: the
-- corners always, an edge only with room between its corners.
local function RingShow(ring)
    local on = ring.on and ring.sized
    for i = 1, 4 do ring[i]:SetShown(on) end
    local x, y = on and ring.roomX, on and ring.roomY
    ring[5]:SetShown(x); ring[6]:SetShown(x)
    ring[7]:SetShown(y); ring[8]:SetShown(y)
end

-- The box's OnSizeChanged (w x h: the art's rect, RM past the line's outer
-- edge): the corners cut again only when their size changes (a box too
-- small for two), and the pieces shown again only when an edge's room
-- changes.
local function RingLayout(box, w, h)
    local ring = box._fvRing
    local cw, ch = min(RC, w / 2), min(RC, h / 2)
    if cw ~= ring.cw or ch ~= ring.ch then CutCorners(ring, cw, ch) end
    local roomX, roomY = w - 2 * RC > EPS, h - 2 * RC > EPS
    if ring.sized and roomX == ring.roomX and roomY == ring.roomY then return end
    ring.roomX, ring.roomY, ring.sized = roomX, roomY, true
    RingShow(ring)
end

-- The ring on `frame` (a frame of ours), seated by ForeverBorderSeat through
-- a box (a frame of ours, laid out by RingLayout) that holds the art's rect:
-- from the shipped file, or with src "textured" from Blizzard's live atlas
-- (the shipped file where the client has none), the corners, each masked
-- unless additive, and the edges. Every piece stays hidden until the box
-- first takes a size. Nil off the Forever client.
function EllesmereUI.ForeverBorder(frame, layer, sub, add, src)
    if EllesmereUI.IS_FOREVER ~= true then return nil end
    local file, L, T, R, B = RING_FILE, RING_LO, RING_LO, RING_HI, RING_HI
    local cuts = RING_CUT
    local info = src == "textured" and LiveInfo()
    if info then
        file = info.file or info.filename
        L, T, R, B = info.leftTexCoord, info.topTexCoord, info.rightTexCoord, info.bottomTexCoord
        cuts = LIVE_CUT
    end
    local W, H = R - L, B - T
    layer, sub = layer or "ARTWORK", sub or 0
    local box = CreateFrame("Frame", nil, frame)
    local ring = { box = box, on = true, L = L, T = T, W = W, H = H }
    for i = 1, 8 do
        local t = frame:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(file)
        if add then t:SetBlendMode("ADD") end
        local at = RING_AT[i]
        t:SetPoint(at[1], box, at[1], at[2], at[3])
        if at[4] then
            local cut = cuts[i]
            t:SetTexCoord(L + W * cut[1], L + W * cut[2], T + H * cut[3], T + H * cut[4])
            t:SetPoint(at[4], box, at[4], at[5], at[6])
            if i <= 6 then t:SetHeight(RD) else t:SetWidth(RD) end
        end
        t:Hide()
        ring[i] = t
    end
    CutCorners(ring, RC, RC)
    if not add then
        for i = 1, 4 do
            local m, p = frame:CreateMaskTexture(), RING_AT[i][1]
            m:SetTexture(RING_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetSize(2 * RC, 2 * RC)
            m:SetPoint(p, box, p)
            ring[i]:AddMaskTexture(m)
        end
    end
    box._fvRing = ring
    box:SetScript("OnSizeChanged", RingLayout)
    return ring
end

-- The line's outer edge (the art reaches RM past it: its clear margin and
-- outer shadow).
function EllesmereUI.ForeverBorderSeat(ring, rel, tp, x1, y1, x2, y2)
    local box = ring.box
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", rel, tp or "TOPLEFT", (x1 or 0) - RM, (y1 or 0) + RM)
    box:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", (x2 or 0) + RM, (y2 or 0) - RM)
end

function EllesmereUI.ForeverBorderPaint(ring, r, g, b, a, desat)
    desat = desat and true or false
    for i = 1, 8 do
        local t = ring[i]
        t:SetVertexColor(r, g, b, a or 1)
        t:SetDesaturated(desat)
    end
end

-- Shown or hidden as a whole; an edge without room stays hidden either way
-- (RingShow).
function EllesmereUI.ForeverBorderShown(ring, shown)
    ring.on = shown and true or false
    RingShow(ring)
end

-- A divider in the shipped line on `frame` (a frame of ours): the top edge's
-- straight middle, RD deep (its clear margin, outer shadow, the line and its
-- inner shadow, top to bottom), so the line runs 1 to 3 units above the
-- piece's bottom. The caller anchors both ends and the bottom. Nil off the
-- Forever client.
function EllesmereUI.ForeverBorderDivider(frame, layer, sub)
    if EllesmereUI.IS_FOREVER ~= true then return nil end
    local t = frame:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
    t:SetTexture(RING_FILE)
    local cut, W = RING_CUT[5], RING_HI - RING_LO
    t:SetTexCoord(RING_LO + W * cut[1], RING_LO + W * cut[2], RING_LO + W * cut[3], RING_LO + W * cut[4])
    t:SetHeight(RD)
    return t
end

-------------------------------------------------------------------------------
--  Forever window frame: the bronze rim of WoW Forever's own windows (the
--  UI-Frame-Metal nine-slice, which that client draws with its "-c60" art:
--  four corners and four edge strips made to repeat seamlessly, a soft drop
--  shadow outside the rim and a dark line inside it), the Heavy Bronze
--  Border Style beside the line above: a module draws one or the other by
--  its setting. Our own pieces on a frame of ours, at an art scale per
--  surface (FOREVER_HEAVY.k for a window; less for a tab or a button). The
--  art's top pieces also carry a window title bar under the rim: they are
--  cut to the rim, or below the bar where a surface asks for it
--  (ForeverHeavyTitle). Each edge strip is one texture repeating along its
--  length. The box between the pieces is a frame of ours: its
--  OnSizeChanged crops the corners where the box is too small for two (no
--  doubled shadow, nothing past the far corner), cuts the bottom corners
--  under the top ones and shows an edge strip only where there is room.
--  FOREVER_HEAVY is in art units (a frame at scale k draws k UI units
--  each): the outer shadow's reach, the rim with its dark line, a body's
--  inset from the rim's outer edge, and the rim with its inner shadow.
--    EllesmereUI.ForeverHeavyOK()           the art exists (Forever only)
--    EllesmereUI.ForeverHeavy(frame, layer, sub, add)   the frame on `frame`
--        (a frame of ours, its scale set first; add: the copper copy, for a
--        highlight)
--    EllesmereUI.ForeverHeavySeat(ring, rel, tp, x1, y1, x2, y2)   the
--        rim's OUTER edge in the units of the frame's parent: top-left off
--        rel's point tp (TOPLEFT when nil), bottom-right off rel's BOTTOMRIGHT
--    EllesmereUI.ForeverHeavyFill(ring, tex, rel, tp, x1, y1, x2, y2)   a
--        body under the rim (`tex`, a region on the ring's frame) from
--        FOREVER_HEAVY.fill inside the edge ForeverHeavySeat places
--    EllesmereUI.ForeverHeavyPaint(ring, r, g, b, a, desat)
--    EllesmereUI.ForeverHeavyShown(ring, shown)
--    EllesmereUI.ForeverHeavyFit(ring, w, h)   a box (w x h at the rim's
--        outer edge) too small for the rim on both sides hides it
--    EllesmereUI.ForeverHeavyTitle(ring, on)   keeps the title bar under the
--        top rim (FOREVER_HEAVY.title: its band and divider below the rim's
--        outer edge; the bar's drop shadow falls on the box below it)
--  Callers build a frame once per surface; a repaint is colour or shown only.
-------------------------------------------------------------------------------
local HEAVY_ART = {
    tl = "UI-Frame-Metal-CornerTopLeft", tr = "UI-Frame-Metal-CornerTopRight",
    bl = "UI-Frame-Metal-CornerBottomLeft", br = "UI-Frame-Metal-CornerBottomRight",
    te = "_UI-Frame-Metal-EdgeTop", be = "_UI-Frame-Metal-EdgeBottom",
    le = "!UI-Frame-Metal-EdgeLeft", re = "!UI-Frame-Metal-EdgeRight",
}
-- Measured on WoW Forever's art (art units): the rim's outer edge in from
-- the pieces' left, right, top and bottom sides (the outer shadow beyond it,
-- a deeper drop shadow below), the depth the top pieces keep (the rim and
-- its dark line; their title bar lies below), and their depth with the
-- title bar (its dark band, the bronze divider and the divider's drop
-- shadow; the side rims below it match the edge strips).
local HML, HMR, HMT, HMB, HTOP, HTITLE = 12.5, 2.5, 13, 7.5, 19, 43
EllesmereUI.FOREVER_HEAVY = {
    k      = 1,         -- a window's art scale (the art's own size)
    margin = 2,         -- the outer shadow's reach past the rim (a drop shadow below it)
    band   = 6,         -- the rim and its dark line
    -- A body's inset from the rim's outer edge: under the rim, its square
    -- corners inside the rim's 5.5-unit corner cuts.
    fill   = 3,
    shade  = 8,         -- the rim, its dark line and its inner shadow
    lift   = { 1, 0.75, 0.45, 0.6 },   -- the copper copy's tint and alpha
    -- The title bar (ForeverHeavyTitle), down from the rim's outer edge: its
    -- dark band from `band` to `bandEnd`, the divider's solid bottom at
    -- `bottom`, its drop shadow fading out by HTITLE - HMT.
    title  = { band = 6, bandEnd = 23, bottom = 27.5 },
}

-- Each piece's atlas info, probed once (false: not the Forever client, or a
-- piece is missing).
local heavyInfo
local function HeavyInfo()
    if heavyInfo == nil then
        heavyInfo = false
        if EllesmereUI.IS_FOREVER == true then
            local info = {}
            for key, name in pairs(HEAVY_ART) do
                info[key] = C_Texture.GetAtlasInfo(name)
                if not info[key] then return false end
            end
            heavyInfo = info
        end
    end
    return heavyInfo
end

function EllesmereUI.ForeverHeavyOK()
    return HeavyInfo() and true or false
end

-- A piece's texcoords: fractions u1..u2, v1..v2 of its atlas box.
local function HeavyCut(t, info, u1, u2, v1, v2)
    local L, T = info.leftTexCoord, info.topTexCoord
    local W, H = info.rightTexCoord - L, info.bottomTexCoord - T
    t:SetTexCoord(L + W * u1, L + W * u2, T + H * v1, T + H * v2)
end

-- Each piece shown while the frame is on, fits, has taken a size and (an
-- edge strip) has room between its corners.
local function HeavyShow(ring)
    local p = ring.p
    local on = ring.on and ring.fit and ring.sized
    p.tl:SetShown(on); p.tr:SetShown(on); p.bl:SetShown(on); p.br:SetShown(on)
    p.te:SetShown(on and ring.roomX); p.be:SetShown(on and ring.roomX)
    p.le:SetShown(on and ring.roomY); p.re:SetShown(on and ring.roomY)
end

-- The box's OnSizeChanged (w x h: the rim's outer edge): each corner cut at
-- the box's middle where two would overlap, the top pieces cut at the rim or
-- below the title bar (ring.top), the bottom corners no taller than the room
-- under the top ones, and each edge strip repeating (texture wrap, one
-- repeat per atlas length) over the room left between its corners.
local function HeavyLayout(box, w, h)
    local ring = box._fvHeavy
    local I, p = heavyInfo, ring.p
    local top = ring.top
    local cw, th, bh0 = I.tl.width, I.tl.height, I.bl.height
    local cl = min(cw, w / 2 + HML)
    local cr = min(cw, w / 2 + HMR)
    local bh = min(bh0, h + HMT + HMB - top)
    local gx = w + HML + HMR - cl - cr
    local gy = h + HMT + HMB - top - bh
    p.tl:SetSize(cl, top); HeavyCut(p.tl, I.tl, 0, cl / cw, 0, top / th)
    p.tr:SetSize(cr, top); HeavyCut(p.tr, I.tr, 1 - cr / cw, 1, 0, top / th)
    p.bl:SetSize(cl, bh);   HeavyCut(p.bl, I.bl, 0, cl / cw, 1 - bh / bh0, 1)
    p.br:SetSize(cr, bh);   HeavyCut(p.br, I.br, 1 - cr / cw, 1, 1 - bh / bh0, 1)
    local te, be, le, re = I.te, I.be, I.le, I.re
    p.te:SetHeight(top)
    p.te:SetTexCoord(0, gx / te.width, te.topTexCoord,
        te.topTexCoord + (te.bottomTexCoord - te.topTexCoord) * top / te.height)
    p.be:SetHeight(bh)
    p.be:SetTexCoord(0, gx / be.width,
        be.bottomTexCoord - (be.bottomTexCoord - be.topTexCoord) * bh / be.height, be.bottomTexCoord)
    p.le:SetWidth(cl)
    p.le:SetTexCoord(le.leftTexCoord,
        le.leftTexCoord + (le.rightTexCoord - le.leftTexCoord) * cl / le.width, 0, gy / le.height)
    p.re:SetWidth(cr)
    p.re:SetTexCoord(re.rightTexCoord - (re.rightTexCoord - re.leftTexCoord) * cr / re.width,
        re.rightTexCoord, 0, gy / re.height)
    ring.roomX, ring.roomY, ring.sized = gx > EPS, gy > EPS, true
    HeavyShow(ring)
end

-- The frame on `frame` (a frame of ours drawn at the art's scale), seated by
-- ForeverHeavySeat; its pieces stay hidden until the box first takes a size.
-- Nil without the art.
function EllesmereUI.ForeverHeavy(frame, layer, sub, add)
    local I = HeavyInfo()
    if not I then return nil end
    local box = CreateFrame("Frame", nil, frame)
    local ring = { box = box, k = frame:GetScale(), p = {}, on = true, fit = true, top = HTOP }
    local p = ring.p
    for key, info in pairs(I) do
        local t = frame:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
        local along = (key == "te" or key == "be") and "h" or (key == "le" or key == "re") and "v" or nil
        t:SetTexture(info.file or info.filename, along == "h" and "REPEAT" or "CLAMP",
            along == "v" and "REPEAT" or "CLAMP")
        -- Unsharpened, as Blizzard draws this layout (scaled art, no shimmer).
        t:SetTexelSnappingBias(0)
        t:SetSnapToPixelGrid(false)
        if add then
            local l = EllesmereUI.FOREVER_HEAVY.lift
            t:SetBlendMode("ADD")
            t:SetVertexColor(l[1], l[2], l[3], l[4])
        end
        t:Hide()
        p[key] = t
    end
    p.tl:SetPoint("TOPLEFT", box, "TOPLEFT", -HML, HMT)
    p.tr:SetPoint("TOPRIGHT", box, "TOPRIGHT", HMR, HMT)
    p.bl:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -HML, -HMB)
    p.br:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", HMR, -HMB)
    p.te:SetPoint("TOPLEFT", p.tl, "TOPRIGHT"); p.te:SetPoint("TOPRIGHT", p.tr, "TOPLEFT")
    p.be:SetPoint("BOTTOMLEFT", p.bl, "BOTTOMRIGHT"); p.be:SetPoint("BOTTOMRIGHT", p.br, "BOTTOMLEFT")
    p.le:SetPoint("TOPLEFT", p.tl, "BOTTOMLEFT"); p.le:SetPoint("BOTTOMLEFT", p.bl, "TOPLEFT")
    p.re:SetPoint("TOPRIGHT", p.tr, "BOTTOMRIGHT"); p.re:SetPoint("BOTTOMRIGHT", p.br, "TOPRIGHT")
    box._fvHeavy = ring
    box:SetScript("OnSizeChanged", HeavyLayout)
    return ring
end

-- The rim's outer edge (the pieces reach past it by the art's margins).
function EllesmereUI.ForeverHeavySeat(ring, rel, tp, x1, y1, x2, y2)
    local box, k = ring.box, ring.k
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", rel, tp or "TOPLEFT", (x1 or 0) / k, (y1 or 0) / k)
    box:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", (x2 or 0) / k, (y2 or 0) / k)
end

-- A body under the rim: `tex` (a region on the ring's frame) from
-- FOREVER_HEAVY.fill (art units) inside the rim's outer edge, that edge
-- given as ForeverHeavySeat takes it.
function EllesmereUI.ForeverHeavyFill(ring, tex, rel, tp, x1, y1, x2, y2)
    local k, f = ring.k, EllesmereUI.FOREVER_HEAVY.fill
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", rel, tp or "TOPLEFT", (x1 or 0) / k + f, (y1 or 0) / k - f)
    tex:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", (x2 or 0) / k - f, (y2 or 0) / k + f)
end

function EllesmereUI.ForeverHeavyPaint(ring, r, g, b, a, desat)
    desat = desat and true or false
    for _, t in pairs(ring.p) do
        t:SetVertexColor(r, g, b, a or 1)
        t:SetDesaturated(desat)
    end
end

function EllesmereUI.ForeverHeavyShown(ring, shown)
    ring.on = shown and true or false
    HeavyShow(ring)
end

-- A box (w x h at the rim's outer edge, in the frame's parent's units) that
-- cannot hold the rim on both sides shows no frame.
function EllesmereUI.ForeverHeavyFit(ring, w, h)
    local span = 2 * EllesmereUI.FOREVER_HEAVY.band * ring.k
    ring.fit = w >= span and h >= span
    HeavyShow(ring)
end

-- The top pieces cut below the window title bar they carry (on) or at the
-- rim (off); a box already sized is laid out again at once.
function EllesmereUI.ForeverHeavyTitle(ring, on)
    local top = on and HTITLE or HTOP
    if ring.top == top then return end
    ring.top = top
    if ring.sized then
        local box = ring.box
        HeavyLayout(box, box:GetWidth(), box:GetHeight())
    end
end

-------------------------------------------------------------------------------
--  Border Style: what a module's saved Border Style value draws on this
--  client, for the module to latch with its look. "heavy" (Heavy Bronze,
--  ForeverHeavy) and "textured" (Slim Textured, ForeverBorder's live art)
--  while their art exists, an unset value reading as Slim Textured (the
--  default: a stored profile keeps no default values); "slim", or either kind
--  without its art, reads "slim" (ForeverBorder's shipped line). Nil off the
--  Forever client.
-------------------------------------------------------------------------------
function EllesmereUI.ForeverBorderKind(v)
    if EllesmereUI.IS_FOREVER ~= true then return nil end
    if v == "heavy" and HeavyInfo() then return "heavy" end
    if (v == nil or v == "textured") and LiveInfo() then return "textured" end
    return "slim"
end

if not EllesmereUI.IS_FOREVER then
    function EllesmereUI.StockAtlas(tex, name, ...) return tex:SetAtlas(name, ...) end
    EllesmereUI.StockAtlasInfo = C_Texture.GetAtlasInfo
    function EllesmereUI.StockMask(mask, name, useSize) return mask:SetAtlas(name, useSize) end
    return
end

-- Retail sheets as the Forever client ships them: file id, path (presence
-- probe), pixel width, height.
local AB    = { 4613342, "Interface\\HUD\\UIActionBar",             256, 1024 }
local AB2   = { 4615764, "Interface\\HUD\\UIActionBar2x",           512, 2048 }
local MM    = { 4618651, "Interface\\HUD\\UIMinimap",               512,  512 }
local MM2   = { 4618666, "Interface\\HUD\\UIMinimap2x",             512, 1024 }
local UF    = { 4631591, "Interface\\HUD\\UIUnitFrame",            1024,  512 }
local UF2   = { 4642466, "Interface\\HUD\\UIUnitFrame2x",          2048, 1024 }
local BOSS  = { 4703659, "Interface\\HUD\\UIUnitFrameBoss",         256,  256 }
local BOSS2 = { 4703662, "Interface\\HUD\\UIUnitFrameBoss2x",       512,  512 }
local CB    = { 4505182, "Interface\\CastingBar\\UICastingBar",     512,  256 }
local CB2   = { 4505194, "Interface\\CastingBar\\UICastingBar2x",  1024,  512 }
local CDM   = { 6704514, "Interface\\HUD\\UICooldownManager",       256,  128 }
local CDM2  = { 6739577, "Interface\\HUD\\UICooldownManager2x",     512,  256 }
local PARTY = { 4681512, "Interface\\HUD\\UIPartyFrame",            256,  256 }

-- Each name's retail member (key lower case: names are case-insensitive), in
-- sheet pixels: 1x sheet, left, right, top, bottom; the 2x sheet and its box
-- when one exists; then the atlas size when it is not the 1x box. Boxes are
-- the Forever client's own records for these retail members: its 2x unit
-- frame sheet is packed differently from retail's (ToT, skull). Never list a
-- sliced (nine- or three-slice) or tiled atlas: a sheet cut loses its slicing.
local ROWS = {
    ["ui-hud-actionbar-iconframe"]                          = { AB, 181, 227, 254, 299, AB2, 359, 451, 649, 739 },
    ["ui-hud-actionbar-iconframe-addrow"]                   = { AB, 181, 232, 305, 356, AB2, 359, 461, 441, 543 },
    ["ui-hud-actionbar-iconframe-slot"]                     = { AB, 181, 245, 136, 198, AB2, 359, 487, 209, 333, 45, 45 },
    ["ui-hud-actionbar-iconframe-down"]                     = { AB, 181, 227, 521, 566, AB2, 359, 451, 881, 971 },
    ["ui-hud-actionbar-gryphon-left"]                       = { AB, 1, 179, 136, 303, AB2, 1, 357, 209, 543, 100, 94 },
    ["ui-hud-actionbar-gryphon-right"]                      = { AB, 1, 179, 305, 472, AB2, 1, 357, 545, 879, 100, 94 },
    ["ui-hud-actionbar-wyvern-left"]                        = { AB, 1, 179, 474, 641, AB2, 1, 357, 881, 1215, 100, 94 },
    ["ui-hud-actionbar-wyvern-right"]                       = { AB, 1, 179, 643, 810, AB2, 1, 357, 1217, 1551, 100, 94 },
    ["ui-hud-minimap-button"]                               = { MM, 491, 511, 100, 118, MM2, 441, 480, 402, 440 },
    ["ui-hud-unitframe-player-portraiton"]                  = { UF, 1, 199, 87, 158, UF2, 1, 397, 171, 313 },
    ["ui-hud-unitframe-target-portraiton"]                  = { UF, 1, 193, 229, 296, UF2, 1, 385, 451, 585 },
    ["ui-hud-unitframe-targetoftarget-portraiton"]          = { UF, 330, 450, 160, 209, UF2, 1113, 1353, 315, 413 },
    ["ui-hud-unitframe-target-rare-portraiton"]             = { UF, 1, 193, 298, 365, UF2, 1, 385, 587, 721 },
    ["ui-hud-unitframe-target-portraiton-type"]             = { UF, 311, 446, 260, 278, UF2, 887, 1157, 461, 497 },
    ["ui-hud-unitframe-target-highleveltarget_icon"]        = { UF, 1008, 1019, 35, 49, UF2, 2001, 2023, 261, 289 },
    ["ui-hud-unitframe-target-portraiton-boss-gold"]        = { BOSS, 1, 81, 84, 163, BOSS2, 1, 161, 165, 323 },
    ["ui-hud-unitframe-target-portraiton-boss-rare-silver"] = { BOSS, 1, 81, 165, 244, BOSS2, 1, 161, 325, 483 },
    ["ui-hud-unitframe-target-portraiton-boss-gold-winged"] = { BOSS, 1, 100, 1, 82, BOSS2, 1, 199, 1, 163 },
    ["ui-castingbar-background"]                            = { CB, 57, 266, 85, 96, CB2, 1, 423, 188, 214 },
    ["ui-castingbar-frame"]                                 = { CB, 1, 215, 31, 47, CB2, 422, 848, 1, 31 },
    ["ui-castingbar-textbox"]                               = { CB, 1, 211, 1, 29, CB2, 1, 420, 1, 58 },
    ["ui-castingbar-uninterruptable"]                       = { CB, 268, 477, 215, 226, CB2, 421, 839, 384, 406 },
    ["ui-hud-cooldownmanager-iconoverlay"]                  = { CDM, 1, 87, 1, 87, CDM2, 1, 173, 1, 173 },
    ["ui-hud-unitframe-party-portraiton"]                   = { PARTY, 123, 243, 57, 106 },
    ["ui-hud-unitframe-party-portraiton-incombat"]          = { PARTY, 123, 237, 116, 163 },
    ["ui-hud-unitframe-party-portraiton-status"]            = { PARTY, 1, 121, 116, 165 },
}

-- Whether a sheet ships with this client (memo in the sheet's slot 5).
local function Present(s)
    local v = s[5]
    if v == nil then
        v = GetFileIDFromPath(s[2]) == s[1]
        s[5] = v
    end
    return v
end

local function Info(s, l, r, t, b, w, h)
    local W, H = s[3], s[4]
    return { file = s[1], width = w, height = h,
        leftTexCoord = l / W, rightTexCoord = r / W, topTexCoord = t / H, bottomTexCoord = b / H,
        tilesHorizontally = false, tilesVertically = false }
end

-- The sheet tier the client draws at: its own pick for the pressed button
-- border, a retail name Forever leaves native (1x or 2x file). Latched once
-- logged in (the screen scale is settled by then).
local hiRes
local function HiRes()
    if hiRes ~= nil then return hiRes end
    local i = C_Texture.GetAtlasInfo("UI-HUD-ActionBar-IconFrame-Down")
    local v = (i and i.file == AB2[1]) and true or false
    if IsLoggedIn() then hiRes = v end
    return v
end

-- name -> { 1x info or false, 2x info or false } | false (native atlas).
local resolved = {}
local function Resolve(name)
    if type(name) ~= "string" then return false end
    local e = false
    local row = ROWS[strlower(name)]
    if row then
        local s1, s2 = row[1], row[6]
        local native = C_Texture.GetAtlasInfo(name)
        local nf = native and native.file
        if nf ~= s1[1] and not (s2 and nf == s2[1]) then
            local w = row[11] or (row[3] - row[2])
            local h = row[12] or (row[5] - row[4])
            local x1 = Present(s1) and Info(s1, row[2], row[3], row[4], row[5], w, h) or false
            local x2 = s2 and Present(s2) and Info(s2, row[7], row[8], row[9], row[10], w, h) or false
            if x1 or x2 then e = { x1, x2 } end
        end
    end
    resolved[name] = e
    return e
end

local function Pick(e)
    if HiRes() then return e[2] or e[1] end
    return e[1] or e[2]
end

-- Textures currently holding sheet coords (weak: never a prop on the frame).
local drawn = setmetatable({}, { __mode = "k" })

function EllesmereUI.StockAtlas(tex, name, ...)
    local e = resolved[name]
    if e == nil then e = Resolve(name) end
    if e then
        local i = Pick(e)
        local useSize, filterMode, _, wrapH, wrapV = ...
        tex:SetTexture(i.file, wrapH, wrapV, filterMode)
        tex:SetTexCoord(i.leftTexCoord, i.rightTexCoord, i.topTexCoord, i.bottomTexCoord)
        if useSize then tex:SetSize(i.width, i.height) end
        drawn[tex] = true
        return
    end
    -- Back to an atlas: clear the sheet coords first (SetAtlas can keep
    -- custom coords, reading them inside the atlas box).
    if drawn[tex] then
        drawn[tex] = nil
        tex:SetTexCoord(0, 1, 0, 1)
    end
    return tex:SetAtlas(name, ...)
end

function EllesmereUI.StockAtlasInfo(name)
    local e = resolved[name]
    if e == nil then e = Resolve(name) end
    if e then return Pick(e) end
    return C_Texture.GetAtlasInfo(name)
end

-- Bar and portrait masks (MaskTextures, in place of mask:SetAtlas): WoW
-- Forever redrew these under the retail names (build 70425: thinner rounded
-- bars, a round player portrait), so the stock looks paint the retail files,
-- which still ship with that client and fill their whole file: path (the
-- presence probe) and file id, the 2x pair where retail has one, then the
-- atlas size. A name the client still draws from the retail file stays an atlas.
local MASK_FILES = {
    ["ui-hud-unitframe-player-portraiton-bar-health-mask"] = { "Interface\\HUD\\UIUnitFramePlayerHealthMask", 4697851,
        "Interface\\HUD\\UIUnitFramePlayerHealthMask2x", 5321215, 128, 32 },
    ["ui-hud-unitframe-player-portraiton-bar-mana-mask"]   = { "Interface\\HUD\\UIUnitFramePlayerManaMask", 4697854,
        "Interface\\HUD\\UIUnitFramePlayerManaMask2x", 5321218, 128, 16 },
    ["ui-hud-unitframe-target-portraiton-bar-health-mask"] = { "Interface\\HUD\\UIUnitFrameTargetHealthMask", 4680792,
        "Interface\\HUD\\UIUnitFrameTargetHealthMask2x", 5321212, 128, 32 },
    ["ui-hud-unitframe-target-portraiton-bar-mana-mask"]   = { "Interface\\HUD\\UIUnitFrameTargetManaMask", 4680795,
        "Interface\\HUD\\UIUnitFrameTargetManaMask2x", 5321221, 256, 16 },
    ["ui-hud-unitframe-player-portrait-mask"]              = { "Interface\\HUD\\UIUnitFramePlayerPortraitMask", 4682541,
        "Interface\\HUD\\UIUnitFramePlayerPortraitMask2x", 5321198, 64, 64 },
    ["ui-hud-unitframe-party-portraiton-bar-health-mask"]  = { "Interface\\HUD\\UIPartyFramePortraitOnHealthMask", 4737301,
        false, false, 128, 16 },
    ["ui-hud-unitframe-party-portraiton-bar-mana-mask"]    = { "Interface\\HUD\\UIPartyFramePortraitOnManaMask", 4737298,
        false, false, 128, 16 },
}

-- name -> { 1x file id or false, 2x file id or false, width, height } | false.
local maskResolved = {}
local function MaskFile(name)
    local e = maskResolved[name]
    if e ~= nil then return e end
    e = false
    local row = type(name) == "string" and MASK_FILES[strlower(name)]
    if row then
        local native = C_Texture.GetAtlasInfo(name)
        local nf = native and native.file
        if nf ~= row[2] and not (row[4] and nf == row[4]) then
            local f1 = GetFileIDFromPath(row[1]) == row[2] and row[2] or false
            local f2 = row[3] and GetFileIDFromPath(row[3]) == row[4] and row[4] or false
            if f1 or f2 then e = { f1, f2, row[5], row[6] } end
        end
    end
    maskResolved[name] = e
    return e
end

function EllesmereUI.StockMask(mask, name, useSize)
    local e = MaskFile(name)
    if e then
        local file
        if HiRes() then file = e[2] or e[1] else file = e[1] or e[2] end
        mask:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        if useSize then mask:SetSize(e[3], e[4]) end
        return
    end
    return mask:SetAtlas(name, useSize)
end
