if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_Castbar.lua
--
--  Cast icon geometry, the kick tick and cast colors, CreateCastBar, show on
--  cast bar and the Blizzard cast bar state. Publishes through I; loads before
--  Builders, which re-imports from it. db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, ns = ...

local issecretvalue = issecretvalue
local PP = EllesmereUI.PP

local I = ns._internals
local frames, GetSettingsForUnit = I.frames, I.GetSettingsForUnit
local GetCastbarColor, SetFSFont = I.GetCastbarColor, I.SetFSFont
local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-- Cast-bar icon "part of the bar" resolver. True = icon counts inside the cast bar's
-- width (icon inside footprint, fill inset to its right, like Resource Bars). False =
-- icon outside the width. Requires the icon shown; a hidden icon is never "in width".
local function CastIconInWidth(unit, s)
    s = s or GetSettingsForUnit(unit)
    if not s then return true end
    -- The stock styles count a shown icon as part of the bar whatever the
    -- toggle says: their frame art wraps bar and icon together, and a width
    -- match lines up with that footprint.
    if ns.UF_Blizz() then
        if unit == "player" then return s.showPlayerCastIcon ~= false end
        return s.showCastIcon ~= false
    end
    -- An icon moved onto the portrait (Show Icon on Portrait) is never in width.
    if ns.UF_CastIconOnPortrait(unit, s) then return false end
    if unit == "player" then
        return s.showPlayerCastIcon ~= false and s.playerCastbarIconInWidth ~= false
    end
    return s.showCastIcon ~= false and s.castbarIconInWidth ~= false
end
-- Shared with the options preview, so it lays the icon out the same way.
ns.UF_CastIconInWidth = CastIconInWidth

-- Whether the cast spell icon is shown at all. Independent of "part of the
-- bar" (CastIconInWidth folds this in already for its own purposes, but
-- ns.UF_ApplyCastIconBorder needs the shown state on its own: a hidden icon
-- shares no edge with the bar).
local function CastIconShown(unit, s)
    s = s or GetSettingsForUnit(unit)
    if not s then return true end
    if unit == "player" then
        return s.showPlayerCastIcon ~= false
    end
    return s.showCastIcon ~= false
end

-- Show Icon on Portrait (player / target / focus, opt-in): true while the
-- cast icon sits over the unit's portrait instead of beside the bar. Needs
-- the icon shown and a visible portrait (Portrait Mode and Art Style not
-- None); the stock styles own the icon. Settings only, so the options preview
-- and the cast bar's size-match pad read the same answer. On ns (local cap).
function ns.UF_CastIconOnPortrait(unit, s)
    if not s then return false end
    local key = (unit == "player") and "playerCastbarIconOnPortrait" or "castbarIconOnPortrait"
    if s[key] ~= true or ns.UF_Blizz() or not CastIconShown(unit, s) then return false end
    local p = db.profile
    if (s.portraitStyle or p.portraitStyle or "attached") == "none" or s.showPortrait == false then return false end
    return (s.portraitMode or p.portraitMode or "2d") ~= "none"
end

-- Whether the cast spell icon sits on the RIGHT of the bar instead of the
-- default left. Independent of "part of the bar"; defaults off (left).
local function CastIconOnRight(unit, s)
    s = s or GetSettingsForUnit(unit)
    if not s then return false end
    if unit == "player" then
        return s.playerCastbarIconRight == true
    end
    return s.castbarIconRight == true
end

-- Additive X/Y nudge for the cast spell icon. Applies to the icon frame's anchors
-- only -- the bar fill and footprint never move.
local function CastIconOffsets(unit, s)
    s = s or GetSettingsForUnit(unit)
    if not s then return 0, 0 end
    if unit == "player" then
        return s.playerCastIconOffsetX or 0, s.playerCastIconOffsetY or 0
    end
    return s.castIconOffsetX or 0, s.castIconOffsetY or 0
end

-- Border Wraps Icon (s.castBorderWrapIcon, opt-in): the Custom Border Style
-- takes in an integrated icon, only while it sits flush (no offset); else
-- the border wraps the bar alone. Settings only, so the border, the shared
-- edge pass and the size-match pad read one answer. On ns (local cap).
function ns.UF_CastBorderWrapsIcon(unit, s)
    if not (s and s.castBorderCustom == true and s.castBorderWrapIcon == true) then return false end
    if not CastIconInWidth(unit, s) then return false end
    local offX, offY = CastIconOffsets(unit, s)
    return offX == 0 and offY == 0
end

-- Vertical Separator: the divider draws as Solid's flat line (also with
-- Custom Border Style off) or in a style's own divider art; a textured style
-- without that art, or a Border Size of 0, draws none. Shared with the
-- options row's disabled state. On ns (local cap).
function ns.UF_CastIconSeamOK(s)
    if not (s and s.castBorderCustom == true) then return true end
    if (s.castBorderSize or 1) <= 0 then return false end
    local tex = s.castBorderStyle or "solid"
    return tex == "solid" or tex == "" or EllesmereUI.GetBorderCompanion(tex, "sepV") ~= nil
end

-- Classic WoW UI: the settings key holding a cast bar's frame size (its
-- Border Size percentage; player keys carry the player prefix). On ns for
-- the local cap.
function ns.UF_CastClassicKey(unit)
    return unit == "player" and "playerCastbarStockBorderScale" or "castbarStockBorderScale"
end

-- Anchor the cast spell icon and inset the fill based on whether the icon is part of
-- the bar width. inWidth=true -> icon at the bar's edge, fill inset by icon width
-- (castbarBg becomes the full footprint, so unlock mode/width matching count the icon
-- for free). inWidth=false -> icon hangs outside the bar width.
--
-- Icon HEIGHT anchors to the bar bg's top AND bottom so it always equals the bar
-- height: a live bg:GetHeight() read is unreliable during creation/login (bg not yet
-- at final height/scale). iconH is the configured cast bar height (castbarHeight/
-- playerCastbarHeight), used only for the square WIDTH and matching fill inset so
-- those stay deterministic; falls back to bg:GetHeight().
--
-- portraitBd: the portrait backdrop the icon sits on (Show Icon on Portrait,
-- laid out by ns.UF_CastIconPortrait, which the callers run as this argument),
-- else nil. With it the bar takes the whole holder and no seam is shared.
local function LayoutCastbarIcon(castbar, inWidth, iconH, onRight, offX, offY, iconShown, framePct, portraitBd)
    if not castbar then return end
    local bg = castbar:GetParent()
    if not bg then return end
    -- Classic WoW UI frame size, read by the style's cast pass.
    castbar._classicPct = framePct
    -- Callers pass the configured height: a holder on the Blizzard Style
    -- aura block reads back a secret rect, size included.
    local side = iconH or bg:GetHeight()
    if issecretvalue(side) then return end
    local iconFrame = castbar._iconFrame
    offX, offY = offX or 0, offY or 0
    -- The style's own icon pass (ns.UF_BlizzCastIcon) re-lays the icon from
    -- these after the stock chrome is on.
    castbar._icoInWidth, castbar._icoOnRight, castbar._icoSide = inWidth, onRight, side
    castbar._icoOffX, castbar._icoOffY, castbar._icoShown = offX, offY, iconShown
    if iconFrame and not portraitBd then
        iconFrame:ClearAllPoints()
        if inWidth then
            -- Icon inside the footprint, flush with the chosen edge.
            if onRight then
                PP.Point(iconFrame, "TOPRIGHT", bg, "TOPRIGHT", offX, offY)
                PP.Point(iconFrame, "BOTTOMRIGHT", bg, "BOTTOMRIGHT", offX, offY)
            else
                PP.Point(iconFrame, "TOPLEFT", bg, "TOPLEFT", offX, offY)
                PP.Point(iconFrame, "BOTTOMLEFT", bg, "BOTTOMLEFT", offX, offY)
            end
        else
            -- Icon hangs outside the bar, off the chosen edge.
            if onRight then
                PP.Point(iconFrame, "TOPLEFT", bg, "TOPRIGHT", offX, offY)
                PP.Point(iconFrame, "BOTTOMLEFT", bg, "BOTTOMRIGHT", offX, offY)
            else
                PP.Point(iconFrame, "TOPRIGHT", bg, "TOPLEFT", offX, offY)
                PP.Point(iconFrame, "BOTTOMRIGHT", bg, "BOTTOMLEFT", offX, offY)
            end
        end
        iconFrame:SetWidth(side)
    end
    castbar:ClearAllPoints()
    if portraitBd then
        -- The icon sits on the portrait: the bar takes the whole footprint.
        PP.Point(castbar, "TOPLEFT", bg, "TOPLEFT", 0, 0)
        PP.Point(castbar, "BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
    elseif inWidth and onRight then
        -- Bar occupies the left of the footprint; icon takes the right edge.
        PP.Point(castbar, "TOPLEFT", bg, "TOPLEFT", 0, 0)
        PP.Point(castbar, "BOTTOMRIGHT", bg, "BOTTOMRIGHT", -side, 0)
    else
        PP.Point(castbar, "TOPLEFT", bg, "TOPLEFT", inWidth and side or 0, 0)
        PP.Point(castbar, "BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
    end
end

-- Cast bar Custom Border Style (s.castBorderCustom, opt-in per unit; boss1-5
-- share one table). Off: the 1px black border CreateCastBar drew on the bar
-- stays as it is; only the icon decoration pass runs and nothing is built
-- unless one of its options is enabled.
-- On: that border hides and the chosen style draws on castbar._cbBorder, our
-- own child frame of the bar built on first enable, so it shows and hides with
-- the bar as the old border did. It wraps the bar alone, or icon and bar
-- together under Border Wraps Icon (ns.UF_CastBorderWrapsIcon). It sits under
-- the cast text overlay; Show Behind drops it under the bar's holder.
-- Settings passes only (creation and ReloadFrames, after LayoutCastbarIcon).
-- An exact size re-applies on a UI scale change through ApplyBorderStyle's
-- own edgePx registration. Stands down under a stock style: stock = nil reads
-- the session's latched style; the options preview (which shares this)
-- passes its own and preview = true. On ns: the local cap.
function ns.UF_ApplyCastBorder(castbar, s, stock, unit, icon, preview)
    if not castbar then return end
    if stock == nil then stock = ns.UF_Blizz() end
    local host = castbar._cbBorder
    if stock or not (s and s.castBorderCustom == true) then
        if castbar._cbHost then
            castbar._cbHost = nil
            EllesmereUI.HideBorderStyle(host)
            host:Hide()
            -- The bar's own border back (the stock chrome keeps it hidden).
            if not stock then PP.ShowBorder(castbar) end
        end
        ns.UF_ApplyCastIconBorder(castbar, s, stock, unit, icon, preview)
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, castbar)
        castbar._cbBorder = host
    end
    host:ClearAllPoints()
    if ns.UF_CastBorderWrapsIcon(unit, s) then
        -- The fill gives up the icon's width (the configured cast bar height,
        -- as LayoutCastbarIcon insets it): reach past the fill by that much on
        -- the icon's side. Anchored to the fill so the options preview uses
        -- the same rule.
        local side = (unit == "player") and (s.playerCastbarHeight or 14) or (s.castbarHeight or 14)
        local onRight = CastIconOnRight(unit, s)
        PP.Point(host, "TOPLEFT", castbar, "TOPLEFT", onRight and 0 or -side, 0)
        PP.Point(host, "BOTTOMRIGHT", castbar, "BOTTOMRIGHT", onRight and side or 0, 0)
    else
        host:SetAllPoints(castbar)
    end
    castbar._cbHost = host
    PP.HideBorder(castbar)
    -- Levelled before the apply: a textured style's backdrop takes the host's.
    if s.castBorderBehind then
        host:SetFrameLevel(math.max(0, (castbar:GetParent() or castbar):GetFrameLevel() - 1))
    else
        -- Over the fill, shield and kick marker (bar +2), under the text overlay.
        local lvl = castbar:GetFrameLevel() + 3
        local ovr = castbar.Text and castbar.Text:GetParent()
        if ovr and ovr ~= castbar then lvl = math.min(lvl, ovr:GetFrameLevel() - 1) end
        host:SetFrameLevel(lvl)
    end
    local tex = s.castBorderStyle or "solid"
    local size = s.castBorderSize or 1
    local c = s.castBorderColor
    local px = EllesmereUI.BorderPx(s.castBorderSizePx, size, tex)
    EllesmereUI.ApplyBorderStyle(host, size, c and c.r or 0, c and c.g or 0, c and c.b or 0,
        s.castBorderAlpha or 1, tex, s.castBorderOffsetX, s.castBorderOffsetY,
        s.castBorderShiftX, s.castBorderShiftY, "unitframes", size, nil, px)
    castbar._cbSolid = (tex == "solid" or tex == "") and size > 0
    castbar._cbSize = px or size
    ns.UF_ApplyCastIconBorder(castbar, s, stock, unit, icon, preview)
