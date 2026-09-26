if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Portrait.lua
--
--  The party frames' portrait (Party tab PORTRAIT section), under every
--  style. Portrait Mode: None, Attached (a square the frame's height beside
--  the bars; the party box widens by it through ns.RF_PartyDims) or Detached
--  (off the health bar's edge with a shape mask and border, or inside the
--  bar with a 3D model). Art Style: 2D portrait, 3D model or class art. The
--  Party Frames kit keeps its own portrait socket and takes the Art Style
--  alone (2D or class).
--
--  Nothing here exists until the portrait is first turned on: the backdrop,
--  its textures, the bars' area frame and (3D only) the model are built on
--  that first pass, and the portrait events register only while the party
--  frames are shown with a portrait that needs them (RF_KitPortraitEvents).
--  State lives on our own backdrop frame, st.pt, where `st` is a header
--  button's FFD entry (never a key on the button) or the preview frame.
--  Layout is out of combat only (the aura containers make the bars
--  protected); painting runs any time.
-------------------------------------------------------------------------------
local _, ns = ...

local PP = EllesmereUI.PP

local MASKS, BORDERS = EllesmereUI.SHAPE_MASKS, EllesmereUI.SHAPE_BORDERS
local MASK_INSETS = EllesmereUI.SHAPE_INSETS
local CLASS_ART = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\"
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local QMARK_MODEL = "Interface\\Buttons\\TalkToMeQuestionMark.m2"

local function Point(r, p, rel, rp, x, y)
    if PP and PP.Point then PP.Point(r, p, rel, rp, x, y) else r:SetPoint(p, rel, rp, x, y) end
end

-- Class art from the shared sprite sheets.
function ns.RF_PtClassArt(tex, ct, style)
    local c = EllesmereUI.CLASS_ICON_SPRITE_COORDS and EllesmereUI.CLASS_ICON_SPRITE_COORDS[ct]
    if not (tex and c) then return end
    tex:SetTexture(CLASS_ART .. (style or "modern") .. ".tga")
    tex:SetTexCoord(c[1], c[2], c[3], c[4])
end

-- The attached portrait's width in the party box (callers snap): a square
-- the frame's full height. Detached and inside take no room.
function ns.RF_PtReserve(s, h)
    if (s.partyPortraitStyle or "none") ~= "attached" then return 0 end
    return h
end

-- Effective side and whether it sits inside the bar: an attached portrait
-- takes the left or right edge only, inside needs Detached.
local function SideOf(s, style)
    local side = s.partyPortraitSide or "left"
    local inside = side == "insideleft" or side == "insideright" or side == "insidecenter"
    if style == "attached" then
        if side ~= "right" then side = "left" end
        return side, false
    end
    return side, inside
end

-- 2D art re-seated on its stored rect (the backdrop, or the mask-expanded
-- rect of a shaped portrait): the portrait paint resets its anchors.
local function SeatArt2D(bd)
    local t = bd._2d
    if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(t) end
    t:ClearAllPoints()
    Point(t, "TOPLEFT", bd, "TOPLEFT", bd._oL, bd._oT)
    Point(t, "BOTTOMRIGHT", bd, "BOTTOMRIGHT", bd._oR, bd._oB)
end
local function SeatClassArt(bd, h)
    local t = bd._class
    local ci = math.floor(h * 0.08)
    t:ClearAllPoints()
    Point(t, "TOPLEFT", bd, "TOPLEFT", ci + bd._oL, -ci + bd._oT)
    Point(t, "BOTTOMRIGHT", bd, "BOTTOMRIGHT", -ci + bd._oR, ci + bd._oB)
end

-- The 3D model drops its model while hidden: every re-show repaints it.
local function ModelOnShow(self)
    local bd = self._bd
    local st = bd and bd._st
    if not (st and bd._on) then return end
    local owner = bd._owner
    local u = bd._pvUnit or (owner and not bd._preview and owner:GetAttribute("unit"))
    if u and UnitExists(u) then ns.RF_PtPaint(st, u, "Show") end
