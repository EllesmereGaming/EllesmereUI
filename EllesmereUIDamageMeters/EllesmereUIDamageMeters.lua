if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIDamageMeters.lua
--  Custom damage meter frame using C_DamageMeter API.
--  Multi-window support (up to 5). Zero Blizzard frame hooks. All settings live.
-------------------------------------------------------------------------------
local _, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.NewCombatQueue) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS["EllesmereUIDamageMeters"] = ns  -- LOD options files read this module ns via the registry
ns.CombatQueue = EllesmereUI.NewCombatQueue(CreateFrame("Frame"))
local EUI = EllesmereUI

-- Constants
local BAR_POOL_SIZE     = 40
local RANK_STRINGS      = {}
for i = 1, 40 do RANK_STRINGS[i] = i .. "." end
local MIN_W, MIN_H      = 150, 50
local TICK_COMBAT       = 1
local REFRESH_RATE_FLOOR      = 0.5  -- default floor; skipped when unsafeRefreshRate is on
local REFRESH_RATE_HARD_FLOOR = 0.2  -- absolute floor regardless of unsafeRefreshRate (the Unsafe slider's minimum); also guards a corrupt/imported 0 or negative value reaching the ticker
ns._REFRESH_RATE_FLOOR = REFRESH_RATE_FLOOR -- published so the options page's toggle-off snap-back uses the same value instead of a second hardcoded 0.5
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

-- DB defaults + helpers
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
            forceEnglishUnits = false, -- force K/M/B units, ignoring CJK locale's 萬/億 (opt-in; default keeps localized units)
            iconStyle       = "spec",
            classIconZoom = 0.06,
            spriteIconZoom = 0,
            iconSeparator = false,
            barSeparators = false,
            showPlayerMarker = false,
            iconColorUseAccent = false,
            iconColor       = { r = 1, g = 1, b = 1 },
            customIconBorder  = false,
            iconBorderTexture = "solid",
            iconBorderSize    = 0,
            iconBorderR = 0, iconBorderG = 0, iconBorderB = 0, iconBorderA = 1,
            showClassColor  = true,
            showPinnedSelf  = false,
            showHoverTooltip = true,
            showSpellTooltips = true,     -- game spell tooltip on breakdown-row hover
            breakdownAnchorPoint = "row", -- "row" (Above Row) | "center" (Center of Screen)
            breakdownBarTexture = "match",
            -- Global Settings > Style: the stock meter's window, header and
            -- bar art (Blizzard Style) or the vanilla tooltip box (Classic
            -- WoW UI) with every feature intact. Both default OFF;
            -- reload-gated; both set resolves as classic.
            useBlizzardStyle = false,
            useClassicStyle  = false,
            -- The WoW Forever look's Border Style (latched in ns.DMStyle, worn
            -- by the threat meter too): "textured" = Slim Textured, the default
            -- there (an unset value reads the same, EllesmereUI.
            -- ForeverBorderKind), "slim" = Slim, "heavy" = Heavy Bronze. Nil
            -- on every other client.
            foreverBorder = (EllesmereUI.IS_FOREVER == true) and "textured" or nil,
            barColorUseAccent = true,
            barColor        = { r = 0.35, g = 0.55, b = 0.8 },
            barFillAlpha    = 1,
            leftFontSize    = 11,
            leftTextUseClassColor = false,
            leftTextColor   = { r = 1, g = 1, b = 1 },
            rightFontSize   = 11,
            rightTextUseClassColor = false,
            rightTextUseThreatGradient = false,
            rightTextColor  = { r = 1, g = 1, b = 1 },
            leftTextOffsetX = 0,
            leftTextOffsetY = 0,
            rightTextOffsetX = 0,
            rightTextOffsetY = 0,
            bgR = 0, bgG = 0, bgB = 0, bgAlpha = 0.75,
            bgTexture = "none",
            windowBorderTexture = "solid",
            windowBorderSize = 0,
            windowBorderOffsetX = 0,
            windowBorderOffsetY = 0,
            windowBorderColor = { r = 0, g = 0, b = 0, a = 1 },
            windowBorderIncludeHeader = true,
            windowBorderBehind = false,
            barBgR = 0, barBgG = 0, barBgB = 0, barBgAlpha = 0,
            barBgUseClassColor = false,
            standaloneTimer       = false,
            standaloneTimerSize   = 26,
            standaloneTimerDecimal = false,
            standaloneTimerUseAccent = false,
            standaloneTimerColor  = { r = 1, g = 1, b = 1 },
            standaloneTimerPos    = nil,
            standaloneTimerAnchor = "free",
            standaloneTimerStrata = "HIGH",
            standaloneTimerShowOOC  = false,
            standaloneTimerDesatOOC = false,
            refreshRate = 1,
            unsafeRefreshRate = false, -- opt-in: lets refreshRate go below the 0.5s floor
            hideResetButton = false, -- display the "reset data" button on the damage meter header
            -- toggleWindowsKey (unset by default) is the hotkey that hides/shows every
            -- meter window at once. Runtime only: the hidden state is never saved, so a
            -- reload restores the configured visibility.
            toggleIncludeTimer        = false, -- also toggle the standalone combat timer
            toggleIncludeSpellHistory = false, -- also toggle the spell history icon strip and bar window
            hdrBgColor      = { r = 0x1B/255, g = 0x1B/255, b = 0x1B/255 },
            hdrBgAlpha      = 1,
            hdrBottomBorderSize = 0,
            hdrBottomSeparator = false,
            hdrBottomBorderColor = { r = 0, g = 0, b = 0, a = 1 },
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
EllesmereUI.RegisterBorderDefaults("damagemeters", EllesmereUI.BORDER_DEFAULTS_BARS)

