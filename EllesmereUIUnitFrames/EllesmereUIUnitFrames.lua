local addonName, ns = ...

local oUF = ns.oUF or oUF
local PP = EllesmereUI.PP
if not oUF then
    error("EllesmereUIUnitFrames: oUF library not found! Please install oUF to Libraries\\oUF\\ folder.")
    return
end

local db
local defaults = {
    profile = {
        showPortrait = true,
        castbarOpacity = 1.0,
        castbarColor = { r = 0.114, g = 0.655, b = 0.514 },
        selectedFont = "Expressway",
        use3DPortrait = false,
        portraitMode = "2d",
        portraitStyle = "attached",
        healthBarTexture = "none",
        healthBarOpacity = 0.9,
        powerBarOpacity = 1.0,
        darkTheme = false,
        -- NEW: separate player sub-table (migrated from shared playerTarget)
        player = {
            frameWidth = 181,
            frameScale = 100,
            healthHeight = 46,
            powerHeight = 6,
            powerPosition = "below",
            powerWidth = 0,
            powerX = 0,
            powerY = 0,
            powerPercentText = "none",
            powerPercentSize = 9,
            powerPercentX = 0,
            powerPercentY = 0,
            powerPercentPowerColor = false,
            healthDisplay = "both",
            showBuffs = false,
            maxBuffs = 4,
            buffAnchor = "topleft",
            buffGrowth = "auto",
            debuffAnchor = "bottomleft",
            debuffGrowth = "auto",
            namePosition = "left",
            healthTextPosition = "right",
            leftTextContent = "name",
            rightTextContent = "both",
            leftTextSize = 12,
            leftTextX = 0,
            leftTextY = 0,
            rightTextSize = 12,
            rightTextX = 0,
            rightTextY = 0,
            leftTextClassColor = false,
            rightTextClassColor = false,
            centerTextContent = "none",
            centerTextSize = 12,
            centerTextX = 0,
            centerTextY = 0,
            centerTextClassColor = false,
            bottomTextBar = false,
            bottomTextBarHeight = 16,
            btbPosition = "bottom",
            btbWidth = 0,
            btbX = 0,
            btbY = 0,
            btbBgColor = { r = 0.2, g = 0.2, b = 0.2 },
            btbBgOpacity = 1.0,
            btbLeftContent = "none",
            btbLeftSize = 11,
            btbLeftX = 0,
            btbLeftY = 0,
            btbLeftClassColor = false,
            btbLeftPowerColor = false,
            btbRightContent = "none",
            btbRightSize = 11,
            btbRightX = 0,
            btbRightY = 0,
            btbRightClassColor = false,
            btbRightPowerColor = false,
            btbCenterContent = "none",
            btbCenterSize = 11,
            btbCenterX = 0,
            btbCenterY = 0,
            btbCenterClassColor = false,
            btbCenterPowerColor = false,
            btbClassIcon = "none",
            btbClassIconSize = 14,
            btbClassIconLocation = "left",
            btbClassIconX = 0,
            btbClassIconY = 0,
            showPortrait = true,
            portraitMode = "2d",
            classThemeStyle = "modern",
            portraitSide = "left",
            portraitSize = 0,
            portraitX = 0,
            portraitY = 0,
            detachedPortraitShape = "portrait",
            detachedPortraitBorderColor = { r = 0, g = 0, b = 0 },
            detachedPortraitClassColor = true,
            detachedPortraitBorder = true,
            detachedPortraitBorderOpacity = 100,
            detachedPortraitBorderSize = 7,
            selectedFont = "Expressway",
            healthBarTexture = "none",
            healthBarOpacity = 0.9,
            powerBarOpacity = 1.0,
            showPlayerAbsorb = false,
            showPlayerCastbar = false,
            showPlayerCastIcon = true,
            lockCastbarToFrame = true,
            playerCastbarX = 0,
            playerCastbarY = 0,
            playerCastbarWidth = 0,
            playerCastbarHeight = 0,
            castSpellNameSize = 11,
            castSpellNameColor = { r = 1, g = 1, b = 1 },
            castDurationSize = 11,
            castDurationColor = { r = 1, g = 1, b = 1 },
            castbarFillColor = { r = 0.863, g = 0.820, b = 0.639 },
            castbarClassColored = false,
            showClassPowerBar = false,
            lockClassPowerToFrame = true,
            classPowerStyle = "none",
            classPowerPosition = "top",
            classPowerBarX = 0,
            classPowerBarY = 0,
            classPowerSize = 8,
            classPowerSpacing = 2,
            classPowerClassColor = true,
            classPowerCustomColor = { r = 1, g = 0.82, b = 0 },
            classPowerBgColor = { r = 0.082, g = 0.082, b = 0.082, a = 1.0 },
            classPowerEmptyColor = { r = 0.2, g = 0.2, b = 0.2, a = 1.0 },
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            highlightColor = { r = 1, g = 1, b = 1 },
            textSize = 12,
            combatIndicatorStyle = "class",
            combatIndicatorColor = "custom",
            combatIndicatorCustomColor = { r = 1, g = 1, b = 1 },
            combatIndicatorPosition = "healthbar",
            combatIndicatorSize = 22,
            combatIndicatorX = 0,
            combatIndicatorY = 0,
            showInRaid = true,
            showInParty = true,
            showSolo = true,
        },
        -- NEW: separate target sub-table (migrated from shared playerTarget)
        target = {
            frameWidth = 181,
            frameScale = 100,
            healthHeight = 46,
            powerHeight = 6,
            powerPosition = "below",
            powerWidth = 0,
            powerX = 0,
            powerY = 0,
            powerPercentText = "none",
            powerPercentSize = 9,
            powerPercentX = 0,
            powerPercentY = 0,
            powerPercentPowerColor = false,
            castbarHeight = 14,
            showCastbar = true,
            showCastIcon = true,
            castSpellNameSize = 11,
            castSpellNameColor = { r = 1, g = 1, b = 1 },
            castDurationSize = 11,
            castDurationColor = { r = 1, g = 1, b = 1 },
            castbarFillColor = { r = 0.863, g = 0.820, b = 0.639 },
            castbarClassColored = false,
            healthDisplay = "both",
            showBuffs = true,
            onlyPlayerDebuffs = false,
            buffAnchor = "topleft",
            buffGrowth = "auto",
            debuffAnchor = "bottomleft",
            debuffGrowth = "auto",
            maxBuffs = 20,
            maxDebuffs = 20,
            namePosition = "left",
            healthTextPosition = "right",
            leftTextContent = "name",
            rightTextContent = "both",
            leftTextSize = 12,
            leftTextX = 0,
            leftTextY = 0,
            rightTextSize = 12,
            rightTextX = 0,
            rightTextY = 0,
            leftTextClassColor = false,
            rightTextClassColor = false,
            centerTextContent = "none",
            centerTextSize = 12,
            centerTextX = 0,
            centerTextY = 0,
            centerTextClassColor = false,
            bottomTextBar = false,
            bottomTextBarHeight = 16,
            btbPosition = "bottom",
            btbWidth = 0,
            btbX = 0,
            btbY = 0,
            btbBgColor = { r = 0.2, g = 0.2, b = 0.2 },
            btbBgOpacity = 1.0,
            btbLeftContent = "none",
            btbLeftSize = 11,
            btbLeftX = 0,
            btbLeftY = 0,
            btbLeftClassColor = false,
            btbLeftPowerColor = false,
            btbRightContent = "none",
            btbRightSize = 11,
            btbRightX = 0,
            btbRightY = 0,
            btbRightClassColor = false,
            btbRightPowerColor = false,
            btbCenterContent = "none",
            btbCenterSize = 11,
            btbCenterX = 0,
            btbCenterY = 0,
            btbCenterClassColor = false,
            btbCenterPowerColor = false,
            btbClassIcon = "none",
            btbClassIconSize = 14,
            btbClassIconLocation = "left",
            btbClassIconX = 0,
            btbClassIconY = 0,
            showPortrait = true,
            portraitMode = "2d",
            classThemeStyle = "modern",
            portraitSide = "right",
            portraitSize = 0,
            portraitX = 0,
            portraitY = 0,
            detachedPortraitShape = "portrait",
            detachedPortraitBorderColor = { r = 0, g = 0, b = 0 },
            detachedPortraitClassColor = true,
            detachedPortraitBorder = true,
            detachedPortraitBorderOpacity = 100,
            detachedPortraitBorderSize = 7,
            selectedFont = "Expressway",
            healthBarTexture = "none",
            healthBarOpacity = 0.9,
            powerBarOpacity = 1.0,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            highlightColor = { r = 1, g = 1, b = 1 },
            textSize = 12,
            showInRaid = true,
            showInParty = true,
            showSolo = true,
        },
        playerTarget = {
            frameWidth = 181,
            healthHeight = 46,
            powerHeight = 6,
            powerPercentText = "none",
            powerPercentSize = 9,
            powerPercentX = 0,
            powerPercentY = 0,
            powerPercentPowerColor = false,
            castbarHeight = 14,
            maxBuffs = 20,
            maxDebuffs = 20,
            healthDisplay = "both",
            showBuffs = true,
            onlyPlayerDebuffs = false,
            showPlayerAbsorb = false,
            showPlayerCastbar = false,
            showClassPowerBar = false,
            classPowerBarX = 0,
            classPowerBarY = 0,
            playerCastbarX = 0,
            playerCastbarY = 0,
            playerCastbarWidth = 0,
            playerCastbarHeight = 0,
        },
        totPet = {
            frameWidth = 101,
            healthHeight = 25,
            frameScale = 100,
            showPortrait = false,
            portraitMode = "2d",
            selectedFont = "Expressway",
            healthBarTexture = "none",
            healthBarOpacity = 0.9,
            textSize = 12,
            leftTextContent = "name",
            rightTextContent = "none",
            centerTextContent = "none",
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            highlightColor = { r = 1, g = 1, b = 1 },
            powerPosition = "none",
        },
        pet = {
            frameWidth = 101,
            healthHeight = 25,
            frameScale = 100,
            showPortrait = false,
            portraitMode = "2d",
            selectedFont = "Expressway",
            healthBarTexture = "none",
            healthBarOpacity = 0.9,
            textSize = 12,
            leftTextContent = "name",
            rightTextContent = "none",
            centerTextContent = "none",
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            highlightColor = { r = 1, g = 1, b = 1 },
            powerPosition = "none",
        },
        focus = {
            frameWidth = 160,
            frameScale = 100,
            healthHeight = 34,
            powerHeight = 6,
            powerPosition = "below",
            powerWidth = 0,
            powerX = 0,
            powerY = 0,
            powerPercentText = "none",
            powerPercentSize = 9,
            powerPercentX = 0,
            powerPercentY = 0,
            powerPercentPowerColor = false,
            castbarHeight = 14,
            showCastbar = true,
            showCastIcon = true,
            castSpellNameSize = 11,
            castSpellNameColor = { r = 1, g = 1, b = 1 },
            castDurationSize = 11,
            castDurationColor = { r = 1, g = 1, b = 1 },
            castbarFillColor = { r = 0.863, g = 0.820, b = 0.639 },
            castbarClassColored = false,
            healthDisplay = "perhp",
            leftTextContent = "name",
            rightTextContent = "perhp",
            leftTextSize = 12,
            leftTextX = 0,
            leftTextY = 0,
            rightTextSize = 12,
            rightTextX = 0,
            rightTextY = 0,
            leftTextClassColor = false,
            rightTextClassColor = false,
            centerTextContent = "none",
            centerTextSize = 12,
            centerTextX = 0,
            centerTextY = 0,
            centerTextClassColor = false,
            bottomTextBar = false,
            bottomTextBarHeight = 16,
            btbPosition = "bottom",
            btbWidth = 0,
            btbX = 0,
            btbY = 0,
            btbLeftContent = "none",
            btbLeftSize = 11,
            btbLeftX = 0,
            btbLeftY = 0,
            btbLeftClassColor = false,
            btbLeftPowerColor = false,
            btbRightContent = "none",
            btbRightSize = 11,
            btbRightX = 0,
            btbRightY = 0,
            btbRightClassColor = false,
            btbRightPowerColor = false,
            btbCenterContent = "none",
            btbCenterSize = 11,
            btbCenterX = 0,
            btbCenterY = 0,
            btbCenterClassColor = false,
            btbCenterPowerColor = false,
            btbClassIcon = "none",
            btbClassIconSize = 14,
            btbClassIconLocation = "left",
            btbClassIconX = 0,
            btbClassIconY = 0,
            showPortrait = true,
            portraitMode = "2d",
            classThemeStyle = "modern",
            portraitSide = "right",
            portraitSize = 0,
            portraitX = 0,
            portraitY = 0,
            detachedPortraitShape = "portrait",
            detachedPortraitBorderColor = { r = 0, g = 0, b = 0 },
            detachedPortraitClassColor = true,
            detachedPortraitBorder = true,
            detachedPortraitBorderOpacity = 100,
            detachedPortraitBorderSize = 7,
            btbBgColor = { r = 0.2, g = 0.2, b = 0.2 },
            btbBgOpacity = 1.0,
            selectedFont = "Expressway",
            healthBarTexture = "none",
            healthBarOpacity = 0.9,
            powerBarOpacity = 1.0,
            onlyPlayerDebuffs = true,
            debuffAnchor = "bottomleft",
            debuffGrowth = "auto",
            maxDebuffs = 10,
            textSize = 12,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            highlightColor = { r = 1, g = 1, b = 1 },
            showInRaid = true,
            showInParty = true,
            showSolo = true,
        },
        boss = {
            frameWidth = 160,
            frameScale = 100,
            healthHeight = 34,
            powerHeight = 6,
            powerPosition = "below",
            powerWidth = 0,
            powerX = 0,
            powerY = 0,
            powerPercentText = "none",
            powerPercentSize = 9,
            powerPercentX = 0,
            powerPercentY = 0,
            powerPercentPowerColor = false,
            castbarHeight = 14,
            healthDisplay = "perhp",
            showPortrait = false,
            portraitMode = "2d",
            selectedFont = "Expressway",
            healthBarTexture = "none",
            healthBarOpacity = 0.9,
            powerBarOpacity = 1.0,
            textSize = 12,
            leftTextContent = "name",
            rightTextContent = "perhp",
            centerTextContent = "none",
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            highlightColor = { r = 1, g = 1, b = 1 },
        },
        enabledFrames = {
            player = true,
            target = true,
            focus = true,
            pet = true,
            targettarget = true,
            focustarget = false,
            boss = true,
        },
        positions = {
            player = { point = "CENTER", x = -317, y = -193.5 },
            target = { point = "CENTER", x = 317, y = -201 },
            focus = { point = "CENTER", x = 0, y = -285 },
            pet = { point = "CENTER", x = -300, y = -260 },
            targettarget = { point = "CENTER", x = 383, y = -152.5 },
            focustarget = { point = "CENTER", x = 50, y = -261 },
            boss = { point = "RIGHT", x = -326, y = 251 },
            playerCastbar = { point = "CENTER", x = 0, y = -250 },
            classPower = { point = "CENTER", x = 0, y = -220 },
        },
        bossSpacing = 60,
    }
}
local frames = {}

local CASTBAR_COLOR = { r = 0.114, g = 0.655, b = 0.514 }
local function GetCastbarColor()
    if db and db.profile and db.profile.castbarColor then
        return db.profile.castbarColor
    end
    return CASTBAR_COLOR
end
local MANA_COLOR = { r = 0.204, g = 0.349, b = 0.851 }

local SOLID_BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8" }
local BORDER_BACKDROP = { edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

local UF_FONT_DIR = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\"
local fontPaths = {
    ["Expressway"]          = UF_FONT_DIR .. "Expressway.TTF",
    ["Avant Garde"]         = UF_FONT_DIR .. "Avant Garde.ttf",
    ["Arial Bold"]          = UF_FONT_DIR .. "Arial Bold.TTF",
    ["Poppins"]             = UF_FONT_DIR .. "Poppins.ttf",
    ["Fira Sans Medium"]    = UF_FONT_DIR .. "FiraSans Medium.ttf",
    ["Arial Narrow"]        = UF_FONT_DIR .. "Arial Narrow.ttf",
    ["Changa"]              = UF_FONT_DIR .. "Changa.ttf",
    ["Cinzel Decorative"]   = UF_FONT_DIR .. "Cinzel Decorative.ttf",
    ["Exo"]                 = UF_FONT_DIR .. "Exo.otf",
    ["Fira Sans Bold"]      = UF_FONT_DIR .. "FiraSans Bold.ttf",
    ["Fira Sans Light"]     = UF_FONT_DIR .. "FiraSans Light.ttf",
    ["Future X Black"]      = UF_FONT_DIR .. "Future X Black.otf",
    ["Gotham Narrow Ultra"] = UF_FONT_DIR .. "Gotham Narrow Ultra.otf",
    ["Gotham Narrow"]       = UF_FONT_DIR .. "Gotham Narrow.otf",
    ["Russo One"]           = UF_FONT_DIR .. "Russo One.ttf",
    ["Ubuntu"]              = UF_FONT_DIR .. "Ubuntu.ttf",
    ["Homespun"]            = UF_FONT_DIR .. "Homespun.ttf",
    ["Friz Quadrata"]       = "Fonts\\FRIZQT__.TTF",
    ["Arial"]               = "Fonts\\ARIALN.TTF",
    ["Morpheus"]            = "Fonts\\MORPHEUS.TTF",
    ["Skurri"]              = "Fonts\\skurri.ttf",
}

-- Locale system font override: for CJK/Cyrillic clients, bypass all custom
-- fonts and use the WoW built-in font that supports the locale's glyphs.
local LOCALE_FONT_OVERRIDE = EllesmereUI and EllesmereUI.LOCALE_FONT_FALLBACK

local cachedFontPath = LOCALE_FONT_OVERRIDE or fontPaths["Expressway"]
local cachedFontPaths = {}  -- per-unit font cache
local function ResolveFontPath(unitKey)
    -- Locale override takes absolute priority — no custom font can render CJK/Cyrillic
    if LOCALE_FONT_OVERRIDE then
        cachedFontPath = LOCALE_FONT_OVERRIDE
        for _, uKey in ipairs({"player", "target", "focus", "boss", "pet", "totPet"}) do
            cachedFontPaths[uKey] = LOCALE_FONT_OVERRIDE
        end
        return
    end
    -- Global font system overrides per-unit fonts
    if EllesmereUI and EllesmereUI.GetFontPath then
        local gPath = EllesmereUI.GetFontPath("unitFrames")
        cachedFontPath = gPath
        for _, uKey in ipairs({"player", "target", "focus", "boss", "pet", "totPet"}) do
            cachedFontPaths[uKey] = gPath
        end
        return
    end
    if unitKey then
        local s = db and db.profile and db.profile[unitKey]
        local fontName = s and s.selectedFont or (db and db.profile and db.profile.selectedFont) or "Expressway"
        cachedFontPaths[unitKey] = fontPaths[fontName] or fontPaths["Expressway"]
        return
    end
    -- Resolve all units + global fallback
    if db and db.profile then
        for _, uKey in ipairs({"player", "target", "focus", "boss", "pet", "totPet"}) do
            local s = db.profile[uKey]
            local fontName = s and s.selectedFont or db.profile.selectedFont or "Expressway"
            cachedFontPaths[uKey] = fontPaths[fontName] or fontPaths["Expressway"]
        end
        -- Global fallback (used when unit context is unknown)
        local gFont = db.profile.player and db.profile.player.selectedFont or db.profile.selectedFont or "Expressway"
        cachedFontPath = fontPaths[gFont] or fontPaths["Expressway"]
    else
        cachedFontPath = fontPaths["Expressway"]
    end
end

local function GetSelectedFont(unitKey)
    if unitKey and cachedFontPaths[unitKey] then
        return cachedFontPaths[unitKey]
    end
    return cachedFontPath
end

local function SetFSFont(fs, size, flags)
  if not (fs and fs.SetFont) then return end
  fs:SetFont(GetSelectedFont(), size or 12, flags or "SHADOW")
end

-- Disable WoW's automatic pixel snapping on a texture (prevents sub-pixel jitter)
local function UnsnapTex(tex)
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then PP.DisablePixelSnap(tex)
    elseif tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0) end
end

-- Health bar texture overlay lookup
local TEXTURE_BASE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local healthBarTextures = {
    ["none"]          = nil,
    ["beautiful"]     = TEXTURE_BASE .. "beautiful.tga",
    ["plating"]       = TEXTURE_BASE .. "plating.tga",
    ["atrocity"]      = TEXTURE_BASE .. "atrocity.tga",
    ["divide"]        = TEXTURE_BASE .. "divide.tga",
    ["glass"]         = TEXTURE_BASE .. "glass.tga",
    ["gradient-lr"]   = TEXTURE_BASE .. "gradient-lr.tga",
    ["gradient-rl"]   = TEXTURE_BASE .. "gradient-rl.tga",
    ["gradient-bt"]   = TEXTURE_BASE .. "gradient-bt.tga",
    ["gradient-tb"]   = TEXTURE_BASE .. "gradient-tb.tga",
    ["matte"]         = TEXTURE_BASE .. "matte.tga",
    ["sheer"]         = TEXTURE_BASE .. "sheer.tga",
}
local healthBarTextureOrder = {
    "none", "beautiful", "plating",
    "atrocity", "divide", "glass",
    "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
    "matte", "sheer",
}
local healthBarTextureNames = {
    ["none"]        = "None",
    ["beautiful"]   = "Beautiful",
    ["plating"]     = "Plating",
    ["atrocity"]    = "Atrocity",
    ["divide"]      = "Divide",
    ["glass"]       = "Glass",
    ["gradient-lr"] = "Gradient Right",
    ["gradient-rl"] = "Gradient Left",
    ["gradient-bt"] = "Gradient Up",
    ["gradient-tb"] = "Gradient Down",
    ["matte"]       = "Matte",
    ["sheer"]       = "Sheer",
}
ns.healthBarTextures = healthBarTextures
ns.healthBarTextureOrder = healthBarTextureOrder
ns.healthBarTextureNames = healthBarTextureNames

-- Map a WoW unit ID ("player", "target", "boss1", "targettarget", etc.)
-- to the settings sub-table key in db.profile.
local function UnitToSettingsKey(unit)
    if not unit then return nil end
    if unit:match("^boss%d$") then return "boss" end
    if unit == "targettarget" or unit == "focustarget" then return "totPet" end
    if unit == "pet" then return "pet" end
    if db.profile[unit] then return unit end
    return nil
end

local function ApplyHealthBarTexture(health, unitKey)
    if not health then return end
    local s = unitKey and db.profile[unitKey]
    local texKey = (s and s.healthBarTexture) or db.profile.healthBarTexture or "none"
    local path   = healthBarTextures[texKey]

    -- Apply texture directly to the StatusBar fill
    if path then
        health:SetStatusBarTexture(path)
    else
        health:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    end
    UnsnapTex(health:GetStatusBarTexture())

    -- Power bar: same texture
    local frame = health:GetParent()
    local power = frame and frame.Power
    if power then
        if path then
            power:SetStatusBarTexture(path)
        else
            power:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        end
        UnsnapTex(power:GetStatusBarTexture())
    end
end

-------------------------------------------------------------------------------
--  Health Bar Opacity â€” controls the overall alpha of the health bar fill
-------------------------------------------------------------------------------
local function ApplyHealthBarOpacity(health, unitKey)
    if not health then return end
    local s = unitKey and db.profile[unitKey]
    local alpha = (s and s.healthBarOpacity) or db.profile.healthBarOpacity or 0.9
    -- Apply to the fill texture and background only (not the whole frame, which would affect text)
    local fillTex = health:GetStatusBarTexture()
    if fillTex then fillTex:SetAlpha(alpha) end
    if health.bg then health.bg:SetAlpha(alpha) end
end

-------------------------------------------------------------------------------
--  Power Bar Opacity â€” controls the overall alpha of the power bar
-------------------------------------------------------------------------------
local function ApplyPowerBarOpacity(power, unitKey)
    if not power then return end
    local s = unitKey and db.profile[unitKey]
    local alpha = (s and s.powerBarOpacity) or db.profile.powerBarOpacity or 1.0
    -- Apply to the fill texture and background only (not the whole frame, which would affect text)
    local fillTex = power:GetStatusBarTexture()
    if fillTex then fillTex:SetAlpha(alpha) end
    if power.bg then power.bg:SetAlpha(alpha) end
end

-------------------------------------------------------------------------------
--  Dark Mode â€” flat dark health bar with gray background
-------------------------------------------------------------------------------
local DARK_HEALTH_R, DARK_HEALTH_G, DARK_HEALTH_B = 0x11/255, 0x11/255, 0x11/255  -- #111111
local DARK_HEALTH_A = 1.0
local DARK_BG_R, DARK_BG_G, DARK_BG_B = 0x4f/255, 0x4f/255, 0x4f/255  -- #4f4f4f