end
local function Ensure3D(bd)
    local m = bd._3d
    if m then return m end
    m = CreateFrame("PlayerModel", nil, bd)
    m:SetAllPoints(bd)
    m:SetCamera(0)
    m:EnableMouse(false)
    m._bd = bd
    m:SetScript("OnShow", ModelOnShow)
    m:Hide()
    bd._3d = m
    ns._ptModelOn = true
    return m
end

-- First enable: the backdrop and the bars' area. Health, power, the Top
-- Name Bar, the uniform anchor and the strips above the frame move onto
-- the area once; from then on a portrait change moves the area alone.
local function Ensure(owner, st, health)
    local bd = CreateFrame("Frame", nil, owner)
    bd:EnableMouse(false)
    local bg = bd:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 1)
    local t2 = bd:CreateTexture(nil, "ARTWORK")
    t2:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    t2:Hide()
    local tc = bd:CreateTexture(nil, "ARTWORK")
    tc:SetAlpha(0.8)
    tc:Hide()
    bd._bg, bd._2d, bd._class = bg, t2, tc
    bd._oL, bd._oT, bd._oR, bd._oB = 0, 0, 0, 0
    bd._owner, bd._st = owner, st
    bd._preview = (st == owner) or nil
    bd:Hide()

    local area = CreateFrame("Frame", nil, owner)
    area:EnableMouse(false)
    area:SetAllPoints(owner)
    bd._area = area
    health._euiBarArea = area
    local _, _, _, _, hy = health:GetPoint(1)
    health:ClearAllPoints()
    health:SetPoint("TOPLEFT", area, "TOPLEFT", 0, hy or 0)
    health:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, hy or 0)
    local power = st.power or st._power
    if power then
        power:ClearAllPoints()
        power:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 0, 0)
        power:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
    end
    local tnb = st.topNameBar or st._topNameBar
    if tnb then
        tnb:ClearAllPoints()
        tnb:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
        tnb:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, 0)
    end
    local uref = st.uniformRef or st._uniformRef
    if uref then
        uref:ClearAllPoints()
        uref:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        uref:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
    end
    -- The absorb strips re-lay out on their next settings pass.
    local ab = st.absorbBar or st._absorbBar
    if ab then
        if ab._topBar then ab._topBar._lpPos = nil end
        if ab._healTopBar then ab._healTopBar._lpPos = nil end
    end
    st.pt = bd
    return bd
end

-- The portrait and the bars' area for a style/side (out of combat).
local function Seat(owner, bd, health, style, side, inside, size, px, py, bh)
    local area = bd._area
    bd:ClearAllPoints()
    area:ClearAllPoints()
    local w, h
    if style == "none" then
        area:SetAllPoints(owner)
        return 0, 0
    elseif style == "attached" then
        w, h = bh, bh
        bd:SetSize(w, h)
        if side == "right" then
            bd:SetPoint("TOPRIGHT", owner, "TOPRIGHT", 0, 0)
            area:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0)
            area:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -bh, 0)
        else
            bd:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0)
            area:SetPoint("TOPLEFT", owner, "TOPLEFT", bh, 0)
            area:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
        end
        bd._lvl = 1
    elseif inside then
        -- Over the health bar, the frame's height, clipped to itself.
        area:SetAllPoints(owner)
        w = bh + size
        if w < 8 then w = 8 end
        h = bh
        bd:SetWidth(w)
        if side == "insideleft" then
            bd:SetPoint("TOPLEFT", health, "TOPLEFT", px, py)
            bd:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", px, 0)
        elseif side == "insideright" then
            bd:SetPoint("TOPRIGHT", health, "TOPRIGHT", px, py)
            bd:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", px, 0)
        else
            bd:SetPoint("TOP", health, "TOP", px, py)
            bd:SetPoint("BOTTOM", owner, "BOTTOM", px, 0)
        end
        -- Above the fills, absorbs, power and Top Name Bar; under the
        -- dispel overlay, the border, text and auras.
        bd._lvl = 6
    else
        -- Detached: off the health bar's edge, a little larger than the
        -- frame, over its neighbours' borders.
        area:SetAllPoints(owner)
        w = bh + size + 10
        if w < 8 then w = 8 end
        h = w
        bd:SetSize(w, h)
        local y = py + 5
        if side == "top" then
            bd:SetPoint("BOTTOM", health, "TOP", px, 15 + y)
        elseif side == "right" then
            bd:SetPoint("TOPLEFT", health, "TOPRIGHT", 15 + px, y)
        else
            bd:SetPoint("TOPRIGHT", health, "TOPLEFT", -15 + px, y)
        end
        bd._lvl = 11
    end
    bd:SetClipsChildren(inside and true or false)
    return w, h
