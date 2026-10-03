if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_RetailAtlas.lua
--
--  Stock atlas painting for the Blizzard Style kits.
--    EllesmereUI.StockAtlas(tex, name, ...)  in place of tex:SetAtlas(name, ...)
--    EllesmereUI.StockAtlasInfo(name)        in place of C_Texture.GetAtlasInfo
--  Retail: exactly those two calls.
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
--  ForeverBorder, below), shared by the chat panel, tabs and sidebar plates,
--  the Damage Meters windows, the threat meter and the XP bar's Forever style.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

-------------------------------------------------------------------------------
--  Forever border: the bronze line of the micro menu's box on the Forever
--  client ("UI-HUD-ActionBar-Frame", Forever's art: a 55-unit square sliced
--  24 a side), round any frame of ours. That art is a FILLED box (a 60%
--  black body inside the line), so it is cut from its sheet into a hollow
--  ring of eight pieces drawn at the art's own size (the micro menu box's
--  weight on every frame): four 8.5-unit corners holding the chamfers, and
--  four edges 6 units deep (1.5 clear, the 1.5-unit outer shadow, the
--  2-unit line and 1 unit of its inner shadow) stretched between them. A
--  frame's own body starts at the line's inner edge (FOREVER_BORDER.line
--  in from its outer edge), its square corners hidden in the chamfers'
--  shadow.
--    EllesmereUI.ForeverBorderOK()          the art exists (Forever only)
--    EllesmereUI.ForeverBorder(frame, layer, sub, add)   the pieces, on a
--        frame of ours (add: an additive copy, where only the line shows)
--    EllesmereUI.ForeverBorderSeat(ring, rel, tp, x1, y1, x2, y2)   the
--        line's OUTER edge: top-left off rel's point tp (TOPLEFT when nil),
--        bottom-right off rel's BOTTOMRIGHT
--    EllesmereUI.ForeverBorderPaint(ring, r, g, b, a, desat)
--    EllesmereUI.ForeverBorderShown(ring, shown)
--    EllesmereUI.ForeverBorderFit(ring, w, h)   a box too small for the
--        corner pieces (a thin bar) drops the edge pieces between them
--  Callers build a ring once per frame; a repaint is colour or shown only.
-------------------------------------------------------------------------------
local RING_ATLAS = "UI-HUD-ActionBar-Frame"
-- In the art's units (55 a side): the line's outer edge RM in from the
-- art's edge, the corner pieces RC square, the edge pieces RD deep. The
-- edges sample the art from RE in to RE from its far side: the span next
-- to each corner still holds the chamfer's tail (bronze under the line)
-- and the fade of its inner shadow, so only the even middle is stretched.
local RS, RM, RC, RD, RE = 55, 3, 8.5, 6, 12
EllesmereUI.FOREVER_BORDER = {
    line   = 2,         -- the line's thickness
    outer  = 1.5,       -- its outer shadow's reach past the line
    shade  = RD - RM,   -- the edges' reach inside the line's outer edge
    corner = RC - RM,   -- the corners' reach inside it (the chamfers)
}
-- Each piece as fractions of the art box (u1, u2, v1, v2) and its anchors
-- on the ring's box (point, x, y, and a second point for an edge): the
-- corners TL, TR, BL, BR, then the top, bottom, left and right edges.
local RING_CUT, RING_AT
do
    local c, d, e = RC / RS, RD / RS, RE / RS
    RING_CUT = {
        { 0, c, 0, c }, { 1 - c, 1, 0, c }, { 0, c, 1 - c, 1 }, { 1 - c, 1, 1 - c, 1 },
        { e, 1 - e, 0, d }, { e, 1 - e, 1 - d, 1 }, { 0, d, e, 1 - e }, { 1 - d, 1, e, 1 - e },
    }
    RING_AT = {
        { "TOPLEFT", 0, 0 }, { "TOPRIGHT", 0, 0 }, { "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", 0, 0 },
        { "TOPLEFT", RC, 0, "TOPRIGHT", -RC, 0 },
        { "BOTTOMLEFT", RC, 0, "BOTTOMRIGHT", -RC, 0 },
        { "TOPLEFT", 0, -RC, "BOTTOMLEFT", 0, RC },
        { "TOPRIGHT", 0, -RC, "BOTTOMRIGHT", 0, RC },
    }
end

-- The art's atlas info, probed once (false: not the Forever client, or the
-- art is missing).
local ringInfo
local function RingInfo()
    if ringInfo == nil then
        ringInfo = EllesmereUI.IS_FOREVER == true and C_Texture.GetAtlasInfo(RING_ATLAS) or false
    end
    return ringInfo
end

function EllesmereUI.ForeverBorderOK()
    return RingInfo() and true or false
end

-- The eight pieces on `frame` (a frame of ours), seated by ForeverBorderSeat
-- through an empty texture that holds the art's rect. Nil without the art.
function EllesmereUI.ForeverBorder(frame, layer, sub, add)
    local info = RingInfo()
    if not info then return nil end
    local file = info.file or info.filename
    local L, T = info.leftTexCoord, info.topTexCoord
    local W, H = info.rightTexCoord - L, info.bottomTexCoord - T
    local box = frame:CreateTexture()
    local ring = { box = box }
    for i = 1, 8 do
        local t = frame:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
        t:SetTexture(file)
        local cut, at = RING_CUT[i], RING_AT[i]
        t:SetTexCoord(L + W * cut[1], L + W * cut[2], T + H * cut[3], T + H * cut[4])
        if add then t:SetBlendMode("ADD") end
        t:SetPoint(at[1], box, at[1], at[2], at[3])
        if at[4] then
            t:SetPoint(at[4], box, at[4], at[5], at[6])
            if i <= 6 then t:SetHeight(RD) else t:SetWidth(RD) end
        else
            t:SetSize(RC, RC)
        end
        ring[i] = t
    end
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

function EllesmereUI.ForeverBorderShown(ring, shown)
    shown = shown and true or false
    for i = 1, 8 do ring[i]:SetShown(shown) end
end

-- A ring round a box (w x h at the line's outer edge) shorter or narrower
-- than its two corner pieces: the side or top and bottom edge pieces, which
-- would span a negative length there, hide and the overlapping corners draw
-- the line alone.
function EllesmereUI.ForeverBorderFit(ring, w, h)
    local span = 2 * (RC - RM)
    local wide, tall = w >= span, h >= span
    ring[5]:SetShown(wide); ring[6]:SetShown(wide)
    ring[7]:SetShown(tall); ring[8]:SetShown(tall)
end

if not EllesmereUI.IS_FOREVER then
    function EllesmereUI.StockAtlas(tex, name, ...) return tex:SetAtlas(name, ...) end
    EllesmereUI.StockAtlasInfo = C_Texture.GetAtlasInfo
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
