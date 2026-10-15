if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_Absorb.lua
--
--  Absorb and heal absorb styles, heal prediction, the Blizzard glow line,
--  the strip bar layout and CreateAbsorbBar, published through I for the
--  files that load after this one. Reads the main file through ns and
--  ns._internals; db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, ns = ...

local issecretvalue = issecretvalue
local PP = EllesmereUI.PP

local I = ns._internals
local GetSettingsForUnit, UnsnapTex = I.GetSettingsForUnit, I.UnsnapTex
local healthBarTextures, AbbreviateNumbers = I.healthBarTextures, I.AbbreviateNumbers
local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-- Shield texture. DO NOT change this path; it is the one that resolves.
local ABSORB_SHIELD_TEX = "Interface\\AddOns\\EllesmereUIUnitFrames\\Media\\shield.tga"

-- Absorb bar style textures (the shared catalogue in EllesmereUI.lua, also
-- read by the Resource Bars health bar) and alpha values.
local ABSORB_STYLE_TEX = EllesmereUI.ABSORB_STYLE_TEX
local ABSORB_STYLE_ALPHA = {
    striped         = 0.8,
    stripedReversed = 0.8,
    clean           = 0.3,
    blizzard        = 0.8,
}
-- Tiled styles (one set for the live shield and heal-absorb bars and the
-- options preview) and the Absorb Style / Heal Absorb Style dropdown data
-- read by the Main Frames rows and the Textures page tile, all from the
-- shared catalogue. Readers copy the names and orders first: the
-- SharedMedia tail is appended into the copies.
ns.ABSORB_TILED_STYLES = EllesmereUI.ABSORB_TILED_STYLES
ns.ABSORB_STYLE_NAMES = EllesmereUI.ABSORB_STYLE_NAMES
ns.ABSORB_STYLE_ORDER = EllesmereUI.ABSORB_STYLE_ORDER
ns.HEAL_ABSORB_STYLE_ORDER = EllesmereUI.HEAL_ABSORB_STYLE_ORDER

-- Absorb-style key -> texture path. Built-ins come from ABSORB_STYLE_TEX; "sm:"
-- SharedMedia keys (shared with the Bar Texture dropdown, appended into
-- healthBarTextures by AppendSharedMediaTextures) fall through to the health-bar
-- lookup. Shared by the live render and the options preview so an SM key paints identically.
function ns.ResolveAbsorbStyleTex(style, fallback)
    return ABSORB_STYLE_TEX[style]
        or (EllesmereUI.ResolveTexturePath(healthBarTextures, style, fallback))
        or fallback
end

-- Effective absorb opacity: per-unit absorbOpacity once set, else legacy behavior
-- (clean uses absorbCleanAlpha, other styles a fixed 0.8). Read-time fallback, no migration.
local function GetAbsorbOpacity(style, settings)
    if settings and settings.absorbOpacity then
        return settings.absorbOpacity / 100
    end
    if style == "clean" and settings then
        return (settings.absorbCleanAlpha or 30) / 100
    end
    return ABSORB_STYLE_ALPHA[style] or 0.8
end

local function ApplyAbsorbStyle(absorbBar, style, settings)
    if not absorbBar then return end
    local tex = ns.ResolveAbsorbStyleTex(style, ABSORB_SHIELD_TEX)
    local alpha = GetAbsorbOpacity(style, settings)
    local ac = (settings and settings.absorbColor) or { r = 1, g = 1, b = 1 }
    -- Repeating tiles vs stretch (striped3 stays a stretch texture).
    local tiled = ns.ABSORB_TILED_STYLES[style] == true
    local mask = absorbBar._absorbMask
    absorbBar:SetStatusBarTexture(tex)
    -- Per-component default: a partial colour table would throw here.
    absorbBar:SetStatusBarColor(ac.r or 1, ac.g or 1, ac.b or 1, alpha)
    local fill = absorbBar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 1)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
        if mask then fill:AddMaskTexture(mask) end
    end
    -- New fill object + tiling state: re-derive rotation (stretch styles rotate
    -- on a vertical bar, tiled ones must not).
    ns.ApplyFillRotation(absorbBar)
    local fw = absorbBar._forward
    if fw then
        fw:SetStatusBarTexture(tex)
        fw:SetStatusBarColor(ac.r, ac.g, ac.b, alpha)
        local fwFill = fw:GetStatusBarTexture()
        if fwFill then
            fwFill:SetDrawLayer("ARTWORK", 1)
            fwFill:SetHorizTile(tiled)
            fwFill:SetVertTile(tiled)
            if mask then fwFill:AddMaskTexture(mask) end
        end
        ns.ApplyFillRotation(fw)
    end
    -- New fill object: the glow lines that ride it re-seat (built only once
    -- the Blizzard Glow Line was turned on).
    if absorbBar._glow then ns.UF_AbsorbGlowAnchor(absorbBar) end
end

-- Heal absorb styling (mirrors the raid frames Absorbs section). Defaults are
-- clean white8x8, red, 0.65 alpha.
local function ApplyHealAbsorbStyle(haBar, style, settings)
    if not haBar then return end
    local tex = ns.ResolveAbsorbStyleTex(style, "Interface\\Buttons\\WHITE8X8")
    local alpha = ((settings and settings.healAbsorbOpacity) or 65) / 100
    local hc = (settings and settings.healAbsorbColor) or { r = 0.8, g = 0.15, b = 0.15 }
    -- The "Large Outlined Stripes" styles are pre-colored; render them untinted.
    if style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" then hc = { r = 1, g = 1, b = 1 } end
    local tiled = ns.ABSORB_TILED_STYLES[style] == true
    local mask = haBar._absorbMask
    haBar:SetStatusBarTexture(tex)
    haBar:SetStatusBarColor(hc.r or 0.8, hc.g or 0.15, hc.b or 0.15, alpha)
    local fill = haBar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 2)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
        if mask then fill:AddMaskTexture(mask) end
    end
    ns.ApplyFillRotation(haBar)
end

-- Two-segment absorb rendering via dynamic clip frames, works with secret-valued
-- absorbs: the value can't be split in Lua (min/subtract on secrets is blocked), so
-- STATUSBAR CLIPPING does the math visually. curClip bounds hpBar.LEFT->healthTexture.RIGHT
-- (dynamic); missClip bounds healthTexture.RIGHT->hpBar.RIGHT (dynamic). The shield
-- fills RIGHTWARD first (into missing health) and only backfills into the filled
-- portion once absorb exceeds missing health.
--   forward bar (primary): child of missClip, forward fill, TOPLEFT at
--     healthTexture.TOPRIGHT, width = hpBar width. Fills rightward by
--     (absorbAmt/maxHealth)*hpWidth; missClip cuts past hpBar.RIGHT, so visible width
--     is exactly min(absorb, missing).
--   backfill bar (overflow): child of curClip, reverse fill, TOPRIGHT at hpBar.TOPRIGHT,
--     width = hpBar width. Fills leftward from hpBar.RIGHT; curClip cuts past
--     healthTexture.RIGHT, so visible width is exactly max(0, absorb-missing) -- only
--     shows on overflow.
-- Both bars get the raw (secret-safe) absorbAmt via SetValue; no Lua arithmetic on it
-- ever happens. Wired into oUF via HealthPrediction.Override so oUF keeps event
-- registration (UNIT_HEALTH, UNIT_ABSORB_AMOUNT_CHANGED, ...) and enable/disable.

