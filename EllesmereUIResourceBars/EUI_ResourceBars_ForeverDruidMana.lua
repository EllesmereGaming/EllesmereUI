if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EUI_ResourceBars_ForeverDruidMana.lua
-- WoW FOREVER ONLY, DRUID ONLY: Mana Bar while Shapeshifted.
--
-- A thin mana bar attached to the Power Bar while the druid's form runs on
-- another power (Cat = energy, Bear = rage), so the mana pool stays in view.
-- It is a child of the Power Bar frame: it moves, fades, hides and
-- mouseover-reveals with it, and it is not an unlock element, an anchor target
-- or part of size matching. Below / Above sit it outside the bar's frame (a
-- vertical bar: right / left side); Inside lays it over the bar's bottom edge
-- (a vertical bar: its right edge), above the fill and under the bar's text.
-- The look follows the Power Bar (texture, background, border, fill opacity,
-- orientation); the fill is the mana power colour.
--
-- Settings: profile.primary.foreverDruidMana, a table that exists only on
-- Forever (DEFAULTS in the main file). The main file calls ns.FDM_Apply at the
-- end of every BuildBars (settings applies, form changes, login) and
-- ns.FDM_Visibility from UpdateVisibility; on every other client and class
-- this file returns right below and both stay nil.
--
-- Cost: off = no frames, no events. On: UNIT_DISPLAYPOWER (form edges) only;
-- the mana events are registered only while this bar is shown and the Power
-- Bar can show, and a paint with unchanged mana and max does nothing.

local _, ns = ...
local EllesmereUI = _G.EllesmereUI

if not EllesmereUI.IS_FOREVER then return end
local _, playerClass = UnitClass("player")
if playerClass ~= "DRUID" then return end

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local WHITE = "Interface\\Buttons\\WHITE8x8"
local EMPTY = {}
local format, max = string.format, math.max
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax

-- Event host at FILE SCOPE (attribution rule, see _erbEventFrame in the main
-- file): its OnEvent work bills ResourceBars. The bar frames stay lazy.
local evf = CreateFrame("Frame")

-- pb (the Power Bar frame), host (outer frame: border + text), sb (inner
-- StatusBar), bg, border, textFrame, text; enabled (feature on, form event
-- registered), shown (the form wants this bar), pbVis (the Power Bar's
-- visibility pass lets it show), live (shown and pbVis: mana events
-- registered), cur / mx (last painted values), texPath (fill file last set),
-- textOn / fmt / suffix (text settings as last applied).
local S = { enabled = false, shown = false, live = false, pbVis = true }

-- Let the unit frame aura reserve see this bar when it floats below the stack
-- (EllesmereUI.ERB_PlayerStackExtent consumes it; see EUI_UnitFrames_AuraContainers.lua).
-- Returns the host ONLY while it is shown for the current form, so the reserved
-- footprint tracks the form (not transient paint state) and is nil on every other
-- client/class and in the carve/inside modes that add no height below the frame.
ns._FDMStackBottomFrame = function() if S.shown and S.host then return S.host end end

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------

-- Secret values throw on comparison and on truth tests: every API read passes
-- here before it is looked at.
local function Plain(v)
    return not (issecretvalue and issecretvalue(v))
end

-- The form's power is not mana. Asks the Power Bar's own resolver, so Power
-- Type "Mana" (the bar itself stays on mana) reads as mana here too. A
-- restricted answer keeps the last verdict.
local function FormWantsBar()
    local pt = _G._ERB_GetPrimaryPowerType()
    if not Plain(pt) then return S.shown end
    return type(pt) == "number" and pt ~= MANA
end

-- The mana colour from the Power Bar's palette (dark mode, overrides and
-- fallbacks included). Read per apply: the palette memo is wiped on edits.
local function ManaColor()
    local pc = _G._ERB_PowerColors[MANA]
    if pc then return pc[1], pc[2], pc[3] end
    return 1, 1, 1
end

