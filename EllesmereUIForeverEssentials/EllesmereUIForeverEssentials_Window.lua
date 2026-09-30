if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_Window.lua  (WoW Forever only)
--  The threat meter's window chrome, built to behave like a Damage Meters
--  window: glyph header buttons (their menus are the shared context menu in
--  the Damage Meters look), a lock icon and a resize grip that fade in while
--  the window is hovered, header drag with edge snapping to the shown Damage
--  Meters windows, and grip resize with size snapping.
--  The ThreatMeter file (listed after this one) owns the settings and hands
--  its storage in through a host table (AttachChrome).
--
--  ns.Look holds the painters for every region a stock look (Global Settings
--  > Style) draws differently: window and header backgrounds, the header
--  line, the header glyphs and their hover, the lock art, the bar fill's
--  seat and background, a per-row restyle hook, the title's accent colour
--  and the menus' look. The EUI look, the two stock looks and Blizzard
--  Style's WoW Forever variant are set here; ns.UseLook copies a stock
--  look's entries in (never replacing the table) before the first surface
--  is built.
-------------------------------------------------------------------------------
local _, module = ...
module.ThreatMeter = module.ThreatMeter or {}
local ns = module.ThreatMeter
local EUI = EllesmereUI

local MEDIA = "Interface\\AddOns\\EllesmereUIForeverEssentials\\Media\\"
local RESIZE_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\resize_element.png"
local MIN_W, MIN_H = 150, 50
local SNAP_DIST = 6
local ICON_ALPHA, ICON_HOVER_ALPHA = 0.4, 0.9
local TEXT_ALPHA = 0.65
local FADE_TIME = 0.12
local HOVER_POLL = 0.1
ns.MIN_W, ns.MIN_H = MIN_W, MIN_H

-- The Damage Meters windows the meter snaps to. Read only: the meter never
-- changes them, and they never snap to the meter.
local DM_ADDON = "EllesmereUIDamageMeters"
local DM_FRAME_NAMES = {}
for i = 1, 5 do DM_FRAME_NAMES[i] = "EllesmereUIDMFrame" .. i end

-- Top-left corner of a frame, nil when it has no plain geometry.
local function Corner(f)
    local left, top = f:GetLeft(), f:GetTop()
    if issecretvalue(left) or issecretvalue(top) then return nil end
    if left and top then return left, top end
end
ns.WindowCorner = Corner

-------------------------------------------------------------------------------
--  Look: the EUI look's painters.
--    inset       how far the header and rows sit inside the window
--    iconPad     gap between header buttons (the glyphs carry their own margin)
--    stock       true for a stock look: no EUI window or bar borders, no
--                configurable header line
--    IconSize(size)                 header button size for a configured size
--    WindowBg(tex, r, g, b, a)
--    HeaderBg(tex, r, g, b, a, winR, winG, winB)   the window colour trails
--    HeaderRail(h)                  extra height the look's header band adds
--                                   under a header h tall (the title and
--                                   buttons stay centred on the h above it)
--    HeaderLine(tex)                true when it painted the header line
--    HeaderIcon(btn)                paints btn.icon for btn.key / btn.file
--    SeatHeaderIcon(btn, size)      after a header button is resized
--    HeaderHover(btn, hovered)
--    LockIcon(btn, locked)          may resize the button for other art
--    SeatFill(row, iconWidth, dm)   anchors the bar fill in its row past the
--                                   icons; returns its left and right insets
--    RowBg(tex, r, g, b, a)         a bar's background colour
--    RowStyled(row, dm)             after a bar's fonts, texture and border
--    titleColor  the title's colour in place of the accent (nil: the accent)
--    menuLook    the header menus' look (EllesmereUI.ShowContextMenu)
-------------------------------------------------------------------------------
local Look = { inset = 0, iconPad = -2, stock = false, menuLook = "meter" }
ns.Look = Look

function Look.IconSize(size) return size end
function Look.WindowBg(tex, r, g, b, a) tex:SetColorTexture(r, g, b, a) end
function Look.HeaderBg(tex, r, g, b, a) tex:SetColorTexture(r, g, b, a) end
function Look.HeaderRail() return 0 end
function Look.HeaderLine() return false end
function Look.HeaderIcon(btn)
    local icon = btn.icon
    icon:SetTexture(MEDIA .. btn.file)
    icon:SetDesaturated(true)
    icon:SetVertexColor(1, 1, 1, ICON_ALPHA)
end
function Look.SeatHeaderIcon() end
function Look.HeaderHover(btn, hovered)
    btn.icon:SetVertexColor(1, 1, 1, hovered and ICON_HOVER_ALPHA or ICON_ALPHA)
end
function Look.LockIcon(btn, locked)
    btn.icon:SetTexture(MEDIA .. (locked and "dm_locked.png" or "dm_unlocked.png"))
end
function Look.SeatFill(row, iconWidth)
    local fill = row.fill
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", row, "TOPLEFT", iconWidth, 0)
    fill:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    return iconWidth, 0
end
function Look.RowBg(tex, r, g, b, a) tex:SetColorTexture(r, g, b, a) end
function Look.RowStyled() end
local GlyphIcon, GlyphHover = Look.HeaderIcon, Look.HeaderHover

