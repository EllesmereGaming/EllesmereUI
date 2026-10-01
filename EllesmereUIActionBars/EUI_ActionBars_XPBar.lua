if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI Action Bars - XP Bar
--  The XP bar's own runtime: its frame art styles and profession flipbook
--  fill, the dividers and Smart Ticks, the XP / rested update and tooltip,
--  and the style getter and setter the XP Bar options tab uses. What it
--  shares with the reputation and House Favor bars (the data bar frame,
--  layout, border, text placement, visibility, hover and Unlock Mode) is in
--  EllesmereUIActionBars.lua, which loads first and calls into this file
--  through ns at run time.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local EAB                    = ns.EAB
local EAB_VTABLE             = ns.EAB_VTABLE
local BAR_LOOKUP             = ns.BAR_LOOKUP
local dataBarFrames          = ns.dataBarFrames
local ApplyDataBarLayout     = ns.ApplyDataBarLayout
local CreateDataBarFrame     = ns.CreateDataBarFrame
local ResolveBorderThickness = ns.ResolveBorderThickness
local PP                     = EllesmereUI.PP
local ipairs, pairs          = ipairs, pairs
local floor, min, max        = math.floor, math.min, math.max

-- XP bar colors
local XP_BAR_COLORS = {
    xpRested   = { r = 0.00, g = 0.44, b = 0.87 },  -- shaman blue (XP when rested)
    xpNoRest   = { r = 0.60, g = 0.40, b = 0.85 },  -- purple (XP when no rested)
    xpRestedBG = { r = 0.15, g = 0.30, b = 0.60 },  -- dark blue (rested overlay)
}