EllesmereUI.RegisterBorderDefaults("damagemeters_icon", EllesmereUI.BORDER_DEFAULTS_BARS)

local _dmDB
local function EnsureDB()
    if _dmDB then return _dmDB end
    if not EUI or not EUI.Lite then return nil end
    _dmDB = EUI.Lite.NewDB("EllesmereUIDamageMetersDB", DM_DEFAULTS)
    _G._EDM_DB = _dmDB
    -- Refresh Rate floor raised to 0.5s: each tick fetches a full session
    -- snapshot per window, so sub-0.5 rates multiply allocation churn far
    -- past any visual gain. Clamp every stored profile once per session
    -- (idempotent; imports of old exports are caught by the ticker clamp
    -- until their next login). Skipped for a profile with unsafeRefreshRate
    -- on; the hard floor still applies regardless, so a corrupt/imported
    -- value can't reach the ticker as 0 or negative.
    local sv = _G.EllesmereUIDamageMetersDB
    if type(sv) == "table" and type(sv.profiles) == "table" then
        for _, p in pairs(sv.profiles) do
            local dm = type(p) == "table" and p.dm
            if type(dm) == "table" and type(dm.refreshRate) == "number" then
                local floor = dm.unsafeRefreshRate and REFRESH_RATE_HARD_FLOOR or REFRESH_RATE_FLOOR
                if dm.refreshRate < floor then
                    dm.refreshRate = floor
                end
            end
        end
    end
    return _dmDB
end

ns.EDM = {}
ns.EDM.DB = function()
    local d = _G._EDM_DB
    if d and d.profile and d.profile.dm then return d.profile.dm end
    return {}
end

local function DB() return ns.EDM.DB() end
-- The header's height: the Header Height setting, plus the Forever header
-- band's rail under it (ns.DMFvRail; 0 on every other look).
local function GetHeaderH() local c = DB(); local h = c.hdrHeight or 22; return h + ns.DMFvRail(h) end

-- Main-chunk locals of this file the EUI_DamageMeters_*.lua files re-import by
-- name; each of them adds what the files behind it need.
-- inCombatSetters and the lists beside it: every file that reads one of these
-- values keeps its own copy and adds a setter here; every assignment goes
-- through the Set<Name> function built below (except the per-tick pin of
-- _curViewFrozenDur in GetCurrentViewDuration, State's only copy).
-- broken: true while a part file loads; a file that fails leaves it set, and
-- the files behind it return at their first lines.
ns._dmInternals = {
    BAR_POOL_SIZE = BAR_POOL_SIZE, BAR_TEX = BAR_TEX, DB = DB, DM_TYPE_ICONS = DM_TYPE_ICONS,
    DM_TYPE_NAMES = DM_TYPE_NAMES, EnsureDB = EnsureDB, GetHeaderH = GetHeaderH,
    HOME_DEFAULTS = HOME_DEFAULTS, ICON_ALPHA = ICON_ALPHA, ICON_HOVER_ALPHA = ICON_HOVER_ALPHA,
    MAX_WINDOWS = MAX_WINDOWS, MEDIA = MEDIA, MIN_H = MIN_H, MIN_W = MIN_W,
    PEAK_BUDGET = PEAK_BUDGET, RANK_STRINGS = RANK_STRINGS,
    REFRESH_RATE_FLOOR = REFRESH_RATE_FLOOR, REFRESH_RATE_HARD_FLOOR = REFRESH_RATE_HARD_FLOOR,
    RESIZE_ICON = RESIZE_ICON, SESSION_TYPE_NAMES = SESSION_TYPE_NAMES,
    SESSION_TYPES = SESSION_TYPES, TICK_COMBAT = TICK_COMBAT,
    inCombatSetters = {}, inEncounterSetters = {}, combatEndTimeSetters = {},
    needsFinalRefreshSetters = {}, curViewFrozenDurSetters = {}, stopSharedTickerSetters = {},
    startSharedTickerSetters = {}, sharedTickerSetters = {}, ttFrameSetters = {},
    activeRowSetters = {}, ttLastScaleSetters = {}, playerGUIDSetters = {},
    updateSATimerTextSetters = {}, saTimerSetters = {},
    broken = false,
}
-- Set<Name> hands a new value to every copy registered in <name>Setters.
for setter, listName in pairs({
    SetInCombat = "inCombatSetters", SetInEncounter = "inEncounterSetters",
    SetCombatEndTime = "combatEndTimeSetters",
    SetNeedsFinalRefresh = "needsFinalRefreshSetters",
    SetCurViewFrozenDur = "curViewFrozenDurSetters",
    SetStopSharedTicker = "stopSharedTickerSetters",
    SetStartSharedTicker = "startSharedTickerSetters", SetSharedTicker = "sharedTickerSetters",
    SetTTFrame = "ttFrameSetters", SetActiveRow = "activeRowSetters",
    SetTTLastScale = "ttLastScaleSetters", SetPlayerGUID = "playerGUIDSetters",
    SetUpdateSATimerText = "updateSATimerTextSetters", SetSATimer = "saTimerSetters",
}) do
    local list = ns._dmInternals[listName]
    ns._dmInternals[setter] = function(v)
        for i = 1, #list do list[i](v) end
    end
end
-- A re-import of a name this table lacks fails where the part file loads,
-- not later as a nil upvalue inside one of its functions.
setmetatable(ns._dmInternals, { __index = function(_, k)
    error("ns._dmInternals has no entry " .. tostring(k), 2)
end })
