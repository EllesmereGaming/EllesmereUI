local addon = EllesmereUI.Lite.NewAddon('EllesmereUIDamageMeter')

if not C_DamageMeter or not Enum.DamageMeterType then return end

addon.S = {}
local S = addon.S

local LSM = LibStub('LibSharedMedia-3.0')

function S.GetClassColor(classFilename)
    if not classFilename then return 1, 1, 1 end
    local cc = EllesmereUI.GetClassColor(classFilename)
    if cc then return cc.r, cc.g, cc.b end
    return 1, 1, 1
end
local GetClassColor = S.GetClassColor

function S.ResolveFontPath(fontNameOrNil)
    if fontNameOrNil and fontNameOrNil ~= '' then
        local path = LSM:Fetch('font', fontNameOrNil)
        if path then return path end
    end
    return EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or LSM:Fetch('font', 'Expressway')
end

function S.ApplyFont(fs, fontPath, size, flags)
    if not fs then return end
    local f = flags or ''
    local shadow = false
    if f == 'SHADOWOUTLINE' then
        f = 'OUTLINE'
        shadow = true
    end
    fs:SetFont(fontPath, size, f)
    if shadow then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowColor(0, 0, 0, 0)
        fs:SetShadowOffset(0, 0)
    end
end

S.MAX_BARS      = 40
S.PANEL_INSET   = 2
S.HEADER_HEIGHT = 22
S.FLAT_TEX      = 'Interface\\Buttons\\WHITE8x8'
S.DEFAULT_TEX   = LSM:Fetch('statusbar', 'ElvUI Blank') or S.FLAT_TEX
-- Use of Fabled class icons with permission from Jiberish, 2026-03-10
S.CLASS_ICONS   = 'Interface\\AddOns\\EllesmereUIDamageMeter\\media\\fabled'

S.texTextures = { ['none'] = S.FLAT_TEX }
S.texNames = { ['none'] = 'Flat' }
S.texOrder = { 'none' }
if EllesmereUI and EllesmereUI.AppendSharedMediaTextures then
	EllesmereUI.AppendSharedMediaTextures(S.texNames, S.texOrder, nil, S.texTextures)
end

S.texDropdownValues = {}
for _, key in ipairs(S.texOrder) do
	if key ~= '---' then
		S.texDropdownValues[key] = S.texNames[key] or key
	end
end
S.texDropdownValues._menuOpts = {
	itemHeight = 28,
	background = function(key)
		return S.texTextures[key]
	end,
}

