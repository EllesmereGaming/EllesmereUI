-------------------------------------------------------------------------------
--  EUI_Nameplates_Options.lua
--  Registers the Nameplates module with EllesmereUI
--  Pure UI migration all get/set calls go to EllesmereUINameplatesDB,
--  same keys, same defaults, same refresh functions as the AceConfig version.
--  Does NOT touch nameplate rendering logic.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local function GetNPOptOutline() return EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag() or "" end

-------------------------------------------------------------------------------
--  Page / section names
-------------------------------------------------------------------------------
local PAGE_GENERAL  = "General"
local PAGE_DISPLAY  = "Display"
local PAGE_COLORS   = "Colors"

local SECTION_FRIENDLY  = "OTHER NAMEPLATES"
local SECTION_ENEMY_NP  = "ENEMY NAMEPLATE SPACING"
local SECTION_MISC      = "EXTRAS"

local SECTION_ENEMY     = "ENEMY COLORS"
local SECTION_CASTBAR   = "CAST BAR"
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
    local GetNPOutline         = ns.GetNPOutline or function() return "OUTLINE" end
    local GetNPUseShadow       = ns.GetNPUseShadow or function() return false end

    local pcall = pcall
    local pairs = pairs

    -- Preview font setter: mirrors SetFSFont shadow logic for direct SetFont calls
    local function SetPVFont(fs, fontPath, size, flags)
        if not (fs and fs.SetFont) then return end
        fs:SetFont(fontPath, size, flags)
        if flags == "" then
            fs:SetShadowOffset(1, -1)
            fs:SetShadowColor(0, 0, 0, 1)
        else
            fs:SetShadowOffset(0, 0)
        end
    end
    local floor = math.floor

    ---------------------------------------------------------------------------
    --  DB helper always reads live EllesmereUINameplatesDB
    ---------------------------------------------------------------------------
    local function DB()
        return EllesmereUINameplatesDB
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
    end

    local function RefreshAllFonts()
        for _, plate in pairs(plates) do
            plate:RefreshNamePosition()
            plate:UpdateHealthValues()
            local cns = ns.defaults.castNameSize
            local cts = ns.defaults.castTargetSize
            local db = EllesmereUINameplatesDB
            if db then
                cns = db.castNameSize or cns
                cts = db.castTargetSize or cts
            end
            if plate.castName then SetFSFont(plate.castName, cns, GetNPOutline()) end
            if plate.castTarget then SetFSFont(plate.castTarget, cts, GetNPOutline()) end
            local auraStackSz = (db and db.auraStackTextSize) or ns.defaults.auraStackTextSize
            for i = 1, 4 do
                if plate.debuffs[i] and plate.debuffs[i].count then SetFSFont(plate.debuffs[i].count, auraStackSz, "OUTLINE") end
                if plate.buffs[i] and plate.buffs[i].count then SetFSFont(plate.buffs[i].count, auraStackSz, "OUTLINE") end
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
    local _colorPreviewRandomizeAll -- randomize all color preview fills/icons on tab switch
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
        if not _previewHpPct then RandomizePreviewValues() end
        local previewHpPct = _previewHpPct
        local previewHpVal = math.floor(PV_CONST.FAKE_MAX_HP * previewHpPct / 100)
        health:SetMinMaxValues(0, PV_CONST.FAKE_MAX_HP)
        health:SetValue(previewHpVal)
        health:SetFrameLevel(pf:GetFrameLevel() + 10)
        health:SetStatusBarColor(0.85, 0.20, 0.20, 1)

        local healthBG = health:CreateTexture(nil, "BACKGROUND")
        healthBG:SetAllPoints()
        healthBG:SetColorTexture(0.12, 0.12, 0.12, 1.0)
        UnsnapTex(healthBG)

        -- Hash line on preview health bar
        local previewHashLine = health:CreateTexture(nil, "OVERLAY", nil, 3)
        previewHashLine:SetColorTexture(1, 1, 1, 0.8)
        UnsnapTex(previewHashLine)
        previewHashLine:SetWidth(Snap(2))
        previewHashLine:SetPoint("TOP", health, "TOP", 0, 0)
        previewHashLine:SetPoint("BOTTOM", health, "BOTTOM", 0, 0)
        previewHashLine:Hide()

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
            return f
        end

        local borderFrame = CreatePreviewBorderSet(healthWrapper, BORDER_TEX)
        local simpleBorderFrame = CreatePreviewBorderSet(healthWrapper, BORDER_TEX_SIMPLE)

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
            local function Mk(coords)
                local t = gf:CreateTexture(nil, "BACKGROUND")
                t:SetTexture(GLOW_TEX)
                t:SetVertexColor(0.4117, 0.6667, 1.0, 1.0)
                t:SetBlendMode("ADD")
                t:SetTexCoord(unpack(coords))
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

        -- Text overlay frame: renders above health bar fill and borders (same as real addon)
        local healthTextFrame = CreateFrame("Frame", nil, health)
        healthTextFrame:SetAllPoints(health)
        healthTextFrame:SetFrameLevel(health:GetFrameLevel() + 2)

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
        nameFS:SetText("Enemy Name Text")
        nameFS:SetTextColor(1, 1, 1, 1)

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
        raidFrame:SetFrameLevel(health:GetFrameLevel() + 6)
        local raidIcon = raidFrame:CreateTexture(nil, "ARTWORK")
        raidIcon:SetAllPoints()
        raidIcon:SetTexture(MARKER_PATH)

        -- Target arrows packed into a table to reduce upvalue count
        local ARROW_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
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
        castBG:SetColorTexture(0.1, 0.1, 0.1, 0.9)
        UnsnapTex(castBG)

        -- Cast bar parts packed into a table to reduce upvalue count
        local castParts = {}

        -- Cast icon (flush to the left of the cast bar)
        castParts.iconFrame = CreateFrame("Frame", nil, cast)
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
        castParts.spark:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\cast_spark.tga")
        UnsnapTex(castParts.spark)
        castParts.spark:SetSize(8, CAST_H)
        castParts.spark:SetPoint("CENTER", cast:GetStatusBarTexture(), "RIGHT", 0, 0)
        castParts.spark:SetBlendMode("ADD")

        -- Cast name (left, width 70)
        castParts.nameFS = cast:CreateFontString(nil, "OVERLAY")
        SetPVFont(castParts.nameFS, FONT_PATH, 10, GetNPOptOutline())
        castParts.nameFS:SetPoint("LEFT", cast, 5, 0)
        castParts.nameFS:SetJustifyH("LEFT")
        castParts.nameFS:SetWordWrap(false)
        castParts.nameFS:SetMaxLines(1)
        castParts.nameFS:SetText("Spell Name")

        -- Cast target (right, dynamic width)
        castParts.targetFS = cast:CreateFontString(nil, "OVERLAY")
        SetPVFont(castParts.targetFS, FONT_PATH, 10, GetNPOptOutline())
        castParts.targetFS:SetPoint("RIGHT", cast, -3, 0)
        castParts.targetFS:SetJustifyH("RIGHT")
        castParts.targetFS:SetWordWrap(false)
        castParts.targetFS:SetMaxLines(1)
        castParts.targetFS:SetText(UnitName("player") or "Spell Target")

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
            },
        }
        CP.pips = {}
        for i = 1, CP.MAX_POSSIBLE do
            local bg = pf:CreateTexture(nil, "OVERLAY", nil, 2)
            bg:SetColorTexture(0.082, 0.082, 0.082, 1)
            bg:Hide()
            local pip = pf:CreateTexture(nil, "OVERLAY", nil, 3)
            pip:SetColorTexture(1, 1, 1, 1)
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
            d.durationText:SetFont(FONT_PATH, 11, "OUTLINE")
            d.durationText:SetPoint("TOPLEFT", d, "TOPLEFT", -3, 4)
            d.durationText:SetJustifyH("LEFT")
            d.durationText:SetText(debuffData[i].text)

            -- Stack count text (bottom-right)
            d.stackText = textFrame:CreateFontString(nil, "OVERLAY")
            d.stackText:SetFont(FONT_PATH, 11, "OUTLINE")
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
            bf.durationText:SetFont(FONT_PATH, 12, "OUTLINE")
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
            cf.durationText:SetFont(FONT_PATH, 12, "OUTLINE")
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
            local npOutline  = (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or "OUTLINE"
            local barH       = Snap(DBVal("healthBarHeight"))
            local rawBarW    = BAR_W + DBVal("healthBarWidth")
            local barW       = IsDragging() and rawBarW or Snap(rawBarW)
            local castH      = Snap(DBVal("castBarHeight") or defaults.castBarHeight)
            local showArrows = DBVal("showTargetArrows") == true
            local arrowScale = DBVal("targetArrowScale") or defaults.targetArrowScale or 1.0
            local arrowW = math.floor(11 * arrowScale + 0.5)
            local arrowH = math.floor(16 * arrowScale + 0.5)
            if pf._arrows then
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
            -- Text on hpText/hpNumber is set later by the slot-based positioning logic
            cast:SetValue(_previewCastFill or 0.60)
            castParts.icon:SetTexture(displayCastIcons[_previewCastIconIdx or 1])

            -- Border style toggle
            local bStyle = DBVal("borderStyle") or defaults.borderStyle
            if bStyle == "none" then
                borderFrame:Hide(); simpleBorderFrame:Hide()
                for _, e in ipairs(_solidEdges) do e:Hide() end
            elseif bStyle == "simple" then
                borderFrame:Hide(); simpleBorderFrame:Show()
                for _, e in ipairs(_solidEdges) do e:Show() end
            else
                borderFrame:Show(); simpleBorderFrame:Hide()
                for _, e in ipairs(_solidEdges) do e:Show() end
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

            -- Icon sizes from slot-based system
            local debuffSlotVal = DBVal("debuffSlot") or defaults.debuffSlot
            local buffSlotVal   = DBVal("buffSlot")   or defaults.buffSlot
            local ccSlotVal     = DBVal("ccSlot")     or defaults.ccSlot
            local debuffSz = (debuffSlotVal ~= "none") and (DBVal(debuffSlotVal .. "SlotSize") or defaults[debuffSlotVal .. "SlotSize"] or 26) or 26
            local buffSz   = (buffSlotVal ~= "none") and (DBVal(buffSlotVal .. "SlotSize") or defaults[buffSlotVal .. "SlotSize"] or 24) or 24
            local ccSz     = (ccSlotVal ~= "none") and (DBVal(ccSlotVal .. "SlotSize") or defaults[ccSlotVal .. "SlotSize"] or 24) or 24

            -- Gap between icons (user setting), then compute per-type center-to-center spacing
            local gap = DBVal("auraSpacing") or defaults.auraSpacing
            local debuffSpacing = gap + debuffSz
            local buffSpacing   = gap + buffSz
            local ccSpacing     = gap + ccSz

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
                    raidFrame:SetPoint("RIGHT", health, "LEFT", -sideOff + rmXOff, rmYOff)
                elseif rmPos == "right" then
                    local sideOff = DBVal("sideAuraXOffset") or defaults.sideAuraXOffset
                    raidFrame:SetPoint("LEFT", health, "RIGHT", sideOff + rmXOff, rmYOff)
                elseif rmPos == "topleft" then
                    raidFrame:SetPoint("BOTTOMLEFT", health, "TOPLEFT", -2 + rmXOff, cpPush + rmYOff)
                elseif rmPos == "topright" then
                    raidFrame:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", 2 + rmXOff, cpPush + rmYOff)
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
                    classIcon:SetPoint("RIGHT", health, "LEFT", -sideOff + clXOff, clYOff)
                elseif clPos == "right" then
                    local sideOff = DBVal("sideAuraXOffset") or defaults.sideAuraXOffset
                    classIcon:SetPoint("LEFT", health, "RIGHT", sideOff + clXOff, clYOff)
                elseif clPos == "topleft" then
                    classIcon:SetPoint("BOTTOMLEFT", health, "TOPLEFT", -2 + clXOff, 2 + cpPush + clYOff)
                elseif clPos == "topright" then
                    classIcon:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", 2 + clXOff, 2 + cpPush + clYOff)
                end
                classIcon:Show()
                if pf._classOverlay then pf._classOverlay:Show() end
            end

            -- Arrow push is no longer used arrows are placed OUTSIDE auras now
            -- (arrow positioning happens after all auras are placed)

            -- Cast bar: full health bar width, icon hangs outside left edge
            cast:ClearAllPoints()
            cast:SetSize(barW, castH)
            cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, 0)
            cast:SetStatusBarColor(cbColor.r, cbColor.g, cbColor.b, 1)
            -- Apply cast icon visibility and scale from DB
            -- Use SetSize instead of SetScale so AddBorder stays pixel-perfect
            local showIcon = true
            local db = DB()
            if db and db.showCastIcon ~= nil then showIcon = db.showCastIcon end
            if showIcon then
                local iconScale = (db and db.castIconScale) or defaults.castIconScale
                local scaledH = castH * iconScale
                castParts.iconFrame:SetScale(1)
                castParts.iconFrame:SetSize(scaledH, scaledH)
                castParts.iconFrame:Show()
            else
                castParts.iconFrame:SetSize(castH, castH)
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
            local function PlaceHealthInBar(element, anchor, point, xOff, yOff, fontSize, cr, cg, cb)
                yOff = yOff or 0
                if element == "healthPercent" or element == "healthPercentNoSign" then
                    SetPVFont(hpText, fontPath, fontSize, npOutline)
                    hpText:SetParent(healthTextFrame)
                    hpText:SetText(element == "healthPercentNoSign" and pctNoSignStr or pctStr)
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
                elseif element == "healthPctNum" then
                    SetPVFont(hpText, fontPath, fontSize, npOutline)
                    hpText:SetParent(healthTextFrame)
                    hpText:SetText(pctStr .. " | " .. hpNumStr)
                    hpText:SetPoint(point, health, anchor, xOff, yOff)
                    hpText:SetTextColor(cr, cg, cb, 1)
                    hpText:Show()
                elseif element == "healthNumPct" then
                    SetPVFont(hpText, fontPath, fontSize, npOutline)
                    hpText:SetParent(healthTextFrame)
                    hpText:SetText(hpNumStr .. " | " .. pctStr)
                    hpText:SetPoint(point, health, anchor, xOff, yOff)
                    hpText:SetTextColor(cr, cg, cb, 1)
                    hpText:Show()
                end
            end

            -- Helper: position a health-related element in the top slot
            local function PlaceHealthOnTop(element, txOff, tyOff, fontSize, cr, cg, cb)
                txOff = txOff or 0
                tyOff = tyOff or 0
                if element == "healthPercent" or element == "healthPercentNoSign" then
                    SetPVFont(hpText, fontPath, fontSize, npOutline)
                    hpText:SetText(element == "healthPercentNoSign" and pctNoSignStr or pctStr)
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
                elseif element == "healthPctNum" then
                    SetPVFont(hpText, fontPath, fontSize, npOutline)
                    hpText:SetText(pctStr .. " | " .. hpNumStr)
                    hpText:SetParent(topTextFrame)
                    hpText:SetPoint("BOTTOM", health, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
                    hpText:SetTextColor(cr, cg, cb, 1)
                    hpText:Show()
                elseif element == "healthNumPct" then
                    SetPVFont(hpText, fontPath, fontSize, npOutline)
                    hpText:SetText(hpNumStr .. " | " .. pctStr)
                    hpText:SetParent(topTextFrame)
                    hpText:SetPoint("BOTTOM", health, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
                    hpText:SetTextColor(cr, cg, cb, 1)
                    hpText:Show()
                end
            end

            -- Helper: position the name in a bar slot
            local function PlaceNameInBar(anchor, point, xOff, justify, txOff, tyOff, fontSize, cr, cg, cb, nameSlotKey)
                txOff = txOff or 0
                tyOff = tyOff or 0
                SetPVFont(nameFS, fontPath, fontSize, npOutline)
                nameFS:SetParent(healthTextFrame)
                nameFS:SetPoint(point, health, anchor, xOff + txOff, tyOff)
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
                nameFS:SetWidth(math.max(barW - usedWidth, 20))
                nameFS:SetTextColor(cr, cg, cb, 1)
                nameFS:Show()
            end

            -- Process top slot
            local topXOff = DBVal("textSlotTopXOffset") or 0
            local topYOff = DBVal("textSlotTopYOffset") or 0
            local topFontSz = DBVal("textSlotTopSize") or defaults.textSlotTopSize
            local topC = (DB() and DB().textSlotTopColor) or defaults.textSlotTopColor
            if slotTop == "enemyName" then
                SetPVFont(nameFS, fontPath, topFontSz, npOutline)
                nameFS:SetParent(topTextFrame)
                nameFS:SetPoint("BOTTOM", health, "TOP", topXOff, 4 + nameYOff + cpPush + topYOff)
                nameFS:SetJustifyH("CENTER")
                local nameW = barW
                if rmPos ~= "none" and showRM then
                    nameW = barW - 2 * (rmSize - 2) - 7
                end
                if showCL and clPos ~= "none" then
                    nameW = nameW - (reIconSz + 4)
                end
                nameFS:SetWidth(math.max(nameW, 20))
                nameFS:SetTextColor(topC.r, topC.g, topC.b, 1)
                nameFS:Show()
            else
                PlaceHealthOnTop(slotTop, topXOff, topYOff, topFontSz, topC.r, topC.g, topC.b)
            end

            -- Process right slot
            local rightXOff = DBVal("textSlotRightXOffset") or 0
            local rightYOff = DBVal("textSlotRightYOffset") or 0
            local rightFontSz = DBVal("textSlotRightSize") or defaults.textSlotRightSize
            local rightC = (DB() and DB().textSlotRightColor) or defaults.textSlotRightColor
            if slotRight == "enemyName" then
                PlaceNameInBar("RIGHT", "RIGHT", -2, "RIGHT", rightXOff, rightYOff, rightFontSz, rightC.r, rightC.g, rightC.b, "textSlotRight")
            else
                PlaceHealthInBar(slotRight, "RIGHT", "RIGHT", -2 + rightXOff, rightYOff, rightFontSz, rightC.r, rightC.g, rightC.b)
            end

            -- Process left slot
            local leftXOff = DBVal("textSlotLeftXOffset") or 0
            local leftYOff = DBVal("textSlotLeftYOffset") or 0
            local leftFontSz = DBVal("textSlotLeftSize") or defaults.textSlotLeftSize
            local leftC = (DB() and DB().textSlotLeftColor) or defaults.textSlotLeftColor
            if slotLeft == "enemyName" then
                PlaceNameInBar("LEFT", "LEFT", 4, "LEFT", leftXOff, leftYOff, leftFontSz, leftC.r, leftC.g, leftC.b, "textSlotLeft")
            else
                PlaceHealthInBar(slotLeft, "LEFT", "LEFT", 4 + leftXOff, leftYOff, leftFontSz, leftC.r, leftC.g, leftC.b)
            end

            -- Process center slot
            local centerXOff = DBVal("textSlotCenterXOffset") or 0
            local centerYOff = DBVal("textSlotCenterYOffset") or 0
            local centerFontSz = DBVal("textSlotCenterSize") or defaults.textSlotCenterSize
            local centerC = (DB() and DB().textSlotCenterColor) or defaults.textSlotCenterColor
            if slotCenter == "enemyName" then
                PlaceNameInBar("CENTER", "CENTER", 0, "CENTER", centerXOff, centerYOff, centerFontSz, centerC.r, centerC.g, centerC.b, "textSlotCenter")
            else
                PlaceHealthInBar(slotCenter, "CENTER", "CENTER", centerXOff, centerYOff, centerFontSz, centerC.r, centerC.g, centerC.b)
            end

            -- Health bar color: always uses "enemies in combat" color
            local eic = (DB() and DB().enemyInCombat) or defaults.enemyInCombat
            health:SetStatusBarColor(eic.r, eic.g, eic.b, 1)

            -- Cast text sizes and colors
            local cns = DBVal("castNameSize") or defaults.castNameSize
            local cts = DBVal("castTargetSize") or defaults.castTargetSize
            local cnc = (DB() and DB().castNameColor) or defaults.castNameColor
            SetPVFont(castParts.nameFS, fontPath, cns, npOutline)
            SetPVFont(castParts.targetFS, fontPath, cts, npOutline)
            castParts.nameFS:SetTextColor(cnc.r, cnc.g, cnc.b, 1)
            local useClassColor = defaults.castTargetClassColor
            local dbRef = DB()
            if dbRef and dbRef.castTargetClassColor ~= nil then useClassColor = dbRef.castTargetClassColor end
            if useClassColor then
                local _, pClass = UnitClass("player")
                local c = pClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[pClass]
                if c then
                    castParts.targetFS:SetTextColor(c.r, c.g, c.b, 1)
                else
                    castParts.targetFS:SetTextColor(1, 1, 1, 1)
                end
            else
                local ctc = (dbRef and dbRef.castTargetColor) or defaults.castTargetColor
                castParts.targetFS:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
            end

            -- Dynamic cast name width: fill space minus target text minus 5px gap
            local targetTextW = castParts.targetFS:GetUnboundedStringWidth()
            local castNameMaxW = barW - 5 - 3 - targetTextW - 5
            if castNameMaxW < 20 then castNameMaxW = 20 end
            castParts.nameFS:SetWidth(castNameMaxW)

            -- Helper: position a single preview frame into a slot
            local function PlaceInSlot(frame, slotName, index, count, iconW, iconH, slotSpacing, sxOff, syOff)
                sxOff = sxOff or 0
                syOff = syOff or 0
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
                    local baseX = -2 + sxOff
                    local baseY = debuffY + cpPush + syOff
                    if growth == "up" then
                        frame:SetPoint("BOTTOMLEFT", health, "TOPLEFT", baseX, baseY + idx * slotSpacing)
                    elseif growth == "right" then
                        frame:SetPoint("BOTTOMLEFT", health, "TOPLEFT", baseX + idx * slotSpacing, baseY)
                    else
                        frame:SetPoint("BOTTOMLEFT", health, "TOPLEFT", baseX - idx * slotSpacing, baseY)
                    end
                elseif slotName == "topright" then
                    local growth = DBVal("toprightSlotGrowth") or defaults.toprightSlotGrowth
                    local idx = index - 1  -- 0 for icon 1, never moves
                    local baseX = 2 + sxOff
                    local baseY = debuffY + cpPush + syOff
                    if growth == "up" then
                        frame:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", baseX, baseY + idx * slotSpacing)
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

            -- Aura text settings (unified)
            local auraDurSz = DBVal("auraDurationTextSize") or defaults.auraDurationTextSize
            local auraDurC = (DB() and DB().auraDurationTextColor) or defaults.auraDurationTextColor
            local auraStackSz = DBVal("auraStackTextSize") or defaults.auraStackTextSize
            local auraStackC = (DB() and DB().auraStackTextColor) or defaults.auraStackTextColor
            local atPos = DBVal("auraTextPosition") or DBVal("debuffTextPosition") or defaults.auraTextPosition
            local debuffTPos = DBVal("debuffTimerPosition") or atPos
            local buffTPos   = DBVal("buffTimerPosition")   or atPos
            local ccTPos     = DBVal("ccTimerPosition")     or atPos

            -- Helper: apply timer position to a duration text fontstring
            local function ApplyTimerPos(durText, auraFrame, pos)
                if pos == "none" then
                    durText:Hide()
                    return
                end
                durText:Show()
                durText:SetFont(fontPath, auraDurSz, "OUTLINE")
                durText:SetTextColor(auraDurC.r, auraDurC.g, auraDurC.b, 1)
                durText:ClearAllPoints()
                if pos == "center" then
                    durText:SetPoint("CENTER", auraFrame, "CENTER", 0, 0)
                    durText:SetJustifyH("CENTER")
                elseif pos == "topright" then
                    durText:SetPoint("TOPRIGHT", auraFrame, "TOPRIGHT", 3, 4)
                    durText:SetJustifyH("RIGHT")
                else
                    durText:SetPoint("TOPLEFT", auraFrame, "TOPLEFT", -3, 4)
                    durText:SetJustifyH("LEFT")
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
                    debuffs[i]:SetSize(Snap(debuffSz), Snap(debuffSz))
                    debuffs[i].durationText:SetFont(fontPath, auraDurSz, "OUTLINE")
                    debuffs[i].durationText:SetTextColor(auraDurC.r, auraDurC.g, auraDurC.b, 1)
                    ApplyTimerPos(debuffs[i].durationText, debuffs[i], debuffTPos)
                    debuffs[i].stackText:SetFont(fontPath, auraStackSz, "OUTLINE")
                    debuffs[i].stackText:SetTextColor(auraStackC.r, auraStackC.g, auraStackC.b, 1)
                    PlaceInSlot(debuffs[i], debuffSlotVal, i, PV_CONST.DEBUFF_COUNT, debuffSz, debuffSz, debuffSpacing, debuffXOff, debuffYOff)
                end
            end

            -- Buff size + duration text styling + slot position
            for i = 1, PV_CONST.BUFF_COUNT do
                if buffSlotVal == "none" then
                    buffs[i]:Hide()
                else
                    buffs[i]:Show()
                    buffs[i]:SetSize(Snap(buffSz), Snap(buffSz))
                    buffs[i].durationText:SetFont(fontPath, auraDurSz, "OUTLINE")
                    buffs[i].durationText:SetTextColor(auraDurC.r, auraDurC.g, auraDurC.b, 1)
                    ApplyTimerPos(buffs[i].durationText, buffs[i], buffTPos)
                    PlaceInSlot(buffs[i], buffSlotVal, i, PV_CONST.BUFF_COUNT, buffSz, buffSz, buffSpacing, buffXOff, buffYOff)
                end
            end

            -- CC size + duration text styling + slot position
            for i = 1, PV_CONST.CC_COUNT do
                if ccSlotVal == "none" then
                    ccs[i]:Hide()
                else
                    ccs[i]:Show()
                    ccs[i]:SetSize(Snap(ccSz), Snap(ccSz))
                    ccs[i].durationText:SetFont(fontPath, auraDurSz, "OUTLINE")
                    ccs[i].durationText:SetTextColor(auraDurC.r, auraDurC.g, auraDurC.b, 1)
                    ApplyTimerPos(ccs[i].durationText, ccs[i], ccTPos)
                    PlaceInSlot(ccs[i], ccSlotVal, i, PV_CONST.CC_COUNT, ccSz, ccSz, ccSpacing, ccXOff, ccYOff)
                end
            end

            -- Position target arrows OUTSIDE the outermost side auras
            if showArrows then
                arrows.left:ClearAllPoints()
                arrows.right:ClearAllPoints()
                -- Compute per-slot pixel extent on each side (accounts for X offsets)
                local sideOff = DBVal("sideAuraXOffset") or defaults.sideAuraXOffset
                local leftExtent, rightExtent = 0, 0
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
                    leftExtent = math.max(leftExtent, sideOff + rmSize - rmXOff)
                elseif rmPos == "right" and showRM then
                    rightExtent = math.max(rightExtent, sideOff + rmSize + rmXOff)
                end
                -- Classification icon
                if clPos == "left" and showCL then
                    leftExtent = math.max(leftExtent, sideOff + reIconSz - clXOff)
                elseif clPos == "right" and showCL then
                    rightExtent = math.max(rightExtent, sideOff + reIconSz + clXOff)
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
                local texPath = ns.healthBarTextures[texKey]
                if texPath then
                    health:SetStatusBarTexture(texPath)
                else
                    health:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
                end
                UnsnapTex(health:GetStatusBarTexture())
            end

            -- Class power pips (preview uses live class/spec resource count, ~70% filled)
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
                    end
                    CP.bar:Hide()
                else
                    CP.bar:Hide()
                    local cpScale = DBVal("classPowerScale") or defaults.classPowerScale
                    local cpYOff  = DBVal("classPowerYOffset") or defaults.classPowerYOffset
                    local cpXOff  = DBVal("classPowerXOffset") or defaults.classPowerXOffset
                    local cpPos   = DBVal("classPowerPos") or defaults.classPowerPos
                    local cpGap   = DBVal("classPowerGap") or defaults.classPowerGap
                    local scaledW   = Snap(CP.PIP_W * cpScale)
                    local scaledH   = Snap(CP.PIP_H * cpScale)
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
                                bg:SetColorTexture(cpBgCol.r, cpBgCol.g, cpBgCol.b, cpBgCol.a)
                                bg:Show()
                            end

                            if i <= cpCur then
                                pip:SetColorTexture(cpColor[1], cpColor[2], cpColor[3], 1)
                            else
                                pip:SetColorTexture(cpEmptyCol.r, cpEmptyCol.g, cpEmptyCol.b, cpEmptyCol.a)
                            end
                            UnsnapTex(pip)
                            pip:Show()
                        else
                            pip:Hide()
                            if pip._bg then pip._bg:Hide() end
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
                end
                CP.bar:Hide()
            end

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
            local glowStyle = DBVal("targetGlowStyle") or defaults.targetGlowStyle
            if showTargetGlowPreview and (glowStyle == "ellesmereui" or glowStyle == "vibrant") then
                pgf:Show()
            else
                pgf:Hide()
            end
            -- Vibrant: also override border to white on preview
            if showTargetGlowPreview and glowStyle == "vibrant" then
                for _, tex in ipairs(borderFrame._texs) do tex:SetVertexColor(1, 1, 1) end
                for _, tex in ipairs(simpleBorderFrame._texs) do tex:SetVertexColor(1, 1, 1) end
                for _, e in ipairs(_solidEdges) do e:SetColorTexture(1, 1, 1, 1); UnsnapTex(e) end
            end

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

        -- Use the core addon's migration logic (writes back to DB)
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
            ns.StartProceduralAnts(f, N, th, period, lineLen, cr, cg, cb, iconSize)
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

        local function friendlyPlayersOff() return DBVal("showFriendlyPlayers") == false and DBVal("friendlyShowDefaultNames") ~= true end
        local function friendlyPlateOff() return friendlyPlayersOff() or DBVal("friendlyNameOnly") ~= false end
        local function nameOnlyOff() return friendlyPlayersOff() or DBVal("friendlyNameOnly") == false end

        local friendlyRow
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Friendly Player Nameplates",
              getValue=function() return DBVal("showFriendlyPlayers") ~= false end,
              setValue=function(v)
                DB().showFriendlyPlayers = v
                if v then DB().friendlyShowDefaultNames = false end
                if SetCVar then
                    pcall(SetCVar, "nameplateShowFriendlyPlayers", v and 1 or 0)
                    pcall(SetCVar, "nameplateShowFriendlyPlayerUnits", v and 1 or 0)
                    pcall(SetCVar, "UnitNameFriendlyPlayerName", v and 1 or 0)
                    pcall(SetCVar, "nameplateShowFriends", v and 1 or 0)
                end
                if ns.UpdateFriendlyNameplateSystem then ns.UpdateFriendlyNameplateSystem() end
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
              disabledTooltip = "Show Friendly Player Nameplates" });  friendlyRow = _; y = y - h

        ---------------------------------------------------------------
        --  Friendly Player cog popup (Distance, Height, Width, Show Health %)
        ---------------------------------------------------------------
        do
            local fpPopup, fpPopupOwner
            local function ShowFriendlyPlayerPopup(anchorBtn)
                if not fpPopup then
                    local SolidTex   = EllesmereUI.SolidTex
                    local MakeBorder = EllesmereUI.MakeBorder
                    local MakeFont   = EllesmereUI.MakeFont
                    local BuildSliderCore = EllesmereUI.BuildSliderCore
                    local BORDER_COLOR   = EllesmereUI.BORDER_COLOR
                    local SL_INPUT_A     = EllesmereUI.SL_INPUT_A

                    local SIDE_PAD = 14; local TOP_PAD = 14
                    local TITLE_H = 11; local TITLE_GAP = 10; local GAP = 10
                    local ROW_H = 24; local TOGGLE_ROW_H = 28
                    local POPUP_INPUT_A = 0.55

                    local INPUT_W = 34; local SLIDER_INPUT_GAP = 8; local LABEL_SLIDER_GAP = 12
                    local MIN_POPUP_W = 180

                    local totalH = TOP_PAD + TITLE_H + TITLE_GAP + GAP
                                 + ROW_H + GAP + ROW_H + GAP + ROW_H + GAP + TOGGLE_ROW_H + GAP + TOGGLE_ROW_H
                                 + TOP_PAD

                    local pf = CreateFrame("Frame", nil, UIParent)
                    pf:SetSize(260, totalH)
                    pf:SetFrameStrata("DIALOG"); pf:SetFrameLevel(200)
                    pf:EnableMouse(true); pf:Hide()

                    local bg = SolidTex(pf, "BACKGROUND", 0.06, 0.08, 0.10, 0.95)
                    bg:SetAllPoints()
                    MakeBorder(pf, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15)

                    local titleFS = MakeFont(pf, 11, "", 1, 1, 1)
                    titleFS:SetAlpha(0.7)
                    titleFS:SetPoint("TOP", pf, "TOP", 0, -TOP_PAD)
                    titleFS:SetText("Friendly Nameplate Settings")

                    -- Measure label widths to compute layout BEFORE creating sliders
                    local tmpFS = pf:CreateFontString(nil, "OVERLAY")
                    tmpFS:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, GetNPOptOutline())
                    local labelTexts = {"Distance", "Height", "Width"}
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

                    -- Row 1: Distance from Friend
                    local r1Y = -(TOP_PAD + TITLE_H + TITLE_GAP + GAP)
                    local lbl1 = MakeFont(pf, 11, nil, 1, 1, 1); lbl1:SetAlpha(0.6)
                    lbl1:SetText("Distance"); lbl1:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r1Y)
                    local t1, v1 = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, ROW_H, 11, POPUP_INPUT_A,
                        -50, 50, 1,
                        function() return DBVal("friendlyPlateYOffset") or 0 end,
                        function(v) DB().friendlyPlateYOffset = v; if ns.RefreshFriendlyPlateYOffset then ns.RefreshFriendlyPlateYOffset() end end, true)
                    t1:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, r1Y - 2)
                    v1:ClearAllPoints(); v1:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r1Y)

                    -- Row 2: Height
                    local r2Y = r1Y - ROW_H - GAP
                    local lbl2 = MakeFont(pf, 11, nil, 1, 1, 1); lbl2:SetAlpha(0.6)
                    lbl2:SetText("Height"); lbl2:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r2Y)
                    local t2, v2 = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, ROW_H, 11, POPUP_INPUT_A,
                        6, 40, 1,
                        function() return DBVal("friendlyHealthBarHeight") or defaults.friendlyHealthBarHeight end,
                        function(v) DB().friendlyHealthBarHeight = v; if ns.RefreshFriendlyPlateSize then ns.RefreshFriendlyPlateSize() end end, true)
                    t2:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, r2Y - 2)
                    v2:ClearAllPoints(); v2:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r2Y)

                    -- Row 3: Width
                    local r3Y = r2Y - ROW_H - GAP
                    local lbl3 = MakeFont(pf, 11, nil, 1, 1, 1); lbl3:SetAlpha(0.6)
                    lbl3:SetText("Width"); lbl3:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r3Y)
                    local t3, v3 = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, ROW_H, 11, POPUP_INPUT_A,
                        80, 250, 1,
                        function() return DBVal("friendlyHealthBarWidth") or defaults.friendlyHealthBarWidth end,
                        function(v) DB().friendlyHealthBarWidth = v; if ns.RefreshFriendlyPlateSize then ns.RefreshFriendlyPlateSize() end end, true)
                    t3:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, r3Y - 2)
                    v3:ClearAllPoints(); v3:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r3Y)

                    -- Row 4: Show Health Percent (toggle inverted from friendlyHideHealthText)
                    local r4Y = r3Y - ROW_H - GAP
                    local lbl4 = MakeFont(pf, 11, nil, 1, 1, 1); lbl4:SetAlpha(0.6)
                    lbl4:SetText("Show Health Percent"); lbl4:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r4Y)

                    local TG_W, TG_H, KNOB_SZ, KNOB_PAD = 32, 16, 12, 2
                    local tgBtn = CreateFrame("Button", nil, pf)
                    tgBtn:SetSize(TG_W, TG_H)
                    tgBtn:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r4Y)

                    local tgBg = SolidTex(tgBtn, "BACKGROUND", 0.18, 0.18, 0.18, 0.85)
                    tgBg:SetAllPoints()
                    local tgKnob = tgBtn:CreateTexture(nil, "ARTWORK")
                    tgKnob:SetColorTexture(0.55, 0.55, 0.55, 1)
                    tgKnob:SetSize(KNOB_SZ, KNOB_SZ)

                    local function UpdateToggle4()
                        local on = not (EllesmereUINameplatesDB and EllesmereUINameplatesDB.friendlyHideHealthText)
                        if on then
                            local g = EllesmereUI.ELLESMERE_GREEN
                            tgBg:SetColorTexture(g.r, g.g, g.b, 0.45)
                            tgKnob:SetColorTexture(1, 1, 1, 0.95)
                            tgKnob:ClearAllPoints(); tgKnob:SetPoint("RIGHT", tgBtn, "RIGHT", -KNOB_PAD, 0)
                        else
                            tgBg:SetColorTexture(0.18, 0.18, 0.18, 0.85)
                            tgKnob:SetColorTexture(0.55, 0.55, 0.55, 1)
                            tgKnob:ClearAllPoints(); tgKnob:SetPoint("LEFT", tgBtn, "LEFT", KNOB_PAD, 0)
                        end
                    end
                    UpdateToggle4()
                    tgBtn:SetScript("OnClick", function()
                        local cur = EllesmereUINameplatesDB and EllesmereUINameplatesDB.friendlyHideHealthText or false
                        DB().friendlyHideHealthText = not cur
                        if ns.RefreshFriendlyHealthText then ns.RefreshFriendlyHealthText() end
                        UpdateToggle4()
                    end)
                    pf._updateToggle = UpdateToggle4

                    -- Row 5: Show Default Names
                    local r5Y = r4Y - TOGGLE_ROW_H - GAP
                    local lbl5 = MakeFont(pf, 11, nil, 1, 1, 1); lbl5:SetAlpha(0.6)
                    lbl5:SetText("Show Default Names"); lbl5:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r5Y)

                    local tgBtn5 = CreateFrame("Button", nil, pf)
                    tgBtn5:SetSize(TG_W, TG_H)
                    tgBtn5:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r5Y)

                    local tgBg5 = SolidTex(tgBtn5, "BACKGROUND", 0.18, 0.18, 0.18, 0.85)
                    tgBg5:SetAllPoints()
                    local tgKnob5 = tgBtn5:CreateTexture(nil, "ARTWORK")
                    tgKnob5:SetColorTexture(0.55, 0.55, 0.55, 1)
                    tgKnob5:SetSize(KNOB_SZ, KNOB_SZ)

                    local function UpdateToggle5()
                        local on = (EllesmereUINameplatesDB and EllesmereUINameplatesDB.friendlyShowDefaultNames == true)
                        if on then
                            local g = EllesmereUI.ELLESMERE_GREEN
                            tgBg5:SetColorTexture(g.r, g.g, g.b, 0.45)
                            tgKnob5:SetColorTexture(1, 1, 1, 0.95)
                            tgKnob5:ClearAllPoints(); tgKnob5:SetPoint("RIGHT", tgBtn5, "RIGHT", -KNOB_PAD, 0)
                        else
                            tgBg5:SetColorTexture(0.18, 0.18, 0.18, 0.85)
                            tgKnob5:SetColorTexture(0.55, 0.55, 0.55, 1)
                            tgKnob5:ClearAllPoints(); tgKnob5:SetPoint("LEFT", tgBtn5, "LEFT", KNOB_PAD, 0)
                        end
                    end
                    UpdateToggle5()
                    tgBtn5:SetScript("OnClick", function()
                        local cur = EllesmereUINameplatesDB and EllesmereUINameplatesDB.friendlyShowDefaultNames or false
                        local newVal = not cur
                        DB().friendlyShowDefaultNames = newVal
                        if newVal then
                            -- Turn off friendly nameplates, keep names on
                            DB().showFriendlyPlayers = false
                            if SetCVar then
                                pcall(SetCVar, "nameplateShowFriendlyPlayers", 0)
                                pcall(SetCVar, "nameplateShowFriendlyPlayerUnits", 0)
                                pcall(SetCVar, "nameplateShowFriends", 0)
                                pcall(SetCVar, "UnitNameFriendlyPlayerName", 1)
                            end
                        else
                            if SetCVar then
                                pcall(SetCVar, "UnitNameFriendlyPlayerName", 0)
                            end
                        end
                        if ns.UpdateFriendlyNameplateSystem then ns.UpdateFriendlyNameplateSystem() end
                        if EllesmereUI and EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
                        UpdateToggle5()
                    end)

                    pf._updateToggle = function()
                        UpdateToggle4()
                        UpdateToggle5()
                    end

                    -- Close on click outside
                    local wasDown = false
                    pf:SetScript("OnHide", function(self)
                        self:SetScript("OnUpdate", nil)
                        if fpPopupOwner then fpPopupOwner:SetAlpha(0.4) end
                        fpPopupOwner = nil
                    end)
                    pf._clickOutside = function(self, dt)
                        local down = IsMouseButtonDown("LeftButton")
                        if down and not wasDown then
                            if not self:IsMouseOver() and not (fpPopupOwner and fpPopupOwner:IsMouseOver()) then
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

                    fpPopup = pf
                end

                -- Toggle off if same icon clicked again
                if fpPopupOwner == anchorBtn and fpPopup:IsShown() then
                    fpPopup:Hide(); return
                end
                fpPopupOwner = anchorBtn
                if fpPopup._updateToggle then fpPopup._updateToggle() end

                fpPopup:ClearAllPoints()
                fpPopup:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6)
                fpPopup:SetAlpha(0)
                fpPopup:Show()
                local elapsed = 0
                fpPopup:SetScript("OnUpdate", function(self, dt)
                    elapsed = elapsed + dt
                    local t = math.min(elapsed / 0.15, 1)
                    self:SetAlpha(t)
                    self:ClearAllPoints()
                    self:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6 + (-8 * (1 - t)))
                    if t >= 1 then self:SetScript("OnUpdate", self._clickOutside) end
                end)
            end

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
        --  Name Only cog popup (Class Colored, Distance from Friend)
        ---------------------------------------------------------------
        do
            local noPopup, noPopupOwner
            local function ShowNameOnlyPopup(anchorBtn)
                if not noPopup then
                    local SolidTex   = EllesmereUI.SolidTex
                    local MakeBorder = EllesmereUI.MakeBorder
                    local MakeFont   = EllesmereUI.MakeFont
                    local BuildSliderCore = EllesmereUI.BuildSliderCore
                    local BORDER_COLOR   = EllesmereUI.BORDER_COLOR
                    local SL_INPUT_A     = EllesmereUI.SL_INPUT_A

                    local SIDE_PAD = 14; local TOP_PAD = 14
                    local TITLE_H = 11; local TITLE_GAP = 10; local GAP = 10
                    local TOGGLE_ROW_H = 28; local ROW_H = 24
                    local POPUP_INPUT_A = 0.55

                    local INPUT_W = 34; local SLIDER_INPUT_GAP = 8; local LABEL_SLIDER_GAP = 12
                    local MIN_POPUP_W = 180

                    local totalH = TOP_PAD + TITLE_H + TITLE_GAP + GAP
                                 + TOGGLE_ROW_H + GAP + ROW_H
                                 + TOP_PAD

                    local pf = CreateFrame("Frame", nil, UIParent)
                    pf:SetSize(260, totalH)
                    pf:SetFrameStrata("DIALOG"); pf:SetFrameLevel(200)
                    pf:EnableMouse(true); pf:Hide()

                    local bg = SolidTex(pf, "BACKGROUND", 0.06, 0.08, 0.10, 0.95)
                    bg:SetAllPoints()
                    MakeBorder(pf, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15)

                    local titleFS = MakeFont(pf, 11, "", 1, 1, 1)
                    titleFS:SetAlpha(0.7)
                    titleFS:SetPoint("TOP", pf, "TOP", 0, -TOP_PAD)
                    titleFS:SetText("Name Only Settings")

                    -- Row 1: Class Colored (toggle)
                    local r1Y = -(TOP_PAD + TITLE_H + TITLE_GAP + GAP)
                    local lbl1 = MakeFont(pf, 11, nil, 1, 1, 1); lbl1:SetAlpha(0.6)
                    lbl1:SetText("Class Colored"); lbl1:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r1Y)

                    local TG_W, TG_H, KNOB_SZ, KNOB_PAD = 32, 16, 12, 2
                    local tgBtn = CreateFrame("Button", nil, pf)
                    tgBtn:SetSize(TG_W, TG_H)
                    tgBtn:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r1Y)

                    local tgBg = SolidTex(tgBtn, "BACKGROUND", 0.18, 0.18, 0.18, 0.85)
                    tgBg:SetAllPoints()
                    local tgKnob = tgBtn:CreateTexture(nil, "ARTWORK")
                    tgKnob:SetColorTexture(0.55, 0.55, 0.55, 1)
                    tgKnob:SetSize(KNOB_SZ, KNOB_SZ)

                    local function UpdateToggleCC()
                        local on = DBVal("classColorFriendly") ~= false
                        if on then
                            local g = EllesmereUI.ELLESMERE_GREEN
                            tgBg:SetColorTexture(g.r, g.g, g.b, 0.45)
                            tgKnob:SetColorTexture(1, 1, 1, 0.95)
                            tgKnob:ClearAllPoints(); tgKnob:SetPoint("RIGHT", tgBtn, "RIGHT", -KNOB_PAD, 0)
                        else
                            tgBg:SetColorTexture(0.18, 0.18, 0.18, 0.85)
                            tgKnob:SetColorTexture(0.55, 0.55, 0.55, 1)
                            tgKnob:ClearAllPoints(); tgKnob:SetPoint("LEFT", tgBtn, "LEFT", KNOB_PAD, 0)
                        end
                    end
                    UpdateToggleCC()
                    tgBtn:SetScript("OnClick", function()
                        local cur = DBVal("classColorFriendly") ~= false
                        DB().classColorFriendly = not cur
                        if SetCVar then
                            pcall(SetCVar, "ShowClassColorInFriendlyNameplate", (not cur) and 1 or 0)
                            pcall(SetCVar, "nameplateUseClassColorForFriendlyPlayerUnitNames", (not cur) and 1 or 0)
                        end
                        UpdateToggleCC()
                    end)
                    pf._updateToggle = UpdateToggleCC

                    -- Row 2: Distance from Friend (slider)
                    local r2Y = r1Y - TOGGLE_ROW_H - GAP

                    -- Measure label widths to compute layout BEFORE creating sliders
                    local tmpFS = pf:CreateFontString(nil, "OVERLAY")
                    tmpFS:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, GetNPOptOutline())
                    local labelTexts = {"Distance"}
                    local maxLblW = 0
                    for _, txt in ipairs(labelTexts) do
                        tmpFS:SetText(txt)
                        local w = tmpFS:GetStringWidth()
                        if w > maxLblW then maxLblW = w end
                    end
                    tmpFS:Hide()
                    if maxLblW < 10 then maxLblW = 55 end

                    local SLIDER_LEFT = SIDE_PAD + maxLblW + LABEL_SLIDER_GAP
                    local SLIDER_W = math.max(80, 260 - SLIDER_LEFT - SLIDER_INPUT_GAP - INPUT_W - SIDE_PAD)
                    local POPUP_W = math.max(MIN_POPUP_W, SLIDER_LEFT + SLIDER_W + SLIDER_INPUT_GAP + INPUT_W + SIDE_PAD)
                    pf:SetWidth(POPUP_W)

                    local lbl2 = MakeFont(pf, 11, nil, 1, 1, 1); lbl2:SetAlpha(0.6)
                    lbl2:SetText("Distance"); lbl2:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r2Y)
                    local t2, v2 = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, ROW_H, 11, POPUP_INPUT_A,
                        -50, 50, 1,
                        function() return DBVal("friendlyNameOnlyYOffset") or defaults.friendlyNameOnlyYOffset end,
                        function(v) DB().friendlyNameOnlyYOffset = v; if ns.RefreshFriendlyNameOnlyOffset then ns.RefreshFriendlyNameOnlyOffset() end end, true)
                    t2:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, r2Y - 2)
                    v2:ClearAllPoints(); v2:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r2Y)

                    -- Close on click outside
                    local wasDown = false
                    pf:SetScript("OnHide", function(self)
                        self:SetScript("OnUpdate", nil)
                        if noPopupOwner then noPopupOwner:SetAlpha(0.4) end
                        noPopupOwner = nil
                    end)
                    pf._clickOutside = function(self, dt)
                        local down = IsMouseButtonDown("LeftButton")
                        if down and not wasDown then
                            if not self:IsMouseOver() and not (noPopupOwner and noPopupOwner:IsMouseOver()) then
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

                    noPopup = pf
                end

                -- Toggle off if same icon clicked again
                if noPopupOwner == anchorBtn and noPopup:IsShown() then
                    noPopup:Hide(); return
                end
                noPopupOwner = anchorBtn
                if noPopup._updateToggle then noPopup._updateToggle() end

                noPopup:ClearAllPoints()
                noPopup:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6)
                noPopup:SetAlpha(0)
                noPopup:Show()
                local elapsed = 0
                noPopup:SetScript("OnUpdate", function(self, dt)
                    elapsed = elapsed + dt
                    local t = math.min(elapsed / 0.15, 1)
                    self:SetAlpha(t)
                    self:ClearAllPoints()
                    self:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6 + (-8 * (1 - t)))
                    if t >= 1 then self:SetScript("OnUpdate", self._clickOutside) end
                end)
            end

            local rgn = friendlyRow._rightRegion
            local btn = CreateFrame("Button", nil, rgn)
            btn:SetSize(26, 26)
            btn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
            btn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            btn:SetAlpha(nameOnlyOff() and 0.15 or 0.4)
            local tex = btn:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints(); tex:SetTexture(COGS_ICON)
            btn:SetScript("OnEnter", function(self)
                if nameOnlyOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "Requires Name Only mode")
                else self:SetAlpha(0.7) end
            end)
            btn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                if noPopupOwner ~= self then self:SetAlpha(nameOnlyOff() and 0.15 or 0.4) end
            end)
            btn:SetScript("OnClick", function(self)
                if nameOnlyOff() then return end
                ShowNameOnlyPopup(self)
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                if noPopupOwner ~= btn then btn:SetAlpha(nameOnlyOff() and 0.15 or 0.4) end
            end)
        end

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Friendly NPC Nameplates",
              getValue=function() return DBVal("showFriendlyNPCs") == true end,
              setValue=function(v)
                DB().showFriendlyNPCs = v
                if SetCVar then
                    pcall(SetCVar, "nameplateShowFriendlyNPCs", v and 1 or 0)
                    pcall(SetCVar, "nameplateShowFriendlyNpcs", v and 1 or 0)
                end
                if ns.UpdateFriendlyNameplateSystem then ns.UpdateFriendlyNameplateSystem() end
              end },
            { type="toggle", text="Show Enemy Pet Nameplates",
              getValue=function() return DBVal("showEnemyPets") == true end,
              setValue=function(v)
                DB().showEnemyPets = v
                if SetCVar then pcall(SetCVar, "nameplateShowEnemyPets", v and 1 or 0) end
              end,
              tooltip="Toggle visibility of enemy pet nameplates." });  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  ENEMY NAMEPLATE SPACING
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_ENEMY_NP, y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="slider", text="Stacked Nameplate Spacing",
              trackWidth=130,
              min=50, max=200, step=5,
              getValue=function() return DBVal("stackSpacingScale") or defaults.stackSpacingScale end,
              setValue=function(v)
                DB().stackSpacingScale = v
                ns.RefreshStackingBounds()
              end,
              tooltip="Adjusts the vertical spacing between stacked nameplates. 100% = default, lower = tighter, higher = more spread." },
            { type="slider", text="Nameplate Distance from Enemy",
              trackWidth=110,
              min=-50, max=50, step=1,
              getValue=function() return DBVal("nameplateYOffset") or defaults.nameplateYOffset end,
              setValue=function(v)
                DB().nameplateYOffset = v
                ns.RefreshNameplateYOffset()
              end });  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Stacking Nameplates",
              getValue=function() return DBVal("stackingEnabled") ~= false end,
              setValue=function(v)
                DB().stackingEnabled = v
                ns.RefreshStackingMotion()
              end,
              tooltip="When enabled, nameplates stack vertically instead of overlapping." },
            { type="label", text="" });  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  EXTRAS
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_MISC, y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show All Your Player Debuffs",
              getValue=function() return DBVal("showAllDebuffs") == true end,
              setValue=function(v)
                DB().showAllDebuffs = v
                RefreshAllAuras()
              end,
              tooltip="This will display ALL of your debuffs on enemy nameplates, rather than only the important ones." },
            { type="slider", text="Scale Nameplate On Cast",
              trackWidth=110,
              min=50, max=200, step=5,
              getValue=function() return DBVal("castScale") or defaults.castScale end,
              setValue=function(v)
                DB().castScale = v
              end,
              tooltip="Scales enemy nameplates while they are casting. 100% = no change." });  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Use Aura Spell ID Filter",
              getValue=function() return DBVal("useAuraFilter") == true end,
              setValue=function(v)
                DB().useAuraFilter = v
                RefreshAllAuras()
              end,
              tooltip="Apply the global Aura Spell ID Filter (configured in Global Settings) to nameplates." },
            { type="label", text="" });  y = y - h

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
            EllesmereUI.RegisterWidgetRefresh(UpdatePreviewGrayOut)
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

        -- Pixel Glow sub-options: only enabled when style is "Pixel Glow" (index 1)
        local function antsOff()
            if pandemicOff() then return true end
            local raw = DBVal("pandemicGlowStyle")
            if type(raw) ~= "number" then return true end
            return raw ~= 1
        end

        -- Cog popup for Pixel Glow settings (Lines, Thickness, Speed)
        do
            local pgPopup, pgPopupOwner
            local function ShowPixelGlowPopup(anchorBtn)
                if not pgPopup then
                    local SolidTex   = EllesmereUI.SolidTex
                    local MakeBorder = EllesmereUI.MakeBorder
                    local MakeFont   = EllesmereUI.MakeFont
                    local BuildSliderCore = EllesmereUI.BuildSliderCore
                    local BORDER_COLOR   = EllesmereUI.BORDER_COLOR
                    local SL_INPUT_A     = EllesmereUI.SL_INPUT_A

                    local SIDE_PAD = 14; local TOP_PAD = 14
                    local TITLE_H = 11; local TITLE_GAP = 10; local GAP = 10
                    local ROW_H = 24
                    local POPUP_INPUT_A = 0.55

                    local INPUT_W = 34; local SLIDER_INPUT_GAP = 8; local LABEL_SLIDER_GAP = 12
                    local MIN_POPUP_W = 180

                    local totalH = TOP_PAD + TITLE_H + TITLE_GAP + GAP
                                 + ROW_H + GAP + ROW_H + GAP + ROW_H
                                 + TOP_PAD

                    local pf = CreateFrame("Frame", nil, UIParent)
                    pf:SetSize(260, totalH)
                    pf:SetFrameStrata("DIALOG"); pf:SetFrameLevel(200)
                    pf:EnableMouse(true); pf:Hide()

                    local bg = SolidTex(pf, "BACKGROUND", 0.06, 0.08, 0.10, 0.95)
                    bg:SetAllPoints()
                    MakeBorder(pf, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15)

                    local titleFS = MakeFont(pf, 11, "", 1, 1, 1)
                    titleFS:SetAlpha(0.7)
                    titleFS:SetPoint("TOP", pf, "TOP", 0, -TOP_PAD)
                    titleFS:SetText("Pixel Glow Settings")

                    -- Measure label widths to compute layout BEFORE creating sliders
                    local tmpFS = pf:CreateFontString(nil, "OVERLAY")
                    tmpFS:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, GetNPOptOutline())
                    local labelTexts = {"Lines", "Thickness", "Speed"}
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
                    lbl1:SetText("Lines"); lbl1:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r1Y)
                    local t1, v1 = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, ROW_H, 11, POPUP_INPUT_A,
                        2, 16, 1,
                        function() return DBVal("pandemicGlowLines") or defaults.pandemicGlowLines end,
                        function(v) DB().pandemicGlowLines = v; RefreshAllAuras(); RefreshPandemicPreview() end, true)
                    t1:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, r1Y - 2)
                    v1:ClearAllPoints(); v1:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r1Y)

                    -- Row 2: Thickness
                    local r2Y = r1Y - ROW_H - GAP
                    local lbl2 = MakeFont(pf, 11, nil, 1, 1, 1); lbl2:SetAlpha(0.6)
                    lbl2:SetText("Thickness"); lbl2:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r2Y)
                    local t2, v2 = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, ROW_H, 11, POPUP_INPUT_A,
                        1, 4, 1,
                        function() return DBVal("pandemicGlowThickness") or defaults.pandemicGlowThickness end,
                        function(v) DB().pandemicGlowThickness = v; RefreshAllAuras(); RefreshPandemicPreview() end, true)
                    t2:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, r2Y - 2)
                    v2:ClearAllPoints(); v2:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r2Y)

                    -- Row 3: Speed (inverted: display = 9 - stored)
                    local r3Y = r2Y - ROW_H - GAP
                    local lbl3 = MakeFont(pf, 11, nil, 1, 1, 1); lbl3:SetAlpha(0.6)
                    lbl3:SetText("Speed"); lbl3:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r3Y)
                    local t3, v3 = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, ROW_H, 11, POPUP_INPUT_A,
                        1, 8, 1,
                        function()
                            local period = DBVal("pandemicGlowSpeed") or defaults.pandemicGlowSpeed
                            return 9 - period
                        end,
                        function(v) DB().pandemicGlowSpeed = 9 - v; RefreshAllAuras(); RefreshPandemicPreview() end, true)
                    t3:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, r3Y - 2)
                    v3:ClearAllPoints(); v3:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r3Y)

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
                    if reg and reg.GetText and reg:GetText() == "Hash Line Location" then
                        sliderLabel = reg
                        break
                    end
                end
                if sliderLabel then
                    suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
                else
                    suffixFS:SetPoint("LEFT", rightFrame, "LEFT", 180, -1)
                end
                suffixFS:SetText("(Percent)")
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

        -- Row 4: Focus Cast Height slider
        local focusCastRow
        focusCastRow, h = W:DualRow(parent, y,
            { type="slider", text="Focus Cast Height",
              trackWidth=110,
              min=100, max=200, step=5,
              getValue=function() return DBVal("focusCastHeight") or defaults.focusCastHeight end,
              setValue=function(v)
                DB().focusCastHeight = v
                ns.RefreshAllSettings()
              end,
              tooltip="Increases the cast bar height on your focus target's nameplate. 100% = normal height." },
            { type="label", text="" });  y = y - h

        -- Add "(Percent)" suffix in smaller, dimmer text next to the slider label
        do
            local leftFrame = focusCastRow._leftRegion
            if leftFrame then
                local suffixFS = leftFrame:CreateFontString(nil, "OVERLAY")
                suffixFS:SetFont(EllesmereUI.EXPRESSWAY, 11, GetNPOptOutline())
                suffixFS:SetTextColor(1, 1, 1, 0.35)
                local sliderLabel
                for i = 1, leftFrame:GetNumRegions() do
                    local reg = select(i, leftFrame:GetRegions())
                    if reg and reg.GetText and reg:GetText() == "Focus Cast Height" then
                        sliderLabel = reg
                        break
                    end
                end
                if sliderLabel then
                    suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
                else
                    suffixFS:SetPoint("LEFT", leftFrame, "LEFT", 180, -1)
                end
                suffixFS:SetText("(Percent)")
            end
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Display page  (preview in content header + settings in scroll area)
    ---------------------------------------------------------------------------
    local _updatePreviewHooked = false

    local _refreshAllPlatesHooked = false

    local function BuildDisplayPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        local function isBorderNone()
            return (DBVal("borderStyle") or defaults.borderStyle) == "none"
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
                    _previewHintFS:SetText("Click elements to scroll to and highlight their options")
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

        -- Hook UpdatePreview so every widget setValue callback that calls it
        -- automatically triggers drift detection (auto-creates "Custom" when editing a built-in).
        -- Only hook once: the original UpdatePreview is a simple wrapper around activePreview:Update().
        -- After hooking, subsequent BuildDisplayPage calls reuse the already-hooked version.
        if not _updatePreviewHooked then
            _updatePreviewHooked = true
            local _origUpdatePreview = UpdatePreview
            UpdatePreview = function()
                _origUpdatePreview()
                if onPresetSettingChanged then onPresetSettingChanged() end
            end
        end

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
                local spacing = ns.GetAuraSpacing()
                local ds, bs, cs = ns.GetAuraSlots()
                if bs ~= "none" then
                    local buffSz = ns.GetBuffIconSize()
                    local bxOff, byOff = ns.GetSlotOffsets(bs)
                    ns.PositionAuraSlot(plate.buffs, 4, bs, plate, buffSz, buffSz, spacing, bxOff, byOff)
                else
                    for i = 1, 4 do plate.buffs[i]:Hide() end
                end
                if cs ~= "none" then
                    local ccSz = ns.GetCCIconSize()
                    local cxOff, cyOff = ns.GetSlotOffsets(cs)
                    ns.PositionAuraSlot(plate.cc, 2, cs, plate, ccSz, ccSz, spacing, cxOff, cyOff)
                else
                    for i = 1, 2 do plate.cc[i]:Hide() end
                end
                if ds == "none" then
                    for i = 1, 4 do plate.debuffs[i]:Hide() end
                end
                plate:UpdateRaidIcon()
                plate:UpdateClassification()
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
            ["none"]      = "None",
        }
        local timerPosOrder = { "topleft", "center", "topright", "none" }

        -- Shared helper: apply a timer position to live plates for one aura type
        local function LiveApplyTimerPos(auraFrames, count, v)
            local durC = (DB() and DB().auraDurationTextColor) or defaults.auraDurationTextColor
            local durSz = DBVal("auraDurationTextSize") or defaults.auraDurationTextSize
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
                                SetFSFont(af.cd.text, durSz, "OUTLINE")
                                af.cd.text:SetTextColor(durC.r, durC.g, durC.b, 1)
                                af.cd.text:ClearAllPoints()
                                if v == "center" then
                                    af.cd.text:SetPoint("CENTER", af, "CENTER", 0, 0)
                                    af.cd.text:SetJustifyH("CENTER")
                                elseif v == "topright" then
                                    PP.Point(af.cd.text, "TOPRIGHT", af, "TOPRIGHT", 3, 4)
                                    af.cd.text:SetJustifyH("RIGHT")
                                else
                                    PP.Point(af.cd.text, "TOPLEFT", af, "TOPLEFT", -3, 4)
                                    af.cd.text:SetJustifyH("LEFT")
                                end
                            end
                        end
                    end
                end
            end
        end

        local atFallback = DBVal("auraTextPosition") or DBVal("debuffTextPosition") or defaults.auraTextPosition

        -----------------------------------------------------------------------
        --  STYLE
        -----------------------------------------------------------------------
        local styleHeader
        styleHeader, h = W:SectionHeader(parent, "STYLE", y);  y = y - h

        local targetGlowRow
        targetGlowRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Target Glow Style",
              values={ ellesmereui = "EllesmereUI", vibrant = "Vibrant", none = "None" },
              getValue=function() return DBVal("targetGlowStyle") or defaults.targetGlowStyle end,
              setValue=function(v)
                DB().targetGlowStyle = v
                for _, plate in pairs(plates) do plate:ApplyTarget() end
                UpdatePreview()
              end,
              order={ "ellesmereui", "vibrant", "none" } },
            { type="toggle", text="Show Arrows on Target",
              getValue=function() return DBVal("showTargetArrows") == true end,
              setValue=function(v)
                DB().showTargetArrows = v
                for _, plate in pairs(plates) do
                    plate:ApplyTarget(); plate:UpdateAuras()
                end
                UpdatePreview()
              end });  y = y - h

        -- Inline cog on Show Arrows (right region) for arrow scale
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
                        for _, plate in pairs(plates) do
                            local sc = v
                            local aw = math.floor(11 * sc + 0.5)
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
            arrowCogBtn:SetPoint("RIGHT", rightRgn._control, "LEFT", -8, 0)
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
            eyeBtn:SetPoint("RIGHT", leftRgn._control, "LEFT", -8, 0)
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

        local function RefreshAllTextures()
            ns.RefreshAllSettings()
            for _, plate in pairs(ns.friendlyPlates or {}) do
                if ns.ApplyHealthBarTexture then ns.ApplyHealthBarTexture(plate) end
            end
        end

        local borderStyleRow
        borderStyleRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Border Style",
              values={ ellesmere = "EllesmereUI", simple = "Simple", none = "None" },
              getValue=function() return DBVal("borderStyle") or defaults.borderStyle end,
              setValue=function(v)
                DB().borderStyle = v
                ns.RefreshBorderStyle()
                UpdatePreview()
                if _G._EUI_ColorPreviews then
                    for _, prev in ipairs(_G._EUI_ColorPreviews) do
                        if prev.RefreshBorderStyle then prev:RefreshBorderStyle() end
                    end
                end
                EllesmereUI:RefreshPage()
              end,
              order={ "ellesmere", "simple", "none" } },
            { type="dropdown", text="Bar Texture", values=hbtValues, order=hbtOrder,
              getValue=function() return DBVal("healthBarTexture") or "none" end,
              setValue=function(v)
                DB().healthBarTexture = v
                RefreshAllTextures()
                UpdatePreview()
              end });  y = y - h

        -- Inline color swatch next to the Border Style dropdown
        do
            local leftRgn = borderStyleRow._leftRegion
            local borderColorGet = function()
                local c = (DB() and DB().borderColor) or defaults.borderColor
                return c.r, c.g, c.b
            end
            local borderColorSet = function(r, g, b)
                DB().borderColor = { r = r, g = g, b = b }
                ns.RefreshBorderColor()
                UpdatePreview()
                if _G._EUI_ColorPreviews then
                    for _, prev in ipairs(_G._EUI_ColorPreviews) do
                        if prev.RefreshBorderColor then prev:RefreshBorderColor() end
                    end
                end
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, borderColorGet, borderColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            -- Disabled state when border style is "none"
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isBorderNone()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            local off = isBorderNone()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
        end

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
                if rgn:IsObjectType("FontString") and rgn:GetText() == "CORE POSITIONS" then
                    local sub = coreHeader:CreateFontString(nil, "OVERLAY")
                    sub:SetFont(rgn:GetFont())
                    sub:SetTextColor(1, 1, 1, 0.25)
                    sub:SetText("(one per slot)")
                    sub:SetPoint("LEFT", rgn, "RIGHT", 6, 0)
                    break
                end
            end
        end

        local coreElementValues = {
            debuffs        = "Debuffs",
            buffs          = "Buffs",
            ccs            = "CCs",
            raidmarker     = "Raid Marker",
            classification = "Elite/Rare Indicator",
            none           = "None",
        }
        local coreElementOrder = { "debuffs", "buffs", "ccs", "raidmarker", "classification", "none" }

        local coreRow1, coreRow2, coreRow3
        local _refreshRaidMarkerEyePos
        local _refreshClassificationEyePos

        RefreshCoreEyes = function()
            if _refreshRaidMarkerEyePos then _refreshRaidMarkerEyePos() end
            if _refreshClassificationEyePos then _refreshClassificationEyePos() end
        end

        -- Map element name to XY offset key prefix (legacy, kept for reference)
        -- Now using slot-based offsets: pos .. "SlotXOffset" / "SlotYOffset"

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

                local bg = SolidTex(pf, "BACKGROUND", 0.06, 0.08, 0.10, 0.95)
                bg:SetAllPoints()
                MakeBorder(pf, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15)

                local titleFS = MakeFont(pf, 11, "", 1, 1, 1)
                titleFS:SetAlpha(0.7)
                titleFS:SetPoint("TOP", pf, "TOP", 0, -TOP_PAD)
                pf._titleFS = titleFS

                -- Measure label widths to compute layout BEFORE creating sliders
                local tmpFS = pf:CreateFontString(nil, "OVERLAY")
                tmpFS:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 12, GetNPOptOutline())
                local labelTexts = {"X", "Y", "Size"}
                local maxLblW = 0
                for _, txt in ipairs(labelTexts) do
                    tmpFS:SetText(txt)
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
                xLabel:SetAlpha(0.6); xLabel:SetText("X")
                xLabel:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, X_ROW_Y)
                local xTrack, xValBox = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, SLIDER_H, 11, SL_INPUT_A,
                    -28, 28, 1,
                    function() return pf._xGet and pf._xGet() or 0 end,
                    function(v) if pf._xSet then pf._xSet(v) end end, true)
                xTrack:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, X_ROW_Y - 2)
                xValBox:ClearAllPoints(); xValBox:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, X_ROW_Y)

                pf._xTrack = xTrack; pf._xValBox = xValBox

                -- Y slider row
                local Y_ROW_Y = X_ROW_Y - SLIDER_H - GAP
                local yLabel = MakeFont(pf, 12, nil, 1, 1, 1)
                yLabel:SetAlpha(0.6); yLabel:SetText("Y")
                yLabel:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, Y_ROW_Y)
                local yTrack, yValBox = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, SLIDER_H, 11, SL_INPUT_A,
                    -28, 28, 1,
                    function() return pf._yGet and pf._yGet() or 0 end,
                    function(v) if pf._ySet then pf._ySet(v) end end, true)
                yTrack:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, Y_ROW_Y - 2)
                yValBox:ClearAllPoints(); yValBox:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, Y_ROW_Y)

                pf._yTrack = yTrack; pf._yValBox = yValBox

                -- Size slider row (hidden when not needed)
                local S_ROW_Y = Y_ROW_Y - SLIDER_H - GAP
                local sLabel = MakeFont(pf, 12, nil, 1, 1, 1)
                sLabel:SetAlpha(0.6); sLabel:SetText("Size")
                sLabel:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, S_ROW_Y)
                pf._sLabel = sLabel

                -- Store layout values for dynamic size slider rebuild
                pf._SLIDER_LEFT = SLIDER_LEFT
                pf._SLIDER_W = SLIDER_W
                pf._S_ROW_Y = S_ROW_Y

                -- Growth direction row (shown only for topleft/topright slots)
                local GROWTH_ROW_H = 22
                local G_ROW_Y = S_ROW_Y - SLIDER_H - GAP
                pf._G_ROW_Y = G_ROW_Y
                pf._GROWTH_ROW_H = GROWTH_ROW_H

                local gLabel = MakeFont(pf, 12, nil, 1, 1, 1)
                gLabel:SetAlpha(0.6); gLabel:SetText("Grow")
                gLabel:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, G_ROW_Y)
                pf._gLabel = gLabel

                -- Three small radio buttons: values filled in at show time
                local gBtns = {}
                local BTN_W, BTN_H, BTN_GAP = 52, 20, 4
                for bi = 1, 3 do
                    local b = CreateFrame("Button", nil, pf)
                    b:SetSize(BTN_W, BTN_H)
                    b:SetPoint("TOPLEFT", pf, "TOPLEFT",
                        SLIDER_LEFT + (bi - 1) * (BTN_W + BTN_GAP),
                        G_ROW_Y - 1)
                    local bg = b:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints()
                    bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
                    b._bg = bg
                    local hl = b:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetAllPoints()
                    hl:SetColorTexture(1, 1, 1, 0.06)
                    local lbl = b:CreateFontString(nil, "OVERLAY")
                    lbl:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, GetNPOptOutline())
                    lbl:SetAllPoints()
                    lbl:SetJustifyH("CENTER")
                    lbl:SetJustifyV("MIDDLE")
                    b._lbl = lbl
                    b:SetScript("OnClick", function(self)
                        if pf._growthSet then pf._growthSet(self._value) end
                        -- Refresh button states
                        local cur = pf._growthGet and pf._growthGet() or ""
                        for _, gb in ipairs(gBtns) do
                            local active = (gb._value == cur)
                            gb._bg:SetColorTexture(
                                active and 0.973 or 0.15,
                                active and 0.839 or 0.15,
                                active and 0.604 or 0.15,
                                active and 0.25  or 0.8)
                            gb._lbl:SetTextColor(active and 1 or 0.7, active and 1 or 0.7, active and 1 or 0.7)
                        end
                    end)
                    gBtns[bi] = b
                end
                pf._gBtns = gBtns

                -- Layout constants stored for height calc
                pf._TOP_PAD = TOP_PAD; pf._TITLE_H = TITLE_H; pf._TITLE_GAP = TITLE_GAP
                pf._GAP = GAP; pf._SLIDER_H = SLIDER_H; pf._SIDE_PAD = SIDE_PAD
                pf._POPUP_W = POPUP_W

                -- Close on click outside
                local wasDown = false
                pf._clickOutside = function(self, dt)
                    local down = IsMouseButtonDown("LeftButton")
                    if down and not wasDown then
                        if not self:IsMouseOver() and not (cogPopupOwner and cogPopupOwner:IsMouseOver()) then
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
            cogPopup._titleFS:SetText(opts.title)
            cogPopupOwner = anchorBtn

            -- Show/hide size row and adjust height
            local hasSize = opts.sizeGet ~= nil
            local hasGrowth = opts.growthGet ~= nil
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
                cogPopup._sLabel:SetText(opts.sizeLabel or "Size")
                cogPopup._sLabel:Show()
                if cogPopup._sTrack then cogPopup._sTrack:Show() end
                if cogPopup._sValBox then cogPopup._sValBox:Show() end
            else
                cogPopup._sLabel:Hide()
                if cogPopup._sTrack then cogPopup._sTrack:Hide() end
                if cogPopup._sValBox then cogPopup._sValBox:Hide() end
            end

            -- Show/hide growth row
            if hasGrowth then
                cogPopup._growthGet = opts.growthGet
                cogPopup._growthSet = opts.growthSet
                local vals = opts.growthValues  -- { { value, label }, ... }
                local cur = opts.growthGet()
                for bi, btn in ipairs(cogPopup._gBtns) do
                    local entry = vals and vals[bi]
                    if entry then
                        btn._value = entry.value
                        btn._lbl:SetText(entry.label)
                        local active = (entry.value == cur)
                        btn._bg:SetColorTexture(
                            active and 0.973 or 0.15,
                            active and 0.839 or 0.15,
                            active and 0.604 or 0.15,
                            active and 0.25  or 0.8)
                        btn._lbl:SetTextColor(active and 1 or 0.7, active and 1 or 0.7, active and 1 or 0.7)
                        btn:Show()
                    else
                        btn:Hide()
                    end
                end
                cogPopup._gLabel:Show()
            else
                cogPopup._growthGet = nil
                cogPopup._growthSet = nil
                cogPopup._gLabel:Hide()
                for _, btn in ipairs(cogPopup._gBtns) do btn:Hide() end
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
                if hasSize   then h = h + gap + rowH end
                if hasGrowth then h = h + gap + p._GROWTH_ROW_H end
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
            tex:SetTexture(COGS_ICON)
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
                    title = slotLabel .. " Slot Settings",
                    xGet = function() return CorePosXGet(posKey) end,
                    xSet = function(v) CorePosXSet(posKey, v) end,
                    yGet = function() return CorePosYGet(posKey) end,
                    ySet = function(v) CorePosYSet(posKey, v) end,
                    sizeGet = function() return DBVal(sizeKey) or defaults[sizeKey] end,
                    sizeSet = function(v) DB()[sizeKey] = v; RefreshAllSlots(); UpdatePreview() end,
                    sizeMin = 10, sizeMax = 50,
                }
                if growthValues then
                    opts.growthGet    = function() return DBVal(growthKey) or defaults[growthKey] end
                    opts.growthSet    = function(v) DB()[growthKey] = v; RefreshAllSlots(); UpdatePreview() end
                    opts.growthValues = growthValues
                end
                ShowCogPopup(self, opts)
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = CorePosOffDisabled(posKey)
                btn:SetAlpha(off and 0.15 or (cogPopupOwner == btn and 0.7 or 0.4))
            end)
            if CorePosOffDisabled(posKey) then btn:SetAlpha(0.15) end
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
              disabledTooltip = "This option requires an aura or indicator to be assigned",
              labelOnlyDisabled = true },
            { type="dropdown", text="Right",
              values = coreElementValues, order = coreElementOrder,
              getValue = function() return GetElementAtPosition("right") end,
              setValue = function(v) SetElementAtPosition("right", v); RefreshAllSlots(); RefreshCoreEyes() end,
              disabled = function() return CorePosOffDisabled("right") end,
              disabledTooltip = "This option requires an aura or indicator to be assigned",
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
              disabledTooltip = "This option requires an aura or indicator to be assigned",
              labelOnlyDisabled = true },
            { type="dropdown", text="Top Right",
              values = coreElementValues, order = coreElementOrder,
              getValue = function() return GetElementAtPosition("topright") end,
              setValue = function(v) SetElementAtPosition("topright", v); RefreshAllSlots(); RefreshCoreEyes() end,
              disabled = function() return CorePosOffDisabled("topright") end,
              disabledTooltip = "This option requires an aura or indicator to be assigned",
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
              disabledTooltip = "This option requires an aura or indicator to be assigned",
              labelOnlyDisabled = true },
            { type="dropdown", text="Bottom",
              values = coreElementValues, order = coreElementOrder,
              getValue = function() return GetElementAtPosition("bottom") end,
              setValue = function(v) SetElementAtPosition("bottom", v); RefreshAllSlots(); RefreshCoreEyes() end,
              disabled = function() return CorePosOffDisabled("bottom") end,
              disabledTooltip = "This option requires an aura or indicator to be assigned",
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

        -- Eye icon that follows whichever Core Positions dropdown has "Elite/Rare Indicator"
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
                if rgn:IsObjectType("FontString") and rgn:GetText() == "CORE TEXT POSITIONS" then
                    local sub = coreTextHeader:CreateFontString(nil, "OVERLAY")
                    sub:SetFont(rgn:GetFont())
                    sub:SetTextColor(1, 1, 1, 0.25)
                    sub:SetText("(one per slot)")
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
            none                 = "None",
        }
        local textElementOrder = { "none", "---", "enemyName", "healthPercent", "healthPercentNoSign", "healthNumber", "healthPctNum", "healthNumPct" }

        local function TextSlotSetValue(slotKey, v)
            SetTextElementAtSlot(slotKey, v)
            for _, plate in pairs(plates) do
                plate:RefreshNamePosition()
                plate:UpdateHealthValues()
            end
            UpdatePreview(); EllesmereUI:RefreshPage()
        end

        local function TextOffsetRefresh()
            for _, plate in pairs(plates) do
                plate:RefreshNamePosition()
                plate:UpdateHealthValues()
            end
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
            tex:SetTexture(COGS_ICON)
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
                ShowCogPopup(self, {
                    title = slotLabel .. " Settings",
                    xGet = function() return TextPosXGet(slotKey) end,
                    xSet = function(v) TextPosXSet(slotKey, v) end,
                    yGet = function() return TextPosYGet(slotKey) end,
                    ySet = function(v) TextPosYSet(slotKey, v) end,
                    sizeGet = function() return DBVal(sizeKey) or defaults[sizeKey] end,
                    sizeSet = function(v) DB()[sizeKey] = v; TextOffsetRefresh() end,
                    sizeMin = 6, sizeMax = 20,
                    sizeLabel = "Size",
                })
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
                for _, plate in pairs(plates) do
                    plate:RefreshNamePosition()
                    plate:UpdateHealthValues()
                end
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
              disabledTooltip="This option requires a text to be assigned",
              labelOnlyDisabled=true },
            { type="dropdown", text="Right Text", values=textElementValues,
              getValue=function() return DBVal("textSlotRight") end,
              setValue=function(v) TextSlotSetValue("textSlotRight", v) end,
              order=textElementOrder,
              disabled=function() return DBVal("textSlotRight") == "none" end,
              disabledTooltip="This option requires a text to be assigned",
              labelOnlyDisabled=true,
              disabledValues=function(k) if (k == "healthPctNum" or k == "healthNumPct") and DBVal("textSlotCenter") == "enemyName" then return "Disabled when Enemy Name is centered on the health bar due to overlapping text" end end });  y = y - h
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
              disabledTooltip="This option requires a text to be assigned",
              labelOnlyDisabled=true,
              disabledValues=function(k) if (k == "healthPctNum" or k == "healthNumPct") and DBVal("textSlotCenter") == "enemyName" then return "Disabled when Enemy Name is centered on the health bar due to overlapping text" end end },
            { type="dropdown", text="Center Text", values=textElementValues,
              getValue=function() return DBVal("textSlotCenter") end,
              setValue=function(v) TextSlotSetValue("textSlotCenter", v) end,
              order=textElementOrder,
              disabled=function() return DBVal("textSlotCenter") == "none" end,
              disabledTooltip="This option requires a text to be assigned",
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
        healthBarHeader, h = W:SectionHeader(parent, "BARS", y);  y = y - h

        local healthBarHeightRow
        healthBarHeightRow, h = W:DualRow(parent, y,
            { type="slider", text="Health Bar Width", min=BAR_W, max=BAR_W+100, step=1,
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
                UpdatePreview()
              end },
            { type="slider", text="Health Bar Height", min=6, max=30, step=1,
              getValue=function() return DBVal("healthBarHeight") end,
              setValue=function(v)
                DB().healthBarHeight = v
                for _, plate in pairs(plates) do PP.Height(plate.health, v) end
                UpdatePreview()
              end });  y = y - h

        local function castIconOff() return DB() and DB().showCastIcon == false end

        local castBarHeightRow
        castBarHeightRow, h = W:DualRow(parent, y,
            { type="slider", text="Cast Bar Height", min=10, max=30, step=1,
              getValue=function() return DBVal("castBarHeight") or defaults.castBarHeight end,
              setValue=function(v)
                DB().castBarHeight = v
                local barW = ns.GetHealthBarWidth()
                for _, plate in pairs(plates) do
                    PP.Size(plate.cast, barW, v)
                    plate.cast:ClearAllPoints()
                    PP.Point(plate.cast, "TOPLEFT", plate.health, "BOTTOMLEFT", 0, 0)
                    PP.Size(plate.castIconFrame, v, v)
                    plate.castIconFrame:ClearAllPoints()
                    PP.Point(plate.castIconFrame, "TOPRIGHT", plate.cast, "TOPLEFT", 0, 0)
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
                        for _, plate in pairs(plates) do
                            plate.castIconFrame:SetScale(v)
                        end
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

        _, h = W:Spacer(parent, y, 20);  y = y - h

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
              setValue=function(v)
                DB().showClassPower = v
                ns.ApplyClassPowerSetting(); UpdatePreview()
                EllesmereUI:RefreshPage()
              end },
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
                { tooltip = "Class Colored",
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

        -- Row 2: Position (with inline cog for X/Y) | Size
        local classResourceRow2
        classResourceRow2, h = W:DualRow(parent, y,
            { type="dropdown", text="Position",
              disabled=classPowerDisabled,
              disabledTooltip="Show Class Resource",
              values={ top = "Top", bottom = "Bottom" },
              getValue=function() return DBVal("classPowerPos") or defaults.classPowerPos end,
              setValue=function(v)
                DB().classPowerPos = v
                ns.RefreshClassPower(); UpdatePreview()
              end, order={ "top", "bottom" } },
            { type="slider", text="Size", min=0.5, max=3.0, step=0.1,
              disabled=classPowerDisabled,
              disabledTooltip="Show Class Resource",
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
            { type="slider", text="Bar Spacing", min=0, max=10, step=1,
              disabled=classPowerDisabled,
              disabledTooltip="Show Class Resource",
              getValue=function() return DBVal("classPowerGap") or defaults.classPowerGap end,
              setValue=function(v)
                DB().classPowerGap = v
                ns.RefreshClassPower(); UpdatePreview()
              end },
            { type="colorpicker", text="Background Color", hasAlpha=true,
              disabled=classPowerDisabled,
              disabledTooltip="Show Class Resource",
              getValue=function()
                local c = (DB() and DB().classPowerBgColor) or defaults.classPowerBgColor
                return c.r, c.g, c.b, c.a
              end,
              setValue=function(r, g, b, a)
                DB().classPowerBgColor = { r=r, g=g, b=b, a=a }
                ns.RefreshClassPower(); UpdatePreview()
              end });  y = y - h

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

        -- Row 1: Aura Duration | Aura Stacks
        local auraDurPosRow
        local auraTimerStackRow
        do
            local dualRow
            dualRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Aura Duration", values=timerPosValues,
                  getValue=function() return DBVal("debuffTimerPosition") or atFallback end,
                  setValue=function(v)
                    DB().debuffTimerPosition = v
                    DB().buffTimerPosition = v
                    DB().ccTimerPosition = v
                    DB().auraTextPosition = v
                    LiveApplyTimerPos(function(p, i) return p.debuffs[i] end, 4, v)
                    LiveApplyTimerPos(function(p, i) return p.buffs[i] end, 4, v)
                    LiveApplyTimerPos(function(p, i) return p.cc[i] end, 2, v)
                    UpdatePreview()
                  end, order=timerPosOrder },
                { type="colorpicker", text="Aura Stacks",
                  getValue=function()
                    local c = (DB() and DB().auraStackTextColor) or defaults.auraStackTextColor
                    return c.r, c.g, c.b
                  end,
                  setValue=function(r, g, b)
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
                    UpdatePreview()
                  end })
            auraDurPosRow = dualRow
            auraTimerStackRow = dualRow

            -- LEFT: Aura Duration inline swatch + cog
            local leftRgn = dualRow._leftRegion
            local adColorGet = function()
                local c = (DB() and DB().auraDurationTextColor) or defaults.auraDurationTextColor
                return c.r, c.g, c.b
            end
            local adColorSet = function(r, g, b)
                DB().auraDurationTextColor = { r = r, g = g, b = b }
                DB().debuffTimerColor = { r = r, g = g, b = b }
                DB().debuffTextWhite = nil
                for _, plate in pairs(plates) do
                    for i = 1, 4 do
                        if plate.debuffs[i] and plate.debuffs[i].cd and plate.debuffs[i].cd.text then
                            plate.debuffs[i].cd.text:SetTextColor(r, g, b, 1)
                        end
                        if plate.buffs[i] and plate.buffs[i].cd and plate.buffs[i].cd.text then
                            plate.buffs[i].cd.text:SetTextColor(r, g, b, 1)
                        end
                    end
                    for i = 1, 2 do
                        if plate.cc[i] and plate.cc[i].cd and plate.cc[i].cd.text then
                            plate.cc[i].cd.text:SetTextColor(r, g, b, 1)
                        end
                    end
                end
                UpdatePreview()
            end
            local adSwatch, adUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, adColorGet, adColorSet, nil, 20)
            PP.Point(adSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = adSwatch
            EllesmereUI.RegisterWidgetRefresh(function() adUpdateSwatch() end)

            local _, auraDurCogShow = EllesmereUI.BuildCogPopup({
                title = "Aura Duration Settings",
                rows = {
                    { type="slider", label="Size", min=6, max=20, step=1,
                      get=function() return DBVal("auraDurationTextSize") or defaults.auraDurationTextSize end,
                      set=function(v)
                        DB().auraDurationTextSize = v
                        for _, plate in pairs(plates) do
                            for i = 1, 4 do
                                if plate.debuffs[i] and plate.debuffs[i].cd and plate.debuffs[i].cd.text then
                                    SetFSFont(plate.debuffs[i].cd.text, v, "OUTLINE")
                                end
                                if plate.buffs[i] and plate.buffs[i].cd and plate.buffs[i].cd.text then
                                    SetFSFont(plate.buffs[i].cd.text, v, "OUTLINE")
                                end
                            end
                            for i = 1, 2 do
                                if plate.cc[i] and plate.cc[i].cd and plate.cc[i].cd.text then
                                    SetFSFont(plate.cc[i].cd.text, v, "OUTLINE")
                                end
                            end
                        end
                        UpdatePreview()
                      end },
                },
            })
            local auraDurCogBtn = CreateFrame("Button", nil, leftRgn)
            auraDurCogBtn:SetSize(26, 26)
            auraDurCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = auraDurCogBtn
            auraDurCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            auraDurCogBtn:SetAlpha(0.4)
            local auraDurCogTex = auraDurCogBtn:CreateTexture(nil, "OVERLAY")
            auraDurCogTex:SetAllPoints()
            auraDurCogTex:SetTexture(EllesmereUI.RESIZE_ICON)   auraDurCogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            auraDurCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            auraDurCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            auraDurCogBtn:SetScript("OnClick", function(self) auraDurCogShow(self) end)

            -- RIGHT: Aura Stacks cog for size
            local rightRgn = dualRow._rightRegion
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
                                    SetFSFont(plate.debuffs[i].count, v, "OUTLINE")
                                end
                                if plate.buffs[i] and plate.buffs[i].count then
                                    SetFSFont(plate.buffs[i].count, v, "OUTLINE")
                                end
                            end
                        end
                        UpdatePreview()
                      end },
                },
            })
            local auraStackCogBtn = CreateFrame("Button", nil, rightRgn)
            auraStackCogBtn:SetSize(26, 26)
            auraStackCogBtn:SetPoint("RIGHT", rightRgn._control, "LEFT", -8, 0)
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
        y = y - h

        -- Row 2: Spell Name | Spell Target
        local spellNameRow
        spellNameRow, h = W:DualRow(parent, y,
            { type="colorpicker", text="Spell Name",
              getValue=function() return DBColor("castNameColor") end,
              setValue=function(r, g, b)
                DB().castNameColor = { r = r, g = g, b = b }
                for _, plate in pairs(plates) do
                    if plate.castName then plate.castName:SetTextColor(r, g, b, 1) end
                end
                UpdatePreview()
              end },
            { type="multiSwatch", text="Spell Target",
              swatches = {
                { tooltip = "Custom Color",
                  getValue=function() return DBColor("castTargetColor") end,
                  setValue=function(r, g, b)
                    DB().castTargetColor = { r = r, g = g, b = b }
                    for _, plate in pairs(plates) do
                        plate:UpdateHealth()
                    end
                    UpdatePreview()
                  end,
                  onClick = function(self)
                    local db = DB()
                    if db.castTargetClassColor ~= nil and db.castTargetClassColor or defaults.castTargetClassColor then
                        DB().castTargetClassColor = false
                        for _, plate in pairs(plates) do plate:UpdateHealth() end
                        UpdatePreview()
                        EllesmereUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                    local db = DB()
                    local cc = db and db.castTargetClassColor
                    if cc == nil then cc = defaults.castTargetClassColor end
                    return cc and 0.3 or 1
                  end },
                { tooltip = "Class Colored",
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
                    DB().castTargetClassColor = true
                    for _, plate in pairs(plates) do plate:UpdateHealth() end
                    UpdatePreview()
                    EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                    local db = DB()
                    local cc = db and db.castTargetClassColor
                    if cc == nil then cc = defaults.castTargetClassColor end
                    return cc and 1 or 0.3
                  end },
              } })
        do
            -- LEFT: Spell Name cog for size
            local leftRgn = spellNameRow._leftRegion
            local _, spellNameCogShow = EllesmereUI.BuildCogPopup({
                title = "Spell Name Settings",
                rows = {
                    { type="slider", label="Size", min=6, max=16, step=1,
                      get=function() return DBVal("castNameSize") or defaults.castNameSize end,
                      set=function(v)
                        DB().castNameSize = v
                        for _, plate in pairs(plates) do
                            if plate.castName then SetFSFont(plate.castName, v, GetNPOutline()) end
                        end
                        UpdatePreview()
                      end },
                },
            })
            local spellNameCogBtn = CreateFrame("Button", nil, leftRgn)
            spellNameCogBtn:SetSize(26, 26)
            spellNameCogBtn:SetPoint("RIGHT", leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = spellNameCogBtn
            spellNameCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            spellNameCogBtn:SetAlpha(0.4)
            local spellNameCogTex = spellNameCogBtn:CreateTexture(nil, "OVERLAY")
            spellNameCogTex:SetAllPoints()
            spellNameCogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            spellNameCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            spellNameCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            spellNameCogBtn:SetScript("OnClick", function(self) spellNameCogShow(self) end)

            -- RIGHT: Spell Target cog for size
            local rightRgn = spellNameRow._rightRegion
            local _, spellTargetCogShow = EllesmereUI.BuildCogPopup({
                title = "Spell Target Settings",
                rows = {
                    { type="slider", label="Size", min=6, max=16, step=1,
                      get=function() return DBVal("castTargetSize") or defaults.castTargetSize end,
                      set=function(v)
                        DB().castTargetSize = v
                        for _, plate in pairs(plates) do
                            if plate.castTarget then SetFSFont(plate.castTarget, v, GetNPOutline()) end
                        end
                        UpdatePreview()
                      end },
                },
            })
            local spellTargetCogBtn = CreateFrame("Button", nil, rightRgn)
            spellTargetCogBtn:SetSize(26, 26)
            spellTargetCogBtn:SetPoint("RIGHT", rightRgn._control, "LEFT", -8, 0)
            rightRgn._lastInline = spellTargetCogBtn
            spellTargetCogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            spellTargetCogBtn:SetAlpha(0.4)
            local spellTargetCogTex = spellTargetCogBtn:CreateTexture(nil, "OVERLAY")
            spellTargetCogTex:SetAllPoints()
            spellTargetCogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            spellTargetCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            spellTargetCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            spellTargetCogBtn:SetScript("OnClick", function(self) spellTargetCogShow(self) end)
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
            auraDuration = { section = generalTextHeader,  target = auraDurPosRow,       slotSide = "left" },
            auraStack    = { section = generalTextHeader,  target = auraTimerStackRow,   slotSide = "right" },
            castBar      = { section = healthBarHeader,  target = castBarHeightRow,    slotSide = "left" },
            castIcon     = { section = healthBarHeader,  target = showCastIconRow,     slotSide = "right" },
            castName     = { section = generalTextHeader, target = spellNameRow,        slotSide = "left" },
            castTarget   = { section = generalTextHeader, target = spellNameRow,        slotSide = "right" },
            healthBar    = { section = healthBarHeader,  target = healthBarHeightRow },
            classResource = { section = classResourceHeader, target = classResourceSection },
            targetArrows = { section = styleHeader,          target = targetGlowRow,       slotSide = "right" },
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
                local slot = FindTextSlotForElement("healthPercent") or FindTextSlotForElement("healthPercentNoSign") or FindTextSlotForElement("healthNumber") or FindTextSlotForElement("healthPctNum") or FindTextSlotForElement("healthNumPct")
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
                            local ov = CreateHitOverlay(pv._ccs[i].durationText, "auraDuration", true, textOnIconLevel)
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
                            local ov = CreateHitOverlay(pv._buffs[i].durationText, "auraDuration", true, textOnIconLevel)
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
                            local ov = CreateHitOverlay(pv._debuffs[i].durationText, "auraDuration", true, textOnIconLevel)
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
            end
            -- Cast spell name and target text (above the cast bar overlay)
            local castTextLevel = (castOverlayLevel or 30) + 5
            if pv._castNameFS then
                local ov = CreateHitOverlay(pv._castNameFS, "castName", true, castTextLevel)
                textOverlays[#textOverlays + 1] = ov
            end
            if pv._castTargetFS then
                local ov = CreateHitOverlay(pv._castTargetFS, "castTarget", true, castTextLevel)
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
            end
            pv._arrowOverlay = arrowOverlay
            -- Store text overlays for size refresh on preview update
            pv._textOverlays = textOverlays
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
                    elseif element == "healthPctNum" then
                        local valStr = tostring(healthVal):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                        pctFS:SetTextColor(sc.r, sc.g, sc.b, 1)
                        pctFS:SetText(healthPct .. "% | " .. valStr)
                        pctFS:SetPoint(slot.anchor, health, slot.anchor, slot.xOff, 0)
                        pctFS:Show()
                    elseif element == "healthNumPct" then
                        local valStr = tostring(healthVal):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                        pctFS:SetTextColor(sc.r, sc.g, sc.b, 1)
                        pctFS:SetText(valStr .. " | " .. healthPct .. "%")
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
                clip:SetPoint("TOPLEFT", tlAnchor, tlRelPoint, 0, -1)
                clip:SetPoint("BOTTOMRIGHT", brAnchor, brRelPoint, 0, 1)
                clip:SetFrameLevel(health:GetFrameLevel() + 1)
                local tex = clip:CreateTexture(nil, "ARTWORK", nil, sublayer)
                tex:SetPoint("TOPLEFT", health, "TOPLEFT", 1, -1)
                tex:SetSize(BAR_W, BAR_H)
                return clip, tex
            end

            if colorKey == "focus" then
                local tex = DBVal("focusOverlayTexture") or defaults.focusOverlayTexture
                if tex ~= "none" then
                    local fillRef = health:GetStatusBarTexture()
                    local oAlpha = DBVal("focusOverlayAlpha") or defaults.focusOverlayAlpha
                    local oc = (DB() and DB().focusOverlayColor) or defaults.focusOverlayColor
                    overlayFillClip, overlayFillTex = MakeOverlayClip(fillRef, "TOPLEFT", fillRef, "BOTTOMRIGHT", 2)
                    overlayFillTex:SetTexture(MEDIA .. tex .. ".png")
                    overlayFillTex:SetAlpha(oAlpha)
                    overlayFillTex:SetVertexColor(oc.r, oc.g, oc.b)
                    overlayBgClip, overlayBgTex = MakeOverlayClip(fillRef, "TOPRIGHT", health, "BOTTOMRIGHT", 1)
                    overlayBgTex:SetTexture(MEDIA .. tex .. ".png")
                    overlayBgTex:SetAlpha(oAlpha * 0.3)
                    overlayBgTex:SetVertexColor(oc.r, oc.g, oc.b)
                end
            end

            -- Live update hook: re-color when swatch changes
            container.UpdateColor = function()
                local cc = (DB() and DB()[colorKey]) or defaults[colorKey]
                health:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
            end
            -- Live update hook: refresh overlay texture from DB
            container.UpdateOverlay = function()
                if colorKey ~= "focus" then return end
                local tex = DBVal("focusOverlayTexture") or defaults.focusOverlayTexture
                if tex == "none" then
                    if overlayFillClip then overlayFillClip:Hide() end
                    if overlayBgClip then overlayBgClip:Hide() end
                else
                    local fillRef = health:GetStatusBarTexture()
                    local oAlpha = DBVal("focusOverlayAlpha") or defaults.focusOverlayAlpha
                    local oc = (DB() and DB().focusOverlayColor) or defaults.focusOverlayColor
                    if not overlayFillClip then
                        overlayFillClip, overlayFillTex = MakeOverlayClip(fillRef, "TOPLEFT", fillRef, "BOTTOMRIGHT", 2)
                    end
                    overlayFillTex:SetTexture(MEDIA .. tex .. ".png")
                    overlayFillTex:SetAlpha(oAlpha)
                    overlayFillTex:SetVertexColor(oc.r, oc.g, oc.b)
                    overlayFillClip:Show()
                    if not overlayBgClip then
                        overlayBgClip, overlayBgTex = MakeOverlayClip(fillRef, "TOPRIGHT", health, "BOTTOMRIGHT", 1)
                    end
                    overlayBgTex:SetTexture(MEDIA .. tex .. ".png")
                    overlayBgTex:SetAlpha(oAlpha * 0.3)
                    overlayBgTex:SetVertexColor(oc.r, oc.g, oc.b)
                    overlayBgClip:Show()
                end
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

            local nameFS = cast:CreateFontString(nil, "OVERLAY")
            SetPVFont(nameFS, fontPath, cns, GetNPOptOutline())
            nameFS:SetPoint("LEFT", cast, "LEFT", 5, 0)
            nameFS:SetJustifyH("LEFT")
            nameFS:SetWordWrap(false)
            nameFS:SetMaxLines(1)
            nameFS:SetText(isHalf and "Spell Name" or "Spell Name")
            nameFS:SetTextColor(cnc.r, cnc.g, cnc.b, 1)

            local targetFS = cast:CreateFontString(nil, "OVERLAY")
            SetPVFont(targetFS, fontPath, cts, GetNPOptOutline())
            targetFS:SetPoint("RIGHT", cast, "RIGHT", -3, 0)
            targetFS:SetJustifyH("RIGHT")
            targetFS:SetWordWrap(false)
            targetFS:SetMaxLines(1)
            targetFS:SetText(isHalf and (UnitName("player") or "Target") or (UnitName("player") or "Spell Target"))
            local useClassColor = defaults.castTargetClassColor
            local dbRef = DB()
            if dbRef and dbRef.castTargetClassColor ~= nil then useClassColor = dbRef.castTargetClassColor end
            if useClassColor then
                local _, pClass = UnitClass("player")
                local c = pClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[pClass]
                if c then
                    targetFS:SetTextColor(c.r, c.g, c.b, 1)
                else
                    targetFS:SetTextColor(1, 1, 1, 1)
                end
            else
                local ctc = (dbRef and dbRef.castTargetColor) or defaults.castTargetColor
                targetFS:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
            end

            -- Dynamic name width: fill available space minus target text minus 5px gap
            local tgtW = targetFS:GetUnboundedStringWidth()
            local nameMaxW = BAR_W - 5 - 3 - tgtW - 5
            if nameMaxW < 20 then nameMaxW = 20 end
            nameFS:SetWidth(nameMaxW)

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

    local function BuildColorsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        -- No content header on Colors tab (presets are inline in scroll area)
        EllesmereUI:ClearContentHeader()

        -- Clear display preset hook (only active on Display page)
        onPresetSettingChanged = nil

        -- Enable per-row center divider for the dual-column layout (same as Display tab)
        parent._showRowDivider = true

        -- Track all mini previews for border style refresh
        _G._EUI_ColorPreviews = {}
        local function TrackPreview(prev)
            if prev then _G._EUI_ColorPreviews[#_G._EUI_ColorPreviews + 1] = prev end
            return prev
        end

        -- Collect all lazy preview proxies for refresh registration
        local _colorPagePreviews = {}

        -- Lazy wrapper: defers MakeColorPreviewBar until the parent row is first shown.
        -- Returns a proxy table with UpdateColor/UpdateOverlay/RefreshBorderStyle/RefreshBorderColor
        -- that forward to the real preview bar once built.
        -- anchorFrame: optional override for positioning (e.g. DualRow half-region)
        local function LazyColorPreviewBar(parentRow, colorType, colorKey, anchorFrame)
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
            -- Proxy methods: build on first call
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
            -- Build when parent row becomes visible (first scroll into view)
            parentRow:HookScript("OnShow", function()
                if not real then
                    EnsureBuilt()
                    _G._EUI_ColorPreviews[#_G._EUI_ColorPreviews + 1] = real
                end
                -- Re-apply disabled state every time the row becomes visible,
                -- in case SetDisabled was called before the bar was built.
                if real and real._health then
                    real._health:SetAlpha(_disabled and 0.3 or 1)
                end
            end)
            -- If the row is already visible (top of page), build immediately
            if parentRow:IsVisible() then
                EnsureBuilt()
            end
            _colorPagePreviews[#_colorPagePreviews + 1] = proxy
            return proxy
        end

        -- Shuffle cast icons and fills so each preview is unique
        -- ShuffleCastIcons()  -- disabled: no cast previews on Colors page
        -- ResetCastFills()    -- disabled: no cast previews on Colors page

        --[[ COLOR PRESET SYSTEM (disabled kept for future use)
        -- Color preset keys
        local colorPresetKeys = {
            "focusColorEnabled", "focus", "focusOverlayTexture", "focusOverlayAlpha", "focusOverlayColor", "caster", "miniboss", "enemyInCombat",
            "castBar", "interruptReady",
            "tankHasAggroEnabled", "tankHasAggro", "tankLosingAggro", "tankNoAggro",
            "dpsHasAggro", "dpsNearAggro",
        }

        local function RandomizeColorSettings(db)
            local function rColor() return { r = math.random(), g = math.random(), b = math.random() } end
            for _, key in ipairs(colorPresetKeys) do
                if key == "focusColorEnabled" or key == "tankHasAggroEnabled" then
                    db[key] = true  -- always enable during randomize so user can see the color
                elseif key ~= "focusOverlayTexture" and key ~= "focusOverlayAlpha" and key ~= "focusOverlayColor" then
                    db[key] = rColor()
                end
            end
        end

        -- Inline preset system at top of scroll area (no content header)
        local checkDrift, presetH = EllesmereUI:BuildPresetSystem({
            presetKeys  = colorPresetKeys,
            dbFunc      = DB,
            dbValFunc   = DBVal,
            defaults    = defaults,
            dbPrefix    = "_color",
            randomizeFn = RandomizeColorSettings,
            refreshFn   = function()
                RefreshAllPlates()
            end,
            inlineParent = parent,
            yOffset      = y,
        })
        onColorPresetSettingChanged = checkDrift
        _colorPresetCheckDrift = checkDrift
        y = y - presetH

        -- Hook RefreshAllPlates to auto-detect color drift (same pattern as Display's UpdatePreview hook)
        if not _refreshAllPlatesHooked then
            _refreshAllPlatesHooked = true
            local _origRefreshAllPlates = RefreshAllPlates
            RefreshAllPlates = function()
                _origRefreshAllPlates()
                if onColorPresetSettingChanged then onColorPresetSettingChanged() end
            end
        end
        --]]

        local focusPrev

        -----------------------------------------------------------------------
        --  ENEMY COLORS
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_ENEMY, y);  y = y - h

        local function isFocusColorDisabled()
            local db = DB()
            if db and db.focusColorEnabled ~= nil then return not db.focusColorEnabled end
            return not defaults.focusColorEnabled
        end

        local function isFocusTextureNone()
            return (DBVal("focusOverlayTexture") or defaults.focusOverlayTexture) == "none"
        end

        -- Enemy Types ---- Enable Focus Color
        local enemyFocusDualFrame
        enemyFocusDualFrame, h = W:DualRow(parent, y,
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
              } },
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

        -- Inline Focus Color swatch next to Enable Focus Color toggle
        do
            local rightRgn = enemyFocusDualFrame._rightRegion
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

        -- Focus Texture ---- Focus Preview
        local focusPreviewRow
        focusPreviewRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Focus Texture",
              values={ ["striped-v2"] = "Stripes", ["striped-wide-v2"] = "Wide Stripes", none = "None" },
              getValue=function() return DBVal("focusOverlayTexture") or defaults.focusOverlayTexture end,
              setValue=function(v)
                DB().focusOverlayTexture = v
                RefreshAllPlates()
                if focusPrev and focusPrev.UpdateOverlay then focusPrev.UpdateOverlay() end
                EllesmereUI:RefreshPage()
              end,
              order={ "striped-v2", "striped-wide-v2", "none" } },
            { type="label", text="Focus Preview" });  y = y - h

        -- Inline texture color swatch next to Focus Texture dropdown
        do
            local leftRgn = focusPreviewRow._leftRegion
            local focusTexColorGet = function()
                local c = (DB() and DB().focusOverlayColor) or defaults.focusOverlayColor
                return c.r, c.g, c.b
            end
            local focusTexColorSet = function(r, g, b)
                DB().focusOverlayColor = { r = r, g = g, b = b }
                RefreshAllPlates()
                if focusPrev and focusPrev.UpdateOverlay then focusPrev.UpdateOverlay() end
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, focusTexColorGet, focusTexColorSet, nil, 20)
            PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = swatch
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isFocusTextureNone()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            local off = isFocusTextureNone()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)

            -- Cog popup for Texture Opacity next to the color swatch
            local _, cogShowFn = EllesmereUI.BuildCogPopup({
                title = "Focus Texture Settings",
                rows = {
                    { type="slider", label="Opacity", min=0, max=1.0, step=0.05,
                      get=function() return DBVal("focusOverlayAlpha") or defaults.focusOverlayAlpha end,
                      set=function(v)
                        DB().focusOverlayAlpha = v
                        RefreshAllPlates()
                        if focusPrev and focusPrev.UpdateOverlay then focusPrev.UpdateOverlay() end
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, leftRgn)
            cogBtn:SetSize(26, 26)
            PP.Point(cogBtn, "RIGHT", swatch, "LEFT", -9, 0)
            cogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 6)
            local cogIcon = cogBtn:CreateTexture(nil, "OVERLAY")
            cogIcon:SetAllPoints()
            cogIcon:SetTexture(EllesmereUI.COGS_ICON)
            cogIcon:SetAlpha(0.4)
            cogBtn:SetScript("OnEnter", function() cogIcon:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function() cogIcon:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShowFn(self) end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isFocusTextureNone()
                cogBtn:SetAlpha(off and 0.15 or 1)
                cogBtn:EnableMouse(not off)
            end)
            cogBtn:SetAlpha(isFocusTextureNone() and 0.15 or 1)
            cogBtn:EnableMouse(not isFocusTextureNone())
        end

        -- Focus preview bar anchored so its right edge aligns with the
        -- Enable Focus Color toggle's right edge (SIDE_PAD = 20 from region edge).
        -- MakeColorPreviewBar positions the bar at -(20+24+27) = -71 to leave room
        -- for a swatch; we override that to -20 since there's no swatch here.
        focusPrev = LazyColorPreviewBar(focusPreviewRow, "health", "focus", focusPreviewRow._rightRegion)
        do
            local function RepositionFocusBar()
                local rgn = focusPreviewRow._rightRegion
                for _, child in ipairs({ focusPreviewRow:GetChildren() }) do
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
            -- Reposition on every show (handles scroll-in visibility)
            focusPreviewRow:HookScript("OnShow", RepositionFocusBar)
            -- Also reposition immediately if the row is already visible
            -- (the lazy builder may have already created the bar)
            C_Timer.After(0, RepositionFocusBar)
        end
        if isFocusColorDisabled() then
            focusPrev.SetColorOverride(function() return DBColor("enemyInCombat") end)
        end
        focusPrev.SetDisabled(isFocusColorDisabled())
        focusPrev.UpdateColor()

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  CAST BAR
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_CASTBAR, y);  y = y - h

        -- Cast Color ---- Show Tick at Kick Ready Spot
        _, h = W:DualRow(parent, y,
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
              } },
            { type="toggle", text="Show Tick at Kick Ready Spot",
              tooltip="Shows a small white tick mark on the cast bar at the point where the cast will be when your interrupt comes off cooldown.",
              getValue=function()
                local db = DB()
                if db and db.kickTickEnabled ~= nil then return db.kickTickEnabled end
                return true
              end,
              setValue=function(v)
                DB().kickTickEnabled = v
              end });  y = y - h

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

        -- Row 2: Show Special "Has Aggro" Color (left) ---- blank (right)
        local function isTankHasAggroDisabled()
            local db = DB()
            if db and db.tankHasAggroEnabled ~= nil then return not db.tankHasAggroEnabled end
            return not defaults.tankHasAggroEnabled
        end

        local tankDualFrame
        tankDualFrame, h = W:DualRow(parent, y,
            { type="toggle", text="Show Special \"Has Aggro\" Color",
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
            { type="label", text="" });  y = y - h

        -- Inline Tank Has Aggro color swatch next to toggle
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
        end

        -----------------------------------------------------------------------
        --  OTHER COLORS
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_OTHER, y);  y = y - h

        -- Row 1: Quest Mob Color (left only, right empty)
        local function questMobColorOff()
            return DBVal("questMobColorEnabled") ~= true
        end

        local questMobRow
        questMobRow, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Quest Mob Color",
              getValue=function() return DBVal("questMobColorEnabled") == true end,
              setValue=function(v)
                DB().questMobColorEnabled = v
                for _, plate in pairs(ns.plates) do
                    plate:UpdateHealthColor()
                end
                EllesmereUI:RefreshPage()
              end,
              tooltip="Colors enemy nameplates for quest mobs you still need to kill." },
            nil);  y = y - h

        -- Inline color swatch on the quest mob toggle
        do
            local leftRgn = questMobRow._leftRegion
            local qmColorGet = function()
                local c = DB().questMobColor or defaults.questMobColor
                return c.r, c.g, c.b
            end
            local qmColorSet = function(r, g, b)
                DB().questMobColor = { r = r, g = g, b = b }
                for _, plate in pairs(ns.plates) do
                    plate:UpdateHealthColor()
                end
            end
            local qmSwatch, qmUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, qmColorGet, qmColorSet, nil, 20)
            PP.Point(qmSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = qmSwatch
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = questMobColorOff()
                qmSwatch:SetAlpha(off and 0.15 or 1)
                qmSwatch:EnableMouse(not off)
                qmUpdateSwatch()
            end)
            qmSwatch:SetAlpha(questMobColorOff() and 0.15 or 1)
            qmSwatch:EnableMouse(not questMobColorOff())
            qmSwatch:SetScript("OnEnter", function(self)
                if questMobColorOff() then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Enable Quest Mob Color"))
                end
            end)
            qmSwatch:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
            end)
        end

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
        _colorPreviewRandomizeAll = nil
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
                -- Restore display preset drift hook (cleared when Colors page builds)
                onPresetSettingChanged = _displayPresetCheckDrift
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
                -- Color preset restore disabled (preset system commented out)
                -- onColorPresetSettingChanged = _colorPresetCheckDrift
                -- Randomize preview fills/icons when switching TO this tab
                if _colorPreviewRandomizeAll then _colorPreviewRandomizeAll() end
                -- Refresh all color preview bars (colors from DB)
                if _colorPreviewRefreshAll then _colorPreviewRefreshAll() end
            end
        end,
        onReset     = function()
            -- Invalidate page cache so pages are rebuilt with fresh defaults
            EllesmereUI:InvalidatePageCache()
            -- Preserve user-saved presets (display + color), Custom presets, AND spec assignments across reset
            if EllesmereUINameplatesDB then
                local pD = EllesmereUINameplatesDB._presets
                local oD = EllesmereUINameplatesDB._presetOrder
                local pC = EllesmereUINameplatesDB._color_presets
                local oC = EllesmereUINameplatesDB._color_presetOrder
                local cD = EllesmereUINameplatesDB._customPreset
                local cC = EllesmereUINameplatesDB._color_customPreset
                local sA = EllesmereUINameplatesDB._specAssignments
                local sCA = EllesmereUINameplatesDB._color_specAssignments
                local sDP = EllesmereUINameplatesDB._specDefaultPreset
                local old = EllesmereUINameplatesDB
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
            else
                EllesmereUINameplatesDB = nil
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
            if EllesmereUINameplatesDB then
                local pD = EllesmereUINameplatesDB._presets
                local oD = EllesmereUINameplatesDB._presetOrder
                local pC = EllesmereUINameplatesDB._color_presets
                local oC = EllesmereUINameplatesDB._color_presetOrder
                local cD = EllesmereUINameplatesDB._customPreset
                local cC = EllesmereUINameplatesDB._color_customPreset
                local sA = EllesmereUINameplatesDB._specAssignments
                local sCA = EllesmereUINameplatesDB._color_specAssignments
                local sDP = EllesmereUINameplatesDB._specDefaultPreset
                for k in pairs(EllesmereUINameplatesDB) do EllesmereUINameplatesDB[k] = nil end
                if pD and next(pD) then EllesmereUINameplatesDB._presets = pD; EllesmereUINameplatesDB._presetOrder = oD end
                if pC and next(pC) then EllesmereUINameplatesDB._color_presets = pC; EllesmereUINameplatesDB._color_presetOrder = oC end
                if cD then EllesmereUINameplatesDB._customPreset = cD end
                if cC then EllesmereUINameplatesDB._color_customPreset = cC end
                if sA and next(sA) then EllesmereUINameplatesDB._specAssignments = sA end
                if sCA and next(sCA) then EllesmereUINameplatesDB._color_specAssignments = sCA end
                if sDP then EllesmereUINameplatesDB._specDefaultPreset = sDP end
                EllesmereUINameplatesDB._activePreset = "ellesmereui"
                EllesmereUINameplatesDB._color_activePreset = "ellesmereui"
            else
                EllesmereUINameplatesDB = nil
            end
            ReloadUI()
            return
        end

        EllesmereUI:ShowModule("EllesmereUINameplates")
    end
end)
