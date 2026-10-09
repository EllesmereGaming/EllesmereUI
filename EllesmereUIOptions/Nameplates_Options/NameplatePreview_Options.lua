if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\NameplatePreview_Options.lua
--  Nameplates options: the enemy nameplate preview in the content header of
--  the Display page (BuildNameplatePreview). Definitions only; the shared
--  helpers come from ns._NPO_OptEnv (filled by EUI_Nameplates_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUINameplates"]
if not ns then return end  -- module disabled: no options page

-- The name slot's Strata, as on the live plate: a slot's text host sits at
-- level 900 in the slot's strata and the aura icons at 800 in MEDIUM (HIGH with
-- Raise Strata). MEDIUM keeps the name where the preview's text tier puts it
-- (over the auras, under raised ones); LOW and BACKGROUND draw it under every
-- aura, HIGH and up over raised auras too, its raid marker with it. Preview
-- levels over the health bar: text +10/+11, auras +9, raised auras +13 (their
-- duration text +15). The refresh re-parents the name and its marker to the
-- text tier before this runs, so MEDIUM needs nothing.
local function PreviewNameStrata(pf, health, nameFS, nameRaidFrame, strata)
    if strata == "MEDIUM" then return end
    local low = (strata == "BACKGROUND" or strata == "LOW")
    local key = low and "_npNameLowHost" or "_npNameHighHost"
    local host = pf[key]
    if not host then
        host = CreateFrame("Frame", nil, pf)
        host:SetAllPoints(health)
        pf[key] = host
    end
    host:SetFrameLevel(health:GetFrameLevel() + (low and 7 or 16))
    nameFS:SetParent(host)
    if nameRaidFrame:IsShown() then
        nameRaidFrame:SetParent(host)
        nameRaidFrame:SetFrameLevel(host:GetFrameLevel() + 1)
    end
end

