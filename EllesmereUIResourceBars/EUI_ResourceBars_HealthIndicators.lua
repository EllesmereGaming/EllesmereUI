if EUI_CLIENT_BLOCKED then return end
-------------------------------------------------------------------------------
--  EUI_ResourceBars_HealthIndicators.lua
--  Opt-in damage absorbs, heal absorbs and max health reduction. Settings
--  build and lay out overlays; events paint values without secret arithmetic.
-------------------------------------------------------------------------------
local _, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local STYLE_TEX = EllesmereUI.ABSORB_STYLE_TEX
local TILED = EllesmereUI.ABSORB_TILED_STYLES
local Glow = EllesmereUI.AbsorbGlow

-- The overlays in paint order (heal absorbs over damage absorbs): settings
-- keys and defaults, read by the options rows too. An absorb is off at style
-- None and takes its alpha from its opacity setting; the reduction has its own
-- toggle and an alpha colour.
ns.HEALTH_INDICATORS = {
    { key = "absorb", style = "absorbStyle", color = "absorbColor",
      opacity = "absorbOpacity", opacityDef = 65, r = 0.3, g = 0.75, b = 1 },
    { key = "healAbsorb", style = "healAbsorbStyle", color = "healAbsorbColor",
      opacity = "healAbsorbOpacity", opacityDef = 75, r = 0.85, g = 0.15, b = 0.2 },
    { key = "maxHealthLoss", show = "showMaxHealthLoss", style = "maxHealthLossStyle", color = "maxHealthLossColor",
      r = 0.35, g = 0.25, b = 0.4, a = 0.9 },
}
local KINDS = ns.HEALTH_INDICATORS

-- The overlay's style while it is on, nil while it is off.
local function StyleOf(cfg, k)
    local style = cfg[k.style]
    if k.show then
        return cfg[k.show] == true and (style or "striped") or nil
    end
    return (style and style ~= "none") and style or nil
end

-- Style key -> texture: the shared absorb styles, else the Resource Bars bar
-- textures ("sm:" SharedMedia keys land there). The live overlays and the
-- options dropdown preview both resolve through this.
function ns.HealthIndicatorTex(style)
    return STYLE_TEX[style] or EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, style, WHITE)
end

local host, sb        -- the health bar and its clipped inner StatusBar (first use)
local bars = {}       -- indicator key -> overlay StatusBar, built on first use
local on = {}         -- indicator key -> true while switched on
local styled = {}     -- indicator key -> style its texture was last set from
local active = false  -- any overlay on
local ori = "HORIZONTAL"
local loss = 0        -- max health reduction fraction; 0 while its overlay is off
local absorbMode, overshieldMode = "overlayReverse", "always"
local healMode = "overlay"
local curClip, missClip

-- Start/end corners along the health fill's axis.
local AXIS = {
    HORIZONTAL = { "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT" },
    VERTICAL_UP = { "BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT", "TOPRIGHT" },
    VERTICAL_DOWN = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
}

local function AnchorEdgeBar(bar, mode, down, axis)
    local atEnd = (mode == "right") ~= down
    local p1, p2 = axis[atEnd and 3 or 1], axis[atEnd and 4 or 2]
    bar:SetPoint(p1, sb, p1)
    bar:SetPoint(p2, sb, p2)
    bar:SetReverseFill(mode == "right")
end

local function BuildSegments()
    if curClip then return end
    curClip = CreateFrame("Frame", nil, sb)
    curClip:SetClipsChildren(true)
    missClip = CreateFrame("Frame", nil, sb)
    missClip:SetClipsChildren(true)
    local ab = bars.absorb
    ab:SetParent(curClip)
    ab._forward = CreateFrame("StatusBar", nil, missClip)
    ab._forward:SetMinMaxValues(0, 1)
    ab._forward:SetValue(0)
    styled.absorb = nil
end

-- Created in the main chunk so its handler work bills Resource Bars. Events
-- are registered only while an overlay that reads them is on.
local eventFrame = CreateFrame("Frame")
local registered = {}
local function WantEvent(event, want)
    want = want and true or false
    if registered[event] == want then return end
    registered[event] = want
    if want then
        eventFrame:RegisterUnitEvent(event, "player")
    else
        eventFrame:UnregisterEvent(event)
    end
end