-- BorderReach for a bar wearing the Power Bar's border settings: l, r, t, b
-- (nil for a border drawn inside the bar).
local function ReachOf(pp, es)
    local bs = pp.borderSize or 0
    local tex = pp.borderTexture or "solid"
    return EllesmereUI.BorderReach(bs, tex, pp.borderTextureOffset, pp.borderTextureOffsetY,
        pp.borderTextureShiftX, pp.borderTextureShiftY, "resourcebars", bs,
        EllesmereUI.BorderPx(pp.borderSizePx, bs, tex), nil, pp.borderA, es)
end

-- One side ("l" / "r" / "t" / "b") of a reach, 0 when drawn inside.
local function Side(side, l, r, t, b)
    if not l then return 0 end
    local v
    if side == "l" then v = l elseif side == "r" then v = r elseif side == "t" then v = t else v = b end
    return (v > 0) and v or 0
end

-- How far the Power Bar's frame reaches past the side this bar faces.
local function PowerBarReach(pp, pos, pbSide, vertical, es)
    local style = ns.ERB_BarsStyle()
    if style == "blizzard" then
        -- The panel's opaque rim (ns.ERB_BlizzMatchPad): 2 above, 1 below,
        -- turned with a vertical bar to 2 left, 1 right. The panel's shadow
        -- draws under this bar.
        if not ns.ERB_BlizzMatchPad(vertical) then return 0 end
        return (pos == "above") and 2 or 1
    elseif style == "classic" then
        -- The vanilla frame's whole reach, so its art never covers this bar;
        -- turned with a vertical bar like the art (top rim on the left).
        local CF = EllesmereUI.ClassicFrame
        return ((pos == "above") and CF.OVER_T or CF.OVER_B) * ns.ERB_BarFrameK(pp)
    end
    -- Extend Top / Extend Bottom move a horizontal bar's border host.
    local ext = 0
    if not vertical then
        local top, bottom = ns.ERB_BorderExtents(pp)
        ext = (pos == "above") and top or bottom
    end
    return Side(pbSide, ReachOf(pp, es)) + ext
end

-- Inside: the Power Bar's hash-line inset (an exact solid border size, else
-- the step). The stock styles draw their frame outside the fill: none.
local function InsideInset(pp)
    if ns.ERB_BarsBlizz() then return 0 end
    local bs = pp.borderSize or 0
    local tex = pp.borderTexture
    if not tex or tex == "" or tex == "solid" then
        bs = EllesmereUI.BorderPx(pp.borderSizePx, bs, tex) or bs
    end
    return bs * EllesmereUI.PP.mult
end

-------------------------------------------------------------------------------
--  Paint
-------------------------------------------------------------------------------

-- Fill and text from live mana, in the Power Bar's text formats. force = the
-- look or the visibility just changed: repaint and snap (no ease). A
-- restricted read skips the clamp and the stamps and always rewrites.
local function Paint(force)
    local sb = S.sb
    local cur = UnitPower("player", MANA)
    local mx = UnitPowerMax("player", MANA)
    local curPlain, mxPlain = Plain(cur), Plain(mx)
    if mxPlain and (type(mx) ~= "number" or mx <= 0) then return end
    if curPlain then
        if type(cur) ~= "number" then return end
        if cur < 0 then cur = 0 end
    end
    if curPlain and mxPlain then
        if not force and cur == S.cur and mx == S.mx then return end
        if force or mx ~= S.mx then sb:SetMinMaxValues(0, mx) end
        S.cur, S.mx = cur, mx
    else
        S.cur, S.mx = nil, nil
        sb:SetMinMaxValues(0, mx)
    end
    if curPlain and not force then
        sb:SetValue(cur, ns.EASE)
    else
        sb:SetValue(cur)
    end

    if not S.textOn then return end
    local fmt = S.fmt
    local wantPct = fmt == "perpp" or fmt == "both"
        or (fmt == "smart" and EllesmereUI.IsSmartPowerPercent and EllesmereUI.IsSmartPowerPercent(MANA))
    local txt
    if wantPct then
        -- Built only for a format that shows it.
        local pctRaw = UnitPowerPercent and UnitPowerPercent("player", MANA, true, CurveConstants and CurveConstants.ScaleTo100) or 0
        local percentText = format("%d", pctRaw) .. S.suffix
        txt = (fmt == "both") and (ns.AbbreviateNumbers(cur) .. " | " .. percentText) or percentText
    else
        txt = ns.AbbreviateNumbers(cur)
    end
    S.text:SetText(txt)