-------------------------------------------------------------------------------
--  XP bar art styles (the XP Bar tab's style selector) and the profession
--  fill (the XP Bar tab's Fill cog). Both opt-in, saved on the XP bar's
--  profile settings:
--    s.xpArt  = nil (the EllesmereUI bar) | "prof" (the Professions skill-bar
--               frame) | "forever" (WoW Forever's bronze border, the one the
--               chat panel and the Damage Meters windows wear; Forever only)
--    s.fvFill = nil | a Skillbar_Fill_Flipbook_* atlas, tiled at its own
--               proportions (s.fvFillStretch: one copy across the bar);
--               it plays once on each XP gain unless s.fvFillSmart is
--               false, or loops while s.fvFillAnim is true
--  Applied from ApplyDataBarLayout only (style and layout changes); an XP update
--  only plays the smart flash. A bar that never opted in reads two fields per
--  layout; leaving a style undoes its art once. On ns: ApplyDataBarLayout
--  (EllesmereUIActionBars.lua) and the dividers below call into it.
-------------------------------------------------------------------------------
ns._XPArtAtlas = { prof = "Professions-skillbar-frame" }
-- Fit of each frame around the bar (px): cap share of a flat atlas, overlay
-- offsets, top / bottom rail reach, divider tick inset and solid-tick reach,
-- fill / trough end tucks, fill vertical inset. The Forever border (ring) has
-- only the divider fit: the ticks start past its line.
ns._XPArtFit = {
    prof = { capFrac = 0.2, offX = -2, offY = -2, top = 0, bot = -3, tickInset = 4, solidExt = 2,
             endInset = 0, bgInset = 2, fillV = 1 },
    forever = { ring = true, tickInset = 1, solidExt = 0 },
}

-- The fit (and frame atlas) of the XP bar's art style, or nil while it shows
-- the EllesmereUI bar or the style's art is missing on this client. A frame
-- style is horizontal art (nil on a vertical bar); the Forever border frames
-- either orientation.
function ns.XPArtFit(s)
    local art = s and s.xpArt
    if not art then return nil end
    if art == "forever" then
        return EllesmereUI.ForeverBorderOK() and ns._XPArtFit.forever or nil
    end
    if (s.orientation or "HORIZONTAL") ~= "HORIZONTAL" then return nil end
    local atlas = ns._XPArtAtlas[art]
    if not (atlas and C_Texture.GetAtlasInfo(atlas)) then return nil end
    return ns._XPArtFit[art], atlas
end

-- A bar-frame atlas on `overlay` at any width. An atlas with sliceData keeps
-- its own slice margins (only the middle stretches); a flat one gets a manual
-- 3-slice: fixed caps (fit.capFrac of the art, drawn undistorted), a uniform
-- stretched middle, and the bottom rail mirrored from the top so both match.
function ns._XPFrameSlice(overlay, atlas, fit)
    local info = C_Texture.GetAtlasInfo(atlas)
    local sd = info and info.sliceData
    overlay._frameTex = overlay._frameTex or overlay:CreateTexture(nil, "OVERLAY")
    local tx = overlay._frameTex
    if sd then
        if overlay._flat then for _, t in pairs(overlay._flat) do t:Hide() end end
        tx:ClearAllPoints(); tx:SetAllPoints(overlay)
        tx:SetAtlas(atlas)
        tx:SetTextureSliceMargins(sd.marginLeft or 0, sd.marginTop or 0, sd.marginRight or 0, sd.marginBottom or 0)
        tx:SetTextureSliceMode(sd.sliceMode or 0)
        tx:Show()
        return
    end
    tx:Hide()
    local s = overlay._flat
    if not s then
        s = {}
        for _, k in ipairs({ "TL", "TM", "TR", "BL", "BM", "BR" }) do
            local t = overlay:CreateTexture(nil, "OVERLAY")
            t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0)
            s[k] = t
        end
        overlay._flat = s
    end
    local lc, rc, tc, bc = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    local du = rc - lc
    local capFrac = max(0.02, min(0.48, fit.capFrac))
    local lMid, rMid = lc + du * capFrac, rc - du * capFrac
    local midU, band = (lc + rc) / 2, du * 0.004
    local vMid = (tc + bc) / 2
    local oh = overlay:GetHeight()
    if not oh or oh <= 0 then oh = info.height or 20 end
    local scale = (info.height and info.height > 0) and (oh / info.height) or 1
    local capW = capFrac * (info.width or 0) * scale
    if capW <= 0 then capW = oh end
    local file = info.file or info.filename
    for _, t in pairs(s) do t:SetTexture(file); t:ClearAllPoints() end
    -- Each column samples the TOP half of the art; the bottom row samples the
    -- same rail flipped, so the two edges always match.
    s.TL:SetTexCoord(lc, lMid, tc, vMid)
    s.TL:SetPoint("TOPLEFT", overlay, "TOPLEFT"); s.TL:SetPoint("BOTTOMLEFT", overlay, "LEFT"); s.TL:SetWidth(capW)
    s.BL:SetTexCoord(lc, lMid, vMid, tc)
    s.BL:SetPoint("TOPLEFT", overlay, "LEFT"); s.BL:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT"); s.BL:SetWidth(capW)
    s.TR:SetTexCoord(rMid, rc, tc, vMid)
    s.TR:SetPoint("TOPRIGHT", overlay, "TOPRIGHT"); s.TR:SetPoint("BOTTOMRIGHT", overlay, "RIGHT"); s.TR:SetWidth(capW)
    s.BR:SetTexCoord(rMid, rc, vMid, tc)
    s.BR:SetPoint("TOPRIGHT", overlay, "RIGHT"); s.BR:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT"); s.BR:SetWidth(capW)
    s.TM:SetTexCoord(midU - band, midU + band, tc, vMid)
    s.TM:SetPoint("TOPLEFT", s.TL, "TOPRIGHT"); s.TM:SetPoint("BOTTOMRIGHT", s.TR, "BOTTOMLEFT")
    s.BM:SetTexCoord(midU - band, midU + band, vMid, tc)
    s.BM:SetPoint("TOPLEFT", s.BL, "TOPRIGHT"); s.BM:SetPoint("BOTTOMRIGHT", s.BR, "BOTTOMLEFT")
    for _, t in pairs(s) do t:Show() end
end

-- The flipbook's idle frame (frame 0 of 2 columns x `rows`), drawn from the
-- sheet file: an atlas-mode texture does not take sheet coords in SetTexCoord.
function ns._XPFlipStatic(tex, info, rows)
    tex:SetTexture(info.file or info.filename)
    local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    tex:SetTexCoord(l, l + (r - l) / 2, t, t + (b - t) / rows)
end

-- Flipbooks whose first frames start abruptly: their pass fades in as slowly
-- as it fades out.
ns._XPFlipSlowIn = {
    Skillbar_Fill_Flipbook_Jewelcrafting = true,
    Skillbar_Fill_Flipbook_Leatherworking = true,
}

-- The profession flipbook over the XP fill (s.fvFill), shown only up to the
-- fill's edge (the plain fill hides under it) through a holder-sized mask
-- whose right edge rides the fill's, moved by the bar itself on every value
-- change. The art (the client's skill bar: 2 columns, a row per 34 px of the
-- atlas's height, 856 x 34 px frames, 2 s per pass) is tiled at its own
-- proportions: copies scaled to the bar's height side by side, the last one
-- cut by the mask, which also ends at the bar's edge. Stretch to Bar
-- (s.fvFillStretch) draws one copy across the whole bar instead. A tile is an
-- idle frame behind and an animated layer in front with its own animation
-- groups; every tile is started in the same pass, so they stay in step.
-- Animate on XP Gain (on unless s.fvFillSmart is false) fades one pass in
-- over the idle frame, holds its last frame and fades back out; Loop
-- Animation (s.fvFillAnim, off by default; the options turn one off when the
-- other goes on) plays it on repeat instead. Laid out on layout passes only;
-- horizontal bars only (the art is horizontal).
local FLIP_MAX_TILES = 24  -- a very long, thin bar widens its tiles past this

-- One tile, masked by the reveal, with its one-pass and looping groups.
local function NewFlipTile(bar, mask)
    local t = {}
    t.idle = bar:CreateTexture(nil, "OVERLAY", nil, 0)
    t.flip = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    t.idle:AddMaskTexture(mask); t.flip:AddMaskTexture(mask)
    local function Book(group)
        local fb = group:CreateAnimation("FlipBook")
        fb:SetTarget(t.flip)
        fb:SetDuration(2)
        fb:SetFlipBookColumns(2)
        fb:SetFlipBookFrameWidth(0); fb:SetFlipBookFrameHeight(0)
        return fb
    end
    -- One pass: the flipbook and its fade-in together, then the last frame
    -- held and faded out onto the idle frame behind it. The layer rests at
    -- alpha 0 between passes.
    local once = bar:CreateAnimationGroup()
    once._fb = Book(once)
    local fadeIn = once:CreateAnimation("Alpha")
    fadeIn:SetTarget(t.flip)
    fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1)
    once._fadeIn = fadeIn
    local fadeOut = once:CreateAnimation("Alpha")
    fadeOut:SetTarget(t.flip)
    fadeOut:SetOrder(2)
    fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0)
    fadeOut:SetStartDelay(0.2); fadeOut:SetDuration(0.5)
    t.once = once
    local loop = bar:CreateAnimationGroup()
    loop._fb = Book(loop)
    loop:SetLooping("REPEAT")
    t.loop = loop
    return t
