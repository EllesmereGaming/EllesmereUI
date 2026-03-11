-------------------------------------------------------------------------------
--  EllesmereUIResourceBars.lua
--  Custom class resource, health, and mana bar display
--  Features: Health bar, primary resource bar (mana/rage/energy/etc),
--  secondary resource display (combo points, holy power, runes, etc),
--  smooth animations, combat fade, low-resource alerts, class-colored bars
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local ERB = EllesmereUI.Lite.NewAddon(ADDON_NAME)
ns.ERB = ERB

local PP = EllesmereUI.PP

local floor, ceil, abs, min, max = math.floor, math.ceil, math.abs, math.min, math.max
local format = string.format
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitClass = UnitClass
local GetSpecialization = GetSpecialization
local InCombatLockdown = InCombatLockdown
local GetShapeshiftFormID = GetShapeshiftFormID

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local RB_FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local function GetRBFont()
    if EllesmereUI and EllesmereUI.GetFontPath then
        return EllesmereUI.GetFontPath("resourceBars")
    end
    return RB_FONT_FALLBACK
end
local function GetRBOutline()
    return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or ""
end
local function GetRBUseShadow()
    return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow()
end
local function SetRBFont(fs, font, size)
    if not (fs and fs.SetFont) then return end
    local f = GetRBOutline()
    fs:SetFont(font, size, f)
    if f == "" then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1)
    else fs:SetShadowOffset(0, 0) end
end

-- PowerType enum values (Enum.PowerType)
local PT = {
    MANA        = 0,
    RAGE        = 1,
    FOCUS       = 2,
    ENERGY      = 3,
    COMBO       = 4,
    RUNES       = 5,
    RUNIC_POWER = 6,
    SOUL_SHARDS = 7,
    LUNAR_POWER = 8,  -- Astral Power (Balance Druid)
    HOLY_POWER  = 9,
    MAELSTROM   = 11,
    CHI         = 12,
    INSANITY    = 13,
    ARCANE      = 16, -- Arcane Charges
    FURY        = 17,
    PAIN        = 18, -- Demon Hunter (Vengeance)
    ESSENCE     = 19, -- Evoker
}


