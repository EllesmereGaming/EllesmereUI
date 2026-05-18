-------------------------------------------------------------------------------
--  EllesmereUIDamageMeters.lua
--  Custom damage meter frame using C_DamageMeter API.
--  Multi-window support (up to 5). Zero Blizzard frame hooks. All settings live.
-------------------------------------------------------------------------------
local _, ns = ...
local EUI = EllesmereUI

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local BAR_POOL_SIZE     = 40
local RANK_STRINGS      = {}
for i = 1, 40 do RANK_STRINGS[i] = i .. "." end
local MIN_W, MIN_H      = 150, 80
local TICK_COMBAT       = 0.5
local PEAK_BUDGET       = 1.5
local BAR_TEX           = "Interface\\Buttons\\WHITE8X8"
local MEDIA             = "Interface\\AddOns\\EllesmereUIDamageMeters\\Media\\"
local ICON_ALPHA        = 0.4
local ICON_HOVER_ALPHA  = 0.9
local RESIZE_ICON       = "Interface\\AddOns\\EllesmereUI\\media\\icons\\resize_element.png"
local MAX_WINDOWS       = 5

local DM_TYPE_NAMES = {
    [Enum.DamageMeterType.DamageDone]           = "Damage Done",
    [Enum.DamageMeterType.HealingDone]          = "Healing Done",
    [Enum.DamageMeterType.DamageTaken]          = "Damage Taken",
    [Enum.DamageMeterType.AvoidableDamageTaken] = "Avoidable Damage Taken",
    [Enum.DamageMeterType.EnemyDamageTaken]     = "Enemy Damage Taken",
    [Enum.DamageMeterType.Interrupts]           = "Interrupts",
    [Enum.DamageMeterType.Dispels]              = "Dispels",
    [Enum.DamageMeterType.Deaths]               = "Deaths",
}

local DM_TYPES = {
    Enum.DamageMeterType.DamageDone,
    Enum.DamageMeterType.HealingDone,
    Enum.DamageMeterType.DamageTaken,
    Enum.DamageMeterType.Interrupts,
    Enum.DamageMeterType.Dispels,
    Enum.DamageMeterType.Deaths,
}

local DM_TYPE_ICONS = {
    [Enum.DamageMeterType.DamageDone]           = MEDIA .. "dm_home_damage.png",
    [Enum.DamageMeterType.HealingDone]          = MEDIA .. "dm_home_healing.png",
    [Enum.DamageMeterType.DamageTaken]          = MEDIA .. "dm_home_taken.png",
    [Enum.DamageMeterType.AvoidableDamageTaken] = MEDIA .. "dm_home_avoidable.png",
    [Enum.DamageMeterType.EnemyDamageTaken]     = MEDIA .. "dm_home_enemytaken.png",
    [Enum.DamageMeterType.Interrupts]           = MEDIA .. "dm_home_interrupt.png",
    [Enum.DamageMeterType.Dispels]              = MEDIA .. "dm_home_dispel.png",
    [Enum.DamageMeterType.Deaths]               = MEDIA .. "dm_home_deaths.png",
}

local SESSION_TYPES = {
    Enum.DamageMeterSessionType.Current,
    Enum.DamageMeterSessionType.Overall,
}
local SESSION_TYPE_NAMES = {
    [Enum.DamageMeterSessionType.Current] = "Current",
    [Enum.DamageMeterSessionType.Overall] = "Overall",
}

local HOME_DEFAULTS = {
    Enum.DamageMeterType.DamageDone,
    Enum.DamageMeterType.HealingDone,
    Enum.DamageMeterType.Interrupts,
    Enum.DamageMeterType.Deaths,
}

-------------------------------------------------------------------------------
--  DB defaults + helpers
-------------------------------------------------------------------------------
local DM_DEFAULTS = {
    global = {},
    profile = {
        dm = {
            visibility      = "always",
            barTexture      = "atrocity",
            fontSize        = 11,
            barHeight       = 18,
            barSpacing      = 2,
            numberFormat    = 2,
            iconStyle       = "spec",
            iconColorUseAccent = false,
            iconColor       = { r = 1, g = 1, b = 1 },
            showClassColor  = true,
            showPinnedSelf  = false,
            showHoverTooltip = true,
            breakdownAnchorPoint = "row", -- "row" (Above Row) | "center" (Center of Screen)
            breakdownBarTexture = "match",
            barColorUseAccent = true,
            barColor        = { r = 0.35, g = 0.55, b = 0.8 },
            barFillAlpha    = 1,
            leftFontSize    = 11,
            leftTextUseClassColor = false,
            leftTextColor   = { r = 1, g = 1, b = 1 },
            rightFontSize   = 11,
            rightTextUseClassColor = false,
            rightTextColor  = { r = 1, g = 1, b = 1 },
            bgR = 0, bgG = 0, bgB = 0, bgAlpha = 0.75,
            standaloneTimer       = false,
            standaloneTimerSize   = 26,
            standaloneTimerUseAccent = false,
            standaloneTimerColor  = { r = 1, g = 1, b = 1 },
            standaloneTimerPos    = nil,
            standaloneTimerAnchor = "free",
            refreshRate = 0.5,
            hdrBgColor      = { r = 0x1B/255, g = 0x1B/255, b = 0x1B/255 },
            hdrBgAlpha      = 1,
            hdrHeight       = 22,
            hdrFontSize     = 11,
            hdrTextOffX     = 0,
            hdrTextOffY     = 0,
            hdrIconSize     = 22,
            hdrMouseoverIcons = false,
            hdrTextUseAccent = true,
            hdrTextColor    = { r = 1, g = 1, b = 1 },
            borderTexture   = "solid",
            borderSize      = 0,
            borderR = 0, borderG = 0, borderB = 0, borderA = 1,
            -- Per-window settings
            windowCount = 1,
            windows = nil,  -- populated at init
        },
    },
}