end

-- Cast icon decoration, shared by live frames and the options preview. New
-- resources are built only on opt-in, during the existing settings pass.
-- preview = the options preview's bar: its divider is never registered for
-- the UI-scale re-layout (the preview re-lays it on every update).
function ns.UF_ApplyCastIconBorder(castbar, s, stock, unit, icon, preview)
    icon = icon or castbar._iconFrame
    if not icon then return end
    local shown = CastIconShown(unit, s)
    local portrait = ns.UF_CastIconOnPortrait(unit, s)
    local inWidth = CastIconInWidth(unit, s)
    local onRight = CastIconOnRight(unit, s)
    local offX, offY = CastIconOffsets(unit, s)
    local custom = s and s.castBorderCustom == true
    local styled = not stock and shown and not portrait and s and s.castIconBorder == true
    local host = icon._castBorder
    local tex = custom and (s.castBorderStyle or "solid") or "solid"
    local size = custom and (s.castBorderSize or 1) or 1
    local c = custom and s.castBorderColor
    local alpha = custom and (s.castBorderAlpha or 1) or 1
    local px = custom and EllesmereUI.BorderPx(s.castBorderSizePx, size, tex) or nil
    if styled then
        if not host then
            host = CreateFrame("Frame", nil, icon)
            host:SetAllPoints(icon)
            icon._castBorder = host
        end
        host:SetFrameLevel(custom and s.castBorderBehind and math.max(0, icon:GetFrameLevel() - 1) or icon:GetFrameLevel() + 1)
        PP.HideBorder(icon)
        EllesmereUI.ApplyBorderStyle(host, size, c and c.r or 0, c and c.g or 0, c and c.b or 0,
            alpha, tex, custom and s.castBorderOffsetX or nil, custom and s.castBorderOffsetY or nil,
            custom and s.castBorderShiftX or nil, custom and s.castBorderShiftY or nil, "unitframes", size, nil, px)
    elseif host then
        EllesmereUI.HideBorderStyle(host)
        host:Hide()
        if not stock and not portrait then PP.ShowBorder(icon) end
    end

    -- Icon and bar each draw a full border (the bar's own 1px one, or a custom
    -- Solid one at its size): flush, both would draw the shared edge, so each
    -- drops its facing side. Only while the icon is shown beside the bar with
    -- no offset and no Icon Border of its own; a textured or hidden custom
    -- border shares none. Under Border Wraps Icon the custom border is the
    -- outside edge of both: it keeps every side and the icon drops its facing
    -- one.
    if not stock then
        local iconEdges = PP.GetBorders(icon)
        local barFrame = castbar._cbHost or castbar
        local barEdges = PP.GetBorders(barFrame)
        local barDrawn = barEdges and (barFrame == castbar or castbar._cbSolid)
        local share = shown and not portrait and offX == 0 and offY == 0 and not styled
        local outer = castbar._cbHost and ns.UF_CastBorderWrapsIcon(unit, s)
        if iconEdges then
            local hide = share and (barDrawn or outer)
            iconEdges._hideLeft = hide and onRight or nil
            iconEdges._hideRight = hide and not onRight or nil
            PP.SetBorderSize(icon, 1)
        end
        if barEdges then
            local hide = share and barDrawn and not outer
            barEdges._hideLeft = hide and not onRight or nil
            barEdges._hideRight = hide and onRight or nil
            if barDrawn then PP.SetBorderSize(barFrame, barFrame == castbar and 1 or castbar._cbSize) end
        end
    end

    local seam = castbar._iconSeam
    if not (s and s.castIconSeparator == true and not stock and shown and inWidth and not portrait
            and ns.UF_CastIconSeamOK(s)) then
        if seam then
            seam:Hide()
            EllesmereUI.RegisterPxReapply(seam, nil)
        end
        return
    end
    if not seam then
        seam = CreateFrame("Frame", nil, castbar)
        seam:SetAllPoints(castbar)
        seam._tex = seam:CreateTexture(nil, "OVERLAY")
        castbar._iconSeam = seam
    end
    -- Above the cast border, including Solid's child at border level +1.
    local borderFrame = castbar._cbHost or castbar
    seam:SetFrameLevel(math.max(castbar:GetFrameLevel(), borderFrame:GetFrameLevel()) + 2)
    seam._key, seam._size, seam._px, seam._right = tex, size, px, onRight
    seam._path = EllesmereUI.GetBorderCompanion(tex, "sepV")
    seam._tex:SetVertexColor(c and c.r or 0, c and c.g or 0, c and c.b or 0, alpha)
    ns.UF_LayoutCastIconSeam(seam)
    seam:Show()
    EllesmereUI.RegisterPxReapply(seam, (not preview) and ns.UF_LayoutCastIconSeam or nil)
end

-- Lays the divider from the values the pass above stamped (also the UI-scale
-- re-layout). A style's divider art goes through the shared placement, its
-- lead hanging past the bar's edge over the icon; Solid draws a flat line on
-- the bar's edge at the border's exact size.
function ns.UF_LayoutCastIconSeam(seam)
    local t = seam._tex
    local es = seam:GetEffectiveScale()
    if seam._path then
        EllesmereUI.PlaceBorderDividerV(t, seam, seam._right, false, seam._key, seam._size, seam._px, es)
        return
    end
    local onePixel = es > 0 and PP.perfect / es or PP.mult
    t:SetColorTexture(1, 1, 1, 1)
    t:SetTexCoord(0, 1, 0, 1)
    t:ClearAllPoints()
    if seam._right then
        t:SetPoint("TOPRIGHT", seam, "TOPRIGHT", 0, 0)
        t:SetPoint("BOTTOMRIGHT", seam, "BOTTOMRIGHT", 0, 0)
    else
        t:SetPoint("TOPLEFT", seam, "TOPLEFT", 0, 0)
        t:SetPoint("BOTTOMLEFT", seam, "BOTTOMLEFT", 0, 0)
    end
    t:SetWidth(math.max(1, math.floor((seam._px or seam._size) + 0.5)) * onePixel)
    t:Show()
end