end

local function Unmask(bd)
    local mk = bd._mask
    if not (mk and bd._masked) then return end
    bd._2d:RemoveMaskTexture(mk)
    bd._class:RemoveMaskTexture(mk)
    bd._bg:RemoveMaskTexture(mk)
    if bd._border then bd._border:RemoveMaskTexture(mk) end
    bd._masked = nil
    mk:Hide()
end

-- Detached shape: the mask over the art and background, the border ring
-- (natively 7px, grown outward so `size` px of it show past the mask) and
-- the art enlarged to fill the mask's opening. Anything else: plain square
-- art filling the backdrop. `w`/`h` = the backdrop's size.
local function Shape(bd, s, shaped, w, h)
    local shape = shaped and (s.partyPortraitShape or "portrait") or nil
    if shape and not MASKS[shape] then shape = nil end
    local bs = s.partyPortraitBorderSize or 7
    local op = s.partyPortraitBorderOpacity or 100
    local art = s.partyPortraitArtScale or 100
    local col = s.partyPortraitBorderColor
    local cr, cg, cb = col and col.r or 0, col and col.g or 0, col and col.b or 0
    local cc = s.partyPortraitBorderClassColor ~= false
    if bd._sShape == shape and bd._sBs == bs and bd._sOp == op and bd._sArt == art
        and bd._sW == w and bd._sH == h and bd._sR == cr and bd._sG == cg and bd._sB == cb
        and bd._sCC == cc and bd._sSet then
        return false
    end
    bd._sShape, bd._sBs, bd._sOp, bd._sArt, bd._sW, bd._sH = shape, bs, op, art, w, h
    bd._sR, bd._sG, bd._sB, bd._sCC, bd._sSet = cr, cg, cb, cc, true
    bd._tintClass = nil
    if not shape then
        Unmask(bd)
        if bd._border then bd._border:Hide() end
        bd._oL, bd._oT, bd._oR, bd._oB = 0, 0, 0, 0
    else
        local mk = bd._mask
        if not mk then
            mk = bd:CreateMaskTexture()
            bd._mask = mk
        end
        mk:ClearAllPoints()
        if bs >= 1 then
            Point(mk, "TOPLEFT", bd, "TOPLEFT", 1, -1)
            Point(mk, "BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
        else
            mk:SetAllPoints(bd)
        end
        mk:SetTexture(MASKS[shape], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mk:Show()
        local bt = bd._border
        if not bt then
            bt = bd:CreateTexture(nil, "OVERLAY")
            bd._border = bt
        end
        local e = 7 - bs
        bt:ClearAllPoints()
        Point(bt, "TOPLEFT", bd, "TOPLEFT", -e, e)
        Point(bt, "BOTTOMRIGHT", bd, "BOTTOMRIGHT", e, -e)
        bt:SetTexture(BORDERS[shape])
        if not bd._masked then
            bd._2d:AddMaskTexture(mk)
            bd._class:AddMaskTexture(mk)
            bd._bg:AddMaskTexture(mk)
            bt:AddMaskTexture(mk)
            bd._masked = true
        end
        bd._bA = op / 100
        bt:SetVertexColor(cr, cg, cb, bd._bA)
        bd._tintClass = cc or nil
        bt:Show()
        local vis = (128 - 2 * (MASK_INSETS[shape] or 17)) / 128
        local ex = ((1 / vis) * (art / 100) - 1) * 0.5
        bd._oL, bd._oT, bd._oR, bd._oB = -(ex * w), ex * h, ex * w, -(ex * h)
    end
    SeatArt2D(bd)
    SeatClassArt(bd, h)
    -- A model is never masked or enlarged: it stays on the backdrop.
    if bd._3d then bd._3d:SetAllPoints(bd) end
    return true
end

-- Class-coloured shape border: the unit's class for players, its reaction
-- colour otherwise, the player's own class in dark mode or with no unit.
local function PlayerClassColor()
    local _, ct = UnitClass("player")
    local c = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end
local function TintBorder(bd, unit, ctOverride)
    local bt = bd._border
    if not (bt and bd._tintClass) then return end
    local r, g, b
    local s = ns._scaledPartyProxy
    if ctOverride then
        local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ctOverride]
        if c then r, g, b = c.r, c.g, c.b end
    elseif s and s.healthColorMode == "dark" then
        r, g, b = PlayerClassColor()
    elseif unit and UnitExists(unit) then
        local _, ct = UnitClass(unit)
        local isPl = UnitIsPlayer(unit)
        if not issecretvalue(ct) and not issecretvalue(isPl) and isPl and ct then
            local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
            if c then r, g, b = c.r, c.g, c.b end
        else
            local re = UnitReaction(unit, "player")
            local c = (not issecretvalue(re)) and re and FACTION_BAR_COLORS and FACTION_BAR_COLORS[re]
            if c then r, g, b = c.r, c.g, c.b end
        end
    end
    if not r then r, g, b = PlayerClassColor() end
    bt:SetVertexColor(r, g, b, bd._bA or 1)
end

-- Which art region shows. Leaving 3D drops the model (frees it). True when
-- the mode changed.
local function SetMode(bd, mode)
    if bd._mode == mode then return false end
    bd._mode = mode
    bd._guid, bd._state, bd._ct = nil, nil, nil
    bd._2d:SetShown(mode == "2d")
    bd._class:SetShown(mode == "class")
    if mode == "3d" then
        Ensure3D(bd)
        bd._3dOn = true
        bd._3d:Show()
        if not bd._preview then ns.RF_PtModelAlphaApply(bd) end
    elseif bd._3d then
        bd._3dOn = nil
        bd._3d:ClearModel()
        bd._3d:Hide()
    end
    return true
end

-- Paint (any time, combat included: our own textures and model only).
-- Repaints on a new occupant, an availability change or a real appearance
-- event; a secret guid never matches, so it always repaints. An
-- unavailable 3D paint never stamps its guid, so the next trigger heals it.
function ns.RF_PtPaint(st, unit, event)
    if st.kitPortrait then return ns.RF_KitPortrait(st, unit) end
    local bd = st.pt
    if not (bd and bd._on and unit) then return end
    local mode = bd._mode
    local guid = UnitGUID(unit)
    local changed
    if issecretvalue(guid) or issecretvalue(bd._guid) then
        changed = true
    else
        changed = bd._guid ~= guid
    end
    local repainted = false
    if mode == "class" then
        local _, ct = UnitClass(unit)
        if issecretvalue(ct) then ct = nil end
        ct = ct or "WARRIOR"
        -- (A change of art set clears _ct at its write in RF_PtApply.)
        if bd._ct ~= ct or event == "Force" then
            bd._ct = ct
            ns.RF_PtClassArt(bd._class, ct, bd._style)
            repainted = true
        end
        if not issecretvalue(guid) then bd._guid = guid end
    elseif mode == "3d" then
        local c, v = UnitIsConnected(unit), UnitIsVisible(unit)
        local avail = true
        if not (issecretvalue(c) or issecretvalue(v)) then avail = (c and v) and true or false end
        local m = bd._3d
        if m and (changed or bd._state ~= avail or event == "Force" or event == "UNIT_MODEL_CHANGED"
            or event == "UNIT_PORTRAIT_UPDATE" or event == "Show" or event == "PLAYER_ENTERING_WORLD"
            or (event == "PORTRAITS_UPDATED" and m:GetModelFileID() == nil)) then
            if avail then
                m:ClearModel()
                m:SetUnit(unit)
                m:SetPortraitZoom(1)
                m:SetPosition(0, 0, 0)
                bd._camZ = bd._zoom3d or 1
                m:SetCamDistanceScale(bd._camZ)
            else
                m:SetCamDistanceScale(0.25)
                m:SetPortraitZoom(0)
                m:SetPosition(0, 0, 0.25)
                m:ClearModel()
                m:SetModel(QMARK_MODEL)
                bd._camZ = nil
            end
            bd._guid = (avail and not issecretvalue(guid)) and guid or nil
            bd._state = avail
            repainted = true
        end
    else
        -- "Resync": the portrait events turning on (art may have streamed
        -- in while they were off).
        if changed or event == "Force" or event == "UNIT_PORTRAIT_UPDATE"
            or event == "PORTRAITS_UPDATED" or event == "UnitChanged" or event == "Resync" then
            local t = bd._2d
            SetPortraitTexture(t, unit)
            SeatArt2D(bd)
            t:SetDesaturated(bd._desat or false)
            if not issecretvalue(guid) then bd._guid = guid end
            repainted = true
        end
    end
    -- The class-coloured border follows the occupant (a real assignment
    -- too: a same-guid return after a no-unit re-shape).
    if repainted or changed or event == "UnitChanged" then TintBorder(bd, unit) end
end

-- Offline grey (from the health-background pass, which every connection
-- edge reaches): 2D and class desaturate, 3D swaps to the question mark.
function ns.RF_PtOffline(st, unit, connected)
    local bd = st.pt
    if not (bd and bd._on) then return end
    local off = not connected
    if bd._desat == off then return end
    bd._desat = off
    bd._2d:SetDesaturated(off)
    bd._class:SetDesaturated(off)
    if bd._mode == "3d" and unit then ns.RF_PtPaint(st, unit, "Conn") end
end

-- The whole pass for one party button or preview frame: build on first
-- enable, seat (deferred to the regen party pass only while a frame it
-- moves is protected: the aura containers protect the bars once anchored;
-- the first layout after a combat /reload applies at once), shape, art
-- mode, then paint `unit` when given. A settings pass paints only what its
-- memos say changed (a mode swap clears them), so it never reloads a model
-- that shows the right unit.
function ns.RF_PtApply(owner, st, s, bw, bh, unit)
    local style = s.partyPortraitStyle or "none"
    local bd = st.pt
    if style == "none" and not bd then return end
    local health = st.health or st._health
    if not health then return end
    local side, inside = SideOf(s, style)
    local size = s.partyPortraitSize or 0
    local px, py = s.partyPortraitX or 0, s.partyPortraitY or 0
    local es = owner:GetEffectiveScale()
    if not (bd and bd._gStyle == style and bd._gSide == side and bd._gIn == inside
        and bd._gSize == size and bd._gX == px and bd._gY == py
        and bd._gW == bw and bd._gH == bh and bd._gEs == es) then
        if InCombatLockdown() then
            local power = st.power or st._power
            local uref = st.uniformRef or st._uniformRef
            if health:IsProtected() or (power and power:IsProtected())
                or (uref and uref:IsProtected()) or (bd and bd._area:IsProtected()) then
                ns._partyKitDirtyInCombat = true
                return
            end
        end
        bd = bd or Ensure(owner, st, health)
        bd._gStyle, bd._gSide, bd._gIn, bd._gSize, bd._gX, bd._gY = style, side, inside, size, px, py
        bd._gW, bd._gH, bd._gEs = bw, bh, es
        bd._w, bd._h = Seat(owner, bd, health, style, side, inside, size, px, py, bh)
    end
    if style == "none" then
        if bd._on then
            bd._on = nil
            bd:Hide()
            SetMode(bd, nil)
        end
        return
    end
    -- Levels re-asserted every pass (a strata change rebuilds child levels).
    local lvl = owner:GetFrameLevel() + (bd._lvl or 1)
    if bd:GetFrameLevel() ~= lvl then bd:SetFrameLevel(lvl) end
    local mode = s.partyPortraitMode or "2d"
    -- The class art set is a paint input: a change clears the class memo
    -- (a button with no unit repaints on its next occupant).
    local cs = s.partyPortraitClassStyle or "modern"
    if bd._style ~= cs then bd._style = cs; bd._ct = nil end
    bd._zoom3d = (s.partyPortrait3dZoom or 100) / 100
    -- Background under square and shaped art; none under a bare model.
    local shaped = style == "detached" and (s.partyPortraitShape or "portrait") ~= "none"
    bd._bg:SetShown(not inside and (style == "attached" or shaped))
    local reshaped = Shape(bd, s, shaped, bd._w, bd._h)
    local wasOn = bd._on
    bd._on = true
    local swapped = SetMode(bd, mode)
    if not wasOn then bd:Show() end
    -- A 3D Zoom change on a loaded model: the camera alone.
    local m = bd._3dOn and bd._3d
    if m and bd._state and bd._camZ and bd._camZ ~= bd._zoom3d then
        bd._camZ = bd._zoom3d
        m:SetCamDistanceScale(bd._zoom3d)
    end
    if unit then
        ns.RF_PtPaint(st, unit, "Apply")
        -- The border colour is in no paint memo (a re-shape, dark mode).
        TintBorder(bd, unit)
        -- A new model starts at full alpha: take the unit's range fade now.
        if swapped and mode == "3d" and not bd._preview and ns._UpdateButtonRange then
            ns._UpdateButtonRange(unit, owner)
        end
    elseif reshaped and bd._tintClass and not bd._preview then
        -- A re-shaped border takes the default colour: re-tint it.
        local u = owner:GetAttribute("unit")
        TintBorder(bd, (u and UnitExists(u)) and u or nil)
    end
end

-- Portrait events the current settings need (RF_KitPortraitEvents): "2d",
-- "3d" or nil (class art and a portrait that is off need none). The kit
-- never runs a model.
function ns.RF_PtEventMode(kit)
    local s = ns._scaledPartyProxy
    local m = s.partyPortraitMode or "2d"
    if kit then return (m ~= "class") and "2d" or nil end
    if (s.partyPortraitStyle or "none") == "none" or m == "class" then return nil end
    return (m == "3d") and "3d" or "2d"
end

-- Every party button, repainted (a zone-in resets models at the same
-- guid; the shown edge re-syncs after a hidden stretch).
function ns.RF_PtRepaintAll(event)
    local list = ns._partyAllButtons
    if not list then return end
    local GetFFD = ns.GetFFD
    for i = 1, #list do
        local b = list[i]
        local d = GetFFD(b)
        if d.kitPortrait or (d.pt and d.pt._on) then
            local u = b:GetAttribute("unit")
            if u and UnitExists(u) then ns.RF_PtPaint(d, u, event) end
        end
    end
end

-- The options' light path (every portrait setting but the ones that change
-- the box width): re-apply each party button, re-sync the events.
function ns.RF_PtRefreshAll()
    local list = ns._partyAllButtons
    local db = ns.db
    if not (list and db and db.profile) then return end
    local GetFFD = ns.GetFFD
    local s = ns._scaledPartyProxy
    local pw, ph = ns.RF_PartyDims(db.profile)
    local bw, bh = ns.PixelSnap(pw), ns.PixelSnap(ph)
    for i = 1, #list do
        local b = list[i]
        local d = GetFFD(b)
        if d.styled then
            local u = b:GetAttribute("unit")
            if u and not UnitExists(u) then u = nil end
            if d.kitPortrait then
                if u then ns.RF_KitPortrait(d, u) end
            else
                ns.RF_PtApply(b, d, s, bw, bh, u)
            end
        end
    end
    if ns.RF_KitPortraitEvents then ns.RF_KitPortraitEvents(ns._partyFramesVisible) end