local function ApplyDarkTheme(health)
    if not health then return end
    local isDark = db and db.profile and db.profile.darkTheme
    if isDark then
        health.colorClass = false
        health.colorReaction = false
        health.colorTapped = false
        health.colorDisconnected = false
        health:SetStatusBarColor(DARK_HEALTH_R, DARK_HEALTH_G, DARK_HEALTH_B, DARK_HEALTH_A)
        if health.bg then
            -- Anchor bg to only cover the empty (missing-health) portion so the
            -- bar opacity fill shows the world behind it, not the bg color.
            health.bg:ClearAllPoints()
            health.bg:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
            health.bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            health.bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, 1)
        end
        -- PostUpdateColor hook to re-apply after oUF tries to color
        health.PostUpdateColor = function(self)
            self:SetStatusBarColor(DARK_HEALTH_R, DARK_HEALTH_G, DARK_HEALTH_B, DARK_HEALTH_A)
            -- Re-apply bar opacity so it isn't lost when oUF recolors
            local unitKey = self._euiUnitKey
            local s = unitKey and db.profile[unitKey]
            local alpha = (s and s.healthBarOpacity) or db.profile.healthBarOpacity or 0.9
            local ft = self:GetStatusBarTexture()
            if ft then ft:SetAlpha(alpha) end
            if self.bg then
                self.bg:ClearAllPoints()
                self.bg:SetPoint("TOPLEFT", self:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
                self.bg:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
                self.bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, 1)
                self.bg:SetAlpha(alpha)
            end
        end
    else
        health.colorClass = true
        health.colorReaction = true
        health.colorTapped = true
        health.colorDisconnected = true
        -- Re-apply bar opacity after oUF recolors (SetVertexColor resets alpha)
        -- Also tint the bg to 20% class color
        health.PostUpdateColor = function(self, _, color)
            local unitKey = self._euiUnitKey
            local s = unitKey and db.profile[unitKey]
            local alpha = (s and s.healthBarOpacity) or db.profile.healthBarOpacity or 0.9
            local ft = self:GetStatusBarTexture()
            if ft then ft:SetAlpha(alpha) end
            if self.bg then
                if color and color.GetRGB then
                    local r, g, b = color:GetRGB()
                    self.bg:SetColorTexture(r * 0.2, g * 0.2, b * 0.2, 0.75)
                end
                self.bg:SetAlpha(alpha)
            end
        end
        if health.bg then
            -- Restore bg to cover the full bar area
            health.bg:ClearAllPoints()
            PP.Point(health.bg, "TOPLEFT", health, "TOPLEFT", 0, 0)
            PP.Point(health.bg, "BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            health.bg:SetColorTexture(0, 0, 0, 0.75)
        end
    end
end
ns.ApplyDarkTheme = ApplyDarkTheme

do
  local tagName = "curhpshort"
  local function AbbrevHP(unit)
    if not unit or not UnitExists(unit) then
      return ""
    end
    if not UnitIsConnected(unit) then
      return "OFFLINE"
    end
    if UnitIsDeadOrGhost(unit) then
      return "DEAD"
    end

    local hp = UnitHealth(unit) or 0
    return AbbreviateLargeNumbers(hp)
  end

  oUF.Tags.Methods[tagName] = AbbrevHP
  oUF.Tags.Events[tagName] = "UNIT_HEALTH UNIT_MAXHEALTH"
end

local optionsFrame
local optionsCategoryID
_G.EllesmereUF_StylesRegistered = _G.EllesmereUF_StylesRegistered or false

local unitSettingsMap
local function GetSettingsForUnit(unit)
    if not unitSettingsMap then
        unitSettingsMap = {
            player = db.profile.player,
            target = db.profile.target,
            targettarget = db.profile.totPet,
            pet = db.profile.pet,
            focus = db.profile.focus,
            focustarget = db.profile.totPet,
        }
        for i = 1, 5 do
            unitSettingsMap["boss" .. i] = db.profile.boss
        end
    end
    return unitSettingsMap[unit] or db.profile.player
end

-- Returns the donor settings table for mini frames (focus â†’ target â†’ player)
-- Used to inherit border, texture, and font settings
local function GetMiniDonorSettings()
    local ef = db.profile.enabledFrames
    if ef.focus ~= false and db.profile.focus then return db.profile.focus end
    if ef.target ~= false and db.profile.target then return db.profile.target end
    return db.profile.player
end

-- Resolve buff anchor + growth direction into oUF aura properties
-- Returns: anchorPoint (on frame), initialAnchor, growthX, growthY, offsetX, offsetY
-- initialAnchor is ALWAYS derived from the anchor position (first icon pinned to anchor corner).
-- Growth direction only affects where icons 2+ are placed.
local function ResolveBuffLayout(anchor, growth)
    anchor = anchor or "topleft"
    growth = growth or "auto"

    -- initialAnchor: first icon always starts at the anchor corner
    local iaMap = {
        topleft     = "BOTTOMLEFT",
        topright    = "BOTTOMRIGHT",
        bottomleft  = "TOPLEFT",
        bottomright = "TOPRIGHT",
        left        = "BOTTOMRIGHT",
        right       = "BOTTOMLEFT",
    }
    local ia = iaMap[anchor] or "BOTTOMLEFT"

    -- Auto growth rules: determines where icons 2+ go
    local autoMap = {
        topleft     = { gx = "RIGHT", gy = "UP" },
        topright    = { gx = "LEFT",  gy = "UP" },
        bottomleft  = { gx = "RIGHT", gy = "DOWN" },
        bottomright = { gx = "LEFT",  gy = "DOWN" },
        left        = { gx = "LEFT",  gy = "DOWN" },
        right       = { gx = "RIGHT", gy = "DOWN" },
    }

    local gx, gy
    if growth == "auto" then
        local a = autoMap[anchor] or autoMap.topleft
        gx, gy = a.gx, a.gy
    elseif growth == "right" then
        gx, gy = "RIGHT", "UP"
    elseif growth == "left" then
        gx, gy = "LEFT", "UP"
    elseif growth == "up" then
        gx, gy = "RIGHT", "UP"
    elseif growth == "down" then
        gx, gy = "RIGHT", "DOWN"
    else
        gx, gy = "RIGHT", "UP"
    end

    -- Map anchor to frame attachment point and offset direction
    -- fp = point on the PARENT frame where the buffs container attaches
    local fpMap = {
        topleft     = { fp = "TOPLEFT",     ox = 0,  oy = 1 },
        topright    = { fp = "TOPRIGHT",    ox = 0,  oy = 1 },
        bottomleft  = { fp = "BOTTOMLEFT",  ox = 0,  oy = -1 },
        bottomright = { fp = "BOTTOMRIGHT", ox = 0,  oy = -1 },
        left        = { fp = "LEFT",         ox = -1, oy = 0 },
        right       = { fp = "RIGHT",        ox = 1,  oy = 0 },
    }
    local m = fpMap[anchor] or fpMap.topleft
    return m.fp, ia, gx, gy, m.ox, m.oy
end

local function GetPlayerTargetHealthTag(unit)
    local tbl = (unit == "target") and db.profile.target or db.profile.player
    local display = tbl.healthDisplay or "both"
    if display == "curhpshort" then
        return "[curhpshort]"
    elseif display == "perhp" then
        return "[perhp]%"
    else
        return "[curhpshort] | [perhp]%"
    end
end

local function GetFocusHealthTag()
    local display = db.profile.focus.healthDisplay or "perhp"
    if display == "curhpshort" then
        return "[curhpshort]"
    elseif display == "both" then
        return "[curhpshort] | [perhp]%"
    else
        return "[perhp]%"
    end
end

local function GetBossHealthTag()
    local display = db.profile.boss.healthDisplay or "perhp"
    if display == "curhpshort" then
        return "[curhpshort]"
    elseif display == "both" then
        return "[curhpshort] | [perhp]%"
    else
        return "[perhp]%"
    end
end

-- Resolve a leftTextContent / rightTextContent value to an oUF tag string.
-- content: "name", "both", "curhpshort", "perhp", "none"
local function ContentToTag(content)
    if content == "name" then return "[name]"
    elseif content == "both" then return "[curhpshort] | [perhp]%"
    elseif content == "curhpshort" then return "[curhpshort]"
    elseif content == "perhp" then return "[perhp]%"
    elseif content == "perpp" then return "[perpp]%"
    elseif content == "curpp" then return "[curpp]"
    elseif content == "curhp_curpp" then return "[curhpshort] | [curpp]"
    elseif content == "perhp_perpp" then return "[perhp]% | [perpp]%"
    else return nil end
end

-- Estimate pixel width of a text content type for name truncation.
-- Flat pixel assumptions matching the nameplate system.
local UF_TEXT_PADDING = 10
local ufTextWidths = {
    both        = 75,  -- "132 K | 86%"
    curhpshort  = 38,  -- "132 K"
    perhp       = 38,  -- "86%"
    perpp       = 38,  -- "86%"
    curpp       = 38,  -- "132"
    curhp_curpp = 75,  -- "132 K | 132"
    perhp_perpp = 75,  -- "86% | 86%"
}
local function EstimateUFTextWidth(content)
    return (ufTextWidths[content] or 0) + UF_TEXT_PADDING
end

-- Apply class color to a FontString based on the unit
local function ApplyClassColor(fs, unit, useClassColor)
    if not fs then return end
    if useClassColor then
        local _, class = UnitClass(unit)
        if class then
            local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
            if c then fs:SetTextColor(c.r, c.g, c.b); return end
        end
    end
    fs:SetTextColor(1, 1, 1)
end

local UF_ICONS_PATH = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
local CLASS_FULL_SPRITE_BASE = UF_ICONS_PATH .. "class-full\\"
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

-- Helper: apply class icon from sprite sheet
local function ApplyClassIconTexture(tex, classToken, style)
    local coords = CLASS_FULL_COORDS[classToken]
    if not coords then return false end
    tex:SetTexture(CLASS_FULL_SPRITE_BASE .. style .. ".tga")
    tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    return true
end


-- Portrait mask and border paths for detached portrait shapes
local PORTRAIT_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\"
local PORTRAIT_MASKS = {
    portrait = PORTRAIT_MEDIA .. "portrait_mask.tga",
    circle   = PORTRAIT_MEDIA .. "circle_mask.tga",
    square   = PORTRAIT_MEDIA .. "square_mask.tga",
    csquare  = PORTRAIT_MEDIA .. "csquare_mask.tga",
    diamond  = PORTRAIT_MEDIA .. "diamond_mask.tga",
    hexagon  = PORTRAIT_MEDIA .. "hexagon_mask.tga",
    shield   = PORTRAIT_MEDIA .. "shield_mask.tga",
}
local PORTRAIT_BORDERS = {
    portrait = PORTRAIT_MEDIA .. "portrait_border.tga",
    circle   = PORTRAIT_MEDIA .. "circle_border.tga",
    square   = PORTRAIT_MEDIA .. "square_border.tga",
    csquare  = PORTRAIT_MEDIA .. "csquare_border.tga",
    diamond  = PORTRAIT_MEDIA .. "diamond_border.tga",
    hexagon  = PORTRAIT_MEDIA .. "hexagon_border.tga",
    shield   = PORTRAIT_MEDIA .. "shield_border.tga",
}

-- Top pixel inset for each mask shape (px from edge to visible portrait area in 128px mask)
local MASK_INSETS = {
    circle   = 17,
    csquare  = 17,
    diamond  = 14,
    hexagon  = 17,
    portrait = 17,
    shield   = 13,
    square   = 17,
}

-- Apply detached portrait shape (mask + border overlay) to a portrait backdrop.
-- Creates mask/border textures on first call, then updates them.
-- backdrop: the portrait backdrop frame
-- uSettings: per-unit DB table
-- unitToken: the unit this portrait belongs to (e.g. "player", "target")
local function ApplyDetachedPortraitShape(backdrop, uSettings, unitToken)
    local isDetached = (db.profile.portraitStyle or "attached") == "detached"
    local shape = (uSettings and uSettings.detachedPortraitShape) or "portrait"
    local showBorder = true
    local borderOpacity = ((uSettings and uSettings.detachedPortraitBorderOpacity) or 100) / 100
    local borderColor = (uSettings and uSettings.detachedPortraitBorderColor) or { r = 0, g = 0, b = 0 }
    local useClassColor = (uSettings and uSettings.detachedPortraitClassColor) or false
    local rawBorderSize = (uSettings and uSettings.detachedPortraitBorderSize) or 7
    -- Border art is naturally 7px. Scale UP by (7 - rawBorderSize) so the mask
    -- clips the inner portion, leaving rawBorderSize px visible.
    local bExp = 7 - rawBorderSize

    -- Resolve border color (class color overrides manual color)
    local bR, bG, bB = borderColor.r, borderColor.g, borderColor.b
    if useClassColor then
        local isDark = db and db.profile and db.profile.darkTheme
        if isDark then
            -- Dark mode: always use the player's own class color
            local _, classToken = UnitClass("player")
            if classToken then
                local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken]
                if c then bR, bG, bB = c.r, c.g, c.b end
            end
        elseif unitToken and UnitExists(unitToken) then
            -- Non-dark: use the unit's health bar color (class for players,
            -- reaction for NPCs, tapped grey, etc.)
            local _, classToken = UnitClass(unitToken)
            if UnitIsPlayer(unitToken) and classToken then
                local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken]
                if c then bR, bG, bB = c.r, c.g, c.b end
            elseif UnitIsTapDenied and UnitIsTapDenied(unitToken) then
                bR, bG, bB = 0.6, 0.6, 0.6
            else
                local reaction = UnitReaction(unitToken, "player")
                if reaction then
                    local c = FACTION_BAR_COLORS[reaction]
                    if c then bR, bG, bB = c.r, c.g, c.b end
                end
            end
        else
            -- Fallback: player class color
            local _, classToken = UnitClass("player")
            if classToken then
                local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken]
                if c then bR, bG, bB = c.r, c.g, c.b end
            end
        end
    end

    -- Remove mask when not detached
    if not isDetached then
        if backdrop._shapeMask then
            if backdrop._2d then backdrop._2d:RemoveMaskTexture(backdrop._shapeMask) end
            if backdrop._class then backdrop._class:RemoveMaskTexture(backdrop._shapeMask) end
            if backdrop._bg then backdrop._bg:RemoveMaskTexture(backdrop._shapeMask) end
            backdrop._shapeMask:Hide()
        end
        if backdrop._shapeBorderTex then backdrop._shapeBorderTex:Hide() end
        if backdrop._sqBorderTexs then
            for _, t in ipairs(backdrop._sqBorderTexs) do t:Hide() end
        end
        return
    end

    -- === MASK ===
    local maskPath = PORTRAIT_MASKS[shape]
    if maskPath then
        if not backdrop._shapeMask then
            backdrop._shapeMask = backdrop:CreateMaskTexture()
        end
        -- Inset mask by 1px when border is visible so scaling can't make the
        -- mask edge poke out from behind the border art
        backdrop._shapeMask:ClearAllPoints()
        if rawBorderSize >= 1 then
            PP.Point(backdrop._shapeMask, "TOPLEFT", backdrop, "TOPLEFT", 1, -1)
            PP.Point(backdrop._shapeMask, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -1, 1)
        else
            backdrop._shapeMask:SetAllPoints(backdrop)
        end
        backdrop._shapeMask:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        backdrop._shapeMask:Show()
        if backdrop._2d then backdrop._2d:AddMaskTexture(backdrop._shapeMask) end
        if backdrop._class then backdrop._class:AddMaskTexture(backdrop._shapeMask) end
        if backdrop._bg then backdrop._bg:AddMaskTexture(backdrop._shapeMask) end
    end

    -- Hide legacy square border textures if they exist
    if backdrop._sqBorderTexs then
        for _, t in ipairs(backdrop._sqBorderTexs) do t:Hide() end
    end

    -- === TGA BORDER OVERLAY ===
    if not backdrop._shapeBorderTex then
        backdrop._shapeBorderTex = backdrop:CreateTexture(nil, "OVERLAY")
        UnsnapTex(backdrop._shapeBorderTex)
    end
    backdrop._shapeBorderTex:ClearAllPoints()
    PP.Point(backdrop._shapeBorderTex, "TOPLEFT", backdrop, "TOPLEFT", -bExp, bExp)
    PP.Point(backdrop._shapeBorderTex, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", bExp, -bExp)
    -- Add border to mask so the mask clips its inner edge
    if backdrop._shapeMask then
        pcall(backdrop._shapeBorderTex.RemoveMaskTexture, backdrop._shapeBorderTex, backdrop._shapeMask)
        backdrop._shapeBorderTex:AddMaskTexture(backdrop._shapeMask)
    end
    if showBorder then
        local borderPath = PORTRAIT_BORDERS[shape]
        if borderPath then
            backdrop._shapeBorderTex:SetTexture(borderPath)
            backdrop._shapeBorderTex:SetVertexColor(bR, bG, bB, borderOpacity)
            backdrop._shapeBorderTex:Show()
        else
            backdrop._shapeBorderTex:Hide()
        end
    else
        backdrop._shapeBorderTex:Hide()
    end

    -- === Content positioning within mask ===
    -- Scale portrait so its visible area fills the mask opening.
    -- MASK_INSETS[shape] = px from mask edge to visible area (in 128px mask).
    -- Content expands to fill mask; border size no longer affects content.
    local insetPx = MASK_INSETS[shape] or 17
    local bw = backdrop:GetWidth()
    local bh2 = backdrop:GetHeight()
    if bw < 1 then bw = 46 end
    if bh2 < 1 then bh2 = 46 end
    local visRatio = (128 - 2 * insetPx) / 128
    local cScale = 1 / visRatio
    -- Apply user art scale (100 = default, stored as percentage)
    local artScale = ((uSettings and uSettings.portraitArtScale) or 100) / 100
    cScale = cScale * artScale
    local expand = (cScale - 1) * 0.5
    local oL = -(expand * bw)
    local oR =  (expand * bw)
    local oT =  (expand * bh2)
    local oB = -(expand * bh2)
    if backdrop._2d then
        backdrop._2d:ClearAllPoints()
        PP.Point(backdrop._2d, "TOPLEFT", backdrop, "TOPLEFT", oL, oT)
        PP.Point(backdrop._2d, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", oR, oB)
    end
    if backdrop._class then
        backdrop._class:ClearAllPoints()
        local classInset = math.floor(bh2 * 0.08)
        PP.Point(backdrop._class, "TOPLEFT", backdrop, "TOPLEFT", classInset + oL, -classInset + oT)
        PP.Point(backdrop._class, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -classInset + oR, classInset + oB)
    end
    if backdrop._3d then
        backdrop._3d:ClearAllPoints()
        PP.Point(backdrop._3d, "TOPLEFT", backdrop, "TOPLEFT", oL, oT)
        PP.Point(backdrop._3d, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", oR, oB)
    end
end
-- Create the bottom text bar frame below the health+power area, above the castbar
local function CreateBottomTextBar(frame, unit, settings, anchorFrame, xOffset, overrideWidth)
    local btbH = settings.bottomTextBarHeight or 16
    local btbPos = settings.btbPosition or "bottom"
    local isDetached = (btbPos == "detached_top" or btbPos == "detached_bottom")
    local btbW = isDetached and (settings.btbWidth or 0) or 0
    local totalWidth = (btbW > 0 and isDetached) and btbW or (overrideWidth or settings.frameWidth)

    local btb = CreateFrame("Frame", nil, frame)
    PP.Size(btb, totalWidth, btbH)

    if btbPos == "top" then
        PP.Point(btb, "BOTTOMLEFT", frame.Health or anchorFrame, "TOPLEFT", xOffset or 0, 0)
    elseif btbPos == "detached_top" then
        btb:SetPoint("BOTTOM", frame, "TOP", settings.btbX or 0, 15 + (settings.btbY or 0))
    elseif btbPos == "detached_bottom" then
        btb:SetPoint("TOP", frame, "BOTTOM", settings.btbX or 0, -15 + (settings.btbY or 0))
    else -- "bottom"
        PP.Point(btb, "TOPLEFT", anchorFrame, "BOTTOMLEFT", xOffset or 0, 0)
    end

    local bgc = settings.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
    local bga = settings.btbBgOpacity or 1.0
    local bg = btb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
    UnsnapTex(bg)
    btb.bg = bg

    -- Text overlay
    local textOvr = CreateFrame("Frame", nil, btb)
    textOvr:SetAllPoints()
    textOvr:SetFrameLevel(btb:GetFrameLevel() + 2)

    local leftFS = textOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftFS, settings.btbLeftSize or 11)
    leftFS:SetWordWrap(false)
    leftFS:SetTextColor(1, 1, 1)
    leftFS:SetShadowOffset(1, -1)
    btb.LeftText = leftFS

    local rightFS = textOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightFS, settings.btbRightSize or 11)
    rightFS:SetWordWrap(false)
    rightFS:SetTextColor(1, 1, 1)
    rightFS:SetShadowOffset(1, -1)
    btb.RightText = rightFS

    local centerFS = textOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerFS, settings.btbCenterSize or 11)
    centerFS:SetWordWrap(false)
    centerFS:SetTextColor(1, 1, 1)
    centerFS:SetShadowOffset(1, -1)
    btb.CenterText = centerFS

    btb._textOverlay = textOvr

    -- Tag and position the BTB texts
    local function ApplyBTBTextTags(lc, rc, cc)
        local lt = ContentToTag(lc)
        local rt = ContentToTag(rc)
        local ct = ContentToTag(cc)
        if leftFS._curTag then frame:Untag(leftFS); leftFS._curTag = nil end
        if rightFS._curTag then frame:Untag(rightFS); rightFS._curTag = nil end
        if centerFS._curTag then frame:Untag(centerFS); centerFS._curTag = nil end
        if lt then frame:Tag(leftFS, lt); leftFS._curTag = lt end
        if rt then frame:Tag(rightFS, rt); rightFS._curTag = rt end
        if ct then frame:Tag(centerFS, ct); centerFS._curTag = ct end
        if frame.UpdateTags then frame:UpdateTags() end
    end

    local function ApplyBTBTextPositions(s)
        local lc = s.btbLeftContent or "none"
        local rc = s.btbRightContent or "none"
        local cc = s.btbCenterContent or "none"
        local lsz = s.btbLeftSize or 11
        local rsz = s.btbRightSize or 11
        local csz = s.btbCenterSize or 11

        SetFSFont(leftFS, lsz)
        leftFS:ClearAllPoints()
        if lc ~= "none" then
            leftFS:SetJustifyH("LEFT")
            PP.Point(leftFS, "LEFT", textOvr, "LEFT", 5 + (s.btbLeftX or 0), s.btbLeftY or 0)
            leftFS:Show()
        else leftFS:Hide() end

        SetFSFont(rightFS, rsz)
        rightFS:ClearAllPoints()
        if rc ~= "none" then
            rightFS:SetJustifyH("RIGHT")
            PP.Point(rightFS, "RIGHT", textOvr, "RIGHT", -5 + (s.btbRightX or 0), s.btbRightY or 0)
            rightFS:Show()
        else rightFS:Hide() end

        SetFSFont(centerFS, csz)
        centerFS:ClearAllPoints()
        if cc ~= "none" then
            centerFS:SetJustifyH("CENTER")
            PP.Point(centerFS, "CENTER", textOvr, "CENTER", s.btbCenterX or 0, s.btbCenterY or 0)
            centerFS:Show()
        else centerFS:Hide() end

        ApplyClassColor(leftFS, unit, s.btbLeftClassColor)
        ApplyClassColor(rightFS, unit, s.btbRightClassColor)
        ApplyClassColor(centerFS, unit, s.btbCenterClassColor)
        -- Power color overrides (applied after class color, takes priority for power-related text)
        local function ApplyBTBPowerColor(fs, contentKey, usePowerColor)
            if not fs or not usePowerColor then return end
            if contentKey == "perpp" or contentKey == "curpp" or contentKey == "curhp_curpp" or contentKey == "perhp_perpp" then
                local pType = UnitPowerType(unit)
                local info = PowerBarColor[pType]
                if info then
                    fs:SetTextColor(info.r, info.g, info.b)
                end
            end
        end
        ApplyBTBPowerColor(leftFS, lc, s.btbLeftPowerColor)
        ApplyBTBPowerColor(rightFS, rc, s.btbRightPowerColor)
        ApplyBTBPowerColor(centerFS, cc, s.btbCenterPowerColor)
    end

    ApplyBTBTextTags(
        settings.btbLeftContent or "none",
        settings.btbRightContent or "none",
        settings.btbCenterContent or "none"
    )
    ApplyBTBTextPositions(settings)

    btb._applyBTBTextTags = ApplyBTBTextTags
    btb._applyBTBTextPositions = ApplyBTBTextPositions

    -- Class icon overlay â€” on a high-level frame so it renders above the border
    local classIconHolder = CreateFrame("Frame", nil, frame)
    classIconHolder:SetAllPoints(textOvr)
    classIconHolder:SetFrameLevel(frame:GetFrameLevel() + 12)
    local classIconTex = classIconHolder:CreateTexture(nil, "ARTWORK")
    classIconTex:SetTexCoord(0, 1, 0, 1)
    UnsnapTex(classIconTex)
    classIconTex:Hide()
    btb.ClassIcon = classIconTex

    local function ApplyBTBClassIcon(s)
        local style = s.btbClassIcon or "none"
        if style == "none" then classIconTex:Hide(); return end
        local _, classToken = UnitClass(unit)
        if not classToken then classIconTex:Hide(); return end
        if not ApplyClassIconTexture(classIconTex, classToken, style) then classIconTex:Hide(); return end
        UnsnapTex(classIconTex)
        local sz = s.btbClassIconSize or 14
        PP.Size(classIconTex, sz, sz)
        classIconTex:ClearAllPoints()
        local loc = s.btbClassIconLocation or "left"
        local ox = s.btbClassIconX or 0
        local oy = s.btbClassIconY or 0
        if loc == "center" then
            PP.Point(classIconTex, "CENTER", textOvr, "CENTER", ox, oy)
        elseif loc == "right" then
            PP.Point(classIconTex, "RIGHT", textOvr, "RIGHT", -3 + ox, oy)
        else
            PP.Point(classIconTex, "LEFT", textOvr, "LEFT", 3 + ox, oy)
        end
        classIconTex:Show()
    end

    ApplyBTBClassIcon(settings)
    btb._applyBTBClassIcon = ApplyBTBClassIcon

    return btb
end

-- SetFrameMovable removed Ã¢â‚¬â€ positioning is now handled by Unlock Mode

local function ApplyFramePosition(frame, unit)
    if not frame or not db.profile.positions[unit] then return end
    local pos = db.profile.positions[unit]
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
end

-- Recalculate all element sizes after frame scale changes so everything remains
-- pixel-perfect within the border.  PixelUtil rounds each element independently,
-- which can cause their sum to exceed the frame's snapped total by 1px at certain
-- scales.  After re-snapping each element we check for overflow and trim the last
-- element in the stack so everything fits exactly inside the border.
local function UpdateBordersForScale(frame, unit)
    if not frame then return end
    local settings = GetSettingsForUnit(unit)
    if not settings then return end
    local borderSize = settings.borderSize or 1

    -- 1) Main frame border textures
    if frame.unifiedBorder and frame.unifiedBorder._texs then
        local texs = frame.unifiedBorder._texs
        PP.Height(texs[1], borderSize)
        PP.Height(texs[2], borderSize)
        PP.Width(texs[3], borderSize)
        PP.Width(texs[4], borderSize)
    end

    -- 2) Gather layout info
    local ppPos = settings.powerPosition or "below"
    local ppIsAtt = (ppPos == "below" or ppPos == "above")
    local ppIsDet = (ppPos == "detached_top" or ppPos == "detached_bottom")
    local ph = settings.powerHeight or 6
    -- Simple frames (pet/tot/focustarget) have no power bar â€” skip power height
    local isMini = (unit == "pet" or unit == "targettarget" or unit == "focustarget")
    local powerH = (ppIsAtt and not isMini) and ph or 0

    local btbPos = settings.btbPosition or "bottom"
    local btbIsAtt = (btbPos == "top" or btbPos == "bottom")
    local btbH = (settings.bottomTextBar and btbIsAtt) and (settings.bottomTextBarHeight or 16) or 0

    local showPortrait = settings.showPortrait ~= false
    local isAttached = (db.profile.portraitStyle or "attached") == "attached"
    local pSide = settings.portraitSide or "right"
    local effectiveSide = pSide
    if isAttached and pSide == "top" then effectiveSide = "right" end

    -- Class power above adds height (player only)
    local cpAboveH = 0
    if unit == "player" then
        local cpSt = settings.classPowerStyle or "none"
        local cpPo = (cpSt == "modern") and (settings.classPowerPosition or "top") or "none"
        if cpSt == "modern" and cpPo == "above" then
            local cpSizeAdj = settings.classPowerSize or 8
            cpAboveH = math.max(3, math.floor(cpSizeAdj * 0.375))
        end
    end

    local barHeight = settings.healthHeight + powerH + cpAboveH
    local expectedFrameH = barHeight + btbH
    local pSizeAdj = settings.portraitSize or 0
    if not isAttached then pSizeAdj = pSizeAdj + 10 end
    local adjPortraitH = barHeight + pSizeAdj
    if adjPortraitH < 8 then adjPortraitH = 8 end

    local expectedFrameW
    if not showPortrait or not isAttached then
        expectedFrameW = settings.frameWidth
    else
        expectedFrameW = adjPortraitH + settings.frameWidth
    end

    -- 3) Re-snap the frame itself
    PP.Size(frame, expectedFrameW, expectedFrameH)
    local snappedFrameW = frame:GetWidth()
    local snappedFrameH = frame:GetHeight()

    -- 4) Re-snap portrait and health bar (width axis)
    local healthTargetW = settings.frameWidth
    if frame.Portrait and frame.Portrait.backdrop and showPortrait and isAttached then
        PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
        local snappedPortW = frame.Portrait.backdrop:GetWidth()
        local snappedPortH = frame.Portrait.backdrop:GetHeight()
        -- Trim portrait width if it + health would exceed frame
        if snappedPortW + healthTargetW > snappedFrameW + 0.01 then
            frame.Portrait.backdrop:SetWidth(snappedFrameW - healthTargetW)
            snappedPortW = frame.Portrait.backdrop:GetWidth()
        end
        -- Trim portrait height to frame height if it overflows
        if snappedPortH > snappedFrameH + 0.01 then
            frame.Portrait.backdrop:SetHeight(snappedFrameH)
        end
    end

    -- 5) Re-snap health bar height (width is derived from two-point anchoring)
    if frame.Health then
        PP.Height(frame.Health, settings.healthHeight)
    end

    -- 6) Re-snap power bar
    if frame.Power and ppPos ~= "none" then
        local pw = settings.frameWidth
        if ppIsDet and (settings.powerWidth or 0) > 0 then
            pw = settings.powerWidth
        end
        PP.Size(frame.Power, pw, ph)
        if ppIsAtt and frame.Health then
            -- Height: ensure health + power don't exceed the bar area
            local snappedHealthH = frame.Health:GetHeight()
            local snappedPowerH = frame.Power:GetHeight()
            local expectedBarH = settings.healthHeight + ph
            if snappedHealthH + snappedPowerH > expectedBarH + 0.01 then
                frame.Power:SetHeight(snappedPowerH - (snappedHealthH + snappedPowerH - expectedBarH))
            end
            -- Width: match health bar width exactly
            local snappedHealthW = frame.Health:GetWidth()
            local snappedPowerW = frame.Power:GetWidth()
            if math.abs(snappedPowerW - snappedHealthW) > 0.01 then
                frame.Power:SetWidth(snappedHealthW)
            end
        elseif not ppIsDet then
            -- Non-attached non-detached shouldn't happen, but trim width to frame
            local snappedPowerW = frame.Power:GetWidth()
            if snappedPowerW > snappedFrameW + 0.01 then
                frame.Power:SetWidth(snappedFrameW)
            end
        end
    end

    -- 7) Re-snap BTB
    if frame.BottomTextBar and settings.bottomTextBar and btbIsAtt then
        PP.Size(frame.BottomTextBar, expectedFrameW, settings.bottomTextBarHeight or 16)
        local snappedBtbW = frame.BottomTextBar:GetWidth()
        local snappedBtbH = frame.BottomTextBar:GetHeight()
        -- Width: trim to frame width
        if snappedBtbW > snappedFrameW + 0.01 then
            frame.BottomTextBar:SetWidth(snappedFrameW)
        end
        -- Height: ensure full stack fits within frame height
        local usedH = cpAboveH
        if frame.Health then usedH = usedH + frame.Health:GetHeight() end
        if frame.Power and ppIsAtt then usedH = usedH + frame.Power:GetHeight() end
        if usedH + snappedBtbH > snappedFrameH + 0.01 then
            frame.BottomTextBar:SetHeight(snappedBtbH - (usedH + snappedBtbH - snappedFrameH))
        end
    end

    -- 8) Castbar: re-snap background width + border textures
    if frame.Castbar then
        local castbarBg = frame.Castbar:GetParent()
        if castbarBg then
            -- Trim castbar bg width to match frame width
            local cbW = castbarBg:GetWidth()
            if cbW > snappedFrameW + 0.01 then
                castbarBg:SetWidth(snappedFrameW)
            end
            -- Re-snap border textures
            if castbarBg._borderTexs then
                for _, info in ipairs(castbarBg._borderTexs) do
                    if info.edge == "width" then
                        PP.Width(info.tex, 1)
                    else
                        PP.Height(info.tex, 1)
                    end
                end
                frame.Castbar:ClearAllPoints()
                PP.Point(frame.Castbar, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
                PP.Point(frame.Castbar, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)
            end
        end
    end
end

-- Snap a requested frame scale to the nearest pixel-perfect value.
-- 768 / physicalHeight gives the scale where
-- 1 logical pixel = 1 physical pixel.  We snap the frame scale so that the
-- combined effective scale (UIParent ES * frameScale) is a multiple of that
-- base pixel size, ensuring all PixelUtil sizes land on exact physical pixels.
local function SnapScaleToPixel(requestedScale)
    local _, physH = GetPhysicalScreenSize()
    if not physH or physH == 0 then return requestedScale end
    local pixelSize = 768 / physH  -- 1 physical pixel in UI points
    local parentES = UIParent:GetEffectiveScale()
    if parentES == 0 then return requestedScale end
    -- The combined effective scale
    local rawES = parentES * requestedScale
    -- Snap to nearest multiple of pixelSize
    local snapped = math.floor(rawES / pixelSize + 0.5) * pixelSize
    if snapped < pixelSize then snapped = pixelSize end
    return snapped / parentES
end

-- Smoothly animate frame scale from center point.
-- On init, applies instantly. On live changes, lerps over SCALE_ANIM_DURATION.
-- Keeps the visual center fixed by computing the anchor offset delta caused by
-- the scale change (frame dimensions in screen space change, shifting the center
-- away from the anchor point).
local SCALE_ANIM_DURATION = 0.18
local function ApplyFrameScaleCentered(frame, unit, newScale, animate)
    if not frame then return end
    local oldScale = frame._euiCurrentScale or frame:GetScale()

    -- Stop any in-progress scale animation
    if frame._euiScaleOnUpdate then
        frame._euiCurrentScale = frame:GetScale()
        oldScale = frame._euiCurrentScale
        frame:SetScript("OnUpdate", frame._euiPrevOnUpdate)
        frame._euiScaleOnUpdate = nil
        frame._euiPrevOnUpdate = nil
    end

    -- Compute the new anchor offset needed to keep the visual center fixed
    -- when scale changes from s1 to s2.
    -- WoW multiplies SetPoint offsets by the frame's scale to get screen position.
    -- For anchor "TOPLEFT" with offset (ox, oy):
    --   screen_left = ox * scale,  screen_top = oy * scale
    --   screen_center_x = ox * scale + width * scale / 2
    -- To keep center fixed: newOx * s2 + w*s2/2 = ox * s1 + w*s1/2
    --   newOx = ox * s1/s2 + w * (s1 - s2) / (2 * s2)
    local function ComputeNewOffset(frm, s1, s2, unitKey)
        if not db.profile.positions[unitKey] then return nil end
        local pos = db.profile.positions[unitKey]
        local ox, oy = pos.x, pos.y
        local w = frm:GetWidth()
        local h = frm:GetHeight()
        local ratio = s1 / s2
        local pt = pos.point

        local newOx, newOy = ox * ratio, oy * ratio

        -- Horizontal center compensation
        local halfWDelta = w * (s1 - s2) / (2 * s2)
        if pt == "TOPLEFT" or pt == "LEFT" or pt == "BOTTOMLEFT" then
            newOx = newOx + halfWDelta
        elseif pt == "TOPRIGHT" or pt == "RIGHT" or pt == "BOTTOMRIGHT" then
            newOx = newOx - halfWDelta
        end
        -- TOP/BOTTOM/CENTER horizontal anchors are already centered, no x adjustment

        -- Vertical center compensation
        local halfHDelta = h * (s1 - s2) / (2 * s2)
        if pt == "TOPLEFT" or pt == "TOP" or pt == "TOPRIGHT" then
            newOy = newOy - halfHDelta
        elseif pt == "BOTTOMLEFT" or pt == "BOTTOM" or pt == "BOTTOMRIGHT" then
            newOy = newOy + halfHDelta
        end
        -- LEFT/RIGHT/CENTER vertical anchors are already centered, no y adjustment

        return newOx, newOy
    end

    local function ApplyScaleAndReposition(frm, sc, unitKey)
        local prevScale = frm:GetScale()
        if math.abs(sc - prevScale) < 0.0001 then return end
        local newOx, newOy = ComputeNewOffset(frm, prevScale, sc, unitKey)
        frm:SetScale(sc)
        if newOx and db.profile.positions[unitKey] then
            local pos = db.profile.positions[unitKey]
            pos.x = newOx
            pos.y = newOy
            frm:ClearAllPoints()
            frm:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
        end
    end

    if not animate or math.abs(newScale - oldScale) < 0.001 then
        if animate and math.abs(newScale - oldScale) < 0.0001 then
            return
        end
        -- On init (animate=false), just apply scale and re-anchor from saved
        -- position without recomputing offsets. The saved position is already
        -- correct for the saved scale; recomputing would displace the frame.
        if not animate then
            frame:SetScale(newScale)
            ApplyFramePosition(frame, unit)
        else
            ApplyScaleAndReposition(frame, newScale, unit)
        end
        frame._euiCurrentScale = newScale
        UpdateBordersForScale(frame, unit)
        return
    end

    -- Animated scale
    local elapsed = 0
    local startScale = oldScale
    local endScale = newScale
    frame._euiPrevOnUpdate = frame:GetScript("OnUpdate")
    frame._euiScaleOnUpdate = true

    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = elapsed / SCALE_ANIM_DURATION
        if t >= 1 then t = 1 end
        local eased = 1 - (1 - t) * (1 - t)
        local curScale = startScale + (endScale - startScale) * eased
        ApplyScaleAndReposition(self, curScale, unit)

        if t >= 1 then
            self._euiCurrentScale = endScale
            self:SetScript("OnUpdate", self._euiPrevOnUpdate)
            self._euiScaleOnUpdate = nil
            self._euiPrevOnUpdate = nil
            UpdateBordersForScale(self, unit)
        end
    end)
