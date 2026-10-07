if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Nameplates_PlatePool.lua
--
--  The frame pool and plate construction, the pool prewarm, RefreshBorder, the
--  hitbox overlay and ns.RefreshAllSettings.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._npInternals
-- EllesmereUINameplates.lua or an earlier nameplate file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs, ipairs = pairs, ipairs
local UnitIsUnit = UnitIsUnit
local C_NamePlate = C_NamePlate
local Enum = Enum

local CAST_H, defaults, ENP, GetNPOutline = I.CAST_H, I.defaults, I.ENP, I.GetNPOutline
local SetFSFont, GetBorderColor = I.SetFSFont, I.GetBorderColor
local GetCastBarHeight, GetDebuffTextColor = I.GetCastBarHeight, I.GetDebuffTextColor
local GetEnemyNameTextSize, GetHealthBarHeight = I.GetEnemyNameTextSize, I.GetHealthBarHeight
local GetHealthBarWidth, GetHitboxYShift = I.GetHealthBarWidth, I.GetHitboxYShift
local GetNameplateYOffset, GetRaidMarkerSize = I.GetNameplateYOffset, I.GetRaidMarkerSize
local GetRareEliteIconSize, GetShowCastIcon = I.GetRareEliteIconSize, I.GetShowCastIcon
local GetStackSpacingScale, IsBorderEnabled = I.GetStackSpacingScale, I.IsBorderEnabled
local SetProfile = I.SetProfile