-------------------------------------------------------------------------------
--  Stock looks (Global Settings > Style), the Damage Meters window's two.
--  Blizzard Style: the stock meter's header and bar art over a flat black
--  body with a softer top band, the EUI glyphs kept. Classic WoW UI: the
--  tiled tooltip background inside the vanilla chat tab's border, a lighter
--  band of the same tile under a rim-grey hairline as the header, vanilla
--  art on the cog and lock, smaller header buttons with a gap between them.
--  Neither draws the EUI window or bar borders. ns.UseLook installs one
--  before the first surface is built; each region's art is made once.
-------------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8X8"
local windowArt = setmetatable({}, { __mode = "k" })  -- window bg texture -> its parts
local rowArt = setmetatable({}, { __mode = "k" })     -- row -> its bevel and edge
local iconArt = setmetatable({}, { __mode = "k" })    -- header button -> its art entry
local tiled = setmetatable({}, { __mode = "k" })      -- textures already set to tile

-- Whether this client has an atlas, checked once per name: a missing piece
-- falls back to the EUI paint (header, bar track) or is left out (edge).
local atlasOK = {}
local function HasAtlas(name)
    local ok = atlasOK[name]
    if ok == nil then
        ok = C_Texture.GetAtlasInfo(name) ~= nil
        atlasOK[name] = ok
    end
    return ok
end

-- A white base for a gradient, off the pixel grid so a thin band stays smooth.
local function GradientBase(tex)
    tex:SetTexture(WHITE)
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
end

local BLIZZ_HEADER = "ui-damagemeters-header-bar"
local BLIZZ_TRACK = "ui-damagemeters-bar-shadowbg"
local BLIZZ_EDGE = "ui-damagemeters-bar-shadowedge"
local shade  -- gradient colours, made when the look is installed

local Blizzard = { stock = true }

-- A 20px top band from half the body's strength up to it, over a flat black
-- body, both hung off the bg texture's rect (which paints nothing). The
-- configured colour is not used; its opacity is.
function Blizzard.WindowBg(tex, _, _, _, a)
    local parts = windowArt[tex]
    if not parts then
        local parent = tex:GetParent()
        local layer, sub = tex:GetDrawLayer()
        parts = {}
        for i = 1, 2 do
            parts[i] = parent:CreateTexture(nil, layer, nil, sub)
            GradientBase(parts[i])
        end
        parts[1]:SetPoint("TOPLEFT", tex, "TOPLEFT", 0, 0)
        parts[1]:SetPoint("TOPRIGHT", tex, "TOPRIGHT", 0, 0)
        parts[1]:SetHeight(20)
        parts[2]:SetPoint("TOPLEFT", tex, "TOPLEFT", 0, -20)
        parts[2]:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 0, 0)
        windowArt[tex] = parts
        tex:SetColorTexture(0, 0, 0, 0)
    end
    local body = 245 / 255 * a
    shade.lo:SetRGBA(0, 0, 0, body)
    shade.hi:SetRGBA(0, 0, 0, body * 0.5)
    -- VERTICAL runs bottom to top.
    parts[1]:SetGradient("VERTICAL", shade.lo, shade.hi)
    parts[2]:SetGradient("VERTICAL", shade.lo, shade.lo)
end

-- The header colour is not used; its opacity is.
function Blizzard.HeaderBg(tex, r, g, b, a)
    if HasAtlas(BLIZZ_HEADER) then
        tex:SetAtlas(BLIZZ_HEADER)
        tex:SetVertexColor(1, 1, 1, a)
    else
        tex:SetColorTexture(r, g, b, a)
    end
end

-- The stock track (set up with the row's art) takes no colour.
function Blizzard.RowBg(tex, r, g, b, a)
    if HasAtlas(BLIZZ_TRACK) then return end
    tex:SetColorTexture(r, g, b, a)
end

-- The stock track 2px outside the fill and its edge highlight over it, set
-- up once per row (WoW Forever wears it too: a bar texture, not frame art).
local function BlizzTrack(row, art)
    local fill = row.fill
    if HasAtlas(BLIZZ_TRACK) then
        local bg = row.bg
        bg:SetAtlas(BLIZZ_TRACK)
        bg:SetVertexColor(1, 1, 1, 1)
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", fill, "TOPLEFT", -2, 2)
        bg:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 2, -2)
    end
    if HasAtlas(BLIZZ_EDGE) then
        local edge = fill:CreateTexture(nil, "OVERLAY", nil, 6)
        edge:SetAtlas(BLIZZ_EDGE)
        edge:SetPoint("TOPLEFT", fill, "TOPLEFT", -2, 2)
        edge:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 2, -2)
        art.edge = edge
    end
end