end

-- Mana events only while this bar is shown and the Power Bar can show; the
-- edge into live repaints at once (mana moved while unregistered).
local function UpdateLive()
    local live = (S.shown and S.pbVis) and true or false
    if live == S.live then return end
    S.live = live
    if live then
        evf:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        evf:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        Paint(true)
    else
        evf:UnregisterEvent("UNIT_POWER_FREQUENT")
        evf:UnregisterEvent("UNIT_MAXPOWER")
    end
end

-- Form edge: show or hide for the form's power, then the event set.
local function Refresh()
    local shown = S.enabled and FormWantsBar() or false
    if shown ~= S.shown then
        S.shown = shown
        S.host:SetShown(shown)
    end
    UpdateLive()
end

evf:SetScript("OnEvent", function(_, event, _, powerType)
    if event == "UNIT_DISPLAYPOWER" then
        Refresh()
    elseif S.live then
        -- Energy and rage ticks share these events: mana only.
        if Plain(powerType) and powerType and powerType ~= "MANA" then return end
        Paint(false)
    end
end)

-------------------------------------------------------------------------------
--  Build / look
-------------------------------------------------------------------------------

-- The Power Bar's frame shape: outer frame (border + text, never clipped),
-- inner StatusBar inset a quarter pixel so the fill never bleeds past the
-- border, bg inside it. host._sb / host._bg are what ns.ApplyFillOpacity reads.
local function EnsureBuilt(pb)
    local host = S.host
    if host then
        if host:GetParent() ~= pb then host:SetParent(pb) end
        return
    end
    host = CreateFrame("Frame", nil, pb)
    host:Hide()
    local sb = CreateFrame("StatusBar", nil, host)
    local q = EllesmereUI.PP.mult * 0.25
    sb:SetPoint("TOPLEFT", host, "TOPLEFT", q, -q)
    sb:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -q, q)
    sb:SetStatusBarTexture(WHITE)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    local bg = sb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local border = CreateFrame("Frame", nil, host)
    border:SetAllPoints(host)
    local textFrame = CreateFrame("Frame", nil, host)
    textFrame:SetAllPoints(host)
    -- Font before any SetText ("Font not set" on the Forever client).
    local text = textFrame:CreateFontString(nil, "OVERLAY")
    ns.SetRBFont(text, ns.GetRBFont(), 8)
    text:SetWordWrap(false)
    host._sb, host._bg = sb, bg
    S.host, S.sb, S.bg, S.border, S.textFrame, S.text = host, sb, bg, border, textFrame, text
end