-- Size matching: the width and height a Custom Border Style cast border
-- draws OUTSIDE the cast bar holder (the unlock element's frame), from the
-- same arguments ns.UF_ApplyCastBorder passes; nil while the opt-in is off,
-- for Solid and under the stock styles, so the pad stays exactly as before.
-- The border wraps the bar, which an in-width icon insets inside the holder
-- by the icon's width (the configured cast bar height): that side's reach
-- shrinks by it. Under Border Wraps Icon (ns.UF_CastBorderWrapsIcon) it
-- wraps the whole holder instead. Each side clamps at 0 before the sum.
-- Settings only.
function ns.UF_CastBorderPad(unit, s)
    if not (s and s.castBorderCustom == true) or ns.UF_Blizz() then return nil end
    local tex = s.castBorderStyle or "solid"
    local size = s.castBorderSize or 1
    local l, r, t, b = EllesmereUI.BorderReach(size, tex, s.castBorderOffsetX, s.castBorderOffsetY,
        s.castBorderShiftX, s.castBorderShiftY, "unitframes", size,
        EllesmereUI.BorderPx(s.castBorderSizePx, size, tex), nil, s.castBorderAlpha or 1)
    if not l then return nil end
    if CastIconInWidth(unit, s) and not ns.UF_CastBorderWrapsIcon(unit, s) then
        local iw = (unit == "player") and (s.playerCastbarHeight or 14) or (s.castbarHeight or 14)
        if CastIconOnRight(unit, s) then r = r - iw else l = l - iw end
    end
    local w = (l > 0 and l or 0) + (r > 0 and r or 0)
    local h = (t > 0 and t or 0) + (b > 0 and b or 0)
    if w <= 0 and h <= 0 then return nil end
    return w, h
end

-- Show Icon on Portrait: lays the cast icon over the portrait backdrop bd, or
-- (bd nil) hands it back to the bar layout. ico = the cast icon frame, tex =
-- its texture, s = the unit's settings. Our own frames only (the options
-- preview shares this with its own icon and portrait). The icon's 1px border
-- and black plate hide and its texture fills the frame; on a shaped detached
-- portrait it is clipped by the icon frame's OWN mask (built on first use)
-- carrying the portrait's shape art, since a mask owned by the portrait's
-- frame tree is not relied on across trees. That mask sits inset so its
-- opening stops at the shape border's inner edge, which keeps the ring in
-- view round the icon. Levelled over the backdrop and its 3D model.
-- ico._pbd = the backdrop it sits on.
function ns.UF_CastIconPortraitLayout(ico, tex, bd, s)
    if not bd then
        if not ico._pbd then return end
        ico._pbd = nil
        PP.ShowBorder(ico)
        if ico._bg then ico._bg:Show() end
        if tex then
            if ico._pMaskOn then tex:RemoveMaskTexture(ico._pMask); ico._pMaskOn = nil end
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", ico, "TOPLEFT", 1, -1)
            tex:SetPoint("BOTTOMRIGHT", ico, "BOTTOMRIGHT", -1, 1)
        end
        local holder = ico:GetParent()
        if holder then
            ico:SetFrameStrata(holder:GetFrameStrata())
            ico:SetFrameLevel(holder:GetFrameLevel() + 1)
        end
        return
    end
    ico._pbd = bd
    PP.HideBorder(ico)
    if ico._bg then ico._bg:Hide() end
    ico:ClearAllPoints()
    ico:SetAllPoints(bd)
    -- The portrait's strata, not the raised cast bar's: the frame border
    -- (frame +10) still closes an attached portrait's edges over the icon.
    ico:SetFrameStrata(bd:GetFrameStrata())
    ico:SetFrameLevel(bd:GetFrameLevel() + 2)
    if not tex then return end
    tex:ClearAllPoints()
    tex:SetAllPoints(ico)
    -- A detached portrait's shape; attached and shape-less ones are square.
    local shape = ((s.portraitStyle or db.profile.portraitStyle or "attached") == "detached")
        and (s.detachedPortraitShape or "portrait") or "none"
    local maskPath = shape ~= "none" and ns.PORTRAIT_MASKS[shape]
    if maskPath then
        local m = ico._pMask
        if not m then
            m = ico:CreateMaskTexture()
            ico._pMask = m
        end
        -- The backdrop mask's own inset, widened until the icon's opening meets
        -- the shape border's inner edge (all in backdrop px, W wide): the ring
        -- art's solid band ends at MASK_INSETS texels of its 128 (an unmasked
        -- ring, ns.UF_UNMASKED_RING: 9 texels into its inset rect), the ring
        -- rect grows by 7 - Size per side, and the mask's opening lies about
        -- 12 of its 128 texels in.
        local band = s.detachedPortraitBorderSize or 7
        local inset = (band >= 1) and 1 or 0
        if band >= 1 and ns.PORTRAIT_BORDERS[shape] then
            local W = bd:GetWidth()
            if W < 1 then W = 46 end
            local exp = 7 - band
            local unmasked = ns.UF_UNMASKED_RING[shape]
            local inner
            if unmasked then
                local ri = unmasked - exp
                inner = ri + 9 / 128 * (W - 2 * ri)
            else
                inner = -exp + (ns.MASK_INSETS[shape] or 17) / 128 * (W + 2 * exp)
            end
            local need = (inner - 12 / 128 * W) * 128 / 104
            if need > inset then inset = need end
        end
        m:ClearAllPoints()
        m:SetPoint("TOPLEFT", bd, "TOPLEFT", inset, -inset)
        m:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -inset, inset)
        if m._path ~= maskPath then
            m:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m._path = maskPath
        end
        m:Show()
        if not ico._pMaskOn then
            tex:AddMaskTexture(m)
            ico._pMaskOn = true
        end
    elseif ico._pMaskOn then
        tex:RemoveMaskTexture(ico._pMask)
        ico._pMaskOn = nil
    end
end

-- The live cast bar's side of Show Icon on Portrait, run as LayoutCastbarIcon's
-- portraitBd argument: returns the backdrop the icon now sits on, or nil. One
-- settings test while off; the layout runs only while on or on the pass that
-- turns it off.
function ns.UF_CastIconPortrait(castbar, frame, s, unit)
    local ico = castbar and castbar._iconFrame
    if not ico then return nil end
    local pt = frame and frame.Portrait
    local bd = pt and ns.UF_CastIconOnPortrait(unit, s) and pt.backdrop or nil
    if bd or ico._pbd then ns.UF_CastIconPortraitLayout(ico, castbar.Icon, bd, s) end
    return bd
end

-- Unlock position key for a unit's castbar, or nil.
local function CastbarUnlockKey(unit)
    if unit == "player" then return "playerCastbar"
    elseif unit == "target" then return "targetCastbar"
    elseif unit == "focus" then return "focusCastbar"
    end
end

-- Cast bar positioning is owned by the centralized unlock/anchor system
-- (ApplySavedPositions).

local function GetActiveKickSpell()
    return EllesmereUI.GetActiveKickSpell()
end
local function ComputeCastBarTint(readyTint, baseTint)
    if EllesmereUI and EllesmereUI.ComputeCastBarTint then
        return EllesmereUI.ComputeCastBarTint(readyTint, baseTint)
    end
    return baseTint.r, baseTint.g, baseTint.b
end
local function IsKickCastbarUnit(unit)
    return unit == "target" or unit == "focus" or (unit and unit:match("^boss") ~= nil)
end
local function GetCastbarKickTickEnabled(settings)
    if not settings then return true end
    if settings.castbarKickTickEnabled ~= nil then return settings.castbarKickTickEnabled end
    return true
end
local function GetCastbarInterruptMidCastEnabled(settings)
    if not settings then return false end
    if settings.castbarInterruptMidCastEnabled ~= nil then return settings.castbarInterruptMidCastEnabled end
    return false
end
local function GetCastbarUninterruptible(castbar)
    local v = castbar and castbar.notInterruptible
    if type(v) == "nil" then return false end
    return v
end
local function HideUnitFrameKickTick(castbar)
    if not castbar or not castbar.kickPositioner then return end
    castbar.kickPositioner:Hide()
    castbar.kickMarker:Hide()
    castbar.kickReadyFill:Hide()
    if castbar._kickTicker then
        castbar._kickTicker:Cancel()
        castbar._kickTicker = nil
    end
end
-- Hoisted defaults for the zero-alloc paint below: as inline literals these would
-- allocate on EVERY call when the setting was absent (the common case).
local UF_KICK_READY_TINT = { r = 0.92, g = 0.35, b = 0.20 }
local UF_UNINTERRUPT_GREY = { r = 0.5, g = 0.5, b = 0.5 }
local function ApplyUnitFrameCastColor(castbar)
    if not castbar or not castbar.castTintLayer then return end
    local settings = castbar._eufSettings
    local ownerUnit = castbar.__owner and castbar.__owner._euiUnit
    -- Zero-alloc: values flow as scalars instead of building up to three throwaway
    -- color tables per call (two default literals + the blended kick tint).
    local r, g, b
    if settings and settings.castbarClassColored and ownerUnit == "player" then
        local _, classToken = UnitClass(ownerUnit)
        if issecretvalue(classToken) then classToken = nil end
        if classToken and EllesmereUI.GetClassColor then
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then r, g, b = cc.r, cc.g, cc.b end
        end
    end
    if not r then
        local baseTint = (settings and settings.castbarFillColor) or GetCastbarColor()
        if IsKickCastbarUnit(ownerUnit) then
            local readyTint = (settings and settings.castbarInterruptReadyColor) or UF_KICK_READY_TINT
            r, g, b = ComputeCastBarTint(readyTint, baseTint)
        else
            r, g, b = baseTint.r, baseTint.g, baseTint.b
        end
    end
    castbar.castTintLayer:SetVertexColor(r, g, b)
    if castbar._shieldedTint then
        -- Uninterruptible overlay colour (defaults to grey). Its alpha is toggled
        -- from the secret "not interruptible" flag, so the colour is always set and
        -- only becomes visible on uninterruptible casts.
        local uc = (settings and settings.castbarUninterruptibleColor) or UF_UNINTERRUPT_GREY
        -- Explicit vertex alpha: Midnight's 3-arg SetVertexColor leaves the
        -- vertex alpha at an unexpected value (measured 0.5 with the gray
        -- default -- GetVertexColor returned a=r), and the composite with the
        -- region alpha rendered the shield faint-to-invisible. Visibility
        -- stays owned by SetAlphaFromBoolean below on the region slot.
        castbar._shieldedTint:SetVertexColor(uc.r, uc.g, uc.b, 1)
        local uninterruptible = GetCastbarUninterruptible(castbar)
        -- Visible alpha honors Fill Opacity (castbar._fillOp, nil at 100); both
        -- branches pass it as a plain number, never touching the secret. The
        -- boolean alpha drives the HOST FRAME -- texture SetAlphaFromBoolean
        -- renders 0 on Midnight despite healthy readbacks (see creation).
        local shieldTarget = castbar._shieldHost or castbar._shieldedTint
        if shieldTarget.SetAlphaFromBoolean then
            shieldTarget:SetAlphaFromBoolean(uninterruptible, castbar._fillOp or 1, 0)
        else
            shieldTarget:SetAlpha(uninterruptible and (castbar._fillOp or 1) or 0)
        end
    end