-- The user's bar texture keeps its colour; the bevel the stock fill bakes in
-- is drawn over the filled part (four gradient strips on the fill texture,
-- so they follow the value), with the track under the fill. The strips are
-- sized from the fill's height and re-anchor only when the fill texture
-- object (a path change can make a new one) or that height changes. The fill
-- fades by its colour's alpha, so its art fades with it.
function Blizzard.RowStyled(row, dm)
    local fill = row.fill
    local art = rowArt[row]
    if not art then
        art = {}
        for i = 1, 4 do
            art[i] = fill:CreateTexture(nil, "OVERLAY", nil, -3)
            GradientBase(art[i])
        end
        -- VERTICAL runs bottom to top, HORIZONTAL left to right.
        art[1]:SetGradient("VERTICAL", shade.clear, shade.top)
        art[2]:SetGradient("VERTICAL", shade.bottom, shade.clear)
        art[3]:SetGradient("HORIZONTAL", shade.ends, shade.clear)
        art[4]:SetGradient("HORIZONTAL", shade.clear, shade.ends)
        BlizzTrack(row, art)
        rowArt[row] = art
    end
    local ft, h = fill:GetStatusBarTexture(), dm.barHeight
    if ft and (art.tex ~= ft or art.h ~= h) then
        art.tex, art.h = ft, h
        local top = math.max(2, math.floor(h * 0.2))
        local bottom = math.max(1, math.floor(h * 0.1))
        local ends = math.max(2, math.floor(h * 0.15))
        local s = art[1]
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", ft, "TOPLEFT", 0, 0)
        s:SetPoint("TOPRIGHT", ft, "TOPRIGHT", 0, 0)
        s:SetHeight(top)
        s = art[2]
        s:ClearAllPoints()
        s:SetPoint("BOTTOMLEFT", ft, "BOTTOMLEFT", 0, 0)
        s:SetPoint("BOTTOMRIGHT", ft, "BOTTOMRIGHT", 0, 0)
        s:SetHeight(bottom)
        s = art[3]
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", ft, "TOPLEFT", 0, 0)
        s:SetPoint("BOTTOMLEFT", ft, "BOTTOMLEFT", 0, 0)
        s:SetWidth(ends)
        s = art[4]
        s:ClearAllPoints()
        s:SetPoint("TOPRIGHT", ft, "TOPRIGHT", 0, 0)
        s:SetPoint("BOTTOMRIGHT", ft, "BOTTOMRIGHT", 0, 0)
        s:SetWidth(ends)
    end
    local a = dm.barFillAlpha
    for i = 1, 4 do art[i]:SetAlpha(a) end
    if art.edge then art.edge:SetAlpha(a) end
end

local CLASSIC_TILE = "Interface\\Tooltips\\UI-Tooltip-Background"
local CLASSIC_EDGE = "Interface\\ChatFrame\\ChatFrameTab"
local ART_IDLE, ART_HOVER = 0.85, 1
-- Vanilla art cropped to what it draws (the lock sheets are 32x32 with the
-- button at columns 6..24, rows 7..24); scale insets it in its button.
local CLASSIC_HDR_ART = {
    settings = { file = "Interface\\Icons\\Trade_Engineering", crop = 0.08, scale = 0.9 },
}
local CLASSIC_LOCKED = { file = "Interface\\Buttons\\LockButton-Locked-Up",
    l = 0.1875, r = 0.78125, t = 0.21875, b = 0.78125 }
local CLASSIC_UNLOCKED = { file = "Interface\\Buttons\\LockButton-Unlocked-Up",
    l = 0.1875, r = 0.78125, t = 0.21875, b = 0.78125 }
-- The chat tab's border cut from its 64x32 sheet, { point, left, right, top,
-- bottom }: 5x5 corners (the bottom ones are the top ones flipped), edges
-- stretched between them (a cut from a sheet cannot tile).
local CLASSIC_EDGE_UV = {
    { "TOPLEFT",     0.03125,  0.109375, 0.28125, 0.4375  },
    { "TOPRIGHT",    0.890625, 0.96875,  0.28125, 0.4375  },
    { "BOTTOMLEFT",  0.03125,  0.109375, 0.4375,  0.28125 },
    { "BOTTOMRIGHT", 0.890625, 0.96875,  0.4375,  0.28125 },
    { "TOP",         0.375,    0.5,      0.28125, 0.4375  },
    { "BOTTOM",      0.375,    0.5,      0.4375,  0.28125 },
    { "LEFT",        0.03125,  0.109375, 0.625,   0.75    },
    { "RIGHT",       0.890625, 0.96875,  0.625,   0.75    },
}

-- The tiled tooltip background tinted r, g, b, a (the file is near-white).
local function Tile(tex, r, g, b, a)
    if not tiled[tex] then
        tiled[tex] = true
        tex:SetHorizTile(true)
        tex:SetVertTile(true)
        tex:SetTexture(CLASSIC_TILE, "REPEAT", "REPEAT")
    end
    tex:SetVertexColor(r, g, b, a)
end

local function PaintArt(tex, art)
    tex:SetDesaturated(false)
    tex:SetTexture(art.file)
    if art.crop then
        tex:SetTexCoord(art.crop, 1 - art.crop, art.crop, 1 - art.crop)
    else
        tex:SetTexCoord(art.l, art.r, art.t, art.b)
    end
    tex:SetVertexColor(ART_IDLE, ART_IDLE, ART_IDLE, 1)
end

local Classic = { inset = 5, iconPad = 2, stock = true }

function Classic.IconSize(size)
    return math.floor(size * 0.85 + 0.5)
end