end

-------------------------------------------------------------------------------
--  3D model alpha: a PlayerModel does not take its parent's alpha, so the
--  model mirrors the button's range fade (a secret in-range boolean goes
--  straight through SetAlphaFromBoolean) and the party container's alpha
--  (the options previews hide the live frames through it). Only runs while
--  a model exists.
-------------------------------------------------------------------------------
function ns.RF_PtModelAlphaApply(bd)
    local m = bd._3dOn and bd._3d
    if not m then return end
    local pc = ns._partyContainerFrame
    local c = pc and pc:GetAlpha() or 1
    if bd._rSecret then
        m:SetAlphaFromBoolean(bd._rIn, c * bd._rA1, c * bd._rA2)
    else
        m:SetAlpha(c * (bd._rA1 or 1))
    end
end
function ns.RF_PtModelAlpha(st, a)
    local bd = st.pt
    if not (bd and bd._3dOn) then return end
    bd._rSecret, bd._rIn, bd._rA1, bd._rA2 = nil, nil, a, nil
    ns.RF_PtModelAlphaApply(bd)
end
function ns.RF_PtModelAlphaSecret(st, inRange, a1, a2)
    local bd = st.pt
    if not (bd and bd._3dOn) then return end
    local m = bd._3d
    if not m.SetAlphaFromBoolean then
        return ns.RF_PtModelAlpha(st, a1)
    end
    bd._rSecret, bd._rIn, bd._rA1, bd._rA2 = true, inRange, a1, a2
    ns.RF_PtModelAlphaApply(bd)