end
local function UpdateUnitFrameKickTick(castbar)
    if not castbar or not castbar.kickPositioner then return end
    local settings = castbar._eufSettings
    local ownerUnit = castbar.__owner and castbar.__owner._euiUnit
    if not IsKickCastbarUnit(ownerUnit) then
        HideUnitFrameKickTick(castbar)
        return
    end
    local tickOn = GetCastbarKickTickEnabled(settings)
    local midOn = GetCastbarInterruptMidCastEnabled(settings)
    if (not (tickOn or midOn)) or not GetActiveKickSpell() then
        HideUnitFrameKickTick(castbar)
        return
    end
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        HideUnitFrameKickTick(castbar)
        return
    end
    local kickProtected = GetCastbarUninterruptible(castbar)
    castbar._kickProtected = kickProtected
    local isChannel = castbar.channeling and true or false
    local isEmpowered = false
    if not (UnitCastingDuration and ownerUnit) then
        HideUnitFrameKickTick(castbar)
        return
    end
    local castDuration
    if isChannel then
        if UnitEmpoweredChannelDuration then
            castDuration = UnitEmpoweredChannelDuration(ownerUnit, true)
            if castDuration then isEmpowered = true end
        end
        if not castDuration and UnitChannelDuration then
            castDuration = UnitChannelDuration(ownerUnit)
        end
    else
        castDuration = UnitCastingDuration(ownerUnit)
    end
    if not castDuration then
        -- Transient read miss during an ongoing cast: skip, do NOT hide (a Hide/re-Show
        -- cycle on every SPELL_UPDATE_COOLDOWN would blink the tick during rotation).
        -- Cast end is handled by the cast-stop path.
        return
    end
    -- Cache cast identity so the light per-event refresh re-pins bar values from it
    -- without re-deriving channel/empower or re-minting fill geometry.
    castbar._kickIsChannel = isChannel
    castbar._kickIsEmpowered = isEmpowered
    local totalDur = castDuration:GetTotalDuration()
    local interruptCD = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
    if not interruptCD then
        -- Transient read miss (see above): skip, do not hide.
        return
    end
    local barW = castbar:GetWidth()
    local barH = castbar:GetHeight()
    -- Blizzard Style: a bar hanging off its frame's aura block resolves its
    -- rect through the engine aura container, a secret value under aura
    -- restriction. The tick keeps the size it took out of combat (the bar
    -- never resizes in combat), so nothing here may compare a secret.
    if issecretvalue(barW) or issecretvalue(barH) then return end
    if not barW or barW <= 0 then
        -- Transient zero-width during resize: skip, do not hide.
        return
    end
    castbar.kickPositioner:SetSize(barW, barH)
    castbar.kickPositioner:SetMinMaxValues(0, totalDur)
    castbar.kickMarker:SetMinMaxValues(0, totalDur)
    castbar.kickMarker:SetSize(barW, barH)
    castbar.kickPositioner:SetValue(castDuration:GetElapsedDuration())
    castbar.kickMarker:SetValue(interruptCD:GetRemainingDuration())
    castbar.kickTick:SetColorTexture(1, 1, 1, 1)
    if isChannel and not isEmpowered then
        castbar.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
        castbar.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
        -- LOAD-BEARING: SetFillStyle resets the inner fill to snap-ON and the global
        -- hook does not re-fire on a cached bar. Re-disable snap so the summed
        -- elapsed+remaining edge stays an exact float.
        local pt = castbar.kickPositioner:GetStatusBarTexture()
        if pt and pt.SetSnapToPixelGrid then pt:SetSnapToPixelGrid(false); pt:SetTexelSnappingBias(0) end
        local mt = castbar.kickMarker:GetStatusBarTexture()
        if mt and mt.SetSnapToPixelGrid then mt:SetSnapToPixelGrid(false); mt:SetTexelSnappingBias(0) end
        castbar.kickMarker:ClearAllPoints()
        castbar.kickTick:ClearAllPoints()
        castbar.kickMarker:SetPoint("RIGHT", castbar.kickPositioner:GetStatusBarTexture(), "LEFT")
        castbar.kickTick:SetPoint("TOP", castbar.kickMarker, "TOP", 0, 0)
        castbar.kickTick:SetPoint("BOTTOM", castbar.kickMarker, "BOTTOM", 0, 0)
        castbar.kickTick:SetPoint("RIGHT", castbar.kickMarker:GetStatusBarTexture(), "LEFT")
        -- Reverse fill (draining channel): kick-ready point is the marker texture LEFT
        -- edge; the available window runs from the channel end (bar left) to it.
        -- Not-in-time pushes that edge past the left edge, crossing anchors to zero width.
        castbar.kickReadyFill:ClearAllPoints()
        castbar.kickReadyFill:SetPoint("TOP", castbar, "TOP", 0, 0)
        castbar.kickReadyFill:SetPoint("BOTTOM", castbar, "BOTTOM", 0, 0)
        castbar.kickReadyFill:SetPoint("LEFT", castbar, "LEFT", 0, 0)
        castbar.kickReadyFill:SetPoint("RIGHT", castbar.kickMarker:GetStatusBarTexture(), "LEFT")
    else
        castbar.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Standard)
        castbar.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Standard)
        -- LOAD-BEARING: re-disable snap on the re-minted fill textures (see the
        -- reverse branch) so the tick stays stationary across every re-pin.
        local pt = castbar.kickPositioner:GetStatusBarTexture()
        if pt and pt.SetSnapToPixelGrid then pt:SetSnapToPixelGrid(false); pt:SetTexelSnappingBias(0) end
        local mt = castbar.kickMarker:GetStatusBarTexture()
        if mt and mt.SetSnapToPixelGrid then mt:SetSnapToPixelGrid(false); mt:SetTexelSnappingBias(0) end
        castbar.kickMarker:ClearAllPoints()
        castbar.kickTick:ClearAllPoints()
        castbar.kickMarker:SetPoint("LEFT", castbar.kickPositioner:GetStatusBarTexture(), "RIGHT")
        castbar.kickTick:SetPoint("TOP", castbar.kickMarker, "TOP", 0, 0)
        castbar.kickTick:SetPoint("BOTTOM", castbar.kickMarker, "BOTTOM", 0, 0)
        castbar.kickTick:SetPoint("LEFT", castbar.kickMarker:GetStatusBarTexture(), "RIGHT")
        -- Standard fill (cast/empowered channel): kick-ready point is the marker
        -- texture RIGHT edge; the window runs from it to the cast end (bar right).
        -- Not-in-time pushes that edge past the right edge, crossing anchors to zero width.
        castbar.kickReadyFill:ClearAllPoints()
        castbar.kickReadyFill:SetPoint("TOP", castbar, "TOP", 0, 0)
        castbar.kickReadyFill:SetPoint("BOTTOM", castbar, "BOTTOM", 0, 0)
        castbar.kickReadyFill:SetPoint("LEFT", castbar.kickMarker:GetStatusBarTexture(), "RIGHT")
        castbar.kickReadyFill:SetPoint("RIGHT", castbar, "RIGHT", 0, 0)
    end
    castbar.kickPositioner:Show()
    castbar.kickMarker:Show()
    -- Mid-cast fill: CLEAN DB color tint + CLEAN per-toggle visibility; its alpha (the
    -- SECRET on-CD x interruptible gate) is applied with the tick alpha below. Geometry
    -- above runs whenever the tick OR fill is enabled; SetShown gates each element to
    -- its own toggle so one never forces the other.
    local mc = (settings and settings.castbarInterruptMidCastColor) or { r = 0.318, g = 0.820, b = 0.357 }
    castbar.kickReadyFill:SetVertexColor(mc.r, mc.g, mc.b, 1)
    castbar.kickTick:SetShown(tickOn)
    castbar.kickReadyFill:SetShown(midOn)
    if interruptCD.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(kickProtected, 0, 1)
        local kickReady = interruptCD:IsZero()
        local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
        castbar.kickTick:SetAlpha(alpha)
        castbar.kickReadyFill:SetAlpha(alpha)
    else
        castbar.kickTick:SetAlpha(0)
        castbar.kickReadyFill:SetAlpha(0)
    end
    if castbar._kickTicker then castbar._kickTicker:Cancel() end
    castbar._kickTicker = C_Timer.NewTicker(0.1, function()
        if not castbar:IsShown() or not ownerUnit then
            HideUnitFrameKickTick(castbar)
            return
        end
        if not GetActiveKickSpell() then
            HideUnitFrameKickTick(castbar)
            return
        end
        local icd = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
        if icd and icd.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(castbar._kickProtected, 0, 1)
            local kickReady = icd:IsZero()
            local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
            castbar.kickTick:SetAlpha(alpha)
            castbar.kickReadyFill:SetAlpha(alpha)
        end
    end)