-- Per-addon border texture defaults (same as resourcebars/cdm)
do
    local function AllSizes(ox, oy, sx, sy)
        local t = {}
        for k = 0, 4 do t[k] = { offsetX = ox, offsetY = oy, shiftX = sx, shiftY = sy } end
        return t
    end
    EllesmereUI.RegisterBorderDefaults("damagemeters", {
        ["glow"] = {
            defaultSize = 1,
            sizes = AllSizes(0, 0, 0, 0),
        },
        ["blizz"] = {
            defaultSize = 3,
            sizes = {
                [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                [1] = { offsetX = 2, offsetY = 1, shiftX = 0, shiftY = 0 },
                [2] = { offsetX = 3, offsetY = 2, shiftX = 1, shiftY = 0 },
                [3] = { offsetX = 4, offsetY = 2, shiftX = 1, shiftY = 0 },
                [4] = { offsetX = 4, offsetY = 2, shiftX = 1, shiftY = 0 },
            },
        },
        ["dialog"] = {
            defaultSize = 1,
            sizes = {
                [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                [1] = { offsetX = 3, offsetY = 3, shiftX = 0, shiftY = 0 },
                [2] = { offsetX = 3, offsetY = 5, shiftX = 0, shiftY = 0 },
                [3] = { offsetX = 3, offsetY = 5, shiftX = 0, shiftY = 0 },
                [4] = { offsetX = 5, offsetY = 10, shiftX = 0, shiftY = 0 },
            },
        },
        ["sm:Blizzard Achievement Wood"] = {
            defaultSize = 1,
            sizes = {
                [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                [1] = { offsetX = 1, offsetY = 1, shiftX = 0, shiftY = 0 },
                [2] = { offsetX = 1, offsetY = 1, shiftX = 0, shiftY = 0 },
                [3] = { offsetX = 1, offsetY = 6, shiftX = 0, shiftY = 0 },
                [4] = { offsetX = 1, offsetY = 8, shiftX = 0, shiftY = 0 },
            },
        },
    })
end

local _dmDB
local function EnsureDB()
    if _dmDB then return _dmDB end
    if not EUI or not EUI.Lite then return nil end
    _dmDB = EUI.Lite.NewDB("EllesmereUIDamageMetersDB", DM_DEFAULTS)
    _G._EDM_DB = _dmDB
    return _dmDB
end

ns.EDM = {}
ns.EDM.DB = function()
    local d = _G._EDM_DB
    if d and d.profile and d.profile.dm then return d.profile.dm end
    return {}
end

local function DB() return ns.EDM.DB() end
local function GetHeaderH() local c = DB(); return c.hdrHeight or 22 end

-- Header icon visibility (hide until title bar hovered)
local function SetHeaderButtonsShown(W, shown)
    if not W or not W.hdrBtns then return end
    for _, btn in ipairs(W.hdrBtns) do
        btn:SetAlpha(shown and 1 or 0)
        btn:EnableMouse(shown)
    end
end

local function EnsureHeaderButtonsHoverHooks(W)
    if not W or W._hdrHideUntilHoverHooksInstalled then return end
    W._hdrHideUntilHoverHooksInstalled = true

    local function Show()
        local cfg = DB()
        if not cfg.hdrMouseoverIcons then return end
        SetHeaderButtonsShown(W, true)
    end

    local function MaybeHide()
        local cfg = DB()
        if not cfg.hdrMouseoverIcons then return end
        if not W.header then return end
        C_Timer.After(0, function()
            if not W.header then return end
            if W.header:IsMouseOver() then return end
            SetHeaderButtonsShown(W, false)
        end)
    end

    if W.header then
        W.header:HookScript("OnEnter", Show)
        W.header:HookScript("OnLeave", MaybeHide)
    end
    if W.hdrBtns then
        for _, btn in ipairs(W.hdrBtns) do
            btn:HookScript("OnEnter", Show)
            btn:HookScript("OnLeave", MaybeHide)
        end
    end
end

local function ApplyHeaderButtonsHoverVisibility(W, cfg)
    if not W or not W.header or not W.hdrBtns then return end
    EnsureHeaderButtonsHoverHooks(W)
    if cfg and cfg.hdrMouseoverIcons then
        SetHeaderButtonsShown(W, W.header:IsMouseOver())
    else
        SetHeaderButtonsShown(W, true)
    end
end

-- Per-window DB accessor
local function WinDB(idx)
    local cfg = DB()
    if not cfg.windows then cfg.windows = {} end
    if not cfg.windows[idx] then
        cfg.windows[idx] = {
            position = nil,
            width = 375,
            height = 150,
        }
    end
    return cfg.windows[idx]
end

-- Bookmarks are shared across all windows (stored in dm.bookmarks)
local function GetBookmarks()
    local cfg = DB()
    if not cfg.bookmarks then
        cfg.bookmarks = {}
        for _, dt in ipairs(HOME_DEFAULTS) do
            cfg.bookmarks[#cfg.bookmarks + 1] = dt
        end
    end
    return cfg.bookmarks
end


-------------------------------------------------------------------------------
--  Shared state
-------------------------------------------------------------------------------
local _inCombat = false
local _playerGUID
local _windows = {}  -- array of active window tables
ns._windows = _windows
ns._DM_TYPE_NAMES = DM_TYPE_NAMES
local _combatStartTime = 0   -- GetTime() at combat start
local _combatEndTime = 0     -- GetTime() at combat end (frozen)
local _needsFinalRefresh = false

local function GetCombatElapsed()
    if _combatEndTime > 0 then
        -- Combat ended: frozen value
        return _combatEndTime - _combatStartTime
    elseif _combatStartTime > 0 then
        -- In combat: live ticking
        return GetTime() - _combatStartTime
    end
    return 0
end

local _raidUnits, _partyUnits = {}, {}
for i = 1, 40 do _raidUnits[i] = "raid" .. i end
for i = 1, 4 do _partyUnits[i] = "party" .. i end

local function IsGroupInCombat()
    if UnitAffectingCombat("player") then return true end
    if IsInRaid() then
        local n = GetNumGroupMembers()
        for i = 1, n do
            if UnitAffectingCombat(_raidUnits[i]) then return true end
        end
    elseif IsInGroup() then
        local n = GetNumGroupMembers() - 1  -- party units exclude player
        for i = 1, n do
            if UnitAffectingCombat(_partyUnits[i]) then return true end
        end
    end
    return false
end

-- Keystone start: wipe data so Overall = this dungeon run
-- Keystone end: auto-swap windows from Current to Overall (if enabled)
local instanceFrame = CreateFrame("Frame")
instanceFrame:RegisterEvent("CHALLENGE_MODE_START")
instanceFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
instanceFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
instanceFrame:RegisterEvent("DAMAGE_METER_RESET")
instanceFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
instanceFrame:SetScript("OnEvent", function(_, event)
    if event == "CHALLENGE_MODE_START" then
        if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
            C_DamageMeter.ResetAllCombatSessions()
        end
        _combatStartTime = 0; _combatEndTime = 0
        -- Auto-swap: Overall -> Current on key start
        for _, w in ipairs(_windows) do
            local wdb2 = WinDB(w.idx)
            if wdb2.autoSwapMythic and w.curSession == Enum.DamageMeterSessionType.Overall then
                w.curSession = Enum.DamageMeterSessionType.Current
                wdb2.curSession = Enum.DamageMeterSessionType.Current
                w.curSessionID = nil
            end
            w.Refresh()
        end
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        -- Auto-swap: Current -> Overall on key completion
        for _, w in ipairs(_windows) do
            local wdb2 = WinDB(w.idx)
            if wdb2.autoSwapMythic and not w.curSessionID and w.curSession == Enum.DamageMeterSessionType.Current then
                w.curSession = Enum.DamageMeterSessionType.Overall
                wdb2.curSession = Enum.DamageMeterSessionType.Overall
                w.curSessionID = nil
                w.Refresh()
            end
        end
    elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        -- Blizzard created or updated a combat session (boss kill, combat end, etc.)
        -- "Current" may now point to a different session. Invalidate cache so the
        -- next ticker-driven refresh picks up fresh data. Only force an immediate
        -- refresh when NOT in combat (the shared ticker handles combat refreshes
        -- at the user's configured refreshRate).
        if not instanceFrame._sessionPending then
            instanceFrame._sessionPending = true
            C_Timer.After(0.1, function()
                instanceFrame._sessionPending = nil
                for _, w in ipairs(_windows) do
                    w._barCacheKey = nil
                    w._cachedTargets = nil
                end
                if not _inCombat then
                    for _, w in ipairs(_windows) do w.Refresh() end
                end
            end)
        end
    elseif event == "DAMAGE_METER_RESET" then
        -- Blizzard cleared all session data (auto-reset CVar, manual reset, etc.)
        _combatStartTime = 0; _combatEndTime = 0
        if _targetsCache then wipe(_targetsCache) end
        for _, w in ipairs(_windows) do
            w._barCacheKey = nil
            w._barSources = nil
            w._cachedTargets = nil
            w.Refresh()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Zone transition (hearth, teleport, etc.): if player is out of combat,
        -- force-end the combat state. Covers the case where the player leaves
        -- an instance mid-combat (hearthing out of a dungeon).
        if not InCombatLockdown() and (_inCombat or _needsFinalRefresh) then
            _combatEndTime = GetTime()
            _inCombat = false
            _needsFinalRefresh = false
            StopSharedTicker()
        end
        -- Refresh after zone-in to pick up visibility/data changes
        for _, w in ipairs(_windows) do
            w._barCacheKey = nil
            w._barSources = nil
        end
        C_Timer.After(0.5, function()
            for _, w in ipairs(_windows) do w.Refresh() end
        end)
    end
end)

-------------------------------------------------------------------------------
--  CVar helper
-------------------------------------------------------------------------------
local function SetCVarSafe(name, value)
    if C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar(name, value)
    elseif SetCVar then
        SetCVar(name, value)
    end
end

-------------------------------------------------------------------------------
--  Font helpers
-------------------------------------------------------------------------------
local function GetDMFont()
    if EUI and EUI.GetFontPath then
        return EUI.GetFontPath("damageMeters")
    end
    return "Fonts\\FRIZQT__.TTF"
end

local function GetDMOutline()
    return (EUI and EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag("damageMeters")) or ""
end

local function SetDMFont(fs, size)
    if not (fs and fs.SetFont) then return end
    local font = GetDMFont()
    local flags = GetDMOutline()
    fs:SetFont(font, size, flags)
    if flags == "" then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-------------------------------------------------------------------------------
--  Accent color helper
-------------------------------------------------------------------------------
local function GetAccentRGB()
    if EUI.ResolveThemeColor then
        local db = EllesmereUIDB or {}
        return EUI.ResolveThemeColor(db.activeTheme or "EllesmereUI")
    end
    return EUI.DEFAULT_ACCENT_R or 12/255,
           EUI.DEFAULT_ACCENT_G or 210/255,
           EUI.DEFAULT_ACCENT_B or 157/255
end

-------------------------------------------------------------------------------
--  Bar texture tables
-------------------------------------------------------------------------------
local DM_TEX_BASE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local DM_BAR_TEXTURES = {
    ["none"]          = nil,
    ["melli"]         = DM_TEX_BASE .. "melli.tga",
    ["beautiful"]     = DM_TEX_BASE .. "beautiful.tga",
    ["plating"]       = DM_TEX_BASE .. "plating.tga",
    ["atrocity"]      = DM_TEX_BASE .. "atrocity.tga",
    ["divide"]        = DM_TEX_BASE .. "divide.tga",
    ["glass"]         = DM_TEX_BASE .. "glass.tga",
    ["fade-right"]    = DM_TEX_BASE .. "fade-right.tga",
    ["thin-line-top"]    = DM_TEX_BASE .. "thin-line-top.tga",
    ["thin-line-bottom"] = DM_TEX_BASE .. "thin-line-bottom.tga",
    ["fade"]          = DM_TEX_BASE .. "fade.tga",
    ["gradient-lr"]   = DM_TEX_BASE .. "gradient-lr.tga",
    ["gradient-rl"]   = DM_TEX_BASE .. "gradient-rl.tga",
    ["gradient-bt"]   = DM_TEX_BASE .. "gradient-bt.tga",
    ["gradient-tb"]   = DM_TEX_BASE .. "gradient-tb.tga",
    ["matte"]         = DM_TEX_BASE .. "matte.tga",
    ["sheer"]         = DM_TEX_BASE .. "sheer.tga",
}
local DM_BAR_TEXTURE_ORDER = {
    "none", "melli", "atrocity",
    "fade", "fade-right", "thin-line-top", "thin-line-bottom",
    "beautiful", "plating",
    "divide", "glass",
    "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
    "matte", "sheer",
}
local DM_BAR_TEXTURE_NAMES = {
    ["none"]        = "None",
    ["melli"]       = "Melli (ElvUI)",
    ["beautiful"]   = "Beautiful",
    ["plating"]     = "Plating",
    ["atrocity"]    = "Atrocity",
    ["divide"]      = "Divide",
    ["glass"]       = "Glass",
    ["fade-right"]  = "Fade Right",
    ["thin-line-top"]    = "Thin Line Top",
    ["thin-line-bottom"] = "Thin Line Bottom",
    ["fade"]        = "Fade",
    ["gradient-lr"] = "Gradient Right",
    ["gradient-rl"] = "Gradient Left",
    ["gradient-bt"] = "Gradient Up",
    ["gradient-tb"] = "Gradient Down",
    ["matte"]       = "Matte",
    ["sheer"]       = "Sheer",
}
_G._EDM_BarTextures     = DM_BAR_TEXTURES
_G._EDM_BarTextureOrder = DM_BAR_TEXTURE_ORDER
_G._EDM_BarTextureNames = DM_BAR_TEXTURE_NAMES

local function AppendDMSharedMedia()
    if not EUI.AppendSharedMediaTextures then return end
    EUI.AppendSharedMediaTextures(
        DM_BAR_TEXTURE_NAMES,
        DM_BAR_TEXTURE_ORDER,
        nil,
        DM_BAR_TEXTURES
    )
end

local function GetBarTexturePath()
    local cfg = DB()
    local key = cfg and cfg.barTexture or "none"
    return EUI.ResolveTexturePath(DM_BAR_TEXTURES, key, BAR_TEX), key
end

local function GetBreakdownBarTexturePath()
    local cfg = DB()
    local key = cfg and cfg.breakdownBarTexture
    if not key or key == "match" then
        key = cfg and cfg.barTexture or "none"
    end
    return EUI.ResolveTexturePath(DM_BAR_TEXTURES, key, BAR_TEX), key
end

-- Thin-line overlay: 3 physical pixels at top or bottom of a StatusBar.
-- Instead of modifying every SetStatusBarColor/SetValue call site, we
-- hook the bar.fill so color/value operations transparently forward to
-- the overlay when thin-line mode is active.
local THIN_LINE_KEYS = { ["thin-line-top"] = "TOP", ["thin-line-bottom"] = "BOTTOM" }
local THIN_LINE_PX = 1

local function SetupThinLine(fill, edge)
    if not fill._thinLine then
        local tl = CreateFrame("StatusBar", nil, fill)
        tl:SetStatusBarTexture(BAR_TEX)
        fill._thinLine = tl
        -- Hook SetStatusBarColor to forward to overlay
        local origSSBC = fill.SetStatusBarColor
        fill.SetStatusBarColor = function(self, r, g, b, a)
            if self._thinLine and self._thinLineActive then
                self._thinLine:SetStatusBarColor(r, g, b, a)
                origSSBC(self, 0, 0, 0, 0)
            else
                origSSBC(self, r, g, b, a)
            end
        end
        -- Hook SetMinMaxValues + SetValue to sync overlay
        local origSMMV = fill.SetMinMaxValues
        fill.SetMinMaxValues = function(self, lo, hi)
            origSMMV(self, lo, hi)
            if self._thinLine and self._thinLineActive then
                self._thinLine:SetMinMaxValues(lo, hi)
            end
        end
        local origSV = fill.SetValue
        fill.SetValue = function(self, v)
            origSV(self, v)
            if self._thinLine and self._thinLineActive then
                self._thinLine:SetValue(v)
            end
        end
    end
    local tl = fill._thinLine
    local PP = EUI and EUI.PP
    local px = THIN_LINE_PX * ((PP and PP.mult) or 1)
    tl:ClearAllPoints()
    if edge == "TOP" then
        tl:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
        tl:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
    else
        tl:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, 0)
        tl:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    end
    tl:SetHeight(px)
    tl:Show()
    fill._thinLineActive = true
end

local function ClearThinLine(fill)
    if not fill._thinLineActive then return end
    fill._thinLineActive = false
    if fill._thinLine then fill._thinLine:Hide() end
    -- Thin-line mode set the fill to (0,0,0,0) transparent; reset to opaque
    -- so the bar is visible immediately. The real color is applied by RefreshUI.
    fill:SetStatusBarColor(1, 1, 1, 1)
end

local function ApplyBarTexture(fill, texPath, texKey)
    local edge = THIN_LINE_KEYS[texKey]
    if edge then
        fill:SetStatusBarTexture(BAR_TEX)
        SetupThinLine(fill, edge)
    else
        fill:SetStatusBarTexture(texPath)
        ClearThinLine(fill)
    end
end

-------------------------------------------------------------------------------
--  Physical pixel spacing
-------------------------------------------------------------------------------
-- Convert user values to physical pixels (user setting = physical pixel count)
local function PhysicalPixels(userValue)
    local PP = EUI and EUI.PP
    local mult = (PP and PP.mult) or 1
    return (userValue or 0) * mult
end

-------------------------------------------------------------------------------
--  Number formatting
-------------------------------------------------------------------------------
local _abbreviateCfg
do
    local opts = {
        { breakpoint = 1000000000, abbreviation = "B", significandDivisor = 10000000, fractionDivisor = 100, abbreviationIsGlobal = false },
        { breakpoint = 1000000,    abbreviation = "M", significandDivisor = 10000,    fractionDivisor = 100, abbreviationIsGlobal = false },
        { breakpoint = 1000,       abbreviation = "K", significandDivisor = 100,      fractionDivisor = 10,  abbreviationIsGlobal = false },
        { breakpoint = 1,          abbreviation = "",  significandDivisor = 1,         fractionDivisor = 1,   abbreviationIsGlobal = false },
    }
    if CreateAbbreviateConfig then
        _abbreviateCfg = { config = CreateAbbreviateConfig(opts) }
    end
end

local function AbbrevNumber(n)
    if n == nil then return "0" end
    if AbbreviateNumbers then
        return AbbreviateNumbers(n, _abbreviateCfg) or "0"
    end
    local num = tonumber(n)
    if not num then return "?" end
    if num >= 1e9 then return format("%.1fB", num / 1e9)
    elseif num >= 1e6 then return format("%.1fM", num / 1e6)
    elseif num >= 1e3 then return format("%.1fK", num / 1e3)
    else return format("%.0f", num) end
end

local function FormatBarValue(amt, perSec, numFmt)
    if numFmt == 0 then
        return AbbrevNumber(perSec)
    end
    if numFmt == 2 and perSec then
        return format("%s (%s)", AbbrevNumber(amt), AbbrevNumber(perSec))
    end
    return AbbrevNumber(amt)
end

local function StripRealm(name)
    if not name then return "Unknown" end
    if Ambiguate then return Ambiguate(name, "short") or name end
    return name
end

local function FormatTimer(seconds)
    if not seconds or (issecretvalue and issecretvalue(seconds)) then return "0:00" end
    return format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

-------------------------------------------------------------------------------
--  Class icon sprite system
-------------------------------------------------------------------------------
local CLASS_ICON_SPRITE_BASE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\"
local CLASS_ICON_SPRITE_TEX = {}
for _, style in ipairs({"modern", "dark", "light", "clean"}) do
    CLASS_ICON_SPRITE_TEX[style] = CLASS_ICON_SPRITE_BASE .. style .. ".tga"
end
local CLASS_SPRITE_COORDS = {
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

local ICON_STYLE_VALUES = {
    none     = "None",
    spec     = "Default Spec Icons",
    blizzard = "Blizzard",
    modern   = "Modern",
    pixel    = "Pixel",
    glyph    = "Glyph",
    arcade   = "Arcade",
    legend   = "Legend",
    midnight = "Midnight",
    runic    = "Runic",
}
local ICON_STYLE_ORDER = {
    "none", "spec", "---", "blizzard", "modern", "pixel", "glyph",
    "arcade", "legend", "midnight", "runic",
}
_G._EDM_IconStyleValues = ICON_STYLE_VALUES
_G._EDM_IconStyleOrder  = ICON_STYLE_ORDER

local function ResolveIcon(src, iconTex, barH)
    local cfg = DB()
    local style = cfg.iconStyle or "spec"
    if style == "none" then iconTex:Hide(); return 0 end

    local classFile = src.classFilename
    if not classFile or (issecretvalue and issecretvalue(classFile)) or classFile == "" then iconTex:Hide(); return 0 end

    if style == "spec" then
        local specIcon = src.specIconID
        if specIcon and type(specIcon) == "number" and specIcon ~= 0 then
            iconTex:SetTexture(specIcon)
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            iconTex:SetSize(barH, barH)
            iconTex:SetDesaturated(false)
            iconTex:SetVertexColor(1, 1, 1, 1)
            iconTex:Show()
            return barH
        end
        iconTex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if coords then iconTex:SetTexCoord(unpack(coords)) else iconTex:SetTexCoord(0, 1, 0, 1) end
    elseif style == "blizzard" then
        iconTex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if coords then iconTex:SetTexCoord(unpack(coords)) else iconTex:SetTexCoord(0, 1, 0, 1) end
    else
        local coords = CLASS_SPRITE_COORDS[classFile]
        if coords then
            iconTex:SetTexture(CLASS_ICON_SPRITE_TEX[style] or (CLASS_ICON_SPRITE_BASE .. style .. ".tga"))
            iconTex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            iconTex:Hide(); return 0
        end
    end
    iconTex:SetSize(barH, barH)
    iconTex:SetDesaturated(false)
    iconTex:SetVertexColor(1, 1, 1, 1)
    iconTex:Show()
    return barH
end

-------------------------------------------------------------------------------
--  Enemy Damage Taken: aggregate combatSpellDetails into per-player totals
--  Returns sorted array of { name, class, specIcon, total } or nil on failure.
-------------------------------------------------------------------------------
local function AggregateEnemyPlayers(srcData)
    if not srcData or not srcData.combatSpells or #srcData.combatSpells == 0 then return nil end
    local byName = {}
    local list = {}
    for _, spell in ipairs(srcData.combatSpells) do
        local det = spell.combatSpellDetails
        if det then
            local name = det.unitName
            if name and not (issecretvalue and issecretvalue(name)) then
                local ok, amt = pcall(function() return spell.totalAmount end)
                local amount = (ok and amt) or 0
                local p = byName[name]
                if not p then
                    p = { name = name, class = det.unitClassFilename, specIcon = det.specIconID, total = 0 }
                    byName[name] = p
                    list[#list + 1] = p
                end
                p.total = p.total + amount
            end
        end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a.total > b.total end)
    return list
end

-------------------------------------------------------------------------------
--  Damage Done targets: cross-reference EnemyDamageTaken to build a complete
--  map of ALL players' damage per enemy in one pass. First hover triggers the
--  build; all subsequent hovers for any player are instant cache lookups.
--  Invalidated on DAMAGE_METER_RESET and COMBAT_SESSION_UPDATED.
-------------------------------------------------------------------------------
local _targetsCache = {}  -- { key = sessionKey, map = { [playerName] = sorted targets } }

local function BuildAllPlayerTargets(session, sessionID)

    local cacheKey = tostring(session) .. "|" .. tostring(sessionID)
    if _targetsCache.key == cacheKey then return _targetsCache.map end

    if not C_DamageMeter then return nil end

    local enemySession
    if sessionID and C_DamageMeter.GetCombatSessionFromID then
        local ok, s = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, Enum.DamageMeterType.EnemyDamageTaken)
        if ok then enemySession = s end
    elseif C_DamageMeter.GetCombatSessionFromType then
        local ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, session, Enum.DamageMeterType.EnemyDamageTaken)
        if ok then enemySession = s end
    end
    if not enemySession or not enemySession.combatSources or #enemySession.combatSources == 0 then
        _targetsCache.key = cacheKey; _targetsCache.map = nil
    
        return nil
    end

    -- Build per-player target totals keyed by unitName (readable from EnemyDamageTaken).
    -- Uses creatureID as enemy key (numeric, never secret) to avoid secret table keys.
    local enemyNames = {}  -- creatureID -> display name
    local byPlayer = {}    -- unitName -> { [creatureID] = totalDamage }
    for ei = 1, #enemySession.combatSources do
        local enemy = enemySession.combatSources[ei]
        local rawCID = enemy.sourceCreatureID
        local eKey = (rawCID and not (issecretvalue and issecretvalue(rawCID))) and rawCID or ei
        enemyNames[eKey] = enemy.name
        local srcData
        if sessionID and C_DamageMeter.GetCombatSessionSourceFromID then
            local ok, sd = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sessionID, Enum.DamageMeterType.EnemyDamageTaken, enemy.sourceGUID, enemy.sourceCreatureID)
            if ok then srcData = sd end
        elseif C_DamageMeter.GetCombatSessionSourceFromType then
            local ok, sd = pcall(C_DamageMeter.GetCombatSessionSourceFromType, session, Enum.DamageMeterType.EnemyDamageTaken, enemy.sourceGUID, enemy.sourceCreatureID)
            if ok then srcData = sd end
        end
        if srcData and srcData.combatSpells then
            for _, spell in ipairs(srcData.combatSpells) do
                local det = spell.combatSpellDetails
                if det and det.unitName and not (issecretvalue and issecretvalue(det.unitName)) then
                    local pName = det.unitName
                    local ok, amt = pcall(function() return spell.totalAmount end)
                    local amount = (ok and amt) or 0
                    if amount > 0 then
                        local pt = byPlayer[pName]
                        if not pt then pt = {}; byPlayer[pName] = pt end
                        pt[eKey] = (pt[eKey] or 0) + amount
                    end
                end
            end
        end
    end

    -- Convert each player's enemy map to a sorted array
    local map = {}
    for pName, enemies in pairs(byPlayer) do
        local list = {}
        for eKey, total in pairs(enemies) do
            list[#list + 1] = { name = enemyNames[eKey], total = total }
        end
        table.sort(list, function(a, b) return a.total > b.total end)
        map[pName] = list
    end

    _targetsCache.key = cacheKey; _targetsCache.map = map

    return map
end

local function BuildPlayerTargets(playerName, session, sessionID, maxTargets)

    if not playerName then return nil end
    if issecretvalue and issecretvalue(playerName) then return nil end
    if playerName == "" then return nil end

    local map = BuildAllPlayerTargets(session, sessionID)
    if not map then return nil end

    local list = map[playerName]
    if not list or #list == 0 then return nil end

    if #list > maxTargets then
        local trimmed = {}
        for i = 1, maxTargets do trimmed[i] = list[i] end
    
        return trimmed
    end

    return list
end

-------------------------------------------------------------------------------
--  Hover tooltip (shared across all windows)
-------------------------------------------------------------------------------
local TT_DEFAULT_MAX = 8
local TT_BAR_H = 18
local TT_BAR_SP = 1
local TT_WIDTH = 275
local function TT_MAX()
    local cfg = DB and DB()
    return (cfg and cfg.showAllBreakdownSpells == false) and TT_DEFAULT_MAX or 50
end

local _ttFrame, _ttBars, _ttVisible = nil, {}, false
local _activeRow = nil

local TT_HDR_H = 20

local function EnsureTooltipFrame()
    if _ttFrame then return end
    _ttFrame = CreateFrame("Frame", nil, UIParent)
    _ttFrame:SetFrameStrata("TOOLTIP")
    _ttFrame:SetSize(TT_WIDTH, 10)
    _ttFrame:SetClampedToScreen(true)
    _ttFrame._bg = _ttFrame:CreateTexture(nil, "BACKGROUND")
    _ttFrame._bg:SetAllPoints()
    _ttFrame._bg:SetColorTexture(0, 0, 0, 0.95)
    if EUI.MakeBorder then EUI.MakeBorder(_ttFrame, 0, 0, 0, 1) end

    -- Header bar
    _ttFrame._hdr = CreateFrame("Frame", nil, _ttFrame)
    _ttFrame._hdr:SetHeight(TT_HDR_H)
    _ttFrame._hdr:SetPoint("TOPLEFT", _ttFrame, "TOPLEFT", 0, 0)
    _ttFrame._hdr:SetPoint("TOPRIGHT", _ttFrame, "TOPRIGHT", 0, 0)
    local hdrBg = _ttFrame._hdr:CreateTexture(nil, "BACKGROUND", nil, 1)
    hdrBg:SetAllPoints()
    _ttFrame._hdrBg = hdrBg
    _ttFrame._hdrText = _ttFrame._hdr:CreateFontString(nil, "OVERLAY")
    _ttFrame._hdrText:SetPoint("LEFT", _ttFrame._hdr, "LEFT", 5, 0)
    _ttFrame._hdrText:SetWidth(TT_WIDTH - 25); _ttFrame._hdrText:SetJustifyH("LEFT"); _ttFrame._hdrText:SetWordWrap(false)
    SetDMFont(_ttFrame._hdrText, 10)

    -- Combat lockdown message (shown instead of bars)
    _ttFrame._combatMsg = _ttFrame:CreateFontString(nil, "OVERLAY")
    _ttFrame._combatMsg:SetPoint("TOP", _ttFrame._hdr, "BOTTOM", 0, -8)
    _ttFrame._combatMsg:SetPoint("LEFT", _ttFrame, "LEFT", 8, 0)
    _ttFrame._combatMsg:SetPoint("RIGHT", _ttFrame, "RIGHT", -8, 0)
    _ttFrame._combatMsg:SetJustifyH("CENTER"); _ttFrame._combatMsg:SetWordWrap(true)
    SetDMFont(_ttFrame._combatMsg, 10)
    _ttFrame._combatMsg:SetTextColor(0.6, 0.6, 0.6, 1)
    _ttFrame._combatMsg:SetText("Detailed information is\nsecret while in combat")
    _ttFrame._combatMsg:Hide()

    _ttFrame:SetScript("OnShow", function() _ttVisible = true end)
    _ttFrame:SetScript("OnHide", function() _ttVisible = false end)

    _ttFrame:Hide()
end

-- Lazy bar pool: creates bars on demand up to the requested index
local function EnsureTTBar(i)
    if _ttBars[i] then return _ttBars[i] end
    EnsureTooltipFrame()
    local ttSp = PhysicalPixels(1)
    local b = {}
    b.row = CreateFrame("Frame", nil, _ttFrame)
    b.row:SetHeight(TT_BAR_H)
    b.row:SetPoint("TOPLEFT", _ttFrame, "TOPLEFT", 0, -(TT_HDR_H + (i-1) * (TT_BAR_H + ttSp)))
    b.row:SetPoint("TOPRIGHT", _ttFrame, "TOPRIGHT", 0, -(TT_HDR_H + (i-1) * (TT_BAR_H + ttSp)))
    b.fill = CreateFrame("StatusBar", nil, b.row)
    b.fill:SetAllPoints(); b.fill:SetMinMaxValues(0, 1); b.fill:SetValue(0); b.fill:SetStatusBarTexture(BAR_TEX)
    b.spellIcon = b.row:CreateTexture(nil, "OVERLAY")
    b.spellIcon:SetSize(TT_BAR_H, TT_BAR_H)
    b.spellIcon:SetPoint("LEFT", b.row, "LEFT", 0, 0)
    b.spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.spellIcon:Hide()
    local tf = CreateFrame("Frame", nil, b.fill)
    tf:SetAllPoints(b.fill); tf:SetFrameLevel(b.fill:GetFrameLevel() + 2)
    b.label = tf:CreateFontString(nil, "OVERLAY"); b.label:SetPoint("LEFT", tf, "LEFT", 2, 0); b.label:SetJustifyH("LEFT"); SetDMFont(b.label, 10)
    b.amount = tf:CreateFontString(nil, "OVERLAY"); b.amount:SetPoint("RIGHT", tf, "RIGHT", -2, 0); b.amount:SetJustifyH("RIGHT"); SetDMFont(b.amount, 10)
    b.label:SetPoint("RIGHT", b.amount, "LEFT", -3, 0)
    b.row:Hide()
    _ttBars[i] = b
    return b
end

local _ttLastSp = -1
local _ttSorted = {}

local function PopulatePreview(bar, curSession, curSessionID, curDMType)

    if _ttFrame and _ttFrame._combatMsg then _ttFrame._combatMsg:Hide() end
    -- Hide target sub-elements from prior tooltip
    if _ttFrame and _ttFrame._tgtDivider then
        _ttFrame._tgtDivider:Hide(); _ttFrame._tgtLabel:Hide()
        for ti = 1, 3 do _ttFrame._tgtBars[ti].row:Hide() end
    end
    if not bar._src then return false end
    if not bar._srcGUID and not bar._src.sourceCreatureID then return false end
    if not C_DamageMeter then return false end

    -- Reposition tooltip bars with physical-pixel spacing (only when spacing changes)
    local ttSp = PhysicalPixels(1)
    local ttStride = TT_BAR_H + ttSp
    if ttSp ~= _ttLastSp then
        _ttLastSp = ttSp
        for ti = 1, #_ttBars do
            local b = _ttBars[ti]
            if b then
                b.row:ClearAllPoints()
                b.row:SetPoint("TOPLEFT", _ttFrame, "TOPLEFT", 0, -(TT_HDR_H + (ti-1) * ttStride))
                b.row:SetPoint("TOPRIGHT", _ttFrame, "TOPRIGHT", 0, -(TT_HDR_H + (ti-1) * ttStride))
            end
        end
    end

    -- Helper: apply header styling
    local function ApplyTTHeader(playerName, typeName)
        EnsureTooltipFrame()
        _ttFrame._hdrText:SetText(playerName .. "'s " .. typeName .. " Breakdown")
        local cfg = DB()
        local hc = cfg.hdrBgColor; local hR = hc and hc.r or 0x1B/255; local hG = hc and hc.g or 0x1B/255; local hB = hc and hc.b or 0x1B/255
        _ttFrame._hdrBg:SetColorTexture(hR, hG, hB, cfg.hdrBgAlpha or 1)
        local tR, tG, tB
        if cfg.hdrTextUseAccent ~= false then tR, tG, tB = GetAccentRGB()
        else local tc = cfg.hdrTextColor; tR = tc and tc.r or 1; tG = tc and tc.g or 1; tB = tc and tc.b or 1 end
        _ttFrame._hdrText:SetTextColor(tR, tG, tB, 1)
    end

    -- Death recap tooltip: show last few events before death
    if curDMType == Enum.DamageMeterType.Deaths then
        local recapID = bar._src.deathRecapID
        if recapID and issecretvalue and issecretvalue(recapID) then recapID = nil end
        if not recapID or recapID <= 0 or not C_DeathRecap or not C_DeathRecap.GetRecapEvents then return false end
        local ok, raw = pcall(C_DeathRecap.GetRecapEvents, recapID)
        if not ok or not raw or #raw == 0 then return false end
        local maxHP = 1
        if C_DeathRecap.GetRecapMaxHealth then
            local ok2, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
            if ok2 and hp and type(hp) == "number" and hp > 0 then maxHP = hp end
        end
        -- Reverse to oldest-first
        local reversed = {}
        for ri = #raw, 1, -1 do reversed[#reversed + 1] = raw[ri] end
        ApplyTTHeader(StripRealm(bar._src.name) or "Unknown", "Death Recap")
        local texPath, texKey = GetBreakdownBarTexturePath()
        local deathTime = reversed[#reversed] and reversed[#reversed].timestamp or GetTime()
        local total = #reversed
        local ttMax = TT_MAX()
        local count = math.min(ttMax, total)
        local startIdx = total - count  -- skip oldest events, show last N
        for i = 1, math.max(ttMax, #_ttBars) do
            local b = EnsureTTBar(i)
            if i <= count then
                local ev = reversed[startIdx + i]
                local spID = ev.spellId
                local spIcon
                if spID and spID > 0 then spIcon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spID) end
                if not spIcon then spIcon = 135274 end
                b.spellIcon:SetTexture(spIcon); b.spellIcon:Show()
                b.fill:ClearAllPoints(); b.fill:SetPoint("TOPLEFT", b.spellIcon, "TOPRIGHT", 0, 0); b.fill:SetPoint("BOTTOMRIGHT", b.row, "BOTTOMRIGHT", 0, 0)
                local curHP = ev.currentHP or 0
                local hpPct = maxHP > 0 and (curHP / maxHP) or 0
                hpPct = math.min(1, math.max(0, hpPct))
                ApplyBarTexture(b.fill, texPath, texKey); b.fill:SetMinMaxValues(0, 1); b.fill:SetValue(hpPct)
                local evType = ev.event or ""
                local isHeal = (evType == "SPELL_HEAL" or evType == "SPELL_PERIODIC_HEAL")
                local isFatal = (i == count and not isHeal)
                if isHeal then b.fill:SetStatusBarColor(0.10, 0.50, 0.10)
                else b.fill:SetStatusBarColor(0.60, 0.08, 0.08) end
                local spellName = ev.spellName
                if not spellName or (issecretvalue and issecretvalue(spellName)) or spellName == "" then
                    if isHeal then spellName = "Heal"
                    elseif evType == "SWING_DAMAGE" then spellName = "Melee"
                    else spellName = "Unknown" end
                end
                b.label:SetTextColor(1, 1, 1); b.amount:SetTextColor(1, 1, 1)
                -- Label: time before death + spell name
                local td = deathTime - (ev.timestamp or deathTime)
                b.label:SetText(format("-%.1fs", td) .. " " .. spellName)
                -- Amount: damage/heal + overkill on killing blow + HP%
                local amt = ev.amount or 0
                local amtStr = isHeal and ("+" .. AbbrevNumber(math.abs(amt))) or ("-" .. AbbrevNumber(amt))
                local overkill = ev.overkill
                if isFatal and overkill and type(overkill) == "number" and overkill > 0 then
                    b.amount:SetText(amtStr .. " |cffff3333(" .. AbbrevNumber(overkill) .. " overkill)|r (" .. format("%.0f%%", hpPct * 100) .. ")")
                else
                    b.amount:SetText(amtStr .. " (" .. format("%.0f%%", hpPct * 100) .. ")")
                end
                b.row:Show()
            else b.row:Hide() end
        end
        _ttFrame:SetSize(TT_WIDTH, TT_HDR_H + count * ttStride - (count > 0 and ttSp or 0))
        return true
    end

    -- Enemy Damage Taken tooltip: show per-player breakdown
    if curDMType == Enum.DamageMeterType.EnemyDamageTaken then
        local guid = bar._srcGUID
        local cid = bar._src.sourceCreatureID
        if issecretvalue and (issecretvalue(guid) or issecretvalue(cid)) then return false end
        local srcData
        if curSessionID and C_DamageMeter.GetCombatSessionSourceFromID then
            srcData = C_DamageMeter.GetCombatSessionSourceFromID(curSessionID, curDMType, guid, cid)
        elseif C_DamageMeter.GetCombatSessionSourceFromType then
            srcData = C_DamageMeter.GetCombatSessionSourceFromType(curSession, curDMType, guid, cid)
        end
        local players = AggregateEnemyPlayers(srcData)
        if not players then return false end

        ApplyTTHeader(StripRealm(bar._src.name) or "Unknown", "Damage Taken")
        local texPath, texKey = GetBreakdownBarTexturePath()
        local maxAmt = players[1].total
        local ttMax = TT_MAX()
        local count = math.min(ttMax, #players)
        for i = 1, math.max(ttMax, #_ttBars) do
            local b = EnsureTTBar(i)
            if i <= count then
                local p = players[i]
                -- Use spec icon if available, else class atlas
                local specIcon = p.specIcon
                if specIcon and type(specIcon) == "number" and specIcon ~= 0 then
                    b.spellIcon:SetTexture(specIcon)
                    b.spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    b.spellIcon:Show()
                elseif p.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[p.class] then
                    b.spellIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                    b.spellIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[p.class]))
                    b.spellIcon:Show()
                else
                    b.spellIcon:Hide()
                end
                if b.spellIcon:IsShown() then
                    b.fill:ClearAllPoints(); b.fill:SetPoint("TOPLEFT", b.spellIcon, "TOPRIGHT", 0, 0); b.fill:SetPoint("BOTTOMRIGHT", b.row, "BOTTOMRIGHT", 0, 0)
                else
                    b.fill:ClearAllPoints(); b.fill:SetAllPoints(b.row)
                end
                ApplyBarTexture(b.fill, texPath, texKey); b.fill:SetMinMaxValues(0, maxAmt); b.fill:SetValue(p.total)
                local cc = p.class and RAID_CLASS_COLORS[p.class]
                if cc then b.fill:SetStatusBarColor(cc.r, cc.g, cc.b)
                else b.fill:SetStatusBarColor(0x33/255, 0x33/255, 0x33/255) end
                b.label:SetTextColor(1, 1, 1); b.amount:SetTextColor(1, 1, 1)
                b.label:SetText(StripRealm(p.name))
                b.amount:SetText(AbbrevNumber(p.total))
                b.row:Show()
            else b.row:Hide() end
        end
        _ttFrame:SetSize(TT_WIDTH, TT_HDR_H + count * ttStride - (count > 0 and ttSp or 0))
        return true
    end

    -- Standard spell breakdown tooltip
    local guid = bar._srcGUID
    local cid = bar._src.sourceCreatureID
    if issecretvalue and (issecretvalue(guid) or issecretvalue(cid)) then return false end
    local srcData
    if curSessionID and C_DamageMeter.GetCombatSessionSourceFromID then
        srcData = C_DamageMeter.GetCombatSessionSourceFromID(curSessionID, curDMType, guid, cid)
    elseif C_DamageMeter.GetCombatSessionSourceFromType then
        srcData = C_DamageMeter.GetCombatSessionSourceFromType(curSession, curDMType, guid, cid)
    end
    if not srcData or not srcData.combatSpells or #srcData.combatSpells == 0 then return false end

    ApplyTTHeader(StripRealm(bar._src.name) or "Unknown", DM_TYPE_NAMES[curDMType] or "Damage Done")

    wipe(_ttSorted)
    for _, spell in ipairs(srcData.combatSpells) do
        local amt = spell.totalAmount
        if issecretvalue and issecretvalue(amt) then amt = 0
        elseif type(amt) ~= "number" then amt = 0 end
        _ttSorted[#_ttSorted + 1] = { spell = spell, amount = amt }
    end
    local maxAmt = _ttSorted[1] and _ttSorted[1].amount or 1
    local totalDmg = 0
    local canPercent = type(maxAmt) == "number" and (not issecretvalue or not issecretvalue(maxAmt))
    if canPercent then for _, e in ipairs(_ttSorted) do totalDmg = totalDmg + e.amount end end
    local texPath, texKey = GetBreakdownBarTexturePath()
    local ttMax = TT_MAX()
    local count = math.min(ttMax, #_ttSorted)
    for i = 1, math.max(ttMax, #_ttBars) do
        local b = EnsureTTBar(i)
        if i <= count then
            local entry = _ttSorted[i]
            local spell = entry.spell
            local hasIcon = false
            if spell.spellID then
                local spIcon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell.spellID)
                if spIcon then
                    hasIcon = true
                    b.spellIcon:SetTexture(spIcon); b.spellIcon:Show()
                end
            end
            if not hasIcon then b.spellIcon:Hide() end
            -- Only re-anchor fill when icon state changes
            if hasIcon ~= b._lastHasIcon then
                b._lastHasIcon = hasIcon
                b.fill:ClearAllPoints()
                if hasIcon then
                    b.fill:SetPoint("TOPLEFT", b.spellIcon, "TOPRIGHT", 0, 0)
                    b.fill:SetPoint("BOTTOMRIGHT", b.row, "BOTTOMRIGHT", 0, 0)
                else
                    b.fill:SetAllPoints(b.row)
                end
            end
            ApplyBarTexture(b.fill, texPath, texKey); b.fill:SetMinMaxValues(0, maxAmt); b.fill:SetValue(entry.amount)
            b.fill:SetStatusBarColor(0x33/255, 0x33/255, 0x33/255)
            local spellName
            if spell.spellID then
                spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell.spellID)
                if issecretvalue and issecretvalue(spellName) then spellName = nil end
            end
            b.label:SetText(spellName or spell.creatureName or "Unknown")
            if canPercent and totalDmg > 0 then
                b.amount:SetText(format("%s  %.1f%%", AbbrevNumber(entry.amount), (entry.amount / totalDmg) * 100))
            else
                b.amount:SetText(AbbrevNumber(entry.amount))
            end
            b.row:Show()
        else b.row:Hide() end
    end
    -- Targets sub-section (DamageDone only): top 3 enemies this player hit
    local ttTargetCount = 0
    if curDMType == Enum.DamageMeterType.DamageDone then
        local rawName = bar._src and bar._src.name
        local targets = BuildPlayerTargets(rawName, curSession, curSessionID, 3)
        if targets then
            -- Lazy-create tooltip target elements
            if not _ttFrame._tgtDivider then
                _ttFrame._tgtDivider = _ttFrame:CreateTexture(nil, "ARTWORK")
                _ttFrame._tgtDivider:SetHeight(PhysicalPixels(1)); _ttFrame._tgtDivider:SetColorTexture(1, 1, 1, 0.15)
                _ttFrame._tgtLabel = _ttFrame:CreateFontString(nil, "OVERLAY")
                SetDMFont(_ttFrame._tgtLabel, 9); _ttFrame._tgtLabel:SetTextColor(0.6, 0.6, 0.6, 1)
                _ttFrame._tgtLabel:SetText("Targets")
                _ttFrame._tgtBars = {}
                for ti = 1, 3 do
                    local tb = {}
                    tb.row = CreateFrame("Frame", nil, _ttFrame); tb.row:SetHeight(TT_BAR_H)
                    tb.fill = CreateFrame("StatusBar", nil, tb.row); tb.fill:SetAllPoints(); tb.fill:SetMinMaxValues(0, 1); tb.fill:SetStatusBarTexture(BAR_TEX)
                    local tf = CreateFrame("Frame", nil, tb.fill); tf:SetAllPoints(tb.fill); tf:SetFrameLevel(tb.fill:GetFrameLevel() + 2)
                    tb.label = tf:CreateFontString(nil, "OVERLAY"); tb.label:SetPoint("LEFT", tf, "LEFT", 2, 0); tb.label:SetJustifyH("LEFT"); SetDMFont(tb.label, 10)
                    tb.amount = tf:CreateFontString(nil, "OVERLAY"); tb.amount:SetPoint("RIGHT", tf, "RIGHT", -2, 0); tb.amount:SetJustifyH("RIGHT"); SetDMFont(tb.amount, 10)
                    tb.label:SetPoint("RIGHT", tb.amount, "LEFT", -3, 0)
                    tb.row:Hide()
                    _ttFrame._tgtBars[ti] = tb
                end
            end
            local baseY = -(TT_HDR_H + count * ttStride + ttSp * 2)
            _ttFrame._tgtDivider:ClearAllPoints()
            _ttFrame._tgtDivider:SetPoint("TOPLEFT", _ttFrame, "TOPLEFT", 0, baseY)
            _ttFrame._tgtDivider:SetPoint("TOPRIGHT", _ttFrame, "TOPRIGHT", 0, baseY)
            _ttFrame._tgtDivider:Show()
            local lblY = baseY - 10
            _ttFrame._tgtLabel:ClearAllPoints()
            _ttFrame._tgtLabel:SetPoint("LEFT", _ttFrame, "TOPLEFT", 3, lblY)
            _ttFrame._tgtLabel:Show()
            local tStartY = lblY - 10
            local tMaxAmt = targets[1].total
            for ti = 1, 3 do
                local tb = _ttFrame._tgtBars[ti]
                if ti <= #targets then
                    local t = targets[ti]
                    tb.row:ClearAllPoints()
                    tb.row:SetPoint("TOPLEFT", _ttFrame, "TOPLEFT", 0, tStartY - ((ti-1) * ttStride))
                    tb.row:SetPoint("TOPRIGHT", _ttFrame, "TOPRIGHT", 0, tStartY - ((ti-1) * ttStride))
                    ApplyBarTexture(tb.fill, texPath, texKey); tb.fill:SetMinMaxValues(0, tMaxAmt); tb.fill:SetValue(t.total)
                    tb.fill:SetStatusBarColor(0xDD/255, 0x31/255, 0x31/255)
                    tb.label:SetTextColor(1, 1, 1); tb.amount:SetTextColor(1, 1, 1)
                    tb.label:SetText(t.name)
                    tb.amount:SetText(AbbrevNumber(t.total))
                    tb.row:Show()
                    ttTargetCount = ttTargetCount + 1
                else tb.row:Hide() end
            end
        end
    end
    -- Hide target elements if not used
    if ttTargetCount == 0 and _ttFrame and _ttFrame._tgtDivider then
        _ttFrame._tgtDivider:Hide(); _ttFrame._tgtLabel:Hide()
        for ti = 1, 3 do _ttFrame._tgtBars[ti].row:Hide() end
    end
    local totalH = TT_HDR_H + count * ttStride - (count > 0 and ttSp or 0)
    if ttTargetCount > 0 then
        totalH = totalH + (ttSp * 2) + 1 + 10 + 10 + (ttTargetCount * ttStride)
    end
    _ttFrame:SetSize(TT_WIDTH, totalH)

    return true
end

local _ttLastGUID, _ttLastSession, _ttLastSessionID, _ttLastDMType
local _ttLastScale, _ttLastAnchor

local function ShowBarTooltip(bar, curSession, curSessionID, curDMType)

    local cfg = DB()
    if cfg.showHoverTooltip == false then return end
    EnsureTooltipFrame()
    local barRow = bar.row
    local anchorMode = cfg.breakdownAnchorPoint
    local desiredAnchor = (anchorMode == "center") and "CENTER" or barRow
    -- Skip full rebuild if tooltip is already populated for this exact player + session
    local barGUID = bar._srcGUID
    if barGUID == _ttLastGUID and curSession == _ttLastSession and curSessionID == _ttLastSessionID and curDMType == _ttLastDMType then
        if _ttLastAnchor ~= desiredAnchor then
            _ttFrame:ClearAllPoints()
            if desiredAnchor == "CENTER" then
                _ttFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                _ttLastAnchor = "CENTER"
            else
                _ttFrame:SetPoint("BOTTOMRIGHT", barRow, "TOPRIGHT", 0, 0)
                _ttLastAnchor = barRow
            end
        end
        _ttFrame:Show()
    
        return
    end
    if PopulatePreview(bar, curSession, curSessionID, curDMType) then
        _ttLastGUID = barGUID; _ttLastSession = curSession; _ttLastSessionID = curSessionID; _ttLastDMType = curDMType
        local scale = (cfg.hoverTooltipScale or 100) / 100
        if scale ~= _ttLastScale then
            _ttFrame:SetScale(scale)
            _ttLastScale = scale
        end
        _ttFrame:ClearAllPoints()
        if anchorMode == "center" then
            _ttFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            _ttLastAnchor = "CENTER"
        else
            _ttFrame:SetPoint("BOTTOMRIGHT", barRow, "TOPRIGHT", 0, 0)
            _ttLastAnchor = barRow
        end
        _ttFrame:Show()
    else
        HideBarTooltip()
    end

end

local function HideBarTooltip()
    if _ttFrame then _ttFrame:Hide() end
    _ttLastGUID = nil; _ttLastAnchor = nil

end

local _hoverPollFrame = CreateFrame("Frame")
_hoverPollFrame:Hide()
_hoverPollFrame:SetScript("OnUpdate", function()
    if not _activeRow then return end
    if not _ttVisible and _activeRow._win then
        local W = _activeRow._win
        ShowBarTooltip(_activeRow, W.curSession, W.curSessionID, W.curDMType)
    end
end)

-------------------------------------------------------------------------------
--  EDM Context Menu (shared)
-------------------------------------------------------------------------------
local _edmMenu, _edmSub
local CTX_ITEM_H   = 22
local CTX_HDR_H    = 20
local CTX_SEP_H    = 7
local CTX_PAD      = 0
local CTX_MIN_W    = 100
local CTX_FONT_SZ  = 11
local CTX_ARROW_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow.png"

local function MakeMenuPanel(level)
    local RS = EUI.RESKIN or {}
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(200 + (level or 0) * 10)
    f:SetClampedToScreen(true); f:EnableMouse(true)
    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
    bg:SetColorTexture(RS.BG_R or 0.067, RS.BG_G or 0.067, RS.BG_B or 0.067, RS.CTX_ALPHA or 0.95)
    local PP_L = EUI.PP
    if PP_L and PP_L.CreateBorder then PP_L.CreateBorder(f, 1, 1, 1, RS.BRD_ALPHA or 0.18, 1) end
    f._pool = {}; f:Hide()
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function(self) self:Hide() end)
    return f
end

local function EnsureMenuRow(menu, idx)
    local row = menu._pool[idx]
    if row then return row end
    local fontPath = (EUI.GetFontPath and EUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
    local outline = (EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag()) or ""
    row = CreateFrame("Button", nil, menu)
    row._hl = row:CreateTexture(nil, "BACKGROUND", nil, 1); row._hl:SetAllPoints()
    row._lbl = row:CreateFontString(nil, "OVERLAY"); row._lbl:SetFont(fontPath, CTX_FONT_SZ, outline)
    row._lbl:SetPoint("LEFT", row, "LEFT", 8, 0); row._lbl:SetJustifyH("LEFT")
    row._arrow = row:CreateTexture(nil, "ARTWORK"); row._arrow:SetTexture(CTX_ARROW_ICON)
    row._arrow:SetSize(19, 19); row._arrow:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row._arrow:SetRotation(math.pi / 2); row._arrow:SetVertexColor(1, 1, 1, 0.75); row._arrow:Hide()
    row._timer = row:CreateFontString(nil, "OVERLAY"); row._timer:SetFont(fontPath, CTX_FONT_SZ, outline)
    row._timer:SetPoint("RIGHT", row, "RIGHT", -8, 0); row._timer:SetJustifyH("RIGHT"); row._timer:SetText("")
    row._sep = row:CreateTexture(nil, "ARTWORK"); row._sep:SetHeight(1)
    row._sep:SetPoint("LEFT", row, "LEFT", 6, 0); row._sep:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row._sep:SetColorTexture(1, 1, 1, 0.12); row._sep:SetPoint("CENTER"); row._sep:Hide()
    menu._pool[idx] = row
    return row
end

local function LayoutMenu(menu, items, onDismiss, isChild)
    local fontPath = (EUI.GetFontPath and EUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
    local outline = (EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag()) or ""
    local EG = EUI.ELLESMERE_GREEN
    local hlAlpha = EUI.DD_ITEM_HL_A or 0.08
    for _, r in ipairs(menu._pool) do r:Hide() end
    if not menu._mfs then menu._mfs = menu:CreateFontString(nil, "OVERLAY") end
    menu._mfs:SetFont(fontPath, CTX_FONT_SZ, outline)
    local maxW = 0
    for _, item in ipairs(items) do
        if type(item) == "table" and item.text then
            local extra = ""
            if item.timerText then extra = "  " .. item.timerText end
            menu._mfs:SetText(item.text .. extra); local w = menu._mfs:GetStringWidth() or 0
            if w > maxW then maxW = w end
        end
    end
    menu._mfs:SetText(""); menu._mfs:Hide()
    local menuW = math.max(CTX_MIN_W, maxW + 50)
    local y = -CTX_PAD
    for idx, item in ipairs(items) do
        local row = EnsureMenuRow(menu, idx)
        row._sep:Hide(); row._arrow:Hide(); row._hl:SetColorTexture(1, 1, 1, 0)
        if row._timer then row._timer:SetText("") end
        if item == "---" then
            row:SetSize(menuW, CTX_SEP_H); row:ClearAllPoints(); row:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, y)
            row._lbl:SetText(""); row._sep:Show(); row:EnableMouse(false)
            row:SetScript("OnEnter", nil); row:SetScript("OnLeave", nil); row:SetScript("OnClick", nil)
            row:Show(); y = y - CTX_SEP_H
        elseif item.isHeader then
            row:SetSize(menuW, CTX_HDR_H); row:ClearAllPoints(); row:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, y)
            row._lbl:SetFont(fontPath, CTX_FONT_SZ, outline); row._lbl:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row._lbl:SetText(item.text); row._lbl:SetTextColor(1, 0.82, 0, 1); row:EnableMouse(false)
            row:SetScript("OnEnter", nil); row:SetScript("OnLeave", nil); row:SetScript("OnClick", nil)
            row:Show(); y = y - CTX_HDR_H
        else
            local rowH = item.compact and (CTX_ITEM_H - 2) or CTX_ITEM_H
            row:SetSize(menuW, rowH); row:ClearAllPoints(); row:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, y)
            row._lbl:SetFont(fontPath, CTX_FONT_SZ, outline)
            row._lbl:SetText(item.text or ""); row:EnableMouse(true)
            -- Timer text (accent-colored, right-aligned)
            if item.timerText and row._timer then
                row._timer:SetFont(fontPath, CTX_FONT_SZ, outline)
                local ar, ag, ab = GetAccentRGB()
                row._timer:SetTextColor(ar, ag, ab, 0.9)
                row._timer:SetText(item.timerText)
                row._lbl:SetPoint("RIGHT", row._timer, "LEFT", -6, 0)
            else
                row._lbl:SetPoint("RIGHT", row, "RIGHT", -18, 0)
            end
            -- Inline input field (e.g. width entry)
            if item.isInput then
                row._lbl:SetTextColor(1, 1, 1, 1)
                row:EnableMouse(false)
                row:SetScript("OnEnter", nil); row:SetScript("OnLeave", nil); row:SetScript("OnClick", nil)
                if not row._editBox then
                    local box = CreateFrame("EditBox", nil, row)
                    box:SetSize(50, 18)
                    box:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                    box:SetFrameLevel(row:GetFrameLevel() + 3)
                    box:SetFont(fontPath, 10, outline)
                    box:SetTextColor(1, 1, 1, 0.9)
                    box:SetJustifyH("CENTER")
                    local boxBg = box:CreateTexture(nil, "BACKGROUND")
                    boxBg:SetAllPoints(); boxBg:SetColorTexture(0, 0, 0, 0.4)
                    box:SetAutoFocus(false)
                    box:SetNumeric(true)
                    box:SetMaxLetters(5)
                    row._editBox = box
                end
                row._editBox:Show()
                row._editBox:SetNumber(item.getValue and item.getValue() or 0)
                row._editBox:SetScript("OnEnterPressed", function(self)
                    local val = math.max(item.min or 1, math.floor(self:GetNumber() + 0.5))
                    self:SetNumber(val)
                    if item.setValue then item.setValue(val) end
                    self:ClearFocus()
                end)
                row._editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                row:Show(); y = y - rowH
            end
            if item.isInput then -- skip normal item logic
            else
            local disabled = item.isDisabled and item.isDisabled()
            if item.children then row._arrow:SetVertexColor(1, 1, 1, disabled and 0.2 or 0.75); row._arrow:Show() end
            if disabled then
                row._lbl:SetTextColor(0.4, 0.4, 0.4, 0.5)
                row:SetScript("OnEnter", function() if not isChild and _edmSub then _edmSub:Hide() end end)
                row:SetScript("OnLeave", nil); row:SetScript("OnClick", nil)
            else
                local active = item.isActive
                if active and EG then row._lbl:SetTextColor(EG.r, EG.g, EG.b, 1) else row._lbl:SetTextColor(1, 1, 1, 1) end
                if active then row._hl:SetColorTexture(1, 1, 1, hlAlpha); row._hl:Show() end
                local itemRef = item
                row:SetScript("OnEnter", function(self)
                    self._hl:SetColorTexture(1, 1, 1, hlAlpha)
                    if EG then self._lbl:SetTextColor(EG.r, EG.g, EG.b, 1) end
                    if itemRef.children then
                        if not _edmSub then _edmSub = MakeMenuPanel(1) end
                        LayoutMenu(_edmSub, itemRef.children, onDismiss, true)
                        _edmSub:ClearAllPoints()
                        local right = self:GetRight(); local subW = _edmSub:GetWidth(); local screenW = UIParent:GetRight()
                        if right and subW and screenW and (right + subW) > screenW then
                            _edmSub:SetPoint("TOPRIGHT", self, "TOPLEFT", 0, 0)
                        else _edmSub:SetPoint("TOPLEFT", self, "TOPRIGHT", 0, 0) end
                        _edmSub:Show()
                    elseif not isChild and _edmSub then _edmSub:Hide() end
                end)
                row:SetScript("OnLeave", function(self)
                    self._hl:SetColorTexture(1, 1, 1, active and hlAlpha or 0)
                    if active and EG then self._lbl:SetTextColor(EG.r, EG.g, EG.b, 1) else self._lbl:SetTextColor(1, 1, 1, 1) end
                    if isChild then return end
                    if _edmSub and _edmSub:IsShown() and _edmSub:IsMouseOver() then return end
                    if _edmSub and itemRef.children then _edmSub:Hide() end
                end)
                row:SetScript("OnClick", function()
                    if itemRef.children then return end
                    if itemRef.onClick then itemRef.onClick() end
                    if onDismiss then onDismiss() end
                end)
            end
            if row._editBox then row._editBox:Hide() end
            row:Show(); y = y - rowH
            end -- close isInput else
        end
    end
    menu:SetSize(menuW, math.abs(y) + CTX_PAD)
end

local _edmMenuAnchor = nil  -- tracks which button opened the menu (for toggle)

local function ShowEDMMenu(items, anchorBtn)
    if not _edmMenu then
        _edmMenu = MakeMenuPanel(0)
        local acc = 0
        _edmMenu:SetScript("OnUpdate", function(self, dt)
            acc = acc + dt; if acc < 0.1 then return end; acc = 0
            local over = self:IsMouseOver()
                or (_edmSub and _edmSub:IsShown() and _edmSub:IsMouseOver())
                or (_edmMenuAnchor and _edmMenuAnchor:IsMouseOver())
            if not over and IsMouseButtonDown("LeftButton") then self:Hide() end
        end)
        _edmMenu:HookScript("OnHide", function()
            if _edmSub then _edmSub:Hide() end
            _edmMenuAnchor = nil
        end)
    end

    -- Toggle: if same button clicked again while menu is open, close it
    if anchorBtn and _edmMenu:IsShown() and _edmMenuAnchor == anchorBtn then
        _edmMenu:Hide()
        return
    end

    local function dismiss() _edmMenu:Hide(); if _edmSub then _edmSub:Hide() end end
    LayoutMenu(_edmMenu, items, dismiss)
    _edmMenu:ClearAllPoints()
    if anchorBtn then
        _edmMenu:SetPoint("BOTTOMRIGHT", anchorBtn, "TOPRIGHT", 0, 0)
    else
        local scale = _edmMenu:GetEffectiveScale(); local cx, cy = GetCursorPosition()
        _edmMenu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
    end
    _edmMenuAnchor = anchorBtn
    _edmMenu:Show()
end

-------------------------------------------------------------------------------
--  Window Factory
--  Creates a fully independent damage meter window with its own frame tree,
--  bar pool, scroll state, source window, home screen, and refresh cycle.
--  Returns a window table W with all state and a Destroy method.
-------------------------------------------------------------------------------
local UpdateSATimerText  -- forward declaration (defined in standalone timer section)

local function CreateDMWindow(winIdx)
    local wdb = WinDB(winIdx)
    local W = {}
    W.idx = winIdx
    W.curDMType    = wdb.curDMType or Enum.DamageMeterType.DamageDone
    W.curSession   = wdb.curSession or Enum.DamageMeterSessionType.Current
    W.curSessionID = nil
    W.visibleCount = 0
    W.isHovered    = false
    W.resizing     = false
    W.windowLocked = wdb.locked or false
    W.snapDisabled = false
    W.sourceOpen   = false
    W.sourceGUID   = nil
    W.sourceCreatureID = nil
    W.sourceClass  = nil
    W.cachedSources = nil
    W.stickyAtTop  = false
    W.stickyGuard  = false
    W.refreshElapsed = 0
    W.hdrIcons     = {}
    local cfg = DB()
    local PP = EUI and EUI.PP

    -- Forward declarations (defined later in this function)
    local RefreshHome
    local RefreshUI
    local homeFrame

    ---------------------------------------------------------------------------
    --  Row factory
    ---------------------------------------------------------------------------
    local function MakeRow(parent)
        local bar = {}
        bar.row = CreateFrame("Button", nil, parent)
        bar.row:SetHeight(18); bar.row:EnableMouse(true); bar.row:RegisterForClicks("AnyUp")
        bar.fill = CreateFrame("StatusBar", nil, bar.row)
        bar.fill:SetMinMaxValues(0, 1); bar.fill:SetValue(0); bar.fill:SetStatusBarTexture(BAR_TEX)
        bar.classIcon = bar.fill:CreateTexture(nil, "OVERLAY")
        bar.classIcon:SetSize(18, 18); bar.classIcon:SetPoint("LEFT", bar.row, "LEFT", 0, 0)
        bar.classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92); bar.classIcon:Hide()
        -- Per-bar border (lazy-created, only when borderSize > 0)
        function bar.ApplyBorder()
            local c = DB()
            local sz = c.borderSize or 0
            if sz <= 0 then
                if bar._borderFrame then bar._borderFrame:Hide() end
                return
            end
            if not bar._borderFrame then
                bar._borderFrame = CreateFrame("Frame", nil, bar.row)
                bar._borderFrame:SetAllPoints(bar.row)
                bar._borderFrame:SetFrameLevel(bar.row:GetFrameLevel() + 3)
            end
            bar._borderFrame:Show()
            local tex = c.borderTexture or "solid"
            EllesmereUI.ApplyBorderStyle(bar._borderFrame, sz,
                c.borderR or 0, c.borderG or 0, c.borderB or 0, c.borderA or 1,
                tex, c.borderTextureOffset, c.borderTextureOffsetY,
                c.borderTextureShiftX, c.borderTextureShiftY, "damagemeters", sz)
        end
        bar.ApplyBorder()
        local tf = CreateFrame("Frame", nil, bar.fill)
        tf:SetAllPoints(bar.fill); tf:SetFrameLevel(bar.fill:GetFrameLevel() + 2)
        bar.pos = tf:CreateFontString(nil, "OVERLAY"); bar.pos:SetPoint("LEFT", tf, "LEFT", 3, 0); SetDMFont(bar.pos, 11)
        bar.label = tf:CreateFontString(nil, "OVERLAY"); bar.label:SetPoint("LEFT", bar.pos, "RIGHT", 2, 0); bar.label:SetPoint("RIGHT", tf, "RIGHT", -70, 0); bar.label:SetJustifyH("LEFT"); SetDMFont(bar.label, 11)
        bar.label:SetWordWrap(false)
        bar.amount = tf:CreateFontString(nil, "OVERLAY"); bar.amount:SetPoint("RIGHT", tf, "RIGHT", -3, 0); bar.amount:SetJustifyH("RIGHT"); SetDMFont(bar.amount, 11)
        bar.row:SetScript("OnClick", function(_, button)
            if button == "LeftButton" then
                if InCombatLockdown() then return end
                if bar._src and (bar._srcGUID or bar._src.sourceCreatureID) then
                    -- Deaths without recap data: block click
                    if W.curDMType == Enum.DamageMeterType.Deaths then
                        local rid = bar._src.deathRecapID
                        if not rid or (issecretvalue and issecretvalue(rid)) or rid <= 0 then return end
                        if C_DeathRecap and C_DeathRecap.GetRecapEvents then
                            local ok, raw = pcall(C_DeathRecap.GetRecapEvents, rid)
                            if not ok or not raw or #raw == 0 then return end
                        end
                    end
                    W.OpenSource(bar._srcGUID, bar._src.sourceCreatureID, StripRealm(bar._src.name), bar._class, bar._src.deathRecapID, bar._src.name)
                end
            elseif button == "RightButton" then
                W.ShowHome()
            end
        end)
        bar._hl = tf:CreateTexture(nil, "BACKGROUND")
        bar._hl:SetAllPoints(bar.row); bar._hl:SetColorTexture(1, 1, 1, 0.08); bar._hl:Hide()
        bar.row:SetScript("OnEnter", function()
            bar._hl:Show()
            -- Deaths without recap: show "no recap available" tooltip
            if W.curDMType == Enum.DamageMeterType.Deaths and bar._src then
                local rid = bar._src.deathRecapID
                local hasRecap = rid and not (issecretvalue and issecretvalue(rid)) and rid > 0
                if hasRecap and C_DeathRecap and C_DeathRecap.GetRecapEvents then
                    local ok, raw = pcall(C_DeathRecap.GetRecapEvents, rid)
                    if not ok or not raw or #raw == 0 then hasRecap = false end
                end
                if not hasRecap then
                    EnsureTooltipFrame()
                    local playerName = StripRealm(bar._src.name) or "Unknown"
                    _ttFrame._hdrText:SetText(playerName .. "'s Death Recap")
                    local cfg2 = DB()
                    local hc = cfg2.hdrBgColor; local hR = hc and hc.r or 0x1B/255; local hG = hc and hc.g or 0x1B/255; local hB = hc and hc.b or 0x1B/255
                    _ttFrame._hdrBg:SetColorTexture(hR, hG, hB, cfg2.hdrBgAlpha or 1)
                    local tR, tG, tB
                    if cfg2.hdrTextUseAccent ~= false then tR, tG, tB = GetAccentRGB()
                    else local tc = cfg2.hdrTextColor; tR = tc and tc.r or 1; tG = tc and tc.g or 1; tB = tc and tc.b or 1 end
                    _ttFrame._hdrText:SetTextColor(tR, tG, tB, 1)
                    for bi = 1, #_ttBars do if _ttBars[bi] then _ttBars[bi].row:Hide() end end
                    _ttFrame._combatMsg:SetText("No death recap available")
                    _ttFrame._combatMsg:Show()
                    _ttFrame:SetSize(TT_WIDTH, TT_HDR_H + 40)
                    _ttFrame:ClearAllPoints()
                    if cfg2 and cfg2.breakdownAnchorPoint == "center" then
                        _ttFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                    else
                        _ttFrame:SetPoint("BOTTOMRIGHT", bar.row, "TOPRIGHT", 0, 0)
                    end
                    _ttFrame:Show()
                    return
                end
            end
            if InCombatLockdown() then
                EnsureTooltipFrame()
                -- Show header with player name + type
                local playerName = StripRealm(bar._src and bar._src.name) or "Unknown"
                local typeName = DM_TYPE_NAMES[W.curDMType] or "Damage Done"
                _ttFrame._hdrText:SetText(playerName .. "'s " .. typeName .. " Breakdown")
                local cfg2 = DB()
                local hc = cfg2.hdrBgColor; local hR = hc and hc.r or 0x1B/255; local hG = hc and hc.g or 0x1B/255; local hB = hc and hc.b or 0x1B/255
                _ttFrame._hdrBg:SetColorTexture(hR, hG, hB, cfg2.hdrBgAlpha or 1)
                local tR, tG, tB
                if cfg2.hdrTextUseAccent ~= false then tR, tG, tB = GetAccentRGB()
                else local tc = cfg2.hdrTextColor; tR = tc and tc.r or 1; tG = tc and tc.g or 1; tB = tc and tc.b or 1 end
                _ttFrame._hdrText:SetTextColor(tR, tG, tB, 1)
                -- Hide bars, show combat message
                for bi = 1, #_ttBars do if _ttBars[bi] then _ttBars[bi].row:Hide() end end
                _ttFrame._combatMsg:SetText("Detailed information is\nsecret while in combat")
                _ttFrame._combatMsg:Show()
                _ttFrame:SetSize(TT_WIDTH, TT_HDR_H + 40)
                _ttFrame:ClearAllPoints()
                if cfg2 and cfg2.breakdownAnchorPoint == "center" then
                    _ttFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                else
                    _ttFrame:SetPoint("BOTTOMRIGHT", bar.row, "TOPRIGHT", 0, 0)
                end
                _ttFrame:Show()
                return
            end
            _activeRow = bar; bar._win = W; _hoverPollFrame:Show()
        end)
        bar.row:SetScript("OnLeave", function()
            bar._hl:Hide()
            _activeRow = nil; _hoverPollFrame:Hide(); HideBarTooltip()
        end)
        bar._src = nil; bar._srcGUID = nil; bar._class = nil; bar._win = W
        bar.row:Hide()
        return bar
    end

    local function MakeSpellRow(parent)
        local bar = {}
        bar.row = CreateFrame("Button", nil, parent); bar.row:SetHeight(18); bar.row:EnableMouse(true); bar.row:RegisterForClicks("AnyUp")
        bar.fill = CreateFrame("StatusBar", nil, bar.row); bar.fill:SetMinMaxValues(0, 1); bar.fill:SetValue(0); bar.fill:SetStatusBarTexture(BAR_TEX)
        bar.classIcon = bar.fill:CreateTexture(nil, "OVERLAY"); bar.classIcon:SetSize(18, 18); bar.classIcon:SetPoint("LEFT", bar.row, "LEFT", 0, 0); bar.classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92); bar.classIcon:Hide()
        local tf = CreateFrame("Frame", nil, bar.fill); tf:SetAllPoints(bar.fill); tf:SetFrameLevel(bar.fill:GetFrameLevel() + 2)
        bar.label = tf:CreateFontString(nil, "OVERLAY"); bar.label:SetPoint("LEFT", tf, "LEFT", 3, 0); bar.label:SetPoint("RIGHT", tf, "RIGHT", -70, 0); bar.label:SetJustifyH("LEFT"); SetDMFont(bar.label, 11)
        bar.label:SetWordWrap(false)
        bar.amount = tf:CreateFontString(nil, "OVERLAY"); bar.amount:SetPoint("RIGHT", tf, "RIGHT", -3, 0); bar.amount:SetJustifyH("RIGHT"); SetDMFont(bar.amount, 11)
        bar.row:SetScript("OnClick", function() W.CloseSource() end)
        bar._spellID = nil; bar.row:Hide()
        return bar
    end

    ---------------------------------------------------------------------------
    --  Main container
    ---------------------------------------------------------------------------
    local frame = CreateFrame("Frame", "EllesmereUIDMFrame" .. winIdx, UIParent)
    frame:SetSize(wdb.width or 300, wdb.height or 200)
    frame:SetClampedToScreen(true); frame:SetMovable(true)
    W.frame = frame

    if wdb.position and wdb.position.x and wdb.position.y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", wdb.position.x, wdb.position.y)
    else
        local uiW, uiH = UIParent:GetSize()
        local fw, fh = frame:GetSize()
        -- Default: 20px from bottom-right of screen
        local defX = uiW - fw - 20 + (winIdx - 1) * 20
        local defY = fh + 20 - (winIdx - 1) * 20
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", defX, defY)
    end

    frame._bg = frame:CreateTexture(nil, "BACKGROUND")
    frame._bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -GetHeaderH())
    frame._bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame._bg:SetColorTexture(cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgAlpha or 0.75)

    ---------------------------------------------------------------------------
    --  Header
    ---------------------------------------------------------------------------
    local header = CreateFrame("Frame", nil, frame)
    header:SetHeight(GetHeaderH()); header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetFrameLevel(frame:GetFrameLevel() + 5)
    W.header = header

    do local hc = cfg.hdrBgColor; local hR = hc and hc.r or 0x1B/255; local hG = hc and hc.g or 0x1B/255; local hB = hc and hc.b or 0x1B/255
    header._hdrBg = header:CreateTexture(nil, "BACKGROUND"); header._hdrBg:SetAllPoints(); header._hdrBg:SetColorTexture(hR, hG, hB, cfg.hdrBgAlpha or 1) end

    local hdrFS = cfg.hdrFontSize or 11
    local txOX, txOY = cfg.hdrTextOffX or 0, cfg.hdrTextOffY or 0
    W.titleText = header:CreateFontString(nil, "OVERLAY"); SetDMFont(W.titleText, hdrFS)
    W.titleText:SetPoint("LEFT", header, "LEFT", 6 + txOX, txOY)
    do
        local tR, tG, tB
        if cfg.hdrTextUseAccent ~= false then tR, tG, tB = GetAccentRGB()
        else local tc = cfg.hdrTextColor; tR = tc and tc.r or 1; tG = tc and tc.g or 1; tB = tc and tc.b or 1 end
        W.titleText:SetTextColor(tR, tG, tB, 1)
    end
    W.titleText:SetText("Damage Done")

    W.timerText = header:CreateFontString(nil, "OVERLAY"); SetDMFont(W.timerText, hdrFS)
    W.timerText:SetTextColor(1, 1, 1, 0.7); W.timerText:SetPoint("LEFT", W.titleText, "RIGHT", 4, 0); W.timerText:SetText("(0:00)")
    if wdb.hideTimer then W.timerText:Hide() end

    if EUI.RegAccent then
        EUI.RegAccent({ type = "callback", fn = function(r, g, b)
            local c = DB()
            -- Header text
            if c.hdrTextUseAccent ~= false then W.titleText:SetTextColor(r, g, b, 1) end
            -- Header button icons
            if c.iconColorUseAccent then
                for _, ic in ipairs(W.hdrIcons) do ic:SetVertexColor(r, g, b, ICON_ALPHA) end
            end
            -- Bars (accent fill color or accent bar color)
            W.Refresh()
            -- Home screen cards (accent icons + active indicator)
            if homeFrame and homeFrame:IsShown() then RefreshHome() end
        end })
    end

    ---------------------------------------------------------------------------
    --  Header buttons
    ---------------------------------------------------------------------------
    local btnSize = cfg.hdrIconSize or 22
    local btnPad = -2

    W.hdrIcons = {}
    local function GetIconColor()
        local c = DB()
        if c.iconColorUseAccent then return GetAccentRGB() end
        local ic = c.iconColor; return ic and ic.r or 1, ic and ic.g or 1, ic and ic.b or 1
    end

    local function MakeHeaderBtn(texFile, xOff, tooltip, onClick)
        local btn = CreateFrame("Button", nil, header)
        btn:SetSize(btnSize, btnSize); btn:SetPoint("RIGHT", header, "RIGHT", xOff, 0)
        btn:SetFrameLevel(header:GetFrameLevel() + 2)
        local ir, ig, ib = GetIconColor()
        local icon = btn:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints()
        icon:SetTexture(MEDIA .. texFile); icon:SetDesaturated(true); icon:SetVertexColor(ir, ig, ib, ICON_ALPHA)
        W.hdrIcons[#W.hdrIcons + 1] = icon
        btn:SetScript("OnEnter", function(self)
            local r, g, b = GetIconColor(); icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
            -- Suppress tooltip while this button's menu is open
            if _edmMenu and _edmMenu:IsShown() and _edmMenuAnchor == self then return end
            if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, tooltip) end
        end)
        btn:SetScript("OnLeave", function()
            local r, g, b = GetIconColor(); icon:SetVertexColor(r, g, b, ICON_ALPHA)
            if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
        end)
        btn:SetScript("OnClick", function(self)
            if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
            onClick(self)
        end)
        return btn
    end

    W.settingsBtn = MakeHeaderBtn("dm_settings.png", -(btnPad + 2), "Settings", function()
        ShowEDMMenu({
            { text = "Hide in Dungeons", isActive = wdb.hideInDungeon, onClick = function()
                wdb.hideInDungeon = not wdb.hideInDungeon
                for _, w in ipairs(_windows) do w.UpdateVisibility() end
            end },
            { text = "Hide in Raids", isActive = wdb.hideInRaid, onClick = function()
                wdb.hideInRaid = not wdb.hideInRaid
                for _, w in ipairs(_windows) do w.UpdateVisibility() end
            end },
            { text = "Hide out of Instances", isActive = wdb.hideOutOfInstance, onClick = function()
                wdb.hideOutOfInstance = not wdb.hideOutOfInstance
                for _, w in ipairs(_windows) do w.UpdateVisibility() end
            end },
            "---",
            { text = "Width", isInput = true,
              getValue = function() return math.floor(frame:GetWidth() + 0.5) end,
              setValue = function(v)
                  local left, top = frame:GetLeft(), frame:GetTop()
                  frame:SetSize(math.max(MIN_W, v), frame:GetHeight())
                  if left and top then frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top) end
                  wdb.width = math.floor(frame:GetWidth() + 0.5)
              end,
              min = MIN_W },
            { text = "Height", isInput = true,
              getValue = function() return math.floor(frame:GetHeight() + 0.5) end,
              setValue = function(v)
                  local left, top = frame:GetLeft(), frame:GetTop()
                  frame:SetSize(frame:GetWidth(), math.max(MIN_H, v))
                  if left and top then frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top) end
                  wdb.height = math.floor(frame:GetHeight() + 0.5)
              end,
              min = MIN_H },
            { text = W.snapDisabled and "Enable Snapping" or "Disable Snapping", onClick = function()
                W.snapDisabled = not W.snapDisabled
            end },
            { text = "Hide Timer", isActive = wdb.hideTimer, onClick = function()
                wdb.hideTimer = not wdb.hideTimer
                W.timerText:SetShown(not wdb.hideTimer)
            end },
            { text = "Auto Swap Current/Overall", isActive = wdb.autoSwapMythic, onClick = function()
                wdb.autoSwapMythic = not wdb.autoSwapMythic
            end },
            { text = "Settings", onClick = function()
                if EUI.ShowModule then EUI:ShowModule("EllesmereUIDamageMeters") end
            end },
        }, W.settingsBtn)
    end)

    W.segmentBtn = MakeHeaderBtn("dm_sheet.png", -(btnSize + btnPad * 2 + 2), "Select Segment", function()
        local items = {}
        -- Segments first (top of upward menu)
        if C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions then
            local sessions = C_DamageMeter.GetAvailableCombatSessions()
            if sessions and #sessions > 0 then
                local startIdx = math.max(1, #sessions - 19)
                for i = startIdx, #sessions do
                    local s = sessions[i]
                    local segName = s.name
                    if not segName or (issecretvalue and issecretvalue(segName)) or segName == "" then segName = "Combat" end
                    local segTime = FormatTimer(s.durationSeconds or 0)
                    items[#items + 1] = {
                        text = segName, timerText = segTime, compact = true,
                        isActive = (W.curSessionID == s.sessionID),
                        onClick = function() W.curSessionID = s.sessionID; W.CloseSource(); W.Refresh() end,
                    }
                end
            end
        end
        -- Divider + Current/Overall at bottom
        items[#items + 1] = "---"
        for _, sType in ipairs(SESSION_TYPES) do
            items[#items + 1] = {
                text = SESSION_TYPE_NAMES[sType] or "Unknown",
                isActive = (not W.curSessionID and sType == W.curSession),
                onClick = function() W.curSession = sType; wdb.curSession = sType; W.curSessionID = nil; W.CloseSource(); W.Refresh() end,
            }
        end
        ShowEDMMenu(items, W.segmentBtn)
    end)

    W.modeBtn = MakeHeaderBtn("dm_arrow.png", -(btnSize * 2 + btnPad * 3 + 2), "Switch Meter Type", function()
        local function sel(dmType) return function()
            W.curDMType = dmType; wdb.curDMType = dmType; W.CloseSource(); W.Refresh()
            W._modeIcon:SetTexture(DM_TYPE_ICONS[dmType] or DM_TYPE_ICONS[Enum.DamageMeterType.DamageDone])
        end end
        local function entry(label, dmType) return { text = label, onClick = sel(dmType), isActive = (dmType == W.curDMType) } end
        local cur = W.curDMType
        local dmActive = (cur == Enum.DamageMeterType.DamageDone or cur == Enum.DamageMeterType.DamageTaken or cur == Enum.DamageMeterType.AvoidableDamageTaken or cur == Enum.DamageMeterType.EnemyDamageTaken)
        local actActive = (cur == Enum.DamageMeterType.Interrupts or cur == Enum.DamageMeterType.Dispels or cur == Enum.DamageMeterType.Deaths)
        ShowEDMMenu({
            { text = "Damage", isActive = dmActive, children = {
                entry("Damage Done", Enum.DamageMeterType.DamageDone), entry("Damage Taken", Enum.DamageMeterType.DamageTaken),
                entry("Avoidable Damage Taken", Enum.DamageMeterType.AvoidableDamageTaken), entry("Enemy Damage Taken", Enum.DamageMeterType.EnemyDamageTaken),
            }},
            entry("Healing", Enum.DamageMeterType.HealingDone),
            { text = "Actions", isActive = actActive, children = {
                entry("Interrupts", Enum.DamageMeterType.Interrupts), entry("Dispels", Enum.DamageMeterType.Dispels), entry("Deaths", Enum.DamageMeterType.Deaths),
            }},
        }, W.modeBtn)
    end)
    -- Set mode icon to current DM type icon
    W._modeIcon = W.hdrIcons[#W.hdrIcons]
    W._modeIcon:SetTexture(DM_TYPE_ICONS[W.curDMType] or DM_TYPE_ICONS[Enum.DamageMeterType.DamageDone])

    -- + (new window) or x (close window) button, left of mode icon
    local winActionIcon = (winIdx == 1) and (MEDIA .. "dm_open.png") or (MEDIA .. "dm_close.png")
    local winActionTip = (winIdx == 1) and "New Window" or "Close Window"
    W.winActionBtn = MakeHeaderBtn("dm_settings.png", -(btnSize * 4 + btnPad * 5 + 2), winActionTip, function()
        if winIdx ~= 1 and W.windowLocked then return end
        if winIdx == 1 then
            if #_windows >= MAX_WINDOWS then return end
            local newIdx2 = #_windows + 1
            local srcW2 = frame:GetWidth(); local srcH2 = frame:GetHeight()
            local srcLeft2 = frame:GetLeft()
            local GAP = 10

            -- Find the highest top and lowest bottom among all existing windows
            local highestTop = frame:GetTop() or 0
            local lowestBot = frame:GetBottom() or 0
            for _, w in ipairs(_windows) do
                if w.frame then
                    local t = w.frame:GetTop()
                    local b = w.frame:GetBottom()
                    if t and t > highestTop then highestTop = t end
                    if b and b < lowestBot then lowestBot = b end
                end
            end

            -- Try above first: new window bottom = highest top + gap
            local screenTop2 = UIParent:GetTop() or 0
            local newTop2 = highestTop + srcH2 + GAP
            if newTop2 > screenTop2 then
                -- No room above: place below the lowest window
                newTop2 = lowestBot - GAP
            end

            local nwdb = WinDB(newIdx2)
            nwdb.width = math.floor(srcW2 + 0.5); nwdb.height = math.floor(srcH2 + 0.5)
            nwdb.position = { x = srcLeft2, y = newTop2 }
            local nw = CreateDMWindow(newIdx2)
            _windows[newIdx2] = nw
            -- Persist count
            local c = DB(); c.windowCount = newIdx2
            nw.ShowHome()
        else
            W.Destroy()
        end
    end)
    -- Override icon texture; close icon 2px larger for visibility
    do
        local iconTex = W.hdrIcons[#W.hdrIcons]
        iconTex:SetTexture(winActionIcon)
        if winIdx ~= 1 then W._closeIconTex = iconTex end
        if winIdx ~= 1 then
            iconTex:ClearAllPoints()
            iconTex:SetSize(btnSize + 2, btnSize + 2)
            iconTex:SetPoint("CENTER", W.winActionBtn, "CENTER", 0, 0)
        end
        -- Disable + button at max windows / close button when locked
        if winIdx == 1 then
            W.winActionBtn:HookScript("OnEnter", function(self)
                if #_windows >= MAX_WINDOWS then
                    iconTex:SetAlpha(0.2)
                    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
                    if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "You may only have " .. MAX_WINDOWS .. " windows active") end
                end
            end)
        else
            W.winActionBtn:HookScript("OnEnter", function(self)
                if W.windowLocked then
                    local ir, ig, ib = GetIconColor()
                    iconTex:SetVertexColor(ir, ig, ib, ICON_ALPHA * 0.5)
                    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
                    if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Unlock Window to Close") end
                end
            end)
            W.winActionBtn:HookScript("OnLeave", function()
                if W.windowLocked then
                    local ir, ig, ib = GetIconColor()
                    iconTex:SetVertexColor(ir, ig, ib, ICON_ALPHA * 0.5)
                end
            end)
        end
    end
    -- Apply initial close icon dimming if window starts locked
    if winIdx ~= 1 and W.windowLocked and W._closeIconTex then
        local ir, ig, ib = GetIconColor()
        W._closeIconTex:SetVertexColor(ir, ig, ib, ICON_ALPHA * 0.5)
    end

    -- Reset Data button, left of win action button
    W.resetBtn = MakeHeaderBtn("dm_reset.png", -(btnSize * 3 + btnPad * 4 + 2), "Reset Data", function()
        if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
            C_DamageMeter.ResetAllCombatSessions()
            _combatStartTime = 0; _combatEndTime = 0
            for _, w in ipairs(_windows) do w.Refresh() end
        end
    end)

    -- Ordered list of header buttons for live resize/reposition
    W.hdrBtns = { W.settingsBtn, W.segmentBtn, W.modeBtn, W.resetBtn, W.winActionBtn }

    -- Option: hide header icons until the title bar is hovered
    ApplyHeaderButtonsHoverVisibility(W, cfg)

    ---------------------------------------------------------------------------
    --  Snap helpers (X-axis alignment + width matching against other DM windows)
    ---------------------------------------------------------------------------
    local SNAP_THRESH = 6

    local function SnapDragPosition()
        local myLeft = frame:GetLeft()
        local myRight = frame:GetRight()
        if not myLeft or not myRight then return end
        local snappedX = myLeft
        local bestDist = SNAP_THRESH + 1
        for _, otherW in ipairs(_windows) do
            if otherW ~= W and otherW.frame and otherW.frame:IsShown() then
                local oLeft = otherW.frame:GetLeft()
                local oRight = otherW.frame:GetRight()
                if oLeft then
                    -- Snap my left to their left
                    local d = math.abs(myLeft - oLeft)
                    if d < bestDist then bestDist = d; snappedX = oLeft end
                    -- Snap my right to their right
                    if oRight then
                        local d2 = math.abs(myRight - oRight)
                        if d2 < bestDist then bestDist = d2; snappedX = oRight - (myRight - myLeft) end
                    end
                    -- Snap my left to their right
                    local d3 = math.abs(myLeft - oRight)
                    if d3 < bestDist then bestDist = d3; snappedX = oRight end
                    -- Snap my right to their left
                    local d4 = math.abs(myRight - oLeft)
                    if d4 < bestDist then bestDist = d4; snappedX = oLeft - (myRight - myLeft) end
                end
            end
        end
        if bestDist <= SNAP_THRESH then
            local top = frame:GetTop()
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", snappedX, top)
        end
    end

    -- Find the closest other DM window by 2D edge-to-edge distance
    -- Optional overrides for left/top allow drag to pass unsnapped target position
    local function FindClosestWindow(overrideL, overrideT)
        local myL = overrideL or frame:GetLeft() or 0
        local myW2 = frame:GetWidth() or 0
        local myH2 = frame:GetHeight() or 0
        local myT = overrideT or frame:GetTop() or 0
        local myR = myL + myW2
        local myB = myT - myH2
        local closest, closestDist = nil, math.huge
        for _, otherW in ipairs(_windows) do
            if otherW ~= W and otherW.frame and otherW.frame:IsShown() then
                local oL = otherW.frame:GetLeft() or 0
                local oR = otherW.frame:GetRight() or 0
                local oT = otherW.frame:GetTop() or 0
                local oB = otherW.frame:GetBottom() or 0
                local gapX = 0
                if myR < oL then gapX = oL - myR
                elseif myL > oR then gapX = myL - oR end
                local gapY = 0
                if myB > oT then gapY = myB - oT
                elseif myT < oB then gapY = oB - myT end
                local dist = math.sqrt(gapX * gapX + gapY * gapY)
                if dist < closestDist then closestDist = dist; closest = otherW end
            end
        end
        return closest
    end

    local function SnapResizeWidth(newW)
        local near = FindClosestWindow()
        if not near then return newW end
        local oW = near.frame:GetWidth()
        if oW and math.abs(newW - oW) <= SNAP_THRESH then return oW end
        return newW
    end

    local function SnapResizeHeight(newH)
        local near = FindClosestWindow()
        if not near then return newH end
        local oH = near.frame:GetHeight()
        if oH and math.abs(newH - oH) <= SNAP_THRESH then return oH end
        return newH
    end

    ---------------------------------------------------------------------------
    --  Header drag (manual, with real-time X-axis snapping)
    ---------------------------------------------------------------------------
    header:EnableMouse(true)
    local dragging = false
    local dragStartCX, dragStartCY, dragStartLeft, dragStartTop
    local dragFrame = CreateFrame("Frame"); dragFrame:Hide()
    dragFrame:SetScript("OnUpdate", function()
        if not dragging then return end
        -- Stop drag if mouse button was released (catches cases where OnMouseUp doesn't fire)
        if not IsMouseButtonDown("LeftButton") then
            dragging = false; dragFrame:Hide()
            local left, top = frame:GetLeft(), frame:GetTop()
            if left and top then
                if PP and PP.Snap then left = PP.Snap(left); top = PP.Snap(top) end
                wdb.position = { x = left, y = top }
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
        end
        local cx, cy = GetCursorPosition(); local es = frame:GetEffectiveScale()
        local newLeft = dragStartLeft + (cx/es - dragStartCX)
        local newTop = dragStartTop + (cy/es - dragStartCY)
        -- Snap to closest window only (use unsnapped target to prevent oscillation)
        local near = not W.snapDisabled and FindClosestWindow(newLeft, newTop)
        if near then
            local myW = frame:GetWidth()
            local myH = frame:GetHeight()
            local oLeft = near.frame:GetLeft()
            local oRight = near.frame:GetRight()
            local oTop = near.frame:GetTop()
            local oBot = near.frame:GetBottom()
            -- X axis
            if oLeft and oRight then
                local bestDist = SNAP_THRESH + 1
                local snappedLeft = newLeft
                local d1 = math.abs(newLeft - oLeft)
                if d1 < bestDist then bestDist = d1; snappedLeft = oLeft end
                local d2 = math.abs((newLeft + myW) - oRight)
                if d2 < bestDist then bestDist = d2; snappedLeft = oRight - myW end
                local d3 = math.abs(newLeft - oRight)
                if d3 < bestDist then bestDist = d3; snappedLeft = oRight end
                local d4 = math.abs((newLeft + myW) - oLeft)
                if d4 < bestDist then bestDist = d4; snappedLeft = oLeft - myW end
                if bestDist <= SNAP_THRESH then newLeft = snappedLeft end
            end
            -- Y axis
            if oTop and oBot then
                local bestDistY = SNAP_THRESH + 1
                local snappedTop = newTop
                local d1 = math.abs(newTop - oTop)
                if d1 < bestDistY then bestDistY = d1; snappedTop = oTop end
                local d2 = math.abs((newTop - myH) - oBot)
                if d2 < bestDistY then bestDistY = d2; snappedTop = oBot + myH end
                local d3 = math.abs(newTop - oBot)
                if d3 < bestDistY then bestDistY = d3; snappedTop = oBot end
                local d4 = math.abs((newTop - myH) - oTop)
                if d4 < bestDistY then bestDistY = d4; snappedTop = oTop + myH end
                if bestDistY <= SNAP_THRESH then newTop = snappedTop end
            end
        end
        -- Snap position to physical pixel grid
        if PP and PP.Snap then newLeft = PP.Snap(newLeft); newTop = PP.Snap(newTop) end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newLeft, newTop)
    end)

    header:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or W.windowLocked then return end
        if IsInProtectedInstance and IsInProtectedInstance() then return end
        local cx, cy = GetCursorPosition(); local es = frame:GetEffectiveScale()
        dragStartCX = cx/es; dragStartCY = cy/es
        dragStartLeft = frame:GetLeft(); dragStartTop = frame:GetTop()
        if not dragStartLeft or not dragStartTop then return end
        dragging = true; dragFrame:Show()
    end)
    header:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or not dragging then return end
        dragging = false; dragFrame:Hide()
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then
            if PP and PP.Snap then left = PP.Snap(left); top = PP.Snap(top) end
            wdb.position = { x = left, y = top }
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end)

    ---------------------------------------------------------------------------
    --  Right-click catcher (covers content area below header)
    --  Catches right-clicks on empty space to open home screen.
    --  Sits behind the viewport so bar clicks pass through normally.
    ---------------------------------------------------------------------------
    local rightClickCatcher = CreateFrame("Button", nil, frame)
    rightClickCatcher:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    rightClickCatcher:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    rightClickCatcher:SetFrameLevel(frame:GetFrameLevel() + 1)
    rightClickCatcher:RegisterForClicks("RightButtonUp")
    rightClickCatcher:EnableMouseWheel(false)
    if rightClickCatcher.SetMouseClickEnabled then rightClickCatcher:SetMouseClickEnabled(true) end
    rightClickCatcher:SetScript("OnClick", function() W.ShowHome() end)

    ---------------------------------------------------------------------------
    --  Viewport + scroll
    ---------------------------------------------------------------------------
    local viewport = CreateFrame("ScrollFrame", nil, frame)
    viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    viewport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    W.viewport = viewport

    local content = CreateFrame("Frame", nil, viewport); content:SetSize(1, 1)
    viewport:SetScrollChild(content)
    W.content = content

    viewport:SetScript("OnSizeChanged", function(self, w)
        if W.stickyGuard then return end
        if w and w > 0 then content:SetWidth(w) end
        W.UpdateSticky(nil, W.visibleCount)
    end)

    -- Mouse wheel scrolling (no visual scrollbar)
    local _scrollMax = 0
    local _scrollRefreshPending = false
    viewport:EnableMouseWheel(true)
    viewport:SetScript("OnMouseWheel", function(_, delta)
        local c = DB(); local step = (PhysicalPixels(c.barHeight or 18) + PhysicalPixels(c.barSpacing)) * 2
        local cur = viewport:GetVerticalScroll() or 0
        local newVal = math.max(0, math.min(_scrollMax, cur - delta * step))
        viewport:SetVerticalScroll(newVal)
        W.UpdateSticky(nil, W.visibleCount)
        -- Debounce: populate newly visible bars on next frame
        if not _scrollRefreshPending and W._lastSession then
            _scrollRefreshPending = true
            C_Timer.After(0, function()
                _scrollRefreshPending = false
                if W._lastSession then RefreshUI(W._lastSession) end
            end)
        end
    end)

    ---------------------------------------------------------------------------
    --  Bar pool
    ---------------------------------------------------------------------------
    W.rowPool = {}
    for i = 1, BAR_POOL_SIZE do W.rowPool[i] = MakeRow(content) end

    ---------------------------------------------------------------------------
    --  Sticky player bar
    ---------------------------------------------------------------------------
    W.stickyPlayer = MakeRow(frame)
    W.stickyPlayer.row:SetFrameLevel(frame:GetFrameLevel() + 8)
    W.stickyPlayer.row:Hide()

    local onePx = (PP and PP.mult) or 1
    W.stickySep = CreateFrame("Frame", nil, frame)
    W.stickySep:SetHeight(onePx); W.stickySep:SetFrameLevel(frame:GetFrameLevel() + 10)
    local sepTex = W.stickySep:CreateTexture(nil, "OVERLAY", nil, 6); sepTex:SetAllPoints(); sepTex:SetColorTexture(0, 0, 0, 1)
    W.stickySep:Hide()

    ---------------------------------------------------------------------------
    --  Source window
    ---------------------------------------------------------------------------
    W.sourceFrame = CreateFrame("Frame", nil, frame)
    W.sourceFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    W.sourceFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    W.sourceFrame:SetFrameLevel(frame:GetFrameLevel() + 20); W.sourceFrame:EnableMouse(true); W.sourceFrame:Hide()
    W.sourceFrame._bg = W.sourceFrame:CreateTexture(nil, "BACKGROUND"); W.sourceFrame._bg:SetAllPoints()
    W.sourceFrame._bg:SetColorTexture(cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgAlpha or 0.75)

    W.srcViewport = CreateFrame("ScrollFrame", nil, W.sourceFrame); W.srcViewport:SetAllPoints()
    W.srcContent = CreateFrame("Frame", nil, W.srcViewport); W.srcContent:SetSize(1, 1); W.srcViewport:SetScrollChild(W.srcContent)
    W.srcViewport:SetScript("OnSizeChanged", function(_, w) W.srcContent:SetWidth(w) end)

    -- Mouse wheel scrolling for spell breakdown
    local _srcScrollMax = 0
    W.srcViewport:EnableMouseWheel(true)
    W.srcViewport:SetScript("OnMouseWheel", function(_, delta)
        local c = DB(); local step = (PhysicalPixels(c.barHeight or 18) + PhysicalPixels(c.barSpacing)) * 2
        local cur = W.srcViewport:GetVerticalScroll() or 0
        W.srcViewport:SetVerticalScroll(math.max(0, math.min(_srcScrollMax, cur - delta * step)))
    end)

    W.sourceFrame:SetScript("OnMouseDown", function() W.CloseSource() end)

    W.spellPool = nil  -- lazy-created on first OpenSource
    local function EnsureSpellPool()
        if W.spellPool then return end
        W.spellPool = {}
        for i = 1, BAR_POOL_SIZE do W.spellPool[i] = MakeSpellRow(W.srcContent) end
    end

    ---------------------------------------------------------------------------
    --  Resize grip
    ---------------------------------------------------------------------------
    W.resizeGrip = CreateFrame("Button", nil, frame)
    W.resizeGrip:SetSize(18, 18); W.resizeGrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    W.resizeGrip:SetFrameStrata("HIGH"); W.resizeGrip:SetFrameLevel(frame:GetFrameLevel() + 15)
    local gripTex = W.resizeGrip:CreateTexture(nil, "ARTWORK"); gripTex:SetAllPoints()
    gripTex:SetTexture(RESIZE_ICON); gripTex:SetDesaturated(true); gripTex:SetVertexColor(1, 1, 1)
    W.resizeGrip:EnableMouse(true); W.resizeGrip:SetAlpha(0)
    W.resizeGrip:SetScript("OnEnter", function(self) if not W.windowLocked then self:SetAlpha(0.7) end end)
    W.resizeGrip:SetScript("OnLeave", function(self) self:SetAlpha((W.isHovered and not W.windowLocked) and 0.3 or 0) end)

    -- Lock icon (shows/hides with resize grip, click toggles lock state)
    W.lockBtn = CreateFrame("Button", nil, frame)
    W.lockBtn:SetSize(13, 17)
    W.lockBtn:SetFrameStrata("HIGH"); W.lockBtn:SetFrameLevel(frame:GetFrameLevel() + 16)
    W.lockBtn:EnableMouse(true); W.lockBtn:SetAlpha(0)
    local lockTex = W.lockBtn:CreateTexture(nil, "ARTWORK"); lockTex:SetAllPoints()
    lockTex:SetDesaturated(true); lockTex:SetVertexColor(1, 1, 1)

    local function UpdateLockIcon()
        if W.windowLocked then
            lockTex:SetTexture(MEDIA .. "dm_locked.png")
            W.lockBtn:ClearAllPoints()
            W.lockBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
        else
            lockTex:SetTexture(MEDIA .. "dm_unlocked.png")
            W.lockBtn:ClearAllPoints()
            W.lockBtn:SetPoint("RIGHT", W.resizeGrip, "LEFT", -2, 0)
        end
        -- Dim close icon when locked (non-window-1 only)
        if winIdx ~= 1 and W._closeIconTex then
            local ir, ig, ib = GetIconColor()
            W._closeIconTex:SetVertexColor(ir, ig, ib, W.windowLocked and (ICON_ALPHA * 0.5) or ICON_ALPHA)
        end
    end
    UpdateLockIcon()

    W.lockBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(0.7)
        if EUI.ShowWidgetTooltip then
            EUI.ShowWidgetTooltip(self, W.windowLocked and "Locked" or "Unlocked")
        end
    end)
    W.lockBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(W.isHovered and 0.3 or 0)
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)
    W.lockBtn:SetScript("OnClick", function()
        W.windowLocked = not W.windowLocked
        wdb.locked = W.windowLocked
        UpdateLockIcon()
        if W.windowLocked then
            W.resizeGrip:SetAlpha(0)
            W.lockBtn:SetAlpha(W.isHovered and 0.3 or 0)
        else
            local a = W.isHovered and 0.3 or 0
            W.resizeGrip:SetAlpha(a)
            W.lockBtn:SetAlpha(a)
        end
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
        if EUI.ShowWidgetTooltip then
            EUI.ShowWidgetTooltip(W.lockBtn, W.windowLocked and "Locked" or "Unlocked")
        end
    end)
    W._updateLockIcon = UpdateLockIcon

    local resizeStartX, resizeStartY, resizeStartW, resizeStartH
    local resizeAnchorLeft, resizeAnchorTop  -- pinned TOPLEFT during resize
    local resizeFrame = CreateFrame("Frame"); resizeFrame:Hide()
    local resizeAxis = nil  -- nil = free, "w" = width only, "h" = height only
    local resizeShiftWas = false
    resizeFrame:SetScript("OnUpdate", function()
        if not W.resizing then return end
        local cx, cy = GetCursorPosition(); local es = frame:GetEffectiveScale()
        local dx = cx/es - resizeStartX
        local dy = resizeStartY - cy/es
        local shiftDown = IsShiftKeyDown()
        local newW, newH
        if shiftDown then
            if not resizeShiftWas then
                resizeAxis = math.abs(dx) >= math.abs(dy) and "w" or "h"
            end
            if resizeAxis == "w" then
                newW = math.max(MIN_W, resizeStartW + dx); newH = math.max(MIN_H, resizeStartH)
            else
                newW = math.max(MIN_W, resizeStartW); newH = math.max(MIN_H, resizeStartH + dy)
            end
        else
            resizeAxis = nil
            newW = math.max(MIN_W, resizeStartW + dx); newH = math.max(MIN_H, resizeStartH + dy)
        end
        -- Snap width/height to other windows
        if not W.snapDisabled then
            newW = SnapResizeWidth(newW)
            newH = SnapResizeHeight(newH)
        end
        -- Cap size so frame can't extend past screen edges from pinned TOPLEFT
        local screenW = UIParent:GetRight() or 0
        local screenB = UIParent:GetBottom() or 0
        local maxW = screenW - resizeAnchorLeft
        local maxH = resizeAnchorTop - screenB
        if maxW > MIN_W then newW = math.min(newW, maxW) end
        if maxH > MIN_H then newH = math.min(newH, maxH) end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", resizeAnchorLeft, resizeAnchorTop)
        frame:SetSize(newW, newH)
        resizeShiftWas = shiftDown
    end)

    W.resizeGrip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or W.windowLocked then return end
        if IsInProtectedInstance and IsInProtectedInstance() then return end
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top) end
        resizeAnchorLeft = left; resizeAnchorTop = top
        local cx, cy = GetCursorPosition(); local es = frame:GetEffectiveScale()
        resizeStartX = cx/es; resizeStartY = cy/es; resizeStartW = frame:GetWidth(); resizeStartH = frame:GetHeight()
        W.resizing = true; resizeFrame:Show()
    end)
    W.resizeGrip:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or not W.resizing then return end
        W.resizing = false; resizeFrame:Hide()
        wdb.width = math.floor(frame:GetWidth() + 0.5); wdb.height = math.floor(frame:GetHeight() + 0.5)
        W.UpdateSticky(nil, W.visibleCount)
        -- Refresh home screen card widths one frame after resize
        if homeFrame and homeFrame:IsShown() then
            C_Timer.After(0, function() if RefreshHome then RefreshHome() end end)
        end
    end)

    ---------------------------------------------------------------------------
    --  Hover fade (scrollbar + resize grip)
    ---------------------------------------------------------------------------
    do
        local fadeSpeed = 1 / 0.12; local fadeAlpha = 0; local fadeTarget = 0
        local fadeFrame2 = CreateFrame("Frame"); fadeFrame2:Hide()
        fadeFrame2:SetScript("OnUpdate", function(self, dt)
            if fadeAlpha == fadeTarget then self:Hide(); return end
            local step = fadeSpeed * dt
            fadeAlpha = fadeTarget > fadeAlpha and math.min(fadeTarget, fadeAlpha + step) or math.max(fadeTarget, fadeAlpha - step)
            if W.resizeGrip and not W.windowLocked and not W.resizeGrip:IsMouseOver() then W.resizeGrip:SetAlpha(fadeAlpha * 0.3) end
            if W.lockBtn and not W.lockBtn:IsMouseOver() then W.lockBtn:SetAlpha(fadeAlpha * 0.3) end
        end)
        local function FadeIn() fadeTarget = 1; fadeFrame2:Show() end
        local function FadeOut() fadeTarget = 0; fadeFrame2:Show() end
        local wasOver = false
        local hoverTicker  -- forward ref
        local function HoverPoll()
            local over = frame:IsMouseOver() or (W.resizeGrip and W.resizeGrip:IsMouseOver()) or (W.lockBtn and W.lockBtn:IsMouseOver())
            if over and not wasOver then
                wasOver = true; W.isHovered = true
                FadeIn()
            elseif not over and wasOver then
                wasOver = false; W.isHovered = false
                FadeOut()
                -- Stop polling until next OnEnter
                if hoverTicker then hoverTicker:Cancel(); hoverTicker = nil end
            end
        end
        local function StartHoverPoll()
            if hoverTicker then return end
            hoverTicker = C_Timer.NewTicker(0.1, HoverPoll)
        end
        -- OnEnter on the main frame starts the poll
        frame:HookScript("OnEnter", StartHoverPoll)
        -- Also start from children that sit above the frame
        header:HookScript("OnEnter", StartHoverPoll)
        viewport:HookScript("OnEnter", StartHoverPoll)
        rightClickCatcher:HookScript("OnEnter", StartHoverPoll)
        W.resizeGrip:HookScript("OnEnter", StartHoverPoll)
        W.lockBtn:HookScript("OnEnter", StartHoverPoll)
        W._startHoverPoll = StartHoverPoll
        W._hoverTicker = { Cancel = function() if hoverTicker then hoverTicker:Cancel(); hoverTicker = nil end end }
        -- Hook bar rows so entering from the content area starts the poll
        for _, bar in ipairs(W.rowPool) do bar.row:HookScript("OnEnter", StartHoverPoll) end
        if W.stickyPlayer then W.stickyPlayer.row:HookScript("OnEnter", StartHoverPoll) end
    end

    ---------------------------------------------------------------------------
    --  Unlock mode overlay
    ---------------------------------------------------------------------------
    local unlockOverlay = CreateFrame("Button", nil, frame)
    unlockOverlay:SetAllPoints(frame); unlockOverlay:SetFrameStrata("DIALOG"); unlockOverlay:SetFrameLevel(999)
    unlockOverlay:SetClampedToScreen(true); unlockOverlay:SetMovable(true); unlockOverlay:EnableMouse(true)
    unlockOverlay:RegisterForDrag("LeftButton"); unlockOverlay:Hide()
    local ovBg = unlockOverlay:CreateTexture(nil, "BACKGROUND"); ovBg:SetAllPoints(); ovBg:SetColorTexture(0.075, 0.113, 0.141, 0.85)
    local ar, ag, ab = GetAccentRGB()
    local ovBrd = EUI.MakeBorder and EUI.MakeBorder(unlockOverlay, ar, ag, ab, 0.6)
    unlockOverlay:HookScript("OnEnter", function() if ovBrd then ovBrd:SetColor(1, 1, 1, 0.9) end end)
    unlockOverlay:HookScript("OnLeave", function() if ovBrd then ovBrd:SetColor(ar, ag, ab, 0.6) end end)
    local ovFont = EUI.EXPRESSWAY or (EUI.GetFontPath and EUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
    local labelFr = CreateFrame("Frame", nil, unlockOverlay); labelFr:SetAllPoints(); labelFr:SetFrameLevel(unlockOverlay:GetFrameLevel() + 3)
    local ovLabel = labelFr:CreateFontString(nil, "OVERLAY"); ovLabel:SetFont(ovFont, 10, "")
    ovLabel:SetShadowOffset(1, -1); ovLabel:SetShadowColor(0, 0, 0, 0.8); ovLabel:SetPoint("CENTER")
    ovLabel:SetText("Damage Meters"); ovLabel:SetTextColor(1, 1, 1, 0.9)

    -- Overlay absorbs clicks to block interaction with the window beneath.
    -- Dragging the overlay uses the same snap logic as the header drag.
    unlockOverlay:EnableMouse(true)
    unlockOverlay:RegisterForClicks("AnyUp")
    unlockOverlay:SetScript("OnClick", function() end)  -- absorb clicks
    unlockOverlay:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local cx, cy = GetCursorPosition(); local es = frame:GetEffectiveScale()
        dragStartCX = cx/es; dragStartCY = cy/es
        dragStartLeft = frame:GetLeft(); dragStartTop = frame:GetTop()
        if not dragStartLeft or not dragStartTop then return end
        dragging = true; dragFrame:Show()
    end)
    unlockOverlay:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or not dragging then return end
        dragging = false; dragFrame:Hide()
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then
            if PP and PP.Snap then left = PP.Snap(left); top = PP.Snap(top) end
            wdb.position = { x = left, y = top }
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end)

    local MOVER_DELAY, MOVER_FADE = 0.50, 0.75
    local fadeElapsed = 0
    unlockOverlay:SetAlpha(0)
    local unlockFadeFrame = CreateFrame("Frame")
    unlockFadeFrame:Hide()
    unlockFadeFrame:SetScript("OnUpdate", function(self, dt)
        fadeElapsed = fadeElapsed + dt
        local t = fadeElapsed - MOVER_DELAY
        local a = t > 0 and math.min(1, t / MOVER_FADE) or 0
        unlockOverlay:SetAlpha(a)
        if a >= 1 then self:Hide() end
    end)

    W._unlockOpen = function()
        fadeElapsed = 0; unlockOverlay:SetAlpha(0); unlockOverlay:Show()
        unlockFadeFrame:Show()
        -- Raise resize + lock above the overlay
        W.resizeGrip:SetFrameStrata("DIALOG"); W.resizeGrip:SetFrameLevel(1000)
        W.lockBtn:SetFrameStrata("DIALOG"); W.lockBtn:SetFrameLevel(1001)
    end
    W._unlockClose = function()
        unlockFadeFrame:Hide()
        unlockOverlay:Hide(); unlockOverlay:SetAlpha(0)
        -- Restore resize + lock to normal strata
        W.resizeGrip:SetFrameStrata("HIGH"); W.resizeGrip:SetFrameLevel(frame:GetFrameLevel() + 15)
        W.lockBtn:SetFrameStrata("HIGH"); W.lockBtn:SetFrameLevel(frame:GetFrameLevel() + 16)
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then
            frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            wdb.position = { x = left, y = top }
        end
    end

    ---------------------------------------------------------------------------
    --  Per-window functions
    ---------------------------------------------------------------------------
    local function ResetScrollAnchors()
        if not viewport or not header or not frame then return end
        W.stickyGuard = true
        viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
        viewport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        -- Clamp scroll
        if content then
            local viewH = frame:GetHeight() - GetHeaderH()
            if viewH < 1 then viewH = 1 end
            local totalH = content:GetHeight()
            local maxScr = math.max(0, totalH - viewH)
            _scrollMax = maxScr
            local cur = viewport:GetVerticalScroll()
            if cur > maxScr then viewport:SetVerticalScroll(maxScr) end
        end
        W.stickyGuard = false
    end

    local function RecalcViewport(dataCount)
        if not viewport or not content then return end
        local c = DB(); local barH = PhysicalPixels(c.barHeight or 18); local barSp = PhysicalPixels(c.barSpacing)
        local totalH = dataCount * (barH + barSp)
        content:SetHeight(math.max(10, totalH))
        local viewH = viewport:GetHeight(); if viewH < 1 then viewH = 1 end
        _scrollMax = math.max(0, totalH - viewH)
        local cur = viewport:GetVerticalScroll() or 0
        if cur > _scrollMax then viewport:SetVerticalScroll(_scrollMax) end
    end

    function W.UpdateSticky(sources, visibleCount)

        if W.stickyGuard then return end
        -- Don't show sticky while home screen or source window is open
        if (homeFrame and homeFrame:IsShown()) or W.sourceOpen then
            W.stickyPlayer.row:Hide(); W.stickySep:Hide(); return
        end
        if sources then W.cachedSources = sources end
        sources = W.cachedSources
        if not W.stickyPlayer or not W.stickySep then return end
        local c = DB()
        if c.showPinnedSelf == false or not _playerGUID or not sources or #sources == 0 then
            W.stickyPlayer.row:Hide(); W.stickySep:Hide(); ResetScrollAnchors(); W.stickyAtTop = false; return
        end
        local playerIdx
        for i, src in ipairs(sources) do if src.isLocalPlayer then playerIdx = i; break end end
        if not playerIdx then W.stickyPlayer.row:Hide(); W.stickySep:Hide(); ResetScrollAnchors(); W.stickyAtTop = false; return end
        local barH = PhysicalPixels(c.barHeight or 18); local barSp = PhysicalPixels(c.barSpacing); local stride = barH + barSp
        local scrollVal = viewport:GetVerticalScroll() or 0
        local fullViewH = frame:GetHeight() - GetHeaderH()
        if fullViewH < 1 then fullViewH = 1 end
        local pxMult = (PP and PP.mult) or 1
        local barTop = (playerIdx - 1) * stride
        local barBot = barTop + barH
        -- Unpin the instant the player bar is fully within the viewport (1px tolerance for float drift)
        if barTop >= scrollVal - 1 and barBot <= scrollVal + fullViewH + 1 then
            W.stickyPlayer.row:Hide(); W.stickySep:Hide(); ResetScrollAnchors(); W.stickyAtTop = false; return
        end
        local pinTop = (barTop < scrollVal); W.stickyAtTop = pinTop
        local pinnedH = barH + pxMult
        W.stickyPlayer.row:ClearAllPoints(); W.stickySep:ClearAllPoints(); W.stickySep:SetHeight(pxMult)
        if pinTop then
            W.stickyPlayer.row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0); W.stickyPlayer.row:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
            W.stickySep:SetPoint("TOPLEFT", W.stickyPlayer.row, "BOTTOMLEFT", 0, 0); W.stickySep:SetPoint("TOPRIGHT", W.stickyPlayer.row, "BOTTOMRIGHT", 0, 0)
        else
            W.stickyPlayer.row:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); W.stickyPlayer.row:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
            W.stickySep:SetPoint("BOTTOMLEFT", W.stickyPlayer.row, "TOPLEFT", 0, 0); W.stickySep:SetPoint("BOTTOMRIGHT", W.stickyPlayer.row, "TOPRIGHT", 0, 0)
        end
        W.stickyGuard = true
        if pinTop then
            viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -pinnedH); viewport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        else
            viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0); viewport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, pinnedH)
        end
        -- Clamp scroll after viewport resize
        local newViewH = viewport:GetHeight()
        if newViewH and newViewH > 0 then
            local totalH = (#sources) * stride
            local maxScr = math.max(0, totalH - newViewH)
            _scrollMax = maxScr
            local cur = viewport:GetVerticalScroll()
            if cur > maxScr then viewport:SetVerticalScroll(maxScr) end
        end
        W.stickyGuard = false
        -- Fill sticky bar (cached -- only SetValue/SetText per tick)
        local isDeaths = (W.curDMType == Enum.DamageMeterType.Deaths)
        local isCount = (W.curDMType == Enum.DamageMeterType.Interrupts or W.curDMType == Enum.DamageMeterType.Dispels)
        local src = sources[playerIdx]; local maxAmt = isDeaths and 1 or (sources[1] and sources[1].totalAmount or 1)
        local bar = W.stickyPlayer
        local leftFS = c.leftFontSize or c.fontSize or 11; local rightFS = c.rightFontSize or c.fontSize or 11
        local showIcon = (c.iconStyle or "spec") ~= "none"; local showClassColor = c.showClassColor ~= false
        local texPath, texKey = GetBarTexturePath()
        -- Layout cache: only rebuild on settings change
        local stickyCacheKey = leftFS .. "|" .. rightFS .. "|" .. texPath .. "|" .. tostring(showIcon) .. "|" .. tostring(showClassColor) .. "|" .. barH
        if stickyCacheKey ~= W._stickyCacheKey then
            W._stickyCacheKey = stickyCacheKey
            bar.row:SetHeight(barH)
            bar.fill:ClearAllPoints(); bar.fill:SetHeight(barH)
            ApplyBarTexture(bar.fill, texPath, texKey)
            bar.fill:SetAlpha(c.barFillAlpha or 1)
            SetDMFont(bar.pos, leftFS); SetDMFont(bar.label, leftFS); SetDMFont(bar.amount, rightFS)
            bar.label:SetWidth(math.max(20, (frame:GetWidth() or 200) * 0.75))
            W._stickyClassCache = nil  -- force icon/color rebuild
        end
        bar.row:Show()
        -- Icon + color: only when class changes
        local classFile = src.classFilename
        if classFile ~= W._stickyClassCache then
            W._stickyClassCache = classFile
            local iconOffset = showIcon and ResolveIcon(src, bar.classIcon, barH) or 0
            if not showIcon then bar.classIcon:Hide() end
            bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", iconOffset, 0)
            bar.fill:SetPoint("TOPRIGHT", bar.row, "TOPRIGHT", 0, 0)
            if showClassColor then
                local cc = classFile and RAID_CLASS_COLORS[classFile]
                if cc then bar.fill:SetStatusBarColor(cc.r, cc.g, cc.b)
                elseif W.curDMType == Enum.DamageMeterType.EnemyDamageTaken then bar.fill:SetStatusBarColor(0xDD/255, 0x31/255, 0x31/255)
                else bar.fill:SetStatusBarColor(0.5, 0.5, 0.5) end
            else
                if c.barColorUseAccent ~= false then local ar2, ag2, ab2 = GetAccentRGB(); bar.fill:SetStatusBarColor(ar2, ag2, ab2)
                else local bc = c.barColor; bar.fill:SetStatusBarColor(bc and bc.r or 0.35, bc and bc.g or 0.55, bc and bc.b or 0.8) end
            end
        end
        -- Per-tick: value + text only
        if isDeaths then
            bar.fill:SetMinMaxValues(0, 1); bar.fill:SetValue(1)
        else
            bar.fill:SetMinMaxValues(0, maxAmt); bar.fill:SetValue(src.totalAmount or 0)
        end
        -- Rank: only when position changes
        local hideNums = c.hideNumbers
        if hideNums then
            bar.pos:SetText("")
        elseif playerIdx ~= W._stickyRankCache then
            W._stickyRankCache = playerIdx
            bar.pos:SetText(RANK_STRINGS[playerIdx] or (playerIdx .. "."))
        end
        -- Name: only when source name changes (guard secret values)
        local srcName = src.name
        if issecretvalue and issecretvalue(srcName) then
            bar.label:SetText(StripRealm(srcName) or "You")
            W._stickyNameCache = nil
        elseif srcName ~= W._stickyNameCache then
            W._stickyNameCache = srcName
            bar.label:SetText(StripRealm(srcName) or "You")
        end
        if isDeaths then
            local isOverall = (not W.curSessionID and W.curSession == Enum.DamageMeterSessionType.Overall)
            bar.amount:SetText(isOverall and "" or FormatTimer(src.deathTimeSeconds))
        elseif isCount then
            bar.amount:SetText(AbbrevNumber(src.totalAmount))
        else
            bar.amount:SetText(FormatBarValue(src.totalAmount, src.amountPerSecond, c.numberFormat or 2))
        end
        bar._src = src; bar._srcGUID = src.sourceGUID; bar._class = classFile
        W.stickySep:Show()

    end

    -- (PEAK_BUDGET is at file scope)

    RefreshUI = function(session)

        if not frame then return end
        W._lastSession = session  -- cache for scroll-triggered refresh

        -- Populate rows
        local count = 0
        if session and session.combatSources then

            local sources = session.combatSources
            local c = DB(); local barH = PhysicalPixels(c.barHeight or 18); local barSp = PhysicalPixels(c.barSpacing); local stride = barH + barSp
            local leftFS = c.leftFontSize or c.fontSize or 11; local rightFS = c.rightFontSize or c.fontSize or 11
            local fontSize = leftFS -- compat for cacheKey
            local showIcon = (c.iconStyle or "spec") ~= "none"
            local showClassColor = c.showClassColor ~= false; local texPath, texKey = GetBarTexturePath()
            local rowWidth = viewport:GetWidth() or 200
            local labelMaxW = math.max(20, rowWidth * 0.75)
            local isDeaths = (W.curDMType == Enum.DamageMeterType.Deaths)
            local isCount = (W.curDMType == Enum.DamageMeterType.Interrupts or W.curDMType == Enum.DamageMeterType.Dispels)
            -- Deaths: reverse to chronological (API returns most recent first)
            -- Filter out feign deaths (deathRecapID <= 0 = no valid recap)
            if isDeaths then
                local rev = {}
                for ri = #sources, 1, -1 do
                    local s = sources[ri]
                    local rid = s.deathRecapID
                    if not (issecretvalue and issecretvalue(rid)) and rid and rid > 0 then
                        rev[#rev + 1] = s
                    end
                end
                sources = rev
            end
            W._barSources = sources  -- share with sticky (may be reversed for Deaths)
            local maxAmt = isDeaths and 1 or (sources[1] and sources[1].totalAmount or 1)
            count = math.min(#sources, BAR_POOL_SIZE)
            -- Cache key: detects settings changes that require full bar rebuild
            local iconStyle = c.iconStyle or "spec"
            local cacheKey = leftFS .. "|" .. rightFS .. "|" .. texPath .. "|" .. iconStyle .. "|" .. tostring(showClassColor) .. "|" .. tostring(c.barColorUseAccent) .. "|" .. barH .. "|" .. barSp .. "|" .. tostring(c.hideNumbers) .. "|" .. tostring(c.leftTextUseClassColor) .. "|" .. tostring(c.rightTextUseClassColor) .. "|" .. tostring(c.barFillAlpha)
            local fullRebuild = (cacheKey ~= W._barCacheKey)
            if fullRebuild then W._barCacheKey = cacheKey end

            local numFmt = c.numberFormat or 2
            local isSecret = issecretvalue and true or false

            -- Visible range calculation
            local scrollOff = viewport:GetVerticalScroll() or 0
            local viewH = viewport:GetHeight() or 200
            local visFirst = math.floor(scrollOff / stride) + 1
            local visLast = math.min(count, math.ceil((scrollOff + viewH) / stride))

            for i = 1, BAR_POOL_SIZE do
                local bar = W.rowPool[i]
                if i <= count then
                    local src = sources[i]
                    if not bar.row:IsShown() then bar.row:Show() end

                    -- Layout + appearance: only on settings change or bar reuse
                    if fullRebuild or bar._cachedSlot ~= i then
                        bar._cachedSlot = i
                        bar.row:ClearAllPoints()
                        local yOff = -((i-1) * stride)
                        bar.row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
                        bar.row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
                        bar.row:SetHeight(barH)
                        bar.fill:ClearAllPoints(); bar.fill:SetHeight(barH)
                        ApplyBarTexture(bar.fill, texPath, texKey)
                        bar.fill:SetAlpha(c.barFillAlpha or 1)
                        SetDMFont(bar.pos, leftFS); SetDMFont(bar.label, leftFS); SetDMFont(bar.amount, rightFS)
                        bar.label:SetWidth(labelMaxW)
                        if c.hideNumbers then
                            bar.pos:SetText("")
                        else
                            bar.pos:SetText(RANK_STRINGS[i] or (i .. "."))
                        end
                        -- Invalidate icon + color caches so they rebuild
                        bar._cachedClass = nil; bar._cachedColorClass = nil
                    end

                    -- Per-tick content: only for visible bars
                    if i >= visFirst and i <= visLast then
                        -- Icon: only when class changes
                        local classFile = src.classFilename
                        if classFile ~= bar._cachedClass then
                            bar._cachedClass = classFile
                            local iconOffset = showIcon and ResolveIcon(src, bar.classIcon, barH) or 0
                            if not showIcon then bar.classIcon:Hide() end
                            bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", iconOffset, 0)
                            bar.fill:SetPoint("TOPRIGHT", bar.row, "TOPRIGHT", 0, 0)
                            bar._cachedColorClass = nil
                        end

                        -- Fill value
                        if isDeaths then
                            bar.fill:SetMinMaxValues(0, 1)
                            bar.fill:SetValue(1)
                        else
                            bar.fill:SetMinMaxValues(0, maxAmt)
                            bar.fill:SetValue(src.totalAmount or 0)
                        end

                        -- Color
                        if showClassColor then
                            if classFile ~= bar._cachedColorClass then
                                bar._cachedColorClass = classFile
                                local cc = classFile and RAID_CLASS_COLORS[classFile]
                                if cc then bar.fill:SetStatusBarColor(cc.r, cc.g, cc.b)
                                elseif W.curDMType == Enum.DamageMeterType.EnemyDamageTaken then bar.fill:SetStatusBarColor(0xDD/255, 0x31/255, 0x31/255)
                                else bar.fill:SetStatusBarColor(0.5, 0.5, 0.5) end
                            end
                        elseif fullRebuild or not bar._cachedColorClass then
                            bar._cachedColorClass = false
                            if c.barColorUseAccent ~= false then local ar2, ag2, ab2 = GetAccentRGB(); bar.fill:SetStatusBarColor(ar2, ag2, ab2)
                            else local bc = c.barColor; bar.fill:SetStatusBarColor(bc and bc.r or 0.35, bc and bc.g or 0.55, bc and bc.b or 0.8) end
                        end

                        -- Left text color (pos + label)
                        if c.leftTextUseClassColor then
                            local cc = classFile and RAID_CLASS_COLORS[classFile]
                            local lr, lg, lb = cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1
                            bar.label:SetTextColor(lr, lg, lb)
                            bar.pos:SetTextColor(lr, lg, lb)
                        elseif fullRebuild then
                            local tc = c.leftTextColor
                            local lr, lg, lb = tc and tc.r or 1, tc and tc.g or 1, tc and tc.b or 1
                            bar.label:SetTextColor(lr, lg, lb)
                            bar.pos:SetTextColor(lr, lg, lb)
                        end
                        -- Right text color (amount)
                        if c.rightTextUseClassColor then
                            local cc = classFile and RAID_CLASS_COLORS[classFile]
                            local rr, rg, rb = cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1
                            bar.amount:SetTextColor(rr, rg, rb)
                        elseif fullRebuild then
                            local tc = c.rightTextColor
                            local rr, rg, rb = tc and tc.r or 1, tc and tc.g or 1, tc and tc.b or 1
                            bar.amount:SetTextColor(rr, rg, rb)
                        end

                        -- Name
                        local srcName = src.name
                        if isSecret and issecretvalue(srcName) then
                            bar.label:SetText(StripRealm(srcName))
                            bar._cachedSrcName = nil
                        elseif srcName ~= bar._cachedSrcName then
                            bar._cachedSrcName = srcName
                            bar._cachedDisplayName = StripRealm(srcName)
                            bar.label:SetText(bar._cachedDisplayName)
                        end

                        -- Amount text (guard secret values -- can't compare)
                        local fmtVal
                        if isDeaths then
                            local isOverall = (not W.curSessionID and W.curSession == Enum.DamageMeterSessionType.Overall)
                            fmtVal = isOverall and "" or FormatTimer(src.deathTimeSeconds)
                        elseif isCount then
                            fmtVal = AbbrevNumber(src.totalAmount)
                        else
                            fmtVal = FormatBarValue(src.totalAmount, src.amountPerSecond, numFmt)
                        end
                        if isSecret and issecretvalue(fmtVal) then
                            bar.amount:SetText(fmtVal)
                            bar._cachedAmtText = nil
                        elseif fmtVal ~= bar._cachedAmtText then
                            bar._cachedAmtText = fmtVal
                            bar.amount:SetText(fmtVal)
                        end
                        bar._src = src; bar._srcGUID = src.sourceGUID; bar._class = classFile
                    end
                else
                    if bar.row:IsShown() then bar.row:Hide() end
                    bar._src = nil; bar._srcGUID = nil; bar._class = nil
                    bar._cachedSlot = nil; bar._cachedClass = nil; bar._cachedColorClass = nil
                    bar._cachedSrcName = nil; bar._cachedDisplayName = nil; bar._cachedAmtText = nil
                end
            end

        else
            for i = 1, BAR_POOL_SIZE do W.rowPool[i].row:Hide() end
        end
        W.visibleCount = count

        W.UpdateSticky(W._barSources, count)



        RecalcViewport(count)

        local dur
        if W.curSessionID then
            -- Historical session: use API duration
            if C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions then
                local sess = C_DamageMeter.GetAvailableCombatSessions()
                if sess then for _, s in ipairs(sess) do if s.sessionID == W.curSessionID then dur = s.durationSeconds; break end end end
            end
        else
            -- Current/Overall: use our own tracked timer during/after combat (immune to API drift)
            local elapsed = GetCombatElapsed()
            if elapsed > 0 then
                dur = elapsed
            else
                -- No combat this session (e.g. after reload): fall back to API
                dur = C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds and C_DamageMeter.GetSessionDurationSeconds(W.curSession)
            end
        end
        local isOverall = (not W.curSessionID and W.curSession == Enum.DamageMeterSessionType.Overall)
        if not isOverall and dur and type(dur) == "number" and dur > 0 then
            W.timerText:SetText("(" .. FormatTimer(dur) .. ")")
        else
            W.timerText:SetText("")
        end
        local titlePrefix = isOverall and "Overall " or ""
        W.titleText:SetText(titlePrefix .. (DM_TYPE_NAMES[W.curDMType] or "Damage Done"))
        if winIdx == 1 then UpdateSATimerText() end

        if W.sourceOpen then
            W.RefreshBreakdown()
        end

    end

    function W.Refresh()
        if not frame then return end

        local apiStart = debugprofilestop()
        local session
        if W.curSessionID and C_DamageMeter and C_DamageMeter.GetCombatSessionFromID then
            local ok, s = pcall(C_DamageMeter.GetCombatSessionFromID, W.curSessionID, W.curDMType)
            if ok then session = s end
        elseif C_DamageMeter and C_DamageMeter.GetCombatSessionFromType then
            session = C_DamageMeter.GetCombatSessionFromType(W.curSession, W.curDMType)
        end
        local apiMs = debugprofilestop() - apiStart

        -- If API spiked, defer UI work to next frame so peaks don't stack
        if apiMs > PEAK_BUDGET then
            C_Timer.After(0, function() RefreshUI(session) end)
        else
            RefreshUI(session)
        end

    end

    function W.RefreshBreakdown()
        if not W.sourceOpen then return end
        if not W.sourceGUID and not W.sourceCreatureID then return end
        if not C_DamageMeter then return end
        EnsureSpellPool()

        local isDeathRecap = (W.curDMType == Enum.DamageMeterType.Deaths)

        -- Death recap: use C_DeathRecap API instead of combatSpells
        if isDeathRecap then
            local recapID = W.sourceRecapID
            if recapID and issecretvalue and issecretvalue(recapID) then recapID = nil end
            local events
            if recapID and recapID > 0 and C_DeathRecap and C_DeathRecap.GetRecapEvents then
                local ok, raw = pcall(C_DeathRecap.GetRecapEvents, recapID)
                if ok and raw and #raw > 0 then events = raw end
            end
            if not events then
                if W.spellPool then for i = 1, BAR_POOL_SIZE do W.spellPool[i].row:Hide() end end
                return
            end
            local maxHP = 1
            if C_DeathRecap.GetRecapMaxHealth then
                local ok2, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
                if ok2 and hp and type(hp) == "number" and hp > 0 then maxHP = hp end
            end
            -- Events come newest-first from API; reverse to oldest-first
            local reversed = {}
            for ri = #events, 1, -1 do reversed[#reversed + 1] = events[ri] end
            local c = DB(); local barH = PhysicalPixels(c.barHeight or 18)
            local barSp = PhysicalPixels(c.barSpacing); local stride = barH + barSp
            local leftFS = c.leftFontSize or c.fontSize or 11; local rightFS = c.rightFontSize or c.fontSize or 11
            local texPath, texKey = GetBarTexturePath()
            local deathTime = reversed[#reversed] and reversed[#reversed].timestamp or GetTime()
            local evCount = math.min(#reversed, BAR_POOL_SIZE)
            for i = 1, BAR_POOL_SIZE do
                local bar = W.spellPool[i]
                if i <= evCount then
                    local ev = reversed[i]; bar.row:Show()
                    bar.row:ClearAllPoints()
                    bar.row:SetPoint("TOPLEFT", W.srcContent, "TOPLEFT", 0, -((i-1) * stride))
                    bar.row:SetPoint("TOPRIGHT", W.srcContent, "TOPRIGHT", 0, -((i-1) * stride))
                    bar.row:SetHeight(barH)
                    -- Spell icon (135274 = melee attack fallback)
                    local iconOffset = 0
                    local spID = ev.spellId
                    local spIcon
                    if spID and spID > 0 then
                        spIcon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spID)
                    end
                    if not spIcon then spIcon = 135274 end
                    bar.classIcon:SetTexture(spIcon); bar.classIcon:SetTexCoord(0.065, 0.935, 0.065, 0.935); bar.classIcon:SetSize(barH, barH); bar.classIcon:Show(); iconOffset = barH
                    bar.fill:ClearAllPoints(); bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", iconOffset, 0)
                    bar.fill:SetPoint("TOPRIGHT", bar.row, "TOPRIGHT", 0, 0); bar.fill:SetHeight(barH)
                    -- Fill = HP% remaining at this event
                    local curHP = ev.currentHP or 0
                    local hpPct = maxHP > 0 and (curHP / maxHP) or 0
                    hpPct = math.min(1, math.max(0, hpPct))
                    ApplyBarTexture(bar.fill, texPath, texKey); bar.fill:SetMinMaxValues(0, 1); bar.fill:SetValue(hpPct)
                    local evType = ev.event or ""
                    local isHeal = (evType == "SPELL_HEAL" or evType == "SPELL_PERIODIC_HEAL")
                    local isFatal = (i == evCount and not isHeal)
                    if isHeal then
                        bar.fill:SetStatusBarColor(0.10, 0.50, 0.10)
                    else
                        bar.fill:SetStatusBarColor(0.60, 0.08, 0.08)
                    end
                    SetDMFont(bar.label, leftFS); SetDMFont(bar.amount, rightFS)
                    bar.label:SetTextColor(1, 1, 1); bar.amount:SetTextColor(1, 1, 1)
                    -- Label: time before death + spell name
                    local spellName = ev.spellName
                    if not spellName or (issecretvalue and issecretvalue(spellName)) or spellName == "" then
                        if isHeal then spellName = "Heal"
                        elseif evType == "SWING_DAMAGE" then spellName = "Melee"
                        else spellName = "Unknown" end
                    end
                    local td = deathTime - (ev.timestamp or deathTime)
                    local timeStr = format("-%.1fs", td)
                    if isHeal then
                        bar.label:SetText(timeStr .. " " .. spellName)
                    else
                        bar.label:SetText(timeStr .. " " .. spellName)
                    end
                    -- Amount: damage/heal + overkill on killing blow + HP%
                    local amt = ev.amount or 0
                    local amtStr
                    if isHeal then
                        amtStr = "+" .. AbbrevNumber(math.abs(amt))
                    else
                        amtStr = "-" .. AbbrevNumber(amt)
                    end
                    local overkill = ev.overkill
                    if isFatal and overkill and type(overkill) == "number" and overkill > 0 then
                        bar.amount:SetText(amtStr .. " |cffff3333(" .. AbbrevNumber(overkill) .. " overkill)|r (" .. format("%.0f%%", hpPct * 100) .. ")")
                    else
                        bar.amount:SetText(amtStr .. " (" .. format("%.0f%%", hpPct * 100) .. ")")
                    end
                    bar._spellID = spID
                else bar.row:Hide(); bar._spellID = nil end
            end
            local srcTotalH = evCount * stride
            W.srcContent:SetHeight(math.max(10, srcTotalH))
            local srcViewH = W.srcViewport:GetHeight(); if srcViewH < 1 then srcViewH = 1 end
            _srcScrollMax = math.max(0, srcTotalH - srcViewH)
            return
        end

        -- Enemy Damage Taken: show per-player breakdown instead of per-spell
        if W.curDMType == Enum.DamageMeterType.EnemyDamageTaken then
            local guid = W.sourceGUID
            local cid = W.sourceCreatureID
            local srcData
            if W.curSessionID and C_DamageMeter.GetCombatSessionSourceFromID then
                local ok, sd = pcall(C_DamageMeter.GetCombatSessionSourceFromID, W.curSessionID, W.curDMType, guid, cid)
                if ok then srcData = sd end
            elseif C_DamageMeter.GetCombatSessionSourceFromType then
                local ok, sd = pcall(C_DamageMeter.GetCombatSessionSourceFromType, W.curSession, W.curDMType, guid, cid)
                if ok then srcData = sd end
            end
            local players = AggregateEnemyPlayers(srcData)
            if not players then
                if W.spellPool then for i = 1, BAR_POOL_SIZE do W.spellPool[i].row:Hide() end end
                return
            end
            local c = DB(); local barH = PhysicalPixels(c.barHeight or 18)
            local barSp = PhysicalPixels(c.barSpacing); local stride = barH + barSp
            local leftFS = c.leftFontSize or c.fontSize or 11; local rightFS = c.rightFontSize or c.fontSize or 11
            local texPath, texKey = GetBarTexturePath()
            local maxAmt = players[1].total
            local pCount = math.min(#players, BAR_POOL_SIZE)
            for i = 1, BAR_POOL_SIZE do
                local bar = W.spellPool[i]
                if i <= pCount then
                    local p = players[i]; bar.row:Show()
                    bar.row:ClearAllPoints()
                    bar.row:SetPoint("TOPLEFT", W.srcContent, "TOPLEFT", 0, -((i-1) * stride))
                    bar.row:SetPoint("TOPRIGHT", W.srcContent, "TOPRIGHT", 0, -((i-1) * stride))
                    bar.row:SetHeight(barH)
                    -- Class/spec icon via ResolveIcon (consistent with main bars)
                    local fakeSrc = { classFilename = p.class, specIconID = p.specIcon }
                    local iconOffset = ResolveIcon(fakeSrc, bar.classIcon, barH)
                    bar.fill:ClearAllPoints(); bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", iconOffset, 0)
                    bar.fill:SetPoint("TOPRIGHT", bar.row, "TOPRIGHT", 0, 0); bar.fill:SetHeight(barH)
                    ApplyBarTexture(bar.fill, texPath, texKey); bar.fill:SetMinMaxValues(0, maxAmt); bar.fill:SetValue(p.total)
                    local cc = p.class and RAID_CLASS_COLORS[p.class]
                    if cc then bar.fill:SetStatusBarColor(cc.r, cc.g, cc.b)
                    else local ar2, ag2, ab2 = GetAccentRGB(); bar.fill:SetStatusBarColor(ar2, ag2, ab2) end
                    SetDMFont(bar.label, leftFS); SetDMFont(bar.amount, rightFS)
                    bar.label:SetTextColor(1, 1, 1); bar.amount:SetTextColor(1, 1, 1)
                    bar.label:SetText(StripRealm(p.name))
                    bar.amount:SetText(AbbrevNumber(p.total)); bar._spellID = nil
                else bar.row:Hide(); bar._spellID = nil end
            end
            local srcTotalH = pCount * stride
            W.srcContent:SetHeight(math.max(10, srcTotalH))
            local srcViewH = W.srcViewport:GetHeight(); if srcViewH < 1 then srcViewH = 1 end
            _srcScrollMax = math.max(0, srcTotalH - srcViewH)
            return
        end

        -- Standard spell breakdown (non-Deaths)
        -- Pass guid/cid straight through -- API accepts its own secret values
        local guid = W.sourceGUID
        local cid = W.sourceCreatureID
        local srcData
        if W.curSessionID and C_DamageMeter.GetCombatSessionSourceFromID then
            local ok, sd = pcall(C_DamageMeter.GetCombatSessionSourceFromID, W.curSessionID, W.curDMType, guid, cid)
            if ok then srcData = sd end
        elseif C_DamageMeter.GetCombatSessionSourceFromType then
            local ok, sd = pcall(C_DamageMeter.GetCombatSessionSourceFromType, W.curSession, W.curDMType, guid, cid)
            if ok then srcData = sd end
        end
        if not srcData or not srcData.combatSpells then
            if W.spellPool then for i = 1, BAR_POOL_SIZE do W.spellPool[i].row:Hide() end end
            return
        end
        local spells = srcData.combatSpells; local c = DB(); local barH = PhysicalPixels(c.barHeight or 18)
        local barSp = PhysicalPixels(c.barSpacing); local stride = barH + barSp; local leftFS = c.leftFontSize or c.fontSize or 11; local rightFS = c.rightFontSize or c.fontSize or 11; local texPath, texKey = GetBarTexturePath()
        local sorted = {}
        for _, spell in ipairs(spells) do local ok, amt = pcall(function() return spell.totalAmount end); sorted[#sorted + 1] = { spell = spell, amount = (ok and amt) or 0 } end
        -- API returns combatSpells pre-sorted; no table.sort needed
        local maxAmt = sorted[1] and sorted[1].amount or 1
        -- Sum totals for percentage (skip if amounts are secret)
        local totalDmg = 0
        local canPercent = maxAmt and (not issecretvalue or not issecretvalue(maxAmt)) and type(maxAmt) == "number"
        if canPercent then for _, e in ipairs(sorted) do totalDmg = totalDmg + e.amount end end
        local spCount = math.min(#sorted, BAR_POOL_SIZE)
        for i = 1, BAR_POOL_SIZE do
            local bar = W.spellPool[i]
            if i <= spCount then
                local entry = sorted[i]; local spell = entry.spell; bar.row:Show()
                bar.row:ClearAllPoints()
                local yOff2 = -((i-1) * stride)
                bar.row:SetPoint("TOPLEFT", W.srcContent, "TOPLEFT", 0, yOff2)
                bar.row:SetPoint("TOPRIGHT", W.srcContent, "TOPRIGHT", 0, yOff2)
                bar.row:SetHeight(barH)
                local iconOffset = 0
                if spell.spellID then
                    local spIcon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell.spellID)
                    if spIcon then bar.classIcon:SetTexture(spIcon); bar.classIcon:SetTexCoord(0.065, 0.935, 0.065, 0.935); bar.classIcon:SetSize(barH, barH); bar.classIcon:Show(); iconOffset = barH
                    else bar.classIcon:Hide() end
                else bar.classIcon:Hide() end
                bar.fill:ClearAllPoints(); bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", iconOffset, 0)
                bar.fill:SetPoint("TOPRIGHT", bar.row, "TOPRIGHT", 0, 0); bar.fill:SetHeight(barH)
                ApplyBarTexture(bar.fill, texPath, texKey); bar.fill:SetMinMaxValues(0, maxAmt); bar.fill:SetValue(entry.amount)
                if W.sourceClass and RAID_CLASS_COLORS[W.sourceClass] then
                    local cc = RAID_CLASS_COLORS[W.sourceClass]; bar.fill:SetStatusBarColor(cc.r, cc.g, cc.b)
                else local ar2, ag2, ab2 = GetAccentRGB(); bar.fill:SetStatusBarColor(ar2, ag2, ab2) end
                SetDMFont(bar.label, leftFS); SetDMFont(bar.amount, rightFS)
                local spellName
                if spell.spellID then local okS, sn = pcall(function() return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell.spellID) end); spellName = (okS and sn) or nil end
                bar.label:SetText(spellName or spell.creatureName or "Unknown")
                if canPercent and totalDmg > 0 then
                    bar.amount:SetText(format("%s  %.1f%%", AbbrevNumber(entry.amount), (entry.amount / totalDmg) * 100))
                else
                    bar.amount:SetText(AbbrevNumber(entry.amount))
                end
                bar._spellID = spell.spellID
            else bar.row:Hide(); bar._spellID = nil end
        end

        -- Targets section (DamageDone only): show top 3 enemies this player hit
        local targetsRendered = 0
        if W.curDMType == Enum.DamageMeterType.DamageDone then
            if not W._cachedTargets then
                W._cachedTargets = BuildPlayerTargets(W.sourceRawName, W.curSession, W.curSessionID, 3) or false
            end
            local tList = W._cachedTargets
            if tList and tList ~= false then
                -- Divider + "Targets" label
                local divY = -(spCount * stride + barSp * 2)
                if not W._targetDivider then
                    W._targetDivider = W.srcContent:CreateTexture(nil, "ARTWORK")
                    W._targetDivider:SetHeight(PhysicalPixels(1)); W._targetDivider:SetColorTexture(1, 1, 1, 0.15)
                    W._targetLabel = W.srcContent:CreateFontString(nil, "OVERLAY")
                    SetDMFont(W._targetLabel, leftFS - 1)
                    W._targetLabel:SetTextColor(0.6, 0.6, 0.6, 1); W._targetLabel:SetText("Targets")
                end
                W._targetDivider:ClearAllPoints()
                W._targetDivider:SetPoint("TOPLEFT", W.srcContent, "TOPLEFT", 0, divY)
                W._targetDivider:SetPoint("TOPRIGHT", W.srcContent, "TOPRIGHT", 0, divY)
                W._targetDivider:Show()
                local labelY = divY - barSp - 10
                W._targetLabel:ClearAllPoints()
                W._targetLabel:SetPoint("LEFT", W.srcContent, "TOPLEFT", 3, labelY)
                SetDMFont(W._targetLabel, leftFS - 1)
                W._targetLabel:Show()

                local tStartY = labelY - 12
                local tMaxAmt = tList[1].total
                for ti = 1, #tList do
                    local tIdx = spCount + ti
                    if tIdx > BAR_POOL_SIZE then break end
                    local bar = W.spellPool[tIdx]
                    local t = tList[ti]; bar.row:Show()
                    bar.row:ClearAllPoints()
                    bar.row:SetPoint("TOPLEFT", W.srcContent, "TOPLEFT", 0, tStartY - ((ti-1) * stride))
                    bar.row:SetPoint("TOPRIGHT", W.srcContent, "TOPRIGHT", 0, tStartY - ((ti-1) * stride))
                    bar.row:SetHeight(barH)
                    bar.classIcon:Hide()
                    bar.fill:ClearAllPoints(); bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", 0, 0)
                    bar.fill:SetPoint("TOPRIGHT", bar.row, "TOPRIGHT", 0, 0); bar.fill:SetHeight(barH)
                    ApplyBarTexture(bar.fill, texPath, texKey); bar.fill:SetMinMaxValues(0, tMaxAmt); bar.fill:SetValue(t.total)
                    bar.fill:SetStatusBarColor(0xDD/255, 0x31/255, 0x31/255)
                    SetDMFont(bar.label, leftFS); SetDMFont(bar.amount, rightFS)
                    bar.label:SetTextColor(1, 1, 1); bar.amount:SetTextColor(1, 1, 1)
                    bar.label:SetText(t.name)
                    bar.amount:SetText(AbbrevNumber(t.total)); bar._spellID = nil
                    targetsRendered = targetsRendered + 1
                end
            end
        end
        -- Hide divider/label if no targets
        if targetsRendered == 0 then
            if W._targetDivider then W._targetDivider:Hide() end
            if W._targetLabel then W._targetLabel:Hide() end
        end

        local extraH = 0
        if targetsRendered > 0 then
            -- divider gap + label + target bars
            extraH = (barSp * 2) + 1 + barSp + 10 + 12 + (targetsRendered * stride)
        end
        local srcTotalH = spCount * stride + extraH
        W.srcContent:SetHeight(math.max(10, srcTotalH))
        local srcViewH = W.srcViewport:GetHeight(); if srcViewH < 1 then srcViewH = 1 end
        _srcScrollMax = math.max(0, srcTotalH - srcViewH)
    end

    function W.OpenSource(guid, creatureID, name, classFile, recapID, rawName)
        if not W.sourceFrame then return end
        W.sourceGUID = guid; W.sourceCreatureID = creatureID; W.sourceClass = classFile; W.sourceOpen = true
        W.sourceRecapID = recapID; W.sourceRawName = rawName
        W._cachedTargets = nil
        W.HideHome()
        if viewport then viewport:Hide() end
        if W.stickyPlayer then W.stickyPlayer.row:Hide() end
        if W.stickySep then W.stickySep:Hide() end
        if frame._bg then frame._bg:Hide() end
        W.sourceFrame:Show(); W.RefreshBreakdown()
    end

    function W.CloseSource()
        W.sourceOpen = false; W.sourceGUID = nil; W.sourceCreatureID = nil; W.sourceRecapID = nil; W.sourceRawName = nil
        W._cachedTargets = nil
        if W.sourceFrame then W.sourceFrame:Hide() end
        if viewport then viewport:Show() end
        if frame._bg then frame._bg:Show() end
        W.UpdateSticky(nil, W.visibleCount)
    end

    ---------------------------------------------------------------------------
    --  Home screen (quick links grid)
    --  2-column card layout with accent indicators, + add button, hint text.
    ---------------------------------------------------------------------------
    local homeScroll, homeChild  -- homeFrame is forward-declared above
    local homeCards = {}
    local homeAddBtn, homeTitle
    local _homeScrollMax = 0
    local CARD_H       = 26
    local CARD_GAP     = 4
    local CARD_COL_GAP = 4
    local CARD_PAD_X   = 8
    local CARD_PAD_TOP = 6
    local CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A = 0.12, 0.12, 0.12, 0.8
    local CARD_HL_A    = 0.18
    local HOME_MAX     = 8

    -- HOME_ICONS is at file scope

    local function MakeCard(parent)
        local card = CreateFrame("Button", nil, parent)
        card:SetHeight(CARD_H)
        card:RegisterForClicks("AnyUp")

        -- Card background
        card._bg = card:CreateTexture(nil, "BACKGROUND")
        card._bg:SetAllPoints()
        card._bg:SetColorTexture(CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A)

        -- Accent left edge indicator (2px wide)
        card._accent = card:CreateTexture(nil, "ARTWORK")
        card._accent:SetWidth(2)
        card._accent:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
        card._accent:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
        card._accent:Hide()

        -- Type icon
        local fontPath = (EUI.GetFontPath and EUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local outline = (EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag()) or ""
        local iconSz = CARD_H - 2
        card._icon = card:CreateTexture(nil, "OVERLAY")
        card._icon:SetSize(iconSz, iconSz)
        card._icon:SetPoint("LEFT", card, "LEFT", 6, 0)
        card._icon:SetDesaturated(true)

        -- Label
        card._lbl = card:CreateFontString(nil, "OVERLAY")
        card._lbl:SetFont(fontPath, CTX_FONT_SZ, outline)
        card._lbl:SetPoint("LEFT", card._icon, "RIGHT", 5, 0)
        card._lbl:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        card._lbl:SetJustifyH("LEFT")
        card._lbl:SetWordWrap(false)

        -- Arrow ">"
        card._arrow = card:CreateTexture(nil, "ARTWORK")
        card._arrow:SetTexture(CTX_ARROW_ICON)
        card._arrow:SetSize(18, 18)
        card._arrow:SetPoint("RIGHT", card, "RIGHT", -4, 0)
        card._arrow:SetRotation(math.pi / 2)
        card._arrow:SetVertexColor(1, 1, 1, 1)

        return card
    end

    RefreshHome = function()
        if not homeFrame or not homeFrame:IsShown() then return end
        local bookmarks = GetBookmarks()
        local fontPath = (EUI.GetFontPath and EUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local outline = (EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag()) or ""
        local EG = EUI.ELLESMERE_GREEN
        local acR, acG, acB = GetAccentRGB()

        -- Calculate column width from scroll frame
        local totalW = homeScroll and homeScroll:GetWidth() or homeFrame:GetWidth()
        local colW = (totalW - CARD_PAD_X * 2 - CARD_COL_GAP) / 2

        -- Hide all existing cards
        for _, c in ipairs(homeCards) do c:Hide() end

        -- Layout bookmarks in 2-column grid
        local row, col = 0, 0
        local startY = -CARD_PAD_TOP

        for idx, dmType in ipairs(bookmarks) do
            local card = homeCards[idx]
            if not card then
                card = MakeCard(homeChild)
                homeCards[idx] = card
            end

            local label = DM_TYPE_NAMES[dmType] or "Unknown"
            local isActive = (dmType == W.curDMType)

            -- Position in grid
            local xOff = CARD_PAD_X + col * (colW + CARD_COL_GAP)
            local yOff = startY - row * (CARD_H + CARD_GAP)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", homeChild, "TOPLEFT", xOff, yOff)
            card:SetWidth(colW)

            -- Visuals
            card._bg:SetColorTexture(CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A)
            card._lbl:SetFont(fontPath, CTX_FONT_SZ, outline)
            card._lbl:SetText(label)
            card._icon:SetTexture(DM_TYPE_ICONS[dmType] or MEDIA .. "dm_home_damage.png")
            card._arrow:Show()

            if isActive then
                card._accent:SetColorTexture(acR, acG, acB, 1)
                card._accent:Show()
                card._icon:SetVertexColor(acR, acG, acB, 1)
                card._lbl:SetTextColor(1, 1, 1, 1)
                card._arrow:SetVertexColor(1, 1, 1, 1)
            else
                card._accent:Hide()
                card._icon:SetVertexColor(acR, acG, acB, 0.6)
                card._lbl:SetTextColor(1, 1, 1, 0.8)
                card._arrow:SetVertexColor(1, 1, 1, 1)
            end

            card:SetScript("OnEnter", function(self)
                self._bg:SetColorTexture(CARD_BG_R + 0.06, CARD_BG_G + 0.06, CARD_BG_B + 0.06, CARD_BG_A + CARD_HL_A)
                self._lbl:SetTextColor(1, 1, 1, 1)
                self._arrow:SetVertexColor(1, 1, 1, 1)
            end)
            card:SetScript("OnLeave", function(self)
                self._bg:SetColorTexture(CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A)
                if isActive then
                    self._lbl:SetTextColor(1, 1, 1, 1)
                    self._arrow:SetVertexColor(1, 1, 1, 1)
                else
                    self._lbl:SetTextColor(1, 1, 1, 0.8)
                    self._arrow:SetVertexColor(1, 1, 1, 1)
                end
            end)
            card:SetScript("OnClick", function(_, button)
                if button == "MiddleButton" then
                    table.remove(bookmarks, idx)
                    RefreshHome()
                elseif button == "LeftButton" then
                    W.curDMType = dmType; wdb.curDMType = dmType
                    W._modeIcon:SetTexture(DM_TYPE_ICONS[dmType] or DM_TYPE_ICONS[Enum.DamageMeterType.DamageDone])
                    W.HideHome(); W.CloseSource(); W.Refresh()
                end
            end)

            card:Show()
            col = col + 1
            if col >= 2 then col = 0; row = row + 1 end
        end

        -- "+ ADD NEW" button (full width, below the grid)
        local addRow = (col > 0) and (row + 1) or row
        if #bookmarks < HOME_MAX then
            if not homeAddBtn then
                homeAddBtn = CreateFrame("Button", nil, homeChild)
                homeAddBtn:SetHeight(CARD_H)
                homeAddBtn._bg = homeAddBtn:CreateTexture(nil, "BACKGROUND"); homeAddBtn._bg:SetAllPoints()
                homeAddBtn._plus = homeAddBtn:CreateFontString(nil, "OVERLAY")
                homeAddBtn._lbl = homeAddBtn:CreateFontString(nil, "OVERLAY")
                homeAddBtn._hint = homeAddBtn:CreateFontString(nil, "OVERLAY")
                homeAddBtn._plus:SetPoint("RIGHT", homeAddBtn._lbl, "LEFT", -4, 0)
                homeAddBtn._hint:SetPoint("LEFT", homeAddBtn._lbl, "RIGHT", 6, 0)
            end
            homeAddBtn._bg:SetColorTexture(CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A * 0.5)
            homeAddBtn._plus:SetFont(fontPath, 13, outline)
            homeAddBtn._plus:SetText("+")
            homeAddBtn._plus:SetTextColor(1, 1, 1, 0.3)
            homeAddBtn._lbl:SetFont(fontPath, CTX_FONT_SZ, outline)
            homeAddBtn._lbl:SetText("ADD NEW")
            homeAddBtn._lbl:SetTextColor(1, 1, 1, 0.3)
            homeAddBtn._hint:SetFont(fontPath, 9, outline)
            homeAddBtn._hint:SetText("(middle click to remove)")
            homeAddBtn._hint:SetTextColor(1, 1, 1, 0.3)
            -- Center the group: offset label so plus+label+hint are visually centered
            local plusW = homeAddBtn._plus:GetStringWidth() + 4
            local hintW = 6 + homeAddBtn._hint:GetStringWidth()
            local shift = (plusW - hintW) / 2
            homeAddBtn._lbl:ClearAllPoints()
            homeAddBtn._lbl:SetPoint("CENTER", homeAddBtn, "CENTER", shift, 0)
            homeAddBtn:ClearAllPoints()
            homeAddBtn:SetPoint("TOPLEFT", homeChild, "TOPLEFT", CARD_PAD_X, startY - addRow * (CARD_H + CARD_GAP))
            homeAddBtn:SetPoint("TOPRIGHT", homeChild, "TOPRIGHT", -CARD_PAD_X, startY - addRow * (CARD_H + CARD_GAP))
            homeAddBtn:SetScript("OnEnter", function(self)
                self._bg:SetColorTexture(CARD_BG_R + 0.04, CARD_BG_G + 0.04, CARD_BG_B + 0.04, CARD_BG_A * 0.7)
                self._lbl:SetTextColor(1, 1, 1, 0.5); self._plus:SetTextColor(1, 1, 1, 0.5)
            end)
            homeAddBtn:SetScript("OnLeave", function(self)
                self._bg:SetColorTexture(CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A * 0.5)
                self._lbl:SetTextColor(1, 1, 1, 0.3); self._plus:SetTextColor(1, 1, 1, 0.3)
            end)
            homeAddBtn:SetScript("OnClick", function()
                local items = {}
                for dt, n in pairs(DM_TYPE_NAMES) do
                    local pinned = false
                    for _, b in ipairs(bookmarks) do if b == dt then pinned = true; break end end
                    if not pinned then items[#items + 1] = { text = n, onClick = function()
                        bookmarks[#bookmarks + 1] = dt; RefreshHome()
                    end } end
                end
                table.sort(items, function(a2, b2) return a2.text < b2.text end)
                ShowEDMMenu(items)
            end)
            homeAddBtn:Show()
            addRow = addRow + 1
        elseif homeAddBtn then
            homeAddBtn:Hide()
        end

        -- Set scroll child height to fit all content + 5px bottom padding
        local contentH = math.abs(startY) + addRow * (CARD_H + CARD_GAP) + 5
        homeChild:SetHeight(math.max(10, contentH))

        -- Update scroll max
        if homeScroll then
            local viewH = homeScroll:GetHeight()
            _homeScrollMax = math.max(0, contentH - viewH)
            local cur = homeScroll:GetVerticalScroll() or 0
            if cur > _homeScrollMax then homeScroll:SetVerticalScroll(_homeScrollMax) end
        end
    end

    function W.ShowHome()
        if not homeFrame then
            homeFrame = CreateFrame("Frame", nil, frame)
            homeFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            homeFrame:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
            homeFrame:SetFrameLevel(frame:GetFrameLevel() + 25)
            homeFrame:EnableMouse(true); homeFrame:Hide()

            local hBg = homeFrame:CreateTexture(nil, "BACKGROUND")
            hBg:SetAllPoints()
            hBg:SetColorTexture(0.03, 0.03, 0.03, 0.95)

            -- Scrollable content area
            homeScroll = CreateFrame("ScrollFrame", nil, homeFrame)
            homeScroll:SetPoint("TOPLEFT", homeFrame, "TOPLEFT", 0, 0)
            homeScroll:SetPoint("BOTTOMRIGHT", homeFrame, "BOTTOMRIGHT", 0, 0)
            homeChild = CreateFrame("Frame", nil, homeScroll)
            homeChild:SetSize(1, 1)
            homeScroll:SetScrollChild(homeChild)
            homeScroll:SetScript("OnSizeChanged", function(_, w) homeChild:SetWidth(w) end)

            -- Mouse wheel scrolling (no visual scrollbar)
            local function HomeWheel(_, delta)
                local cur = homeScroll:GetVerticalScroll() or 0
                homeScroll:SetVerticalScroll(math.max(0, math.min(_homeScrollMax, cur - delta * 30)))
            end
            homeScroll:EnableMouseWheel(true)
            homeScroll:SetScript("OnMouseWheel", HomeWheel)
            homeFrame:EnableMouseWheel(true)
            homeFrame:SetScript("OnMouseWheel", HomeWheel)


            homeFrame:SetScript("OnMouseDown", function(_, button)
                if button == "RightButton" then W.HideHome() end
            end)
        end

        if viewport then viewport:Hide() end
        if W.stickyPlayer then W.stickyPlayer.row:Hide() end
        if W.stickySep then W.stickySep:Hide() end
        if frame._bg then frame._bg:Hide() end
        homeFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        homeFrame:Show()
        RefreshHome()
    end

    function W.HideHome()
        if homeFrame then homeFrame:Hide() end
        if viewport then viewport:Show() end
        if frame._bg then frame._bg:Show() end
    end

    -- (Refresh ticker is shared across all windows -- see file scope below CreateDMWindow)

    ---------------------------------------------------------------------------
    --  Visibility
    ---------------------------------------------------------------------------
    function W.UpdateVisibility()
        if not frame then return end
        local c = DB()
        if EUI._unlockActive or ns._optionsOpen then frame:SetAlpha(1); frame:EnableMouse(true); frame:Show(); return end
        local vis = EUI.EvalVisibility and EUI.EvalVisibility(c)
        if not vis or vis == false then frame:Hide(); return end
        -- Per-window instance visibility
        local _, iType = IsInInstance()
        if wdb.hideInDungeon and iType == "party" then frame:Hide(); return end
        if wdb.hideInRaid and iType == "raid" then frame:Hide(); return end
        if wdb.hideOutOfInstance and (iType == "none" or iType == nil) then frame:Hide(); return end
        if vis == "mouseover" then frame:Hide()
        else frame:SetAlpha(1); frame:EnableMouse(true); frame:Show() end
    end

    if EUI.RegisterVisibilityUpdater then EUI.RegisterVisibilityUpdater(W.UpdateVisibility) end
    if EUI.RegisterMouseoverTarget then
        EUI.RegisterMouseoverTarget(frame, function() local c = DB(); return c and c.visibility == "mouseover" end)
    end

    ---------------------------------------------------------------------------
    --  Destroy
    ---------------------------------------------------------------------------
    function W.Destroy()
        if W._hoverTicker then W._hoverTicker:Cancel() end
        unlockFadeFrame:SetScript("OnUpdate", nil)
        resizeFrame:SetScript("OnUpdate", nil)
        -- Unregister from global visibility system (prevents ghost resurrection)
        if EUI.UnregisterVisibilityUpdater then EUI.UnregisterVisibilityUpdater(W.UpdateVisibility) end
        frame:Hide(); frame:SetParent(nil)
        -- Remove from runtime array
        local runtimeIdx
        for i, w in ipairs(_windows) do if w == W then runtimeIdx = i; break end end
        if runtimeIdx then table.remove(_windows, runtimeIdx) end
        -- Compact DB: remove entry and shift remaining down (no holes)
        local c = DB()
        if c.windows then
            table.remove(c.windows, winIdx)
            c.windowCount = #c.windows
        end
        -- Update remaining windows' idx to match their new DB position
        for i, w in ipairs(_windows) do w.idx = i end
    end


    W.UpdateVisibility()

    -- Defer initial refresh off the init frame
    C_Timer.After(0, function()
        W.Refresh()
        -- First install: show home page so user can pick a mode
        if not wdb.curDMType then W.ShowHome() end
    end)

    return W
end

-------------------------------------------------------------------------------
--  ns exports (loop over all windows)
-------------------------------------------------------------------------------
ns.RefreshMeter = function()
    for _, w in ipairs(_windows) do w.Refresh() end
end

ns.ApplyBorder = function()
    for _, w in ipairs(_windows) do
        if w.rowPool then
            for _, bar in ipairs(w.rowPool) do
                if bar.ApplyBorder then bar.ApplyBorder() end
            end
        end
        if w.stickyPlayer and w.stickyPlayer.ApplyBorder then
            w.stickyPlayer.ApplyBorder()
        end
    end
end

ns.ApplyBackground = function()
    local cfg = DB()
    local r, g, b, a = cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgAlpha or 0.75
    for _, w in ipairs(_windows) do
        if w.frame and w.frame._bg then w.frame._bg:SetColorTexture(r, g, b, a) end
        if w.sourceFrame and w.sourceFrame._bg then w.sourceFrame._bg:SetColorTexture(r, g, b, a) end
    end
end

ns.ApplyHeader = function()
    local cfg = DB()
    local hc = cfg.hdrBgColor; local hR = hc and hc.r or 0x1B/255; local hG = hc and hc.g or 0x1B/255; local hB = hc and hc.b or 0x1B/255
    local hA = cfg.hdrBgAlpha or 1
    local tR, tG, tB
    if cfg.hdrTextUseAccent ~= false then tR, tG, tB = GetAccentRGB()
    else local c = cfg.hdrTextColor; tR = c and c.r or 1; tG = c and c.g or 1; tB = c and c.b or 1 end
    local hdrFS = cfg.hdrFontSize or 11
    local hdrH = GetHeaderH()
    local iconSz = cfg.hdrIconSize or 14
    for _, w in ipairs(_windows) do
        if w.header then
            w.header:SetHeight(hdrH)
            if w.header._hdrBg then w.header._hdrBg:SetColorTexture(hR, hG, hB, hA) end
        end
        if w.frame and w.frame._bg then
            w.frame._bg:ClearAllPoints()
            w.frame._bg:SetPoint("TOPLEFT", w.frame, "TOPLEFT", 0, -hdrH)
            w.frame._bg:SetPoint("BOTTOMRIGHT", w.frame, "BOTTOMRIGHT", 0, 0)
        end
        if w.titleText then
            SetDMFont(w.titleText, hdrFS)
            w.titleText:SetTextColor(tR, tG, tB, 1)
            local txOX, txOY = cfg.hdrTextOffX or 0, cfg.hdrTextOffY or 0
            w.titleText:ClearAllPoints()
            w.titleText:SetPoint("LEFT", w.header, "LEFT", 6 + txOX, txOY)
        end
        if w.timerText then
            SetDMFont(w.timerText, hdrFS)
        end
        -- Resize and reposition header buttons
        if w.hdrBtns then
            local btnPad = -2
            for bi, btn in ipairs(w.hdrBtns) do
                btn:SetSize(iconSz, iconSz)
                btn:ClearAllPoints()
                btn:SetPoint("RIGHT", w.header, "RIGHT", -(iconSz * (bi - 1) + btnPad * bi + 2), 0)
            end
        end
        -- Close icon is 2px larger than other icons
        if w._closeIconTex then
            w._closeIconTex:ClearAllPoints()
            w._closeIconTex:SetSize(iconSz + 2, iconSz + 2)
            w._closeIconTex:SetPoint("CENTER", w.winActionBtn, "CENTER", 0, 0)
        end

        ApplyHeaderButtonsHoverVisibility(w, cfg)
    end
end

ns.ApplyIconColor = function()
    local cfg = DB()
    local r, g, b
    if cfg.iconColorUseAccent then r, g, b = GetAccentRGB()
    else local c = cfg.iconColor; r = c and c.r or 1; g = c and c.g or 1; b = c and c.b or 1 end
    for _, w in ipairs(_windows) do
        for _, icon in ipairs(w.hdrIcons) do icon:SetVertexColor(r, g, b, ICON_ALPHA) end
    end
end

ns.ApplyDMPosition = function()
    for _, w in ipairs(_windows) do
        local wdb = WinDB(w.idx)
        if w.frame and wdb.position and wdb.position.x and wdb.position.y then
            w.frame:ClearAllPoints()
            w.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", wdb.position.x, wdb.position.y)
        end
    end
end

ns.ApplyDMSize = function()
    for _, w in ipairs(_windows) do
        local wdb = WinDB(w.idx)
        if w.frame then
            if wdb.width then w.frame:SetWidth(math.max(MIN_W, wdb.width)) end
            if wdb.height then w.frame:SetHeight(math.max(MIN_H, wdb.height)) end
        end
    end
end

-------------------------------------------------------------------------------
--  Standalone Combat Timer
-------------------------------------------------------------------------------
local _saTimer  -- frame reference
local _saTimerFS -- fontstring
local _saTimerPreview = false

local function GetSATimerColor()
    local cfg = DB()
    if cfg.standaloneTimerUseAccent then return GetAccentRGB() end
    local c = cfg.standaloneTimerColor
    return c and c.r or 1, c and c.g or 1, c and c.b or 1
end

local function ApplySATimerStyle()
    if not _saTimer or not _saTimerFS then return end
    local cfg = DB()
    SetDMFont(_saTimerFS, cfg.standaloneTimerSize or 14)
    local r, g, b = GetSATimerColor()
    _saTimerFS:SetTextColor(r, g, b, 1)
    _saTimerFS:ClearAllPoints()
    local anchor = cfg.standaloneTimerAnchor or "free"
    local alignLeft
    if anchor == "free" then
        alignLeft = cfg.standaloneTimerAlignLeft
    else
        alignLeft = anchor == "topleft" or anchor == "bottomleft"
    end
    if alignLeft then
        _saTimerFS:SetPoint("LEFT")
        _saTimerFS:SetJustifyH("LEFT")
    else
        _saTimerFS:SetPoint("RIGHT")
        _saTimerFS:SetJustifyH("RIGHT")
    end
end

UpdateSATimerText = function()
    if not _saTimer or not _saTimerFS then return end
    local cfg = DB()
    if not cfg.standaloneTimer then return end
    -- Only visible during group combat (or options preview)
    if not _inCombat then
        if not _saTimerPreview and _saTimer:IsShown() then _saTimer:Hide() end
        return
    end
    if not _saTimer:IsShown() then _saTimer:Show() end
    local elapsed = GetCombatElapsed()
    _saTimerFS:SetText(FormatTimer(elapsed > 0 and elapsed or 0))
end

local function RepositionSATimer()
    if not _saTimer then return end
    local cfg = DB()
    local anchor = cfg.standaloneTimerAnchor or "free"

    _saTimer:ClearAllPoints()

    if anchor == "free" then
        _saTimer:SetMovable(true)
        _saTimer:EnableMouse(true)
        local pos = cfg.standaloneTimerPos
        if pos and pos.x and pos.y then
            _saTimer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
        else
            local W1 = _windows[1]
            if W1 and W1.frame then
                _saTimer:SetPoint("BOTTOMRIGHT", W1.frame, "TOPRIGHT", 0, 5)
            else
                _saTimer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
        return
    end

    _saTimer:SetMovable(false)
    _saTimer:EnableMouse(false)

    -- Find the highest (max top) and lowest (min bottom) window
    local topWin, botWin
    local maxTop, minBot = -math.huge, math.huge
    for _, w in ipairs(_windows) do
        if w.frame and w.frame:IsShown() then
            local t = w.frame:GetTop()
            local b = w.frame:GetBottom()
            if t and t > maxTop then maxTop = t; topWin = w end
            if b and b < minBot then minBot = b; botWin = w end
        end
    end

    local isTop = anchor == "topleft" or anchor == "topright"
    local isLeft = anchor == "topleft" or anchor == "bottomleft"
    local ref = isTop and topWin or botWin

    if not ref or not ref.frame then
        _saTimer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end

    if isTop and isLeft then
        _saTimer:SetPoint("BOTTOMLEFT", ref.frame, "TOPLEFT", 0, 0)
    elseif isTop then
        _saTimer:SetPoint("BOTTOMRIGHT", ref.frame, "TOPRIGHT", 0, 0)
    elseif isLeft then
        _saTimer:SetPoint("TOPLEFT", ref.frame, "BOTTOMLEFT", 0, 0)
    else
        _saTimer:SetPoint("TOPRIGHT", ref.frame, "BOTTOMRIGHT", 0, 0)
    end
end

local function CreateSATimer()
    if _saTimer then return end
    local cfg = DB()

    _saTimer = CreateFrame("Frame", "EllesmereUIDMStandaloneTimer", UIParent)
    _saTimer:SetSize(1, 1)
    _saTimer:SetClampedToScreen(true)
    _saTimer:SetMovable(true)
    _saTimer:EnableMouse(true)
    _saTimer:SetFrameStrata("HIGH")
    _saTimer:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and IsShiftKeyDown() then
            local c = DB()
            if (c.standaloneTimerAnchor or "free") == "free" then self:StartMoving() end
        end
    end)
    _saTimer:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local c = DB()
        if (c.standaloneTimerAnchor or "free") == "free" then
            local left, top = self:GetLeft(), self:GetTop()
            if left and top then c.standaloneTimerPos = { x = left, y = top } end
        end
    end)

    _saTimerFS = _saTimer:CreateFontString(nil, "OVERLAY")
    _saTimerFS:SetPoint("RIGHT")
    ApplySATimerStyle()
    _saTimerFS:SetText("0:00")

    -- Size to text
    _saTimer:SetScript("OnSizeChanged", nil)
    local function ResizeToText()
        local w = (_saTimerFS:GetStringWidth() or 30) + 4
        local h = (_saTimerFS:GetStringHeight() or 14) + 4
        _saTimer:SetSize(w, h)
    end
    _saTimerFS:SetText("99:99")
    ResizeToText()
    _saTimerFS:SetText("0:00")

    RepositionSATimer()

    _saTimer:Hide()  -- starts hidden; combat state controls visibility
end

ns.ApplySATimer = function()
    local cfg = DB()
    if cfg.standaloneTimer then
        if not _saTimer then CreateSATimer() end
        ApplySATimerStyle()
        -- Resize for new font size (measure with worst-case, then restore)
        local prevText = _saTimerFS:GetText()
        _saTimerFS:SetText("99:99")
        local w = (_saTimerFS:GetStringWidth() or 30) + 4
        local h = (_saTimerFS:GetStringHeight() or 14) + 4
        _saTimer:SetSize(w, h)
        RepositionSATimer()
        if _saTimerPreview then
            _saTimerFS:SetText("11:37")
        else
            _saTimerFS:SetText(prevText or "0:00")
            UpdateSATimerText()
        end
    else
        if _saTimer then _saTimer:Hide() end
    end
end

ns.ShowSATimerPreview = function()
    if not _saTimer then CreateSATimer() end
    if not _saTimer then return end
    _saTimerPreview = true
    _saTimerFS:SetText("11:37")
    _saTimer:Show()
end
ns.HideSATimerPreview = function()
    _saTimerPreview = false
    if not _saTimer then return end
    if not _inCombat then _saTimer:Hide() end
end

-- Accent color callback for standalone timer
if EUI.RegAccent then
    EUI.RegAccent({ type = "callback", fn = function(r, g, b)
        if not _saTimer or not _saTimerFS then return end
        local cfg = DB()
        if cfg.standaloneTimerUseAccent then
            _saTimerFS:SetTextColor(r, g, b, 1)
        end
    end })
end

-------------------------------------------------------------------------------
--  Shared refresh ticker (one ticker for ALL windows)
-------------------------------------------------------------------------------
local _sharedTicker

local function SharedRefreshTick()
    -- Player out of combat but group still fighting (player died mid-pull)
    if _needsFinalRefresh then
        if not IsGroupInCombat() then
            -- Group combat ended: freeze timer, final refresh, stop
            _combatEndTime = GetTime()
            _inCombat = false
            _needsFinalRefresh = false
            for _, w in ipairs(_windows) do w.Refresh() end
            if _sharedTicker then _sharedTicker:Cancel(); _sharedTicker = nil end
            return
        end
        -- Group still fighting: fall through to normal refresh
    end
    if _combatEndTime > 0 then
        -- Combat fully ended, ticker should stop
        if _sharedTicker then _sharedTicker:Cancel(); _sharedTicker = nil end
        return
    end
    for _, w in ipairs(_windows) do w.Refresh() end
end

-- Feign death cache: tracks hunter feign deaths via UNIT_FLAGS so they
-- can be filtered from the C_DamageMeter Deaths session (which sometimes
-- assigns a valid deathRecapID to feign deaths).
-- Only active during combat to avoid idle CPU cost.
local function StartSharedTicker()
    if _sharedTicker then _sharedTicker:Cancel() end
    local rate = DB().refreshRate or TICK_COMBAT
    _sharedTicker = C_Timer.NewTicker(rate, SharedRefreshTick)
end

local function StopSharedTicker()
    if _sharedTicker then _sharedTicker:Cancel(); _sharedTicker = nil end
end

-------------------------------------------------------------------------------
--  Combat state tracking (shared, group-aware)
-------------------------------------------------------------------------------
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:RegisterEvent("UNIT_FLAGS")
combatFrame:SetScript("OnEvent", function(_, event)
    if event == "UNIT_FLAGS" then
        -- Group member entered combat before us: start polling so bars populate
        if not _inCombat and not _sharedTicker and IsGroupInCombat() then
            _combatEndTime = 0
            local apiDur = C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds
                and C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Current)
            if apiDur and type(apiDur) == "number" and apiDur > 0 then
                _combatStartTime = GetTime() - apiDur
            end
            StartSharedTicker()
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        _inCombat = true
        _combatEndTime = 0
        _needsFinalRefresh = false
        _ttLastGUID = nil
        if _targetsCache then wipe(_targetsCache) end
        -- Sync timer with API: if session already has elapsed time, backdate our start
        local apiDur = C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds
            and C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Current)
        if apiDur and type(apiDur) == "number" and apiDur > 0 then
            _combatStartTime = GetTime() - apiDur
        else
            _combatStartTime = GetTime()
        end
        StartSharedTicker()
    else
        -- Feign Death + group still fighting: keep timer running
        if UnitIsFeignDeath and UnitIsFeignDeath("player") and IsGroupInCombat() then return end
        _ttLastGUID = nil
        if _targetsCache then wipe(_targetsCache) end
        -- Check if group is still fighting (player died but boss alive)
        if IsGroupInCombat() then
            _needsFinalRefresh = true  -- let tick poll until group leaves combat
            -- Don't freeze timer -- group is still in combat
        else
            -- Freeze timer: entire group out of combat
            _combatEndTime = GetTime()
            _inCombat = false
            _needsFinalRefresh = false
            for _, w in ipairs(_windows) do w.Refresh() end
            -- One final tick then stop
            C_Timer.After(DB().refreshRate or TICK_COMBAT, function()
                StopSharedTicker()
            end)
        end
        -- Delayed refresh after player exits combat: API needs a moment to
        -- declassify secret source GUIDs so breakdowns work post-combat
        C_Timer.After(0.5, function()
            for _, w in ipairs(_windows) do w.Refresh() end
        end)
    end
end)


-------------------------------------------------------------------------------
--  Reset Data keybind button (hidden, receives override binding click)
-------------------------------------------------------------------------------
if not _G["EllesmereUIDMResetBindBtn"] then
    local btn = CreateFrame("Button", "EllesmereUIDMResetBindBtn", UIParent)
    btn:Hide()
    btn:SetScript("OnClick", function()
        if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
            C_DamageMeter.ResetAllCombatSessions()
            _combatStartTime = 0; _combatEndTime = 0
            for _, w in ipairs(_windows) do w.Refresh() end
        end
    end)
end

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if EUI and EUI.ADDON_ROSTER then
        for _, info in ipairs(EUI.ADDON_ROSTER) do
            if info.folder == "EllesmereUIDamageMeters" and info.comingSoon then return end
        end
    end

    EnsureDB()
    -- Disable Blizzard's built-in damage meter UI; C_DamageMeter API still works
    SetCVarSafe("damageMeterEnabled", 0)
    AppendDMSharedMedia()
    local cfg = DB()

    _playerGUID = UnitGUID("player")

    -- Restore reset data keybind
    if cfg.resetDataKey and _G.EllesmereUIDMResetBindBtn then
        SetOverrideBindingClick(_G.EllesmereUIDMResetBindBtn, true, cfg.resetDataKey, "EllesmereUIDMResetBindBtn")
    end

    -- Defer window creation off the login frame to avoid blocking
    local cfg = DB()
    if not cfg.windows then cfg.windows = {} end
    -- windowCount is authoritative; trim stale array entries beyond it
    local winCount = math.max(1, cfg.windowCount or 1)
    cfg.windowCount = winCount
    for i = winCount + 1, MAX_WINDOWS do cfg.windows[i] = nil end
    local winIdx = 0
    local function CreateNextWindow()
        winIdx = winIdx + 1
        if winIdx > winCount then
            if cfg.standaloneTimer then CreateSATimer() end
            if _inCombat and not _sharedTicker then StartSharedTicker() end
            -- Pre-create tooltip frame so first hover doesn't pay creation cost
            EnsureTooltipFrame()
            local sc = (cfg.hoverTooltipScale or 100) / 100
            if _ttFrame then _ttFrame:SetScale(sc); _ttLastScale = sc end
            return
        end
        _windows[winIdx] = CreateDMWindow(winIdx)
        C_Timer.After(0, CreateNextWindow)
    end
    C_Timer.After(0, CreateNextWindow)

    -- Unlock mode hooks (notify all DM windows)
    _G._EDM_UnlockModeOpen = function()
        for _, w in ipairs(_windows) do if w._unlockOpen then w._unlockOpen() end end
    end
    _G._EDM_UnlockModeClose = function()
        for _, w in ipairs(_windows) do if w._unlockClose then w._unlockClose() end end
    end

    -- Profile swap rebuild: tear down all windows and recreate from new profile
    _G._EDM_Apply = function()
        -- Destroy existing windows (frame cleanup only, don't touch DB)
        for i = #_windows, 1, -1 do
            local w = _windows[i]
            if w._hoverTicker then w._hoverTicker:Cancel() end
            if EUI.UnregisterVisibilityUpdater and w.UpdateVisibility then
                EUI.UnregisterVisibilityUpdater(w.UpdateVisibility)
            end
            if w.frame then w.frame:Hide(); w.frame:SetParent(nil) end
        end
        wipe(_windows)
        -- Destroy standalone timer if present
        if _saTimer then _saTimer:Hide(); _saTimer:SetParent(nil); _saTimer = nil; _saTimerFS = nil end
        -- Hide tooltip
        if _ttFrame then _ttFrame:Hide() end
        _activeRow = nil
        -- Re-apply keybind from new profile
        local c = DB()
        if _G.EllesmereUIDMResetBindBtn then
            ClearOverrideBindings(_G.EllesmereUIDMResetBindBtn)
            if c.resetDataKey then
                SetOverrideBindingClick(_G.EllesmereUIDMResetBindBtn, true, c.resetDataKey, "EllesmereUIDMResetBindBtn")
            end
        end
        -- Recreate windows from new profile
        if not c.windows then c.windows = {} end
        local wc = math.max(1, c.windowCount or 1)
        c.windowCount = wc
        for i = wc + 1, MAX_WINDOWS do c.windows[i] = nil end
        for i = 1, wc do
            _windows[i] = CreateDMWindow(i)
        end
        -- Recreate standalone timer if enabled
        if c.standaloneTimer then CreateSATimer() end
        -- Update tooltip scale
        if _ttFrame then
            local sc = (c.hoverTooltipScale or 100) / 100
            _ttFrame:SetScale(sc)
        end
    end
end)