end

-- ToggleLock removed Ã¢â‚¬â€ positioning is now handled by Unlock Mode

-- fakeFrames / CreateFakeFrame / ShowFakeFrames / HideFakeFrames removed
-- Positioning is now handled exclusively by Unlock Mode

local function GetFrameDimensions(unit)
    local settings = GetSettingsForUnit(unit)
    local showPortrait = (db.profile.portraitStyle or "attached") ~= "none" and settings.showPortrait ~= false
    local isAttached = (db.profile.portraitStyle or "attached") == "attached"
    local pSizeAdj = settings.portraitSize or 0
    local btbPos = settings.btbPosition or "bottom"
    local btbIsAtt = (btbPos == "top" or btbPos == "bottom")
    local btbExtra = (settings.bottomTextBar and btbIsAtt) and (settings.bottomTextBarHeight or 16) or 0
    local powerPos = settings.powerPosition or "below"
    local powerIsAtt = (powerPos == "below" or powerPos == "above")
    local powerExtra = powerIsAtt and (settings.powerHeight or 6) or 0

    if not isAttached then pSizeAdj = pSizeAdj + 10 end
    if unit == "player" or unit == "target" then
        local ptH = settings.healthHeight + powerExtra
        local adjPH = ptH + pSizeAdj
        if adjPH < 8 then adjPH = 8 end
        local pSide = settings.portraitSide or (unit == "player" and "left" or "right")
        if isAttached and pSide == "top" then pSide = (unit == "player") and "left" or "right" end
        local w = (showPortrait and isAttached) and (adjPH + settings.frameWidth) or settings.frameWidth
        return w, ptH + btbExtra
    elseif unit == "focus" then
        local pH = powerIsAtt and (settings.powerHeight or 6) or 0
        local barH = settings.healthHeight + pH
        local adjPH = barH + pSizeAdj
        if adjPH < 8 then adjPH = 8 end
        local w = (showPortrait and isAttached) and (adjPH + settings.frameWidth) or settings.frameWidth
        return w, barH + btbExtra
    elseif unit == "pet" or unit == "targettarget" or unit == "focustarget" then
        return settings.frameWidth, settings.healthHeight
    elseif unit:match("^boss") then
        local pH = powerIsAtt and (settings.powerHeight or 6) or 0
        local barH = settings.healthHeight + pH
        local adjPH = barH + pSizeAdj
        if adjPH < 8 then adjPH = 8 end
        local w = (showPortrait and isAttached) and (adjPH + settings.frameWidth) or settings.frameWidth
        return w, barH
    end
    return 150, 30
end

-- ShowFakeFrames / HideFakeFrames removed Ã¢â‚¬â€ Unlock Mode handles all positioning