local p
I.profileSetters[#I.profileSetters + 1] = function(v) p = v end

local frameCache = CreateFramePool("Frame", UIParent, nil, nil, false, function(plate)
    plate:SetFlattensRenderLayers(true)
    plate.health = CreateFrame("StatusBar", nil, plate)
    plate.health:SetFrameLevel(10)
    plate.health:SetPoint("CENTER", plate, "CENTER", 0, GetNameplateYOffset())
    plate.health:SetSize(GetHealthBarWidth(), GetHealthBarHeight())
    plate.health:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    plate.health:SetClipsChildren(false)
    plate.healthBG = plate.health:CreateTexture(nil, "BACKGROUND")
    plate.healthBG:SetAllPoints()
    local _bg = (p and p.bgColor) or defaults.bgColor
    local _bga = (p and p.bgAlpha) or defaults.bgAlpha
    plate.healthBG:SetColorTexture(_bg.r, _bg.g, _bg.b, _bga)
    -- Hash line: thin vertical marker at a configurable health percentage
    plate.hashLine = plate.health:CreateTexture(nil, "OVERLAY", nil, 3)
    plate.hashLine:SetColorTexture(1, 1, 1, 0.8)
    plate.hashLine:SetWidth(2)
    plate.hashLine:SetPoint("TOP", plate.health, "TOP", 0, 0)
    plate.hashLine:SetPoint("BOTTOM", plate.health, "BOTTOM", 0, 0)
    plate.hashLine:Hide()
    -- Mask texture: constrains absorb rendering to exact health bar bounds at the GPU level,
    -- preventing the 1px subpixel bleed absorb textures show at certain nameplate positions.
    local absorbMask = plate.health:CreateMaskTexture()
    absorbMask:SetAllPoints(plate.health)
    absorbMask:SetTexture("Interface\\Buttons\\WHITE8X8")
    plate._absorbMask = absorbMask

    ns.NP_BuildAbsorbBars(plate, plate.health, absorbMask)
    ns.NP_SizeAbsorbBars(plate, GetHealthBarWidth(), GetHealthBarHeight())
    ns.NP_LayoutAbsorbBars(plate, plate.health, (p and p.absorbEdgeMode) or defaults.absorbEdgeMode)
    if CreateUnitHealPredictionCalculator then
        plate.hpCalculator = CreateUnitHealPredictionCalculator()
        -- Configured once: plain max health (the shield never widens the
        -- bar's range) and absorbs clamped to it (a shield fills at most the bar).
        if plate.hpCalculator.SetMaximumHealthMode then
            plate.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
            plate.hpCalculator:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
        end
    end
    local function AddBorder(parent)
        local PP = EllesmereUI and EllesmereUI.PP
        if PP then
            PP.CreateBorder(parent, 0, 0, 0, 1, 1, "OVERLAY", 5, true)  -- scaleGuard: NP frame
        end
    end
    -- Border: single pixel-perfect PP.CreateBorder (BackdropTemplate).
    -- Two settings: showBorder (bool) and borderSize (physical pixels).
    local PP = EllesmereUI and EllesmereUI.PP
    local bc = { r = 0, g = 0, b = 0 }
    bc.r, bc.g, bc.b = GetBorderColor()
    if PP and PP.CreateBorder then
        local sz = ns.NP_BorderSize()
        PP.CreateBorder(plate.health, bc.r, bc.g, bc.b, 1, sz, "OVERLAY", 7, true)  -- scaleGuard: NP frame
        if not IsBorderEnabled() or ns.NP_Classic() then PP.HideBorder(plate.health) end
    end

    function plate:ApplyBorder()
        if not PP then return end
        if ns.NP_Classic() then
            -- Classic WoW UI: the vanilla border art replaces every EUI border.
            PP.HideBorder(plate.health)
            ns.HideCustomBorder(plate)
            ns.NP_ApplyClassicHealthArt(plate)
            ns.NP_ApplyRounding(plate)
            return
        end
        if ns.IsCustomBorderEnabled() then
            -- Custom border replaces the simple one: hide the PP strips on the
            -- health bar and render the custom border on its own child frame.
            PP.HideBorder(plate.health)
            ns.ApplyCustomBorderStyle(plate)
        else
            ns.HideCustomBorder(plate)
            if IsBorderEnabled() then
                PP.SetBorderSize(plate.health, ns.NP_BorderSize())
                PP.ShowBorder(plate.health)
            else
                PP.HideBorder(plate.health)
            end
        end
        -- WoW Forever: the level box right of the bar, sized to it (the
        -- style latched at enable, before any plate).
        if ns._npForever then ns.NP_ApplyForeverLevelBox(plate) end
        -- The spell icon border and divider follow border style edits.
        if (p and (p.castIconCustomBorder or p.castIconSeparator)) or (plate.cast and plate.cast._iconSeam) then
            ns.ApplyCastIconBorder(plate)
        end
        ns.NP_ApplyRounding(plate)
    end
    function plate:ApplyBorderColor()
        if not PP then return end
        -- Threat Colors "Border" channel: UpdateHealthColor parks the resolved threat color
        -- on the plate and this stays the single funnel that paints the BASE border, so
        -- every caller that restores it -- RefreshBorderColor, ApplyTarget's else-branch,
        -- ClearHoverExtras -- picks the threat tint up for free. The target and hover border
        -- colors are applied AFTER this and still win: those are explicit selection states
        -- the user asked for. _threatBdOn is the plain gate; the components themselves can
        -- be SECRET (off-tank C-fold), so they are never tested for truth, only handed to
        -- the setter.
        if plate._threatBdOn then
            if ns.IsCustomBorderEnabled() then
                -- Same lazy build ApplyTarget does: a plate can take the threat tint before
                -- its first ApplyBorder ever ran.
                if not plate._customBorder then ns.ApplyCustomBorderStyle(plate) end
                if plate._customBorder then
                    local a = (p and p.customBorderAlpha) or defaults.customBorderAlpha or 1
                    EllesmereUI.SetBorderStyleColor(plate._customBorder,
                        plate._threatBdR, plate._threatBdG, plate._threatBdB, a)
                end
                plate._hbThreatTint = nil
            else
                ns.NP_BasicBorderColor(plate, plate._threatBdR, plate._threatBdG, plate._threatBdB, 1)
                -- The health border wears the parked tint now: UpdateBorderWrap reads this,
                -- and every other border colour paint (base, target, hover) clears it.
                plate._hbThreatTint = true
            end
        else
            plate._hbThreatTint = nil
            if ns.IsCustomBorderEnabled() then
                ns.ApplyCustomBorderColor(plate)
            else
                local cr, cg, cb = GetBorderColor()
                ns.NP_BasicBorderColor(plate, cr, cg, cb, 1)
            end
        end
        -- ...and border colour edits and the target tint's restore (a tint only), on the
        -- threat path too: untargeting a threat-tinted plate drops the target colour here.
        if (p and (p.castIconCustomBorder or p.castIconSeparator)) or (plate.cast and plate.cast._iconSeam) then
            ns.ApplyCastIconBorder(plate)
        end
    end
    -- Target glow, arrows and focus overlay are lazy (EnsureGlow / EnsureArrows /
    -- EnsureFocusOverlay): only 1 plate shows them, saving ~14 objects per plate.
    plate.healthTextFrame = CreateFrame("Frame", nil, plate)
    plate.healthTextFrame:SetAllPoints(plate.health)
    -- TEXT TIER (top). All three layered groups -- text (900), aura icons (800), indicators
    -- (raid marker/classification, ~13-18) -- use explicit MEDIUM strata so they are pulled out
    -- of the plate's flattened render layer together, ordered purely by frame level. Without
    -- it this frame stays flattened and renders BELOW the aura icons. Text > Auras > Ind.
    plate.healthTextFrame:SetFrameStrata("MEDIUM")
    plate.healthTextFrame:SetFrameLevel(900)
    plate.hpText = plate.healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.hpText, 10, GetNPOutline())
    PP.Point(plate.hpText, "RIGHT", plate.health, "RIGHT", -2, 0)
    plate.hpNumber = plate.healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.hpNumber, 10, GetNPOutline())
    plate.hpNumber:SetPoint("CENTER", plate.health, "CENTER", 0, 0)
    plate.hpNumber:Hide()
    -- Standalone level text: its own FontString so it can share the plate
    -- with the name (see the NAME_FAMILY note). Content is static per unit.
    plate.levelText = plate.healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.levelText, 10, GetNPOutline())
    plate.levelText:SetPoint("CENTER", plate.health, "CENTER", 0, 0)
    plate.levelText:Hide()
    -- Mouseover highlight: parented to the health bar (not the higher-level text
    -- frame) so it renders BEHIND the border (a child at health level + 1).
    -- Blizzard Style: under the stock ring / deselected overlay (OVERLAY 4/5),
    -- above the target wash (0). The EUI and classic looks keep it at 6.
    plate.highlight = plate.health:CreateTexture(nil, "OVERLAY", nil, ns.NP_Style() == "blizzard" and 1 or 6)
    plate.highlight:SetAllPoints(plate.health)
    local _hc = (p and p.hoverColor) or defaults.hoverColor
    local _ha = (p and p.hoverAlpha) or defaults.hoverAlpha
    plate.highlight:SetColorTexture(_hc.r, _hc.g, _hc.b, _ha)
    plate.highlight:Hide()
    -- Top text overlay: renders above health bar + borders so top-slot text is never hidden
    plate.topTextFrame = CreateFrame("Frame", nil, plate)
    plate.topTextFrame:SetAllPoints(plate.health)
    -- TEXT TIER (see healthTextFrame). MEDIUM + level 900 so name text renders
    -- above the aura icons (the name/health fontstrings are reparented between
    -- this frame and healthTextFrame depending on the chosen text slot).
    plate.topTextFrame:SetFrameStrata("MEDIUM")
    plate.topTextFrame:SetFrameLevel(900)
    plate.name = plate:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.name, GetEnemyNameTextSize(), GetNPOutline())
    PP.Point(plate.name, "BOTTOM", plate.health, "TOP", 0, 4)
    PP.Width(plate.name, math.max(GetHealthBarWidth(), 20))
    plate.name:SetWordWrap(false)
    plate.name:SetMaxLines(1)
    plate.nameRaidFrame = CreateFrame("Frame", nil, plate)
    local nameRmSize = (p and p.nameRaidMarkerSize) or defaults.nameRaidMarkerSize or 14
    PP.Size(plate.nameRaidFrame, nameRmSize, nameRmSize)
    plate.nameRaidFrame:SetFrameStrata("MEDIUM")
    plate.nameRaidFrame:SetFrameLevel(901)
    plate.nameRaidFrame:Hide()
    plate.nameRaid = plate.nameRaidFrame:CreateTexture(nil, "ARTWORK")
    plate.nameRaid:SetAllPoints()
    plate.nameRaid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    plate.raidFrame = CreateFrame("Frame", nil, plate)
    local rmSize = GetRaidMarkerSize()
    PP.Size(plate.raidFrame, rmSize, rmSize)
    -- INDICATOR TIER (bottom of the three groups). Explicit MEDIUM strata like the aura icons
    -- and text, so frame level alone orders the pulled-out group: the marker (health+8=18)
    -- sits BELOW auras (800) and text (900) but above the flattened health bar. Sharing MEDIUM
    -- across all three tiers keeps order predictable -- a no-strata frame drops into flattening.
    plate.raidFrame:SetFrameStrata("MEDIUM")
    plate.raidFrame:SetFrameLevel(plate.health:GetFrameLevel() + 8)
    plate.raidFrame:Hide()
    plate.raid = plate.raidFrame:CreateTexture(nil, "ARTWORK")
    plate.raid:SetAllPoints()
    plate.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    plate.classFrame = CreateFrame("Frame", nil, plate)
    local _reIconSz = GetRareEliteIconSize()
    PP.Size(plate.classFrame, _reIconSz, _reIconSz)
    PP.Point(plate.classFrame, "LEFT", plate.health, "LEFT", 2, 0)
    -- INDICATOR TIER (see raidFrame). MEDIUM strata + low level (health+3=13) so the
    -- classification/elite/rare/quest indicator sits below auras/text but above the flattened bar.
    plate.classFrame:SetFrameStrata("MEDIUM")
    plate.classFrame:SetFrameLevel(plate.health:GetFrameLevel() + 3)
    plate.classFrame:Hide()
    plate.class = plate.classFrame:CreateTexture(nil, "ARTWORK")
    plate.class:SetAllPoints()
    -- The faction badge (plate.factionFrame) is built on first use by UpdateFaction.
    plate.cast = CreateFrame("StatusBar", nil, plate)
    -- Cast bar spans the health bar width; by default the icon hangs outside left, and with
    -- "Make Icon Part of the Bar" the bar shrinks to fit it. Must run after plate.health exists.
    ns.LayoutCastBar(plate, ns.GetHealthBarWidth(), CAST_H)
    plate.cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    plate.cast:SetMinMaxValues(0, 1)
    plate.cast:Hide()
    plate.castBG = plate.cast:CreateTexture(nil, "BACKGROUND")
    plate.castBG:SetAllPoints()
    local _cbg = (p and p.castBgColor) or defaults.castBgColor
    local _cba = (p and p.castBgAlpha) or defaults.castBgAlpha
    plate.castBG:SetColorTexture(_cbg.r, _cbg.g, _cbg.b, _cba)
    -- Cast bar border: pixel-perfect PP.CreateBorder, lazy-created (size 0 default, costs
    -- nothing unless enabled). Mirrors the health border; a child of plate.cast.
    function plate:ApplyCastBorder()
        if not PP or not PP.CreateBorder then return end
        local sz = (p and p.castBorderSize) or defaults.castBorderSize or 0
        -- The stock styles carry their own cast bar art (the stock art, the
        -- vanilla cast border): no EUI border.
        if ns.NP_Blizz() then sz = 0 end
        if sz and sz > 0 then
            if PP.GetBorders(plate.cast) then
                PP.SetBorderSize(plate.cast, sz)
                PP.ShowBorder(plate.cast)
            else
                local cr, cg, cb = ns.NP_CastBorderColor()
                PP.CreateBorder(plate.cast, cr, cg, cb, 1, sz, "OVERLAY", 7, true)  -- scaleGuard: NP frame
            end
        elseif PP.GetBorders(plate.cast) then
            PP.HideBorder(plate.cast)
        end
        ns.NP_ApplyRounding(plate, "cast")
    end
    function plate:ApplyCastBorderColor()
        if not PP or not PP.GetBorders or not PP.GetBorders(plate.cast) then return end
        local cr, cg, cb = ns.NP_CastBorderColor()
        PP.SetBorderColor(plate.cast, cr, cg, cb, 1)
    end
    -- "Wrap Border Around Castbar" (opt-in). While cast bar shown + feature on, health + cast
    -- get ONE continuous border from two pieces: the REAL health border (top+sides, untouched
    -- colour) and a region frame for the lower half (sides+bottom, full footprint width, health
    -- bottom -> cast bottom). Touching edges hidden so they read as one outline; region copies
    -- the health border's colour. Each piece MUST live in its own bar's subtree: a PP border is
    -- an OVERLAY texture that reliably beats its OWN bar's ARTWORK fill in the flattened render
    -- layer -- one frame spanning BOTH bars does NOT work (health half would render over the
    -- cast fill, the unreliable cross-flatten case). The region rides "Casts In Front of
    -- Nameplates" natively and lets the lower half bridge a Cast Bar Y gap / enclose an
    -- in-width icon: PP snaps a border's edges to its own frame (SnapBorderTextures), so the
    -- cast bar's own border could only hug the narrower/gapped cast bar. shouldWrap covers
    -- the simple PP border only; the custom border has its own branch and flag
    -- (ns.NP_UpdateCustomBorderWrap, plate._cbWrapActive), run after it.
    function plate:UpdateBorderWrap()
        if not PP or not PP.GetBorders then return end
        -- Classic WoW UI: no EUI borders to wrap (the vanilla art is drawn).
        if ns.NP_Classic() then return end
        local shouldWrap = ns.GetWrapBorderCastbar()
            and plate.cast and plate.cast:IsShown()
            and IsBorderEnabled() and not ns.IsCustomBorderEnabled()
        if shouldWrap then
            local hb = PP.GetBorders(plate.health)
            if hb then
                local sz = ns.NP_BorderSize()
                -- The target border-size effect (ApplyTarget) already resized the health
                -- border before the cast bar showed; carry that size into the wrap instead
                -- of falling back to the base size, or starting a cast on your target visibly
                -- shrinks the border back to normal until the next target change.
                if plate._targetBorderSized then
                    local tbsz = ns.GetTargetBorderSizeValue()
                    if tbsz then sz = tbsz end
                end
                local col = hb._bdColor
                local r, g, b, a = 0, 0, 0, 1
                if col then r, g, b, a = col[1], col[2], col[3], col[4] or 1 end
                -- Threat Colors "Border" tint on the health border: _bdColor keeps only the
                -- last CLEAN colour (PP leaves a secret off-tank fold out of it), so the
                -- region and the re-snapped health border take the parked tint from the
                -- plate. It may be secret: it only ever reaches PP.SetBorderColor, never
                -- the CreateBorder below (which stores its colour) or a compare.
                local thr = plate._hbThreatTint and plate._threatBdOn
                -- Region frame (child of plate.cast) spans the FULL footprint width from the
                -- health bar's BOTTOM to the cast bar's BOTTOM, bridging any Cast Bar Y-offset
                -- gap and enclosing an in-width cast icon; health border keeps top+sides. The
                -- seam (health bottom + region top) is hidden to read as one outline, and the
                -- health border's live colour is copied onto the region (target highlight carries over).
                local region = plate.castWrapRegion
                if not region then
                    region = CreateFrame("Frame", nil, plate.cast)
                    plate.castWrapRegion = region
                end
                region:ClearAllPoints()
                region:SetPoint("TOPLEFT", plate.health, "BOTTOMLEFT", 0, 0)
                region:SetPoint("TOPRIGHT", plate.health, "BOTTOMRIGHT", 0, 0)
                region:SetPoint("BOTTOM", plate.cast, "BOTTOM", 0, 0)
                region:Show()
                -- Lift the region above the cast spell icon (raised to health-level+1 so a
                -- full-size icon clears the health bar), else an in-width icon draws ON TOP of
                -- the wrap border. Re-set every pass -- a strata propagation from the cast-lift would collapse it.
                if plate.castIconFrame then
                    region:SetFrameLevel(plate.castIconFrame:GetFrameLevel() + 2)
                end
                if not PP.GetBorders(region) then
                    PP.CreateBorder(region, r, g, b, a, sz, "OVERLAY", 7, true)  -- scaleGuard: NP frame
                end
                -- Seam flags go on the containers BEFORE (re)snapping so SnapBorderTextures
                -- hides the two touching edges AND runs the side strips to the seam (no edge
                -- line, no corner notch). Flags survive every later re-snap (create-border
                -- 2-tick OnUpdate, scale changes, RefreshBorder); a one-shot :Hide() would not.
                local rb = PP.GetBorders(region)
                if rb then rb._hideTop = true end
                hb._hideBottom = true
                PP.SetBorderSize(region, sz)
                if thr then
                    PP.SetBorderColor(region, plate._threatBdR, plate._threatBdG, plate._threatBdB, 1)
                else
                    PP.SetBorderColor(region, r, g, b, a)
                end
                PP.ShowBorder(region)
                PP.SetBorderSize(plate.health, sz)
                -- The re-snap just re-applied _bdColor to the health strips.
                if thr then
                    ns.NP_BasicBorderColor(plate, plate._threatBdR, plate._threatBdG, plate._threatBdB, 1)
                end
                -- Leave the cast bar's OWN border ACTIVE under the wrap (region border sits
                -- higher and draws over it); only the icon-separator line is hidden so an
                -- in-width icon stays seamless.
                if plate.castLeftBorder then plate.castLeftBorder:Hide() end
                -- Optional: tint the full-size icon's border with the live target border colour
                -- to match the wrapped bar; else-branch keeps it black so toggling off resets it.
                if plate.castIconFrame and PP.GetBorders(plate.castIconFrame) then
                    if p and p.castIconTargetBorder
                        and GetShowCastIcon() and ns.GetCastIconFullSize()
                        and plate.unit and UnitIsUnit(plate.unit, "target")
                        and ns.GetTargetGlowBorderColor()
                    then
                        PP.SetBorderColor(plate.castIconFrame, r, g, b, a)
                    else
                        PP.SetBorderColor(plate.castIconFrame, 0, 0, 0, 1)
                    end
                end
            end
            plate._wrapActive = true
        elseif plate._wrapActive then
            plate._wrapActive = false
            -- Clear the seam flag and re-snap the health border so its bottom edge/side insets
            -- come back (re-applies the live colour). Drop the region, hand the cast border back.
            local hb = PP.GetBorders(plate.health)
            if hb then
                hb._hideBottom = nil
                local sz = ns.NP_BorderSize()
                if plate._targetBorderSized then
                    local tbsz = ns.GetTargetBorderSizeValue()
                    if tbsz then sz = tbsz end
                end
                PP.SetBorderSize(plate.health, sz)
                -- The re-snap re-applied the last clean colour: put a threat tint back.
                if plate._hbThreatTint and plate._threatBdOn then
                    ns.NP_BasicBorderColor(plate, plate._threatBdR, plate._threatBdG, plate._threatBdB, 1)
                end
            end
            if plate.castWrapRegion then
                local crb = PP.GetBorders(plate.castWrapRegion)
                if crb then crb._hideTop = nil end
                if crb then PP.HideBorder(plate.castWrapRegion) end
                plate.castWrapRegion:Hide()
            end
            if plate.castLeftBorder then plate.castLeftBorder:Show() end
            if plate.castIconFrame and PP.GetBorders(plate.castIconFrame) then
                PP.SetBorderColor(plate.castIconFrame, 0, 0, 0, 1)
            end
            plate:ApplyCastBorder()
            plate:ApplyCastBorderColor()
        end
        -- Custom border: wraps (or unwraps a plate it wrapped) whatever the Border mode now is.
        if plate._cbWrapActive or ns.IsCustomBorderEnabled() then
            ns.NP_UpdateCustomBorderWrap(plate)
        end
        ns.ApplyCastIconBorder(plate)
    end
    plate:ApplyCastBorder()
    plate.castLeftBorder = plate.cast:CreateTexture(nil, "OVERLAY", nil, 7)
    plate.castLeftBorder:SetColorTexture(0, 0, 0, 1)
    plate.castLeftBorder:SetWidth(1)
    plate.castLeftBorder:SetPoint("TOPLEFT", plate.cast, "TOPLEFT", 0, 0)
    plate.castLeftBorder:SetPoint("BOTTOMLEFT", plate.cast, "BOTTOMLEFT", 0, 0)
    -- Icon frame hangs outside the cast bar's left edge. Parented AND anchored to cast
    -- (auto-hides with it; same frame = single-pass resolve, no jitter).
    plate.castIconFrame = CreateFrame("Frame", nil, plate.cast)
    -- Lift above the health bar (level 10) once so a full-size icon is never occluded.
    plate.castIconFrame:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    ns.LayoutCastIcon(plate, CAST_H)
    AddBorder(plate.castIconFrame)
    ns.ApplyCastIconBorder(plate)
    plate.castIcon = plate.castIconFrame:CreateTexture(nil, "ARTWORK")
    -- Fill the frame (inset 0) so the 1px OVERLAY border draws ON TOP of the icon's rim: the
    -- visible edge IS the border's inner edge, no bare frame gap. DisablePixelSnap matches the
    -- icon to the unsnapped border strips so they translate together under plate motion.
    plate.castIcon:SetPoint("TOPLEFT", plate.castIconFrame, "TOPLEFT", 0, 0)
    plate.castIcon:SetPoint("BOTTOMRIGHT", plate.castIconFrame, "BOTTOMRIGHT", 0, 0)
    if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(plate.castIcon) end
    -- Stock styles draw the whole icon (zoom 0); the EUI look trims the art's rim.
    if ns.NP_Blizz() then
        plate.castIcon:SetTexCoord(0, 1, 0, 1)
    else
        plate.castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    plate.castSpark = plate.cast:CreateTexture(nil, "OVERLAY", nil, 1)
    plate.castSpark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    plate.castSpark:SetSize(8, CAST_H)
    plate.castSpark:SetPoint("CENTER", plate.cast:GetStatusBarTexture(), "RIGHT", 0, 0)
    plate.castSpark:SetBlendMode("ADD")
    -- Show Spark (Cast Color cog): default on; explicit false hides it.
    plate.castSpark:SetShown(not (p and p.castBarSparkEnabled == false))
    local shieldHeight = CAST_H * 0.75
    local shieldWidth = shieldHeight * (29 / 35)
    plate.castShieldFrame = CreateFrame("Frame", nil, plate.cast)
    plate.castShieldFrame:SetSize(shieldWidth, shieldHeight)
    plate.castShieldFrame:SetPoint("CENTER", plate.cast, "LEFT", 0, 0)
    plate.castShieldFrame:SetFrameLevel(plate.castIconFrame:GetFrameLevel() + 5)
    plate.castShieldFrame:Hide()
    plate.castShield = plate.castShieldFrame:CreateTexture(nil, "OVERLAY")
    plate.castShield:SetAllPoints()
    plate.castShield:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\shield.png")
    plate.castBarOverlay = plate.cast:CreateTexture(nil, "ARTWORK", nil, 2)
    plate.castBarOverlay:SetAllPoints(plate.cast:GetStatusBarTexture())
    plate.castBarOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    plate.castBarOverlay:SetAlpha(0)
    -- Kick tick: clip frame so the tick never renders outside the cast bar when kick CD exceeds
    -- remaining cast time. ONLY kick elements go here; icon/text/shield/spark stay unclipped.
    plate.kickClip = CreateFrame("Frame", nil, plate.cast)
    plate.kickClip:SetAllPoints(plate.cast)
    plate.kickClip:SetClipsChildren(true)
    plate.kickPositioner = CreateFrame("StatusBar", nil, plate.kickClip)
    plate.kickPositioner:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    plate.kickPositioner:GetStatusBarTexture():SetAlpha(0)
    -- Pixel-snap OFF on the fill texture. The tick sits at positioner_width + marker_width; if
    -- either fill snaps independently, round(a)+round(b) flips by 1px when one width crosses a
    -- pixel boundary and the other does not, even though the ratio is invariant -- that's the
    -- jitter. Belt-and-suspenders: the load-bearing unsnap is after each SetFillStyle in
    -- UpdateKickTick (SetFillStyle re-mints the fill to snap-ON; the global SetStatusBarTexture
    -- hook won't re-fire on an already-cached bar).
    if plate.kickPositioner:GetStatusBarTexture().SetSnapToPixelGrid then
        plate.kickPositioner:GetStatusBarTexture():SetSnapToPixelGrid(false)
        plate.kickPositioner:GetStatusBarTexture():SetTexelSnappingBias(0)
    end
    plate.kickPositioner:SetPoint("CENTER", plate.cast)
    plate.kickPositioner:SetFrameLevel(plate.cast:GetFrameLevel() + 1)
    plate.kickPositioner:Hide()
    plate.kickMarker = CreateFrame("StatusBar", nil, plate.kickClip)
    plate.kickMarker:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    plate.kickMarker:GetStatusBarTexture():SetAlpha(0)
    if plate.kickMarker:GetStatusBarTexture().SetSnapToPixelGrid then
        plate.kickMarker:GetStatusBarTexture():SetSnapToPixelGrid(false)
        plate.kickMarker:GetStatusBarTexture():SetTexelSnappingBias(0)
    end
    plate.kickMarker:SetPoint("LEFT", plate.kickPositioner:GetStatusBarTexture(), "RIGHT")
    plate.kickMarker:SetSize(1, 1) -- sized later in UpdateKickTick
    plate.kickMarker:SetFrameLevel(plate.cast:GetFrameLevel() + 2)
    plate.kickMarker:Hide()
    plate.kickTick = plate.kickMarker:CreateTexture(nil, "OVERLAY", nil, 3)
    plate.kickTick:SetColorTexture(1, 1, 1, 1)
    plate.kickTick:SetWidth(2)
    plate.kickTick:SetPoint("TOP", plate.kickMarker, "TOP", 0, 0)
    plate.kickTick:SetPoint("BOTTOM", plate.kickMarker, "BOTTOM", 0, 0)
    plate.kickTick:SetPoint("LEFT", plate.kickMarker:GetStatusBarTexture(), "RIGHT")
    -- Interrupt-ready mid-cast fill: colors the cast-bar segment from "kick ready here" to cast
    -- end (window where the interrupt is available) when kick is on CD now but comes off before
    -- the cast finishes. Rides the SAME kickMarker geometry as the tick, so the "ready in time"
    -- two-secret-duration test resolves purely by where the marker texture edge lands: if the
    -- kick will NOT be ready the left/right anchors cross, the fill collapses to zero width and
    -- self-hides with no Lua branch on a secret. On plate.cast at ARTWORK sublevel 1: above the
    -- bar fill, below the OVERLAY cast text and uninterruptible grey overlay (sublevel 2).
    -- Anchors (re)applied per cast in UpdateKickTick.
    plate.kickReadyFill = plate.cast:CreateTexture(nil, "ARTWORK", nil, 1)
    plate.kickReadyFill:SetColorTexture(1, 1, 1, 1)
    plate.kickReadyFill:SetAlpha(0)
    plate.kickReadyFill:Hide()
    -- Cast bar text: three independent fixed zones [castName LEFT 50%] [castTarget
    -- CENTER-RIGHT 25%] [castTimer RIGHT 15%]. Explicit MEDIUM frame so text leaves the
    -- plate's flattened render layer and draws ABOVE the cast bar border.
    plate.castTextFrame = CreateFrame("Frame", nil, plate.cast)
    plate.castTextFrame:SetAllPoints(plate.cast)
    plate.castTextFrame:SetFrameStrata("MEDIUM")
    plate.castTextFrame:SetFrameLevel(900)
    plate.castName = plate.castTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.castName, 10, GetNPOutline())
    plate.castName:SetPoint("LEFT", plate.cast, "LEFT", 5, 0)
    plate.castName:SetJustifyH("LEFT")
    plate.castName:SetWordWrap(false)
    plate.castName:SetMaxLines(1)
    plate.castTarget = plate.castTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.castTarget, 10, GetNPOutline())
    plate.castTarget:SetJustifyH("RIGHT")
    plate.castTarget:SetWordWrap(false)
    plate.castTarget:SetNonSpaceWrap(false)
    plate.castTarget:SetMaxLines(1)
    plate.castTimer = plate.castTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.castTimer, 10, GetNPOutline())
    plate.castTimer:SetPoint("RIGHT", plate.cast, "RIGHT", -3, 0)
    plate.castTimer:SetJustifyH("RIGHT")
    plate.castTimer:SetWordWrap(false)
    plate.castTimer:SetMaxLines(1)
    plate.castTimer:SetTextColor(1, 1, 1, 1)
    -- Cast timer on a 10Hz ANIM TICKER (engine sleeps between fires), never a per-frame
    -- OnUpdate: text is %.1f, so the displayed tenth cannot change faster than 0.1s, and a
    -- per-render-frame entry per casting plate at uncapped FPS is pure dispatch-floor cost for
    -- a 10Hz job (old accumulator measured 60.8ms/min in a caster-heavy pull). Armed by
    -- NotifyCastStarted; body self-stops at cast end. Uses
    -- UnitCastingDuration/UnitChannelDuration objects + :GetRemainingDuration(), since
    -- UnitCastingInfo's endTime/startTime are secret and unusable in arithmetic.
    plate.cast._timerTick = function(force)
        local self = plate.cast
        local owner = self._timerPlate
        -- force = the synchronous arm-time paint from NotifyCastStarted, which fires BEFORE
        -- the caller sets isCasting (Notify IS the rising-edge detector).
        if not owner or not owner.unit or (not owner.isCasting and not force) then return end
        if not owner._showCastTimer then return true end
        if UnitCastingDuration then
            local durObj = UnitCastingDuration(owner.unit)
                or (UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration(owner.unit, true))
                or (UnitChannelDuration and UnitChannelDuration(owner.unit))
            if durObj then
                local remaining = durObj:GetRemainingDuration()
                owner.castTimer:SetFormattedText("%.1f", remaining)
            else
                owner.castTimer:SetText("")
            end
        else
            local min, max = owner.cast:GetMinMaxValues()
            local val = owner.cast:GetValue()
            if max and max > 0 then
                local remaining = max - val
                if remaining < 0 then remaining = 0 end
                owner.castTimer:SetFormattedText("%.1f", remaining)
            else
                owner.castTimer:SetText("")
            end
        end
        return true
    end
    plate.cast._timerTicker = EllesmereUI.Tick.NewAnimTicker(plate.cast, plate.cast._timerTick, 0.1)
    plate.cast._timerPlate = plate
    -- Full-size cast icon: side-slot reserve is valid only while the cast bar is shown, so
    -- re-anchor reserving side elements on every cast show/hide. One chokepoint catches every
    -- path (start/stop/channel stop/interrupt flash+timer); RefreshCastIconSideReserve
    -- early-outs unless full-size is on.
    local function OnCastVisibilityChanged(self)
        local owner = self._timerPlate
        if owner and owner.RefreshCastIconSideReserve then
            owner:RefreshCastIconSideReserve()
        end
        -- Wrap-border driver, gated so when the feature is off (plate not wrapped) nothing
        -- runs beyond a field read + setting lookup.
        if owner and owner.UpdateBorderWrap and (owner._wrapActive or owner._cbWrapActive or ns.GetWrapBorderCastbar()) then
            owner:UpdateBorderWrap()
        end
        -- Bottom text slots drop below the cast bar while it shows (one flag read when unused).
        if owner and ns._npBottomUsed then owner:AnchorBottomTexts() end
    end
    plate.cast:HookScript("OnShow", OnCastVisibilityChanged)
    plate.cast:HookScript("OnHide", OnCastVisibilityChanged)
    plate.debuffs = {}
    local maxDbf = (p and p.maxDebuffs) or defaults.maxDebuffs
    for i = 1, maxDbf do
        local d = CreateFrame("Frame", nil, plate)
        d:SetFrameStrata("MEDIUM")
        d:SetFrameLevel(800)
        PP.Size(d, 26, 26)
        PP.Point(d, "BOTTOM", plate.name, "TOP", (i - (maxDbf + 1) / 2) * 30, 2)
        AddBorder(d)
        ns.ApplyFrameIconBorder(d, ns.GetIconBorderEnabled("debuffs"), true)
        d.icon = d:CreateTexture(nil, "ARTWORK")
        PP.Point(d.icon, "TOPLEFT", d, "TOPLEFT", 1, -1)
        PP.Point(d.icon, "BOTTOMRIGHT", d, "BOTTOMRIGHT", -1, 1)
        d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- Snap-disable ONCE at creation: aura arm/clear hot paths use PP.RawSetTexture (pre-hook original), which never re-triggers the pixel-snap hook.
        PP.DisablePixelSnap(d.icon)
        d.cd = CreateFrame("Cooldown", nil, d, "CooldownFrameTemplate")
        PP.Point(d.cd, "TOPLEFT", d, "TOPLEFT", 1, -1)
        PP.Point(d.cd, "BOTTOMRIGHT", d, "BOTTOMRIGHT", -1, 1)
        d.cd:SetFrameLevel(d:GetFrameLevel() + 2)
        if d.cd.SetDrawSwipe then d.cd:SetDrawSwipe(true) end
        if d.cd.SetDrawEdge then d.cd:SetDrawEdge(false) end
        if d.cd.SetDrawBling then d.cd:SetDrawBling(false) end
        if d.cd.SetReverse then d.cd:SetReverse(true) end
        if d.cd.SetHideCountdownNumbers then d.cd:SetHideCountdownNumbers(false) end
        -- Stack count + countdown text on a carrier ABOVE the cooldown so the zero-duration
        -- alpha mask on d.cd (kills the permanent-aura swipe strobe) never hides them. Carrier
        -- at slot+6, above the pandemic/dispel glow wrappers (slot+5).
        d.countCarrier = CreateFrame("Frame", nil, d)
        d.countCarrier:SetAllPoints(d)
        d.countCarrier:SetFrameLevel(d:GetFrameLevel() + 6)
        d.count = d.countCarrier:CreateFontString(nil, "OVERLAY")
        SetFSFont(d.count, 11, "OUTLINE, SLUG")
        PP.Point(d.count, "BOTTOMRIGHT", d, "BOTTOMRIGHT", 1, 1)
        d.count:SetJustifyH("RIGHT")
        local cdRegions = { d.cd:GetRegions() }
        for _, region in ipairs(cdRegions) do
            if region:GetObjectType() == "FontString" then
                d.cd.text = region
                region:SetParent(d.countCarrier)
                SetFSFont(region, 11, "OUTLINE, SLUG")
                region:ClearAllPoints()
                PP.Point(region, "TOPLEFT", d, "TOPLEFT", -3, 4)
                region:SetJustifyH("LEFT")
                region:SetTextColor(GetDebuffTextColor())
                break
            end
        end
        d:Hide()
        plate.debuffs[i] = d
    end
    plate.buffs = {}
    for i = 1, 4 do
        local b = CreateFrame("Frame", nil, plate)
        b:SetFrameStrata("MEDIUM")
        b:SetFrameLevel(800)
        PP.Size(b, 24, 24)
        PP.Point(b, "RIGHT", plate.health, "LEFT", -2 - (i - 1) * 26, 0)
        AddBorder(b)
        ns.ApplyFrameIconBorder(b, ns.GetIconBorderEnabled("buffs"), true)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        PP.Point(b.icon, "TOPLEFT", b, "TOPLEFT", 1, -1)
        PP.Point(b.icon, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        PP.DisablePixelSnap(b.icon)
        b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        PP.Point(b.cd, "TOPLEFT", b, "TOPLEFT", 1, -1)
        PP.Point(b.cd, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        b.cd:SetFrameLevel(b:GetFrameLevel() + 2)
        if b.cd.SetDrawSwipe then b.cd:SetDrawSwipe(true) end
        if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
        if b.cd.SetDrawBling then b.cd:SetDrawBling(false) end
        if b.cd.SetReverse then b.cd:SetReverse(true) end
        if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(false) end
        -- Stack count + countdown text on a carrier ABOVE the cooldown (see debuff slot) so
        -- b.cd's zero-duration alpha mask never hides them. Carrier at slot+6, above dispel glow.
        b.countCarrier = CreateFrame("Frame", nil, b)
        b.countCarrier:SetAllPoints(b)
        b.countCarrier:SetFrameLevel(b:GetFrameLevel() + 6)
        b.count = b.countCarrier:CreateFontString(nil, "OVERLAY")
        SetFSFont(b.count, 9, "OUTLINE, SLUG")
        PP.Point(b.count, "BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
        local bCdRegions = { b.cd:GetRegions() }
        for _, region in ipairs(bCdRegions) do
            if region:GetObjectType() == "FontString" then
                b.cd.text = region
                region:SetParent(b.countCarrier)
                SetFSFont(region, 12, "OUTLINE, SLUG")
                region:ClearAllPoints()
                region:SetPoint("CENTER", b, "CENTER", 0, 0)
                break
            end
        end
        b:Hide()
        plate.buffs[i] = b
    end
    plate.cc = {}
    for i = 1, 2 do
        local c = CreateFrame("Frame", nil, plate)
        c:SetFrameStrata("MEDIUM")
        c:SetFrameLevel(800)
        PP.Size(c, 24, 24)
        PP.Point(c, "LEFT", plate.health, "RIGHT", 2 + (i - 1) * 26, 0)
        AddBorder(c)
        ns.ApplyFrameIconBorder(c, ns.GetIconBorderEnabled("ccs"), true)
        c.icon = c:CreateTexture(nil, "ARTWORK")
        PP.Point(c.icon, "TOPLEFT", c, "TOPLEFT", 1, -1)
        PP.Point(c.icon, "BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
        c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        PP.DisablePixelSnap(c.icon)
        c.cd = CreateFrame("Cooldown", nil, c, "CooldownFrameTemplate")
        PP.Point(c.cd, "TOPLEFT", c, "TOPLEFT", 1, -1)
        PP.Point(c.cd, "BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
        c.cd:SetFrameLevel(c:GetFrameLevel() + 2)
        if c.cd.SetDrawSwipe then c.cd:SetDrawSwipe(true) end
        if c.cd.SetDrawEdge then c.cd:SetDrawEdge(false) end
        if c.cd.SetDrawBling then c.cd:SetDrawBling(false) end
        if c.cd.SetReverse then c.cd:SetReverse(true) end
        if c.cd.SetHideCountdownNumbers then c.cd:SetHideCountdownNumbers(false) end
        local cdRegions = { c.cd:GetRegions() }
        for _, region in ipairs(cdRegions) do
            if region:GetObjectType() == "FontString" then
                c.cd.text = region
                SetFSFont(region, 12, "OUTLINE, SLUG")
                region:ClearAllPoints()
                region:SetPoint("CENTER", c, "CENTER", 0, 0)
                break
            end
        end
        c:Hide()
        plate.cc[i] = c
    end
    plate:SetScript("OnEvent", function(self, event, ...)
        local handler = self[event]
        if handler then handler(self, ...) end
    end)
end)

-- Pre-warm the plate frame pool so AoE pulls don't pay the 2ms+ per-plate creation cost
-- (CreateFrame + child textures + cooldowns) on every Acquire when many plates appear in one
-- engine frame; a 5-mob pack can otherwise stack 10+ms of synchronous setup -> visible stutter.
-- Spread over 2 seconds (1 plate/100ms) after PLAYER_LOGIN so login stays smooth. Each Acquire
-- runs the pool's creation function; Release returns the frame for instant reuse.
do
    local prewarmFrame = CreateFrame("Frame")
    prewarmFrame:RegisterEvent("PLAYER_LOGIN")
    prewarmFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(2, function()
            -- Hold acquires until end so each one actually creates a new pool frame.
            local held = {}
            local made = 0
            local target = 20
            local ticker
            ticker = C_Timer.NewTicker(0.1, function()
                made = made + 1
                if made > target then
                    for i = 1, #held do frameCache:Release(held[i]) end
                    ticker:Cancel()
                    return
                end
                held[made] = frameCache:Acquire()
            end)
        end)
    end)
end

function ns.GetActiveKickSpell()
    return EllesmereUI.GetActiveKickSpell()
end
-- Cast overlay uses the same tint as the on-plate cast bar.
ns.ComputeCastBarTint = function(readyTint, baseTint)
    if EllesmereUI and EllesmereUI.ComputeCastBarTint then
        return EllesmereUI.ComputeCastBarTint(readyTint, baseTint)
    end
    return baseTint.r, baseTint.g, baseTint.b
end
local function GetActiveKickSpell()
    return ns.GetActiveKickSpell()
end
local ComputeCastBarTint = ns.ComputeCastBarTint
-- Re-evaluate the cast-bar wrap on every enemy plate; each plate self-decides to wrap or
-- unwrap, so this both applies and tears down. Called unconditionally from the option toggle
-- (catches toggle-off) and, gated on the setting, from the border refreshers, so size/colour
-- edits during a wrapped mid-cast plate keep the unified border in sync.
function ns.ApplyBorderWrapToAll()
    for _, plate in pairs(ns.plates) do
        if plate.UpdateBorderWrap then plate:UpdateBorderWrap() end
    end
end
function ns.RefreshBorder()
    -- Bump appearance gen so pooled/off-screen plates pick up the change on their next SetUnit.
    ns._npAppearanceGen = (ns._npAppearanceGen or 0) + 1
    for _, plate in pairs(ns.plates) do
        if plate.ApplyBorder then plate:ApplyBorder() end
        -- ApplyBorder draws the base colour (custom rebuild) or the last clean one (re-snap)
        -- over a Threat Colors tint, and the _threatBdK memo would skip the repaint.
        if plate._threatBdOn and plate.unit then plate:RepaintThreatBorder(plate.unit) end
    end
    -- Friendly plates mirror the enemy border settings 1:1.
    if ns.friendlyPlates then
        -- Target Border Effects: the base repaint drops a friendly target's target size
        -- and tint, so its ApplyTarget puts them back. One field read while off.
        local fx = p and p.friendlyTargetBorderFx
        for _, plate in pairs(ns.friendlyPlates) do
            if plate.ApplyBorder then plate:ApplyBorder() end
            if fx and plate._isTarget then plate:ApplyTarget() end
        end
    end
    -- Additive: no-op unless the wrap feature is enabled.
    if ns.GetWrapBorderCastbar() then ns.ApplyBorderWrapToAll() end
    -- Custom Border on Aura Icons: the aura styles carry the custom border, so a border
    -- edit restyles them (fingerprint-gated). One field read while off.
    if p and p.auraIconCustomBorder and ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
    -- Debuff Coloring's Color Border is drawn from the border's own numbers
    -- (fingerprint-gated, one profile read while off).
    if ns.DebuffColors_RequestRefresh then ns.DebuffColors_RequestRefresh() end
end
ns.RefreshBorderStyle = ns.RefreshBorder
ns.RefreshSimpleBorderSize = ns.RefreshBorder
function ns.RefreshBorderColor()
    ns._npAppearanceGen = (ns._npAppearanceGen or 0) + 1
    for _, plate in pairs(ns.plates) do
        if plate.ApplyBorderColor then plate:ApplyBorderColor() end
    end
    -- Friendly plates mirror the enemy border settings 1:1.
    if ns.friendlyPlates then
        -- Target Border Effects: a friendly target keeps its target tint (a tint only;
        -- its untarget restore paints the new base colour). One field read while off.
        local keepTint = p and p.friendlyTargetBorderFx and ns.GetTargetGlowBorderColor()
        for _, plate in pairs(ns.friendlyPlates) do
            if plate.ApplyBorderColor and not (keepTint and plate._isTarget and plate._fxBorderTinted) then
                plate:ApplyBorderColor()
            end
        end
    end
    -- Additive: no-op unless the wrap feature is enabled.
    if ns.GetWrapBorderCastbar() then ns.ApplyBorderWrapToAll() end
    if p and p.auraIconCustomBorder and ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
end
function ns.RefreshCastBorder()
    ns._npAppearanceGen = (ns._npAppearanceGen or 0) + 1
    for _, plate in pairs(ns.plates) do
        if plate.ApplyCastBorder then plate:ApplyCastBorder() end
    end
    -- ApplyCastBorder re-shows/re-sizes the cast border, so a wrapped mid-cast plate must re-merge.
    if ns.GetWrapBorderCastbar() then ns.ApplyBorderWrapToAll() end
end
function ns.RefreshCastBorderColor()
    ns._npAppearanceGen = (ns._npAppearanceGen or 0) + 1
    for _, plate in pairs(ns.plates) do
        if plate.ApplyCastBorderColor then plate:ApplyCastBorderColor() end
    end
    if ns.GetWrapBorderCastbar() then ns.ApplyBorderWrapToAll() end
end

function ns.RefreshStackingBounds()
    local scale = GetStackSpacingScale() / 100
    local barH = GetHealthBarHeight()
    local castH2 = GetCastBarHeight()
    local nameGap = 4 + GetEnemyNameTextSize()
    local totalH = nameGap + barH + castH2
    local w = GetHealthBarWidth()
    for _, plate in pairs(ns.plates) do
        if plate._stackBounds then
            plate._stackBounds:SetSize(w, totalH * scale)
        end
    end
end

function ns.RefreshStackingMotion()
    if not (Enum and Enum.NamePlateStackType) then return end
    local db = p or defaults
    -- Enemy stacking is always EUI-owned; apply every time. Must NOT be gated on friendly
    -- players, or enemy plates stop stacking for anyone who hands friendly plates to Blizzard.
    EllesmereUI.SetCVarBitfield("nameplateStackingTypes", Enum.NamePlateStackType.Enemy, db.stackingEnabled ~= false, "EllesmereUINameplates")
    -- Friendly stacking is only ours to write while we manage friendly players; when
    -- Blizzard-managed, leave the friendly bit untouched so the user's setting survives.
    if (db.showFriendlyPlayers ~= false) then
        EllesmereUI.SetCVarBitfield("nameplateStackingTypes", Enum.NamePlateStackType.Friendly, db.stackingFriendly == true, "EllesmereUINameplates")
    end
end

-- The click area's height: Hitbox Size Y scales the bar's height, and the
-- stock looks (Blizzard Style, its WoW Forever variant, Classic WoW UI) add 6
-- on top, their art reaching past the bar. The setting itself is untouched.
function ns.NP_HitboxHeight(db)
    local h = GetHealthBarHeight() * ((db.hitboxScaleY or 100) / 100)
    if ns.NP_Blizz() then h = h + 6 end
    return h
end

function ns.RefreshHitboxSize()
    if InCombatLockdown() then return end
    if not C_NamePlate or not C_NamePlate.SetNamePlateSize then return end
    local db = p or defaults
    local sx = (db.hitboxScaleX or 100) / 100
    C_NamePlate.SetNamePlateSize(GetHealthBarWidth() * sx, ns.NP_HitboxHeight(db))
    -- The frame grows from its CENTER, so a taller size enlarges the hitbox evenly above and
    -- below the unit. -10000 insets let the hit rect fill the full (centered) frame.
    if C_NamePlateManager and C_NamePlateManager.SetNamePlateHitTestInsets
       and Enum and Enum.NamePlateType then
        C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Enemy, -10000, -10000, -10000, -10000)
        C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Friendly, -10000, -10000, -10000, -10000)
    end
    -- Anchor content at the frame center (GetHitboxYShift is 0): the frame grows
    -- centered, so the bar stays put and the hitbox stays centered on it.
    local yShift = GetHitboxYShift()
    for _, plate in pairs(ns.plates) do
        plate:ClearAllPoints()
        plate:SetPoint("CENTER", plate.nameplate, "CENTER", 0, yShift)
    end
end

-- Hitbox visualizer: translucent overlay matching each enemy nameplate's clickable bounds (the
-- frame sized by SetNamePlateSize), so the Hitbox Size sliders can be dialled in visually.
-- Runtime-only (resets on reload), created lazily so it costs nothing when off. On ns (cap).
function ns._ApplyHitboxOverlay(plate)
    local np = plate and plate.nameplate
    if not np then return end
    if ns._hitboxOverlayShown then
        local ov = plate.hitboxOverlay
        if not ov then
            ov = CreateFrame("Frame", nil, np)
            local fill = ov:CreateTexture(nil, "BACKGROUND")
            fill:SetAllPoints()
            fill:SetColorTexture(0.047, 0.824, 0.624, 0.18)
            local function Edge()
                local t = ov:CreateTexture(nil, "BORDER")
                t:SetColorTexture(0.047, 0.824, 0.624, 0.85)
                return t
            end
            local top, bottom, left, right = Edge(), Edge(), Edge(), Edge()
            top:SetPoint("TOPLEFT");    top:SetPoint("TOPRIGHT");    top:SetHeight(1)
            bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
            left:SetPoint("TOPLEFT");   left:SetPoint("BOTTOMLEFT");  left:SetWidth(1)
            right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
            plate.hitboxOverlay = ov
        end
        -- Re-parent + re-anchor each apply: pooled plates get reused on a fresh nameplate.
        ov:SetParent(np)
        ov:SetFrameLevel(np:GetFrameLevel() + 10)
        ov:ClearAllPoints()
        ov:SetAllPoints(np)
        ov:Show()
    elseif plate.hitboxOverlay then
        plate.hitboxOverlay:Hide()
    end