-- Levels, then position and size (sized before the border is styled: a
-- textured border set up on a 0x0 frame never paints). One level above the
-- Power Bar's fill: Inside draws over the fill, under the Power Bar's text
-- (25), the classic frame and a lifted border; Below / Above clear every
-- frame the Power Bar draws (reach below). Returns orientation, inside.
local function Layout(pb, pp, g, c)
    local PP = EllesmereUI.PP
    local host, bdr = S.host, S.border
    local base = pb._sb:GetFrameLevel() + 1
    host:SetFrameLevel(base)
    S.sb:SetFrameLevel(base + 1)
    bdr:SetFrameLevel(pp.borderBehind and max(0, base - 1) or (base + 1))
    S.textFrame:SetFrameLevel(24)

    local es = pb:GetEffectiveScale()
    local ori = pp.orientation or g.orientation or "HORIZONTAL"
    local vertical = ns.IsVerticalOrientation(ori)
    local pos = c.position
    if pos ~= "above" and pos ~= "inside" then pos = "below" end
    local thick = PP.SnapForES(max(c.height or 6, 1), es)
    local ox = PP.SnapForES(c.offsetX or 0, es)
    local oy = PP.SnapForES(c.offsetY or 0, es)

    host:ClearAllPoints()
    if pos == "inside" then
        local i = PP.SnapForES(InsideInset(pp), es)
        -- Never thicker than the Power Bar's fill.
        local room = (vertical and pb:GetWidth() or pb:GetHeight()) - 2 * i
        if room > 0 and thick > room then thick = room end
        if vertical then
            host:SetPoint("TOPRIGHT", pb, "TOPRIGHT", ox - i, oy - i)
            host:SetPoint("BOTTOMRIGHT", pb, "BOTTOMRIGHT", ox - i, oy + i)
            host:SetWidth(thick)
        else
            host:SetPoint("BOTTOMLEFT", pb, "BOTTOMLEFT", ox + i, oy + i)
            host:SetPoint("BOTTOMRIGHT", pb, "BOTTOMRIGHT", ox - i, oy + i)
            host:SetHeight(thick)
        end
        return ori, true
    end

    -- Gap = the space between the two bars' visible edges: the Power Bar's
    -- reach on the facing side and this bar's own border reach toward it are
    -- added to it. A vertical bar: Below = right side, Above = left side.
    local above = pos == "above"
    local pbSide, ownSide
    if vertical then
        pbSide, ownSide = above and "l" or "r", above and "r" or "l"
    else
        pbSide, ownSide = above and "t" or "b", above and "b" or "t"
    end
    local d = PP.SnapForES(max(c.gap or 2, 0) + PowerBarReach(pp, pos, pbSide, vertical, es)
        + Side(ownSide, ReachOf(pp, es)), es)
    if vertical then
        if above then
            host:SetPoint("TOPRIGHT", pb, "TOPLEFT", ox - d, oy)
            host:SetPoint("BOTTOMRIGHT", pb, "BOTTOMLEFT", ox - d, oy)
        else
            host:SetPoint("TOPLEFT", pb, "TOPRIGHT", ox + d, oy)
            host:SetPoint("BOTTOMLEFT", pb, "BOTTOMRIGHT", ox + d, oy)
        end
        host:SetWidth(thick)
    else
        if above then
            host:SetPoint("BOTTOMLEFT", pb, "TOPLEFT", ox, oy + d)
            host:SetPoint("BOTTOMRIGHT", pb, "TOPRIGHT", ox, oy + d)
        else
            host:SetPoint("TOPLEFT", pb, "BOTTOMLEFT", ox, oy - d)
            host:SetPoint("TOPRIGHT", pb, "BOTTOMRIGHT", ox, oy - d)
        end
        host:SetHeight(thick)
    end
    return ori, false
end

-- The Power Bar's border settings in every style (a stock style's frame art
-- has no plain form, so this bar keeps the EllesmereUI border). Inside sits
-- within the Power Bar's own border and wears none.
local function ApplyBorder(pp, inside)
    local bdr = S.border
    -- Lost-rect recovery, see the cast bar border in the main file.
    if not bdr:GetLeft() then bdr:SetAllPoints(S.host) end
    if inside then
        EllesmereUI.ApplyBorderStyle(bdr, 0, 0, 0, 0, 0, "solid")
        return
    end
    local bs = pp.borderSize or 0
    local tex = pp.borderTexture or "solid"
    EllesmereUI.ApplyBorderStyle(bdr, bs,
        pp.borderR or 0, pp.borderG or 0, pp.borderB or 0, pp.borderA or 1,
        tex, pp.borderTextureOffset, pp.borderTextureOffsetY,
        pp.borderTextureShiftX, pp.borderTextureShiftY, "resourcebars", bs,
        nil, EllesmereUI.BorderPx(pp.borderSizePx, bs, tex))
    -- The strip container was levelled off the border frame when it was made.
    local edges = EllesmereUI.PP.GetBorders(bdr)
    if edges then edges:SetFrameLevel(bdr:GetFrameLevel() + 1) end
end