end
-- The container's alpha moved (callers gate on ns._ptModelOn): re-mirror.
function ns.RF_PtContainerAlpha()
    local list = ns._partyAllButtons
    if not list then return end
    local GetFFD = ns.GetFFD
    for i = 1, #list do
        local bd = GetFFD(list[i]).pt
        if bd and bd._3dOn then ns.RF_PtModelAlphaApply(bd) end
    end
end

-------------------------------------------------------------------------------
--  Options preview: the party preview frame takes the same pass (built on
--  its first need; the raid preview never reaches here), then a mock paint:
--  the player's own portrait or model in the player's slot, the class crest
--  in the others (five copies of one face, or five models, would read
--  wrong), class art per slot, the offline slot greyed.
-------------------------------------------------------------------------------
function ns.RF_PtPreview(f, s, classToken, isPlayer, offline)
    if (s.partyPortraitStyle or "none") == "none" and not f.pt then return end
    local db = ns.db
    local pw, ph = ns.RF_PartyDims(ns._pvOverlayProxy or (db and db.profile) or s)
    local bw, bh = ns.PixelSnap(pw), ns.PixelSnap(ph)
    f:SetSize(bw, bh)
    ns.RF_PtApply(f, f, s, bw, bh, nil)
    local bd = f.pt
    if not (bd and bd._on) then return end
    local _, playerCT = UnitClass("player")
    local mode = bd._mode
    local tc = (not isPlayer) and classToken and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken]
    bd._pvUnit = nil
    if mode == "class" then
        ns.RF_PtClassArt(bd._class, classToken or playerCT or "WARRIOR", bd._style)
    else
        local t2 = bd._2d
        if tc then
            if bd._3d then bd._3d:Hide() end
            t2:SetTexture(CLASS_SHEET)
            t2:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            SeatArt2D(bd)
            t2:Show()
        elseif mode == "3d" then
            t2:Hide()
            local m = bd._3d
            if m then
                -- Loaded once: the paint memos keep a preview refresh from
                -- reloading it (a hidden model paints on its show edge).
                bd._pvUnit = "player"
                if m:IsShown() then
                    ns.RF_PtPaint(f, "player", "Apply")
                else
                    m:Show()
                end
            end
        else
            t2:SetTexCoord(0.15, 0.85, 0.15, 0.85)
            SetPortraitTexture(t2, "player")
            SeatArt2D(bd)
            t2:Show()
        end
    end
    local grey = offline and true or false
    bd._desat = grey
    bd._2d:SetDesaturated(grey)
    bd._class:SetDesaturated(grey)
    TintBorder(bd, nil, classToken or playerCT)
end
