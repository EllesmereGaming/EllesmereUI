if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Absorb.lua
--
--  Absorb styles, the absorb, heal absorb and heal prediction bars, their
--  position and UpdateAbsorb.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local UnitHealthMax         = UnitHealthMax
local UnitGetTotalAbsorbs   = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local issecretvalue         = issecretvalue
local CreateFrame           = CreateFrame

local ABSORB_STYLE_ALPHA, ABSORB_STYLE_TEX = I.ABSORB_STYLE_ALPHA, I.ABSORB_STYLE_TEX
local GetFFD, PixelSnap = I.GetFFD, I.PixelSnap

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-------------------------------------------------------------------------------
--  Absorb style application. Single-fill styles match the unit-frame look; the
--  RF-only compound "Blizzard (Modern)" style layers a tiled stripe fill over a
--  solid base, diverging from UnitFrames (which offers only "Blizzard").
-------------------------------------------------------------------------------

-- Configure ONE absorb StatusBar for the compound "Blizzard (Modern)" style: tiled 9196ff striped
-- fill over an opaque c6c8ff base (._modernBase, colored once at creation). Re-establishes the
-- striped fill (the bar's fill is shared with other styles, so it must be restored) and anchors the
-- base to the fill rect so it rides the clip/mask geometry the secret SetValue drives -- no Lua
-- math on the secret. Colors hardcoded; ignores user color/opacity.
ns.ApplyModernAbsorbBar = function(bar, mask)
    if not bar then return end
    bar:SetStatusBarTexture(ABSORB_STYLE_TEX.striped)
    bar:SetStatusBarColor(0.569, 0.588, 1.0, 1)
    local fill = bar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 1)
        fill:SetHorizTile(true)
        fill:SetVertTile(true)
        if mask then fill:AddMaskTexture(mask) end
        local base = bar._modernBase
        if base then base:SetAllPoints(fill); base:Show() end
    end
    ns.RF_ApplyFillRotation(bar)  -- tiled: stays unrotated on a vertical bar
end

-- Hide the modern solid base on any non-modern style, so switching away leaves no stale layer.
ns.HideModernAbsorbBase = function(bar)
    if bar and bar._modernBase then bar._modernBase:Hide() end
end

local function ApplyAbsorbStyle(absorbBar, style, settings)
    if not absorbBar then return end
    local mask = absorbBar._absorbMask
    local fw = absorbBar._forward

    -- "Default Blizz Frames": forward (missing-health shield) = compound modern texture;
    -- backfill (overshield over existing health) = flat 10% white overlay, not the texture.
    if style == "blizzardModern" then
        if fw then ns.ApplyModernAbsorbBar(fw, mask) end
        ns.HideModernAbsorbBase(absorbBar)
        absorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        absorbBar:SetStatusBarColor(1, 1, 1, 0.10)
        local bfFill = absorbBar:GetStatusBarTexture()
        if bfFill then
            bfFill:SetDrawLayer("ARTWORK", 1)
            bfFill:SetHorizTile(false); bfFill:SetVertTile(false)
            if mask then bfFill:AddMaskTexture(mask) end
        end
        return
    end

    -- Every other style is a single fill texture; ensure the modern base is off.
    ns.HideModernAbsorbBase(absorbBar)
    if fw then ns.HideModernAbsorbBase(fw) end

    local tex = ns.ResolveAbsorbStyleTex(style, "Interface\\Buttons\\WHITE8X8")
    local alpha = settings and (settings.absorbOpacity or 90) / 100 or (ABSORB_STYLE_ALPHA[style] or 0.8)
    local ac = settings and settings.absorbColor or { r = 1, g = 1, b = 1 }
    absorbBar:SetStatusBarTexture(tex)
    absorbBar:SetStatusBarColor(ac.r or 1, ac.g or 1, ac.b or 1, alpha)
    local tiled = (style == "striped" or style == "stripedReversed" or style == "stripedThick" or style == "stripedThickR" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" or style == "pixelsShieldFill")
    local fill = absorbBar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 1)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
        if mask then fill:AddMaskTexture(mask) end
    end
    -- New fill object + new tiling state: re-derive rotation.
    ns.RF_ApplyFillRotation(absorbBar)
    if fw then
        fw:SetStatusBarTexture(tex)
        fw:SetStatusBarColor(ac.r or 1, ac.g or 1, ac.b or 1, alpha)
        local fwFill = fw:GetStatusBarTexture()
        if fwFill then
            fwFill:SetDrawLayer("ARTWORK", 1)
            fwFill:SetHorizTile(tiled)
            fwFill:SetVertTile(tiled)
            if mask then fwFill:AddMaskTexture(mask) end
        end
        ns.RF_ApplyFillRotation(fw)
    end
end

ns.ApplyHealAbsorbStyle = function(haBar, style, settings)
    if not haBar then return end
    local tex = ns.ResolveAbsorbStyleTex(style, "Interface\\Buttons\\WHITE8X8")
    local alpha = settings and (settings.healAbsorbOpacity or 75) / 100 or 0.65
    local hc = settings and settings.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
    -- "Default Blizz Frames" / "Large Outlined Stripes" heal styles are pre-colored: forced white tint (swatch disabled).
    if style == "healBlizzModern" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" then hc = { r = 1, g = 1, b = 1 } end
    local mask = haBar._absorbMask
    haBar:SetStatusBarTexture(tex)
    haBar:SetStatusBarColor(hc.r or 0.8, hc.g or 0.15, hc.b or 0.15, alpha)
    local tiled = (style == "striped" or style == "stripedReversed" or style == "stripedThick" or style == "stripedThickR" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" or style == "pixelsShieldFill")
    local fill = haBar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 2)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
        if mask then fill:AddMaskTexture(mask) end
    end
    ns.RF_ApplyFillRotation(haBar)
end