end

-- Light per-cooldown-event refresh: bar values + tick alpha only. Geometry (SetSize,
-- anchors, SetFillStyle, color) is cast-identity work done once by
-- UpdateUnitFrameKickTick. Re-pin positioner(elapsed) and marker(remaining) together to
-- keep the tick stationary; NEVER re-pin one without the other.
local function RefreshUnitFrameKickTick(castbar)
    if not castbar or not castbar.kickPositioner then return end
    if not GetActiveKickSpell() or not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        HideUnitFrameKickTick(castbar)
        return
    end
    local interruptCD = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
    if not interruptCD then
        -- Transient read miss during an ongoing cast: skip, do not hide.
        return
    end
    local ownerUnit = castbar.__owner and castbar.__owner._euiUnit
    if not (UnitCastingDuration and ownerUnit) then return end
    local castDuration
    if castbar._kickIsChannel then
        if castbar._kickIsEmpowered and UnitEmpoweredChannelDuration then
            castDuration = UnitEmpoweredChannelDuration(ownerUnit, true)
        end
        if not castDuration and UnitChannelDuration then
            castDuration = UnitChannelDuration(ownerUnit)
        end
    else
        castDuration = UnitCastingDuration(ownerUnit)
    end
    if not castDuration then
        -- Transient read miss (see above): skip, do not hide.
        return
    end
    castbar.kickPositioner:SetValue(castDuration:GetElapsedDuration())
    castbar.kickMarker:SetValue(interruptCD:GetRemainingDuration())
    if interruptCD.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(castbar._kickProtected, 0, 1)
        local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(interruptCD:IsZero(), 0, interruptible)
        castbar.kickTick:SetAlpha(alpha)
        castbar.kickReadyFill:SetAlpha(alpha)
    end
end

ns._castingCastbars = {}
local activeCastbarCount = 0
local _ufCastColorTicker
local ufKickWatcher = CreateFrame("Frame")
ufKickWatcher:SetScript("OnEvent", function(_, event)
    if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_USABLE" then
        for cb in pairs(ns._castingCastbars) do
            if cb:IsShown() and cb.__owner and cb.__owner._euiUnit then
                ApplyUnitFrameCastColor(cb)
                -- Light refresh once the kick bars are set up; re-run the full geometry/
                -- fill setup only when not shown (kick learned mid-cast, CD info late,
                -- toggle flipped on). Stops SetFillStyle from re-minting the inner fill
                -- textures every cooldown event, which re-snapped them to the pixel grid.
                if cb.kickPositioner and not cb.kickPositioner:IsShown() then
                    UpdateUnitFrameKickTick(cb)
                else
                    RefreshUnitFrameKickTick(cb)
                end
            end
        end
    end
end)
local function NotifyCastbarStarted(castbar)
    if not castbar or not castbar.__owner then return end
    if not IsKickCastbarUnit(castbar.__owner._euiUnit) then return end
    if ns._castingCastbars[castbar] then return end
    ns._castingCastbars[castbar] = true
    activeCastbarCount = activeCastbarCount + 1
    if activeCastbarCount == 1 then
        ufKickWatcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        ufKickWatcher:RegisterEvent("SPELL_UPDATE_USABLE")
        if GetActiveKickSpell() and not _ufCastColorTicker then
            _ufCastColorTicker = C_Timer.NewTicker(0.2, function()
                for cb in pairs(ns._castingCastbars) do
                    if cb:IsShown() then
                        ApplyUnitFrameCastColor(cb)
                    end
                end
            end)
        end
    end
end
local function NotifyCastbarEnded(castbar)
    if not castbar or not ns._castingCastbars[castbar] then return end
    ns._castingCastbars[castbar] = nil
    activeCastbarCount = activeCastbarCount - 1
    if activeCastbarCount <= 0 then
        activeCastbarCount = 0
        wipe(ns._castingCastbars)
        ufKickWatcher:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        ufKickWatcher:UnregisterEvent("SPELL_UPDATE_USABLE")
        if _ufCastColorTicker then
            _ufCastColorTicker:Cancel()
            _ufCastColorTicker = nil
        end
    end
end