end

local function HideFlipTile(t)
    t.once:Stop(); t.loop:Stop()
    t.flip:Hide(); t.idle:Hide()
end

-- A tile's layer at x across the bar, tw wide, the bar's full height.
local function PlaceFlipLayer(r, bar, x, tw)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
    r:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
    r:SetWidth(tw)
end

function ns.ApplyXPFlipFill(frame, s)
    local bar = frame._bar
    local tex = bar:GetStatusBarTexture()
    local atlas = (s.orientation or "HORIZONTAL") == "HORIZONTAL" and s.fvFill
    local info = atlas and C_Texture.GetAtlasInfo(atlas)
    local tiles = frame._fvTiles
    if not info then
        if frame._fvFlipOn then
            frame._fvFlipOn, frame._fvFlipSmart, frame._fvTileN, frame._fvFlipAtlas = nil, nil, nil, nil
            for i = 1, #tiles do HideFlipTile(tiles[i]) end
            tex:SetAlpha(1)
        end
        return
    end
    local mask = frame._fvFlipMask
    if not tiles then
        -- The reveal: a fixed, holder-sized rect, never the fill's own (that
        -- is zero-wide at no XP, where a mask samples undefined; this one
        -- then sits wholly left of the bar).
        mask = bar:CreateMaskTexture()
        mask:SetTexture("Interface\\Buttons\\WHITE8x8",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
        frame._fvFlipMask = mask
        tiles = {}
        frame._fvTiles = tiles
    end
    -- The holder's size covers the bar inside it, whatever the art style's insets.
    mask:ClearAllPoints()
    mask:SetPoint("RIGHT", tex, "RIGHT")
    mask:SetSize(frame:GetSize())

    -- Rows differ per atlas (Enchanting 37, Jewelcrafting 22, the rest 30).
    local rows = max(1, floor(info.height / 34 + 0.5))
    -- Tile width: a frame's width at the bar's height, snapped to whole
    -- pixels so neighbours meet exactly; one bar-wide copy to stretch.
    local bw, bh = bar:GetSize()
    local n, tw = 1, bw
    if not s.fvFillStretch and bh > 0 then
        tw = max(1, PP.Scale(bh * (info.width / 2) / (info.height / rows)))
        n = max(1, math.ceil(bw / tw))
        if n > FLIP_MAX_TILES then n = FLIP_MAX_TILES; tw = bw / n end
    end
    -- A new tile count or art restarts every tile together.
    local resync = n ~= frame._fvTileN or atlas ~= frame._fvFlipAtlas
    for i = #tiles + 1, n do tiles[i] = NewFlipTile(bar, mask) end
    for i = n + 1, #tiles do HideFlipTile(tiles[i]) end
    local fadeIn = ns._XPFlipSlowIn[atlas] and 0.5 or 0.25
    for i = 1, n do
        local t = tiles[i]
        if resync then t.once:Stop(); t.loop:Stop() end
        if t.atlas ~= atlas then
            t.once._fb:SetFlipBookRows(rows); t.once._fb:SetFlipBookFrames(rows * 2)
            t.loop._fb:SetFlipBookRows(rows); t.loop._fb:SetFlipBookFrames(rows * 2)
            t.once._fadeIn:SetDuration(fadeIn)
            t.flip:SetAtlas(atlas)
            ns._XPFlipStatic(t.idle, info, rows)
            t.atlas = atlas
        end
        local x = (i - 1) * tw
        PlaceFlipLayer(t.flip, bar, x, tw)
        PlaceFlipLayer(t.idle, bar, x, tw)
        t.idle:Show()
    end
    frame._fvFlipOn, frame._fvTileN, frame._fvFlipAtlas = true, n, atlas
    tex:SetAlpha(0)

    local loopOn = s.fvFillAnim == true
    local smart = not loopOn and s.fvFillSmart ~= false
    frame._fvFlipSmart = smart or nil
    for i = 1, n do
        local t = tiles[i]
        if loopOn then
            t.once:Stop()
            t.flip:SetAlpha(1); t.flip:Show()
            if not t.loop:IsPlaying() then t.loop:Play() end
        else
            -- Smart: a running pass carries on; static: the idle frame alone.
            t.loop:Stop()
            t.flip:SetAlpha(0)
            if smart then t.flip:Show() else t.once:Stop(); t.flip:Hide() end
        end
    end
end

-- Smart fill: one pass of the flipbook on an XP gain (UpdateXPBar), on every
-- tile together; a gain during a pass lets it finish.
function ns.PlayXPFlipOnce(frame)
    local tiles, n = frame._fvTiles, frame._fvTileN
    if not (tiles and n) or tiles[1].once:IsPlaying() then return end
    for i = 1, n do tiles[i].once:Play() end
end

-- The Forever style: WoW Forever's bronze border (EllesmereUI.ForeverBorder)
-- in place of our 1px line, its outer edge on the bar's edge as on the
-- Damage Meters windows, so size matching and snapping are unchanged. The
-- fill, rested bar and trough start at the line's inner edge and keep the
-- bar's own texture and colours. Built once on its own child above the fill
-- (holder+1) and the ticks (holder+2).
local function ApplyXPForeverBorder(frame, bar, bg, rb)
    local host = frame._fvRingHost
    if not host then
        host = CreateFrame("Frame", nil, frame)
        host:SetAllPoints(frame)
        host:EnableMouse(false)
        frame._fvRing = EllesmereUI.ForeverBorder(host)
        EllesmereUI.ForeverBorderSeat(frame._fvRing, frame)
        frame._fvRingHost = host
    end
    host:SetFrameLevel(frame:GetFrameLevel() + 3)
    host:Show()
    local w, h = frame:GetSize()
    EllesmereUI.ForeverBorderFit(frame._fvRing, w, h)
    local e = EllesmereUI.FOREVER_BORDER.line
    PP.SetInside(bar, frame, e, e); PP.SetInside(bg, frame, e, e)
    if rb then PP.SetInside(rb, frame, e, e) end
end

-- The XP bar's art style. frame._xpArtOn names the style on the bar ("frame"
-- art or the Forever "ring"); leaving it undoes its pieces once (the layout
-- already restored the fill and rested textures), and back on the EllesmereUI
-- bar the insets and the plain border return unless Custom Border owns the
-- edge.
local function ApplyXPArt(frame, s)
    local fit, atlas = ns.XPArtFit(s)
    local bar, bg, rb = frame._bar, frame._bg, frame._restedBar
    local line = frame._border and frame._border._frame
    local kind = fit and (fit.ring and "ring" or "frame") or nil
    local was = frame._xpArtOn
    if was and was ~= kind then
        frame._xpArtOn = nil
        if was == "frame" then
            frame._fvOverlay:Hide()
            bg:SetTextureSliceMargins(0, 0, 0, 0)
            bg:SetTexCoord(0, 1, 0, 1)
            bg:SetColorTexture(0.06, 0.06, 0.08, 0.85)
        else
            frame._fvRingHost:Hide()
        end
        if not kind then
            PP.SetInside(bar, frame, 1, 1); PP.SetInside(bg, frame, 1, 1)
            if rb then PP.SetInside(rb, frame, 1, 1) end
            if line and not s.customBorder then line:Show() end
        end
    end
    if not kind then return end
    frame._xpArtOn = kind
    -- The art replaces our 1px border.
    if line then line:Hide() end
    if kind == "ring" then
        ApplyXPForeverBorder(frame, bar, bg, rb)
        return
    end
    -- Fill: flat and square-ended, tinted by the bar's Color setting (UpdateXPBar).
    local tex = bar:GetStatusBarTexture()
    tex:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    tex:SetDrawLayer("ARTWORK", 4)
    -- Trough: the client's own XP-bar background; its rounded ends keep their
    -- radius through its slice margins.
    bg:SetAtlas("UI-HUD-ExperienceBar-Background")
    bg:SetTextureSliceMargins(10, 0, 10, 0)
    bg:SetTextureSliceMode(0)
    -- Frame art on its own overlay above the fill (holder+1) and ticks (+2).
    local ov = frame._fvOverlay
    if not ov then
        ov = CreateFrame("Frame", nil, frame)
        ov:EnableMouse(false)
        frame._fvOverlay = ov
    end
    ov:ClearAllPoints()
    ov:SetPoint("TOPLEFT", frame, "TOPLEFT", -2 + fit.offX, 2 + fit.offY + fit.top)
    ov:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2 + fit.offX, -2 + fit.offY - fit.bot)
    ov:SetFrameLevel(frame:GetFrameLevel() + 3)
    ov:Show()
    ns._XPFrameSlice(ov, atlas, fit)
    -- The fill and rested bar tuck their ends under the frame's caps and match
    -- the trough's visible height; the trough tucks a little further.
    local endInset, fillV = fit.endInset, fit.fillV
    local bgInset = endInset + fit.bgInset
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", endInset, -1 - fillV)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -endInset, 1 + fillV)
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", bgInset, -1)
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -bgInset, 1)
    if rb then
        rb:GetStatusBarTexture():SetTexture("Interface\\BUTTONS\\WHITE8X8")
        rb:ClearAllPoints()
        rb:SetPoint("TOPLEFT", frame, "TOPLEFT", endInset, -1 - fillV)
        rb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -endInset, 1 + fillV)
    end