-------------------------------------------------------------------------------
--  Class/Spec resource mapping
-------------------------------------------------------------------------------
local CLASS_COLORS = {
    WARRIOR     = { 0.78, 0.61, 0.43 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    ROGUE       = { 1.00, 0.96, 0.41 },
    PRIEST      = { 1.00, 1.00, 1.00 },
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN      = { 0.00, 0.44, 0.87 },
    MAGE        = { 0.25, 0.78, 0.92 },
    WARLOCK     = { 0.53, 0.53, 0.93 },
    MONK        = { 0.00, 1.00, 0.60 },
    DRUID       = { 1.00, 0.49, 0.04 },
    DEMONHUNTER = { 0.64, 0.19, 0.79 },
    EVOKER      = { 0.20, 0.58, 0.50 },
}

local POWER_COLORS = {
    [PT.MANA]        = { 0.00, 0.55, 1.00 },
    [PT.RAGE]        = { 0.90, 0.15, 0.15 },
    [PT.FOCUS]       = { 0.77, 0.53, 0.24 },
    [PT.ENERGY]      = { 1.00, 0.96, 0.41 },
    [PT.RUNIC_POWER] = { 0.00, 0.82, 1.00 },
    [PT.LUNAR_POWER] = { 0.30, 0.52, 0.90 },
    [PT.HOLY_POWER]  = { 0.95, 0.90, 0.60 },
    [PT.MAELSTROM]   = { 0.00, 0.50, 1.00 },
    [PT.CHI]         = { 0.71, 1.00, 0.92 },
    [PT.INSANITY]    = { 0.40, 0.00, 0.80 },
    [PT.ARCANE]      = { 0.10, 0.69, 0.97 },
    [PT.FURY]        = { 0.79, 0.26, 0.99 },
    [PT.PAIN]        = { 1.00, 0.61, 0.00 },
    [PT.ESSENCE]     = { 0.20, 0.58, 0.50 },
    [PT.SOUL_SHARDS] = { 0.58, 0.51, 0.79 },
    [PT.COMBO]       = { 1.00, 0.96, 0.41 },
    [PT.RUNES]       = { 0.77, 0.12, 0.23 },
    -- Custom aura-tracked resource colors
    ["SOUL_FRAGMENTS"]   = { 0.64, 0.19, 0.79 },
    ["SOUL_FRAGMENTS_VENGEANCE"] = { 0.34, 0.06, 0.46 },
    ["SOUL_FRAGMENTS_DEVOURER"]  = { 0.64, 0.19, 0.79 },
    ["MAELSTROM_WEAPON"] = { 0.00, 0.44, 0.87 },
    ["MAELSTROM_BAR"]    = { 0.00, 0.50, 1.00 },
    ["INSANITY_BAR"]     = { 0.40, 0.00, 0.80 },
    ["FOCUS_BAR"]        = { 0.77, 0.53, 0.24 },
    ["TIP_OF_THE_SPEAR"] = { 0.67, 0.83, 0.45 },
    ["WHIRLWIND_STACKS"] = { 0.78, 0.61, 0.43 },
    ["BREWMASTER_STAGGER"] = { 0.52, 1.00, 0.52 },  -- green (light stagger default)
}

-- Dark theme colors (matches unit frames)
local DARK_FILL_R, DARK_FILL_G, DARK_FILL_B, DARK_FILL_A = 0x11/255, 0x11/255, 0x11/255, 0.90
local DARK_BG_R, DARK_BG_G, DARK_BG_B, DARK_BG_A = 0x4f/255, 0x4f/255, 0x4f/255, 1


local PRIMARY_CLASS_MAP = {
    WARRIOR     = PT.RAGE,
    PALADIN     = PT.MANA,
    HUNTER      = PT.FOCUS,
    ROGUE       = PT.ENERGY,
    PRIEST      = PT.MANA,
    DEATHKNIGHT = PT.RUNIC_POWER,
    SHAMAN      = PT.MANA,
    MAGE        = PT.MANA,
    WARLOCK     = PT.MANA,
    MONK        = PT.ENERGY,
    DEMONHUNTER = PT.FURY,
    EVOKER      = PT.MANA,
}

local function GetPrimaryPowerType()
    local _, classFile = UnitClass("player")
    local spec = GetSpecialization()
    local form = GetShapeshiftFormID()

    -- Druid form handling
    if classFile == "DRUID" then
        if form == 1 then return PT.ENERGY end
        if form == 5 then return PT.RAGE end
        if spec == 1 then return PT.LUNAR_POWER end
        return PT.MANA
    end

    if classFile == "SHAMAN" then
        -- All shaman specs use Mana as primary; Maelstrom is a class resource
        -- displayed as a secondary bar (Elemental) or pips (Enhancement).
    end
    if classFile == "PRIEST" then
        -- All priest specs use Mana as primary; Insanity is a class resource
        -- displayed as a secondary bar (Shadow).
    end
    if classFile == "HUNTER" then
        -- BM and MM: Focus is displayed as a class resource bar (secondary),
        -- not the power bar. Survival keeps Focus as the power bar.
        if spec == 1 or spec == 2 then return nil end
    end
    if classFile == "MONK" then
        if spec == 1 then return PT.ENERGY end  -- Brewmaster
        if spec == 2 then return PT.MANA end    -- Mistweaver
        if spec == 3 then return PT.ENERGY end  -- Windwalker
    end
    if classFile == "DEMONHUNTER" then
        return PT.FURY
    end

    return PRIMARY_CLASS_MAP[classFile] or PT.MANA
end

local function GetSecondaryResource()
    local _, classFile = UnitClass("player")
    local spec = GetSpecialization()
    local form = GetShapeshiftFormID()

    if classFile == "PALADIN" then
        local mx = UnitPowerMax("player", PT.HOLY_POWER)
        return { power = PT.HOLY_POWER, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points" }
    elseif classFile == "ROGUE" then
        local mx = UnitPowerMax("player", PT.COMBO)
        return { power = PT.COMBO, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points" }
    elseif classFile == "DRUID" and form == 1 then
        local mx = UnitPowerMax("player", PT.COMBO)
        return { power = PT.COMBO, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points" }
    elseif classFile == "MONK" and (spec == 3) then
        local mx = UnitPowerMax("player", PT.CHI)
        return { power = PT.CHI, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points" }
    elseif classFile == "MONK" and (spec == 1) then
        -- Brewmaster: stagger as a bar (max = player max health)
        local mx = UnitHealthMax("player") or 1
        if issecretvalue and issecretvalue(mx) then mx = 1 end
        if mx <= 0 then mx = 1 end
        return { power = "BREWMASTER_STAGGER", max = mx, type = "bar" }
    elseif classFile == "WARLOCK" then
        local mx = UnitPowerMax("player", PT.SOUL_SHARDS)
        return { power = PT.SOUL_SHARDS, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points" }
    elseif classFile == "DEATHKNIGHT" then
        return { power = PT.RUNES, max = 6, type = "runes" }
    elseif classFile == "EVOKER" then
        local mx = UnitPowerMax("player", PT.ESSENCE)
        return { power = PT.ESSENCE, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points" }
    elseif classFile == "MAGE" and spec == 1 then
        local mx = UnitPowerMax("player", PT.ARCANE)
        return { power = PT.ARCANE, max = (not issecretvalue or not issecretvalue(mx)) and mx or 4, type = "points" }
    elseif classFile == "DEMONHUNTER" then
        -- Resolve specID: 581=Vengeance, 1480=Devourer, 577=Havoc
        local specID = spec and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(spec)
        if specID == 581 then -- Vengeance: 6 soul fragment pips
            return { power = "SOUL_FRAGMENTS_VENGEANCE", max = 6, type = "custom" }
        elseif specID == 1480 then -- Devourer: soul fragments as a bar (35-50 max)
            local maxC = 50
            if EllesmereUI and EllesmereUI.GetSoulFragments then
                local _, m = EllesmereUI.GetSoulFragments()
                if m and m > 0 then maxC = m end
            end
            return { power = "SOUL_FRAGMENTS_DEVOURER", max = maxC, type = "bar" }
        end
        -- Havoc (577) has no secondary resource.
        return nil
    elseif classFile == "SHAMAN" and spec == 1 then
        -- Elemental: Maelstrom as a bar (like Devourer soul fragments)
        local mx = UnitPowerMax("player", PT.MAELSTROM)
        if issecretvalue and issecretvalue(mx) then mx = 100 end
        if not mx or mx <= 0 then mx = 100 end
        return { power = "MAELSTROM_BAR", max = mx, type = "bar" }
    elseif classFile == "PRIEST" and spec == 3 then
        -- Shadow: Insanity as a bar (like Elemental maelstrom)
        local mx = UnitPowerMax("player", PT.INSANITY)
        if issecretvalue and issecretvalue(mx) then mx = 100 end
        if not mx or mx <= 0 then mx = 100 end
        return { power = "INSANITY_BAR", max = mx, type = "bar" }
    elseif classFile == "SHAMAN" and spec == 2 then
        -- Base max 5, or 10 with Raging Maelstrom talent; BuildBars
        -- overrides from GetMaelstromWeapon() at runtime.
        return { power = "MAELSTROM_WEAPON", max = 5, type = "custom" }
    elseif classFile == "HUNTER" and spec == 3 then
        return { power = "TIP_OF_THE_SPEAR", max = 3, type = "custom" }
    elseif classFile == "HUNTER" and (spec == 1 or spec == 2) then
        -- BM and MM: Focus as a class resource bar
        local mx = UnitPowerMax("player", PT.FOCUS)
        if issecretvalue and issecretvalue(mx) then mx = 100 end
        if not mx or mx <= 0 then mx = 100 end
        return { power = "FOCUS_BAR", max = mx, type = "bar" }
    elseif classFile == "WARRIOR" and spec == 2 then
        return { power = "WHIRLWIND_STACKS", max = 4, type = "custom" }
    end

    return nil
end

-------------------------------------------------------------------------------
--  ColorCurve helper for secret-value-safe bar threshold coloring
--  Builds a two-point step curve: base color below threshold, threshold color
--  at or above. Pass the curve to UnitPowerPercent as the 4th arg � WoW
--  evaluates the secret value on the C side and returns a Color object.
-------------------------------------------------------------------------------
local _barColorCurve = nil
local _barColorCurveHash = nil

local function GetBarThresholdCurve(baseR, baseG, baseB, threshR, threshG, threshB, threshPct)
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end
    local hash = format("%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.1f", baseR, baseG, baseB, threshR, threshG, threshB, threshPct)
    if _barColorCurveHash == hash then return _barColorCurve end
    local curve = C_CurveUtil.CreateColorCurve()
    local t = math.max(0, math.min(1, threshPct / 100))
    local EPSILON = 0.0001
    curve:AddPoint(0.0, CreateColor(baseR, baseG, baseB, 1))
    if t > EPSILON then
        curve:AddPoint(t - EPSILON, CreateColor(baseR, baseG, baseB, 1))
    end
    curve:AddPoint(t,   CreateColor(threshR, threshG, threshB, 1))
    curve:AddPoint(1.0, CreateColor(threshR, threshG, threshB, 1))
    _barColorCurve = curve
    _barColorCurveHash = hash
    return curve
end

-- per-element scale, border, colors, text, alerts
-------------------------------------------------------------------------------
local _, playerClassFile = UnitClass("player")
local playerCC = CLASS_COLORS[playerClassFile] or { 0.15, 0.75, 0.30 }
local playerPowerCC = POWER_COLORS[PRIMARY_CLASS_MAP[playerClassFile]] or { 0, 0.55, 1 }

local DEFAULTS = {
    profile = {
        health = {
            enabled     = false,
            width       = 214,
            height      = 16,
            scale       = 1.0,
            borderSize  = 0,
            borderR     = 0, borderG = 0, borderB = 0, borderA = 1,
            darkTheme   = false,
            customColored = false,
            fillR       = playerCC[1], fillG = playerCC[2], fillB = playerCC[3], fillA = 1,
            bgR         = 0x11/255, bgG = 0x11/255, bgB = 0x11/255, bgA = 0.75,
            textFormat  = "none",  -- "none","both","curhpshort","perhp"
            textSize    = 11,
            textXOffset = 0,
            textYOffset = 0,
            offsetX     = 0,
            offsetY     = -64,
            barAlpha    = 1.0,
            visibility  = "always",  -- "always","combat","target"
            orientation = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL_UP","VERTICAL_DOWN"
            thresholdEnabled = false,
            thresholdPct     = 30,
            thresholdR = 1.0, thresholdG = 0.2, thresholdB = 0.2, thresholdA = 1,
        },
        primary = {
            enabled     = true,
            width       = 214,
            height      = 14,
            scale       = 1.0,
            borderSize  = 1,
            borderR     = 0, borderG = 0, borderB = 0, borderA = 1,
            darkTheme   = false,
            customColored = false,
            fillR       = playerPowerCC[1], fillG = playerPowerCC[2], fillB = playerPowerCC[3], fillA = 1,
            bgR         = 0x11/255, bgG = 0x11/255, bgB = 0x11/255, bgA = 0.75,
            textFormat  = "perpp",  -- "none","smart","curpp","perpp","both"
            showPercent = true,
            textSize    = 10,
            textXOffset = 0,
            textYOffset = 0,
            offsetX     = 0,
            offsetY     = -54,
            barAlpha    = 1.0,
            visibility  = "always",  -- "always","combat","target"
            orientation = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL_UP","VERTICAL_DOWN"
            thresholdEnabled = false,
            thresholdPct     = 30,
            thresholdR = 1.0, thresholdG = 0.2, thresholdB = 0.2, thresholdA = 1,
        },
        secondary = {
            enabled     = true,
            scale       = 1.0,
            pipWidth    = 214,
            pipHeight   = 20,
            pipSpacing  = 1,
            pipOrientation = "HORIZONTAL",
            borderSize  = 1,
            borderR     = 0, borderG = 0, borderB = 0, borderA = 1,
            darkTheme   = false,
            classColored = true,
            fillR       = 0.95, fillG = 0.90, fillB = 0.60, fillA = 1,
            bgR         = 1, bgG = 1, bgB = 1, bgA = 0.1,
            showText    = true,
            textSize    = 11,
            textXOffset = 0,
            textYOffset = 0,
            barBgR      = 0, barBgG = 0, barBgB = 0, barBgA = 0.5,
            barAlpha    = 1.0,
            thresholdEnabled = false,
            thresholdCount   = 3,
            thresholdPartialOnly = false,
            thresholdR = 0x0c/255, thresholdG = 0xd2/255, thresholdB = 0x9d/255, thresholdA = 1,
            chargedR = 0.44, chargedG = 0.77, chargedB = 1.00, chargedA = 1,
            visibility  = "always",  -- "always","combat","target"
            oocAlpha    = 1.0,
            offsetX     = 0,
            offsetY     = -38,
        },
        castBar = {
            enabled       = true,
            showIcon      = true,
            width         = 220,
            height        = 20,
            anchorX       = 0,
            anchorY       = -54,
            fillR         = playerCC[1], fillG = playerCC[2], fillB = playerCC[3], fillA = 1,
            gradientEnabled = false,
            gradientR     = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
            gradientDir   = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL"
            texture       = "none",
            showSpark     = true,
            borderSize    = 1,
            borderR       = 0, borderG = 0, borderB = 0, borderA = 1,
            bgR           = 0, bgG = 0, bgB = 0, bgA = 0.7,
            showTimer     = true,
            timerSize     = 11,
            timerX        = 0,
            timerY        = 0,
            showSpellText = true,
            spellTextSize = 11,
            spellTextX    = 0,
            spellTextY    = 0,
            scale         = 1.0,
            unlockPos     = nil,
        },
        general = {
            anchorX     = 0,
            anchorY     = -100,
            unlocked    = false,
            orientation = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL_UP","VERTICAL_DOWN"
            barTexture  = "none",
        },
    },
}


-------------------------------------------------------------------------------
--  State
-------------------------------------------------------------------------------
local mainFrame
local healthBar
local primaryBar
local secondaryFrame
local secondaryBar  -- bar-style secondary (e.g. Devourer soul fragments, Elemental maelstrom)
local castBarFrame
local isInCombat = false
local currentAlpha = 1
local targetAlpha = 1
local cachedClass
local cachedPrimary
local cachedSecondary

-- Forward declarations
local UpdateCastBar
local BuildCastBar
local OnCastStart, OnChannelStart, OnCastStop, OnEmpowerStart, OnEmpowerUpdate

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function GetAccent()
    local eg = EllesmereUI and EllesmereUI.ELLESMERE_GREEN
    if eg then return eg.r, eg.g, eg.b end
    return 12/255, 210/255, 157/255
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

local function FormatNumber(n)
    if n >= 1e6 then return format("%.1fM", n / 1e6) end
    if n >= 1e3 then return format("%.1fK", n / 1e3) end
    return tostring(floor(n))
end

local function IsVerticalOrientation(ori)
    return ori == "VERTICAL_UP" or ori == "VERTICAL_DOWN"
end

local function OrientedSize(w, h, orientation)
    if IsVerticalOrientation(orientation) then
        return h, w  -- swap width and height for vertical bars
    end
    return w, h
end

local function ApplyBarOrientation(bar, orientation)
    if not bar then return end
    if orientation == "VERTICAL_UP" then
        bar:SetOrientation("VERTICAL")
        bar:SetRotatesTexture(true)
        bar:SetReverseFill(false)
    elseif orientation == "VERTICAL_DOWN" then
        bar:SetOrientation("VERTICAL")
        bar:SetRotatesTexture(true)
        bar:SetReverseFill(true)
    else
        bar:SetOrientation("HORIZONTAL")
        bar:SetRotatesTexture(false)
        bar:SetReverseFill(false)
    end
end

-------------------------------------------------------------------------------
--  Bar texture helper
-------------------------------------------------------------------------------
local function ApplyBarTexture(bar, texKey)
    if not bar then return end
    local texLookup = _G._ERB_BarTextures
    local path = texLookup and texLookup[texKey]
    if path then
        bar:SetStatusBarTexture(path)
    else
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    end
end


-- Compute pixel-snapped pip geometry for a given frame's effective scale.
-- Returns a table of {x0, x1} pairs (in logical units, snapped to physical
-- pixels) for each pip index 1..numPips. Spacing between every adjacent pair
-- is guaranteed to be exactly pipSp physical pixels at any UI scale.
local function CalcPipGeometry(totalW, numPips, pipSp, frame)
    local es = frame:GetEffectiveScale()
    if es <= 0 then es = 1 end
    -- 1 physical pixel in this frame's coordinate space
    local onePixel = PP.perfect / es

    -- Snap spacing to nearest whole physical pixel (minimum 1px)
    local spPx = math.max(1, math.floor(pipSp / onePixel + 0.5))

    -- Total physical pixels for the whole bar
    local totalPx = math.floor(totalW / onePixel + 0.5)
    local gapPx   = spPx * (numPips - 1)
    local pipPx   = totalPx - gapPx
    local basePx  = math.floor(pipPx / numPips)
    local extraPx = pipPx - basePx * numPips -- first extraPx pips get +1px

    -- Build per-pip positions in physical pixels, convert to logical units once.
    local slots = {}
    local cursor = 0
    for i = 1, numPips do
        local w = basePx + (i <= extraPx and 1 or 0)
        slots[i] = { x0 = cursor * onePixel, x1 = (cursor + w) * onePixel }
        cursor = cursor + w + spPx
    end

    return slots, spPx * onePixel, onePixel
end

local function MakePixelBorder(parent, r, g, b, a, size)
    local alpha = a or 1
    local sz = size or 1
    local bf = CreateFrame("Frame", nil, parent)
    bf:SetAllPoints(parent)
    bf:SetFrameLevel(parent:GetFrameLevel() + 1)

    -- Use the unified PP border system (raw integer sizes, never scaled)
    PP.CreateBorder(bf, r, g, b, alpha, sz, "OVERLAY", 7)

    return {
        _frame = bf,
        edges = bf._ppBorders,
        SetColor = function(self, cr, cg, cb, ca)
            PP.SetBorderColor(bf, cr, cg, cb, ca or 1)
        end,
        SetSize = function(self, newSz)
            PP.SetBorderSize(bf, newSz)
        end,
        SetShown = function(self, shown)
            if shown then PP.ShowBorder(bf) else PP.HideBorder(bf) end
        end,
    }
end

-------------------------------------------------------------------------------
--  Bar creation helpers
-------------------------------------------------------------------------------
local function CreateStatusBar(parent, name, w, h, borderSize, borderR, borderG, borderB, borderA)
    local bar = CreateFrame("StatusBar", name, parent)
    bar:SetSize(w, h)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:EnableMouse(false)

    -- Background
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0x11/255, 0x11/255, 0x11/255, 0.75)
    bar._bg = bg

    -- Pixel-perfect border with variable size
    local bSz = borderSize or 1
    bar._border = MakePixelBorder(bar, borderR or 0, borderG or 0, borderB or 0, borderA or 1, bSz)

    function bar:ApplyBorder(sz, r, g, b, a)
        self._border:SetSize(sz)
        self._border:SetColor(r, g, b, a)
        if sz == 0 then
            self._border:SetShown(false)
        else
            self._border:SetShown(true)
        end
    end

    -- Text overlay on a child frame above the border (above frame level + 1 border)
    local textFrame = CreateFrame("Frame", nil, bar)
    textFrame:SetAllPoints(bar)
    textFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
    textFrame:EnableMouse(false)
    local text = textFrame:CreateFontString(nil, "OVERLAY")
    SetRBFont(text, GetRBFont(), 11)
    text:SetTextColor(1, 1, 1, 0.9)
    text:SetPoint("CENTER", textFrame, "CENTER")
    bar._text = text

    -- Smooth animation state
    bar._smoothTarget = 0
    bar._smoothCurrent = 0

    return bar
end

-- Create a single pip (for combo points, holy power, etc.)
local function CreatePip(parent, w, h, idx, borderSize, borderR, borderG, borderB, borderA)
    local pip = CreateFrame("Frame", nil, parent)
    pip:SetSize(w, h)

    local bg = pip:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
    pip._bg = bg

    local fill = pip:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    fill:SetColorTexture(1, 1, 1, 1)
    pip._fill = fill
    pip._texKey = nil  -- current bar texture key

    -- Pixel-perfect border with variable size
    local bSz = borderSize or 1
    pip._border = MakePixelBorder(pip, borderR or 0, borderG or 0, borderB or 0, borderA or 1, bSz)

    function pip:ApplyBorder(sz, r, g, b, a)
        self._border:SetSize(sz)
        self._border:SetColor(r, g, b, a)
        if sz == 0 then
            self._border:SetShown(false)
        else
            self._border:SetShown(true)
        end
    end

    function pip:ApplyTexture(texKey)
        self._texKey = texKey
        local texLookup = _G._ERB_BarTextures
        local path = texLookup and texLookup[texKey]
        if path then
            self._fill:SetTexture(path)
        else
            self._fill:SetTexture("Interface\\Buttons\\WHITE8x8")
        end
        -- Keep recharge bar texture in sync if it exists
        if self._rechargeBar then
            if path then
                self._rechargeBar:SetStatusBarTexture(path)
            else
                self._rechargeBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            end
        end
    end

    pip._active = false
    pip._idx = idx

    function pip:SetActive(active, r, g, b, a)
        self._active = active
        if active then
            self._fill:SetVertexColor(r, g, b, a or 1)
            self._fill:Show()
        else
            self._fill:Hide()
        end
    end

    return pip
end


-------------------------------------------------------------------------------
--  Main frame construction
-------------------------------------------------------------------------------
local pips = {}
local runeFrames = {}

-------------------------------------------------------------------------------
--  Smooth animation helper for actual bar scale / offset changes
-------------------------------------------------------------------------------
local _barAnimTimers = {}
local BAR_ANIM_DURATION = 0.18

local function SmoothBarAnimate(frame, key, targetVal, applyFn)
    if not frame then return end
    if not _barAnimTimers[frame] then _barAnimTimers[frame] = {} end
    if _barAnimTimers[frame][key] then
        _barAnimTimers[frame][key]:Cancel()
        _barAnimTimers[frame][key] = nil
    end
    local startVal = frame["_barAnim_" .. key] or targetVal
    if math.abs(startVal - targetVal) < 0.001 then
        frame["_barAnim_" .. key] = targetVal
        applyFn(targetVal)
        return
    end
    local elapsed = 0
    local ticker
    ticker = C_Timer.NewTicker(0.016, function()
        elapsed = elapsed + 0.016
        local t = math.min(elapsed / BAR_ANIM_DURATION, 1)
        t = 1 - (1 - t) * (1 - t)  -- ease-out quad
        local v = startVal + (targetVal - startVal) * t
        frame["_barAnim_" .. key] = v
        applyFn(v)
        if t >= 1 then
            frame["_barAnim_" .. key] = targetVal
            ticker:Cancel()
            if _barAnimTimers[frame] then _barAnimTimers[frame][key] = nil end
        end
    end)
    _barAnimTimers[frame][key] = ticker
end

local function BuildMainFrame()
    if mainFrame then return mainFrame end

    local g = ERB.db.profile.general or DEFAULTS.profile.general

    mainFrame = CreateFrame("Frame", "EllesmereUIResourceBarsFrame", UIParent)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", g.anchorX or 0, g.anchorY or -100)
    mainFrame:SetSize(1, 1)  -- invisible anchor point
    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:SetFrameLevel(5)

    return mainFrame
end


-------------------------------------------------------------------------------
--  Unlock mode: register with shared EllesmereUI unlock system
-------------------------------------------------------------------------------
local function RegisterUnlockElements()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end

    local elements = {}

    -- Health Bar
    elements[#elements + 1] = {
        key = "ERB_Health",
        label = "Health Bar",
        group = "Resource Bars",
        order = 500,
        getFrame = function() return healthBar end,
        getSize = function()
            local hp = ERB.db.profile.health
            return hp.width, hp.height
        end,
        getScale = function()
            return ERB.db.profile.health.scale or 1.0
        end,
        savePosition = function(_, point, relPoint, x, y, scale)
            if not point then return end
            local hp = ERB.db.profile.health
            hp.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y, scale = scale }
            if scale then hp.scale = scale end
            if healthBar then
                if scale then pcall(function() healthBar:SetScale(scale) end) end
                healthBar:ClearAllPoints()
                healthBar:SetPoint(point, UIParent, relPoint or point, x, y)
            end
        end,
        loadPosition = function()
            local pos = ERB.db.profile.health.unlockPos
            if not pos then return nil end
            return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y, scale = pos.scale }
        end,
        clearPosition = function()
            local hp = ERB.db.profile.health
            hp.unlockPos = nil
            hp.offsetX = 0; hp.offsetY = -65
        end,
        isAnchored = function()
            local hp = ERB.db.profile.health
            return hp.anchorTo and hp.anchorTo ~= "none"
        end,
        applyPosition = function()
            local hp = ERB.db.profile.health
            local pos = hp.unlockPos
            if not pos then return end
            if healthBar then
                local sc = pos.scale or hp.scale or 1
                pcall(function() healthBar:SetScale(sc) end)
                healthBar:ClearAllPoints()
                healthBar:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
            end
        end,
    }

    -- Power Bar
    elements[#elements + 1] = {
        key = "ERB_Power",
        label = "Power Bar",
        group = "Resource Bars",
        order = 501,
        getFrame = function() return primaryBar end,
        getSize = function()
            local pp = ERB.db.profile.primary
            return pp.width, pp.height
        end,
        getScale = function()
            return ERB.db.profile.primary.scale or 1.0
        end,
        savePosition = function(_, point, relPoint, x, y, scale)
            if not point then return end
            local pp = ERB.db.profile.primary
            pp.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y, scale = scale }
            if scale then pp.scale = scale end
            if primaryBar then
                if scale then pcall(function() primaryBar:SetScale(scale) end) end
                primaryBar:ClearAllPoints()
                primaryBar:SetPoint(point, UIParent, relPoint or point, x, y)
            end
        end,
        loadPosition = function()
            local pos = ERB.db.profile.primary.unlockPos
            if not pos then return nil end
            return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y, scale = pos.scale }
        end,
        clearPosition = function()
            local pp = ERB.db.profile.primary
            pp.unlockPos = nil
            pp.offsetX = 0; pp.offsetY = -74
        end,
        isAnchored = function()
            local pp = ERB.db.profile.primary
            return pp.anchorTo and pp.anchorTo ~= "none"
        end,
        applyPosition = function()
            local pp = ERB.db.profile.primary
            local pos = pp.unlockPos
            if not pos then return end
            if primaryBar then
                local sc = pos.scale or pp.scale or 1
                pcall(function() primaryBar:SetScale(sc) end)
                primaryBar:ClearAllPoints()
                primaryBar:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
            end
        end,
    }

    -- Class Resource (pips/runes)
    elements[#elements + 1] = {
        key = "ERB_ClassResource",
        label = "Class Resource",
        group = "Resource Bars",
        order = 502,
        getFrame = function() return secondaryFrame end,
        getSize = function()
            local sp = ERB.db.profile.secondary
            if cachedSecondary and cachedSecondary.type == "bar" then
                local totalW = ERB.db.profile.primary.width or 214
                return totalW, sp.pipHeight
            end
            return sp.pipWidth, sp.pipHeight
        end,
        getScale = function()
            return ERB.db.profile.secondary.scale or 1.0
        end,
        savePosition = function(_, point, relPoint, x, y, scale)
            if not point then return end
            local sp = ERB.db.profile.secondary
            sp.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y, scale = scale }
            if scale then sp.scale = scale end
            if secondaryFrame then
                if scale then pcall(function() secondaryFrame:SetScale(scale) end) end
                secondaryFrame:ClearAllPoints()
                secondaryFrame:SetPoint(point, UIParent, relPoint or point, x, y)
            end
        end,
        loadPosition = function()
            local pos = ERB.db.profile.secondary.unlockPos
            if not pos then return nil end
            return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y, scale = pos.scale }
        end,
        clearPosition = function()
            local sp = ERB.db.profile.secondary
            sp.unlockPos = nil
            sp.offsetX = 0; sp.offsetY = -38
        end,
        isAnchored = function()
            local sp = ERB.db.profile.secondary
            return sp.anchorTo and sp.anchorTo ~= "none"
        end,
        applyPosition = function()
            local sp = ERB.db.profile.secondary
            local pos = sp.unlockPos
            if not pos then return end
            if secondaryFrame then
                local sc = pos.scale or sp.scale or 1
                pcall(function() secondaryFrame:SetScale(sc) end)
                secondaryFrame:ClearAllPoints()
                secondaryFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
            end
        end,
    }

    -- Cast Bar
    elements[#elements + 1] = {
        key = "ERB_CastBar",
        label = "Cast Bar",
        group = "Resource Bars",
        order = 504,
        getFrame = function() return castBarFrame end,
        getSize = function()
            local cb = ERB.db.profile.castBar
            local iconW = (cb.showIcon ~= false) and cb.height or 0
            return cb.width + iconW, cb.height
        end,
        getScale = function()
            return ERB.db.profile.castBar.scale or 1.0
        end,
        savePosition = function(_, point, relPoint, x, y, scale)
            if not point then return end
            local cb = ERB.db.profile.castBar
            cb.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y, scale = scale }
            if scale then cb.scale = scale end
            if castBarFrame then
                if scale then pcall(function() castBarFrame:SetScale(scale) end) end
                castBarFrame:ClearAllPoints()
                castBarFrame:SetPoint(point, UIParent, relPoint or point, x, y)
            end
        end,
        loadPosition = function()
            local pos = ERB.db.profile.castBar.unlockPos
            if not pos then return nil end
            return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y, scale = pos.scale }
        end,
        clearPosition = function()
            local cb = ERB.db.profile.castBar
            cb.unlockPos = nil
            cb.anchorX = 0; cb.anchorY = -54
        end,
        applyPosition = function()
            local cb = ERB.db.profile.castBar
            local pos = cb.unlockPos
            if not pos then return end
            if castBarFrame then
                local sc = pos.scale or cb.scale or 1
                pcall(function() castBarFrame:SetScale(sc) end)
                castBarFrame:ClearAllPoints()
                castBarFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
            end
        end,
    }
    EllesmereUI:RegisterUnlockElements(elements)