-- The window wears the whole box: the tile from under the bevel (the rim's
-- corner pixels round its corners) and the eight edge pieces along the
-- inside of the window's rect, all regions of the window, so every child
-- draws above them. The bg texture itself paints nothing.
function Classic.WindowBg(tex, r, g, b, a)
    local tile = windowArt[tex]
    if not tile then
        local win = tex:GetParent()
        tile = win:CreateTexture(nil, "BACKGROUND", nil, -8)
        tile:SetPoint("TOPLEFT", win, "TOPLEFT", 3, -3)
        tile:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -3, 3)
        local p = {}
        for i = 1, #CLASSIC_EDGE_UV do
            local uv = CLASSIC_EDGE_UV[i]
            local t = win:CreateTexture(nil, "BORDER")
            t:SetTexture(CLASSIC_EDGE)
            t:SetTexCoord(uv[2], uv[3], uv[4], uv[5])
            if i <= 4 then
                t:SetSize(5, 5)
                t:SetPoint(uv[1], win, uv[1], 0, 0)
            end
            p[uv[1]] = t
        end
        p.TOP:SetPoint("TOPLEFT", p.TOPLEFT, "TOPRIGHT", 0, 0)
        p.TOP:SetPoint("BOTTOMRIGHT", p.TOPRIGHT, "BOTTOMLEFT", 0, 0)
        p.BOTTOM:SetPoint("TOPLEFT", p.BOTTOMLEFT, "TOPRIGHT", 0, 0)
        p.BOTTOM:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "BOTTOMLEFT", 0, 0)
        p.LEFT:SetPoint("TOPLEFT", p.TOPLEFT, "BOTTOMLEFT", 0, 0)
        p.LEFT:SetPoint("BOTTOMRIGHT", p.BOTTOMLEFT, "TOPRIGHT", 0, 0)
        p.RIGHT:SetPoint("TOPLEFT", p.TOPRIGHT, "BOTTOMLEFT", 0, 0)
        p.RIGHT:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "TOPRIGHT", 0, 0)
        windowArt[tex] = tile
        tex:SetColorTexture(0, 0, 0, 0)
    end
    Tile(tile, r, g, b, a)
end

-- A lighter band of the window's tile (the header colour is not used; its
-- opacity is), lifted so a black window still gets a visible band.
function Classic.HeaderBg(tex, _, _, _, a, winR, winG, winB)
    Tile(tex, math.min(1, winR * 1.6 + 0.05), math.min(1, winG * 1.6 + 0.05),
        math.min(1, winB * 1.6 + 0.05), a)
end

-- One physical pixel in the rim's grey, whatever the header line settings say.
function Classic.HeaderLine(tex)
    local PP = EUI.PP
    tex:SetHeight(PP.Scale(PP.mult))
    tex:SetColorTexture(0.41, 0.41, 0.41, 1)
    tex:Show()
    return true
end

function Classic.HeaderIcon(btn)
    local art = CLASSIC_HDR_ART[btn.key]
    if not art then return GlyphIcon(btn) end
    iconArt[btn] = art
    PaintArt(btn.icon, art)
end

function Classic.SeatHeaderIcon(btn, size)
    local art = iconArt[btn]
    if not art then return end
    local icon, k = btn.icon, art.scale
    icon:ClearAllPoints()
    if k and k < 1 then
        local inset = size * (1 - k) / 2
        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", inset, -inset)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
    else
        icon:SetAllPoints(btn)
    end
end

-- Stock art brightens on hover instead of fading in.
function Classic.HeaderHover(btn, hovered)
    if not iconArt[btn] then return GlyphHover(btn, hovered) end
    local k = hovered and ART_HOVER or ART_IDLE
    btn.icon:SetVertexColor(k, k, k, 1)
end

-- The vanilla lock is a square button.
function Classic.LockIcon(btn, locked)
    btn:SetSize(18, 18)
    PaintArt(btn.icon, locked and CLASSIC_LOCKED or CLASSIC_UNLOCKED)
end