end

-- Toggle the hitbox visualizer across every active enemy plate; driven by the eyeball button
-- beside the Hitbox Size sliders in options.
function ns.SetHitboxOverlayShown(show)
    ns._hitboxOverlayShown = show and true or false
    for _, plate in pairs(ns.plates) do
        ns._ApplyHitboxOverlay(plate)
    end
end

--- Full visual refresh for all plates when an entire preset is applied: re-runs SetUnit on each
--- active plate (re-reads all DB values). Deliberate switch only, never per-frame or per-event.
function ns.RefreshAllSettings()
    -- Re-read the profile reference: RepointAllDBs may have swapped the profile table
    -- (spec-linked profiles). All color lookups via _C() read this local.
    SetProfile(ENP.db.profile)
    -- Before any plate repaints: the Text Coloring slot flags the health pass reads
    -- and the name text's combo formats.
    ns.NP_RefreshSlotClassFlags()
    ns.NP_RefreshThreatPctFlag()
    ns.NP_RefreshThreatColorFlag()
    -- Bump the appearance generation so SetUnit re-runs ApplyAppearance per plate; without it,
    -- cache-hit re-spawns skip the static appearance work and new settings never apply.
    ns._npAppearanceGen = (ns._npAppearanceGen or 0) + 1
    for _, plate in pairs(ns.plates) do
        if plate.unit and plate.nameplate then
            plate:SetUnit(plate.unit, plate.nameplate)
        elseif plate.cast and plate.cast._iconSeam then
            ns.ApplyCastIconBorder(plate)
        end
    end
    -- WoW Forever's Show Level Box (per profile): on a flip the level
    -- watchers follow it and the friendly plates gain or park their boxes
    -- (the enemy plates followed through the appearance pass above).
    if ns._npForever and ns.NP_ForeverWatchLevels() then ns.NP_ForeverFriendlyBoxes() end
    if ns.NT_RefreshSetting then ns.NT_RefreshSetting() end
    if ns.RangeText_Apply then ns.RangeText_Apply() end
    if ns.ApplyClassPowerSetting then ns.ApplyClassPowerSetting() end
    if ns.DebuffColors_Refresh then ns.DebuffColors_Refresh() end
    -- Aura containers: fingerprint-guarded, near-free when no aura setting changed.
    if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
    -- Hide Enemy Nameplates OOC is CVar + event driven, and its options setter plus
    -- PLAYER_LOGIN were its only callers: a value written straight into the profile
    -- (override group, profile switch, import) flipped the checkbox while plates kept
    -- the old behaviour. Self-guarded, so an unchanged key costs nothing.
    if ns.ApplyOOCPlates then ns.ApplyOOCPlates() end
    -- Friendly faction badges: redraw for this profile's faction settings.
    ns.NP_RefreshFriendlyFaction()
    -- Friendly Target Border Effects: a profile or override flip reaches the friendly
    -- target now (applies, or restores a plate it styled). Field reads while off.
    if ns.friendlyPlates then
        local fx = p and p.friendlyTargetBorderFx
        for _, fp in pairs(ns.friendlyPlates) do
            if fx or fp._targetBorderSized or fp._fxBorderTinted then fp:ApplyTarget() end
        end
    end
    -- Friendly bar and name colours: a profile or override flip of the class colour
    -- toggles reaches the live full plates.
    if ns.RefreshFriendlyColors then ns.RefreshFriendlyColors() end
    -- WoW Forever: a profile or override flip of the friendly Name Format, the
    -- Subtitle Text mode or its guild brackets reaches the live friendly names
    -- (one compare while they are unchanged).
    if ns.NP_SyncFriendlyNameFormat then ns.NP_SyncFriendlyNameFormat() end
end

I.frameCache, I.GetActiveKickSpell = frameCache, GetActiveKickSpell
I.broken = false
