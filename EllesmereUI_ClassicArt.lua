if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_ClassicArt.lua
--
--  Classic WoW UI: the vanilla cast bar frame (Interface\CastingBar\
--  UI-CastingBar-Border, a 256x64 sheet drawn round a 195x13 bar) as a
--  nine-slice round any bar. Measured on the sheet: the top rim is opaque
--  on rows 22..27 and the bottom rim on rows 37..41, each with a soft
--  shadow fading into the window; the end caps' vertical rims sit on columns
--  27..33 and 222..228; and the window itself is NOT clear -- it carries a
--  13% black tint over the whole bar (alpha 34) plus those inner shadows,
--  which is what makes a vanilla bar read recessed. The sheet is cut at
--  columns 16 | 48 | 208 | 240 and rows 16 | 28 | 37 | 48: two 32-column
--  end caps with the middle between, each split into the 12-row top band
--  (margin + rim), the 9-row window band (shadow, clear, shadow) and the
--  11-row bottom band (rim + fade + margin). Caps and rim bands draw at the
--  sheet's own pixel size (k = 1) and only the window band stretches to the
--  bar, so a thin bar and a tall one wear the same weight of frame; the
--  window's centre piece IS drawn (its tint over the fill is the look). A
--  vertical bar turns every piece a quarter turn counter-clockwise (the
--  art's top rim along the bar's left, its right cap at the bar's top).
--  Shared by the unit frame and resource bar cast bars, the health / power
--  / class resource bars and the tracked buff bars, each of which scales it
--  by its own Border Size percentage (CF.ScaleK).
--
--  Cost: nine textures created once per bar, re-anchored only when the rect,
--  scale or orientation changes (memo on the piece table); nothing runs while
--  the style is off (no caller reaches it).
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

local FILE = "Interface\\CastingBar\\UI-CastingBar-Border"
-- Sheet cut lines as texcoords (columns 16, 48, 208, 240 of 256; rows 16,
-- 28, 37, 48 of 64).
local X0, X1, X2, X3 = 0.0625, 0.1875, 0.8125, 0.9375
local Y0, Y1, Y2, Y3 = 0.25, 0.4375, 0.578125, 0.75
-- Piece sizes in sheet pixels: cap width; top and bottom band heights.
local CAP, TOP, BOT = 32, 12, 11
-- The frame's reach beyond the bar it is drawn round: the caps overhang the
-- bar's ends by 14.5, the top band sits on the bar's top edge and the bottom
-- band hangs under its bottom edge.
local OVER_L, OVER_R, OVER_T, OVER_B = 14.5, 14.5, TOP, BOT

local CF = {}
EllesmereUI.ClassicFrame = CF
CF.FILE = FILE
CF.OVER_L, CF.OVER_R, CF.OVER_T, CF.OVER_B = OVER_L, OVER_R, OVER_T, OVER_B

-- A bar's frame size: the percentage of the sheet's own size its Border Size
-- slider stores on the bar's settings (nil = BORDER_DEFAULT), as the scale k
-- Seat and Pad take. Caps, rims and reach all scale together.
CF.BORDER_DEFAULT = 60
function CF.ScaleK(pct)
    return (pct or CF.BORDER_DEFAULT) / 100
end

-- How far the frame's VISIBLE rim reaches past the bar, in sheet pixels: the
-- caps' vertical rims start at columns 27 and 228, 3.5 outside the bar's ends
-- (30.5 and 225.5); the top rim's rows 22..27 sit 6 above the bar and the
-- bottom rim's rows 37..41 hang 5 below it. The caps' transparent margin (the
-- rest of OVER_L / OVER_R) is not frame a player sees.
local RIM_L, RIM_R, RIM_T, RIM_B = 3.5, 3.5, 6, 5

-- The frame's visible rim beyond a bar's rect at scale k, for size matching
-- (a matched element lines up with the rim, not the art's margin): extra
-- width, extra height.
function CF.Pad(k, vertical)
    k = k or 1
    if vertical then return (RIM_T + RIM_B) * k, (RIM_L + RIM_R) * k end
    return (RIM_L + RIM_R) * k, (RIM_T + RIM_B) * k
end

-- Piece indices.
local TL, T, TR, L, C, R, BL, B, BR = 1, 2, 3, 4, 5, 6, 7, 8, 9
local N = 9

-- Nine textures on `parent` at layer/sublevel, created once; keep the table
-- and hand it back to Seat.
function CF.Create(parent, layer, sub)
    local p = {}
    for i = 1, N do
        local t = parent:CreateTexture(nil, layer or "OVERLAY", nil, sub or 2)
        t:SetTexture(FILE)
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        p[i] = t
    end
    return p
end

function CF.SetShown(p, shown)
    for i = 1, N do p[i]:SetShown(shown and true or false) end
end

-- A sheet sub-rectangle on a piece: upright, or turned a quarter turn
-- counter-clockwise (the sub-rectangle's top edge lands on the piece's left).
local function Coords(t, a, b, c, d, turned)
    if turned then
        t:SetTexCoord(b, c, a, c, b, d, a, d)
    else
        t:SetTexCoord(a, b, c, d)
    end
end

-- Lays the frame round `rect` at scale k (1 = the sheet's pixels). Memoized
-- on rect, k and orientation; every layout pass may call it.
function CF.Seat(p, rect, k, vertical)
    if not (p and rect) then return end
    k = k or 1
    vertical = vertical and true or false
    if p._rect == rect and p._k == k and p._vert == vertical then return end
    p._rect, p._k, p._vert = rect, k, vertical
    for i = 1, N do p[i]:ClearAllPoints() end
    local cap, top, bot = CAP * k, TOP * k, BOT * k
    if not vertical then
        Coords(p[TL], X0, X1, Y0, Y1); p[TL]:SetSize(cap, top)
        p[TL]:SetPoint("TOPLEFT", rect, "TOPLEFT", -OVER_L * k, OVER_T * k)
        Coords(p[TR], X2, X3, Y0, Y1); p[TR]:SetSize(cap, top)
        p[TR]:SetPoint("TOPRIGHT", rect, "TOPRIGHT", OVER_R * k, OVER_T * k)
        Coords(p[T], X1, X2, Y0, Y1); p[T]:SetHeight(top)
        p[T]:SetPoint("TOPLEFT", p[TL], "TOPRIGHT", 0, 0)
        p[T]:SetPoint("TOPRIGHT", p[TR], "TOPLEFT", 0, 0)
        Coords(p[BL], X0, X1, Y2, Y3); p[BL]:SetSize(cap, bot)
        p[BL]:SetPoint("BOTTOMLEFT", rect, "BOTTOMLEFT", -OVER_L * k, -OVER_B * k)
        Coords(p[BR], X2, X3, Y2, Y3); p[BR]:SetSize(cap, bot)
        p[BR]:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", OVER_R * k, -OVER_B * k)
        Coords(p[B], X1, X2, Y2, Y3); p[B]:SetHeight(bot)
        p[B]:SetPoint("BOTTOMLEFT", p[BL], "BOTTOMRIGHT", 0, 0)
        p[B]:SetPoint("BOTTOMRIGHT", p[BR], "BOTTOMLEFT", 0, 0)
        -- The window band stretches to the bar's height between the rims.
        Coords(p[L], X0, X1, Y1, Y2)
        p[L]:SetPoint("TOPLEFT", p[TL], "BOTTOMLEFT", 0, 0)
        p[L]:SetPoint("BOTTOMRIGHT", p[BL], "TOPRIGHT", 0, 0)
        Coords(p[R], X2, X3, Y1, Y2)
        p[R]:SetPoint("TOPLEFT", p[TR], "BOTTOMLEFT", 0, 0)
        p[R]:SetPoint("BOTTOMRIGHT", p[BR], "TOPRIGHT", 0, 0)
        Coords(p[C], X1, X2, Y1, Y2)
        p[C]:SetPoint("TOPLEFT", p[L], "TOPRIGHT", 0, 0)
        p[C]:SetPoint("BOTTOMRIGHT", p[R], "BOTTOMLEFT", 0, 0)
    else
        -- Turned: the art's top band runs along the bar's left (width top),
        -- its bottom band along the right (width bot), its right cap sits at
        -- the bar's top and its left cap at the bottom (height cap).
        Coords(p[TR], X2, X3, Y0, Y1, true); p[TR]:SetSize(top, cap)
        p[TR]:SetPoint("TOPLEFT", rect, "TOPLEFT", -OVER_T * k, OVER_R * k)
        Coords(p[TL], X0, X1, Y0, Y1, true); p[TL]:SetSize(top, cap)
        p[TL]:SetPoint("BOTTOMLEFT", rect, "BOTTOMLEFT", -OVER_T * k, -OVER_L * k)
        Coords(p[T], X1, X2, Y0, Y1, true); p[T]:SetWidth(top)
        p[T]:SetPoint("TOPLEFT", p[TR], "BOTTOMLEFT", 0, 0)
        p[T]:SetPoint("BOTTOMLEFT", p[TL], "TOPLEFT", 0, 0)
        Coords(p[BR], X2, X3, Y2, Y3, true); p[BR]:SetSize(bot, cap)
        p[BR]:SetPoint("TOPRIGHT", rect, "TOPRIGHT", OVER_B * k, OVER_R * k)
        Coords(p[BL], X0, X1, Y2, Y3, true); p[BL]:SetSize(bot, cap)
        p[BL]:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", OVER_B * k, -OVER_L * k)
        Coords(p[B], X1, X2, Y2, Y3, true); p[B]:SetWidth(bot)
        p[B]:SetPoint("TOPRIGHT", p[BR], "BOTTOMRIGHT", 0, 0)
        p[B]:SetPoint("BOTTOMRIGHT", p[BL], "TOPRIGHT", 0, 0)
        -- The window band stretches to the bar's width between the rims.
        Coords(p[R], X2, X3, Y1, Y2, true)
        p[R]:SetPoint("TOPLEFT", p[TR], "TOPRIGHT", 0, 0)
        p[R]:SetPoint("BOTTOMRIGHT", p[BR], "BOTTOMLEFT", 0, 0)
        Coords(p[L], X0, X1, Y1, Y2, true)
        p[L]:SetPoint("TOPLEFT", p[TL], "TOPRIGHT", 0, 0)
        p[L]:SetPoint("BOTTOMRIGHT", p[BL], "BOTTOMLEFT", 0, 0)
        Coords(p[C], X1, X2, Y1, Y2, true)
        p[C]:SetPoint("TOPLEFT", p[R], "BOTTOMLEFT", 0, 0)
        p[C]:SetPoint("BOTTOMRIGHT", p[L], "TOPRIGHT", 0, 0)
    end
    for i = 1, N do p[i]:Show() end
end