-------------------------------------------------------------------------------
--  WoW Forever: Blizzard Style's variant on the Forever client, the Damage
--  Meters window's own variant look over Blizzard Style's painters. The
--  bronze line of Forever's micro menu box (EllesmereUI.ForeverBorder, on a
--  child frame of the window, the line inside the window's rect so snapping
--  and size matching are unchanged) over a flat dark body; the header
--  glyphs and the lock tan on Forever's square button plates; a gold title
--  in place of the accent; the menus in Forever's dropdown art (the rows
--  keep Blizzard Style's bar art). The header bar is Forever's objective
--  tracker header cut to its warm body and lower bronze rod, the header
--  taller by the rod so the buttons sit on the body. Every atlas is probed
--  once and a missing piece keeps plain Blizzard Style.
--  Installed after Blizzard Style's entries.
-------------------------------------------------------------------------------
local FV = {
    frameLevel = 14,   -- the line over the header and rows, under the grip and lock
    inset = EUI.FOREVER_BORDER.shade,     -- header and rows start past the line and its inner shadow
    bodyInset = EUI.FOREVER_BORDER.line,  -- the body from the line's inner edge
    plate = "common-button-tertiary-square-normal",
    plateHover = "common-button-tertiary-square-hover",
    glyph = { 0.95, 0.82, 0.60 },
    gold = { r = 1, g = 0.82, b = 0 },
    btnScale = 0.86, btnPad = 3,
    -- Header band: this 300x40 art cut to columns 64..176 (clear of its
    -- fading ends and filigree) and rows 9..39 (the body, the lower rod and
    -- its shadow; the frame's top line stands in for the upper rod), reaching
    -- hdrReach past the header's sides under the frame. The rod and shadow
    -- are 6 of the cut's 30 rows, so the header grows by a quarter of its
    -- height (hdrRail) to keep the 24-row body for its content.
    header = "ui-questtracker-primary-objective-header",
    hdrCut = { 64 / 300, 176 / 300, 9 / 40, 39 / 40 },
    hdrReach = 2, hdrRail = 0.25,
}
local plates = setmetatable({}, { __mode = "k" })  -- button -> { tex, atlas }
local hdrCut = setmetatable({}, { __mode = "k" })  -- header textures set to the band
local platesOK   -- both plate atlases exist

-- Always installed; the window pieces go in only with their art (UseForever).
local Forever = { iconPad = FV.btnPad, titleColor = FV.gold, menuLook = "meterForever" }

function Forever.IconSize(size)
    return math.floor(size * FV.btnScale + 0.5)
end

-- A button's plate in its idle or hover art, set only when it changes.
local function Plate(btn, hovered)
    if not platesOK then return end
    local p = plates[btn]
    if not p then
        local tex = btn:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints(btn)
        p = { tex = tex }
        plates[btn] = p
    end
    local atlas = hovered and FV.plateHover or FV.plate
    if p.atlas ~= atlas then
        p.atlas = atlas
        p.tex:SetAtlas(atlas)
    end
end

local function Tan(icon, k)
    local c = FV.glyph
    icon:SetVertexColor(c[1] * k, c[2] * k, c[3] * k, 1)
end

-- A glyph file from this addon's media, desaturated and tan on its plate.
local function FvGlyph(btn, file)
    local icon = btn.icon
    icon:SetTexture(MEDIA .. file)
    icon:SetDesaturated(true)
    Tan(icon, ART_IDLE)
    Plate(btn, false)
end

function Forever.HeaderIcon(btn)
    FvGlyph(btn, btn.file)
end

function Forever.HeaderHover(btn, hovered)
    Tan(btn.icon, hovered and ART_HOVER or ART_IDLE)
    Plate(btn, hovered)
end

-- The lock's own art on a square plate.
function Forever.LockIcon(btn, locked)
    btn:SetSize(18, 18)
    FvGlyph(btn, locked and "dm_locked_top.png" or "dm_unlock_top.png")
end

-- The bronze line on a window, on a child frame over its content, the
-- line's outer edge on the window's edge.
local function FrameArt(win)
    local host = CreateFrame("Frame", nil, win)
    host:SetFrameLevel(win:GetFrameLevel() + FV.frameLevel)
    host:SetAllPoints(win)
    EUI.ForeverBorderSeat(EUI.ForeverBorder(host), win)
end

-- The window wears the bronze line over a flat black body spanning it at
-- Blizzard Style's strength times the opacity (the configured colour is not
-- used), both made once per window; the bg texture itself paints nothing.
local function FvWindowBg(tex, _, _, _, a)
    local body = windowArt[tex]
    if not body then
        local win = tex:GetParent()
        local e = FV.bodyInset
        body = win:CreateTexture(nil, "BACKGROUND", nil, -8)
        body:SetPoint("TOPLEFT", win, "TOPLEFT", e, -e)
        body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -e, e)
        FrameArt(win)
        windowArt[tex] = body
        tex:SetColorTexture(0, 0, 0, 0)
    end
    body:SetColorTexture(0, 0, 0, 245 / 255 * a)
end

-- The header band (the header colour is not used; its opacity is). An atlas
-- cannot be cropped, so the cut is drawn from the atlas's sheet file at its
-- coords; set up once per texture, every later call sets the opacity only.
local function FvHeaderBg(tex, _, _, _, a)
    if not hdrCut[tex] then
        local info = C_Texture.GetAtlasInfo(FV.header)
        local l, t = info.leftTexCoord, info.topTexCoord
        local w, h = info.rightTexCoord - l, info.bottomTexCoord - t
        local c, e, header = FV.hdrCut, FV.hdrReach, tex:GetParent()
        tex:SetTexture(info.file or info.filename)
        tex:SetTexCoord(l + w * c[1], l + w * c[2], t + h * c[3], t + h * c[4])
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", header, "TOPLEFT", -e, 0)
        tex:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", e, 0)
        hdrCut[tex] = true
    end
    tex:SetVertexColor(1, 1, 1, a)
end

local function FvHeaderRail(h)
    return math.floor(h * FV.hdrRail + 0.5)
end

-- Over Blizzard Style's entries: the pieces whose art this client has.
local function UseForever()
    platesOK = HasAtlas(FV.plate) and HasAtlas(FV.plateHover)
    for key, value in pairs(Forever) do Look[key] = value end
    if EUI.ForeverBorderOK() then
        Look.inset, Look.WindowBg = FV.inset, FvWindowBg
        -- The band's rod ends run under the frame's side lines.
        if HasAtlas(FV.header) then
            Look.HeaderBg, Look.HeaderRail = FvHeaderBg, FvHeaderRail
        end
    end
end

-- styleKey: "blizzard" or "classic" (anything else keeps the EUI look);
-- forever: Blizzard Style's WoW Forever variant.
function ns.UseLook(styleKey, forever)
    local src = (styleKey == "blizzard" and Blizzard) or (styleKey == "classic" and Classic) or nil
    if not src then return end
    if src == Blizzard then
        shade = { lo = CreateColor(0, 0, 0, 1), hi = CreateColor(0, 0, 0, 0.5),
            clear = CreateColor(0, 0, 0, 0), top = CreateColor(0, 0, 0, 0.55),
            bottom = CreateColor(0, 0, 0, 0.30), ends = CreateColor(0, 0, 0, 0.35) }
    end
    for key, value in pairs(src) do Look[key] = value end
    if src == Blizzard and forever then UseForever() end
end