-- Only the reduction fraction (never a health amount) enters Lua arithmetic;
-- a secret or missing reading counts as no reduction.
local function ReadLoss()
    if not (on.maxHealthLoss and GetUnitTotalModifiedMaxHealthPercent) then return 0 end
    local v = GetUnitTotalModifiedMaxHealthPercent("player")
    if issecretvalue(v) or type(v) ~= "number" then return 0 end
    return math.max(0, math.min(1, v))
end

-- The reduction takes the end of the bar the fill grows toward (the right, the
-- top for Vertical Up, the bottom for Vertical Down): the inner bar gives it up
-- and the reduction overlay paints it. Fill-edge anchors follow secret health
-- in the engine; clip frames split absorbs without reading that edge in Lua.
local function Layout()
    local inset = EllesmereUI.PP.mult * 0.25
    local w = math.max(0, host:GetWidth() - 2 * inset)
    local h = math.max(0, host:GetHeight() - 2 * inset)
    -- Vertical exactly where the health bar is (ApplyBarOrientation).
    local down = ori == "VERTICAL_DOWN"
    local vertical = down or ori == "VERTICAL_UP"
    local cut = (vertical and h or w) * loss
    sb:ClearAllPoints()
    sb:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -inset - ((vertical and not down) and cut or 0))
    sb:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -inset - (vertical and 0 or cut), inset + (down and cut or 0))

    local span = (vertical and h or w) - cut
    local fill = sb:GetStatusBarTexture()
    local p1, p2
    if not vertical then
        p1, p2 = "TOPRIGHT", "BOTTOMRIGHT"
    elseif down then
        p1, p2 = "BOTTOMLEFT", "BOTTOMRIGHT"
    else
        p1, p2 = "TOPLEFT", "TOPRIGHT"
    end
    for key, bar in pairs(bars) do
        bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
        bar:SetReverseFill(not down)
        bar:ClearAllPoints()
        if key == "maxHealthLoss" then
            bar:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -inset)
            bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -inset, inset)
        else
            if key == "healAbsorb" and (healMode == "right" or healMode == "left") then
                AnchorEdgeBar(bar, healMode, down, AXIS[ori] or AXIS.HORIZONTAL)
            else
                bar:SetPoint(p1, fill, p1)
                bar:SetPoint(p2, fill, p2)
            end
            if vertical then bar:SetHeight(span) else bar:SetWidth(span) end
        end
    end
    local ab = bars.absorb
    if ab and curClip then
        local axis = AXIS[ori] or AXIS.HORIZONTAL
        local start1, start2, end1, end2 = axis[1], axis[2], axis[3], axis[4]
        local fw = ab._forward
        curClip:ClearAllPoints()
        missClip:ClearAllPoints()
        missClip:SetPoint(start1, fill, end1)
        missClip:SetPoint(end2, sb, end2)
        fw:ClearAllPoints()
        local full = absorbMode == "overlayReverseFull"
        fw:SetPoint(start1, full and sb or fill, full and start1 or end1)
        fw:SetPoint(start2, full and sb or fill, full and start2 or end2)
        fw:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
        fw:SetReverseFill(down)
        if vertical then fw:SetHeight(span) else fw:SetWidth(span) end
        ab:ClearAllPoints()
        local edge = absorbMode == "right" or absorbMode == "left"
        if edge then
            curClip:SetAllPoints(sb)
            AnchorEdgeBar(ab, absorbMode, down, axis)
        else
            curClip:SetPoint(start1, sb, start1)
            curClip:SetPoint(end2, fill, end2)
            local target = absorbMode == "overlay" and overshieldMode ~= "fromleft" and sb or fill
            ab:SetPoint(end1, target, end1)
            ab:SetPoint(end2, target, end2)
            if absorbMode == "overlay" and overshieldMode == "fromleft" then
                ab:SetReverseFill(down)
            else
                ab:SetReverseFill(not down)
            end
        end
        missClip:SetShown(on.absorb and (absorbMode == "overlay" or full))
        curClip:SetShown(on.absorb)
    end
    if ab and ab._glowOn then Glow.Anchor(ab) end
end

-- Hooked once on the health bar at first use (file scope: the hook bills
-- Resource Bars); inert while every overlay is off.
local function OnHostSized()
    if active then
        Layout()
        local ab = bars.absorb
        if ab and ab._glowOn then Glow.Paint(ab, "player", UnitGetTotalAbsorbs("player"), sb:GetHeight()) end
    end
end