end

_G._ERB_ApplyUnlock = function()
    -- The shared unlock system handles everything now
end
_G._ERB_RegisterUnlock = RegisterUnlockElements

-------------------------------------------------------------------------------
--  Anchor resolution helper
--  Returns the target frame for a given anchorTo key, or nil if not available.
-------------------------------------------------------------------------------
local ERB_ANCHOR_FRAMES = {
    erb_classresource = function() return secondaryFrame end,
    erb_powerbar      = function() return primaryBar end,
    erb_health        = function() return healthBar end,
    erb_castbar       = function() return castBarFrame end,
    erb_cdm           = function() return _G._ECME_GetBarFrame and _G._ECME_GetBarFrame("cooldowns") end,
    mouse             = nil,  -- handled separately
    partyframe        = nil,  -- handled separately
    playerframe       = nil,  -- handled separately
}

local function ResolveAnchorFrame(anchorKey)
    local fn = ERB_ANCHOR_FRAMES[anchorKey]
    if fn then return fn() end
    return nil
end

-- Apply anchor-based positioning for a bar frame.
-- anchorKey: the anchorTo setting value
-- anchorPos: "left"/"right"/"top"/"bottom"
-- frame: the bar frame to position
-- offsetX, offsetY: additional offsets
-- growthDir: "UP", "DOWN", "LEFT", "RIGHT" -- which direction the bar grows from the anchor edge
-- growCentered: true = bar centered on anchor edge midpoint; false = bar corner at anchor edge midpoint
-- Recursively set mouse passthrough on a frame and all its children.
-- Stores original state on first call so it can be restored.
local function SetFrameClickThrough(frame, clickThrough)
    if not frame then return end
    if clickThrough then
        -- Store original state if not already stored
        if frame._erbMouseWas == nil then
            frame._erbMouseWas = frame:IsMouseEnabled()
        end
        frame:EnableMouse(false)
        if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
        if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
    else
        -- Restore original state
        if frame._erbMouseWas ~= nil then
            frame:EnableMouse(frame._erbMouseWas)
            frame._erbMouseWas = nil
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        SetFrameClickThrough(child, clickThrough)
    end
end

local function ApplyBarAnchor(frame, anchorKey, anchorPos, offsetX, offsetY, growthDir, growCentered)
    -- Always clear any previous mouse-tracking OnUpdate
    if frame._erbMouseTrack then
        frame:SetScript("OnUpdate", nil)
        frame._erbMouseTrack = nil
        frame:SetFrameStrata("LOW")
        frame:SetFrameLevel(5)
        -- Restore mouse on frame and all children
        SetFrameClickThrough(frame, false)
        if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
    end

    if not anchorKey or anchorKey == "none" then return false end
    offsetX = offsetX or 0
    offsetY = offsetY or 0
    anchorPos = anchorPos or "left"
    growthDir = growthDir or "UP"
    local centered = (growCentered ~= false)

    -- Determine the frame's own anchor point -- always the near edge center.
    -- LayoutCDMBar-equivalent offset logic handles non-centered icon positioning.
    --   grow RIGHT -> near edge = LEFT   -> "LEFT"
    --   grow LEFT  -> near edge = RIGHT  -> "RIGHT"
    --   grow DOWN  -> near edge = TOP    -> "TOP"
    --   grow UP    -> near edge = BOTTOM -> "BOTTOM"
    local function GetFramePoint()
        if growthDir == "RIGHT" then return "LEFT"   end
        if growthDir == "LEFT"  then return "RIGHT"  end
        if growthDir == "DOWN"  then return "TOP"    end
        if growthDir == "UP"    then return "BOTTOM" end
        return "LEFT"
    end

    if anchorKey == "mouse" then
        -- Determine SetPoint anchor and directional nudge based on anchorPos
        local pointFrom, baseOX, baseOY
        if anchorPos == "left" then
            pointFrom = "RIGHT"; baseOX = -15 + offsetX; baseOY = offsetY
        elseif anchorPos == "right" then
            pointFrom = "LEFT"; baseOX = 15 + offsetX; baseOY = offsetY
        elseif anchorPos == "top" then
            pointFrom = "BOTTOM"; baseOX = offsetX; baseOY = 15 + offsetY
        elseif anchorPos == "bottom" then
            pointFrom = "TOP"; baseOX = offsetX; baseOY = -15 + offsetY
        else
            pointFrom = "LEFT"; baseOX = 15 + offsetX; baseOY = offsetY
        end
        frame:SetFrameStrata("TOOLTIP")
        frame:SetFrameLevel(9980)
        frame:ClearAllPoints()
        frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", 0, 0)
        frame._erbMouseTrack = true
        -- Make frame and all children fully click-through while following cursor
        SetFrameClickThrough(frame, true)
        local lastMX, lastMY
        frame:SetScript("OnUpdate", function()
            local s = UIParent:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx = floor(cx / s + 0.5)
            cy = floor(cy / s + 0.5)
            if cx ~= lastMX or cy ~= lastMY then
                lastMX, lastMY = cx, cy
                frame:ClearAllPoints()
                frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", cx + baseOX, cy + baseOY)
            end
        end)
        return true
    elseif anchorKey == "partyframe" then
        local partyFrame = _G._ECME_FindPlayerPartyFrame and _G._ECME_FindPlayerPartyFrame()
        if not partyFrame then return false end
        frame:ClearAllPoints()
        if anchorPos == "left" then
            frame:SetPoint(GetFramePoint(), partyFrame, "LEFT", offsetX, offsetY)
        elseif anchorPos == "right" then
            frame:SetPoint(GetFramePoint(), partyFrame, "RIGHT", offsetX, offsetY)
        elseif anchorPos == "top" then
            frame:SetPoint(GetFramePoint(), partyFrame, "TOP", offsetX, offsetY)
        elseif anchorPos == "bottom" then
            frame:SetPoint(GetFramePoint(), partyFrame, "BOTTOM", offsetX, offsetY)
        end
        return true
    elseif anchorKey == "playerframe" then
        local playerFrame = _G._ECME_FindPlayerUnitFrame and _G._ECME_FindPlayerUnitFrame()
        if not playerFrame then return false end
        frame:ClearAllPoints()
        if anchorPos == "left" then
            frame:SetPoint(GetFramePoint(), playerFrame, "LEFT", offsetX, offsetY)
        elseif anchorPos == "right" then
            frame:SetPoint(GetFramePoint(), playerFrame, "RIGHT", offsetX, offsetY)
        elseif anchorPos == "top" then
            frame:SetPoint(GetFramePoint(), playerFrame, "TOP", offsetX, offsetY)
        elseif anchorPos == "bottom" then
            frame:SetPoint(GetFramePoint(), playerFrame, "BOTTOM", offsetX, offsetY)
        end
        return true
    end

    local targetFrame = ResolveAnchorFrame(anchorKey)
    if not targetFrame or not targetFrame:IsShown() then return false end

    frame:ClearAllPoints()
    local ok
    if anchorPos == "left" then
        ok = pcall(frame.SetPoint, frame, GetFramePoint(), targetFrame, "LEFT", offsetX, offsetY)
    elseif anchorPos == "right" then
        ok = pcall(frame.SetPoint, frame, GetFramePoint(), targetFrame, "RIGHT", offsetX, offsetY)
    elseif anchorPos == "top" then
        ok = pcall(frame.SetPoint, frame, GetFramePoint(), targetFrame, "TOP", offsetX, offsetY)
    elseif anchorPos == "bottom" then
        ok = pcall(frame.SetPoint, frame, GetFramePoint(), targetFrame, "BOTTOM", offsetX, offsetY)
    end
    return ok or false
end

-------------------------------------------------------------------------------
--  BuildBars -- applies per-element scale, border, colors, text positioning
-------------------------------------------------------------------------------

