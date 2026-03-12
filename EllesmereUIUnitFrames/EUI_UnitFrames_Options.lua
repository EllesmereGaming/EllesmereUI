-------------------------------------------------------------------------------
--  EUI_UnitFrames_Options.lua
--  Registers the Unit Frames module with EllesmereUI
--  2 tabs: Frame Display, Mini Frame Edit
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_DISPLAY   = "Frame Display"
local PAGE_MINI      = "Mini Frame Edit"
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
        return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or ""
    end
    local function GetUFOptUseShadow()
        return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow()
    end
    local function SetPVFont(fs, font, size)
        if not (fs and fs.SetFont) then return end
        local f = GetUFOptOutline()
        fs:SetFont(font, size, f)
        if f == "" then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1)
        else fs:SetShadowOffset(0, 0) end
    end

    ---------------------------------------------------------------------------
    --  Shared helpers
    ---------------------------------------------------------------------------
    local activePreview
    local allPreviews = {}

    local showCombatIndicatorPreview = false
    -- Preview hover-highlight hint text (shared across Single/Multi tabs)
    local _ufPreviewHintFS_display     -- hint FontString for Frame Display
    local _displayHeaderBaseH = 0      -- display header height WITHOUT hint

    local function IsPreviewHintDismissed()
        return EllesmereUIDB and EllesmereUIDB.previewHintDismissed
    end

    local function UpdatePreview()
        for _, pv in pairs(allPreviews) do
            if pv and pv.Update then pv:Update() end
        end
    end

    local function ReloadAndUpdate()
        if ReloadFrames then ReloadFrames() end
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
    end)

    ---------------------------------------------------------------------------
    --  Individual Display unit selector
    ---------------------------------------------------------------------------
    local selectedUnit = "player"

    local unitLabels = {
        ["player"]       = "Player",
        ["target"]       = "Target",
        ["focus"]        = "Focus",
        ["targettarget"] = "Focus Target / Target of Target",
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
        targettarget = function() return db.profile.totPet end,
        pet          = function() return db.profile.pet end,
        boss         = function() return db.profile.boss end,
    }

    local GROUP_UNIT_ORDER = { "player", "target", "focus" }
    local SHORT_LABELS = {
        player       = "Player",
        target       = "Target",
        focus        = "Focus",
        targettarget = "Focus Target / Target of Target",
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
    --  Health bar texture dropdown values (built from ns tables)
    ---------------------------------------------------------------------------
    -- Append SharedMedia textures so the dropdown includes SM entries
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
                            if texPath then
                                pFill:SetTexture(texPath)
                                pFill:SetVertexColor(0, 0, 1, 1)
                            else
                                pFill:SetVertexColor(1, 1, 1, 1)
                                pFill:SetColorTexture(0, 0, 1, 1)
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
    end

    ---------------------------------------------------------------------------
    --  Buff anchor / growth direction dropdown values
    ---------------------------------------------------------------------------
    local buffAnchorValues = {
        ["topleft"]     = "Top Left",
        ["topright"]    = "Top Right",
        ["bottomleft"]  = "Bottom Left",
        ["bottomright"] = "Bottom Right",
        ["left"]        = "Left",
        ["right"]       = "Right",
    }
    local buffAnchorOrder = { "topleft", "topright", "bottomleft", "bottomright", "left", "right" }

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
        ["perhp"]        = "Health %",
        ["perhpnosign"]  = "Health % (No Sign)",
        ["curhpshort"]   = "Health #",
        ["perhpnum"]     = "Health % | #",
        ["both"]         = "Health # | %",
        ["none"]         = "None",
    }
    local healthTextOrder = { "none", "---", "name", "perhp", "perhpnosign", "curhpshort", "perhpnum", "both" }

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
        local isDetached = (db.profile.portraitStyle or "attached") == "detached"
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

        -- Hide legacy square border textures if they exist
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
        ["portrait"] = "Portrait",
        ["circle"]   = "Circle",
        ["square"]   = "Square",
        ["csquare"]  = "Rounded Square",
        ["diamond"]  = "Diamond",
        ["hexagon"]  = "Hexagon",
        ["shield"]   = "Shield",
    }
    local detPortraitShapeOrder = { "portrait", "circle", "square", "csquare", "diamond", "hexagon", "shield" }

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
        local p = db.profile
        local settings
        if unitKey == "player" then settings = p.player
        elseif unitKey == "target" then settings = p.target
        elseif unitKey == "focus" then settings = p.focus
        elseif unitKey == "pet" then settings = p.pet
        elseif unitKey == "boss" then settings = p.boss
        elseif unitKey == "targettarget" then settings = p.totPet
        else settings = p.player end

        side = side or "left"

        -- FoT/ToT and Pet previews: no portrait or power bar
        local noPortraitPreview = (unitKey == "targettarget" or unitKey == "pet")
        local noPowerPreview = (unitKey == "targettarget" or unitKey == "pet")

        local hasPortraitSupport = not noPortraitPreview and (settings.showPortrait ~= nil or settings.portraitMode ~= nil)
        local showPortrait = hasPortraitSupport and (db.profile.portraitStyle or "attached") ~= "none"
        local frameW = settings.frameWidth or 181
        local healthH = settings.healthHeight or 46
        local powerH = noPowerPreview and 0 or (settings.powerHeight or 6)
        local initPpPos = noPowerPreview and "none" or (settings.powerPosition or "below")
        local initPpIsAtt = (initPpPos == "below" or initPpPos == "above")
        local initPpExtra = initPpIsAtt and powerH or 0
        -- For player, show preview castbar when showPlayerCastbar is on (always locked to frame)
        -- For target/focus, show when showCastbar is on
        local castbarH
        if unitKey == "player" then
            local pch = settings.playerCastbarHeight
            castbarH = settings.showPlayerCastbar and (pch and pch > 0 and pch or 14) or 0
        else
            castbarH = (settings.showCastbar ~= false) and (settings.castbarHeight or 14) or 0
        end
        local barH = healthH + initPpExtra
        local isAttachedInit = (db.profile.portraitStyle or "attached") == "attached"
        local portraitW = (showPortrait and isAttachedInit) and barH or 0
        local totalW = frameW + portraitW
        local totalH = barH

        -- Compute initial buff extra height for player (buffs extend beyond frame)
        local initBuffExtra = 0
        local initBuffTopPad = 0
        if unitKey == "player" and settings.showBuffs then
            local ba = settings.buffAnchor or "topleft"
            if ba == "topleft" or ba == "topright" or ba == "bottomleft" or ba == "bottomright" or ba == "left" or ba == "right" then
                initBuffExtra = 22 + 1 + 2  -- buffSize + buffGap + 2
            end
            if ba == "topleft" or ba == "topright" then
                initBuffTopPad = initBuffExtra
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

            -- Track last applied mode+style to avoid redundant re-init
            local _lastAppliedMode = nil
            local _lastAppliedStyle = nil

            local function ApplyPortraitMode()
                -- Read settings fresh from DB so the closure never goes stale
                -- after a preview switch or cache restore.
                local curSettings
                if unitKey == "player" then curSettings = db.profile.player
                elseif unitKey == "target" then curSettings = db.profile.target
                elseif unitKey == "focus" then curSettings = db.profile.focus
                elseif unitKey == "pet" then curSettings = db.profile.pet
                elseif unitKey == "boss" then curSettings = db.profile.boss
                elseif unitKey == "targettarget" then curSettings = db.profile.totPet
                else curSettings = db.profile.player end
                local mode = curSettings.portraitMode or "2d"
                local style = curSettings.classThemeStyle or "modern"
                -- Skip if nothing changed -- avoids re-initializing PlayerModel
                -- every Update() call which causes blinking and massive GPU cost
                if mode == _lastAppliedMode and style == _lastAppliedStyle then return end
                _lastAppliedMode = mode
                _lastAppliedStyle = style
                if mode == "3d" then
                    portraitFrame:Show()
                    portraitTex:Hide()
                    local pm = EnsurePreviewModel()
                    pm:SetUnit("player")
                    pm:SetCamera(0)
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
            hR, hG, hB, hA = 0x11/255, 0x11/255, 0x11/255, 0.90
            bgR, bgG, bgB, bgA = 0x4f/255, 0x4f/255, 0x4f/255, 1
        else
            local barOpacity = (settings.healthBarOpacity or 90) / 100
            hA = barOpacity
            -- Check for custom fill color (skipped when class colored is enabled)
            local cFill = settings.customFillColor
            local isClassColored = settings.healthClassColored
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
            -- Check for custom background color
            local cBg = settings.customBgColor
            if cBg then
                bgR, bgG, bgB = cBg.r, cBg.g, cBg.b
            else
                bgR, bgG, bgB = 17/255, 17/255, 17/255
            end
            bgA = barOpacity
        end

        -- Health bar
        local health = CreateFrame("Frame", nil, pf)
        PP.Size(health, frameW, healthH)
        local healthBgColor = health:CreateTexture(nil, "BACKGROUND")
        if isDarkTheme then
            -- Only cover the empty (missing-health) portion so the fill's alpha shows through
            healthBgColor:SetPoint("TOPLEFT", health, "TOPLEFT", math.floor(frameW * (_previewHealthPct or 0.70) + 0.5), 0)
            healthBgColor:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
        else
            healthBgColor:SetAllPoints()
        end
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
        healthFill:SetColorTexture(hR, hG, hB, 1)
        healthFill:SetAlpha(hA)
        pf._healthFill = healthFill
        pf._hR, pf._hG, pf._hB, pf._hA = hR, hG, hB, hA

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

        -- Resolve preview text for a content key
        local function PreviewTextForContent(content, s)
            if content == "name" then
                if unitKey == "player" then
                    return UnitName("player") or "Player"
                else
                    return _previewCreatureNames[unitKey] or unitKey
                end
            elseif content == "both" or content == "curhpshort" or content == "perhp" or content == "perhpnosign" or content == "perhpnum" then
                local maxHP = UnitHealthMax("player") or 1
                local pct = _previewHealthPct or 0.70
                local curHP = math.floor(maxHP * pct)
                local pctInt = math.floor(pct * 100)
                if content == "curhpshort" then return AbbreviateLargeNumbers(curHP)
                elseif content == "perhp" then return pctInt .. "%"
                elseif content == "perhpnosign" then return tostring(pctInt)
                elseif content == "perhpnum" then return pctInt .. "% | " .. AbbreviateLargeNumbers(curHP)
                else return AbbreviateLargeNumbers(curHP) .. " | " .. pctInt .. "%" end
            elseif content == "perpp" then
                local ppPct = _previewPowerPct or 0.85
                return math.floor(ppPct * 100) .. "%"
            elseif content == "curpp" then
                local maxPP = UnitPowerMax("player") or 100
                local ppPct = _previewPowerPct or 0.85
                return AbbreviateLargeNumbers(math.floor(maxPP * ppPct))
            elseif content == "curhp_curpp" then
                local maxHP = UnitHealthMax("player") or 1
                local pct = _previewHealthPct or 0.70
                local curHP = math.floor(maxHP * pct)
                local maxPP = UnitPowerMax("player") or 100
                local ppPct2 = _previewPowerPct or 0.85
                return AbbreviateLargeNumbers(curHP) .. " | " .. AbbreviateLargeNumbers(math.floor(maxPP * ppPct2))
            elseif content == "perhp_perpp" then
                local pct = _previewHealthPct or 0.70
                local ppPct3 = _previewPowerPct or 0.85
                return math.floor(pct * 100) .. "% | " .. math.floor(ppPct3 * 100) .. "%"
            else
                return ""
            end
        end

        -- Class color helper for preview
        local function PreviewClassColor(fs, useCC)
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
            fs:SetTextColor(1, 1, 1)
        end


        -- Power color override for preview (takes priority over class color for power-related text)
        local function PreviewPowerColor(fs, contentKey, usePowerColor)
            if not fs or not usePowerColor then return end
            if contentKey == "perpp" or contentKey == "curpp" or contentKey == "curhp_curpp" or contentKey == "perhp_perpp" then
                fs:SetTextColor(0, 0, 1)
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


            -- Center text: if active, hide left/right
            if cc ~= "none" then
                leftFS:Hide()
                rightFS:Hide()
                centerFS:SetFont(PREVIEW_FONT, csz, GetUFOptOutline())
                centerFS:ClearAllPoints()
                centerFS:SetJustifyH("CENTER")
                PP.Point(centerFS, "CENTER", textOverlay, "CENTER", cxo, cyo)
                centerFS:SetText(PreviewTextForContent(cc, s))
                centerFS:Show()
                PreviewClassColor(centerFS, s.centerTextClassColor)
            else
                centerFS:Hide()
                leftFS:SetFont(PREVIEW_FONT, lsz, GetUFOptOutline())
                leftFS:ClearAllPoints()
                if lc ~= "none" then
                    leftFS:SetJustifyH("LEFT")
                    PP.Point(leftFS, "LEFT", textOverlay, "LEFT", 5 + lxo, lyo)
                    -- Constrain width when opposing right text exists (matches live frame truncation)
                    local barW = s.frameWidth or 181
                    if rc ~= "none" then
                        local UF_TEXT_PADDING = 10
                        local ufTW = { both = 75, curhpshort = 38, perhp = 38, perpp = 38, curpp = 38, curhp_curpp = 75, perhp_perpp = 75 }
                        local rightUsed = (ufTW[rc] or 0) + UF_TEXT_PADDING
                        PP.Width(leftFS, math.max(barW - rightUsed - 10, 20))
                    else
                        leftFS:SetWidth(0)
                    end
                    leftFS:SetText(PreviewTextForContent(lc, s))
                    leftFS:Show()
                    PreviewClassColor(leftFS, s.leftTextClassColor)
                else
                    leftFS:Hide()
                end

                rightFS:SetFont(PREVIEW_FONT, rsz, GetUFOptOutline())
                rightFS:ClearAllPoints()
                if rc ~= "none" then
                    rightFS:SetJustifyH("RIGHT")
                    PP.Point(rightFS, "RIGHT", textOverlay, "RIGHT", -5 + rxo, ryo)
                    rightFS:SetText(PreviewTextForContent(rc, s))
                    rightFS:Show()
                    PreviewClassColor(rightFS, s.rightTextClassColor)
                else
                    rightFS:Hide()
                end
            end
        end
        ApplyPreviewTextPositions(settings)

        -- Power bar
        local power
        local ppPreviewFS
        if powerH > 0 then
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
                local pType = UnitPowerType("player")
                local info = PowerBarColor[pType]
                if info then pfR, pfG, pfB = info.r, info.g, info.b
                else pfR, pfG, pfB = 0, 0, 1 end
            elseif customPFill then
                pfR, pfG, pfB = customPFill.r, customPFill.g, customPFill.b
            else
                pfR, pfG, pfB = 0, 0, 1
            end
            local pbR, pbG, pbB
            if customPBg then
                pbR, pbG, pbB = customPBg.r, customPBg.g, customPBg.b
            else
                pbR, pbG, pbB = 17/255, 17/255, 17/255
            end
            local powerOpacity = (settings.powerBarOpacity or 100) / 100
            powerBg:SetColorTexture(pbR, pbG, pbB, 1)
            powerBg:SetAlpha(powerOpacity)
            powerFill:SetColorTexture(pfR, pfG, pfB, 1)
            powerFill:SetAlpha(powerOpacity)
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
                healthFill:SetTexture(texPath)
                healthFill:SetVertexColor(hR, hG, hB, 1)
                if pf._powerFill and powerH > 0 then
                    pf._powerFill:SetTexture(texPath)
                    local txR, txG, txB
                    local isPwrC = settings.powerPercentPowerColor ~= false
                    if isPwrC then
                        local pType = UnitPowerType("player")
                        local info = PowerBarColor[pType]
                        if info then txR, txG, txB = info.r, info.g, info.b
                        else txR, txG, txB = 0, 0, 1 end
                    else
                        local cpf = settings.customPowerFillColor
                        if cpf then txR, txG, txB = cpf.r, cpf.g, cpf.b
                        else txR, txG, txB = 0, 0, 1 end
                    end
                    pf._powerFill:SetVertexColor(txR, txG, txB, 1)
                end
            end
        end

        -- Castbar -- always created for player (toggled in Update); conditional for others
        local castbar, castFill, castNameFS2, castIconFrame
        local shouldCreateCastbar = (unitKey == "player") or (castbarH > 0)
        local castTimeFS
        if shouldCreateCastbar then
            local initCH = (unitKey == "player") and (castbarH > 0 and castbarH or 14) or castbarH
            castbar = CreateFrame("Frame", nil, pf)
            PP.Size(castbar, totalW, initCH)
            local cbAnchor = power or health
            local cbOffset = 0
            if showPortrait and side == "right" then
                cbOffset = portraitW / 2
            elseif showPortrait and side == "left" then
                cbOffset = -(portraitW / 2)
            end
            PP.Point(castbar, "TOP", cbAnchor, "BOTTOM", cbOffset, 0)
            if castbarH > 0 then
                totalH = totalH + castbarH
            end

            -- Background matching real castbar: black 50% alpha
            local cbBg = castbar:CreateTexture(nil, "BACKGROUND")
            cbBg:SetAllPoints(castbar)
            cbBg:SetColorTexture(0, 0, 0, 0.5)

            -- Black borders via unified PP system
            PP.CreateBorder(castbar, 0, 0, 0, 1, 1, "OVERLAY", 0)

            -- Cast fill (inset 1px from left, 1px from bottom to sit inside borders)
            castFill = castbar:CreateTexture(nil, "ARTWORK")
            PP.Point(castFill, "TOPLEFT", castbar, "TOPLEFT", 1, 0)
            PP.Point(castFill, "BOTTOMLEFT", castbar, "BOTTOMLEFT", 1, 1)
            PP.Width(castFill, (totalW - 2) * (_previewCastFill or 0.6))
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

            castNameFS2 = castbar:CreateFontString(nil, "OVERLAY")
            SetPVFont(castNameFS2, PREVIEW_FONT, 11)
            PP.Point(castNameFS2, "LEFT", castbar, "LEFT", 5, 1)
            castNameFS2:SetJustifyH("LEFT")
            castNameFS2:SetTextColor(1, 1, 1)
            castNameFS2:SetText(castSpellName)

            -- Cast timer text on the right (matching real castbar.Time)
            castTimeFS = castbar:CreateFontString(nil, "OVERLAY")
            SetPVFont(castTimeFS, PREVIEW_FONT, 11)
            PP.Point(castTimeFS, "RIGHT", castbar, "RIGHT", -5, 0)
            castTimeFS:SetJustifyH("RIGHT")
            castTimeFS:SetTextColor(1, 1, 1)
            local spellCastTime = (_previewCastSpell and _previewCastSpell.castTime) or 3.0
            castTimeFS:SetText(string.format("%.1f", spellCastTime * (1 - (_previewCastFill or 0.6))))

            -- Cast spell icon -- always on the LEFT side of the castbar (matches real addon)
            -- Uses plain frame + edge textures instead of BackdropTemplate for pixel-perfect rendering
            local iconSize = initCH + 1
            castIconFrame = CreateFrame("Frame", nil, pf)
            PP.Size(castIconFrame, iconSize, iconSize)
            PP.Point(castIconFrame, "TOPRIGHT", castbar, "TOPLEFT", 1, 1)
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

            -- Text overlay
            local btbTextOvr = CreateFrame("Frame", nil, btbFrame)
            btbTextOvr:SetAllPoints()
            btbTextOvr:SetFrameLevel(btbFrame:GetFrameLevel() + 2)

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
                    btbLeftFS:SetText(PreviewTextForContent(lc, s))
                    btbLeftFS:Show()
                    PreviewClassColor(btbLeftFS, s.btbLeftClassColor)
                    PreviewPowerColor(btbLeftFS, lc, s.btbLeftPowerColor)
                else btbLeftFS:Hide() end

                btbRightFS:SetFont(PREVIEW_FONT, rsz, GetUFOptOutline())
                btbRightFS:ClearAllPoints()
                if rc ~= "none" then
                    btbRightFS:SetJustifyH("RIGHT")
                    PP.Point(btbRightFS, "RIGHT", btbTextOvr, "RIGHT", -5 + (s.btbRightX or 0), s.btbRightY or 0)
                    btbRightFS:SetText(PreviewTextForContent(rc, s))
                    btbRightFS:Show()
                    PreviewClassColor(btbRightFS, s.btbRightClassColor)
                    PreviewPowerColor(btbRightFS, rc, s.btbRightPowerColor)
                else btbRightFS:Hide() end

                btbCenterFS:SetFont(PREVIEW_FONT, csz, GetUFOptOutline())
                btbCenterFS:ClearAllPoints()
                if cc ~= "none" then
                    btbCenterFS:SetJustifyH("CENTER")
                    PP.Point(btbCenterFS, "CENTER", btbTextOvr, "CENTER", s.btbCenterX or 0, s.btbCenterY or 0)
                    btbCenterFS:SetText(PreviewTextForContent(cc, s))
                    btbCenterFS:Show()
                    PreviewClassColor(btbCenterFS, s.btbCenterClassColor)
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
            local CP_CLASS_COLORS = {
                ROGUE={1.00,0.96,0.41}, DRUID={1.00,0.49,0.04}, PALADIN={0.96,0.55,0.73},
                MONK={0.00,1.00,0.60}, WARLOCK={0.58,0.51,0.79}, MAGE={0.25,0.78,0.92},
                EVOKER={0.20,0.58,0.50}, DEATHKNIGHT={0.77,0.12,0.23},
                DEMONHUNTER={0.34,0.06,0.46}, SHAMAN={0.00,0.44,0.87},
                HUNTER={0.67,0.83,0.45}, WARRIOR={0.78,0.61,0.43},
            }
            local CP_DEFAULT_COLOR = {1.00, 0.84, 0.30}
            local CLASS_POWER_MAP = {
                ROGUE={5}, DRUID={5}, PALADIN={5}, MONK={5},
                WARLOCK={5}, MAGE={4}, EVOKER={5}, DEATHKNIGHT={6},
                DEMONHUNTER={[581]=6}, SHAMAN={[263]=10}, HUNTER={[255]=3}, WARRIOR={[72]=4},
            }
            local _, playerClass = UnitClass("player")
            local cpInfo = CLASS_POWER_MAP[playerClass]
            local cpMax
            if cpInfo then
                if cpInfo[1] then
                    cpMax = cpInfo[1]
                else
                    -- Spec-keyed: resolve current spec
                    local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
                    local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec)
                    cpMax = specID and cpInfo[specID] or 0
                end
            else
                cpMax = 0
            end
            if cpMax <= 0 then cpMax = 5 end  -- fallback for preview
            local cpColor = CP_CLASS_COLORS[playerClass] or CP_DEFAULT_COLOR

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
        end

        -- Border -- plain frame child of barArea with 4 individual edge textures.
        -- BackdropTemplate is avoided: its edgeSize clipping causes sides to vanish
        -- when the frame is small, and its internal snapping can't be disabled.
        -- Individual textures with PixelUtil sizing render reliably.
        local bdrSize = settings.borderSize or 1
        local bdrColor = settings.borderColor or { r = 0, g = 0, b = 0 }
        local border = CreateFrame("Frame", nil, pf)
        border:SetPoint("TOPLEFT", barArea, "TOPLEFT", 0, 0)
        border:SetPoint("TOPRIGHT", barArea, "TOPRIGHT", 0, 0)
        local initBdrBtbPos = settings.btbPosition or "bottom"
        local initBdrBtbAtt = (initBdrBtbPos == "top" or initBdrBtbPos == "bottom")
        border:SetHeight(settings.healthHeight + initPpExtra + (settings.bottomTextBar and initBdrBtbAtt and (settings.bottomTextBarHeight or 16) or 0))
        border:SetFrameLevel(barArea:GetFrameLevel() + 5)
        PP.CreateBorder(border, bdrColor.r, bdrColor.g, bdrColor.b, 1, bdrSize)
        if bdrSize == 0 then border:Hide() end

        -- Absorb bar (player only, uses shield.tga like the real addon)
        local absorbBar
        if unitKey == "player" then
            -- Use a StatusBar with reverse fill + shield texture, same as CreateAbsorbBar
            absorbBar = CreateFrame("StatusBar", nil, health)
            absorbBar:SetStatusBarTexture("Interface\\AddOns\\EllesmereUIUnitFrames\\Media\\shield.tga")
            absorbBar:SetStatusBarColor(1, 1, 1, 0.8)
            absorbBar:SetReverseFill(true)
            PP.Point(absorbBar, "TOPRIGHT", healthFill, "TOPRIGHT", 0, 0)
            PP.Point(absorbBar, "BOTTOMRIGHT", healthFill, "BOTTOMRIGHT", 0, 0)
            PP.Width(absorbBar, frameW)
            PP.Height(absorbBar, healthH)
            absorbBar:SetMinMaxValues(0, 1)
            absorbBar:SetValue(0.14)  -- ~10% absorb relative to 70% health fill
            absorbBar:SetFrameLevel(health:GetFrameLevel() + 1)
            if not settings.showPlayerAbsorb then absorbBar:Hide() end
        end

        -- Fake buff icons (player only, shown when showBuffs is on)
        local buffIcons = {}
        if unitKey == "player" then
            local buffSize = 22
            local buffGap = 1
            local ba = settings.buffAnchor or "topleft"
            for i = 1, 2 do
                local bf = CreateFrame("Frame", nil, pf, "BackdropTemplate")
                PP.Size(bf, buffSize, buffSize)
                bf:SetBackdrop(SOLID_BACKDROP)
                bf:SetBackdropColor(0, 0, 0, 1)
                bf:SetFrameLevel(pf:GetFrameLevel() + 3)
                -- Initial placement at topleft; Update() will reposition properly
                PP.Point(bf, "BOTTOMLEFT", pf, "TOPLEFT", (i - 1) * (buffSize + buffGap), buffGap)
                local tex = bf:CreateTexture(nil, "ARTWORK")
                PP.Point(tex, "TOPLEFT", bf, "TOPLEFT", 1, -1)
                PP.Point(tex, "BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1, 1)
                tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                tex:SetTexture(_previewBuffIcons[i] or 135932)
                bf._iconTex = tex
                buffIcons[i] = bf
                if not settings.showBuffs then bf:Hide() end
            end
        end

        -- Disabled overlay -- must render above ALL other child frames
        -- Parent to UIParent so strata isn't clamped by pf's strata
        local disabledOverlay = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        disabledOverlay:SetFrameStrata("TOOLTIP")
        disabledOverlay:SetBackdrop(SOLID_BACKDROP)
        disabledOverlay:SetBackdropColor(0, 0, 0, 0.6)
        disabledOverlay:Hide()
        local disabledText = disabledOverlay:CreateFontString(nil, "OVERLAY")
        SetPVFont(disabledText, PREVIEW_FONT, 11)
        disabledText:SetTextColor(1, 1, 1)
        disabledText:SetText("Disabled")
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
            elseif unitKey == "targettarget" then s = db.profile.totPet
            else s = db.profile.player end

            -- Donor settings for mini frames (border/texture/font inherit from focus player)
            local isMini = (unitKey == "pet" or unitKey == "boss" or unitKey == "targettarget")
            local ds = s
            if isMini then
                local ef = db.profile.enabledFrames
                if ef.focus ~= false and db.profile.focus then ds = db.profile.focus
                elseif ef.target ~= false and db.profile.target then ds = db.profile.target
                else ds = db.profile.player end
            end

            -- Enabled/disabled overlay
            local unitKey2 = unitKey:match("^boss") and "boss" or unitKey
            local isEnabled = db.profile.enabledFrames[unitKey2] ~= false
            if isEnabled then
                disabledOverlay:Hide()
                pf:SetAlpha(1)
            else
                pf:SetAlpha(0.5)
            end

            -- (text content updated by ApplyPreviewTextPositions)

            -- Reposition name and health text based on settings
            side = s.portraitSide or unitSide[unitKey] or "left"
            local sp = hasPortraitSupport and (db.profile.portraitStyle or "attached") ~= "none"
            local isAttached = (db.profile.portraitStyle or "attached") == "attached"
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
            if cpStyle == "modern" and cpPos == "above" then
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
            if not isAttached then pSizeAdj = pSizeAdj + 10; pYOff = pYOff + 5 end
            local portraitDim = bh2 + pSizeAdj  -- portrait width & height
            if portraitDim < 8 then portraitDim = 8 end
            -- For attached, "top" falls back to default side
            local effectiveSide = side
            if isAttached and side == "top" then
                effectiveSide = unitSide[unitKey] or "left"
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
                PP.Size(portraitFrame, portraitDim, portraitDim)
                if isAttached then
                    -- Attached: portrait to barArea, then health to portrait
                    if effectiveSide == "left" then
                        portraitFrame:SetPoint("TOPLEFT", barArea, "TOPLEFT", 0, 0)
                        PP.Point(health, "TOPLEFT", portraitFrame, "TOPRIGHT", 0, -cpAboveH - btbTopOff - pvPwAbove)
                    else
                        portraitFrame:SetPoint("TOPRIGHT", barArea, "TOPRIGHT", 0, 0)
                        PP.Point(health, "TOPRIGHT", portraitFrame, "TOPLEFT", 0, -cpAboveH - btbTopOff - pvPwAbove)
                    end
                else
                    -- Detached: health to barArea, then portrait floats
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
            PP.Width(healthFill, math.floor(fw * (_previewHealthPct or 0.70) + 0.5))

            -- Live-update dark mode colors
            do
                local isDark = db.profile.darkTheme
                local uHR, uHG, uHB, uBgR, uBgG, uBgB
                if isDark then
                    uHR, uHG, uHB = 0x11/255, 0x11/255, 0x11/255
                    uBgR, uBgG, uBgB = 0x4f/255, 0x4f/255, 0x4f/255
                else
                    -- Check for custom fill color (skipped when class colored is enabled)
                    local cFill = s.customFillColor
                    local isCC = s.healthClassColored
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
                    -- Check for custom background color
                    local cBg = s.customBgColor
                    if cBg then
                        uBgR, uBgG, uBgB = cBg.r, cBg.g, cBg.b
                    else
                        uBgR, uBgG, uBgB = 17/255, 17/255, 17/255
                    end
                end
                healthFill:SetColorTexture(uHR, uHG, uHB, 1)
                if isDark then
                    healthBgColor:ClearAllPoints()
                    healthBgColor:SetPoint("TOPLEFT", health, "TOPLEFT", math.floor(fw * (_previewHealthPct or 0.70) + 0.5), 0)
                    healthBgColor:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
                else
                    healthBgColor:ClearAllPoints()
                    healthBgColor:SetAllPoints(health)
                end
                healthBgColor:SetColorTexture(uBgR, uBgG, uBgB, 1)
                -- Update bar texture on fill textures
                do
                    local curTexKey = s.healthBarTexture or db.profile.healthBarTexture or "none"
                    local curTexPath = (ns.healthBarTextures or {})[curTexKey]
                    if healthFill then
                        if curTexPath then
                            healthFill:SetTexture(curTexPath)
                            healthFill:SetVertexColor(uHR, uHG, uHB, 1)
                        else
                            healthFill:SetVertexColor(1, 1, 1, 1)
                            healthFill:SetColorTexture(uHR, uHG, uHB, 1)
                        end
                    end
                    if pf._powerFill then
                        local pvFR, pvFG, pvFB
                        local isPwrC2 = s.powerPercentPowerColor ~= false
                        if isPwrC2 then
                            local pType = UnitPowerType("player")
                            local info = PowerBarColor[pType]
                            if info then pvFR, pvFG, pvFB = info.r, info.g, info.b
                            else pvFR, pvFG, pvFB = 0, 0, 1 end
                        else
                            local cpf2 = s.customPowerFillColor
                            if cpf2 then pvFR, pvFG, pvFB = cpf2.r, cpf2.g, cpf2.b
                            else pvFR, pvFG, pvFB = 0, 0, 1 end
                        end
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
                    hBgA   = barOp
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
                if pf._powerFill then
                    PP.Width(pf._powerFill, math.floor(pvPw * (_previewPowerPct or 0.85) + 0.5))
                end

                -- Apply power bar opacity from unified setting
                local pOpacity = (s.powerBarOpacity or 100) / 100
                if pf._powerFill then pf._powerFill:SetAlpha(pOpacity) end
                if pf._powerBg then pf._powerBg:SetAlpha(pOpacity) end

                -- Apply power bar colors
                local pvPfR, pvPfG, pvPfB
                local pvUsePowerColor = s.powerPercentPowerColor ~= false
                if pvUsePowerColor then
                    local pType = UnitPowerType("player")
                    local info = PowerBarColor[pType]
                    if info then pvPfR, pvPfG, pvPfB = info.r, info.g, info.b
                    else pvPfR, pvPfG, pvPfB = 0, 0, 1 end
                else
                    local cpFill = s.customPowerFillColor
                    if cpFill then pvPfR, pvPfG, pvPfB = cpFill.r, cpFill.g, cpFill.b
                    else pvPfR, pvPfG, pvPfB = 0, 0, 1 end
                end
                local pvPbR, pvPbG, pvPbB
                local cpBg = s.customPowerBgColor
                if cpBg then pvPbR, pvPbG, pvPbB = cpBg.r, cpBg.g, cpBg.b
                else pvPbR, pvPbG, pvPbB = 17/255, 17/255, 17/255 end
                if pf._powerFill then pf._powerFill:SetColorTexture(pvPfR, pvPfG, pvPfB, 1) end
                if pf._powerBg then pf._powerBg:SetColorTexture(pvPbR, pvPbG, pvPbB, 1) end
            end

            -- Power percent text in preview
            if ppPreviewFS then
                local ppPos = s.powerPercentText or "none"
                local ppFmt = s.powerTextFormat or "perpp"
                if ppPos ~= "none" and ppFmt ~= "none" and power and ph > 0 then
                    local ppSz = s.powerPercentSize or 9
                    local ppOx = s.powerPercentX or 0
                    local ppOy = s.powerPercentY or 0
                    ppPreviewFS:SetFont(PREVIEW_FONT, ppSz, GetUFOptOutline())
                    ppPreviewFS:ClearAllPoints()
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
                        ppPreviewFS:SetTextColor(0, 0, 1)
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
                    btbFrame:ClearAllPoints()
                    local btbPvAnchor = (pvPpIsAtt and power and power:IsShown()) and power or health
                    if btbPos == "top" then
                        PP.Point(btbFrame, "BOTTOM", health, "TOP", cbOff, 0)
                    elseif btbPos == "detached_top" then
                        btbFrame:SetPoint("BOTTOM", health, "TOP", s.btbX or 0, 15 + (s.btbY or 0))
                    elseif btbPos == "detached_bottom" then
                        btbFrame:SetPoint("TOP", btbPvAnchor, "BOTTOM", s.btbX or 0, -15 + (s.btbY or 0))
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
                    castbar:SetSize(tw, ch)
                    castbar:Show()
                    if castFill then
                        castFill:SetWidth(math.floor((tw - 2) * (_previewCastFill or 0.6) + 0.5))
                        -- Update fill color from per-unit settings (class colored only for player)
                        local fillC
                        if unitKey == "player" and s.castbarClassColored then
                            local _, classToken = UnitClass("player")
                            if classToken then fillC = RAID_CLASS_COLORS[classToken] end
                        end
                        if not fillC then fillC = s.castbarFillColor end
                        if fillC then
                            castFill:SetColorTexture(fillC.r, fillC.g, fillC.b, 1)
                        else
                            local gc = db.profile.castbarColor or { r=0.114, g=0.655, b=0.514 }
                            castFill:SetColorTexture(gc.r, gc.g, gc.b, 1)
                        end
                    end
                    if castIconFrame then
                        castIconFrame:SetSize(ch + 1, ch + 1)
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
                    if castNameFS2 then
                        local spellName = (unitKey == "player") and (_previewCastSpell and _previewCastSpell.name or "Spell Name") or "Spell Name"
                        castNameFS2:SetText(spellName)
                        local snSz = s.castSpellNameSize or 11
                        castNameFS2:SetFont(PREVIEW_FONT, snSz, GetUFOptOutline())
                        local snC = s.castSpellNameColor or { r=1, g=1, b=1 }
                        castNameFS2:SetTextColor(snC.r, snC.g, snC.b)
                    end
                    if castTimeFS then
                        local spCastTime = (_previewCastSpell and _previewCastSpell.castTime) or 3.0
                        castTimeFS:SetText(string.format("%.1f", spCastTime * (1 - (_previewCastFill or 0.6))))
                        local dtSz = s.castDurationSize or 11
                        castTimeFS:SetFont(PREVIEW_FONT, dtSz, GetUFOptOutline())
                        local dtC = s.castDurationColor or { r=1, g=1, b=1 }
                        castTimeFS:SetTextColor(dtC.r, dtC.g, dtC.b)
                    end
                    castbar:ClearAllPoints()
                    local pvBtbVisible = (btbFrame and s.bottomTextBar and btbPos == "bottom")
                    local cbAnchorFrame = pvBtbVisible and btbFrame or ((pvPpIsAtt and power and power:IsShown()) and power or health)
                    local cbAnchorOff = pvBtbVisible and 0 or cbOff
                    PP.Point(castbar, "TOP", cbAnchorFrame, "BOTTOM", cbAnchorOff, 0)
                else
                    castbar:Hide()
                    if castIconFrame then castIconFrame:Hide() end
                end
            end

            -- Border size and color (encompasses health+power+BTB+above pips)
            local bs = ds.borderSize or 1
            local bc = ds.borderColor or { r = 0, g = 0, b = 0 }
            local borderH = bh2 + (s.bottomTextBar and btbIsAtt and (s.bottomTextBarHeight or 16) or 0)
            border:ClearAllPoints()
            border:SetPoint("TOPLEFT", barArea, "TOPLEFT", 0, 0)
            border:SetPoint("TOPRIGHT", barArea, "TOPRIGHT", 0, 0)
            border:SetHeight(borderH)
            if bs > 0 then
                PP.UpdateBorder(border, bs, bc.r, bc.g, bc.b, 1)
                border:Show()
            else
                border:Hide()
            end

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
                    local CP_CLASS_COLORS_U = {
                        ROGUE={1.00,0.96,0.41}, DRUID={1.00,0.49,0.04}, PALADIN={0.96,0.55,0.73},
                        MONK={0.00,1.00,0.60}, WARLOCK={0.58,0.51,0.79}, MAGE={0.25,0.78,0.92},
                        EVOKER={0.20,0.58,0.50}, DEATHKNIGHT={0.77,0.12,0.23},
                    }
                    local _, cpPlayerClass = UnitClass("player")
                    local cpUseCC = s.classPowerClassColor ~= false
                    local cpCr, cpCg, cpCb
                    if not cpUseCC then
                        local cc = s.classPowerCustomColor or { r = 1, g = 0.82, b = 0 }
                        cpCr, cpCg, cpCb = cc.r, cc.g, cc.b
                    else
                        local mc = CP_CLASS_COLORS_U[cpPlayerClass] or {1.00, 0.84, 0.30}
                        cpCr, cpCg, cpCb = mc[1], mc[2], mc[3]
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

            -- Absorb bar (player only)
            if absorbBar then
                if s.showPlayerAbsorb then
                    absorbBar:ClearAllPoints()
                    absorbBar:SetPoint("TOPRIGHT", healthFill, "TOPRIGHT", 0, 0)
                    absorbBar:SetPoint("BOTTOMRIGHT", healthFill, "BOTTOMRIGHT", 0, 0)
                    absorbBar:SetWidth(fw)
                    absorbBar:SetHeight(hh)
                    absorbBar:Show()
                else
                    absorbBar:Hide()
                end
            end

            -- Buff icons (player only) -- reposition based on anchor/growth settings
            local buffExtra = 0
            if #buffIcons > 0 then
                local maxBuf = s.maxBuffs or 4
                local visibleBuffCount = math.min(2, maxBuf)
                if s.showBuffs and visibleBuffCount > 0 then
                    local buffSize = 22
                    local buffGap = 1
                    local ba = s.buffAnchor or "topleft"
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
                        topleft     = { pt = "TOPLEFT",     ox = 0,                       oy = buffGap },
                        topright    = { pt = "TOPRIGHT",    ox = 0,                       oy = buffGap },
                        bottomleft  = { pt = "BOTTOMLEFT",  ox = 0,                       oy = -(buffSize + buffGap) },
                        bottomright = { pt = "BOTTOMRIGHT", ox = 0,                       oy = -(buffSize + buffGap) },
                        left        = { pt = "LEFT",         ox = -(buffGap),              oy = 0 },
                        right       = { pt = "RIGHT",        ox = buffGap,                 oy = 0 },
                    }
                    local am = anchorMap[ba] or anchorMap.topleft

                    -- Growth offset for icon 2 relative to icon 1
                    local dx, dy = 0, 0
                    if gDir == "right" then dx = buffSize + buffGap
                    elseif gDir == "left" then dx = -(buffSize + buffGap)
                    elseif gDir == "up" then dy = buffSize + buffGap
                    elseif gDir == "down" then dy = -(buffSize + buffGap)
                    else dx = buffSize + buffGap end

                    -- Determine justifyH for SetPoint (which corner of the icon anchors)
                    local justH = "BOTTOMLEFT"
                    if ba == "topright" or ba == "bottomright" then
                        justH = "BOTTOMRIGHT"
                    elseif ba == "left" then
                        justH = "BOTTOMRIGHT"
                    elseif ba == "right" then
                        justH = "BOTTOMLEFT"
                    end

                    -- Build a cache key so we only reanchor when the anchor actually changes.
                    -- ClearAllPoints + SetPoint causes a one-frame gap that makes icons blink.
                    -- Also guard Show()/Hide() -- calling Show() on an already-visible frame
                    -- triggers a re-render that causes a shutter effect.
                    local anchorKey = justH .. am.pt .. am.ox .. am.oy .. dx .. dy
                    for i, bf in ipairs(buffIcons) do
                        if i <= visibleBuffCount then
                            if bf._anchorKey ~= anchorKey then
                                bf:ClearAllPoints()
                                if i == 1 then
                                    PP.Point(bf, justH, pf, am.pt, am.ox, am.oy)
                                else
                                    PP.Point(bf, justH, buffIcons[1], justH, dx * (i - 1), dy * (i - 1))
                                end
                                bf._anchorKey = anchorKey
                            end
                            if not bf:IsShown() then bf:Show() end
                            if bf._iconTex then bf._iconTex:SetTexture(_previewBuffIcons[i] or 135932) end
                        else
                            if bf:IsShown() then bf:Hide() end
                        end
                    end

                    -- Add buff height to header when buffs are above or below the frame
                    if ba == "topleft" or ba == "topright" or ba == "bottomleft" or ba == "bottomright" or ba == "left" or ba == "right" then
                        buffExtra = buffSize + buffGap + 2
                    end
                else
                    for _, bf in ipairs(buffIcons) do if bf:IsShown() then bf:Hide() end end
                end
            end

            local btbExtra = (btbFrame and s.bottomTextBar and btbIsAtt) and (s.bottomTextBarHeight or 16) or 0
            local th = bh2 + btbExtra + (ch > 0 and ch or 0)
            pf:SetSize(tw, th)

            -- Apply frame scale to preview
            local fScale = (s.frameScale or 100) / 100
            local combinedScale = (pf._previewScale or 1) * fScale
            pf:SetScale(combinedScale)

            -- Recalculate border sizes after scale change so they stay pixel-perfect
            if border then
                local bs2 = ds.borderSize or 1
                PP.SetBorderSize(border, bs2)
            end
            if castbar then
                if castbar._ppBorders then PP.SetBorderSize(castbar, 1) end
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

            -- Re-snap castbar background width
            if castbar then
                local cbW = castbar:GetWidth()
                if cbW > snappedFrameW + 0.01 then
                    castbar:SetWidth(snappedFrameW)
                end
            end

            -- Determine how much extra space buffs need above/below the frame
            local buffTopPad = 0  -- extra space above frame (push preview down)
            if buffExtra > 0 then
                local ba2 = s.buffAnchor or "topleft"
                if ba2 == "topleft" or ba2 == "topright" then
                    buffTopPad = buffExtra
                end
            end

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
            buffTopPad = buffTopPad + detTopExtra

            -- Reposition pf vertically based on buff padding
            local baseOY = pf._headerDropdownOY or 25
            local pfOY = -(baseOY + buffTopPad) / combinedScale
            if pf._lastOY ~= pfOY then
                pf:ClearAllPoints()
                PP.Point(pf, "TOP", pf:GetParent(), "TOP", 0, pfOY)
                pf._lastOY = pfOY
            end

            -- Notify framework of height change for dynamic content header.
            -- Use UpdateContentHeaderHeight so the scroll position is
            -- compensated -- keeps the widget the user is interacting with
            -- in the same screen position even when the preview grows/shrinks.
            pf._buffExtra = buffExtra
            pf._detTopExtra = detTopExtra
            local parentTH = th * combinedScale
            local cpBottomScaled = cpBottomH * combinedScale
            local hintH = 0
            if _ufPreviewHintFS_display and _ufPreviewHintFS_display:IsShown() then hintH = 29 end
            local fixedH = pf._headerFixedH or 0
            if fixedH > 0 then
                EllesmereUI:UpdateContentHeaderHeight(fixedH + parentTH + buffExtra + detTopExtra + cpBottomScaled + hintH)

            end
            -- Reposition segmented pill below the preview when height changes
            if pf._segFrame then
                local pillY = -(baseOY + parentTH + buffExtra + detTopExtra + cpBottomScaled + (pf._segGap or 20))
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
                    local ciAnchor = pf
                    if ciPos == "healthbar" then ciAnchor = health
                    elseif ciPos == "textbar" and btbFrame then ciAnchor = btbFrame
                    elseif ciPos == "portrait" and portraitFrame and sp then ciAnchor = portraitFrame
                    end
                    combatInd:SetPoint("CENTER", ciAnchor, "CENTER", ciOx, ciOy)
                    local _, classToken = UnitClass("player")
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
        pf._nameFS = leftFS
        pf._hpFS = rightFS
        pf._centerFS = centerFS
        pf._portraitFrame = portraitFrame
        pf._buffIcons = buffIcons
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
            { type="colorpicker", text="Border Color",
              getValue=function()
                local c = settingsTable.borderColor or { r = 0, g = 0, b = 0 }
                return c.r, c.g, c.b
              end,
              setValue=function(r, g, b)
                settingsTable.borderColor = { r = r, g = g, b = b }
                ReloadAndUpdate()
              end },
            nil);  y = y - h

        -- Inline cog on Border Color for Border Size
        do
            local leftRgn = borderRow._leftRegion
            local _, borderCogShow = EllesmereUI.BuildCogPopup({
                title = "Border Settings",
                rows = {
                    { type="slider", label="Size", min=0, max=4, step=1,
                      get=function() return settingsTable.borderSize or 1 end,
                      set=function(v) settingsTable.borderSize = v; ReloadAndUpdate() end },
                },
            })
            local bCogBtn = CreateFrame("Button", nil, leftRgn)
            bCogBtn:SetSize(26, 26)
            bCogBtn:SetPoint("RIGHT", leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = bCogBtn
            bCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            bCogBtn:SetAlpha(0.4)
            local bCogTex = bCogBtn:CreateTexture(nil, "OVERLAY")
            bCogTex:SetAllPoints()
            bCogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            bCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            bCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            bCogBtn:SetScript("OnClick", function(self) borderCogShow(self) end)
        end

        return y
    end

    ---------------------------------------------------------------------------
    --  Page Builders
    ---------------------------------------------------------------------------

    -- General tab removed settings migrated to per-unit DISPLAY section,
    -- positioning migrated to Unlock Mode.

    ---------------------------------------------------------------------------
    --  MULTI FRAME EDIT TAB  (checkbox selector + shared per-unit settings)
    ---------------------------------------------------------------------------
    local function RegisterWidgetRefresh(fn)
        if not EllesmereUI._widgetRefreshList then
            EllesmereUI._widgetRefreshList = {}
        end
        table.insert(EllesmereUI._widgetRefreshList, fn)
    end

    ---------------------------------------------------------------------------
    --  Unified settings builder  (shared settings for Frame Display)
    ---------------------------------------------------------------------------
    local UNIT_SUPPORTS = {
        powerHeight          = { player=true, target=true, focus=true },
        showPlayerAbsorb     = { player=true },
        showBuffs            = { player=true, target=true },
        combatIndicatorStyle   = { player=true },
        combatIndicatorColor   = { player=true },
        combatIndicatorCustomColor = { player=true },
        combatIndicatorPosition = { player=true },
        combatIndicatorSize    = { player=true },
        combatIndicatorX       = { player=true },
        combatIndicatorY       = { player=true },
        buffAnchor           = { player=true, target=true },
        buffGrowth           = { player=true, target=true },
        maxBuffs             = { player=true, target=true },
        showPlayerCastbar    = { player=true },
        showPlayerCastIcon   = { player=true },
        playerCastbarHeight  = { player=true },
        showCastbar          = { target=true, focus=true },
        showCastIcon         = { target=true, focus=true },
        castbarHeight        = { target=true, focus=true },
        castbarHideWhenInactive = { player=true, target=true, focus=true },
        castSpellNameSize    = { player=true, target=true, focus=true },
        castSpellNameColor   = { player=true, target=true, focus=true },
        castDurationSize     = { player=true, target=true, focus=true },
        castDurationColor    = { player=true, target=true, focus=true },
        castbarFillColor     = { player=true, target=true, focus=true },
        castbarClassColored  = { player=true },
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
        debuffAnchor         = { target=true },
        debuffGrowth         = { target=true },
        maxDebuffs           = { target=true },
        onlyPlayerDebuffs    = { target=true },
        showInRaid           = { player=true, target=true, focus=true },
        showInParty          = { player=true, target=true, focus=true },
        showSolo             = { player=true, target=true, focus=true },
    }
    local UNIT_LABELS_SUP = { player="Player", target="Target", focus="Focus" }

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
        local function SSupportTooltip(key)
            local sup = UNIT_SUPPORTS[key]
            if not sup then return nil end
            local names = {}
            for _, k in ipairs(GROUP_UNIT_ORDER) do
                if sup[k] then names[#names+1] = UNIT_LABELS_SUP[k] end
            end
            return "Applies to: " .. table.concat(names, ", ")
        end
        -- Dim a row region and add tooltip when no checked unit supports the setting
        local function SApplySupport(region, key)
            if not SVisible(key) then
                region:SetAlpha(0.35)
                if region._control and region._control.Disable then region._control:Disable() end
            end
            local tip = SSupportTooltip(key)
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
                    hitFrame:SetPassThroughButtons("LeftButton", "RightButton")
                end
                MakeSupportHit(region._label)
                MakeSupportHit(region._control)
            end
        end
        -- Helper: build a standard cog button on a region
        local function MakeCogBtn(rgn, showFn, anchorTo, iconPath)
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", anchorTo or rgn._lastInline or rgn._control, "LEFT", -8, 0)
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

        parent._showRowDivider = true

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

        -- Row 1: Enable Frame + Frame Scale
        local sharedEnableRow
        sharedEnableRow, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Frame",
              getValue=function()
                  return db.profile.enabledFrames[selectedUnit] ~= false
              end,
              setValue=function(v)
                  db.profile.enabledFrames[selectedUnit] = v
                  ReloadAndUpdate()
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Frame Scale", min=50, max=200, step=1,
              getValue=function() return SVal("frameScale", 100) end,
              setValue=function(v) SSet("frameScale", v) end });  y = y - h
        -- Sync icon: Frame Scale
        do
            local rgn = sharedEnableRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Frame Scale to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().frameScale or 100
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then
                            UNIT_DB_MAP[key]().frameScale = v
                        end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().frameScale or 100
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().frameScale or 100) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().frameScale or 100
                        for _, key in ipairs(checkedKeys) do
                            UNIT_DB_MAP[key]().frameScale = v
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Inline cog on Enable Frames for group visibility (player/target/focus only)
        do
            local rgn = sharedEnableRow._leftRegion
            local function VisSet(key, v)
                UNIT_DB_MAP[selectedUnit]()[key] = v
                if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Frame Display Options",
                rows = {
                    { type = "toggle", label = "In Raid Group",
                      get = function() local v = SGet("showInRaid"); if v == nil then return true end; return v ~= false end,
                      set = function(v) VisSet("showInRaid", v) end },
                    { type = "toggle", label = "In Party",
                      get = function() local v = SGet("showInParty"); if v == nil then return true end; return v ~= false end,
                      set = function(v) VisSet("showInParty", v) end },
                    { type = "toggle", label = "Solo",
                      get = function() local v = SGet("showSolo"); if v == nil then return true end; return v ~= false end,
                      set = function(v) VisSet("showSolo", v) end },
                },
            })
            local visCogBtn = MakeCogBtn(rgn, cogShow)

            -- Blocking overlay: disabled when Enable Frame is off
            local visCogBlock = CreateFrame("Frame", nil, visCogBtn)
            visCogBlock:SetAllPoints()
            visCogBlock:SetFrameLevel(visCogBtn:GetFrameLevel() + 10)
            visCogBlock:EnableMouse(true)
            visCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(visCogBtn, EllesmereUI.DisabledTooltip("Enable Frame"))
            end)
            visCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateVisCogDisabled()
                local frameEnabled = db.profile.enabledFrames[selectedUnit] ~= false
                if frameEnabled then
                    visCogBtn:SetAlpha(0.4)
                    visCogBlock:Hide()
                else
                    visCogBtn:SetAlpha(0.15)
                    visCogBlock:Show()
                end
            end
            UpdateVisCogDisabled()
            RegisterWidgetRefresh(UpdateVisCogDisabled)
        end

        -- Row 2: Dark Mode + Bar Texture
        local sharedDarkTexRow
        sharedDarkTexRow, h = W:DualRow(parent, y,
            { type="toggle", text="Dark Mode",
              getValue=function() return db.profile.darkTheme end,
              setValue=function(v)
                  db.profile.darkTheme = v
                  ReloadAndUpdate(); UpdatePreview()
                  EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Bar Texture", values=hbtValues, order=hbtOrder,
              getValue=function() return SVal("healthBarTexture", "none") end,
              setValue=function(v) SSet("healthBarTexture", v); ReloadAndUpdate(); UpdatePreview() end });  y = y - h
        -- Sync icon: Health Bar Texture
        do
            local rgn = sharedDarkTexRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Bar Texture to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().healthBarTexture or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then
                            UNIT_DB_MAP[key]().healthBarTexture = v
                        end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().healthBarTexture or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().healthBarTexture or "none") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().healthBarTexture or "none"
                        for _, key in ipairs(checkedKeys) do
                            UNIT_DB_MAP[key]().healthBarTexture = v
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 3: Border Color (with Highlight in cog)
        local sharedBorderRow
        sharedBorderRow, h = W:DualRow(parent, y,
            { type="colorpicker", text="Border Color",
              getValue=function()
                  local c = SGet("borderColor")
                  if not c then return 0, 0, 0 end
                  return c.r, c.g, c.b
              end,
              setValue=function(r, g, b)
                  UNIT_DB_MAP[selectedUnit]().borderColor = { r=r, g=g, b=b }
                  ReloadAndUpdate()
              end },
            { type="label", text="" });  y = y - h
        -- Sync icon: Border Color (deep compare for table values)
        do
            local rgn = sharedBorderRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Border Color to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().borderColor
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit and v then
                            UNIT_DB_MAP[key]().borderColor = { r=v.r, g=v.g, b=v.b }
                        end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().borderColor
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local other = UNIT_DB_MAP[key]().borderColor
                        if v and other then
                            if v.r ~= other.r or v.g ~= other.g or v.b ~= other.b then return false end
                        elseif v ~= other then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().borderColor
                        for _, key in ipairs(checkedKeys) do
                            if v then UNIT_DB_MAP[key]().borderColor = { r=v.r, g=v.g, b=v.b } end
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        -- Inline cog on Border Color for Highlight Color + Border Size
        do
            local leftRgn = sharedBorderRow._leftRegion
            local _, borderCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Border Settings",
                rows = {
                    { type="slider", label="Size", min=0, max=4, step=1,
                      get=function() return SVal("borderSize", 1) end,
                      set=function(v) SSet("borderSize", v) end },
                    { type="colorpicker", label="Highlight Color",
                      get=function()
                          local c = SGet("highlightColor")
                          if not c then return 1, 1, 1 end
                          return c.r, c.g, c.b
                      end,
                      set=function(r, g, b)
                          UNIT_DB_MAP[selectedUnit]().highlightColor = { r=r, g=g, b=b }
                          ReloadAndUpdate()
                      end },
                },
            })
            local borderCogShow = borderCogShowRaw
            MakeCogBtn(leftRgn, borderCogShow, nil, EllesmereUI.RESIZE_ICON)
        end

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
                  return db.profile.portraitStyle or "attached"
              end,
              setValue=function(v)
                  db.profile.portraitStyle = v
                  -- Reset detached-only settings when leaving detached mode
                  if v ~= "detached" then
                      UNIT_DB_MAP[selectedUnit]().portraitSize = 0
                  end
                  UNIT_DB_MAP[selectedUnit]().showPortrait = (v ~= "none")
                  ReloadAndUpdate(); UpdatePreview()
                  C_Timer.After(0, function() local rl = EllesmereUI._widgetRefreshList; if rl then for i = 1, #rl do rl[i]() end end end)
              end },
            { type="dropdown", text="Art Style", values=portraitArtValues, order=portraitArtOrder,
              disabled=function() return (db.profile.portraitStyle or "attached") == "none" end,
              disabledTooltip="Portrait Mode is set to None",
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
                  ReloadAndUpdate(); UpdatePreview()
              end });  y = y - h
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

        -- Row 2: Size + Position
        local portraitLocationValues = { ["left"] = "Left", ["right"] = "Right", ["top"] = "Top" }
        local portraitLocationOrder = { "left", "right", "top" }
        local sharedSizePosRow
        sharedSizePosRow, h = W:DualRow(parent, y,
            { type="slider", text="Size", min=-20, max=40, step=1,
              disabled=function() return (db.profile.portraitStyle or "attached") ~= "detached" end,
              disabledTooltip="Only available when Portrait Mode is Detached",
              getValue=function() return SVal("portraitSize", 0) end,
              setValue=function(v) SSet("portraitSize", v); UpdatePreview() end },
            { type="dropdown", text="Position", values=portraitLocationValues, order=portraitLocationOrder,
              disabled=function() return (db.profile.portraitStyle or "attached") == "none" end,
              disabledTooltip="Portrait Mode is set to None",
              itemDisabled=function(v) return v == "top" and (db.profile.portraitStyle or "attached") == "attached" end,
              itemDisabledTooltip=function(v) if v == "top" then return "Top position is only available in Detached mode" end end,
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
                    { type="slider", label="Art Scale", min=50, max=200, step=1,
                      get=function() return SVal("portraitArtScale", 100) end,
                      set=function(v) SSet("portraitArtScale", v); UpdatePreview() end },
                },
            })
            local posCogShow = posCogShowRaw
            local cogBtn = MakeCogBtn(posRgn, posCogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local function UpdatePosCogState()
                local pStyle = db.profile.portraitStyle or "attached"
                if pStyle == "detached" then cogBtn:SetAlpha(0.4); cogBtn:Enable()
                else cogBtn:SetAlpha(0.15); cogBtn:Disable() end
            end
            cogBtn:SetScript("OnEnter", function(self)
                if (db.profile.portraitStyle or "attached") == "detached" then
                    self:SetAlpha(0.7)
                else
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Portrait Mode is set to Detached"))
                end
            end)
            cogBtn:SetScript("OnLeave", function(self) UpdatePosCogState(); EllesmereUI.HideWidgetTooltip() end)
            cogBtn:SetScript("OnClick", function(self) posCogShow(self) end)
            UpdatePosCogState()
            RegisterWidgetRefresh(UpdatePosCogState)
        end

        -- Row 3: Shape + Shape Border (color swatch + cog)
        local sharedShapeBorderRow
        sharedShapeBorderRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Shape", values=detPortraitShapeValues, order=detPortraitShapeOrder,
              disabled=function() return (db.profile.portraitStyle or "attached") ~= "detached" end,
              disabledTooltip="This option is only available when Portrait Mode is Detached.",
              getValue=function() return SVal("detachedPortraitShape", "portrait") end,
              setValue=function(v)
                  SSet("detachedPortraitShape", v); UpdatePreview()
              end },
            { type="colorpicker", text="Shape Border",
              disabled=function() return (db.profile.portraitStyle or "attached") ~= "detached" end,
              disabledTooltip="Only available when Portrait Mode is Detached",
              getValue=function()
                  local c = SGet("detachedPortraitBorderColor")
                  c = c or { r=0, g=0, b=0 }
                  local a = SGet("detachedPortraitBorderOpacity")
                  return c.r, c.g, c.b, (a or 100) / 100
              end,
              setValue=function(r, g, b, a)
                  UNIT_DB_MAP[selectedUnit]().detachedPortraitBorderColor = { r=r, g=g, b=b }
                  UNIT_DB_MAP[selectedUnit]().detachedPortraitBorderOpacity = math.floor(a * 100 + 0.5)
                  ReloadAndUpdate(); UpdatePreview()
              end,
              hasAlpha=true });  y = y - h
        -- Disabled state for Shape Border swatch
        do
            local borderRgn = sharedShapeBorderRow._rightRegion
            local sw = borderRgn._control
            local function UpdateSwatchState()
                local pStyle = db.profile.portraitStyle or "attached"
                if pStyle ~= "detached" then
                    sw:SetAlpha(0.15); sw:Disable()
                    sw._disabledTooltip = "Only available when Portrait Mode is Detached"
                else
                    local useCC = SVal("detachedPortraitClassColor", true)
                    if useCC then
                        sw:SetAlpha(0.25); sw:Disable()
                        sw._disabledTooltip = "Disabled while Class Color is enabled"
                    else
                        sw:SetAlpha(1); sw:Enable()
                        sw._disabledTooltip = nil
                    end
                end
            end
            UpdateSwatchState()
            RegisterWidgetRefresh(UpdateSwatchState)
            sw:HookScript("OnEnter", function(self)
                if self._disabledTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip(self._disabledTooltip))
                end
            end)
            sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        end
        -- Cog on Shape Border for border settings
        do
            local borderRgn = sharedShapeBorderRow._rightRegion
            local _, detShapeCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Shape Border Settings",
                rows = {
                    { type="toggle", label="Class Color",
                      get=function() return SVal("detachedPortraitClassColor", true) end,
                      set=function(v)
                          SSet("detachedPortraitClassColor", v); UpdatePreview()
                      end },
                    { type="slider", label="Size", min=1, max=7, step=1,
                      get=function() return SVal("detachedPortraitBorderSize", 7) end,
                      set=function(v) SSet("detachedPortraitBorderSize", v); UpdatePreview() end },
                    { type="slider", label="Border", min=0, max=100, step=1,
                      get=function() return SVal("detachedPortraitBorderOpacity", 100) end,
                      set=function(v) SSet("detachedPortraitBorderOpacity", v); UpdatePreview() end },
                },
            })
            local detShapeCogShow = detShapeCogShowRaw
            local cogBtn = MakeCogBtn(borderRgn, detShapeCogShow)
            local function UpdateDetShapeCogState()
                local pStyle = db.profile.portraitStyle or "attached"
                if pStyle == "detached" then cogBtn:SetAlpha(0.4); cogBtn:Enable()
                else cogBtn:SetAlpha(0.15); cogBtn:Disable() end
            end
            cogBtn:SetScript("OnEnter", function(self)
                if (db.profile.portraitStyle or "attached") == "detached" then
                    self:SetAlpha(0.7)
                else
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Only available when Portrait Mode is Detached"))
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

        _, h = W:Spacer(parent, y, 20); y = y - h

        -------------------------------------------------------------------
        --  HEALTH BAR
        -------------------------------------------------------------------
        local sharedBarsHeader
        sharedBarsHeader, h = W:SectionHeader(parent, "HEALTH BAR", y); y = y - h

        -- Row 1: Bar Height + Bar Width (was Frame Width)
        local sharedSizeRow
        sharedSizeRow, h = W:DualRow(parent, y,
            { type="slider", text="Bar Height", min=15, max=100, step=1,
              getValue=function() return SVal("healthHeight", 46) end,
              setValue=function(v) SSet("healthHeight", v) end },
            { type="slider", text="Bar Width", min=80, max=400, step=1,
              getValue=function() return SVal("frameWidth", 181) end,
              setValue=function(v) SSet("frameWidth", v) end });  y = y - h
        -- Sync icons: Bar Height (left) and Bar Width (right)
        do
            local rgn = sharedSizeRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Bar Height to all Frames",
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

        -- Row 2: Bar Color (multiSwatch) + Bar Opacity (slider)
        local sharedHealthColorRow
        sharedHealthColorRow, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Bar Color",
              swatches = {
                { tooltip = "Bar Background",
                  hasAlpha = false,
                  getValue = function()
                      local c = SGet("customBgColor")
                      if c then return c.r, c.g, c.b end
                      return 17/255, 17/255, 17/255
                  end,
                  setValue = function(r, g, b)
                      UNIT_DB_MAP[selectedUnit]().customBgColor = { r=r, g=g, b=b }
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
            { type="slider", text="Bar Opacity", min=10, max=100, step=1,
              getValue=function() return SVal("healthBarOpacity", 90) end,
              setValue=function(v)
                  SSet("healthBarOpacity", v)
                  UpdatePreview()
              end });  y = y - h
        -- Sync icons: Bar Color (left) and Bar Opacity (right)
        do
            local rgn = sharedHealthColorRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Bar Color to all Frames",
                onClick = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    local cc = src.healthClassColored or false
                    local fc = src.customFillColor
                    local bc = src.customBgColor or { r=17/255, g=17/255, b=17/255 }
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then
                            local d = UNIT_DB_MAP[key]()
                            d.healthClassColored = cc
                            if fc then d.customFillColor = { r=fc.r, g=fc.g, b=fc.b }
                            else d.customFillColor = nil end
                            d.customBgColor = { r=bc.r, g=bc.g, b=bc.b }
                        end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    local cc = src.healthClassColored or false
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().healthClassColored or false) ~= cc then return false end
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
                        local cc = src.healthClassColored or false
                        local fc = src.customFillColor
                        local bc = src.customBgColor or { r=17/255, g=17/255, b=17/255 }
                        for _, key in ipairs(checkedKeys) do
                            local d = UNIT_DB_MAP[key]()
                            d.healthClassColored = cc
                            if fc then d.customFillColor = { r=fc.r, g=fc.g, b=fc.b }
                            else d.customFillColor = nil end
                            d.customBgColor = { r=bc.r, g=bc.g, b=bc.b }
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = sharedHealthColorRow._rightRegion
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

        -- Row 3: Left Text + Right Text
        local sharedTextRow
        sharedTextRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Left Text", values=healthTextValues, order=healthTextOrder,
              getValue=function() return SVal("leftTextContent", "name") end,
              setValue=function(v)
                  SSet("leftTextContent", v)
                  if v ~= "none" then
                      local rv = SGet("rightTextContent")
                      if rv == v then SSet("rightTextContent", "none") end
                  end
                  UpdatePreview()
              end },
            { type="dropdown", text="Right Text", values=healthTextValues, order=healthTextOrder,
              getValue=function() return SVal("rightTextContent", "both") end,
              setValue=function(v)
                  SSet("rightTextContent", v)
                  if v ~= "none" then
                      local lv = SGet("leftTextContent")
                      if lv == v then SSet("leftTextContent", "none") end
                  end
                  UpdatePreview()
              end });  y = y - h
        -- Sync icons: Left Text (left) and Right Text (right)
        do
            local rgn = sharedTextRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Left Text to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().leftTextContent or "name"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then UNIT_DB_MAP[key]().leftTextContent = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().leftTextContent or "name"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().leftTextContent or "name") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().leftTextContent or "name"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().leftTextContent = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = sharedTextRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Right Text to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().rightTextContent or "both"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then UNIT_DB_MAP[key]().rightTextContent = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().rightTextContent or "both"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().rightTextContent or "both") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().rightTextContent or "both"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().rightTextContent = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        -- Cogwheel on Left Text
        do
            local leftRgn = sharedTextRow._leftRegion
            local _, leftCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Left Text Settings",
                rows = {
                    { type="toggle", label="Class Color",
                      get=function() return SVal("leftTextClassColor", false) end,
                      set=function(v) SSet("leftTextClassColor", v); UpdatePreview() end },
                    { type="slider", label="Size", min=8, max=24, step=1,
                      get=function() return SVal("leftTextSize", SDB().textSize or 12) end,
                      set=function(v) SSet("leftTextSize", v); UpdatePreview() end },
                    { type="slider", label="X", min=-50, max=50, step=1,
                      get=function() return SVal("leftTextX", 0) end,
                      set=function(v) SSet("leftTextX", v); UpdatePreview() end },
                    { type="slider", label="Y", min=-30, max=30, step=1,
                      get=function() return SVal("leftTextY", 0) end,
                      set=function(v) SSet("leftTextY", v); UpdatePreview() end },
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
        -- Cogwheel on Right Text
        do
            local rightRgn = sharedTextRow._rightRegion
            local _, rightCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Right Text Settings",
                rows = {
                    { type="toggle", label="Class Color",
                      get=function() return SVal("rightTextClassColor", false) end,
                      set=function(v) SSet("rightTextClassColor", v); UpdatePreview() end },
                    { type="slider", label="Size", min=8, max=24, step=1,
                      get=function() return SVal("rightTextSize", SDB().textSize or 12) end,
                      set=function(v) SSet("rightTextSize", v); UpdatePreview() end },
                    { type="slider", label="X", min=-50, max=50, step=1,
                      get=function() return SVal("rightTextX", 0) end,
                      set=function(v) SSet("rightTextX", v); UpdatePreview() end },
                    { type="slider", label="Y", min=-30, max=30, step=1,
                      get=function() return SVal("rightTextY", 0) end,
                      set=function(v) SSet("rightTextY", v); UpdatePreview() end },
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

        -- Row 4: Center Text + empty
        local sharedCenterTextRow
        sharedCenterTextRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Center Text", values=healthTextValues, order=healthTextOrder,
              getValue=function() return SVal("centerTextContent", "none") end,
              setValue=function(v)
                  SSet("centerTextContent", v)
                  if v ~= "none" then
                      SSet("leftTextContent", "none")
                      SSet("rightTextContent", "none")
                  end
                  ReloadAndUpdate(); UpdatePreview()
              end },
            { type="label", text="" });  y = y - h
        -- Sync icon: Center Text (left)
        do
            local rgn = sharedCenterTextRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Center Text to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().centerTextContent or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then UNIT_DB_MAP[key]().centerTextContent = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().centerTextContent or "none"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().centerTextContent or "none") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().centerTextContent or "none"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().centerTextContent = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        -- Cogwheel on Center Text
        do
            local ctrRgn = sharedCenterTextRow._leftRegion
            local _, centerCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Center Text Settings",
                rows = {
                    { type="toggle", label="Class Color",
                      get=function() return SVal("centerTextClassColor", false) end,
                      set=function(v) SSet("centerTextClassColor", v); UpdatePreview() end },
                    { type="slider", label="Size", min=8, max=24, step=1,
                      get=function() return SVal("centerTextSize", SDB().textSize or 12) end,
                      set=function(v) SSet("centerTextSize", v); UpdatePreview() end },
                    { type="slider", label="X", min=-50, max=50, step=1,
                      get=function() return SVal("centerTextX", 0) end,
                      set=function(v) SSet("centerTextX", v); UpdatePreview() end },
                    { type="slider", label="Y", min=-30, max=30, step=1,
                      get=function() return SVal("centerTextY", 0) end,
                      set=function(v) SSet("centerTextY", v); UpdatePreview() end },
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
            { type="slider", text="Bar Height", min=0, max=30, step=1,
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
                tooltip = "Apply Bar Height to all Frames",
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

        -- Row 2: Power Text (format) + Text Position
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
            { type="dropdown", text="Text Position", values=ppTextValues, order=ppTextOrder,
              getValue=function() return SVal("powerPercentText", "none") end,
              setValue=function(v) SSet("powerPercentText", v); ReloadAndUpdate(); UpdatePreview() end });  y = y - h
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
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Show % is only available for formats that display a percentage."))
                else self:SetAlpha(0.7) end
            end)
            fmtCogBtn:SetScript("OnLeave", function(self) UpdateFmtCogState(); EllesmereUI.HideWidgetTooltip() end)
            fmtCogBtn:SetScript("OnClick", function(self) fmtCogShow(self) end)
            UpdateFmtCogState()
            RegisterWidgetRefresh(UpdateFmtCogState)
        end
        -- Cogwheel on Text Position for size + x/y offsets
        do
            local ppRgn = sharedPowerRow2._rightRegion
            local _, ppCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Text Position",
                rows = {
                    { type="slider", label="Size", min=6, max=24, step=1,
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
        -- Sync icons: Power Text Format (left) and Text Position (right)
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
        do
            local rgn = sharedPowerRow2._rightRegion
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

        -- Row 3: Bar Color (multiSwatch) + Power Bar Opacity (slider)
        local sharedPowerRow3
        sharedPowerRow3, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Bar Color",
              swatches = {
                { tooltip = "Bar Background",
                  hasAlpha = false,
                  getValue = function()
                      local c = SGet("customPowerBgColor")
                      if c then return c.r, c.g, c.b end
                      return 17/255, 17/255, 17/255
                  end,
                  setValue = function(r, g, b)
                      UNIT_DB_MAP[selectedUnit]().customPowerBgColor = { r=r, g=g, b=b }
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
                      local pType = UnitPowerType("player")
                      local info = PowerBarColor[pType]
                      if info then return info.r, info.g, info.b end
                      return 0, 0, 1
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
            { type="slider", text="Power Bar Opacity", min=10, max=100, step=1,
              getValue=function() return SVal("powerBarOpacity", 100) end,
              setValue=function(v)
                  SSet("powerBarOpacity", v)
                  UpdatePreview()
              end });  y = y - h
        -- Sync icons: Bar Color (left) and Power Bar Opacity (right)
        do
            local rgn = sharedPowerRow3._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Bar Color to all Frames",
                onClick = function()
                    local src = UNIT_DB_MAP[selectedUnit]()
                    local pc = src.powerPercentPowerColor
                    if pc == nil then pc = true end
                    local fc = src.customPowerFillColor
                    local bc = src.customPowerBgColor or { r=17/255, g=17/255, b=17/255 }
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if key ~= selectedUnit then
                            local d = UNIT_DB_MAP[key]()
                            d.powerPercentPowerColor = pc
                            if fc then d.customPowerFillColor = { r=fc.r, g=fc.g, b=fc.b }
                            else d.customPowerFillColor = nil end
                            d.customPowerBgColor = { r=bc.r, g=bc.g, b=bc.b }
                        end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().powerPercentPowerColor
                    if v == nil then v = true end
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local ov = UNIT_DB_MAP[key]().powerPercentPowerColor
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
                        local src = UNIT_DB_MAP[selectedUnit]()
                        local pc = src.powerPercentPowerColor
                        if pc == nil then pc = true end
                        local fc = src.customPowerFillColor
                        local bc = src.customPowerBgColor or { r=17/255, g=17/255, b=17/255 }
                        for _, key in ipairs(checkedKeys) do
                            local d = UNIT_DB_MAP[key]()
                            d.powerPercentPowerColor = pc
                            if fc then d.customPowerFillColor = { r=fc.r, g=fc.g, b=fc.b }
                            else d.customPowerFillColor = nil end
                            d.customPowerBgColor = { r=bc.r, g=bc.g, b=bc.b }
                        end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = sharedPowerRow3._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Power Bar Opacity to all Frames",
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

        -- Row 4: Text Color (multiSwatch: custom left, power colored right) + empty
        local sharedPowerRow4
        sharedPowerRow4, h = W:DualRow(parent, y,
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
                      local pType = UnitPowerType("player")
                      local info = PowerBarColor[pType]
                      if info then return info.r, info.g, info.b end
                      return 0, 0, 1
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
              } },
            { type="label", text="" });  y = y - h
        -- Sync icon: Text Color (left of row 4)
        do
            local rgn = sharedPowerRow4._leftRegion
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

        -- Helper: build a checkbox dropdown summary label
        local function CBSummaryLabel(getFn)
            local names = {}
            local unitLabels = { player = "Player", target = "Target", focus = "Focus" }
            local unitOrder = { "player", "target", "focus" }
            for _, u in ipairs(unitOrder) do
                if getFn(u) then names[#names + 1] = unitLabels[u] end
            end
            if #names == 3 then return "All"
            elseif #names == 0 then return "None"
            else return table.concat(names, ", ") end
        end

        -- Helper: build an inline checkbox dropdown (button + flyout with checkboxes)
        -- items = { { key, label }, ... }, getFn(key)->bool, setFn(key,bool), onChanged()
        local function BuildCBDropdown(parentFrame, ddW, fLevel, items, getFn, setFn, onChanged)
            local ddBtn = CreateFrame("Button", nil, parentFrame)
            PP.Size(ddBtn, ddW, 30)
            ddBtn:SetFrameLevel(fLevel)
            local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
            ddBg:SetAllPoints()
            ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            local ddBrd = EllesmereUI.MakeBorder(ddBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
            local ddLbl = ddBtn:CreateFontString(nil, "OVERLAY")
            local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("options") or "Fonts\\FRIZQT__.TTF"
            ddLbl:SetFont(fontPath, 13, "")
            ddLbl:SetTextColor(1, 1, 1, 0.7)
            ddLbl:SetJustifyH("LEFT")
            ddLbl:SetWordWrap(false)
            ddLbl:SetMaxLines(1)
            ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 12, 0)
            ddLbl:SetPoint("RIGHT", ddBtn, "RIGHT", -24, 0)
            local arrow = EllesmereUI.MakeDropdownArrow(ddBtn, 12, PP)

            local menu
            local function UpdateLabel()
                ddLbl:SetText(CBSummaryLabel(getFn))
            end
            UpdateLabel()

            local function EnsureMenu()
                if menu then return end
                local ITEM_H = 28
                local menuH = 4 + #items * ITEM_H + 4
                menu = CreateFrame("Frame", nil, UIParent)
                menu:SetFrameStrata("FULLSCREEN_DIALOG")
                menu:SetFrameLevel(200)
                menu:SetClampedToScreen(true)
                menu:EnableMouse(true)
                menu:SetSize(ddW, menuH)
                menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
                menu:Hide()
                local mBg = menu:CreateTexture(nil, "BACKGROUND")
                mBg:SetAllPoints()
                mBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA or 0.92)
                EllesmereUI.MakeBorder(menu, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
                local ppScale = EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale() or 1
                menu:SetScale(ppScale)

                local yOff = -4
                for _, item in ipairs(items) do
                    local row = CreateFrame("Button", nil, menu)
                    row:SetHeight(ITEM_H)
                    row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, yOff)
                    row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, yOff)
                    row:SetFrameLevel(menu:GetFrameLevel() + 2)
                    local box = CreateFrame("Frame", nil, row)
                    box:SetSize(16, 16)
                    box:SetPoint("LEFT", row, "LEFT", 10, 0)
                    local boxBg = box:CreateTexture(nil, "BACKGROUND")
                    boxBg:SetAllPoints()
                    boxBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                    local boxBrd = EllesmereUI.MakeBorder(box, 0.4, 0.4, 0.4, 0.6, PP)
                    local chk = box:CreateTexture(nil, "ARTWORK")
                    PP.SetInside(chk, box, 2, 2)
                    chk:SetColorTexture(EllesmereUI.ELLESMERE_GREEN.r, EllesmereUI.ELLESMERE_GREEN.g, EllesmereUI.ELLESMERE_GREEN.b, 1)
                    local lbl = row:CreateFontString(nil, "OVERLAY")
                    lbl:SetFont(fontPath, 13, "")
                    lbl:SetTextColor(0.75, 0.75, 0.75, 1)
                    lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
                    lbl:SetText(item.label)
                    local hl = row:CreateTexture(nil, "ARTWORK")
                    hl:SetAllPoints()
                    hl:SetColorTexture(1, 1, 1, 0)
                    local function UpdateCheck()
                        if getFn(item.key) then
                            chk:Show()
                            boxBrd:SetColor(EllesmereUI.ELLESMERE_GREEN.r, EllesmereUI.ELLESMERE_GREEN.g, EllesmereUI.ELLESMERE_GREEN.b, 0.8)
                        else
                            chk:Hide()
                            boxBrd:SetColor(0.4, 0.4, 0.4, 0.6)
                        end
                    end
                    UpdateCheck()
                    row._updateCheck = UpdateCheck
                    row:SetScript("OnEnter", function() lbl:SetTextColor(1, 1, 1, 1); hl:SetColorTexture(1, 1, 1, 0.04) end)
                    row:SetScript("OnLeave", function() lbl:SetTextColor(0.75, 0.75, 0.75, 1); hl:SetColorTexture(1, 1, 1, 0) end)
                    row:SetScript("OnClick", function()
                        setFn(item.key, not getFn(item.key))
                        UpdateCheck(); UpdateLabel()
                        if onChanged then onChanged() end
                    end)
                    yOff = yOff - ITEM_H
                end
                ddBtn._ddMenu = menu
            end

            ddBtn:SetScript("OnEnter", function()
                ddLbl:SetTextColor(1, 1, 1, 1)
                ddBrd:SetColor(1, 1, 1, EllesmereUI.DD_BRD_HA or 0.25)
                ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA or 0.92)
            end)
            ddBtn:SetScript("OnLeave", function()
                if not (menu and menu:IsShown()) then
                    ddLbl:SetTextColor(1, 1, 1, 0.7)
                    ddBrd:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A)
                    ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                end
            end)
            ddBtn:SetScript("OnClick", function()
                EnsureMenu()
                if menu:IsShown() then menu:Hide() else menu:Show() end
            end)
            ddBtn:HookScript("OnHide", function() if menu then menu:Hide() end end)

            local function RefreshAll()
                UpdateLabel()
                if menu then
                    for _, child in pairs({menu:GetChildren()}) do
                        if child._updateCheck then child._updateCheck() end
                    end
                end
            end
            return ddBtn, RefreshAll
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

        -- Row 1: Show Cast Bars (checkbox dropdown) | Height (slider)
        local sharedCastRow1
        sharedCastRow1, h = W:DualRow(parent, y,
            { type="dropdown", text="Show Cast Bars",
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end },
            { type="slider", text="Height", min=1, max=40, step=1,
              getValue=GetCastbarHeight,
              setValue=function(v) SetCastbarHeight(v); ReloadAndUpdate(); UpdatePreview() end });  y = y - h

        -- Replace the dummy dropdown with our checkbox dropdown
        do
            local leftRgn = sharedCastRow1._leftRegion
            if leftRgn._control then leftRgn._control:Hide() end

            local castbarItems = {
                { key = "player", label = "Player" },
                { key = "target", label = "Target" },
                { key = "focus",  label = "Focus" },
            }
            local cbDD, cbDDRefresh = BuildCBDropdown(leftRgn, 170, leftRgn:GetFrameLevel() + 2,
                castbarItems, GetCastbarEnabled, function(k, v)
                    SetCastbarEnabled(k, v)
                    ReloadAndUpdate(); UpdatePreview()
                    EllesmereUI:RefreshPage()
                end)
            PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
            leftRgn._control = cbDD
            leftRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)

            -- Hide While Not Casting helpers
            local function GetHideInactive(unitKey)
                local v = UNIT_DB_MAP[unitKey]().castbarHideWhenInactive
                if v == nil then return (unitKey ~= "target") end
                return v
            end
            local function SetHideInactive(unitKey, val)
                UNIT_DB_MAP[unitKey]().castbarHideWhenInactive = val
            end

            -- Cog popup: Hide Idle toggles + Show Icon + Class Colored Player
            local _, castCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Cast Bar Settings",
                rows = {
                    { type="toggle", label="Hide Idle Player Cast Bar",
                      get=function() return GetHideInactive("player") end,
                      set=function(v) SetHideInactive("player", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="toggle", label="Hide Idle Target Cast Bar",
                      get=function() return GetHideInactive("target") end,
                      set=function(v) SetHideInactive("target", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="toggle", label="Hide Idle Focus Cast Bar",
                      get=function() return GetHideInactive("focus") end,
                      set=function(v) SetHideInactive("focus", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="toggle", label="Show Icon",
                      get=function()
                          if selectedUnit == "player" then return UNIT_DB_MAP.player().showPlayerCastIcon ~= false
                          else return UNIT_DB_MAP[selectedUnit]().showCastIcon ~= false end
                      end,
                      set=function(v)
                          if selectedUnit == "player" then UNIT_DB_MAP.player().showPlayerCastIcon = v
                          else UNIT_DB_MAP[selectedUnit]().showCastIcon = v end
                          ReloadAndUpdate(); UpdatePreview()
                      end },
                    { type="toggle", label="Class Colored Player",
                      get=function() return UNIT_DB_MAP.player().castbarClassColored or false end,
                      set=function(v)
                          UNIT_DB_MAP.player().castbarClassColored = v
                          ReloadAndUpdate(); UpdatePreview()
                      end },
                },
            })
            local castCogShow = castCogShowRaw

            MakeCogBtn(leftRgn, castCogShow)

            -- Inline fill color swatch
            local cbSw = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5,
                function()
                    local c = SGetSupported("castbarFillColor")
                    c = c or { r=1, g=0.7, b=0 }
                    return c.r, c.g, c.b, 1
                end,
                function(r, g, b)
                    UNIT_DB_MAP[selectedUnit]().castbarFillColor = { r=r, g=g, b=b }
                    ReloadAndUpdate(); UpdatePreview()
                end, false, 20)
            cbSw:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -12, 0)
            cbSw:SetScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, "Fill Color") end)
            cbSw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            leftRgn._lastInline = cbSw

            -- Blocking overlay: disabled when no cast bars are enabled
            local cbSwBlock = CreateFrame("Frame", nil, cbSw)
            cbSwBlock:SetAllPoints()
            cbSwBlock:SetFrameLevel(cbSw:GetFrameLevel() + 10)
            cbSwBlock:EnableMouse(true)
            cbSwBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cbSw, EllesmereUI.DisabledTooltip("Show Cast Bars"))
            end)
            cbSwBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCBSwDisabled()
                local anyOn = false
                for _, u in ipairs({"player", "target", "focus"}) do
                    if GetCastbarEnabled(u) then anyOn = true; break end
                end
                if anyOn then cbSw:SetAlpha(1); cbSwBlock:Hide()
                else cbSw:SetAlpha(0.3); cbSwBlock:Show() end
            end
            UpdateCBSwDisabled()
            EllesmereUI.RegisterWidgetRefresh(UpdateCBSwDisabled)
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

        -- Row 2: Spell Name Size (with inline color swatch) | Duration Size (with inline color swatch)
        local castTextRow
        castTextRow, h = W:DualRow(parent, y,
            { type="slider", text="Spell Name Size", min=6, max=20, step=1,
              getValue=function() return SValSupported("castSpellNameSize", 11) end,
              setValue=function(v) SSetSupported("castSpellNameSize", v); ReloadAndUpdate(); UpdatePreview() end },
            { type="slider", text="Duration Size", min=6, max=20, step=1,
              getValue=function() return SValSupported("castDurationSize", 11) end,
              setValue=function(v) SSetSupported("castDurationSize", v); ReloadAndUpdate(); UpdatePreview() end });  y = y - h
        SApplySupport(castTextRow._leftRegion, "castSpellNameSize")
        SApplySupport(castTextRow._rightRegion, "castDurationSize")
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
        -- Sync icons: Spell Name Size (left) and Duration Size (right)
        do
            local rgn = castTextRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Spell Name Size to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().castSpellNameSize or 11
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().castSpellNameSize = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().castSpellNameSize or 11
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().castSpellNameSize or 11) ~= v then return false end
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
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().castSpellNameSize = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = castTextRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Duration Size to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().castDurationSize or 11
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().castDurationSize = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().castDurationSize or 11
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().castDurationSize or 11) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().castDurationSize or 11
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().castDurationSize = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

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
              setValue=function(v) SSet("bottomTextBar", v); UpdatePreview() end },
            { type="dropdown", text="Position", values=btbPositionValues, order=btbPositionOrder,
              disabled=function() return not SVal("bottomTextBar", false) end,
              disabledTooltip="Enable Text Bar is off",
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
                    sw._disabledTooltip = "Enable Text Bar is off"
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
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Enable Text Bar is off"))
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

        -- Row 2: Height + Width
        local sharedBtbHeightRow
        sharedBtbHeightRow, h = W:DualRow(parent, y,
            { type="slider", text="Height", min=0, max=40, step=1,
              disabled=function() return not SVal("bottomTextBar", false) end,
              disabledTooltip="Enable Text Bar is off",
              getValue=function() return SVal("bottomTextBarHeight", 16) end,
              setValue=function(v) SSet("bottomTextBarHeight", v); UpdatePreview() end },
            { type="slider", text="Width", min=0, max=400, step=1,
              disabled=function()
                  if not SVal("bottomTextBar", false) then return true end
                  local pos = SVal("btbPosition", "bottom")
                  return pos ~= "detached_top" and pos ~= "detached_bottom"
              end,
              disabledTooltip=function()
                  if not SVal("bottomTextBar", false) then return "Enable Text Bar is off" end
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
        local sharedBtbTextRow
        sharedBtbTextRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Left Text", values=btbTextValues, order=btbTextOrder,
              disabled=function() return not SVal("bottomTextBar", false) end,
              disabledTooltip="Enable Text Bar is off",
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
              disabledTooltip="Enable Text Bar is off",
              getValue=function() return SVal("btbRightContent", "none") end,
              setValue=function(v)
                  SSet("btbRightContent", v)
                  if v ~= "none" then
                      if SGet("btbLeftContent") == v then SSet("btbLeftContent", "none") end
                      if SGet("btbCenterContent") == v then SSet("btbCenterContent", "none") end
                  end
                  ReloadAndUpdate(); UpdatePreview()
              end });  y = y - h
        -- Cogwheel on BTB Left Text
        do
            local btbLRgn = sharedBtbTextRow._leftRegion
            local _, btbLeftCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "BTB Left Text Settings",
                rows = {
                    { type="toggle", label="Class Color",
                      get=function() return SVal("btbLeftClassColor", false) end,
                      set=function(v) SSet("btbLeftClassColor", v); UpdatePreview() end },
                    { type="toggle", label="Power Color",
                      get=function() return SVal("btbLeftPowerColor", false) end,
                      set=function(v) SSet("btbLeftPowerColor", v); UpdatePreview() end },
                    { type="slider", label="Size", min=8, max=24, step=1,
                      get=function() return SVal("btbLeftSize", 11) end,
                      set=function(v) SSet("btbLeftSize", v); UpdatePreview() end },
                    { type="slider", label="X", min=-50, max=50, step=1,
                      get=function() return SVal("btbLeftX", 0) end,
                      set=function(v) SSet("btbLeftX", v); UpdatePreview() end },
                    { type="slider", label="Y", min=-30, max=30, step=1,
                      get=function() return SVal("btbLeftY", 0) end,
                      set=function(v) SSet("btbLeftY", v); UpdatePreview() end },
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
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Enable Text Bar is off"))
                elseif isNone then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Left Text is set to None"))
                else self:SetAlpha(0.7) end
            end)
            btbLCogBtn:SetScript("OnLeave", function(self) UpdateBtbLCogState(); EllesmereUI.HideWidgetTooltip() end)
            btbLCogBtn:SetScript("OnClick", function(self) btbLeftCogShow(self) end)
            UpdateBtbLCogState()
            RegisterWidgetRefresh(UpdateBtbLCogState)
        end
        -- Cogwheel on BTB Right Text
        do
            local btbRRgn = sharedBtbTextRow._rightRegion
            local _, btbRightCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "BTB Right Text Settings",
                rows = {
                    { type="toggle", label="Class Color",
                      get=function() return SVal("btbRightClassColor", false) end,
                      set=function(v) SSet("btbRightClassColor", v); UpdatePreview() end },
                    { type="toggle", label="Power Color",
                      get=function() return SVal("btbRightPowerColor", false) end,
                      set=function(v) SSet("btbRightPowerColor", v); UpdatePreview() end },
                    { type="slider", label="Size", min=8, max=24, step=1,
                      get=function() return SVal("btbRightSize", 11) end,
                      set=function(v) SSet("btbRightSize", v); UpdatePreview() end },
                    { type="slider", label="X", min=-50, max=50, step=1,
                      get=function() return SVal("btbRightX", 0) end,
                      set=function(v) SSet("btbRightX", v); UpdatePreview() end },
                    { type="slider", label="Y", min=-30, max=30, step=1,
                      get=function() return SVal("btbRightY", 0) end,
                      set=function(v) SSet("btbRightY", v); UpdatePreview() end },
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
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Enable Text Bar is off"))
                elseif isNone then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Right Text is set to None"))
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
        local sharedBtbCenterRow
        sharedBtbCenterRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Center Text", values=btbTextValues, order=btbTextOrder,
              disabled=function() return not SVal("bottomTextBar", false) end,
              disabledTooltip="Enable Text Bar is off",
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
              disabledTooltip="Enable Text Bar is off",
              getValue=function() return SVal("btbClassIcon", "none") end,
              setValue=function(v) SSet("btbClassIcon", v); UpdatePreview() end });  y = y - h
        -- Cogwheel on BTB Center Text
        do
            local btbCRgn = sharedBtbCenterRow._leftRegion
            local _, btbCenterCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "BTB Center Text Settings",
                rows = {
                    { type="toggle", label="Class Color",
                      get=function() return SVal("btbCenterClassColor", false) end,
                      set=function(v) SSet("btbCenterClassColor", v); UpdatePreview() end },
                    { type="toggle", label="Power Color",
                      get=function() return SVal("btbCenterPowerColor", false) end,
                      set=function(v) SSet("btbCenterPowerColor", v); UpdatePreview() end },
                    { type="slider", label="Size", min=8, max=24, step=1,
                      get=function() return SVal("btbCenterSize", 11) end,
                      set=function(v) SSet("btbCenterSize", v); UpdatePreview() end },
                    { type="slider", label="X", min=-50, max=50, step=1,
                      get=function() return SVal("btbCenterX", 0) end,
                      set=function(v) SSet("btbCenterX", v); UpdatePreview() end },
                    { type="slider", label="Y", min=-30, max=30, step=1,
                      get=function() return SVal("btbCenterY", 0) end,
                      set=function(v) SSet("btbCenterY", v); UpdatePreview() end },
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
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Enable Text Bar is off"))
                elseif isNone then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Center Text is set to None"))
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
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Enable Text Bar is off"))
                elseif isNone then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Class Icon is set to None"))
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
              setValue=function(v)
                  SSetSupported("classPowerStyle", v)
                  SSetSupported("showClassPowerBar", v ~= "none")
                  if ns.frames and ns.frames._toggleClassPower then
                      ns.frames._toggleClassPower(v)
                  end
                  UpdatePreview()
                  C_Timer.After(0, function() local rl = EllesmereUI._widgetRefreshList; if rl then for i = 1, #rl do rl[i]() end end end)
              end },
            { type="toggle", text="Class Colors",
              disabled=function() return SValSupported("classPowerStyle", "none") == "none" end,
              disabledTooltip="Enable Class Resource is set to None",
              getValue=function()
                  return SGetSupported("classPowerClassColor")
              end,
              setValue=function(v)
                  SSetSupported("classPowerClassColor", v)
                  ReloadAndUpdate(); UpdatePreview()
                  C_Timer.After(0, function() local rl = EllesmereUI._widgetRefreshList; if rl then for i = 1, #rl do rl[i]() end end end)
              end });  y = y - h
        SApplySupport(sharedClassResRow._leftRegion, "classPowerStyle")
        SApplySupport(sharedClassResRow._rightRegion, "classPowerClassColor")
        -- Inline color swatch on Class Colors (disabled when class colors toggle is active)
        do
            local ccRgn = sharedClassResRow._rightRegion
            local ccSwatch = EllesmereUI.BuildColorSwatch(ccRgn, ccRgn:GetFrameLevel() + 5,
                function()
                    local c = SGetSupported("classPowerCustomColor")
                    c = c or { r=1, g=0.82, b=0 }
                    return c.r, c.g, c.b, 1
                end,
                function(r, g, b)
                    UNIT_DB_MAP[selectedUnit]().classPowerCustomColor = { r=r, g=g, b=b }
                    if ns.frames and ns.frames._toggleClassPower then
                        ns.frames._toggleClassPower()
                    end
                    ReloadAndUpdate(); UpdatePreview()
                end, false, 20)
            ccSwatch:SetPoint("RIGHT", ccRgn._lastInline or ccRgn._control, "LEFT", -12, 0)
            ccRgn._lastInline = ccSwatch
            ccRgn._classPowerSwatch = ccSwatch
            local function UpdateCCSwatch()
                local crOff = SValSupported("classPowerStyle", "none") == "none"
                local useCC = SValSupported("classPowerClassColor", true)
                if crOff then
                    ccSwatch:SetAlpha(0.15); ccSwatch:Disable()
                    ccSwatch._disabledTooltip = "Enable Class Resource is set to None"
                elseif useCC then
                    ccSwatch:SetAlpha(0.25); ccSwatch:Disable()
                    ccSwatch._disabledTooltip = "Disabled while Class Colors is enabled"
                else
                    ccSwatch:SetAlpha(1); ccSwatch:Enable()
                    ccSwatch._disabledTooltip = nil
                end
            end
            UpdateCCSwatch()
            RegisterWidgetRefresh(UpdateCCSwatch)
            ccSwatch:HookScript("OnEnter", function(self)
                if self._disabledTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip(self._disabledTooltip))
                end
            end)
            ccSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        end

        -- Inline "Empty Bar Color" swatch on Class Colors row (next to custom color swatch)
        do
            local ccRgn = sharedClassResRow._rightRegion
            local emptySwatch = EllesmereUI.BuildColorSwatch(ccRgn, ccRgn:GetFrameLevel() + 5,
                function()
                    local c = SGetSupported("classPowerEmptyColor")
                    ReloadAndUpdate(); UpdatePreview()
                end, true, 20)
            emptySwatch:SetPoint("RIGHT", ccRgn._lastInline or ccRgn._control, "LEFT", -6, 0)
            ccRgn._lastInline = emptySwatch
            local function UpdateEmptySwatch()
                local crOff = SValSupported("classPowerStyle", "none") == "none"
                if crOff then
                    emptySwatch:SetAlpha(0.15); emptySwatch:Disable()
                else
                    emptySwatch:SetAlpha(1); emptySwatch:Enable()
                end
            end
            UpdateEmptySwatch()
            RegisterWidgetRefresh(UpdateEmptySwatch)
            emptySwatch:HookScript("OnEnter", function(self)
                if SValSupported("classPowerStyle", "none") == "none" then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Enable Class Resource is set to None"))
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

        -- Row 2: Position (with cog for x/y) + Size
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Position", values=classPowerPosValues, order=classPowerPosOrder,
              disabled=function() return SValSupported("classPowerStyle", "none") == "none" end,
              disabledTooltip="Enable Class Resource is set to None",
              getValue=function() return SValSupported("classPowerPosition", "top") end,
              setValue=function(v)
                  SSetSupported("classPowerPosition", v)
                  if ns.frames and ns.frames._toggleClassPower then
                      ns.frames._toggleClassPower()
                  end
                  UpdatePreview(); UpdatePreview()
              end },
            { type="slider", text="Size", min=4, max=30, step=1,
              disabled=function() return SValSupported("classPowerStyle", "none") == "none" end,
              disabledTooltip="Enable Class Resource is set to None",
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
                local crOff = SValSupported("classPowerStyle", "none") == "none"
                local isAbove = SValSupported("classPowerPosition", "top") == "above"
                local disabled = crOff or isAbove
                cpPosCogBtn:SetAlpha(disabled and 0.15 or 0.4)
                cpPosCogBtn:SetEnabled(not disabled)
            end
            cpPosCogBtn:SetScript("OnEnter", function(self)
                if SValSupported("classPowerStyle", "none") == "none" then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Enable Class Resource is set to None"))
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
            { type="slider", text="Bar Spacing", min=0, max=10, step=1,
              disabled=function() return SValSupported("classPowerStyle", "none") == "none" end,
              disabledTooltip="Enable Class Resource is set to None",
              getValue=function() return SValSupported("classPowerSpacing", 2) end,
              setValue=function(v)
                  SSetSupported("classPowerSpacing", v)
                  if ns.frames and ns.frames._toggleClassPower then ns.frames._toggleClassPower() end
                  UpdatePreview(); UpdatePreview()
              end },
            { type="colorpicker", text="Background Color", hasAlpha=true,
              disabled=function() return SValSupported("classPowerStyle", "none") == "none" end,
              disabledTooltip="Enable Class Resource is set to None",
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

        end -- _showClassRes

        _, h = W:Spacer(parent, y, 20); y = y - h

        local sharedAddHeader
        -------------------------------------------------------------------
        --  ADDITIONAL SETTINGS
        -------------------------------------------------------------------
        sharedAddHeader, h = W:SectionHeader(parent, "ADDITIONAL SETTINGS", y); y = y - h

        -- Row 1: Show Absorbs on Frame + Combat Indicator (player-only in single edit)
        local _showAbsorbsCombat = selectedUnit == "player"
        if _showAbsorbsCombat then
        local COMBAT_MEDIA_P = "Interface\\AddOns\\EllesmereUI\\media\\combat\\"
        local combatIndValues = {
            ["none"]="None", ["standard"]="Standard", ["class"]="Class Theme",
            _menuOpts = { itemHeight = 32, icon = function(key)
                if key == "none" then return nil end
                local _, ct = UnitClass("player")
                if not ct then return nil end
                if key == "class" then
                    local coords = CLASS_FULL_COORDS[ct]
                    if not coords then return nil end
                    return COMBAT_MEDIA_P .. "combat-indicator-class-custom.png", coords[1], coords[2], coords[3], coords[4]
                else
                    return COMBAT_MEDIA_P .. "combat-indicator-custom.png", 0, 1, 0, 1
                end
            end },
        }
        local combatIndOrder = { "none", "standard", "class" }
        local sharedAddRow1
        sharedAddRow1, h = W:DualRow(parent, y,
            { type="toggle", text="Show Absorbs on Frame",
              getValue=function() return SValSupported("showPlayerAbsorb", false) end,
              setValue=function(v) SSetSupported("showPlayerAbsorb", v) end },
            { type="dropdown", text="Combat Indicator", values=combatIndValues, order=combatIndOrder,
              getValue=function() return SValSupported("combatIndicatorStyle", "class") end,
              setValue=function(v) SSetSupported("combatIndicatorStyle", v); ReloadAndUpdate(); UpdatePreview() end });  y = y - h
        SApplySupport(sharedAddRow1._leftRegion, "showPlayerAbsorb")
        SApplySupport(sharedAddRow1._rightRegion, "combatIndicatorStyle")
        -- Sync icons: Show Absorbs (left) and Combat Indicator (right)
        do
            local rgn = sharedAddRow1._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Show Absorbs to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().showPlayerAbsorb or false
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().showPlayerAbsorb = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().showPlayerAbsorb or false
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().showPlayerAbsorb or false) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().showPlayerAbsorb or false
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().showPlayerAbsorb = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = sharedAddRow1._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Combat Indicator Style to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().combatIndicatorStyle or "class"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().combatIndicatorStyle = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().combatIndicatorStyle or "class"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().combatIndicatorStyle or "class") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
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
        do
            local ciRgn = sharedAddRow1._rightRegion
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
            local combatPosValues = { ["portrait"]="Portrait", ["healthbar"]="Health Bar", ["textbar"]="Text Bar" }
            local combatPosOrder = { "portrait", "healthbar", "textbar" }

            local _, combatCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Combat Indicator Settings",
                rows = {
                    { type="toggle", label="Class Colored",
                      get=function() return SValSupported("combatIndicatorColor", "custom") == "classcolor" end,
                      set=function(v) SSetSupported("combatIndicatorColor", v and "classcolor" or "custom"); ReloadAndUpdate(); UpdatePreview() end },
                    { type="dropdown", label="Position", values=combatPosValues, order=combatPosOrder,
                      get=function() return SValSupported("combatIndicatorPosition", "healthbar") end,
                      set=function(v) SSetSupported("combatIndicatorPosition", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="slider", label="Size", min=8, max=64, step=1,
                      get=function() return SValSupported("combatIndicatorSize", 22) end,
                      set=function(v) SSetSupported("combatIndicatorSize", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="slider", label="X", min=-100, max=100, step=1,
                      get=function() return SValSupported("combatIndicatorX", 0) end,
                      set=function(v) SSetSupported("combatIndicatorX", v); ReloadAndUpdate(); UpdatePreview() end },
                    { type="slider", label="Y", min=-100, max=100, step=1,
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
                if colorMode == "custom" and style ~= "none" then
                    combatSwatch:Show()
                else
                    combatSwatch:Hide()
                end
            end
            UpdateSwatchVisibility()
            RegisterWidgetRefresh(UpdateSwatchVisibility)
        end
        end -- _showAbsorbsCombat

        -- Row 2: Show Buffs on Frame + Target Debuffs Location
        local sharedAddRow2
        sharedAddRow2, h = W:DualRow(parent, y,
            { type="toggle", text="Show Buffs on Frame",
              getValue=function()
                  local v = SGetSupported("showBuffs")
                  return v ~= false
              end,
              setValue=function(v) SSetSupported("showBuffs", v) end },
            { type="dropdown", text="Target Debuffs Location", values=buffAnchorValues, order=buffAnchorOrder,
              getValue=function() return SValSupported("debuffAnchor", "bottomleft") end,
              setValue=function(v)
                  SwapAuraSlot(UNIT_DB_MAP[selectedUnit](), "debuffAnchor", v)
                  ReloadAndUpdate(); UpdatePreview()
              end });  y = y - h
        SApplySupport(sharedAddRow2._leftRegion, "showBuffs")
        SApplySupport(sharedAddRow2._rightRegion, "debuffAnchor")
        -- Sync icons: Show Buffs (left) and Target Debuffs Location (right)
        do
            local rgn = sharedAddRow2._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Show Buffs to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().showBuffs
                    if v == nil then v = true end
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().showBuffs = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().showBuffs
                    if v == nil then v = true end
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local ov = UNIT_DB_MAP[key]().showBuffs
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
                        local v = UNIT_DB_MAP[selectedUnit]().showBuffs
                        if v == nil then v = true end
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().showBuffs = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = sharedAddRow2._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Target Debuffs Location to all Frames",
                onClick = function()
                    local v = UNIT_DB_MAP[selectedUnit]().debuffAnchor or "bottomleft"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().debuffAnchor = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = UNIT_DB_MAP[selectedUnit]().debuffAnchor or "bottomleft"
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        if (UNIT_DB_MAP[key]().debuffAnchor or "bottomleft") ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_UNIT_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return selectedUnit end,
                    onApply       = function(checkedKeys)
                        local v = UNIT_DB_MAP[selectedUnit]().debuffAnchor or "bottomleft"
                        for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().debuffAnchor = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Cogwheel on Show Buffs for Position, Growth Direction, Max Count
        do
            local leftRgn = sharedAddRow2._leftRegion
            local _, buffCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Buff Settings",
                rows = {
                    { type="dropdown", label="Position", values=buffAnchorValues, order=buffAnchorOrder,
                      get=function() return SValSupported("buffAnchor", "topleft") end,
                      set=function(v)
                          SwapAuraSlot(UNIT_DB_MAP[selectedUnit](), "buffAnchor", v)
                          ReloadAndUpdate(); UpdatePreview()
                      end },
                    { type="dropdown", label="Growth Direction", values=buffGrowthValues, order=buffGrowthOrder,
                      get=function() return SValSupported("buffGrowth", "auto") end,
                      set=function(v) SSetSupported("buffGrowth", v) end },
                    { type="slider", label="Max Count", min=1, max=20, step=1,
                      get=function() return SValSupported("maxBuffs", 4) end,
                      set=function(v) SSetSupported("maxBuffs", v) end },
                },
            })
            local buffCogShow = buffCogShowRaw
            MakeCogBtn(leftRgn, buffCogShow)
        end

        -- Cogwheel on Target Debuffs Location
        do
            local rightRgn = sharedAddRow2._rightRegion
            local _, debuffCogShowRaw = EllesmereUI.BuildCogPopup({
                title = "Debuff Settings",
                rows = {
                    { type="dropdown", label="Growth Direction", values=buffGrowthValues, order=buffGrowthOrder,
                      get=function() return SValSupported("debuffGrowth", "auto") end,
                      set=function(v) SSetSupported("debuffGrowth", v) end },
                    { type="slider", label="Max Count", min=1, max=20, step=1,
                      get=function() return SValSupported("maxDebuffs", 20) end,
                      set=function(v) SSetSupported("maxDebuffs", v) end },
                    { type="toggle", label="Show Own Only",
                      get=function() return SValSupported("onlyPlayerDebuffs", false) end,
                      set=function(v) SSetSupported("onlyPlayerDebuffs", v) end },
                    { type="toggle", label="Use Aura Spell ID Filter",
                      get=function() return SValSupported("useAuraFilter", false) end,
                      set=function(v) SSetSupported("useAuraFilter", v) end },
                },
            })
            local debuffCogShow = debuffCogShowRaw
            MakeCogBtn(rightRgn, debuffCogShow)
        end

        _, h = W:Spacer(parent, y, 20); y = y - h

        -------------------------------------------------------------------
        --  Return click mapping targets + total height
        -------------------------------------------------------------------
        parent._sharedClickTargets = {
            healthBar    = { section = sharedBarsHeader,     target = sharedSizeRow },
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
            combatIndicator = { section = sharedAddHeader, target = sharedAddRow1, slotSide = "right" },
        }

        return y
    end  -- BuildSharedSettings

    ---------------------------------------------------------------------------
    --  Frame Display page  (dropdown selector + shared/mini settings)
    ---------------------------------------------------------------------------
    local _displayHeaderBuilder
    local displayHeaderFixedH = 0

    local function BuildFrameDisplayPage(pageName, parent, yOffset)
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
                    selectedUnit = v
                    EllesmereUI:InvalidateContentHeaderCache()
                    EllesmereUI:SetContentHeader(_displayHeaderBuilder)
                    EllesmereUI:RefreshPage(true)
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
                    _ufPreviewHintFS_display:SetText("Click elements to scroll to and highlight their options")
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
            y = -BuildFoTToTOptions(W, parent, y)
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
            if pv._power then CreateHitOverlay(pv._power, "powerBar", false, baseLevel) end
            if pv._portraitFrame and pv._portraitFrame:IsShown() then CreateHitOverlay(pv._portraitFrame, "portrait", false, baseLevel) end
            if pv._castbar then
                local castLevel = pv._castbar:GetFrameLevel() + 20
                CreateHitOverlay(pv._castbar, "castBar", false, castLevel)
                if pv._castIconFrame then CreateHitOverlay(pv._castIconFrame, "castIcon", false, castLevel) end
                if pv._castNameFS then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._castNameFS, "castName", true, castLevel + 5) end
            end
            if pv._nameFS and pv._nameFS:IsShown() then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._nameFS, "nameText", true, textLevel) end
            if pv._hpFS and pv._hpFS:IsShown() then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._hpFS, "healthText", true, textLevel) end
            if pv._centerFS and pv._centerFS:IsShown() then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._centerFS, "centerText", true, textLevel) end
            if pv._buffIcons then
                for i = 1, #pv._buffIcons do
                    if pv._buffIcons[i] and pv._buffIcons[i]:IsShown() then CreateHitOverlay(pv._buffIcons[i], "buffIcon", false, baseLevel) end
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
    local function BuildMiniTextAndSize(W, parent, y, settingsTable, unitKey, enableRow)
        local _, h

        -- DISPLAY
        local displayHeader
        displayHeader, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h

        -- Enable row (passed in from each builder)
        local enableRowFrame
        if enableRow then
            enableRowFrame, h = enableRow(W, parent, y)
            y = y - h
        end

        -- Row: Bar Height + Bar Width
        local sizeRow
        sizeRow, h = W:DualRow(parent, y,
            { type="slider", text="Bar Height", min=10, max=80, step=1,
              getValue=function() return settingsTable.healthHeight end,
              setValue=function(v)
                settingsTable.healthHeight = v
                ReloadAndUpdate()
              end },
            { type="slider", text="Bar Width", min=60, max=300, step=1,
              getValue=function() return settingsTable.frameWidth end,
              setValue=function(v)
                settingsTable.frameWidth = v
                ReloadAndUpdate()
              end });  y = y - h

        -- Row: Frame Scale (solo)
        local scaleRow
        scaleRow, h = W:DualRow(parent, y,
            { type="slider", text="Frame Scale", min=50, max=200, step=1,
              getValue=function() return settingsTable.frameScale or 100 end,
              setValue=function(v)
                settingsTable.frameScale = v
                ReloadAndUpdate()
              end }, { type="label", text="" });  y = y - h

        -- TEXT section
        local textHeader
        textHeader, h = W:SectionHeader(parent, "TEXT", y); y = y - h

        -- Row: Left Text + Right Text
        local textRow
        textRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Left Text", values=healthTextValues, order=healthTextOrder,
              getValue=function() return settingsTable.leftTextContent or "name" end,
              setValue=function(v)
                settingsTable.leftTextContent = v
                if v ~= "none" then
                    if settingsTable.rightTextContent == v then settingsTable.rightTextContent = "none" end
                end
                ReloadAndUpdate()
              end },
            { type="dropdown", text="Right Text", values=healthTextValues, order=healthTextOrder,
              getValue=function() return settingsTable.rightTextContent or "none" end,
              setValue=function(v)
                settingsTable.rightTextContent = v
                if v ~= "none" then
                    if settingsTable.leftTextContent == v then settingsTable.leftTextContent = "none" end
                end
                ReloadAndUpdate()
              end });  y = y - h

        -- Row: Center Text (solo)
        local centerRow
        centerRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Center Text", values=healthTextValues, order=healthTextOrder,
              getValue=function() return settingsTable.centerTextContent or "none" end,
              setValue=function(v)
                settingsTable.centerTextContent = v
                if v ~= "none" then
                    settingsTable.leftTextContent = "none"
                    settingsTable.rightTextContent = "none"
                end
                ReloadAndUpdate()
              end }, { type="label", text="" });  y = y - h

        return y, displayHeader, sizeRow, textHeader, textRow, enableRowFrame
    end

    local function BuildFoTToTOptions(W, parent, y)
        local _, h

        local function enableRow(Ww, pp, yy)
            return Ww:DualRow(pp, yy,
                { type="toggle", text="Enable Target of Target",
                  getValue=function() return db.profile.enabledFrames.targettarget ~= false end,
                  setValue=function(v)
                    db.profile.enabledFrames.targettarget = v
                    ReloadAndUpdate()
                  end },
                { type="toggle", text="Enable Focus Target",
                  getValue=function() return db.profile.enabledFrames.focustarget ~= false end,
                  setValue=function(v)
                    db.profile.enabledFrames.focustarget = v
                    ReloadAndUpdate()
                  end })
        end

        local displayHeader, sizeRow, textHeader, textRow
        y, displayHeader, sizeRow, textHeader, textRow = BuildMiniTextAndSize(W, parent, y, db.profile.totPet, "totPet", enableRow)

        -- Store click targets for hover highlight system
        parent._ufClickTargets = {
            healthBar  = { section = displayHeader,  target = sizeRow },
            nameText   = { section = textHeader or displayHeader,  target = textRow or sizeRow },
            healthText = { section = textHeader or displayHeader,  target = textRow or sizeRow },
        }

        return abs(y)
    end

    local function BuildPetOptions(W, parent, y)
        local _, h

        local portraitRow
        local function enableRow(Ww, pp, yy)
            portraitRow, h = Ww:DualRow(pp, yy,
                { type="toggle", text="Enable Pet Frame",
                  getValue=function() return db.profile.enabledFrames.pet ~= false end,
                  setValue=function(v)
                    db.profile.enabledFrames.pet = v
                    ReloadAndUpdate()
                  end },
                { type="toggle", text="Show Portrait",
                  getValue=function() return db.profile.pet.showPortrait ~= false end,
                  setValue=function(v)
                    db.profile.pet.showPortrait = v
                    ReloadAndUpdate()
                  end })
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

    local function BuildBossOptions(W, parent, y)
        local _, h

        local portraitRow
        local function enableRow(Ww, pp, yy)
            portraitRow, h = Ww:DualRow(pp, yy,
                { type="toggle", text="Enable Boss Frames",
                  getValue=function() return db.profile.enabledFrames.boss ~= false end,
                  setValue=function(v)
                    db.profile.enabledFrames.boss = v
                    ReloadAndUpdate()
                  end },
                { type="toggle", text="Show Portrait",
                  getValue=function() return db.profile.boss.showPortrait ~= false end,
                  setValue=function(v)
                    db.profile.boss.showPortrait = v
                    ReloadAndUpdate()
                  end })
            return portraitRow, h
        end

        local displayHeader, sizeRow, textHeader, textRow
        y, displayHeader, sizeRow, textHeader, textRow = BuildMiniTextAndSize(W, parent, y, db.profile.boss, "boss", enableRow)

        -- Store click targets for hover highlight system
        parent._ufClickTargets = {
            healthBar  = { section = displayHeader,  target = sizeRow },
            portrait   = { section = displayHeader,  target = portraitRow,   slotSide = "right" },
            nameText   = { section = textHeader or displayHeader,  target = textRow or sizeRow },
            healthText = { section = textHeader or displayHeader,  target = textRow or sizeRow },
        }

        return abs(y)
    end

    ---------------------------------------------------------------------------
    --  Mini Frame Edits page  (dropdown selector + mini builders)
    ---------------------------------------------------------------------------
    local selectedMiniUnit = "targettarget"
    local miniUnitLabels = {
        ["targettarget"] = "Focus Target / Target of Target",
        ["pet"]          = "Pet",
        ["boss"]         = "Boss",
    }
    local miniUnitOrder = { "targettarget", "pet", "boss" }

    local _miniHeaderBuilder
    local miniHeaderFixedH = 0

    local function BuildMiniPage(pageName, parent, yOffset)
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
            y = -BuildFoTToTOptions(W, parent, y)
        elseif selectedMiniUnit == "pet" then
            y = -BuildPetOptions(W, parent, y)
        elseif selectedMiniUnit == "boss" then
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
            local targets = parent._ufClickTargets
            if not targets then return end
            local m = targets[key]
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
    EllesmereUI:RegisterModule("EllesmereUIUnitFrames", {
        title       = "Unit Frames",
        description = "Configure unit frame appearance and behavior.",
        pages       = { PAGE_DISPLAY, PAGE_MINI },
        buildPage   = function(pageName, parent, yOffset)
            -- Randomize preview creature IDs on every tab switch
            RandomizePreviewCreatures()
            if pageName == PAGE_DISPLAY then
                return BuildFrameDisplayPage(pageName, parent, yOffset)
            elseif pageName == PAGE_MINI then
                return BuildMiniPage(pageName, parent, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_DISPLAY then
                return _displayHeaderBuilder
            elseif pageName == PAGE_MINI then
                return _miniHeaderBuilder
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