end

-- The bar's background: the XP Bar tab's Background Opacity (s.barBgOpacity,
-- 0-100) and its colour (s.barBgColor). Unset keeps each style's own: the
-- dark EllesmereUI body at 85%, the Professions trough untinted at 100%.
-- Returns r, g, b and the opacity (0-100).
function ns.XPBarBackground(s)
    local fit = ns.XPArtFit(s)
    local art = fit and not fit.ring
    local c = s.barBgColor
    local r, g, b
    if c then
        r, g, b = c.r or 0, c.g or 0, c.b or 0
    elseif art then
        r, g, b = 1, 1, 1
    else
        r, g, b = 0.06, 0.06, 0.08
    end
    return r, g, b, s.barBgOpacity or (art and 100 or 85)
end

-- The Professions trough is art, so it is tinted and faded; every other
-- style's background is a flat colour.
local function PaintXPBackground(frame, s)
    local bg = frame._bg
    local r, g, b, op = ns.XPBarBackground(s)
    if frame._xpArtOn == "frame" then
        bg:SetVertexColor(r, g, b, op / 100)
    else
        bg:SetVertexColor(1, 1, 1, 1)
        bg:SetColorTexture(r, g, b, op / 100)
    end
end

-- The XP bar's art style, background and fill, from ApplyDataBarLayout
-- (after it set the bar texture, before the dividers and the Custom Border).
-- The fill comes last: its tiles size from the bar the art style left.
function ns.ApplyXPBarStyle(frame, s)
    ApplyXPArt(frame, s)
    PaintXPBackground(frame, s)
    ns.ApplyXPFlipFill(frame, s)
