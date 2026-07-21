-------------------------------------------------------------------------------
--  EUI_UnitFrames_Options.lua
--  Registers the Unit Frames module with EllesmereUI
--  4 tabs: Main Frames, Boss Frames, Mini Frames, Blizzard Aura Frames
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_DISPLAY   = "Main Frames"
local PAGE_BOSS      = "Boss Frames"
local PAGE_MINI      = "Mini Frames"
local PAGE_AURAS     = "Blizzard Aura Frames"
local PAGE_UNLOCK    = "Unlock Mode"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Store the init function on the namespace; the main addon calls it
    -- from SetupOptionsPanel() once ns.db and ns.frames are ready.
    -- If SetupOptionsPanel already ran (race), fire immediately.
    ns._InitEUIModule = function()
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    if not ns.db then return end

    local PP = EllesmereUI.PanelPP
    local db = ns.db
    local frames = ns.frames
    local ReloadFrames = ns.ReloadFrames
    local ResolveFontPath = ns.ResolveFontPath
    -- fontPaths removed all modules use EllesmereUI.GetFontPath() now

    local floor = math.floor
    local abs = math.abs

    local function GetUFOptOutline()
        -- Already slug-gated at the source (GetFontOutlineFlag).
        return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or ""
    end
    local function GetUFOptUseShadow()
        return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow()
    end
    local function SetPVFont(fs, font, size)
        if not (fs and fs.SetFont) then return end
        local f = GetUFOptOutline()
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, f == "") end
        fs:SetFont(font, size, f)
    end

    ---------------------------------------------------------------------------
    --  Shared helpers
    ---------------------------------------------------------------------------
    local activePreview
    local allPreviews = {}

    local showCombatIndicatorPreview = false
    local showHealAbsorbPreview      = false  -- eyeball toggle for the Heal Absorb Style preview
    local showDispelOverlayPreview   = false  -- eyeball toggle for the player dispel overlay preview
    -- Preview hover-highlight hint text (shared across Single/Multi tabs)
    local _ufPreviewHintFS_display     -- hint FontString for the Main Frames page
    local _displayHeaderBaseH = 0      -- display header height WITHOUT hint

    local function IsPreviewHintDismissed()
        return EllesmereUIDB and EllesmereUIDB.previewHintDismissed
    end

    local function UpdatePreview()
        for _, pv in pairs(allPreviews) do
            if pv and pv.Update then pv:Update() end
        end
        -- Keep the in-game boss preview's fake debuffs in sync with live
        -- edits (Debuffs Location, Simple Debuff Display, debuff size, etc).
        if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
    end

    local function ReloadAndUpdate()
        -- Resolve at call time: ns.ReloadFrames gets wrapped after this file's
        -- setup runs (aura containers, dispel overlay); a load-time capture
        -- would bypass those hooks and settings would stop live-updating.
        local rf = ns.ReloadFrames or ReloadFrames
        if rf then rf() end
        UpdatePreview()
    end

    EllesmereUI:RegisterOnShow(UpdatePreview)
    ns.UpdatePreview = UpdatePreview

    -- Re-run preview Update() when panel scale changes so border pixel sizes refresh
    if not EllesmereUI._onScaleChanged then EllesmereUI._onScaleChanged = {} end
    EllesmereUI._onScaleChanged[#EllesmereUI._onScaleChanged + 1] = UpdatePreview

    -- Hide UIParent-parented disabled overlays when the options window closes
    EllesmereUI:RegisterOnHide(function()
        for _, pv in pairs(allPreviews) do
            if pv and pv._disabledOverlay then pv._disabledOverlay:Hide() end
        end
        -- Auto-disable the in-game boss preview so live boss frames don't
        -- linger after the user closes the options window.
        if ns._bossPreviewActive and ns.SetBossPreview then
            ns.SetBossPreview(false)
        end
    end)

    ---------------------------------------------------------------------------
    --  Individual Display unit selector
    ---------------------------------------------------------------------------
    local selectedUnit = "player"

    -- Allow external code to pre-select a unit before page rebuild.
    -- Two mechanisms: direct setter + pending override consumed at page build time.
    EllesmereUI._setUnitFrameUnit = function(unit) selectedUnit = unit end
    EllesmereUI._consumePendingUnitSelect = function()
        local pending = EllesmereUI._pendingUnitSelect
        if pending then
            selectedUnit = pending
            EllesmereUI._pendingUnitSelect = nil
        end
    end

    local unitLabels = {
        ["player"]       = "Player",
        ["target"]       = "Target",
        ["focus"]        = "Focus",
        ["targettarget"] = "Target of Target",
        ["focustarget"]  = "Focus Target",
        ["pet"]          = "Pet",
        ["boss"]         = "Boss",
    }
    local unitOrder = { "player", "target", "focus" }

    -- Side mapping: which side the portrait sits on for each unit
    local unitSide = {
        ["player"]       = "left",
        ["target"]       = "right",
        ["focus"]        = "right",
        ["targettarget"] = "left",
        ["focustarget"]  = "left",
        ["pet"]          = "left",
        ["boss"]         = "right",
    }

    ---------------------------------------------------------------------------
    --  Group editing state  (sync icon targets)
    ---------------------------------------------------------------------------
    -- Map unit keys to their DB settings table
    local UNIT_DB_MAP = {
        player       = function() return db.profile.player end,
        target       = function() return db.profile.target end,
        focus        = function() return db.profile.focus end,
        targettarget = function() return db.profile.targettarget end,
        focustarget  = function() return db.profile.focustarget end,
        pet          = function() return db.profile.pet end,
        boss         = function() return db.profile.boss end,
    }

    local GROUP_UNIT_ORDER = { "player", "target", "focus" }
    local SHORT_LABELS = {
        player       = "Player",
        target       = "Target",
        focus        = "Focus",
        targettarget = "Target of Target",
        focustarget  = "Focus Target",
        pet          = "Pet",
        boss         = "Boss",
    }


    ---------------------------------------------------------------------------
    --  Health display dropdown values
    ---------------------------------------------------------------------------
    local healthDisplayValues = {
        ["both"]       = "Current HP | Percent",
        ["curhpshort"] = "Current HP Only",
        ["perhp"]      = "Percent Only",
    }
    local healthDisplayOrder = { "both", "curhpshort", "perhp" }

    ---------------------------------------------------------------------------
    --  Health bar texture dropdown  built LIVE each render (mirrors
    --  GetBorderTextureDropdown) so SharedMedia textures registered by other
    --  addons after login ALWAYS appear. The shared ns tables are also kept
    --  current by an LSM registration callback, so late packs are never missed.
    ---------------------------------------------------------------------------
    local function BuildBarTexDropdown()
        -- Refresh the shared snapshot from LSM (registers this consumer for the
        -- late-registration callback on first call; idempotent thereafter).
        if EllesmereUI.AppendSharedMediaTextures then
            EllesmereUI.AppendSharedMediaTextures(
                ns.healthBarTextureNames or {},
                ns.healthBarTextureOrder or {},
                nil,
                ns.healthBarTextures
            )
        end

        local hbtValues, hbtOrder = {}, {}
        local texNames = ns.healthBarTextureNames or {}
        local texOrder2 = ns.healthBarTextureOrder or {}
        for _, key in ipairs(texOrder2) do
            if key ~= "---" then
                hbtValues[key] = texNames[key] or key
                hbtOrder[#hbtOrder + 1] = key
            end
        end
        -- _menuOpts: texture preview backgrounds on each item
        local texLookup = ns.healthBarTextures or {}
        hbtValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                return texLookup[key]
            end,
            onItemHover = function(key)
                local texPath = texLookup[key]
                for _, pv in pairs(allPreviews) do
                    if pv then
                        local hFill = pv._healthFill
                        if hFill then
                            if texPath then
                                hFill:SetTexture(texPath)
                                hFill:SetVertexColor(pv._hR or 0.8, pv._hG or 0.2, pv._hB or 0.2, 1)
                            else
                                hFill:SetVertexColor(1, 1, 1, 1)
                                hFill:SetColorTexture(pv._hR or 0.8, pv._hG or 0.2, pv._hB or 0.2, 1)
                            end
                        end
                        local pFill = pv._powerFill
                        if pFill then
                            local pvR, pvG, pvB = pv._pR or 0, pv._pG or 0, pv._pB or 1
                            if texPath then
                                pFill:SetTexture(texPath)
                                pFill:SetVertexColor(pvR, pvG, pvB, 1)
                            else
                                pFill:SetVertexColor(1, 1, 1, 1)
                                pFill:SetColorTexture(pvR, pvG, pvB, 1)
                            end
                        end
                    end
                end
            end,
            onItemLeave = function(key)
                -- Revert to the saved texture
                for _, pv in pairs(allPreviews) do
                    if pv and pv.Update then pv:Update() end
                end
            end,
        }
        return hbtValues, hbtOrder
    end

    ---------------------------------------------------------------------------
    --  Buff anchor / growth direction dropdown values
    ---------------------------------------------------------------------------
    local buffAnchorValues = {
        ["none"]        = "None",
        ["topleft"]     = "Top Left",
        ["topright"]    = "Top Right",
        ["bottomleft"]  = "Bottom Left",
        ["bottomright"] = "Bottom Right",
        ["left"]        = "Left",
        ["right"]       = "Right",
    }
    local buffAnchorOrder = { "none", "topleft", "topright", "bottomleft", "bottomright", "left", "right" }

    local buffGrowthValues = {
        ["auto"]  = "Auto",
        ["up"]    = "Up",
        ["down"]  = "Down",
        ["left"]  = "Left",
        ["right"] = "Right",
    }
    local buffGrowthOrder = { "auto", "up", "down", "left", "right" }

    local classPowerStyleValues = {
        ["none"]     = "None",
        ["modern"]   = "Modern",
        ["blizzard"] = "Blizzard",
    }
    local classPowerStyleOrder = { "none", "modern", "blizzard" }

    local classPowerPosValues = {
        ["top"]    = "Top",
        ["bottom"] = "Bottom",
        ["above"]  = "Above Health Bar",
    }
    local classPowerPosOrder = { "top", "bottom", "above" }

    ---------------------------------------------------------------------------
    --  Text content dropdown values (left / right text)
    ---------------------------------------------------------------------------
    -- Health bar text dropdown values (no power options)
    local healthTextValues = {
        ["name"]         = "Name",
        ["nametotarget"] = "Name > Target",
        ["levelname"]    = "Level | Name",
        ["namelevel"]    = "Name | Level",
        ["level"]        = "Level",
        ["perhp"]        = "Health %",
        ["perhpnosign"]  = "Health % (No Sign)",
        ["curhpshort"]   = "Health #",
        ["perhpnum"]     = "Health % | #",
        ["both"]         = "Health # | %",
        ["bothdash"]     = "Health # - %",
        ["perhpnumdash"] = "Health % - #",
        ["absorb"]       = "Absorb Amount",
        ["absorbshort"]  = "Absorb Short (230k)",
        ["healabsorb"]      = "Heal Absorb Amount",
        ["healabsorbshort"] = "Heal Absorb Short (80k)",
        ["group"]        = "Group Number",
        ["none"]         = "None",
    }
    local healthTextOrder = { "none", "---", "name", "levelname", "namelevel", "level", "perhp", "perhpnosign", "curhpshort", "perhpnum", "both" }
    -- Boss frames also get "Name > Target" (the boss's current target); the other
    -- mini frames (Target of Target / Focus Target / Pet) do not.
    local healthTextOrderBoss = { "none", "---", "name", "nametotarget", "levelname", "namelevel", "level", "perhp", "perhpnosign", "curhpshort", "perhpnum", "both", "bothdash", "perhpnumdash" }
    local healthTextOrderPlayer = { "none", "---", "name", "nametotarget", "levelname", "namelevel", "level", "perhp", "perhpnosign", "curhpshort", "perhpnum", "both", "bothdash", "perhpnumdash", "absorb", "absorbshort", "healabsorb", "healabsorbshort", "group" }
    -- Target/Focus get the same absorb text options as player, minus "group"
    -- (Group Number is the player's own raid group; it is meaningless on a target/focus).
    local healthTextOrderTargetFocus = { "none", "---", "name", "nametotarget", "levelname", "namelevel", "level", "perhp", "perhpnosign", "curhpshort", "perhpnum", "both", "bothdash", "perhpnumdash", "absorb", "absorbshort", "healabsorb", "healabsorbshort" }

    -- Text bar (BTB) text dropdown values (includes power options)
    local btbTextValues = {
        ["name"]         = "Name",
        ["perhp"]        = "Health %",
        ["perhpnosign"]  = "Health % (No Sign)",
        ["curhpshort"]   = "Health #",
        ["perhpnum"]     = "Health % | #",
        ["both"]         = "Health # | %",
        ["perpp"]        = "Power %",
        ["curpp"]        = "Power Value",
        ["curhp_curpp"]  = "Health | Power Value",
        ["perhp_perpp"]  = "Health | Power %",
        ["none"]         = "None",
    }
    local btbTextOrder = { "none", "---", "name", "perhp", "perhpnosign", "curhpshort", "perhpnum", "both", "perpp", "curpp", "curhp_curpp", "perhp_perpp" }

    -- Class theme portrait icons (full-size versions of the sidebar class art)
    -- Always use EllesmereUIUnitFrames path since only that addon ships the -full.png files
    local ICONS_PATH = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
    local CLASS_FULL_SPRITE_BASE = ICONS_PATH .. "class-full\\"

    local CLASS_FULL_COORDS = {
        WARRIOR     = { 0,     0.125, 0,     0.125 },
        MAGE        = { 0.125, 0.25,  0,     0.125 },
        ROGUE       = { 0.25,  0.375, 0,     0.125 },
        DRUID       = { 0.375, 0.5,   0,     0.125 },
        EVOKER      = { 0.5,   0.625, 0,     0.125 },
        HUNTER      = { 0,     0.125, 0.125, 0.25  },
        SHAMAN      = { 0.125, 0.25,  0.125, 0.25  },
        PRIEST      = { 0.25,  0.375, 0.125, 0.25  },
        WARLOCK     = { 0.375, 0.5,   0.125, 0.25  },
        PALADIN     = { 0,     0.125, 0.25,  0.375 },
        DEATHKNIGHT = { 0.125, 0.25,  0.25,  0.375 },
        MONK        = { 0.25,  0.375, 0.25,  0.375 },
        DEMONHUNTER = { 0.375, 0.5,   0.25,  0.375 },
    }

    local classIconValues = {
        ["none"]="None", ["modern"]="Modern",
        ["arcade"]="Arcade", ["glyph"]="Glyph", ["legend"]="Legend",
        ["midnight"]="Midnight", ["pixel"]="Pixel", ["runic"]="Runic",
        _menuOpts = { itemHeight = 32, icon = function(key)
            if key == "none" then return nil end
            local _, ct = UnitClass("player")
            if not ct then return nil end
            local coords = CLASS_FULL_COORDS[ct]
            if not coords then return nil end
            return CLASS_FULL_SPRITE_BASE .. key .. ".tga", coords[1], coords[2], coords[3], coords[4]
        end },
    }
    local classIconOrder = { "none", "---", "arcade", "glyph", "legend", "midnight", "modern", "pixel", "runic" }
    local classIconLocValues = { ["left"]="Left", ["center"]="Center", ["right"]="Right" }
    local classIconLocOrder = { "left", "center", "right" }

    -- Swap helper for buff/debuff anchors: prevent both from occupying the same slot
    local function SwapAuraSlot(settingsTable, changedKey, newVal)
        local otherKey = (changedKey == "buffAnchor") and "debuffAnchor" or "buffAnchor"
        local otherVal = settingsTable[otherKey] or (otherKey == "buffAnchor" and "topleft" or "bottomleft")
        if otherVal == newVal then
            local oldVal = settingsTable[changedKey] or (changedKey == "buffAnchor" and "topleft" or "bottomleft")
            settingsTable[otherKey] = oldVal
        end
        settingsTable[changedKey] = newVal
    end

    ---------------------------------------------------------------------------
    --  Preview builder: cosmetic unit frame preview
    --  Creates a simple health bar + power bar + portrait + castbar preview
    ---------------------------------------------------------------------------
    local PREVIEW_FONT = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames"))
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
    local SOLID_BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8" }
    local BORDER_BACKDROP = { edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

    -- Generic portrait image for NPC previews (player uses SetPortraitTexture)
    local ENEMY_PORTRAIT_PATH = "Interface\\AddOns\\EllesmereUI\\media\\enemy-portrait.png"

    -- Portrait mask/border media paths (for detached portrait shape preview)
    local PORTRAIT_MEDIA_P = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\"
    local PORTRAIT_MASKS_P = {
        portrait = PORTRAIT_MEDIA_P .. "portrait_mask.tga",
        circle   = PORTRAIT_MEDIA_P .. "circle_mask.tga",
        square   = PORTRAIT_MEDIA_P .. "square_mask.tga",
        csquare  = PORTRAIT_MEDIA_P .. "csquare_mask.tga",
        diamond  = PORTRAIT_MEDIA_P .. "diamond_mask.tga",
        hexagon  = PORTRAIT_MEDIA_P .. "hexagon_mask.tga",
        shield   = PORTRAIT_MEDIA_P .. "shield_mask.tga",
    }
    local PORTRAIT_BORDERS_P = {
        portrait = PORTRAIT_MEDIA_P .. "portrait_border.tga",
        circle   = PORTRAIT_MEDIA_P .. "circle_border.tga",
        square   = PORTRAIT_MEDIA_P .. "square_border.tga",
        csquare  = PORTRAIT_MEDIA_P .. "csquare_border.tga",
        diamond  = PORTRAIT_MEDIA_P .. "diamond_border.tga",
        hexagon  = PORTRAIT_MEDIA_P .. "hexagon_border.tga",
        shield   = PORTRAIT_MEDIA_P .. "shield_border.tga",
    }

    -- Top pixel inset for each mask shape (px from edge to visible portrait area)
    local MASK_INSETS = {
        circle   = 17,
        csquare  = 17,
        diamond  = 14,
        hexagon  = 17,
        portrait = 17,
        shield   = 13,
        square   = 17,
    }

    local function ApplyClassIconTexture_Preview(tex, classToken, style)
        local coords = CLASS_FULL_COORDS[classToken]
        if not coords then return false end
        tex:SetTexture(CLASS_FULL_SPRITE_BASE .. style .. ".tga")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        return true
    end

    -- Apply detached portrait shape to a preview portrait frame.
    -- pFrame: the preview portraitFrame
    -- s: per-unit settings table
    local function ApplyPreviewPortraitShape(pFrame, s)
        if not pFrame then return end
        local isDetached = (s.portraitStyle or db.profile.portraitStyle or "attached") == "detached"
        local shape = s.detachedPortraitShape or "portrait"
        local showBorder = true
        local borderOpacity = (s.detachedPortraitBorderOpacity or 100) / 100
        local borderColor = s.detachedPortraitBorderColor or { r = 0, g = 0, b = 0 }
        local useClassColor = s.detachedPortraitClassColor or false
        local rawBorderSize = s.detachedPortraitBorderSize or 7
        local bExp = 7 - rawBorderSize  -- scale border UP; mask clips inner portion

        local bR, bG, bB = borderColor.r, borderColor.g, borderColor.b
        if useClassColor then
            local _, ct = UnitClass("player")
            if ct then
                local c = RAID_CLASS_COLORS[ct]
                if c then bR, bG, bB = c.r, c.g, c.b end
            end
        end

        local texList = {}
        if pFrame._previewTex then table.insert(texList, pFrame._previewTex) end
        if pFrame._previewBg then table.insert(texList, pFrame._previewBg) end

        -- Remove mask when not detached
        if not isDetached then
            if pFrame._shapeMask then
                for _, tex in ipairs(texList) do tex:RemoveMaskTexture(pFrame._shapeMask) end
                pFrame._shapeMask:Hide()
            end
            if pFrame._shapeBorderTex then pFrame._shapeBorderTex:Hide() end
            if pFrame._sqBorderTexs then
                for _, t in ipairs(pFrame._sqBorderTexs) do t:Hide() end
            end
            -- Reset texture positions to default (detached mode expands them for mask fill)
            if pFrame._previewTex then
                pFrame._previewTex:ClearAllPoints()
                pFrame._previewTex:SetPoint("TOPLEFT", pFrame, "TOPLEFT", 0, 0)
                pFrame._previewTex:SetPoint("BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", 0, 0)
            end
            if pFrame._previewModel then
                pFrame._previewModel:ClearAllPoints()
                pFrame._previewModel:SetPoint("TOPLEFT", pFrame, "TOPLEFT", 0, 0)
                pFrame._previewModel:SetPoint("BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", 0, 0)
            end
            return
        end

        -- === MASK ===
        if shape == "none" then
            -- "None": remove mask, border, and background
            if pFrame._previewBg then pFrame._previewBg:Hide() end
            if pFrame._shapeMask then
                for _, tex in ipairs(texList) do pcall(tex.RemoveMaskTexture, tex, pFrame._shapeMask) end
                pFrame._shapeMask:Hide()
            end
            if pFrame._shapeBorderTex then pFrame._shapeBorderTex:Hide() end
            if pFrame._sqBorderTexs then
                for _, t in ipairs(pFrame._sqBorderTexs) do t:Hide() end
            end
            if pFrame._previewTex then
                pFrame._previewTex:ClearAllPoints()
                pFrame._previewTex:SetPoint("TOPLEFT", pFrame, "TOPLEFT", 0, 0)
                pFrame._previewTex:SetPoint("BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", 0, 0)
            end
            if pFrame._previewModel then
                pFrame._previewModel:ClearAllPoints()
                pFrame._previewModel:SetPoint("TOPLEFT", pFrame, "TOPLEFT", 0, 0)
                pFrame._previewModel:SetPoint("BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", 0, 0)
            end
            return
        end
        if pFrame._previewBg then pFrame._previewBg:Show() end
        local maskPath = PORTRAIT_MASKS_P[shape]
        if maskPath then
            if not pFrame._shapeMask then
                pFrame._shapeMask = pFrame:CreateMaskTexture()
                pFrame._shapeMask:SetAllPoints(pFrame)
            end
            pFrame._shapeMask:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            pFrame._shapeMask:Show()
            for _, tex in ipairs(texList) do tex:AddMaskTexture(pFrame._shapeMask) end
        end

        -- Hide old square border textures if they exist on this frame
        if pFrame._sqBorderTexs then
            for _, t in ipairs(pFrame._sqBorderTexs) do t:Hide() end
        end

        -- === TGA BORDER OVERLAY ===
        if not pFrame._shapeBorderTex then
            pFrame._shapeBorderTex = pFrame:CreateTexture(nil, "OVERLAY")
            if pFrame._shapeBorderTex.SetSnapToPixelGrid then pFrame._shapeBorderTex:SetSnapToPixelGrid(false); pFrame._shapeBorderTex:SetTexelSnappingBias(0) end
        end
        pFrame._shapeBorderTex:ClearAllPoints()
        PP.Point(pFrame._shapeBorderTex, "TOPLEFT", pFrame, "TOPLEFT", -bExp, bExp)
        PP.Point(pFrame._shapeBorderTex, "BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", bExp, -bExp)
        -- Add border to mask so the mask clips its inner edge
        if pFrame._shapeMask then
            pcall(pFrame._shapeBorderTex.RemoveMaskTexture, pFrame._shapeBorderTex, pFrame._shapeMask)
            pFrame._shapeBorderTex:AddMaskTexture(pFrame._shapeMask)
        end
        if showBorder then
            local bp = PORTRAIT_BORDERS_P[shape]
            if bp then
                pFrame._shapeBorderTex:SetTexture(bp)
                pFrame._shapeBorderTex:SetVertexColor(bR, bG, bB, borderOpacity)
                pFrame._shapeBorderTex:Show()
            else
                pFrame._shapeBorderTex:Hide()
            end
        else
            pFrame._shapeBorderTex:Hide()
        end

        -- Content positioning within mask (preview)
        -- Scale portrait so its visible area fills the mask opening.
        -- Content expands to fill mask; border size no longer affects content.
        local insetPx = MASK_INSETS[shape] or 17
        local bw = pFrame:GetWidth()
        local bh2 = pFrame:GetHeight()
        if bw < 1 then bw = 46 end
        if bh2 < 1 then bh2 = 46 end
        local visRatio = (128 - 2 * insetPx) / 128
        local cScale = 1 / visRatio
        -- Apply user art scale (100 = default, stored as percentage)
        local artScale = (s.portraitArtScale or 100) / 100
        cScale = cScale * artScale
        local expand = (cScale - 1) * 0.5
        local oL = -(expand * bw)
        local oR =  (expand * bw)
        local oT =  (expand * bh2)
        local oB = -(expand * bh2)
        if pFrame._previewTex then
            pFrame._previewTex:ClearAllPoints()
            PP.Point(pFrame._previewTex, "TOPLEFT", pFrame, "TOPLEFT", oL, oT)
            PP.Point(pFrame._previewTex, "BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", oR, oB)
        end
        if pFrame._previewModel then
            -- 3D models can't be clipped by SetClipsChildren, so keep them
            -- within the portrait frame bounds to prevent overflow
            pFrame._previewModel:ClearAllPoints()
            PP.Point(pFrame._previewModel, "TOPLEFT", pFrame, "TOPLEFT", 0, 0)
            PP.Point(pFrame._previewModel, "BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- Portrait art style dropdown values (was "Portrait Mode")
    local classThemeSubValues = {
        ["modern"]="Modern", ["arcade"]="Arcade", ["glyph"]="Glyph",
        ["legend"]="Legend", ["midnight"]="Midnight", ["pixel"]="Pixel", ["runic"]="Runic",
    }
    local classThemeSubOrder = { "modern", "arcade", "glyph", "legend", "midnight", "pixel", "runic" }
    local portraitArtValues = {
        ["3d"]    = "3D Portrait",
        ["2d"]    = "2D Portrait",
        ["class"] = {
            text = "Class",
            subnav = {
                order = classThemeSubOrder,
                values = classThemeSubValues,
                onSelect = nil,  -- wired per-unit below
                icon = nil,      -- wired per-unit below
                itemHeight = 32,
            },
        },
    }
    local portraitArtOrder = { "3d", "2d", "class" }

    -- Portrait mode dropdown values (was "Portrait Style")
    -- "none" hides the portrait entirely
    local portraitModeValues2 = {
        ["none"]     = "None",
        ["attached"] = "Attached",
        ["detached"] = "Detached",
    }
    local portraitModeOrder2 = { "none", "attached", "detached" }

    -- Detached portrait shape dropdown values
    local detPortraitShapeValues = {
        ["none"]     = "None",
        ["portrait"] = "Portrait",
        ["circle"]   = "Circle",
        ["square"]   = "Square",
        ["csquare"]  = "Rounded Square",
        ["diamond"]  = "Diamond",
        ["hexagon"]  = "Hexagon",
        ["shield"]   = "Shield",
    }
    local detPortraitShapeOrder = { "none", "portrait", "circle", "square", "csquare", "diamond", "hexagon", "shield" }

    -- Text Bar position dropdown values
    local btbPositionValues = {
        ["top"]             = "Top",
        ["bottom"]          = "Bottom",
        ["detached_top"]    = "Detached Top",
        ["detached_bottom"] = "Detached Bottom",
    }
    local btbPositionOrder = { "top", "bottom", "detached_top", "detached_bottom" }

    -- Enemy NPC names for preview (randomized on tab switch)
    local PREVIEW_ENEMY_NAMES = {
        "Doomguard", "Dreadlord", "Infernal", "Sea Giant", "Ogre Mage",
        "Satyr", "Stone Golem", "Water Elemental", "Silithid", "Naga Siren",
    }
    local PREVIEW_BOSS_NAMES = {
        "The Lich King", "Varimathras", "Cenarius", "Ragnaros", "Kel'Thuzad",
        "Archimonde", "Kil'jaeden", "Deathwing", "Yogg-Saron", "C'Thun",
    }
    -- Persistent random creature names per unit -- regenerated only on tab switch
    local _previewCreatureNames = {}

    -- Class-specific cast spells for player preview (only spells with cast times)
    -- Icons are resolved at runtime via C_Spell.GetSpellInfo to ensure correctness.
    local CLASS_CAST_SPELLS = {
        WARRIOR     = { {name="Slam", castTime=1.5}, {name="Whirlwind", castTime=1.5} },
        PALADIN     = { {name="Flash of Light", castTime=1.5}, {name="Holy Light", castTime=2.5}, {name="Hammer of Wrath", castTime=1.0} },
        HUNTER      = { {name="Aimed Shot", castTime=2.5}, {name="Steady Shot", castTime=1.8}, {name="Cobra Shot", castTime=2.0} },
        ROGUE       = { {name="Kidney Shot", castTime=1.5} },
        PRIEST      = { {name="Flash Heal", castTime=1.5}, {name="Smite", castTime=1.5}, {name="Mind Blast", castTime=1.5}, {name="Greater Heal", castTime=2.5} },
        DEATHKNIGHT = { {name="Death Coil", castTime=1.5}, {name="Howling Blast", castTime=1.5} },
        SHAMAN      = { {name="Lightning Bolt", castTime=2.0}, {name="Chain Lightning", castTime=2.0}, {name="Lava Burst", castTime=2.0}, {name="Healing Wave", castTime=2.5} },
        MAGE        = { {name="Fireball", castTime=2.25}, {name="Frostbolt", castTime=2.0}, {name="Arcane Blast", castTime=2.25}, {name="Pyroblast", castTime=4.0} },
        WARLOCK     = { {name="Shadow Bolt", castTime=2.0}, {name="Chaos Bolt", castTime=3.0}, {name="Incinerate", castTime=2.0} },
        MONK        = { {name="Vivify", castTime=1.5}, {name="Spinning Crane Kick", castTime=1.5} },
        DRUID       = { {name="Wrath", castTime=1.5}, {name="Starfire", castTime=2.25}, {name="Regrowth", castTime=1.5}, {name="Healing Touch", castTime=2.5} },
        DEMONHUNTER = { {name="Eye Beam", castTime=2.0} },
        EVOKER      = { {name="Fire Breath", castTime=2.5}, {name="Disintegrate", castTime=3.0}, {name="Living Flame", castTime=1.5}, {name="Eternity Surge", castTime=2.5} },
    }
    -- Fallback spells if class pool yields nothing with a cast time
    local FALLBACK_CAST_SPELLS = {
        {name="Cosmic Hearthstone", spellID=1242509, castTime=5.0},
        {name="Teleport Home", spellID=1233637, castTime=10.0},
    }
    -- Universal hearthstone spells added to every class pool
    local UNIVERSAL_CAST_SPELLS = {
        {name="Cosmic Hearthstone", spellID=1242509, castTime=5.0},
        {name="Teleport Home", spellID=1233637, castTime=10.0},
    }
    -- Resolve spell info from name at runtime (returns icon fileID and castTime in seconds)
    -- castTime comes from the API so we never show instant-cast spells in the preview
    local function ResolveSpellInfo(spellNameOrID)
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spellNameOrID)
            if info then
                local icon = info.iconID or 136197
                local ct = (info.castTime or 0) / 1000  -- API returns ms
                return icon, ct
            end
        end
        return 136197, 0
    end
    local _previewCastSpell  -- {icon, name, castTime} -- randomized on tab switch
    local _previewCastFill   -- 0.4 0.9 fill for the cast bar

    -- Class-specific common proc/buff icons for player preview (icon IDs)
    local CLASS_BUFF_ICONS = {
        WARRIOR     = { 132404, 132352, 132333, 136012, 458972 },
        PALADIN     = { 135964, 236254, 135993, 135920, 461860 },
        HUNTER      = { 132242, 132176, 132312, 132329, 461846 },
        ROGUE       = { 132290, 132350, 136206, 132301, 236279 },
        PRIEST      = { 135936, 135987, 237548, 135940, 136207 },
        DEATHKNIGHT = { 237517, 135834, 135833, 237511, 135840 },
        SHAMAN      = { 136048, 136052, 136042, 136044, 136053 },
        MAGE        = { 135812, 135846, 135735, 135808, 236219 },
        WARLOCK     = { 136197, 136145, 136188, 136169, 136162 },
        MONK        = { 606551, 627606, 775461, 606543, 620827 },
        DRUID       = { 136096, 136048, 136041, 136085, 136060 },
        DEMONHUNTER = { 1344649, 1247262, 1344650, 1344652, 1344651 },
        EVOKER      = { 4622462, 4622460, 4622468, 4622464, 4622466 },
    }
    local FALLBACK_BUFF_ICONS = { 135932, 135981, 136075, 136205, 135987 }
    local _previewBuffIcons = {}  -- 2 randomized buff icons for player preview

    local _previewHealthPct = 0.70  -- randomized health percentage for preview
    local _previewPowerPct = 0.85  -- randomized power percentage for preview

    local function RandomizePreviewCreatures()
        _previewCreatureNames.target       = PREVIEW_ENEMY_NAMES[math.random(#PREVIEW_ENEMY_NAMES)]
        _previewCreatureNames.focus        = PREVIEW_ENEMY_NAMES[math.random(#PREVIEW_ENEMY_NAMES)]
        _previewCreatureNames.pet          = PREVIEW_ENEMY_NAMES[math.random(#PREVIEW_ENEMY_NAMES)]
        _previewCreatureNames.targettarget = PREVIEW_ENEMY_NAMES[math.random(#PREVIEW_ENEMY_NAMES)]
        _previewCreatureNames.focustarget  = PREVIEW_ENEMY_NAMES[math.random(#PREVIEW_ENEMY_NAMES)]
        _previewCreatureNames.boss         = PREVIEW_BOSS_NAMES[math.random(#PREVIEW_BOSS_NAMES)]
        -- Randomize player cast spell (validate cast time via API, skip instants)
        local _, classToken = UnitClass("player")
        local classPool = CLASS_CAST_SPELLS[classToken] or {}
        -- Build combined pool: class spells + universal hearthstones
        local pool = {}
        for _, s in ipairs(classPool) do pool[#pool + 1] = s end
        for _, s in ipairs(UNIVERSAL_CAST_SPELLS) do pool[#pool + 1] = s end
        -- Shuffle pool (Fisher-Yates) then pick first spell with a real cast time
        for i = #pool, 2, -1 do
            local j = math.random(i)
            pool[i], pool[j] = pool[j], pool[i]
        end
        local chosen = nil
        for _, s in ipairs(pool) do
            local icon, ct = ResolveSpellInfo(s.spellID or s.name)
            if ct and ct > 0 then
                chosen = { icon = icon, name = s.name, castTime = ct }
                break
            end
        end
        -- If nothing had a cast time (shouldn't happen), use first entry with table castTime
        if not chosen then
            local fb = FALLBACK_CAST_SPELLS[1]
            chosen = { icon = 136197, name = fb.name, castTime = fb.castTime }
        end
        _previewCastSpell = chosen
        _previewCastFill = 0.40 + math.random() * 0.50
        -- Randomize health percentage (60%-90%)
        _previewHealthPct = 0.60 + math.random() * 0.30
        -- Randomize power percentage (50%-95%)
        _previewPowerPct = 0.50 + math.random() * 0.45
        -- Randomize 2 buff icons for player preview
        local buffPool = CLASS_BUFF_ICONS[classToken] or FALLBACK_BUFF_ICONS
        local i1 = math.random(#buffPool)
        local i2 = i1
        while i2 == i1 and #buffPool > 1 do i2 = math.random(#buffPool) end
        _previewBuffIcons[1] = buffPool[i1]
        _previewBuffIcons[2] = buffPool[i2]
    end


    local function BuildUnitPreview(parent, unitKey, side)
        -- The preview honors the aura Y offset only up to this magnitude, so a
        -- large offset can't balloon the preview / content header. Real frames
        -- still apply the full offset; only the preview clamps.
        local PREVIEW_Y_CAP = 50
        -- Preview fill coloring with optional additive gradient (mirrors real frames).
        local function PV_FillColor(tex, texPath, br, bg, bb, gEnabled, gColor, gDir, alpha)
            if not tex then return end
            if gEnabled then
                local gr, gg, gbb = 0.20, 0.20, 0.80
                if gColor then gr, gg, gbb = gColor.r, gColor.g, gColor.b end
                if texPath then tex:SetTexture(texPath) else tex:SetColorTexture(1, 1, 1, 1) end
                tex:SetVertexColor(1, 1, 1, 1)
                -- A gradient overrides the texture's region alpha, so Bar Opacity
                -- is baked into the gradient endpoint alphas.
                local a = alpha or 1
                tex:SetGradient(gDir or "HORIZONTAL", CreateColor(br, bg, bb, a), CreateColor(gr, gg, gbb, a))
            elseif texPath then
                tex:SetTexture(texPath)
                tex:SetVertexColor(br, bg, bb, 1)
            else
                tex:SetColorTexture(br, bg, bb, 1)
            end
        end
        local p = db.profile
        local settings
        if unitKey == "player" then settings = p.player
        elseif unitKey == "target" then settings = p.target
        elseif unitKey == "focus" then settings = p.focus
        elseif unitKey == "pet" then settings = p.pet
        elseif unitKey == "boss" then settings = p.boss
        elseif unitKey == "targettarget" then settings = p.targettarget
        elseif unitKey == "focustarget" then settings = p.focustarget
        else settings = p.player end

        side = side or "left"

        -- Mini frames (ToT/FoT/Pet) don't render power bars, debuffs, or
        -- castbars at runtime, so the preview must match.
        local isMiniPreview = (unitKey == "targettarget" or unitKey == "focustarget" or unitKey == "pet")
        local noPowerPreview = isMiniPreview
        local noDebuffPreview = isMiniPreview
        local noCastbarPreview = isMiniPreview

        local hasPortraitSupport = (settings.showPortrait ~= nil or settings.portraitMode ~= nil)
        local portraitShownByUser = settings.showPortrait ~= false
        local showPortrait = hasPortraitSupport
                         and (settings.portraitStyle or db.profile.portraitStyle or "attached") ~= "none"
                         and portraitShownByUser
        local frameW = settings.frameWidth or 181
        local healthH = settings.healthHeight or 46
        local powerH = noPowerPreview and 0 or (settings.powerHeight or 6)
        local initPpPos = noPowerPreview and "none" or (settings.powerPosition or "below")
        local initPpIsAtt = (initPpPos == "below" or initPpPos == "above")
        local initPpExtra = initPpIsAtt and powerH or 0
        -- For player, show preview castbar when showPlayerCastbar is on (always locked to frame)
        -- For target/focus, show when showCastbar is on
        -- Mini frames never show a castbar.
        local castbarH
        if noCastbarPreview then
            castbarH = 0
        elseif unitKey == "player" then
            local pch = settings.playerCastbarHeight
            castbarH = settings.showPlayerCastbar and (pch and pch > 0 and pch or 14) or 0
        else
            castbarH = (settings.showCastbar ~= false) and (settings.castbarHeight or 14) or 0
        end
        local barH = healthH + initPpExtra
        local isAttachedInit = (settings.portraitStyle or db.profile.portraitStyle or "attached") == "attached"
        local portraitW = (showPortrait and isAttachedInit) and barH or 0
        local totalW = frameW + portraitW
        local totalH = barH

        -- Compute initial aura extra height (buffs/debuffs extend beyond frame)
        local initBuffExtra = 0
        local initBuffTopPad = 0
        if settings.showBuffs then
            local ba = settings.buffAnchor or "topleft"
            -- Only top/bottom anchors extend the frame vertically; left/right
            -- columns grow sideways and need no extra vertical room.
            if ba == "topleft" or ba == "topright" or ba == "bottomleft" or ba == "bottomright" then
                initBuffExtra = (settings.buffSize or 22) + 1 + 2
            end
            if ba == "topleft" or ba == "topright" then
                initBuffTopPad = initBuffExtra
            end
            -- Mirror the Y-offset overflow that pf:Update reserves (auraTopOv/
            -- auraBotOv), so the first build positions the preview and the content
            -- below it correctly -- otherwise the spacing is wrong on unit switch
            -- until a slider nudge forces a full Update.
            local boy = math.max(-PREVIEW_Y_CAP, math.min(PREVIEW_Y_CAP, settings.buffOffsetY or 0))
            if ba == "topleft" or ba == "topright" then
                if boy > 0 then initBuffTopPad = initBuffTopPad + boy end
            elseif ba == "bottomleft" or ba == "bottomright" then
                if boy < 0 then initBuffExtra = initBuffExtra - boy end
            else
                if boy > 0 then initBuffTopPad = initBuffTopPad + boy
                elseif boy < 0 then initBuffExtra = initBuffExtra - boy end
            end
        end
        do
            local da = settings.debuffAnchor or "none"
            if da == "topleft" or da == "topright" or da == "bottomleft" or da == "bottomright" then
                local debuffH = (settings.debuffSize or 22) + 1 + 2
                initBuffExtra = initBuffExtra + debuffH
                if da == "topleft" or da == "topright" then
                    initBuffTopPad = initBuffTopPad + debuffH
                end
            end
            -- Mirror the debuff Y-offset overflow reserved in pf:Update.
            local doy = math.max(-PREVIEW_Y_CAP, math.min(PREVIEW_Y_CAP, settings.debuffOffsetY or 0))
            if da == "topleft" or da == "topright" then
                if doy > 0 then initBuffTopPad = initBuffTopPad + doy end
            elseif da == "bottomleft" or da == "bottomright" then
                if doy < 0 then initBuffExtra = initBuffExtra - doy end
            elseif da ~= "none" then
                if doy > 0 then initBuffTopPad = initBuffTopPad + doy
                elseif doy < 0 then initBuffExtra = initBuffExtra - doy end
            end
        end

        local pf = CreateFrame("Frame", nil, parent)
        -- Scale the preview so it matches real unit frame size on screen.
        -- Real unit frames render at UIParent's effective scale; the preview
        -- lives inside the EllesmereUI panel which has a smaller effective
        -- scale.  Applying this ratio makes every pixel value appear at the
        -- same physical size as the real frames.
        local previewScale = UIParent:GetEffectiveScale() / parent:GetEffectiveScale()
        pf:SetScale(previewScale)
        pf._buffExtra = initBuffExtra
        pf._buffTopPad = initBuffTopPad
        pf._previewScale = previewScale
        PP.Point(pf, "TOP", parent, "TOP", 0, -(25 + initBuffTopPad) / previewScale)

        -- barArea: child of pf sized to health+power only (excludes castbar).
        local barArea = CreateFrame("Frame", nil, pf)
        PP.Size(barArea, totalW, barH)
        PP.Point(barArea, "TOPLEFT", pf, "TOPLEFT", 0, 0)

        -- Portrait
        local portraitFrame
        if hasPortraitSupport then
            portraitFrame = CreateFrame("Frame", nil, pf)
            PP.Size(portraitFrame, barH, barH)
            portraitFrame:SetClipsChildren(true)
            local portraitBg = portraitFrame:CreateTexture(nil, "BACKGROUND")
            portraitBg:SetAllPoints()
            portraitBg:SetColorTexture(0.082, 0.082, 0.082, 1)
            portraitFrame._previewBg = portraitBg
            if side == "left" then
                PP.Point(portraitFrame, "TOPLEFT", barArea, "TOPLEFT", 0, 0)
            else
                PP.Point(portraitFrame, "TOPRIGHT", barArea, "TOPRIGHT", 0, 0)
            end

            local portraitTex = portraitFrame:CreateTexture(nil, "ARTWORK")
            portraitTex:SetPoint("TOPLEFT", portraitFrame, "TOPLEFT", 0, 0)
            portraitTex:SetPoint("BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", 0, 0)
            portraitTex:SetTexCoord(0.15, 0.85, 0.15, 0.85)

            -- 3D model for preview (lazy-created only when mode is "3d")
            local portraitModel = nil

            local function EnsurePreviewModel()
                if portraitModel then return portraitModel end
                portraitModel = CreateFrame("PlayerModel", nil, portraitFrame)
                portraitModel:SetPoint("TOPLEFT", portraitFrame, "TOPLEFT", 0, 0)
                portraitModel:SetPoint("BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", 0, 0)
                portraitModel:SetUnit("player")
                portraitModel:SetCamera(0)
                portraitModel:Hide()
                portraitFrame._previewModel = portraitModel
                return portraitModel
            end

            -- Track last applied mode+style+zoom to avoid redundant re-init
            local _lastAppliedMode = nil
            local _lastAppliedStyle = nil
            local _lastAppliedZoom = nil

            local function ApplyPortraitMode()
                -- Read settings fresh from DB so the closure never goes stale
                -- after a preview switch or cache restore.
                local curSettings
                if unitKey == "player" then curSettings = db.profile.player
                elseif unitKey == "target" then curSettings = db.profile.target
                elseif unitKey == "focus" then curSettings = db.profile.focus
                elseif unitKey == "pet" then curSettings = db.profile.pet
                elseif unitKey == "boss" then curSettings = db.profile.boss
                elseif unitKey == "targettarget" then curSettings = db.profile.targettarget
                elseif unitKey == "focustarget" then curSettings = db.profile.focustarget
                else curSettings = db.profile.player end
                local mode = curSettings.portraitMode or "2d"
                local style = curSettings.classThemeStyle or "modern"
                local zoom = (curSettings.portraitArtScale or 100) + (curSettings.portrait3dZoom or 100) * 1000
                -- Skip if nothing changed -- avoids re-initializing PlayerModel
                -- every Update() call which causes blinking and massive GPU cost
                if mode == _lastAppliedMode and style == _lastAppliedStyle and zoom == _lastAppliedZoom then return end
                _lastAppliedMode = mode
                _lastAppliedStyle = style
                _lastAppliedZoom = zoom
                if mode == "3d" then
                    portraitFrame:Show()
                    portraitTex:Hide()
                    local pm = EnsurePreviewModel()
                    pm:SetUnit("player")
                    pm:SetCamera(0)
                    pm:SetPortraitZoom(1)
                    pm:SetPosition(0, 0, 0)
                    local camScale = (curSettings.portrait3dZoom or 100) / 100
                    pm:SetCamDistanceScale(camScale)
                    pm:Show()
                elseif mode == "class" then
                    portraitFrame:Show()
                    if portraitModel then portraitModel:Hide() end
                    portraitTex:Show()
                    local _, ct = UnitClass("player")
                    ApplyClassIconTexture_Preview(portraitTex, ct or "WARRIOR", style)
                    portraitTex:SetAlpha(0.9)
                    -- Use current portrait frame height for inset (not captured barH)
                    local curBH = portraitFrame:GetHeight()
                    if curBH < 1 then curBH = barH end
                    local inset = math.floor(curBH * 0.10)
                    portraitTex:ClearAllPoints()
                    PP.Point(portraitTex, "TOPLEFT", portraitFrame, "TOPLEFT", inset, -inset)
                    PP.Point(portraitTex, "BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", -inset, inset)
                else
                    portraitFrame:Show()
                    if portraitModel then portraitModel:Hide() end
                    portraitTex:Show()
                    SetPortraitTexture(portraitTex, "player")
                    portraitTex:SetTexCoord(0.15, 0.85, 0.15, 0.85)
                    portraitTex:SetAlpha(1)
                    portraitTex:ClearAllPoints()
                    PP.Point(portraitTex, "TOPLEFT", portraitFrame, "TOPLEFT", 0, 0)
                    PP.Point(portraitTex, "BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", 0, 0)
                end
            end
            portraitFrame._applyMode = ApplyPortraitMode
            portraitFrame._previewTex = portraitTex
            portraitFrame._previewModel = portraitModel
            ApplyPortraitMode()

            if not showPortrait then
                portraitFrame:Hide()
            end
        end

        -- Health bar color
        local hR, hG, hB, hA, bgR, bgG, bgB, bgA
        local isDarkTheme = db.profile.darkTheme
        if isDarkTheme then
            hR, hG, hB, hA = EllesmereUI.GetDarkModeFill()
            bgR, bgG, bgB, bgA = EllesmereUI.GetDarkModeBg()
        else
            local barOpacity = (settings.healthBarOpacity or 90) / 100
            hA = barOpacity
            -- Check for custom fill color (skipped when class colored is enabled).
            -- Boss preview always renders as hostile-red since the real boss
            -- frame never class-colors (no player class).
            local cFill = settings.customFillColor
            local isClassColored = settings.healthClassColored and unitKey ~= "boss"
            if isClassColored then
                local _, classToken = UnitClass("player")
                local cc = RAID_CLASS_COLORS[classToken]
                if cc then hR, hG, hB = cc.r, cc.g, cc.b
                else hR, hG, hB = 37/255, 193/255, 29/255 end
            elseif cFill then
                hR, hG, hB = cFill.r, cFill.g, cFill.b
            elseif unitKey == "player" then
                local _, classToken = UnitClass("player")
                local cc = RAID_CLASS_COLORS[classToken]
                if cc then hR, hG, hB = cc.r, cc.g, cc.b
                else hR, hG, hB = 37/255, 193/255, 29/255 end
            elseif unitKey == "pet" then
                hR, hG, hB = 37/255, 193/255, 29/255
            else
                hR, hG, hB = 0.8, 0.2, 0.2
            end
            -- Class-colored background (designer shows the player's class), else custom.
            local bgClassCC
            if settings.bgClassColored then
                local _, ct = UnitClass("player")
                bgClassCC = ct and EllesmereUI.GetClassColor(ct)
            end
            if bgClassCC then
                bgR, bgG, bgB = bgClassCC.r, bgClassCC.g, bgClassCC.b
            else
                local cBg = settings.customBgColor
                if cBg then
                    bgR, bgG, bgB = cBg.r, cBg.g, cBg.b
                else
                    bgR, bgG, bgB = 17/255, 17/255, 17/255
                end
            end
            bgA = (settings.customBgAlpha or 100) / 100
        end

        -- Health bar
        local health = CreateFrame("Frame", nil, pf)
        PP.Size(health, frameW, healthH)
        local healthBgColor = health:CreateTexture(nil, "BACKGROUND")
        -- Cover only the empty (missing-health) portion in both light and dark
        -- mode so a reduced fill opacity shows the backdrop through the fill, not
        -- the bg color. The live-update pass below re-anchors this accounting for
        -- reverse fill; matches the live frame edge-anchored bg.
        healthBgColor:SetPoint("TOPLEFT", health, "TOPLEFT", math.floor(frameW * (_previewHealthPct or 0.70) + 0.5), 0)
        healthBgColor:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
        healthBgColor:SetColorTexture(bgR, bgG, bgB, 1)
        healthBgColor:SetAlpha(bgA)
        local pvPowerAboveOff = (initPpPos == "above") and powerH or 0
        if showPortrait and portraitFrame then
            if side == "left" then
                PP.Point(health, "TOPLEFT", portraitFrame, "TOPRIGHT", 0, -pvPowerAboveOff)
            else
                PP.Point(health, "TOPRIGHT", portraitFrame, "TOPLEFT", 0, -pvPowerAboveOff)
            end
        else
            PP.Point(health, "TOPLEFT", barArea, "TOPLEFT", 0, -pvPowerAboveOff)
        end

        local healthBg = health:CreateTexture(nil, "BACKGROUND", nil, -1)
        healthBg:SetAllPoints()
        healthBg:SetColorTexture(0.1, 0.1, 0.1, 0.75)

        local healthFill = health:CreateTexture(nil, "ARTWORK")
        healthFill:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        healthFill:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
        healthFill:SetWidth(math.floor(frameW * (_previewHealthPct or 0.70) + 0.5))
        PV_FillColor(healthFill, nil, hR, hG, hB, (not isDarkTheme) and settings.gradientEnabled, settings.gradientColor, settings.gradientDir, hA)
        healthFill:SetAlpha(hA)
        pf._healthFill = healthFill
        pf._hR, pf._hG, pf._hB, pf._hA = hR, hG, hB, hA

        local dispelOverlayPreview
        if unitKey == "player" then
            dispelOverlayPreview = health:CreateTexture(nil, "ARTWORK", nil, 3)
            dispelOverlayPreview:SetTexture("Interface\\Buttons\\WHITE8X8")
            dispelOverlayPreview:Hide()
        end

        -- Text overlay frame (sits above absorb StatusBar and border)
        local textOverlay = CreateFrame("Frame", nil, pf)
        textOverlay:SetAllPoints(health)
        textOverlay:SetFrameStrata(pf:GetFrameStrata())
        textOverlay:SetFrameLevel(math.max(pf:GetFrameLevel() + 20, health:GetFrameLevel() + 12))

        -- Left text
        local leftContent = settings.leftTextContent or "name"
        local rightContent = settings.rightTextContent or (unitKey == "focus" and "perhp" or "both")
        local leftTS = settings.leftTextSize or settings.textSize or 12
        local rightTS = settings.rightTextSize or settings.textSize or 12
        local leftFS = textOverlay:CreateFontString(nil, "OVERLAY")
        SetPVFont(leftFS, PREVIEW_FONT, leftTS)
        leftFS:SetTextColor(1, 1, 1)
        leftFS:SetWordWrap(false)

        -- Right text
        local rightFS = textOverlay:CreateFontString(nil, "OVERLAY")
        SetPVFont(rightFS, PREVIEW_FONT, rightTS)
        rightFS:SetTextColor(1, 1, 1)
        rightFS:SetWordWrap(false)

        local centerFS = textOverlay:CreateFontString(nil, "OVERLAY")
        SetPVFont(centerFS, PREVIEW_FONT, settings.centerTextSize or settings.textSize or 12)
        centerFS:SetTextColor(1, 1, 1)
        centerFS:SetWordWrap(false)

        -- Extra Text preview FontString: anchored per extraTextAlign,
        -- never width-constrained (matches the live frame's zero-truncation behavior).
        local extraFS = textOverlay:CreateFontString(nil, "OVERLAY")
        SetPVFont(extraFS, PREVIEW_FONT, settings.extraTextSize or settings.textSize or 12)
        extraFS:SetTextColor(1, 1, 1)
        extraFS:SetWordWrap(false)

        -- Resolve preview text for a content key
        local function PreviewTextForContent(content, s, prefix)
            -- Mirror live "Show Decimal on Text": one decimal on abbreviated values
            -- and percents when the global flag is on; integer (current) otherwise.
            local function _pvAbbrev(v)
                local cfg = _G._EUI_AbbrevDecimalCfg
                return cfg and AbbreviateNumbers(v, cfg) or AbbreviateNumbers(v)
            end
            local function _pvPct(p01)
                return _G._EUI_TextDecimals and string.format("%.1f", p01 * 100) or tostring(math.floor(p01 * 100))
            end
            local function _pvName()
                if unitKey == "player" then return UnitName("player") or "Player" end
                return _previewCreatureNames[unitKey] or unitKey
            end
            local function _pvTargetSuffix()
                local _, ct = UnitClass("player")
                local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                local tgt = "Target"
                if cc then
                    tgt = string.format("|cff%02x%02x%02x%s|r", math.floor(cc.r * 255 + 0.5), math.floor(cc.g * 255 + 0.5), math.floor(cc.b * 255 + 0.5), tgt)
                end
                -- Mirror the live [eui-tgtsep(...)] tag: per-slot separator
                -- string, space-padded, indicator colored class (the preview
                -- target's class = the player's) or custom (default white).
                local sep = prefix and s[prefix .. "TargetSep"]
                if type(sep) ~= "string" or sep == "" then sep = ">" end
                sep = " " .. sep .. " "
                if prefix and s[prefix .. "TargetSepClassColor"] then
                    if cc then
                        sep = string.format("|cff%02x%02x%02x%s|r", math.floor(cc.r * 255 + 0.5), math.floor(cc.g * 255 + 0.5), math.floor(cc.b * 255 + 0.5), sep)
                    end
                else
                    local c = prefix and s[prefix .. "TargetSepColor"]
                    local r, g, b = 1, 1, 1
                    if type(c) == "table" then r, g, b = c.r or 1, c.g or 1, c.b or 1 end
                    sep = string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), sep)
                end
                return sep .. tgt
            end
            local function _pvShortName(raw)
                if not prefix then return raw end
                local maxLen = s[prefix .. "ShortNameLength"] or 0
                if maxLen <= 0 then return raw end
                local useEllipsis = s[prefix .. "ShortNameEllipsis"] ~= false
                -- Mirror the live eui-name tag exactly: truncate by UTF-8
                -- codepoints on a character boundary, never by bytes.
                local i, chars = 1, 0
                local len = #raw
                while i <= len do
                    if chars == maxLen then
                        local cut = raw:sub(1, i - 1)
                        if useEllipsis then return cut .. "..." end
                        return cut
                    end
                    local b = raw:byte(i)
                    i = i + ((b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1)
                    chars = chars + 1
                end
                return raw
            end
            if content == "name" then
                return _pvShortName(_pvName())
            elseif content == "nametotarget" then
                return _pvShortName(_pvName()) .. _pvTargetSuffix()
            elseif content == "level" or content == "levelname" or content == "namelevel" then
                local lvl = UnitLevel("player")
                lvl = (type(lvl) == "number" and lvl > 0) and tostring(lvl) or "80"
                if content == "level" then return lvl
                elseif content == "levelname" then return lvl .. " | " .. _pvShortName(_pvName())
                else return _pvShortName(_pvName()) .. " | " .. lvl end
            elseif content == "both" or content == "bothdash" or content == "curhpshort" or content == "perhp" or content == "perhpnosign" or content == "perhpnum" or content == "perhpnumdash" then
                local maxHP = UnitHealthMax("player") or 1
                local pct = _previewHealthPct or 0.70
                local curHP = math.floor(maxHP * pct)
                if content == "curhpshort" then return _pvAbbrev(curHP)
                elseif content == "perhp" then return _pvPct(pct) .. "%"
                elseif content == "perhpnosign" then return _pvPct(pct)
                elseif content == "perhpnum" then return _pvPct(pct) .. "% | " .. _pvAbbrev(curHP)
                elseif content == "perhpnumdash" then return _pvPct(pct) .. "% - " .. _pvAbbrev(curHP)
                elseif content == "bothdash" then return _pvAbbrev(curHP) .. " - " .. _pvPct(pct) .. "%"
                else return _pvAbbrev(curHP) .. " | " .. _pvPct(pct) .. "%" end
            elseif content == "perpp" then
                local ppPct = _previewPowerPct or 0.85
                return math.floor(ppPct * 100) .. "%"
            elseif content == "curpp" then
                local maxPP = UnitPowerMax("player") or 100
                local ppPct = _previewPowerPct or 0.85
                return AbbreviateNumbers(math.floor(maxPP * ppPct))
            elseif content == "curhp_curpp" then
                local maxHP = UnitHealthMax("player") or 1
                local pct = _previewHealthPct or 0.70
                local curHP = math.floor(maxHP * pct)
                local maxPP = UnitPowerMax("player") or 100
                local ppPct2 = _previewPowerPct or 0.85
                return _pvAbbrev(curHP) .. " | " .. AbbreviateNumbers(math.floor(maxPP * ppPct2))
            elseif content == "perhp_perpp" then
                local pct = _previewHealthPct or 0.70
                local ppPct3 = _previewPowerPct or 0.85
                return _pvPct(pct) .. "% | " .. math.floor(ppPct3 * 100) .. "%"
            elseif content == "absorb" then
                local maxHP = UnitHealthMax("player") or 1
                return string.format("%d", math.floor(maxHP * 0.14))
            elseif content == "absorbshort" then
                local maxHP = UnitHealthMax("player") or 1
                return _pvAbbrev(math.floor(maxHP * 0.14))
            elseif content == "healabsorb" then
                local maxHP = UnitHealthMax("player") or 1
                return string.format("%d", math.floor(maxHP * 0.08))
            elseif content == "healabsorbshort" then
                local maxHP = UnitHealthMax("player") or 1
                return _pvAbbrev(math.floor(maxHP * 0.08))
            elseif content == "group" then
                return "3"
            else
                return ""
            end
        end

        -- Class color helper for preview
        local function PreviewClassColor(fs, useCC, customR, customG, customB)
            if not fs then return end
            if useCC then
                if unitKey == "player" then
                    local _, cls = UnitClass("player")
                    if cls then
                        local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[cls]
                        if c then fs:SetTextColor(c.r, c.g, c.b); return end
                    end
                else
                    fs:SetTextColor(0.9, 0.3, 0.3); return
                end
            end
            fs:SetTextColor(customR or 1, customG or 1, customB or 1)
        end


        -- Power color override for preview (takes priority over class color for power-related text)
        local function PreviewPowerColor(fs, contentKey, usePowerColor)
            if not fs or not usePowerColor then return end
            if contentKey == "perpp" or contentKey == "curpp" or contentKey == "curhp_curpp" or contentKey == "perhp_perpp" then
                -- EUI global power color (player's current power), matching the
                -- real frame -- not hardcoded blue.
                local _, pToken = UnitPowerType("player")
                local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                if info then fs:SetTextColor(info.r, info.g, info.b)
                else fs:SetTextColor(1, 1, 1) end
            end
        end
        local function ApplyPreviewTextPositions(s, donorS)
            local lc = s.leftTextContent or "name"
            local rc = s.rightTextContent or (unitKey == "focus" and "perhp" or "both")
            local cc = s.centerTextContent or "none"
            local fontS = donorS or s
            local lsz = fontS.leftTextSize or fontS.textSize or 12
            local rsz = fontS.rightTextSize or fontS.textSize or 12
            local csz = fontS.centerTextSize or fontS.textSize or 12
            local lxo = s.leftTextX or 0
            local lyo = s.leftTextY or 0
            local rxo = s.rightTextX or 0
            local ryo = s.rightTextY or 0
            local cxo = s.centerTextX or 0
            local cyo = s.centerTextY or 0


            -- Extra Text preview: anchored per extraTextAlign, no truncation.
            local ec = s.extraTextContent or "none"
            extraFS:SetFont(PREVIEW_FONT, (fontS.extraTextSize or fontS.textSize or 12), GetUFOptOutline())
            extraFS:ClearAllPoints()
            extraFS:SetWidth(0)
            if ec ~= "none" then
                local exo = s.extraTextX or 0
                local eyo = s.extraTextY or 0
                local ealign = s.extraTextAlign or "left"
                if ealign == "right" then
                    extraFS:SetJustifyH("RIGHT")
                    PP.Point(extraFS, "RIGHT", textOverlay, "RIGHT", -5 + exo, eyo)
                elseif ealign == "center" then
                    extraFS:SetJustifyH("CENTER")
                    PP.Point(extraFS, "CENTER", textOverlay, "CENTER", exo, eyo)
                else
                    extraFS:SetJustifyH("LEFT")
                    PP.Point(extraFS, "LEFT", textOverlay, "LEFT", 5 + exo, eyo)
                end
                extraFS:SetText(PreviewTextForContent(ec, s, "extraText"))
                extraFS:Show()
                PreviewClassColor(extraFS, s.extraTextClassColor, s.extraTextColorR, s.extraTextColorG, s.extraTextColorB)
            else
                extraFS:Hide()
            end

            -- Each text position renders independently; Center no longer hides Left/Right.
            centerFS:SetFont(PREVIEW_FONT, csz, GetUFOptOutline())
            centerFS:ClearAllPoints()
            if cc ~= "none" then
                centerFS:SetJustifyH("CENTER")
                PP.Point(centerFS, "CENTER", textOverlay, "CENTER", cxo, cyo)
                centerFS:SetText(PreviewTextForContent(cc, s, "centerText"))
                centerFS:Show()
                PreviewClassColor(centerFS, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
            else
                centerFS:Hide()
            end

            leftFS:SetFont(PREVIEW_FONT, lsz, GetUFOptOutline())
            leftFS:ClearAllPoints()
            if lc ~= "none" then
                leftFS:SetJustifyH("LEFT")
                PP.Point(leftFS, "LEFT", textOverlay, "LEFT", 5 + lxo, lyo)
                -- Constrain width when opposing right text exists (matches live frame truncation)
                local barW = s.frameWidth or 181
                if rc ~= "none" then
                    local UF_TEXT_PADDING = 10
                    local ufTW = { both = 75, curhpshort = 38, perhp = 38, perpp = 38, curpp = 38, curhp_curpp = 75, perhp_perpp = 75, level = 24 }
                    local rightUsed = (ufTW[rc] or 0) + UF_TEXT_PADDING
                    PP.Width(leftFS, math.max(barW - rightUsed - 10, 20))
                else
                    leftFS:SetWidth(0)
                end
                leftFS:SetText(PreviewTextForContent(lc, s, "leftText"))
                leftFS:Show()
                PreviewClassColor(leftFS, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
            else
                leftFS:Hide()
            end

            rightFS:SetFont(PREVIEW_FONT, rsz, GetUFOptOutline())
            rightFS:ClearAllPoints()
            if rc ~= "none" then
                rightFS:SetJustifyH("RIGHT")
                PP.Point(rightFS, "RIGHT", textOverlay, "RIGHT", -5 + rxo, ryo)
                rightFS:SetText(PreviewTextForContent(rc, s, "rightText"))
                rightFS:Show()
                PreviewClassColor(rightFS, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
            else
                rightFS:Hide()
            end
        end
        ApplyPreviewTextPositions(settings)

        -- Power bar
        local power
        local ppPreviewFS
        -- Create the bar (and its text overlay) for any power-supporting unit, even
        -- at height 0, so "power bar 0 + text" works and the bar isn't lost when the
        -- height goes 0 -> back up. noPowerPreview units (no power) still skip it.
        if not noPowerPreview then
            power = CreateFrame("Frame", nil, pf)
            PP.Size(power, frameW, powerH)
            local powerBg = power:CreateTexture(nil, "BACKGROUND")
            powerBg:SetAllPoints()
            pf._powerBg = powerBg
            local powerFill = power:CreateTexture(nil, "ARTWORK")
            powerFill:SetPoint("TOPLEFT", power, "TOPLEFT", 0, 0)
            powerFill:SetPoint("BOTTOMLEFT", power, "BOTTOMLEFT", 0, 0)
            powerFill:SetWidth(math.floor(frameW * (_previewPowerPct or 0.85) + 0.5))
            pf._powerFill = powerFill

            -- Apply custom power bar colors or default
            local isPowerColored = settings.powerPercentPowerColor ~= false
            local customPFill = settings.customPowerFillColor
            local customPBg = settings.customPowerBgColor
            local pfR, pfG, pfB
            if isPowerColored then
                local _, pToken = UnitPowerType("player")
                local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                pfR, pfG, pfB = info.r, info.g, info.b
            elseif customPFill then
                pfR, pfG, pfB = customPFill.r, customPFill.g, customPFill.b
            else
                pfR, pfG, pfB = 0, 0, 1
            end
            local pbR, pbG, pbB
            if settings.powerBgPowerColored then
                local _, pbToken = UnitPowerType("player")
                local pbInfo = EllesmereUI.GetPowerColor(pbToken or "MANA")
                local pbF = EllesmereUI.GetPowerBgDarkenFactor()
                pbR, pbG, pbB = pbInfo.r * pbF, pbInfo.g * pbF, pbInfo.b * pbF
            elseif customPBg then
                pbR, pbG, pbB = customPBg.r, customPBg.g, customPBg.b
            else
                pbR, pbG, pbB = 17/255, 17/255, 17/255
            end
            local powerOpacity = (settings.powerBarOpacity or 100) / 100
            powerBg:SetColorTexture(pbR, pbG, pbB, 1)
            powerBg:SetAlpha((settings.customPowerBgAlpha or 100) / 100)
            PV_FillColor(powerFill, nil, pfR, pfG, pfB, settings.powerGradientEnabled, settings.powerGradientColor, settings.powerGradientDir, powerOpacity)
            powerFill:SetAlpha(powerOpacity)
            -- Fill Opacity below 100: bg covers only the empty portion so the
            -- preview mirrors the live world-show-through behavior.
            if powerOpacity < 1 then
                pf._powerBgOpAnchored = true
                powerBg:ClearAllPoints()
                if settings.powerReverseFill then
                    powerBg:SetPoint("TOPLEFT", power, "TOPLEFT", 0, 0)
                    powerBg:SetPoint("BOTTOMRIGHT", powerFill, "BOTTOMLEFT", 0, 0)
                else
                    powerBg:SetPoint("TOPLEFT", powerFill, "TOPRIGHT", 0, 0)
                    powerBg:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
                end
            end
            -- Initial anchor based on power position
            if initPpPos == "none" then
                power:Hide()
            elseif initPpPos == "above" then
                PP.Point(power, "BOTTOMLEFT", health, "TOPLEFT", 0, 0)
                PP.Point(power, "BOTTOMRIGHT", health, "TOPRIGHT", 0, 0)
            elseif initPpPos == "detached_top" then
                power:SetPoint("BOTTOM", health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
            elseif initPpPos == "detached_bottom" then
                power:SetPoint("TOP", health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
            else
                PP.Point(power, "TOPLEFT", health, "BOTTOMLEFT", 0, 0)
                PP.Point(power, "TOPRIGHT", health, "BOTTOMRIGHT", 0, 0)
            end

            -- Power percent text overlay in preview (parented to pf, above border)
            local ppOvr = CreateFrame("Frame", nil, pf)
            ppOvr:SetAllPoints(power)
            ppOvr:SetFrameLevel(barArea:GetFrameLevel() + 8)
            ppPreviewFS = ppOvr:CreateFontString(nil, "OVERLAY")
            SetPVFont(ppPreviewFS, PREVIEW_FONT, 9)
            ppPreviewFS:Hide()
        end

        -- Bar texture: applied to the fill textures directly (preview uses plain Frames, not StatusBars)
        do
            local texKey = settings.healthBarTexture or db.profile.healthBarTexture or "none"
            local texPath = (ns.healthBarTextures or {})[texKey]

            if texPath then
                PV_FillColor(healthFill, texPath, hR, hG, hB, (not isDarkTheme) and settings.gradientEnabled, settings.gradientColor, settings.gradientDir, hA)
            end
            if pf._powerFill and powerH > 0 then
                local txR, txG, txB
                local isPwrC = settings.powerPercentPowerColor ~= false
                if isPwrC then
                    local _, pToken = UnitPowerType("player")
                    local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                    txR, txG, txB = info.r, info.g, info.b
                else
                    local cpf = settings.customPowerFillColor
                    if cpf then txR, txG, txB = cpf.r, cpf.g, cpf.b
                    else txR, txG, txB = 0, 0, 1 end
                end
                pf._pR, pf._pG, pf._pB = txR, txG, txB
                PV_FillColor(pf._powerFill, texPath, txR, txG, txB, settings.powerGradientEnabled, settings.powerGradientColor, settings.powerGradientDir, powerOpacity)
            end
        end

        -- Castbar -- always created for player (toggled in Update); conditional for others
        local castbar, castFill, castNameFS2, castIconFrame
        local shouldCreateCastbar = (unitKey == "player") or (castbarH > 0)
        local castTimeFS, castTargetFS
        if shouldCreateCastbar then
            local initCH = (unitKey == "player") and (castbarH > 0 and castbarH or 14) or castbarH
            -- Cast icon "part of the bar": when on, the bar (bg + border + fill)
            -- shrinks from the left and the icon (anchored to the bar's left edge)
            -- fills the freed space, keeping the right edge fixed -- exactly like
            -- the real cast bar. Off = icon hangs outside the left, bar full width.
            local pvCastIconW = initCH
            local pvCastIconInWidth, pvCastIconOnRight, pvCastIconOffX, pvCastIconOffY
            if unitKey == "player" then
                pvCastIconInWidth = settings.showPlayerCastIcon ~= false and settings.playerCastbarIconInWidth ~= false
                pvCastIconOnRight = settings.playerCastbarIconRight == true
                pvCastIconOffX = settings.playerCastIconOffsetX or 0
                pvCastIconOffY = settings.playerCastIconOffsetY or 0
            else
                pvCastIconInWidth = settings.showCastIcon ~= false and settings.castbarIconInWidth ~= false
                pvCastIconOnRight = settings.castbarIconRight == true
                pvCastIconOffX = settings.castIconOffsetX or 0
                pvCastIconOffY = settings.castIconOffsetY or 0
            end
            -- Boss: castbarWidth > 0 overrides the frame-matched width (0 = match frame).
            -- Display-clamped to the frame width + 120 so an extreme custom width
            -- can't spill across the options panel (pf doesn't clip children);
            -- the real frames + in-game boss preview show the true width.
            local pvCbBaseW = totalW
            if unitKey == "boss" and (settings.castbarWidth or 0) > 0 then
                pvCbBaseW = math.min(math.max(settings.castbarWidth, 30), totalW + 120)
            end
            local pvBarW = pvCastIconInWidth and math.max(1, pvCbBaseW - pvCastIconW) or pvCbBaseW
            castbar = CreateFrame("Frame", nil, pf)
            PP.Size(castbar, pvBarW, initCH)
            local cbAnchor = power or health
            local cbOffset = 0
            if showPortrait and side == "right" then
                cbOffset = portraitW / 2
            elseif showPortrait and side == "left" then
                cbOffset = -(portraitW / 2)
            end
            -- Shift the narrower bar right by half the icon width so the footprint
            -- stays centered where the full bar was (right edge unchanged).
            castbar._cbAnchor = cbAnchor
            castbar._cbOffset = cbOffset
            -- Icon-in-width shifts the narrowed bar toward the icon-free side so
            -- the footprint stays put: right by half the icon (icon on left) or
            -- left by half (icon on right).
            PP.Point(castbar, "TOP", cbAnchor, "BOTTOM", cbOffset + (pvCastIconInWidth and (pvCastIconOnRight and -(pvCastIconW / 2) or (pvCastIconW / 2)) or 0), 0)
            if castbarH > 0 then
                totalH = totalH + castbarH
            end

            -- Background matching real castbar: black 50% alpha
            local cbBg = castbar:CreateTexture(nil, "BACKGROUND")
            cbBg:SetAllPoints(castbar)
            cbBg:SetColorTexture(0, 0, 0, 0.5)
            castbar._previewBgTex = cbBg

            -- Black borders via unified PP system
            PP.CreateBorder(castbar, 0, 0, 0, 1, 1, "OVERLAY", 0)

            -- Cast fill fills the (possibly shortened) bar.
            castFill = castbar:CreateTexture(nil, "ARTWORK")
            PP.Point(castFill, "TOPLEFT", castbar, "TOPLEFT", 1, 0)
            PP.Point(castFill, "BOTTOMLEFT", castbar, "BOTTOMLEFT", 1, 1)
            PP.Width(castFill, math.max(0, pvBarW - 2) * (_previewCastFill or 0.6))
            -- Initial placeholder; real color + bar texture applied in the Update closure.
            castFill:SetColorTexture(0.114, 0.655, 0.514, 1)

            -- Cast spell name and icon -- class spell for player, generic for enemies
            local castSpellName, castSpellIcon
            if unitKey == "player" then
                castSpellName = _previewCastSpell and _previewCastSpell.name or "Spell Name"
                castSpellIcon = _previewCastSpell and _previewCastSpell.icon or 136197
            else
                castSpellName = "Spell Name"
                castSpellIcon = 136197  -- Shadow Bolt icon as generic
            end

            -- Text overlay above both castbar border (+1) and main frame border
            local cbTextOvr = CreateFrame("Frame", nil, castbar)
            cbTextOvr:SetAllPoints(castbar)
            cbTextOvr:SetFrameLevel(pf:GetFrameLevel() + 11)

            -- Three-zone layout: all zones truncate (no word wrap)
            castNameFS2 = cbTextOvr:CreateFontString(nil, "OVERLAY")
            SetPVFont(castNameFS2, PREVIEW_FONT, 11)
            castNameFS2:SetJustifyH("LEFT")
            castNameFS2:SetWordWrap(false)
            castNameFS2:SetMaxLines(1)
            castNameFS2:SetTextColor(1, 1, 1)
            castNameFS2:SetText(castSpellName)

            castTimeFS = cbTextOvr:CreateFontString(nil, "OVERLAY")
            SetPVFont(castTimeFS, PREVIEW_FONT, 11)
            castTimeFS:SetJustifyH("RIGHT")
            castTimeFS:SetWordWrap(false)
            castTimeFS:SetMaxLines(1)
            castTimeFS:SetTextColor(1, 1, 1)
            local spellCastTime = (_previewCastSpell and _previewCastSpell.castTime) or 3.0
            castTimeFS:SetText(string.format("%.1f", spellCastTime * (1 - (_previewCastFill or 0.6))))

            if unitKey ~= "player" then
                castTargetFS = cbTextOvr:CreateFontString(nil, "OVERLAY")
                SetPVFont(castTargetFS, PREVIEW_FONT, 10)
                castTargetFS:SetJustifyH("RIGHT")
                castTargetFS:SetWordWrap(false)
                castTargetFS:SetMaxLines(1)
                castTargetFS:SetText(UnitName("player") or "Player")
                local _, ct = UnitClass("player")
                local cc = ct and RAID_CLASS_COLORS and RAID_CLASS_COLORS[ct]
                if cc then
                    castTargetFS:SetTextColor(cc.r, cc.g, cc.b)
                else
                    castTargetFS:SetTextColor(1, 1, 1)
                end
            end

            -- Initial three-zone positioning
            do
                local barW = castbar:GetWidth() or totalW
                local timerW = 11 * 2.2
                castNameFS2:SetWidth(barW * 0.42)
                castNameFS2:SetPoint("LEFT", castbar, "LEFT", 5, 1)
                castTimeFS:SetWidth(timerW)
                castTimeFS:SetPoint("RIGHT", castbar, "RIGHT", -3, 0)
                if castTargetFS then
                    castTargetFS:SetWidth(barW * 0.42)
                    castTargetFS:SetPoint("RIGHT", castbar, "RIGHT", -3 - timerW, 0)
                end
            end

            -- Cast spell icon -- left side of the castbar by default (matches real addon),
            -- or the right side when "Show Icon on Right" is enabled.
            -- Uses plain frame + edge textures instead of BackdropTemplate for pixel-perfect rendering
            local iconSize = initCH
            castIconFrame = CreateFrame("Frame", nil, pf)
            PP.Size(castIconFrame, iconSize, iconSize)
            -- Icon hangs off the bar's chosen edge; when "part of the bar" is on the
            -- bar is narrower + shifted away (above), so the icon sits inside.
            if pvCastIconOnRight then
                PP.Point(castIconFrame, "TOPLEFT", castbar, "TOPRIGHT", pvCastIconOffX, pvCastIconOffY)
            else
                PP.Point(castIconFrame, "TOPRIGHT", castbar, "TOPLEFT", pvCastIconOffX, pvCastIconOffY)
            end
            -- Black background
            local iconBg = castIconFrame:CreateTexture(nil, "BACKGROUND")
            iconBg:SetAllPoints()
            iconBg:SetColorTexture(0, 0, 0, 1)
            -- 1px black border via unified PP system
            PP.CreateBorder(castIconFrame, 0, 0, 0, 1)
            local castIconTex = castIconFrame:CreateTexture(nil, "ARTWORK")
            PP.Point(castIconTex, "TOPLEFT", castIconFrame, "TOPLEFT", 1, -1)
            PP.Point(castIconTex, "BOTTOMRIGHT", castIconFrame, "BOTTOMRIGHT", -1, 1)
            castIconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            castIconTex:SetTexture(castSpellIcon)
            castIconFrame._iconTex = castIconTex

            -- Hide initially if player castbar not enabled
            if unitKey == "player" and castbarH <= 0 then
                castbar:Hide()
                castIconFrame:Hide()
            end
        end

        -- Text Bar (preview) -- mirrors real CreateBottomTextBar
        local btbFrame, btbBg, btbLeftFS, btbRightFS, btbCenterFS, btbClassIconTex
        local ApplyBTBPreviewTexts
        do
            local btbH = settings.bottomTextBarHeight or 16
            local initPos = settings.btbPosition or "bottom"
            local initIsDetached = (initPos == "detached_top" or initPos == "detached_bottom")
            local initBtbW = initIsDetached and (settings.btbWidth or 0) or 0
            local initBtbTW = (initBtbW > 0 and initIsDetached) and initBtbW or totalW
            btbFrame = CreateFrame("Frame", nil, pf)
            PP.Size(btbFrame, initBtbTW, btbH)
            local btbAnchor = (initPpIsAtt and power) and power or health
            local btbXOff = 0
            local initBtbIsAtt = (initPos == "top" or initPos == "bottom")
            if initBtbIsAtt and showPortrait and isAttachedInit then
                if side == "right" then btbXOff = portraitW / 2
                elseif side == "left" then btbXOff = -(portraitW / 2) end
            end
            if initPos == "top" then
                PP.Point(btbFrame, "BOTTOM", health, "TOP", btbXOff, 0)
            elseif initPos == "detached_top" then
                btbFrame:SetPoint("BOTTOM", health, "TOP", settings.btbX or 0, 15 + (settings.btbY or 0))
            elseif initPos == "detached_bottom" then
                btbFrame:SetPoint("TOP", btbAnchor, "BOTTOM", settings.btbX or 0, -15 + (settings.btbY or 0))
            else
                PP.Point(btbFrame, "TOP", btbAnchor, "BOTTOM", btbXOff, 0)
            end

            local bgc = settings.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
            local bga = settings.btbBgOpacity or 1.0
            btbBg = btbFrame:CreateTexture(nil, "BACKGROUND")
            btbBg:SetAllPoints()
            btbBg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)

            -- BTB borders removed: main frame border now encompasses BTB

            -- Text overlay (above border at barArea+5)
            local btbTextOvr = CreateFrame("Frame", nil, btbFrame)
            btbTextOvr:SetAllPoints()
            btbTextOvr:SetFrameLevel(barArea:GetFrameLevel() + 10)

            btbLeftFS = btbTextOvr:CreateFontString(nil, "OVERLAY")
            SetPVFont(btbLeftFS, PREVIEW_FONT, settings.btbLeftSize or 11)
            btbLeftFS:SetTextColor(1, 1, 1)
            btbLeftFS:SetWordWrap(false)

            btbRightFS = btbTextOvr:CreateFontString(nil, "OVERLAY")
            SetPVFont(btbRightFS, PREVIEW_FONT, settings.btbRightSize or 11)
            btbRightFS:SetTextColor(1, 1, 1)
            btbRightFS:SetWordWrap(false)

            btbCenterFS = btbTextOvr:CreateFontString(nil, "OVERLAY")
            SetPVFont(btbCenterFS, PREVIEW_FONT, settings.btbCenterSize or 11)
            btbCenterFS:SetTextColor(1, 1, 1)
            btbCenterFS:SetWordWrap(false)

            -- Class icon texture on BTB preview on a high-level frame so it renders above the border
            local btbClassIconHolder = CreateFrame("Frame", nil, btbFrame)
            btbClassIconHolder:SetAllPoints(btbTextOvr)
            btbClassIconHolder:SetFrameLevel(barArea:GetFrameLevel() + 12)
            btbClassIconTex = btbClassIconHolder:CreateTexture(nil, "ARTWORK")
            btbClassIconTex:SetTexCoord(0, 1, 0, 1)
            btbClassIconTex:Hide()

            -- Position BTB texts
            ApplyBTBPreviewTexts = function(s)
                local lc = s.btbLeftContent or "none"
                local rc = s.btbRightContent or "none"
                local cc = s.btbCenterContent or "none"
                local lsz = s.btbLeftSize or 11
                local rsz = s.btbRightSize or 11
                local csz = s.btbCenterSize or 11

                btbLeftFS:SetFont(PREVIEW_FONT, lsz, GetUFOptOutline())
                btbLeftFS:ClearAllPoints()
                if lc ~= "none" then
                    btbLeftFS:SetJustifyH("LEFT")
                    PP.Point(btbLeftFS, "LEFT", btbTextOvr, "LEFT", 5 + (s.btbLeftX or 0), s.btbLeftY or 0)
                    btbLeftFS:SetText(PreviewTextForContent(lc, s, "btbLeft"))
                    btbLeftFS:Show()
                    PreviewClassColor(btbLeftFS, s.btbLeftClassColor, s.btbLeftColorR, s.btbLeftColorG, s.btbLeftColorB)
                    PreviewPowerColor(btbLeftFS, lc, s.btbLeftPowerColor)
                else btbLeftFS:Hide() end

                btbRightFS:SetFont(PREVIEW_FONT, rsz, GetUFOptOutline())
                btbRightFS:ClearAllPoints()
                if rc ~= "none" then
                    btbRightFS:SetJustifyH("RIGHT")
                    PP.Point(btbRightFS, "RIGHT", btbTextOvr, "RIGHT", -5 + (s.btbRightX or 0), s.btbRightY or 0)
                    btbRightFS:SetText(PreviewTextForContent(rc, s, "btbRight"))
                    btbRightFS:Show()
                    PreviewClassColor(btbRightFS, s.btbRightClassColor, s.btbRightColorR, s.btbRightColorG, s.btbRightColorB)
                    PreviewPowerColor(btbRightFS, rc, s.btbRightPowerColor)
                else btbRightFS:Hide() end

                btbCenterFS:SetFont(PREVIEW_FONT, csz, GetUFOptOutline())
                btbCenterFS:ClearAllPoints()
                if cc ~= "none" then
                    btbCenterFS:SetJustifyH("CENTER")
                    PP.Point(btbCenterFS, "CENTER", btbTextOvr, "CENTER", s.btbCenterX or 0, s.btbCenterY or 0)
                    btbCenterFS:SetText(PreviewTextForContent(cc, s, "btbCenter"))
                    btbCenterFS:Show()
                    PreviewClassColor(btbCenterFS, s.btbCenterClassColor, s.btbCenterColorR, s.btbCenterColorG, s.btbCenterColorB)
                    PreviewPowerColor(btbCenterFS, cc, s.btbCenterPowerColor)
                else btbCenterFS:Hide() end

                -- Class icon in BTB preview
                local ciStyle = s.btbClassIcon or "none"
                if ciStyle ~= "none" then
                    local _, classToken = UnitClass("player")
                    if classToken and ApplyClassIconTexture_Preview(btbClassIconTex, classToken, ciStyle) then
                        local ciSz = s.btbClassIconSize or 14
                        PP.Size(btbClassIconTex, ciSz, ciSz)
                        btbClassIconTex:ClearAllPoints()
                        local ciLoc = s.btbClassIconLocation or "left"
                        local ciOx = s.btbClassIconX or 0
                        local ciOy = s.btbClassIconY or 0
                        if ciLoc == "center" then
                            PP.Point(btbClassIconTex, "CENTER", btbTextOvr, "CENTER", ciOx, ciOy)
                        elseif ciLoc == "right" then
                            PP.Point(btbClassIconTex, "RIGHT", btbTextOvr, "RIGHT", -3 + ciOx, ciOy)
                        else
                            PP.Point(btbClassIconTex, "LEFT", btbTextOvr, "LEFT", 3 + ciOx, ciOy)
                        end
                        btbClassIconTex:Show()
                        if pf._btbClassIconOv then pf._btbClassIconOv:Show() end
                    else
                        btbClassIconTex:Hide()
                        if pf._btbClassIconOv then pf._btbClassIconOv:Hide() end
                    end
                else
                    btbClassIconTex:Hide()
                    if pf._btbClassIconOv then pf._btbClassIconOv:Hide() end
                end
            end
            ApplyBTBPreviewTexts(settings)

            -- Show/hide based on setting
            local initBtbPos = settings.btbPosition or "bottom"
            local initBtbIsAtt = (initBtbPos == "top" or initBtbPos == "bottom")
            if not settings.bottomTextBar then
                btbFrame:Hide()
            else
                if initBtbIsAtt then totalH = totalH + btbH end
            end
        end

        -- Class Power Pips (player only preview) -- matches nameplate pip style
        local cpPipContainer, cpPips
        if unitKey == "player" then
            local CLASS_POWER_MAP = {
                ROGUE={5}, DRUID={[103]=5,[104]=5,[105]=5}, PALADIN={5}, MONK={5},
                WARLOCK={5}, MAGE={4}, EVOKER={5}, DEATHKNIGHT={6},
                DEMONHUNTER={[581]=6, [1480]=5}, SHAMAN={[263]=10}, HUNTER={[255]=3}, WARRIOR={[72]=4},
            }
            local _, playerClass = UnitClass("player")
            local cpInfo = CLASS_POWER_MAP[playerClass]
            local cpMax = 0
            if cpInfo then
                if cpInfo[1] then
                    cpMax = cpInfo[1]
                else
                    local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
                    local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec)
                    cpMax = specID and cpInfo[specID] or 0
                end
            end
            -- Resolve fill color from global system
            local cpColor = { 1.00, 0.84, 0.30 }
            if EllesmereUI.GetResourceColor then
                local rc = EllesmereUI.GetResourceColor(playerClass)
                if rc then cpColor = { rc.r, rc.g, rc.b } end
            elseif EllesmereUI.GetClassColor then
                local cc = EllesmereUI.GetClassColor(playerClass)
                if cc then cpColor = { cc.r, cc.g, cc.b } end
            end

            if cpMax > 0 then
            cpPipContainer = CreateFrame("Frame", nil, pf)
            cpPipContainer:SetFrameLevel(pf:GetFrameLevel() + 4)
            -- Background texture behind all pips
            local cpBgTex = cpPipContainer:CreateTexture(nil, "BACKGROUND")
            cpBgTex:SetAllPoints()
            local initBg = settings.classPowerBgColor or { r=0.082, g=0.082, b=0.082, a=1.0 }
            cpBgTex:SetColorTexture(initBg.r, initBg.g, initBg.b, initBg.a)
            cpPipContainer._bgTex = cpBgTex
            cpPips = {}
            for i = 1, cpMax do
                local pip = cpPipContainer:CreateTexture(nil, "OVERLAY", nil, 3)
                pip:SetColorTexture(1, 1, 1, 1)
                PP.Size(pip, 8, 3)
                cpPips[i] = pip
            end
            -- Color pips: first 3 filled, rest empty (preview)
            local previewFilled = math.min(3, cpMax)
            for i = 1, cpMax do
                if i <= previewFilled then
                    cpPips[i]:SetColorTexture(cpColor[1], cpColor[2], cpColor[3], 1)
                end
            end
            cpPipContainer:Hide()  -- shown in Update() if style ~= "none"

            -- 1px inset bottom border for "above" position (matches frame border color)
            -- Sublevel 7 so it renders over pip fill textures (sublevel 3)
            local cpBottomBdr = cpPipContainer:CreateTexture(nil, "OVERLAY", nil, 7)
            cpBottomBdr:SetHeight(1)
            PP.Point(cpBottomBdr, "BOTTOMLEFT", cpPipContainer, "BOTTOMLEFT", 0, 0)
            PP.Point(cpBottomBdr, "BOTTOMRIGHT", cpPipContainer, "BOTTOMRIGHT", 0, 0)
            local initBdrC = settings.borderColor or { r = 0, g = 0, b = 0 }
            cpBottomBdr:SetColorTexture(initBdrC.r, initBdrC.g, initBdrC.b, 1)
            cpBottomBdr:Hide()  -- shown only when position is "above"
            cpPipContainer._bottomBdr = cpBottomBdr
            end -- cpMax > 0
        end

        -- Border -- plain frame child of barArea with 4 individual edge textures.
        -- BackdropTemplate is avoided: its edgeSize clipping causes sides to vanish
        -- when the frame is small, and its internal snapping can't be disabled.
        -- Individual textures with PixelUtil sizing render reliably.
        local bdrSize = settings.borderSize or 1
        local bdrColor = settings.borderColor or { r = 0, g = 0, b = 0 }
        local bdrTexKey = settings.borderTexture or "solid"
        local border = CreateFrame("Frame", nil, pf)
        border:SetPoint("TOPLEFT", barArea, "TOPLEFT", 0, 0)
        border:SetPoint("TOPRIGHT", barArea, "TOPRIGHT", 0, 0)
        local initBdrBtbPos = settings.btbPosition or "bottom"
        local initBdrBtbAtt = (initBdrBtbPos == "top" or initBdrBtbPos == "bottom")
        border:SetHeight(settings.healthHeight + initPpExtra + (settings.bottomTextBar and initBdrBtbAtt and (settings.bottomTextBarHeight or 16) or 0))
        border:SetFrameLevel(barArea:GetFrameLevel() + 5)
        EllesmereUI.ApplyBorderStyle(border, bdrSize, bdrColor.r, bdrColor.g, bdrColor.b, settings.borderAlpha or 1, bdrTexKey, settings.borderTextureOffset, settings.borderTextureOffsetY, settings.borderTextureShiftX, settings.borderTextureShiftY, "unitframes", bdrSize)
        if bdrSize == 0 and bdrTexKey == "solid" then border:Hide() end

        -- Position an absorb-style StatusBar per its edge mode, mirroring
        -- UpdateAbsorbBarReverseFill in EllesmereUIUnitFrames.lua:
        --   overlay = fill into the missing-health area from the current-HP edge
        --             (real frames only backfill over the filled health for
        --             overshields; the preview shows the normal, non-over case)
        --   right   = pinned to the health bar's right edge, fills leftward
        --   left    = pinned to the health bar's left edge, fills rightward
        -- right/left are absolute (independent of reverse fill); overlay mirrors.
        local function PositionPreviewAbsorb(bar, mode, isRev)
            if not bar then return end
            bar:ClearAllPoints()
            if mode == "right" then
                bar:SetReverseFill(true)
                bar:SetPoint("TOPRIGHT",    health, "TOPRIGHT",    0, 0)
                bar:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            elseif mode == "left" then
                bar:SetReverseFill(false)
                bar:SetPoint("TOPLEFT",    health, "TOPLEFT",    0, 0)
                bar:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
            elseif isRev then
                -- Reverse fill: missing health sits on the LEFT, so the shield
                -- grows leftward out of the current-HP edge (health-fill's left).
                bar:SetReverseFill(true)
                bar:SetPoint("TOPRIGHT",    healthFill, "TOPLEFT",    0, 0)
                bar:SetPoint("BOTTOMRIGHT", healthFill, "BOTTOMLEFT", 0, 0)
            else
                -- Normal fill: missing health sits on the RIGHT, so the shield
                -- grows rightward out of the current-HP edge (health-fill's right).
                bar:SetReverseFill(false)
                bar:SetPoint("TOPLEFT",    healthFill, "TOPRIGHT",    0, 0)
                bar:SetPoint("BOTTOMLEFT", healthFill, "BOTTOMRIGHT", 0, 0)
            end
        end

        -- Absorb bars (style-aware preview for player, target, focus):
        --   absorbBar     = shield (damage) absorb, white/shield, drawn below
        --   healAbsorbBar = heal absorb, red, drawn one sublevel above; shown
        --                   only when the Heal Absorb Style eyeball is toggled on
        local absorbBar, healAbsorbBar, absorbTopBar, healAbsorbTopBar
        if unitKey == "player" or unitKey == "target" or unitKey == "focus" then
            local PREV_ABS_TEX = {
                striped         = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped3.tga",
                stripedReversed = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-5-reversed.png",
                clean           = "Interface\\Buttons\\WHITE8X8",
                blizzard        = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\blizzard.tga",
                largeOutlinedStripes  = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-habsorb-left.png",
                largeOutlinedStripesR = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-habsorb-right.png",
                largeStripes          = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-absorb-left.png",
                largeStripesR         = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-absorb-right.png",
            }
            -- Clip container: the shield/heal-absorb fills anchor off the
            -- health fill's current-HP edge with a full-frame width, so a
            -- high preview fill can push them past the bar's edge. Real
            -- frames clamp; mirror that by clipping both preview bars to the
            -- health bar's rect.
            local absClip = CreateFrame("Frame", nil, health)
            absClip:SetAllPoints(health)
            absClip:SetFrameLevel(health:GetFrameLevel() + 1)
            absClip:SetClipsChildren(true)

            -- Shield (damage) absorb
            local absStyle = settings.showPlayerAbsorb
            local PREV_ABS_ALPHA = { striped = 0.8, stripedReversed = 0.8, clean = (settings.absorbCleanAlpha or 30) / 100, blizzard = 0.8 }
            -- SharedMedia keys fall through to the health-bar texture lookup.
            local tex   = ns.ResolveAbsorbStyleTex(absStyle, PREV_ABS_TEX.striped)
            -- Effective opacity/color: mirrors GetAbsorbOpacity in EllesmereUIUnitFrames.lua
            local alpha = settings.absorbOpacity and (settings.absorbOpacity / 100) or PREV_ABS_ALPHA[absStyle] or 0.8
            local ac = settings.absorbColor or { r = 1, g = 1, b = 1 }
            absorbBar = CreateFrame("StatusBar", nil, absClip)
            absorbBar:SetStatusBarTexture(tex)
            local absFillTex = absorbBar:GetStatusBarTexture()
            if absFillTex then
                absFillTex:SetDrawLayer("ARTWORK", 1)
                local absTiled = (absStyle == "stripedReversed" or absStyle == "largeStripes" or absStyle == "largeStripesR" or absStyle == "largeOutlinedStripes" or absStyle == "largeOutlinedStripesR")
                absFillTex:SetHorizTile(absTiled); absFillTex:SetVertTile(absTiled)
            end
            absorbBar:SetStatusBarColor(ac.r, ac.g, ac.b, alpha)
            PositionPreviewAbsorb(absorbBar, settings.absorbEdgeMode or "overlay", settings.healthReverseFill)
            PP.Width(absorbBar, frameW)
            PP.Height(absorbBar, healthH)
            absorbBar:SetMinMaxValues(0, 1)
            absorbBar:SetValue(0.14)
            absorbBar:SetFrameLevel(health:GetFrameLevel() + 1)
            if not absStyle or absStyle == "none" then absorbBar:Hide() end

            -- Heal absorb (red, draws one sublevel above the shield absorb).
            -- Mutually exclusive with the shield absorb on the preview: only
            -- visible while the eyeball is on, at which point absorbBar hides.
            local haStyle = settings.healAbsorbStyle or "clean"
            local haTex   = ns.ResolveAbsorbStyleTex(haStyle, "Interface\\Buttons\\WHITE8X8")
            local haAlpha = ((settings.healAbsorbOpacity) or 65) / 100
            local hc = settings.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
            if haStyle == "largeOutlinedStripes" or haStyle == "largeOutlinedStripesR" then hc = { r = 1, g = 1, b = 1 } end
            healAbsorbBar = CreateFrame("StatusBar", nil, absClip)
            healAbsorbBar:SetStatusBarTexture(haTex)
            local haFillTex = healAbsorbBar:GetStatusBarTexture()
            if haFillTex then
                haFillTex:SetDrawLayer("ARTWORK", 2)
                local haTiled = (haStyle == "stripedReversed" or haStyle == "largeStripes" or haStyle == "largeStripesR" or haStyle == "largeOutlinedStripes" or haStyle == "largeOutlinedStripesR")
                haFillTex:SetHorizTile(haTiled); haFillTex:SetVertTile(haTiled)
            end
            healAbsorbBar:SetStatusBarColor(hc.r, hc.g, hc.b, haAlpha)
            PositionPreviewAbsorb(healAbsorbBar, settings.healAbsorbEdgeMode or "overlay", settings.healthReverseFill)
            PP.Width(healAbsorbBar, frameW)
            PP.Height(healAbsorbBar, healthH)
            healAbsorbBar:SetMinMaxValues(0, 1)
            healAbsorbBar:SetValue(0.14)
            healAbsorbBar:SetFrameLevel(health:GetFrameLevel() + 1)
            healAbsorbBar:Hide()
            -- Black backing behind the heal-absorb fill (opacity via healAbsorbBgOpacity),
            -- drawn one sublevel under the fill and tracking its rect.
            local haBgPv = healAbsorbBar:CreateTexture(nil, "ARTWORK", nil, 1)
            haBgPv:SetColorTexture(0, 0, 0, ((settings.healAbsorbBgOpacity) or 15) / 100)
            haBgPv:SetAllPoints(healAbsorbBar:GetStatusBarTexture())
            healAbsorbBar._bg = haBgPv

            -- Absorb Bar / Heal Absorb Bar preview strips (parented to the frame
            -- so "above" positions sit outside the health bar). Driven below.
            absorbTopBar = CreateFrame("StatusBar", nil, pf)
            absorbTopBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            absorbTopBar:SetMinMaxValues(0, 1)
            absorbTopBar:SetValue(0.45)
            absorbTopBar:Hide()
            healAbsorbTopBar = CreateFrame("StatusBar", nil, pf)
            healAbsorbTopBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            healAbsorbTopBar:SetMinMaxValues(0, 1)
            healAbsorbTopBar:SetValue(0.45)
            healAbsorbTopBar:Hide()
        end
        pf._absorbBar = absorbBar
        pf._healAbsorbBar = healAbsorbBar
        pf._absorbTopBar = absorbTopBar
        pf._healAbsorbTopBar = healAbsorbTopBar

        -- Fake buff icons (all units, shown when showBuffs is on and anchor is not "none")
        local buffIcons = {}
        do
            local buffSize = settings.buffSize or 22
            local buffGap = 1
            for i = 1, 2 do
                local bf = CreateFrame("Frame", nil, pf, "BackdropTemplate")
                PP.Size(bf, buffSize, buffSize)
                bf:SetBackdrop(SOLID_BACKDROP)
                bf:SetBackdropColor(0, 0, 0, 1)
                -- Above the preview border so it renders BEHIND the buff icons.
                -- The border frame is barArea+5 and its solid PP border textures
                -- sit on a sub-container at barArea+6, so clear barArea+6.
                bf:SetFrameLevel(barArea:GetFrameLevel() + 7)
                PP.Point(bf, "BOTTOMLEFT", pf, "TOPLEFT", (i - 1) * (buffSize + buffGap), buffGap)
                local tex = bf:CreateTexture(nil, "ARTWORK")
                PP.Point(tex, "TOPLEFT", bf, "TOPLEFT", 1, -1)
                PP.Point(tex, "BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1, 1)
                tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                tex:SetTexture(_previewBuffIcons[i] or 135932)
                bf._iconTex = tex
                buffIcons[i] = bf
                local showB = settings.showBuffs and (settings.buffAnchor or "topleft") ~= "none"
                if not showB then bf:Hide() end
            end
        end

        -- Fake debuff icons (all units, shown when debuffAnchor is not "none")
        local debuffIcons = {}
        do
            local debuffSize = settings.debuffSize or 22
            local debuffGap = 1
            local previewDebuffIcons = {
                136116, 132099, 136182, 136214, 132155,
                136201, 136148, 136175, 136130, 136160,
                136195, 136133, 136222, 136168, 136205,
                136186, 136124, 136151, 136210, 136143,
            }
            for i = 1, 20 do
                local df = CreateFrame("Frame", nil, pf, "BackdropTemplate")
                PP.Size(df, debuffSize, debuffSize)
                df:SetBackdrop(SOLID_BACKDROP)
                -- Black 1px edge (backdrop fill showing through the icon's 1px
                -- inset) to match the buff icons and the live frames' black border.
                df:SetBackdropColor(0, 0, 0, 1)
                -- Above the preview border so it renders BEHIND the debuff icons.
                -- Border frame is barArea+5, its solid PP container barArea+6, so
                -- clear barArea+6; df's cd (+1) and text host (+2) ride up too.
                df:SetFrameLevel(barArea:GetFrameLevel() + 7)
                PP.Point(df, "TOPLEFT", pf, "BOTTOMLEFT", (i - 1) * (debuffSize + debuffGap), -debuffGap)
                local tex = df:CreateTexture(nil, "ARTWORK")
                PP.Point(tex, "TOPLEFT", df, "TOPLEFT", 1, -1)
                PP.Point(tex, "BOTTOMRIGHT", df, "BOTTOMRIGHT", -1, 1)
                tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                tex:SetTexture(previewDebuffIcons[i] or 136116)
                df._iconTex = tex
                -- Static fake cooldown swipe (huge duration parked at a fixed
                -- fraction so the wedge never visibly moves) plus manual static
                -- duration / stack text. Shown only on the boss preview in
                -- pf:Update; sizing/visibility follow the boss aura settings.
                local cd = CreateFrame("Cooldown", nil, df, "CooldownFrameTemplate")
                cd:SetPoint("TOPLEFT", df, "TOPLEFT", 1, -1)
                cd:SetPoint("BOTTOMRIGHT", df, "BOTTOMRIGHT", -1, 1)
                cd:SetFrameLevel(df:GetFrameLevel() + 1)
                cd:SetDrawEdge(false)
                cd:SetDrawBling(false)
                cd:SetReverse(false)
                cd:SetDrawSwipe(true)
                cd:SetSwipeColor(0, 0, 0, 0.6)
                cd:SetHideCountdownNumbers(true)
                local frac = 0.25 + (((i - 1) % 5) * 0.15)
                cd:SetCooldown(GetTime() - 3600 * (1 - frac), 3600)
                cd:Hide()
                df._previewCD = cd
                local textHost = CreateFrame("Frame", nil, df)
                textHost:SetAllPoints(df)
                textHost:SetFrameLevel(cd:GetFrameLevel() + 1)
                local pvFontP = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF"
                local durText = textHost:CreateFontString(nil, "OVERLAY", nil, 7)
                EllesmereUI.ApplyIconTextFont(durText, pvFontP, 10, "unitFrames")
                durText:SetPoint("CENTER", df, "CENTER", 0, 0)
                durText:SetText(4 + ((i - 1) % 5) * 5)
                durText:Hide()
                df._durText = durText
                local stackText = textHost:CreateFontString(nil, "OVERLAY", nil, 7)
                EllesmereUI.ApplyIconTextFont(stackText, pvFontP, 14, "unitFrames")
                stackText:SetText(2 + ((i - 1) % 5))
                stackText:Hide()
                df._stackText = stackText
                debuffIcons[i] = df
                if noDebuffPreview or (settings.debuffAnchor or "bottomleft") == "none" then df:Hide() end
            end
        end

        -- Disabled overlay -- must render above ALL other child frames
        -- Parent to UIParent so strata isn't clamped by pf's strata
        local disabledOverlay = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        disabledOverlay:SetFrameStrata("FULLSCREEN_DIALOG")
        disabledOverlay:SetBackdrop(SOLID_BACKDROP)
        disabledOverlay:SetBackdropColor(0, 0, 0, 0.6)
        disabledOverlay:Hide()
        local disabledText = disabledOverlay:CreateFontString(nil, "OVERLAY")
        SetPVFont(disabledText, PREVIEW_FONT, 11)
        disabledText:SetTextColor(1, 1, 1)
        disabledText:SetText(EllesmereUI.L("Disabled"))
        -- Position overlay and text relative to pf/health (updated in Update and on show)
        local function SyncDisabledOverlay()
            disabledOverlay:ClearAllPoints()
            disabledOverlay:SetScale(pf:GetScale())
            disabledOverlay:SetPoint("TOPLEFT", pf, "TOPLEFT", 0, 0)
            disabledOverlay:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", 0, 0)
            disabledText:ClearAllPoints()
            disabledText:SetPoint("CENTER", disabledOverlay, "CENTER", 0, 0)
        end
        SyncDisabledOverlay()

        -- Auto-hide the UIParent-parented overlay when the preview is hidden
        -- (tab switch, module switch, or page cache stash)
        pf:HookScript("OnHide", function() disabledOverlay:Hide() end)

        -- Combat indicator preview texture (highest frame level)
        local COMBAT_MEDIA_P = "Interface\\AddOns\\EllesmereUI\\media\\combat\\"
        local combatIndHolder = CreateFrame("Frame", nil, pf)
        combatIndHolder:SetAllPoints(pf)
        combatIndHolder:SetFrameLevel(pf:GetFrameLevel() + 20)
        local combatInd = combatIndHolder:CreateTexture(nil, "OVERLAY", nil, 7)
        combatInd:SetSize(24, 24)
        combatInd:SetPoint("CENTER", portraitFrame or health, "CENTER", 0, 0)
        combatInd:Hide()
        pf._combatIndicator = combatInd
        pf:SetSize(totalW, totalH)

        -- Update method
        function pf:Update()
            -- Skip update when preview is stashed (hidden during tab switch).
            -- Updating a stashed preview re-anchors it to _chStash via GetParent(),
            -- which breaks its position when later restored from cache.
            if not pf:IsShown() then
                -- Hide UIParent-parented disabled overlay while stashed
                if disabledOverlay then disabledOverlay:Hide() end
                return
            end
            local s
            if unitKey == "player" then s = db.profile.player
            elseif unitKey == "target" then s = db.profile.target
            elseif unitKey == "focus" then s = db.profile.focus
            elseif unitKey == "pet" then s = db.profile.pet
            elseif unitKey == "boss" then s = db.profile.boss
            elseif unitKey == "targettarget" then s = db.profile.targettarget
            elseif unitKey == "focustarget" then s = db.profile.focustarget
            else s = db.profile.player end

            -- Player/target preview: mirror the live shared aura border style.
            if unitKey == "player" or unitKey == "target" or unitKey == "boss" then
                local function ApplyPreviewAuraBorder(icon)
                    if icon._iconTex then
                        icon._iconTex:ClearAllPoints()
                        local inset = (s.auraBorderSize or 1) > 0 and 1 or 0
                        PP.Point(icon._iconTex, "TOPLEFT", icon, "TOPLEFT", inset, -inset)
                        PP.Point(icon._iconTex, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset, inset)
                    end
                    local border = icon._euiAuraBorder
                    if not border then
                        border = CreateFrame("Frame", nil, icon)
                        border:SetAllPoints(icon)
                        border:EnableMouse(false)
                        icon._euiAuraBorder = border
                    end
                    if s.auraBorderBehindUnitFrame then
                        border:SetFrameLevel(0)
                    else
                        border:SetFrameLevel(s.auraBorderBehind
                            and math.max(0, icon:GetFrameLevel() - 1) or (icon:GetFrameLevel() + 1))
                    end
                    EllesmereUI.ApplyBorderStyle(border, s.auraBorderSize or 1,
                        s.auraBorderR or 0, s.auraBorderG or 0, s.auraBorderB or 0, s.auraBorderA or 1,
                        s.auraBorderTexture or "solid",
                        s.auraBorderTextureOffset, s.auraBorderTextureOffsetY,
                        s.auraBorderTextureShiftX, s.auraBorderTextureShiftY,
                        "unitframes", s.auraBorderSize or 1)
                end
                for i = 1, #buffIcons do ApplyPreviewAuraBorder(buffIcons[i]) end
                for i = 1, #debuffIcons do ApplyPreviewAuraBorder(debuffIcons[i]) end
            end

            -- Donor settings for mini frames (border/texture/font inherit from focus player)
            local isMini = (unitKey == "pet" or unitKey == "boss" or unitKey == "targettarget" or unitKey == "focustarget")
            local ds = s
            if isMini then
                local ef = db.profile.enabledFrames
                if ef.focus ~= false and db.profile.focus then ds = db.profile.focus
                elseif ef.target ~= false and db.profile.target then ds = db.profile.target
                else ds = db.profile.player end
            end

            -- Enabled/disabled overlay: the preview mocks the EllesmereUI frame,
            -- so it is only "enabled" when the unit's source is the EUI frame.
            local unitKey2 = unitKey:match("^boss") and "boss" or unitKey
            local isEnabled = ns.GetUnitFrameSource(unitKey2) == "eui"
            if isEnabled then
                disabledOverlay:Hide()
                pf:SetAlpha(1)
            else
                pf:SetAlpha(0.5)
            end

            -- (text content updated by ApplyPreviewTextPositions)

            -- Reposition name and health text based on settings
            side = s.portraitSide or unitSide[unitKey] or "left"
            local pvPStyle = s.portraitStyle or db.profile.portraitStyle or "attached"
            local sp = hasPortraitSupport
                   and pvPStyle ~= "none"
                   and s.showPortrait ~= false
            local isAttached = pvPStyle == "attached"
            local fw = s.frameWidth or 181
            local hh = s.healthHeight or 46
            local ph = noPowerPreview and 0 or (s.powerHeight or 6)
            local pvPpPos = noPowerPreview and "none" or (s.powerPosition or "below")
            local pvPpIsAtt = (pvPpPos == "below" or pvPpPos == "above")
            local pvPpExtra = pvPpIsAtt and ph or 0
            local ch = (unitKey == "player") and (s.showPlayerCastbar and (s.playerCastbarHeight and s.playerCastbarHeight > 0 and s.playerCastbarHeight or 14) or 0) or ((s.showCastbar ~= false) and (s.castbarHeight or 14) or 0)
            local bh = hh + pvPpExtra
            -- Class power "above" position adds height above health bar ("top" floats outside)
            local cpStyle = (unitKey == "player") and (s.classPowerStyle or "none") or "none"
            local cpPos = (cpStyle == "modern") and (s.classPowerPosition or "top") or "none"
            local cpAboveH = 0
            if cpStyle == "modern" and cpPos == "above" and cpPips then
                local cpSizeAdj = s.classPowerSize or 8
                local cpPipH = math.max(3, math.floor(cpSizeAdj * 0.375))
                cpAboveH = cpPipH
            end
            local bh2 = bh + cpAboveH  -- total bar area height including above pips
            -- Compute floating pip heights for "top" and "bottom" positions
            -- These float outside the frame and need to be accounted for in the
            -- overall content header height so they push content above/below.
            local cpTopH = 0
            local cpBottomH = 0
            if cpStyle == "modern" and (cpPos == "top" or cpPos == "bottom") then
                local cpSizeAdj = s.classPowerSize or 8
                local cpPipH = math.max(3, math.floor(cpSizeAdj * 0.375))
                local cpYOff = s.classPowerBarY or 0
                if cpPos == "top" then
                    cpTopH = cpPipH + cpYOff
                else
                    cpBottomH = cpPipH
                end
            end
            -- Portrait size/offset from DB
            local pSizeAdj = sp and (s.portraitSize or 0) or 0
            local pXOff = sp and (s.portraitX or 0) or 0
            local pYOff = sp and (s.portraitY or 0) or 0
            local pvIsInside = (side == "insideleft" or side == "insideright" or side == "insidecenter")
            if not isAttached and not pvIsInside then pSizeAdj = pSizeAdj + 10; pYOff = pYOff + 5 end
            local portraitDim = bh2 + pSizeAdj  -- portrait width & height
            if portraitDim < 8 then portraitDim = 8 end
            -- For attached, "top" and "inside*" fall back to default side
            local effectiveSide = side
            if isAttached and (side == "top" or pvIsInside) then
                effectiveSide = unitSide[unitKey] or "left"
                pvIsInside = false
            end
            local pw = (sp and isAttached and effectiveSide ~= "top") and portraitDim or 0
            local tw = fw + pw

            -- Resize and reposition health bar
            PP.Size(health, fw, hh)

            -- Re-anchor portrait and health every update (no caching)
            -- to avoid circular dependency errors on style switches.
            -- Order matters: clear BOTH first, then anchor in dependency order.
            if portraitFrame then portraitFrame:ClearAllPoints() end
            health:ClearAllPoints()
            local btbTopOff = (s.bottomTextBar and (s.btbPosition or "bottom") == "top") and (s.bottomTextBarHeight or 16) or 0
            local pvPwAbove = (pvPpPos == "above") and ph or 0

            if portraitFrame and sp then
                if pvIsInside then
                    PP.Size(portraitFrame, portraitDim, bh2)
                else
                    PP.Size(portraitFrame, portraitDim, portraitDim)
                end
                if pvIsInside then
                    -- Inside: portrait overlays the health bar
                    PP.Point(health, "TOPLEFT", barArea, "TOPLEFT", 0, -cpAboveH - btbTopOff - pvPwAbove)
                    portraitFrame:SetClipsChildren(true)
                    if portraitFrame._previewBg then portraitFrame._previewBg:Hide() end
                    if effectiveSide == "insideleft" then
                        portraitFrame:SetPoint("TOPLEFT", health, "TOPLEFT", pXOff, pYOff)
                    elseif effectiveSide == "insideright" then
                        portraitFrame:SetPoint("TOPRIGHT", health, "TOPRIGHT", pXOff, pYOff)
                    else -- insidecenter
                        portraitFrame:SetPoint("TOP", health, "TOP", pXOff, pYOff)
                    end
                elseif isAttached then
                    -- Attached: portrait to barArea, then health to portrait
                    portraitFrame:SetClipsChildren(true)
                    if portraitFrame._previewBg then portraitFrame._previewBg:Show() end
                    if effectiveSide == "left" then
                        portraitFrame:SetPoint("TOPLEFT", barArea, "TOPLEFT", 0, 0)
                        PP.Point(health, "TOPLEFT", portraitFrame, "TOPRIGHT", 0, -cpAboveH - btbTopOff - pvPwAbove)
                    else
                        portraitFrame:SetPoint("TOPRIGHT", barArea, "TOPRIGHT", 0, 0)
                        PP.Point(health, "TOPRIGHT", portraitFrame, "TOPLEFT", 0, -cpAboveH - btbTopOff - pvPwAbove)
                    end
                else
                    -- Detached: health to barArea, then portrait floats
                    if portraitFrame._previewBg then portraitFrame._previewBg:Show() end
                    PP.Point(health, "TOPLEFT", barArea, "TOPLEFT", 0, -cpAboveH - btbTopOff - pvPwAbove)
                    if effectiveSide == "top" then
                        -- Top: portrait centered above health bar
                        portraitFrame:SetPoint("BOTTOM", health, "TOP", pXOff, 15 + pYOff)
                    elseif effectiveSide == "left" then
                        portraitFrame:SetPoint("TOPRIGHT", health, "TOPLEFT", -15 + pXOff, pYOff)
                    else
                        portraitFrame:SetPoint("TOPLEFT", health, "TOPRIGHT", 15 + pXOff, pYOff)
                    end
                end
                portraitFrame._anchored = true
                portraitFrame._anchoredAttached = isAttached
                -- Raise detached portrait above border in preview (capped to avoid
                -- overlapping dropdown menus and other UI controls)
                if isAttached then
                    portraitFrame:SetFrameLevel(pf:GetFrameLevel() + 1)
                else
                    portraitFrame:SetFrameLevel(pf:GetFrameLevel() + 3)
                end
            else
                PP.Point(health, "TOPLEFT", barArea, "TOPLEFT", 0, -cpAboveH - btbTopOff - pvPwAbove)
                if portraitFrame then portraitFrame._anchored = false end
            end
            healthFill:ClearAllPoints()
            if s.healthReverseFill then
                healthFill:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, 0)
                healthFill:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            else
                healthFill:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
                healthFill:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
            end
            PP.Width(healthFill, math.floor(fw * (_previewHealthPct or 0.70) + 0.5))

            -- Live-update dark mode colors
            do
                local isDark = db.profile.darkTheme
                local uHR, uHG, uHB, uBgR, uBgG, uBgB
                if isDark then
                    uHR, uHG, uHB = EllesmereUI.GetDarkModeFill()
                    uBgR, uBgG, uBgB = EllesmereUI.GetDarkModeBg()
                else
                    -- Check for custom fill color (skipped when class colored is enabled).
                    -- Boss preview always renders as hostile-red since the real
                    -- boss frame never class-colors (no player class).
                    local cFill = s.customFillColor
                    local isCC = s.healthClassColored and unitKey ~= "boss"
                    if isCC then
                        local _, ct = UnitClass("player")
                        local cc = RAID_CLASS_COLORS[ct]
                        if cc then uHR, uHG, uHB = cc.r, cc.g, cc.b
                        else uHR, uHG, uHB = 37/255, 193/255, 29/255 end
                    elseif cFill then
                        uHR, uHG, uHB = cFill.r, cFill.g, cFill.b
                    elseif unitKey == "player" then
                        local _, ct = UnitClass("player")
                        local cc = RAID_CLASS_COLORS[ct]
                        if cc then uHR, uHG, uHB = cc.r, cc.g, cc.b
                        else uHR, uHG, uHB = 37/255, 193/255, 29/255 end
                    elseif unitKey == "pet" then
                        uHR, uHG, uHB = 37/255, 193/255, 29/255
                    else
                        uHR, uHG, uHB = 0.8, 0.2, 0.2
                    end
                    -- Class-colored background (designer shows the player's class), else custom.
                    local uBgClassCC
                    if s.bgClassColored then
                        local _, ct = UnitClass("player")
                        uBgClassCC = ct and EllesmereUI.GetClassColor(ct)
                    end
                    if uBgClassCC then
                        uBgR, uBgG, uBgB = uBgClassCC.r, uBgClassCC.g, uBgClassCC.b
                    else
                        local cBg = s.customBgColor
                        if cBg then
                            uBgR, uBgG, uBgB = cBg.r, cBg.g, cBg.b
                        else
                            uBgR, uBgG, uBgB = 17/255, 17/255, 17/255
                        end
                    end
                end
                healthFill:SetColorTexture(uHR, uHG, uHB, 1)
                -- Background covers only the empty (missing-health) portion in
                -- both light and dark mode, so a reduced fill opacity reveals the
                -- backdrop, not the bg color. Mirrors the live frame edge-anchor.
                healthBgColor:ClearAllPoints()
                do
                    local hpW = math.floor(fw * (_previewHealthPct or 0.70) + 0.5)
                    if s.healthReverseFill then
                        healthBgColor:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
                        healthBgColor:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -hpW, 0)
                    else
                        healthBgColor:SetPoint("TOPLEFT", health, "TOPLEFT", hpW, 0)
                        healthBgColor:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
                    end
                end
                healthBgColor:SetColorTexture(uBgR, uBgG, uBgB, 1)
                -- Update bar texture on fill textures (mini frames resolve the
                -- donor texture unless they set their own override).
                do
                    local curTexKey = ns.ResolveHealthBarTextureKey(s, isMini and ds or nil)
                    local curTexPath = (ns.healthBarTextures or {})[curTexKey]
                    if healthFill then
                        local hGA = s.healthBarOpacity or 90
                        if hGA > 1.0 then hGA = hGA / 100 end
                        PV_FillColor(healthFill, curTexPath, uHR, uHG, uHB, (not isDark) and s.gradientEnabled, s.gradientColor, s.gradientDir, hGA)
                    end
                    if pf._powerFill then
                        local pvFR, pvFG, pvFB
                        local isPwrC2 = s.powerPercentPowerColor ~= false
                        if isPwrC2 then
                            local _, pToken = UnitPowerType("player")
                            local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                            pvFR, pvFG, pvFB = info.r, info.g, info.b
                        else
                            local cpf2 = s.customPowerFillColor
                            if cpf2 then pvFR, pvFG, pvFB = cpf2.r, cpf2.g, cpf2.b
                            else pvFR, pvFG, pvFB = 0, 0, 1 end
                        end
                        pf._pR, pf._pG, pf._pB = pvFR, pvFG, pvFB
                        if curTexPath then
                            pf._powerFill:SetTexture(curTexPath)
                            pf._powerFill:SetVertexColor(pvFR, pvFG, pvFB, 1)
                        else
                            pf._powerFill:SetVertexColor(1, 1, 1, 1)
                            pf._powerFill:SetColorTexture(pvFR, pvFG, pvFB, 1)
                        end
                    end
                end

                -- Apply health bar alpha from unified opacity setting
                local hFillA, hBgA
                if isDark then
                    hFillA = 0.90
                    hBgA   = 1
                else
                    local barOp = (s.healthBarOpacity or 90) / 100
                    hFillA = barOp
                    hBgA   = (s.customBgAlpha or 100) / 100
                end
                if healthFill then healthFill:SetAlpha(hFillA) end
                if healthBgColor then healthBgColor:SetAlpha(hBgA) end
            end

            -- Update text via unified function
            ApplyPreviewTextPositions(s, isMini and ds or nil)

            -- Resize barArea to health+power area (+ above pips if active)
            PP.Size(barArea, tw, bh2 + btbTopOff)

            if power then
                local pvPw = fw
                local pvPpIsDet = (pvPpPos == "detached_top" or pvPpPos == "detached_bottom")
                if pvPpIsDet and (s.powerWidth or 0) > 0 then
                    pvPw = s.powerWidth
                end
                PP.Size(power, pvPw, ph)
                if pvPpIsDet and db.profile.enableCustomBarStratas then
                    power:SetFrameLevel(pf:GetFrameLevel() + 40)
                elseif pvPpIsDet then
                    power:SetFrameLevel(pf:GetFrameLevel() + 3)
                end
                power:ClearAllPoints()
                if pvPpPos == "none" then
                    power:Hide()
                elseif pvPpPos == "above" then
                    PP.Point(power, "BOTTOMLEFT", health, "TOPLEFT", 0, 0)
                    PP.Point(power, "BOTTOMRIGHT", health, "TOPRIGHT", 0, 0)
                    if ph > 0 then power:Show() else power:Hide() end
                elseif pvPpPos == "detached_top" then
                    power:SetPoint("BOTTOM", health, "TOP", s.powerX or 0, 15 + (s.powerY or 0))
                    if ph > 0 then power:Show() else power:Hide() end
                elseif pvPpPos == "detached_bottom" then
                    power:SetPoint("TOP", health, "BOTTOM", s.powerX or 0, -15 + (s.powerY or 0))
                    if ph > 0 then power:Show() else power:Hide() end
                else -- "below"
                    PP.Point(power, "TOPLEFT", health, "BOTTOMLEFT", 0, 0)
                    PP.Point(power, "TOPRIGHT", health, "BOTTOMRIGHT", 0, 0)
                    if ph > 0 then power:Show() else power:Hide() end
                end
                -- Match the live frame: attached bars get only the Solid seam
                -- facing health; detached bars retain their selected full style.
                if ns.UpdatePowerBorder then ns.UpdatePowerBorder(power, s) end
                if pf._powerFill then
                    pf._powerFill:ClearAllPoints()
                    if s.powerReverseFill then
                        pf._powerFill:SetPoint("TOPRIGHT", power, "TOPRIGHT", 0, 0)
                        pf._powerFill:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
                    else
                        pf._powerFill:SetPoint("TOPLEFT", power, "TOPLEFT", 0, 0)
                        pf._powerFill:SetPoint("BOTTOMLEFT", power, "BOTTOMLEFT", 0, 0)
                    end
                    PP.Width(pf._powerFill, math.floor(pvPw * (_previewPowerPct or 0.85) + 0.5))
                end

                -- Apply power bar opacity from unified setting. The fill's region alpha
                -- is set AFTER PV_FillColor below (the texture/vertex call would otherwise
                -- leave it at full opacity) -- mirrors ApplyPowerBarAlpha on the real frame.
                local pOpacity = (s.powerBarOpacity or 100) / 100
                if pf._powerBg then pf._powerBg:SetAlpha((s.customPowerBgAlpha or 100) / 100) end
                -- Fill Opacity below 100: bg covers only the empty portion so
                -- the preview mirrors the live world-show-through; restore the
                -- full-size anchors when back at 100.
                if pf._powerBg and pf._powerFill then
                    if pOpacity < 1 then
                        pf._powerBgOpAnchored = true
                        pf._powerBg:ClearAllPoints()
                        if s.powerReverseFill then
                            pf._powerBg:SetPoint("TOPLEFT", power, "TOPLEFT", 0, 0)
                            pf._powerBg:SetPoint("BOTTOMRIGHT", pf._powerFill, "BOTTOMLEFT", 0, 0)
                        else
                            pf._powerBg:SetPoint("TOPLEFT", pf._powerFill, "TOPRIGHT", 0, 0)
                            pf._powerBg:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
                        end
                    elseif pf._powerBgOpAnchored then
                        pf._powerBgOpAnchored = nil
                        pf._powerBg:ClearAllPoints()
                        pf._powerBg:SetAllPoints(power)
                    end
                end

                -- Apply power bar colors
                local pvPfR, pvPfG, pvPfB
                local pvUsePowerColor = s.powerPercentPowerColor ~= false
                if pvUsePowerColor then
                    local _, pToken = UnitPowerType("player")
                    local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                    pvPfR, pvPfG, pvPfB = info.r, info.g, info.b
                else
                    local cpFill = s.customPowerFillColor
                    if cpFill then pvPfR, pvPfG, pvPfB = cpFill.r, cpFill.g, cpFill.b
                    else pvPfR, pvPfG, pvPfB = 0, 0, 1 end
                end
                local pvPbR, pvPbG, pvPbB
                local cpBg = s.customPowerBgColor
                if s.powerBgPowerColored then
                    local _, pbToken = UnitPowerType("player")
                    local pbInfo = EllesmereUI.GetPowerColor(pbToken or "MANA")
                    local pbF = EllesmereUI.GetPowerBgDarkenFactor()
                    pvPbR, pvPbG, pvPbB = pbInfo.r * pbF, pbInfo.g * pbF, pbInfo.b * pbF
                elseif cpBg then pvPbR, pvPbG, pvPbB = cpBg.r, cpBg.g, cpBg.b
                else pvPbR, pvPbG, pvPbB = 17/255, 17/255, 17/255 end
                if pf._powerFill then
                    local curTK = s.healthBarTexture or db.profile.healthBarTexture or "none"
                    local curTP = (ns.healthBarTextures or {})[curTK]
                    PV_FillColor(pf._powerFill, curTP, pvPfR, pvPfG, pvPfB, s.powerGradientEnabled, s.powerGradientColor, s.powerGradientDir, pOpacity)
                    -- Region alpha last (a gradient bakes opacity into its endpoints, so
                    -- keep it at 1 then to avoid double-dimming) -- matches the real frame.
                    pf._powerFill:SetAlpha(s.powerGradientEnabled and 1 or pOpacity)
                end
                if pf._powerBg then pf._powerBg:SetColorTexture(pvPbR, pvPbG, pvPbB, 1) end
            end

            -- Power percent text in preview
            if ppPreviewFS then
                local ppPos = s.powerPercentText or "none"
                local ppFmt = s.powerTextFormat or "perpp"
                if ppPos ~= "none" and ppFmt ~= "none" and power then
                    local ppSz = s.powerPercentSize or 9
                    local ppOx = s.powerPercentX or 0
                    local ppOy = s.powerPercentY or 0
                    ppPreviewFS:SetFont(PREVIEW_FONT, ppSz, GetUFOptOutline())
                    ppPreviewFS:ClearAllPoints()
                    if ph > 0 then
                        if ppPos == "left" then
                            ppPreviewFS:SetJustifyH("LEFT")
                            PP.Point(ppPreviewFS, "LEFT", power, "LEFT", 2 + ppOx, ppOy)
                        elseif ppPos == "right" then
                            ppPreviewFS:SetJustifyH("RIGHT")
                            PP.Point(ppPreviewFS, "RIGHT", power, "RIGHT", -2 + ppOx, ppOy)
                        else
                            ppPreviewFS:SetJustifyH("CENTER")
                            PP.Point(ppPreviewFS, "CENTER", power, "CENTER", ppOx, ppOy)
                        end
                    else
                        -- Power Bar Height 0: the power bar collapses to a zero-height
                        -- frame whose rect won't resolve, so anchor the text to the
                        -- HEALTH bar in the power row instead -- mirrors the real frame.
                        local above = (pvPpPos == "above" or pvPpPos == "detached_top")
                        local hEdge = above and "TOP" or "BOTTOM"   -- health edge to meet
                        local fEdge = above and "BOTTOM" or "TOP"   -- text edge that meets it
                        if ppPos == "left" then
                            ppPreviewFS:SetJustifyH("LEFT")
                            PP.Point(ppPreviewFS, fEdge .. "LEFT", health, hEdge .. "LEFT", 2 + ppOx, ppOy)
                        elseif ppPos == "right" then
                            ppPreviewFS:SetJustifyH("RIGHT")
                            PP.Point(ppPreviewFS, fEdge .. "RIGHT", health, hEdge .. "RIGHT", -2 + ppOx, ppOy)
                        else
                            ppPreviewFS:SetJustifyH("CENTER")
                            PP.Point(ppPreviewFS, fEdge, health, hEdge, ppOx, ppOy)
                        end
                    end
                    local ppPctVal = _previewPowerPct or 0.85
                    local ppPctRaw = math.floor(ppPctVal * 100)
                    local ppSuffix = (s.powerShowPercent == false) and "" or "%"
                    local ppCurFake = "18.2k"
                    local ppTxt
                    if ppFmt == "smart" then
                        ppTxt = ppPctRaw .. ppSuffix  -- preview always shows percent for smart
                    elseif ppFmt == "curpp" then
                        ppTxt = ppCurFake
                    elseif ppFmt == "both" then
                        ppTxt = ppCurFake .. " | " .. ppPctRaw .. ppSuffix
                    else  -- "perpp"
                        ppTxt = ppPctRaw .. ppSuffix
                    end
                    ppPreviewFS:SetText(ppTxt)
                    if s.powerPercentTextPowerColor then
                        -- EUI global power color (player's current power), matching
                        -- the swatch and the real frame -- not hardcoded blue.
                        local _, pToken = UnitPowerType("player")
                        local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                        if info then ppPreviewFS:SetTextColor(info.r, info.g, info.b)
                        else ppPreviewFS:SetTextColor(1, 1, 1) end
                    else
                        local ptc = s.powerTextColor
                        if ptc then
                            ppPreviewFS:SetTextColor(ptc.r, ptc.g, ptc.b)
                        else
                            ppPreviewFS:SetTextColor(1, 1, 1)
                        end
                    end
                    ppPreviewFS:Show()
                else
                    ppPreviewFS:Hide()
                end
            end

            if portraitFrame then
                if sp then
                    if not portraitFrame:IsShown() then
                        portraitFrame:Show()
                    end
                    if portraitFrame._applyMode then portraitFrame._applyMode() end
                    ApplyPreviewPortraitShape(portraitFrame, s)
                else
                    if portraitFrame:IsShown() then
                        portraitFrame:Hide()
                        portraitFrame._anchored = false
                    end
                end
            end

            -- Bottom Text Bar update (before castbar so castbar can anchor to it)
            local cbOff = 0
            if sp and isAttached and side == "right" then cbOff = pw / 2
            elseif sp and isAttached and side == "left" then cbOff = -(pw / 2) end
            local btbPos = s.btbPosition or "bottom"
            local btbIsAtt = (btbPos == "top" or btbPos == "bottom")
            if btbFrame then
                local btbH2 = s.bottomTextBarHeight or 16
                if s.bottomTextBar then
                    local btbIsDetached = not btbIsAtt
                    local btbW2 = btbIsDetached and (s.btbWidth or 0) or 0
                    local btbTW = (btbW2 > 0 and btbIsDetached) and btbW2 or tw
                    PP.Size(btbFrame, btbTW, btbH2)
                    if btbIsDetached and db.profile.enableCustomBarStratas then
                        btbFrame:SetFrameLevel(pf:GetFrameLevel() + 50)
                    elseif btbIsDetached then
                        btbFrame:SetFrameLevel(pf:GetFrameLevel() + 3)
                    end
                    btbFrame:ClearAllPoints()
                    local btbPvAnchor = (pvPpIsAtt and power and power:IsShown()) and power or health
                    if btbPos == "top" then
                        PP.Point(btbFrame, "BOTTOM", health, "TOP", cbOff, 0)
                    elseif btbPos == "detached_top" then
                        btbFrame:SetPoint("BOTTOM", pf, "TOP", s.btbX or 0, 15 + (s.btbY or 0))
                    elseif btbPos == "detached_bottom" then
                        btbFrame:SetPoint("TOP", pf, "BOTTOM", s.btbX or 0, -15 + (s.btbY or 0))
                    else
                        PP.Point(btbFrame, "TOP", btbPvAnchor, "BOTTOM", cbOff, 0)
                    end
                    local bgc = s.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
                    local bga = s.btbBgOpacity or 1.0
                    btbBg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
                    ApplyBTBPreviewTexts(s)
                    if not btbFrame:IsShown() then btbFrame:Show() end
                else
                    if btbFrame:IsShown() then btbFrame:Hide() end
                end
            end

            if castbar then
                if ch > 0 then
                    -- Cast icon "part of the bar": shrink the bar from the left +
                    -- shift it right so the icon sits inside the width (right edge
                    -- fixed); otherwise full width with the icon hanging outside.
                    local ciInWidth, ciOnRight, ciOffX, ciOffY
                    if unitKey == "player" then
                        ciInWidth = s.showPlayerCastIcon ~= false and s.playerCastbarIconInWidth ~= false
                        ciOnRight = s.playerCastbarIconRight == true
                        ciOffX = s.playerCastIconOffsetX or 0
                        ciOffY = s.playerCastIconOffsetY or 0
                    else
                        ciInWidth = s.showCastIcon ~= false and s.castbarIconInWidth ~= false
                        ciOnRight = s.castbarIconRight == true
                        ciOffX = s.castIconOffsetX or 0
                        ciOffY = s.castIconOffsetY or 0
                    end
                    local ciIconW = ch
                    -- Boss: castbarWidth > 0 overrides the frame-matched width (0 = match frame).
                    -- Display-clamped (frame width + 120) -- see the creation-time note.
                    local cbBaseW = tw
                    if unitKey == "boss" and (s.castbarWidth or 0) > 0 then
                        cbBaseW = math.min(math.max(s.castbarWidth, 30), tw + 120)
                    end
                    local ciBarW = ciInWidth and math.max(1, cbBaseW - ciIconW) or cbBaseW
                    castbar:SetSize(ciBarW, ch)
                    -- Anchoring is applied once below (the authoritative anchor
                    -- that accounts for bottom-text-bar / attached-power cases),
                    -- including the icon-in-width rightward shift.
                    castbar:Show()
                    -- Re-apply background color/alpha from settings so the preview
                    -- updates live when Bar Background is changed.
                    if castbar._previewBgTex then
                        local cbgC = s.castBgColor
                        castbar._previewBgTex:SetColorTexture(cbgC and cbgC.r or 0, cbgC and cbgC.g or 0, cbgC and cbgC.b or 0, s.castBgAlpha or 0.5)
                    end
                    if castFill then
                        castFill:ClearAllPoints()
                        if s.castReverseFill then
                            PP.Point(castFill, "TOPRIGHT", castbar, "TOPRIGHT", -1, 0)
                            PP.Point(castFill, "BOTTOMRIGHT", castbar, "BOTTOMRIGHT", -1, 1)
                        else
                            PP.Point(castFill, "TOPLEFT", castbar, "TOPLEFT", 1, 0)
                            PP.Point(castFill, "BOTTOMLEFT", castbar, "BOTTOMLEFT", 1, 1)
                        end
                        castFill:SetWidth(math.floor(math.max(0, ciBarW - 2) * (_previewCastFill or 0.6) + 0.5))
                        -- Update fill color from per-unit settings (class colored only for player)
                        local fillC
                        if unitKey == "player" and s.castbarClassColored then
                            local _, classToken = UnitClass("player")
                            if classToken then fillC = RAID_CLASS_COLORS[classToken] end
                        end
                        if not fillC then fillC = s.castbarFillColor end
                        -- Cast fill reuses the unit's health bar texture (matches real frames).
                        -- WHITE8X8 fallback ensures PV_FillColor always sets vertex color fresh.
                        local cbTexKey = s.healthBarTexture or db.profile.healthBarTexture or "none"
                        local cbTexPath = (ns.healthBarTextures or {})[cbTexKey] or "Interface\\Buttons\\WHITE8X8"
                        if fillC then
                            PV_FillColor(castFill, cbTexPath, fillC.r, fillC.g, fillC.b, nil, nil, nil, 1)
                        else
                            local gc = db.profile.castbarColor or { r=0.114, g=0.655, b=0.514 }
                            PV_FillColor(castFill, cbTexPath, gc.r, gc.g, gc.b, nil, nil, nil, 1)
                        end
                    end
                    if castIconFrame then
                        castIconFrame:SetSize(ch, ch)
                        castIconFrame:ClearAllPoints()
                        if ciOnRight then
                            PP.Point(castIconFrame, "TOPLEFT", castbar, "TOPRIGHT", ciOffX, ciOffY)
                        else
                            PP.Point(castIconFrame, "TOPRIGHT", castbar, "TOPLEFT", ciOffX, ciOffY)
                        end
                        -- Check showCastIcon / showPlayerCastIcon
                        local showIcon
                        if unitKey == "player" then
                            showIcon = s.showPlayerCastIcon ~= false
                        else
                            showIcon = s.showCastIcon ~= false
                        end
                        if showIcon then
                            castIconFrame:Show()
                        else
                            castIconFrame:Hide()
                        end
                        if castIconFrame._iconTex then
                            local spellIcon = (unitKey == "player") and (_previewCastSpell and _previewCastSpell.icon or 136197) or 136197
                            castIconFrame._iconTex:SetTexture(spellIcon)
                        end
                    end
                    -- Side-aware three-zone layout (mirrors the live cast bar). Name and
                    -- duration position for every unit (player has no target zone).
                    local pvNameSide = s.castSpellNameSide or "left"
                    local pvTgtSide  = s.castSpellTargetSide or "right"
                    local pvDurSide  = s.castDurationSide or "right"
                    local showDur    = s.showCastDuration ~= false
                    local showTgt    = s.showCastTarget ~= false
                    local pvBarW     = castbar:GetWidth()
                    local pvHasW     = pvBarW and pvBarW > 0
                    local pvTimerW   = (s.castDurationSize or 10) * 2.2
                    local pvTextW    = pvHasW and (pvBarW * 0.42) or 0
                    if castNameFS2 then
                        local spellName = (unitKey == "player") and (_previewCastSpell and _previewCastSpell.name or "Spell Name") or "Spell Name"
                        castNameFS2:SetText(spellName)
                        castNameFS2:SetFont(PREVIEW_FONT, s.castSpellNameSize or 11, GetUFOptOutline())
                        local snC = s.castSpellNameColor or { r=1, g=1, b=1 }
                        castNameFS2:SetTextColor(snC.r, snC.g, snC.b)
                        castNameFS2:ClearAllPoints()
                        if pvNameSide == "none" then
                            castNameFS2:Hide()
                        elseif pvHasW then
                            local pt, xb, jh = ns.GetCastTextAnchor(pvNameSide, showDur and pvDurSide == pvNameSide, pvTimerW, false)
                            castNameFS2:SetWidth(pvTextW)
                            castNameFS2:SetJustifyH(jh)
                            castNameFS2:SetPoint(pt, castbar, pt, xb + (s.castSpellNameX or 0), 1 + (s.castSpellNameY or 0))
                            castNameFS2:Show()
                        end
                    end
                    if castTimeFS then
                        local spCastTime = (_previewCastSpell and _previewCastSpell.castTime) or 3.0
                        castTimeFS:SetText(string.format("%.1f", spCastTime * (1 - (_previewCastFill or 0.6))))
                        castTimeFS:SetFont(PREVIEW_FONT, s.castDurationSize or 10, GetUFOptOutline())
                        local dtC = s.castDurationColor or { r=1, g=1, b=1 }
                        castTimeFS:SetTextColor(dtC.r, dtC.g, dtC.b)
                        castTimeFS:SetShown(showDur)
                        if pvHasW then
                            local pt, xb, jh = ns.GetCastTextAnchor(pvDurSide, false, pvTimerW, true)
                            castTimeFS:SetWidth(pvTimerW)
                            castTimeFS:SetJustifyH(jh)
                            castTimeFS:ClearAllPoints()
                            castTimeFS:SetPoint(pt, castbar, pt, xb + (s.castDurationX or 0), (s.castDurationY or 0))
                        end
                    end
                    if castTargetFS then
                        castTargetFS:SetFont(PREVIEW_FONT, s.castSpellTargetSize or 11, GetUFOptOutline())
                        local tsC = s.castSpellTargetColor or { r=1, g=1, b=1 }
                        castTargetFS:SetTextColor(tsC.r, tsC.g, tsC.b)
                        castTargetFS:SetShown(showTgt)
                        if pvHasW then
                            local pt, xb, jh = ns.GetCastTextAnchor(pvTgtSide, showDur and pvDurSide == pvTgtSide, pvTimerW, false)
                            castTargetFS:SetWidth(pvTextW)
                            castTargetFS:SetJustifyH(jh)
                            castTargetFS:ClearAllPoints()
                            castTargetFS:SetPoint(pt, castbar, pt, xb + (s.castSpellTargetX or 0), (s.castSpellTargetY or 0))
                        end
                    end
                    -- Re-flow so a live JustifyH change takes effect on already-rendered text.
                    if castNameFS2 then ns.ReflowFontString(castNameFS2) end
                    if castTimeFS then ns.ReflowFontString(castTimeFS) end
                    if castTargetFS then ns.ReflowFontString(castTargetFS) end
                    castbar:ClearAllPoints()
                    local pvBtbVisible = (btbFrame and s.bottomTextBar and btbPos == "bottom")
                    local cbAnchorFrame = pvBtbVisible and btbFrame or ((pvPpIsAtt and power and power:IsShown()) and power or health)
                    local cbAnchorOff = pvBtbVisible and 0 or cbOff
                    -- Icon-in-width: shift the (narrowed) bar by half the icon width
                    -- toward the icon-free side so the footprint stays flush under
                    -- the frame and the icon sits inside its edge (matches the real
                    -- frame). Left icon -> shift right; right icon -> shift left.
                    PP.Point(castbar, "TOP", cbAnchorFrame, "BOTTOM", cbAnchorOff + (ciInWidth and (ciOnRight and -(ciIconW / 2) or (ciIconW / 2)) or 0), 0)
                else
                    castbar:Hide()
                    if castIconFrame then castIconFrame:Hide() end
                end
            end

            -- Border size and color (encompasses health+power+BTB+above pips)
            local bs = ds.borderSize or 1
            local bc = ds.borderColor or { r = 0, g = 0, b = 0 }
            local bTexKey = ds.borderTexture or "solid"
            local borderH = bh2 + (s.bottomTextBar and btbIsAtt and (s.bottomTextBarHeight or 16) or 0)
            border:ClearAllPoints()
            border:SetPoint("TOPLEFT", barArea, "TOPLEFT", 0, 0)
            border:SetPoint("TOPRIGHT", barArea, "TOPRIGHT", 0, 0)
            border:SetHeight(borderH)
            EllesmereUI.ApplyBorderStyle(border, bs, bc.r, bc.g, bc.b, ds.borderAlpha or 1, bTexKey, ds.borderTextureOffset, ds.borderTextureOffsetY, ds.borderTextureShiftX, ds.borderTextureShiftY, "unitframes", bs)

            -- Class Power Pips update (player only)
            if cpPipContainer and cpPips then
                if cpStyle == "modern" then
                    local cpPos = s.classPowerPosition or "top"
                    local cpMax = #cpPips
                    local cpSizeAdj = s.classPowerSize or 8
                    local cpSpacingAdj = s.classPowerSpacing or 2
                    local pipW = cpSizeAdj
                    local pipH = math.max(3, math.floor(cpSizeAdj * 0.375))
                    local pipGap = cpSpacingAdj

                    -- Update background color
                    local cpBgCol = s.classPowerBgColor or { r=0.082, g=0.082, b=0.082, a=1.0 }
                    if cpPipContainer._bgTex then
                        cpPipContainer._bgTex:SetColorTexture(cpBgCol.r, cpBgCol.g, cpBgCol.b, cpBgCol.a)
                    end

                    cpPipContainer:ClearAllPoints()
                    if cpPos == "above" then
                        -- Flush with health bar edges, pixel-perfect
                        -- Uses Snap() to round all positions to physical pixel boundaries
                        -- so gaps between pips are guaranteed identical.
                        local efs = cpPipContainer:GetEffectiveScale()
                        if efs <= 0 then efs = 1 end
                        local function Snap(v) return math.floor(v * efs + 0.5) / efs end
                        local intW = math.floor(fw)
                        -- Compute pip boundary positions: n pips with (n-1) gaps of pipGap
                        -- Total gap space in pixels, snapped
                        local gapPx = Snap(pipGap)
                        local totalGapW = (cpMax - 1) * gapPx
                        local totalPipW = intW - totalGapW
                        local basePipW = totalPipW / cpMax
                        cpPipContainer:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, 0)
                        cpPipContainer:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", 0, 0)
                        cpPipContainer:SetHeight(pipH)
                        for i = 1, cpMax do
                            -- Compute left and right edge of pip i by snapping proportional positions
                            local leftEdge = Snap((i - 1) * (basePipW + gapPx))
                            local rightEdge = Snap((i - 1) * (basePipW + gapPx) + basePipW)
                            local w = rightEdge - leftEdge
                            cpPips[i]:ClearAllPoints()
                            cpPips[i]:SetSize(w, pipH)
                            cpPips[i]:SetPoint("TOPLEFT", cpPipContainer, "TOPLEFT", leftEdge, 0)
                            cpPips[i]:Show()
                        end
                    else
                        -- "top" / "bottom" floating, pixel-perfect sizing
                        local efs = cpPipContainer:GetEffectiveScale()
                        if efs <= 0 then efs = 1 end
                        local function Snap(v) return math.floor(v * efs + 0.5) / efs end
                        local snappedW = Snap(pipW)
                        local snappedH = Snap(pipH)
                        local snappedGap = Snap(pipGap)
                        local totalPipW = cpMax * snappedW + (cpMax - 1) * snappedGap
                        PP.Size(cpPipContainer, totalPipW, snappedH)
                        if cpPos == "top" then
                            local cpXOff = s.classPowerBarX or 0
                            local cpYOff = s.classPowerBarY or 0
                            PP.Point(cpPipContainer, "BOTTOM", health, "TOP", cpXOff, cpYOff)
                        else
                            -- "bottom" position
                            local cpXOff = s.classPowerBarX or 0
                            local cpYOff = s.classPowerBarY or 0
                            local cpBaseY = -1
                            if cpYOff == 0 and castbar and ch > 0 and s.showPlayerCastbar then
                                cpBaseY = -1 - ch
                            end
                            PP.Point(cpPipContainer, "TOP", pf, "BOTTOM", cpXOff, cpBaseY + cpYOff)
                        end
                        local x = 0
                        for i = 1, cpMax do
                            cpPips[i]:ClearAllPoints()
                            cpPips[i]:SetSize(snappedW, snappedH)
                            cpPips[i]:SetPoint("TOPLEFT", cpPipContainer, "TOPLEFT", Snap(x), 0)
                            cpPips[i]:Show()
                            x = x + snappedW + snappedGap
                        end
                    end
                    -- 1px bottom border on pip container (only for "above" position)
                    if cpPipContainer._bottomBdr then
                        if cpPos == "above" then
                            cpPipContainer._bottomBdr:SetColorTexture(bc.r, bc.g, bc.b, 1)
                            cpPipContainer._bottomBdr:Show()
                        else
                            cpPipContainer._bottomBdr:Hide()
                        end
                    end
                    -- Re-color pips based on class color toggle
                    local _, cpPlayerClass = UnitClass("player")
                    local cpUseCC = s.classPowerClassColor ~= false
                    local cpCr, cpCg, cpCb
                    if not cpUseCC then
                        local cc = s.classPowerCustomColor or { r = 1, g = 0.82, b = 0 }
                        cpCr, cpCg, cpCb = cc.r, cc.g, cc.b
                    else
                        local rc = EllesmereUI.GetResourceColor and EllesmereUI.GetResourceColor(cpPlayerClass)
                        if rc then
                            cpCr, cpCg, cpCb = rc.r, rc.g, rc.b
                        else
                            local cc = EllesmereUI.GetClassColor and EllesmereUI.GetClassColor(cpPlayerClass)
                            if cc then cpCr, cpCg, cpCb = cc.r, cc.g, cc.b
                            else cpCr, cpCg, cpCb = 1, 0.84, 0.30 end
                        end
                    end
                    local cpEmptyCol = s.classPowerEmptyColor or { r=0.2, g=0.2, b=0.2, a=1.0 }
                    local previewFilled = math.min(3, cpMax)
                    for i = 1, cpMax do
                        if i <= previewFilled then
                            cpPips[i]:SetColorTexture(cpCr, cpCg, cpCb, 1)
                            cpPips[i]:SetAlpha(1)
                        else
                            cpPips[i]:SetColorTexture(cpEmptyCol.r, cpEmptyCol.g, cpEmptyCol.b, cpEmptyCol.a)
                            cpPips[i]:SetAlpha(1)
                        end
                    end
                    cpPipContainer:Show()
                    if pf._cpPipOv then pf._cpPipOv:Show() end
                else
                    cpPipContainer:Hide()
                    for i = 1, #cpPips do cpPips[i]:Hide() end
                    if pf._cpPipOv then pf._cpPipOv:Hide() end
                end
            end

            -- Absorb bars (player/target/focus). The Heal Absorb Style eyeball
            -- preview, when on, replaces the shield absorb with the heal absorb.
            -- Both honor their placement cog (absorbEdgeMode / healAbsorbEdgeMode).
            local _healPrev = showHealAbsorbPreview
            -- The eyeball only replaces the shield when there is actually a heal
            -- absorb to show; if Heal Absorb Style is "none" we leave the shield
            -- preview alone instead of blanking the absorb area.
            local _healWillShow = _healPrev and (s.healAbsorbStyle or "clean") ~= "none"
            if absorbBar then
                local absS = s.showPlayerAbsorb
                if (not _healWillShow) and absS and absS ~= "none" then
                    local _paTex = {
                        striped         = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped3.tga",
                        stripedReversed = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-5-reversed.png",
                        clean           = "Interface\\Buttons\\WHITE8X8",
                        blizzard        = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\blizzard.tga",
                        largeOutlinedStripes  = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-habsorb-left.png",
                        largeOutlinedStripesR = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-habsorb-right.png",
                        largeStripes          = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-absorb-left.png",
                        largeStripesR         = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-absorb-right.png",
                    }
                    local _paAlpha = { striped = 0.8, stripedReversed = 0.8, clean = (s.absorbCleanAlpha or 30) / 100, blizzard = 0.8 }
                    -- Effective opacity/color: mirrors GetAbsorbOpacity in EllesmereUIUnitFrames.lua
                    local _paA = s.absorbOpacity and (s.absorbOpacity / 100) or _paAlpha[absS] or 0.8
                    local _paC = s.absorbColor or { r = 1, g = 1, b = 1 }
                    absorbBar:SetStatusBarTexture(ns.ResolveAbsorbStyleTex(absS, _paTex.striped))
                    local _paFill = absorbBar:GetStatusBarTexture()
                    if _paFill then
                        _paFill:SetDrawLayer("ARTWORK", 1)
                        local _paTiled = (absS == "stripedReversed" or absS == "largeStripes" or absS == "largeStripesR" or absS == "largeOutlinedStripes" or absS == "largeOutlinedStripesR")
                        _paFill:SetHorizTile(_paTiled); _paFill:SetVertTile(_paTiled)
                    end
                    absorbBar:SetStatusBarColor(_paC.r, _paC.g, _paC.b, _paA)
                    PositionPreviewAbsorb(absorbBar, s.absorbEdgeMode or "overlay", s.healthReverseFill)
                    absorbBar:SetWidth(fw)
                    absorbBar:SetHeight(hh)
                    absorbBar:Show()
                else
                    absorbBar:Hide()
                end
            end
            if healAbsorbBar then
                local haS = s.healAbsorbStyle or "clean"
                if _healPrev and haS ~= "none" then
                    local _haA = ((s.healAbsorbOpacity) or 65) / 100
                    local _haC = s.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
                    if haS == "largeOutlinedStripes" or haS == "largeOutlinedStripesR" then _haC = { r = 1, g = 1, b = 1 } end
                    healAbsorbBar:SetStatusBarTexture(ns.ResolveAbsorbStyleTex(haS, "Interface\\Buttons\\WHITE8X8"))
                    local _haFill = healAbsorbBar:GetStatusBarTexture()
                    if _haFill then
                        _haFill:SetDrawLayer("ARTWORK", 2)
                        local _haTiled = (haS == "stripedReversed" or haS == "largeStripes" or haS == "largeStripesR" or haS == "largeOutlinedStripes" or haS == "largeOutlinedStripesR")
                        _haFill:SetHorizTile(_haTiled); _haFill:SetVertTile(_haTiled)
                    end
                    healAbsorbBar:SetStatusBarColor(_haC.r, _haC.g, _haC.b, _haA)
                    PositionPreviewAbsorb(healAbsorbBar, s.healAbsorbEdgeMode or "overlay", s.healthReverseFill)
                    healAbsorbBar:SetWidth(fw)
                    healAbsorbBar:SetHeight(hh)
                    healAbsorbBar:Show()
                    if healAbsorbBar._bg then
                        healAbsorbBar._bg:SetColorTexture(0, 0, 0, ((s.healAbsorbBgOpacity) or 15) / 100)
                        healAbsorbBar._bg:SetAllPoints(healAbsorbBar:GetStatusBarTexture())
                        healAbsorbBar._bg:Show()
                    end
                else
                    healAbsorbBar:Hide()
                end
            end

            -- Absorb Bar / Heal Absorb Bar preview strips (independent of the
            -- overlay styles; anchored to the preview health bar).
            local _absStripHp = absorbBar and absorbBar:GetParent()
            if absorbTopBar and _absStripHp then
                local pos = s.absorbBarPosition or "none"
                if pos ~= "none" then
                    local bc = s.absorbBarColor or { r = 1, g = 1, b = 1 }
                    ns.UF_ApplyStripBarLayout(absorbTopBar, _absStripHp, pos, s.absorbBarHeight or 4, _absStripHp:GetFrameLevel() + 1)
                    absorbTopBar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a or 1)
                    absorbTopBar:Show()
                else
                    absorbTopBar:Hide()
                end
            end
            if healAbsorbTopBar and _absStripHp then
                local pos = s.healAbsorbBarPosition or "none"
                if pos ~= "none" then
                    local hbc = s.healAbsorbBarColor or { r = 200/255, g = 29/255, b = 29/255 }
                    ns.UF_ApplyStripBarLayout(healAbsorbTopBar, _absStripHp, pos, s.healAbsorbBarHeight or 4, _absStripHp:GetFrameLevel() + 1, s.absorbBarPosition or "none", s.absorbBarHeight or 4)
                    healAbsorbTopBar:SetStatusBarColor(hbc.r, hbc.g, hbc.b, hbc.a or 1)
                    healAbsorbTopBar:Show()
                else
                    healAbsorbTopBar:Hide()
                end
            end

            if dispelOverlayPreview then
                local mode = db.profile.dispelOverlay or "none"
                if showDispelOverlayPreview and mode ~= "none" then
                    local c = db.profile.dispelColorMagic or { r = 0.349, g = 0.475, b = 1.0 }
                    local alpha = (db.profile.dispelOverlayOpacity or 100) / 100
                    dispelOverlayPreview:ClearAllPoints()
                    dispelOverlayPreview:SetVertexColor(1, 1, 1, 1)
                    if mode == "full" then
                        dispelOverlayPreview:SetAllPoints(health)
                        dispelOverlayPreview:SetColorTexture(c.r, c.g, c.b, alpha)
                    elseif mode == "gradient" or mode == "gradient_sharp" then
                        dispelOverlayPreview:SetAllPoints(health)
                        dispelOverlayPreview:SetTexture(mode == "gradient_sharp"
                            and "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-sharp.tga"
                            or "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-tb.tga")
                        dispelOverlayPreview:SetVertexColor(c.r, c.g, c.b, alpha)
                    else
                        dispelOverlayPreview:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
                        dispelOverlayPreview:SetPoint("BOTTOMRIGHT", healthFill, "BOTTOMRIGHT", 0, 0)
                        dispelOverlayPreview:SetColorTexture(c.r, c.g, c.b, alpha)
                    end
                    dispelOverlayPreview:Show()
                else
                    dispelOverlayPreview:Hide()
                end
            end

            -- Buff icons -- reposition based on anchor/growth/size/offset settings
            local buffExtra = 0
            -- Vertical overflow (px) reserved when a Y offset pushes auras past the
            -- frame edges, beyond their footprint. Fed into the dynamic header below
            -- so the preview grows instead of icons spilling onto neighboring options.
            local auraTopOv, auraBotOv = 0, 0
            if #buffIcons > 0 then
                -- Boss Simple Buff Display forces a single Left/Right column matched
                -- to the frame height; mirrors the live runtime override.
                local simpleBuffMode = (unitKey == "boss") and ns.GetBossSimpleBuffMode(s) or "none"
                local simpleBuffOn = simpleBuffMode ~= "none"
                local maxBuf = s.maxBuffs or 4
                local visibleBuffCount = math.min(2, maxBuf)
                -- Boss preview always shows exactly 2 buffs regardless of Max Count.
                if unitKey == "boss" then visibleBuffCount = math.min(#buffIcons, 2) end
                local showB = simpleBuffOn or (s.showBuffs and (s.buffAnchor or "topleft") ~= "none")
                if showB and visibleBuffCount > 0 then
                    local buffSize = s.buffSize or 22
                    if simpleBuffOn then
                        local pvPowerPos = s.powerPosition or "below"
                        local pvPowerIsAtt = (pvPowerPos == "below" or pvPowerPos == "above")
                        local pvPowerH = pvPowerIsAtt and (s.powerHeight or 0) or 0
                        buffSize = (s.healthHeight or 34) + pvPowerH
                    end
                    -- Crop never applies in simple mode (runtime parity).
                    local buffCrop = (not simpleBuffOn) and (s.buffCropIcons or false) or false
                    local buffH = ns.GetAuraCropHeight(buffCrop, buffSize)
                    -- Boss icon spacing from the configured slider (simple display
                    -- uses its own key); other units keep the 1px schematic gap.
                    local buffGapX = (unitKey == "boss") and ns.GetBossBuffSpacing(s, simpleBuffOn) or (s.buffSpacingX or 1)
                    local buffGapY = (unitKey == "boss") and ns.GetBossBuffSpacing(s, simpleBuffOn) or (s.buffSpacingY or 1)
                    local bOffX = s.buffOffsetX or 0
                    -- Preview now mirrors the real frame's Y offset too; the dynamic
                    -- header below reserves room so offset auras never overflow.
                    local bOffY = s.buffOffsetY or 0
                    -- Simple mode uses its own X/Y offsets (falling back to the regular
                    -- buff offsets for existing users) to match the live column.
                    if simpleBuffOn then bOffX, bOffY = ns.GetBossSimpleBuffOffset(s) end
                    -- Cap the preview's Y offset so it can't over-expand the preview.
                    bOffY = math.max(-PREVIEW_Y_CAP, math.min(PREVIEW_Y_CAP, bOffY))
                    local ba = simpleBuffOn and simpleBuffMode or (s.buffAnchor or "topleft")
                    local bg = s.buffGrowth or "auto"

                    -- Determine growth direction for icon 2 placement
                    local autoGrowth = {
                        topleft = "right", topright = "left",
                        bottomleft = "right", bottomright = "left",
                        left = "left", right = "right",
                    }
                    local gDir = (bg == "auto") and (autoGrowth[ba] or "right") or bg

                    -- Anchor point on pf and offset for first icon
                    local anchorMap = {
                        topleft     = { pt = "TOPLEFT",     ox = bOffX,                        oy = buffGapY + bOffY },
                        topright    = { pt = "TOPRIGHT",    ox = bOffX,                        oy = buffGapY + bOffY },
                        bottomleft  = { pt = "BOTTOMLEFT",  ox = bOffX,                        oy = -(buffH + buffGapY) + bOffY },
                        bottomright = { pt = "BOTTOMRIGHT", ox = bOffX,                        oy = -(buffH + buffGapY) + bOffY },
                        left        = { pt = "LEFT",        ox = -(buffGapX) + bOffX,          oy = bOffY },
                        right       = { pt = "RIGHT",       ox = buffGapX + bOffX,             oy = bOffY },
                    }
                    local am = anchorMap[ba] or anchorMap.topleft

                    -- Growth offset for icon 2 relative to icon 1
                    local dx, dy = 0, 0
                    if gDir == "right" then dx = buffSize + buffGapX
                    elseif gDir == "left" then dx = -(buffSize + buffGapX)
                    elseif gDir == "up" then dy = buffH + buffGapY
                    elseif gDir == "down" then dy = -(buffH + buffGapY)
                    else dx = buffSize + buffGapX end

                    -- Determine justifyH for SetPoint (which corner of the icon anchors)
                    local justH = "BOTTOMLEFT"
                    if ba == "topright" or ba == "bottomright" then
                        justH = "BOTTOMRIGHT"
                    elseif ba == "left" then
                        justH = "RIGHT"
                    elseif ba == "right" then
                        justH = "LEFT"
                    end

                    -- Boss Simple Buff Display: anchor the column to the top of the
                    -- health bar (not pf, which includes the cast bar) so the icons
                    -- align with the bar area, matching the runtime layout.
                    local useSimpleBossAnchor = simpleBuffOn
                    local bossSimpleAnchorFrame = useSimpleBossAnchor and health or pf
                    local simpleIconPt   = (simpleBuffMode == "right") and "TOPLEFT"  or "TOPRIGHT"
                    local simpleParentPt = (simpleBuffMode == "right") and "TOPRIGHT" or "TOPLEFT"
                    local simpleEdgeSign = (simpleBuffMode == "right") and 1 or -1

                    -- Build a cache key so we only reanchor when the anchor actually changes.
                    -- ClearAllPoints + SetPoint causes a one-frame gap that makes icons blink.
                    -- Also guard Show()/Hide() -- calling Show() on an already-visible frame
                    -- triggers a re-render that causes a shutter effect.
                    local anchorKey = justH .. am.pt .. am.ox .. am.oy .. dx .. dy .. buffSize .. buffH .. (useSimpleBossAnchor and "S" or "N") .. simpleBuffMode .. bOffX .. "gx" .. buffGapX .. "gy" .. buffGapY
                    for i, bf in ipairs(buffIcons) do
                        if i <= visibleBuffCount then
                            if bf._anchorKey ~= anchorKey then
                                PP.Size(bf, buffSize, buffH)
                                bf:ClearAllPoints()
                                if i == 1 then
                                    if useSimpleBossAnchor then
                                        PP.Point(bf, simpleIconPt, bossSimpleAnchorFrame, simpleParentPt, simpleEdgeSign * buffGapX + bOffX, bOffY)
                                    else
                                        -- Left/Right center on the bar area (barArea) only, not pf
                                        -- which includes the cast bar -- matches real frames + boss preview.
                                        PP.Point(bf, justH, (ba == "left" or ba == "right") and barArea or pf, am.pt, am.ox, am.oy)
                                    end
                                else
                                    if useSimpleBossAnchor then
                                        PP.Point(bf, simpleIconPt, buffIcons[1], simpleIconPt, simpleEdgeSign * (i - 1) * (buffSize + buffGapX), 0)
                                    else
                                        PP.Point(bf, justH, buffIcons[1], justH, dx * (i - 1), dy * (i - 1))
                                    end
                                end
                                bf._anchorKey = anchorKey
                            end
                            if not bf:IsShown() then bf:Show() end
                            if bf._iconTex then
                                bf._iconTex:SetTexture(_previewBuffIcons[i] or 135932)
                                -- SetTexture resets texcoord, so re-apply the crop each update.
                                ns.SetAuraIconCrop(bf._iconTex, buffCrop, buffSize, buffH, s.buffIconZoom or 0.07)
                            end
                        else
                            if bf:IsShown() then bf:Hide() end
                        end
                    end

                    -- Add buff height only when buffs sit above/below the frame
                    -- (top/bottom anchors). Left/Right columns grow sideways and
                    -- need no extra vertical room, so they reserve no space.
                    if ba == "topleft" or ba == "topright" or ba == "bottomleft" or ba == "bottomright" then
                        buffExtra = buffH + buffGapY + 2
                    end
                    -- Reserve any vertical overflow the Y offset adds beyond the
                    -- footprint above: top anchors pushed up / bottom pushed down;
                    -- side anchors have no footprint so the whole offset counts.
                    if ba == "topleft" or ba == "topright" then
                        if bOffY > 0 then auraTopOv = auraTopOv + bOffY end
                    elseif ba == "bottomleft" or ba == "bottomright" then
                        if bOffY < 0 then auraBotOv = auraBotOv - bOffY end
                    else
                        if bOffY > 0 then auraTopOv = auraTopOv + bOffY
                        elseif bOffY < 0 then auraBotOv = auraBotOv - bOffY end
                    end
                else
                    for _, bf in ipairs(buffIcons) do if bf:IsShown() then bf:Hide() end end
                end
            end

            -- Debuff icons -- reposition based on anchor/growth/size/offset settings.
            -- Boss Simple Debuff Display forces Left anchor + frame-height-matched
            -- size; this must match the live runtime override.
            local debuffExtra = 0
            if #debuffIcons > 0 and not noDebuffPreview then
                local dAnc = s.debuffAnchor or "bottomleft"
                local effectiveDebuffSize = s.debuffSize or 22
                local simpleMode = (unitKey == "boss") and ns.GetBossSimpleDebuffMode(s) or "none"
                local simpleOn = simpleMode ~= "none"
                if simpleOn then
                    dAnc = simpleMode  -- "left" or "right"
                    local pvPowerPos = s.powerPosition or "below"
                    local pvPowerIsAtt = (pvPowerPos == "below" or pvPowerPos == "above")
                    local pvPowerH = pvPowerIsAtt and (s.powerHeight or 0) or 0
                    effectiveDebuffSize = (s.healthHeight or 34) + pvPowerH
                end
                local maxDeb = s.maxDebuffs or 10
                local previewDebuffLimit = 5
                local visibleDebuffCount = math.min(#debuffIcons, maxDeb, previewDebuffLimit)
                -- Boss preview always shows exactly 3 debuffs regardless of Max Count.
                if unitKey == "boss" then visibleDebuffCount = math.min(#debuffIcons, 3) end
                if dAnc ~= "none" and visibleDebuffCount > 0 then
                    local debuffSize = effectiveDebuffSize
                    -- Crop never applies in simple boss mode (runtime parity: it
                    -- passes nil crop and frame-height-matches those icons).
                    local debuffCrop = (not simpleOn) and (s.debuffCropIcons or false) or false
                    local debuffH = ns.GetAuraCropHeight(debuffCrop, debuffSize)
                    -- Boss icon spacing from the configured slider (simple display
                    -- uses its own key); other units keep the 1px schematic gap.
                    local debuffGapX = (unitKey == "boss") and ns.GetBossDebuffSpacing(s, simpleOn) or (s.debuffSpacingX or 1)
                    local debuffGapY = (unitKey == "boss") and ns.GetBossDebuffSpacing(s, simpleOn) or (s.debuffSpacingY or 1)
                    local dOffX = s.debuffOffsetX or 0
                    -- Preview now mirrors the real frame's Y offset too; the dynamic
                    -- header below reserves room so offset auras never overflow.
                    local dOffY = s.debuffOffsetY or 0
                    -- Simple mode uses its own X/Y offsets (falling back to the regular
                    -- debuff offsets for existing users) to match the live column.
                    if simpleOn then dOffX, dOffY = ns.GetBossSimpleDebuffOffset(s) end
                    -- Cap the preview's Y offset so it can't over-expand the preview.
                    dOffY = math.max(-PREVIEW_Y_CAP, math.min(PREVIEW_Y_CAP, dOffY))
                    local dg = s.debuffGrowth or "auto"

                    local autoGrowth = {
                        topleft = "right", topright = "left",
                        bottomleft = "right", bottomright = "left",
                        left = "left", right = "right",
                    }
                    local gDir = (dg == "auto") and (autoGrowth[dAnc] or "right") or dg

                    local anchorMap = {
                        topleft     = { pt = "TOPLEFT",     ox = dOffX,                         oy = debuffGapY + dOffY },
                        topright    = { pt = "TOPRIGHT",    ox = dOffX,                         oy = debuffGapY + dOffY },
                        bottomleft  = { pt = "BOTTOMLEFT",  ox = dOffX,                         oy = -(debuffH + debuffGapY) + dOffY },
                        bottomright = { pt = "BOTTOMRIGHT", ox = dOffX,                         oy = -(debuffH + debuffGapY) + dOffY },
                        left        = { pt = "LEFT",        ox = -(debuffGapX) + dOffX,         oy = dOffY },
                        right       = { pt = "RIGHT",       ox = debuffGapX + dOffX,            oy = dOffY },
                    }
                    local am = anchorMap[dAnc] or anchorMap.bottomleft

                    local dx, dy = 0, 0
                    if gDir == "right" then dx = debuffSize + debuffGapX
                    elseif gDir == "left" then dx = -(debuffSize + debuffGapX)
                    elseif gDir == "up" then dy = debuffH + debuffGapY
                    elseif gDir == "down" then dy = -(debuffH + debuffGapY)
                    else dx = debuffSize + debuffGapX end

                    local justH = "BOTTOMLEFT"
                    if dAnc == "topright" or dAnc == "bottomright" then
                        justH = "BOTTOMRIGHT"
                    elseif dAnc == "left" then
                        justH = "RIGHT"
                    elseif dAnc == "right" then
                        justH = "LEFT"
                    end

                    -- Boss Simple Debuff Display: anchor the stack to the
                    -- top of the health bar (not pf, which includes the cast
                    -- bar) so the icons align with the bar area, matching
                    -- the runtime layout.
                    local useSimpleBossAnchor = simpleOn
                    local bossSimpleAnchorFrame = useSimpleBossAnchor and health or pf
                    -- Simple mode side: Left pins the column to the frame's left edge
                    -- (icons grow left), Right pins to the right edge (icons grow right).
                    local simpleIconPt   = (simpleMode == "right") and "TOPLEFT"  or "TOPRIGHT"
                    local simpleParentPt = (simpleMode == "right") and "TOPRIGHT" or "TOPLEFT"
                    local simpleEdgeSign = (simpleMode == "right") and 1 or -1
                    local anchorKey = justH .. am.pt .. am.ox .. am.oy .. dx .. dy .. debuffSize .. debuffH .. (useSimpleBossAnchor and "S" or "N") .. simpleMode .. dOffX .. "gx" .. debuffGapX .. "gy" .. debuffGapY .. "z" .. (s.debuffIconZoom or 0.07)
                    for i, df in ipairs(debuffIcons) do
                        if i <= visibleDebuffCount then
                            if df._anchorKey ~= anchorKey then
                                PP.Size(df, debuffSize, debuffH)
                                if df._iconTex then ns.SetAuraIconCrop(df._iconTex, debuffCrop, debuffSize, debuffH, s.debuffIconZoom or 0.07) end
                                df:ClearAllPoints()
                                if i == 1 then
                                    if useSimpleBossAnchor then
                                        PP.Point(df, simpleIconPt, bossSimpleAnchorFrame, simpleParentPt, simpleEdgeSign * debuffGapX + dOffX, dOffY)
                                    else
                                        -- Left/Right center on the bar area (barArea) only, not pf
                                        -- which includes the cast bar -- matches real frames + boss preview.
                                        PP.Point(df, justH, (dAnc == "left" or dAnc == "right") and barArea or pf, am.pt, am.ox, am.oy)
                                    end
                                else
                                    if useSimpleBossAnchor then
                                        PP.Point(df, simpleIconPt, debuffIcons[1], simpleIconPt, simpleEdgeSign * (i - 1) * (debuffSize + debuffGapX), 0)
                                    else
                                        PP.Point(df, justH, debuffIcons[1], justH, dx * (i - 1), dy * (i - 1))
                                    end
                                end
                                df._anchorKey = anchorKey
                            end
                            if not df:IsShown() then df:Show() end
                        else
                            if df:IsShown() then df:Hide() end
                        end
                    end

                    -- Add debuff height only when debuffs sit above/below the frame
                    -- (top/bottom anchors). Left/Right columns grow sideways and
                    -- need no extra vertical room, so they reserve no space.
                    local debuffGap2 = 1
                    if dAnc == "topleft" or dAnc == "topright" or dAnc == "bottomleft" or dAnc == "bottomright" then
                        debuffExtra = debuffH + debuffGap2 + 2
                    end
                    -- Reserve any vertical overflow the Y offset adds beyond the
                    -- footprint above (see the buff block for the rationale).
                    if dAnc == "topleft" or dAnc == "topright" then
                        if dOffY > 0 then auraTopOv = auraTopOv + dOffY end
                    elseif dAnc == "bottomleft" or dAnc == "bottomright" then
                        if dOffY < 0 then auraBotOv = auraBotOv - dOffY end
                    else
                        if dOffY > 0 then auraTopOv = auraTopOv + dOffY
                        elseif dOffY < 0 then auraBotOv = auraBotOv - dOffY end
                    end
                else
                    for _, df in ipairs(debuffIcons) do if df:IsShown() then df:Hide() end end
                end
            end

            -- Fake static cooldown swipe + duration text + stack text on the boss
            -- debuff preview icons (mirrors the live boss aura buttons). Sizing and
            -- visibility follow the boss aura settings so the new Simple Text Size /
            -- Show Cooldown Text / Stack controls live-update here.
            do
                local showExtras = (unitKey == "boss") and not noDebuffPreview
                local showCDText, cdTextSize, cdTOffX, cdTOffY, stackTextSize, stackTextPosition, stackTOffX, stackTOffY, cdTextColor, stackTextColor
                if showExtras then
                    if ns.GetBossSimpleDebuffMode(s) ~= "none" then
                        showCDText = s.simpleDebuffShowCooldownText
                        cdTextSize = s.simpleDebuffCooldownTextSize or 14
                        cdTOffX = s.simpleDebuffCooldownTextOffsetX or 0
                        cdTOffY = s.simpleDebuffCooldownTextOffsetY or 0
                    else
                        showCDText = s.debuffShowCooldownText
                        cdTextSize = s.debuffCooldownTextSize or 10
                        cdTOffX = s.debuffCooldownTextOffsetX or 0
                        cdTOffY = s.debuffCooldownTextOffsetY or 0
                    end
                    stackTextSize = s.debuffStackTextSize or 14
                    stackTextPosition = s.debuffStackTextPosition or "bottomright"
                    stackTOffX = s.debuffStackTextOffsetX or 0
                    stackTOffY = s.debuffStackTextOffsetY or 0
                    cdTextColor = s.debuffCooldownTextColor or {r=1, g=1, b=1}
                    stackTextColor = s.debuffStackTextColor or {r=1, g=1, b=1}
                end
                local fontP = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF"
                for i = 1, #debuffIcons do
                    local df = debuffIcons[i]
                    local cd, dt, st = df._previewCD, df._durText, df._stackText
                    if showExtras and df:IsShown() then
                        if cd and not cd:IsShown() then cd:Show() end
                        if dt then
                            if showCDText then
                                EllesmereUI.ApplyIconTextFont(dt, fontP, cdTextSize, "unitFrames")
                                dt:ClearAllPoints()
                                dt:SetPoint("CENTER", df, "CENTER", cdTOffX, cdTOffY)
                                dt:SetTextColor(cdTextColor.r, cdTextColor.g, cdTextColor.b)
                                dt:Show()
                            else
                                dt:Hide()
                            end
                        end
                        -- Stack text on a single icon only (most debuffs are
                        -- unstacked); icon 2 matches the in-game preview.
                        if st then
                            if i == 2 then
                                EllesmereUI.ApplyIconTextFont(st, fontP, stackTextSize, "unitFrames")
                                st:SetText(3)
                                ns.ApplyStackAnchor(st, df, stackTextPosition, stackTOffX, stackTOffY)
                                st:SetTextColor(stackTextColor.r, stackTextColor.g, stackTextColor.b)
                                st:Show()
                            else
                                st:Hide()
                            end
                        end
                    else
                        if cd then cd:Hide() end
                        if dt then dt:Hide() end
                        if st then st:Hide() end
                    end
                end
            end

            local btbExtra = (btbFrame and s.bottomTextBar and btbIsAtt) and (s.bottomTextBarHeight or 16) or 0
            local th = bh2 + btbExtra + (ch > 0 and ch or 0)
            pf:SetSize(tw, th)

            -- Apply preview scale; shrink to fit when the frame is wider than the panel
            local baseScale = pf._previewScale or 1
            local fitScale = 1
            do
                local PAD = EllesmereUI.CONTENT_PAD or 10
                local availW = (pf:GetParent():GetWidth() - PAD * 2) / baseScale
                if tw > availW and tw > 0 and availW > 0 then
                    fitScale = availW / tw
                end
            end
            local combinedScale = baseScale * fitScale
            pf:SetScale(combinedScale)

            -- Recalculate border sizes after scale change so they stay pixel-perfect
            if border then
                local bs2 = ds.borderSize or 1
                local bTex2 = ds.borderTexture or "solid"
                EllesmereUI.ApplyBorderStyle(border, bs2, (ds.borderColor or {r=0,g=0,b=0}).r, (ds.borderColor or {r=0,g=0,b=0}).g, (ds.borderColor or {r=0,g=0,b=0}).b, ds.borderAlpha or 1, bTex2, ds.borderTextureOffset, ds.borderTextureOffsetY, ds.borderTextureShiftX, ds.borderTextureShiftY, "unitframes", bs2)
            end
            if castbar then
                if PP.GetBorders(castbar) then PP.SetBorderSize(castbar, 1) end
                if castFill then
                    castFill:ClearAllPoints()
                    PP.Point(castFill, "TOPLEFT", castbar, "TOPLEFT", 1, 0)
                    PP.Point(castFill, "BOTTOMLEFT", castbar, "BOTTOMLEFT", 1, 1)
                end
            end
            if castIconFrame then
                PP.SetBorderSize(castIconFrame, 1)
                if castIconFrame._iconTex then
                    castIconFrame._iconTex:ClearAllPoints()
                    PP.Point(castIconFrame._iconTex, "TOPLEFT", castIconFrame, "TOPLEFT", 1, -1)
                    PP.Point(castIconFrame._iconTex, "BOTTOMRIGHT", castIconFrame, "BOTTOMRIGHT", -1, 1)
                end
            end

            -- Re-apply PixelUtil sizing on all elements so they stay pixel-perfect at new scale
            -- Re-snap the preview frame itself
            PP.Size(pf, tw, th)
            local snappedFrameW = pf:GetWidth()
            local snappedFrameH = pf:GetHeight()

            -- Re-snap portrait
            if portraitFrame and sp and isAttached then
                PP.Size(portraitFrame, portraitDim, portraitDim)
                local snappedPortW = portraitFrame:GetWidth()
                local snappedPortH = portraitFrame:GetHeight()
                if snappedPortW + fw > snappedFrameW + 0.01 then
                    portraitFrame:SetWidth(snappedFrameW - fw)
                end
                if snappedPortH > snappedFrameH + 0.01 then
                    portraitFrame:SetHeight(snappedFrameH)
                end
            end

            -- Re-snap health bar
            if health then
                PP.Size(health, fw, hh)
                local snappedHealthW = health:GetWidth()
                local availW = snappedFrameW
                if portraitFrame and sp and isAttached then
                    availW = snappedFrameW - portraitFrame:GetWidth()
                end
                if snappedHealthW > availW + 0.01 then
                    health:SetWidth(availW)
                end
            end

            -- Re-snap power bar
            if power and power:IsShown() then
                local pvPw2 = fw
                local pvPpIsDet2 = (pvPpPos == "detached_top" or pvPpPos == "detached_bottom")
                if pvPpIsDet2 and (s.powerWidth or 0) > 0 then pvPw2 = s.powerWidth end
                PP.Size(power, pvPw2, ph)
                if pvPpIsAtt and health then
                    -- Height: ensure health + power don't exceed expected total
                    local snappedHH = health:GetHeight()
                    local snappedPH = power:GetHeight()
                    local expectedTotal = hh + ph
                    if snappedHH + snappedPH > expectedTotal + 0.01 then
                        power:SetHeight(snappedPH - (snappedHH + snappedPH - expectedTotal))
                    end
                    -- Width: match health bar width exactly
                    local snappedHealthW2 = health:GetWidth()
                    local snappedPowerW2 = power:GetWidth()
                    if math.abs(snappedPowerW2 - snappedHealthW2) > 0.01 then
                        power:SetWidth(snappedHealthW2)
                    end
                end
            end

            -- Re-snap BTB
            if btbFrame and s.bottomTextBar and btbIsAtt then
                PP.Size(btbFrame, tw, s.bottomTextBarHeight or 16)
                local snappedBtbW = btbFrame:GetWidth()
                local snappedBtbH = btbFrame:GetHeight()
                -- Width: trim to frame width
                if snappedBtbW > snappedFrameW + 0.01 then
                    btbFrame:SetWidth(snappedFrameW)
                end
                -- Height: ensure full stack fits within frame height
                local usedH = cpAboveH
                if health then usedH = usedH + health:GetHeight() end
                if power and pvPpIsAtt and power:IsShown() then usedH = usedH + power:GetHeight() end
                if usedH + snappedBtbH > snappedFrameH + 0.01 then
                    btbFrame:SetHeight(snappedBtbH - (usedH + snappedBtbH - snappedFrameH))
                end
            end

            -- Re-snap castbar background width. Boss custom widths (castbarWidth
            -- > 0) are intentionally wider/narrower than the frame and already
            -- display-clamped at sizing time -- trimming here would silently
            -- revert them to frame width.
            if castbar then
                local pvCbCustom = unitKey == "boss" and (s.castbarWidth or 0) > 0
                local cbW = castbar:GetWidth()
                if not pvCbCustom and cbW > snappedFrameW + 0.01 then
                    castbar:SetWidth(snappedFrameW)
                end
            end

            -- Determine how much extra space buffs/debuffs need above/below the frame
            local auraTopPad = 0  -- extra space above frame (push preview down)
            if buffExtra > 0 then
                local ba2 = s.buffAnchor or "topleft"
                if ba2 == "topleft" or ba2 == "topright" then
                    auraTopPad = buffExtra
                end
            end
            if debuffExtra > 0 then
                local da2 = s.debuffAnchor or "bottomleft"
                if da2 == "topleft" or da2 == "topright" then
                    auraTopPad = auraTopPad + debuffExtra
                end
            end
            -- Add the upward Y-offset overflow so the preview slides down enough to
            -- fit auras pushed above their footprint (any anchor).
            auraTopPad = auraTopPad + auraTopOv

            -- Extra space above frame for detached-top elements
            local detTopExtra = 0
            -- Detached top portrait
            if sp and not isAttached and effectiveSide == "top" and portraitFrame and portraitFrame:IsShown() then
                detTopExtra = detTopExtra + portraitDim + 15 + pYOff
            end
            -- Detached top text bar
            if btbFrame and s.bottomTextBar and (s.btbPosition or "bottom") == "detached_top" then
                detTopExtra = detTopExtra + (s.bottomTextBarHeight or 16) + 15 + (s.btbY or 0)
            end
            -- Floating "top" class power pips
            if cpTopH > 0 then
                detTopExtra = detTopExtra + cpTopH
            end
            auraTopPad = auraTopPad + detTopExtra

            -- Reposition pf vertically based on aura padding
            local baseOY = pf._headerDropdownOY or 25
            local pfOY = -(baseOY + auraTopPad) / combinedScale
            if pf._lastOY ~= pfOY then
                pf:ClearAllPoints()
                PP.Point(pf, "TOP", pf:GetParent(), "TOP", 0, pfOY)
                pf._lastOY = pfOY
            end

            -- Notify framework of height change for dynamic content header.
            -- Use UpdateContentHeaderHeight so the scroll position is
            -- compensated -- keeps the widget the user is interacting with
            -- in the same screen position even when the preview grows/shrinks.
            -- auraBotOv clears auras pushed below their footprint by the Y offset.
            local auraExtra = buffExtra + debuffExtra + auraBotOv
            pf._buffExtra = auraExtra
            pf._detTopExtra = detTopExtra
            local parentTH = th * combinedScale
            local cpBottomScaled = cpBottomH * combinedScale
            local hintH = 0
            if _ufPreviewHintFS_display and _ufPreviewHintFS_display:IsShown() then hintH = 29 end
            local fixedH = pf._headerFixedH or 0
            if fixedH > 0 then
                -- auraTopOv: the preview slid down by this much (auraTopPad), so the
                -- section must grow by it too, else it overlaps the next section.
                EllesmereUI:UpdateContentHeaderHeight(fixedH + parentTH + auraExtra + auraTopOv + detTopExtra + cpBottomScaled + hintH)
            end
            -- Reposition segmented pill below the preview when height changes
            if pf._segFrame then
                local pillY = -(baseOY + parentTH + auraExtra + auraTopOv + detTopExtra + cpBottomScaled + (pf._segGap or 20))
                PP.Point(pf._segFrame, "TOP", pf:GetParent(), "TOP", 0, pillY)
            end


            -- Combat indicator preview
            if combatInd then
                if showCombatIndicatorPreview and s.combatIndicatorStyle and s.combatIndicatorStyle ~= "none" then
                    local ciStyle = s.combatIndicatorStyle or "class"
                    local ciColor = s.combatIndicatorColor or "custom"
                    local ciSz = s.combatIndicatorSize or 22
                    local ciOx = s.combatIndicatorX or 0
                    local ciOy = s.combatIndicatorY or 0
                    local ciPos = s.combatIndicatorPosition or "healthbar"
                    combatInd:SetSize(ciSz, ciSz)
                    combatInd:ClearAllPoints()
                    -- "healthbar" is the stored value shown as "Center" in the dropdown;
                    -- "center" is a render alias for it.
                    if ciPos == "portrait" and portraitFrame and sp then
                        combatInd:SetPoint("CENTER", portraitFrame, "CENTER", ciOx, ciOy)
                    elseif ciPos == "textbar" then
                        combatInd:SetPoint("CENTER", btbFrame or pf, "CENTER", ciOx, ciOy)
                    elseif ciPos == "healthbar" or ciPos == "center" then
                        combatInd:SetPoint("CENTER", health, "CENTER", ciOx, ciOy)
                    else
                        local anchor =
                            (ciPos == "topright"    and "TOPRIGHT")    or
                            (ciPos == "bottomleft"  and "BOTTOMLEFT")  or
                            (ciPos == "bottomright" and "BOTTOMRIGHT") or
                            "TOPLEFT"
                        combatInd:SetPoint(anchor, health, anchor, ciOx, ciOy)
                    end
                    local _, classToken = UnitClass("player")
                    -- All custom combat icons (combat0..5) are shown as-is (no tint).
                    -- Standard/Class Theme are tinted by the colour mode below.
                    if ciStyle:find("^combat%d") then
                        combatInd:SetTexture(COMBAT_MEDIA_P .. ciStyle .. ".tga")
                        combatInd:SetTexCoord(0, 1, 0, 1)
                        if combatInd.SetDesaturated then combatInd:SetDesaturated(false) end
                        combatInd:SetVertexColor(1, 1, 1, 1)
                    else
                        if ciStyle == "class" then
                            combatInd:SetTexture(COMBAT_MEDIA_P .. "combat-indicator-class-custom.png")
                            local crd = CLASS_FULL_COORDS[classToken]
                            if crd then combatInd:SetTexCoord(crd[1], crd[2], crd[3], crd[4])
                            else combatInd:SetTexCoord(0, 1, 0, 1) end
                        else
                            combatInd:SetTexture(COMBAT_MEDIA_P .. "combat-indicator-custom.png")
                            combatInd:SetTexCoord(0, 1, 0, 1)
                        end
                        if ciColor == "classcolor" then
                            local cc = RAID_CLASS_COLORS[classToken] or { r=1, g=1, b=1 }
                            combatInd:SetVertexColor(cc.r, cc.g, cc.b, 1)
                        elseif ciColor == "custom" then
                            local cc = s.combatIndicatorCustomColor or { r=1, g=1, b=1 }
                            combatInd:SetVertexColor(cc.r or 1, cc.g or 1, cc.b or 1, 1)
                        else
                            combatInd:SetVertexColor(1, 1, 1, 1)
                        end
                    end
                    combatInd:Show()
                else
                    combatInd:Hide()
                end
            end
            -- Sync disabled overlay AFTER pf is fully sized/positioned
            if not isEnabled then
                SyncDisabledOverlay()
                disabledOverlay:Show()
            end
        end

        -- Store element references for hit overlay system
        pf._health = health
        pf._power = power
        pf._castbar = castbar
        pf._castIconFrame = castIconFrame
        pf._castNameFS = castNameFS2
        pf._castTimeFS = castTimeFS
        pf._castTargetFS = castTargetFS
        pf._nameFS = leftFS
        pf._hpFS = rightFS
        pf._centerFS = centerFS
        pf._portraitFrame = portraitFrame
        pf._buffIcons = buffIcons
        pf._debuffIcons = debuffIcons
        pf._barArea = barArea
        pf._textOverlay = textOverlay
        pf._btbFrame = btbFrame
        pf._btbBg = btbBg
        pf._btbLeftFS = btbLeftFS
        pf._btbRightFS = btbRightFS
        pf._btbCenterFS = btbCenterFS
        pf._btbClassIcon = btbClassIconTex
        pf._ppFS = ppPreviewFS
        pf._border = border
        pf._cpPipContainer = cpPipContainer
        pf._cpPips = cpPips
        pf._combatIndicator = combatInd
        pf._dispelOverlayPreview = dispelOverlayPreview

        pf._disabledOverlay = disabledOverlay
        -- Clean up any orphaned preview for this unit key before storing the new one
        local oldPv = allPreviews[unitKey]
        if oldPv and oldPv ~= pf then
            if oldPv._disabledOverlay then oldPv._disabledOverlay:Hide() end
        end
        -- Also purge any orphaned previews (parent set to nil by ClearContentHeaderInner)
        for k, pv in pairs(allPreviews) do
            if pv and pv ~= pf and not pv:GetParent() then
                if pv._disabledOverlay then pv._disabledOverlay:Hide() end
                allPreviews[k] = nil
            end
        end
        allPreviews[unitKey] = pf
        return pf
    end

    ---------------------------------------------------------------------------
    --  Shared border options builder (used by all per-unit pages)
    ---------------------------------------------------------------------------
    local function BuildBorderOptions(W, parent, y, settingsTable)
        local _, h

        local borderRow
        borderRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Border Size",
              min = 0, max = 4, step = 1, trackWidth = 120,
              getValue = function() return settingsTable.borderSize or 1 end,
              setValue = function(v)
                  settingsTable.borderSize = v; ReloadAndUpdate()
              end },
            nil);  y = y - h

        -- Double inline swatches on Border slider: left = Highlight, right = Border
        do
            local leftRgn = borderRow._leftRegion
            local ctrl = leftRgn._control
            local PP = EllesmereUI.PP

            -- Right swatch: Border color (with alpha)
            local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                leftRgn, borderRow:GetFrameLevel() + 3,
                function()
                    local c = settingsTable.borderColor or { r = 0, g = 0, b = 0 }
                    return c.r, c.g, c.b, settingsTable.borderAlpha or 1
                end,
                function(r, g, b, a)
                    settingsTable.borderColor = { r = r, g = g, b = b }
                    settingsTable.borderAlpha = a
                    ReloadAndUpdate()
                end,
                true, 20)
            PP.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            borderSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(borderSwatch, "Border")
            end)
            borderSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Left swatch: Highlight color (with alpha)
            local hlSwatch, updateHlSwatch = EllesmereUI.BuildColorSwatch(
                leftRgn, borderRow:GetFrameLevel() + 3,
                function()
                    local c = settingsTable.highlightColor or { r = 1, g = 1, b = 1 }
                    return c.r, c.g, c.b, settingsTable.highlightAlpha or 1
                end,
                function(r, g, b, a)
                    settingsTable.highlightColor = { r = r, g = g, b = b }
                    settingsTable.highlightAlpha = a
                    ReloadAndUpdate()
                end,
                true, 20)
            PP.Point(hlSwatch, "RIGHT", borderSwatch, "LEFT", -8, 0)
            hlSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(hlSwatch, "Highlight")
            end)
            hlSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch(); updateHlSwatch() end)
        end

        return y
    end

    ---------------------------------------------------------------------------
    --  Page Builders
    ---------------------------------------------------------------------------

    -- General tab removed; per-unit settings live in DISPLAY sections,
    -- positioning lives in Unlock Mode.

    ---------------------------------------------------------------------------
    --  MULTI FRAME EDIT TAB  (checkbox selector + shared per-unit settings)
    ---------------------------------------------------------------------------
    local function RegisterWidgetRefresh(fn)
        if not EllesmereUI._widgetRefreshList then
            EllesmereUI._widgetRefreshList = {}
        end
        table.insert(EllesmereUI._widgetRefreshList, fn)
    end

    -- Dark Mode flattens the health bar to a fixed dark color, so its fill and
    -- background color settings have no visible effect. This greys out and blocks
    -- an entire DualRow region (every swatch/slider/cog/sync inside it) while Dark
    -- Mode is on. Driven by a widget-refresh callback so it tracks the Dark Mode
    -- toggle live (RefreshPage's fast path re-runs these without a full rebuild).
    local function AddDarkModeBlock(rgn)
        if not rgn then return end
        local block = CreateFrame("Frame", nil, rgn)
        block:SetAllPoints()
        block:SetFrameLevel(rgn:GetFrameLevel() + 50)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(block, "Not available in Dark Mode") end)
        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function Update()
            if db and db.profile and db.profile.darkTheme then
                rgn:SetAlpha(0.3); block:Show()
            else
                rgn:SetAlpha(1); block:Hide()
            end
        end
        Update()
        RegisterWidgetRefresh(Update)
    end

    ---------------------------------------------------------------------------
    --  Unified settings builder  (shared settings for the Main Frames page)
    ---------------------------------------------------------------------------
    local UNIT_SUPPORTS = {
        powerHeight          = { player=true, target=true, focus=true },
        showPlayerAbsorb     = { player=true, target=true, focus=true },
        absorbCleanAlpha     = { player=true, target=true, focus=true },
        absorbOpacity        = { player=true, target=true, focus=true },
        absorbColor          = { player=true, target=true, focus=true },
        absorbEdgeMode       = { player=true, target=true, focus=true },
        showOvershield       = { player=true, target=true, focus=true },
        healAbsorbStyle      = { player=true, target=true, focus=true },
        healAbsorbOpacity    = { player=true, target=true, focus=true },
        healAbsorbColor      = { player=true, target=true, focus=true },
        healAbsorbEdgeMode   = { player=true, target=true, focus=true },
        healAbsorbBgOpacity  = { player=true, target=true, focus=true },
        absorbBarPosition     = { player=true, target=true, focus=true },
        absorbBarHeight       = { player=true, target=true, focus=true },
        absorbBarColor        = { player=true, target=true, focus=true },
        healAbsorbBarPosition = { player=true, target=true, focus=true },
        healAbsorbBarHeight   = { player=true, target=true, focus=true },
        healAbsorbBarColor    = { player=true, target=true, focus=true },
        showBuffs            = { player=true, target=true, focus=true },
        combatIndicatorStyle   = { player=true, target=true },
        combatIndicatorColor   = { player=true, target=true },
        combatIndicatorCustomColor = { player=true, target=true },
        combatIndicatorPosition = { player=true, target=true },
        combatIndicatorSize    = { player=true, target=true },
        combatIndicatorX       = { player=true, target=true },
        combatIndicatorY       = { player=true, target=true },
        leaderIndicatorEnabled = { player=true, target=true },
        leaderIndicatorSize    = { player=true, target=true },
        leaderIndicatorPosition= { player=true, target=true },
        leaderIndicatorX       = { player=true, target=true },
        leaderIndicatorY       = { player=true, target=true },
        buffAnchor           = { player=true, target=true, focus=true },
        buffGrowth           = { player=true, target=true, focus=true },
        maxBuffs             = { player=true, target=true, focus=true },
        showPlayerCastbar    = { player=true },
        showPlayerCastIcon   = { player=true },
        playerCastbarIconInWidth = { player=true },
        playerCastbarHeight  = { player=true },
        showCastbar          = { target=true, focus=true },
        showCastIcon         = { target=true, focus=true },
        castbarIconInWidth   = { target=true, focus=true },
        castbarHeight        = { target=true, focus=true },
        castbarHideWhenInactive = { player=true, target=true, focus=true },
        castSpellNameSize    = { player=true, target=true, focus=true },
        castSpellNameColor   = { player=true, target=true, focus=true },
        castDurationSize     = { player=true, target=true, focus=true },
        castDurationColor    = { player=true, target=true, focus=true },
        castSpellTargetSize  = { player=true, target=true, focus=true },
        castSpellTargetColor = { player=true, target=true, focus=true },
        showCastDuration     = { player=true, target=true, focus=true },
        showCastTarget       = { player=true, target=true, focus=true },
        castSpellNameSide    = { player=true, target=true, focus=true },
        castSpellTargetSide  = { player=true, target=true, focus=true },
        castDurationSide     = { player=true, target=true, focus=true },
        castbarFillColor     = { player=true, target=true, focus=true },
        castbarInterruptReadyColor = { target=true, focus=true },
        castbarKickTickEnabled     = { target=true, focus=true },
        castCombineNameTarget      = { target=true, focus=true },
        showClassPowerBar    = { player=true },
        lockClassPowerToFrame= { player=true },
        classPowerStyle      = { player=true },
        classPowerPosition   = { player=true },
        classPowerBarX       = { player=true },
        classPowerBarY       = { player=true },
        classPowerSize       = { player=true },
        classPowerSpacing    = { player=true },
        classPowerClassColor = { player=true },
        classPowerCustomColor= { player=true },
        classPowerBgColor    = { player=true },
        classPowerEmptyColor = { player=true },
        showInRaid           = { player=true, target=true, focus=true },
        showInParty          = { player=true, target=true, focus=true },
        showSolo             = { player=true, target=true, focus=true },
    }
    local UNIT_LABELS_SUP = { player="Player", target="Target", focus="Focus" }

    -- Shown in place of a unit's settings when it isn't using the EllesmereUI
    -- frame (Blizzard default / hidden): we simply don't build the inapplicable
    -- controls, and this one-line notice explains why. Returns the new y.
    local function BuildInactiveNotice(parent, y, src)
        local CPAD = EllesmereUI.CONTENT_PAD or 10
        local note = EllesmereUI.MakeFont(parent, 13, nil, 1, 1, 1)
        note:SetTextColor(1, 1, 1, 0.55)
        note:SetPoint("TOPLEFT", parent, "TOPLEFT", CPAD + 4, y - 18)
        note:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(CPAD + 4), y - 18)
        note:SetJustifyH("LEFT")
        note:SetText(src == "blizzard"
            and EllesmereUI.L("This unit uses the Blizzard default frame -- there are no EllesmereUI settings to configure here.")
            or  EllesmereUI.L("This unit's frame is hidden -- there are no EllesmereUI settings to configure here."))
        return y - 54
    end

    -- After a visibility/enable change makes a unit visible again (or hides a
    -- Blizzard-sourced one), the change may not be applyable live: a unit whose
    -- source was Blizzard/Hidden at login has no spawned EUI frame this session
    -- (and Blizzard's frame can't be torn down live), so prompt for a /reload.
    -- unitKeys: list of unit keys; "boss" checks the boss1 frame.
    local function PromptReloadIfUnspawned(unitKeys)
        local f = ns.frames
        if not f then return end
        local missing = false
        for _, u in ipairs(unitKeys) do
            local spawned = (u == "boss") and f.boss1 or f[u]
            if not spawned then missing = true; break end
        end
        if not missing then return end
        EllesmereUI:ShowConfirmPopup({
            title = "Reload Required",
            message = "This frame's source changes require a UI reload to take effect.",
            confirmText = "Reload Now",
            cancelText = "Later",
            onConfirm = function() ReloadUI() end,
        })
    end

    -- Inline "Frame Source" cog: a small cog next to a unit's Visibility
    -- dropdown / Enable toggle opening a popup with one dropdown -- EllesmereUI
    -- (our skinned frame) or Blizzard Default (leave Blizzard's frame alone).
    -- Hiding stays on the host widget itself (Visibility "Never Show" / the
    -- Enable toggle), so "Hidden" is not duplicated here; the stored style is
    -- kept while hidden and resumes when the frame is re-enabled.
    -- opts: tooltip (row tooltip), disabled/disabledTooltip (row disable, used
    -- by ToT/FoT parent gating), onBeforeSet(v) (boss stops its live preview).
    local function AttachFrameSourceCog(rgn, unitKey, opts)
        opts = opts or {}
        local function StoredStyle()
            local fs = db.profile.frameSource and db.profile.frameSource[unitKey]
            return fs == "blizzard" and "blizzard" or "eui"
        end
        local fsShow  -- forward decl: set() below closes the popup through it
        local _
        local rows = {
            { type = "dropdown", label = "Frame Source",
              values = { eui = "EllesmereUI", blizzard = "Blizzard Default" },
              order = { "eui", "blizzard" },
              tooltip = opts.tooltip,
              disabled = opts.disabled,
              disabledTooltip = opts.disabledTooltip,
              get = StoredStyle,
              set = function(v)
                  if v == StoredStyle() then return end
                  if opts.onBeforeSet then opts.onBeforeSet(v) end
                  -- Also re-enables a hidden frame (picking a style means
                  -- wanting to see it); see ns.SetUnitFrameSource.
                  ns.SetUnitFrameSource(unitKey, v)
                  if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
                  ReloadAndUpdate()
                  EllesmereUI:RefreshPage(true)
                  -- Close the cog popup before the reload prompt: the page
                  -- under it was just rebuilt, so leaving it open would show
                  -- stale rows floating behind the dialog.
                  if fsShow and fsShow._popupFrame and fsShow._popupFrame:IsShown() then
                      fsShow._popupFrame:Hide()
                  end
                  EllesmereUI:ShowConfirmPopup({
                      title = "Reload Required",
                      message = "Changing the frame source requires a UI reload to take effect.",
                      confirmText = "Reload Now",
                      cancelText = "Later",
                      onConfirm = function() ReloadUI() end,
                  })
              end },
        }
        -- Callers can fold additional rows into the same popup (the main
        -- Visibility row hosts the Out of Combat fade here, so the row
        -- carries ONE cog instead of two).
        if opts.extraRows then
            for _, r in ipairs(opts.extraRows) do rows[#rows + 1] = r end
        end
        _, fsShow = EllesmereUI.BuildCogPopup({
            title = opts.title or "Frame Source", bgAlpha = 1,
            frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
            rows = rows,
        })
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints()
        cogTex:SetTexture(EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.7)
            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L(opts.cogTooltip or "Frame Source"))
        end)
        cogBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            EllesmereUI.HideWidgetTooltip()
        end)
        cogBtn:SetScript("OnClick", function(self) fsShow(self) end)
        return cogBtn
    end

    ---------------------------------------------------------------------------
    --  "Apply All Settings To" -- bulk copy between frames of the same group
    ---------------------------------------------------------------------------
    -- Copies every setting shared by the whole group from the source unit's
    -- profile table to the chosen unit's. A key is shared unless UNIT_SUPPORTS
    -- limits it to a subset of the group, or it exists in some group units'
    -- defaults but not all of them (unit-exclusive keys like the player-only
    -- private auras or the player vs target/focus castbar key split). The
    -- union of source and destination keys is copied, so overrides unset on
    -- the source are also cleared on the destination. Frame positions and
    -- enable state live outside the per-unit tables (db.profile.positions /
    -- db.profile.enabledFrames) and are never touched.
    -- Exception: a copy between target and focus evaluates sharedness against
    -- just that pair, so the cast bar section they share (which player lacks)
    -- transfers between them. Copies involving player keep the full-group
    -- rule, so cast bar settings never cross to or from player.
    local MINI_GROUP_ORDER = { "targettarget", "focustarget", "pet" }
    local TARGET_FOCUS_PAIR = { "target", "focus" }
    local function IsGroupSharedKey(key, groupUnits)
        -- Visibility mode stays with the frame: it pairs with
        -- db.profile.enabledFrames (never copied), and copying one without
        -- the other would desync them. Underscore keys are runtime memos
        -- (e.g. _preHiddenBarVisibility), not settings.
        if type(key) ~= "string" then return false end
        if key == "barVisibility" or key:sub(1, 1) == "_" then return false end
        local sup = UNIT_SUPPORTS[key]
        if sup then
            for _, u in ipairs(groupUnits) do
                if not sup[u] then return false end
            end
        end
        local defs = db._profileDefaults or {}
        local inAny, inAll = false, true
        for _, u in ipairs(groupUnits) do
            local d = defs[u]
            if d and d[key] ~= nil then inAny = true else inAll = false end
        end
        if inAny and not inAll then return false end
        return true
    end
    local function CopyAllGroupSettings(srcUnit, dstUnit, groupUnits)
        if (srcUnit == "target" or srcUnit == "focus")
            and (dstUnit == "target" or dstUnit == "focus") then
            groupUnits = TARGET_FOCUS_PAIR
        end
        local src = UNIT_DB_MAP[srcUnit]()
        local dst = UNIT_DB_MAP[dstUnit]()
        local keys = {}
        for k in pairs(src) do keys[k] = true end
        for k in pairs(dst) do keys[k] = true end
        for k in pairs(keys) do
            if IsGroupSharedKey(k, groupUnits) then
                local v = src[k]
                if type(v) == "table" then
                    dst[k] = EllesmereUI.Lite.DeepCopy(v)
                else
                    dst[k] = v
                end
            end
        end
        ReloadAndUpdate()
        EllesmereUI:RefreshPage(true)
    end
    -- Centered one-line label + action dropdown at the top of a unit's
    -- settings list: lists the other frames of the group and copies to the
    -- chosen one after a confirm popup. getValue always returns the
    -- placeholder so the dropdown stores nothing; the registered widget
    -- refresh snaps the label back to the placeholder after each pick.
    local function BuildApplyAllRow(parent, y, groupUnits, srcUnit)
        local ddValues = { [""] = "Choose Frame..." }
        local ddOrder = {}
        for _, key in ipairs(groupUnits) do
            if key ~= srcUnit then
                ddValues[key] = SHORT_LABELS[key] or key
                ddOrder[#ddOrder + 1] = key
            end
        end

        local ROW_H = 50
        local contentPad = EllesmereUI.CONTENT_PAD or 45
        local row = CreateFrame("Frame", nil, parent)
        PP.Size(row, parent:GetWidth() - contentPad * 2, ROW_H)
        PP.Point(row, "TOPLEFT", parent, "TOPLEFT", contentPad, y)

        local label = EllesmereUI.MakeFont(row, 14, nil, 1, 1, 1)
        label:SetText(EllesmereUI.L("Apply All Settings To"))
        label:SetTextColor(1, 1, 1, 0.6)

        local DD_W, GAP = 180, 12
        local ddBtn = EllesmereUI.BuildDropdownControl(
            row, DD_W, row:GetFrameLevel() + 2,
            ddValues, ddOrder,
            function() return "" end,
            function(dstUnit)
                if dstUnit == "" then return end
                EllesmereUI:ShowConfirmPopup({
                    title   = "Apply All Settings",
                    message = EllesmereUI.Lf("Copy all shared settings from %1$s to %2$s?",
                        SHORT_LABELS[srcUnit] or srcUnit, SHORT_LABELS[dstUnit] or dstUnit),
                    disclaimer = "This overwrites the chosen frame's current settings. Frame position, visibility, and enable state are not changed.",
                    confirmText = "Apply",
                    cancelText  = "Cancel",
                    onConfirm = function() CopyAllGroupSettings(srcUnit, dstUnit, groupUnits) end,
                })
            end)
        ddBtn._ttText = "Copy every shared setting from this frame to another frame in this group."
        EllesmereUI.RegisterWidgetRefresh(function() ddBtn._refreshLabel() end)

        -- Center the label + dropdown pair as one line
        local totalW = label:GetStringWidth() + GAP + DD_W
        label:SetPoint("LEFT", row, "CENTER", -totalW / 2, 0)
        ddBtn:SetPoint("LEFT", label, "RIGHT", GAP, 0)

        return row, ROW_H
    end

    local function BuildSharedSettings(parent, y)
        local W = EllesmereUI.Widgets
        local _, h
        local row

        ---------------------------------------------------------------
        --  Unified Get / Set / DB abstraction
        ---------------------------------------------------------------
        local function SGet(key)
            return UNIT_DB_MAP[selectedUnit]()[key]
        end
        local function SSet(key, val)
            UNIT_DB_MAP[selectedUnit]()[key] = val
            ReloadAndUpdate()
        end
        local function SDB()
            return UNIT_DB_MAP[selectedUnit]()
        end
        local function SVal(key, default)
            local v = UNIT_DB_MAP[selectedUnit]()[key]
            if v ~= nil then return v end
            return default
        end
        -- Set that also writes to the current unit (for UNIT_SUPPORTS keys)
        local function SSetSupported(key, val)
            UNIT_DB_MAP[selectedUnit]()[key] = val
            ReloadAndUpdate(); UpdatePreview()
        end
        local function SGetSupported(key)
            return UNIT_DB_MAP[selectedUnit]()[key]
        end
        local function SValSupported(key, default)
            local v = UNIT_DB_MAP[selectedUnit]()[key]
            if v == nil then return default end
            return v
        end
        -- Check if current unit supports a setting
        local function SVisible(key)
            local sup = UNIT_SUPPORTS[key]
            if not sup then return true end
            return sup[selectedUnit] == true
        end
        -- Dim a row region and add tooltip when no checked unit supports the
        -- setting. unsupportedTip (optional) is shown over the dimmed row when
        -- the current unit doesn't support the key.
        local function SApplySupport(region, key, unsupportedTip)
            local visible = SVisible(key)
            if not visible then
                region:SetAlpha(0.35)
                if region._control and region._control.Disable then region._control:Disable() end
            end
            local tip = not visible and unsupportedTip or nil
            if tip then
                local function MakeSupportHit(anchor)
                    if not anchor then return end
                    local hitFrame = CreateFrame("Frame", nil, region)
                    hitFrame:SetPoint("TOPLEFT", anchor, "TOPLEFT", -5, 5)
                    hitFrame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 5, -5)
                    hitFrame:SetFrameLevel(region:GetFrameLevel() + 10)
                    hitFrame:EnableMouse(true)
                    hitFrame:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(anchor, tip)
                    end)
                    hitFrame:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    securecallfunction(hitFrame.SetPassThroughButtons, hitFrame, "LeftButton", "RightButton")
                end
                MakeSupportHit(region._label)
                MakeSupportHit(region._control)
            end
        end
        -- Helper: build a standard cog button on a region
        local function MakeCogBtn(rgn, showFn, anchorTo, iconPath, disabledFn)
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", anchorTo or rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(iconPath or EllesmereUI.COGS_ICON)
            local function isOff() return disabledFn and disabledFn() or false end
            cogBtn:SetScript("OnEnter", function(self) if not isOff() then self:SetAlpha(0.7) end end)
            cogBtn:SetScript("OnLeave", function(self) if not isOff() then self:SetAlpha(0.4) end end)
            cogBtn:SetScript("OnClick", function(self) if not isOff() then showFn(self) end end)
            -- Disabled state (cog alpha 0.15 disabled / 0.4 enabled, per the
            -- inline-controls pattern); re-evaluated on page refresh.
            local function applyCogState()
                local off = isOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                cogBtn:EnableMouse(not off)
            end
            applyCogState()
            if disabledFn then EllesmereUI.RegisterWidgetRefresh(applyCogState) end
            return cogBtn
        end

        parent._showRowDivider = true

        row, h = BuildApplyAllRow(parent, y, GROUP_UNIT_ORDER, selectedUnit); y = y - h

        -------------------------------------------------------------------
        --  DISPLAY
        -------------------------------------------------------------------
        local sharedDisplayHeader
        sharedDisplayHeader, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h

        -- Wire class theme subnav callbacks (per-unit context)
        do
            local sn = portraitArtValues["class"].subnav
            sn.onSelect = function(styleKey)
                UNIT_DB_MAP[selectedUnit]().portraitMode = "class"
                UNIT_DB_MAP[selectedUnit]().classThemeStyle = styleKey
                UNIT_DB_MAP[selectedUnit]().showPortrait = true
                ReloadAndUpdate(); UpdatePreview()
                C_Timer.After(0, function() local rl = EllesmereUI._widgetRefreshList; if rl then for ri = 1, #rl do rl[ri]() end end end)
            end
            sn.icon = function(styleKey)
                local _, classToken = UnitClass("player")
                if not classToken then return nil end
                local coords = CLASS_FULL_COORDS[classToken]
                if not coords then return nil end
                return CLASS_FULL_SPRITE_BASE .. styleKey .. ".tga", coords[1], coords[2], coords[3], coords[4]
            end
        end

        -- Row 1: Visibility | Visibility Options (checkbox dropdown)
        -- Group-axis pass check for the legacy showInRaid/showInParty/showSolo
        -- trio: only the group items constrain it (unconstrained = true), so
        -- ToggleFrame's group gating stays consistent with a multi-selection.
        local function GroupAxisPasses(vm, inRaid, inParty)
            local g1, g2, g3 = vm.in_raid, vm.in_party, vm.solo
            if not (g1 or g2 or g3) or (g1 and g2 and g3) then return true end
            if g1 and inRaid then return true end
            if g2 and (inParty or inRaid) then return true end
            if g3 and not inRaid and not inParty then return true end
            return false
        end
        -- Keeps the boolean trio in sync with the effective selection. The
        -- legacy branch mirrors the old dropdown chain exactly (including
        -- leaving the trio untouched for in_combat/out_of_combat/mouseover).
        local function SyncUnitVisBooleans(s)
            local vm = s.visibilityModes
            if type(vm) == "table" and next(vm) then
                s.showInRaid  = GroupAxisPasses(vm, true, false)
                s.showInParty = GroupAxisPasses(vm, false, true)
                s.showSolo    = GroupAxisPasses(vm, false, false)
                return
            end
            local v = s.barVisibility or "always"
            if v == "always" then
                s.showInRaid = true; s.showInParty = true; s.showSolo = true
            elseif v == "never" then
                s.showInRaid = false; s.showInParty = false; s.showSolo = false
            elseif v == "in_raid" then
                s.showInRaid = true; s.showInParty = false; s.showSolo = false
            elseif v == "in_party" then
                s.showInRaid = true; s.showInParty = true; s.showSolo = false
            elseif v == "solo" then
                s.showInRaid = false; s.showInParty = false; s.showSolo = true
            end
        end
        local visRow
        visRow, h = EllesmereUI.BuildVisibilityModeRow(W, parent, y,
            { getStore = function() return UNIT_DB_MAP[selectedUnit]() end,
              legacyKey = "barVisibility",
              caps = { partyIncludesRaid = true, luaDragonriding = true },
              refreshPageArg = true,
              -- Visibility owns only the hidden/not-hidden axis: "never"
              -- disables the frame; any visible mode re-enables it. The
              -- EUI/Blizzard style choice (frameSource, set via the inline
              -- cog) is left intact so it resumes when re-enabled.
              applyScalarFn = function(s, mode)
                  s.barVisibility = mode
                  db.profile.enabledFrames[selectedUnit] = (mode ~= "never")
              end,
              onChanged = function()
                  local s = UNIT_DB_MAP[selectedUnit]()
                  SyncUnitVisBooleans(s)
                  if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
                  ReloadAndUpdate()
                  -- Un-hiding a frame whose EUI frame isn't spawned this session
                  -- (source was Blizzard/Hidden at login) needs a /reload.
                  if (s.barVisibility or "always") ~= "never" then PromptReloadIfUnspawned({ selectedUnit }) end
              end },
            { type="dropdown", text="Visibility Options",
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end });  y = y - h

        -- Inline cog on Visibility: ONE combined popup hosting this unit's
        -- Frame Source dropdown (EllesmereUI / Blizzard Default) and the Out
        -- of Combat fade. Hiding stays on the Visibility dropdown itself
        -- ("Never Show"). The fade dims the whole frame to a chosen alpha
        -- while out of combat (100 = no fade); applied via
        -- ns.ResolveFrameAlpha inside UpdateFrameVisibility, so it reacts to
        -- combat on the existing regen path. Reuses the CDM fade's strings
        -- ("Fade Out of Combat" / "Out of Combat Alpha") so the terminology
        -- stays consistent across modules.
        -- Fade rows only join for the EllesmereUI source (the fade drives
        -- the EUI frame; a Blizzard-sourced page kept just the Frame Source
        -- picker before the merge, and still does).
        local _visSrcIsEui = ns.GetUnitFrameSource(selectedUnit) == "eui"
        AttachFrameSourceCog(visRow._leftRegion, selectedUnit, {
            title = _visSrcIsEui and "Frame Source & Fade" or "Frame Source",
            cogTooltip = _visSrcIsEui and "Frame Source & Fade" or "Frame Source",
            extraRows = _visSrcIsEui and {
                { type = "toggle", label = "Fade Out of Combat",
                  tooltip = "Fades the entire frame (portrait, health and power bars, text) while out of combat.",
                  get = function() return SVal("oocFadeEnabled", false) == true end,
                  set = function(v)
                      SSet("oocFadeEnabled", v)
                      if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
                  end },
                { type = "slider", label = "Out of Combat Alpha", min = 0, max = 100, step = 1,
                  disabled = function() return not SVal("oocFadeEnabled", false) end,
                  disabledTooltip = "Enable Fade Out of Combat first",
                  get = function() return math.floor((SVal("oocAlpha", 0.5)) * 100 + 0.5) end,
                  set = function(v)
                      SSet("oocAlpha", v / 100)
                      if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
                  end },
            },
        })

        -- When this unit isn't on the EllesmereUI frame there is nothing below
        -- to configure (its EUI frame isn't spawned): keep the Visibility row
        -- (it hosts the Frame Source cog; in the hidden state its "Never Show"
        -- is also the way back), grey it for the Blizzard source, and show the
        -- one-line notice in place of the settings.
        do
            local srcNow = ns.GetUnitFrameSource(selectedUnit)
            if srcNow ~= "eui" then
                local rightRgn = visRow._rightRegion
                if rightRgn._control then rightRgn._control:Hide() end
                if srcNow == "blizzard" then
                    -- Visibility modes only drive the EUI frame -- block the
                    -- dropdown (the cog stays live to switch back).
                    local ctl = visRow._leftRegion._control
                    if visRow._leftRegion._label then visRow._leftRegion._label:SetAlpha(0.3) end
                    local dis = CreateFrame("Frame", nil, visRow)
                    dis:SetPoint("TOPLEFT", ctl, "TOPLEFT", -2, 2)
                    dis:SetPoint("BOTTOMRIGHT", ctl, "BOTTOMRIGHT", 2, -2)
                    dis:SetFrameLevel(visRow:GetFrameLevel() + 10)
                    dis:EnableMouse(true)
                    local disTex = dis:CreateTexture(nil, "OVERLAY")
                    disTex:SetAllPoints()
                    disTex:SetColorTexture(0.06, 0.08, 0.10, 0.7)
                    dis:SetScript("OnEnter", function(self)
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("the Frame Source to be EllesmereUI"))
                    end)
                    dis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                end
                return BuildInactiveNotice(parent, y, srcNow)
            end
        end

        -- Replace the dummy right dropdown with our checkbox dropdown
        do
            local rightRgn = visRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local visItems = EllesmereUI.VIS_OPT_ITEMS
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                visItems,
                function(k) return UNIT_DB_MAP[selectedUnit]()[k] or false end,
                function(k, v)
                    UNIT_DB_MAP[selectedUnit]()[k] = v
                    if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
                    EllesmereUI:RefreshPage()
                end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            RegisterWidgetRefresh(cbDDRefresh)
        end

        -- Sync icon on Visibility (left) -- set-aware so multi-selections
        -- compare and copy correctly, running each target unit's scalar side
        -- effects (enabledFrames) and boolean-trio derivation.
        do
            local rgn = visRow._leftRegion
            local function CopyVisToUnit(key)
                local src = UNIT_DB_MAP[selectedUnit]()
                local dst = UNIT_DB_MAP[key]()
                if dst == src then return end
                EllesmereUI.VisCopySelection(dst, src, "barVisibility", nil, function(t, mode)
                    t.barVisibility = mode
                    db.profile.enabledFrames[key] = (mode ~= "never")
                end)
                SyncUnitVisBooleans(dst)
            end
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Visibility to all Frames",
                isSynced = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if not EllesmereUI.VisSelectionEquals(src, "barVisibility", UNIT_DB_MAP[key](), "barVisibility") then return false end
                    end
                    return true
                end,
                onClick = function()
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        CopyVisToUnit(key)
                    end
                    if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage(true)
                    local v = UNIT_DB_MAP[selectedUnit]().barVisibility or "always"
                    if v ~= "never" then PromptReloadIfUnspawned(GROUP_UNIT_ORDER) end
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        for _, key in ipairs(checkedKeys) do
                            CopyVisToUnit(key)
                        end
                        if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage(true)
                        local v = UNIT_DB_MAP[selectedUnit]().barVisibility or "always"
                        if v ~= "never" then PromptReloadIfUnspawned(checkedKeys) end
                    end,
                },
            })
        end

        -- Sync icon on Visibility Options (right)
        do
            local rgn = visRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Visibility Options to all Frames",
                isSynced = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    for _, item in ipairs(EllesmereUI.VIS_OPT_ITEMS) do
                        local k = item.key
                        local cur = src[k] or false
                        for _, key in ipairs(GROUP_UNIT_ORDER) do
                            if (UNIT_DB_MAP[key]()[k] or false) ~= cur then return false end
                        end
                    end
                    return true
                end,
                onClick = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    for _, item in ipairs(EllesmereUI.VIS_OPT_ITEMS) do
                        local k = item.key
                        local v = src[k] or false
                        for _, key in ipairs(GROUP_UNIT_ORDER) do
                            UNIT_DB_MAP[key]()[k] = v
                        end
                    end
                    if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
                    EllesmereUI:RefreshPage()
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local src = UNIT_DB_MAP[selectedUnit]()
                        for _, item in ipairs(EllesmereUI.VIS_OPT_ITEMS) do
                            local k = item.key
                            local v = src[k] or false
                            for _, key in ipairs(checkedKeys) do
                                UNIT_DB_MAP[key]()[k] = v
                            end
                        end
                        if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
                        EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 2: Bar Texture (per-unit + sync) | Dark Mode
        -- healthBarTexture is per-unit (drives health/power/cast/absorb). The global
        -- db.profile.healthBarTexture remains as the inherited fallback for any unit
        -- that hasn't set its own, so existing setups are unchanged until overridden.
        local barTexRow
        local hbtValues, hbtOrder = BuildBarTexDropdown()
        barTexRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Bar Texture", values=hbtValues, order=hbtOrder,
                  getValue=function() return SVal("healthBarTexture", db.profile.healthBarTexture or "none") end,
                  setValue=function(v)
                      SSet("healthBarTexture", v)
                      UpdatePreview(); EllesmereUI:RefreshPage()
                  end },
                { type="toggle", text="Dark Mode",
                  getValue=function() return db.profile.darkTheme end,
                  setValue=function(v)
                      db.profile.darkTheme = v
                      ReloadAndUpdate(); UpdatePreview()
                      EllesmereUI:RefreshPage()
                  end });  y = y - h
        -- Sync icon: Bar Texture (left region) -- pushes this unit's texture to frames
        do
            local rgn = barTexRow._leftRegion
            local function ApplyTexTo(keys)
                local src = UNIT_DB_MAP[selectedUnit]()
                local tex = src.healthBarTexture or db.profile.healthBarTexture or "none"
                for _, key in ipairs(keys) do
                    if key ~= selectedUnit then
                        UNIT_DB_MAP[key]().healthBarTexture = tex
                    end
                end
                ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
            end
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Bar Texture to all Frames",
                onClick = function() ApplyTexTo(GROUP_UNIT_ORDER) end,
                isSynced = function()
                    local g = db.profile.healthBarTexture or "none"
                    local srcTex = UNIT_DB_MAP[selectedUnit]().healthBarTexture or g
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().healthBarTexture or g) ~= srcTex then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys) ApplyTexTo(checkedKeys) end,
                },
            })
        end

        -- Row 3: Border Style (+ cog) | Border (slider + double inline swatches)
        local sharedScaleBorderRow
        local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
        sharedScaleBorderRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Border Style",
              values=texValues, order=texOrder,
              getValue=function() return SGet("borderTexture") or "solid" end,
              setValue=function(v)
                  SSet("borderTexture", v)
                  SSet("borderTextureOffset", nil)
                  SSet("borderTextureOffsetY", nil)
                  SSet("borderTextureShiftX", nil)
                  SSet("borderTextureShiftY", nil)
                  local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                  SSet("borderColor", _bcol)
                  SSet("borderAlpha", 1)
                  SSet("borderBehind", _bbehind)
                  local defSz = EllesmereUI.GetBorderDefaultSize("unitframes", v)
                  if defSz then SSet("borderSize", defSz) end
                  ReloadAndUpdate()
              end },
            { type="slider", text="Border Size",
              min=0, max=4, step=1, trackWidth=120,
              getValue=function() return SVal("borderSize", 1) end,
              setValue=function(v)
                  SSet("borderSize", v); ReloadAndUpdate()
              end });  y = y - h
        -- Inline cog for border offset (left region)
        do
            local rgn = sharedScaleBorderRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Border Offset",
                rows = {
                    { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                      get = function()
                          local v = SGet("borderTextureOffset")
                          if v then return v end
                          local tex = SGet("borderTexture") or "solid"
                          local sz = SVal("borderSize", 1)
                          local dox = EllesmereUI.GetBorderDefaults("unitframes", tex, sz)
                          return dox
                      end,
                      set = function(v)
                          SSet("borderTextureOffset", v); ReloadAndUpdate()
                      end },
                    { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                      get = function()
                          local v = SGet("borderTextureOffsetY")
                          if v then return v end
                          local tex = SGet("borderTexture") or "solid"
                          local sz = SVal("borderSize", 1)
                          local _, doy = EllesmereUI.GetBorderDefaults("unitframes", tex, sz)
                          return doy
                      end,
                      set = function(v)
                          SSet("borderTextureOffsetY", v); ReloadAndUpdate()
                      end },
                    { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                      get = function()
                          local v = SGet("borderTextureShiftX")
                          if v then return v end
                          local tex = SGet("borderTexture") or "solid"
                          local sz = SVal("borderSize", 1)
                          local _, _, dsx = EllesmereUI.GetBorderDefaults("unitframes", tex, sz)
                          return dsx
                      end,
                      set = function(v)
                          SSet("borderTextureShiftX", v == 0 and nil or v); ReloadAndUpdate()
                      end },
                    { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                      get = function()
                          local v = SGet("borderTextureShiftY")
                          if v then return v end
                          local tex = SGet("borderTexture") or "solid"
                          local sz = SVal("borderSize", 1)
                          local _, _, _, dsy = EllesmereUI.GetBorderDefaults("unitframes", tex, sz)
                          return dsy
                      end,
                      set = function(v)
                          SSet("borderTextureShiftY", v == 0 and nil or v); ReloadAndUpdate()
                      end },
                    { type = "toggle", label = "Show Behind",
                      get = function() return SVal("borderBehind", false) end,
                      set = function(v) SSet("borderBehind", v); ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local function UpdateCogVis()
                local tex = SGet("borderTexture") or "solid"
                if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
        -- Sync icon: Border Style (left region - dropdown)
        do
            local bsLeftRgn = sharedScaleBorderRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = bsLeftRgn,
                tooltip = "Apply Border Style to all Frames",
                onClick = function()
                    local bt = SGet("borderTexture") or "solid"
                    local ox = SGet("borderTextureOffset")
                    local oy = SGet("borderTextureOffsetY")
                    local sx = SGet("borderTextureShiftX")
                    local sy = SGet("borderTextureShiftY")
                    local bh = SGet("borderBehind")
                    local bc = SGet("borderColor")
                    local ba = SGet("borderAlpha")
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then
                            UNIT_DB_MAP[key]().borderTexture = bt
                            UNIT_DB_MAP[key]().borderTextureOffset = ox
                            UNIT_DB_MAP[key]().borderTextureOffsetY = oy
                            UNIT_DB_MAP[key]().borderTextureShiftX = sx
                            UNIT_DB_MAP[key]().borderTextureShiftY = sy
                            UNIT_DB_MAP[key]().borderBehind = bh
                            if bc then UNIT_DB_MAP[key]().borderColor = { r=bc.r, g=bc.g, b=bc.b } end
                            UNIT_DB_MAP[key]().borderAlpha = ba
                        end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local bt = SGet("borderTexture") or "solid"
                    local ox = SGet("borderTextureOffset")
                    local oy = SGet("borderTextureOffsetY")
                    local sx = SGet("borderTextureShiftX")
                    local sy = SGet("borderTextureShiftY")
                    local bh = SGet("borderBehind") or false
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().borderTexture or "solid") ~= bt then return false end
                        if UNIT_DB_MAP[key]().borderTextureOffset ~= ox then return false end
                        if UNIT_DB_MAP[key]().borderTextureOffsetY ~= oy then return false end
                        if UNIT_DB_MAP[key]().borderTextureShiftX ~= sx then return false end
                        if UNIT_DB_MAP[key]().borderTextureShiftY ~= sy then return false end
                        if (UNIT_DB_MAP[key]().borderBehind or false) ~= bh then return false end
                    end
                    return true
                end,
                flashTargets = function() return { bsLeftRgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local bt = SGet("borderTexture") or "solid"
                        local ox = SGet("borderTextureOffset")
                        local oy = SGet("borderTextureOffsetY")
                        local sx = SGet("borderTextureShiftX")
                        local sy = SGet("borderTextureShiftY")
                        local bh = SGet("borderBehind")
                        local bc = SGet("borderColor")
                        local ba = SGet("borderAlpha")
                        for _, key in ipairs(checkedKeys) do
                            UNIT_DB_MAP[key]().borderTexture = bt
                            UNIT_DB_MAP[key]().borderTextureOffset = ox
                            UNIT_DB_MAP[key]().borderTextureOffsetY = oy
                            UNIT_DB_MAP[key]().borderTextureShiftX = sx
                            UNIT_DB_MAP[key]().borderTextureShiftY = sy
                            UNIT_DB_MAP[key]().borderBehind = bh
                            if bc then UNIT_DB_MAP[key]().borderColor = { r=bc.r, g=bc.g, b=bc.b } end
                            UNIT_DB_MAP[key]().borderAlpha = ba
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        -- Sync icon: Border (right region - border slider)
        do
            local rgn = sharedScaleBorderRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Border to all Frames",
                onClick = function()
                    local bs = SVal("borderSize", 1)
                    local bc = SGet("borderColor")
                    local ba = SGet("borderAlpha")
                    local bt = SGet("borderTexture") or "solid"
                    local hc = SGet("highlightColor")
                    local ha = SGet("highlightAlpha")
                    local sx = SGet("borderTextureShiftX")
                    local sy = SGet("borderTextureShiftY")
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then
                            UNIT_DB_MAP[key]().borderSize = bs
                            if bc then UNIT_DB_MAP[key]().borderColor = { r=bc.r, g=bc.g, b=bc.b } end
                            if ba then UNIT_DB_MAP[key]().borderAlpha = ba end
                            UNIT_DB_MAP[key]().borderTexture = bt
                            UNIT_DB_MAP[key]().borderTextureShiftX = sx
                            UNIT_DB_MAP[key]().borderTextureShiftY = sy
                            if hc then UNIT_DB_MAP[key]().highlightColor = { r=hc.r, g=hc.g, b=hc.b } end
                            if ha then UNIT_DB_MAP[key]().highlightAlpha = ha end
                        end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local bs = SVal("borderSize", 1)
                    local bt = SGet("borderTexture") or "solid"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().borderSize or 1) ~= bs then return false end
                        if (UNIT_DB_MAP[key]().borderTexture or "solid") ~= bt then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local bs = SVal("borderSize", 1)
                        local bc = SGet("borderColor")
                        local ba = SGet("borderAlpha")
                        local bt = SGet("borderTexture") or "solid"
                        local hc = SGet("highlightColor")
                        local ha = SGet("highlightAlpha")
                        local sx = SGet("borderTextureShiftX")
                        local sy = SGet("borderTextureShiftY")
                        for _, key in ipairs(checkedKeys) do
                            UNIT_DB_MAP[key]().borderSize = bs
                            if bc then UNIT_DB_MAP[key]().borderColor = { r=bc.r, g=bc.g, b=bc.b } end
                            if ba then UNIT_DB_MAP[key]().borderAlpha = ba end
                            UNIT_DB_MAP[key]().borderTexture = bt
                            UNIT_DB_MAP[key]().borderTextureShiftX = sx
                            UNIT_DB_MAP[key]().borderTextureShiftY = sy
                            if hc then UNIT_DB_MAP[key]().highlightColor = { r=hc.r, g=hc.g, b=hc.b } end
                            if ha then UNIT_DB_MAP[key]().highlightAlpha = ha end
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        -- Inline Border color swatch on the Border slider. The Highlight swatch
        -- moved to the "Hover Borders" dropdown below (same highlightColor var).
        do
            local leftRgn = sharedScaleBorderRow._rightRegion
            local ctrl = leftRgn._control
            local PP = EllesmereUI.PP

            -- Border color (with alpha)
            local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                leftRgn, sharedScaleBorderRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("borderColor") or { r = 0, g = 0, b = 0 }
                    return c.r, c.g, c.b, SVal("borderAlpha", 1)
                end,
                function(r, g, b, a)
                    UNIT_DB_MAP[selectedUnit]().borderColor = { r=r, g=g, b=b }
                    UNIT_DB_MAP[selectedUnit]().borderAlpha = a
                    ReloadAndUpdate()
                end,
                true, 20)
            PP.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            borderSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(borderSwatch, "Border")
            end)
            borderSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch() end)
        end

        -- Row 4: Show Tooltip | Frame Strata
        local ufStrataValues = { BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium", HIGH = "High", DIALOG = "Dialog" }
        local ufStrataOrder = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Tooltip",
              getValue=function() return SVal("showUnitTooltip", true) end,
              setValue=function(v)
                  local keys = GROUP_UNIT_ORDER or {"player", "target", "focus"}
                  for _, key in ipairs(keys) do
                      UNIT_DB_MAP[key]().showUnitTooltip = v
                  end
                  ReloadAndUpdate()
              end },
            { type="dropdown", text="Frame Strata",
              tooltip="Controls the order that overlapping elements display in. Set higher to show above other elements.",
              values = ufStrataValues, order = ufStrataOrder,
              getValue=function() return db.profile.frameStrata or "MEDIUM" end,
              setValue=function(v)
                  db.profile.frameStrata = v
                  ReloadAndUpdate()
              end });  y = y - h

        -- Cog on Frame Strata: custom bar stratas for detached power/text bar
        do
            local strataRgn = _
            if strataRgn and strataRgn._rightRegion then strataRgn = strataRgn._rightRegion end
            local barStrataValues = { BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium", HIGH = "High", DIALOG = "Dialog" }
            local barStrataOrder = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Detached Bar Stratas",
                rows = {
                    { type="toggle", label="Custom Bar Stratas",
                      get=function() return db.profile.enableCustomBarStratas or false end,
                      set=function(v) db.profile.enableCustomBarStratas = v; ReloadAndUpdate() end },
                    { type="dropdown", label="Detached Power Bar", values=barStrataValues, order=barStrataOrder,
                      get=function() return db.profile.detachedPowerStrata or "HIGH" end,
                      set=function(v) db.profile.detachedPowerStrata = v; ReloadAndUpdate() end },
                    { type="dropdown", label="Detached Text Bar", values=barStrataValues, order=barStrataOrder,
                      get=function() return db.profile.detachedTextBarStrata or "DIALOG" end,
                      set=function(v) db.profile.detachedTextBarStrata = v; ReloadAndUpdate() end },
                },
            })
            if strataRgn then
                MakeCogBtn(strataRgn, cogShow)
            end
        end

        -- Show Decimal on Health Text (global): one decimal on health value
        -- (240.5k) and health percent (77.3%) for every unit. Default off.
        local decRow
        decRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Decimal on Health Text",
              tooltip="Show one decimal place on health text: health values like 240.5k and health percent like 77.3%. Power text is unaffected. Off by default.",
              getValue=function() return db.profile.showDecimalOnText end,
              setValue=function(v)
                  db.profile.showDecimalOnText = v
                  if ns.ApplyTextDecimalGlobals then ns.ApplyTextDecimalGlobals() end
                  ReloadAndUpdate(); UpdatePreview()
                  EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Hover Borders",
              values={ __placeholder = "All" }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end });  y = y - h
        -- Smaller dimmed "(Applies to All Units)" subtitle next to the label
        -- (mirrors the CDM "Anchor to Cursor" subtitle pattern).
        do
            local suffix = decRow._leftRegion:CreateFontString(nil, "OVERLAY")
            suffix:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
            suffix:SetTextColor(1, 1, 1, 0.35)
            suffix:SetText(EllesmereUI.L("(Applies to All Units)"))
            local lbl
            for i = 1, decRow._leftRegion:GetNumRegions() do
                local reg = select(i, decRow._leftRegion:GetRegions())
                if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Show Decimal on Health Text" then
                    lbl = reg; break
                end
            end
            if lbl then
                suffix:SetPoint("LEFT", lbl, "RIGHT", 5, 0)
            else
                suffix:SetPoint("LEFT", decRow._leftRegion, "LEFT", 120, 0)
            end
        end

        -- Inline cog on the toggle: extra decimal options. "Show 2 for Boss"
        -- (default on) gives boss frames a second decimal place when decimals
        -- are enabled. Greyed out while the master decimal toggle is off.
        do
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Health Text Decimals",
                rows = {
                    { type="toggle", label="Only Show for % Health",
                      get=function() return db.profile.showDecimalPercentOnly == true end,
                      set=function(v)
                          db.profile.showDecimalPercentOnly = v
                          if ns.ApplyTextDecimalGlobals then ns.ApplyTextDecimalGlobals() end
                          ReloadAndUpdate(); UpdatePreview()
                      end },
                    { type="toggle", label="Show 2 for Boss",
                      get=function() return db.profile.showDecimalBoss2 ~= false end,
                      set=function(v)
                          db.profile.showDecimalBoss2 = v
                          if ns.ApplyTextDecimalGlobals then ns.ApplyTextDecimalGlobals() end
                          ReloadAndUpdate(); UpdatePreview()
                      end },
                },
            })
            MakeCogBtn(decRow._leftRegion, cogShow, nil, nil,
                function() return not db.profile.showDecimalOnText end)
        end

        -- Hover Borders dropdown (mirrors Raid Frames): Highlight (per-unit hover
        -- highlight border) + Player Threat (player frame only, global). Inline
        -- swatches: Highlight / Has Aggro / Close to Aggro.
        do
            local rightRgn = decRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local isPlayer = (selectedUnit == "player")
            local hbItems = { { key = "highlight", label = "Highlight" } }
            if isPlayer then
                hbItems[#hbItems + 1] = {
                    key = "playerThreat",
                    label = "Player Threat (Non-Tank)",
                    tooltip = "Adds a Shadow border to your player frame when you pull or hold threat as a non-tank. Only active in dungeons, raids and delves.",
                }
            end
            local UpdateHBSwatchVis  -- forward declare; assigned after swatches
            local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                rightRgn, 170, rightRgn:GetFrameLevel() + 2,
                hbItems,
                function(k)
                    -- Highlight is shared across all 3 main frames; read the player copy.
                    if k == "highlight" then return UNIT_DB_MAP.player().highlightEnabled ~= false end
                    if k == "playerThreat" then return db.profile.playerThreatBorderEnabled or false end
                    return false
                end,
                function(k, v)
                    if k == "highlight" then
                        -- Shared across all 3 main frames: changing it on player/target/
                        -- focus applies to all of them. (Threat stays player-only below.)
                        for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().highlightEnabled = v end
                        ReloadAndUpdate()
                    elseif k == "playerThreat" then
                        db.profile.playerThreatBorderEnabled = v
                        if ns.SetPlayerThreatEnabled then ns.SetPlayerThreatEnabled(v) end
                    end
                    if UpdateHBSwatchVis then UpdateHBSwatchVis() end
                end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil

            local lvl = decRow:GetFrameLevel() + 3
            -- Highlight swatch (per-unit), nearest the dropdown.
            local hlSwatch, updHl = EllesmereUI.BuildColorSwatch(
                rightRgn, lvl,
                function()
                    local c = UNIT_DB_MAP.player().highlightColor or { r = 1, g = 1, b = 1 }
                    return c.r, c.g, c.b, UNIT_DB_MAP.player().highlightAlpha or 1
                end,
                function(r, g, b, a)
                    -- Shared across all 3 main frames (see Highlight enable above).
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local d = UNIT_DB_MAP[key]()
                        d.highlightColor = { r=r, g=g, b=b }
                        d.highlightAlpha = a
                    end
                    ReloadAndUpdate()
                end, true, 20)
            hlSwatch:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
            rightRgn._lastInline = hlSwatch
            hlSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(hlSwatch, "Highlight") end)
            hlSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local hasSwatch, updHas, nearSwatch, updNear
            if isPlayer then
                -- Has Aggro swatch (global), left of Highlight.
                hasSwatch, updHas = EllesmereUI.BuildColorSwatch(
                    rightRgn, lvl,
                    function()
                        local c = db.profile.playerThreatHasAggroColor or { r = 1, g = 0.5, b = 0 }
                        return c.r, c.g, c.b, 1
                    end,
                    function(r, g, b)
                        db.profile.playerThreatHasAggroColor = { r=r, g=g, b=b }
                        if ns.UpdatePlayerThreatBorder then ns.UpdatePlayerThreatBorder() end
                    end, false, 20)
                hasSwatch:SetPoint("RIGHT", rightRgn._lastInline, "LEFT", -8, 0)
                rightRgn._lastInline = hasSwatch
                hasSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(hasSwatch, "Has Aggro") end)
                hasSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                -- Close to Aggro swatch (global), left of Has Aggro.
                nearSwatch, updNear = EllesmereUI.BuildColorSwatch(
                    rightRgn, lvl,
                    function()
                        local c = db.profile.playerThreatNearAggroColor or { r = 0.81, g = 0.72, b = 0.19 }
                        return c.r, c.g, c.b, 1
                    end,
                    function(r, g, b)
                        db.profile.playerThreatNearAggroColor = { r=r, g=g, b=b }
                        if ns.UpdatePlayerThreatBorder then ns.UpdatePlayerThreatBorder() end
                    end, false, 20)
                nearSwatch:SetPoint("RIGHT", rightRgn._lastInline, "LEFT", -8, 0)
                rightRgn._lastInline = nearSwatch
                nearSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(nearSwatch, "Close to Aggro") end)
                nearSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end

            -- Gray a swatch when its toggle is off (still clickable to pre-set).
            UpdateHBSwatchVis = function()
                hlSwatch:SetAlpha(UNIT_DB_MAP.player().highlightEnabled ~= false and 1 or 0.3)
                if hasSwatch then
                    local on = db.profile.playerThreatBorderEnabled
                    hasSwatch:SetAlpha(on and 1 or 0.3)
                    nearSwatch:SetAlpha(on and 1 or 0.3)
                end
            end
            EllesmereUI.RegisterWidgetRefresh(function()
                updHl(); if updHas then updHas() end; if updNear then updNear() end; UpdateHBSwatchVis()
            end)
            UpdateHBSwatchVis()
        end

        -- Show Nicknames: global master toggle for ALL main frames (player /
        -- target / focus), default OFF. Gates ns.ResolveUnitNickname -- off shows
        -- raw unit names, on shows nicknames from supported providers. Not
        -- per-frame: one switch drives every main frame.
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Nicknames",
              tooltip="Show player nicknames from supported addons instead of character names on your main frames.",
              getValue=function() return db.profile.showNicknames or false end,
              setValue=function(v)
                  db.profile.showNicknames = v
                  if ns.RefreshAllUnitNames then ns.RefreshAllUnitNames() end
              end },
            { type="label", text="" });  y = y - h

        _, h = W:Spacer(parent, y, 20); y = y - h

        -------------------------------------------------------------------
        --  PORTRAIT
        -------------------------------------------------------------------
        local sharedPortraitHeader
        sharedPortraitHeader, h = W:SectionHeader(parent, "PORTRAIT", y); y = y - h

        -- Forward declarations for cross-row updates
        local sharedDetShapeRow
        local sharedDetSizeRow

        -- Row 1: Portrait Mode + Art Style
        local sharedPortraitModeRow
        sharedPortraitModeRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Portrait Mode", values=portraitModeValues2, order=portraitModeOrder2,
              getValue=function()
                  return SVal("portraitStyle", "attached")
              end,
              setValue=function(v)
                  -- Any mode change flips row visibility below (Size/Position
                  -- hidden at None, Shape row detached-only), so a real change
                  -- forces the full rebuild at the end of this setter.
                  local prevStyle = SVal("portraitStyle", "attached")
                  SSet("portraitStyle", v)
                  -- Auto-set shape to "none" when entering detached + 3D
                  if v == "detached" and SVal("portraitMode", "2d") == "3d" then
                      UNIT_DB_MAP[selectedUnit]().detachedPortraitShape = "none"
                  end
                  -- Reset detached-only settings when leaving detached mode
                  if v ~= "detached" then
                      UNIT_DB_MAP[selectedUnit]().portraitSize = 0
                      local side = UNIT_DB_MAP[selectedUnit]().portraitSide
                      if side == "top" or side == "insideleft" or side == "insideright" or side == "insidecenter" then
                          UNIT_DB_MAP[selectedUnit]().portraitSide = "left"
                      end
                  end
                  UNIT_DB_MAP[selectedUnit]().showPortrait = (v ~= "none")
                  UpdatePreview()
                  if v ~= prevStyle then
                      EllesmereUI:RefreshPage(true)
                      return
                  end
                  C_Timer.After(0, function() local rl = EllesmereUI._widgetRefreshList; if rl then for i = 1, #rl do rl[i]() end end end)
              end },
            { type="dropdown", text="Art Style", values=portraitArtValues, order=portraitArtOrder,
              disabled=function() return SVal("portraitStyle", "attached") == "none" end,
              disabledTooltip="Portrait Mode is set to None", rawTooltip=true,
              getValue=function()
                  local v = SGet("portraitMode")
                  if v == "class" then return SVal("classThemeStyle", "modern") end
                  return v or "2d"
              end,
              setValue=function(v)
                  if v == "3d" then
                      local curVal = SVal("portraitMode", "2d")
                      if curVal ~= "3d" and not (EllesmereUIDB and EllesmereUIDB.dismissed3DWarning) then
                          EllesmereUI:ShowConfirmPopup({
                              title       = "3D Portraits",
                              message     = "3D portraits may cause a slight loss in performance efficiency. Do you want to enable them?",
                              confirmText = "Enable",
                              cancelText  = "Cancel",
                              onConfirm   = function()
                                  if not EllesmereUIDB then EllesmereUIDB = {} end
                                  EllesmereUIDB.dismissed3DWarning = true
                                  UNIT_DB_MAP[selectedUnit]().portraitMode = "3d"
                                  UNIT_DB_MAP[selectedUnit]().showPortrait = true
                                  if UNIT_DB_MAP[selectedUnit]().portraitStyle == "detached" then
                                      UNIT_DB_MAP[selectedUnit]().detachedPortraitShape = "none"
                                  end
                                  ReloadAndUpdate(); UpdatePreview()
                                  if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
                              end,
                              onCancel    = function()
                                  if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
                              end,
                          })
                          return
                      end
                  end
                  UNIT_DB_MAP[selectedUnit]().portraitMode = v
                  UNIT_DB_MAP[selectedUnit]().showPortrait = true
                  -- Auto-set shape to "none" when entering 3D + detached
                  if v == "3d" and UNIT_DB_MAP[selectedUnit]().portraitStyle == "detached" then
                      UNIT_DB_MAP[selectedUnit]().detachedPortraitShape = "none"
                  end
                  -- 3D-only options: reset when leaving 3D
                  if v ~= "3d" then
                      if UNIT_DB_MAP[selectedUnit]().detachedPortraitShape == "none" then
                          UNIT_DB_MAP[selectedUnit]().detachedPortraitShape = "portrait"
                      end
                      local side = UNIT_DB_MAP[selectedUnit]().portraitSide
                      if side == "insideleft" or side == "insideright" or side == "insidecenter" then
                          UNIT_DB_MAP[selectedUnit]().portraitSide = "left"
                      end
                  end
                  ReloadAndUpdate(); UpdatePreview()
              end });  y = y - h
        -- Sync icon: Portrait Mode (Style)
        do
            local rgn = sharedPortraitModeRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Portrait Mode to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().portraitStyle or "attached"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then
                            UNIT_DB_MAP[key]().portraitStyle = v
                            UNIT_DB_MAP[key]().showPortrait = (v ~= "none")
                        end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().portraitStyle or "attached"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().portraitStyle or "attached") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().portraitStyle or "attached"
                        for _, key in ipairs(checkedKeys) do
                            UNIT_DB_MAP[key]().portraitStyle = v
                            UNIT_DB_MAP[key]().showPortrait = (v ~= "none")
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        -- Sync icon: Portrait Mode (Art Style)
        do
            local rgn = sharedPortraitModeRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Art Style to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().portraitMode
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then UNIT_DB_MAP[key]().portraitMode = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().portraitMode or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().portraitMode or "none") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().portraitMode
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().portraitMode = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 2: Size + Position. HIDDEN entirely while Portrait Mode is None
        -- (the mode dropdown's setValue forces the rebuild on any mode change).
        if SVal("portraitStyle", "attached") ~= "none" then
        local portraitLocationValues = {
            ["left"] = "Left", ["right"] = "Right", ["top"] = "Top",
            ["insideleft"] = "Inside Left", ["insideright"] = "Inside Right", ["insidecenter"] = "Inside Center",
        }
        local portraitLocationOrder = { "left", "right", "top", "insideleft", "insideright", "insidecenter" }
        local sharedSizePosRow
        sharedSizePosRow, h = W:DualRow(parent, y,
            { type="slider", text="Size", min=-20, max=100, step=1,
              disabled=function()
                  local style = SVal("portraitStyle", "attached")
                  local side = SVal("portraitSide", "left")
                  local isInside = side == "insideleft" or side == "insideright" or side == "insidecenter"
                  return style ~= "detached" and not isInside
              end,
              disabledTooltip="Only available in Detached or Inside modes", rawTooltip=true,
              getValue=function() return SVal("portraitSize", 0) end,
              setValue=function(v) SSet("portraitSize", v); UpdatePreview() end },
            { type="dropdown", text="Position", values=portraitLocationValues, order=portraitLocationOrder,
              itemDisabled=function(v)
                  local pStyle = SVal("portraitStyle", "attached")
                  if v == "top" and pStyle == "attached" then return true end
                  if v == "insideleft" or v == "insideright" or v == "insidecenter" then
                      if SVal("portraitMode", "2d") ~= "3d" then return true end
                      if pStyle ~= "detached" then return true end
                  end
                  return false
              end,
              itemDisabledTooltip=function(v)
                  if v == "top" then return "Top position is only available in Detached mode" end
                  if v == "insideleft" or v == "insideright" or v == "insidecenter" then
                      if SVal("portraitMode", "2d") ~= "3d" then return "Inside positions require 3D Art Style" end
                      return "Inside positions require Detached mode"
                  end
              end,
              getValue=function() return SVal("portraitSide", "left") end,
              setValue=function(v) SSet("portraitSide", v); UpdatePreview() end });  y = y - h
        -- Sync icons: Portrait Size (left) and Portrait Side (right)
        do
            local rgn = sharedSizePosRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Portrait Size to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().portraitSize or 0
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then UNIT_DB_MAP[key]().portraitSize = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().portraitSize or 0
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().portraitSize or 0) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().portraitSize or 0
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().portraitSize = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
            -- Zoom cog on Size slider
            local _, zoomCogShow = EllesmereUI.BuildCogPopup({
                title = "Portrait Zoom",
                rows = {
                    { type="slider", label="2D Zoom", min=50, max=100, step=1,
                      get=function() return SVal("portraitArtScale", 100) end,
                      set=function(v) SSet("portraitArtScale", v); UpdatePreview() end },
                    { type="slider", label="3D Zoom", min=100, max=300, step=1,
                      get=function() return SVal("portrait3dZoom", 100) end,
                      set=function(v) SSet("portrait3dZoom", v); UpdatePreview() end },
                },
            })
            MakeCogBtn(rgn, zoomCogShow)
        end
        do
            local rgn = sharedSizePosRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Portrait Position to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().portraitSide or "left"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then UNIT_DB_MAP[key]().portraitSide = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().portraitSide or "left"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().portraitSide or "left") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().portraitSide or "left"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().portraitSide = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        sharedDetSizeRow = sharedSizePosRow
        -- Cog on Position for X/Y offsets
        do
            local posRgn = sharedSizePosRow._rightRegion
            local _, posCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Portrait Position Offsets",
                rows = {
                    { type="slider", label="X Offset", min=-100, max=100, step=1,
                      get=function() return SVal("portraitX", 0) end,
                      set=function(v) SSet("portraitX", v); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-100, max=100, step=1,
                      get=function() return SVal("portraitY", 0) end,
                      set=function(v) SSet("portraitY", v); UpdatePreview() end },
                },
            })
            local posCogShow = posCogShowRaw
            local cogBtn = MakeCogBtn(posRgn, posCogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local function UpdatePosCogState()
                local pStyle = SVal("portraitStyle", "attached")
                if pStyle == "detached" then cogBtn:SetAlpha(0.4); cogBtn:Enable()
                else cogBtn:SetAlpha(0.15); cogBtn:Disable() end
            end
            cogBtn:SetScript("OnEnter", function(self)
                if SVal("portraitStyle", "attached") == "detached" then
                    self:SetAlpha(0.7)
                else
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires Portrait Mode to be set to Detached."))
                end
            end)
            cogBtn:SetScript("OnLeave", function(self) UpdatePosCogState(); EllesmereUI.HideWidgetTooltip() end)
            cogBtn:SetScript("OnClick", function(self) posCogShow(self) end)
            UpdatePosCogState()
            RegisterWidgetRefresh(UpdatePosCogState)
        end
        end   -- close Size/Position hidden-at-None gate

        -- Row 3: Shape + Shape Border (color swatch + cog). HIDDEN unless
        -- Portrait Mode is Detached (Attached and None both hide it; the mode
        -- dropdown's setValue forces the rebuild on any mode change).
        if SVal("portraitStyle", "attached") == "detached" then
        local sharedShapeBorderRow
        sharedShapeBorderRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Shape", values=detPortraitShapeValues, order=detPortraitShapeOrder,
              itemDisabled=function(v) return v == "none" and SVal("portraitMode", "2d") ~= "3d" end,
              itemDisabledTooltip=function(v) if v == "none" then return "None shape requires 3D Art Style" end end,
              getValue=function() return SVal("detachedPortraitShape", "portrait") end,
              setValue=function(v)
                  SSet("detachedPortraitShape", v); UpdatePreview()
              end },
            { type="multiSwatch", text="Shape Border",
              swatches = {
                { tooltip = "Custom Color",
                  hasAlpha = false,
                  getValue = function()
                      local c = SGet("detachedPortraitBorderColor")
                      c = c or { r=0, g=0, b=0 }
                      return c.r, c.g, c.b
                  end,
                  setValue = function(r, g, b)
                      UNIT_DB_MAP[selectedUnit]().detachedPortraitBorderColor = { r=r, g=g, b=b }
                      ReloadAndUpdate(); UpdatePreview()
                  end,
                  onClick = function(self)
                      if SVal("detachedPortraitClassColor", true) then
                          SSet("detachedPortraitClassColor", false)
                          ReloadAndUpdate(); UpdatePreview()
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      return SVal("detachedPortraitClassColor", true) and 0.3 or 1
                  end },
                { tooltip = "Class Colored",
                  hasAlpha = false,
                  getValue = function()
                      local _, ct = UnitClass("player")
                      if ct and RAID_CLASS_COLORS[ct] then
                          local cc = RAID_CLASS_COLORS[ct]
                          return cc.r, cc.g, cc.b
                      end
                      return 1, 1, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      SSet("detachedPortraitClassColor", true)
                      ReloadAndUpdate(); UpdatePreview()
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      return SVal("detachedPortraitClassColor", true) and 1 or 0.3
                  end },
              } });  y = y - h
        -- Cog on Shape Border for border settings
        do
            local borderRgn = sharedShapeBorderRow._rightRegion
            local _, detShapeCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Shape Border Settings",
                rows = {
                    { type="slider", label="Size", min=1, max=7, step=1,
                      get=function() return SVal("detachedPortraitBorderSize", 7) end,
                      set=function(v) SSet("detachedPortraitBorderSize", v); UpdatePreview() end },
                    { type="slider", label="Opacity", min=0, max=100, step=1,
                      get=function() return SVal("detachedPortraitBorderOpacity", 100) end,
                      set=function(v) SSet("detachedPortraitBorderOpacity", v); UpdatePreview() end },
                },
            })
            local detShapeCogShow = detShapeCogShowRaw
            local cogBtn = MakeCogBtn(borderRgn, detShapeCogShow)
            local function UpdateDetShapeCogState()
                local pStyle = SVal("portraitStyle", "attached")
                if pStyle == "detached" then cogBtn:SetAlpha(0.4); cogBtn:Enable()
                else cogBtn:SetAlpha(0.15); cogBtn:Disable() end
            end
            cogBtn:SetScript("OnEnter", function(self)
                if SVal("portraitStyle", "attached") == "detached" then
                    self:SetAlpha(0.7)
                else
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option is only available when Portrait Mode is Detached."))
                end
            end)
            cogBtn:SetScript("OnLeave", function(self) UpdateDetShapeCogState(); EllesmereUI.HideWidgetTooltip() end)
            cogBtn:SetScript("OnClick", function(self) detShapeCogShow(self) end)
            UpdateDetShapeCogState()
            RegisterWidgetRefresh(UpdateDetShapeCogState)
        end
        -- Sync icons: Shape (left) and Shape Border (right)
        do
            local rgn = sharedShapeBorderRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Portrait Shape to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().detachedPortraitShape or "portrait"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then UNIT_DB_MAP[key]().detachedPortraitShape = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().detachedPortraitShape or "portrait"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().detachedPortraitShape or "portrait") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().detachedPortraitShape or "portrait"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().detachedPortraitShape = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = sharedShapeBorderRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Shape Border to all Frames",
                onClick = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    local bc = src.detachedPortraitBorderColor
                    local bo = src.detachedPortraitBorderOpacity
                    local bs = src.detachedPortraitBorderSize
                    local cc = src.detachedPortraitClassColor
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then
                            local d = UNIT_DB_MAP[key]()
                            if bc then d.detachedPortraitBorderColor = { r=bc.r, g=bc.g, b=bc.b }
                            else d.detachedPortraitBorderColor = nil end
                            d.detachedPortraitBorderOpacity = bo
                            d.detachedPortraitBorderSize = bs
                            d.detachedPortraitClassColor = cc
                        end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    local cc = src.detachedPortraitClassColor
                    if cc == nil then cc = true end
                    local bs = src.detachedPortraitBorderSize or 7
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local d = UNIT_DB_MAP[key]()
                        local dcc = d.detachedPortraitClassColor
                        if dcc == nil then dcc = true end
                        if dcc ~= cc then return false end
                        if (d.detachedPortraitBorderSize or 7) ~= bs then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local src = UNIT_DB_MAP[selectedUnit]()
                        local bc = src.detachedPortraitBorderColor
                        local bo = src.detachedPortraitBorderOpacity
                        local bs = src.detachedPortraitBorderSize
                        local cc = src.detachedPortraitClassColor
                        for _, key in ipairs(checkedKeys) do
                            local d = UNIT_DB_MAP[key]()
                            if bc then d.detachedPortraitBorderColor = { r=bc.r, g=bc.g, b=bc.b }
                            else d.detachedPortraitBorderColor = nil end
                            d.detachedPortraitBorderOpacity = bo
                            d.detachedPortraitBorderSize = bs
                            d.detachedPortraitClassColor = cc
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        end   -- close Shape/Shape Border detached-only gate

        _, h = W:Spacer(parent, y, 20); y = y - h

        -------------------------------------------------------------------
        --  HEALTH BAR
        -------------------------------------------------------------------
        local sharedBarsHeader
        sharedBarsHeader, h = W:SectionHeader(parent, "HEALTH BAR", y); y = y - h

        -- Row 1: Bar Height + Bar Width (was Frame Width)
        local sharedSizeRow
        local ufhDis, ufhTip, ufhRaw = EllesmereUI.MatchGuard(selectedUnit, "Height")
        local ufwDis, ufwTip, ufwRaw = EllesmereUI.MatchGuard(selectedUnit, "Width")
        sharedSizeRow, h = W:DualRow(parent, y,
            { type="slider", text="Health Bar Height", min=15, max=100, step=1,
              disabled=ufhDis, disabledTooltip=ufhTip, rawTooltip=ufhRaw,
              getValue=function() return SVal("healthHeight", 46) end,
              setValue=function(v) SSet("healthHeight", v) end },
            { type="slider", text="Bar Width", min=80, max=400, step=1,
              disabled=ufwDis, disabledTooltip=ufwTip, rawTooltip=ufwRaw,
              getValue=function() return SVal("frameWidth", 181) end,
              setValue=function(v) SSet("frameWidth", v) end });  y = y - h
        -- Sync icons: Bar Height (left) and Bar Width (right)
        do
            local rgn = sharedSizeRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Health Bar Height to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().healthHeight or 46
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then UNIT_DB_MAP[key]().healthHeight = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().healthHeight or 46
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().healthHeight or 46) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().healthHeight or 46
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().healthHeight = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        -- Reverse Fill cog on Bar Height (left region)
        do
            local rgn = sharedSizeRow._leftRegion
            local _, revCogShow = EllesmereUI.BuildCogPopup({
                title = "Health Bar Fill",
                rows = {
                    { type="toggle", label="Reverse Fill",
                      get=function() return SVal("healthReverseFill", false) end,
                      set=function(v) SSet("healthReverseFill", v); ReloadAndUpdate(); UpdatePreview() end },
                },
            })
            MakeCogBtn(rgn, revCogShow)
        end
        do
            local rgn = sharedSizeRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Bar Width to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().frameWidth or 181
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then UNIT_DB_MAP[key]().frameWidth = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().frameWidth or 181
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().frameWidth or 181) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().frameWidth or 181
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().frameWidth = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 2: Bar Color (multiSwatch) + Bar Background (slider + inline swatch)
        local sharedHealthColorRow
        sharedHealthColorRow, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Fill Color",
              swatches = {
                { tooltip = "Gradient End Color", hasAlpha = false,
                  disabled = function() return not SVal("gradientEnabled", false) end,
                  disabledTooltip = function() return "Gradient" end,
                  getValue = function()
                      local c = SGet("gradientColor")
                      if c then return c.r, c.g, c.b end
                      return 0.20, 0.20, 0.80
                  end,
                  setValue = function(r, g, b)
                      UNIT_DB_MAP[selectedUnit]().gradientColor = { r=r, g=g, b=b }
                      ReloadAndUpdate(); UpdatePreview()
                  end },
                { tooltip = "Custom Colored Fill",
                  hasAlpha = false,
                  getValue = function()
                      local c = SGet("customFillColor")
                      if c then return c.r, c.g, c.b end
                      return 37/255, 193/255, 29/255
                  end,
                  setValue = function(r, g, b)
                      UNIT_DB_MAP[selectedUnit]().customFillColor = { r=r, g=g, b=b }
                      ReloadAndUpdate(); UpdatePreview()
                  end,
                  onClick = function(self)
                      if SVal("healthClassColored", true) then
                          -- Seed the custom fill with the swatch's default the first
                          -- time, so the bar shows it immediately. Without a stored
                          -- customFillColor the runtime falls back to oUF's class/
                          -- reaction color, so the bar looked unchanged until the
                          -- color picker was dragged ("jump start"). Only seeds when
                          -- unset, so it never clobbers an existing custom color.
                          if SGet("customFillColor") == nil then
                              UNIT_DB_MAP[selectedUnit]().customFillColor = { r = 37/255, g = 193/255, b = 29/255 }
                          end
                          SSet("healthClassColored", false)
                          UpdatePreview()
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      return SVal("healthClassColored", true) and 0.3 or 1
                  end },
                { tooltip = "Class Colored Fill",
                  hasAlpha = false,
                  getValue = function()
                      local _, ct = UnitClass("player")
                      if ct and RAID_CLASS_COLORS[ct] then
                          local cc = RAID_CLASS_COLORS[ct]
                          return cc.r, cc.g, cc.b
                      end
                      return 1, 1, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      SSet("healthClassColored", true)
                      UpdatePreview()
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      return SVal("healthClassColored", true) and 1 or 0.3
                  end },
              } },
            { type="slider", text="Bar Background", min=0, max=100, step=1,
              getValue=function() return SVal("customBgAlpha", 100) end,
              setValue=function(v) SSet("customBgAlpha", v); ReloadAndUpdate(); UpdatePreview() end });  y = y - h
        -- Inline color swatches on Bar Background (right region): a Custom + Class
        -- pair mirroring the Bar Color picker. Clicking either toggles bgClassColored;
        -- the inactive one dims to 0.3 (matches the fill swatch behavior).
        do
            local rgn = sharedHealthColorRow._rightRegion
            -- Class-colored background swatch (shows player class color; not editable).
            local bgClassGet = function()
                local _, ct = UnitClass("player")
                local cc = ct and RAID_CLASS_COLORS[ct]
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end
            local bgClassSw, bgClassUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgClassGet, function() end, false, 20)
            bgClassSw._eabOrigClick = bgClassSw:GetScript("OnClick")
            bgClassSw:SetScript("OnClick", function()
                SSet("bgClassColored", true)
                ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
            end)
            bgClassSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgClassSw, "Class Colored Background") end)
            bgClassSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            PP.Point(bgClassSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = bgClassSw
            RegisterWidgetRefresh(function()
                bgClassUpdate()
                bgClassSw:SetAlpha(SVal("bgClassColored", false) and 1 or 0.3)
            end)
            bgClassSw:SetAlpha(SVal("bgClassColored", false) and 1 or 0.3)

            -- Custom background color swatch.
            local bgSwGet = function()
                local c = SGet("customBgColor")
                if c then return c.r, c.g, c.b end
                return 17/255, 17/255, 17/255
            end
            local bgSwSet = function(r, g, b)
                UNIT_DB_MAP[selectedUnit]().customBgColor = { r=r, g=g, b=b }
                ReloadAndUpdate(); UpdatePreview()
            end
            local bgSw, bgSwUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgSwGet, bgSwSet, false, 20)
            bgSw._eabOrigClick = bgSw:GetScript("OnClick")
            bgSw:SetScript("OnClick", function(self)
                if SVal("bgClassColored", false) then
                    SSet("bgClassColored", false)
                    ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
                    return
                end
                if self._eabOrigClick then self._eabOrigClick(self) end
            end)
            bgSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgSw, "Custom Background Color") end)
            bgSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            PP.Point(bgSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = bgSw
            RegisterWidgetRefresh(function()
                bgSwUpdate()
                bgSw:SetAlpha(SVal("bgClassColored", false) and 0.3 or 1)
            end)
            bgSw:SetAlpha(SVal("bgClassColored", false) and 0.3 or 1)
        end
        -- Sync icon: Bar Background (right) -- background color + opacity
        do
            local rgn = sharedHealthColorRow._rightRegion
            local function ApplyBgTo(keys)
                local src = UNIT_DB_MAP[selectedUnit]()
                local bc = src.customBgColor or { r=17/255, g=17/255, b=17/255 }
                local bgA = src.customBgAlpha or 100
                local bgClass = src.bgClassColored or false
                for _, key in ipairs(keys) do
                    if key ~= selectedUnit then
                        local d = UNIT_DB_MAP[key]()
                        d.customBgColor = { r=bc.r, g=bc.g, b=bc.b }
                        d.customBgAlpha = bgA
                        d.bgClassColored = bgClass
                    end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Bar Background to all Frames",
                onClick = function() ApplyBgTo(GROUP_UNIT_ORDER) end,
                isSynced = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    local function colEq(a, b)
                        if a == nil and b == nil then return true end
                        if a == nil or b == nil then return false end
                        return a.r == b.r and a.g == b.g and a.b == b.b
                    end
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local d = UNIT_DB_MAP[key]()
                        if not colEq(d.customBgColor, src.customBgColor) then return false end
                        if (d.customBgAlpha or 100) ~= (src.customBgAlpha or 100) then return false end
                        if (d.bgClassColored or false) ~= (src.bgClassColored or false) then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys) ApplyBgTo(checkedKeys) end,
                },
            })
        end
        -- Sync icon: Bar Color (left) -- fill/class color and gradient
        do
            local rgn = sharedHealthColorRow._leftRegion
            local function ApplyColorTo(keys)
                local src = UNIT_DB_MAP[selectedUnit]()
                local cc = src.healthClassColored or false
                local fc = src.customFillColor
                local gEn = src.gradientEnabled or false
                local gDir = src.gradientDir or "HORIZONTAL"
                local gc = src.gradientColor
                for _, key in ipairs(keys) do
                    if key ~= selectedUnit then
                        local d = UNIT_DB_MAP[key]()
                        d.healthClassColored = cc
                        if fc then d.customFillColor = { r=fc.r, g=fc.g, b=fc.b }
                        else d.customFillColor = nil end
                        d.gradientEnabled = gEn
                        d.gradientDir = gDir
                        if gc then d.gradientColor = { r=gc.r, g=gc.g, b=gc.b }
                        else d.gradientColor = nil end
                    end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Bar Color to all Frames",
                onClick = function() ApplyColorTo(GROUP_UNIT_ORDER) end,
                isSynced = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    local function colEq(a, b)
                        if a == nil and b == nil then return true end
                        if a == nil or b == nil then return false end
                        return a.r == b.r and a.g == b.g and a.b == b.b
                    end
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local d = UNIT_DB_MAP[key]()
                        if (d.healthClassColored or false) ~= (src.healthClassColored or false) then return false end
                        if not colEq(d.customFillColor, src.customFillColor) then return false end
                        if (d.gradientEnabled or false) ~= (src.gradientEnabled or false) then return false end
                        if not colEq(d.gradientColor, src.gradientColor) then return false end
                        if (d.gradientDir or "HORIZONTAL") ~= (src.gradientDir or "HORIZONTAL") then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys) ApplyColorTo(checkedKeys) end,
                },
            })
        end
        -- Gradient cog on Bar Color (left region)
        do
            local rgn = sharedHealthColorRow._leftRegion
            local _, gradCogShow = EllesmereUI.BuildCogPopup({
                title = "Gradient Settings",
                rows = {
                    { type="toggle", label="Enable Gradient",
                      get=function() return SVal("gradientEnabled", false) end,
                      set=function(v) SSet("gradientEnabled", v); ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage() end },
                    { type="dropdown", label="Gradient Direction",
                      values={ HORIZONTAL="Horizontal", VERTICAL="Vertical" }, order={ "HORIZONTAL", "VERTICAL" },
                      get=function() return SVal("gradientDir", "HORIZONTAL") end,
                      set=function(v) SSet("gradientDir", v); ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage() end },
                },
            })
            MakeCogBtn(rgn, gradCogShow)
        end

        -- Dark Mode: disable all Bar Color + Bar Background controls (the flat dark
        -- health bar ignores fill/background colors).
        AddDarkModeBlock(sharedHealthColorRow._leftRegion)
        AddDarkModeBlock(sharedHealthColorRow._rightRegion)

        -- Row 3: Smooth Health Bars + Bar Opacity
        local sharedOpacityRow
        sharedOpacityRow, h = W:DualRow(parent, y,
            { type="toggle", text="Smooth Health Bars",
              getValue=function() return SVal("smoothBars", false) end,
              setValue=function(v) SSet("smoothBars", v) end },
            { type="slider", text="Fill Opacity", min=0, max=100, step=1,
              disabled=function() return db.profile.darkTheme end,
              disabledTooltip="Dark Mode", requireState="disabled",
              getValue=function() return SVal("healthBarOpacity", 90) end,
              setValue=function(v)
                  SSet("healthBarOpacity", v)
                  UpdatePreview()
              end });  y = y - h
        -- Sync icon: Bar Opacity (right)
        do
            local rgn = sharedOpacityRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Bar Opacity to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().healthBarOpacity or 90
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then UNIT_DB_MAP[key]().healthBarOpacity = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().healthBarOpacity or 90
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().healthBarOpacity or 90) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().healthBarOpacity or 90
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().healthBarOpacity = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 4: Left Text + Right Text
        local sharedTextRow
        sharedTextRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Left Text", values=healthTextValues, order=(selectedUnit == "player" and healthTextOrderPlayer) or ((selectedUnit == "target" or selectedUnit == "focus") and healthTextOrderTargetFocus) or healthTextOrder,
              getValue=function() return SVal("leftTextContent", "name") end,
              setValue=function(v)
                  SSet("leftTextContent", v)
                  if v ~= "none" then
                      if SGet("rightTextContent") == v then SSet("rightTextContent", "none") end
                      if SGet("centerTextContent") == v then SSet("centerTextContent", "none") end
                  end
                  UpdatePreview(); EllesmereUI:RefreshPage()
              end,
            },
            { type="dropdown", text="Right Text", values=healthTextValues, order=(selectedUnit == "player" and healthTextOrderPlayer) or ((selectedUnit == "target" or selectedUnit == "focus") and healthTextOrderTargetFocus) or healthTextOrder,
              getValue=function() return SVal("rightTextContent", "both") end,
              setValue=function(v)
                  SSet("rightTextContent", v)
                  if v ~= "none" then
                      if SGet("leftTextContent") == v then SSet("leftTextContent", "none") end
                      if SGet("centerTextContent") == v then SSet("centerTextContent", "none") end
                  end
                  UpdatePreview(); EllesmereUI:RefreshPage()
              end,
            });  y = y - h
        -- Sync icon: Left Text (left)
        do
            local rgn = sharedTextRow._leftRegion
            local function ApplyLeftTextTo(keys)
                local src = UNIT_DB_MAP[selectedUnit]()
                local v = src.leftTextContent or "name"
                for _, key in ipairs(keys) do
                    if key ~= selectedUnit then
                        local d = UNIT_DB_MAP[key]()
                        d.leftTextContent = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                        d.leftTextClassColor = src.leftTextClassColor
                        d.leftTextColorR, d.leftTextColorG, d.leftTextColorB = src.leftTextColorR, src.leftTextColorG, src.leftTextColorB
                        d.leftTextSize = src.leftTextSize
                        d.leftTextX, d.leftTextY = src.leftTextX, src.leftTextY
                        d.leftTextShortNameLength = src.leftTextShortNameLength
                        d.leftTextShortNameEllipsis = src.leftTextShortNameEllipsis
                    end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Left Text to all Frames",
                onClick = function() ApplyLeftTextTo(GROUP_UNIT_ORDER) end,
                isSynced = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    local v = src.leftTextContent or "name"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local d = UNIT_DB_MAP[key]()
                        local expected = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                        if (d.leftTextContent or "name") ~= expected then return false end
                        if (d.leftTextClassColor or false) ~= (src.leftTextClassColor or false) then return false end
                        if (d.leftTextColorR or 1) ~= (src.leftTextColorR or 1) then return false end
                        if (d.leftTextColorG or 1) ~= (src.leftTextColorG or 1) then return false end
                        if (d.leftTextColorB or 1) ~= (src.leftTextColorB or 1) then return false end
                        if (d.leftTextSize or 0) ~= (src.leftTextSize or 0) then return false end
                        if (d.leftTextX or 0) ~= (src.leftTextX or 0) then return false end
                        if (d.leftTextY or 0) ~= (src.leftTextY or 0) then return false end
                        if (d.leftTextShortNameLength or 0) ~= (src.leftTextShortNameLength or 0) then return false end
                        if (d.leftTextShortNameEllipsis == false) ~= (src.leftTextShortNameEllipsis == false) then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys) ApplyLeftTextTo(checkedKeys) end,
                },
            })
        end
        -- Inline color swatches on Left Text (left region): Custom + Class, mirroring
        -- the CDM Border Size double-swatch. The class swatch sets leftTextClassColor;
        -- the custom swatch opens the picker (and switches back from class when active).
        do
            local leftRgn = sharedTextRow._leftRegion
            local ltAnchor = leftRgn._lastInline or leftRgn._control
            -- Class Colored swatch (nearest the control): shows the player's class color.
            local ltClassSwatch, ltUpdateClassSwatch = EllesmereUI.BuildColorSwatch(
                leftRgn, leftRgn:GetFrameLevel() + 5,
                function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            PP.Point(ltClassSwatch, "RIGHT", ltAnchor, "LEFT", -8, 0)
            ltClassSwatch:SetScript("OnClick", function()
                if SVal("leftTextContent", "name") == "none" then return end
                SSet("leftTextClassColor", true); UpdatePreview(); EllesmereUI:RefreshPage()
            end)
            ltClassSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(ltClassSwatch, "Class Colored") end)
            ltClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            -- Custom Colored swatch (left of the class swatch): opens the color picker.
            local ltSwGet = function()
                return SVal("leftTextColorR", 1), SVal("leftTextColorG", 1), SVal("leftTextColorB", 1)
            end
            local ltSwSet = function(r, g, b)
                SSet("leftTextColorR", r); SSet("leftTextColorG", g); SSet("leftTextColorB", b)
                UpdatePreview()
            end
            local ltSwatch, ltUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, ltSwGet, ltSwSet, nil, 20)
            PP.Point(ltSwatch, "RIGHT", ltClassSwatch, "LEFT", -8, 0)
            leftRgn._lastInline = ltSwatch
            local ltOrigClick = ltSwatch:GetScript("OnClick")
            ltSwatch:SetScript("OnClick", function(self, ...)
                if SVal("leftTextContent", "name") == "none" then return end
                if SVal("leftTextClassColor", false) then
                    SSet("leftTextClassColor", false); UpdatePreview(); EllesmereUI:RefreshPage(); return
                end
                if ltOrigClick then ltOrigClick(self, ...) end
            end)
            ltSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(ltSwatch, "Custom Colored") end)
            ltSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateLtSwatches()
                local isNone = SVal("leftTextContent", "name") == "none"
                local isClass = SVal("leftTextClassColor", false)
                ltSwatch:SetAlpha((isClass or isNone) and 0.3 or 1)
                ltClassSwatch:SetAlpha((isClass and not isNone) and 1 or 0.3)
            end
            RegisterWidgetRefresh(function() ltUpdateSwatch(); ltUpdateClassSwatch(); UpdateLtSwatches() end)
            UpdateLtSwatches()
        end
        -- Cogwheel on Left Text (left region)
        do
            local leftRgn = sharedTextRow._leftRegion
            local _, leftCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Left Text Settings",
                rows = {
                    { type="slider", label="Size", min=8, max=100, step=1,
                      get=function() return SVal("leftTextSize", SDB().textSize or 12) end,
                      set=function(v) SSet("leftTextSize", v); UpdatePreview() end },
                    { type="slider", label="X Offset", min=-150, max=150, step=1,
                      get=function() return SVal("leftTextX", 0) end,
                      set=function(v) SSet("leftTextX", v); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-150, max=150, step=1,
                      get=function() return SVal("leftTextY", 0) end,
                      set=function(v) SSet("leftTextY", v); UpdatePreview() end },
                    { type="slider", label="Name Length", min=0, max=30, step=1,
                      get=function() return SVal("leftTextShortNameLength", 0) end,
                      set=function(v) SSet("leftTextShortNameLength", v); UpdatePreview() end,
                      disabled=function() local c=SVal("leftTextContent","name") return c ~= "name" and c ~= "nametotarget" and c ~= "levelname" and c ~= "namelevel" end,
                      disabledTooltip="Only applies when the selected text includes a Name." },
                    { type="toggle", label="Show Ellipsis",
                      get=function() return SVal("leftTextShortNameEllipsis", true) ~= false end,
                      set=function(v) SSet("leftTextShortNameEllipsis", v); UpdatePreview() end,
                      disabled=function() local c=SVal("leftTextContent","name") return c ~= "name" and c ~= "nametotarget" and c ~= "levelname" and c ~= "namelevel" end,
                      disabledTooltip="Only applies when the selected text includes a Name." },
                    { type="multiswatch", label="Indicator Color",
                      disabled=function() return SVal("leftTextContent","name") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected.",
                      swatches = {
                        { tooltip = "Custom Colored", hasAlpha = false,
                          getValue = function() local c = SVal("leftTextTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                          setValue = function(r, g, b) SSet("leftTextTargetSepColor", { r=r, g=g, b=b }); UpdatePreview() end,
                          onClick = function(self)
                              if SVal("leftTextTargetSepClassColor", false) then
                                  SSet("leftTextTargetSepClassColor", false); UpdatePreview()
                                  return
                              end
                              if self._eabOrigClick then self._eabOrigClick(self) end
                          end,
                          refreshAlpha = function() return SVal("leftTextTargetSepClassColor", false) and 0.3 or 1 end },
                        { tooltip = "Class Colored", hasAlpha = false,
                          getValue = function()
                              local _, ct = UnitClass("player")
                              local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                              if cc then return cc.r, cc.g, cc.b end
                              return 1, 1, 1
                          end,
                          setValue = function() end,
                          onClick = function() SSet("leftTextTargetSepClassColor", true); UpdatePreview() end,
                          refreshAlpha = function() return SVal("leftTextTargetSepClassColor", false) and 1 or 0.3 end },
                      } },
                    { type="input", label="Separator", inputWidth=60,
                      get=function() return SVal("leftTextTargetSep", ">") end,
                      set=function(v)
                          v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                          if v == "" then v = ">" end
                          SSet("leftTextTargetSep", v); UpdatePreview()
                      end,
                      disabled=function() return SVal("leftTextContent","name") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected." },
                                    },
            })
            local leftCogShow = leftCogShowRaw
            local leftCogBtn = MakeCogBtn(leftRgn, leftCogShow)
            local function UpdateLeftCogState()
                local isNone = SVal("leftTextContent", "name") == "none"
                leftCogBtn:SetAlpha(isNone and 0.15 or 0.4)
                leftCogBtn:SetEnabled(not isNone)
            end
            leftCogBtn:SetScript("OnEnter", function(self)
                if SVal("leftTextContent", "name") == "none" then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a text selection other than none."))
                else self:SetAlpha(0.7) end
            end)
            leftCogBtn:SetScript("OnLeave", function(self) UpdateLeftCogState(); EllesmereUI.HideWidgetTooltip() end)
            leftCogBtn:SetScript("OnClick", function(self) leftCogShow(self) end)
            UpdateLeftCogState()
            RegisterWidgetRefresh(UpdateLeftCogState)
        end
        -- Sync icon: Right Text (right)
        do
            local rgn = sharedTextRow._rightRegion
            local function ApplyRightTextTo(keys)
                local src = UNIT_DB_MAP[selectedUnit]()
                local v = src.rightTextContent or "both"
                for _, key in ipairs(keys) do
                    if key ~= selectedUnit then
                        local d = UNIT_DB_MAP[key]()
                        d.rightTextContent = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                        d.rightTextClassColor = src.rightTextClassColor
                        d.rightTextColorR, d.rightTextColorG, d.rightTextColorB = src.rightTextColorR, src.rightTextColorG, src.rightTextColorB
                        d.rightTextSize = src.rightTextSize
                        d.rightTextX, d.rightTextY = src.rightTextX, src.rightTextY
                        d.rightTextShortNameLength = src.rightTextShortNameLength
                        d.rightTextShortNameEllipsis = src.rightTextShortNameEllipsis
                    end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Right Text to all Frames",
                onClick = function() ApplyRightTextTo(GROUP_UNIT_ORDER) end,
                isSynced = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    local v = src.rightTextContent or "both"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local d = UNIT_DB_MAP[key]()
                        local expected = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                        if (d.rightTextContent or "both") ~= expected then return false end
                        if (d.rightTextClassColor or false) ~= (src.rightTextClassColor or false) then return false end
                        if (d.rightTextColorR or 1) ~= (src.rightTextColorR or 1) then return false end
                        if (d.rightTextColorG or 1) ~= (src.rightTextColorG or 1) then return false end
                        if (d.rightTextColorB or 1) ~= (src.rightTextColorB or 1) then return false end
                        if (d.rightTextSize or 0) ~= (src.rightTextSize or 0) then return false end
                        if (d.rightTextX or 0) ~= (src.rightTextX or 0) then return false end
                        if (d.rightTextY or 0) ~= (src.rightTextY or 0) then return false end
                        if (d.rightTextShortNameLength or 0) ~= (src.rightTextShortNameLength or 0) then return false end
                        if (d.rightTextShortNameEllipsis == false) ~= (src.rightTextShortNameEllipsis == false) then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys) ApplyRightTextTo(checkedKeys) end,
                },
            })
        end
        -- Inline color swatches on Right Text (right region): Custom + Class (CDM Border
        -- Size double-swatch pattern). Class swatch sets rightTextClassColor; custom
        -- swatch opens the picker (and switches back from class when active).
        do
            local rightRgn = sharedTextRow._rightRegion
            local rtAnchor = rightRgn._lastInline or rightRgn._control
            local rtClassSwatch, rtUpdateClassSwatch = EllesmereUI.BuildColorSwatch(
                rightRgn, rightRgn:GetFrameLevel() + 5,
                function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            PP.Point(rtClassSwatch, "RIGHT", rtAnchor, "LEFT", -8, 0)
            rtClassSwatch:SetScript("OnClick", function()
                if SVal("rightTextContent", "both") == "none" then return end
                SSet("rightTextClassColor", true); UpdatePreview(); EllesmereUI:RefreshPage()
            end)
            rtClassSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(rtClassSwatch, "Class Colored") end)
            rtClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local rtSwGet = function()
                return SVal("rightTextColorR", 1), SVal("rightTextColorG", 1), SVal("rightTextColorB", 1)
            end
            local rtSwSet = function(r, g, b)
                SSet("rightTextColorR", r); SSet("rightTextColorG", g); SSet("rightTextColorB", b)
                UpdatePreview()
            end
            local rtSwatch, rtUpdateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, rtSwGet, rtSwSet, nil, 20)
            PP.Point(rtSwatch, "RIGHT", rtClassSwatch, "LEFT", -8, 0)
            rightRgn._lastInline = rtSwatch
            local rtOrigClick = rtSwatch:GetScript("OnClick")
            rtSwatch:SetScript("OnClick", function(self, ...)
                if SVal("rightTextContent", "both") == "none" then return end
                if SVal("rightTextClassColor", false) then
                    SSet("rightTextClassColor", false); UpdatePreview(); EllesmereUI:RefreshPage(); return
                end
                if rtOrigClick then rtOrigClick(self, ...) end
            end)
            rtSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(rtSwatch, "Custom Colored") end)
            rtSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateRtSwatches()
                local isNone = SVal("rightTextContent", "both") == "none"
                local isClass = SVal("rightTextClassColor", false)
                rtSwatch:SetAlpha((isClass or isNone) and 0.3 or 1)
                rtClassSwatch:SetAlpha((isClass and not isNone) and 1 or 0.3)
            end
            RegisterWidgetRefresh(function() rtUpdateSwatch(); rtUpdateClassSwatch(); UpdateRtSwatches() end)
            UpdateRtSwatches()
        end
        -- Cogwheel on Right Text (right region)
        do
            local rightRgn = sharedTextRow._rightRegion
            local _, rightCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Right Text Settings",
                rows = {
                    { type="slider", label="Size", min=8, max=100, step=1,
                      get=function() return SVal("rightTextSize", SDB().textSize or 12) end,
                      set=function(v) SSet("rightTextSize", v); UpdatePreview() end },
                    { type="slider", label="X Offset", min=-150, max=150, step=1,
                      get=function() return SVal("rightTextX", 0) end,
                      set=function(v) SSet("rightTextX", v); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-150, max=150, step=1,
                      get=function() return SVal("rightTextY", 0) end,
                      set=function(v) SSet("rightTextY", v); UpdatePreview() end },
                    { type="slider", label="Name Length", min=0, max=30, step=1,
                      get=function() return SVal("rightTextShortNameLength", 0) end,
                      set=function(v) SSet("rightTextShortNameLength", v); UpdatePreview() end,
                      disabled=function() local c=SVal("rightTextContent","both") return c ~= "name" and c ~= "nametotarget" and c ~= "levelname" and c ~= "namelevel" end,
                      disabledTooltip="Only applies when the selected text includes a Name." },
                    { type="toggle", label="Show Ellipsis",
                      get=function() return SVal("rightTextShortNameEllipsis", true) ~= false end,
                      set=function(v) SSet("rightTextShortNameEllipsis", v); UpdatePreview() end,
                      disabled=function() local c=SVal("rightTextContent","both") return c ~= "name" and c ~= "nametotarget" and c ~= "levelname" and c ~= "namelevel" end,
                      disabledTooltip="Only applies when the selected text includes a Name." },
                    { type="multiswatch", label="Indicator Color",
                      disabled=function() return SVal("rightTextContent","both") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected.",
                      swatches = {
                        { tooltip = "Custom Colored", hasAlpha = false,
                          getValue = function() local c = SVal("rightTextTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                          setValue = function(r, g, b) SSet("rightTextTargetSepColor", { r=r, g=g, b=b }); UpdatePreview() end,
                          onClick = function(self)
                              if SVal("rightTextTargetSepClassColor", false) then
                                  SSet("rightTextTargetSepClassColor", false); UpdatePreview()
                                  return
                              end
                              if self._eabOrigClick then self._eabOrigClick(self) end
                          end,
                          refreshAlpha = function() return SVal("rightTextTargetSepClassColor", false) and 0.3 or 1 end },
                        { tooltip = "Class Colored", hasAlpha = false,
                          getValue = function()
                              local _, ct = UnitClass("player")
                              local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                              if cc then return cc.r, cc.g, cc.b end
                              return 1, 1, 1
                          end,
                          setValue = function() end,
                          onClick = function() SSet("rightTextTargetSepClassColor", true); UpdatePreview() end,
                          refreshAlpha = function() return SVal("rightTextTargetSepClassColor", false) and 1 or 0.3 end },
                      } },
                    { type="input", label="Separator", inputWidth=60,
                      get=function() return SVal("rightTextTargetSep", ">") end,
                      set=function(v)
                          v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                          if v == "" then v = ">" end
                          SSet("rightTextTargetSep", v); UpdatePreview()
                      end,
                      disabled=function() return SVal("rightTextContent","both") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected." },
                                    },
            })
            local rightCogShow = rightCogShowRaw
            local rightCogBtn = MakeCogBtn(rightRgn, rightCogShow)
            local function UpdateRightCogState()
                local isNone = SVal("rightTextContent", "both") == "none"
                rightCogBtn:SetAlpha(isNone and 0.15 or 0.4)
                rightCogBtn:SetEnabled(not isNone)
            end
            rightCogBtn:SetScript("OnEnter", function(self)
                if SVal("rightTextContent", "both") == "none" then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a text selection other than none."))
                else self:SetAlpha(0.7) end
            end)
            rightCogBtn:SetScript("OnLeave", function(self) UpdateRightCogState(); EllesmereUI.HideWidgetTooltip() end)
            rightCogBtn:SetScript("OnClick", function(self) rightCogShow(self) end)
            UpdateRightCogState()
            RegisterWidgetRefresh(UpdateRightCogState)
        end

        -- Row 5: Center Text
        local sharedCenterTextRow
        sharedCenterTextRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Center Text", values=healthTextValues, order=(selectedUnit == "player" and healthTextOrderPlayer) or ((selectedUnit == "target" or selectedUnit == "focus") and healthTextOrderTargetFocus) or healthTextOrder,
              getValue=function() return SVal("centerTextContent", "none") end,
              setValue=function(v)
                  SSet("centerTextContent", v)
                  ReloadAndUpdate(); UpdatePreview()
              end },
            { type="dropdown", text="Extra Text (full length)", values=healthTextValues, order=(selectedUnit == "player" and healthTextOrderPlayer) or ((selectedUnit == "target" or selectedUnit == "focus") and healthTextOrderTargetFocus) or healthTextOrder,
              getValue=function() return SVal("extraTextContent", "none") end,
              setValue=function(v)
                  SSet("extraTextContent", v)
                  ReloadAndUpdate(); UpdatePreview()
              end });  y = y - h
        -- Sync icon: Center Text (left)
        do
            local rgn = sharedCenterTextRow._leftRegion
            local function ApplyCenterTextTo(keys)
                local src = UNIT_DB_MAP[selectedUnit]()
                local v = src.centerTextContent or "none"
                for _, key in ipairs(keys) do
                    if key ~= selectedUnit then
                        local d = UNIT_DB_MAP[key]()
                        d.centerTextContent = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                        d.centerTextClassColor = src.centerTextClassColor
                        d.centerTextColorR, d.centerTextColorG, d.centerTextColorB = src.centerTextColorR, src.centerTextColorG, src.centerTextColorB
                        d.centerTextSize = src.centerTextSize
                        d.centerTextX, d.centerTextY = src.centerTextX, src.centerTextY
                        d.centerTextShortNameLength = src.centerTextShortNameLength
                        d.centerTextShortNameEllipsis = src.centerTextShortNameEllipsis
                    end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Center Text to all Frames",
                onClick = function() ApplyCenterTextTo(GROUP_UNIT_ORDER) end,
                isSynced = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    local v = src.centerTextContent or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local d = UNIT_DB_MAP[key]()
                        local expected = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                        if (d.centerTextContent or "none") ~= expected then return false end
                        if (d.centerTextClassColor or false) ~= (src.centerTextClassColor or false) then return false end
                        if (d.centerTextColorR or 1) ~= (src.centerTextColorR or 1) then return false end
                        if (d.centerTextColorG or 1) ~= (src.centerTextColorG or 1) then return false end
                        if (d.centerTextColorB or 1) ~= (src.centerTextColorB or 1) then return false end
                        if (d.centerTextSize or 0) ~= (src.centerTextSize or 0) then return false end
                        if (d.centerTextX or 0) ~= (src.centerTextX or 0) then return false end
                        if (d.centerTextY or 0) ~= (src.centerTextY or 0) then return false end
                        if (d.centerTextShortNameLength or 0) ~= (src.centerTextShortNameLength or 0) then return false end
                        if (d.centerTextShortNameEllipsis == false) ~= (src.centerTextShortNameEllipsis == false) then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys) ApplyCenterTextTo(checkedKeys) end,
                },
            })
        end
        -- Inline color swatches on Center Text (left region): Custom + Class (CDM Border
        -- Size double-swatch pattern). Class swatch sets centerTextClassColor; custom
        -- swatch opens the picker (and switches back from class when active).
        do
            local ctrRgn = sharedCenterTextRow._leftRegion
            local ctAnchor = ctrRgn._lastInline or ctrRgn._control
            local ctClassSwatch, ctUpdateClassSwatch = EllesmereUI.BuildColorSwatch(
                ctrRgn, ctrRgn:GetFrameLevel() + 5,
                function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            PP.Point(ctClassSwatch, "RIGHT", ctAnchor, "LEFT", -8, 0)
            ctClassSwatch:SetScript("OnClick", function()
                if SVal("centerTextContent", "none") == "none" then return end
                SSet("centerTextClassColor", true); UpdatePreview(); EllesmereUI:RefreshPage()
            end)
            ctClassSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(ctClassSwatch, "Class Colored") end)
            ctClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local ctSwGet = function()
                return SVal("centerTextColorR", 1), SVal("centerTextColorG", 1), SVal("centerTextColorB", 1)
            end
            local ctSwSet = function(r, g, b)
                SSet("centerTextColorR", r); SSet("centerTextColorG", g); SSet("centerTextColorB", b)
                UpdatePreview()
            end
            local ctSwatch, ctUpdateSwatch = EllesmereUI.BuildColorSwatch(ctrRgn, ctrRgn:GetFrameLevel() + 5, ctSwGet, ctSwSet, nil, 20)
            PP.Point(ctSwatch, "RIGHT", ctClassSwatch, "LEFT", -8, 0)
            ctrRgn._lastInline = ctSwatch
            local ctOrigClick = ctSwatch:GetScript("OnClick")
            ctSwatch:SetScript("OnClick", function(self, ...)
                if SVal("centerTextContent", "none") == "none" then return end
                if SVal("centerTextClassColor", false) then
                    SSet("centerTextClassColor", false); UpdatePreview(); EllesmereUI:RefreshPage(); return
                end
                if ctOrigClick then ctOrigClick(self, ...) end
            end)
            ctSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(ctSwatch, "Custom Colored") end)
            ctSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCtSwatches()
                local isNone = SVal("centerTextContent", "none") == "none"
                local isClass = SVal("centerTextClassColor", false)
                ctSwatch:SetAlpha((isClass or isNone) and 0.3 or 1)
                ctClassSwatch:SetAlpha((isClass and not isNone) and 1 or 0.3)
            end
            RegisterWidgetRefresh(function() ctUpdateSwatch(); ctUpdateClassSwatch(); UpdateCtSwatches() end)
            UpdateCtSwatches()
        end
        -- Cogwheel on Center Text (left region)
        do
            local ctrRgn = sharedCenterTextRow._leftRegion
            local _, centerCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Center Text Settings",
                rows = {
                    { type="slider", label="Size", min=8, max=100, step=1,
                      get=function() return SVal("centerTextSize", SDB().textSize or 12) end,
                      set=function(v) SSet("centerTextSize", v); UpdatePreview() end },
                    { type="slider", label="X Offset", min=-150, max=150, step=1,
                      get=function() return SVal("centerTextX", 0) end,
                      set=function(v) SSet("centerTextX", v); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-150, max=150, step=1,
                      get=function() return SVal("centerTextY", 0) end,
                      set=function(v) SSet("centerTextY", v); UpdatePreview() end },
                    { type="slider", label="Name Length", min=0, max=30, step=1,
                      get=function() return SVal("centerTextShortNameLength", 0) end,
                      set=function(v) SSet("centerTextShortNameLength", v); UpdatePreview() end,
                      disabled=function() local c=SVal("centerTextContent","none") return c ~= "name" and c ~= "nametotarget" and c ~= "levelname" and c ~= "namelevel" end,
                      disabledTooltip="Only applies when the selected text includes a Name." },
                    { type="toggle", label="Show Ellipsis",
                      get=function() return SVal("centerTextShortNameEllipsis", true) ~= false end,
                      set=function(v) SSet("centerTextShortNameEllipsis", v); UpdatePreview() end,
                      disabled=function() local c=SVal("centerTextContent","none") return c ~= "name" and c ~= "nametotarget" and c ~= "levelname" and c ~= "namelevel" end,
                      disabledTooltip="Only applies when the selected text includes a Name." },
                    { type="multiswatch", label="Indicator Color",
                      disabled=function() return SVal("centerTextContent","none") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected.",
                      swatches = {
                        { tooltip = "Custom Colored", hasAlpha = false,
                          getValue = function() local c = SVal("centerTextTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                          setValue = function(r, g, b) SSet("centerTextTargetSepColor", { r=r, g=g, b=b }); UpdatePreview() end,
                          onClick = function(self)
                              if SVal("centerTextTargetSepClassColor", false) then
                                  SSet("centerTextTargetSepClassColor", false); UpdatePreview()
                                  return
                              end
                              if self._eabOrigClick then self._eabOrigClick(self) end
                          end,
                          refreshAlpha = function() return SVal("centerTextTargetSepClassColor", false) and 0.3 or 1 end },
                        { tooltip = "Class Colored", hasAlpha = false,
                          getValue = function()
                              local _, ct = UnitClass("player")
                              local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                              if cc then return cc.r, cc.g, cc.b end
                              return 1, 1, 1
                          end,
                          setValue = function() end,
                          onClick = function() SSet("centerTextTargetSepClassColor", true); UpdatePreview() end,
                          refreshAlpha = function() return SVal("centerTextTargetSepClassColor", false) and 1 or 0.3 end },
                      } },
                    { type="input", label="Separator", inputWidth=60,
                      get=function() return SVal("centerTextTargetSep", ">") end,
                      set=function(v)
                          v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                          if v == "" then v = ">" end
                          SSet("centerTextTargetSep", v); UpdatePreview()
                      end,
                      disabled=function() return SVal("centerTextContent","none") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected." },
                                    },
            })
            local centerCogShow = centerCogShowRaw
            local centerCogBtn = MakeCogBtn(ctrRgn, centerCogShow)
            local function UpdateCenterCogState()
                local isNone = SVal("centerTextContent", "none") == "none"
                centerCogBtn:SetAlpha(isNone and 0.15 or 0.4)
                centerCogBtn:SetEnabled(not isNone)
            end
            centerCogBtn:SetScript("OnEnter", function(self)
                if SVal("centerTextContent", "none") == "none" then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a text selection other than none."))
                else self:SetAlpha(0.7) end
            end)
            centerCogBtn:SetScript("OnLeave", function(self) UpdateCenterCogState(); EllesmereUI.HideWidgetTooltip() end)
            centerCogBtn:SetScript("OnClick", function(self) centerCogShow(self) end)
            UpdateCenterCogState()
            RegisterWidgetRefresh(UpdateCenterCogState)
        end

        -- Extra Text shares the Center Text row: its dropdown is that row's 2nd (right)
        -- slot, added above. Its inline controls attach to the row's RIGHT region.
        -- Sync icon: Extra Text (right region)
        do
            local rgn = sharedCenterTextRow._rightRegion
            local function ApplyExtraTextTo(keys)
                local src = UNIT_DB_MAP[selectedUnit]()
                local v = src.extraTextContent or "none"
                for _, key in ipairs(keys) do
                    if key ~= selectedUnit then
                        local d = UNIT_DB_MAP[key]()
                        d.extraTextContent = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                        d.extraTextClassColor = src.extraTextClassColor
                        d.extraTextColorR, d.extraTextColorG, d.extraTextColorB = src.extraTextColorR, src.extraTextColorG, src.extraTextColorB
                        d.extraTextSize = src.extraTextSize
                        d.extraTextX, d.extraTextY = src.extraTextX, src.extraTextY
                        d.extraTextAlign = src.extraTextAlign
                        d.extraTextShortNameLength = src.extraTextShortNameLength
                        d.extraTextShortNameEllipsis = src.extraTextShortNameEllipsis
                    end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Extra Text to all Frames",
                onClick = function() ApplyExtraTextTo(GROUP_UNIT_ORDER) end,
                isSynced = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    local v = src.extraTextContent or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local d = UNIT_DB_MAP[key]()
                        local expected = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                        if (d.extraTextContent or "none") ~= expected then return false end
                        if (d.extraTextClassColor or false) ~= (src.extraTextClassColor or false) then return false end
                        if (d.extraTextColorR or 1) ~= (src.extraTextColorR or 1) then return false end
                        if (d.extraTextColorG or 1) ~= (src.extraTextColorG or 1) then return false end
                        if (d.extraTextColorB or 1) ~= (src.extraTextColorB or 1) then return false end
                        if (d.extraTextSize or 0) ~= (src.extraTextSize or 0) then return false end
                        if (d.extraTextX or 0) ~= (src.extraTextX or 0) then return false end
                        if (d.extraTextY or 0) ~= (src.extraTextY or 0) then return false end
                        if (d.extraTextAlign or "left") ~= (src.extraTextAlign or "left") then return false end
                        if (d.extraTextShortNameLength or 0) ~= (src.extraTextShortNameLength or 0) then return false end
                        if (d.extraTextShortNameEllipsis == false) ~= (src.extraTextShortNameEllipsis == false) then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys) ApplyExtraTextTo(checkedKeys) end,
                },
            })
        end
        -- Inline color swatches on Extra Text (Center row right region): Custom + Class.
        -- Class swatch sets extraTextClassColor; custom opens the picker.
        do
            local etrRgn = sharedCenterTextRow._rightRegion
            local etAnchor = etrRgn._lastInline or etrRgn._control
            local etClassSwatch, etUpdateClassSwatch = EllesmereUI.BuildColorSwatch(
                etrRgn, etrRgn:GetFrameLevel() + 5,
                function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            PP.Point(etClassSwatch, "RIGHT", etAnchor, "LEFT", -8, 0)
            etClassSwatch:SetScript("OnClick", function()
                if SVal("extraTextContent", "none") == "none" then return end
                SSet("extraTextClassColor", true); UpdatePreview(); EllesmereUI:RefreshPage()
            end)
            etClassSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(etClassSwatch, "Class Colored") end)
            etClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local etSwGet = function()
                return SVal("extraTextColorR", 1), SVal("extraTextColorG", 1), SVal("extraTextColorB", 1)
            end
            local etSwSet = function(r, g, b)
                SSet("extraTextColorR", r); SSet("extraTextColorG", g); SSet("extraTextColorB", b)
                UpdatePreview()
            end
            local etSwatch, etUpdateSwatch = EllesmereUI.BuildColorSwatch(etrRgn, etrRgn:GetFrameLevel() + 5, etSwGet, etSwSet, nil, 20)
            PP.Point(etSwatch, "RIGHT", etClassSwatch, "LEFT", -8, 0)
            etrRgn._lastInline = etSwatch
            local etOrigClick = etSwatch:GetScript("OnClick")
            etSwatch:SetScript("OnClick", function(self, ...)
                if SVal("extraTextContent", "none") == "none" then return end
                if SVal("extraTextClassColor", false) then
                    SSet("extraTextClassColor", false); UpdatePreview(); EllesmereUI:RefreshPage(); return
                end
                if etOrigClick then etOrigClick(self, ...) end
            end)
            etSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(etSwatch, "Custom Colored") end)
            etSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateEtSwatches()
                local isNone = SVal("extraTextContent", "none") == "none"
                local isClass = SVal("extraTextClassColor", false)
                etSwatch:SetAlpha((isClass or isNone) and 0.3 or 1)
                etClassSwatch:SetAlpha((isClass and not isNone) and 1 or 0.3)
            end
            RegisterWidgetRefresh(function() etUpdateSwatch(); etUpdateClassSwatch(); UpdateEtSwatches() end)
            UpdateEtSwatches()
        end
        -- Cogwheel on Extra Text (Center row right region): Alignment + Size/X/Y
        do
            local etrRgn = sharedCenterTextRow._rightRegion
            local _, extraCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Extra Text Settings",
                rows = {
                    { type="dropdown", label="Alignment",
                      values={ ["left"]="Left", ["right"]="Right", ["center"]="Center" }, order={ "left", "right", "center" },
                      get=function() return SVal("extraTextAlign", "left") end,
                      set=function(v) SSet("extraTextAlign", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="slider", label="Size", min=8, max=100, step=1,
                      get=function() return SVal("extraTextSize", SDB().textSize or 12) end,
                      set=function(v) SSet("extraTextSize", v); UpdatePreview() end },
                    { type="slider", label="X Offset", min=-150, max=150, step=1,
                      get=function() return SVal("extraTextX", 0) end,
                      set=function(v) SSet("extraTextX", v); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-150, max=150, step=1,
                      get=function() return SVal("extraTextY", 0) end,
                      set=function(v) SSet("extraTextY", v); UpdatePreview() end },
                    { type="slider", label="Name Length", min=0, max=30, step=1,
                      get=function() return SVal("extraTextShortNameLength", 0) end,
                      set=function(v) SSet("extraTextShortNameLength", v); UpdatePreview() end,
                      disabled=function() local c=SVal("extraTextContent","none") return c ~= "name" and c ~= "nametotarget" and c ~= "levelname" and c ~= "namelevel" end,
                      disabledTooltip="Only applies when the selected text includes a Name." },
                    { type="toggle", label="Show Ellipsis",
                      get=function() return SVal("extraTextShortNameEllipsis", true) ~= false end,
                      set=function(v) SSet("extraTextShortNameEllipsis", v); UpdatePreview() end,
                      disabled=function() local c=SVal("extraTextContent","none") return c ~= "name" and c ~= "nametotarget" and c ~= "levelname" and c ~= "namelevel" end,
                      disabledTooltip="Only applies when the selected text includes a Name." },
                    { type="multiswatch", label="Indicator Color",
                      disabled=function() return SVal("extraTextContent","none") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected.",
                      swatches = {
                        { tooltip = "Custom Colored", hasAlpha = false,
                          getValue = function() local c = SVal("extraTextTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                          setValue = function(r, g, b) SSet("extraTextTargetSepColor", { r=r, g=g, b=b }); UpdatePreview() end,
                          onClick = function(self)
                              if SVal("extraTextTargetSepClassColor", false) then
                                  SSet("extraTextTargetSepClassColor", false); UpdatePreview()
                                  return
                              end
                              if self._eabOrigClick then self._eabOrigClick(self) end
                          end,
                          refreshAlpha = function() return SVal("extraTextTargetSepClassColor", false) and 0.3 or 1 end },
                        { tooltip = "Class Colored", hasAlpha = false,
                          getValue = function()
                              local _, ct = UnitClass("player")
                              local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                              if cc then return cc.r, cc.g, cc.b end
                              return 1, 1, 1
                          end,
                          setValue = function() end,
                          onClick = function() SSet("extraTextTargetSepClassColor", true); UpdatePreview() end,
                          refreshAlpha = function() return SVal("extraTextTargetSepClassColor", false) and 1 or 0.3 end },
                      } },
                    { type="input", label="Separator", inputWidth=60,
                      get=function() return SVal("extraTextTargetSep", ">") end,
                      set=function(v)
                          v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                          if v == "" then v = ">" end
                          SSet("extraTextTargetSep", v); UpdatePreview()
                      end,
                      disabled=function() return SVal("extraTextContent","none") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected." },
                                    },
            })
            local extraCogShow = extraCogShowRaw
            local extraCogBtn = MakeCogBtn(etrRgn, extraCogShow)
            local function UpdateExtraCogState()
                local isNone = SVal("extraTextContent", "none") == "none"
                extraCogBtn:SetAlpha(isNone and 0.15 or 0.4)
                extraCogBtn:SetEnabled(not isNone)
            end
            extraCogBtn:SetScript("OnEnter", function(self)
                if SVal("extraTextContent", "none") == "none" then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a text selection other than none."))
                else self:SetAlpha(0.7) end
            end)
            extraCogBtn:SetScript("OnLeave", function(self) UpdateExtraCogState(); EllesmereUI.HideWidgetTooltip() end)
            extraCogBtn:SetScript("OnClick", function(self) extraCogShow(self) end)
            UpdateExtraCogState()
            RegisterWidgetRefresh(UpdateExtraCogState)
        end

        _, h = W:Spacer(parent, y, 20); y = y - h

        -------------------------------------------------------------------
        --  POWER BAR
        -------------------------------------------------------------------
        local sharedPowerHeader
        sharedPowerHeader, h = W:SectionHeader(parent, "POWER BAR", y); y = y - h

        local ppPosValues = { ["below"]="Below Health Bar", ["above"]="Above Health Bar", ["detached_bottom"]="Detached Bottom", ["detached_top"]="Detached Top", ["none"]="None" }
        local ppPosOrder = { "below", "above", "---", "detached_bottom", "detached_top", "---", "none" }
        local ppTextValues = { ["none"]="None", ["left"]="Left", ["right"]="Right", ["center"]="Center" }
        local ppTextOrder = { "none", "---", "left", "right", "center" }
        local ppFmtValues = { ["none"]="None", ["smart"]="Smart Text", ["curpp"]="Power Value", ["perpp"]="Power %", ["both"]="Value | %" }
        local ppFmtOrder = { "none", "smart", "curpp", "perpp", "both" }

        -- Row 1: Bar Height + Bar Position
        local sharedPowerRow1
        sharedPowerRow1, h = W:DualRow(parent, y,
            { type="slider", text="Power Bar Height", min=0, max=30, step=1,
              getValue=function() return SValSupported("powerHeight", 6) end,
              setValue=function(v) SSetSupported("powerHeight", v); ReloadAndUpdate(); UpdatePreview() end },
            { type="dropdown", text="Bar Position", values=ppPosValues, order=ppPosOrder,
              getValue=function() return SVal("powerPosition", "below") end,
              setValue=function(v)
                  SSet("powerPosition", v)
                  ReloadAndUpdate(); UpdatePreview()
              end });  y = y - h
        -- Cog on Position for X/Y offsets + Width (disabled unless detached)
        do
            local posRgn = sharedPowerRow1._rightRegion
            local _, ppPosCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Position Settings",
                rows = {
                    { type="slider", label="Width", min=0, max=400, step=1,
                      get=function() return SVal("powerWidth", 0) end,
                      set=function(v) SSet("powerWidth", v); UpdatePreview() end },
                    { type="slider", label="X Offset", min=-200, max=200, step=1,
                      get=function() return SVal("powerX", 0) end,
                      set=function(v) SSet("powerX", v); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-200, max=200, step=1,
                      get=function() return SVal("powerY", 0) end,
                      set=function(v) SSet("powerY", v); UpdatePreview() end },
                },
            })
            local ppPosCogShow = ppPosCogShowRaw
            local ppPosCogBtn = MakeCogBtn(posRgn, ppPosCogShow, nil, EllesmereUI.RESIZE_ICON)
            local function _ppPosCogUpdate()
                local pos = SVal("powerPosition", "below")
                local isDet = (pos == "detached_top" or pos == "detached_bottom")
                ppPosCogBtn:SetAlpha(isDet and 0.4 or 0.15)
                ppPosCogBtn:SetEnabled(isDet)
            end
            ppPosCogBtn:SetScript("OnEnter", function(self)
                local pos = SVal("powerPosition", "below")
                if pos == "detached_top" or pos == "detached_bottom" then self:SetAlpha(0.7)
                else EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a detached position to be active.")) end
            end)
            ppPosCogBtn:SetScript("OnLeave", function(self) _ppPosCogUpdate(); EllesmereUI.HideWidgetTooltip() end)
            ppPosCogBtn:SetScript("OnClick", function(self) ppPosCogShow(self) end)
            _ppPosCogUpdate()
            RegisterWidgetRefresh(_ppPosCogUpdate)
        end
        -- Sync icons: Power Height (left) and Power Position (right)
        do
            local rgn = sharedPowerRow1._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Power Bar Height to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().powerHeight or 6
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().powerHeight = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().powerHeight or 6
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().powerHeight or 6) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().powerHeight or 6
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().powerHeight = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        -- Reverse Fill cog on Bar Height (left region)
        do
            local rgn = sharedPowerRow1._leftRegion
            local _, revCogShow = EllesmereUI.BuildCogPopup({
                title = "Power Bar Fill",
                rows = {
                    { type="toggle", label="Reverse Fill",
                      get=function() return SVal("powerReverseFill", false) end,
                      set=function(v) SSet("powerReverseFill", v); ReloadAndUpdate(); UpdatePreview() end },
                },
            })
            MakeCogBtn(rgn, revCogShow)
        end
        do
            local rgn = sharedPowerRow1._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Bar Position to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().powerPosition or "below"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().powerPosition = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().powerPosition or "below"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().powerPosition or "below") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().powerPosition or "below"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().powerPosition = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 2: Power Text (format) + Fill Opacity
        local sharedPowerRow2
        sharedPowerRow2, h = W:DualRow(parent, y,
            { type="dropdown", text="Power Text", values=ppFmtValues, order=ppFmtOrder,
              getValue=function() return SVal("powerTextFormat", "perpp") end,
              setValue=function(v)
                  SSet("powerTextFormat", v)
                  -- Auto-set position to center if user picks a format while position is "none"
                  if v ~= "none" and SVal("powerPercentText", "none") == "none" then
                      SSet("powerPercentText", "center")
                  end
                  -- If format is "none", clear position too
                  if v == "none" then SSet("powerPercentText", "none") end
                  ReloadAndUpdate(); UpdatePreview()
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Fill Opacity", min=0, max=100, step=1,
              getValue=function() return SVal("powerBarOpacity", 100) end,
              setValue=function(v)
                  SSet("powerBarOpacity", v)
                  UpdatePreview()
              end });  y = y - h
        -- Cogwheel on Power Text for Show % toggle
        do
            local fmtRgn = sharedPowerRow2._leftRegion
            local _, fmtCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Power Text",
                rows = {
                    { type="toggle", label="Show %",
                      get=function() return SVal("powerShowPercent", true) ~= false end,
                      set=function(v)
                          SSet("powerShowPercent", v)
                          UpdatePreview()
                      end },
                },
            })
            local fmtCogShow = fmtCogShowRaw
            local fmtCogBtn = MakeCogBtn(fmtRgn, fmtCogShow)
            local function UpdateFmtCogState()
                local fmt = SVal("powerTextFormat", "perpp")
                local isNone = (fmt == "none" or fmt == "curpp")
                fmtCogBtn:SetAlpha(isNone and 0.15 or 0.4)
                fmtCogBtn:SetEnabled(not isNone)
            end
            fmtCogBtn:SetScript("OnEnter", function(self)
                local fmt = SVal("powerTextFormat", "perpp")
                if fmt == "none" or fmt == "curpp" then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option is only available for formats that display a percentage."))
                else self:SetAlpha(0.7) end
            end)
            fmtCogBtn:SetScript("OnLeave", function(self) UpdateFmtCogState(); EllesmereUI.HideWidgetTooltip() end)
            fmtCogBtn:SetScript("OnClick", function(self) fmtCogShow(self) end)
            UpdateFmtCogState()
            RegisterWidgetRefresh(UpdateFmtCogState)
        end
        -- Sync icon: Power Text Format (left of row 2)
        do
            local rgn = sharedPowerRow2._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Power Text Format to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().powerTextFormat or "perpp"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().powerTextFormat = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().powerTextFormat or "perpp"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().powerTextFormat or "perpp") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().powerTextFormat or "perpp"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().powerTextFormat = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        -- Fill Opacity sync (right of row 2)
        do
            local rgn = sharedPowerRow2._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Bar Opacity to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().powerBarOpacity or 100
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then UNIT_DB_MAP[key]().powerBarOpacity = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().powerBarOpacity or 100
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().powerBarOpacity or 100) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().powerBarOpacity or 100
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().powerBarOpacity = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 3: Bar Color (multiSwatch) + Bar Background (slider + inline swatch)
        local sharedPowerRow3
        sharedPowerRow3, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Fill Color",
              swatches = {
                { tooltip = "Gradient End Color", hasAlpha = false,
                  disabled = function() return not SVal("powerGradientEnabled", false) end,
                  disabledTooltip = function() return "Gradient" end,
                  getValue = function()
                      local c = SGet("powerGradientColor")
                      if c then return c.r, c.g, c.b end
                      return 0.20, 0.20, 0.80
                  end,
                  setValue = function(r, g, b)
                      UNIT_DB_MAP[selectedUnit]().powerGradientColor = { r=r, g=g, b=b }
                      ReloadAndUpdate(); UpdatePreview()
                  end },
                { tooltip = "Custom Colored Fill",
                  hasAlpha = false,
                  getValue = function()
                      local c = SGet("customPowerFillColor")
                      if c then return c.r, c.g, c.b end
                      return 0, 0, 1
                  end,
                  setValue = function(r, g, b)
                      UNIT_DB_MAP[selectedUnit]().customPowerFillColor = { r=r, g=g, b=b }
                      ReloadAndUpdate(); UpdatePreview()
                  end,
                  onClick = function(self)
                      local v = SVal("powerPercentPowerColor", true)
                      if v then
                          SSet("powerPercentPowerColor", false)
                          UpdatePreview()
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      return SVal("powerPercentPowerColor", true) and 0.3 or 1
                  end },
                { tooltip = "Power Colored Fill",
                  hasAlpha = false,
                  getValue = function()
                      local _, pToken = UnitPowerType("player")
                      local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                      return info.r, info.g, info.b
                  end,
                  setValue = function() end,
                  onClick = function()
                      SSet("powerPercentPowerColor", true)
                      UpdatePreview()
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      return SVal("powerPercentPowerColor", true) and 1 or 0.3
                  end },
              } },
            { type="slider", text="Bar Background", min=0, max=100, step=1,
              getValue=function() return SVal("customPowerBgAlpha", 100) end,
              setValue=function(v) SSet("customPowerBgAlpha", v); ReloadAndUpdate(); UpdatePreview() end });  y = y - h
        -- Inline color swatches on Bar Background (right region): a Custom + Power
        -- Colored pair mirroring the Bar Color picker. Clicking either toggles
        -- powerBgPowerColored; the inactive one dims to 0.3 (matches the fill swatch).
        do
            local rgn = sharedPowerRow3._rightRegion
            -- Power-colored background swatch (shows the player's power color; not editable).
            local bgPwrGet = function()
                local _, pToken = UnitPowerType("player")
                local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                local f = EllesmereUI.GetPowerBgDarkenFactor()
                return info.r * f, info.g * f, info.b * f
            end
            local bgPwrSw, bgPwrUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgPwrGet, function() end, false, 20)
            bgPwrSw._eabOrigClick = bgPwrSw:GetScript("OnClick")
            bgPwrSw:SetScript("OnClick", function()
                SSet("powerBgPowerColored", true)
                ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
            end)
            bgPwrSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgPwrSw, "Power Colored Background") end)
            bgPwrSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            PP.Point(bgPwrSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = bgPwrSw
            RegisterWidgetRefresh(function()
                bgPwrUpdate()
                bgPwrSw:SetAlpha(SVal("powerBgPowerColored", false) and 1 or 0.3)
            end)
            bgPwrSw:SetAlpha(SVal("powerBgPowerColored", false) and 1 or 0.3)

            -- Custom background color swatch.
            local bgSwGet = function()
                local c = SGet("customPowerBgColor")
                if c then return c.r, c.g, c.b end
                return 17/255, 17/255, 17/255
            end
            local bgSwSet = function(r, g, b)
                UNIT_DB_MAP[selectedUnit]().customPowerBgColor = { r=r, g=g, b=b }
                ReloadAndUpdate(); UpdatePreview()
            end
            local bgSw, bgSwUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgSwGet, bgSwSet, false, 20)
            bgSw._eabOrigClick = bgSw:GetScript("OnClick")
            bgSw:SetScript("OnClick", function(self)
                if SVal("powerBgPowerColored", false) then
                    SSet("powerBgPowerColored", false)
                    ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
                    return
                end
                if self._eabOrigClick then self._eabOrigClick(self) end
            end)
            bgSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgSw, "Custom Background Color") end)
            bgSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            PP.Point(bgSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = bgSw
            RegisterWidgetRefresh(function()
                bgSwUpdate()
                bgSw:SetAlpha(SVal("powerBgPowerColored", false) and 0.3 or 1)
            end)
            bgSw:SetAlpha(SVal("powerBgPowerColored", false) and 0.3 or 1)
        end
        -- Sync icon: Bar Background (right) -- background color + opacity
        do
            local rgn = sharedPowerRow3._rightRegion
            local function ApplyBgTo(keys)
                local src = UNIT_DB_MAP[selectedUnit]()
                local bc = src.customPowerBgColor or { r=17/255, g=17/255, b=17/255 }
                local bgA = src.customPowerBgAlpha or 100
                local bgPwr = src.powerBgPowerColored or false
                for _, key in ipairs(keys) do
                    if key ~= selectedUnit then
                        local d = UNIT_DB_MAP[key]()
                        d.customPowerBgColor = { r=bc.r, g=bc.g, b=bc.b }
                        d.customPowerBgAlpha = bgA
                        d.powerBgPowerColored = bgPwr
                    end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Bar Background to all Frames",
                onClick = function() ApplyBgTo(GROUP_UNIT_ORDER) end,
                isSynced = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    local function colEq(a, b)
                        if a == nil and b == nil then return true end
                        if a == nil or b == nil then return false end
                        return a.r == b.r and a.g == b.g and a.b == b.b
                    end
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local d = UNIT_DB_MAP[key]()
                        if not colEq(d.customPowerBgColor, src.customPowerBgColor) then return false end
                        if (d.customPowerBgAlpha or 100) ~= (src.customPowerBgAlpha or 100) then return false end
                        if (d.powerBgPowerColored or false) ~= (src.powerBgPowerColored or false) then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys) ApplyBgTo(checkedKeys) end,
                },
            })
        end
        -- Sync icon: Bar Color (left) -- fill/power color and gradient
        do
            local rgn = sharedPowerRow3._leftRegion
            local function ApplyColorTo(keys)
                local src = UNIT_DB_MAP[selectedUnit]()
                local pc = src.powerPercentPowerColor
                if pc == nil then pc = true end
                local fc = src.customPowerFillColor
                local gEn = src.powerGradientEnabled or false
                local gDir = src.powerGradientDir or "HORIZONTAL"
                local gc = src.powerGradientColor
                for _, key in ipairs(keys) do
                    if key ~= selectedUnit then
                        local d = UNIT_DB_MAP[key]()
                        d.powerPercentPowerColor = pc
                        if fc then d.customPowerFillColor = { r=fc.r, g=fc.g, b=fc.b }
                        else d.customPowerFillColor = nil end
                        d.powerGradientEnabled = gEn
                        d.powerGradientDir = gDir
                        if gc then d.powerGradientColor = { r=gc.r, g=gc.g, b=gc.b }
                        else d.powerGradientColor = nil end
                    end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Bar Color to all Frames",
                onClick = function() ApplyColorTo(GROUP_UNIT_ORDER) end,
                isSynced = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    local function colEq(a, b)
                        if a == nil and b == nil then return true end
                        if a == nil or b == nil then return false end
                        return a.r == b.r and a.g == b.g and a.b == b.b
                    end
                    local v = src.powerPercentPowerColor
                    if v == nil then v = true end
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local d = UNIT_DB_MAP[key]()
                        local ov = d.powerPercentPowerColor
                        if ov == nil then ov = true end
                        if ov ~= v then return false end
                        if not colEq(d.customPowerFillColor, src.customPowerFillColor) then return false end
                        if (d.powerGradientEnabled or false) ~= (src.powerGradientEnabled or false) then return false end
                        if not colEq(d.powerGradientColor, src.powerGradientColor) then return false end
                        if (d.powerGradientDir or "HORIZONTAL") ~= (src.powerGradientDir or "HORIZONTAL") then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys) ApplyColorTo(checkedKeys) end,
                },
            })
        end
        -- Gradient cog on Bar Color (left region)
        do
            local rgn = sharedPowerRow3._leftRegion
            local _, gradCogShow = EllesmereUI.BuildCogPopup({
                title = "Gradient Settings",
                rows = {
                    { type="toggle", label="Enable Gradient",
                      get=function() return SVal("powerGradientEnabled", false) end,
                      set=function(v) SSet("powerGradientEnabled", v); ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage() end },
                    { type="dropdown", label="Gradient Direction",
                      values={ HORIZONTAL="Horizontal", VERTICAL="Vertical" }, order={ "HORIZONTAL", "VERTICAL" },
                      get=function() return SVal("powerGradientDir", "HORIZONTAL") end,
                      set=function(v) SSet("powerGradientDir", v); ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage() end },
                },
            })
            MakeCogBtn(rgn, gradCogShow)
        end

        -- Row 4: Text Position + Text Color
        local sharedPowerRow4
        sharedPowerRow4, h = W:DualRow(parent, y,
            { type="dropdown", text="Text Position", values=ppTextValues, order=ppTextOrder,
              getValue=function() return SVal("powerPercentText", "none") end,
              setValue=function(v) SSet("powerPercentText", v); ReloadAndUpdate(); UpdatePreview() end },
            { type="multiSwatch", text="Text Color",
              swatches = {
                { tooltip = "Custom Text Color",
                  hasAlpha = false,
                  getValue = function()
                      local c = SGet("powerTextColor")
                      if c then return c.r, c.g, c.b end
                      return 1, 1, 1
                  end,
                  setValue = function(r, g, b)
                      UNIT_DB_MAP[selectedUnit]().powerTextColor = { r=r, g=g, b=b }
                      ReloadAndUpdate(); UpdatePreview()
                  end,
                  onClick = function(self)
                      local v = SVal("powerPercentTextPowerColor", false)
                      if v then
                          SSet("powerPercentTextPowerColor", false)
                          UpdatePreview()
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      return SVal("powerPercentTextPowerColor", false) and 0.3 or 1
                  end },
                { tooltip = "Power Colored Text",
                  hasAlpha = false,
                  getValue = function()
                      local _, pToken = UnitPowerType("player")
                      local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                      return info.r, info.g, info.b
                  end,
                  setValue = function() end,
                  onClick = function()
                      SSet("powerPercentTextPowerColor", true)
                      UNIT_DB_MAP[selectedUnit]().powerTextColor = nil
                      UpdatePreview()
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      return SVal("powerPercentTextPowerColor", false) and 1 or 0.3
                  end },
              } });  y = y - h
        -- Cogwheel on Text Position for size + x/y offsets (left of row 4)
        do
            local ppRgn = sharedPowerRow4._leftRegion
            local _, ppCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Text Position",
                rows = {
                    { type="slider", label="Size", min=6, max=100, step=1,
                      get=function() return SVal("powerPercentSize", 9) end,
                      set=function(v) SSet("powerPercentSize", v); UpdatePreview() end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return SVal("powerPercentX", 0) end,
                      set=function(v) SSet("powerPercentX", v); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() return SVal("powerPercentY", 0) end,
                      set=function(v) SSet("powerPercentY", v); UpdatePreview() end },
                },
            })
            local ppCogShow = ppCogShowRaw
            local ppCogBtn = MakeCogBtn(ppRgn, ppCogShow, nil, EllesmereUI.RESIZE_ICON)
            local function UpdatePPCogState()
                local isNone = SVal("powerPercentText", "none") == "none"
                ppCogBtn:SetAlpha(isNone and 0.15 or 0.4)
                ppCogBtn:SetEnabled(not isNone)
            end
            ppCogBtn:SetScript("OnEnter", function(self)
                if SVal("powerPercentText", "none") == "none" then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a text position other than none."))
                else self:SetAlpha(0.7) end
            end)
            ppCogBtn:SetScript("OnLeave", function(self) UpdatePPCogState(); EllesmereUI.HideWidgetTooltip() end)
            ppCogBtn:SetScript("OnClick", function(self) ppCogShow(self) end)
            UpdatePPCogState()
            RegisterWidgetRefresh(UpdatePPCogState)
        end
        -- Text Position sync (left of row 4)
        do
            local rgn = sharedPowerRow4._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Power Text Position to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().powerPercentText or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().powerPercentText = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().powerPercentText or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().powerPercentText or "none") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().powerPercentText or "none"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().powerPercentText = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        -- Sync icon: Text Color (right of row 4)
        do
            local rgn = sharedPowerRow4._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Text Color to all Frames",
                onClick = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    local v = src.powerPercentTextPowerColor or false
                    local tc = src.powerTextColor
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local d = UNIT_DB_MAP[key]()
                        d.powerPercentTextPowerColor = v
                        if tc then d.powerTextColor = { r=tc.r, g=tc.g, b=tc.b }
                        else d.powerTextColor = nil end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().powerPercentTextPowerColor or false
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().powerPercentTextPowerColor or false) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local src = UNIT_DB_MAP[selectedUnit]()
                        local v = src.powerPercentTextPowerColor or false
                        local tc = src.powerTextColor
                        for _, key in ipairs(checkedKeys) do
                            local d = UNIT_DB_MAP[key]()
                            d.powerPercentTextPowerColor = v
                            if tc then d.powerTextColor = { r=tc.r, g=tc.g, b=tc.b }
                            else d.powerTextColor = nil end
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 5: Power Border Style (+ cog) | Power Border Size (+ inline swatches)
        local pbTexValues, pbTexOrder = EllesmereUI.GetBorderTextureDropdown()
        local sharedPowerBorderRow
        sharedPowerBorderRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Border Style",
              disabled=function()
                  local pos = SVal("powerPosition", "below")
                  return pos ~= "detached_top" and pos ~= "detached_bottom"
              end,
              disabledTooltip=function()
                  return EllesmereUI.L("Border Style is only configurable when the Power Bar is detached. Attached Power Bars always use Solid.")
              end, rawTooltip=true,
              values=pbTexValues, order=pbTexOrder,
              getValue=function() return SGet("powerBorderStyle") or "solid" end,
              setValue=function(v)
                  SSet("powerBorderStyle", v)
                  SSet("powerBorderOffsetX", nil)
                  SSet("powerBorderOffsetY", nil)
                  SSet("powerBorderShiftX", nil)
                  SSet("powerBorderShiftY", nil)
                  if v ~= "solid" then
                      SSet("powerBorderColor", { r = 1, g = 1, b = 1 })
                      SSet("powerBorderAlpha", 1)
                  else
                      SSet("powerBorderColor", { r = 0, g = 0, b = 0 })
                      SSet("powerBorderAlpha", 1)
                  end
                  local defSz = EllesmereUI.GetBorderDefaultSize("unitframes", v)
                  if defSz then SSet("powerBorderSize", defSz) end
                  ReloadAndUpdate()
              end },
            { type="slider", text="Border Size",
              disabled=function()
                  local pos = SVal("powerPosition", "below")
                  return pos == "none"
              end,
              disabledTooltip=function()
                  return EllesmereUI.L("Border is only available when the Power Bar is shown.")
              end, rawTooltip=true,
              min=0, max=4, step=1, trackWidth=120,
              getValue=function() return SVal("powerBorderSize", 0) end,
              setValue=function(v)
                  SSet("powerBorderSize", v); ReloadAndUpdate()
              end });  y = y - h
        -- Cog for power border offset (left region)
        do
            local rgn = sharedPowerBorderRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Power Border Offset",
                rows = {
                    { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                      get = function()
                          local v = SGet("powerBorderOffsetX")
                          if v then return v end
                          local tex = SGet("powerBorderStyle") or "solid"
                          local sz = SVal("powerBorderSize", 0)
                          local dox = EllesmereUI.GetBorderDefaults("unitframes", tex, sz)
                          return dox
                      end,
                      set = function(v) SSet("powerBorderOffsetX", v); ReloadAndUpdate() end },
                    { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                      get = function()
                          local v = SGet("powerBorderOffsetY")
                          if v then return v end
                          local tex = SGet("powerBorderStyle") or "solid"
                          local sz = SVal("powerBorderSize", 0)
                          local _, doy = EllesmereUI.GetBorderDefaults("unitframes", tex, sz)
                          return doy
                      end,
                      set = function(v) SSet("powerBorderOffsetY", v); ReloadAndUpdate() end },
                    { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                      get = function()
                          local v = SGet("powerBorderShiftX")
                          if v then return v end
                          local tex = SGet("powerBorderStyle") or "solid"
                          local sz = SVal("powerBorderSize", 0)
                          local _, _, dsx = EllesmereUI.GetBorderDefaults("unitframes", tex, sz)
                          return dsx
                      end,
                      set = function(v) SSet("powerBorderShiftX", v == 0 and nil or v); ReloadAndUpdate() end },
                    { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                      get = function()
                          local v = SGet("powerBorderShiftY")
                          if v then return v end
                          local tex = SGet("powerBorderStyle") or "solid"
                          local sz = SVal("powerBorderSize", 0)
                          local _, _, _, dsy = EllesmereUI.GetBorderDefaults("unitframes", tex, sz)
                          return dsy
                      end,
                      set = function(v) SSet("powerBorderShiftY", v == 0 and nil or v); ReloadAndUpdate() end },
                    { type = "toggle", label = "Show Behind",
                      get = function() return SVal("powerBorderBehind", false) end,
                      set = function(v) SSet("powerBorderBehind", v); ReloadAndUpdate() end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local function UpdatePBCogVis()
                local pos = SVal("powerPosition", "below")
                local isDet = (pos == "detached_top" or pos == "detached_bottom")
                local tex = SGet("powerBorderStyle") or "solid"
                if not isDet or tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdatePBCogVis)
            UpdatePBCogVis()
        end
        -- Inline swatches on Border Size (right region)
        do
            local rightRgn = sharedPowerBorderRow._rightRegion
            local ctrl = rightRgn._lastInline or rightRgn._control
            -- Border color swatch
            local pbSwatch, updatePBSwatch = EllesmereUI.BuildColorSwatch(
                rightRgn, sharedPowerBorderRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("powerBorderColor") or { r = 0, g = 0, b = 0 }
                    return c.r, c.g, c.b, SVal("powerBorderAlpha", 1)
                end,
                function(r, g, b, a)
                    UNIT_DB_MAP[selectedUnit]().powerBorderColor = { r=r, g=g, b=b }
                    UNIT_DB_MAP[selectedUnit]().powerBorderAlpha = a
                    ReloadAndUpdate()
                end,
                true, 20)
            PP.Point(pbSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            pbSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(pbSwatch, "Border Color")
            end)
            pbSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            rightRgn._lastInline = pbSwatch
            EllesmereUI.RegisterWidgetRefresh(function() updatePBSwatch() end)
        end

        -- Row 6: Power Type override (player-only, spec-dependent)
        -- (was Row 5 before border rows were added)
        do
            local _, playerClass = UnitClass("player")
            -- Specs that offer an alternative power type on the player power bar.
            -- { defaultLabel, altLabel, altPowerType (Enum.PowerType value to force) }
            -- For Shadow Priest the alt is "no override" (nil) so UnitPowerType returns Insanity.
            local SPEC_POWER_ALTS = {
                DRUID  = {
                    [1] = { "Astral Power", "Mana",     0 },   -- Balance
                    [2] = { "Energy",       "Mana",     0 },   -- Feral
                    [3] = { "Rage",         "Mana",     0 },   -- Guardian
                },
                PRIEST = {
                    [3] = { "Mana",         "Insanity", nil },  -- Shadow (default is our Mana override)
                },
                SHAMAN = {
                    [1] = { "Maelstrom",    "Mana",     0 },   -- Elemental
                },
            }
            local classAlts = SPEC_POWER_ALTS[playerClass]
            if classAlts then
                local spec = GetSpecialization and GetSpecialization()
                local data = spec and classAlts[spec]
                local ptValues = {}
                local ptOrder  = { "default", "alt" }
                if data then
                    ptValues["default"] = data[1]
                    ptValues["alt"]     = data[2]
                end

                local sharedPowerRow5
                sharedPowerRow5, h = W:DualRow(parent, y,
                    { type="dropdown", text="Power Type",
                      values = ptValues, order = ptOrder,
                      getValue = function()
                          local s = GetSpecialization and GetSpecialization()
                          if not s or not classAlts[s] then return "default" end
                          local ov = UNIT_DB_MAP["player"]().powerTypeOverride
                          if ov and ov[s] then return "alt" end
                          return "default"
                      end,
                      setValue = function(v)
                          local s = GetSpecialization and GetSpecialization()
                          if not s then return end
                          local pdb = UNIT_DB_MAP["player"]()
                          if v == "alt" then
                              if not pdb.powerTypeOverride then pdb.powerTypeOverride = {} end
                              pdb.powerTypeOverride[s] = true
                          else
                              if pdb.powerTypeOverride then pdb.powerTypeOverride[s] = nil end
                          end
                          ReloadAndUpdate()
                      end },
                    { type="label", text="" }); y = y - h

                local function UpdatePowerTypeRow()
                    local s = GetSpecialization and GetSpecialization()
                    if selectedUnit == "player" and s and classAlts[s] then
                        sharedPowerRow5:Show()
                    else
                        sharedPowerRow5:Hide()
                    end
                end
                RegisterWidgetRefresh(UpdatePowerTypeRow)
                UpdatePowerTypeRow()
            end
        end

        _, h = W:Spacer(parent, y, 20); y = y - h

        -------------------------------------------------------------------
        --  CAST BAR
        -------------------------------------------------------------------
        local sharedCastHeader
        sharedCastHeader, h = W:SectionHeader(parent, "CAST BAR", y); y = y - h

        -- Helper: get/set castbar visibility per unit
        local function GetCastbarEnabled(unitKey)
            if unitKey == "player" then
                return UNIT_DB_MAP.player().showPlayerCastbar or false
            else
                return UNIT_DB_MAP[unitKey]().showCastbar ~= false
            end
        end
        local function SetCastbarEnabled(unitKey, val)
            if unitKey == "player" then
                UNIT_DB_MAP.player().showPlayerCastbar = val
            else
                UNIT_DB_MAP[unitKey]().showCastbar = val
            end
        end

        -- Height getter/setter: player -> playerCastbarHeight, target/focus -> castbarHeight
        local function GetCastbarHeight()
            local u = selectedUnit
            if u == "player" then
                local v = UNIT_DB_MAP.player().playerCastbarHeight or 0
                return (v <= 0) and 14 or v
            else
                return UNIT_DB_MAP[u]().castbarHeight or 14
            end
        end
        local function SetCastbarHeight(v)
            if selectedUnit == "player" then UNIT_DB_MAP.player().playerCastbarHeight = v
            else UNIT_DB_MAP[selectedUnit]().castbarHeight = v end
        end

        -- Player-only hint: the cast bar configured here is a compact mini bar
        -- shown under the player frame. The full-size player cast bar is owned by
        -- the Resource & Cast Bars module, so deep-link the user straight to it.
        -- (The page fully rebuilds when the unit dropdown changes, so gating on
        -- selectedUnit here is enough -- it re-evaluates per unit.)
        if selectedUnit == "player" then
            local ar, ag, ab = EllesmereUI.GetAccentColor()
            ar, ag, ab = ar or 12/255, ag or 210/255, ab or 157/255
            local accentHex = string.format("|cff%02x%02x%02x",
                math.floor(ar * 255 + 0.5),
                math.floor(ag * 255 + 0.5),
                math.floor(ab * 255 + 0.5))
            local hintText = EllesmereUI.Lf("For player frame, this provides a simple, mini castbar below player frame. To edit the main player cast bar, %sclick here|r", accentHex)
            -- Full-width label (passing nil as the right slot expands the left
            -- region to the whole row) so the text renders via the panel's own
            -- widget path. A transparent button over the row makes the line
            -- clickable -> Resource & Cast Bars > Cast Bar (accent "click here"
            -- is the visual affordance).
            local hintRow
            hintRow, h = W:DualRow(parent, y, { type = "label", text = hintText }, nil)
            -- The label is single-line by default; let this long hint wrap inside
            -- the full-width row so "click here" stays on screen.
            local lbl = hintRow._leftRegion and hintRow._leftRegion._label
            if lbl then
                lbl:SetJustifyH("LEFT")
                lbl:SetWordWrap(true)
                local rw = hintRow._leftRegion:GetWidth()
                if not rw or rw < 80 then rw = 300 end
                lbl:SetWidth(rw - 40)
            end
            local clickRgn = hintRow._leftRegion or hintRow
            local linkBtn = CreateFrame("Button", nil, clickRgn)
            linkBtn:SetAllPoints(clickRgn)
            linkBtn:SetFrameLevel(clickRgn:GetFrameLevel() + 5)
            linkBtn:SetScript("OnClick", function()
                EllesmereUI:NavigateToElementSettings("EllesmereUIResourceBars", "Cast Bar")
            end)
            linkBtn:SetScript("OnEnter", function(self)
                EllesmereUI.ShowWidgetTooltip(self, "Open Resource & Cast Bars > Cast Bar")
            end)
            linkBtn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            y = y - h
        end

        -- Row 1: Show Cast Bar (toggle + fill swatch) | Height (slider).
        -- This row (and the player hint above) stays visible while the cast
        -- bar is off; the rows below it are hidden entirely. Height composes
        -- the castbar-off disable into the size-match guard.
        local sharedCastRow1
        local cbKey = selectedUnit .. "Castbar"
        local cbhDis, cbhTip, cbhRaw = EllesmereUI.MatchGuard(cbKey, "Height",
            function() return not GetCastbarEnabled(selectedUnit) end,
            "Show Cast Bar")
        sharedCastRow1, h = W:DualRow(parent, y,
            { type="toggle", text="Show Cast Bar",
              getValue=function() return GetCastbarEnabled(selectedUnit) end,
              -- DependentSetValue: the rows below Row 1 are hidden while the
              -- cast bar is off; the toggle flip forces the full rebuild.
              setValue=EllesmereUI.DependentSetValue(
                  function() return GetCastbarEnabled(selectedUnit) end,
                  function(v) SetCastbarEnabled(selectedUnit, v); ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage() end) },
            { type="slider", text="Height", min=1, max=40, step=1,
              disabled=cbhDis, disabledTooltip=cbhTip, rawTooltip=cbhRaw,
              getValue=GetCastbarHeight,
              setValue=function(v) SetCastbarHeight(v); ReloadAndUpdate(); UpdatePreview() end });  y = y - h
        -- Inline cast color swatch(es) on Show Cast Bar
        do
            local leftRgn = sharedCastRow1._leftRegion
            local function AddCastColorSwatch(tooltip, colorKey, fallback, disabledFn)
                local sw, updateSw = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5,
                    function()
                        local c = SGetSupported(colorKey)
                        c = c or fallback
                        return c.r, c.g, c.b, 1
                    end,
                    function(r, g, b)
                        SSetSupported(colorKey, { r = r, g = g, b = b })
                        ReloadAndUpdate(); UpdatePreview()
                    end, false, 20)
                PP.Point(sw, "RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
                sw:SetScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, tooltip) end)
                sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                leftRgn._lastInline = sw
                -- Optional disabled gate: grey (0.3) + non-interactive when
                -- disabledFn returns true. Used by the default-off Interrupt Ready
                -- Mid-Cast swatch so it tracks its enable toggle in the cog.
                if disabledFn then
                    local function applySwState()
                        local off = disabledFn()
                        sw:SetAlpha(off and 0.3 or 1)
                        sw:EnableMouse(not off)
                        if updateSw then updateSw() end
                    end
                    applySwState()
                    EllesmereUI.RegisterWidgetRefresh(applySwState)
                end
            end
            if selectedUnit == "target" or selectedUnit == "focus" then
                -- Inline swatches anchor right-to-left; add Mid-Cast first so it
                -- sits rightmost, then CD, then interruptible (matches the
                -- Interruptible / On CD / Mid-Cast order shown on Nameplates). The
                -- Mid-Cast swatch greys out unless its enable toggle in the cog is on.
                AddCastColorSwatch("Interrupt Ready Mid-Cast", "castbarInterruptMidCastColor", { r = 0.318, g = 0.820, b = 0.357 },
                    function() return not SValSupported("castbarInterruptMidCastEnabled", false) end)
                AddCastColorSwatch("Interrupt on CD", "castbarInterruptReadyColor", { r = 0.92, g = 0.35, b = 0.20 })
                AddCastColorSwatch("Uninterruptible Cast", "castbarUninterruptibleColor", { r = 0.5, g = 0.5, b = 0.5 })
                AddCastColorSwatch("Interruptible Cast", "castbarFillColor", { r = 0.863, g = 0.820, b = 0.639 })
            else
                AddCastColorSwatch("Fill Color", "castbarFillColor", { r = 1, g = 0.7, b = 0 })
            end
        end
        -- Sync icon: Show Cast Bar + Fill Color (left region)
        do
            local rgn = sharedCastRow1._leftRegion
            local isKickUnit = selectedUnit == "target" or selectedUnit == "focus"
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = isKickUnit and "Apply Show Cast Bar and Cast Color to Target and Focus"
                    or "Apply Show Cast Bar and Fill Color to all Frames",
                onClick = function()
                    local v = GetCastbarEnabled(selectedUnit)
                    local c = UNIT_DB_MAP[selectedUnit]().castbarFillColor
                    local readyC = isKickUnit and UNIT_DB_MAP[selectedUnit]().castbarInterruptReadyColor
                    local unintC = isKickUnit and UNIT_DB_MAP[selectedUnit]().castbarUninterruptibleColor
                    local keys = isKickUnit and { "target", "focus" } or GROUP_UNIT_ORDER
                    for _, key in ipairs(keys) do
                        SetCastbarEnabled(key, v)
                        if c then UNIT_DB_MAP[key]().castbarFillColor = { r = c.r, g = c.g, b = c.b } end
                        if readyC then UNIT_DB_MAP[key]().castbarInterruptReadyColor = { r = readyC.r, g = readyC.g, b = readyC.b } end
                        if unintC then UNIT_DB_MAP[key]().castbarUninterruptibleColor = { r = unintC.r, g = unintC.g, b = unintC.b } end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = GetCastbarEnabled(selectedUnit)
                    local c = UNIT_DB_MAP[selectedUnit]().castbarFillColor
                    local readyC = isKickUnit and UNIT_DB_MAP[selectedUnit]().castbarInterruptReadyColor
                    local unintC = isKickUnit and UNIT_DB_MAP[selectedUnit]().castbarUninterruptibleColor
                    local keys = isKickUnit and { "target", "focus" } or GROUP_UNIT_ORDER
                    for _, key in ipairs(keys) do
                        if GetCastbarEnabled(key) ~= v then return false end
                        local kc = UNIT_DB_MAP[key]().castbarFillColor
                        if c and kc then
                            if kc.r ~= c.r or kc.g ~= c.g or kc.b ~= c.b then return false end
                        elseif c ~= kc then return false end
                        if isKickUnit then
                            local kr = UNIT_DB_MAP[key]().castbarInterruptReadyColor
                            if readyC and kr then
                                if kr.r ~= readyC.r or kr.g ~= readyC.g or kr.b ~= readyC.b then return false end
                            elseif readyC ~= kr then return false end
                            local ku = UNIT_DB_MAP[key]().castbarUninterruptibleColor
                            if unintC and ku then
                                if ku.r ~= unintC.r or ku.g ~= unintC.g or ku.b ~= unintC.b then return false end
                            elseif unintC ~= ku then return false end
                        end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = GetCastbarEnabled(selectedUnit)
                        local c = UNIT_DB_MAP[selectedUnit]().castbarFillColor
                        local readyC = isKickUnit and UNIT_DB_MAP[selectedUnit]().castbarInterruptReadyColor
                        local unintC = isKickUnit and UNIT_DB_MAP[selectedUnit]().castbarUninterruptibleColor
                        for _, key in ipairs(checkedKeys) do
                            SetCastbarEnabled(key, v)
                            if c then UNIT_DB_MAP[key]().castbarFillColor = { r = c.r, g = c.g, b = c.b } end
                            if readyC and (key == "target" or key == "focus") then
                                UNIT_DB_MAP[key]().castbarInterruptReadyColor = { r = readyC.r, g = readyC.g, b = readyC.b }
                            end
                            if unintC and (key == "target" or key == "focus") then
                                UNIT_DB_MAP[key]().castbarUninterruptibleColor = { r = unintC.r, g = unintC.g, b = unintC.b }
                            end
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        -- Inline cog on Show Cast Bar: Hide When Idle (all units) plus the
        -- kick-ready tick (target/focus only). These stay out of the Show Cast
        -- Bar sync icon on purpose -- they are per-unit detail settings.
        do
            local rgn = sharedCastRow1._leftRegion
            local cogRows = {
                { type = "toggle", label = "Hide When Idle",
                  tooltip = "Only show the cast bar while a cast is in progress; hide it the rest of the time.",
                  get = function()
                      local v = UNIT_DB_MAP[selectedUnit]().castbarHideWhenInactive
                      if v == nil then return true end
                      return v
                  end,
                  set = function(v)
                      UNIT_DB_MAP[selectedUnit]().castbarHideWhenInactive = v
                      ReloadAndUpdate(); UpdatePreview()
                  end },
                { type = "slider", label = "Fill Opacity", min = 0, max = 100, step = 1,
                  tooltip = "Opacity of the cast bar fill; below 100 the world shows through the fill instead of the background.",
                  get = function() return UNIT_DB_MAP[selectedUnit]().castFillOpacity or 100 end,
                  set = function(v)
                      UNIT_DB_MAP[selectedUnit]().castFillOpacity = v
                      ReloadAndUpdate(); UpdatePreview()
                  end },
                -- Global (not per-frame, not synced): lift the player/target/focus
                -- cast bars to HIGH strata. Default on = existing behavior; off leaves
                -- them at the frame's strata. A single db.profile key drives all three.
                { type = "toggle", label = "Raise Cast Bar Strata (All)",
                  tooltip = "Lifts the player, target, and focus cast bars above other frames so they are never hidden behind them.",
                  get = function() return db.profile.raiseCastbarStrata ~= false end,
                  set = function(v)
                      db.profile.raiseCastbarStrata = v
                      ReloadAndUpdate()
                  end },
            }
            if selectedUnit == "target" or selectedUnit == "focus" then
                cogRows[#cogRows + 1] = { type = "toggle", label = "Show Kick Ready Mid-Cast Tick",
                    tooltip = "Shows a small white tick mark on the cast bar at the point where the cast will be when your interrupt comes off cooldown.",
                    get = function()
                        local v = SGetSupported("castbarKickTickEnabled")
                        if v == nil then return true end
                        return v
                    end,
                    set = function(v)
                        SSetSupported("castbarKickTickEnabled", v)
                        ReloadAndUpdate(); UpdatePreview()
                    end }
                cogRows[#cogRows + 1] = { type = "toggle", label = "Show Kick Ready Mid-Cast Bar",
                    tooltip = "When your interrupt is on cooldown now but will be ready before the enemy cast finishes, color the part of the cast bar during which your interrupt will be available. The color clears the instant your interrupt comes off cooldown.",
                    get = function()
                        local v = SGetSupported("castbarInterruptMidCastEnabled")
                        if v == nil then return false end
                        return v
                    end,
                    set = function(v)
                        SSetSupported("castbarInterruptMidCastEnabled", v)
                        ReloadAndUpdate(); UpdatePreview()
                        -- Refresh the page so the inline Mid-Cast color swatch
                        -- greys/ungreys immediately; the cog popup stays open.
                        EllesmereUI:RefreshPage()
                    end }
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Cast Bar",
                rows = cogRows,
            })
            MakeCogBtn(rgn, cogShow)
        end
        -- Sync icon: Cast Bar Height (right region)
        do
            local rgn = sharedCastRow1._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Cast Bar Height to all Frames",
                onClick = function()
                    local v = GetCastbarHeight()
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key == "player" then UNIT_DB_MAP[key]().playerCastbarHeight = v
                        else UNIT_DB_MAP[key]().castbarHeight = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = GetCastbarHeight()
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local kv
                        if key == "player" then kv = UNIT_DB_MAP[key]().playerCastbarHeight or 20
                        else kv = UNIT_DB_MAP[key]().castbarHeight or 20 end
                        if kv ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = GetCastbarHeight()
                        for _, key in ipairs(checkedKeys) do
                            if key == "player" then UNIT_DB_MAP[key]().playerCastbarHeight = v
                            else UNIT_DB_MAP[key]().castbarHeight = v end
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Rows 2-4 are HIDDEN entirely while Show Cast Bar is off (the toggle's
        -- DependentSetValue forces the rebuild on flips). Row locals are
        -- hoisted above the gate: the element-nav map at the end of the
        -- builder references them, and an in-gate declaration would leave the
        -- map reading nil globals even with the cast bar enabled.
        local castRow2, castTextRow, castTargetRow
        if GetCastbarEnabled(selectedUnit) then
        -- Row 2: Show Icon | Bar Background (opacity slider + inline color swatch)
        local function GetShowIcon()
            if selectedUnit == "player" then
                local v = UNIT_DB_MAP.player().showPlayerCastIcon
                if v == nil then return true end
                return v
            else
                local v = UNIT_DB_MAP[selectedUnit]().showCastIcon
                if v == nil then return true end
                return v
            end
        end
        local function SetShowIcon(val)
            if selectedUnit == "player" then
                UNIT_DB_MAP.player().showPlayerCastIcon = val
            else
                UNIT_DB_MAP[selectedUnit]().showCastIcon = val
            end
        end
        castRow2, h = W:DualRow(parent, y,
            { type="toggle", text="Show Icon",
              getValue=GetShowIcon,
              setValue=function(v) SetShowIcon(v); ReloadAndUpdate(); UpdatePreview() end },
            { type="slider", text="Bar Background", min=0, max=100, step=1,
              getValue=function() return math.floor(SValSupported("castBgAlpha", 0.5) * 100 + 0.5) end,
              setValue=function(v) UNIT_DB_MAP[selectedUnit]().castBgAlpha = v / 100; ReloadAndUpdate(); UpdatePreview() end });  y = y - h
        -- Sync icon: Show Icon (left)
        do
            local rgn = castRow2._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Show Icon to all Frames",
                onClick = function()
                    local v = GetShowIcon()
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key == "player" then UNIT_DB_MAP[key]().showPlayerCastIcon = v
                        else UNIT_DB_MAP[key]().showCastIcon = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = GetShowIcon()
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local kv
                        if key == "player" then
                            kv = UNIT_DB_MAP[key]().showPlayerCastIcon
                            if kv == nil then kv = true end
                        else
                            kv = UNIT_DB_MAP[key]().showCastIcon
                            if kv == nil then kv = true end
                        end
                        if kv ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = GetShowIcon()
                        for _, key in ipairs(checkedKeys) do
                            if key == "player" then UNIT_DB_MAP[key]().showPlayerCastIcon = v
                            else UNIT_DB_MAP[key]().showCastIcon = v end
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        -- Inline cog on the Show Icon toggle: "Make Icon Part of the Bar",
        -- "Show Icon on Right", and additive Offset X/Y icon nudges.
        -- Operates on the currently selected unit (player/target/focus).
        do
            local rgn = castRow2._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Cast Icon",
                rows = {
                    { type = "toggle", label = "Make Icon Part of the Bar",
                      tooltip = "This makes it so the width of the cast bar includes the icon, rather than placing it to the left of the cast bars width.",
                      get = function()
                          if selectedUnit == "player" then
                              return UNIT_DB_MAP.player().playerCastbarIconInWidth ~= false
                          end
                          return UNIT_DB_MAP[selectedUnit]().castbarIconInWidth ~= false
                      end,
                      set = function(v)
                          if selectedUnit == "player" then
                              UNIT_DB_MAP.player().playerCastbarIconInWidth = v
                          else
                              UNIT_DB_MAP[selectedUnit]().castbarIconInWidth = v
                          end
                          ReloadAndUpdate(); UpdatePreview()
                      end },
                    { type = "toggle", label = "Show Icon on Right",
                      tooltip = "Place the cast icon on the right side of the bar instead of the left.",
                      get = function()
                          if selectedUnit == "player" then
                              return UNIT_DB_MAP.player().playerCastbarIconRight == true
                          end
                          return UNIT_DB_MAP[selectedUnit]().castbarIconRight == true
                      end,
                      set = function(v)
                          if selectedUnit == "player" then
                              UNIT_DB_MAP.player().playerCastbarIconRight = v
                          else
                              UNIT_DB_MAP[selectedUnit]().castbarIconRight = v
                          end
                          ReloadAndUpdate(); UpdatePreview()
                      end },
                    { type = "slider", label = "Offset X", min = -50, max = 50, step = 1,
                      get = function()
                          if selectedUnit == "player" then
                              return UNIT_DB_MAP.player().playerCastIconOffsetX or 0
                          end
                          return UNIT_DB_MAP[selectedUnit]().castIconOffsetX or 0
                      end,
                      set = function(v)
                          if selectedUnit == "player" then
                              UNIT_DB_MAP.player().playerCastIconOffsetX = v
                          else
                              UNIT_DB_MAP[selectedUnit]().castIconOffsetX = v
                          end
                          ReloadAndUpdate(); UpdatePreview()
                      end },
                    { type = "slider", label = "Offset Y", min = -50, max = 50, step = 1,
                      get = function()
                          if selectedUnit == "player" then
                              return UNIT_DB_MAP.player().playerCastIconOffsetY or 0
                          end
                          return UNIT_DB_MAP[selectedUnit]().castIconOffsetY or 0
                      end,
                      set = function(v)
                          if selectedUnit == "player" then
                              UNIT_DB_MAP.player().playerCastIconOffsetY = v
                          else
                              UNIT_DB_MAP[selectedUnit]().castIconOffsetY = v
                          end
                          ReloadAndUpdate(); UpdatePreview()
                      end },
                },
            })
            MakeCogBtn(rgn, cogShow)
        end
        -- Inline color swatch on Bar Background (right region). Defaults to the
        -- cast bar's hardcoded background color (black) until the user sets one.
        do
            local rgn = castRow2._rightRegion
            local bgSwGet = function()
                local c = UNIT_DB_MAP[selectedUnit]().castBgColor
                if c then return c.r, c.g, c.b end
                return 0, 0, 0
            end
            local bgSwSet = function(r, g, b)
                UNIT_DB_MAP[selectedUnit]().castBgColor = { r=r, g=g, b=b }
                ReloadAndUpdate(); UpdatePreview()
            end
            local bgSw, bgSwUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgSwGet, bgSwSet, false, 20)
            PP.Point(bgSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = bgSw
            RegisterWidgetRefresh(function() bgSwUpdate() end)
        end
        -- Sync icon: Bar Background (right) -- background color + opacity
        do
            local rgn = castRow2._rightRegion
            local function ApplyCastBgTo(keys)
                local src = UNIT_DB_MAP[selectedUnit]()
                local bc = src.castBgColor or { r=0, g=0, b=0 }
                local bgA = src.castBgAlpha
                for _, key in ipairs(keys) do
                    if key ~= selectedUnit then
                        local d = UNIT_DB_MAP[key]()
                        d.castBgColor = { r=bc.r, g=bc.g, b=bc.b }
                        d.castBgAlpha = bgA
                    end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Bar Background to all Frames",
                onClick = function() ApplyCastBgTo(GROUP_UNIT_ORDER) end,
                isSynced = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    local function colEq(a, b)
                        -- A nil color means "use the hardcoded default (black)", so a
                        -- nil color and an explicit black must compare equal. Without
                        -- this the icon never reads as synced after Apply to All (the
                        -- source stays nil while the targets get an explicit black).
                        local ar, ag, ab = a and a.r or 0, a and a.g or 0, a and a.b or 0
                        local cr, cg, cb = b and b.r or 0, b and b.g or 0, b and b.b or 0
                        return ar == cr and ag == cg and ab == cb
                    end
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local d = UNIT_DB_MAP[key]()
                        if not colEq(d.castBgColor, src.castBgColor) then return false end
                        if (d.castBgAlpha or 0.5) ~= (src.castBgAlpha or 0.5) then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys) ApplyCastBgTo(checkedKeys) end,
                },
            })
        end

        -- Row 3: Spell Name (position dropdown + swatch + cog) | Duration (position dropdown + swatch + cog)
        -- Cast text position dropdowns mirror nameplates: Name/Target are None/Left/Right/
        -- Center; the name and target may not share a side (setting one onto the other's
        -- side bumps the other to None). Duration is None/Right/Left -- "None" sets
        -- showCastDuration=false; it reserves a slot on its side and pushes same-side text.
        -- Size / X / Y live in each row's inline cog. Existing users keep their layout:
        -- Name defaults Left, Target Right, Duration Right.
        local castTextPosValues = { none = "None", left = "Left", right = "Right", center = "Center" }
        local castTextPosOrder = { "none", "left", "right", "center" }
        castTextRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Spell Name", values=castTextPosValues, order=castTextPosOrder,
              getValue=function() return SValSupported("castSpellNameSide", "left") end,
              setValue=function(v)
                local s = UNIT_DB_MAP[selectedUnit]()
                s.castSpellNameSide = v
                if v ~= "none" and (s.showCastTarget ~= false) and (s.castSpellTargetSide or "right") == v then
                    s.showCastTarget = false
                end
                ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Duration",
              values={ none = "None", right = "Right", left = "Left" },
              order={ "none", "right", "left" },
              getValue=function()
                if SValSupported("showCastDuration", true) == false then return "none" end
                return SValSupported("castDurationSide", "right")
              end,
              setValue=function(v)
                local s = UNIT_DB_MAP[selectedUnit]()
                if v == "none" then
                    s.showCastDuration = false
                else
                    s.showCastDuration = true
                    s.castDurationSide = v
                end
                ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
              end });  y = y - h
        -- Inline color swatch on Spell Name Size
        do
            local snRgn = castTextRow._leftRegion
            local snSw = EllesmereUI.BuildColorSwatch(snRgn, snRgn:GetFrameLevel() + 5,
                function()
                    local c = SGetSupported("castSpellNameColor")
                    c = c or { r=1, g=1, b=1 }
                    return c.r, c.g, c.b, 1
                end,
                function(r, g, b)
                    UNIT_DB_MAP[selectedUnit]().castSpellNameColor = { r=r, g=g, b=b }
                    ReloadAndUpdate(); UpdatePreview()
                end, false, 20)
            snSw:SetPoint("RIGHT", snRgn._lastInline or snRgn._control, "LEFT", -12, 0)
            snRgn._lastInline = snSw
        end
        -- Inline cog on Spell Name Size: X/Y offsets (+ target/focus combine)
        do
            local snCogRgn = castTextRow._leftRegion
            local snCogRows = {
                    { type="slider", label="Size", min=6, max=20, step=1,
                      get=function() return SValSupported("castSpellNameSize", 11) end,
                      set=function(v) SSetSupported("castSpellNameSize", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return SValSupported("castSpellNameX", 0) end,
                      set=function(v) SSetSupported("castSpellNameX", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() return SValSupported("castSpellNameY", 0) end,
                      set=function(v) SSetSupported("castSpellNameY", v); ReloadAndUpdate(); UpdatePreview() end },
            }
            if selectedUnit == "target" or selectedUnit == "focus" then
                snCogRows[#snCogRows + 1] = { type="toggle", label="Combine Spell Name and Target",
                    tooltip="Appends the cast target to the spell name (Spell Name - Target), class colored, and disables the separate Spell Target display.",
                    get=function() return SValSupported("castCombineNameTarget", false) end,
                    set=function(v)
                        SSetSupported("castCombineNameTarget", v)
                        ReloadAndUpdate(); UpdatePreview()
                        -- Grey/ungrey the Spell Name dropdown immediately.
                        EllesmereUI:RefreshPage()
                    end }
            end
            local _, snCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Spell Name",
                rows = snCogRows,
            })
            local snCogBtn = MakeCogBtn(snCogRgn, snCogShowRaw)
            snCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            snCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            snCogBtn:SetScript("OnClick", function(self) snCogShowRaw(self) end)
        end
        -- Inline color swatch on Duration Size
        do
            local dtRgn = castTextRow._rightRegion
            local dtSw = EllesmereUI.BuildColorSwatch(dtRgn, dtRgn:GetFrameLevel() + 5,
                function()
                    local c = SGetSupported("castDurationColor")
                    c = c or { r=1, g=1, b=1 }
                    return c.r, c.g, c.b, 1
                end,
                function(r, g, b)
                    UNIT_DB_MAP[selectedUnit]().castDurationColor = { r=r, g=g, b=b }
                    ReloadAndUpdate(); UpdatePreview()
                end, false, 20)
            dtSw:SetPoint("RIGHT", dtRgn._lastInline or dtRgn._control, "LEFT", -12, 0)
            dtRgn._lastInline = dtSw
        end
        -- Inline cog on Duration Size: toggle + X/Y offsets
        do
            local dtCogRgn = castTextRow._rightRegion
            local _, dtCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Duration",
                rows = {
                    { type="slider", label="Size", min=6, max=20, step=1,
                      get=function() return SValSupported("castDurationSize", 10) end,
                      set=function(v) SSetSupported("castDurationSize", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return SValSupported("castDurationX", 0) end,
                      set=function(v) SSetSupported("castDurationX", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() return SValSupported("castDurationY", 0) end,
                      set=function(v) SSetSupported("castDurationY", v); ReloadAndUpdate(); UpdatePreview() end },
                },
            })
            local dtCogBtn = MakeCogBtn(dtCogRgn, dtCogShowRaw)
            dtCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            dtCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            dtCogBtn:SetScript("OnClick", function(self) dtCogShowRaw(self) end)
        end

        -- Sync icons: Spell Name Size + Color (left) and Duration Size + Color (right)
        do
            local rgn = castTextRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Spell Name Size and Color to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().castSpellNameSize or 11
                    local c = UNIT_DB_MAP[selectedUnit]().castSpellNameColor
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        UNIT_DB_MAP[key]().castSpellNameSize = v
                        if c then UNIT_DB_MAP[key]().castSpellNameColor = { r=c.r, g=c.g, b=c.b } end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().castSpellNameSize or 11
                    local c = UNIT_DB_MAP[selectedUnit]().castSpellNameColor
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().castSpellNameSize or 11) ~= v then return false end
                        local kc = UNIT_DB_MAP[key]().castSpellNameColor
                        if c and kc then
                            if kc.r ~= c.r or kc.g ~= c.g or kc.b ~= c.b then return false end
                        elseif c ~= kc then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().castSpellNameSize or 11
                        local c = UNIT_DB_MAP[selectedUnit]().castSpellNameColor
                        for _, key in ipairs(checkedKeys) do
                            UNIT_DB_MAP[key]().castSpellNameSize = v
                            if c then UNIT_DB_MAP[key]().castSpellNameColor = { r=c.r, g=c.g, b=c.b } end
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = castTextRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Duration Size and Color to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().castDurationSize or 10
                    local c = UNIT_DB_MAP[selectedUnit]().castDurationColor
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        UNIT_DB_MAP[key]().castDurationSize = v
                        if c then UNIT_DB_MAP[key]().castDurationColor = { r=c.r, g=c.g, b=c.b } end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().castDurationSize or 10
                    local c = UNIT_DB_MAP[selectedUnit]().castDurationColor
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().castDurationSize or 10) ~= v then return false end
                        local kc = UNIT_DB_MAP[key]().castDurationColor
                        if c and kc then
                            if kc.r ~= c.r or kc.g ~= c.g or kc.b ~= c.b then return false end
                        elseif c ~= kc then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().castDurationSize or 10
                        local c = UNIT_DB_MAP[selectedUnit]().castDurationColor
                        for _, key in ipairs(checkedKeys) do
                            UNIT_DB_MAP[key]().castDurationSize = v
                            if c then UNIT_DB_MAP[key]().castDurationColor = { r=c.r, g=c.g, b=c.b } end
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 4: Spell Target (position dropdown + swatch + cog) | Reverse Fill
        castTargetRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Spell Target", values=castTextPosValues, order=castTextPosOrder,
              -- Combine Spell Name and Target appends the target to the spell
              -- name string; the separate target display greys out and no-ops
              -- while it is on.
              disabled=function()
                  if selectedUnit ~= "target" and selectedUnit ~= "focus" then return false end
                  local s = UNIT_DB_MAP[selectedUnit]()
                  return (s and s.castCombineNameTarget == true) and true or false
              end,
              disabledTooltip="This option requires Combine Spell Name and Target to be disabled.",
              getValue=function()
                if SValSupported("showCastTarget", true) == false then return "none" end
                return SValSupported("castSpellTargetSide", "right")
              end,
              setValue=function(v)
                local s = UNIT_DB_MAP[selectedUnit]()
                if v == "none" then
                    s.showCastTarget = false
                else
                    s.showCastTarget = true
                    s.castSpellTargetSide = v
                    if (s.castSpellNameSide or "left") == v then s.castSpellNameSide = "none" end
                end
                ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Reverse Fill",
              getValue=function() return SValSupported("castReverseFill", false) end,
              setValue=function(v) SSetSupported("castReverseFill", v); ReloadAndUpdate(); UpdatePreview() end });  y = y - h
        -- Inline color swatch on Spell Target Size
        do
            local trgRgn = castTargetRow._leftRegion
            local trgSw = EllesmereUI.BuildColorSwatch(trgRgn, trgRgn:GetFrameLevel() + 5,
                function()
                    local c = SGetSupported("castSpellTargetColor")
                    c = c or { r=1, g=1, b=1 }
                    return c.r, c.g, c.b, 1
                end,
                function(r, g, b)
                    UNIT_DB_MAP[selectedUnit]().castSpellTargetColor = { r=r, g=g, b=b }
                    ReloadAndUpdate(); UpdatePreview()
                end, false, 20)
            trgSw:SetPoint("RIGHT", trgRgn._lastInline or trgRgn._control, "LEFT", -12, 0)
            trgRgn._lastInline = trgSw
        end
        -- Inline cog on Spell Target Size: toggle + X/Y offsets
        do
            local tgCogRgn = castTargetRow._leftRegion
            local _, tgCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Spell Target",
                rows = {
                    { type="slider", label="Size", min=6, max=20, step=1,
                      get=function() return SValSupported("castSpellTargetSize", 10) end,
                      set=function(v) SSetSupported("castSpellTargetSize", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return SValSupported("castSpellTargetX", 0) end,
                      set=function(v) SSetSupported("castSpellTargetX", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() return SValSupported("castSpellTargetY", 0) end,
                      set=function(v) SSetSupported("castSpellTargetY", v); ReloadAndUpdate(); UpdatePreview() end },
                },
            })
            local tgCogBtn = MakeCogBtn(tgCogRgn, tgCogShowRaw)
            tgCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            tgCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            tgCogBtn:SetScript("OnClick", function(self) tgCogShowRaw(self) end)
        end

        -- Sync icons: Spell Target Size + Color (left)
        do
            local rgn = castTargetRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Spell Target Size and Color to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().castSpellTargetSize or 11
                    local c = UNIT_DB_MAP[selectedUnit]().castSpellTargetColor
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        UNIT_DB_MAP[key]().castSpellTargetSize = v
                        if c then UNIT_DB_MAP[key]().castSpellTargetColor = { r=c.r, g=c.g, b=c.b } end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().castSpellTargetSize or 11
                    local c = UNIT_DB_MAP[selectedUnit]().castSpellTargetColor
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().castSpellTargetSize or 11) ~= v then return false end
                        local kc = UNIT_DB_MAP[key]().castSpellTargetColor
                        if c and kc then
                            if kc.r ~= c.r or kc.g ~= c.g or kc.b ~= c.b then return false end
                        elseif c ~= kc then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().castSpellTargetSize or 11
                        local c = UNIT_DB_MAP[selectedUnit]().castSpellTargetColor
                        for _, key in ipairs(checkedKeys) do
                            UNIT_DB_MAP[key]().castSpellTargetSize = v
                            if c then UNIT_DB_MAP[key]().castSpellTargetColor = { r=c.r, g=c.g, b=c.b } end
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        end   -- close Cast Bar hidden-while-disabled gate

        _, h = W:Spacer(parent, y, 20); y = y - h

        -------------------------------------------------------------------
        --  TEXT BAR
        -------------------------------------------------------------------
        local sharedBtbHeader
        sharedBtbHeader, h = W:SectionHeader(parent, "TEXT BAR", y); y = y - h

        -- Row 1: Enable Text Bar + Position
        local _sharedBtbWidthRgn
        local sharedBtbToggleRow
        sharedBtbToggleRow, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Text Bar",
              getValue=function() return SVal("bottomTextBar", false) end,
              -- DependentSetValue: Rows 2-4 below are hidden while the Text
              -- Bar is off; the flip forces the full rebuild.
              setValue=EllesmereUI.DependentSetValue(
                  function() return SVal("bottomTextBar", false) end,
                  function(v) SSet("bottomTextBar", v); UpdatePreview(); EllesmereUI:RefreshPage() end) },
            { type="dropdown", text="Position", values=btbPositionValues, order=btbPositionOrder,
              disabled=function() return not SVal("bottomTextBar", false) end,
              disabledTooltip="Text Bar",
              getValue=function() return SVal("btbPosition", "bottom") end,
              setValue=function(v)
                  SSet("btbPosition", v); UpdatePreview()
                  if _sharedBtbWidthRgn then
                      local isDet = (v == "detached_top" or v == "detached_bottom")
                      if _sharedBtbWidthRgn._control and _sharedBtbWidthRgn._control.SetEnabled then
                          _sharedBtbWidthRgn._control:SetEnabled(isDet)
                      end
                  end
              end });  y = y - h
        -- Sync icon: Enable Text Bar
        do
            local rgn = sharedBtbToggleRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Enable Text Bar to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().bottomTextBar or false
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then UNIT_DB_MAP[key]().bottomTextBar = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().bottomTextBar or false
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().bottomTextBar or false) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().bottomTextBar or false
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().bottomTextBar = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        -- Sync icon: Text Bar Position (right region)
        do
            local rgn = sharedBtbToggleRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Text Bar Position to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().btbPosition or "bottom"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then UNIT_DB_MAP[key]().btbPosition = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().btbPosition or "bottom"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().btbPosition or "bottom") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().btbPosition or "bottom"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().btbPosition = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        -- Inline color swatch for BTB background on Enable Text Bar
        do
            local btbRgn = sharedBtbToggleRow._leftRegion
            local sw = EllesmereUI.BuildColorSwatch(btbRgn, btbRgn:GetFrameLevel() + 5,
                function()
                    local c = SGet("btbBgColor")
                    c = c or { r=0.2, g=0.2, b=0.2 }
                    local a = SGet("btbBgOpacity")
                    return c.r, c.g, c.b, a or 1.0
                end,
                function(r, g, b, a)
                    UNIT_DB_MAP[selectedUnit]().btbBgColor = { r=r, g=g, b=b }
                    UNIT_DB_MAP[selectedUnit]().btbBgOpacity = a
                    ReloadAndUpdate(); UpdatePreview()
                end, true, 20)
            sw:SetPoint("RIGHT", btbRgn._lastInline or btbRgn._control, "LEFT", -12, 0)
            btbRgn._lastInline = sw
            -- Disabled state for swatch when text bar is off
            local function UpdateBtbSwatchState()
                local btbOn = SVal("bottomTextBar", false)
                if not btbOn then
                    sw:SetAlpha(0.15); sw:Disable()
                    sw._disabledTooltip = "Text Bar"
                else
                    sw:SetAlpha(1); sw:Enable()
                    sw._disabledTooltip = nil
                end
            end
            UpdateBtbSwatchState()
            RegisterWidgetRefresh(UpdateBtbSwatchState)
            sw:HookScript("OnEnter", function(self)
                if self._disabledTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip(self._disabledTooltip))
                end
            end)
            sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        end
        -- Cog on Position for X/Y offsets
        do
            local posRgn = sharedBtbToggleRow._rightRegion
            local _, btbPosCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Detached Position Offsets",
                rows = {
                    { type="slider", label="X Offset", min=-200, max=200, step=1,
                      get=function() return SVal("btbX", 0) end,
                      set=function(v) SSet("btbX", v); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-200, max=200, step=1,
                      get=function() return SVal("btbY", 0) end,
                      set=function(v) SSet("btbY", v); UpdatePreview() end },
                },
            })
            local btbPosCogShow = btbPosCogShowRaw
            local cogBtn = MakeCogBtn(posRgn, btbPosCogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local function _btbPosCogUpdate()
                local btbOff = not SVal("bottomTextBar", false)
                local pos = SVal("btbPosition", "bottom")
                local isDet = (pos == "detached_top" or pos == "detached_bottom")
                if btbOff then
                    cogBtn:SetAlpha(0.15); cogBtn:SetEnabled(false)
                elseif isDet then
                    cogBtn:SetAlpha(0.4); cogBtn:SetEnabled(true)
                else
                    cogBtn:SetAlpha(0.15); cogBtn:SetEnabled(false)
                end
            end
            cogBtn:SetScript("OnEnter", function(self)
                local btbOff = not SVal("bottomTextBar", false)
                if btbOff then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Text Bar"))
                else
                    local pos = SVal("btbPosition", "bottom")
                    if pos == "detached_top" or pos == "detached_bottom" then self:SetAlpha(0.7)
                    else EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a detached position to be active.")) end
                end
            end)
            cogBtn:SetScript("OnLeave", function(self) _btbPosCogUpdate(); EllesmereUI.HideWidgetTooltip() end)
            cogBtn:SetScript("OnClick", function(self) btbPosCogShow(self) end)
            _btbPosCogUpdate()
            RegisterWidgetRefresh(_btbPosCogUpdate)
        end

        -- Rows 2-4 are HIDDEN entirely while Enable Text Bar is off (the
        -- toggle's DependentSetValue forces the rebuild on flips). Row locals
        -- referenced by the element-nav map are hoisted above the gate so the
        -- map never reads nil globals.
        local sharedBtbTextRow, sharedBtbCenterRow
        if SVal("bottomTextBar", false) then
        -- Row 2: Height + Width
        local sharedBtbHeightRow
        sharedBtbHeightRow, h = W:DualRow(parent, y,
            { type="slider", text="Height", min=0, max=40, step=1,
              disabled=function() return not SVal("bottomTextBar", false) end,
              disabledTooltip="Text Bar",
              getValue=function() return SVal("bottomTextBarHeight", 16) end,
              setValue=function(v) SSet("bottomTextBarHeight", v); UpdatePreview() end },
            { type="slider", text="Width", min=0, max=400, step=1,
              disabled=function()
                  if not SVal("bottomTextBar", false) then return true end
                  local pos = SVal("btbPosition", "bottom")
                  return pos ~= "detached_top" and pos ~= "detached_bottom"
              end,
              disabledTooltip=function()
                  if not SVal("bottomTextBar", false) then return "Text Bar" end
                  return "This option requires the position setting to be detached"
              end,
              getValue=function() return SVal("btbWidth", 0) end,
              setValue=function(v) SSet("btbWidth", v); UpdatePreview() end });  y = y - h
        _sharedBtbWidthRgn = sharedBtbHeightRow._rightRegion
        do
            local pos = SVal("btbPosition", "bottom")
            local isDet = (pos == "detached_top" or pos == "detached_bottom")
            if _sharedBtbWidthRgn._control and _sharedBtbWidthRgn._control.SetEnabled then
                _sharedBtbWidthRgn._control:SetEnabled(isDet)
            end
        end
        -- Sync icons: BTB Height (left) and BTB Width (right)
        do
            local rgn = sharedBtbHeightRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Text Bar Height to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().bottomTextBarHeight or 16
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().bottomTextBarHeight = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().bottomTextBarHeight or 16
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().bottomTextBarHeight or 16) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().bottomTextBarHeight or 16
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().bottomTextBarHeight = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = sharedBtbHeightRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Text Bar Width to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().btbWidth or 0
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().btbWidth = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().btbWidth or 0
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().btbWidth or 0) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().btbWidth or 0
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().btbWidth = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 3: Left Text + Right Text
        sharedBtbTextRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Left Text", values=btbTextValues, order=btbTextOrder,
              disabled=function() return not SVal("bottomTextBar", false) end,
              disabledTooltip="Text Bar",
              getValue=function() return SVal("btbLeftContent", "none") end,
              setValue=function(v)
                  SSet("btbLeftContent", v)
                  if v ~= "none" then
                      if SGet("btbRightContent") == v then SSet("btbRightContent", "none") end
                      if SGet("btbCenterContent") == v then SSet("btbCenterContent", "none") end
                  end
                  ReloadAndUpdate(); UpdatePreview()
              end },
            { type="dropdown", text="Right Text", values=btbTextValues, order=btbTextOrder,
              disabled=function() return not SVal("bottomTextBar", false) end,
              disabledTooltip="Text Bar",
              getValue=function() return SVal("btbRightContent", "none") end,
              setValue=function(v)
                  SSet("btbRightContent", v)
                  if v ~= "none" then
                      if SGet("btbLeftContent") == v then SSet("btbLeftContent", "none") end
                      if SGet("btbCenterContent") == v then SSet("btbCenterContent", "none") end
                  end
                  ReloadAndUpdate(); UpdatePreview()
              end });  y = y - h
        -- Inline color swatches on BTB Left Text: Custom + Class (CDM Border Size
        -- pattern). Power Color stays in the cog; the three modes are mutually exclusive.
        do
            local btbLRgn = sharedBtbTextRow._leftRegion
            local function blOff() return SVal("btbLeftContent", "none") == "none" or not SVal("bottomTextBar", false) end
            local blClassSwatch, blUpdateClassSwatch = EllesmereUI.BuildColorSwatch(
                btbLRgn, btbLRgn:GetFrameLevel() + 5,
                function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            PP.Point(blClassSwatch, "RIGHT", btbLRgn._lastInline or btbLRgn._control, "LEFT", -8, 0)
            blClassSwatch:SetScript("OnClick", function()
                if blOff() then return end
                SSet("btbLeftClassColor", true); SSet("btbLeftPowerColor", false)
                UpdatePreview(); EllesmereUI:RefreshPage()
            end)
            blClassSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(blClassSwatch, "Class Colored") end)
            blClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local blSwGet = function()
                return SVal("btbLeftColorR", 1), SVal("btbLeftColorG", 1), SVal("btbLeftColorB", 1)
            end
            local blSwSet = function(r, g, b)
                SSet("btbLeftColorR", r); SSet("btbLeftColorG", g); SSet("btbLeftColorB", b)
                UpdatePreview()
            end
            local blSwatch, blUpdateSwatch = EllesmereUI.BuildColorSwatch(btbLRgn, btbLRgn:GetFrameLevel() + 5, blSwGet, blSwSet, nil, 20)
            PP.Point(blSwatch, "RIGHT", blClassSwatch, "LEFT", -8, 0)
            btbLRgn._lastInline = blSwatch
            local blOrigClick = blSwatch:GetScript("OnClick")
            blSwatch:SetScript("OnClick", function(self, ...)
                if blOff() then return end
                if SVal("btbLeftClassColor", false) or SVal("btbLeftPowerColor", false) then
                    SSet("btbLeftClassColor", false); SSet("btbLeftPowerColor", false)
                    UpdatePreview(); EllesmereUI:RefreshPage(); return
                end
                if blOrigClick then blOrigClick(self, ...) end
            end)
            blSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(blSwatch, "Custom Colored") end)
            blSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            -- Power Color swatch: shows the player's current power color; click to
            -- select power-colored mode. Same per-unit power resolution as the power
            -- bar text (white fallback when the power token can't resolve).
            local blPowerSwatch, blUpdatePowerSwatch = EllesmereUI.BuildColorSwatch(
                btbLRgn, btbLRgn:GetFrameLevel() + 5,
                function()
                    local _, pToken = UnitPowerType("player")
                    local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                    if info then return info.r, info.g, info.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            PP.Point(blPowerSwatch, "RIGHT", blSwatch, "LEFT", -8, 0)
            btbLRgn._lastInline = blPowerSwatch
            blPowerSwatch:SetScript("OnClick", function()
                if blOff() then return end
                SSet("btbLeftPowerColor", true); SSet("btbLeftClassColor", false)
                UpdatePreview(); EllesmereUI:RefreshPage()
            end)
            blPowerSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(blPowerSwatch, "Power Colored") end)
            blPowerSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateBlSwatches()
                local off = blOff()
                local isClass = SVal("btbLeftClassColor", false)
                local isPower = SVal("btbLeftPowerColor", false)
                blSwatch:SetAlpha((isClass or isPower or off) and 0.3 or 1)
                blClassSwatch:SetAlpha((isClass and not off) and 1 or 0.3)
                blPowerSwatch:SetAlpha((isPower and not off) and 1 or 0.3)
            end
            RegisterWidgetRefresh(function() blUpdateSwatch(); blUpdateClassSwatch(); blUpdatePowerSwatch(); UpdateBlSwatches() end)
            UpdateBlSwatches()
        end
        -- Cogwheel on BTB Left Text
        do
            local btbLRgn = sharedBtbTextRow._leftRegion
            local _, btbLeftCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "BTB Left Text Settings",
                rows = {
                    { type="slider", label="Size", min=8, max=100, step=1,
                      get=function() return SVal("btbLeftSize", 11) end,
                      set=function(v) SSet("btbLeftSize", v); UpdatePreview() end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return SVal("btbLeftX", 0) end,
                      set=function(v) SSet("btbLeftX", v); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-30, max=30, step=1,
                      get=function() return SVal("btbLeftY", 0) end,
                      set=function(v) SSet("btbLeftY", v); UpdatePreview() end },
                    { type="slider", label="Name Length", min=0, max=30, step=1,
                      get=function() return SVal("btbLeftShortNameLength", 0) end,
                      set=function(v) SSet("btbLeftShortNameLength", v); UpdatePreview() end,
                      disabled=function() local c=SVal("btbLeftContent","none") return c ~= "name" and c ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name or Name > Target is selected." },
                    { type="toggle", label="Show Ellipsis",
                      get=function() return SVal("btbLeftShortNameEllipsis", true) ~= false end,
                      set=function(v) SSet("btbLeftShortNameEllipsis", v); UpdatePreview() end,
                      disabled=function() local c=SVal("btbLeftContent","none") return c ~= "name" and c ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name or Name > Target is selected." },
                    { type="multiswatch", label="Indicator Color",
                      disabled=function() return SVal("btbLeftContent","none") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected.",
                      swatches = {
                        { tooltip = "Custom Colored", hasAlpha = false,
                          getValue = function() local c = SVal("btbLeftTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                          setValue = function(r, g, b) SSet("btbLeftTargetSepColor", { r=r, g=g, b=b }); UpdatePreview() end,
                          onClick = function(self)
                              if SVal("btbLeftTargetSepClassColor", false) then
                                  SSet("btbLeftTargetSepClassColor", false); UpdatePreview()
                                  return
                              end
                              if self._eabOrigClick then self._eabOrigClick(self) end
                          end,
                          refreshAlpha = function() return SVal("btbLeftTargetSepClassColor", false) and 0.3 or 1 end },
                        { tooltip = "Class Colored", hasAlpha = false,
                          getValue = function()
                              local _, ct = UnitClass("player")
                              local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                              if cc then return cc.r, cc.g, cc.b end
                              return 1, 1, 1
                          end,
                          setValue = function() end,
                          onClick = function() SSet("btbLeftTargetSepClassColor", true); UpdatePreview() end,
                          refreshAlpha = function() return SVal("btbLeftTargetSepClassColor", false) and 1 or 0.3 end },
                      } },
                    { type="input", label="Separator", inputWidth=60,
                      get=function() return SVal("btbLeftTargetSep", ">") end,
                      set=function(v)
                          v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                          if v == "" then v = ">" end
                          SSet("btbLeftTargetSep", v); UpdatePreview()
                      end,
                      disabled=function() return SVal("btbLeftContent","none") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected." },
                                    },
            })
            local btbLeftCogShow = btbLeftCogShowRaw
            local btbLCogBtn = MakeCogBtn(btbLRgn, btbLeftCogShow)
            local function UpdateBtbLCogState()
                local btbOff = not SVal("bottomTextBar", false)
                local isNone = SVal("btbLeftContent", "none") == "none"
                btbLCogBtn:SetAlpha((btbOff or isNone) and 0.15 or 0.4)
                btbLCogBtn:SetEnabled(not btbOff and not isNone)
            end
            btbLCogBtn:SetScript("OnEnter", function(self)
                local btbOff = not SVal("bottomTextBar", false)
                local isNone = SVal("btbLeftContent", "none") == "none"
                if btbOff then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Text Bar"))
                elseif isNone then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a text selection other than none."))
                else self:SetAlpha(0.7) end
            end)
            btbLCogBtn:SetScript("OnLeave", function(self) UpdateBtbLCogState(); EllesmereUI.HideWidgetTooltip() end)
            btbLCogBtn:SetScript("OnClick", function(self) btbLeftCogShow(self) end)
            UpdateBtbLCogState()
            RegisterWidgetRefresh(UpdateBtbLCogState)
        end
        -- Inline color swatches on BTB Right Text: Custom + Class (Power Color stays in
        -- the cog; the three modes are mutually exclusive).
        do
            local btbRRgn = sharedBtbTextRow._rightRegion
            local function brOff() return SVal("btbRightContent", "none") == "none" or not SVal("bottomTextBar", false) end
            local brClassSwatch, brUpdateClassSwatch = EllesmereUI.BuildColorSwatch(
                btbRRgn, btbRRgn:GetFrameLevel() + 5,
                function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            PP.Point(brClassSwatch, "RIGHT", btbRRgn._lastInline or btbRRgn._control, "LEFT", -8, 0)
            brClassSwatch:SetScript("OnClick", function()
                if brOff() then return end
                SSet("btbRightClassColor", true); SSet("btbRightPowerColor", false)
                UpdatePreview(); EllesmereUI:RefreshPage()
            end)
            brClassSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(brClassSwatch, "Class Colored") end)
            brClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local brSwGet = function()
                return SVal("btbRightColorR", 1), SVal("btbRightColorG", 1), SVal("btbRightColorB", 1)
            end
            local brSwSet = function(r, g, b)
                SSet("btbRightColorR", r); SSet("btbRightColorG", g); SSet("btbRightColorB", b)
                UpdatePreview()
            end
            local brSwatch, brUpdateSwatch = EllesmereUI.BuildColorSwatch(btbRRgn, btbRRgn:GetFrameLevel() + 5, brSwGet, brSwSet, nil, 20)
            PP.Point(brSwatch, "RIGHT", brClassSwatch, "LEFT", -8, 0)
            btbRRgn._lastInline = brSwatch
            local brOrigClick = brSwatch:GetScript("OnClick")
            brSwatch:SetScript("OnClick", function(self, ...)
                if brOff() then return end
                if SVal("btbRightClassColor", false) or SVal("btbRightPowerColor", false) then
                    SSet("btbRightClassColor", false); SSet("btbRightPowerColor", false)
                    UpdatePreview(); EllesmereUI:RefreshPage(); return
                end
                if brOrigClick then brOrigClick(self, ...) end
            end)
            brSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(brSwatch, "Custom Colored") end)
            brSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            -- Power Color swatch: shows the player's current power color; click to
            -- select power-colored mode. Same per-unit power resolution as the power
            -- bar text (white fallback when the power token can't resolve).
            local brPowerSwatch, brUpdatePowerSwatch = EllesmereUI.BuildColorSwatch(
                btbRRgn, btbRRgn:GetFrameLevel() + 5,
                function()
                    local _, pToken = UnitPowerType("player")
                    local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                    if info then return info.r, info.g, info.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            PP.Point(brPowerSwatch, "RIGHT", brSwatch, "LEFT", -8, 0)
            btbRRgn._lastInline = brPowerSwatch
            brPowerSwatch:SetScript("OnClick", function()
                if brOff() then return end
                SSet("btbRightPowerColor", true); SSet("btbRightClassColor", false)
                UpdatePreview(); EllesmereUI:RefreshPage()
            end)
            brPowerSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(brPowerSwatch, "Power Colored") end)
            brPowerSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateBrSwatches()
                local off = brOff()
                local isClass = SVal("btbRightClassColor", false)
                local isPower = SVal("btbRightPowerColor", false)
                brSwatch:SetAlpha((isClass or isPower or off) and 0.3 or 1)
                brClassSwatch:SetAlpha((isClass and not off) and 1 or 0.3)
                brPowerSwatch:SetAlpha((isPower and not off) and 1 or 0.3)
            end
            RegisterWidgetRefresh(function() brUpdateSwatch(); brUpdateClassSwatch(); brUpdatePowerSwatch(); UpdateBrSwatches() end)
            UpdateBrSwatches()
        end
        -- Cogwheel on BTB Right Text
        do
            local btbRRgn = sharedBtbTextRow._rightRegion
            local _, btbRightCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "BTB Right Text Settings",
                rows = {
                    { type="slider", label="Size", min=8, max=100, step=1,
                      get=function() return SVal("btbRightSize", 11) end,
                      set=function(v) SSet("btbRightSize", v); UpdatePreview() end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return SVal("btbRightX", 0) end,
                      set=function(v) SSet("btbRightX", v); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-30, max=30, step=1,
                      get=function() return SVal("btbRightY", 0) end,
                      set=function(v) SSet("btbRightY", v); UpdatePreview() end },
                    { type="slider", label="Name Length", min=0, max=30, step=1,
                      get=function() return SVal("btbRightShortNameLength", 0) end,
                      set=function(v) SSet("btbRightShortNameLength", v); UpdatePreview() end,
                      disabled=function() local c=SVal("btbRightContent","none") return c ~= "name" and c ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name or Name > Target is selected." },
                    { type="toggle", label="Show Ellipsis",
                      get=function() return SVal("btbRightShortNameEllipsis", true) ~= false end,
                      set=function(v) SSet("btbRightShortNameEllipsis", v); UpdatePreview() end,
                      disabled=function() local c=SVal("btbRightContent","none") return c ~= "name" and c ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name or Name > Target is selected." },
                    { type="multiswatch", label="Indicator Color",
                      disabled=function() return SVal("btbRightContent","none") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected.",
                      swatches = {
                        { tooltip = "Custom Colored", hasAlpha = false,
                          getValue = function() local c = SVal("btbRightTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                          setValue = function(r, g, b) SSet("btbRightTargetSepColor", { r=r, g=g, b=b }); UpdatePreview() end,
                          onClick = function(self)
                              if SVal("btbRightTargetSepClassColor", false) then
                                  SSet("btbRightTargetSepClassColor", false); UpdatePreview()
                                  return
                              end
                              if self._eabOrigClick then self._eabOrigClick(self) end
                          end,
                          refreshAlpha = function() return SVal("btbRightTargetSepClassColor", false) and 0.3 or 1 end },
                        { tooltip = "Class Colored", hasAlpha = false,
                          getValue = function()
                              local _, ct = UnitClass("player")
                              local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                              if cc then return cc.r, cc.g, cc.b end
                              return 1, 1, 1
                          end,
                          setValue = function() end,
                          onClick = function() SSet("btbRightTargetSepClassColor", true); UpdatePreview() end,
                          refreshAlpha = function() return SVal("btbRightTargetSepClassColor", false) and 1 or 0.3 end },
                      } },
                    { type="input", label="Separator", inputWidth=60,
                      get=function() return SVal("btbRightTargetSep", ">") end,
                      set=function(v)
                          v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                          if v == "" then v = ">" end
                          SSet("btbRightTargetSep", v); UpdatePreview()
                      end,
                      disabled=function() return SVal("btbRightContent","none") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected." },
                                    },
            })
            local btbRightCogShow = btbRightCogShowRaw
            local btbRCogBtn = MakeCogBtn(btbRRgn, btbRightCogShow)
            local function UpdateBtbRCogState()
                local btbOff = not SVal("bottomTextBar", false)
                local isNone = SVal("btbRightContent", "none") == "none"
                btbRCogBtn:SetAlpha((btbOff or isNone) and 0.15 or 0.4)
                btbRCogBtn:SetEnabled(not btbOff and not isNone)
            end
            btbRCogBtn:SetScript("OnEnter", function(self)
                local btbOff = not SVal("bottomTextBar", false)
                local isNone = SVal("btbRightContent", "none") == "none"
                if btbOff then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Text Bar"))
                elseif isNone then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a text selection other than none."))
                else self:SetAlpha(0.7) end
            end)
            btbRCogBtn:SetScript("OnLeave", function(self) UpdateBtbRCogState(); EllesmereUI.HideWidgetTooltip() end)
            btbRCogBtn:SetScript("OnClick", function(self) btbRightCogShow(self) end)
            UpdateBtbRCogState()
            RegisterWidgetRefresh(UpdateBtbRCogState)
        end
        -- Sync icons: BTB Left Text (left) and BTB Right Text (right)
        do
            local rgn = sharedBtbTextRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Text Bar Left Text to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().btbLeftContent or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().btbLeftContent = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().btbLeftContent or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().btbLeftContent or "none") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().btbLeftContent or "none"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().btbLeftContent = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = sharedBtbTextRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Text Bar Right Text to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().btbRightContent or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().btbRightContent = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().btbRightContent or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().btbRightContent or "none") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().btbRightContent or "none"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().btbRightContent = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 4: Center Text + Class Icon
        sharedBtbCenterRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Center Text", values=btbTextValues, order=btbTextOrder,
              disabled=function() return not SVal("bottomTextBar", false) end,
              disabledTooltip="Text Bar",
              getValue=function() return SVal("btbCenterContent", "none") end,
              setValue=function(v)
                  SSet("btbCenterContent", v)
                  if v ~= "none" then
                      SSet("btbLeftContent", "none")
                      SSet("btbRightContent", "none")
                  end
                  ReloadAndUpdate(); UpdatePreview()
              end },
            { type="dropdown", text="Class Icon", values=classIconValues, order=classIconOrder,
              disabled=function() return not SVal("bottomTextBar", false) end,
              disabledTooltip="Text Bar",
              getValue=function() return SVal("btbClassIcon", "none") end,
              setValue=function(v) SSet("btbClassIcon", v); UpdatePreview() end });  y = y - h
        -- Inline color swatches on BTB Center Text: Custom + Class (Power Color stays in
        -- the cog; the three modes are mutually exclusive).
        do
            local btbCRgn = sharedBtbCenterRow._leftRegion
            local function bcOff() return SVal("btbCenterContent", "none") == "none" or not SVal("bottomTextBar", false) end
            local bcClassSwatch, bcUpdateClassSwatch = EllesmereUI.BuildColorSwatch(
                btbCRgn, btbCRgn:GetFrameLevel() + 5,
                function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            PP.Point(bcClassSwatch, "RIGHT", btbCRgn._lastInline or btbCRgn._control, "LEFT", -8, 0)
            bcClassSwatch:SetScript("OnClick", function()
                if bcOff() then return end
                SSet("btbCenterClassColor", true); SSet("btbCenterPowerColor", false)
                UpdatePreview(); EllesmereUI:RefreshPage()
            end)
            bcClassSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bcClassSwatch, "Class Colored") end)
            bcClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local bcSwGet = function()
                return SVal("btbCenterColorR", 1), SVal("btbCenterColorG", 1), SVal("btbCenterColorB", 1)
            end
            local bcSwSet = function(r, g, b)
                SSet("btbCenterColorR", r); SSet("btbCenterColorG", g); SSet("btbCenterColorB", b)
                UpdatePreview()
            end
            local bcSwatch, bcUpdateSwatch = EllesmereUI.BuildColorSwatch(btbCRgn, btbCRgn:GetFrameLevel() + 5, bcSwGet, bcSwSet, nil, 20)
            PP.Point(bcSwatch, "RIGHT", bcClassSwatch, "LEFT", -8, 0)
            btbCRgn._lastInline = bcSwatch
            local bcOrigClick = bcSwatch:GetScript("OnClick")
            bcSwatch:SetScript("OnClick", function(self, ...)
                if bcOff() then return end
                if SVal("btbCenterClassColor", false) or SVal("btbCenterPowerColor", false) then
                    SSet("btbCenterClassColor", false); SSet("btbCenterPowerColor", false)
                    UpdatePreview(); EllesmereUI:RefreshPage(); return
                end
                if bcOrigClick then bcOrigClick(self, ...) end
            end)
            bcSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bcSwatch, "Custom Colored") end)
            bcSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            -- Power Color swatch: shows the player's current power color; click to
            -- select power-colored mode. Same per-unit power resolution as the power
            -- bar text (white fallback when the power token can't resolve).
            local bcPowerSwatch, bcUpdatePowerSwatch = EllesmereUI.BuildColorSwatch(
                btbCRgn, btbCRgn:GetFrameLevel() + 5,
                function()
                    local _, pToken = UnitPowerType("player")
                    local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                    if info then return info.r, info.g, info.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            PP.Point(bcPowerSwatch, "RIGHT", bcSwatch, "LEFT", -8, 0)
            btbCRgn._lastInline = bcPowerSwatch
            bcPowerSwatch:SetScript("OnClick", function()
                if bcOff() then return end
                SSet("btbCenterPowerColor", true); SSet("btbCenterClassColor", false)
                UpdatePreview(); EllesmereUI:RefreshPage()
            end)
            bcPowerSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bcPowerSwatch, "Power Colored") end)
            bcPowerSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateBcSwatches()
                local off = bcOff()
                local isClass = SVal("btbCenterClassColor", false)
                local isPower = SVal("btbCenterPowerColor", false)
                bcSwatch:SetAlpha((isClass or isPower or off) and 0.3 or 1)
                bcClassSwatch:SetAlpha((isClass and not off) and 1 or 0.3)
                bcPowerSwatch:SetAlpha((isPower and not off) and 1 or 0.3)
            end
            RegisterWidgetRefresh(function() bcUpdateSwatch(); bcUpdateClassSwatch(); bcUpdatePowerSwatch(); UpdateBcSwatches() end)
            UpdateBcSwatches()
        end
        -- Cogwheel on BTB Center Text
        do
            local btbCRgn = sharedBtbCenterRow._leftRegion
            local _, btbCenterCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "BTB Center Text Settings",
                rows = {
                    { type="slider", label="Size", min=8, max=100, step=1,
                      get=function() return SVal("btbCenterSize", 11) end,
                      set=function(v) SSet("btbCenterSize", v); UpdatePreview() end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return SVal("btbCenterX", 0) end,
                      set=function(v) SSet("btbCenterX", v); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-30, max=30, step=1,
                      get=function() return SVal("btbCenterY", 0) end,
                      set=function(v) SSet("btbCenterY", v); UpdatePreview() end },
                    { type="slider", label="Name Length", min=0, max=30, step=1,
                      get=function() return SVal("btbCenterShortNameLength", 0) end,
                      set=function(v) SSet("btbCenterShortNameLength", v); UpdatePreview() end,
                      disabled=function() local c=SVal("btbCenterContent","none") return c ~= "name" and c ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name or Name > Target is selected." },
                    { type="toggle", label="Show Ellipsis",
                      get=function() return SVal("btbCenterShortNameEllipsis", true) ~= false end,
                      set=function(v) SSet("btbCenterShortNameEllipsis", v); UpdatePreview() end,
                      disabled=function() local c=SVal("btbCenterContent","none") return c ~= "name" and c ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name or Name > Target is selected." },
                    { type="multiswatch", label="Indicator Color",
                      disabled=function() return SVal("btbCenterContent","none") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected.",
                      swatches = {
                        { tooltip = "Custom Colored", hasAlpha = false,
                          getValue = function() local c = SVal("btbCenterTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                          setValue = function(r, g, b) SSet("btbCenterTargetSepColor", { r=r, g=g, b=b }); UpdatePreview() end,
                          onClick = function(self)
                              if SVal("btbCenterTargetSepClassColor", false) then
                                  SSet("btbCenterTargetSepClassColor", false); UpdatePreview()
                                  return
                              end
                              if self._eabOrigClick then self._eabOrigClick(self) end
                          end,
                          refreshAlpha = function() return SVal("btbCenterTargetSepClassColor", false) and 0.3 or 1 end },
                        { tooltip = "Class Colored", hasAlpha = false,
                          getValue = function()
                              local _, ct = UnitClass("player")
                              local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                              if cc then return cc.r, cc.g, cc.b end
                              return 1, 1, 1
                          end,
                          setValue = function() end,
                          onClick = function() SSet("btbCenterTargetSepClassColor", true); UpdatePreview() end,
                          refreshAlpha = function() return SVal("btbCenterTargetSepClassColor", false) and 1 or 0.3 end },
                      } },
                    { type="input", label="Separator", inputWidth=60,
                      get=function() return SVal("btbCenterTargetSep", ">") end,
                      set=function(v)
                          v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                          if v == "" then v = ">" end
                          SSet("btbCenterTargetSep", v); UpdatePreview()
                      end,
                      disabled=function() return SVal("btbCenterContent","none") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected." },
                                    },
            })
            local btbCenterCogShow = btbCenterCogShowRaw
            local btbCCogBtn = MakeCogBtn(btbCRgn, btbCenterCogShow)
            local function UpdateBtbCCogState()
                local btbOff = not SVal("bottomTextBar", false)
                local isNone = SVal("btbCenterContent", "none") == "none"
                btbCCogBtn:SetAlpha((btbOff or isNone) and 0.15 or 0.4)
                btbCCogBtn:SetEnabled(not btbOff and not isNone)
            end
            btbCCogBtn:SetScript("OnEnter", function(self)
                local btbOff = not SVal("bottomTextBar", false)
                local isNone = SVal("btbCenterContent", "none") == "none"
                if btbOff then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Text Bar"))
                elseif isNone then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a text selection other than none."))
                else self:SetAlpha(0.7) end
            end)
            btbCCogBtn:SetScript("OnLeave", function(self) UpdateBtbCCogState(); EllesmereUI.HideWidgetTooltip() end)
            btbCCogBtn:SetScript("OnClick", function(self) btbCenterCogShow(self) end)
            UpdateBtbCCogState()
            RegisterWidgetRefresh(UpdateBtbCCogState)
        end
        -- Cogwheel on Class Icon for size/location/x/y
        do
            local ciRgn = sharedBtbCenterRow._rightRegion
            local _, ciCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Class Icon Settings",
                rows = {
                    { type="slider", label="Size", min=8, max=60, step=1,
                      get=function() return SVal("btbClassIconSize", 14) end,
                      set=function(v) SSet("btbClassIconSize", v); UpdatePreview() end },
                    { type="dropdown", label="Location", values=classIconLocValues, order=classIconLocOrder,
                      get=function() return SVal("btbClassIconLocation", "left") end,
                      set=function(v) SSet("btbClassIconLocation", v); UpdatePreview() end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return SVal("btbClassIconX", 0) end,
                      set=function(v) SSet("btbClassIconX", v); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() return SVal("btbClassIconY", 0) end,
                      set=function(v) SSet("btbClassIconY", v); UpdatePreview() end },
                },
            })
            local ciCogShow = ciCogShowRaw
            local ciCogBtn = MakeCogBtn(ciRgn, ciCogShow)
            local function UpdateCiCogState()
                local btbOff = not SVal("bottomTextBar", false)
                local isNone = SVal("btbClassIcon", "none") == "none"
                ciCogBtn:SetAlpha((btbOff or isNone) and 0.15 or 0.4)
                ciCogBtn:SetEnabled(not btbOff and not isNone)
            end
            ciCogBtn:SetScript("OnEnter", function(self)
                local btbOff = not SVal("bottomTextBar", false)
                local isNone = SVal("btbClassIcon", "none") == "none"
                if btbOff then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Text Bar"))
                elseif isNone then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a Class Icon other than None."))
                else self:SetAlpha(0.7) end
            end)
            ciCogBtn:SetScript("OnLeave", function(self) UpdateCiCogState(); EllesmereUI.HideWidgetTooltip() end)
            ciCogBtn:SetScript("OnClick", function(self) ciCogShow(self) end)
            UpdateCiCogState()
            RegisterWidgetRefresh(UpdateCiCogState)
        end
        -- Sync icons: BTB Center Text (left) and Class Icon (right)
        do
            local rgn = sharedBtbCenterRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Text Bar Center Text to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().btbCenterContent or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().btbCenterContent = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().btbCenterContent or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().btbCenterContent or "none") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().btbCenterContent or "none"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().btbCenterContent = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = sharedBtbCenterRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Text Bar Class Icon to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().btbClassIcon or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().btbClassIcon = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().btbClassIcon or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().btbClassIcon or "none") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().btbClassIcon or "none"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().btbClassIcon = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        end   -- close Text Bar hidden-while-disabled gate

        -- CLASS RESOURCE section: only shown in multi-edit or when player is selected
        local _showClassRes = selectedUnit == "player"
        if _showClassRes then
        _, h = W:Spacer(parent, y, 20); y = y - h

        -------------------------------------------------------------------
        --  CLASS RESOURCE
        -------------------------------------------------------------------
        local sharedClassResHeader
        sharedClassResHeader, h = W:SectionHeader(parent, "CLASS RESOURCE", y); y = y - h

        -- Row 1: Enable Class Resource + Class Colors (with inline swatch)
        local sharedClassResRow
        sharedClassResRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Enable Class Resource", values=classPowerStyleValues, order=classPowerStyleOrder,
              getValue=function() return SValSupported("classPowerStyle", "none") end,
              -- DependentSetValue: Rows 2-3 below are hidden while the style
              -- is None; only the None <-> enabled flip forces the rebuild
              -- (style-to-style changes keep the cheap refresh path).
              setValue=EllesmereUI.DependentSetValue(
                  function() return SValSupported("classPowerStyle", "none") ~= "none" end,
                  function(v)
                      SSetSupported("classPowerStyle", v)
                      SSetSupported("showClassPowerBar", v ~= "none")
                      if ns.frames and ns.frames._toggleClassPower then
                          ns.frames._toggleClassPower(v)
                      end
                      UpdatePreview()
                      C_Timer.After(0, function() local rl = EllesmereUI._widgetRefreshList; if rl then for i = 1, #rl do rl[i]() end end end)
                  end) },
            { type="multiSwatch", text="Fill Color",
              disabled=function() return SValSupported("classPowerStyle", "none") ~= "modern" end,
              disabledTooltip="Class Resource must be set to Modern", rawTooltip=true,
              swatches = {
                { tooltip = "Custom Colored",
                  hasAlpha = false,
                  getValue = function()
                      local c = SGetSupported("classPowerCustomColor")
                      c = c or { r = 1, g = 0.82, b = 0 }
                      return c.r, c.g, c.b, 1
                  end,
                  setValue = function(r, g, b)
                      UNIT_DB_MAP[selectedUnit]().classPowerCustomColor = { r=r, g=g, b=b }
                      if ns.frames and ns.frames._toggleClassPower then
                          ns.frames._toggleClassPower()
                      end
                      ReloadAndUpdate(); UpdatePreview()
                  end,
                  onClick = function(self)
                      if SGetSupported("classPowerClassColor") then
                          SSetSupported("classPowerClassColor", false)
                          ReloadAndUpdate(); UpdatePreview()
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      return SGetSupported("classPowerClassColor") and 0.3 or 1
                  end },
                { tooltip = "Dynamic Colored",
                  getValue = function()
                      local _, ct = UnitClass("player")
                      if ct and RAID_CLASS_COLORS[ct] then
                          local cc = RAID_CLASS_COLORS[ct]
                          return cc.r, cc.g, cc.b, 1
                      end
                      return 1, 0.82, 0, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      SSetSupported("classPowerClassColor", true)
                      ReloadAndUpdate(); UpdatePreview()
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      return SGetSupported("classPowerClassColor") and 1 or 0.3
                  end },
              } });  y = y - h
        SApplySupport(sharedClassResRow._leftRegion, "classPowerStyle")
        SApplySupport(sharedClassResRow._rightRegion, "classPowerClassColor")

        -- Inline "Empty Bar Color" swatch on Class Colors row (next to custom color swatch)
        do
            local ccRgn = sharedClassResRow._rightRegion
            local emptySwatch = EllesmereUI.BuildColorSwatch(ccRgn, ccRgn:GetFrameLevel() + 5,
                function()
                    local c = SGetSupported("classPowerEmptyColor")
                    c = c or { r = 0.2, g = 0.2, b = 0.2, a = 1.0 }
                    return c.r, c.g, c.b, c.a or 1
                end,
                function(r, g, b, a)
                    UNIT_DB_MAP[selectedUnit]().classPowerEmptyColor = { r = r, g = g, b = b, a = a or 1 }
                    if ns.frames and ns.frames._toggleClassPower then
                        ns.frames._toggleClassPower()
                    end
                    ReloadAndUpdate(); UpdatePreview()
                end, true, 20)
            emptySwatch:SetPoint("RIGHT", ccRgn._lastInline or ccRgn._control, "LEFT", -6, 0)
            ccRgn._lastInline = emptySwatch
            local function UpdateEmptySwatch()
                local crOff = SValSupported("classPowerStyle", "none") ~= "modern"
                if crOff then
                    emptySwatch:SetAlpha(0.15); emptySwatch:Disable()
                else
                    emptySwatch:SetAlpha(1); emptySwatch:Enable()
                end
            end
            UpdateEmptySwatch()
            RegisterWidgetRefresh(UpdateEmptySwatch)
            emptySwatch:HookScript("OnEnter", function(self)
                if SValSupported("classPowerStyle", "none") ~= "modern" then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires Class Resource to be set to Modern."))
                else
                    EllesmereUI.ShowWidgetTooltip(self, "Empty Bar Color")
                end
            end)
            emptySwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        end
        -- Sync icons: Enable Class Resource (left) and Class Colors (right)
        do
            local rgn = sharedClassResRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Class Resource Style to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().classPowerStyle or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        UNIT_DB_MAP[key]().classPowerStyle = v
                        UNIT_DB_MAP[key]().showClassPowerBar = (v ~= "none")
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().classPowerStyle or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().classPowerStyle or "none") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().classPowerStyle or "none"
                        for _, key in ipairs(checkedKeys) do
                            UNIT_DB_MAP[key]().classPowerStyle = v
                            UNIT_DB_MAP[key]().showClassPowerBar = (v ~= "none")
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = sharedClassResRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Class Colors to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().classPowerClassColor
                    if v == nil then v = true end
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().classPowerClassColor = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().classPowerClassColor
                    if v == nil then v = true end
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local ov = UNIT_DB_MAP[key]().classPowerClassColor
                        if ov == nil then ov = true end
                        if ov ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().classPowerClassColor
                        if v == nil then v = true end
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().classPowerClassColor = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Rows 2-3 are HIDDEN entirely while Enable Class Resource is None
        -- (the dropdown's DependentSetValue forces the rebuild on flips).
        if SValSupported("classPowerStyle", "none") ~= "none" then
        -- Row 2: Position (with cog for x/y) + Size
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Position", values=classPowerPosValues, order=classPowerPosOrder,
              disabled=function() return SValSupported("classPowerStyle", "none") ~= "modern" end,
              disabledTooltip="Class Resource must be set to Modern", rawTooltip=true,
              getValue=function() return SValSupported("classPowerPosition", "top") end,
              setValue=function(v)
                  SSetSupported("classPowerPosition", v)
                  if ns.frames and ns.frames._toggleClassPower then
                      ns.frames._toggleClassPower()
                  end
                  UpdatePreview(); UpdatePreview()
              end },
            { type="slider", text="Size", min=4, max=100, step=1,
              disabled=function() return SValSupported("classPowerStyle", "none") ~= "modern" end,
              disabledTooltip="Class Resource must be set to Modern", rawTooltip=true,
              getValue=function() return SValSupported("classPowerSize", 8) end,
              setValue=function(v)
                  SSetSupported("classPowerSize", v)
                  if ns.frames and ns.frames._toggleClassPower then
                      ns.frames._toggleClassPower()
                  end
                  UpdatePreview(); UpdatePreview()
              end });  y = y - h
        SApplySupport(row._leftRegion, "classPowerPosition")
        SApplySupport(row._rightRegion, "classPowerSize")
        -- Cog on Position for X/Y
        do
            local posRgn = row._leftRegion
            local _, cpPosCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Class Resource Position",
                rows = {
                    { type="slider", label="X Offset", min=-100, max=100, step=1,
                      get=function() return SValSupported("classPowerBarX", 0) end,
                      set=function(v) SSetSupported("classPowerBarX", v)
                          if ns.frames and ns.frames._toggleClassPower then ns.frames._toggleClassPower() end
                          UpdatePreview(); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-100, max=100, step=1,
                      get=function() return SValSupported("classPowerBarY", 0) end,
                      set=function(v) SSetSupported("classPowerBarY", v)
                          if ns.frames and ns.frames._toggleClassPower then ns.frames._toggleClassPower() end
                          UpdatePreview(); UpdatePreview() end },
                },
            })
            local cpPosCogShow = cpPosCogShowRaw
            local cpPosCogBtn = MakeCogBtn(posRgn, cpPosCogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local function UpdateCpPosCogState()
                local crOff = SValSupported("classPowerStyle", "none") ~= "modern"
                local isAbove = SValSupported("classPowerPosition", "top") == "above"
                local disabled = crOff or isAbove
                cpPosCogBtn:SetAlpha(disabled and 0.15 or 0.4)
                cpPosCogBtn:SetEnabled(not disabled)
            end
            cpPosCogBtn:SetScript("OnEnter", function(self)
                if SValSupported("classPowerStyle", "none") ~= "modern" then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires Class Resource to be set to Modern."))
                elseif SValSupported("classPowerPosition", "top") == "above" then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a dropdown selection other than Above Health Bar"))
                else self:SetAlpha(0.7) end
            end)
            cpPosCogBtn:SetScript("OnLeave", function(self) UpdateCpPosCogState(); EllesmereUI.HideWidgetTooltip() end)
            cpPosCogBtn:SetScript("OnClick", function(self) cpPosCogShow(self) end)
            UpdateCpPosCogState()
            RegisterWidgetRefresh(UpdateCpPosCogState)
        end
        -- Sync icons: Class Resource Position (left) and Size (right)
        do
            local rgn = row._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Class Resource Position to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().classPowerPosition or "top"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().classPowerPosition = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().classPowerPosition or "top"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().classPowerPosition or "top") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().classPowerPosition or "top"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().classPowerPosition = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = row._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Class Resource Size to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().classPowerSize or 8
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().classPowerSize = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().classPowerSize or 8
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().classPowerSize or 8) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().classPowerSize or 8
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().classPowerSize = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 3: Bar Spacing + Background Color (with alpha)
        local sharedClassResRow3
        sharedClassResRow3, h = W:DualRow(parent, y,
            { type="slider", pixel=true, text="Bar Spacing", min=0, max=10, step=1,
              disabled=function() return SValSupported("classPowerStyle", "none") ~= "modern" end,
              disabledTooltip="Class Resource must be set to Modern", rawTooltip=true,
              getValue=function() return SValSupported("classPowerSpacing", 2) end,
              setValue=function(v)
                  SSetSupported("classPowerSpacing", v)
                  if ns.frames and ns.frames._toggleClassPower then ns.frames._toggleClassPower() end
                  UpdatePreview(); UpdatePreview()
              end },
            { type="colorpicker", text="Background Color", hasAlpha=true,
              disabled=function() return SValSupported("classPowerStyle", "none") ~= "modern" end,
              disabledTooltip="Class Resource must be set to Modern", rawTooltip=true,
              getValue=function()
                  local c = SGetSupported("classPowerBgColor")
                  c = c or { r=0.082, g=0.082, b=0.082, a=1.0 }
                  return c.r, c.g, c.b, c.a
              end,
              setValue=function(r, g, b, a)
                  SSetSupported("classPowerBgColor", { r=r, g=g, b=b, a=a or 1 })
                  UpdatePreview()
              end });  y = y - h
        SApplySupport(sharedClassResRow3._leftRegion, "classPowerSpacing")
        SApplySupport(sharedClassResRow3._rightRegion, "classPowerBgColor")
        -- Sync icons: Bar Spacing (left) and Background Color (right)
        do
            local rgn = sharedClassResRow3._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Class Resource Bar Spacing to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().classPowerSpacing or 2
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().classPowerSpacing = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().classPowerSpacing or 2
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().classPowerSpacing or 2) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().classPowerSpacing or 2
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().classPowerSpacing = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = sharedClassResRow3._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Class Resource Background Color to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().classPowerBgColor
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if v then UNIT_DB_MAP[key]().classPowerBgColor = { r=v.r, g=v.g, b=v.b, a=v.a }
                        else UNIT_DB_MAP[key]().classPowerBgColor = nil end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().classPowerBgColor
                    local vr = v and v.r or 0
                    local vg = v and v.g or 0
                    local vb = v and v.b or 0
                    local va = v and v.a or 0.5
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local ov = UNIT_DB_MAP[key]().classPowerBgColor
                        local or_ = ov and ov.r or 0
                        local og = ov and ov.g or 0
                        local ob = ov and ov.b or 0
                        local oa = ov and ov.a or 0.5
                        if or_ ~= vr or og ~= vg or ob ~= vb or oa ~= va then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().classPowerBgColor
                        for _, key in ipairs(checkedKeys) do
                            if v then UNIT_DB_MAP[key]().classPowerBgColor = { r=v.r, g=v.g, b=v.b, a=v.a }
                            else UNIT_DB_MAP[key]().classPowerBgColor = nil end
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        end   -- close Class Resource hidden-while-None gate

        end -- _showClassRes

        _, h = W:Spacer(parent, y, 20); y = y - h

        local sharedBuffDebuffHeader
        -------------------------------------------------------------------
        --  BUFFS AND DEBUFFS
        -------------------------------------------------------------------
        sharedBuffDebuffHeader, h = W:SectionHeader(parent, "BUFFS AND DEBUFFS", y); y = y - h

        -- When Buff/Debuff Display is "none", everything in that column is disabled.
        local function BuffDisabled()
            local s = UNIT_DB_MAP[selectedUnit]()
            return s and s.showBuffs == false
        end
        local function DebuffDisabled()
            return SValSupported("debuffAnchor", "bottomleft") == "none"
        end

        -- Buffs: Location | Icon Size + inline directions cog (X/Y)
        local sharedAddRow2
        sharedAddRow2, h = W:DualRow(parent, y,
            { type="dropdown", text="Buff Display", values=buffAnchorValues, order=buffAnchorOrder,
              getValue=function()
                  local s = UNIT_DB_MAP[selectedUnit]()
                  if s.showBuffs == false then return "none" end
                  return SValSupported("buffAnchor", "topleft")
              end,
              -- DependentSetValue: the Buff Duration/Stack row (and, together
              -- with Debuff Display, the filter row) hides while None; only
              -- the None <-> shown flip forces the full rebuild.
              setValue=EllesmereUI.DependentSetValue(
                  function() return not BuffDisabled() end,
                  function(v)
                      local s = UNIT_DB_MAP[selectedUnit]()
                      if v == "none" then
                          s.showBuffs = false
                      else
                          s.showBuffs = true
                          SwapAuraSlot(s, "buffAnchor", v)
                      end
                      ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
                  end) },
            { type="slider", text="Buff Size", min=10, max=70, step=1,
              disabled=BuffDisabled, disabledTooltip="Buff Display",
              getValue=function() return SValSupported("buffSize", 22) end,
              setValue=function(v) SSetSupported("buffSize", v) end });  y = y - h
        SApplySupport(sharedAddRow2._leftRegion, "showBuffs")
        -- Sync icon: Buffs Location (left)
        do
            local rgn = sharedAddRow2._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Buffs Location to all Frames",
                onClick = function()
                    local s = UNIT_DB_MAP[selectedUnit]()
                    local showV = s.showBuffs
                    if showV == nil then showV = true end
                    local anchorV = s.buffAnchor or "topleft"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        UNIT_DB_MAP[key]().showBuffs = showV
                        if showV then UNIT_DB_MAP[key]().buffAnchor = anchorV end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local s = UNIT_DB_MAP[selectedUnit]()
                    local showV = s.showBuffs
                    if showV == nil then showV = true end
                    local anchorV = s.buffAnchor or "topleft"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local os = UNIT_DB_MAP[key]()
                        local ov = os.showBuffs; if ov == nil then ov = true end
                        if ov ~= showV then return false end
                        if showV and (os.buffAnchor or "topleft") ~= anchorV then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local s = UNIT_DB_MAP[selectedUnit]()
                        local showV = s.showBuffs
                        if showV == nil then showV = true end
                        local anchorV = s.buffAnchor or "topleft"
                        for _, key in ipairs(checkedKeys) do
                            UNIT_DB_MAP[key]().showBuffs = showV
                            if showV then UNIT_DB_MAP[key]().buffAnchor = anchorV end
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        -- Cog on Buffs Location (Growth + Max Count)
        do
            local leftRgn = sharedAddRow2._leftRegion
            local _, buffCogShow = EllesmereUI.BuildCogPopup({
                title = "Buff Settings",
                rows = {
                    { type="dropdown", label="Growth Direction", values=buffGrowthValues, order=buffGrowthOrder,
                      get=function() return SValSupported("buffGrowth", "auto") end,
                      set=function(v) SSetSupported("buffGrowth", v) end },
                    { type="slider", label="Max Count", min=1, max=40, step=1,
                      get=function() return SValSupported("maxBuffs", 4) end,
                      set=function(v) SSetSupported("maxBuffs", v) end },
                    { type="slider", label="Max Per Row", min=1, max=40, step=1,
                      get=function() return SValSupported("buffMaxPerRow", nil) or SValSupported("maxBuffs", 4) end,
                      set=function(v) SSetSupported("buffMaxPerRow", v) end },
                    { type="toggle", label="Cropped Icons",
                      get=function() return SValSupported("buffCropIcons", false) end,
                      set=function(v) SSetSupported("buffCropIcons", v) end },
                    { type="slider", label="Icon Zoom", min=0, max=0.20, step=0.01,
                      get=function() return SValSupported("buffIconZoom", 0.07) end,
                      set=function(v) SSetSupported("buffIconZoom", v) end },
                },
            })
            MakeCogBtn(leftRgn, buffCogShow, nil, nil, BuffDisabled)
        end
        -- Directions cog on Buff Icon Size (X/Y offsets)
        do
            local rightRgn = sharedAddRow2._rightRegion
            local _, buffPosCogShow = EllesmereUI.BuildCogPopup({
                title = "Buff Position",
                rows = {
                    { type="slider", label="Offset X", min=-1500, max=1500, step=1,
                      get=function() return SValSupported("buffOffsetX", 0) end,
                      set=function(v) SSetSupported("buffOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-1500, max=1500, step=1,
                      get=function() return SValSupported("buffOffsetY", 0) end,
                      set=function(v) SSetSupported("buffOffsetY", v) end },
                    -- Physical-pixel-perfect gaps between buff icons (X = columns, Y = rows).
                    { type="slider", pixel=true, label="Spacing X", min=-1, max=10, step=1,
                      get=function() return SValSupported("buffSpacingX", 1) end,
                      set=function(v) SSetSupported("buffSpacingX", v) end },
                    { type="slider", pixel=true, label="Spacing Y", min=-1, max=10, step=1,
                      get=function() return SValSupported("buffSpacingY", 1) end,
                      set=function(v) SSetSupported("buffSpacingY", v) end },
                },
            })
            MakeCogBtn(rightRgn, buffPosCogShow, nil, EllesmereUI.DIRECTIONS_ICON, BuffDisabled)
        end

        -- Buffs row 2: Duration Text Size | Stack Size. HIDDEN entirely while
        -- Buff Display is None (the dropdown's DependentSetValue rebuilds).
        -- Duration Size is gated by an inline "Show Cooldown Text" toggle (same
        -- DB key as before); when off, the slider/cog/label are disabled.
        if not BuffDisabled() then
        local buffDurOff = function() return BuffDisabled() or not SValSupported("buffShowCooldownText", false) end
        local buffDurTip = function() return BuffDisabled() and "Buff Display" or "Show Cooldown Text" end
        local sharedBuffRow2
        sharedBuffRow2, h = W:DualRow(parent, y,
            { type="slider", text="Buff Duration Size", min=6, max=100, step=1, trackWidth=120,
              disabled=buffDurOff, disabledTooltip=buffDurTip,
              getValue=function() return SValSupported("buffCooldownTextSize", 10) end,
              setValue=function(v) SSetSupported("buffCooldownTextSize", v) end },
            { type="slider", text="Buff Stack Size", min=6, max=100, step=1,
              disabled=BuffDisabled, disabledTooltip="Buff Display",
              getValue=function() return SValSupported("buffStackTextSize", 14) end,
              setValue=function(v) SSetSupported("buffStackTextSize", v) end });  y = y - h
        -- Directions cog on Buff Duration Size (X/Y offsets) -- disabled with the row
        do
            local leftRgn = sharedBuffRow2._leftRegion
            local _, buffDurCogShow = EllesmereUI.BuildCogPopup({
                title = "Duration Text",
                rows = {
                    { type="slider", label="Offset X", min=-100, max=100, step=1,
                      get=function() return SValSupported("buffCooldownTextOffsetX", 0) end,
                      set=function(v) SSetSupported("buffCooldownTextOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-100, max=100, step=1,
                      get=function() return SValSupported("buffCooldownTextOffsetY", 0) end,
                      set=function(v) SSetSupported("buffCooldownTextOffsetY", v) end },
                },
            })
            MakeCogBtn(leftRgn, buffDurCogShow, nil, EllesmereUI.DIRECTIONS_ICON, buffDurOff)
        end
        -- Inline "Show Cooldown Text" toggle on Buff Duration Size (always enabled)
        EllesmereUI.BuildInlineToggle({
            region   = sharedBuffRow2._leftRegion,
            getValue = function() return SValSupported("buffShowCooldownText", false) end,
            setValue = function(v) SSetSupported("buffShowCooldownText", v) end,
            onToggle = function() EllesmereUI:RefreshPage() end,
        })
        -- Directions cog on Buff Stack Size (X/Y offsets)
        do
            local rightRgn = sharedBuffRow2._rightRegion
            local _, buffStackPosCogShow = EllesmereUI.BuildCogPopup({
                title = "Stack Position",
                rows = {
                    { type="dropdown", label="Position",
                      values={ bottomright="Bottom Right", bottomleft="Bottom Left", topright="Top Right", topleft="Top Left", center="Center" },
                      order={ "bottomright", "bottomleft", "topright", "topleft", "center" },
                      get=function() return SValSupported("buffStackTextPosition", "bottomright") end,
                      set=function(v) SSetSupported("buffStackTextPosition", v) end },
                    { type="slider", label="Offset X", min=-100, max=100, step=1,
                      get=function() return SValSupported("buffStackTextOffsetX", 0) end,
                      set=function(v) SSetSupported("buffStackTextOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-100, max=100, step=1,
                      get=function() return SValSupported("buffStackTextOffsetY", 0) end,
                      set=function(v) SSetSupported("buffStackTextOffsetY", v) end },
                },
            })
            MakeCogBtn(rightRgn, buffStackPosCogShow, nil, EllesmereUI.DIRECTIONS_ICON, BuffDisabled)
        end
        end   -- close Buff row 2 hidden-while-None gate

        -- Debuffs: Location | Icon Size + inline directions cog (X/Y)
        local sharedAddRow3
        sharedAddRow3, h = W:DualRow(parent, y,
            { type="dropdown", text="Debuff Display", values=buffAnchorValues, order=buffAnchorOrder,
              getValue=function()
                  return SValSupported("debuffAnchor", "bottomleft")
              end,
              -- DependentSetValue: the Debuff Duration/Stack row (and, together
              -- with Buff Display, the filter row) hides while None; only the
              -- None <-> shown flip forces the full rebuild.
              setValue=EllesmereUI.DependentSetValue(
                  function() return not DebuffDisabled() end,
                  function(v)
                      SwapAuraSlot(UNIT_DB_MAP[selectedUnit](), "debuffAnchor", v)
                      ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
                  end) },
            { type="slider", text="Debuff Size", min=10, max=70, step=1,
              disabled=DebuffDisabled, disabledTooltip="Debuff Display",
              getValue=function() return SValSupported("debuffSize", 22) end,
              setValue=function(v) SSetSupported("debuffSize", v) end });  y = y - h
        -- Cog on Debuffs Location (Growth + Max Count)
        do
            local leftRgn = sharedAddRow3._leftRegion
            local _, debuffCogShow = EllesmereUI.BuildCogPopup({
                title = "Debuff Settings",
                rows = {
                    { type="dropdown", label="Growth Direction", values=buffGrowthValues, order=buffGrowthOrder,
                      get=function() return SValSupported("debuffGrowth", "auto") end,
                      set=function(v) SSetSupported("debuffGrowth", v) end },
                    { type="slider", label="Max Count", min=1, max=20, step=1,
                      get=function() return SValSupported("maxDebuffs", 20) end,
                      set=function(v) SSetSupported("maxDebuffs", v) end },
                    { type="slider", label="Max Per Row", min=1, max=20, step=1,
                      get=function() return SValSupported("debuffMaxPerRow", nil) or SValSupported("maxDebuffs", 20) end,
                      set=function(v) SSetSupported("debuffMaxPerRow", v) end },
                    { type="toggle", label="Cropped Icons",
                      get=function() return SValSupported("debuffCropIcons", false) end,
                      set=function(v) SSetSupported("debuffCropIcons", v) end },
                    { type="slider", label="Icon Zoom", min=0, max=0.20, step=0.01,
                      get=function() return SValSupported("debuffIconZoom", 0.07) end,
                      set=function(v) SSetSupported("debuffIconZoom", v) end },
                    { type="toggle", label="Dispel Type Borders",
                      get=function() return SValSupported("debuffDispelBorder", false) end,
                      set=function(v) SSetSupported("debuffDispelBorder", v) end },
                },
            })
            MakeCogBtn(leftRgn, debuffCogShow, nil, nil, DebuffDisabled)
        end
        -- Directions cog on Debuff Icon Size (X/Y offsets)
        do
            local rightRgn = sharedAddRow3._rightRegion
            local _, debuffPosCogShow = EllesmereUI.BuildCogPopup({
                title = "Debuff Position",
                rows = {
                    { type="slider", label="Offset X", min=-1500, max=1500, step=1,
                      get=function() return SValSupported("debuffOffsetX", 0) end,
                      set=function(v) SSetSupported("debuffOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-1500, max=1500, step=1,
                      get=function() return SValSupported("debuffOffsetY", 0) end,
                      set=function(v) SSetSupported("debuffOffsetY", v) end },
                    -- Physical-pixel-perfect gaps between debuff icons (X = columns, Y = rows).
                    { type="slider", pixel=true, label="Spacing X", min=-1, max=10, step=1,
                      get=function() return SValSupported("debuffSpacingX", 1) end,
                      set=function(v) SSetSupported("debuffSpacingX", v) end },
                    { type="slider", pixel=true, label="Spacing Y", min=-1, max=10, step=1,
                      get=function() return SValSupported("debuffSpacingY", 1) end,
                      set=function(v) SSetSupported("debuffSpacingY", v) end },
                },
            })
            MakeCogBtn(rightRgn, debuffPosCogShow, nil, EllesmereUI.DIRECTIONS_ICON, DebuffDisabled)
        end

        -- Debuffs row 2: Duration Text Size | Stack Size. HIDDEN entirely while
        -- Debuff Display is None (the dropdown's DependentSetValue rebuilds).
        -- Duration Size is gated by an inline "Show Cooldown Text" toggle (same
        -- DB key as before); when off, the slider/cog/label are disabled.
        if not DebuffDisabled() then
        local debuffDurOff = function() return DebuffDisabled() or not SValSupported("debuffShowCooldownText", false) end
        local debuffDurTip = function() return DebuffDisabled() and "Debuff Display" or "Show Cooldown Text" end
        local sharedDebuffRow2
        sharedDebuffRow2, h = W:DualRow(parent, y,
            { type="slider", text="Debuff Duration Size", min=6, max=100, step=1, trackWidth=120,
              disabled=debuffDurOff, disabledTooltip=debuffDurTip,
              getValue=function() return SValSupported("debuffCooldownTextSize", 10) end,
              setValue=function(v) SSetSupported("debuffCooldownTextSize", v) end },
            { type="slider", text="Debuff Stack Size", min=6, max=100, step=1,
              disabled=DebuffDisabled, disabledTooltip="Debuff Display",
              getValue=function() return SValSupported("debuffStackTextSize", 14) end,
              setValue=function(v) SSetSupported("debuffStackTextSize", v) end });  y = y - h
        -- Directions cog on Debuff Duration Size (X/Y offsets) -- disabled with the row
        do
            local leftRgn = sharedDebuffRow2._leftRegion
            local _, debuffDurCogShow = EllesmereUI.BuildCogPopup({
                title = "Duration Text",
                rows = {
                    { type="slider", label="Offset X", min=-100, max=100, step=1,
                      get=function() return SValSupported("debuffCooldownTextOffsetX", 0) end,
                      set=function(v) SSetSupported("debuffCooldownTextOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-100, max=100, step=1,
                      get=function() return SValSupported("debuffCooldownTextOffsetY", 0) end,
                      set=function(v) SSetSupported("debuffCooldownTextOffsetY", v) end },
                },
            })
            MakeCogBtn(leftRgn, debuffDurCogShow, nil, EllesmereUI.DIRECTIONS_ICON, debuffDurOff)
        end
        -- Inline "Show Cooldown Text" toggle on Debuff Duration Size (always enabled)
        EllesmereUI.BuildInlineToggle({
            region   = sharedDebuffRow2._leftRegion,
            getValue = function() return SValSupported("debuffShowCooldownText", false) end,
            setValue = function(v) SSetSupported("debuffShowCooldownText", v) end,
            onToggle = function() EllesmereUI:RefreshPage() end,
        })
        -- Directions cog on Debuff Stack Size (X/Y offsets)
        do
            local rightRgn = sharedDebuffRow2._rightRegion
            local _, debuffStackPosCogShow = EllesmereUI.BuildCogPopup({
                title = "Stack Position",
                rows = {
                    { type="dropdown", label="Position",
                      values={ bottomright="Bottom Right", bottomleft="Bottom Left", topright="Top Right", topleft="Top Left", center="Center" },
                      order={ "bottomright", "bottomleft", "topright", "topleft", "center" },
                      get=function() return SValSupported("debuffStackTextPosition", "bottomright") end,
                      set=function(v) SSetSupported("debuffStackTextPosition", v) end },
                    { type="slider", label="Offset X", min=-100, max=100, step=1,
                      get=function() return SValSupported("debuffStackTextOffsetX", 0) end,
                      set=function(v) SSetSupported("debuffStackTextOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-100, max=100, step=1,
                      get=function() return SValSupported("debuffStackTextOffsetY", 0) end,
                      set=function(v) SSetSupported("debuffStackTextOffsetY", v) end },
                },
            })
            MakeCogBtn(rightRgn, debuffStackPosCogShow, nil, EllesmereUI.DIRECTIONS_ICON, DebuffDisabled)
        end
        end   -- close Debuff row 2 hidden-while-None gate

        -- Built here with the aura section's helpers, but appended only after
        -- all other buff/debuff controls so the border row stays last.
        local function AddAuraBorderSettings()
        if selectedUnit == "player" or selectedUnit == "target" then
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local borderSizeValues = {
                none = "None", thin = "Thin", normal = "Normal",
                heavy = "Heavy", strong = "Strong",
            }
            local borderSizeOrder = { "none", "thin", "normal", "heavy", "strong" }
            local sizeToNumber = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }
            local numberToSize = { [0] = "none", [1] = "thin", [2] = "normal", [3] = "heavy", [4] = "strong" }
            local auraBorderRow
            auraBorderRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Border Style", values=texValues, order=texOrder,
                  getValue=function() return SVal("auraBorderTexture", "solid") end,
                  setValue=function(v)
                      local color, behind, behindUnitFrame = EllesmereUI.GetBorderStyleSelectDefaults(v)
                      local s = SDB()
                      s.auraBorderTexture = v
                      s.auraBorderTextureOffset = nil; s.auraBorderTextureOffsetY = nil
                      s.auraBorderTextureShiftX = nil; s.auraBorderTextureShiftY = nil
                      s.auraBorderBehind = behind
                      s.auraBorderBehindUnitFrame = behindUnitFrame
                      s.auraBorderR = color.r; s.auraBorderG = color.g; s.auraBorderB = color.b; s.auraBorderA = 1
                      local defSz = EllesmereUI.GetBorderDefaultSize("unitframes", v)
                      if defSz then s.auraBorderSize = defSz end
                      ReloadAndUpdate(); UpdatePreview()
                  end },
                { type="dropdown", text="Border Size", values=borderSizeValues, order=borderSizeOrder,
                  getValue=function() return numberToSize[SVal("auraBorderSize", 1)] or "thin" end,
                  setValue=function(v) SSetSupported("auraBorderSize", sizeToNumber[v] or 1) end }
            ); y = y - h

            do
                local rgn = auraBorderRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title="Border Offset",
                    rows={
                        { type="slider", label="Offset X", min=-10, max=10, step=1,
                          get=function()
                              local v = SGet("auraBorderTextureOffset"); if v ~= nil then return v end
                              return EllesmereUI.GetBorderDefaults("unitframes", SVal("auraBorderTexture", "solid"), SVal("auraBorderSize", 1))
                          end,
                          set=function(v) SSetSupported("auraBorderTextureOffset", v) end },
                        { type="slider", label="Offset Y", min=-10, max=10, step=1,
                          get=function()
                              local v = SGet("auraBorderTextureOffsetY"); if v ~= nil then return v end
                              local _, oy = EllesmereUI.GetBorderDefaults("unitframes", SVal("auraBorderTexture", "solid"), SVal("auraBorderSize", 1)); return oy
                          end,
                          set=function(v) SSetSupported("auraBorderTextureOffsetY", v) end },
                        { type="slider", label="Shift X", min=-10, max=10, step=1,
                          get=function()
                              local v = SGet("auraBorderTextureShiftX"); if v ~= nil then return v end
                              local _, _, sx = EllesmereUI.GetBorderDefaults("unitframes", SVal("auraBorderTexture", "solid"), SVal("auraBorderSize", 1)); return sx
                          end,
                          set=function(v) SSetSupported("auraBorderTextureShiftX", v == 0 and nil or v) end },
                        { type="slider", label="Shift Y", min=-10, max=10, step=1,
                          get=function()
                              local v = SGet("auraBorderTextureShiftY"); if v ~= nil then return v end
                              local _, _, _, sy = EllesmereUI.GetBorderDefaults("unitframes", SVal("auraBorderTexture", "solid"), SVal("auraBorderSize", 1)); return sy
                          end,
                          set=function(v) SSetSupported("auraBorderTextureShiftY", v == 0 and nil or v) end },
                        { type="toggle", label="Show Behind",
                          get=function() return SVal("auraBorderBehind", false) end,
                          set=function(v) SSetSupported("auraBorderBehind", v) end },
                        { type="toggle", label="Behind Unit Frame",
                          get=function() return SVal("auraBorderBehindUnitFrame", false) end,
                          set=function(v) SSetSupported("auraBorderBehindUnitFrame", v) end },
                    },
                })
                local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
                local function UpdateCogVis()
                    if SVal("auraBorderTexture", "solid") == "solid" then cogBtn:Hide() else cogBtn:Show() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis); UpdateCogVis()
            end

            do
                local rgn = auraBorderRow._rightRegion
                local swatch, refreshSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, auraBorderRow:GetFrameLevel() + 3,
                    function() return SVal("auraBorderR", 0), SVal("auraBorderG", 0), SVal("auraBorderB", 0), SVal("auraBorderA", 1) end,
                    function(r, g, b, a)
                        local s = SDB(); s.auraBorderR = r; s.auraBorderG = g; s.auraBorderB = b; s.auraBorderA = a
                        ReloadAndUpdate(); UpdatePreview()
                    end, true, 20)
                PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -8, 0)
                EllesmereUI.RegisterWidgetRefresh(refreshSwatch)
            end
        end
        end

        -- Per-unit aura filters (NOT synced). Labels track the selected section
        -- (Player/Target/Focus). Each is a multi-select checkbox dropdown; checked
        -- classifications OR together at runtime (Own Only = PLAYER, Raid Frames =
        -- RAID, Crowd Control, Big Defensive, External Defensive). "Own Only"
        -- reuses the legacy onlyPlayerDebuffs key so existing settings carry over.
        -- HIDDEN entirely only when BOTH displays are None (either Display
        -- dropdown's DependentSetValue rebuilds on its None flip); with one
        -- side shown, the row stays and the off side grays out as before.
        if not (BuffDisabled() and DebuffDisabled()) then
        do
            -- Version-branched classification lists: 12.1 exposes the full
            -- engine set; 12.0 keeps today's exact five entries. Both
            -- branches assign the SAME local names the consumers below use.
            local buffFilterItems, debuffFilterItems, BUFF_FILTER_KEYS, DEBUFF_FILTER_KEYS
            if EllesmereUI.IS_121 then
                -- Full 12.1 classification set. Checked classes OR together at
                -- runtime; all default OFF (off = show everything). Cancelable and
                -- Stealable are buff-side classes; Boss/Role/Priority are
                -- debuff-side engine selectors.
                buffFilterItems = {
                    { key = "raidFrames",        label = "Raid Frames",        tooltip = "Shows only the Buffs that appear on Raid Frames" },
                    { key = "raidInCombat",      label = "Raid (In Combat)",   tooltip = "Shows only auras flagged for raid frames during combat" },
                    { key = "dispellable",       label = "Dispellable",        tooltip = "Shows only auras with a dispel type you can dispel" },
                    { key = "crowdControl",      label = "Crowd Control",      tooltip = "Shows only crowd-control auras" },
                    { key = "bigDefensive",      label = "Big Defensive",      tooltip = "Shows only major defensive cooldowns" },
                    { key = "externalDefensive", label = "External Defensive", tooltip = "Shows only external defensive cooldowns cast on the unit" },
                    { key = "cancelable",        label = "Cancelable",         tooltip = "Shows only buffs that can be canceled" },
                    { key = "stealable",         label = "Stealable",          tooltip = "Shows only buffs you can spellsteal or purge" },
                    { key = "ownOnly",           label = "Own Only",           tooltip = "Shows only the Buffs you apply" },
                }
                debuffFilterItems = {
                    { key = "raidFrames",        label = "Raid Frames",        tooltip = "Shows only the Debuffs that appear on Raid Frames" },
                    { key = "raidInCombat",      label = "Raid (In Combat)",   tooltip = "Shows only auras flagged for raid frames during combat" },
                    { key = "dispellable",       label = "Dispellable",        tooltip = "Shows only auras with a dispel type you can dispel" },
                    { key = "crowdControl",      label = "Crowd Control",      tooltip = "Shows only crowd-control auras" },
                    { key = "bigDefensive",      label = "Big Defensive",      tooltip = "Shows only major defensive cooldowns" },
                    { key = "externalDefensive", label = "External Defensive", tooltip = "Shows only external defensive cooldowns cast on the unit" },
                    { key = "bossAura",          label = "Boss Auras",         tooltip = "Shows only debuffs applied by bosses" },
                    { key = "roleAura",          label = "Role Auras",         tooltip = "Shows only debuffs flagged for your role" },
                    { key = "priorityAura",      label = "Priority",           tooltip = "Shows only priority debuffs" },
                    { key = "ownOnly",           label = "Own Only",           tooltip = "Shows only the Debuffs you apply" },
                }
                BUFF_FILTER_KEYS   = { ownOnly = "onlyPlayerBuffs",   raidFrames = "buffRaid",   raidInCombat = "buffRaidInCombat",   dispellable = "buffDispellable",   crowdControl = "buffCrowdControl",   bigDefensive = "buffBigDefensive",   externalDefensive = "buffExternalDefensive",   cancelable = "buffCancelable", stealable = "buffStealable" }
                DEBUFF_FILTER_KEYS = { ownOnly = "onlyPlayerDebuffs", raidFrames = "debuffRaid", raidInCombat = "debuffRaidInCombat", dispellable = "debuffDispellable", crowdControl = "debuffCrowdControl", bigDefensive = "debuffBigDefensive", externalDefensive = "debuffExternalDefensive", bossAura = "debuffBossAura", roleAura = "debuffRoleAura", priorityAura = "debuffPriorityAura" }
            else
                buffFilterItems = {
                    { key = "raidFrames",        label = "Raid Frames",        tooltip = "Shows only the Buffs/Debuffs that appear on Raid Frames" },
                    { key = "crowdControl",      label = "Crowd Control",      tooltip = "Shows only crowd-control auras" },
                    { key = "bigDefensive",      label = "Big Defensive",      tooltip = "Shows only major defensive cooldowns" },
                    { key = "externalDefensive", label = "External Defensive", tooltip = "Shows only external defensive cooldowns cast on the unit" },
                    { key = "ownOnly",           label = "Own Only",           tooltip = "Shows only the Buffs/Debuffs you apply" },
                }
                debuffFilterItems = buffFilterItems
                BUFF_FILTER_KEYS   = { ownOnly = "onlyPlayerBuffs",   raidFrames = "buffRaid",   crowdControl = "buffCrowdControl",   bigDefensive = "buffBigDefensive",   externalDefensive = "buffExternalDefensive" }
                DEBUFF_FILTER_KEYS = { ownOnly = "onlyPlayerDebuffs", raidFrames = "debuffRaid", crowdControl = "debuffCrowdControl", bigDefensive = "debuffBigDefensive", externalDefensive = "debuffExternalDefensive" }
            end
            -- "Own Only" is not offered for the PLAYER's debuffs (you rarely apply
            -- your own debuffs to yourself); any stale onlyPlayerDebuffs value is
            -- ignored at runtime.
            if selectedUnit == "player" then
                local trimmed = {}
                for _, it in ipairs(debuffFilterItems) do
                    if it.key ~= "ownOnly" then trimmed[#trimmed + 1] = it end
                end
                debuffFilterItems = trimmed
            end
            local unitLabel = UNIT_LABELS_SUP[selectedUnit] or "Player"
            local filterRow
            filterRow, h = W:DualRow(parent, y,
                { type="dropdown", text=unitLabel.." Buff Filter",
                  values={ __placeholder="..." }, order={ "__placeholder" },
                  getValue=function() return "__placeholder" end, setValue=function() end },
                { type="dropdown", text=unitLabel.." Debuff Filter",
                  values={ __placeholder="..." }, order={ "__placeholder" },
                  getValue=function() return "__placeholder" end, setValue=function() end });  y = y - h
            -- Gray out + block a CB-dropdown when its column's Display is "none".
            local function ApplyFilterDisabled(cbDD, label, isOff)
                local function refresh()
                    local off = isOff()
                    cbDD:SetAlpha(off and 0.3 or 1)
                    cbDD:EnableMouse(not off)
                    if label then label:SetAlpha(off and 0.3 or 1) end
                end
                refresh()
                RegisterWidgetRefresh(refresh)
            end
            -- Left slot: Buff Filter
            do
                local rgn = filterRow._leftRegion
                if rgn._control then rgn._control:Hide() end
                local cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    rgn, 210, rgn:GetFrameLevel() + 2, buffFilterItems,
                    function(k) return SValSupported(BUFF_FILTER_KEYS[k], false) end,
                    function(k, v) SSetSupported(BUFF_FILTER_KEYS[k], v) end)
                PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
                rgn._control = cbDD; rgn._lastInline = nil
                RegisterWidgetRefresh(cbRefresh)
                ApplyFilterDisabled(cbDD, rgn._label, BuffDisabled)
            end
            -- Right slot: Debuff Filter
            do
                local rgn = filterRow._rightRegion
                if rgn._control then rgn._control:Hide() end
                local cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    rgn, 210, rgn:GetFrameLevel() + 2, debuffFilterItems,
                    function(k) return SValSupported(DEBUFF_FILTER_KEYS[k], false) end,
                    function(k, v) SSetSupported(DEBUFF_FILTER_KEYS[k], v) end)
                PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
                rgn._control = cbDD; rgn._lastInline = nil
                RegisterWidgetRefresh(cbRefresh)
                ApplyFilterDisabled(cbDD, rgn._label, DebuffDisabled)
                -- Inline cog: Show Lust Debuff. NOT part of the filter system --
                -- forces the Sated/Exhaustion (lust) debuff to show. Off by default.
                local _, lustCogShow = EllesmereUI.BuildCogPopup({
                    title = "Debuff Extras",
                    rows = {
                        { type="toggle", label="Show Lust Debuff",
                          get=function() return SValSupported("showLustDebuff", false) end,
                          set=function(v) SSetSupported("showLustDebuff", v) end },
                    },
                })
                MakeCogBtn(rgn, lustCogShow)
            end
        end
        end   -- close filter row hidden-while-both-None gate

        -- Dispel Overlay + Dispel Colors (player frame only; settings keys
        -- mirror the Raid Frames dispel system 1:1)
        if selectedUnit == "player" then
            local dispelOverlayValues = {
                none     = "None",
                fill     = "Fill Overlay",
                full     = "Full Overlay",
                gradient = "Gradient Overlay",
                gradient_sharp = "Gradient Sharp",
            }
            local dispelOverlayOrder = { "none", "fill", "full", "gradient", "gradient_sharp" }
            local function DispelRefresh()
                if ns.UpdatePlayerDispelOverlay then ns.UpdatePlayerDispelOverlay() end
                UpdatePreview()
            end
            local dispelRow
            dispelRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Dispel Overlay", values=dispelOverlayValues, order=dispelOverlayOrder,
                  getValue=function() return db.profile.dispelOverlay or "none" end,
                  -- RefreshPage (fast path) so the Dispel Colors disabled
                  -- state tracks the overlay selection live.
                  setValue=function(v) db.profile.dispelOverlay = v; DispelRefresh(); EllesmereUI:RefreshPage() end },
                { type="multiSwatch", text="Dispel Colors",
                  disabled=function() return (db.profile.dispelOverlay or "none") == "none" end,
                  disabledTooltip="Dispel Overlay",
                  swatches = {
                    { tooltip = "Magic", hasAlpha = false,
                      getValue = function() local c = db.profile.dispelColorMagic; if c then return c.r, c.g, c.b end return 0.349, 0.475, 1.0 end,
                      setValue = function(r, g, b) db.profile.dispelColorMagic = { r=r, g=g, b=b }; DispelRefresh() end },
                    { tooltip = "Curse", hasAlpha = false,
                      getValue = function() local c = db.profile.dispelColorCurse; if c then return c.r, c.g, c.b end return 0.636, 0.0, 0.64 end,
                      setValue = function(r, g, b) db.profile.dispelColorCurse = { r=r, g=g, b=b }; DispelRefresh() end },
                    { tooltip = "Disease", hasAlpha = false,
                      getValue = function() local c = db.profile.dispelColorDisease; if c then return c.r, c.g, c.b end return 0.671, 0.384, 0.098 end,
                      setValue = function(r, g, b) db.profile.dispelColorDisease = { r=r, g=g, b=b }; DispelRefresh() end },
                    { tooltip = "Poison", hasAlpha = false,
                      getValue = function() local c = db.profile.dispelColorPoison; if c then return c.r, c.g, c.b end return 0.0, 0.706, 0.286 end,
                      setValue = function(r, g, b) db.profile.dispelColorPoison = { r=r, g=g, b=b }; DispelRefresh() end },
                    { tooltip = "Bleed", hasAlpha = false,
                      getValue = function() local c = db.profile.dispelColorBleed; if c then return c.r, c.g, c.b end return 0.75, 0.15, 0.15 end,
                      setValue = function(r, g, b) db.profile.dispelColorBleed = { r=r, g=g, b=b }; DispelRefresh() end },
                  } });  y = y - h
            -- Inline eyeball: preview a magic dispel overlay on the top player preview.
            do
                local rgn = dispelRow._leftRegion
                local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
                local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
                local eyeBtn = CreateFrame("Button", nil, rgn)
                eyeBtn:SetSize(26, 26)
                eyeBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                eyeBtn:SetAlpha(0.4)
                rgn._lastInline = eyeBtn
                local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
                eyeTex:SetAllPoints()
                local function RefreshDispelEye()
                    eyeTex:SetTexture(showDispelOverlayPreview and EYE_INVISIBLE or EYE_VISIBLE)
                end
                RefreshDispelEye()
                eyeBtn:SetScript("OnClick", function()
                    showDispelOverlayPreview = not showDispelOverlayPreview
                    RefreshDispelEye()
                    UpdatePreview()
                end)
                eyeBtn:SetScript("OnEnter", function(self)
                    self:SetAlpha(0.7)
                    EllesmereUI.ShowWidgetTooltip(self, showDispelOverlayPreview and "Hide dispel overlay preview" or "Show dispel overlay preview")
                end)
                eyeBtn:SetScript("OnLeave", function(self)
                    self:SetAlpha(0.4)
                    EllesmereUI.HideWidgetTooltip()
                end)
            end
            -- Inline cog on Dispel Overlay: Overlay Opacity
            do
                local rgn = dispelRow._leftRegion
                local _, opShow = EllesmereUI.BuildCogPopup({
                    title = "Dispel Overlay",
                    rows = {
                        { type="slider", label="Overlay Opacity", min=5, max=100, step=1,
                          get=function() return db.profile.dispelOverlayOpacity or 100 end,
                          set=function(v) db.profile.dispelOverlayOpacity = v; DispelRefresh() end },
                        { type="toggle", label="Only Dispellable by You",
                          tooltip="Shows the overlay only for debuffs you can currently dispel.",
                          get=function() return db.profile.dispelOverlayByMe == true end,
                          set=function(v) db.profile.dispelOverlayByMe = v and true or false; DispelRefresh() end },
                    },
                })
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                cogBtn:SetAlpha(0.4)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints()
                cogTex:SetTexture(EllesmereUI.COGS_ICON)
                cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                cogBtn:SetScript("OnClick", function(self) opShow(self) end)
            end
        end

        AddAuraBorderSettings()

        -------------------------------------------------------------------
        --  PRIVATE AURAS (player frame only)
        -------------------------------------------------------------------
        if selectedUnit == "player" then
        _, h = W:Spacer(parent, y, 20); y = y - h
        _, h = W:SectionHeader(parent, "PRIVATE AURAS", y); y = y - h

        local function PrivGet(key, default)
            local p = db.profile.player
            local v = p and p[key]
            if v ~= nil then return v end
            return default
        end
        local function PrivSet(key, v)
            db.profile.player[key] = v
            ReloadAndUpdate()
        end

        local paPosValues = {
            none        = "None",
            topleft     = "Top Left",
            top         = "Top",
            topright    = "Top Right",
            left        = "Left",
            center      = "Center",
            right       = "Right",
            bottomleft  = "Bottom Left",
            bottom      = "Bottom",
            bottomright = "Bottom Right",
        }
        local paPosOrder = { "none", "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
        local paGrowValues = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" }
        local paGrowOrder = { "RIGHT", "LEFT", "UP", "DOWN" }

        local function GetDefaultPaGrow(pos)
            if pos == "right" or pos == "topright" or pos == "bottomright" then return "LEFT" end
            if pos == "left" or pos == "topleft" or pos == "bottomleft" then return "RIGHT" end
            if pos == "top" then return "DOWN" end
            if pos == "bottom" then return "UP" end
            return "RIGHT"
        end

        -- Row 1: Enable Private Auras | Position (+ cog X/Y)
        local paRow1
        paRow1, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Private Auras",
              tooltip="Show Blizzard's private boss-mechanic aura icons on the player frame.",
              getValue=function() return PrivGet("paEnabled", false) end,
              -- DependentSetValue: Rows 2-4 below are hidden while Private
              -- Auras are off; the flip forces the full rebuild.
              setValue=EllesmereUI.DependentSetValue(
                  function() return PrivGet("paEnabled", false) end,
                  function(v) PrivSet("paEnabled", v) end) },
            { type="dropdown", text="Position", values=paPosValues, order=paPosOrder,
              getValue=function() return PrivGet("paPosition", "center") end,
              setValue=function(v)
                  PrivSet("paPosition", v)
                  PrivSet("paGrowDirection", GetDefaultPaGrow(v))
                  EllesmereUI:RefreshPage()
              end });  y = y - h
        -- Cog for position offset X/Y
        do
            local rgn = paRow1._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Private Aura Offset",
                rows = {
                    { type="slider", label="Offset X", min=-50, max=50, step=1,
                      get=function() return PrivGet("paOffsetX", 0) end,
                      set=function(v) PrivSet("paOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-50, max=50, step=1,
                      get=function() return PrivGet("paOffsetY", 0) end,
                      set=function(v) PrivSet("paOffsetY", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -- Rows 2-4 are HIDDEN entirely while Enable Private Auras is off (the
        -- toggle's DependentSetValue forces the rebuild on flips).
        if PrivGet("paEnabled", false) then
        -- Row 2: Growth Direction | Icon Size
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Growth Direction", values=paGrowValues, order=paGrowOrder,
              getValue=function() return PrivGet("paGrowDirection", "RIGHT") end,
              setValue=function(v) PrivSet("paGrowDirection", v) end },
            { type="slider", text="Icon Size", min=10, max=50, step=1,
              getValue=function() return PrivGet("paSize", 20) end,
              setValue=function(v) PrivSet("paSize", v) end });  y = y - h

        -- Row 3: Spacing | Show Countdown Text
        _, h = W:DualRow(parent, y,
            { type="slider", pixel=true, text="Spacing", min=-1, max=10, step=1,
              getValue=function() return PrivGet("paSpacing", 0) end,
              setValue=function(v) PrivSet("paSpacing", v) end },
            { type="toggle", text="Show Countdown Text",
              getValue=function() return PrivGet("paShowCountdown", false) end,
              setValue=function(v) PrivSet("paShowCountdown", v) end });  y = y - h

        -- Row 4: Hide Tooltips | (blank)
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Tooltips",
              getValue=function() return PrivGet("paHideTooltip", true) end,
              setValue=function(v) PrivSet("paHideTooltip", v) end },
            { type="label", text="" });  y = y - h
        end   -- close Private Auras hidden-while-disabled gate
        end -- selectedUnit == "player" (private auras)

        _, h = W:Spacer(parent, y, 20); y = y - h

        -------------------------------------------------------------------
        --  ABSORBS (player/target/focus -- mirrors the Raid Frames section)
        -------------------------------------------------------------------
        -- Declared outside the gate: the click-mapping table at the bottom of
        -- this function references them (block-locals would be nil there).
        local sharedAbsorbsHeader, absorbRow
        local _supportsAbsorbs = (selectedUnit == "player" or selectedUnit == "target" or selectedUnit == "focus")
        if _supportsAbsorbs then
        sharedAbsorbsHeader, h = W:SectionHeader(parent, "ABSORBS", y); y = y - h

        local absorbStyleValues = {
            ["none"]            = "None",
            ["striped"]         = "Striped",
            ["stripedReversed"] = "Striped Reversed",
            ["clean"]           = "Clean (Flat)",
            ["blizzard"]        = "Blizzard",
            ["largeOutlinedStripes"]  = "Large Outlined Stripes",  -- heal-absorb only: large-habsorb-left.png
            ["largeOutlinedStripesR"] = "Large Outlined Stripes R", -- heal-absorb only: large-habsorb-right.png
            ["largeStripes"]          = "Large Stripes",            -- large-absorb-left.png
            ["largeStripesR"]         = "Large Stripes R",          -- large-absorb-right.png
        }
        -- Shield (regular) absorb dropdown order. Heal absorb uses its own
        -- order (it adds the two "Outlined" variants on top).
        local absorbStyleOrder = { "none", "striped", "stripedReversed", "clean", "blizzard", "largeStripes", "largeStripesR" }
        local healAbsorbStyleOrder = { "none", "striped", "stripedReversed", "clean", "blizzard", "largeOutlinedStripes", "largeOutlinedStripesR", "largeStripes", "largeStripesR" }
        -- Append SharedMedia statusbar textures after a divider, mirroring the
        -- Bar Texture dropdown. SM keys ("sm:" prefixed) were appended to the
        -- shared health-bar tables by AppendSharedMediaTextures; render-time
        -- resolution flows through ns.ResolveAbsorbStyleTex -> the health-bar
        -- texture lookup. Both the shield and heal-absorb dropdowns share
        -- absorbStyleValues, so both gain the SM entries and the preview swatch.
        do
            if EllesmereUI.AppendSharedMediaTextures then
                EllesmereUI.AppendSharedMediaTextures(
                    ns.healthBarTextureNames or {}, ns.healthBarTextureOrder or {}, nil, ns.healthBarTextures)
            end
            local smNames = ns.healthBarTextureNames or {}
            local smKeys = {}
            for _, k in ipairs(ns.healthBarTextureOrder or {}) do
                if type(k) == "string" and k:find("^sm:") then
                    smKeys[#smKeys + 1] = k
                    absorbStyleValues[k] = smNames[k] or k
                end
            end
            if #smKeys > 0 then
                absorbStyleOrder[#absorbStyleOrder + 1] = "---"
                healAbsorbStyleOrder[#healAbsorbStyleOrder + 1] = "---"
                for _, k in ipairs(smKeys) do
                    absorbStyleOrder[#absorbStyleOrder + 1] = k
                    healAbsorbStyleOrder[#healAbsorbStyleOrder + 1] = k
                end
            end
            -- Preview swatch behind each menu row, resolved exactly like render.
            absorbStyleValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    if not key or key == "---" or key == "none" then return nil end
                    return ns.ResolveAbsorbStyleTex and ns.ResolveAbsorbStyleTex(key) or nil
                end,
            }
        end

        -- Effective absorb opacity: absorbOpacity once set, otherwise the
        -- pre-split behavior (clean -> absorbCleanAlpha, other styles 80).
        -- Must match GetAbsorbOpacity in EllesmereUIUnitFrames.lua.
        local function EffAbsorbOpacity()
            local v = SValSupported("absorbOpacity", nil)
            if v then return v end
            if SValSupported("showPlayerAbsorb", "none") == "clean" then
                return SValSupported("absorbCleanAlpha", 30)
            end
            return 80
        end

        -- The Absorb Style / Heal Absorb Style sync icons carry the style, the
        -- inline color swatch, AND every inline-cog setting together. Each entry
        -- is a DB key + its default, so an unset value compares equal to an
        -- explicit one. Color tables are deep-copied and compared by component.
        local ABSORB_SYNC_DEFS = {
            { k = "showPlayerAbsorb", d = "none" },
            { k = "absorbColor",      d = { r = 1, g = 1, b = 1 } },
            { k = "absorbEdgeMode",   d = "overlay" },
            { k = "showOvershield",   d = true },
        }
        local HEAL_ABSORB_SYNC_DEFS = {
            { k = "healAbsorbStyle",     d = "clean" },
            { k = "healAbsorbColor",     d = { r = 0.8, g = 0.15, b = 0.15 } },
            { k = "healAbsorbEdgeMode",  d = "overlay" },
            { k = "healAbsorbBgOpacity", d = 15 },
        }
        local function _AbsSyncValEq(a, b)
            if type(a) == "table" or type(b) == "table" then
                a = a or {}; b = b or {}
                return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
            end
            return a == b
        end
        local function CopyAbsorbSync(defs, srcUnit, dstUnit)
            if srcUnit == dstUnit then return end
            local src, dst = UNIT_DB_MAP[srcUnit](), UNIT_DB_MAP[dstUnit]()
            for _, e in ipairs(defs) do
                local v = src[e.k]; if v == nil then v = e.d end
                if type(v) == "table" then
                    dst[e.k] = { r = v.r, g = v.g, b = v.b, a = v.a }
                else
                    dst[e.k] = v
                end
            end
        end
        local function AbsorbSyncMatches(defs, srcUnit, units)
            local src = UNIT_DB_MAP[srcUnit]()
            for _, unit in ipairs(units) do
                local dst = UNIT_DB_MAP[unit]()
                for _, e in ipairs(defs) do
                    local a = src[e.k]; if a == nil then a = e.d end
                    local b = dst[e.k]; if b == nil then b = e.d end
                    if not _AbsSyncValEq(a, b) then return false end
                end
            end
            return true
        end

        -- Row 1: Absorb Style (+ color swatch + placement cog) | Absorb Opacity
        absorbRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Absorb Style", values=absorbStyleValues, order=absorbStyleOrder,
              getValue=function() return SValSupported("showPlayerAbsorb", "none") end,
              setValue=function(v)
                  if v == "clean" then
                      UNIT_DB_MAP[selectedUnit]().absorbOpacity = 30
                  else
                      UNIT_DB_MAP[selectedUnit]().absorbOpacity = 90
                  end
                  SSetSupported("showPlayerAbsorb", v)
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Absorb Opacity", min=5, max=100, step=1,
              disabled=function() return SValSupported("showPlayerAbsorb", "none") == "none" end,
              disabledTooltip="Absorb Style",
              getValue=EffAbsorbOpacity,
              setValue=function(v) SSetSupported("absorbOpacity", v) end });  y = y - h
        SApplySupport(absorbRow._leftRegion, "showPlayerAbsorb")
        SApplySupport(absorbRow._rightRegion, "absorbOpacity")
        -- Inline color swatch for absorb color
        do
            local rgn = absorbRow._leftRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, absorbRow:GetFrameLevel() + 3,
                function()
                    local c = SGetSupported("absorbColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 1, 1, 1, 1
                end,
                function(r, g, b)
                    UNIT_DB_MAP[selectedUnit]().absorbColor = { r=r, g=g, b=b }
                    ReloadAndUpdate(); UpdatePreview()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
            local function UpdateAbsorbSwatchVis()
                swatch:SetAlpha(SValSupported("showPlayerAbsorb", "none") == "none" and 0.3 or 1)
            end
            RegisterWidgetRefresh(UpdateAbsorbSwatchVis)
            UpdateAbsorbSwatchVis()
        end
        -- Inline cog: absorb placement (overlay / right edge / left edge)
        do
            local rgn = absorbRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Absorb Rendering",
                rows = {
                    { type="dropdown", label="Placement",
                      values = { overlay = "Overlay", right = "From Right Edge", left = "From Left Edge" },
                      order = { "overlay", "right", "left" },
                      get=function() return SValSupported("absorbEdgeMode", "overlay") end,
                      set=function(v) SSetSupported("absorbEdgeMode", v) end },
                    { type="toggle", label="Show Overshield",
                      tooltip="Show the part of an absorb that exceeds your empty health and backfills over your current health. When off, absorbs only fill the empty part of the health bar.",
                      get=function() return SValSupported("showOvershield", true) end,
                      set=function(v) SSetSupported("showOvershield", v) end },
                    -- Single global toggle (boss block key, nil = enabled):
                    -- boss frames render absorbs with the TARGET frame's
                    -- absorb styling -- no per-boss customization.
                    { type="toggle", label="Show on Boss Frames",
                      tooltip="Render absorbs on Boss Frames using the Target frame's absorb styling.",
                      get=function() return not (db.profile.boss and db.profile.boss.showAbsorbs == false) end,
                      set=function(v)
                          local b = db.profile.boss
                          if b then
                              if v then b.showAbsorbs = nil else b.showAbsorbs = false end
                          end
                          ReloadAndUpdate()
                      end },
                },
            })
            MakeCogBtn(rgn, cogShow)
        end
        -- Sync icon: Absorb Style + color swatch + cog settings across all frames
        do
            local rgn = absorbRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Absorb Style, color and rendering to all Frames",
                onClick = function()
                    for _, key in ipairs(GROUP_UNIT_ORDER) do CopyAbsorbSync(ABSORB_SYNC_DEFS, selectedUnit, key) end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    return AbsorbSyncMatches(ABSORB_SYNC_DEFS, selectedUnit, GROUP_UNIT_ORDER)
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        for _, key in ipairs(checkedKeys) do CopyAbsorbSync(ABSORB_SYNC_DEFS, selectedUnit, key) end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 2: Heal Absorb Style (+ color swatch + placement cog) | Heal Absorb Opacity
        local healAbsorbRow
        healAbsorbRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Heal Absorb Style", values=absorbStyleValues,
              order=healAbsorbStyleOrder,
              getValue=function() return SValSupported("healAbsorbStyle", "clean") end,
              setValue=function(v)
                  if v == "clean" then
                      UNIT_DB_MAP[selectedUnit]().healAbsorbOpacity = 50
                  else
                      UNIT_DB_MAP[selectedUnit]().healAbsorbOpacity = 75
                  end
                  SSetSupported("healAbsorbStyle", v)
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Heal Absorb Opacity", min=5, max=100, step=1,
              disabled=function() return SValSupported("healAbsorbStyle", "clean") == "none" end,
              disabledTooltip="Heal Absorb Style",
              getValue=function() return SValSupported("healAbsorbOpacity", 65) end,
              setValue=function(v) SSetSupported("healAbsorbOpacity", v) end });  y = y - h
        SApplySupport(healAbsorbRow._leftRegion, "healAbsorbStyle")
        SApplySupport(healAbsorbRow._rightRegion, "healAbsorbOpacity")
        -- Inline eyeball: preview the heal absorb on the live preview frame.
        -- While on, the shield (regular) absorb is hidden on the preview so the
        -- heal absorb is shown in isolation. State is a session-only runtime flag.
        do
            local rgn = healAbsorbRow._leftRegion
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
            local eyeBtn = CreateFrame("Button", nil, rgn)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            eyeBtn:SetAlpha(0.4)
            rgn._lastInline = eyeBtn
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function RefreshHealEye()
                eyeTex:SetTexture(showHealAbsorbPreview and EYE_INVISIBLE or EYE_VISIBLE)
            end
            RefreshHealEye()
            eyeBtn:SetScript("OnClick", function()
                showHealAbsorbPreview = not showHealAbsorbPreview
                RefreshHealEye()
                UpdatePreview()
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, showHealAbsorbPreview and "Hide heal absorb preview" or "Show heal absorb preview")
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                self:SetAlpha(0.4)
                EllesmereUI.HideWidgetTooltip()
            end)
        end
        -- Inline color swatch for heal absorb color
        do
            local rgn = healAbsorbRow._leftRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, healAbsorbRow:GetFrameLevel() + 3,
                function()
                    local c = SGetSupported("healAbsorbColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 0.8, 0.15, 0.15, 1
                end,
                function(r, g, b)
                    UNIT_DB_MAP[selectedUnit]().healAbsorbColor = { r=r, g=g, b=b }
                    ReloadAndUpdate(); UpdatePreview()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
            -- Blocking overlay: disabled for "none" and the pre-colored
            -- "Large Outlined Stripes" heal styles (their texture is not tinted).
            local swatchBlock = CreateFrame("Frame", nil, swatch)
            swatchBlock:SetAllPoints()
            swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
            swatchBlock:EnableMouse(true)
            swatchBlock:Hide()
            local function UpdateHealAbsorbSwatchVis()
                local st = SValSupported("healAbsorbStyle", "clean")
                local off = (st == "none" or st == "largeOutlinedStripes" or st == "largeOutlinedStripesR")
                swatch:SetAlpha(off and 0.3 or 1)
                if off then swatchBlock:Show() else swatchBlock:Hide() end
            end
            RegisterWidgetRefresh(UpdateHealAbsorbSwatchVis)
            UpdateHealAbsorbSwatchVis()
        end
        -- Inline cog: heal absorb placement (independent of shield absorb)
        do
            local rgn = healAbsorbRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Heal Absorb Rendering",
                rows = {
                    { type="dropdown", label="Placement",
                      values = { overlay = "Overlay", right = "From Right Edge", left = "From Left Edge" },
                      order = { "overlay", "right", "left" },
                      get=function() return SValSupported("healAbsorbEdgeMode", "overlay") end,
                      set=function(v) SSetSupported("healAbsorbEdgeMode", v) end },
                    { type="slider", label="Backing Opacity", min=0, max=100, step=1,
                      get=function() return SValSupported("healAbsorbBgOpacity", 15) end,
                      set=function(v) SSetSupported("healAbsorbBgOpacity", v) end },
                },
            })
            MakeCogBtn(rgn, cogShow)
        end
        -- Sync icon: Heal Absorb Style + color swatch + cog settings across all frames
        do
            local rgn = healAbsorbRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Heal Absorb Style, color and rendering to all Frames",
                onClick = function()
                    for _, key in ipairs(GROUP_UNIT_ORDER) do CopyAbsorbSync(HEAL_ABSORB_SYNC_DEFS, selectedUnit, key) end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    return AbsorbSyncMatches(HEAL_ABSORB_SYNC_DEFS, selectedUnit, GROUP_UNIT_ORDER)
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        for _, key in ipairs(checkedKeys) do CopyAbsorbSync(HEAL_ABSORB_SYNC_DEFS, selectedUnit, key) end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 3: Absorb Bar (position dropdown) | Bar Height (+ alpha swatch)
        local absorbBarRow
        absorbBarRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Absorb Bar",
              values={ none="None", aboveRight="Above Frame Right", aboveLeft="Above Frame Left", topRight="Top Right", topLeft="Top Left" },
              order={ "none", "aboveRight", "aboveLeft", "topRight", "topLeft" },
              getValue=function() return SValSupported("absorbBarPosition", "none") end,
              setValue=function(v) SSetSupported("absorbBarPosition", v); EllesmereUI:RefreshPage() end },
            { type="slider", text="Bar Height", min=1, max=20, step=1,
              disabled=function() return SValSupported("absorbBarPosition", "none") == "none" end,
              disabledTooltip="Absorb Bar",
              getValue=function() return SValSupported("absorbBarHeight", 4) end,
              setValue=function(v) SSetSupported("absorbBarHeight", v) end });  y = y - h
        SApplySupport(absorbBarRow._leftRegion, "absorbBarPosition")
        SApplySupport(absorbBarRow._rightRegion, "absorbBarHeight")
        do
            local rgn = absorbBarRow._rightRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, absorbBarRow:GetFrameLevel() + 3,
                function()
                    local c = SGetSupported("absorbBarColor")
                    if c then return c.r, c.g, c.b, c.a or 1 end
                    return 1, 1, 1, 1
                end,
                function(r, g, b, a)
                    UNIT_DB_MAP[selectedUnit]().absorbBarColor = { r=r, g=g, b=b, a=a }
                    ReloadAndUpdate(); UpdatePreview()
                end, true, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
            local function UpdateAbsorbBarSwatchVis()
                swatch:SetAlpha(SValSupported("absorbBarPosition", "none") == "none" and 0.3 or 1)
            end
            RegisterWidgetRefresh(UpdateAbsorbBarSwatchVis)
            UpdateAbsorbBarSwatchVis()
        end

        -- Row 4: Heal Absorb Bar (position dropdown) | Bar Height (+ alpha swatch)
        local healAbsorbBarRow
        healAbsorbBarRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Heal Absorb Bar",
              values={ none="None", belowAbsorb="Below Absorb Bar", aboveRight="Above Frame Right", aboveLeft="Above Frame Left", topRight="Top Right", topLeft="Top Left" },
              order={ "none", "belowAbsorb", "aboveRight", "aboveLeft", "topRight", "topLeft" },
              getValue=function() return SValSupported("healAbsorbBarPosition", "none") end,
              setValue=function(v) SSetSupported("healAbsorbBarPosition", v); EllesmereUI:RefreshPage() end },
            { type="slider", text="Bar Height", min=1, max=20, step=1,
              disabled=function() return SValSupported("healAbsorbBarPosition", "none") == "none" end,
              disabledTooltip="Heal Absorb Bar",
              getValue=function() return SValSupported("healAbsorbBarHeight", 4) end,
              setValue=function(v) SSetSupported("healAbsorbBarHeight", v) end });  y = y - h
        SApplySupport(healAbsorbBarRow._leftRegion, "healAbsorbBarPosition")
        SApplySupport(healAbsorbBarRow._rightRegion, "healAbsorbBarHeight")
        do
            local rgn = healAbsorbBarRow._rightRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, healAbsorbBarRow:GetFrameLevel() + 3,
                function()
                    local c = SGetSupported("healAbsorbBarColor")
                    if c then return c.r, c.g, c.b, c.a or 1 end
                    return 200/255, 29/255, 29/255, 1
                end,
                function(r, g, b, a)
                    UNIT_DB_MAP[selectedUnit]().healAbsorbBarColor = { r=r, g=g, b=b, a=a }
                    ReloadAndUpdate(); UpdatePreview()
                end, true, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
            local function UpdateHealAbsorbBarSwatchVis()
                swatch:SetAlpha(SValSupported("healAbsorbBarPosition", "none") == "none" and 0.3 or 1)
            end
            RegisterWidgetRefresh(UpdateHealAbsorbBarSwatchVis)
            UpdateHealAbsorbBarSwatchVis()
        end

        _, h = W:Spacer(parent, y, 20); y = y - h
        end -- _supportsAbsorbs

        local sharedAddHeader
        -------------------------------------------------------------------
        --  EXTRAS
        -------------------------------------------------------------------
        sharedAddHeader, h = W:SectionHeader(parent, "EXTRAS", y); y = y - h

        -- Row 1: Combat Indicator (absorb settings live in the ABSORBS section above)
        -- Declared outside the gate: the click-mapping table at the bottom of
        -- this function references it (a block-local would be nil there).
        local sharedAddRow1
        local _showAbsorbsCombat = (selectedUnit == "player" or selectedUnit == "target" or selectedUnit == "focus")
        if _showAbsorbsCombat then
        local COMBAT_MEDIA_P = "Interface\\AddOns\\EllesmereUI\\media\\combat\\"
        local combatIndValues = {
            ["none"]="None", ["standard"]="Standard", ["class"]="Class Theme",
            _menuOpts = { itemHeight = 32, icon = function(key)
                if key == "none" then return nil end
                if key == "class" then
                    local _, ct = UnitClass("player")
                    if not ct then return nil end
                    local coords = CLASS_FULL_COORDS[ct]
                    if not coords then return nil end
                    return COMBAT_MEDIA_P .. "combat-indicator-class-custom.png", coords[1], coords[2], coords[3], coords[4]
                elseif key == "standard" then
                    return COMBAT_MEDIA_P .. "combat-indicator-custom.png", 0, 1, 0, 1
                else
                    -- New full-colour combat icons (combat0..combat5), shown as-is.
                    return COMBAT_MEDIA_P .. key .. ".tga", 0, 1, 0, 1
                end
            end },
        }
        local combatIndOrder = { "none", "standard", "class" }
        -- combat0..2 (Arcade/Dungeoneer/Classic) are shown as-is (non-colorable);
        -- combat3..5 (Cross/Circle/Square) are colorable like Standard/Class Theme.
        local _combatNames = { [0] = "Arcade", [1] = "Dungeoneer", [2] = "Classic", [3] = "Cross", [4] = "Circle", [5] = "Square" }
        for _i = 0, 5 do
            combatIndValues["combat" .. _i] = _combatNames[_i]
            combatIndOrder[#combatIndOrder + 1] = "combat" .. _i
        end
        -- Enemy Colors helper: custom reaction colors for non-player units.
        -- Global (one set shared by all frames); empty entries fall back to
        -- Blizzard defaults. Consumed by the Enemy Colors multiSwatch in slot 2.
        local function enemySwatch(key, defIdx, dr, dg, dbb, tip)
            return {
                tooltip = tip,
                getValue = function()
                    local ec = db.profile.enemyColors or {}
                    local c = ec[key]
                    if c then return c.r, c.g, c.b end
                    local f = defIdx and FACTION_BAR_COLORS[defIdx]
                    if f then return f.r, f.g, f.b end
                    return dr, dg, dbb
                end,
                setValue = function(r, g, b)
                    db.profile.enemyColors = db.profile.enemyColors or {}
                    db.profile.enemyColors[key] = { r = r, g = g, b = b }
                    if ns.ApplyEnemyColors then ns.ApplyEnemyColors() end
                end,
            }
        end
        sharedAddRow1, h = W:DualRow(parent, y,
            { type="dropdown", text="Combat Indicator", values=combatIndValues, order=combatIndOrder,
              -- Target ships disabled ("none"): opt-in, no change for existing users.
              getValue=function() return SValSupported("combatIndicatorStyle", selectedUnit == "player" and "class" or "none") end,
              setValue=function(v) SSetSupported("combatIndicatorStyle", v); ReloadAndUpdate(); UpdatePreview() end },
            { type = "multiSwatch", text = "Enemy Colors",
              swatches = {
                  enemySwatch("hostile",  2,   0.78, 0.25, 0.25, "Hostile"),
                  enemySwatch("neutral",  4,   0.85, 0.77, 0.36, "Neutral"),
                  enemySwatch("friendly", 5,   0.29, 0.68, 0.30, "Friendly NPC"),
                  enemySwatch("tapped",   nil, 0.6,  0.6,  0.6,  "Tapped"),
              } });  y = y - h
        SApplySupport(sharedAddRow1._leftRegion, "combatIndicatorStyle",
            "The Combat Indicator is not available for the Focus frame.")
        -- Sync icon: Combat Indicator (player + target only -- focus has none)
        if SVisible("combatIndicatorStyle") then
            local rgn = sharedAddRow1._leftRegion
            local ciSyncUnits = { "player", "target" }
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Combat Indicator Style to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().combatIndicatorStyle or "class"
                    for _, key in ipairs(ciSyncUnits) do UNIT_DB_MAP[key]().combatIndicatorStyle = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().combatIndicatorStyle or "class"
                    for _, key in ipairs(ciSyncUnits) do
                        if (UNIT_DB_MAP[key]().combatIndicatorStyle or "class") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = ciSyncUnits,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().combatIndicatorStyle or "class"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().combatIndicatorStyle = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Eyeball toggle + cog + swatch on combat indicator dropdown
        -- (player + target only -- the focus row is dimmed with a tooltip)
        if SVisible("combatIndicatorStyle") then
            local ciRgn = sharedAddRow1._leftRegion
            local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
            local eyeBtn = CreateFrame("Button", nil, ciRgn)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetPoint("RIGHT", ciRgn._lastInline or ciRgn._control, "LEFT", -8, 0)
            eyeBtn:SetFrameLevel(ciRgn:GetFrameLevel() + 5)
            eyeBtn:SetAlpha(0.4)
            ciRgn._lastInline = eyeBtn
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function RefreshCombatEye()
                eyeTex:SetTexture(showCombatIndicatorPreview and EYE_INVISIBLE or EYE_VISIBLE)
            end
            RefreshCombatEye()
            eyeBtn:SetScript("OnClick", function()
                showCombatIndicatorPreview = not showCombatIndicatorPreview
                RefreshCombatEye()
                UpdatePreview()
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, showCombatIndicatorPreview and "Hide combat indicator preview" or "Show combat indicator preview")
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                self:SetAlpha(0.4)
                EllesmereUI.HideWidgetTooltip()
            end)

            -- Cog popup for combat indicator settings
            -- "healthbar" is the long-standing stored value for centered-on-health-bar,
            -- shown as "Center". "center" (briefly stored by 8.4.9-era builds) maps to it.
            local combatPosValues = { ["topleft"]="Top Left", ["topright"]="Top Right", ["healthbar"]="Center", ["bottomleft"]="Bottom Left", ["bottomright"]="Bottom Right", ["textbar"]="Text Bar", ["portrait"]="Portrait" }
            local combatPosOrder = { "topleft", "topright", "healthbar", "bottomleft", "bottomright", "textbar", "portrait" }

            local _, combatCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Combat Indicator Settings",
                rows = {
                    { type="toggle", label="Class Colored",
                      -- All custom combat icons (Arcade/Dungeoneer/Classic/Cross/Circle/
                      -- Square = combat0..5) are shown as-is, so class coloring doesn't
                      -- apply to them.
                      disabled=function()
                          local st = SValSupported("combatIndicatorStyle", "class")
                          return st:find("^combat%d") and true or false
                      end,
                      disabledTooltip="Not available for this combat indicator style.", rawTooltip=true,
                      get=function() return SValSupported("combatIndicatorColor", "custom") == "classcolor" end,
                      set=function(v) SSetSupported("combatIndicatorColor", v and "classcolor" or "custom"); ReloadAndUpdate(); UpdatePreview() end },
                    { type="dropdown", label="Position", values=combatPosValues, order=combatPosOrder,
                      get=function()
                          local pos = SValSupported("combatIndicatorPosition", "healthbar")
                          if pos == "center" then pos = "healthbar" end
                          return combatPosValues[pos] and pos or "healthbar"
                      end,
                      set=function(v) SSetSupported("combatIndicatorPosition", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="slider", label="Size", min=8, max=64, step=1,
                      get=function() return SValSupported("combatIndicatorSize", 22) end,
                      set=function(v) SSetSupported("combatIndicatorSize", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="slider", label="X Offset", min=-200, max=200, step=1,
                      get=function() return SValSupported("combatIndicatorX", 0) end,
                      set=function(v) SSetSupported("combatIndicatorX", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-200, max=200, step=1,
                      get=function() return SValSupported("combatIndicatorY", 0) end,
                      set=function(v) SSetSupported("combatIndicatorY", v); ReloadAndUpdate(); UpdatePreview() end },
                },
            })
            local combatCogShow = combatCogShowRaw
            MakeCogBtn(ciRgn, combatCogShow)

            -- Inline color swatch for custom color
            local combatSwatch = EllesmereUI.BuildColorSwatch(ciRgn, ciRgn:GetFrameLevel() + 5,
                function()
                    local cc = SGetSupported("combatIndicatorCustomColor")
                    cc = cc or { r=1, g=1, b=1 }
                    return cc.r, cc.g, cc.b, 1
                end,
                function(r, g, b)
                    UNIT_DB_MAP[selectedUnit]().combatIndicatorCustomColor = { r=r, g=g, b=b }
                    ReloadAndUpdate(); UpdatePreview()
                end, false, 20)
            combatSwatch:SetPoint("RIGHT", ciRgn._lastInline or ciRgn._control, "LEFT", -12, 0)
            ciRgn._lastInline = combatSwatch

            local function UpdateSwatchVisibility()
                local colorMode = SValSupported("combatIndicatorColor", "custom")
                local style = SValSupported("combatIndicatorStyle", "class")
                -- All custom combat icons (combat0..5) are shown as-is, so the custom-
                -- color swatch doesn't apply to them.
                local isRawIcon = style:find("^combat%d") and true or false
                if colorMode == "custom" and style ~= "none" and not isRawIcon then
                    combatSwatch:Show()
                else
                    combatSwatch:Hide()
                end
            end
            UpdateSwatchVisibility()
            RegisterWidgetRefresh(UpdateSwatchVisibility)
        end
        end -- _showAbsorbsCombat

        -- Row 4: Raid Marker toggle | Icon Size slider + inline directions cog (X/Y)
        local function raidMarkerOff()
            return SValSupported("raidMarkerEnabled", false) == false
        end
        local sharedAddRow4
        sharedAddRow4, h = W:DualRow(parent, y,
            { type="toggle", text="Raid Marker",
              getValue=function() return SValSupported("raidMarkerEnabled", false) end,
              setValue=function(v)
                  SSetSupported("raidMarkerEnabled", v)
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Marker Size", min=12, max=64, step=1,
              disabled=raidMarkerOff, disabledTooltip="Raid Marker",
              getValue=function() return SValSupported("raidMarkerSize", 28) end,
              setValue=function(v) SSetSupported("raidMarkerSize", v) end });  y = y - h
        do
            local rgn = sharedAddRow4._rightRegion
            local rmPosValues = { ["left"]="Left", ["center"]="Center", ["right"]="Right" }
            local rmPosOrder  = { "left", "center", "right" }
            local _, rmCogShow = EllesmereUI.BuildCogPopup({
                title = "Raid Marker Settings",
                rows = {
                    { type="dropdown", label="Position", values=rmPosValues, order=rmPosOrder,
                      get=function() return SValSupported("raidMarkerAlign", "right") end,
                      set=function(v) SSetSupported("raidMarkerAlign", v) end },
                    { type="slider", label="X Offset", min=-200, max=200, step=1,
                      get=function() return SValSupported("raidMarkerX", 0) end,
                      set=function(v) SSetSupported("raidMarkerX", v) end },
                    { type="slider", label="Y Offset", min=-200, max=200, step=1,
                      get=function() return SValSupported("raidMarkerY", 0) end,
                      set=function(v) SSetSupported("raidMarkerY", v) end },
                },
            })
            local rmCogBtn = MakeCogBtn(rgn, rmCogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local rmCogTex = select(1, rmCogBtn:GetRegions())
            local function UpdateRmCogState()
                local off = raidMarkerOff()
                rmCogBtn:SetAlpha(off and 0.15 or 0.4)
            end
            rmCogBtn:SetScript("OnEnter", function(self)
                if raidMarkerOff() then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Raid Marker"))
                else
                    self:SetAlpha(0.7)
                end
            end)
            rmCogBtn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                UpdateRmCogState()
            end)
            rmCogBtn:SetScript("OnClick", function(self)
                if raidMarkerOff() then return end
                rmCogShow(self)
            end)
            EllesmereUI.RegisterWidgetRefresh(UpdateRmCogState)
            UpdateRmCogState()
        end
        -- Sync icons: Raid Marker (left) and Marker Size (right)
        do
            local rgn = sharedAddRow4._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Raid Marker to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().raidMarkerEnabled
                    if v == nil then v = false end
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().raidMarkerEnabled = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().raidMarkerEnabled
                    if v == nil then v = false end
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local ov = UNIT_DB_MAP[key]().raidMarkerEnabled
                        if ov == nil then ov = false end
                        if ov ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().raidMarkerEnabled
                        if v == nil then v = false end
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().raidMarkerEnabled = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = sharedAddRow4._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Marker Size to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().raidMarkerSize or 28
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().raidMarkerSize = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().raidMarkerSize or 28
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().raidMarkerSize or 28) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().raidMarkerSize or 28
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().raidMarkerSize = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 5: Leader Indicator toggle | Leader Icon Size slider + inline directions cog (X/Y)
        -- Visible for player and target.
        local sharedAddRow5
        local function leaderIndOff()
            return SValSupported("leaderIndicatorEnabled", true) == false
        end
        local function leaderIndSupported()
            return selectedUnit == "player" or selectedUnit == "target"
        end
        if leaderIndSupported() then
            local leaderSyncUnits = { "player", "target" }
            sharedAddRow5, h = W:DualRow(parent, y,
                { type="toggle", text="Leader Indicator",
                  getValue=function() return SValSupported("leaderIndicatorEnabled", true) end,
                  setValue=function(v)
                      SSetSupported("leaderIndicatorEnabled", v)
                      EllesmereUI:RefreshPage()
                  end },
                { type="slider", text="Leader Icon Size", min=8, max=48, step=1,
                  disabled=leaderIndOff, disabledTooltip="Leader Indicator",
                  getValue=function() return SValSupported("leaderIndicatorSize", 16) end,
                  setValue=function(v) SSetSupported("leaderIndicatorSize", v) end });  y = y - h
            SApplySupport(sharedAddRow5._leftRegion, "leaderIndicatorEnabled")
            SApplySupport(sharedAddRow5._rightRegion, "leaderIndicatorSize")
            do
                local rgn = sharedAddRow5._rightRegion
                local leaderPosValues = { ["topleft"]="Top Left", ["topright"]="Top Right", ["bottomleft"]="Bottom Left", ["bottomright"]="Bottom Right", ["portrait"]="Portrait" }
                local leaderPosOrder = { "topleft", "topright", "bottomleft", "bottomright", "portrait" }
                local _, leaderCogShow = EllesmereUI.BuildCogPopup({
                    title = "Leader Indicator Settings",
                    rows = {
                        { type="dropdown", label="Position", values=leaderPosValues, order=leaderPosOrder,
                          get=function() return SValSupported("leaderIndicatorPosition", "topleft") end,
                          set=function(v) SSetSupported("leaderIndicatorPosition", v) end },
                        { type="slider", label="X Offset", min=-200, max=200, step=1,
                          get=function() return SValSupported("leaderIndicatorX", 0) end,
                          set=function(v) SSetSupported("leaderIndicatorX", v) end },
                        { type="slider", label="Y Offset", min=-200, max=200, step=1,
                          get=function() return SValSupported("leaderIndicatorY", 0) end,
                          set=function(v) SSetSupported("leaderIndicatorY", v) end },
                    },
                })
                local leaderCogBtn = MakeCogBtn(rgn, leaderCogShow)
                local function UpdateLeaderCogState()
                    local off = leaderIndOff()
                    leaderCogBtn:SetAlpha(off and 0.15 or 0.4)
                end
                leaderCogBtn:SetScript("OnEnter", function(self)
                    if leaderIndOff() then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Leader Indicator"))
                    else
                        self:SetAlpha(0.7)
                    end
                end)
                leaderCogBtn:SetScript("OnLeave", function(self)
                    EllesmereUI.HideWidgetTooltip()
                    UpdateLeaderCogState()
                end)
                leaderCogBtn:SetScript("OnClick", function(self)
                    if leaderIndOff() then return end
                    leaderCogShow(self)
                end)
                EllesmereUI.RegisterWidgetRefresh(UpdateLeaderCogState)
                UpdateLeaderCogState()
            end
            local function BuildLeaderSync(rgn, key, default, tooltip)
                local function GetValue(unit)
                    local v = UNIT_DB_MAP[unit]()[key]
                    if v == nil then return default end
                    return v
                end
                EllesmereUI.BuildSyncIcon({
                    region = rgn,
                    tooltip = tooltip,
                    onClick = function()
                        local v = GetValue(selectedUnit)
                        for _, unit in ipairs(leaderSyncUnits) do UNIT_DB_MAP[unit]()[key] = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local v = GetValue(selectedUnit)
                        for _, unit in ipairs(leaderSyncUnits) do
                            if GetValue(unit) ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys = leaderSyncUnits,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return selectedUnit end,
                        onApply = function(checkedKeys)
                            local v = GetValue(selectedUnit)
                            for _, unit in ipairs(checkedKeys) do UNIT_DB_MAP[unit]()[key] = v end
                            ReloadAndUpdate(); EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end
            BuildLeaderSync(sharedAddRow5._leftRegion, "leaderIndicatorEnabled", true,
                "Apply Leader Indicator to all Frames")
            BuildLeaderSync(sharedAddRow5._rightRegion, "leaderIndicatorSize", 16,
                "Apply Leader Icon Size to all Frames")
        end

        -------------------------------------------------------------------
        --  Return click mapping targets + total height
        -------------------------------------------------------------------
        parent._sharedClickTargets = {
            healthBar    = { section = sharedBarsHeader,     target = sharedSizeRow },
            absorbs      = { section = sharedAbsorbsHeader,  target = absorbRow, slotSide = "left" },
            healAbsorb   = { section = sharedAbsorbsHeader,  target = healAbsorbRow, slotSide = "left" },
            powerBar     = { section = sharedPowerHeader,    target = sharedPowerRow1, slotSide = "left" },
            powerBarText = { section = sharedPowerHeader,    target = sharedPowerRow2, slotSide = "left" },
            portrait     = { section = sharedPortraitHeader, target = sharedPortraitModeRow, slotSide = "left" },
            nameText     = { section = sharedBarsHeader,     target = sharedTextRow, slotSide = "left" },
            healthText   = { section = sharedBarsHeader,     target = sharedTextRow, slotSide = "right" },
            centerText   = { section = sharedBarsHeader,     target = sharedCenterTextRow, slotSide = "left" },
            classResource= { section = sharedClassResHeader, target = sharedClassResRow, slotSide = "left" },
            btbBar       = { section = sharedBtbHeader,      target = sharedBtbToggleRow, slotSide = "left" },
            btbLeftText  = { section = sharedBtbHeader,      target = sharedBtbTextRow, slotSide = "left" },
            btbRightText = { section = sharedBtbHeader,      target = sharedBtbTextRow, slotSide = "right" },
            btbCenterText= { section = sharedBtbHeader,      target = sharedBtbCenterRow, slotSide = "left" },
            btbClassIcon = { section = sharedBtbHeader,      target = sharedBtbCenterRow, slotSide = "right" },
            combatIndicator = { section = sharedAddHeader, target = sharedAddRow1, slotSide = "left" },
            buffIcon     = { section = sharedBuffDebuffHeader, target = sharedAddRow2, slotSide = "left" },
            debuffIcon   = { section = sharedBuffDebuffHeader, target = sharedAddRow3, slotSide = "left" },
            raidMarker   = { section = sharedAddHeader,      target = sharedAddRow4, slotSide = "left" },
            leaderIndicator = { section = sharedAddHeader,   target = sharedAddRow5, slotSide = "left" },
            castBar      = { section = sharedCastHeader,     target = sharedCastRow1 },
            castIcon     = { section = sharedCastHeader,     target = castRow2,      slotSide = "left" },
            castName     = { section = sharedCastHeader,     target = castTextRow,   slotSide = "left" },
            castTime     = { section = sharedCastHeader,     target = castTextRow,   slotSide = "right" },
            castTarget   = { section = sharedCastHeader,     target = castTargetRow, slotSide = "left" },
        }

        return y
    end  -- BuildSharedSettings

    ---------------------------------------------------------------------------
    --  Main Frames page  (dropdown selector + shared/mini settings)
    ---------------------------------------------------------------------------
    local _displayHeaderBuilder
    local displayHeaderFixedH = 0
    local BuildFoTToTOptions, BuildPetOptions, BuildBossOptions

    local function BuildFrameDisplayPage(pageName, parent, yOffset)
        -- Consume any pending unit selection from Element Options navigation
        if EllesmereUI._consumePendingUnitSelect then EllesmereUI._consumePendingUnitSelect() end

        -- Tag every option registered while building this page with the
        -- currently-selected unit, so a global-search jump to a unit-specific
        -- setting can restore this exact unit selection first via
        -- EllesmereUI._setUnitFrameUnit -- see EUI_CooldownManager_Options.lua's
        -- matching EllesmereUI._buildingSelector comment for the full reasoning.
        EllesmereUI._buildingSelector = { setter = EllesmereUI._setUnitFrameUnit, key = selectedUnit }

        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        activePreview = nil

        -------------------------------------------------------------------
        --  CONTENT HEADER  (dropdown + preview)
        -------------------------------------------------------------------
        _displayHeaderBuilder = function(hdr, hdrW)
            local DD_H = 34
            local fy = -20

            -- Centered dropdown (matches Action Bars Single Bar Edit)
            local ddW = 350
            local ddBtn, ddLbl = EllesmereUI.BuildDropdownControl(
                hdr, ddW, hdr:GetFrameLevel() + 5,
                unitLabels, unitOrder,
                function() return selectedUnit end,
                function(v)
                    -- Preserve the user's scroll position across the unit swap
                    -- (captured BEFORE the rebuild, since SetContentHeader's
                    -- relayout can clobber the live scroll value). The settings
                    -- list sits below the fixed content header, so the same
                    -- offset lands on the same section for any unit.
                    local savedScroll = EllesmereUI.GetContentScroll and EllesmereUI.GetContentScroll() or 0
                    selectedUnit = v
                    EllesmereUI:InvalidateContentHeaderCache()
                    EllesmereUI:SetContentHeader(_displayHeaderBuilder)
                    EllesmereUI:RefreshPage(true)
                    EllesmereUI.SmoothScrollTo(savedScroll)
                    -- The preview's Update runs DURING the rebuild above, before the
                    -- content header's layout has settled, so its sizing/header-height
                    -- pass lands on stale geometry (preview spacing wrong, debuff row
                    -- missing until a slider nudge). Initial page load gets a settled
                    -- pass via RegisterOnShow; a unit switch (panel already open) does
                    -- not -- so re-run the preview next frame, once layout has settled.
                    C_Timer.After(0, UpdatePreview)
                end
            )
            PP.Point(ddBtn, "TOP", hdr, "TOP", 0, fy)
            ddBtn:SetHeight(DD_H)
            fy = fy - DD_H - 20

            local side = unitSide[selectedUnit] or "left"
            local preview = BuildUnitPreview(hdr, selectedUnit, side)
            activePreview = preview
            local previewScale = preview._previewScale or 1
            local initBuffTopPad = preview._buffTopPad or 0
            preview._headerDropdownOY = math.abs(fy)
            preview:ClearAllPoints()
            PP.Point(preview, "TOP", hdr, "TOP", 0, (fy - initBuffTopPad) / previewScale)
            preview._lastOY = (fy - initBuffTopPad) / previewScale
            preview:Update()
            local previewH = preview:GetHeight() * preview:GetScale()
            local buffExtra = preview._buffExtra or 0
            local detTopExtra = preview._detTopExtra or 0
            fy = fy - previewH - buffExtra - detTopExtra - 20

            displayHeaderFixedH = 20 + DD_H + 20 + 20
            if preview then preview._headerFixedH = displayHeaderFixedH end

            -- Hint text
            if _ufPreviewHintFS_display and not _ufPreviewHintFS_display:GetParent() then
                _ufPreviewHintFS_display = nil
            end
            local hintH = 0
            if not IsPreviewHintDismissed() then
                if not _ufPreviewHintFS_display then
                    _ufPreviewHintFS_display = EllesmereUI.MakeFont(preview or hdr, 11, nil, 1, 1, 1)
                    _ufPreviewHintFS_display:SetAlpha(0.45)
                    _ufPreviewHintFS_display:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
                end
                _ufPreviewHintFS_display:SetParent(preview or hdr)
                _ufPreviewHintFS_display:ClearAllPoints()
                _ufPreviewHintFS_display:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 17)
                _ufPreviewHintFS_display:SetAlpha(0.45)
                _ufPreviewHintFS_display:Show()
                hintH = 29
            elseif _ufPreviewHintFS_display then
                _ufPreviewHintFS_display:Hide()
            end

            _displayHeaderBaseH = math.abs(fy)
            return _displayHeaderBaseH + hintH
        end
        EllesmereUI:SetContentHeader(_displayHeaderBuilder)

        parent._showRowDivider = true

        -------------------------------------------------------------------
        --  Route to shared settings or mini builders
        -------------------------------------------------------------------
        if selectedUnit == "player" or selectedUnit == "target" or selectedUnit == "focus" then
            y = BuildSharedSettings(parent, y)
        elseif selectedUnit == "targettarget" then
            y = -BuildFoTToTOptions(W, parent, y, db.profile.targettarget, "targettarget")
        elseif selectedUnit == "focustarget" then
            y = -BuildFoTToTOptions(W, parent, y, db.profile.focustarget, "focustarget")
        elseif selectedUnit == "pet" then
            y = -BuildPetOptions(W, parent, y)
        elseif selectedUnit == "boss" then
            y = -BuildBossOptions(W, parent, y)
        end

        -------------------------------------------------------------------
        --  CLICK NAVIGATION
        -------------------------------------------------------------------
        local glowFrame
        local function PlaySettingGlow(targetFrame)
            if not targetFrame then return end
            if not glowFrame then
                glowFrame = CreateFrame("Frame")
                local c = EllesmereUI.ELLESMERE_GREEN
                local function MkEdge()
                    local t = glowFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                    t:SetColorTexture(c.r, c.g, c.b, 1)
                    return t
                end
                glowFrame._top = MkEdge()
                glowFrame._bot = MkEdge()
                glowFrame._lft = MkEdge()
                glowFrame._rgt = MkEdge()
                glowFrame._top:SetHeight(2)
                glowFrame._top:SetPoint("TOPLEFT"); glowFrame._top:SetPoint("TOPRIGHT")
                glowFrame._bot:SetHeight(2)
                glowFrame._bot:SetPoint("BOTTOMLEFT"); glowFrame._bot:SetPoint("BOTTOMRIGHT")
                glowFrame._lft:SetWidth(2)
                glowFrame._lft:SetPoint("TOPLEFT", glowFrame._top, "BOTTOMLEFT")
                glowFrame._lft:SetPoint("BOTTOMLEFT", glowFrame._bot, "TOPLEFT")
                glowFrame._rgt:SetWidth(2)
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

        local function NavigateToSetting(key)
            local targets = parent._sharedClickTargets or parent._ufClickTargets
            if not targets then return end
            local m = targets[key]
            -- A target may be a resolver function (e.g. boss buff/debuff icons,
            -- which point to Simple Display or Location depending on the mode).
            if type(m) == "function" then m = m() end
            if not m or not m.section or not m.target then return end

            -- Dismiss hint
            if not IsPreviewHintDismissed() and _ufPreviewHintFS_display and _ufPreviewHintFS_display:IsShown() then
                EllesmereUIDB = EllesmereUIDB or {}
                EllesmereUIDB.previewHintDismissed = true
                local hint = _ufPreviewHintFS_display
                local _, anchorTo, _, _, startY = hint:GetPoint(1)
                startY = startY or 17
                anchorTo = anchorTo or hint:GetParent()
                local startHeaderH = _displayHeaderBaseH + 29
                local targetHeaderH = _displayHeaderBaseH
                local steps = 0
                local ticker
                ticker = C_Timer.NewTicker(0.016, function()
                    steps = steps + 1
                    local progress = steps * 0.016 / 0.3
                    if progress >= 1 then
                        hint:Hide(); ticker:Cancel()
                        if targetHeaderH > 0 then EllesmereUI:SetContentHeaderHeightSilent(targetHeaderH) end
                        return
                    end
                    hint:SetAlpha(0.45 * (1 - progress))
                    hint:ClearAllPoints()
                    hint:SetPoint("BOTTOM", anchorTo, "BOTTOM", 0, startY + progress * 12)
                    local hh = startHeaderH - 29 * progress
                    if hh > 0 then EllesmereUI:SetContentHeaderHeightSilent(hh) end
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

        -- Hit overlay factory
        local function CreateHitOverlay(element, mappingKey, isText, frameLevelOverride, opts)
            local anchor = isText and element:GetParent() or element
            if not anchor.CreateTexture then anchor = anchor:GetParent() end
            local btn = CreateFrame("Button", nil, anchor)
            if isText then
                local function ResizeToText()
                    local ok, tw, th = pcall(function()
                        local w = element:GetStringWidth() or 0
                        local hh = element:GetStringHeight() or 0
                        if w < 4 then w = 4 end
                        if hh < 4 then hh = 4 end
                        return w, hh
                    end)
                    if not ok then tw = 40; th = 12 end
                    btn:SetSize(tw + 4, th + 4)
                end
                ResizeToText()
                local justify = element:GetJustifyH()
                if justify == "RIGHT" then btn:SetPoint("RIGHT", element, "RIGHT", 2, 0)
                elseif justify == "CENTER" then btn:SetPoint("CENTER", element, "CENTER", 0, 0)
                else btn:SetPoint("LEFT", element, "LEFT", -2, 0) end
                btn:SetScript("OnShow", function() ResizeToText() end)
                btn._resizeToText = ResizeToText
            else
                btn:SetAllPoints(opts and opts.hlAnchor or element)
            end
            btn:SetFrameLevel(frameLevelOverride or (anchor:GetFrameLevel() + 20))
            btn:RegisterForClicks("LeftButtonDown")
            local c = EllesmereUI.ELLESMERE_GREEN
            local hlTarget = (opts and opts.hlBehindText) and element or (opts and opts.hlAnchor) or btn
            local brd = EllesmereUI.PP.CreateBorder(hlTarget, c.r, c.g, c.b, 1, 2, "OVERLAY", 7)
            brd:Hide()
            btn:SetScript("OnEnter", function() brd:Show() end)
            btn:SetScript("OnLeave", function() brd:Hide() end)
            btn:SetScript("OnMouseDown", function() NavigateToSetting(mappingKey) end)
            return btn
        end

        -- Create hit overlays on preview elements
        local textOverlays = {}
        if activePreview then
            local pv = activePreview
            local baseLevel = (pv._health and pv._health:GetFrameLevel() or 20) + 15
            local textLevel = baseLevel + 10
            if pv._health then CreateHitOverlay(pv._health, "healthBar", false, baseLevel) end
            -- Absorb segments: hit area follows each absorb bar's FILL texture
            -- (the bar frame spans the whole health width), sitting above the
            -- health overlay so the strip routes to the Absorbs section. No
            -- :IsShown() guard -- the overlay is a child of the bar and
            -- SetAllPoints its fill, so it auto-hides/shows WITH the bar when
            -- the heal-absorb eyeball flips which bar is visible. Both bars get
            -- an overlay so whichever is shown is click-navigable.
            if pv._absorbBar then
                local absFill = pv._absorbBar:GetStatusBarTexture()
                if absFill then CreateHitOverlay(absFill, "absorbs", false, baseLevel + 5) end
            end
            if pv._healAbsorbBar then
                local haFill = pv._healAbsorbBar:GetStatusBarTexture()
                if haFill then CreateHitOverlay(haFill, "healAbsorb", false, baseLevel + 5) end
            end
            if pv._power then CreateHitOverlay(pv._power, "powerBar", false, baseLevel) end
            if pv._portraitFrame and pv._portraitFrame:IsShown() then CreateHitOverlay(pv._portraitFrame, "portrait", false, baseLevel) end
            if pv._castbar then
                local castLevel = pv._castbar:GetFrameLevel() + 20
                CreateHitOverlay(pv._castbar, "castBar", false, castLevel)
                if pv._castIconFrame then CreateHitOverlay(pv._castIconFrame, "castIcon", false, castLevel) end
                if pv._castNameFS then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._castNameFS, "castName", true, castLevel + 5) end
                if pv._castTimeFS and pv._castTimeFS:IsShown() then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._castTimeFS, "castTime", true, castLevel + 5) end
                if pv._castTargetFS and pv._castTargetFS:IsShown() then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._castTargetFS, "castTarget", true, castLevel + 5) end
            end
            if pv._nameFS and pv._nameFS:IsShown() then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._nameFS, "nameText", true, textLevel) end
            if pv._hpFS and pv._hpFS:IsShown() then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._hpFS, "healthText", true, textLevel) end
            if pv._centerFS and pv._centerFS:IsShown() then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._centerFS, "centerText", true, textLevel) end
            if pv._ppFS and pv._ppFS:IsShown() then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._ppFS, "powerBarText", true, textLevel) end
            -- Create an overlay for EVERY buff/debuff frame, not just the ones
            -- shown right now. Each overlay is a child of its icon frame with
            -- SetAllPoints, so it hides/shows and re-anchors with the icon. The
            -- old ":IsShown()" guard tied clickability to the icon's visibility
            -- at header-build time -- enabling buffs or changing the debuff count
            -- afterwards (header is cached, not rebuilt) left the newly shown
            -- icons with no overlay, so they weren't clickable.
            if pv._buffIcons then
                for i = 1, #pv._buffIcons do
                    if pv._buffIcons[i] then CreateHitOverlay(pv._buffIcons[i], "buffIcon", false, baseLevel) end
                end
            end
            if pv._debuffIcons then
                for i = 1, #pv._debuffIcons do
                    if pv._debuffIcons[i] then CreateHitOverlay(pv._debuffIcons[i], "debuffIcon", false, baseLevel) end
                end
            end
            if pv._btbFrame then
                local btbLevel = pv._btbFrame:GetFrameLevel() + 20
                CreateHitOverlay(pv._btbFrame, "btbBar", false, btbLevel)
                local btbTextLevel = btbLevel + 5
                if pv._btbLeftFS then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._btbLeftFS, "btbLeftText", true, btbTextLevel) end
                if pv._btbRightFS then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._btbRightFS, "btbRightText", true, btbTextLevel) end
                if pv._btbCenterFS then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._btbCenterFS, "btbCenterText", true, btbTextLevel) end
                if pv._btbClassIcon then
                    local ciOv = CreateHitOverlay(pv._btbClassIcon, "btbClassIcon", false, btbTextLevel + 2)
                    pv._btbClassIconOv = ciOv
                    if not pv._btbClassIcon:IsShown() then ciOv:Hide() end
                end
            end
            if pv._cpPipContainer and pv._cpPipContainer:IsShown() then
                pv._cpPipOv = CreateHitOverlay(pv._cpPipContainer, "classResource", false, baseLevel + 10)
            end
            if pv._combatIndicator and pv._combatIndicator:IsShown() then CreateHitOverlay(pv._combatIndicator, "combatIndicator", false, baseLevel + 20) end
            pv._textOverlays = textOverlays
        end

        return abs(y)
    end

    ---------------------------------------------------------------------------
    --  Mini frame donor settings helper
    --  Returns the settings table from focus (if enabled) target player
    ---------------------------------------------------------------------------
    local function GetMiniDonorSettings()
        local ef = db.profile.enabledFrames
        if ef.focus ~= false and db.profile.focus then return db.profile.focus end
        if ef.target ~= false and db.profile.target then return db.profile.target end
        return db.profile.player
    end

    ---------------------------------------------------------------------------
    --  Shared mini frame settings builder
    ---------------------------------------------------------------------------
    local function BuildMiniTextAndSize(W, parent, y, settingsTable, unitKey, enableRow, afterSizeRow, opts)
        local _, h
        opts = opts or {}

        -- Local cog button helper (MakeCogBtn is scoped to BuildSharedSettings)
        local function MCogBtn(rgn, showFn, iconPath)
            local btn = CreateFrame("Button", nil, rgn)
            btn:SetSize(26, 26)
            btn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = btn
            btn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            btn:SetAlpha(0.4)
            local tex = btn:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints()
            tex:SetTexture(iconPath or EllesmereUI.COGS_ICON)
            btn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            btn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            btn:SetScript("OnClick", function(self) showFn(self) end)
            return btn
        end

        -- Shorthand accessors for this mini frame's settings
        local function MGet(key) return settingsTable[key] end
        local function MSet(key, val) settingsTable[key] = val; ReloadAndUpdate() end
        local function MVal(key, default)
            local v = settingsTable[key]
            if v ~= nil then return v end
            return default
        end

        -- DISPLAY
        local displayHeader
        displayHeader, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h

        -- Enable row (passed in from each builder)
        local enableRowFrame
        if enableRow then
            enableRowFrame, h = enableRow(W, parent, y)
            y = y - h
        end

        -- If this unit isn't on the EllesmereUI frame, skip the (inapplicable)
        -- settings below and show a short notice instead.
        if enableRow and ns.GetUnitFrameSource(unitKey) ~= "eui" then
            y = BuildInactiveNotice(parent, y, ns.GetUnitFrameSource(unitKey))
            return y, displayHeader, nil, nil, nil, enableRowFrame
        end

        -- Bar Texture override (new row, slot 1). Mini frames inherit the main
        -- frames' donor texture (focus > target > player) by default; picking a
        -- specific texture here overrides that for this frame only. Lands as the
        -- last DISPLAY row: Row 2 for ToT/Focus Target/Pet, Row 3 for Boss.
        do
            local mtVals, mtOrder = BuildBarTexDropdown()
            table.insert(mtOrder, 1, "inherit")
            mtVals["inherit"] = "Inherit (Main Frames)"
            -- Menu item preview background for "Inherit" shows the donor texture.
            local mo = mtVals._menuOpts
            if mo then
                local baseBg = mo.background
                mo.background = function(key)
                    if key == "inherit" then
                        local donor = GetMiniDonorSettings()
                        local dk = donor and donor.healthBarTexture
                        if dk == "inherit" then dk = nil end
                        dk = dk or db.profile.healthBarTexture
                        return dk and (ns.healthBarTextures or {})[dk] or nil
                    end
                    return baseBg and baseBg(key) or nil
                end
            end
            -- Boss frames get a "Hover Borders" control in the right slot (mirrors
            -- Raid Frames); the other mini frames leave that slot empty.
            local isBoss = (unitKey == "boss")
            local rightSlot
            if isBoss then
                rightSlot = { type="dropdown", text="Hover Borders",
                    values={ __placeholder = "All" }, order={ "__placeholder" },
                    getValue=function() return "__placeholder" end,
                    setValue=function() end }
            else
                -- ToT / Focus Target / Pet: per-frame Strata override. Same options
                -- as the main frames "Frame Strata" dropdown; overrides the global
                -- strata for THIS frame only. Inherits the global value until set
                -- (getter falls back to db.profile.frameStrata).
                local miniStrataValues = { BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium", HIGH = "High", DIALOG = "Dialog" }
                local miniStrataOrder = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }
                rightSlot = { type="dropdown", text="Strata",
                    tooltip="Overrides the Frame Strata set in the main frames for this frame only. Controls the order that overlapping frames display in; set higher to show above other frames.",
                    values = miniStrataValues, order = miniStrataOrder,
                    getValue=function() return settingsTable.frameStrata or db.profile.frameStrata or "MEDIUM" end,
                    setValue=function(v)
                        settingsTable.frameStrata = v
                        ReloadAndUpdate()
                    end }
            end
            local barTexRow
            barTexRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Bar Texture", values=mtVals, order=mtOrder,
                  getValue=function()
                      local v = settingsTable.healthBarTexture
                      if v == nil then return "inherit" end
                      return v
                  end,
                  setValue=function(v)
                      if v == "inherit" then
                          settingsTable.healthBarTexture = nil
                      else
                          settingsTable.healthBarTexture = v
                      end
                      ReloadAndUpdate()
                  end },
                rightSlot);  y = y - h

            -- Boss Hover Borders: checkbox dropdown (Hover Border / Target Border,
            -- both default off) with inline color swatches. Enabling one recolors
            -- the boss frame's existing border to that color (hover > target).
            if isBoss then
                local PP = EllesmereUI.PP
                local rightRgn = barTexRow._rightRegion
                if rightRgn._control then rightRgn._control:Hide() end
                local hbKeyMap = { hover = "bossHoverBorderEnabled", target = "bossTargetBorderEnabled" }
                local hbItems = {
                    { key = "hover",  label = "Hover Border" },
                    { key = "target", label = "Target Border" },
                }
                local UpdateHBSwatchVis  -- forward declare; assigned after swatches
                local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                    rightRgn, 170, rightRgn:GetFrameLevel() + 2,
                    hbItems,
                    function(k) return settingsTable[hbKeyMap[k]] and true or false end,
                    function(k, v)
                        settingsTable[hbKeyMap[k]] = v
                        ReloadAndUpdate()
                        if UpdateHBSwatchVis then UpdateHBSwatchVis() end
                    end)
                PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
                rightRgn._control = cbDD
                rightRgn._lastInline = nil

                -- Inline swatches: Hover (nearest the dropdown), then Target to its left.
                local lvl = barTexRow:GetFrameLevel() + 3
                local hoverSwatch, updHover = EllesmereUI.BuildColorSwatch(
                    rightRgn, lvl,
                    function()
                        local c = settingsTable.bossHoverBorderColor or { r = 1, g = 1, b = 1 }
                        return c.r, c.g, c.b, settingsTable.bossHoverBorderAlpha or 1
                    end,
                    function(r, g, b, a)
                        settingsTable.bossHoverBorderColor = { r=r, g=g, b=b }
                        settingsTable.bossHoverBorderAlpha = a
                        ReloadAndUpdate()
                    end, true, 20)
                hoverSwatch:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                rightRgn._lastInline = hoverSwatch
                hoverSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(hoverSwatch, "Hover") end)
                hoverSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                local targetSwatch, updTarget = EllesmereUI.BuildColorSwatch(
                    rightRgn, lvl,
                    function()
                        local c = settingsTable.bossTargetBorderColor or { r = 1, g = 1, b = 1 }
                        return c.r, c.g, c.b, settingsTable.bossTargetBorderAlpha or 1
                    end,
                    function(r, g, b, a)
                        settingsTable.bossTargetBorderColor = { r=r, g=g, b=b }
                        settingsTable.bossTargetBorderAlpha = a
                        ReloadAndUpdate()
                    end, true, 20)
                targetSwatch:SetPoint("RIGHT", rightRgn._lastInline, "LEFT", -8, 0)
                rightRgn._lastInline = targetSwatch
                targetSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(targetSwatch, "Target") end)
                targetSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                -- Gray a swatch when its border state is off (still clickable so the
                -- color can be pre-set), matching the Raid Frames Hover Borders row.
                UpdateHBSwatchVis = function()
                    hoverSwatch:SetAlpha(settingsTable.bossHoverBorderEnabled and 1 or 0.3)
                    targetSwatch:SetAlpha(settingsTable.bossTargetBorderEnabled and 1 or 0.3)
                end
                EllesmereUI.RegisterWidgetRefresh(function() updHover(); updTarget(); UpdateHBSwatchVis() end)
                UpdateHBSwatchVis()
            end
        end

        -- DISPLAY bottom row: per-frame Border Size override for ToT / Focus
        -- Target / Pet (the mini frames). Just the size slider, no color swatch --
        -- overrides ONLY the border size; color and texture still inherit from the
        -- main frames. borderSizeOverride nil = inherit the donor border size until
        -- the user sets it. Boss frames are NOT mini frames, so they are excluded.
        if unitKey ~= "boss" then
            _, h = W:DualRow(parent, y,
                { type="slider", text="Border Size", min=0, max=4, step=1,
                  tooltip="Overrides the border size from the main frames for this frame only. Border color and texture still follow the main frames.",
                  getValue=function()
                      local donor = GetMiniDonorSettings()
                      return settingsTable.borderSizeOverride or (donor and donor.borderSize) or 1
                  end,
                  setValue=function(v) settingsTable.borderSizeOverride = v; ReloadAndUpdate() end },
                { type="toggle", text="Show Highlight Border",
                  tooltip="Show the main frames' hover highlight border on this frame. Turn off so this frame never recolors on mouseover. No effect when Highlight is off in the main frames' Hover Borders.",
                  getValue=function() return settingsTable.showHighlightBorder ~= false end,
                  setValue=function(v) settingsTable.showHighlightBorder = v end });  y = y - h
        end

        -- Optional extra rows after enable (e.g. portrait, cast icon, indicators)
        if afterSizeRow then
            y = afterSizeRow(W, parent, y)
        end

        -- HEALTH BAR section
        local textHeader
        textHeader, h = W:SectionHeader(parent, "HEALTH BAR", y); y = y - h

        -- Row 1: Bar Height + Bar Width
        local sizeRow
        local mhDis, mhTip, mhRaw = EllesmereUI.MatchGuard(unitKey, "Height")
        local mwDis, mwTip, mwRaw = EllesmereUI.MatchGuard(unitKey, "Width")
        local rightSlot
        if opts.hideBarWidth then
            rightSlot = { type="label", text="" }
        else
            rightSlot = { type="slider", text="Bar Width", min=60, max=300, step=1,
                disabled=mwDis, disabledTooltip=mwTip, rawTooltip=mwRaw,
                getValue=function() return settingsTable.frameWidth end,
                setValue=function(v) settingsTable.frameWidth = v; ReloadAndUpdate() end }
        end
        sizeRow, h = W:DualRow(parent, y,
            { type="slider", text="Health Bar Height", min=10, max=100, step=1,
              disabled=mhDis, disabledTooltip=mhTip, rawTooltip=mhRaw,
              getValue=function() return settingsTable.healthHeight end,
              setValue=function(v) settingsTable.healthHeight = v; ReloadAndUpdate() end },
            rightSlot);  y = y - h

        -- Row 2: Fill Color + Bar Background / Bar Opacity. Boss frames present
        -- Fill Color AND Bar Background each as an opacity slider with inline
        -- class/custom swatches (mirroring Main Frames' Bar Background); other mini
        -- units keep the combined "Bar Color" multiSwatch + a "Bar Opacity" slider.
        do
            local isBoss = (unitKey == "boss")

            local leftSlot2, rightSlot2
            if isBoss then
                -- Fill Color = the health fill opacity (formerly "Fill Opacity")
                -- with the fill color swatches moved inline below.
                leftSlot2 = { type="slider", text="Fill Color", min=0, max=100, step=1,
                  disabled=function() return db.profile.darkTheme end,
                  disabledTooltip="Dark Mode", requireState="disabled",
                  getValue=function() return MVal("healthBarOpacity", 90) end,
                  setValue=function(v) MSet("healthBarOpacity", v) end }
                rightSlot2 = { type="slider", text="Bar Background", min=0, max=100, step=1,
                  getValue=function() return MVal("customBgAlpha", 100) end,
                  setValue=function(v) MSet("customBgAlpha", v) end }
            else
                -- "Fill Color" picker: Custom Colored Fill + Class Colored Fill.
                -- Bar Background was split out to its own slider + swatch row below
                -- (still the same customBgColor / customBgAlpha variables).
                local fillSwatches = {
                    { tooltip = "Custom Colored Fill", hasAlpha = false,
                      getValue = function()
                          local c = MGet("customFillColor")
                          if c then return c.r, c.g, c.b end
                          return 37/255, 193/255, 29/255
                      end,
                      setValue = function(r, g, b)
                          settingsTable.customFillColor = { r=r, g=g, b=b }
                          ReloadAndUpdate()
                      end,
                      onClick = function(self)
                          if MVal("healthClassColored", false) then
                              if MGet("customFillColor") == nil then
                                  settingsTable.customFillColor = { r = 37/255, g = 193/255, b = 29/255 }
                              end
                              settingsTable.healthClassColored = false
                              ReloadAndUpdate(); EllesmereUI:RefreshPage()
                              return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha = function()
                          return MVal("healthClassColored", false) and 0.3 or 1
                      end },
                    { tooltip = "Class Colored Fill", hasAlpha = false,
                      getValue = function()
                          local _, ct = UnitClass("player")
                          if ct and RAID_CLASS_COLORS[ct] then
                              local cc = RAID_CLASS_COLORS[ct]
                              return cc.r, cc.g, cc.b
                          end
                          return 1, 1, 1
                      end,
                      setValue = function() end,
                      onClick = function()
                          settingsTable.healthClassColored = true
                          ReloadAndUpdate(); EllesmereUI:RefreshPage()
                      end,
                      refreshAlpha = function()
                          return MVal("healthClassColored", false) and 1 or 0.3
                      end },
                }
                leftSlot2 = { type="multiSwatch", text="Fill Color", swatches = fillSwatches }
                rightSlot2 = { type="slider", text="Fill Opacity", min=0, max=100, step=1,
                  disabled=function() return db.profile.darkTheme end,
                  disabledTooltip="Dark Mode", requireState="disabled",
                  getValue=function() return MVal("healthBarOpacity", 90) end,
                  setValue=function(v) MSet("healthBarOpacity", v) end }
            end

            local colorRow
            colorRow, h = W:DualRow(parent, y, leftSlot2, rightSlot2);  y = y - h

            if isBoss then
                -- Inline Custom + Class fill swatches on the Fill Color slider (left
                -- region); both toggle healthClassColored, the inactive one dims to 0.3.
                do
                    local rgn = colorRow._leftRegion
                    local fClassGet = function()
                        local _, ct = UnitClass("player")
                        local cc = ct and RAID_CLASS_COLORS[ct]
                        if cc then return cc.r, cc.g, cc.b end
                        return 1, 1, 1
                    end
                    local fClassSw, fClassUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, fClassGet, function() end, false, 20)
                    fClassSw._eabOrigClick = fClassSw:GetScript("OnClick")
                    fClassSw:SetScript("OnClick", function()
                        settingsTable.healthClassColored = true
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end)
                    fClassSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(fClassSw, "Class Colored Fill") end)
                    fClassSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    PP.Point(fClassSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                    rgn._lastInline = fClassSw
                    RegisterWidgetRefresh(function()
                        fClassUpdate()
                        fClassSw:SetAlpha(MVal("healthClassColored", false) and 1 or 0.3)
                    end)
                    fClassSw:SetAlpha(MVal("healthClassColored", false) and 1 or 0.3)

                    local fCustomGet = function()
                        local c = MGet("customFillColor")
                        if c then return c.r, c.g, c.b end
                        return 37/255, 193/255, 29/255
                    end
                    local fCustomSet = function(r, g, b)
                        settingsTable.customFillColor = { r=r, g=g, b=b }
                        ReloadAndUpdate()
                    end
                    local fCustomSw, fCustomUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, fCustomGet, fCustomSet, false, 20)
                    fCustomSw._eabOrigClick = fCustomSw:GetScript("OnClick")
                    fCustomSw:SetScript("OnClick", function(self)
                        if MVal("healthClassColored", false) then
                            if MGet("customFillColor") == nil then
                                settingsTable.customFillColor = { r = 37/255, g = 193/255, b = 29/255 }
                            end
                            settingsTable.healthClassColored = false
                            ReloadAndUpdate(); EllesmereUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end)
                    fCustomSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(fCustomSw, "Custom Colored Fill") end)
                    fCustomSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    PP.Point(fCustomSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                    rgn._lastInline = fCustomSw
                    RegisterWidgetRefresh(function()
                        fCustomUpdate()
                        fCustomSw:SetAlpha(MVal("healthClassColored", false) and 0.3 or 1)
                    end)
                    fCustomSw:SetAlpha(MVal("healthClassColored", false) and 0.3 or 1)
                end

                -- Inline Custom + Class background swatches on the Bar Background
                -- slider (right region); both toggle bgClassColored, inactive dims to 0.3.
                do
                    local rgn = colorRow._rightRegion
                    local bgClassGet = function()
                        local _, ct = UnitClass("player")
                        local cc = ct and RAID_CLASS_COLORS[ct]
                        if cc then return cc.r, cc.g, cc.b end
                        return 1, 1, 1
                    end
                    local bgClassSw, bgClassUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgClassGet, function() end, false, 20)
                    bgClassSw._eabOrigClick = bgClassSw:GetScript("OnClick")
                    bgClassSw:SetScript("OnClick", function()
                        settingsTable.bgClassColored = true
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end)
                    bgClassSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgClassSw, "Class Colored Background") end)
                    bgClassSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    PP.Point(bgClassSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                    rgn._lastInline = bgClassSw
                    RegisterWidgetRefresh(function()
                        bgClassUpdate()
                        bgClassSw:SetAlpha(MVal("bgClassColored", false) and 1 or 0.3)
                    end)
                    bgClassSw:SetAlpha(MVal("bgClassColored", false) and 1 or 0.3)

                    local bgSwGet = function()
                        local c = MGet("customBgColor")
                        if c then return c.r, c.g, c.b end
                        return 17/255, 17/255, 17/255
                    end
                    local bgSwSet = function(r, g, b)
                        settingsTable.customBgColor = { r=r, g=g, b=b }
                        ReloadAndUpdate()
                    end
                    local bgSw, bgSwUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgSwGet, bgSwSet, false, 20)
                    bgSw._eabOrigClick = bgSw:GetScript("OnClick")
                    bgSw:SetScript("OnClick", function(self)
                        if MVal("bgClassColored", false) then
                            settingsTable.bgClassColored = false
                            ReloadAndUpdate(); EllesmereUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end)
                    bgSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgSw, "Custom Background Color") end)
                    bgSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    PP.Point(bgSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                    rgn._lastInline = bgSw
                    RegisterWidgetRefresh(function()
                        bgSwUpdate()
                        bgSw:SetAlpha(MVal("bgClassColored", false) and 0.3 or 1)
                    end)
                    bgSw:SetAlpha(MVal("bgClassColored", false) and 0.3 or 1)
                end
            end

            -- Dark Mode: disable the Fill Color controls (the flat dark health bar
            -- ignores fill/background colors). Boss also blocks the Bar Background
            -- region so its swatches gray out like Main Frames; for other mini units
            -- the right-slot Bar Opacity is already disabled via its own handler.
            AddDarkModeBlock(colorRow._leftRegion)
            if isBoss then AddDarkModeBlock(colorRow._rightRegion) end
        end

        -- Smooth Health Bars + Reverse Fill. For the mini frames (ToT / Focus
        -- Target / Pet) Smooth Health Bars is relocated to the Center Text row
        -- (slot 2) below, leaving only Reverse Fill on this row. Boss keeps both.
        local smoothBarsWidget = { type="toggle", text="Smooth Health Bars",
              getValue=function() return MVal("smoothBars", false) end,
              setValue=function(v) MSet("smoothBars", v) end }
        local reverseFillWidget = { type="toggle", text="Reverse Fill",
              getValue=function() return settingsTable.healthReverseFill end,
              setValue=function(v) settingsTable.healthReverseFill = v; ReloadAndUpdate() end }
        if unitKey == "boss" then
            _, h = W:DualRow(parent, y, smoothBarsWidget, reverseFillWidget);  y = y - h
        else
            -- Bar Background (opacity slider + inline color swatch) | Reverse Fill.
            -- Reuses the existing customBgAlpha (opacity) + customBgColor (color)
            -- variables -- same as the Boss frames and the runtime health bg, so
            -- no saved option changes.
            local bgRow
            bgRow, h = W:DualRow(parent, y,
                { type="slider", text="Bar Background", min=0, max=100, step=1,
                  getValue=function() return MVal("customBgAlpha", 100) end,
                  setValue=function(v) MSet("customBgAlpha", v) end },
                reverseFillWidget);  y = y - h
            -- Inline Bar Background color swatch (customBgColor) on the slider region.
            do
                local rgn = bgRow._leftRegion
                local bgSwGet = function()
                    local c = MGet("customBgColor")
                    if c then return c.r, c.g, c.b end
                    return 17/255, 17/255, 17/255
                end
                local bgSwSet = function(r, g, b)
                    settingsTable.customBgColor = { r=r, g=g, b=b }
                    ReloadAndUpdate()
                end
                local bgSw, bgSwUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgSwGet, bgSwSet, false, 20)
                bgSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgSw, "Bar Background Color") end)
                bgSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                PP.Point(bgSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = bgSw
                RegisterWidgetRefresh(function() bgSwUpdate() end)
            end
        end

        -- Row 3: Left Text + Right Text (with inline swatches + cogs)
        local textRow
        textRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Left Text", values=healthTextValues, order=(unitKey == "boss") and healthTextOrderBoss or healthTextOrder,
              getValue=function() return MVal("leftTextContent", "name") end,
              setValue=function(v)
                settingsTable.leftTextContent = v
                if v ~= "none" then
                    if settingsTable.rightTextContent == v then settingsTable.rightTextContent = "none" end
                    if settingsTable.centerTextContent == v then settingsTable.centerTextContent = "none" end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
              end,
            },
            { type="dropdown", text="Right Text", values=healthTextValues, order=(unitKey == "boss") and healthTextOrderBoss or healthTextOrder,
              getValue=function() return MVal("rightTextContent", "none") end,
              setValue=function(v)
                settingsTable.rightTextContent = v
                if v ~= "none" then
                    if settingsTable.leftTextContent == v then settingsTable.leftTextContent = "none" end
                    if settingsTable.centerTextContent == v then settingsTable.centerTextContent = "none" end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
              end,
            });  y = y - h
        -- Inline color swatches + cog on Left Text: Custom + Class (CDM Border Size pattern)
        do
            local rgn = textRow._leftRegion
            local classSw, classSwUp = EllesmereUI.BuildColorSwatch(
                rgn, rgn:GetFrameLevel() + 5,
                function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            PP.Point(classSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            classSw:SetScript("OnClick", function()
                if MVal("leftTextContent", "name") == "none" then return end
                MSet("leftTextClassColor", true); EllesmereUI:RefreshPage()
            end)
            classSw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(classSw, "Class Colored") end)
            classSw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local swGet = function()
                return MVal("leftTextColorR", 1), MVal("leftTextColorG", 1), MVal("leftTextColorB", 1)
            end
            local swSet = function(r, g, b)
                settingsTable.leftTextColorR = r; settingsTable.leftTextColorG = g; settingsTable.leftTextColorB = b
                ReloadAndUpdate()
            end
            local sw, swUp = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, swGet, swSet, nil, 20)
            PP.Point(sw, "RIGHT", classSw, "LEFT", -8, 0)
            rgn._lastInline = sw
            local origClick = sw:GetScript("OnClick")
            sw:SetScript("OnClick", function(self, ...)
                if MVal("leftTextContent", "name") == "none" then return end
                if MVal("leftTextClassColor", false) then
                    MSet("leftTextClassColor", false); EllesmereUI:RefreshPage(); return
                end
                if origClick then origClick(self, ...) end
            end)
            sw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Custom Colored") end)
            sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdSwatches()
                local isNone = MVal("leftTextContent", "name") == "none"
                local isClass = MVal("leftTextClassColor", false)
                sw:SetAlpha((isClass or isNone) and 0.3 or 1)
                classSw:SetAlpha((isClass and not isNone) and 1 or 0.3)
            end
            RegisterWidgetRefresh(function() swUp(); classSwUp(); UpdSwatches() end)
            UpdSwatches()

            local _, cogShowFn = EllesmereUI.BuildCogPopup({
                title = "Left Text Settings",
                rows = {
                    { type="slider", label="Size", min=8, max=100, step=1,
                      get=function() return MVal("leftTextSize", settingsTable.textSize or 12) end,
                      set=function(v) MSet("leftTextSize", v) end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return MVal("leftTextX", 0) end,
                      set=function(v) MSet("leftTextX", v) end },
                    { type="slider", label="Y Offset", min=-30, max=30, step=1,
                      get=function() return MVal("leftTextY", 0) end,
                      set=function(v) MSet("leftTextY", v) end },
                    { type="slider", label="Name Length", min=0, max=30, step=1,
                      get=function() return MVal("leftTextShortNameLength", 0) end,
                      set=function(v) MSet("leftTextShortNameLength", v) end,
                      disabled=function() local c=MVal("leftTextContent","name") return c ~= "name" and c ~= "nametotarget" and c ~= "levelname" and c ~= "namelevel" end,
                      disabledTooltip="Only applies when the selected text includes a Name." },
                    { type="toggle", label="Show Ellipsis",
                      get=function() return MVal("leftTextShortNameEllipsis", true) ~= false end,
                      set=function(v) MSet("leftTextShortNameEllipsis", v) end,
                      disabled=function() local c=MVal("leftTextContent","name") return c ~= "name" and c ~= "nametotarget" and c ~= "levelname" and c ~= "namelevel" end,
                      disabledTooltip="Only applies when the selected text includes a Name." },
                    { type="multiswatch", label="Indicator Color",
                      disabled=function() return MVal("leftTextContent","name") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected.",
                      swatches = {
                        { tooltip = "Custom Colored", hasAlpha = false,
                          getValue = function() local c = MVal("leftTextTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                          setValue = function(r, g, b) MSet("leftTextTargetSepColor", { r=r, g=g, b=b }) end,
                          onClick = function(self)
                              if MVal("leftTextTargetSepClassColor", false) then
                                  MSet("leftTextTargetSepClassColor", false)
                                  return
                              end
                              if self._eabOrigClick then self._eabOrigClick(self) end
                          end,
                          refreshAlpha = function() return MVal("leftTextTargetSepClassColor", false) and 0.3 or 1 end },
                        { tooltip = "Class Colored", hasAlpha = false,
                          getValue = function()
                              local _, ct = UnitClass("player")
                              local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                              if cc then return cc.r, cc.g, cc.b end
                              return 1, 1, 1
                          end,
                          setValue = function() end,
                          onClick = function() MSet("leftTextTargetSepClassColor", true) end,
                          refreshAlpha = function() return MVal("leftTextTargetSepClassColor", false) and 1 or 0.3 end },
                      } },
                    { type="input", label="Separator", inputWidth=60,
                      get=function() return MVal("leftTextTargetSep", ">") end,
                      set=function(v)
                          v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                          if v == "" then v = ">" end
                          MSet("leftTextTargetSep", v)
                      end,
                      disabled=function() return MVal("leftTextContent","name") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected." },
                                    },
            })
            local cogBtn = MCogBtn(rgn, cogShowFn)
            local function UpdCog()
                local isNone = MVal("leftTextContent", "name") == "none"
                cogBtn:SetAlpha(isNone and 0.15 or 0.4)
            end
            cogBtn:SetScript("OnEnter", function(self)
                if MVal("leftTextContent", "name") == "none" then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a text selection other than none."))
                else self:SetAlpha(0.7) end
            end)
            cogBtn:SetScript("OnLeave", function(self) UpdCog(); EllesmereUI.HideWidgetTooltip() end)
            cogBtn:SetScript("OnClick", function(self) if MVal("leftTextContent", "name") ~= "none" then cogShowFn(self) end end)
            UpdCog(); RegisterWidgetRefresh(UpdCog)
        end
        -- Inline color swatches + cog on Right Text: Custom + Class (CDM Border Size pattern)
        do
            local rgn = textRow._rightRegion
            local classSw, classSwUp = EllesmereUI.BuildColorSwatch(
                rgn, rgn:GetFrameLevel() + 5,
                function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            PP.Point(classSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            classSw:SetScript("OnClick", function()
                if MVal("rightTextContent", "none") == "none" then return end
                MSet("rightTextClassColor", true); EllesmereUI:RefreshPage()
            end)
            classSw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(classSw, "Class Colored") end)
            classSw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local swGet = function()
                return MVal("rightTextColorR", 1), MVal("rightTextColorG", 1), MVal("rightTextColorB", 1)
            end
            local swSet = function(r, g, b)
                settingsTable.rightTextColorR = r; settingsTable.rightTextColorG = g; settingsTable.rightTextColorB = b
                ReloadAndUpdate()
            end
            local sw, swUp = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, swGet, swSet, nil, 20)
            PP.Point(sw, "RIGHT", classSw, "LEFT", -8, 0)
            rgn._lastInline = sw
            local origClick = sw:GetScript("OnClick")
            sw:SetScript("OnClick", function(self, ...)
                if MVal("rightTextContent", "none") == "none" then return end
                if MVal("rightTextClassColor", false) then
                    MSet("rightTextClassColor", false); EllesmereUI:RefreshPage(); return
                end
                if origClick then origClick(self, ...) end
            end)
            sw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Custom Colored") end)
            sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdSwatches()
                local isNone = MVal("rightTextContent", "none") == "none"
                local isClass = MVal("rightTextClassColor", false)
                sw:SetAlpha((isClass or isNone) and 0.3 or 1)
                classSw:SetAlpha((isClass and not isNone) and 1 or 0.3)
            end
            RegisterWidgetRefresh(function() swUp(); classSwUp(); UpdSwatches() end)
            UpdSwatches()

            local _, cogShowFn = EllesmereUI.BuildCogPopup({
                title = "Right Text Settings",
                rows = {
                    { type="slider", label="Size", min=8, max=100, step=1,
                      get=function() return MVal("rightTextSize", settingsTable.textSize or 12) end,
                      set=function(v) MSet("rightTextSize", v) end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return MVal("rightTextX", 0) end,
                      set=function(v) MSet("rightTextX", v) end },
                    { type="slider", label="Y Offset", min=-30, max=30, step=1,
                      get=function() return MVal("rightTextY", 0) end,
                      set=function(v) MSet("rightTextY", v) end },
                    { type="slider", label="Name Length", min=0, max=30, step=1,
                      get=function() return MVal("rightTextShortNameLength", 0) end,
                      set=function(v) MSet("rightTextShortNameLength", v) end,
                      disabled=function() local c=MVal("rightTextContent","none") return c ~= "name" and c ~= "nametotarget" and c ~= "levelname" and c ~= "namelevel" end,
                      disabledTooltip="Only applies when the selected text includes a Name." },
                    { type="toggle", label="Show Ellipsis",
                      get=function() return MVal("rightTextShortNameEllipsis", true) ~= false end,
                      set=function(v) MSet("rightTextShortNameEllipsis", v) end,
                      disabled=function() local c=MVal("rightTextContent","none") return c ~= "name" and c ~= "nametotarget" and c ~= "levelname" and c ~= "namelevel" end,
                      disabledTooltip="Only applies when the selected text includes a Name." },
                    { type="multiswatch", label="Indicator Color",
                      disabled=function() return MVal("rightTextContent","none") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected.",
                      swatches = {
                        { tooltip = "Custom Colored", hasAlpha = false,
                          getValue = function() local c = MVal("rightTextTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                          setValue = function(r, g, b) MSet("rightTextTargetSepColor", { r=r, g=g, b=b }) end,
                          onClick = function(self)
                              if MVal("rightTextTargetSepClassColor", false) then
                                  MSet("rightTextTargetSepClassColor", false)
                                  return
                              end
                              if self._eabOrigClick then self._eabOrigClick(self) end
                          end,
                          refreshAlpha = function() return MVal("rightTextTargetSepClassColor", false) and 0.3 or 1 end },
                        { tooltip = "Class Colored", hasAlpha = false,
                          getValue = function()
                              local _, ct = UnitClass("player")
                              local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                              if cc then return cc.r, cc.g, cc.b end
                              return 1, 1, 1
                          end,
                          setValue = function() end,
                          onClick = function() MSet("rightTextTargetSepClassColor", true) end,
                          refreshAlpha = function() return MVal("rightTextTargetSepClassColor", false) and 1 or 0.3 end },
                      } },
                    { type="input", label="Separator", inputWidth=60,
                      get=function() return MVal("rightTextTargetSep", ">") end,
                      set=function(v)
                          v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                          if v == "" then v = ">" end
                          MSet("rightTextTargetSep", v)
                      end,
                      disabled=function() return MVal("rightTextContent","none") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected." },
                                    },
            })
            local cogBtn = MCogBtn(rgn, cogShowFn)
            local function UpdCog()
                local isNone = MVal("rightTextContent", "none") == "none"
                cogBtn:SetAlpha(isNone and 0.15 or 0.4)
            end
            cogBtn:SetScript("OnEnter", function(self)
                if MVal("rightTextContent", "none") == "none" then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a text selection other than none."))
                else self:SetAlpha(0.7) end
            end)
            cogBtn:SetScript("OnLeave", function(self) UpdCog(); EllesmereUI.HideWidgetTooltip() end)
            cogBtn:SetScript("OnClick", function(self) if MVal("rightTextContent", "none") ~= "none" then cogShowFn(self) end end)
            UpdCog(); RegisterWidgetRefresh(UpdCog)
        end

        -- Row 4: Center Text (with inline swatch + cog). Slot 2 holds Smooth Health
        -- Bars for the mini frames (ToT / Focus Target / Pet); blank for boss.
        local centerRow
        centerRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Center Text", values=healthTextValues, order=(unitKey == "boss") and healthTextOrderBoss or healthTextOrder,
              getValue=function() return MVal("centerTextContent", "none") end,
              setValue=function(v)
                settingsTable.centerTextContent = v
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
              end },
            (unitKey ~= "boss") and smoothBarsWidget or { type="label", text="" });  y = y - h
        -- Inline color swatches + cog on Center Text: Custom + Class (CDM Border Size pattern)
        do
            local rgn = centerRow._leftRegion
            local classSw, classSwUp = EllesmereUI.BuildColorSwatch(
                rgn, rgn:GetFrameLevel() + 5,
                function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            PP.Point(classSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            classSw:SetScript("OnClick", function()
                if MVal("centerTextContent", "none") == "none" then return end
                MSet("centerTextClassColor", true); EllesmereUI:RefreshPage()
            end)
            classSw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(classSw, "Class Colored") end)
            classSw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local swGet = function()
                return MVal("centerTextColorR", 1), MVal("centerTextColorG", 1), MVal("centerTextColorB", 1)
            end
            local swSet = function(r, g, b)
                settingsTable.centerTextColorR = r; settingsTable.centerTextColorG = g; settingsTable.centerTextColorB = b
                ReloadAndUpdate()
            end
            local sw, swUp = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, swGet, swSet, nil, 20)
            PP.Point(sw, "RIGHT", classSw, "LEFT", -8, 0)
            rgn._lastInline = sw
            local origClick = sw:GetScript("OnClick")
            sw:SetScript("OnClick", function(self, ...)
                if MVal("centerTextContent", "none") == "none" then return end
                if MVal("centerTextClassColor", false) then
                    MSet("centerTextClassColor", false); EllesmereUI:RefreshPage(); return
                end
                if origClick then origClick(self, ...) end
            end)
            sw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Custom Colored") end)
            sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdSwatches()
                local isNone = MVal("centerTextContent", "none") == "none"
                local isClass = MVal("centerTextClassColor", false)
                sw:SetAlpha((isClass or isNone) and 0.3 or 1)
                classSw:SetAlpha((isClass and not isNone) and 1 or 0.3)
            end
            RegisterWidgetRefresh(function() swUp(); classSwUp(); UpdSwatches() end)
            UpdSwatches()

            local _, cogShowFn = EllesmereUI.BuildCogPopup({
                title = "Center Text Settings",
                rows = {
                    { type="slider", label="Size", min=8, max=100, step=1,
                      get=function() return MVal("centerTextSize", settingsTable.textSize or 12) end,
                      set=function(v) MSet("centerTextSize", v) end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return MVal("centerTextX", 0) end,
                      set=function(v) MSet("centerTextX", v) end },
                    { type="slider", label="Y Offset", min=-30, max=30, step=1,
                      get=function() return MVal("centerTextY", 0) end,
                      set=function(v) MSet("centerTextY", v) end },
                    { type="slider", label="Name Length", min=0, max=30, step=1,
                      get=function() return MVal("centerTextShortNameLength", 0) end,
                      set=function(v) MSet("centerTextShortNameLength", v) end,
                      disabled=function() local c=MVal("centerTextContent","none") return c ~= "name" and c ~= "nametotarget" and c ~= "levelname" and c ~= "namelevel" end,
                      disabledTooltip="Only applies when the selected text includes a Name." },
                    { type="toggle", label="Show Ellipsis",
                      get=function() return MVal("centerTextShortNameEllipsis", true) ~= false end,
                      set=function(v) MSet("centerTextShortNameEllipsis", v) end,
                      disabled=function() local c=MVal("centerTextContent","none") return c ~= "name" and c ~= "nametotarget" and c ~= "levelname" and c ~= "namelevel" end,
                      disabledTooltip="Only applies when the selected text includes a Name." },
                    { type="multiswatch", label="Indicator Color",
                      disabled=function() return MVal("centerTextContent","none") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected.",
                      swatches = {
                        { tooltip = "Custom Colored", hasAlpha = false,
                          getValue = function() local c = MVal("centerTextTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                          setValue = function(r, g, b) MSet("centerTextTargetSepColor", { r=r, g=g, b=b }) end,
                          onClick = function(self)
                              if MVal("centerTextTargetSepClassColor", false) then
                                  MSet("centerTextTargetSepClassColor", false)
                                  return
                              end
                              if self._eabOrigClick then self._eabOrigClick(self) end
                          end,
                          refreshAlpha = function() return MVal("centerTextTargetSepClassColor", false) and 0.3 or 1 end },
                        { tooltip = "Class Colored", hasAlpha = false,
                          getValue = function()
                              local _, ct = UnitClass("player")
                              local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                              if cc then return cc.r, cc.g, cc.b end
                              return 1, 1, 1
                          end,
                          setValue = function() end,
                          onClick = function() MSet("centerTextTargetSepClassColor", true) end,
                          refreshAlpha = function() return MVal("centerTextTargetSepClassColor", false) and 1 or 0.3 end },
                      } },
                    { type="input", label="Separator", inputWidth=60,
                      get=function() return MVal("centerTextTargetSep", ">") end,
                      set=function(v)
                          v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                          if v == "" then v = ">" end
                          MSet("centerTextTargetSep", v)
                      end,
                      disabled=function() return MVal("centerTextContent","none") ~= "nametotarget" end,
                      disabledTooltip="Only applies when Name > Target is selected." },
                                    },
            })
            local cogBtn = MCogBtn(rgn, cogShowFn)
            local function UpdCog()
                local isNone = MVal("centerTextContent", "none") == "none"
                cogBtn:SetAlpha(isNone and 0.15 or 0.4)
            end
            cogBtn:SetScript("OnEnter", function(self)
                if MVal("centerTextContent", "none") == "none" then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a text selection other than none."))
                else self:SetAlpha(0.7) end
            end)
            cogBtn:SetScript("OnLeave", function(self) UpdCog(); EllesmereUI.HideWidgetTooltip() end)
            cogBtn:SetScript("OnClick", function(self) if MVal("centerTextContent", "none") ~= "none" then cogShowFn(self) end end)
            UpdCog(); RegisterWidgetRefresh(UpdCog)
        end

        -- POWER BAR section (only for mini units that render a power bar, i.e. boss).
        -- Fill always uses the unit's power color (powerPercentPowerColor default on);
        -- a height of 0 effectively hides the bar.
        if opts.hasPowerBar then
            local powerHeader
            powerHeader, h = W:SectionHeader(parent, "POWER BAR", y); y = y - h

            -- Row 1: Power Bar Height (+ Reverse Fill cog) | Above Health Bar toggle
            local pwrRow1
            pwrRow1, h = W:DualRow(parent, y,
                { type="slider", text="Power Bar Height", min=0, max=30, step=1,
                  getValue=function() return MVal("powerHeight", 6) end,
                  setValue=function(v) MSet("powerHeight", v) end },
                { type="toggle", text="Above Health Bar",
                  getValue=function() return MVal("powerPosition", "below") == "above" end,
                  setValue=function(v) MSet("powerPosition", v and "above" or "below") end });  y = y - h
            -- Expose the Power Bar Height row + POWER BAR header so the boss
            -- preview's power-bar click overlay can scroll here.
            parent._powerHeaderFrame = powerHeader
            parent._powerHeightRow = pwrRow1
            -- Reverse Fill cog on Power Bar Height (left) -- mirrors Main Frames.
            do
                local rgn = pwrRow1._leftRegion
                local _, revCogShow = EllesmereUI.BuildCogPopup({
                    title = "Power Bar Fill",
                    rows = {
                        { type="toggle", label="Reverse Fill",
                          get=function() return MVal("powerReverseFill", false) end,
                          set=function(v) MSet("powerReverseFill", v) end },
                    },
                })
                MCogBtn(rgn, revCogShow)
            end

            -- Row 2: Bar Background (opacity slider + power/custom bg swatches) |
            -- Fill Color (opacity slider + power/custom fill swatches). Mirrors the
            -- Main Frames power bar; the opacity sliders replace the old plain ones.
            local pwrRow2
            pwrRow2, h = W:DualRow(parent, y,
                { type="slider", text="Bar Background", min=0, max=100, step=1,
                  getValue=function() return MVal("customPowerBgAlpha", 100) end,
                  setValue=function(v) MSet("customPowerBgAlpha", v) end },
                { type="slider", text="Fill Color", min=0, max=100, step=1,
                  getValue=function() return MVal("powerBarOpacity", 100) end,
                  setValue=function(v) MSet("powerBarOpacity", v) end });  y = y - h
            -- Inline Power Colored + Custom background swatches on Bar Background
            -- (left region); both toggle powerBgPowerColored, the inactive one
            -- dims to 0.3 (mirrors the Main Frames power Bar Background).
            do
                local rgn = pwrRow2._leftRegion
                local bgPwrGet = function()
                    local _, pToken = UnitPowerType("player")
                    local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                    local f = EllesmereUI.GetPowerBgDarkenFactor()
                    return info.r * f, info.g * f, info.b * f
                end
                local bgPwrSw, bgPwrUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgPwrGet, function() end, false, 20)
                bgPwrSw._eabOrigClick = bgPwrSw:GetScript("OnClick")
                bgPwrSw:SetScript("OnClick", function()
                    settingsTable.powerBgPowerColored = true
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end)
                bgPwrSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgPwrSw, "Power Colored Background") end)
                bgPwrSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                PP.Point(bgPwrSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = bgPwrSw
                RegisterWidgetRefresh(function()
                    bgPwrUpdate()
                    bgPwrSw:SetAlpha(MVal("powerBgPowerColored", false) and 1 or 0.3)
                end)
                bgPwrSw:SetAlpha(MVal("powerBgPowerColored", false) and 1 or 0.3)

                local bgGet = function()
                    local c = MGet("customPowerBgColor")
                    if c then return c.r, c.g, c.b end
                    return 17/255, 17/255, 17/255
                end
                local bgSet = function(r, g, b)
                    settingsTable.customPowerBgColor = { r=r, g=g, b=b }
                    ReloadAndUpdate()
                end
                local bgSw, bgSwUp = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgGet, bgSet, false, 20)
                bgSw._eabOrigClick = bgSw:GetScript("OnClick")
                bgSw:SetScript("OnClick", function(self)
                    if MVal("powerBgPowerColored", false) then
                        settingsTable.powerBgPowerColored = false
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then self._eabOrigClick(self) end
                end)
                bgSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgSw, "Custom Background Color") end)
                bgSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                PP.Point(bgSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = bgSw
                RegisterWidgetRefresh(function()
                    bgSwUp()
                    bgSw:SetAlpha(MVal("powerBgPowerColored", false) and 0.3 or 1)
                end)
                bgSw:SetAlpha(MVal("powerBgPowerColored", false) and 0.3 or 1)
            end
            -- Inline Power Colored + Custom fill swatches on Fill Color (right
            -- region); both toggle powerPercentPowerColor (default on = power
            -- colored), the inactive one dims to 0.3.
            do
                local rgn = pwrRow2._rightRegion
                local fPwrGet = function()
                    local _, pToken = UnitPowerType("player")
                    local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                    return info.r, info.g, info.b
                end
                local fPwrSw, fPwrUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, fPwrGet, function() end, false, 20)
                fPwrSw._eabOrigClick = fPwrSw:GetScript("OnClick")
                fPwrSw:SetScript("OnClick", function()
                    settingsTable.powerPercentPowerColor = true
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end)
                fPwrSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(fPwrSw, "Power Colored Fill") end)
                fPwrSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                PP.Point(fPwrSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = fPwrSw
                RegisterWidgetRefresh(function()
                    fPwrUpdate()
                    fPwrSw:SetAlpha((MVal("powerPercentPowerColor", true) ~= false) and 1 or 0.3)
                end)
                fPwrSw:SetAlpha((MVal("powerPercentPowerColor", true) ~= false) and 1 or 0.3)

                local fGet = function()
                    local c = MGet("customPowerFillColor")
                    if c then return c.r, c.g, c.b end
                    return 0, 0, 1
                end
                local fSet = function(r, g, b)
                    settingsTable.customPowerFillColor = { r=r, g=g, b=b }
                    ReloadAndUpdate()
                end
                local fSw, fSwUp = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, fGet, fSet, false, 20)
                fSw._eabOrigClick = fSw:GetScript("OnClick")
                fSw:SetScript("OnClick", function(self)
                    if MVal("powerPercentPowerColor", true) ~= false then
                        settingsTable.powerPercentPowerColor = false
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then self._eabOrigClick(self) end
                end)
                fSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(fSw, "Custom Colored Fill") end)
                fSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                PP.Point(fSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = fSw
                RegisterWidgetRefresh(function()
                    fSwUp()
                    fSw:SetAlpha((MVal("powerPercentPowerColor", true) ~= false) and 0.3 or 1)
                end)
                fSw:SetAlpha((MVal("powerPercentPowerColor", true) ~= false) and 0.3 or 1)
            end

            -- Row 3: Power Text (format) + Text Position -- ported from Main Frames.
            -- Reads/writes the same per-unit keys; MSet -> ReloadAndUpdate live-updates
            -- the real boss frames AND the preview (runtime already supports boss).
            local pwrTextRow
            pwrTextRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Power Text",
                  values = { ["none"]="None", ["smart"]="Smart Text", ["curpp"]="Power Value", ["perpp"]="Power %", ["both"]="Value | %" },
                  order  = { "none", "smart", "curpp", "perpp", "both" },
                  getValue=function() return MVal("powerTextFormat", "perpp") end,
                  setValue=function(v)
                      settingsTable.powerTextFormat = v
                      if v ~= "none" and MVal("powerPercentText", "none") == "none" then
                          settingsTable.powerPercentText = "center"
                      end
                      if v == "none" then settingsTable.powerPercentText = "none" end
                      ReloadAndUpdate(); EllesmereUI:RefreshPage()
                  end },
                { type="dropdown", text="Text Position",
                  values = { ["none"]="None", ["left"]="Left", ["right"]="Right", ["center"]="Center" },
                  order  = { "none", "---", "left", "right", "center" },
                  getValue=function() return MVal("powerPercentText", "none") end,
                  setValue=function(v) MSet("powerPercentText", v); EllesmereUI:RefreshPage() end });  y = y - h
            -- Expose the power-text row so the preview's power-text click overlay
            -- can scroll here (mirrors parent._powerHeightRow / _powerHeaderFrame).
            parent._powerTextRow = pwrTextRow
            -- Inline Text Color swatches on Power Text (left): Custom + Power Colored,
            -- mutually exclusive (mirrors Main Frames' Text Color multiSwatch). Custom
            -- click: first clears power-colored (selecting custom), second opens the
            -- picker. Power-colored click: selects power-colored + clears custom.
            do
                local rgn = pwrTextRow._leftRegion
                local customSw, customSwUp = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                    function()
                        local c = MGet("powerTextColor")
                        if c then return c.r, c.g, c.b end
                        return 1, 1, 1
                    end,
                    function(r, g, b)
                        settingsTable.powerTextColor = { r=r, g=g, b=b }
                        ReloadAndUpdate()
                    end, false, 20)
                PP.Point(customSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = customSw
                local customOrigClick = customSw:GetScript("OnClick")
                customSw:SetScript("OnClick", function(self, ...)
                    if MVal("powerPercentTextPowerColor", false) then
                        settingsTable.powerPercentTextPowerColor = false
                        ReloadAndUpdate(); EllesmereUI:RefreshPage(); return
                    end
                    if customOrigClick then customOrigClick(self, ...) end
                end)
                customSw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(customSw, "Custom Text Color") end)
                customSw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local powerSw, powerSwUp = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                    function()
                        local _, pToken = UnitPowerType("player")
                        local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                        if info then return info.r, info.g, info.b end
                        return 1, 1, 1
                    end,
                    function() end, false, 20)
                PP.Point(powerSw, "RIGHT", customSw, "LEFT", -8, 0)
                rgn._lastInline = powerSw
                powerSw:SetScript("OnClick", function()
                    settingsTable.powerPercentTextPowerColor = true
                    settingsTable.powerTextColor = nil
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end)
                powerSw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(powerSw, "Power Colored Text") end)
                powerSw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function UpdSwatches()
                    local isPower = MVal("powerPercentTextPowerColor", false)
                    customSw:SetAlpha(isPower and 0.3 or 1)
                    powerSw:SetAlpha(isPower and 1 or 0.3)
                end
                RegisterWidgetRefresh(function() customSwUp(); powerSwUp(); UpdSwatches() end)
                UpdSwatches()
            end
            -- Show % cog on Power Text (left)
            do
                local rgn = pwrTextRow._leftRegion
                local _, showCog = EllesmereUI.BuildCogPopup({
                    title = "Power Text",
                    rows = {
                        { type="toggle", label="Show %",
                          get=function() return MVal("powerShowPercent", true) ~= false end,
                          set=function(v) MSet("powerShowPercent", v) end },
                    },
                })
                local cogBtn = MCogBtn(rgn, showCog)
                local function Upd()
                    local fmt = MVal("powerTextFormat", "perpp")
                    local off = (fmt == "none" or fmt == "curpp")
                    cogBtn:SetAlpha(off and 0.15 or 0.4)
                    cogBtn:SetEnabled(not off)
                end
                cogBtn:SetScript("OnEnter", function(self)
                    local fmt = MVal("powerTextFormat", "perpp")
                    if fmt == "none" or fmt == "curpp" then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option is only available for formats that display a percentage."))
                    else self:SetAlpha(0.7) end
                end)
                cogBtn:SetScript("OnLeave", function(self) Upd(); EllesmereUI.HideWidgetTooltip() end)
                cogBtn:SetScript("OnClick", function(self) showCog(self) end)
                Upd()
                RegisterWidgetRefresh(Upd)
            end
            -- Size + X/Y offsets cog on Text Position (right)
            do
                local rgn = pwrTextRow._rightRegion
                local _, szCog = EllesmereUI.BuildCogPopup({
                    title = "Text Position",
                    rows = {
                        { type="slider", label="Size", min=6, max=100, step=1,
                          get=function() return MVal("powerPercentSize", 9) end,
                          set=function(v) MSet("powerPercentSize", v) end },
                        { type="slider", label="X Offset", min=-50, max=50, step=1,
                          get=function() return MVal("powerPercentX", 0) end,
                          set=function(v) MSet("powerPercentX", v) end },
                        { type="slider", label="Y Offset", min=-50, max=50, step=1,
                          get=function() return MVal("powerPercentY", 0) end,
                          set=function(v) MSet("powerPercentY", v) end },
                    },
                })
                local cogBtn = MCogBtn(rgn, szCog, EllesmereUI.RESIZE_ICON)
                local function Upd()
                    local off = MVal("powerPercentText", "none") == "none"
                    cogBtn:SetAlpha(off and 0.15 or 0.4)
                    cogBtn:SetEnabled(not off)
                end
                cogBtn:SetScript("OnEnter", function(self)
                    if MVal("powerPercentText", "none") == "none" then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires a text position other than none."))
                    else self:SetAlpha(0.7) end
                end)
                cogBtn:SetScript("OnLeave", function(self) Upd(); EllesmereUI.HideWidgetTooltip() end)
                cogBtn:SetScript("OnClick", function(self) szCog(self) end)
                Upd()
                RegisterWidgetRefresh(Upd)
            end
        end

        -- Extra section rendered at the very bottom, below the Power Bar (boss "Indicators").
        if opts.afterPowerRow then
            y = opts.afterPowerRow(W, parent, y)
        end

        return y, displayHeader, sizeRow, textHeader, textRow, enableRowFrame
    end

    -- Inline "Portrait on Right" cog attached to a Show Portrait toggle
    -- region. Clicking the cog opens a popup with a single toggle that
    -- swaps settings.portraitSide between "left" and "right" live.
    local function AttachPortraitSideCog(rgn, settingsTable)
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Portrait Settings",
            rows = {
                { type="toggle", label="Portrait on Right",
                  get=function() return (settingsTable.portraitSide or "left") == "right" end,
                  set=function(v)
                      settingsTable.portraitSide = v and "right" or "left"
                      ReloadAndUpdate(); UpdatePreview()
                  end },
            },
        })
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -9, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints()
        cogTex:SetTexture(EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
        cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
    end

    -- Shared builder for the two independent mini frames (Target of Target,
    -- Focus Target). settingsTable/unitKey select which one; each renders its
    -- own single enable toggle + Show Portrait (right slot), Pet-style.
    BuildFoTToTOptions = function(W, parent, y, settingsTable, unitKey)
        settingsTable = settingsTable or db.profile.targettarget
        unitKey = unitKey or "targettarget"
        local enableText = (unitKey == "focustarget") and "Enable Focus Target" or "Enable Target of Target"
        local _, h

        _, h = BuildApplyAllRow(parent, y, MINI_GROUP_ORDER, unitKey); y = y - h

        local portraitRow
        local function enableRow(Ww, pp, yy)
            local isEUI = ns.GetUnitFrameSource(unitKey) == "eui"
            -- The Frame Source cog's "Blizzard Default" only makes sense when the
            -- parent target/focus frame is itself on Blizzard's frame (its native
            -- child target-of-target is then alive; see ns.GetUnitFrameSource);
            -- the cog's dropdown is blocked otherwise with an explanation.
            local parentLabel = (unitKey == "focustarget") and "Focus" or "Target"
            local parentKey = (unitKey == "focustarget") and "focus" or "target"
            local childName = (unitKey == "focustarget") and "focus-target" or "target-of-target"
            portraitRow, h = Ww:DualRow(pp, yy,
                { type="toggle", text=enableText,
                  getValue=function() return db.profile.enabledFrames[unitKey] ~= false end,
                  setValue=function(v)
                    db.profile.enabledFrames[unitKey] = v
                    ReloadAndUpdate()
                    EllesmereUI:RefreshPage(true)
                    PromptReloadIfUnspawned({ unitKey })
                  end },
                isEUI and { type="toggle", text="Show Portrait",
                  getValue=function() return settingsTable.showPortrait ~= false end,
                  setValue=function(v)
                    settingsTable.showPortrait = v
                    ReloadAndUpdate()
                  end } or { type="label", text="" })
            if isEUI then
                AttachPortraitSideCog(portraitRow._rightRegion, settingsTable)
            end
            AttachFrameSourceCog(portraitRow._leftRegion, unitKey, {
                tooltip = "Due to Blizzard API restrictions, Blizzard's native " .. childName
                    .. " can't be hidden in combat and will show the whole time you are in combat. Recommended: match the "
                    .. parentLabel .. " frame's source -- both Blizzard Default, or both EllesmereUI.",
                disabled = function() return ns.GetUnitFrameSource(parentKey) ~= "blizzard" end,
                disabledTooltip = "\"Blizzard Default\" is only available when the " .. parentLabel
                    .. " frame's source is set to Blizzard Default -- the " .. childName
                    .. " then comes from Blizzard's " .. parentKey .. " frame.",
            })
            return portraitRow, h
        end

        local displayHeader, sizeRow, textHeader, textRow
        y, displayHeader, sizeRow, textHeader, textRow = BuildMiniTextAndSize(W, parent, y, settingsTable, unitKey, enableRow)

        -- Store click targets for hover highlight system
        parent._ufClickTargets = {
            healthBar  = { section = displayHeader,  target = sizeRow },
            portrait   = { section = displayHeader,  target = portraitRow,   slotSide = "right" },
            nameText   = { section = textHeader or displayHeader,  target = textRow or sizeRow },
            healthText = { section = textHeader or displayHeader,  target = textRow or sizeRow },
        }

        return abs(y)
    end

    BuildPetOptions = function(W, parent, y)
        local _, h

        _, h = BuildApplyAllRow(parent, y, MINI_GROUP_ORDER, "pet"); y = y - h

        local portraitRow
        local function enableRow(Ww, pp, yy)
            local isEUI = ns.GetUnitFrameSource("pet") == "eui"
            portraitRow, h = Ww:DualRow(pp, yy,
                { type="toggle", text="Enable Pet Frame",
                  getValue=function() return db.profile.enabledFrames.pet ~= false end,
                  setValue=function(v)
                    db.profile.enabledFrames.pet = v
                    ReloadAndUpdate()
                    EllesmereUI:RefreshPage(true)
                    PromptReloadIfUnspawned({ "pet" })
                  end },
                isEUI and { type="toggle", text="Show Portrait",
                  getValue=function() return db.profile.pet.showPortrait ~= false end,
                  setValue=function(v)
                    db.profile.pet.showPortrait = v
                    ReloadAndUpdate()
                  end } or { type="label", text="" })
            if isEUI then
                AttachPortraitSideCog(portraitRow._rightRegion, db.profile.pet)
            end
            AttachFrameSourceCog(portraitRow._leftRegion, "pet")
            return portraitRow, h
        end

        local displayHeader, sizeRow, textHeader, textRow
        y, displayHeader, sizeRow, textHeader, textRow = BuildMiniTextAndSize(W, parent, y, db.profile.pet, "pet", enableRow)

        -- Store click targets for hover highlight system
        parent._ufClickTargets = {
            healthBar  = { section = displayHeader,  target = sizeRow },
            portrait   = { section = displayHeader,  target = portraitRow,   slotSide = "right" },
            nameText   = { section = textHeader or displayHeader,  target = textRow or sizeRow },
            healthText = { section = textHeader or displayHeader,  target = textRow or sizeRow },
        }

        return abs(y)
    end

    BuildBossOptions = function(W, parent, y)
        local _, h

        -- Activate / Deactivate Boss Preview button -- matches the Party Mode
        -- activate button: centered above the first section. Disabled while Boss
        -- Frames are turned off: the in-game preview rides on the real (now
        -- disabled) boss frames and renders broken, so it must not be activatable.
        local activateBtnFrame, activateBtnLbl, activateBtn
        local function PreviewLabel()
            return ns._bossPreviewActive and EllesmereUI.L("Deactivate Boss Preview") or EllesmereUI.L("Activate Boss Preview")
        end
        local function BossFramesDisabled()
            return ns.GetUnitFrameSource("boss") ~= "eui"
        end
        activateBtnFrame, h = W:WideButton(parent, PreviewLabel(), y, function()
            if BossFramesDisabled() then return end
            if not ns.SetBossPreview then return end
            ns.SetBossPreview(not ns._bossPreviewActive)
            if activateBtnLbl then activateBtnLbl:SetText(PreviewLabel()) end
        end);  y = y - h
        do
            activateBtn = select(1, activateBtnFrame:GetChildren())
            if activateBtn then
                for i = 1, activateBtn:GetNumRegions() do
                    local rgn = select(i, activateBtn:GetRegions())
                    if rgn and rgn.GetText and rgn:GetText() then
                        activateBtnLbl = rgn; break
                    end
                end
            end
        end
        local function UpdateActivateBtn()
            local off = BossFramesDisabled()
            if activateBtnLbl then activateBtnLbl:SetText(PreviewLabel()) end
            if activateBtn then
                activateBtn:SetAlpha(off and 0.4 or 1)
                activateBtn:EnableMouse(not off)
            end
        end
        UpdateActivateBtn()
        EllesmereUI.RegisterWidgetRefresh(UpdateActivateBtn)

        -- Rows exposed as upvalues so the click-to-scroll targets (built below)
        -- can point at them. growthRow holds Show Cast Icon + Cast Bar Height
        -- after the swap; simpleRow/simpleBuffRow/bossAuraRow + bossAuraHeader are
        -- the aura rows under the "Buffs and Debuffs" section.
        local portraitRow, growthRow, simpleRow, simpleBuffRow, bossAuraRow, bossAuraHeader, bossCastHeader, castMainRow
        local function enableRow(Ww, pp, yy)
            local isEUI = ns.GetUnitFrameSource("boss") == "eui"
            local eh
            portraitRow, eh = Ww:DualRow(pp, yy,
                { type="toggle", text="Enable Boss Frames",
                  getValue=function() return db.profile.enabledFrames.boss ~= false end,
                  setValue=function(v)
                    db.profile.enabledFrames.boss = v
                    -- Force-stop the in-game preview when disabling boss frames;
                    -- it rides on the now-disabled frames and renders broken.
                    if not v and ns._bossPreviewActive and ns.SetBossPreview then
                        ns.SetBossPreview(false)
                    end
                    ReloadAndUpdate()
                    EllesmereUI:RefreshPage(true)
                    PromptReloadIfUnspawned({ "boss" })
                  end },
                isEUI and { type="toggle", text="Show Portrait",
                  getValue=function() return db.profile.boss.showPortrait ~= false end,
                  setValue=function(v)
                    db.profile.boss.showPortrait = v
                    ReloadAndUpdate()
                  end } or { type="label", text="" })
            if isEUI then
                AttachPortraitSideCog(portraitRow._rightRegion, db.profile.boss)
            end
            AttachFrameSourceCog(portraitRow._leftRegion, "boss", {
                onBeforeSet = function(v)
                    -- Force-stop the in-game preview when boss frames are no longer
                    -- EUI-owned; it rides on the real boss frames and renders broken.
                    if v ~= "eui" and ns._bossPreviewActive and ns.SetBossPreview then
                        ns.SetBossPreview(false)
                    end
                end,
            })
            local total = eh
            if isEUI then
                local castRow, ch = Ww:DualRow(pp, yy - eh,
                    { type="dropdown", text="Stack Direction", values={ up="Up", down="Down" }, order={ "up", "down" },
                      getValue=function() return db.profile.boss.bossStackDirection or "down" end,
                      setValue=function(v) db.profile.boss.bossStackDirection = v; ReloadAndUpdate() end },
                    { type="slider", pixel=true, text="Vertical Spacing", min=-200, max=200, step=1,
                      getValue=function() return db.profile.bossSpacing or 80 end,
                      setValue=function(v) db.profile.bossSpacing = v; ReloadAndUpdate() end })
                total = total + ch
            end
            return portraitRow, total
        end

        local function bossAfterSize(Ww, pp, yy)
            local _, hh
            local function BossCogBtn(rgn, showFn, iconPath, disabledFn)
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints()
                cogTex:SetTexture(iconPath or EllesmereUI.COGS_ICON)
                local function isOff() return disabledFn and disabledFn() or false end
                cogBtn:SetScript("OnEnter", function(self) if not isOff() then self:SetAlpha(0.7) end end)
                cogBtn:SetScript("OnLeave", function(self) if not isOff() then self:SetAlpha(0.4) end end)
                cogBtn:SetScript("OnClick", function(self) if not isOff() then showFn(self) end end)
                -- Disabled state (cog alpha 0.15 disabled / 0.4 enabled, per the
                -- inline-controls pattern); re-evaluated on page refresh.
                local function applyCogState()
                    local off = isOff()
                    cogBtn:SetAlpha(off and 0.15 or 0.4)
                    cogBtn:EnableMouse(not off)
                end
                applyCogState()
                if disabledFn then EllesmereUI.RegisterWidgetRefresh(applyCogState) end
                return cogBtn
            end
            -- BUFFS AND DEBUFFS section (below DISPLAY)
            bossAuraHeader, hh = Ww:SectionHeader(pp, "Buffs and Debuffs", yy);  yy = yy - hh

            -- Effective boss aura locations. Simple display overrides the stored
            -- location at runtime and the location dropdowns display None while
            -- it is active, so every disabled check must treat the location as
            -- None whenever the matching simple mode is on. Raw key checks
            -- deadlock: defaults hold simpleDebuffs="left" alongside
            -- debuffAnchor="bottomleft", which locked BOTH the Simple Debuff
            -- Display dropdown (raw anchor not none) and the Debuffs Location
            -- dropdown (simple active) at the same time.
            local function BossDebuffLocationActive()
                local s = db.profile.boss
                if ns.GetBossSimpleDebuffMode(s) ~= "none" then return false end
                return (s.debuffAnchor or "bottomleft") ~= "none"
            end
            local function BossBuffLocationActive()
                local s = db.profile.boss
                if ns.GetBossSimpleBuffMode(s) ~= "none" then return false end
                if s.showBuffs == false then return false end
                return (s.buffAnchor or "topleft") ~= "none"
            end
            -- Composite show-state of the two aura sizing rows (Buff Size |
            -- Buff Text Size and Debuff Size | Debuff Text Size). A row hides
            -- while its column's effective Location is None (Simple mode also
            -- reads as None -- simple has its own text/size controls). All
            -- four Location/Simple dropdown setters capture this BEFORE
            -- writing and force the full rebuild when it changes: any of them
            -- can flip EITHER row (collision pushes, SwapAuraSlot displacing
            -- the other aura's anchor, simple forcing showBuffs/debuffAnchor).
            local function BossBuffRowShown()
                local p = db.profile.boss
                return ns.GetBossSimpleBuffMode(p) == "none" and p.showBuffs ~= false
            end
            local function BossDebuffRowShown()
                local p = db.profile.boss
                return ns.GetBossSimpleDebuffMode(p) == "none" and (p.debuffAnchor or "bottomleft") ~= "none"
            end
            local function BossAuraRowsState()
                return tostring(BossBuffRowShown()) .. "/" .. tostring(BossDebuffRowShown())
            end

            -- Simple Buff Display: identical to Simple Debuff Display above but for
            -- buffs. Defaults to None. Forces a single Left/Right column matched to
            -- the frame height, overriding Buffs Location + Buff Size while active.
            local simpleBuffTextOff = function()
                return BossBuffLocationActive()
                or ns.GetBossSimpleBuffMode(db.profile.boss) == "none"
                or not db.profile.boss.simpleBuffShowCooldownText
            end
            simpleBuffRow, hh = Ww:DualRow(pp, yy,
                { type="dropdown", text="Simple Buff Display",
                  disabled = function()
                      return BossBuffLocationActive()
                  end,
                  disabledTooltip="Buffs Location", requireState="disabled",
                  tooltip = "Force boss buffs into a single large column matched to the frame height.",
                  values = { none = "None", left = "Left", right = "Right" },
                  order = { "none", "left", "right" },
                  getValue=function() return ns.GetBossSimpleBuffMode(db.profile.boss) end,
                  setValue=function(v)
                      local prevState = BossAuraRowsState()
                      db.profile.boss.simpleBuffs = v
                      if v ~= "none" then
                          -- Same-side collision: if Simple Debuff Display occupies this
                          -- side, push it off (set to None) so they never overlap.
                          if ns.GetBossSimpleDebuffMode(db.profile.boss) == v then
                              db.profile.boss.simpleDebuffs = "none"
                          end
                          -- Selecting a side takes over from the normal Buffs
                          -- Location, so force that setting to None.
                          db.profile.boss.showBuffs = false
                      end
                      ReloadAndUpdate()
                      if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
                      if BossAuraRowsState() ~= prevState then
                          EllesmereUI:RefreshPage(true)
                      else
                          EllesmereUI:RefreshPage()
                      end
                  end },
                { type="slider", text="Buff Text Size", min=6, max=100, step=1, trackWidth=120,
                  disabled=simpleBuffTextOff, disabledTooltip="Show Duration (Inside Cog)",
                  getValue=function() return db.profile.boss.simpleBuffCooldownTextSize or 14 end,
                  setValue=function(v) db.profile.boss.simpleBuffCooldownTextSize = v; ReloadAndUpdate() end });  yy = yy - hh

            -- Directions cog on Simple Buff Display: the simple column's own X/Y
            -- offset (defaults to the regular buff offsets via ns.GetBossSimpleBuffOffset);
            -- writing here makes the simple offset independent. Disabled while None.
            do
                local leftRgn = simpleBuffRow._leftRegion
                local _, simpleBuffPosCogShow = EllesmereUI.BuildCogPopup({
                    title = "Simple Buff Position",
                    rows = {
                        -- Max buffs shown in simple mode. Shares the boss maxBuffs key
                        -- with Buffs Location (the two modes are mutually exclusive);
                        -- the runtime caps frame.Buffs.num to it.
                        { type="slider", label="Max Count", min=1, max=20, step=1,
                          get=function() return db.profile.boss.maxBuffs or 4 end,
                          set=function(v) db.profile.boss.maxBuffs = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                        { type="slider", label="Offset X", min=-200, max=200, step=1,
                          get=function() local x = ns.GetBossSimpleBuffOffset(db.profile.boss); return x end,
                          set=function(v) db.profile.boss.simpleBuffOffsetX = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                        { type="slider", label="Offset Y", min=-200, max=200, step=1,
                          get=function() local _, y = ns.GetBossSimpleBuffOffset(db.profile.boss); return y end,
                          set=function(v) db.profile.boss.simpleBuffOffsetY = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                        -- Physical-pixel-perfect gap between the simple buff icons.
                        { type="slider", pixel=true, label="Spacing", min=-1, max=10, step=1,
                          get=function() return db.profile.boss.simpleBuffSpacing or 1 end,
                          set=function(v) db.profile.boss.simpleBuffSpacing = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    },
                })
                BossCogBtn(leftRgn, simpleBuffPosCogShow, EllesmereUI.DIRECTIONS_ICON,
                    function() return ns.GetBossSimpleBuffMode(db.profile.boss) == "none" end)
            end

            -- Inline cog on Simple Text Size: duration X/Y + stack size / X/Y.
            do
                local rightRgn = simpleBuffRow._rightRegion
                -- Inline Duration + Stack swatches mirroring the regular Buff Text
                -- Size swatches (same keys); greyed + disabled on this row cog's
                -- condition.
                local buffOff = function() return BossBuffLocationActive() or ns.GetBossSimpleBuffMode(db.profile.boss) == "none" end
                do
                    local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                        function() local c = db.profile.boss.buffCooldownTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                        function(r, g, b) db.profile.boss.buffCooldownTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                    sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Duration Text Color") end)
                    sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                    rightRgn._lastInline = sw
                    local function apply() upd(); local o = buffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                    apply(); EllesmereUI.RegisterWidgetRefresh(apply)
                end
                do
                    local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                        function() local c = db.profile.boss.buffStackTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                        function(r, g, b) db.profile.boss.buffStackTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                    sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Stack Text Color") end)
                    sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                    rightRgn._lastInline = sw
                    local function apply() upd(); local o = buffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                    apply(); EllesmereUI.RegisterWidgetRefresh(apply)
                end
                local _, simpleBuffStackCogShow = EllesmereUI.BuildCogPopup({
                    title = "Duration & Stack",
                    rows = {
                        { type="toggle", label="Show Duration",
                          get=function() return db.profile.boss.simpleBuffShowCooldownText end,
                          set=function(v) db.profile.boss.simpleBuffShowCooldownText = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                        { type="slider", label="Duration X", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.simpleBuffCooldownTextOffsetX or 0 end,
                          set=function(v) db.profile.boss.simpleBuffCooldownTextOffsetX = v; ReloadAndUpdate() end },
                        { type="slider", label="Duration Y", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.simpleBuffCooldownTextOffsetY or 0 end,
                          set=function(v) db.profile.boss.simpleBuffCooldownTextOffsetY = v; ReloadAndUpdate() end },
                        { type="slider", label="Stack Size", min=6, max=100, step=1,
                          get=function() return db.profile.boss.buffStackTextSize or 14 end,
                          set=function(v) db.profile.boss.buffStackTextSize = v; ReloadAndUpdate() end },
                        { type="dropdown", label="Stack Position",
                          values={ bottomright="Bottom Right", bottomleft="Bottom Left", topright="Top Right", topleft="Top Left", center="Center" },
                          order={ "bottomright", "bottomleft", "topright", "topleft", "center" },
                          get=function() return db.profile.boss.buffStackTextPosition or "bottomright" end,
                          set=function(v) db.profile.boss.buffStackTextPosition = v; ReloadAndUpdate() end },
                        { type="slider", label="Stack X", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.buffStackTextOffsetX or 0 end,
                          set=function(v) db.profile.boss.buffStackTextOffsetX = v; ReloadAndUpdate() end },
                        { type="slider", label="Stack Y", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.buffStackTextOffsetY or 0 end,
                          set=function(v) db.profile.boss.buffStackTextOffsetY = v; ReloadAndUpdate() end },
                    },
                })
                BossCogBtn(rightRgn, simpleBuffStackCogShow, nil, buffOff)
            end
            -- (Show Duration toggle lives inside the Duration & Stack cog above.)

            -- Simple Debuff Display: forces Left anchor + debuff height =
            -- frame bar height so boss debuffs render as one large column.
            -- Row 1 slot 2 is "Simple Text Size": the cooldown-text size slider,
            -- gated by an inline Show-Cooldown-Text toggle, with an inline cog
            -- holding the stack size and stack X/Y position controls.
            
            local simpleTextOff = function()
                return BossDebuffLocationActive()
                or ns.GetBossSimpleDebuffMode(db.profile.boss) == "none"
                or not db.profile.boss.simpleDebuffShowCooldownText
            end
            simpleRow, hh = Ww:DualRow(pp, yy,
                { type="dropdown", text="Simple Debuff Display",
                  disabled = function()
                      return BossDebuffLocationActive()
                  end,
                  disabledTooltip="Debuffs Location", requireState="disabled",
                  tooltip = "Force boss debuffs into a single large column matched to the frame height.",
                  values = { none = "None", left = "Left", right = "Right" },
                  order = { "none", "left", "right" },
                  getValue=function() return ns.GetBossSimpleDebuffMode(db.profile.boss) end,
                  setValue=function(v)
                      local prevState = BossAuraRowsState()
                      db.profile.boss.simpleDebuffs = v
                      if v ~= "none" then
                          -- Same-side collision: if Simple Buff Display occupies this
                          -- side, push it off (set to None) so they never overlap.
                          if ns.GetBossSimpleBuffMode(db.profile.boss) == v then
                              db.profile.boss.simpleBuffs = "none"
                          end
                          -- Selecting a side takes over from the normal Debuffs
                          -- Location, so force that setting to None.
                          db.profile.boss.debuffAnchor = "none"
                      end
                      ReloadAndUpdate()
                      if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
                      if BossAuraRowsState() ~= prevState then
                          EllesmereUI:RefreshPage(true)
                      else
                          EllesmereUI:RefreshPage()
                      end
                  end },
                { type="slider", text="Debuff Text Size", min=6, max=100, step=1, trackWidth=120,
                  disabled=simpleTextOff, disabledTooltip="Show Duration (Inside Cog)",
                  getValue=function() return db.profile.boss.simpleDebuffCooldownTextSize or 14 end,
                  setValue=function(v) db.profile.boss.simpleDebuffCooldownTextSize = v; ReloadAndUpdate() end });  yy = yy - hh

            -- Directions cog on Simple Debuff Display: the simple column's own X/Y
            -- offset. Defaults to the regular debuff offsets for existing users
            -- (ns.GetBossSimpleDebuffOffset); writing here makes the simple offset
            -- independent. Disabled while Simple Debuff Display is None.
            do
                local leftRgn = simpleRow._leftRegion
                local _, simplePosCogShow = EllesmereUI.BuildCogPopup({
                    title = "Simple Debuff Position",
                    rows = {
                        -- Max debuffs shown in simple mode. Shares the boss maxDebuffs
                        -- key with Debuffs Location (the two modes are mutually
                        -- exclusive); the runtime caps frame.Debuffs.num to it.
                        { type="slider", label="Max Count", min=1, max=20, step=1,
                          get=function() return db.profile.boss.maxDebuffs or 10 end,
                          set=function(v) db.profile.boss.maxDebuffs = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                        { type="slider", label="Offset X", min=-200, max=200, step=1,
                          get=function() local x = ns.GetBossSimpleDebuffOffset(db.profile.boss); return x end,
                          set=function(v) db.profile.boss.simpleDebuffOffsetX = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                        { type="slider", label="Offset Y", min=-200, max=200, step=1,
                          get=function() local _, y = ns.GetBossSimpleDebuffOffset(db.profile.boss); return y end,
                          set=function(v) db.profile.boss.simpleDebuffOffsetY = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                        -- Physical-pixel-perfect gap between the simple debuff icons.
                        { type="slider", pixel=true, label="Spacing", min=-1, max=10, step=1,
                          get=function() return db.profile.boss.simpleDebuffSpacing or 1 end,
                          set=function(v) db.profile.boss.simpleDebuffSpacing = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    },
                })
                BossCogBtn(leftRgn, simplePosCogShow, EllesmereUI.DIRECTIONS_ICON,
                    function() return ns.GetBossSimpleDebuffMode(db.profile.boss) == "none" end)
            end

            -- Inline cog on Simple Text Size: duration X/Y + stack size / X/Y.
            do
                local rightRgn = simpleRow._rightRegion
                -- Inline Duration + Stack swatches mirroring the regular Debuff Text
                -- Size swatches (same keys); greyed + disabled on this row cog's
                -- condition.
                local debuffOff = function() return BossDebuffLocationActive() or ns.GetBossSimpleDebuffMode(db.profile.boss) == "none" end
                do
                    local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                        function() local c = db.profile.boss.debuffCooldownTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                        function(r, g, b) db.profile.boss.debuffCooldownTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                    sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Duration Text Color") end)
                    sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                    rightRgn._lastInline = sw
                    local function apply() upd(); local o = debuffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                    apply(); EllesmereUI.RegisterWidgetRefresh(apply)
                end
                do
                    local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                        function() local c = db.profile.boss.debuffStackTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                        function(r, g, b) db.profile.boss.debuffStackTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                    sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Stack Text Color") end)
                    sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                    rightRgn._lastInline = sw
                    local function apply() upd(); local o = debuffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                    apply(); EllesmereUI.RegisterWidgetRefresh(apply)
                end
                local _, simpleStackCogShow = EllesmereUI.BuildCogPopup({
                    title = "Duration & Stack",
                    rows = {
                        { type="toggle", label="Show Duration",
                          get=function() return db.profile.boss.simpleDebuffShowCooldownText end,
                          set=function(v) db.profile.boss.simpleDebuffShowCooldownText = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                        { type="slider", label="Duration X", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.simpleDebuffCooldownTextOffsetX or 0 end,
                          set=function(v) db.profile.boss.simpleDebuffCooldownTextOffsetX = v; ReloadAndUpdate() end },
                        { type="slider", label="Duration Y", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.simpleDebuffCooldownTextOffsetY or 0 end,
                          set=function(v) db.profile.boss.simpleDebuffCooldownTextOffsetY = v; ReloadAndUpdate() end },
                        { type="slider", label="Stack Size", min=6, max=100, step=1,
                          get=function() return db.profile.boss.debuffStackTextSize or 14 end,
                          set=function(v) db.profile.boss.debuffStackTextSize = v; ReloadAndUpdate() end },
                        { type="dropdown", label="Stack Position",
                          values={ bottomright="Bottom Right", bottomleft="Bottom Left", topright="Top Right", topleft="Top Left", center="Center" },
                          order={ "bottomright", "bottomleft", "topright", "topleft", "center" },
                          get=function() return db.profile.boss.debuffStackTextPosition or "bottomright" end,
                          set=function(v) db.profile.boss.debuffStackTextPosition = v; ReloadAndUpdate() end },
                        { type="slider", label="Stack X", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.debuffStackTextOffsetX or 0 end,
                          set=function(v) db.profile.boss.debuffStackTextOffsetX = v; ReloadAndUpdate() end },
                        { type="slider", label="Stack Y", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.debuffStackTextOffsetY or 0 end,
                          set=function(v) db.profile.boss.debuffStackTextOffsetY = v; ReloadAndUpdate() end },
                    },
                })
                BossCogBtn(rightRgn, simpleStackCogShow, nil, debuffOff)
            end
            -- (Show Duration toggle lives inside the Duration & Stack cog above.)

            bossAuraRow, hh = Ww:DualRow(pp, yy,
                { type="dropdown", text="Buffs Location", values=buffAnchorValues, order=buffAnchorOrder,
                  disabled = function() return ns.GetBossSimpleBuffMode(db.profile.boss) ~= "none" end,
                  disabledTooltip = "Simple Buff Display", requireState = "disabled",
                  getValue=function()
                      local s = db.profile.boss
                      -- Forced to None while Simple Buff Display is active (it takes
                      -- over placement); the setter also stores None (showBuffs=false).
                      if ns.GetBossSimpleBuffMode(s) ~= "none" then return "none" end
                      if s.showBuffs == false then return "none" end
                      return s.buffAnchor or "topleft"
                  end,
                  setValue=function(v)
                      local prevState = BossAuraRowsState()
                      local s = db.profile.boss
                      if v == "none" then
                          s.showBuffs = false
                      else
                          s.showBuffs = true
                          SwapAuraSlot(s, "buffAnchor", v)
                      end
                      ReloadAndUpdate()
                      if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
                      if BossAuraRowsState() ~= prevState then
                          EllesmereUI:RefreshPage(true)
                      else
                          EllesmereUI:RefreshPage()
                      end
                  end },
                { type="dropdown", text="Debuffs Location", values=buffAnchorValues, order=buffAnchorOrder,
                  disabled = function() return ns.GetBossSimpleDebuffMode(db.profile.boss) ~= "none" end,
                  disabledTooltip = "Simple Debuff Display", requireState = "disabled",
                  getValue=function()
                      -- Forced to None while Simple Debuff Display is active (it
                      -- takes over placement); the setter also stores None.
                      if ns.GetBossSimpleDebuffMode(db.profile.boss) ~= "none" then return "none" end
                      return db.profile.boss.debuffAnchor or "bottomleft"
                  end,
                  setValue=function(v)
                      local prevState = BossAuraRowsState()
                      SwapAuraSlot(db.profile.boss, "debuffAnchor", v)
                      if db.profile.boss.buffAnchor == "none" then
                          db.profile.boss.showBuffs = false
                      end
                      ReloadAndUpdate()
                      if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
                      -- Full rebuild when either aura row's visibility flipped;
                      -- otherwise the fast refresh keeps dependent disabled
                      -- states (Boss Debuff Filter) current.
                      if BossAuraRowsState() ~= prevState then
                          EllesmereUI:RefreshPage(true)
                      else
                          EllesmereUI:RefreshPage()
                      end
                  end });  yy = yy - hh

            -- Boss Buff Size | Debuff Size: icon size sliders, each with an inline
            -- DIRECTIONS cog holding the cluster X/Y offset. Debuff Size is disabled
            -- while Simple Debuff Display is active (simple mode frame-matches the
            -- size). All setters refresh live frames + both previews.
            -- Debuff Size (and its directions cog) are disabled while Simple
            -- Debuff Display frame-matches the size, or when no debuffs are shown
            -- at all (Simple None + Location None). Shared so the cog matches.
            local bossDebuffSizeOff = function()
                local p = db.profile.boss
                return ns.GetBossSimpleDebuffMode(p) ~= "none" or (p.debuffAnchor or "bottomleft") == "none"
            end
            -- Buff Size (and its directions cog) are disabled while Simple Buff
            -- Display frame-matches the size, or when buffs are hidden (Buffs
            -- Location None). Shared so the cog matches.
            local bossBuffSizeOff = function()
                local p = db.profile.boss
                return ns.GetBossSimpleBuffMode(p) ~= "none" or p.showBuffs == false
            end
            -- Buff Text Size gates on the "Show Duration" toggle inside its
            -- Duration & Stack cog (mirrors Debuff Text Size on the row below).
            local buffTextOff = function()
                return not BossBuffLocationActive()
                or not db.profile.boss.buffShowCooldownText
            end
            -- Buff Size | Buff Text Size row: HIDDEN entirely while the buff
            -- column's effective Location is None (see BossBuffRowShown; the
            -- dropdown setters above force the rebuild on flips).
            if BossBuffRowShown() then
            local bossAuraSizeRow
            bossAuraSizeRow, hh = Ww:DualRow(pp, yy,
                { type="slider", text="Buff Size", min=10, max=70, step=1,
                  disabled=bossBuffSizeOff,
                  disabledTooltip=function()
                      if ns.GetBossSimpleBuffMode(db.profile.boss) ~= "none" then
                          return EllesmereUI.DisabledTooltip("Simple Buff Display", "disabled")
                      end
                      return EllesmereUI.DisabledTooltip("Buffs Location")
                  end,
                  rawTooltip=true,
                  getValue=function() return db.profile.boss.buffSize or 22 end,
                  setValue=function(v)
                      db.profile.boss.buffSize = v; ReloadAndUpdate()
                      if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
                  end },
                { type="slider", text="Buff Text Size", min=6, max=100, step=1, trackWidth=120,
                  disabled=buffTextOff, disabledTooltip="Show Duration (Inside Cog)",
                  getValue=function() return db.profile.boss.buffCooldownTextSize or 10 end,
                  setValue=function(v) db.profile.boss.buffCooldownTextSize = v; ReloadAndUpdate() end });  yy = yy - hh
            do  -- Directions cog on Buff Size (X/Y cluster offset)
                local _, bSizeCog = EllesmereUI.BuildCogPopup({ title = "Buff Position", rows = {
                    { type="slider", label="Offset X", min=-200, max=200, step=1,
                      get=function() return db.profile.boss.buffOffsetX or 0 end,
                      set=function(v) db.profile.boss.buffOffsetX = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    { type="slider", label="Offset Y", min=-200, max=200, step=1,
                      get=function() return db.profile.boss.buffOffsetY or 0 end,
                      set=function(v) db.profile.boss.buffOffsetY = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    -- Physical-pixel-perfect gap between the boss buff icons.
                    { type="slider", pixel=true, label="Spacing", min=-1, max=10, step=1,
                      get=function() return db.profile.boss.buffSpacing or 1 end,
                      set=function(v) db.profile.boss.buffSpacing = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                } })
                BossCogBtn(bossAuraSizeRow._leftRegion, bSizeCog, EllesmereUI.DIRECTIONS_ICON, bossBuffSizeOff)
            end
            do  -- Icon Zoom cog on Buff Size (gated only on buffs hidden, so it
                -- stays adjustable in Simple Buff Display, where zoom still applies)
                local bossBuffZoomOff = function() return db.profile.boss.showBuffs == false end
                local _, bZoomCog = EllesmereUI.BuildCogPopup({ title = "Icon Zoom", rows = {
                    { type="slider", label="Zoom", min=0, max=0.20, step=0.01,
                      get=function() return db.profile.boss.buffIconZoom or 0.07 end,
                      set=function(v) db.profile.boss.buffIconZoom = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                } })
                BossCogBtn(bossAuraSizeRow._leftRegion, bZoomCog, nil, bossBuffZoomOff)
            end
            -- Buff Text Size cog + swatches (right slot): Show Duration +
            -- Duration X/Y + Stack, with inline Duration/Stack text-color
            -- swatches; greyed on the same condition as the cog.
            do
                local PP = EllesmereUI.PanelPP
                local rightRgn = bossAuraSizeRow._rightRegion
                local buffOff = function() return not BossBuffLocationActive() end
                do
                    local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                        function() local c = db.profile.boss.buffCooldownTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                        function(r, g, b) db.profile.boss.buffCooldownTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                    sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Duration Text Color") end)
                    sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                    rightRgn._lastInline = sw
                    local function apply() upd(); local o = buffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                    apply(); EllesmereUI.RegisterWidgetRefresh(apply)
                end
                do
                    local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                        function() local c = db.profile.boss.buffStackTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                        function(r, g, b) db.profile.boss.buffStackTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                    sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Stack Text Color") end)
                    sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                    rightRgn._lastInline = sw
                    local function apply() upd(); local o = buffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                    apply(); EllesmereUI.RegisterWidgetRefresh(apply)
                end
                local _, buffStackCogShow = EllesmereUI.BuildCogPopup({
                    title = "Duration & Stack",
                    rows = {
                        { type="toggle", label="Show Duration",
                          get=function() return db.profile.boss.buffShowCooldownText end,
                          set=function(v) db.profile.boss.buffShowCooldownText = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                        { type="slider", label="Duration X", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.buffCooldownTextOffsetX or 0 end,
                          set=function(v) db.profile.boss.buffCooldownTextOffsetX = v; ReloadAndUpdate() end },
                        { type="slider", label="Duration Y", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.buffCooldownTextOffsetY or 0 end,
                          set=function(v) db.profile.boss.buffCooldownTextOffsetY = v; ReloadAndUpdate() end },
                        { type="slider", label="Stack Size", min=6, max=100, step=1,
                          get=function() return db.profile.boss.buffStackTextSize or 14 end,
                          set=function(v) db.profile.boss.buffStackTextSize = v; ReloadAndUpdate() end },
                        { type="dropdown", label="Stack Position",
                          values={ bottomright="Bottom Right", bottomleft="Bottom Left", topright="Top Right", topleft="Top Left", center="Center" },
                          order={ "bottomright", "bottomleft", "topright", "topleft", "center" },
                          get=function() return db.profile.boss.buffStackTextPosition or "bottomright" end,
                          set=function(v) db.profile.boss.buffStackTextPosition = v; ReloadAndUpdate() end },
                        { type="slider", label="Stack X", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.buffStackTextOffsetX or 0 end,
                          set=function(v) db.profile.boss.buffStackTextOffsetX = v; ReloadAndUpdate() end },
                        { type="slider", label="Stack Y", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.buffStackTextOffsetY or 0 end,
                          set=function(v) db.profile.boss.buffStackTextOffsetY = v; ReloadAndUpdate() end },
                    },
                })
                BossCogBtn(rightRgn, buffStackCogShow, nil, buffOff)
            end
            end   -- close buff sizing row hidden-while-None gate

            -- Per-unit DEBUFF filter for boss frames (NOT synced). Boss BUFFS are
            -- never filtered -- they always show every HELPFUL aura. Multi-select
            -- checkbox dropdown; checked classifications OR together at runtime
            -- (Own Only = PLAYER, Raid Frames = RAID, Crowd Control, Big Defensive,
            -- External Defensive). "Own Only" reuses the legacy onlyPlayerDebuffs
            -- key so existing boss settings carry over.
            do
                local PP = EllesmereUI.PanelPP
                -- Version-branched: 12.1 exposes the full engine
                -- classification set plus a buff-side list for the 12.1-only
                -- Boss Buff Filter; 12.0 keeps today's exact five entries
                -- (buff vars stay nil -- only the 12.1 block consumes them).
                local filterItems, DEBUFF_FILTER_KEYS, buffFilterItems, BUFF_FILTER_KEYS
                if EllesmereUI.IS_121 then
                    filterItems = {
                        { key = "raidFrames",        label = "Raid Frames",        tooltip = "Shows only the Debuffs that appear on Raid Frames" },
                        { key = "raidInCombat",      label = "Raid (In Combat)",   tooltip = "Shows only auras flagged for raid frames during combat" },
                        { key = "dispellable",       label = "Dispellable",        tooltip = "Shows only auras with a dispel type you can dispel" },
                        { key = "crowdControl",      label = "Crowd Control",      tooltip = "Shows only crowd-control auras" },
                        { key = "bigDefensive",      label = "Big Defensive",      tooltip = "Shows only major defensive cooldowns" },
                        { key = "externalDefensive", label = "External Defensive", tooltip = "Shows only external defensive cooldowns cast on the unit" },
                        { key = "bossAura",          label = "Boss Auras",         tooltip = "Shows only debuffs applied by bosses" },
                        { key = "roleAura",          label = "Role Auras",         tooltip = "Shows only debuffs flagged for your role" },
                        { key = "priorityAura",      label = "Priority",           tooltip = "Shows only priority debuffs" },
                        { key = "ownOnly",           label = "Own Only",           tooltip = "Shows only the Debuffs you apply" },
                    }
                    DEBUFF_FILTER_KEYS = { ownOnly = "onlyPlayerDebuffs", raidFrames = "debuffRaid", raidInCombat = "debuffRaidInCombat", dispellable = "debuffDispellable", crowdControl = "debuffCrowdControl", bigDefensive = "debuffBigDefensive", externalDefensive = "debuffExternalDefensive", bossAura = "debuffBossAura", roleAura = "debuffRoleAura", priorityAura = "debuffPriorityAura" }
                    buffFilterItems = {
                        { key = "raidFrames",        label = "Raid Frames",        tooltip = "Shows only the Buffs that appear on Raid Frames" },
                        { key = "raidInCombat",      label = "Raid (In Combat)",   tooltip = "Shows only auras flagged for raid frames during combat" },
                        { key = "dispellable",       label = "Dispellable",        tooltip = "Shows only auras with a dispel type you can dispel" },
                        { key = "crowdControl",      label = "Crowd Control",      tooltip = "Shows only crowd-control auras" },
                        { key = "bigDefensive",      label = "Big Defensive",      tooltip = "Shows only major defensive cooldowns" },
                        { key = "externalDefensive", label = "External Defensive", tooltip = "Shows only external defensive cooldowns cast on the unit" },
                        { key = "cancelable",        label = "Cancelable",         tooltip = "Shows only buffs that can be canceled" },
                        { key = "stealable",         label = "Stealable",          tooltip = "Shows only buffs you can spellsteal or purge" },
                        { key = "ownOnly",           label = "Own Only",           tooltip = "Shows only the Buffs you apply" },
                    }
                    BUFF_FILTER_KEYS = { ownOnly = "onlyPlayerBuffs", raidFrames = "buffRaid", raidInCombat = "buffRaidInCombat", dispellable = "buffDispellable", crowdControl = "buffCrowdControl", bigDefensive = "buffBigDefensive", externalDefensive = "buffExternalDefensive", cancelable = "buffCancelable", stealable = "buffStealable" }
                else
                    filterItems = {
                        { key = "raidFrames",        label = "Raid Frames",        tooltip = "Shows only the Debuffs that appear on Raid Frames" },
                        { key = "crowdControl",      label = "Crowd Control",      tooltip = "Shows only crowd-control auras" },
                        { key = "bigDefensive",      label = "Big Defensive",      tooltip = "Shows only major defensive cooldowns" },
                        { key = "externalDefensive", label = "External Defensive", tooltip = "Shows only external defensive cooldowns cast on the unit" },
                        { key = "ownOnly",           label = "Own Only",           tooltip = "Shows only the Debuffs you apply" },
                    }
                    DEBUFF_FILTER_KEYS = { ownOnly = "onlyPlayerDebuffs", raidFrames = "debuffRaid", crowdControl = "debuffCrowdControl", bigDefensive = "debuffBigDefensive", externalDefensive = "debuffExternalDefensive" }
                end
                -- Debuff Size | Debuff Text Size: the debuff sizing pair
                -- (mirrors the buff pair on the row above). Debuff Text Size
                -- gates on the "Show Duration" toggle inside its Duration &
                -- Stack cog (which also holds Duration X/Y + Stack
                -- size/position/X/Y). HIDDEN entirely while the debuff
                -- column's effective Location is None (see BossDebuffRowShown;
                -- the dropdown setters above force the rebuild on flips).
                if BossDebuffRowShown() then
                local debuffTextOff = function()
                    return not BossDebuffLocationActive()
                    or not db.profile.boss.debuffShowCooldownText
                end
                local textSizeRow
                textSizeRow, hh = Ww:DualRow(pp, yy,
                    { type="slider", text="Debuff Size", min=10, max=70, step=1,
                      disabled=bossDebuffSizeOff,
                      disabledTooltip=function()
                          if ns.GetBossSimpleDebuffMode(db.profile.boss) ~= "none" then
                              return EllesmereUI.DisabledTooltip("Simple Debuff Display", "disabled")
                          end
                          return EllesmereUI.DisabledTooltip("Debuffs Location")
                      end,
                      rawTooltip=true,
                      getValue=function() return db.profile.boss.debuffSize or 22 end,
                      setValue=function(v)
                          db.profile.boss.debuffSize = v; ReloadAndUpdate()
                          if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
                      end },
                    { type="slider", text="Debuff Text Size", min=6, max=100, step=1, trackWidth=120,
                      disabled=debuffTextOff, disabledTooltip="Show Duration (Inside Cog)",
                      getValue=function() return db.profile.boss.debuffCooldownTextSize or 10 end,
                      setValue=function(v) db.profile.boss.debuffCooldownTextSize = v; ReloadAndUpdate() end });  yy = yy - hh
                do  -- Directions cog on Debuff Size (X/Y cluster offset)
                    local _, dSizeCog = EllesmereUI.BuildCogPopup({ title = "Debuff Position", rows = {
                        { type="slider", label="Offset X", min=-200, max=200, step=1,
                          get=function() return db.profile.boss.debuffOffsetX or 0 end,
                          set=function(v) db.profile.boss.debuffOffsetX = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                        { type="slider", label="Offset Y", min=-200, max=200, step=1,
                          get=function() return db.profile.boss.debuffOffsetY or 0 end,
                          set=function(v) db.profile.boss.debuffOffsetY = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                        -- Physical-pixel-perfect gap between the boss debuff icons.
                        { type="slider", pixel=true, label="Spacing", min=-1, max=10, step=1,
                          get=function() return db.profile.boss.debuffSpacing or 1 end,
                          set=function(v) db.profile.boss.debuffSpacing = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    } })
                    BossCogBtn(textSizeRow._leftRegion, dSizeCog, EllesmereUI.DIRECTIONS_ICON, bossDebuffSizeOff)
                end
                do  -- Icon Zoom cog on Debuff Size
                    local bossDebuffZoomOff = function() return (db.profile.boss.debuffAnchor or "bottomleft") == "none" end
                    local _, dZoomCog = EllesmereUI.BuildCogPopup({ title = "Icon Zoom", rows = {
                        { type="slider", label="Zoom", min=0, max=0.20, step=0.01,
                          get=function() return db.profile.boss.debuffIconZoom or 0.07 end,
                          set=function(v) db.profile.boss.debuffIconZoom = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    } })
                    BossCogBtn(textSizeRow._leftRegion, dZoomCog, nil, bossDebuffZoomOff)
                end
                -- Debuff Text Size cog (right): Show Duration + Duration X/Y + Stack.
                -- Disabled while Simple Debuff Display is active.
                do
                    local rightRgn = textSizeRow._rightRegion
                    -- Inline Duration + Stack text-color swatches on the Debuff Text
                    -- Size slider; greyed + mouse-disabled on the same condition as
                    -- the row's cog.
                    local debuffOff = function() return not BossDebuffLocationActive() end
                    do
                        local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                            function() local c = db.profile.boss.debuffCooldownTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                            function(r, g, b) db.profile.boss.debuffCooldownTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                        sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Duration Text Color") end)
                        sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                        PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                        rightRgn._lastInline = sw
                        local function apply() upd(); local o = debuffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                        apply(); EllesmereUI.RegisterWidgetRefresh(apply)
                    end
                    do
                        local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                            function() local c = db.profile.boss.debuffStackTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                            function(r, g, b) db.profile.boss.debuffStackTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                        sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Stack Text Color") end)
                        sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                        PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                        rightRgn._lastInline = sw
                        local function apply() upd(); local o = debuffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                        apply(); EllesmereUI.RegisterWidgetRefresh(apply)
                    end
                    local _, debuffStackCogShow = EllesmereUI.BuildCogPopup({
                        title = "Duration & Stack",
                        rows = {
                            { type="toggle", label="Show Duration",
                              get=function() return db.profile.boss.debuffShowCooldownText end,
                              set=function(v) db.profile.boss.debuffShowCooldownText = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                            { type="slider", label="Duration X", min=-100, max=100, step=1,
                              get=function() return db.profile.boss.debuffCooldownTextOffsetX or 0 end,
                              set=function(v) db.profile.boss.debuffCooldownTextOffsetX = v; ReloadAndUpdate() end },
                            { type="slider", label="Duration Y", min=-100, max=100, step=1,
                              get=function() return db.profile.boss.debuffCooldownTextOffsetY or 0 end,
                              set=function(v) db.profile.boss.debuffCooldownTextOffsetY = v; ReloadAndUpdate() end },
                            { type="slider", label="Stack Size", min=6, max=100, step=1,
                              get=function() return db.profile.boss.debuffStackTextSize or 14 end,
                              set=function(v) db.profile.boss.debuffStackTextSize = v; ReloadAndUpdate() end },
                            { type="dropdown", label="Stack Position",
                              values={ bottomright="Bottom Right", bottomleft="Bottom Left", topright="Top Right", topleft="Top Left", center="Center" },
                              order={ "bottomright", "bottomleft", "topright", "topleft", "center" },
                              get=function() return db.profile.boss.debuffStackTextPosition or "bottomright" end,
                              set=function(v) db.profile.boss.debuffStackTextPosition = v; ReloadAndUpdate() end },
                            { type="slider", label="Stack X", min=-100, max=100, step=1,
                              get=function() return db.profile.boss.debuffStackTextOffsetX or 0 end,
                              set=function(v) db.profile.boss.debuffStackTextOffsetX = v; ReloadAndUpdate() end },
                            { type="slider", label="Stack Y", min=-100, max=100, step=1,
                              get=function() return db.profile.boss.debuffStackTextOffsetY or 0 end,
                              set=function(v) db.profile.boss.debuffStackTextOffsetY = v; ReloadAndUpdate() end },
                        },
                    })
                    -- Disabled while Simple Debuff Display is active: simple mode
                    -- uses its own (simpleDebuff*) cooldown text, so the regular
                    -- debuff Duration & Stack controls do not apply.
                    BossCogBtn(rightRgn, debuffStackCogShow, nil, debuffOff)
                end
                end   -- close debuff sizing row hidden-while-None gate

                -- Built alongside the aura controls, then appended at the end
                -- of this section to keep border settings consistently last.
                local function AddBossAuraBorderSettings()
                    local B = db.profile.boss
                    local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
                    local sizeValues = { none="None", thin="Thin", normal="Normal", heavy="Heavy", strong="Strong" }
                    local sizeOrder = { "none", "thin", "normal", "heavy", "strong" }
                    local toNumber = { none=0, thin=1, normal=2, heavy=3, strong=4 }
                    local toSize = { [0]="none", [1]="thin", [2]="normal", [3]="heavy", [4]="strong" }
                    local borderRow
                    borderRow, hh = Ww:DualRow(pp, yy,
                        { type="dropdown", text="Border Style", values=texValues, order=texOrder,
                          getValue=function() return B.auraBorderTexture or "solid" end,
                          setValue=function(v)
                              local color, behind, behindUnitFrame = EllesmereUI.GetBorderStyleSelectDefaults(v)
                              B.auraBorderTexture = v
                              B.auraBorderTextureOffset = nil; B.auraBorderTextureOffsetY = nil
                              B.auraBorderTextureShiftX = nil; B.auraBorderTextureShiftY = nil
                              B.auraBorderBehind = behind
                              B.auraBorderBehindUnitFrame = behindUnitFrame
                              B.auraBorderR=color.r; B.auraBorderG=color.g; B.auraBorderB=color.b; B.auraBorderA=1
                              local ds=EllesmereUI.GetBorderDefaultSize("unitframes",v); if ds then B.auraBorderSize=ds end
                              ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
                          end },
                        { type="dropdown", text="Border Size", values=sizeValues, order=sizeOrder,
                          getValue=function() return toSize[B.auraBorderSize or 1] or "thin" end,
                          setValue=function(v) B.auraBorderSize=toNumber[v] or 1; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end }
                    ); yy = yy - hh
                    do
                        local rgn=borderRow._leftRegion
                        local _,show=EllesmereUI.BuildCogPopup({ title="Border Offset", rows={
                            { type="slider",label="Offset X",min=-10,max=10,step=1,
                              get=function() local v=B.auraBorderTextureOffset;if v~=nil then return v end;return EllesmereUI.GetBorderDefaults("unitframes",B.auraBorderTexture or "solid",B.auraBorderSize or 1) end,
                              set=function(v) B.auraBorderTextureOffset=v;ReloadAndUpdate() end },
                            { type="slider",label="Offset Y",min=-10,max=10,step=1,
                              get=function() local v=B.auraBorderTextureOffsetY;if v~=nil then return v end;local _,y=EllesmereUI.GetBorderDefaults("unitframes",B.auraBorderTexture or "solid",B.auraBorderSize or 1);return y end,
                              set=function(v) B.auraBorderTextureOffsetY=v;ReloadAndUpdate() end },
                            { type="slider",label="Shift X",min=-10,max=10,step=1,
                              get=function() local v=B.auraBorderTextureShiftX;if v~=nil then return v end;local _,_,x=EllesmereUI.GetBorderDefaults("unitframes",B.auraBorderTexture or "solid",B.auraBorderSize or 1);return x end,
                              set=function(v) B.auraBorderTextureShiftX=v==0 and nil or v;ReloadAndUpdate() end },
                            { type="slider",label="Shift Y",min=-10,max=10,step=1,
                              get=function() local v=B.auraBorderTextureShiftY;if v~=nil then return v end;local _,_,_,y=EllesmereUI.GetBorderDefaults("unitframes",B.auraBorderTexture or "solid",B.auraBorderSize or 1);return y end,
                              set=function(v) B.auraBorderTextureShiftY=v==0 and nil or v;ReloadAndUpdate() end },
                            { type="toggle",label="Show Behind",get=function() return B.auraBorderBehind or false end,set=function(v) B.auraBorderBehind=v;ReloadAndUpdate() end },
                            { type="toggle",label="Behind Unit Frame",get=function() return B.auraBorderBehindUnitFrame or false end,set=function(v) B.auraBorderBehindUnitFrame=v;ReloadAndUpdate() end },
                        } })
                        local btn=BossCogBtn(rgn,show,EllesmereUI.DIRECTIONS_ICON)
                        local function vis() if (B.auraBorderTexture or "solid")=="solid" then btn:Hide() else btn:Show() end end
                        EllesmereUI.RegisterWidgetRefresh(vis);vis()
                    end
                    do
                        local rgn=borderRow._rightRegion
                        local sw,upd=EllesmereUI.BuildColorSwatch(rgn,borderRow:GetFrameLevel()+3,
                            function() return B.auraBorderR or 0,B.auraBorderG or 0,B.auraBorderB or 0,B.auraBorderA or 1 end,
                            function(r,g,b,a) B.auraBorderR=r;B.auraBorderG=g;B.auraBorderB=b;B.auraBorderA=a;ReloadAndUpdate() end,true,20)
                        PP.Point(sw,"RIGHT",rgn._control,"LEFT",-8,0)
                        EllesmereUI.RegisterWidgetRefresh(upd)
                    end
                end
                AddBossAuraBorderSettings()
                -- Boss Debuff Filter in slot 1. The right slot is the
                -- 12.1-only Boss Buff Filter; on 12.0 it stays the blank
                -- label it is today (boss buffs are never filtered there).
                local filterRow
                local filterOff = function()
                    local p = db.profile.boss
                    return ns.GetBossSimpleDebuffMode(p) == "none" and (p.debuffAnchor or "bottomleft") == "none"
                end
                local buffFilterOff
                local bossFilterRightSlot = { type="label", text="" }
                if EllesmereUI.IS_121 then
                    buffFilterOff = function()
                        local p = db.profile.boss
                        return ns.GetBossSimpleBuffMode(p) == "none" and not p.showBuffs
                    end
                    bossFilterRightSlot = { type="dropdown", text="Boss Buff Filter",
                      disabled=buffFilterOff, disabledTooltip="Buffs", requireState="displayed",
                      values={ __placeholder="..." }, order={ "__placeholder" },
                      getValue=function() return "__placeholder" end, setValue=function() end }
                end
                filterRow, hh = Ww:DualRow(pp, yy,
                    { type="dropdown", text="Boss Debuff Filter",
                      disabled=filterOff, disabledTooltip="Debuffs", requireState="displayed",
                      values={ __placeholder="..." }, order={ "__placeholder" },
                      getValue=function() return "__placeholder" end, setValue=function() end },
                    bossFilterRightSlot);  yy = yy - hh
                do
                    local rgn = filterRow._leftRegion
                    if rgn._control then rgn._control:Hide() end
                    local cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                        rgn, 210, rgn:GetFrameLevel() + 2, filterItems,
                        function(k) return db.profile.boss[DEBUFF_FILTER_KEYS[k]] or false end,
                        function(k, v) db.profile.boss[DEBUFF_FILTER_KEYS[k]] = v; ReloadAndUpdate() end)
                    PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
                    rgn._control = cbDD; rgn._lastInline = nil
                    EllesmereUI.RegisterWidgetRefresh(cbRefresh)
                    -- Disable the filter when no debuffs are shown at all (Simple
                    -- Debuff Display None + Debuffs Location None): nothing to
                    -- filter. A block frame intercepts mouse and shows the
                    -- requirement tooltip while the dropdown is greyed.
                    local filterBlock = CreateFrame("Frame", nil, cbDD)
                    filterBlock:SetAllPoints()
                    filterBlock:SetFrameLevel(cbDD:GetFrameLevel() + 10)
                    filterBlock:EnableMouse(true)
                    filterBlock:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(cbDD, EllesmereUI.DisabledTooltip("Debuffs", "displayed"))
                    end)
                    filterBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    local function UpdateFilterDisabled()
                        local off = filterOff()
                        if off then
                            cbDD:SetAlpha(0.3); filterBlock:Show()
                        else
                            cbDD:SetAlpha(1); filterBlock:Hide()
                        end
                    end
                    UpdateFilterDisabled()
                    EllesmereUI.RegisterWidgetRefresh(UpdateFilterDisabled)
                end
                -- Right slot: Boss Buff Filter (12.1 only; mirror of the
                -- debuff dropdown).
                if EllesmereUI.IS_121 then
                    local rgn = filterRow._rightRegion
                    if rgn._control then rgn._control:Hide() end
                    local cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                        rgn, 210, rgn:GetFrameLevel() + 2, buffFilterItems,
                        function(k) return db.profile.boss[BUFF_FILTER_KEYS[k]] or false end,
                        function(k, v) db.profile.boss[BUFF_FILTER_KEYS[k]] = v; ReloadAndUpdate() end)
                    PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
                    rgn._control = cbDD; rgn._lastInline = nil
                    EllesmereUI.RegisterWidgetRefresh(cbRefresh)
                    local buffFilterBlock = CreateFrame("Frame", nil, cbDD)
                    buffFilterBlock:SetAllPoints()
                    buffFilterBlock:SetFrameLevel(cbDD:GetFrameLevel() + 10)
                    buffFilterBlock:EnableMouse(true)
                    buffFilterBlock:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(cbDD, EllesmereUI.DisabledTooltip("Buffs", "displayed"))
                    end)
                    buffFilterBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    local function UpdateBuffFilterDisabled()
                        if buffFilterOff() then
                            cbDD:SetAlpha(0.3); buffFilterBlock:Show()
                        else
                            cbDD:SetAlpha(1); buffFilterBlock:Hide()
                        end
                    end
                    UpdateBuffFilterDisabled()
                    EllesmereUI.RegisterWidgetRefresh(UpdateBuffFilterDisabled)
                end
            end

            -- Cogwheel on Buffs Location (disabled while Simple Buff Display
            -- overrides placement, or when Buffs Location is None)
            do
                local leftRgn = bossAuraRow._leftRegion
                local _, bBuffCogShowRaw = EllesmereUI.BuildCogPopup({
                    title = "Buff Settings",
                    rows = {
                        { type="dropdown", label="Growth Direction", values=buffGrowthValues, order=buffGrowthOrder,
                          get=function() return db.profile.boss.buffGrowth or "auto" end,
                          set=function(v) db.profile.boss.buffGrowth = v; ReloadAndUpdate() end },
                        { type="slider", label="Max Count", min=1, max=20, step=1,
                          get=function() return db.profile.boss.maxBuffs or 4 end,
                          set=function(v) db.profile.boss.maxBuffs = v; ReloadAndUpdate() end },
                    },
                })
                local cogBtn = BossCogBtn(leftRgn, bBuffCogShowRaw)
                if cogBtn then
                    local cogBlock = CreateFrame("Frame", nil, cogBtn)
                    cogBlock:SetAllPoints()
                    cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10)
                    cogBlock:EnableMouse(true)
                    cogBlock:SetScript("OnEnter", function()
                        if ns.GetBossSimpleBuffMode(db.profile.boss) ~= "none" then
                            EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Simple Buff Display", "disabled"))
                        else
                            EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Buffs Location"))
                        end
                    end)
                    cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    local function UpdateBuffCogDisabled()
                        local off = bossBuffSizeOff()
                        if off then
                            cogBtn:SetAlpha(0.15)
                            cogBlock:Show()
                        else
                            cogBtn:SetAlpha(0.4)
                            cogBlock:Hide()
                        end
                    end
                    UpdateBuffCogDisabled()
                    EllesmereUI.RegisterWidgetRefresh(UpdateBuffCogDisabled)
                end
            end

            -- Cogwheel on Debuffs Location (hidden when Simple Debuff Display overrides placement)
            do
                local rightRgn = bossAuraRow._rightRegion
                local _, bDebuffCogShowRaw = EllesmereUI.BuildCogPopup({
                    title = "Debuff Settings",
                    rows = {
                        { type="dropdown", label="Growth Direction", values=buffGrowthValues, order=buffGrowthOrder,
                          get=function() return db.profile.boss.debuffGrowth or "auto" end,
                          set=function(v) db.profile.boss.debuffGrowth = v; ReloadAndUpdate() end },
                        { type="slider", label="Max Count", min=1, max=20, step=1,
                          get=function() return db.profile.boss.maxDebuffs or 10 end,
                          set=function(v) db.profile.boss.maxDebuffs = v; ReloadAndUpdate() end },
                    },
                })
                local cogBtn = BossCogBtn(rightRgn, bDebuffCogShowRaw)
                if cogBtn then
                    local cogBlock = CreateFrame("Frame", nil, cogBtn)
                    cogBlock:SetAllPoints()
                    cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10)
                    cogBlock:EnableMouse(true)
                    cogBlock:SetScript("OnEnter", function()
                        if ns.GetBossSimpleDebuffMode(db.profile.boss) ~= "none" then
                            EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Simple Debuff Display", "disabled"))
                        else
                            EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Debuffs Location"))
                        end
                    end)
                    cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    local function UpdateDebuffCogDisabled()
                        local p = db.profile.boss
                        local off = ns.GetBossSimpleDebuffMode(p) ~= "none" or (p.debuffAnchor or "bottomleft") == "none"
                        if off then
                            cogBtn:SetAlpha(0.15)
                            cogBlock:Show()
                        else
                            cogBtn:SetAlpha(0.4)
                            cogBlock:Hide()
                        end
                    end
                    UpdateDebuffCogDisabled()
                    EllesmereUI.RegisterWidgetRefresh(UpdateDebuffCogDisabled)
                end

            end

            -- Buff/Debuff text colors now live as inline swatches on the Buff Text
            -- Size / Debuff Text Size sliders above (Duration + Stack per side).

            return yy
        end

        -- New "Indicators" section, rendered at the BOTTOM (below the Power Bar)
        -- via opts.afterPowerRow. Holds the non-aura indicators moved out of the
        -- Buffs and Debuffs section above.
        local function bossIndicators(Ww, pp, yy)
            local hh
            local function ICogBtn(rgn, showFn)
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                cogBtn:SetAlpha(0.4)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints()
                cogTex:SetTexture(EllesmereUI.COGS_ICON)
                cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                cogBtn:SetScript("OnClick", function(self) showFn(self) end)
                return cogBtn
            end

            _, hh = Ww:SectionHeader(pp, "Indicators", yy);  yy = yy - hh

            -- Row 1: Out of Range Alpha | Spell Target
            -- (Out of Range read live by the range ticker, so no reload needed.)
            _, hh = Ww:DualRow(pp, yy,
                { type="slider", text="Out of Range Alpha", min=10, max=100, step=1,
                  tooltip="Fades boss frames when the boss is out of range of your spells. Set to 100% to disable the fade.",
                  getValue=function() return math.floor(((db.profile.boss.oorAlpha or 0.4) * 100) + 0.5) end,
                  setValue=function(v) db.profile.boss.oorAlpha = v / 100 end },
                { type="toggle", text="Spell Target",
                  tooltip = "Show the name of who the boss is casting on.",
                  getValue=function() return db.profile.boss.showCastTarget == true end,
                  setValue=function(v)
                      db.profile.boss.showCastTarget = v
                      ReloadAndUpdate()
                  end });  yy = yy - hh

            -- Row 2: Show Raid Marker | Raid Marker Size (+ position cog)
            local function bossRmOff()
                return db.profile.boss.raidMarkerEnabled == false
            end
            local bossRmRow
            bossRmRow, hh = Ww:DualRow(pp, yy,
                { type="toggle", text="Show Raid Marker",
                  tooltip="Shows the raid target marker icon on boss frames.",
                  getValue=function() return db.profile.boss.raidMarkerEnabled ~= false end,
                  setValue=function(v)
                    db.profile.boss.raidMarkerEnabled = v
                    ReloadAndUpdate()
                    EllesmereUI:RefreshPage()
                  end },
                { type="slider", text="Raid Marker Size", min=12, max=48, step=1,
                  disabled=bossRmOff, disabledTooltip="Raid Marker",
                  getValue=function() return db.profile.boss.raidMarkerSize or 28 end,
                  setValue=function(v) db.profile.boss.raidMarkerSize = v; ReloadAndUpdate() end });  yy = yy - hh
            do
                local _, bossRmCogShow = EllesmereUI.BuildCogPopup({
                    title = "Raid Marker Position",
                    rows = {
                        { type="slider", label="X Offset", min=-50, max=50, step=1,
                          get=function() return db.profile.boss.raidMarkerX or 0 end,
                          set=function(v) db.profile.boss.raidMarkerX = v; ReloadAndUpdate() end },
                        { type="slider", label="Y Offset", min=-50, max=50, step=1,
                          get=function() return db.profile.boss.raidMarkerY or 0 end,
                          set=function(v) db.profile.boss.raidMarkerY = v; ReloadAndUpdate() end },
                        { type="dropdown", label="Alignment", values={ left="Left", center="Center", right="Right" }, order={ "left", "center", "right" },
                          get=function() return db.profile.boss.raidMarkerAlign or "left" end,
                          set=function(v) db.profile.boss.raidMarkerAlign = v; ReloadAndUpdate() end },
                    },
                })
                ICogBtn(bossRmRow._leftRegion, bossRmCogShow)
            end

            return yy
        end

        -- CAST BAR section, rendered below the Power Bar. Mirrors the player cast
        -- bar's Show Cast Bar / Height / Bar Background / Spell Name / Duration /
        -- Reverse Fill settings. All keys are boss-scoped (db.profile.boss.*) and read
        -- by the shared castbar runtime + preview, so they live-update both. "Show Cast
        -- Bar" off (showCastbar=false) hides the cast bar entirely (runtime disables the
        -- Castbar element; preview gives it zero height).
        local function bossCastBar(Ww, pp, yy)
            local B = db.profile.boss
            local hh
            -- Inline cog-button helper (boss-section style).
            local function CCogBtn(rgn, showFn, iconPath)
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                cogBtn:SetAlpha(0.4)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints()
                cogTex:SetTexture(iconPath or EllesmereUI.COGS_ICON)
                cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                cogBtn:SetScript("OnClick", function(self) showFn(self) end)
                return cogBtn
            end

            -- The Show Cast Bar toggle gates the rest of the section. AddCastBlock
            -- greys a region (its slider/dropdown/toggle plus any inline swatch or
            -- cog) to 0.3 and drops an invisible mouse-blocker over it while the
            -- cast bar is off, tracking the toggle live via the widget-refresh fast
            -- path. Mirrors AddDarkModeBlock. The Show Cast Bar toggle's own fill
            -- swatch is gated on its own so the toggle itself stays interactive.
            local castFillSwatch
            local function AddCastBlock(rgn)
                if not rgn then return end
                local block = CreateFrame("Frame", nil, rgn)
                block:SetAllPoints()
                block:SetFrameLevel(rgn:GetFrameLevel() + 50)
                block:EnableMouse(true)
                block:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(block, EllesmereUI.DisabledTooltip("Show Cast Bar"))
                end)
                block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function Update()
                    if B.showCastbar == false then
                        rgn:SetAlpha(0.3); block:Show()
                    else
                        rgn:SetAlpha(1); block:Hide()
                    end
                end
                Update()
                EllesmereUI.RegisterWidgetRefresh(Update)
            end

            bossCastHeader, hh = Ww:SectionHeader(pp, "CAST BAR", yy);  yy = yy - hh

            -- Row 1: Show Cast Bar (+ inline fill-color swatch) | Cast Bar Height
            castMainRow, hh = Ww:DualRow(pp, yy,
                { type="toggle", text="Show Cast Bar",
                  getValue=function() return B.showCastbar ~= false end,
                  -- DependentSetValue: rows 2-4 below are hidden while the
                  -- cast bar is off; the flip forces the full rebuild.
                  setValue=EllesmereUI.DependentSetValue(
                      function() return B.showCastbar ~= false end,
                      function(v) B.showCastbar = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end) },
                { type="slider", text="Cast Bar Height", min=1, max=40, step=1,
                  disabled=function() return B.showCastbar == false end,
                  disabledTooltip="Show Cast Bar",
                  getValue=function() return B.castbarHeight or 14 end,
                  setValue=function(v) B.castbarHeight = v; ReloadAndUpdate() end });  yy = yy - hh
            -- Inline fill-color swatch on Show Cast Bar (left region).
            do
                local rgn = castMainRow._leftRegion
                local sw = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                    function() local c = B.castbarFillColor or { r=0.863, g=0.820, b=0.639 }; return c.r, c.g, c.b end,
                    function(r, g, b) B.castbarFillColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                sw:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                sw:SetScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, "Fill Color") end)
                sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                rgn._lastInline = sw
                castFillSwatch = sw
            end
            -- Inline cog on Show Cast Bar (left region): Offset X/Y nudge the whole
            -- cast bar (positive = right/up). Updates the live frames + both
            -- previews via ReloadAndUpdate + the boss preview refresh.
            do
                local _, offCogShow = EllesmereUI.BuildCogPopup({
                    title = "Cast Bar Position",
                    rows = {
                        { type="slider", label="Offset X", min=-500, max=500, step=1,
                          get=function() return B.castbarOffsetX or 0 end,
                          set=function(v) B.castbarOffsetX = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                        { type="slider", label="Offset Y", min=-200, max=200, step=1,
                          get=function() return B.castbarOffsetY or 0 end,
                          set=function(v) B.castbarOffsetY = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    },
                })
                AddCastBlock(CCogBtn(castMainRow._leftRegion, offCogShow, EllesmereUI.DIRECTIONS_ICON))
            end

            -- Rows 2-4 are HIDDEN entirely while Show Cast Bar is off (the
            -- toggle's DependentSetValue forces the rebuild on flips). The
            -- master row's own inlines (fill swatch, offset cog) keep the
            -- AddCastBlock grey+block treatment instead.
            if B.showCastbar ~= false then
            -- Row 2: Show Cast Icon (+ icon cog) | Cast Bar Width (right under Cast
            -- Bar Height so the two dimensions sit stacked in the same column)
            growthRow, hh = Ww:DualRow(pp, yy,
                { type="toggle", text="Show Cast Icon",
                  getValue=function() return B.showCastIcon ~= false end,
                  setValue=function(v) B.showCastIcon = v; ReloadAndUpdate() end },
                { type="slider", text="Cast Bar Width", min=0, max=500, step=1,
                  tooltip="Sets a custom width for the cast bar. Set to 0 to match the boss frame width.",
                  getValue=function() return B.castbarWidth or 0 end,
                  -- Custom widths floor at 30 (matches the unlock-mode resize
                  -- minimum): below the cast icon size the bar layout inverts.
                  setValue=function(v) if v > 0 and v < 30 then v = 30 end; B.castbarWidth = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end });  yy = yy - hh
            -- Icon cog (left): "Make Icon Part of the Bar" / "Show Icon on Right".
            do
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Cast Icon",
                    rows = {
                        { type = "toggle", label = "Make Icon Part of the Bar",
                          tooltip = "This makes it so the width of the cast bar includes the icon, rather than placing it to the left of the cast bars width.",
                          get = function() return B.castbarIconInWidth ~= false end,
                          set = function(v) B.castbarIconInWidth = v; ReloadAndUpdate() end },
                        { type = "toggle", label = "Show Icon on Right",
                          tooltip = "Place the cast icon on the right side of the bar instead of the left.",
                          get = function() return B.castbarIconRight == true end,
                          set = function(v) B.castbarIconRight = v; ReloadAndUpdate() end },
                    },
                })
                CCogBtn(growthRow._leftRegion, cogShow)
            end
            -- Row 3: Reverse Fill | Bar Background (opacity slider + color swatch).
            -- Bar Background sits right below the size sliders (mirrors the main
            -- frames' cast bar section, where it follows the Height row).
            local reverseRow
            reverseRow, hh = Ww:DualRow(pp, yy,
                { type="toggle", text="Reverse Fill",
                  getValue=function() return B.castReverseFill == true end,
                  setValue=function(v) B.castReverseFill = v; ReloadAndUpdate() end },
                { type="slider", text="Bar Background", min=0, max=100, step=1,
                  getValue=function() return math.floor((B.castBgAlpha or 0.5) * 100 + 0.5) end,
                  setValue=function(v) B.castBgAlpha = v / 100; ReloadAndUpdate() end });  yy = yy - hh
            -- Inline color swatch on Bar Background (right region).
            do
                local rgn = reverseRow._rightRegion
                local sw = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                    function()
                        local c = B.castBgColor
                        if c then return c.r, c.g, c.b end
                        return 0, 0, 0
                    end,
                    function(r, g, b) B.castBgColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                sw:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                sw:SetScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, "Cast Background") end)
                sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                rgn._lastInline = sw
            end

            -- Row 4: Spell Name (dropdown + swatch + Size/X/Y cog) | Duration (same)
            local castTextRow
            castTextRow, hh = Ww:DualRow(pp, yy,
                { type="dropdown", text="Spell Name",
                  values={ none="None", left="Left", right="Right", center="Center" },
                  order={ "none", "left", "right", "center" },
                  getValue=function() return B.castSpellNameSide or "left" end,
                  setValue=function(v)
                    B.castSpellNameSide = v
                    -- Conflict rule (mirrors player): name and the spell target may
                    -- not share a side -- setting the name onto the target's side
                    -- turns the target (Indicators) off.
                    if v ~= "none" and (B.showCastTarget ~= false) and (B.castSpellTargetSide or "right") == v then
                        B.showCastTarget = false
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                  end },
                { type="dropdown", text="Duration",
                  values={ none="None", right="Right", left="Left" },
                  order={ "none", "right", "left" },
                  getValue=function()
                    if B.showCastDuration == false then return "none" end
                    return B.castDurationSide or "right"
                  end,
                  setValue=function(v)
                    if v == "none" then
                        B.showCastDuration = false
                    else
                        B.showCastDuration = true
                        B.castDurationSide = v
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                  end });  yy = yy - hh
            -- Spell Name (left): color swatch + Size/X/Y cog
            do
                local rgn = castTextRow._leftRegion
                local sw = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                    function() local c = B.castSpellNameColor or { r=1, g=1, b=1 }; return c.r, c.g, c.b end,
                    function(r, g, b) B.castSpellNameColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                sw:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
                rgn._lastInline = sw
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Spell Name",
                    rows = {
                        { type="slider", label="Size", min=6, max=20, step=1,
                          get=function() return B.castSpellNameSize or 11 end,
                          set=function(v) B.castSpellNameSize = v; ReloadAndUpdate() end },
                        { type="slider", label="X Offset", min=-50, max=50, step=1,
                          get=function() return B.castSpellNameX or 0 end,
                          set=function(v) B.castSpellNameX = v; ReloadAndUpdate() end },
                        { type="slider", label="Y Offset", min=-50, max=50, step=1,
                          get=function() return B.castSpellNameY or 0 end,
                          set=function(v) B.castSpellNameY = v; ReloadAndUpdate() end },
                    },
                })
                CCogBtn(rgn, cogShow)
            end
            -- Duration (right): color swatch + Size/X/Y cog
            do
                local rgn = castTextRow._rightRegion
                local sw = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                    function() local c = B.castDurationColor or { r=1, g=1, b=1 }; return c.r, c.g, c.b end,
                    function(r, g, b) B.castDurationColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                sw:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
                rgn._lastInline = sw
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Duration",
                    rows = {
                        { type="slider", label="Size", min=6, max=20, step=1,
                          get=function() return B.castDurationSize or 10 end,
                          set=function(v) B.castDurationSize = v; ReloadAndUpdate() end },
                        { type="slider", label="X Offset", min=-50, max=50, step=1,
                          get=function() return B.castDurationX or 0 end,
                          set=function(v) B.castDurationX = v; ReloadAndUpdate() end },
                        { type="slider", label="Y Offset", min=-50, max=50, step=1,
                          get=function() return B.castDurationY or 0 end,
                          set=function(v) B.castDurationY = v; ReloadAndUpdate() end },
                    },
                })
                CCogBtn(rgn, cogShow)
            end

            end   -- close boss Cast Bar hidden-while-disabled gate

            -- The Show Cast Bar toggle's own fill swatch stays gated grey +
            -- blocked while the cast bar is off (the Height slider uses a
            -- native disabled state; the hidden rows need nothing).
            if castFillSwatch then AddCastBlock(castFillSwatch) end
            return yy
        end

        local displayHeader, sizeRow, textHeader, textRow
        y, displayHeader, sizeRow, textHeader, textRow = BuildMiniTextAndSize(W, parent, y, db.profile.boss, "boss", enableRow, bossAfterSize, { hasPowerBar = true, afterPowerRow = function(Ww, pp, yy)
            yy = bossCastBar(Ww, pp, yy)
            return bossIndicators(Ww, pp, yy)
        end })

        -- Store click targets for hover highlight system
        parent._ufClickTargets = {
            -- Health bar -> Health Bar Height (sizeRow left, HEALTH BAR section);
            -- Power bar -> Power Bar Height (pwrRow1 left, POWER BAR section).
            healthBar  = { section = textHeader or displayHeader,  target = sizeRow,  slotSide = "left" },
            powerBar   = { section = parent._powerHeaderFrame or displayHeader,  target = parent._powerHeightRow,  slotSide = "left" },
            powerBarText = { section = parent._powerHeaderFrame or displayHeader,  target = parent._powerTextRow,  slotSide = "left" },
            portrait   = { section = displayHeader,  target = portraitRow,   slotSide = "right" },
            nameText   = { section = textHeader or displayHeader,  target = textRow or sizeRow },
            healthText = { section = textHeader or displayHeader,  target = textRow or sizeRow },
            -- Cast bar -> Cast Bar Height; spell icon -> Show Cast Icon. Both live
            -- in growthRow after the swap (Show Cast Icon left, Cast Bar Height right).
            castBar    = { section = bossCastHeader or displayHeader,  target = castMainRow or growthRow,  slotSide = "left" },
            castIcon   = { section = bossCastHeader or displayHeader,  target = growthRow,  slotSide = "left" },
            -- Buffs/Debuffs scroll to the active control: Simple Display when it's
            -- on (the column is forced), otherwise the normal Location dropdown.
            buffIcon   = function()
                if ns.GetBossSimpleBuffMode(db.profile.boss) ~= "none" then
                    return { section = bossAuraHeader or displayHeader, target = simpleBuffRow }
                end
                return { section = bossAuraHeader or displayHeader, target = bossAuraRow, slotSide = "left" }
            end,
            debuffIcon = function()
                if ns.GetBossSimpleDebuffMode(db.profile.boss) ~= "none" then
                    return { section = bossAuraHeader or displayHeader, target = simpleRow }
                end
                return { section = bossAuraHeader or displayHeader, target = bossAuraRow, slotSide = "right" }
            end,
        }

        return abs(y)
    end

    ---------------------------------------------------------------------------
    --  Mini Frames page  (dropdown selector + mini builders)
    ---------------------------------------------------------------------------
    local selectedMiniUnit = "targettarget"
    local miniUnitLabels = {
        ["targettarget"] = "Target of Target",
        ["focustarget"]  = "Focus Target",
        ["pet"]          = "Pet",
    }
    local miniUnitOrder = { "targettarget", "focustarget", "pet" }

    -- Allow Unlock Mode's "Element Options" to pre-select a mini unit before the
    -- Mini Frames page builds (mirrors the Main Frames _setUnitFrameUnit /
    -- _pendingUnitSelect mechanism). Field assignments -- no new locals.
    EllesmereUI._setMiniUnit = function(unit) selectedMiniUnit = unit end
    EllesmereUI._consumePendingMiniSelect = function()
        local pending = EllesmereUI._pendingMiniSelect
        if pending then
            selectedMiniUnit = pending
            EllesmereUI._pendingMiniSelect = nil
        end
    end

    local _miniHeaderBuilder
    local miniHeaderFixedH = 0

    local function BuildMiniPage(pageName, parent, yOffset)
        -- Consume any pending mini selection from Element Options navigation
        if EllesmereUI._consumePendingMiniSelect then EllesmereUI._consumePendingMiniSelect() end

        -- Tag every option registered while building this page with the
        -- currently-selected mini unit, so a global-search jump to a
        -- unit-specific setting can restore this exact selection first via
        -- EllesmereUI._setMiniUnit -- see EUI_CooldownManager_Options.lua's
        -- matching EllesmereUI._buildingSelector comment for the full reasoning.
        EllesmereUI._buildingSelector = { setter = EllesmereUI._setMiniUnit, key = selectedMiniUnit }

        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        activePreview = nil

        -------------------------------------------------------------------
        --  CONTENT HEADER  (dropdown + preview)
        -------------------------------------------------------------------
        _miniHeaderBuilder = function(hdr, hdrW)
            local DD_H = 34
            local fy = -20

            -- Centered dropdown (matches Action Bars Single Bar Edit)
            local ddW = 350
            local ddBtn, ddLbl = EllesmereUI.BuildDropdownControl(
                hdr, ddW, hdr:GetFrameLevel() + 5,
                miniUnitLabels, miniUnitOrder,
                function() return selectedMiniUnit end,
                function(v)
                    selectedMiniUnit = v
                    EllesmereUI:InvalidateContentHeaderCache()
                    EllesmereUI:SetContentHeader(_miniHeaderBuilder)
                    EllesmereUI:RefreshPage(true)
                    EllesmereUI.SmoothScrollTo(0)
                    -- Re-run the preview next frame once the rebuilt layout has
                    -- settled (same fix as the Main Frames unit selector).
                    C_Timer.After(0, UpdatePreview)
                end
            )
            PP.Point(ddBtn, "TOP", hdr, "TOP", 0, fy)
            ddBtn:SetHeight(DD_H)
            fy = fy - DD_H - 20

            local side = unitSide[selectedMiniUnit] or "left"
            local preview = BuildUnitPreview(hdr, selectedMiniUnit, side)
            activePreview = preview
            local previewScale = preview._previewScale or 1
            local initBuffTopPad = preview._buffTopPad or 0
            preview._headerDropdownOY = math.abs(fy)
            preview:ClearAllPoints()
            PP.Point(preview, "TOP", hdr, "TOP", 0, (fy - initBuffTopPad) / previewScale)
            preview._lastOY = (fy - initBuffTopPad) / previewScale
            preview:Update()
            local previewH = preview:GetHeight() * preview:GetScale()
            local buffExtra = preview._buffExtra or 0
            local detTopExtra = preview._detTopExtra or 0
            fy = fy - previewH - buffExtra - detTopExtra - 20
            miniHeaderFixedH = 20 + DD_H + 20 + 20
            if preview then preview._headerFixedH = miniHeaderFixedH end

            local _miniHeaderBaseH = math.abs(fy)
            return _miniHeaderBaseH
        end
        EllesmereUI:SetContentHeader(_miniHeaderBuilder)

        parent._showRowDivider = true

        -------------------------------------------------------------------
        --  Route to mini builders
        -------------------------------------------------------------------
        if selectedMiniUnit == "targettarget" then
            y = -BuildFoTToTOptions(W, parent, y, db.profile.targettarget, "targettarget")
        elseif selectedMiniUnit == "focustarget" then
            y = -BuildFoTToTOptions(W, parent, y, db.profile.focustarget, "focustarget")
        elseif selectedMiniUnit == "pet" then
            y = -BuildPetOptions(W, parent, y)
        end

        -------------------------------------------------------------------
        --  CLICK NAVIGATION
        -------------------------------------------------------------------
        local glowFrame
        local function PlaySettingGlow(targetFrame)
            if not targetFrame then return end
            if not glowFrame then
                glowFrame = CreateFrame("Frame")
                local c = EllesmereUI.ELLESMERE_GREEN
                local function MkEdge()
                    local t = glowFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                    t:SetColorTexture(c.r, c.g, c.b, 1)
                    return t
                end
                glowFrame._top = MkEdge()
                glowFrame._bot = MkEdge()
                glowFrame._lft = MkEdge()
                glowFrame._rgt = MkEdge()
                glowFrame._top:SetHeight(2)
                glowFrame._top:SetPoint("TOPLEFT"); glowFrame._top:SetPoint("TOPRIGHT")
                glowFrame._bot:SetHeight(2)
                glowFrame._bot:SetPoint("BOTTOMLEFT"); glowFrame._bot:SetPoint("BOTTOMRIGHT")
                glowFrame._lft:SetWidth(2)
                glowFrame._lft:SetPoint("TOPLEFT", glowFrame._top, "BOTTOMLEFT")
                glowFrame._lft:SetPoint("BOTTOMLEFT", glowFrame._bot, "TOPLEFT")
                glowFrame._rgt:SetWidth(2)
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

        local function NavigateToSetting(key)
            local targets = parent._ufClickTargets
            if not targets then return end
            local m = targets[key]
            -- A target may be a resolver function (e.g. boss buff/debuff icons,
            -- which point to Simple Display or Location depending on the mode).
            if type(m) == "function" then m = m() end
            if not m or not m.section or not m.target then return end

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

        -- Hit overlay factory
        local function CreateHitOverlay(element, mappingKey, isText, frameLevelOverride, opts)
            local anchor = isText and element:GetParent() or element
            if not anchor.CreateTexture then anchor = anchor:GetParent() end
            local btn = CreateFrame("Button", nil, anchor)
            if isText then
                local function ResizeToText()
                    local ok, tw, th = pcall(function()
                        local w = element:GetStringWidth() or 0
                        local hh = element:GetStringHeight() or 0
                        if w < 4 then w = 4 end
                        if hh < 4 then hh = 4 end
                        return w, hh
                    end)
                    if not ok then tw = 40; th = 12 end
                    btn:SetSize(tw + 4, th + 4)
                end
                ResizeToText()
                local justify = element:GetJustifyH()
                if justify == "RIGHT" then btn:SetPoint("RIGHT", element, "RIGHT", 2, 0)
                elseif justify == "CENTER" then btn:SetPoint("CENTER", element, "CENTER", 0, 0)
                else btn:SetPoint("LEFT", element, "LEFT", -2, 0) end
                btn:SetScript("OnShow", function() ResizeToText() end)
                btn._resizeToText = ResizeToText
            else
                btn:SetAllPoints(opts and opts.hlAnchor or element)
            end
            btn:SetFrameLevel(frameLevelOverride or (anchor:GetFrameLevel() + 20))
            btn:RegisterForClicks("LeftButtonDown")
            local c = EllesmereUI.ELLESMERE_GREEN
            local PP = EllesmereUI.PP
            -- Use a child container so the hover border doesn't conflict with
            -- any existing PP border on the target frame.
            local hlBase = (opts and opts.hlAnchor) or btn
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

        -- Create hit overlays on preview elements
        if activePreview then
            local pv = activePreview
            local baseLevel = (pv._health and pv._health:GetFrameLevel() or 20) + 15
            local textLevel = baseLevel + 10
            if pv._health then CreateHitOverlay(pv._health, "healthBar", false, baseLevel, { hlAnchor = pv._border or pv._health }) end
            if pv._portraitFrame and pv._portraitFrame:IsShown() then CreateHitOverlay(pv._portraitFrame, "portrait", false, baseLevel) end
            if pv._castbar then
                local castLevel = pv._castbar:GetFrameLevel() + 20
                CreateHitOverlay(pv._castbar, "castBar", false, castLevel)
            end
            if pv._nameFS and pv._nameFS:IsShown() then CreateHitOverlay(pv._nameFS, "nameText", true, textLevel) end
            if pv._hpFS and pv._hpFS:IsShown() then CreateHitOverlay(pv._hpFS, "healthText", true, textLevel) end
        end

        return abs(y)
    end

    ---------------------------------------------------------------------------
    --  Boss Frames page  (single-unit page; no unit dropdown -- boss only)
    ---------------------------------------------------------------------------
    -- Stored on ns (not new init-function locals) to stay clear of the Lua 5.1
    -- 200-local cap in this chunk. The header builder mirrors the Mini page's,
    -- minus the unit dropdown (boss is the only unit on this page). The click-
    -- navigation block is the same machinery the Mini page uses.
    ns._bossHeaderBuilder = nil
    ns._BuildBossPage = function(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset

        activePreview = nil

        -------------------------------------------------------------------
        --  CONTENT HEADER  (preview only, no dropdown)
        -------------------------------------------------------------------
        ns._bossHeaderBuilder = function(hdr, hdrW)
            local fy = -20
            local side = unitSide.boss or "right"
            local preview = BuildUnitPreview(hdr, "boss", side)
            activePreview = preview
            local previewScale = preview._previewScale or 1
            local initBuffTopPad = preview._buffTopPad or 0
            preview._headerDropdownOY = math.abs(fy)
            preview:ClearAllPoints()
            PP.Point(preview, "TOP", hdr, "TOP", 0, (fy - initBuffTopPad) / previewScale)
            preview._lastOY = (fy - initBuffTopPad) / previewScale
            preview:Update()
            local previewH = preview:GetHeight() * preview:GetScale()
            local buffExtra = preview._buffExtra or 0
            local detTopExtra = preview._detTopExtra or 0
            fy = fy - previewH - buffExtra - detTopExtra - 20
            preview._headerFixedH = 20 + 20
            return math.abs(fy)
        end
        EllesmereUI:SetContentHeader(ns._bossHeaderBuilder)

        parent._showRowDivider = true

        -------------------------------------------------------------------
        --  Boss section
        -------------------------------------------------------------------
        y = -BuildBossOptions(W, parent, y)

        -------------------------------------------------------------------
        --  CLICK NAVIGATION  (mirrors the Mini Frames page)
        -------------------------------------------------------------------
        local glowFrame
        local function PlaySettingGlow(targetFrame)
            if not targetFrame then return end
            if not glowFrame then
                glowFrame = CreateFrame("Frame")
                local c = EllesmereUI.ELLESMERE_GREEN
                local function MkEdge()
                    local t = glowFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                    t:SetColorTexture(c.r, c.g, c.b, 1)
                    return t
                end
                glowFrame._top = MkEdge()
                glowFrame._bot = MkEdge()
                glowFrame._lft = MkEdge()
                glowFrame._rgt = MkEdge()
                glowFrame._top:SetHeight(2)
                glowFrame._top:SetPoint("TOPLEFT"); glowFrame._top:SetPoint("TOPRIGHT")
                glowFrame._bot:SetHeight(2)
                glowFrame._bot:SetPoint("BOTTOMLEFT"); glowFrame._bot:SetPoint("BOTTOMRIGHT")
                glowFrame._lft:SetWidth(2)
                glowFrame._lft:SetPoint("TOPLEFT", glowFrame._top, "BOTTOMLEFT")
                glowFrame._lft:SetPoint("BOTTOMLEFT", glowFrame._bot, "TOPLEFT")
                glowFrame._rgt:SetWidth(2)
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

        local function NavigateToSetting(key)
            local targets = parent._ufClickTargets
            if not targets then return end
            local m = targets[key]
            -- A target may be a resolver function (e.g. boss buff/debuff icons,
            -- which point to Simple Display or Location depending on the mode).
            if type(m) == "function" then m = m() end
            if not m or not m.section or not m.target then return end

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

        -- Hit overlay factory
        local function CreateHitOverlay(element, mappingKey, isText, frameLevelOverride, opts)
            local anchor = isText and element:GetParent() or element
            if not anchor.CreateTexture then anchor = anchor:GetParent() end
            local btn = CreateFrame("Button", nil, anchor)
            if isText then
                local function ResizeToText()
                    local ok, tw, th = pcall(function()
                        local w = element:GetStringWidth() or 0
                        local hh = element:GetStringHeight() or 0
                        if w < 4 then w = 4 end
                        if hh < 4 then hh = 4 end
                        return w, hh
                    end)
                    if not ok then tw = 40; th = 12 end
                    btn:SetSize(tw + 4, th + 4)
                end
                ResizeToText()
                local justify = element:GetJustifyH()
                if justify == "RIGHT" then btn:SetPoint("RIGHT", element, "RIGHT", 2, 0)
                elseif justify == "CENTER" then btn:SetPoint("CENTER", element, "CENTER", 0, 0)
                else btn:SetPoint("LEFT", element, "LEFT", -2, 0) end
                btn:SetScript("OnShow", function() ResizeToText() end)
                btn._resizeToText = ResizeToText
            else
                btn:SetAllPoints(opts and opts.hlAnchor or element)
            end
            btn:SetFrameLevel(frameLevelOverride or (anchor:GetFrameLevel() + 20))
            btn:RegisterForClicks("LeftButtonDown")
            local c = EllesmereUI.ELLESMERE_GREEN
            local PP = EllesmereUI.PP
            -- Use a child container so the hover border doesn't conflict with
            -- any existing PP border on the target frame.
            local hlBase = (opts and opts.hlAnchor) or btn
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

        -- Create hit overlays on preview elements
        if activePreview then
            local pv = activePreview
            local baseLevel = (pv._health and pv._health:GetFrameLevel() or 20) + 15
            local textLevel = baseLevel + 10
            -- Health bar and power bar are separately clickable, each covering just
            -- its own bar (replacing the old ambiguous whole-frame overlay).
            if pv._health then CreateHitOverlay(pv._health, "healthBar", false, baseLevel) end
            if pv._power then CreateHitOverlay(pv._power, "powerBar", false, baseLevel) end
            if pv._ppFS and pv._ppFS:IsShown() then CreateHitOverlay(pv._ppFS, "powerBarText", true, textLevel) end
            if pv._portraitFrame and pv._portraitFrame:IsShown() then CreateHitOverlay(pv._portraitFrame, "portrait", false, baseLevel) end
            if pv._castbar then
                local castLevel = pv._castbar:GetFrameLevel() + 20
                CreateHitOverlay(pv._castbar, "castBar", false, castLevel)
                -- Spell icon -> Show Cast Icon setting.
                if pv._castIconFrame then CreateHitOverlay(pv._castIconFrame, "castIcon", false, castLevel) end
            end
            if pv._nameFS and pv._nameFS:IsShown() then CreateHitOverlay(pv._nameFS, "nameText", true, textLevel) end
            if pv._hpFS and pv._hpFS:IsShown() then CreateHitOverlay(pv._hpFS, "healthText", true, textLevel) end
            -- Buff/Debuff icons -> their aura settings (Simple Display or Location,
            -- resolved at click time). Overlay every icon so newly shown ones stay
            -- clickable without a header rebuild.
            if pv._buffIcons then
                for i = 1, #pv._buffIcons do
                    if pv._buffIcons[i] then CreateHitOverlay(pv._buffIcons[i], "buffIcon", false, baseLevel) end
                end
            end
            if pv._debuffIcons then
                for i = 1, #pv._debuffIcons do
                    if pv._debuffIcons[i] then CreateHitOverlay(pv._debuffIcons[i], "debuffIcon", false, baseLevel) end
                end
            end
        end

        return abs(y)
    end

    ---------------------------------------------------------------------------
    --  Unlock Mode page  (stub SelectPage intercepts this before buildPage)
    ---------------------------------------------------------------------------
    local function BuildUnlockPage(pageName, parent, yOffset)
        -- SelectPage() intercepts "Unlock Mode" and fires _openUnlockMode directly.
        -- This stub exists only as a safety net in case buildPage is ever called.
        if EllesmereUI._openUnlockMode then
            C_Timer.After(0, EllesmereUI._openUnlockMode)
        end
        return 100
    end


    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    local ufSearchTerms = {}
    for _, label in pairs(unitLabels) do ufSearchTerms[#ufSearchTerms + 1] = label end
    for _, label in pairs(miniUnitLabels) do ufSearchTerms[#ufSearchTerms + 1] = label end
    local _paTerms = { "buff", "debuff", "aura", "player buffs", "player debuffs", "icon zoom", "private auras", "external defensives", "externals", "pain suppression" }
    for _, t in ipairs(_paTerms) do ufSearchTerms[#ufSearchTerms + 1] = t end

    -- Rebuild preview when spec changes (class resource pips may appear/disappear)
    local ufOptSpecFrame = CreateFrame("Frame")
    ufOptSpecFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ufOptSpecFrame:SetScript("OnEvent", function(_, _, unit)
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

    ---------------------------------------------------------------------------
    --  Player Buffs & Debuffs page
    ---------------------------------------------------------------------------
    local function BuildPlayerAurasPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        local function PAGet(key)
            local p = db and db.profile and db.profile.playerAuras
            return p and p[key]
        end
        local function PASet(key, v)
            if not db or not db.profile then return end
            if not db.profile.playerAuras then db.profile.playerAuras = {} end
            db.profile.playerAuras[key] = v
            if ns.RefreshPlayerAuras then ns.RefreshPlayerAuras() end
            if ns.ApplyPlayerAuraScale then ns.ApplyPlayerAuraScale() end
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "PLAYER BUFFS & DEBUFFS", y);  y = y - h

        parent._showRowDivider = true

        -- Row 1: Enable Styled Buffs & Debuffs | Icon Size
        local paRow1
        paRow1, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Styled Buffs & Debuffs",
              getValue = function() return PAGet("enabled") or false end,
              setValue = function(v)
                  PASet("enabled", v)
                  EllesmereUI:ShowConfirmPopup({
                      title   = "Reload Required",
                      message = "This change requires a UI reload to take effect.",
                      confirmText = "Reload Now",
                      cancelText  = "Later",
                      onConfirm = function() ReloadUI() end,
                  })
              end },
            { type = "slider", text = "Icon Size", min = 16, max = 60, step = 1,
              getValue = function() return PAGet("iconSize") or 32 end,
              setValue = function(v) PASet("iconSize", v) end }
        );  y = y - h

        -- Inline cog: Icon Zoom (next to "Icon Size"). Buffs and debuffs
        -- crop independently.
        do
            local rgn = paRow1._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Icon Zoom",
                rows = {
                    { type = "slider", label = "Buff Zoom", min = 0, max = 0.20, step = 0.01,
                      get = function() return PAGet("buffIconZoom") or 0.055 end,
                      set = function(v) PASet("buffIconZoom", v) end },
                    { type = "slider", label = "Debuff Zoom", min = 0, max = 0.20, step = 0.01,
                      get = function() return PAGet("debuffIconZoom") or 0.055 end,
                      set = function(v) PASet("debuffIconZoom", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -- Row 2: Show Text | Text Size (+ inline Duration Format cog)
        local paRow2
        paRow2, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Text",
              getValue = function() return PAGet("showText") ~= false end,
              setValue = function(v) PASet("showText", v) end },
            { type = "slider", text = "Text Size", min = 6, max = 24, step = 1,
              getValue = function() return PAGet("textSize") or 11 end,
              setValue = function(v) PASet("textSize", v) end }
        );  y = y - h

        -- Inline cog: Duration Format (next to "Text Size").
        do
            local rgn = paRow2._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Duration Format",
                rows = {
                    { type = "dropdown", label = "Format",
                      values = {
                          blizzard = { text = "Blizzard Default (2 min)" },
                          compact  = { text = "Standard (5m / 32)" },
                          colon    = { text = "Colon (5:32)" },
                          seconds  = { text = "Seconds (152)" },
                      },
                      order = { "blizzard", "compact", "colon", "seconds" },
                      get = function() return PAGet("durationFormat") or "blizzard" end,
                      set = function(v) PASet("durationFormat", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -- Row 3: Border Style | Border Size (+ inline color swatch)
        do
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local borderSizeValues = {
                none = "None", thin = "Thin", normal = "Normal",
                heavy = "Heavy", strong = "Strong",
            }
            local borderSizeOrder = { "none", "thin", "normal", "heavy", "strong" }
            local borderSizeToNumber = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }
            local borderNumberToSize = { [0] = "none", [1] = "thin", [2] = "normal", [3] = "heavy", [4] = "strong" }
            local bsRow
            bsRow, h = W:DualRow(parent, y,
                { type = "dropdown", text = "Border Style",
                  values = texValues, order = texOrder,
                  getValue = function() return PAGet("borderTexture") or "solid" end,
                  setValue = function(v)
                      local color, behind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                      PASet("borderTexture", v)
                      PASet("borderTextureOffset", nil); PASet("borderTextureOffsetY", nil)
                      PASet("borderTextureShiftX", nil); PASet("borderTextureShiftY", nil)
                      PASet("borderBehind", behind)
                      PASet("borderR", color.r); PASet("borderG", color.g); PASet("borderB", color.b)
                      PASet("borderA", 1)
                      local defSz = EllesmereUI.GetBorderDefaultSize("unitframes", v)
                      if defSz then PASet("borderSize", defSz) end
                  end },
                { type = "dropdown", text = "Border Size",
                  values = borderSizeValues, order = borderSizeOrder,
                  getValue = function()
                      return borderNumberToSize[PAGet("borderSize") or 1] or "thin"
                  end,
                  setValue = function(v) PASet("borderSize", borderSizeToNumber[v] or 1) end }
            );  y = y - h

            -- Textured-border offset and layer controls.
            do
                local rgn = bsRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Border Offset",
                    rows = {
                        { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                          get = function()
                              local v = PAGet("borderTextureOffset")
                              if v ~= nil then return v end
                              return EllesmereUI.GetBorderDefaults("unitframes", PAGet("borderTexture") or "solid", PAGet("borderSize") or 1)
                          end,
                          set = function(v) PASet("borderTextureOffset", v) end },
                        { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                          get = function()
                              local v = PAGet("borderTextureOffsetY")
                              if v ~= nil then return v end
                              local _, oy = EllesmereUI.GetBorderDefaults("unitframes", PAGet("borderTexture") or "solid", PAGet("borderSize") or 1)
                              return oy
                          end,
                          set = function(v) PASet("borderTextureOffsetY", v) end },
                        { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                          get = function()
                              local v = PAGet("borderTextureShiftX")
                              if v ~= nil then return v end
                              local _, _, sx = EllesmereUI.GetBorderDefaults("unitframes", PAGet("borderTexture") or "solid", PAGet("borderSize") or 1)
                              return sx
                          end,
                          set = function(v) PASet("borderTextureShiftX", v == 0 and nil or v) end },
                        { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                          get = function()
                              local v = PAGet("borderTextureShiftY")
                              if v ~= nil then return v end
                              local _, _, _, sy = EllesmereUI.GetBorderDefaults("unitframes", PAGet("borderTexture") or "solid", PAGet("borderSize") or 1)
                              return sy
                          end,
                          set = function(v) PASet("borderTextureShiftY", v == 0 and nil or v) end },
                        { type = "toggle", label = "Show Behind",
                          get = function() return PAGet("borderBehind") or false end,
                          set = function(v) PASet("borderBehind", v) end },
                    },
                })
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                cogBtn:SetAlpha(0.4)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints()
                cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
                cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
                local function UpdateCogVis()
                    if (PAGet("borderTexture") or "solid") == "solid" then cogBtn:Hide() else cogBtn:Show() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end

            -- Inline border color swatch on Border Size dropdown
            do
                local rgn = bsRow._rightRegion
                local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, bsRow:GetFrameLevel() + 3,
                    function()
                        return (PAGet("borderR") or 0), (PAGet("borderG") or 0),
                               (PAGet("borderB") or 0), (PAGet("borderA") or 1)
                    end,
                    function(r, g, b, a)
                        PASet("borderR", r); PASet("borderG", g); PASet("borderB", b); PASet("borderA", a)
                    end,
                    true, 20)
                PP.Point(borderSwatch, "RIGHT", rgn._control, "LEFT", -8, 0)
                -- Disable swatch when border size is 0
                local borderSwatchBlock = CreateFrame("Frame", nil, borderSwatch)
                borderSwatchBlock:SetAllPoints()
                borderSwatchBlock:SetFrameLevel(borderSwatch:GetFrameLevel() + 10)
                borderSwatchBlock:EnableMouse(true)
                borderSwatchBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(borderSwatch, EllesmereUI.DisabledTooltip("This option requires a Border Size above 0."))
                end)
                borderSwatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function UpdateBorderSwatchState()
                    local noBorder = (PAGet("borderSize") or 0) == 0
                    if noBorder then borderSwatch:SetAlpha(0.3); borderSwatchBlock:Show()
                    else borderSwatch:SetAlpha(1); borderSwatchBlock:Hide() end
                end
                EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch(); UpdateBorderSwatchState() end)
                UpdateBorderSwatchState()
            end
        end

        -- Row 4: Blizzard debuff borders | buff-frame expand button.
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "No Border on Debuffs",
              tooltip = "When enabled, debuff icons keep Blizzard's colored border instead of using the custom border.",
              getValue = function() return PAGet("noBorderDebuffs") ~= false end,
              setValue = function(v) PASet("noBorderDebuffs", v) end },
            { type = "toggle", text = "Show Expand Button",
              getValue = function() return PAGet("showExpandButton") ~= false end,
              setValue = function(v) PASet("showExpandButton", v) end }
        );  y = y - h

        -----------------------------------------------------------------------
        --  External Defensives Frame (our own frame; live enable, no reload)
        -----------------------------------------------------------------------
        local function EDGet(key)
            local p = db and db.profile and db.profile.externalDefensives
            return p and p[key]
        end
        local function EDSet(key, v)
            if not db or not db.profile then return end
            if not db.profile.externalDefensives then db.profile.externalDefensives = {} end
            db.profile.externalDefensives[key] = v
            if ns.RefreshExternalDefensives then ns.RefreshExternalDefensives() end
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h
        _, h = W:SectionHeader(parent, "EXTERNAL DEFENSIVES FRAME", y);  y = y - h

        -- Row 1: Enable | Icon Size (+ Icon Zoom cog)
        local edRow1
        edRow1, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable External Defensives Frame",
              tooltip = "Shows external defensives cast on you (Pain Suppression, Ironbark, etc.) in its own movable frame; position it via Unlock Mode.",
              getValue = function() return EDGet("enabled") or false end,
              setValue = function(v) EDSet("enabled", v) end },
            { type = "slider", text = "Icon Size", min = 16, max = 60, step = 1,
              getValue = function() return EDGet("iconSize") or 32 end,
              setValue = function(v) EDSet("iconSize", v) end }
        );  y = y - h
        do
            local rgn = edRow1._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Icon Zoom",
                rows = {
                    { type = "slider", label = "Icon Zoom", min = 0, max = 0.20, step = 0.01,
                      get = function() return EDGet("iconZoom") or 0.055 end,
                      set = function(v) EDSet("iconZoom", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -- Row 2: Show Text | Text Size (+ Duration Format cog)
        local edRow2
        edRow2, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Text",
              getValue = function() return EDGet("showText") ~= false end,
              setValue = function(v) EDSet("showText", v) end },
            { type = "slider", text = "Text Size", min = 6, max = 24, step = 1,
              getValue = function() return EDGet("textSize") or 11 end,
              setValue = function(v) EDSet("textSize", v) end }
        );  y = y - h
        do
            local rgn = edRow2._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Duration Format",
                rows = {
                    { type = "dropdown", label = "Format",
                      values = {
                          blizzard = { text = "Blizzard Default (2 min)" },
                          compact  = { text = "Standard (5m / 32)" },
                          colon    = { text = "Colon (5:32)" },
                          seconds  = { text = "Seconds (152)" },
                      },
                      order = { "blizzard", "compact", "colon", "seconds" },
                      get = function() return EDGet("durationFormat") or "blizzard" end,
                      set = function(v) EDSet("durationFormat", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -- Row 3: Border Style (+ offset cog) | Border Size (+ color swatch)
        do
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local borderSizeValues = { none="None", thin="Thin", normal="Normal", heavy="Heavy", strong="Strong" }
            local borderSizeOrder = { "none", "thin", "normal", "heavy", "strong" }
            local sizeToNumber = { none=0, thin=1, normal=2, heavy=3, strong=4 }
            local numberToSize = { [0]="none", [1]="thin", [2]="normal", [3]="heavy", [4]="strong" }
            local edBsRow
            edBsRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Border Style", values=texValues, order=texOrder,
                  getValue=function() return EDGet("borderTexture") or "solid" end,
                  setValue=function(v)
                      local color, behind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                      local p = db.profile.externalDefensives
                      p.borderTexture = v
                      p.borderTextureOffset = nil; p.borderTextureOffsetY = nil
                      p.borderTextureShiftX = nil; p.borderTextureShiftY = nil
                      p.borderBehind = behind
                      p.borderR = color.r; p.borderG = color.g; p.borderB = color.b; p.borderA = 1
                      local defSz = EllesmereUI.GetBorderDefaultSize("unitframes", v)
                      if defSz then p.borderSize = defSz end
                      if ns.RefreshExternalDefensives then ns.RefreshExternalDefensives() end
                  end },
                { type="dropdown", text="Border Size", values=borderSizeValues, order=borderSizeOrder,
                  getValue=function() return numberToSize[EDGet("borderSize") or 1] or "thin" end,
                  setValue=function(v) EDSet("borderSize", sizeToNumber[v] or 1) end }
            );  y = y - h

            do
                local rgn = edBsRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title="Border Offset",
                    rows={
                        { type="slider", label="Offset X", min=-10, max=10, step=1,
                          get=function()
                              local v=EDGet("borderTextureOffset"); if v ~= nil then return v end
                              return EllesmereUI.GetBorderDefaults("unitframes", EDGet("borderTexture") or "solid", EDGet("borderSize") or 1)
                          end, set=function(v) EDSet("borderTextureOffset", v) end },
                        { type="slider", label="Offset Y", min=-10, max=10, step=1,
                          get=function()
                              local v=EDGet("borderTextureOffsetY"); if v ~= nil then return v end
                              local _,oy=EllesmereUI.GetBorderDefaults("unitframes", EDGet("borderTexture") or "solid", EDGet("borderSize") or 1); return oy
                          end, set=function(v) EDSet("borderTextureOffsetY", v) end },
                        { type="slider", label="Shift X", min=-10, max=10, step=1,
                          get=function()
                              local v=EDGet("borderTextureShiftX"); if v ~= nil then return v end
                              local _,_,sx=EllesmereUI.GetBorderDefaults("unitframes", EDGet("borderTexture") or "solid", EDGet("borderSize") or 1); return sx
                          end, set=function(v) EDSet("borderTextureShiftX", v == 0 and nil or v) end },
                        { type="slider", label="Shift Y", min=-10, max=10, step=1,
                          get=function()
                              local v=EDGet("borderTextureShiftY"); if v ~= nil then return v end
                              local _,_,_,sy=EllesmereUI.GetBorderDefaults("unitframes", EDGet("borderTexture") or "solid", EDGet("borderSize") or 1); return sy
                          end, set=function(v) EDSet("borderTextureShiftY", v == 0 and nil or v) end },
                        { type="toggle", label="Show Behind",
                          get=function() return EDGet("borderBehind") or false end,
                          set=function(v) EDSet("borderBehind", v) end },
                    },
                })
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26,26); cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8,0)
                rgn._lastInline=cogBtn; cogBtn:SetFrameLevel(rgn:GetFrameLevel()+5); cogBtn:SetAlpha(0.4)
                local tex=cogBtn:CreateTexture(nil,"OVERLAY"); tex:SetAllPoints(); tex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
                cogBtn:SetScript("OnEnter",function(self) self:SetAlpha(0.7) end)
                cogBtn:SetScript("OnLeave",function(self) self:SetAlpha(0.4) end)
                cogBtn:SetScript("OnClick",function(self) cogShow(self) end)
                local function UpdateCogVis() if (EDGet("borderTexture") or "solid") == "solid" then cogBtn:Hide() else cogBtn:Show() end end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis); UpdateCogVis()
            end
            do
                local rgn = edBsRow._rightRegion
                local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, edBsRow:GetFrameLevel() + 3,
                    function()
                        return (EDGet("borderR") or 0), (EDGet("borderG") or 0),
                               (EDGet("borderB") or 0), (EDGet("borderA") or 1)
                    end,
                    function(r, g, b, a)
                        EDSet("borderR", r); EDSet("borderG", g); EDSet("borderB", b); EDSet("borderA", a)
                    end,
                    true, 20)
                PP.Point(borderSwatch, "RIGHT", rgn._control, "LEFT", -8, 0)
                local borderSwatchBlock = CreateFrame("Frame", nil, borderSwatch)
                borderSwatchBlock:SetAllPoints()
                borderSwatchBlock:SetFrameLevel(borderSwatch:GetFrameLevel() + 10)
                borderSwatchBlock:EnableMouse(true)
                borderSwatchBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(borderSwatch, EllesmereUI.DisabledTooltip("This option requires a Border Size above 0."))
                end)
                borderSwatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function UpdateEDBorderSwatchState()
                    local noBorder = (EDGet("borderSize") or 0) == 0
                    if noBorder then borderSwatch:SetAlpha(0.3); borderSwatchBlock:Show()
                    else borderSwatch:SetAlpha(1); borderSwatchBlock:Hide() end
                end
                EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch(); UpdateEDBorderSwatchState() end)
                UpdateEDBorderSwatchState()
            end
        end

        -- Row 4: icon growth direction.
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Growth Direction",
              tooltip = "Which direction new icons extend from the frame's edge.",
              values = { right = "Right", left = "Left" }, order = { "right", "left" },
              getValue = function() return EDGet("growDirection") or "right" end,
              setValue = function(v) EDSet("growDirection", v) end },
            nil
        ); y = y - h

        return math.abs(y)
    end

    EllesmereUI:RegisterModule("EllesmereUIUnitFrames", {
        title       = "Unit Frames",
        description = "Configure unit frame appearance and behavior.",
        pages       = { PAGE_DISPLAY, PAGE_BOSS, PAGE_MINI, PAGE_AURAS },
        searchTerms = ufSearchTerms,
        buildPage   = function(pageName, parent, yOffset)
            -- Randomize preview creature IDs on every tab switch
            RandomizePreviewCreatures()
            if pageName == PAGE_DISPLAY then
                return BuildFrameDisplayPage(pageName, parent, yOffset)
            elseif pageName == PAGE_BOSS then
                return ns._BuildBossPage(pageName, parent, yOffset)
            elseif pageName == PAGE_MINI then
                return BuildMiniPage(pageName, parent, yOffset)
            elseif pageName == PAGE_AURAS then
                return BuildPlayerAurasPage(pageName, parent, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_DISPLAY then
                return _displayHeaderBuilder
            elseif pageName == PAGE_BOSS then
                return ns._bossHeaderBuilder
            elseif pageName == PAGE_MINI then
                return _miniHeaderBuilder
            end
            return nil
        end,
        -- Main/Mini Frames content is gated on whichever unit is currently
        -- selected, and the default is always "player"/"targettarget" -- so a
        -- hidden pre-build that only ever builds the default leaves the other
        -- units' settings unsearchable until the player picks them live. Both
        -- unit lists are small and fixed, so build once per unit rather than
        -- collapsing to representative shapes.
        getPrebuildVariants = function(pageName)
            if pageName == PAGE_DISPLAY then
                return { setter = EllesmereUI._setUnitFrameUnit, keys = unitOrder, currentKey = selectedUnit }
            elseif pageName == PAGE_MINI then
                return { setter = EllesmereUI._setMiniUnit, keys = miniUnitOrder, currentKey = selectedMiniUnit }
            end
            return nil
        end,
        onPageCacheRestore = function(pageName)
            RandomizePreviewCreatures()
            -- Hide all UIParent-parented disabled overlays before restoring
            -- (they persist across tab switches since they're not children of pf)
            for _, pv in pairs(allPreviews) do
                if pv and pv._disabledOverlay then pv._disabledOverlay:Hide() end
            end
            -- Force re-anchor previews after cache restore (parent changed)
            for _, pv in pairs(allPreviews) do
                if pv then
                    pv._lastOY = nil
                    -- Reset portrait anchor flag so Update() re-anchors it
                    if pv._portraitFrame then pv._portraitFrame._anchored = false end
                    -- Reset health anchor key so Update() re-anchors health bar
                    if pv._health then pv._health._anchorKey = nil end
                end
            end
            UpdatePreview()
            -- Refresh hint visibility on cache restore
            local dismissed = IsPreviewHintDismissed()
            if pageName == PAGE_DISPLAY and _ufPreviewHintFS_display then
                if dismissed then
                    _ufPreviewHintFS_display:Hide()
                else
                    _ufPreviewHintFS_display:SetAlpha(0.45)
                    _ufPreviewHintFS_display:Show()
                end
            end
        end,
        onReset     = function()
            db:ResetProfile()
            ReloadUI()
        end,
    })

    ---------------------------------------------------------------------------
    --  Slash command  /euf
    ---------------------------------------------------------------------------
    SLASH_ELLESMEREUNITFRAMES1 = "/euf"
    SlashCmdList.ELLESMEREUNITFRAMES = function(msg)
        if InCombatLockdown and InCombatLockdown() then
            print("Cannot open options in combat")
            return
        end

        if msg == "reset" then
            db:ResetProfile()
            ReloadUI()
            return
        end

        EllesmereUI:ShowModule("EllesmereUIUnitFrames")
    end
    end -- ns._InitEUIModule

    -- If SetupOptionsPanel already ran before PLAYER_LOGIN (unlikely but safe),
    -- fire immediately
    if ns.db then
        ns._InitEUIModule()
    end
end)