-- Re-anchor existing absorb bars for the current fill state (reverse + axis).
-- Called from the live-update path on a reverse/vertical fill toggle.
-- `settingsOverride` lets the creation path pass the settings table it already
-- holds, for frames whose ._euiUnit is not resolvable yet.
local function UpdateAbsorbBarReverseFill(frame, isReversed, settingsOverride)
    if not frame or not frame.HealthPrediction then return end
    local ab = frame.HealthPrediction.damageAbsorb
    if not ab then return end
    local fw = ab._forward
    local curClip = ab._curClip
    local missClip = ab._missClip
    local hpBar = ab._hpBar
    if not (fw and curClip and missClip and hpBar) then return end
    local hpTex = hpBar:GetStatusBarTexture()
    if not hpTex then return end

    ab._isReversed = isReversed and true or false

    -- Placement (mirrors the raid frames Absorbs section):
    --   overlay = backfill into the filled health from the HP edge (default)
    --   right   = full bar, fill from the frame's right edge
    --   left    = full bar, fill from the frame's left edge
    local s = settingsOverride or GetSettingsForUnit(frame._euiUnit)
    local absorbMode = (s and s.absorbEdgeMode) or "overlay"
    local healMode = (s and s.healAbsorbEdgeMode) or "overlay"
    -- Overshield "From Left" (overlay placement only): the excess grows from
    -- the bar's ORIGIN edge (left; right when reverse-filled; bottom/top on
    -- the vertical axis) instead of hanging off the fill edge. Mechanism:
    -- the Overlay Reverse fill-texture anchors with the OPPOSITE fill
    -- direction -- the bar's origin end sits one bar-length before the fill
    -- edge, so the clip shows exactly the absorb exceeding missing health,
    -- emerging from the frame's origin edge. nil overshieldMode falls back
    -- to the legacy showOvershield boolean (saved toggles keep meaning).
    local osm = s and s.overshieldMode
    if osm == nil then osm = (s and s.showOvershield == false) and "never" or "always" end
    local osFromLeft = osm == "fromleft"
    -- Overlay Reverse (Full): Overlay Reverse, plus the forward bar filling
    -- from the bar's ORIGIN edge, so the missing-health clip shows the absorb
    -- exceeding current health past the fill edge instead of losing it. Its
    -- clip starts exactly at the fill edge: the 1px seal into the fill would
    -- double that pixel over the backfill.
    local orFull = absorbMode == "overlayReverseFull"

    -- Vertical fill: the whole HP cluster rotates with the health bar. Every anchor
    -- below is the horizontal layout with its axis swapped -- the health fill's RIGHT
    -- edge (the "HP edge" shields/heal absorb hang off) becomes its TOP edge, reverse
    -- fill flips it to BOTTOM. Edge modes keep their key names: "right" = far edge of
    -- the fill axis (top when vertical), "left" = near edge (bottom when vertical).
    local isVert = (s and s.healthVerticalFill) and true or false
    ab._isVert = isVert
    local ha = ab._healAbsorb
    local healClip = ab._healClip
    -- Indexed, not ipairs: ha can be nil and ipairs would stop at the hole.
    local axisBars = { ab, fw, ha }
    for i = 1, 3 do
        local bar = axisBars[i]
        if bar then
            bar:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
            ns.ApplyFillRotation(bar)  -- rotate stretch styles only
        end
    end

    curClip:ClearAllPoints()
    missClip:ClearAllPoints()
    ab:ClearAllPoints()
    fw:ClearAllPoints()

    if isVert then
        -- missClip + forward bar use the overlay layout (from the origin edge in
        -- Overlay Reverse (Full)); in the other modes the backfill shows the
        -- absorb and the Override hides fw.
        if isReversed then
            missClip:SetPoint("TOPLEFT",     hpTex, "BOTTOMLEFT",  0, orFull and 0 or 1)
            missClip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
            fw:SetReverseFill(true)
            if orFull then
                fw:SetPoint("TOPLEFT",  hpBar, "TOPLEFT",  0, 0)
                fw:SetPoint("TOPRIGHT", hpBar, "TOPRIGHT", 0, 0)
            else
                fw:SetPoint("TOPLEFT",  hpTex, "BOTTOMLEFT",  0, 0)
                fw:SetPoint("TOPRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
            end
        else
            missClip:SetPoint("BOTTOMLEFT", hpTex, "TOPLEFT",  0, orFull and 0 or -1)
            missClip:SetPoint("TOPRIGHT",   hpBar, "TOPRIGHT", 0, 0)
            fw:SetReverseFill(false)
            if orFull then
                fw:SetPoint("BOTTOMLEFT",  hpBar, "BOTTOMLEFT",  0, 0)
                fw:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
            else
                fw:SetPoint("BOTTOMLEFT",  hpTex, "TOPLEFT",  0, 0)
                fw:SetPoint("BOTTOMRIGHT", hpTex, "TOPRIGHT", 0, 0)
            end
        end

        -- Shield absorb placement.
        if absorbMode == "right" or absorbMode == "left" then
            curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",     0, 0)
            curClip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
            if absorbMode == "left" then
                ab:SetReverseFill(false)
                ab:SetPoint("BOTTOMLEFT",  hpBar, "BOTTOMLEFT",  0, 0)
                ab:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
            else
                ab:SetReverseFill(true)
                ab:SetPoint("TOPLEFT",  hpBar, "TOPLEFT",  0, 0)
                ab:SetPoint("TOPRIGHT", hpBar, "TOPRIGHT", 0, 0)
            end
        elseif absorbMode == "overlayReverse" or orFull then
            -- Overlay Reverse: the WHOLE absorb fills from the health fill's
            -- leading edge back INTO the fill; the filled-region clip masks
            -- any excess past empty, so shields larger than current health
            -- never escape the fill (fw hidden by the Override, like the edge
            -- modes; Full draws that excess through fw instead).
            -- Axis-swapped for vertical, mirrored for reversed fill.
            if isReversed then
                curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",     0, 0)
                curClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
                ab:SetReverseFill(false)
                ab:SetPoint("BOTTOMLEFT",  hpTex, "BOTTOMLEFT",  0, 0)
                ab:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
            else
                curClip:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
                curClip:SetPoint("TOPRIGHT",   hpTex, "TOPRIGHT",   0, 0)
                ab:SetReverseFill(true)
                ab:SetPoint("TOPLEFT",  hpTex, "TOPLEFT",  0, 0)
                ab:SetPoint("TOPRIGHT", hpTex, "TOPRIGHT", 0, 0)
            end
        elseif isReversed then
            curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",       0, 0)
            curClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT",   0, 0)
            if osFromLeft then
                ab:SetReverseFill(true)
                ab:SetPoint("BOTTOMLEFT",  hpTex, "BOTTOMLEFT",  0, 0)
                ab:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
            else
                ab:SetReverseFill(false)
                ab:SetPoint("BOTTOMLEFT",  hpBar, "BOTTOMLEFT",  0, 0)
                ab:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
            end
        else
            curClip:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
            curClip:SetPoint("TOPRIGHT",   hpTex, "TOPRIGHT",   0, 0)
            if osFromLeft then
                ab:SetReverseFill(false)
                ab:SetPoint("TOPLEFT",  hpTex, "TOPLEFT",  0, 0)
                ab:SetPoint("TOPRIGHT", hpTex, "TOPRIGHT", 0, 0)
            else
                ab:SetReverseFill(true)
                ab:SetPoint("TOPLEFT",  hpBar, "TOPLEFT",  0, 0)
                ab:SetPoint("TOPRIGHT", hpBar, "TOPRIGHT", 0, 0)
            end
        end

        -- Heal absorb placement (own clip frame, same rules).
        if healClip then
            healClip:ClearAllPoints()
            if healMode == "right" or healMode == "left" then
                healClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",     0, 0)
                healClip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
            elseif isReversed then
                healClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",     0, 0)
                healClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
            else
                healClip:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
                healClip:SetPoint("TOPRIGHT",   hpTex, "TOPRIGHT",   0, 0)
            end
        end
        if ha then
            ha:ClearAllPoints()
            if healMode == "right" then
                ha:SetReverseFill(true)
                ha:SetPoint("TOPLEFT",  hpBar, "TOPLEFT",  0, 0)
                ha:SetPoint("TOPRIGHT", hpBar, "TOPRIGHT", 0, 0)
            elseif healMode == "left" then
                ha:SetReverseFill(false)
                ha:SetPoint("BOTTOMLEFT",  hpBar, "BOTTOMLEFT",  0, 0)
                ha:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
            elseif isReversed then
                ha:SetReverseFill(false)
                ha:SetPoint("BOTTOMLEFT",  hpTex, "BOTTOMLEFT",  0, 0)
                ha:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
            else
                ha:SetReverseFill(true)
                ha:SetPoint("TOPLEFT",  hpTex, "TOPLEFT",  0, 0)
                ha:SetPoint("TOPRIGHT", hpTex, "TOPRIGHT", 0, 0)
            end
        end
        if ab._predOn then
            ns.UF_AnchorHealPred(ab)
            ns.UF_HealPredLayout(ab)
        end
        return
    end

    -- missClip + forward bar use the overlay layout (from the origin edge in
    -- Overlay Reverse (Full)); in the other modes the backfill shows the
    -- absorb and the Override hides fw.
    if isReversed then
        missClip:SetPoint("TOPRIGHT",    hpTex, "TOPLEFT", orFull and 0 or 1, 0)
        missClip:SetPoint("BOTTOMLEFT",  hpBar, "BOTTOMLEFT", 0, 0)
        fw:SetReverseFill(true)
        if orFull then
            fw:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT",    0, 0)
            fw:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        else
            fw:SetPoint("TOPRIGHT",    hpTex, "TOPLEFT",    0, 0)
            fw:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMLEFT", 0, 0)
        end
    else
        missClip:SetPoint("TOPLEFT",     hpTex, "TOPRIGHT", orFull and 0 or -1, 0)
        missClip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        fw:SetReverseFill(false)
        if orFull then
            fw:SetPoint("TOPLEFT",    hpBar, "TOPLEFT",    0, 0)
            fw:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
        else
            fw:SetPoint("TOPLEFT",    hpTex, "TOPRIGHT",    0, 0)
            fw:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- Shield absorb placement
    if absorbMode == "right" or absorbMode == "left" then
        -- Full bar: clip covers the whole health bar, backfill anchors to the
        -- chosen frame edge (absolute, independent of reverse fill).
        curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",  0, 0)
        curClip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        if absorbMode == "left" then
            ab:SetReverseFill(false)
            ab:SetPoint("TOPLEFT",    hpBar, "TOPLEFT",    0, 0)
            ab:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
        else
            ab:SetReverseFill(true)
            ab:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT",    0, 0)
            ab:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        end
    elseif absorbMode == "overlayReverse" or orFull then
        -- Overlay Reverse: the WHOLE absorb fills from the health fill's
        -- leading edge back INTO the fill; the filled-region clip masks any
        -- excess past empty (fw hidden by the Override, like the edge modes;
        -- Full draws that excess through fw instead).
        if isReversed then
            curClip:SetPoint("TOPRIGHT",   hpBar, "TOPRIGHT",   0, 0)
            curClip:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMLEFT", 0, 0)
            ab:SetReverseFill(false)
            ab:SetPoint("TOPLEFT",    hpTex, "TOPLEFT",    0, 0)
            ab:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMLEFT", 0, 0)
        else
            curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",     0, 0)
            curClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
            ab:SetReverseFill(true)
            ab:SetPoint("TOPRIGHT",    hpTex, "TOPRIGHT",    0, 0)
            ab:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
        end
    elseif isReversed then
        curClip:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT", 0, 0)
        curClip:SetPoint("BOTTOMLEFT",  hpTex, "BOTTOMLEFT", 0, 0)
        if osFromLeft then
            ab:SetReverseFill(true)
            ab:SetPoint("TOPLEFT",    hpTex, "TOPLEFT",    0, 0)
            ab:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMLEFT", 0, 0)
        else
            ab:SetReverseFill(false)
            ab:SetPoint("TOPLEFT",    hpBar, "TOPLEFT",    0, 0)
            ab:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
        end
    else
        curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",  0, 0)
        curClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
        if osFromLeft then
            ab:SetReverseFill(false)
            ab:SetPoint("TOPRIGHT",    hpTex, "TOPRIGHT",    0, 0)
            ab:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
        else
            ab:SetReverseFill(true)
            ab:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT",    0, 0)
            ab:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- Heal absorb placement, independent of shield absorb. It has its OWN clip
    -- frame (ab._healClip) so right/left span the full bar (filled + missing
    -- health) while overlay stays clipped to filled health.
    if healClip then
        healClip:ClearAllPoints()
        if healMode == "right" or healMode == "left" then
            healClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",     0, 0)
            healClip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        elseif isReversed then
            healClip:SetPoint("TOPRIGHT",   hpBar, "TOPRIGHT",   0, 0)
            healClip:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMLEFT", 0, 0)
        else
            healClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",     0, 0)
            healClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
        end
    end
    if ha then
        ha:ClearAllPoints()
        if healMode == "right" then
            ha:SetReverseFill(true)
            ha:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT",    0, 0)
            ha:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        elseif healMode == "left" then
            ha:SetReverseFill(false)
            ha:SetPoint("TOPLEFT",    hpBar, "TOPLEFT",    0, 0)
            ha:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
        else
            -- Overlay: eat into the filled health from the HP edge, mirrored for
            -- reverse-filled health bars.
            ha:SetReverseFill(not isReversed)
            if isReversed then
                ha:SetPoint("TOPLEFT",    hpTex, "TOPLEFT",    0, 0)
                ha:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMLEFT", 0, 0)
            else
                ha:SetPoint("TOPRIGHT",    hpTex, "TOPRIGHT",    0, 0)
                ha:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
            end
        end
    end
    if ab._predOn then
        ns.UF_AnchorHealPred(ab)
        ns.UF_HealPredLayout(ab)
    end
end

-------------------------------------------------------------------------------
--  Heal Prediction (opt-in per unit, s.healPrediction; player, target and
--  focus): incoming heals drawn past the health fill as two segments, the
--  player's own heals first, then everyone else's. Both are StatusBars fed by
--  a heal prediction calculator (secret-safe: values only reach SetValue).
--  Cost: off builds nothing and leaves the engine's opt-in "healpred" channel
--  off the frame, so no event or repaint reaches it. On, that channel
--  registers UNIT_HEAL_PREDICTION for the one unit (plus the vehicle for the
--  player) and joins its max-health and heal-absorb routes; the engine's
--  same-frame stamp collapses bursts (one trailing next-frame paint settles a
--  deduped repeat), and a paint is one calculator fill, the range and two
--  SetValue calls.
--  No current-health input: the calculator clamps to MAXIMUM health, the
--  segments ride the health fill's edge by anchor, and a clip cuts them at the
--  bar's end -- Overheal 0: the missing-health clip; Overheal > 0: a holder
--  outside the frame's bar clip that clips at the end plus the allowance.
--  Style (texture, colors, opacity, Overheal) is applied by UF_HealPredApply
--  from the spawn and settings reload paths, size by the health bar's
--  OnSizeChanged; never per paint.
--  On ns: this chunk sits at the Lua 5.1 local ceiling.
-------------------------------------------------------------------------------
ns.UF_HEAL_PRED_MY    = { r = 102/255, g = 243/255, b = 102/255 }
ns.UF_HEAL_PRED_OTHER = { r = 40/255,  g = 170/255, b = 40/255 }
ns.UF_HEAL_PRED_UNITS = { player = true, target = true, focus = true }

-- Anchors both segments at the health fill's leading edge, in the fill
-- direction (reverse and vertical fill included), the others' segment
-- starting where the player's ends.
function ns.UF_AnchorHealPred(ab)
    local my, other = ab._predMy, ab._predOther
    local hpTex = ab._hpBar and ab._hpBar:GetStatusBarTexture()
    if not (my and hpTex) then return end
    local myTex = my:GetStatusBarTexture()
    local isVert, isRev = ab._isVert and true or false, ab._isReversed and true or false
    for i = 1, 2 do
        local bar = (i == 1) and my or other
        bar:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
        ns.ApplyFillRotation(bar)
        bar:SetReverseFill(isRev)
        bar:ClearAllPoints()
    end
    local a1, b1, a2, b2
    if isVert then
        if isRev then a1, b1, a2, b2 = "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT"
        else a1, b1, a2, b2 = "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT" end
    elseif isRev then a1, b1, a2, b2 = "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT"
    else a1, b1, a2, b2 = "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" end
    my:SetPoint(a1, hpTex, b1, 0, 0)
    my:SetPoint(a2, hpTex, b2, 0, 0)
    other:SetPoint(a1, myTex, b1, 0, 0)
    other:SetPoint(a2, myTex, b2, 0, 0)
end

function ns.UF_NewHealPredBar(ab)
    local bar = CreateFrame("StatusBar", nil, ab._missClip)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local fill = bar:GetStatusBarTexture()
    if fill and ab._absorbMask then fill:AddMaskTexture(ab._absorbMask) end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetFrameLevel(ab._hpBar:GetFrameLevel() + 1)
    bar:Hide()
    return bar
end

-- Seats the segment fills' masks: the health-bar-bounds edge mask and, under
-- Blizzard Style, the stock bar shape (ab._blizzMaskOn, stamped by the art
-- pass). Both apply only while the segments sit inside the bar (Overheal 0).
-- A texture swap makes new fills, so this runs after every swap, parent
-- change and art pass.
function ns.UF_HealPredMasks(ab)
    local inside = (ab._predOver or 0) == 0
    local edge = ab._absorbMask
    local shape = ab._hpBar._blizzMask
    for i = 1, 2 do
        local bar = (i == 1) and ab._predMy or ab._predOther
        local fill = bar:GetStatusBarTexture()
        if fill then
            if edge then
                pcall(fill.RemoveMaskTexture, fill, edge)
                if inside then fill:AddMaskTexture(edge) end
            end
            if shape then
                pcall(fill.RemoveMaskTexture, fill, shape)
                if inside and ab._blizzMaskOn then fill:AddMaskTexture(shape) end
            end
        end
    end
end

-- Size and the Overheal holder: both follow the health bar's size and fill
-- axis. Runs from the style pass, the absorb re-anchor pass and the health
-- bar's OnSizeChanged.
function ns.UF_HealPredLayout(ab)
    local hp = ab._hpBar
    local w, h = hp:GetWidth(), hp:GetHeight()
    ab._predMy:SetSize(w, h)
    ab._predOther:SetSize(w, h)
    local over = ab._predOver or 0
    local holder = ab._predHolder
    if over > 0 and holder then
        local ext = (ab._isVert and h or w) * over / 100
        local l, r, t, b = 0, 0, 0, 0
        if ab._isVert then
            if ab._isReversed then b = -ext else t = ext end
        elseif ab._isReversed then
            l = -ext
        else
            r = ext
        end
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", hp, "TOPLEFT", l, t)
        holder:SetPoint("BOTTOMRIGHT", hp, "BOTTOMRIGHT", r, b)
    end
end

-- The healpred channel's painter: values only, no style work.
function ns.UF_PaintHealPred(frame, unit)
    local ab = frame.HealthPrediction.damageAbsorb
    if not ab._predOn then return end
    local calc = ab._predCalc
    UnitGetDetailedHealPrediction(unit, "player", calc)
    local _, mine, others = calc:GetIncomingHeals()
    local maxHealth = UnitHealthMax(unit) or 0
    local my, other = ab._predMy, ab._predOther
    my:SetMinMaxValues(0, maxHealth)
    other:SetMinMaxValues(0, maxHealth)
    my:SetValue(mine)
    other:SetValue(others)
end
ns.Engine.SetPainter("healpred", ns.UF_PaintHealPred)

-- Style pass + channel sync for one frame (unitKey = its settings key).
-- Idempotent; runs at spawn and on every settings reload, after the health
-- texture is applied. Off tears down to hidden bars and no channel.
function ns.UF_HealPredApply(frame, unitKey, s)
    local hpe = frame.HealthPrediction
    local ab = hpe and hpe.damageAbsorb
    if not (ab and ab._missClip) then return end
    local on = ns.UF_HEAL_PRED_UNITS[unitKey] and s and s.healPrediction == true
        and CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction and true or false
    if not on then
        if ab._predOn then
            ab._predOn = false
            ab._predMy:Hide()
            ab._predOther:Hide()
            ns.Engine.SetChannelOn(frame, "healpred", false)
        end
        return
    end
    local hp = ab._hpBar
    if not ab._predMy then
        ab._predMy = ns.UF_NewHealPredBar(ab)
        ab._predOther = ns.UF_NewHealPredBar(ab)
        local calc = CreateUnitHealPredictionCalculator()
        -- Every clamp reads maximum health, never current health, so the clip
        -- does the missing-health cut and no health event is needed; heal
        -- absorbs reduce the drawn heal (their own event is routed).
        local modes = Enum and Enum.UnitIncomingHealClampMode
        if calc.SetIncomingHealClampMode and modes then
            calc:SetIncomingHealClampMode(modes.MaximumHealth)
        end
        local haClamp = Enum and Enum.UnitHealAbsorbClampMode
        if calc.SetHealAbsorbClampMode and haClamp then
            calc:SetHealAbsorbClampMode(haClamp.MaximumHealth)
        end
        local haMode = Enum and Enum.UnitHealAbsorbMode
        if calc.SetHealAbsorbMode and haMode then
            calc:SetHealAbsorbMode(haMode.ReducedByIncomingHeals)
        end
        ab._predCalc = calc
        -- Our own health bar; returns at once while the option is off.
        hp:HookScript("OnSizeChanged", function()
            if ab._predOn then ns.UF_HealPredLayout(ab) end
        end)
    end
    local my, other = ab._predMy, ab._predOther
    -- Texture (s.healPredTexture): "health" (default) follows the frame's own
    -- health bar, read off its fill so every texture path (per frame, profile,
    -- donor, Blizzard Style) matches; "flat" is a plain fill; anything else is a
    -- health-bar texture key. A swap makes new fill objects, so the others'
    -- anchor, fill rotation and the masks are re-seated after it.
    local texKey = s.healPredTexture or "health"
    local path
    if texKey == "health" then
        local hFill = hp:GetStatusBarTexture()
        path = hFill and hFill:GetTexture()
    elseif texKey ~= "flat" then
        path = EllesmereUI.ResolveTexturePath(healthBarTextures, texKey, nil)
    end
    path = path or "Interface\\Buttons\\WHITE8X8"
    local retex = ab._predTexPath ~= path
    if retex then
        ab._predTexPath = path
        for i = 1, 2 do
            local bar = (i == 1) and my or other
            bar:SetStatusBarTexture(path)
            local fill = bar:GetStatusBarTexture()
            if fill then UnsnapTex(fill) end
        end
    end
    -- While off, the re-anchor pass skips the bars, so turning on re-seats
    -- them for the current fill axis.
    if retex or not ab._predOn then ns.UF_AnchorHealPred(ab) end
    -- Overheal: how far past full health the bars may run (0 = stop at the
    -- end). The health bar sits inside the frame's bar clip, so running past
    -- its end takes a holder outside it, parented to the unit frame; the masks
    -- come off there. Layout places the holder.
    local over = tonumber(s.healPredOverheal) or 0
    local relayout = (not ab._predOn) or ab._predOver ~= over
    if retex or ab._predOver ~= over then
        ab._predOver = over
        local parent = ab._missClip
        if over > 0 then
            local holder = ab._predHolder
            if not holder then
                holder = CreateFrame("Frame", nil, frame)
                holder:SetClipsChildren(true)
                ab._predHolder = holder
            end
            holder:SetFrameLevel(hp:GetFrameLevel() + 1)
            parent = holder
        end
        for i = 1, 2 do
            local bar = (i == 1) and other or my
            bar:SetParent(parent)
            bar:SetFrameLevel(hp:GetFrameLevel() + i)
        end
        ns.UF_HealPredMasks(ab)
    end
    local alpha = (s.healPredOpacity or 60) / 100
    local mc = s.healPredColor or ns.UF_HEAL_PRED_MY
    local oc = s.healPredOtherColor or ns.UF_HEAL_PRED_OTHER
    my:SetStatusBarColor(mc.r, mc.g, mc.b, alpha)
    other:SetStatusBarColor(oc.r, oc.g, oc.b, alpha)
    -- While on, the re-anchor pass and the size hook keep the layout current.
    if relayout then ns.UF_HealPredLayout(ab) end
    my:Show()
    other:Show()
    ab._predOn = true
    ns.Engine.SetChannelOn(frame, "healpred", true)
    if frame:IsShown() then ns.UF_PaintHealPred(frame, frame._euiUnit) end
end

-------------------------------------------------------------------------------
--  Blizzard Glow Line (opt-in per unit, s.absorbGlowLine; player, target and
--  focus, and boss frames through the Target styling they draw absorbs with).
--  A soft line on the shield's edge next to current health. Placement
--  (g.ge), resolved by the settings pass:
--    1 = Overlay: the current-health seam, moving to the overshield's inner
--        edge while overshielding (the bar's far end with Show Overshield Never);
--    2 = Overlay with Show Overshield From Left: the seam, moving to the
--        from-left overshield's edge;
--    3 = Overlay Reverse: the shield's inner end, which always meets health;
--    5 = the far-edge placement (From Right Edge; From Left Edge on a reverse
--        fill): the shield's inner end, only while it reaches current health.
--  The origin-edge placement and a vertical fill draw nothing.
--  Cost: off builds nothing and the absorb painter pays one field test. The
--  host, gate bar, lines and the clamp calculator are built on first enable.
--  On, the seam line self-gates off the secret absorb through its gate bar,
--  and the overshield boolean (the calculator's Missing Health clamp) flips
--  the lines through their host frames' boolean alpha. Placements that read
--  it join the opt-in "absglow" channel (the unit's health changes), and the
--  flip returns at once while no shield is up. Anchors and art are set by
--  the settings pass and after a retexture, never per paint.
--  On ns: this chunk sits at the Lua 5.1 local ceiling.
-------------------------------------------------------------------------------
-- Glow Line Texture art: { file, blend mode, width, width in whole pixels }.
ns.UF_GLOW_LINE_ART = {
    blizzard         = { "Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga", "ADD", 16 },
    pixelsGlow       = { "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\pixels-glowline.tga", "ADD", 16 },
    pixelsOvershield = { "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\pixels-overshield-line.tga", "BLEND", 2, true },
}
function ns.UF_GlowLineWidth(art)
    return art[4] and PP.Scale(art[3]) or art[3]
end

-- Leader Indicator Icon Style art (leaderIndicatorStyle), shared with the
-- options preview.
ns.UF_LEADER_ART = {
    blizzard = { leader = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
                 assist = "Interface\\GroupFrame\\UI-Group-AssistantIcon" },
    pixels   = { leader = "Interface\\AddOns\\EllesmereUI\\media\\icons\\roles\\pixels-leader.tga",
                 assist = "Interface\\AddOns\\EllesmereUI\\media\\icons\\roles\\pixels-assist.tga" },
}
-- Elite/Rare Indicator Pixels Dragon art (eliteIndicatorStyle "pixelsDragon"),
-- keyed by classification plus "player" for player targets. The art wraps a
-- circle 120 texels across on its 512 canvas, so the texture spans the
-- portrait's size times 512/120, centred on it.
ns.UF_ELITE_DRAGON_ART = {
    worldboss = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\pixels_dragon_boss.tga",
    elite     = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\pixels_dragon_elite.tga",
    rareelite = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\pixels_dragon_rare.tga",
    rare      = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\pixels_dragon_rare.tga",
    player    = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\pixels_dragon_player.tga",
}
ns.UF_ELITE_DRAGON_SCALE = 512 / 120

function ns.UF_BuildAbsorbGlow(ab)
    local hp = ab._hpBar
    -- Own clip host above the shield bars: the health-side half of the line
    -- would otherwise be cut by the missing-health clip.
    local host = CreateFrame("Frame", nil, hp)
    host:SetAllPoints(hp)
    host:SetClipsChildren(true)
    host:SetFrameLevel(hp:GetFrameLevel() + 4)
    -- Each line sits on its own frame: boolean alpha works on frames (on a
    -- texture it renders nothing on this client).
    local edgeHost = CreateFrame("Frame", nil, host)
    edgeHost:SetAllPoints(host)
    -- Invisible gate bar on the edge: fed the absorb over a 0-1 range, its
    -- fill is full with ANY shield and empty without one, so the line drawn
    -- over the fill needs no boolean read of the secret amount.
    local gate = CreateFrame("StatusBar", nil, edgeHost)
    gate:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    gate:SetStatusBarColor(1, 1, 1, 0)
    gate:SetMinMaxValues(0, 1)
    gate:SetValue(0)
    local edge = edgeHost:CreateTexture(nil, "OVERLAY")
    edge:SetAllPoints(gate:GetStatusBarTexture())
    local bfHost = CreateFrame("Frame", nil, host)
    bfHost:SetAllPoints(host)
    local bf = bfHost:CreateTexture(nil, "OVERLAY")
    local g = { host = host, edgeHost = edgeHost, gate = gate, edge = edge, bfHost = bfHost, bf = bf }
    if CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction then
        local calc = CreateUnitHealPredictionCalculator()
        -- Configured once: the Missing Health clamp makes GetDamageAbsorbs'
        -- second return the overshield boolean (shield exceeds empty health).
        if calc.SetMaximumHealthMode and Enum.UnitMaximumHealthMode then
            calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
        end
        if calc.SetDamageAbsorbClampMode and Enum.UnitDamageAbsorbClampMode then
            calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)
        end
        g.calc = calc
    end
    ab._glow = g
    return g
end

-- Seats both lines for the stamped placement and fill direction. Runs from
-- the settings pass and after a retexture (a new shield fill object).
function ns.UF_AbsorbGlowAnchor(ab)
    local g = ab._glow
    if not (g and g.ge) then return end
    local rev = g.rev
    local near, far = rev and "RIGHT" or "LEFT", rev and "LEFT" or "RIGHT"
    local off = rev and 1 or -1
    local fill = ab:GetStatusBarTexture()
    local gate, bf = g.gate, g.bf
    gate:ClearAllPoints()
    if g.ge >= 3 then
        gate:SetPoint("CENTER", fill, near, off, 0)
    else
        gate:SetPoint("CENTER", ab._forward, near, off, 0)
    end
    bf:ClearAllPoints()
    if g.anc == 1 then
        bf:SetPoint("CENTER", fill, near, off, 0)
    elseif g.anc == 2 then
        bf:SetPoint("CENTER", fill, far, -off, 0)
    else
        bf:SetPoint("CENTER", ab, far, off, 0)
    end
end

-- The overshield flip. Placements 1-2: the seam line hides while
-- overshielding and the overshield line shows only then; 5: the line shows
-- only while the shield reaches current health. The boolean only ever
-- reaches SetAlphaFromBoolean.
function ns.UF_AbsorbGlowFlip(ab, unit)
    local g = ab._glow
    local ge = g.ge
    if ge == 3 then return end
    local eh, bh = g.edgeHost, g.bfHost
    local calc = g.calc
    if not (calc and eh.SetAlphaFromBoolean) then
        -- No calculator on this client: the seam line alone.
        eh:SetAlpha(ge == 5 and 0 or 1)
        bh:SetAlpha(0)
        return
    end
    UnitGetDetailedHealPrediction(unit, nil, calc)
    local _, clamped = calc:GetDamageAbsorbs()
    if ge == 5 then
        eh:SetAlphaFromBoolean(clamped, 1, 0)
    else
        eh:SetAlphaFromBoolean(clamped, 0, 1)
        bh:SetAlphaFromBoolean(clamped, 1, 0)
    end
end

-- Value pass, from the absorb painter while the line is on: the gate takes
-- the raw absorb, sizes follow the bar height and the pixel grid (a
-- whole-pixel width moves with it; size-gated), then the flip.
function ns.UF_PaintAbsorbGlow(ab, unit, absorbAmt, hpH)
    local g = ab._glow
    if g.szH ~= hpH or g.szM ~= PP.mult then
        g.szH, g.szM = hpH, PP.mult
        local w = ns.UF_GlowLineWidth(g.art)
        g.gate:SetSize(w, hpH)
        g.bf:SetSize(w, hpH)
    end
    g.gate:SetValue(absorbAmt)
    ns.UF_AbsorbGlowFlip(ab, unit)
end

-- The absglow channel's painter: the flip alone, and only while a shield is
-- up (without one there is nothing to flip; the absorb paint that cleared
-- it already did).
ns.Engine.SetPainter("absglow", function(frame, unit)
    local hpe = frame.HealthPrediction
    local ab = hpe and hpe.damageAbsorb
    if ab and ab._glowOn and frame._absActive then ns.UF_AbsorbGlowFlip(ab, unit) end
end)

-- Settings pass for one frame (spawn and every reload), after the absorb
-- re-anchor pass so the fill direction and axis are current. Resolves on/off
-- and the placement, builds on first enable, and re-seats art and anchors
-- only when one of their inputs (placement, overshield anchor, fill
-- direction, art) changed; a change repaints the frame at once.
function ns.UF_AbsorbGlowApply(frame, unit)
    local hpe = frame.HealthPrediction
    local ab = hpe and hpe.damageAbsorb
    if not (ab and ab._forward) then return end
    local s
    if unit and unit:match("^boss") then
        if not (db.profile.boss and db.profile.boss.showAbsorbs == false) then s = db.profile.target end
    else
        s = GetSettingsForUnit(unit)
    end
    local on = s and s.absorbGlowLine == true and (s.showPlayerAbsorb or "none") ~= "none"
        and not ab._isVert
    local rev = ab._isReversed and true or false
    local ge, anc
    if on then
        local em = s.absorbEdgeMode or "overlay"
        if em == "overlay" then
            local osm = s.overshieldMode
            if osm == nil then osm = (s.showOvershield == false) and "never" or "always" end
            ge = (osm == "fromleft") and 2 or 1
            anc = (osm == "never") and 0 or ge
        elseif em == "overlayReverse" or em == "overlayReverseFull" then
            ge, anc = 3, 0
        elseif em == (rev and "left" or "right") then
            ge, anc = 5, 0
        else
            on = false
        end
    end
    if not on then
        if ab._glowOn then
            ab._glowOn = false
            ab._glow.host:Hide()
            ns.Engine.SetChannelOn(frame, "absglow", false)
        end
        return
    end
    local g = ab._glow or ns.UF_BuildAbsorbGlow(ab)
    local art = ns.UF_GLOW_LINE_ART[s.absorbGlowLineTexture] or ns.UF_GLOW_LINE_ART.blizzard
    local changed = not ab._glowOn
    if g.ge ~= ge or g.anc ~= anc or g.rev ~= rev then
        g.ge, g.anc, g.rev = ge, anc, rev
        ns.UF_AbsorbGlowAnchor(ab)
        if ge == 3 then g.edgeHost:SetAlpha(1) end
        if ge <= 2 then g.bfHost:Show() else g.bfHost:Hide() end
        changed = true
    end
    if g.art ~= art then
        g.art = art
        g.edge:SetTexture(art[1]); g.edge:SetBlendMode(art[2])
        g.bf:SetTexture(art[1]); g.bf:SetBlendMode(art[2])
        g.szH = nil
        changed = true
    end
    if not changed then return end
    ab._glowOn = true
    g.host:Show()
    ns.Engine.SetChannelOn(frame, "absglow", ge ~= 3 and g.calc ~= nil)
    if frame:IsShown() and frame._euiUnit and hpe.Override then
        hpe.Override(frame, "ForceUpdate", frame._euiUnit)
    end
end

-- Absorb / Heal Absorb strip-bar position resolvers + layout (mirrors Raid
-- Frames). On ns so the options-panel preview can reuse the layout.
ns.UF_GetAbsorbBarPos     = function(s) return (s and s.absorbBarPosition)     or "none" end
ns.UF_GetHealAbsorbBarPos = function(s) return (s and s.healAbsorbBarPosition) or "none" end

-- Anchor/orient a strip bar (Absorb Bar or Heal Absorb Bar). "above*" sit on top
-- of the health bar; "top*"/"bottom*" sit inside at the matching edge, drawn just
-- above the absorb texture; "aboveAbsorb"/"belowAbsorb" (heal bar only) sit flush
-- against the Absorb Bar, derived from its POSITION (not its live visibility, so
-- they never shift). "*Right" fills from the right edge. `absorbLevel` is the
-- absorb-overlay frame level (inside strips render at +1).
ns.UF_ApplyStripBarLayout = function(stripBar, hp, position, height, absorbLevel, absorbPos, absorbHeight)
    if not stripBar or not hp then return end
    stripBar:ClearAllPoints()
    stripBar:SetHeight(PP.Scale(height or 4))
    local insideLevel = (absorbLevel or (hp:GetFrameLevel() + 1)) + 1
    if position == "aboveAbsorb" then
        absorbPos = absorbPos or "none"
        local leftPoint, rightPoint, yOff = "TOPLEFT", "TOPRIGHT", 0
        if absorbPos == "aboveRight" or absorbPos == "aboveLeft" then
            yOff = PP.Scale(absorbHeight or 4)
        elseif absorbPos == "bottomRight" or absorbPos == "bottomLeft" then
            leftPoint, rightPoint = "BOTTOMLEFT", "BOTTOMRIGHT"
            yOff = PP.Scale(absorbHeight or 4)
        end
        stripBar:SetReverseFill(absorbPos ~= "aboveLeft" and absorbPos ~= "topLeft" and absorbPos ~= "bottomLeft")
        stripBar:SetPoint("BOTTOMLEFT", hp, leftPoint, 0, yOff)
        stripBar:SetPoint("BOTTOMRIGHT", hp, rightPoint, 0, yOff)
        stripBar:SetFrameLevel(insideLevel)
    elseif position == "belowAbsorb" then
        absorbPos = absorbPos or "none"
        if absorbPos == "bottomRight" or absorbPos == "bottomLeft" then
            stripBar:SetReverseFill(absorbPos == "bottomRight")
            stripBar:SetPoint("TOPLEFT",  hp, "BOTTOMLEFT",  0, 0)
            stripBar:SetPoint("TOPRIGHT", hp, "BOTTOMRIGHT", 0, 0)
            stripBar:SetFrameLevel(insideLevel)
            return
        end
        local yOff = 0
        if absorbPos == "topRight" or absorbPos == "topLeft" then
            yOff = -PP.Scale(absorbHeight or 4)
        end
        stripBar:SetReverseFill(absorbPos ~= "aboveLeft" and absorbPos ~= "topLeft")
        stripBar:SetPoint("TOPLEFT",  hp, "TOPLEFT",  0, yOff)
        stripBar:SetPoint("TOPRIGHT", hp, "TOPRIGHT", 0, yOff)
        stripBar:SetFrameLevel(insideLevel)
    elseif position == "topRight" or position == "topLeft" then
        stripBar:SetReverseFill(position == "topRight")
        stripBar:SetPoint("TOPLEFT",  hp, "TOPLEFT",  0, 0)
        stripBar:SetPoint("TOPRIGHT", hp, "TOPRIGHT", 0, 0)
        stripBar:SetFrameLevel(insideLevel)
    elseif position == "bottomRight" or position == "bottomLeft" then
        stripBar:SetReverseFill(position == "bottomRight")
        stripBar:SetPoint("BOTTOMLEFT",  hp, "BOTTOMLEFT",  0, 0)
        stripBar:SetPoint("BOTTOMRIGHT", hp, "BOTTOMRIGHT", 0, 0)
        stripBar:SetFrameLevel(insideLevel)
    else
        stripBar:SetReverseFill(position == "aboveRight")
        stripBar:SetPoint("BOTTOMLEFT",  hp, "TOPLEFT",  0, 0)
        stripBar:SetPoint("BOTTOMRIGHT", hp, "TOPRIGHT", 0, 0)
        stripBar:SetFrameLevel(hp:GetFrameLevel() + 3)
    end
end

-- Armed-frames absorb belt (mirror of the Raid Frames one): covers the ONE
-- absorb transition with no event at all -- an aura-granted shield expiring
-- on its TIMER on an unhit, topped unit (VDH Infernal Strike field class).
-- One shared 0.5s ticker exists only while some hosted frame is armed; each
-- sweep repaints only stale-painted armed frames and cancels itself when the
-- set empties. Zero event registrations, zero cost with no shields up.
do
    local armed = {}
    local belt
    function ns.UF_AbArm(frame)
        frame._absActive = true
        armed[frame] = true
        if not belt and C_Timer then
            belt = C_Timer.NewTicker(0.5, function()
                local now = GetTime()
                local any = false
                for f in pairs(armed) do
                    any = true
                    if (now - (f._absPaintAt or 0)) > 0.45 then
                        local hp = f.HealthPrediction
                        local ov = hp and hp.Override
                        if ov then ov(f, "EUI_AbsorbBelt", f._euiUnit) end
                    end
                end
                if not any then belt:Cancel(); belt = nil end
            end)
        end
    end
    function ns.UF_AbDisarm(frame)
        -- Armed -> clear is the moment a shield ended; if it ended with no
        -- absorb event (the timer-expiry class this belt exists for), any
        -- long-form Absorb text zone is showing the dead amount. One text
        -- recompose here keeps those zones honest WITHOUT the text channel
        -- riding UNIT_AURA. No-op frames early-return on their zone list.
        if frame._absActive and ns.UF_PaintText then
            ns.UF_PaintText(frame, frame._euiUnit, "EUI_AbsorbEnd")
        end
        frame._absActive = false
        armed[frame] = nil
    end
end

local function CreateAbsorbBar(frame, unit, settings)
    if not frame.Health then return end

    local hpBar = frame.Health

    -- Mask texture: constrains absorb rendering to exact health bar bounds at the
    -- GPU level, preventing the subpixel bleed where absorb textures extend 1px
    -- outside the health bar at some frame positions.
    local absorbMask = hpBar:CreateMaskTexture()
    absorbMask:SetAllPoints(hpBar)
    absorbMask:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Reverse fill: when health fills right-to-left, mirror all absorb anchors.
    local isReversed = settings.healthReverseFill and true or false

    -- Current HP clip: bounds the backfill bar to the filled health area.
    local curClip = CreateFrame("Frame", nil, hpBar)
    if isReversed then
        curClip:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT", 0, 0)
        curClip:SetPoint("BOTTOMLEFT",  hpBar:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
    else
        curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",  0, 0)
        curClip:SetPoint("BOTTOMRIGHT", hpBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    end
    curClip:SetClipsChildren(true)

    -- Missing HP clip: bounds the forward bar to the empty health area.
    local missClip = CreateFrame("Frame", nil, hpBar)
    if isReversed then
        missClip:SetPoint("TOPRIGHT",    hpBar:GetStatusBarTexture(), "TOPLEFT", 1, 0)
        missClip:SetPoint("BOTTOMLEFT",  hpBar, "BOTTOMLEFT", 0, 0)
    else
        missClip:SetPoint("TOPLEFT",     hpBar:GetStatusBarTexture(), "TOPRIGHT", -1, 0)
        missClip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
    end
    missClip:SetClipsChildren(true)

    -- Backfill bar (overflow): grows into filled health from the edge.
    local backfillBar = CreateFrame("StatusBar", nil, curClip)
    backfillBar:SetStatusBarTexture(ABSORB_SHIELD_TEX)
    local bfFill = backfillBar:GetStatusBarTexture()
    if bfFill then bfFill:SetDrawLayer("ARTWORK", 1); bfFill:AddMaskTexture(absorbMask) end
    backfillBar:SetStatusBarColor(1, 1, 1, 0.8)
    backfillBar:SetReverseFill(not isReversed)
    if isReversed then
        backfillBar:SetPoint("TOPLEFT",    hpBar, "TOPLEFT",    0, 0)
        backfillBar:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
    else
        backfillBar:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT",    0, 0)
        backfillBar:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
    end
    backfillBar:SetWidth(hpBar:GetWidth())
    backfillBar:SetHeight(hpBar:GetHeight())
    backfillBar:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    backfillBar:Hide()

    -- Forward bar (primary): grows into missing health from the HP edge.
    local forwardBar = CreateFrame("StatusBar", nil, missClip)
    forwardBar:SetStatusBarTexture(ABSORB_SHIELD_TEX)
    local fwFill = forwardBar:GetStatusBarTexture()
    if fwFill then fwFill:SetDrawLayer("ARTWORK", 1); fwFill:AddMaskTexture(absorbMask) end
    forwardBar:SetStatusBarColor(1, 1, 1, 0.8)
    forwardBar:SetReverseFill(isReversed)
    if isReversed then
        forwardBar:SetPoint("TOPRIGHT",    hpBar:GetStatusBarTexture(), "TOPLEFT",    0, 0)
        forwardBar:SetPoint("BOTTOMRIGHT", hpBar:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
    else
        forwardBar:SetPoint("TOPLEFT",    hpBar:GetStatusBarTexture(), "TOPRIGHT",    0, 0)
        forwardBar:SetPoint("BOTTOMLEFT", hpBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    end
    forwardBar:SetWidth(hpBar:GetWidth())
    forwardBar:SetHeight(hpBar:GetHeight())
    forwardBar:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    forwardBar:Hide()

    -- Heal absorb bar: overlays filled-health in red, reverse-filling from the health
    -- texture edge inward. Has its OWN clip frame (not the shield's curClip) so
    -- placement is independent: overlay clips to filled health, right/left span the
    -- FULL bar. Bounds set per healAbsorbEdgeMode in UpdateAbsorbBarReverseFill.
    local healClip = CreateFrame("Frame", nil, hpBar)
    if isReversed then
        healClip:SetPoint("TOPRIGHT",   hpBar, "TOPRIGHT", 0, 0)
        healClip:SetPoint("BOTTOMLEFT", hpBar:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
    else
        healClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT", 0, 0)
        healClip:SetPoint("BOTTOMRIGHT", hpBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    end
    healClip:SetClipsChildren(true)
    local healAbsorbBar = CreateFrame("StatusBar", nil, healClip)
    healAbsorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    healAbsorbBar._absorbMask = absorbMask
    local haFill = healAbsorbBar:GetStatusBarTexture()
    if haFill then haFill:SetDrawLayer("ARTWORK", 2); haFill:AddMaskTexture(absorbMask) end
    healAbsorbBar:SetStatusBarColor(0.8, 0.15, 0.15, 0.65)
    healAbsorbBar:SetReverseFill(not isReversed)
    if isReversed then
        healAbsorbBar:SetPoint("TOPLEFT",    hpBar, "TOPLEFT",    0, 0)
        healAbsorbBar:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
    else
        healAbsorbBar:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT",    0, 0)
        healAbsorbBar:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
    end
    healAbsorbBar:SetWidth(hpBar:GetWidth())
    healAbsorbBar:SetHeight(hpBar:GetHeight())
    healAbsorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    healAbsorbBar:Hide()

    -- Black backing behind the heal-absorb texture (opacity via healAbsorbBgOpacity),
    -- drawn UNDER the fill (ARTWORK sublevel 1 < fill's 2), masked + SetAllPoints'd to
    -- the fill rect each update so it tracks the secret heal-absorb amount.
    local haBg = healAbsorbBar:CreateTexture(nil, "ARTWORK", nil, 1)
    haBg:SetColorTexture(0, 0, 0, 0.15)
    if absorbMask then haBg:AddMaskTexture(absorbMask) end
    haBg:Hide()
    healAbsorbBar._bg = haBg

    -- Absorb Bar + Heal Absorb Bar: separate strips (mirrors Raid Frames) at a
    -- configurable position, parented to the frame so "above" positions can sit
    -- outside the health bar. Created hidden; the Override drives them.
    local absorbTopBar = CreateFrame("StatusBar", nil, frame)
    absorbTopBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    absorbTopBar:SetStatusBarColor(1, 1, 1, 1)
    absorbTopBar:SetReverseFill(true)
    absorbTopBar:SetPoint("BOTTOMLEFT",  hpBar, "TOPLEFT",  0, 0)
    absorbTopBar:SetPoint("BOTTOMRIGHT", hpBar, "TOPRIGHT", 0, 0)
    absorbTopBar:SetHeight(4)
    absorbTopBar:SetFrameLevel(hpBar:GetFrameLevel() + 3)
    absorbTopBar:Hide()

    local healAbsorbTopBar = CreateFrame("StatusBar", nil, frame)
    healAbsorbTopBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    healAbsorbTopBar:SetStatusBarColor(200/255, 29/255, 29/255, 1)
    healAbsorbTopBar:SetReverseFill(true)
    healAbsorbTopBar:SetPoint("BOTTOMLEFT",  hpBar, "TOPLEFT",  0, 0)
    healAbsorbTopBar:SetPoint("BOTTOMRIGHT", hpBar, "TOPRIGHT", 0, 0)
    healAbsorbTopBar:SetHeight(4)
    healAbsorbTopBar:SetFrameLevel(hpBar:GetFrameLevel() + 3)
    healAbsorbTopBar:Hide()

    -- Attach extras to the backfill (main) bar so anything referencing
    -- HealthPrediction.damageAbsorb can hide/show both segments together.
    backfillBar._forward      = forwardBar
    backfillBar._healAbsorb   = healAbsorbBar
    backfillBar._topBar       = absorbTopBar
    backfillBar._healTopBar   = healAbsorbTopBar
    backfillBar._hpBar        = hpBar
    backfillBar._curClip      = curClip
    backfillBar._healClip     = healClip
    backfillBar._missClip     = missClip
    backfillBar._absorbMask   = absorbMask
    backfillBar._isReversed   = isReversed

    -- Raise the power bar above the absorb overlay.
    local power = frame and frame.Power
    if power then
        power:SetFrameLevel(math.max(power:GetFrameLevel(), hpBar:GetFrameLevel() + 2))
    end

    backfillBar:HookScript("OnHide", function()
        forwardBar:Hide()
        healAbsorbBar:Hide()
    end)

    -- Named local so profilers attribute this hot painter (it traced as the
    -- "(anonymous) :5228" row); assigned into HealthPrediction below.
    local UF_AbsorbOverride
    UF_AbsorbOverride = function(self, event, updUnit)
            if self._euiUnit ~= updUnit then return end

            -- Arm on the dedicated absorb events (plainly observable even
            -- while values are secret). Value-only health chatter is not
            -- delivered to this channel at all (engine list); max changes
            -- repaint ONLY while a shield/heal-absorb is known active --
            -- with no absorb, a range change moves nothing visible.
            -- Repoints, ForceUpdate and the belt always paint and re-derive
            -- the flag below. Mirror of the RF gate.
            if event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
                ns.UF_AbArm(self)
            elseif event == "UNIT_MAXHEALTH" and not self._absActive then
                return
            end

            -- Drive the "Absorb Short" health-text gate(s): feed the raw absorb so the
            -- clip reveals/collapses, AND refresh the text in LOCKSTEP so it never
            -- flashes a stale "0" (oUF tags update on a throttled cycle, lagging the
            -- synchronous clip reveal by a frame). Runs before the bar-style early
            -- return so it works with the absorb BAR disabled. The gate must move on
            -- EVERY update, not only absorb events: volatile units (target/focus/boss/
            -- pet) get re-pointed with no absorb event at all (target switch, OnShow,
            -- ForceUpdate), and a dying unit drops its shield without one either -- the
            -- TAG re-evaluates on those paths and lands on "0", so a gate still held
            -- open by the PREVIOUS unit's shield would leave a stuck "0". Max-health
            -- events skip the text refresh (absorb text only changes on an absorb event,
            -- which does its own lockstep SetText). Secret-safe: absorb only reaches SetValue
            -- and AbbreviateNumbers, never a zero comparison. Each gate feeds its own
            -- source: shield gates use total absorbs, heal gates (g._euiHealGate) total
            -- heal absorbs, fetched lazily once.
            local shieldAmt, healAmt
            if self._absGate then
                local syncText = (event ~= "UNIT_MAXHEALTH")
                local fsZone
                for zone, g in pairs(self._absGate) do
                    if g:IsShown() then
                        local amt
                        if g._euiHealGate then
                            if not healAmt then healAmt = (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(updUnit)) or 0 end
                            amt = healAmt
                        else
                            if not shieldAmt then shieldAmt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(updUnit)) or 0 end
                            amt = shieldAmt
                        end
                        g:SetValue(amt)
                        if syncText then
                            fsZone = fsZone or { left = self.LeftText, right = self.RightText, center = self.CenterText, extra = self.ExtraText }
                            local fs = fsZone[zone]
                            if fs then
                                local cfg = _G._EUI_AbbrevDecimalCfg
                                fs:SetText(cfg and AbbreviateNumbers(amt, cfg) or AbbreviateNumbers(amt))
                            end
                        end
                    end
                end
            end

            local element = self.HealthPrediction
            local ab = element.damageAbsorb
            if not ab then return end
            local fw   = ab._forward
            local hp   = ab._hpBar
            if not hp then return end

            -- Heal absorb renders independently of shield absorb: shield "none" hides
            -- only the shield segments, and the whole update is skipped only when BOTH
            -- are off, so unit events can't re-Show() bars ReloadFrames hid. (Heal
            -- Absorb Style defaults to "clean", so it shows even with shield "none".)
            local s = GetSettingsForUnit(updUnit)
            -- Boss frames have no absorb settings of their own: render with the TARGET
            -- frame's styling (donor convention), behind "Show on Boss Frames" in the
            -- absorb cog (nil = enabled).
            local bossAbsorbOff
            if updUnit and updUnit:match("^boss") then
                bossAbsorbOff = db.profile.boss and db.profile.boss.showAbsorbs == false
                s = db.profile.target or s
            end
            local ha = ab._healAbsorb
            local topBar = ab._topBar
            local healTopBar = ab._healTopBar
            local barPos = ns.UF_GetAbsorbBarPos(s)
            local barOn = topBar and barPos ~= "none"
            local healBarPos = ns.UF_GetHealAbsorbBarPos(s)
            local healBarOn = healTopBar and healBarPos ~= "none"
            local shieldOff = s and (not s.showPlayerAbsorb or s.showPlayerAbsorb == "none")
            local healOff = (((s and s.healAbsorbStyle) or "clean") == "none")
            if bossAbsorbOff or (shieldOff and healOff and not barOn and not healBarOn) then
                ab:Hide()
                if fw then fw:Hide() end
                if ha then ha:Hide() end
                if topBar then topBar:Hide() end
                if healTopBar then healTopBar:Hide() end
                return
            end

            -- Direct pair, matching PaintHealth's scale: the health bar runs raw
            -- UnitHealthMax, and every absorb sink below is a StatusBar with a
            -- (0, maxHealth) range that clamps oversized shields visually, so a
            -- detailed-prediction calculator adds fetches without changing a pixel.
            -- The gate block above may have fetched the shield total already.
            local maxHealth = UnitHealthMax(updUnit) or 0
            local absorbAmt = shieldAmt or (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(updUnit)) or 0

            -- Lean-flag derivation + belt stamp (mirror of Raid Frames): a
            -- fresh PLAIN all-zero read disarms the head gate; secret reads
            -- keep it armed (fail-open to today's always-paint in combat).
            self._absPaintAt = GetTime()
            local haAmtD = healAmt or (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(updUnit)) or 0
            local isSecD = issecretvalue
            if (isSecD and (isSecD(absorbAmt) or isSecD(haAmtD)))
               or (absorbAmt or 0) > 0 or (haAmtD or 0) > 0 then
                if not self._absActive then ns.UF_AbArm(self) end
            else
                ns.UF_AbDisarm(self)
            end

            local hpW, hpH = hp:GetWidth(), hp:GetHeight()
            -- Identical-state short-circuit (RF's memo, ported): chatter
            -- events with unchanged values skip the whole paint below.
            -- Identity/settings paints bypass the skip; any secret input
            -- fails open to painting and poisons the memo for the next plain
            -- pass (exactly the RF contract). The 0.5s belt honors the memo
            -- like RF's does: it exists for the no-event timer expiry, and
            -- that edge reads a CHANGED amount (memo miss) -- the arm/disarm
            -- derivation and the paint stamp above already ran, so a belt
            -- pass over unchanged plain values has nothing left to move.
            if isSecD and (isSecD(absorbAmt) or isSecD(maxHealth) or isSecD(haAmtD)) then
                ab._mAbs = nil
            elseif event ~= "ForceUpdate" and event ~= "Resettle"
               and ab._mAbs == absorbAmt and ab._mHeal == haAmtD
               and ab._mMax == maxHealth and ab._mW == hpW and ab._mH == hpH then
                return
            else
                ab._mAbs, ab._mHeal, ab._mMax = absorbAmt, haAmtD, maxHealth
                ab._mW, ab._mH = hpW, hpH
            end
            -- Bars track the health-bar size; size-gated (sizes never secret).
            if ab._szW ~= hpW or ab._szH ~= hpH then
                ab._szW = hpW; ab._szH = hpH
                ab:SetWidth(hpW); ab:SetHeight(hpH)
                if fw then fw:SetWidth(hpW); fw:SetHeight(hpH) end
            end

            -- Strip bars (mirrors Raid Frames): independent of the overlay styles.
            if topBar then
                if barOn then
                    local bc = (s and s.absorbBarColor) or { r = 1, g = 1, b = 1 }
                    local bh = (s and s.absorbBarHeight) or 4
                    -- Re-layout only on position/height change (no SetPoint churn).
                    if topBar._lpPos ~= barPos or topBar._lpH ~= bh then
                        topBar._lpPos = barPos; topBar._lpH = bh
                        ns.UF_ApplyStripBarLayout(topBar, hp, barPos, bh, ab:GetFrameLevel())
                    end
                    topBar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a or 1)
                    topBar:SetMinMaxValues(0, maxHealth)
                    topBar:SetValue(absorbAmt)
                    topBar:Show()
                else
                    topBar:Hide()
                end
            end
            if healTopBar then
                if healBarOn then
                    local hbc = (s and s.healAbsorbBarColor) or { r = 200/255, g = 29/255, b = 29/255 }
                    local hbh = (s and s.healAbsorbBarHeight) or 4
                    local abh = (s and s.absorbBarHeight) or 4
                    -- Re-layout only when its or the Absorb Bar's position/height changes.
                    if healTopBar._lpPos ~= healBarPos or healTopBar._lpH ~= hbh
                       or healTopBar._lpAP ~= barPos or healTopBar._lpAH ~= abh then
                        healTopBar._lpPos = healBarPos; healTopBar._lpH = hbh
                        healTopBar._lpAP = barPos; healTopBar._lpAH = abh
                        ns.UF_ApplyStripBarLayout(healTopBar, hp, healBarPos, hbh, ab:GetFrameLevel(), barPos, abh)
                    end
                    healTopBar:SetStatusBarColor(hbc.r, hbc.g, hbc.b, hbc.a or 1)
                    healTopBar:SetMinMaxValues(0, maxHealth)
                    healTopBar:SetValue(haAmtD)
                    healTopBar:Show()
                else
                    healTopBar:Hide()
                end
            end

            -- Re-anchor when placement settings change. Key starts nil, so this also
            -- applies the saved placement on the first update. Fill AXIS belongs in the
            -- key too: the settings-apply path already re-anchors on a Vertical Fill
            -- toggle, but this keeps it self-healing if the axis changes another way.
            local absorbMode = (s and s.absorbEdgeMode) or "overlay"
            -- Overshield mode (three-way; nil falls back to the legacy
            -- showOvershield boolean). Joins the edge key: "fromleft"
            -- re-anchors the backfill in UpdateAbsorbBarReverseFill.
            local osMode = s and s.overshieldMode
            if osMode == nil then osMode = (s and s.showOvershield == false) and "never" or "always" end
            -- Component compares instead of a concatenated key: same change
            -- detection, zero string allocation on the per-event path. Fields
            -- start nil, so the first update always anchors.
            local healEdgeMode = (s and s.healAbsorbEdgeMode) or "overlay"
            local vertFill = (s and s.healthVerticalFill) and true or false
            if ab._ekAbs ~= absorbMode or ab._ekHeal ~= healEdgeMode
               or ab._ekVert ~= vertFill or ab._ekOs ~= osMode then
                ab._ekAbs, ab._ekHeal = absorbMode, healEdgeMode
                ab._ekVert, ab._ekOs = vertFill, osMode
                UpdateAbsorbBarReverseFill(self, ab._isReversed)
            end

            -- Shield (damage) absorb segments render only when enabled; style
            -- "none" hides them and falls through to the independent heal absorb.
            if shieldOff then
                ab:Hide()
                if fw then fw:Hide() end
            else
                -- Re-apply the absorb style only when the setting changes, never on
                -- every health event: SetStatusBarTexture per update flashes the
                -- bar visible even at zero absorb. Opacity/color edits re-apply via
                -- ReloadFrames' direct call.
                local absStyle = s and s.showPlayerAbsorb
                if absStyle and absStyle ~= "none" and ab._lastAbsStyle ~= absStyle then
                    ab._lastAbsStyle = absStyle
                    ApplyAbsorbStyle(ab, absStyle, s)
                end

                -- Show Overshield (three-way, resolved above as osMode):
                -- "never" (overlay mode only) feeds backfill 0 so only empty
                -- health fills, while the forward bar still caps at the right
                -- edge; "always"/"fromleft" draw the excess (placement decided
                -- by the anchor pass). Right/left edge modes draw the WHOLE
                -- absorb through ab (fw hidden below) and are untouched.
                local abValue = absorbAmt
                if osMode == "never" and absorbMode == "overlay" then abValue = 0 end

                -- Both bars get the raw absorb value and the normal maxHealth; the clip
                -- frames do "min(absorb,curHealth)" and "max(0,absorb-curHealth)"
                -- visually, so no Lua arithmetic touches the (possibly secret) absorb.
                ab:SetMinMaxValues(0, maxHealth)
                ab:SetValue(abValue)
                ab:Show()

                if fw then
                    fw:SetMinMaxValues(0, maxHealth)
                    fw:SetValue(absorbAmt)
                    fw:Show()
                    -- Edge modes and Overlay Reverse: the backfill shows the
                    -- absorb, so the forward bar is not needed (Overlay Reverse
                    -- (Full) draws its excess through it).
                    if absorbMode ~= "overlay" and absorbMode ~= "overlayReverseFull" then fw:Hide() end
                end
                -- Blizzard Glow Line (opt-in; see ns.UF_AbsorbGlowApply).
                if ab._glowOn then ns.UF_PaintAbsorbGlow(ab, updUnit, absorbAmt, hpH) end
            end

            -- Heal absorb: overlay eating into filled health. The value can be a secret
            -- number in 12.0+, so never compare it in Lua. Feed it directly to
            -- StatusBar:SetValue and let the bar render zero width when the value is 0.
            if ha then
                local haStyle = (s and s.healAbsorbStyle) or "clean"
                if haStyle == "none" then
                    ha:Hide()
                else
                    local hc = (s and s.healAbsorbColor) or { r = 0.8, g = 0.15, b = 0.15 }
                    local hcR, hcG, hcB = hc.r or 0.8, hc.g or 0.15, hc.b or 0.15
                    local haKey = haStyle .. ((s and s.healAbsorbOpacity) or 65) .. hcR .. hcG .. hcB
                    if ha._lastHaKey ~= haKey then
                        ha._lastHaKey = haKey
                        ApplyHealAbsorbStyle(ha, haStyle, s)
                    end
                    local healAbsorbAmt = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(updUnit) or 0
                    ha:SetWidth(hpW); ha:SetHeight(hpH)
                    ha:SetMinMaxValues(0, maxHealth)
                    ha:SetValue(healAbsorbAmt)
                    ha:Show()
                    -- Black backing tracks the fill rect; opacity from settings.
                    local hbg = ha._bg
                    if hbg then
                        hbg:SetColorTexture(0, 0, 0, ((s and s.healAbsorbBgOpacity) or 15) / 100)
                        hbg:SetAllPoints(ha:GetStatusBarTexture())
                        hbg:Show()
                    end
                end
            end
    end
    frame.HealthPrediction = {
        damageAbsorb = backfillBar,
        Override = UF_AbsorbOverride,
    }

    -- The anchors above are the horizontal layout; hand the cluster to the shared
    -- re-anchor pass so a vertical-fill frame starts correct without waiting for
    -- the first settings apply. `settings` is passed through because frame._euiUnit is
    -- not resolvable this early on every frame.
    UpdateAbsorbBarReverseFill(frame, isReversed, settings)

    return backfillBar
end

I.ApplyAbsorbStyle, I.UpdateAbsorbBarReverseFill = ApplyAbsorbStyle, UpdateAbsorbBarReverseFill
I.CreateAbsorbBar = CreateAbsorbBar