local function BuildBars()
    local p = ERB.db.profile

    -- If the profile is missing critical sub-tables, reset to defaults
    if type(p.primary) ~= "table" or type(p.secondary) ~= "table"
    or type(p.general) ~= "table" then
        ERB.db:ResetProfile()
        p = ERB.db.profile
    end

    local g = p.general or DEFAULTS.profile.general

    if not mainFrame then BuildMainFrame() end

    -- Clear animation state so DB values are always authoritative on a fresh build
    local _animClearKeys = { "scale", "ox", "oy", "w", "h" }
    for _, _animBar in ipairs({ healthBar, primaryBar, secondaryFrame, castBarFrame }) do
        if _animBar then
            for _, _k in ipairs(_animClearKeys) do
                _animBar["_barAnim_" .. _k] = nil
            end
        end
    end

    -- Fallback defaults for nil-safe reads (protects against sparse SavedVariables from migration)
    local FALLBACK = DEFAULTS.profile

    -- Health bar
    local hp = p.health or FALLBACK.health
    if hp.enabled then
        local hpOri = hp.orientation or g.orientation or "HORIZONTAL"
        if not healthBar then
            healthBar = CreateStatusBar(mainFrame, "ERB_HealthBar", hp.width, hp.height,
                hp.borderSize, hp.borderR, hp.borderG, hp.borderB, hp.borderA)
        end
        if hp.unlockPos and hp.unlockPos.point then
            -- Position fully managed by unlock mode -- no animations, just apply directly
            local rp = hp.unlockPos.relPoint or hp.unlockPos.point
            local ow, oh = OrientedSize(hp.width, hp.height, hpOri)
            healthBar:SetScale(hp.scale)
            healthBar:SetSize(ow, oh)
            healthBar:ClearAllPoints()
            healthBar:SetPoint(hp.unlockPos.point, UIParent, rp, hp.unlockPos.x or 0, hp.unlockPos.y or 0)
        elseif hp.anchorTo and hp.anchorTo ~= "none" then
            local ow, oh = OrientedSize(hp.width, hp.height, hpOri)
            healthBar:SetScale(hp.scale)
            healthBar:SetSize(ow, oh)
            ApplyBarAnchor(healthBar, hp.anchorTo, hp.anchorPosition, hp.anchorOffsetX, hp.anchorOffsetY, hp.growthDirection, hp.growCentered)
        else
            -- Clear any mouse-tracking OnUpdate from a previous anchor
            ApplyBarAnchor(healthBar, "none")
            local function ApplyHealthBarTransform()
                local s = healthBar["_barAnim_scale"] or hp.scale or 1
                local ox = healthBar["_barAnim_ox"] or hp.offsetX or 0
                local oy = healthBar["_barAnim_oy"] or hp.offsetY or -64
                local w = healthBar["_barAnim_w"] or hp.width or 214
                local h2 = healthBar["_barAnim_h"] or hp.height or 16
                local ow, oh = OrientedSize(w, h2, hpOri)
                healthBar:ClearAllPoints()
                healthBar:SetPoint("CENTER", mainFrame, "CENTER", ox, oy)
                healthBar:SetScale(s)
                healthBar:SetSize(ow, oh)
            end
            SmoothBarAnimate(healthBar, "scale", hp.scale or 1, function() ApplyHealthBarTransform() end)
            SmoothBarAnimate(healthBar, "ox", hp.offsetX or 0, function() ApplyHealthBarTransform() end)
            SmoothBarAnimate(healthBar, "oy", hp.offsetY or -64, function() ApplyHealthBarTransform() end)
            SmoothBarAnimate(healthBar, "w", hp.width or 214, function() ApplyHealthBarTransform() end)
            SmoothBarAnimate(healthBar, "h", hp.height or 16, function() ApplyHealthBarTransform() end)
        end
        healthBar:ApplyBorder(hp.borderSize, hp.borderR, hp.borderG, hp.borderB, hp.borderA)

        -- Bar texture (must be applied before colors since SetStatusBarTexture resets vertex color)
        ApplyBarTexture(healthBar, g.barTexture or "none")

        -- Colors: dark theme > custom colored > class color
        if hp.darkTheme then
            healthBar:GetStatusBarTexture():SetVertexColor(DARK_FILL_R, DARK_FILL_G, DARK_FILL_B, DARK_FILL_A)
            healthBar._bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, DARK_BG_A)
        elseif hp.customColored then
            healthBar:GetStatusBarTexture():SetVertexColor(hp.fillR, hp.fillG, hp.fillB, hp.fillA)
            healthBar._bg:SetColorTexture(hp.bgR, hp.bgG, hp.bgB, hp.bgA)
        else
            -- Class color
            local cc = CLASS_COLORS[cachedClass]
            if cc then
                healthBar:GetStatusBarTexture():SetVertexColor(cc[1], cc[2], cc[3], 1)
            else
                healthBar:GetStatusBarTexture():SetVertexColor(0.15, 0.75, 0.30, 1)
            end
            healthBar._bg:SetColorTexture(hp.bgR, hp.bgG, hp.bgB, hp.bgA)
        end

        -- Text positioning
        healthBar._text:ClearAllPoints()
        healthBar._text:SetPoint("CENTER", healthBar, "CENTER", hp.textXOffset, hp.textYOffset)
        SetRBFont(healthBar._text, GetRBFont(), hp.textSize)
        healthBar:Show()
        healthBar:SetAlpha(hp.barAlpha or 1)
        ApplyBarOrientation(healthBar, hpOri)
    elseif healthBar then
        healthBar:Hide()
    end

    -- Power bar (primary resource)
    cachedPrimary = GetPrimaryPowerType()
    local pp = p.primary or FALLBACK.primary
    if pp.enabled ~= false and cachedPrimary then
        local ppOri = pp.orientation or g.orientation or "HORIZONTAL"
        if not primaryBar then
            primaryBar = CreateStatusBar(mainFrame, "ERB_PrimaryBar", pp.width, pp.height,
                pp.borderSize, pp.borderR, pp.borderG, pp.borderB, pp.borderA)
        end
        if pp.unlockPos and pp.unlockPos.point then
            -- Position fully managed by unlock mode -- no animations, just apply directly
            local rp = pp.unlockPos.relPoint or pp.unlockPos.point
            local ow, oh = OrientedSize(pp.width, pp.height, ppOri)
            primaryBar:SetScale(pp.scale)
            primaryBar:SetSize(ow, oh)
            primaryBar:ClearAllPoints()
            primaryBar:SetPoint(pp.unlockPos.point, UIParent, rp, pp.unlockPos.x or 0, pp.unlockPos.y or 0)
        elseif pp.anchorTo and pp.anchorTo ~= "none" then
            local ow, oh = OrientedSize(pp.width, pp.height, ppOri)
            primaryBar:SetScale(pp.scale)
            primaryBar:SetSize(ow, oh)
            ApplyBarAnchor(primaryBar, pp.anchorTo, pp.anchorPosition, pp.anchorOffsetX, pp.anchorOffsetY, pp.growthDirection, pp.growCentered)
        else
            -- Clear any mouse-tracking OnUpdate from a previous anchor
            ApplyBarAnchor(primaryBar, "none")
            local function ApplyPowerBarTransform()
                local s = primaryBar["_barAnim_scale"] or pp.scale or 1
                local ox = primaryBar["_barAnim_ox"] or pp.offsetX or 0
                local oy = primaryBar["_barAnim_oy"] or pp.offsetY or -54
                local w = primaryBar["_barAnim_w"] or pp.width or 214
                local h2 = primaryBar["_barAnim_h"] or pp.height or 4
                local ow, oh = OrientedSize(w, h2, ppOri)
                primaryBar:ClearAllPoints()
                primaryBar:SetPoint("CENTER", mainFrame, "CENTER", ox, oy)
                primaryBar:SetScale(s)
                primaryBar:SetSize(ow, oh)
            end
            SmoothBarAnimate(primaryBar, "scale", pp.scale or 1, function() ApplyPowerBarTransform() end)
            SmoothBarAnimate(primaryBar, "ox", pp.offsetX or 0, function() ApplyPowerBarTransform() end)
            SmoothBarAnimate(primaryBar, "oy", pp.offsetY or -54, function() ApplyPowerBarTransform() end)
            SmoothBarAnimate(primaryBar, "w", pp.width or 214, function() ApplyPowerBarTransform() end)
            SmoothBarAnimate(primaryBar, "h", pp.height or 4, function() ApplyPowerBarTransform() end)
        end
        primaryBar:ApplyBorder(pp.borderSize, pp.borderR, pp.borderG, pp.borderB, pp.borderA)

        -- Bar texture (must be applied before colors since SetStatusBarTexture resets vertex color)
        ApplyBarTexture(primaryBar, g.barTexture or "none")

        -- Colors: dark theme > custom colored > power type color
        if pp.darkTheme then
            primaryBar:GetStatusBarTexture():SetVertexColor(DARK_FILL_R, DARK_FILL_G, DARK_FILL_B, DARK_FILL_A)
            primaryBar._bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, DARK_BG_A)
        elseif pp.customColored then
            primaryBar:GetStatusBarTexture():SetVertexColor(pp.fillR, pp.fillG, pp.fillB, pp.fillA)
            primaryBar._bg:SetColorTexture(pp.bgR, pp.bgG, pp.bgB, pp.bgA)
        else
            local pc = POWER_COLORS[cachedPrimary]
            if pc then
                primaryBar:GetStatusBarTexture():SetVertexColor(pc[1], pc[2], pc[3], 1)
            else
                primaryBar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
            end
            primaryBar._bg:SetColorTexture(pp.bgR, pp.bgG, pp.bgB, pp.bgA)
        end

        -- Text positioning
        primaryBar._text:ClearAllPoints()
        primaryBar._text:SetPoint("CENTER", primaryBar, "CENTER", pp.textXOffset, pp.textYOffset)
        SetRBFont(primaryBar._text, GetRBFont(), pp.textSize)
        primaryBar:Show()
        primaryBar:SetAlpha(pp.barAlpha or 1)
        ApplyBarOrientation(primaryBar, ppOri)
    elseif primaryBar then
        primaryBar:Hide()
    end


    -- Class resource (secondary: pips / runes)
    cachedSecondary = GetSecondaryResource()
    local sp = p.secondary or FALLBACK.secondary
    if sp.enabled ~= false and cachedSecondary then
        if not secondaryFrame then
            secondaryFrame = CreateFrame("Frame", "ERB_SecondaryFrame", mainFrame)
            secondaryFrame:SetClipsChildren(true)
        end

        local maxPts = cachedSecondary.max or 5
        if cachedSecondary.type == "custom" and EllesmereUI then
            local powerType = cachedSecondary.power
            if powerType == "SOUL_FRAGMENTS" and EllesmereUI.GetSoulFragments then
                local _, realMax = EllesmereUI.GetSoulFragments()
                if realMax and realMax > 0 then maxPts = realMax end
            elseif powerType == "MAELSTROM_WEAPON" and EllesmereUI.GetMaelstromWeapon then
                local _, realMax = EllesmereUI.GetMaelstromWeapon()
                if realMax and realMax > 0 then maxPts = realMax end
            elseif powerType == "TIP_OF_THE_SPEAR" and EllesmereUI.GetTipOfTheSpear then
                local _, realMax = EllesmereUI.GetTipOfTheSpear()
                if realMax and realMax > 0 then maxPts = realMax end
            elseif powerType == "WHIRLWIND_STACKS" and EllesmereUI.GetWhirlwindStacks then
                local _, realMax = EllesmereUI.GetWhirlwindStacks()
                if realMax and realMax > 0 then maxPts = realMax end
            end
        end
        local pipH = sp.pipHeight or 20
        local pipSp = sp.pipSpacing or 1
        local pipOri = sp.pipOrientation or "HORIZONTAL"
        local isVertical = (pipOri ~= "HORIZONTAL")
        local isReversed = (pipOri == "VERTICAL_UP")
        local totalW

        local isBarType = cachedSecondary.type == "bar"
        if isBarType then
            totalW = ERB.db.profile.primary.width or 214
        else
            totalW = sp.pipWidth or 214
        end

        -- Frame dimensions: vertical flips width/height axes
        local frameW = isVertical and pipH or totalW
        local frameH = isVertical and totalW or pipH

        if sp.unlockPos and sp.unlockPos.point then
            secondaryFrame:SetScale(sp.scale or 1)
            secondaryFrame:SetSize(frameW, frameH)
            secondaryFrame:ClearAllPoints()
            secondaryFrame:SetPoint(sp.unlockPos.point, UIParent, sp.unlockPos.relPoint or sp.unlockPos.point, sp.unlockPos.x or 0, sp.unlockPos.y or 0)
        elseif sp.anchorTo and sp.anchorTo ~= "none" then
            secondaryFrame:SetScale(sp.scale or 1)
            secondaryFrame:SetSize(frameW, frameH)
            ApplyBarAnchor(secondaryFrame, sp.anchorTo, sp.anchorPosition, sp.anchorOffsetX, sp.anchorOffsetY, sp.growthDirection, sp.growCentered)
        else
            ApplyBarAnchor(secondaryFrame, "none")
            local function ApplySecondaryBarTransform()
                local s  = secondaryFrame["_barAnim_scale"] or sp.scale or 1
                local ox = secondaryFrame["_barAnim_ox"] or sp.offsetX or 0
                local oy = secondaryFrame["_barAnim_oy"] or sp.offsetY or -38
                local w  = secondaryFrame["_barAnim_w"] or frameW
                local h2 = secondaryFrame["_barAnim_h"] or frameH
                secondaryFrame:ClearAllPoints()
                secondaryFrame:SetPoint("CENTER", mainFrame, "CENTER", ox, oy)
                secondaryFrame:SetScale(s)
                secondaryFrame:SetSize(w, h2)
            end
            SmoothBarAnimate(secondaryFrame, "scale", sp.scale or 1, function() ApplySecondaryBarTransform() end)
            SmoothBarAnimate(secondaryFrame, "ox", sp.offsetX or 0, function() ApplySecondaryBarTransform() end)
            SmoothBarAnimate(secondaryFrame, "oy", sp.offsetY or -38, function() ApplySecondaryBarTransform() end)
            SmoothBarAnimate(secondaryFrame, "w", frameW, function() ApplySecondaryBarTransform() end)
            SmoothBarAnimate(secondaryFrame, "h", frameH, function() ApplySecondaryBarTransform() end)
        end

        -- Create/reuse pips or bar
        if isBarType then
            -- Bar-style secondary (e.g. Devourer soul fragments, Elemental maelstrom)
            -- Hide all pips and runes
            for i = 1, #pips do if pips[i] then pips[i]:Hide() end end
            for i = 1, #runeFrames do if runeFrames[i] then runeFrames[i]:Hide() end end

            if not secondaryBar then
                secondaryBar = CreateStatusBar(secondaryFrame, "ERB_SecondaryBar", totalW, pipH,
                    0, 0, 0, 0, 0)
            end
            secondaryBar:SetSize(totalW, pipH)
            secondaryBar:ClearAllPoints()
            secondaryBar:SetAllPoints(secondaryFrame)
            secondaryBar:SetMinMaxValues(0, maxPts)
            secondaryBar:SetValue(0)

            -- Bar texture and orientation must be applied before colors since
            -- SetStatusBarTexture and SetRotatesTexture both reset vertex color
            ApplyBarTexture(secondaryBar, g.barTexture or "none")
            ApplyBarOrientation(secondaryBar, p.general.orientation)

            -- Colors
            local pc = POWER_COLORS[cachedSecondary.power]
            if sp.darkTheme then
                secondaryBar:GetStatusBarTexture():SetVertexColor(DARK_FILL_R, DARK_FILL_G, DARK_FILL_B, DARK_FILL_A)
                secondaryBar._bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, DARK_BG_A)
            elseif sp.classColored ~= false then
                -- classColored is true (default) -- use class color, or power color if no class color
                local cc = CLASS_COLORS[cachedClass]
                if cc then
                    secondaryBar:GetStatusBarTexture():SetVertexColor(cc[1], cc[2], cc[3], sp.fillA or 1)
                elseif pc then
                    secondaryBar:GetStatusBarTexture():SetVertexColor(pc[1], pc[2], pc[3], sp.fillA or 1)
                end
                secondaryBar._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
            else
                -- classColored explicitly false -- use custom fill color
                secondaryBar:GetStatusBarTexture():SetVertexColor(sp.fillR, sp.fillG, sp.fillB, sp.fillA)
                secondaryBar._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
            end
            secondaryBar:ApplyBorder(0, 0, 0, 0, 0)
            secondaryBar:Show()
        elseif cachedSecondary.type == "runes" then
            local numPips = 6
            local slots = CalcPipGeometry(totalW, numPips, pipSp, secondaryFrame)
            for i = 1, 6 do
                if not runeFrames[i] then
                    runeFrames[i] = CreatePip(secondaryFrame, 20, pipH, i,
                        0, 0, 0, 0, 0)
                    local cdText = runeFrames[i]:CreateFontString(nil, "OVERLAY")
                    SetRBFont(cdText, GetRBFont(), 9)
                    cdText:SetTextColor(1, 1, 1, 0.8)
                    cdText:SetPoint("CENTER")
                    runeFrames[i]._cdText = cdText
                end
                local x0 = slots[i].x0
                local x1 = slots[i].x1
                local rf = runeFrames[i]
                local function ApplyRunePos()
                    local ap0 = rf["_barAnim_x0"] or x0
                    local aw  = rf["_barAnim_x1"] or (x1 - x0)
                    local ah  = rf["_barAnim_ph"] or pipH
                    rf:ClearAllPoints()
                    if isVertical then
                        if isReversed then
                            rf:SetPoint("BOTTOM", secondaryFrame, "BOTTOM", 0, ap0)
                        else
                            rf:SetPoint("TOP", secondaryFrame, "TOP", 0, -ap0)
                        end
                        rf:SetHeight(aw)
                        rf:SetWidth(ah)
                    else
                        rf:SetPoint("LEFT", secondaryFrame, "LEFT", ap0, 0)
                        rf:SetWidth(aw)
                        rf:SetHeight(ah)
                    end
                end
                SmoothBarAnimate(rf, "x0", x0, function() ApplyRunePos() end)
                SmoothBarAnimate(rf, "x1", x1 - x0, function() ApplyRunePos() end)
                SmoothBarAnimate(rf, "ph", pipH, function() ApplyRunePos() end)
                runeFrames[i]:ApplyBorder(0, 0, 0, 0, 0)
                runeFrames[i]:ApplyTexture(g.barTexture or "none")
                if sp.darkTheme then
                    runeFrames[i]._bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, 1)
                elseif sp.classColored then
                    runeFrames[i]._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
                else
                    runeFrames[i]._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
                end
                runeFrames[i]:Show()
            end
            for i = 7, #pips do if pips[i] then pips[i]:Hide() end end
            if secondaryBar then secondaryBar:Hide() end
        else
            local slots = CalcPipGeometry(totalW, maxPts, pipSp, secondaryFrame)
            for i = 1, maxPts do
                if not pips[i] then
                    pips[i] = CreatePip(secondaryFrame, 20, pipH, i,
                        0, 0, 0, 0, 0)
                end
                local x0 = slots[i].x0
                local x1 = slots[i].x1
                local pip = pips[i]
                local function ApplyPipPos()
                    local ap0 = pip["_barAnim_x0"] or x0
                    local aw  = pip["_barAnim_x1"] or (x1 - x0)
                    local ah  = pip["_barAnim_ph"] or pipH
                    pip:ClearAllPoints()
                    if isVertical then
                        if isReversed then
                            pip:SetPoint("BOTTOM", secondaryFrame, "BOTTOM", 0, ap0)
                        else
                            pip:SetPoint("TOP", secondaryFrame, "TOP", 0, -ap0)
                        end
                        pip:SetHeight(aw)
                        pip:SetWidth(ah)
                    else
                        pip:SetPoint("LEFT", secondaryFrame, "LEFT", ap0, 0)
                        pip:SetWidth(aw)
                        pip:SetHeight(ah)
                    end
                end
                SmoothBarAnimate(pip, "x0", x0, function() ApplyPipPos() end)
                SmoothBarAnimate(pip, "x1", x1 - x0, function() ApplyPipPos() end)
                SmoothBarAnimate(pip, "ph", pipH, function() ApplyPipPos() end)
                pips[i]:ApplyBorder(0, 0, 0, 0, 0)
                pips[i]:ApplyTexture(g.barTexture or "none")
                if sp.darkTheme then
                    pips[i]._bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, 1)
                elseif sp.classColored then
                    pips[i]._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
                else
                    pips[i]._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
                end
                pips[i]:Show()
            end
            for i = maxPts + 1, #pips do if pips[i] then pips[i]:Hide() end end
            for i = 1, #runeFrames do if runeFrames[i] then runeFrames[i]:Hide() end end
            if secondaryBar then secondaryBar:Hide() end
        end

        -- Full-bar border (wraps the entire class resource bar)
        if not secondaryFrame._barBorder then
            secondaryFrame._barBorder = MakePixelBorder(secondaryFrame,
                sp.borderR, sp.borderG, sp.borderB, sp.borderA, sp.borderSize)
        end
        if sp.borderSize > 0 then
            secondaryFrame._barBorder:SetSize(sp.borderSize)
            secondaryFrame._barBorder:SetColor(sp.borderR, sp.borderG, sp.borderB, sp.borderA)
            secondaryFrame._barBorder:SetShown(true)
        else
            secondaryFrame._barBorder:SetShown(false)
        end

        -- Full-bar background (behind all pips)
        if not secondaryFrame._barBg then
            secondaryFrame._barBg = secondaryFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
        end
        secondaryFrame._barBg:ClearAllPoints()
        secondaryFrame._barBg:SetAllPoints(secondaryFrame)
        secondaryFrame._barBg:SetColorTexture(sp.barBgR or 0, sp.barBgG or 0, sp.barBgB or 0, sp.barBgA or 0.5)

        -- Count text
        if sp.showText then
            if not secondaryFrame._countText then
                -- Parent to a high-level overlay so text renders above pip fills and borders
                if not secondaryFrame._countTextOverlay then
                    secondaryFrame._countTextOverlay = CreateFrame("Frame", nil, secondaryFrame)
                    secondaryFrame._countTextOverlay:SetAllPoints(secondaryFrame)
                end
                secondaryFrame._countTextOverlay:SetFrameLevel(secondaryFrame:GetFrameLevel() + 10)
                secondaryFrame._countText = secondaryFrame._countTextOverlay:CreateFontString(nil, "OVERLAY")
                secondaryFrame._countText:SetTextColor(1, 1, 1, 0.9)
            end
            -- Keep overlay level current in case frame levels shifted
            if secondaryFrame._countTextOverlay then
                secondaryFrame._countTextOverlay:SetFrameLevel(secondaryFrame:GetFrameLevel() + 10)
            end
            secondaryFrame._countText:ClearAllPoints()
            secondaryFrame._countText:SetParent(secondaryFrame._countTextOverlay)
            secondaryFrame._countText:SetPoint("CENTER", secondaryFrame, "CENTER", sp.textXOffset, sp.textYOffset)
            SetRBFont(secondaryFrame._countText, GetRBFont(), sp.textSize)
            secondaryFrame._countText:Show()
        elseif secondaryFrame._countText then
            secondaryFrame._countText:Hide()
        end

        secondaryFrame:Show()
        secondaryFrame:SetAlpha(sp.barAlpha or 1)
    elseif secondaryFrame then
        secondaryFrame:Hide()
    end
end