-------------------------------------------------------------------------------
--  Header buttons, in list order from the right edge of the header. A glyph
--  button idles at 0.4 and brightens to 0.9 on hover; a text button (Target /
--  Focus) takes its label's width. The tooltip stays hidden while the
--  button's own menu is open. btn.onClick(btn) is set by the owner.
-------------------------------------------------------------------------------
local function HeaderEnter(btn)
    if btn.isText then btn.label:SetTextColor(1, 1, 1, 1) else Look.HeaderHover(btn, true) end
    if btn.tooltip and EUI.ContextMenuOwner() ~= btn then EUI.ShowWidgetTooltip(btn, btn.tooltip) end
end

local function HeaderLeave(btn)
    if btn.isText then btn.label:SetTextColor(1, 1, 1, TEXT_ALPHA) else Look.HeaderHover(btn, false) end
    EUI.HideWidgetTooltip()
end

local function HeaderClick(btn)
    EUI.HideWidgetTooltip()
    if btn.onClick then btn.onClick(btn) end
end

local function NewHeaderButton(surface, key, tooltip)
    local header = surface.header
    local btn = CreateFrame("Button", nil, header)
    btn:SetFrameLevel(header:GetFrameLevel() + 2)
    btn.key, btn.tooltip = key, tooltip
    btn:SetScript("OnEnter", HeaderEnter)
    btn:SetScript("OnLeave", HeaderLeave)
    btn:SetScript("OnClick", HeaderClick)
    local list = surface.hdrBtns
    list[#list + 1] = btn
    return btn
end

function ns.MakeHeaderButton(surface, key, file, tooltip)
    local btn = NewHeaderButton(surface, key, tooltip)
    btn.file = file
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    Look.HeaderIcon(btn)
    return btn
end

-- The label needs a font before its first text.
function ns.MakeHeaderTextButton(surface, key, tooltip)
    local btn = NewHeaderButton(surface, key, tooltip)
    btn.isText = true
    btn.label = btn:CreateFontString(nil, "OVERLAY")
    btn.label:SetPoint("CENTER")
    btn.label:SetWordWrap(false)
    btn.label:SetTextColor(1, 1, 1, TEXT_ALPHA)
    return btn
end

-- Lays out the shown header buttons at `size`, raised by `lift` (nil = 0);
-- returns the leftmost one (the title runs up to it), or nil when none is
-- shown.
function ns.LayoutHeaderButtons(surface, size, lift)
    local header, pad = surface.header, Look.iconPad
    local used, n, leftmost = 0, 0, nil
    local list = surface.hdrBtns
    for i = 1, #list do
        local btn = list[i]
        if btn:IsShown() then
            n = n + 1
            local width = size
            if btn.isText then width = math.ceil(btn.label:GetStringWidth() or 0) + 12 end
            btn:SetSize(width, size)
            if not btn.isText then Look.SeatHeaderIcon(btn, size) end
            btn:ClearAllPoints()
            btn:SetPoint("RIGHT", header, "RIGHT", -(used + pad * n + 2), lift or 0)
            used = used + width
            leftmost = btn
        end
    end
    return leftmost
end

-------------------------------------------------------------------------------
--  Snapping (one window at a time is dragged, so the state is shared). The
--  target list is read fresh at each drag or resize start: the Damage Meters
--  windows are built after login and replaced on a profile switch.
-------------------------------------------------------------------------------
local targets = {}
local nearL, nearR, nearT, nearB

local function GatherTargets(self)
    wipe(targets)
    local dm = EUI._ModuleNS[DM_ADDON]
    local windows = dm and dm._windows
    if type(windows) == "table" then
        for i = 1, #windows do
            local w = windows[i]
            local f = type(w) == "table" and w.frame
            if f and f ~= self then targets[#targets + 1] = f end
        end
    else
        for i = 1, #DM_FRAME_NAMES do
            local f = _G[DM_FRAME_NAMES[i]]
            if type(f) == "table" and f ~= self and f.GetLeft then targets[#targets + 1] = f end
        end
    end
end

local function Plain(v)
    return not issecretvalue(v) and v ~= nil
end

-- The shown target nearest the rect: the smallest edge-to-edge gap (0 when
-- they overlap), the first in list order on a tie. Its edges land in near*.
local function Closest(left, top, width, height)
    local right, bottom = left + width, top - height
    local best, bestDist
    for i = 1, #targets do
        local f = targets[i]
        if f:GetParent() == UIParent and f:IsShown() then
            local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
            if Plain(l) and Plain(r) and Plain(t) and Plain(b) then
                local gx, gy = 0, 0
                if right < l then gx = l - right elseif left > r then gx = left - r end
                if bottom > t then gy = bottom - t elseif top < b then gy = b - top end
                local dist = gx * gx + gy * gy
                if not bestDist or dist < bestDist then
                    best, bestDist = f, dist
                    nearL, nearR, nearT, nearB = l, r, t, b
                end
            end
        end
    end
    return best
end

-- Edge snap for a drag: per axis the closest of left-to-left, right-to-right,
-- beside it on the right, beside it on the left (top-to-top, bottom-to-bottom,
-- stacked below, stacked above), taken within SNAP_DIST.
local function SnapMove(self, left, top)
    local width, height = self:GetWidth(), self:GetHeight()
    if not Closest(left, top, width, height) then return left, top end
    local best, snapped = SNAP_DIST + 1, left
    local d = math.abs(left - nearL)
    if d < best then best, snapped = d, nearL end
    d = math.abs(left + width - nearR)
    if d < best then best, snapped = d, nearR - width end
    d = math.abs(left - nearR)
    if d < best then best, snapped = d, nearR end
    d = math.abs(left + width - nearL)
    if d < best then best, snapped = d, nearL - width end
    if best <= SNAP_DIST then left = snapped end
    best, snapped = SNAP_DIST + 1, top
    d = math.abs(top - nearT)
    if d < best then best, snapped = d, nearT end
    d = math.abs(top - height - nearB)
    if d < best then best, snapped = d, nearB + height end
    d = math.abs(top - nearB)
    if d < best then best, snapped = d, nearB end
    d = math.abs(top - height - nearT)
    if d < best then best, snapped = d, nearT + height end
    if best <= SNAP_DIST then top = snapped end
    return left, top
end

-- Size snap for a resize: each dimension takes the nearest window's within
-- SNAP_DIST.
local function SnapSize(self, left, top, width, height)
    local near = Closest(left, top, self:GetWidth(), self:GetHeight())
    if not near then return width, height end
    local w, h = near:GetWidth(), near:GetHeight()
    if Plain(w) and math.abs(width - w) <= SNAP_DIST then width = w end
    if Plain(h) and math.abs(height - h) <= SNAP_DIST then height = h end
    return width, height
end

-------------------------------------------------------------------------------
--  Live window chrome: frame is the window (with .header). host:
--    IsLocked(), SetLocked(locked), SnapDisabled()
--    CanMove()             false while unlock mode owns the window
--    PinPosition(l, t)     a grip drag pins the top-left corner: a saved
--                          point-format spot becomes that corner first, so no
--                          re-apply of it can pull the window back mid-drag
--    SaveMove(l, t)        after a header drag
--    SaveSize(w, h)        after a grip drag (whole units)
--  Returns the handle: SyncLock() re-reads the lock state; resizing is true
--  while the grip is held.
--  Locked: no header drag and no grip. Every driver is a frame hidden while
--  idle, and the hover poll runs only while the pointer is over the window.
-------------------------------------------------------------------------------
function ns.AttachChrome(frame, host)
    local PP = EUI.PP
    local header = frame.header
    local level = frame:GetFrameLevel()
    local chrome = { resizing = false }
    local locked = host.IsLocked()
    local hovered = false
    header:EnableMouse(true)

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(level + 15)
    grip.icon = grip:CreateTexture(nil, "ARTWORK")
    grip.icon:SetAllPoints()
    grip.icon:SetTexture(RESIZE_ICON)
    grip.icon:SetDesaturated(true)
    grip.icon:SetVertexColor(1, 1, 1)
    grip:EnableMouse(true)
    grip:SetAlpha(0)
    frame.grip = grip

    local lock = CreateFrame("Button", nil, frame)
    lock:SetSize(13, 17)
    lock:SetFrameLevel(level + 16)
    lock.icon = lock:CreateTexture(nil, "ARTWORK")
    lock.icon:SetAllPoints()
    lock.icon:SetDesaturated(true)
    lock.icon:SetVertexColor(1, 1, 1)
    lock:EnableMouse(true)
    lock:SetAlpha(0)
    frame.lockBtn = lock

    local function Resting()
        return hovered and 0.3 or 0
    end

    local function LockText()
        return locked and EllesmereUI.L("Locked") or EllesmereUI.L("Unlocked")
    end

    -- Locked, the icon takes the grip's corner (the grip is hidden then).
    local function UpdateLockIcon()
        Look.LockIcon(lock, locked)
        lock:ClearAllPoints()
        if locked then
            lock:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
        else
            lock:SetPoint("RIGHT", grip, "LEFT", -2, 0)
        end
    end

    grip:SetScript("OnEnter", function(self)
        if not locked then self:SetAlpha(0.7) end
    end)
    grip:SetScript("OnLeave", function(self)
        self:SetAlpha((hovered and not locked) and 0.3 or 0)
    end)
    lock:SetScript("OnEnter", function(self)
        self:SetAlpha(0.7)
        EUI.ShowWidgetTooltip(self, LockText())
    end)
    lock:SetScript("OnLeave", function(self)
        self:SetAlpha(Resting())
        EUI.HideWidgetTooltip()
    end)
    lock:SetScript("OnClick", function(self)
        locked = not locked
        host.SetLocked(locked)
        UpdateLockIcon()
        grip:SetAlpha(locked and 0 or Resting())
        self:SetAlpha(Resting())
        EUI.HideWidgetTooltip()
        EUI.ShowWidgetTooltip(self, LockText())
    end)

    function chrome.SyncLock()
        locked = host.IsLocked()
        UpdateLockIcon()
        grip:SetAlpha((hovered and not locked) and 0.3 or 0)
        lock:SetAlpha(Resting())
    end

    -- Hover fade: grip and lock ease to 0.3 while the window is hovered (0.7
    -- on the control itself), and back to 0 when it is left.
    local fadeAlpha, fadeTarget = 0, 0
    local fader = CreateFrame("Frame")
    fader:Hide()
    fader:SetScript("OnUpdate", function(self, elapsed)
        local step = elapsed / FADE_TIME
        if fadeTarget > fadeAlpha then
            fadeAlpha = math.min(fadeTarget, fadeAlpha + step)
        else
            fadeAlpha = math.max(fadeTarget, fadeAlpha - step)
        end
        if math.abs(fadeAlpha - fadeTarget) < 0.001 then fadeAlpha = fadeTarget end
        if not locked and not grip:IsMouseOver() then grip:SetAlpha(fadeAlpha * 0.3) end
        if not lock:IsMouseOver() then lock:SetAlpha(fadeAlpha * 0.3) end
        if fadeAlpha == fadeTarget then self:Hide() end
    end)

    local poll
    local function StopPoll()
        if poll then
            poll:Cancel()
            poll = nil
        end
    end
    local function Poll()
        if frame:IsMouseOver() or grip:IsMouseOver() or lock:IsMouseOver() then
            if not hovered then
                hovered, fadeTarget = true, 1
                fader:Show()
            end
        else
            if hovered then
                hovered, fadeTarget = false, 0
                fader:Show()
            end
            StopPoll()
        end
    end
    local function StartPoll()
        if not poll then poll = C_Timer.NewTicker(HOVER_POLL, Poll) end
    end
    frame:HookScript("OnEnter", StartPoll)
    header:HookScript("OnEnter", StartPoll)
    grip:HookScript("OnEnter", StartPoll)
    lock:HookScript("OnEnter", StartPoll)
    frame:HookScript("OnHide", function()
        StopPoll()
        hovered, fadeAlpha, fadeTarget = false, 0, 0
        fader:Hide()
        grip:SetAlpha(0)
        lock:SetAlpha(0)
        -- A menu opened from this window's header closes with it.
        local owner = EUI.ContextMenuOwner()
        if owner and owner:GetParent() == header then EUI.CloseContextMenu() end
    end)

    local function Cursor()
        local x, y = GetCursorPosition()
        local scale = frame:GetEffectiveScale()
        return x / scale, y / scale
    end

    local function CanStart()
        return not locked and host.CanMove() and not EUI.InProtectedInstance()
    end

    local snapOff, cursorX, cursorY, startL, startT
    -- The last applied spot and size: a held but still pointer re-anchors
    -- nothing.
    local lastL, lastT, lastW, lastH
    -- A drag starts once the pointer travels this far; a plain click on the
    -- header moves and saves nothing.
    local DRAG_START = 3
    local moved = false

    -- Header drag. A release caught by the per-frame check finishes the drag
    -- and stops there, so the saved spot is the one on screen.
    local dragger = CreateFrame("Frame")
    dragger:Hide()
    local function EndDrag()
        dragger:Hide()
        wipe(targets)
        if not moved then return end
        local left, top = Corner(frame)
        if not left then return end
        left, top = PP.Snap(left), PP.Snap(top)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        host.SaveMove(left, top)
    end
    dragger:SetScript("OnUpdate", function()
        if not IsMouseButtonDown("LeftButton") then
            EndDrag()
            return
        end
        local x, y = Cursor()
        if not moved then
            if math.abs(x - cursorX) + math.abs(y - cursorY) <= DRAG_START then return end
            moved = true
        end
        local left, top = startL + (x - cursorX), startT + (y - cursorY)
        if not snapOff then left, top = SnapMove(frame, left, top) end
        left, top = PP.Snap(left), PP.Snap(top)
        if left == lastL and top == lastT then return end
        lastL, lastT = left, top
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end)
    header:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or not CanStart() then return end
        local left, top = Corner(frame)
        if not left then return end
        cursorX, cursorY = Cursor()
        startL, startT = left, top
        moved, lastL, lastT = false, nil, nil
        snapOff = host.SnapDisabled()
        GatherTargets(frame)
        dragger:Show()
    end)
    header:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and dragger:IsShown() then EndDrag() end
    end)

    -- Grip resize from the pinned top-left corner, never past the screen's
    -- right or bottom edge. Shift locks the axis that moved most when it went
    -- down. A release caught by the per-frame check ends it too (the window
    -- can hide under the pointer).
    local sizer = CreateFrame("Frame")
    sizer:Hide()
    local pinL, pinT, startW, startH, axis, shiftWas
    local function EndResize()
        sizer:Hide()
        wipe(targets)
        chrome.resizing = false
        host.SaveSize(math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5))
        host.PinPosition(Corner(frame))
    end
    sizer:SetScript("OnUpdate", function()
        if not IsMouseButtonDown("LeftButton") then
            EndResize()
            return
        end
        local x, y = Cursor()
        local dx, dy = x - cursorX, cursorY - y
        local shift = IsShiftKeyDown()
        local width, height = startW + dx, startH + dy
        if shift then
            if not shiftWas then axis = math.abs(dx) >= math.abs(dy) and "w" or "h" end
            if axis == "w" then height = startH else width = startW end
        end
        width, height = math.max(MIN_W, width), math.max(MIN_H, height)
        if not snapOff then width, height = SnapSize(frame, pinL, pinT, width, height) end
        local maxW = (UIParent:GetRight() or 0) - pinL
        local maxH = pinT - (UIParent:GetBottom() or 0)
        if maxW > MIN_W then width = math.min(width, maxW) end
        if maxH > MIN_H then height = math.min(height, maxH) end
        shiftWas = shift
        if width == lastW and height == lastH then return end
        lastW, lastH = width, height
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pinL, pinT)
        frame:SetSize(width, height)
    end)
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or not CanStart() then return end
        local left, top = Corner(frame)
        if not left then return end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        host.PinPosition(left, top)
        pinL, pinT = left, top
        cursorX, cursorY = Cursor()
        startW, startH = frame:GetWidth(), frame:GetHeight()
        axis, shiftWas = nil, false
        lastW, lastH = nil, nil
        snapOff = host.SnapDisabled()
        GatherTargets(frame)
        chrome.resizing = true
        sizer:Show()
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and sizer:IsShown() then EndResize() end
    end)

    UpdateLockIcon()
    return chrome
end