local function PaintMax()
    local mx = UnitHealthMax("player")
    if on.absorb then
        bars.absorb:SetMinMaxValues(0, mx)
        if bars.absorb._forward then bars.absorb._forward:SetMinMaxValues(0, mx) end
    end
    if on.healAbsorb then bars.healAbsorb:SetMinMaxValues(0, mx) end
end

local function ApplyGlow(cfg)
    local ab = bars.absorb
    if not ab then return end
    local enabled = on.absorb and cfg.absorbGlowLine == true and ori == "HORIZONTAL" and absorbMode ~= "left"
    ab._glowOn = enabled and true or false
    if not enabled then
        if ab._glow then ab._glow.host:Hide() end
        return
    end
    ab._hpBar = sb
    local g = ab._glow or Glow.Build(ab)
    g.ge = absorbMode == "overlay" and (overshieldMode == "fromleft" and 2 or 1)
        or (absorbMode == "right" and 5 or 3)
    g.anc = absorbMode == "overlay" and overshieldMode ~= "never" and g.ge or 0
    g.rev = false
    g.art = Glow.art[cfg.absorbGlowLineTexture] or Glow.art.blizzard
    g.edge:SetTexture(g.art[1]); g.edge:SetBlendMode(g.art[2])
    g.bf:SetTexture(g.art[1]); g.bf:SetBlendMode(g.art[2])
    g.szH = nil
    g.host:SetFrameLevel(sb:GetFrameLevel() + 4)
    g.bfHost:SetShown(g.ge <= 2)
    if g.ge == 3 then g.edgeHost:SetAlpha(1) end
    g.host:Show()
end

local function PaintAbsorb()
    local ab = bars.absorb
    local amount = UnitGetTotalAbsorbs("player")
    if absorbMode == "overlay" and overshieldMode == "never" then
        ab:SetValue(0)
    else
        ab:SetValue(amount)
    end
    if ab._forward then ab._forward:SetValue(amount) end
    if ab._glowOn then Glow.Paint(ab, "player", amount, sb:GetHeight()) end
end

local function PaintLoss()
    local v = ReadLoss()
    if v == loss then return end
    loss = v
    Layout()
    local bar = bars.maxHealthLoss
    bar:SetValue(v)
    bar:SetShown(v > 0)
end

-- Amounts go straight to SetValue: they may be secret, so they are never
-- compared, tested or combined here.
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        PaintAbsorb()
    elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
        bars.healAbsorb:SetValue(UnitGetTotalHealAbsorbs("player"))
    elseif event == "UNIT_MAXHEALTH" then
        PaintMax()
        if on.absorb then PaintAbsorb() end
    elseif event == "UNIT_HEALTH" then
        Glow.Flip(bars.absorb, "player")
    elseif event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
        PaintLoss()
    end
end)

local function Overlay(key)
    local bar = bars[key]
    if bar then return bar end
    -- The absorbs are children of the clipped inner bar, so they never draw
    -- past the health area; the reduction sits on the health bar itself.
    bar = CreateFrame("StatusBar", nil, key == "maxHealthLoss" and host or sb)
    bar:SetMinMaxValues(0, 1)
    bar:Hide()
    bars[key] = bar
    return bar
end

local function ApplyHealBacking(bar, cfg)
    local alpha = (cfg.healAbsorbBgOpacity or 0) / 100
    local bg = bar._bg
    if alpha <= 0 then
        if bg then bg:Hide() end
        return
    end
    if not bg then
        bg = bar:CreateTexture(nil, "ARTWORK", nil, 1)
        bar._bg = bg
    end
    local fill = bar:GetStatusBarTexture()
    fill:SetDrawLayer("ARTWORK", 2)
    bg:SetColorTexture(0, 0, 0, alpha)
    bg:SetAllPoints(fill)
    bg:Show()
end

-- Every overlay off: hide them, drop the events and hand the inner bar its
-- stock anchors back (CreateStatusBar's quarter-pixel inset).
local function Deactivate()
    active = false
    loss = 0
    for i = 1, #KINDS do
        local key = KINDS[i].key
        on[key] = nil
        if bars[key] then bars[key]:Hide() end
    end
    if curClip then curClip:Hide(); missClip:Hide() end
    local ab = bars.absorb
    if ab then
        ab._glowOn = false
        if ab._glow then ab._glow.host:Hide() end
    end
    WantEvent("UNIT_ABSORB_AMOUNT_CHANGED", false)
    WantEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", false)
    WantEvent("UNIT_MAXHEALTH", false)
    WantEvent("UNIT_MAX_HEALTH_MODIFIERS_CHANGED", false)
    WantEvent("UNIT_HEALTH", false)
    local inset = EllesmereUI.PP.mult * 0.25
    sb:ClearAllPoints()
    sb:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -inset)
    sb:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -inset, inset)