local function CreateCastBar(frame, unit, settings)
    local settings = GetSettingsForUnit(unit)
    
    -- Standalone element parented to the oUF frame for compatibility, but sized
    -- and positioned independently. Blizzard Style: created with the layout
    -- aspect so it can hang off the frame's aura block (see ns.UF_LayoutAspectOK);
    -- its pieces below are all children and inherit it.
    local aspectTemplate = ns.UF_CastbarAspectTemplate(unit)
    local castbarBg = CreateFrame("Frame", nil, frame, aspectTemplate)
    if aspectTemplate then castbarBg._blizzAspect = true end

    -- Width/height always come from settings; nothing is auto-derived.
    local cbWidth, cbHeight
    if unit == "player" then
        cbWidth = db.profile.player.playerCastbarWidth or 181
        cbHeight = db.profile.player.playerCastbarHeight or 14
    else
        -- castbarWidth 0 = auto (boss frames match frame width; the boss update
        -- pass re-sizes to the live frame width right after creation).
        local cbw = settings.castbarWidth or 0
        cbWidth = cbw > 0 and cbw or 181
        cbHeight = settings.castbarHeight or 14
    end
    PP.Size(castbarBg, cbWidth, cbHeight)

    -- Position is owned by the centralized unlock system; this temporary anchor
    -- just gives the frame valid bounds until ApplySavedPositions runs at login
    -- (unlock default: BOTTOM of the parent unit frame).
    castbarBg:SetPoint("TOP", frame, "BOTTOM", 0, 0)

    local bgTex = castbarBg:CreateTexture(nil, "BACKGROUND")
    PP.Point(bgTex, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
    PP.Point(bgTex, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)
    -- Background color/alpha default to black 0.5 unless castBgColor/castBgAlpha
    -- are set.
    local _cbgC = settings.castBgColor
    bgTex:SetColorTexture(_cbgC and _cbgC.r or 0, _cbgC and _cbgC.g or 0, _cbgC and _cbgC.b or 0, settings.castBgAlpha or 0.5)
    castbarBg._bgTex = bgTex

    local castbar = CreateFrame("StatusBar", nil, castbarBg)
    PP.Point(castbar, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
    PP.Point(castbar, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)
    castbar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    castbar:GetStatusBarTexture():SetHorizTile(false)
    castbar:SetReverseFill(settings.castReverseFill and true or false)

    -- Borders draw on the castbar itself (same frame level as the fill texture) so
    -- the OVERLAY border sits above the ARTWORK fill. On castbarBg they would land
    -- BEHIND the fill, since castbar is its child and draws above it.
    PP.CreateBorder(castbar, 0, 0, 0, 1, 1, "OVERLAY", 0)


    -- Three-zone cast bar text layout matching nameplates: [spell name LEFT 42%]
    -- [target RIGHT-of-center 42%] [timer RIGHT]. All zones ellipsize (WordWrap off,
    -- MaxLines 1); text overlay sits above the unified border (frame +10).
    local textOverlay = CreateFrame("Frame", nil, castbar)
    textOverlay:SetAllPoints(castbar)
    textOverlay:SetFrameLevel(frame:GetFrameLevel() + 11)

    local text = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(text, settings.castSpellNameSize or 11)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetMaxLines(1)
    text:SetTextColor(1, 1, 1)
    castbar.Text = text

    local time = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(time, settings.castDurationSize or 10)
    time:SetJustifyH("RIGHT")
    time:SetWordWrap(false)
    time:SetMaxLines(1)
    time:SetTextColor(1, 1, 1)
    castbar.Time = time

    local target = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(target, settings.castSpellTargetSize or 11)
    target:SetJustifyH("RIGHT")
    target:SetWordWrap(false)
    target:SetMaxLines(1)
    target:SetTextColor(1, 1, 1)
    target:Hide()
    castbar.Target = target

    -- Side-aware three-zone layout (mirrors the nameplate cast text system). Each
    -- element has a side; duration reserves its slot and pushes whichever non-center
    -- element shares that side (center is never pushed). Spell name hides on side
    -- "none"; target/duration visibility rides _showTarget/_showDuration (their
    -- dropdown "None" clears those flags).
    local function LayoutCastTextZones(cb)
        local barW = cb:GetWidth()
        -- Secret under aura restriction when the bar rides the aura block
        -- (Blizzard Style): keep the out-of-combat layout, the width is fixed.
        if issecretvalue(barW) then return end
        if not barW or barW <= 0 then return end
        -- +5px so the timer text has a little extra room before it truncates.
        local timerW = (cb._durationSize or 10) * 2.2 + 5
        local showDur = cb._showDuration ~= false
        local nameSide = cb._nameSide or "left"
        local tgtSide  = cb._tgtSide or "right"
        local durSide  = cb._durSide or "right"
        local textW = barW * 0.42
        -- The 42% reserves the opposite half for the cast target. When this unit never
        -- shows a target (boss frames: showCastTarget false with no UI to enable it)
        -- the name owns the row and gets 80% before truncating.
        local nameW = (cb._showTarget == false) and (barW * 0.80) or textW
        -- Combine Spell Name and Target suppresses the target element, so the combined
        -- name owns the row and gets the wide budget.
        cb.Text:ClearAllPoints()
        if nameSide == "none" then
            cb.Text:Hide()
        else
            local pt, xb, jh = ns.GetCastTextAnchor(nameSide, showDur and durSide == nameSide, timerW, false)
            cb.Text:SetWidth(cb._combineNT and (barW * 0.80) or nameW)
            cb.Text:SetJustifyH(jh)
            cb.Text:SetPoint(pt, cb, pt, xb + (cb._nameOX or 0), 1 + (cb._nameOY or 0))
            cb.Text:Show()
        end
        -- Spell target; visibility is handled by _showTarget / hasTarget elsewhere.
        do
            local pt, xb, jh = ns.GetCastTextAnchor(tgtSide, showDur and durSide == tgtSide, timerW, false)
            cb.Target:ClearAllPoints()
            cb.Target:SetWidth(textW)
            cb.Target:SetJustifyH(jh)
            cb.Target:SetPoint(pt, cb, pt, xb + (cb._tgtOX or 0), (cb._tgtOY or 0))
        end
        -- Duration/timer: side is only "left"/"right"; visibility via _showDuration.
        do
            local pt, xb, jh = ns.GetCastTextAnchor(durSide, false, timerW, true)
            cb.Time:ClearAllPoints()
            cb.Time:SetWidth(timerW)
            cb.Time:SetJustifyH(jh)
            cb.Time:SetPoint(pt, cb, pt, xb + (cb._durOX or 0), (cb._durOY or 0))
        end
        -- Re-flow so a live JustifyH change takes effect on already-rendered text.
        ns.ReflowFontString(cb.Text)
        ns.ReflowFontString(cb.Target)
        ns.ReflowFontString(cb.Time)
    end
    castbar._durationSize = settings.castDurationSize or 10
    castbar._nameOX = settings.castSpellNameX or 0
    castbar._nameOY = settings.castSpellNameY or 0
    castbar._durOX = settings.castDurationX or 0
    castbar._durOY = settings.castDurationY or 0
    castbar._tgtOX = settings.castSpellTargetX or 0
    castbar._tgtOY = settings.castSpellTargetY or 0
    castbar._nameSide = settings.castSpellNameSide or "left"
    castbar._tgtSide  = settings.castSpellTargetSide or "right"
    castbar._durSide  = settings.castDurationSide or "right"
    castbar._showDuration = settings.showCastDuration ~= false
    castbar._showTarget = settings.showCastTarget ~= false
    castbar._layoutTextZones = LayoutCastTextZones
    LayoutCastTextZones(castbar)

    -- Helper: sync all offset/size/side cache values from settings onto
    -- the castbar, then re-layout. Called from live refresh paths.
    castbar._syncOffsetsAndLayout = function(self, s)
        self._durationSize = s.castDurationSize or 10
        self._nameOX = s.castSpellNameX or 0
        self._nameOY = s.castSpellNameY or 0
        self._durOX  = s.castDurationX or 0
        self._durOY  = s.castDurationY or 0
        self._tgtOX  = s.castSpellTargetX or 0
        self._tgtOY  = s.castSpellTargetY or 0
        self._nameSide = s.castSpellNameSide or "left"
        self._tgtSide  = s.castSpellTargetSide or "right"
        self._durSide  = s.castDurationSide or "right"
        self._showDuration = s.showCastDuration ~= false
        if self._layoutTextZones then self:_layoutTextZones() end
    end

    local castTintLayer = castbar:CreateTexture(nil, "ARTWORK", nil, 1)
    castTintLayer:SetPoint("TOPLEFT", castbar:GetStatusBarTexture(), "TOPLEFT")
    castTintLayer:SetPoint("BOTTOMRIGHT", castbar:GetStatusBarTexture(), "BOTTOMRIGHT")
    castTintLayer:SetTexture("Interface\\Buttons\\WHITE8X8")
    local c = GetCastbarColor()
    castTintLayer:SetVertexColor(c.r, c.g, c.b)
    castTintLayer:SetAlpha(0)
    castbar.castTintLayer = castTintLayer
    castbar._castTintOn = nil

    -- The shield tint lives on its own child FRAME: the secret-safe show/hide
    -- rides SetAlphaFromBoolean, and on Midnight that API renders 0 on
    -- TEXTURES while GetAlpha reads back the true-branch value (measured
    -- 2026-08-12 -- perfect state readbacks, nothing painted). Frame alpha is
    -- the proven boolean lane (range fading uses it suite-wide).
    local shieldHost = CreateFrame("Frame", nil, castbar)
    shieldHost:SetAllPoints(castbar)
    shieldHost:SetAlpha(0)
    local shieldedTint = shieldHost:CreateTexture(nil, "ARTWORK", nil, 2)
    shieldedTint:SetPoint("TOPLEFT", castbar:GetStatusBarTexture(), "TOPLEFT")
    shieldedTint:SetPoint("BOTTOMRIGHT", castbar:GetStatusBarTexture(), "BOTTOMRIGHT")
    shieldedTint:SetTexture("Interface\\Buttons\\WHITE8X8")
    shieldedTint:SetVertexColor(0.5, 0.5, 0.5, 1)
    castbar._shieldedTint = shieldedTint
    castbar._shieldHost = shieldHost

    -- Cast bar reuses the unit's health bar texture (overridden donor-aware in ReloadFrames).
    ns.ApplyCastBarTexture(castbar, (settings and settings.healthBarTexture) or db.profile.healthBarTexture or "none")
    ns.ApplyCastFillOpacity(castbar, settings)

    local function OnCastbarCastActive(self)
        if self.castTintLayer then
            -- _fillOp is nil unless Fill Opacity is below 100 (see
            -- ns.ApplyCastFillOpacity), so the default path is unchanged.
            self.castTintLayer:SetAlpha(self._fillOp or 1)
            self._castTintOn = true
            ApplyUnitFrameCastColor(self)
            -- Blizzard Style: the fill art is its own colour, per cast kind.
            if self._blizzCast then
                self.castTintLayer:SetAlpha(0)
                self._castTintOn = nil
                ns.UF_SetBlizzCastFill(self, self.channeling and "channel" or "cast")
            end
        end
    end
    castbar.PostCastStart = OnCastbarCastActive
    castbar.PostChannelStart = OnCastbarCastActive

    castbar.PostCastInterruptible = function(self)
        ApplyUnitFrameCastColor(self)
        UpdateUnitFrameKickTick(self)
    end

    if IsKickCastbarUnit(unit) then
        local kickClip = CreateFrame("Frame", nil, castbar)
        kickClip:SetAllPoints(castbar)
        kickClip:SetClipsChildren(true)
        castbar.kickClip = kickClip
        local kickPositioner = CreateFrame("StatusBar", nil, kickClip)
        kickPositioner:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        kickPositioner:GetStatusBarTexture():SetAlpha(0)
        -- Pixel-snap OFF on the fill texture (mirrors Nameplates). The tick sits
        -- at positioner_width + marker_width; independent per-fill snapping makes
        -- round(a) + round(b) wobble 1px even though the summed fraction is
        -- invariant. Load-bearing unsnap is after each SetFillStyle below.
        if kickPositioner:GetStatusBarTexture().SetSnapToPixelGrid then
            kickPositioner:GetStatusBarTexture():SetSnapToPixelGrid(false)
            kickPositioner:GetStatusBarTexture():SetTexelSnappingBias(0)
        end
        kickPositioner:SetPoint("CENTER", castbar)
        kickPositioner:SetFrameLevel(castbar:GetFrameLevel() + 1)
        kickPositioner:Hide()
        castbar.kickPositioner = kickPositioner
        local kickMarker = CreateFrame("StatusBar", nil, kickClip)
        kickMarker:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        kickMarker:GetStatusBarTexture():SetAlpha(0)
        if kickMarker:GetStatusBarTexture().SetSnapToPixelGrid then
            kickMarker:GetStatusBarTexture():SetSnapToPixelGrid(false)
            kickMarker:GetStatusBarTexture():SetTexelSnappingBias(0)
        end
        kickMarker:SetPoint("LEFT", kickPositioner:GetStatusBarTexture(), "RIGHT")
        kickMarker:SetSize(1, 1)
        kickMarker:SetFrameLevel(castbar:GetFrameLevel() + 2)
        kickMarker:Hide()
        castbar.kickMarker = kickMarker
        local kickTick = kickMarker:CreateTexture(nil, "OVERLAY", nil, 3)
        kickTick:SetColorTexture(1, 1, 1, 1)
        kickTick:SetWidth(2)
        kickTick:SetPoint("TOP", kickMarker, "TOP", 0, 0)
        kickTick:SetPoint("BOTTOM", kickMarker, "BOTTOM", 0, 0)
        kickTick:SetPoint("LEFT", kickMarker:GetStatusBarTexture(), "RIGHT")
        castbar.kickTick = kickTick
        -- Interrupt-ready mid-cast fill: colors the cast-bar segment from the "kick
        -- ready here" point to the cast end (the window during which the interrupt will
        -- be available) when the kick is on cooldown now but comes off before the cast
        -- finishes. Rides the SAME kickMarker geometry as the tick; the "ready in time"
        -- two-secret test resolves by where the marker texture edge lands -- when the
        -- kick will NOT be ready in time the fill anchors cross to zero width and it
        -- self-hides with no Lua branch on a secret. ARTWORK sublevel 1 (created after
        -- castTintLayer so it draws above the fill colour) sits below the cast text
        -- (OVERLAY) and the uninterruptible grey (sublevel 2). Anchors are (re)applied
        -- per cast in UpdateUnitFrameKickTick.
        local kickReadyFill = castbar:CreateTexture(nil, "ARTWORK", nil, 1)
        kickReadyFill:SetColorTexture(1, 1, 1, 1)
        kickReadyFill:SetAlpha(0)
        kickReadyFill:Hide()
        castbar.kickReadyFill = kickReadyFill
    end

    castbar.CustomTimeText = function(self, durationObject)
        if self._showDuration == false then
            self.Time:SetText("")
            self.Time:Hide()
            self._timeBucket = nil
            return
        end
        self.Time:Show()
        if durationObject then
            -- oUF calls this per RENDER FRAME, but the displayed value has %.1f
            -- precision -- format + SetText only when the displayed tenth actually
            -- changes (~6x fewer at 60fps, more uncapped). Secret durations (other
            -- units' casts in combat) can't be floored: fail open to formatting every
            -- call (SetFormattedText accepts secrets). The delay branch is rare
            -- (pushback) and stays unmemoized.
            local duration = durationObject:GetRemainingDuration()
            if self.delay and self.delay ~= 0 then
                self._timeBucket = nil
                self.Time:SetFormattedText('%.1f|cffff0000%s%.2f|r', duration, self.channeling and '-' or '+', self.delay)
            elseif issecretvalue and issecretvalue(duration) then
                self._timeBucket = nil
                self.Time:SetFormattedText('%.1f', duration)
            else
                local bucket = math.floor(duration * 10)
                if bucket ~= self._timeBucket then
                    self._timeBucket = bucket
                    self.Time:SetFormattedText('%.1f', duration)
                end
            end
        end
    end
    castbar.CustomDelayText = castbar.CustomTimeText

    -- Cast spell icon (oUF sets castbar.Icon texture automatically). Size from the
    -- CONFIGURED height (cbHeight), not a live castbarBg:GetHeight() which is
    -- unreliable this early; LayoutCastbarIcon anchors height to the bar regardless,
    -- this is just the initial square.
    local iconSize = cbHeight
    local iconFrame = CreateFrame("Frame", nil, castbarBg)
    iconFrame:SetSize(iconSize, iconSize)
    PP.Point(iconFrame, "TOPRIGHT", castbarBg, "TOPLEFT", 0, 0)
    local iconBg = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconBg:SetAllPoints()
    iconBg:SetColorTexture(0, 0, 0, 1)
    iconFrame._bg = iconBg
    -- 1px black border via unified PP system
    PP.CreateBorder(iconFrame, 0, 0, 0, 1)
    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
    iconTex:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    castbar.Icon = iconTex
    castbar._iconFrame = iconFrame

    -- Initial icon/fill layout (re-applied on every reload by the per-unit
    -- update paths and whenever the cast-bar height changes).
    do
        local offX, offY = CastIconOffsets(unit, settings)
        LayoutCastbarIcon(castbar, CastIconInWidth(unit, settings), cbHeight, CastIconOnRight(unit, settings), offX, offY, CastIconShown(unit, settings), settings and settings[ns.UF_CastClassicKey(unit)],
            ns.UF_CastIconPortrait(castbar, frame, settings, unit))
        ns.UF_ApplyCastBorder(castbar, settings, nil, unit)
    end

    return castbar
end

-- Important Cast Glow (target/focus), mirrors Nameplates.
-- The secret IsSpellImportant flag only drives overlay alpha.
do
    local IMP_GLOW_COLOR = { r = 1, g = 0.2, b = 0.2 }
    local IMP_GLOW_BG_COLOR = { r = 0, g = 0, b = 0 }
    -- One scratch spec for both cast bars: StartSpecGlow reads it synchronously.
    local impSpec = {}

    ns.ClearUnitFrameImportantGlow = function(castbar)
        local ov = castbar and castbar._importantOverlay
        if not ov or not castbar._impGlowActive then return end
        EllesmereUI.Glows.StopAllGlows(ov)
        ov:SetAlpha(0)
        ov:Hide()
        castbar._impGlowActive = nil
    end

    -- Called from PostCastStart; the engine has already set castbar.spellID.
    ns.UpdateUnitFrameImportantGlow = function(castbar)
        local s = castbar and castbar._eufSettings
        local Glows = EllesmereUI.Glows
        if not (s and s.castbarImportantGlow and C_Spell and C_Spell.IsSpellImportant) then
            ns.ClearUnitFrameImportantGlow(castbar)
            return
        end
        -- Probe first: a readable "not important" never starts a glow. A secret
        -- answer (combat restriction) still takes the alpha path below.
        local ok, isImportant = pcall(C_Spell.IsSpellImportant, castbar.spellID or 0)
        if not ok or (not issecretvalue(isImportant) and not isImportant) then
            ns.ClearUnitFrameImportantGlow(castbar)
            return
        end

        local ov = castbar._importantOverlay
        if not ov then
            ov = CreateFrame("Frame", nil, castbar)
            ov:SetAllPoints(castbar)
            ov:EnableMouse(false)
            castbar._importantOverlay = ov
        end
        ov:SetFrameLevel(castbar:GetFrameLevel() + 5)

        local c = s.castbarImportantGlowColor or IMP_GLOW_COLOR
        local bgc = s.castbarImportantGlowBackgroundColor or IMP_GLOW_BG_COLOR
        local spec = impSpec
        spec.style = s.castbarImportantGlowStyle or 1
        spec.r, spec.g, spec.b = Glows.ResolveColor(s.castbarImportantGlowColorMode or "custom", c.r, c.g, c.b)
        spec.lines = s.castbarImportantGlowLines or 8
        spec.thickness = s.castbarImportantGlowThickness or 2
        spec.speed = s.castbarImportantGlowSpeed or 4
        spec.bg = (s.castbarImportantGlowBackground == true) or nil
        spec.bgR, spec.bgG, spec.bgB = bgc.r, bgc.g, bgc.b
        local pW, pH = castbar:GetWidth(), castbar:GetHeight()
        -- Secret while the bar rides the stock-style aura block: use the last plain read
        -- (the bar never resizes in combat), else the configured holder size.
        if issecretvalue(pW) or issecretvalue(pH) then
            pW, pH = castbar._impPlainW, castbar._impPlainH
            if not pW then
                local cbw = s.castbarWidth or 0
                pW = cbw > 0 and cbw or 181
                pH = s.castbarHeight or 14
            end
        else
            castbar._impPlainW, castbar._impPlainH = pW, pH
        end
        if pW < 5 then pW = 100 end
        if pH < 5 then pH = 14 end
        -- Restarts only when the look or the bar size changed, so back-to-back
        -- casts keep the animation running.
        Glows.StartSpecGlow(ov, spec, pW, pH, "bar")
        castbar._impGlowActive = true

        ov:Show()
        ov:SetAlphaFromBoolean(isImportant)
    end
end

local function SetupShowOnCastBar(frame, unit)
    local castbar = frame.Castbar
    local castbarBg = castbar:GetParent()
    local iconFrame = castbar._iconFrame
    local impGlowUnit = IsKickCastbarUnit(unit)

    -- Read the hide-when-inactive flag dynamically so closures always reflect the
    -- current setting rather than a value captured at frame-creation time.
    local function shouldHideWhenInactive()
        local s = GetSettingsForUnit(unit)
        if not s then return true end
        local v = s.castbarHideWhenInactive
        if v == nil then return true end
        return v
    end

    castbar:Hide()
    if iconFrame then iconFrame:Hide() end
    if castbarBg then
        if shouldHideWhenInactive() then
            castbarBg:Hide()
        else
            castbarBg:Show()
        end
    end

    local savedCastHook = castbar.PostCastStart
    local savedInterruptHook = castbar.PostCastInterruptible

    castbar.PostCastStart = function(self, ...)
        local bg = self:GetParent()
        if bg then
            -- Boss: re-assert the configured width (castbarWidth>0=custom, 0=match
            -- frame width) at cast start, so a live cast always shows the right width
            -- even if no settings pass ran since the frame was resized.
            if unit and unit:match("^boss") then
                local s = db and db.profile and GetSettingsForUnit(unit)
                local cw = (s and s.castbarWidth) or 0
                if cw > 0 and cw < 30 then cw = 30 end
                if s then PP.Width(bg, cw > 0 and cw or frame:GetWidth()) end
            end
            bg:Show()
        end
        self:Show()
        if self._iconFrame then
            local s = db and db.profile and GetSettingsForUnit(unit)
            local showIcon
            if unit == "player" then
                showIcon = (s and s.showPlayerCastIcon ~= false)
            else
                showIcon = (not s or s.showCastIcon ~= false)
            end
            if showIcon then
                self._iconFrame:Show()
            else
                self._iconFrame:Hide()
            end
        end
        -- Spell target text (who the unit is casting on)
        if self.Target then
            local spellTarget, spellTargetClass
            local ownerUnit = self.__owner and self.__owner._euiUnit
            -- Channels are excluded: UnitSpellTargetName tracks the last CAST
            -- and keeps returning the previous hard-cast's target for the
            -- whole channel (field-verified stale), and no channel-target API
            -- exists -- so channels show no target name rather than a wrong
            -- one. Empowered casts read correctly and keep theirs.
            if ownerUnit and not self.channeling
               and UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(ownerUnit) then
                local rawTarget = UnitSpellTargetName and UnitSpellTargetName(ownerUnit)
                if rawTarget then
                    spellTarget = rawTarget
                    spellTargetClass = UnitSpellTargetClass and UnitSpellTargetClass(ownerUnit)
                end
            end
            local hasTarget = spellTarget and true or false
            local sOwn = ownerUnit and db and db.profile and GetSettingsForUnit(ownerUnit)
            -- Combine Spell Name and Target (target/focus): one string in the TARGET
            -- slot ("Spell Name - Target", target class colored); the separate Spell
            -- Name element is suppressed via _combineNT in LayoutCastTextZones. Color
            -- code lives in the clean FORMAT string; (possibly secret) names ride
            -- through SetFormattedText -- never Lua-concatenated.
            local combine = sOwn and sOwn.castCombineNameTarget == true
                and (ownerUnit == "target" or ownerUnit == "focus")
            self._combineNT = combine or nil
            if combine then
                -- The separate target element is fully suppressed; the target
                -- rides appended to the spell NAME element instead.
                self.Target:SetText("")
                self.Target:Hide()
                if self.Text and hasTarget then
                    local spellName = UnitCastingInfo(ownerUnit)
                    if not spellName then spellName = UnitChannelInfo(ownerUnit) end
                    local hex
                    if spellTargetClass and C_ClassColor then
                        local c = C_ClassColor.GetClassColor(spellTargetClass)
                        if c and c.GenerateHexColor then hex = c:GenerateHexColor() end
                    end
                    if spellName then
                        if hex then
                            self.Text:SetFormattedText("%s - |c" .. hex .. "%s|r", spellName, spellTarget)
                        else
                            self.Text:SetFormattedText("%s - %s", spellName, spellTarget)
                        end
                    end
                end
                -- No cast target: oUF's plain spell name in the Text element
                -- stands untouched.
            else
                self.Target:SetText(spellTarget or "")
                self.Target:SetShown(hasTarget and self._showTarget ~= false)
                -- Class color the target name
                if hasTarget and spellTargetClass and C_ClassColor then
                    local c = C_ClassColor.GetClassColor(spellTargetClass)
                    if c then
                        self.Target:SetTextColor(c:GetRGB())
                    else
                        local tc = (sOwn and sOwn.castSpellTargetColor) or { r=1, g=1, b=1 }
                        self.Target:SetTextColor(tc.r, tc.g, tc.b)
                    end
                elseif hasTarget then
                    local tc = (sOwn and sOwn.castSpellTargetColor) or { r=1, g=1, b=1 }
                    self.Target:SetTextColor(tc.r, tc.g, tc.b)
                end
            end
            if self._layoutTextZones then self:_layoutTextZones() end
        end
        if savedCastHook then savedCastHook(self, ...) end
        UpdateUnitFrameKickTick(self)
        if impGlowUnit then ns.UpdateUnitFrameImportantGlow(self) end
        NotifyCastbarStarted(self)
    end
    castbar.PostChannelStart = castbar.PostCastStart
    castbar.PostCastInterruptible = function(self, ...)
        if savedInterruptHook then savedInterruptHook(self) end
    end

    local function dismissCastBar(self)
        HideUnitFrameKickTick(self)
        NotifyCastbarEnded(self)
        self:Hide()
        if self._iconFrame then self._iconFrame:Hide() end
        -- Read setting dynamically so changes take effect without a reload.
        if shouldHideWhenInactive() then
            local bg = self:GetParent()
            if bg then bg:Hide() end
        end
    end
    castbar.PostCastStop = dismissCastBar
    castbar.PostChannelStop = dismissCastBar
    castbar.PostCastFail = dismissCastBar

    -- Guard against nil stages from UnitEmpoweredStagePercentages during
    -- empower casts where stage data isn't available yet.
    castbar.UpdatePips = function(element, stages)
        if not stages then return end
        local isHoriz = element:GetOrientation() == "HORIZONTAL"
        local elementSize = isHoriz and element:GetWidth() or element:GetHeight()
        local lastOffset = 0
        for stage, stageSection in next, stages do
            local offset = lastOffset + (elementSize * stageSection)
            lastOffset = offset
            local pip = element.Pips[stage]
            if not pip then
                pip = (element.CreatePip or function(e)
                    return CreateFrame("Frame", nil, e, "CastingBarFrameStagePipTemplate")
                end)(element, stage)
                element.Pips[stage] = pip
            end
            pip:ClearAllPoints()
            if isHoriz then
                pip:SetPoint("CENTER", element, "LEFT", offset, 0)
            else
                pip:SetPoint("CENTER", element, "BOTTOM", 0, offset)
            end
            pip:Show()
        end
        for i = #stages + 1, #element.Pips do
            element.Pips[i]:Hide()
        end
    end

    -- Catch-all: hide the icon AND background whenever the castbar hides for any
    -- reason (oUF holdTime expiry, target/focus switch, etc.) so neither gets stuck.
    -- Key case: target/focus switching mid-cast -- oUF's CastStart hides the castbar
    -- but never fires PostCastStop, so dismissCastBar never runs and the background
    -- frame would otherwise remain visible as a black rectangle.
    castbar:HookScript("OnHide", function(self)
        HideUnitFrameKickTick(self)
        if impGlowUnit then ns.ClearUnitFrameImportantGlow(self) end
        NotifyCastbarEnded(self)
        if self._iconFrame then self._iconFrame:Hide() end
        if shouldHideWhenInactive() then
            local bg = self:GetParent()
            if bg then bg:Hide() end
        end
    end)
end


-- Toggle a frame's oUF Castbar element without rewriting Blizzard's cast bar event
-- registration. oUF silences PlayerCastingBarFrame/PetCastingBarFrame when the element
-- enables on the player frame and re-arms them when it disables; the shared helpers
-- keep whatever a standalone cast bar addon set. On ns for the 200-locals cap.
function ns.SetCastbarElement(frame, enable)
    if not frame or not frame.Castbar then return end
    if (frame:IsElementEnabled("Castbar") and true or false) == (enable and true or false) then return end
    EllesmereUI.CaptureBlizzCastBarEvents()
    if enable then
        frame:EnableElement("Castbar")
    else
        frame:DisableElement("Castbar")
    end
    EllesmereUI.RestoreBlizzCastBarEvents()
end

-- Manage Blizzard's player cast bar ownership based on whether UnitFrames renders its
-- own player cast bar. oUF already handles event plumbing for its own castbar element;
-- this helper only coordinates suppression with other EUI modules and releases control
-- cleanly for external addons.
local function ApplyBlizzCastbarState()
    if EllesmereUI and EllesmereUI.SetPlayerCastBarSuppressed and db and db.profile and db.profile.player then
        -- Only suppress Blizzard's player cast bar when EUI actually provides a
        -- replacement. If the player is on the Blizzard (or hidden) frame source,
        -- there is no EUI cast bar, so leave Blizzard's alone. Visibility "never"
        -- counts as no replacement too: our cast bar is built now but hides with the
        -- frame, and taking Blizzard's away would leave no player cast bar at all.
        local suppress = (db.profile.player.showPlayerCastbar
            and ns.VisEffective(db.profile.player) ~= "never"
            and ns.GetUnitFrameSource("player") == "eui") or false
        EllesmereUI.SetPlayerCastBarSuppressed("UnitFrames", suppress)
    end
end

-- Hide While Using Gamepad (Global Settings > Gamepad): Blizzard's gamepad UI
-- draws its own player cast bar, so ours stands down while a controller is
-- connected. It rides the same element switch "Show Player Cast Bar" off uses,
-- keyed on a runtime flag the reload and visibility passes also read
-- (ns._ufCastPadHidden); the saved toggle is never written and Blizzard's bar
-- stays suppressed. The pad edges are watched only while the option is on and
-- our player cast bar is on screen. padOn is the watcher's verdict; the login,
-- reload and options callers pass nothing and it is read live.
function ns.UF_ApplyGamepadCastbar(padOn)
    local s = db and db.profile and db.profile.player
    local frame = frames.player
    local cb = frame and frame.Castbar
    local want = (cb and s and s.showPlayerCastbar and s.castbarGamepadHide == true
        and ns.VisEffective(s) ~= "never"
        and ns.GetUnitFrameSource("player") == "eui") and true or false
    if want ~= (ns._ufCastPadWatched == true) then
        ns._ufCastPadWatched = want
        if want then
            EllesmereUI.WatchPad("UF_PlayerCastbar", ns.UF_ApplyGamepadCastbar)
        else
            EllesmereUI.UnwatchPad("UF_PlayerCastbar")
        end
    end
    local hide = false
    if want then
        if padOn == nil then padOn = EllesmereUI.PadConnected() end
        hide = padOn and true or false
    end
    if hide == (ns._ufCastPadHidden == true) then return end
    ns._ufCastPadHidden = hide
    if not cb then return end
    local castbarBg = cb:GetParent()
    if hide then
        ns.SetCastbarElement(frame, false)
        cb:Hide()
        if castbarBg then castbarBg:Hide() end
        return
    end
    -- Back on, mid-cast included: the enable re-derives the live cast; an idle
    -- holder follows the reload pass's hide-while-not-casting rule. A setting
    -- that turned the bar off is left to the reload pass that hides it.
    if not (s and s.showPlayerCastbar) then return end
    -- Enabled whether or not the frame is shown, as the reload pass does: a
    -- frame hidden by its visibility driver gets no element re-enable when the
    -- driver shows it again, so skipping it here would leave the bar dead. The
    -- holder is a child of the frame, so a hidden frame draws nothing.
    ns.SetCastbarElement(frame, true)
    if castbarBg then
        if s.castbarHideWhenInactive and not cb:IsShown() then
            castbarBg:Hide()
        else
            castbarBg:Show()
        end
    end
end

I.CastIconInWidth, I.CastIconShown, I.CastIconOnRight = CastIconInWidth, CastIconShown, CastIconOnRight
I.CastIconOffsets, I.LayoutCastbarIcon = CastIconOffsets, LayoutCastbarIcon
I.CastbarUnlockKey, I.IsKickCastbarUnit = CastbarUnlockKey, IsKickCastbarUnit
I.ApplyUnitFrameCastColor, I.UpdateUnitFrameKickTick = ApplyUnitFrameCastColor, UpdateUnitFrameKickTick
I.CreateCastBar, I.SetupShowOnCastBar = CreateCastBar, SetupShowOnCastBar
I.ApplyBlizzCastbarState = ApplyBlizzCastbarState