local function CreateHealthBar(frame, unit, height, xOffset, settings, rightInset)
    height = height or settings.healthHeight
    xOffset = xOffset or 0
    rightInset = rightInset or 0

    local health = CreateFrame("StatusBar", nil, frame)
    -- Two-point horizontal anchoring: width is derived from the frame so it can
    -- never exceed the frame boundary regardless of pixel-snapping rounding.
    PP.Point(health, "TOPLEFT", frame, "TOPLEFT", xOffset, 0)
    PP.Point(health, "RIGHT", frame, "RIGHT", -rightInset, 0)
    PP.Height(health, height)
    health._xOffset = xOffset  -- store for class power repositioning
    health._rightInset = rightInset  -- store for class power repositioning
    health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    health:GetStatusBarTexture():SetHorizTile(false)
    UnsnapTex(health:GetStatusBarTexture())

    local bg = health:CreateTexture(nil, "BACKGROUND")
    PP.Point(bg, "TOPLEFT", health, "TOPLEFT", 0, 0)
    PP.Point(bg, "BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    bg:SetColorTexture(0, 0, 0, 0.5)
    UnsnapTex(bg)
    health.bg = bg

    health.colorClass = true
    health.colorReaction = true
    health.colorTapped = true
    health.colorDisconnected = true
    health._euiUnitKey = UnitToSettingsKey(unit)

    ApplyHealthBarTexture(health, UnitToSettingsKey(unit))
    ApplyHealthBarOpacity(health, UnitToSettingsKey(unit))
    ApplyDarkTheme(health)

    return health
end

local function CreateAbsorbBar(frame, unit, settings)
    if not frame.Health then return end

    local hpBar = frame.Health
    local barWidth = settings.frameWidth
    local barHeight = settings.healthHeight

    hpBar:SetClipsChildren(true)

    local shieldBar = CreateFrame("StatusBar", nil, hpBar)
    shieldBar:SetStatusBarTexture("Interface\\AddOns\\EllesmereUIUnitFrames\\Media\\shield.tga")
    shieldBar:SetStatusBarColor(1, 1, 1, 0.8)
    shieldBar:SetReverseFill(true)
    UnsnapTex(shieldBar:GetStatusBarTexture())
    shieldBar:ClearAllPoints()
    shieldBar:SetPoint("TOPRIGHT", hpBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    shieldBar:SetPoint("BOTTOMRIGHT", hpBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    shieldBar:SetWidth(barWidth)
    shieldBar:SetHeight(barHeight)
    shieldBar:Show()

    frame.HealthPrediction = {
        damageAbsorb = shieldBar,
        damageAbsorbClampMode = 2,
    }

    return shieldBar
end

local function CreatePowerBar(frame, unit, settings)
    local powerPos = settings.powerPosition or "below"

    local power = CreateFrame("StatusBar", nil, frame)
    local pw = settings.frameWidth
    local isDetached = (powerPos == "detached_top" or powerPos == "detached_bottom")
    if isDetached and (settings.powerWidth or 0) > 0 then
        pw = settings.powerWidth
    end
    PP.Size(power, pw, settings.powerHeight)

    if powerPos == "none" then
        power:Hide()
    elseif powerPos == "above" then
        PP.Point(power, "BOTTOM", frame.Health, "TOP", 0, 0)
    elseif powerPos == "detached_top" then
        power:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
    elseif powerPos == "detached_bottom" then
        power:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
    else -- "below" (default)
        PP.Point(power, "TOP", frame.Health, "BOTTOM", 0, 0)
    end

    power:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    power:GetStatusBarTexture():SetHorizTile(false)
    UnsnapTex(power:GetStatusBarTexture())

    local bg = power:CreateTexture(nil, "BACKGROUND")
    PP.Point(bg, "TOPLEFT", power, "TOPLEFT", 0, 0)
    PP.Point(bg, "BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
    bg:SetColorTexture(0, 0, 0, 0.5)
    UnsnapTex(bg)
    power.bg = bg

    power.colorPower = true

    -- Power percent text overlay
    local ppTextOvr = CreateFrame("Frame", nil, power)
    ppTextOvr:SetAllPoints()
    ppTextOvr:SetFrameLevel(power:GetFrameLevel() + 2)
    local ppFS = ppTextOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(ppFS, settings.powerPercentSize or 9)
    ppFS:SetShadowOffset(1, -1)
    ppFS:Hide()
    power._ppFS = ppFS
    power._ppTextOvr = ppTextOvr

    local function ApplyPowerPercentText(s)
        local pos = s.powerPercentText or "none"
        local sz = s.powerPercentSize or 9
        local ox = s.powerPercentX or 0
        local oy = s.powerPercentY or 0
        local usePowerColor = s.powerPercentPowerColor

        SetFSFont(ppFS, sz)
        ppFS:ClearAllPoints()
        if pos == "none" then
            ppFS:Hide()
            if ppFS._curTag then frame:Untag(ppFS); ppFS._curTag = nil end
            return
        end

        if pos == "left" then
            ppFS:SetJustifyH("LEFT")
            PP.Point(ppFS, "LEFT", ppTextOvr, "LEFT", 2 + ox, oy)
        elseif pos == "right" then
            ppFS:SetJustifyH("RIGHT")
            PP.Point(ppFS, "RIGHT", ppTextOvr, "RIGHT", -2 + ox, oy)
        else
            ppFS:SetJustifyH("CENTER")
            PP.Point(ppFS, "CENTER", ppTextOvr, "CENTER", ox, oy)
        end

        if ppFS._curTag then frame:Untag(ppFS); ppFS._curTag = nil end
        local tag = "[perpp]%"
        frame:Tag(ppFS, tag); ppFS._curTag = tag
        if frame.UpdateTags then frame:UpdateTags() end

        if usePowerColor then
            local pType = UnitPowerType(unit)
            local info = PowerBarColor[pType]
            if info then
                ppFS:SetTextColor(info.r, info.g, info.b)
            else
                ppFS:SetTextColor(1, 1, 1)
            end
        else
            ppFS:SetTextColor(1, 1, 1)
        end
        ppFS:Show()
    end

    ApplyPowerPercentText(settings)
    power._applyPowerPercentText = ApplyPowerPercentText

    ApplyPowerBarOpacity(power, UnitToSettingsKey(unit))

    return power
end

local function CreatePortrait(frame, side, frameHeight, unit)
    local portraitHeight = frameHeight or 46
    local isAttached = (db.profile.portraitStyle or "attached") == "attached"

    -- Check if portrait is hidden via portraitStyle == "none"
    if (db.profile.portraitStyle or "attached") == "none" then
        return nil
    end

    -- Per-unit size/offset adjustments
    local uKey = UnitToSettingsKey(unit)
    local uSettings = uKey and db.profile[uKey]
    local pSizeAdj = (uSettings and uSettings.portraitSize) or 0
    local pXOff = (uSettings and uSettings.portraitX) or 0
    local pYOff = (uSettings and uSettings.portraitY) or 0
    local baseHeight = portraitHeight
    if not isAttached then pSizeAdj = pSizeAdj + 10; pYOff = pYOff + 5 end
    local adjustedHeight = baseHeight + pSizeAdj
    if adjustedHeight < 8 then adjustedHeight = 8 end

    -- For attached, "top" falls back to default side
    local effectiveSide = side
    if isAttached and side == "top" then
        effectiveSide = (unit == "player") and "left" or "right"
    end

    local backdrop = CreateFrame("Frame", nil, frame)
    PP.Size(backdrop, adjustedHeight, adjustedHeight)
    backdrop:SetClipsChildren(true)

    local bgTex = backdrop:CreateTexture(nil, "BACKGROUND")
    PP.Point(bgTex, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
    PP.Point(bgTex, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
    bgTex:SetColorTexture(0.1, 0.1, 0.1, 1)
    UnsnapTex(bgTex)
    backdrop._bg = bgTex

    if isAttached then
        if effectiveSide == "left" then
            PP.Point(backdrop, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        else
            PP.Point(backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        end
    else
        -- Detached: float outside the health bar edge
        if effectiveSide == "top" then
            backdrop:SetPoint("BOTTOM", frame.Health or frame, "TOP", pXOff, 15 + pYOff)
        elseif effectiveSide == "left" then
            backdrop:SetPoint("TOPRIGHT", frame.Health or frame, "TOPLEFT", -15 + pXOff, pYOff)
        else
            backdrop:SetPoint("TOPLEFT", frame.Health or frame, "TOPRIGHT", 15 + pXOff, pYOff)
        end
        -- Raise detached portrait above border/text/power so it renders on top
        backdrop:SetFrameLevel(frame:GetFrameLevel() + 15)
    end

    -- Always create 2D, 3D, and class theme textures; only show the active one.
    local model3D = CreateFrame("PlayerModel", nil, backdrop)
    PP.Point(model3D, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
    PP.Point(model3D, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
    model3D:SetCamera(0)
    model3D:Hide()

    local tex2D = backdrop:CreateTexture(nil, "ARTWORK")
    PP.Point(tex2D, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
    PP.Point(tex2D, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
    tex2D:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    UnsnapTex(tex2D)
    tex2D:Hide()

    -- Class theme icon (static texture, no oUF element needed)
    local texClass = backdrop:CreateTexture(nil, "ARTWORK")
    local classInset = math.floor(portraitHeight * 0.08)
    PP.Point(texClass, "TOPLEFT", backdrop, "TOPLEFT", classInset, -classInset)
    PP.Point(texClass, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -classInset, classInset)
    texClass:SetAlpha(0.8)
    local _, classToken = UnitClass("player")
    local classStyle = (uSettings and uSettings.classThemeStyle) or "modern"
    ApplyClassIconTexture(texClass, classToken or "WARRIOR", classStyle)
    UnsnapTex(texClass)
    texClass:Hide()

    backdrop._3d = model3D
    backdrop._2d = tex2D
    backdrop._class = texClass

    local mode
    do
        mode = (uSettings and uSettings.portraitMode) or db.profile.portraitMode or "2d"
        -- Legacy: if portraitMode is still "none" from old DB, hide portrait
        if mode == "none" then
            backdrop:Hide()
            return nil
        end
    end
    -- Class theme only applies to the player frame; others fall back to 2D
    if mode == "class" and unit ~= "player" then
        mode = "2d"
    end
    local active
    if mode == "class" then
        texClass:Show()
        -- Use tex2D as the oUF element (hidden) so oUF doesn't overwrite texClass
        tex2D:Hide()
        active = tex2D
        active.is2D = true
        active.isClass = true
    elseif mode == "2d" then
        tex2D:Show()
        active = tex2D
        active.is2D = true
    else
        model3D:Show()
        active = model3D
        active.is2D = false
    end
    active.backdrop = backdrop

    -- Re-apply pixel snap disable and re-anchor after oUF updates the portrait texture
    -- (SetPortraitTexture can reset snapping properties and anchor points)
    tex2D.PostUpdate = function(self)
        UnsnapTex(self)
        self:ClearAllPoints()
        PP.Point(self, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
        PP.Point(self, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
    end

    -- Apply detached portrait shape (mask + border) on creation
    ApplyDetachedPortraitShape(backdrop, uSettings, unit)

    return active
end

local function CreateCastBar(frame, unit, settings)
    local castbarBg = CreateFrame("Frame", nil, frame)
    local totalWidth = 0
    local settings = GetSettingsForUnit(unit)
    local isAttached = (db.profile.portraitStyle or "attached") == "attached"
    local showPortraitCB = (db.profile.portraitStyle or "attached") ~= "none" and settings.showPortrait ~= false
    local powerHeightTotal = 0
    local ppPos = settings.powerPosition or "below"
    local ppIsAtt = (ppPos == "below" or ppPos == "above")
    if settings.powerHeight and ppIsAtt then
        powerHeightTotal = settings.powerHeight
    end
    local playerTargetHeight = settings.healthHeight + powerHeightTotal
    local pSizeAdj = settings.portraitSize or 0
    local adjPH = playerTargetHeight + pSizeAdj
    if adjPH < 8 then adjPH = 8 end
    local castBarOffset = 0
    if not isAttached then pSizeAdj = pSizeAdj + 10 end
    if not showPortraitCB or not isAttached then
        totalWidth = settings.frameWidth
    else
        local pSide = settings.portraitSide or (unit == "player" and "left" or "right")
        local eSide = pSide
        if pSide == "top" then eSide = (unit == "player") and "left" or "right" end
        totalWidth = adjPH + settings.frameWidth
        if eSide == "left" then
            castBarOffset = -(adjPH / 2)
        else
            castBarOffset = adjPH / 2
        end
    end
    PP.Size(castbarBg, totalWidth, settings.castbarHeight or 14)

    local ppPos2 = settings.powerPosition or "below"
    local anchorFrame = (ppPos2 == "below" and frame.Power) or frame.Health
    local pcbX = 0
    local pcbY = 0
    if unit == "player" then
        local owH = db.profile.player.playerCastbarHeight or 0
        if owH > 0 then
            PP.Size(castbarBg, totalWidth, owH)
        else
            PP.Size(castbarBg, totalWidth, settings.castbarHeight or 14)
        end
        -- Player castbar is always locked to frame â€” anchor from left edge of frame
        local healthOff = (frame.Health and frame.Health._xOffset) or 0
        castbarBg:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", -healthOff, 0)
    else
        local healthOff = (frame.Health and frame.Health._xOffset) or 0
        castbarBg:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", -healthOff + pcbX, pcbY)
    end

    local bgTex = castbarBg:CreateTexture(nil, "BACKGROUND")
    PP.Point(bgTex, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
    PP.Point(bgTex, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)
    bgTex:SetColorTexture(0, 0, 0, 0.5)
    UnsnapTex(bgTex)

    local leftBorder = castbarBg:CreateTexture(nil, "OVERLAY")
    leftBorder:SetColorTexture(0, 0, 0, 1)
    UnsnapTex(leftBorder)
    PP.Width(leftBorder, 1)
    PP.Point(leftBorder, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
    PP.Point(leftBorder, "BOTTOMLEFT", castbarBg, "BOTTOMLEFT", 0, 0)

    local rightBorder = castbarBg:CreateTexture(nil, "OVERLAY")
    rightBorder:SetColorTexture(0, 0, 0, 1)
    UnsnapTex(rightBorder)
    PP.Width(rightBorder, 1)
    PP.Point(rightBorder, "TOPRIGHT", castbarBg, "TOPRIGHT", 0, 0)
    PP.Point(rightBorder, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)

    local bottomBorder = castbarBg:CreateTexture(nil, "OVERLAY")
    bottomBorder:SetColorTexture(0, 0, 0, 1)
    UnsnapTex(bottomBorder)
    PP.Height(bottomBorder, 1)
    PP.Point(bottomBorder, "BOTTOMLEFT", castbarBg, "BOTTOMLEFT", 0, 0)
    PP.Point(bottomBorder, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)

    -- Store castbar border textures so UpdateBordersForScale can adjust them
    castbarBg._borderTexs = {
        { tex = leftBorder,   edge = "width" },
        { tex = rightBorder,  edge = "width" },
        { tex = bottomBorder, edge = "height" },
    }

    local castbar = CreateFrame("StatusBar", nil, castbarBg)
    PP.Point(castbar, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
    PP.Point(castbar, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)
    castbar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    castbar:GetStatusBarTexture():SetHorizTile(false)
    UnsnapTex(castbar:GetStatusBarTexture())


    local text = castbar:CreateFontString(nil, "OVERLAY")
    SetFSFont(text, 11)
    text:SetPoint("LEFT", castbar, "LEFT", 5, 1)
    text:SetJustifyH("LEFT")
    text:SetTextColor(1, 1, 1)
    text:SetShadowOffset(1, -1)
    castbar.Text = text

    local time = castbar:CreateFontString(nil, "OVERLAY")
    SetFSFont(time, 11)
    time:SetPoint("RIGHT", castbar, "RIGHT", -5, 0)
    time:SetJustifyH("RIGHT")
    time:SetTextColor(1, 1, 1)
    time:SetShadowOffset(1, -1)
    castbar.Time = time

    local shield = castbar:CreateTexture(nil, "OVERLAY")
    shield:SetSize(1, 1)
    shield:SetAlpha(0)
    shield:Hide()
    castbar.Shield = shield

    local castTintLayer = castbar:CreateTexture(nil, "ARTWORK", nil, 1)
    castTintLayer:SetPoint("TOPLEFT", castbar:GetStatusBarTexture(), "TOPLEFT")
    castTintLayer:SetPoint("BOTTOMRIGHT", castbar:GetStatusBarTexture(), "BOTTOMRIGHT")
    castTintLayer:SetTexture("Interface\\Buttons\\WHITE8X8")
    local c = GetCastbarColor()
    castTintLayer:SetVertexColor(c.r, c.g, c.b)
    castTintLayer:SetAlpha(0)
    castbar.castTintLayer = castTintLayer

    local shieldedTint = castbar:CreateTexture(nil, "ARTWORK", nil, 2)
    shieldedTint:SetPoint("TOPLEFT", castbar:GetStatusBarTexture(), "TOPLEFT")
    shieldedTint:SetPoint("BOTTOMRIGHT", castbar:GetStatusBarTexture(), "BOTTOMRIGHT")
    shieldedTint:SetTexture("Interface\\Buttons\\WHITE8X8")
    shieldedTint:SetVertexColor(0.5, 0.5, 0.5)
    shieldedTint:SetAlpha(0)
    castbar._shieldedTint = shieldedTint

    castbar.PostCastStart = function(self)
        if self.castTintLayer then
            self.castTintLayer:SetAlpha(1)
            local cc
            local uSettings = self._eufSettings
            if uSettings and uSettings.castbarClassColored then
                local unit = self.__owner and self.__owner.unit
                if unit then
                    local _, classToken = UnitClass(unit)
                    if classToken then
                        cc = RAID_CLASS_COLORS[classToken]
                    end
                end
            end
            if not cc then
                cc = (uSettings and uSettings.castbarFillColor) or GetCastbarColor()
            end
            self.castTintLayer:SetVertexColor(cc.r, cc.g, cc.b)
            if self._shieldedTint then
                self._shieldedTint:SetAlphaFromBoolean(self.notInterruptible, 1, 0)
            end
        end
    end
    castbar.PostChannelStart = castbar.PostCastStart

    castbar.PostCastInterruptible = castbar.PostCastStart

    castbar.CustomTimeText = function(self, durationObject)
        if durationObject then
            local duration = durationObject:GetRemainingDuration()
            if self.delay and self.delay ~= 0 then
                self.Time:SetFormattedText('%.1f|cffff0000%s%.2f|r', duration, self.channeling and '-' or '+', self.delay)
            else
                self.Time:SetFormattedText('%.1f', duration)
            end
        end
    end
    castbar.CustomDelayText = castbar.CustomTimeText

    -- Cast spell icon (oUF sets castbar.Icon texture automatically)
    local cbH = castbarBg:GetHeight()
    local iconSize = cbH + 1
    local iconFrame = CreateFrame("Frame", nil, castbarBg)
    iconFrame:SetSize(iconSize, iconSize)
    PP.Point(iconFrame, "TOPRIGHT", castbarBg, "TOPLEFT", 1, 1)
    local iconBg = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconBg:SetAllPoints()
    iconBg:SetColorTexture(0, 0, 0, 1)
    -- 1px black border
    local function MkCBdr(parent)
        local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(0, 0, 0, 1)
        return t
    end
    local ibT = MkCBdr(iconFrame); ibT:SetHeight(1); ibT:SetPoint("TOPLEFT"); ibT:SetPoint("TOPRIGHT")
    local ibB = MkCBdr(iconFrame); ibB:SetHeight(1); ibB:SetPoint("BOTTOMLEFT"); ibB:SetPoint("BOTTOMRIGHT")
    local ibL = MkCBdr(iconFrame); ibL:SetWidth(1); ibL:SetPoint("TOPLEFT"); ibL:SetPoint("BOTTOMLEFT")
    local ibR = MkCBdr(iconFrame); ibR:SetWidth(1); ibR:SetPoint("TOPRIGHT"); ibR:SetPoint("BOTTOMRIGHT")
    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
    iconTex:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    castbar.Icon = iconTex
    castbar._iconFrame = iconFrame

    return castbar
end

local function SetupShowOnCastBar(frame, unit)
    local castbar = frame.Castbar
    local castbarBg = castbar:GetParent()
    local iconFrame = castbar._iconFrame

    -- For target: keep the castbar background always visible so the
    -- empty bar area is part of the frame layout.  Only the StatusBar fill,
    -- text, and icon hide when nothing is being cast.
    -- For player/focus: hide everything when not casting.
    local alwaysShowBg = (unit == "target")

    castbar:Hide()
    if iconFrame then iconFrame:Hide() end
    if castbarBg then
        if alwaysShowBg then
            castbarBg:Show()
        else
            castbarBg:Hide()
        end
    end

    local savedCastHook = castbar.PostCastStart

    castbar.PostCastStart = function(self, ...)
        local bg = self:GetParent()
        if bg then bg:Show() end
        self:Show()
        if self._iconFrame then
            -- Respect per-unit showCastIcon / showPlayerCastIcon setting
            local s = db and db.profile and GetSettingsForUnit(unit)
            local showIcon
            if unit == "player" then
                showIcon = (s and s.showPlayerCastIcon ~= false)
            else
                showIcon = (not s or s.showCastIcon ~= false)
            end
            if showIcon then
                self._iconFrame:Show()
            else
                self._iconFrame:Hide()
            end
        end
        if savedCastHook then savedCastHook(self, ...) end
    end
    castbar.PostChannelStart = castbar.PostCastStart
    castbar.PostCastInterruptible = savedCastHook

    local function dismissCastBar(self)
        self:Hide()
        if self._iconFrame then self._iconFrame:Hide() end
        if not alwaysShowBg then
            local bg = self:GetParent()
            if bg then bg:Hide() end
        end
    end
    castbar.PostCastStop = dismissCastBar
    castbar.PostChannelStop = dismissCastBar
    castbar.PostCastFail = dismissCastBar
end


local function FrameBorderEnter(self)
    if self.unifiedBorder and self.unifiedBorder._texs then
        local unit = self.unit or "player"
        local isMini = (unit == "pet" or unit == "targettarget" or unit == "focustarget" or (unit and unit:match("^boss%d$")))
        local settings = isMini and GetMiniDonorSettings() or GetSettingsForUnit(unit)
        local hc = settings.highlightColor or { r = 1, g = 1, b = 1 }
        for _, t in ipairs(self.unifiedBorder._texs) do
            t:SetColorTexture(hc.r, hc.g, hc.b, 1)
        end
    end
end
local function FrameBorderLeave(self)
    if self.unifiedBorder and self.unifiedBorder._texs then
        local unit = self.unit or "player"
        local isMini = (unit == "pet" or unit == "targettarget" or unit == "focustarget" or (unit and unit:match("^boss%d$")))
        local settings = isMini and GetMiniDonorSettings() or GetSettingsForUnit(unit)
        local bc = settings.borderColor or { r = 0, g = 0, b = 0 }
        for _, t in ipairs(self.unifiedBorder._texs) do
            t:SetColorTexture(bc.r, bc.g, bc.b, 1)
        end
    end
end

-- Uses individual edge textures instead of BackdropTemplate for pixel-perfect rendering
-- (BackdropTemplate has internal pixel snapping that can't be disabled)
local function CreateUnifiedBorder(frame, unit)
    local settings = GetSettingsForUnit(unit or "player")
    local size = settings.borderSize or 1
    local bc = settings.borderColor or { r = 0, g = 0, b = 0 }

    local border = CreateFrame("Frame", nil, frame)
    PP.Point(border, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    PP.Point(border, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    border:SetFrameLevel(frame:GetFrameLevel() + 10)

    local function MkEdge()
        local t = border:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(bc.r, bc.g, bc.b, 1)
        UnsnapTex(t)
        return t
    end
    local eT = MkEdge(); PP.Height(eT, size); PP.Point(eT, "TOPLEFT", border, "TOPLEFT", 0, 0); PP.Point(eT, "TOPRIGHT", border, "TOPRIGHT", 0, 0)
    local eB = MkEdge(); PP.Height(eB, size); PP.Point(eB, "BOTTOMLEFT", border, "BOTTOMLEFT", 0, 0); PP.Point(eB, "BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, 0)
    local eL = MkEdge(); PP.Width(eL, size); PP.Point(eL, "TOPLEFT", border, "TOPLEFT", 0, 0); PP.Point(eL, "BOTTOMLEFT", border, "BOTTOMLEFT", 0, 0)
    local eR = MkEdge(); PP.Width(eR, size); PP.Point(eR, "TOPRIGHT", border, "TOPRIGHT", 0, 0); PP.Point(eR, "BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, 0)
    border._texs = { eT, eB, eL, eR }

    frame.unifiedBorder = border

    if size == 0 then
        border:Hide()
    end

    frame:HookScript("OnEnter", FrameBorderEnter)
    frame:HookScript("OnLeave", FrameBorderLeave)

    return border
end


local function CreateTargetAuras(frame, unit)
    local function SetupAuraIcon(_, button)
        if not button then return end

        if button.Icon then
            button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end

        if button.Cooldown then
            button.Cooldown:SetDrawEdge(false)
            button.Cooldown:SetReverse(true)
            button.Cooldown:SetHideCountdownNumbers(true)
        end

        if not button.Border then
            button.Border = CreateFrame("Frame", nil, button, "BackdropTemplate")
            button.Border:SetAllPoints()
            button.Border:SetBackdrop(BORDER_BACKDROP)
            button.Border:SetBackdropBorderColor(0, 0, 0, 1)
            button.Border:SetFrameLevel(button:GetFrameLevel() + 1)
        end
    end

    local auraSize = 22
    local gap = 1
    local perRow = 7
    local containerWidth = frame:GetWidth()

    local settings = GetSettingsForUnit(unit or 'target')

    local showBuffs = true
    if settings and settings.showBuffs == false then
        showBuffs = false
    end

    -- Compute castbar offset for bottom-anchored auras so they sit below the cast bar
    local cbOffset = 0
    if settings.showCastbar then
        local cbH = settings.castbarHeight or 14
        if cbH <= 0 then cbH = 14 end
        cbOffset = -cbH
    end

    local buffs = CreateFrame("Frame", nil, frame)
    local bfp, bia, bgx, bgy, box, boy = ResolveBuffLayout(
        settings and settings.buffAnchor,
        settings and settings.buffGrowth
    )
    local buffCbOff = 0
    local bAnc = settings.buffAnchor or "topleft"
    if bAnc == "bottomleft" or bAnc == "bottomright" then
        buffCbOff = cbOffset
    end
    buffs:SetPoint(bia, frame, bfp, box * gap, boy * gap + buffCbOff)
    buffs:SetSize(containerWidth, auraSize)
    buffs.size = auraSize
    buffs.spacing = gap
    buffs.num = 4
    buffs["size-x"] = perRow
    buffs.initialAnchor = bia
    buffs.growthX = bgx
    buffs.growthY = bgy
    buffs.filter = "HELPFUL"
    buffs.PostCreateButton = SetupAuraIcon
    if not showBuffs then
        buffs:Hide()
        buffs.num = 0
    end
    frame.Buffs = buffs

    local maxDebuffs = (settings and settings.maxDebuffs) or 28

    local debuffs = CreateFrame("Frame", nil, frame)
    local dfp, dia, dgx, dgy, dox, doy = ResolveBuffLayout(
        settings and settings.debuffAnchor or "bottomleft",
        settings and settings.debuffGrowth or "auto"
    )
    local debuffCbOff = 0
    local dAnc = settings.debuffAnchor or "bottomleft"
    if dAnc == "bottomleft" or dAnc == "bottomright" then
        debuffCbOff = cbOffset
    end
    debuffs:SetPoint(dia, frame, dfp, dox * gap, doy * gap + debuffCbOff)
    debuffs:SetSize(containerWidth, auraSize)
    debuffs.size = auraSize
    debuffs.spacing = gap
    debuffs.num = maxDebuffs
    debuffs["size-x"] = perRow
    debuffs.initialAnchor = dia
    debuffs.growthX = dgx
    debuffs.growthY = dgy
    debuffs.filter = "HARMFUL"
    debuffs.PostCreateButton = SetupAuraIcon
    if settings and settings.onlyPlayerDebuffs then
        debuffs.onlyShowPlayer = true
    end
    frame.Debuffs = debuffs
end

local function StyleFullFrame(frame, unit)
    local settings = GetSettingsForUnit(unit)
    local powerPos = settings.powerPosition or "below"
    local powerIsAtt = (powerPos == "below" or powerPos == "above")
    local powerExtra = powerIsAtt and settings.powerHeight or 0
    local playerTargetHeight = settings.healthHeight + powerExtra
    local btbPos = settings.btbPosition or "bottom"
    local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
    local btbExtra = (settings.bottomTextBar and btbIsAttached) and (settings.bottomTextBarHeight or 16) or 0
    local targetFrameHeight = playerTargetHeight + btbExtra
    local totalWidth = 0
    local portraitHeight = playerTargetHeight
    local showPortrait = (db.profile.portraitStyle or "attached") ~= "none" and settings.showPortrait ~= false
    local isAttached = (db.profile.portraitStyle or "attached") == "attached"

    if unit == "player" then
        local pSide = settings.portraitSide or "left"
        -- For attached, "top" falls back to default side
        local effectiveSide = pSide
        if isAttached and pSide == "top" then effectiveSide = "left" end
        -- Class power "above" adds height above health bar ("top" floats outside)
        local cpAboveH = 0
        local cpSt = settings.classPowerStyle or "none"
        local cpPo = (cpSt == "modern") and (settings.classPowerPosition or "top") or "none"
        if cpSt == "modern" and cpPo == "above" then
            local cpSizeAdj = settings.classPowerSize or 8
            local cpPipH = math.max(3, math.floor(cpSizeAdj * 0.375))
            cpAboveH = cpPipH
        end
        local playerHeightWithCp = playerTargetHeight + cpAboveH
        -- Apply portrait size adjustment
        local pSizeAdj = settings.portraitSize or 0
        local adjPortraitH = playerHeightWithCp + pSizeAdj
        if adjPortraitH < 8 then adjPortraitH = 8 end
        if not isAttached then pSizeAdj = pSizeAdj + 10 end
        if not showPortrait then
            totalWidth = settings.frameWidth
            portraitHeight = 0
        elseif isAttached then
            totalWidth = adjPortraitH + settings.frameWidth
        else
            -- Detached: portrait doesn't contribute to frame width
            totalWidth = settings.frameWidth
            portraitHeight = 0
        end
        -- Health bar xOffset: only offset when portrait is attached on the left
        local healthXOffset = (showPortrait and isAttached and effectiveSide == "left") and adjPortraitH or 0
        local healthRightInset = (showPortrait and isAttached and effectiveSide == "right") and adjPortraitH or 0
        PP.Size(frame, totalWidth, playerHeightWithCp + btbExtra)
        frame.Health = CreateHealthBar(frame, unit, settings.healthHeight, healthXOffset, settings, healthRightInset)
        frame.Power = CreatePowerBar(frame, unit, settings)
        -- Always create absorb bar; oUF element disabled later if not wanted
        CreateAbsorbBar(frame, unit, settings)
        -- Always create portrait; hide backdrop when disabled
        frame.Portrait = CreatePortrait(frame, pSide, playerHeightWithCp, unit)
        frame._portraitSide = pSide
        if frame.Portrait and not showPortrait then
            frame.Portrait.backdrop:Hide()
        end

        -- Always create castbar; oUF element disabled later if not wanted
        frame.Castbar = CreateCastBar(frame, unit, settings)
        SetupShowOnCastBar(frame, "player")

        -- Always create player buffs; oUF element disabled later if not wanted
        do
            local auraSize = 22
            local gap = 1
            local perRow = 7
            local bfp, bia, bgx, bgy, box, boy = ResolveBuffLayout(
                settings.buffAnchor, settings.buffGrowth
            )
            -- Offset bottom-anchored buffs below castbar when locked to frame
            local buffCbOffset = 0
            if (settings.buffAnchor == "bottomleft" or settings.buffAnchor == "bottomright"
                or settings.buffAnchor == "left" or settings.buffAnchor == "right")
                and settings.showPlayerCastbar then
                local cbH = settings.playerCastbarHeight or 0
                if cbH <= 0 then cbH = 14 end
                buffCbOffset = -cbH
            end
            local buffs = CreateFrame("Frame", nil, frame)
            buffs:SetPoint(bia, frame, bfp, box * gap, boy * gap + buffCbOffset)
            buffs:SetSize(frame:GetWidth(), auraSize)
            buffs.size = auraSize
            buffs.spacing = gap
            buffs.num = settings.maxBuffs or 4
            buffs["size-x"] = perRow
            buffs.initialAnchor = bia
            buffs.growthX = bgx
            buffs.growthY = bgy
            buffs.filter = "HELPFUL"
            buffs.PostCreateButton = function(_, button)
                if not button then return end
                if button.Icon then button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
                if button.Cooldown then
                    button.Cooldown:SetDrawEdge(false)
                    button.Cooldown:SetReverse(true)
                    button.Cooldown:SetHideCountdownNumbers(true)
                end
                if not button.Border then
                    button.Border = CreateFrame("Frame", nil, button, "BackdropTemplate")
                    button.Border:SetAllPoints()
                    button.Border:SetBackdrop(BORDER_BACKDROP)
                    button.Border:SetBackdropBorderColor(0, 0, 0, 1)
                    button.Border:SetFrameLevel(button:GetFrameLevel() + 1)
                end
            end
            frame.Buffs = buffs
        end
    elseif unit == "target" then
        local pSide = settings.portraitSide or "right"
        -- For attached, "top" falls back to default side
        local effectiveSide = pSide
        if isAttached and pSide == "top" then effectiveSide = "right" end
        local pSizeAdj = settings.portraitSize or 0
        local adjPortraitH = playerTargetHeight + pSizeAdj
        if not isAttached then pSizeAdj = pSizeAdj + 10 end
        if adjPortraitH < 8 then adjPortraitH = 8 end
        if not showPortrait then
            totalWidth = settings.frameWidth
        elseif isAttached then
            totalWidth = adjPortraitH + settings.frameWidth
        else
            totalWidth = settings.frameWidth
        end
        local healthXOffset = (showPortrait and isAttached and effectiveSide == "left") and adjPortraitH or 0
        local healthRightInset = (showPortrait and isAttached and effectiveSide == "right") and adjPortraitH or 0
        PP.Size(frame, totalWidth, targetFrameHeight)
        frame.Health = CreateHealthBar(frame, unit, settings.healthHeight, healthXOffset, settings, healthRightInset)
        frame.Power = CreatePowerBar(frame, unit, settings)
        CreateAbsorbBar(frame, unit, settings)
        frame.Castbar = CreateCastBar(frame, unit, settings)
        SetupShowOnCastBar(frame, unit)
        frame.Portrait = CreatePortrait(frame, pSide, playerTargetHeight, unit)
        frame._portraitSide = pSide
        if frame.Portrait and not showPortrait then
            frame.Portrait.backdrop:Hide()
        end

        CreateTargetAuras(frame, unit)
    end

    CreateUnifiedBorder(frame, unit)
    UpdateBordersForScale(frame, unit)

    -- Text overlay frame -- sits above the StatusBar for clean text rendering.
    local textOverlay = CreateFrame("Frame", nil, frame.Health)
    textOverlay:SetAllPoints(frame.Health)
    textOverlay:SetFrameLevel(frame.Health:GetFrameLevel() + 3)
    frame._textOverlay = textOverlay

    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "both"
    local centerContent = settings.centerTextContent or "none"
    local lts = settings.leftTextSize or settings.textSize or 12
    local rts = settings.rightTextSize or settings.textSize or 12
    local cts = settings.centerTextSize or settings.textSize or 12

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, lts)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    leftText:SetShadowOffset(1, -1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, rts)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    rightText:SetShadowOffset(1, -1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, cts)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    centerText:SetShadowOffset(1, -1)
    frame.CenterText = centerText

    -- Backward compat aliases
    frame.NameText = leftText
    frame.HealthValue = rightText

    -- Apply tags based on content
    local function ApplyTextTags(lc, rc, cc)
        local ltag = ContentToTag(lc)
        local rtag = ContentToTag(rc)
        local ctag = ContentToTag(cc)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        if frame.UpdateTags then frame:UpdateTags() end
    end
    ApplyTextTags(leftContent, rightContent, centerContent)
    frame._applyTextTags = ApplyTextTags

    -- Position and show/hide based on content + offsets
    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "both"
        local cc = s.centerTextContent or "none"
        local lsz = s.leftTextSize or s.textSize or 12
        local rsz = s.rightTextSize or s.textSize or 12
        local csz = s.centerTextSize or s.textSize or 12
        local lxo = s.leftTextX or 0
        local lyo = s.leftTextY or 0
        local rxo = s.rightTextX or 0
        local ryo = s.rightTextY or 0
        local cxo = s.centerTextX or 0
        local cyo = s.centerTextY or 0
        local barW = s.frameWidth or 181

        -- Center text: if active, hide left/right
        if cc ~= "none" then
            leftText:Hide()
            rightText:Hide()
            SetFSFont(centerText, csz)
            centerText:ClearAllPoints()
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            centerText:SetWidth(0)
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor)
        else
            centerText:Hide()
            SetFSFont(leftText, lsz)
            leftText:ClearAllPoints()
            if lc ~= "none" then
                leftText:SetJustifyH("LEFT")
                PP.Point(leftText, "LEFT", textOverlay, "LEFT", 5 + lxo, lyo)
                -- Constrain width when opposing right text exists
                if rc ~= "none" then
                    local rightUsed = EstimateUFTextWidth(rc)
                    PP.Width(leftText, math.max(barW - rightUsed - 10, 20))
                else
                    leftText:SetWidth(0)
                end
                leftText:Show()
                ApplyClassColor(leftText, unit, s.leftTextClassColor)
            else leftText:Hide() end

            SetFSFont(rightText, rsz)
            rightText:ClearAllPoints()
            if rc ~= "none" then
                rightText:SetJustifyH("RIGHT")
                PP.Point(rightText, "RIGHT", textOverlay, "RIGHT", -5 + rxo, ryo)
                -- Constrain width when opposing left text exists
                if lc ~= "none" then
                    local leftUsed = EstimateUFTextWidth(lc)
                    PP.Width(rightText, math.max(barW - leftUsed - 10, 20))
                else
                    rightText:SetWidth(0)
                end
                rightText:Show()
                ApplyClassColor(rightText, unit, s.rightTextClassColor)
            else rightText:Hide() end
        end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions

    -- Bottom Text Bar
    if settings.bottomTextBar then
        local anchorFrame = (powerIsAtt and frame.Power) or frame.Health
        local btbPos = settings.btbPosition or "bottom"
        local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
        -- BTB spans full frame width; offset left when portrait is attached on the left
        local btbXOff = 0
        if btbIsAttached and showPortrait and isAttached then
            local pSide = settings.portraitSide or (unit == "player" and "left" or "right")
            local eSide = pSide
            if pSide == "top" then eSide = (unit == "player") and "left" or "right" end
            if eSide == "left" then
                local ppPos2 = settings.powerPosition or "below"
                local ppIsAtt2 = (ppPos2 == "below" or ppPos2 == "above")
                local barH = settings.healthHeight + (ppIsAtt2 and (settings.powerHeight or 6) or 0)
                local adj = barH + (settings.portraitSize or 0)
                if adj < 8 then adj = 8 end
                btbXOff = -adj
            end
        end
        frame.BottomTextBar = CreateBottomTextBar(frame, unit, settings, anchorFrame, btbXOff, totalWidth)
        frame._btb = frame.BottomTextBar
        -- Re-anchor cast bar below BTB only when BTB is attached at bottom
        if btbPos == "bottom" and frame.Castbar then
            local castbarBg = frame.Castbar:GetParent()
            if castbarBg and castbarBg:GetParent() == frame then
                castbarBg:ClearAllPoints()
                castbarBg:SetPoint("TOP", frame.BottomTextBar, "BOTTOM", 0, 0)
            end
        end
    end
end


local function StyleFocusFrame(frame, unit)
    local settings = GetSettingsForUnit(unit)
    local fPpPos = settings.powerPosition or "below"
    local fPpIsAtt = (fPpPos == "below" or fPpPos == "above")
    local powerHeight = fPpIsAtt and (settings.powerHeight or 6) or 0
    local focusBarHeight = settings.healthHeight + powerHeight
    local btbPos = settings.btbPosition or "bottom"
    local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
    local btbExtra = (settings.bottomTextBar and btbIsAttached) and (settings.bottomTextBarHeight or 16) or 0
    local focusFrameHeight = focusBarHeight + btbExtra + (settings.castbarHeight or 14)
    local totalWidth = 0
    local portraitHeight = 0
    local showPortrait = (db.profile.portraitStyle or "attached") ~= "none" and settings.showPortrait ~= false
    local isAttached = (db.profile.portraitStyle or "attached") == "attached"
    local pSide = settings.portraitSide or "right"
    -- For attached, "top" falls back to default side
    local effectiveSide = pSide
    if isAttached and pSide == "top" then effectiveSide = "right" end
    local pSizeAdj = settings.portraitSize or 0
    if not isAttached then pSizeAdj = pSizeAdj + 10 end
    local adjPortraitH = focusBarHeight + pSizeAdj
    if adjPortraitH < 8 then adjPortraitH = 8 end

    if not showPortrait then
        totalWidth = settings.frameWidth
    elseif isAttached then
        totalWidth = adjPortraitH + settings.frameWidth
    else
        totalWidth = settings.frameWidth
    end

    PP.Size(frame, totalWidth, focusFrameHeight)
    local healthXOffset = (showPortrait and isAttached and effectiveSide == "left") and adjPortraitH or 0
    local healthRightInset = (showPortrait and isAttached and effectiveSide == "right") and adjPortraitH or 0
    frame.Health = CreateHealthBar(frame, unit, settings.healthHeight, healthXOffset, settings, healthRightInset)
    frame.Power = CreatePowerBar(frame, unit, settings)
    frame.Castbar = CreateCastBar(frame, unit, settings)
    -- Always create portrait; hide backdrop when disabled
    frame.Portrait = CreatePortrait(frame, pSide, focusBarHeight, unit)
    frame._portraitSide = pSide
    if frame.Portrait and not showPortrait then
        frame.Portrait.backdrop:Hide()
    end

    PP.Size(frame, totalWidth, focusBarHeight)

    SetupShowOnCastBar(frame, "focus")

    CreateUnifiedBorder(frame, unit)
    UpdateBordersForScale(frame, unit)

    -- Text overlay frame -- sits above the StatusBar for clean text rendering.
    local textOverlay = CreateFrame("Frame", nil, frame.Health)
    textOverlay:SetAllPoints(frame.Health)
    textOverlay:SetFrameLevel(frame.Health:GetFrameLevel() + 3)
    frame._textOverlay = textOverlay

    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "perhp"
    local centerContent = settings.centerTextContent or "none"
    local lts = settings.leftTextSize or settings.textSize or 12
    local rts = settings.rightTextSize or settings.textSize or 12
    local cts = settings.centerTextSize or settings.textSize or 12

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, lts)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    leftText:SetShadowOffset(1, -1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, rts)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    rightText:SetShadowOffset(1, -1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, cts)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    centerText:SetShadowOffset(1, -1)
    frame.CenterText = centerText

    -- Backward compat aliases
    frame.NameText = leftText
    frame.HealthValue = rightText

    -- Apply tags based on content
    local function ApplyTextTags(lc, rc, cc)
        local ltag = ContentToTag(lc)
        local rtag = ContentToTag(rc)
        local ctag = ContentToTag(cc)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        if frame.UpdateTags then frame:UpdateTags() end
    end
    ApplyTextTags(leftContent, rightContent, centerContent)
    frame._applyTextTags = ApplyTextTags

    -- Position and show/hide based on content + offsets
    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "perhp"
        local cc = s.centerTextContent or "none"
        local lsz = s.leftTextSize or s.textSize or 12
        local rsz = s.rightTextSize or s.textSize or 12
        local csz = s.centerTextSize or s.textSize or 12
        local lxo = s.leftTextX or 0
        local lyo = s.leftTextY or 0
        local rxo = s.rightTextX or 0
        local ryo = s.rightTextY or 0
        local cxo = s.centerTextX or 0
        local cyo = s.centerTextY or 0
        local barW = s.frameWidth or 181

        -- Center text: if active, hide left/right
        if cc ~= "none" then
            leftText:Hide()
            rightText:Hide()
            SetFSFont(centerText, csz)
            centerText:ClearAllPoints()
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            centerText:SetWidth(0)
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor)
        else
            centerText:Hide()
            SetFSFont(leftText, lsz)
            leftText:ClearAllPoints()
            if lc ~= "none" then
                leftText:SetJustifyH("LEFT")
                PP.Point(leftText, "LEFT", textOverlay, "LEFT", 5 + lxo, lyo)
                if rc ~= "none" then
                    local rightUsed = EstimateUFTextWidth(rc)
                    PP.Width(leftText, math.max(barW - rightUsed - 10, 20))
                else
                    leftText:SetWidth(0)
                end
                leftText:Show()
                ApplyClassColor(leftText, unit, s.leftTextClassColor)
            else leftText:Hide() end

            SetFSFont(rightText, rsz)
            rightText:ClearAllPoints()
            if rc ~= "none" then
                rightText:SetJustifyH("RIGHT")
                PP.Point(rightText, "RIGHT", textOverlay, "RIGHT", -5 + rxo, ryo)
                if lc ~= "none" then
                    local leftUsed = EstimateUFTextWidth(lc)
                    PP.Width(rightText, math.max(barW - leftUsed - 10, 20))
                else
                    rightText:SetWidth(0)
                end
                rightText:Show()
                ApplyClassColor(rightText, unit, s.rightTextClassColor)
            else rightText:Hide() end
        end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions

    -- Bottom Text Bar
    if settings.bottomTextBar then
        local anchorFrame = (fPpIsAtt and frame.Power) or frame.Health
        local btbPos = settings.btbPosition or "bottom"
        local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
        -- BTB spans full frame width; offset left when portrait is attached on the left
        local btbXOff = 0
        if btbIsAttached and showPortrait and isAttached and effectiveSide == "left" then
            btbXOff = -adjPortraitH
        end
        frame.BottomTextBar = CreateBottomTextBar(frame, unit, settings, anchorFrame, btbXOff, totalWidth)
        frame._btb = frame.BottomTextBar
        -- Re-anchor cast bar below BTB only when BTB is attached at bottom
        if btbPos == "bottom" and frame.Castbar then
            local castbarBg = frame.Castbar:GetParent()
            if castbarBg and castbarBg:GetParent() == frame then
                castbarBg:ClearAllPoints()
                castbarBg:SetPoint("TOP", frame.BottomTextBar, "BOTTOM", 0, 0)
            end
        end
    end
end

local function StyleSimpleFrame(frame, unit)
    local settings = GetSettingsForUnit(unit)
    PP.Size(frame, settings.frameWidth, settings.healthHeight)

    local health = CreateFrame("StatusBar", nil, frame)
    PP.Point(health, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    PP.Point(health, "RIGHT", frame, "RIGHT", 0, 0)
    PP.Height(health, settings.healthHeight)
    health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    health:GetStatusBarTexture():SetHorizTile(false)
    UnsnapTex(health:GetStatusBarTexture())

    local bg = health:CreateTexture(nil, "BACKGROUND")
    PP.Point(bg, "TOPLEFT", health, "TOPLEFT", 0, 0)
    PP.Point(bg, "BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    bg:SetColorTexture(0, 0, 0, 0.5)
    UnsnapTex(bg)
    health.bg = bg

    health.colorClass = true
    health.colorReaction = true
    health.colorTapped = true
    health.colorDisconnected = true
    health._euiUnitKey = UnitToSettingsKey(unit)

    ApplyHealthBarTexture(health, UnitToSettingsKey(unit))
    ApplyHealthBarOpacity(health, UnitToSettingsKey(unit))
    ApplyDarkTheme(health)

    frame.Health = health
    CreateUnifiedBorder(frame, unit)
    UpdateBordersForScale(frame, unit)

    -- Text overlay frame
    local textOverlay = CreateFrame("Frame", nil, health)
    textOverlay:SetAllPoints(health)
    textOverlay:SetFrameLevel(health:GetFrameLevel() + 3)
    frame._textOverlay = textOverlay

    local ts = settings.textSize or 12
    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "none"
    local centerContent = settings.centerTextContent or "none"

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, ts)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    leftText:SetShadowOffset(1, -1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, ts)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    rightText:SetShadowOffset(1, -1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, ts)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    centerText:SetShadowOffset(1, -1)
    frame.CenterText = centerText

    -- Backward compat aliases
    frame.NameText = leftText
    frame.HealthValue = rightText

    local function ApplyTextTags(lc, rc, cc)
        local ltag = ContentToTag(lc)
        local rtag = ContentToTag(rc)
        local ctag = ContentToTag(cc)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        if frame.UpdateTags then frame:UpdateTags() end
    end
    ApplyTextTags(leftContent, rightContent, centerContent)
    frame._applyTextTags = ApplyTextTags

    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "none"
        local cc = s.centerTextContent or "none"
        local barW = s.frameWidth or 100
        if cc ~= "none" then
            centerText:ClearAllPoints()
            centerText:SetPoint("CENTER", health, "CENTER", 0, 0)
            centerText:SetWidth(0)
            centerText:Show()
            leftText:Hide(); rightText:Hide()
        else
            centerText:Hide()
            if lc ~= "none" then
                leftText:ClearAllPoints()
                leftText:SetPoint("LEFT", health, "LEFT", 5, 0)
                leftText:SetJustifyH("LEFT")
                if rc ~= "none" then
                    local rightUsed = EstimateUFTextWidth(rc)
                    PP.Width(leftText, math.max(barW - rightUsed - 10, 20))
                else
                    leftText:SetWidth(0)
                end
                leftText:Show()
            else leftText:Hide() end
            if rc ~= "none" then
                rightText:ClearAllPoints()
                rightText:SetPoint("RIGHT", health, "RIGHT", -5, 0)
                rightText:SetJustifyH("RIGHT")
                if lc ~= "none" then
                    local leftUsed = EstimateUFTextWidth(lc)
                    PP.Width(rightText, math.max(barW - leftUsed - 10, 20))
                else
                    rightText:SetWidth(0)
                end
                rightText:Show()
            else rightText:Hide() end
        end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions
end


local function StylePetFrame(frame, unit)
    local settings = GetSettingsForUnit(unit)
    local showPortrait = (db.profile.portraitStyle or "attached") ~= "none" and settings.showPortrait ~= false
    local totalWidth = settings.frameWidth
    local portraitOffset = 0

    if showPortrait then
        totalWidth = settings.healthHeight + settings.frameWidth
        portraitOffset = settings.healthHeight
    end

    PP.Size(frame, totalWidth, settings.healthHeight)

    local health = CreateFrame("StatusBar", nil, frame)
    PP.Point(health, "TOPLEFT", frame, "TOPLEFT", portraitOffset, 0)
    PP.Point(health, "RIGHT", frame, "RIGHT", 0, 0)
    PP.Height(health, settings.healthHeight)
    health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    health:GetStatusBarTexture():SetHorizTile(false)
    UnsnapTex(health:GetStatusBarTexture())

    local bg = health:CreateTexture(nil, "BACKGROUND")
    PP.Point(bg, "TOPLEFT", health, "TOPLEFT", 0, 0)
    PP.Point(bg, "BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    bg:SetColorTexture(0, 0, 0, 0.5)
    UnsnapTex(bg)
    health.bg = bg

    health.colorClass = true
    health.colorReaction = true
    health.colorTapped = true
    health.colorDisconnected = true
    health._euiUnitKey = UnitToSettingsKey(unit)

    ApplyHealthBarTexture(health, UnitToSettingsKey(unit))
    ApplyHealthBarOpacity(health, UnitToSettingsKey(unit))
    ApplyDarkTheme(health)

    frame.Health = health

    -- Always create portrait; hide backdrop when disabled
    frame.Portrait = CreatePortrait(frame, "left", settings.healthHeight, unit)
    frame._portraitSide = "left"
    if frame.Portrait and not showPortrait then
        frame.Portrait.backdrop:Hide()
    end

    CreateUnifiedBorder(frame, unit)
    UpdateBordersForScale(frame, unit)

    -- Text overlay frame
    local textOverlay = CreateFrame("Frame", nil, health)
    textOverlay:SetAllPoints(health)
    textOverlay:SetFrameLevel(health:GetFrameLevel() + 3)
    frame._textOverlay = textOverlay

    local ts = settings.textSize or 12
    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "none"
    local centerContent = settings.centerTextContent or "none"

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, ts)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    leftText:SetShadowOffset(1, -1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, ts)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    rightText:SetShadowOffset(1, -1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, ts)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    centerText:SetShadowOffset(1, -1)
    frame.CenterText = centerText

    frame.NameText = leftText
    frame.HealthValue = rightText

    local function ApplyTextTags(lc, rc, cc)
        local ltag = ContentToTag(lc)
        local rtag = ContentToTag(rc)
        local ctag = ContentToTag(cc)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        if frame.UpdateTags then frame:UpdateTags() end
    end
    ApplyTextTags(leftContent, rightContent, centerContent)
    frame._applyTextTags = ApplyTextTags

    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "none"
        local cc = s.centerTextContent or "none"
        local barW = s.frameWidth or 100
        if cc ~= "none" then
            centerText:ClearAllPoints()
            centerText:SetPoint("CENTER", health, "CENTER", 0, 0)
            centerText:SetWidth(0)
            centerText:Show()
            leftText:Hide(); rightText:Hide()
        else
            centerText:Hide()
            if lc ~= "none" then
                leftText:ClearAllPoints()
                leftText:SetPoint("LEFT", health, "LEFT", 5, 0)
                leftText:SetJustifyH("LEFT")
                if rc ~= "none" then
                    local rightUsed = EstimateUFTextWidth(rc)
                    PP.Width(leftText, math.max(barW - rightUsed - 10, 20))
                else
                    leftText:SetWidth(0)
                end
                leftText:Show()
            else leftText:Hide() end
            if rc ~= "none" then
                rightText:ClearAllPoints()
                rightText:SetPoint("RIGHT", health, "RIGHT", -5, 0)
                rightText:SetJustifyH("RIGHT")
                if lc ~= "none" then
                    local leftUsed = EstimateUFTextWidth(lc)
                    PP.Width(rightText, math.max(barW - leftUsed - 10, 20))
                else
                    rightText:SetWidth(0)
                end
                rightText:Show()
            else rightText:Hide() end
        end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions
end


local function StyleBossFrame(frame, unit)
    local settings = GetSettingsForUnit(unit)
    local bPpPos = settings.powerPosition or "below"
    local bPpIsAtt = (bPpPos == "below" or bPpPos == "above")
    local powerHeight = bPpIsAtt and (settings.powerHeight or 6) or 0
    local bossBarHeight = settings.healthHeight + powerHeight
    local totalWidth = 0
    local portraitHeight = 0
    local showPortrait = (db.profile.portraitStyle or "attached") ~= "none" and settings.showPortrait ~= false
    if not showPortrait then
        totalWidth = settings.frameWidth
    else
        totalWidth = bossBarHeight + settings.frameWidth
    end

    PP.Size(frame, totalWidth, bossBarHeight)
    local healthRightInset = showPortrait and bossBarHeight or 0
    frame.Health = CreateHealthBar(frame, unit, settings.healthHeight, portraitHeight, settings, healthRightInset)
    frame.Power = CreatePowerBar(frame, unit, settings)
    -- Always create portrait; hide backdrop when disabled
    frame.Portrait = CreatePortrait(frame, "right", bossBarHeight, unit)
    frame._portraitSide = "right"
    if frame.Portrait and not showPortrait then
        frame.Portrait.backdrop:Hide()
    end

    PP.Size(frame, totalWidth, bossBarHeight)

    CreateUnifiedBorder(frame, unit)
    UpdateBordersForScale(frame, unit)

    -- Text overlay frame
    local textOverlay = CreateFrame("Frame", nil, frame.Health)
    textOverlay:SetAllPoints(frame.Health)
    textOverlay:SetFrameLevel(frame.Health:GetFrameLevel() + 3)
    frame._textOverlay = textOverlay

    local bts = settings.textSize or 12
    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "perhp"
    local centerContent = settings.centerTextContent or "none"

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, bts)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    leftText:SetShadowOffset(1, -1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, bts)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    rightText:SetShadowOffset(1, -1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, bts)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    centerText:SetShadowOffset(1, -1)
    frame.CenterText = centerText

    frame.NameText = leftText
    frame.HealthValue = rightText

    local function ApplyTextTags(lc, rc, cc)
        local ltag = ContentToTag(lc)
        local rtag = ContentToTag(rc)
        local ctag = ContentToTag(cc)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        if frame.UpdateTags then frame:UpdateTags() end
    end
    ApplyTextTags(leftContent, rightContent, centerContent)
    frame._applyTextTags = ApplyTextTags

    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "perhp"
        local cc = s.centerTextContent or "none"
        local barW = s.frameWidth or 100
        if cc ~= "none" then
            centerText:ClearAllPoints()
            centerText:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)
            centerText:SetWidth(0)
            centerText:Show()
            leftText:Hide(); rightText:Hide()
        else
            centerText:Hide()
            if lc ~= "none" then
                leftText:ClearAllPoints()
                leftText:SetPoint("LEFT", frame.Health, "LEFT", 5, 0)
                leftText:SetJustifyH("LEFT")
                if rc ~= "none" then
                    local rightUsed = EstimateUFTextWidth(rc)
                    PP.Width(leftText, math.max(barW - rightUsed - 10, 20))
                else
                    leftText:SetWidth(0)
                end
                leftText:Show()
            else leftText:Hide() end
            if rc ~= "none" then
                rightText:ClearAllPoints()
                rightText:SetPoint("RIGHT", frame.Health, "RIGHT", -5, 0)
                rightText:SetJustifyH("RIGHT")
                if lc ~= "none" then
                    local leftUsed = EstimateUFTextWidth(lc)
                    PP.Width(rightText, math.max(barW - leftUsed - 10, 20))
                else
                    rightText:SetWidth(0)
                end
                rightText:Show()
            else rightText:Hide() end
        end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions
end


local function RegisterStylesOnce()
    if _G.EllesmereUF_StylesRegistered then
        return
    end
    _G.EllesmereUF_StylesRegistered = true

    oUF:RegisterStyle("EllesmerePlayer", function(frame, unit)
        StyleFullFrame(frame, unit)
    end)
    oUF:RegisterStyle("EllesmereTarget", function(frame, unit)
        StyleFullFrame(frame, unit)
    end)
    oUF:RegisterStyle("EllesmereFocus", function(frame, unit)
        StyleFocusFrame(frame, unit)
    end)
    oUF:RegisterStyle("EllesmerePet", function(frame, unit)
        StylePetFrame(frame, unit)
    end)
    oUF:RegisterStyle("EllesmereTargetTarget", function(frame, unit)
        StyleSimpleFrame(frame, unit)
    end)
    oUF:RegisterStyle("EllesmereFocusTarget", function(frame, unit)
        StyleSimpleFrame(frame, unit)
    end)
    oUF:RegisterStyle("EllesmereBoss", function(frame, unit)
        StyleBossFrame(frame, unit)
    end)
end


-- Swap portrait mode (3D / 2D / class theme) without recreating frames.
-- All three objects already exist on the backdrop; we just show/hide and reassign frame.Portrait.
local function SwapPortraitMode(frame)
    local portrait = frame.Portrait
    if not portrait or not portrait.backdrop then return end
    local bd = portrait.backdrop
    if not bd._2d or not bd._3d then return end

    local wantMode
    do
        local unit2 = frame.unit or frame:GetAttribute("unit")
        local uKey = UnitToSettingsKey(unit2)
        local s = uKey and db.profile[uKey]
        wantMode = (s and s.portraitMode) or db.profile.portraitMode or "2d"
    end

    -- Class theme only applies to the player frame; others fall back to 2D
    local unit = frame.unit or frame:GetAttribute("unit")
    if wantMode == "class" and unit ~= "player" then
        wantMode = "2d"
    end

    local curMode
    if portrait.isClass then curMode = "class"
    elseif portrait.is2D then curMode = "2d"
    else curMode = "3d" end

    if wantMode == curMode then return end

    -- Disable the oUF element so it unregisters events for the old object
    if frame:IsElementEnabled("Portrait") then
        frame:DisableElement("Portrait")
    end

    -- Hide all
    bd._3d:ClearModel()
    bd._3d:Hide()
    bd._2d:Hide()
    if bd._class then bd._class:Hide() end

    if wantMode == "class" and bd._class then
        bd._class:Show()
        -- Keep tex2D as the oUF element (hidden) so oUF doesn't overwrite texClass
        bd._2d:Hide()
        bd._2d.backdrop = bd
        bd._2d.is2D = true
        bd._2d.isClass = true
        frame.Portrait = bd._2d
        -- Class theme is static -- no oUF element needed, skip re-enable
        return
    elseif wantMode == "3d" then
        bd._3d:Show()
        bd._3d.backdrop = bd
        bd._3d.is2D = false
        bd._3d.isClass = nil
        frame.Portrait = bd._3d
    else
        bd._2d:Show()
        bd._2d.backdrop = bd
        bd._2d.is2D = true
        bd._2d.isClass = nil
        frame.Portrait = bd._2d
    end

    -- Re-enable the oUF element with the new object and force an update
    frame:EnableElement("Portrait")
    frame.Portrait:ForceUpdate()
end

-------------------------------------------------------------------------------
--  Custom Class Power Display (Bars / Circles styles)
-------------------------------------------------------------------------------
local CLASS_POWER_TYPES = {
    ROGUE       = Enum.PowerType.ComboPoints,
    DRUID       = Enum.PowerType.ComboPoints,
    MAGE        = { [62]  = { Enum.PowerType.ArcaneCharges, 4 } }, -- Arcane only
    WARLOCK     = Enum.PowerType.SoulShards,
    PALADIN     = Enum.PowerType.HolyPower,
    MONK        = { [269] = { Enum.PowerType.Chi, 5 } },
    EVOKER      = Enum.PowerType.Essence,
    DEATHKNIGHT = Enum.PowerType.Runes,
    -- Spec-specific custom resources (resolved at creation time)
    DEMONHUNTER = { [581] = { "SOUL_FRAGMENTS_VENGEANCE", 6 } },
    SHAMAN      = { [263] = { "MAELSTROM_WEAPON", 10 } },
    HUNTER      = { [255] = { "TIP_OF_THE_SPEAR", 3 } },
    WARRIOR     = { [72]  = { "WHIRLWIND_STACKS", 4 } },
}

local function DestroyCustomClassPower()
    if frames._customClassPower then
        frames._customClassPower:Hide()
        -- Unregister events on all children to prevent leaks
        local kids = { frames._customClassPower:GetChildren() }
        for _, child in ipairs(kids) do
            child:UnregisterAllEvents()
            child:SetScript("OnEvent", nil)
            child:Hide()
        end
        frames._customClassPower:SetParent(nil)
        frames._customClassPower = nil
    end
end

local function CreateCustomClassPower(playerFrame, style)
    local _, playerClass = UnitClass("player")
    local entry = CLASS_POWER_TYPES[playerClass]
    if not entry then return nil end

    -- Resolve spec-specific entries (table with specID keys)
    local powerType, customMax, isCustom
    if type(entry) == "table" then
        local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
        local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec)
        local specEntry = specID and entry[specID]
        if not specEntry then return nil end
        if type(specEntry) == "table" and type(specEntry[1]) == "string" then
            -- String-keyed custom resource (e.g. "SOUL_FRAGMENTS_VENGEANCE")
            powerType = specEntry[1]
            customMax = specEntry[2]
            isCustom = true
        elseif type(specEntry) == "table" then
            -- Numeric powerType wrapped in a spec table (e.g. Chi for Windwalker)
            powerType = specEntry[1]
            customMax = specEntry[2]
            isCustom = false
        else
            powerType = specEntry
            isCustom = false
        end
    else
        powerType = entry
        isCustom = false
    end

    local maxPower
    if isCustom then
        -- For custom resources, get live max from EllesmereUI helpers
        if powerType == "SOUL_FRAGMENTS_VENGEANCE" then
            maxPower = 6
        elseif powerType == "MAELSTROM_WEAPON" and EllesmereUI and EllesmereUI.GetMaelstromWeapon then
            local _, mMax = EllesmereUI.GetMaelstromWeapon()
            maxPower = (mMax and mMax > 0) and mMax or customMax
        elseif powerType == "TIP_OF_THE_SPEAR" then
            maxPower = customMax
        elseif powerType == "WHIRLWIND_STACKS" then
            maxPower = customMax
        else
            maxPower = customMax or 5
        end
    else
        maxPower = UnitPowerMax("player", powerType) or 5
        if maxPower <= 0 then maxPower = 5 end
    end

    local isModern = (style == "modern")
    local isCircle = (style == "circles")
    local sizeAdj = db.profile.player.classPowerSize or 8
    local spacingAdj = db.profile.player.classPowerSpacing or 2
    local pipSize = isModern and sizeAdj or (isCircle and (sizeAdj + 6) or (sizeAdj + 12))
    local pipH = isModern and math.max(3, math.floor(sizeAdj * 0.375)) or (isCircle and (sizeAdj + 6) or (sizeAdj))
    local gap = spacingAdj
    local pad = isModern and 0 or 4
    local totalW = maxPower * pipSize + (maxPower - 1) * gap + pad
    local totalH = pipH + pad

    local container = CreateFrame("Frame", nil, UIParent)
    PP.Size(container, totalW, totalH)
    container:SetFrameStrata("MEDIUM")
    container:SetFrameLevel(10)

    -- Background color behind all pips (spans left edge of first pip to right edge of last pip)
    local bgCol = db.profile.player.classPowerBgColor or { r = 0.082, g = 0.082, b = 0.082, a = 1.0 }
    local containerBg = container:CreateTexture(nil, "BACKGROUND")
    containerBg:SetAllPoints()
    containerBg:SetColorTexture(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
    UnsnapTex(containerBg)
    container._bg = containerBg

    -- Empty pip color (shown when pip is not filled)
    local emptyCol = db.profile.player.classPowerEmptyColor or { r = 0.2, g = 0.2, b = 0.2, a = 1.0 }

    if not isModern then
        -- Border
        MakeBorder(container, 0, 0, 0, 0.8)
    end

    -- 1px inset bottom border for "above" position (matches frame border color)
    -- Must be on a separate overlay frame at a higher frame level than pip child frames,
    -- because child frames always render over parent textures regardless of draw layer.
    local cpBdrOverlay = CreateFrame("Frame", nil, container)
    cpBdrOverlay:SetAllPoints()
    cpBdrOverlay:SetFrameLevel(container:GetFrameLevel() + 20)
    local cpBottomBdr = cpBdrOverlay:CreateTexture(nil, "OVERLAY", nil, 7)
    PP.Height(cpBottomBdr, 1)
    PP.Point(cpBottomBdr, "BOTTOMLEFT", cpBdrOverlay, "BOTTOMLEFT", 0, 0)
    PP.Point(cpBottomBdr, "BOTTOMRIGHT", cpBdrOverlay, "BOTTOMRIGHT", 0, 0)
    UnsnapTex(cpBottomBdr)
    cpBdrOverlay:Hide()  -- shown only when position is "above"
    container._bottomBdr = cpBottomBdr
    container._bottomBdrFrame = cpBdrOverlay

    -- Per-class pip colors for modern style (matches nameplate pips)
    local MODERN_CLASS_COLORS = {
        ROGUE={1.00,0.96,0.41}, DRUID={1.00,0.49,0.04}, PALADIN={0.96,0.55,0.73},
        MONK={0.00,1.00,0.60}, WARLOCK={0.58,0.51,0.79}, MAGE={0.25,0.78,0.92},
        EVOKER={0.20,0.58,0.50}, DEATHKNIGHT={0.77,0.12,0.23},
        DEMONHUNTER={0.34,0.06,0.46}, SHAMAN={0.00,0.44,0.87},
        HUNTER={0.67,0.83,0.45}, WARRIOR={0.78,0.61,0.43},
    }
    local useClassColor = db.profile.player.classPowerClassColor ~= false
    local cr, cg, cb
    if not useClassColor then
        local cc = db.profile.player.classPowerCustomColor or { r = 1, g = 0.82, b = 0 }
        cr, cg, cb = cc.r, cc.g, cc.b
    elseif isModern then
        local mc = MODERN_CLASS_COLORS[playerClass] or {1.00, 0.84, 0.30}
        cr, cg, cb = mc[1], mc[2], mc[3]
    else
        local classColor = RAID_CLASS_COLORS[playerClass] or { r = 1, g = 1, b = 1 }
        cr, cg, cb = classColor.r, classColor.g, classColor.b
    end

    local function MakePip(parent, index)
        local pip = CreateFrame("Frame", nil, parent)
        pip:SetSize(pipSize, pipH)
        local x = (index - 1) * (pipSize + gap) + pad / 2
        pip:SetPoint("LEFT", parent, "LEFT", x, 0)

        -- Empty bar color (visible when pip is not filled)
        local pipEmpty = pip:CreateTexture(nil, "ARTWORK", nil, 0)
        pipEmpty:SetAllPoints()
        if isCircle then
            pipEmpty:SetTexture("Interface\\COMMON\\Indicator-Gray")
            pipEmpty:SetVertexColor(emptyCol.r, emptyCol.g, emptyCol.b, emptyCol.a)
        else
            pipEmpty:SetColorTexture(emptyCol.r, emptyCol.g, emptyCol.b, emptyCol.a)
            UnsnapTex(pipEmpty)
        end

        -- Fill color (on top of empty)
        local pipFill = pip:CreateTexture(nil, "ARTWORK", nil, 1)
        pipFill:SetAllPoints()

        if isCircle then
            pipFill:SetTexture("Interface\\COMMON\\Indicator-Gray")
            pipFill:SetVertexColor(cr, cg, cb, 1)
        else
            pipFill:SetColorTexture(cr, cg, cb, 1)
            UnsnapTex(pipFill)
        end

        pip._fill = pipFill
        pip._empty = pipEmpty
        return pip
    end

    local pips = {}
    for i = 1, maxPower do
        pips[i] = MakePip(container, i)
    end

    -- Update function
    local isSecretResource = (powerType == "SOUL_FRAGMENTS_VENGEANCE")
    local function UpdatePips()
        local cur, max
        if isCustom then
            -- Custom resource: use EllesmereUI tracker functions
            if powerType == "SOUL_FRAGMENTS_VENGEANCE" then
                cur = C_Spell and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(228477) or 0
                max = 6
            elseif powerType == "MAELSTROM_WEAPON" and EllesmereUI and EllesmereUI.GetMaelstromWeapon then
                cur, max = EllesmereUI.GetMaelstromWeapon()
            elseif powerType == "TIP_OF_THE_SPEAR" and EllesmereUI and EllesmereUI.GetTipOfTheSpear then
                cur, max = EllesmereUI.GetTipOfTheSpear()
            elseif powerType == "WHIRLWIND_STACKS" and EllesmereUI and EllesmereUI.GetWhirlwindStacks then
                cur, max = EllesmereUI.GetWhirlwindStacks()
            else
                cur, max = 0, maxPower
            end
            if not max or max <= 0 then max = maxPower end
        else
            cur = UnitPower("player", powerType) or 0
            max = UnitPowerMax("player", powerType) or maxPower

            -- Handle runes specially (count available runes)
            if powerType == Enum.PowerType.Runes then
                cur = 0
                for i = 1, max do
                    local start, duration, ready = GetRuneCooldown(i)
                    if ready then cur = cur + 1 end
                end
            end
        end

        -- Rebuild pips if max changed
        if max ~= #pips and max > 0 then
            for _, p in ipairs(pips) do p:Hide() end
            local newTotalW = max * pipSize + (max - 1) * gap + pad
            container:SetWidth(newTotalW)
            for i = 1, max do
                if not pips[i] then
                    pips[i] = MakePip(container, i)
                end
                local x = (i - 1) * (pipSize + gap) + pad / 2
                pips[i]:ClearAllPoints()
                pips[i]:SetPoint("TOPLEFT", container, "TOPLEFT", x, 0)
                pips[i]:SetSize(pipSize, pipH)
                pips[i]:Show()
            end
        end

        if isSecretResource then
            -- Secret-value path: use StatusBar overlays per pip
            for i = 1, #pips do
                if pips[i] then
                    if not pips[i]._secretBar then
                        local sb = CreateFrame("StatusBar", nil, pips[i])
                        sb:SetAllPoints(pips[i]._fill or pips[i])
                        sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                        sb:SetStatusBarColor(cr, cg, cb, 1)
                        sb:SetFrameLevel(pips[i]:GetFrameLevel() + 1)
                        pips[i]._secretBar = sb
                    end
                    pips[i]._secretBar:SetMinMaxValues(i - 1, i)
                    pips[i]._secretBar:SetValue(cur)
                    pips[i]._secretBar:SetStatusBarColor(cr, cg, cb, 1)
                    pips[i]._secretBar:Show()
                    -- Hide normal fill; StatusBar replaces it
                    if pips[i]._fill then pips[i]._fill:Hide() end
                end
            end
        else
            -- Clean-value path
            for i = 1, #pips do
                if pips[i] then
                    if pips[i]._secretBar then pips[i]._secretBar:Hide() end
                    if pips[i]._fill then
                        if i <= cur then
                            pips[i]._fill:Show()
                        else
                            pips[i]._fill:Hide()
                        end
                    end
                end
            end
        end
    end

    -- Event driver
    local eventFrame = CreateFrame("Frame", nil, container)
    if isCustom then
        -- Custom resources: poll + manual tracker events
        local elapsed = 0
        eventFrame:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed < 0.1 then return end
            elapsed = 0
            UpdatePips()
        end)
        eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        eventFrame:RegisterEvent("PLAYER_DEAD")
        eventFrame:RegisterEvent("PLAYER_ALIVE")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:SetScript("OnEvent", function(_, event, ...)
            if event == "PLAYER_SPECIALIZATION_CHANGED" then
                -- Spec changed: destroy and rebuild via ReloadFrames
                DestroyCustomClassPower()
                frames._classPowerBar = nil
                C_Timer.After(0.1, function()
                    if ns.ReloadFrames then ns.ReloadFrames() end
                end)
                return
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                -- Route to manual trackers (skip if resource bars handles it)
                if not _G._ERB_AceDB and EllesmereUI then
                    local unit, castGUID, spellID = ...
                    if unit == "player" then
                        if EllesmereUI.HandleTipOfTheSpear then
                            EllesmereUI.HandleTipOfTheSpear(event, unit, castGUID, spellID)
                        end
                        if EllesmereUI.HandleWhirlwindStacks then
                            EllesmereUI.HandleWhirlwindStacks(event, unit, castGUID, spellID)
                        end
                    end
                end
            elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
                if not _G._ERB_AceDB and EllesmereUI then
                    if EllesmereUI.HandleTipOfTheSpear then
                        EllesmereUI.HandleTipOfTheSpear(event)
                    end
                    if EllesmereUI.HandleWhirlwindStacks then
                        EllesmereUI.HandleWhirlwindStacks(event)
                    end
                end
            elseif event == "PLAYER_REGEN_ENABLED" then
                if not _G._ERB_AceDB and EllesmereUI and EllesmereUI.HandleWhirlwindStacks then
                    EllesmereUI.HandleWhirlwindStacks(event)
                end
            end
            UpdatePips()
        end)
    else
        eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        if powerType == Enum.PowerType.Runes then
            eventFrame:RegisterEvent("RUNE_POWER_UPDATE")
        end
        eventFrame:SetScript("OnEvent", function(_, event, unit)
            if event == "PLAYER_ENTERING_WORLD" or event == "RUNE_POWER_UPDATE"
               or (unit == "player") then
                UpdatePips()
            end
        end)
    end

    UpdatePips()
    container._updatePips = UpdatePips
    container._pips = pips
    container._pipSize = pipSize
    container._pipH = pipH
    container._gap = gap
    container._pad = pad

    -- Reposition pips to fill a given width (for "above" position)
    -- Uses Snap() to round all positions to physical pixel boundaries
    -- so gaps between pips are guaranteed identical.
    container._repositionForWidth = function(targetW)
        local n = #pips
        if n <= 0 then return end
        local efs = container:GetEffectiveScale()
        if efs <= 0 then efs = 1 end
        local function Snap(v) return math.floor(v * efs + 0.5) / efs end
        local intW = math.floor(targetW)
        local gapPx = Snap(gap)
        local totalGapW = (n - 1) * gapPx
        local totalPipW = intW - totalGapW
        local basePipW = totalPipW / n
        for i = 1, n do
            local leftEdge = Snap((i - 1) * (basePipW + gapPx))
            local rightEdge = Snap((i - 1) * (basePipW + gapPx) + basePipW)
            local w = rightEdge - leftEdge
            pips[i]:ClearAllPoints()
            pips[i]:SetSize(w, pipH)
            pips[i]:SetPoint("TOPLEFT", container, "TOPLEFT", leftEdge, 0)
        end
        container:SetWidth(intW)
        container:SetHeight(pipH)
    end

    return container
end

local function ReloadFrames()
    if InCombatLockdown() then
        return
    end

    -- Reset cached settings map so it rebuilds with fresh DB references
    unitSettingsMap = nil

    local profile = db.profile
    local castbarColor = GetCastbarColor()
    local castbarOpacity = profile.castbarOpacity
    local enabled = profile.enabledFrames

    -- Resolve donor font for mini frames (inherit from focusâ†’targetâ†’player)
    local donorS = GetMiniDonorSettings()
    local donorFont = donorS.selectedFont or profile.selectedFont or "Expressway"
    local donorFontPath = fontPaths[donorFont] or fontPaths["Expressway"]

    -- Live enable/disable frames without reload
    local function ToggleFrame(unit, frame)
        if not frame then return end
        local unitKey = unit:match("^boss%d$") and "boss" or unit
        local isEnabled = enabled[unitKey] ~= false
        -- Check group visibility for player/target/focus
        if isEnabled and (unitKey == "player" or unitKey == "target" or unitKey == "focus") then
            local s = profile[unitKey]
            if s then
                local inRaid = IsInRaid()
                local inParty = not inRaid and IsInGroup()
                local solo = not inRaid and not inParty
                local vis = (inRaid and (s.showInRaid ~= false))
                    or (inParty and (s.showInParty ~= false))
                    or (solo and (s.showSolo ~= false))
                if not vis then isEnabled = false end
            end
        end
        if isEnabled then
            if not frame:IsShown() and UnitExists(unit) then
                frame:SetAttribute("unit", unit)
                frame:Show()
                -- Re-enable core oUF elements; per-feature elements (Portrait,
                -- Buffs, HealthPrediction) are handled by the per-unit sections below
                for _, elem in ipairs({"Health", "Power", "Debuffs"}) do
                    if frame[elem] and not frame:IsElementEnabled(elem) then
                        frame:EnableElement(elem)
                    end
                end
                frame:UpdateAllElements("ToggleFrame")
            end
        else
            if frame:IsShown() then
                -- Disable all oUF elements for zero performance impact
                for _, elem in ipairs({"Health", "Power", "Portrait", "Castbar", "Buffs", "Debuffs", "HealthPrediction"}) do
                    if frame[elem] and frame:IsElementEnabled(elem) then
                        frame:DisableElement(elem)
                    end
                end
                frame:SetAttribute("unit", nil)
                frame:Hide()
            end
        end
    end

    for unit, frame in pairs(frames) do
        if type(unit) == "string" and unit:sub(1,1) ~= "_" then
            ToggleFrame(unit, frame)
        end
    end

    for unit, frame in pairs(frames) do
        if type(unit) == "string" and unit:sub(1,1) ~= "_" and frame then
            local unitKey = unit:match("^boss%d$") and "boss" or unit
            if enabled[unitKey] == false then
                -- skip disabled frames
            else
            local settings = GetSettingsForUnit(unit)
            local showPortrait = (db.profile.portraitStyle or "attached") ~= "none" and settings.showPortrait ~= false

            -- Swap 2D/3D portrait mode if changed (no reload needed)
            if frame.Portrait then
                SwapPortraitMode(frame)
            end

            -- Show/hide portrait live (no reload needed)
            if frame.Portrait and frame.Portrait.backdrop then
                local uKey = UnitToSettingsKey(unit) or unit
                local uSettings = uKey and db.profile[uKey]
                local isClassMode = ((uSettings and uSettings.portraitMode) or "2d") == "class"
                local unitForClass = unit
                if showPortrait then
                    frame.Portrait.backdrop:Show()
                    if isClassMode and unitForClass == "player" then
                        -- Class theme is static -- keep oUF Portrait disabled (player only)
                        if frame:IsElementEnabled("Portrait") then
                            frame:DisableElement("Portrait")
                        end
                    elseif not frame:IsElementEnabled("Portrait") then
                        frame:EnableElement("Portrait")
                        frame.Portrait:ForceUpdate()
                    end
                else
                    frame.Portrait.backdrop:Hide()
                    if frame:IsElementEnabled("Portrait") then
                        frame:DisableElement("Portrait")
                    end
                end
                -- Live-update detached portrait shape/mask/border
                ApplyDetachedPortraitShape(frame.Portrait.backdrop, uSettings, unit)
                -- Raise detached portrait above border/text/power
                local isDetachedNow = (db.profile.portraitStyle or "attached") == "detached"
                if isDetachedNow then
                    frame.Portrait.backdrop:SetFrameLevel(frame:GetFrameLevel() + 15)
                else
                    frame.Portrait.backdrop:SetFrameLevel(frame:GetFrameLevel() + 1)
                end
            end

            if unit == "player" or unit == "target" then
                local ppPos = settings.powerPosition or "below"
                local ppIsAtt = (ppPos == "below" or ppPos == "above")
                local ppExtra = ppIsAtt and settings.powerHeight or 0
                local playerTargetHeight = settings.healthHeight + ppExtra
                -- Class power "above" adds height above health bar (player only, "top" floats outside)
                local cpAboveH = 0
                if unit == "player" then
                    local cpSt = settings.classPowerStyle or "none"
                    local cpPo = (cpSt == "modern") and (settings.classPowerPosition or "top") or "none"
                    if cpSt == "modern" and cpPo == "above" then
                        local cpSizeAdj = settings.classPowerSize or 8
                        local cpPipH = math.max(3, math.floor(cpSizeAdj * 0.375))
                        cpAboveH = cpPipH
                    end
                end
                local playerTargetHeightWithCp = playerTargetHeight + cpAboveH
                local btbPos = settings.btbPosition or "bottom"
                local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
                local btbExtra = (settings.bottomTextBar and btbIsAttached) and (settings.bottomTextBarHeight or 16) or 0
                local targetFrameHeight = playerTargetHeight + btbExtra
                local portraitHeight = 0
                local totalWidth = 0
                local isAttached = (db.profile.portraitStyle or "attached") == "attached"
                local pSizeAdj = settings.portraitSize or 0
                local pXOff = settings.portraitX or 0
                local pYOff = settings.portraitY or 0
                if not isAttached then pSizeAdj = pSizeAdj + 10; pYOff = pYOff + 5 end

                if unit == "player" then
                    local pSide = settings.portraitSide or "left"
                    local effectiveSide = pSide
                    if isAttached and pSide == "top" then effectiveSide = "left" end
                    local adjPortraitH = playerTargetHeightWithCp + pSizeAdj
                    if adjPortraitH < 8 then adjPortraitH = 8 end
                    if not showPortrait then
                        totalWidth = settings.frameWidth
                        portraitHeight = 0
                    elseif isAttached then
                        totalWidth = adjPortraitH + settings.frameWidth
                        portraitHeight = adjPortraitH
                    else
                        totalWidth = settings.frameWidth
                        portraitHeight = 0
                    end
                    -- Health bar xOffset: only offset when portrait is attached on the left
                    local healthXOffset = 0
                    local healthRightInset = 0
                    if showPortrait and isAttached and effectiveSide == "left" then
                        healthXOffset = portraitHeight
                    elseif showPortrait and isAttached and effectiveSide == "right" then
                        healthRightInset = portraitHeight
                    end

                    PP.Size(frame, totalWidth, playerTargetHeightWithCp + btbExtra)

                    if frame.Portrait and frame.Portrait.backdrop then
                        PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
                        -- Reposition portrait for attached/detached
                        frame.Portrait.backdrop:ClearAllPoints()
                        local pBtbTopOff = (btbPos == "top" and settings.bottomTextBar) and (settings.bottomTextBarHeight or 16) or 0
                        if isAttached then
                            if effectiveSide == "left" then
                                PP.Point(frame.Portrait.backdrop, "TOPLEFT", frame, "TOPLEFT", 0, -pBtbTopOff)
                            else
                                PP.Point(frame.Portrait.backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, -pBtbTopOff)
                            end
                        else
                            if effectiveSide == "top" then
                                frame.Portrait.backdrop:SetPoint("BOTTOM", frame.Health or frame, "TOP", pXOff, 15 + pYOff)
                            elseif effectiveSide == "left" then
                                frame.Portrait.backdrop:SetPoint("TOPRIGHT", frame.Health or frame, "TOPLEFT", -15 + pXOff, pYOff)
                            else
                                frame.Portrait.backdrop:SetPoint("TOPLEFT", frame.Health or frame, "TOPRIGHT", 15 + pXOff, pYOff)
                            end
                        end
                        if frame.Portrait.backdrop._2d then
                            UnsnapTex(frame.Portrait.backdrop._2d)
                        end
                        if frame:IsElementEnabled("Portrait") and frame.Portrait.ForceUpdate then
                            frame.Portrait:ForceUpdate()
                        end
                    end
                    if frame.Health then
                        frame.Health:ClearAllPoints()
                        frame.Health._xOffset = healthXOffset
                        frame.Health._rightInset = healthRightInset
                        local hTopOff = cpAboveH + (btbPos == "top" and settings.bottomTextBar and (settings.bottomTextBarHeight or 16) or 0)
                        PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", healthXOffset, -hTopOff)
                        PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -healthRightInset, 0)
                        PP.Height(frame.Health, settings.healthHeight)
                    end
                    if frame.Power then
                        local pw = settings.frameWidth
                        local ppIsDetached = (ppPos == "detached_top" or ppPos == "detached_bottom")
                        if ppIsDetached and (settings.powerWidth or 0) > 0 then
                            pw = settings.powerWidth
                        end
                        PP.Size(frame.Power, pw, settings.powerHeight)
                        frame.Power:ClearAllPoints()
                        if ppPos == "none" then
                            frame.Power:Hide()
                        elseif ppPos == "above" then
                            PP.Point(frame.Power, "BOTTOM", frame.Health, "TOP", 0, 0)
                            frame.Power:Show()
                        elseif ppPos == "detached_top" then
                            frame.Power:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
                            frame.Power:Show()
                        elseif ppPos == "detached_bottom" then
                            frame.Power:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
                            frame.Power:Show()
                        else
                            PP.Point(frame.Power, "TOP", frame.Health, "BOTTOM", 0, 0)
                            frame.Power:Show()
                        end
                        if frame.Power._applyPowerPercentText then frame.Power._applyPowerPercentText(settings) end
                    end
                    
                    if frame.Castbar then
                        local castbarBg = frame.Castbar:GetParent()
                        if settings.showPlayerCastbar then
                            if not frame:IsElementEnabled("Castbar") then
                                frame:EnableElement("Castbar")
                            end
                            if castbarBg then
                                local castBarOffset = 0
                                if showPortrait and isAttached then
                                    castBarOffset = (effectiveSide == "left") and -(adjPortraitH / 2) or (adjPortraitH / 2)
                                end
                                local cbW = totalWidth
                                local cbH = settings.castbarHeight or 14
                                local owH = settings.playerCastbarHeight or 0
                                if owH > 0 then cbH = owH end
                                castbarBg:SetSize(cbW, cbH)
                                -- Resize cast icon to match castbar height
                                if frame.Castbar._iconFrame then
                                    frame.Castbar._iconFrame:SetSize(cbH + 1, cbH + 1)
                                    -- Icon only visible during active cast AND if showPlayerCastIcon is enabled
                                    if not frame.Castbar:IsShown() or settings.showPlayerCastIcon == false then
                                        frame.Castbar._iconFrame:Hide()
                                    end
                                end
                                castbarBg:ClearAllPoints()
                                local pBtbPos = settings.btbPosition or "bottom"
                                local pBtbVisible = (settings.bottomTextBar and pBtbPos == "bottom" and frame.BottomTextBar and frame.BottomTextBar:IsShown())
                                local anchorFrame = pBtbVisible and frame.BottomTextBar or (ppIsAtt and frame.Power) or frame.Health
                                local pCbXOff = pBtbVisible and 0 or castBarOffset
                                -- Player castbar is always locked to frame â€” no x/y offsets
                                castbarBg:SetPoint("TOP", anchorFrame, "BOTTOM", pCbXOff, 0)
                            end
                            -- Store per-unit settings for PostCastStart
                            frame.Castbar._eufSettings = settings
                            -- Resolve per-unit fill color
                            local pCbColor = castbarColor
                            if settings.castbarClassColored then
                                local _, classToken = UnitClass("player")
                                if classToken then
                                    pCbColor = RAID_CLASS_COLORS[classToken] or castbarColor
                                end
                            elseif settings.castbarFillColor then
                                pCbColor = settings.castbarFillColor
                            end
                            frame.Castbar:SetStatusBarColor(pCbColor.r, pCbColor.g, pCbColor.b, castbarOpacity)
                            -- Apply cast bar text settings
                            if frame.Castbar.Text then
                                local snSz = settings.castSpellNameSize or 11
                                SetFSFont(frame.Castbar.Text, snSz)
                                local snC = settings.castSpellNameColor or { r=1, g=1, b=1 }
                                frame.Castbar.Text:SetTextColor(snC.r, snC.g, snC.b)
                            end
                            if frame.Castbar.Time then
                                local dtSz = settings.castDurationSize or 11
                                SetFSFont(frame.Castbar.Time, dtSz)
                                local dtC = settings.castDurationColor or { r=1, g=1, b=1 }
                                frame.Castbar.Time:SetTextColor(dtC.r, dtC.g, dtC.b)
                            end
                        else
                            if frame:IsElementEnabled("Castbar") then
                                frame:DisableElement("Castbar")
                            end
                            frame.Castbar:Hide()
                            if castbarBg then castbarBg:Hide() end
                        end
                    end

                    -- Live toggle player absorbs
                    if frame.HealthPrediction then
                        if settings.showPlayerAbsorb then
                            if not frame:IsElementEnabled("HealthPrediction") then
                                frame:EnableElement("HealthPrediction")
                            end
                            if frame.HealthPrediction.damageAbsorb then
                                frame.HealthPrediction.damageAbsorb:Show()
                            end
                            if frame.HealthPrediction.ForceUpdate then
                                frame.HealthPrediction:ForceUpdate()
                            elseif frame.UpdateAllElements then
                                frame:UpdateAllElements("ReloadFrames")
                            end
                        else
                            if frame:IsElementEnabled("HealthPrediction") then
                                frame:DisableElement("HealthPrediction")
                            end
                            if frame.HealthPrediction.damageAbsorb then
                                frame.HealthPrediction.damageAbsorb:Hide()
                            end
                        end
                    end

                    -- Live toggle player buffs
                    if frame.Buffs then
                        if settings.showBuffs then
                            if not frame:IsElementEnabled("Buffs") then
                                frame:EnableElement("Buffs")
                            end
                            frame.Buffs:Show()
                            frame.Buffs.num = settings.maxBuffs or 4
                            -- Reposition buffs based on anchor/growth settings
                            local bfp, bia, bgx, bgy, box, boy = ResolveBuffLayout(
                                settings.buffAnchor, settings.buffGrowth
                            )
                            -- Offset bottom-anchored buffs below castbar when locked to frame
                            local buffCbOff = 0
                            if (settings.buffAnchor == "bottomleft" or settings.buffAnchor == "bottomright"
                                or settings.buffAnchor == "left" or settings.buffAnchor == "right")
                                and settings.showPlayerCastbar then
                                local cbH = settings.playerCastbarHeight or 0
                                if cbH <= 0 then cbH = 14 end
                                buffCbOff = -cbH
                            end
                            -- Only reanchor + ForceUpdate when layout actually changed
                            local buffKey = (bia or "") .. (bfp or "") .. (box or 0) .. (boy or 0) .. buffCbOff .. (bgx or 0) .. (bgy or 0) .. (settings.maxBuffs or 4)
                            if frame.Buffs._lastBuffKey ~= buffKey then
                                frame.Buffs._lastBuffKey = buffKey
                                frame.Buffs:ClearAllPoints()
                                frame.Buffs:SetPoint(bia, frame, bfp, box * 1, boy * 1 + buffCbOff)
                                frame.Buffs.initialAnchor = bia
                                frame.Buffs.growthX = bgx
                                frame.Buffs.growthY = bgy
                                if frame.Buffs.ForceUpdate then
                                    frame.Buffs:ForceUpdate()
                                end
                            end
                        else
                            if frame:IsElementEnabled("Buffs") then
                                frame:DisableElement("Buffs")
                            end
                            frame.Buffs:Hide()
                            frame.Buffs.num = 0
                        end
                    end

                    -- Reposition name and health text (player)
                    if frame._applyTextTags then
                        frame._applyTextTags(settings.leftTextContent or "name", settings.rightTextContent or "both", settings.centerTextContent or "none")
                    end
                    if frame._applyTextPositions then
                        frame._applyTextPositions(settings)
                    end

                    -- Bottom Text Bar update (player)
                    if settings.bottomTextBar then
                        local btbPos2 = settings.btbPosition or "bottom"
                        local btbIsAtt = (btbPos2 == "top" or btbPos2 == "bottom")
                        local btbIsDetached = not btbIsAtt
                        local btbW2 = btbIsDetached and (settings.btbWidth or 0) or 0
                        local btbTW = (btbW2 > 0 and btbIsDetached) and btbW2 or totalWidth
                        -- Compute BTB xOffset for left-side portrait (attached only)
                        local btbXOff = 0
                        if btbIsAtt and showPortrait and isAttached and effectiveSide == "left" then
                            btbXOff = -adjPortraitH
                        end
                        local ppBtbAnchor = (ppIsAtt and frame.Power) or frame.Health
                        if not frame.BottomTextBar then
                            frame.BottomTextBar = CreateBottomTextBar(frame, unit, settings, ppBtbAnchor, btbXOff, totalWidth)
                            frame._btb = frame.BottomTextBar
                        else
                            local btb = frame.BottomTextBar
                            PP.Size(btb, btbTW, settings.bottomTextBarHeight or 16)
                            btb:ClearAllPoints()
                            if btbPos2 == "top" then
                                PP.Point(btb, "BOTTOMLEFT", frame.Health or frame, "TOPLEFT", btbXOff, 0)
                            elseif btbPos2 == "detached_top" then
                                btb:SetPoint("BOTTOM", frame, "TOP", settings.btbX or 0, 15 + (settings.btbY or 0))
                            elseif btbPos2 == "detached_bottom" then
                                btb:SetPoint("TOP", frame, "BOTTOM", settings.btbX or 0, -15 + (settings.btbY or 0))
                            else
                                PP.Point(btb, "TOPLEFT", ppBtbAnchor, "BOTTOMLEFT", btbXOff, 0)
                            end
                            -- Update BTB bg color
                            if btb.bg then
                                local bgc = settings.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
                                local bga = settings.btbBgOpacity or 1.0
                                btb.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
                                UnsnapTex(btb.bg)
                            end
                            if btb._applyBTBTextTags then
                                btb._applyBTBTextTags(settings.btbLeftContent or "none", settings.btbRightContent or "none", settings.btbCenterContent or "none")
                            end
                            if btb._applyBTBTextPositions then
                                btb._applyBTBTextPositions(settings)
                if btb._applyBTBClassIcon then btb._applyBTBClassIcon(settings) end
                            end
                            btb:Show()
                        end
                    elseif frame.BottomTextBar then
                        frame.BottomTextBar:Hide()
                    end

                    UpdateBordersForScale(frame, unit)

                elseif unit == "target" then
                    local pSide = settings.portraitSide or "right"
                    local effectiveSide = pSide
                    if isAttached and pSide == "top" then effectiveSide = "right" end
                    local adjPortraitH = playerTargetHeight + pSizeAdj
                    if adjPortraitH < 8 then adjPortraitH = 8 end
                    if not showPortrait then
                        totalWidth = settings.frameWidth
                        portraitHeight = 0
                    elseif isAttached then
                        totalWidth = adjPortraitH + settings.frameWidth
                        portraitHeight = adjPortraitH
                    else
                        totalWidth = settings.frameWidth
                        portraitHeight = 0
                    end
                    -- Health bar xOffset: only offset when portrait is attached on the left
                    local healthXOffset = 0
                    local healthRightInset = 0
                    if showPortrait and isAttached and effectiveSide == "left" then
                        healthXOffset = portraitHeight
                    elseif showPortrait and isAttached and effectiveSide == "right" then
                        healthRightInset = portraitHeight
                    end

                    PP.Size(frame, totalWidth, targetFrameHeight)

                    if frame.Portrait and frame.Portrait.backdrop then
                        PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
                        frame.Portrait.backdrop:ClearAllPoints()
                        local btbTopOff = (btbPos == "top" and settings.bottomTextBar) and (settings.bottomTextBarHeight or 16) or 0
                        if isAttached then
                            if effectiveSide == "left" then
                                PP.Point(frame.Portrait.backdrop, "TOPLEFT", frame, "TOPLEFT", 0, -btbTopOff)
                            else
                                PP.Point(frame.Portrait.backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, -btbTopOff)
                            end
                        else
                            if effectiveSide == "top" then
                                frame.Portrait.backdrop:SetPoint("BOTTOM", frame.Health or frame, "TOP", pXOff, 15 + pYOff)
                            elseif effectiveSide == "left" then
                                frame.Portrait.backdrop:SetPoint("TOPRIGHT", frame.Health or frame, "TOPLEFT", -15 + pXOff, pYOff)
                            else
                                frame.Portrait.backdrop:SetPoint("TOPLEFT", frame.Health or frame, "TOPRIGHT", 15 + pXOff, pYOff)
                            end
                        end
                        if frame.Portrait.backdrop._2d then
                            UnsnapTex(frame.Portrait.backdrop._2d)
                        end
                        if frame:IsElementEnabled("Portrait") and frame.Portrait.ForceUpdate then
                            frame.Portrait:ForceUpdate()
                        end
                    end
                    if frame.Health then
                        frame.Health:ClearAllPoints()
                        PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", healthXOffset, -(btbPos == "top" and settings.bottomTextBar and (settings.bottomTextBarHeight or 16) or 0))
                        PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -healthRightInset, 0)
                        PP.Height(frame.Health, settings.healthHeight)
                    end
                    if frame.Power then
                        local pw2 = settings.frameWidth
                        local ppIsDetached2 = (ppPos == "detached_top" or ppPos == "detached_bottom")
                        if ppIsDetached2 and (settings.powerWidth or 0) > 0 then
                            pw2 = settings.powerWidth
                        end
                        PP.Size(frame.Power, pw2, settings.powerHeight)
                        frame.Power:ClearAllPoints()
                        if ppPos == "none" then
                            frame.Power:Hide()
                        elseif ppPos == "above" then
                            PP.Point(frame.Power, "BOTTOM", frame.Health, "TOP", 0, 0)
                            frame.Power:Show()
                        elseif ppPos == "detached_top" then
                            frame.Power:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
                            frame.Power:Show()
                        elseif ppPos == "detached_bottom" then
                            frame.Power:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
                            frame.Power:Show()
                        else
                            PP.Point(frame.Power, "TOP", frame.Health, "BOTTOM", 0, 0)
                            frame.Power:Show()
                        end
                        if frame.Power._applyPowerPercentText then frame.Power._applyPowerPercentText(settings) end
                    end

                    -- Reposition name and health text
                    if frame._applyTextTags then
                        frame._applyTextTags(settings.leftTextContent or "name", settings.rightTextContent or "both", settings.centerTextContent or "none")
                    end
                    if frame._applyTextPositions then
                        frame._applyTextPositions(settings)
                    end

                    -- Bottom Text Bar update (target) â€” must come before castbar so castbar can anchor to it
                    local tPpBtbAnchor = (ppIsAtt and frame.Power) or frame.Health
                    if settings.bottomTextBar then
                        local btbPos2 = settings.btbPosition or "bottom"
                        local btbIsAtt = (btbPos2 == "top" or btbPos2 == "bottom")
                        local btbIsDetached = not btbIsAtt
                        local btbW2 = btbIsDetached and (settings.btbWidth or 0) or 0
                        local btbTW = (btbW2 > 0 and btbIsDetached) and btbW2 or totalWidth
                        local btbXOff = 0
                        if btbIsAtt and showPortrait and isAttached and effectiveSide == "left" then
                            btbXOff = -adjPortraitH
                        end
                        if not frame.BottomTextBar then
                            frame.BottomTextBar = CreateBottomTextBar(frame, unit, settings, tPpBtbAnchor, btbXOff, totalWidth)
                            frame._btb = frame.BottomTextBar
                        else
                            local btb = frame.BottomTextBar
                            PP.Size(btb, btbTW, settings.bottomTextBarHeight or 16)
                            btb:ClearAllPoints()
                            if btbPos2 == "top" then
                                PP.Point(btb, "BOTTOMLEFT", frame.Health or frame, "TOPLEFT", btbXOff, 0)
                            elseif btbPos2 == "detached_top" then
                                btb:SetPoint("BOTTOM", frame, "TOP", settings.btbX or 0, 15 + (settings.btbY or 0))
                            elseif btbPos2 == "detached_bottom" then
                                btb:SetPoint("TOP", frame, "BOTTOM", settings.btbX or 0, -15 + (settings.btbY or 0))
                            else
                                PP.Point(btb, "TOPLEFT", tPpBtbAnchor, "BOTTOMLEFT", btbXOff, 0)
                            end
                            if btb.bg then
                                local bgc = settings.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
                                local bga = settings.btbBgOpacity or 1.0
                                btb.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
                                UnsnapTex(btb.bg)
                            end
                            if btb._applyBTBTextTags then
                                btb._applyBTBTextTags(settings.btbLeftContent or "none", settings.btbRightContent or "none", settings.btbCenterContent or "none")
                            end
                            if btb._applyBTBTextPositions then
                                btb._applyBTBTextPositions(settings)
                                if btb._applyBTBClassIcon then btb._applyBTBClassIcon(settings) end
                            end
                            btb:Show()
                        end
                    elseif frame.BottomTextBar then
                        frame.BottomTextBar:Hide()
                    end

                    -- Castbar (target) â€” anchors to BTB when BTB is bottom, otherwise to power/health
                    if frame.Castbar then
                        local castbarBg = frame.Castbar:GetParent()
                        if castbarBg then
                            if settings.showCastbar ~= false then
                                if not frame:IsElementEnabled("Castbar") then
                                    frame:EnableElement("Castbar")
                                end
                                local castBarOffset = 0
                                if showPortrait and isAttached then
                                    castBarOffset = (effectiveSide == "left") and -(adjPortraitH / 2) or (adjPortraitH / 2)
                                end
                                castbarBg:SetSize(totalWidth, settings.castbarHeight or 14)
                                if frame.Castbar._iconFrame then
                                    local cbH = settings.castbarHeight or 14
                                    frame.Castbar._iconFrame:SetSize(cbH + 1, cbH + 1)
                                    -- Icon only visible during active cast, always hide on settings update
                                    if not frame.Castbar:IsShown() then
                                        frame.Castbar._iconFrame:Hide()
                                    elseif settings.showCastIcon == false then
                                        frame.Castbar._iconFrame:Hide()
                                    else
                                        frame.Castbar._iconFrame:Show()
                                    end
                                end
                                castbarBg:ClearAllPoints()
                                local tBtbPos = settings.btbPosition or "bottom"
                                local btbVisible = (settings.bottomTextBar and tBtbPos == "bottom" and frame.BottomTextBar and frame.BottomTextBar:IsShown())
                                local cbAnchor = btbVisible and frame.BottomTextBar or tPpBtbAnchor
                                local cbXOff = btbVisible and 0 or castBarOffset
                                castbarBg:SetPoint("TOP", cbAnchor, "BOTTOM", cbXOff, 0)
                                castbarBg:Show()
                            else
                                if frame:IsElementEnabled("Castbar") then
                                    frame:DisableElement("Castbar")
                                end
                                frame.Castbar:Hide()
                                castbarBg:Hide()
                            end
                        end
                        -- Store per-unit settings for PostCastStart
                        frame.Castbar._eufSettings = settings
                        -- Resolve per-unit fill color
                        local tCbColor = castbarColor
                        if settings.castbarClassColored then
                            local _, classToken = UnitClass(unit)
                            if classToken then
                                tCbColor = RAID_CLASS_COLORS[classToken] or castbarColor
                            end
                        elseif settings.castbarFillColor then
                            tCbColor = settings.castbarFillColor
                        end
                        frame.Castbar:SetStatusBarColor(tCbColor.r, tCbColor.g, tCbColor.b, castbarOpacity)
                        -- Apply cast bar text settings
                        if frame.Castbar.Text then
                            local snSz = settings.castSpellNameSize or 11
                            SetFSFont(frame.Castbar.Text, snSz)
                            local snC = settings.castSpellNameColor or { r=1, g=1, b=1 }
                            frame.Castbar.Text:SetTextColor(snC.r, snC.g, snC.b)
                        end
                        if frame.Castbar.Time then
                            local dtSz = settings.castDurationSize or 11
                            SetFSFont(frame.Castbar.Time, dtSz)
                            local dtC = settings.castDurationColor or { r=1, g=1, b=1 }
                            frame.Castbar.Time:SetTextColor(dtC.r, dtC.g, dtC.b)
                        end
                    end

                    -- Buffs
                    if frame.Buffs then
                        local showBuffs = settings.showBuffs ~= false
                        if showBuffs then
                            if not frame:IsElementEnabled("Buffs") then
                                frame:EnableElement("Buffs")
                            end
                            frame.Buffs:Show()
                            frame.Buffs.num = settings.maxBuffs or 20
                            local bfp, bia, bgx, bgy, box, boy = ResolveBuffLayout(
                                settings.buffAnchor, settings.buffGrowth
                            )
                            local liveCbOff = 0
                            if settings.showCastbar ~= false then
                                local bAnc = settings.buffAnchor or "topleft"
                                if bAnc == "bottomleft" or bAnc == "bottomright" then
                                    local cbH = settings.castbarHeight or 14
                                    if cbH <= 0 then cbH = 14 end
                                    liveCbOff = -cbH
                                end
                            end
                            local buffKey = (bia or "") .. (bfp or "") .. (box or 0) .. (boy or 0) .. (bgx or 0) .. (bgy or 0) .. (settings.maxBuffs or 20) .. liveCbOff
                            if frame.Buffs._lastBuffKey ~= buffKey then
                                frame.Buffs._lastBuffKey = buffKey
                                frame.Buffs:ClearAllPoints()
                                frame.Buffs:SetPoint(bia, frame, bfp, box * 1, boy * 1 + liveCbOff)
                                frame.Buffs.initialAnchor = bia
                                frame.Buffs.growthX = bgx
                                frame.Buffs.growthY = bgy
                                if frame.Buffs.ForceUpdate then
                                    frame.Buffs:ForceUpdate()
                                end
                            end
                        else
                            if frame:IsElementEnabled("Buffs") then
                                frame:DisableElement("Buffs")
                            end
                            frame.Buffs:Hide()
                            frame.Buffs.num = 0
                        end
                    end

                    -- Debuffs
                    if frame.Debuffs then
                        frame.Debuffs.num = settings.maxDebuffs or 20
                        local dfp, dia, dgx, dgy, dox, doy = ResolveBuffLayout(
                            settings.debuffAnchor or "bottomleft",
                            settings.debuffGrowth or "auto"
                        )
                        local liveDbCbOff = 0
                        if settings.showCastbar ~= false then
                            local dAnc = settings.debuffAnchor or "bottomleft"
                            if dAnc == "bottomleft" or dAnc == "bottomright" then
                                local cbH = settings.castbarHeight or 14
                                if cbH <= 0 then cbH = 14 end
                                liveDbCbOff = -cbH
                            end
                        end
                        local debuffKey = (dia or "") .. (dfp or "") .. (dox or 0) .. (doy or 0) .. (dgx or 0) .. (dgy or 0) .. (settings.maxDebuffs or 20) .. liveDbCbOff
                        if frame.Debuffs._lastDebuffKey ~= debuffKey then
                            frame.Debuffs._lastDebuffKey = debuffKey
                            frame.Debuffs:ClearAllPoints()
                            frame.Debuffs:SetPoint(dia, frame, dfp, dox * 1, doy * 1 + liveDbCbOff)
                            frame.Debuffs.initialAnchor = dia
                            frame.Debuffs.growthX = dgx
                            frame.Debuffs.growthY = dgy
                            if frame.Debuffs.ForceUpdate then
                                frame.Debuffs:ForceUpdate()
                            end
                        end
                    end

                    UpdateBordersForScale(frame, unit)
                end

                -- (health tag re-tagging now handled by _applyTextTags above)

            elseif unit == "focus" then
                local fPpPos = settings.powerPosition or "below"
                local fPpIsAtt = (fPpPos == "below" or fPpPos == "above")
                local powerHeight = fPpIsAtt and (settings.powerHeight or 6) or 0
                local focusBarHeight = settings.healthHeight + powerHeight
                local fBtbPos = settings.btbPosition or "bottom"
                local fBtbIsAtt = (fBtbPos == "top" or fBtbPos == "bottom")
                local fBtbExtra = (settings.bottomTextBar and fBtbIsAtt) and (settings.bottomTextBarHeight or 16) or 0
                local totalWidth = 0
                local isAttached = (db.profile.portraitStyle or "attached") == "attached"
                local pSide = settings.portraitSide or "right"
                local effectiveSide = pSide
                if isAttached and pSide == "top" then effectiveSide = "right" end
                local pSizeAdj = settings.portraitSize or 0
                if not isAttached then pSizeAdj = pSizeAdj + 10 end
                local pXOff = settings.portraitX or 0
                local pYOff = settings.portraitY or 0
                if not isAttached then pYOff = pYOff + 5 end
                local adjPortraitH = focusBarHeight + pSizeAdj
                if adjPortraitH < 8 then adjPortraitH = 8 end

                if not showPortrait then
                    totalWidth = settings.frameWidth
                elseif isAttached then
                    totalWidth = adjPortraitH + settings.frameWidth
                else
                    totalWidth = settings.frameWidth
                end

                PP.Size(frame, totalWidth, focusBarHeight + fBtbExtra)

                if frame.Portrait and frame.Portrait.backdrop then
                    PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
                    -- Reposition portrait for attached/detached
                    frame.Portrait.backdrop:ClearAllPoints()
                    local fBtbTopOff = (fBtbPos == "top" and settings.bottomTextBar) and (settings.bottomTextBarHeight or 16) or 0
                    if isAttached then
                        if effectiveSide == "left" then
                            PP.Point(frame.Portrait.backdrop, "TOPLEFT", frame, "TOPLEFT", 0, -fBtbTopOff)
                        else
                            PP.Point(frame.Portrait.backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, -fBtbTopOff)
                        end
                    else
                        if effectiveSide == "top" then
                            frame.Portrait.backdrop:SetPoint("BOTTOM", frame.Health or frame, "TOP", pXOff, 15 + pYOff)
                        elseif effectiveSide == "left" then
                            frame.Portrait.backdrop:SetPoint("TOPRIGHT", frame.Health or frame, "TOPLEFT", -15 + pXOff, pYOff)
                        else
                            frame.Portrait.backdrop:SetPoint("TOPLEFT", frame.Health or frame, "TOPRIGHT", 15 + pXOff, pYOff)
                        end
                    end
                    -- Re-apply pixel snap disable after resize
                    if frame.Portrait.backdrop._2d then
                        UnsnapTex(frame.Portrait.backdrop._2d)
                    end
                    if frame:IsElementEnabled("Portrait") and frame.Portrait.ForceUpdate then
                        frame.Portrait:ForceUpdate()
                    end
                end
                if frame.Health then
                    frame.Health:ClearAllPoints()
                    local focusHealthXOff = (showPortrait and isAttached and effectiveSide == "left") and adjPortraitH or 0
                    local focusHealthRightInset = (showPortrait and isAttached and effectiveSide == "right") and adjPortraitH or 0
                    PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", focusHealthXOff, -(fBtbPos == "top" and settings.bottomTextBar and (settings.bottomTextBarHeight or 16) or 0))
                    PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -focusHealthRightInset, 0)
                    PP.Height(frame.Health, settings.healthHeight)
                end
                if frame.Power then
                    local fpw = settings.frameWidth
                    local fPpIsDet = (fPpPos == "detached_top" or fPpPos == "detached_bottom")
                    if fPpIsDet and (settings.powerWidth or 0) > 0 then
                        fpw = settings.powerWidth
                    end
                    PP.Size(frame.Power, fpw, settings.powerHeight or 6)
                    frame.Power:ClearAllPoints()
                    if fPpPos == "none" then
                        frame.Power:Hide()
                    elseif fPpPos == "above" then
                        PP.Point(frame.Power, "BOTTOM", frame.Health, "TOP", 0, 0)
                        frame.Power:Show()
                    elseif fPpPos == "detached_top" then
                        frame.Power:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
                        frame.Power:Show()
                    elseif fPpPos == "detached_bottom" then
                        frame.Power:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
                        frame.Power:Show()
                    else
                        PP.Point(frame.Power, "TOP", frame.Health, "BOTTOM", 0, 0)
                        frame.Power:Show()
                    end
                    if frame.Power._applyPowerPercentText then frame.Power._applyPowerPercentText(settings) end
                end
                if frame._applyTextTags then
                    frame._applyTextTags(settings.leftTextContent or "name", settings.rightTextContent or "perhp", settings.centerTextContent or "none")
                end
                if frame._applyTextPositions then
                    frame._applyTextPositions(settings)
                end

                -- Bottom Text Bar update (focus) â€” must come before castbar so castbar can anchor to it
                local fPpBtbAnchor = (fPpIsAtt and frame.Power) or frame.Health
                if settings.bottomTextBar then
                    local btbPos2 = settings.btbPosition or "bottom"
                    local btbIsAtt2 = (btbPos2 == "top" or btbPos2 == "bottom")
                    local btbIsDet2 = not btbIsAtt2
                    local btbW2 = btbIsDet2 and (settings.btbWidth or 0) or 0
                    local btbTW = (btbW2 > 0 and btbIsDet2) and btbW2 or totalWidth
                    local btbXOff = 0
                    if btbIsAtt2 and showPortrait and isAttached and effectiveSide == "left" then
                        btbXOff = -adjPortraitH
                    end
                    if not frame.BottomTextBar then
                        frame.BottomTextBar = CreateBottomTextBar(frame, unit, settings, fPpBtbAnchor, btbXOff, totalWidth)
                        frame._btb = frame.BottomTextBar
                    else
                        local btb = frame.BottomTextBar
                        PP.Size(btb, btbTW, settings.bottomTextBarHeight or 16)
                        btb:ClearAllPoints()
                        if btbPos2 == "top" then
                            PP.Point(btb, "BOTTOMLEFT", frame.Health or frame, "TOPLEFT", btbXOff, 0)
                        elseif btbPos2 == "detached_top" then
                            btb:SetPoint("BOTTOM", frame, "TOP", settings.btbX or 0, 15 + (settings.btbY or 0))
                        elseif btbPos2 == "detached_bottom" then
                            btb:SetPoint("TOP", frame, "BOTTOM", settings.btbX or 0, -15 + (settings.btbY or 0))
                        else
                            PP.Point(btb, "TOPLEFT", fPpBtbAnchor, "BOTTOMLEFT", btbXOff, 0)
                        end
                        if btb.bg then
                            local bgc = settings.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
                            local bga = settings.btbBgOpacity or 1.0
                            btb.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
                            UnsnapTex(btb.bg)
                        end
                        if btb._applyBTBTextTags then
                            btb._applyBTBTextTags(settings.btbLeftContent or "none", settings.btbRightContent or "none", settings.btbCenterContent or "none")
                        end
                        if btb._applyBTBTextPositions then
                            btb._applyBTBTextPositions(settings)
                            if btb._applyBTBClassIcon then btb._applyBTBClassIcon(settings) end
                        end
                        btb:Show()
                    end
                elseif frame.BottomTextBar then
                    frame.BottomTextBar:Hide()
                end

                -- Castbar (focus) â€” anchors to BTB when BTB is bottom, otherwise to power/health
                if frame.Castbar then
                    local castbarBg = frame.Castbar:GetParent()
                    if castbarBg then
                        if settings.showCastbar ~= false then
                            if not frame:IsElementEnabled("Castbar") then
                                frame:EnableElement("Castbar")
                            end
                            local castBarOffset = 0
                            if showPortrait and isAttached then
                                castBarOffset = (effectiveSide == "left") and -(adjPortraitH / 2) or (adjPortraitH / 2)
                            end
                            castbarBg:SetSize(totalWidth, settings.castbarHeight or 14)
                            if frame.Castbar._iconFrame then
                                local cbH = settings.castbarHeight or 14
                                frame.Castbar._iconFrame:SetSize(cbH + 1, cbH + 1)
                                -- Icon only visible during active cast, always hide on settings update
                                if not frame.Castbar:IsShown() then
                                    frame.Castbar._iconFrame:Hide()
                                elseif settings.showCastIcon == false then
                                    frame.Castbar._iconFrame:Hide()
                                else
                                    frame.Castbar._iconFrame:Show()
                                end
                            end
                            castbarBg:ClearAllPoints()
                            local fBtbPos2 = settings.btbPosition or "bottom"
                            local btbVisible = (settings.bottomTextBar and fBtbPos2 == "bottom" and frame.BottomTextBar and frame.BottomTextBar:IsShown())
                            local cbAnchor = btbVisible and frame.BottomTextBar or fPpBtbAnchor
                            local cbXOff = btbVisible and 0 or castBarOffset
                            castbarBg:SetPoint("TOP", cbAnchor, "BOTTOM", cbXOff, 0)
                            castbarBg:Show()
                        else
                            if frame:IsElementEnabled("Castbar") then
                                frame:DisableElement("Castbar")
                            end
                            frame.Castbar:Hide()
                            castbarBg:Hide()
                        end
                    end
                    -- Store per-unit settings for PostCastStart
                    frame.Castbar._eufSettings = settings
                    -- Resolve per-unit fill color
                    local fCbColor = castbarColor
                    if settings.castbarClassColored then
                        local _, classToken = UnitClass(unit)
                        if classToken then
                            fCbColor = RAID_CLASS_COLORS[classToken] or castbarColor
                        end
                    elseif settings.castbarFillColor then
                        fCbColor = settings.castbarFillColor
                    end
                    frame.Castbar:SetStatusBarColor(fCbColor.r, fCbColor.g, fCbColor.b, castbarOpacity)
                    -- Apply cast bar text settings
                    if frame.Castbar.Text then
                        local snSz = settings.castSpellNameSize or 11
                        SetFSFont(frame.Castbar.Text, snSz)
                        local snC = settings.castSpellNameColor or { r=1, g=1, b=1 }
                        frame.Castbar.Text:SetTextColor(snC.r, snC.g, snC.b)
                    end
                    if frame.Castbar.Time then
                        local dtSz = settings.castDurationSize or 11
                        SetFSFont(frame.Castbar.Time, dtSz)
                        local dtC = settings.castDurationColor or { r=1, g=1, b=1 }
                        frame.Castbar.Time:SetTextColor(dtC.r, dtC.g, dtC.b)
                    end
                end

                UpdateBordersForScale(frame, unit)

            elseif unit == "pet" or unit == "targettarget" or unit == "focustarget" then
                if unit == "pet" then
                    local showPetPortrait = (db.profile.portraitStyle or "attached") ~= "none" and settings.showPortrait ~= false
                    local petW = settings.frameWidth
                    if showPetPortrait then
                        petW = settings.healthHeight + settings.frameWidth
                    end
                    PP.Size(frame, petW, settings.healthHeight)
                    if frame.Health then
                        frame.Health:ClearAllPoints()
                        PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", showPetPortrait and settings.healthHeight or 0, 0)
                        PP.Point(frame.Health, "RIGHT", frame, "RIGHT", 0, 0)
                        PP.Height(frame.Health, settings.healthHeight)
                    end
                    if frame.Portrait and frame.Portrait.backdrop then
                        PP.Size(frame.Portrait.backdrop, settings.healthHeight, settings.healthHeight)
                    end
                else
                    PP.Size(frame, settings.frameWidth, settings.healthHeight)
                    if frame.Health then
                        frame.Health:ClearAllPoints()
                        PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                        PP.Point(frame.Health, "RIGHT", frame, "RIGHT", 0, 0)
                        PP.Height(frame.Health, settings.healthHeight)
                    end
                end

                UpdateBordersForScale(frame, unit)

            elseif unit:match("^boss%d$") then
                local bPpPos = settings.powerPosition or "below"
                local bPpIsAtt = (bPpPos == "below" or bPpPos == "above")
                local powerHeight = bPpIsAtt and (settings.powerHeight or 6) or 0
                local bossBarHeight = settings.healthHeight + powerHeight
                local totalWidth = 0

                if not showPortrait then
                    totalWidth = settings.frameWidth
                else
                    totalWidth = bossBarHeight + settings.frameWidth
                end

                PP.Size(frame, totalWidth, bossBarHeight)

                if frame.Portrait and frame.Portrait.backdrop then
                    PP.Size(frame.Portrait.backdrop, bossBarHeight, bossBarHeight)
                end
                if frame.Health then
                    frame.Health:ClearAllPoints()
                    PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                    PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -(showPortrait and bossBarHeight or 0), 0)
                    PP.Height(frame.Health, settings.healthHeight)
                end
                if frame.Power then
                    local bpw = settings.frameWidth
                    local bPpIsDet = (bPpPos == "detached_top" or bPpPos == "detached_bottom")
                    if bPpIsDet and (settings.powerWidth or 0) > 0 then
                        bpw = settings.powerWidth
                    end
                    frame.Power:SetSize(bpw, settings.powerHeight or 6)
                    frame.Power:ClearAllPoints()
                    if bPpPos == "none" then
                        frame.Power:Hide()
                    elseif bPpPos == "above" then
                        PP.Point(frame.Power, "BOTTOM", frame.Health, "TOP", 0, 0)
                        frame.Power:Show()
                    elseif bPpPos == "detached_top" then
                        frame.Power:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
                        frame.Power:Show()
                    elseif bPpPos == "detached_bottom" then
                        frame.Power:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
                        frame.Power:Show()
                    else
                        PP.Point(frame.Power, "TOP", frame.Health, "BOTTOM", 0, 0)
                        frame.Power:Show()
                    end
                    if frame.Power._applyPowerPercentText then frame.Power._applyPowerPercentText(settings) end
                end

                UpdateBordersForScale(frame, unit)
            end

            -- Determine if this is a mini frame that inherits border/texture/font
            local isMiniFrame = (unit == "pet" or unit == "targettarget" or unit == "focustarget" or unit:match("^boss%d$"))
            local donorSettings = isMiniFrame and GetMiniDonorSettings() or settings

            -- Apply health bar texture overlay (use donor for mini frames)
            if isMiniFrame then
                -- Override texture settings from donor
                local uKey = UnitToSettingsKey(unit)
                local origTex = settings.healthBarTexture
                local origHbOp = settings.healthBarOpacity
                settings.healthBarTexture = donorSettings.healthBarTexture
                settings.healthBarOpacity = donorSettings.healthBarOpacity
                ApplyHealthBarTexture(frame.Health, uKey)
                ApplyHealthBarOpacity(frame.Health, uKey)
                settings.healthBarTexture = origTex
                settings.healthBarOpacity = origHbOp
            else
                ApplyHealthBarTexture(frame.Health, UnitToSettingsKey(unit))
                ApplyHealthBarOpacity(frame.Health, UnitToSettingsKey(unit))
            end
            ApplyDarkTheme(frame.Health)
            if frame.Health.ForceUpdate then
                frame.Health:ForceUpdate()
            end

            -- Apply power bar opacity
            if frame.Power then
                if isMiniFrame then
                    local uKey = UnitToSettingsKey(unit)
                    local origPbOp = settings.powerBarOpacity
                    settings.powerBarOpacity = donorSettings.powerBarOpacity
                    ApplyPowerBarOpacity(frame.Power, uKey)
                    settings.powerBarOpacity = origPbOp
                else
                    ApplyPowerBarOpacity(frame.Power, UnitToSettingsKey(unit))
                end
            end

            if frame.unifiedBorder then
                frame.unifiedBorder:ClearAllPoints()
                local bs = donorSettings.borderSize or 1
                local bc = donorSettings.borderColor or { r = 0, g = 0, b = 0 }
                if bs == 0 then
                    frame.unifiedBorder:Hide()
                else
                    PP.Point(frame.unifiedBorder, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                    PP.Point(frame.unifiedBorder, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
                    if frame.unifiedBorder._texs then
                        for _, t in ipairs(frame.unifiedBorder._texs) do
                            t:SetColorTexture(bc.r, bc.g, bc.b, 1)
                        end
                        PP.Height(frame.unifiedBorder._texs[1], bs)
                        PP.Height(frame.unifiedBorder._texs[2], bs)
                        PP.Width(frame.unifiedBorder._texs[3], bs)
                        PP.Width(frame.unifiedBorder._texs[4], bs)
                    end
                    frame.unifiedBorder:Show()
                end
            end

            -- Helper: set font on a FontString, using donor font for mini frames
            local function SetMiniFont(fs, sz)
                if not fs or not fs.SetFont then return end
                if isMiniFrame then
                    fs:SetFont(donorFontPath, sz or 12, "SHADOW")
                else
                    SetFSFont(fs, sz)
                end
            end

            if frame.NameText then
                local s = isMiniFrame and donorSettings or GetSettingsForUnit(unit)
                local rts = s.leftTextSize or s.textSize or 12
                SetMiniFont(frame.NameText, rts)
                frame.NameText:SetWordWrap(false)
            end
            if frame.HealthValue then
                local s = isMiniFrame and donorSettings or GetSettingsForUnit(unit)
                local rts = s.rightTextSize or s.textSize or 12
                SetMiniFont(frame.HealthValue, rts)
                frame.HealthValue:SetWordWrap(false)
            end
            if frame.CenterText then
                local s = isMiniFrame and donorSettings or GetSettingsForUnit(unit)
                local cts = s.centerTextSize or s.textSize or 12
                SetMiniFont(frame.CenterText, cts)
                frame.CenterText:SetWordWrap(false)
            end

            -- Apply text tags and positions for mini frames
            if isMiniFrame and frame._applyTextTags then
                frame._applyTextTags(settings.leftTextContent or "name", settings.rightTextContent or "none", settings.centerTextContent or "none")
            end
            if isMiniFrame and frame._applyTextPositions then
                frame._applyTextPositions(settings)
            end

            if frame.Castbar then
                if frame.Castbar.Text then
                    SetFSFont(frame.Castbar.Text, 11)
                end
                if frame.Castbar.Time then
                    SetFSFont(frame.Castbar.Time, 11)
                end
            end
            end -- else (enabled frame processing)
        end
    end

    -- Apply frame scale for all units after layout (centered, animated)
    for unit, frame in pairs(frames) do
        if type(unit) == "string" and unit:sub(1,1) ~= "_" and frame then
            local s = GetSettingsForUnit(unit)
            local sc = (s and s.frameScale) or 100
            ApplyFrameScaleCentered(frame, unit, sc / 100, true)
        end
    end

    -- Refresh combat indicator on player frame after settings change
    if frames.player and frames.player._applyCombatTexture then
        frames.player._applyCombatTexture()
        if (db.profile.player.combatIndicatorStyle or "standard") ~= "none" and UnitAffectingCombat("player") then
            frames.player._combatIndicator:Show()
        else
            frames.player._combatIndicator:Hide()
        end
    end
end

function InitializeFrames()
    if oUF and oUF.colors and oUF.colors.power then
        local manaColor = { r = MANA_COLOR.r, g = MANA_COLOR.g, b = MANA_COLOR.b }
        manaColor.GetRGB = function(self) return self.r, self.g, self.b end
        oUF.colors.power[0] = manaColor
    end

    if oUF.Tags and oUF.Tags.SetEventUpdateTimer then
        oUF.Tags:SetEventUpdateTimer(0.25)
    end

    local classPowerStyle = db.profile.player.classPowerStyle or "none"
    local savedClassPowerBar = nil
    if classPowerStyle == "blizzard" then
        if PlayerFrame and PlayerFrame.classPowerBar then
            savedClassPowerBar = PlayerFrame.classPowerBar
            PlayerFrame.classPowerBar = nil
            savedClassPowerBar:SetParent(UIParent)
        end
    end

    local enabled = db.profile.enabledFrames

    RegisterStylesOnce()

    local function SetupUnitMenu(frame, unit)
        frame:RegisterForClicks("AnyUp")
        frame:SetAttribute("*type2", "togglemenu")
        frame:HookScript("OnEnter", UnitFrame_OnEnter)
        frame:HookScript("OnLeave", UnitFrame_OnLeave)
    end

    -- Apply frame scale from per-unit settings
    local function ApplyFrameScale(frame, unit)
        if not frame then return end
        local settings = GetSettingsForUnit(unit)
        local scale = (settings and settings.frameScale) or 100
        ApplyFrameScaleCentered(frame, unit, scale / 100, false)
    end

    -- Always spawn all frames; hide disabled ones for zero performance impact
    oUF:SetActiveStyle("EllesmerePlayer")
    frames.player = oUF:Spawn("player", "EllesmereUIUnitFrames_Player")
    ApplyFramePosition(frames.player, "player")
    ApplyFrameScale(frames.player, "player")
    SetupUnitMenu(frames.player, "player")

    if enabled.player == false then
        frames.player:Hide()
        frames.player:SetAttribute("unit", nil)
    end

    -- Combat indicator overlay on player frame
    do
        local pf = frames.player
        local ps = db.profile.player
        local COMBAT_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\combat\\"

        -- Create a holder frame at a high frame level so the indicator draws above everything
        local combatHolder = CreateFrame("Frame", nil, pf)
        combatHolder:SetAllPoints(pf)
        combatHolder:SetFrameLevel(pf:GetFrameLevel() + 20)
        local combat = combatHolder:CreateTexture(nil, "OVERLAY", nil, 7)
        combat:Hide()
        pf._combatIndicator = combat

        -- Helper: resolve which texture file + coords to use
        local function ApplyCombatTexture()
            local style = ps.combatIndicatorStyle or "standard"
            if style == "none" then combat:Hide(); return end

            local colorMode = ps.combatIndicatorColor or "custom"
            local sz = ps.combatIndicatorSize or 22
            local ox = ps.combatIndicatorX or 0
            local oy = ps.combatIndicatorY or 0
            local pos = ps.combatIndicatorPosition or "healthbar"

            combat:SetSize(sz, sz)
            combat:ClearAllPoints()

            -- Determine anchor element
            local anchor = pf
            if pos == "healthbar" and pf.Health then
                anchor = pf.Health
            elseif pos == "textbar" and pf._btb then
                anchor = pf._btb
            elseif pos == "portrait" and pf.Portrait then
                anchor = pf.Portrait
            end
            combat:SetPoint("CENTER", anchor, "CENTER", ox, oy)

            -- Determine texture file (always use -custom / white base)
            local _, classToken = UnitClass("player")
            if style == "class" then
                combat:SetTexture(COMBAT_MEDIA .. "combat-indicator-class-custom.png")
                local coords = CLASS_FULL_COORDS[classToken]
                if coords then
                    combat:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                else
                    combat:SetTexCoord(0, 1, 0, 1)
                end
            else
                combat:SetTexture(COMBAT_MEDIA .. "combat-indicator-custom.png")
                combat:SetTexCoord(0, 1, 0, 1)
            end

            -- Apply color tint
            if colorMode == "classcolor" then
                local cc = RAID_CLASS_COLORS[classToken] or { r = 1, g = 1, b = 1 }
                combat:SetVertexColor(cc.r, cc.g, cc.b, 1)
            elseif colorMode == "custom" then
                local cc = ps.combatIndicatorCustomColor or { r = 1, g = 1, b = 1 }
                combat:SetVertexColor(cc.r, cc.g, cc.b, 1)
            else
                combat:SetVertexColor(1, 1, 1, 1)
            end
        end
        pf._applyCombatTexture = ApplyCombatTexture

        -- Event frame for combat state changes
        local combatFrame = CreateFrame("Frame", nil, pf)
        combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        combatFrame:SetScript("OnEvent", function(_, event)
            local style = ps.combatIndicatorStyle or "standard"
            if style ~= "none" then
                if event == "PLAYER_REGEN_DISABLED" then
                    ApplyCombatTexture()
                    combat:Show()
                else
                    combat:Hide()
                end
            else
                combat:Hide()
            end
        end)

        -- Set correct initial state
        local style = ps.combatIndicatorStyle or "standard"
        if style ~= "none" and UnitAffectingCombat("player") then
            ApplyCombatTexture()
            combat:Show()
        end
    end

    -- Rested indicator ("ZZZ") on player health bar top-left
    do
        local pf = frames.player
        if pf and pf.Health then
            local restHolder = CreateFrame("Frame", nil, pf.Health)
            restHolder:SetAllPoints(pf.Health)
            restHolder:SetFrameLevel(pf.Health:GetFrameLevel() + 5)

            local restText = restHolder:CreateFontString(nil, "OVERLAY")
            SetFSFont(restText, 9)
            restText:SetTextColor(1, 1, 1)
            restText:SetShadowOffset(1, -1)
            restText:SetText("ZZZ")
            restText:SetPoint("TOPLEFT", pf.Health, "TOPLEFT", 3, -2)
            restText:Hide()
            pf._restIndicator = restText

            local restFrame = CreateFrame("Frame", nil, pf)
            restFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
            restFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            restFrame:SetScript("OnEvent", function()
                if IsResting() then
                    restText:Show()
                else
                    restText:Hide()
                end
            end)

            if IsResting() then restText:Show() end
        end
    end

    -- Always suppress the Blizzard default castbar — we have our own.
    -- This must run unconditionally so zone changes (portals, etc.) can't
    -- re-show it even when the player castbar setting is disabled.
    if PlayerCastingBarFrame then
        PlayerCastingBarFrame:UnregisterAllEvents()
        PlayerCastingBarFrame:Hide()
        PlayerCastingBarFrame:SetScript("OnUpdate", nil)
        if not PlayerCastingBarFrame._euiShowHooked then
            PlayerCastingBarFrame._euiShowHooked = true
            hooksecurefunc(PlayerCastingBarFrame, "Show", function(self) self:Hide() end)
        end
    end
    -- Re-suppress after zone changes: Blizzard re-registers events on PlayerCastingBarFrame
    -- on PLAYER_ENTERING_WORLD, which lets it show again on the next cast.
    -- The hooksecurefunc on Show above already makes it permanently invisible,
    -- but hiding it here prevents even a single-frame flash before the hook fires.
    do
        local cbSuppressFrame = CreateFrame("Frame")
        cbSuppressFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        cbSuppressFrame:SetScript("OnEvent", function()
            if PlayerCastingBarFrame then
                PlayerCastingBarFrame:Hide()
            end
        end)
    end

    -- Resize frame and portrait to account for class power pips above health bar
    local function ResizeFrameForClassPower(cpAboveH)
        local frame = frames.player
        if not frame then return end
        local settings = GetSettingsForUnit("player")
        local ppPos = settings.powerPosition or "below"
        local ppIsAtt = (ppPos == "below" or ppPos == "above")
        local ppExtra = ppIsAtt and settings.powerHeight or 0
        local baseH = settings.healthHeight + ppExtra
        local btbPos2 = settings.btbPosition or "bottom"
        local btbIsAtt = (btbPos2 == "top" or btbPos2 == "bottom")
        local btbExtra = (settings.bottomTextBar and btbIsAtt) and (settings.bottomTextBarHeight or 16) or 0
        local totalH = baseH + cpAboveH + btbExtra

        local showPortrait = (db.profile.portraitStyle or "attached") ~= "none" and settings.showPortrait ~= false
        local isAttached = (db.profile.portraitStyle or "attached") == "attached"
        local pSizeAdj = settings.portraitSize or 0
        if not isAttached then pSizeAdj = pSizeAdj + 10 end
        local adjPortraitH = baseH + cpAboveH + pSizeAdj
        if adjPortraitH < 8 then adjPortraitH = 8 end

        local pSide = settings.portraitSide or "left"
        local effectiveSide = pSide
        if isAttached and pSide == "top" then effectiveSide = "left" end

        local totalWidth
        local portraitW = 0
        if not showPortrait then
            totalWidth = settings.frameWidth
        elseif isAttached then
            totalWidth = adjPortraitH + settings.frameWidth
            portraitW = adjPortraitH
        else
            totalWidth = settings.frameWidth
        end

        PP.Size(frame, totalWidth, totalH)

        -- Update health bar xOffset when portrait width changes
        if frame.Health then
            local newXOff = (showPortrait and isAttached and effectiveSide == "left") and portraitW or 0
            local newRightInset = (showPortrait and isAttached and effectiveSide == "right") and portraitW or 0
            frame.Health._xOffset = newXOff
            frame.Health._rightInset = newRightInset
        end

        if frame.Portrait and frame.Portrait.backdrop and showPortrait then
            PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
            frame.Portrait.backdrop:ClearAllPoints()
            if isAttached then
                if effectiveSide == "left" then
                    PP.Point(frame.Portrait.backdrop, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                else
                    PP.Point(frame.Portrait.backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
                end
            end
            if frame.Portrait.backdrop._2d then
                UnsnapTex(frame.Portrait.backdrop._2d)
            end
            if frame:IsElementEnabled("Portrait") and frame.Portrait.ForceUpdate then
                frame.Portrait:ForceUpdate()
            end
        end
    end

    local function PositionClassPowerBar(bar)
        if not bar or not frames.player then return end
        bar:ClearAllPoints()
        local style = db.profile.player.classPowerStyle or "none"
        local position = db.profile.player.classPowerPosition or "top"
        local offsetX = db.profile.player.classPowerBarX or 0
        local offsetY = db.profile.player.classPowerBarY or 0

        if style == "modern" and position == "above" then
            -- Above health bar, inside the frame â€” pips stretch to fill health bar width
            -- Bottom of pips flush with top of health bar, top of pips flush with top of border
            bar:SetParent(frames.player)
            local anchorFrame = frames.player.Health
            local pipH = bar._pipH or 3
            -- Resize frame/portrait BEFORE anchoring health bar so _xOffset is correct
            ResizeFrameForClassPower(pipH)
            local btbOff = 0
            local btbPos2 = db.profile.player.btbPosition or "bottom"
            if btbPos2 == "top" and db.profile.player.bottomTextBar then
                btbOff = db.profile.player.bottomTextBarHeight or 16
            end
            local cpPush = pipH + btbOff
            anchorFrame:ClearAllPoints()
            PP.Point(anchorFrame, "TOPLEFT", frames.player, "TOPLEFT", anchorFrame._xOffset or 0, -cpPush)
            PP.Point(anchorFrame, "RIGHT", frames.player, "RIGHT", -(anchorFrame._rightInset or 0), 0)
            PP.Point(bar, "BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 0)
            PP.Point(bar, "BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 0)
            local fw = db.profile.player.frameWidth or 181
            if bar._repositionForWidth then
                bar._repositionForWidth(fw)
            end
            -- Show 1px bottom border matching frame border color
            if bar._bottomBdrFrame then
                local bdrC = db.profile.player.borderColor or { r = 0, g = 0, b = 0 }
                bar._bottomBdr:SetColorTexture(bdrC.r, bdrC.g, bdrC.b, 1)
                bar._bottomBdrFrame:Show()
            end
        elseif style == "modern" and position == "top" then
            -- "top" floats above the frame (like "bottom" floats below) â€” does NOT become part of the frame
            bar:SetParent(frames.player)
            ResizeFrameForClassPower(0)
            -- Reset health bar to normal position
            if frames.player.Health then
                local btbOff = 0
                local btbPos2 = db.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and db.profile.player.bottomTextBar then
                    btbOff = db.profile.player.bottomTextBarHeight or 16
                end
                frames.player.Health:ClearAllPoints()
                PP.Point(frames.player.Health, "TOPLEFT", frames.player, "TOPLEFT", frames.player.Health._xOffset or 0, -btbOff)
                PP.Point(frames.player.Health, "RIGHT", frames.player, "RIGHT", -(frames.player.Health._rightInset or 0), 0)
            end
            -- Center on health bar (ignores portrait)
            PP.Point(bar, "BOTTOM", frames.player.Health, "TOP", offsetX, offsetY)
            if bar._bottomBdrFrame then bar._bottomBdrFrame:Hide() end
        elseif not db.profile.player.lockClassPowerToFrame then
            -- Reset health bar to normal position
            if frames.player.Health then
                local btbOff = 0
                local btbPos2 = db.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and db.profile.player.bottomTextBar then
                    btbOff = db.profile.player.bottomTextBarHeight or 16
                end
                frames.player.Health:ClearAllPoints()
                PP.Point(frames.player.Health, "TOPLEFT", frames.player, "TOPLEFT", frames.player.Health._xOffset or 0, -btbOff)
                PP.Point(frames.player.Health, "RIGHT", frames.player, "RIGHT", -(frames.player.Health._rightInset or 0), 0)
            end
            bar:SetParent(UIParent)
            local pos = db.profile.positions.classPower
            if pos then
                PP.Point(bar, pos.point, UIParent, pos.point, pos.x, pos.y)
            else
                PP.Point(bar, "CENTER", UIParent, "CENTER", 0, -220)
            end
            ResizeFrameForClassPower(0)
            if bar._bottomBdrFrame then bar._bottomBdrFrame:Hide() end
        else
            -- Reset health bar to normal position
            if frames.player.Health then
                local btbOff = 0
                local btbPos2 = db.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and db.profile.player.bottomTextBar then
                    btbOff = db.profile.player.bottomTextBarHeight or 16
                end
                frames.player.Health:ClearAllPoints()
                PP.Point(frames.player.Health, "TOPLEFT", frames.player, "TOPLEFT", frames.player.Health._xOffset or 0, -btbOff)
                PP.Point(frames.player.Health, "RIGHT", frames.player, "RIGHT", -(frames.player.Health._rightInset or 0), 0)
            end
            -- "bottom" position â€” flush with bottom of frame; shifts below castbar when visible (unless user set Y offset)
            bar:SetParent(frames.player)
            if bar._bottomBdrFrame then bar._bottomBdrFrame:Hide() end
            local function AnchorBottom()
                bar:ClearAllPoints()
                local baseY = -1 + offsetY
                if offsetY == 0 then
                    local castbarBg = frames.player.Castbar and frames.player.Castbar:GetParent()
                    local castVisible = castbarBg and castbarBg:IsShown() and db.profile.player.showPlayerCastbar
                    if castVisible then
                        baseY = -1 - castbarBg:GetHeight()
                    end
                end
                PP.Point(bar, "TOP", frames.player, "BOTTOM", offsetX, baseY)
            end
            AnchorBottom()
            if not bar._castbarWatcher then
                bar._castbarWatcher = CreateFrame("Frame", nil, bar)
                bar._castbarWatcher:SetScript("OnUpdate", function()
                    local castbarBg = frames.player.Castbar and frames.player.Castbar:GetParent()
                    local nowVis = castbarBg and castbarBg:IsShown() and db.profile.player.showPlayerCastbar
                    if nowVis ~= bar._lastCastVis then
                        bar._lastCastVis = nowVis
                        AnchorBottom()
                    end
                end)
            end
            ResizeFrameForClassPower(0)
        end
        bar:SetFrameStrata(frames.player:GetFrameStrata())
        bar:SetFrameLevel(frames.player:GetFrameLevel() + 5)
        bar:Show()
    end

    if classPowerStyle ~= "none" and frames.player then
        if classPowerStyle == "blizzard" then
            if savedClassPowerBar then
                PositionClassPowerBar(savedClassPowerBar)
                frames._classPowerBar = savedClassPowerBar
            end
        else
            -- Modern custom style
            DestroyCustomClassPower()
            local custom = CreateCustomClassPower(frames.player, classPowerStyle)
            if custom then
                frames._customClassPower = custom
                frames._classPowerBar = custom
                PositionClassPowerBar(custom)
            end
        end
    end

    -- Live toggle for class power bar (no reload needed)
    -- Called with the style string: "none", "modern", or "blizzard"
    frames._toggleClassPower = function(style)
        style = style or db.profile.player.classPowerStyle or "none"
        -- Also keep showClassPowerBar in sync for backward compat
        db.profile.player.showClassPowerBar = (style ~= "none")
        db.profile.player.classPowerStyle = style

        -- Clean up existing
        if frames._customClassPower then
            DestroyCustomClassPower()
            frames._classPowerBar = nil
        elseif frames._classPowerBar then
            frames._classPowerBar:Hide()
            frames._classPowerBar:ClearAllPoints()
            frames._classPowerBar:SetParent(PlayerFrame or UIParent)
            if PlayerFrame then
                PlayerFrame.classPowerBar = frames._classPowerBar
            end
            frames._classPowerBar = nil
        end

        if style == "none" then
            -- Reset health bar to normal position
            if frames.player and frames.player.Health then
                local btbOff = 0
                local btbPos2 = db.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and db.profile.player.bottomTextBar then
                    btbOff = db.profile.player.bottomTextBarHeight or 16
                end
                frames.player.Health:ClearAllPoints()
                PP.Point(frames.player.Health, "TOPLEFT", frames.player, "TOPLEFT", frames.player.Health._xOffset or 0, -btbOff)
                PP.Point(frames.player.Health, "RIGHT", frames.player, "RIGHT", -(frames.player.Health._rightInset or 0), 0)
            end
            ResizeFrameForClassPower(0)
            return
        end

        if style == "blizzard" then
            if PlayerFrame and PlayerFrame.classPowerBar then
                local cpb = PlayerFrame.classPowerBar
                PlayerFrame.classPowerBar = nil
                cpb:SetParent(UIParent)
                frames._classPowerBar = cpb
            end
            if frames._classPowerBar and frames.player then
                PositionClassPowerBar(frames._classPowerBar)
            end
        else
            -- Modern
            local custom = CreateCustomClassPower(frames.player, style)
            if custom then
                frames._customClassPower = custom
                frames._classPowerBar = custom
                PositionClassPowerBar(custom)
            end
        end
    end

    oUF:SetActiveStyle("EllesmereTarget")
    frames.target = oUF:Spawn("target", "EllesmereUIUnitFrames_Target")
    ApplyFramePosition(frames.target, "target")
    ApplyFrameScale(frames.target, "target")
    SetupUnitMenu(frames.target, "target")
    if enabled.target == false then
        frames.target:Hide()
        frames.target:SetAttribute("unit", nil)
    end

    oUF:SetActiveStyle("EllesmereFocus")
    frames.focus = oUF:Spawn("focus", "EllesmereUIUnitFrames_Focus")
    ApplyFramePosition(frames.focus, "focus")
    ApplyFrameScale(frames.focus, "focus")
    SetupUnitMenu(frames.focus, "focus")
    if enabled.focus == false then
        frames.focus:Hide()
        frames.focus:SetAttribute("unit", nil)
    end

    oUF:SetActiveStyle("EllesmerePet")
    frames.pet = oUF:Spawn("pet", "EllesmereUIUnitFrames_Pet")
    ApplyFramePosition(frames.pet, "pet")
    SetupUnitMenu(frames.pet, "pet")
    if enabled.pet == false then
        frames.pet:Hide()
        frames.pet:SetAttribute("unit", nil)
    end

    oUF:SetActiveStyle("EllesmereTargetTarget")
    frames.targettarget = oUF:Spawn("targettarget", "EllesmereUIUnitFrames_TargetTarget")
    ApplyFramePosition(frames.targettarget, "targettarget")
    SetupUnitMenu(frames.targettarget, "targettarget")
    if enabled.targettarget == false then
        frames.targettarget:Hide()
        frames.targettarget:SetAttribute("unit", nil)
    end

    oUF:SetActiveStyle("EllesmereFocusTarget")
    frames.focustarget = oUF:Spawn("focustarget", "EllesmereUIUnitFrames_FocusTarget")
    ApplyFramePosition(frames.focustarget, "focustarget")
    SetupUnitMenu(frames.focustarget, "focustarget")
    if enabled.focustarget == false then
        frames.focustarget:Hide()
        frames.focustarget:SetAttribute("unit", nil)
    end

    oUF:SetActiveStyle("EllesmereBoss")
    local bossPos = db.profile.positions.boss
    local spacing = db.profile.bossSpacing or 60
    for i = 1, 5 do
        local bossUnit = "boss" .. i
        local bossFrame = oUF:Spawn(bossUnit, "EllesmereUIUnitFrames_Boss" .. i)
        frames[bossUnit] = bossFrame

        if bossPos then
            bossFrame:ClearAllPoints()
            bossFrame:SetPoint(bossPos.point, UIParent, bossPos.point, bossPos.x, bossPos.y - ((i - 1) * spacing))
        end

        SetupUnitMenu(bossFrame, bossUnit)

        if enabled.boss == false then
            bossFrame:Hide()
            bossFrame:SetAttribute("unit", nil)
        end
    end

    for i = 1, 5 do
        local blizzBoss = _G["Boss" .. i .. "TargetFrame"]
        if blizzBoss then
            blizzBoss:UnregisterAllEvents()
            blizzBoss:Hide()
        end
    end

    -- Disable oUF elements for frames where features are initially off.
    -- Portrait backdrop is already hidden by style functions, but oUF
    -- auto-enables the element at spawn time since frame.Portrait is always set.
    for unit, frame in pairs(frames) do
        if type(frame) ~= "table" or not frame.Portrait then -- skip non-frame entries
        elseif frame.Portrait.backdrop then
            local settings = GetSettingsForUnit(unit)
            if settings.showPortrait == false or (db.profile.portraitStyle or "attached") == "none" then
                if frame:IsElementEnabled("Portrait") then
                    frame:DisableElement("Portrait")
                end
            elseif settings.portraitMode == "class" and unit == "player" then
                -- Class theme is a static texture -- disable oUF Portrait element (player only)
                if frame:IsElementEnabled("Portrait") then
                    frame:DisableElement("Portrait")
                end
            end
        end
    end

    -- Player absorbs: disable oUF element if not wanted (bar is always created)
    if frames.player and frames.player.HealthPrediction then
        if not db.profile.player.showPlayerAbsorb then
            if frames.player:IsElementEnabled("HealthPrediction") then
                frames.player:DisableElement("HealthPrediction")
            end
            if frames.player.HealthPrediction.damageAbsorb then
                frames.player.HealthPrediction.damageAbsorb:Hide()
            end
        end
    end

    -- Player buffs: disable oUF element if not wanted (frame is always created)
    if frames.player and frames.player.Buffs then
        if not db.profile.player.showBuffs then
            if frames.player:IsElementEnabled("Buffs") then
                frames.player:DisableElement("Buffs")
            end
            frames.player.Buffs:Hide()
        end
    end

    -- Player castbar: disable oUF element if not wanted (always created now)
    if frames.player and frames.player.Castbar then
        if not db.profile.player.showPlayerCastbar then
            if frames.player:IsElementEnabled("Castbar") then
                frames.player:DisableElement("Castbar")
            end
            frames.player.Castbar:Hide()
            local castbarBg = frames.player.Castbar:GetParent()
            if castbarBg then castbarBg:Hide() end
        elseif db.profile.player.showPlayerCastIcon == false and frames.player.Castbar._iconFrame then
            frames.player.Castbar._iconFrame:Hide()
        end
    end

    -- Target castbar: disable oUF element if not wanted
    if frames.target and frames.target.Castbar then
        if db.profile.target.showCastbar == false then
            if frames.target:IsElementEnabled("Castbar") then
                frames.target:DisableElement("Castbar")
            end
            frames.target.Castbar:Hide()
            local castbarBg = frames.target.Castbar:GetParent()
            if castbarBg then castbarBg:Hide() end
        elseif db.profile.target.showCastIcon == false and frames.target.Castbar._iconFrame then
            frames.target.Castbar._iconFrame:Hide()
        end
    end

    -- Focus castbar: disable oUF element if not wanted
    if frames.focus and frames.focus.Castbar then
        if db.profile.focus.showCastbar == false then
            if frames.focus:IsElementEnabled("Castbar") then
                frames.focus:DisableElement("Castbar")
            end
            frames.focus.Castbar:Hide()
            local castbarBg = frames.focus.Castbar:GetParent()
            if castbarBg then castbarBg:Hide() end
        elseif db.profile.focus.showCastIcon == false and frames.focus.Castbar._iconFrame then
            frames.focus.Castbar._iconFrame:Hide()
        end
    end

    ---------------------------------------------------------------------------
    --  Group visibility: show/hide player/target/focus based on group state
    ---------------------------------------------------------------------------
    local function UpdateFrameVisibility()
        if InCombatLockdown() then return end
        local enabled2 = db.profile.enabledFrames
        local inRaid = IsInRaid()
        local inParty = not inRaid and IsInGroup()
        local solo = not inRaid and not inParty
        for _, unitKey in ipairs({"player", "target", "focus"}) do
            local s = db.profile[unitKey]
            local frame = frames[unitKey]
            if frame and enabled2[unitKey] ~= false and s then
                local shouldShow = (inRaid and (s.showInRaid ~= false))
                    or (inParty and (s.showInParty ~= false))
                    or (solo and (s.showSolo ~= false))
                if shouldShow then
                    if not frame:IsShown() and UnitExists(unitKey) then
                        frame:SetAttribute("unit", unitKey)
                        -- Re-enable oUF elements that were disabled on hide.
                        -- Castbar is handled separately below to respect the
                        -- user's show/hide setting — never blindly re-enable it.
                        for _, elem in ipairs({"Health", "Power", "Portrait", "Buffs", "Debuffs", "HealthPrediction"}) do
                            if frame[elem] and not frame:IsElementEnabled(elem) then
                                frame:EnableElement(elem)
                            end
                        end
                        -- Restore castbar state based on saved setting
                        if frame.Castbar then
                            local wantsCastbar
                            if unitKey == "player" then
                                wantsCastbar = s.showPlayerCastbar
                            else
                                wantsCastbar = s.showCastbar ~= false
                            end
                            if wantsCastbar then
                                if not frame:IsElementEnabled("Castbar") then
                                    frame:EnableElement("Castbar")
                                end
                            else
                                if frame:IsElementEnabled("Castbar") then
                                    frame:DisableElement("Castbar")
                                end
                                frame.Castbar:Hide()
                                local castbarBg = frame.Castbar:GetParent()
                                if castbarBg then castbarBg:Hide() end
                            end
                        end
                        frame:Show()
                        frame:UpdateAllElements("GroupVisibility")
                    end
                else
                    if frame:IsShown() then
                        -- Disable oUF elements before hiding to prevent a
                        -- single-frame flash when the unit attribute is cleared
                        for _, elem in ipairs({"Health", "Power", "Portrait", "Castbar", "Buffs", "Debuffs", "HealthPrediction"}) do
                            if frame[elem] and frame:IsElementEnabled(elem) then
                                frame:DisableElement(elem)
                            end
                        end
                        frame:Hide()
                        frame:SetAttribute("unit", nil)
                    end
                end
            end
        end
    end
    ns.UpdateFrameVisibility = UpdateFrameVisibility

    local visFrame = CreateFrame("Frame")
    visFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    visFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    visFrame:SetScript("OnEvent", UpdateFrameVisibility)
    UpdateFrameVisibility()

    ---------------------------------------------------------------------------
    --  Portrait border color: update when target/focus unit changes
    --  so "class color" mode reflects the new unit's color.
    ---------------------------------------------------------------------------
    local portraitBorderUpdater = CreateFrame("Frame")
    portraitBorderUpdater:RegisterEvent("PLAYER_TARGET_CHANGED")
    portraitBorderUpdater:RegisterEvent("PLAYER_FOCUS_CHANGED")
    portraitBorderUpdater:SetScript("OnEvent", function(_, event)
        local unitKey = (event == "PLAYER_TARGET_CHANGED") and "target" or "focus"
        local frame = frames[unitKey]
        if not frame or not frame.Portrait then return end
        local backdrop = frame.Portrait.backdrop
        if not backdrop then return end
        local uSettings = db.profile[unitKey]
        if uSettings and uSettings.detachedPortraitClassColor then
            ApplyDetachedPortraitShape(backdrop, uSettings, unitKey)
        end
    end)
end


function SetupOptionsPanel()
    ns.db = db
    ns.frames = frames
    ns.ApplyFramePosition = ApplyFramePosition
    ns.ApplyFrameScale = ApplyFrameScale
    ns.SnapScaleToPixel = SnapScaleToPixel
    ns.GetFrameDimensions = GetFrameDimensions
    local reloadPending = false
    local reloadThrottle = CreateFrame("Frame")
    reloadThrottle:Hide()
    reloadThrottle:SetScript("OnUpdate", function(self)
        self:Hide()
        reloadPending = false
        ReloadFrames()
    end)
    ns.ReloadFrames = function()
        if not reloadPending then
            reloadPending = true
            reloadThrottle:Show()
        end
    end
    ns.ResolveFontPath = ResolveFontPath
    ns.fontPaths = fontPaths

    -- Trigger the EllesmereUI options module registration now that ns.db is ready
    if ns._InitEUIModule then
        ns._InitEUIModule()
    end

    ---------------------------------------------------------------------------
    --  Register unit frame elements with Unlock Mode
    ---------------------------------------------------------------------------
    if EllesmereUI and EllesmereUI.RegisterUnlockElements then
        local UNIT_LABELS = {
            player = "Player", target = "Target", focus = "Focus",
            pet = "Pet", targettarget = "Target of Target",
            focustarget = "Focus Target", boss = "Boss Frames",
            classPower = "Class Resource",
        }
        local elements = {}
        local orderBase = 100  -- unit frames sort after action bars

        local function MakeUFElement(key, order)
            return {
                key = key,
                label = UNIT_LABELS[key] or key,
                group = "Unit Frames",
                order = orderBase + order,
                getFrame = function(k)
                    if k == "boss" then return frames["boss1"] end
                    if k == "playerCastbar" then
                        if frames.player and frames.player.Castbar then
                            return frames.player.Castbar:GetParent()
                        end
                        return nil
                    end
                    if k == "classPower" then return frames._classPowerBar end
                    return frames[k]
                end,
                getSize = function(k)
                    if k == "playerCastbar" then
                        local pS = GetSettingsForUnit("player")
                        local ppPos2 = pS.powerPosition or "below"
                        local ppIsAtt2 = (ppPos2 == "below" or ppPos2 == "above")
                        local ptH = pS.healthHeight + (ppIsAtt2 and pS.powerHeight or 0)
                        local cbW = (pS.showPortrait ~= false and (db.profile.portraitStyle or "attached") == "attached") and (ptH + pS.frameWidth) or pS.frameWidth
                        local cbH = db.profile.player.playerCastbarHeight
                        if not cbH or cbH <= 0 then cbH = 14 end
                        return cbW, cbH
                    end
                    if k == "classPower" then
                        if frames._classPowerBar then
                            local w = frames._classPowerBar:GetWidth()
                            local h = frames._classPowerBar:GetHeight()
                            if w < 10 then w = 120 end
                            if h < 5 then h = 14 end
                            return w, h
                        end
                        return 120, 14
                    end
                    if k == "boss" then return GetFrameDimensions("boss1") end
                    return GetFrameDimensions(k)
                end,
                loadPosition = function(k)
                    local pos = db.profile.positions[k]
                    if not pos then return nil end
                    return { point = pos.point, relPoint = pos.point, x = pos.x, y = pos.y, scale = pos.scale }
                end,
                getScale = function(k)
                    local pos = db.profile.positions[k]
                    return pos and pos.scale or 1.0
                end,
                savePosition = function(k, point, relPoint, x, y, scale)
                    db.profile.positions[k] = { point = point, x = x, y = y, scale = scale }
                    -- Write scale back to the per-unit settings so ApplyFrameScale
                    -- on reload uses the unlock mode value instead of overwriting it.
                    if scale then
                        local unitKey = (k == "boss") and "boss"
                                     or (k == "classPower") and nil
                                     or k
                        if unitKey and db.profile[unitKey] then
                            db.profile[unitKey].frameScale = math.floor(scale * 100 + 0.5)
                        end
                    end
                    -- Apply to live frame immediately
                    local fr
                    if k == "boss" then
                        local spacing = db.profile.bossSpacing or 60
                        for i = 1, 5 do
                            if frames["boss" .. i] then
                                if scale then pcall(function() frames["boss" .. i]:SetScale(scale) end) end
                                frames["boss" .. i]:ClearAllPoints()
                                frames["boss" .. i]:SetPoint(point, UIParent, point, x, y - ((i - 1) * spacing))
                            end
                        end
                    elseif k == "classPower" then
                        if frames._classPowerBar then
                            if scale then pcall(function() frames._classPowerBar:SetScale(scale) end) end
                            frames._classPowerBar:ClearAllPoints()
                            frames._classPowerBar:SetPoint(point, UIParent, point, x, y)
                        end
                    else
                        fr = frames[k]
                        if fr then
                            if scale then pcall(function() fr:SetScale(scale) end) end
                            fr:ClearAllPoints()
                            fr:SetPoint(point, UIParent, point, x, y)
                        end
                    end
                end,
                clearPosition = function(k)
                    db.profile.positions[k] = nil
                end,
                applyPosition = function(k)
                    local pos = db.profile.positions[k]
                    if not pos then return end
                    local sc = pos.scale
                    if k == "boss" then
                        local spacing = db.profile.bossSpacing or 60
                        for i = 1, 5 do
                            if frames["boss" .. i] then
                                if sc then pcall(function() frames["boss" .. i]:SetScale(sc) end) end
                                frames["boss" .. i]:ClearAllPoints()
                                frames["boss" .. i]:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y - ((i - 1) * spacing))
                            end
                        end
                    elseif k == "classPower" then
                        if frames._classPowerBar then
                            if sc then pcall(function() frames._classPowerBar:SetScale(sc) end) end
                            frames._classPowerBar:ClearAllPoints()
                            frames._classPowerBar:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
                        end
                    else
                        local fr = frames[k]
                        if fr then
                            if sc then pcall(function() fr:SetScale(sc) end) end
                            fr:ClearAllPoints()
                            fr:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
                        end
                    end
                end,
            }
        end

        -- Core unit frames
        elements[#elements + 1] = MakeUFElement("player", 1)
        elements[#elements + 1] = MakeUFElement("target", 2)
        elements[#elements + 1] = MakeUFElement("focus", 3)
        elements[#elements + 1] = MakeUFElement("pet", 4)
        elements[#elements + 1] = MakeUFElement("targettarget", 5)
        elements[#elements + 1] = MakeUFElement("focustarget", 6)
        elements[#elements + 1] = MakeUFElement("boss", 7)

        -- Conditional elements
        if db.profile.player.showClassPowerBar and not db.profile.player.lockClassPowerToFrame then
            elements[#elements + 1] = MakeUFElement("classPower", 9)
        end

        EllesmereUI:RegisterUnlockElements(elements)
    end
end

StaticPopupDialogs["ELLESMERE_RELOAD_UI"] = {
    text = "Ellesmere Unit Frames setting changed. Reload UI to apply?",
    button1 = "Reload",
    button2 = "Later",
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["ELLESMERE_RESET_DEFAULTS"] = {
    text = "Reset all Ellesmere Unit Frames settings to defaults? This cannot be undone.",
    button1 = "Reset & Reload",
    button2 = "Cancel",
    OnAccept = function()
        if db then db:ResetProfile() end
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self)
        self:SetFrameStrata("TOOLTIP")
    end,
}

-- 3D portrait warning popup is now handled by EllesmereUI:ShowConfirmPopup
-- in EUI_UnitFrames_Options.lua (portrait mode dropdown handler).

local EllesmereUF = EllesmereUI.Lite.NewAddon("EllesmereUIUnitFrames")

-- Migrate old shared playerTarget table into separate player/target sub-tables
local function MigratePlayerTarget()
    local p = db.profile
    -- Use a dedicated flag so this migration runs exactly once.
    -- The old guard (checking frameWidth != default) was unreliable: users
    -- with frameWidth at the default value would re-run migration every load,
    -- overwriting their saved healthHeight/powerHeight with the old defaults.
    if p._playerTargetMigrated then return end
    -- Skip if the old table doesn't exist (new installs)
    local old = p.playerTarget
    if not old then
        p._playerTargetMigrated = true
        return
    end
    local oldDef = defaults.profile.playerTarget

    -- Copy shared values into player table
    p.player = p.player or {}
    p.player.frameWidth = old.frameWidth or oldDef.frameWidth
    p.player.healthHeight = old.healthHeight or oldDef.healthHeight
    p.player.powerHeight = old.powerHeight or oldDef.powerHeight
    p.player.healthDisplay = old.healthDisplay or oldDef.healthDisplay
    p.player.showPlayerAbsorb = old.showPlayerAbsorb or false
    p.player.showPlayerCastbar = old.showPlayerCastbar or false
    p.player.showClassPowerBar = old.showClassPowerBar or false
    p.player.playerCastbarX = old.playerCastbarX or 0
    p.player.playerCastbarY = old.playerCastbarY or 0
    p.player.playerCastbarWidth = old.playerCastbarWidth or 0
    p.player.playerCastbarHeight = old.playerCastbarHeight or 0
    p.player.classPowerBarX = old.classPowerBarX or 0
    p.player.classPowerBarY = old.classPowerBarY or 0
    p.player.showPortrait = p.showPortrait  -- migrate from root level

    -- Copy shared values into target table
    p.target = p.target or {}
    p.target.frameWidth = old.frameWidth or oldDef.frameWidth
    p.target.healthHeight = old.healthHeight or oldDef.healthHeight
    p.target.powerHeight = old.powerHeight or oldDef.powerHeight
    p.target.castbarHeight = old.castbarHeight or oldDef.castbarHeight
    p.target.healthDisplay = old.healthDisplay or oldDef.healthDisplay
    p.target.showBuffs = old.showBuffs
    if p.target.showBuffs == nil then p.target.showBuffs = true end
    p.target.onlyPlayerDebuffs = old.onlyPlayerDebuffs or false
    p.target.showPortrait = p.showPortrait  -- migrate from root level

    -- Mark as done so this never runs again
    p._playerTargetMigrated = true
    -- Leave old playerTarget intact for backward compat
end

function EllesmereUF:OnInitialize()
    -- Bail out if user has disabled this addon in Global Settings
    if EllesmereUIDB and EllesmereUIDB.disabledAddons and EllesmereUIDB.disabledAddons[addonName] then
        self._userDisabled = true
        return
    end

    db = EllesmereUI.Lite.NewDB("EllesmereUIUnitFramesDB", defaults, true)
    MigratePlayerTarget()
    -- Migrate old use3DPortrait boolean to new portraitMode string (one-time)
    do
        local prof = db.profile
        if prof.use3DPortrait ~= nil then
            if prof.use3DPortrait == true then
                prof.portraitMode = "3d"
            elseif prof.use3DPortrait == false and not prof.portraitMode then
                prof.portraitMode = "2d"
            end
            prof.use3DPortrait = nil  -- clear so migration doesn't re-run
        end
    end

    -- Migrate global portraitMode / selectedFont / healthBarTexture
    -- into per-unit sub-tables.  Runs once: when the global key still exists.
    do
        local prof = db.profile
        local UNITS = { "player", "target", "focus", "boss", "pet", "totPet" }
        local globalPM   = prof.portraitMode
        local globalFont = prof.selectedFont
        local globalTex  = prof.healthBarTexture
        if globalPM ~= nil or globalFont ~= nil or globalTex ~= nil then
            for _, uKey in ipairs(UNITS) do
                local s = prof[uKey]
                if s then
                    -- Portrait mode: if unit had showPortrait=false, set to "none"
                    if s.portraitMode == nil then
                        if s.showPortrait == false then
                            s.portraitMode = "none"
                        else
                            s.portraitMode = globalPM or "2d"
                        end
                    end
                    if s.selectedFont == nil then
                        s.selectedFont = globalFont or "Expressway"
                    end
                    if s.healthBarTexture == nil then
                        s.healthBarTexture = globalTex or "none"
                    end
                end
            end
            -- Clear globals so migration doesn't re-run
            prof.portraitMode = nil
            prof.selectedFont = nil
            prof.healthBarTexture = nil
            prof.healthBarTextureOpacity = nil
        end
    end
    ResolveFontPath()

    -- Migrate old texture keys (gradient, grunge, stripe) to "none"
    do
        local prof = db.profile
        local OLD_KEYS = { gradient = true, grunge = true, stripe = true }
        local UNITS = { "player", "target", "focus", "boss", "pet", "totPet" }
        for _, uKey in ipairs(UNITS) do
            local s = prof[uKey]
            if s and s.healthBarTexture and OLD_KEYS[s.healthBarTexture] then
                s.healthBarTexture = "none"
            end
        end
    end

    -- Migrate old namePosition/healthTextPosition to new leftTextContent/rightTextContent
    do
        local prof = db.profile
        local UNITS = { "player", "target", "focus" }
        for _, uKey in ipairs(UNITS) do
            local s = prof[uKey]
            if s and s.leftTextContent == nil and (s.namePosition or s.healthTextPosition) then
                local np = s.namePosition or "left"
                local hp = s.healthTextPosition or "right"
                local hd = s.healthDisplay or (uKey == "focus" and "perhp" or "both")
                -- Map old positions to new content model
                if np == "left" then
                    s.leftTextContent = "name"
                    s.rightTextContent = (hp == "right") and hd or "none"
                elseif np == "right" then
                    s.rightTextContent = "name"
                    s.leftTextContent = (hp == "left") and hd or "none"
                else -- np == "none"
                    s.leftTextContent = (hp == "left") and hd or "none"
                    s.rightTextContent = (hp == "right") and hd or "none"
                end
                -- Migrate textSize to per-side sizes
                local ts = s.textSize or 12
                if s.leftTextSize == nil then s.leftTextSize = ts end
                if s.rightTextSize == nil then s.rightTextSize = ts end
                if s.leftTextX == nil then s.leftTextX = 0 end
                if s.leftTextY == nil then s.leftTextY = 0 end
                if s.rightTextX == nil then s.rightTextX = 0 end
                if s.rightTextY == nil then s.rightTextY = 0 end
            end
        end
    end

    -- Migrate old classPowerStyle values (bars/circles Ã¢â€ â€™ modern) and
    -- sync showClassPowerBar with classPowerStyle
    do
        local p = db and db.profile
        if p and p.player then
            local s = p.player
            if s.classPowerStyle == "bars" or s.classPowerStyle == "circles" then
                s.classPowerStyle = "modern"
            end
            -- If showClassPowerBar was true but classPowerStyle is still default "none",
            -- set it to "blizzard" to preserve old behavior
            if s.showClassPowerBar and (s.classPowerStyle == "none" or s.classPowerStyle == nil) then
                s.classPowerStyle = "blizzard"
            end
            -- Sync: if classPowerStyle is set to something other than none, ensure showClassPowerBar is true
            if s.classPowerStyle and s.classPowerStyle ~= "none" then
                s.showClassPowerBar = true
            end
        end
    end

    -- Migrate portraitMode="none" Ã¢â€ â€™ portraitStyle="none" + portraitMode="2d"
    -- (portrait hide moved from per-unit portraitMode to global portraitStyle)
    do
        local prof = db.profile
        local UNITS = { "player", "target", "focus", "boss", "pet", "totPet" }
        local anyNone = false
        for _, uKey in ipairs(UNITS) do
            local s = prof[uKey]
            if s and s.portraitMode == "none" then
                anyNone = true
                break
            end
        end
        if anyNone then
            -- Set global portraitStyle to "none" (hides all portraits)
            prof.portraitStyle = "none"
            for _, uKey in ipairs(UNITS) do
                local s = prof[uKey]
                if s and s.portraitMode == "none" then
                    s.portraitMode = "2d"
                    s.showPortrait = false
                end
            end
        end
    end

    -- Minimap button (shared across all Ellesmere addons Ã¢â‚¬â€ first to load wins)
    -- Minimap button (handled by parent addon)
    if not _EllesmereUI_MinimapRegistered and EllesmereUI and EllesmereUI.CreateMinimapButton then
        EllesmereUI.CreateMinimapButton()
    end

    -- Blizzard options panel is registered centrally in EllesmereUI.lua
end

function EllesmereUF:OnEnable()
    if self._userDisabled then return end

    InitializeFrames()
    C_Timer.After(0, SetupOptionsPanel)
    C_Timer.After(0, function()
        if EllesmereUI and EllesmereUI.ApplyColorsToOUF then
            EllesmereUI.ApplyColorsToOUF()
        end
    end)

    -- Incompatible addon detection is handled globally by EllesmereUI
end