-- Reduced max-health overlay style: the heal-absorb texture set plus a dedicated "Max Health
-- Stripes" texture; always right-anchored (caller sets ReverseFill). Swatch tints, slider =
-- texture opacity (backing opacity is the caller's). Pre-colored styles force white.
ns.ApplyMaxHealthStyle = function(bar, style, settings)
    if not bar then return end
    style = style or "maxHealthStripes"
    local tex, tiled
    if style == "maxHealthStripes" then
        tex = "Interface\\AddOns\\EllesmereUIRaidFrames\\Media\\striped-maxhp.png"
        tiled = true
    else
        tex = ns.ResolveAbsorbStyleTex(style, "Interface\\Buttons\\WHITE8X8")
        tiled = (style == "striped" or style == "stripedReversed" or style == "stripedThick" or style == "stripedThickR" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" or style == "pixelsShieldFill")
    end
    local alpha = settings and (settings.maxHealthOpacity or 100) / 100 or 1
    local mc = settings and settings.maxHealthColor or { r = 0.7, g = 0.1, b = 0.1 }
    if style == "healBlizzModern" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" then mc = { r = 1, g = 1, b = 1 } end
    bar:SetStatusBarTexture(tex)
    bar:SetStatusBarColor(mc.r or 0.7, mc.g or 0.1, mc.b or 0.1, alpha)
    local fill = bar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 3)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
    end
    ns.RF_ApplyFillRotation(bar)
end

-------------------------------------------------------------------------------
--  Create absorb bar (dual clip-frame, secret-value safe). Matches UnitFrames
--  exactly. Clip frames do "min(absorb, curHealth)" and "max(0, absorb -
--  curHealth)" visually, so no Lua arithmetic on secret values.
-------------------------------------------------------------------------------
local function CreateAbsorbBar(button, healthBar)
    if not healthBar then return end
    local d = GetFFD(button)

    -- Mask texture: constrains absorb rendering to exact health bar bounds
    local absorbMask = healthBar:CreateMaskTexture()
    absorbMask:SetAllPoints(healthBar)
    absorbMask:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Current HP clip: bounds the backfill bar to the filled health area
    local curClip = CreateFrame("Frame", nil, healthBar)
    curClip:SetClipsChildren(true)

    -- Missing HP clip: bounds the forward bar to the empty health area
    local missClip = CreateFrame("Frame", nil, healthBar)
    missClip:SetClipsChildren(true)

    -- Filled-region bound for the backfill, as a MASK shadowing curClip's rect
    -- instead of scissor clipping: in restricted content the clip frame's
    -- secret-anchored scissor stops rendering its children entirely (bisect
    -- strips: a plain bar under curClip died while a masked twin on the health
    -- bar rendered), which is why the overshield vanished whenever a
    -- dispellable debuff -- restricted content's signature -- was up. The mask
    -- tracks curClip through every ReanchorAbsorbToFill re-anchor for free.
    -- CLAMPTOBLACKADDITIVE is what makes the mask a BOUND: the default wrap
    -- extends the white edge pixels past the mask's rect, so the backfill
    -- rendered unmasked over missing health (doubled onto the forward bar).
    -- NEAREST because WHITE8X8 is 8x8: stretched over the rect, bilinear blends
    -- the edge texel with the black border across the outer 1/16 of each side,
    -- and that alpha ramp read as a shadow along the overshield's edges.
    local curMask = healthBar:CreateMaskTexture()
    curMask:SetAllPoints(curClip)
    curMask:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")

    -- Backfill bar (overflow): grows into filled health from the right edge.
    -- Child of the HEALTH BAR, not curClip -- the filled-region bound rides
    -- curMask above (the scissor path is dead in restricted content).
    local backfillBar = CreateFrame("StatusBar", nil, healthBar)
    backfillBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local bfFill = backfillBar:GetStatusBarTexture()
    if bfFill then bfFill:SetDrawLayer("ARTWORK", 1); bfFill:AddMaskTexture(absorbMask); bfFill:AddMaskTexture(curMask) end
    -- Compound "Blizzard (Modern)" solid base (c6c8ff): BEHIND the striped fill (ARTWORK sublevel
    -- 0 < fill 1). Masked once here; shown only for that style, re-anchored to the fill each update.
    local bfBase = backfillBar:CreateTexture(nil, "ARTWORK", nil, 0)
    bfBase:SetColorTexture(0.776, 0.784, 1.0, 1)
    if absorbMask then bfBase:AddMaskTexture(absorbMask) end
    bfBase:AddMaskTexture(curMask)
    bfBase:Hide()
    backfillBar._modernBase = bfBase
    backfillBar:SetStatusBarColor(1, 1, 1, 0.8)
    backfillBar:SetReverseFill(true)
    backfillBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
    backfillBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    backfillBar:SetWidth(healthBar:GetWidth())
    backfillBar:SetHeight(healthBar:GetHeight())
    -- Absorb tops the HP cluster: above heal absorb/prediction (healthBar+1) and reduced max health (+2).
    backfillBar:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    backfillBar:Hide()

    -- Forward bar (primary): grows into missing health from the HP edge
    local forwardBar = CreateFrame("StatusBar", nil, missClip)
    forwardBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local fwFill = forwardBar:GetStatusBarTexture()
    if fwFill then fwFill:SetDrawLayer("ARTWORK", 1); fwFill:AddMaskTexture(absorbMask) end
    -- Modern solid base (c6c8ff) for the forward bar (see backfill above).
    local fwBase = forwardBar:CreateTexture(nil, "ARTWORK", nil, 0)
    fwBase:SetColorTexture(0.776, 0.784, 1.0, 1)
    if absorbMask then fwBase:AddMaskTexture(absorbMask) end
    fwBase:Hide()
    forwardBar._modernBase = fwBase
    forwardBar:SetStatusBarColor(1, 1, 1, 0.8)
    forwardBar:SetReverseFill(false)
    forwardBar:SetWidth(healthBar:GetWidth())
    forwardBar:SetHeight(healthBar:GetHeight())
    -- Match backfill: absorb renders above heal absorb/heal prediction and max health.
    forwardBar:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    forwardBar:Hide()

    -- Blizzard Glow Line (Default Blizz Frames' spark, any style when on): fixed 16px soft glow
    -- (cast_spark.tga, ADD) centered on the shield's edge next to current health, half over
    -- health, half over shield. Its own host above the shield keeps the health-side half out of
    -- missClip. Created on the forward bar's LEFT edge (the current-HP seam); UpdateAbsorb
    -- re-points it per placement. A StatusBar fed the absorb with a tiny max fills 100% on ANY
    -- shield -- self-gates off the secret absorb, no boolean/mask.
    local sparkHost = CreateFrame("Frame", nil, healthBar)
    sparkHost:SetAllPoints(healthBar)
    sparkHost:SetClipsChildren(true)
    sparkHost:SetFrameLevel(healthBar:GetFrameLevel() + 4)
    -- Invisible gate bar (16px on the seam): binary fill -- full with ANY shield, zero with none. Only its fill GEOMETRY is used.
    local gateBar = CreateFrame("StatusBar", nil, sparkHost)
    gateBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    gateBar:SetStatusBarColor(1, 1, 1, 0)
    gateBar:SetSize(16, healthBar:GetHeight())
    gateBar:SetMinMaxValues(0, 1)
    gateBar:SetValue(0)
    gateBar:SetPoint("CENTER", forwardBar, "LEFT", -1, 0)
    -- Visible spark over the gate's fill rect (cast_spark.tga renders as a plain texture but not as a StatusBar fill, hence the split).
    local edgeSpark = sparkHost:CreateTexture(nil, "OVERLAY")
    edgeSpark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    edgeSpark:SetBlendMode("ADD")
    edgeSpark:SetAllPoints(gateBar:GetStatusBarTexture())
    edgeSpark:Hide()
    forwardBar._edgeSpark = edgeSpark
    forwardBar._edgeGate = gateBar
    -- Overshield spark: rides the overshield's edge next to current health while overshielding
    -- (the backfill's LEFT edge; its RIGHT edge with From Left). Anchored by UpdateAbsorb.
    local bfSpark = sparkHost:CreateTexture(nil, "OVERLAY")
    bfSpark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    bfSpark:SetBlendMode("ADD")
    bfSpark:SetSize(16, healthBar:GetHeight())
    bfSpark:SetPoint("CENTER", forwardBar, "LEFT", -1, 0)
    bfSpark:Hide()
    forwardBar._bfSpark = bfSpark

    -- Absorb Bar: solid bar above the frame showing the shield amount, filling from the right edge.
    -- Always created hidden so toggling it on later needs no rebuild; UpdateAbsorb drives it.
    local topBar = CreateFrame("StatusBar", nil, button)
    topBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    topBar:SetStatusBarColor(1, 1, 1, 1)
    topBar:SetReverseFill(true)
    topBar:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 0)
    topBar:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 0)
    topBar:SetHeight(4)
    topBar:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    topBar:Hide()

    -- Heal Absorb Bar: second strip mirroring the Absorb Bar. Always created hidden; UpdateAbsorb drives it.
    local healTopBar = CreateFrame("StatusBar", nil, button)
    healTopBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    healTopBar:SetStatusBarColor(200/255, 29/255, 29/255, 1)
    healTopBar:SetReverseFill(true)
    healTopBar:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 0)
    healTopBar:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 0)
    healTopBar:SetHeight(4)
    healTopBar:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    healTopBar:Hide()

    -- Forward-declared so ReanchorAbsorbToFill captures these as UPVALUES: an undeclared name in
    -- the closure resolves to a nil global and the bar silently never re-anchors. The bars are
    -- created further down, before the first call (at the end of this function), so every
    -- button's first pass anchors them too, including buttons built mid-session.
    local healAbsorbBar, healPredBar, healClip, reducedBar

    -- Re-anchor clip frames and forward bar to the current health fill texture.
    -- Must be called whenever SetStatusBarTexture replaces the fill object.
    local function ReanchorAbsorbToFill()
        local fill = healthBar:GetStatusBarTexture()

        -- Vertical fill: the whole HP cluster rotates with the health bar -- every anchor below is
        -- the horizontal layout axis-swapped (the fill's RIGHT "HP edge" that shields/heal
        -- absorb/prediction hang off becomes its TOP edge; frame right/left become top/bottom).
        -- Resolved live off the button's settings source so party keeps its own Health Bar section.
        -- Inverted fill: the seam (the current-HP point) sits at the same coordinate
        -- either way -- only which side of it the fill texture paints changes. So the
        -- "HP edge" the cluster hangs off moves from the fill's RIGHT/TOP to its
        -- LEFT/BOTTOM and every anchor on it flips; anchors on the health FRAME's edges
        -- are unaffected and are deliberately left alone below.
        local vs = d._isParty and ns._scaledPartyProxy
            or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
        local isVert, isInvert = ns.RF_ApplyHealthOrientation(healthBar, vs)
        backfillBar._axisVert = isVert  -- read by the Blizzard Glow Line (hidden on a vertical fill)
        -- The fill's two HP-edge corners: every fill anchor below is on one of these.
        local hpA, hpB = ns.RF_HpEdge(isVert, isInvert)
        -- Overlay Reverse (Full): Overlay Reverse, plus the forward bar filling from the bar's
        -- ORIGIN edge (left; bottom when vertical -- frame edges, so Inverted Fill leaves them
        -- alone), so missClip shows the absorb exceeding current health past the seam instead
        -- of losing it. Its clip starts exactly at the seam: the 1px seal into the fill would
        -- double that pixel over the backfill. Default Blizz Frames keeps Overlay Reverse.
        local orFull = db.profile.absorbEdgeMode == "overlayReverseFull"
            and db.profile.absorbStyle ~= "blizzardModern"

        -- Health Bar Color overlays track this bar's fill, so they follow the swap
        -- for the same reason the absorb cluster below does. After the orientation
        -- call, not before: the repaint copies the fill's tex coords, and that call
        -- is what rotates them.
        healthBar._euiFillOpacity = (vs.healthBarOpacity or 100) / 100
        ns.RF_RefreshBarTints(healthBar)
        -- Indexed, not ipairs: a nil entry must not end the walk early.
        local axisBars = { backfillBar, forwardBar, healAbsorbBar, healPredBar, reducedBar }
        for i = 1, 5 do
            local b = axisBars[i]
            if b then
                b:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
                ns.RF_ApplyFillRotation(b)  -- derived: rotate stretch styles only
            end
        end

        if isVert then
            curClip:ClearAllPoints()
            curClip:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
            curClip:SetPoint("TOPRIGHT", fill, hpB, 0, 0)
            missClip:ClearAllPoints()
            missClip:SetPoint("BOTTOMLEFT", fill, hpA, 0, orFull and 0 or -1)
            missClip:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            forwardBar:ClearAllPoints()
            if orFull then
                forwardBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                forwardBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            else
                forwardBar:SetPoint("BOTTOMLEFT", fill, hpA, 0, 0)
                forwardBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
            end
            if healPredBar then
                healPredBar:ClearAllPoints()
                healPredBar:SetPoint("BOTTOMLEFT", fill, hpA, 0, 0)
                healPredBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
            end
            -- Edge modes keep their key names: "right" = the far edge of the fill axis (top when vertical), "left" = the near one (bottom).
            local vAbsorbMode = db.profile.absorbEdgeMode or "overlay"
            backfillBar:ClearAllPoints()
            if vAbsorbMode == "right" or vAbsorbMode == "left" then
                curClip:ClearAllPoints()
                curClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                curClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
                if vAbsorbMode == "left" then
                    backfillBar:SetReverseFill(false)
                    backfillBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                    backfillBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
                else
                    backfillBar:SetReverseFill(true)
                    backfillBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                    backfillBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                end
            elseif vAbsorbMode == "overlayReverse" or vAbsorbMode == "overlayReverseFull" then
                -- Overlay Reverse, vertical axis: whole absorb fills DOWN into the fill from
                -- its top edge (UP from its bottom edge under Inverted Fill); default
                -- filled-region clip masks any excess (see the horizontal branch; Full draws
                -- it through the forward bar).
                backfillBar:SetReverseFill(true)
                backfillBar:SetPoint("TOPLEFT", fill, hpA, 0, 0)
                backfillBar:SetPoint("TOPRIGHT", fill, hpB, 0, 0)
            else
                -- Overshield "From Left" on the vertical axis: excess grows
                -- from the bar's bottom (origin) edge -- see the horizontal
                -- branch for the anchor mechanics.
                local osm = db.profile.overshieldMode
                if osm == nil then osm = (db.profile.showOvershield == false) and "never" or "always" end
                if osm == "fromleft" and db.profile.absorbStyle ~= "blizzardModern" then
                    backfillBar:SetReverseFill(false)
                    backfillBar:SetPoint("TOPLEFT", fill, hpA, 0, 0)
                    backfillBar:SetPoint("TOPRIGHT", fill, hpB, 0, 0)
                else
                    backfillBar:SetReverseFill(true)
                    backfillBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                    backfillBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                end
            end

            if healAbsorbBar then
                local vHealMode = db.profile.healAbsorbEdgeMode or "overlay"
                if healClip then
                    healClip:ClearAllPoints()
                    if vHealMode == "right" or vHealMode == "left" then
                        healClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                        healClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
                    else
                        healClip:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                        healClip:SetPoint("TOPRIGHT", fill, hpB, 0, 0)
                    end
                end
                healAbsorbBar:ClearAllPoints()
                if vHealMode == "right" then
                    healAbsorbBar:SetReverseFill(true)
                    healAbsorbBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                    healAbsorbBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                elseif vHealMode == "left" then
                    healAbsorbBar:SetReverseFill(false)
                    healAbsorbBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                    healAbsorbBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
                else
                    healAbsorbBar:SetReverseFill(true)
                    healAbsorbBar:SetPoint("TOPLEFT", fill, hpA, 0, 0)
                    healAbsorbBar:SetPoint("TOPRIGHT", fill, hpB, 0, 0)
                end
            end
            return
        end

        curClip:ClearAllPoints()
        curClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        curClip:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
        missClip:ClearAllPoints()
        missClip:SetPoint("TOPLEFT", fill, hpA, orFull and 0 or -1, 0)
        missClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        forwardBar:ClearAllPoints()
        if orFull then
            forwardBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            forwardBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
        else
            forwardBar:SetPoint("TOPLEFT", fill, hpA, 0, 0)
            forwardBar:SetPoint("BOTTOMLEFT", fill, hpB, 0, 0)
        end
        if healPredBar then
            healPredBar:ClearAllPoints()
            healPredBar:SetPoint("TOPLEFT", fill, hpA, 0, 0)
            healPredBar:SetPoint("BOTTOMLEFT", fill, hpB, 0, 0)
        end
        -- Shield absorb placement (independent of heal absorb): overlay = backfill into filled
        -- health from the HP edge (default); right/left = full bar filling from that frame edge.
        local absorbMode = db.profile.absorbEdgeMode or "overlay"
        if absorbMode == "right" or absorbMode == "left" then
            curClip:ClearAllPoints()
            curClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            curClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            backfillBar:ClearAllPoints()
            if absorbMode == "left" then
                backfillBar:SetReverseFill(false)
                backfillBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                backfillBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
            else
                backfillBar:SetReverseFill(true)
                backfillBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                backfillBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            end
        elseif absorbMode == "overlayReverse" or absorbMode == "overlayReverseFull" then
            -- Overlay Reverse: the WHOLE absorb backfills from the health
            -- fill's leading edge INTO the fill. curClip keeps the default
            -- filled-region clip from above, so a shield larger than current
            -- health is masked at the frame edge -- nothing ever renders over
            -- missing health (the forward bar is hidden by the value pass,
            -- same as the edge modes). Full shows that excess through the
            -- origin-edge forward bar instead.
            backfillBar:SetReverseFill(true)
            backfillBar:ClearAllPoints()
            backfillBar:SetPoint("TOPRIGHT", fill, hpA, 0, 0)
            backfillBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
        else
            -- Overlay: curClip already clipped to the fill above. Overshield "From Left" uses the
            -- Overlay Reverse anchors with FORWARD fill: the bar's origin end sits one bar-width
            -- left of the fill edge, so exactly the excess past missing health emerges from the
            -- frame's left edge (the clip masks the rest). Default = right-anchored reverse fill
            -- (excess hangs left off the fill edge). Default Blizz Frames keeps the classic
            -- backfill -- its overshield spark machinery rides those anchors.
            local osm = db.profile.overshieldMode
            if osm == nil then osm = (db.profile.showOvershield == false) and "never" or "always" end
            backfillBar:ClearAllPoints()
            if osm == "fromleft" and db.profile.absorbStyle ~= "blizzardModern" then
                backfillBar:SetReverseFill(false)
                backfillBar:SetPoint("TOPRIGHT", fill, hpA, 0, 0)
                backfillBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
            else
                backfillBar:SetReverseFill(true)
                backfillBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                backfillBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            end
        end

        -- Heal absorb placement (independent of shield absorb). Its own clip frame spans the full bar for right/left, filled health for overlay.
        if healAbsorbBar then
            local healMode = db.profile.healAbsorbEdgeMode or "overlay"
            if healClip then
                healClip:ClearAllPoints()
                if healMode == "right" or healMode == "left" then
                    healClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                    healClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
                else
                    healClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                    healClip:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
                end
            end
            healAbsorbBar:ClearAllPoints()
            if healMode == "right" then
                healAbsorbBar:SetReverseFill(true)
                healAbsorbBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                healAbsorbBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            elseif healMode == "left" then
                healAbsorbBar:SetReverseFill(false)
                healAbsorbBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                healAbsorbBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
            else
                -- Overlay (default): eat into the filled health from the HP edge.
                healAbsorbBar:SetReverseFill(true)
                healAbsorbBar:SetPoint("TOPRIGHT", fill, hpA, 0, 0)
                healAbsorbBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
            end
        end
    end

    -- Per-button calculator for reading absorb value (secret-safe)
    local hpCalc
    if CreateUnitHealPredictionCalculator then
        hpCalc = CreateUnitHealPredictionCalculator()
        if hpCalc.SetMaximumHealthMode then
            -- Configured ONCE: modes persist on the calculator across fills, and
            -- UpdateAbsorb reads the Default (base) maximum every paint.
            hpCalc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
            -- Missing Health clamp: GetDamageAbsorbs' 2nd return is then the standard "overshield"
            -- boolean (absorb exceeds empty health), consistent in and out of combat. Bars get the
            -- FULL absorb (UnitGetTotalAbsorbs) so overflow/backfill still renders.
            hpCalc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)
        end
    end

    -- Heal absorb has its OWN clip frame (not the shield's curClip) so its placement is
    -- independent: overlay clips to filled health, right/left span the FULL bar (filled +
    -- missing). Bounds set per healAbsorbEdgeMode in ReanchorAbsorbToFill (initial = overlay).
    healClip = CreateFrame("Frame", nil, healthBar)
    healClip:SetClipsChildren(true)
    healClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
    healClip:SetPoint("BOTTOMRIGHT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    -- Heal absorb bar: red overlay eating into filled health
    healAbsorbBar = CreateFrame("StatusBar", nil, healClip)
    healAbsorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    healAbsorbBar._absorbMask = absorbMask
    local haFill = healAbsorbBar:GetStatusBarTexture()
    if haFill then haFill:SetDrawLayer("ARTWORK", 2); haFill:AddMaskTexture(absorbMask) end
    healAbsorbBar:SetStatusBarColor(0.8, 0.15, 0.15, 0.65)
    healAbsorbBar:SetReverseFill(true)
    healAbsorbBar:SetPoint("TOPRIGHT", healthBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    healAbsorbBar:SetPoint("BOTTOMRIGHT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    healAbsorbBar:SetWidth(healthBar:GetWidth())
    healAbsorbBar:SetHeight(healthBar:GetHeight())
    healAbsorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    healAbsorbBar._lastOverDispel = false  -- "Show Over Dispels" applied state; off = created level
    healAbsorbBar:Hide()

    -- Black backing behind the heal-absorb texture (all styles; opacity = healAbsorbBgOpacity).
    -- UNDER the fill (ARTWORK sublevel 1 < the fill's 2), masked + SetAllPoints'd to the fill rect
    -- each update so it tracks the secret heal-absorb amount and collapses to nothing at zero.
    local haBg = healAbsorbBar:CreateTexture(nil, "ARTWORK", nil, 1)
    haBg:SetColorTexture(0, 0, 0, 0.25)
    if absorbMask then haBg:AddMaskTexture(absorbMask) end
    haBg:Hide()
    healAbsorbBar._bg = haBg

    -- Heal prediction bar: extends from current HP edge into missing health
    healPredBar = CreateFrame("StatusBar", nil, missClip)
    healPredBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local hpFill = healPredBar:GetStatusBarTexture()
    if hpFill then hpFill:SetDrawLayer("ARTWORK", 2); hpFill:AddMaskTexture(absorbMask) end
    healPredBar:SetStatusBarColor(0.3, 0.8, 0.3, 0.4)
    healPredBar:SetReverseFill(false)
    healPredBar:SetPoint("TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    healPredBar:SetPoint("BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    healPredBar:SetWidth(healthBar:GetWidth())
    healPredBar:SetHeight(healthBar:GetHeight())
    healPredBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    healPredBar:Hide()

    -- Reduced max health bar: black bg + red striped overlay on the right side (forward-declared above for ReanchorAbsorbToFill).
    reducedBar = CreateFrame("StatusBar", nil, healthBar)
    reducedBar:SetStatusBarTexture("Interface\\AddOns\\EllesmereUIRaidFrames\\Media\\striped-maxhp.png")
    local rmhFill = reducedBar:GetStatusBarTexture()
    if rmhFill then
        rmhFill:SetDrawLayer("ARTWORK", 3)
        rmhFill:SetHorizTile(true); rmhFill:SetVertTile(true)
    end
    reducedBar:SetStatusBarColor(0.7, 0.1, 0.1, 1)
    reducedBar:SetReverseFill(true)
    reducedBar:SetAllPoints(healthBar)
    reducedBar:SetFrameLevel(healthBar:GetFrameLevel() + 2)
    reducedBar:SetMinMaxValues(0, 1)
    reducedBar:Hide()
    local rmhBg = reducedBar:CreateTexture(nil, "ARTWORK", nil, 2)
    rmhBg:SetColorTexture(0, 0, 0, 1)

    -- Store references in FFD (never on the Blizzard-owned button)
    backfillBar._forward      = forwardBar
    backfillBar._topBar       = topBar
    backfillBar._healTopBar   = healTopBar
    backfillBar._healAbsorb   = healAbsorbBar
    backfillBar._healPred     = healPredBar
    backfillBar._reducedMax   = reducedBar
    backfillBar._reducedMaxBg = rmhBg
    backfillBar._hpBar        = healthBar
    backfillBar._hpCalculator = hpCalc
    -- Health-bar size for the absorb paint: stamped by the bar's own resize edge
    -- instead of two reads per paint (the bar resizes only on reload/tier
    -- passes; the next paint reads the stamp). 0 until the first layout, which
    -- the paint treats as "read it".
    backfillBar._hpW, backfillBar._hpH = healthBar:GetWidth(), healthBar:GetHeight()
    healthBar:HookScript("OnSizeChanged", function(_, w, h)
        backfillBar._hpW, backfillBar._hpH = w, h
    end)
    backfillBar._curClip      = curClip
    backfillBar._missClip     = missClip
    backfillBar._absorbMask   = absorbMask

    d.absorbBar = backfillBar
    -- First pass here, after every bar it anchors exists: a button built mid-session
    -- (Extra Frames) may get no restyle pass, and its heal bars would keep their
    -- creation anchors (horizontal, not inverted).
    ReanchorAbsorbToFill()
    d.ReanchorAbsorbToFill = ReanchorAbsorbToFill
    return backfillBar
end

-------------------------------------------------------------------------------
--  Absorb Bar position. Positions: none / aboveRight / aboveLeft / topRight /
--  topLeft / rightVertical / leftVertical (vertical side bar; fill direction
--  from the per-bar grow-direction setting, default up).
-------------------------------------------------------------------------------
-- Absorb / Heal Absorb Bar position resolvers + strip layout. The legacy
-- absorbBarEnabled boolean maps to "aboveRight"/"none"; absorbBarPosition wins once set.
ns.GetAbsorbBarPosition = function(s)
    local p = s and s.absorbBarPosition
    if p then return p end
    return (s and s.absorbBarEnabled) and "aboveRight" or "none"
end
ns.GetHealAbsorbBarPosition = function(s)
    return (s and s.healAbsorbBarPosition) or "none"
end

-- Anchor/orient a strip bar (Absorb or Heal Absorb) for a position. "above*" sit on top of the
-- frame; "top*" inside at the top of the health bar, just above the absorb-style texture.
-- "belowAbsorb" (heal bar only) sits flush below the Absorb Bar's bottom edge, derived from its
-- POSITION not live visibility, so it never shifts up. "*Right" fills from the right edge.
-- "*Vertical" hugs the health bar's left/right edge: "height" acts as width and vertGrowDir
-- ("up" default / "down") picks the fill direction.
ns.ApplyStripBarLayout = function(stripBar, ab, button, position, height, absorbPos, absorbHeight, vertGrowDir)
    if not stripBar then return end
    local hp = ab._hpBar or button
    -- Party Frames kit: the strips that hang off the frame edge use the
    -- visible party frame, not the whole button box; a party portrait's
    -- frame, the bars beside it.
    button = hp._euiKitRef or hp._euiBarArea or button
    stripBar:ClearAllPoints()
    if position == "rightVertical" or position == "leftVertical" then
        stripBar:SetOrientation("VERTICAL")
        stripBar:SetReverseFill(vertGrowDir == "down")
        stripBar:SetWidth(PixelSnap(height or 4))
        if position == "rightVertical" then
            stripBar:SetPoint("TOPRIGHT", hp, "TOPRIGHT", 0, 0)
            stripBar:SetPoint("BOTTOMRIGHT", hp, "BOTTOMRIGHT", 0, 0)
        else
            stripBar:SetPoint("TOPLEFT", hp, "TOPLEFT", 0, 0)
            stripBar:SetPoint("BOTTOMLEFT", hp, "BOTTOMLEFT", 0, 0)
        end
        stripBar:SetFrameLevel(ab:GetFrameLevel() + 1)
        return
    end
    stripBar:SetOrientation("HORIZONTAL")
    stripBar:SetHeight(PixelSnap(height or 4))
    if position == "belowAbsorb" then
        absorbPos = absorbPos or "none"
        -- "above" absorb bottom = frame top edge (yOff 0); "top" (inside) = one absorb-height below the top edge.
        local yOff = 0
        if absorbPos == "topRight" or absorbPos == "topLeft" then
            yOff = -PixelSnap(absorbHeight or 4)
        end
        -- Match the Absorb Bar's fill direction so the pair lines up.
        stripBar:SetReverseFill(absorbPos ~= "aboveLeft" and absorbPos ~= "topLeft")
        stripBar:SetPoint("TOPLEFT", button, "TOPLEFT", 0, yOff)
        stripBar:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, yOff)
        stripBar:SetFrameLevel(ab:GetFrameLevel() + 1)
    elseif position == "topRight" or position == "topLeft" then
        stripBar:SetReverseFill(position == "topRight")
        stripBar:SetPoint("TOPLEFT", hp, "TOPLEFT", 0, 0)
        stripBar:SetPoint("TOPRIGHT", hp, "TOPRIGHT", 0, 0)
        stripBar:SetFrameLevel(ab:GetFrameLevel() + 1)
    else
        stripBar:SetReverseFill(position == "aboveRight")
        stripBar:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 0)
        stripBar:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 0)
        if ab._hpBar then stripBar:SetFrameLevel(ab._hpBar:GetFrameLevel() + 3) end
    end
end

-------------------------------------------------------------------------------
--  Update absorb bar for a button
-------------------------------------------------------------------------------
-- Absorb paint helpers (on ns). Every
-- absorb child is toggled by UpdateAbsorb alone -- creation hides them and the
-- style appliers never touch visibility -- so a stamped Show/Hide is exact:
-- nil = fresh frame, always pushes. Ranges: max health reads PLAIN for group
-- members, so a per-bar stamp skips the identical re-push; a secret max always
-- pushes and clears the stamp (today's behavior in every restricted context).
function ns._RFShow(f)
    if f._vis ~= true then f._vis = true; f:Show() end
end
function ns._RFHide(f)
    if f._vis ~= false then f._vis = false; f:Hide() end
end
function ns._RFPushRange(bar, maxHealth, maxPlain)
    if maxPlain and bar._rMax == maxHealth then return end
    bar:SetMinMaxValues(0, maxHealth)
    bar._rMax = maxPlain and maxHealth or nil
end

-- now: the caller's frame clock when it has one (the flush paints a batch on
-- one read); nil = read it here.
local function UpdateAbsorb(button, unit, now)
    local d = GetFFD(button)
    local ab = d.absorbBar
    if not ab then return end
    local fw = ab._forward
    local hp = ab._hpBar
    local ha = ab._healAbsorb
    local calc = ab._hpCalculator
    if not hp then return end
    local RFShow, RFHide, PushRange = ns._RFShow, ns._RFHide, ns._RFPushRange

    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    local topBar = ab._topBar
    local barPos = ns.GetAbsorbBarPosition(s)
    local barOn = topBar and barPos ~= "none"
    local healTopBar = ab._healTopBar
    local healBarPos = ns.GetHealAbsorbBarPosition(s)
    local healBarOn = healTopBar and healBarPos ~= "none"
    local styleOn = s.absorbStyle and s.absorbStyle ~= "none"
    local modern = s.absorbStyle == "blizzardModern"
    -- Blizzard Glow Line, settings-derived and gen-gated (an unset key would otherwise fall
    -- through the proxy chain on every paint). Unset follows the style: on for Default Blizz
    -- Frames only. _glowEdge = where the line sits on the drawn layout:
    --   1 = the current-HP seam, moving to the overshield's LEFT edge while overshielding
    --       (Overlay; Default Blizz Frames in every stored placement, as it always drew);
    --   2 = Overlay with From Left: the seam, moving to the from-left overshield's RIGHT
    --       edge while overshielding;
    --   3 = Overlay Reverse: the shield's LEFT edge, which always meets current health;
    --   5 = From Right Edge: the shield's LEFT edge, shown only while the shield reaches
    --       current health (exactly the overshield boolean).
    -- From Left Edge draws no line: no secret-safe test tells whether its edge meets current
    -- health. Vertical fill hides it too: these 16px glows cannot follow a vertical edge.
    if ab._glowGen ~= ns._absorbGen then
        ab._glowGen = ns._absorbGen
        local gl = s.absorbGlowLine
        ab._glowOn = gl == true or (gl == nil and modern)
        local em = s.absorbEdgeMode or "overlay"
        if modern then
            ab._glowEdge = 1
        elseif em == "overlay" then
            local osm = s.overshieldMode
            if osm == nil then osm = (s.showOvershield == false) and "never" or "always" end
            ab._glowEdge = (osm == "fromleft") and 2 or 1
        elseif em == "right" then
            ab._glowEdge = 5
        elseif em == "left" then
            ab._glowOn = false
            ab._glowEdge = 4
        else
            ab._glowEdge = 3
        end
    end
    local glowOn = styleOn and ab._glowOn and not ab._axisVert
    -- The seam/overshield flip (placements 1-2) and the From Right Edge gate (5) read the
    -- overshield boolean; Overlay Reverse (3) needs none.
    local needClamp = glowOn and ab._glowEdge ~= 3
    -- Heal absorb is independent of the shield absorb: keep going whenever its style is on.
    local healOn = (s.healAbsorbStyle or "clean") ~= "none"
    -- Heal prediction is also independent, and shares this frame, so it must keep the frame alive too.
    local predOn = s.healPrediction and true or false
    -- Reduced max health is independent too (a max-HP-loss debuff has nothing to do with
    -- shield absorbs) -- without this the whole overlay frame bails out below whenever
    -- Absorb Style is "none", even with Max Health Style on, so it never gets to paint.
    local maxHealthOn = (s.maxHealthStyle or "maxHealthStripes") ~= "none"
    if not styleOn and not barOn and not healOn and not healBarOn and not predOn and not maxHealthOn then
        RFHide(ab)
        if fw then RFHide(fw) end
        if fw and fw._edgeSpark then RFHide(fw._edgeSpark) end
        if fw and fw._bfSpark then RFHide(fw._bfSpark) end
        if ha then RFHide(ha) end
        if topBar then RFHide(topBar) end
        if healTopBar then RFHide(healTopBar) end
        return
    end

    local maxHealth, absorbAmt, isClamped
    -- The calculator serves exactly two consumers: the Blizzard Glow Line's
    -- seam/overshield flip (the Missing-Health clamp boolean) and the
    -- incoming-heal amount (its heal-absorb-reduced form). Anything else with
    -- prediction off reads nothing it adds, so it skips the fill and takes the
    -- range from the plain max. Max mode is configured once at creation.
    if calc and UnitGetDetailedHealPrediction and (needClamp or predOn) then
        UnitGetDetailedHealPrediction(unit, nil, calc)
        maxHealth = calc:GetMaximumHealth()
        if needClamp then
            -- 2nd return (Missing Health clamp) = secret-safe overshield boolean.
            local _, clampedBool = calc:GetDamageAbsorbs()
            isClamped = clampedBool
        end
    else
        maxHealth = UnitHealthMax(unit) or 0
    end
    -- Bars get the FULL absorb so the overflow/backfill renders correctly.
    absorbAmt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0
    local maxPlain = not issecretvalue(maxHealth)
    -- One heal-absorb fetch serves both the strip bar AND the overlay below.
    local healAbsorbAmt = (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit)) or 0

    -- Incoming heals, fetched here so the short-circuit below sees it too.
    -- predOn-GATED: with prediction off this stays a constant 0, so the fetch
    -- never runs and the memo's _mPred compares 0==0 forever -- heal traffic
    -- must not break the short-circuit for users without the feature.
    -- Calculator is refreshed above; legacy global only as its fallback.
    local incomingHeals = 0
    if predOn then
        if calc and UnitGetDetailedHealPrediction and calc.GetIncomingHeals then
            incomingHeals = calc:GetIncomingHeals() or 0
        elseif UnitGetIncomingHeals then
            incomingHeals = UnitGetIncomingHeals(unit) or 0
        end
    end

    -- Identical-state short-circuit: absorbs re-flush far more often than values change and every
    -- paint below is idempotent. Skip when values, health-bar size and the settings generation all
    -- match the last paint. SECRET-SAFE: secrets cannot be compared, so any secret input fails
    -- open to painting and poisons the memo for the next plain pass.
    -- Health-bar size from the resize stamp (CreateAbsorbBar hooks the bar's
    -- own OnSizeChanged); the read is the fallback until the first layout.
    local hpW, hpH = ab._hpW, ab._hpH
    if not hpW or hpW == 0 then hpW, hpH = hp:GetWidth(), hp:GetHeight() end
    local isSec = issecretvalue
    local anySec = isSec and (isSec(absorbAmt) or isSec(maxHealth)
       or isSec(healAbsorbAmt) or isSec(isClamped) or isSec(incomingHeals))
    -- Absorb-active lean flag: the health ride repaints absorbs ONLY while
    -- this is set (clamp state can flip with health while shielded; with no
    -- absorb, a health change alters nothing this function paints). Event
    -- branches arm it; a fresh PLAIN all-zero read here disarms; secret reads
    -- keep it armed (fail-open = today's always-paint behavior in combat).
    ab._paintAt = now or GetTime()
    if anySec then
        if not d._absActive then ns._AbArm(button, unit, d) end
    elseif (absorbAmt or 0) > 0 or (healAbsorbAmt or 0) > 0
        or incomingHeals > 0 or isClamped == true then
        if not d._absActive then ns._AbArm(button, unit, d) end
    else
        d._absActive = false
        ns._abArmed[button] = nil
    end
    if anySec then
        ab._mAbs = nil
    elseif ab._mAbs == absorbAmt and ab._mHeal == healAbsorbAmt
       and ab._mMax == maxHealth and ab._mClamp == isClamped
       and ab._mW == hpW and ab._mH == hpH
       and ab._mPred == incomingHeals
       and ab._mGen == ns._absorbGen then
        return
    else
        ab._mAbs, ab._mHeal, ab._mMax = absorbAmt, healAbsorbAmt, maxHealth
        ab._mClamp, ab._mW, ab._mH = isClamped, hpW, hpH
        ab._mPred = incomingHeals
        ab._mGen = ns._absorbGen
    end

    -- Absorb Bar: fed raw values (secret-safe); a zero absorb renders as an empty bar.
    if topBar then
        if barOn then
            -- Settings-derived pushes are GEN-GATED: they change only on settings writes (every RF
            -- options write bumps ns._absorbGen, see _BumpAbsorbGen), and unlike the value memo
            -- this gate survives combat secrecy (gen + frame sizes are never secret).
            if topBar._sGen ~= ns._absorbGen then
                topBar._sGen = ns._absorbGen
                local bc = s.absorbBarColor or { r = 1, g = 1, b = 1 }
                local bh = s.absorbBarHeight or 4
                local gd = s.absorbBarGrowDir or "up"
                -- Re-layout only when position/height/direction changes (no per-update SetPoint churn).
                if topBar._lpPos ~= barPos or topBar._lpH ~= bh or topBar._lpGD ~= gd then
                    topBar._lpPos = barPos; topBar._lpH = bh; topBar._lpGD = gd
                    ns.ApplyStripBarLayout(topBar, ab, button, barPos, bh, nil, nil, gd)
                end
                topBar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a or 1)
            end
            PushRange(topBar, maxHealth, maxPlain)
            topBar:SetValue(absorbAmt)
            RFShow(topBar)
        else
            RFHide(topBar)
        end
    end

    -- Heal Absorb Bar: strip showing the heal-absorb amount, independent of the heal-absorb overlay
    -- style (mirrors the Absorb Bar). "Below Absorb Bar" positions it relative to the Absorb slot.
    if healTopBar then
        if healBarOn then
            -- Same gen gate as the Absorb Bar above: settings-only pushes.
            if healTopBar._sGen ~= ns._absorbGen then
                healTopBar._sGen = ns._absorbGen
                local hbc = s.healAbsorbBarColor or { r = 200/255, g = 29/255, b = 29/255 }
                local hbh = s.healAbsorbBarHeight or 4
                local abh = s.absorbBarHeight or 4
                local hgd = s.healAbsorbBarGrowDir or "up"
                -- Re-layout only when its or the Absorb Bar's position/height changes.
                if healTopBar._lpPos ~= healBarPos or healTopBar._lpH ~= hbh
                   or healTopBar._lpAP ~= barPos or healTopBar._lpAH ~= abh
                   or healTopBar._lpGD ~= hgd then
                    healTopBar._lpPos = healBarPos; healTopBar._lpH = hbh
                    healTopBar._lpAP = barPos; healTopBar._lpAH = abh
                    healTopBar._lpGD = hgd
                    ns.ApplyStripBarLayout(healTopBar, ab, button, healBarPos, hbh, barPos, abh, hgd)
                end
                healTopBar:SetStatusBarColor(hbc.r, hbc.g, hbc.b, hbc.a or 1)
            end
            PushRange(healTopBar, maxHealth, maxPlain)
            healTopBar:SetValue(healAbsorbAmt)
            RFShow(healTopBar)
        else
            RFHide(healTopBar)
        end
    end

    -- Heal absorb (independent) draws under the shield bars (heal level +1 < shield +3) and runs
    -- before the shield gate below so it survives when the shield style is off.
    if ha then
        -- Settings-derived style/level/color pushes gen-gated; per-paint work below is value/size only.
        if ha._sGen ~= ns._absorbGen then
            ha._sGen = ns._absorbGen
            local haStyle = s.healAbsorbStyle or "clean"
            ha._styleNone = (haStyle == "none")
            if not ha._styleNone then
                local hc = s.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
                local hcR, hcG, hcB = hc.r or 0.8, hc.g or 0.15, hc.b or 0.15
                local haKey = (haStyle or "") .. (s.healAbsorbOpacity or 75) .. hcR .. hcG .. hcB
                if ha._lastHaKey ~= haKey then
                    ha._lastHaKey = haKey
                    ns.ApplyHealAbsorbStyle(ha, haStyle, s)
                    -- Retexture REPLACES the fill object: re-arm the backing's one-time fill anchor.
                    if ha._bg then ha._bg._fillAnchored = nil end
                end
                -- "Show Over Dispels" (default off): lift the heal-absorb overlay above the dispel
                -- gradient (button + LVL_DISPEL_OVERLAY + 1), still below border/text/auras and
                -- masked to the bar. Per-bar tracked: level touched only when the toggle flips.
                local overDispel = s.healAbsorbOverDispel == true
                if ha._lastOverDispel ~= overDispel then
                    ha._lastOverDispel = overDispel
                    if overDispel then
                        ha:SetFrameLevel(button:GetFrameLevel() + ns.LVL_DISPEL_OVERLAY + 1)
                    else
                        ha:SetFrameLevel(hp:GetFrameLevel() + 1)
                    end
                end
                -- Black backing: color from settings (gen-gated); the fill-rect anchor is permanent
                -- -- the statusbar texture region persists across SetValue, so anchor once.
                local hbg = ha._bg
                if hbg then
                    hbg:SetColorTexture(0, 0, 0, (s.healAbsorbBgOpacity or 25) / 100)
                    if not hbg._fillAnchored then
                        hbg._fillAnchored = true
                        hbg:SetAllPoints(ha:GetStatusBarTexture())
                    end
                end
            end
        end
        if ha._styleNone then
            RFHide(ha)
        else
            if ha._szW ~= hpW or ha._szH ~= hpH then
                ha._szW = hpW; ha._szH = hpH
                ha:SetWidth(hpW); ha:SetHeight(hpH)
            end
            PushRange(ha, maxHealth, maxPlain)
            ha:SetValue(healAbsorbAmt)
            RFShow(ha)
            local hbg = ha._bg
            if hbg then RFShow(hbg) end
        end
    end

    -- Shield style off: hide the in-frame shield bars. Heal absorb paints earlier in this
    -- function so it's untouched either way; heal prediction and reduced max health both
    -- paint later, so only stop here if those are off too, or their blocks below never run.
    if not styleOn then
        RFHide(ab)
        if fw then RFHide(fw) end
        if fw and fw._edgeSpark then RFHide(fw._edgeSpark) end
        if fw and fw._bfSpark then RFHide(fw._bfSpark) end
        if not predOn and not maxHealthOn then return end
    end

    -- Bars track the health-bar size; size-gated (frame sizes are never secret, so it holds in combat).
    if ab._szW ~= hpW or ab._szH ~= hpH then
        ab._szW = hpW; ab._szH = hpH
        ab:SetWidth(hpW); ab:SetHeight(hpH)
        if fw then fw:SetWidth(hpW); fw:SetHeight(hpH) end
    end

    -- Shield absorb bar painting (ab/fw + the Default Blizz spark decoration below) is scoped to
    -- styleOn only -- with it off, execution still reaches this point (Heal Prediction/Max Health
    -- Style may need to run past here), but must not re-Show() the shield bars styleOn already
    -- asked to hide above.
    if styleOn then
    -- Settings-derived style + mode flags, gen-gated (see the Absorb Bar note).
    if ab._sGen ~= ns._absorbGen then
        ab._sGen = ns._absorbGen
        -- Re-apply style when style, color, or opacity changes
        local absStyle = s.absorbStyle
        local ac = s.absorbColor or { r = 1, g = 1, b = 1 }
        local acR, acG, acB = ac.r or 1, ac.g or 1, ac.b or 1
        local absKey = (absStyle or "") .. (s.absorbOpacity or 90) .. acR .. acG .. acB
        if absStyle and absStyle ~= "none" and ab._lastAbsKey ~= absKey then
            ab._lastAbsKey = absKey
            ApplyAbsorbStyle(ab, absStyle, s)
            -- Retexture REPLACES the fill objects: re-arm the modern base's one-time fill anchor
            -- and the glow anchors that can ride ab's fill (the gate, the overshield spark). The
            -- seam spark's target (the gate bar's texture) is creation-static and never re-arms.
            if fw and fw._modernBase then fw._modernBase._fillAnchored = nil end
            if fw and fw._edgeGate then fw._edgeGate._ge = nil end
            if fw and fw._bfSpark then fw._bfSpark._anc = nil end
        end
        ab._absStyle = absStyle
        -- Show Overshield (three-way; legacy boolean preserved): the absorb exceeding empty
        -- health, backfilling over current health -- drawn by the backfill bar (ab) in overlay +
        -- Default-Blizz modes. "never" (old toggle OFF) feeds the backfill 0 so only empty health
        -- fills; "always" (old ON, default) keeps the classic fill-edge backfill; "fromleft"
        -- re-anchors it in the reanchor pass so the excess grows from the bar's origin edge.
        -- nil overshieldMode falls back to the old showOvershield boolean, so saved toggles keep
        -- their meaning. Right/left edge modes draw the WHOLE absorb through ab (fw hidden
        -- below) and are untouched -- overshield is meaningless there.
        local osm = s.overshieldMode
        if osm == nil then osm = (s.showOvershield == false) and "never" or "always" end
        ab._overshieldOn = osm ~= "never"
        ab._overlayLike = absStyle == "blizzardModern" or (s.absorbEdgeMode or "overlay") == "overlay"
        -- Forward bar on: Overlay, and Overlay Reverse (Full) for its excess (Default Blizz
        -- Frames keeps that placement as plain Overlay Reverse, see ReanchorAbsorbToFill).
        ab._edgeOverlay = (s.absorbEdgeMode or "overlay") == "overlay"
            or (s.absorbEdgeMode == "overlayReverseFull" and absStyle ~= "blizzardModern")
    end
    local absStyle = ab._absStyle
    local abValue = absorbAmt
    if not ab._overshieldOn and ab._overlayLike then abValue = 0 end

    -- Both bars get the raw absorb value and maxHealth; clip frames do the visual math, so no secret comparisons.
    PushRange(ab, maxHealth, maxPlain)
    ab:SetValue(abValue)
    RFShow(ab)

    if fw then
        PushRange(fw, maxHealth, maxPlain)
        fw:SetValue(absorbAmt)
        -- Edge modes (right/left): the full-bar backfill shows the whole absorb, so the
        -- overlay-only forward bar is not needed.
        if ab._edgeOverlay then RFShow(fw) else RFHide(fw) end
    end

    -- "Default Blizz Frames": backfill = 10% white overshield, forward = modern texture, whose
    -- solid base rides the forward fill (one-time anchor, re-armed by a retexture).
    if absStyle == "blizzardModern" and fw and not ab._axisVert then
        local fmb = fw._modernBase
        if fmb and not fmb._fillAnchored then
            fmb._fillAnchored = true
            fmb:SetAllPoints(fw:GetStatusBarTexture())
        end
    end

    -- Blizzard Glow Line (placements at the settings stamp above). The seam spark sits on its
    -- invisible gate bar, which self-gates on "has shield". Placements 1-2: the seam spark hides
    -- while overshielding and the overshield spark shows only then (1: the backfill's LEFT edge,
    -- or the health-bar RIGHT edge with Show Overshield off; 2: the from-left overshield's RIGHT
    -- edge) -- isClamped (the Missing-Health-clamp overshield boolean) flips between them
    -- secret-safely, so exactly one is visible. Placements 3 and 5: the gate moves to the
    -- shield's inner edge, one spark; 5 shows it only while isClamped. Anchors move only when
    -- the placement changes or a retexture re-arms them; sizes are size-gated.
    if glowOn and fw then
        local ge = ab._glowEdge or 1
        local g, sp = fw._edgeGate, fw._edgeSpark
        if g and sp then
            if g._szH ~= hpH then g._szH = hpH; g:SetHeight(hpH) end
            if g._ge ~= ge then
                g._ge = ge
                g:ClearAllPoints()
                if ge >= 3 then
                    g:SetPoint("CENTER", ab:GetStatusBarTexture(), "LEFT", -1, 0)
                else
                    g:SetPoint("CENTER", fw, "LEFT", -1, 0)
                end
                if ge == 3 then sp:SetAlpha(1) end
            end
            g:SetValue(absorbAmt)
            if not sp._fillAnchored then
                sp._fillAnchored = true
                sp:SetAllPoints(g:GetStatusBarTexture())
            end
            if ge <= 2 then
                if sp.SetAlphaFromBoolean then sp:SetAlphaFromBoolean(isClamped, 0, 1) else sp:SetAlpha(1) end
            elseif ge == 5 then
                if sp.SetAlphaFromBoolean then sp:SetAlphaFromBoolean(isClamped, 1, 0) else sp:SetAlpha(0) end
            end
            RFShow(sp)
        end
        local bsp = fw._bfSpark
        if bsp then
            if ge <= 2 then
                if bsp._szH ~= hpH then bsp._szH = hpH; bsp:SetSize(16, hpH) end
                -- 0 = health-bar RIGHT (Show Overshield off), 1 = backfill LEFT, 2 = backfill RIGHT.
                local anc = ab._overshieldOn and ge or 0
                if bsp._anc ~= anc then
                    bsp._anc = anc
                    bsp:ClearAllPoints()
                    if anc == 1 then
                        bsp:SetPoint("CENTER", ab:GetStatusBarTexture(), "LEFT", -1, 0)
                    elseif anc == 2 then
                        bsp:SetPoint("CENTER", ab:GetStatusBarTexture(), "RIGHT", 1, 0)
                    else
                        bsp:SetPoint("CENTER", ab, "RIGHT", -1, 0)
                    end
                end
                if bsp.SetAlphaFromBoolean then bsp:SetAlphaFromBoolean(isClamped, 1, 0) else bsp:SetAlpha(0) end
                RFShow(bsp)
            else
                RFHide(bsp)
            end
        end
    elseif fw and fw._edgeSpark then
        RFHide(fw._edgeSpark)
        if fw._bfSpark then RFHide(fw._bfSpark) end
    end
    end -- styleOn

    -- Heal prediction: extends from current HP into missing health
    local hpd = ab._healPred
    if hpd then
        -- Toggle + color gen-gated; size size-gated; value pushes live.
        if hpd._sGen ~= ns._absorbGen then
            hpd._sGen = ns._absorbGen
            hpd._on = s.healPrediction and true or false
            if hpd._on then
                local pc = s.healPredColor or { r = 102/255, g = 243/255, b = 102/255 }
                hpd:SetStatusBarColor(pc.r, pc.g, pc.b, (s.healPredOpacity or 75) / 100)
            end
        end
        if not hpd._on then
            RFHide(hpd)
        else
            if hpd._szW ~= hpW or hpd._szH ~= hpH then
                hpd._szW = hpW; hpd._szH = hpH
                hpd:SetWidth(hpW); hpd:SetHeight(hpH)
            end
            PushRange(hpd, maxHealth, maxPlain)
            hpd:SetValue(incomingHeals)
            RFShow(hpd)
        end
    end

    -- Reduced max health: styled overlay anchored to the right side. Texture/color/opacity/backing
    -- mirror Heal Absorb; re-styled only on change.
    local rmh = ab._reducedMax
    if rmh then
        -- Style key + backing color gen-gated; the fill-rect anchor is permanent.
        if rmh._sGen ~= ns._absorbGen then
            rmh._sGen = ns._absorbGen
            local rmhStyle = s.maxHealthStyle or "maxHealthStripes"
            rmh._styleNone = (rmhStyle == "none")
            if not rmh._styleNone then
                local mc = s.maxHealthColor or { r = 0.7, g = 0.1, b = 0.1 }
                local mcR, mcG, mcB = mc.r or 0.7, mc.g or 0.1, mc.b or 0.1
                local rmhKey = rmhStyle .. (s.maxHealthOpacity or 100) .. mcR .. mcG .. mcB
                if rmh._lastRmhKey ~= rmhKey then
                    rmh._lastRmhKey = rmhKey
                    ns.ApplyMaxHealthStyle(rmh, rmhStyle, s)
                    -- Retexture replaced the fill object: re-arm the backing anchor (re-anchored just below).
                    if ab._reducedMaxBg then ab._reducedMaxBg._fillAnchored = nil end
                end
                local rmhBg = ab._reducedMaxBg
                if rmhBg then
                    rmhBg:SetColorTexture(0, 0, 0, (s.maxHealthBgOpacity or 100) / 100)
                    if not rmhBg._fillAnchored then
                        rmhBg._fillAnchored = true
                        rmhBg:SetAllPoints(rmh:GetStatusBarTexture())
                    end
                end
            end
        end
        -- Loss percent is cached per occupant: it moves only on
        -- UNIT_MAX_HEALTH_MODIFIERS_CHANGED (both dispatchers clear the stamp
        -- there), on occupant change (the assignment hook's full path) and on
        -- a full paint (UpdateButton clears it) -- never on an absorb tick.
        local lossPct = d._rmhPct
        if lossPct == nil then
            lossPct = GetUnitTotalModifiedMaxHealthPercent and GetUnitTotalModifiedMaxHealthPercent(unit) or 0
            d._rmhPct = lossPct
        end
        if not rmh._styleNone and lossPct > 0 then
            if rmh._rv ~= lossPct then rmh._rv = lossPct; rmh:SetValue(lossPct) end
            RFShow(rmh)
        else
            RFHide(rmh)
        end
    end
end

I.CreateAbsorbBar, I.UpdateAbsorb = CreateAbsorbBar, UpdateAbsorb
I.broken = false