-------------------------------------------------------------------------------
--  Update functions (event-driven)
-------------------------------------------------------------------------------
local function UpdateHealthBar()
    if not healthBar or not healthBar:IsShown() then return end
    local hp = ERB.db.profile.health

    local cur = UnitHealth("player")
    local mx = UnitHealthMax("player")
    if not cur or not mx or mx <= 0 then return end

    healthBar:SetMinMaxValues(0, mx)

    local curTainted = issecretvalue and issecretvalue(cur)
    local pctRaw = UnitHealthPercent and UnitHealthPercent("player", true, CurveConstants and CurveConstants.ScaleTo100) or 0
    local pctTainted = issecretvalue and issecretvalue(pctRaw)
    local pct01 = (not pctTainted) and (pctRaw / 100) or 1

    -- Color: dark theme and custom colored are handled in BuildBars,
    -- but we need to re-apply class color + low health lerp dynamically.
    -- When threshold is enabled, always re-apply color so we can swap
    -- between normal and threshold colors each tick.
    local applyThreshold = hp.thresholdEnabled and not pctTainted and pctRaw <= (hp.thresholdPct or 30)
    if applyThreshold then
        healthBar:GetStatusBarTexture():SetVertexColor(
            hp.thresholdR or 1, hp.thresholdG or 0.2, hp.thresholdB or 0.2, hp.thresholdA or 1)
    elseif hp.thresholdEnabled or (not hp.darkTheme and not hp.customColored) then
        -- Re-apply normal color (needed every tick when threshold is enabled
        -- so the bar reverts when health rises above the threshold)
        if hp.darkTheme then
            healthBar:GetStatusBarTexture():SetVertexColor(DARK_FILL_R, DARK_FILL_G, DARK_FILL_B, DARK_FILL_A)
        elseif hp.customColored then
            healthBar:GetStatusBarTexture():SetVertexColor(hp.fillR, hp.fillG, hp.fillB, hp.fillA)
        else
            local r, g, b
            local cc = CLASS_COLORS[cachedClass]
            if cc then r, g, b = cc[1], cc[2], cc[3] else r, g, b = 0.15, 0.75, 0.30 end
            healthBar:GetStatusBarTexture():SetVertexColor(r, g, b, 1)
        end
    end

    -- Smooth animation
    if not curTainted then
        healthBar._smoothTarget = cur
    else
        healthBar:SetValue(cur)
    end

    -- Text
    if hp.textFormat ~= "none" then
        local fmt = hp.textFormat
        local txt
        if fmt == "both" then
            txt = AbbreviateLargeNumbers(cur) .. " | " .. format("%d", pctRaw) .. "%"
        elseif fmt == "curhpshort" then
            txt = AbbreviateLargeNumbers(cur)
        elseif fmt == "perhp" then
            txt = format("%d", pctRaw) .. "%"
        elseif fmt == "perhpnosign" then
            txt = format("%d", pctRaw)
        elseif fmt == "perhpnum" then
            txt = format("%d", pctRaw) .. "% | " .. AbbreviateLargeNumbers(cur)
        else
            txt = format("%d", pctRaw) .. "%"
        end
        healthBar._text:SetText(txt)
        healthBar._text:Show()
    else
        healthBar._text:Hide()
    end
end

local function UpdatePrimaryBar()
    if not primaryBar or not primaryBar:IsShown() then return end
    local pp = ERB.db.profile.primary

    cachedPrimary = GetPrimaryPowerType()
    if not cachedPrimary then return end
    local cur = UnitPower("player", cachedPrimary)
    local mx = UnitPowerMax("player", cachedPrimary)
    if not mx or mx <= 0 then return end

    primaryBar:SetMinMaxValues(0, mx)

    local pctRaw = UnitPowerPercent and UnitPowerPercent("player", cachedPrimary, true, CurveConstants and CurveConstants.ScaleTo100) or 0
    local pctTainted = issecretvalue and issecretvalue(pctRaw)
    local pct01 = (not pctTainted) and (pctRaw / 100) or 1

    -- Color: threshold via ColorCurve (secret-safe) for non-mana specs;
    -- otherwise dark/custom/power-type color applied directly.
    local ft = primaryBar:GetStatusBarTexture()
    if pp.thresholdEnabled and cachedPrimary ~= PT.MANA and ft and UnitPowerPercent then
        local baseR, baseG, baseB
        if pp.darkTheme then
            baseR, baseG, baseB = DARK_FILL_R, DARK_FILL_G, DARK_FILL_B
        elseif pp.customColored then
            baseR, baseG, baseB = pp.fillR, pp.fillG, pp.fillB
        else
            local pc = POWER_COLORS[cachedPrimary]
            if pc then baseR, baseG, baseB = pc[1], pc[2], pc[3] else baseR, baseG, baseB = 1, 1, 1 end
        end
        local curve = GetBarThresholdCurve(
            baseR, baseG, baseB,
            pp.thresholdR or 1, pp.thresholdG or 0.2, pp.thresholdB or 0.2,
            pp.thresholdPct or 30)
        if curve then
            local ok, colorResult = pcall(UnitPowerPercent, "player", cachedPrimary, false, curve)
            if ok and colorResult and colorResult.GetRGBA then
                ft:SetVertexColor(colorResult:GetRGBA())
            end
        end
    elseif not pp.darkTheme and not pp.customColored then
        local r, g, b
        local pc = POWER_COLORS[cachedPrimary]
        if pc then r, g, b = pc[1], pc[2], pc[3] else r, g, b = 1, 1, 1 end
        ft:SetVertexColor(r, g, b, 1)
    end

    -- Smooth animation
    local tainted = issecretvalue and issecretvalue(cur)
    if not tainted then
        primaryBar._smoothTarget = cur
    else
        primaryBar:SetValue(cur)
    end

    -- Text
    if pp.textFormat ~= "none" then
        local fmt = pp.textFormat
        local percentSuffix = (pp.showPercent == false) and "" or "%"
        local percentText = format("%d", pctRaw) .. percentSuffix
        local txt
        if fmt == "smart" then
            local isPercent = EllesmereUI.IsSmartPowerPercent and EllesmereUI.IsSmartPowerPercent()
            txt = isPercent and percentText or AbbreviateLargeNumbers(cur)
        elseif fmt == "both" then
            txt = AbbreviateLargeNumbers(cur) .. " | " .. percentText
        elseif fmt == "curpp" then
            txt = AbbreviateLargeNumbers(cur)
        elseif fmt == "perpp" then
            txt = percentText
        else
            txt = AbbreviateLargeNumbers(cur)
        end
        primaryBar._text:SetText(txt)
        primaryBar._text:Show()
    else
        primaryBar._text:Hide()
    end
end

-- Pre-allocated rune sorting buffers to avoid per-tick table creation.
-- Uses parallel arrays instead of tables-of-tables for zero GC pressure.
local _runeOrder = {}       -- [slot] = rune index (1-6)
local _runeRemaining = {}   -- [rune index] = remaining time
local _runeStart = {}       -- [rune index] = cooldown start
local _runeDuration = {}    -- [rune index] = cooldown duration
local _runeReady = {}       -- [rune index] = true/false

local function UpdateSecondaryResource()
    if not secondaryFrame or not secondaryFrame:IsShown() then return end
    if not cachedSecondary then return end

    local powerType = cachedSecondary.power
    local maxPts = cachedSecondary.max or 5

    local sp = ERB.db.profile.secondary
    local pc = POWER_COLORS[powerType]
    local r, g, b, a = 1, 1, 1, 1

    -- Color: dark theme > class colored > custom fill color
    if sp.darkTheme then
        r, g, b = DARK_FILL_R, DARK_FILL_G, DARK_FILL_B
    elseif sp.classColored ~= false then
        -- classColored is true (default) -- use class color
        local cc = CLASS_COLORS[cachedClass]
        if cc then r, g, b = cc[1], cc[2], cc[3] end
        a = sp.fillA or 1
    else
        -- classColored explicitly false -- custom fill
        r, g, b, a = sp.fillR, sp.fillG, sp.fillB, sp.fillA or 1
    end

    if cachedSecondary.type == "runes" then
        -- Sort runes: ready first (left), then cooling down sorted by
        -- ascending remaining time so they deplete right-to-left.
        -- Uses pre-allocated parallel arrays to avoid per-tick table creation.
        local now = GetTime()
        local readyN, cdN = 0, 0
        for i = 1, 6 do
            local start, duration, ready = GetRuneCooldown(i)
            _runeStart[i] = start
            _runeDuration[i] = duration
            if ready then
                _runeReady[i] = true
                _runeRemaining[i] = 0
                readyN = readyN + 1
                _runeOrder[readyN] = i
            else
                _runeReady[i] = false
                _runeRemaining[i] = (start and duration and duration > 0)
                    and max(0, start + duration - now) or 999
                cdN = cdN + 1
            end
        end
        -- Append cd runes after ready runes in _runeOrder
        local ci = readyN
        for i = 1, 6 do
            if not _runeReady[i] then
                ci = ci + 1
                _runeOrder[ci] = i
            end
        end
        -- Insertion-sort the cd portion (indices readyN+1..readyN+cdN) by
        -- remaining time. Max 6 elements so this is faster than table.sort
        -- and avoids creating a comparator closure each tick.
        for i = readyN + 2, readyN + cdN do
            local key = _runeOrder[i]
            local keyRem = _runeRemaining[key]
            local j = i - 1
            while j > readyN and _runeRemaining[_runeOrder[j]] > keyRem do
                _runeOrder[j + 1] = _runeOrder[j]
                j = j - 1
            end
            _runeOrder[j + 1] = key
        end
        local totalRunes = readyN + cdN

        -- Compute pixel-snapped pip geometry (spacing guaranteed >= 1 physical pixel)
        local numPips = 6
        local totalW = sp.pipWidth or 214
        local pipSp = sp.pipSpacing or 1
        local slots = CalcPipGeometry(totalW, numPips, pipSp, secondaryFrame)

        for pos = 1, totalRunes do
            local runeIdx = _runeOrder[pos]
            local rf = runeFrames[runeIdx]
            if rf and rf:IsShown() then
                local slot = slots[pos]
                local x0 = slot.x0
                local w  = slot.x1 - slot.x0
                local pipOri = sp.pipOrientation or "HORIZONTAL"
                rf:ClearAllPoints()
                if pipOri == "VERTICAL_UP" then
                    rf:SetPoint("BOTTOM", secondaryFrame, "BOTTOM", 0, x0)
                    rf:SetHeight(w)
                elseif pipOri == "VERTICAL_DOWN" or pipOri == "VERTICAL" then
                    rf:SetPoint("TOP", secondaryFrame, "TOP", 0, -x0)
                    rf:SetHeight(w)
                else
                    rf:SetPoint("LEFT", secondaryFrame, "LEFT", x0, 0)
                    rf:SetWidth(w)
                end

                if _runeReady[runeIdx] then
                    -- Ready rune: full brightness, hide recharge overlay
                    rf:SetActive(true, r, g, b, a)
                    if rf._rechargeBar then rf._rechargeBar:Hide() end
                    if rf._cdText then rf._cdText:SetText("") end
                else
                    -- Cooling-down rune: hide normal fill, show recharge bar
                    rf:SetActive(false, r, g, b, a)

                    -- Lazily create a StatusBar overlay for recharge progress
                    if not rf._rechargeBar then
                        local sb = CreateFrame("StatusBar", nil, rf)
                        sb:SetAllPoints(rf)
                        sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                        sb:SetFrameLevel(rf:GetFrameLevel())
                        sb:SetMinMaxValues(0, 1)
                        -- Apply the same bar texture if one is set
                        if rf._texKey then
                            local texLookup = _G._ERB_BarTextures
                            local path = texLookup and texLookup[rf._texKey]
                            if path then sb:SetStatusBarTexture(path) end
                        end
                        rf._rechargeBar = sb
                    end

                    -- Compute recharge fraction (0 = just started, 1 = almost ready)
                    local frac = 0
                    local rStart, rDur = _runeStart[runeIdx], _runeDuration[runeIdx]
                    if rStart and rDur and rDur > 0 then
                        local elapsed = now - rStart
                        frac = max(0, min(1, elapsed / rDur))
                    end
                    rf._rechargeBar:SetValue(frac)
                    -- 75% brightness while recharging (subtle dim)
                    rf._rechargeBar:SetStatusBarColor(r * 0.75, g * 0.75, b * 0.75, a)
                    rf._rechargeBar:Show()

                    -- Show duration text if Resource Text is enabled (DK runes use it for cooldown)
                    if rf._cdText then
                        local rem = _runeRemaining[runeIdx]
                        if sp.showText and rem > 0 and rem < 999 then
                            rf._cdText:SetText(format("%d", ceil(rem)))
                        else
                            rf._cdText:SetText("")
                        end
                    end
                end
            end
        end
    elseif cachedSecondary.type == "bar" then
        -- Bar-style secondary (e.g. Devourer soul fragments, Elemental maelstrom, Brewmaster stagger)
        if secondaryBar then
            local cur, maxC = 0, maxPts
            if powerType == "SOUL_FRAGMENTS_DEVOURER" and EllesmereUI and EllesmereUI.GetSoulFragments then
                cur, maxC = EllesmereUI.GetSoulFragments()
                if not maxC or maxC <= 0 then maxC = maxPts end
            elseif powerType == "MAELSTROM_BAR" then
                cur = UnitPower("player", PT.MAELSTROM) or 0
                maxC = UnitPowerMax("player", PT.MAELSTROM) or maxPts
                if issecretvalue and issecretvalue(maxC) then maxC = maxPts end
                if maxC <= 0 then maxC = maxPts end
            elseif powerType == "INSANITY_BAR" then
                cur = UnitPower("player", PT.INSANITY) or 0
                maxC = UnitPowerMax("player", PT.INSANITY) or maxPts
                if issecretvalue and issecretvalue(maxC) then maxC = maxPts end
                if maxC <= 0 then maxC = maxPts end
            elseif powerType == "FOCUS_BAR" then
                cur = UnitPower("player", PT.FOCUS) or 0
                maxC = UnitPowerMax("player", PT.FOCUS) or maxPts
                if issecretvalue and issecretvalue(maxC) then maxC = maxPts end
                if maxC <= 0 then maxC = maxPts end
            elseif powerType == "BREWMASTER_STAGGER" then
                cur = UnitStagger("player") or 0
                maxC = UnitHealthMax("player") or 1
                local curTainted = issecretvalue and issecretvalue(cur)
                local maxTainted = issecretvalue and issecretvalue(maxC)
                -- Apply stagger threshold colors only when using default power colors
                if not sp.darkTheme and not sp.classColored then
                    if not curTainted and not maxTainted and maxC > 0 then
                        local pct = cur / maxC
                        if pct >= 0.6 then
                            secondaryBar:GetStatusBarTexture():SetVertexColor(1.0, 0.2, 0.2, 1)
                        elseif pct >= 0.3 then
                            secondaryBar:GetStatusBarTexture():SetVertexColor(1.0, 0.85, 0.2, 1)
                        else
                            secondaryBar:GetStatusBarTexture():SetVertexColor(0.2, 0.8, 0.2, 1)
                        end
                    end
                end
                if maxTainted then maxC = maxPts end
                if not maxTainted and maxC <= 0 then maxC = 1 end
            end
            secondaryBar:SetMinMaxValues(0, maxC)
            -- Apply fill color (dark theme / class colored / custom).
            -- Brewmaster stagger uses threshold colors when neither override
            -- is active; all other cases use r,g,b,a from above.
            -- For bar-type resources (Maelstrom, Insanity), threshold triggers
            -- at or above thresholdCount treated as a percent value.
            if powerType ~= "BREWMASTER_STAGGER" or sp.darkTheme or sp.classColored then
                local ft = secondaryBar:GetStatusBarTexture()
                if ft then
                    local pType = (powerType == "MAELSTROM_BAR") and PT.MAELSTROM
                               or (powerType == "INSANITY_BAR") and PT.INSANITY
                               or (powerType == "FOCUS_BAR") and PT.FOCUS
                               or nil
                    if sp.thresholdEnabled and pType and UnitPowerPercent then
                        -- Use ColorCurve + UnitPowerPercent: WoW evaluates the secret
                        -- value against the curve on the C side, returns a Color object.
                        local curve = GetBarThresholdCurve(
                            r, g, b,
                            sp.thresholdR or 1, sp.thresholdG or 0.2, sp.thresholdB or 0.2,
                            sp.thresholdCount or 30)
                        if curve then
                            local ok, colorResult = pcall(UnitPowerPercent, "player", pType, false, curve)
                            if ok and colorResult and colorResult.GetRGBA then
                                ft:SetVertexColor(colorResult:GetRGBA())
                            else
                                ft:SetVertexColor(r, g, b, a)
                            end
                        else
                            ft:SetVertexColor(r, g, b, a)
                        end
                    else
                        ft:SetVertexColor(r, g, b, a)
                    end
                end
            end
            -- Secret-aware update: pass secret values directly to the
            -- StatusBar (the C widget handles them natively).  Only use
            -- smooth animation for clean numeric values.
            local tainted = issecretvalue and issecretvalue(cur)
            if not tainted then
                secondaryBar._smoothTarget = cur
            else
                secondaryBar:SetValue(cur)
            end
            -- Count text
            if sp.showText and secondaryFrame._countText then
                if not tainted then
                    if powerType == "BREWMASTER_STAGGER" then
                        -- Show stagger as percentage of max health
                        local pct = maxC > 0 and (cur / maxC * 100) or 0
                        secondaryFrame._countText:SetText(format("%d", pct) .. "%")
                    else
                        secondaryFrame._countText:SetText(tostring(cur) .. " / " .. tostring(maxC))
                    end
                else
                    -- Secret value path: try UnitPowerPercent first, fall back to tostring
                    if powerType == "MAELSTROM_BAR" then
                        local pct = UnitPowerPercent and UnitPowerPercent("player", PT.MAELSTROM) or 0
                        if not issecretvalue(pct) then
                            secondaryFrame._countText:SetText(format("%d", pct) .. "%")
                        else
                            secondaryFrame._countText:SetText(tostring(cur))
                        end
                    elseif powerType == "INSANITY_BAR" then
                        local pct = UnitPowerPercent and UnitPowerPercent("player", PT.INSANITY) or 0
                        if not issecretvalue(pct) then
                            secondaryFrame._countText:SetText(format("%d", pct) .. "%")
                        else
                            secondaryFrame._countText:SetText(tostring(cur))
                        end
                    elseif powerType == "FOCUS_BAR" then
                        local pct = UnitPowerPercent and UnitPowerPercent("player", PT.FOCUS) or 0
                        if not issecretvalue(pct) then
                            secondaryFrame._countText:SetText(format("%d", pct) .. "%")
                        else
                            secondaryFrame._countText:SetText(tostring(cur))
                        end
                    else
                        secondaryFrame._countText:SetText(tostring(cur))
                    end
                end
            end
        end
    elseif cachedSecondary.type == "custom" then
        local cur, maxC = 0, maxPts
        local isSecret = false
        if powerType == "SOUL_FRAGMENTS_VENGEANCE" then
            -- Vengeance DH: GetSpellCastCount returns a SECRET value in 12.0+.
            -- We cannot compare it in Lua.  Instead we pass the raw value to
            -- StatusBar widgets embedded in each pip (SetMinMaxValues(i-1, i)
            -- + SetValue(secret)) which fill/empty entirely on the C side.
            local rawCur = C_Spell and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(228477) or 0
            cur = rawCur
            isSecret = true
            maxC = 6
        elseif powerType == "SOUL_FRAGMENTS" and EllesmereUI and EllesmereUI.GetSoulFragments then
            cur, maxC = EllesmereUI.GetSoulFragments()
            if not maxC or maxC <= 0 then maxC = maxPts end
        elseif powerType == "MAELSTROM_WEAPON" and EllesmereUI and EllesmereUI.GetMaelstromWeapon then
            cur, maxC = EllesmereUI.GetMaelstromWeapon()
        elseif powerType == "TIP_OF_THE_SPEAR" and EllesmereUI and EllesmereUI.GetTipOfTheSpear then
            cur, maxC = EllesmereUI.GetTipOfTheSpear()
        elseif powerType == "WHIRLWIND_STACKS" and EllesmereUI and EllesmereUI.GetWhirlwindStacks then
            cur, maxC = EllesmereUI.GetWhirlwindStacks()
            if not maxC or maxC <= 0 then
                for i = 1, #pips do if pips[i] then pips[i]:Hide() end end
                return
            end
        end
        -- Use custom resource color from EllesmereUI if available
        local _, classFile = UnitClass("player")
        if sp.classColored and EllesmereUI and EllesmereUI.GetResourceColor then
            local rc = EllesmereUI.GetResourceColor(classFile)
            if rc then r, g, b = rc.r, rc.g, rc.b end
        end

        if isSecret then
            -- Secret-value path: drive each pip via a StatusBar overlay.
            -- The StatusBar accepts the secret number natively; when the
            -- value falls within [i-1, i] the bar fills proportionally,
            -- giving us a binary active/inactive look for integer counts.
            for i = 1, maxC do
                local pip = pips[i]
                if pip and pip:IsShown() then
                    -- Lazily create a StatusBar overlay inside the pip
                    if not pip._secretBar then
                        local sb = CreateFrame("StatusBar", nil, pip)
                        sb:SetAllPoints(pip._fill)
                        sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                        sb:SetStatusBarColor(r, g, b, a)
                        sb:SetFrameLevel(pip:GetFrameLevel())
                        pip._secretBar = sb
                    end
                    pip._secretBar:SetMinMaxValues(i - 1, i)
                    pip._secretBar:SetValue(cur)
                    pip._secretBar:SetStatusBarColor(r, g, b, a)
                    pip._secretBar:Show()
                    -- Hide the normal fill; the StatusBar replaces it
                    pip._fill:Hide()
                end
            end
            -- Count text -- tostring handles secret values safely
            if sp.showText and secondaryFrame._countText then
                secondaryFrame._countText:SetText(tostring(cur))
            end
        else
            -- Clean-value path: normal boolean comparisons
            -- Hide any leftover secret StatusBar overlays
            for i = 1, maxC do
                if pips[i] and pips[i]._secretBar then pips[i]._secretBar:Hide() end
            end
            local useThresh = sp.thresholdEnabled and cur >= sp.thresholdCount
            local tr, tg, tb = sp.thresholdR, sp.thresholdG, sp.thresholdB
            for i = 1, maxC do
                if pips[i] and pips[i]:IsShown() then
                    local active = i <= cur
                    if active and useThresh then
                        if sp.thresholdPartialOnly and i < sp.thresholdCount then
                            pips[i]:SetActive(true, r, g, b, a)
                        else
                            pips[i]:SetActive(true, tr, tg, tb)
                        end
                    else
                        pips[i]:SetActive(active, r, g, b, a)
                    end
                end
            end
            -- Count text
            if sp.showText and secondaryFrame._countText then
                secondaryFrame._countText:SetText(tostring(cur))
            end
        end
    else
        local cur = UnitPower("player", powerType)
        local useThresh = sp.thresholdEnabled and cur >= sp.thresholdCount
        local tr, tg, tb = sp.thresholdR, sp.thresholdG, sp.thresholdB

        -- Charged combo points (e.g. Supercharger talent)
        local chargedSet
        if powerType == PT.COMBO then
            local fn = GetUnitChargedPowerPoints
            if fn then
                local pts = fn("player")
                if pts and #pts > 0 then
                    chargedSet = {}
                    for _, idx in ipairs(pts) do chargedSet[idx] = true end
                end
            end
        end
        local cr, cg, cb, ca = sp.chargedR or 0.44, sp.chargedG or 0.77, sp.chargedB or 1.00, sp.chargedA or 1

        for i = 1, maxPts do
            if pips[i] and pips[i]:IsShown() then
                local active = i <= cur
                if chargedSet and chargedSet[i] then
                    if active then
                        pips[i]:SetActive(true, cr, cg, cb, ca)
                    else
                        pips[i]:SetActive(true, cr * 0.5, cg * 0.5, cb * 0.5, ca)
                    end
                elseif active and useThresh then
                    if sp.thresholdPartialOnly and i < sp.thresholdCount then
                        pips[i]:SetActive(true, r, g, b, a)
                    else
                        pips[i]:SetActive(true, tr, tg, tb)
                    end
                else
                    pips[i]:SetActive(active, r, g, b, a)
                end
            end
        end
        -- Count text
        if sp.showText and secondaryFrame._countText then
            secondaryFrame._countText:SetText(tostring(cur))
        end
    end