end

-------------------------------------------------------------------------------
--  Dividers and Smart Ticks (the XP Bar tab's Show Dividers row)
-------------------------------------------------------------------------------
-- Show Dividers (a data bar's showDividers, offered on the XP Bar tab;
-- ApplyDataBarLayout calls this for a bar that has it on or a built host):
-- a dashed tick at every 5% and a full line at every 10% across the bar,
-- inside its border (left to right on a horizontal bar, bottom to top on a
-- vertical one), one physical pixel thick on whole pixels, over the fill
-- and under the text. Divider Text labels the 10% lines (10%..90%), each
-- centred on its line, drawn above it and nudged by the offsets (X along the
-- label's reading direction, Y across it); rotateDividerText turns them to
-- run along a vertical bar. A rotated string pivots about the top centre of
-- its unrotated region, so a label's anchor is moved back by that
-- displacement. Pooled on a child host built the first time the option is
-- on; off, a built host hides.
function ns.AB_DataBarDividers(holder, w, h, orient, s)
    local host = holder._divHost
    if not s.showDividers then
        if host then host:Hide(); host._nTick = nil end
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, holder)
        host:SetAllPoints(holder)
        host._tick = {}
        host._lbl = {}
        holder._divHost = host
    end
    host:SetFrameLevel(holder:GetFrameLevel() + 2)
    host:Show()
    local tick, lbl = host._tick, host._lbl
    local vertical = (orient == "VERTICAL")
    -- The border's inner edge across the bar: 1 in, or a thicker solid
    -- Custom Border's own width, so no line or dash reaches into it.
    local e = 1
    if s.customBorder then
        local bt = s.borderTexture
        if not bt or bt == "" or bt == "solid" then
            local sz, px = ResolveBorderThickness(s)
            e = max(1, floor((px or sz) + 0.5) * PP.mult)
        end
    end
    -- An XP bar frame art style: the ticks sit inside its rails.
    local fit = holder == dataBarFrames.XPBar and ns.XPArtFit(s)
    if fit then
        e = e + fit.tickInset * PP.mult
    end
    -- Length along the bar (the fill's) and across it, inside the border.
    local L = (vertical and h or w) - 2
    local C = (vertical and w or h) - 2 * e
    local nTick, nLbl = 0, 0
    if L > 0 and C > 0 then
        local Snap, one = PP.Snap, PP.mult
        -- 5% Line Style: "dashed" (default), "dotted" (1px dots), "solid" (a
        -- continuous line like the 10% lines) or "none" (the 10% lines alone).
        local style5 = s.divider5Style or "dashed"
        local dash = style5 == "dotted" and one or max(one, Snap(2))
        local gap = max(one, Snap(2))
        local step = dash + gap
        local count = max(1, floor((C + gap) / step))
        local c0 = Snap(e)
        local dash0 = c0 + Snap(max(0, (C - (count * step - gap)) / 2))
        local full = Snap(e + C) - c0
        -- Inside an art frame the solid lines reach a little past the tick inset.
        local solidExt = fit and fit.solidExt * one or 0
        local solidFull = full + 2 * solidExt
        local solidC0 = c0 - solidExt
        local c = s.tick5Color
        local r5, g5, b5 = c and c.r or 220 / 255, c and c.g or 167 / 255, c and c.b or 127 / 255
        local a5 = c and c.a or 0.9
        c = s.tick10Color
        local r10, g10, b10 = c and c.r or 1, c and c.g or 1, c and c.b or 1
        local a10 = c and c.a or 0.9
        local showLbl = s.showDividerText
        local lsz, lflag, lr, lg, lb, lrot, lcos, lsin, lox, loy, across
        if showLbl then
            local pi = math.pi
            lsz = s.dividerTextSize or 8
            lflag = EllesmereUI.GetFontOutlineFlag("actionBars")
            c = s.dividerTextColor
            lr, lg, lb = c and c.r or 1, c and c.g or 1, c and c.b or 1
            lrot = (vertical and s.rotateDividerText) and (s.textReadDown and -pi / 2 or pi / 2) or 0
            lcos, lsin = math.cos(lrot), math.sin(lrot)
            local ox, oy = s.dividerTextOffX or 0, s.dividerTextOffY or 0
            lox, loy = ox * lcos - oy * lsin, ox * lsin + oy * lcos
            across = e + C / 2
        end
        for pct = 5, 95, 5 do
            local pos = Snap(1 + pct / 100 * L)
            if pct % 10 == 0 then
                nTick = nTick + 1
                local t = tick[nTick]
                if not t then t = host:CreateTexture(nil, "OVERLAY"); tick[nTick] = t end
                t:SetColorTexture(r10, g10, b10, a10)
                t:ClearAllPoints()
                if vertical then
                    t:SetSize(solidFull, one)
                    t:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", solidC0, pos)
                else
                    t:SetSize(one, solidFull)
                    t:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", pos, solidC0)
                end
                t._pct = pct
                t:Show()
                if showLbl then
                    -- Slot k is the (10 * k)% line; its text is set once.
                    nLbl = nLbl + 1
                    local fs = lbl[nLbl]
                    if not fs then
                        fs = host:CreateFontString(nil, "OVERLAY")
                        -- Sublevel 1: above the lines (OVERLAY 0) it sits on.
                        fs:SetDrawLayer("OVERLAY", 1)
                        -- The font first: SetText needs one.
                        EllesmereUI.ApplyModuleFont(fs, nil, lsz, "actionBars", lflag)
                        fs:SetText(nLbl * 10 .. "%")
                        lbl[nLbl] = fs
                    end
                    EllesmereUI.ApplyModuleFont(fs, nil, lsz, "actionBars", lflag)
                    fs:SetTextColor(lr, lg, lb, 1)
                    fs:SetRotation(lrot)
                    local hh = fs:GetStringHeight()
                    if not hh or hh <= 0 then hh = fs:GetLineHeight() end
                    if not hh or hh <= 0 then hh = lsz end
                    hh = hh / 2
                    -- The line's centre along the bar (it spans pos to pos + one).
                    local mid = pos + one / 2
                    local x, y = mid, across
                    if vertical then x, y = across, mid end
                    fs:ClearAllPoints()
                    fs:SetPoint("CENTER", holder, "BOTTOMLEFT",
                        x + lox - hh * lsin, y + loy - hh * (1 - lcos))
                    fs._pct = pct
                    fs:Show()
                end
            elseif style5 == "none" then
                -- No 5% marks: the 10% lines alone.
            elseif style5 == "solid" then
                -- A single continuous line across the bar (like the 10% lines).
                nTick = nTick + 1
                local t = tick[nTick]
                if not t then t = host:CreateTexture(nil, "OVERLAY"); tick[nTick] = t end
                t:SetColorTexture(r5, g5, b5, a5)
                t:ClearAllPoints()
                if vertical then
                    t:SetSize(solidFull, one)
                    t:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", solidC0, pos)
                else
                    t:SetSize(one, solidFull)
                    t:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", pos, solidC0)
                end
                t._pct = pct
                t:Show()
            else
                -- Dashes/dots across the bar, the run centred.
                for d = 0, count - 1 do
                    nTick = nTick + 1
                    local t = tick[nTick]
                    if not t then t = host:CreateTexture(nil, "OVERLAY"); tick[nTick] = t end
                    t:SetColorTexture(r5, g5, b5, a5)
                    t:ClearAllPoints()
                    if vertical then
                        t:SetSize(dash, one)
                        t:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", dash0 + d * step, pos)
                    else
                        t:SetSize(one, dash)
                        t:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", pos, dash0 + d * step)
                    end
                    t._pct = pct
                    t:Show()
                end
            end
        end
    end
    for i = nTick + 1, #tick do tick[i]:Hide() end
    for i = nLbl + 1, #lbl do lbl[i]:Hide() end
    -- Every mark is shown here; Smart Ticks then hides the passed ones.
    host._nTick, host._nLbl, host._smart, host._anyHidden = nTick, nLbl, s.smartTicks and true or nil, nil
    ns.ApplyDataBarSmartTicks(holder)
end

-- Smart Ticks: the marks the fill has passed hide, the ones ahead stay. Called
-- on every XP bar value change; returns at once while dividers are off, and
-- while Smart Ticks is off with every mark shown.
function ns.ApplyDataBarSmartTicks(holder)
    local host = holder._divHost
    if not (host and host._nTick) then return end
    local smart = host._smart
    if not smart and not host._anyHidden then return end
    local bar = holder._bar
    local _, maxv = bar:GetMinMaxValues()
    local curPct = (smart and maxv > 0) and (bar:GetValue() / maxv * 100) or -1
    local tick, lbl = host._tick, host._lbl
    local anyHidden
    for i = 1, host._nTick do
        local t = tick[i]
        local on = t._pct >= curPct
        if not on then anyHidden = true end
        t:SetShown(on)
    end
    for i = 1, host._nLbl do
        local fs = lbl[i]
        fs:SetShown(fs._pct >= curPct)
    end
    host._anyHidden = anyHidden
end

-- The XP Bar tab's style selector (options addon): "default" = Blizzard's
-- own XP and reputation bars (the profile's one useBlizzardDataBars switch,
-- which the Use Blizzard's Rep Bars toggle also sets), "eui" = the
-- EllesmereUI bar, "prof" = in the Professions frame, "forever" = in WoW
-- Forever's border.
function EllesmereUI._GetXPBarStyle()
    local p = EAB.db and EAB.db.profile
    if not p then return "eui" end
    if p.useBlizzardDataBars then return "default" end
    local s = p.bars and p.bars.XPBar
    return (s and s.xpArt) or "eui"
end

-- A Blizz Default <-> EllesmereUI swap flips that switch live through
-- ns.SetUseBlizzardDataBars; the frame art applies live. Returns true while
-- our bars are wanted but were never built (a reload builds them), so the
-- caller can offer the reload.
function EllesmereUI._SetXPBarStyle(style)
    local p = EAB.db and EAB.db.profile
    if not p then return false end
    local wantBlizz = style == "default"
    local s = p.bars and p.bars.XPBar
    if s and not wantBlizz then
        s.xpArt = (style == "prof" or style == "forever") and style or nil
    end
    local reload = false
    if (p.useBlizzardDataBars and true or false) ~= wantBlizz then
        reload = ns.SetUseBlizzardDataBars(wantBlizz)
    end
    if not wantBlizz and dataBarFrames.XPBar then ApplyDataBarLayout("XPBar") end
    return reload or (not wantBlizz and not dataBarFrames.XPBar)
end

-- Whether an art style exists on this client ("forever" = WoW Forever's
-- border, on that client only).
function EllesmereUI._XPBarArtAvailable(style)
    if style == "forever" then return EllesmereUI.ForeverBorderOK() end
    local atlas = ns._XPArtAtlas[style]
    return atlas ~= nil and C_Texture.GetAtlasInfo(atlas) ~= nil
end

-------------------------------------------------------------------------------
--  XP Bar
-------------------------------------------------------------------------------
-- Max-level check with layered fallbacks. The Is* helpers are nil-guarded, so client
-- API churn can silently disable them -- a plain numeric compare against the expansion
-- max level backstops the check so the bar can never show for a max-level character.
function ns.XPBarAtMaxLevel()
    local level = UnitLevel("player") or 0
    if IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() then return true end
    if IsLevelAtEffectiveMaxLevel and IsLevelAtEffectiveMaxLevel(level) then return true end
    local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
        or (GetMaxPlayerLevel and GetMaxPlayerLevel())
    return (maxLevel and level >= maxLevel) or false
end

-- WoW Forever: raw XP under 10,000 is not abbreviated (EllesmereUI_NumberFormat.lua).
ns.AbbreviateLargeNumbers = (EllesmereUI.IS_FOREVER and EllesmereUI.ForeverAbbreviateLargeNumbers) or AbbreviateLargeNumbers
local function UpdateXPBar()
    local frame, s = EAB_VTABLE.ExtraBars.BeginManagedDataBarUpdate("XPBar")
    if not frame then return end

    local bar = frame._bar
    local text = frame._text

    -- Hide at max level (or XP disabled)
    if ns.XPBarAtMaxLevel() or (IsXPUserDisabled and IsXPUserDisabled()) then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(BAR_LOOKUP["XPBar"], frame, s, false, true)
        return
    end

    local currentXP = UnitXP("player")
    local maxXP = UnitXPMax("player")
    if maxXP <= 0 then maxXP = 1 end
    local restedXP = GetXPExhaustion() or 0
    local level = UnitLevel("player")

    -- Smart profession fill: one flipbook pass on each XP gain (a level-up
    -- resets XP low but is still a gain).
    if frame._fvFlipSmart then
        local lv = frame._lastXPLevel
        if lv and (level > lv or (level == lv and currentXP > frame._lastXP)) then
            ns.PlayXPFlipOnce(frame)
        end
        frame._lastXP, frame._lastXPLevel = currentXP, level
    end

    bar:SetMinMaxValues(0, maxXP)
    bar:SetValue(currentXP)
    ns.ApplyDataBarSmartTicks(frame)

    -- Rested XP overlay
    local restedBar = frame._restedBar
    if restedXP > 0 then
        bar:SetStatusBarColor(ns.ResolveDataBarColor(s, XP_BAR_COLORS.xpRested.r, XP_BAR_COLORS.xpRested.g, XP_BAR_COLORS.xpRested.b))
        restedBar:SetMinMaxValues(0, maxXP)
        restedBar:SetValue(min(currentXP + restedXP, maxXP))
        -- Rested Color (the XP Bar tab), else the dark blue at half opacity.
        local rc = s.restedColor or XP_BAR_COLORS.xpRestedBG
        restedBar:SetStatusBarColor(rc.r, rc.g, rc.b, rc.a or 0.5)
        restedBar:Show()
    else
        bar:SetStatusBarColor(ns.ResolveDataBarColor(s, XP_BAR_COLORS.xpNoRest.r, XP_BAR_COLORS.xpNoRest.g, XP_BAR_COLORS.xpNoRest.b))
        restedBar:Hide()
    end

    local config = (EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars["XPBar"]) or {}
    local showLevel = config.showLevel
    local showRawValues = config.showRawValues

    local strLevel = ""
    local strXP = ""
    local strRested = ""

    if showLevel then
        strLevel = format("%s %d - ", LEVEL, level)
    end

    if showRawValues then
        strXP = format("%s / %s", ns.AbbreviateLargeNumbers(currentXP), ns.AbbreviateLargeNumbers(maxXP))
    else
        local pct = (currentXP / maxXP) * 100
        strXP = format("%.1f%%", pct)
    end

    if restedXP > 0 then
        if showRawValues then
            strRested = format(EllesmereUI.L(" (Rested: %s)"), ns.AbbreviateLargeNumbers(restedXP))
        else
            local restedPct = (restedXP / maxXP) * 100
            strRested = format(EllesmereUI.L(" (Rested: %.1f%%)"), restedPct)
        end
    end

    -- Show %: append the XP percentage after raw values, e.g. "1234 / 5678 (21.7%)".
    -- Only when raw values are shown (otherwise strXP is already the percentage).
    local strPct = ""
    if config.showPercent and showRawValues then
        strPct = format(" (%.1f%%)", (currentXP / maxXP) * 100)
    end

    text:SetText(strLevel .. strXP .. strPct .. strRested)
    if frame._textPost then ns.DataBarPlaceText(frame, s) end

    EAB_VTABLE.ExtraBars.FinishManagedDataBarUpdate("XPBar", frame, s)
end

-- Called by CreateManagedDataBarFrames (EllesmereUIActionBars.lua) when the
-- data bars are built at enable.
function ns.CreateXPBar()
    local holder = CreateDataBarFrame("XPBar", UpdateXPBar)
    holder:SetPoint("TOP", UIParent, "TOP", 0, -100)

    -- Rested XP overlay bar (behind main bar)
    local restedBar = CreateFrame("StatusBar", "EllesmereEAB_XPBar_Rested", holder)
    restedBar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then
        PP.SetInside(restedBar, holder, 1, 1)
    else
        restedBar:SetPoint("TOPLEFT", 1, -1)
        restedBar:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    restedBar:SetMinMaxValues(0, 1)
    restedBar:SetValue(0)
    restedBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 2)
    restedBar:Hide()
    holder._restedBar = restedBar

    -- Tooltip. Click Through suppresses it: on a mouseover bar the holder keeps mouse
    -- motion only so the hover fade can see the cursor.
    holder:EnableMouse(true)
    holder:SetScript("OnEnter", function(self)
        local cfg = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars["XPBar"]
        if cfg and cfg.clickThrough then return end
        if ns.XPBarAtMaxLevel() or (IsXPUserDisabled and IsXPUserDisabled()) then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        local currentXP = UnitXP("player")
        local maxXP = UnitXPMax("player")
        if maxXP <= 0 then maxXP = 1 end
        local restedXP = GetXPExhaustion() or 0
        local pct = (currentXP / maxXP) * 100
        local remain = maxXP - currentXP
        GameTooltip:AddLine(EllesmereUI.L("Experience"), 1, 1, 1)
        GameTooltip:AddDoubleLine(EllesmereUI.L("Level"), tostring(UnitLevel("player")), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(EllesmereUI.L("XP"), format("%s / %s (%.1f%%)", BreakUpLargeNumbers(currentXP), BreakUpLargeNumbers(maxXP), pct), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(EllesmereUI.L("Remaining"), BreakUpLargeNumbers(remain), 1, 1, 1, 1, 1, 1)
        if restedXP > 0 then
            GameTooltip:AddDoubleLine(EllesmereUI.L("Rested"), format("+%s (%.1f%%)", BreakUpLargeNumbers(restedXP), (restedXP / maxXP) * 100), 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    holder:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)

    -- Events
    local evFrame = ns.TakeShell()
    evFrame:RegisterEvent("PLAYER_XP_UPDATE")
    evFrame:RegisterEvent("PLAYER_LEVEL_UP")
    evFrame:RegisterEvent("UPDATE_EXHAUSTION")
    evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    evFrame:SetScript("OnEvent", UpdateXPBar)

    ApplyDataBarLayout("XPBar")
    UpdateXPBar()
end