end

-- Settings pass, from the health bar build: cfg is the health settings (nil
-- while the bar is off or disabled for this spec), orientation the bar's own.
function ns.HealthIndicatorsApply(bar, cfg, orientation)
    local showA = cfg and StyleOf(cfg, KINDS[1]) ~= nil
    local showH = cfg and StyleOf(cfg, KINDS[2]) ~= nil
    local showL = cfg and StyleOf(cfg, KINDS[3]) ~= nil
    if not (showA or showH or showL) then
        if active then Deactivate() end
        return
    end
    if not host then
        host, sb = bar, bar._sb
        host:HookScript("OnSizeChanged", OnHostSized)
    end
    active = true
    ori = orientation or "HORIZONTAL"
    on.absorb, on.healAbsorb, on.maxHealthLoss = showA, showH, showL
    absorbMode = cfg.absorbEdgeMode or "overlayReverse"
    overshieldMode = cfg.overshieldMode or "always"
    healMode = cfg.healAbsorbEdgeMode or "overlay"
    if showA and absorbMode ~= "overlayReverse" then
        Overlay("absorb")
        BuildSegments()
    end

    local level = sb:GetFrameLevel()
    local vertical = ori == "VERTICAL_UP" or ori == "VERTICAL_DOWN"
    for i = 1, #KINDS do
        local k = KINDS[i]
        if on[k.key] then
            local ov = Overlay(k.key)
            ov:SetFrameLevel(level + (k.key == "healAbsorb" and 2 or 1))
            -- A retexture resets the colour, so the colour goes on after it.
            local style = StyleOf(cfg, k)
            local tiled = TILED[style] == true
            local fw = k.key == "absorb" and ov._forward
            if styled[k.key] ~= style then
                styled[k.key] = style
                ov:SetStatusBarTexture(ns.HealthIndicatorTex(style))
                local tex = ov:GetStatusBarTexture()
                tex:SetHorizTile(tiled)
                tex:SetVertTile(tiled)
                if fw then
                    fw:SetStatusBarTexture(ns.HealthIndicatorTex(style))
                    local fwTex = fw:GetStatusBarTexture()
                    fwTex:SetHorizTile(tiled); fwTex:SetVertTile(tiled)
                end
            end
            ov:SetRotatesTexture(vertical and not tiled)
            local c = cfg[k.color]
            local r, g, b, a = k.r, k.g, k.b, k.a
            if c then r, g, b, a = c.r or r, c.g or g, c.b or b, c.a or a end
            if k.opacity then a = (cfg[k.opacity] or k.opacityDef) / 100 end
            -- The outlined stripes carry their own colours: only the alpha tints them.
            if style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" then r, g, b = 1, 1, 1 end
            ov:SetStatusBarColor(r, g, b, a)
            if fw then
                fw:SetFrameLevel(level + 1)
                fw:SetRotatesTexture(vertical and not tiled)
                fw:SetStatusBarColor(r, g, b, a)
            end
            if k.key == "healAbsorb" then ApplyHealBacking(ov, cfg) end
        elseif bars[k.key] then
            bars[k.key]:Hide()
        end
    end

    ApplyGlow(cfg)
    loss = ReadLoss()
    Layout()

    WantEvent("UNIT_ABSORB_AMOUNT_CHANGED", showA)
    WantEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", showH)
    WantEvent("UNIT_MAXHEALTH", showA or showH)
    WantEvent("UNIT_MAX_HEALTH_MODIFIERS_CHANGED", showL)
    local ab = bars.absorb
    WantEvent("UNIT_HEALTH", ab and ab._glowOn and ab._glow.ge ~= 3)

    PaintMax()
    if showA then
        PaintAbsorb()
        bars.absorb:Show()
    end
    if showH then
        bars.healAbsorb:SetValue(UnitGetTotalHealAbsorbs("player"))
        bars.healAbsorb:Show()
    end
    if showL then
        bars.maxHealthLoss:SetValue(loss)
        bars.maxHealthLoss:SetShown(loss > 0)
    end
    -- The overlays draw inside the bar's rect: keep its border over them.
    host:RaiseBorderAbove(level + (ab and ab._glowOn and 4 or 2), cfg.borderBehind)
end
