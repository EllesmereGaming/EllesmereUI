-------------------------------------------------------------------------------
--  EUI_Nameplates_Options.lua
--  Registers the Nameplates module with EllesmereUI.
--  All get/set calls go to ns.db.profile (centralized store).
--  Does NOT touch nameplate rendering logic.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local function GetNPOptOutline()
    -- Body-text preview flag, already slug-gated at the source (GetFontOutlineFlag).
    return EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag() or ""
end

-------------------------------------------------------------------------------
--  Page / section names
-------------------------------------------------------------------------------
local PAGE_GENERAL   = "General"
local PAGE_DISPLAY   = "Display"
local PAGE_COLORS    = "Colors"

local SECTION_FRIENDLY  = "OTHER NAMEPLATES"
local SECTION_ENEMY_NP  = "NAMEPLATE SPACING"
local SECTION_MISC      = "EXTRAS"
local SECTION_AURA      = "EXTRA AURA OPTIONS"

local SECTION_ENEMY     = "ENEMY COLORS"
local SECTION_CASTBAR   = "CAST COLORS AND EFFECTS"
local SECTION_THREAT    = "THREAT COLORS (INSTANCES ONLY)"
local SECTION_OTHER     = "OTHER COLORS"

-- Wait for EllesmereUI to exist
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    local PP = EllesmereUI.PanelPP

    ---------------------------------------------------------------------------
    --  Local references from the addon namespace
    ---------------------------------------------------------------------------
    local defaults             = ns.defaults
    local SetFSFont            = ns.SetFSFont
    local GetEnemyNameTextSize = ns.GetEnemyNameTextSize
    local GetDebuffTextColor   = ns.GetDebuffTextColor
    local BAR_W                = ns.BAR_W
    local plates               = ns.plates
    local GetNPOutline         = ns.GetNPOutline or function() return "OUTLINE, SLUG" end
    local GetNPUseShadow       = ns.GetNPUseShadow or function() return false end

    local pcall = pcall
    local pairs = pairs

    -- Preview font setter: mirrors SetFSFont shadow logic for direct SetFont calls
    local function SetPVFont(fs, fontPath, size, flags)
        if not (fs and fs.SetFont) then return end
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, flags == "") end
        fs:SetFont(fontPath, size, flags)
    end
    local floor = math.floor
    local NAME_RAID_MARKER_GAP = 3

    ---------------------------------------------------------------------------
    --  DB helper reads from the centralized profile via ns.db
    ---------------------------------------------------------------------------
    local function DB()
        return ns.db and ns.db.profile
    end

    local function DBVal(key)
        local db = DB()
        if db and db[key] ~= nil then return db[key] end
        return defaults[key]
    end

    local function DBColor(key)
        local db = DB()
        local c = (db and db[key]) or defaults[key]
        return c.r, c.g, c.b
    end

    local FOCUS_LETTER_ANCHORS = {
        CENTER = "Center",
        LEFT = "Left",
        RIGHT = "Right",
        TOP = "Top",
        BOTTOM = "Bottom",
        TOPLEFT = "Top Left",
        TOPRIGHT = "Top Right",
        BOTTOMLEFT = "Bottom Left",
        BOTTOMRIGHT = "Bottom Right",
    }
    local FOCUS_LETTER_ANCHOR_ORDER = {
        "CENTER", "LEFT", "RIGHT", "TOP", "BOTTOM",
        "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT",
    }
    local function GetFocusLetterAnchor()
        local anchor = DBVal("focusLetterAnchor") or defaults.focusLetterAnchor
        return FOCUS_LETTER_ANCHORS[anchor] and anchor or defaults.focusLetterAnchor
    end

    ---------------------------------------------------------------------------
    --  Refresh helpers  (same logic as the AceConfig version)
    ---------------------------------------------------------------------------
    local function RefreshAllPlates()
        for _, plate in pairs(plates) do
            plate:UpdateHealth()
        end
    end

    local function RefreshAllAuras()
        for _, plate in pairs(plates) do
            plate:UpdateAuras()
        end
        -- 12.1 aura containers own the aura rows there (the plate loop above
        -- only drives the legacy pools); the container reload is fingerprint-
        -- guarded, so redundant calls cost next to nothing. nil on 12.0.
        if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
    end

    local function RefreshAllFonts()
        for _, plate in pairs(plates) do
            plate:RefreshNamePosition()
            plate:UpdateHealthValues()
            local cns = ns.defaults.castNameSize
            local cts = ns.defaults.castTargetSize
            local _db = DB()
            if _db then
                cns = _db.castNameSize or cns
                cts = _db.castTargetSize or cts
            end
            local ctmSz = ns.defaults.castTimerSize
            local ctmC = ns.defaults.castTimerColor
            if _db then
                ctmSz = _db.castTimerSize or ctmSz
                ctmC = _db.castTimerColor or ctmC
            end
            if plate.castName then SetFSFont(plate.castName, cns, GetNPOutline()) end
            if plate.castTarget then SetFSFont(plate.castTarget, cts, GetNPOutline()) end
            if plate.castTimer then
                SetFSFont(plate.castTimer, ctmSz, GetNPOutline())
                plate.castTimer:SetTextColor(ctmC.r, ctmC.g, ctmC.b, 1)
            end
            local auraStackSz = (_db and _db.auraStackTextSize) or ns.defaults.auraStackTextSize
            for i = 1, 4 do
                if plate.debuffs[i] and plate.debuffs[i].count then SetFSFont(plate.debuffs[i].count, auraStackSz, "OUTLINE, SLUG") end
                if plate.buffs[i] and plate.buffs[i].count then SetFSFont(plate.buffs[i].count, auraStackSz, "OUTLINE, SLUG") end
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Health bar texture dropdown values (built from ns tables)
    ---------------------------------------------------------------------------
    -- Append SharedMedia textures to the runtime ns tables first so both
    -- the dropdown AND the live nameplate rendering can resolve SM keys.
    if EllesmereUI.AppendSharedMediaTextures then
        EllesmereUI.AppendSharedMediaTextures(
            ns.healthBarTextureNames or {},
            ns.healthBarTextureOrder or {},
            nil,
            ns.healthBarTextures
        )
    end

    local hbtValues = {}
    local hbtOrder = {}
    do
        local texNames = ns.healthBarTextureNames or {}
        local texOrder2 = ns.healthBarTextureOrder or {}
        for _, key in ipairs(texOrder2) do
            if key ~= "---" then
                hbtValues[key] = texNames[key] or key
            end
            hbtOrder[#hbtOrder + 1] = key
        end
        local texLookup = ns.healthBarTextures or {}
        hbtValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                return texLookup[key]
            end,
        }
    end

    ---------------------------------------------------------------------------
    --  Live Preview System
    --
    --  A cosmetic-only enemy nameplate preview built from persistent frames.
    --  Created once, updated via :Update() no rebuilding, no GC pressure.
    --  Reads current DB settings for colors, sizes, font, health number, etc.
    ---------------------------------------------------------------------------
    local activePreview
    local _displayHeaderBuilder   -- stored for page cache re-use
    local _colorPreviewRefreshAll -- refresh all color preview bars on cache restore
    local RefreshCoreEyes          -- forward-declared; defined in BuildDisplayPage
    local _previewHintFS                 -- the hint FontString
    local _headerBaseH = 0               -- header height WITHOUT hint (for cache restore)

    local function IsPreviewHintDismissed()
        return EllesmereUIDB and EllesmereUIDB.previewHintDismissed
    end

    -- Raid marker hidden on preview by default; toggled via eye icon.
    -- Shared scope so both BuildNameplatePreview and BuildDisplayPage can access it.
    local showRaidMarkerPreview = false
    local showClassificationPreview = false
    local showTargetGlowPreview = false
    local showAbsorbPreview = false
    local showDispelGlowPreview = false

    -- Transient flags: force-show indicators during slider drag
    local _sliderDragShowRaidMarker = false
    local _sliderDragShowClassification = false

    -- Persistent random preview values regenerated only on tab switch, NOT on
    -- profile changes or setting tweaks (which trigger fast-path RefreshPage rebuilds).
    local _previewHpPct
    local _previewCastFill
    local _previewCastIconIdx
    local displayCastIcons = { 136197, 236802, 135808, 136116, 135735, 136048, 135812, 136075 }
    local function RandomizePreviewValues()
        _previewHpPct = math.floor(60 + math.random() * 15)
        _previewCastFill = 0.40 + math.random() * 0.20
        _previewCastIconIdx = math.random(#displayCastIcons)
    end

    local function UpdatePreview()
        if activePreview and activePreview.Update then
            activePreview:Update()
        end
    end

    -- Refresh the preview every time the panel is reopened
    EllesmereUI:RegisterOnShow(UpdatePreview)

    --- Build the nameplate preview in the content header area.
    --- @param parent  Frame   contentHeaderFrame
    --- @param parentW number  available width
    --- @return number height consumed
    --- Build the nameplate preview in the content header area.
    --- Exact 1:1 replica of a real enemy nameplate same pixel sizes,
    --- same anchors, same fonts, same borders. No glow, no added effects.
    --- @param parent  Frame   contentHeaderFrame
    --- @param parentW number  available width
    --- @return number height consumed
    local function BuildNameplatePreview(parent, parentW)
        local FONT_PATH = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("nameplates")) or DBVal("font")

        -- Constants matching the real addon exactly
        local CAST_H = 17
        local BORDER_CORNER = 6
        local BORDER_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\border-colorless.png"

        -- Container sized in Update()
        local pf = CreateFrame("Frame", nil, parent)
        pf:SetPoint("TOP", parent, "TOP", 0, 0)

        -- Scale the preview so it matches real nameplate size on screen.
        -- Real nameplates render at UIParent's effective scale; the preview
        -- lives inside the EllesmereUI panel which has a smaller effective
        -- scale.  Applying this ratio makes every pixel value (bar width,
        -- font size, icon size, etc.) appear at the same physical size as
        -- the real nameplates.  Snap() still works correctly because it
        -- reads pf:GetEffectiveScale(), which now equals UIParent's scale.
        local previewScale = UIParent:GetEffectiveScale() / parent:GetEffectiveScale()
        pf:SetScale(previewScale)
        -- parentW in preview-local coordinates (used for centering the bar)
        local localParentW = parentW / previewScale

        -- Pixel-snap helper for the preview's own effective scale
        -- (defined early so AddBorder and CreatePreviewBorderSet can use it)
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

        -- 1px black border helper uses Snap() for the preview's effective scale
        -- (not PixelUtil, which snaps to screen pixels and can disagree with
        -- the preview's own pixel grid at certain panel scales)
        -- Returns a refresh function that re-snaps the 1px sizes when scale changes.
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
            _borderRefreshers[#_borderRefreshers + 1] = function()
                local npx = Snap(1)
                t:SetHeight(npx); b:SetHeight(npx)
                l:SetWidth(npx);  r:SetWidth(npx)
            end
        end

        -- Disable WoW's automatic pixel snapping on a texture (prevents sub-pixel jitter vs borders)
        local function UnsnapTex(tex)
            if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0) end
        end

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
        -- Type colors for preview dispel glow: Magic (blue), Enrage (red)
        local previewDispelColors = { CreateColor(0.2, 0.6, 1.0, 1), CreateColor(1.0, 0.2, 0.2, 1) }
        if not _previewHpPct then RandomizePreviewValues() end
        local previewHpPct = _previewHpPct
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

        -- Absorb preview: mask + two StatusBars matching real absorb rendering
        local absorbMask = health:CreateMaskTexture()
        absorbMask:SetAllPoints(health)
        absorbMask:SetTexture("Interface\\Buttons\\WHITE8X8")
        local previewAbsorb = CreateFrame("StatusBar", nil, health)
        previewAbsorb:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        previewAbsorb:SetPoint("BOTTOMLEFT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        previewAbsorb:SetReverseFill(false)
        previewAbsorb:SetMinMaxValues(0, 100)
        previewAbsorb:SetValue(95)
        previewAbsorb:SetFrameLevel(health:GetFrameLevel())
        previewAbsorb:Hide()
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
            previewAbsorb:SetStatusBarTexture(tex)
            previewAbsorb:SetStatusBarColor(r, g, b, alpha)
            local fill = previewAbsorb:GetStatusBarTexture()
            if fill then fill:SetDrawLayer("ARTWORK", 1); fill:AddMaskTexture(absorbMask) end
        end
        local function ToggleAbsorbPreview()
            if showAbsorbPreview then
                local barW = health:GetWidth()
                local barH = health:GetHeight()
                local hpPct = (previewHpPct or 75) / 100
                -- Match the live absorbForward bar: a FULL bar-width StatusBar
                -- windowed by its fill value, so the texture renders at bar scale
                -- (not squished into the absorb width). The visible absorb still
                -- occupies the same ~missing-health region; only the texture scale
                -- changes. The mask clips the overrun past the health bar's edge.
                previewAbsorb:SetSize(barW, barH)
                previewAbsorb:SetMinMaxValues(0, 1)
                previewAbsorb:SetValue((1 - hpPct) * 0.95)
                ApplyPreviewAbsorbStyle()
                previewAbsorb:Show()
            else
                previewAbsorb:Hide()
            end
        end

        -- Bar texture: applied directly via SetStatusBarTexture (no overlay)
        -- (updated in the preview refresh below)

        local BORDER_TEX_SIMPLE = "Interface\\AddOns\\EllesmereUINameplates\\Media\\border-simple.png"

        -- Wrapper frame around the health bar a plain Frame (not StatusBar).
        -- The image border is parented to this wrapper so it never interacts
        -- with StatusBar internals.  Sized to match the health bar exactly.
        local healthWrapper = CreateFrame("Frame", nil, pf)
        healthWrapper:SetFrameLevel(health:GetFrameLevel() + 4)

        -- Border set builder: 9-slice image border on a plain Frame.
        -- Uses PixelUtil (like the working UnitFrames preview).
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
            -- Corners inset UV by half a texel (T) from texture edges (0.0 and 1.0)
            -- so the GPU fully samples the outermost solid pixel line.
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
        -- Custom border preview: a dedicated child frame the shared border
        -- engine draws onto when Custom Border is enabled. Stored on the
        -- wrapper (a frame we own) so it adds no new builder local.
        healthWrapper._customBorder = CreateFrame("Frame", nil, healthWrapper)
        healthWrapper._customBorder:SetAllPoints(healthWrapper)
        healthWrapper._customBorder:Hide()

        -- Solid 1px edge lines on all 4 sides of healthWrapper.
        -- The image border's outermost solid pixel can vanish at non-native
        -- scales due to texture filtering.  These SetColorTexture lines sit
        -- directly on healthWrapper (below the image border's frame level)
        -- as a pixel-perfect fallback for any missing edge pixels.
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

        -- 9-slice soft glow frame for EllesmereUI target glow preview
        -- Matches the real nameplate glow: background.png with ADD blend, blue tint
        -- Packed into a single table to avoid exceeding Lua's 60-upvalue limit.
        local previewGlow = {}
        do
            local GLOW_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\background.png"
            local GM = 0.48  -- margin
            local GC = 12    -- corner size
            previewGlow.extend = 6
            local gf = CreateFrame("Frame", nil, pf)
            gf:SetFrameLevel(pf:GetFrameLevel() + 1)
            previewGlow.frame = gf
            -- Collected so Update() can re-tint the preview glow with the target
            -- Glow Color/Opacity alongside the live nameplates.
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

        -- Target "Highlight" style preview: translucent wash over the health bar
        -- (color + opacity configurable via the Target Highlight cog). The
        -- texture + glow getter refs are stashed on previewGlow (already an
        -- Update() upvalue) so they add no new upvalues to the near-cap preview
        -- Update closure.
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

        -- Text overlay frame: renders above health bar fill and borders (same as real addon)
        local healthTextFrame = CreateFrame("Frame", nil, health)
        healthTextFrame:SetAllPoints(health)
        healthTextFrame:SetFrameLevel(health:GetFrameLevel() + 7)

        -- Top text overlay: renders above health bar + borders so top-slot text is never hidden
        local topTextFrame = CreateFrame("Frame", nil, pf)
        topTextFrame:SetAllPoints(health)
        topTextFrame:SetFrameLevel(health:GetFrameLevel() + 6)

        -- Name text (anchored BOTTOM to health TOP, +4px gap, width 113)
        local nameFS = pf:CreateFontString(nil, "OVERLAY")
        SetPVFont(nameFS, FONT_PATH, 11, GetNPOptOutline())
        nameFS:SetPoint("BOTTOM", health, "TOP", 0, 4)
        nameFS:SetWordWrap(false)
        nameFS:SetMaxLines(1)
        nameFS:SetText(EllesmereUI.L("Enemy Name Text"))
        nameFS:SetTextColor(1, 1, 1, 1)

        local nameRaidFrame = CreateFrame("Frame", nil, pf)
        nameRaidFrame:SetFrameLevel(health:GetFrameLevel() + 8)
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

        -- Raid marker: custom marker.png image, position/size from settings
        local MARKER_PATH = "Interface\\AddOns\\EllesmereUI\\media\\marker.png"
        local raidFrame = CreateFrame("Frame", nil, health)
        -- +8 keeps the marker above the name/health text frames (healthTextFrame
        -- sits at health+7), matching the live plate so the preview is accurate.
        raidFrame:SetFrameLevel(health:GetFrameLevel() + 8)
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

        -- Cast bar (icon + bar fill health bar width)
        local cast = CreateFrame("StatusBar", nil, pf)
        cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        UnsnapTex(cast:GetStatusBarTexture())
        cast:SetMinMaxValues(0, 1)
        cast:SetValue(_previewCastFill)
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
        castParts.icon:SetTexture(displayCastIcons[_previewCastIconIdx])

        -- Cast spark
        castParts.spark = cast:CreateTexture(nil, "OVERLAY", nil, 1)
        castParts.spark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
        UnsnapTex(castParts.spark)
        castParts.spark:SetSize(8, CAST_H)
        castParts.spark:SetPoint("CENTER", cast:GetStatusBarTexture(), "RIGHT", 0, 0)
        castParts.spark:SetBlendMode("ADD")

        -- Cast text frame: a dedicated child ABOVE the cast border so the
        -- name/target/timer render in front of it (mirrors the live nameplate's
        -- castTextFrame). The PP border is a child of `cast` at cast+1, which
        -- would otherwise draw over text placed on `cast`'s own OVERLAY layer.
        castParts.textFrame = CreateFrame("Frame", nil, cast)
        castParts.textFrame:SetAllPoints(cast)
        castParts.textFrame:SetFrameLevel(cast:GetFrameLevel() + 5)

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

        -- Class power pips (cosmetic preview queries live class/spec resource count)
        -- Packed into a single table to stay under Lua's 60-upvalue limit.
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
            d:SetFrameLevel(health:GetFrameLevel() + 8)
            AddBorder(d)

            d.icon = d:CreateTexture(nil, "ARTWORK")
            UnsnapTex(d.icon)
            d.icon:SetPoint("TOPLEFT", d, "TOPLEFT", px, -px)
            d.icon:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -px, px)
            d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            d.icon:SetTexture(debuffData[i].icon)
            _insetIcons[#_insetIcons + 1] = { tex = d.icon, parent = d }

            -- Text child frame: sits above the icon frame so highlights can
            -- be sandwiched between icon artwork and text via frame levels.
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
            bf:SetFrameLevel(health:GetFrameLevel() + 8)
            AddBorder(bf)
            bf.icon = bf:CreateTexture(nil, "ARTWORK")
            UnsnapTex(bf.icon)
            bf.icon:SetPoint("TOPLEFT", bf, "TOPLEFT", px, -px)
            bf.icon:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -px, px)
            bf.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            bf.icon:SetTexture(buffData[i].icon)
            _insetIcons[#_insetIcons + 1] = { tex = bf.icon, parent = bf }
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
            cf:SetFrameLevel(health:GetFrameLevel() + 8)
            AddBorder(cf)
            cf.icon = cf:CreateTexture(nil, "ARTWORK")
            UnsnapTex(cf.icon)
            cf.icon:SetPoint("TOPLEFT", cf, "TOPLEFT", px, -px)
            cf.icon:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -px, px)
            cf.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            cf.icon:SetTexture(ccData[i].icon)
            _insetIcons[#_insetIcons + 1] = { tex = cf.icon, parent = cf }
            local cfTextFrame = CreateFrame("Frame", nil, cf)
            cfTextFrame:SetAllPoints()
            cfTextFrame:SetFrameLevel(cf:GetFrameLevel() + 2)
            cf.durationText = cfTextFrame:CreateFontString(nil, "OVERLAY")
            cf.durationText:SetFont(FONT_PATH, 12, EllesmereUI.SlugFlag("OUTLINE, SLUG"))
            cf.durationText:SetPoint("CENTER", cf, "CENTER", 0, 0)
            cf.durationText:SetText(ccData[i].text)
            ccs[i] = cf
        end

        -- Cached position values for the health bar anchor (see health block).
        local _cachedRawBarW, _cachedXOff

        -------------------------------------------------------------------
        --  Update re-reads DB, applies to existing frames. No rebuilds.
        -------------------------------------------------------------------
        pf.Update = function(self)
            local fontPath   = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("nameplates")) or DBVal("font")
            -- Body-text outline, already slug-gated at the source (GetFontOutlineFlag).
            local npOutline  = (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or "OUTLINE, SLUG"
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
            local curHpPct = _previewHpPct or 70
            local curHpVal = math.floor(PV_CONST.FAKE_MAX_HP * curHpPct / 100)
            health:SetValue(curHpVal)
            local pctStr = curHpPct .. "%"
            local pctNoSignStr = tostring(curHpPct)
            local hpNumStr = tostring(curHpVal):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
            -- Synthetic fractional percent so the "Show % Decimal" toggle is
            -- visible in the preview (the fake preview HP is a whole number).
            local pctStrDec = string.format("%.1f%%", curHpPct + 0.4)
            local pctNoSignStrDec = string.format("%.1f", curHpPct + 0.4)
            -- Text on hpText/hpNumber is set later by the slot-based positioning logic
            cast:SetValue(_previewCastFill or 0.60)
            castParts.icon:SetTexture(displayCastIcons[_previewCastIconIdx or 1])
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
                    EllesmereUI.ApplyBorderStyle(pcb, csz, ccol.r, ccol.g, ccol.b, ca, ctex,
                        DBVal("customBorderOffset"), DBVal("customBorderOffsetY"),
                        DBVal("customBorderShiftX"), DBVal("customBorderShiftY"),
                        "nameplates", csz)
                end
            else
                if pcb and EllesmereUI.ApplyBorderStyle then
                    EllesmereUI.ApplyBorderStyle(pcb, 0)
                    pcb:Hide()
                end
                local bOn = DBVal("showBorder")
                if bOn == nil then bOn = defaults.showBorder end
                if bOn then
                    borderFrame:Hide(); simpleBorderFrame:Show()
                    for _, e in ipairs(_solidEdges) do e:Show() end
                    simpleBorderFrame:ApplySize(DBVal("borderSize") or defaults.borderSize)
                else
                    borderFrame:Hide(); simpleBorderFrame:Hide()
                    for _, e in ipairs(_solidEdges) do e:Hide() end
                end
            end

            -- Refresh all 1px AddBorder edges (cast icon, aura icons)
            for _, refreshFn in ipairs(_borderRefreshers) do refreshFn() end

            -- Refresh icon insets (1px from border) for current scale
            local curPx = Snap(1)
            for _, entry in ipairs(_insetIcons) do
                entry.tex:ClearAllPoints()
                entry.tex:SetPoint("TOPLEFT", entry.parent, "TOPLEFT", curPx, -curPx)
                entry.tex:SetPoint("BOTTOMRIGHT", entry.parent, "BOTTOMRIGHT", -curPx, curPx)
            end

            -- Border color update
            local bc = (DB() and DB().borderColor) or defaults.borderColor
            for _, tex in ipairs(borderFrame._texs) do tex:SetVertexColor(bc.r, bc.g, bc.b) end
            for _, tex in ipairs(simpleBorderFrame._texs) do tex:SetVertexColor(bc.r, bc.g, bc.b) end
            for _, e in ipairs(_solidEdges) do e:SetColorTexture(bc.r, bc.g, bc.b, 1); if e.SetSnapToPixelGrid then e:SetSnapToPixelGrid(false); e:SetTexelSnappingBias(0) end end

            -- "Wrap Around Castbar" preview. Fully additive: this block is skipped
            -- entirely while the feature has never been enabled (so the border
            -- frames keep their original full-points anchoring and look exactly as
            -- before). It only extends the border down to the preview cast bar
            -- when the toggle is on, and restores the anchors once on toggle-off.
            -- The preview border frames already sit above the cast bar in frame
            -- level, so no re-leveling is needed.
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
                -- Solid 1px fallback edges: extend the bottom + side bottoms too
                -- (_solidEdges = { top, bottom, left, right }; top is untouched).
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

            -- Per-element gap between icons (user setting), then compute per-type center-to-center spacing
            local debuffGap = DBVal("debuffSpacing") or defaults.debuffSpacing
            local buffGap   = DBVal("buffSpacing")   or defaults.buffSpacing
            local ccGap     = DBVal("ccSpacing")     or defaults.ccSpacing
            local debuffSpacing = debuffGap + debuffSz
            local buffSpacing   = buffGap + buffSz
            local ccSpacing     = ccGap + ccSz

            -- Cropped icons (mirror the runtime): rectangular height (80% of
            -- width) + matching texcoord trim. Off by default.
            local debuffCrop = DBVal("debuffCropIcons") or defaults.debuffCropIcons
            local buffCrop   = DBVal("buffCropIcons")   or defaults.buffCropIcons
            local ccCrop     = DBVal("ccCropIcons")     or defaults.ccCropIcons
            local debuffH = ns.GetAuraCropHeight(debuffCrop, debuffSz)
            local buffH   = ns.GetAuraCropHeight(buffCrop, buffSz)
            local ccH     = ns.GetAuraCropHeight(ccCrop, ccSz)

            -- Arrow visibility is deferred until after auras are placed
            -- (arrows go OUTSIDE the outermost side aura)

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
                _sliderDragShowRaidMarker = false
                _sliderDragShowClassification = false
            end

            local showRM = showRaidMarkerPreview or _sliderDragShowRaidMarker

            -- Cast spell icon settings (mirror ns.GetCastIconReserve). Computed
            -- once here, before the core icons, and reused by the core icons,
            -- the cast bar, and the target arrows below. barH/castH are snapped
            -- profile numbers already in scope.
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
            if showIcon then
                if fullSize then
                    if onRight then castIconRightPush = barH + castH
                    else castIconLeftPush = barH + castH end
                elseif onRight and not iconInWidth then
                    castIconRightPush = castH * iconScale
                end
            end

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
            local showCL = showClassificationPreview or _sliderDragShowClassification
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
                classIcon:Show()
                if pf._classOverlay then pf._classOverlay:Show() end
            end

            -- Arrow push is no longer used arrows are placed OUTSIDE auras now
            -- (arrow positioning happens after all auras are placed)

            -- Cast bar: spans the health bar width. With "Make Icon Part of the
            -- Bar" the bar shrinks + shifts right so the icon (anchored to the
            -- bar's left edge) sits inside the width; otherwise it hangs outside.
            local pIconW = 0
            local pShiftX = 0
            if showIcon and iconInWidth and not fullSize then
                pIconW = castH * iconScale
                if not onRight then pShiftX = pIconW end
            end
            cast:ClearAllPoints()
            cast:SetSize(math.max(1, barW - pIconW), castH)
            cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", pShiftX, (DBVal("castBarOffsetY") or defaults.castBarOffsetY))
            do
                local cTexKey = DBVal("castBarTexture") or "none"
                local cTexPath = EllesmereUI.ResolveTexturePath(ns.healthBarTextures, cTexKey, "Interface\\Buttons\\WHITE8x8")
                cast:SetStatusBarTexture(cTexPath)
                UnsnapTex(cast:GetStatusBarTexture())
            end
            cast:SetStatusBarColor(cbColor.r, cbColor.g, cbColor.b, 1)
            -- Cast icon: size + anchor per side / full-size. SetSize (not
            -- SetScale) keeps AddBorder pixel-perfect. Frame level was lifted at
            -- creation. Full-size pins to the cast bottom so the square reaches
            -- the health top (zero-gap bar stack).
            castParts.iconFrame:ClearAllPoints()
            castParts.iconFrame:SetScale(1)
            if showIcon then
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
            castParts.spark:SetHeight(castH)

            -- Name font + color + position (font size set per-slot below)
            local nameYOff = DBVal("nameYOffset") or defaults.nameYOffset

            -- Slot-based text positioning 
            -- Read slot assignments
            local slotTop    = DBVal("textSlotTop") or defaults.textSlotTop
            local slotRight  = DBVal("textSlotRight") or defaults.textSlotRight
            local slotLeft   = DBVal("textSlotLeft") or defaults.textSlotLeft
            local slotCenter = DBVal("textSlotCenter") or defaults.textSlotCenter

            -- Hide all three text elements first
            nameFS:Hide()
            hpText:Hide()
            hpNumber:Hide()
            nameFS:ClearAllPoints()
            hpText:ClearAllPoints()
            hpNumber:ClearAllPoints()

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
                    ns.SetCombinedHealthText(hpText, element, dec and pctStrDec or pctStr, hpNumStr)
                    hpText:SetPoint(point, health, anchor, xOff, yOff)
                    hpText:SetTextColor(cr, cg, cb, 1)
                    hpText:Show()
                end
                -- Per-slot Width % (of the health bar) + Wrap, mirroring runtime.
                -- At the default 100% leave the FontString UNCONSTRAINED (SetWidth 0 =
                -- auto-size). A width box on a single-point-anchored FontString does NOT
                -- honour SetJustifyH, so a right/left-slot value would drift to centre;
                -- only impose a box when the user actually narrows it (< 100%).
                local hfs = (element == "healthNumber") and hpNumber or hpText
                hfs:SetJustifyH(point)
                local hwpct = (slotKey and DBVal(slotKey .. "WidthPct")) or 100
                local hw = 0
                if hwpct < 100 then hw = barW * hwpct / 100 end
                hfs:SetWidth(hw)
                local hwrap = false
                if slotKey and DBVal(slotKey .. "Wrap") == true then hwrap = true end
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
                    ns.SetCombinedHealthText(hpText, element, dec and pctStrDec or pctStr, hpNumStr)
                    hpText:SetParent(topTextFrame)
                    hpText:SetPoint("BOTTOM", health, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
                    hpText:SetTextColor(cr, cg, cb, 1)
                    hpText:Show()
                end
                -- Per-slot Width % (of the health bar) + Wrap, mirroring runtime. Top
                -- slot is centered; leave it unconstrained at the default 100% (see
                -- PlaceHealthInBar for why a width box would mis-position the text).
                local hfs = (element == "healthNumber") and hpNumber or hpText
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

            -- Enemy name truncation, mirroring runtime: width % of the bar-derived
            -- width + wrap toggle. Applied to the shared preview name FontString.
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
                nameRaidFrame:SetFrameLevel(health:GetFrameLevel() + 8)
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
                        if el ~= "none" and el ~= "enemyName" then
                            usedWidth = usedWidth + ns.EstimateHealthTextWidth(el)
                        end
                    end
                end
                nameFS:SetWidth(math.max((barW - usedWidth - pvNameMarkerReserve) * pvNameWPct / 100, 20))
                nameFS:SetTextColor(cr, cg, cb, 1)
                nameFS:Show()
            end

            -- Process top slot
            local topXOff = DBVal("textSlotTopXOffset") or 0
            local topYOff = DBVal("textSlotTopYOffset") or 0
            local topFontSz = DBVal("textSlotTopSize") or defaults.textSlotTopSize
            local topC = (DB() and DB().textSlotTopColor) or defaults.textSlotTopColor
            if slotTop == "enemyName" then
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
            local rightC = (DB() and DB().textSlotRightColor) or defaults.textSlotRightColor
            if slotRight == "enemyName" then
                PlaceNameInBar("RIGHT", "RIGHT", -2, "RIGHT", rightXOff, rightYOff, rightFontSz, rightC.r, rightC.g, rightC.b, "textSlotRight")
            else
                PlaceHealthInBar(slotRight, "RIGHT", "RIGHT", -2 + rightXOff, rightYOff, rightFontSz, rightC.r, rightC.g, rightC.b, "textSlotRight")
            end

            -- Process left slot
            local leftXOff = DBVal("textSlotLeftXOffset") or 0
            local leftYOff = DBVal("textSlotLeftYOffset") or 0
            local leftFontSz = DBVal("textSlotLeftSize") or defaults.textSlotLeftSize
            local leftC = (DB() and DB().textSlotLeftColor) or defaults.textSlotLeftColor
            if slotLeft == "enemyName" then
                PlaceNameInBar("LEFT", "LEFT", 4, "LEFT", leftXOff, leftYOff, leftFontSz, leftC.r, leftC.g, leftC.b, "textSlotLeft")
            else
                PlaceHealthInBar(slotLeft, "LEFT", "LEFT", 4 + leftXOff, leftYOff, leftFontSz, leftC.r, leftC.g, leftC.b, "textSlotLeft")
            end

            -- Process center slot
            local centerXOff = DBVal("textSlotCenterXOffset") or 0
            local centerYOff = DBVal("textSlotCenterYOffset") or 0
            local centerFontSz = DBVal("textSlotCenterSize") or defaults.textSlotCenterSize
            local centerC = (DB() and DB().textSlotCenterColor) or defaults.textSlotCenterColor
            if slotCenter == "enemyName" then
                PlaceNameInBar("CENTER", "CENTER", 0, "CENTER", centerXOff, centerYOff, centerFontSz, centerC.r, centerC.g, centerC.b, "textSlotCenter")
            else
                PlaceHealthInBar(slotCenter, "CENTER", "CENTER", centerXOff, centerYOff, centerFontSz, centerC.r, centerC.g, centerC.b, "textSlotCenter")
            end
            if DBVal("hideEnemyNameWhileCasting") == true then nameFS:Hide() end
            LayoutPreviewNameRaidMarker()

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
            -- Force the new justify onto already-rendered text (a JustifyH change
            -- alone does not re-flow it; only a fresh build does). See ns.ReflowFontString.
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

            -- Name/target/timer widths are set per-element above (each text uses its
            -- configured % of the bar width, the timer its reserved slot) to mirror
            -- the in-game layout.

            -- Helper: position a single preview frame into a slot
            local function PlaceInSlot(frame, slotName, index, count, iconW, iconH, slotSpacing, sxOff, syOff)
                sxOff = sxOff or 0
                syOff = syOff or 0
                -- Vertical center-to-center distance. Cropped icons are shorter,
                -- so vertically stacked slots (topleft/topright "up") pack
                -- tighter. slotSpacing is the horizontal (gap + width) distance;
                -- swap the width term for the height term. Equal when uncropped.
                local slotSpacingV = slotSpacing - iconW + iconH
                frame:ClearAllPoints()
                if slotName == "top" then
                    -- Anchor auras to whichever FontString is in the top slot
                    local anchor
                    if slotTop == "enemyName" then
                        anchor = nameFS
                    elseif slotTop == "healthNumber" then
                        anchor = hpNumber
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
                    local sideOff = DBVal("sideAuraXOffset") or defaults.sideAuraXOffset
                    frame:SetPoint("BOTTOMRIGHT", health, "BOTTOMLEFT", -sideOff - (index - 1) * slotSpacing + sxOff, syOff)
                elseif slotName == "right" then
                    local sideOff = DBVal("sideAuraXOffset") or defaults.sideAuraXOffset
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
                    if showDispelGlowPreview and DBVal("dispelGlow") == true
                        and DBVal("showAllEnemyBuffs") ~= true then
                        if buffs[i].dispelGlow and buffs[i].dispelGlow.active then
                            ns.StopDispelGlow(buffs[i])
                        end
                        ns.StartDispelGlow(buffs[i], buffSz, previewDispelColors[i])
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
                    if slotVal == "left" then
                        leftExtent = math.max(leftExtent, sideOff + (count - 1) * sp + sz - xOff)
                    elseif slotVal == "right" then
                        rightExtent = math.max(rightExtent, sideOff + (count - 1) * sp + sz + xOff)
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

            -- Height calculation "top" slot determines the area above the name
            -- Find which aura type is in the "top" slot for height,
            -- including per-slot Y offsets that push elements further up.
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

            -- Size the plain-Frame wrapper to match the health bar exactly.
            -- The image border lives on this wrapper (not on the StatusBar).
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

            -- Class power pips (preview). The renderer is a nested function, defined
            -- and called once right here, so its ~38 locals live in their own scope --
            -- pf.Update was over Lua 5.1's 200-local-per-function cap.
            pf.UpdateCP = function()
            local showCP = DBVal("showClassPower") == true
            local cpExtraH = 0
            local cpIsBarType = false
            local cpResourceName = nil
            if showCP then
                -- Determine pip count from player's class, using live UnitPowerMax when available
                local _, playerClass = UnitClass("player")
                local cpInfo = CP.CLASS_MAP[playerClass]
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

                    -- Pre-compute each pip's left-edge X in group-local coords.
                    -- Position by BOTTOMLEFT/TOPLEFT to avoid half-pixel center offsets.
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
            if showTargetGlowPreview and glowEUI then
                local gc = previewGlow.getGlowCol()
                local ga = previewGlow.getGlowAlpha()
                for _, t in ipairs(previewGlow.texs) do t:SetVertexColor(gc.r, gc.g, gc.b, ga) end
                pgf:Show()
            else
                pgf:Hide()
            end
            -- Border Color: override the preview border with the custom target color
            if showTargetGlowPreview and glowBorder then
                local bc = previewGlow.getBorderCol()
                for _, tex in ipairs(borderFrame._texs) do tex:SetVertexColor(bc.r, bc.g, bc.b) end
                for _, tex in ipairs(simpleBorderFrame._texs) do tex:SetVertexColor(bc.r, bc.g, bc.b) end
                for _, e in ipairs(_solidEdges) do e:SetColorTexture(bc.r, bc.g, bc.b, 1); UnsnapTex(e) end
            end
            -- Highlight: translucent wash across the preview health bar (color +
            -- opacity configurable via the Target Highlight cog)
            if previewGlow.highlight then
                local showHL = showTargetGlowPreview and glowHighlight
                if showHL then
                    local hc = previewGlow.getHighlightCol()
                    previewGlow.highlight:SetColorTexture(hc.r, hc.g, hc.b, previewGlow.getHighlightAlpha())
                end
                previewGlow.highlight:SetShown(showHL)
            end

            -- Absorb preview: update and toggle
            ToggleAbsorbPreview()

            -- Notify framework so the scroll area adjusts to the new preview height
            -- Add the preset header offset + bottom padding so the full content header
            -- height is reported (not just the preview frame height).
            -- totalH is in preview-local coordinates; convert to parent-space.
            local headerExtra = pf._headerExtra or 0
            local hintH = (_previewHintFS and _previewHintFS:IsShown()) and 29 or 0
            EllesmereUI:UpdateContentHeaderHeight(totalH * previewScale + headerExtra + hintH)

            -- Refresh text overlay sizes (font/text may have changed)
            if pf._textOverlays then
                for _, ov in ipairs(pf._textOverlays) do
                    if ov._resizeToText then ov._resizeToText() end
                end
            end
        end

        -- Expose preview elements for click-navigation hit overlays
        pf._nameFS       = nameFS
        pf._hpText       = hpText
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
        pf._health       = health
        pf._healthWrapper = healthWrapper
        pf._cpPips       = CP.pips
        pf._cpBar        = CP.bar
        pf._cpMax        = CP.MAX_POSSIBLE
        pf._arrows       = arrows

        activePreview = pf
        pf:Update()
        -- Return visual height in parent-scale pixels (pf:GetHeight() is local, scale it)
        return pf:GetHeight() * previewScale
    end

    ---------------------------------------------------------------------------
    --  General page  (Friendly settings, Spacing, Show All Debuffs)
    --  Two-column layout using DualRow where possible
    ---------------------------------------------------------------------------
    -- Pandemic preview: randomized spell icon with live glow
    -- Spell IDs mapped by class for preview icon (prioritize player's class)
    local PANDEMIC_PREVIEW_BY_CLASS = {
        DRUID   = { 1079, 8921 },       -- Rip, Moonfire
        DEATHKNIGHT = { 194310 },        -- Festering Wound
        PRIEST  = { 34914 },             -- Vampiric Touch
        WARLOCK = { 980 },               -- Agony
        ROGUE   = { 1943 },              -- Rupture
    }
    local PANDEMIC_PREVIEW_FALLBACK = { 1079, 8921, 194310, 34914, 980, 1943 }
    local _pandemicPreviewIcon  -- resolved icon fileID
    local _pandemicPreviewFrame -- the preview icon frame (persists across rebuilds)

    local function RandomizePandemicPreview()
        local _, playerClass = UnitClass("player")
        local pool = PANDEMIC_PREVIEW_BY_CLASS[playerClass] or PANDEMIC_PREVIEW_FALLBACK
        local spellID = pool[math.random(#pool)]
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spellID)
            if info and info.iconID then
                _pandemicPreviewIcon = info.iconID
            else
                _pandemicPreviewIcon = 136197
            end
        else
            _pandemicPreviewIcon = 136197
        end
        -- Update the texture on the existing frame if it exists
        if _pandemicPreviewFrame and _pandemicPreviewFrame._iconTex then
            _pandemicPreviewFrame._iconTex:SetTexture(_pandemicPreviewIcon)
        end
    end

    local function RefreshPandemicPreview()
        if not _pandemicPreviewFrame then return end
        local f = _pandemicPreviewFrame

        -- Create or reuse FlipBook overlay
        if not f._flipTex then
            local flipTex = f:CreateTexture(nil, "OVERLAY", nil, 7)
            flipTex:SetPoint("CENTER")
            local animGroup = flipTex:CreateAnimationGroup()
            animGroup:SetLooping("REPEAT")
            local flipAnim = animGroup:CreateAnimation("FlipBook")
            f._flipTex = flipTex
            f._animGroup = animGroup
            f._flipAnim = flipAnim
        end

        -- Stop all current animations
        f._animGroup:Stop()
        f._flipTex:Hide()
        ns.StopProceduralAnts(f)
        ns.StopButtonGlow(f)
        ns.StopAutoCastShine(f)

        -- Gray out preview when pandemic glow is off
        local off = DBVal("pandemicGlow") ~= true
        f:SetAlpha(off and 0.3 or 1)

        -- Only show glow if pandemic glow is enabled
        if off then return end

        -- Read the current glow style
        local styleIdx = ns.GetPandemicGlowStyle and ns.GetPandemicGlowStyle() or (DBVal("pandemicGlowStyle") or 1)
        if type(styleIdx) ~= "number" then styleIdx = 1 end
        local styles = ns.PANDEMIC_GLOW_STYLES
        if styleIdx < 1 or styleIdx > #styles then styleIdx = 1 end
        local entry = styles[styleIdx]

        local c = DB().pandemicGlowColor or defaults.pandemicGlowColor
        local cr, cg, cb = c.r, c.g, c.b
        local iconSize = 36

        if entry.procedural then
            -- Pixel Glow: procedural ants preview
            local N = DBVal("pandemicGlowLines") or defaults.pandemicGlowLines
            local th = DBVal("pandemicGlowThickness") or defaults.pandemicGlowThickness
            local speed = DBVal("pandemicGlowSpeed") or defaults.pandemicGlowSpeed
            local period = speed
            local lineLen = math.floor((iconSize + iconSize) * (2 / N - 0.1))
            lineLen = math.min(lineLen, iconSize)
            if lineLen < 1 then lineLen = 1 end
            local bgc = DB().pandemicGlowBackgroundColor or defaults.pandemicGlowBackgroundColor or { r = 0, g = 0, b = 0 }
            ns.StartProceduralAnts(f, N, th, period, lineLen, cr, cg, cb, iconSize, nil,
                DBVal("pandemicGlowBackground") == true and (bgc.r or 0) or nil, bgc.g or 0, bgc.b or 0)
        elseif entry.buttonGlow then
            -- Action Button Glow preview
            ns.StartButtonGlow(f, iconSize, cr, cg, cb, entry.previewScale or 1.28)
        elseif entry.autocast then
            -- Auto-Cast Shine preview
            ns.StartAutoCastShine(f, iconSize, cr, cg, cb)
        else
            -- FlipBook preview (GCD, Modern WoW, Classic WoW)
            local texSz = iconSize * (entry.previewScale or entry.scale or 1)
            f._flipTex:SetSize(texSz, texSz)
            if entry.atlas then
                f._flipTex:SetAtlas(entry.atlas)
            elseif entry.texture then
                f._flipTex:SetTexture(entry.texture)
            end
            f._flipAnim:SetFlipBookRows(entry.rows or 6)
            f._flipAnim:SetFlipBookColumns(entry.columns or 5)
            f._flipAnim:SetFlipBookFrames(entry.frames or 30)
            f._flipAnim:SetDuration(entry.duration or 1.0)
            f._flipAnim:SetFlipBookFrameWidth(entry.frameW or 0)
            f._flipAnim:SetFlipBookFrameHeight(entry.frameH or 0)

            -- Always apply color tint (fixes default FFEB96 showing as blue)
            f._flipTex:SetDesaturated(true)
            f._flipTex:SetVertexColor(cr, cg, cb)

            f._flipTex:Show()
            f._animGroup:Play()
        end
    end

    local function BuildGeneralPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local COGS_ICON = EllesmereUI.COGS_ICON
        local y = yOffset
        local _, h

        -- No preview on General tab
        EllesmereUI:ClearContentHeader()

        -- Randomize pandemic preview icon each time this tab is opened
        RandomizePandemicPreview()

        -- Enable per-row center divider for the dual-column layout
        parent._showRowDivider = true

        -----------------------------------------------------------------------
        --  FRIENDLY NAMEPLATES
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_FRIENDLY, y);  y = y - h

        local function friendlyPlayersOff() return DBVal("showFriendlyPlayers") == false end
        local function friendlyPlateOff() return friendlyPlayersOff() or DBVal("friendlyNameOnly") ~= false end
        local function nameOnlyOff() return friendlyPlayersOff() or DBVal("friendlyNameOnly") == false end

        local friendlyRow
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show EUI Friendly Player Nameplates",
              tooltip="When disabled, EUI relinquishes full control of friendly player nameplates to Blizzard. Use Blizzard's own Nameplate settings (Esc > Options > Nameplates) to control them.",
              getValue=function() return DBVal("showFriendlyPlayers") ~= false end,
              setValue=function(v)
                DB().showFriendlyPlayers = v
                if SetCVar then
                    if v then
                        -- Enabling: re-assert every friendly player CVar
                        -- that SetupAuraCVars sets on load. SetupAuraCVars
                        -- skips these while the toggle is off, so toggling
                        -- back on at runtime is the only chance to restore
                        -- them without a /reload.
                        local p = DB()
                        local nameOnly = (p and p.friendlyNameOnly ~= false)
                        local classColor = (p and p.classColorFriendly ~= false)
                        pcall(SetCVar, "nameplateShowFriendlyPlayers", 1)
                        pcall(SetCVar, "nameplateShowFriends", 1)
                        pcall(SetCVar, "UnitNameFriendlyPlayerName", 1)
                        pcall(SetCVar, "nameplateShowOnlyNameForFriendlyPlayerUnits", nameOnly and 1 or 0)
                        pcall(SetCVar, "ShowClassColorInFriendlyNameplate", classColor and 1 or 0)
                        pcall(SetCVar, "nameplateUseClassColorForFriendlyPlayerUnitNames", classColor and 1 or 0)
                    else
                        -- Disabling: reset the three CVars EUI uniquely
                        -- manages (name-only override + class color) back
                        -- to Blizzard defaults so the user starts from a
                        -- clean slate. The visibility CVars are left
                        -- untouched so the Blizzard Nameplate panel keeps
                        -- whatever the user already had there.
                        if GetCVarDefault then
                            for _, cvar in ipairs({
                                "nameplateShowOnlyNameForFriendlyPlayerUnits",
                                "ShowClassColorInFriendlyNameplate",
                                "nameplateUseClassColorForFriendlyPlayerUnitNames",
                            }) do
                                local d = GetCVarDefault(cvar)
                                if d ~= nil then pcall(SetCVar, cvar, d) end
                            end
                        end
                    end
                end
                if ns.UpdateFriendlyNameplateSystem then ns.UpdateFriendlyNameplateSystem() end
                -- Re-assert stacking after friendly CVar changes, since Blizzard
                -- can reset the stacking bitfield as a side effect.
                ns.RefreshStackingMotion()
                EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Make Friendly Nameplates Name Only",
              tooltip="Hide friendly player health bars and instead only see their names.\n\nRequires 'Simplified Friendly Nameplates' to be disabled in Blizzard's Nameplate settings (Esc > Options > Nameplates).",
              getValue=function() return DBVal("friendlyNameOnly") ~= false end,
              setValue=function(v)
                DB().friendlyNameOnly = v
                if SetCVar then pcall(SetCVar, "nameplateShowOnlyNameForFriendlyPlayerUnits", v and 1 or 0) end
                if ns.UpdateFriendlyNameplateSystem then ns.UpdateFriendlyNameplateSystem() end
                EllesmereUI:RefreshPage()
              end,
              disabled = friendlyPlayersOff,
              disabledTooltip = "Show EUI Friendly Player Nameplates" });  friendlyRow = _; y = y - h

        ---------------------------------------------------------------
        --  Friendly Player cog popup (Distance, Height, Width, Show Health %)
        ---------------------------------------------------------------
        do
            local fpPopup, fpPopupOwner
            local _, ShowFriendlyPlayerPopup = EllesmereUI.BuildCogPopup({
                title = "Friendly Nameplate Settings",
                rows = {
                    { type = "slider", label = "Distance", min = -50, max = 50, step = 1,
                      get = function() return DBVal("friendlyPlateYOffset") or 0 end,
                      set = function(v) DB().friendlyPlateYOffset = v; if ns.RefreshFriendlyPlateYOffset then ns.RefreshFriendlyPlateYOffset() end end },
                    { type = "slider", label = "Height", min = 6, max = 40, step = 1,
                      get = function() return DBVal("friendlyHealthBarHeight") or defaults.friendlyHealthBarHeight end,
                      set = function(v) DB().friendlyHealthBarHeight = v; if ns.RefreshFriendlyPlateSize then ns.RefreshFriendlyPlateSize() end end },
                    { type = "slider", label = "Width", min = 80, max = 250, step = 1,
                      get = function() return DBVal("friendlyHealthBarWidth") or defaults.friendlyHealthBarWidth end,
                      set = function(v) DB().friendlyHealthBarWidth = v; if ns.RefreshFriendlyPlateSize then ns.RefreshFriendlyPlateSize() end end },
                    { type = "slider", label = "Name Size", min = 6, max = 30, step = 1,
                      get = function() return DBVal("friendlyNameTextSize") or defaults.friendlyNameTextSize end,
                      set = function(v) DB().friendlyNameTextSize = v; if ns.RefreshFriendlyNameTextSize then ns.RefreshFriendlyNameTextSize() end end },
                    { type = "toggle", label = "Show Health Percent",
                      get = function() local db = DB(); return not (db and db.friendlyHideHealthText) end,
                      set = function(v)
                        DB().friendlyHideHealthText = not v
                        if ns.RefreshFriendlyHealthText then ns.RefreshFriendlyHealthText() end
                      end },
                    { type = "toggle", label = "Class Colored",
                      get = function() return DBVal("classColorFriendly") ~= false end,
                      set = function(v)
                        DB().classColorFriendly = v and true or false
                        ns.RefreshAllSettings()
                        if ns.RefreshFriendlyColors then ns.RefreshFriendlyColors() end
                      end },
                },
            })

            local rgn = friendlyRow._leftRegion
            local btn = CreateFrame("Button", nil, rgn)
            btn:SetSize(26, 26)
            btn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
            btn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            btn:SetAlpha(friendlyPlateOff() and 0.15 or 0.4)
            local tex = btn:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints(); tex:SetTexture(COGS_ICON)
            btn:SetScript("OnEnter", function(self)
                if friendlyPlateOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "Requires Name Only setting to be disabled")
                else self:SetAlpha(0.7) end
            end)
            btn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                if fpPopupOwner ~= self then self:SetAlpha(friendlyPlateOff() and 0.15 or 0.4) end
            end)
            btn:SetScript("OnClick", function(self)
                if friendlyPlateOff() then return end
                ShowFriendlyPlayerPopup(self)
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                if fpPopupOwner ~= btn then btn:SetAlpha(friendlyPlateOff() and 0.15 or 0.4) end
            end)
        end

        ---------------------------------------------------------------
        --  Name Only inline color swatches (White + Class Color).
        --  Replaces the old cog. Mirrors the Target Arrows double-swatch
        --  pattern: the "Class Colored" setting (classColorFriendly) decides
        --  which swatch is active; the inactive one dims. Neither swatch
        --  opens a color picker -- White is fixed, Class follows the player's
        --  class color. Both gray out when Name Only mode is off.
        ---------------------------------------------------------------
        do
            local rightRgn = friendlyRow._rightRegion
            local whiteSwatch, updateWhite, classSwatch, updateClass
            local function refreshNameSwatches()
                if updateWhite then updateWhite() end
                if updateClass then updateClass() end
                local off = nameOnlyOff()
                local useClass = DBVal("classColorFriendly") ~= false
                whiteSwatch:SetAlpha(off and 0.15 or (useClass and 0.3 or 1))
                classSwatch:SetAlpha(off and 0.15 or (useClass and 1 or 0.3))
                whiteSwatch:SetMouseClickEnabled(not off)
                classSwatch:SetMouseClickEnabled(not off)
            end
            local function ApplyClassColored(useClass)
                DB().classColorFriendly = useClass and true or false
                if SetCVar then
                    pcall(SetCVar, "ShowClassColorInFriendlyNameplate", useClass and 1 or 0)
                    pcall(SetCVar, "nameplateUseClassColorForFriendlyPlayerUnitNames", useClass and 1 or 0)
                end
                if ns.RefreshAllSettings then ns.RefreshAllSettings() end
                if ns.RefreshFriendlyColors then ns.RefreshFriendlyColors() end
                refreshNameSwatches()
            end
            -- White swatch: fixed white, not editable. Clicking only selects
            -- the non-class-colored mode (the default OnClick color picker is
            -- replaced below).
            whiteSwatch, updateWhite = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                function() return 1, 1, 1 end,
                function() end, nil, 20)
            PP.Point(whiteSwatch, "RIGHT", rightRgn._control, "LEFT", -8, 0)
            whiteSwatch:SetScript("OnClick", function()
                if nameOnlyOff() then return end
                ApplyClassColored(false)
            end)
            whiteSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(whiteSwatch, "White") end)
            whiteSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            -- Class color swatch: shows the player's class color; selects
            -- class-colored mode.
            classSwatch, updateClass = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                function()
                    local _, ct = UnitClass("player")
                    local cc = ct and C_ClassColor and C_ClassColor.GetClassColor(ct)
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            PP.Point(classSwatch, "RIGHT", whiteSwatch, "LEFT", -8, 0)
            rightRgn._lastInline = classSwatch
            classSwatch:SetScript("OnClick", function()
                if nameOnlyOff() then return end
                ApplyClassColored(true)
            end)
            classSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Color") end)
            classSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(refreshNameSwatches)
            refreshNameSwatches()
        end

        local npcRow
        npcRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Friendly NPC Nameplates",
              getValue=function() return DBVal("showFriendlyNPCs") == true end,
              setValue=function(v)
                DB().showFriendlyNPCs = v
                if SetCVar then
                    pcall(SetCVar, "nameplateShowFriendlyNPCs", v and 1 or 0)
                    pcall(SetCVar, "nameplateShowFriendlyNpcs", v and 1 or 0)
                end
                if ns.UpdateFriendlyNameplateSystem then ns.UpdateFriendlyNameplateSystem() end
                EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Friendly Name Size", trackWidth=120,
              min=8, max=30, step=1,
              disabled=nameOnlyOff,
              disabledTooltip="Make Friendly Nameplates Name Only",
              getValue=function() return DBVal("friendlyNameSize") or defaults.friendlyNameSize end,
              setValue=function(v)
                DB().friendlyNameSize = v
                if ns.RefreshFriendlyNameSize then ns.RefreshFriendlyNameSize() end
              end,
              tooltip="Adjusts the size of friendly player names shown in Name Only mode. Default is 15." });  y = y - h

        -- Cog popup for NPC nameplate settings (Show NPC Titles)
        do
            -- Retained (always nil) so the cog button's legacy owner checks stay
            -- harmless after the popup itself moved to the shared BuildCogPopup.
            local npcCogPopup, npcCogPopupOwner
            local function npcOff() return DBVal("showFriendlyNPCs") ~= true end

            local _, ShowNPCCogPopup = EllesmereUI.BuildCogPopup({
                title = "Friendly NPC Settings",
                rows = {
                    { type = "toggle", label = "Show NPC Titles",
                      get = function() return DBVal("showNPCTitles") ~= false end,
                      set = function(v)
                        DB().showNPCTitles = v and true or false
                        if ns.RefreshAllNPCOverlays then ns.RefreshAllNPCOverlays() end
                      end },
                    { type = "slider", label = "Name Only Size", min = 6, max = 30, step = 1,
                      get = function() return DBVal("friendlyNPCNameSize") or defaults.friendlyNPCNameSize end,
                      set = function(v)
                        DB().friendlyNPCNameSize = v
                        if ns.RefreshAllNPCOverlays then ns.RefreshAllNPCOverlays() end
                      end },
                },
            })

            local rgn = npcRow._leftRegion
            local btn = CreateFrame("Button", nil, rgn)
            btn:SetSize(26, 26)
            btn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
            btn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            btn:SetAlpha(npcOff() and 0.15 or 0.4)
            local tex = btn:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints(); tex:SetTexture(COGS_ICON)
            btn:SetScript("OnEnter", function(self)
                if npcOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "Requires Show Friendly NPC Nameplates to be enabled")
                else self:SetAlpha(0.7) end
            end)
            btn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                if npcCogPopupOwner ~= self then self:SetAlpha(npcOff() and 0.15 or 0.4) end
            end)
            btn:SetScript("OnClick", function(self)
                if npcOff() then return end
                ShowNPCCogPopup(self)
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                if npcCogPopupOwner ~= btn then btn:SetAlpha(npcOff() and 0.15 or 0.4) end
            end)

            -- Inline color swatch: friendly NPC bar & name color. Our own bars
            -- and text, so this is freely customizable -- but only in full-plate
            -- mode. Disabled in Name Only mode (NPCs use a reaction-colored name
            -- overlay there) and when friendly NPC nameplates are hidden.
            local function npcColorOff() return npcOff() or DBVal("friendlyNameOnly") ~= false end
            local npcSwatch, updateNpcSwatch
            local function refreshNpcSwatch()
                if updateNpcSwatch then updateNpcSwatch() end
                local off = npcColorOff()
                npcSwatch:SetAlpha(off and 0.3 or 1)
                npcSwatch:SetMouseClickEnabled(not off)
            end
            npcSwatch, updateNpcSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                function() local c = DBVal("friendlyNPCColor") or defaults.friendlyNPCColor; return c.r, c.g, c.b end,
                function(r, g, b)
                    DB().friendlyNPCColor = { r = r, g = g, b = b }
                    if ns.RefreshFriendlyColors then ns.RefreshFriendlyColors() end
                    refreshNpcSwatch()
                end, nil, 20)
            PP.Point(npcSwatch, "RIGHT", btn, "LEFT", -8, 0)
            rgn._lastInline = npcSwatch
            local origNpcClick = npcSwatch:GetScript("OnClick")
            npcSwatch:SetScript("OnClick", function(self, ...)
                if npcColorOff() then return end
                if origNpcClick then origNpcClick(self, ...) end
            end)
            npcSwatch:SetScript("OnEnter", function(self)
                if npcOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "Requires Show Friendly NPC Nameplates to be enabled")
                elseif DBVal("friendlyNameOnly") ~= false then
                    EllesmereUI.ShowWidgetTooltip(self, "Requires Name Only mode to be disabled")
                else
                    EllesmereUI.ShowWidgetTooltip(self, "NPC Bar & Name Color")
                end
            end)
            npcSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(refreshNpcSwatch)
            refreshNpcSwatch()
        end

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Friendly Names Not Clickable",
              tooltip="Make friendly player and NPC nameplates click-through so their names never block your mouse or cause accidental friendly targeting.\n\nUse this when friendly names get in the way of clicking the world or the enemy nameplates behind them.",
              getValue=function() return DBVal("friendlyClickThrough") == true end,
              setValue=function(v)
                DB().friendlyClickThrough = v
                if ns.UpdateFriendlyClickThrough then ns.UpdateFriendlyClickThrough() end
              end },
            { type="toggle", text="Show Enemy Pet Nameplates",
              getValue=function() return DBVal("showEnemyPets") == true end,
              setValue=function(v)
                DB().showEnemyPets = v
                if SetCVar then pcall(SetCVar, "nameplateShowEnemyPets", v and 1 or 0) end
              end,
              tooltip="Toggle visibility of enemy pet nameplates." });  y = y - h

        -- Inline DIRECTIONS cog on Friendly Name Size: name-only vertical distance
        do
            local _, distCogShow = EllesmereUI.BuildCogPopup({
                title = "Name Distance",
                rows = {
                    { type = "slider", label = "Distance", min = -50, max = 50, step = 1,
                      get = function() return DBVal("friendlyNameOnlyYOffset") or defaults.friendlyNameOnlyYOffset end,
                      set = function(v)
                        DB().friendlyNameOnlyYOffset = v
                        if ns.RefreshFriendlyNameOnlyOffset then ns.RefreshFriendlyNameOnlyOffset() end
                      end },
                },
            })
            local rgn = npcRow._rightRegion
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            if cogTex.SetSnapToPixelGrid then cogTex:SetSnapToPixelGrid(false); cogTex:SetTexelSnappingBias(0) end
            cogBtn:SetScript("OnEnter", function(self)
                if nameOnlyOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "Requires Name Only mode")
                else self:SetAlpha(0.7) end
            end)
            cogBtn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                self:SetAlpha(nameOnlyOff() and 0.15 or 0.4)
            end)
            cogBtn:SetScript("OnClick", function(self)
                if nameOnlyOff() then return end
                distCogShow(self)
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                cogBtn:SetAlpha(nameOnlyOff() and 0.15 or 0.4)
            end)
            cogBtn:SetAlpha(nameOnlyOff() and 0.15 or 0.4)
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  ENEMY NAMEPLATE SPACING
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_ENEMY_NP, y);  y = y - h

        local stackingRow
        stackingRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Stacking Nameplates",
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end },
            { type="slider", text="Stacked Nameplate Spacing",
              trackWidth=130,
              min=50, max=200, step=5,
              getValue=function() return DBVal("stackSpacingScale") or defaults.stackSpacingScale end,
              setValue=function(v)
                DB().stackSpacingScale = v
                ns.RefreshStackingBounds()
              end,
              tooltip="Adjusts the vertical spacing between stacked nameplates. 100% = default, lower = tighter, higher = more spread." });  y = y - h

        -- Replace the placeholder dropdown with a multi-select checkbox dropdown.
        -- Enemy and Friendly stacking are independent toggles over the Midnight
        -- stacking bitfield. Friendly is locked out while EUI is not managing
        -- friendly player nameplates, since Blizzard owns that stacking bit then.
        do
            local leftRgn = stackingRow._leftRegion
            if leftRgn._control then leftRgn._control:Hide() end
            local stackItems = {
                { key = "enemy",    label = "Enemy Nameplates" },
                { key = "friendly", label = "Friendly Nameplates",
                  lockedFn = function() return DBVal("showFriendlyPlayers") == false end },
            }
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                leftRgn, 170, leftRgn:GetFrameLevel() + 2,
                stackItems,
                function(k)
                    if k == "enemy" then return DBVal("stackingEnabled") ~= false end
                    if k == "friendly" then return DBVal("stackingFriendly") == true end
                    return false
                end,
                function(k, v)
                    if k == "enemy" then DB().stackingEnabled = v
                    elseif k == "friendly" then DB().stackingFriendly = v end
                    ns.RefreshStackingMotion()
                end)
            PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
            leftRgn._control = cbDD
            cbDD:HookScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cbDD, "Choose which nameplates stack vertically instead of overlapping.")
            end)
            cbDD:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        local hitboxRow
        hitboxRow, h = W:DualRow(parent, y,
            { type="slider", text="Hitbox Size X",
              min=50, max=250, step=5,
              getValue=function() return DBVal("hitboxScaleX") or defaults.hitboxScaleX end,
              setValue=function(v)
                DB().hitboxScaleX = v
                ns.RefreshHitboxSize()
              end,
              tooltip="Widens the clickable hitbox of enemy nameplates. 100% = matches bar width. Increase to make nameplates easier to click." },
            { type="slider", text="Hitbox Size Y",
              min=50, max=250, step=5,
              getValue=function() return DBVal("hitboxScaleY") or defaults.hitboxScaleY end,
              setValue=function(v)
                DB().hitboxScaleY = v
                ns.RefreshHitboxSize()
              end,
              tooltip="Increases the clickable hitbox height of enemy nameplates. 100% = matches bar height. Increase to make nameplates easier to click." });  y = y - h

        -- Eyeball toggle on Hitbox Size X: shows a translucent overlay on real
        -- enemy nameplates marking the clickable area, so the sliders can be
        -- dialled in visually. Runtime-only; auto-hides when the panel closes.
        do
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
            local leftRgn = hitboxRow._leftRegion
            local eyeBtn = CreateFrame("Button", nil, leftRgn)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            eyeBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            eyeBtn:SetAlpha(0.4)
            leftRgn._lastInline = eyeBtn
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function RefreshEyeIcon()
                eyeTex:SetTexture(ns._hitboxOverlayShown and EYE_INVISIBLE or EYE_VISIBLE)
            end
            RefreshEyeIcon()
            eyeBtn:SetScript("OnClick", function()
                if ns.SetHitboxOverlayShown then ns.SetHitboxOverlayShown(not ns._hitboxOverlayShown) end
                RefreshEyeIcon()
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, "Show/Hide Hitbox Overlay", { width = 175 })
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                self:SetAlpha(0.4)
                EllesmereUI.HideWidgetTooltip()
            end)
            -- Auto-hide the overlay when the options panel closes (hook once).
            if not ns._hitboxOverlayCloseHook and EllesmereUI._mainFrame then
                ns._hitboxOverlayCloseHook = true
                EllesmereUI._mainFrame:HookScript("OnHide", function()
                    if ns._hitboxOverlayShown and ns.SetHitboxOverlayShown then
                        ns.SetHitboxOverlayShown(false)
                    end
                end)
            end
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  EXTRA AURA OPTIONS
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_AURA, y);  y = y - h

        -- 12.0: Show All Your Player Debuffs | Max Debuffs. On 12.1 the
        -- per-kind Edit Filters popups (Core Positions) own Show All -- the
        -- legacy key seeded the new defaults once -- so the row becomes
        -- Max Debuffs | blank (row 1 slot 1 per spec).
        local maxDbfOriginal = DBVal("maxDebuffs") or defaults.maxDebuffs
        local maxDbfPendingPopup
        local npShowAllCfg
        if not EllesmereUI.IS_121 then
            npShowAllCfg =
            { type="toggle", text="Show All Your Player Debuffs",
              getValue=function() return DBVal("showAllDebuffs") == true end,
              setValue=function(v)
                DB().showAllDebuffs = v
                RefreshAllAuras()
              end,
              tooltip="This will display ALL of your debuffs on enemy nameplates, rather than only the important ones." }
        end
        local maxDbfCfg =
            { type="slider", text="Max Debuffs", min=1, max=10, step=1,
              getValue=function() return DBVal("maxDebuffs") or defaults.maxDebuffs end,
              setValue=function(v)
                DB().maxDebuffs = v
                -- 12.1 containers raise/lower the group's frame cap live
                -- (SetAuraGroupMaxFrameCount inside the reload's cfg pass).
                if ns.NPC_ReloadAll then
                    ns.NPC_ReloadAll()
                    return
                end
                -- Legacy pools are sized at plate creation: show the reload
                -- popup once after the slider drag ends (debounced).
                if v ~= maxDbfOriginal then
                    if maxDbfPendingPopup then maxDbfPendingPopup:Cancel() end
                    maxDbfPendingPopup = C_Timer.NewTimer(0.5, function()
                        maxDbfPendingPopup = nil
                        if (DB().maxDebuffs or defaults.maxDebuffs) ~= maxDbfOriginal then
                            EllesmereUI:ShowConfirmPopup({
                                title = "Reload Required",
                                message = "Changing Max Debuffs requires a UI reload to take effect.",
                                confirmText = "Reload Now",
                                cancelText = "Later",
                                onConfirm = function() ReloadUI() end,
                            })
                        end
                    end)
                end
              end,
              tooltip="Maximum number of debuff icons shown on enemy nameplates." }
        local debuffRow1
        if EllesmereUI.IS_121 then
            debuffRow1, h = W:DualRow(parent, y, maxDbfCfg, { type="label", text="" });  y = y - h
        else
            debuffRow1, h = W:DualRow(parent, y, npShowAllCfg, maxDbfCfg);  y = y - h
        end

        -- Helper: pandemic glow is off when style is "None"
        local function pandemicOff()
            return DBVal("pandemicGlow") ~= true
        end

        -- Pandemic glow style dropdown + inline color swatch + cog
        -- "None" disables pandemic glow entirely (replaces the old toggle)
        local glowStyleValues = { [0] = "None" }
        local glowStyleOrder = { 0 }
        local styles = ns.PANDEMIC_GLOW_STYLES
        for i, entry in ipairs(styles) do
            glowStyleValues[i] = entry.name
            glowStyleOrder[#glowStyleOrder + 1] = i
        end

        local glowStyleRow
        glowStyleRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Pandemic Glow Style",
              values=glowStyleValues,
              getValue=function()
                if pandemicOff() then return 0 end
                local raw = ns.GetPandemicGlowStyle and ns.GetPandemicGlowStyle() or (DBVal("pandemicGlowStyle") or 1)
                if type(raw) ~= "number" then return 1 end
                if raw < 1 or raw > #ns.PANDEMIC_GLOW_STYLES then return 1 end
                return raw
              end,
              setValue=function(v)
                if v == 0 then
                    DB().pandemicGlow = false
                else
                    DB().pandemicGlow = true
                    DB().pandemicGlowStyle = v
                end
                RefreshAllAuras()
                RefreshPandemicPreview()
                C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
              end,
              order=glowStyleOrder },
            { type="label", text="Pandemic Glow Preview" });  y = y - h

        -- Glow Preview icon: built into the right half of the glow style row
        do
            local SIDE_PAD = 20

            local iconSize = 36
            local iconFrame = CreateFrame("Frame", nil, glowStyleRow)
            PP.Size(iconFrame, iconSize, iconSize)
            PP.Point(iconFrame, "RIGHT", glowStyleRow, "RIGHT", -SIDE_PAD, 0)

            local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
            iconTex:SetAllPoints()
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            iconTex:SetTexture(_pandemicPreviewIcon or 136197)
            iconFrame._iconTex = iconTex

            -- 1px black border
            local function AddIconBorder(p)
                local onePx = PP.Scale(1)
                local function mkB(anchor1, rel, anchor2, isH)
                    local t = p:CreateTexture(nil, "OVERLAY", nil, 7)
                    t:SetColorTexture(0, 0, 0, 1)
                    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
                    PP.Point(t, anchor1, p, anchor1, 0, 0)
                    PP.Point(t, anchor2, p, anchor2, 0, 0)
                    if isH then t:SetHeight(onePx) else t:SetWidth(onePx) end
                    return t
                end
                local tEdge = mkB("TOPLEFT", p, "TOPRIGHT", true)
                local bEdge = mkB("BOTTOMLEFT", p, "BOTTOMRIGHT", true)
                local lEdge = p:CreateTexture(nil, "OVERLAY", nil, 7)
                lEdge:SetColorTexture(0, 0, 0, 1)
                if lEdge.SetSnapToPixelGrid then lEdge:SetSnapToPixelGrid(false); lEdge:SetTexelSnappingBias(0) end
                PP.Point(lEdge, "TOPLEFT", tEdge, "BOTTOMLEFT", 0, 0)
                PP.Point(lEdge, "BOTTOMLEFT", bEdge, "TOPLEFT", 0, 0)
                lEdge:SetWidth(onePx)
                local rEdge = p:CreateTexture(nil, "OVERLAY", nil, 7)
                rEdge:SetColorTexture(0, 0, 0, 1)
                if rEdge.SetSnapToPixelGrid then rEdge:SetSnapToPixelGrid(false); rEdge:SetTexelSnappingBias(0) end
                PP.Point(rEdge, "TOPRIGHT", tEdge, "BOTTOMRIGHT", 0, 0)
                PP.Point(rEdge, "BOTTOMRIGHT", bEdge, "TOPRIGHT", 0, 0)
                rEdge:SetWidth(onePx)
            end
            AddIconBorder(iconFrame)

            _pandemicPreviewFrame = iconFrame
            RefreshPandemicPreview()

            -- Gray out preview + label when pandemic glow is off (style = None)
            local previewLabel = ({ glowStyleRow._rightRegion:GetRegions() })[1]
            local function UpdatePreviewGrayOut()
                local off = pandemicOff()
                iconFrame:SetAlpha(off and 0.3 or 1)
                if previewLabel and previewLabel.SetAlpha then
                    previewLabel:SetAlpha(off and 0.3 or 1)
                end
            end
            EllesmereUI.RegisterWidgetRefresh(function()
                UpdatePreviewGrayOut()
                -- Re-render the glow so external changes (e.g. the CDM
                -- "Apply to: All" sync) update the preview, not just the
                -- dropdown label. Mirrors the CDM pandemic preview.
                RefreshPandemicPreview()
            end)
            UpdatePreviewGrayOut()
        end

        -- Inline color swatch next to the Glow Style dropdown
        do
            local glowColorGet = function()
                local c = DB().pandemicGlowColor or defaults.pandemicGlowColor
                return c.r, c.g, c.b
            end
            local glowColorSet = function(r, g, b)
                DB().pandemicGlowColor = { r = r, g = g, b = b }
                RefreshAllAuras()
                RefreshPandemicPreview()
            end
            local leftRgn = glowStyleRow._leftRegion
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, glowColorGet, glowColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = swatch
            -- Gray out swatch when pandemic glow is off
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = pandemicOff()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            swatch:SetAlpha(pandemicOff() and 0.15 or 1)
            swatch:EnableMouse(not pandemicOff())
        end

        -- Apply-to-All: push this nameplate pandemic glow out to all CDM bars.
        -- The coordinator lives in the CDM core, so the link only appears when
        -- that module is loaded (otherwise there's nothing to sync to).
        if EllesmereUI.BuildSyncIcon and EllesmereUI.ApplyPandemicGlowToAll then
            EllesmereUI.BuildSyncIcon({
                region = glowStyleRow._leftRegion,
                tooltip = "Apply this pandemic glow to all CDM bars and tracking bars. A surface that can't show a style uses its closest match.",
                isSynced = function()
                    return EllesmereUI.IsPandemicGlowSyncedToAll(
                        EllesmereUI.PandemicPayloadFromNameplate(DB()), { skipNameplates = true })
                end,
                onClick = function()
                    EllesmereUI.ApplyPandemicGlowToAll(
                        EllesmereUI.PandemicPayloadFromNameplate(DB()), { skipNameplates = true })
                    C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
                end,
            })
        end

        -- Pixel Glow sub-options: only enabled when style is "Pixel Glow" (index 1)
        local function antsOff()
            if pandemicOff() then return true end
            local raw = DBVal("pandemicGlowStyle")
            if type(raw) ~= "number" then return true end
            return raw ~= 1
        end

        -- Cog popup for Pixel Glow settings.
        do
            local pgPopup, pgPopupOwner
            local function ShowPixelGlowPopup(anchorBtn)
                if not pgPopup then
                    local SolidTex   = EllesmereUI.SolidTex
                    local MakeBorder = EllesmereUI.MakeBorder
                    local MakeFont   = EllesmereUI.MakeFont
                    local BuildSliderCore = EllesmereUI.BuildSliderCore
                    local BuildToggleControl = EllesmereUI.BuildToggleControl
                    local BuildColorSwatch = EllesmereUI.BuildColorSwatch
                    local BORDER_COLOR   = EllesmereUI.BORDER_COLOR
                    local SL_INPUT_A     = EllesmereUI.SL_INPUT_A

                    local SIDE_PAD = 14; local TOP_PAD = 14
                    local TITLE_H = 11; local TITLE_GAP = 10; local GAP = 10
                    local ROW_H = 24
                    local POPUP_INPUT_A = 0.55

                    local INPUT_W = 34; local SLIDER_INPUT_GAP = 8; local LABEL_SLIDER_GAP = 12
                    local MIN_POPUP_W = 180

                    local totalH = TOP_PAD + TITLE_H + TITLE_GAP + GAP
                                 + ROW_H + GAP + ROW_H + GAP + ROW_H + GAP + ROW_H + GAP + ROW_H
                                 + TOP_PAD

                    local pf = CreateFrame("Frame", nil, UIParent)
                    pf:SetSize(260, totalH)
                    pf:SetFrameStrata("DIALOG"); pf:SetFrameLevel(200)
                    pf:EnableMouse(true); pf:Hide()
                    -- Match panel/popup scale (otherwise renders oversized).
                    pf:SetScale((EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1)
                    if EllesmereUI._popupFrames then
                        EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = pf }
                    end

                    local bg = SolidTex(pf, "BACKGROUND", 0.06, 0.08, 0.10, 0.95)
                    bg:SetAllPoints()
                    MakeBorder(pf, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15)

                    local titleFS = MakeFont(pf, 11, "", 1, 1, 1)
                    titleFS:SetAlpha(0.7)
                    titleFS:SetPoint("TOP", pf, "TOP", 0, -TOP_PAD)
                    titleFS:SetText(EllesmereUI.L("Pixel Glow Settings"))

                    -- Measure label widths to compute layout BEFORE creating sliders
                    local tmpFS = pf:CreateFontString(nil, "OVERLAY")
                    tmpFS:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, GetNPOptOutline())
                    local labelTexts = {"Lines", "Thickness", "Speed", "Background", "Background Color"}
                    local maxLblW = 0
                    for _, txt in ipairs(labelTexts) do
                        tmpFS:SetText(txt)
                        local w = tmpFS:GetStringWidth()
                        if w > maxLblW then maxLblW = w end
                    end
                    tmpFS:Hide()
                    if maxLblW < 10 then maxLblW = 60 end

                    local SLIDER_LEFT = SIDE_PAD + maxLblW + LABEL_SLIDER_GAP
                    local SLIDER_W = math.max(80, 260 - SLIDER_LEFT - SLIDER_INPUT_GAP - INPUT_W - SIDE_PAD)
                    local POPUP_W = math.max(MIN_POPUP_W, SLIDER_LEFT + SLIDER_W + SLIDER_INPUT_GAP + INPUT_W + SIDE_PAD)
                    pf:SetWidth(POPUP_W)

                    -- Row 1: Lines
                    local r1Y = -(TOP_PAD + TITLE_H + TITLE_GAP + GAP)
                    local lbl1 = MakeFont(pf, 11, nil, 1, 1, 1); lbl1:SetAlpha(0.6)
                    lbl1:SetText(EllesmereUI.L("Lines")); lbl1:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r1Y)
                    local t1, v1 = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, ROW_H, 11, POPUP_INPUT_A,
                        2, 16, 1,
                        function() return DBVal("pandemicGlowLines") or defaults.pandemicGlowLines end,
                        function(v) DB().pandemicGlowLines = v; RefreshAllAuras(); RefreshPandemicPreview() end, true)
                    t1:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, r1Y - 2)
                    v1:ClearAllPoints(); v1:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r1Y)

                    -- Row 2: Thickness
                    local r2Y = r1Y - ROW_H - GAP
                    local lbl2 = MakeFont(pf, 11, nil, 1, 1, 1); lbl2:SetAlpha(0.6)
                    lbl2:SetText(EllesmereUI.L("Thickness")); lbl2:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r2Y)
                    local t2, v2 = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, ROW_H, 11, POPUP_INPUT_A,
                        1, 4, 1,
                        function() return DBVal("pandemicGlowThickness") or defaults.pandemicGlowThickness end,
                        function(v) DB().pandemicGlowThickness = v; RefreshAllAuras(); RefreshPandemicPreview() end, true)
                    t2:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, r2Y - 2)
                    v2:ClearAllPoints(); v2:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r2Y)

                    -- Row 3: Speed (inverted: display = 9 - stored)
                    local r3Y = r2Y - ROW_H - GAP
                    local lbl3 = MakeFont(pf, 11, nil, 1, 1, 1); lbl3:SetAlpha(0.6)
                    lbl3:SetText(EllesmereUI.L("Speed")); lbl3:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r3Y)
                    local t3, v3 = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, ROW_H, 11, POPUP_INPUT_A,
                        1, 8, 1,
                        function()
                            local period = DBVal("pandemicGlowSpeed") or defaults.pandemicGlowSpeed
                            return 9 - period
                        end,
                        function(v) DB().pandemicGlowSpeed = 9 - v; RefreshAllAuras(); RefreshPandemicPreview() end, true)
                    t3:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, r3Y - 2)
                    v3:ClearAllPoints(); v3:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r3Y)

                    -- Row 4: Background
                    local r4Y = r3Y - ROW_H - GAP
                    local lbl4 = MakeFont(pf, 11, nil, 1, 1, 1); lbl4:SetAlpha(0.6)
                    lbl4:SetText(EllesmereUI.L("Background")); lbl4:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r4Y)
                    local bgToggle, _, bgSnap = BuildToggleControl(pf, pf:GetFrameLevel() + 2,
                        function() return DBVal("pandemicGlowBackground") == true end,
                        function(v)
                            DB().pandemicGlowBackground = v and true or nil
                            RefreshAllAuras(); RefreshPandemicPreview()
                        end, { sizeRatio = 0.8, noAnim = true })
                    bgToggle:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, r4Y - ROW_H / 2)

                    -- Row 5: Background Color
                    local r5Y = r4Y - ROW_H - GAP
                    local lbl5 = MakeFont(pf, 11, nil, 1, 1, 1); lbl5:SetAlpha(0.6)
                    lbl5:SetText(EllesmereUI.L("Background Color")); lbl5:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r5Y)
                    local bgSwatch, bgUpdate = BuildColorSwatch(pf, pf:GetFrameLevel() + 2,
                        function()
                            local c = DB().pandemicGlowBackgroundColor or defaults.pandemicGlowBackgroundColor or { r = 0, g = 0, b = 0 }
                            return c.r or 0, c.g or 0, c.b or 0
                        end,
                        function(r, g, b)
                            DB().pandemicGlowBackgroundColor = { r = r, g = g, b = b }
                            RefreshAllAuras(); RefreshPandemicPreview()
                        end, false, 20)
                    bgSwatch:ClearAllPoints()
                    bgSwatch:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, r5Y - ROW_H / 2)
                    local bgBlock = CreateFrame("Frame", nil, bgSwatch)
                    bgBlock:SetAllPoints(); bgBlock:SetFrameLevel(bgSwatch:GetFrameLevel() + 10); bgBlock:EnableMouse(true)
                    bgBlock:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(bgSwatch, EllesmereUI.DisabledTooltip("Pixel Glow Background"))
                    end)
                    bgBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                    local function RefreshBgControls()
                        if bgSnap then bgSnap() end
                        if bgUpdate then bgUpdate() end
                        local on = DBVal("pandemicGlowBackground") == true
                        bgSwatch:SetAlpha(on and 1 or 0.3)
                        if on then bgBlock:Hide() else bgBlock:Show() end
                    end
                    bgToggle:HookScript("OnClick", RefreshBgControls)
                    pf._refreshBgControls = RefreshBgControls
                    RefreshBgControls()

                    -- Close on click outside
                    local wasDown = false
                    pf:SetScript("OnHide", function(self)
                        self:SetScript("OnUpdate", nil)
                        if pgPopupOwner then pgPopupOwner:SetAlpha(0.4) end
                        pgPopupOwner = nil
                    end)
                    pf._clickOutside = function(self, dt)
                        local down = IsMouseButtonDown("LeftButton")
                        if down and not wasDown then
                            if not self:IsMouseOver() and not (pgPopupOwner and pgPopupOwner:IsMouseOver()) then
                                self:Hide()
                            end
                        end
                        wasDown = down
                    end

                    if EllesmereUI._mainFrame then
                        EllesmereUI._mainFrame:HookScript("OnHide", function()
                            if pf:IsShown() then pf:Hide() end
                        end)
                    end

                    pgPopup = pf
                end

                if pgPopupOwner == anchorBtn and pgPopup:IsShown() then
                    pgPopup:Hide(); return
                end
                pgPopupOwner = anchorBtn

                if pgPopup._refreshBgControls then pgPopup._refreshBgControls() end
                pgPopup:ClearAllPoints()
                pgPopup:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6)
                pgPopup:SetAlpha(0)
                pgPopup:Show()
                local elapsed = 0
                pgPopup:SetScript("OnUpdate", function(self, dt)
                    elapsed = elapsed + dt
                    local t = math.min(elapsed / 0.15, 1)
                    self:SetAlpha(t)
                    self:ClearAllPoints()
                    self:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6 + (-8 * (1 - t)))
                    if t >= 1 then self:SetScript("OnUpdate", self._clickOutside) end
                end)
            end

            local leftRgn2 = glowStyleRow._leftRegion
            local btn = CreateFrame("Button", nil, leftRgn2)
            btn:SetSize(26, 26)
            btn:SetPoint("RIGHT", leftRgn2._lastInline or leftRgn2._control, "LEFT", -9, 0)
            btn:SetFrameLevel(leftRgn2:GetFrameLevel() + 5)
            btn:SetAlpha(0.4)
            local tex = btn:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints(); tex:SetTexture(COGS_ICON)
            btn:SetScript("OnEnter", function(self)
                if antsOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "This option requires Pixel Glow to be the selected glow type")
                else self:SetAlpha(0.7) end
            end)
            btn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                if pgPopupOwner ~= btn then self:SetAlpha(antsOff() and 0.15 or 0.4) end
            end)
            btn:SetScript("OnClick", function(self)
                if antsOff() then return end
                ShowPixelGlowPopup(self)
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                if pgPopupOwner ~= btn then btn:SetAlpha(antsOff() and 0.15 or 0.4) end
            end)
        end

        -- ─── Dispellable Buff Glow ────────────────────────────────────────
        local function dispelGlowOff()
            return DBVal("dispelGlow") ~= true
        end

        -- Shared graying for the inline swatch/eye. 12.1: Show All Enemy
        -- Buffs suppresses the glow entirely (the row is no longer
        -- dispellable-only), locking the style/color controls. 12.0 keeps
        -- the legacy conditions: the swatch also grays while Use Dispel
        -- Type Color is on (checkTypeColor); the eye button never did.
        local function dispelGlowLocked(checkTypeColor)
            if dispelGlowOff() then return true end
            if EllesmereUI.IS_121 then
                return DBVal("showAllEnemyBuffs") == true
            end
            if checkTypeColor and DBVal("dispelGlowUseTypeColor") == true then
                return true
            end
            return false
        end

        local dispelGlowStyleValues = { [0] = "None" }
        local dispelGlowStyleOrder = { 0 }
        for i, entry in ipairs(ns.PANDEMIC_GLOW_STYLES) do
            dispelGlowStyleValues[i] = entry.name
            dispelGlowStyleOrder[#dispelGlowStyleOrder + 1] = i
        end

        -- Build-both-select-one: the dropdown table is shared; the right
        -- slot differs per client (12.1 replaces Use Dispel Type Color --
        -- per-aura type is unreadable there -- with Show All Enemy Buffs).
        local dispelGlowDropdown = {
            type="dropdown", text="Dispel Glow Style",
            values=dispelGlowStyleValues,
            getValue=function()
                if dispelGlowOff() then return 0 end
                local raw = ns.GetDispelGlowStyle and ns.GetDispelGlowStyle() or (DBVal("dispelGlowStyle") or 2)
                if type(raw) ~= "number" then return 2 end
                if raw < 1 or raw > #ns.PANDEMIC_GLOW_STYLES then return 2 end
                return raw
            end,
            setValue=function(v)
                local function applyStyle()
                    if v == 0 then
                        DB().dispelGlow = false
                    else
                        DB().dispelGlow = true
                        DB().dispelGlowStyle = v
                    end
                    RefreshAllAuras()
                    UpdatePreview()
                    C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
                end
                -- 12.1: off->on pays the per-plate aura-watcher cost --
                -- prompt like the suite's other performance-priced enables.
                -- Style switches while already enabled never prompt.
                if EllesmereUI.IS_121 and v ~= 0 and DBVal("dispelGlow") ~= true then
                    EllesmereUI:ShowConfirmPopup({
                        title       = "Dispel Glow",
                        message     = "Dispel Glow may cause a slight loss in performance efficiency. Do you want to enable it?",
                        confirmText = "Enable",
                        cancelText  = "Cancel",
                        onConfirm   = applyStyle,
                        onCancel    = function()
                            C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
                        end,
                    })
                    return
                end
                applyStyle()
            end,
            order=dispelGlowStyleOrder,
        }
        local dispelRightWidget
        if EllesmereUI.IS_121 then
            -- Disabled fields attach ONLY here: on 12.0 they must be
            -- absent, not false.
            dispelGlowDropdown.disabled = function() return DBVal("showAllEnemyBuffs") == true end
            dispelGlowDropdown.disabledTooltip = "Disable Show All Enemy Buffs"
            dispelRightWidget = { type="toggle", text="Show All Enemy Buffs",
              getValue=function() return DBVal("showAllEnemyBuffs") or false end,
              setValue=function(v)
                DB().showAllEnemyBuffs = v
                -- Applies live: RefreshAllAuras drives the container reload,
                -- whose cfg pass replaces the buff group's candidate filters
                -- and whose style/purge passes re-evaluate the dispel glow.
                RefreshAllAuras()
                UpdatePreview()
                C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
              end }
        else
            dispelRightWidget = { type="toggle", text="Use Dispel Type Color",
              getValue=function() return DBVal("dispelGlowUseTypeColor") or false end,
              setValue=function(v)
                DB().dispelGlowUseTypeColor = v
                RefreshAllAuras()
                UpdatePreview()
                C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
              end }
        end
        local dispelGlowRow
        dispelGlowRow, h = W:DualRow(parent, y, dispelGlowDropdown, dispelRightWidget);  y = y - h

        -- Inline color swatch for dispel glow
        do
            local glowColorGet = function()
                local c = DB().dispelGlowColor or defaults.dispelGlowColor
                return c.r, c.g, c.b
            end
            local glowColorSet = function(r, g, b)
                DB().dispelGlowColor = { r = r, g = g, b = b }
                RefreshAllAuras()
                UpdatePreview()
            end
            local leftRgn = dispelGlowRow._leftRegion
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, glowColorGet, glowColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = swatch
            -- Gray out swatch when dispel glow is off or suppressed
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = dispelGlowLocked(true)
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            local initialOff = dispelGlowLocked(true)
            swatch:SetAlpha(initialOff and 0.15 or 1)
            swatch:EnableMouse(not initialOff)
        end

        -- Eye icon: show/hide dispel glow on preview buff icons
        do
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
            local leftRgn = dispelGlowRow._leftRegion
            local eyeBtn = CreateFrame("Button", nil, leftRgn)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            eyeBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            eyeBtn:SetAlpha(0.4)
            leftRgn._lastInline = eyeBtn
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function RefreshEyeIcon()
                eyeTex:SetTexture(showDispelGlowPreview and EYE_INVISIBLE or EYE_VISIBLE)
            end
            RefreshEyeIcon()
            eyeBtn:SetScript("OnClick", function()
                showDispelGlowPreview = not showDispelGlowPreview
                RefreshEyeIcon()
                UpdatePreview()
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, "Show/Hide on Preview", { width = 155 })
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                self:SetAlpha(0.4)
                EllesmereUI.HideWidgetTooltip()
            end)
            -- Gray out when dispel glow is off or suppressed
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = dispelGlowLocked(false)
                eyeBtn:SetAlpha(off and 0.15 or 0.4)
                eyeBtn:EnableMouse(not off)
            end)
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  TARGET AND FOCUS EFFECTS
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "TARGET AND FOCUS EFFECTS", y);  y = y - h

        local function hashLineOff() return not (DBVal("hashLineEnabled")) end

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Hash Line on Target at Percent",
              getValue=function() return DBVal("hashLineEnabled") or false end,
              setValue=function(v)
                DB().hashLineEnabled = v
                RefreshAllPlates()
                UpdatePreview()
                EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Hash Line Location",
              min=0, max=100, step=1,
              disabled=hashLineOff, disabledTooltip="Show Hash Line on Target at Percent",
              getValue=function() return DBVal("hashLinePercent") or defaults.hashLinePercent end,
              setValue=function(v)
                DB().hashLinePercent = v
                RefreshAllPlates()
                UpdatePreview()
              end });  y = y - h

        -- Add "(Percent)" suffix in smaller, dimmer text next to the slider label
        do
            local rightFrame = row._rightRegion
            if rightFrame then
                local suffixFS = rightFrame:CreateFontString(nil, "OVERLAY")
                suffixFS:SetFont(EllesmereUI.EXPRESSWAY, 11, GetNPOptOutline())
                suffixFS:SetTextColor(1, 1, 1, 0.35)
                local sliderLabel
                for i = 1, rightFrame:GetNumRegions() do
                    local reg = select(i, rightFrame:GetRegions())
                    if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Hash Line Location" then
                        sliderLabel = reg
                        break
                    end
                end
                if sliderLabel then
                    suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
                else
                    suffixFS:SetPoint("LEFT", rightFrame, "LEFT", 180, -1)
                end
                suffixFS:SetText(EllesmereUI.L("(Percent)"))
                -- Gray out suffix when hash line is off
                EllesmereUI.RegisterWidgetRefresh(function()
                    suffixFS:SetAlpha(hashLineOff() and 0.10 or 0.35)
                end)
                suffixFS:SetAlpha(hashLineOff() and 0.10 or 0.35)
            end
        end

        -- Inline color swatch for hash line custom color
        do
            local hashColorGet = function()
                local c = (DB() and DB().hashLineColor) or defaults.hashLineColor
                return c.r, c.g, c.b
            end
            local hashColorSet = function(r, g, b)
                DB().hashLineColor = { r = r, g = g, b = b }
                RefreshAllPlates()
                UpdatePreview()
            end
            local leftRgn = row._leftRegion
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, hashColorGet, hashColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            -- Gray out swatch when hash line is off
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = hashLineOff()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            swatch:SetAlpha(hashLineOff() and 0.15 or 1)
            swatch:EnableMouse(not hashLineOff())
        end

        -- Row 2: Scale Target Nameplate | Non-Target Opacity
        local tfScaleRow
        tfScaleRow, h = W:DualRow(parent, y,
            { type="slider", text="Scale Target Nameplate",
              trackWidth=110,
              min=50, max=200, step=5,
              getValue=function() return DBVal("targetScale") or defaults.targetScale end,
              setValue=function(v)
                DB().targetScale = v
                for _, plate in pairs(plates) do
                    plate:ApplyScale()
                end
              end,
              tooltip="Scales your current target's nameplate. 100% = no change." },
            { type="slider", text="Non-Target Opacity",
              tooltip="Fades enemy nameplates that are not your current target or focus while you have a target. 100 = no fading.",
              min=0, max=100, step=1,
              getValue=function() return DBVal("nonTargetAlpha") or 100 end,
              setValue=function(v)
                DB().nonTargetAlpha = v
                if ns.NT_RefreshSetting then ns.NT_RefreshSetting() end
                EllesmereUI:RefreshPage()  -- update the cog disabled state
              end });  y = y - h
        -- "(Percent)" suffix on the target scale slider
        do
            local leftFrame = tfScaleRow._leftRegion
            if leftFrame then
                local suffixFS = leftFrame:CreateFontString(nil, "OVERLAY")
                suffixFS:SetFont(EllesmereUI.EXPRESSWAY, 11, GetNPOptOutline())
                suffixFS:SetTextColor(1, 1, 1, 0.35)
                local sliderLabel
                for i = 1, leftFrame:GetNumRegions() do
                    local reg = select(i, leftFrame:GetRegions())
                    if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Scale Target Nameplate" then
                        sliderLabel = reg
                        break
                    end
                end
                if sliderLabel then
                    suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
                else
                    suffixFS:SetPoint("LEFT", leftFrame, "LEFT", 180, -1)
                end
                suffixFS:SetText(EllesmereUI.L("(Percent)"))
            end
        end
        -- Inline cog on Non-Target Opacity: focus exclusion toggle.
        do
            local function ntOff() return (DBVal("nonTargetAlpha") or 100) >= 100 end
            local rgn = tfScaleRow._rightRegion
            local _, ntCogShow = EllesmereUI.BuildCogPopup({
                title = "Non-Target Opacity",
                rows = {
                    { type="toggle", label="Keep Focus Full Opacity",
                      tooltip="Your focus target's nameplate never fades with the non-target opacity.",
                      get=function() return DBVal("nonTargetKeepFocus") ~= false end,
                      set=function(v)
                        DB().nonTargetKeepFocus = v
                        if ns.NT_RefreshSetting then ns.NT_RefreshSetting() end
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            local function UpdateNtCogAlpha()
                cogBtn:SetAlpha(ntOff() and 0.15 or 0.4)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateNtCogAlpha)
            UpdateNtCogAlpha()
            cogBtn:SetScript("OnClick", function(self)
                if not ntOff() then ntCogShow(self) end
            end)
            cogBtn:SetScript("OnEnter", function(self)
                if not ntOff() then self:SetAlpha(0.75) end
            end)
            cogBtn:SetScript("OnLeave", function() UpdateNtCogAlpha() end)
        end

        -- Row 3: Focus Cast Height | Focus Letter
        local focusLetterOff = function()
            return DBVal("focusLetterEnabled") ~= true
        end
        local tfFocusRow
        tfFocusRow, h = W:DualRow(parent, y,
            { type="slider", text="Focus Cast Height",
              trackWidth=110,
              min=100, max=200, step=5,
              getValue=function() return DBVal("focusCastHeight") or defaults.focusCastHeight end,
              setValue=function(v)
                DB().focusCastHeight = v
                ns.RefreshAllSettings()
              end,
              tooltip="Increases the cast bar height on your focus target's nameplate. 100% = normal height." },
            { type="toggle", text="Focus Letter",
              tooltip="Draws a white letter F on your current focus target's nameplate.",
              getValue=function() return DBVal("focusLetterEnabled") == true end,
              setValue=function(v)
                DB().focusLetterEnabled = v
                RefreshAllPlates()
                EllesmereUI:RefreshPage()
              end });  y = y - h
        -- "(Percent)" suffix on Focus Cast Height
        do
            local leftFrame = tfFocusRow._leftRegion
            if leftFrame then
                local suffixFS = leftFrame:CreateFontString(nil, "OVERLAY")
                suffixFS:SetFont(EllesmereUI.EXPRESSWAY, 11, GetNPOptOutline())
                suffixFS:SetTextColor(1, 1, 1, 0.35)
                local sliderLabel
                for i = 1, leftFrame:GetNumRegions() do
                    local reg = select(i, leftFrame:GetRegions())
                    if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Focus Cast Height" then
                        sliderLabel = reg
                        break
                    end
                end
                if sliderLabel then
                    suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
                else
                    suffixFS:SetPoint("LEFT", leftFrame, "LEFT", 180, -1)
                end
                suffixFS:SetText(EllesmereUI.L("(Percent)"))
            end
        end

        do
            local rgn = tfFocusRow._rightRegion
            local _, focusLetterCogShow = EllesmereUI.BuildCogPopup({
                title = "Focus Letter",
                rows = {
                    { type="dropdown", label="Anchor",
                      values=FOCUS_LETTER_ANCHORS,
                      order=FOCUS_LETTER_ANCHOR_ORDER,
                      get=GetFocusLetterAnchor,
                      set=function(v)
                        DB().focusLetterAnchor = v
                        RefreshAllPlates()
                      end },
                    { type="slider", label="Size", min=6, max=40, step=1,
                      get=function() return DBVal("focusLetterSize") or defaults.focusLetterSize end,
                      set=function(v)
                        DB().focusLetterSize = v
                        RefreshAllPlates()
                      end },
                    { type="slider", label="X", min=-100, max=100, step=1,
                      get=function() return DBVal("focusLetterX") or defaults.focusLetterX end,
                      set=function(v)
                        DB().focusLetterX = v
                        RefreshAllPlates()
                      end },
                    { type="slider", label="Y", min=-100, max=100, step=1,
                      get=function() return DBVal("focusLetterY") or defaults.focusLetterY end,
                      set=function(v)
                        DB().focusLetterY = v
                        RefreshAllPlates()
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            if cogTex.SetSnapToPixelGrid then cogTex:SetSnapToPixelGrid(false); cogTex:SetTexelSnappingBias(0) end
            local function UpdateCogAlpha()
                cogBtn:SetAlpha(focusLetterOff() and 0.15 or 0.4)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogAlpha)
            UpdateCogAlpha()
            cogBtn:SetScript("OnClick", function(self)
                if not focusLetterOff() then focusLetterCogShow(self) end
            end)
            cogBtn:SetScript("OnEnter", function(self)
                if not focusLetterOff() then self:SetAlpha(0.75) end
            end)
            cogBtn:SetScript("OnLeave", function(self) UpdateCogAlpha() end)
        end

        -- Row 4: Distance to Target Text: range bucket ("15+") on the target's
        -- nameplate (see the runtime block at the end of the main file).
        local tfRangeOff = function() return DBVal("rangeTextEnabled") ~= true end
        local tfRangeRow
        tfRangeRow, h = W:DualRow(parent, y,
            { type="toggle", text="Distance to Target Text",
              tooltip="Shows the approximate distance to your current target on its nameplate as a range bracket, e.g. 15+ when the target is 15-20 yards away.",
              getValue=function() return DBVal("rangeTextEnabled") == true end,
              setValue=function(v)
                DB().rangeTextEnabled = v
                if ns.RangeText_Apply then ns.RangeText_Apply() end
                EllesmereUI:RefreshPage()
              end },
            { type="label", text="" }
        );  y = y - h
        -- RESIZE cog: text size + X/Y offsets (mirrors the raid-marker cog)
        do
            local rgn = tfRangeRow._leftRegion
            local _, rangeCogShow = EllesmereUI.BuildCogPopup({
                title = "Distance Text",
                rows = {
                    { type="slider", label="Text Size", min=6, max=32, step=1,
                      get=function() return DBVal("rangeTextSize") or defaults.rangeTextSize end,
                      set=function(v)
                        DB().rangeTextSize = v
                        if ns.RangeText_Refresh then ns.RangeText_Refresh() end
                      end },
                    { type="slider", label="Offset X", min=-200, max=200, step=1,
                      get=function() return DBVal("rangeTextOffsetX") or 0 end,
                      set=function(v)
                        DB().rangeTextOffsetX = v
                        if ns.RangeText_Refresh then ns.RangeText_Refresh() end
                      end },
                    { type="slider", label="Offset Y", min=-200, max=200, step=1,
                      get=function() return DBVal("rangeTextOffsetY") or 0 end,
                      set=function(v)
                        DB().rangeTextOffsetY = v
                        if ns.RangeText_Refresh then ns.RangeText_Refresh() end
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            if cogTex.SetSnapToPixelGrid then cogTex:SetSnapToPixelGrid(false); cogTex:SetTexelSnappingBias(0) end
            local function UpdateRangeCogAlpha()
                cogBtn:SetAlpha(tfRangeOff() and 0.15 or 0.4)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateRangeCogAlpha)
            UpdateRangeCogAlpha()
            cogBtn:SetScript("OnClick", function(self)
                if not tfRangeOff() then rangeCogShow(self) end
            end)
            cogBtn:SetScript("OnEnter", function(self)
                if not tfRangeOff() then self:SetAlpha(0.75) end
            end)
            cogBtn:SetScript("OnLeave", function() UpdateRangeCogAlpha() end)
        end
        -- Inline color swatch (default light orange), left of the cog
        do
            local rgn = tfRangeRow._leftRegion
            local rangeColorGet = function()
                local c = (DB() and DB().rangeTextColor) or defaults.rangeTextColor
                return c.r, c.g, c.b
            end
            local rangeColorSet = function(r, g, b)
                DB().rangeTextColor = { r = r, g = g, b = b }
                if ns.RangeText_Refresh then ns.RangeText_Refresh() end
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, rangeColorGet, rangeColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = tfRangeOff()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            swatch:SetAlpha(tfRangeOff() and 0.15 or 1)
            swatch:EnableMouse(not tfRangeOff())
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  EXTRAS
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_MISC, y);  y = y - h

        -- Row 1: Scale Nameplate on Cast | Hide Enemy Name While Casting
        local exCastRow
        exCastRow, h = W:DualRow(parent, y,
            { type="slider", text="Scale Nameplate On Cast",
              trackWidth=110,
              min=50, max=200, step=5,
              getValue=function() return DBVal("castScale") or defaults.castScale end,
              setValue=function(v)
                DB().castScale = v
              end,
              tooltip="Scales enemy nameplates while they are casting. 100% = no change." },
            { type="toggle", text="Hide Enemy Name While Casting",
              tooltip="Hide the enemy name text while that nameplate's cast bar is visible.",
              getValue=function() return DBVal("hideEnemyNameWhileCasting") == true end,
              setValue=function(v)
                DB().hideEnemyNameWhileCasting = v
                ns.RefreshAllSettings()
                UpdatePreview()
              end });  y = y - h
        -- "(Percent)" suffix on the cast scale slider
        do
            local leftFrame = exCastRow._leftRegion
            if leftFrame then
                local suffixFS = leftFrame:CreateFontString(nil, "OVERLAY")
                suffixFS:SetFont(EllesmereUI.EXPRESSWAY, 11, GetNPOptOutline())
                suffixFS:SetTextColor(1, 1, 1, 0.35)
                local sliderLabel
                for i = 1, leftFrame:GetNumRegions() do
                    local reg = select(i, leftFrame:GetRegions())
                    if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Scale Nameplate On Cast" then
                        sliderLabel = reg
                        break
                    end
                end
                if sliderLabel then
                    suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
                else
                    suffixFS:SetPoint("LEFT", leftFrame, "LEFT", 180, -1)
                end
                suffixFS:SetText(EllesmereUI.L("(Percent)"))
            end
        end

        -- Row 2: Name Raid Marker | Experimental: Cast Lockout as CC Icon.
        -- Name Raid Marker: the target raid marker shown directly before the
        -- enemy name. Size lives on the inline cog.
        local nameRaidMarkerRow
        nameRaidMarkerRow, h = W:DualRow(parent, y,
            { type="toggle", text="Name Raid Marker",
              tooltip="Shows the target marker directly before the enemy name text. Uses its own size and does not use the Core Positions raid marker slot.",
              getValue=function() return DBVal("nameRaidMarkerEnabled") == true end,
              setValue=function(v)
                DB().nameRaidMarkerEnabled = v
                ns.RefreshAllSettings()
                UpdatePreview()
                EllesmereUI:RefreshPage()
              end },
            { type = "toggle", text = "Experimental: Cast Lockout as CC Icon",
              tooltip = "Show successful interrupt lockouts in the crowd-control icon slot.\n\nDue to addon restrictions, the duration shown is a generic 4 seconds for all classes, so it is not 100% accurate.",
              getValue = function() return DBVal("showCastLockoutAsCrowdControl") == true end,
              setValue = function(v)
                  DB().showCastLockoutAsCrowdControl = v
                  RefreshAllAuras()
              end });  y = y - h

        do
            local function nameRaidMarkerOff() return DBVal("nameRaidMarkerEnabled") ~= true end
            local rgn = nameRaidMarkerRow._leftRegion
            local _, nameRaidMarkerCogShow = EllesmereUI.BuildCogPopup({
                title = "Name Raid Marker",
                rows = {
                    { type="slider", label="Size", min=6, max=32, step=1,
                      get=function() return DBVal("nameRaidMarkerSize") or defaults.nameRaidMarkerSize end,
                      set=function(v)
                        DB().nameRaidMarkerSize = v
                        ns.RefreshAllSettings()
                        UpdatePreview()
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            if cogTex.SetSnapToPixelGrid then cogTex:SetSnapToPixelGrid(false); cogTex:SetTexelSnappingBias(0) end
            local function UpdateCogAlpha()
                cogBtn:SetAlpha(nameRaidMarkerOff() and 0.15 or 0.4)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogAlpha)
            UpdateCogAlpha()
            cogBtn:SetScript("OnClick", function(self)
                if not nameRaidMarkerOff() then nameRaidMarkerCogShow(self) end
            end)
            cogBtn:SetScript("OnEnter", function(self)
                if not nameRaidMarkerOff() then self:SetAlpha(0.75) end
            end)
            cogBtn:SetScript("OnLeave", function() UpdateCogAlpha() end)
        end

        -- Row 3: Replace Quest Icon with Objective | Line of Sight Opacity
        local questObjRow
        questObjRow, h = W:DualRow(parent, y,
            { type="toggle", text="Replace Quest Icon with Objective",
              getValue=function() return DBVal("replaceQuestIconWithObjective") == true end,
              setValue=function(v)
                DB().replaceQuestIconWithObjective = v
                if ns.RefreshQuestObjective then ns.RefreshQuestObjective() end
                EllesmereUI:RefreshPage()
              end,
              tooltip="On quest mobs in the open world, replaces the quest icon with the objective progress (ex: kill quests show 0/6, percentage objectives show 50%)." },
            -- Line of Sight Opacity: a pure CVar passthrough (like the Lag
            -- Tolerance slider). Nothing is stored in our DB -- getValue reflects
            -- the live nameplateOccludedAlphaMult CVar and setValue only writes it
            -- when the user moves the slider. Combat-guarded write, mirroring
            -- SetCVarSafe in the global options.
            { type="slider", text="Line of Sight Opacity",
              tooltip="Nameplates opacity for units that are out of line of sight. 0 = fully transparent, 1 = fully opaque.",
              min=0, max=1, step=0.01,
              getValue=function() return tonumber(GetCVar("nameplateOccludedAlphaMult")) or 0 end,
              setValue=function(v)
                if InCombatLockdown() then return end
                SetCVar("nameplateOccludedAlphaMult", v)
              end });  y = y - h

        -- Inline cog on the quest toggle: objective text size
        do
            local function questObjOff() return DBVal("replaceQuestIconWithObjective") ~= true end
            local rgn = questObjRow._leftRegion
            local _, sizeCogShow = EllesmereUI.BuildCogPopup({
                title = "Quest Objective",
                rows = {
                    { type = "slider", label = "Text Size", min = 6, max = 24, step = 1,
                      get = function() return DBVal("questObjectiveTextSize") or defaults.questObjectiveTextSize end,
                      set = function(v)
                        DB().questObjectiveTextSize = v
                        if ns.RefreshQuestObjective then ns.RefreshQuestObjective() end
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            if cogTex.SetSnapToPixelGrid then cogTex:SetSnapToPixelGrid(false); cogTex:SetTexelSnappingBias(0) end
            cogBtn:SetScript("OnEnter", function(self) if not questObjOff() then self:SetAlpha(0.7) end end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(questObjOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self)
                if questObjOff() then return end
                sizeCogShow(self)
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                cogBtn:SetAlpha(questObjOff() and 0.15 or 0.4)
            end)
            cogBtn:SetAlpha(questObjOff() and 0.15 or 0.4)
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Display page  (preview in content header + settings in scroll area)
    ---------------------------------------------------------------------------
    local LazyColorPreviewBar -- forward declaration; defined after MakeColorPreviewBar

    local function BuildDisplayPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        local function isBorderNone()
            local v = DBVal("showBorder")
            if v == nil then return not defaults.showBorder end
            return not v
        end

        -- Set content header with preview centered above nameplate preview
        _displayHeaderBuilder = function(headerParent, headerW)

            local PRESET_HEADER_H = 0
            local PREVIEW_TOP_PAD = 10
            local PREVIEW_BOTTOM_PAD = 5
            local previewH = BuildNameplatePreview(headerParent, headerW)
            -- Position the preview at the top of the header area.
            -- pf has SetScale matching the UIParent/panel ratio; SetPoint
            -- offsets are in the child's scaled coordinate space, so divide
            -- by the same ratio to get the correct visual offset.
            if activePreview then
                activePreview:ClearAllPoints()
                local correction = UIParent:GetEffectiveScale() / headerParent:GetEffectiveScale()
                activePreview:SetPoint("TOP", headerParent, "TOP", 0, -(PRESET_HEADER_H + PREVIEW_TOP_PAD) / correction)
                activePreview._headerExtra = PRESET_HEADER_H + PREVIEW_TOP_PAD + PREVIEW_BOTTOM_PAD
            end

            -- "Click elements" hint below the preview
            -- Parent to activePreview (a child Frame) so the FontString
            -- travels with it through the content-header cache system.
            -- Parenting to headerParent directly caused the hint to be
            -- orphaned by ClearContentHeaderInner when switching pages.
            -- If the old hint was orphaned (parent gone), nil it so we recreate.
            if _previewHintFS and not _previewHintFS:GetParent() then
                _previewHintFS = nil
            end
            local hintShown = not IsPreviewHintDismissed()
            if hintShown then
                if not _previewHintFS then
                    _previewHintFS = EllesmereUI.MakeFont(activePreview or headerParent, 11, nil, 1, 1, 1)
                    _previewHintFS:SetAlpha(0.45)
                    _previewHintFS:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
                end
                _previewHintFS:SetParent(activePreview or headerParent)
                _previewHintFS:ClearAllPoints()
                _previewHintFS:SetPoint("BOTTOM", headerParent, "BOTTOM", 0, 17)
                _previewHintFS:SetAlpha(0.45)
                _previewHintFS:Show()
            elseif _previewHintFS then
                _previewHintFS:Hide()
            end

            _headerBaseH = previewH + PRESET_HEADER_H + PREVIEW_TOP_PAD + PREVIEW_BOTTOM_PAD
            return _headerBaseH + (hintShown and 29 or 0)
        end
        EllesmereUI:SetContentHeader(_displayHeaderBuilder)

        -- Enable per-row center divider for the dual-column layout
        parent._showRowDivider = true

        -----------------------------------------------------------------------
        --  AURA POSITIONS
        -----------------------------------------------------------------------
        local slotKeys = { "debuffSlot", "buffSlot", "ccSlot", "raidMarkerPos", "classificationSlot" }

        -- Inverted mapping: position element (for CORE POSITIONS dropdowns)
        local elementToKey = {
            debuffs        = "debuffSlot",
            buffs          = "buffSlot",
            ccs            = "ccSlot",
            raidmarker     = "raidMarkerPos",
            classification = "classificationSlot",
        }
        local keyToElement = {}
        for elem, key in pairs(elementToKey) do keyToElement[key] = elem end

        local function GetElementAtPosition(pos)
            local db = DB()
            for _, key in ipairs(slotKeys) do
                if (db[key] or defaults[key]) == pos then
                    -- "Debuffs + CC" is a VIEW over the debuff slot: same
                    -- position key, plus the debuffIncludeCC flag.
                    if key == "debuffSlot" and db.debuffIncludeCC then
                        return "debuffsccs"
                    end
                    return keyToElement[key]
                end
            end
            return "none"
        end

        local function SetElementAtPosition(pos, element)
            if element == "none" then
                -- Clear: find whatever element is at this position and move it to "none"
                local db = DB()
                for _, key in ipairs(slotKeys) do
                    if (db[key] or defaults[key]) == pos then
                        db[key] = "none"
                    end
                end
                return
            end
            -- "Debuffs + CC" rides the debuff slot key; the two dropdown
            -- entries only differ by the debuffIncludeCC flag.
            if element == "debuffsccs" then
                DB().debuffIncludeCC = true
                element = "debuffs"
            elseif element == "debuffs" then
                DB().debuffIncludeCC = false
            end
            local key = elementToKey[element]
            if not key then return end
            local db = DB()
            -- Clear old holder of this position (set to "none"), no swapping
            for _, otherKey in ipairs(slotKeys) do
                if otherKey ~= key and (db[otherKey] or defaults[otherKey]) == pos then
                    db[otherKey] = "none"
                end
            end
            db[key] = pos
        end

        local slotValues = {
            ["top"]      = "Top",
            ["left"]     = "Left",
            ["right"]    = "Right",
            ["topleft"]  = "Top Left",
            ["topright"] = "Top Right",
            ["bottom"]   = "Bottom",
            ["none"]     = "None",
        }
        local slotOrder = { "top", "left", "right", "topleft", "topright", "bottom", "none" }
        local function RefreshAllSlots()
            RefreshAllAuras()
            for _, plate in pairs(plates) do
                local ds, bs, cs = ns.GetAuraSlots()
                if bs ~= "none" then
                    local buffSz = ns.GetBuffIconSize()
                    local buffH = ns.GetAuraCropHeight(ns.GetAuraCrop("buffs"), buffSz)
                    local bxOff, byOff = ns.GetSlotOffsets(bs)
                    ns.PositionAuraSlot(plate.buffs, 4, bs, plate, buffSz, buffH, ns.GetAuraSpacing("buffs"), bxOff, byOff)
                else
                    for i = 1, 4 do plate.buffs[i]:Hide() end
                end
                if cs ~= "none" then
                    local ccSz = ns.GetCCIconSize()
                    local ccH = ns.GetAuraCropHeight(ns.GetAuraCrop("ccs"), ccSz)
                    local cxOff, cyOff = ns.GetSlotOffsets(cs)
                    ns.PositionAuraSlot(plate.cc, 2, cs, plate, ccSz, ccH, ns.GetAuraSpacing("ccs"), cxOff, cyOff)
                else
                    for i = 1, 2 do plate.cc[i]:Hide() end
                end
                if ds == "none" then
                    for i = 1, 4 do plate.debuffs[i]:Hide() end
                end
                plate:UpdateRaidIcon()
                plate:UpdateClassification()
                if ns.ApplySlotStrata then ns.ApplySlotStrata(plate) end
            end
            UpdatePreview()
            EllesmereUI:RefreshPage()
        end

        -----------------------------------------------------------------------
        --  Helpers for position-swapping dropdowns
        -----------------------------------------------------------------------

        -- Exclusive slot assignment for the new Core Text Positions system.
        local textSlotKeys = ns.textSlotKeys
        local function SetTextElementAtSlot(slotKey, element)
            local db = DB()
            if element ~= "none" then
                for _, key in ipairs(textSlotKeys) do
                    if key ~= slotKey and (db[key] or defaults[key]) == element then
                        db[key] = "none"
                    end
                end
            end
            db[slotKey] = element
        end

        local timerPosValues = {
            ["topleft"]  = "Top Left",
            ["center"]   = "Center",
            ["topright"]  = "Top Right",
            ["bottomleft"]  = "Bottom Left",
            ["bottomright"] = "Bottom Right",
            ["none"]      = "None",
        }
        local timerPosOrder = { "none", "topleft", "topright", "bottomleft", "bottomright", "center" }

        local function AuraDurationVal(kind, suffix)
            local db = DB()
            local key = kind .. "DurationText" .. suffix
            local oldKey = "auraDurationText" .. suffix
            if db and db[key] ~= nil then return db[key] end
            if db and db[oldKey] ~= nil then return db[oldKey] end
            return defaults[oldKey]
        end

        -- Shared helper: apply a timer position to live plates for one aura type
        local function LiveApplyTimerPos(auraFrames, count, v, kind)
            local durC = AuraDurationVal(kind, "Color")
            local durSz = AuraDurationVal(kind, "Size")
            local durX = AuraDurationVal(kind, "X")
            local durY = AuraDurationVal(kind, "Y")
            for _, plate in pairs(plates) do
                for i = 1, count do
                    local af = auraFrames(plate, i)
                    if af and af.cd then
                        if v == "none" then
                            if af.cd.SetHideCountdownNumbers then
                                af.cd:SetHideCountdownNumbers(true)
                            end
                        else
                            if af.cd.SetHideCountdownNumbers then
                                af.cd:SetHideCountdownNumbers(false)
                            end
                            if af.cd.text then
                                SetFSFont(af.cd.text, durSz, "OUTLINE, SLUG")
                                af.cd.text:SetTextColor(durC.r, durC.g, durC.b, 1)
                                af.cd.text:ClearAllPoints()
                                if v == "center" then
                                    af.cd.text:SetPoint("CENTER", af, "CENTER", durX, durY)
                                    af.cd.text:SetJustifyH("CENTER")
                                elseif v == "topright" then
                                    PP.Point(af.cd.text, "TOPRIGHT", af, "TOPRIGHT", 3 + durX, 4 + durY)
                                    af.cd.text:SetJustifyH("RIGHT")
                                elseif v == "bottomleft" then
                                    PP.Point(af.cd.text, "BOTTOMLEFT", af, "BOTTOMLEFT", -3 + durX, -4 + durY)
                                    af.cd.text:SetJustifyH("LEFT")
                                elseif v == "bottomright" then
                                    PP.Point(af.cd.text, "BOTTOMRIGHT", af, "BOTTOMRIGHT", 3 + durX, -4 + durY)
                                    af.cd.text:SetJustifyH("RIGHT")
                                else
                                    PP.Point(af.cd.text, "TOPLEFT", af, "TOPLEFT", -3 + durX, 4 + durY)
                                    af.cd.text:SetJustifyH("LEFT")
                                end
                            end
                        end
                    end
                end
            end
            -- 12.1 aura containers render the text through the style pass
            -- instead of the legacy frames above (fingerprint-guarded; nil
            -- on 12.0).
            if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
        end

        -- Shared helper: apply a stack-count position to live plates for one aura type
        local function LiveApplyStackPos(auraFrames, count, v)
            local stkC = (DB() and DB().auraStackTextColor) or defaults.auraStackTextColor
            local stkSz = DBVal("auraStackTextSize") or defaults.auraStackTextSize
            local stkX = DBVal("auraStackTextX") or defaults.auraStackTextX
            local stkY = DBVal("auraStackTextY") or defaults.auraStackTextY
            for _, plate in pairs(plates) do
                for i = 1, count do
                    local af = auraFrames(plate, i)
                    if af and af.count then
                        if v == "none" then
                            af.count:Hide()
                        else
                            af.count:Show()
                            SetFSFont(af.count, stkSz, "OUTLINE, SLUG")
                            af.count:SetTextColor(stkC.r, stkC.g, stkC.b, 1)
                            af.count:ClearAllPoints()
                            if v == "center" then
                                af.count:SetPoint("CENTER", af, "CENTER", stkX, stkY)
                                af.count:SetJustifyH("CENTER")
                            elseif v == "topright" then
                                PP.Point(af.count, "TOPRIGHT", af, "TOPRIGHT", 3 + stkX, 4 + stkY)
                                af.count:SetJustifyH("RIGHT")
                            elseif v == "bottomleft" then
                                PP.Point(af.count, "BOTTOMLEFT", af, "BOTTOMLEFT", -3 + stkX, -4 + stkY)
                                af.count:SetJustifyH("LEFT")
                            elseif v == "topleft" then
                                PP.Point(af.count, "TOPLEFT", af, "TOPLEFT", -3 + stkX, 4 + stkY)
                                af.count:SetJustifyH("LEFT")
                            else
                                PP.Point(af.count, "BOTTOMRIGHT", af, "BOTTOMRIGHT", 3 + stkX, -4 + stkY)
                                af.count:SetJustifyH("RIGHT")
                            end
                        end
                    end
                end
            end
            -- 12.1 aura containers: stacks render through the style pass
            -- (fingerprint-guarded; nil on 12.0).
            if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
        end

        local atFallback = DBVal("auraTextPosition") or defaults.auraTextPosition
        local asFallback = DBVal("auraStackTextPosition") or defaults.auraStackTextPosition

        -----------------------------------------------------------------------
        --  STYLE
        -----------------------------------------------------------------------
        local styleHeader
        styleHeader, h = W:SectionHeader(parent, "STYLE", y);  y = y - h

        local function RefreshAllTextures()
            ns.RefreshAllSettings()
            for _, plate in pairs(ns.friendlyPlates or {}) do
                if ns.ApplyHealthBarTexture then ns.ApplyHealthBarTexture(plate) end
                if ns.ApplyCastBarTexture then ns.ApplyCastBarTexture(plate) end
            end
        end

        -- Row 1: Border (None / Basic / Custom) | Border Size
        -- The dropdown is a pure VIEW over the existing showBorder +
        -- customBorderEnabled keys (no migration): None = border off,
        -- Basic = standard border, Custom = the custom border engine. Selecting
        -- Custom reveals the Custom Border row below (the page rebuild reflows
        -- the rows beneath it down); None/Basic collapse it away.
        local borderStyleRow
        borderStyleRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Border",
              values={ none = "None", basic = "Basic", custom = "Custom" },
              order={ "none", "basic", "custom" },
              getValue=function()
                if DBVal("customBorderEnabled") then return "custom" end
                local sb = DBVal("showBorder")
                if sb == nil then sb = defaults.showBorder end
                return sb and "basic" or "none"
              end,
              setValue=function(v)
                if v == "custom" then
                  DB().customBorderEnabled = true
                elseif v == "basic" then
                  DB().customBorderEnabled = false
                  DB().showBorder = true
                else
                  DB().customBorderEnabled = false
                  DB().showBorder = false
                end
                ns.RefreshBorder()
                ns.RefreshBorderColor()
                UpdatePreview()
                -- Force rebuild so the Custom Border row shows/hides and the
                -- rows below reflow.
                EllesmereUI:RefreshPage(true)
              end },
            { type="slider", text="Border Size", min=1, max=4, step=1,
              -- Only the Basic border uses this size (None has no border;
              -- Custom uses its own Custom Border Size below).
              disabled=function()
                if DBVal("customBorderEnabled") then return true end
                local v = DBVal("showBorder")
                if v == nil then return not defaults.showBorder end
                return not v
              end,
              disabledTooltip="This option is only used by the Basic border.",
              rawTooltip=true,
              getValue=function() return DBVal("borderSize") or defaults.borderSize end,
              setValue=function(v)
                DB().borderSize = v
                ns.RefreshBorder()
                UpdatePreview()
              end })
        y = y - h
        -- Inline color swatch next to the Border dropdown (left region) -- the
        -- standard (Basic) border color. Dimmed unless the mode is Basic.
        do
            local leftRgn = borderStyleRow._leftRegion
            local function isBorderOff()
                -- Off for None and Custom (the standard border, and therefore
                -- its color, is inert then) -- only Basic uses it.
                if DBVal("customBorderEnabled") then return true end
                local v = DBVal("showBorder")
                if v == nil then return not defaults.showBorder end
                return not v
            end
            local borderColorGet = function()
                local c = (DB() and DB().borderColor) or defaults.borderColor
                return c.r, c.g, c.b
            end
            local borderColorSet = function(r, g, b)
                DB().borderColor = { r = r, g = g, b = b }
                ns.RefreshBorderColor()
                UpdatePreview()
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, borderColorGet, borderColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = swatch
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isBorderOff()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            local off = isBorderOff()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
        end

        -- Inline cog on the Border region: opt-in "Wrap Around Castbar". Placed
        -- to the left of the colour swatch. Dimmed only for the "None" mode
        -- (the wrap applies to both Basic and Custom borders).
        do
            local leftRgn = borderStyleRow._leftRegion
            local _, wrapCogShow = EllesmereUI.BuildCogPopup({
                title = "Castbar Border",
                rows = {
                    { type="toggle", label="Wrap Around Castbar",
                      get=function()
                        local v = DBVal("wrapBorderCastbar")
                        if v == nil then return defaults.wrapBorderCastbar end
                        return v
                      end,
                      set=function(v)
                        DB().wrapBorderCastbar = v
                        -- Unconditional re-apply so toggling OFF also unwraps any
                        -- plate that is currently mid-cast and wrapped.
                        if ns.ApplyBorderWrapToAll then ns.ApplyBorderWrapToAll() end
                        UpdatePreview()
                      end },
                },
            })
            local wrapCogBtn = CreateFrame("Button", nil, leftRgn)
            wrapCogBtn:SetSize(26, 26)
            wrapCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = wrapCogBtn
            wrapCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            local wrapCogTex = wrapCogBtn:CreateTexture(nil, "OVERLAY")
            wrapCogTex:SetAllPoints(); wrapCogTex:SetTexture(EllesmereUI.COGS_ICON)
            local function wrapCogOff()
                -- Only "None" disables it; Basic and Custom both support the wrap.
                if DBVal("customBorderEnabled") then return false end
                local v = DBVal("showBorder")
                if v == nil then v = defaults.showBorder end
                return not v
            end
            wrapCogBtn:SetScript("OnEnter", function(s) if not wrapCogOff() then s:SetAlpha(0.7) end end)
            wrapCogBtn:SetScript("OnLeave", function(s) if not wrapCogOff() then s:SetAlpha(0.4) end end)
            wrapCogBtn:SetScript("OnClick", function(s) if not wrapCogOff() then wrapCogShow(s) end end)
            local function wrapCogState()
                local off = wrapCogOff()
                wrapCogBtn:SetAlpha(off and 0.15 or 0.4)
                wrapCogBtn:EnableMouse(not off)
            end
            EllesmereUI.RegisterWidgetRefresh(wrapCogState)
            wrapCogState()
        end

        -- Custom Border row -- only built when the Border dropdown above is set
        -- to "Custom". Selecting Custom triggers a page rebuild (in that
        -- dropdown's setValue), which reveals this row and reflows the rows
        -- below it down; choosing None/Basic collapses it away. Uses the shared
        -- EllesmereUI border engine (identical to Unit Frames, full SharedMedia
        -- support). The if-body scopes its locals so they don't grow this
        -- builder's local count.
        if DBVal("customBorderEnabled") then
            -- Custom Border Style dropdown (+ offset cog) | Custom Border Size (+ color swatch)
            local cbTexValues, cbTexOrder = EllesmereUI.GetBorderTextureDropdown()
            local customBorderRow
            customBorderRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Custom Border Style",
                  values=cbTexValues, order=cbTexOrder,
                  getValue=function() return DBVal("customBorderTexture") or defaults.customBorderTexture end,
                  setValue=function(v)
                    DB().customBorderTexture = v
                    DB().customBorderOffset  = nil
                    DB().customBorderOffsetY = nil
                    DB().customBorderShiftX  = nil
                    DB().customBorderShiftY  = nil
                    local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                    DB().customBorderColor  = _bcol
                    DB().customBorderAlpha  = 1
                    DB().customBorderBehind = _bbehind
                    local defSz = EllesmereUI.GetBorderDefaultSize("nameplates", v)
                    if defSz then DB().customBorderSize = defSz end
                    ns.RefreshBorder()
                    UpdatePreview()
                    EllesmereUI:RefreshPage()
                  end },
                { type="slider", text="Custom Border Size", min=0, max=4, step=1,
                  getValue=function() return DBVal("customBorderSize") or defaults.customBorderSize end,
                  setValue=function(v)
                    DB().customBorderSize = v
                    ns.RefreshBorder()
                    UpdatePreview()
                  end })
            y = y - h

            -- Inline "Border Offset" cog on the Custom Border Style region
            do
                local leftRgn = customBorderRow._leftRegion
                local _, cbCogShow = EllesmereUI.BuildCogPopup({
                    title = "Border Offset",
                    rows = {
                        { type="slider", label="Offset X", min=-10, max=10, step=1,
                          get=function()
                            local v = DB() and DB().customBorderOffset
                            if v then return v end
                            local tex = DBVal("customBorderTexture") or defaults.customBorderTexture
                            local sz  = DBVal("customBorderSize") or defaults.customBorderSize
                            local dox = EllesmereUI.GetBorderDefaults("nameplates", tex, sz)
                            return dox
                          end,
                          set=function(v) DB().customBorderOffset = v; ns.RefreshBorder(); UpdatePreview() end },
                        { type="slider", label="Offset Y", min=-10, max=10, step=1,
                          get=function()
                            local v = DB() and DB().customBorderOffsetY
                            if v then return v end
                            local tex = DBVal("customBorderTexture") or defaults.customBorderTexture
                            local sz  = DBVal("customBorderSize") or defaults.customBorderSize
                            local _, doy = EllesmereUI.GetBorderDefaults("nameplates", tex, sz)
                            return doy
                          end,
                          set=function(v) DB().customBorderOffsetY = v; ns.RefreshBorder(); UpdatePreview() end },
                        { type="slider", label="Shift X", min=-10, max=10, step=1,
                          get=function()
                            local v = DB() and DB().customBorderShiftX
                            if v then return v end
                            local tex = DBVal("customBorderTexture") or defaults.customBorderTexture
                            local sz  = DBVal("customBorderSize") or defaults.customBorderSize
                            local _, _, dsx = EllesmereUI.GetBorderDefaults("nameplates", tex, sz)
                            return dsx
                          end,
                          set=function(v) DB().customBorderShiftX = (v == 0 and nil or v); ns.RefreshBorder(); UpdatePreview() end },
                        { type="slider", label="Shift Y", min=-10, max=10, step=1,
                          get=function()
                            local v = DB() and DB().customBorderShiftY
                            if v then return v end
                            local tex = DBVal("customBorderTexture") or defaults.customBorderTexture
                            local sz  = DBVal("customBorderSize") or defaults.customBorderSize
                            local _, _, _, dsy = EllesmereUI.GetBorderDefaults("nameplates", tex, sz)
                            return dsy
                          end,
                          set=function(v) DB().customBorderShiftY = (v == 0 and nil or v); ns.RefreshBorder(); UpdatePreview() end },
                        { type="toggle", label="Show Behind",
                          get=function()
                            local v = DBVal("customBorderBehind")
                            if v == nil then return defaults.customBorderBehind end
                            return v
                          end,
                          set=function(v) DB().customBorderBehind = v; ns.RefreshBorder(); UpdatePreview() end },
                    },
                })
                local cbCogBtn = CreateFrame("Button", nil, leftRgn)
                cbCogBtn:SetSize(26, 26)
                cbCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
                leftRgn._lastInline = cbCogBtn
                cbCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
                local cbCogTex = cbCogBtn:CreateTexture(nil, "OVERLAY")
                cbCogTex:SetAllPoints(); cbCogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON or EllesmereUI.COGS_ICON)
                -- Offsets only apply to textured styles, so dim + disable the
                -- cog for the "solid" style. (The whole row only exists when
                -- Custom is selected, so no enable gate is needed.)
                local function cbCogOff() return (DBVal("customBorderTexture") or defaults.customBorderTexture) == "solid" end
                cbCogBtn:SetScript("OnEnter", function(s) if not cbCogOff() then s:SetAlpha(0.7) end end)
                cbCogBtn:SetScript("OnLeave", function(s) if not cbCogOff() then s:SetAlpha(0.4) end end)
                cbCogBtn:SetScript("OnClick", function(s) if not cbCogOff() then cbCogShow(s) end end)
                local function cbCogState()
                    local off = cbCogOff()
                    cbCogBtn:SetAlpha(off and 0.15 or 0.4)
                    cbCogBtn:EnableMouse(not off)
                end
                EllesmereUI.RegisterWidgetRefresh(cbCogState)
                cbCogState()
            end

            -- Inline color swatch (with alpha) on the Custom Border Size region
            do
                local rightRgn = customBorderRow._rightRegion
                local cbColGet = function()
                    local c = (DB() and DB().customBorderColor) or defaults.customBorderColor
                    return c.r, c.g, c.b, (DBVal("customBorderAlpha") or defaults.customBorderAlpha or 1)
                end
                local cbColSet = function(r, g, b, a)
                    DB().customBorderColor = { r = r, g = g, b = b }
                    if a ~= nil then DB().customBorderAlpha = a end
                    ns.RefreshBorderColor()
                    UpdatePreview()
                end
                local cbSwatch, cbUpdateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, cbColGet, cbColSet, true, 20)
                PP.Point(cbSwatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
                rightRgn._lastInline = cbSwatch
                EllesmereUI.RegisterWidgetRefresh(function() cbUpdateSwatch() end)
            end
        end

        -- Row 2: Background (+ inline color swatch) | Absorb Style (+ settings
        -- cog and preview eye). Absorb Style sits here so the section fills
        -- sequentially with no blank slot left in the middle.
        -- Blizzard + the stripe overlay set (shared with the Focus Texture
        -- dropdown) + Clean. Stripe keys resolve through ns.ResolveOverlayTexPath.
        local absorbStyleValues = {
            ["blizzard"]="Blizzard",
            ["striped"]="Striped",
            ["striped-v2"]="Stripes",
            ["striped-wide-v2"]="Wide Stripes",
            ["stripes-medium"]="Medium Stripes",
            ["stripes-small-close"]="Small Dense Stripes",
            ["stripes-small-spread"]="Small Spread Stripes",
            ["striped-tiny"]="Tiny Stripes",
            ["clean"]="Clean (Flat)",
        }
        local absorbStyleOrder = {
            "blizzard", "striped",
            "striped-v2", "striped-wide-v2", "stripes-medium",
            "stripes-small-close", "stripes-small-spread", "striped-tiny",
            "clean",
        }
        -- Append SharedMedia statusbar textures after a divider, mirroring the
        -- Bar Texture dropdown. SM keys ("sm:" prefixed) were appended to the
        -- shared health-bar tables by AppendSharedMediaTextures; render-time
        -- resolution flows through ns.ResolveOverlayTexPath -> the health-bar
        -- texture lookup, so a saved SM key paints correctly on the absorb bar.
        do
            local sepAdded = false
            for _, k in ipairs(hbtOrder) do
                if k ~= "---" and k:find("^sm:") then
                    if not sepAdded then
                        absorbStyleOrder[#absorbStyleOrder + 1] = "---"
                        sepAdded = true
                    end
                    absorbStyleOrder[#absorbStyleOrder + 1] = k
                    absorbStyleValues[k] = hbtValues[k]
                end
            end
            -- Preview swatch behind each menu row. Resolves exactly like the
            -- render path: NP_ABSORB_STYLE_TEX for blizzard/striped/clean, then
            -- ns.ResolveOverlayTexPath for stripe overlays and SM keys.
            absorbStyleValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    if not key or key == "---" then return nil end
                    return ns.NP_ABSORB_STYLE_TEX[key] or ns.ResolveOverlayTexPath(key)
                end,
            }
        end
        local bgHoverRow
        bgHoverRow, h = W:DualRow(parent, y,
            { type="slider", text="Background", min=0, max=100, step=1,
              getValue=function()
                return math.floor(((DBVal("bgAlpha") or defaults.bgAlpha) * 100) + 0.5)
              end,
              setValue=function(v)
                DB().bgAlpha = v / 100
                local c = (DB() and DB().bgColor) or defaults.bgColor
                for _, plate in pairs(plates) do
                    plate.healthBG:SetColorTexture(c.r, c.g, c.b, v / 100)
                end
                UpdatePreview()
              end },
            { type="dropdown", text="Absorb Style", values=absorbStyleValues, order=absorbStyleOrder,
              getValue=function() return DBVal("absorbStyle") or "blizzard" end,
              setValue=function(v)
                DB().absorbStyle = v
                -- Selecting a style sets the opacity to that style's default
                -- (Blizzard/Stripes 80%, Clean 30%); the slider tweaks from there.
                DB().absorbAlpha = math.floor(((ns.NP_ABSORB_STYLE_ALPHA[v] or 0.8) * 100) + 0.5)
                ns.ApplyAbsorbStyleAll()
                UpdatePreview()
                -- Refresh so the color swatch enables/disables (Blizzard = off).
                EllesmereUI:RefreshPage()
              end })
        y = y - h
        -- Inline color swatch on Background (left region)
        do
            local leftRgn = bgHoverRow._leftRegion
            local cbColorGet = function()
                local c = (DB() and DB().bgColor) or defaults.bgColor
                return c.r, c.g, c.b
            end
            local cbColorSet = function(r, g, b)
                DB().bgColor = { r = r, g = g, b = b }
                local a = DBVal("bgAlpha") or defaults.bgAlpha
                for _, plate in pairs(plates) do
                    plate.healthBG:SetColorTexture(r, g, b, a)
                end
                UpdatePreview()
            end
            local cbSwatch, cbUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, cbColorGet, cbColorSet, nil, 20)
            PP.Point(cbSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = cbSwatch
            EllesmereUI.RegisterWidgetRefresh(function() cbUpdateSwatch() end)
        end

        -- Inline absorb color swatch on the Absorb Style region (right of Row 2).
        -- White by default; tints every style except Blizzard (disabled there,
        -- since the Blizzard texture keeps its own coloring). Mirrors the Focus
        -- Texture swatch's disabled pattern.
        do
            local rgn = bgHoverRow._rightRegion
            local acColorGet = function()
                local c = (DB() and DB().absorbColor) or defaults.absorbColor or { r = 1, g = 1, b = 1 }
                return c.r, c.g, c.b
            end
            local acColorSet = function(r, g, b)
                DB().absorbColor = { r = r, g = g, b = b }
                ns.ApplyAbsorbStyleAll()
                UpdatePreview()
            end
            local acSwatch, acUpdateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, acColorGet, acColorSet, nil, 20)
            PP.Point(acSwatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = acSwatch
            local function absorbColorOff() return (DBVal("absorbStyle") or "blizzard") == "blizzard" end
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = absorbColorOff()
                acSwatch:SetAlpha(off and 0.15 or 1)
                acSwatch:EnableMouse(not off)
                acUpdateSwatch()
            end)
            local off0 = absorbColorOff()
            acSwatch:SetAlpha(off0 and 0.15 or 1)
            acSwatch:EnableMouse(not off0)
        end

        -- Inline "Absorb Settings" cog on the Absorb Style region (right of Row 2)
        do
            local rgn = bgHoverRow._rightRegion
            local _, absorbCogShow = EllesmereUI.BuildCogPopup({
                title = "Absorb Settings",
                rows = {
                    { type = "slider", label = "Opacity", min = 5, max = 100, step = 1,
                      get = function()
                        local v = DBVal("absorbAlpha")
                        if v then return v end
                        -- Untouched profiles: show the active style's default.
                        local style = DBVal("absorbStyle") or "blizzard"
                        if style == "clean" then return DBVal("absorbCleanAlpha") or 30 end
                        return math.floor(((ns.NP_ABSORB_STYLE_ALPHA[style] or 0.8) * 100) + 0.5)
                      end,
                      set = function(v)
                        DB().absorbAlpha = v
                        ns.ApplyAbsorbStyleAll()
                        UpdatePreview()
                      end },
                },
            })
            local absorbCogBtn = CreateFrame("Button", nil, rgn)
            absorbCogBtn:SetSize(26, 26)
            absorbCogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = absorbCogBtn
            absorbCogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            absorbCogBtn:SetAlpha(0.4)
            local absorbCogTex = absorbCogBtn:CreateTexture(nil, "OVERLAY")
            absorbCogTex:SetAllPoints(); absorbCogTex:SetTexture(EllesmereUI.COGS_ICON)
            absorbCogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            absorbCogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            absorbCogBtn:SetScript("OnClick", function(s) absorbCogShow(s) end)
        end

        -- Eye icon: toggle absorb preview on the preview nameplate
        do
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
            local rgn = bgHoverRow._rightRegion
            local eyeBtn = CreateFrame("Button", nil, rgn)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = eyeBtn
            eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            eyeBtn:SetAlpha(0.4)
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function RefreshAbsorbEye()
                if showAbsorbPreview then
                    eyeTex:SetTexture(EYE_INVISIBLE)
                else
                    eyeTex:SetTexture(EYE_VISIBLE)
                end
            end
            RefreshAbsorbEye()
            eyeBtn:SetScript("OnClick", function()
                showAbsorbPreview = not showAbsorbPreview
                RefreshAbsorbEye()
                UpdatePreview()
            end)
            eyeBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            eyeBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
        end

        -- Row 3: Bar Texture | Cast Bar Texture
        -- Both dropdowns share the same texture set (EUI built-ins + SharedMedia)
        -- and resolve identically; Bar Texture drives the health bar, Cast Bar
        -- Texture drives the cast bar.
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Bar Texture", values=hbtValues, order=hbtOrder,
              getValue=function() return DBVal("healthBarTexture") or "none" end,
              setValue=function(v)
                DB().healthBarTexture = v
                RefreshAllTextures()
                UpdatePreview()
              end },
            { type="dropdown", text="Cast Bar Texture", values=hbtValues, order=hbtOrder,
              getValue=function() return DBVal("castBarTexture") or "none" end,
              setValue=function(v)
                DB().castBarTexture = v
                RefreshAllTextures()
                UpdatePreview()
              end });  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  CORE POSITIONS
        -----------------------------------------------------------------------
        local coreHeader
        coreHeader, h = W:SectionHeader(parent, "CORE POSITIONS", y);  y = y - h

        -- Subtitle hint next to the section header
        do
            local regions = { coreHeader:GetRegions() }
            for _, rgn in ipairs(regions) do
                if rgn:IsObjectType("FontString") and EllesmereUI.EnKey(rgn:GetText()) == "CORE POSITIONS" then
                    local sub = coreHeader:CreateFontString(nil, "OVERLAY")
                    sub:SetFont(rgn:GetFont())
                    sub:SetTextColor(1, 1, 1, 0.25)
                    sub:SetText(EllesmereUI.L("(one per slot)"))
                    sub:SetPoint("LEFT", rgn, "RIGHT", 6, 0)
                    break
                end
            end
        end

        local coreElementValues = {
            debuffs        = "Debuffs",
            buffs          = "Buffs",
            ccs            = "CCs",
            debuffsccs     = "Debuffs + CC",
            raidmarker     = "Raid Marker",
            classification = "Rare/Quest Indicator",
            none           = "None",
        }
        local coreElementOrder = { "debuffs", "buffs", "ccs", "debuffsccs", "raidmarker", "classification", "none" }

        local coreRow1, coreRow2, coreRow3
        local _refreshRaidMarkerEyePos
        local _refreshClassificationEyePos

        RefreshCoreEyes = function()
            if _refreshRaidMarkerEyePos then _refreshRaidMarkerEyePos() end
            if _refreshClassificationEyePos then _refreshClassificationEyePos() end
        end

        -- Slot-based offsets: pos .. "SlotXOffset" / "SlotYOffset"

        local function CorePosXGet(pos)
            return DBVal(pos .. "SlotXOffset") or 0
        end
        local function CorePosYGet(pos)
            return DBVal(pos .. "SlotYOffset") or 0
        end
        local function CorePosXSet(pos, v)
            DB()[pos .. "SlotXOffset"] = v
            RefreshAllSlots()
        end
        local function CorePosYSet(pos, v)
            DB()[pos .. "SlotYOffset"] = v
            RefreshAllSlots()
        end
        local function CorePosOffDisabled(pos)
            return GetElementAtPosition(pos) == "none"
        end

        -------------------------------------------------------------------
        --  Icon Position Slider Popup  (singleton, slide-up animation)
        -------------------------------------------------------------------
        -------------------------------------------------------------------
        --  Combined Settings Popup  (singleton, slide-up, pos + optional size)
        -------------------------------------------------------------------
        local cogPopup          -- the popup frame (created once)
        local cogPopupOwner     -- which cog icon currently owns the popup

        local COGS_ICON = EllesmereUI.COGS_ICON

        -- opts = { title, xGet, xSet, yGet, ySet, sizeGet, sizeSet, sizeMin, sizeMax, sizeStep, sizeLabel }
        -- sizeGet may be nil no size row shown
        local function ShowCogPopup(anchorBtn, opts)
            if not cogPopup then
                local SolidTex = EllesmereUI.SolidTex
                local MakeBorder = EllesmereUI.MakeBorder
                local MakeFont = EllesmereUI.MakeFont
                local BuildSliderCore = EllesmereUI.BuildSliderCore
                local BORDER_COLOR = EllesmereUI.BORDER_COLOR
                local SL_INPUT_A = EllesmereUI.SL_INPUT_A

                local SIDE_PAD   = 14
                local INPUT_W    = 34; local SLIDER_INPUT_GAP = 8; local LABEL_SLIDER_GAP = 12
                local TOP_PAD    = 14
                local TITLE_H    = 11
                local TITLE_GAP  = 10
                local GAP        = 10
                local SLIDER_H   = 24

                -- Max height: title + X + Y + Size = 4 rows
                local MAX_H = TOP_PAD + TITLE_H + TITLE_GAP + GAP + SLIDER_H + GAP + SLIDER_H + GAP + SLIDER_H + TOP_PAD

                local pf = CreateFrame("Frame", nil, UIParent)
                pf:SetSize(260, MAX_H)
                pf:SetFrameStrata("DIALOG")
                pf:SetFrameLevel(200)
                pf:EnableMouse(true)
                pf:Hide()

                -- Match the panel/popup scale so this popup renders at the same
                -- size as the shared BuildCogPopup popups. Without this it stays
                -- at scale 1.0 and looks oversized next to every other cog popup.
                -- Registering it also lets it track the panel scale slider.
                pf:SetScale((EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1)
                if EllesmereUI._popupFrames then
                    EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = pf }
                end

                local bg = SolidTex(pf, "BACKGROUND", 0.06, 0.08, 0.10, 0.95)
                bg:SetAllPoints()
                MakeBorder(pf, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15)

                local titleFS = MakeFont(pf, 11, "", 1, 1, 1)
                titleFS:SetAlpha(0.7)
                titleFS:SetPoint("TOP", pf, "TOP", 0, -TOP_PAD)
                pf._titleFS = titleFS

                local tmpFS = pf:CreateFontString(nil, "OVERLAY")
                tmpFS:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 12, GetNPOptOutline())
                local labelTexts = {"X Offset", "Y Offset", "Size", "Width %", "Spacing", "Opacity"}
                local maxLblW = 0
                for _, txt in ipairs(labelTexts) do
                    tmpFS:SetText(EllesmereUI.L(txt))
                    local w = tmpFS:GetStringWidth()
                    if w > maxLblW then maxLblW = w end
                end
                tmpFS:Hide()
                if maxLblW < 10 then maxLblW = 28 end

                local SLIDER_LEFT = SIDE_PAD + maxLblW + LABEL_SLIDER_GAP
                local SLIDER_W = math.max(80, 260 - SLIDER_LEFT - SLIDER_INPUT_GAP - INPUT_W - SIDE_PAD)
                local POPUP_W = SLIDER_LEFT + SLIDER_W + SLIDER_INPUT_GAP + INPUT_W + SIDE_PAD
                if POPUP_W < 180 then POPUP_W = 180 end
                pf:SetSize(POPUP_W, pf:GetHeight())

                -- X slider row
                local X_ROW_Y = -(TOP_PAD + TITLE_H + TITLE_GAP + GAP)
                local xLabel = MakeFont(pf, 12, nil, 1, 1, 1)
                xLabel:SetAlpha(0.6); xLabel:SetText(EllesmereUI.L("X Offset"))
                xLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, X_ROW_Y - SLIDER_H / 2)
                local xTrack, xValBox = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, SLIDER_H, 11, SL_INPUT_A,
                    -100, 100, 1,
                    function() return pf._xGet and pf._xGet() or 0 end,
                    function(v) if pf._xSet then pf._xSet(v) end end, true)
                xTrack:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, X_ROW_Y - 2)
                xValBox:ClearAllPoints(); xValBox:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, X_ROW_Y)

                pf._xTrack = xTrack; pf._xValBox = xValBox; pf._xLabel = xLabel

                -- Y slider row
                local Y_ROW_Y = X_ROW_Y - SLIDER_H - GAP
                local yLabel = MakeFont(pf, 12, nil, 1, 1, 1)
                yLabel:SetAlpha(0.6); yLabel:SetText(EllesmereUI.L("Y Offset"))
                yLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, Y_ROW_Y - SLIDER_H / 2)
                local yTrack, yValBox = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, SLIDER_H, 11, SL_INPUT_A,
                    -100, 100, 1,
                    function() return pf._yGet and pf._yGet() or 0 end,
                    function(v) if pf._ySet then pf._ySet(v) end end, true)
                yTrack:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, Y_ROW_Y - 2)
                yValBox:ClearAllPoints(); yValBox:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, Y_ROW_Y)

                pf._yTrack = yTrack; pf._yValBox = yValBox; pf._yLabel = yLabel

                -- Size slider row (hidden when not needed)
                local S_ROW_Y = Y_ROW_Y - SLIDER_H - GAP
                local sLabel = MakeFont(pf, 12, nil, 1, 1, 1)
                sLabel:SetAlpha(0.6); sLabel:SetText(EllesmereUI.L("Size"))
                sLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, S_ROW_Y - SLIDER_H / 2)
                pf._sLabel = sLabel

                -- Spacing slider row (hidden unless the slot holds a multi-icon
                -- aura element: debuffs / buffs / CCs). Fixed range, built once.
                local SP_ROW_Y = S_ROW_Y - SLIDER_H - GAP
                local spLabel = MakeFont(pf, 12, nil, 1, 1, 1)
                spLabel:SetAlpha(0.6); spLabel:SetText(EllesmereUI.L("Spacing"))
                spLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, SP_ROW_Y - SLIDER_H / 2)
                spLabel:Hide()
                pf._spLabel = spLabel
                local spTrack, spValBox = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, SLIDER_H, 11, SL_INPUT_A,
                    -5, 20, 1,
                    function() return pf._spGet and pf._spGet() or 0 end,
                    function(v) if pf._spSet then pf._spSet(v) end end, true)
                spTrack:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, SP_ROW_Y - 2)
                spValBox:ClearAllPoints(); spValBox:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, SP_ROW_Y)
                spTrack:Hide(); spValBox:Hide()
                pf._spTrack = spTrack; pf._spValBox = spValBox

                -- Width % slider row (hidden unless a width-fit text element: enemy
                -- name, cast spell name, cast target). Fixed range, built once; the
                -- row is reordered/repositioned per show via the seq block below.
                local W_ROW_Y = SP_ROW_Y - SLIDER_H - GAP
                local wLabel = MakeFont(pf, 12, nil, 1, 1, 1)
                wLabel:SetAlpha(0.6); wLabel:SetText(EllesmereUI.L("Width %"))
                wLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, W_ROW_Y - SLIDER_H / 2)
                wLabel:Hide()
                pf._wLabel = wLabel
                -- Invisible hover region over the label for its tooltip (FontStrings
                -- are not mouse-interactive). SetAllPoints tracks the label, so it
                -- follows the row wherever it is repositioned; shown/hidden with the row.
                local wHover = CreateFrame("Frame", nil, pf)
                wHover:SetFrameLevel(pf:GetFrameLevel() + 10)
                wHover:SetAllPoints(wLabel)
                wHover:EnableMouse(true)
                wHover:Hide()
                wHover:SetScript("OnEnter", function(self)
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Maximum width the text can fill before it truncates, as a percentage of the bar."), { width = 230 })
                end)
                wHover:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                pf._wHover = wHover
                local wTrack, wValBox = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, SLIDER_H, 11, SL_INPUT_A,
                    10, 150, 1,
                    function() return pf._wGet and pf._wGet() or 0 end,
                    function(v) if pf._wSet then pf._wSet(v) end end, true)
                wTrack:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, W_ROW_Y - 2)
                wValBox:ClearAllPoints(); wValBox:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, W_ROW_Y)
                wTrack:Hide(); wValBox:Hide()
                pf._wTrack = wTrack; pf._wValBox = wValBox

                -- Store layout values for dynamic size slider rebuild + reorder
                pf._SLIDER_LEFT = SLIDER_LEFT
                pf._SLIDER_W = SLIDER_W
                pf._X_ROW_Y = X_ROW_Y
                pf._Y_ROW_Y = Y_ROW_Y
                pf._S_ROW_Y = S_ROW_Y
                pf._SP_ROW_Y = SP_ROW_Y
                pf._ROW0 = X_ROW_Y
                pf._ROW_STEP = SLIDER_H + GAP

                -- Growth direction row (shown only for topleft/topright slots)
                local GROWTH_ROW_H = 22
                local G_ROW_Y = S_ROW_Y - SLIDER_H - GAP
                pf._G_ROW_Y = G_ROW_Y
                pf._GROWTH_ROW_H = GROWTH_ROW_H

                local gLabel = MakeFont(pf, 12, nil, 1, 1, 1)
                gLabel:SetAlpha(0.6); gLabel:SetText(EllesmereUI.L("Grow"))
                gLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
                pf._gLabel = gLabel

                -- Grow direction is a standard dropdown. Its option list + order vary
                -- per cog (topleft vs topright), so they are filled into these mutable
                -- tables at show time and the menu is invalidated to rebuild from them.
                -- getValue/setValue delegate to the per-show growth getter/setter, so
                -- the backend keys and behaviour are identical to the old buttons.
                pf._growthValues = {}   -- key -> label
                pf._growthOrder  = {}   -- ordered keys
                -- Standard cog-popup dropdown sizing (matches BuildCogPopup's
                -- dropdown rows): 130px wide, rendered 10% smaller, right-aligned
                -- at layout time -- not the old full-content-width control.
                local GROW_DD_W = 130
                local GROW_DD_SCALE = 0.9
                pf._GROW_DD_SCALE = GROW_DD_SCALE
                local gDD = EllesmereUI.BuildDropdownControl(pf, GROW_DD_W, pf:GetFrameLevel() + 6,
                    pf._growthValues, pf._growthOrder,
                    function() return pf._growthGet and pf._growthGet() or "" end,
                    function(v) if pf._growthSet then pf._growthSet(v) end end)
                gDD:SetScale(GROW_DD_SCALE)
                -- The lazily-created menu parents to UIParent (scale 1); sync it
                -- to the shrunk control the first time it opens.
                gDD:HookScript("OnClick", function(self)
                    if self._ddMenu and not self._ddMenu._npCogScaled then
                        self._ddMenu:SetScale(GROW_DD_SCALE)
                        self._ddMenu._npCogScaled = true
                    end
                end)
                gDD:Hide()
                pf._gDD = gDD

                -- Optional toggle row. Anchored at layout time: it takes the
                -- 4th-row slot (G_ROW_Y) when the cog has no Grow row, and
                -- stacks BELOW Grow when both are present (Rare/Quest Indicator
                -- on a topleft/topright slot: Grow + Show In Instances). Wired
                -- per-invocation via pf._toggleGet / pf._toggleSet.
                local tLabel = MakeFont(pf, 12, nil, 1, 1, 1)
                tLabel:SetAlpha(0.6)
                tLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
                tLabel:Hide()
                pf._tLabel = tLabel
                local tToggle, _, tToggleSnap = EllesmereUI.BuildToggleControl(pf, pf:GetFrameLevel() + 5,
                    function() return pf._toggleGet and pf._toggleGet() or false end,
                    function(v) if pf._toggleSet then pf._toggleSet(v) end end,
                    { sizeRatio = 0.8, noAnim = true })
                tToggle:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
                tToggle:Hide()
                pf._tToggle = tToggle
                pf._toggleSnap = tToggleSnap

                -- Optional "Raise Strata" toggle row (own row, below Grow /
                -- Cropped Icons / Wrap so it can coexist with any of them on a
                -- Core Position slot). Wired via pf._rsGet / pf._rsSet.
                local rsLabel = MakeFont(pf, 12, nil, 1, 1, 1)
                rsLabel:SetAlpha(0.6)
                rsLabel:SetText(EllesmereUI.L("Raise Strata"))
                rsLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
                rsLabel:Hide()
                pf._rsLabel = rsLabel
                -- Invisible hover region over the label for its tooltip.
                local rsHover = CreateFrame("Frame", nil, pf)
                rsHover:SetFrameLevel(pf:GetFrameLevel() + 10)
                rsHover:SetAllPoints(rsLabel)
                rsHover:EnableMouse(true)
                rsHover:Hide()
                rsHover:SetScript("OnEnter", function(self)
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Renders this slot's element above the rest of the nameplate."), { width = 230 })
                end)
                rsHover:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                pf._rsHover = rsHover
                local rsToggle, _, rsToggleSnap = EllesmereUI.BuildToggleControl(pf, pf:GetFrameLevel() + 5,
                    function() return pf._rsGet and pf._rsGet() or false end,
                    function(v) if pf._rsSet then pf._rsSet(v) end end,
                    { sizeRatio = 0.8, noAnim = true })
                rsToggle:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
                rsToggle:Hide()
                pf._rsToggle = rsToggle
                pf._rsToggleSnap = rsToggleSnap

                -- Optional "Cropped Icons" toggle row. Unlike the generic toggle
                -- above, this gets its OWN row below the data/grow rows so it can
                -- coexist with the Grow row on aura slots. Wired via
                -- pf._cropGet / pf._cropSet; repositioned per show.
                local cropLabel = MakeFont(pf, 12, nil, 1, 1, 1)
                cropLabel:SetAlpha(0.6)
                cropLabel:SetText(EllesmereUI.L("Cropped Icons"))
                cropLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
                cropLabel:Hide()
                pf._cropLabel = cropLabel
                local cropToggle, _, cropToggleSnap = EllesmereUI.BuildToggleControl(pf, pf:GetFrameLevel() + 5,
                    function() return pf._cropGet and pf._cropGet() or false end,
                    function(v) if pf._cropSet then pf._cropSet(v) end end,
                    { sizeRatio = 0.8, noAnim = true })
                cropToggle:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
                cropToggle:Hide()
                pf._cropToggle = cropToggle
                pf._cropToggleSnap = cropToggleSnap

                -- Optional "Wrap" toggle row (own row, like Cropped Icons). Used by
                -- the truncating text elements (enemy name, cast name/target, health
                -- text) so it can coexist with the generic toggle -- e.g. health
                -- text keeps "Show % Decimal" on the generic toggle and "Wrap" here.
                -- Wired via pf._wrapGet / pf._wrapSet; repositioned per show.
                local wrapLabel = MakeFont(pf, 12, nil, 1, 1, 1)
                wrapLabel:SetAlpha(0.6)
                wrapLabel:SetText(EllesmereUI.L("Wrap"))
                wrapLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
                wrapLabel:Hide()
                pf._wrapLabel = wrapLabel
                -- Invisible hover region over the Wrap label for its tooltip (see the
                -- Width % hover above). Tracks the label and is shown/hidden with the row.
                local wrapHover = CreateFrame("Frame", nil, pf)
                wrapHover:SetFrameLevel(pf:GetFrameLevel() + 10)
                wrapHover:SetAllPoints(wrapLabel)
                wrapHover:EnableMouse(true)
                wrapHover:Hide()
                wrapHover:SetScript("OnEnter", function(self)
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Lets long text wrap onto a second line instead of being cut off."), { width = 230 })
                end)
                wrapHover:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                pf._wrapHover = wrapHover
                local wrapToggle, _, wrapToggleSnap = EllesmereUI.BuildToggleControl(pf, pf:GetFrameLevel() + 5,
                    function() return pf._wrapGet and pf._wrapGet() or false end,
                    function(v) if pf._wrapSet then pf._wrapSet(v) end end,
                    { sizeRatio = 0.8, noAnim = true })
                wrapToggle:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
                wrapToggle:Hide()
                pf._wrapToggle = wrapToggle
                pf._wrapToggleSnap = wrapToggleSnap

                -- Layout constants stored for height calc
                pf._TOP_PAD = TOP_PAD; pf._TITLE_H = TITLE_H; pf._TITLE_GAP = TITLE_GAP
                pf._GAP = GAP; pf._SLIDER_H = SLIDER_H; pf._SIDE_PAD = SIDE_PAD
                pf._POPUP_W = POPUP_W

                -- Close on click outside
                local wasDown = false
                pf._clickOutside = function(self, dt)
                    local down = IsMouseButtonDown("LeftButton")
                    if down and not wasDown then
                        -- The Grow dropdown's menu floats outside this popup's rect;
                        -- a click on it must not be treated as a click-outside.
                        local m = self._gDD and self._gDD._ddMenu
                        local overMenu = m and m:IsShown() and m:IsMouseOver()
                        if not self:IsMouseOver() and not (cogPopupOwner and cogPopupOwner:IsMouseOver()) and not overMenu then
                            self:Hide()
                        end
                    end
                    wasDown = down
                end

                pf:SetScript("OnHide", function(self)
                    self:SetScript("OnUpdate", nil)
                    if cogPopupOwner then cogPopupOwner:SetAlpha(0.4) end
                    cogPopupOwner = nil
                end)

                if EllesmereUI._mainFrame then
                    EllesmereUI._mainFrame:HookScript("OnHide", function()
                        if pf:IsShown() then pf:Hide() end
                    end)
                end

                cogPopup = pf
            end

            -- Toggle off if same icon clicked again
            if cogPopupOwner == anchorBtn and cogPopup:IsShown() then
                cogPopup:Hide()
                return
            end

            -- Wire getters/setters
            cogPopup._xGet = opts.xGet; cogPopup._xSet = opts.xSet
            cogPopup._yGet = opts.yGet; cogPopup._ySet = opts.ySet
            cogPopup._titleFS:SetText(EllesmereUI.L(opts.title))
            cogPopupOwner = anchorBtn

            -- Show/hide size row and adjust height
            local hasSize = opts.sizeGet ~= nil
            local hasWidth = opts.widthGet ~= nil
            local hasSpacing = opts.spacingGet ~= nil
            local hasGrowth = opts.growthGet ~= nil
            local hasToggle = opts.toggleGet ~= nil
            local hasCrop = opts.cropGet ~= nil
            local hasWrap = opts.wrapGet ~= nil
            local hasRaiseStrata = opts.raiseStrataGet ~= nil
            if hasSize then
                -- Rebuild size slider if range changed
                local sStep = opts.sizeStep or 1
                if cogPopup._curMin ~= opts.sizeMin or cogPopup._curMax ~= opts.sizeMax or cogPopup._curStep ~= sStep then
                    if cogPopup._sTrack then cogPopup._sTrack:Hide(); cogPopup._sTrack:SetParent(nil) end
                    if cogPopup._sValBox then cogPopup._sValBox:Hide(); cogPopup._sValBox:SetParent(nil) end
                    local sTrack, sValBox = EllesmereUI.BuildSliderCore(cogPopup, cogPopup._SLIDER_W, 4, 12, 34, 24, 11, EllesmereUI.SL_INPUT_A,
                        opts.sizeMin, opts.sizeMax, sStep,
                        function() return cogPopup._sGet and cogPopup._sGet() or 0 end,
                        function(v) if cogPopup._sSet then cogPopup._sSet(v) end end, true)
                    sTrack:ClearAllPoints(); sTrack:SetPoint("TOPLEFT", cogPopup, "TOPLEFT", cogPopup._SLIDER_LEFT, cogPopup._S_ROW_Y - (cogPopup._SLIDER_H - 20) / 2)
                    sValBox:ClearAllPoints(); sValBox:SetPoint("TOPRIGHT", cogPopup, "TOPRIGHT", -cogPopup._SIDE_PAD, cogPopup._S_ROW_Y)
                    cogPopup._sTrack = sTrack; cogPopup._sValBox = sValBox
                    cogPopup._curMin = opts.sizeMin; cogPopup._curMax = opts.sizeMax; cogPopup._curStep = sStep
                end
                cogPopup._sGet = opts.sizeGet; cogPopup._sSet = opts.sizeSet
                cogPopup._sLabel:SetText(opts.sizeLabel or EllesmereUI.L("Size"))
                cogPopup._sLabel:Show()
                if cogPopup._sTrack then cogPopup._sTrack:Show() end
                if cogPopup._sValBox then cogPopup._sValBox:Show() end
            else
                cogPopup._sLabel:Hide()
                if cogPopup._sTrack then cogPopup._sTrack:Hide() end
                if cogPopup._sValBox then cogPopup._sValBox:Hide() end
            end

            -- Show/hide spacing row
            if hasSpacing then
                cogPopup._spGet = opts.spacingGet
                cogPopup._spSet = opts.spacingSet
                cogPopup._spLabel:Show()
                cogPopup._spTrack:Show()
                cogPopup._spValBox:Show()
            else
                cogPopup._spGet = nil
                cogPopup._spSet = nil
                cogPopup._spLabel:Hide()
                cogPopup._spTrack:Hide()
                cogPopup._spValBox:Hide()
            end

            -- Show/hide width % row
            if hasWidth then
                cogPopup._wGet = opts.widthGet
                cogPopup._wSet = opts.widthSet
                cogPopup._wLabel:SetText(EllesmereUI.L(opts.widthLabel or "Width %"))
                cogPopup._wLabel:Show()
                cogPopup._wTrack:Show()
                cogPopup._wValBox:Show()
                if cogPopup._wHover then cogPopup._wHover:Show() end
            else
                cogPopup._wGet = nil
                cogPopup._wSet = nil
                cogPopup._wLabel:Hide()
                cogPopup._wTrack:Hide()
                cogPopup._wValBox:Hide()
                if cogPopup._wHover then cogPopup._wHover:Hide() end
            end

            -- Show/hide growth row (a dropdown)
            if hasGrowth then
                cogPopup._growthGet = opts.growthGet
                cogPopup._growthSet = opts.growthSet
                -- Refill the dropdown's option map + order from this cog's values
                -- (mutated in place so the dropdown's captured tables stay current).
                local vals = opts.growthValues  -- { { value, label }, ... }
                wipe(cogPopup._growthValues)
                wipe(cogPopup._growthOrder)
                if vals then
                    for _, entry in ipairs(vals) do
                        cogPopup._growthValues[entry.value] = entry.label
                        cogPopup._growthOrder[#cogPopup._growthOrder + 1] = entry.value
                    end
                end
                if cogPopup._gDD then
                    -- Rebuild the menu from the refilled tables and refresh the label.
                    if cogPopup._gDD._invalidateMenu then cogPopup._gDD._invalidateMenu() end
                    cogPopup._gDD:Show()
                end
                cogPopup._gLabel:Show()
            else
                cogPopup._growthGet = nil
                cogPopup._growthSet = nil
                cogPopup._gLabel:Hide()
                if cogPopup._gDD then cogPopup._gDD:Hide() end
            end

            -- Show/hide toggle row (shares the G_ROW_Y slot with Grow)
            if hasToggle then
                cogPopup._toggleGet = opts.toggleGet
                cogPopup._toggleSet = opts.toggleSet
                cogPopup._tLabel:SetText(EllesmereUI.L(opts.toggleLabel or ""))
                cogPopup._tLabel:Show()
                cogPopup._tToggle:Show()
                if cogPopup._toggleSnap then cogPopup._toggleSnap() end
            else
                cogPopup._toggleGet = nil
                cogPopup._toggleSet = nil
                cogPopup._tLabel:Hide()
                cogPopup._tToggle:Hide()
            end

            -- Show/hide Cropped Icons row (its own row, below Grow when present)
            if hasCrop then
                cogPopup._cropGet = opts.cropGet
                cogPopup._cropSet = opts.cropSet
                cogPopup._cropLabel:Show()
                cogPopup._cropToggle:Show()
                if cogPopup._cropToggleSnap then cogPopup._cropToggleSnap() end
            else
                cogPopup._cropGet = nil
                cogPopup._cropSet = nil
                cogPopup._cropLabel:Hide()
                cogPopup._cropToggle:Hide()
            end

            -- Show/hide Wrap row (its own row, like Cropped Icons)
            if hasWrap then
                cogPopup._wrapGet = opts.wrapGet
                cogPopup._wrapSet = opts.wrapSet
                cogPopup._wrapLabel:Show()
                cogPopup._wrapToggle:Show()
                if cogPopup._wrapToggleSnap then cogPopup._wrapToggleSnap() end
                if cogPopup._wrapHover then cogPopup._wrapHover:Show() end
            else
                cogPopup._wrapGet = nil
                cogPopup._wrapSet = nil
                cogPopup._wrapLabel:Hide()
                cogPopup._wrapToggle:Hide()
                if cogPopup._wrapHover then cogPopup._wrapHover:Hide() end
            end

            -- Show/hide Raise Strata row (its own row, below all other toggles)
            if hasRaiseStrata then
                cogPopup._rsGet = opts.raiseStrataGet
                cogPopup._rsSet = opts.raiseStrataSet
                cogPopup._rsLabel:Show()
                cogPopup._rsToggle:Show()
                if cogPopup._rsToggleSnap then cogPopup._rsToggleSnap() end
                if cogPopup._rsHover then cogPopup._rsHover:Show() end
            else
                cogPopup._rsGet = nil
                cogPopup._rsSet = nil
                cogPopup._rsLabel:Hide()
                cogPopup._rsToggle:Hide()
                if cogPopup._rsHover then cogPopup._rsHover:Hide() end
            end

            -- Row order: cogs that pass sizeFirst (core position / core text
            -- position) put Size at the top; everyone else keeps X, Y, Size.
            -- Spacing (when present) follows Size. Grow / toggle always sit in
            -- the row directly after the last data row, repositioned each show
            -- so they slide down when the optional Spacing row appears.
            do
                local p = cogPopup
                local SH, SLEFT, SPAD = p._SLIDER_H, p._SLIDER_LEFT, p._SIDE_PAD
                local GRH = p._GROWTH_ROW_H
                local function rowY(i) return p._ROW0 - (i - 1) * p._ROW_STEP end
                local function anchorRow(lbl, track, valBox, ry)
                    lbl:ClearAllPoints();  lbl:SetPoint("LEFT", p, "TOPLEFT", SPAD, ry - SH / 2)
                    if track  then track:ClearAllPoints();  track:SetPoint("TOPLEFT", p, "TOPLEFT", SLEFT, ry - 2) end
                    if valBox then valBox:ClearAllPoints(); valBox:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SPAD, ry) end
                end
                -- Width % is intentionally NOT in this data-row sequence: it is
                -- repositioned to the very bottom (below Wrap) further down, so it
                -- never sits between Size and X/Y.
                local seq = {}
                if hasSize and opts.sizeFirst then
                    seq[#seq + 1] = { p._sLabel, p._sTrack, p._sValBox }
                    if hasSpacing then seq[#seq + 1] = { p._spLabel, p._spTrack, p._spValBox } end
                    seq[#seq + 1] = { p._xLabel, p._xTrack, p._xValBox }
                    seq[#seq + 1] = { p._yLabel, p._yTrack, p._yValBox }
                else
                    seq[#seq + 1] = { p._xLabel, p._xTrack, p._xValBox }
                    seq[#seq + 1] = { p._yLabel, p._yTrack, p._yValBox }
                    if hasSize    then seq[#seq + 1] = { p._sLabel, p._sTrack, p._sValBox } end
                    if hasSpacing then seq[#seq + 1] = { p._spLabel, p._spTrack, p._spValBox } end
                end
                for i, r in ipairs(seq) do
                    anchorRow(r[1], r[2], r[3], rowY(i))
                end
                -- Growth / toggle rows sit directly after the data rows. They
                -- historically shared one row (mutually exclusive), but a cog
                -- can now pass BOTH (Rare/Quest Indicator on a topleft/right
                -- slot: Grow + Show In Instances) -- the toggle then takes the
                -- row BELOW Grow.
                local nextY = rowY(#seq + 1)
                p._gLabel:ClearAllPoints()
                p._gLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, nextY - GRH / 2)
                if p._gDD then
                    -- Right-aligned like standard cog dropdowns. Offsets divided
                    -- by the control's scale so the scaled frame still lands
                    -- flush-right and vertically centered on the row.
                    local ds = p._GROW_DD_SCALE or 1
                    p._gDD:ClearAllPoints()
                    p._gDD:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD / ds, (nextY - GRH / 2) / ds)
                end
                local toggleY = hasGrowth and rowY(#seq + 2) or nextY
                p._tLabel:ClearAllPoints()
                p._tLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, toggleY - GRH / 2)
                p._tToggle:ClearAllPoints()
                p._tToggle:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD, toggleY - GRH / 2)
                -- Rows consumed by the Grow/toggle band (0, 1 or 2).
                local extraRows = (hasGrowth and 1 or 0) + (hasToggle and 1 or 0)
                -- Cropped Icons sits in its own row below the Grow/toggle band,
                -- otherwise directly after the data rows.
                local cropY = rowY(#seq + 1 + extraRows)
                p._cropLabel:ClearAllPoints()
                p._cropLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, cropY - GRH / 2)
                p._cropToggle:ClearAllPoints()
                p._cropToggle:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD, cropY - GRH / 2)
                -- Wrap sits in its own row, like Cropped Icons: below the
                -- Grow/toggle band when present, else after the data rows.
                -- (No cog uses both Wrap and Cropped Icons, so they never collide.)
                local wrapY = rowY(#seq + 1 + extraRows)
                p._wrapLabel:ClearAllPoints()
                p._wrapLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, wrapY - GRH / 2)
                p._wrapToggle:ClearAllPoints()
                p._wrapToggle:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD, wrapY - GRH / 2)
                -- Raise Strata sits in its own row, below the Grow/toggle band
                -- and below Cropped Icons when those are present. Core Position
                -- cogs never use Wrap or Width %, so it never collides with those.
                if hasRaiseStrata then
                    local rsRowIndex = #seq + 1 + extraRows
                    if hasCrop or hasWrap then rsRowIndex = rsRowIndex + 1 end
                    local rsY = rowY(rsRowIndex)
                    p._rsLabel:ClearAllPoints()
                    p._rsLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, rsY - GRH / 2)
                    p._rsToggle:ClearAllPoints()
                    p._rsToggle:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD, rsY - GRH / 2)
                end
                -- Width % is the very last row, one below Wrap (and below the
                -- Grow/toggle band / Cropped Icons when those are present). It
                -- stays a slider row, so anchorRow handles label + track + box.
                if hasWidth then
                    local widthRowIndex = #seq + 1 + extraRows
                    if hasCrop or hasWrap then widthRowIndex = widthRowIndex + 1 end
                    anchorRow(p._wLabel, p._wTrack, p._wValBox, rowY(widthRowIndex))
                end
            end

            -- Compute height based on visible rows
            do
                local p = cogPopup
                local rowH = p._SLIDER_H
                local gap  = p._GAP
                local rows = 2  -- X + Y always present
                if hasSize   then rows = rows + 1 end
                if hasGrowth then rows = rows + 1 end
                local h = p._TOP_PAD + p._TITLE_H + p._TITLE_GAP
                for r = 1, rows do
                    h = h + gap + (r < rows and rowH or p._GROWTH_ROW_H)
                end
                -- last row uses GROWTH_ROW_H only if growth is the last row
                -- recalculate cleanly
                h = p._TOP_PAD + p._TITLE_H + p._TITLE_GAP
                    + gap + rowH   -- X
                    + gap + rowH   -- Y
                if hasSize    then h = h + gap + rowH end
                if hasWidth   then h = h + gap + rowH end
                if hasSpacing then h = h + gap + rowH end
                if hasGrowth then h = h + gap + p._GROWTH_ROW_H end
                -- Toggle gets its own row (stacks below Grow when both present).
                if hasToggle then h = h + gap + p._GROWTH_ROW_H end
                -- Cropped Icons always occupies its own extra row.
                if hasCrop then h = h + gap + p._GROWTH_ROW_H end
                -- Wrap occupies its own extra row.
                if hasWrap then h = h + gap + p._GROWTH_ROW_H end
                -- Raise Strata occupies its own extra row.
                if hasRaiseStrata then h = h + gap + p._GROWTH_ROW_H end
                h = h + p._TOP_PAD
                cogPopup:SetHeight(h)
            end

            -- Anchor above the icon
            cogPopup:ClearAllPoints()
            cogPopup:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6)

            -- Slide-up animation
            cogPopup:SetAlpha(0)
            cogPopup:Show()
            local elapsed = 0
            local ANIM_DUR = 0.15
            cogPopup:SetScript("OnUpdate", function(self, dt)
                elapsed = elapsed + dt
                local t = math.min(elapsed / ANIM_DUR, 1)
                self:SetAlpha(t)
                self:ClearAllPoints()
                self:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6 + (-8 * (1 - t)))
                if t >= 1 then
                    self:SetScript("OnUpdate", self._clickOutside)
                end
            end)

            EllesmereUI:RefreshPage()
        end

        local DISABLED_TIP = "This option requires an aura or indicator to be assigned"

        -- Per-kind slot filter popup (12.1): Show All Debuffs toggle |
        -- Filters checkbox dropdown, on the standard dimmer/panel chrome.
        -- The containers file owns the configs and record groups
        -- (ns.NPF_Config / NPC_ReloadAll); this is pure UI over them.
        local NPF_KIND_TITLES = {
            debuffs = "Debuff Filters", cc = "CC Filters", dcc = "Debuffs + CC Filters",
        }
        local NPF_CAT_ITEMS = {
            { key = "priority",   label = "Important" },
            { key = "cc",         label = "Crowd Control" },
            { key = "boss",       label = "Boss" },
            { key = "role",       label = "Role" },
            { key = "raid",       label = "Raid" },
            { key = "raidcombat", label = "Raid While In Combat" },
            { key = "dispel",     label = "Dispellable By You" },
        }
        function ns.NPP_ShowFilterPopup(kind)
            if not (EllesmereUI.IS_121 and ns.NPF_Config) then return end
            local cfg = ns.NPF_Config(kind)
            if not cfg then return end
            if ns._npfPopup then ns._npfPopup:Hide(); ns._npfPopup = nil end
            local fp2 = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("nameplates")) or DBVal("font")

            local ppScale = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1
            local EG = EllesmereUI.ELLESMERE_GREEN

            local dimmer = CreateFrame("Button", "EUINPFilterDimmer", UIParent)
            dimmer:SetAllPoints(UIParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetScale(ppScale)
            dimmer:EnableMouseWheel(true)
            dimmer:SetScript("OnMouseWheel", function() end)
            local dim = dimmer:CreateTexture(nil, "BACKGROUND")
            dim:SetAllPoints(); dim:SetColorTexture(0, 0, 0, 0.35)
            dimmer:SetScript("OnClick", function()
                dimmer:Hide(); ns._npfPopup = nil
            end)
            ns._npfPopup = dimmer

            local panel = CreateFrame("Frame", "EUINPFilterPopup", dimmer)
            panel:SetSize(440, 470)
            panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
            panel:SetFrameLevel(dimmer:GetFrameLevel() + 10)
            panel:EnableMouse(true)
            local pbg = panel:CreateTexture(nil, "BACKGROUND")
            pbg:SetAllPoints(); pbg:SetColorTexture(0.06, 0.08, 0.10, 1)
            -- One-physical-pixel border (announcement-popup chrome): four
            -- edge textures, snap disabled, scale-derived thickness.
            do
                local onePhys = 1 / (panel:GetEffectiveScale() or 1)
                local function Edge()
                    local t = panel:CreateTexture(nil, "BORDER")
                    t:SetColorTexture(1, 1, 1, 0.15)
                    if t.SetSnapToPixelGrid then
                        t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0)
                    end
                    return t
                end
                local eT = Edge(); eT:SetPoint("TOPLEFT", 0, 0); eT:SetPoint("TOPRIGHT", 0, 0); eT:SetHeight(onePhys)
                local eB = Edge(); eB:SetPoint("BOTTOMLEFT", 0, 0); eB:SetPoint("BOTTOMRIGHT", 0, 0); eB:SetHeight(onePhys)
                local eL = Edge(); eL:SetPoint("TOPLEFT", eT, "BOTTOMLEFT"); eL:SetPoint("BOTTOMLEFT", eB, "TOPLEFT"); eL:SetWidth(onePhys)
                local eR = Edge(); eR:SetPoint("TOPRIGHT", eT, "BOTTOMRIGHT"); eR:SetPoint("BOTTOMRIGHT", eB, "TOPRIGHT"); eR:SetWidth(onePhys)
            end
            -- Header: accent eyebrow + large title (announcement style).
            local eyebrow = panel:CreateFontString(nil, "OVERLAY")
            eyebrow:SetFont(fp2, 11, "")
            eyebrow:SetPoint("TOP", panel, "TOP", 0, -16)
            eyebrow:SetTextColor(EG.r, EG.g, EG.b, 0.9)
            eyebrow:SetText(EllesmereUI.L("NAMEPLATE AURA FILTERS"))
            local title = panel:CreateFontString(nil, "OVERLAY")
            title:SetFont(fp2, 20, "")
            title:SetPoint("TOP", panel, "TOP", 0, -32)
            title:SetTextColor(1, 1, 1, 0.95)
            title:SetText(EllesmereUI.L(NPF_KIND_TITLES[kind] or "Filters"))

            local function ClosePopup()
                dimmer:Hide()
                ns._npfPopup = nil
            end

            -- Escape closes (consume Escape only; other keys propagate so
            -- chat/UI shortcuts keep working behind the dimmer).
            panel:EnableKeyboard(true)
            panel:SetScript("OnKeyDown", function(self, key)
                self:SetPropagateKeyboardInput(key ~= "ESCAPE")
                if key == "ESCAPE" then ClosePopup() end
            end)

            -- X close (standard popup chrome: borderless eui-close, top right)
            local closeBtn = CreateFrame("Button", nil, panel)
            closeBtn:SetSize(19, 19)
            closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -10)
            local closeTex = closeBtn:CreateTexture(nil, "OVERLAY")
            closeTex:SetAllPoints()
            closeTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
            closeBtn:SetAlpha(0.5)
            closeBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
            closeBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
            closeBtn:SetScript("OnClick", ClosePopup)

            -- LEFT: Show All Debuffs (checkbox-dropdown box visuals)
            local tog = CreateFrame("Button", nil, panel)
            tog:SetSize(170, 20)
            tog:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -68)
            local box = CreateFrame("Frame", nil, tog)
            box:SetSize(16, 16); box:SetPoint("LEFT", tog, "LEFT", 0, 0)
            local bbg = box:CreateTexture(nil, "BACKGROUND")
            bbg:SetAllPoints(); bbg:SetColorTexture(0.12, 0.12, 0.14, 1)
            local bbrd = EllesmereUI.MakeBorder(box, 0.4, 0.4, 0.4, 0.6, PP)
            local chk = box:CreateTexture(nil, "ARTWORK")
            PP.SetInside(chk, box, 2, 2)
            chk:SetColorTexture(EllesmereUI.ELLESMERE_GREEN.r, EllesmereUI.ELLESMERE_GREEN.g,
                EllesmereUI.ELLESMERE_GREEN.b, 1)
            local tl = tog:CreateFontString(nil, "OVERLAY")
            tl:SetFont(fp2, 13, "")
            tl:SetPoint("LEFT", box, "RIGHT", 8, 0)
            tl:SetTextColor(0.85, 0.85, 0.85)
            tl:SetText(EllesmereUI.L("Show All Debuffs"))

            -- RIGHT: filter categories (RF debuff set)
            local dd = EllesmereUI.BuildVisOptsCBDropdown(panel, 170, panel:GetFrameLevel() + 3,
                NPF_CAT_ITEMS,
                function(k) return (cfg.f or {})[k] == true end,
                function(k, v)
                    cfg.f = cfg.f or {}
                    cfg.f[k] = v or nil
                    if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
                end,
                nil, 10, false)
            dd:ClearAllPoints()
            dd:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, -63)

            local function UpdAll()
                chk:SetShown(cfg.all == true)
                if bbrd and bbrd.SetColor then
                    if cfg.all then
                        bbrd:SetColor(EllesmereUI.ELLESMERE_GREEN.r, EllesmereUI.ELLESMERE_GREEN.g,
                            EllesmereUI.ELLESMERE_GREEN.b, 0.8)
                    else
                        bbrd:SetColor(0.4, 0.4, 0.4, 0.6)
                    end
                end
                -- Filters are inert while Show All is on (DM parity).
                dd:SetAlpha(cfg.all and 0.4 or 1)
                dd:EnableMouse(not cfg.all)
            end
            tog:SetScript("OnClick", function()
                cfg.all = not cfg.all
                UpdAll()
                if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
            end)
            UpdAll()

            -- BLACKLIST: the shared exclude list (all three kinds; real
            -- engine excludeSpellIDs on every debuff-side group). Add via
            -- spell ID; rows are name-sorted with a remove X.
            local div = panel:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1)
            div:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -104)
            div:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -20, -104)
            div:SetColorTexture(1, 1, 1, 0.08)

            -- Section label (options-page section style: small gray caps).
            local exTitle = panel:CreateFontString(nil, "OVERLAY")
            exTitle:SetFont(fp2, 11, "")
            exTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -120)
            exTitle:SetTextColor(1, 1, 1, 0.45)
            exTitle:SetText(EllesmereUI.L("EXCLUDED DEBUFFS"))

            -- Add Spell ID: the announcement popup's bordered accent button,
            -- secondary weight (dim border that brightens on hover).
            local addBtn = CreateFrame("Button", nil, panel)
            addBtn:SetSize(110, 26)
            addBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, -112)
            local abg = addBtn:CreateTexture(nil, "BACKGROUND")
            abg:SetAllPoints(); abg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
            local abrd = EllesmereUI.MakeBorder and EllesmereUI.MakeBorder(addBtn, EG.r, EG.g, EG.b, 0.35, PP)
            local al = addBtn:CreateFontString(nil, "OVERLAY")
            al:SetFont(fp2, 12, "")
            al:SetPoint("CENTER")
            al:SetTextColor(EG.r, EG.g, EG.b, 0.7)
            al:SetText(EllesmereUI.L("Add Spell ID"))
            addBtn:SetScript("OnEnter", function()
                al:SetTextColor(EG.r, EG.g, EG.b, 1)
                if abrd and abrd.SetColor then abrd:SetColor(EG.r, EG.g, EG.b, 0.8) end
            end)
            addBtn:SetScript("OnLeave", function()
                al:SetTextColor(EG.r, EG.g, EG.b, 0.7)
                if abrd and abrd.SetColor then abrd:SetColor(EG.r, EG.g, EG.b, 0.35) end
            end)

            local scroll = CreateFrame("ScrollFrame", nil, panel)
            scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -148)
            scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 62)
            local child = CreateFrame("Frame", nil, scroll)
            child:SetWidth(392)
            scroll:SetScrollChild(child)
            scroll:EnableMouseWheel(true)
            scroll:SetScript("OnMouseWheel", function(self, delta)
                local maxS = math.max(0, child:GetHeight() - self:GetHeight())
                local cur = self:GetVerticalScroll() - delta * 30
                if cur < 0 then cur = 0 elseif cur > maxS then cur = maxS end
                self:SetVerticalScroll(cur)
            end)

            -- Exclude rows: checkbox (enable/disable the entry without
            -- deleting it) + spell icon + name with the spell ID in gray
            -- parentheses + delete X. Disabled entries stay stored (false)
            -- and dim the whole row; only true entries reach the engine.
            local exRows = {}
            local function RefreshList()
                for i = 1, #exRows do exRows[i]:Hide() end
                local ex = (ns.NPF_Exclude and ns.NPF_Exclude()) or {}
                local sorted = {}
                for id, v in pairs(ex) do
                    local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                    sorted[#sorted + 1] = { id = id, on = v == true, name = nm or tostring(id) }
                end
                table.sort(sorted, function(a, b) return a.name < b.name end)
                for i = 1, #sorted do
                    local row = exRows[i]
                    if not row then
                        row = CreateFrame("Button", nil, child)
                        row:SetSize(392, 28)
                        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * 29)
                        row.hl = row:CreateTexture(nil, "BACKGROUND")
                        row.hl:SetAllPoints()
                        row.hl:SetColorTexture(1, 1, 1, 0)
                        -- Checkbox (checkbox-dropdown visuals)
                        row.box = CreateFrame("Frame", nil, row)
                        row.box:SetSize(16, 16)
                        row.box:SetPoint("LEFT", row, "LEFT", 2, 0)
                        local bxbg = row.box:CreateTexture(nil, "BACKGROUND")
                        bxbg:SetAllPoints(); bxbg:SetColorTexture(0.12, 0.12, 0.14, 1)
                        row.boxBrd = EllesmereUI.MakeBorder(row.box, 0.4, 0.4, 0.4, 0.6, PP)
                        row.chk = row.box:CreateTexture(nil, "ARTWORK")
                        PP.SetInside(row.chk, row.box, 2, 2)
                        row.chk:SetColorTexture(EG.r, EG.g, EG.b, 1)
                        row.icon = row:CreateTexture(nil, "ARTWORK")
                        row.icon:SetSize(20, 20)
                        row.icon:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
                        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        row.name = row:CreateFontString(nil, "OVERLAY")
                        row.name:SetFont(fp2, 13, "")
                        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
                        row.name:SetPoint("RIGHT", row, "RIGHT", -32, 0)
                        row.name:SetJustifyH("LEFT")
                        row.name:SetWordWrap(false)
                        row.x = CreateFrame("Button", nil, row)
                        row.x:SetSize(14, 14)
                        row.x:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                        row.x:SetFrameLevel(row:GetFrameLevel() + 2)
                        row.x.tex = row.x:CreateTexture(nil, "OVERLAY")
                        row.x.tex:SetAllPoints()
                        row.x.tex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
                        row.x:SetAlpha(0.5)
                        row.x:SetScript("OnEnter", function(self)
                            self:SetAlpha(0.9)
                            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Remove"))
                        end)
                        row.x:SetScript("OnLeave", function(self)
                            self:SetAlpha(0.5)
                            EllesmereUI.HideWidgetTooltip()
                        end)
                        row:SetScript("OnEnter", function(self) self.hl:SetColorTexture(1, 1, 1, 0.04) end)
                        row:SetScript("OnLeave", function(self) self.hl:SetColorTexture(1, 1, 1, 0) end)
                        exRows[i] = row
                    end
                    local entry = sorted[i]
                    row._id = entry.id
                    local tex = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.id)
                    row.icon:SetTexture(tex or 134400)
                    row.name:SetText(entry.name .. " |cff808080(" .. entry.id .. ")|r")
                    -- Checked = actively excluded; unchecked entries dim.
                    row.chk:SetShown(entry.on)
                    if row.boxBrd and row.boxBrd.SetColor then
                        if entry.on then
                            row.boxBrd:SetColor(EG.r, EG.g, EG.b, 0.8)
                        else
                            row.boxBrd:SetColor(0.4, 0.4, 0.4, 0.6)
                        end
                    end
                    row.icon:SetDesaturated(not entry.on)
                    row.icon:SetAlpha(entry.on and 1 or 0.45)
                    row.name:SetAlpha(entry.on and 0.9 or 0.45)
                    row:SetScript("OnClick", function()
                        local ex2 = ns.NPF_Exclude and ns.NPF_Exclude()
                        if ex2 then
                            ex2[row._id] = not (ex2[row._id] == true)
                            if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
                            RefreshList()
                        end
                    end)
                    row.x:SetScript("OnClick", function()
                        local ex2 = ns.NPF_Exclude and ns.NPF_Exclude()
                        if ex2 then ex2[row._id] = nil end
                        if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
                        RefreshList()
                    end)
                    row:Show()
                end
                child:SetHeight(math.max(1, #sorted * 29))
            end
            addBtn:SetScript("OnClick", function()
                EllesmereUI:ShowInputPopup({
                    title = EllesmereUI.L("Add Spell ID"),
                    message = EllesmereUI.L("Enter the spell ID to exclude from nameplates."),
                    confirmText = EllesmereUI.L("Add"),
                    cancelText = EllesmereUI.L("Cancel"),
                    onConfirm = function(text)
                        local id = tonumber(text or "")
                        local ex2 = id and ns.NPF_Exclude and ns.NPF_Exclude()
                        if ex2 then
                            ex2[id] = true
                            if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
                            RefreshList()
                        end
                    end,
                })
            end)

            -- Done (standard popup button chrome: dark fill, subtle border,
            -- brighten on hover). Everything applies live, so Done = close.
            -- Done: the announcement popup's primary action button (green
            -- border and label, brighten on hover).
            local doneBtn = CreateFrame("Button", nil, panel)
            doneBtn:SetSize(150, 32)
            doneBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 14)
            local dbg2 = doneBtn:CreateTexture(nil, "BACKGROUND")
            dbg2:SetAllPoints(); dbg2:SetColorTexture(0.06, 0.08, 0.10, 0.92)
            local dbrd = EllesmereUI.MakeBorder and EllesmereUI.MakeBorder(doneBtn, EG.r, EG.g, EG.b, 0.9, PP)
            local dl2 = doneBtn:CreateFontString(nil, "OVERLAY")
            dl2:SetFont(fp2, 14, "")
            dl2:SetPoint("CENTER")
            dl2:SetTextColor(EG.r, EG.g, EG.b, 0.9)
            dl2:SetText(EllesmereUI.L("Done"))
            doneBtn:SetScript("OnEnter", function()
                dl2:SetTextColor(EG.r, EG.g, EG.b, 1)
                if dbrd and dbrd.SetColor then dbrd:SetColor(EG.r, EG.g, EG.b, 1) end
            end)
            doneBtn:SetScript("OnLeave", function()
                dl2:SetTextColor(EG.r, EG.g, EG.b, 0.9)
                if dbrd and dbrd.SetColor then dbrd:SetColor(EG.r, EG.g, EG.b, 0.9) end
            end)
            doneBtn:SetScript("OnClick", ClosePopup)

            RefreshList()
        end

        local function MakeCogIcon(row, regionKey, posKey, slotLabel)
            local rgn = row[regionKey]
            local btn = CreateFrame("Button", nil, rgn)
            btn:SetSize(26, 26)
            btn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
            rgn._lastInline = btn
            btn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            btn:SetAlpha(0.4)
            local tex = btn:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints()
            tex:SetTexture(EllesmereUI.RESIZE_ICON)
            btn:SetScript("OnEnter", function(self)
                if CorePosOffDisabled(posKey) then
                    EllesmereUI.ShowWidgetTooltip(self, DISABLED_TIP)
                else
                    self:SetAlpha(0.7)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                if cogPopupOwner ~= self then self:SetAlpha(CorePosOffDisabled(posKey) and 0.15 or 0.4) end
            end)
            btn:SetScript("OnClick", function(self)
                if CorePosOffDisabled(posKey) then return end
                local sizeKey = posKey .. "SlotSize"
                local growthKey = posKey .. "SlotGrowth"
                local growthValues
                if posKey == "topleft" then
                    growthValues = {
                        { value = "left",  label = "Left"  },
                        { value = "right", label = "Right" },
                        { value = "up",    label = "Up"    },
                    }
                elseif posKey == "topright" then
                    growthValues = {
                        { value = "right", label = "Right" },
                        { value = "left",  label = "Left"  },
                        { value = "up",    label = "Up"    },
                    }
                end
                local opts = {
                    title = EllesmereUI.Lf("%1$s Slot Settings", EllesmereUI.L(slotLabel)),
                    xGet = function() return CorePosXGet(posKey) end,
                    xSet = function(v) CorePosXSet(posKey, v) end,
                    yGet = function() return CorePosYGet(posKey) end,
                    ySet = function(v) CorePosYSet(posKey, v) end,
                    sizeGet = function() return DBVal(sizeKey) or defaults[sizeKey] end,
                    sizeSet = function(v) DB()[sizeKey] = v; RefreshAllSlots(); UpdatePreview() end,
                    sizeMin = 10, sizeMax = 50,
                    sizeFirst = true,
                }
                if growthValues then
                    opts.growthGet    = function() return DBVal(growthKey) or defaults[growthKey] end
                    opts.growthSet    = function(v) DB()[growthKey] = v; RefreshAllSlots(); UpdatePreview() end
                    opts.growthValues = growthValues
                end
                -- Spacing + Cropped Icons: only for multi-icon aura elements
                -- (debuffs/buffs/CCs). Both map the slot's currently assigned
                -- element to its per-element key.
                local element = GetElementAtPosition(posKey)
                local spacingKey, cropKey
                if element == "debuffs" then
                    spacingKey = "debuffSpacing"; cropKey = "debuffCropIcons"
                elseif element == "buffs" then
                    spacingKey = "buffSpacing"; cropKey = "buffCropIcons"
                elseif element == "ccs" then
                    spacingKey = "ccSpacing"; cropKey = "ccCropIcons"
                end
                if spacingKey then
                    opts.spacingGet = function() return DBVal(spacingKey) or defaults[spacingKey] end
                    opts.spacingSet = function(v) DB()[spacingKey] = v; RefreshAllSlots(); UpdatePreview() end
                end
                if cropKey then
                    opts.cropGet = function() return DBVal(cropKey) or defaults[cropKey] end
                    opts.cropSet = function(v) DB()[cropKey] = v; RefreshAllSlots(); UpdatePreview() end
                end
                -- Rare/Quest Indicator: "Show In Instances" lifts the
                -- open-world-only gates (UpdateClassification render gate +
                -- IsQuestMob's tooltip-scan gate). RefreshQuestObjective wipes
                -- the quest-mob caches AND re-runs UpdateClassification on
                -- every plate, so the toggle applies immediately both ways.
                if element == "classification" then
                    opts.toggleLabel = "Show In Instances"
                    opts.toggleGet = function() return DBVal("classificationShowInInstances") == true end
                    opts.toggleSet = function(v)
                        DB().classificationShowInInstances = v and true or false
                        if ns.RefreshQuestObjective then ns.RefreshQuestObjective() end
                        UpdatePreview()
                    end
                end
                -- Raise Strata: bumps whatever element occupies this slot one
                -- strata level up so it renders above the rest of the plate.
                local rsKey = posKey .. "SlotRaiseStrata"
                opts.raiseStrataGet = function() return DBVal(rsKey) and true or false end
                opts.raiseStrataSet = function(v) DB()[rsKey] = v and true or false; RefreshAllSlots(); UpdatePreview() end
                ShowCogPopup(self, opts)
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = CorePosOffDisabled(posKey)
                btn:SetAlpha(off and 0.15 or (cogPopupOwner == btn and 0.7 or 0.4))
            end)
            if CorePosOffDisabled(posKey) then btn:SetAlpha(0.15) end

            -- Edit Filters (12.1 slot filters): accent link left of the cog
            -- whenever this row holds a debuff-side aura element; opens the
            -- per-kind filter popup. Refreshes on the same widget-refresh
            -- channel as the cog alpha.
            if EllesmereUI.IS_121 then
                local link = CreateFrame("Button", nil, rgn)
                link:SetFrameLevel(rgn:GetFrameLevel() + 5)
                local lfp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("nameplates")) or DBVal("font")
                local lfs = link:CreateFontString(nil, "OVERLAY")
                lfs:SetFont(lfp, 12, "")
                local ar, ag, ab = 1, 0.82, 0.30
                if EllesmereUI.GetAccentColor then ar, ag, ab = EllesmereUI.GetAccentColor() end
                lfs:SetTextColor(ar, ag, ab)
                lfs:SetAlpha(0.85)
                lfs:SetPoint("CENTER")
                lfs:SetText(EllesmereUI.L("Edit Filters"))
                link:SetSize(lfs:GetStringWidth() + 6, 16)
                link:SetPoint("RIGHT", btn, "LEFT", -6, 0)
                rgn._lastInline = link
                local function LinkKind()
                    local el = GetElementAtPosition(posKey)
                    if el == "debuffs" then return "debuffs"
                    elseif el == "ccs" then return "cc"
                    elseif el == "debuffsccs" then return "dcc" end
                end
                local function UpdLink()
                    link:SetShown(LinkKind() ~= nil)
                end
                link:SetScript("OnEnter", function() lfs:SetAlpha(1) end)
                link:SetScript("OnLeave", function() lfs:SetAlpha(0.85) end)
                link:SetScript("OnClick", function()
                    local k = LinkKind()
                    if k and ns.NPP_ShowFilterPopup then ns.NPP_ShowFilterPopup(k) end
                end)
                EllesmereUI.RegisterWidgetRefresh(UpdLink)
                UpdLink()
            end
            return btn
        end

        parent._showRowDivider = true

        -- Row 1: Top | Right
        coreRow1, h = W:DualRow(parent, y,
            { type="dropdown", text="Top",
              values = coreElementValues, order = coreElementOrder,
              getValue = function() return GetElementAtPosition("top") end,
              setValue = function(v) SetElementAtPosition("top", v); RefreshAllSlots(); RefreshCoreEyes() end,
              disabled = function() return CorePosOffDisabled("top") end,
              disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
              labelOnlyDisabled = true },
            { type="dropdown", text="Right",
              values = coreElementValues, order = coreElementOrder,
              getValue = function() return GetElementAtPosition("right") end,
              setValue = function(v) SetElementAtPosition("right", v); RefreshAllSlots(); RefreshCoreEyes() end,
              disabled = function() return CorePosOffDisabled("right") end,
              disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
              labelOnlyDisabled = true });  y = y - h
        MakeCogIcon(coreRow1, "_leftRegion",  "top",      "Top")
        MakeCogIcon(coreRow1, "_rightRegion", "right",    "Right")

        -- Row 2: Left | Top Right
        coreRow2, h = W:DualRow(parent, y,
            { type="dropdown", text="Left",
              values = coreElementValues, order = coreElementOrder,
              getValue = function() return GetElementAtPosition("left") end,
              setValue = function(v) SetElementAtPosition("left", v); RefreshAllSlots(); RefreshCoreEyes() end,
              disabled = function() return CorePosOffDisabled("left") end,
              disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
              labelOnlyDisabled = true },
            { type="dropdown", text="Top Right",
              values = coreElementValues, order = coreElementOrder,
              getValue = function() return GetElementAtPosition("topright") end,
              setValue = function(v) SetElementAtPosition("topright", v); RefreshAllSlots(); RefreshCoreEyes() end,
              disabled = function() return CorePosOffDisabled("topright") end,
              disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
              labelOnlyDisabled = true });  y = y - h
        MakeCogIcon(coreRow2, "_leftRegion",  "left",     "Left")
        MakeCogIcon(coreRow2, "_rightRegion", "topright", "Top Right")

        -- Row 3: Top Left | Bottom
        coreRow3, h = W:DualRow(parent, y,
            { type="dropdown", text="Top Left",
              values = coreElementValues, order = coreElementOrder,
              getValue = function() return GetElementAtPosition("topleft") end,
              setValue = function(v) SetElementAtPosition("topleft", v); RefreshAllSlots(); RefreshCoreEyes() end,
              disabled = function() return CorePosOffDisabled("topleft") end,
              disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
              labelOnlyDisabled = true },
            { type="dropdown", text="Bottom",
              values = coreElementValues, order = coreElementOrder,
              getValue = function() return GetElementAtPosition("bottom") end,
              setValue = function(v) SetElementAtPosition("bottom", v); RefreshAllSlots(); RefreshCoreEyes() end,
              disabled = function() return CorePosOffDisabled("bottom") end,
              disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
              labelOnlyDisabled = true });  y = y - h
        MakeCogIcon(coreRow3, "_leftRegion", "topleft", "Top Left")
        MakeCogIcon(coreRow3, "_rightRegion", "bottom", "Bottom")

        -- Map each position to { row, regionKey } for eye icon anchoring
        local posToRegion = {
            top      = { coreRow1, "_leftRegion" },
            right    = { coreRow1, "_rightRegion" },
            left     = { coreRow2, "_leftRegion" },
            topright = { coreRow2, "_rightRegion" },
            topleft  = { coreRow3, "_leftRegion" },
            bottom   = { coreRow3, "_rightRegion" },
        }

        -- Eye icon that follows whichever Core Positions dropdown has "Raid Marker"
        do
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
            local eyeBtn = CreateFrame("Button", nil, parent)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetFrameLevel(parent:GetFrameLevel() + 10)
            eyeBtn:SetAlpha(0.4)
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function RefreshIcon()
                eyeTex:SetTexture(showRaidMarkerPreview and EYE_INVISIBLE or EYE_VISIBLE)
            end
            RefreshIcon()
            eyeBtn:SetScript("OnClick", function()
                showRaidMarkerPreview = not showRaidMarkerPreview
                RefreshIcon()
                UpdatePreview()
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, "Show/Hide on Preview", { width = 155 })
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                self:SetAlpha(0.4)
                EllesmereUI.HideWidgetTooltip()
            end)
            _refreshRaidMarkerEyePos = function()
                local rmPos = DBVal("raidMarkerPos") or defaults.raidMarkerPos
                local info = posToRegion[rmPos]
                if not info or rmPos == "none" then
                    eyeBtn:Hide()
                    return
                end
                local rgn = info[1][info[2]]
                eyeBtn:ClearAllPoints()
                eyeBtn:SetParent(rgn)
                -- Anchor next to the cog icon
                eyeBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                eyeBtn:Show()
            end
            _refreshRaidMarkerEyePos()
        end

        -- Eye icon that follows whichever Core Positions dropdown has "Rare/Quest Indicator"
        do
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
            local eyeBtn = CreateFrame("Button", nil, parent)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetFrameLevel(parent:GetFrameLevel() + 10)
            eyeBtn:SetAlpha(0.4)
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function RefreshIcon()
                eyeTex:SetTexture(showClassificationPreview and EYE_INVISIBLE or EYE_VISIBLE)
            end
            RefreshIcon()
            eyeBtn:SetScript("OnClick", function()
                showClassificationPreview = not showClassificationPreview
                RefreshIcon()
                UpdatePreview()
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, "Show/Hide on Preview", { width = 155 })
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                self:SetAlpha(0.4)
                EllesmereUI.HideWidgetTooltip()
            end)
            _refreshClassificationEyePos = function()
                local clPos = DBVal("classificationSlot") or defaults.classificationSlot
                local info = posToRegion[clPos]
                if not info or clPos == "none" then
                    eyeBtn:Hide()
                    return
                end
                local rgn = info[1][info[2]]
                eyeBtn:ClearAllPoints()
                eyeBtn:SetParent(rgn)
                -- Anchor next to the cog icon
                eyeBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                eyeBtn:Show()
            end
            _refreshClassificationEyePos()
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  CORE TEXT POSITIONS
        -----------------------------------------------------------------------
        local coreTextHeader
        coreTextHeader, h = W:SectionHeader(parent, "CORE TEXT POSITIONS", y);  y = y - h

        -- Subtitle hint next to the section header (same style as Core Positions)
        do
            local regions = { coreTextHeader:GetRegions() }
            for _, rgn in ipairs(regions) do
                if rgn:IsObjectType("FontString") and EllesmereUI.EnKey(rgn:GetText()) == "CORE TEXT POSITIONS" then
                    local sub = coreTextHeader:CreateFontString(nil, "OVERLAY")
                    sub:SetFont(rgn:GetFont())
                    sub:SetTextColor(1, 1, 1, 0.25)
                    sub:SetText(EllesmereUI.L("(one per slot)"))
                    sub:SetPoint("LEFT", rgn, "RIGHT", 6, 0)
                    break
                end
            end
        end

        local textElementValues = {
            enemyName            = "Enemy Name",
            healthPercent        = "Health %",
            healthPercentNoSign  = "Health % (No Sign)",
            healthNumber         = "Health #",
            healthPctNum         = "Health % | #",
            healthNumPct         = "Health # | %",
            healthPctNumDash     = "Health % - #",
            healthNumPctDash     = "Health # - %",
            none                 = "None",
        }
        local textElementOrder = { "none", "---", "enemyName", "healthPercent", "healthPercentNoSign", "healthNumber", "healthPctNum", "healthNumPct", "healthPctNumDash", "healthNumPctDash" }

        local function TextSlotSetValue(slotKey, v)
            SetTextElementAtSlot(slotKey, v)
            ns.RefreshAllSettings()
            UpdatePreview(); EllesmereUI:RefreshPage()
        end

        local function TextOffsetRefresh()
            ns.RefreshAllSettings()
            UpdatePreview()
        end

        -- Text slot X/Y offset helpers (parallel to CorePosXGet etc.)
        local function TextPosXGet(slotKey)
            return DBVal(slotKey .. "XOffset") or 0
        end
        local function TextPosYGet(slotKey)
            return DBVal(slotKey .. "YOffset") or 0
        end
        local function TextPosXSet(slotKey, v)
            DB()[slotKey .. "XOffset"] = v; TextOffsetRefresh()
        end
        local function TextPosYSet(slotKey, v)
            DB()[slotKey .. "YOffset"] = v; TextOffsetRefresh()
        end
        local function TextPosDisabled(slotKey)
            return DBVal(slotKey) == "none"
        end

        local TEXT_DISABLED_TIP = "This option requires a text to be assigned"

        local function MakeTextCogIcon(row, regionKey, slotKey, slotLabel)
            local rgn = row[regionKey]
            local btn = CreateFrame("Button", nil, rgn)
            btn:SetSize(26, 26)
            btn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -9, 0)
            rgn._lastInline = btn
            btn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            btn:SetAlpha(0.4)
            local tex = btn:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints()
            tex:SetTexture(EllesmereUI.RESIZE_ICON)
            btn:SetScript("OnEnter", function(self)
                if TextPosDisabled(slotKey) then
                    EllesmereUI.ShowWidgetTooltip(self, TEXT_DISABLED_TIP)
                else
                    self:SetAlpha(0.7)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                if cogPopupOwner ~= self then self:SetAlpha(TextPosDisabled(slotKey) and 0.15 or 0.4) end
            end)
            btn:SetScript("OnClick", function(self)
                if TextPosDisabled(slotKey) then return end
                local sizeKey = slotKey .. "Size"
                local cogOpts = {
                    title = EllesmereUI.Lf("%1$s Settings", EllesmereUI.L(slotLabel)),
                    xGet = function() return TextPosXGet(slotKey) end,
                    xSet = function(v) TextPosXSet(slotKey, v) end,
                    yGet = function() return TextPosYGet(slotKey) end,
                    ySet = function(v) TextPosYSet(slotKey, v) end,
                    sizeGet = function() return DBVal(sizeKey) or defaults[sizeKey] end,
                    sizeSet = function(v) DB()[sizeKey] = v; TextOffsetRefresh() end,
                    sizeMin = 6, sizeMax = 30,
                    sizeLabel = "Size",
                    sizeFirst = true,
                }
                -- Both name and health text in this slot get Width % + Wrap (on the
                -- dedicated Wrap row). Enemy name uses the GLOBAL enemyName keys (one
                -- slot holds the name at a time) and its width % scales the computed
                -- width. Health text uses PER-SLOT keys, width % is of the health bar
                -- (default 100 = no clip), and it keeps the "Show % Decimal" toggle.
                if DBVal(slotKey) == "enemyName" then
                    cogOpts.widthGet = function() return DBVal("enemyNameWidthPct") or defaults.enemyNameWidthPct end
                    cogOpts.widthSet = function(v) DB().enemyNameWidthPct = v; ns.RefreshAllSettings(); UpdatePreview() end
                    cogOpts.wrapGet = function() return DBVal("enemyNameWrap") == true end
                    cogOpts.wrapSet = function(v) DB().enemyNameWrap = v; ns.RefreshAllSettings(); UpdatePreview() end
                else
                    local widthKey = slotKey .. "WidthPct"
                    local wrapKey = slotKey .. "Wrap"
                    cogOpts.widthGet = function() return DBVal(widthKey) or 100 end
                    cogOpts.widthSet = function(v) DB()[widthKey] = v; ns.RefreshAllSettings(); UpdatePreview() end
                    cogOpts.wrapGet = function() return DBVal(wrapKey) == true end
                    cogOpts.wrapSet = function(v) DB()[wrapKey] = v; ns.RefreshAllSettings(); UpdatePreview() end
                    cogOpts.toggleLabel = "Show % Decimal"
                    cogOpts.toggleGet = function() return DBVal(slotKey .. "PctDecimal") == true end
                    cogOpts.toggleSet = function(v)
                        DB()[slotKey .. "PctDecimal"] = v
                        ns.RefreshAllSettings()
                        UpdatePreview()
                    end
                end
                ShowCogPopup(self, cogOpts)
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = TextPosDisabled(slotKey)
                btn:SetAlpha(off and 0.15 or (cogPopupOwner == btn and 0.7 or 0.4))
            end)
            if TextPosDisabled(slotKey) then btn:SetAlpha(0.15) end
            return btn
        end

        parent._showRowDivider = true

        local function MakeTextColorSwatch(row, regionKey, slotKey)
            local rgn = row[regionKey]
            local colorKey = slotKey .. "Color"
            local function getColor()
                local c = (DB() and DB()[colorKey]) or defaults[colorKey]
                return c.r, c.g, c.b
            end
            local function setColor(r, g, b)
                DB()[colorKey] = { r = r, g = g, b = b }
                ns.RefreshAllSettings()
                UpdatePreview()
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, getColor, setColor, nil, 20)
            PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -12, 0)
            rgn._lastInline = swatch
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = TextPosDisabled(slotKey)
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            local off = TextPosDisabled(slotKey)
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            return swatch
        end

        local textRow1, textRow2

        -- Row 1: Top Text | Right Text
        textRow1, h = W:DualRow(parent, y,
            { type="dropdown", text="Top Text", values=textElementValues,
              getValue=function() return DBVal("textSlotTop") end,
              setValue=function(v) TextSlotSetValue("textSlotTop", v) end,
              order=textElementOrder,
              disabled=function() return DBVal("textSlotTop") == "none" end,
              disabledTooltip="This option requires a text to be assigned", rawTooltip=true,
              labelOnlyDisabled=true },
            { type="dropdown", text="Right Text", values=textElementValues,
              getValue=function() return DBVal("textSlotRight") end,
              setValue=function(v) TextSlotSetValue("textSlotRight", v) end,
              order=textElementOrder,
              disabled=function() return DBVal("textSlotRight") == "none" end,
              disabledTooltip="This option requires a text to be assigned", rawTooltip=true,
              labelOnlyDisabled=true,
              disabledValues=function(k) if ns.IsComboHealthText(k) and DBVal("textSlotCenter") == "enemyName" then return "Disabled when Enemy Name is centered on the health bar due to overlapping text" end end });  y = y - h
        MakeTextColorSwatch(textRow1, "_leftRegion",  "textSlotTop")
        MakeTextCogIcon(textRow1, "_leftRegion",  "textSlotTop",   "Top Text")
        MakeTextColorSwatch(textRow1, "_rightRegion", "textSlotRight")
        MakeTextCogIcon(textRow1, "_rightRegion", "textSlotRight", "Right Text")

        -- Row 2: Left Text | Center Text
        textRow2, h = W:DualRow(parent, y,
            { type="dropdown", text="Left Text", values=textElementValues,
              getValue=function() return DBVal("textSlotLeft") end,
              setValue=function(v) TextSlotSetValue("textSlotLeft", v) end,
              order=textElementOrder,
              disabled=function() return DBVal("textSlotLeft") == "none" end,
              disabledTooltip="This option requires a text to be assigned", rawTooltip=true,
              labelOnlyDisabled=true,
              disabledValues=function(k) if ns.IsComboHealthText(k) and DBVal("textSlotCenter") == "enemyName" then return "Disabled when Enemy Name is centered on the health bar due to overlapping text" end end },
            { type="dropdown", text="Center Text", values=textElementValues,
              getValue=function() return DBVal("textSlotCenter") end,
              setValue=function(v) TextSlotSetValue("textSlotCenter", v) end,
              order=textElementOrder,
              disabled=function() return DBVal("textSlotCenter") == "none" end,
              disabledTooltip="This option requires a text to be assigned", rawTooltip=true,
              labelOnlyDisabled=true });  y = y - h
        MakeTextColorSwatch(textRow2, "_leftRegion",  "textSlotLeft")
        MakeTextCogIcon(textRow2, "_leftRegion",  "textSlotLeft",   "Left Text")
        MakeTextColorSwatch(textRow2, "_rightRegion", "textSlotCenter")
        MakeTextCogIcon(textRow2, "_rightRegion", "textSlotCenter", "Center Text")

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  HEALTH BAR
        -----------------------------------------------------------------------
        local healthBarHeader
        healthBarHeader, h = W:SectionHeader(parent, "HEALTH AND CAST BAR", y);  y = y - h

        local healthBarHeightRow
        healthBarHeightRow, h = W:DualRow(parent, y,
            { type="slider", text="Health Bar Width", min=100, max=BAR_W+100, step=1,
              getValue=function() return BAR_W + DBVal("healthBarWidth") end,
              setValue=function(v)
                local extra = v - BAR_W
                DB().healthBarWidth = extra
                for _, plate in pairs(plates) do
                    PP.Width(plate.health, v)
                    PP.Width(plate.absorb, v)
                    PP.Width(plate.cast, v)
                    plate:UpdateNameWidth()
                end
                if ns.ApplyNamePlateClickArea then ns.ApplyNamePlateClickArea() end
                UpdatePreview()
              end },
            { type="slider", text="Health Bar Height", min=6, max=50, step=1,
              getValue=function() return DBVal("healthBarHeight") end,
              setValue=function(v)
                DB().healthBarHeight = v
                for _, plate in pairs(plates) do PP.Height(plate.health, v) end
                if ns.ApplyNamePlateClickArea then ns.ApplyNamePlateClickArea() end
                UpdatePreview()
              end });  y = y - h

        local function castIconOff() return DB() and DB().showCastIcon == false end

        local castBarHeightRow
        castBarHeightRow, h = W:DualRow(parent, y,
            { type="slider", text="Cast Bar Height", min=10, max=40, step=1,
              getValue=function() return DBVal("castBarHeight") or defaults.castBarHeight end,
              setValue=function(v)
                DB().castBarHeight = v
                local barW = ns.GetHealthBarWidth()
                for _, plate in pairs(plates) do
                    ns.LayoutCastBar(plate, barW, v)
                    ns.LayoutCastIcon(plate, v)
                    plate.castSpark:SetHeight(v)
                end
                UpdatePreview()
              end },
            { type="toggle", text="Spell Icon",
              getValue=function()
                local db = DB()
                if db and db.showCastIcon ~= nil then return db.showCastIcon end
                return defaults.showCastIcon
              end,
              setValue=function(v)
                DB().showCastIcon = v
                ns.RefreshAllSettings()
                UpdatePreview()
                EllesmereUI:RefreshPage()
              end });  y = y - h
        local showCastIconRow = castBarHeightRow

        -- Inline cog on Spell Icon (right region) for Scale
        do
            local rightRgn = castBarHeightRow._rightRegion
            local _, spellIconCogShow = EllesmereUI.BuildCogPopup({
                title = "Spell Icon Settings",
                rows = {
                    { type="slider", label="Scale", min=0.5, max=2, step=0.1,
                      get=function() return DBVal("castIconScale") or defaults.castIconScale end,
                      set=function(v)
                        DB().castIconScale = v
                        if not (DB() and DB().castIconFullSize) then
                            for _, plate in pairs(plates) do
                                plate.castIconFrame:SetScale(v)
                            end
                        end
                        UpdatePreview()
                      end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return DBVal("castIconOffsetX") or defaults.castIconOffsetX or 0 end,
                      set=function(v)
                        DB().castIconOffsetX = v
                        ns.RefreshAllSettings()
                        UpdatePreview()
                      end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() return DBVal("castIconOffsetY") or defaults.castIconOffsetY or 0 end,
                      set=function(v)
                        DB().castIconOffsetY = v
                        ns.RefreshAllSettings()
                        UpdatePreview()
                      end },
                    { type="toggle", label="Make Icon Part of the Bar",
                      tooltip="This makes it so the width of the cast bar includes the icon, rather than placing it to the left of the cast bars width.",
                      get=function()
                        local db = DB()
                        if db and db.castbarIconInWidth ~= nil then return db.castbarIconInWidth end
                        return defaults.castbarIconInWidth
                      end,
                      set=function(v)
                        DB().castbarIconInWidth = v
                        ns.RefreshAllSettings()
                        UpdatePreview()
                      end },
                    { type="toggle", label="Icon on Right",
                      tooltip="Place the cast bar spell icon on the right side of the bars instead of the left.",
                      get=function()
                        local db = DB()
                        if db and db.castIconOnRight ~= nil then return db.castIconOnRight end
                        return defaults.castIconOnRight
                      end,
                      set=function(v)
                        DB().castIconOnRight = v
                        ns.RefreshAllSettings()
                        UpdatePreview()
                      end },
                    { type="toggle", label="Full Sized (Health + Cast Bar)",
                      tooltip="Make the spell icon a large square the combined height of the health bar plus the cast bar, flush with the top of the health bar and the bottom of the cast bar.",
                      get=function()
                        local db = DB()
                        if db and db.castIconFullSize ~= nil then return db.castIconFullSize end
                        return defaults.castIconFullSize
                      end,
                      set=function(v)
                        DB().castIconFullSize = v
                        ns.RefreshAllSettings()
                        UpdatePreview()
                      end },
                    { type="toggle", label="Use Target Border Color",
                      tooltip="Colors the full-size spell icon border with your target border color while the cast bar wrap border is active.",
                      get=function()
                        local db = DB()
                        if db and db.castIconTargetBorder ~= nil then return db.castIconTargetBorder end
                        return defaults.castIconTargetBorder
                      end,
                      set=function(v)
                        DB().castIconTargetBorder = v
                        if ns.ApplyBorderWrapToAll then ns.ApplyBorderWrapToAll() end
                        UpdatePreview()
                      end },
                },
            })
            local spellIconCogBtn = CreateFrame("Button", nil, rightRgn)
            spellIconCogBtn:SetSize(26, 26)
            spellIconCogBtn:SetPoint("RIGHT", rightRgn._control, "LEFT", -8, 0)
            rightRgn._lastInline = spellIconCogBtn
            spellIconCogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            spellIconCogBtn:SetAlpha(castIconOff() and 0.15 or 0.4)
            local spellIconCogTex = spellIconCogBtn:CreateTexture(nil, "OVERLAY")
            spellIconCogTex:SetAllPoints()
            spellIconCogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            spellIconCogBtn:SetScript("OnEnter", function(self)
                if castIconOff() then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Spell Icon"))
                else
                    self:SetAlpha(0.7)
                end
            end)
            spellIconCogBtn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                self:SetAlpha(castIconOff() and 0.15 or 0.4)
            end)
            spellIconCogBtn:SetScript("OnClick", function(self)
                if castIconOff() then return end
                spellIconCogShow(self)
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                spellIconCogBtn:SetAlpha(castIconOff() and 0.15 or 0.4)
            end)
        end

        -- Cast Background Opacity (+ swatch) | Cast Bar Border (+ swatch)
        local castBgRow
        castBgRow, h = W:DualRow(parent, y,
            { type="slider", text="Cast Background", min=0, max=100, step=1,
              getValue=function()
                return math.floor(((DBVal("castBgAlpha") or defaults.castBgAlpha) * 100) + 0.5)
              end,
              setValue=function(v)
                DB().castBgAlpha = v / 100
                local c = (DB() and DB().castBgColor) or defaults.castBgColor
                for _, plate in pairs(plates) do
                    plate.castBG:SetColorTexture(c.r, c.g, c.b, v / 100)
                end
                UpdatePreview()
              end },
            { type="slider", text="Cast Bar Border", min=0, max=4, step=1,
              tooltip="Pixel-perfect border around the cast bar. Set to 0 for no border.",
              getValue=function() return DBVal("castBorderSize") or defaults.castBorderSize end,
              setValue=function(v)
                DB().castBorderSize = v
                ns.RefreshCastBorder()
                UpdatePreview()
              end });  y = y - h
        do
            local leftRgn = castBgRow._leftRegion
            local castBgColorGet = function()
                local c = (DB() and DB().castBgColor) or defaults.castBgColor
                return c.r, c.g, c.b
            end
            local castBgColorSet = function(r, g, b)
                DB().castBgColor = { r = r, g = g, b = b }
                local a = DBVal("castBgAlpha") or defaults.castBgAlpha
                for _, plate in pairs(plates) do
                    plate.castBG:SetColorTexture(r, g, b, a)
                end
                UpdatePreview()
            end
            local castBgSwatch, castBgUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, castBgColorGet, castBgColorSet, nil, 20)
            PP.Point(castBgSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = castBgSwatch
            EllesmereUI.RegisterWidgetRefresh(function() castBgUpdateSwatch() end)
        end
        -- Inline color swatch on Cast Bar Border (right region)
        do
            local rightRgn = castBgRow._rightRegion
            local castBorderColorGet = function()
                local c = (DB() and DB().castBorderColor) or defaults.castBorderColor
                return c.r, c.g, c.b
            end
            local castBorderColorSet = function(r, g, b)
                DB().castBorderColor = { r = r, g = g, b = b }
                ns.RefreshCastBorderColor()
                UpdatePreview()
            end
            local cbSwatch, cbUpdateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, castBorderColorGet, castBorderColorSet, nil, 20)
            PP.Point(cbSwatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
            rightRgn._lastInline = cbSwatch
            EllesmereUI.RegisterWidgetRefresh(function() cbUpdateSwatch() end)
        end

        -- Cast Timer: position dropdown (None / Right / Left), styled like the
        -- duration dropdowns. "None" hides the timer (showCastTimer = false);
        -- Right/Left choose the side -- which reserves space and pushes whichever
        -- cast text shares that side. Size / X / Y live in the inline cog.
        local castTimerRow
        castTimerRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Cast Timer",
              values={ none = "None", right = "Right", left = "Left" },
              order={ "none", "right", "left" },
              getValue=function()
                local db = DB()
                local shown = defaults.showCastTimer
                if db and db.showCastTimer ~= nil then shown = db.showCastTimer end
                if not shown then return "none" end
                return (db and db.castTimerSide) or defaults.castTimerSide
              end,
              setValue=function(v)
                if v == "none" then
                    DB().showCastTimer = false
                else
                    DB().showCastTimer = true
                    DB().castTimerSide = v
                end
                ns.RefreshAllSettings()
                UpdatePreview()
                EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Cast Bar Y Offset", min=-25, max=75, step=1,
              tooltip="Nudge the cast bar up or down from its default spot under the health bar.",
              getValue=function() return DBVal("castBarOffsetY") or defaults.castBarOffsetY end,
              setValue=function(v)
                DB().castBarOffsetY = v
                local barW = ns.GetHealthBarWidth()
                local castH = ns.GetCastBarHeight()
                for _, plate in pairs(plates) do
                    ns.LayoutCastBar(plate, barW, castH)
                end
                UpdatePreview()
              end });  y = y - h
        do
            local leftRgn = castTimerRow._leftRegion
            local ctColorGet = function()
                local c = (DB() and DB().castTimerColor) or defaults.castTimerColor
                return c.r, c.g, c.b
            end
            local ctColorSet = function(r, g, b)
                DB().castTimerColor = { r = r, g = g, b = b }
                for _, plate in pairs(plates) do
                    if plate.castTimer then plate.castTimer:SetTextColor(r, g, b, 1) end
                end
                UpdatePreview()
            end
            local ctSwatch, ctUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, ctColorGet, ctColorSet, nil, 20)
            PP.Point(ctSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = ctSwatch
            EllesmereUI.RegisterWidgetRefresh(function() ctUpdateSwatch() end)

            -- Inline cog for Cast Timer Size / X / Y
            local tmCogBtn = CreateFrame("Button", nil, leftRgn)
            tmCogBtn:SetSize(26, 26)
            tmCogBtn:SetPoint("RIGHT", ctSwatch, "LEFT", -6, 0)
            leftRgn._lastInline = tmCogBtn
            tmCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            tmCogBtn:SetAlpha(0.4)
            local tmCogTex = tmCogBtn:CreateTexture(nil, "OVERLAY")
            tmCogTex:SetAllPoints()
            tmCogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            tmCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            tmCogBtn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                if cogPopupOwner ~= self then self:SetAlpha(0.4) end
            end)
            tmCogBtn:SetScript("OnClick", function(self)
                ShowCogPopup(self, {
                    title = EllesmereUI.L("Cast Timer Settings"),
                    xGet = function() return DBVal("castTimerOffsetX") or defaults.castTimerOffsetX end,
                    xSet = function(v) DB().castTimerOffsetX = v; ns.RefreshAllSettings(); UpdatePreview() end,
                    yGet = function() return DBVal("castTimerOffsetY") or defaults.castTimerOffsetY end,
                    ySet = function(v) DB().castTimerOffsetY = v; ns.RefreshAllSettings(); UpdatePreview() end,
                    sizeGet = function() return DBVal("castTimerSize") or defaults.castTimerSize end,
                    sizeSet = function(v) DB().castTimerSize = v; ns.RefreshAllSettings(); UpdatePreview() end,
                    sizeMin = 6, sizeMax = 20, sizeLabel = EllesmereUI.L("Size"),
                    sizeFirst = true,
                })
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                tmCogBtn:SetAlpha(cogPopupOwner == tmCogBtn and 0.7 or 0.4)
            end)
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  CAST COLORS AND EFFECTS
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_CASTBAR, y);  y = y - h

        -- Cast Color ---- Kick Ready Mid-Cast Hint
        local kickHintValues = { none = "None", tick = "Tick", tickbar = "Tick + Bar" }
        local kickHintOrder = { "none", "tick", "tickbar" }
        local castColorRow
        castColorRow, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Cast Color",
              swatches = {
                { tooltip = "Interruptible Cast",
                  getValue = function() return DBColor("castBar") end,
                  setValue = function(r, g, b)
                    DB().castBar = { r = r, g = g, b = b }
                    RefreshAllPlates(); UpdatePreview()
                  end },
                { tooltip = "Interrupt on CD",
                  getValue = function() return DBColor("interruptReady") end,
                  setValue = function(r, g, b)
                    DB().interruptReady = { r = r, g = g, b = b }
                    RefreshAllPlates()
                  end },
                { tooltip = "Uninterruptible Cast",
                  getValue = function() return DBColor("castBarUninterruptible") end,
                  setValue = function(r, g, b)
                    DB().castBarUninterruptible = { r = r, g = g, b = b }
                    RefreshAllPlates()
                  end },
                { tooltip = "Important Cast",
                  getValue = function() return DBColor("castBarImportant") end,
                  setValue = function(r, g, b)
                    DB().castBarImportant = { r = r, g = g, b = b }
                    RefreshAllPlates()
                  end,
                  disabled = function()
                    local db = DB()
                    local on = db and db.importantCastColorEnabled
                    if on == nil then on = defaults.importantCastColorEnabled end
                    return not on
                  end,
                  disabledTooltip = "Important Cast Color" },
              } },
            { type="dropdown", text="Kick Ready Mid-Cast Hint",
              values=kickHintValues, order=kickHintOrder,
              tooltip="Shows where your interrupt will be ready during an enemy cast. \"Tick\" marks the exact spot on the cast bar; \"Tick + Bar\" also colours the window during which your interrupt will be available.",
              getValue=function()
                -- View over the two underlying toggles (kickTickEnabled +
                -- interruptMidCastEnabled) so nothing migrates: tick off -> None,
                -- tick on -> Tick, tick on + bar on -> Tick + Bar. Tick default is
                -- true (matches the old toggle), so a fresh user reads "Tick".
                local db = DB()
                local tick = true
                if db and db.kickTickEnabled ~= nil then tick = db.kickTickEnabled end
                local bar = defaults.interruptMidCastEnabled
                if db and db.interruptMidCastEnabled ~= nil then bar = db.interruptMidCastEnabled end
                if not tick then return "none" end
                if bar then return "tickbar" end
                return "tick"
              end,
              setValue=function(v)
                local db = DB()
                if v == "none" then
                    db.kickTickEnabled = false
                    db.interruptMidCastEnabled = false
                elseif v == "tickbar" then
                    db.kickTickEnabled = true
                    db.interruptMidCastEnabled = true
                else
                    db.kickTickEnabled = true
                    db.interruptMidCastEnabled = false
                end
                ns.RefreshAllSettings()
                -- Rebuild so the inline mid-cast colour swatch greys/ungreys.
                C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
              end });  y = y - h

        -- Inline mid-cast colour swatch on the Hint dropdown (moved here from the
        -- Cast Color swatches). Greys out unless "Tick + Bar" is selected, since
        -- the colour only applies to the bar.
        do
            local rightRgn = castColorRow._rightRegion
            local ctrl = rightRgn and rightRgn._control
            if ctrl and EllesmereUI.BuildColorSwatch then
                local function midColorOff()
                    local db = DB()
                    local on = db and db.interruptMidCastEnabled
                    if on == nil then on = defaults.interruptMidCastEnabled end
                    return not on
                end
                local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                    rightRgn, castColorRow:GetFrameLevel() + 3,
                    function()
                        local c = DB().interruptMidCastColor or defaults.interruptMidCastColor
                        return c.r, c.g, c.b
                    end,
                    function(r, g, b)
                        DB().interruptMidCastColor = { r = r, g = g, b = b }
                        ns.RefreshAllSettings()
                    end, nil, 20)
                PP.Point(swatch, "RIGHT", ctrl, "LEFT", -12, 0)
                rightRgn._lastInline = swatch
                swatch:SetScript("OnEnter", function(s) EllesmereUI.ShowWidgetTooltip(s, "Interrupt Ready Mid-Cast") end)
                swatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                EllesmereUI.RegisterWidgetRefresh(function()
                    local off = midColorOff()
                    swatch:SetAlpha(off and 0.15 or 1)
                    swatch:EnableMouse(not off)
                    updateSwatch()
                end)
                swatch:SetAlpha(midColorOff() and 0.15 or 1)
                swatch:EnableMouse(not midColorOff())
            end
        end

        -- Inline cog beside the Cast Color swatches: Show Shield Icon
        do
            local rgn = castColorRow._leftRegion
            local _, midCastCogShow = EllesmereUI.BuildCogPopup({
                title = "Cast Color",
                rows = {
                    { type = "toggle", label = "Show Shield Icon",
                      tooltip = "Show a shield icon on the cast bar when an enemy's cast cannot be interrupted.",
                      get = function()
                        local db = DB()
                        if db and db.castBarShieldEnabled ~= nil then return db.castBarShieldEnabled end
                        return defaults.castBarShieldEnabled
                      end,
                      set = function(v)
                        DB().castBarShieldEnabled = v
                        RefreshAllPlates()
                      end },
                    { type = "toggle", label = "Important Cast Color",
                      tooltip = "Tint the cast bar with the Important colour when the enemy casts a spell the game flags as important. Overrides the Interruptible Cast colour; your interrupt being on cooldown still takes priority.",
                      get = function()
                        local db = DB()
                        if db and db.importantCastColorEnabled ~= nil then return db.importantCastColorEnabled end
                        return defaults.importantCastColorEnabled
                      end,
                      set = function(v)
                        DB().importantCastColorEnabled = v
                        RefreshAllPlates()
                        EllesmereUI:RefreshPage()
                      end },
                },
            })
            local midCastCogBtn = CreateFrame("Button", nil, rgn)
            midCastCogBtn:SetSize(26, 26)
            midCastCogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = midCastCogBtn
            midCastCogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            midCastCogBtn:SetAlpha(0.4)
            local midCastCogTex = midCastCogBtn:CreateTexture(nil, "OVERLAY")
            midCastCogTex:SetAllPoints(); midCastCogTex:SetTexture(EllesmereUI.COGS_ICON)
            if midCastCogTex.SetSnapToPixelGrid then midCastCogTex:SetSnapToPixelGrid(false); midCastCogTex:SetTexelSnappingBias(0) end
            midCastCogBtn:SetScript("OnEnter", function(s)
                s:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(s, "Cast Color Settings")
            end)
            midCastCogBtn:SetScript("OnLeave", function(s)
                s:SetAlpha(0.4)
                EllesmereUI.HideWidgetTooltip()
            end)
            midCastCogBtn:SetScript("OnClick", function(s) midCastCogShow(s) end)
        end

        -- Important Cast Glow dropdown + inline color swatch + cog
        do
            local function impCastOff()
                local db = DB()
                local on = db and db.importantCastGlow
                if on == nil then on = defaults.importantCastGlow end
                return not on
            end
            local function impCastAntsOff()
                if impCastOff() then return true end
                local raw = DB().importantCastGlowStyle or defaults.importantCastGlowStyle
                return type(raw) ~= "number" or raw ~= 1
            end

            local impGlowValues = { [0] = "None", [1] = "Pixel Glow", [4] = "Auto-Cast Shine" }
            local impGlowOrder = { 0, 1, 4 }

            local impGlowRow
            impGlowRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Important Cast Glow",
                  values=impGlowValues, order=impGlowOrder,
                  getValue=function()
                    if impCastOff() then return 0 end
                    return DB().importantCastGlowStyle or defaults.importantCastGlowStyle or 1
                  end,
                  setValue=function(v)
                    if v == 0 then
                        DB().importantCastGlow = false
                    else
                        DB().importantCastGlow = true
                        DB().importantCastGlowStyle = v
                    end
                    RefreshAllPlates()
                    C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
                  end,
                  tooltip="Show a glow on the cast bar when the enemy is casting a spell Blizzard marks as important." },
                { type="toggle", text="Casts In Front of Nameplates",
                  tooltip="Forces all casts to be shown in front of nameplates for visual clarity",
                  getValue=function() return DBVal("castOverlayEnabled") == true end,
                  setValue=function(v)
                    DB().castOverlayEnabled = v
                    ns.RefreshAllSettings()
                  end });  y = y - h

            -- Inline color swatch
            do
                local leftRgn = impGlowRow._leftRegion
                local ctrl = leftRgn and leftRgn._control
                if ctrl and EllesmereUI.BuildColorSwatch then
                    local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                        leftRgn, impGlowRow:GetFrameLevel() + 3,
                        function()
                            local c = DB().importantCastGlowColor or defaults.importantCastGlowColor
                            return c.r or 1, c.g or 0.2, c.b or 0.2
                        end,
                        function(r, g, b)
                            DB().importantCastGlowColor = { r = r, g = g, b = b }
                            RefreshAllPlates()
                        end, nil, 20)
                    PP.Point(swatch, "RIGHT", ctrl, "LEFT", -12, 0)
                    leftRgn._lastInline = swatch
                    EllesmereUI.RegisterWidgetRefresh(function()
                        local off = impCastOff()
                        swatch:SetAlpha(off and 0.15 or 1)
                        swatch:EnableMouse(not off)
                        updateSwatch()
                    end)
                    swatch:SetAlpha(impCastOff() and 0.15 or 1)
                    swatch:EnableMouse(not impCastOff())
                end
            end

            -- Cog popup for Pixel Glow settings.
            do
                local _, ShowImpCastGlowPopup = EllesmereUI.BuildCogPopup({
                    title = "Pixel Glow Settings",
                    rows = {
                        { type = "slider", label = "Lines", min = 2, max = 16, step = 1,
                          get = function() return DB().importantCastGlowLines or defaults.importantCastGlowLines or 8 end,
                          set = function(v) DB().importantCastGlowLines = v; RefreshAllPlates() end },
                        { type = "slider", label = "Thickness", min = 1, max = 4, step = 1,
                          get = function() return DB().importantCastGlowThickness or defaults.importantCastGlowThickness or 2 end,
                          set = function(v) DB().importantCastGlowThickness = v; RefreshAllPlates() end },
                        { type = "slider", label = "Speed", min = 1, max = 8, step = 1,
                          get = function() local s = DB().importantCastGlowSpeed or defaults.importantCastGlowSpeed or 4; return 9 - s end,
                          set = function(v) DB().importantCastGlowSpeed = 9 - v; RefreshAllPlates() end },
                        { type = "toggle", label = "Background",
                          get = function() return DB().importantCastGlowBackground == true end,
                          set = function(v) DB().importantCastGlowBackground = v and true or nil; RefreshAllPlates() end },
                        { type = "colorpicker", label = "Background Color",
                          get = function()
                              local c = DB().importantCastGlowBackgroundColor or defaults.importantCastGlowBackgroundColor or { r = 0, g = 0, b = 0 }
                              return c.r or 0, c.g or 0, c.b or 0
                          end,
                          set = function(r, g, b) DB().importantCastGlowBackgroundColor = { r = r, g = g, b = b }; RefreshAllPlates() end,
                          disabled = function() return DB().importantCastGlowBackground ~= true end,
                          disabledTooltip = EllesmereUI.DisabledTooltip("Pixel Glow Background") },
                    },
                })

                local leftRgn = impGlowRow._leftRegion
                local COGS_ICON = EllesmereUI.COGS_ICON
                local cogBtn = CreateFrame("Button", nil, leftRgn)
                cogBtn:SetSize(26, 26)
                if leftRgn._lastInline then
                    PP.Point(cogBtn, "RIGHT", leftRgn._lastInline, "LEFT", -6, 0)
                else
                    PP.Point(cogBtn, "RIGHT", leftRgn._control, "LEFT", -8, 0)
                end
                cogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints(); cogTex:SetTexture(COGS_ICON)
                if cogTex.SetSnapToPixelGrid then cogTex:SetSnapToPixelGrid(false); cogTex:SetTexelSnappingBias(0) end
                cogBtn:SetAlpha(0.4)
                cogBtn:SetScript("OnClick", function(self) ShowImpCastGlowPopup(self) end)
                cogBtn:SetScript("OnEnter", function(self)
                    self:SetAlpha(1)
                    EllesmereUI.ShowWidgetTooltip(self, "Pixel Glow Settings")
                end)
                cogBtn:SetScript("OnLeave", function(self)
                    self:SetAlpha(0.4)
                    EllesmereUI.HideWidgetTooltip()
                end)
                -- Disable cog when not using pixel glow
                EllesmereUI.RegisterWidgetRefresh(function()
                    local off = impCastAntsOff()
                    cogBtn:SetAlpha(off and 0.15 or 0.4)
                    cogBtn:EnableMouse(not off)
                end)
                cogBtn:SetAlpha(impCastAntsOff() and 0.15 or 0.4)
                cogBtn:EnableMouse(not impCastAntsOff())
            end
        end

        -- Row 3: Focus Text Reminders (CDM only, left) | Show Interrupted Flash
        -- Effect (always present). The flash toggle is a core cast bar setting, so
        -- when the Cooldown Manager is loaded the Focus Text Reminders toggle fills
        -- the left slot and the flash toggle takes the right; otherwise the flash
        -- toggle takes the left slot itself.
        do
            local function flashOff()
                local db = DB()
                local on = db and db.interruptedFlashEnabled
                if on == nil then on = defaults.interruptedFlashEnabled end
                return not on
            end
            local flashCfg = {
                type = "toggle", text = "Show Interrupted Flash Effect",
                tooltip = "Flash the enemy's cast bar and show \"Interrupted\" for a moment when their cast is interrupted. Use the swatch to change the flash colour.",
                getValue = function()
                    local db = DB()
                    if db and db.interruptedFlashEnabled ~= nil then return db.interruptedFlashEnabled end
                    return defaults.interruptedFlashEnabled
                end,
                setValue = function(v)
                    DB().interruptedFlashEnabled = v
                    RefreshAllPlates()
                    -- Rebuild so the inline flash colour swatch greys/ungreys.
                    C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
                end,
            }

            local row3, swatchRegion
            if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUICooldownManager") then
                -- Access the FocusKick bar config in CDM's profile data
                local function GetFocusKickBar()
                    local cdmDb = _G._ECME_AceDB
                    local p = cdmDb and cdmDb.profile
                    local bars = p and p.cdmBars and p.cdmBars.bars
                    if not bars then return nil end
                    for _, b in ipairs(bars) do
                        if b.key == "focuskick" then return b end
                    end
                    return nil
                end
                row3, h = W:DualRow(parent, y,
                    { type="toggle", text="Focus Text Reminders",
                      tooltip = "Display the word \"FOCUS\" below caster/miniboss mobs in M+ if you have not set your focus. This is the same setting as in the FocusKick bar options. Disabled for specs with no kick.",
                      getValue = function()
                          local fk = GetFocusKickBar()
                          return fk and fk.focusReminderEnabled == true
                      end,
                      setValue = function(v)
                          local fk = GetFocusKickBar()
                          if fk then fk.focusReminderEnabled = v end
                          if _G._ECME_RefreshFocusReminders then
                              _G._ECME_RefreshFocusReminders()
                          end
                          EllesmereUI:RefreshPage()
                      end },
                    flashCfg
                );  y = y - h
                swatchRegion = row3._rightRegion
            else
                row3, h = W:DualRow(parent, y,
                    flashCfg,
                    { type = "label", text = "" }
                );  y = y - h
                swatchRegion = row3._leftRegion
            end

            -- Inline flash colour swatch on the Show Interrupted Flash Effect
            -- toggle. Greys out when the effect is disabled.
            do
                local rgn = swatchRegion
                local ctrl = rgn and rgn._control
                if ctrl and EllesmereUI.BuildColorSwatch then
                    local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                        rgn, row3:GetFrameLevel() + 3,
                        function()
                            local c = DB().interruptedFlashColor or defaults.interruptedFlashColor
                            return c.r, c.g, c.b
                        end,
                        function(r, g, b)
                            DB().interruptedFlashColor = { r = r, g = g, b = b }
                            RefreshAllPlates()
                        end, nil, 20)
                    PP.Point(swatch, "RIGHT", rgn._lastInline or ctrl, "LEFT", -12, 0)
                    rgn._lastInline = swatch
                    swatch:SetScript("OnEnter", function(s) EllesmereUI.ShowWidgetTooltip(s, "Interrupted Flash Colour") end)
                    swatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    EllesmereUI.RegisterWidgetRefresh(function()
                        local off = flashOff()
                        swatch:SetAlpha(off and 0.15 or 1)
                        swatch:EnableMouse(not off)
                        updateSwatch()
                    end)
                    swatch:SetAlpha(flashOff() and 0.15 or 1)
                    swatch:EnableMouse(not flashOff())
                end
            end
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  TARGET, FOCUS & HOVER EFFECTS
        -----------------------------------------------------------------------
        local tfxHeader
        tfxHeader, h = W:SectionHeader(parent, "TARGET, FOCUS & HOVER EFFECTS", y);  y = y - h

        local targetGlowRow
        -- Build the arrow-style dropdown options from the shared style table.
        local arrowVals = { none = "None" }
        local arrowOrd = { "none" }
        for _, k in ipairs(ns.TARGET_ARROW_ORDER) do
            arrowVals[k] = ns.TARGET_ARROW_STYLES[k].label
            arrowOrd[#arrowOrd + 1] = k
        end
        -- Preview the right-arrow texture on the right of each dropdown row.
        arrowVals._menuOpts = {
            itemHeight = 26,
            icon = function(key)
                local st = ns.TARGET_ARROW_STYLES[key]
                if not st then return nil end  -- "none" has no preview
                return ns.TARGET_ARROW_DIR .. st.l .. ".png"
            end,
            iconWidth = function(key)
                local st = ns.TARGET_ARROW_STYLES[key]
                if not st then return nil end
                -- Match in-game aspect: drawn width is st.w at height 16; the icon
                -- slot is itemHeight(32) - 8 = 24 tall, so scale width by 24/16.
                return math.floor(st.w * 24 / 16 + 0.5)
            end,
        }
        targetGlowRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Target Effect",
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end },
            { type="dropdown", text="Target Arrows",
              values=arrowVals,
              order=arrowOrd,
              getValue=function()
                if DBVal("showTargetArrows") ~= true then return "none" end
                return DBVal("targetArrowStyle") or (DBVal("targetArrowDouble") and "double") or "simple"
              end,
              setValue=function(v)
                if v == "none" then
                    DB().showTargetArrows = false
                else
                    DB().showTargetArrows = true
                    DB().targetArrowStyle = v
                end
                for _, plate in pairs(plates) do
                    plate:ApplyTarget(); plate:UpdateAuras()
                end
                UpdatePreview()
              end });  y = y - h

        -- Target Effect: multi-select checkbox dropdown (EllesmereUI / Border
        -- Color / Highlight), replacing the placeholder control above. The toggles
        -- are independent; the data model live-converts from the legacy
        -- targetGlowStyle string (see ns.GetTargetGlow* in the core file).
        local refreshTargetBorderSwatch  -- fwd decl; assigned when the swatch builds
        local refreshTargetGlowSwatch    -- fwd decl; assigned when the glow swatch builds
        local refreshTargetHighlightCog  -- fwd decl; assigned when the cog builds
        do
            local leftRgn = targetGlowRow._leftRegion
            if leftRgn._control then leftRgn._control:Hide() end
            local glowItems = {
                { key = "ellesmereui", label = "EUI Glow" },
                { key = "borderColor", label = "Border Color" },
                { key = "highlight",   label = "Highlight" },
                { key = "borderSize",  label = "Border Size",
                  tooltip = "Change Size in the Cogwheel" },
            }
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                leftRgn, 170, leftRgn:GetFrameLevel() + 2,
                glowItems,
                function(k)
                    if k == "ellesmereui" then return ns.GetTargetGlowEllesmereUI() end
                    if k == "borderColor" then return ns.GetTargetGlowBorderColor() end
                    if k == "highlight"   then return ns.GetTargetGlowHighlight() end
                    if k == "borderSize"  then return ns.GetTargetGlowBorderSize() end
                    return false
                end,
                function(k, v)
                    if k == "ellesmereui" then DB().targetGlowEllesmereUI = v
                    elseif k == "borderColor" then DB().targetGlowBorderColor = v
                    elseif k == "highlight" then DB().targetGlowHighlight = v
                    elseif k == "borderSize" then
                        DB().targetGlowBorderSize = v
                        -- First-enable snapshot: seed the cog slider with the
                        -- user's CURRENT border size, so enabling the effect
                        -- changes nothing until they move the slider. One-time
                        -- (never re-snapshots on later toggles).
                        if v and DB().targetBorderSizeValue == nil then
                            if ns.IsCustomBorderEnabled() then
                                DB().targetBorderSizeValue = DBVal("customBorderSize") or defaults.customBorderSize
                            else
                                DB().targetBorderSizeValue = DBVal("borderSize") or defaults.borderSize
                            end
                        end
                    end
                    for _, plate in pairs(plates) do plate:ApplyTarget() end
                    UpdatePreview()
                    if refreshTargetBorderSwatch then refreshTargetBorderSwatch() end
                    if refreshTargetGlowSwatch then refreshTargetGlowSwatch() end
                    if refreshTargetHighlightCog then refreshTargetHighlightCog() end
                end)
            PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
            leftRgn._control = cbDD
            leftRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)

            -- Inline Border Color swatch: edits targetBorderColor (default white),
            -- which tints the custom border. Dimmed + non-interactive unless the
            -- Border Color toggle is checked.
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5,
                function() local c = ns.GetTargetBorderColor(); return c.r, c.g, c.b end,
                function(r, g, b)
                    DB().targetBorderColor = { r = r, g = g, b = b }
                    for _, plate in pairs(plates) do plate:ApplyTarget() end
                    UpdatePreview()
                end, nil, 20)
            PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = swatch
            -- Tooltip so the swatch's purpose is clear (shown when interactive,
            -- i.e. while the Border Color toggle is on).
            swatch:SetScript("OnEnter", function() if EllesmereUI.ShowWidgetTooltip then EllesmereUI.ShowWidgetTooltip(swatch, "Border Color") end end)
            swatch:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)
            refreshTargetBorderSwatch = function()
                local off = not ns.GetTargetGlowBorderColor()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end
            EllesmereUI.RegisterWidgetRefresh(refreshTargetBorderSwatch)
            refreshTargetBorderSwatch()

            -- Inline Glow Color swatch: edits targetGlowColor (default the
            -- signature blue), which tints the EUI background glow. Dimmed +
            -- non-interactive unless the EUI Glow toggle is checked.
            local glowSwatch, updateGlowSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5,
                function() local c = ns.GetTargetGlowColor(); return c.r, c.g, c.b end,
                function(r, g, b)
                    DB().targetGlowColor = { r = r, g = g, b = b }
                    for _, plate in pairs(plates) do plate:ApplyTarget() end
                    UpdatePreview()
                end, nil, 20)
            PP.Point(glowSwatch, "RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = glowSwatch
            glowSwatch:SetScript("OnEnter", function() if EllesmereUI.ShowWidgetTooltip then EllesmereUI.ShowWidgetTooltip(glowSwatch, "Glow Color") end end)
            glowSwatch:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)
            refreshTargetGlowSwatch = function()
                local off = not ns.GetTargetGlowEllesmereUI()
                glowSwatch:SetAlpha(off and 0.15 or 1)
                glowSwatch:EnableMouse(not off)
                updateGlowSwatch()
            end
            EllesmereUI.RegisterWidgetRefresh(refreshTargetGlowSwatch)
            refreshTargetGlowSwatch()

            -- Inline cog: "More Effects" -- Highlight color/opacity + Glow
            -- opacity. Enabled when either the Highlight OR EUI Glow toggle is on
            -- (so Glow Opacity is reachable whenever the glow is active).
            do
                local _, highlightCogShow = EllesmereUI.BuildCogPopup({
                    title = "More Effects",
                    rows = {
                        { type="colorpicker", label="Highlight Color", hasAlpha=false,
                          get=function() local c = ns.GetTargetHighlightColor(); return c.r, c.g, c.b end,
                          set=function(r, g, b)
                            DB().targetHighlightColor = { r = r, g = g, b = b }
                            for _, plate in pairs(plates) do plate:ApplyTarget() end
                            UpdatePreview()
                          end },
                        { type="slider", label="Highlight Opacity", min=0, max=100, step=1,
                          get=function() return math.floor((ns.GetTargetHighlightAlpha() * 100) + 0.5) end,
                          set=function(v)
                            DB().targetHighlightAlpha = v / 100
                            for _, plate in pairs(plates) do plate:ApplyTarget() end
                            UpdatePreview()
                          end },
                        { type="slider", label="Glow Opacity", min=0, max=100, step=1,
                          get=function() return math.floor((ns.GetTargetGlowAlpha() * 100) + 0.5) end,
                          set=function(v)
                            DB().targetGlowAlpha = v / 100
                            for _, plate in pairs(plates) do plate:ApplyTarget() end
                            UpdatePreview()
                          end },
                        { type="slider", label="Border Size", min=0, max=4, step=1,
                          get=function()
                            local v = DBVal("targetBorderSizeValue")
                            if v ~= nil then return v end
                            -- Not snapshotted yet: show the current border size.
                            if ns.IsCustomBorderEnabled() then
                                return DBVal("customBorderSize") or defaults.customBorderSize
                            end
                            return DBVal("borderSize") or defaults.borderSize
                          end,
                          set=function(v)
                            DB().targetBorderSizeValue = v
                            for _, plate in pairs(plates) do plate:ApplyTarget() end
                            UpdatePreview()
                          end,
                          disabled=function() return not ns.GetTargetGlowBorderSize() end,
                          disabledTooltip=EllesmereUI.DisabledTooltip("Border Size Target Effect") },
                    },
                })
                local highlightCogBtn = CreateFrame("Button", nil, leftRgn)
                highlightCogBtn:SetSize(26, 26)
                highlightCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
                leftRgn._lastInline = highlightCogBtn
                highlightCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
                local highlightCogTex = highlightCogBtn:CreateTexture(nil, "OVERLAY")
                highlightCogTex:SetAllPoints(); highlightCogTex:SetTexture(EllesmereUI.COGS_ICON)
                local function highlightCogOff()
                    return not (ns.GetTargetGlowHighlight() or ns.GetTargetGlowEllesmereUI()
                        or ns.GetTargetGlowBorderSize())
                end
                highlightCogBtn:SetScript("OnEnter", function(s) if not highlightCogOff() then s:SetAlpha(0.7) end end)
                highlightCogBtn:SetScript("OnLeave", function(s) if not highlightCogOff() then s:SetAlpha(0.4) end end)
                highlightCogBtn:SetScript("OnClick", function(s) if not highlightCogOff() then highlightCogShow(s) end end)
                refreshTargetHighlightCog = function()
                    local off = highlightCogOff()
                    highlightCogBtn:SetAlpha(off and 0.15 or 0.4)
                    highlightCogBtn:EnableMouse(not off)
                end
                EllesmereUI.RegisterWidgetRefresh(refreshTargetHighlightCog)
                refreshTargetHighlightCog()
            end
        end

        -- Inline Custom + Class color swatches on Target Arrows (next to the dropdown;
        -- custom adjacent to the control, class to its left). Click to switch; the
        -- inactive swatch dims. Both gray out when arrows are off.
        do
            local rightRgn = targetGlowRow._rightRegion
            local arrowOff = function() return DBVal("showTargetArrows") ~= true end
            local customSwatch, updateCustom, classSwatch, updateClass
            local function refreshArrowSwatches()
                if updateCustom then updateCustom() end
                if updateClass then updateClass() end
                local off = arrowOff()
                local useClass = DBVal("targetArrowClassColor") == true
                customSwatch:SetAlpha(off and 0.15 or (useClass and 0.3 or 1))
                classSwatch:SetAlpha(off and 0.15 or (useClass and 1 or 0.3))
                customSwatch:SetMouseClickEnabled(not off)
                classSwatch:SetMouseClickEnabled(not off)
            end
            customSwatch, updateCustom = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                function() local c = DBVal("targetArrowColor") or defaults.targetArrowColor; return c.r, c.g, c.b end,
                function(r, g, b)
                    DB().targetArrowColor = { r = r, g = g, b = b }
                    DB().targetArrowClassColor = false
                    for _, plate in pairs(plates) do plate:ApplyTarget() end
                    UpdatePreview(); refreshArrowSwatches()
                end, nil, 20)
            PP.Point(customSwatch, "RIGHT", rightRgn._control, "LEFT", -8, 0)
            local origCustomClick = customSwatch:GetScript("OnClick")
            customSwatch:SetScript("OnClick", function(self, ...)
                if arrowOff() then return end
                if DBVal("targetArrowClassColor") == true then
                    DB().targetArrowClassColor = false
                    for _, plate in pairs(plates) do plate:ApplyTarget() end
                    UpdatePreview(); refreshArrowSwatches()
                    return
                end
                if origCustomClick then origCustomClick(self, ...) end
            end)
            customSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color") end)
            customSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            classSwatch, updateClass = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                function() local _, ct = UnitClass("player"); local cc = ct and C_ClassColor and C_ClassColor.GetClassColor(ct); if cc then return cc.r, cc.g, cc.b end return 1, 1, 1 end,
                function() end, nil, 20)
            PP.Point(classSwatch, "RIGHT", customSwatch, "LEFT", -8, 0)
            rightRgn._lastInline = classSwatch
            classSwatch:SetScript("OnClick", function()
                if arrowOff() then return end
                DB().targetArrowClassColor = true
                for _, plate in pairs(plates) do plate:ApplyTarget() end
                UpdatePreview(); refreshArrowSwatches()
            end)
            classSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Color") end)
            classSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(refreshArrowSwatches)
            refreshArrowSwatches()
        end

        -- Inline cog (arrow scale), to the left of the swatches
        do
            local rightRgn = targetGlowRow._rightRegion
            local arrowOff = function() return DBVal("showTargetArrows") ~= true end
            local _, arrowCogShow = EllesmereUI.BuildCogPopup({
                title = "Arrow Scale",
                rows = {
                    { type="slider", label="Scale", min=0.5, max=3.0, step=0.1,
                      get=function() return DBVal("targetArrowScale") or defaults.targetArrowScale or 1.0 end,
                      set=function(v)
                        DB().targetArrowScale = v
                        local _scKey = DBVal("targetArrowStyle") or (DBVal("targetArrowDouble") and "double") or "simple"
                        local _scW = (ns.TARGET_ARROW_STYLES[_scKey] or ns.TARGET_ARROW_STYLES.simple).w
                        for _, plate in pairs(plates) do
                            local sc = v
                            local aw = math.floor(_scW * sc + 0.5)
                            local ah = math.floor(16 * sc + 0.5)
                            if plate.leftArrow then PP.Size(plate.leftArrow, aw, ah) end
                            if plate.rightArrow then PP.Size(plate.rightArrow, aw, ah) end
                        end
                        UpdatePreview()
                      end },
                },
            })
            local arrowCogBtn = CreateFrame("Button", nil, rightRgn)
            arrowCogBtn:SetSize(26, 26)
            arrowCogBtn:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
            rightRgn._lastInline = arrowCogBtn
            arrowCogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            local arrowCogTex = arrowCogBtn:CreateTexture(nil, "OVERLAY")
            arrowCogTex:SetAllPoints()
            arrowCogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            local function UpdateArrowCogAlpha()
                arrowCogBtn:SetAlpha(arrowOff() and 0.15 or 0.4)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateArrowCogAlpha)
            UpdateArrowCogAlpha()
            arrowCogBtn:SetScript("OnClick", function(self)
                if not arrowOff() then arrowCogShow(self) end
            end)
            arrowCogBtn:SetScript("OnEnter", function(self)
                if not arrowOff() then self:SetAlpha(0.75) end
            end)
            arrowCogBtn:SetScript("OnLeave", function(self) UpdateArrowCogAlpha() end)
        end

        -- Eye icon to the left of the Target Glow Style dropdown to toggle glow on preview
        do
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
            local leftRgn = targetGlowRow._leftRegion
            local eyeBtn = CreateFrame("Button", nil, leftRgn)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            eyeBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            eyeBtn:SetAlpha(0.4)
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function RefreshTargetGlowEye()
                if showTargetGlowPreview then
                    eyeTex:SetTexture(EYE_INVISIBLE)
                else
                    eyeTex:SetTexture(EYE_VISIBLE)
                end
            end
            RefreshTargetGlowEye()
            eyeBtn:SetScript("OnClick", function()
                showTargetGlowPreview = not showTargetGlowPreview
                RefreshTargetGlowEye()
                UpdatePreview()
            end)
            eyeBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            eyeBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
        end

        -- Enable Target Color ---- Target Texture
        local isTargetColorDisabled = function()
            local db = DB()
            if db and db.targetColorEnabled ~= nil then return not db.targetColorEnabled end
            return not defaults.targetColorEnabled
        end
        local isTargetTextureNone = function()
            return (DBVal("targetOverlayTexture") or defaults.targetOverlayTexture) == "none"
        end
        local isFocusColorDisabled = function()
            local db = DB()
            if db and db.focusColorEnabled ~= nil then return not db.focusColorEnabled end
            return not defaults.focusColorEnabled
        end
        local isFocusTextureNone = function()
            return (DBVal("focusOverlayTexture") or defaults.focusOverlayTexture) == "none"
        end

        local targetPrev, focusPrev
        local function RefreshFocusPreview()
            RefreshAllPlates()
            if focusPrev and focusPrev.UpdateOverlay then focusPrev.UpdateOverlay() end
        end

        local targetColorRow
        targetColorRow, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Target Color",
              getValue=function()
                local db = DB()
                if db and db.targetColorEnabled ~= nil then return db.targetColorEnabled end
                return defaults.targetColorEnabled
              end,
              setValue=function(v)
                DB().targetColorEnabled = v
                RefreshAllPlates()
                if targetPrev then
                    if v then
                        targetPrev.SetColorOverride(nil)
                    else
                        targetPrev.SetColorOverride(function() return DBColor("enemyInCombat") end)
                    end
                    targetPrev.UpdateColor()
                    targetPrev.SetDisabled(not v)
                end
                EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Enable Focus Color",
              getValue=function()
                local db = DB()
                if db and db.focusColorEnabled ~= nil then return db.focusColorEnabled end
                return defaults.focusColorEnabled
              end,
              setValue=function(v)
                DB().focusColorEnabled = v
                RefreshAllPlates()
                if focusPrev then
                    if v then
                        focusPrev.SetColorOverride(nil)
                    else
                        focusPrev.SetColorOverride(function() return DBColor("enemyInCombat") end)
                    end
                    focusPrev.UpdateColor()
                    focusPrev.SetDisabled(not v)
                end
                EllesmereUI:RefreshPage()
              end });  y = y - h

        -- Inline Target Color swatch
        do
            local leftRgn = targetColorRow._leftRegion
            local targetColorGet = function() return DBColor("target") end
            local targetColorSet = function(r, g, b)
                DB().target = { r = r, g = g, b = b }
                RefreshAllPlates()
                if targetPrev then targetPrev.UpdateColor() end
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, targetColorGet, targetColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isTargetColorDisabled()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            local off = isTargetColorDisabled()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
        end

        -- Inline Focus Color swatch
        do
            local rightRgn = targetColorRow._rightRegion
            local focusColorGet = function() return DBColor("focus") end
            local focusColorSet = function(r, g, b)
                DB().focus = { r = r, g = g, b = b }
                RefreshAllPlates()
                if focusPrev then focusPrev.UpdateColor() end
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, focusColorGet, focusColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isFocusColorDisabled()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            local off = isFocusColorDisabled()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
        end

        -- Target Texture ---- Focus Texture
        -- Both dropdowns list the special stripe overlays first, then the full bar
        -- texture set (EUI textures + SharedMedia) shared with the main Bar Texture
        -- dropdown. Stripe keys resolve to nameplate Media; bar keys resolve through
        -- the health-bar texture lookup at render time (ns.ResolveOverlayTexPath).
        local ovtValues, ovtOrder = {}, {}
        do
            local STRIPE_ORDER = { "striped-v2", "striped-wide-v2", "stripes-medium", "stripes-small-close", "stripes-small-spread", "striped-tiny" }
            local STRIPE_NAMES = {
                ["striped-v2"] = "Stripes", ["striped-wide-v2"] = "Wide Stripes",
                ["stripes-medium"] = "Medium Stripes", ["stripes-small-close"] = "Small Dense Stripes",
                ["stripes-small-spread"] = "Small Spread Stripes", ["striped-tiny"] = "Tiny Stripes",
            }
            for _, k in ipairs(STRIPE_ORDER) do ovtValues[k] = STRIPE_NAMES[k]; ovtOrder[#ovtOrder + 1] = k end
            ovtOrder[#ovtOrder + 1] = "---"
            for _, k in ipairs(hbtOrder) do
                ovtOrder[#ovtOrder + 1] = k
                if k ~= "---" then ovtValues[k] = hbtValues[k] end
            end
            ovtValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    if not key or key == "none" or key == "---" then return nil end
                    if ns.OVERLAY_STRIPE_KEYS and ns.OVERLAY_STRIPE_KEYS[key] then
                        return "Interface\\AddOns\\EllesmereUINameplates\\Media\\" .. key .. ".png"
                    end
                    return ns.healthBarTextures and ns.healthBarTextures[key]
                end,
            }
        end
        local textureDualRow
        textureDualRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Target Texture",
              values=ovtValues,
              getValue=function() return DBVal("targetOverlayTexture") or defaults.targetOverlayTexture end,
              setValue=function(v)
                DB().targetOverlayTexture = v
                RefreshAllPlates()
                if targetPrev and targetPrev.UpdateOverlay then targetPrev.UpdateOverlay() end
                EllesmereUI:RefreshPage()
              end,
              order=ovtOrder },
            { type="dropdown", text="Focus Texture",
              values=ovtValues,
              getValue=function() return DBVal("focusOverlayTexture") or defaults.focusOverlayTexture end,
              setValue=function(v)
                DB().focusOverlayTexture = v
                RefreshAllPlates()
                if focusPrev and focusPrev.UpdateOverlay then focusPrev.UpdateOverlay() end
                EllesmereUI:RefreshPage()
              end,
              order=ovtOrder });  y = y - h

        -- Inline Target Texture color swatch
        do
            local leftRgn = textureDualRow._leftRegion
            local targetTexColorGet = function()
                local c = (DB() and DB().targetOverlayColor) or defaults.targetOverlayColor
                return c.r, c.g, c.b
            end
            local targetTexColorSet = function(r, g, b)
                DB().targetOverlayColor = { r = r, g = g, b = b }
                RefreshAllPlates()
                if targetPrev and targetPrev.UpdateOverlay then targetPrev.UpdateOverlay() end
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, targetTexColorGet, targetTexColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = swatch
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isTargetTextureNone()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            local off = isTargetTextureNone()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
        end

        -- Inline Target Texture cog (Opacity), to the left of the swatch
        do
            local leftRgn = textureDualRow._leftRegion
            local _, targetTexCogShow = EllesmereUI.BuildCogPopup({
                title = "Target Texture",
                rows = {
                    { type="slider", label="Opacity", min=5, max=100, step=1,
                      get=function() return math.floor(((DBVal("targetOverlayAlpha") or defaults.targetOverlayAlpha) * 100) + 0.5) end,
                      set=function(v)
                        DB().targetOverlayAlpha = v / 100
                        RefreshAllPlates()
                        if targetPrev and targetPrev.UpdateOverlay then targetPrev.UpdateOverlay() end
                      end },
                    { type="toggle", label="Full alpha on empty part of bar",
                      get=function()
                        local v = DBVal("targetOverlayFullBgAlpha")
                        if v == nil then return defaults.targetOverlayFullBgAlpha end
                        return v
                      end,
                      set=function(v)
                        DB().targetOverlayFullBgAlpha = v
                        RefreshAllPlates()
                        if targetPrev and targetPrev.UpdateOverlay then targetPrev.UpdateOverlay() end
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, leftRgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            local function UpdateCogAlpha()
                cogBtn:SetAlpha(isTargetTextureNone() and 0.15 or 0.4)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogAlpha)
            UpdateCogAlpha()
            cogBtn:SetScript("OnClick", function(self)
                if not isTargetTextureNone() then targetTexCogShow(self) end
            end)
            cogBtn:SetScript("OnEnter", function(self)
                if not isTargetTextureNone() then self:SetAlpha(0.75) end
            end)
            cogBtn:SetScript("OnLeave", function(self) UpdateCogAlpha() end)
        end

        -- Inline Focus Texture color swatch
        do
            local rightRgn = textureDualRow._rightRegion
            local focusTexColorGet = function()
                local c = (DB() and DB().focusOverlayColor) or defaults.focusOverlayColor
                return c.r, c.g, c.b
            end
            local focusTexColorSet = function(r, g, b)
                DB().focusOverlayColor = { r = r, g = g, b = b }
                RefreshAllPlates()
                if focusPrev and focusPrev.UpdateOverlay then focusPrev.UpdateOverlay() end
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, focusTexColorGet, focusTexColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
            rightRgn._lastInline = swatch
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isFocusTextureNone()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            local off = isFocusTextureNone()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
        end

        -- Inline Focus Texture cog (Opacity), to the left of the swatch
        do
            local rightRgn = textureDualRow._rightRegion
            local _, focusTexCogShow = EllesmereUI.BuildCogPopup({
                title = "Focus Texture",
                rows = {
                    { type="slider", label="Opacity", min=5, max=100, step=1,
                      get=function() return math.floor(((DBVal("focusOverlayAlpha") or defaults.focusOverlayAlpha) * 100) + 0.5) end,
                      set=function(v)
                        DB().focusOverlayAlpha = v / 100
                        RefreshFocusPreview()
                      end },
                    { type="toggle", label="Full alpha on empty part of bar",
                      get=function()
                        local v = DBVal("focusOverlayFullBgAlpha")
                        if v == nil then return defaults.focusOverlayFullBgAlpha end
                        return v
                      end,
                      set=function(v)
                        DB().focusOverlayFullBgAlpha = v
                        RefreshFocusPreview()
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rightRgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
            rightRgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            local function UpdateCogAlpha()
                cogBtn:SetAlpha(isFocusTextureNone() and 0.15 or 0.4)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogAlpha)
            UpdateCogAlpha()
            cogBtn:SetScript("OnClick", function(self)
                if not isFocusTextureNone() then focusTexCogShow(self) end
            end)
            cogBtn:SetScript("OnEnter", function(self)
                if not isFocusTextureNone() then self:SetAlpha(0.75) end
            end)
            cogBtn:SetScript("OnLeave", function(self) UpdateCogAlpha() end)
        end

        -- Target Preview ---- Focus Preview
        local previewDualRow
        previewDualRow, h = W:DualRow(parent, y,
            { type="label", text="Target Preview" },
            { type="label", text="Focus Preview" });  y = y - h

        targetPrev = LazyColorPreviewBar(previewDualRow, "health", "target", previewDualRow._leftRegion)
        do
            local function RepositionTargetBar()
                local rgn = previewDualRow._leftRegion
                for _, child in ipairs({ previewDualRow:GetChildren() }) do
                    if child.GetNumPoints and child:GetNumPoints() > 0 then
                        local _, rel = child:GetPoint(1)
                        if rel == rgn then
                            child:ClearAllPoints()
                            PP.Point(child, "RIGHT", rgn, "RIGHT", -20, 0)
                            return
                        end
                    end
                end
            end
            previewDualRow:HookScript("OnShow", RepositionTargetBar)
            C_Timer.After(0, RepositionTargetBar)
        end
        if isTargetColorDisabled() then
            targetPrev.SetColorOverride(function() return DBColor("enemyInCombat") end)
        end
        targetPrev.SetDisabled(isTargetColorDisabled())
        targetPrev.UpdateColor()

        focusPrev = LazyColorPreviewBar(previewDualRow, "health", "focus", previewDualRow._rightRegion)
        do
            local function RepositionFocusBar()
                local rgn = previewDualRow._rightRegion
                for _, child in ipairs({ previewDualRow:GetChildren() }) do
                    if child.GetNumPoints and child:GetNumPoints() > 0 then
                        local _, rel = child:GetPoint(1)
                        if rel == rgn then
                            child:ClearAllPoints()
                            PP.Point(child, "RIGHT", rgn, "RIGHT", -20, 0)
                            return
                        end
                    end
                end
            end
            previewDualRow:HookScript("OnShow", RepositionFocusBar)
            C_Timer.After(0, RepositionFocusBar)
        end
        if isFocusColorDisabled() then
            focusPrev.SetColorOverride(function() return DBColor("enemyInCombat") end)
        end
        focusPrev.SetDisabled(isFocusColorDisabled())
        focusPrev.UpdateColor()

        -- Hover Texture (+ Hover Effect opacity slider + color swatch beside it):
        -- the mouseover highlight overlay and its opacity/color. Lives at the
        -- bottom of this section.
        local hoverOverlayValues, hoverOverlayOrder = {}, {}
        do
            local STRIPE_ORDER = { "striped-v2", "striped-wide-v2", "stripes-medium", "stripes-small-close", "stripes-small-spread", "striped-tiny" }
            local STRIPE_NAMES = {
                ["striped-v2"] = "Stripes", ["striped-wide-v2"] = "Wide Stripes",
                ["stripes-medium"] = "Medium Stripes", ["stripes-small-close"] = "Small Dense Stripes",
                ["stripes-small-spread"] = "Small Spread Stripes", ["striped-tiny"] = "Tiny Stripes",
            }
            hoverOverlayValues.none = "None"
            hoverOverlayOrder[#hoverOverlayOrder + 1] = "none"
            hoverOverlayOrder[#hoverOverlayOrder + 1] = "---"
            for _, k in ipairs(STRIPE_ORDER) do hoverOverlayValues[k] = STRIPE_NAMES[k]; hoverOverlayOrder[#hoverOverlayOrder + 1] = k end
            hoverOverlayOrder[#hoverOverlayOrder + 1] = "---"
            for _, k in ipairs(hbtOrder) do
                -- "none" is already prepended above; skip the copy from hbtOrder
                -- (which starts with "none") so the dropdown shows it only once.
                if k ~= "none" then
                    hoverOverlayOrder[#hoverOverlayOrder + 1] = k
                    if k ~= "---" then hoverOverlayValues[k] = hbtValues[k] end
                end
            end
            hoverOverlayValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    if not key or key == "none" or key == "---" then return nil end
                    if ns.OVERLAY_STRIPE_KEYS and ns.OVERLAY_STRIPE_KEYS[key] then
                        return "Interface\\AddOns\\EllesmereUINameplates\\Media\\" .. key .. ".png"
                    end
                    return ns.healthBarTextures and ns.healthBarTextures[key]
                end,
            }
        end
        do
            local hoverRow
            hoverRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Hover Texture",
                  tooltip="Uses the Hover Effect color and opacity. Set to None for the flat hover highlight.",
                  values=hoverOverlayValues, order=hoverOverlayOrder,
                  getValue=function() return DBVal("hoverOverlayTexture") or defaults.hoverOverlayTexture end,
                  setValue=function(v)
                    DB().hoverOverlayTexture = v
                    ns.RefreshHoverEffect()
                    UpdatePreview()
                    EllesmereUI:RefreshPage()
                  end },
                { type="slider", text="Hover Effect", min=0, max=100, step=1,
                  tooltip="Controls the highlight shown over a nameplate when you mouse over it. Set to 0 to disable.",
                  getValue=function()
                    return math.floor(((DBVal("hoverAlpha") or defaults.hoverAlpha) * 100) + 0.5)
                  end,
                  setValue=function(v)
                    DB().hoverAlpha = v / 100
                    ns.RefreshHoverEffect()
                    UpdatePreview()
                  end });  y = y - h
            -- Inline color swatch on Hover Effect (right region)
            local rightRgn = hoverRow._rightRegion
            local hvColorGet = function()
                local c = (DB() and DB().hoverColor) or defaults.hoverColor
                return c.r, c.g, c.b
            end
            local hvColorSet = function(r, g, b)
                DB().hoverColor = { r = r, g = g, b = b }
                ns.RefreshHoverEffect()
                UpdatePreview()
            end
            local hvSwatch, hvUpdateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, hvColorGet, hvColorSet, nil, 20)
            PP.Point(hvSwatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
            rightRgn._lastInline = hvSwatch
            EllesmereUI.RegisterWidgetRefresh(function() hvUpdateSwatch() end)

            -- Inline Hover Texture cog (Full alpha on empty part of bar), to the
            -- left of the Hover Texture dropdown. Disabled while it is set to None.
            local leftRgn = hoverRow._leftRegion
            local isHoverTextureNone = function()
                return (DBVal("hoverOverlayTexture") or defaults.hoverOverlayTexture) == "none"
            end
            local _, hoverTexCogShow = EllesmereUI.BuildCogPopup({
                title = "Hover Texture",
                rows = {
                    { type="toggle", label="Full alpha on empty part of bar",
                      get=function()
                        local v = DBVal("hoverOverlayFullBgAlpha")
                        if v == nil then return defaults.hoverOverlayFullBgAlpha end
                        return v
                      end,
                      set=function(v)
                        DB().hoverOverlayFullBgAlpha = v
                        ns.RefreshHoverEffect()
                        UpdatePreview()
                      end },
                },
            })
            local hvCogBtn = CreateFrame("Button", nil, leftRgn)
            hvCogBtn:SetSize(26, 26)
            hvCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = hvCogBtn
            hvCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            local hvCogTex = hvCogBtn:CreateTexture(nil, "OVERLAY")
            hvCogTex:SetAllPoints()
            hvCogTex:SetTexture(EllesmereUI.COGS_ICON)
            local function UpdateHvCogAlpha()
                hvCogBtn:SetAlpha(isHoverTextureNone() and 0.15 or 0.4)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateHvCogAlpha)
            UpdateHvCogAlpha()
            hvCogBtn:SetScript("OnClick", function(self)
                if not isHoverTextureNone() then hoverTexCogShow(self) end
            end)
            hvCogBtn:SetScript("OnEnter", function(self)
                if not isHoverTextureNone() then self:SetAlpha(0.75) end
            end)
            hvCogBtn:SetScript("OnLeave", function(self) UpdateHvCogAlpha() end)
        end

        -----------------------------------------------------------------------
        --  CLASS RESOURCE
        -----------------------------------------------------------------------
        local classResourceHeader
        classResourceHeader, h = W:SectionHeader(parent, "CLASS RESOURCE", y);  y = y - h

        local function classPowerDisabled() return DBVal("showClassPower") ~= true end

        local classResourceSectionTop = y  -- track top of content rows

        local classResourceToggleRow
        classResourceToggleRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Class Resource",
              getValue=function() return DBVal("showClassPower") == true end,
              -- DependentSetValue: Rows 2-4 below are hidden while the class
              -- resource is off; the flip forces the full rebuild.
              setValue=EllesmereUI.DependentSetValue(
                  function() return DBVal("showClassPower") == true end,
                  function(v)
                    DB().showClassPower = v
                    ns.ApplyClassPowerSetting(); UpdatePreview()
                    EllesmereUI:RefreshPage()
                  end) },
            { type="multiSwatch", text="Fill Color",
              disabled=classPowerDisabled,
              disabledTooltip="Show Class Resource",
              swatches = {
                { tooltip = "Custom Color",
                  disabled = classPowerDisabled,
                  disabledTooltip = "Show Class Resource",
                  getValue = function()
                      local c = (DB() and DB().classPowerCustomColor) or defaults.classPowerCustomColor
                      return c.r, c.g, c.b
                  end,
                  setValue = function(r, g, b)
                      DB().classPowerCustomColor = { r = r, g = g, b = b }
                      ns.RefreshClassPower(); UpdatePreview()
                  end,
                  onClick = function(self)
                      local v = DBVal("classPowerClassColors")
                      if v == nil then v = defaults.classPowerClassColors end
                      if v then
                          DB().classPowerClassColors = false
                          ns.RefreshClassPower(); UpdatePreview()
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      local v = DBVal("classPowerClassColors")
                      if v == nil then v = defaults.classPowerClassColors end
                      return v and 0.3 or 1
                  end },
                { tooltip = "Class Color",
                  disabled = classPowerDisabled,
                  disabledTooltip = "Show Class Resource",
                  getValue = function()
                      local _, ct = UnitClass("player")
                      if ct and RAID_CLASS_COLORS[ct] then
                          local cc = RAID_CLASS_COLORS[ct]
                          return cc.r, cc.g, cc.b, 1
                      end
                      return 1, 1, 1, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      DB().classPowerClassColors = true
                      ns.RefreshClassPower(); UpdatePreview()
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      local v = DBVal("classPowerClassColors")
                      if v == nil then v = defaults.classPowerClassColors end
                      return v and 1 or 0.3
                  end },
              } });  y = y - h

        -- Rows 2-4 are HIDDEN entirely while Show Class Resource is off (the
        -- toggle's DependentSetValue forces the rebuild on flips).
        if not classPowerDisabled() then
        -- Row 2: Position (with inline cog for X/Y) | Size
        local classResourceRow2
        classResourceRow2, h = W:DualRow(parent, y,
            { type="dropdown", text="Position",
              values={ top = "Top", bottom = "Bottom" },
              getValue=function() return DBVal("classPowerPos") or defaults.classPowerPos end,
              setValue=function(v)
                DB().classPowerPos = v
                ns.RefreshClassPower(); UpdatePreview()
              end, order={ "top", "bottom" } },
            { type="slider", text="Size", min=0.5, max=4.0, step=0.1,
              getValue=function() return DBVal("classPowerScale") or defaults.classPowerScale end,
              setValue=function(v)
                DB().classPowerScale = v
                ns.RefreshClassPower(); UpdatePreview()
              end });  y = y - h

        -- Inline cog on Position dropdown (X/Y offset settings)
        do
            local leftRgn = classResourceRow2._leftRegion
            local cpPosCogBtn = CreateFrame("Button", nil, leftRgn)
            cpPosCogBtn:SetSize(26, 26)
            cpPosCogBtn:SetPoint("RIGHT", leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = cpPosCogBtn
            cpPosCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            cpPosCogBtn:SetAlpha(classPowerDisabled() and 0.15 or 0.4)
            local cpPosCogTex = cpPosCogBtn:CreateTexture(nil, "OVERLAY")
            cpPosCogTex:SetAllPoints()
            cpPosCogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cpPosCogBtn:SetScript("OnEnter", function(self)
                if classPowerDisabled() then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Show Class Resource"))
                else
                    self:SetAlpha(0.7)
                end
            end)
            cpPosCogBtn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                if cogPopupOwner ~= self then self:SetAlpha(classPowerDisabled() and 0.15 or 0.4) end
            end)
            cpPosCogBtn:SetScript("OnClick", function(self)
                if classPowerDisabled() then return end
                ShowCogPopup(self, {
                    title = "Position Settings",
                    xGet = function() return DBVal("classPowerXOffset") or defaults.classPowerXOffset end,
                    xSet = function(v) DB().classPowerXOffset = v; ns.RefreshClassPower(); UpdatePreview() end,
                    yGet = function() return DBVal("classPowerYOffset") or defaults.classPowerYOffset end,
                    ySet = function(v) DB().classPowerYOffset = v; ns.RefreshClassPower(); UpdatePreview() end,
                })
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                cpPosCogBtn:SetAlpha(classPowerDisabled() and 0.15 or (cogPopupOwner == cpPosCogBtn and 0.7 or 0.4))
            end)
        end

        -- Row 3: Bar Spacing + Background Color (with alpha)
        local classResourceRow3
        classResourceRow3, h = W:DualRow(parent, y,
            { type="slider", pixel=true, text="Bar Spacing", min=-5, max=10, step=1,
              getValue=function() return DBVal("classPowerGap") or defaults.classPowerGap end,
              setValue=function(v)
                DB().classPowerGap = v
                ns.RefreshClassPower(); UpdatePreview()
              end },
            { type="colorpicker", text="Background Color", hasAlpha=true,
              getValue=function()
                local c = (DB() and DB().classPowerBgColor) or defaults.classPowerBgColor
                return c.r, c.g, c.b, c.a
              end,
              setValue=function(r, g, b, a)
                DB().classPowerBgColor = { r=r, g=g, b=b, a=a }
                ns.RefreshClassPower(); UpdatePreview()
              end });  y = y - h

        -- Row 4: Shape | Border (inline color swatch + thickness cog on Border)
        local classResourceRow4
        classResourceRow4, h = W:DualRow(parent, y,
            { type="dropdown", text="Shape",
              values={ rectangle="Rectangle", square="Square", circle="Circle",
                       diamond="Diamond", hexagon="Hexagon", shield="Shield",
                       rune="Rune", holypower="Holy Power", shard="Soul Shard",
                       combo="Combo Points", chi="Chi", arcane="Arcane Charges",
                       essence="Essence" },
              order={ "rectangle", "square", "circle", "diamond", "hexagon", "shield",
                      "rune", "holypower", "shard", "combo", "chi", "arcane", "essence" },
              getValue=function() return DBVal("classPowerShape") or defaults.classPowerShape end,
              setValue=function(v)
                DB().classPowerShape = v
                ns.RefreshClassPower(); UpdatePreview()
              end },
            { type="toggle", text="Border",
              getValue=function() return DBVal("classPowerBorder") == true end,
              setValue=function(v)
                DB().classPowerBorder = v
                ns.RefreshClassPower(); UpdatePreview()
                EllesmereUI:RefreshPage()
              end });  y = y - h

        -- Inline border color swatch + thickness cog on the Border toggle
        do
            local rgn = classResourceRow4._rightRegion
            local function borderOff()
                return classPowerDisabled() or DBVal("classPowerBorder") ~= true
            end
            local colorGet = function()
                local c = (DB() and DB().classPowerBorderColor) or defaults.classPowerBorderColor
                return c.r, c.g, c.b
            end
            local colorSet = function(r, g, b)
                DB().classPowerBorderColor = { r = r, g = g, b = b, a = 1 }
                ns.RefreshClassPower(); UpdatePreview()
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, colorGet, colorSet, nil, 20)
            PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -12, 0)
            rgn._lastInline = swatch
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = borderOff()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            local off = borderOff()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)

            local _, showCog = EllesmereUI.BuildCogPopup({
                title = "Border Settings",
                rows = {
                    { type="slider", label="Thickness", min=1, max=4, step=1,
                      get=function() return DBVal("classPowerBorderSize") or defaults.classPowerBorderSize end,
                      set=function(v) DB().classPowerBorderSize = v; ns.RefreshClassPower(); UpdatePreview() end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -9, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(borderOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) if not borderOff() then self:SetAlpha(0.7) end end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(borderOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) if not borderOff() then showCog(self) end end)
            EllesmereUI.RegisterWidgetRefresh(function()
                cogBtn:SetAlpha(borderOff() and 0.15 or 0.4)
            end)
        end
        end   -- close Class Resource hidden-while-disabled gate

        -- Invisible frame spanning the entire CLASS RESOURCE section for glow targeting
        local classResourceSection = CreateFrame("Frame", nil, parent)
        local crPad = EllesmereUI.CONTENT_PAD or 20
        classResourceSection:SetPoint("TOPLEFT", parent, "TOPLEFT", crPad, classResourceSectionTop)
        classResourceSection:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -crPad, classResourceSectionTop)
        classResourceSection:SetHeight(math.abs(classResourceSectionTop - y))
        classResourceSection._isSpacer = true  -- hide from search layout

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  GENERAL TEXT
        -----------------------------------------------------------------------
        local generalTextHeader
        generalTextHeader, h = W:SectionHeader(parent, "GENERAL TEXT", y);  y = y - h

        -- Duration controls are per aura type. "None" is the show/hide switch.
        local auraDurPosRow
        local auraTimerStackRow
        do
            local durationTypes = {
                debuff = { text = "Debuff Duration", title = "Debuff Duration Settings", key = "debuffTimerPosition", count = 4, frames = function(p, i) return p.debuffs[i] end },
                buff = { text = "Buff Duration", title = "Buff Duration Settings", key = "buffTimerPosition", count = 4, frames = function(p, i) return p.buffs[i] end },
                cc = { text = "CC Duration", title = "CC Duration Settings", key = "ccTimerPosition", count = 2, frames = function(p, i) return p.cc[i] end },
            }
            local function DurationDropdown(kind)
                local cfg = durationTypes[kind]
                return { type="dropdown", text=cfg.text, values=timerPosValues,
                  getValue=function() return DBVal(cfg.key) or atFallback end,
                  setValue=function(v)
                    DB()[cfg.key] = v
                    LiveApplyTimerPos(cfg.frames, cfg.count, v, kind)
                    UpdatePreview()
                  end, order=timerPosOrder }
            end
            local function CurrentDurationPos(cfg)
                return DBVal(cfg.key) or atFallback
            end
            local function RefreshDuration(kind)
                local cfg = durationTypes[kind]
                LiveApplyTimerPos(cfg.frames, cfg.count, CurrentDurationPos(cfg), kind)
                UpdatePreview()
            end
            local function AttachDurationTools(region, kind)
                local cfg = durationTypes[kind]
                local colorGet = function()
                    local c = AuraDurationVal(kind, "Color")
                    return c.r, c.g, c.b
                end
                local colorSet = function(r, g, b)
                    DB()[kind .. "DurationTextColor"] = { r = r, g = g, b = b }
                    RefreshDuration(kind)
                end
                local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, colorGet, colorSet, nil, 20)
                PP.Point(swatch, "RIGHT", region._control, "LEFT", -12, 0)
                region._lastInline = swatch
                EllesmereUI.RegisterWidgetRefresh(function() updateSwatch() end)

                local _, showCog = EllesmereUI.BuildCogPopup({
                    title = cfg.title,
                    rows = {
                        { type="slider", label="Size", min=6, max=20, step=1,
                          get=function() return AuraDurationVal(kind, "Size") end,
                          set=function(v) DB()[kind .. "DurationTextSize"] = v; RefreshDuration(kind) end },
                        { type="slider", label="X", min=-20, max=20, step=1,
                          get=function() return AuraDurationVal(kind, "X") end,
                          set=function(v) DB()[kind .. "DurationTextX"] = v; RefreshDuration(kind) end },
                        { type="slider", label="Y", min=-20, max=20, step=1,
                          get=function() return AuraDurationVal(kind, "Y") end,
                          set=function(v) DB()[kind .. "DurationTextY"] = v; RefreshDuration(kind) end },
                    },
                })
                local btn = CreateFrame("Button", nil, region)
                btn:SetSize(26, 26)
                btn:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -9, 0)
                region._lastInline = btn
                btn:SetFrameLevel(region:GetFrameLevel() + 5)
                btn:SetAlpha(0.4)
                local tex = btn:CreateTexture(nil, "OVERLAY")
                tex:SetAllPoints()
                tex:SetTexture(EllesmereUI.RESIZE_ICON)
                btn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                btn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                btn:SetScript("OnClick", function(self) showCog(self) end)
            end

            local durationRow1
            durationRow1, h = W:DualRow(parent, y, DurationDropdown("debuff"), DurationDropdown("buff")); y = y - h
            auraDurPosRow = durationRow1
            AttachDurationTools(durationRow1._leftRegion, "debuff")
            AttachDurationTools(durationRow1._rightRegion, "buff")

            local durationRow2
            durationRow2, h = W:DualRow(parent, y,
                DurationDropdown("cc"),
                { type="dropdown", text="Aura Stacks", values=timerPosValues,
                  getValue=function() return DBVal("auraStackTextPosition") or asFallback end,
                  setValue=function(v)
                    DB().auraStackTextPosition = v
                    LiveApplyStackPos(function(p, i) return p.debuffs[i] end, 4, v)
                    LiveApplyStackPos(function(p, i) return p.buffs[i] end, 4, v)
                    UpdatePreview()
                  end, order=timerPosOrder }); y = y - h
            auraTimerStackRow = durationRow2
            AttachDurationTools(durationRow2._leftRegion, "cc")

            -- RIGHT: Aura Stacks inline color swatch
            local rightRgn = durationRow2._rightRegion
            local asColorGet = function()
                local c = (DB() and DB().auraStackTextColor) or defaults.auraStackTextColor
                return c.r, c.g, c.b
            end
            local asColorSet = function(r, g, b)
                DB().auraStackTextColor = { r = r, g = g, b = b }
                for _, plate in pairs(plates) do
                    for i = 1, 4 do
                        if plate.debuffs[i] and plate.debuffs[i].count then
                            plate.debuffs[i].count:SetTextColor(r, g, b, 1)
                        end
                        if plate.buffs[i] and plate.buffs[i].count then
                            plate.buffs[i].count:SetTextColor(r, g, b, 1)
                        end
                    end
                end
                if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end -- 12.1 containers
                UpdatePreview()
            end
            local asSwatch, asUpdateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, asColorGet, asColorSet, nil, 20)
            PP.Point(asSwatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
            rightRgn._lastInline = asSwatch
            EllesmereUI.RegisterWidgetRefresh(function() asUpdateSwatch() end)

            -- RIGHT: Aura Stacks inline cog (Size / X / Y)
            local _, auraStackCogShow = EllesmereUI.BuildCogPopup({
                title = "Aura Stacks Settings",
                rows = {
                    { type="slider", label="Size", min=6, max=20, step=1,
                      get=function() return DBVal("auraStackTextSize") or defaults.auraStackTextSize end,
                      set=function(v)
                        DB().auraStackTextSize = v
                        for _, plate in pairs(plates) do
                            for i = 1, 4 do
                                if plate.debuffs[i] and plate.debuffs[i].count then
                                    SetFSFont(plate.debuffs[i].count, v, "OUTLINE, SLUG")
                                end
                                if plate.buffs[i] and plate.buffs[i].count then
                                    SetFSFont(plate.buffs[i].count, v, "OUTLINE, SLUG")
                                end
                            end
                        end
                        if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end -- 12.1 containers
                        UpdatePreview()
                      end },
                    { type="slider", label="X", min=-20, max=20, step=1,
                      get=function() return DBVal("auraStackTextX") or defaults.auraStackTextX end,
                      set=function(v)
                        DB().auraStackTextX = v
                        LiveApplyStackPos(function(p, i) return p.debuffs[i] end, 4, DBVal("auraStackTextPosition") or asFallback)
                        LiveApplyStackPos(function(p, i) return p.buffs[i] end, 4, DBVal("auraStackTextPosition") or asFallback)
                        UpdatePreview()
                      end },
                    { type="slider", label="Y", min=-20, max=20, step=1,
                      get=function() return DBVal("auraStackTextY") or defaults.auraStackTextY end,
                      set=function(v)
                        DB().auraStackTextY = v
                        LiveApplyStackPos(function(p, i) return p.debuffs[i] end, 4, DBVal("auraStackTextPosition") or asFallback)
                        LiveApplyStackPos(function(p, i) return p.buffs[i] end, 4, DBVal("auraStackTextPosition") or asFallback)
                        UpdatePreview()
                      end },
                },
            })
            local auraStackCogBtn = CreateFrame("Button", nil, rightRgn)
            auraStackCogBtn:SetSize(26, 26)
            auraStackCogBtn:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -9, 0)
            rightRgn._lastInline = auraStackCogBtn
            auraStackCogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            auraStackCogBtn:SetAlpha(0.4)
            local auraStackCogTex = auraStackCogBtn:CreateTexture(nil, "OVERLAY")
            auraStackCogTex:SetAllPoints()
            auraStackCogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            auraStackCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            auraStackCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            auraStackCogBtn:SetScript("OnClick", function(self) auraStackCogShow(self) end)
        end

        -- Spell Name | Spell Target -- position dropdowns (None / Left / Right /
        -- Center) styled like the duration dropdowns. The name and target may not
        -- share a side: setting one onto the side the other occupies bumps the
        -- other to None. Size / X / Y live in each row's inline cog.
        local castTextPosValues = { none = "None", left = "Left", right = "Right", center = "Center" }
        local castTextPosOrder = { "none", "left", "right", "center" }
        local spellNameRow
        spellNameRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Spell Name", values=castTextPosValues, order=castTextPosOrder,
              getValue=function() return (DB() and DB().castNameSide) or defaults.castNameSide end,
              setValue=function(v)
                DB().castNameSide = v
                if v ~= "none" then
                    local ts = (DB() and DB().castTargetSide) or defaults.castTargetSide
                    if ts == v then DB().castTargetSide = "none" end
                end
                ns.RefreshAllSettings()
                UpdatePreview()
                EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Spell Target", values=castTextPosValues, order=castTextPosOrder,
              disabled=function() return DBVal("castCombineNameTarget") == true end,
              disabledTooltip="This option requires Combine Spell Name and Target to be disabled.",
              getValue=function() return (DB() and DB().castTargetSide) or defaults.castTargetSide end,
              setValue=function(v)
                DB().castTargetSide = v
                if v ~= "none" then
                    local nss = (DB() and DB().castNameSide) or defaults.castNameSide
                    if nss == v then DB().castNameSide = "none" end
                end
                ns.RefreshAllSettings()
                UpdatePreview()
                EllesmereUI:RefreshPage()
              end })
        do
            -- LEFT: Spell Name inline color swatch
            local leftRgn = spellNameRow._leftRegion
            local snColorGet = function() return DBColor("castNameColor") end
            local snColorSet = function(r, g, b)
                DB().castNameColor = { r = r, g = g, b = b }
                for _, plate in pairs(plates) do
                    if plate.castName then plate.castName:SetTextColor(r, g, b, 1) end
                end
                UpdatePreview()
            end
            local snSwatch, snUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, snColorGet, snColorSet, nil, 20)
            PP.Point(snSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            EllesmereUI.RegisterWidgetRefresh(function() snUpdateSwatch() end)

            -- LEFT: Spell Name inline cog for X/Y offset
            do
                local snCogBtn = CreateFrame("Button", nil, leftRgn)
                snCogBtn:SetSize(26, 26)
                snCogBtn:SetPoint("RIGHT", snSwatch, "LEFT", -6, 0)
                snCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
                snCogBtn:SetAlpha(0.4)
                local snCogTex = snCogBtn:CreateTexture(nil, "OVERLAY")
                snCogTex:SetAllPoints()
                snCogTex:SetTexture(EllesmereUI.RESIZE_ICON)
                snCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                snCogBtn:SetScript("OnLeave", function(self)
                    EllesmereUI.HideWidgetTooltip()
                    if cogPopupOwner ~= self then self:SetAlpha(0.4) end
                end)
                snCogBtn:SetScript("OnClick", function(self)
                    ShowCogPopup(self, {
                        title = EllesmereUI.L("Spell Name Settings"),
                        xGet = function() return DBVal("castNameOffsetX") or defaults.castNameOffsetX end,
                        xSet = function(v) DB().castNameOffsetX = v; ns.RefreshAllSettings(); UpdatePreview() end,
                        yGet = function() return DBVal("castNameOffsetY") or defaults.castNameOffsetY end,
                        ySet = function(v) DB().castNameOffsetY = v; ns.RefreshAllSettings(); UpdatePreview() end,
                        sizeGet = function() return DBVal("castNameSize") or defaults.castNameSize end,
                        sizeSet = function(v) DB().castNameSize = v; ns.RefreshAllSettings(); UpdatePreview() end,
                        sizeMin = 6, sizeMax = 20, sizeLabel = EllesmereUI.L("Size"),
                        sizeFirst = true,
                        widthGet = function() return DBVal("castNameWidthPct") or defaults.castNameWidthPct end,
                        widthSet = function(v) DB().castNameWidthPct = v; ns.RefreshAllSettings(); UpdatePreview() end,
                        wrapGet = function() return DBVal("castNameWrap") == true end,
                        wrapSet = function(v) DB().castNameWrap = v; ns.RefreshAllSettings(); UpdatePreview() end,
                        toggleLabel = "Combine Spell Name and Target",
                        toggleGet = function() return DBVal("castCombineNameTarget") == true end,
                        toggleSet = function(v)
                            DB().castCombineNameTarget = v
                            ns.RefreshAllSettings()
                            UpdatePreview()
                            EllesmereUI:RefreshPage()
                        end,
                    })
                end)
                EllesmereUI.RegisterWidgetRefresh(function()
                    snCogBtn:SetAlpha(cogPopupOwner == snCogBtn and 0.7 or 0.4)
                end)
            end

            -- RIGHT: Spell Target inline double swatch (custom + class colored)
            local rightRgn = spellNameRow._rightRegion
            local ctrl = rightRgn._control

            -- Class colored swatch (rightmost)
            local ccGet = function()
                local _, ct = UnitClass("player")
                if ct and RAID_CLASS_COLORS[ct] then
                    local cc = RAID_CLASS_COLORS[ct]
                    return cc.r, cc.g, cc.b
                end
                return 1, 1, 1
            end
            local ccSwatch, ccUpdate = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, ccGet, function() end, nil, 20)
            PP.Point(ccSwatch, "RIGHT", ctrl, "LEFT", -12, 0)
            ccSwatch:SetScript("OnClick", function()
                DB().castTargetClassColor = true
                for _, plate in pairs(plates) do plate:UpdateHealth() end
                UpdatePreview()
                EllesmereUI:RefreshPage()
            end)
            ccSwatch:SetScript("OnEnter", function() if EllesmereUI.ShowWidgetTooltip then EllesmereUI.ShowWidgetTooltip(ccSwatch, "Class Color") end end)
            ccSwatch:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)

            -- Custom color swatch (to the left of class swatch)
            local stColorGet = function() return DBColor("castTargetColor") end
            local stColorSet = function(r, g, b)
                DB().castTargetColor = { r = r, g = g, b = b }
                for _, plate in pairs(plates) do plate:UpdateHealth() end
                UpdatePreview()
            end
            local stSwatch, stUpdate = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, stColorGet, stColorSet, nil, 20)
            PP.Point(stSwatch, "RIGHT", ccSwatch, "LEFT", -9, 0)
            stSwatch._eabOrigClick = stSwatch:GetScript("OnClick")
            stSwatch:SetScript("OnClick", function(self)
                local db = DB()
                local cc = db and db.castTargetClassColor
                if cc == nil then cc = defaults.castTargetClassColor end
                if cc then
                    DB().castTargetClassColor = false
                    for _, plate in pairs(plates) do plate:UpdateHealth() end
                    UpdatePreview()
                    EllesmereUI:RefreshPage()
                    return
                end
                if self._eabOrigClick then self._eabOrigClick(self) end
            end)
            stSwatch:SetScript("OnEnter", function() if EllesmereUI.ShowWidgetTooltip then EllesmereUI.ShowWidgetTooltip(stSwatch, "Custom Color") end end)
            stSwatch:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)

            EllesmereUI.RegisterWidgetRefresh(function()
                local db = DB()
                local isCC = db and db.castTargetClassColor
                if isCC == nil then isCC = defaults.castTargetClassColor end
                stSwatch:SetAlpha(isCC and 0.3 or 1)
                ccSwatch:SetAlpha(isCC and 1 or 0.3)
                stUpdate()
                ccUpdate()
            end)
            local isCC = (DB() and DB().castTargetClassColor)
            if isCC == nil then isCC = defaults.castTargetClassColor end
            stSwatch:SetAlpha(isCC and 0.3 or 1)
            ccSwatch:SetAlpha(isCC and 1 or 0.3)

            -- RIGHT: Spell Target inline cog for X/Y offset
            do
                local stCogBtn = CreateFrame("Button", nil, rightRgn)
                stCogBtn:SetSize(26, 26)
                stCogBtn:SetPoint("RIGHT", stSwatch, "LEFT", -6, 0)
                stCogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
                stCogBtn:SetAlpha(0.4)
                local stCogTex = stCogBtn:CreateTexture(nil, "OVERLAY")
                stCogTex:SetAllPoints()
                stCogTex:SetTexture(EllesmereUI.RESIZE_ICON)
                stCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                stCogBtn:SetScript("OnLeave", function(self)
                    EllesmereUI.HideWidgetTooltip()
                    if cogPopupOwner ~= self then self:SetAlpha(0.4) end
                end)
                stCogBtn:SetScript("OnClick", function(self)
                    ShowCogPopup(self, {
                        title = EllesmereUI.L("Spell Target Settings"),
                        xGet = function() return DBVal("castTargetOffsetX") or defaults.castTargetOffsetX end,
                        xSet = function(v) DB().castTargetOffsetX = v; ns.RefreshAllSettings(); UpdatePreview() end,
                        yGet = function() return DBVal("castTargetOffsetY") or defaults.castTargetOffsetY end,
                        ySet = function(v) DB().castTargetOffsetY = v; ns.RefreshAllSettings(); UpdatePreview() end,
                        sizeGet = function() return DBVal("castTargetSize") or defaults.castTargetSize end,
                        sizeSet = function(v) DB().castTargetSize = v; ns.RefreshAllSettings(); UpdatePreview() end,
                        sizeMin = 6, sizeMax = 20, sizeLabel = EllesmereUI.L("Size"),
                        sizeFirst = true,
                        widthGet = function() return DBVal("castTargetWidthPct") or defaults.castTargetWidthPct end,
                        widthSet = function(v) DB().castTargetWidthPct = v; ns.RefreshAllSettings(); UpdatePreview() end,
                        wrapGet = function() return DBVal("castTargetWrap") == true end,
                        wrapSet = function(v) DB().castTargetWrap = v; ns.RefreshAllSettings(); UpdatePreview() end,
                    })
                end)
                EllesmereUI.RegisterWidgetRefresh(function()
                    stCogBtn:SetAlpha(cogPopupOwner == stCogBtn and 0.7 or 0.4)
                end)
            end
        end
        y = y - h

        -----------------------------------------------------------------------
        --  CLICK NAVIGATION: glow, scroll, mapping, hit overlays
        -----------------------------------------------------------------------
        local glowFrame
        local function PlaySettingGlow(targetFrame)
            if not targetFrame then return end
            if not glowFrame then
                glowFrame = CreateFrame("Frame")
                local c = EllesmereUI.ELLESMERE_GREEN
                local function MkEdge()
                    local t = glowFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                    t:SetColorTexture(c.r, c.g, c.b, 1)
                    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
                    return t
                end
                glowFrame._top = MkEdge()
                glowFrame._bot = MkEdge()
                glowFrame._lft = MkEdge()
                glowFrame._rgt = MkEdge()
                local glowPx = PP.Scale(2)
                glowFrame._top:SetHeight(glowPx)
                glowFrame._top:SetPoint("TOPLEFT"); glowFrame._top:SetPoint("TOPRIGHT")
                glowFrame._bot:SetHeight(glowPx)
                glowFrame._bot:SetPoint("BOTTOMLEFT"); glowFrame._bot:SetPoint("BOTTOMRIGHT")
                glowFrame._lft:SetWidth(glowPx)
                glowFrame._lft:SetPoint("TOPLEFT", glowFrame._top, "BOTTOMLEFT")
                glowFrame._lft:SetPoint("BOTTOMLEFT", glowFrame._bot, "TOPLEFT")
                glowFrame._rgt:SetWidth(glowPx)
                glowFrame._rgt:SetPoint("TOPRIGHT", glowFrame._top, "BOTTOMRIGHT")
                glowFrame._rgt:SetPoint("BOTTOMRIGHT", glowFrame._bot, "TOPRIGHT")
            end
            glowFrame:SetParent(targetFrame)
            glowFrame:SetAllPoints(targetFrame)
            glowFrame:SetFrameLevel(targetFrame:GetFrameLevel() + 5)
            glowFrame:SetAlpha(1)
            glowFrame:Show()
            local elapsed = 0
            glowFrame:SetScript("OnUpdate", function(self, dt)
                elapsed = elapsed + dt
                if elapsed >= 0.75 then
                    self:Hide(); self:SetScript("OnUpdate", nil); return
                end
                self:SetAlpha(1 - elapsed / 0.75)
            end)
        end

        -- Maps Core Position slot keys to their row/region
        local corePosToRow = {
            top      = { row = coreRow1, side = "_leftRegion" },
            right    = { row = coreRow1, side = "_rightRegion" },
            left     = { row = coreRow2, side = "_leftRegion" },
            topright = { row = coreRow2, side = "_rightRegion" },
            topleft  = { row = coreRow3, side = "_leftRegion" },
        }

        -- Maps Core Text Position slot keys to their row/region
        local textSlotToRow = {
            textSlotTop    = { row = textRow1, side = "_leftRegion" },
            textSlotRight  = { row = textRow1, side = "_rightRegion" },
            textSlotLeft   = { row = textRow2, side = "_leftRegion" },
            textSlotCenter = { row = textRow2, side = "_rightRegion" },
        }

        -- Reverse lookup: find which Core Position slot holds a given element
        local function FindCorePosForElement(element)
            local db = DB()
            local key = elementToKey[element]
            if not key then return nil end
            local pos = db[key] or defaults[key]
            if pos == "none" then return nil end
            return pos
        end

        -- Reverse lookup: find which text slot holds a given element
        local function FindTextSlotForElement(element)
            local db = DB()
            for _, key in ipairs(textSlotKeys) do
                if (db[key] or defaults[key]) == element then return key end
            end
            return nil
        end

        -- Resolve a dynamic click mapping for icon elements Core Positions row
        local function ResolveCoreMapping(element)
            local pos = FindCorePosForElement(element)
            if not pos then return { section = coreHeader, target = coreRow1 } end
            local info = corePosToRow[pos]
            if not info then return { section = coreHeader, target = coreRow1 } end
            return { section = coreHeader, target = info.row, slotSide = (info.side == "_leftRegion") and "left" or "right" }
        end

        -- Resolve a dynamic click mapping for text elements Core Text Positions row
        local function ResolveTextMapping(element)
            local slotKey = FindTextSlotForElement(element)
            if not slotKey then return { section = coreTextHeader, target = textRow1 } end
            local info = textSlotToRow[slotKey]
            if not info then return { section = coreTextHeader, target = textRow1 } end
            return { section = coreTextHeader, target = info.row, slotSide = (info.side == "_leftRegion") and "left" or "right" }
        end

        local clickMappings = {
            debuffDuration = { section = generalTextHeader, target = auraDurPosRow,      slotSide = "left" },
            buffDuration = { section = generalTextHeader,   target = auraDurPosRow,      slotSide = "right" },
            ccDuration = { section = generalTextHeader,     target = auraTimerStackRow,  slotSide = "left" },
            auraStack    = { section = generalTextHeader,  target = auraTimerStackRow,   slotSide = "right" },
            castBar      = { section = healthBarHeader,  target = castBarHeightRow,    slotSide = "left" },
            castIcon     = { section = healthBarHeader,  target = showCastIconRow,     slotSide = "right" },
            castTimer    = { section = healthBarHeader,  target = castTimerRow,        slotSide = "left" },
            castName     = { section = generalTextHeader, target = spellNameRow,        slotSide = "left" },
            castTarget   = { section = generalTextHeader, target = spellNameRow,        slotSide = "right" },
            healthBar    = { section = healthBarHeader,  target = healthBarHeightRow },
            classResource = { section = classResourceHeader, target = classResourceSection },
            targetArrows = { section = tfxHeader,            target = targetGlowRow,       slotSide = "right" },
        }

        -- Dynamic resolvers for elements assigned to Core Positions / Core Text Positions
        local dynamicMappings = {
            debuffIcon   = function() return ResolveCoreMapping("debuffs") end,
            buffIcon     = function() return ResolveCoreMapping("buffs") end,
            ccIcon       = function() return ResolveCoreMapping("ccs") end,
            raidMarker   = function() return ResolveCoreMapping("raidmarker") end,
            classIcon    = function() return ResolveCoreMapping("classification") end,
            enemyName    = function() return ResolveTextMapping("enemyName") end,
            healthText   = function()
                local slot = FindTextSlotForElement("healthPercent") or FindTextSlotForElement("healthPercentNoSign") or FindTextSlotForElement("healthNumber") or FindTextSlotForElement("healthPctNum") or FindTextSlotForElement("healthNumPct") or FindTextSlotForElement("healthPctNumDash") or FindTextSlotForElement("healthNumPctDash")
                if not slot then return { section = coreTextHeader, target = textRow1 } end
                local info = textSlotToRow[slot]
                if not info then return { section = coreTextHeader, target = textRow1 } end
                return { section = coreTextHeader, target = info.row, slotSide = (info.side == "_leftRegion") and "left" or "right" }
            end,
        }

        local function NavigateToSetting(key)
            local m = clickMappings[key]
            -- Check dynamic mappings (icon/text elements assigned to Core Positions)
            if not m then
                local resolver = dynamicMappings[key]
                if resolver then m = resolver() end
            end
            if not m or not m.section or not m.target then return end

            -- Dismiss the hint text on first click (fade out over 0.3s using ticker)
            if not IsPreviewHintDismissed() and _previewHintFS and _previewHintFS:IsShown() then
                EllesmereUIDB = EllesmereUIDB or {}
                EllesmereUIDB.previewHintDismissed = true
                local hint = _previewHintFS
                local _, anchorTo, _, _, startY = hint:GetPoint(1)
                startY = startY or 17
                anchorTo = anchorTo or hint:GetParent()
                local startHeaderH = _headerBaseH + 29
                local targetHeaderH = _headerBaseH
                local steps = 0
                local ticker
                ticker = C_Timer.NewTicker(0.016, function()
                    steps = steps + 1
                    local progress = steps * 0.016 / 0.3
                    if progress >= 1 then
                        hint:Hide()
                        ticker:Cancel()
                        if targetHeaderH > 0 then
                            EllesmereUI:SetContentHeaderHeightSilent(targetHeaderH)
                        end
                        return
                    end
                    hint:SetAlpha(0.45 * (1 - progress))
                    hint:ClearAllPoints()
                    hint:SetPoint("BOTTOM", anchorTo, "BOTTOM", 0, startY + progress * 12)
                    local h = startHeaderH - 39 * progress
                    if h > 0 then
                        EllesmereUI:SetContentHeaderHeightSilent(h)
                    end
                end)
            end

            local sf = EllesmereUI._scrollFrame
            if not sf then return end
            local _, _, _, _, headerY = m.section:GetPoint(1)
            if not headerY then return end
            local scrollPos = math.max(0, math.abs(headerY) - 40)
            EllesmereUI.SmoothScrollTo(scrollPos)
            local glowTarget = m.target
            if m.slotSide and m.target then
                local region = (m.slotSide == "left") and m.target._leftRegion or m.target._rightRegion
                if region then glowTarget = region end
            end
            C_Timer.After(0.15, function() PlaySettingGlow(glowTarget) end)
        end

        -- Hit overlay factory for preview elements
        -- opts (optional table):
        --   hlAnchor     = frame draw highlight around this frame instead of btn
        --   hlBehindText = true  draw highlight on a child frame at icon level + 1
        --                          (text lives on a child frame at icon level + 2)
        local function SnapPreview(val)
            local s = activePreview and activePreview:GetEffectiveScale() or 1
            if s <= 0 then s = 1 end
            return math.floor(val * s + 0.5) / s
        end
        -- Destroy any stale hit overlays from a previous BuildDisplayPage call
        -- (RefreshPage can re-call buildPage without cleaning the preview).
        if activePreview and activePreview._hitOverlays then
            for i = 1, #activePreview._hitOverlays do
                local ov = activePreview._hitOverlays[i]
                ov:EnableMouse(false)
                ov:Hide()
                ov:SetParent(nil)
            end
            wipe(activePreview._hitOverlays)
        end

        local allOverlays = {}

        local function CreateHitOverlay(element, mappingKey, isText, frameLevelOverride, opts)
            local anchor = isText and element:GetParent() or element
            -- If the element is a Texture (not a Frame), parent to its owner frame
            if not anchor.CreateTexture then anchor = anchor:GetParent() end
            local btn = CreateFrame("Button", nil, anchor)
            if isText then
                -- For FontStrings: dynamically size to the actual rendered text
                local function ResizeToText()
                    local ok, tw, th = pcall(function()
                        local w = element:GetStringWidth() or 0
                        local h = element:GetStringHeight() or 0
                        if w < 4 then w = 4 end
                        if h < 4 then h = 4 end
                        return w, h
                    end)
                    if not ok then tw = 40; th = 12 end
                    btn:SetSize(tw + 4, th + 4)
                end
                ResizeToText()
                -- Anchor to the FontString's justification point
                local justify = element:GetJustifyH()
                if justify == "RIGHT" then
                    btn:SetPoint("RIGHT", element, "RIGHT", 2, 0)
                elseif justify == "CENTER" then
                    btn:SetPoint("CENTER", element, "CENTER", 0, 0)
                else
                    btn:SetPoint("LEFT", element, "LEFT", -2, 0)
                end
                -- Re-measure on every show so size tracks font/text changes
                btn:SetScript("OnShow", function() ResizeToText() end)
                btn._resizeToText = ResizeToText
            else
                btn:SetAllPoints(opts and opts.hlAnchor or element)
            end
            btn:SetFrameLevel(frameLevelOverride or (anchor:GetFrameLevel() + 20))
            btn:RegisterForClicks("LeftButtonDown")
            local c = EllesmereUI.ELLESMERE_GREEN
            local PP = EllesmereUI.PP
            -- When hlBehindText is set, attach the border to a dedicated child frame
            -- at icon level + 1 so it sits between the icon artwork and text layers.
            -- Always use a child container so the hover border doesn't conflict
            -- with any existing PP border on the target frame.
            local behindText = opts and opts.hlBehindText
            local hlBase
            if behindText then
                local hlFrame = CreateFrame("Frame", nil, element)
                hlFrame:SetAllPoints()
                hlFrame:SetFrameLevel(element:GetFrameLevel() + 1)
                hlBase = hlFrame
            else
                hlBase = (opts and opts.hlAnchor) or btn
            end
            local hlCont = CreateFrame("Frame", nil, hlBase)
            hlCont:SetAllPoints()
            hlCont:SetFrameLevel(hlBase:GetFrameLevel() + 1)
            local brd = PP.CreateBorder(hlCont, c.r, c.g, c.b, 1, 2, "OVERLAY", 7)
            brd:Hide()
            btn:SetScript("OnEnter", function() brd:Show() end)
            btn:SetScript("OnLeave", function() brd:Hide() end)
            btn:SetScript("OnMouseDown", function() NavigateToSetting(mappingKey) end)
            allOverlays[#allOverlays + 1] = btn
            if hlBase ~= btn then allOverlays[#allOverlays + 1] = hlBase end
            allOverlays[#allOverlays + 1] = hlCont
            return btn
        end

        -- Create hit overlays for all interactive preview elements
        local textOverlays = {}  -- collect text overlays for size refresh
        if activePreview then
            local pv = activePreview
            -- Icon overlays need to be above the icon frames (which are at health:GetFrameLevel() + 8)
            local iconLevel = (pv._health and pv._health:GetFrameLevel() or 20) + 15
            -- Text overlays on icons need to be above the icon overlays
            local textOnIconLevel = iconLevel + 10
            -- Aura icons (all debuffs, buffs, ccs)
            local iconHlOpts = { hlBehindText = true }
            if pv._ccs then
                for i = 1, #pv._ccs do
                    if pv._ccs[i] then
                        CreateHitOverlay(pv._ccs[i], "ccIcon", false, iconLevel, iconHlOpts)
                        if pv._ccs[i].durationText then
                            local ov = CreateHitOverlay(pv._ccs[i].durationText, "ccDuration", true, textOnIconLevel)
                            textOverlays[#textOverlays + 1] = ov
                        end
                    end
                end
            end
            if pv._buffs then
                for i = 1, #pv._buffs do
                    if pv._buffs[i] then
                        CreateHitOverlay(pv._buffs[i], "buffIcon", false, iconLevel, iconHlOpts)
                        if pv._buffs[i].durationText then
                            local ov = CreateHitOverlay(pv._buffs[i].durationText, "buffDuration", true, textOnIconLevel)
                            textOverlays[#textOverlays + 1] = ov
                        end
                    end
                end
            end
            if pv._debuffs then
                for i = 1, #pv._debuffs do
                    if pv._debuffs[i] then
                        CreateHitOverlay(pv._debuffs[i], "debuffIcon", false, iconLevel, iconHlOpts)
                        if pv._debuffs[i].durationText then
                            local ov = CreateHitOverlay(pv._debuffs[i].durationText, "debuffDuration", true, textOnIconLevel)
                            textOverlays[#textOverlays + 1] = ov
                        end
                        if pv._debuffs[i].stackText then
                            local ov = CreateHitOverlay(pv._debuffs[i].stackText, "auraStack", true, textOnIconLevel)
                            textOverlays[#textOverlays + 1] = ov
                        end
                    end
                end
            end
            -- Cast icon overlay (separate from cast bar navigates to Show Spell Icon row)
            local castOverlayLevel
            if pv._cast then
                castOverlayLevel = pv._cast:GetFrameLevel() + 20
                local cc = EllesmereUI.ELLESMERE_GREEN
                -- Cast icon overlay
                if pv._castIconFrame then
                    local iconOv = CreateFrame("Button", nil, pv._cast:GetParent())
                    iconOv:SetAllPoints(pv._castIconFrame)
                    iconOv:SetFrameLevel(castOverlayLevel)
                    iconOv:RegisterForClicks("LeftButtonDown")
                    local ioBrd = EllesmereUI.PP.CreateBorder(iconOv, cc.r, cc.g, cc.b, 1, 2, "OVERLAY", 7)
                    ioBrd:Hide()
                    iconOv:SetScript("OnEnter", function() ioBrd:Show() end)
                    iconOv:SetScript("OnLeave", function() ioBrd:Hide() end)
                    iconOv:SetScript("OnMouseDown", function() NavigateToSetting("castIcon") end)
                    allOverlays[#allOverlays + 1] = iconOv
                end
                -- Cast bar overlay (bar only, not icon)
                local castOverlay = CreateFrame("Button", nil, pv._cast:GetParent())
                castOverlay:SetAllPoints(pv._cast)
                castOverlay:SetFrameLevel(castOverlayLevel)
                castOverlay:RegisterForClicks("LeftButtonDown")
                local coBrd = EllesmereUI.PP.CreateBorder(castOverlay, cc.r, cc.g, cc.b, 1, 2, "OVERLAY", 7)
                coBrd:Hide()
                castOverlay:SetScript("OnEnter", function() coBrd:Show() end)
                castOverlay:SetScript("OnLeave", function() coBrd:Hide() end)
                castOverlay:SetScript("OnMouseDown", function() NavigateToSetting("castBar") end)
                allOverlays[#allOverlays + 1] = castOverlay
            end
            -- Cast spell name and target text (above the cast bar overlay)
            local castTextLevel = (castOverlayLevel or 30) + 5
            if pv._castNameFS and pv._castNameFS:IsShown() then
                local ov = CreateHitOverlay(pv._castNameFS, "castName", true, castTextLevel)
                textOverlays[#textOverlays + 1] = ov
            end
            if pv._castTargetFS and pv._castTargetFS:IsShown() then
                local ov = CreateHitOverlay(pv._castTargetFS, "castTarget", true, castTextLevel)
                textOverlays[#textOverlays + 1] = ov
            end
            if pv._castTimerFS and pv._castTimerFS:IsShown() then
                local ov = CreateHitOverlay(pv._castTimerFS, "castTimer", true, castTextLevel)
                textOverlays[#textOverlays + 1] = ov
            end
            -- Enemy name text
            if pv._nameFS then
                local ov = CreateHitOverlay(pv._nameFS, "enemyName", true)
                textOverlays[#textOverlays + 1] = ov
            end
            -- Health text
            if pv._hpText then
                local ov = CreateHitOverlay(pv._hpText, "healthText", true)
                textOverlays[#textOverlays + 1] = ov
            end
            -- Health bar
            if pv._health then
                CreateHitOverlay(pv._health, "healthBar")
            end
            -- Raid marker
            local raidOverlay
            if pv._raidFrame then
                raidOverlay = CreateHitOverlay(pv._raidFrame, "raidMarker")
                if not showRaidMarkerPreview then raidOverlay:Hide() end
            end
            -- Rare/elite icon
            local classOverlay
            if pv._classIcon then
                classOverlay = CreateHitOverlay(pv._classIcon, "classIcon")
                if not showClassificationPreview then classOverlay:Hide() end
            end
            -- Class resource pips wrapper button spanning all visible pips
            local cpOverlay
            if pv._cpPips then
                local firstVis, lastVis
                for i = 1, pv._cpMax do
                    if pv._cpPips[i] and pv._cpPips[i]:IsShown() then
                        if not firstVis then firstVis = pv._cpPips[i] end
                        lastVis = pv._cpPips[i]
                    end
                end
                -- Bar-type resource: use the bar frame as anchor
                local useBar = (not firstVis) and pv._cpBar and pv._cpBar:IsShown()
                local anchorFirst = firstVis or (useBar and pv._cpBar)
                local anchorLast  = lastVis  or (useBar and pv._cpBar)
                if anchorFirst and anchorLast then
                    local cpBtn = CreateFrame("Button", nil, pv)
                    cpBtn:SetPoint("TOPLEFT", anchorFirst, "TOPLEFT", -2, 2)
                    cpBtn:SetPoint("BOTTOMRIGHT", anchorLast, "BOTTOMRIGHT", 2, -2)
                    cpBtn:SetFrameLevel((pv._health and pv._health:GetFrameLevel() or 20) + 15)
                    cpBtn:RegisterForClicks("LeftButtonDown")
                    local cc = EllesmereUI.ELLESMERE_GREEN
                    local function MkCPHL()
                        local t = cpBtn:CreateTexture(nil, "OVERLAY", nil, 7)
                        t:SetColorTexture(cc.r, cc.g, cc.b, 1)
                        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
                        return t
                    end
                    local cpPx = SnapPreview(2)
                    local cpt = MkCPHL(); cpt:SetHeight(cpPx); cpt:SetPoint("TOPLEFT"); cpt:SetPoint("TOPRIGHT")
                    local cpb = MkCPHL(); cpb:SetHeight(cpPx); cpb:SetPoint("BOTTOMLEFT"); cpb:SetPoint("BOTTOMRIGHT")
                    local cpl = MkCPHL(); cpl:SetWidth(cpPx); cpl:SetPoint("TOPLEFT", cpt, "BOTTOMLEFT"); cpl:SetPoint("BOTTOMLEFT", cpb, "TOPLEFT")
                    local cpr = MkCPHL(); cpr:SetWidth(cpPx); cpr:SetPoint("TOPRIGHT", cpt, "BOTTOMRIGHT"); cpr:SetPoint("BOTTOMRIGHT", cpb, "TOPRIGHT")
                    cpBtn._hlTextures = { cpt, cpb, cpl, cpr }
                    local function ShowCPHL() for _, t in ipairs(cpBtn._hlTextures) do t:Show() end end
                    local function HideCPHL() for _, t in ipairs(cpBtn._hlTextures) do t:Hide() end end
                    HideCPHL()
                    cpBtn:SetScript("OnEnter", function() ShowCPHL() end)
                    cpBtn:SetScript("OnLeave", function() HideCPHL() end)
                    cpBtn:SetScript("OnMouseDown", function() NavigateToSetting("classResource") end)
                    cpOverlay = cpBtn
                    allOverlays[#allOverlays + 1] = cpBtn
                    -- Disable hover/click when class resource setting is off
                    local function UpdateCPOverlay()
                        local off = DBVal("showClassPower") ~= true
                        cpBtn:EnableMouse(not off)
                        cpBtn:SetAlpha(off and 0 or 1)
                    end
                    EllesmereUI.RegisterWidgetRefresh(UpdateCPOverlay)
                    UpdateCPOverlay()
                end
            end
            -- Sync overlay visibility with preview toggles
            pv._raidOverlay = raidOverlay
            pv._classOverlay = classOverlay
            -- Target arrows wrapper button spanning both arrow textures
            local arrowOverlay
            if pv._arrows then
                local arrowBtn = CreateFrame("Button", nil, pv)
                arrowBtn:SetPoint("TOPLEFT", pv._arrows.left, "TOPLEFT", -2, 2)
                arrowBtn:SetPoint("BOTTOMRIGHT", pv._arrows.right, "BOTTOMRIGHT", 2, -2)
                arrowBtn:SetFrameLevel((pv._health and pv._health:GetFrameLevel() or 20) + 15)
                arrowBtn:RegisterForClicks("LeftButtonDown")
                local cc = EllesmereUI.ELLESMERE_GREEN
                local function MkAHL()
                    local t = arrowBtn:CreateTexture(nil, "OVERLAY", nil, 7)
                    t:SetColorTexture(cc.r, cc.g, cc.b, 1)
                    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
                    return t
                end
                -- Highlight on left arrow
                local aPx = SnapPreview(2)
                local alt = MkAHL(); alt:SetHeight(aPx); alt:SetPoint("TOPLEFT", pv._arrows.left, -2, 2); alt:SetPoint("TOPRIGHT", pv._arrows.left, 2, 2)
                local alb = MkAHL(); alb:SetHeight(aPx); alb:SetPoint("BOTTOMLEFT", pv._arrows.left, -2, -2); alb:SetPoint("BOTTOMRIGHT", pv._arrows.left, 2, -2)
                local all = MkAHL(); all:SetWidth(aPx); all:SetPoint("TOPLEFT", alt, "BOTTOMLEFT"); all:SetPoint("BOTTOMLEFT", alb, "TOPLEFT")
                local alr = MkAHL(); alr:SetWidth(aPx); alr:SetPoint("TOPRIGHT", alt, "BOTTOMRIGHT"); alr:SetPoint("BOTTOMRIGHT", alb, "TOPRIGHT")
                -- Highlight on right arrow
                local art = MkAHL(); art:SetHeight(aPx); art:SetPoint("TOPLEFT", pv._arrows.right, -2, 2); art:SetPoint("TOPRIGHT", pv._arrows.right, 2, 2)
                local arb = MkAHL(); arb:SetHeight(aPx); arb:SetPoint("BOTTOMLEFT", pv._arrows.right, -2, -2); arb:SetPoint("BOTTOMRIGHT", pv._arrows.right, 2, -2)
                local arl = MkAHL(); arl:SetWidth(aPx); arl:SetPoint("TOPLEFT", art, "BOTTOMLEFT"); arl:SetPoint("BOTTOMLEFT", arb, "TOPLEFT")
                local arr = MkAHL(); arr:SetWidth(aPx); arr:SetPoint("TOPRIGHT", art, "BOTTOMRIGHT"); arr:SetPoint("BOTTOMRIGHT", arb, "TOPRIGHT")
                arrowBtn._hlTextures = { alt, alb, all, alr, art, arb, arl, arr }
                local function ShowAHL() for _, t in ipairs(arrowBtn._hlTextures) do t:Show() end end
                local function HideAHL() for _, t in ipairs(arrowBtn._hlTextures) do t:Hide() end end
                HideAHL()
                arrowBtn:SetScript("OnEnter", function() ShowAHL() end)
                arrowBtn:SetScript("OnLeave", function() HideAHL() end)
                arrowBtn:SetScript("OnMouseDown", function() NavigateToSetting("targetArrows") end)
                -- Only show when arrows are visible
                if not pv._arrows.left:IsShown() then arrowBtn:Hide() end
                arrowOverlay = arrowBtn
                allOverlays[#allOverlays + 1] = arrowBtn
            end
            pv._arrowOverlay = arrowOverlay
            -- Store text overlays for size refresh on preview update
            pv._textOverlays = textOverlays
            -- Store all overlays for cleanup on next rebuild
            pv._hitOverlays = allOverlays
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Colors page
    ---------------------------------------------------------------------------

    -- Shuffled spell icon pool for cast bar previews (reset each time Colors tab opens)
    local castIconPool = { 136197, 236802, 135808, 136116, 135735, 136048, 135812, 136075 }
    local castIconIdx = 0
    local function ShuffleCastIcons()
        castIconIdx = 0
        for i = #castIconPool, 2, -1 do
            local j = math.random(i)
            castIconPool[i], castIconPool[j] = castIconPool[j], castIconPool[i]
        end
    end
    local function NextCastIcon()
        castIconIdx = castIconIdx + 1
        if castIconIdx > #castIconPool then castIconIdx = 1 end
        return castIconPool[castIconIdx]
    end

    -- Cast fill values: each at least 5% apart, range 40 90%
    local castFillUsed = {}
    local function ResetCastFills()
        for i = #castFillUsed, 1, -1 do castFillUsed[i] = nil end
    end
    local function NextCastFill()
        for _ = 1, 50 do
            local v = 0.40 + math.random() * 0.20
            local ok = true
            for _, prev in ipairs(castFillUsed) do
                if math.abs(v - prev) < 0.05 then ok = false; break end
            end
            if ok then
                castFillUsed[#castFillUsed + 1] = v
                return v
            end
        end
        -- fallback if somehow can't find a valid value
        local v = 0.40 + math.random() * 0.20
        castFillUsed[#castFillUsed + 1] = v
        return v
    end

    -- Mini preview bar builder for color swatches
    -- type: "health" or "cast" or "castLocked"
    -- colorKey: DB key for the bar color (read live)
    -- parentRow: the frame to attach to (ColorPicker row or DualRow half-region)
    -- anchorFrame: optional override anchor (e.g. DualRow half-region for positioning)
    local function MakeColorPreviewBar(parentRow, colorType, colorKey, anchorFrame)
        local MEDIA = "Interface\\AddOns\\EllesmereUINameplates\\Media\\"
        local isHalf = anchorFrame and true or false
        local BAR_W = isHalf and 161 or 180
        local BAR_H = 20
        local SWATCH_SZ = 24
        local SWATCH_GAP = isHalf and 27 or 52
        local fontPath = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("nameplates")) or DBVal("font")
        local anchor = anchorFrame or parentRow

        local container = CreateFrame("Frame", nil, parentRow)
        PP.Size(container, BAR_W + 2, BAR_H + 2)  -- +2 for border
        -- Position: to the left of the swatch (swatch is at RIGHT -SIDE_PAD, 24px wide)
        PP.Point(container, "RIGHT", anchor, "RIGHT", -(20 + SWATCH_SZ + SWATCH_GAP), 0)
        container:SetFrameLevel(parentRow:GetFrameLevel() + 2)

        -- Simple 1px solid border using the user's nameplate border color.
        -- Uses two-point anchoring for pixel-perfect rendering inside the scroll frame.
        local function MakePreviewBorder(parent)
            local bc = (DB() and DB().borderColor) or defaults.borderColor
            local edges = {}
            local function mkE()
                local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
                t:SetColorTexture(bc.r, bc.g, bc.b, 1)
                edges[#edges + 1] = t
                return t
            end
            local t = mkE(); t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(1)
            local b = mkE(); b:SetPoint("BOTTOMLEFT"); b:SetPoint("BOTTOMRIGHT"); b:SetHeight(1)
            local l = mkE(); l:SetPoint("TOPLEFT", t, "BOTTOMLEFT"); l:SetPoint("BOTTOMLEFT", b, "TOPLEFT"); l:SetWidth(1)
            local r = mkE(); r:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT"); r:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT"); r:SetWidth(1)
            return edges
        end

        if colorType == "health" then
            -- Health bar preview: random fill 60-75%, colored by the swatch color
            local FAKE_MAX_HP = 10000
            local healthPct = math.floor(60 + math.random() * 15)
            local healthVal = math.floor(FAKE_MAX_HP * healthPct / 100)

            local health = CreateFrame("StatusBar", nil, container)
            health:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            health:SetMinMaxValues(0, 100)
            health:SetValue(healthPct)
            health:SetAllPoints()

            local bg = health:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.20, 0.20, 0.20, 1.0)

            -- 1px solid border on a dedicated frame ABOVE the health StatusBar
            -- so the border renders on top (child frames cover parent textures).
            -- Parented to container (not health) so it stays at full opacity
            -- when the health bar is dimmed via SetDisabled.
            local brdFrame = CreateFrame("Frame", nil, container)
            brdFrame:SetAllPoints()
            brdFrame:SetFrameLevel(health:GetFrameLevel() + 2)
            local brdEdges = MakePreviewBorder(brdFrame)
            container._brdEdges = brdEdges
            container._health = health  -- exposed for proxy color override / dimming

            -- Always create both FontStrings (shown/hidden dynamically)
            -- Parent them to a text frame ABOVE the overlay clips so focus
            -- texture never covers the health numbers.
            local textFrame = CreateFrame("Frame", nil, health)
            textFrame:SetAllPoints()
            textFrame:SetFrameLevel(health:GetFrameLevel() + 3)

            local pctFS = textFrame:CreateFontString(nil, "OVERLAY")
            local initHpSz = 10
            SetPVFont(pctFS, fontPath, initHpSz, GetNPOptOutline())
            pctFS:Hide()

            local numFS = textFrame:CreateFontString(nil, "OVERLAY")
            SetPVFont(numFS, fontPath, initHpSz, GetNPOptOutline())
            numFS:Hide()

            -- Full refresh: re-reads DB settings, repositions, updates text & values
            local function RefreshHealthText()
                local hpFS = 10
                -- Use the largest text slot size (capped at 13 for mini bars)
                for _, sk in ipairs({"textSlotRight", "textSlotLeft", "textSlotCenter"}) do
                    local el = DBVal(sk) or defaults[sk]
                    if el and el ~= "none" and el ~= "enemyName" then
                        hpFS = math.min(DBVal(sk .. "Size") or defaults[sk .. "Size"] or 10, 13)
                        break
                    end
                end
                local curFont = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("nameplates")) or DBVal("font")
                local curOutline = GetNPOptOutline()

                -- Hide both FontStrings first
                SetPVFont(pctFS, curFont, hpFS, curOutline)
                pctFS:ClearAllPoints()
                pctFS:Hide()
                SetPVFont(numFS, curFont, hpFS, curOutline)
                numFS:ClearAllPoints()
                numFS:Hide()

                -- Bar slots: show health text based on slot assignments
                local barSlots = {
                    { key = "textSlotRight",  anchor = "RIGHT",  xOff = -2 },
                    { key = "textSlotLeft",   anchor = "LEFT",   xOff = 2 },
                    { key = "textSlotCenter", anchor = "CENTER", xOff = 0 },
                }
                for _, slot in ipairs(barSlots) do
                    local element = DBVal(slot.key) or defaults[slot.key]
                    local sc = (DB() and DB()[slot.key .. "Color"]) or defaults[slot.key .. "Color"]
                    if element == "healthPercent" or element == "healthPercentNoSign" then
                        pctFS:SetTextColor(sc.r, sc.g, sc.b, 1)
                        pctFS:SetText(element == "healthPercentNoSign" and tostring(healthPct) or (healthPct .. "%"))
                        pctFS:SetPoint(slot.anchor, health, slot.anchor, slot.xOff, 0)
                        pctFS:Show()
                    elseif element == "healthNumber" then
                        numFS:SetTextColor(sc.r, sc.g, sc.b, 1)
                        local valStr = tostring(healthVal):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                        numFS:SetText(valStr)
                        numFS:SetPoint(slot.anchor, health, slot.anchor, slot.xOff, 0)
                        numFS:Show()
                    elseif ns.IsComboHealthText(element) then
                        local valStr = tostring(healthVal):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                        pctFS:SetTextColor(sc.r, sc.g, sc.b, 1)
                        ns.SetCombinedHealthText(pctFS, element, healthPct .. "%", valStr)
                        pctFS:SetPoint(slot.anchor, health, slot.anchor, slot.xOff, 0)
                        pctFS:Show()
                    end
                end
            end

            -- Run initial layout
            RefreshHealthText()

            -- Color the bar from the swatch's DB value
            local c = (DB() and DB()[colorKey]) or defaults[colorKey]
            health:SetStatusBarColor(c.r, c.g, c.b, 1)

            -- Focus overlay on the focus preview bar: clip frames for non-overlapping fixed-size textures
            local overlayFillClip, overlayFillTex, overlayBgClip, overlayBgTex

            -- Helper: create a clipped overlay frame+texture pair for the focus bar
            local function MakeOverlayClip(tlAnchor, tlRelPoint, brAnchor, brRelPoint, sublayer)
                local clip = CreateFrame("Frame", nil, health)
                clip:SetClipsChildren(true)
                -- Full bar height (top/bottom from the bar) with horizontal edges
                -- from the passed fill/health anchors -- matches the live nameplate
                -- overlay so the preview shows the same full-height stripes.
                clip:SetPoint("TOP", health, "TOP", 0, 0)
                clip:SetPoint("BOTTOM", health, "BOTTOM", 0, 0)
                clip:SetPoint("LEFT", tlAnchor, tlRelPoint, 0, 0)
                clip:SetPoint("RIGHT", brAnchor, brRelPoint, 0, 0)
                clip:SetFrameLevel(health:GetFrameLevel() + 1)
                local tex = clip:CreateTexture(nil, "ARTWORK", nil, sublayer)
                tex:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
                tex:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
                tex:SetWidth(BAR_W)
                return clip, tex
            end

            local _overlayTexKey   = (colorKey == "target") and "targetOverlayTexture"  or "focusOverlayTexture"
            local _overlayAlphaKey = (colorKey == "target") and "targetOverlayAlpha"   or "focusOverlayAlpha"
            local _overlayColorKey = (colorKey == "target") and "targetOverlayColor"   or "focusOverlayColor"
            local _overlayFullBgKey = (colorKey == "target") and "targetOverlayFullBgAlpha" or "focusOverlayFullBgAlpha"
            -- Empty-portion (bg) opacity: full when the "Full alpha on empty part
            -- of bar" toggle is on, otherwise dimmed to 30% (matches live plates).
            local function _overlayBgAlpha(oAlpha)
                local full = DBVal(_overlayFullBgKey)
                if full == nil then full = defaults[_overlayFullBgKey] end
                if full then return oAlpha end
                return oAlpha * 0.3
            end
            if colorKey == "focus" or colorKey == "target" then
                local tex = DBVal(_overlayTexKey) or defaults[_overlayTexKey]
                if tex ~= "none" then
                    local fillRef = health:GetStatusBarTexture()
                    local oAlpha = DBVal(_overlayAlphaKey) or defaults[_overlayAlphaKey]
                    local oc = (DB() and DB()[_overlayColorKey]) or defaults[_overlayColorKey]
                    overlayFillClip, overlayFillTex = MakeOverlayClip(fillRef, "TOPLEFT", fillRef, "BOTTOMRIGHT", 2)
                    overlayFillTex:SetTexture(ns.ResolveOverlayTexPath and ns.ResolveOverlayTexPath(tex) or (MEDIA .. tex .. ".png"))
                    overlayFillTex:SetAlpha(oAlpha)
                    overlayFillTex:SetVertexColor(oc.r, oc.g, oc.b)
                    overlayBgClip, overlayBgTex = MakeOverlayClip(fillRef, "TOPRIGHT", health, "BOTTOMRIGHT", 1)
                    overlayBgTex:SetTexture(ns.ResolveOverlayTexPath and ns.ResolveOverlayTexPath(tex) or (MEDIA .. tex .. ".png"))
                    overlayBgTex:SetAlpha(_overlayBgAlpha(oAlpha))
                    overlayBgTex:SetVertexColor(oc.r, oc.g, oc.b)
                end
            end

            local focusLetterFS
            local function RefreshFocusLetter()
                if colorKey ~= "focus" then return end
                if DBVal("focusLetterEnabled") ~= true then
                    if focusLetterFS then focusLetterFS:Hide() end
                    return
                end
                if not focusLetterFS then
                    focusLetterFS = textFrame:CreateFontString(nil, "OVERLAY")
                    focusLetterFS:SetJustifyH("CENTER")
                    focusLetterFS:SetJustifyV("MIDDLE")
                end
                local size = DBVal("focusLetterSize") or defaults.focusLetterSize
                local anchor = GetFocusLetterAnchor()
                local x = DBVal("focusLetterX") or defaults.focusLetterX
                local y = DBVal("focusLetterY") or defaults.focusLetterY
                local curFont = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("nameplates")) or DBVal("font")
                SetPVFont(focusLetterFS, curFont, size, GetNPOptOutline())
                focusLetterFS:SetText("F")
                focusLetterFS:ClearAllPoints()
                focusLetterFS:SetPoint(anchor, health, anchor, x, y)
                focusLetterFS:SetTextColor(1, 1, 1, 1)
                focusLetterFS:Show()
            end
            RefreshFocusLetter()

            -- Live update hook: re-color when swatch changes
            container.UpdateColor = function()
                local cc = (DB() and DB()[colorKey]) or defaults[colorKey]
                health:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
            end
            -- Live update hook: refresh overlay texture from DB
            container.UpdateOverlay = function()
                if colorKey ~= "focus" and colorKey ~= "target" then return end
                local tex = DBVal(_overlayTexKey) or defaults[_overlayTexKey]
                if tex == "none" then
                    if overlayFillClip then overlayFillClip:Hide() end
                    if overlayBgClip then overlayBgClip:Hide() end
                else
                    local fillRef = health:GetStatusBarTexture()
                    local oAlpha = DBVal(_overlayAlphaKey) or defaults[_overlayAlphaKey]
                    local oc = (DB() and DB()[_overlayColorKey]) or defaults[_overlayColorKey]
                    if not overlayFillClip then
                        overlayFillClip, overlayFillTex = MakeOverlayClip(fillRef, "TOPLEFT", fillRef, "BOTTOMRIGHT", 2)
                    end
                    overlayFillTex:SetTexture(ns.ResolveOverlayTexPath and ns.ResolveOverlayTexPath(tex) or (MEDIA .. tex .. ".png"))
                    overlayFillTex:SetAlpha(oAlpha)
                    overlayFillTex:SetVertexColor(oc.r, oc.g, oc.b)
                    overlayFillClip:Show()
                    if not overlayBgClip then
                        overlayBgClip, overlayBgTex = MakeOverlayClip(fillRef, "TOPRIGHT", health, "BOTTOMRIGHT", 1)
                    end
                    overlayBgTex:SetTexture(ns.ResolveOverlayTexPath and ns.ResolveOverlayTexPath(tex) or (MEDIA .. tex .. ".png"))
                    overlayBgTex:SetAlpha(_overlayBgAlpha(oAlpha))
                    overlayBgTex:SetVertexColor(oc.r, oc.g, oc.b)
                    overlayBgClip:Show()
                end
                RefreshFocusLetter()
            end
            container.Randomize = function()
                healthPct = math.floor(60 + math.random() * 15)
                healthVal = math.floor(FAKE_MAX_HP * healthPct / 100)
                health:SetValue(healthPct)
                RefreshHealthText()
            end
            -- Exposed so cache-restore / refresh-all can update text from current DB
            container.RefreshHealthText = RefreshHealthText
            container.RefreshBorderStyle = function() end  -- no style toggle needed for 1px solid
            container.RefreshBorderColor = function()
                local bc = (DB() and DB().borderColor) or defaults.borderColor
                for _, tex in ipairs(container._brdEdges) do
                    tex:SetColorTexture(bc.r, bc.g, bc.b, 1)
                end
            end

        elseif colorType == "cast" or colorType == "castLocked" then
            PP.Size(container, BAR_W + 2, BAR_H + 2)

            local cast = CreateFrame("StatusBar", nil, container)
            cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            cast:SetMinMaxValues(0, 1)
            cast:SetValue(NextCastFill())
            cast:SetAllPoints()

            local castBG = cast:CreateTexture(nil, "BACKGROUND")
            castBG:SetAllPoints()
            castBG:SetColorTexture(0.20, 0.20, 0.20, 0.9)


            -- Spark
            local spark = cast:CreateTexture(nil, "OVERLAY", nil, 1)
            spark:SetTexture(MEDIA .. "cast_spark.tga")
            spark:SetSize(8, BAR_H)
            spark:SetPoint("CENTER", cast:GetStatusBarTexture(), "RIGHT", 0, 0)
            spark:SetBlendMode("ADD")

            -- Cast icon frame (to the left) no border for Colors tab previews
            local iconFrame = CreateFrame("Frame", nil, cast)
            iconFrame:SetSize(BAR_H + 2, BAR_H + 2)
            iconFrame:SetPoint("RIGHT", cast, "LEFT", 0, 0)
            iconFrame:SetFrameLevel(cast:GetFrameLevel() + 1)
            local icon = iconFrame:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:SetTexture(NextCastIcon())

            -- Cast text
            local cns = math.min(DBVal("castNameSize") or defaults.castNameSize, 13)
            local cts = math.min(DBVal("castTargetSize") or defaults.castTargetSize, 13)
            local cnc = (DB() and DB().castNameColor) or defaults.castNameColor

            local dbRef = DB()
            local colShowTimer = defaults.showCastTimer
            if dbRef and dbRef.showCastTimer ~= nil then colShowTimer = dbRef.showCastTimer end
            local colCtmSz = math.min((dbRef and dbRef.castTimerSize) or defaults.castTimerSize, 13)
            local colCtmC = (dbRef and dbRef.castTimerColor) or defaults.castTimerColor
            local colNameSide   = (dbRef and dbRef.castNameSide)   or defaults.castNameSide
            local colTargetSide = (dbRef and dbRef.castTargetSide) or defaults.castTargetSide
            local colTimerSide  = (dbRef and dbRef.castTimerSide)  or defaults.castTimerSide
            local colCombine = dbRef and dbRef.castCombineNameTarget == true
            local colTimerW = colCtmSz * 2.2
            -- Per-element cast text truncation (% of bar width + wrap), mirroring runtime.
            local colNameW = BAR_W * ((dbRef and dbRef.castNameWidthPct) or defaults.castNameWidthPct) / 100
            local colTgtW  = BAR_W * ((dbRef and dbRef.castTargetWidthPct) or defaults.castTargetWidthPct) / 100
            local colNameWrap = (dbRef and dbRef.castNameWrap) == true
            local colTgtWrap  = (dbRef and dbRef.castTargetWrap) == true

            -- Spell name
            local nameFS = cast:CreateFontString(nil, "OVERLAY")
            SetPVFont(nameFS, fontPath, cns, GetNPOptOutline())
            nameFS:SetWordWrap(colNameWrap)
            nameFS:SetMaxLines(colNameWrap and 2 or 1)
            nameFS:SetText(EllesmereUI.L("Spell Name"))
            nameFS:SetTextColor(cnc.r, cnc.g, cnc.b, 1)
            if colNameSide == "none" then
                nameFS:Hide()
            else
                local pt, xb, jh = ns.GetCastTextAnchor(colNameSide, colShowTimer and colTimerSide == colNameSide, colTimerW, false)
                nameFS:SetWidth(colCombine and (BAR_W * 0.80) or colNameW)
                nameFS:SetJustifyH(jh)
                nameFS:SetPoint(pt, cast, pt, xb, 0)
            end

            -- Cast timer (side only "left"/"right"; visibility via showCastTimer)
            local timerFS = cast:CreateFontString(nil, "OVERLAY")
            SetPVFont(timerFS, fontPath, colCtmSz, GetNPOptOutline())
            timerFS:SetWordWrap(false)
            timerFS:SetMaxLines(1)
            timerFS:SetTextColor(colCtmC.r, colCtmC.g, colCtmC.b, 1)
            timerFS:SetText("2.3")
            if colShowTimer then
                local tpt, txb, tjh = ns.GetCastTextAnchor(colTimerSide, false, colTimerW, true)
                timerFS:SetWidth(colTimerW)
                timerFS:SetJustifyH(tjh)
                timerFS:SetPoint(tpt, cast, tpt, txb, 0)
            else
                timerFS:Hide()
            end

            -- Spell target
            local targetFS = cast:CreateFontString(nil, "OVERLAY")
            SetPVFont(targetFS, fontPath, cts, GetNPOptOutline())
            targetFS:SetWordWrap(colTgtWrap)
            targetFS:SetNonSpaceWrap(false)
            targetFS:SetMaxLines(colTgtWrap and 2 or 1)
            local colTargetText = isHalf and (UnitName("player") or EllesmereUI.L("Target")) or (UnitName("player") or EllesmereUI.L("Spell Target"))
            targetFS:SetText(colTargetText)
            local useClassColor = defaults.castTargetClassColor
            if dbRef and dbRef.castTargetClassColor ~= nil then useClassColor = dbRef.castTargetClassColor end
            local colTargetHex
            if useClassColor then
                local _, pClass = UnitClass("player")
                local c = pClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[pClass]
                if c then
                    targetFS:SetTextColor(c.r, c.g, c.b, 1)
                    colTargetHex = (c.GenerateHexColor and c:GenerateHexColor()) or c.colorStr or "ffffffff"
                else
                    targetFS:SetTextColor(1, 1, 1, 1)
                    colTargetHex = "ffffffff"
                end
            else
                local ctc = (dbRef and dbRef.castTargetColor) or defaults.castTargetColor
                targetFS:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
                colTargetHex = string.format("ff%02x%02x%02x",
                    math.floor(ctc.r * 255 + 0.5), math.floor(ctc.g * 255 + 0.5), math.floor(ctc.b * 255 + 0.5))
            end
            if colCombine then
                nameFS:SetFormattedText("%s - |c" .. colTargetHex .. "%s|r",
                    EllesmereUI.L("Spell Name"), colTargetText)
            end
            if colCombine or colTargetSide == "none" then
                targetFS:Hide()
            else
                local pt, xb, jh = ns.GetCastTextAnchor(colTargetSide, colShowTimer and colTimerSide == colTargetSide, colTimerW, false)
                targetFS:SetWidth(colTgtW)
                targetFS:SetJustifyH(jh)
                targetFS:SetPoint(pt, cast, pt, xb, 0)
            end

            -- Shield for uninterruptible
            if colorType == "castLocked" then
                local shieldH = BAR_H * 0.75
                local shieldW = shieldH * (29 / 35)
                local shieldFrame = CreateFrame("Frame", nil, cast)
                shieldFrame:SetSize(shieldW, shieldH)
                shieldFrame:SetPoint("CENTER", cast, "LEFT", 0, 0)
                shieldFrame:SetFrameLevel(cast:GetFrameLevel() + 10)
                local shield = shieldFrame:CreateTexture(nil, "OVERLAY")
                shield:SetAllPoints()
                shield:SetTexture(MEDIA .. "shield.png")
            end

            -- Color the bar
            local c = (DB() and DB()[colorKey]) or defaults[colorKey]
            cast:SetStatusBarColor(c.r, c.g, c.b, 1)

            -- Shift container left to account for cast icon hanging outside
            container:ClearAllPoints()
            PP.Point(container, "RIGHT", anchor, "RIGHT", -(20 + SWATCH_SZ + SWATCH_GAP), 0)

            container.UpdateColor = function()
                local cc = (DB() and DB()[colorKey]) or defaults[colorKey]
                cast:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
            end
            container.Randomize = function()
                cast:SetValue(NextCastFill())
                icon:SetTexture(NextCastIcon())
            end
            container.RefreshBorderStyle = function() end
            container.RefreshBorderColor = function() end
        end

        return container
    end

    -- Shared preview bar list and lazy builder (used by both Display and Colors pages)
    local _colorPagePreviews = {}

    LazyColorPreviewBar = function(parentRow, colorType, colorKey, anchorFrame)
        local real = nil
        local proxy = {}
        local _disabled = false
        local _colorOverrideFn = nil
        local function EnsureBuilt()
            if real then return real end
            real = MakeColorPreviewBar(parentRow, colorType, colorKey, anchorFrame)
            if _disabled and real._health then real._health:SetAlpha(0.3) end
            return real
        end
        proxy.UpdateColor = function()
            local r = EnsureBuilt()
            if r and r.UpdateColor then
                if _colorOverrideFn then
                    local cr, cg, cb = _colorOverrideFn()
                    if cr and r._health then
                        r._health:SetStatusBarColor(cr, cg, cb, 1)
                        return
                    end
                end
                r.UpdateColor()
            end
        end
        proxy.UpdateOverlay = function()
            local r = EnsureBuilt()
            if r and r.UpdateOverlay then r.UpdateOverlay() end
        end
        proxy.RefreshBorderStyle = function()
            if real and real.RefreshBorderStyle then real.RefreshBorderStyle() end
        end
        proxy.RefreshBorderColor = function()
            if real and real.RefreshBorderColor then real.RefreshBorderColor() end
        end
        proxy.Randomize = function()
            if real and real.Randomize then real.Randomize() end
        end
        proxy.RefreshHealthText = function()
            if real and real.RefreshHealthText then real.RefreshHealthText() end
        end
        proxy.SetDisabled = function(off)
            _disabled = off
            if real and real._health then
                real._health:SetAlpha(off and 0.3 or 1)
            end
        end
        proxy.SetColorOverride = function(fn)
            _colorOverrideFn = fn
        end
        parentRow:HookScript("OnShow", function()
            if not real then
                EnsureBuilt()
                _G._EUI_ColorPreviews[#_G._EUI_ColorPreviews + 1] = real
            end
            if real and real._health then
                real._health:SetAlpha(_disabled and 0.3 or 1)
            end
        end)
        if parentRow:IsVisible() then
            EnsureBuilt()
        end
        _colorPagePreviews[#_colorPagePreviews + 1] = proxy
        return proxy
    end

    local function BuildColorsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        -- No content header on Colors tab (presets are inline in scroll area)
        EllesmereUI:ClearContentHeader()

        -- Enable per-row center divider for the dual-column layout (same as Display tab)
        parent._showRowDivider = true

        -- Track all mini previews for border style refresh
        _G._EUI_ColorPreviews = {}
        local function TrackPreview(prev)
            if prev then _G._EUI_ColorPreviews[#_G._EUI_ColorPreviews + 1] = prev end
            return prev
        end

        -- LazyColorPreviewBar and _colorPagePreviews moved to init scope
        -- (shared between Display and Colors pages)

        -----------------------------------------------------------------------
        --  ENEMY COLORS
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_ENEMY, y);  y = y - h

        -- Enemy Types
        local enemyTypesRow
        enemyTypesRow, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Enemy Types",
              swatches = {
                { tooltip = "Enemies",
                  getValue = function() return DBColor("enemyInCombat") end,
                  setValue = function(r, g, b)
                    DB().enemyInCombat = { r = r, g = g, b = b }
                    RefreshAllPlates()
                  end },
                { tooltip = "Spell Casters",
                  getValue = function() return DBColor("caster") end,
                  setValue = function(r, g, b)
                    DB().caster = { r = r, g = g, b = b }
                    RefreshAllPlates()
                  end },
                { tooltip = "Mini-Bosses",
                  getValue = function() return DBColor("miniboss") end,
                  setValue = function(r, g, b)
                    DB().miniboss = { r = r, g = g, b = b }
                    RefreshAllPlates()
                  end },
                { tooltip = "Bosses",
                  getValue = function() return DBColor("boss") end,
                  setValue = function(r, g, b)
                    DB().boss = { r = r, g = g, b = b }
                    RefreshAllPlates()
                  end },
              } },
            { type="toggle", text="Enable Quest Mob Color",
              getValue=function() return DBVal("questMobColorEnabled") == true end,
              setValue=function(v)
                DB().questMobColorEnabled = v
                for _, plate in pairs(ns.plates) do
                    plate:UpdateHealthColor()
                end
                EllesmereUI:RefreshPage()
              end,
              tooltip="Colors enemy nameplates for quest mobs you still need to kill." });  y = y - h

        -- Inline Quest Mob Color swatch
        do
            local rightRgn = enemyTypesRow._rightRegion
            local questColorGet = function()
                local c = DB().questMobColor or defaults.questMobColor
                return c.r, c.g, c.b
            end
            local questColorSet = function(r, g, b)
                DB().questMobColor = { r = r, g = g, b = b }
                RefreshAllPlates()
            end
            local isQuestOff = function() return DBVal("questMobColorEnabled") ~= true end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, questColorGet, questColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isQuestOff()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            local off = isQuestOff()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
        end

        -- Inline cog on the "Enemy Types" region: Full Coloring M+ Only.
        -- On: outside 5-man dungeons, Mini Enemies / Spell Casters /
        -- Mini-Bosses / Bosses all use the single flat "All Enemies" color
        -- below; Neutral keeps its own color. Off (default): no effect on
        -- coloring anywhere. Keys keep their original owBasic* names
        -- (formerly "Open World Basic Coloring", which gated on any instance).
        do
            local leftRgn = enemyTypesRow._leftRegion
            local isOWOff = function()
                local v = DBVal("owBasicColoring")
                if v == nil then return not defaults.owBasicColoring end
                return not v
            end
            local _, owCogShow = EllesmereUI.BuildCogPopup({
                title = "Enemy Colors",
                rows = {
                    { type="toggle", label="Full Coloring M+ Only",
                      get=function()
                        local v = DBVal("owBasicColoring")
                        if v == nil then return defaults.owBasicColoring end
                        return v
                      end,
                      set=function(v)
                        DB().owBasicColoring = v
                        RefreshAllPlates()
                      end },
                    { type="colorpicker", label="All Enemies",
                      get=function() return DBColor("owBasicColor") end,
                      set=function(r, g, b)
                        DB().owBasicColor = { r = r, g = g, b = b }
                        RefreshAllPlates()
                      end,
                      disabled=isOWOff,
                      disabledTooltip="Full Coloring M+ Only" },
                },
            })
            local owCogBtn = CreateFrame("Button", nil, leftRgn)
            owCogBtn:SetSize(26, 26)
            owCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = owCogBtn
            owCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            owCogBtn:SetAlpha(0.4)
            local owCogTex = owCogBtn:CreateTexture(nil, "OVERLAY")
            owCogTex:SetAllPoints(); owCogTex:SetTexture(EllesmereUI.COGS_ICON)
            owCogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            owCogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            owCogBtn:SetScript("OnClick", function(s) owCogShow(s) end)
        end

        -- Neutral & Mini Enemies | Darken Enemies Out of Combat
        local neutralMiniRow
        neutralMiniRow, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Neutral & Mini Enemies",
              swatches = {
                { tooltip = "Neutral",
                  getValue = function() return DBColor("neutral") end,
                  setValue = function(r, g, b)
                    DB().neutral = { r = r, g = g, b = b }
                    RefreshAllPlates()
                  end },
                { tooltip = "Mini Enemies",
                  -- Until explicitly set, views the user's "Enemies" color so the
                  -- swatch starts matching enemyInCombat (see GetReactionColor).
                  getValue = function()
                    local db = DB()
                    local c = (db and db.miniEnemy) or (db and db.enemyInCombat) or defaults.enemyInCombat
                    return c.r, c.g, c.b
                  end,
                  setValue = function(r, g, b)
                    DB().miniEnemy = { r = r, g = g, b = b }
                    RefreshAllPlates()
                  end },
              } },
            { type="toggle", text="Darken Enemies Out of Combat",
              getValue=function()
                local db = DB()
                if db and db.darkenEnemiesOOC ~= nil then return db.darkenEnemiesOOC end
                return defaults.darkenEnemiesOOC
              end,
              setValue=function(v)
                DB().darkenEnemiesOOC = v
                for _, plate in pairs(ns.plates) do
                    plate:UpdateHealthColor()
                end
              end,
              tooltip="Dims enemy nameplate colours while the enemy is out of combat. Turn off to keep enemies at full colour whether or not they are fighting." });  y = y - h

        -- Inline cog on the "Neutral & Mini Enemies" region: "Mini Coloring M+
        -- Only" toggle. On (default) restricts the Mini Enemies color to 5-man
        -- dungeons; off applies it everywhere.
        do
            local leftRgn = neutralMiniRow._leftRegion
            local _, miniCogShow = EllesmereUI.BuildCogPopup({
                title = "Mini Enemies",
                rows = {
                    { type="toggle", label="Mini Coloring M+ Only",
                      get=function()
                        local v = DBVal("miniColoringMPlusOnly")
                        if v == nil then return defaults.miniColoringMPlusOnly end
                        return v
                      end,
                      set=function(v)
                        DB().miniColoringMPlusOnly = v
                        RefreshAllPlates()
                      end },
                },
            })
            local miniCogBtn = CreateFrame("Button", nil, leftRgn)
            miniCogBtn:SetSize(26, 26)
            miniCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = miniCogBtn
            miniCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            miniCogBtn:SetAlpha(0.4)
            local miniCogTex = miniCogBtn:CreateTexture(nil, "OVERLAY")
            miniCogTex:SetAllPoints(); miniCogTex:SetTexture(EllesmereUI.COGS_ICON)
            miniCogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            miniCogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            miniCogBtn:SetScript("OnClick", function(s) miniCogShow(s) end)
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  THREAT COLORS (INSTANCES ONLY)
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_THREAT, y);  y = y - h

        -- Row 1: Tank Threat (left) ---- Non-Tank Threat (right)
        _, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Tank Threat",
              swatches = {
                { tooltip = "Losing Aggro",
                  getValue = function() return DBColor("tankLosingAggro") end,
                  setValue = function(r, g, b)
                    DB().tankLosingAggro = { r = r, g = g, b = b }
                    RefreshAllPlates()
                  end },
                { tooltip = "No Aggro",
                  getValue = function() return DBColor("tankNoAggro") end,
                  setValue = function(r, g, b)
                    DB().tankNoAggro = { r = r, g = g, b = b }
                    RefreshAllPlates()
                  end },
              } },
            { type="multiSwatch", text="Non-Tank Threat",
              swatches = {
                { tooltip = "Has Aggro",
                  getValue = function() return DBColor("dpsHasAggro") end,
                  setValue = function(r, g, b)
                    DB().dpsHasAggro = { r = r, g = g, b = b }
                    RefreshAllPlates()
                  end },
                { tooltip = "Near Aggro",
                  getValue = function() return DBColor("dpsNearAggro") end,
                  setValue = function(r, g, b)
                    DB().dpsNearAggro = { r = r, g = g, b = b }
                    RefreshAllPlates()
                  end },
              } });  y = y - h

        -- Disabled-state helpers (shared across Row 2 / Row 3 swatches)
        local function isTankHasAggroDisabled()
            local db = DB()
            if db and db.tankHasAggroEnabled ~= nil then return not db.tankHasAggroEnabled end
            return not defaults.tankHasAggroEnabled
        end
        local function isClassicTankAggroDisabled()
            local db = DB()
            if db and db.classicTankAggro ~= nil then return not db.classicTankAggro end
            return not defaults.classicTankAggro
        end
        local function isOffTankDisabled()
            local db = DB()
            if db and db.offTankAggroEnabled ~= nil then return not db.offTankAggroEnabled end
            return not defaults.offTankAggroEnabled
        end
        local function isDpsNoAggroDisabled()
            local db = DB()
            if db and db.dpsNoAggroEnabled ~= nil then return not db.dpsNoAggroEnabled end
            return not defaults.dpsNoAggroEnabled
        end

        -- Row 2: DPS: Show Special "No Aggro" Color (left) ---- Classic Tank Aggro (right)
        local dpsDualFrame
        dpsDualFrame, h = W:DualRow(parent, y,
            { type="toggle", text="DPS: Show Special \"No Aggro\" Color",
              tooltip="Shows a special color for non caster/mini-boss enemies when you do not have aggro on them.",
              getValue=function()
                local db = DB()
                if db and db.dpsNoAggroEnabled ~= nil then return db.dpsNoAggroEnabled end
                return defaults.dpsNoAggroEnabled
              end,
              setValue=function(v)
                DB().dpsNoAggroEnabled = v
                RefreshAllPlates()
                EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Classic Tank Aggro",
              tooltip="Enables a three-tier tank aggro system: has aggro, losing aggro, and no aggro colors override all mob-type colors.",
              getValue=function()
                local db = DB()
                if db and db.classicTankAggro ~= nil then return db.classicTankAggro end
                return defaults.classicTankAggro
              end,
              setValue=function(v)
                DB().classicTankAggro = v
                RefreshAllPlates()
                EllesmereUI:RefreshPage()
              end });  y = y - h

        -- Inline "No Aggro" color swatch next to left toggle
        do
            local leftRgn = dpsDualFrame._leftRegion
            local dpsNoAggroColorGet = function() return DBColor("dpsNoAggro") end
            local dpsNoAggroColorSet = function(r, g, b)
                DB().dpsNoAggro = { r = r, g = g, b = b }
                RefreshAllPlates()
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, dpsNoAggroColorGet, dpsNoAggroColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isDpsNoAggroDisabled()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            local off = isDpsNoAggroDisabled()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)

            -- Inline cog: independent "Override Mini-Boss colors" and "Override
            -- Caster colors". Each promotes the DPS No Aggro color above that
            -- single mob-type color. Kept separate so Casters can stay their own
            -- color for contrast. Dimmed + non-interactive while the toggle is off.
            local _, dpsNoAggroCogShow = EllesmereUI.BuildCogPopup({
                title = "No Aggro",
                rows = {
                    { type="toggle", label="Override Mini-Boss colors",
                      get=function()
                        local db = DB()
                        if db and db.dpsNoAggroOverrideMiniBoss ~= nil then return db.dpsNoAggroOverrideMiniBoss end
                        return defaults.dpsNoAggroOverrideMiniBoss
                      end,
                      set=function(v) DB().dpsNoAggroOverrideMiniBoss = v; RefreshAllPlates() end },
                    { type="toggle", label="Override Caster colors",
                      get=function()
                        local db = DB()
                        if db and db.dpsNoAggroOverrideCaster ~= nil then return db.dpsNoAggroOverrideCaster end
                        return defaults.dpsNoAggroOverrideCaster
                      end,
                      set=function(v) DB().dpsNoAggroOverrideCaster = v; RefreshAllPlates() end },
                },
            })
            local dpsNoAggroCogBtn = CreateFrame("Button", nil, leftRgn)
            dpsNoAggroCogBtn:SetSize(26, 26)
            dpsNoAggroCogBtn:SetPoint("RIGHT", swatch, "LEFT", -8, 0)
            dpsNoAggroCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            local dpsNoAggroCogTex = dpsNoAggroCogBtn:CreateTexture(nil, "OVERLAY")
            dpsNoAggroCogTex:SetAllPoints(); dpsNoAggroCogTex:SetTexture(EllesmereUI.COGS_ICON)
            dpsNoAggroCogBtn:SetScript("OnEnter", function(s) if not isDpsNoAggroDisabled() then s:SetAlpha(0.7) end end)
            dpsNoAggroCogBtn:SetScript("OnLeave", function(s) if not isDpsNoAggroDisabled() then s:SetAlpha(0.4) end end)
            dpsNoAggroCogBtn:SetScript("OnClick", function(s) if not isDpsNoAggroDisabled() then dpsNoAggroCogShow(s) end end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local cogOff = isDpsNoAggroDisabled()
                dpsNoAggroCogBtn:SetAlpha(cogOff and 0.15 or 0.4)
                dpsNoAggroCogBtn:EnableMouse(not cogOff)
            end)
            do
                local cogOff = isDpsNoAggroDisabled()
                dpsNoAggroCogBtn:SetAlpha(cogOff and 0.15 or 0.4)
                dpsNoAggroCogBtn:EnableMouse(not cogOff)
            end
        end

        -- Inline "Has Aggro" color swatch next to Classic Tank Aggro toggle
        do
            local rightRgn = dpsDualFrame._rightRegion
            local aggroColorGet = function() return DBColor("tankHasAggro") end
            local aggroColorSet = function(r, g, b)
                DB().tankHasAggro = { r = r, g = g, b = b }
                RefreshAllPlates()
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, aggroColorGet, aggroColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isClassicTankAggroDisabled()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            local off = isClassicTankAggroDisabled()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
        end

        -- Row 3: Tank: Show Special "Has Aggro" Color (left) ---- Tank: Show Special "Off-Tank" Color (right)
        local tankDualFrame
        tankDualFrame, h = W:DualRow(parent, y,
            { type="toggle", text="Tank: Show Special \"Has Aggro\" Color",
              tooltip="Shows a special color for non caster/mini-boss enemies when you have aggro on them.",
              getValue=function()
                local db = DB()
                if db and db.tankHasAggroEnabled ~= nil then return db.tankHasAggroEnabled end
                return defaults.tankHasAggroEnabled
              end,
              setValue=function(v)
                DB().tankHasAggroEnabled = v
                RefreshAllPlates()
                EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Tank: Show Special \"Off-Tank\" Color",
              tooltip="Shows a special color for nameplates that another tank in your raid has aggro on.",
              getValue=function()
                local db = DB()
                if db and db.offTankAggroEnabled ~= nil then return db.offTankAggroEnabled end
                return defaults.offTankAggroEnabled
              end,
              setValue=function(v)
                DB().offTankAggroEnabled = v
                RefreshAllPlates()
                EllesmereUI:RefreshPage()
              end });  y = y - h

        -- Inline "Has Aggro" color swatch next to left toggle
        do
            local leftRgn = tankDualFrame._leftRegion
            local tankAggroColorGet = function() return DBColor("tankHasAggro") end
            local tankAggroColorSet = function(r, g, b)
                DB().tankHasAggro = { r = r, g = g, b = b }
                RefreshAllPlates()
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, tankAggroColorGet, tankAggroColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isTankHasAggroDisabled()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            local off = isTankHasAggroDisabled()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)

            -- Inline cog: "Override Mini-Boss and Caster colors". Promotes the
            -- tank has-aggro color above the mini-boss/caster priority steps.
            -- Dimmed + non-interactive while the Has Aggro toggle is off.
            local _, hasAggroCogShow = EllesmereUI.BuildCogPopup({
                title = "Has Aggro",
                rows = {
                    { type="toggle", label="Override Mini-Boss and Caster colors",
                      get=function()
                        local db = DB()
                        if db and db.tankHasAggroOverrideMobType ~= nil then return db.tankHasAggroOverrideMobType end
                        return defaults.tankHasAggroOverrideMobType
                      end,
                      set=function(v) DB().tankHasAggroOverrideMobType = v; RefreshAllPlates() end },
                    { type="toggle", label="Override Boss colors",
                      get=function()
                        local db = DB()
                        if db and db.tankHasAggroOverrideBoss ~= nil then return db.tankHasAggroOverrideBoss end
                        return defaults.tankHasAggroOverrideBoss
                      end,
                      set=function(v) DB().tankHasAggroOverrideBoss = v; RefreshAllPlates() end },
                },
            })
            local hasAggroCogBtn = CreateFrame("Button", nil, leftRgn)
            hasAggroCogBtn:SetSize(26, 26)
            hasAggroCogBtn:SetPoint("RIGHT", swatch, "LEFT", -8, 0)
            hasAggroCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            local hasAggroCogTex = hasAggroCogBtn:CreateTexture(nil, "OVERLAY")
            hasAggroCogTex:SetAllPoints(); hasAggroCogTex:SetTexture(EllesmereUI.COGS_ICON)
            hasAggroCogBtn:SetScript("OnEnter", function(s) if not isTankHasAggroDisabled() then s:SetAlpha(0.7) end end)
            hasAggroCogBtn:SetScript("OnLeave", function(s) if not isTankHasAggroDisabled() then s:SetAlpha(0.4) end end)
            hasAggroCogBtn:SetScript("OnClick", function(s) if not isTankHasAggroDisabled() then hasAggroCogShow(s) end end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local cogOff = isTankHasAggroDisabled()
                hasAggroCogBtn:SetAlpha(cogOff and 0.15 or 0.4)
                hasAggroCogBtn:EnableMouse(not cogOff)
            end)
            do
                local cogOff = isTankHasAggroDisabled()
                hasAggroCogBtn:SetAlpha(cogOff and 0.15 or 0.4)
                hasAggroCogBtn:EnableMouse(not cogOff)
            end
        end

        -- Inline "Off-Tank" color swatch next to right toggle
        do
            local rightRgn = tankDualFrame._rightRegion
            local otColorGet = function() return DBColor("offTankAggro") end
            local otColorSet = function(r, g, b)
                DB().offTankAggro = { r = r, g = g, b = b }
                RefreshAllPlates()
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, otColorGet, otColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isOffTankDisabled()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            local off = isOffTankDisabled()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -- Build a refresh-all function for page cache restore
        _colorPreviewRefreshAll = function()
            for _, prev in ipairs(_G._EUI_ColorPreviews) do
                if prev.UpdateColor then prev.UpdateColor() end
                if prev.UpdateOverlay then prev.UpdateOverlay() end
                if prev.RefreshBorderColor then prev.RefreshBorderColor() end
                if prev.RefreshHealthText then prev.RefreshHealthText() end
            end
            for _, prev in ipairs(_colorPagePreviews) do
                if prev.UpdateColor then prev.UpdateColor() end
                if prev.UpdateOverlay then prev.UpdateOverlay() end
                if prev.RefreshBorderColor then prev.RefreshBorderColor() end
                if prev.RefreshHealthText then prev.RefreshHealthText() end
            end
        end
        for _, prev in ipairs(_colorPagePreviews) do
            if prev.UpdateColor then
                EllesmereUI.RegisterWidgetRefresh(prev.UpdateColor)
            end
            if prev.UpdateOverlay then
                EllesmereUI.RegisterWidgetRefresh(prev.UpdateOverlay)
            end
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    -- Rebuild preview when spec changes (class resource pips may appear/disappear)
    local npOptSpecFrame = CreateFrame("Frame")
    npOptSpecFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    npOptSpecFrame:SetScript("OnEvent", function(_, _, unit)
        if unit ~= "player" then return end
        -- Only invalidate + rebuild when the panel is actually open.
        -- Invalidating while closed destroys all cached pages, causing
        -- a blank panel on next open.
        if EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then
            if EllesmereUI.InvalidatePageCache then EllesmereUI:InvalidatePageCache() end
            C_Timer.After(0.2, function()
                if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
            end)
        end
    end)

    EllesmereUI:RegisterModule("EllesmereUINameplates", {
        title       = "Nameplates",
        description = "Custom nameplate design and behavior.",
        pages       = { PAGE_DISPLAY, PAGE_COLORS, PAGE_GENERAL },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_GENERAL then
                return BuildGeneralPage(pageName, parent, yOffset)
            elseif pageName == PAGE_DISPLAY then
                return BuildDisplayPage(pageName, parent, yOffset)
            elseif pageName == PAGE_COLORS then
                return BuildColorsPage(pageName, parent, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_DISPLAY then
                return _displayHeaderBuilder
            end
            return nil  -- General and Colors have no content header
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_DISPLAY then
                -- Re-evaluate Set as Default button visibility (cache restore
                -- blanket-shows all children, which can ghost the button)
                local pState = EllesmereUI._presetState and EllesmereUI._presetState[""]
                if pState and pState.UpdateDefaultBtnState then pState.UpdateDefaultBtnState() end
                -- Randomize preview values when switching TO this tab
                RandomizePreviewValues()
                -- Refresh the preview after cache restore
                if activePreview and activePreview.Update then activePreview:Update() end
                -- Refresh hint visibility never recreate here, just show/hide
                local dismissed = IsPreviewHintDismissed()
                if _previewHintFS then
                    if dismissed then
                        _previewHintFS:Hide()
                    else
                        _previewHintFS:SetAlpha(0.45)
                        _previewHintFS:Show()
                    end
                end
                -- Set correct header height based on current hint state
                if _headerBaseH > 0 then
                    EllesmereUI:SetContentHeaderHeightSilent(_headerBaseH + (dismissed and 0 or 29))
                end
            elseif pageName == PAGE_COLORS then
                -- Refresh all color preview bars (colors from DB)
                if _colorPreviewRefreshAll then _colorPreviewRefreshAll() end
            end
        end,
        onReset     = function()
            -- Invalidate page cache so pages are rebuilt with fresh defaults
            EllesmereUI:InvalidatePageCache()
            -- Preserve user-saved presets (display + color), Custom presets, AND spec assignments across reset
            local old = DB()
            if old then
                local pD = old._presets
                local oD = old._presetOrder
                local pC = old._color_presets
                local oC = old._color_presetOrder
                local cD = old._customPreset
                local cC = old._color_customPreset
                local sA = old._specAssignments
                local sCA = old._color_specAssignments
                local sDP = old._specDefaultPreset
                for k in pairs(old) do old[k] = nil end
                if pD and next(pD) then old._presets = pD; old._presetOrder = oD end
                if pC and next(pC) then old._color_presets = pC; old._color_presetOrder = oC end
                if cD then old._customPreset = cD end
                if cC then old._color_customPreset = cC end
                if sA and next(sA) then old._specAssignments = sA end
                if sCA and next(sCA) then old._color_specAssignments = sCA end
                if sDP then old._specDefaultPreset = sDP end
                -- Explicitly activate EllesmereUI for both preset systems
                old._activePreset = "ellesmereui"
                old._color_activePreset = "ellesmereui"
            end
        end,
    })

    ---------------------------------------------------------------------------
    --  Slash command  /enp  opens EllesmereUI to the Nameplates module
    ---------------------------------------------------------------------------
    SLASH_ELLESMERENAMEPLATES1 = "/enp"
    SlashCmdList.ELLESMERENAMEPLATES = function(msg)
        if InCombatLockdown and InCombatLockdown() then
            print("Cannot open options in combat")
            return
        end

        if msg == "reset" then
            local _db = DB()
            if _db then
                local pD = _db._presets
                local oD = _db._presetOrder
                local pC = _db._color_presets
                local oC = _db._color_presetOrder
                local cD = _db._customPreset
                local cC = _db._color_customPreset
                local sA = _db._specAssignments
                local sCA = _db._color_specAssignments
                local sDP = _db._specDefaultPreset
                for k in pairs(_db) do _db[k] = nil end
                if pD and next(pD) then _db._presets = pD; _db._presetOrder = oD end
                if pC and next(pC) then _db._color_presets = pC; _db._color_presetOrder = oC end
                if cD then _db._customPreset = cD end
                if cC then _db._color_customPreset = cC end
                if sA and next(sA) then _db._specAssignments = sA end
                if sCA and next(sCA) then _db._color_specAssignments = sCA end
                if sDP then _db._specDefaultPreset = sDP end
                _db._activePreset = "ellesmereui"
                _db._color_activePreset = "ellesmereui"
            end
            ReloadUI()
            return
        end

        EllesmereUI:ShowModule("EllesmereUINameplates")
    end
end)