S.texDropdownOrder = {}
for _, key in ipairs(S.texOrder) do
	S.texDropdownOrder[#S.texDropdownOrder + 1] = key
end

S.COMBINED_DAMAGE  = "CombinedDamage"
S.COMBINED_HEALING = "CombinedHealing"

S.COMBINED_DATA_TYPE = {
    [S.COMBINED_DAMAGE]  = Enum.DamageMeterType.DamageDone,
    [S.COMBINED_HEALING] = Enum.DamageMeterType.HealingDone,
}

S.MODE_ORDER = {
    Enum.DamageMeterType.DamageDone,
    Enum.DamageMeterType.Dps,
    S.COMBINED_DAMAGE,
    Enum.DamageMeterType.HealingDone,
    Enum.DamageMeterType.Hps,
    S.COMBINED_HEALING,
    Enum.DamageMeterType.Absorbs,
    Enum.DamageMeterType.Interrupts,
    Enum.DamageMeterType.Dispels,
    Enum.DamageMeterType.DamageTaken,
    Enum.DamageMeterType.AvoidableDamageTaken,
}
if Enum.DamageMeterType.Deaths           then S.MODE_ORDER[#S.MODE_ORDER + 1] = Enum.DamageMeterType.Deaths           end
if Enum.DamageMeterType.EnemyDamageTaken then S.MODE_ORDER[#S.MODE_ORDER + 1] = Enum.DamageMeterType.EnemyDamageTaken end

function S.ResolveMeterType(modeEntry)
    return S.COMBINED_DATA_TYPE[modeEntry] or modeEntry
end

S.MODE_LABELS = {
    [Enum.DamageMeterType.DamageDone]           = "Damage",
    [Enum.DamageMeterType.Dps]                  = "DPS",
    [S.COMBINED_DAMAGE]                         = "DPS/Damage",
    [Enum.DamageMeterType.HealingDone]          = "Healing",
    [Enum.DamageMeterType.Hps]                  = "HPS",
    [S.COMBINED_HEALING]                        = "HPS/Healing",
    [Enum.DamageMeterType.Absorbs]              = "Absorbs",
    [Enum.DamageMeterType.Interrupts]           = "Interrupts",
    [Enum.DamageMeterType.Dispels]              = "Dispels",
    [Enum.DamageMeterType.DamageTaken]          = "Damage Taken",
    [Enum.DamageMeterType.AvoidableDamageTaken] = "Avoidable Damage Taken",
}
if Enum.DamageMeterType.Deaths           then S.MODE_LABELS[Enum.DamageMeterType.Deaths]           = "Deaths"              end
if Enum.DamageMeterType.EnemyDamageTaken then S.MODE_LABELS[Enum.DamageMeterType.EnemyDamageTaken] = "Enemy Damage Taken"   end

S.MODE_SHORT = {
    [Enum.DamageMeterType.DamageDone]           = "Damage",
    [Enum.DamageMeterType.Dps]                  = "DPS",
    [S.COMBINED_DAMAGE]                         = "DPS/Dmg",
    [Enum.DamageMeterType.HealingDone]          = "Healing",
    [Enum.DamageMeterType.Hps]                  = "HPS",
    [S.COMBINED_HEALING]                        = "HPS/Heal",
    [Enum.DamageMeterType.Absorbs]              = "Absorbs",
    [Enum.DamageMeterType.Interrupts]           = "Interrupts",
    [Enum.DamageMeterType.Dispels]              = "Dispels",
    [Enum.DamageMeterType.DamageTaken]          = "Dmg Taken",
    [Enum.DamageMeterType.AvoidableDamageTaken] = "Avoidable",
}
if Enum.DamageMeterType.Deaths           then S.MODE_SHORT[Enum.DamageMeterType.Deaths]           = "Deaths"    end
if Enum.DamageMeterType.EnemyDamageTaken then S.MODE_SHORT[Enum.DamageMeterType.EnemyDamageTaken] = "Enemy Dmg" end

S.CLASS_ICON_COORDS = {
    WARRIOR     = { 0,     0,     0,     0.125, 0.125, 0,     0.125, 0.125 },
    MAGE        = { 0.125, 0,     0.125, 0.125, 0.25,  0,     0.25,  0.125 },
    ROGUE       = { 0.25,  0,     0.25,  0.125, 0.375, 0,     0.375, 0.125 },
    DRUID       = { 0.375, 0,     0.375, 0.125, 0.5,   0,     0.5,   0.125 },
    EVOKER      = { 0.5,   0,     0.5,   0.125, 0.625, 0,     0.625, 0.125 },
    HUNTER      = { 0,     0.125, 0,     0.25,  0.125, 0.125, 0.125, 0.25  },
    SHAMAN      = { 0.125, 0.125, 0.125, 0.25,  0.25,  0.125, 0.25,  0.25  },
    PRIEST      = { 0.25,  0.125, 0.25,  0.25,  0.375, 0.125, 0.375, 0.25  },
    WARLOCK     = { 0.375, 0.125, 0.375, 0.25,  0.5,   0.125, 0.5,   0.25  },
    PALADIN     = { 0,     0.25,  0,     0.375, 0.125, 0.25,  0.125, 0.375 },
    DEATHKNIGHT = { 0.125, 0.25,  0.125, 0.375, 0.25,  0.25,  0.25,  0.375 },
    MONK        = { 0.25,  0.25,  0.25,  0.375, 0.375, 0.25,  0.375, 0.375 },
    DEMONHUNTER = { 0.375, 0.25,  0.375, 0.375, 0.5,   0.25,  0.5,   0.375 },
}

S.CLASS_FULL_COORDS = {
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

S.CLASS_FULL_BASE = 'Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\'

function S.ResolveClassIcon(style, classFilename)
    if not classFilename or style == 'none' then return nil, nil end
    if not style or style == 'fabled' then
        local coords = S.CLASS_ICON_COORDS[classFilename]
        return S.CLASS_ICONS, coords
    end
    local coords = S.CLASS_FULL_COORDS[classFilename]
    return S.CLASS_FULL_BASE .. style .. '.tga', coords
end

function S.ApplyClassIcon(icon, style, classFilename)
    local tex, coords = S.ResolveClassIcon(style, classFilename)
    if not tex or not coords then
        icon:Hide()
        return
    end
    icon:SetTexture(tex)
    if style == 'fabled' or not style then
        icon:SetTexCoord(unpack(coords))
    else
        icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end
    icon:Show()
end

S.SESSION_LABELS = {
    [Enum.DamageMeterSessionType.Current] = "Current",
    [Enum.DamageMeterSessionType.Overall] = "Overall",
}

StaticPopupDialogs['EUIDM_RESET'] = {
    text         = "Reset all damage meter data?",
    button1      = ACCEPT,
    button2      = CANCEL,
    OnAccept     = function()
        C_DamageMeter.ResetAllCombatSessions()
        addon:RefreshMeter()
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}

S.windows  = {}
S.testMode = false
S.meterHidden = false
S.meterFadedOut = false
S.flightTicker = nil
S.flightFadeTimer = nil

S.nameCache  = {}
S.classCache = {}
S.specNameCache = {}
S.specCollisions = {}
S.spellCache = {}
S.winDBCache = {}
S.sessionLabelCache = {}

local strsplit = strsplit
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local UnitGUID = UnitGUID
local floor = math.floor

function S.ScanRoster()
    local pg = UnitGUID('player')
    if pg then
        S.nameCache[pg] = UnitName('player')
        S.classCache[pg] = select(2, UnitClass('player'))
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = 'raid' .. i
            local guid = UnitGUID(unit)
            if guid then
                S.nameCache[guid] = UnitName(unit)
                S.classCache[guid] = select(2, UnitClass(unit))
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = 'party' .. i
            local guid = UnitGUID(unit)
            if guid then
                S.nameCache[guid] = UnitName(unit)
                S.classCache[guid] = select(2, UnitClass(unit))
            end
        end
    end
end

function S.IsSecret(val)
    return val ~= nil and issecretvalue and issecretvalue(val)
end

function S.FindUnitByGUID(guid)
    if UnitGUID('player') == guid then return 'player' end
    for i = 1, 40 do
        local unit = 'raid' .. i
        if UnitGUID(unit) == guid then return unit end
    end
    for i = 1, 4 do
        local unit = 'party' .. i
        if UnitGUID(unit) == guid then return unit end
    end
end

function S.RoundIfPlain(val)
    if val and not S.IsSecret(val) then
        return floor(val + 0.5)
    end
    return val
end

-- Strip decimals from sub-1K abbreviated strings (e.g. "209.385" -> "209")
function S.TruncateDecimals(text)
    if type(text) ~= 'string' or S.IsSecret(text) then return text end
    if text:match('%a') then return text end
    return (strsplit('.', text))
end

function S.FormatValueText(fontString, val)
    if not val then
        fontString:SetText('0')
        return
    end
    fontString:SetText(S.TruncateDecimals(AbbreviateNumbers(S.RoundIfPlain(val))))
end

function S.FormatCombinedText(fontString, total, perSec)
    if not total and not perSec then
        fontString:SetText('0')
        return
    end
    local ok = pcall(function()
        local p = S.TruncateDecimals(perSec and AbbreviateNumbers(S.RoundIfPlain(perSec)) or '0')
        local t = S.TruncateDecimals(total and AbbreviateNumbers(S.RoundIfPlain(total)) or '0')
        fontString:SetText(p .. ' (' .. t .. ')')
    end)
    if not ok then
        if total then
            fontString:SetText(S.TruncateDecimals(AbbreviateNumbers(S.RoundIfPlain(total))))
        else
            fontString:SetText('0')
        end
    end
end

function S.FontFlags(outline)
    return (outline and outline ~= "NONE") and outline or ""
end

function S.GetWinDB(winIndex)
    local mainDB = addon.db.profile
    if winIndex == 1 then return mainDB end
    local proxy = S.winDBCache[winIndex]
    if not proxy then
        proxy = setmetatable({}, { __index = function(_, k)
            local ew = addon.db.profile.extraWindows and addon.db.profile.extraWindows[winIndex]
            if ew then
                local v = ew[k]
                if v ~= nil then return v end
            end
            return addon.db.profile[k]
        end })
        S.winDBCache[winIndex] = proxy
    end
    return proxy
end

local cachedClassR, cachedClassG, cachedClassB, cachedClassName

local function CacheClassColor(classFilename)
    if classFilename == cachedClassName then return end
    cachedClassName = classFilename
    cachedClassR, cachedClassG, cachedClassB = GetClassColor(classFilename)
end

function S.ClassOrColor(db, flagKey, colorKey, classFilename)
    if db[flagKey] then
        CacheClassColor(classFilename)
        if cachedClassR then return cachedClassR, cachedClassG, cachedClassB, db[colorKey].a end
    end
    local c = db[colorKey]
    return c.r, c.g, c.b, c.a
end

function S.StyleBarTexts(bar, fontPath, size, flags)
    S.ApplyFont(bar.leftText, fontPath, size, flags)
    S.ApplyFont(bar.rightText, fontPath, size, flags)
    S.ApplyFont(bar.pctText, fontPath, size, flags)
end

function S.NewWindowState(index, savedModeIndex)
    return {
        index         = index,
        frame         = nil,
        header        = nil,
        window        = nil,
        bars          = {},
        modeIndex     = savedModeIndex or 1,
        sessionType   = Enum.DamageMeterSessionType.Current,
        sessionId     = nil,
        embedded      = false,
        scrollOffset  = 0,
        drillSource   = nil,
    }
end

function S.GetSession(win, meterType)
    if win.sessionId and C_DamageMeter.GetCombatSessionFromID then
        return C_DamageMeter.GetCombatSessionFromID(win.sessionId, meterType)
    end
    return C_DamageMeter.GetCombatSessionFromType(win.sessionType, meterType)
end

function S.GetSessionSource(win, meterType, guid)
    if win.sessionId and C_DamageMeter.GetCombatSessionSourceFromID then
        return C_DamageMeter.GetCombatSessionSourceFromID(win.sessionId, meterType, guid)
    end
    return C_DamageMeter.GetCombatSessionSourceFromType(win.sessionType, meterType, guid)
end

function S.GetSessionLabel(win)
    if win.sessionId then
        local cached = S.sessionLabelCache[win.sessionId]
        if cached then return cached end
        if C_DamageMeter.GetAvailableCombatSessions then
            local sessions = C_DamageMeter.GetAvailableCombatSessions()
            if sessions then
                for i, sess in ipairs(sessions) do
                    local sid = sess.sessionId or sess.combatSessionId or sess.id or sess.sessionID
                    if sid == win.sessionId then
                        local label = sess.name or 'Encounter'
                        if label == 'Encounter' then label = 'Encounter ' .. i end
                        S.sessionLabelCache[win.sessionId] = label
                        return label
                    end
                end
            end
        end
        return 'Encounter'
    end
    return S.SESSION_LABELS[win.sessionType] or '?'
end

local defaults = {
    profile = {
        enabled = true, barHeight = 18, barSpacing = 1,
        barFont = 'Expressway', barFontSize = 11, barFontOutline = 'OUTLINE',
        barTexture = 'none', barBGTexture = 'none',
        barColor = { r = 0.3, g = 0.3, b = 0.8, a = 1 },
        barBGColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.35 },
        barClassColor = true, barBGClassColor = false,
        textColor = { r = 1, g = 1, b = 1 }, textClassColor = false,
        valueColor = { r = 1, g = 1, b = 1 }, valueClassColor = false,
        rankColor = { r = 0.7, g = 0.7, b = 0.7 }, rankClassColor = false,
        showRank = false, showClassIcon = true, classIconStyle = 'fabled',
        showBackdrop = true, backdropColor = { r = 0.1, g = 0.1, b = 0.1, a = 0.8 },
        showHeaderBackdrop = true, showHeaderBorder = true,
        headerBGColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 },
        headerFont = 'Expressway', headerFontSize = 11, headerFontOutline = 'OUTLINE',
        headerFontColor = { r = 1, g = 1, b = 1 }, headerMouseover = false,
        showTimer = true, barBorderEnabled = false,
        standaloneWidth = 220, standaloneHeight = 180,
        modeIndex = 1, hideInFlight = false, hideInPetBattle = false,
        autoResetOnComplete = false,
    }
}
addon.defaults = defaults
addon.db = EllesmereUI.Lite.NewDB('EllesmereUIDamageMeterDB', defaults)

EllesmereUIDamageMeter = addon