end


-------------------------------------------------------------------------------
--  Visibility & combat fade
-------------------------------------------------------------------------------
local function ShouldShowSecondary()
    local vis = ERB.db.profile.secondary.visibility
    if vis == "always" then return true end
    if vis == "combat" then return isInCombat end
    if vis == "target" then return UnitExists("target") and UnitCanAttack("player", "target") end
    return true
end

local function ShouldShowBar(barProfile)
    local vis = barProfile.visibility or "always"
    if vis == "always" then return true end
    if vis == "combat" then return isInCombat end
    if vis == "target" then return UnitExists("target") and UnitCanAttack("player", "target") end
    return true
end

local function UpdateVisibility()
    if not mainFrame then return end

    -- Main frame always shown
    mainFrame:Show()
    mainFrame:SetAlpha(1)

    local inVehicle = ERB._inVehicle

    -- Health bar visibility
    if healthBar then
        local hp = ERB.db.profile.health
        if hp and hp.enabled and ShouldShowBar(hp) and not inVehicle then
            healthBar:Show()
            healthBar:SetAlpha(hp.barAlpha or 1)
        else
            healthBar:Hide()
        end
    end

    -- Power bar visibility
    if primaryBar then
        local pp = ERB.db.profile.primary
        if pp and pp.enabled ~= false and ShouldShowBar(pp) and not inVehicle then
            primaryBar:Show()
            primaryBar:SetAlpha(pp.barAlpha or 1)
        else
            primaryBar:Hide()
        end
    end

    -- Secondary resource visibility + ooc alpha
    if secondaryFrame then
        local sp = ERB.db.profile.secondary
        if sp and sp.enabled ~= false and cachedSecondary and ShouldShowSecondary() and not inVehicle then
            secondaryFrame:Show()
            local base = sp.barAlpha or 1
            local ooc = isInCombat and 1 or (sp.oocAlpha or 1)
            secondaryFrame:SetAlpha(base * ooc)
        else
            secondaryFrame:Hide()
        end
    end
end

-------------------------------------------------------------------------------
--  OnUpdate: smooth bar animation
-------------------------------------------------------------------------------
local SMOOTH_SPEED = 8
local _runeThrottle = 0

local function OnUpdate(self, dt)
    -- Smooth bar animation (health)
    if healthBar and healthBar:IsShown() then
        local tgt = healthBar._smoothTarget
        if issecretvalue and issecretvalue(tgt) then
            healthBar:SetValue(tgt)
        else
            local cur = healthBar._smoothCurrent
            if abs(cur - tgt) > 1 then
                cur = Lerp(cur, tgt, min(1, dt * SMOOTH_SPEED))
                healthBar._smoothCurrent = cur
                healthBar:SetValue(cur)
            end
        end
    end

    -- Smooth bar animation (primary resource)
    if primaryBar and primaryBar:IsShown() then
        local tgt = primaryBar._smoothTarget
        if issecretvalue and issecretvalue(tgt) then
            primaryBar:SetValue(tgt)
        else
            local cur = primaryBar._smoothCurrent
            if abs(cur - tgt) > 1 then
                cur = Lerp(cur, tgt, min(1, dt * SMOOTH_SPEED))
                primaryBar._smoothCurrent = cur
                primaryBar:SetValue(cur)
            end
        end
    end

    -- Smooth bar animation (bar-style secondary, e.g. Devourer / Elemental maelstrom)
    if secondaryBar and secondaryBar:IsShown() then
        local tgt = secondaryBar._smoothTarget
        if issecretvalue and issecretvalue(tgt) then
            secondaryBar:SetValue(tgt)
        else
            local cur = secondaryBar._smoothCurrent
            if abs(cur - tgt) > 0.5 then
                cur = Lerp(cur, tgt, min(1, dt * SMOOTH_SPEED))
                secondaryBar._smoothCurrent = cur
                secondaryBar:SetValue(cur)
            end
        end
    end

    -- DK rune updates (throttled to ~10 fps) � calls the full sorted
    -- update so rune positions stay consistent with depletion order.
    if cachedSecondary and cachedSecondary.type == "runes" then
        _runeThrottle = _runeThrottle + dt
        if _runeThrottle >= 0.1 then
            _runeThrottle = 0
            UpdateSecondaryResource()
        end
    end

    -- Cast bar update
    UpdateCastBar(dt)

    -- Throttled poll for Vengeance soul fragments (GetSpellCastCount has no
    -- discrete event) and as a safety net for other custom/bar resources.
    if cachedSecondary and (cachedSecondary.type == "custom" or cachedSecondary.type == "bar") then
        _runeThrottle = _runeThrottle + dt  -- reuse the rune throttle counter
        if _runeThrottle >= 0.1 then
            _runeThrottle = 0
            UpdateSecondaryResource()
        end
    end
end