--- Build the nameplate preview in the content header area: an exact 1:1
--- replica of a real enemy nameplate (same pixel sizes, anchors, fonts,
--- borders; no glow, no added effects).
--- @param parent  Frame   contentHeaderFrame
--- @param parentW number  available width
--- @return number height consumed
local function BuildNameplatePreview(parent, parentW)
    local env = ns._NPO_OptEnv
    local ADDON_NAME, BAR_W, DB, DBVal = env.ADDON_NAME, env.BAR_W, env.DB, env.DBVal
    local defaults, displayCastIcons, GetNPOptOutline, NAME_RAID_MARKER_GAP = env.defaults, env.displayCastIcons, env.GetNPOptOutline, env.NAME_RAID_MARKER_GAP
    local optState, pcall, PP, RandomizePreviewValues = env.optState, env.pcall, env.PP, env.RandomizePreviewValues
    local SetPVFont = env.SetPVFont
    local FONT_PATH = (EllesmereUI.GetFontPath("nameplates")) or DBVal("font")

    -- Constants matching the real addon exactly
    local CAST_H = 17
    local BORDER_CORNER = 6
    local BORDER_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\border-colorless.png"

    -- Container sized in Update()
    local pf = CreateFrame("Frame", nil, parent)
    pf:SetPoint("TOP", parent, "TOP", 0, 0)

    -- Scale so the preview matches real nameplate size: real plates render at UIParent's effective scale, the panel's is smaller; this ratio keeps pixel values (bar/font/icon) physically sized, and Snap() still works via pf:GetEffectiveScale().
    local previewScale = UIParent:GetEffectiveScale() / parent:GetEffectiveScale()
    pf:SetScale(previewScale)
    -- parentW in preview-local coordinates (used for centering the bar)
    local localParentW = parentW / previewScale

    -- Pixel-snap helper for the preview's scale; defined early so AddBorder and CreatePreviewBorderSet can use it.
    local function IsDragging()
        return EllesmereUI._sliderDragging and EllesmereUI._sliderDragging > 0
    end

    local function Snap(val)
        local s = pf:GetEffectiveScale()
        return math.floor(val * s + 0.5) / s
    end

    -- 1px in preview-scale coordinates (used for borders and icon insets)
    local px = Snap(1)

    -- Icon textures whose insets (px, -px) need refreshing when scale changes
    local _insetIcons = {}

    -- 1px black border helper uses Snap(), not PixelUtil (screen-pixel snap that can disagree with the preview's own grid); returns a refresh fn that re-snaps sizes on scale change.
    local _borderRefreshers = {}
    local function AddBorder(f)
        local function mkB()
            local x = f:CreateTexture(nil, "OVERLAY", nil, 7)
            x:SetColorTexture(0, 0, 0, 1)
            if x.SetSnapToPixelGrid then x:SetSnapToPixelGrid(false); x:SetTexelSnappingBias(0) end
            return x
        end
        local px = Snap(1)
        local t = mkB(); t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); t:SetHeight(px)
        local b = mkB(); b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); b:SetHeight(px)
        -- Vertical edges inset between horizontal edges to avoid corner overlap
        local l = mkB(); l:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, 0); l:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 0); l:SetWidth(px)
        local r = mkB(); r:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT", 0, 0); r:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", 0, 0); r:SetWidth(px)
        f._euiIconEdges = { t, b, l, r }
        _borderRefreshers[#_borderRefreshers + 1] = function()
            local npx = Snap(1)
            t:SetHeight(npx); b:SetHeight(npx)
            l:SetWidth(npx);  r:SetWidth(npx)
        end
    end

    -- Disable WoW's automatic pixel snapping on a texture (prevents sub-pixel jitter vs borders)
    local UnsnapTex = EllesmereUI.PP.DisablePixelSnap

    -- Health bar the central anchor for everything
    local health = CreateFrame("StatusBar", nil, pf)
    health:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    UnsnapTex(health:GetStatusBarTexture())
    -- Preview constants packed to reduce upvalue count
    local PV_CONST = {
        FAKE_MAX_HP = 10000,
        DEBUFF_COUNT = 2,
        BUFF_COUNT = 1,
        CC_COUNT = 1,
    }
    -- There is one preview buff slot, so it shows the type THIS character
    -- removes -- and nil (no glow at all) for a character with no
    -- offensive dispel, which is what their nameplates will do.
    local function PreviewDispelType()
        local magic, enrage = false, false
        if ns.GetOffensiveDispelTypes then magic, enrage = ns.GetOffensiveDispelTypes() end
        if magic then return "magic" end
        if enrage then return "enrage" end
        return nil
    end
    if not optState._previewHpPct then RandomizePreviewValues() end
    local previewHpPct = optState._previewHpPct
    local previewHpVal = math.floor(PV_CONST.FAKE_MAX_HP * previewHpPct / 100)
    health:SetMinMaxValues(0, PV_CONST.FAKE_MAX_HP)
    health:SetValue(previewHpVal)
    health:SetFrameLevel(pf:GetFrameLevel() + 10)
    health:SetStatusBarColor(0.85, 0.20, 0.20, 1)

    local healthBG = health:CreateTexture(nil, "BACKGROUND")
    healthBG:SetAllPoints()
    local _hbg = (DB() and DB().bgColor) or defaults.bgColor
    local _hba = (DBVal("bgAlpha") or defaults.bgAlpha)
    healthBG:SetColorTexture(_hbg.r, _hbg.g, _hbg.b, _hba)
    UnsnapTex(healthBG)

    -- Hash line on preview health bar
    local previewHashLine = health:CreateTexture(nil, "OVERLAY", nil, 3)
    previewHashLine:SetColorTexture(1, 1, 1, 0.8)
    UnsnapTex(previewHashLine)
    previewHashLine:SetWidth(Snap(2))
    previewHashLine:SetPoint("TOP", health, "TOP", 0, 0)
    previewHashLine:SetPoint("BOTTOM", health, "BOTTOM", 0, 0)
    previewHashLine:Hide()

    -- Absorb preview: the live plates' own clip-frame bars and placement
    -- (ns.NP_BuildAbsorbBars), so the preview draws exactly what plates do.
    local absorbMask = health:CreateMaskTexture()
    absorbMask:SetAllPoints(health)
    absorbMask:SetTexture("Interface\\Buttons\\WHITE8X8")
    local pvAbs = {}
    ns.NP_BuildAbsorbBars(pvAbs, health, absorbMask)
    local function ApplyPreviewAbsorbStyle()
        local style = DBVal("absorbStyle") or "blizzard"
        local tex = ns.NP_ABSORB_STYLE_TEX[style] or ns.ResolveOverlayTexPath(style) or ns.NP_ABSORB_STYLE_TEX.blizzard
        local alpha = DBVal("absorbAlpha")
        if alpha then
            alpha = alpha / 100
        elseif style == "clean" then
            alpha = (DBVal("absorbCleanAlpha") or 30) / 100
        else
            alpha = ns.NP_ABSORB_STYLE_ALPHA[style] or 0.8
        end
        local r, g, b = 1, 1, 1
        if style ~= "blizzard" then
            local c = (DB() and DB().absorbColor) or defaults.absorbColor or { r = 1, g = 1, b = 1 }
            r, g, b = c.r, c.g, c.b
        end
        for _, bar in ipairs({ pvAbs.absorb, pvAbs.absorbForward }) do
            bar:SetStatusBarTexture(tex)
            bar:SetStatusBarColor(r, g, b, alpha)
            local fill = bar:GetStatusBarTexture()
            if fill then fill:SetDrawLayer("ARTWORK", 1); fill:AddMaskTexture(absorbMask) end
        end
    end
    local function ToggleAbsorbPreview()
        if optState.showAbsorbPreview then
            local mode = DBVal("absorbEdgeMode") or "overlay"
            -- A shield smaller than the empty health (preview health is
            -- 60-75%), so each placement draws somewhere different: past the
            -- health edge, back over it, or at either end of the bar. A shield
            -- past empty health would draw Overlay and From Right Edge alike.
            local shield = 0.15
            ns.NP_SizeAbsorbBars(pvAbs, health:GetWidth(), health:GetHeight())
            if pvAbs._absEdge ~= mode or pvAbs._absFill ~= health:GetStatusBarTexture() then
                ns.NP_LayoutAbsorbBars(pvAbs, health, mode)
            end
            ApplyPreviewAbsorbStyle()
            pvAbs.absorb:SetMinMaxValues(0, 1)
            pvAbs.absorb:SetValue(shield)
            pvAbs._absCurClip:Show()
            if pvAbs._absFwOn then
                pvAbs.absorbForward:SetMinMaxValues(0, 1)
                pvAbs.absorbForward:SetValue(shield)
                pvAbs._absMissClip:Show()
            end
        else
            pvAbs._absCurClip:Hide()
            pvAbs._absMissClip:Hide()
        end
    end

    -- Bar texture applied directly via SetStatusBarTexture (no overlay); updated in the preview refresh below.

    local BORDER_TEX_SIMPLE = "Interface\\AddOns\\EllesmereUINameplates\\Media\\border-simple.png"

    -- Wrapper frame around the health bar: a plain Frame (not StatusBar) so the image border parented to it never interacts with StatusBar internals; sized to match the health bar exactly.
    local healthWrapper = CreateFrame("Frame", nil, pf)
    healthWrapper:SetFrameLevel(health:GetFrameLevel() + 4)

    -- Border set builder: 9-slice image border on a plain Frame, using PixelUtil (mirrors the UnitFrames preview).
    local function CreatePreviewBorderSet(parent, tex)
        local bc = (DB() and DB().borderColor) or defaults.borderColor
        local f = CreateFrame("Frame", nil, parent)
        f:SetFrameLevel(parent:GetFrameLevel() + 1)
        f:SetAllPoints()
        f._texs = {}
        local function Mk()
            local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetTexture(tex)
            t:SetVertexColor(bc.r, bc.g, bc.b)
            if t.SetSnapToPixelGrid then
                t:SetSnapToPixelGrid(false)
                t:SetTexelSnappingBias(0)
            end
            f._texs[#f._texs + 1] = t
            return t
        end
        -- Corners inset UV by half a texel (T) from edges (0/1) so the GPU fully samples the outermost solid pixel line.
        local T = 0.042
        local function UnsnapAfter(t)
            if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        end
        local tl = Mk(); PP.Size(tl, BORDER_CORNER, BORDER_CORNER); PP.Point(tl, "TOPLEFT", f, "TOPLEFT", 0, 0); tl:SetTexCoord(T, 0.5, T, 0.5); UnsnapAfter(tl)
        local tr = Mk(); PP.Size(tr, BORDER_CORNER, BORDER_CORNER); PP.Point(tr, "TOPRIGHT", f, "TOPRIGHT", 0, 0); tr:SetTexCoord(0.5, 1-T, T, 0.5); UnsnapAfter(tr)
        local bl = Mk(); PP.Size(bl, BORDER_CORNER, BORDER_CORNER); PP.Point(bl, "BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); bl:SetTexCoord(T, 0.5, 0.5, 1-T); UnsnapAfter(bl)
        local br = Mk(); PP.Size(br, BORDER_CORNER, BORDER_CORNER); PP.Point(br, "BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); br:SetTexCoord(0.5, 1-T, 0.5, 1-T); UnsnapAfter(br)
        -- Edges: sample the center column/row with half-texel width
        local H = 0.042
        local top = Mk(); PP.Height(top, BORDER_CORNER); PP.Point(top, "TOPLEFT", tl, "TOPRIGHT", 0, 0); PP.Point(top, "TOPRIGHT", tr, "TOPLEFT", 0, 0); top:SetTexCoord(0.5-H, 0.5+H, T, 0.5); UnsnapAfter(top)
        local bot = Mk(); PP.Height(bot, BORDER_CORNER); PP.Point(bot, "BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0); PP.Point(bot, "BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0); bot:SetTexCoord(0.5-H, 0.5+H, 0.5, 1-T); UnsnapAfter(bot)
        local lft = Mk(); PP.Width(lft, BORDER_CORNER); PP.Point(lft, "TOPLEFT", tl, "BOTTOMLEFT", 0, 0); PP.Point(lft, "BOTTOMLEFT", bl, "TOPLEFT", 0, 0); lft:SetTexCoord(T, 0.5, 0.5-H, 0.5+H); UnsnapAfter(lft)
        local rgt = Mk(); PP.Width(rgt, BORDER_CORNER); PP.Point(rgt, "TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0); PP.Point(rgt, "BOTTOMRIGHT", br, "TOPRIGHT", 0, 0); rgt:SetTexCoord(0.5, 1-T, 0.5-H, 0.5+H); UnsnapAfter(rgt)
        f._corners = { tl, tr, bl, br }
        f._hEdges  = { top, bot }
        f._vEdges  = { lft, rgt }
        function f:ApplySize(sz)
            for _, c in ipairs(self._corners) do PP.Size(c, sz, sz) end
            for _, e in ipairs(self._hEdges)  do PP.Height(e, sz) end
            for _, e in ipairs(self._vEdges)  do PP.Width(e, sz) end
        end
        return f
    end

    local borderFrame = CreatePreviewBorderSet(healthWrapper, BORDER_TEX)
    local simpleBorderFrame = CreatePreviewBorderSet(healthWrapper, BORDER_TEX_SIMPLE)
    -- Custom border preview: dedicated child frame the shared border engine draws onto when Custom Border is enabled; stored on the wrapper (a frame we own) so it adds no new builder local.
    healthWrapper._customBorder = CreateFrame("Frame", nil, healthWrapper)
    healthWrapper._customBorder:SetAllPoints(healthWrapper)
    healthWrapper._customBorder:Hide()

    -- Solid 1px edge lines on all 4 sides of healthWrapper: the image border's outermost pixel can vanish at non-native scales (texture filtering), so these sit below it as a pixel-perfect fallback.
    local function MkSolidEdge()
        local t = healthWrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(0, 0, 0, 1)  -- placeholder; color updated in Update()
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        return t
    end
    local solidT = MkSolidEdge(); solidT:SetHeight(1); PP.Point(solidT, "TOPLEFT", healthWrapper, "TOPLEFT", 0, 0); PP.Point(solidT, "TOPRIGHT", healthWrapper, "TOPRIGHT", 0, 0)
    local solidB = MkSolidEdge(); solidB:SetHeight(1); PP.Point(solidB, "BOTTOMLEFT", healthWrapper, "BOTTOMLEFT", 0, 0); PP.Point(solidB, "BOTTOMRIGHT", healthWrapper, "BOTTOMRIGHT", 0, 0)
    local solidL = MkSolidEdge(); solidL:SetWidth(1); PP.Point(solidL, "TOPLEFT", healthWrapper, "TOPLEFT", 0, 0); PP.Point(solidL, "BOTTOMLEFT", healthWrapper, "BOTTOMLEFT", 0, 0)
    local solidR = MkSolidEdge(); solidR:SetWidth(1); PP.Point(solidR, "TOPRIGHT", healthWrapper, "TOPRIGHT", 0, 0); PP.Point(solidR, "BOTTOMRIGHT", healthWrapper, "BOTTOMRIGHT", 0, 0)
    local _solidEdges = { solidT, solidB, solidL, solidR }

    -- 9-slice soft glow frame for the target-glow preview; matches the real nameplate glow (background.png, ADD blend, blue tint), packed into one table to stay under Lua's 60-upvalue limit.
    local previewGlow = {}
    do
        local GLOW_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\background.png"
        local GM = 0.48  -- margin
        local GC = 12    -- corner size
        previewGlow.extend = 6
        local gf = CreateFrame("Frame", nil, pf)
        gf:SetFrameLevel(pf:GetFrameLevel() + 1)
        previewGlow.frame = gf
        -- Collected so Update() can re-tint the preview glow with target Glow Color/Opacity, matching live nameplates.
        previewGlow.texs = {}
        local gc0 = ns.GetTargetGlowColor()
        local ga0 = ns.GetTargetGlowAlpha()
        local function Mk(coords)
            local t = gf:CreateTexture(nil, "BACKGROUND")
            t:SetTexture(GLOW_TEX)
            t:SetVertexColor(gc0.r, gc0.g, gc0.b, ga0)
            t:SetBlendMode("ADD")
            t:SetTexCoord(unpack(coords))
            previewGlow.texs[#previewGlow.texs + 1] = t
            return t
        end
        local tl = Mk({0,GM,0,GM}); PP.Size(tl,GC,GC); tl:SetPoint("TOPLEFT")
        local tr = Mk({1-GM,1,0,GM}); PP.Size(tr,GC,GC); tr:SetPoint("TOPRIGHT")
        local bl = Mk({0,GM,1-GM,1}); PP.Size(bl,GC,GC); bl:SetPoint("BOTTOMLEFT")
        local br = Mk({1-GM,1,1-GM,1}); PP.Size(br,GC,GC); br:SetPoint("BOTTOMRIGHT")
        local top = Mk({GM,1-GM,0,GM}); PP.Height(top,GC); top:SetPoint("TOPLEFT",tl,"TOPRIGHT"); top:SetPoint("TOPRIGHT",tr,"TOPLEFT")
        local bot = Mk({GM,1-GM,1-GM,1}); PP.Height(bot,GC); bot:SetPoint("BOTTOMLEFT",bl,"BOTTOMRIGHT"); bot:SetPoint("BOTTOMRIGHT",br,"BOTTOMLEFT")
        local lft = Mk({0,GM,GM,1-GM}); PP.Width(lft,GC); lft:SetPoint("TOPLEFT",tl,"BOTTOMLEFT"); lft:SetPoint("BOTTOMLEFT",bl,"TOPLEFT")
        local rgt = Mk({1-GM,1,GM,1-GM}); PP.Width(rgt,GC); rgt:SetPoint("TOPRIGHT",tr,"BOTTOMRIGHT"); rgt:SetPoint("BOTTOMRIGHT",br,"TOPRIGHT")
        gf:Hide()
    end

    -- Target "Highlight" preview: translucent wash over the health bar (color/opacity via the Target Highlight cog); getter refs stashed on previewGlow (already an Update() upvalue) to avoid new upvalues in the near-cap closure.
    previewGlow.highlight = health:CreateTexture(nil, "OVERLAY", nil, 5)
    previewGlow.highlight:SetAllPoints(health)
    do local hc = ns.GetTargetHighlightColor(); previewGlow.highlight:SetColorTexture(hc.r, hc.g, hc.b, ns.GetTargetHighlightAlpha()) end
    previewGlow.highlight:Hide()
    previewGlow.getEUI            = ns.GetTargetGlowEllesmereUI
    previewGlow.getBorderOn       = ns.GetTargetGlowBorderColor
    previewGlow.getHighlight      = ns.GetTargetGlowHighlight
    previewGlow.getBorderCol      = ns.GetTargetBorderColor
    previewGlow.getGlowCol        = ns.GetTargetGlowColor
    previewGlow.getGlowAlpha      = ns.GetTargetGlowAlpha
    previewGlow.getHighlightCol   = ns.GetTargetHighlightColor
    previewGlow.getHighlightAlpha = ns.GetTargetHighlightAlpha
    -- Classic WoW UI (Global Settings > Style), latched for the session
    -- like the live plates: the mock wears the plain 1px black edge on the
    -- health and cast bars. Stashed here so Update gains no upvalue.
    previewGlow.classic = EllesmereUI.BlizzStyle.Active("nameplates") == "classic"
    previewGlow.black = { r = 0, g = 0, b = 0 }
    -- The WoW Forever variant (latched the same way): the level box right
    -- of the bar.
    previewGlow.forever = EllesmereUI.BlizzStyle.Forever("nameplates")

    -- Text overlay frame: renders above health bar fill and borders (same as real addon)
    local healthTextFrame = CreateFrame("Frame", nil, health)
    healthTextFrame:SetAllPoints(health)
    healthTextFrame:SetFrameLevel(health:GetFrameLevel() + 11)

    -- Top text overlay: renders above health bar + borders so top-slot text is never hidden
    local topTextFrame = CreateFrame("Frame", nil, pf)
    topTextFrame:SetAllPoints(health)
    topTextFrame:SetFrameLevel(health:GetFrameLevel() + 10)

    -- Name text (anchored BOTTOM to health TOP, +4px gap, width 113)
    local nameFS = pf:CreateFontString(nil, "OVERLAY")
    SetPVFont(nameFS, FONT_PATH, 11, GetNPOptOutline())
    nameFS:SetPoint("BOTTOM", health, "TOP", 0, 4)
    nameFS:SetWordWrap(false)
    nameFS:SetMaxLines(1)
    nameFS:SetText(EllesmereUI.L("Enemy Name Text"))
    nameFS:SetTextColor(1, 1, 1, 1)

    local nameRaidFrame = CreateFrame("Frame", nil, pf)
    nameRaidFrame:SetFrameLevel(health:GetFrameLevel() + 12)
    nameRaidFrame:Hide()
    local nameRaidIcon = nameRaidFrame:CreateTexture(nil, "ARTWORK")
    nameRaidIcon:SetAllPoints()
    nameRaidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    if SetRaidTargetIconTexture then SetRaidTargetIconTexture(nameRaidIcon, 1) end

    -- Health percentage text (right-aligned inside health bar)
    local hpText = healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(hpText, FONT_PATH, 10, GetNPOptOutline())
    hpText:SetPoint("RIGHT", health, -2, 0)
    hpText:SetText(previewHpPct .. "%")

    -- Health number (centered, hidden by default)
    local hpNumber = healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(hpNumber, FONT_PATH, 10, GetNPOptOutline())
    hpNumber:SetPoint("CENTER", health, "CENTER", 0, 0)
    local hpNumStr = tostring(previewHpVal):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    hpNumber:SetText(hpNumStr)
    hpNumber:Hide()

    -- Standalone level FontString mirrors the live plate's levelText; the player's level stands in for the mob level. Plain text: its colour comes from the slot's Text Coloring mode (previewGlow.slotColor).
    local lvlText = healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(lvlText, FONT_PATH, 10, GetNPOptOutline())
    lvlText:SetPoint("CENTER", health, "CENTER", 0, 0)
    lvlText:SetText((ns.GetUnitLevelText and ns.GetUnitLevelText("player")) or "??")
    lvlText:Hide()
    -- Target of Target sample: the preview mob targets the player (WoW Forever:
    -- with the surname, in the slot's Name Format, as live).
    pf._totFS = healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(pf._totFS, FONT_PATH, 10, GetNPOptOutline())
    pf._totFS:Hide()
    pf._totSample = function(slotKey)
        local name = EllesmereUI.WithSurname(UnitName("player")) or ""
        if ns.NP_FormatName then name = ns.NP_FormatName(name, slotKey) end
        return name
    end
    -- Its colour: in Class mode the player's class colour (the sample target),
    -- else the slot colour passed in.
    pf._totSampleColor = function(slotKey, r, g, b)
        if slotKey and ns.NP_SlotColorMode(slotKey, DB()) == "class" then
            local _, ct = UnitClass("player")
            local cc = ct and EllesmereUI.GetClassColor(ct)
            if cc then return cc.r, cc.g, cc.b end
        end
        return r, g, b
    end

    -- Raid marker: custom marker.png image, position/size from settings
    local MARKER_PATH = "Interface\\AddOns\\EllesmereUI\\media\\marker.png"
    local raidFrame = CreateFrame("Frame", nil, health)
    -- +12 keeps the marker above name/health text (healthTextFrame is health+11), matching the live plate.
    raidFrame:SetFrameLevel(health:GetFrameLevel() + 12)
    local raidIcon = raidFrame:CreateTexture(nil, "ARTWORK")
    raidIcon:SetAllPoints()
    raidIcon:SetTexture(MARKER_PATH)

    -- Target arrows packed into a table to reduce upvalue count
    local ARROW_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Arrows\\"
    local arrows = {}
    arrows.left = pf:CreateTexture(nil, "OVERLAY")
    arrows.left:SetTexture(ARROW_PATH .. "arrow_left.png")
    arrows.left:SetSize(11, 16)
    arrows.left:SetPoint("RIGHT", health, "LEFT", -8, 0)
    arrows.left:Hide()
    arrows.right = pf:CreateTexture(nil, "OVERLAY")
    arrows.right:SetTexture(ARROW_PATH .. "arrow_right.png")
    arrows.right:SetSize(11, 16)
    arrows.right:SetPoint("LEFT", health, "RIGHT", 8, 0)
    arrows.right:Hide()
    pf._arrows = arrows  -- expose for Update resizing

    -- Classification icon (elite dragon) shown when transient toggle is on
    local classIcon = pf:CreateTexture(nil, "OVERLAY")
    classIcon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\elite-rare-indicator.png")
    classIcon:SetSize(24, 24)
    classIcon:Hide()
    -- Faction badge preview (Core Positions "Faction" element)
    local factionIcon = pf:CreateTexture(nil, "OVERLAY", nil, -1)  -- under classIcon when stacked
    factionIcon:SetSize(20, 20)
    factionIcon:Hide()

    -- Cast bar (icon + bar fill health bar width)
    local cast = CreateFrame("StatusBar", nil, pf)
    cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    UnsnapTex(cast:GetStatusBarTexture())
    cast:SetMinMaxValues(0, 1)
    cast:SetValue(optState._previewCastFill)
    cast:SetFrameLevel(pf:GetFrameLevel() + 10)

    local castBG = cast:CreateTexture(nil, "BACKGROUND")
    castBG:SetAllPoints()
    local _pcbg = (DB() and DB().castBgColor) or defaults.castBgColor
    local _pcba = (DBVal("castBgAlpha") or defaults.castBgAlpha)
    castBG:SetColorTexture(_pcbg.r, _pcbg.g, _pcbg.b, _pcba)
    UnsnapTex(castBG)

    -- Cast bar parts packed into a table to reduce upvalue count
    local castParts = {}
    castParts.bg = castBG

    -- Cast icon (flush to the left of the cast bar)
    castParts.iconFrame = CreateFrame("Frame", nil, cast)
    castParts.iconFrame:SetFrameLevel(health:GetFrameLevel() + 1)
    castParts.iconFrame:SetSize(CAST_H, CAST_H)
    castParts.iconFrame:SetPoint("TOPRIGHT", cast, "TOPLEFT", 0, 0)
    AddBorder(castParts.iconFrame)
    castParts.icon = castParts.iconFrame:CreateTexture(nil, "ARTWORK")
    UnsnapTex(castParts.icon)
    castParts.icon:SetAllPoints()
    castParts.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    castParts.icon:SetTexture(displayCastIcons[optState._previewCastIconIdx])

    castParts.spark = cast:CreateTexture(nil, "OVERLAY", nil, 1)
    castParts.spark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    UnsnapTex(castParts.spark)
    castParts.spark:SetSize(8, CAST_H)
    castParts.spark:SetPoint("CENTER", cast:GetStatusBarTexture(), "RIGHT", 0, 0)
    castParts.spark:SetBlendMode("ADD")

    -- Cast text frame: dedicated child ABOVE the cast border so name/target/timer render in front (mirrors the live castTextFrame); the PP border is cast+1 and would otherwise draw over text on cast's own OVERLAY layer.
    castParts.textFrame = CreateFrame("Frame", nil, cast)
    castParts.textFrame:SetAllPoints(cast)
    castParts.textFrame:SetFrameLevel(cast:GetFrameLevel() + 10)

    -- Cast name (left, width 70)
    castParts.nameFS = castParts.textFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(castParts.nameFS, FONT_PATH, 10, GetNPOptOutline())
    castParts.nameFS:SetPoint("LEFT", cast, 5, 0)
    castParts.nameFS:SetJustifyH("LEFT")
    castParts.nameFS:SetWordWrap(false)
    castParts.nameFS:SetMaxLines(1)
    castParts.nameFS:SetText(EllesmereUI.L("Spell Name"))

    -- Cast timer (far right)
    castParts.timerFS = castParts.textFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(castParts.timerFS, FONT_PATH, 10, GetNPOptOutline())
    castParts.timerFS:SetPoint("RIGHT", cast, -3, 0)
    castParts.timerFS:SetJustifyH("RIGHT")
    castParts.timerFS:SetWordWrap(false)
    castParts.timerFS:SetMaxLines(1)
    castParts.timerFS:SetTextColor(1, 1, 1, 1)
    castParts.timerFS:SetText("2.3")

    -- Cast target (right, anchored left of timer)
    castParts.targetFS = castParts.textFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(castParts.targetFS, FONT_PATH, 10, GetNPOptOutline())
    castParts.targetFS:SetPoint("RIGHT", castParts.timerFS, "LEFT", -4, 0)
    castParts.targetFS:SetJustifyH("RIGHT")
    castParts.targetFS:SetWordWrap(false)
    castParts.targetFS:SetMaxLines(1)
    castParts.targetFS:SetText(UnitName("player") or EllesmereUI.L("Spell Target"))

    -- Blizzard Style (Global Settings > Style): the stock plate look over the
    -- mock at the end of every Update, as the live plates get it -- the
    -- shadowed background art around the bar (the user's own fill texture
    -- stays), the bar's inner shadow, no EUI borders, the selection ring or
    -- deselected overlay, and the stock cast bar art. Stashed on previewGlow
    -- (an Update upvalue already) so Update stays under Lua's 60-upvalue cap.
    previewGlow.applyBlizz = function()
        local B, ok = ns.NP_BLIZZ, ns.NP_AtlasOK
        if not (B and ok) then return end
        borderFrame:Hide(); simpleBorderFrame:Hide()
        for _, e in ipairs(_solidEdges) do e:Hide() end
        if healthWrapper._customBorder then healthWrapper._customBorder:Hide() end
        if ok(B.barBg) then
            healthBG:SetAtlas(B.barBg)
            healthBG:SetVertexColor(1, 1, 1, 1)
            healthBG:ClearAllPoints()
            healthBG:SetPoint("TOPLEFT", health, "TOPLEFT", -2, 3)
            healthBG:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 6, -6)
        end
        -- The stock fill art's footprint masks the fill, the highlight
        -- wash and the shadow inside the background's rim, as live.
        local mask = previewGlow.blizzMask
        if not mask and ok(B.bar) then
            mask = health:CreateMaskTexture()
            mask:SetAtlas(B.bar)
            mask:SetAllPoints(health)
            previewGlow.blizzMask = mask
        end
        if mask then
            local fill = health:GetStatusBarTexture()
            if fill and previewGlow.blizzMaskedFill ~= fill then
                pcall(fill.RemoveMaskTexture, fill, mask)
                fill:AddMaskTexture(mask)
                previewGlow.blizzMaskedFill = fill
            end
            if not previewGlow.blizzMaskedHL then
                previewGlow.highlight:AddMaskTexture(mask)
                previewGlow.blizzMaskedHL = true
            end
        end
        if ns.NP_BlizzBarShadow then ns.NP_BlizzBarShadow(health, health:GetHeight(), mask) end
        -- Selection ring while the target glow preview is on, else the
        -- deselected overlay every other plate carries.
        local sel, desel = previewGlow.blizzSel, previewGlow.blizzDesel
        local fv = previewGlow.forever and ok(B.selYellow)
        if not sel and (fv or ok(B.selected)) and ok(B.deselected) then
            sel = health:CreateTexture(nil, "OVERLAY", nil, 5)
            if fv then
                -- WoW Forever's thin yellow ring, as live.
                sel:SetAtlas(B.selYellow)
                sel:SetPoint("TOPLEFT", healthBG, "TOPLEFT", -3, 2)
                sel:SetPoint("BOTTOMRIGHT", healthBG, "BOTTOMRIGHT", 0, 2)
            else
                sel:SetAtlas(B.selected)
                sel:SetPoint("TOPLEFT", healthBG, "TOPLEFT", -1, 1)
                sel:SetPoint("BOTTOMRIGHT", healthBG, "BOTTOMRIGHT", -3, 3)
            end
            previewGlow.blizzSel = sel
            desel = health:CreateTexture(nil, "OVERLAY", nil, 4)
            desel:SetAtlas(B.deselected)
            desel:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 1)
            desel:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, -1)
            previewGlow.blizzDesel = desel
        end
        if sel then
            if optState.showTargetGlowPreview then
                local c = NAMEPLATE_BORDER_TARGET_COLOR
                if c and c.r then sel:SetVertexColor(c.r, c.g, c.b) else sel:SetVertexColor(1, 1, 1) end
                sel:Show(); desel:Hide()
            else
                sel:Hide(); desel:Show()
            end
        end
        -- The highlight wash sits under the ring, as on the live plates.
        previewGlow.highlight:SetDrawLayer("OVERLAY", 0)
        -- Cast bar: stock background (the retail art under WoW
        -- Forever too, as live), fill art and pip; no EUI border.
        if ok(B.castBg) then
            EllesmereUI.StockAtlas(castParts.bg, B.castBg)
            castParts.bg:SetVertexColor(1, 1, 1, 1)
            castParts.bg:ClearAllPoints()
            castParts.bg:SetPoint("TOPLEFT", cast, "TOPLEFT", 1, 0)
            castParts.bg:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", -1, 0)
        end
        if ok(B.cast) then
            cast:GetStatusBarTexture():SetAtlas(B.cast)
            cast:SetStatusBarColor(1, 1, 1, 1)
        end
        if ok(B.castPip) then
            castParts.spark:SetAtlas(B.castPip)
            castParts.spark:SetWidth(4)
        end
        if PP.GetBorders(cast) then PP.HideBorder(cast) end
        castParts.icon:SetTexCoord(0, 1, 0, 1)
        -- WoW Forever: the level box right of the bar, as live
        -- (ns.NP_ApplyForeverLevelBox), with a level 60 at an even match.
        if previewGlow.forever and ok(B.lvlBg) then
            local L = ns.NP_FOREVER_LVL
            local box = previewGlow.fvBox
            if not box then
                -- The live box's own frame; the mock paints its text.
                box = ns.NP_BuildForeverLevelBox(health)
                local fs = box._fs
                -- Font BEFORE any SetText: a FontString with no font raises.
                SetPVFont(fs, FONT_PATH, L.font, GetNPOptOutline())
                fs:SetText("60")
                local c = FAIR_DIFFICULTY_COLOR
                if c and c.r then fs:SetTextColor(c.r, c.g, c.b, 1) else fs:SetTextColor(1, 0.82, 0, 1) end
                if box._sel then box._sel:SetVertexColor(L.target[1], L.target[2], L.target[3]) end
                previewGlow.fvBox = box
                -- Exposed for the click-navigation hit overlays (built
                -- after the first pf:Update()); the overlay hides with it.
                pf._fvLevelBox = box
            end
            local bh = health:GetHeight() + L.pad
            box:SetSize(L.w, bh)
            SetPVFont(box._fs, FONT_PATH, ns.NP_ForeverLevelFont(bh), GetNPOptOutline())
            -- Its target border rides the ring's preview toggle.
            if box._sel then box._sel:SetShown(optState.showTargetGlowPreview and true or false) end
            -- Show Level Box, as live.
            box:SetShown(ns.NP_ForeverBoxOn())
        end
    end
    -- Classic WoW UI: the vanilla borders over the mock, as the live plates
    -- get them (ns.NP_ApplyClassicHealthArt / CastArt): the health border
    -- with a level in its plate, the cast border with the icon in its
    -- plate, the vanilla spark; no EUI border. Same stash as applyBlizz.
    previewGlow.applyClassic = function(barH, castH)
        local C = ns.NP_CLASSIC
        if not (C and C.health and ns.NP_ClassicBorderPieces and ns.NP_SeatClassicBorder and ns.NP_ClassicLevelOffset) then return end
        borderFrame:Hide(); simpleBorderFrame:Hide()
        for _, e in ipairs(_solidEdges) do e:Hide() end
        if healthWrapper._customBorder then healthWrapper._customBorder:Hide() end
        local hp = previewGlow.classicHealthArt
        if not hp then
            local host = CreateFrame("Frame", nil, health)
            host:SetAllPoints(health)
            host:EnableMouse(false)
            host:SetFrameLevel(health:GetFrameLevel() + 6)
            hp = ns.NP_ClassicBorderPieces(host, C.health)
            previewGlow.classicHealthArt = hp
            local lv = healthTextFrame:CreateFontString(nil, "OVERLAY")
            -- Font BEFORE any SetText: a FontString with no font raises.
            SetPVFont(lv, FONT_PATH, 10, GetNPOptOutline())
            lv:SetJustifyH("CENTER")
            lv:SetText("60")
            lv:SetTextColor(1, 0.82, 0, 1)
            previewGlow.classicLevel = lv
            -- Exposed for the click-navigation hit overlays below; this
            -- runs from the build's first pf:Update(), before they build.
            pf._classicLevel = lv
            local ch = CreateFrame("Frame", nil, cast)
            ch:SetAllPoints(cast)
            ch:EnableMouse(false)
            ch:SetFrameLevel(cast:GetFrameLevel() + 2)
            previewGlow.classicCastArt = ns.NP_ClassicBorderPieces(ch, C.cast)
            castParts.iconFrame:SetFrameLevel(ch:GetFrameLevel() + 1)
        end
        local kh, kc = barH, castH
        ns.NP_SeatClassicBorder(hp, health, kh)
        ns.NP_SeatClassicBorder(previewGlow.classicCastArt, cast, kc)
        local lv = previewGlow.classicLevel
        SetPVFont(lv, FONT_PATH, ns.NP_ClassicLevelSize(kh), GetNPOptOutline())
        local lx, ly = ns.NP_ClassicLevelOffset(kh)
        lv:ClearAllPoints()
        lv:SetPoint("CENTER", health, "RIGHT", lx, ly)
        lv:Show()
        castParts.spark:SetTexture(C.spark)
        castParts.spark:SetSize(C.sparkSize * kc, C.sparkSize * kc)
        castParts.spark:ClearAllPoints()
        castParts.spark:SetPoint("CENTER", cast:GetStatusBarTexture(), "RIGHT", 0, C.sparkY * kc)
        if PP.GetBorders(cast) then PP.HideBorder(cast) end
        castParts.icon:SetTexCoord(0, 1, 0, 1)
    end

    -- Class power pips (cosmetic preview queries live class/spec resource count); packed into a single table to stay under Lua's 60-upvalue limit.
    local CP = {
        PIP_W = 8, PIP_H = 3, PIP_GAP = 2,
        EMPTY_R = 0.35, EMPTY_G = 0.35, EMPTY_B = 0.35, EMPTY_A = 0.85,
        MAX_POSSIBLE = 10,
        FILL_FRAC = 0.70,
        DEFAULT_COLOR = { 1.00, 0.84, 0.30 },
        CLASS_COLORS = {
            ROGUE       = { 1.00, 0.96, 0.41 },
            DRUID       = { 1.00, 0.49, 0.04 },
            PALADIN     = { 0.96, 0.55, 0.73 },
            MONK        = { 0.00, 1.00, 0.60 },
            WARLOCK     = { 0.58, 0.51, 0.79 },
            MAGE        = { 0.25, 0.78, 0.92 },
            EVOKER      = { 0.20, 0.58, 0.50 },
            DEMONHUNTER = { 0.34, 0.06, 0.46 },
            SHAMAN      = { 0.00, 0.44, 0.87 },
            HUNTER      = { 0.67, 0.83, 0.45 },
            WARRIOR     = { 0.78, 0.61, 0.43 },
            DEATHKNIGHT = { 0.77, 0.12, 0.23 },
        },
        CLASS_MAP = {
            ROGUE   = { Enum.PowerType.ComboPoints,   5 },
            DRUID   = { Enum.PowerType.ComboPoints,   5 },
            PALADIN = { Enum.PowerType.HolyPower,     5 },
            MONK    = { [268] = { "BREWMASTER_STAGGER", 1 },
                        [269] = { Enum.PowerType.Chi, 5 } },
            WARLOCK = { Enum.PowerType.SoulShards,     5 },
            MAGE    = { Enum.PowerType.ArcaneCharges,  4 },
            EVOKER  = { Enum.PowerType.Essence,        5 },
            DEMONHUNTER = { [581] = { "SOUL_FRAGMENTS_VENGEANCE", 6 } },
            SHAMAN  = { [263] = { "MAELSTROM_WEAPON", 10 } },
            HUNTER  = { [255] = { "TIP_OF_THE_SPEAR", 3 } },
            WARRIOR = { [72]  = { "WHIRLWIND_STACKS", 4 } },
            DEATHKNIGHT = { [250] = { Enum.PowerType.Runes, 6 },
                            [251] = { Enum.PowerType.Runes, 6 },
                            [252] = { Enum.PowerType.Runes, 6 } },
        },
        WHITE = "Interface\\Buttons\\WHITE8X8",
        SQUARE_SHAPE = { square = true, circle = true, diamond = true, hexagon = true, shield = true },
    }
    CP.pips = {}
    for i = 1, CP.MAX_POSSIBLE do
        local bg = pf:CreateTexture(nil, "OVERLAY", nil, 2)
        bg:SetTexture(CP.WHITE)
        bg:SetVertexColor(0.082, 0.082, 0.082, 1)
        bg:Hide()
        local pip = pf:CreateTexture(nil, "OVERLAY", nil, 3)
        pip:SetTexture(CP.WHITE)
        pip:SetVertexColor(1, 1, 1, 1)
        pip:SetSize(CP.PIP_W, CP.PIP_H)
        pip:Hide()
        pip._bg = bg
        CP.pips[i] = pip
    end
    -- Bar-type class resource (e.g. stagger) preview
    CP.bar = CreateFrame("StatusBar", nil, pf)
    CP.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    CP.bar:SetFrameLevel(pf:GetFrameLevel() + 5)
    CP.bar:Hide()
    CP.bar._bg = CP.bar:CreateTexture(nil, "BACKGROUND")
    CP.bar._bg:SetAllPoints()
    CP.bar._bg:SetColorTexture(0.082, 0.082, 0.082, 1)

    -- Debuffs: 2 icons centered above name
    local debuffs = {}
    local debuffData = {
        { icon = 136207, text = "8",  dur = 12, elapsed = 4, stacks = 3 },  -- SW:P  (12s total, 4s elapsed 8s left, 3 stacks)
        { icon = 135978, text = "14", dur = 18, elapsed = 4, stacks = 0 },  -- VT    (18s total, 4s elapsed 14s left)
    }
    for i = 1, PV_CONST.DEBUFF_COUNT do
        local d = CreateFrame("Frame", nil, pf)
        d:SetSize(26, 26)
        d:SetPoint("BOTTOM", nameFS, "TOP", (i - (PV_CONST.DEBUFF_COUNT + 1) / 2) * 30, 2)
        d:SetFrameLevel(health:GetFrameLevel() + 9)
        AddBorder(d)

        d.icon = d:CreateTexture(nil, "ARTWORK")
        UnsnapTex(d.icon)
        d.icon:SetPoint("TOPLEFT", d, "TOPLEFT", px, -px)
        d.icon:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -px, px)
        d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        d.icon:SetTexture(debuffData[i].icon)
        _insetIcons[#_insetIcons + 1] = { tex = d.icon, parent = d, kind = "debuffs" }

        -- Text child frame: sits above the icon frame so highlights can be sandwiched between icon artwork and text via frame levels.
        local textFrame = CreateFrame("Frame", nil, d)
        textFrame:SetAllPoints()
        textFrame:SetFrameLevel(d:GetFrameLevel() + 2)

        d.durationText = textFrame:CreateFontString(nil, "OVERLAY")
        -- Preview aura text mirrors runtime: SlugFlag drops slug when the toggle is on.
        d.durationText:SetFont(FONT_PATH, 11, EllesmereUI.SlugFlag("OUTLINE, SLUG"))
        d.durationText:SetPoint("TOPLEFT", d, "TOPLEFT", -3, 4)
        d.durationText:SetJustifyH("LEFT")
        d.durationText:SetText(debuffData[i].text)

        -- Stack count text (bottom-right)
        d.stackText = textFrame:CreateFontString(nil, "OVERLAY")
        d.stackText:SetFont(FONT_PATH, 11, EllesmereUI.SlugFlag("OUTLINE, SLUG"))
        d.stackText:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 1, 1)
        d.stackText:SetJustifyH("RIGHT")
        if debuffData[i].stacks > 0 then
            d.stackText:SetText(tostring(debuffData[i].stacks))
        else
            d.stackText:SetText("")
        end

        debuffs[i] = d
    end

    -- Buffs: 2 icons (left of health bar by default)
    local buffs = {}
    local buffData = {
        { icon = 136224, text = "12", frac = 0.20 },  -- Enrage
        { icon = 132333, text = "7",  frac = 0.45 },  -- Battle Shout
    }
    for i = 1, PV_CONST.BUFF_COUNT do
        local bf = CreateFrame("Frame", nil, pf)
        bf:SetSize(24, 24)
        bf:SetFrameLevel(health:GetFrameLevel() + 9)
        AddBorder(bf)
        bf.icon = bf:CreateTexture(nil, "ARTWORK")
        UnsnapTex(bf.icon)
        bf.icon:SetPoint("TOPLEFT", bf, "TOPLEFT", px, -px)
        bf.icon:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -px, px)
        bf.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        bf.icon:SetTexture(buffData[i].icon)
        _insetIcons[#_insetIcons + 1] = { tex = bf.icon, parent = bf, kind = "buffs" }
        local bfTextFrame = CreateFrame("Frame", nil, bf)
        bfTextFrame:SetAllPoints()
        bfTextFrame:SetFrameLevel(bf:GetFrameLevel() + 2)
        bf.durationText = bfTextFrame:CreateFontString(nil, "OVERLAY")
        bf.durationText:SetFont(FONT_PATH, 12, EllesmereUI.SlugFlag("OUTLINE, SLUG"))
        bf.durationText:SetPoint("CENTER", bf, "CENTER", 0, 0)
        bf.durationText:SetText(buffData[i].text)
        buffs[i] = bf
    end

    -- CC: 2 icons (right of health bar by default)
    local ccs = {}
    local ccData = {
        { icon = 136071, text = "5",  frac = 0.55 },  -- Polymorph
        { icon = 118699, text = "3",  frac = 0.70 },  -- Fear
    }
    for i = 1, PV_CONST.CC_COUNT do
        local cf = CreateFrame("Frame", nil, pf)
        cf:SetSize(24, 24)
        cf:SetFrameLevel(health:GetFrameLevel() + 9)
        AddBorder(cf)
        cf.icon = cf:CreateTexture(nil, "ARTWORK")
        UnsnapTex(cf.icon)
        cf.icon:SetPoint("TOPLEFT", cf, "TOPLEFT", px, -px)
        cf.icon:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -px, px)
        cf.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        cf.icon:SetTexture(ccData[i].icon)
        _insetIcons[#_insetIcons + 1] = { tex = cf.icon, parent = cf, kind = "ccs" }
        local cfTextFrame = CreateFrame("Frame", nil, cf)
        cfTextFrame:SetAllPoints()
        cfTextFrame:SetFrameLevel(cf:GetFrameLevel() + 2)
        cf.durationText = cfTextFrame:CreateFontString(nil, "OVERLAY")
        cf.durationText:SetFont(FONT_PATH, 12, EllesmereUI.SlugFlag("OUTLINE, SLUG"))
        cf.durationText:SetPoint("CENTER", cf, "CENTER", 0, 0)
        cf.durationText:SetText(ccData[i].text)
        ccs[i] = cf
    end

    -- Icon Borders cog (Custom Border on Aura Icons / on Spell Icon), as the live plates
    -- draw them: an owned border child over the icon in place of its 1px edges, the aura
    -- icon inset at 0, the plate's custom border style, size (exact px included), colour
    -- and offsets. Update calls it after the 1px edge and inset refreshes and the cast
    -- icon layout, and it overrides them only where a custom icon border draws. Stashed on
    -- previewGlow (already an Update upvalue) so Update gains no upvalue.
    do
        -- The custom border style, read once per pass by iconBorders for every icon.
        local sTex, sPath, sSz, sPx, sR, sG, sB, sA, sOX, sOY, sSX, sSY, sMult
        -- One icon, built once. ApplyBorderStyle runs only when an input it draws from
        -- changed since this icon's last paint: texture key and its resolved file, size
        -- step, exact px, colour and alpha, offsets, shifts, the pixel grid, the icon's
        -- effective scale (the anchor snap), its frame level, or its shown state. The
        -- 1px edges and the inset are reset by every Update pass, so they are overridden
        -- on every pass.
        local function paint(f, on, lvlAdd, iconTex)
            local cb = f._pvCustomBorder
            if on then
                if not cb then
                    cb = CreateFrame("Frame", nil, f)
                    cb:SetAllPoints(f)
                    f._pvCustomBorder = cb
                end
                local lvl = f:GetFrameLevel() + lvlAdd
                local es = cb:GetEffectiveScale()
                if not cb:IsShown() or cb:GetFrameLevel() ~= lvl or cb._sES ~= es
                    or cb._sMult ~= sMult or cb._sTex ~= sTex or cb._sPath ~= sPath
                    or cb._sSz ~= sSz or cb._sPx ~= sPx
                    or cb._sR ~= sR or cb._sG ~= sG or cb._sB ~= sB or cb._sA ~= sA
                    or cb._sOX ~= sOX or cb._sOY ~= sOY or cb._sSX ~= sSX or cb._sSY ~= sSY then
                    cb:SetFrameLevel(lvl)
                    EllesmereUI.ApplyBorderStyle(cb, sSz, sR, sG, sB, sA, sTex,
                        sOX, sOY, sSX, sSY, "nameplates", sSz, nil, sPx)
                    cb._sES, cb._sMult, cb._sTex, cb._sPath = es, sMult, sTex, sPath
                    cb._sSz, cb._sPx = sSz, sPx
                    cb._sR, cb._sG, cb._sB, cb._sA = sR, sG, sB, sA
                    cb._sOX, cb._sOY, cb._sSX, cb._sSY = sOX, sOY, sSX, sSY
                end
                local e = f._euiIconEdges
                if e then for k = 1, #e do e[k]:Hide() end end
                if iconTex then
                    iconTex:ClearAllPoints()
                    iconTex:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
                    iconTex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
                end
            elseif cb and cb:IsShown() then
                -- Off through ApplyBorderStyle(frame, 0), so no UI scale re-apply revives it.
                EllesmereUI.ApplyBorderStyle(cb, 0)
                cb:Hide()
            end
        end
        previewGlow.iconBorders = function(customOn, showIcon)
            if EllesmereUI._prebuilding then return end
            local ib = ns.GetIconBorderEnabled
            local db = DB()
            if (db and db.castIconSeparator) or cast._iconSeam then
                ns.NP_ApplyCastIconSeparator(cast, castParts.iconFrame, db, customOn and showIcon)
            end
            sTex = DBVal("customBorderTexture") or defaults.customBorderTexture
            sPath = EllesmereUI.ResolveBorderTexture(sTex)
            sSz = DBVal("customBorderSize") or defaults.customBorderSize
            sPx = EllesmereUI.BorderPx(db and db.customBorderSizePx, sSz, sTex)
            local ccol = (db and db.customBorderColor) or defaults.customBorderColor
            sR, sG, sB = ccol.r, ccol.g, ccol.b
            sA = DBVal("customBorderAlpha") or defaults.customBorderAlpha or 1
            sOX, sOY = DBVal("customBorderOffset"), DBVal("customBorderOffsetY")
            sSX, sSY = DBVal("customBorderShiftX"), DBVal("customBorderShiftY")
            sMult = EllesmereUI.PP.mult
            local castOn = customOn and showIcon and DBVal("castIconCustomBorder") == true
                and DBVal("castbarIconInWidth") ~= true
                and (not ib or ib("cast"))
            -- Above the icon, as the live border sits at the icon's level + 3.
            paint(castParts.iconFrame, castOn, 3)
            local auraOn = customOn and DBVal("auraIconCustomBorder") == true
            -- Under the aura text frame (icon level + 2).
            for i = 1, PV_CONST.DEBUFF_COUNT do
                paint(debuffs[i], auraOn and (not ib or ib("debuffs")), 1, debuffs[i].icon)
            end
            for i = 1, PV_CONST.BUFF_COUNT do
                paint(buffs[i], auraOn and (not ib or ib("buffs")), 1, buffs[i].icon)
            end
            for i = 1, PV_CONST.CC_COUNT do
                paint(ccs[i], auraOn and (not ib or ib("ccs")), 1, ccs[i].icon)
            end
        end
    end
    -- Core Text slot colours by the slot's Text Coloring mode. The preview is a
    -- hostile NPC at the player's level: Hostility / Class shows the Hostile name
    -- colour, Level Difficulty that level's difficulty colour (friendly levels
    -- included, as the player stands in for the mob), Custom the slot colour.
    -- lvlColor is reused by every level-mode read.
    previewGlow.lvlColor = { r = 1, g = 1, b = 1 }
    previewGlow.slotColor = function(slotKey)
        local db = DB()
        local mode = ns.NP_SlotColorMode(slotKey, db)
        if mode == "class" then
            return (db and db.enemyNameHostileColor) or defaults.hostile
        elseif mode == "level" then
            local r, g, b = EllesmereUI.GetLevelColor("player", UnitEffectiveLevel("player"), true)
            if r then
                local c = previewGlow.lvlColor
                c.r, c.g, c.b = r, g, b
                return c
            end
        end
        return (db and db[slotKey .. "Color"]) or defaults[slotKey .. "Color"]
    end

    -- Cached position values for the health bar anchor (see health block).
    local _cachedRawBarW, _cachedXOff

    -------------------------------------------------------------------
    --  Update re-reads DB, applies to existing frames. No rebuilds.
    -------------------------------------------------------------------
    pf.Update = function(self)
        local fontPath   = (EllesmereUI.GetFontPath("nameplates")) or DBVal("font")
        -- Body-text outline, already slug-gated at the source (GetFontOutlineFlag).
        local npOutline  = (EllesmereUI.GetFontOutlineFlag("nameplates")) or "OUTLINE, SLUG"
        local barH       = Snap(DBVal("healthBarHeight"))
        local rawBarW    = BAR_W + DBVal("healthBarWidth")
        local barW       = IsDragging() and rawBarW or Snap(rawBarW)
        local castH      = Snap(DBVal("castBarHeight") or defaults.castBarHeight)
        local showArrows = DBVal("showTargetArrows") == true
        local arrowStyleKey = DBVal("targetArrowStyle") or (DBVal("targetArrowDouble") and "double") or "simple"
        local arrowSt = ns.TARGET_ARROW_STYLES[arrowStyleKey] or ns.TARGET_ARROW_STYLES.simple
        local arrowScale = DBVal("targetArrowScale") or defaults.targetArrowScale or 1.0
        local arrowW = math.floor(arrowSt.w * arrowScale + 0.5)
        local arrowH = math.floor(16 * arrowScale + 0.5)
        if pf._arrows then
            local _acr, _acg, _acb = ns.GetTargetArrowColor(DB())
            pf._arrows.left:SetTexture(ns.TARGET_ARROW_DIR .. arrowSt.l .. ".png")
            pf._arrows.right:SetTexture(ns.TARGET_ARROW_DIR .. arrowSt.r .. ".png")
            pf._arrows.left:SetVertexColor(_acr, _acg, _acb)
            pf._arrows.right:SetVertexColor(_acr, _acg, _acb)
            pf._arrows.left:SetSize(arrowW, arrowH)
            pf._arrows.right:SetSize(arrowW, arrowH)
        end
        local cbColor    = (DB() and DB().castBar) or defaults.castBar
        local debuffY    = DBVal("debuffYOffset") or defaults.debuffYOffset

        -- Class power top push: extra offset for name/auras when pips sit above the bar
        local cpPush = 0
        if DBVal("showClassPower") == true then
            local cpPos = DBVal("classPowerPos") or defaults.classPowerPos
            if cpPos == "top" then
                local cpScale = DBVal("classPowerScale") or defaults.classPowerScale
                local cpYOff  = DBVal("classPowerYOffset") or defaults.classPowerYOffset
                cpPush = CP.PIP_H * cpScale + cpYOff
            end
        end
        -- Apply current random preview values (regenerated on tab switch only)
        local curHpPct = optState._previewHpPct or 70
        local curHpVal = math.floor(PV_CONST.FAKE_MAX_HP * curHpPct / 100)
        health:SetValue(curHpVal)
        local pctStr = curHpPct .. "%"
        local pctNoSignStr = tostring(curHpPct)
        local hpNumStr = tostring(curHpVal):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
        local hpMaxStr = tostring(PV_CONST.FAKE_MAX_HP):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
        -- Synthetic fractional percent so "Show % Decimal" is visible here (the fake preview HP is a whole number).
        local pctStrDec = string.format("%.1f%%", curHpPct + 0.4)
        local pctNoSignStrDec = string.format("%.1f", curHpPct + 0.4)
        -- Text on hpText/hpNumber is set later by the slot-based positioning logic
        cast:SetValue(optState._previewCastFill or 0.60)
        castParts.icon:SetTexture(displayCastIcons[optState._previewCastIconIdx or 1])
        do
            local hbgC = (DB() and DB().bgColor) or defaults.bgColor
            local hbgA = DBVal("bgAlpha") or defaults.bgAlpha
            healthBG:SetColorTexture(hbgC.r, hbgC.g, hbgC.b, hbgA)
            local cbgC = (DB() and DB().castBgColor) or defaults.castBgColor
            local cbgA = DBVal("castBgAlpha") or defaults.castBgAlpha
            castParts.bg:SetColorTexture(cbgC.r, cbgC.g, cbgC.b, cbgA)
        end

        -- Cast bar border (pixel-perfect, mirrors the real nameplates)
        do
            local cbSz = DBVal("castBorderSize") or defaults.castBorderSize or 0
            local cbC = (DB() and DB().castBorderColor) or defaults.castBorderColor
            -- Classic WoW UI: no EUI edge; the vanilla cast border is drawn at the end of Update.
            if previewGlow.classic then cbSz = 0; cbC = previewGlow.black end
            if PP and PP.CreateBorder then
                if cbSz and cbSz > 0 then
                    if PP.GetBorders(cast) then
                        PP.SetBorderColor(cast, cbC.r, cbC.g, cbC.b, 1)
                        PP.SetBorderSize(cast, cbSz)
                        PP.ShowBorder(cast)
                    else
                        PP.CreateBorder(cast, cbC.r, cbC.g, cbC.b, 1, cbSz, "OVERLAY", 7)
                    end
                elseif PP.GetBorders(cast) then
                    PP.HideBorder(cast)
                end
            end
        end

        -- Border style toggle
        local customOn = DBVal("customBorderEnabled")
        if customOn == nil then customOn = defaults.customBorderEnabled end
        -- Classic WoW UI: the plain 1px black edge, as live (no custom border).
        if previewGlow.classic then customOn = false end
        local pcb = healthWrapper._customBorder
        if customOn then
            -- Custom border (shared engine) replaces the simple preview border.
            borderFrame:Hide(); simpleBorderFrame:Hide()
            for _, e in ipairs(_solidEdges) do e:Hide() end
            if pcb and EllesmereUI.ApplyBorderStyle then
                local ctex   = DBVal("customBorderTexture") or defaults.customBorderTexture
                local csz    = DBVal("customBorderSize") or defaults.customBorderSize
                local ccol   = (DB() and DB().customBorderColor) or defaults.customBorderColor
                local ca     = DBVal("customBorderAlpha") or defaults.customBorderAlpha or 1
                local cbehind = DBVal("customBorderBehind")
                if cbehind == nil then cbehind = defaults.customBorderBehind end
                pcb:SetFrameLevel(cbehind and math.max(0, healthWrapper:GetFrameLevel() - 1) or (healthWrapper:GetFrameLevel() + 2))
                local cpx = EllesmereUI.BorderPx(DB() and DB().customBorderSizePx, csz, ctex)
                EllesmereUI.ApplyBorderStyle(pcb, csz, ccol.r, ccol.g, ccol.b, ca, ctex,
                    DBVal("customBorderOffset"), DBVal("customBorderOffsetY"),
                    DBVal("customBorderShiftX"), DBVal("customBorderShiftY"),
                    "nameplates", csz, nil, cpx)
                -- Show Seam Line, as the live wrap draws it (with or without Casts In
                -- Front of Nameplates: both draw the same single outline).
                ns.NP_SetWrapSeam(pcb, cast, DBVal("wrapBorderCastbar") == true
                    and DBVal("wrapBorderSeam") == true,
                    ctex, csz, cpx, ccol.r, ccol.g, ccol.b, ca, health)
                -- The mock cast bar sits above this border's frame: lift the seam over its
                -- fill, under its text (cast + 5), as it draws on a live plate.
                if pcb._cbSeamHost then pcb._cbSeamHost:SetFrameLevel(cast:GetFrameLevel() + 3) end
            end
        else
            if pcb and EllesmereUI.ApplyBorderStyle then
                EllesmereUI.ApplyBorderStyle(pcb, 0)
                pcb:Hide()
                ns.NP_SetWrapSeam(pcb, nil, false)
            end
            local bOn = DBVal("showBorder")
            if bOn == nil then bOn = defaults.showBorder end
            -- Classic WoW UI: no EUI edge; the vanilla health border is drawn at the end of Update.
            if previewGlow.classic then bOn = false end
            if bOn then
                borderFrame:Hide(); simpleBorderFrame:Show()
                for _, e in ipairs(_solidEdges) do e:Show() end
                simpleBorderFrame:ApplySize(previewGlow.classic and 1 or (DBVal("borderSize") or defaults.borderSize))
            else
                borderFrame:Hide(); simpleBorderFrame:Hide()
                for _, e in ipairs(_solidEdges) do e:Hide() end
            end
        end
        -- Rounded corners, as on a live plate. The image border cannot round,
        -- so a rounded Basic border draws as a Solid one on the custom border
        -- frame (the live plate's Basic border is that same Solid border).
        do
            local radius = (not EllesmereUI.BlizzStyle.Get("nameplates") and DBVal("cornerRadius")) or 0
            -- Wrap Around Castbar keeps the plates square, as on a live plate.
            if DBVal("wrapBorderCastbar") == true then radius = 0 end
            local style = customOn and (DBVal("customBorderTexture") or defaults.customBorderTexture) or "solid"
            -- A custom style that cannot round keeps the cast bar square too.
            if not EllesmereUI.RoundedStyleOK(style) then radius = 0 end
            if radius > 0 and not customOn and pcb and simpleBorderFrame:IsShown() then
                local bc = (DB() and DB().borderColor) or defaults.borderColor
                simpleBorderFrame:Hide()
                for _, e in ipairs(_solidEdges) do e:Hide() end
                pcb:Show()
                EllesmereUI.ApplyBorderStyle(pcb, DBVal("borderSize") or defaults.borderSize,
                    bc.r, bc.g, bc.b, 1, "solid")
            end
            if radius > 0 then
                EllesmereUI.RoundCorners(pf, radius, {
                    roots = {}, rect = health, border = pcb, style = style,
                    textures = { health:GetStatusBarTexture(), healthBG,
                        pvAbs.absorb:GetStatusBarTexture(), pvAbs.absorbForward:GetStatusBarTexture() },
                })
                EllesmereUI.RoundCorners(cast, radius, {
                    roots = {}, border = cast,
                    textures = { cast:GetStatusBarTexture(), castBG },
                })
            else
                EllesmereUI.RoundCorners(pf, 0)
                EllesmereUI.RoundCorners(cast, 0)
            end
        end

        -- Refresh all 1px AddBorder edges (cast icon, aura icons)
        for _, refreshFn in ipairs(_borderRefreshers) do refreshFn() end
        do
            local function setEdges(f, on)
                local e = f and f._euiIconEdges
                if not e then return end
                for i = 1, #e do e[i]:SetShown(on) end
            end
            local ib = ns.GetIconBorderEnabled
            setEdges(castParts.iconFrame, not ib or ib("cast"))
            for i = 1, PV_CONST.DEBUFF_COUNT do setEdges(debuffs[i], not ib or ib("debuffs")) end
            for i = 1, PV_CONST.BUFF_COUNT do setEdges(buffs[i], not ib or ib("buffs")) end
            for i = 1, PV_CONST.CC_COUNT do setEdges(ccs[i], not ib or ib("ccs")) end
        end

        -- Refresh icon insets (1px from border) for current scale
        local curPx = Snap(1)
        for _, entry in ipairs(_insetIcons) do
            local inset = curPx
            if entry.kind and ns.GetIconBorderEnabled and not ns.GetIconBorderEnabled(entry.kind) then
                inset = 0
            end
            entry.tex:ClearAllPoints()
            entry.tex:SetPoint("TOPLEFT", entry.parent, "TOPLEFT", inset, -inset)
            entry.tex:SetPoint("BOTTOMRIGHT", entry.parent, "BOTTOMRIGHT", -inset, inset)
        end

        local bc = (DB() and DB().borderColor) or defaults.borderColor
        if previewGlow.classic then bc = previewGlow.black end
        for _, tex in ipairs(borderFrame._texs) do tex:SetVertexColor(bc.r, bc.g, bc.b) end
        for _, tex in ipairs(simpleBorderFrame._texs) do tex:SetVertexColor(bc.r, bc.g, bc.b) end
        for _, e in ipairs(_solidEdges) do e:SetColorTexture(bc.r, bc.g, bc.b, 1); if e.SetSnapToPixelGrid then e:SetSnapToPixelGrid(false); e:SetTexelSnappingBias(0) end end

        -- "Wrap Around Castbar" preview: skipped while never enabled (borders keep their original anchoring). When on, extends the border down to the cast bar and restores anchors on toggle-off; no re-leveling needed.
        local wrapOn = DBVal("wrapBorderCastbar")
        if wrapOn == nil then wrapOn = defaults.wrapBorderCastbar end
        local borderVisible
        if customOn then
            borderVisible = true
        else
            local b = DBVal("showBorder")
            if b == nil then b = defaults.showBorder end
            borderVisible = b
        end
        if previewGlow.classic then borderVisible = true end
        local wrapActive = wrapOn and borderVisible
        if wrapActive or self._wrapPrev then
            local bottomF = healthWrapper
            if wrapActive then bottomF = cast end
            simpleBorderFrame:ClearAllPoints()
            simpleBorderFrame:SetPoint("TOPLEFT", healthWrapper, "TOPLEFT", 0, 0)
            simpleBorderFrame:SetPoint("TOPRIGHT", healthWrapper, "TOPRIGHT", 0, 0)
            simpleBorderFrame:SetPoint("BOTTOMLEFT", bottomF, "BOTTOMLEFT", 0, 0)
            simpleBorderFrame:SetPoint("BOTTOMRIGHT", bottomF, "BOTTOMRIGHT", 0, 0)
            pcb:ClearAllPoints()
            pcb:SetPoint("TOPLEFT", healthWrapper, "TOPLEFT", 0, 0)
            pcb:SetPoint("TOPRIGHT", healthWrapper, "TOPRIGHT", 0, 0)
            pcb:SetPoint("BOTTOMLEFT", bottomF, "BOTTOMLEFT", 0, 0)
            pcb:SetPoint("BOTTOMRIGHT", bottomF, "BOTTOMRIGHT", 0, 0)
            -- Solid 1px fallback edges: extend bottom + side bottoms too (_solidEdges = {top, bottom, left, right}; top is untouched).
            local sB, sL, sR = _solidEdges[2], _solidEdges[3], _solidEdges[4]
            sB:ClearAllPoints()
            sB:SetPoint("BOTTOMLEFT", bottomF, "BOTTOMLEFT", 0, 0)
            sB:SetPoint("BOTTOMRIGHT", bottomF, "BOTTOMRIGHT", 0, 0)
            sL:ClearAllPoints()
            sL:SetPoint("TOPLEFT", healthWrapper, "TOPLEFT", 0, 0)
            sL:SetPoint("BOTTOMLEFT", bottomF, "BOTTOMLEFT", 0, 0)
            sR:ClearAllPoints()
            sR:SetPoint("TOPRIGHT", healthWrapper, "TOPRIGHT", 0, 0)
            sR:SetPoint("BOTTOMRIGHT", bottomF, "BOTTOMRIGHT", 0, 0)
            self._wrapPrev = wrapActive
        end

        -- Icon sizes from slot-based system
        local debuffSlotVal = DBVal("debuffSlot") or defaults.debuffSlot
        local buffSlotVal   = DBVal("buffSlot")   or defaults.buffSlot
        local ccSlotVal     = DBVal("ccSlot")     or defaults.ccSlot
        local debuffSz = (debuffSlotVal ~= "none") and (DBVal(debuffSlotVal .. "SlotSize") or defaults[debuffSlotVal .. "SlotSize"] or 26) or 26
        local buffSz   = (buffSlotVal ~= "none") and (DBVal(buffSlotVal .. "SlotSize") or defaults[buffSlotVal .. "SlotSize"] or 24) or 24
        local ccSz     = (ccSlotVal ~= "none") and (DBVal(ccSlotVal .. "SlotSize") or defaults[ccSlotVal .. "SlotSize"] or 24) or 24

        -- Aura tier as on the live plate: auras (800) sit below the text tier (900),
        -- unless the slot's Raise Strata lifts them to HIGH, above everything else.
        -- Here: text health+10/+11, auras +9, raised auras +13 (hit overlays +15).
        do
            local hl = health:GetFrameLevel()
            for k = 1, 3 do
                local list = (k == 1 and debuffs) or (k == 2 and buffs) or ccs
                local slotVal = (k == 1 and debuffSlotVal) or (k == 2 and buffSlotVal) or ccSlotVal
                local lvl = hl + ((slotVal ~= "none" and DBVal(slotVal .. "SlotRaiseStrata")) and 13 or 9)
                for i = 1, #list do
                    local f = list[i]
                    if f:GetFrameLevel() ~= lvl then
                        f:SetFrameLevel(lvl)
                        f.durationText:GetParent():SetFrameLevel(lvl + 2)
                    end
                end
            end
        end

        -- Per-element gap between icons (user setting), then compute per-type center-to-center spacing
        local debuffGap = DBVal("debuffSpacing") or defaults.debuffSpacing
        local buffGap   = DBVal("buffSpacing")   or defaults.buffSpacing
        local ccGap     = DBVal("ccSpacing")     or defaults.ccSpacing
        local debuffSpacing = debuffGap + debuffSz
        local buffSpacing   = buffGap + buffSz
        local ccSpacing     = ccGap + ccSz

        -- Cropped icons mirror runtime: height = 80% of width + matching texcoord trim (off by default). ns.GetAuraCrop returns the height FACTOR (truthy number) when cropped, so preview follows the slider.
        local debuffCrop = ns.GetAuraCrop("debuffs")
        local buffCrop   = ns.GetAuraCrop("buffs")
        local ccCrop     = ns.GetAuraCrop("ccs")
        local debuffH = ns.GetAuraCropHeight(debuffCrop, debuffSz)
        local buffH   = ns.GetAuraCropHeight(buffCrop, buffSz)
        local ccH     = ns.GetAuraCropHeight(ccCrop, ccSz)

        -- Arrow visibility deferred until after auras are placed (arrows go OUTSIDE the outermost side aura).

        -- Raid marker position and size (slot-based)
        local rmPos = DBVal("raidMarkerPos") or defaults.raidMarkerPos
        local rmSize = (rmPos ~= "none") and (DBVal(rmPos .. "SlotSize") or defaults[rmPos .. "SlotSize"] or 24) or 24
        local rmXOff, rmYOff = 0, 0
        if rmPos ~= "none" then
            rmXOff = DBVal(rmPos .. "SlotXOffset") or 0
            rmYOff = DBVal(rmPos .. "SlotYOffset") or 0
        end

        -- Classification slot
        local clPos = DBVal("classificationSlot") or defaults.classificationSlot

        -- Clear drag-show flags when not dragging
        if not IsDragging() then
            optState._sliderDragShowRaidMarker = false
            optState._sliderDragShowClassification = false
        end

        local showRM = optState.showRaidMarkerPreview or optState._sliderDragShowRaidMarker

        -- Cast spell icon settings (mirror ns.GetCastIconReserve), computed once and reused by the core icons, cast bar, and target arrows below; barH/castH are already-snapped profile numbers in scope.
        local icdb = DB()
        local showIcon = true
        if icdb and icdb.showCastIcon ~= nil then showIcon = icdb.showCastIcon end
        local iconInWidth = defaults.castbarIconInWidth
        if icdb and icdb.castbarIconInWidth ~= nil then iconInWidth = icdb.castbarIconInWidth end
        local onRight = (icdb and icdb.castIconOnRight) or false
        local fullSize = (icdb and icdb.castIconFullSize) or false
        local iconScale = (icdb and icdb.castIconScale) or defaults.castIconScale
        local iconXOff = (icdb and icdb.castIconOffsetX) or defaults.castIconOffsetX or 0
        local iconYOff = (icdb and icdb.castIconOffsetY) or defaults.castIconOffsetY or 0
        local castIconLeftPush, castIconRightPush = 0, 0
        if previewGlow.classic then
            -- Classic WoW UI, as live: the spell icon sits inside the cast
            -- border's own plate and reserves nothing of its own, while the
            -- border art counts as part of the bar on both sides.
            castIconLeftPush, castIconRightPush = ns.NP_ClassicBarReserve()
        elseif showIcon then
            if fullSize then
                if onRight then castIconRightPush = barH + castH
                else castIconLeftPush = barH + castH end
            elseif onRight and not iconInWidth then
                castIconRightPush = castH * iconScale
            end
        end
        -- WoW Forever, as live: right-side elements clear the level box
        -- (it never counts for centring).
        if previewGlow.forever then castIconRightPush = castIconRightPush + ns.NP_ForeverSide() end

        raidFrame:ClearAllPoints()
        raidFrame:SetSize(rmSize, rmSize)
        if rmPos == "none" or not showRM then
            raidFrame:Hide()
            if pf._raidOverlay then pf._raidOverlay:Hide() end
        else
            if rmPos == "top" then
                raidFrame:SetPoint("BOTTOM", health, "TOP", rmXOff, debuffY + cpPush + rmYOff)
            elseif rmPos == "left" then
                local sideOff = DBVal("sideAuraXOffset") or defaults.sideAuraXOffset
                raidFrame:SetPoint("RIGHT", health, "LEFT", -sideOff - castIconLeftPush + rmXOff, rmYOff)
            elseif rmPos == "right" then
                local sideOff = DBVal("sideAuraXOffset") or defaults.sideAuraXOffset
                raidFrame:SetPoint("LEFT", health, "RIGHT", sideOff + castIconRightPush + rmXOff, rmYOff)
            elseif rmPos == "topleft" then
                raidFrame:SetPoint("BOTTOMLEFT", health, "TOPLEFT", rmXOff, cpPush + rmYOff)
            elseif rmPos == "topright" then
                raidFrame:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", rmXOff, cpPush + rmYOff)
            elseif rmPos == "bottom" then
                raidFrame:SetPoint("TOP", cast, "BOTTOM", rmXOff, -2 + rmYOff)
            end
            raidFrame:SetAlpha(1)
            raidFrame:Show()
            if pf._raidOverlay then pf._raidOverlay:Show() end
        end

        -- Classification icon (elite dragon) slot-based
        classIcon:ClearAllPoints()
        local clXOff, clYOff = 0, 0
        if clPos ~= "none" then
            clXOff = DBVal(clPos .. "SlotXOffset") or 0
            clYOff = DBVal(clPos .. "SlotYOffset") or 0
        end
        local reIconSz = (clPos ~= "none") and (DBVal(clPos .. "SlotSize") or defaults[clPos .. "SlotSize"] or 20) or 20
        local showCL = optState.showClassificationPreview or optState._sliderDragShowClassification
        classIcon:SetSize(reIconSz, reIconSz)
        if clPos == "none" or not showCL then
            classIcon:Hide()
            if pf._classOverlay then pf._classOverlay:Hide() end
        else
            if clPos == "top" then
                classIcon:SetPoint("BOTTOM", health, "TOP", clXOff, debuffY + cpPush + clYOff)
            elseif clPos == "left" then
                local sideOff = DBVal("sideAuraXOffset") or defaults.sideAuraXOffset
                classIcon:SetPoint("RIGHT", health, "LEFT", -sideOff - castIconLeftPush + clXOff, clYOff)
            elseif clPos == "right" then
                local sideOff = DBVal("sideAuraXOffset") or defaults.sideAuraXOffset
                classIcon:SetPoint("LEFT", health, "RIGHT", sideOff + castIconRightPush + clXOff, clYOff)
            elseif clPos == "topleft" then
                classIcon:SetPoint("BOTTOMLEFT", health, "TOPLEFT", clXOff, 2 + cpPush + clYOff)
            elseif clPos == "topright" then
                classIcon:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", clXOff, 2 + cpPush + clYOff)
            elseif clPos == "bottom" then
                classIcon:SetPoint("TOP", cast, "BOTTOM", clXOff, -2 + clYOff)
            end
            -- The quest mark while the Rare Indicator is off (or under the WoW
            -- Forever look, whose plates show no elite or rare marks).
            if DBVal("classificationHideRare") or EllesmereUI.BlizzStyle.Forever("nameplates") then
                classIcon:SetAtlas("Crosshair_Quest_64")
            else
                classIcon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\elite-rare-indicator.png")
                classIcon:SetTexCoord(0, 1, 0, 1)
            end
            classIcon:Show()
            if pf._classOverlay then pf._classOverlay:Show() end
        end

        -- Faction badge, slot-based like the classification icon above. Shows the
        -- other faction's badge (what Opposite Faction Only would show).
        local fcCombined = DBVal("classificationIncludeFaction") == true
        local fcPos = fcCombined and clPos or (DBVal("factionSlot") or defaults.factionSlot or "none")
        factionIcon:ClearAllPoints()
        if fcPos == "none" then
            factionIcon:Hide()
            if pf._factionOverlay then pf._factionOverlay:Hide() end
        else
            local fcX = DBVal(fcPos .. "SlotXOffset") or 0
            local fcY = DBVal(fcPos .. "SlotYOffset") or 0
            local fcSz = DBVal(fcPos .. "SlotSize") or defaults[fcPos .. "SlotSize"] or 20
            -- Sharing the slot with a showing Rare/Quest icon: stack behind it,
            -- overlapping by 40%, up or down in the Bottom slot (matches
            -- NameplateFrame:UpdateFaction).
            if fcCombined and classIcon:IsShown() then
                local step = math.floor(reIconSz * 0.6 + 0.5)
                fcY = fcY + ((fcPos == "bottom") and -step or step)
            end
            local mine = UnitFactionGroup("player")
            local fac = (mine == "Horde") and "Alliance" or "Horde"
            EllesmereUI.SetFactionArt(factionIcon, DBVal("factionStyle") or defaults.factionStyle, fac)
            factionIcon:SetSize(fcSz, fcSz)
            if fcPos == "top" then
                factionIcon:SetPoint("BOTTOM", health, "TOP", fcX, debuffY + cpPush + fcY)
            elseif fcPos == "left" then
                local sideOff = DBVal("sideAuraXOffset") or defaults.sideAuraXOffset
                factionIcon:SetPoint("RIGHT", health, "LEFT", -sideOff - castIconLeftPush + fcX, fcY)
            elseif fcPos == "right" then
                local sideOff = DBVal("sideAuraXOffset") or defaults.sideAuraXOffset
                factionIcon:SetPoint("LEFT", health, "RIGHT", sideOff + castIconRightPush + fcX, fcY)
            elseif fcPos == "topleft" then
                factionIcon:SetPoint("BOTTOMLEFT", health, "TOPLEFT", fcX, 2 + cpPush + fcY)
            elseif fcPos == "topright" then
                factionIcon:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", fcX, 2 + cpPush + fcY)
            elseif fcPos == "bottom" then
                factionIcon:SetPoint("TOP", cast, "BOTTOM", fcX, -2 + fcY)
            end
            factionIcon:Show()
            if pf._factionOverlay then pf._factionOverlay:Show() end
        end

        -- Arrow positioning happens after all auras are placed (arrows sit OUTSIDE the auras).

        -- Cast bar spans the health bar width. With "Make Icon Part of the Bar" it shrinks + shifts right so the icon (anchored to its left edge) sits inside the width; otherwise the icon hangs outside.
        local pIconW = 0
        local pShiftX = 0
        local pCastW = barW
        local pCastY = (DBVal("castBarOffsetY") or defaults.castBarOffsetY)
        if previewGlow.classic and ns.NP_ClassicCastLayout then
            -- Classic WoW UI, as live (ns.LayoutCastBar): the vanilla cast border
            -- hangs under the health border, plate under plain end, the stock gap lower.
            local drop
            pShiftX, pCastW, drop = ns.NP_ClassicCastLayout(barW, barH, castH)
            pCastY = pCastY + drop
        elseif showIcon and iconInWidth and not fullSize then
            pIconW = castH * iconScale
            if not onRight then pShiftX = pIconW end
        end
        cast:ClearAllPoints()
        cast:SetSize(math.max(1, pCastW - pIconW), castH)
        cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", pShiftX, pCastY)
        do
            local cTexKey = DBVal("castBarTexture") or "none"
            local cTexPath = EllesmereUI.ResolveTexturePath(ns.healthBarTextures, cTexKey, "Interface\\Buttons\\WHITE8x8")
            cast:SetStatusBarTexture(cTexPath)
            UnsnapTex(cast:GetStatusBarTexture())
        end
        cast:SetStatusBarColor(cbColor.r, cbColor.g, cbColor.b, 1)
        -- Cast icon: size/anchor per side or full-size; SetSize (not SetScale) keeps AddBorder pixel-perfect. Full-size pins to the cast bottom so the square reaches the health top (zero-gap bar stack).
        castParts.iconFrame:ClearAllPoints()
        castParts.iconFrame:SetScale(1)
        if showIcon and previewGlow.classic and ns.NP_ClassicIconOffset then
            -- Classic WoW UI, as live (ns.LayoutCastIcon): the icon in the
            -- vanilla cast border's plate.
            local C = ns.NP_CLASSIC
            local ix, iy = ns.NP_ClassicIconOffset(castH)
            castParts.iconFrame:SetSize(C.icon * castH, C.icon * castH)
            castParts.iconFrame:SetPoint("CENTER", cast, "LEFT", ix + iconXOff, iy + iconYOff)
            castParts.iconFrame:Show()
        elseif showIcon then
            if fullSize then
                local fs = barH + castH
                castParts.iconFrame:SetSize(fs, fs)
                if onRight then
                    castParts.iconFrame:SetPoint("BOTTOMLEFT", cast, "BOTTOMRIGHT", iconXOff, iconYOff)
                else
                    castParts.iconFrame:SetPoint("BOTTOMRIGHT", cast, "BOTTOMLEFT", iconXOff, iconYOff)
                end
            else
                local scaledH = castH * iconScale
                castParts.iconFrame:SetSize(scaledH, scaledH)
                if onRight then
                    castParts.iconFrame:SetPoint("TOPLEFT", cast, "TOPRIGHT", iconXOff, iconYOff)
                else
                    castParts.iconFrame:SetPoint("TOPRIGHT", cast, "TOPLEFT", iconXOff, iconYOff)
                end
            end
            castParts.iconFrame:Show()
        else
            castParts.iconFrame:SetSize(castH, castH)
            castParts.iconFrame:SetPoint("TOPRIGHT", cast, "TOPLEFT", 0, 0)
            castParts.iconFrame:Hide()
        end
        -- Custom icon borders (Icon Borders cog), over the 1px edges and insets set above.
        previewGlow.iconBorders(customOn, showIcon)
        -- The classic spark is a square sized by applyClassic below.
        if not previewGlow.classic then castParts.spark:SetHeight(castH) end
        -- Show Spark (Cast Color cog): default on; explicit false hides it.
        castParts.spark:SetShown(DBVal("castBarSparkEnabled") ~= false)

        -- Name font + color + position (font size set per-slot below)
        local nameYOff = DBVal("nameYOffset") or defaults.nameYOffset

        -- Slot-based text positioning Read slot assignments
        local slotTop    = DBVal("textSlotTop") or defaults.textSlotTop
        local slotRight  = DBVal("textSlotRight") or defaults.textSlotRight
        local slotLeft   = DBVal("textSlotLeft") or defaults.textSlotLeft
        local slotCenter = DBVal("textSlotCenter") or defaults.textSlotCenter
        local slotBL = DBVal("textSlotBottomLeft") or defaults.textSlotBottomLeft
        local slotBR = DBVal("textSlotBottomRight") or defaults.textSlotBottomRight

        -- Hide all text elements first
        nameFS:Hide()
        hpText:Hide()
        hpNumber:Hide()
        lvlText:Hide()
        pf._totFS:Hide()
        nameFS:ClearAllPoints()
        hpText:ClearAllPoints()
        hpNumber:ClearAllPoints()
        lvlText:ClearAllPoints()
        pf._totFS:ClearAllPoints()

        -- Helper: position a health-related element in a bar slot
        local function PlaceHealthInBar(element, anchor, point, xOff, yOff, fontSize, cr, cg, cb, slotKey)
            yOff = yOff or 0
            local dec = slotKey and DBVal(slotKey .. "PctDecimal") == true
            if element == "healthPercent" or element == "healthPercentNoSign" then
                SetPVFont(hpText, fontPath, fontSize, npOutline)
                hpText:SetParent(healthTextFrame)
                hpText:SetText(element == "healthPercentNoSign" and (dec and pctNoSignStrDec or pctNoSignStr) or (dec and pctStrDec or pctStr))
                hpText:SetPoint(point, health, anchor, xOff, yOff)
                hpText:SetTextColor(cr, cg, cb, 1)
                hpText:Show()
            elseif element == "healthNumber" then
                SetPVFont(hpNumber, fontPath, fontSize, npOutline)
                hpNumber:SetParent(healthTextFrame)
                hpNumber:SetText(hpNumStr)
                hpNumber:SetPoint(point, health, anchor, xOff, yOff)
                hpNumber:SetTextColor(cr, cg, cb, 1)
                hpNumber:Show()
            elseif ns.IsComboHealthText(element) then
                SetPVFont(hpText, fontPath, fontSize, npOutline)
                hpText:SetParent(healthTextFrame)
                ns.SetCombinedHealthText(hpText, element, dec and pctStrDec or pctStr, hpNumStr, hpMaxStr)
                hpText:SetPoint(point, health, anchor, xOff, yOff)
                hpText:SetTextColor(cr, cg, cb, 1)
                hpText:Show()
            elseif element == "level" or element == "targetOfTarget" then
                local fs = (element == "level") and lvlText or pf._totFS
                if fs ~= lvlText then cr, cg, cb = pf._totSampleColor(slotKey, cr, cg, cb) end
                SetPVFont(fs, fontPath, fontSize, npOutline)
                if fs ~= lvlText then fs:SetText(pf._totSample(slotKey)) end
                fs:SetParent(healthTextFrame)
                fs:SetPoint(point, health, anchor, xOff, yOff)
                fs:SetTextColor(cr, cg, cb, 1)
                fs:Show()
            end
            -- Per-slot Width % + Wrap mirrors runtime. At 100% (default) the FontString stays UNCONSTRAINED (SetWidth 0): a width box on a single-point-anchored FontString ignores SetJustifyH and drifts to centre, so only impose one below 100%.
            local hfs = (element == "healthNumber") and hpNumber
                or (element == "level") and lvlText
                or (element == "targetOfTarget") and pf._totFS or hpText
            -- Bottom slots anchor by a top corner; justify by its side.
            hfs:SetJustifyH((point == "TOPLEFT" and "LEFT") or (point == "TOPRIGHT" and "RIGHT") or point)
            -- The bottom slots never truncate (no Width % or Wrap), as live.
            local noClip = slotKey == "textSlotBottomLeft" or slotKey == "textSlotBottomRight"
            local hwpct = (not noClip and slotKey and DBVal(slotKey .. "WidthPct")) or 100
            local hw = 0
            if hwpct < 100 then hw = barW * hwpct / 100 end
            hfs:SetWidth(hw)
            local hwrap = false
            if not noClip and slotKey and DBVal(slotKey .. "Wrap") == true then hwrap = true end
            hfs:SetWordWrap(hwrap)
            hfs:SetMaxLines(hwrap and 2 or 1)
        end

        -- Helper: position a health-related element in the top slot
        local function PlaceHealthOnTop(element, txOff, tyOff, fontSize, cr, cg, cb, slotKey)
            txOff = txOff or 0
            tyOff = tyOff or 0
            local dec = slotKey and DBVal(slotKey .. "PctDecimal") == true
            if element == "healthPercent" or element == "healthPercentNoSign" then
                SetPVFont(hpText, fontPath, fontSize, npOutline)
                hpText:SetText(element == "healthPercentNoSign" and (dec and pctNoSignStrDec or pctNoSignStr) or (dec and pctStrDec or pctStr))
                hpText:SetParent(topTextFrame)
                hpText:SetPoint("BOTTOM", health, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
                hpText:SetTextColor(cr, cg, cb, 1)
                hpText:Show()
            elseif element == "healthNumber" then
                SetPVFont(hpNumber, fontPath, fontSize, npOutline)
                hpNumber:SetText(hpNumStr)
                hpNumber:SetParent(topTextFrame)
                hpNumber:SetPoint("BOTTOM", health, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
                hpNumber:SetTextColor(cr, cg, cb, 1)
                hpNumber:Show()
            elseif ns.IsComboHealthText(element) then
                SetPVFont(hpText, fontPath, fontSize, npOutline)
                ns.SetCombinedHealthText(hpText, element, dec and pctStrDec or pctStr, hpNumStr, hpMaxStr)
                hpText:SetParent(topTextFrame)
                hpText:SetPoint("BOTTOM", health, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
                hpText:SetTextColor(cr, cg, cb, 1)
                hpText:Show()
            elseif element == "level" or element == "targetOfTarget" then
                local fs = (element == "level") and lvlText or pf._totFS
                if fs ~= lvlText then cr, cg, cb = pf._totSampleColor(slotKey, cr, cg, cb) end
                SetPVFont(fs, fontPath, fontSize, npOutline)
                if fs ~= lvlText then fs:SetText(pf._totSample(slotKey)) end
                fs:SetParent(topTextFrame)
                fs:SetPoint("BOTTOM", health, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
                fs:SetTextColor(cr, cg, cb, 1)
                fs:Show()
            end
            -- Per-slot Width % + Wrap mirrors runtime. Top slot is centered and stays unconstrained at 100% (see PlaceHealthInBar for why a width box mis-positions the text).
            local hfs = (element == "healthNumber") and hpNumber
                or (element == "level") and lvlText
                or (element == "targetOfTarget") and pf._totFS or hpText
            hfs:SetJustifyH("CENTER")
            local hwpct = (slotKey and DBVal(slotKey .. "WidthPct")) or 100
            local hw = 0
            if hwpct < 100 then hw = barW * hwpct / 100 end
            hfs:SetWidth(hw)
            local hwrap = false
            if slotKey and DBVal(slotKey .. "Wrap") == true then hwrap = true end
            hfs:SetWordWrap(hwrap)
            hfs:SetMaxLines(hwrap and 2 or 1)
        end

        -- Enemy name truncation mirrors runtime (width % of bar-derived width + wrap toggle), applied to the shared preview name FontString.
        local pvNameWPct = DBVal("enemyNameWidthPct") or defaults.enemyNameWidthPct
        local pvNameWrap = DBVal("enemyNameWrap") == true
        nameFS:SetWordWrap(pvNameWrap)
        nameFS:SetNonSpaceWrap(false)
        nameFS:SetMaxLines(pvNameWrap and 2 or 1)
        local pvNameMarkerEnabled = DBVal("nameRaidMarkerEnabled") == true
        local pvNameMarkerSize = DBVal("nameRaidMarkerSize") or defaults.nameRaidMarkerSize or 14
        local pvNameMarkerReserve = pvNameMarkerEnabled and (pvNameMarkerSize + NAME_RAID_MARKER_GAP) or 0
        local pvNameSlotKey

        local function LayoutPreviewNameRaidMarker()
            if not (pvNameMarkerEnabled and pvNameSlotKey and nameFS:IsShown()) then
                nameRaidFrame:Hide()
                return
            end
            nameRaidFrame:SetParent((pvNameSlotKey == "textSlotTop") and topTextFrame or healthTextFrame)
            nameRaidFrame:SetFrameLevel(health:GetFrameLevel() + 12)
            nameRaidFrame:SetSize(pvNameMarkerSize, pvNameMarkerSize)
            nameRaidFrame:ClearAllPoints()
            nameRaidFrame:SetPoint("RIGHT", nameFS, "LEFT", -NAME_RAID_MARKER_GAP, 0)
            if SetRaidTargetIconTexture then SetRaidTargetIconTexture(nameRaidIcon, 1) end
            nameRaidFrame:Show()
        end

        -- Helper: position the name in a bar slot
        local function PlaceNameInBar(anchor, point, xOff, justify, txOff, tyOff, fontSize, cr, cg, cb, nameSlotKey)
            txOff = txOff or 0
            tyOff = tyOff or 0
            pvNameSlotKey = nameSlotKey
            local markerShift = 0
            if pvNameMarkerEnabled then
                markerShift = (justify == "LEFT") and pvNameMarkerReserve or ((justify == "CENTER") and (pvNameMarkerReserve * 0.5) or 0)
            end
            SetPVFont(nameFS, fontPath, fontSize, npOutline)
            nameFS:SetParent(healthTextFrame)
            nameFS:SetPoint(point, health, anchor, xOff + txOff + markerShift, tyOff)
            nameFS:SetJustifyH(justify)
            if nameSlotKey == "textSlotBottomLeft" or nameSlotKey == "textSlotBottomRight" then
                -- Under the bar the name never truncates (no width box, one line), as live.
                nameFS:SetWidth(0)
                nameFS:SetWordWrap(false)
                nameFS:SetMaxLines(1)
            else
                -- Estimate health text width in opposing bar slots
                local usedWidth = 0
                local barSlotInfo = {
                    { key = "textSlotRight",  slot = slotRight },
                    { key = "textSlotLeft",   slot = slotLeft },
                    { key = "textSlotCenter", slot = slotCenter },
                }
                for _, info in ipairs(barSlotInfo) do
                    if info.key ~= nameSlotKey then
                        local el = info.slot
                        if el ~= "none" and not ns.IsNameElement(el) then
                            usedWidth = usedWidth + ns.EstimateHealthTextWidth(el)
                        end
                    end
                end
                nameFS:SetWidth(math.max((barW - usedWidth - pvNameMarkerReserve) * pvNameWPct / 100, 20))
            end
            nameFS:SetTextColor(cr, cg, cb, 1)
            nameFS:Show()
        end

        -- Process top slot
        local topXOff = DBVal("textSlotTopXOffset") or 0
        local topYOff = DBVal("textSlotTopYOffset") or 0
        local topFontSz = DBVal("textSlotTopSize") or defaults.textSlotTopSize
        local topC = previewGlow.slotColor("textSlotTop")
        if ns.IsNameElement(slotTop) then
            pvNameSlotKey = "textSlotTop"
            SetPVFont(nameFS, fontPath, topFontSz, npOutline)
            nameFS:SetParent(topTextFrame)
            nameFS:SetPoint("BOTTOM", health, "TOP", topXOff + (pvNameMarkerReserve * 0.5), 4 + nameYOff + cpPush + topYOff)
            nameFS:SetJustifyH("CENTER")
            local nameW = barW - pvNameMarkerReserve
            if rmPos ~= "none" and showRM then
                nameW = nameW - 2 * (rmSize - 2) - 7
            end
            if showCL and clPos ~= "none" then
                nameW = nameW - (reIconSz + 4)
            end
            nameFS:SetWidth(math.max(nameW * pvNameWPct / 100, 20))
            nameFS:SetTextColor(topC.r, topC.g, topC.b, 1)
            nameFS:Show()
        else
            PlaceHealthOnTop(slotTop, topXOff, topYOff, topFontSz, topC.r, topC.g, topC.b, "textSlotTop")
        end

        -- Process right slot
        local rightXOff = DBVal("textSlotRightXOffset") or 0
        local rightYOff = DBVal("textSlotRightYOffset") or 0
        local rightFontSz = DBVal("textSlotRightSize") or defaults.textSlotRightSize
        local rightC = previewGlow.slotColor("textSlotRight")
        if ns.IsNameElement(slotRight) then
            PlaceNameInBar("RIGHT", "RIGHT", -2, "RIGHT", rightXOff, rightYOff, rightFontSz, rightC.r, rightC.g, rightC.b, "textSlotRight")
        else
            PlaceHealthInBar(slotRight, "RIGHT", "RIGHT", -2 + rightXOff, rightYOff, rightFontSz, rightC.r, rightC.g, rightC.b, "textSlotRight")
        end

        -- Process left slot
        local leftXOff = DBVal("textSlotLeftXOffset") or 0
        local leftYOff = DBVal("textSlotLeftYOffset") or 0
        local leftFontSz = DBVal("textSlotLeftSize") or defaults.textSlotLeftSize
        local leftC = previewGlow.slotColor("textSlotLeft")
        if ns.IsNameElement(slotLeft) then
            PlaceNameInBar("LEFT", "LEFT", 4, "LEFT", leftXOff, leftYOff, leftFontSz, leftC.r, leftC.g, leftC.b, "textSlotLeft")
        else
            PlaceHealthInBar(slotLeft, "LEFT", "LEFT", 4 + leftXOff, leftYOff, leftFontSz, leftC.r, leftC.g, leftC.b, "textSlotLeft")
        end

        -- Process center slot
        local centerXOff = DBVal("textSlotCenterXOffset") or 0
        local centerYOff = DBVal("textSlotCenterYOffset") or 0
        local centerFontSz = DBVal("textSlotCenterSize") or defaults.textSlotCenterSize
        local centerC = previewGlow.slotColor("textSlotCenter")
        if ns.IsNameElement(slotCenter) then
            PlaceNameInBar("CENTER", "CENTER", 0, "CENTER", centerXOff, centerYOff, centerFontSz, centerC.r, centerC.g, centerC.b, "textSlotCenter")
        else
            PlaceHealthInBar(slotCenter, "CENTER", "CENTER", centerXOff, centerYOff, centerFontSz, centerC.r, centerC.g, centerC.b, "textSlotCenter")
        end

        -- Process the bottom slots: under the health bar's corners, below the
        -- cast bar (the preview always shows one), as live while casting.
        do
            -- Clamped at 0 like live: a raised cast bar never lifts them.
            local by = math.min(0, pCastY - castH) - 2
            local ext = 0
            for i = 1, 2 do
                local key = (i == 1) and "textSlotBottomLeft" or "textSlotBottomRight"
                local el = (i == 1) and slotBL or slotBR
                local corner = (i == 1) and "LEFT" or "RIGHT"
                local c = previewGlow.slotColor(key)
                local sz = DBVal(key .. "Size") or defaults[key .. "Size"]
                local bx, byo = DBVal(key .. "XOffset") or 0, by + (DBVal(key .. "YOffset") or 0)
                if ns.IsNameElement(el) then
                    PlaceNameInBar("BOTTOM" .. corner, "TOP" .. corner, 0, corner, bx, byo, sz, c.r, c.g, c.b, key)
                elseif el ~= "none" then
                    PlaceHealthInBar(el, "BOTTOM" .. corner, "TOP" .. corner, bx, byo, sz, c.r, c.g, c.b, key)
                end
                if el ~= "none" then ext = math.max(ext, sz + 2 - (DBVal(key .. "YOffset") or 0)) end
            end
            -- Read by the preview height below (a table field: no new pf.Update local).
            previewGlow.botTextH = ext
        end
        -- Preview sample for whichever name-family variant is slotted (player level stands in for mob level), run after slot branches so text re-flows under the new justify (SetJustifyH alone won't re-flow it). The name slot's key carries its Level | Name part colours.
        ns.SetNameElementText(nameFS,
            (ns.IsNameElement(slotTop) and slotTop)
            or (ns.IsNameElement(slotRight) and slotRight)
            or (ns.IsNameElement(slotLeft) and slotLeft)
            or (ns.IsNameElement(slotCenter) and slotCenter)
            or (ns.IsNameElement(slotBL) and slotBL)
            or (ns.IsNameElement(slotBR) and slotBR)
            or "enemyName",
            -- WoW Forever: the slot's Name Format, as live (nil function off Forever).
            ns.NP_FormatName and ns.NP_FormatName(EllesmereUI.L("Enemy Name Text"), pvNameSlotKey)
                or EllesmereUI.L("Enemy Name Text"), "player", pvNameSlotKey)
        ns.ReflowFontString(nameFS)
        if DBVal("hideEnemyNameWhileCasting") == true then nameFS:Hide() end
        LayoutPreviewNameRaidMarker()
        PreviewNameStrata(pf, health, nameFS, nameRaidFrame,
            pvNameSlotKey and DBVal(pvNameSlotKey .. "Strata") or "MEDIUM")

        -- Health bar color: always uses "enemies in combat" color
        local eic = (DB() and DB().enemyInCombat) or defaults.enemyInCombat
        health:SetStatusBarColor(eic.r, eic.g, eic.b, 1)

        -- Cast text sizes, colors, and offsets
        local cns = DBVal("castNameSize") or defaults.castNameSize
        local cts = DBVal("castTargetSize") or defaults.castTargetSize
        local cnc = (DB() and DB().castNameColor) or defaults.castNameColor
        local ctmSz = DBVal("castTimerSize") or defaults.castTimerSize
        local ctmC = (DB() and DB().castTimerColor) or defaults.castTimerColor
        local cnOX = DBVal("castNameOffsetX") or defaults.castNameOffsetX
        local cnOY = DBVal("castNameOffsetY") or defaults.castNameOffsetY
        local ctOX = DBVal("castTargetOffsetX") or defaults.castTargetOffsetX
        local ctOY = DBVal("castTargetOffsetY") or defaults.castTargetOffsetY
        local tmOX = DBVal("castTimerOffsetX") or defaults.castTimerOffsetX
        local tmOY = DBVal("castTimerOffsetY") or defaults.castTimerOffsetY
        SetPVFont(castParts.nameFS, fontPath, cns, npOutline)
        SetPVFont(castParts.targetFS, fontPath, cts, npOutline)
        SetPVFont(castParts.timerFS, fontPath, ctmSz, npOutline)
        castParts.timerFS:SetTextColor(ctmC.r, ctmC.g, ctmC.b, 1)
        castParts.nameFS:SetTextColor(cnc.r, cnc.g, cnc.b, 1)
        local dbRef = DB()
        local pvShowTimer = defaults.showCastTimer
        if dbRef and dbRef.showCastTimer ~= nil then pvShowTimer = dbRef.showCastTimer end
        local pvNameSide   = (dbRef and dbRef.castNameSide)   or defaults.castNameSide
        local pvTargetSide = (dbRef and dbRef.castTargetSide) or defaults.castTargetSide
        local pvTimerSide  = (dbRef and dbRef.castTimerSide)  or defaults.castTimerSide
        local pvCombine = dbRef and dbRef.castCombineNameTarget == true
        local pvTimerW = ctmSz * 2.2
        -- Per-element cast text truncation (% of cast bar width + wrap), mirroring runtime.
        local pvNameTextW = barW * (DBVal("castNameWidthPct") or defaults.castNameWidthPct) / 100
        local pvTgtTextW  = barW * (DBVal("castTargetWidthPct") or defaults.castTargetWidthPct) / 100
        local pvCNameWrap = DBVal("castNameWrap") == true
        local pvCTgtWrap  = DBVal("castTargetWrap") == true
        castParts.nameFS:SetWordWrap(pvCNameWrap)
        castParts.nameFS:SetMaxLines(pvCNameWrap and 2 or 1)
        castParts.targetFS:SetWordWrap(pvCTgtWrap)
        castParts.targetFS:SetNonSpaceWrap(false)
        castParts.targetFS:SetMaxLines(pvCTgtWrap and 2 or 1)
        -- Spell name
        castParts.nameFS:ClearAllPoints()
        if pvNameSide == "none" then
            castParts.nameFS:Hide()
        else
            local pt, xb, jh = ns.GetCastTextAnchor(pvNameSide, pvShowTimer and pvTimerSide == pvNameSide, pvTimerW, false)
            castParts.nameFS:SetWidth(pvCombine and (barW * 0.80) or pvNameTextW)
            castParts.nameFS:SetJustifyH(jh)
            castParts.nameFS:SetPoint(pt, cast, pt, xb + cnOX, cnOY)
            castParts.nameFS:Show()
        end
        -- Spell target
        castParts.targetFS:ClearAllPoints()
        if pvCombine or pvTargetSide == "none" then
            castParts.targetFS:Hide()
        else
            local pt, xb, jh = ns.GetCastTextAnchor(pvTargetSide, pvShowTimer and pvTimerSide == pvTargetSide, pvTimerW, false)
            castParts.targetFS:SetWidth(pvTgtTextW)
            castParts.targetFS:SetJustifyH(jh)
            castParts.targetFS:SetPoint(pt, cast, pt, xb + ctOX, ctOY)
            castParts.targetFS:Show()
        end
        -- Cast timer (side only "left"/"right"; visibility via showCastTimer)
        castParts.timerFS:ClearAllPoints()
        if pvShowTimer then
            local tpt, txb, tjh = ns.GetCastTextAnchor(pvTimerSide, false, pvTimerW, true)
            castParts.timerFS:SetWidth(pvTimerW)
            castParts.timerFS:SetJustifyH(tjh)
            castParts.timerFS:SetPoint(tpt, cast, tpt, txb + tmOX, tmOY)
            castParts.timerFS:Show()
        else
            castParts.timerFS:Hide()
        end
        -- Force new justify onto already-rendered text (JustifyH alone won't re-flow it; see ns.ReflowFontString).
        ns.ReflowFontString(castParts.nameFS)
        ns.ReflowFontString(castParts.targetFS)
        ns.ReflowFontString(castParts.timerFS)
        local useClassColor = defaults.castTargetClassColor
        if dbRef and dbRef.castTargetClassColor ~= nil then useClassColor = dbRef.castTargetClassColor end
        local pvTargetHex
        if useClassColor then
            local _, pClass = UnitClass("player")
            local c = pClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[pClass]
            if c then
                castParts.targetFS:SetTextColor(c.r, c.g, c.b, 1)
                pvTargetHex = (c.GenerateHexColor and c:GenerateHexColor()) or c.colorStr or "ffffffff"
            else
                castParts.targetFS:SetTextColor(1, 1, 1, 1)
                pvTargetHex = "ffffffff"
            end
        else
            local ctc = (dbRef and dbRef.castTargetColor) or defaults.castTargetColor
            castParts.targetFS:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
            pvTargetHex = string.format("ff%02x%02x%02x",
                math.floor(ctc.r * 255 + 0.5), math.floor(ctc.g * 255 + 0.5), math.floor(ctc.b * 255 + 0.5))
        end
        local pvTargetText = UnitName("player") or EllesmereUI.L("Spell Target")
        castParts.targetFS:SetText(pvTargetText)
        if pvCombine then
            castParts.nameFS:SetFormattedText("%s - |c" .. pvTargetHex .. "%s|r",
                EllesmereUI.L("Spell Name"), pvTargetText)
        else
            castParts.nameFS:SetText(EllesmereUI.L("Spell Name"))
        end

        -- Name/target/timer widths are set per-element above (each uses its configured % of bar width; timer uses its reserved slot) to mirror the in-game layout.

        -- Helper: position a single preview frame into a slot
        local function PlaceInSlot(frame, slotName, index, count, iconW, iconH, slotSpacing, sxOff, syOff)
            sxOff = sxOff or 0
            syOff = syOff or 0
            -- Vertical center-to-center distance: cropped icons are shorter, so "up"-growth stacked slots pack tighter. slotSpacing is horizontal (gap+width); swap width for height here (equal when uncropped).
            local slotSpacingV = slotSpacing - iconW + iconH
            frame:ClearAllPoints()
            if slotName == "top" then
                -- Anchor auras to whichever FontString is in the top slot
                local anchor
                if ns.IsNameElement(slotTop) then
                    anchor = nameFS
                elseif slotTop == "healthNumber" then
                    anchor = hpNumber
                elseif slotTop == "level" then
                    anchor = lvlText
                elseif slotTop == "targetOfTarget" then
                    anchor = pf._totFS
                elseif slotTop ~= "none" then
                    anchor = hpText
                else
                    anchor = health
                end
                -- Only add cpPush when anchoring to health bar (top slot is "none")
                local slotCpPush = (slotTop == "none") and cpPush or 0
                frame:SetPoint("BOTTOM", anchor, "TOP",
                    (index - (count + 1) / 2) * slotSpacing + sxOff, debuffY + slotCpPush + syOff)
            elseif slotName == "left" then
                -- Classic WoW UI: gap off the border art, as live does.
                local sideOff = (DBVal("sideAuraXOffset") or defaults.sideAuraXOffset) + ns.NP_ClassicSide("left")
                frame:SetPoint("BOTTOMRIGHT", health, "BOTTOMLEFT", -sideOff - (index - 1) * slotSpacing + sxOff, syOff)
            elseif slotName == "right" then
                local sideOff = (DBVal("sideAuraXOffset") or defaults.sideAuraXOffset) + ns.NP_ClassicSide("right")
                frame:SetPoint("BOTTOMLEFT", health, "BOTTOMRIGHT", sideOff + (index - 1) * slotSpacing + sxOff, syOff)
            elseif slotName == "topleft" then
                local growth = DBVal("topleftSlotGrowth") or defaults.topleftSlotGrowth
                local idx = index - 1  -- 0 for icon 1, never moves
                local baseX = sxOff
                local baseY = debuffY + cpPush + syOff
                if growth == "up" then
                    frame:SetPoint("BOTTOMLEFT", health, "TOPLEFT", baseX, baseY + idx * slotSpacingV)
                elseif growth == "right" then
                    frame:SetPoint("BOTTOMLEFT", health, "TOPLEFT", baseX + idx * slotSpacing, baseY)
                else
                    frame:SetPoint("BOTTOMLEFT", health, "TOPLEFT", baseX - idx * slotSpacing, baseY)
                end
            elseif slotName == "topright" then
                local growth = DBVal("toprightSlotGrowth") or defaults.toprightSlotGrowth
                local idx = index - 1  -- 0 for icon 1, never moves
                local baseX = sxOff
                local baseY = debuffY + cpPush + syOff
                if growth == "up" then
                    frame:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", baseX, baseY + idx * slotSpacingV)
                elseif growth == "left" then
                    frame:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", baseX - idx * slotSpacing, baseY)
                else
                    frame:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", baseX + idx * slotSpacing, baseY)
                end
            elseif slotName == "bottom" then
                frame:SetPoint("TOP", cast, "BOTTOM",
                    (index - (count + 1) / 2) * slotSpacing + sxOff, -2 + syOff)
            end
        end

        local function AuraDurationVal(kind, suffix)
            local db = DB()
            local key = kind .. "DurationText" .. suffix
            local oldKey = "auraDurationText" .. suffix
            if db and db[key] ~= nil then return db[key] end
            if db and db[oldKey] ~= nil then return db[oldKey] end
            return defaults[oldKey]
        end
        local debuffDurSz = AuraDurationVal("debuff", "Size")
        local debuffDurX = AuraDurationVal("debuff", "X")
        local debuffDurY = AuraDurationVal("debuff", "Y")
        local debuffDurC = AuraDurationVal("debuff", "Color")
        local buffDurSz = AuraDurationVal("buff", "Size")
        local buffDurX = AuraDurationVal("buff", "X")
        local buffDurY = AuraDurationVal("buff", "Y")
        local buffDurC = AuraDurationVal("buff", "Color")
        local ccDurSz = AuraDurationVal("cc", "Size")
        local ccDurX = AuraDurationVal("cc", "X")
        local ccDurY = AuraDurationVal("cc", "Y")
        local ccDurC = AuraDurationVal("cc", "Color")
        local auraStackSz = DBVal("auraStackTextSize") or defaults.auraStackTextSize
        local auraStackC = (DB() and DB().auraStackTextColor) or defaults.auraStackTextColor
        local auraStackX = DBVal("auraStackTextX") or defaults.auraStackTextX
        local auraStackY = DBVal("auraStackTextY") or defaults.auraStackTextY
        local auraStackPos = DBVal("auraStackTextPosition") or defaults.auraStackTextPosition
        local atPos = DBVal("auraTextPosition") or defaults.auraTextPosition
        local debuffTPos = DBVal("debuffTimerPosition") or atPos
        local buffTPos   = DBVal("buffTimerPosition")   or atPos
        local ccTPos     = DBVal("ccTimerPosition")     or atPos

        -- Helper: apply timer position to a duration text fontstring
        local function ApplyTimerPos(durText, auraFrame, pos, size, x, y, color)
            if pos == "none" then
                durText:Hide()
                return
            end
            durText:Show()
            durText:SetFont(fontPath, size, EllesmereUI.SlugFlag("OUTLINE, SLUG"))
            durText:SetTextColor(color.r, color.g, color.b, 1)
            durText:ClearAllPoints()
            if pos == "center" then
                durText:SetPoint("CENTER", auraFrame, "CENTER", x, y)
                durText:SetJustifyH("CENTER")
            elseif pos == "topright" then
                durText:SetPoint("TOPRIGHT", auraFrame, "TOPRIGHT", 3 + x, 4 + y)
                durText:SetJustifyH("RIGHT")
            elseif pos == "bottomleft" then
                durText:SetPoint("BOTTOMLEFT", auraFrame, "BOTTOMLEFT", -3 + x, -4 + y)
                durText:SetJustifyH("LEFT")
            elseif pos == "bottomright" then
                durText:SetPoint("BOTTOMRIGHT", auraFrame, "BOTTOMRIGHT", 3 + x, -4 + y)
                durText:SetJustifyH("RIGHT")
            else
                durText:SetPoint("TOPLEFT", auraFrame, "TOPLEFT", -3 + x, 4 + y)
                durText:SetJustifyH("LEFT")
            end
        end

        -- Helper: apply stack-count position to a stack text fontstring
        local function ApplyStackPos(countText, auraFrame)
            if auraStackPos == "none" then
                countText:Hide()
                return
            end
            countText:Show()
            countText:SetFont(fontPath, auraStackSz, EllesmereUI.SlugFlag("OUTLINE, SLUG"))
            countText:SetTextColor(auraStackC.r, auraStackC.g, auraStackC.b, 1)
            countText:ClearAllPoints()
            if auraStackPos == "center" then
                countText:SetPoint("CENTER", auraFrame, "CENTER", auraStackX, auraStackY)
                countText:SetJustifyH("CENTER")
            elseif auraStackPos == "topright" then
                countText:SetPoint("TOPRIGHT", auraFrame, "TOPRIGHT", 3 + auraStackX, 4 + auraStackY)
                countText:SetJustifyH("RIGHT")
            elseif auraStackPos == "bottomleft" then
                countText:SetPoint("BOTTOMLEFT", auraFrame, "BOTTOMLEFT", -3 + auraStackX, -4 + auraStackY)
                countText:SetJustifyH("LEFT")
            elseif auraStackPos == "topleft" then
                countText:SetPoint("TOPLEFT", auraFrame, "TOPLEFT", -3 + auraStackX, 4 + auraStackY)
                countText:SetJustifyH("LEFT")
            else
                countText:SetPoint("BOTTOMRIGHT", auraFrame, "BOTTOMRIGHT", 3 + auraStackX, -4 + auraStackY)
                countText:SetJustifyH("RIGHT")
            end
        end

        -- Aura slot XY offsets (slot-based)
        local debuffXOff, debuffYOff = 0, 0
        if debuffSlotVal ~= "none" then
            debuffXOff = DBVal(debuffSlotVal .. "SlotXOffset") or 0
            debuffYOff = DBVal(debuffSlotVal .. "SlotYOffset") or 0
        end
        local buffXOff, buffYOff = 0, 0
        if buffSlotVal ~= "none" then
            buffXOff = DBVal(buffSlotVal .. "SlotXOffset") or 0
            buffYOff = DBVal(buffSlotVal .. "SlotYOffset") or 0
        end
        local ccXOff, ccYOff = 0, 0
        if ccSlotVal ~= "none" then
            ccXOff = DBVal(ccSlotVal .. "SlotXOffset") or 0
            ccYOff = DBVal(ccSlotVal .. "SlotYOffset") or 0
        end

        for i = 1, PV_CONST.DEBUFF_COUNT do
            if debuffSlotVal == "none" then
                debuffs[i]:Hide()
            else
                debuffs[i]:Show()
                debuffs[i]:SetSize(Snap(debuffSz), Snap(debuffH))
                ns.SetAuraIconCrop(debuffs[i].icon, debuffCrop, debuffSz, debuffH)
                debuffs[i].durationText:SetFont(fontPath, debuffDurSz, EllesmereUI.SlugFlag("OUTLINE, SLUG"))
                debuffs[i].durationText:SetTextColor(debuffDurC.r, debuffDurC.g, debuffDurC.b, 1)
                ApplyTimerPos(debuffs[i].durationText, debuffs[i], debuffTPos, debuffDurSz, debuffDurX, debuffDurY, debuffDurC)
                ApplyStackPos(debuffs[i].stackText, debuffs[i])
                PlaceInSlot(debuffs[i], debuffSlotVal, i, PV_CONST.DEBUFF_COUNT, debuffSz, debuffH, debuffSpacing, debuffXOff, debuffYOff)
            end
        end

        -- Buff size + duration text styling + slot position
        for i = 1, PV_CONST.BUFF_COUNT do
            if buffSlotVal == "none" then
                buffs[i]:Hide()
                if buffs[i].dispelGlow and buffs[i].dispelGlow.active then
                    ns.StopDispelGlow(buffs[i])
                end
            else
                buffs[i]:Show()
                buffs[i]:SetSize(Snap(buffSz), Snap(buffH))
                ns.SetAuraIconCrop(buffs[i].icon, buffCrop, buffSz, buffH)
                buffs[i].durationText:SetFont(fontPath, buffDurSz, EllesmereUI.SlugFlag("OUTLINE, SLUG"))
                buffs[i].durationText:SetTextColor(buffDurC.r, buffDurC.g, buffDurC.b, 1)
                ApplyTimerPos(buffs[i].durationText, buffs[i], buffTPos, buffDurSz, buffDurX, buffDurY, buffDurC)
                PlaceInSlot(buffs[i], buffSlotVal, i, PV_CONST.BUFF_COUNT, buffSz, buffH, buffSpacing, buffXOff, buffYOff)
                -- Dispel glow preview (always stop first to pick up color/style changes)
                local previewType = PreviewDispelType()
                if DBVal("dispelGlow") == true and previewType then
                    if buffs[i].dispelGlow and buffs[i].dispelGlow.active then
                        ns.StopDispelGlow(buffs[i])
                    end
                    ns.StartDispelGlow(buffs[i], buffSz, previewType, buffH)
                elseif buffs[i].dispelGlow and buffs[i].dispelGlow.active then
                    ns.StopDispelGlow(buffs[i])
                end
            end
        end

        -- CC size + duration text styling + slot position
        for i = 1, PV_CONST.CC_COUNT do
            if ccSlotVal == "none" then
                ccs[i]:Hide()
            else
                ccs[i]:Show()
                ccs[i]:SetSize(Snap(ccSz), Snap(ccH))
                ns.SetAuraIconCrop(ccs[i].icon, ccCrop, ccSz, ccH)
                ccs[i].durationText:SetFont(fontPath, ccDurSz, EllesmereUI.SlugFlag("OUTLINE, SLUG"))
                ccs[i].durationText:SetTextColor(ccDurC.r, ccDurC.g, ccDurC.b, 1)
                ApplyTimerPos(ccs[i].durationText, ccs[i], ccTPos, ccDurSz, ccDurX, ccDurY, ccDurC)
                PlaceInSlot(ccs[i], ccSlotVal, i, PV_CONST.CC_COUNT, ccSz, ccH, ccSpacing, ccXOff, ccYOff)
            end
        end

        -- Position target arrows OUTSIDE the outermost side auras
        if showArrows then
            arrows.left:ClearAllPoints()
            arrows.right:ClearAllPoints()
            -- Compute per-slot pixel extent on each side (accounts for X offsets)
            local sideOff = DBVal("sideAuraXOffset") or defaults.sideAuraXOffset
            local leftExtent, rightExtent = 0, 0
            -- Cast spell icon reserve (mirror live PositionArrowsOutsideAuras)
            if castIconLeftPush > 0 then leftExtent = math.max(leftExtent, castIconLeftPush) end
            if castIconRightPush > 0 then rightExtent = math.max(rightExtent, castIconRightPush) end
            -- Aura slots (debuffs, buffs, ccs)
            local function addAuraSide(slotVal, count, sz, sp, xOff)
                -- Classic WoW UI: the rows sit past the border art, as live.
                if slotVal == "left" then
                    leftExtent = math.max(leftExtent, sideOff + ns.NP_ClassicSide("left") + (count - 1) * sp + sz - xOff)
                elseif slotVal == "right" then
                    rightExtent = math.max(rightExtent, sideOff + ns.NP_ClassicSide("right") + (count - 1) * sp + sz + xOff)
                end
            end
            addAuraSide(debuffSlotVal, PV_CONST.DEBUFF_COUNT, debuffSz, debuffSpacing, debuffXOff)
            addAuraSide(buffSlotVal, PV_CONST.BUFF_COUNT, buffSz, buffSpacing, buffXOff)
            addAuraSide(ccSlotVal, PV_CONST.CC_COUNT, ccSz, ccSpacing, ccXOff)
            -- Raid marker
            if rmPos == "left" and showRM then
                leftExtent = math.max(leftExtent, sideOff + castIconLeftPush + rmSize - rmXOff)
            elseif rmPos == "right" and showRM then
                rightExtent = math.max(rightExtent, sideOff + castIconRightPush + rmSize + rmXOff)
            end
            -- Classification icon
            if clPos == "left" and showCL then
                leftExtent = math.max(leftExtent, sideOff + castIconLeftPush + reIconSz - clXOff)
            elseif clPos == "right" and showCL then
                rightExtent = math.max(rightExtent, sideOff + castIconRightPush + reIconSz + clXOff)
            end

            if leftExtent > 0 then
                arrows.left:SetPoint("RIGHT", health, "LEFT", -(leftExtent + 8), 0)
            else
                arrows.left:SetPoint("RIGHT", health, "LEFT", -8, 0)
            end
            if rightExtent > 0 then
                arrows.right:SetPoint("LEFT", health, "RIGHT", rightExtent + 8, 0)
            else
                arrows.right:SetPoint("LEFT", health, "RIGHT", 8, 0)
            end
            arrows.left:Show(); arrows.right:Show()
            if pf._arrowOverlay then pf._arrowOverlay:Show() end
        else
            arrows.left:Hide(); arrows.right:Hide()
            if pf._arrowOverlay then pf._arrowOverlay:Hide() end
        end

        -- Height calculation: the "top" slot determines the area above the name. Find which aura type occupies it, including per-slot Y offsets that push elements further up.
        local topExtent = 0
        local function isTopSlot(s) return s == "top" or s == "topleft" or s == "topright" end
        if isTopSlot(debuffSlotVal) then topExtent = math.max(topExtent, debuffSz + debuffYOff) end
        if isTopSlot(buffSlotVal) then topExtent = math.max(topExtent, buffSz + buffYOff) end
        if isTopSlot(ccSlotVal) then topExtent = math.max(topExtent, ccSz + ccYOff) end
        if isTopSlot(rmPos) and showRM then topExtent = math.max(topExtent, rmSize + rmYOff) end
        if isTopSlot(clPos) and showCL then topExtent = math.max(topExtent, reIconSz + clYOff) end
        -- Only include name text height when something is actually in the top slot
        local topTextH = (slotTop ~= "none") and (topFontSz + 4 + nameYOff + topYOff) or 0
        -- Only add debuffY gap when something occupies the center "top" position or top text slot
        local hasTopCenter = false
        if debuffSlotVal == "top" then hasTopCenter = true end
        if buffSlotVal == "top" then hasTopCenter = true end
        if ccSlotVal == "top" then hasTopCenter = true end
        if rmPos == "top" and showRM then hasTopCenter = true end
        if clPos == "top" and showCL then hasTopCenter = true end
        local effectiveDebuffY = (hasTopCenter or slotTop ~= "none") and debuffY or 0
        local healthFromTop = Snap(15 + 4 + topExtent + effectiveDebuffY + topTextH + cpPush)
        health:ClearAllPoints()
        health:SetSize(barW, barH)

        -- Size the plain-Frame wrapper to match the health bar exactly; the image border lives on this wrapper (not the StatusBar).
        healthWrapper:ClearAllPoints()
        healthWrapper:SetSize(barW, barH)

        local pfW = localParentW
        local dragging = IsDragging()
        local xOff
        if dragging and _cachedRawBarW then
            local delta = (rawBarW - _cachedRawBarW) / 2
            xOff = _cachedXOff - delta
            health:SetPoint("TOPLEFT", pf, "TOPLEFT", xOff, -healthFromTop)
            healthWrapper:SetPoint("TOPLEFT", pf, "TOPLEFT", xOff, -healthFromTop)
        else
            xOff = Snap((pfW - barW) / 2)
            _cachedRawBarW = rawBarW
            _cachedXOff    = xOff
            health:SetPoint("TOPLEFT", pf, "TOPLEFT", xOff, -healthFromTop)
            healthWrapper:SetPoint("TOPLEFT", pf, "TOPLEFT", xOff, -healthFromTop)
        end

        -- Preview hash line
        local hlEnabled = DBVal("hashLineEnabled")
        local hlPct = DBVal("hashLinePercent") or defaults.hashLinePercent
        if hlEnabled and hlPct and hlPct > 0 then
            local hlX = barW * (hlPct / 100)
            previewHashLine:ClearAllPoints()
            previewHashLine:SetPoint("TOP", health, "TOPLEFT", hlX, 0)
            previewHashLine:SetPoint("BOTTOM", health, "BOTTOMLEFT", hlX, 0)
            local hlc = (DB() and DB().hashLineColor) or defaults.hashLineColor
            previewHashLine:SetColorTexture(hlc.r, hlc.g, hlc.b, 0.8)
            previewHashLine:Show()
        else
            previewHashLine:Hide()
        end

        -- Preview bar texture: apply via SetStatusBarTexture
        do
            local texKey = DBVal("healthBarTexture") or "none"
            local texPath = EllesmereUI.ResolveTexturePath(ns.healthBarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
            health:SetStatusBarTexture(texPath)
            UnsnapTex(health:GetStatusBarTexture())
        end

        -- Class power pips (preview): the renderer is a nested function, defined and called once right here so its ~38 locals live in their own scope -- pf.Update was over Lua 5.1's 200-local-per-function cap.
        pf.UpdateCP = function()
        local showCP = DBVal("showClassPower") == true
        local cpExtraH = 0
        local cpIsBarType = false
        local cpResourceName = nil
        if showCP then
            -- Determine pip count from player's class, using live UnitPowerMax when available
            local _, playerClass = UnitClass("player")
            local cpInfo = CP.CLASS_MAP[playerClass]
            -- Match the module: vanilla content has only these two resources,
            -- so previewing the rest would promise pips that never appear.
            if EllesmereUI.IS_FOREVER then
                cpInfo = (playerClass == "ROGUE" or playerClass == "DRUID")
                    and CP.CLASS_MAP[playerClass] or nil
            end
            local cpMax = 0
            if cpInfo then
                -- Resolve spec-specific entries (numeric specID keys)
                if cpInfo[1] == nil then
                    local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
                    local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec)
                    cpInfo = specID and cpInfo[specID]
                end
                if cpInfo then
                    cpResourceName = type(cpInfo[1]) == "string" and cpInfo[1] or nil
                    if type(cpInfo[1]) == "string" then
                        if cpInfo[1] == "BREWMASTER_STAGGER" then
                            cpIsBarType = true
                            cpMax = 1
                        elseif cpInfo[1] == "SOUL_FRAGMENTS_VENGEANCE" then
                            cpMax = 6
                        elseif cpInfo[1] == "MAELSTROM_WEAPON" and EllesmereUI and EllesmereUI.GetMaelstromWeapon then
                            local _, mMax = EllesmereUI.GetMaelstromWeapon()
                            cpMax = (mMax and mMax > 0) and mMax or cpInfo[2]
                        elseif cpInfo[1] == "TIP_OF_THE_SPEAR" then
                            cpMax = cpInfo[2]
                        elseif cpInfo[1] == "WHIRLWIND_STACKS" then
                            cpMax = cpInfo[2]
                        else
                            cpMax = cpInfo[2]
                        end
                    else
                        local liveMax = UnitPowerMax("player", cpInfo[1])
                        cpMax = (liveMax and liveMax > 0) and liveMax or cpInfo[2]
                    end
                end
            end
            local cpCur = math.floor(cpMax * CP.FILL_FRAC + 0.5)
            local useClassColors = DBVal("classPowerClassColors")
            if useClassColors == nil then useClassColors = defaults.classPowerClassColors end
            local cpColor = CP.DEFAULT_COLOR
            if useClassColors then
                cpColor = CP.CLASS_COLORS[playerClass] or CP.DEFAULT_COLOR
            else
                local cc = (DB() and DB().classPowerCustomColor) or defaults.classPowerCustomColor
                cpColor = { cc.r, cc.g, cc.b }
            end

            local cpBgCol = (DB() and DB().classPowerBgColor) or defaults.classPowerBgColor

            if cpIsBarType then
                -- Bar-type preview (stagger): single StatusBar
                for i = 1, CP.MAX_POSSIBLE do
                    CP.pips[i]:Hide()
                    if CP.pips[i]._bg then CP.pips[i]._bg:Hide() end
                    ns.HidePipDecor(CP.pips[i])
                end
                local cpScale = DBVal("classPowerScale") or defaults.classPowerScale
                local cpYOff  = DBVal("classPowerYOffset") or defaults.classPowerYOffset
                local cpXOff  = DBVal("classPowerXOffset") or defaults.classPowerXOffset
                local cpPos   = DBVal("classPowerPos") or defaults.classPowerPos
                local scaledH = Snap(CP.PIP_H * cpScale)
                local barW    = Snap(CP.PIP_W * cpScale * 6)

                local anchorPoint, anchorRelPoint, anchorFrame, yDir
                if cpPos == "top" then
                    anchorPoint    = "BOTTOM"
                    anchorRelPoint = "TOP"
                    anchorFrame    = health
                    yDir = 1
                else
                    anchorPoint    = "TOP"
                    anchorRelPoint = "BOTTOM"
                    anchorFrame    = cast
                    yDir = -1
                end

                local bar = CP.bar
                bar:ClearAllPoints()
                bar:SetSize(barW, scaledH)
                bar:SetPoint(anchorPoint, anchorFrame, anchorRelPoint,
                    Snap(cpXOff), Snap(yDir * cpYOff))
                bar:SetMinMaxValues(0, 100)
                bar:SetValue(45)  -- preview at 45% (moderate stagger)
                bar:SetStatusBarColor(1.0, 0.85, 0.2, 1)  -- yellow for preview
                bar._bg:SetColorTexture(cpBgCol.r, cpBgCol.g, cpBgCol.b, cpBgCol.a)
                bar:Show()

                if cpPos ~= "top" then
                    cpExtraH = cpYOff + scaledH
                end
            elseif cpMax <= 0 then
                for i = 1, CP.MAX_POSSIBLE do
                    CP.pips[i]:Hide()
                    if CP.pips[i]._bg then CP.pips[i]._bg:Hide() end
                    ns.HidePipDecor(CP.pips[i])
                end
                CP.bar:Hide()
            else
                CP.bar:Hide()
                local cpScale = DBVal("classPowerScale") or defaults.classPowerScale
                local cpYOff  = DBVal("classPowerYOffset") or defaults.classPowerYOffset
                local cpXOff  = DBVal("classPowerXOffset") or defaults.classPowerXOffset
                local cpPos   = DBVal("classPowerPos") or defaults.classPowerPos
                local cpGap   = DBVal("classPowerGap") or defaults.classPowerGap
                local cpShape     = DBVal("classPowerShape") or defaults.classPowerShape
                local cpBorderOn  = DBVal("classPowerBorder") == true
                local cpBorderCol = (DB() and DB().classPowerBorderColor) or defaults.classPowerBorderColor
                local cpBorderPx  = cpBorderOn and Snap(DBVal("classPowerBorderSize") or defaults.classPowerBorderSize) or 0
                local cpIconKind  = ns.GetPipIconKind(cpShape)
                local cpSquare    = CP.SQUARE_SHAPE[cpShape] or (cpIconKind ~= nil)
                local scaledW   = Snap(CP.PIP_W * cpScale)
                local scaledH   = cpSquare and scaledW or Snap(CP.PIP_H * cpScale)
                local scaledGap = Snap(cpGap * cpScale)
                local totalPipW = cpMax * scaledW + (cpMax - 1) * scaledGap

                -- Determine anchor frame and direction
                local anchorPoint, anchorRelPoint, anchorFrame, yDir
                if cpPos == "top" then
                    anchorPoint    = "BOTTOM"
                    anchorRelPoint = "TOP"
                    anchorFrame    = health
                    yDir = 1
                else
                    -- Bottom: attach below cast bar (preview always shows cast bar)
                    anchorPoint    = "TOP"
                    anchorRelPoint = "BOTTOM"
                    anchorFrame    = cast
                    yDir = -1
                end

                local cpEmptyCol = (DB() and DB().classPowerEmptyColor) or defaults.classPowerEmptyColor

                -- Pre-compute each pip's left-edge X in group-local coords; anchor via BOTTOMLEFT/TOPLEFT to avoid half-pixel center offsets.
                local pipPositions = {}
                for i = 1, cpMax do
                    pipPositions[i] = Snap((i - 1) * (scaledW + scaledGap))
                end
                local groupW = pipPositions[cpMax] + scaledW
                local halfGroup = Snap(groupW / 2)

                local leftAnchor = (anchorPoint == "BOTTOM") and "BOTTOMLEFT" or "TOPLEFT"

                for i = 1, CP.MAX_POSSIBLE do
                    local pip = CP.pips[i]
                    if i <= cpMax then
                        pip:ClearAllPoints()
                        pip:SetSize(scaledW, scaledH)
                        local pipLeftX = Snap(pipPositions[i] - halfGroup + cpXOff)
                        pip:SetPoint(leftAnchor, anchorFrame, anchorRelPoint,
                            pipLeftX, Snap(yDir * cpYOff))

                        -- Background behind each pip
                        local bg = pip._bg
                        if bg then
                            bg:ClearAllPoints()
                            bg:SetAllPoints(pip)
                            bg:SetTexture(CP.WHITE)
                            bg:SetTexCoord(0, 1, 0, 1)
                            bg:SetDesaturated(false)
                            bg:SetVertexColor(cpBgCol.r, cpBgCol.g, cpBgCol.b, cpBgCol.a)
                            bg:Show()
                        end

                        ns.ApplyPipShape(pf, pip, cpShape, cpBorderOn, cpBorderCol, cpBorderPx)

                        if cpIconKind == "holypower" then
                            local n = (i - 1) % 5 + 1
                            local flip = (n == 5)
                            local idx = flip and 4 or n
                            if bg then
                                bg:SetAtlas("nameplates-holypower" .. idx .. "-off")
                                bg:SetDesaturated(true)
                                if flip then bg:SetTexCoord(1, 0, 0, 1) end
                                bg:SetVertexColor(1, 1, 1, cpBgCol.a)
                                bg:Show()
                            end
                            if i <= cpCur then
                                pip:SetAtlas("nameplates-holypower" .. idx .. "-on")
                                if flip then pip:SetTexCoord(1, 0, 0, 1) end
                                pip:SetVertexColor(1, 1, 1, 1)
                                UnsnapTex(pip)
                                pip:Show()
                            else
                                pip:Hide()
                            end
                        elseif cpIconKind then
                            pip:SetAtlas(ns.GetPipIconAtlas(cpIconKind, i <= cpCur, i))
                            if (i > cpCur) and ns.CP_ICON_DIM_EMPTY[cpIconKind] then
                                pip:SetVertexColor(0.35, 0.35, 0.35, 1)
                            else
                                pip:SetVertexColor(1, 1, 1, 1)
                            end
                            UnsnapTex(pip)
                            pip:Show()
                        else
                            pip:SetTexture(CP.WHITE)
                            pip:SetTexCoord(0, 1, 0, 1)
                            if i <= cpCur then
                                pip:SetVertexColor(cpColor[1], cpColor[2], cpColor[3], 1)
                            else
                                pip:SetVertexColor(cpEmptyCol.r, cpEmptyCol.g, cpEmptyCol.b, cpEmptyCol.a)
                            end
                            UnsnapTex(pip)
                            pip:Show()
                        end
                    else
                        pip:Hide()
                        if pip._bg then pip._bg:Hide() end
                        if pip._border then pip._border:Hide() end
                        if pip._borderBox then pip._borderBox:Hide() end
                    end
                end
                -- Extra height only when pips are below the cast bar
                if cpPos ~= "top" then
                    cpExtraH = cpYOff + scaledH
                end
            end
        else
            for i = 1, CP.MAX_POSSIBLE do
                CP.pips[i]:Hide()
                if CP.pips[i]._bg then CP.pips[i]._bg:Hide() end
                ns.HidePipDecor(CP.pips[i])
            end
            CP.bar:Hide()
        end
        return cpExtraH
        end
        local cpExtraH = pf.UpdateCP()

        local totalH = Snap(healthFromTop + barH + castH + cpExtraH + 15)
        -- Add extra height for auras in the "bottom" slot (below cast bar)
        local bottomExtent = 0
        local function isBottomSlot(s) return s == "bottom" end
        if isBottomSlot(debuffSlotVal) then bottomExtent = math.max(bottomExtent, debuffSz + 2 - debuffYOff) end
        if isBottomSlot(buffSlotVal) then bottomExtent = math.max(bottomExtent, buffSz + 2 - buffYOff) end
        if isBottomSlot(ccSlotVal) then bottomExtent = math.max(bottomExtent, ccSz + 2 - ccYOff) end
        if isBottomSlot(rmPos) and showRM then bottomExtent = math.max(bottomExtent, rmSize + 2 - rmYOff) end
        if isBottomSlot(clPos) and showCL then bottomExtent = math.max(bottomExtent, reIconSz + 2 - clYOff) end
        -- The Bottom Left / Bottom Right texts hang there too.
        bottomExtent = math.max(bottomExtent, previewGlow.botTextH or 0)
        totalH = totalH + bottomExtent
        self:SetSize(localParentW, totalH)

        -- Target glow preview (9-slice soft glow matching real nameplates)
        local pgf = previewGlow.frame
        pgf:ClearAllPoints()
        local ge = previewGlow.extend
        PP.Point(pgf, "TOPLEFT", healthWrapper, "TOPLEFT", -ge, ge)
        PP.Point(pgf, "BOTTOMRIGHT", healthWrapper, "BOTTOMRIGHT", ge, -ge)
        local glowEUI       = previewGlow.getEUI()
        local glowBorder    = previewGlow.getBorderOn()
        local glowHighlight = previewGlow.getHighlight()
        -- EllesmereUI: background glow, tinted + faded with the Glow Color/Opacity
        if optState.showTargetGlowPreview and glowEUI then
            local gc = previewGlow.getGlowCol()
            local ga = previewGlow.getGlowAlpha()
            for _, t in ipairs(previewGlow.texs) do t:SetVertexColor(gc.r, gc.g, gc.b, ga) end
            pgf:Show()
        else
            pgf:Hide()
        end
        -- Border Color: override the preview border with the custom target color
        if optState.showTargetGlowPreview and glowBorder then
            local bc = previewGlow.getBorderCol()
            for _, tex in ipairs(borderFrame._texs) do tex:SetVertexColor(bc.r, bc.g, bc.b) end
            for _, tex in ipairs(simpleBorderFrame._texs) do tex:SetVertexColor(bc.r, bc.g, bc.b) end
            for _, e in ipairs(_solidEdges) do e:SetColorTexture(bc.r, bc.g, bc.b, 1); UnsnapTex(e) end
        end
        -- Highlight: translucent wash across the preview health bar (color/opacity via the Target Highlight cog).
        if previewGlow.highlight then
            local showHL = optState.showTargetGlowPreview and glowHighlight
            if showHL then
                local hc = previewGlow.getHighlightCol()
                previewGlow.highlight:SetColorTexture(hc.r, hc.g, hc.b, previewGlow.getHighlightAlpha())
            end
            previewGlow.highlight:SetShown(showHL)
        end

        -- Stock styles: the stock look over everything laid out above.
        if previewGlow.classic then
            -- Classic WoW UI: the vanilla borders round both bars (the
            -- border block hid the EUI edges); the cast icon shows its
            -- whole art in the cast border's plate and the harmful aura
            -- mocks wear the stock dispel-type border like the live
            -- cells. No ring, overlay or mask.
            previewGlow.applyClassic(barH, castH)
            if ns.NP_ApplyClassicIconArt then
                for i = 1, PV_CONST.DEBUFF_COUNT do ns.NP_ApplyClassicIconArt(debuffs[i]) end
                for i = 1, PV_CONST.CC_COUNT do ns.NP_ApplyClassicIconArt(ccs[i]) end
            end
        elseif EllesmereUI.BlizzStyle.Get("nameplates") then
            previewGlow.applyBlizz()
            -- Aura mocks: the stock rounded mask and ring, as the live cells
            -- (sized above, so the ring geometry reads the frames).
            if ns.NP_ApplyBlizzIconArt then
                for i = 1, PV_CONST.DEBUFF_COUNT do ns.NP_ApplyBlizzIconArt(debuffs[i], debuffs[i].icon) end
                for i = 1, PV_CONST.BUFF_COUNT do ns.NP_ApplyBlizzIconArt(buffs[i], buffs[i].icon) end
                for i = 1, PV_CONST.CC_COUNT do ns.NP_ApplyBlizzIconArt(ccs[i], ccs[i].icon) end
            end
        end

        -- Absorb preview: update and toggle
        ToggleAbsorbPreview()

        -- Notify framework so the scroll area adjusts: report full content header height (preset offset + bottom padding, not just the preview frame), converting totalH from preview-local to parent-space.
        local headerExtra = pf._headerExtra or 0
        local hintH = (optState._previewHintFS and optState._previewHintFS:IsShown()) and 29 or 0
        EllesmereUI:UpdateContentHeaderHeight(totalH * previewScale + headerExtra + hintH)

        -- Refresh text overlay sizes (font/text may have changed)
        if pf._textOverlays then
            for _, ov in ipairs(pf._textOverlays) do
                if ov._syncFS then ov:SetShown(ov._syncFS:IsShown()) end
                if ov._resizeToText then ov._resizeToText() end
            end
        end
    end

    -- Expose preview elements for click-navigation hit overlays
    pf._nameFS       = nameFS
    pf._hpText       = hpText
    pf._hpNumber     = hpNumber
    pf._lvlText      = lvlText
    pf._debuffs      = debuffs
    pf._buffs        = buffs
    pf._ccs          = ccs
    pf._cast         = cast
    pf._castIconFrame = castParts.iconFrame
    pf._castNameFS   = castParts.nameFS
    pf._castTargetFS = castParts.targetFS
    pf._castTimerFS  = castParts.timerFS
    pf._raidFrame    = raidFrame
    pf._classIcon    = classIcon
    pf._factionIcon  = factionIcon
    pf._health       = health
    pf._healthWrapper = healthWrapper
    pf._cpPips       = CP.pips
    pf._cpBar        = CP.bar
    pf._cpMax        = CP.MAX_POSSIBLE
    pf._arrows       = arrows

    optState.activePreview = pf
    pf:Update()
    -- Return visual height in parent-scale pixels (pf:GetHeight() is local, scale it)
    return pf:GetHeight() * previewScale
end

-- Used by EUI_Nameplates_Options.lua
ns.NPO_BuildNameplatePreview = BuildNameplatePreview