-- Orientation, the Power Bar's fill texture (the plain user texture under
-- every style), the mana fill, the Power Bar's background and fill opacity.
-- Returns the mana colour for the text.
local function ApplyLook(pp, g, p, ori)
    local sb = S.sb
    if ori == "VERTICAL_UP" or ori == "VERTICAL_DOWN" then
        sb:SetOrientation("VERTICAL")
        sb:SetRotatesTexture(true)
        sb:SetReverseFill(ori == "VERTICAL_DOWN")
    else
        sb:SetOrientation("HORIZONTAL")
        sb:SetRotatesTexture(false)
        sb:SetReverseFill(false)
    end
    local path = EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures,
        (p.splitTex == true and pp.barTexture) or g.barTexture or "none", WHITE)
    if path ~= S.texPath then
        S.texPath = path
        sb:SetStatusBarTexture(path)
        -- A new file resets the vertex colour: drop the fill memo so the
        -- paint below lands.
        local ft = sb:GetStatusBarTexture()
        if ft then ft._lfOn, ft._lgOn = nil, nil end
    end
    local r, gr, b = ManaColor()
    ns.ApplyBarFlat(sb:GetStatusBarTexture(), r, gr, b, 1)
    S.bg:SetColorTexture(pp.bgR or 0, pp.bgG or 0, pp.bgB or 0, pp.bgA or 0.75)
    ns.ApplyFillOpacity(S.host, ori, pp.fillOpacity)
    return r, gr, b
end

-- Text style, same keys and colour rule as the Power Bar's text (custom, or
-- the power colour: here mana's).
local function ApplyText(c, r, g, b)
    local fs = S.text
    ns.SetRBFont(fs, ns.GetRBFont(), c.textSize or 8)
    fs:ClearAllPoints()
    local a = c.textAnchor or "CENTER"
    fs:SetPoint(a, S.host, a, c.textXOffset or 0, c.textYOffset or 0)
    if c.textCustomColored == false then
        fs:SetTextColor(r, g, b, 1)
    else
        fs:SetTextColor(c.textFillR or 1, c.textFillG or 1, c.textFillB or 1, c.textFillA or 1)
    end
    local fmt = c.textFormat or "none"
    S.fmt = fmt
    S.suffix = (c.showPercent == false) and "" or "%"
    S.textOn = fmt ~= "none"
    fs:SetShown(S.textOn)
end

-- Off: every event dropped, the bar hidden (nothing anchors to it).
local function Teardown()
    if not S.enabled then return end
    S.enabled, S.shown, S.live = false, false, false
    S.cur, S.mx = nil, nil
    evf:UnregisterAllEvents()
    S.host:Hide()
end

-------------------------------------------------------------------------------
--  Entry points (main file)
-------------------------------------------------------------------------------

-- End of every BuildBars: full restyle from settings, then show / hide for
-- the form. pb / pp / g = the Power Bar frame, its resolved settings and the
-- general settings; each falls back to a lookup when omitted.
function ns.FDM_Apply(pb, pp, g)
    local ERB = ns.ERB
    local p = ERB.db and ERB.db.profile
    if not p then return end
    pb = pb or S.pb or _G.ERB_PrimaryBar
    pp = pp or _G._ERB_ResolvePowerCfg(p)
    local c = pp and pp.foreverDruidMana
    -- Power Type "Mana" keeps the Power Bar itself on mana: nothing to add.
    local ov = p.primary and p.primary.powerTypeOverride
    if not (pb and c and c.enabled and pp.enabled ~= false) or (ov and ov.foreverDruid) then
        Teardown()
        return
    end
    S.pb = pb
    EnsureBuilt(pb)
    if not S.enabled then
        S.enabled = true
        evf:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    end
    g = g or p.general or EMPTY
    local ori, inside = Layout(pb, pp, g, c)
    ApplyBorder(pp, inside)
    local r, gr, b = ApplyLook(pp, g, p, ori)
    ApplyText(c, r, gr, b)
    local wasLive = S.live
    Refresh()
    -- Already live: the new look and text settings paint now (an edge into
    -- live painted in UpdateLive).
    if wasLive and S.live then Paint(true) end
end

-- The Power Bar's visibility pass (vis = true / "mouseover" / false / nil).
-- Tracked while off too, so an enable knows the current state. Alpha and
-- fades need nothing here: this bar is the Power Bar's child.
function ns.FDM_Visibility(vis)
    local on = (vis == true or vis == "mouseover")
    if on == S.pbVis then return end
    S.pbVis = on
    if S.enabled then UpdateLive() end
end