-------------------------------------------------------------------------------
--  Bar Textures (shared with options)
-------------------------------------------------------------------------------
local TEX_BASE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local CAST_BAR_TEXTURES = {
    ["none"]          = nil,
    ["blizzard"]      = "ATLAS",
    ["beautiful"]     = TEX_BASE .. "beautiful.tga",
    ["plating"]       = TEX_BASE .. "plating.tga",
    ["atrocity"]      = TEX_BASE .. "atrocity.tga",
    ["divide"]        = TEX_BASE .. "divide.tga",
    ["glass"]         = TEX_BASE .. "glass.tga",
    ["gradient-lr"]   = TEX_BASE .. "gradient-lr.tga",
    ["gradient-rl"]   = TEX_BASE .. "gradient-rl.tga",
    ["gradient-bt"]   = TEX_BASE .. "gradient-bt.tga",
    ["gradient-tb"]   = TEX_BASE .. "gradient-tb.tga",
    ["matte"]         = TEX_BASE .. "matte.tga",
    ["sheer"]         = TEX_BASE .. "sheer.tga",
}
local CAST_BAR_TEXTURE_ORDER = {
    "none", "blizzard",
    "beautiful", "plating",
    "atrocity", "divide", "glass",
    "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
    "matte", "sheer",
}
local CAST_BAR_TEXTURE_NAMES = {
    ["none"]        = "None",
    ["blizzard"]    = "Blizzard",
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
-- Expose for options
_G._ERB_CastBarTextures     = CAST_BAR_TEXTURES
_G._ERB_CastBarTextureOrder = CAST_BAR_TEXTURE_ORDER
_G._ERB_CastBarTextureNames = CAST_BAR_TEXTURE_NAMES

-------------------------------------------------------------------------------
--  Health/Power bar texture tables (shared with options dropdown)
-------------------------------------------------------------------------------
local BAR_TEX_BASE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local BAR_TEXTURES = {
    ["none"]          = nil,
    ["beautiful"]     = BAR_TEX_BASE .. "beautiful.tga",
    ["plating"]       = BAR_TEX_BASE .. "plating.tga",
    ["atrocity"]      = BAR_TEX_BASE .. "atrocity.tga",
    ["divide"]        = BAR_TEX_BASE .. "divide.tga",
    ["glass"]         = BAR_TEX_BASE .. "glass.tga",
    ["gradient-lr"]   = BAR_TEX_BASE .. "gradient-lr.tga",
    ["gradient-rl"]   = BAR_TEX_BASE .. "gradient-rl.tga",
    ["gradient-bt"]   = BAR_TEX_BASE .. "gradient-bt.tga",
    ["gradient-tb"]   = BAR_TEX_BASE .. "gradient-tb.tga",
    ["matte"]         = BAR_TEX_BASE .. "matte.tga",
    ["sheer"]         = BAR_TEX_BASE .. "sheer.tga",
}
local BAR_TEXTURE_ORDER = {
    "none", "beautiful", "plating",
    "atrocity", "divide", "glass",
    "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
    "matte", "sheer",
}
local BAR_TEXTURE_NAMES = {
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
_G._ERB_BarTextures     = BAR_TEXTURES
_G._ERB_BarTextureOrder = BAR_TEXTURE_ORDER
_G._ERB_BarTextureNames = BAR_TEXTURE_NAMES

-------------------------------------------------------------------------------
--  Append SharedMedia statusbar textures to both texture tables
--  (deferred to OnInitialize so all addons have registered their textures)
-------------------------------------------------------------------------------
local function AppendSharedMediaTextures()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    local smTextures = LSM:HashTable("statusbar")
    if not smTextures then return end

    -- Collect and sort SharedMedia texture names alphabetically
    local sorted = {}
    for name in pairs(smTextures) do
        -- Skip any that duplicate our built-in keys
        local lk = name:lower():gsub("%s+", "-")
        if not CAST_BAR_TEXTURES[lk] and not BAR_TEXTURES[lk] then
            sorted[#sorted + 1] = name
        end
    end
    table.sort(sorted)

    if #sorted > 0 then
        -- Add separator + SharedMedia entries to cast bar textures
        CAST_BAR_TEXTURE_ORDER[#CAST_BAR_TEXTURE_ORDER + 1] = "---"
        for _, name in ipairs(sorted) do
            local key = "sm:" .. name
            CAST_BAR_TEXTURES[key] = smTextures[name]
            CAST_BAR_TEXTURE_ORDER[#CAST_BAR_TEXTURE_ORDER + 1] = key
            CAST_BAR_TEXTURE_NAMES[key] = name
        end

        -- Add separator + SharedMedia entries to bar textures
        BAR_TEXTURE_ORDER[#BAR_TEXTURE_ORDER + 1] = "---"
        for _, name in ipairs(sorted) do
            local key = "sm:" .. name
            BAR_TEXTURES[key] = smTextures[name]
            BAR_TEXTURE_ORDER[#BAR_TEXTURE_ORDER + 1] = key
            BAR_TEXTURE_NAMES[key] = name
        end
    end
end


-------------------------------------------------------------------------------
--  Player Cast Bar
-------------------------------------------------------------------------------
local SPARK_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\cast_spark.tga"

BuildCastBar = function()
    local cb = ERB.db.profile.castBar

    -- Hide/show Blizzard default cast bar
    -- IMPORTANT: We reparent the bar to a hidden frame instead of calling
    -- Hide() or replacing Show().  Directly hiding or unregistering events
    -- taints the secure frame, which causes errors on empowered spell casts
    -- (CastingBarFrame.lua "attempt to compare secret string value").
    -- Reparenting removes it from the visible hierarchy cleanly.
    -- This also keeps the frame in the layout system so other addons
    -- that anchor to it aren't disrupted.
    local blizzBar = PlayerCastingBarFrame
    if blizzBar then
        if cb.enabled then
            -- Create a hidden parent frame once
            if not ERB._hiddenParent then
                ERB._hiddenParent = CreateFrame("Frame")
                ERB._hiddenParent:Hide()
            end
            -- Always re-apply: Blizzard may re-parent the bar on spec change
            -- or other UI resets, so we can't rely on a cached flag.
            blizzBar._erbOrigParent = blizzBar._erbOrigParent or blizzBar:GetParent()
            local curParent = blizzBar:GetParent()
            if curParent ~= ERB._hiddenParent then
                blizzBar:SetParent(ERB._hiddenParent)
            end
            blizzBar._erbHidden = true

            -- Prevent Blizzard from reparenting the cast bar back during
            -- Edit Mode enter/exit or layout changes.  Use a guard flag
            -- so our own SetParent calls (restore path) still work.
            if not blizzBar._erbSetParentHooked then
                blizzBar._erbSetParentHooked = true
                hooksecurefunc(blizzBar, "SetParent", function(self, newParent)
                    if self._erbHidden and newParent ~= ERB._hiddenParent then
                        C_Timer.After(0, function()
                            if self._erbHidden and not InCombatLockdown() then
                                self:SetParent(ERB._hiddenParent)
                            end
                        end)
                    end
                end)
            end

            -- Hide the Edit Mode selection overlay so the cast bar cannot
            -- be selected or highlighted in Blizzard Edit Mode.
            if blizzBar.Selection and not blizzBar._erbSelectionHooked then
                blizzBar._erbSelectionHooked = true
                blizzBar.Selection:SetAlpha(0)
                blizzBar.Selection:EnableMouse(false)
                hooksecurefunc(blizzBar.Selection, "Show", function(self)
                    if blizzBar._erbHidden then
                        self:SetAlpha(0)
                        self:EnableMouse(false)
                    end
                end)
            end
        else
            if blizzBar._erbHidden then
                blizzBar._erbHidden = false
                -- Restore to original parent
                if blizzBar._erbOrigParent then
                    blizzBar:SetParent(blizzBar._erbOrigParent)
                end
                -- Restore Edit Mode selection overlay
                if blizzBar.Selection then
                    blizzBar.Selection:SetAlpha(1)
                    blizzBar.Selection:EnableMouse(true)
                end
                -- Nudge SetUnit so it picks up any cast already in progress
                if blizzBar.SetUnit then
                    blizzBar:SetUnit("player")
                end
            end
        end
    end

    if not cb.enabled then
        if castBarFrame then castBarFrame:Hide() end
        return
    end

    if not castBarFrame then
        castBarFrame = CreateFrame("Frame", "ERB_CastBarFrame", UIParent)
        castBarFrame:SetFrameStrata("MEDIUM")
        castBarFrame:SetFrameLevel(10)

        -- Background
        local bg = castBarFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        castBarFrame._bg = bg

        -- Border (simple 4-edge)
        local function MkEdge()
            local t = castBarFrame:CreateTexture(nil, "BORDER", nil, 7)
            return t
        end
        castBarFrame._bT = MkEdge()
        castBarFrame._bB = MkEdge()
        castBarFrame._bL = MkEdge()
        castBarFrame._bR = MkEdge()

        -- Status bar
        local bar = CreateFrame("StatusBar", "ERB_CastBar", castBarFrame)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        castBarFrame._bar = bar

        -- Spark
        local spark = bar:CreateTexture(nil, "OVERLAY", nil, 1)
        spark:SetTexture(SPARK_TEX)
        spark:SetBlendMode("ADD")
        castBarFrame._spark = spark

        -- Spell icon
        local iconFrame = CreateFrame("Frame", nil, castBarFrame)
        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        castBarFrame._iconFrame = iconFrame
        castBarFrame._icon = icon

        -- Spell name text
        local nameText = bar:CreateFontString(nil, "OVERLAY")
        SetRBFont(nameText, GetRBFont(), 11)
        nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
        nameText:SetJustifyH("LEFT")
        castBarFrame._nameText = nameText

        -- Timer text
        local timerText = bar:CreateFontString(nil, "OVERLAY")
        SetRBFont(timerText, GetRBFont(), 11)
        timerText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        timerText:SetJustifyH("RIGHT")
        castBarFrame._timerText = timerText

        -- Casting state
        castBarFrame._casting = false
        castBarFrame._channeling = false
        castBarFrame._empowering = false
        castBarFrame._castID = nil
        castBarFrame._startTime = 0
        castBarFrame._endTime = 0
        castBarFrame._spellName = ""
        castBarFrame._pips = {}
        castBarFrame._numStages = 0
    end

    -- Apply settings
    local w, h = cb.width, cb.height
    local bs = cb.borderSize
    local hasIcon = cb.showIcon ~= false
    -- Total frame width includes icon (h x h) only when icon is shown
    local totalW = hasIcon and (w + h) or w
    if cb.unlockPos and cb.unlockPos.point then
        -- Position managed by unlock mode -- only animate size changes
        local rp = cb.unlockPos.relPoint or cb.unlockPos.point
        local px, py = cb.unlockPos.x or 0, cb.unlockPos.y or 0
        local function ApplyCastUnlockTransform()
            local aw = castBarFrame["_barAnim_w"] or totalW
            local ah = castBarFrame["_barAnim_h"] or h
            castBarFrame:SetScale(cb.scale or 1)
            castBarFrame:SetSize(aw, ah)
            castBarFrame:ClearAllPoints()
            castBarFrame:SetPoint(cb.unlockPos.point, UIParent, rp, px, py)
        end
        SmoothBarAnimate(castBarFrame, "w", totalW, function() ApplyCastUnlockTransform() end)
        SmoothBarAnimate(castBarFrame, "h", h, function() ApplyCastUnlockTransform() end)
    else
        castBarFrame:SetScale(cb.scale or 1)
        castBarFrame:SetSize(totalW, h)
        castBarFrame:ClearAllPoints()
        castBarFrame:SetPoint("CENTER", UIParent, "CENTER", cb.anchorX, cb.anchorY)
    end

    -- Border (wraps the full container including icon)
    local br, bg2, bb, ba = cb.borderR, cb.borderG, cb.borderB, cb.borderA
    for _, edge in ipairs({ castBarFrame._bT, castBarFrame._bB, castBarFrame._bL, castBarFrame._bR }) do
        edge:SetColorTexture(br, bg2, bb, ba)
    end
    castBarFrame._bT:ClearAllPoints()
    castBarFrame._bT:SetPoint("TOPLEFT", castBarFrame, "TOPLEFT", 0, 0)
    castBarFrame._bT:SetPoint("TOPRIGHT", castBarFrame, "TOPRIGHT", 0, 0)
    castBarFrame._bT:SetHeight(bs)
    castBarFrame._bB:ClearAllPoints()
    castBarFrame._bB:SetPoint("BOTTOMLEFT", castBarFrame, "BOTTOMLEFT", 0, 0)
    castBarFrame._bB:SetPoint("BOTTOMRIGHT", castBarFrame, "BOTTOMRIGHT", 0, 0)
    castBarFrame._bB:SetHeight(bs)
    castBarFrame._bL:ClearAllPoints()
    castBarFrame._bL:SetPoint("TOPLEFT", castBarFrame._bT, "BOTTOMLEFT", 0, 0)
    castBarFrame._bL:SetPoint("BOTTOMLEFT", castBarFrame._bB, "TOPLEFT", 0, 0)
    castBarFrame._bL:SetWidth(bs)
    castBarFrame._bR:ClearAllPoints()
    castBarFrame._bR:SetPoint("TOPRIGHT", castBarFrame._bT, "BOTTOMRIGHT", 0, 0)
    castBarFrame._bR:SetPoint("BOTTOMRIGHT", castBarFrame._bB, "TOPRIGHT", 0, 0)
    castBarFrame._bR:SetWidth(bs)

    -- Icon: left side of the container, inset by border size to sit within the border
    local iconFrame = castBarFrame._iconFrame
    if hasIcon then
        local iSize = h - 2 * bs
        if iSize < 1 then iSize = 1 end
        iconFrame:SetSize(iSize, iSize)
        iconFrame:ClearAllPoints()
        iconFrame:SetPoint("TOPLEFT", castBarFrame, "TOPLEFT", bs, -bs)
        iconFrame:Show()
    else
        iconFrame:Hide()
    end

    -- Bar: right of the icon (or full width when no icon), inset by border
    local bar = castBarFrame._bar
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", castBarFrame, "TOPLEFT", (hasIcon and h or 0) + bs, -bs)
    bar:SetPoint("BOTTOMRIGHT", castBarFrame, "BOTTOMRIGHT", -bs, bs)

    -- Bar texture
    local texKey = cb.texture
    local isBlizzard = (texKey == "blizzard")
    if isBlizzard then
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        bar:GetStatusBarTexture():SetAtlas("UI-CastingBar-Fill", true)
        castBarFrame._bg:SetAtlas("UI-CastingBar-Background", true)
        castBarFrame._bg:ClearAllPoints()
        castBarFrame._bg:SetAllPoints(castBarFrame)
    else
        local texPath = CAST_BAR_TEXTURES[texKey]
        if texPath then
            bar:SetStatusBarTexture(texPath)
        else
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        end
        castBarFrame._bg:SetTexture(nil)
        castBarFrame._bg:SetColorTexture(cb.bgR, cb.bgG, cb.bgB, cb.bgA)
    end

    -- Bar color / gradient
    local fillTex = bar:GetStatusBarTexture()
    if cb.gradientEnabled then
        local dir = cb.gradientDir or "HORIZONTAL"
        -- Clip-frame approach: a child frame sized to the fill width clips
        -- a full-bar-width gradient texture inside it, so the gradient always
        -- maps across the entire bar regardless of fill progress.
        fillTex:SetVertexColor(1, 1, 1, 0)  -- hide the status bar fill
        if not castBarFrame._gradClip then
            local clip = CreateFrame("Frame", nil, bar)
            clip:SetClipsChildren(true)
            clip:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            clip:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            clip:SetWidth(0.01)
            clip:SetFrameLevel(bar:GetFrameLevel() + 1)
            local tex = clip:CreateTexture(nil, "ARTWORK", nil, 1)
            tex:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            tex:SetColorTexture(1, 1, 1, 1)
            castBarFrame._gradClip = clip
            castBarFrame._gradTex = tex
            -- Text overlay frame above the clip so text isn't hidden
            local textOverlay = CreateFrame("Frame", nil, bar)
            textOverlay:SetAllPoints(bar)
            textOverlay:SetFrameLevel(clip:GetFrameLevel() + 1)
            castBarFrame._textOverlay = textOverlay
        end
        -- Reparent text to the overlay frame so it draws above the gradient
        castBarFrame._nameText:SetParent(castBarFrame._textOverlay)
        castBarFrame._timerText:SetParent(castBarFrame._textOverlay)
        local clip = castBarFrame._gradClip
        local tex = castBarFrame._gradTex
        tex:SetGradient(dir,
            CreateColor(cb.fillR, cb.fillG, cb.fillB, cb.fillA),
            CreateColor(cb.gradientR, cb.gradientG, cb.gradientB, cb.gradientA))
        clip:SetWidth(0.01)
        clip:Show()
        castBarFrame._gradientFullBar = true
        -- Clean up old overlay if present
        if castBarFrame._gradientOverlay then castBarFrame._gradientOverlay:Hide() end
    else
        fillTex:SetVertexColor(cb.fillR, cb.fillG, cb.fillB, cb.fillA)
        castBarFrame._gradientFullBar = false
        if castBarFrame._gradClip then castBarFrame._gradClip:Hide() end
        -- Reparent text back to bar when gradient is off
        castBarFrame._nameText:SetParent(bar)
        castBarFrame._timerText:SetParent(bar)
    end

    -- Spark
    local spark = castBarFrame._spark
    if cb.showSpark then
        spark:SetSize(8, h)
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", fillTex, "RIGHT", 0, 0)
        spark:Show()
    else
        spark:Hide()
    end


    -- Timer text
    local timerText = castBarFrame._timerText
    if cb.showTimer then
        SetRBFont(timerText, GetRBFont(), cb.timerSize or 11)
        timerText:ClearAllPoints()
        timerText:SetPoint("RIGHT", bar, "RIGHT", -4 + (cb.timerX or 0), cb.timerY or 0)
        timerText:Show()
    else
        timerText:Hide()
    end

    -- Spell name text
    local nameText = castBarFrame._nameText
    if cb.showSpellText then
        SetRBFont(nameText, GetRBFont(), cb.spellTextSize or 11)
        nameText:ClearAllPoints()
        nameText:SetPoint("LEFT", bar, "LEFT", 4 + (cb.spellTextX or 0), cb.spellTextY or 0)
        nameText:SetWidth(cb.width * 0.9)
        nameText:Show()
    else
        nameText:Hide()
    end

    -- Hide pips when not empowering
    if castBarFrame._pips then
        for i = 1, #castBarFrame._pips do
            castBarFrame._pips[i]:Hide()
        end
    end

    -- Hide when not casting
    if not castBarFrame._casting and not castBarFrame._channeling and not castBarFrame._empowering then
        castBarFrame:Hide()
    else
        castBarFrame:Show()
    end
end


UpdateCastBar = function(dt)
    if not castBarFrame or not castBarFrame:IsShown() then return end
    local now = GetTime()
    local bar = castBarFrame._bar
    local showTimer = ERB.db.profile.castBar.showTimer

    if castBarFrame._casting or castBarFrame._empowering then
        local progress = (now - castBarFrame._startTime) / (castBarFrame._endTime - castBarFrame._startTime)
        progress = min(max(progress, 0), 1)
        bar:SetValue(progress)
        -- Size the gradient clip frame to match the fill width
        if castBarFrame._gradientFullBar and castBarFrame._gradClip then
            castBarFrame._gradClip:SetWidth(max(0.01, bar:GetWidth() * progress))
        end
        if showTimer then
            local remaining = castBarFrame._endTime - now
            if remaining > 0 then
                castBarFrame._timerText:SetText(format("%.1f", remaining))
            else
                castBarFrame._timerText:SetText("")
            end
        end
    elseif castBarFrame._channeling then
        local progress = (castBarFrame._endTime - now) / (castBarFrame._endTime - castBarFrame._startTime)
        progress = min(max(progress, 0), 1)
        bar:SetValue(progress)
        -- Size the gradient clip frame to match the fill width
        if castBarFrame._gradientFullBar and castBarFrame._gradClip then
            castBarFrame._gradClip:SetWidth(max(0.01, bar:GetWidth() * progress))
        end
        if showTimer then
            local remaining = castBarFrame._endTime - now
            if remaining > 0 then
                castBarFrame._timerText:SetText(format("%.1f", remaining))
            else
                castBarFrame._timerText:SetText("")
            end
        end
    end

    -- Update spark position
    if castBarFrame._spark:IsShown() then
        castBarFrame._spark:ClearAllPoints()
        castBarFrame._spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    end
end

OnCastStart = function()
    if not castBarFrame then return end
    local cb = ERB.db.profile.castBar
    if not cb.enabled then return end

    local name, _, _, startTimeMS, endTimeMS, _, _, notInterruptible, spellID, barID = UnitCastingInfo("player")
    if not name then return end

    castBarFrame._casting = true
    castBarFrame._channeling = false
    castBarFrame._empowering = false
    castBarFrame._castID = barID
    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
    castBarFrame._spellName = name
    castBarFrame._nameText:SetText(name)
    castBarFrame._bar:SetValue(0)

    -- Hide empower pips
    if castBarFrame._pips then
        for i = 1, #castBarFrame._pips do castBarFrame._pips[i]:Hide() end
    end
    castBarFrame._numStages = 0

    -- Icon
    do
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        local iconTex = spellInfo and spellInfo.iconID
        if iconTex and ERB.db.profile.castBar.showIcon ~= false then
            castBarFrame._icon:SetTexture(iconTex)
            castBarFrame._iconFrame:Show()
        else
            castBarFrame._iconFrame:Hide()
        end
    end

    castBarFrame:Show()
end

OnChannelStart = function()
    if not castBarFrame then return end
    local cb = ERB.db.profile.castBar
    if not cb.enabled then return end

    local name, _, _, startTimeMS, endTimeMS, _, notInterruptible, spellID, _, _, channelCastID = UnitChannelInfo("player")
    if not name then return end

    castBarFrame._casting = false
    castBarFrame._channeling = true
    castBarFrame._empowering = false
    castBarFrame._castID = channelCastID
    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
    castBarFrame._spellName = name
    castBarFrame._nameText:SetText(name)
    castBarFrame._bar:SetValue(1)

    -- Hide empower pips
    if castBarFrame._pips then
        for i = 1, #castBarFrame._pips do castBarFrame._pips[i]:Hide() end
    end
    castBarFrame._numStages = 0

    -- Icon
    do
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        local iconTex = spellInfo and spellInfo.iconID
        if iconTex and ERB.db.profile.castBar.showIcon ~= false then
            castBarFrame._icon:SetTexture(iconTex)
            castBarFrame._iconFrame:Show()
        else
            castBarFrame._iconFrame:Hide()
        end
    end

    castBarFrame:Show()
end

-- Called for UNIT_SPELLCAST_STOP only (normal cast completion).
-- Ignores the event if the castID doesn't match the active cast -- this
-- prevents hiding the bar when a new cast has already started.
local function OnCastComplete(eventCastID)
    if not castBarFrame then return end
    if not castBarFrame._casting then return end
    if not eventCastID or not castBarFrame._castID or eventCastID ~= castBarFrame._castID then return end
    castBarFrame._casting = false
    castBarFrame._castID = nil
    castBarFrame:Hide()
end

-- Called for UNIT_SPELLCAST_FAILED / INTERRUPTED.
-- These fire for the spell that FAILED, which may be a completely different
-- spell than the one currently being cast (e.g. pressing an instant while
-- casting). Only hide if the castID matches our active cast.
local function OnCastFailed(eventCastID)
    if not castBarFrame then return end
    if not castBarFrame._casting then return end
    if not eventCastID or not castBarFrame._castID or eventCastID ~= castBarFrame._castID then return end
    castBarFrame._casting = false
    castBarFrame._castID = nil
    castBarFrame:Hide()
end

-- Called for UNIT_SPELLCAST_CHANNEL_STOP.
local function OnChannelStop(eventCastID)
    if not castBarFrame then return end
    if not castBarFrame._channeling then return end
    if not eventCastID or not castBarFrame._castID or eventCastID ~= castBarFrame._castID then return end
    castBarFrame._channeling = false
    castBarFrame._castID = nil
    castBarFrame:Hide()
end

-- Called for UNIT_SPELLCAST_EMPOWER_STOP.
local function OnEmpowerStop(eventCastID)
    if not castBarFrame then return end
    if not castBarFrame._empowering then return end
    if not eventCastID or not castBarFrame._castID or eventCastID ~= castBarFrame._castID then return end
    castBarFrame._empowering = false
    castBarFrame._castID = nil
    if castBarFrame._pips then
        for i = 1, #castBarFrame._pips do
            castBarFrame._pips[i]:Hide()
        end
    end
    castBarFrame._numStages = 0
    castBarFrame:Hide()
end

OnCastStop = function()
    if not castBarFrame then return end
    castBarFrame._casting = false
    castBarFrame._channeling = false
    castBarFrame._empowering = false
    castBarFrame._castID = nil
    -- Hide pip textures
    if castBarFrame._pips then
        for i = 1, #castBarFrame._pips do
            castBarFrame._pips[i]:Hide()
        end
    end
    castBarFrame._numStages = 0
    castBarFrame:Hide()
end


OnEmpowerStart = function()
    if not castBarFrame then return end
    local cb = ERB.db.profile.castBar
    if not cb.enabled then return end

    local name, _, _, startTimeMS, endTimeMS, _, notInterruptible, spellID, empowering, _, empowerCastID = UnitChannelInfo("player")
    if not name or not empowering then return end

    -- Add hold-at-max time to the end
    local holdAtMax = GetUnitEmpowerHoldAtMaxTime("player")
    endTimeMS = endTimeMS + holdAtMax

    castBarFrame._casting = false
    castBarFrame._channeling = false
    castBarFrame._empowering = true
    castBarFrame._castID = empowerCastID
    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
    castBarFrame._spellName = name
    castBarFrame._nameText:SetText(name)
    castBarFrame._bar:SetValue(0)

    -- Icon
    do
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        local iconTex = spellInfo and spellInfo.iconID
        if iconTex and ERB.db.profile.castBar.showIcon ~= false then
            castBarFrame._icon:SetTexture(iconTex)
            castBarFrame._iconFrame:Show()
        else
            castBarFrame._iconFrame:Hide()
        end
    end

    -- Stage pips (hash marks) -- pixel-perfect positioning
    local stages = UnitEmpoweredStagePercentages("player")
    if stages then
        local bar = castBarFrame._bar
        local barWidth = bar:GetWidth()
        local barHeight = bar:GetHeight()
        local numStages = #stages
        castBarFrame._numStages = numStages

        -- Compute the effective scale so we can snap to physical pixels
        local effectiveScale = bar:GetEffectiveScale()
        local pixelSize = 1 / effectiveScale          -- 1 physical pixel in UI units
        local pipWidth = max(pixelSize, floor(2 * effectiveScale + 0.5) / effectiveScale) -- at least 1px, target ~2px

        -- Position a pip at each stage boundary (skip the last -- it's the bar end)
        local lastOffset = 0
        for i = 1, numStages - 1 do
            local pip = castBarFrame._pips[i]
            if not pip then
                pip = bar:CreateTexture(nil, "OVERLAY", nil, 2)
                pip:SetColorTexture(1, 1, 1, 0.85)
                castBarFrame._pips[i] = pip
            end
            local rawOffset = lastOffset + (barWidth * stages[i])
            lastOffset = rawOffset
            -- Snap offset to nearest physical pixel
            local snappedOffset = floor(rawOffset * effectiveScale + 0.5) / effectiveScale
            local snappedHeight = floor(barHeight * effectiveScale + 0.5) / effectiveScale
            pip:SetSize(pipWidth, snappedHeight)
            pip:ClearAllPoints()
            pip:SetPoint("CENTER", bar, "LEFT", snappedOffset, 0)
            pip:Show()
        end

        -- Hide any extra pips from a previous cast with more stages
        for i = numStages, #castBarFrame._pips do
            castBarFrame._pips[i]:Hide()
        end
    end

    castBarFrame:Show()
end

OnEmpowerUpdate = function()
    if not castBarFrame then return end
    if not castBarFrame._empowering then return end

    local name, _, _, startTimeMS, endTimeMS, _, notInterruptible, spellID, empowering = UnitChannelInfo("player")
    if not name or not empowering then return end

    local holdAtMax = GetUnitEmpowerHoldAtMaxTime("player")
    endTimeMS = endTimeMS + holdAtMax

    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
end

-------------------------------------------------------------------------------
--  Master Apply
-------------------------------------------------------------------------------
function ERB:ApplyAll()
    local _, classFile = UnitClass("player")
    cachedClass = classFile
    cachedPrimary = GetPrimaryPowerType()
    cachedSecondary = GetSecondaryResource()

    BuildMainFrame()
    BuildBars()
    BuildCastBar()
    UpdateHealthBar()
    UpdatePrimaryBar()
    UpdateSecondaryResource()
    UpdateVisibility()

    -- Vehicle proxy: hide resource bars during full vehicle UI ([vehicleui] condition)
    if not ERB._vehicleProxy then
        ERB._vehicleProxy = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
        ERB._vehicleProxy:SetAttribute("_onstate-erbvehicle", [[
            self:CallMethod("OnVehicleStateChanged", newstate)
        ]])
        ERB._vehicleProxy.OnVehicleStateChanged = function(_, state)
            ERB._inVehicle = (state == "hide")
            UpdateVisibility()
        end
        RegisterStateDriver(ERB._vehicleProxy, "erbvehicle", "[vehicleui][petbattle] hide; show")
    end
end


-------------------------------------------------------------------------------
--  Event handling
-------------------------------------------------------------------------------
local function OnEvent(self, event, ...)
    if event == "UNIT_HEALTH" then
        UpdateHealthBar()
        -- Stagger is based on health, so update secondary resource too
        if cachedSecondary and cachedSecondary.power == "BREWMASTER_STAGGER" then
            UpdateSecondaryResource()
        end
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
        local unit, powerToken = ...
        if unit == "player" then
            UpdatePrimaryBar()
            UpdateSecondaryResource()
        end
    elseif event == "UNIT_MAXHEALTH" then
        UpdateHealthBar()
        -- Stagger max is player max health, so rebuild if needed
        if cachedSecondary and cachedSecondary.power == "BREWMASTER_STAGGER" then
            local newMax = UnitHealthMax("player") or 1
            if not issecretvalue or not issecretvalue(newMax) then
                if newMax > 0 and newMax ~= cachedSecondary.max then
                    cachedSecondary.max = newMax
                    BuildBars()
                end
            end
            UpdateSecondaryResource()
        end
    elseif event == "UNIT_MAXPOWER" then
        -- Re-check secondary resource in case max changed (e.g. talent-based pip count)
        local newSec = GetSecondaryResource()
        local oldMax = cachedSecondary and cachedSecondary.max
        local newMax = newSec and newSec.max
        if oldMax ~= newMax then
            cachedSecondary = newSec
            BuildBars()
        end
        UpdatePrimaryBar()
        UpdateSecondaryResource()
    elseif event == "RUNE_POWER_UPDATE" then
        UpdateSecondaryResource()
    elseif event == "UNIT_POWER_POINT_CHARGE" then
        UpdateSecondaryResource()
    elseif event == "PLAYER_REGEN_DISABLED" then
        isInCombat = true
        UpdateVisibility()
    elseif event == "PLAYER_REGEN_ENABLED" then
        isInCombat = false
        UpdateVisibility()
        -- Clean up Whirlwind GUID cache on combat end
        if EllesmereUI and EllesmereUI.HandleWhirlwindStacks then
            EllesmereUI.HandleWhirlwindStacks(event)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateVisibility()
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        cachedPrimary = GetPrimaryPowerType()
        cachedSecondary = GetSecondaryResource()
        BuildBars()
        BuildCastBar()
        UpdatePrimaryBar()
        UpdateSecondaryResource()
        UpdateVisibility()
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        cachedPrimary = GetPrimaryPowerType()
        cachedSecondary = GetSecondaryResource()
        BuildBars()
        UpdatePrimaryBar()
        UpdateSecondaryResource()
        UpdateVisibility()
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" and cachedSecondary and cachedSecondary.type == "custom" then
            UpdateSecondaryResource()
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Route to manual resource trackers (12.0+ secret-value safe)
        local unit, castGUID, spellID = ...
        if unit == "player" and EllesmereUI then
            if EllesmereUI.HandleTipOfTheSpear then
                EllesmereUI.HandleTipOfTheSpear(event, unit, castGUID, spellID)
            end
            if EllesmereUI.HandleWhirlwindStacks then
                EllesmereUI.HandleWhirlwindStacks(event, unit, castGUID, spellID)
            end
            if cachedSecondary and cachedSecondary.type == "custom" then
                UpdateSecondaryResource()
            end
        end
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
        -- Reset manual trackers on death/resurrect
        if EllesmereUI then
            if EllesmereUI.HandleTipOfTheSpear then
                EllesmereUI.HandleTipOfTheSpear(event)
            end
            if EllesmereUI.HandleWhirlwindStacks then
                EllesmereUI.HandleWhirlwindStacks(event)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            ERB:ApplyAll()
            RegisterUnlockElements()
        end)
    elseif event == "UNIT_SPELLCAST_START" then
        local unit = ...
        if unit == "player" then OnCastStart() end
    elseif event == "UNIT_SPELLCAST_STOP" then
        local unit, _, _, castID = ...
        if unit == "player" then OnCastComplete(castID) end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        -- args: unit, castGUID, spellID, castID
        local unit, _, _, castID = ...
        if unit == "player" then OnCastFailed(castID) end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- args: unit, castGUID, spellID, interruptedBy, castID
        local unit, _, _, _, castID = ...
        if unit == "player" then OnCastFailed(castID) end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit = ...
        if unit == "player" then OnChannelStart() end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- args: unit, castGUID, spellID, interruptedBy, castID
        local unit, _, _, _, castID = ...
        if unit == "player" then OnChannelStop(castID) end
    elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
        local unit = ...
        if unit == "player" then OnEmpowerStart() end
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        -- args: unit, castGUID, spellID, empowerComplete, interruptedBy, castID
        local unit, _, _, _, _, castID = ...
        if unit == "player" then OnEmpowerStop(castID) end
    elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        local unit = ...
        if unit == "player" then OnEmpowerUpdate() end
    end
end


-------------------------------------------------------------------------------
--  Initialization
-------------------------------------------------------------------------------
function ERB:OnInitialize()
    self.db = EllesmereUI.Lite.NewDB("EllesmereUIResourceBarsDB", DEFAULTS, true)

    -- One-time migration from AceDB to Lite: reset the profile to ensure
    -- all defaults are properly applied.  AceDB used metatables for defaults
    -- which left the raw SavedVariables sparse; Lite writes defaults directly.
    -- This flag persists in the SV root so it only fires once per character.
    local sv = _G["EllesmereUIResourceBarsDB"]
    if sv and not sv._liteMigrated then
        self.db:ResetProfile()
        sv._liteMigrated = true
    end

    _G._ERB_AceDB = self.db
    _G._ERB_Apply = function() ERB:ApplyAll() end
    _G._ERB_GetSecondaryResource = GetSecondaryResource
    _G._ERB_GetPrimaryPowerType = GetPrimaryPowerType
    _G._ERB_PowerColors = POWER_COLORS

    AppendSharedMediaTextures()
end

function ERB:OnEnable()
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterUnitEvent("UNIT_HEALTH", "player")
    eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    eventFrame:RegisterEvent("RUNE_POWER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")
    eventFrame:RegisterEvent("PLAYER_DEAD")
    eventFrame:RegisterEvent("PLAYER_ALIVE")
    eventFrame:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", "player")
    eventFrame:SetScript("OnEvent", OnEvent)
    eventFrame:SetScript("OnUpdate", OnUpdate)
end

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
SLASH_ERB1 = "/erb"
SLASH_ERB2 = "/ellesresource"
SlashCmdList.ERB = function(msg)
    if msg == "lock" or msg == "unlock" then
        -- Unlock mode is now handled by the shared EllesmereUI system
        if EllesmereUI and EllesmereUI.ToggleUnlockMode then
            EllesmereUI:ToggleUnlockMode()
        end
        return
    end
    if InCombatLockdown and InCombatLockdown() then return end
    if EllesmereUI and EllesmereUI.ShowModule then
        EllesmereUI:ShowModule("EllesmereUIResourceBars")
    end
end
