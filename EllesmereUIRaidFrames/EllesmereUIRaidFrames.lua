-------------------------------------------------------------------------------
--  EllesmereUIRaidFrames.lua
--  Custom raid frames built on SecureGroupHeaderTemplate.
--  8 per-group headers (separated mode) + 1 combined header (flat mode).
--  Secret-value-safe absorb shields matching UnitFrames visuals.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local ERF = EllesmereUI.Lite.NewAddon(ADDON_NAME)
ns.ERF = ERF
_G.EllesmereUIRaidFrames = ERF

-------------------------------------------------------------------------------
--  Frame-level layout (offsets above the button / preview-frame level).
--  All aura VISUALS share one band ABOVE the threat/dispel/base border so the
--  threat border renders behind them: debuffs, defensives/externals, private
--  auras, dispel-type icons, and Buff Manager icons/squares/bars. Each aura
--  unit renders its own children (cooldown/border/text) up to +5 above its base.
--  Only the target/hover border-raise and the marker carrier sit above the band.
--  Kept on `ns` (not file-scope locals) to avoid the Lua 5.1 local cap in this
--  large file, and shared with EUI_RaidFrames_BuffManager.lua.
-------------------------------------------------------------------------------
ns.LVL_AURA   = 13   -- base level for every aura icon/bar (children at +1..+5); sits ONE above the name/health text (+12) so auras draw over text
ns.LVL_RAISE  = 20   -- main border while hovered/targeted (PP container at +1)
ns.LVL_MARKER = 22   -- raid marker icon (always on top)

-------------------------------------------------------------------------------
--  Chat-strata host: lowers a frame onto the chat frame's strata, one level
--  above it, so its contents render on the SAME layer as chat (just above chat
--  on that layer) instead of the marker carrier's always-on-top layer. Used by
--  the leader/assistant icon host. Re-applied on reload so it tracks the chat
--  frame's current strata/level (and recovers if a container SetFrameStrata
--  cascade reset it). Mirrors the chat sidebar's own strata match.
-------------------------------------------------------------------------------
function ns.ApplyChatStrata(frame)
    local cf = DEFAULT_CHAT_FRAME
    if cf and cf.GetFrameStrata then
        frame:SetFrameStrata(cf:GetFrameStrata())
        frame:SetFrameLevel((cf:GetFrameLevel() or 0) + 1)
    else
        frame:SetFrameStrata("LOW")
    end
end

-------------------------------------------------------------------------------
--  Profiler: zero cost when off, /erfprof to toggle.
-------------------------------------------------------------------------------
do
    local _profData, _profActive = {}, false
    local dps = debugprofilestop
    local _addonName = "EllesmereUIRaidFrames"
    local _frameCount = 0
    local _totalAddonMs = 0
    local _peakAddonMs = 0
    local _startTime = 0
    local _curFrameLabels = {}
    local _curFrameTotal = 0
    local _curFrameTime = 0
    local _peakFrameLabels = {}
    local _peakFrameTotal = 0

    ns.ProfBegin = function(label)
        if not _profActive then return 0 end
        return dps()
    end
    ns.ProfEnd = function(label, t0)
        if not _profActive then return end
        local elapsed = dps() - t0
        local now = GetTime()
        if now ~= _curFrameTime then
            if _curFrameTotal > _peakFrameTotal then
                _peakFrameTotal = _curFrameTotal
                wipe(_peakFrameLabels)
                for k, v in pairs(_curFrameLabels) do _peakFrameLabels[k] = v end
            end
            wipe(_curFrameLabels)
            _curFrameTotal = 0
            _curFrameTime = now
        end
        local d = _profData[label]
        if not d then d = { n = 0, total = 0 }; _profData[label] = d end
        d.n = d.n + 1
        d.total = d.total + elapsed
        _curFrameLabels[label] = (_curFrameLabels[label] or 0) + elapsed
        _curFrameTotal = _curFrameTotal + elapsed
    end

    local profFrame = CreateFrame("Frame")
    profFrame:Hide()
    profFrame:SetScript("OnUpdate", function()
        if not _profActive then profFrame:Hide(); return end
        if not C_AddOnProfiler or not C_AddOnProfiler.GetAddOnMetric then return end
        local addonMs = C_AddOnProfiler.GetAddOnMetric(
            _addonName, Enum.AddOnProfilerMetric.LastTime) or 0
        _frameCount = _frameCount + 1
        _totalAddonMs = _totalAddonMs + addonMs
        if addonMs > _peakAddonMs then _peakAddonMs = addonMs end
    end)

    local function ResetProf()
        wipe(_profData); wipe(_curFrameLabels); wipe(_peakFrameLabels)
        _frameCount = 0; _totalAddonMs = 0; _peakAddonMs = 0
        _peakFrameTotal = 0; _curFrameTotal = 0; _curFrameTime = 0; _startTime = 0
    end

    SLASH_ERFPROF1 = "/erfprof"
    SlashCmdList["ERFPROF"] = function(msg)
        if msg == "reset" then
            ResetProf()
            print("|cff00ccffERFProf:|r data cleared")
            return
        end
        _profActive = not _profActive
        if _profActive then
            ResetProf()
            _startTime = GetTime()
            profFrame:Show()
            print("|cff00ccffERFProf:|r ON -- type /erfprof again to stop")
        else
            profFrame:Hide()
            if _curFrameTotal > _peakFrameTotal then
                _peakFrameTotal = _curFrameTotal
                wipe(_peakFrameLabels)
                for k, v in pairs(_curFrameLabels) do _peakFrameLabels[k] = v end
            end
            local dur = GetTime() - _startTime
            local avgAddon = _frameCount > 0
                and (_totalAddonMs / _frameCount) or 0
            print("|cff00ccffERFProf Report:|r  "
                .. _frameCount .. " frames, " .. format("%.1f", dur) .. "s")
            print(format("  |cff00ccffAddon Peak:|r  %.3f ms   |cff00ccffAvg:|r %.3f ms", _peakAddonMs, avgAddon))
            local scale = (_peakFrameTotal > 0) and (_peakAddonMs / _peakFrameTotal) or 1
            local sorted = {}
            for label, ms in pairs(_peakFrameLabels) do
                local scaled = ms * scale
                local d = _profData[label]
                local avg = (d and _frameCount > 0) and (d.total / _frameCount) or 0
                sorted[#sorted + 1] = { label = label, peak = scaled, avg = avg }
            end
            table.sort(sorted, function(a, b) return a.avg > b.avg end)
            print(format("  %-30s %10s %10s", "Label", "avg ms", "peak ms"))
            for _, e in ipairs(sorted) do
                print(format("  %-30s %10.3f %10.3f", e.label, e.avg, e.peak))
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Locals & upvalues
-------------------------------------------------------------------------------
local PP           = nil  -- set in OnEnable once parent is ready
local db           = nil
local floor        = math.floor
local max          = math.max
local min          = math.min
local abs          = math.abs
local pairs        = pairs
local ipairs       = ipairs
local wipe         = wipe
local type         = type
local tostring     = tostring
local select       = select
local unpack       = unpack
local tinsert      = table.insert

local UnitHealth            = UnitHealth
local UnitHealthMax         = UnitHealthMax
local UnitPower             = UnitPower
local UnitPowerMax          = UnitPowerMax
local UnitPowerType         = UnitPowerType
local UnitName              = UnitName
local UnitClass             = UnitClass
local UnitExists            = UnitExists
local UnitIsConnected       = UnitIsConnected
local UnitIsVisible         = UnitIsVisible
local UnitIsDeadOrGhost     = UnitIsDeadOrGhost
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitThreatSituation   = UnitThreatSituation
local UnitIsUnit            = UnitIsUnit
local UnitInRange           = UnitInRange
local UnitGetTotalAbsorbs   = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local GetReadyCheckStatus   = GetReadyCheckStatus
local GetRaidTargetIndex    = GetRaidTargetIndex
local IsInRaid              = IsInRaid
local IsInGroup             = IsInGroup
local InCombatLockdown      = InCombatLockdown
local GetNumGroupMembers    = GetNumGroupMembers
local C_Timer               = C_Timer
local issecretvalue         = issecretvalue
local CreateFrame           = CreateFrame
local RAID_CLASS_COLORS     = RAID_CLASS_COLORS

-- Private aura container API (12.0.5+)
local C_UnitAuras_AddPrivateAuraAnchor    = C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor
local C_UnitAuras_RemovePrivateAuraAnchor = C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor

-- Strata bump for private aura container frames (workaround for 12.0.5
-- bug where container icons render behind the parent frame)
local PA_STRATA_FIX = {
    BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG",
}

-- Absorb shield textures (must match UnitFrames exactly)
local ABSORB_STYLE_TEX = {
    striped  = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-5.png",
    clean    = "Interface\\Buttons\\WHITE8X8",
    blizzard = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\blizzard.tga",
}
local ABSORB_STYLE_ALPHA = {
    striped  = 0.8,
    clean    = 0.3,
    blizzard = 0.8,
}

-- Role icon definitions per style
-- _isTexture = true means the values are file paths (use SetTexture),
-- otherwise they are atlas names (use SetAtlas).
local ROLE_MEDIA = "Interface\\AddOns\\EllesmereUIRaidFrames\\Media\\"
local ROLE_ICON_STYLES = {
    modern = {
        _isTexture = true,
        TANK    = ROLE_MEDIA .. "tank-modern.png",
        HEALER  = ROLE_MEDIA .. "healer-modern.png",
        DAMAGER = ROLE_MEDIA .. "dps-modern.png",
    },
    modernCircle = {
        TANK    = "UI-LFG-RoleIcon-Tank",
        HEALER  = "UI-LFG-RoleIcon-Healer",
        DAMAGER = "UI-LFG-RoleIcon-DPS",
    },
    styled = {
        TANK    = "UI-LFG-RoleIcon-Tank-Background",
        HEALER  = "UI-LFG-RoleIcon-Healer-Background",
        DAMAGER = "UI-LFG-RoleIcon-DPS-Background",
    },
    classicCircle = {
        TANK    = "UI-LFG-RoleIcon-Tank-Micro-GroupFinder",
        HEALER  = "UI-LFG-RoleIcon-Healer-Micro-GroupFinder",
        DAMAGER = "UI-LFG-RoleIcon-DPS-Micro-GroupFinder",
    },
    classic = {
        TANK    = "roleicon-tiny-tank",
        HEALER  = "roleicon-tiny-healer",
        DAMAGER = "roleicon-tiny-dps",
    },
    blizzDefault = {
        TANK    = "GM-icon-role-tank",
        HEALER  = "GM-icon-role-healer",
        DAMAGER = "GM-icon-role-dps",
    },
}

local function ApplyRoleIcon(texture, role, style)
    -- style is supplied by the caller from its own settings context (the party
    -- proxy / preview override), so party frames honor their unsynced
    -- roleIconStyle. Fall back to the raid profile only if a caller omits it.
    style = style or (db and db.profile.roleIconStyle) or "modern"
    local map = ROLE_ICON_STYLES[style]
    if not map then return false end
    local icon = map[role]
    if not icon then return false end
    if map._isTexture then
        texture:SetTexture(icon)
        texture:SetTexCoord(0, 1, 0, 1)
    else
        texture:SetAtlas(icon)
    end
    return true
end

-- Raid marker textures
local RAID_MARKER_TEXCOORDS = {
    [1] = { 0,    0.25, 0,    0.25 },  -- Star
    [2] = { 0.25, 0.5,  0,    0.25 },  -- Circle
    [3] = { 0.5,  0.75, 0,    0.25 },  -- Diamond
    [4] = { 0.75, 1,    0,    0.25 },  -- Triangle
    [5] = { 0,    0.25, 0.25, 0.5  },  -- Moon
    [6] = { 0.25, 0.5,  0.25, 0.5  },  -- Square
    [7] = { 0.5,  0.75, 0.25, 0.5  },  -- Cross
    [8] = { 0.75, 1,    0.25, 0.5  },  -- Skull
}

-- Dispel colors
local DISPEL_COLORS = {
    Magic   = { r = 0.349, g = 0.475, b = 1.0 },
    Curse   = { r = 0.636, g = 0.0,   b = 0.64 },
    Disease = { r = 0.671, g = 0.384, b = 0.098 },
    Poison  = { r = 0.0,   g = 0.706, b = 0.286 },
    [""]    = { r = 0.75,  g = 0.15,  b = 0.15 },  -- Bleed / physical (no dispelName)
}

-- Dispel type icon atlases
local DISPEL_ICON_ATLAS = {
    Magic   = "RaidFrame-Icon-DebuffMagic",
    Curse   = "RaidFrame-Icon-DebuffCurse",
    Disease = "RaidFrame-Icon-DebuffDisease",
    Poison  = "RaidFrame-Icon-DebuffPoison",
    [""]    = "RaidFrame-Icon-DebuffBleed",
}

-- Rez spells by class (for dead target range checking)
-- IsSpellInRange returns normal booleans, not secret values.
local REZ_SPELL_BY_CLASS = {
    DRUID       = 20484,   -- Rebirth
    PRIEST      = 2006,    -- Resurrection
    PALADIN     = 461622,  -- Intercession
    SHAMAN      = 2008,    -- Ancestral Spirit
    MONK        = 115178,  -- Resuscitate
    DEATHKNIGHT = 61999,   -- Raise Ally
    WARLOCK     = 20707,   -- Soulstone
    EVOKER      = 361227,  -- Return
}
local _, playerClassToken = UnitClass("player")
local playerRezSpell = REZ_SPELL_BY_CLASS[playerClassToken]

-- Classes that use IsSpellInRange instead of UnitInRange for living units.
-- These classes have shorter effective ranges that 43yd UnitInRange misrepresents.
local FRIENDLY_SPELL_BY_CLASS = {
    EVOKER = 361469,  -- Living Flame (baseline all specs, unit-targeted friendly -> IsSpellInRange returns a real boolean; ~25yd, 30 talented). Emerald Blossom (355913) is a location/smart-heal whose IsSpellInRange can stay nil, which stranded Evoker frames at full alpha.
    ROGUE  = 36554,   -- Shadowstep (25yd)
}
local playerFriendlySpell = FRIENDLY_SPELL_BY_CLASS[playerClassToken]

-- Threat: only show for active aggro (states 2 and 3).
-- Rendered as a white border matching the hover highlight style.
local THREAT_ACTIVE = { [2] = true, [3] = true }

-------------------------------------------------------------------------------
--  Default settings
-------------------------------------------------------------------------------
local defaults = {
    profile = {
        -- Size & layout
        frameWidth       = 125,
        frameHeight      = 60,
        cellSpacing      = -1,
        groupSpacing     = -1,
        groupGrowth      = "RIGHT",  -- "DOWN", "UP", "RIGHT", "LEFT"
        unitGrowth       = "DOWN",   -- perpendicular to groupGrowth
        sortMode         = "ROLE",   -- "INDEX" (by group) or "ROLE" (by assigned role)
        roleOrder        = { "TANK", "HEALER", "DAMAGER" },
        showSelfFirst    = true,
        showSelfLast     = false,
        mergeGroups      = false,
        visibleGroups    = { true, true, true, true, true, true, false, false },

        -- Visibility
        showWhenSolo     = false,
        showWhenGroup    = false,
        showWhenRaid     = true,

        -- Position (saved by unlock mode)
        unlockPos        = nil,

        -- Health bar
        healthBarTexture = "atrocity",
        healthBarOpacity = 100,
        healthColorMode  = "class",  -- "class", "dark", "classic", "custom"
        customFillColor  = { r = 37/255, g = 193/255, b = 29/255 },
        customBgColor    = { r = 17/255, g = 17/255, b = 17/255 },
        bgDarkness       = 50,

        -- Power bar (on when any powerShowFor* role is true)
        showPowerBar     = true,
        powerHeight      = 4,
        powerBgDarkness  = 40,
        powerBgColor     = { r = 107/255, g = 107/255, b = 107/255 },
        powerBorderStyle = "eui",      -- "eui", "divider", "border"
        powerBorderSize  = 1,
        powerBorderColor = { r = 0, g = 0, b = 0 },
        powerBorderAlpha = 1,
        powerShowForHealer = true,
        powerShowForTank   = true,
        powerShowForDPS    = false,

        -- Text
        nameSize         = 10,
        nameColorMode    = "custom",  -- "class", "accent", "custom"
        nameCustomColor  = { r = 1, g = 1, b = 1 },
        namePosition     = "topleft", -- "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom"
        nameOffsetX      = 0,
        nameOffsetY      = 0,
        healthTextMode   = "none",   -- "none", "percent", "number"
        healthTextColorMode   = "custom",  -- "class", "accent", "custom"
        healthTextCustomColor = { r = 1, g = 1, b = 1 },
        healthTextSize   = 9,
        healthTextPosition = "center",
        healthTextOffsetX  = 0,
        healthTextOffsetY  = 0,

        -- Border (unified style/size, recolored by state -- matches Unit Frames)
        borderSize       = 1,
        borderColor      = { r = 0, g = 0, b = 0 },
        borderAlpha      = 1,
        borderTexture    = "solid",
        borderBehind     = false,
        -- borderTextureOffset/OffsetY/ShiftX/ShiftY default via GetBorderDefaults

        -- Smooth bars
        smoothBars       = true,
        smoothPowerBars  = true,

        -- Absorb shields (must match UF options)
        absorbStyle      = "striped",   -- "none", "striped", "clean", "blizzard"
        absorbOpacity    = 90,
        absorbColor      = { r = 1, g = 1, b = 1 },
        healAbsorbStyle  = "clean",
        healAbsorbOpacity = 75,
        healAbsorbColor  = { r = 0.8, g = 0.15, b = 0.15 },
        healPrediction   = false,
        healPredOpacity  = 75,
        healPredColor    = { r = 102/255, g = 243/255, b = 102/255 },
        absorbFromRightEdge = false,

        -- Indicators
        roleIconStyle    = "modern",  -- "none", "modern", "modernCircle", "styled", "classicCircle", "classic"
        roleIconSize     = 13,
        roleIconPosition = "bottomleft",  -- "topleft", "topright", "bottomleft", "bottomright"
        roleIconOffsetX  = 0,
        roleIconOffsetY  = 0,
        showRoleForTank    = true,
        showRoleForHealer  = true,
        showRoleForDPS     = false,
        showRaidMarker   = true,
        raidMarkerSize   = 16,
        raidMarkerPosition = "center",  -- "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom"
        raidMarkerOffsetX  = 0,
        raidMarkerOffsetY  = 0,
        showReadyCheck   = true,
        showSummonPending = true,
        threatBorderSize = 2,    -- aggro warning border thickness; 0 = off
        showLeaderIcon   = false,
        leaderIconPosition = "top",
        leaderIconSize   = 14,
        leaderIconOffsetX  = 0,
        leaderIconOffsetY  = 0,
        statusTextPosition = "center",
        statusTextOffsetX  = 0,
        statusTextOffsetY  = 0,
        statusTextSize     = 12,
        statusTextColor    = { r = 1, g = 1, b = 1 },
        statusShowAFK      = false,
        -- Group numbers (raid only). Size + color shared with the preview; the
        -- toggle gates only the real frames (preview always shows numbers).
        showGroupNumbers   = false,
        groupNumberSize    = 10,
        groupNumberColor   = { r = 1, g = 1, b = 1, a = 0.75 },
        groupNumberOffsetX = 0,
        groupNumberOffsetY = 0,
        hoverBorderEnabled = true,
        hoverBorderSize  = 1,
        hoverBorderColor = { r = 1, g = 1, b = 1 },
        hoverBorderAlpha = 1,
        targetBorderEnabled = true,
        targetBorderSize = 1,
        targetBorderColor = { r = 1, g = 1, b = 1 },
        targetBorderAlpha = 1,

        -- Dispels
        dispelBorderSize = 0,
        dispelOverlay    = "fill",   -- "none", "fill", "full", "gradient"
        dispelOverlayOpacity = 100,
        dispelShowAll        = true,   -- true = highlight any dispellable debuff; false = only player-dispellable
        showDispelIcons  = false,
        dispelIconSize     = 16,
        dispelIconPosition = "right",
        dispelIconOffsetX  = 0,
        dispelIconOffsetY  = 0,
        -- Per-dispel-type colors (defaults mirror DISPEL_COLORS). "Bleed" is the
        -- no-dispelName/physical type (stored under the "" key in DISPEL_COLORS).
        dispelColorMagic   = { r = 0.349, g = 0.475, b = 1.0 },
        dispelColorCurse   = { r = 0.636, g = 0.0,   b = 0.64 },
        dispelColorDisease = { r = 0.671, g = 0.384, b = 0.098 },
        dispelColorPoison  = { r = 0.0,   g = 0.706, b = 0.286 },
        dispelColorBleed   = { r = 0.75,  g = 0.15,  b = 0.15 },

        -- Buff Manager (indicator-centric model)
        bmIndicators      = {},  -- { [specKey] = { indicator1, indicator2, ... } }

        -- Private Auras (Blizzard-rendered boss debuff icons)
        paSize           = 20,
        paShowCountdown  = false,
        paPosition       = "center",
        paOffsetX        = 0,
        paOffsetY        = 0,
        paGrowDirection  = "RIGHT",
        paSpacing        = 0,

        -- Debuffs
        debuffFilter     = "all",  -- "none", "all", "raid", "dispellable"
        hideLustDebuff   = true,
        -- Defensives & Externals
        showDefensives   = true,
        showExternals    = true,
        defPosition      = "center",
        defOffsetX       = 0,
        defOffsetY       = 0,
        defGrowDirection = "CENTER",
        defSize          = 22,
        defBorderSize    = 1,
        defBorderColor   = { r = 0, g = 0, b = 0 },
        defSpacing       = 1,
        defShowSwipe     = true,
        defShowDurText   = false,
        defDurTextColor  = { r = 1, g = 1, b = 1 },
        defDurTextSize   = 8,
        defDurTextOffsetX = 0,
        defDurTextOffsetY = 0,

        -- Buff Manager "Simple Setup" mode. Fully isolated namespace: shares no
        -- keys with the custom indicator system (bmIndicators) or the def*
        -- defensives. Mirrors the Defensives & Externals controls but drives the
        -- simple buff grid (all of the active spec's tracked buffs, in a grid).
        bmSimple = {
            showBuffs       = true,
            maxBuffs        = 8,
            iconsPerRow     = 4,
            position        = "topright",
            offsetX         = 0,
            offsetY         = 0,
            growDirection   = "LEFT",   -- sensible default for the Top Right anchor
            size            = 18,
            spacing         = 1,
            borderSize      = 1,
            borderColor     = { r = 0, g = 0, b = 0 },
            showSwipe       = true,
            showDurText     = false,
            durTextColor    = { r = 1, g = 1, b = 1 },
            durTextSize     = 8,
            durTextOffsetX  = 0,
            durTextOffsetY  = 0,
        },

        debuffSize       = 18,
        debuffCap        = 3,
        debuffPosition   = "bottomright",
        debuffOffsetX    = 0,
        debuffOffsetY    = 0,
        debuffGrowDirection = "LEFT",
        debuffSpacing    = 1,
        debuffBorderSize = 1,
        debuffBorderColor = { r = 0, g = 0, b = 0 },
        debuffShowStacks = true,
        debuffStacksTextColor = { r = 1, g = 1, b = 1 },
        debuffStacksTextSize = 8,
        debuffStacksOffsetX = 0,
        debuffStacksOffsetY = 0,
        debuffShowSwipe  = true,
        debuffShowDurText = false,
        debuffDurTextColor = { r = 1, g = 1, b = 1 },
        debuffDurTextSize = 8,
        debuffDurTextOffsetX = 0,
        debuffDurTextOffsetY = 0,

        -- Range & misc
        oorAlpha         = 0.4,
        showTooltip      = true,
        tooltipInCombat  = false,

        -- Preview mode: "real", "overlay", "none"
        previewMode       = "overlay",

        -- Raid size overrides: { [10] = { width=X, height=Y }, ... }
        raidSizeOverrides = nil,
        autoResizeIndicators = false,

        -- Party frame overrides (sparse -- falls back to raid settings)
        partyFrameWidth   = 125,
        partyFrameHeight  = 60,
        partyShowWhenSolo = false,
        partyCenterWhenSolo = false,  -- center the lone player frame in the container when solo
        partySyncSections = nil,  -- nil = all synced; { healthBar=false } = healthBar custom
        partySortMode     = "ROLE",
        partyShowSelfFirst = true,
        partySelfLast      = false,
        partyHorizontal   = false,
        partyHideSelf     = false,
        partyUnlockPos    = nil,
    }
}

-------------------------------------------------------------------------------
--  State tables
-------------------------------------------------------------------------------
local allButtons     = {}   -- flat list of all created buttons
local unitToButton   = {}   -- unitToken -> button map (rebuilt on roster change)
local separatedHdrs  = {}   -- [1..8] group headers
local containerFrame = nil  -- top-level positioning frame
ns._flatButtons      = {}   -- buttons owned by the flat (merged) header
ns._flatHeader       = nil  -- single header for merge-groups mode
local eventFrame     = CreateFrame("Frame")
local unitTrackers   = {}  -- [unitToken] = tracker frame
local inCombat       = false

-------------------------------------------------------------------------------
--  Suppress Blizzard raid frames (zero CPU when our frames are active)
--  Only raid container/manager suppressed unconditionally at file scope.
--  Party frame suppression is conditional, applied in UpdateVisibility.
-------------------------------------------------------------------------------
ns._blizzHiddenParent = CreateFrame("Frame", nil, UIParent)
ns._blizzHiddenParent:SetAllPoints()
ns._blizzHiddenParent:Hide()

do
    local hookedFrames = {}
    local looseFrames = {}

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:SetScript("OnEvent", function()
        for frame in next, looseFrames do
            frame:SetParent(ns._blizzHiddenParent)
        end
        wipe(looseFrames)
    end)

    local function resetParent(self, parent)
        if parent ~= ns._blizzHiddenParent then
            if InCombatLockdown() and self:IsProtected() then
                looseFrames[self] = true
            else
                self:SetParent(ns._blizzHiddenParent)
            end
        end
    end

    local function handleFrame(frame, doNotReparent)
        if not frame then return end
        frame:UnregisterAllEvents()
        frame:Hide()
        if not doNotReparent then
            frame:SetParent(ns._blizzHiddenParent)
            if not hookedFrames[frame] then
                hooksecurefunc(frame, "SetParent", resetParent)
                hookedFrames[frame] = true
            end
        end
        local health = frame.healthBar or frame.healthbar or frame.HealthBar
            or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar)
        if health then health:UnregisterAllEvents() end
        local power = frame.manabar or frame.ManaBar
        if power then power:UnregisterAllEvents() end
        local castbar = frame.castBar or frame.spellbar or frame.CastingBarFrame
        if castbar then castbar:UnregisterAllEvents() end
        local altpower = frame.powerBarAlt or frame.PowerBarAlt
        if altpower then altpower:UnregisterAllEvents() end
        local buffs = frame.BuffFrame or frame.AurasFrame
        if buffs then buffs:UnregisterAllEvents() end
        local debuffs = frame.DebuffFrame
        if debuffs then debuffs:UnregisterAllEvents() end
    end

    -- Suppress the Blizzard Edit Mode selection overlay (the dashed, labelled
    -- "Raid Frames" / "Party Frames" mover box). Hiding or reparenting the
    -- system frame is NOT enough: Blizzard Edit Mode force-shows its registered
    -- systems, so the selection box still appears. Scale the system frame down so its
    -- Selection child renders invisibly small, plus alpha 0. SetScale is blocked
    -- in combat, but Edit Mode is always entered out of combat, so we just skip
    -- the scale when locked. pcall-wrapped -- these are protected Blizzard frames.
    local function suppressEditModeOverlay(frame)
        if not frame then return end
        pcall(function()
            frame:SetAlpha(0)
            if not InCombatLockdown() then
                frame:SetScale(0.001)
            end
            -- Per-frame Blizzard selection textures. No-op if absent.
            if frame.selectionHighlight and frame.selectionHighlight.SetShown then
                frame.selectionHighlight:SetShown(false)
            end
            if frame.selectionIndicator and frame.selectionIndicator.SetShown then
                frame.selectionIndicator:SetShown(false)
            end
        end)
    end

    -- Raid frame CONTAINER (the unit health bars) is always suppressed -- EUI
    -- replaces the raid unit frames. The MANAGER (the left sidebar panel with
    -- ready check / markers) is intentionally NOT touched here: it is controlled
    -- by the shared "Hide Blizzard Party Panel" toggle
    -- (EllesmereUI_BlizzardParty.lua), so it can be shown when the user wants the
    -- Blizzard leader tools. Re-assert the Edit Mode scale-down in OnShow because
    -- Edit Mode re-shows the system (and may reset its scale) every time it is
    -- entered.
    if CompactRaidFrameContainer then
        handleFrame(CompactRaidFrameContainer)
        CompactRaidFrameContainer:HookScript("OnShow", function(self)
            self:Hide()
            suppressEditModeOverlay(self)
        end)
    end

    -- Callable from UpdateVisibility when "Show When: In a Group" is active
    ns._SuppressBlizzParty = function()
        if ns._blizzPartySuppressed then return end
        ns._blizzPartySuppressed = true
        if PartyFrame then
            handleFrame(PartyFrame)
            if PartyFrame.PartyMemberFramePool then
                for mf in PartyFrame.PartyMemberFramePool:EnumerateActive() do
                    handleFrame(mf, true)
                end
            end
            local MEMBERS_PER_GROUP = _G.MEMBERS_PER_RAID_GROUP or 5
            for i = 1, MEMBERS_PER_GROUP do
                handleFrame(_G["CompactPartyFrameMember" .. i])
            end
            -- Hide the party Edit Mode selection overlay. This runs only while
            -- EUI owns the party frames (called from UpdateVisibility), so
            -- Blizzard party frames left in place for non-EUI users keep their
            -- Edit Mode movers. PartyFrame is the standard party system;
            -- CompactPartyFrame covers raid-style party (guarded if absent).
            suppressEditModeOverlay(PartyFrame)
            suppressEditModeOverlay(_G["CompactPartyFrame"])
        end
    end

    -- Edit Mode overlay timing: Edit Mode re-shows its registered systems (and
    -- can reset their scale) every time it is entered, so a one-time call at
    -- load is not enough. Re-apply the scale-down on PLAYER_ENTERING_WORLD,
    -- EDIT_MODE_LAYOUTS_UPDATED, the EditModeManagerFrame show/hide, and the
    -- CompactRaidFrameManager_UpdateShown global.
    local function applyEditModeOverlaySuppression()
        -- Manager omitted on purpose -- the shared "Hide Blizzard Party Panel"
        -- toggle owns the manager's visibility, so it may be shown.
        suppressEditModeOverlay(CompactRaidFrameContainer)
        -- Party overlays suppressed unconditionally, same as raid. Blizzard's
        -- party frame is empty/hidden when solo, so the scale-down only ever
        -- matters for the Edit Mode mover box -- no need to gate on whether we
        -- are currently in a group.
        suppressEditModeOverlay(PartyFrame)
        suppressEditModeOverlay(_G["CompactPartyFrame"])
    end
    ns._ApplyEditModeOverlaySuppression = applyEditModeOverlaySuppression

    local editModeWatcher = CreateFrame("Frame")
    editModeWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    editModeWatcher:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    editModeWatcher:SetScript("OnEvent", function()
        C_Timer.After(0, applyEditModeOverlaySuppression)
    end)

    -- Edit Mode and the raid manager re-show the container through this global;
    -- re-assert our suppression whenever it fires.
    if type(_G.CompactRaidFrameManager_UpdateShown) == "function" then
        hooksecurefunc("CompactRaidFrameManager_UpdateShown", function()
            C_Timer.After(0, applyEditModeOverlaySuppression)
        end)
    end

    local function hookEditModeManager()
        if not EditModeManagerFrame then return end
        local fd = EllesmereUI._GetFFD(EditModeManagerFrame)
        if fd.rfOverlayHooked then return end
        fd.rfOverlayHooked = true
        -- OnShow = Edit Mode entered (overlay appears); Hide = Edit Mode closed.
        EditModeManagerFrame:HookScript("OnShow", function()
            C_Timer.After(0, applyEditModeOverlaySuppression)
        end)
        hooksecurefunc(EditModeManagerFrame, "Hide", function()
            C_Timer.After(0, applyEditModeOverlaySuppression)
        end)
    end
    if EditModeManagerFrame then
        hookEditModeManager()
    elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", hookEditModeManager)
    end
end

-- FFD: external weak-keyed lookup for state on header-managed buttons
-- (SecureGroupHeader buttons are Blizzard-owned, never write custom keys)
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

-------------------------------------------------------------------------------
--  Physical pixel snapping
--  PP.Scale uses PanelPP.mult which can be 1 even when the frame's effective
--  scale differs from 1.0. This helper snaps to the container's actual
--  physical pixel grid using EllesmereUI.PP.perfect (the real PP, not PanelPP).
-------------------------------------------------------------------------------
local function PixelSnap(value)
    if value == 0 then return 0 end
    local realPP = EllesmereUI and EllesmereUI.PP
    local perfect = realPP and realPP.perfect
    if not perfect then return value end
    local es = containerFrame and containerFrame:GetEffectiveScale() or (UIParent and UIParent:GetEffectiveScale() or 1)
    local onePixel = perfect / es
    return floor(value / onePixel + 0.5) * onePixel
end

-------------------------------------------------------------------------------
--  Font helper (matches UF/CDM pattern)
-------------------------------------------------------------------------------
local function GetOutline()
    return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or ""
end
local function GetUseShadow()
    return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow()
end
local function ApplyFont(fs, size)
    if not (fs and fs.SetFont) then return end
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
    local outline = GetOutline()
    fs:SetFont(fontPath, size, outline)
    if outline == "" and GetUseShadow() then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-------------------------------------------------------------------------------
--  Health bar texture helpers
-------------------------------------------------------------------------------
local healthBarTextures     = {}
local healthBarTextureNames = {}
local healthBarTextureOrder = {}

local function InitHealthBarTextures()
    local TEX_BASE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
    -- Built-in textures (matches DM/UF texture set)
    healthBarTextures["none"]             = "Interface\\Buttons\\WHITE8X8"
    healthBarTextures["melli"]            = TEX_BASE .. "melli.tga"
    healthBarTextures["atrocity"]         = TEX_BASE .. "atrocity.tga"
    healthBarTextures["beautiful"]        = TEX_BASE .. "beautiful.tga"
    healthBarTextures["plating"]          = TEX_BASE .. "plating.tga"
    healthBarTextures["divide"]           = TEX_BASE .. "divide.tga"
    healthBarTextures["glass"]            = TEX_BASE .. "glass.tga"
    healthBarTextures["fade"]             = TEX_BASE .. "fade.tga"
    healthBarTextures["fade-right"]       = TEX_BASE .. "fade-right.tga"
    healthBarTextures["thin-line-top"]    = TEX_BASE .. "thin-line-top.tga"
    healthBarTextures["thin-line-bottom"] = TEX_BASE .. "thin-line-bottom.tga"
    healthBarTextures["gradient-lr"]      = TEX_BASE .. "gradient-lr.tga"
    healthBarTextures["gradient-rl"]      = TEX_BASE .. "gradient-rl.tga"
    healthBarTextures["gradient-bt"]      = TEX_BASE .. "gradient-bt.tga"
    healthBarTextures["gradient-tb"]      = TEX_BASE .. "gradient-tb.tga"
    healthBarTextures["matte"]            = TEX_BASE .. "matte.tga"
    healthBarTextures["sheer"]            = TEX_BASE .. "sheer.tga"

    healthBarTextureNames["none"]             = "None"
    healthBarTextureNames["melli"]            = "Melli"
    healthBarTextureNames["atrocity"]         = "Atrocity"
    healthBarTextureNames["beautiful"]        = "Beautiful"
    healthBarTextureNames["plating"]          = "Plating"
    healthBarTextureNames["divide"]           = "Divide"
    healthBarTextureNames["glass"]            = "Glass"
    healthBarTextureNames["fade"]             = "Fade"
    healthBarTextureNames["fade-right"]       = "Fade Right"
    healthBarTextureNames["thin-line-top"]    = "Thin Line Top"
    healthBarTextureNames["thin-line-bottom"] = "Thin Line Bottom"
    healthBarTextureNames["gradient-lr"]      = "Gradient Right"
    healthBarTextureNames["gradient-rl"]      = "Gradient Left"
    healthBarTextureNames["gradient-bt"]      = "Gradient Up"
    healthBarTextureNames["gradient-tb"]      = "Gradient Down"
    healthBarTextureNames["matte"]            = "Matte"
    healthBarTextureNames["sheer"]            = "Sheer"

    healthBarTextureOrder[1]  = "none"
    healthBarTextureOrder[2]  = "melli"
    healthBarTextureOrder[3]  = "atrocity"
    healthBarTextureOrder[4]  = "fade"
    healthBarTextureOrder[5]  = "fade-right"
    healthBarTextureOrder[6]  = "thin-line-top"
    healthBarTextureOrder[7]  = "thin-line-bottom"
    healthBarTextureOrder[8]  = "beautiful"
    healthBarTextureOrder[9]  = "plating"
    healthBarTextureOrder[10] = "divide"
    healthBarTextureOrder[11] = "glass"
    healthBarTextureOrder[12] = "gradient-lr"
    healthBarTextureOrder[13] = "gradient-rl"
    healthBarTextureOrder[14] = "gradient-bt"
    healthBarTextureOrder[15] = "gradient-tb"
    healthBarTextureOrder[16] = "matte"
    healthBarTextureOrder[17] = "sheer"

    -- Append SharedMedia textures after built-ins
    if EllesmereUI.AppendSharedMediaTextures then
        EllesmereUI.AppendSharedMediaTextures(
            healthBarTextureNames,
            healthBarTextureOrder,
            nil,
            healthBarTextures
        )
    end
end

local function ResolveHealthTexture()
    local key = db.profile.healthBarTexture or "atrocity"
    return EllesmereUI.ResolveTexturePath(healthBarTextures, key, healthBarTextures["atrocity"] or "Interface\\Buttons\\WHITE8X8")
end

-- Expose for options panel
ns.healthBarTextures     = healthBarTextures
ns.healthBarTextureNames = healthBarTextureNames
ns.healthBarTextureOrder = healthBarTextureOrder

-------------------------------------------------------------------------------
--  Power bar visibility (derived from role flags)
-------------------------------------------------------------------------------
local function IsPowerBarEnabled(s)
    return s.powerShowForHealer or s.powerShowForTank or s.powerShowForDPS
end

-- Resolve a unit's role for POWER-BAR gating. UnitGroupRolesAssigned returns
-- "NONE" for the player when SOLO (no group role is assigned outside a group);
-- that would fall through to the DPS toggle and wrongly hide a solo healer's
-- mana bar. For the player, fall back to the spec's role so a solo Resto Druid
-- resolves to HEALER (a Blood DK to TANK, etc). Only the player is resolved this
-- way -- arbitrary group units have no reliable spec role, and in a real group
-- Blizzard assigns roles so "NONE" does not occur there.
ns._ResolvePowerRole = function(unit)
    local role = UnitGroupRolesAssigned(unit)
    if role == "NONE" and UnitIsUnit(unit, "player") then
        local spec = GetSpecialization and GetSpecialization()
        local specRole = spec and GetSpecializationRole and GetSpecializationRole(spec)
        if specRole then return specRole end
    end
    return role
end

-------------------------------------------------------------------------------
--  Raid size tier resolution
--  Returns width, height for the given group size based on defined overrides.
--  Cascades toward 20 man (the base) when a tier is not defined.
--  Tiers: 10, 15, 20(base), 25, 30
-------------------------------------------------------------------------------
ns._GetRaidSizeFrameDimensions = function(groupSize)
    local s = db.profile
    local baseW = s.frameWidth or 125
    local baseH = s.frameHeight or 60
    local overrides = s.raidSizeOverrides
    if not overrides or not next(overrides) then return baseW, baseH end

    -- Determine which tier this group size falls into
    local tier
    if groupSize <= 10 then     tier = 10
    elseif groupSize <= 15 then tier = 15
    elseif groupSize <= 20 then tier = 20
    elseif groupSize <= 25 then tier = 25
    else                        tier = 30
    end

    if tier == 20 then return baseW, baseH end

    -- Cascade toward 20: check exact tier, then move toward 20
    if tier < 20 then
        -- Below 20: check tier, then check next tier up, then 20
        if tier == 10 then
            if overrides[10] then return overrides[10].width, overrides[10].height end
            if overrides[15] then return overrides[15].width, overrides[15].height end
        elseif tier == 15 then
            if overrides[15] then return overrides[15].width, overrides[15].height end
        end
    else
        -- Above 20: check tier, then check next tier down, then 20
        if tier == 30 then
            if overrides[30] then return overrides[30].width, overrides[30].height end
            if overrides[25] then return overrides[25].width, overrides[25].height end
        elseif tier == 25 then
            if overrides[25] then return overrides[25].width, overrides[25].height end
        end
    end

    return baseW, baseH
end

-- Track current active tier so we know when to re-layout
ns._currentSizeTier = 20

-------------------------------------------------------------------------------
--  Color helpers
-------------------------------------------------------------------------------
-- Safe health percent: returns 0-100, no secret value arithmetic
local function GetSafeHealthPercent(unit)
    return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
end

-- Classic health color curve: red (dead) -> yellow (mid) -> green (full)
-- Built once via C_CurveUtil, passed to UnitHealthPercent which handles
-- secret values internally and returns a clean ColorMixin.
local classicHealthCurve
local function GetClassicHealthCurve()
    if classicHealthCurve then return classicHealthCurve end
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Linear)
    curve:AddPoint(0, CreateColor(1, 0, 0, 1))     -- red at 0%
    curve:AddPoint(0.5, CreateColor(1, 1, 0, 1))   -- yellow at 50%
    curve:AddPoint(1, CreateColor(0, 1, 0, 1))     -- green at 100%
    classicHealthCurve = curve
    return curve
end

-- Dark mode colors (must match UnitFrames exactly)
local DARK_FILL_R, DARK_FILL_G, DARK_FILL_B = 0x11/255, 0x11/255, 0x11/255  -- #111111
local DARK_FILL_A = 0.9
local DARK_BG_R, DARK_BG_G, DARK_BG_B = 0x4f/255, 0x4f/255, 0x4f/255        -- #4f4f4f

local function GetHealthColor(unit, s)
    s = s or db.profile
    local mode = s.healthColorMode or "class"

    if mode == "dark" then
        return DARK_FILL_R, DARK_FILL_G, DARK_FILL_B
    elseif mode == "classic" then
        -- Native WoW health gradient via Blizzard's curve system (secret-value safe)
        local color = UnitHealthPercent(unit, true, GetClassicHealthCurve())
        if color and color.GetRGB then
            return color:GetRGB()
        end
        return 0, 1, 0
    elseif mode == "custom" then
        local c = s.customFillColor
        return c.r, c.g, c.b
    else -- "class"
        local _, classToken = UnitClass(unit)
        -- Secret-safe: a secret classToken would throw on GetClassColor's table index.
        if classToken and not issecretvalue(classToken) then
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then return cc.r, cc.g, cc.b end
        end
        return 0.5, 0.5, 0.5
    end
end

-- Resolve the display name for a unit. When Northern Sky Raid Tools (NSAPI) is
-- present, returns the NSRT nickname; otherwise the short character name. We pass
-- our addon key "EUI" (NSRT added a dedicated per-addon setting + EUI_NICKNAME_TOGGLE
-- callback for us): NSAPI:GetName self-gates on NSRT's Global Nicknames AND its EUI
-- checkbox, so the user controls nicknames entirely through NSRT (no EUI-side toggle).
-- GetName returns the short name when no nickname is set and guards secret values
-- itself, so the plain UnitName path (with Ambiguate) only runs as a fallback. pcall
-- keeps a misbehaving external API from ever breaking name rendering.
local function ResolveDisplayName(unit)
    local name = UnitName(unit) or ""
    if NSAPI and NSAPI.GetName then
        local ok, dn = pcall(NSAPI.GetName, NSAPI, name, "EUI")
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
            return dn
        end
    end
    if Ambiguate then name = Ambiguate(name, "short") end
    return name
end

local function GetNameColor(unit, s)
    s = s or db.profile
    local mode = s.nameColorMode or "class"
    if mode == "accent" then
        local r, g, b = EllesmereUI.ResolveThemeColor(EllesmereUI.GetActiveTheme())
        if r then return r, g, b end
        return 1, 1, 1
    elseif mode == "custom" then
        local c = s.nameCustomColor
        return c.r, c.g, c.b
    else -- "class"
        local _, classToken = UnitClass(unit)
        if classToken then
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then return cc.r, cc.g, cc.b end
        end
        return 1, 1, 1
    end
end

-- Live name refresh for every raid + party button. Fired by the NSRT nickname
-- callback so added/removed nicknames apply instantly without a /reload.
function ns.RefreshAllNames()
    local s = db and db.profile
    if not s then return end
    local function refresh(unit, btn)
        local d = GetFFD(btn)
        if d and d.nameText then
            d.nameText:SetText(ResolveDisplayName(unit))
            local nr, ng, nb = GetNameColor(unit, s)
            d.nameText:SetTextColor(nr, ng, nb)
        end
    end
    for unit, btn in pairs(unitToButton) do refresh(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do refresh(unit, btn) end
end

-- Health text color (mirrors GetNameColor). Default mode "custom" with white
-- keeps the historical white health text for existing users.
local function GetHealthTextColor(unit, s)
    s = s or db.profile
    local mode = s.healthTextColorMode or "custom"
    if mode == "accent" then
        local r, g, b = EllesmereUI.ResolveThemeColor(EllesmereUI.GetActiveTheme())
        if r then return r, g, b end
        return 1, 1, 1
    elseif mode == "class" then
        local _, classToken = UnitClass(unit)
        if classToken then
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then return cc.r, cc.g, cc.b end
        end
        return 1, 1, 1
    else -- "custom"
        local c = s.healthTextCustomColor
        if c then return c.r, c.g, c.b end
        return 1, 1, 1
    end
end

-- Maps a dispel type to its saved-color key. The "" type (Bleed/physical) is
-- stored under dispelColorBleed.
local DISPEL_COLOR_KEYS = {
    Magic   = "dispelColorMagic",
    Curse   = "dispelColorCurse",
    Disease = "dispelColorDisease",
    Poison  = "dispelColorPoison",
    [""]    = "dispelColorBleed",
}

-- Resolve a dispel type's color: user-customized value (via the proxy `s`)
-- falling back to the hardcoded DISPEL_COLORS default. Returns nil for an
-- unknown/nil type so callers can keep their own fallback behavior.
local function GetDispelColor(dtype, s)
    s = s or db.profile
    local key = DISPEL_COLOR_KEYS[dtype]
    if key then
        local c = s[key]
        if c then return c end
    end
    return DISPEL_COLORS[dtype]
end

local function GetPowerColor(unit)
    local _, pToken = UnitPowerType(unit)
    if pToken and EllesmereUI.GetPowerColor then
        local info = EllesmereUI.GetPowerColor(pToken)
        if info then return info.r, info.g, info.b end
    end
    local pType = UnitPowerType(unit) or 0
    local info = PowerBarColor[pType]
    if info then return info.r, info.g, info.b end
    return 0.5, 0.5, 0.5
end

-------------------------------------------------------------------------------
--  Absorb style application (matches UF exactly)
-------------------------------------------------------------------------------
local function ApplyAbsorbStyle(absorbBar, style, settings)
    if not absorbBar then return end
    local tex = ABSORB_STYLE_TEX[style] or "Interface\\Buttons\\WHITE8X8"
    local alpha = settings and (settings.absorbOpacity or 90) / 100 or (ABSORB_STYLE_ALPHA[style] or 0.8)
    local ac = settings and settings.absorbColor or { r = 1, g = 1, b = 1 }
    local mask = absorbBar._absorbMask
    absorbBar:SetStatusBarTexture(tex)
    absorbBar:SetStatusBarColor(ac.r, ac.g, ac.b, alpha)
    local tiled = (style == "striped")
    local fill = absorbBar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 1)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
        if mask then fill:AddMaskTexture(mask) end
    end
    local fw = absorbBar._forward
    if fw then
        fw:SetStatusBarTexture(tex)
        fw:SetStatusBarColor(ac.r, ac.g, ac.b, alpha)
        local fwFill = fw:GetStatusBarTexture()
        if fwFill then
            fwFill:SetDrawLayer("ARTWORK", 1)
            fwFill:SetHorizTile(tiled)
            fwFill:SetVertTile(tiled)
            if mask then fwFill:AddMaskTexture(mask) end
        end
    end
end

ns.ApplyHealAbsorbStyle = function(haBar, style, settings)
    if not haBar then return end
    local tex = ABSORB_STYLE_TEX[style] or "Interface\\Buttons\\WHITE8X8"
    local alpha = settings and (settings.healAbsorbOpacity or 75) / 100 or 0.65
    local hc = settings and settings.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
    local mask = haBar._absorbMask
    haBar:SetStatusBarTexture(tex)
    haBar:SetStatusBarColor(hc.r, hc.g, hc.b, alpha)
    local tiled = (style == "striped")
    local fill = haBar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 2)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
        if mask then fill:AddMaskTexture(mask) end
    end
end

-------------------------------------------------------------------------------
--  Create absorb bar (dual clip-frame, secret-value safe)
--  Matches UnitFrames implementation exactly.
--  Clip frames do "min(absorb, curHealth)" and "max(0, absorb - curHealth)"
--  visually so we never need Lua arithmetic on secret values.
-------------------------------------------------------------------------------
local function CreateAbsorbBar(button, healthBar)
    if not healthBar then return end
    local d = GetFFD(button)

    -- Mask texture: constrains absorb rendering to exact health bar bounds
    local absorbMask = healthBar:CreateMaskTexture()
    absorbMask:SetAllPoints(healthBar)
    absorbMask:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Current HP clip: bounds the backfill bar to the filled health area
    local curClip = CreateFrame("Frame", nil, healthBar)
    curClip:SetClipsChildren(true)

    -- Missing HP clip: bounds the forward bar to the empty health area
    local missClip = CreateFrame("Frame", nil, healthBar)
    missClip:SetClipsChildren(true)

    -- Backfill bar (overflow): grows into filled health from the right edge
    local backfillBar = CreateFrame("StatusBar", nil, curClip)
    backfillBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local bfFill = backfillBar:GetStatusBarTexture()
    if bfFill then bfFill:SetDrawLayer("ARTWORK", 1); bfFill:AddMaskTexture(absorbMask) end
    backfillBar:SetStatusBarColor(1, 1, 1, 0.8)
    backfillBar:SetReverseFill(true)
    backfillBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
    backfillBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    backfillBar:SetWidth(healthBar:GetWidth())
    backfillBar:SetHeight(healthBar:GetHeight())
    -- Absorb sits on top of the HP cluster: above heal absorb/heal prediction
    -- (healthBar+1) and reduced max health (healthBar+2).
    backfillBar:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    backfillBar:Hide()

    -- Forward bar (primary): grows into missing health from the HP edge
    local forwardBar = CreateFrame("StatusBar", nil, missClip)
    forwardBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local fwFill = forwardBar:GetStatusBarTexture()
    if fwFill then fwFill:SetDrawLayer("ARTWORK", 1); fwFill:AddMaskTexture(absorbMask) end
    forwardBar:SetStatusBarColor(1, 1, 1, 0.8)
    forwardBar:SetReverseFill(false)
    forwardBar:SetWidth(healthBar:GetWidth())
    forwardBar:SetHeight(healthBar:GetHeight())
    -- Match backfill: absorb renders above heal absorb/heal prediction and max health.
    forwardBar:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    forwardBar:Hide()

    -- Forward-declared so ReanchorAbsorbToFill (defined just below) captures
    -- these as upvalues. The bars are created further down; until then the
    -- nil guards inside ReanchorAbsorbToFill simply skip them. Without this,
    -- they resolved to globals (nil) inside the closure, so the heal absorb
    -- never re-anchored to the right edge in "Show Absorbs from Right Edge".
    local healAbsorbBar, healPredBar

    -- Re-anchor clip frames and forward bar to the current health fill texture.
    -- Must be called whenever SetStatusBarTexture replaces the fill object.
    local function ReanchorAbsorbToFill()
        local fill = healthBar:GetStatusBarTexture()
        curClip:ClearAllPoints()
        curClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        curClip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
        missClip:ClearAllPoints()
        missClip:SetPoint("TOPLEFT", fill, "TOPRIGHT", -1, 0)
        missClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        forwardBar:ClearAllPoints()
        forwardBar:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        forwardBar:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
        if healPredBar then
            healPredBar:ClearAllPoints()
            healPredBar:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
            healPredBar:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
        end
        -- Right-edge mode: absorbs render from frame right edge filling left
        if db.profile.absorbFromRightEdge then
            curClip:ClearAllPoints()
            curClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            curClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            if healAbsorbBar then
                healAbsorbBar:ClearAllPoints()
                healAbsorbBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                healAbsorbBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            end
        else
            if healAbsorbBar then
                healAbsorbBar:ClearAllPoints()
                healAbsorbBar:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
                healAbsorbBar:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
            end
        end
    end
    ReanchorAbsorbToFill()

    -- Per-button calculator for reading absorb value (secret-safe)
    local hpCalc
    if CreateUnitHealPredictionCalculator then
        hpCalc = CreateUnitHealPredictionCalculator()
        if hpCalc.SetMaximumHealthMode then
            hpCalc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.WithAbsorbs)
            hpCalc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
        end
    end

    -- Heal absorb bar: red overlay eating into filled health
    healAbsorbBar = CreateFrame("StatusBar", nil, curClip)
    healAbsorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    healAbsorbBar._absorbMask = absorbMask
    local haFill = healAbsorbBar:GetStatusBarTexture()
    if haFill then haFill:SetDrawLayer("ARTWORK", 2); haFill:AddMaskTexture(absorbMask) end
    healAbsorbBar:SetStatusBarColor(0.8, 0.15, 0.15, 0.65)
    healAbsorbBar:SetReverseFill(true)
    healAbsorbBar:SetPoint("TOPRIGHT", healthBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    healAbsorbBar:SetPoint("BOTTOMRIGHT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    healAbsorbBar:SetWidth(healthBar:GetWidth())
    healAbsorbBar:SetHeight(healthBar:GetHeight())
    healAbsorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    healAbsorbBar:Hide()

    -- Heal prediction bar: extends from current HP edge into missing health
    healPredBar = CreateFrame("StatusBar", nil, missClip)
    healPredBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local hpFill = healPredBar:GetStatusBarTexture()
    if hpFill then hpFill:SetDrawLayer("ARTWORK", 2); hpFill:AddMaskTexture(absorbMask) end
    healPredBar:SetStatusBarColor(0.3, 0.8, 0.3, 0.4)
    healPredBar:SetReverseFill(false)
    healPredBar:SetPoint("TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    healPredBar:SetPoint("BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    healPredBar:SetWidth(healthBar:GetWidth())
    healPredBar:SetHeight(healthBar:GetHeight())
    healPredBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    healPredBar:Hide()

    -- Reduced max health bar: black bg + red striped overlay on right side
    local reducedBar = CreateFrame("StatusBar", nil, healthBar)
    reducedBar:SetStatusBarTexture("Interface\\AddOns\\EllesmereUIRaidFrames\\Media\\striped-maxhp.png")
    local rmhFill = reducedBar:GetStatusBarTexture()
    if rmhFill then
        rmhFill:SetDrawLayer("ARTWORK", 3)
        rmhFill:SetHorizTile(true); rmhFill:SetVertTile(true)
    end
    reducedBar:SetStatusBarColor(0.7, 0.1, 0.1, 1)
    reducedBar:SetReverseFill(true)
    reducedBar:SetAllPoints(healthBar)
    reducedBar:SetFrameLevel(healthBar:GetFrameLevel() + 2)
    reducedBar:SetMinMaxValues(0, 1)
    reducedBar:Hide()
    local rmhBg = reducedBar:CreateTexture(nil, "ARTWORK", nil, 2)
    rmhBg:SetColorTexture(0, 0, 0, 1)

    -- Store references in FFD (never on the Blizzard-owned button)
    backfillBar._forward      = forwardBar
    backfillBar._healAbsorb   = healAbsorbBar
    backfillBar._healPred     = healPredBar
    backfillBar._reducedMax   = reducedBar
    backfillBar._reducedMaxBg = rmhBg
    backfillBar._hpBar        = healthBar
    backfillBar._hpCalculator = hpCalc
    backfillBar._curClip      = curClip
    backfillBar._missClip     = missClip
    backfillBar._absorbMask   = absorbMask

    d.absorbBar = backfillBar
    d.ReanchorAbsorbToFill = ReanchorAbsorbToFill
    return backfillBar
end

-------------------------------------------------------------------------------
--  Update absorb bar for a button
-------------------------------------------------------------------------------
local function UpdateAbsorb(button, unit)
    local d = GetFFD(button)
    local ab = d.absorbBar
    if not ab then return end
    local fw = ab._forward
    local hp = ab._hpBar
    local ha = ab._healAbsorb
    local calc = ab._hpCalculator
    if not hp then return end

    local s = d._isParty and ns._scaledPartyProxy or ns._scaledProfile
    if not s.absorbStyle or s.absorbStyle == "none" then
        ab:Hide()
        if fw then fw:Hide() end
        if ha then ha:Hide() end
        return
    end

    local maxHealth, absorbAmt
    if calc and UnitGetDetailedHealPrediction then
        UnitGetDetailedHealPrediction(unit, nil, calc)
        calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
        maxHealth = calc:GetMaximumHealth()
        absorbAmt = calc:GetDamageAbsorbs()
    else
        maxHealth = UnitHealthMax(unit) or 0
        absorbAmt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0
    end

    -- Keep bars sized to health bar every update
    local hpW, hpH = hp:GetWidth(), hp:GetHeight()
    ab:SetWidth(hpW); ab:SetHeight(hpH)
    if fw then fw:SetWidth(hpW); fw:SetHeight(hpH) end

    -- Re-apply style when style, color, or opacity changes
    local absStyle = s.absorbStyle
    local ac = s.absorbColor or { r = 1, g = 1, b = 1 }
    local absKey = (absStyle or "") .. (s.absorbOpacity or 90) .. ac.r .. ac.g .. ac.b
    if absStyle and absStyle ~= "none" and ab._lastAbsKey ~= absKey then
        ab._lastAbsKey = absKey
        ApplyAbsorbStyle(ab, absStyle, s)
    end

    -- Both bars get the raw absorb value and maxHealth.
    -- Clip frames do the visual math so we never compare secret values.
    ab:SetMinMaxValues(0, maxHealth)
    ab:SetValue(absorbAmt)
    ab:Show()

    if fw then
        fw:SetMinMaxValues(0, maxHealth)
        fw:SetValue(absorbAmt)
        fw:Show()
    end
    -- Right-edge mode: forward bar not needed, all absorb shown via backfill
    if s.absorbFromRightEdge and fw then fw:Hide() end

    -- Heal absorb: feed directly without Lua comparison
    if ha then
        local haStyle = s.healAbsorbStyle or "clean"
        if haStyle == "none" then
            ha:Hide()
        else
            local hc = s.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
            local haKey = (haStyle or "") .. (s.healAbsorbOpacity or 75) .. hc.r .. hc.g .. hc.b
            if ha._lastHaKey ~= haKey then
                ha._lastHaKey = haKey
                ns.ApplyHealAbsorbStyle(ha, haStyle, s)
            end
            local healAbsorbAmt = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit) or 0
            ha:SetWidth(hpW); ha:SetHeight(hpH)
            ha:SetMinMaxValues(0, maxHealth)
            ha:SetValue(healAbsorbAmt)
            ha:Show()
        end
    end

    -- Heal prediction: extends from current HP into missing health
    local hpd = ab._healPred
    if hpd then
        if not s.healPrediction then
            hpd:Hide()
        else
            local pc = s.healPredColor or { r = 102/255, g = 243/255, b = 102/255 }
            local pAlpha = (s.healPredOpacity or 75) / 100
            hpd:SetStatusBarColor(pc.r, pc.g, pc.b, pAlpha)
            local incomingHeals = UnitGetIncomingHeals and UnitGetIncomingHeals(unit) or 0
            hpd:SetWidth(hpW); hpd:SetHeight(hpH)
            hpd:SetMinMaxValues(0, maxHealth)
            hpd:SetValue(incomingHeals)
            hpd:Show()
        end
    end

    -- Reduced max health: striped overlay on right side
    local rmh = ab._reducedMax
    if rmh then
        local lossPct = GetUnitTotalModifiedMaxHealthPercent and GetUnitTotalModifiedMaxHealthPercent(unit) or 0
        if lossPct > 0 then
            rmh:SetValue(lossPct)
            -- Anchor background to the fill texture
            local rmhBg = ab._reducedMaxBg
            if rmhBg then rmhBg:SetAllPoints(rmh:GetStatusBarTexture()) end
            rmh:Show()
        else
            rmh:Hide()
        end
    end
end

-------------------------------------------------------------------------------
--  Style a single button (called once per button at creation time)
-------------------------------------------------------------------------------
local function StyleButton(button)
    local d = GetFFD(button)
    if d.styled then return end
    d.styled = true

    local s = db.profile
    local w = PixelSnap(s.frameWidth or 72)
    local h = PixelSnap(s.frameHeight or 46)
    -- The power bar is ALWAYS created (hidden) below so a later profile swap
    -- into a power-enabled profile always has a bar to show; UpdateButton drives
    -- the per-role show/hide and the matching health height. The health bar
    -- therefore starts at FULL height (power hidden) -- otherwise the bottom
    -- powerH strip would show the dark bg as an "empty power bar" until the first
    -- UpdateButton (the profile-swap-into-power bug + a ~0.5s login gap).
    local powerH = PixelSnap(s.powerHeight or 4)
    local healthH = h

    button:SetSize(w, h)

    -- Background (visible behind the health bar where HP is missing)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local bgc = s.customBgColor
    bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
    if PP then PP.DisablePixelSnap(bg) end
    d.bg = bg

    -- Health bar
    local health = CreateFrame("StatusBar", nil, button)
    health:SetFrameLevel(button:GetFrameLevel() + 2)
    health:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    health:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    health:SetHeight(healthH)
    local texPath = ResolveHealthTexture()
    health:SetStatusBarTexture(texPath)
    health:GetStatusBarTexture():SetHorizTile(false)
    if PP then PP.DisablePixelSnap(health) end
    health:SetMinMaxValues(0, 100)
    health:SetValue(100)
    d.health = health

    -- Power bar (ALWAYS created, anchored to button bottom for pixel alignment).
    -- Created HIDDEN and decoupled from the role toggles: UpdateButton's per-role
    -- gate shows it + fills it for power-wanting units. Creating it unconditionally
    -- (was gated on IsPowerBarEnabled) is what lets a power-OFF login profile still
    -- have bars to show after swapping to a power-ON profile.
    do
        local power = CreateFrame("StatusBar", nil, button)
        power:SetFrameLevel(button:GetFrameLevel() + 3)
        power:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
        power:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        power:SetHeight(powerH)
        power:SetStatusBarTexture(texPath)
        power:GetStatusBarTexture():SetHorizTile(false)
        if PP then PP.DisablePixelSnap(power) end
        power:SetMinMaxValues(0, 1)
        power:SetValue(1)
        local pwBg = power:CreateTexture(nil, "BACKGROUND")
        pwBg:SetAllPoints()
        pwBg:SetColorTexture((s.powerBgColor or {}).r or 0, (s.powerBgColor or {}).g or 0, (s.powerBgColor or {}).b or 0, (s.powerBgDarkness or 70) / 100)
        if PP then PP.DisablePixelSnap(pwBg) end
        d.power = power
        d.powerBg = pwBg

        -- Power border frame
        local pwBdrFrame = CreateFrame("Frame", nil, button)
        pwBdrFrame:SetAllPoints(power)
        pwBdrFrame:SetFrameLevel(power:GetFrameLevel() + 1)
        if PP then PP.CreateBorder(pwBdrFrame, 0, 0, 0, 1, 1) end
        d.powerBorderFrame = pwBdrFrame

        -- Start hidden; UpdateButton shows it per role (and wasShown=false there
        -- plain-snaps the first fill, preserving the existing interpolation fix).
        power:Hide()
        pwBdrFrame:Hide()
    end

    -- Absorb shields
    CreateAbsorbBar(button, health)

    -- Border frame
    local bdrFrame = CreateFrame("Frame", nil, button)
    bdrFrame:SetAllPoints(button)
    bdrFrame:SetFrameLevel(button:GetFrameLevel() + 8)
    d.borderFrame = bdrFrame
    -- Styled via EllesmereUI.ApplyBorderStyle (PP or textured/SharedMedia) in
    -- UpdateBorder. Hover/Target are color states recolored onto this single
    -- border (mirrors Unit Frames), not separate frames.

    -- Threat border
    local threatFrame = CreateFrame("Frame", nil, button)
    threatFrame:SetAllPoints(button)
    threatFrame:SetFrameLevel(button:GetFrameLevel() + 10)
    threatFrame:Hide()
    d.threatFrame = threatFrame
    if PP then PP.CreateBorder(threatFrame, 1, 0, 0, 1, 2) end

    -- Dispel border (health bar only, not power bar)
    local dispelFrame = CreateFrame("Frame", nil, button)
    dispelFrame:SetAllPoints(health)
    dispelFrame:SetFrameLevel(button:GetFrameLevel() + 10)
    dispelFrame:Hide()
    d.dispelFrame = dispelFrame
    if PP then PP.CreateBorder(dispelFrame, 0.2, 0.6, 1, 1, 2) end

    -- Dispel overlay (fill / full / gradient)
    -- Texture on health bar at ARTWORK sublevel 3: above fill (0) AND above the
    -- BM health-color overlay (sublevel 2), below absorb bars (child frames at
    -- higher frame level) and text (OVERLAY).
    local dispelOLTex = health:CreateTexture(nil, "ARTWORK", nil, 3)
    dispelOLTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    dispelOLTex:Hide()
    d.dispelOLTex = dispelOLTex
    d.dispelOLHealth = health  -- anchor reference for fill/full modes

    -- Dispel type icon
    local dispelIcon = CreateFrame("Frame", nil, button)
    dispelIcon:SetFrameLevel(button:GetFrameLevel() + ns.LVL_AURA)
    local diSz = PixelSnap(s.dispelIconSize or 16)
    dispelIcon:SetSize(diSz, diSz)
    dispelIcon:Hide()
    d.dispelIcon = dispelIcon
    -- One overlapping atlas texture per dispellable type. We can't read the
    -- (secret) dispel type to pick one, so we show them all and let a per-type
    -- alpha curve make only the matching one visible (secret alpha passthrough).
    d.dispelIconTextures = {}
    -- Keyed by Blizzard dispel-type index. 9 (Enrage) and 11 (Bleed) share the
    -- physical/bleed atlas, matching how the color curve treats them.
    for idx, name in pairs({ [1] = "Magic", [2] = "Curse", [3] = "Disease", [4] = "Poison", [9] = "", [11] = "" }) do
        local tex = dispelIcon:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetAtlas(DISPEL_ICON_ATLAS[name])
        tex:Hide()
        d.dispelIconTextures[idx] = tex
    end

    -- Private aura dispel container (Blizzard-rendered overlay for private
    -- dispellable debuffs). Only way to show dispel info for re-privated
    -- auras in 12.0.5+. Uses alpha gating: our custom overlay wins for
    -- normal debuffs, container catches private ones we can't see.
    if C_UnitAuras_AddPrivateAuraAnchor then
        local dcWrapper = CreateFrame("Frame", nil, button)
        dcWrapper:SetAllPoints(health)
        dcWrapper:SetFrameLevel(button:GetFrameLevel() + ns.LVL_AURA)
        dcWrapper:EnableMouse(false)
        if dcWrapper.SetMouseClickEnabled then dcWrapper:SetMouseClickEnabled(false) end
        -- Set all required attributes BEFORE AddPrivateAuraAnchor
        dcWrapper:SetAttribute("max-buffs", 0)
        dcWrapper:SetAttribute("max-debuffs", 0)
        dcWrapper:SetAttribute("max-dispel-debuffs", 1)
        dcWrapper:SetAttribute("ignore-buffs", true)
        dcWrapper:SetAttribute("ignore-debuffs", true)
        dcWrapper:SetAttribute("ignore-dispel-debuffs", true)
        dcWrapper:SetAttribute("show-dispel-indicator-overlay", true)
        dcWrapper:SetAttribute("suppress-dispel-border-icons", true)
        -- The container is the private-aura fallback for re-privated debuffs our
        -- own overlay cannot see; Blizzard applies the dispel filter for us via this
        -- attribute. When the user wants every dispellable debuff we ask Blizzard for
        -- the wider set, otherwise we restrict it to what this character can remove.
        -- Re-applied in RegisterDispelContainer so the setting survives a reload.
        dcWrapper:SetAttribute("dispel-indicator-option", (s.dispelShowAll ~= false) and 2 or 1)
        dcWrapper:SetAttribute("aura-organization-type", 0)   -- 0 = top-down growth
        dcWrapper:SetAttribute("always-hide-duration", true)
        dcWrapper:SetAttribute("set-aura-size-to-icon-size", true)
        dcWrapper:SetAttribute("icon-size", 12)
        dcWrapper:SetAttribute("power-bar-used-height", 0)
        dcWrapper:SetAttribute("group-type", 5)  -- updated per-unit in RebuildUnitMap
        -- Start hidden via alpha (not Show/Hide -- container eventFrame
        -- unregisters from UNIT_AURA on OnHide, so we keep it Shown and
        -- gate visibility with alpha)
        dcWrapper:SetAlpha(0)
        dcWrapper:Show()
        d.dispelContainer = dcWrapper
        d.dispelContainerAnchorID = nil  -- set when unit is assigned
    end

    -- Per-slot private aura icon frames for boss debuffs (isContainer=false).
    -- Created lazily here, anchors registered when units are assigned.
    if C_UnitAuras_AddPrivateAuraAnchor then
        local paCap = s.debuffCap or 3
        local paSz = s.paSize or 18
        d.privateAuraFrames = {}
        d.privateAuraAnchorIDs = {}
        for i = 1, paCap do
            local paFrame = CreateFrame("Frame", nil, button)
            paFrame:SetFrameLevel(button:GetFrameLevel() + ns.LVL_AURA)
            paFrame:SetSize(paSz, paSz)
            paFrame:EnableMouse(false)
            if paFrame.SetMouseClickEnabled then paFrame:SetMouseClickEnabled(false) end
            paFrame:Hide()
            d.privateAuraFrames[i] = paFrame
        end
    end

    local function AnchorDispelIcon()
        dispelIcon:ClearAllPoints()
        local pos = s.dispelIconPosition or "center"
        local ox = s.dispelIconOffsetX or 0
        local oy = s.dispelIconOffsetY or 0
        -- Dispel icon anchors flush to the health bar edge (no 1px inset),
        -- matching the debuff/role icon displays.
        if pos == "topleft" then
            dispelIcon:SetPoint("TOPLEFT", health, "TOPLEFT", ox, oy)
        elseif pos == "top" then
            dispelIcon:SetPoint("TOP", health, "TOP", ox, oy)
        elseif pos == "topright" then
            dispelIcon:SetPoint("TOPRIGHT", health, "TOPRIGHT", ox, oy)
        elseif pos == "left" then
            dispelIcon:SetPoint("LEFT", health, "LEFT", ox, oy)
        elseif pos == "right" then
            dispelIcon:SetPoint("RIGHT", health, "RIGHT", ox, oy)
        elseif pos == "bottomleft" then
            dispelIcon:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", ox, oy)
        elseif pos == "bottom" then
            dispelIcon:SetPoint("BOTTOM", health, "BOTTOM", ox, oy)
        elseif pos == "bottomright" then
            dispelIcon:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", ox, oy)
        else -- center
            dispelIcon:SetPoint("CENTER", health, "CENTER", ox, oy)
        end
    end
    AnchorDispelIcon()
    d.AnchorDispelIcon = AnchorDispelIcon

    -- Text carrier: name + health text sit ABOVE the base/threat/dispel borders
    -- (+8/+10/+11) and the BM frame-border effect (+11) so they stay readable,
    -- but BELOW the aura layer (ns.LVL_AURA = +13) so debuffs/buffs draw over them.
    local textCarrier = CreateFrame("Frame", nil, button)
    textCarrier:SetAllPoints(health)
    textCarrier:SetFrameLevel(button:GetFrameLevel() + 12)

    -- Name text
    local nameFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(nameFS, s.nameSize or 10)
    nameFS:SetJustifyH("CENTER")
    nameFS:SetWordWrap(false)
    d.nameText = nameFS

    -- Health deficit text
    local healthFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(healthFS, s.healthTextSize or 9)
    healthFS:SetTextColor(1, 1, 1, 0.9)
    d.healthText = healthFS

    local function AnchorHealthText()
        healthFS:ClearAllPoints()
        local pos = s.healthTextPosition or "center"
        local ox = s.healthTextOffsetX or 0
        local oy = s.healthTextOffsetY or 0
        healthFS:SetWidth((s.frameWidth or 72) * 0.75)
        healthFS:SetHeight(0)
        if pos == "topleft" then
            healthFS:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
            healthFS:SetJustifyH("LEFT"); healthFS:SetJustifyV("TOP")
        elseif pos == "top" then
            healthFS:SetPoint("TOP", health, "TOP", ox, -2 + oy)
            healthFS:SetJustifyH("CENTER"); healthFS:SetJustifyV("TOP")
        elseif pos == "topright" then
            healthFS:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
            healthFS:SetJustifyH("RIGHT"); healthFS:SetJustifyV("TOP")
        elseif pos == "left" then
            healthFS:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
            healthFS:SetJustifyH("LEFT"); healthFS:SetJustifyV("MIDDLE")
        elseif pos == "right" then
            healthFS:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
            healthFS:SetJustifyH("RIGHT"); healthFS:SetJustifyV("MIDDLE")
        elseif pos == "bottomleft" then
            healthFS:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
            healthFS:SetJustifyH("LEFT"); healthFS:SetJustifyV("BOTTOM")
        elseif pos == "bottom" then
            healthFS:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
            healthFS:SetJustifyH("CENTER"); healthFS:SetJustifyV("BOTTOM")
        elseif pos == "bottomright" then
            healthFS:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            healthFS:SetJustifyH("RIGHT"); healthFS:SetJustifyV("BOTTOM")
        else -- "center"
            healthFS:SetPoint("CENTER", health, "CENTER", ox, oy)
            healthFS:SetJustifyH("CENTER"); healthFS:SetJustifyV("MIDDLE")
        end
        local txt = healthFS:GetText()
        healthFS:SetText("")
        healthFS:SetText(txt or "")
    end
    AnchorHealthText()
    d.AnchorHealthText = AnchorHealthText

    -- Status text (DEAD / OFFLINE / AFK -- always shown, own position/size/color)
    local statusFS = health:CreateFontString(nil, "OVERLAY")
    local stc = s.statusTextColor or { r = 1, g = 1, b = 1 }
    ApplyFont(statusFS, s.statusTextSize or 14)
    statusFS:SetJustifyH("CENTER")
    statusFS:SetTextColor(stc.r, stc.g, stc.b)
    statusFS:Hide()
    d.statusText = statusFS

    local function AnchorStatusText()
        statusFS:ClearAllPoints()
        local pos = s.statusTextPosition or "center"
        local ox = s.statusTextOffsetX or 0
        local oy = s.statusTextOffsetY or 0
        if pos == "topleft" then
            statusFS:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
        elseif pos == "top" then
            statusFS:SetPoint("TOP", health, "TOP", ox, -2 + oy)
        elseif pos == "topright" then
            statusFS:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
        elseif pos == "left" then
            statusFS:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
        elseif pos == "right" then
            statusFS:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
        elseif pos == "bottomleft" then
            statusFS:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
        elseif pos == "bottom" then
            statusFS:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
        elseif pos == "bottomright" then
            statusFS:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
        else -- center
            statusFS:SetPoint("CENTER", health, "CENTER", ox, oy)
        end
    end
    AnchorStatusText()
    d.AnchorStatusText = AnchorStatusText

    -- Role icon (carrier frame above power bar + its border so icon renders on top)
    local roleCarrier = CreateFrame("Frame", nil, button)
    roleCarrier:SetAllPoints(health)
    roleCarrier:SetFrameLevel(button:GetFrameLevel() + 5)
    local roleIcon = roleCarrier:CreateTexture(nil, "OVERLAY")
    local riSz = PixelSnap(s.roleIconSize or 14)
    roleIcon:SetSize(riSz, riSz)
    roleIcon:Hide()
    d.roleIcon = roleIcon

    local function AnchorRoleIcon()
        roleIcon:ClearAllPoints()
        local pos = s.roleIconPosition or "bottomleft"
        local ox = s.roleIconOffsetX or 0
        local oy = s.roleIconOffsetY or 0
        if pos == "topright" then
            roleIcon:SetPoint("TOPRIGHT", health, "TOPRIGHT", ox, oy)
        elseif pos == "bottomleft" then
            roleIcon:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", ox, oy)
        elseif pos == "bottomright" then
            roleIcon:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", ox, oy)
        else -- topleft
            roleIcon:SetPoint("TOPLEFT", health, "TOPLEFT", ox, oy)
        end
    end
    AnchorRoleIcon()
    d.AnchorRoleIcon = AnchorRoleIcon

    -- Marker carrier: above the frame border (including the hover/target raise
    -- at +12/+13) so the raid marker renders on top of the border instead of
    -- being clipped behind it.
    local markerCarrier = CreateFrame("Frame", nil, button)
    markerCarrier:SetAllPoints(health)
    markerCarrier:SetFrameLevel(button:GetFrameLevel() + ns.LVL_MARKER)

    -- Leader/assistant icon. Hosted on its own frame lowered to the chat frame's
    -- strata (one level above chat) so it renders on the same layer as chat,
    -- above chat on that layer -- NOT on the marker carrier, whose high level
    -- keeps the raid marker always on top. Parented to the button so it tracks
    -- the frame; SetAllPoints(health) so the icon still anchors to the health
    -- bar as before. Strata/level are re-asserted on reload (chat-relative).
    d.leaderHost = CreateFrame("Frame", nil, button)
    d.leaderHost:SetAllPoints(health)
    ns.ApplyChatStrata(d.leaderHost)

    local leaderIcon = d.leaderHost:CreateTexture(nil, "OVERLAY")
    local liSz = PixelSnap(s.leaderIconSize or 14)
    leaderIcon:SetSize(liSz, liSz)
    local liPos = (s.leaderIconPosition or "top"):upper()
    leaderIcon:SetPoint(liPos, health, liPos, s.leaderIconOffsetX or 0, s.leaderIconOffsetY or 0)
    leaderIcon:Hide()
    d.leaderIcon = leaderIcon

    -- Raid marker (on marker carrier, above the border)
    local raidMarker = markerCarrier:CreateTexture(nil, "OVERLAY", nil, 2)
    local rmSz = PixelSnap(s.raidMarkerSize or 16)
    raidMarker:SetSize(rmSz, rmSz)
    raidMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    raidMarker:Hide()
    d.raidMarker = raidMarker

    local function AnchorRaidMarker()
        raidMarker:ClearAllPoints()
        local pos = s.raidMarkerPosition or "center"
        local ox = s.raidMarkerOffsetX or 0
        local oy = s.raidMarkerOffsetY or 0
        if pos == "topleft" then
            raidMarker:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
        elseif pos == "top" then
            raidMarker:SetPoint("TOP", health, "TOP", ox, -2 + oy)
        elseif pos == "topright" then
            raidMarker:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
        elseif pos == "left" then
            raidMarker:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
        elseif pos == "right" then
            raidMarker:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
        elseif pos == "bottomleft" then
            raidMarker:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
        elseif pos == "bottom" then
            raidMarker:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
        elseif pos == "bottomright" then
            raidMarker:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
        else -- center
            raidMarker:SetPoint("CENTER", health, "CENTER", ox, oy)
        end
    end
    AnchorRaidMarker()
    d.AnchorRaidMarker = AnchorRaidMarker

    -- Ready check icon
    local readyCheck = health:CreateTexture(nil, "OVERLAY", nil, 3)
    readyCheck:SetSize(18, 18)
    readyCheck:SetPoint("CENTER", health, "CENTER", 0, 0)
    readyCheck:Hide()
    d.readyCheck = readyCheck

    -- Debuff icons (pre-created, anchored dynamically)
    d.debuffIcons = {}
    local cap = s.debuffCap or 3
    for i = 1, cap do
        local icon = CreateFrame("Frame", nil, button)
        icon:SetFrameLevel(button:GetFrameLevel() + ns.LVL_AURA)
        icon:SetSize(s.debuffSize or 18, s.debuffSize or 18)
        icon:Hide()

        local iconTex = icon:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon._tex = iconTex

        local cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        cooldown:SetAllPoints()
        cooldown:SetDrawEdge(false)
        cooldown:SetDrawSwipe(true)
        cooldown:SetSwipeColor(0, 0, 0, 0.6)
        cooldown:SetReverse(true)
        cooldown:SetHideCountdownNumbers(true)
        icon._cooldown = cooldown

        -- Debuff type border
        local dbBorder = CreateFrame("Frame", nil, icon)
        dbBorder:SetAllPoints()
        dbBorder:SetFrameLevel(icon:GetFrameLevel() + 1)
        icon._borderFrame = dbBorder
        if PP then PP.CreateBorder(dbBorder, 0, 0, 0, 1, 1) end

        -- Text carrier above cooldown swipe AND border
        local dbFontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local dbTextLevel = math.max(cooldown:GetFrameLevel() + 2, dbBorder:GetFrameLevel() + 1)
        local dbDurCarrier = CreateFrame("Frame", nil, icon)
        dbDurCarrier:SetAllPoints()
        dbDurCarrier:SetFrameLevel(dbTextLevel)

        -- Stack count text
        local dbCountFS = dbDurCarrier:CreateFontString(nil, "OVERLAY")
        dbCountFS:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
        dbCountFS:SetFont(dbFontPath, 8, "OUTLINE")
        dbCountFS:SetTextColor(1, 1, 1)
        icon._count = dbCountFS

        -- Duration text
        local dbDurFS = dbDurCarrier:CreateFontString(nil, "OVERLAY")
        dbDurFS:SetPoint("CENTER", icon, "CENTER", 0, 0)
        dbDurFS:SetFont(dbFontPath, 8, "OUTLINE")
        dbDurFS:SetTextColor(1, 1, 1)
        dbDurFS:Hide()
        icon._durText = dbDurFS

        d.debuffIcons[i] = icon
    end

    -- Anchor debuff icons based on position + growth direction
    -- Anchor debuff icons. For CENTER growth, call with visibleCount to
    -- dynamically center the row based on how many icons are actually shown.
    local function AnchorDebuffs(visibleCount)
        local pos = s.debuffPosition or "bottomleft"
        local ox = s.debuffOffsetX or 0
        local oy = s.debuffOffsetY or 0
        local grow = s.debuffGrowDirection or "RIGHT"
        local sz = s.debuffSize or 18
        local spc = PixelSnap(s.debuffSpacing or 1)
        local spacing = sz + spc

        -- CENTER growth: offset so visible icons are centered on anchor
        local centerOff = 0
        if grow == "CENTER" and visibleCount and visibleCount > 0 then
            centerOff = -((visibleCount - 1) * spacing) / 2
        end

        for i, icon in ipairs(d.debuffIcons) do
            icon:ClearAllPoints()
            if i == 1 then
                local fx = ox + (grow == "CENTER" and centerOff or 0)
                -- Debuffs anchor flush to the health bar edge (no 1px inset), so
                -- the bottom positions sit level with the edge like the role icon.
                if pos == "topleft" then
                    icon:SetPoint("TOPLEFT", health, "TOPLEFT", fx, oy)
                elseif pos == "top" then
                    icon:SetPoint("TOP", health, "TOP", fx, oy)
                elseif pos == "topright" then
                    icon:SetPoint("TOPRIGHT", health, "TOPRIGHT", fx, oy)
                elseif pos == "left" then
                    icon:SetPoint("LEFT", health, "LEFT", fx, oy)
                elseif pos == "center" then
                    icon:SetPoint("CENTER", health, "CENTER", fx, oy)
                elseif pos == "right" then
                    icon:SetPoint("RIGHT", health, "RIGHT", fx, oy)
                elseif pos == "bottomright" then
                    icon:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", fx, oy)
                elseif pos == "bottom" then
                    icon:SetPoint("BOTTOM", health, "BOTTOM", fx, oy)
                else -- bottomleft
                    icon:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", fx, oy)
                end
            else
                local prev = d.debuffIcons[i - 1]
                if grow == "RIGHT" or grow == "CENTER" then
                    icon:SetPoint("LEFT", prev, "RIGHT", spc, 0)
                elseif grow == "LEFT" then
                    icon:SetPoint("RIGHT", prev, "LEFT", -spc, 0)
                elseif grow == "UP" then
                    icon:SetPoint("BOTTOM", prev, "TOP", 0, spc)
                elseif grow == "DOWN" then
                    icon:SetPoint("TOP", prev, "BOTTOM", 0, -spc)
                end
            end
        end
    end
    AnchorDebuffs()
    d.AnchorDebuffs = AnchorDebuffs

    -- Defensive/external icon pool (same structure as debuff icons)
    local DEF_CAP = 4
    d.defIcons = {}
    for i = 1, DEF_CAP do
        local defIcon = CreateFrame("Frame", nil, button)
        defIcon:SetFrameLevel(button:GetFrameLevel() + ns.LVL_AURA)
        defIcon:SetSize(s.defSize or 22, s.defSize or 22)
        defIcon:Hide()

        local defTex = defIcon:CreateTexture(nil, "ARTWORK")
        defTex:SetAllPoints()
        defTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        defIcon._tex = defTex

        local defCD = CreateFrame("Cooldown", nil, defIcon, "CooldownFrameTemplate")
        defCD:SetAllPoints()
        defCD:SetDrawEdge(false)
        defCD:SetDrawSwipe(true)
        defCD:SetSwipeColor(0, 0, 0, 0.6)
        defCD:SetReverse(true)
        defCD:SetHideCountdownNumbers(true)
        defIcon._cooldown = defCD

        local defBdr = CreateFrame("Frame", nil, defIcon)
        defBdr:SetAllPoints()
        defBdr:SetFrameLevel(defIcon:GetFrameLevel() + 1)
        defIcon._borderFrame = defBdr
        if PP then PP.CreateBorder(defBdr, 0, 0, 0, 1, 1) end

        -- Duration text (on carrier above cooldown swipe, matching debuff icons)
        local defDurCarrier = CreateFrame("Frame", nil, defIcon)
        defDurCarrier:SetAllPoints()
        defDurCarrier:SetFrameLevel(defCD:GetFrameLevel() + 2)
        local defDurFontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local defDurFS = defDurCarrier:CreateFontString(nil, "OVERLAY")
        defDurFS:SetPoint("CENTER", defIcon, "CENTER", 0, 0)
        defDurFS:SetFont(defDurFontPath, 8, "OUTLINE")
        defDurFS:SetTextColor(1, 1, 1)
        defDurFS:Hide()
        defIcon._durText = defDurFS

        d.defIcons[i] = defIcon
    end

    -- Anchor defensive icons. For CENTER growth, call with visibleCount
    -- to dynamically center the row based on how many are actually shown.
    local function AnchorDefensives(visibleCount)
        local pos = s.defPosition or "center"
        local ox = s.defOffsetX or 0
        local oy = s.defOffsetY or 0
        local grow = s.defGrowDirection or "CENTER"
        local sz = s.defSize or 22
        local spc = PixelSnap(s.defSpacing or 1)
        local spacing = sz + spc

        local centerOff = 0
        if grow == "CENTER" and visibleCount and visibleCount > 0 then
            centerOff = -((visibleCount - 1) * spacing) / 2
        end

        for i, icon in ipairs(d.defIcons) do
            icon:ClearAllPoints()
            if i == 1 then
                local fx = ox + (grow == "CENTER" and centerOff or 0)
                -- Defensive icons anchor flush to the health bar edge (no 1px
                -- inset), matching the debuff/role icon displays.
                if pos == "topleft" then
                    icon:SetPoint("TOPLEFT", health, "TOPLEFT", fx, oy)
                elseif pos == "top" then
                    icon:SetPoint("TOP", health, "TOP", fx, oy)
                elseif pos == "topright" then
                    icon:SetPoint("TOPRIGHT", health, "TOPRIGHT", fx, oy)
                elseif pos == "left" then
                    icon:SetPoint("LEFT", health, "LEFT", fx, oy)
                elseif pos == "center" then
                    icon:SetPoint("CENTER", health, "CENTER", fx, oy)
                elseif pos == "right" then
                    icon:SetPoint("RIGHT", health, "RIGHT", fx, oy)
                elseif pos == "bottomright" then
                    icon:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", fx, oy)
                elseif pos == "bottom" then
                    icon:SetPoint("BOTTOM", health, "BOTTOM", fx, oy)
                else
                    icon:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", fx, oy)
                end
            else
                local prev = d.defIcons[i - 1]
                if grow == "RIGHT" or grow == "CENTER" then
                    icon:SetPoint("LEFT", prev, "RIGHT", spc, 0)
                elseif grow == "LEFT" then
                    icon:SetPoint("RIGHT", prev, "LEFT", -spc, 0)
                elseif grow == "UP" then
                    icon:SetPoint("BOTTOM", prev, "TOP", 0, spc)
                elseif grow == "DOWN" then
                    icon:SetPoint("TOP", prev, "BOTTOM", 0, -spc)
                end
            end
        end
    end
    AnchorDefensives()
    d.AnchorDefensives = AnchorDefensives

    -- Anchor name text based on position setting
    -- Uses two-point anchoring (LEFT+RIGHT) for width constraint, with
    -- vertical position via a single vertical anchor. JustifyH/V controls
    -- text alignment within the bounded region.
    local function AnchorNameText()
        nameFS:ClearAllPoints()
        local pos = s.namePosition or "center"
        local ox = s.nameOffsetX or 0
        local oy = s.nameOffsetY or 0
        nameFS:SetWidth((s.frameWidth or 72) * 0.75)
        nameFS:SetHeight(0)
        if pos == "topleft" then
            nameFS:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
            nameFS:SetJustifyH("LEFT"); nameFS:SetJustifyV("TOP")
        elseif pos == "top" then
            nameFS:SetPoint("TOP", health, "TOP", ox, -2 + oy)
            nameFS:SetJustifyH("CENTER"); nameFS:SetJustifyV("TOP")
        elseif pos == "topright" then
            nameFS:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
            nameFS:SetJustifyH("RIGHT"); nameFS:SetJustifyV("TOP")
        elseif pos == "left" then
            nameFS:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
            nameFS:SetJustifyH("LEFT"); nameFS:SetJustifyV("MIDDLE")
        elseif pos == "right" then
            nameFS:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
            nameFS:SetJustifyH("RIGHT"); nameFS:SetJustifyV("MIDDLE")
        elseif pos == "bottomleft" then
            nameFS:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
            nameFS:SetJustifyH("LEFT"); nameFS:SetJustifyV("BOTTOM")
        elseif pos == "bottom" then
            nameFS:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
            nameFS:SetJustifyH("CENTER"); nameFS:SetJustifyV("BOTTOM")
        elseif pos == "bottomright" then
            nameFS:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            nameFS:SetJustifyH("RIGHT"); nameFS:SetJustifyV("BOTTOM")
        else -- "center"
            nameFS:SetPoint("CENTER", health, "CENTER", ox, oy)
            nameFS:SetJustifyH("CENTER"); nameFS:SetJustifyV("MIDDLE")
        end
        -- Force text re-render (WoW doesn't visually re-layout on JustifyH change alone)
        local txt = nameFS:GetText()
        nameFS:SetText("")
        nameFS:SetText(txt or "")
    end
    AnchorNameText()
    d.AnchorNameText = AnchorNameText

    -- Raise the border above neighboring frames while hovered/targeted. Buttons
    -- share a frame level, and the border is inset, so with small or negative
    -- Frame Spacing the frames overlap and a neighbor's border would cover this
    -- frame's highlight border. Highlight states bump it up; normal restores the
    -- base level. The PP container's level is fixed at creation, so it must be
    -- moved explicitly (changing borderFrame alone won't move it).
    local function ApplyBorderLevel(raised)
        if not (PP and d.borderFrame) then return end
        local pl = button:GetFrameLevel()
        local lvl = s.borderBehind and math.max(0, pl - 1) or (pl + (raised and ns.LVL_RAISE or 8))
        -- Hot path: this runs from ApplyBorderColor on every UpdateButton. Skip
        -- the SetFrameLevel calls unless the level actually needs to change (only
        -- on a hover/target transition or a borderBehind toggle), so the common
        -- per-update case is just two cheap getter comparisons.
        local container = PP.GetBorders(d.borderFrame)
        if d.borderFrame:GetFrameLevel() == lvl
           and (not container or container:GetFrameLevel() == lvl + 1) then
            return
        end
        d.borderFrame:SetFrameLevel(lvl)
        if container then container:SetFrameLevel(lvl + 1) end
    end

    -- Recolor the single border to reflect the current state. Priority matches
    -- the old frame layering: hover (highest) > target > normal.
    local function ApplyBorderColor()
        if not (PP and d.borderFrame) then return end
        if (s.borderSize or 1) <= 0 then return end
        local r, g, b, a
        local raised = false
        if d._hovered and s.hoverBorderEnabled ~= false then
            local c = s.hoverBorderColor or { r = 1, g = 1, b = 1 }
            r, g, b, a = c.r, c.g, c.b, s.hoverBorderAlpha or 1
            raised = true
        elseif d._isTarget and s.targetBorderEnabled ~= false then
            local c = s.targetBorderColor or { r = 1, g = 1, b = 1 }
            r, g, b, a = c.r, c.g, c.b, s.targetBorderAlpha or 1
            raised = true
        else
            local c = s.borderColor or { r = 0, g = 0, b = 0 }
            r, g, b, a = c.r, c.g, c.b, s.borderAlpha or 1
        end
        ApplyBorderLevel(raised)
        EllesmereUI.SetBorderStyleColor(d.borderFrame, r, g, b, a)
    end
    d.ApplyBorderColor = ApplyBorderColor

    -- Apply border (style/size/texture/offsets via shared ApplyBorderStyle, then
    -- recolor for the current state). "Show Behind" lowers the border below the
    -- frame; otherwise it sits above at +8 (unchanged from the old layering).
    local function UpdateBorder()
        if not (PP and d.borderFrame) then return end
        local bs = s.borderSize or 1
        local bc = s.borderColor or { r = 0, g = 0, b = 0 }
        local texKey = s.borderTexture or "solid"
        local pl = button:GetFrameLevel()
        d.borderFrame:SetFrameLevel(s.borderBehind and math.max(0, pl - 1) or (pl + 8))
        EllesmereUI.ApplyBorderStyle(d.borderFrame, bs, bc.r, bc.g, bc.b, s.borderAlpha or 1,
            texKey, s.borderTextureOffset, s.borderTextureOffsetY,
            s.borderTextureShiftX, s.borderTextureShiftY, "unitframes", bs)
        ApplyBorderColor()
    end
    UpdateBorder()
    d.UpdateBorder = UpdateBorder

    -- Apply power border
    local function UpdatePowerBorder()
        -- No-op while the power bar is hidden. The border frame is always created
        -- now (even on power-OFF profiles), and the unconditional callers
        -- (StyleButton tail, ReloadFrames, ReloadPartyFrames) must not draw a
        -- border over a hidden bar. UpdateButton calls this AFTER power:Show().
        if not PP or not d.powerBorderFrame or (d.power and not d.power:IsShown()) then return end
        local style = s.powerBorderStyle or "eui"
        if style == "eui" then
            -- EUI style: 1px divider, white at 20% opacity
            PP.UpdateBorder(d.powerBorderFrame, 1, 1, 1, 1, 0.2)
            d.powerBorderFrame:Show()
            local ppC = PP.GetBorders(d.powerBorderFrame)
            if ppC then
                if ppC._bottom then ppC._bottom:SetAlpha(0) end
                if ppC._left then ppC._left:SetAlpha(0) end
                if ppC._right then ppC._right:SetAlpha(0) end
                if ppC._top then ppC._top:SetAlpha(0.2) end
            end
            return
        end
        local bs = s.powerBorderSize or 1
        if bs <= 0 then
            d.powerBorderFrame:Hide()
            return
        end
        local bc = s.powerBorderColor
        local ba = s.powerBorderAlpha or 1
        PP.UpdateBorder(d.powerBorderFrame, bs, bc.r, bc.g, bc.b, ba)
        d.powerBorderFrame:Show()
        local ppC = PP.GetBorders(d.powerBorderFrame)
        if ppC then
            if style == "divider" then
                if ppC._bottom then ppC._bottom:SetAlpha(0) end
                if ppC._left then ppC._left:SetAlpha(0) end
                if ppC._right then ppC._right:SetAlpha(0) end
                if ppC._top then ppC._top:SetAlpha(ba) end
            else -- "border"
                if ppC._top then ppC._top:SetAlpha(ba) end
                if ppC._bottom then ppC._bottom:SetAlpha(ba) end
                if ppC._left then ppC._left:SetAlpha(ba) end
                if ppC._right then ppC._right:SetAlpha(ba) end
            end
        end
    end
    UpdatePowerBorder()
    d.UpdatePowerBorder = UpdatePowerBorder

    -- Tooltip handlers
    button:HookScript("OnEnter", function(self)
        local fd = GetFFD(self)
        fd._hovered = true
        if fd.ApplyBorderColor then fd.ApplyBorderColor() end
        -- Read through the party-aware proxy (like every other render path), not
        -- raw db.profile -- otherwise party_<key> overrides written by a custom
        -- party "Range & Tooltip" section are never seen and the toggle (and its
        -- in-combat sub-toggle) appear to do nothing on party frames.
        local s = fd._isParty and ns._scaledPartyProxy or ns._scaledProfile
        if not s.showTooltip then return end
        if inCombat and not s.tooltipInCombat then return end
        local u = self:GetAttribute("unit")
        if u and UnitExists(u) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            -- Populate with a freshly-built clean literal token (matched by GUID)
            -- rather than the secure unit attribute. A literal "raidN"/"partyN"/
            -- "player" string we construct here does not carry the secure-frame
            -- origin that makes GameTooltip:GetUnit() return a secret value, so
            -- external tooltip addons (which read GetUnit) can resolve the unit
            -- and add their lines. GUID-matched, so never the wrong person; falls
            -- back to the attribute when no clean token can be derived.
            local tip, g = u, UnitGUID(u)
            if g and not (issecretvalue and issecretvalue(g)) then
                if UnitGUID("player") == g then
                    tip = "player"
                elseif IsInRaid() then
                    for i = 1, GetNumGroupMembers() do
                        local tk = "raid" .. i
                        local tg = UnitGUID(tk)
                        if tg and not (issecretvalue and issecretvalue(tg)) and tg == g then tip = tk; break end
                    end
                else
                    for i = 1, GetNumSubgroupMembers() do
                        local tk = "party" .. i
                        local tg = UnitGUID(tk)
                        if tg and not (issecretvalue and issecretvalue(tg)) and tg == g then tip = tk; break end
                    end
                end
            end
            GameTooltip:SetUnit(tip)
            -- RaiderIO (and similar) resolve the tooltip unit via
            -- UnitTokenFromGUID(data.guid), which returns a SECRET token on our
            -- secure header frames, so their own handler bails before drawing.
            -- When the tooltip unit is still secret, hand RaiderIO our clean
            -- GUID-matched token through its public API so the score lines show.
            -- Gated on a secret/absent GetUnit() so we never double-draw when
            -- its normal path already succeeded (e.g. for the player's target).
            if _G.RaiderIO and _G.RaiderIO.ShowProfile then
                local _, ttUnit = GameTooltip:GetUnit()
                if not ttUnit or (issecretvalue and issecretvalue(ttUnit)) then
                    _G.RaiderIO.ShowProfile(GameTooltip, tip)
                end
            end
            GameTooltip:Show()
        end
    end)
    button:HookScript("OnLeave", function(self)
        local fd = GetFFD(self)
        fd._hovered = false
        if fd.ApplyBorderColor then fd.ApplyBorderColor() end
        GameTooltip:Hide()
    end)

    -- Private auras: re-anchor whenever the secure header reassigns this button's
    -- unit. Blizzard's recent change drops the private-aura anchors on unit
    -- reassignment (member join/leave, sort, zone-in) even when the unit token
    -- string is unchanged, so the roster-event RebuildUnitMap path -- which
    -- re-registers only when the token CHANGES -- can leave the anchor dropped
    -- and the auras showing inconsistently. OnAttributeChanged is the reliable
    -- per-button signal that fires on exactly those reassignments, so we
    -- re-register from it. HookScript (never SetScript) preserves the secure
    -- header's own attribute handlers; the helpers are referenced through ns
    -- because they are defined later in the file.
    button:HookScript("OnAttributeChanged", function(self, name)
        if name ~= "unit" then return end
        local u = self:GetAttribute("unit")
        if u and UnitExists(u) then
            -- Repaint + remap the instant the secure header (re)assigns this
            -- button. OnAttributeChanged is the reliable per-button signal
            -- (RebuildUnitMap is not -- see above), so a late assignment that
            -- lands after the roster-timer rebuild already read the buttons can
            -- never leave this one blank, nor route its live events to a stale
            -- button, until the next roster change. Only fires for buttons whose
            -- unit actually changed, so it stays bounded to the units that moved.
            local d = GetFFD(self)
            if d._isParty then ns._partyUnitToButton[u] = self else unitToButton[u] = self end
            if ns._RefreshAssignedButton then ns._RefreshAssignedButton(self, u) end
            if ns._UpdateButtonRange then ns._UpdateButtonRange(u, self) end
            if C_UnitAuras_AddPrivateAuraAnchor and ns._RegisterPrivateAuras then ns._RegisterPrivateAuras(self, u) end
        elseif ns._UnregisterPrivateAuras then
            ns._UnregisterPrivateAuras(self)
        end
    end)

    -- Secure click: left=target, right=menu
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("type1", "target")
    button:SetAttribute("type2", "togglemenu")
    -- Wildcard fallbacks so target + context menu always survive even if the
    -- click-cast engine later clears the explicit type1/type2 (e.g. on a
    -- disable transition). Right-click must never break.
    button:SetAttribute("*type1", "target")
    button:SetAttribute("*type2", "togglemenu")

    -- Hover ping support. Without this, a mouseover ping over our frame falls
    -- through to the 3D world behind it, because the ping system only targets a
    -- unit when the moused-over frame is flagged as a ping receiver. The recipe
    -- is: mix in the pingable-unit type, set the secure "ping-receiver"
    -- attribute, and resolve the target GUID live from our own "unit" attribute
    -- (the same source every update path reads), so it always tracks the current
    -- occupant after sorts and roster changes. Returning nil when there is no
    -- unit lets the ping correctly fall through. The GUID can be a secret value
    -- in Midnight: it is handed to the ping system raw and must never be guarded
    -- or stringified. button is a frame we spawned (our own secure template), so
    -- mixing in and adding the resolver method is safe here. Runs once per button
    -- via the d.styled guard, at creation out of combat, beside the type1/type2
    -- secure attributes above.
    if PingableType_UnitFrameMixin then
        Mixin(button, PingableType_UnitFrameMixin)
        button:SetAttribute("ping-receiver", true)
        button.GetTargetPingGUID = function(self)
            local u = self:GetAttribute("unit")
            if u and UnitExists(u) then
                return UnitGUID(u)
            end
        end
    end

    -- Register for click-casting (EUI built-in system)
    if ns.CC_RegisterFrame then
        ns.CC_RegisterFrame(button)
    elseif ClickCastFrames then
        ClickCastFrames[button] = true
    end

    -- Buff manager indicators
    if ns.BM_CreateIndicators then
        ns.BM_CreateIndicators(button, health, d, PP)
        if ns.BM_AnchorIndicators then
            ns.BM_AnchorIndicators(d, health, s)
        end
    end
end

-------------------------------------------------------------------------------
--  Update all visual elements for a single button
-------------------------------------------------------------------------------
local function UpdateButton(button)
    local unit = button:GetAttribute("unit")
    if not unit or not UnitExists(unit) then
        button:SetAlpha(0)
        return
    end

    local d = GetFFD(button)
    if not d.styled then return end

    local s = d._isParty and ns._scaledPartyProxy or ns._scaledProfile
    -- Restore alpha respecting BM frame alpha + range alpha.
    -- If rangeAlpha is nil, it's managed by the secret-safe SetAlphaFromBoolean
    -- path -- don't override it here or we'd flash full alpha until the next
    -- range ticker run (0.2s).
    if d.rangeAlpha then
        local baseA = button._bmSavedAlpha or 1
        button:SetAlpha(baseA * d.rangeAlpha)
    end

    -- Health (percent-based, secret-value safe)
    -- Smooth bar interpolation
    local smooth = s.smoothBars and Enum and Enum.StatusBarInterpolation
        and Enum.StatusBarInterpolation.ExponentialEaseOut

    local health = d.health
    if health then
        local pct = GetSafeHealthPercent(unit)
        health:SetMinMaxValues(0, 100)
        if smooth then
            health:SetValue(pct, smooth)
        else
            health:SetValue(pct)
        end

        local r, g, b = GetHealthColor(unit, s)
        local fillTex = health:GetStatusBarTexture()
        if s.healthColorMode == "dark" then
            health:SetStatusBarColor(r, g, b, 1)
            if fillTex then fillTex:SetAlpha(DARK_FILL_A) end
        else
            if fillTex then fillTex:SetAlpha(1) end
            health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
        end
    end

    -- Background
    if d.bg then
        if s.healthColorMode == "dark" then
            -- BG only covers missing health portion, matching UF dark mode
            d.bg:ClearAllPoints()
            d.bg:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
            d.bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            d.bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, 1)
        else
            -- BG only covers the missing-health portion (anchored to the fill's
            -- right edge), never behind the fill. A full-width bg behind the fill
            -- bleeds through when the range fade's secret alpha under-renders the
            -- fill -> the OOR "blend". This matches EUI's Dark mode and ouF based
            -- Unit Frame addons so behavior is familiar to users.
            d.bg:ClearAllPoints()
            d.bg:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
            d.bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            local bgc = s.customBgColor
            d.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
        end
    end

    -- Power (filtered by role + hide if unit has no power)
    local power = d.power
    if power then
        local role = ns._ResolvePowerRole(unit)
        local showForRole = (role == "HEALER" and s.powerShowForHealer)
            or (role == "TANK" and s.powerShowForTank)
            or (role == "DAMAGER" and s.powerShowForDPS)
            or (role == "NONE" and s.powerShowForDPS)
        local pType = UnitPowerType(unit) or 0
        -- maxPower can be a secret number in group context (12.0.7+); never compare
        -- it in Lua. Only treat the unit as powerless on a CLEAN zero max.
        local pmx = UnitPowerMax(unit, pType)
        local cleanNoPower = (not issecretvalue(pmx)) and (not pmx or pmx == 0)
        local hidePower = not showForRole or cleanNoPower

        if hidePower then
            power:Hide()
            if d.powerBorderFrame then d.powerBorderFrame:Hide() end
            -- Expand health bar to full frame height
            if d.health then
                d.health:SetHeight(PixelSnap(s.frameHeight or 46))
            end
        else
            -- Restore health bar height with power bar space
            local powerH = PixelSnap(s.powerHeight or 4)
            if d.health then
                d.health:SetHeight(PixelSnap((s.frameHeight or 46) - powerH))
            end
            -- Was the bar already visible before this update? Smooth
            -- interpolation only animates correctly on a bar that was already
            -- shown last frame. On a fresh hidden->shown transition (e.g. a
            -- profile swap where ReloadFrames hides the bar and replaces its
            -- fill texture), animating in the same frame leaves the fill at 0.
            -- Snap the value plainly on first show; smooth only after that.
            local wasShown = power:IsShown()
            power:Show()
            if d.UpdatePowerBorder then d.UpdatePowerBorder() end
            local smoothPower = wasShown and s.smoothPowerBars and Enum
                and Enum.StatusBarInterpolation
                and Enum.StatusBarInterpolation.ExponentialEaseOut
            -- Percent-based, secret-safe (mirrors the health bar). UnitPower/
            -- UnitPowerMax can be secret numbers in group context (12.0.7+) and
            -- cannot be fed to SetMinMaxValues; UnitPowerPercent evaluates the
            -- secret on the C side against ScaleTo100 and returns a clean 0-100.
            power:SetMinMaxValues(0, 100)
            local ppct = UnitPowerPercent(unit, pType, true, CurveConstants.ScaleTo100)
            if smoothPower then
                power:SetValue(ppct, smoothPower)
            else
                power:SetValue(ppct)
            end
            local pr, pg, pb = GetPowerColor(unit)
            power:SetStatusBarColor(pr, pg, pb, 1)
        end
    end

    -- Absorb
    UpdateAbsorb(button, unit)

    -- Name
    if d.nameText then
        d.nameText:SetText(ResolveDisplayName(unit))
        local nr, ng, nb = GetNameColor(unit, s)
        d.nameText:SetTextColor(nr, ng, nb)
    end

    -- Health text
    if d.healthText then
        local mode = s.healthTextMode or "none"
        -- Hide the health %/value while the unit is dead or offline -- the status
        -- text shows DEAD/OFFLINE there instead. UnitIsDeadOrGhost/UnitIsConnected
        -- return clean booleans for group units in Midnight (only UnitIsAFK can be secret),
        -- so they're safe in a conditional with no issecretvalue guard.
        if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
            d.healthText:SetText("")
        elseif mode == "percent" then
            local pct = GetSafeHealthPercent(unit)
            d.healthText:SetFormattedText("%.0f%%", pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            d.healthText:SetTextColor(htr, htg, htb, 0.9)
        elseif mode == "percentNoSign" then
            local pct = GetSafeHealthPercent(unit)
            d.healthText:SetFormattedText("%.0f", pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            d.healthText:SetTextColor(htr, htg, htb, 0.9)
        elseif mode == "number" then
            local curr = UnitHealth(unit, true)
            if curr and AbbreviateNumbers then
                d.healthText:SetText(AbbreviateNumbers(curr))
            elseif curr then
                d.healthText:SetFormattedText("%s", curr)
            end
            local htr, htg, htb = GetHealthTextColor(unit, s)
            d.healthText:SetTextColor(htr, htg, htb, 0.9)
        elseif mode == "numberPercent" then
            local curr = UnitHealth(unit, true)
            local pct = GetSafeHealthPercent(unit)
            local numStr = (curr and AbbreviateNumbers) and AbbreviateNumbers(curr) or tostring(curr or 0)
            d.healthText:SetFormattedText("%s | %.0f%%", numStr, pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            d.healthText:SetTextColor(htr, htg, htb, 0.9)
        elseif mode == "percentNumber" then
            local curr = UnitHealth(unit, true)
            local pct = GetSafeHealthPercent(unit)
            local numStr = (curr and AbbreviateNumbers) and AbbreviateNumbers(curr) or tostring(curr or 0)
            d.healthText:SetFormattedText("%.0f%% | %s", pct, numStr)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            d.healthText:SetTextColor(htr, htg, htb, 0.9)
        else
            d.healthText:SetText("")
        end
    end

    -- Status text (DEAD / OFFLINE / AFK -- always shown, own position/size/color)
    if d.statusText then
        local stc = s.statusTextColor or { r = 1, g = 1, b = 1 }
        if s.statusTextPosition == "none" then
            d.statusText:Hide()
        elseif UnitIsDeadOrGhost(unit) then
            d.statusText:SetText("DEAD")
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            d.statusText:Show()
        elseif not UnitIsConnected(unit) then
            d.statusText:SetText("OFFLINE")
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            d.statusText:Show()
        elseif s.statusShowAFK and UnitIsAFK and not issecretvalue(UnitIsAFK(unit)) and UnitIsAFK(unit) then
            d.statusText:SetText("AFK")
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            d.statusText:Show()
        else
            d.statusText:Hide()
        end
    end

    -- Dead/DC overlay
    if UnitIsDeadOrGhost(unit) then
        if health then health:SetStatusBarColor(0.3, 0.3, 0.3, 0.5) end
    elseif not UnitIsConnected(unit) then
        if health then health:SetStatusBarColor(0.3, 0.3, 0.3, 0.3) end
    end

    -- Role icon
    if d.roleIcon then
        local style = s.roleIconStyle or "modern"
        if style ~= "none" then
            local role = UnitGroupRolesAssigned(unit)
            if role and not issecretvalue(role) then
                local showForRole = (role == "TANK" and s.showRoleForTank)
                    or (role == "HEALER" and s.showRoleForHealer)
                    or (role == "DAMAGER" and s.showRoleForDPS)
                if showForRole and ApplyRoleIcon(d.roleIcon, role, style) then
                    d.roleIcon:Show()
                else
                    d.roleIcon:Hide()
                end
            else
                d.roleIcon:Hide()
            end
        else
            d.roleIcon:Hide()
        end
    end

    -- Leader/assistant icon
    if d.leaderIcon then
        if s.showLeaderIcon then
            local isLeader = UnitIsGroupLeader(unit)
            local isAssist = UnitIsGroupAssistant(unit)
            if isLeader and not issecretvalue(isLeader) then
                d.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
                d.leaderIcon:SetTexCoord(0, 1, 0, 1)
                d.leaderIcon:Show()
            elseif isAssist and not issecretvalue(isAssist) then
                d.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
                d.leaderIcon:SetTexCoord(0, 1, 0, 1)
                d.leaderIcon:Show()
            else
                d.leaderIcon:Hide()
            end
        else
            d.leaderIcon:Hide()
        end
    end

    -- Raid marker
    if d.raidMarker then
        if s.showRaidMarker then
            local idx = GetRaidTargetIndex(unit)
            if idx then
                if issecretvalue(idx) then
                    -- Secret-safe path: use SetSpriteSheetCell for secret marker index
                    d.raidMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
                    if d.raidMarker.SetSpriteSheetCell then
                        pcall(d.raidMarker.SetSpriteSheetCell, d.raidMarker, idx, 4, 4, 64, 64)
                    end
                    d.raidMarker:Show()
                elseif RAID_MARKER_TEXCOORDS[idx] then
                    local tc = RAID_MARKER_TEXCOORDS[idx]
                    d.raidMarker:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
                    d.raidMarker:Show()
                else
                    d.raidMarker:Hide()
                end
            else
                d.raidMarker:Hide()
            end
        else
            d.raidMarker:Hide()
        end
    end

    -- Target state: recolor the single border ONLY when the target actually
    -- changes for this button (hover takes priority in ApplyBorderColor). Firing
    -- only on a real transition keeps the recolor + level work off the per-update
    -- hot path -- no work on a plain UNIT_HEALTH/UNIT_AURA tick. Both operands are
    -- clean booleans, so the compare never touches a secret value.
    do
        local isTarget = UnitIsUnit(unit, "target")
        local newTarget = (isTarget and not issecretvalue(isTarget)) and true or false
        if newTarget ~= d._isTarget then
            d._isTarget = newTarget
            if d.ApplyBorderColor then d.ApplyBorderColor() end
        end
    end

    -- Threat border (red aggro highlight); size 0 = disabled
    if d.threatFrame then
        local bs = s.threatBorderSize or 0
        if bs > 0 then
            local status = UnitThreatSituation(unit)
            if status and THREAT_ACTIVE[status] and PP then
                PP.UpdateBorder(d.threatFrame, bs, 1, 0, 0, 1)
                d.threatFrame:Show()
            else
                d.threatFrame:Hide()
            end
        else
            d.threatFrame:Hide()
        end
    end
end

-------------------------------------------------------------------------------
--  Aura scanning (secret-value safe, incremental via UNIT_AURA payload)
--  Uses C_UnitAuras.IsAuraFilteredOutByInstanceID() with Blizzard-defined
--  filter strings instead of reading isBossAura / isFromPlayerOrPlayerPet
--  (which are secret booleans on other players in Midnight).
--
--  Performance: on incremental UNIT_AURA updates, only processes the delta
--  (added/updated/removed auras) instead of rescanning all HARMFUL auras.
--  Full scan only on isFullUpdate or first call for a button.
-------------------------------------------------------------------------------
local C_UnitAuras_GetAuraDataByAuraInstanceID = C_UnitAuras.GetAuraDataByAuraInstanceID
local C_UnitAuras_IsAuraFilteredOutByInstanceID = C_UnitAuras.IsAuraFilteredOutByInstanceID

-- Sated/Exhaustion spell IDs (lust debuff variants)
local SATED_DEBUFFS = {
    [57723]  = true,  -- Exhaustion (Heroism)
    [57724]  = true,  -- Sated (Bloodlust)
    [80354]  = true,  -- Temporal Displacement (Time Warp)
    [95809]  = true,  -- Insanity (Ancient Hysteria)
    [160455] = true,  -- Fatigued (Netherwinds)
    [264689] = true,  -- Fatigued (Primal Rage)
    [390435] = true,  -- Exhaustion (Fury of the Aspects)
    [428628] = true,  -- Exhaustion (variant)
}

-- Debuff filter check based on user setting
local function IsDisplayDebuff(unit, auraData)
    local iid = auraData.auraInstanceID
    if not iid then return false end
    local s = db and db.profile
    local mode = s and s.debuffFilter or "all"
    if mode == "none" then return false end

    -- Sated blacklist (secret-safe: skip check if spellId is secret)
    if s and s.hideLustDebuff then
        local sid = auraData.spellId
        if sid and not issecretvalue(sid) and SATED_DEBUFFS[sid] then
            return false
        end
    end

    if mode == "all" then return true end
    if not C_UnitAuras_IsAuraFilteredOutByInstanceID then return true end
    if mode == "raid" then
        return not C_UnitAuras_IsAuraFilteredOutByInstanceID(unit, iid, "HARMFUL|RAID")
            or not C_UnitAuras_IsAuraFilteredOutByInstanceID(unit, iid, "HARMFUL|RAID_IN_COMBAT")
    elseif mode == "dispellable" then
        return not C_UnitAuras_IsAuraFilteredOutByInstanceID(unit, iid, "HARMFUL|RAID_PLAYER_DISPELLABLE")
    end
    return true
end

-- Apply a single debuff's visual data to an icon frame
local function ApplyDebuffIcon(icon, auraData, unit, s)
    -- SetTexture accepts secret values natively (GPU renders correctly)
    local tex = auraData.icon
    if tex then
        icon._tex:SetTexture(tex)
    else
        icon._tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Border (dispel-type colored or user default)
    local borderSz = s.debuffBorderSize or 1
    if icon._borderFrame and PP then
        if borderSz > 0 then
            local dispelName = auraData.dispelName
            local dc
            if dispelName and not issecretvalue(dispelName) then
                dc = GetDispelColor(dispelName, s)
            end
            if dc then
                PP.UpdateBorder(icon._borderFrame, borderSz, dc.r, dc.g, dc.b, 1)
            else
                local bc = s.debuffBorderColor or { r=0, g=0, b=0 }
                PP.UpdateBorder(icon._borderFrame, borderSz, bc.r, bc.g, bc.b, 1)
            end
            icon._borderFrame:Show()
        else
            icon._borderFrame:Hide()
        end
    end

    -- Duration swipe + text (secret-safe via DurationObject + GetCountdownFontString)
    if icon._cooldown then
        local wantSwipe = s.debuffShowSwipe
        local wantDurText = s.debuffShowDurText
        if wantSwipe or wantDurText then
            local iid = auraData.auraInstanceID
            if iid and not issecretvalue(iid) and C_UnitAuras.GetAuraDuration then
                local durObj = C_UnitAuras.GetAuraDuration(unit, iid)
                if durObj then
                    icon._cooldown:SetCooldownFromDurationObject(durObj)
                end
            else
                local dur = auraData.duration
                local exp = auraData.expirationTime
                if dur and exp and not issecretvalue(dur) and not issecretvalue(exp) and dur > 0 then
                    icon._cooldown:SetCooldown(exp - dur, dur)
                end
            end
            icon._cooldown:SetDrawSwipe(wantSwipe)
            icon._cooldown:SetHideCountdownNumbers(not wantDurText)
            icon._cooldown:Show()
            -- Style the built-in countdown text via GetCountdownFontString
            if wantDurText then
                local cdText = icon._cooldown.GetCountdownFontString and icon._cooldown:GetCountdownFontString()
                if cdText then
                    local dtc = s.debuffDurTextColor or { r = 1, g = 1, b = 1 }
                    local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
                    cdText:SetFont(fp, s.debuffDurTextSize or 8, "OUTLINE")
                    cdText:SetTextColor(dtc.r, dtc.g, dtc.b)
                    cdText:ClearAllPoints()
                    cdText:SetPoint("CENTER", icon, "CENTER", s.debuffDurTextOffsetX or 0, s.debuffDurTextOffsetY or 0)
                end
            end
        else
            icon._cooldown:Hide()
        end
    end

    -- Stacks (secret-safe via Blizzard API)
    if icon._count then
        if s.debuffShowStacks and C_UnitAuras.GetAuraApplicationDisplayCount then
            local stackText = C_UnitAuras.GetAuraApplicationDisplayCount(
                unit, auraData.auraInstanceID, 2, 99)
            if stackText then
                icon._count:SetText(stackText)
            else
                icon._count:SetText("")
            end
        else
            icon._count:SetText("")
        end
    end

    icon:Show()
end

-- Render the cached debuff list to icon frames
local function RenderDebuffs(d, s, unit)
    local debuffCache = d.debuffCache
    local cap = s.debuffCap or 3
    local shown = 0

    -- Apply font/position settings once per render (not per-aura)
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
    for _, icon in ipairs(d.debuffIcons) do
        -- Stacks font
        if icon._count and s.debuffShowStacks then
            local stc = s.debuffStacksTextColor or { r=1, g=1, b=1 }
            icon._count:SetFont(fontPath, s.debuffStacksTextSize or 8, "OUTLINE")
            icon._count:SetTextColor(stc.r, stc.g, stc.b)
            icon._count:ClearAllPoints()
            icon._count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT",
                1 + (s.debuffStacksOffsetX or 0), -1 + (s.debuffStacksOffsetY or 0))
        end
    end

    if debuffCache then
        for _, auraData in ipairs(debuffCache) do
            if shown >= cap then break end
            shown = shown + 1
            local icon = d.debuffIcons[shown]
            if icon then
                ApplyDebuffIcon(icon, auraData, unit, s)
            end
        end
    end
    for j = shown + 1, #d.debuffIcons do
        local icon = d.debuffIcons[j]
        icon:Hide()
        if icon._durText and ns.UnregisterDurText then ns.UnregisterDurText(icon._durText) end
    end

    -- CENTER growth: re-anchor based on actual visible count
    if (s.debuffGrowDirection or "RIGHT") == "CENTER" and d.AnchorDebuffs then
        d.AnchorDebuffs(shown)
    end
end

-- Full scan: rebuild debuff cache from scratch
local function FullScanDebuffs(d, unit)
    if not d.debuffCache then d.debuffCache = {} end
    wipe(d.debuffCache)
    d.debuffInstanceMap = d.debuffInstanceMap or {}
    wipe(d.debuffInstanceMap)
    local i = 1
    while true do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
        if not auraData then break end
        i = i + 1
        if IsDisplayDebuff(unit, auraData) then
            local idx = #d.debuffCache + 1
            d.debuffCache[idx] = auraData
            d.debuffInstanceMap[auraData.auraInstanceID] = idx
        end
    end
end

local function UpdateDebuffs(button, unit, updateInfo)
    local d = GetFFD(button)
    if not d.debuffIcons then return end
    local s = d._isParty and ns._scaledPartyProxy or ns._scaledProfile

    if s.debuffFilter == "none" then
        for _, icon in ipairs(d.debuffIcons) do icon:Hide() end
        if d.debuffCache then wipe(d.debuffCache) end
        return
    end

    local needFullScan = not d.debuffCache
        or not updateInfo
        or (updateInfo.isFullUpdate)

    if needFullScan then
        FullScanDebuffs(d, unit)
    else
        -- Incremental update
        local cache = d.debuffCache
        local imap = d.debuffInstanceMap or {}

        -- Removed auras
        if updateInfo.removedAuraInstanceIDs then
            for _, iid in ipairs(updateInfo.removedAuraInstanceIDs) do
                local idx = imap[iid]
                if idx then
                    imap[iid] = nil
                    table.remove(cache, idx)
                    -- Rebuild index map after removal
                    for ci = idx, #cache do
                        imap[cache[ci].auraInstanceID] = ci
                    end
                end
            end
        end

        -- Added auras (payload contains full auraData)
        if updateInfo.addedAuras then
            for _, auraData in ipairs(updateInfo.addedAuras) do
                -- addedAuras contains both helpful and harmful; verify harmful
                -- via filter API (isHarmful is secret on other players)
                local iid = auraData.auraInstanceID
                if iid and C_UnitAuras_IsAuraFilteredOutByInstanceID
                    and not C_UnitAuras_IsAuraFilteredOutByInstanceID(unit, iid, "HARMFUL")
                    and IsDisplayDebuff(unit, auraData) then
                    local idx = #cache + 1
                    cache[idx] = auraData
                    imap[auraData.auraInstanceID] = idx
                end
            end
        end

        -- Updated auras
        if updateInfo.updatedAuraInstanceIDs then
            for _, iid in ipairs(updateInfo.updatedAuraInstanceIDs) do
                local idx = imap[iid]
                if idx then
                    local fresh = C_UnitAuras_GetAuraDataByAuraInstanceID(unit, iid)
                    if fresh then
                        cache[idx] = fresh
                    end
                end
            end
        end

        d.debuffInstanceMap = imap
    end

    RenderDebuffs(d, s, unit)
end

-------------------------------------------------------------------------------
--  Defensive/external aura detection and rendering
--  Scans HELPFUL auras, tests against EXTERNAL_DEFENSIVE and BIG_DEFENSIVE
--  filters, renders matching icons with secret-safe cooldown swipe.
-------------------------------------------------------------------------------
local C_UnitAuras_GetAuraDuration = C_UnitAuras and C_UnitAuras.GetAuraDuration

local function UpdateDefensives(button, unit, updateInfo)
    local d = GetFFD(button)
    if not d.defIcons then return end
    local s = d._isParty and ns._scaledPartyProxy or ns._scaledProfile

    local showDef = s.showDefensives
    local showExt = s.showExternals
    if not showDef and not showExt then
        for _, icon in ipairs(d.defIcons) do
            icon:Hide()
            if icon._durText then
                icon._durText:Hide()
                if ns.UnregisterDurText then ns.UnregisterDurText(icon._durText) end
            end
        end
        d.defActiveIDs = nil
        return
    end

    -- Incremental: skip full HELPFUL scan if no relevant auras changed
    if updateInfo and not updateInfo.isFullUpdate and d.defActiveIDs then
        local needRescan = false
        if updateInfo.addedAuras then
            for _, aura in ipairs(updateInfo.addedAuras) do
                if aura.isHelpful ~= false then needRescan = true; break end
            end
        end
        if not needRescan and updateInfo.removedAuraInstanceIDs then
            for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
                if d.defActiveIDs[id] then needRescan = true; break end
            end
        end
        if not needRescan and updateInfo.updatedAuraInstanceIDs then
            for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
                if d.defActiveIDs[id] then needRescan = true; break end
            end
        end
        if not needRescan then return end
    end

    -- Scan all HELPFUL auras for defensive matches.
    -- BIG_DEFENSIVE includes both self-defensives AND externals.
    -- EXTERNAL_DEFENSIVE only includes externals cast by other players.
    -- When only Defensives is on, exclude auras that pass EXTERNAL_DEFENSIVE.
    if not d.defActiveIDs then d.defActiveIDs = {} else wipe(d.defActiveIDs) end
    local shown = 0
    local defSz = s.defSize or 22
    local defBdrSz = s.defBorderSize or 1
    local defBdrC = s.defBorderColor or { r = 0, g = 0, b = 0 }
    local PP2 = PP

    local idx = 1
    while true do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, idx, "HELPFUL")
        if not auraData then break end
        idx = idx + 1
        if shown >= #d.defIcons then break end

        local iid = auraData.auraInstanceID
        if iid and C_UnitAuras_IsAuraFilteredOutByInstanceID then
            local isExternal = not C_UnitAuras_IsAuraFilteredOutByInstanceID(unit, iid, "HELPFUL|EXTERNAL_DEFENSIVE")
            local isBigDef   = not C_UnitAuras_IsAuraFilteredOutByInstanceID(unit, iid, "HELPFUL|BIG_DEFENSIVE")
            local isSelfDef  = isBigDef and not isExternal

            local isDefensive = (showExt and isExternal) or (showDef and isSelfDef)

            if isDefensive then
                d.defActiveIDs[iid] = true
                shown = shown + 1
                local icon = d.defIcons[shown]
                icon:SetSize(defSz, defSz)

                -- Icon texture (SetTexture accepts secret values natively)
                local tex = auraData.icon
                if tex then
                    icon._tex:SetTexture(tex)
                else
                    icon._tex:SetTexture(136243)
                end

                -- Duration swipe + text (secret-safe via DurationObject + GetCountdownFontString)
                local cd = icon._cooldown
                if cd then
                    local wantSwipe = s.defShowSwipe ~= false
                    local wantDurText = s.defShowDurText
                    if wantSwipe or wantDurText then
                        if C_UnitAuras_GetAuraDuration and cd.SetCooldownFromDurationObject then
                            local durObj = C_UnitAuras_GetAuraDuration(unit, iid)
                            if durObj then
                                cd:SetCooldownFromDurationObject(durObj)
                            else
                                cd:Clear()
                            end
                        end
                        cd:SetDrawSwipe(wantSwipe)
                        cd:SetHideCountdownNumbers(not wantDurText)
                        cd:Show()
                        -- Style the built-in countdown text via GetCountdownFontString
                        if wantDurText then
                            local cdText = cd.GetCountdownFontString and cd:GetCountdownFontString()
                            if cdText then
                                local dtc = s.defDurTextColor or { r = 1, g = 1, b = 1 }
                                local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
                                cdText:SetFont(fp, s.defDurTextSize or 8, "OUTLINE")
                                cdText:SetTextColor(dtc.r, dtc.g, dtc.b)
                                cdText:ClearAllPoints()
                                cdText:SetPoint("CENTER", icon, "CENTER", s.defDurTextOffsetX or 0, s.defDurTextOffsetY or 0)
                            end
                        end
                    else
                        cd:Hide()
                    end
                end

                -- Border
                if icon._borderFrame and PP2 then
                    if defBdrSz > 0 then
                        PP2.UpdateBorder(icon._borderFrame, defBdrSz, defBdrC.r, defBdrC.g, defBdrC.b, 1)
                        icon._borderFrame:Show()
                    else
                        icon._borderFrame:Hide()
                    end
                end

                icon:Show()
            end
        end
    end

    -- Hide unused icons + unregister duration texts
    for j = shown + 1, #d.defIcons do
        local icon = d.defIcons[j]
        icon:Hide()
        if icon._durText then
            icon._durText:Hide()
            if ns.UnregisterDurText then ns.UnregisterDurText(icon._durText) end
        end
    end

    -- CENTER growth: re-anchor based on actual visible count
    if (s.defGrowDirection or "CENTER") == "CENTER" and d.AnchorDefensives then
        d.AnchorDefensives(shown)
    end
end

-------------------------------------------------------------------------------
--  Dispel detection (secret-value safe)
--  Handles border, overlay (fill/full/gradient), and type icon.
-------------------------------------------------------------------------------
local function HideDispelVisuals(d)
    if d.dispelFrame then d.dispelFrame:Hide() end
    if d.dispelOLTex then d.dispelOLTex:Hide() end
    if d.dispelIcon then d.dispelIcon:Hide() end
end

local function ApplyDispelOverlay(d, dc, s)
    local olTex = d.dispelOLTex
    if not olTex then return end
    local mode = s.dispelOverlay or "fill"
    if mode == "none" then olTex:Hide(); return end

    local alpha = (s.dispelOverlayOpacity or 100) / 100
    local health = d.dispelOLHealth or d.health

    olTex:ClearAllPoints()
    -- Reset any prior vertex tint so the fill/full SetColorTexture paths render
    -- their explicit color cleanly (the gradient path below tints via vertex color).
    olTex:SetVertexColor(1, 1, 1, 1)

    if mode == "fill" then
        -- Cover only the filled health portion
        if health then
            local fillTex = health:GetStatusBarTexture()
            if fillTex then
                olTex:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
                olTex:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 0)
            else
                olTex:SetAllPoints(health)
            end
        end
        olTex:SetColorTexture(dc.r, dc.g, dc.b, alpha)
    elseif mode == "full" then
        -- Cover the entire health bar area
        if health then
            olTex:SetAllPoints(health)
        end
        olTex:SetColorTexture(dc.r, dc.g, dc.b, alpha)
    elseif mode == "gradient" then
        -- Pre-baked vertical gradient texture (solid at the top, fading to
        -- transparent at the bottom) tinted with the dispel color. SetVertexColor
        -- passes the (secret) dispel-type color through natively; the texture's own
        -- alpha supplies the fade. WHITE8X8 + SetGradient + CreateColor errors here
        -- because CreateColor cannot wrap a secret color value.
        if health then
            olTex:SetAllPoints(health)
        end
        olTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-tb.tga")
        olTex:SetVertexColor(dc.r, dc.g, dc.b, alpha)
    end
    olTex:Show()
end

local function ApplyDispelIcon(d, unit, iid)
    local icon = d.dispelIcon
    if not icon or not d.dispelIconTextures then return end
    -- Drive each per-type icon by its alpha curve; only the matching dispel type
    -- ends up with alpha 1. Secret-safe: the (secret) color/alpha is passed
    -- straight to SetVertexColor and never read.
    local getColor = C_UnitAuras.GetAuraDispelTypeColor
    local shownAny = false
    for idx, tex in pairs(d.dispelIconTextures) do
        local curve = iid and ns._GetDispelIconCurve(idx)
        local col = curve and getColor and getColor(unit, iid, curve)
        if col then
            tex:SetVertexColor(col:GetRGBA())
            tex:Show()
            shownAny = true
        else
            tex:Hide()
        end
    end
    -- Fallback: the dispel type could not be resolved (e.g. a secret/hidden boss
    -- debuff where GetAuraDispelTypeColor returns nil). Mirror the highlight's
    -- Magic fallback (UpdateDispelBorder uses GetDispelColor("Magic") in the same
    -- case) so the type icon never vanishes while the border/overlay still show.
    -- `col` existence is a clean (non-secret) check, so shownAny is clean.
    if not shownAny and d.dispelIconTextures[1] then
        d.dispelIconTextures[1]:SetVertexColor(1, 1, 1, 1)
        d.dispelIconTextures[1]:Show()
    end
    icon:Show()
end

-------------------------------------------------------------------------------
--  Private aura container management (12.0.5+)
--  Dispel container: registers an isContainer=true anchor on a wrapper frame
--  so Blizzard renders its native dispel gradient for private auras.
--  Per-slot private auras: registers isContainer=false anchors for individual
--  boss debuff icon display.
-------------------------------------------------------------------------------

-- Register the dispel container anchor for a button's unit
local function RegisterDispelContainer(button, unit)
    if not C_UnitAuras_AddPrivateAuraAnchor then return end
    local d = GetFFD(button)
    local wrapper = d.dispelContainer
    if not wrapper then return end

    -- Remove old anchor if unit changed
    if d.dispelContainerAnchorID then
        C_UnitAuras_RemovePrivateAuraAnchor(d.dispelContainerAnchorID)
        d.dispelContainerAnchorID = nil
    end

    if not unit or not UnitExists(unit) then return end

    -- Set group type from unit token
    local groupType = unit:find("^party") and 4 or 5
    wrapper:SetAttribute("group-type", groupType)
    -- Re-apply dispel mode (follows dispelShowAll; runs on reload so the toggle takes effect)
    local s = (groupType == 4) and ns._scaledPartyProxy or ns._scaledProfile
    wrapper:SetAttribute("dispel-indicator-option", (s and s.dispelShowAll ~= false) and 2 or 1)
    wrapper:SetAttribute("update-settings", true)

    -- Apply strata fix (12.0.5 container rendering workaround)
    local parentStrata = button:GetFrameStrata()
    wrapper:SetFrameStrata(PA_STRATA_FIX[parentStrata] or "DIALOG")

    local ok, anchorID = pcall(function()
        return C_UnitAuras_AddPrivateAuraAnchor({
            unitToken     = unit,
            parent        = wrapper,
            isContainer   = true,
            auraIndex     = 1,
            showCountdownFrame   = false,
            showCountdownNumbers = false,
        })
    end)
    if ok and anchorID then
        d.dispelContainerAnchorID = anchorID
    end
    d.dispelContainerUnit = unit
end

-- Remove the dispel container anchor (cleanup)
local function UnregisterDispelContainer(button)
    if not C_UnitAuras_RemovePrivateAuraAnchor then return end
    local d = GetFFD(button)
    if d.dispelContainerAnchorID then
        C_UnitAuras_RemovePrivateAuraAnchor(d.dispelContainerAnchorID)
        d.dispelContainerAnchorID = nil
    end
    d.dispelContainerUnit = nil
    if d.dispelContainer then
        d.dispelContainer:SetAlpha(0)
    end
end

-- Hybrid visibility gate: suppress Blizzard container when our overlay is
-- handling a normal (non-private) dispellable debuff; reveal container when
-- our overlay sees nothing (private aura only Blizzard can detect).
-- Uses alpha, never Show/Hide, so the container keeps receiving aura updates while suppressed.
local function UpdateDispelContainerVisibility(button)
    if not C_UnitAuras_AddPrivateAuraAnchor then return end
    local d = GetFFD(button)
    local wrapper = d.dispelContainer
    if not wrapper then return end

    -- Our custom overlay is active = we handle this debuff, suppress container
    local ourShowing = (d.dispelFrame and d.dispelFrame:IsShown())
        or (d.dispelOLTex and d.dispelOLTex:IsShown())
    if ourShowing then
        wrapper:SetAlpha(0)
        return
    end

    -- Our overlay not showing = might be a private aura. Reveal on the next
    -- frame so the container's own pending refresh settles first, preventing a
    -- brief stale-overlay flash; re-check below since our overlay may reclaim
    -- the slot within that frame.
    C_Timer.After(0, function()
        if not wrapper then return end
        local d2 = GetFFD(button)
        if not d2 then return end
        local stillOurs = (d2.dispelFrame and d2.dispelFrame:IsShown())
            or (d2.dispelOLTex and d2.dispelOLTex:IsShown())
        if not stillOurs then
            wrapper:SetAlpha(1)
        end
    end)
end

-- Register per-slot private aura anchors for boss debuff icons
local function RegisterPrivateAuraSlots(button, unit)
    if not C_UnitAuras_AddPrivateAuraAnchor then return end
    local d = GetFFD(button)
    if not d.privateAuraFrames then return end
    if not unit or not UnitExists(unit) then return end

    -- Remove old anchors
    if d.privateAuraAnchorIDs then
        for i, aid in ipairs(d.privateAuraAnchorIDs) do
            C_UnitAuras_RemovePrivateAuraAnchor(aid)
        end
        wipe(d.privateAuraAnchorIDs)
    end

    local s = d._isParty and ns._scaledPartyProxy or ns._scaledProfile
    local health = d.health
    if not health then return end
    local sz = s.paSize or 18
    local showCD = s.paShowCountdown ~= false

    -- Independent position/growth for private auras
    local pos = s.paPosition or "bottomleft"
    local ox = s.paOffsetX or 0
    local oy = s.paOffsetY or 0
    local grow = s.paGrowDirection or "RIGHT"
    local spc = PixelSnap(s.paSpacing or 1)

    local parentStrata = button:GetFrameStrata()
    local fixedStrata = PA_STRATA_FIX[parentStrata] or "DIALOG"

    for i, paFrame in ipairs(d.privateAuraFrames) do
        paFrame:SetSize(sz, sz)
        paFrame:SetFrameStrata(fixedStrata)
        paFrame:SetFrameLevel(button:GetFrameLevel() + ns.LVL_AURA)
        paFrame:ClearAllPoints()

        if i == 1 then
            -- Private auras anchor flush to the health bar edge (no 1px inset),
            -- matching the debuff/role icon displays.
            if pos == "topleft" then
                paFrame:SetPoint("TOPLEFT", health, "TOPLEFT", ox, oy)
            elseif pos == "top" then
                paFrame:SetPoint("TOP", health, "TOP", ox, oy)
            elseif pos == "topright" then
                paFrame:SetPoint("TOPRIGHT", health, "TOPRIGHT", ox, oy)
            elseif pos == "left" then
                paFrame:SetPoint("LEFT", health, "LEFT", ox, oy)
            elseif pos == "center" then
                paFrame:SetPoint("CENTER", health, "CENTER", ox, oy)
            elseif pos == "right" then
                paFrame:SetPoint("RIGHT", health, "RIGHT", ox, oy)
            elseif pos == "bottomright" then
                paFrame:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", ox, oy)
            elseif pos == "bottom" then
                paFrame:SetPoint("BOTTOM", health, "BOTTOM", ox, oy)
            else
                paFrame:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", ox, oy)
            end
        else
            local prev = d.privateAuraFrames[i - 1]
            if grow == "RIGHT" then
                paFrame:SetPoint("LEFT", prev, "RIGHT", spc, 0)
            elseif grow == "LEFT" then
                paFrame:SetPoint("RIGHT", prev, "LEFT", -spc, 0)
            elseif grow == "UP" then
                paFrame:SetPoint("BOTTOM", prev, "TOP", 0, spc)
            elseif grow == "DOWN" then
                paFrame:SetPoint("TOP", prev, "BOTTOM", 0, -spc)
            end
        end

        paFrame:Show()

        -- Register per-slot anchor
        local iconInfoTbl = {
            iconWidth  = sz,
            iconHeight = sz,
            iconAnchor = {
                point         = "CENTER",
                relativeTo    = paFrame,
                relativePoint = "CENTER",
                offsetX       = 0,
                offsetY       = 0,
            },
        }
        -- Scale Blizzard's native border 1:1 to OUR icon size. The border art is
        -- authored for a 32px icon, so iconSize/32*2 makes it fit any size. Letting 
        -- Blizzard draw the border also means empty slots show nothing. the border
        -- only appears when Blizzard actually renders an icon there.
        iconInfoTbl.borderScale = sz / 32 * 2
        local ok, anchorID = pcall(function()
            return C_UnitAuras_AddPrivateAuraAnchor({
                unitToken     = unit,
                auraIndex     = i,
                parent        = paFrame,
                isContainer   = false,
                showCountdownFrame   = true,
                showCountdownNumbers = showCD,
                iconInfo = iconInfoTbl,
            })
        end)
        if ok and anchorID then
            d.privateAuraAnchorIDs[i] = anchorID
        end
    end
    d.privateAuraUnit = unit
end

-- Remove per-slot private aura anchors
local function UnregisterPrivateAuraSlots(button)
    if not C_UnitAuras_RemovePrivateAuraAnchor then return end
    local d = GetFFD(button)
    if d.privateAuraAnchorIDs then
        for _, aid in ipairs(d.privateAuraAnchorIDs) do
            C_UnitAuras_RemovePrivateAuraAnchor(aid)
        end
        wipe(d.privateAuraAnchorIDs)
    end
    if d.privateAuraFrames then
        for _, f in ipairs(d.privateAuraFrames) do f:Hide() end
    end
    d.privateAuraUnit = nil
end

-- Register all private aura anchors for a button (both container + per-slot)
local function RegisterPrivateAuras(button, unit)
    RegisterDispelContainer(button, unit)
    RegisterPrivateAuraSlots(button, unit)
end

-- Remove all private aura anchors from a button
local function UnregisterPrivateAuras(button)
    UnregisterDispelContainer(button)
    UnregisterPrivateAuraSlots(button)
end

-- Exposed for the per-button OnAttributeChanged watch installed in StyleButton,
-- which is defined earlier in the file than these locals and so cannot capture
-- them as upvalues. The watch reads them through ns at event time.
ns._RegisterPrivateAuras = RegisterPrivateAuras
ns._UnregisterPrivateAuras = UnregisterPrivateAuras

-- "By Me" dispel selection no longer uses a per-aura predicate: the scan in
-- UpdateDispelBorder queries auras with the "HARMFUL|RAID_PLAYER_DISPELLABLE"
-- filter directly, so Blizzard returns only player-dispellable auras and we
-- never branch on a (possibly secret) auraInstanceID -- the old approach
-- negated IsAuraFilteredOutByInstanceID on that id, which made selection
-- nondeterministic for secret boss debuffs (the intermittent-highlight bug).
-- (Removing this file-local also frees one main-chunk local slot.)

-- Check if a HARMFUL aura is dispellable by SOMEONE (any class), regardless of
-- whether this player can remove it. Used by the "Show All Dispellable" mode.
-- A typed (dispellable) debuff has a non-nil dispelName even when that name is a
-- secret value; physical/bleed debuffs have nil dispelName. This is a
-- secret-safe nil check (it never reads the secret), so it works on boss debuffs
-- where both the dispel-school string and the numeric dispelType are hidden.
local function IsAnyDispellable(unit, auraData)
    return auraData.dispelName ~= nil
end

-- Scratch color reused for dispel overlays (avoids a per-call table alloc).
ns._dispelScratch = ns._dispelScratch or {}

-- Build the dispel-type -> color curves from the user's custom colors. Blizzard's
-- GetAuraDispelTypeColor evaluates this curve against an aura's (secret) dispel
-- type internally and hands back the matching color, so we never need to read
-- the secret dispelName/dispelType ourselves. Indices are Blizzard's dispel-type
-- enum: 1 Magic, 2 Curse, 3 Disease, 4 Poison, 9 Enrage, 11 Bleed (0 = none).
-- Rebuilt on every ReloadFrames so custom-color edits take effect. Stored on ns
-- (not file locals) to respect the 200-local main-chunk cap.
function ns._RebuildDispelCurves()
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return end
    local function build(profile)
        local c = C_CurveUtil.CreateColorCurve()
        c:SetType(Enum.LuaCurveType.Step)
        local function add(idx, key, dr, dg, db)
            local col = profile and profile[key]
            c:AddPoint(idx, CreateColor(col and col.r or dr, col and col.g or dg, col and col.b or db))
        end
        add(0,  "dispelColorMagic",   0.349, 0.475, 1.0)   -- none: harmless default
        add(1,  "dispelColorMagic",   0.349, 0.475, 1.0)
        add(2,  "dispelColorCurse",   0.636, 0.0,   0.64)
        add(3,  "dispelColorDisease", 0.671, 0.384, 0.098)
        add(4,  "dispelColorPoison",  0.0,   0.706, 0.286)
        add(9,  "dispelColorBleed",   0.75,  0.15,  0.15)
        add(11, "dispelColorBleed",   0.75,  0.15,  0.15)
        return c
    end
    ns._dispelCurve = build(ns._scaledProfile)
    ns._dispelCurveParty = build(ns._scaledPartyProxy)
end

-- Per-type visibility curves for the dispel-type icons. Each curve is white at
-- full alpha for its own dispel index and alpha 0 at every other index, so
-- GetAuraDispelTypeColor returns a (secret) alpha of 1 only when the aura is
-- that type. Feeding that straight through SetVertexColor reveals exactly the
-- matching type's icon without ever reading the secret type. Cached on ns.
ns._dispelIconCurves = ns._dispelIconCurves or {}
function ns._GetDispelIconCurve(targetIdx)
    local c = ns._dispelIconCurves[targetIdx]
    if c then return c end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return nil end
    c = C_CurveUtil.CreateColorCurve()
    c:SetType(Enum.LuaCurveType.Step)
    for _, idx in ipairs({ 0, 1, 2, 3, 4, 9, 11 }) do
        c:AddPoint(idx, CreateColor(1, 1, 1, idx == targetIdx and 1 or 0))
    end
    ns._dispelIconCurves[targetIdx] = c
    return c
end

local function UpdateDispelBorder(button, unit, updateInfo)
    local d = GetFFD(button)
    local s = d._isParty and ns._scaledPartyProxy or ns._scaledProfile
    local borderSize  = s.dispelBorderSize or 2
    if not ns._dispelCurve then ns._RebuildDispelCurves() end
    local wantBorder  = borderSize > 0
    local wantOverlay = s.dispelOverlay and s.dispelOverlay ~= "none"
    local wantIcon    = s.showDispelIcons

    if not wantBorder and not wantOverlay and not wantIcon then
        HideDispelVisuals(d)
        return
    end

    -- Quick path: check if the incremental update could affect dispels.
    -- If no HARMFUL auras were added/updated/removed, skip the scan.
    if updateInfo and not updateInfo.isFullUpdate then
        local hasHarmfulChange = false
        if updateInfo.addedAuras then
            for _, ad in ipairs(updateInfo.addedAuras) do
                local iid = ad.auraInstanceID
                if iid and C_UnitAuras_IsAuraFilteredOutByInstanceID
                    and not C_UnitAuras_IsAuraFilteredOutByInstanceID(unit, iid, "HARMFUL") then
                    hasHarmfulChange = true; break
                end
            end
        end
        if not hasHarmfulChange and updateInfo.removedAuraInstanceIDs and d.dispelInstanceID then
            for _, iid in ipairs(updateInfo.removedAuraInstanceIDs) do
                if iid == d.dispelInstanceID then hasHarmfulChange = true; break end
            end
        end
        if not hasHarmfulChange and updateInfo.updatedAuraInstanceIDs and d.dispelInstanceID then
            for _, iid in ipairs(updateInfo.updatedAuraInstanceIDs) do
                if iid == d.dispelInstanceID then hasHarmfulChange = true; break end
            end
        end
        if not hasHarmfulChange then return end
    end

    -- Apply the dispel visuals (border/overlay/icon) for a chosen aura.
    local function ShowDispelFor(auraData, dc)
        d.dispelInstanceID = auraData.auraInstanceID
        if wantBorder and d.dispelFrame and PP then
            PP.UpdateBorder(d.dispelFrame, borderSize, dc.r, dc.g, dc.b, 1)
            d.dispelFrame:Show()
        elseif d.dispelFrame then
            d.dispelFrame:Hide()
        end
        if wantOverlay then
            ApplyDispelOverlay(d, dc, s)
        elseif d.dispelOLTex then
            d.dispelOLTex:Hide()
        end
        if wantIcon then
            ApplyDispelIcon(d, unit, auraData.auraInstanceID)
        elseif d.dispelIcon then
            d.dispelIcon:Hide()
        end
        UpdateDispelContainerVisibility(button)
    end

    -- Scan HARMFUL auras for the dispel highlight/icon.
    -- "Show All" matches any typed dispellable debuff via the secret-safe
    -- dispelName check. "By Me" asks Blizzard to apply the RAID_PLAYER_DISPELLABLE
    -- filter directly -- any aura it returns is player-dispellable -- so we never
    -- feed a (possibly secret) auraInstanceID into a per-aura filter decision.
    local showAll = s.dispelShowAll ~= false
    local scanFilter = showAll and "HARMFUL" or "HARMFUL|RAID_PLAYER_DISPELLABLE"
    local i = 1
    while true do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, scanFilter)
        if not auraData then break end
        i = i + 1

        -- Secret-safe match. Show-all: this nil check IS the dispellable test.
        -- By-me: the filter already restricted the list to player-dispellable
        -- auras (all of which carry a dispelName), so this is a harmless backstop
        -- that still never highlights a non-dispellable harmful aura even if the
        -- RAID_PLAYER_DISPELLABLE filter token were ever ignored.
        if IsAnyDispellable(unit, auraData) then
            -- Color via Blizzard's secret-safe curve: it resolves the dispel type
            -- internally (even when dispelName/dispelType are secret or nil) and
            -- returns the matching color from our custom-seeded curve. Falls back
            -- to the Magic color only if the curve API is unavailable. The icon is
            -- handled the same way (per-type alpha curves) inside ShowDispelFor.
            local iid = auraData.auraInstanceID
            local curve = d._isParty and ns._dispelCurveParty or ns._dispelCurve
            local dc
            if curve and C_UnitAuras.GetAuraDispelTypeColor then
                local col = C_UnitAuras.GetAuraDispelTypeColor(unit, iid, curve)
                if col then
                    local sc = ns._dispelScratch
                    sc.r, sc.g, sc.b = col:GetRGB()
                    dc = sc
                end
            end
            if not dc then dc = GetDispelColor("Magic", s) end
            ShowDispelFor(auraData, dc)
            return
        end
    end

    d.dispelInstanceID = nil
    HideDispelVisuals(d)
    -- Our overlay found nothing -- let container show (private aura fallback)
    UpdateDispelContainerVisibility(button)
end

-------------------------------------------------------------------------------
--  Ready check handling
-------------------------------------------------------------------------------
local readyCheckActive = false

local function UpdateReadyCheck(button, unit)
    local d = GetFFD(button)
    if not d.readyCheck then return end
    if not db.profile.showReadyCheck or not readyCheckActive then
        d.readyCheck:Hide()
        return
    end

    local status = GetReadyCheckStatus(unit)
    if status == "ready" then
        d.readyCheck:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        d.readyCheck:Show()
    elseif status == "notready" then
        d.readyCheck:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        d.readyCheck:Show()
    elseif status == "waiting" then
        d.readyCheck:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
        d.readyCheck:Show()
    else
        d.readyCheck:Hide()
    end
end

-------------------------------------------------------------------------------
--  Unit-to-button mapping
-------------------------------------------------------------------------------
local function RebuildUnitMap()
    local t0 = ns.ProfBegin("RebuildUnitMap")
    wipe(unitToButton)
    for _, btn in ipairs(allButtons) do
        if btn:IsVisible() then
            local u = btn:GetAttribute("unit")
            if u then
                unitToButton[u] = btn
                -- Cache class token for power border (avoids UnitClass in hot path)
                local d = GetFFD(btn)
                local _, classToken = UnitClass(u)
                d.classToken = classToken
                -- Re-register private aura anchors if unit token changed
                if d.dispelContainerUnit ~= u or d.privateAuraUnit ~= u then
                    RegisterPrivateAuras(btn, u)
                end
            end
        else
            -- Button not visible -- clean up any stale private aura anchors
            local d = GetFFD(btn)
            if d.dispelContainerAnchorID or (d.privateAuraAnchorIDs and #d.privateAuraAnchorIDs > 0) then
                UnregisterPrivateAuras(btn)
            end
        end
    end
    ns.ProfEnd("RebuildUnitMap", t0)
end

-------------------------------------------------------------------------------
--  Full update for all visible buttons
-------------------------------------------------------------------------------
local function UpdateAllButtons()
    if previewActive then return end  -- real buttons hidden during preview
    local t0 = ns.ProfBegin("UpdateAllButtons")
    for _, btn in ipairs(allButtons) do
        local u = btn:GetAttribute("unit")
        if u and btn:IsVisible() then
            UpdateButton(btn)
            UpdateDebuffs(btn, u)
            UpdateDefensives(btn, u)
            UpdateDispelBorder(btn, u)
            UpdateReadyCheck(btn, u)
            if ns.BM_UpdateIndicators then
                ns.BM_UpdateIndicators(btn, u, db)
            end
        end
    end
    ns.ProfEnd("UpdateAllButtons", t0)
end

-- Full per-button refresh for a freshly (re)assigned unit. Mirrors the
-- per-button work in UpdateAllButtons. Exposed on ns so the per-button
-- OnAttributeChanged("unit") watch in StyleButton (created before these locals
-- exist) can repaint a button the instant the secure header assigns it.
ns._RefreshAssignedButton = function(button, unit)
    if not GetFFD(button).styled then return end  -- not built yet; init paint handles it
    UpdateButton(button)
    UpdateDebuffs(button, unit)
    UpdateDefensives(button, unit)
    UpdateDispelBorder(button, unit)
    UpdateReadyCheck(button, unit)
    if ns.BM_UpdateIndicators then
        ns.BM_UpdateIndicators(button, unit, db)
    end
end

function ERF:UpdateAllFrames()
    UpdateAllButtons()
end

-- Lightweight: only toggle raid markers on each button (for RAID_TARGET_UPDATE)
ns._UpdateRaidMarkers = function()
    local function updateMarker(unit, btn)
        local d = GetFFD(btn)
        local s = d._isParty and ns._scaledPartyProxy or ns._scaledProfile
        if not s.showRaidMarker then
            if d.raidMarker then d.raidMarker:Hide() end
            return
        end
        if d.raidMarker then
            local idx = GetRaidTargetIndex(unit)
            if idx then
                if issecretvalue(idx) then
                    d.raidMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
                    if d.raidMarker.SetSpriteSheetCell then
                        pcall(d.raidMarker.SetSpriteSheetCell, d.raidMarker, idx, 4, 4, 64, 64)
                    end
                    d.raidMarker:Show()
                elseif RAID_MARKER_TEXCOORDS[idx] then
                    local tc = RAID_MARKER_TEXCOORDS[idx]
                    d.raidMarker:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
                    d.raidMarker:Show()
                else
                    d.raidMarker:Hide()
                end
            else
                d.raidMarker:Hide()
            end
        end
    end
    for unit, btn in pairs(unitToButton) do updateMarker(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do updateMarker(unit, btn) end
end

-- Lightweight: only toggle target border on each button (for PLAYER_TARGET_CHANGED)
ns._UpdateTargetBorders = function()
    local function updateTarget(unit, btn)
        local d = GetFFD(btn)
        local isTarget = UnitIsUnit(unit, "target")
        d._isTarget = (isTarget and not issecretvalue(isTarget)) and true or false
        if d.ApplyBorderColor then d.ApplyBorderColor() end
    end
    for unit, btn in pairs(unitToButton) do updateTarget(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do updateTarget(unit, btn) end
end

-- Lightweight: health-only update for UNIT_HEALTH / UNIT_MAXHEALTH.
-- Skips power, name, role, leader, marker, target, threat -- those don't
-- change on health events and are handled by their own event paths.
ns._UpdateButtonHealth = function(button)
    local unit = button:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end
    local d = GetFFD(button)
    if not d.styled then return end
    local s = d._isParty and ns._scaledPartyProxy or ns._scaledProfile

    local health = d.health
    local pct = GetSafeHealthPercent(unit)

    -- Health bar
    if health then
        health:SetMinMaxValues(0, 100)
        local smooth = s.smoothBars and Enum and Enum.StatusBarInterpolation
            and Enum.StatusBarInterpolation.ExponentialEaseOut
        if smooth then
            health:SetValue(pct, smooth)
        else
            health:SetValue(pct)
        end
        local r, g, b = GetHealthColor(unit, s)
        local fillTex = health:GetStatusBarTexture()
        if s.healthColorMode == "dark" then
            health:SetStatusBarColor(r, g, b, 1)
            if fillTex then fillTex:SetAlpha(DARK_FILL_A) end
        else
            if fillTex then fillTex:SetAlpha(1) end
            health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
        end
    end

    -- Absorb (clip frames anchor to fill texture, need visual update)
    UpdateAbsorb(button, unit)

    -- Health text
    if d.healthText then
        local mode = s.healthTextMode or "none"
        -- Hide health text while dead/offline (see UpdateButton; matches preview).
        if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
            d.healthText:SetText("")
        elseif mode == "percent" then
            d.healthText:SetFormattedText("%.0f%%", pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            d.healthText:SetTextColor(htr, htg, htb, 0.9)
        elseif mode == "percentNoSign" then
            d.healthText:SetFormattedText("%.0f", pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            d.healthText:SetTextColor(htr, htg, htb, 0.9)
        elseif mode == "number" then
            local curr = UnitHealth(unit, true)
            if curr and AbbreviateNumbers then
                d.healthText:SetText(AbbreviateNumbers(curr))
            elseif curr then
                d.healthText:SetFormattedText("%s", curr)
            end
            local htr, htg, htb = GetHealthTextColor(unit, s)
            d.healthText:SetTextColor(htr, htg, htb, 0.9)
        elseif mode == "numberPercent" then
            local curr = UnitHealth(unit, true)
            local numStr = (curr and AbbreviateNumbers) and AbbreviateNumbers(curr) or tostring(curr or 0)
            d.healthText:SetFormattedText("%s | %.0f%%", numStr, pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            d.healthText:SetTextColor(htr, htg, htb, 0.9)
        elseif mode == "percentNumber" then
            local curr = UnitHealth(unit, true)
            local numStr = (curr and AbbreviateNumbers) and AbbreviateNumbers(curr) or tostring(curr or 0)
            d.healthText:SetFormattedText("%.0f%% | %s", pct, numStr)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            d.healthText:SetTextColor(htr, htg, htb, 0.9)
        else
            d.healthText:SetText("")
        end
    end

    -- Status text (dead/ghost state changes with health)
    if d.statusText then
        local stc = s.statusTextColor or { r = 1, g = 1, b = 1 }
        if s.statusTextPosition == "none" then
            d.statusText:Hide()
        elseif UnitIsDeadOrGhost(unit) then
            d.statusText:SetText("DEAD")
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            d.statusText:Show()
        elseif not UnitIsConnected(unit) then
            d.statusText:SetText("OFFLINE")
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            d.statusText:Show()
        elseif s.statusShowAFK and UnitIsAFK and not issecretvalue(UnitIsAFK(unit)) and UnitIsAFK(unit) then
            d.statusText:SetText("AFK")
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            d.statusText:Show()
        else
            d.statusText:Hide()
        end
    end

    -- Dead/DC overlay
    if UnitIsDeadOrGhost(unit) then
        if health then health:SetStatusBarColor(0.3, 0.3, 0.3, 0.5) end
    elseif not UnitIsConnected(unit) then
        if health then health:SetStatusBarColor(0.3, 0.3, 0.3, 0.3) end
    end
end

-------------------------------------------------------------------------------
--  Show Self First (raid, out-of-combat only)
--  The player's own subgroup header sorts via a per-group nameList that lists
--  every group member with the player first, so the secure header itself orders
--  the player to the top natively -- no SetPoint override, nothing to flicker.
--  showPlayer cannot exclude the player in a raid, so the party-style self
--  button is not usable here. Non-merged only (ignored when Merge Groups on).
-------------------------------------------------------------------------------
-- Player's raid subgroup (1-8). Party/solo collapses to group 1.
function ns._GetPlayerSubgroup()
    if not IsInRaid() then return 1 end
    local n = GetNumGroupMembers()
    for i = 1, n do
        if UnitIsUnit("raid" .. i, "player") then
            local _, _, subgroup = GetRaidRosterInfo(i)
            return subgroup
        end
    end
    return nil
end

-- Build a "player first" nameList for the player's raid subgroup. Names come
-- from GetRaidRosterInfo (available for every member regardless of range, and
-- the same source the secure header matches against), so nothing can vanish.
-- Others follow the active sort: role order (ROLE mode) else raid index. Role
-- comes from UnitGroupRolesAssigned -- the ASSIGNED role the other group
-- headers' groupBy="ASSIGNEDROLE" also use (GetRaidRosterInfo's combatRole is
-- the spec role and is "NONE" for un-inspected/out-of-range members).
-- selfLast: when true the player is ordered LAST in the group instead of first.
function ns._BuildSelfFirstNameList(playerGroup, sortByRole, roleOrder, selfLast)
    if not IsInRaid() or not playerGroup then return nil end
    local pri
    if sortByRole then
        pri = {}
        for p, r in ipairs(roleOrder) do pri[r] = p end
    end
    local members = {}
    local n = GetNumGroupMembers()
    for i = 1, n do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if subgroup == playerGroup and name then
            local unit = "raid" .. i
            local rp = 99
            if pri then rp = pri[UnitGroupRolesAssigned(unit)] or 99 end
            members[#members + 1] = {
                name = name,
                isPlayer = UnitIsUnit(unit, "player"),
                rolePri = rp,
                index = i,
            }
        end
    end
    if #members == 0 then return nil end
    table.sort(members, function(a, b)
        -- Player to the top (self-first) or bottom (self-last). Exactly one of
        -- a/b is the player inside this branch, so the XOR with selfLast flips it.
        if a.isPlayer ~= b.isPlayer then return a.isPlayer ~= selfLast end
        if sortByRole and a.rolePri ~= b.rolePri then return a.rolePri < b.rolePri end
        return a.index < b.index
    end)
    local names = {}
    for _, m in ipairs(members) do names[#names + 1] = m.name end
    return table.concat(names, ",")
end

-------------------------------------------------------------------------------
--  Apply sort attributes to all headers. Show Self First (raid) uses a per-group
--  nameList on the player's own subgroup so the secure header itself puts the
--  player first natively -- no SetPoint override, nothing to flicker. (showPlayer
--  cannot exclude the player in a raid, so a self button is not usable here; the
--  nameList lists every group member, player first.) Non-merged, in-raid only.
--  Only does the expensive Hide/Show when an attribute actually changed.
-------------------------------------------------------------------------------
local function ApplySortToHeaders()
    if not containerFrame or InCombatLockdown() then return end
    local s = db.profile
    local sortByRole = s.sortMode == "ROLE"
    local roleOrder = s.roleOrder or { "TANK", "HEALER", "DAMAGER" }

    local baseGroupBy = sortByRole and "ASSIGNEDROLE" or nil
    local baseSortMethod = sortByRole and "NAME" or "INDEX"
    local baseGroupingOrder = sortByRole and (table.concat(roleOrder, ",") .. ",NONE") or ""

    -- Self-first: build the player-first nameList for the player's group.
    -- Raid only (showPlayer-based party self-first lives in _LayoutPartyFrames).
    local useSelf = (s.showSelfFirst or s.showSelfLast) and not s.mergeGroups and IsInRaid()
    local selfLast = s.showSelfLast
    local playerGroup = useSelf and ns._GetPlayerSubgroup() or nil
    local selfNameList = playerGroup and ns._BuildSelfFirstNameList(playerGroup, sortByRole, roleOrder, selfLast) or nil
    if not selfNameList then playerGroup = nil end

    -- gf = desired groupFilter. The player's group is ordered by nameList, which
    -- Blizzard only honors when groupFilter is CLEARED (with a groupFilter present
    -- it ignores nameList and falls back to roster/index order). The nameList
    -- lists every member of the group, so clearing groupFilter shows the same
    -- members, now in nameList order.
    local function applySortTo(hdr, gb, sm, go, nl, gf)
        local needsHideShow = (hdr:GetAttribute("groupBy") ~= gb)
            or (hdr:GetAttribute("sortMethod") ~= sm)
            or (hdr:GetAttribute("groupingOrder") ~= go)
            or (hdr:GetAttribute("nameList") ~= nl)
            or (hdr:GetAttribute("groupFilter") ~= gf)
        if needsHideShow then
            hdr:Hide()
            hdr:SetAttribute("groupFilter", gf)
            hdr:SetAttribute("groupBy", gb)
            hdr:SetAttribute("sortMethod", sm)
            hdr:SetAttribute("groupingOrder", go)
            hdr:SetAttribute("nameList", nl)
            hdr:Show()
        end
    end

    if s.mergeGroups and ns._flatHeader then
        -- Flat header's groupFilter is managed by LayoutGroups; pass it through.
        applySortTo(ns._flatHeader, baseGroupBy, baseSortMethod, baseGroupingOrder, nil,
            ns._flatHeader:GetAttribute("groupFilter"))
    else
        for group = 1, 8 do
            local hdr = separatedHdrs[group]
            if not hdr then break end
            if playerGroup and group == playerGroup then
                -- Player's group: ordered by nameList -- clear groupFilter, nil
                -- groupBy so the nameList order is what the header uses.
                applySortTo(hdr, nil, "NAMELIST", "", selfNameList, nil)
            else
                applySortTo(hdr, baseGroupBy, baseSortMethod, baseGroupingOrder, nil, tostring(group))
            end
        end
    end
end
ns._ApplySortToHeaders = ApplySortToHeaders

-------------------------------------------------------------------------------
--  Header creation
-------------------------------------------------------------------------------
local function CreateHeaders()
    if containerFrame then return end

    local s = db.profile

    -- Container frame for positioning (not secure, just holds headers)
    containerFrame = CreateFrame("Frame", "EllesmereUIRaidFrameContainer", UIParent)
    containerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    containerFrame:SetSize(1, 1)
    containerFrame:SetFrameStrata("LOW")
    containerFrame:Show()

    -- Button dimensions passed to headers via attributes (pixel-snapped)
    local bw = PixelSnap(s.frameWidth or 72)
    local bh = PixelSnap(s.frameHeight or 46)

    -- initialConfigFunction: runs in restricted env when header creates a button
    local initConfig = ([[
        self:SetWidth(%d)
        self:SetHeight(%d)
    ]]):format(bw, bh)

    -- Compute correct initial point/offset from saved growth direction
    local initUnitGrowth = s.unitGrowth or "DOWN"
    local initPoint, initXOff, initYOff
    local csInit = PixelSnap(s.cellSpacing or 2)
    if initUnitGrowth == "DOWN" then
        initPoint = "TOP";    initXOff = 0;    initYOff = -csInit
    elseif initUnitGrowth == "UP" then
        initPoint = "BOTTOM"; initXOff = 0;    initYOff = csInit
    elseif initUnitGrowth == "RIGHT" then
        initPoint = "LEFT";   initXOff = csInit; initYOff = 0
    else -- LEFT
        initPoint = "RIGHT";  initXOff = -csInit; initYOff = 0
    end

    -----------------------------------------------------------
    --  8 separated group headers (one per raid group)
    -----------------------------------------------------------
    for group = 1, 8 do
        local hdr = CreateFrame("Frame", "ERFGroupHeader" .. group, containerFrame, "SecureGroupHeaderTemplate")
        hdr:SetAttribute("template", "SecureUnitButtonTemplate")
        hdr:SetAttribute("templateType", "Button")
        hdr:SetAttribute("initialConfigFunction", initConfig)
        hdr:SetAttribute("point", initPoint)
        hdr:SetAttribute("xOffset", initXOff)
        hdr:SetAttribute("yOffset", initYOff)
        hdr:SetAttribute("groupFilter", tostring(group))
        hdr:SetAttribute("showRaid", true)
        hdr:SetAttribute("showParty", true)
        hdr:SetAttribute("showPlayer", true)
        hdr:SetAttribute("showSolo", s.showWhenSolo or false)
        hdr:SetAttribute("maxColumns", 1)
        hdr:SetAttribute("unitsPerColumn", 5)

        hdr:SetAttribute("sortMethod", "INDEX")

        -- Pre-create 5 buttons per group
        hdr:SetAttribute("startingIndex", -4)
        hdr:Show()
        hdr:SetAttribute("startingIndex", 1)

        -- Style pre-created buttons
        for i = 1, 5 do
            local btn = hdr[i]
            if btn then
                StyleButton(btn)
                allButtons[#allButtons + 1] = btn
            end
        end

        separatedHdrs[group] = hdr
    end

    -- Group-number labels (1-8) for the real raid frames. Own (non-secure)
    -- FontStrings parented to the container; they track each group's first unit
    -- via relative anchoring (no SetPoint is ever issued on the secure headers).
    -- Shown only when showGroupNumbers is on (see ns._UpdateGroupNumbers).
    if not ns._groupNumberLabels then
        ns._groupNumberLabels = {}
        for gi = 1, 8 do
            local lbl = containerFrame:CreateFontString(nil, "OVERLAY")
            lbl:Hide()
            ns._groupNumberLabels[gi] = lbl
        end
    end

    -----------------------------------------------------------
    --  Flat header for merge-groups mode (all members in one grid)
    -----------------------------------------------------------
    ns._flatHeader = CreateFrame("Frame", "ERFFlatHeader", containerFrame, "SecureGroupHeaderTemplate")
    ns._flatHeader:SetAttribute("template", "SecureUnitButtonTemplate")
    ns._flatHeader:SetAttribute("templateType", "Button")
    ns._flatHeader:SetAttribute("initialConfigFunction", initConfig)
    ns._flatHeader:SetAttribute("point", initPoint)
    ns._flatHeader:SetAttribute("xOffset", initXOff)
    ns._flatHeader:SetAttribute("yOffset", initYOff)
    ns._flatHeader:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8")
    ns._flatHeader:SetAttribute("showRaid", true)
    ns._flatHeader:SetAttribute("showParty", true)
    ns._flatHeader:SetAttribute("showPlayer", true)
    ns._flatHeader:SetAttribute("showSolo", s.showWhenSolo or false)
    ns._flatHeader:SetAttribute("unitsPerColumn", 5)
    ns._flatHeader:SetAttribute("maxColumns", 8)
    ns._flatHeader:SetAttribute("columnSpacing", PixelSnap(s.groupSpacing or 8))
    -- Compute correct initial columnAnchorPoint from saved growth directions
    local initGroupGrowth = s.groupGrowth or "RIGHT"
    local initColAnchor
    if initGroupGrowth == "DOWN" or initGroupGrowth == "RIGHT" then
        if initUnitGrowth == "DOWN" or initUnitGrowth == "UP" then
            initColAnchor = "LEFT"
        else
            initColAnchor = "TOP"
        end
    else
        if initUnitGrowth == "DOWN" or initUnitGrowth == "UP" then
            initColAnchor = "RIGHT"
        else
            initColAnchor = "BOTTOM"
        end
    end
    ns._flatHeader:SetAttribute("columnAnchorPoint", initColAnchor)
    ns._flatHeader:SetAttribute("sortMethod", "INDEX")

    -- Pre-create 40 buttons
    ns._flatHeader:SetAttribute("startingIndex", -39)
    ns._flatHeader:Show()
    ns._flatHeader:SetAttribute("startingIndex", 1)
    ns._flatHeader:Hide()  -- start hidden; LayoutGroups shows the right headers

    -- Style all flat-header buttons
    for i = 1, 40 do
        local btn = ns._flatHeader[i]
        if btn then
            StyleButton(btn)
            allButtons[#allButtons + 1] = btn
            ns._flatButtons[#ns._flatButtons + 1] = btn
        end
    end

    -- Apply initial sort settings
    ApplySortToHeaders()
end

-------------------------------------------------------------------------------
--  Layout groups
--  Two perpendicular axes: groupGrowth (where next group goes) and
--  unitGrowth (where next unit within a group goes).
--  Container sized for 4 groups (standard 20-player raid).
-------------------------------------------------------------------------------
local MOVER_GROUPS = 4

-- Real-frame group numbers (1-8): mirror the preview labels onto the actual
-- raid frames when showGroupNumbers is on. Anchors each group's label to that
-- group's first populated unit, using the shared groupNumberSize/groupNumberColor.
-- Raid-only and separated-groups only (merged mode has no per-group first unit).
-- Combat-safe: only ever called from LayoutGroups (which early-returns in combat)
-- and only SetPoints our own non-secure FontStrings (never the secure headers).
function ns._UpdateGroupNumbers()
    local labels = ns._groupNumberLabels
    if not labels then return end
    if InCombatLockdown() then return end
    local s = db.profile
    if (not s.showGroupNumbers) or s.mergeGroups or (not IsInRaid()) then
        for g = 1, 8 do if labels[g] then labels[g]:Hide() end end
        return
    end
    -- Effective unit growth (mirror the LayoutGroups tier override)
    local unitGrowth = s.unitGrowth or "DOWN"
    local activeOv = ns._activeTierOverride
    if activeOv and activeOv.unitGrowth then unitGrowth = activeOv.unitGrowth end
    local vg = s.visibleGroups or { true, true, true, true, true, true, false, false }
    local size = s.groupNumberSize or 10
    local gc = s.groupNumberColor or {}
    local ox = s.groupNumberOffsetX or 0
    local oy = s.groupNumberOffsetY or 0
    for group = 1, 8 do
        local lbl = labels[group]
        local hdr = separatedHdrs[group]
        local firstBtn
        if lbl and hdr and vg[group] ~= false then
            -- First populated unit of this group (empty-but-visible groups -> none)
            for i = 1, 5 do
                local btn = hdr[i]
                if btn and btn:IsShown() and btn:GetAttribute("unit") then firstBtn = btn; break end
            end
        end
        if lbl then
            if firstBtn then
                lbl:ClearAllPoints()
                if unitGrowth == "DOWN" then
                    lbl:SetPoint("BOTTOM", firstBtn, "TOP", ox, 4 + oy)
                elseif unitGrowth == "UP" then
                    lbl:SetPoint("TOP", firstBtn, "BOTTOM", ox, -4 + oy)
                elseif unitGrowth == "RIGHT" then
                    lbl:SetPoint("RIGHT", firstBtn, "LEFT", -3 + ox, oy)
                else -- LEFT
                    lbl:SetPoint("LEFT", firstBtn, "RIGHT", 3 + ox, oy)
                end
                ApplyFont(lbl, size)  -- must precede SetText (FontString needs a font first)
                lbl:SetText(tostring(group))
                lbl:SetTextColor(gc.r or 1, gc.g or 1, gc.b or 1, gc.a or 0.75)
                lbl:Show()
            else
                lbl:Hide()
            end
        end
    end
end

local function LayoutGroups()
    if not containerFrame then return end
    if InCombatLockdown() then return end

    local s = db.profile
    local merged = s.mergeGroups
    local groupGrowth = s.groupGrowth or "RIGHT"
    local unitGrowth  = s.unitGrowth or "DOWN"
    -- Per-tier growth overrides
    local activeOv = ns._activeTierOverride
    if activeOv then
        groupGrowth = activeOv.groupGrowth or groupGrowth
        unitGrowth  = activeOv.unitGrowth or unitGrowth
    end
    local bw = PixelSnap(ns._activeSizeW or s.frameWidth or 72)
    local bh = PixelSnap(ns._activeSizeH or s.frameHeight or 46)
    local cs = PixelSnap(s.cellSpacing or 2)
    local gs = PixelSnap(s.groupSpacing or 8)

    -- Header attributes for unit growth direction
    local hdrPoint, hdrXOff, hdrYOff
    if unitGrowth == "DOWN" then
        hdrPoint = "TOP";    hdrXOff = 0;   hdrYOff = -cs
    elseif unitGrowth == "UP" then
        hdrPoint = "BOTTOM"; hdrXOff = 0;   hdrYOff = cs
    elseif unitGrowth == "RIGHT" then
        hdrPoint = "LEFT";   hdrXOff = cs;  hdrYOff = 0
    else -- LEFT
        hdrPoint = "RIGHT";  hdrXOff = -cs; hdrYOff = 0
    end

    -- Column anchor: where next column of 5 goes (perpendicular to unit growth)
    local colAnchor
    if groupGrowth == "DOWN" or groupGrowth == "RIGHT" then
        if unitGrowth == "DOWN" or unitGrowth == "UP" then
            colAnchor = "LEFT"
        else
            colAnchor = "TOP"
        end
    else -- UP or LEFT
        if unitGrowth == "DOWN" or unitGrowth == "UP" then
            colAnchor = "RIGHT"
        else
            colAnchor = "BOTTOM"
        end
    end

    -- Group bounding box: size of one group along each axis
    local groupW, groupH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        groupW = 5 * bw + 4 * cs
        groupH = bh
    else
        groupW = bw
        groupH = 5 * bh + 4 * cs
    end

    -- Build visible groups filter string from settings
    local vg = s.visibleGroups or { true, true, true, true, true, true, false, false }

    if merged then
        ---------------------------------------------------------------
        --  Merge-groups mode: single flat header, all members in one grid
        ---------------------------------------------------------------
        -- Hide separated headers
        for group = 1, 8 do
            local hdr = separatedHdrs[group]
            if hdr and hdr:IsShown() then hdr:Hide() end
        end

        -- Build groupFilter from visible groups
        local gfParts = {}
        for i = 1, 8 do
            if vg[i] ~= false then gfParts[#gfParts + 1] = tostring(i) end
        end
        local gfStr = table.concat(gfParts, ",")

        -- Configure flat header layout attributes
        if ns._flatHeader then
            ns._flatHeader:ClearAllPoints()
            ns._flatHeader:SetPoint("TOPLEFT", containerFrame, "TOPLEFT", 0, 0)
            local layoutChanged = false
            if ns._flatHeader:GetAttribute("groupFilter") ~= gfStr then
                ns._flatHeader:SetAttribute("groupFilter", gfStr)
            end
            if ns._flatHeader:GetAttribute("point") ~= hdrPoint
            or ns._flatHeader:GetAttribute("xOffset") ~= hdrXOff
            or ns._flatHeader:GetAttribute("yOffset") ~= hdrYOff
            or ns._flatHeader:GetAttribute("columnAnchorPoint") ~= colAnchor then
                -- Clear child anchors before changing layout direction
                local ci, child = 1, ns._flatHeader:GetAttribute("child1")
                while child do
                    child:ClearAllPoints()
                    ci = ci + 1
                    child = ns._flatHeader:GetAttribute("child" .. ci)
                end
                ns._flatHeader:SetAttribute("point", hdrPoint)
                ns._flatHeader:SetAttribute("xOffset", hdrXOff)
                ns._flatHeader:SetAttribute("yOffset", hdrYOff)
                ns._flatHeader:SetAttribute("columnAnchorPoint", colAnchor)
                layoutChanged = true
            end
            if ns._flatHeader:GetAttribute("columnSpacing") ~= gs then
                ns._flatHeader:SetAttribute("columnSpacing", gs)
            end
            if layoutChanged and ns._flatHeader:IsShown() then
                ns._flatHeader:Hide()
                ns._flatHeader:Show()
            elseif not ns._flatHeader:IsShown() then
                ns._flatHeader:Show()
            end
        end
    else
        ---------------------------------------------------------------
        --  Per-group mode: 8 separated headers
        ---------------------------------------------------------------
        -- Hide flat header
        if ns._flatHeader and ns._flatHeader:IsShown() then ns._flatHeader:Hide() end

        -- Step between adjacent group origins along the growth axis
        local stepX, stepY = 0, 0
        if groupGrowth == "DOWN" then
            stepY = -(groupH + gs)
        elseif groupGrowth == "UP" then
            stepY = (groupH + gs)
        elseif groupGrowth == "RIGHT" then
            stepX = (groupW + gs)
        else -- LEFT
            stepX = -(groupW + gs)
        end

        -- Normalize for UP/LEFT growth so slot 0 stays within container bounds
        local minX, maxY = 0, 0
        for i = 0, MOVER_GROUPS - 1 do
            local px = i * stepX
            local py = i * stepY
            if px < minX then minX = px end
            if py > maxY then maxY = py end
        end

        local hdrOffX, hdrOffY = 0, 0
        if unitGrowth == "UP"   then hdrOffY = -groupH end
        if unitGrowth == "LEFT" then hdrOffX = groupW  end

        local visSlot = 0  -- running counter for visible groups (collapses gaps)
        for group = 1, 8 do
            local hdr = separatedHdrs[group]
            if hdr then
                if vg[group] == false then
                    if hdr:IsShown() then hdr:Hide() end
                else
                    local x = PixelSnap(visSlot * stepX - minX + hdrOffX)
                    local y = PixelSnap(visSlot * stepY - maxY + hdrOffY)
                    visSlot = visSlot + 1

                    hdr:ClearAllPoints()
                    hdr:SetPoint("TOPLEFT", containerFrame, "TOPLEFT", x, y)
                    local layoutChanged = false
                    if hdr:GetAttribute("point") ~= hdrPoint
                    or hdr:GetAttribute("xOffset") ~= hdrXOff
                    or hdr:GetAttribute("yOffset") ~= hdrYOff then
                        -- Clear child anchors before changing layout direction
                        local ci, child = 1, hdr:GetAttribute("child1")
                        while child do
                            child:ClearAllPoints()
                            ci = ci + 1
                            child = hdr:GetAttribute("child" .. ci)
                        end
                        hdr:SetAttribute("point", hdrPoint)
                        hdr:SetAttribute("xOffset", hdrXOff)
                        hdr:SetAttribute("yOffset", hdrYOff)
                        layoutChanged = true
                    end
                    if layoutChanged and hdr:IsShown() then
                        hdr:Hide()
                        hdr:Show()
                    elseif not hdr:IsShown() then
                        hdr:Show()
                    end
                end
            end
        end
    end

    -- Apply sort after all headers are positioned
    ApplySortToHeaders()

    -- Container size based on 4 groups for unlock mode mover
    local totalW, totalH
    if groupGrowth == "DOWN" or groupGrowth == "UP" then
        totalW = groupW
        totalH = MOVER_GROUPS * groupH + (MOVER_GROUPS - 1) * gs
    else
        totalW = MOVER_GROUPS * groupW + (MOVER_GROUPS - 1) * gs
        totalH = groupH
    end
    containerFrame:SetSize(PixelSnap(totalW), PixelSnap(totalH))

    -- Snap the container's screen position to the pixel grid
    if not InCombatLockdown() then
        local l = containerFrame:GetLeft()
        local t = containerFrame:GetTop()
        if l and t then
            local snappedL = PixelSnap(l)
            local snappedT = PixelSnap(t)
            if abs(l - snappedL) > 0.01 or abs(t - snappedT) > 0.01 then
                containerFrame:ClearAllPoints()
                containerFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", snappedL, snappedT)
            end
        end
    end

    -- Update real-frame group numbers now that all headers are positioned.
    ns._UpdateGroupNumbers()
end

local RangeUpdate  -- forward declaration (defined in Range fading section below)

-------------------------------------------------------------------------------
--  Reload: re-apply all settings to existing buttons
-------------------------------------------------------------------------------
local function ReloadFrames()
    local s = ns._scaledProfile
    -- Rebuild dispel-color curves so custom-color edits take effect immediately.
    if ns._RebuildDispelCurves then ns._RebuildDispelCurves() end
    -- Recalculate active tier from current group size + overrides
    local numMembers = GetNumGroupMembers()
    local prevW, prevH = ns._activeSizeW, ns._activeSizeH
    if numMembers > 0 then
        ns._activeSizeW, ns._activeSizeH = ns._GetRaidSizeFrameDimensions(numMembers)
        -- Resolve active tier override table (for per-tier growth directions)
        local overrides = db.profile.raidSizeOverrides
        if overrides then
            local tier = numMembers <= 10 and 10 or numMembers <= 15 and 15 or numMembers <= 20 and 20 or numMembers <= 25 and 25 or 30
            if tier ~= 20 then
                if tier < 20 then
                    ns._activeTierOverride = overrides[tier] or (tier == 10 and overrides[15]) or nil
                else
                    ns._activeTierOverride = overrides[tier] or (tier == 30 and overrides[25]) or nil
                end
            else
                ns._activeTierOverride = nil
            end
        else
            ns._activeTierOverride = nil
        end
    else
        ns._activeSizeW, ns._activeSizeH = nil, nil
        ns._activeTierOverride = nil
    end
    local bw = PixelSnap(ns._activeSizeW or s.frameWidth or 72)
    local bh = PixelSnap(ns._activeSizeH or s.frameHeight or 46)

    -- Auto-resize indicators: scale factor based on active tier vs base 20-man
    -- Read base dimensions from raw db.profile (not proxy, which returns active tier)
    if db.profile.autoResizeIndicators and ns._activeSizeW and ns._activeSizeH then
        local baseW = db.profile.frameWidth or 72
        local baseH = db.profile.frameHeight or 46
        local scale = math.min(ns._activeSizeW / baseW, ns._activeSizeH / baseH)
        ns._indicatorScale = math.max(math.min(scale, 1.3), 0.7)
    else
        ns._indicatorScale = 1
    end

    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - powerH)
    local texPath = ResolveHealthTexture()

    for _, btn in ipairs(allButtons) do
        local d = GetFFD(btn)
        if not d.styled then StyleButton(btn) end

        btn:SetSize(bw, bh)

        -- Background
        if d.bg then
            local bgc = s.customBgColor
            d.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
        end

        -- Health bar
        if d.health then
            d.health:SetHeight(healthH)
            d.health:SetStatusBarTexture(texPath)
            d.health:GetStatusBarTexture():SetHorizTile(false)
            -- Re-anchor absorb clips to the new fill texture object
            if d.ReanchorAbsorbToFill then d.ReanchorAbsorbToFill() end
        end

        -- Power bar (always hide here; UpdateButton handles per-role show)
        if d.power then
            d.power:Hide()
            if powerH > 0 then
                d.power:SetHeight(powerH)
                d.power:SetStatusBarTexture(texPath)
                d.power:GetStatusBarTexture():SetHorizTile(false)
            end
        end
        if d.powerBg then
            d.powerBg:SetColorTexture((s.powerBgColor or {}).r or 0, (s.powerBgColor or {}).g or 0, (s.powerBgColor or {}).b or 0, (s.powerBgDarkness or 70) / 100)
        end
        if d.UpdatePowerBorder then d.UpdatePowerBorder() end

        -- Name text
        if d.nameText then
            ApplyFont(d.nameText, s.nameSize or 10)
            if d.AnchorNameText then d.AnchorNameText() end
        end

        -- Health text
        if d.healthText then
            ApplyFont(d.healthText, s.healthTextSize or 9)
            if d.AnchorHealthText then d.AnchorHealthText() end
        end

        -- Status text (DEAD/OFFLINE/AFK)
        if d.statusText then
            local stc = s.statusTextColor or { r = 1, g = 1, b = 1 }
            ApplyFont(d.statusText, s.statusTextSize or 14)
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            if d.AnchorStatusText then d.AnchorStatusText() end
        end

        -- Role icon size + position
        if d.roleIcon then
            local riSz = PixelSnap(s.roleIconSize or 14)
            d.roleIcon:SetSize(riSz, riSz)
            if d.AnchorRoleIcon then d.AnchorRoleIcon() end
        end

        -- Leader icon size + position
        if d.leaderIcon then
            local liSz = PixelSnap(s.leaderIconSize or 14)
            d.leaderIcon:SetSize(liSz, liSz)
            d.leaderIcon:ClearAllPoints()
            local liPos = (s.leaderIconPosition or "top"):upper()
            d.leaderIcon:SetPoint(liPos, d.health, liPos, s.leaderIconOffsetX or 0, s.leaderIconOffsetY or 0)
            -- Keep the leader-icon host on the chat frame's current strata/level
            if d.leaderHost then ns.ApplyChatStrata(d.leaderHost) end
        end

        -- Raid marker size + position
        if d.raidMarker then
            local rmSz = PixelSnap(s.raidMarkerSize or 16)
            d.raidMarker:SetSize(rmSz, rmSz)
            if d.AnchorRaidMarker then d.AnchorRaidMarker() end
        end

        -- Border
        if d.UpdateBorder then d.UpdateBorder() end

        -- Debuff size + position
        if d.debuffIcons then
            for _, icon in ipairs(d.debuffIcons) do
                icon:SetSize(s.debuffSize or 18, s.debuffSize or 18)
            end
            if d.AnchorDebuffs then d.AnchorDebuffs() end
        end

        -- Defensive icon size + position
        if d.defIcons then
            for _, icon in ipairs(d.defIcons) do
                icon:SetSize(s.defSize or 22, s.defSize or 22)
            end
            if d.AnchorDefensives then d.AnchorDefensives() end
        end

        -- Dispel icon size + position
        if d.dispelIcon then
          local diSz = PixelSnap(s.dispelIconSize or 16)
          d.dispelIcon:SetSize(diSz, diSz)
          if d.AnchorDispelIcon then d.AnchorDispelIcon() end
        end

        -- Private aura per-slot frames (re-anchor for changed debuff settings)
        if d.privateAuraFrames then
            for _, paFrame in ipairs(d.privateAuraFrames) do
                paFrame:SetSize(s.debuffSize or 18, s.debuffSize or 18)
            end
        end

        -- Buff manager indicators
        if d.bmIconPool and d.health and ns.BM_AnchorIndicators then
            ns.BM_AnchorIndicators(d, d.health, s)
        end
    end

    -- Re-layout headers (may switch between flat/grouped)
    LayoutGroups()
    -- Apply tier-based position offset
    if ns._ApplyTierOffset then ns._ApplyTierOffset() end
    RebuildUnitMap()
    UpdateAllButtons()
    -- Immediate range update so new buttons don't flash full alpha
    RangeUpdate()

    -- Re-register private aura anchors with updated settings
    for unit, btn in pairs(unitToButton) do
        RegisterPrivateAuras(btn, unit)
    end
end

ns.ReloadFrames = ReloadFrames
ns.PixelSnap = PixelSnap
ns._allButtons = allButtons

-- Lightweight resize: only changes button/health/power dimensions + layout.
-- No texture, border, font, or anchor changes. Safe for slider hot path.
ns._ResizeButtons = function(w, h)
    if InCombatLockdown() then return end
    local bw = PixelSnap(w)
    local bh = PixelSnap(h)
    local s = db.profile
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - powerH)
    for _, btn in ipairs(allButtons) do
        local d = GetFFD(btn)
        if d.styled then
            btn:SetSize(bw, bh)
            -- Full height when the power bar is hidden for this button's role
            -- (mirrors _ResizePartyButtons); avoids a dark strip on OFF-role units
            -- now that d.power always exists.
            if d.health then
                d.health:SetHeight((d.power and d.power:IsShown()) and healthH or bh)
            end
            if d.nameText then d.nameText:SetWidth(bw * 0.75) end
        end
    end
    ns._activeSizeW = w
    ns._activeSizeH = h
    LayoutGroups()
end

-- Lightweight party resize: only changes button/health/power dimensions + container.
-- No sort/self-first re-chain. Safe for slider hot path.
ns._ResizePartyButtons = function(w, h)
    if InCombatLockdown() then return end
    if not ns._partyAllButtons then return end
    local bw = PixelSnap(w)
    local bh = PixelSnap(h)
    local s = db.profile
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - powerH)
    -- Auto Resize scale depends on frame size; recompute on this lightweight
    -- width/height slider path (which skips the full reload).
    if ns._UpdatePartyIndicatorScale then ns._UpdatePartyIndicatorScale() end
    local autoResize = s.partyAutoResizeIndicators
    for _, btn in ipairs(ns._partyAllButtons) do
        local d = GetFFD(btn)
        if d.styled then
            btn:SetSize(bw, bh)
            -- Use full height if power bar is hidden for this button's role
            if d.health then
                local hh = (d.power and d.power:IsShown()) and healthH or bh
                d.health:SetHeight(hh)
            end
            if d.nameText then d.nameText:SetWidth(bw * 0.75) end
            -- Live-rescale indicators/auras. No-op for hidden buttons / no unit
            -- (e.g. options menu while not grouped), so cheap there.
            if autoResize and ns.BM_UpdateIndicators and btn:IsVisible() then
                local u = btn:GetAttribute("unit")
                if u then ns.BM_UpdateIndicators(btn, u, db) end
            end
        end
    end
    -- Container resize deferred to drag end (SetSize on the container
    -- triggers SecureGroupHeaderTemplate to re-process children, causing blink)

end

-- Apply tier-based position offset to the container frame.
-- Adds the active tier's offsetX/Y on top of the saved unlock position.
ns._ApplyTierOffset = function()
    if not containerFrame or InCombatLockdown() then return end
    local pos = db.profile.unlockPos
    if not pos then return end
    local ox, oy = 0, 0
    local numMembers = GetNumGroupMembers()
    if numMembers > 0 then
        local s = db.profile
        local overrides = s.raidSizeOverrides
        if overrides then
            local tier
            if numMembers <= 10 then     tier = 10
            elseif numMembers <= 15 then tier = 15
            elseif numMembers <= 20 then tier = 20
            elseif numMembers <= 25 then tier = 25
            else                         tier = 30
            end
            if tier ~= 20 then
                -- Cascade toward 20 (same logic as _GetRaidSizeFrameDimensions)
                local ov
                if tier < 20 then
                    ov = overrides[tier] or (tier == 10 and overrides[15]) or nil
                else
                    ov = overrides[tier] or (tier == 30 and overrides[25]) or nil
                end
                if ov then
                    ox = ov.offsetX or 0
                    oy = ov.offsetY or 0
                end
            end
        end
    end
    containerFrame:ClearAllPoints()
    containerFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x + ox, pos.y + oy)
end

-------------------------------------------------------------------------------
--  Range fading
--  Event-driven via UNIT_IN_RANGE_UPDATE for the standard ~40yd interact range
--  (all classes), which also covers dead units (they use UnitInRange like the
--  living). A conditional 0.5s refiner poll handles only what the event cannot:
--  the tighter friendly-spell range (Evoker/Rogue) and re-syncing a revived unit
--  back to that tight range. Pure classes with no rez run fully event-driven.
-------------------------------------------------------------------------------
-- Wrapped in a do-block so these helpers stay out of the main chunk's 200-local
-- cap; only Start/StopRangeTicker (+ the forward-declared RangeUpdate) need to
-- be reachable from later code.
local StartRangeTicker, StopRangeTicker
do
local rangeTicker = nil

local UnitPhaseReason = UnitPhaseReason
local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange

-- Classes whose effective reach is well under the ~40yd UnitInRange interact
-- range, so living units are refined with a tighter friendly spell check.
local usesSpellRange = playerFriendlySpell ~= nil
-- Whether the player can resurrect (enables dead-unit rez-range refinement).
local playerHasRez   = playerRezSpell ~= nil

-- Apply final alpha to a button: range alpha * BM frame alpha. Range alpha is
-- stored in FFD so BM can read it; BM alpha lives in _bmSavedAlpha so range can
-- read it. Each system stores its own value; final apply multiplies the two.
local function ApplyRangeAlpha(btn, rangeAlpha)
    local d = GetFFD(btn)
    d.rangeAlpha = rangeAlpha
    local bmA = btn._bmSavedAlpha or 1
    btn:SetAlpha(bmA * rangeAlpha)
end

-- Secret-safe range alpha via SetAlphaFromBoolean (UnitInRange can return a
-- secret boolean in Midnight). Marks rangeAlpha nil so UpdateButton/BM leave
-- the secret-set alpha alone.
local function ApplyRangeAlphaSecret(btn, inRange, inAlpha, outAlpha)
    local bmA = btn._bmSavedAlpha or 1
    if btn.SetAlphaFromBoolean then
        btn:SetAlphaFromBoolean(inRange, bmA * inAlpha, bmA * outAlpha)
    else
        ApplyRangeAlpha(btn, inAlpha)
        return
    end
    GetFFD(btn).rangeAlpha = nil
end

-- Evaluate + apply range alpha for ONE unit. Shared by the
-- UNIT_IN_RANGE_UPDATE event, the refiner poll, the seed pass, and roster
-- assignment. Standard living units take the secret-safe UnitInRange path.
local function UpdateButtonRange(unit, btn)
    -- Read oorAlpha through the party-aware proxy so a custom party_oorAlpha
    -- actually applies to party frames (was reading the raid value directly).
    local rd = GetFFD(btn)
    local rs = rd._isParty and ns._scaledPartyProxy or ns._scaledProfile
    local oorAlpha = rs.oorAlpha or 0.4
    if UnitIsUnit(unit, "player") or not UnitExists(unit) then
        ApplyRangeAlpha(btn, 1)
    elseif UnitPhaseReason and UnitPhaseReason(unit) then
        ApplyRangeAlpha(btn, oorAlpha)
    elseif UnitIsDeadOrGhost(unit) then
        -- Dead units use the standard ~40yd interact range (UnitInRange), the same
        -- secret-safe path living non-spell-range units take, so corpses fade once
        -- the player moves out of range. The old rez-spell-only check forced full
        -- alpha whenever the player had no rez (most DPS) or the rez range came back
        -- indeterminate, which left dead players stuck at full alpha regardless of range.
        ApplyRangeAlphaSecret(btn, UnitInRange(unit), 1, oorAlpha)
    elseif usesSpellRange then
        local r = C_Spell_IsSpellInRange(playerFriendlySpell, unit)
        if r == true then
            ApplyRangeAlpha(btn, 1)
        elseif r == false then
            ApplyRangeAlpha(btn, oorAlpha)
        else
            -- r == nil: the friendly spell has NO range relationship to this unit.
            -- Because this spell is unit-targeted, a same-zone out-of-range target
            -- still returns false (handled above), so nil means the unit is
            -- genuinely unreachable -- almost always a DIFFERENT ZONE (or a brief
            -- untargetable / LOS blip). Resolve it via the secret-safe ~40yd
            -- UnitInRange (false for a different-zone unit -> faded) instead of
            -- holding the last alpha: holding left a unit that moved to another
            -- zone stuck at the in-range alpha it had before leaving. This cannot
            -- reintroduce the 25-vs-40yd boundary flicker -- that needed the spell
            -- check to return nil AT the boundary, which it does not for a valid
            -- same-zone target (UnitInRange here is stable because the unit is far).
            ApplyRangeAlphaSecret(btn, UnitInRange(unit), 1, oorAlpha)
        end
    else
        ApplyRangeAlphaSecret(btn, UnitInRange(unit), 1, oorAlpha)
    end
end
ns._UpdateButtonRange = UpdateButtonRange

-- Refiner handles only what UNIT_IN_RANGE_UPDATE cannot: the tighter
-- friendly-spell range (Evoker/Rogue). Dead units use the event-driven
-- UnitInRange path like living units, but are still polled so a spell-range
-- class hands a revived unit back to its tight spell range (one-shot resync via
-- _rangeWasDead). Living, non-spell-range units are owned by the event and
-- skipped here, so the poll does ~no work for a stable raid.
local function RefineButtonRange(unit, btn)
    if not UnitExists(unit) or UnitIsUnit(unit, "player") then return end
    local d = GetFFD(btn)
    if UnitIsDeadOrGhost(unit) then
        d._rangeWasDead = true
        UpdateButtonRange(unit, btn)
    elseif d._rangeWasDead then
        d._rangeWasDead = nil
        UpdateButtonRange(unit, btn)
    elseif usesSpellRange then
        UpdateButtonRange(unit, btn)
    end
end

-- Seed / full re-evaluation of every assigned unit (enable, roster change,
-- phase change). Kept as RangeUpdate (forward-declared) for existing callers.
RangeUpdate = function()
    local t0 = ns.ProfBegin("RangeUpdate")
    for unit, btn in pairs(unitToButton) do UpdateButtonRange(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do UpdateButtonRange(unit, btn) end
    ns.ProfEnd("RangeUpdate", t0)
end
ns._RangeSeedAll = RangeUpdate

local function RangeRefineAll()
    local t0 = ns.ProfBegin("RangeRefine")
    for unit, btn in pairs(unitToButton) do RefineButtonRange(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do RefineButtonRange(unit, btn) end
    ns.ProfEnd("RangeRefine", t0)
end

function StartRangeTicker()
    -- Seed initial alpha; UNIT_IN_RANGE_UPDATE only fires on later changes.
    RangeUpdate()
    -- Conditional refiner: only spell-range or rez-capable classes poll.
    -- Everyone else is fully event-driven (zero polling).
    if not rangeTicker and (usesSpellRange or playerHasRez) then
        rangeTicker = C_Timer.NewTicker(0.5, RangeRefineAll)
    end
end

function StopRangeTicker()
    if rangeTicker then
        rangeTicker:Cancel()
        rangeTicker = nil
    end
    -- Reset range alpha, respect BM frame alpha
    for _, btn in pairs(unitToButton) do ApplyRangeAlpha(btn, 1) end
    for _, btn in pairs(ns._partyUnitToButton) do ApplyRangeAlpha(btn, 1) end
end
end  -- range fading section (do-block keeps its locals out of the 200-cap)

-------------------------------------------------------------------------------
--  Ghost aura safety net
--  Throttled 1s ticker clears stale debuff/BM/dispel indicators when a unit
--  goes invisible (loadscreen, out of render range) or disconnects. Without
--  this, indicators painted before the unit ghosted persist indefinitely
--  because UNIT_AURA stops firing for invisible/DC'd units.
-------------------------------------------------------------------------------
local ghostTicker = nil

local function GhostAuraCheck()
    local t0 = ns.ProfBegin("GhostAuraCheck")
    local function checkUnit(unit, btn)
        local d = GetFFD(btn)
        if not UnitIsVisible(unit) or not UnitIsConnected(unit) then
            if not d.ghostCleared then
                d.ghostCleared = true
                if d.debuffIcons then
                    for _, icon in ipairs(d.debuffIcons) do
                        icon:Hide()
                        if icon._durText and ns.UnregisterDurText then
                            ns.UnregisterDurText(icon._durText)
                        end
                    end
                end
                d.debuffCache = nil
                d.debuffInstanceMap = nil
                if d.defIcons then
                    for _, icon in ipairs(d.defIcons) do
                        icon:Hide()
                        if icon._durText and ns.UnregisterDurText then
                            ns.UnregisterDurText(icon._durText)
                        end
                    end
                end
                HideDispelVisuals(d)
                if ns.BM_ClearIndicators then
                    ns.BM_ClearIndicators(btn)
                end
            end
        else
            if d.ghostCleared then
                d.ghostCleared = false
            end
        end
    end
    for unit, btn in pairs(unitToButton) do checkUnit(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do checkUnit(unit, btn) end
    ns.ProfEnd("GhostAuraCheck", t0)
end

local function StartGhostTicker()
    if not ghostTicker then
        ghostTicker = C_Timer.NewTicker(1.0, GhostAuraCheck)
    end
end

local function StopGhostTicker()
    if ghostTicker then
        ghostTicker:Cancel()
        ghostTicker = nil
    end
    -- Clear ghost flags
    for _, btn in pairs(unitToButton) do
        local d = GetFFD(btn)
        d.ghostCleared = nil
    end
    for _, btn in pairs(ns._partyUnitToButton) do
        local d = GetFFD(btn)
        d.ghostCleared = nil
    end
end

-------------------------------------------------------------------------------
--  Visibility: show/hide based on solo/group/raid setting
-------------------------------------------------------------------------------
local framesVisible = false

local function UpdateVisibility()
    if not containerFrame then return end
    if InCombatLockdown() then return end

    -- Preview overrides all visibility logic -- container stays shown,
    -- real buttons stay suppressed, no state changes.
    if previewActive then return end

    -- Defensive: re-assert full opacity unless a preview is intentionally
    -- dimming the real frames. The preview system is the only thing that lowers
    -- container alpha; this runs out of combat only (the function bails in combat
    -- above) and heals any case where alpha was left at 0 with the flags cleared.
    -- Gated on the party-preview flag too so a raid-visibility recompute never
    -- un-hides the raid container behind an active party preview.
    if not ns._sizePreviewTier and not ns._partyPvActive then containerFrame:SetAlpha(1) end

    local s = db.profile
    local visible = false
    if IsInRaid() then
        visible = true
    elseif IsInGroup() then
        visible = false  -- party frames handle group visibility
    else
        visible = s.showWhenSolo
    end
    local wasVisible = framesVisible
    framesVisible = visible

    -- Update showSolo attribute on all headers, but ONLY when it actually
    -- differs from the header's current value. Re-setting a SecureGroupHeader
    -- attribute re-triggers Blizzard's full child re-process (re-sort/re-assign)
    -- even when unchanged, so doing it every combat exit / visibility recompute
    -- was a large needless secure-header spike. showWhenSolo is a static setting;
    -- mirrors the needsHideShow guard in ApplySortToHeaders.
    local wantSolo = s.showWhenSolo or false
    for _, hdr in ipairs(separatedHdrs) do
        if hdr and hdr:GetAttribute("showSolo") ~= wantSolo then
            hdr:SetAttribute("showSolo", wantSolo)
        end
    end
    if ns._flatHeader and ns._flatHeader:GetAttribute("showSolo") ~= wantSolo then
        ns._flatHeader:SetAttribute("showSolo", wantSolo)
    end

    if visible then
        containerFrame:Show()
        -- Suppress Blizzard party frames when we're showing for groups
        if (IsInGroup() and not IsInRaid()) and ns._SuppressBlizzParty then
            ns._SuppressBlizzParty()
        end
        -- Skip heavy refresh at combat end if roster didn't change.
        -- Per-unit events (UNIT_HEALTH, UNIT_AURA, etc.) kept buttons in
        -- sync during combat, so a full rebuild is only needed when the
        -- roster changed or we transition from hidden to visible.
        -- Heavy content rebuild ONLY when it could actually be stale: a real
        -- hidden->visible transition (unitToButton was wiped on hide) or a
        -- caller that flagged a roster/size change. Re-checking visibility while
        -- already shown and unchanged skips the 40-button rebuild -- the live
        -- per-unit events kept every button current the whole time. This
        -- generalizes the old combat-exit "lightweight" skip to every caller
        -- (preview restore, EnsureRealFramesRestored, etc.) so a redundant
        -- visibility recompute can never trigger a full refresh spike.
        local forceRebuild = ns._visForceRebuild
        ns._visForceRebuild = nil
        if (not wasVisible) or forceRebuild then
            RebuildUnitMap()
            if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
            UpdateAllButtons()
        end
        if IsInGroup() or IsInRaid() then
            StartRangeTicker()
            StartGhostTicker()
        end
    else
        containerFrame:Hide()
        StopRangeTicker()
        StopGhostTicker()
        -- Clean up private aura anchors when hiding
        for unit, btn in pairs(unitToButton) do
            UnregisterPrivateAuras(btn)
        end
        wipe(unitToButton)
    end
end
ns.UpdateVisibility = UpdateVisibility

-------------------------------------------------------------------------------
--  Aura-storm throttle (UNIT_AURA only). Steady-state events process
--  immediately; only a genuine single-frame flood (the pull-start/-end aura
--  storm or a raid-wide aura event) spills the overflow into a drain ticker
--  that processes a bounded number of units per frame, draining ~40 units in
--  ~4 frames. The deferred path does a FULL current-state rescan (nil
--  updateInfo), so it never replays a stale delta -- nothing is ever wrong or
--  dropped, only shown a few frames later. Health, power, and the dispel
--  border are NEVER throttled (own immediate paths), so death and dispel
--  signals stay instant; only informational aura icons can briefly lag. State
--  lives on ns (not file locals) to respect this file's Lua 5.1 local cap.
-------------------------------------------------------------------------------
ns._auraBudget = 10       -- units processed immediately per frame before spilling
ns._auraFrameStamp = 0    -- GetTime() of the frame the immediate budget last reset
ns._auraFrameN = 0        -- units processed immediately this frame
ns._auraDirty = {}        -- [unit] = true: deferred, awaiting a full rescan
ns._auraDirtyN = 0

-- Full current-state aura refresh for one unit (deferred drain path; lossless
-- because nil updateInfo forces each consumer's full-scan branch).
ns._FlushUnitAuras = function(unit)
    local btn = unitToButton[unit] or ns._partyUnitToButton[unit]
    if not btn then return end
    UpdateDebuffs(btn, unit)
    UpdateDefensives(btn, unit)
    UpdateAbsorb(btn, unit)
    if ns.BM_UpdateIndicators then ns.BM_UpdateIndicators(btn, unit, db) end
end

ns._auraDrainFrame = CreateFrame("Frame")
ns._auraDrainFrame:Hide()
ns._auraDrainFrame:SetScript("OnUpdate", function(self)
    local n = 0
    for unit in pairs(ns._auraDirty) do
        ns._auraDirty[unit] = nil
        ns._auraDirtyN = ns._auraDirtyN - 1
        ns._FlushUnitAuras(unit)
        n = n + 1
        if n >= ns._auraBudget then break end
    end
    -- Authoritative empty check (not the counter) so the OnUpdate always hides
    -- when the backlog is drained, even if the count ever drifts.
    if next(ns._auraDirty) == nil then ns._auraDirtyN = 0; self:Hide() end
end)

-------------------------------------------------------------------------------
--  Event handlers
-------------------------------------------------------------------------------
local function OnEvent(self, event, arg1, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        -- HARD INVARIANT: the real party/raid frames must never be left hidden
        -- when a pull starts. Every restore op reached from here is combat-legal
        -- (SetAlpha on our own containers; Hide/SetParent on our own non-secure
        -- preview frames), so it can never be blocked or deferred. This forces
        -- the frames fully visible the instant combat begins, even if a preview
        -- or size preview was still active, independent of the panel auto-close.
        if ns._sizePreviewTier then
            ns._sizePreviewTier = nil
            if ns._HideSizePreview then ns._HideSizePreview() end
        end
        if ns.EnsureRealFramesRestored then ns.EnsureRealFramesRestored() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        -- Complete any container reparent that was blocked during combat (e.g.
        -- the options panel was closed mid-combat while a preview was active).
        -- Without this, a combat auto-close can leave the real frames orphaned
        -- under the hidden preview parent until the next options open+close.
        if ns._restorePending then
            ns._restorePending = nil
            if ns.EnsureRealFramesRestored then ns.EnsureRealFramesRestored() end
        end
        local rosterDirty = ns._rosterDirtyInCombat
        local sizeTierDirty = ns._sizeTierDirtyInCombat
        -- Force the heavy refresh ONLY if the roster/size changed during combat.
        -- Otherwise the live per-unit events kept buttons current and the
        -- transition gate in UpdateVisibility skips the rebuild.
        if rosterDirty or sizeTierDirty then
            ns._visForceRebuild = true
        end
        ns._rosterDirtyInCombat = nil
        ns._sizeTierDirtyInCombat = nil
        local t0 = ns.ProfBegin("Visibility:REGEN"); UpdateVisibility(); ns.ProfEnd("Visibility:REGEN", t0)
        ns._UpdatePartyVisibility()
        if rosterDirty or sizeTierDirty then
            if framesVisible then
                if sizeTierDirty then
                    -- Size tier crossed during combat: full reload now safe
                    ReloadFrames()
                else
                    t0 = ns.ProfBegin("LayoutGroups:REGEN"); LayoutGroups(); ns.ProfEnd("LayoutGroups:REGEN", t0)
                end
            end
            if ns._partyFramesVisible then
                ns._LayoutPartyFrames()
            end
        end
    elseif event == "PLAYER_ROLES_ASSIGNED" then
        -- Roles changed: refresh raid sort so the player's-group nameList
        -- (Show Self First) re-orders the rest by the new roles. The other
        -- groups re-sort natively. Out of combat only; no-op if order unchanged.
        if not inCombat and framesVisible and ns._ApplySortToHeaders then
            ns._ApplySortToHeaders()
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
        if inCombat then
            ns._rosterDirtyInCombat = true
            -- Check if size tier changed during combat (deferred to REGEN)
            local numMembers = GetNumGroupMembers()
            if numMembers > 0 then
                local newW, newH = ns._GetRaidSizeFrameDimensions(numMembers)
                if newW ~= ns._activeSizeW or newH ~= ns._activeSizeH then
                    ns._sizeTierDirtyInCombat = true
                end
            end
            -- Rebuild unit maps during combat so new/moved members get events.
            if framesVisible then
                local t0 = ns.ProfBegin("RebuildUnitMap:COMBAT")
                wipe(unitToButton)
                for _, btn in ipairs(allButtons) do
                    if btn:IsVisible() then
                        local u = btn:GetAttribute("unit")
                        if u then
                            unitToButton[u] = btn
                            local d = GetFFD(btn)
                            local _, classToken = UnitClass(u)
                            d.classToken = classToken
                        end
                    end
                end
                ns.ProfEnd("RebuildUnitMap:COMBAT", t0)
                t0 = ns.ProfBegin("UpdateAll:COMBAT_ROSTER")
                for _, btn in ipairs(allButtons) do
                    local u = btn:GetAttribute("unit")
                    if u and btn:IsVisible() then
                        UpdateButton(btn)
                        ns._UpdateButtonRange(u, btn)
                        UpdateDebuffs(btn, u)
                        UpdateDefensives(btn, u)
                        UpdateDispelBorder(btn, u)
                        if ns.BM_UpdateIndicators then
                            ns.BM_UpdateIndicators(btn, u, db)
                        end
                    end
                end
                ns.ProfEnd("UpdateAll:COMBAT_ROSTER", t0)
            end
            -- Party frames: rebuild unit map + update during combat
            if ns._partyFramesVisible then
                wipe(ns._partyUnitToButton)
                for _, btn in ipairs(ns._partyAllButtons) do
                    if btn:IsVisible() then
                        local u = btn:GetAttribute("unit")
                        if u then
                            ns._partyUnitToButton[u] = btn
                            local d = GetFFD(btn)
                            local _, classToken = UnitClass(u)
                            d.classToken = classToken
                        end
                    end
                end
                for _, btn in ipairs(ns._partyAllButtons) do
                    local u = btn:GetAttribute("unit")
                    if u and btn:IsVisible() then
                        UpdateButton(btn)
                        ns._UpdateButtonRange(u, btn)
                        UpdateDebuffs(btn, u)
                        UpdateDefensives(btn, u)
                        UpdateDispelBorder(btn, u)
                        if ns.BM_UpdateIndicators then
                            ns.BM_UpdateIndicators(btn, u, db)
                        end
                    end
                end
            end
            return
        end
        if ns._rosterUpdateTimer then
            ns._rosterUpdateTimer:Cancel()
        end
        ns._rosterUpdateTimer = C_Timer.NewTimer(0, function()
            ns._rosterUpdateTimer = nil
            -- Roster changed (out of combat). We never force UpdateVisibility's
            -- full 40-button rebuild here. The per-button OnAttributeChanged hook
            -- already fully repainted (incl. auras) every button whose unit was
            -- (re)assigned, so a blanket aura re-scan x40 is redundant. React 
            -- per-unit instead of rebuilding all. We still UpdateButton each visible
            -- button (no aura rescan) so leader/role/marker/health for
            -- UNCHANGED-token units stay correct -- e.g. a new leader after the
            -- old one left, which keeps its token so the hook won't fire.
            local numMembers = GetNumGroupMembers()
            local newW, newH = ns._GetRaidSizeFrameDimensions(numMembers > 0 and numMembers or 1)
            local tierChanged = (newW ~= ns._activeSizeW or newH ~= ns._activeSizeH)
            local wasVis = framesVisible
            ns._visForceRebuild = nil
            local t0 = ns.ProfBegin("Visibility:ROSTER"); UpdateVisibility(); ns.ProfEnd("Visibility:ROSTER", t0)
            ns._UpdatePartyVisibility()
            if framesVisible then
                if tierChanged then
                    -- Tier changed: full reload (recalculates _activeSizeW/H, restyles).
                    ReloadFrames()
                    if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
                elseif not wasVis then
                    -- Hidden->visible transition: UpdateVisibility already ran the
                    -- full rebuild (RebuildUnitMap + UpdateAllButtons); just lay out.
                    t0 = ns.ProfBegin("LayoutGroups:ROSTER"); LayoutGroups(); ns.ProfEnd("LayoutGroups:ROSTER", t0)
                else
                    -- Already visible, same tier: light refresh only. Aura
                    -- full-rescans are intentionally skipped (hook + UNIT_AURA
                    -- keep them current); UpdateButton keeps leader/role/health.
                    RebuildUnitMap()
                    if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
                    for _, btn in ipairs(allButtons) do
                        if btn:IsVisible() and btn:GetAttribute("unit") then UpdateButton(btn) end
                    end
                    t0 = ns.ProfBegin("LayoutGroups:ROSTER"); LayoutGroups(); ns.ProfEnd("LayoutGroups:ROSTER", t0)
                end
            end
            if ns._partyFramesVisible then
                ns._LayoutPartyFrames()
            end
        end)
    elseif not framesVisible and not ns._partyFramesVisible then
        -- Skip all per-unit event processing when no frames are visible
        return
    elseif event == "UNIT_IN_RANGE_UPDATE" then
        -- Standard ~40yd range change for this unit (event-driven, debounced).
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            local t0 = ns.ProfBegin("RangeEvent")
            ns._UpdateButtonRange(arg1, btn)
            ns.ProfEnd("RangeEvent", t0)
        end
    elseif event == "UNIT_PHASE" then
        -- Phasing doesn't fire UNIT_IN_RANGE_UPDATE; re-evaluate all (rare).
        if ns._RangeSeedAll then ns._RangeSeedAll() end
    elseif event == "UNIT_HEALTH" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then local t0 = ns.ProfBegin("UpdateButton:HEALTH"); ns._UpdateButtonHealth(btn); ns.ProfEnd("UpdateButton:HEALTH", t0) end
    elseif event == "UNIT_MAXHEALTH" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then local t0 = ns.ProfBegin("UpdateButton:MAXHEALTH"); ns._UpdateButtonHealth(btn); ns.ProfEnd("UpdateButton:MAXHEALTH", t0) end
    elseif event == "UNIT_POWER_UPDATE" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn and GetFFD(btn).power then
            local t0 = ns.ProfBegin("PowerUpdate")
            local d = GetFFD(btn)
            local pType = UnitPowerType(arg1) or 0
            -- Percent-based, secret-safe (see UpdateButton power block).
            d.power:SetMinMaxValues(0, 100)
            d.power:SetValue(UnitPowerPercent(arg1, pType, true, CurveConstants.ScaleTo100))
            local pr, pg, pb = GetPowerColor(arg1)
            d.power:SetStatusBarColor(pr, pg, pb, 1)
            ns.ProfEnd("PowerUpdate", t0)
        end
    elseif event == "UNIT_AURA" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            local updateInfo = ...
            -- Dispel border is the dispel signal: never throttled, always now.
            local t0 = ns.ProfBegin("UpdateDispelBorder"); UpdateDispelBorder(btn, arg1, updateInfo); ns.ProfEnd("UpdateDispelBorder", t0)
            -- Informational aura icons: immediate under the per-frame budget; a
            -- single-frame flood spills the overflow to the drain ticker, which
            -- full-rescans current state a few frames later (lossless).
            local now = GetTime()
            if now ~= ns._auraFrameStamp then ns._auraFrameStamp = now; ns._auraFrameN = 0 end
            if ns._auraFrameN < ns._auraBudget then
                ns._auraFrameN = ns._auraFrameN + 1
                if ns._auraDirty[arg1] then ns._auraDirty[arg1] = nil; ns._auraDirtyN = ns._auraDirtyN - 1 end
                t0 = ns.ProfBegin("UpdateDebuffs"); UpdateDebuffs(btn, arg1, updateInfo); ns.ProfEnd("UpdateDebuffs", t0)
                t0 = ns.ProfBegin("UpdateDefensives"); UpdateDefensives(btn, arg1, updateInfo); ns.ProfEnd("UpdateDefensives", t0)
                t0 = ns.ProfBegin("UpdateAbsorb:AURA"); UpdateAbsorb(btn, arg1); ns.ProfEnd("UpdateAbsorb:AURA", t0)
                if ns.BM_UpdateIndicators then
                    t0 = ns.ProfBegin("BM_UpdateIndicators"); ns.BM_UpdateIndicators(btn, arg1, db, updateInfo); ns.ProfEnd("BM_UpdateIndicators", t0)
                end
            elseif not ns._auraDirty[arg1] then
                ns._auraDirty[arg1] = true
                ns._auraDirtyN = ns._auraDirtyN + 1
                ns._auraDrainFrame:Show()
            end
        end
    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
        or event == "UNIT_HEAL_PREDICTION" or event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then local t0 = ns.ProfBegin("UpdateAbsorb:OTHER"); UpdateAbsorb(btn, arg1); ns.ProfEnd("UpdateAbsorb:OTHER", t0) end
    elseif event == "UNIT_NAME_UPDATE" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then UpdateButton(btn) end
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            local t0 = ns.ProfBegin("ThreatUpdate")
            local d = GetFFD(btn)
            if d.threatFrame then
                local bs = db.profile.threatBorderSize or 0
                if bs > 0 then
                    local status = UnitThreatSituation(arg1)
                    if status and THREAT_ACTIVE[status] and PP then
                        PP.UpdateBorder(d.threatFrame, bs, 1, 0, 0, 1)
                        d.threatFrame:Show()
                    else
                        d.threatFrame:Hide()
                    end
                else
                    d.threatFrame:Hide()
                end
            end
            ns.ProfEnd("ThreatUpdate", t0)
        end
    elseif event == "PLAYER_FLAGS_CHANGED" or event == "UNIT_CONNECTION" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then UpdateButton(btn) end
    elseif event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE" then
        -- Only status text / health color changes (online/offline)
        local t0 = ns.ProfBegin("UpdateAll:PARTY_MEMBER")
        if not previewActive then
            for _, btn in ipairs(allButtons) do
                local u = btn:GetAttribute("unit")
                if u and btn:IsVisible() then UpdateButton(btn) end
            end
        end
        if not ns._partyPvActive then
            for _, btn in ipairs(ns._partyAllButtons) do
                local u = btn:GetAttribute("unit")
                if u and btn:IsVisible() then UpdateButton(btn) end
            end
        end
        ns.ProfEnd("UpdateAll:PARTY_MEMBER", t0)
    elseif event == "RAID_TARGET_UPDATE" then
        local t0 = ns.ProfBegin("UpdateRaidMarkers"); ns._UpdateRaidMarkers(); ns.ProfEnd("UpdateRaidMarkers", t0)
    elseif event == "PLAYER_TARGET_CHANGED" then
        local t0 = ns.ProfBegin("UpdateTargetBorders"); ns._UpdateTargetBorders(); ns.ProfEnd("UpdateTargetBorders", t0)
    elseif event == "READY_CHECK" then
        local t0 = ns.ProfBegin("ReadyCheck:START")
        readyCheckActive = true
        for _, btn in ipairs(allButtons) do
            local u = btn:GetAttribute("unit")
            if u and btn:IsVisible() then UpdateReadyCheck(btn, u) end
        end
        for _, btn in ipairs(ns._partyAllButtons) do
            local u = btn:GetAttribute("unit")
            if u and btn:IsVisible() then UpdateReadyCheck(btn, u) end
        end
        ns.ProfEnd("ReadyCheck:START", t0)
    elseif event == "READY_CHECK_CONFIRM" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then UpdateReadyCheck(btn, arg1) end
    elseif event == "READY_CHECK_FINISHED" then
        readyCheckActive = false
        C_Timer.After(5, function()
            if not readyCheckActive then
                for _, btn in ipairs(allButtons) do
                    local d = GetFFD(btn)
                    if d.readyCheck then d.readyCheck:Hide() end
                end
                for _, btn in ipairs(ns._partyAllButtons) do
                    local d = GetFFD(btn)
                    if d.readyCheck then d.readyCheck:Hide() end
                end
            end
        end)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if ns.BM_RebuildLookup then ns.BM_RebuildLookup(db) end
        -- BM_RebuildLookup only rebuilds the global spell-lookup tables for the
        -- new spec; it re-renders no button and never clears any per-button
        -- bmActiveInstanceIDs cache. The render-side quick-skip in
        -- BM_UpdateIndicators then freezes the currently-drawn icons until an
        -- aura event happens to touch a tracked spell or a still-cached instance
        -- id -- which a self-cast HoT that simply keeps ticking never triggers,
        -- so a stale old-spec icon would stay stuck until /reload. Force a full
        -- BM rescan (no updateInfo) on every visible button so old icons clear
        -- and the new spec config renders. Spec changes cannot occur in combat,
        -- and BM_UpdateIndicators only touches our own pooled child frames (never
        -- SetSize/SetPoint on the secure buttons), so this is safe.
        if ns.BM_UpdateIndicators then
            if framesVisible then
                for _, btn in ipairs(allButtons) do
                    local u = btn:GetAttribute("unit")
                    if u and btn:IsVisible() then ns.BM_UpdateIndicators(btn, u, db) end
                end
            end
            if ns._partyFramesVisible then
                for _, btn in ipairs(ns._partyAllButtons) do
                    local u = btn:GetAttribute("unit")
                    if u and btn:IsVisible() then ns.BM_UpdateIndicators(btn, u, db) end
                end
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            -- Zoning in mid-combat (e.g. into a raid where trash is already
            -- pulled) must NOT run the reload here: ReloadFrames calls SetSize on
            -- the protected SecureGroupHeader buttons, which Blizzard blocks in
            -- combat (ADDON_ACTION_BLOCKED). Defer the full reload to combat end
            -- via the existing size-tier dirty flag; PLAYER_REGEN_ENABLED re-runs
            -- UpdateVisibility + ReloadFrames + the party layout once it is safe.
            -- The other calls below already self-bail in combat, so skipping them
            -- until REGEN is behavior-neutral.
            if InCombatLockdown() then
                ns._sizeTierDirtyInCombat = true
                return
            end
            local t0 = ns.ProfBegin("Visibility:PEW"); UpdateVisibility(); ns.ProfEnd("Visibility:PEW", t0)
            ns._UpdatePartyVisibility()
            if framesVisible then
                -- Full reload to recalculate tier dimensions from current group size
                t0 = ns.ProfBegin("ReloadFrames:PEW"); ReloadFrames(); ns.ProfEnd("ReloadFrames:PEW", t0)
            end
            if ns._partyFramesVisible then
                ns._LayoutPartyFrames()
            end
        end)
    end
end

-------------------------------------------------------------------------------
--  Unlock mode registration
-------------------------------------------------------------------------------
-- Party container frame (placeholder for unlock mode positioning)
ns._partyContainerFrame = CreateFrame("Frame", nil, UIParent)
ns._partyContainerFrame:SetSize(125, 308)
ns._partyContainerFrame:SetFrameStrata("LOW")
ns._partyContainerFrame:Hide()

-------------------------------------------------------------------------------
--  Party frames: real SecureGroupHeader (5 buttons, reuses all raid rendering)
--  Minimal infrastructure -- StyleButton, UpdateButton, UpdateDebuffs, etc.
--  are the same functions used by raid buttons. Party buttons just get
--  party-specific sizing via ReloadPartyFrames.
-------------------------------------------------------------------------------
ns._partyAllButtons    = {}
ns._partyUnitToButton  = {}
ns._partyHeader        = nil
ns._partyFramesVisible = false

-------------------------------------------------------------------------------
--  Party settings proxy
--  Per-section sync: partySyncSections[sectionKey] = true (synced) or false
--  (custom). Party buttons read "party_<key>" only for keys whose section
--  is unsynced. Falls through to raid value otherwise.
--  ALL tables/functions stored on ns to avoid 200-local cap.
-------------------------------------------------------------------------------
ns._PARTY_KEY_SECTION = {}
ns._PARTY_OVERRIDE_KEYS = {}

ns._PARTY_SECTION_ORDER = {
    "healthBar", "powerBar", "textDisplay", "indicators", "dispels",
    "rangeTooltip", "defensives", "privateAuras", "debuffDisplay", "debuffStyle",
}
ns._PARTY_SECTION_LABELS = {
    healthBar     = "Health Bar",
    powerBar      = "Power Bar",
    textDisplay   = "Text Display",
    indicators    = "Indicators",
    dispels       = "Dispels",
    rangeTooltip  = "Range & Tooltip",
    defensives    = "Defensives & Externals",
    privateAuras  = "Private Auras",
    debuffDisplay = "Debuff Display",
    debuffStyle   = "Debuff Style",
}

do
    local map = {
        healthBar = {
            "healthBarTexture", "healthBarOpacity", "healthColorMode",
            "customFillColor", "customBgColor", "bgDarkness", "smoothBars",
            "absorbStyle", "absorbOpacity", "absorbColor", "absorbFromRightEdge",
            "healAbsorbStyle", "healAbsorbOpacity", "healAbsorbColor",
            "healPrediction", "healPredOpacity", "healPredColor",
        },
        powerBar = {
            "showPowerBar", "powerHeight", "powerBgDarkness", "powerBgColor",
            "powerBorderStyle", "powerBorderSize", "powerBorderColor", "powerBorderAlpha",
            "powerShowForHealer", "powerShowForTank", "powerShowForDPS", "smoothPowerBars",
        },
        textDisplay = {
            "nameSize", "nameColorMode", "nameCustomColor",
            "namePosition", "nameOffsetX", "nameOffsetY",
            "healthTextMode", "healthTextColorMode", "healthTextCustomColor",
            "healthTextSize", "healthTextPosition", "healthTextOffsetX", "healthTextOffsetY",
        },
        indicators = {
            "roleIconStyle", "roleIconSize", "roleIconPosition", "roleIconOffsetX", "roleIconOffsetY",
            "showRoleForTank", "showRoleForHealer", "showRoleForDPS",
            "showRaidMarker", "raidMarkerSize", "raidMarkerPosition", "raidMarkerOffsetX", "raidMarkerOffsetY",
            "showReadyCheck", "showSummonPending",
            "statusTextPosition", "statusTextOffsetX", "statusTextOffsetY", "statusTextSize", "statusTextColor",
            "showLeaderIcon", "leaderIconPosition", "leaderIconSize", "leaderIconOffsetX", "leaderIconOffsetY",
            "borderSize", "borderColor", "borderAlpha", "borderTexture",
            "borderBehind", "borderTextureOffset", "borderTextureOffsetY",
            "borderTextureShiftX", "borderTextureShiftY",
            "hoverBorderEnabled", "hoverBorderSize", "hoverBorderColor", "hoverBorderAlpha",
            "targetBorderEnabled", "targetBorderSize", "targetBorderColor", "targetBorderAlpha", "threatBorderSize",
        },
        dispels = {
            "dispelBorderSize", "dispelOverlay", "dispelOverlayOpacity", "dispelShowAll",
            "showDispelIcons", "dispelIconSize", "dispelIconPosition", "dispelIconOffsetX", "dispelIconOffsetY",
            "dispelColorMagic", "dispelColorCurse", "dispelColorDisease",
            "dispelColorPoison", "dispelColorBleed",
        },
        rangeTooltip = {
            "oorAlpha", "showTooltip", "tooltipInCombat",
        },
        defensives = {
            "showDefensives", "showExternals",
            "defPosition", "defOffsetX", "defOffsetY", "defGrowDirection",
            "defSize", "defSpacing", "defBorderSize", "defBorderColor",
            "defShowSwipe", "defShowDurText", "defDurTextColor", "defDurTextSize", "defDurTextOffsetX", "defDurTextOffsetY",
        },
        privateAuras = {
            "paSize", "paShowCountdown",
            "paPosition", "paOffsetX", "paOffsetY", "paGrowDirection", "paSpacing",
        },
        debuffDisplay = {
            "debuffFilter", "hideLustDebuff",
            "debuffPosition", "debuffOffsetX", "debuffOffsetY",
            "debuffGrowDirection", "debuffCap",
        },
        debuffStyle = {
            "debuffSize", "debuffBorderSize", "debuffBorderColor", "debuffSpacing",
            "debuffShowStacks", "debuffStacksTextColor", "debuffStacksTextSize", "debuffStacksOffsetX", "debuffStacksOffsetY",
            "debuffShowSwipe", "debuffShowDurText", "debuffDurTextColor", "debuffDurTextSize", "debuffDurTextOffsetX", "debuffDurTextOffsetY",
        },
    }
    for section, keys in pairs(map) do
        for _, k in ipairs(keys) do
            ns._PARTY_KEY_SECTION[k] = section
            ns._PARTY_OVERRIDE_KEYS[k] = true
        end
    end
end

ns._IsPartySectionCustom = function(section)
    if not db or not db.profile then return false end
    local ss = db.profile.partySyncSections
    if not ss then return false end
    return ss[section] == false
end

ns._partyProxy = setmetatable({}, {
    __index = function(_, key)
        local section = ns._PARTY_KEY_SECTION[key]
        if section and db and db.profile and ns._IsPartySectionCustom(section) then
            local pv = rawget(db.profile, "party_" .. key)
            if pv ~= nil then return pv end
        end
        return db and db.profile and db.profile[key]
    end,
})

-------------------------------------------------------------------------------
--  Auto-resize indicators: scale all indicator sizes/offsets proportionally
--  when a custom raid size tier is active.  Uses a metatable proxy so
--  rendering functions read scaled values transparently.
-------------------------------------------------------------------------------
ns._indicatorScale = 1
-- Separate scale for party frames (party + raid never display together, but the
-- single global was a conflict trap). Computed by ns._UpdatePartyIndicatorScale.
ns._partyIndicatorScale = 1

local INDICATOR_SCALE_KEYS = {}
for _, k in ipairs({
    -- Font sizes
    "nameSize", "healthTextSize", "statusTextSize",
    "debuffStacksTextSize", "debuffDurTextSize", "defDurTextSize",
    -- Icon sizes
    "roleIconSize", "leaderIconSize", "raidMarkerSize",
    "debuffSize", "defSize", "paSize", "dispelIconSize",
    -- Offsets
    "nameOffsetX", "nameOffsetY",
    "healthTextOffsetX", "healthTextOffsetY",
    "statusTextOffsetX", "statusTextOffsetY",
    "roleIconOffsetX", "roleIconOffsetY",
    "leaderIconOffsetX", "leaderIconOffsetY",
    "raidMarkerOffsetX", "raidMarkerOffsetY",
    "debuffOffsetX", "debuffOffsetY",
    "debuffStacksOffsetX", "debuffStacksOffsetY",
    "debuffDurTextOffsetX", "debuffDurTextOffsetY",
    "defOffsetX", "defOffsetY",
    "defDurTextOffsetX", "defDurTextOffsetY",
    "paOffsetX", "paOffsetY",
    "dispelIconOffsetX", "dispelIconOffsetY",
}) do INDICATOR_SCALE_KEYS[k] = true end

ns._scaledProfile = setmetatable({}, { __index = function(_, key)
    -- Return active tier dimensions so all rendering uses the correct size
    if key == "frameWidth"  and ns._activeSizeW then return ns._activeSizeW end
    if key == "frameHeight" and ns._activeSizeH then return ns._activeSizeH end
    local val = db and db.profile and db.profile[key]
    if INDICATOR_SCALE_KEYS[key] and type(val) == "number" and ns._indicatorScale ~= 1 then
        return val * ns._indicatorScale
    end
    return val
end })

ns._scaledPartyProxy = setmetatable({}, { __index = function(_, key)
    -- Return party dimensions for frameWidth/frameHeight reads
    if key == "frameWidth" then
        return db and db.profile and (db.profile.partyFrameWidth or db.profile.frameWidth)
    end
    if key == "frameHeight" then
        return db and db.profile and (db.profile.partyFrameHeight or db.profile.frameHeight)
    end
    local val = ns._partyProxy[key]
    if INDICATOR_SCALE_KEYS[key] and type(val) == "number" and ns._partyIndicatorScale ~= 1 then
        return val * ns._partyIndicatorScale
    end
    return val
end })

-- Compute the party indicator/aura scale (mirrors the raid auto-resize in
-- ReloadFrames). Party frames have a fixed size (no tiers), so the scale is the
-- party frame size relative to the configured raid base, clamped to [0.7, 1.3].
-- Independent of raid: gated on partyAutoResizeIndicators (default off).
ns._UpdatePartyIndicatorScale = function()
    if not (db and db.profile) then return end
    local s = db.profile
    if s.partyAutoResizeIndicators then
        local baseW = s.frameWidth or 72
        local baseH = s.frameHeight or 46
        local pw = s.partyFrameWidth or s.frameWidth or 125
        local ph = s.partyFrameHeight or s.frameHeight or 60
        local scale = math.min(pw / baseW, ph / baseH)
        ns._partyIndicatorScale = math.max(math.min(scale, 1.3), 0.7)
    else
        ns._partyIndicatorScale = 1
    end
end

ns._IsPartyAllSynced = function()
    if not db or not db.profile then return true end
    local ss = db.profile.partySyncSections
    if not ss then return true end
    for _, sec in ipairs(ns._PARTY_SECTION_ORDER) do
        if ss[sec] == false then return false end
    end
    return true
end

-- Create a single SecureGroupHeader for party frames (5 buttons max).
-- Called once from OnEnable.
ns._CreatePartyHeader = function()
    if ns._partyHeader then return end
    local s = db.profile
    local bw = PixelSnap(s.partyFrameWidth or s.frameWidth or 125)
    local bh = PixelSnap(s.partyFrameHeight or s.frameHeight or 60)
    local cs = PixelSnap(s.partyCellSpacing or s.cellSpacing or 2)

    local initConfig = ([[
        self:SetWidth(%d)
        self:SetHeight(%d)
    ]]):format(bw, bh)

    local hdr = CreateFrame("Frame", "ERFPartyHeader", ns._partyContainerFrame, "SecureGroupHeaderTemplate")
    hdr:SetAttribute("template", "SecureUnitButtonTemplate")
    hdr:SetAttribute("templateType", "Button")
    hdr:SetAttribute("initialConfigFunction", initConfig)
    hdr:SetAttribute("point", "TOP")
    hdr:SetAttribute("xOffset", 0)
    hdr:SetAttribute("yOffset", -cs)
    hdr:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8")
    hdr:SetAttribute("showRaid", false)
    hdr:SetAttribute("showParty", true)
    hdr:SetAttribute("showPlayer", true)
    hdr:SetAttribute("showSolo", s.partyShowWhenSolo or false)
    hdr:SetAttribute("maxColumns", 1)
    hdr:SetAttribute("unitsPerColumn", 5)

    -- Pre-create 5 buttons.
    -- Container must be visible for SecureGroupHeaderTemplate to process
    -- children (IsVisible checks parent chain). Show temporarily, then hide.
    ns._partyContainerFrame:Show()
    hdr:SetAttribute("startingIndex", -4)
    hdr:Show()
    hdr:SetAttribute("startingIndex", 1)
    hdr:Hide()
    ns._partyContainerFrame:Hide()

    -- Style all 5 buttons with shared StyleButton (uses raid sizes initially;
    -- ReloadPartyFrames applies party-specific sizing afterward)
    for i = 1, 5 do
        local btn = hdr[i]
        if btn then
            StyleButton(btn)
            GetFFD(btn)._isParty = true
            ns._partyAllButtons[#ns._partyAllButtons + 1] = btn
        end
    end

    -- Self button for "Show Self First": a static unit="player" secure button
    -- (composition). Because the unit is fixed, nothing the header does can
    -- ever move it -- it is always slot 0 and cannot flicker. When self-first
    -- is on, the party header runs showPlayer=false and this button owns the
    -- player frame; when off, it is hidden and the header shows the player.
    local selfBtn = CreateFrame("Button", "ERFPartySelfButton", ns._partyContainerFrame, "SecureUnitButtonTemplate")
    selfBtn:SetAttribute("unit", "player")
    StyleButton(selfBtn)
    local sd = GetFFD(selfBtn)
    sd._isParty = true
    sd._isSelf = true
    selfBtn:Hide()
    ns._partyAllButtons[#ns._partyAllButtons + 1] = selfBtn
    ns._partySelfButton = selfBtn

    ns._partyHeader = hdr
end

-- Rebuild party unit map from visible party buttons.
ns._RebuildPartyUnitMap = function()
    wipe(ns._partyUnitToButton)
    for _, btn in ipairs(ns._partyAllButtons) do
        if btn:IsVisible() then
            local u = btn:GetAttribute("unit")
            if u then
                ns._partyUnitToButton[u] = btn
                local d = GetFFD(btn)
                local _, classToken = UnitClass(u)
                d.classToken = classToken
                if d.dispelContainerUnit ~= u or d.privateAuraUnit ~= u then
                    RegisterPrivateAuras(btn, u)
                end
            end
        else
            local d = GetFFD(btn)
            if d.dispelContainerAnchorID or (d.privateAuraAnchorIDs and #d.privateAuraAnchorIDs > 0) then
                UnregisterPrivateAuras(btn)
            end
        end
    end
end

-- Full update for all visible party buttons (shared rendering functions).
ns._UpdateAllPartyButtons = function()
    if ns._partyPvActive then return end
    for _, btn in ipairs(ns._partyAllButtons) do
        local u = btn:GetAttribute("unit")
        if u and btn:IsVisible() then
            UpdateButton(btn)
            UpdateDebuffs(btn, u)
            UpdateDefensives(btn, u)
            UpdateDispelBorder(btn, u)
            UpdateReadyCheck(btn, u)
            if ns.BM_UpdateIndicators then
                ns.BM_UpdateIndicators(btn, u, db)
            end
        end
    end
end

-- Layout party frames: apply unitGrowth direction and cell spacing to the header.
ns._LayoutPartyFrames = function()
    if not ns._partyHeader then return end
    if InCombatLockdown() then return end

    local s = db.profile
    local bw = PixelSnap(s.partyFrameWidth or s.frameWidth or 125)
    local bh = PixelSnap(s.partyFrameHeight or s.frameHeight or 60)
    local cs = PixelSnap(s.partyCellSpacing or s.cellSpacing or 2)
    local unitGrowth = s.partyHorizontal and "RIGHT" or "DOWN"

    local hdrPoint, hdrXOff, hdrYOff
    if unitGrowth == "DOWN" then
        hdrPoint = "TOP";    hdrXOff = 0;   hdrYOff = -cs
    elseif unitGrowth == "UP" then
        hdrPoint = "BOTTOM"; hdrXOff = 0;   hdrYOff = cs
    elseif unitGrowth == "RIGHT" then
        hdrPoint = "LEFT";   hdrXOff = cs;  hdrYOff = 0
    else -- LEFT
        hdrPoint = "RIGHT";  hdrXOff = -cs; hdrYOff = 0
    end

    local needsRelayout = ns._partyHeader:GetAttribute("point") ~= hdrPoint
        or ns._partyHeader:GetAttribute("xOffset") ~= hdrXOff
        or ns._partyHeader:GetAttribute("yOffset") ~= hdrYOff
    if needsRelayout then
        local wasShown = ns._partyHeader:IsShown()
        if wasShown then ns._partyHeader:Hide() end
        for i = 1, 5 do
            local btn = ns._partyHeader[i]
            if btn then btn:ClearAllPoints() end
        end
        ns._partyHeader:SetAttribute("point", hdrPoint)
        ns._partyHeader:SetAttribute("xOffset", hdrXOff)
        ns._partyHeader:SetAttribute("yOffset", hdrYOff)
        if wasShown then ns._partyHeader:Show() end
    end

    -- Self-first via composition: a static unit="player" self button owns
    -- slot 0 and the party header excludes the player (showPlayer=false).
    -- Strict player-first only (no tanks-above), so the self button is fully
    -- static and can never be wiped/reordered.
    local pSelfFirst = s.partyShowSelfFirst
    if pSelfFirst == nil then pSelfFirst = s.showSelfFirst end
    local pSelfLast = s.partySelfLast
    if pSelfLast == nil then pSelfLast = s.showSelfLast end
    local hideSelf = s.partyHideSelf
    -- Self ordering only matters in a group. When solo, skip the self button and
    -- let the header show the lone player via showSolo -- otherwise showSolo
    -- forces the player into the header too (showPlayer=false is ignored solo),
    -- duplicating the player frame.
    local useSelf = (pSelfFirst or pSelfLast) and not hideSelf and IsInGroup()

    -- Step between adjacent unit slots along the growth axis (party = DOWN/RIGHT)
    local slotStepX, slotStepY = 0, 0
    if unitGrowth == "RIGHT" then slotStepX = bw + cs else slotStepY = -(bh + cs) end

    -- Size container for unlock mode mover (always sized for 5 units)
    local containerW, containerH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        containerW = 5 * bw + 4 * cs
        containerH = bh
    else
        containerW = bw
        containerH = 5 * bh + 4 * cs
    end
    ns._partyContainerFrame:SetSize(PixelSnap(containerW), PixelSnap(containerH))

    -- Apply sort attributes + player visibility to the party header
    if not InCombatLockdown() then
        local pSortMode = s.partySortMode or s.sortMode
        local sortByRole = pSortMode == "ROLE"
        local wantGroupBy = sortByRole and "ASSIGNEDROLE" or nil
        local wantSortMethod = sortByRole and "NAME" or "INDEX"
        local wantGroupingOrder = ""
        if sortByRole then
            local ro = s.partyRoleOrder or s.roleOrder or { "TANK", "HEALER", "DAMAGER" }
            wantGroupingOrder = table.concat(ro, ",") .. ",NONE"
        end
        -- showPlayer is false when the self button owns the player (useSelf) or
        -- when hiding self; true only for a normal in-header player frame.
        local wantShowPlayer = not hideSelf and not useSelf
        local needsHideShow = (ns._partyHeader:GetAttribute("groupBy") ~= wantGroupBy)
            or (ns._partyHeader:GetAttribute("sortMethod") ~= wantSortMethod)
            or (ns._partyHeader:GetAttribute("groupingOrder") ~= wantGroupingOrder)
            or (ns._partyHeader:GetAttribute("showPlayer") ~= wantShowPlayer)
        if needsHideShow and ns._partyHeader:IsShown() then
            ns._partyHeader:Hide()
            ns._partyHeader:SetAttribute("nameList", nil)
            ns._partyHeader:SetAttribute("groupingOrder", wantGroupingOrder)
            ns._partyHeader:SetAttribute("groupBy", wantGroupBy)
            ns._partyHeader:SetAttribute("sortMethod", wantSortMethod)
            ns._partyHeader:SetAttribute("showPlayer", wantShowPlayer)
            ns._partyHeader:Show()
        elseif needsHideShow then
            ns._partyHeader:SetAttribute("nameList", nil)
            ns._partyHeader:SetAttribute("groupingOrder", wantGroupingOrder)
            ns._partyHeader:SetAttribute("groupBy", wantGroupBy)
            ns._partyHeader:SetAttribute("sortMethod", wantSortMethod)
            ns._partyHeader:SetAttribute("showPlayer", wantShowPlayer)
        end
    end

    -- Position the self button and the party header. Self-first: self owns slot 0
    -- and the header starts at slot 1. Self-last: the header owns slots 0..N-1 and
    -- the self button sits in the slot just after the last other member (count is
    -- live group size minus self; layout re-runs on roster change out of combat).
    local sb = ns._partySelfButton
    if useSelf then
        local selfSlot, hdrSlot = 0, 1
        if pSelfLast then
            local numOthers = (GetNumGroupMembers() or 1) - 1
            if numOthers < 0 then numOthers = 0 end
            selfSlot, hdrSlot = numOthers, 0
        end
        if sb then
            sb:SetSize(bw, bh)
            sb:ClearAllPoints()
            sb:SetPoint("TOPLEFT", ns._partyContainerFrame, "TOPLEFT", PixelSnap(slotStepX * selfSlot), PixelSnap(slotStepY * selfSlot))
            if not InCombatLockdown() then sb:Show() end
        end
        ns._partyHeader:ClearAllPoints()
        ns._partyHeader:SetPoint("TOPLEFT", ns._partyContainerFrame, "TOPLEFT", PixelSnap(slotStepX * hdrSlot), PixelSnap(slotStepY * hdrSlot))
    else
        if sb and not InCombatLockdown() then sb:Hide() end
        ns._partyHeader:ClearAllPoints()
        -- Center When Solo: when not in a group, center the lone player frame in
        -- the container by offsetting the header 2 slots along the growth axis
        -- ((5-1)/2 = 2). The container is always sized for 5 slots (above), so a
        -- single frame at slot 2 sits centered. Only DOWN/RIGHT growth for party,
        -- both covered by slotStepX/slotStepY.
        local cOffX, cOffY = 0, 0
        if s.partyCenterWhenSolo and not IsInGroup() then
            cOffX = slotStepX * 2
            cOffY = slotStepY * 2
        end
        ns._partyHeader:SetPoint("TOPLEFT", ns._partyContainerFrame, "TOPLEFT", PixelSnap(cOffX), PixelSnap(cOffY))
    end
end

-- Party visibility: show/hide based on group state.
ns._UpdatePartyVisibility = function()
    if not ns._partyHeader then return end
    if InCombatLockdown() then return end
    if ns._partyPvActive then return end
    if previewActive then return end
    -- Defensive: re-assert full opacity unless a size preview is dimming the
    -- real frames (see UpdateVisibility). Out of combat only (bails above).
    if not ns._sizePreviewTier and ns._partyContainerFrame then ns._partyContainerFrame:SetAlpha(1) end

    local s = db.profile
    local visible = false
    if IsInGroup() and not IsInRaid() then
        visible = true
    elseif not IsInGroup() then
        visible = s.partyShowWhenSolo
    end
    ns._partyFramesVisible = visible
    if ns._NotifyTrackerProviders then ns._NotifyTrackerProviders() end

    -- Update showSolo attribute, but only when it changed -- re-setting a
    -- SecureGroupHeader attribute re-triggers a full child re-process even when
    -- unchanged (see UpdateVisibility's showSolo guard).
    local wantPartySolo = s.partyShowWhenSolo or false
    if ns._partyHeader and ns._partyHeader:GetAttribute("showSolo") ~= wantPartySolo then
        ns._partyHeader:SetAttribute("showSolo", wantPartySolo)
    end

    if visible then
        ns._partyHeader:Show()
        ns._partyContainerFrame:Show()

        -- Suppress Blizzard party frames
        if ns._SuppressBlizzParty then
            ns._SuppressBlizzParty()
        end

        ns._LayoutPartyFrames()
        ns._RebuildPartyUnitMap()
        if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
        ns._UpdateAllPartyButtons()

        if IsInGroup() then
            StartRangeTicker()
            StartGhostTicker()
        end
    else
        ns._partyHeader:Hide()
        ns._partyContainerFrame:Hide()

        if not framesVisible then
            StopRangeTicker()
            StopGhostTicker()
        end

        for unit, btn in pairs(ns._partyUnitToButton) do
            UnregisterPrivateAuras(btn)
        end
        wipe(ns._partyUnitToButton)
    end
end

-- Reload party frames: apply party-specific sizing then shared rendering.
-- Uses ns._partyProxy for all reads so party overrides take effect.
-- Anchor closures (captured db.profile at StyleButton time) need a temp-swap:
-- we write party_ values onto db.profile, call the closures, then restore.
ns.ReloadPartyFrames = function()
    if not ns._partyHeader then return end
    local p = ns._partyProxy  -- reads party_ keys with fallthrough
    local raw = db.profile

    -- Recompute the party indicator/aura scale (Auto Resize) up front; the
    -- _UpdateAllPartyButtons() call at the end re-renders indicators with it.
    if ns._UpdatePartyIndicatorScale then ns._UpdatePartyIndicatorScale() end

    -- Temp-swap: write party overrides onto db.profile so anchor closures
    -- (which captured db.profile) read party values. Only for keys whose
    -- section is custom (unsynced).
    local saved = {}
    for key, section in pairs(ns._PARTY_KEY_SECTION) do
        if ns._IsPartySectionCustom(section) then
            local pv = rawget(raw, "party_" .. key)
            if pv ~= nil then
                saved[key] = raw[key]
                raw[key] = pv
            end
        end
    end

    -- Now db.profile has party values in place. Read from it directly for
    -- sizing (which also needs party width/height overrides).
    local bw = PixelSnap(raw.partyFrameWidth or raw.frameWidth or 125)
    local bh = PixelSnap(raw.partyFrameHeight or raw.frameHeight or 60)
    local powerH = IsPowerBarEnabled(raw) and PixelSnap(raw.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - powerH)
    local texPath = ResolveHealthTexture()

    for _, btn in ipairs(ns._partyAllButtons) do
        local d = GetFFD(btn)
        if not d.styled then
            StyleButton(btn)
            d._isParty = true
        end

        btn:SetSize(bw, bh)

        -- Background
        if d.bg then
            local bgc = raw.customBgColor
            d.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (raw.bgDarkness or 50) / 100)
        end

        -- Health bar
        if d.health then
            d.health:SetHeight(healthH)
            d.health:SetStatusBarTexture(texPath)
            d.health:GetStatusBarTexture():SetHorizTile(false)
            if d.ReanchorAbsorbToFill then d.ReanchorAbsorbToFill() end
        end

        -- Power bar (always hide here; UpdateButton handles per-role show)
        if d.power then
            d.power:Hide()
            if powerH > 0 then
                d.power:SetHeight(powerH)
                d.power:SetStatusBarTexture(texPath)
                d.power:GetStatusBarTexture():SetHorizTile(false)
            end
        end
        if d.powerBg then
            d.powerBg:SetColorTexture((raw.powerBgColor or {}).r or 0, (raw.powerBgColor or {}).g or 0, (raw.powerBgColor or {}).b or 0, (raw.powerBgDarkness or 70) / 100)
        end
        if d.UpdatePowerBorder then d.UpdatePowerBorder() end

        -- Name text
        if d.nameText then
            ApplyFont(d.nameText, raw.nameSize or 10)
            if d.AnchorNameText then d.AnchorNameText() end
            -- Override width constraint for party button dimensions
            d.nameText:SetWidth(bw * 0.75)
        end

        -- Health text
        if d.healthText then
            ApplyFont(d.healthText, raw.healthTextSize or 9)
            if d.AnchorHealthText then d.AnchorHealthText() end
        end

        -- Status text
        if d.statusText then
            local stc = raw.statusTextColor or { r = 1, g = 1, b = 1 }
            ApplyFont(d.statusText, raw.statusTextSize or 14)
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            if d.AnchorStatusText then d.AnchorStatusText() end
        end

        -- Role icon
        if d.roleIcon then
            local riSz = PixelSnap(raw.roleIconSize or 14)
            d.roleIcon:SetSize(riSz, riSz)
            if d.AnchorRoleIcon then d.AnchorRoleIcon() end
        end

        -- Leader icon
        if d.leaderIcon then
            local liSz = PixelSnap(raw.leaderIconSize or 14)
            d.leaderIcon:SetSize(liSz, liSz)
            d.leaderIcon:ClearAllPoints()
            local liPos = (raw.leaderIconPosition or "top"):upper()
            d.leaderIcon:SetPoint(liPos, d.health, liPos, raw.leaderIconOffsetX or 0, raw.leaderIconOffsetY or 0)
            -- Keep the leader-icon host on the chat frame's current strata/level
            if d.leaderHost then ns.ApplyChatStrata(d.leaderHost) end
        end

        -- Raid marker
        if d.raidMarker then
            local rmSz = PixelSnap(raw.raidMarkerSize or 16)
            d.raidMarker:SetSize(rmSz, rmSz)
            if d.AnchorRaidMarker then d.AnchorRaidMarker() end
        end

        -- Border
        if d.UpdateBorder then d.UpdateBorder() end

        -- Debuff icons
        if d.debuffIcons then
            for _, icon in ipairs(d.debuffIcons) do
                icon:SetSize(raw.debuffSize or 18, raw.debuffSize or 18)
            end
            if d.AnchorDebuffs then d.AnchorDebuffs() end
        end

        -- Defensive icons
        if d.defIcons then
            for _, icon in ipairs(d.defIcons) do
                icon:SetSize(raw.defSize or 22, raw.defSize or 22)
            end
            if d.AnchorDefensives then d.AnchorDefensives() end
        end

        -- Dispel icon
        if d.dispelIcon then
            local diSz = PixelSnap(raw.dispelIconSize or 16)
            d.dispelIcon:SetSize(diSz, diSz)
            if d.AnchorDispelIcon then d.AnchorDispelIcon() end
        end

        -- Private aura frames
        if d.privateAuraFrames then
            for _, paFrame in ipairs(d.privateAuraFrames) do
                paFrame:SetSize(raw.debuffSize or 18, raw.debuffSize or 18)
            end
        end

        -- Buff manager indicators
        if d.bmIconPool and d.health and ns.BM_AnchorIndicators then
            ns.BM_AnchorIndicators(d, d.health, raw)
        end
    end

    -- Restore db.profile to raid values
    for key, val in pairs(saved) do
        raw[key] = val
    end

    -- Re-layout header
    ns._LayoutPartyFrames()
    ns._RebuildPartyUnitMap()
    ns._UpdateAllPartyButtons()

    -- Re-register private aura anchors
    for unit, btn in pairs(ns._partyUnitToButton) do
        RegisterPrivateAuras(btn, unit)
    end
end

local function RegisterWithUnlockMode()
    if not (EllesmereUI and EllesmereUI.RegisterUnlockElements) then return end
    if not containerFrame then return end

    -- Snap saved positions to the physical pixel grid using each container's
    -- own effective scale. Uses the REAL PP (EllesmereUI.PP) -- the file-local
    -- PP is PanelPP, which has no .Snap, so the old `PP.Snap or floor` fell
    -- through to plain integer rounding (whole coordinate units, not physical
    -- pixels). This matches the SnapForES pattern every other unlock element
    -- uses (and RF's own PixelSnap), so the container stays crisp after save.
    local realPP = EllesmereUI and EllesmereUI.PP
    local function snap(frame, v)
        if realPP and realPP.SnapForES and frame then
            return realPP.SnapForES(v, frame:GetEffectiveScale())
        end
        return floor(v + 0.5)
    end

    EllesmereUI:RegisterUnlockElements({
        EllesmereUI.MakeUnlockElement({
            key   = "RF_RaidFrames",
            label = "Raid Frames",
            group = "Raid Frames",
            order = 500,
            noAnchorChildren = true,
            noAnchorTo = true,
            noAnchorTarget = true,
            noResize = true,

            getFrame = function() return containerFrame end,
            getSize  = function()
                return containerFrame:GetWidth(), containerFrame:GetHeight()
            end,

            savePos = function(_, point, relPoint, x, y)
                db.profile.unlockPos = { point = point, relPoint = relPoint, x = snap(containerFrame, x), y = snap(containerFrame, y) }
            end,
            loadPos = function()
                return db.profile.unlockPos
            end,
            clearPos = function()
                db.profile.unlockPos = nil
            end,
            applyPos = function()
                local pos = db.profile.unlockPos
                if pos and containerFrame then
                    containerFrame:ClearAllPoints()
                    containerFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
                end
            end,
        }),
        EllesmereUI.MakeUnlockElement({
            key   = "RF_PartyFrames",
            label = "Party Frames",
            group = "Raid Frames",
            order = 501,
            noAnchorChildren = true,
            noAnchorTo = true,
            noAnchorTarget = true,
            noResize = true,

            getFrame = function() return ns._partyContainerFrame end,
            getSize  = function()
                return ns._partyContainerFrame:GetWidth(), ns._partyContainerFrame:GetHeight()
            end,

            savePos = function(_, point, relPoint, x, y)
                db.profile.partyUnlockPos = { point = point, relPoint = relPoint, x = snap(ns._partyContainerFrame, x), y = snap(ns._partyContainerFrame, y) }
            end,
            loadPos = function()
                return db.profile.partyUnlockPos
            end,
            clearPos = function()
                db.profile.partyUnlockPos = nil
            end,
            applyPos = function()
                local pos = db.profile.partyUnlockPos
                if pos and ns._partyContainerFrame then
                    ns._partyContainerFrame:ClearAllPoints()
                    ns._partyContainerFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
                end
            end,
        }),
    })
end

-------------------------------------------------------------------------------
--  Options preview (fake raid members when options panel is open)
--  Shows 20 buttons with randomized class colors and names so the user
--  can see their settings applied without needing a real group.
-------------------------------------------------------------------------------
local previewActive = false
ns._PV_CLASS_TOKENS = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK",
    "DRUID", "DEMONHUNTER", "EVOKER",
}
ns._PV_TANK_CLASSES   = { "WARRIOR", "PALADIN", "DEATHKNIGHT", "MONK", "DRUID", "DEMONHUNTER" }
ns._PV_HEALER_CLASSES = { "PRIEST", "PALADIN", "SHAMAN", "MONK", "DRUID", "EVOKER" }
ns._PV_DPS_CLASSES    = ns._PV_CLASS_TOKENS
ns._PV_EXT_ICONS = {
    572025, 135936, 237542, 627485, 135964, 135966, 4622478,
}
ns._PV_DEF_ICONS = {
    DEATHKNIGHT = { 237525, 136120 }, DEMONHUNTER = { 1305150, 463284 },
    DRUID = { 136097, 236169 }, EVOKER = { 1394891 },
    HUNTER = { 132199, 136094 }, MAGE = { 135841, 609811 },
    MONK = { 615341, 620827 }, PALADIN = { 524353, 524354 },
    PRIEST = { 237550, 237563 }, ROGUE = { 136177, 132294 },
    SHAMAN = { 538565 }, WARLOCK = { 136146, 136150 }, WARRIOR = { 132336, 132361 },
}
ns._PV_NAMES = {
    "Thaldrin", "Kaelara", "Morgath", "Sylvaris", "Drakmoor",
    "Elyndra", "Bronthar", "Velisara", "Grimjaw", "Luneth",
    "Ashvane", "Tormund", "Ravynne", "Zulkhar", "Brightwing",
    "Fenwick", "Dawnforge", "Nighthollow", "Stormhelm", "Embertide",
}
ns._PV_DISPEL_DB_ICONS = {
    Magic = 135735, Curse = 132291, Disease = 237535, Poison = 132106, [""] = 4547635,
}
ns._PV_CLASS_POWER = {
    WARRIOR = "RAGE", PALADIN = "MANA", HUNTER = "FOCUS", ROGUE = "ENERGY",
    PRIEST = "MANA", DEATHKNIGHT = "RUNIC_POWER", SHAMAN = "MANA", MAGE = "MANA",
    WARLOCK = "MANA", MONK = "ENERGY", DRUID = "MANA", DEMONHUNTER = "FURY", EVOKER = "MANA",
}
ns._PV_DEBUFF_ICONS = { 135813, 136139, 132090, 136197, 135849, 136188 }
ns._pvActiveAuras = {}

-- Forward declarations for preview aura cycling (actual tables defined later)
local previewFrames
local previewClassTokens

-------------------------------------------------------------------------------
--  Preview aura cycling system
--  Manages fake debuffs/defensives on preview frames with real durations.
--  Maintains at least 1 per group for each enabled category.
-------------------------------------------------------------------------------
local pvAuraTicker = nil

-- Active-preview resolvers: the shared aura/animation tickers serve BOTH the
-- raid preview (previewFrames / previewActive) and the party preview
-- (ns._partyPvFrames / ns._partyPvActive). Keying off ns._partyPvActive at call
-- time lets one code path drive whichever preview is currently on screen.
local function PvFrames()
    return (ns._partyPvActive and ns._partyPvFrames) or previewFrames
end
local function PvActive()
    return previewActive or ns._partyPvActive
end
-- Party preview reads party-scaled / party-prefixed settings so aura icons match
-- the party frames (size, position, colors); raid preview reads the live profile.
local function PvSettings()
    return (ns._partyPvActive and ns._scaledPartyProxy) or db.profile
end
-- Class tokens for icon selection: the async ticker runs outside the synchronous
-- table swap in ApplyPartyPreviewData, so it must resolve party tokens itself.
local function PvClassTokens()
    return (ns._partyPvActive and ns._partyPvCT) or previewClassTokens
end

local function PvAuraGetGroup(index)
    return math.ceil(index / 5)
end

-- Pick a random icon for the given type and frame index
ns._PV_PA_ICONS = { 136090, 135894, 237274, 132301, 136116 }

local function PvAuraPickIcon(auraType, frameIndex)
    if auraType == "def" then
        local s2 = PvSettings()
        local showDef = s2 and s2.showDefensives
        local showExt = s2 and s2.showExternals
        local pool = {}
        local ct = PvClassTokens()[frameIndex] or "WARRIOR"
        if showDef then
            local ci = ns._PV_DEF_ICONS[ct]
            if ci then for _, ic in ipairs(ci) do pool[#pool + 1] = ic end end
        end
        if showExt then
            for _, ic in ipairs(ns._PV_EXT_ICONS) do pool[#pool + 1] = ic end
        end
        if #pool == 0 then return nil end
        return pool[math.random(#pool)]
    elseif auraType == "pa" then
        return ns._PV_PA_ICONS[math.random(#ns._PV_PA_ICONS)]
    else
        return ns._PV_DEBUFF_ICONS[math.random(#ns._PV_DEBUFF_ICONS)]
    end
end

-- Position a preview aura icon on a frame (reuses anchor logic)
local function PvAuraAnchor(icon, f, auraType, slot, totalShown)
    local s2 = PvSettings()
    local pos, ox, oy, grow, sz, spc
    if auraType == "def" then
        pos = s2.defPosition or "center"
        ox = s2.defOffsetX or 0
        oy = s2.defOffsetY or 0
        grow = s2.defGrowDirection or "CENTER"
        sz = s2.defSize or 22
        spc = PixelSnap(s2.defSpacing or 1)
    elseif auraType == "pa" then
        pos = s2.paPosition or "bottomleft"
        ox = s2.paOffsetX or 0
        oy = s2.paOffsetY or 0
        grow = s2.paGrowDirection or "RIGHT"
        sz = s2.paSize or 18
        spc = PixelSnap(s2.paSpacing or 1)
    else
        pos = s2.debuffPosition or "bottomleft"
        ox = s2.debuffOffsetX or 0
        oy = s2.debuffOffsetY or 0
        grow = s2.debuffGrowDirection or "RIGHT"
        sz = s2.debuffSize or 18
        spc = PixelSnap(s2.debuffSpacing or 1)
    end
    local spacing = sz + spc
    local centerOff = 0
    if grow == "CENTER" and totalShown > 0 then
        centerOff = -((totalShown - 1) * spacing) / 2
    end
    icon:SetSize(sz, sz)
    icon:ClearAllPoints()
    if slot == 0 then
        local fx = ox + (grow == "CENTER" and centerOff or 0)
        -- All aura icon previews (debuffs, defensives, private auras) anchor flush
        -- to the health bar edge -- no 1px inset -- matching the real frames.
        if pos == "topleft" then icon:SetPoint("TOPLEFT", f._health, "TOPLEFT", fx, oy)
        elseif pos == "top" then icon:SetPoint("TOP", f._health, "TOP", fx, oy)
        elseif pos == "topright" then icon:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", fx, oy)
        elseif pos == "left" then icon:SetPoint("LEFT", f._health, "LEFT", fx, oy)
        elseif pos == "center" then icon:SetPoint("CENTER", f._health, "CENTER", fx, oy)
        elseif pos == "right" then icon:SetPoint("RIGHT", f._health, "RIGHT", fx, oy)
        elseif pos == "bottomright" then icon:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", fx, oy)
        elseif pos == "bottom" then icon:SetPoint("BOTTOM", f._health, "BOTTOM", fx, oy)
        else icon:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", fx, oy)
        end
    else
        -- Chain from previous icon in same pool
        local pool = auraType == "def" and f._pvDefs
            or auraType == "pa" and f._pvPA
            or f._pvDebuffs
        local prev = pool[slot] -- slot is 1-based, current is slot+1
        if prev and prev:IsShown() then
            if grow == "RIGHT" or grow == "CENTER" then
                icon:SetPoint("LEFT", prev, "RIGHT", spc, 0)
            elseif grow == "LEFT" then
                icon:SetPoint("RIGHT", prev, "LEFT", -spc, 0)
            elseif grow == "UP" then
                icon:SetPoint("BOTTOM", prev, "TOP", 0, spc)
            elseif grow == "DOWN" then
                icon:SetPoint("TOP", prev, "BOTTOM", 0, -spc)
            end
        end
    end
end

-- Apply a fake aura to a preview frame slot
local function PvAuraApply(frameIndex, auraType, slotIndex)
    local f = PvFrames()[frameIndex]
    if not f or not f._health then return end
    local pool = auraType == "def" and f._pvDefs
        or auraType == "pa" and f._pvPA
        or f._pvDebuffs
    local icon = pool and pool[slotIndex]
    if not icon then return end

    local tex = PvAuraPickIcon(auraType, frameIndex)
    if not tex then icon:Hide(); return end

    local s2 = PvSettings()
    local dur = 8 + math.random() * 4  -- 8-12 seconds
    local startTime = GetTime()

    icon._tex:SetTexture(tex)
    if icon._cooldown then
        local showSwipe, showDurText, dtColor, dtSize, dtOX, dtOY
        if auraType == "pa" then
            -- Private auras: swipe always on, text controlled by paShowCountdown
            showSwipe = true
            showDurText = s2.paShowCountdown ~= false
            dtColor = { r = 1, g = 1, b = 1 }
            dtSize = 8
            dtOX = 0
            dtOY = 0
        elseif auraType == "db" then
            showSwipe = s2.debuffShowSwipe ~= false
            showDurText = s2.debuffShowDurText
            dtColor = s2.debuffDurTextColor or { r = 1, g = 1, b = 1 }
            dtSize = s2.debuffDurTextSize or 8
            dtOX = s2.debuffDurTextOffsetX or 0
            dtOY = s2.debuffDurTextOffsetY or 0
        else
            showSwipe = s2.defShowSwipe ~= false
            showDurText = s2.defShowDurText
            dtColor = s2.defDurTextColor or { r = 1, g = 1, b = 1 }
            dtSize = s2.defDurTextSize or 8
            dtOX = s2.defDurTextOffsetX or 0
            dtOY = s2.defDurTextOffsetY or 0
        end
        icon._cooldown:SetCooldown(startTime, dur)
        icon._cooldown:SetDrawSwipe(showSwipe)
        icon._cooldown:SetHideCountdownNumbers(not showDurText)
        icon._cooldown:Show()

        -- Style the built-in countdown text via GetCountdownFontString
        if showDurText and dtColor then
            local cdText = icon._cooldown.GetCountdownFontString and icon._cooldown:GetCountdownFontString()
            if cdText then
                local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
                cdText:SetFont(fontPath, dtSize, "OUTLINE")
                cdText:SetTextColor(dtColor.r, dtColor.g, dtColor.b)
                cdText:ClearAllPoints()
                cdText:SetPoint("CENTER", icon, "CENTER", dtOX, dtOY)
            end
        end
    end

    -- Border
    local bdrSz, bdrC
    if auraType == "pa" then
        -- Private auras: real frames use Blizzard's native border scaled 1:1 to
        -- the icon. The preview can't use Blizzard rendering, so approximate it
        -- with a fixed 1px EUI border (no longer user-configurable).
        bdrSz = 1
        bdrC = { r = 0, g = 0, b = 0 }
    elseif auraType == "def" then
        bdrSz = s2.defBorderSize or 1
        bdrC = s2.defBorderColor or { r = 0, g = 0, b = 0 }
    else
        bdrSz = s2.debuffBorderSize or 1
        bdrC = s2.debuffBorderColor or { r = 0, g = 0, b = 0 }
    end
    if icon._borderFrame and PP and bdrSz > 0 then
        PP.UpdateBorder(icon._borderFrame, bdrSz, bdrC.r, bdrC.g, bdrC.b, 1)
        icon._borderFrame:Show()
    elseif icon._borderFrame then
        icon._borderFrame:Hide()
    end

    -- Stacks text (debuffs only: show "2" on exactly one random debuff)
    if icon._count then
        icon._count:SetText("")
    end

    icon:Show()

    -- Track expiration
    local key = frameIndex .. ":" .. auraType .. ":" .. slotIndex
    ns._pvActiveAuras[key] = { frameIndex = frameIndex, auraType = auraType,
        slot = slotIndex, expTime = startTime + dur }
end

-- Count active auras of a type in a group (optionally skip slots below minSlot)
local function PvAuraCountInGroup(group, auraType, minSlot)
    minSlot = minSlot or 1
    local count = 0
    for _, info in pairs(ns._pvActiveAuras) do
        if info.auraType == auraType and info.slot >= minSlot
            and PvAuraGetGroup(info.frameIndex) == group
            and info.expTime > GetTime() then
            count = count + 1
        end
    end
    return count
end

-- Pick a random frame in a group that doesn't have a random aura of this type
-- (ignores permanent slot 1 debuffs so random debuffs can still be assigned)
local function PvAuraPickFrame(group, auraType, minSlot)
    minSlot = minSlot or 1
    local candidates = {}
    local pf = PvFrames()
    local startIdx = (group - 1) * 5 + 1
    local endIdx = group * 5
    for i = startIdx, endIdx do
        if i <= #pf and pf[i] then
            local hasType = false
            for _, info in pairs(ns._pvActiveAuras) do
                if info.frameIndex == i and info.auraType == auraType
                    and info.slot >= minSlot and info.expTime > GetTime() then
                    hasType = true; break
                end
            end
            if not hasType then candidates[#candidates + 1] = i end
        end
    end
    if #candidates == 0 then return nil end
    return candidates[math.random(#candidates)]
end

-- Re-anchor all visible icons on a frame for CENTER growth
local function PvAuraReanchorFrame(frameIndex, auraType)
    local f = PvFrames()[frameIndex]
    if not f then return end
    local pool = auraType == "def" and f._pvDefs
        or auraType == "pa" and f._pvPA
        or f._pvDebuffs
    if not pool then return end
    local shown = 0
    for _, ic in ipairs(pool) do
        if ic:IsShown() then shown = shown + 1 end
    end
    local slotIdx = 0
    for _, ic in ipairs(pool) do
        if ic:IsShown() then
            PvAuraAnchor(ic, f, auraType, slotIdx, shown)
            slotIdx = slotIdx + 1
        end
    end
end

local function PvAuraTick()
    if not PvActive() then return end
    local now = GetTime()
    local s2 = PvSettings()
    local wantDef = ns._defensivesPreviewVisible and (s2.showDefensives or s2.showExternals)
    local wantDb = ns._debuffsPreviewVisible and s2.debuffFilter ~= "none"

    -- Expire finished auras. In Real/Overlay preview the random per-player auras
    -- (defensives, private auras, and random debuffs in slot 2+) loop on the SAME
    -- frame with a fresh duration instead of being removed -- otherwise the
    -- per-group top-up below re-picks a new random player every cycle, so icons
    -- appear to "jump" between players. Full Preview (test mode) keeps rotating.
    -- The raid-wide pulse debuff (db slot 1) is never looped here; it hits every
    -- frame at once on its own pulse cycle.
    local loopSame = not ns._testMode
    for key, info in pairs(ns._pvActiveAuras) do
        if key ~= "_stackKey" and key ~= "raidwide:db" and info.expTime and info.expTime <= now then
            local isRandom = info.auraType == "def" or info.auraType == "pa"
                or (info.auraType == "db" and info.slot >= 2)
            if loopSame and isRandom then
                -- Re-spawn on the same frame/slot (overwrites this same key, so the
                -- group count stays put and no new player is chosen). If it held the
                -- stacks marker, drop it so the stacks pass re-applies the count text.
                if ns._pvActiveAuras._stackKey == key then ns._pvActiveAuras._stackKey = nil end
                PvAuraApply(info.frameIndex, info.auraType, info.slot)
                PvAuraReanchorFrame(info.frameIndex, info.auraType)
            else
                local f = PvFrames()[info.frameIndex]
                if f then
                    local pool = info.auraType == "def" and f._pvDefs
                        or info.auraType == "pa" and f._pvPA
                        or f._pvDebuffs
                    local ic = pool and pool[info.slot]
                    if ic then
                        ic:Hide()
                        if ic._cooldown then ic._cooldown:Clear() end
                        if ic._count then ic._count:SetText("") end
                    end
                end
                if ns._pvActiveAuras._stackKey == key then ns._pvActiveAuras._stackKey = nil end
                ns._pvActiveAuras[key] = nil
            end
        end
    end

    -- Raid-wide debuff pulse: 10s debuff on ALL frames, cycling every 25s
    if wantDb then
        -- Check if the raid-wide pulse is active or needs to start/restart
        local pulseKey = "raidwide:db"
        local pulseInfo = ns._pvActiveAuras[pulseKey]
        if not pulseInfo then
            -- First tick or after expiry gap: schedule next pulse
            ns._pvActiveAuras[pulseKey] = { nextPulse = now, active = false }
            pulseInfo = ns._pvActiveAuras[pulseKey]
        end
        if pulseInfo.active and pulseInfo.expTime and pulseInfo.expTime <= now then
            -- Pulse expired: hide slot 1 on all frames
            local pf = PvFrames()
            for fi = 1, #pf do
                local f = pf[fi]
                if f and f._pvDebuffs and f._pvDebuffs[1] then
                    f._pvDebuffs[1]:Hide()
                    if f._pvDebuffs[1]._cooldown then f._pvDebuffs[1]._cooldown:Clear() end
                    -- Re-pack remaining debuffs so a surviving slot-2+ icon shifts
                    -- into the vacated first position immediately, instead of only
                    -- when that icon itself refreshes.
                    PvAuraReanchorFrame(fi, "db")
                end
                ns._pvActiveAuras[fi .. ":db:1"] = nil
            end
            pulseInfo.active = false
            pulseInfo.nextPulse = now + 15  -- 15s gap before next pulse
        end
        if not pulseInfo.active and now >= (pulseInfo.nextPulse or 0) then
            -- Apply 10s debuff to all frames
            local dur = 10
            local pf = PvFrames()
            for fi = 1, #pf do
                local key = fi .. ":db:1"
                local f = pf[fi]
                if f and f._pvDebuffs and f._pvDebuffs[1] and f._health then
                    local icon = f._pvDebuffs[1]
                    icon._tex:SetTexture(5927657)
                    icon:SetSize(s2.debuffSize or 18, s2.debuffSize or 18)
                    if icon._cooldown then
                        icon._cooldown:SetCooldown(now, dur)
                        icon._cooldown:SetDrawSwipe(s2.debuffShowSwipe ~= false)
                        icon._cooldown:SetHideCountdownNumbers(not s2.debuffShowDurText)
                        icon._cooldown:Show()
                        if s2.debuffShowDurText then
                            local cdText = icon._cooldown.GetCountdownFontString and icon._cooldown:GetCountdownFontString()
                            if cdText then
                                local dtc = s2.debuffDurTextColor or { r = 1, g = 1, b = 1 }
                                local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
                                cdText:SetFont(fp, s2.debuffDurTextSize or 8, "OUTLINE")
                                cdText:SetTextColor(dtc.r, dtc.g, dtc.b)
                                cdText:ClearAllPoints()
                                cdText:SetPoint("CENTER", icon, "CENTER",
                                    s2.debuffDurTextOffsetX or 0, s2.debuffDurTextOffsetY or 0)
                            end
                        end
                    end
                    local bdrSz = s2.debuffBorderSize or 1
                    local bdrC = s2.debuffBorderColor or { r = 0, g = 0, b = 0 }
                    if icon._borderFrame and PP and bdrSz > 0 then
                        PP.UpdateBorder(icon._borderFrame, bdrSz, bdrC.r, bdrC.g, bdrC.b, 1)
                        icon._borderFrame:Show()
                    elseif icon._borderFrame then
                        icon._borderFrame:Hide()
                    end
                    icon:Show()
                    -- Re-pack all shown debuffs so slot 1 takes the first position
                    -- and any random slot-2+ debuff shifts right, rather than the
                    -- two overlapping when the pulse returns.
                    PvAuraReanchorFrame(fi, "db")
                    ns._pvActiveAuras[key] = { frameIndex = fi, auraType = "db",
                        slot = 1, expTime = now + dur }
                end
            end
            pulseInfo.active = true
            pulseInfo.expTime = now + dur
        end
    end

    -- Ensure minimum random auras per group for each enabled category.
    -- Party is a single group of 5, so it gets a higher per-group defensive
    -- count (3) to read as a populated showcase; raid keeps 1 per group.
    local defTarget = ns._partyPvActive and 3 or 1
    for group = 1, 4 do
        while wantDef and PvAuraCountInGroup(group, "def") < defTarget do
            local fi = PvAuraPickFrame(group, "def")
            if not fi then break end
            PvAuraApply(fi, "def", 1); PvAuraReanchorFrame(fi, "def")
        end
        -- Random debuffs use slot 2+
        if wantDb and PvAuraCountInGroup(group, "db", 2) < 1 then
            local fi = PvAuraPickFrame(group, "db", 2)
            if fi then PvAuraApply(fi, "db", 2); PvAuraReanchorFrame(fi, "db") end
        end
    end

    -- Assign stacks "2" to exactly one active debuff (slot 2+).
    -- Stays on the same icon until it expires, then the next new one gets it.
    if wantDb and s2.debuffShowStacks then
        -- Check if current stacks target is still alive
        local stackKey = ns._pvActiveAuras._stackKey
        local stackAlive = stackKey and ns._pvActiveAuras[stackKey] and ns._pvActiveAuras[stackKey].expTime > now
        if not stackAlive then
            -- Clear old stacks text
            if stackKey then
                local oldInfo = ns._pvActiveAuras[stackKey]
                -- oldInfo may have been wiped already
            end
            ns._pvActiveAuras._stackKey = nil
        end
        -- If no current target, assign to the next new debuff that appears
        -- (handled in PvAuraApply via _pvNeedStacks flag)
        if not ns._pvActiveAuras._stackKey then
            -- Find any active slot 2+ debuff to assign stacks to
            for key, info in pairs(ns._pvActiveAuras) do
                if key ~= "_stackKey" and info.auraType == "db" and info.slot >= 2 and info.expTime > now then
                    ns._pvActiveAuras._stackKey = key
                    local f = PvFrames()[info.frameIndex]
                    local ic = f and f._pvDebuffs and f._pvDebuffs[info.slot]
                    if ic and ic._count then
                        local stc = s2.debuffStacksTextColor or { r = 1, g = 1, b = 1 }
                        local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
                        ic._count:SetFont(fp, s2.debuffStacksTextSize or 8, "OUTLINE")
                        ic._count:SetTextColor(stc.r, stc.g, stc.b)
                        ic._count:ClearAllPoints()
                        ic._count:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT",
                            1 + (s2.debuffStacksOffsetX or 0), -1 + (s2.debuffStacksOffsetY or 0))
                        ic._count:SetText("2")
                    end
                    break
                end
            end
        end
    end

    -- Private aura preview: cycling icons like defensives/debuffs.
    -- Party (single group of 5) gets 2 guaranteed + a 50% 3rd; raid keeps
    -- 1 guaranteed + a 50% 2nd per group.
    local wantPA = ns._privateAurasPreviewVisible
    if wantPA then
        local paBase = ns._partyPvActive and 2 or 1
        local paMax  = ns._partyPvActive and 3 or 2
        -- Ensure the guaranteed PA icons (1 per frame, spread across the group)
        for group = 1, 4 do
            while PvAuraCountInGroup(group, "pa") < paBase do
                local fi = PvAuraPickFrame(group, "pa")
                if not fi then break end
                PvAuraApply(fi, "pa", 1); PvAuraReanchorFrame(fi, "pa")
            end
        end
        -- Add one more icon on a random frame per group (50% chance)
        for group = 1, 4 do
            if PvAuraCountInGroup(group, "pa") < paMax and math.random() > 0.5 then
                local fi = PvAuraPickFrame(group, "pa")
                if fi then PvAuraApply(fi, "pa", 2); PvAuraReanchorFrame(fi, "pa") end
            end
        end
    end
end

local function StartPvAuraTicker()
    if not pvAuraTicker then
        -- Seed initial auras
        PvAuraTick()
        pvAuraTicker = C_Timer.NewTicker(0.5, PvAuraTick)
    end
end

local function StopPvAuraTicker()
    if pvAuraTicker then
        pvAuraTicker:Cancel()
        pvAuraTicker = nil
    end
    wipe(ns._pvActiveAuras)
    -- Hide all preview aura icons, reset cooldowns, unregister dur texts
    for _, f in ipairs(PvFrames()) do
        if f._pvDebuffs then
            for _, ic in ipairs(f._pvDebuffs) do
                ic:Hide()
                if ic._cooldown then ic._cooldown:Clear() end
            end
        end
        if f._pvDefs then
            for _, ic in ipairs(f._pvDefs) do
                ic:Hide()
                if ic._cooldown then ic._cooldown:Clear() end
            end
        end
        if f._pvPA then
            for _, ic in ipairs(f._pvPA) do
                ic:Hide()
                if ic._cooldown then ic._cooldown:Clear() end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Preview Buff Ticker (test mode only: cycles configured buffs across frames)
-------------------------------------------------------------------------------
ns._pvBuffTicker = nil
ns._pvBuffAssignments = {}

local function GetConfiguredBuffSpells()
    if not db or not db.profile or not db.profile.bmIndicators then return {} end
    -- BM indicators are keyed by "CLASS_SPEC" strings (e.g. "PALADIN_HOLY").
    -- Resolve the player's spec via the shared, locale-independent helper (matches
    -- by spec ID, not the localized spec name) so indicators show on every client.
    local specKey = ns.BM_CurrentSpecKey and ns.BM_CurrentSpecKey()
    if not specKey then return {} end
    local indicators = db.profile.bmIndicators[specKey]
    if not indicators then return {} end
    local spells = {}
    local seen = {}
    for _, ind in ipairs(indicators) do
        if ind.enabled and ind.spells and (ind.type == "icon" or ind.type == "square") then
            for _, sid in ipairs(ind.spells) do
                if not seen[sid] then
                    seen[sid] = true
                    local iconTex
                    if ind.type == "icon" then
                        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                        iconTex = info and info.iconID or 136243
                    end
                    local baseSz = ind.size or 18
                    local soff = ind.sizeOffsets and ind.sizeOffsets[sid] or 0
                    local spellSz = baseSz + soff
                    if spellSz < 1 then spellSz = 1 end
                    spells[#spells + 1] = {
                        id = sid, icon = iconTex,
                        indType = ind.type,
                        color = ind.color,
                        size = spellSz,
                        position = ind.position or "TOPLEFT",
                        offsetX = ind.offsetX or 0,
                        offsetY = ind.offsetY or 0,
                        growDirection = ind.growDirection or "RIGHT",
                        spacing = ind.spacing or 0,
                        borderSize = ind.indBorderSize or 1,
                        borderColor = ind.indBorderColor or { r = 0, g = 0, b = 0 },
                        permanent = ns.BM_PREVIEW_NO_DURATION and ns.BM_PREVIEW_NO_DURATION[sid],
                    }
                end
            end
        end
    end
    return spells
end

ns.PvBuffAnchor = function(icon, f, spellInfo, prevIcon)
    if not f._health then return end
    icon:SetSize(spellInfo.size, spellInfo.size)
    icon:ClearAllPoints()
    if prevIcon then
        -- Chain from previous icon using growth direction
        local spc = PixelSnap(spellInfo.spacing or 0)
        local grow = spellInfo.growDirection or "RIGHT"
        if grow == "RIGHT" then icon:SetPoint("LEFT", prevIcon, "RIGHT", spc, 0)
        elseif grow == "LEFT" then icon:SetPoint("RIGHT", prevIcon, "LEFT", -spc, 0)
        elseif grow == "UP" then icon:SetPoint("BOTTOM", prevIcon, "TOP", 0, spc)
        elseif grow == "DOWN" then icon:SetPoint("TOP", prevIcon, "BOTTOM", 0, -spc)
        end
    else
        local pos = spellInfo.position and spellInfo.position:upper() or "BOTTOMLEFT"
        local ox, oy = spellInfo.offsetX or 0, spellInfo.offsetY or 0
        icon:SetPoint(pos, f._health, pos, ox, oy)
    end
end

ns.PvBuffApply = function(spellInfo, frameIndex, slot)
    local f = previewFrames[frameIndex]
    if not f or not f._pvBuffs then return end
    local icon = f._pvBuffs[slot]
    if not icon then return end

    if spellInfo.indType == "icon" then
        icon._tex:SetTexture(spellInfo.icon or 136243)
        icon._tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon._tex:SetVertexColor(1, 1, 1)
    else
        local c = spellInfo.color or { r = 0.05, g = 0.82, b = 0.62 }
        icon._tex:SetColorTexture(c.r, c.g, c.b, 1)
        icon._tex:SetTexCoord(0, 1, 0, 1)
    end

    ns.PvBuffAnchor(icon, f, spellInfo)

    -- Border
    if icon._borderFrame and PP and spellInfo.borderSize > 0 then
        PP.UpdateBorder(icon._borderFrame, spellInfo.borderSize,
            spellInfo.borderColor.r, spellInfo.borderColor.g, spellInfo.borderColor.b, 1)
        icon._borderFrame:Show()
    elseif icon._borderFrame then
        icon._borderFrame:Hide()
    end

    -- Cooldown
    if icon._cooldown then
        if not spellInfo.permanent then
            local dur = 15
            local startTime = GetTime() - math.random() * 10
            icon._cooldown:SetCooldown(startTime, dur)
            icon._cooldown:SetDrawSwipe(true)
            icon._cooldown:SetHideCountdownNumbers(true)
            icon._cooldown:Show()
        else
            icon._cooldown:Hide()
        end
    end

    icon:Show()
end

ns.PvBuffTick = function()
    if not previewActive or not ns._testBuffsVisible then return end
    local now = GetTime()
    local PREVIEW_COUNT2 = #previewFrames

    -- Loop cooldown swipes on player frame buffs (permanent, but swipe should cycle)
    local playerF = previewFrames[1]
    if playerF and playerF._pvBuffs then
        for _, info in pairs(ns._pvBuffAssignments) do
            if info.permanent and info.frameIndex == 1 and not info.spellInfo.permanent then
                if not info.cdEndTime or now >= info.cdEndTime then
                    local ic = playerF._pvBuffs[info.slot]
                    if ic and ic._cooldown then
                        local dur = 12 + math.random() * 8  -- 12-20s
                        ic._cooldown:SetCooldown(now, dur)
                        info.cdEndTime = now + dur
                    end
                end
            end
        end
    end

    -- Expire and reassign
    for sid, info in pairs(ns._pvBuffAssignments) do
        if not info.permanent and info.expTime and info.expTime <= now then
            -- Hide old
            local f = previewFrames[info.frameIndex]
            if f and f._pvBuffs and f._pvBuffs[info.slot] then
                local ic = f._pvBuffs[info.slot]
                ic:Hide()
                if ic._cooldown then ic._cooldown:SetCooldown(0, 0) end
            end
            -- Pick new frame (skip frame 1 = player)
            local newFi = math.random(2, PREVIEW_COUNT2)
            local tries = 0
            while newFi == info.frameIndex and tries < 5 do
                newFi = math.random(2, PREVIEW_COUNT2); tries = tries + 1
            end
            info.frameIndex = newFi
            info.expTime = now + 15
            ns.PvBuffApply(info.spellInfo, newFi, info.slot)
        end
    end
end

ns.StartPvBuffTicker = function()
    if ns._pvBuffTicker then return end
    wipe(ns._pvBuffAssignments)

    local spells = GetConfiguredBuffSpells()
    if #spells == 0 then return end

    local now = GetTime()
    local PREVIEW_COUNT2 = #previewFrames
    local playerSlot = 0

    -- Player frame (1): show all buffs, max 3 per position, chained
    local posCounts = {}   -- [position] = count
    local posLastIcon = {} -- [position] = last icon frame for chaining
    local playerF = previewFrames[1]
    if playerF and playerF._pvBuffs then
        for _, sp in ipairs(spells) do
            local pos = sp.position
            posCounts[pos] = (posCounts[pos] or 0) + 1
            if posCounts[pos] <= 3 then
                playerSlot = playerSlot + 1
                if playerSlot > 8 then break end
                local prev = posLastIcon[pos]
                ns.PvBuffApply(sp, 1, playerSlot)
                local icon = playerF._pvBuffs[playerSlot]
                if icon then
                    ns.PvBuffAnchor(icon, playerF, sp, prev)
                    posLastIcon[pos] = icon
                end
                ns._pvBuffAssignments[sp.id .. ":p"] = {
                    spellInfo = sp, frameIndex = 1, slot = playerSlot,
                    expTime = now + 99999, permanent = true,  -- always visible on player
                }
            end
        end
    end

    -- Other frames: spread spells across frames 2+, one each, cycling on expiry
    local frameSlotsUsed = {}
    for i, sp in ipairs(spells) do
        local fi = ((i - 1) % (PREVIEW_COUNT2 - 1)) + 2
        frameSlotsUsed[fi] = (frameSlotsUsed[fi] or 0) + 1
        local slot = frameSlotsUsed[fi]
        if slot > 4 then break end
        ns._pvBuffAssignments[sp.id] = {
            spellInfo = sp, frameIndex = fi, slot = slot,
            expTime = sp.permanent and (now + 99999) or (now + math.random(3, 15)),
            permanent = sp.permanent,
        }
        ns.PvBuffApply(sp, fi, slot)
    end

    ns._pvBuffTicker = C_Timer.NewTicker(0.5, ns.PvBuffTick)
end

ns.StopPvBuffTicker = function()
    if ns._pvBuffTicker then ns._pvBuffTicker:Cancel(); ns._pvBuffTicker = nil end
    wipe(ns._pvBuffAssignments)
    for _, f in ipairs(previewFrames) do
        if f._pvBuffs then
            for _, ic in ipairs(f._pvBuffs) do
                ic:Hide()
                if ic._cooldown then ic._cooldown:SetCooldown(0, 0) end
            end
        end
    end
end

-- Restart: stop (instant clear) then start if any eyeball is on
local function RestartPvAuraTicker()
    StopPvAuraTicker()
    if PvActive() and (ns._defensivesPreviewVisible or ns._debuffsPreviewVisible or ns._privateAurasPreviewVisible) then
        StartPvAuraTicker()
    end
end
ns.RestartPvAuraTicker = RestartPvAuraTicker

-- Re-anchor + resize + re-border all active preview aura icons (settings changed, no icon swap)
-- Reads shared state via ns to stay under the 60-upvalue cap.
ns._PvAuraReanchorFrame = PvAuraReanchorFrame
ns.RefreshPvAuraVisuals = function()
    local s2 = PvSettings()
    if not s2 then return end
    local _PP = EllesmereUI.PanelPP or EllesmereUI.PP
    local _pvFrames = PvFrames()
    local _reanchor = ns._PvAuraReanchorFrame
    local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"

    local dbBdrSz = s2.debuffBorderSize or 1
    local dbBdrC = s2.debuffBorderColor or { r = 0, g = 0, b = 0 }
    local dbShowSwipe = s2.debuffShowSwipe ~= false
    local dbShowDurText = s2.debuffShowDurText
    local dbDtC = s2.debuffDurTextColor or { r = 1, g = 1, b = 1 }
    local dbDtSz = s2.debuffDurTextSize or 8
    local dbDtOX = s2.debuffDurTextOffsetX or 0
    local dbDtOY = s2.debuffDurTextOffsetY or 0
    local defBdrSz = s2.defBorderSize or 1
    local defBdrC = s2.defBorderColor or { r = 0, g = 0, b = 0 }
    local defShowSwipe = s2.defShowSwipe ~= false
    local defShowDurText = s2.defShowDurText
    local defDtC = s2.defDurTextColor or { r = 1, g = 1, b = 1 }
    local defDtSz = s2.defDurTextSize or 8
    local defDtOX = s2.defDurTextOffsetX or 0
    local defDtOY = s2.defDurTextOffsetY or 0
    local stc = s2.debuffStacksTextColor or { r = 1, g = 1, b = 1 }
    local sSz = s2.debuffStacksTextSize or 8
    local sOX = s2.debuffStacksOffsetX or 0
    local sOY = s2.debuffStacksOffsetY or 0

    for fi, f in ipairs(_pvFrames) do
        if f._pvDebuffs then
            for _, ic in ipairs(f._pvDebuffs) do
                if ic:IsShown() then
                    ic:SetSize(s2.debuffSize or 18, s2.debuffSize or 18)
                    if ic._borderFrame and _PP then
                        if dbBdrSz > 0 then
                            _PP.UpdateBorder(ic._borderFrame, dbBdrSz, dbBdrC.r, dbBdrC.g, dbBdrC.b, 1)
                            ic._borderFrame:Show()
                        else
                            ic._borderFrame:Hide()
                        end
                    end
                    if ic._cooldown then
                        ic._cooldown:SetDrawSwipe(dbShowSwipe)
                        ic._cooldown:SetHideCountdownNumbers(not dbShowDurText)
                        if dbShowDurText then
                            local cdText = ic._cooldown.GetCountdownFontString and ic._cooldown:GetCountdownFontString()
                            if cdText then
                                cdText:SetFont(fp, dbDtSz, "OUTLINE")
                                cdText:SetTextColor(dbDtC.r, dbDtC.g, dbDtC.b)
                                cdText:ClearAllPoints()
                                cdText:SetPoint("CENTER", ic, "CENTER", dbDtOX, dbDtOY)
                            end
                        end
                    end
                    if ic._count and ic._count:GetText() ~= "" then
                        ic._count:SetFont(fp, sSz, "OUTLINE")
                        ic._count:SetTextColor(stc.r, stc.g, stc.b)
                        ic._count:ClearAllPoints()
                        ic._count:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 1 + sOX, -1 + sOY)
                    end
                end
            end
            _reanchor(fi, "db")
        end
        if f._pvDefs then
            for _, ic in ipairs(f._pvDefs) do
                if ic:IsShown() then
                    ic:SetSize(s2.defSize or 22, s2.defSize or 22)
                    if ic._borderFrame and _PP then
                        if defBdrSz > 0 then
                            _PP.UpdateBorder(ic._borderFrame, defBdrSz, defBdrC.r, defBdrC.g, defBdrC.b, 1)
                            ic._borderFrame:Show()
                        else
                            ic._borderFrame:Hide()
                        end
                    end
                    if ic._cooldown then
                        ic._cooldown:SetDrawSwipe(defShowSwipe)
                        ic._cooldown:SetHideCountdownNumbers(not defShowDurText)
                        if defShowDurText then
                            local cdText = ic._cooldown.GetCountdownFontString and ic._cooldown:GetCountdownFontString()
                            if cdText then
                                cdText:SetFont(fp, defDtSz, "OUTLINE")
                                cdText:SetTextColor(defDtC.r, defDtC.g, defDtC.b)
                                cdText:ClearAllPoints()
                                cdText:SetPoint("CENTER", ic, "CENTER", defDtOX, defDtOY)
                            end
                        end
                    end
                end
            end
            _reanchor(fi, "def")
        end
        if f._pvPA then
            local paSz = s2.paSize or 20
            local paCD = s2.paShowCountdown ~= false
            for _, ic in ipairs(f._pvPA) do
                if ic:IsShown() then
                    ic:SetSize(paSz, paSz)
                    -- Fixed 1px border approximating Blizzard's 1:1 native border
                    -- (Border Size is no longer user-configurable).
                    if ic._borderFrame and _PP then
                        _PP.UpdateBorder(ic._borderFrame, 1, 0, 0, 0, 1)
                        ic._borderFrame:Show()
                    end
                    if ic._cooldown then
                        ic._cooldown:SetDrawSwipe(true)
                        ic._cooldown:SetHideCountdownNumbers(not paCD)
                    end
                end
            end
            _reanchor(fi, "pa")
        end
    end
end

-- Preview frames: standalone frames NOT managed by SecureGroupHeaderTemplate.
-- Header-managed buttons can't be shown without real units, so we create
-- our own lightweight frames that look identical for the options preview.
previewFrames = {}
local previewGroupLabels = {}  -- [1..4] FontStrings showing group numbers
local previewContainer = nil   -- standalone anchor frame for preview (doesn't move with containerFrame)
local previewHiddenParent = nil -- hidden frame to reparent containerFrame into during preview

local function CreatePreviewFrame(index)
    local s = db.profile
    local w = PixelSnap(s.frameWidth or 72)
    local h = PixelSnap(s.frameHeight or 46)
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(h - powerH)

    local f = CreateFrame("Frame", nil, previewContainer or containerFrame)
    f:SetSize(w, h)
    f:SetFrameStrata("LOW")
    f:Hide()

    -- Background
    local bgc = s.customBgColor
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
    if PP then PP.DisablePixelSnap(bg) end

    -- Health bar
    local health = CreateFrame("StatusBar", nil, f)
    health:SetFrameLevel(f:GetFrameLevel() + 2)
    health:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    health:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    health:SetHeight(healthH)
    health:SetStatusBarTexture(ResolveHealthTexture())
    health:GetStatusBarTexture():SetHorizTile(false)
    if PP then PP.DisablePixelSnap(health) end
    health:SetMinMaxValues(0, 100)
    health:SetValue(100)

    -- Absorb shield preview (dual clip-frame, matching real frames)
    -- Mask: constrains absorb rendering to health bar bounds
    local absorbMask = health:CreateMaskTexture()
    absorbMask:SetAllPoints(health)
    absorbMask:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Current HP clip: bounds the backfill bar to the filled health area
    local curClip = CreateFrame("Frame", nil, health)
    curClip:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    curClip:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    curClip:SetClipsChildren(true)

    -- Missing HP clip: bounds the forward bar to the empty health area
    local missClip = CreateFrame("Frame", nil, health)
    missClip:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", -1, 0)
    missClip:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    missClip:SetClipsChildren(true)

    -- Backfill bar: grows into filled health from the right (overshield)
    local backfillBar = CreateFrame("StatusBar", nil, curClip)
    backfillBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local bfFill = backfillBar:GetStatusBarTexture()
    if bfFill then bfFill:SetDrawLayer("ARTWORK", 1); bfFill:AddMaskTexture(absorbMask) end
    backfillBar:SetStatusBarColor(1, 1, 1, 0.3)
    backfillBar:SetReverseFill(true)
    backfillBar:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, 0)
    backfillBar:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    backfillBar:SetWidth(health:GetWidth())
    backfillBar:SetHeight(health:GetHeight())
    -- Absorb on top of the HP cluster (above heal absorb/heal pred and max health).
    backfillBar:SetFrameLevel(health:GetFrameLevel() + 3)
    backfillBar:SetMinMaxValues(0, 100)
    backfillBar:Hide()

    -- Forward bar: grows into missing health from the HP edge
    local forwardBar = CreateFrame("StatusBar", nil, missClip)
    forwardBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local fwFill = forwardBar:GetStatusBarTexture()
    if fwFill then fwFill:SetDrawLayer("ARTWORK", 1); fwFill:AddMaskTexture(absorbMask) end
    forwardBar:SetStatusBarColor(1, 1, 1, 0.3)
    forwardBar:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    forwardBar:SetPoint("BOTTOMLEFT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    forwardBar:SetWidth(health:GetWidth())
    forwardBar:SetHeight(health:GetHeight())
    -- Match backfill: absorb above heal absorb/heal pred and max health.
    forwardBar:SetFrameLevel(health:GetFrameLevel() + 3)
    forwardBar:SetMinMaxValues(0, 100)
    forwardBar:Hide()

    -- Heal absorb bar (preview): red overlay eating into filled health from HP edge
    do
        local ha = CreateFrame("StatusBar", nil, curClip)
        ha:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local hf = ha:GetStatusBarTexture()
        if hf then hf:SetDrawLayer("ARTWORK", 2); hf:AddMaskTexture(absorbMask) end
        ha:SetStatusBarColor(0.8, 0.15, 0.15, 0.65)
        ha:SetReverseFill(true)
        ha:SetPoint("TOPRIGHT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        ha:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        ha:SetWidth(health:GetWidth())
        ha:SetHeight(health:GetHeight())
        ha:SetFrameLevel(health:GetFrameLevel() + 1)
        ha:SetMinMaxValues(0, 100)
        ha._mask = absorbMask
        ha:Hide()
        f._healAbsorbBar = ha
    end

    -- Heal prediction bar (preview): extends from HP edge into missing health
    do
        local hp = CreateFrame("StatusBar", nil, missClip)
        hp:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local hf = hp:GetStatusBarTexture()
        if hf then hf:SetDrawLayer("ARTWORK", 2); hf:AddMaskTexture(absorbMask) end
        hp:SetStatusBarColor(0.3, 0.8, 0.3, 0.4)
        hp:SetReverseFill(false)
        hp:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        hp:SetPoint("BOTTOMLEFT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        hp:SetWidth(health:GetWidth())
        hp:SetHeight(health:GetHeight())
        hp:SetFrameLevel(health:GetFrameLevel() + 1)
        hp:SetMinMaxValues(0, 100)
        hp:Hide()
        f._healPredBar = hp
    end

    -- Reduced max health bar (preview): black bg + red striped overlay on right side
    do
        local rmh = CreateFrame("StatusBar", nil, health)
        rmh:SetStatusBarTexture("Interface\\AddOns\\EllesmereUIRaidFrames\\Media\\striped-maxhp.png")
        local rmhFill = rmh:GetStatusBarTexture()
        if rmhFill then
            rmhFill:SetDrawLayer("ARTWORK", 3)
            rmhFill:SetHorizTile(true); rmhFill:SetVertTile(true)
        end
        rmh:SetStatusBarColor(0.7, 0.1, 0.1, 1)
        rmh:SetReverseFill(true)
        rmh:SetAllPoints(health)
        rmh:SetFrameLevel(health:GetFrameLevel() + 2)
        rmh:SetMinMaxValues(0, 1)
        rmh:Hide()
        -- Black background behind the stripes
        local rmhBg = rmh:CreateTexture(nil, "ARTWORK", nil, 2)
        rmhBg:SetAllPoints(rmhFill)
        rmhBg:SetColorTexture(0, 0, 0, 1)
        f._reducedMaxHealthBar = rmh
    end

    -- Store absorb references on preview frame
    local absorbBar = backfillBar
    absorbBar._forward = forwardBar
    absorbBar._mask = absorbMask
    absorbBar._curClip = curClip
    absorbBar._missClip = missClip

    -- Power bar (anchored to frame bottom for pixel alignment)
    local power
    if powerH > 0 then
        power = CreateFrame("StatusBar", nil, f)
        power:SetFrameLevel(f:GetFrameLevel() + 3)
        power:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        power:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        power:SetHeight(powerH)
        power:SetStatusBarTexture(ResolveHealthTexture())
        power:GetStatusBarTexture():SetHorizTile(false)
        if PP then PP.DisablePixelSnap(power) end
        power:SetMinMaxValues(0, 100)
        power:SetValue(100)
        local pwBg = power:CreateTexture(nil, "BACKGROUND")
        pwBg:SetAllPoints()
        pwBg:SetColorTexture((s.powerBgColor or {}).r or 0, (s.powerBgColor or {}).g or 0, (s.powerBgColor or {}).b or 0, (s.powerBgDarkness or 70) / 100)
        if PP then PP.DisablePixelSnap(pwBg) end
        f._powerBg = pwBg

        -- Power border
        local pwBdr = CreateFrame("Frame", nil, f)
        pwBdr:SetAllPoints(power)
        pwBdr:SetFrameLevel(power:GetFrameLevel() + 1)
        if PP then PP.CreateBorder(pwBdr, 0, 0, 0, 1, 1) end
        f._powerBorder = pwBdr
    end

    -- Border (single border styled via ApplyBorderStyle in ApplyPreviewData,
    -- recolored by state -- mirrors the real frames)
    local bdrFrame = CreateFrame("Frame", nil, f)
    bdrFrame:SetAllPoints(f)
    bdrFrame:SetFrameLevel(f:GetFrameLevel() + 8)

    local function PvApplyBorderColor()
        if not PP then return end
        local s = ns._previewSettingsOverride or (ns._partyPvActive and ns._scaledPartyProxy) or ns._scaledProfile
        if (s.borderSize or 1) <= 0 then return end
        local r, g, b, a
        local raised = false
        if f._hovered and s.hoverBorderEnabled ~= false then
            local c = s.hoverBorderColor or { r = 1, g = 1, b = 1 }
            r, g, b, a = c.r, c.g, c.b, s.hoverBorderAlpha or 1
            raised = true
        elseif f._isTarget and s.targetBorderEnabled ~= false then
            local c = s.targetBorderColor or { r = 1, g = 1, b = 1 }
            r, g, b, a = c.r, c.g, c.b, s.targetBorderAlpha or 1
            raised = true
        else
            local c = s.borderColor or { r = 0, g = 0, b = 0 }
            r, g, b, a = c.r, c.g, c.b, s.borderAlpha or 1
        end
        -- Match real frames: raise the inset border above overlapping neighbors
        -- while highlighted (handles negative Frame Spacing in the preview too).
        -- Guard the level writes so a refresh only touches them on a real change.
        local pl = f:GetFrameLevel()
        local lvl = s.borderBehind and math.max(0, pl - 1) or (pl + (raised and ns.LVL_RAISE or 8))
        local container = PP.GetBorders(bdrFrame)
        if bdrFrame:GetFrameLevel() ~= lvl
           or (container and container:GetFrameLevel() ~= lvl + 1) then
            bdrFrame:SetFrameLevel(lvl)
            if container then container:SetFrameLevel(lvl + 1) end
        end
        EllesmereUI.SetBorderStyleColor(bdrFrame, r, g, b, a)
    end
    f._ApplyBorderColor = PvApplyBorderColor

    f:EnableMouse(true)
    f:SetScript("OnEnter", function() f._hovered = true; PvApplyBorderColor() end)
    f:SetScript("OnLeave", function() f._hovered = false; PvApplyBorderColor() end)

    -- Threat border (aggro indicator)
    local threatFrame = CreateFrame("Frame", nil, f)
    threatFrame:SetAllPoints(f)
    threatFrame:SetFrameLevel(f:GetFrameLevel() + 10)
    threatFrame:Hide()
    if PP then PP.CreateBorder(threatFrame, 1, 0, 0, 1, 2) end

    -- Click to toggle target in test mode (recolors the single border)
    f:SetScript("OnMouseDown", function(self)
        if not PvActive() then return end
        for _, pf in ipairs(PvFrames()) do
            if pf ~= self and pf._isTarget then
                pf._isTarget = false
                if pf._ApplyBorderColor then pf._ApplyBorderColor() end
            end
        end
        f._isTarget = true
        PvApplyBorderColor()
    end)

    -- Dispel border
    local dispelBdrFrame = CreateFrame("Frame", nil, f)
    dispelBdrFrame:SetAllPoints(health)
    dispelBdrFrame:SetFrameLevel(f:GetFrameLevel() + 10)
    dispelBdrFrame:Hide()
    if PP then PP.CreateBorder(dispelBdrFrame, 0.2, 0.6, 1, 1, 2) end

    -- Dispel overlay (texture on health bar at ARTWORK sublevel 3: above fill
    -- and above the BM health-color overlay (sublevel 2), below absorbs/text)
    local dispelOLTex = health:CreateTexture(nil, "ARTWORK", nil, 3)
    dispelOLTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    dispelOLTex:Hide()

    -- Dispel type icon
    local dispelIconFrame = CreateFrame("Frame", nil, f)
    dispelIconFrame:SetFrameLevel(f:GetFrameLevel() + ns.LVL_AURA)
    local diSz = PixelSnap(s.dispelIconSize or 16)
    dispelIconFrame:SetSize(diSz, diSz)
    dispelIconFrame:SetPoint("CENTER", health, "CENTER", 0, 0)
    dispelIconFrame:Hide()
    local dispelIconTex = dispelIconFrame:CreateTexture(nil, "ARTWORK")
    dispelIconTex:SetAllPoints()
    dispelIconTex:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Marker carrier: above the frame border (incl. hover/target raise) so the
    -- leader icon and raid marker render on top of it (mirrors real frames).
    local markerCarrier = CreateFrame("Frame", nil, f)
    markerCarrier:SetAllPoints(health)
    markerCarrier:SetFrameLevel(f:GetFrameLevel() + ns.LVL_MARKER)

    -- Raid marker (on marker carrier, above the border)
    local raidMarker = markerCarrier:CreateTexture(nil, "OVERLAY", nil, 2)
    local rmSz = PixelSnap(s.raidMarkerSize or 16)
    raidMarker:SetSize(rmSz, rmSz)
    raidMarker:Hide()

    -- Ready check icon
    local readyCheck = health:CreateTexture(nil, "OVERLAY", nil, 3)
    readyCheck:SetSize(18, 18)
    readyCheck:SetPoint("CENTER", health, "CENTER", 0, 0)
    readyCheck:Hide()

    -- Text carrier: above borders (+8/+10/+11), below the aura layer (+13).
    local textCarrier = CreateFrame("Frame", nil, f)
    textCarrier:SetAllPoints(health)
    textCarrier:SetFrameLevel(f:GetFrameLevel() + 12)

    -- Name text (anchoring done by ApplyPreviewData on every refresh)
    local nameFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(nameFS, s.nameSize or 10)
    nameFS:SetJustifyH("CENTER")
    nameFS:SetWordWrap(false)
    nameFS:SetPoint("CENTER", health, "CENTER", 0, 0)

    -- Health text
    local healthFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(healthFS, s.healthTextSize or 9)
    healthFS:SetJustifyH("CENTER")
    healthFS:SetPoint("CENTER", health, "CENTER", 0, 0)
    healthFS:SetTextColor(1, 1, 1, 0.9)

    -- Status text (DEAD / OFFLINE / AFK)
    local statusFS = textCarrier:CreateFontString(nil, "OVERLAY")
    local pvStc = s.statusTextColor or { r = 1, g = 1, b = 1 }
    ApplyFont(statusFS, s.statusTextSize or 14)
    statusFS:SetJustifyH("CENTER")
    statusFS:SetTextColor(pvStc.r, pvStc.g, pvStc.b)
    statusFS:Hide()

    -- Role icon (carrier frame above power bar + its border)
    local roleCarrier = CreateFrame("Frame", nil, f)
    roleCarrier:SetAllPoints(health)
    roleCarrier:SetFrameLevel(f:GetFrameLevel() + 5)
    local roleIcon = roleCarrier:CreateTexture(nil, "OVERLAY")
    local riSz = PixelSnap(s.roleIconSize or 14)
    roleIcon:SetSize(riSz, riSz)

    -- Leader icon (on marker carrier, above the border)
    local leaderIcon = markerCarrier:CreateTexture(nil, "OVERLAY")
    local liSz = PixelSnap(s.leaderIconSize or 14)
    leaderIcon:SetSize(liSz, liSz)
    local liPos = (s.leaderIconPosition or "top"):upper()
    leaderIcon:SetPoint(liPos, health, liPos, s.leaderIconOffsetX or 0, s.leaderIconOffsetY or 0)
    leaderIcon:Hide()

    -- Store references
    f._bg = bg
    f._health = health
    f._absorbBar = absorbBar
    f._power = power
    f._border = bdrFrame
    f._threatFrame = threatFrame
    f._dispelBdrFrame = dispelBdrFrame
    f._dispelOLTex = dispelOLTex
    f._dispelIcon = dispelIconFrame
    f._dispelIconTex = dispelIconTex
    f._raidMarker = raidMarker
    f._readyCheck = readyCheck
    f._nameText = nameFS
    f._healthText = healthFS
    f._statusText = statusFS
    f._roleIcon = roleIcon
    f._leaderIcon = leaderIcon

    -- Helper: create a preview aura icon with texture, cooldown, border
    local function MakePreviewAuraIcon(parent, level, sz)
        local di = CreateFrame("Frame", nil, parent)
        di:SetFrameLevel(level)
        di:SetSize(sz, sz)
        di:Hide()
        local dt = di:CreateTexture(nil, "ARTWORK")
        dt:SetAllPoints(); dt:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        di._tex = dt
        local cd = CreateFrame("Cooldown", nil, di, "CooldownFrameTemplate")
        cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawSwipe(true)
        cd:SetSwipeColor(0, 0, 0, 0.6); cd:SetReverse(true)
        cd:SetHideCountdownNumbers(true)
        di._cooldown = cd
        local dbdr = CreateFrame("Frame", nil, di)
        dbdr:SetAllPoints(); dbdr:SetFrameLevel(di:GetFrameLevel() + 1)
        if PP then PP.CreateBorder(dbdr, 0, 0, 0, 1, 1) end
        di._borderFrame = dbdr
        local countCarrier = CreateFrame("Frame", nil, di)
        countCarrier:SetAllPoints()
        countCarrier:SetFrameLevel(math.max(cd:GetFrameLevel() + 2, dbdr:GetFrameLevel() + 1))
        local fpInit = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local countFS = countCarrier:CreateFontString(nil, "OVERLAY")
        countFS:SetPoint("BOTTOMRIGHT", di, "BOTTOMRIGHT", 1, -1)
        countFS:SetFont(fpInit, 8, "OUTLINE")
        countFS:SetTextColor(1, 1, 1)
        countFS:SetText("")
        di._count = countFS
        -- Duration text (on same carrier above cooldown swipe)
        local durFS = countCarrier:CreateFontString(nil, "OVERLAY")
        durFS:SetPoint("CENTER", di, "CENTER", 0, 0)
        durFS:SetFont(fpInit, 8, "OUTLINE")
        durFS:SetTextColor(1, 1, 1)
        durFS:Hide()
        di._durText = durFS
        return di
    end

    -- Debuff preview icons
    f._pvDebuffs = {}
    for i = 1, 3 do
        f._pvDebuffs[i] = MakePreviewAuraIcon(f, f:GetFrameLevel() + ns.LVL_AURA, s.debuffSize or 18)
    end

    -- Static dispel debuff icon (shown when dispel eyeball is on)
    f._pvDispelDebuff = MakePreviewAuraIcon(f, f:GetFrameLevel() + ns.LVL_AURA, s.debuffSize or 18)

    -- Defensive preview icons
    f._pvDefs = {}
    for i = 1, 4 do
        f._pvDefs[i] = MakePreviewAuraIcon(f, f:GetFrameLevel() + ns.LVL_AURA, s.defSize or 22)
    end

    -- Private aura preview icons (simulated Blizzard-rendered boss debuffs)
    f._pvPA = {}
    for i = 1, 3 do
        f._pvPA[i] = MakePreviewAuraIcon(f, f:GetFrameLevel() + ns.LVL_AURA, s.paSize or 18)
    end

    -- Buff preview icons (test mode: configured buffs cycled across frames)
    f._pvBuffs = {}
    for i = 1, 8 do
        f._pvBuffs[i] = MakePreviewAuraIcon(f, f:GetFrameLevel() + ns.LVL_AURA, 18)
    end

    return f
end

local function GetOrCreatePreviewFrame(index)
    if not previewFrames[index] then
        previewFrames[index] = CreatePreviewFrame(index)
    end
    return previewFrames[index]
end

-- Preview role assignments: 2 tanks, 4 healers, 14 DPS.
-- Player (slot 1) uses their real role and counts toward the total.
local previewRoles = {}  -- [1..20] = "TANK"/"HEALER"/"DAMAGER"

previewClassTokens = {}  -- [1..20] class token per slot

local function BuildPreviewRoles()
    -- Clear numeric role assignments but preserve random state (underscore keys)
    for i = 1, 20 do previewRoles[i] = nil end
    wipe(previewClassTokens)

    -- Use group role if in a group, otherwise fall back to spec role
    local playerRole = UnitGroupRolesAssigned("player")
    if playerRole ~= "TANK" and playerRole ~= "HEALER" then
        local specIdx = GetSpecialization()
        local specRole = specIdx and select(5, GetSpecializationInfo(specIdx))
        if specRole == "TANK" or specRole == "HEALER" then
            playerRole = specRole
        else
            playerRole = "DAMAGER"
        end
    end
    previewRoles[1] = playerRole
    local _, pct = UnitClass("player")
    previewClassTokens[1] = pct or "WARRIOR"

    local tanksLeft = 2
    local healersLeft = 4
    if playerRole == "TANK" then tanksLeft = tanksLeft - 1 end
    if playerRole == "HEALER" then healersLeft = healersLeft - 1 end

    -- Counters for round-robin within each role's class pool
    local tankIdx, healerIdx, dpsIdx = 1, 1, 1

    for i = 2, 20 do
        if tanksLeft > 0 then
            previewRoles[i] = "TANK"
            previewClassTokens[i] = ns._PV_TANK_CLASSES[tankIdx]
            tankIdx = (tankIdx % #ns._PV_TANK_CLASSES) + 1
            tanksLeft = tanksLeft - 1
        elseif healersLeft > 0 then
            previewRoles[i] = "HEALER"
            previewClassTokens[i] = ns._PV_HEALER_CLASSES[healerIdx]
            healerIdx = (healerIdx % #ns._PV_HEALER_CLASSES) + 1
            healersLeft = healersLeft - 1
        else
            previewRoles[i] = "DAMAGER"
            previewClassTokens[i] = ns._PV_DPS_CLASSES[dpsIdx]
            dpsIdx = (dpsIdx % #ns._PV_DPS_CLASSES) + 1
        end
    end

    -- Sort within each group based on sort settings
    local sortMode = db.profile.sortMode or "INDEX"
    -- Self ordering is non-merged only (ignored when Merge Groups is enabled).
    -- showSelfFirst here means "self ordering active"; selfLast picks the end.
    local selfLast = db.profile.showSelfLast and not db.profile.mergeGroups
    local showSelfFirst = (db.profile.showSelfFirst or db.profile.showSelfLast) and not db.profile.mergeGroups
    previewRoles._playerSlot = 1  -- default: player is slot 1

    if sortMode == "ROLE" or showSelfFirst then
        for g = 0, 3 do
            local base = g * 5
            -- Build sortable list for this group
            local group = {}
            for u = 1, 5 do
                local idx = base + u
                group[u] = {
                    role = previewRoles[idx],
                    classToken = previewClassTokens[idx],
                    isPlayer = (idx == 1),
                }
            end

            if sortMode == "ROLE" then
                local roleOrder = db.profile.roleOrder or { "TANK", "HEALER", "DAMAGER" }
                local rolePriority = {}
                for pri, role in ipairs(roleOrder) do
                    rolePriority[role] = pri
                end
                -- Stable sort by role priority
                local tmpGroup = {}
                for pri, role in ipairs(roleOrder) do
                    for _, entry in ipairs(group) do
                        if entry.role == role then
                            tmpGroup[#tmpGroup + 1] = entry
                        end
                    end
                end
                -- Any roles not in roleOrder (shouldn't happen, but safe)
                for _, entry in ipairs(group) do
                    if not rolePriority[entry.role] then
                        tmpGroup[#tmpGroup + 1] = entry
                    end
                end
                group = tmpGroup
            end

            if showSelfFirst then
                local playerPos
                for i, entry in ipairs(group) do
                    if entry.isPlayer then playerPos = i; break end
                end
                if playerPos then
                    if selfLast and playerPos < #group then
                        local playerEntry = table.remove(group, playerPos)
                        group[#group + 1] = playerEntry
                    elseif not selfLast and playerPos > 1 then
                        local playerEntry = table.remove(group, playerPos)
                        tinsert(group, 1, playerEntry)
                    end
                end
            end

            -- Write back sorted data
            for u = 1, 5 do
                local idx = base + u
                previewRoles[idx] = group[u].role
                previewClassTokens[idx] = group[u].classToken
                if group[u].isPlayer then
                    previewRoles._playerSlot = idx
                end
            end
        end
    end

    -- Random element picks: only randomize once per preview session.
    -- Subsequent calls (from setting changes) reuse the same values.
    if not previewRoles._randomized then
        previewRoles._randomized = true

        -- Pick a random tank for the aggro indicator
        local tanks = {}
        for i = 1, 20 do
            if previewRoles[i] == "TANK" then tanks[#tanks + 1] = i end
        end
        previewRoles._threatIndex = tanks[math.random(#tanks)] or 1

        -- Pick random players for raid markers: 1 in group 1, 1 in group 4
        previewRoles._markerSlot1 = math.random(5)          -- slot 1-5 (group 1)
        previewRoles._markerSlot2 = 15 + math.random(5)     -- slot 16-20 (group 4)

        -- Ready check: 3 not ready, 11 ready, 6 pending (randomized)
        local rcStatuses = {}
        for i = 1, 3 do rcStatuses[#rcStatuses + 1] = "notready" end
        for i = 1, 8 do rcStatuses[#rcStatuses + 1] = "ready" end
        for i = 1, 6 do rcStatuses[#rcStatuses + 1] = "pending" end
        rcStatuses[#rcStatuses + 1] = "summon_pending"
        rcStatuses[#rcStatuses + 1] = "summon_accepted"
        rcStatuses[#rcStatuses + 1] = "summon_declined"
        -- Shuffle
        for i = #rcStatuses, 2, -1 do
            local j = math.random(i)
            rcStatuses[i], rcStatuses[j] = rcStatuses[j], rcStatuses[i]
        end
        -- Clear readycheck/summon on marker slots so they don't overlap
        local ms1, ms2 = previewRoles._markerSlot1, previewRoles._markerSlot2
        if ms1 then rcStatuses[ms1] = nil end
        if ms2 then rcStatuses[ms2] = nil end
        previewRoles._readyCheck = rcStatuses

        -- Dispel types: one of each in group 1 (slots 1-5)
        local dispelTypes = { "Magic", "Curse", "Disease", "Poison", "" }
        local dispelMap = {}
        for i, dt in ipairs(dispelTypes) do
            dispelMap[i] = dt
        end
        previewRoles._dispelMap = dispelMap

        -- Dead/offline: one of each, random non-player slots
        local statePool = {}
        for i = 2, 20 do statePool[#statePool + 1] = i end
        for i = #statePool, 2, -1 do
            local j = math.random(i)
            statePool[i], statePool[j] = statePool[j], statePool[i]
        end
        previewRoles._deadSlot    = statePool[1]
        previewRoles._offlineSlot = statePool[2]
        -- Clear readycheck on dead/offline slots
        if rcStatuses[statePool[1]] then rcStatuses[statePool[1]] = nil end
        if rcStatuses[statePool[2]] then rcStatuses[statePool[2]] = nil end
    end
end

ns.previewAbsorbValues = ns.previewAbsorbValues or {}
local previewHealthValues = {}
local previewPowerValues = {}
ns.previewHealAbsorbValues = {}

local function ApplyPreviewData(f, index)
    -- The main raid preview is a base "20 Man" mockup: RefreshPreview lays it
    -- out from the base frameWidth and CreatePreviewFrame sizes from it too, so
    -- the per-button sizing here must read the base profile as well. Using
    -- ns._scaledProfile instead returned ns._activeSizeW (the active raid-size
    -- tier override) for frameWidth, which froze the buttons at the override
    -- size while the layout used the base width -- so the 20 Man Width slider
    -- re-spaced the layout without resizing the buttons whenever a custom raid
    -- size was active (e.g. in a party / small group on the Raid tab). The
    -- party preview still passes its own override via _previewSettingsOverride.
    local s = ns._previewSettingsOverride or db.profile
    local classToken = previewClassTokens[index] or ns._PV_CLASS_TOKENS[((index - 1) % #ns._PV_CLASS_TOKENS) + 1]
    local playerSlot = previewRoles._playerSlot or 1
    local name
    if index == playerSlot then
        name = UnitName("player") or "Player"
        if Ambiguate then name = Ambiguate(name, "short") end
    else
        name = ns._PV_NAMES[((index - 1) % #ns._PV_NAMES) + 1]
    end
    local healthPct = previewHealthValues[index] or (40 + math.random(60))

    local w = PixelSnap(s.frameWidth or 72)
    local h = PixelSnap(s.frameHeight or 46)
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(h - powerH)

    f:SetSize(w, h)

    -- Health bar
    if f._health then
        f._health:SetHeight(healthH)
        f._health:SetStatusBarTexture(ResolveHealthTexture())
        f._health:GetStatusBarTexture():SetHorizTile(false)
        f._health:SetMinMaxValues(0, 100)
        f._health:SetValue(healthPct)
        f._healthPct = healthPct
        f._classToken = classToken

        local mode = s.healthColorMode or "class"
        local fillTex = f._health:GetStatusBarTexture()
        if mode == "dark" then
            f._health:SetStatusBarColor(DARK_FILL_R, DARK_FILL_G, DARK_FILL_B, 1)
            if fillTex then fillTex:SetAlpha(DARK_FILL_A) end
        elseif mode == "classic" then
            if fillTex then fillTex:SetAlpha(1) end
            local pct = healthPct / 100
            local r = pct < 0.5 and 1 or (1 - (pct - 0.5) * 2)
            local g = pct > 0.5 and 1 or (pct * 2)
            f._health:SetStatusBarColor(r, g, 0, (s.healthBarOpacity or 100) / 100)
        elseif mode == "custom" then
            if fillTex then fillTex:SetAlpha(1) end
            local c = s.customFillColor
            f._health:SetStatusBarColor(c.r, c.g, c.b, (s.healthBarOpacity or 100) / 100)
        else
            if fillTex then fillTex:SetAlpha(1) end
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then f._health:SetStatusBarColor(cc.r, cc.g, cc.b, (s.healthBarOpacity or 100) / 100) end
        end
    end

    -- Background
    if f._bg then
        if s.healthColorMode == "dark" then
            f._bg:ClearAllPoints()
            f._bg:SetPoint("TOPLEFT", f._health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
            f._bg:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
            f._bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, 1)
        else
            -- BG covers the missing-health portion only (never behind the fill),
            -- matching the real-frame themed branch + Dark mode. Keeps the preview
            -- a 1:1 replica for reduced-fill-opacity setups.
            f._bg:ClearAllPoints()
            f._bg:SetPoint("TOPLEFT", f._health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
            f._bg:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
            local bgc = s.customBgColor
            f._bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
        end
    end

    -- Absorb shield preview (dual clip-frame: backfill + forward)
    if f._absorbBar then
        local absStyle = s.absorbStyle or "none"
        if ns._indicatorsVisible then absStyle = "none"
        elseif ns._testMode then
            if ns._testAbsorbs == false then absStyle = "none"
            elseif ns._testAbsorbs and absStyle == "none" then absStyle = "striped" end
        end
        local absorbAmt = ns.previewAbsorbValues[index] or 0
        local fw = f._absorbBar._forward
        if absStyle ~= "none" and absorbAmt > 0 then
            local tex = ABSORB_STYLE_TEX[absStyle] or "Interface\\Buttons\\WHITE8X8"
            local alpha = (s.absorbOpacity or 90) / 100
            local tiled = (absStyle == "striped")
            local hpW = w
            local hpH = healthH
            local mask = f._absorbBar._mask

            -- Apply style to backfill bar
            local ac = s.absorbColor or { r = 1, g = 1, b = 1 }
            f._absorbBar:SetStatusBarTexture(tex)
            f._absorbBar:SetStatusBarColor(ac.r, ac.g, ac.b, alpha)
            f._absorbBar:SetWidth(hpW)
            f._absorbBar:SetHeight(hpH)
            local bfFill = f._absorbBar:GetStatusBarTexture()
            if bfFill then
                bfFill:SetDrawLayer("ARTWORK", 1)
                bfFill:SetHorizTile(tiled)
                bfFill:SetVertTile(tiled)
                if mask then bfFill:AddMaskTexture(mask) end
            end

            -- Apply style to forward bar
            if fw then
                fw:SetStatusBarTexture(tex)
                fw:SetStatusBarColor(ac.r, ac.g, ac.b, alpha)
                fw:SetWidth(hpW)
                fw:SetHeight(hpH)
                local fwFill = fw:GetStatusBarTexture()
                if fwFill then
                    fwFill:SetDrawLayer("ARTWORK", 1)
                    fwFill:SetHorizTile(tiled)
                    fwFill:SetVertTile(tiled)
                    if mask then fwFill:AddMaskTexture(mask) end
                end
            end

            -- Feed both bars with the same absorb value; clip frames do the visual math
            f._absorbBar:SetMinMaxValues(0, 100)
            f._absorbBar:SetValue(absorbAmt)
            f._absorbBar:Show()
            if fw then
                fw:SetMinMaxValues(0, 100)
                fw:SetValue(absorbAmt)
                fw:Show()
            end
        else
            f._absorbBar:Hide()
            if fw then fw:Hide() end
        end
        -- Position clip frames based on absorb rendering mode
        local cc = f._absorbBar._curClip
        local mc = f._absorbBar._missClip
        if cc and mc and f._health then
            if s.absorbFromRightEdge then
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                cc:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                if fw then fw:Hide() end
            else
                local fill = f._health:GetStatusBarTexture()
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                cc:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
                mc:ClearAllPoints()
                mc:SetPoint("TOPLEFT", fill, "TOPRIGHT", -1, 0)
                mc:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
            end
        end
    end

    -- Heal absorb preview
    if f._healAbsorbBar then
        local haStyle = s.healAbsorbStyle or "clean"
        if ns._indicatorsVisible then haStyle = "none"
        elseif ns._testMode then
            if ns._testHealAbsorbs == false then haStyle = "none"
            elseif ns._testHealAbsorbs and haStyle == "none" then haStyle = "clean" end
        end
        local haAmt = ns.previewHealAbsorbValues[index] or 0
        if haStyle ~= "none" and haAmt > 0 then
            local haTex = ABSORB_STYLE_TEX[haStyle] or "Interface\\Buttons\\WHITE8X8"
            local haAlpha = (s.healAbsorbOpacity or 75) / 100
            local hc = s.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
            local tiled = (haStyle == "striped")
            local hpW = w
            local hpH = healthH
            local mask = f._healAbsorbBar._mask
            f._healAbsorbBar:SetStatusBarTexture(haTex)
            f._healAbsorbBar:SetStatusBarColor(hc.r, hc.g, hc.b, haAlpha)
            f._healAbsorbBar:SetWidth(hpW)
            f._healAbsorbBar:SetHeight(hpH)
            local haFillPv = f._healAbsorbBar:GetStatusBarTexture()
            if haFillPv then
                haFillPv:SetDrawLayer("ARTWORK", 2)
                haFillPv:SetHorizTile(tiled)
                haFillPv:SetVertTile(tiled)
                if mask then haFillPv:AddMaskTexture(mask) end
            end
            f._healAbsorbBar:SetMinMaxValues(0, 100)
            f._healAbsorbBar:SetValue(haAmt)
            f._healAbsorbBar:Show()
        else
            f._healAbsorbBar:Hide()
        end
        -- Right-edge mode: anchor heal absorb to health bar right edge
        if f._health then
            if s.absorbFromRightEdge then
                f._healAbsorbBar:ClearAllPoints()
                f._healAbsorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                f._healAbsorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
            else
                local fill = f._health:GetStatusBarTexture()
                f._healAbsorbBar:ClearAllPoints()
                f._healAbsorbBar:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
                f._healAbsorbBar:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
            end
        end
    end

    -- Heal prediction preview
    if f._healPredBar then
        local predAmt = ns.previewHealPredValues and ns.previewHealPredValues[index] or 0
        local wantPred = s.healPrediction
        if ns._indicatorsVisible then wantPred = false
        elseif ns._testMode and ns._testHealPrediction ~= nil then wantPred = ns._testHealPrediction end
        if wantPred and predAmt > 0 then
            local pc = s.healPredColor or { r = 102/255, g = 243/255, b = 102/255 }
            local pAlpha = (s.healPredOpacity or 75) / 100
            f._healPredBar:SetStatusBarColor(pc.r, pc.g, pc.b, pAlpha)
            f._healPredBar:SetWidth(w)
            f._healPredBar:SetHeight(healthH)
            f._healPredBar:SetMinMaxValues(0, 100)
            f._healPredBar:SetValue(predAmt)
            f._healPredBar:Show()
        else
            f._healPredBar:Hide()
        end
    end

    -- Reduced max health preview
    if f._reducedMaxHealthBar then
        local rmhAmt = ns.previewReducedMaxHealth and ns.previewReducedMaxHealth[index] or 0
        if ns._testReducedMaxHealth and rmhAmt > 0 then
            f._reducedMaxHealthBar:SetValue(rmhAmt)
            f._reducedMaxHealthBar:Show()
        else
            f._reducedMaxHealthBar:Hide()
        end
    end

    -- Power (filtered by role, hidden if class has no power)
    local role = previewRoles[index] or "DAMAGER"
    local showForRole = (role == "HEALER" and s.powerShowForHealer)
        or (role == "TANK" and s.powerShowForTank)
        or (role == "DAMAGER" and s.powerShowForDPS)
    local hidePower = powerH <= 0 or not showForRole

    if f._power then
        if not hidePower then
            f._power:SetHeight(powerH)
            f._power:SetStatusBarTexture(ResolveHealthTexture())
            f._power:GetStatusBarTexture():SetHorizTile(false)
            local pwPct = previewPowerValues[index] or (60 + math.random(40))
            f._power:SetMinMaxValues(0, 100)
            f._power:SetValue(pwPct)
            f._powerPct = pwPct
            local pwToken = ns._PV_CLASS_POWER[classToken] or "MANA"
            local pc = EllesmereUI.GetPowerColor and EllesmereUI.GetPowerColor(pwToken)
            if pc then
                f._power:SetStatusBarColor(pc.r, pc.g, pc.b, 1)
            else
                f._power:SetStatusBarColor(0, 0.5, 1, 1)
            end
            f._power:Show()
        else
            f._power:Hide()
        end
    end

    -- Expand health to full frame when power is hidden
    if f._health then
        if hidePower then
            f._health:SetHeight(h)
        else
            f._health:SetHeight(healthH)
        end
    end

    if f._powerBg then
        if hidePower then
            f._powerBg:Hide()
        else
            f._powerBg:SetColorTexture((s.powerBgColor or {}).r or 0, (s.powerBgColor or {}).g or 0, (s.powerBgColor or {}).b or 0, (s.powerBgDarkness or 70) / 100)
            f._powerBg:Show()
        end
    end

    -- Power border
    if f._powerBorder and PP then
        if hidePower then
            f._powerBorder:Hide()
        else
            local pbStyle = s.powerBorderStyle or "eui"
            if pbStyle == "eui" then
                PP.UpdateBorder(f._powerBorder, 1, 1, 1, 1, 0.2)
                f._powerBorder:Show()
                local ppC = PP.GetBorders(f._powerBorder)
                if ppC then
                    if ppC._bottom then ppC._bottom:SetAlpha(0) end
                    if ppC._left then ppC._left:SetAlpha(0) end
                    if ppC._right then ppC._right:SetAlpha(0) end
                    if ppC._top then ppC._top:SetAlpha(0.2) end
                end
            else
                local pbSize = s.powerBorderSize or 1
                if pbSize <= 0 then
                    f._powerBorder:Hide()
                else
                    local pbc = s.powerBorderColor
                    local pba = s.powerBorderAlpha or 1
                    PP.UpdateBorder(f._powerBorder, pbSize, pbc.r, pbc.g, pbc.b, pba)
                    f._powerBorder:Show()
                    local ppC = PP.GetBorders(f._powerBorder)
                    if ppC then
                        if pbStyle == "divider" then
                            if ppC._bottom then ppC._bottom:SetAlpha(0) end
                            if ppC._left then ppC._left:SetAlpha(0) end
                            if ppC._right then ppC._right:SetAlpha(0) end
                            if ppC._top then ppC._top:SetAlpha(pba) end
                        else
                            if ppC._top then ppC._top:SetAlpha(pba) end
                            if ppC._bottom then ppC._bottom:SetAlpha(pba) end
                            if ppC._left then ppC._left:SetAlpha(pba) end
                            if ppC._right then ppC._right:SetAlpha(pba) end
                        end
                    end
                end
            end
        end
    end

    -- Border (style/size/texture/offsets via ApplyBorderStyle, then state recolor)
    if f._border and PP then
        local bs = s.borderSize or 1
        local bc = s.borderColor or { r = 0, g = 0, b = 0 }
        local pl = f:GetFrameLevel()
        f._border:SetFrameLevel(s.borderBehind and math.max(0, pl - 1) or (pl + 8))
        EllesmereUI.ApplyBorderStyle(f._border, bs, bc.r, bc.g, bc.b, s.borderAlpha or 1,
            s.borderTexture or "solid", s.borderTextureOffset, s.borderTextureOffsetY,
            s.borderTextureShiftX, s.borderTextureShiftY, "unitframes", bs)
        if f._ApplyBorderColor then f._ApplyBorderColor() end
    end

    -- Indicators visibility (eyeball toggle)
    local indVis = ns._indicatorsVisible ~= false

    -- Threat border (always visible in test mode, otherwise requires animation)
    if f._threatFrame and PP then
        local bs = s.threatBorderSize or 0
        local wantThreat = bs > 0
        if ns._testMode and ns._testThreat ~= nil then wantThreat = ns._testThreat end
        if wantThreat and (ns._testMode or ns._healthAnimActive) and previewRoles._threatIndex == index then
            PP.UpdateBorder(f._threatFrame, bs > 0 and bs or 1, 1, 0, 0, 1)
            f._threatFrame:Show()
        else
            f._threatFrame:Hide()
        end
    end

    -- Dispel visuals (border, overlay, icon)
    local dispVis = ns._dispelsVisible ~= false
    local dispelMap = previewRoles._dispelMap
    local dispelType = dispelMap and dispelMap[index]
    local dispelDC = dispelType and GetDispelColor(dispelType, s)
    if dispVis and dispelDC then
        -- Dispel border (PP.UpdateBorder handles physical pixel sizing internally)
        local dbs = s.dispelBorderSize or 2
        if f._dispelBdrFrame and PP and dbs > 0 then
            PP.UpdateBorder(f._dispelBdrFrame, dbs, dispelDC.r, dispelDC.g, dispelDC.b, 1)
            f._dispelBdrFrame:Show()
        elseif f._dispelBdrFrame then
            f._dispelBdrFrame:Hide()
        end
        -- Dispel overlay
        local olMode = s.dispelOverlay or "fill"
        if olMode ~= "none" and f._dispelOLTex and f._health then
            local olAlpha = (s.dispelOverlayOpacity or 100) / 100
            local olTex = f._dispelOLTex
            olTex:ClearAllPoints()
            -- Reset any prior vertex tint so fill/full render their explicit color cleanly.
            olTex:SetVertexColor(1, 1, 1, 1)
            if olMode == "fill" then
                local fillTex = f._health:GetStatusBarTexture()
                if fillTex then
                    olTex:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    olTex:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 0)
                else
                    olTex:SetAllPoints(f._health)
                end
                olTex:SetColorTexture(dispelDC.r, dispelDC.g, dispelDC.b, olAlpha)
            elseif olMode == "full" then
                olTex:SetAllPoints(f._health)
                olTex:SetColorTexture(dispelDC.r, dispelDC.g, dispelDC.b, olAlpha)
            elseif olMode == "gradient" then
                -- Same pre-baked gradient texture as the live frames so the preview matches.
                olTex:SetAllPoints(f._health)
                olTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-tb.tga")
                olTex:SetVertexColor(dispelDC.r, dispelDC.g, dispelDC.b, olAlpha)
            end
            olTex:Show()
        elseif f._dispelOLTex then
            f._dispelOLTex:Hide()
        end
        -- Dispel type icon (positioned per setting)
        if s.showDispelIcons and f._dispelIcon and f._dispelIconTex then
            local atlas = DISPEL_ICON_ATLAS[dispelType]
            if atlas then f._dispelIconTex:SetAtlas(atlas) end
            local diSz = PixelSnap(s.dispelIconSize or 16)
            f._dispelIcon:SetSize(diSz, diSz)
            f._dispelIcon:ClearAllPoints()
            local diPos = s.dispelIconPosition or "center"
            local diOX = s.dispelIconOffsetX or 0
            local diOY = s.dispelIconOffsetY or 0
            -- Dispel icon anchors flush to the health bar edge (no 1px inset),
            -- matching the debuff/role icon displays.
            if diPos == "topleft" then
                f._dispelIcon:SetPoint("TOPLEFT", f._health, "TOPLEFT", diOX, diOY)
            elseif diPos == "top" then
                f._dispelIcon:SetPoint("TOP", f._health, "TOP", diOX, diOY)
            elseif diPos == "topright" then
                f._dispelIcon:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", diOX, diOY)
            elseif diPos == "left" then
                f._dispelIcon:SetPoint("LEFT", f._health, "LEFT", diOX, diOY)
            elseif diPos == "right" then
                f._dispelIcon:SetPoint("RIGHT", f._health, "RIGHT", diOX, diOY)
            elseif diPos == "bottomleft" then
                f._dispelIcon:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", diOX, diOY)
            elseif diPos == "bottom" then
                f._dispelIcon:SetPoint("BOTTOM", f._health, "BOTTOM", diOX, diOY)
            elseif diPos == "bottomright" then
                f._dispelIcon:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", diOX, diOY)
            else -- center
                f._dispelIcon:SetPoint("CENTER", f._health, "CENTER", diOX, diOY)
            end
            f._dispelIcon:Show()
        elseif f._dispelIcon then
            f._dispelIcon:Hide()
        end
    else
        if f._dispelBdrFrame then f._dispelBdrFrame:Hide() end
        if f._dispelOLTex then f._dispelOLTex:Hide() end
        if f._dispelIcon then f._dispelIcon:Hide() end
    end

    -- Static dispel debuff icon (shows a fake debuff matching user's debuff settings)
    if f._pvDispelDebuff then
        if dispVis and dispelType and ns._PV_DISPEL_DB_ICONS[dispelType] then
            local ddi = f._pvDispelDebuff
            local dbSz = s.debuffSize or 18
            ddi:SetSize(dbSz, dbSz)
            ddi._tex:SetTexture(ns._PV_DISPEL_DB_ICONS[dispelType])
            ddi._tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- Position using debuff settings
            ddi:ClearAllPoints()
            local dbPos = s.debuffPosition or "bottomright"
            local dbOX = s.debuffOffsetX or 0
            local dbOY = s.debuffOffsetY or 0
            if dbPos == "topleft" then
                ddi:SetPoint("TOPLEFT", f._health, "TOPLEFT", dbOX, dbOY)
            elseif dbPos == "top" then
                ddi:SetPoint("TOP", f._health, "TOP", dbOX, dbOY)
            elseif dbPos == "topright" then
                ddi:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", dbOX, dbOY)
            elseif dbPos == "left" then
                ddi:SetPoint("LEFT", f._health, "LEFT", dbOX, dbOY)
            elseif dbPos == "center" then
                ddi:SetPoint("CENTER", f._health, "CENTER", dbOX, dbOY)
            elseif dbPos == "right" then
                ddi:SetPoint("RIGHT", f._health, "RIGHT", dbOX, dbOY)
            elseif dbPos == "bottomleft" then
                ddi:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", dbOX, dbOY)
            elseif dbPos == "bottom" then
                ddi:SetPoint("BOTTOM", f._health, "BOTTOM", dbOX, dbOY)
            else -- bottomright
                ddi:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", dbOX, dbOY)
            end

            -- Border (dispel-type colored)
            local dbBdrSz = s.debuffBorderSize or 1
            if ddi._borderFrame and PP and dbBdrSz > 0 then
                local dc = GetDispelColor(dispelType, s)
                if dc then
                    PP.UpdateBorder(ddi._borderFrame, dbBdrSz, dc.r, dc.g, dc.b, 1)
                else
                    local bc = s.debuffBorderColor or { r = 0, g = 0, b = 0 }
                    PP.UpdateBorder(ddi._borderFrame, dbBdrSz, bc.r, bc.g, bc.b, 1)
                end
                ddi._borderFrame:Show()
            elseif ddi._borderFrame then
                ddi._borderFrame:Hide()
            end

            if ddi._cooldown then ddi._cooldown:Hide() end
            if ddi._count then ddi._count:SetText("") end
            if ddi._durText then ddi._durText:Hide() end
            ddi:Show()
        else
            f._pvDispelDebuff:Hide()
        end
    end

    -- Hover/target are recolored onto the single border (f._ApplyBorderColor),
    -- applied above with the border style; no separate hover/target frames.

    -- Raid marker (1 random in group 1, 1 random in group 4)
    if f._raidMarker then
        local isMarked = indVis and s.showRaidMarker and
            (index == previewRoles._markerSlot1 or index == previewRoles._markerSlot2)
        if isMarked then
            local rmSz = PixelSnap(s.raidMarkerSize or 16)
            f._raidMarker:SetSize(rmSz, rmSz)
            -- Use custom marker PNGs
            if index == previewRoles._markerSlot1 then
                f._raidMarker:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\marker.png")
                f._raidMarker:SetTexCoord(0, 1, 0, 1)
            else
                f._raidMarker:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\marker2.png")
                f._raidMarker:SetTexCoord(0, 1, 0, 1)
            end
            -- Anchor based on marker position setting
            f._raidMarker:ClearAllPoints()
            local pos = s.raidMarkerPosition or "center"
            local ox = s.raidMarkerOffsetX or 0
            local oy = s.raidMarkerOffsetY or 0
            if pos == "topleft" then
                f._raidMarker:SetPoint("TOPLEFT", f._health, "TOPLEFT", 2 + ox, -2 + oy)
            elseif pos == "top" then
                f._raidMarker:SetPoint("TOP", f._health, "TOP", ox, -2 + oy)
            elseif pos == "topright" then
                f._raidMarker:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", -2 + ox, -2 + oy)
            elseif pos == "left" then
                f._raidMarker:SetPoint("LEFT", f._health, "LEFT", 2 + ox, oy)
            elseif pos == "right" then
                f._raidMarker:SetPoint("RIGHT", f._health, "RIGHT", -2 + ox, oy)
            elseif pos == "bottomleft" then
                f._raidMarker:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 2 + ox, 2 + oy)
            elseif pos == "bottom" then
                f._raidMarker:SetPoint("BOTTOM", f._health, "BOTTOM", ox, 2 + oy)
            elseif pos == "bottomright" then
                f._raidMarker:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            else -- center
                f._raidMarker:SetPoint("CENTER", f._health, "CENTER", ox, oy)
            end
            f._raidMarker:Show()
        else
            f._raidMarker:Hide()
        end
    end

    -- Ready check icon
    if f._readyCheck then
        local rcStatuses = previewRoles._readyCheck
        local rcStatuses = previewRoles._readyCheck
        local rcStatus = rcStatuses and rcStatuses[index]
        local isSummon = rcStatus and rcStatus:sub(1, 6) == "summon"
        local showRC = indVis and rcStatus and (
            (not isSummon and s.showReadyCheck) or
            (isSummon and s.showSummonPending)
        )
        if showRC then
            if isSummon then
                f._readyCheck:SetSize(20, 20)
            else
                f._readyCheck:SetSize(18, 18)
            end
            if rcStatus == "ready" then
                f._readyCheck:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                f._readyCheck:SetTexCoord(0, 1, 0, 1)
            elseif rcStatus == "notready" then
                f._readyCheck:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
                f._readyCheck:SetTexCoord(0, 1, 0, 1)
            elseif rcStatus == "pending" then
                f._readyCheck:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
                f._readyCheck:SetTexCoord(0, 1, 0, 1)
            elseif rcStatus == "summon_pending" then
                f._readyCheck:SetAtlas("RaidFrame-Icon-SummonPending")
            elseif rcStatus == "summon_accepted" then
                f._readyCheck:SetAtlas("RaidFrame-Icon-SummonAccepted")
            elseif rcStatus == "summon_declined" then
                f._readyCheck:SetAtlas("RaidFrame-Icon-SummonDeclined")
            end
            f._readyCheck:Show()
        else
            f._readyCheck:Hide()
        end
    end

    -- Name (re-anchor position every refresh, single-point + width constraint)
    if f._nameText then
        f._nameText:ClearAllPoints()
        local pos = s.namePosition or "center"
        local ox = s.nameOffsetX or 0
        local oy = s.nameOffsetY or 0
        f._nameText:SetWidth((s.frameWidth or 72) * 0.75)
        f._nameText:SetHeight(0)
        if pos == "topleft" then
            f._nameText:SetPoint("TOPLEFT", f._health, "TOPLEFT", 2 + ox, -2 + oy)
            f._nameText:SetJustifyH("LEFT"); f._nameText:SetJustifyV("TOP")
        elseif pos == "top" then
            f._nameText:SetPoint("TOP", f._health, "TOP", ox, -2 + oy)
            f._nameText:SetJustifyH("CENTER"); f._nameText:SetJustifyV("TOP")
        elseif pos == "topright" then
            f._nameText:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", -2 + ox, -2 + oy)
            f._nameText:SetJustifyH("RIGHT"); f._nameText:SetJustifyV("TOP")
        elseif pos == "left" then
            f._nameText:SetPoint("LEFT", f._health, "LEFT", 2 + ox, oy)
            f._nameText:SetJustifyH("LEFT"); f._nameText:SetJustifyV("MIDDLE")
        elseif pos == "right" then
            f._nameText:SetPoint("RIGHT", f._health, "RIGHT", -2 + ox, oy)
            f._nameText:SetJustifyH("RIGHT"); f._nameText:SetJustifyV("MIDDLE")
        elseif pos == "bottomleft" then
            f._nameText:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 2 + ox, 2 + oy)
            f._nameText:SetJustifyH("LEFT"); f._nameText:SetJustifyV("BOTTOM")
        elseif pos == "bottom" then
            f._nameText:SetPoint("BOTTOM", f._health, "BOTTOM", ox, 2 + oy)
            f._nameText:SetJustifyH("CENTER"); f._nameText:SetJustifyV("BOTTOM")
        elseif pos == "bottomright" then
            f._nameText:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            f._nameText:SetJustifyH("RIGHT"); f._nameText:SetJustifyV("BOTTOM")
        else -- center
            f._nameText:SetPoint("CENTER", f._health, "CENTER", ox, oy)
            f._nameText:SetJustifyH("CENTER"); f._nameText:SetJustifyV("MIDDLE")
        end
        -- Force text re-render (WoW doesn't visually re-layout on JustifyH change alone)
        f._nameText:SetText("")
        f._nameText:SetText(name)
        ApplyFont(f._nameText, s.nameSize or 10)
        local nameMode = s.nameColorMode or "class"
        if nameMode == "accent" then
            local ar, ag, ab = EllesmereUI.ResolveThemeColor(EllesmereUI.GetActiveTheme())
            if ar then f._nameText:SetTextColor(ar, ag, ab)
            else f._nameText:SetTextColor(1, 1, 1) end
        elseif nameMode == "custom" then
            local c = s.nameCustomColor
            f._nameText:SetTextColor(c.r, c.g, c.b)
        else
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then f._nameText:SetTextColor(cc.r, cc.g, cc.b)
            else f._nameText:SetTextColor(1, 1, 1) end
        end
    end

    -- Dead/offline/AFK states (only when indicators eyeball is on)
    local isDead    = indVis and index == previewRoles._deadSlot
    local isOffline = indVis and index == previewRoles._offlineSlot
    -- Mark dead/offline preview frames so the animated-preview ticker skips them
    -- (their health bar is emptied and health text hidden -- never animated).
    f._pvHideHealthText = (isDead or isOffline) or nil
    local isAfk     = indVis and index == previewRoles._afkSlot

    -- Health text
    if f._healthText then
        ApplyFont(f._healthText, s.healthTextSize or 9)
        -- Position
        f._healthText:ClearAllPoints()
        local htPos = s.healthTextPosition or "center"
        local htOX = s.healthTextOffsetX or 0
        local htOY = s.healthTextOffsetY or 0
        local htW = (s.frameWidth or 72) * 0.75
        f._healthText:SetWidth(htW)
        f._healthText:SetHeight(0)
        if htPos == "topleft" then
            f._healthText:SetPoint("TOPLEFT", f._health, "TOPLEFT", 2 + htOX, -2 + htOY)
            f._healthText:SetJustifyH("LEFT"); f._healthText:SetJustifyV("TOP")
        elseif htPos == "top" then
            f._healthText:SetPoint("TOP", f._health, "TOP", htOX, -2 + htOY)
            f._healthText:SetJustifyH("CENTER"); f._healthText:SetJustifyV("TOP")
        elseif htPos == "topright" then
            f._healthText:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", -2 + htOX, -2 + htOY)
            f._healthText:SetJustifyH("RIGHT"); f._healthText:SetJustifyV("TOP")
        elseif htPos == "left" then
            f._healthText:SetPoint("LEFT", f._health, "LEFT", 2 + htOX, htOY)
            f._healthText:SetJustifyH("LEFT"); f._healthText:SetJustifyV("MIDDLE")
        elseif htPos == "right" then
            f._healthText:SetPoint("RIGHT", f._health, "RIGHT", -2 + htOX, htOY)
            f._healthText:SetJustifyH("RIGHT"); f._healthText:SetJustifyV("MIDDLE")
        elseif htPos == "bottomleft" then
            f._healthText:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 2 + htOX, 2 + htOY)
            f._healthText:SetJustifyH("LEFT"); f._healthText:SetJustifyV("BOTTOM")
        elseif htPos == "bottom" then
            f._healthText:SetPoint("BOTTOM", f._health, "BOTTOM", htOX, 2 + htOY)
            f._healthText:SetJustifyH("CENTER"); f._healthText:SetJustifyV("BOTTOM")
        elseif htPos == "bottomright" then
            f._healthText:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", -2 + htOX, 2 + htOY)
            f._healthText:SetJustifyH("RIGHT"); f._healthText:SetJustifyV("BOTTOM")
        else
            f._healthText:SetPoint("CENTER", f._health, "CENTER", htOX, htOY)
            f._healthText:SetJustifyH("CENTER"); f._healthText:SetJustifyV("MIDDLE")
        end
        -- Force text re-render (WoW doesn't visually re-layout on JustifyH change alone)
        local htTxt = f._healthText:GetText()
        f._healthText:SetText("")
        f._healthText:SetText(htTxt or "")
        local mode = s.healthTextMode or "none"
        -- Resolve health text color (mirrors the preview name-color block above,
        -- using the preview's classToken since `unit` isn't a real unit here).
        local htMode = s.healthTextColorMode or "custom"
        local htr, htg, htb = 1, 1, 1
        if htMode == "accent" then
            local ar, ag, ab = EllesmereUI.ResolveThemeColor(EllesmereUI.GetActiveTheme())
            if ar then htr, htg, htb = ar, ag, ab end
        elseif htMode == "class" then
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then htr, htg, htb = cc.r, cc.g, cc.b end
        else -- custom
            local c = s.healthTextCustomColor
            if c then htr, htg, htb = c.r, c.g, c.b end
        end
        if mode == "percent" and not isDead and not isOffline then
            f._healthText:SetFormattedText("%d%%", healthPct)
            f._healthText:SetTextColor(htr, htg, htb, 0.9)
        elseif mode == "percentNoSign" and not isDead and not isOffline then
            f._healthText:SetFormattedText("%d", healthPct)
            f._healthText:SetTextColor(htr, htg, htb, 0.9)
        elseif mode == "number" and not isDead and not isOffline then
            local fakeHP = healthPct * 12000
            if AbbreviateNumbers then
                f._healthText:SetText(AbbreviateNumbers(fakeHP))
            end
            f._healthText:SetTextColor(htr, htg, htb, 0.9)
        elseif mode == "numberPercent" and not isDead and not isOffline then
            local fakeHP = healthPct * 12000
            local numStr = AbbreviateNumbers and AbbreviateNumbers(fakeHP) or tostring(fakeHP)
            f._healthText:SetFormattedText("%s | %d%%", numStr, healthPct)
            f._healthText:SetTextColor(htr, htg, htb, 0.9)
        elseif mode == "percentNumber" and not isDead and not isOffline then
            local fakeHP = healthPct * 12000
            local numStr = AbbreviateNumbers and AbbreviateNumbers(fakeHP) or tostring(fakeHP)
            f._healthText:SetFormattedText("%d%% | %s", healthPct, numStr)
            f._healthText:SetTextColor(htr, htg, htb, 0.9)
        else
            f._healthText:SetText("")
        end
    end

    -- Status text (DEAD / OFFLINE / AFK)
    if f._statusText then
        local pvStc = s.statusTextColor or { r = 1, g = 1, b = 1 }
        ApplyFont(f._statusText, s.statusTextSize or 14)
        f._statusText:SetTextColor(pvStc.r, pvStc.g, pvStc.b)
        f._statusText:ClearAllPoints()
        local stPos = s.statusTextPosition or "center"
        local stOX = s.statusTextOffsetX or 0
        local stOY = s.statusTextOffsetY or 0
        if stPos == "topleft" then
            f._statusText:SetPoint("TOPLEFT", f._health, "TOPLEFT", 2 + stOX, -2 + stOY)
        elseif stPos == "top" then
            f._statusText:SetPoint("TOP", f._health, "TOP", stOX, -2 + stOY)
        elseif stPos == "topright" then
            f._statusText:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", -2 + stOX, -2 + stOY)
        elseif stPos == "left" then
            f._statusText:SetPoint("LEFT", f._health, "LEFT", 2 + stOX, stOY)
        elseif stPos == "right" then
            f._statusText:SetPoint("RIGHT", f._health, "RIGHT", -2 + stOX, stOY)
        elseif stPos == "bottomleft" then
            f._statusText:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 2 + stOX, 2 + stOY)
        elseif stPos == "bottom" then
            f._statusText:SetPoint("BOTTOM", f._health, "BOTTOM", stOX, 2 + stOY)
        elseif stPos == "bottomright" then
            f._statusText:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", -2 + stOX, 2 + stOY)
        else
            f._statusText:SetPoint("CENTER", f._health, "CENTER", stOX, stOY)
        end
        if isDead then
            f._statusText:SetText("DEAD")
            f._statusText:Show()
        elseif isOffline then
            f._statusText:SetText("OFFLINE")
            f._statusText:Show()
        elseif isAfk then
            f._statusText:SetText("AFK")
            f._statusText:Show()
        else
            f._statusText:Hide()
        end
    end

    -- Dead/DC overlay
    if isDead then
        if f._health then
            f._health:SetValue(0)
            local ft = f._health:GetStatusBarTexture()
            if ft then ft:SetAlpha(0) end
        end
        -- Hide shield on dead players
        if f._absorbBar then
            f._absorbBar:Hide()
            if f._absorbBar._forward then f._absorbBar._forward:Hide() end
        end
    elseif isOffline then
        if f._health then
            f._health:SetValue(0)
            local ft = f._health:GetStatusBarTexture()
            if ft then ft:SetAlpha(0) end
        end
    end

    -- Role icon (not affected by indicators toggle)
    if f._roleIcon then
        local style = s.roleIconStyle or "modern"
        if style ~= "none" then
            local role = previewRoles[index] or "DAMAGER"
            local showForRole = (role == "TANK" and s.showRoleForTank)
                or (role == "HEALER" and s.showRoleForHealer)
                or (role == "DAMAGER" and s.showRoleForDPS)
            if showForRole ~= false and ApplyRoleIcon(f._roleIcon, role, style) then
                local riSz = PixelSnap(s.roleIconSize or 14)
                f._roleIcon:SetSize(riSz, riSz)
                f._roleIcon:ClearAllPoints()
                local pos = s.roleIconPosition or "bottomleft"
                local ox = s.roleIconOffsetX or 0
                local oy = s.roleIconOffsetY or 0
                if pos == "topright" then
                    f._roleIcon:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", ox, oy)
                elseif pos == "bottomleft" then
                    f._roleIcon:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", ox, oy)
                elseif pos == "bottomright" then
                    f._roleIcon:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", ox, oy)
                else
                    f._roleIcon:SetPoint("TOPLEFT", f._health, "TOPLEFT", ox, oy)
                end
                f._roleIcon:Show()
            else
                f._roleIcon:Hide()
            end
        else
            f._roleIcon:Hide()
        end
    end

    -- Leader icon: show on slot 1 (player = leader in preview)
    if f._leaderIcon then
        if s.showLeaderIcon and index == 1 then
            local liSz = PixelSnap(s.leaderIconSize or 14)
            f._leaderIcon:SetSize(liSz, liSz)
            f._leaderIcon:ClearAllPoints()
            local liPos = (s.leaderIconPosition or "top"):upper()
            f._leaderIcon:SetPoint(liPos, f._health, liPos, s.leaderIconOffsetX or 0, s.leaderIconOffsetY or 0)
            f._leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
            f._leaderIcon:Show()
        else
            f._leaderIcon:Hide()
        end
    end

    -- Buff manager indicators only shown on the BM page preview, not here

    -- Debuff/defensive preview icons managed by PvAuraTicker (cycling system)

    f:Show()
end

ns._previewInitialized = false

local function InitPreviewHealthValues()
    if ns._previewInitialized then return end
    ns._previewInitialized = true
    for i = 1, 20 do
        previewHealthValues[i] = 40 + math.random(60)
        previewPowerValues[i] = 50 + math.random(50)
        ns.previewAbsorbValues[i] = 0
        ns.previewHealAbsorbValues[i] = 0
    end
    -- Assign shields: at least 1 per group of 5, plus a few random extras
    for g = 0, 3 do
        -- Guaranteed 1 per group
        local slot = g * 5 + math.random(5)
        ns.previewAbsorbValues[slot] = 5 + math.random(25)
        -- 50% chance of a second in the group
        if math.random() > 0.5 then
            local slot2 = g * 5 + math.random(5)
            if ns.previewAbsorbValues[slot2] == 0 then
                ns.previewAbsorbValues[slot2] = 3 + math.random(15)
            end
        end
    end
    -- Assign heal absorbs: 2 random slots
    local haPool = {}
    for i = 2, 20 do haPool[#haPool + 1] = i end
    for i = #haPool, 2, -1 do
        local j = math.random(i)
        haPool[i], haPool[j] = haPool[j], haPool[i]
    end
    ns.previewHealAbsorbValues[haPool[1]] = 20 + math.random(20)
    ns.previewHealAbsorbValues[haPool[2]] = 20 + math.random(20)

    -- Assign heal prediction: 2 random slots (non-full-health frames)
    ns.previewHealPredValues = {}
    for i = 1, 20 do ns.previewHealPredValues[i] = 0 end
    local hpPool = {}
    for i = 1, 20 do
        if previewHealthValues[i] < 95 then hpPool[#hpPool + 1] = i end
    end
    for i = #hpPool, 2, -1 do
        local j = math.random(i)
        hpPool[i], hpPool[j] = hpPool[j], hpPool[i]
    end
    if hpPool[1] then ns.previewHealPredValues[hpPool[1]] = 10 + math.random(20) end
    if hpPool[2] then ns.previewHealPredValues[hpPool[2]] = 10 + math.random(20) end

    -- Reduced max health: 2 random slots with 10-25% health loss
    ns.previewReducedMaxHealth = {}
    for i = 1, 20 do ns.previewReducedMaxHealth[i] = 0 end
    local rmhPool = {}
    for i = 2, 20 do rmhPool[#rmhPool + 1] = i end
    for i = #rmhPool, 2, -1 do
        local j = math.random(i)
        rmhPool[i], rmhPool[j] = rmhPool[j], rmhPool[i]
    end
    ns.previewReducedMaxHealth[rmhPool[1]] = 0.10 + math.random() * 0.15
    ns.previewReducedMaxHealth[rmhPool[2]] = 0.10 + math.random() * 0.15
end

-------------------------------------------------------------------------------
--  Overlay preview container
--  A black-background frame that holds the preview when in overlay mode.
--  Position is hardcoded (see RefreshPreview) -- it is NOT draggable and
--  nothing is saved to the profile.
-------------------------------------------------------------------------------
local overlayContainer = nil

local function GetOrCreateOverlayContainer()
    if overlayContainer then return overlayContainer end

    local oc = CreateFrame("Frame", nil, UIParent)
    oc:SetFrameStrata("FULLSCREEN_DIALOG")
    oc:SetFrameLevel(10)
    oc:SetClampedToScreen(true)
    oc:Hide()

    local bg = oc:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.9)
    oc._bg = bg

    -- Centered title at the top of the preview. Font/text/color/visibility are
    -- (re)applied each refresh in RefreshPreview so it tracks the active font.
    -- SetText is deferred until after ApplyFont there (a fontstring with no font
    -- set errors on SetText), matching how the group-number labels are built.
    local title = oc:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", oc, "TOP", 0, -7)
    oc._title = title

    overlayContainer = oc
    ns._overlayContainer = oc
    return oc
end

local function RefreshPreview()
    if not previewActive then return end
    if not containerFrame then return end
    BuildPreviewRoles()

    local s = db.profile
    local groupGrowth = s.groupGrowth or "RIGHT"
    local unitGrowth  = s.unitGrowth or "DOWN"
    local bw = PixelSnap(s.frameWidth or 72)
    local bh = PixelSnap(s.frameHeight or 46)
    local cs = PixelSnap(s.cellSpacing or 2)
    local gs = PixelSnap(s.groupSpacing or 8)

    -- Group bounding box
    local groupW, groupH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        groupW = 5 * bw + 4 * cs
        groupH = bh
    else
        groupW = bw
        groupH = 5 * bh + 4 * cs
    end

    -- Group step along growth axis
    local stepX, stepY = 0, 0
    if groupGrowth == "DOWN" then
        stepY = -(groupH + gs)
    elseif groupGrowth == "UP" then
        stepY = (groupH + gs)
    elseif groupGrowth == "RIGHT" then
        stepX = (groupW + gs)
    else -- LEFT
        stepX = -(groupW + gs)
    end

    -- Raw group positions + normalize
    local rawGX, rawGY = {}, {}
    local minGX, maxGY = 0, 0
    for i = 0, 3 do
        rawGX[i] = i * stepX
        rawGY[i] = i * stepY
        if rawGX[i] < minGX then minGX = rawGX[i] end
        if rawGY[i] > maxGY then maxGY = rawGY[i] end
    end

    -- Unit step within a group
    local uStepX, uStepY = 0, 0
    if unitGrowth == "DOWN" then
        uStepY = -(bh + cs)
    elseif unitGrowth == "UP" then
        uStepY = (bh + cs)
    elseif unitGrowth == "RIGHT" then
        uStepX = (bw + cs)
    else -- LEFT
        uStepX = -(bw + cs)
    end

    -- Normalize unit positions within a group (0-indexed)
    local rawUX, rawUY = {}, {}
    local minUX, maxUY = 0, 0
    for i = 0, 4 do
        rawUX[i] = i * uStepX
        rawUY[i] = i * uStepY
        if rawUX[i] < minUX then minUX = rawUX[i] end
        if rawUY[i] > maxUY then maxUY = rawUY[i] end
    end

    -- Overlay mode: anchor to overlay container with padding
    local isOverlay = (db.profile.previewMode == "overlay") or ns._testMode
    local anchor = previewContainer or containerFrame
    local anchorPad = 0
    local topExtra = 0   -- extra top space (overlay only): 25px gap above the
                         -- group numbers, leaving room for the centered title
    if isOverlay then
        local oc = GetOrCreateOverlayContainer()
        anchor = oc
        anchorPad = 20
        topExtra = 25
    end

    -- Hide all preview frames first
    for _, f in ipairs(previewFrames) do f:Hide() end

    -- Place 20 preview frames: 4 groups x 5 units
    local frameIdx = 0
    for g = 0, 3 do
        local gx = rawGX[g] - minGX
        local gy = rawGY[g] - maxGY
        local firstFrame
        for u = 0, 4 do
            frameIdx = frameIdx + 1
            local f = GetOrCreatePreviewFrame(frameIdx)
            f:ClearAllPoints()
            local fx = gx + (rawUX[u] - minUX)
            local fy = gy + (rawUY[u] - maxUY)
            f:SetPoint("TOPLEFT", anchor, "TOPLEFT", fx + anchorPad, fy - anchorPad - topExtra)
            ApplyPreviewData(f, frameIdx)

            if f._health and previewHealthValues[frameIdx] then
                f._health:SetValue(previewHealthValues[frameIdx])
                f._healthPct = previewHealthValues[frameIdx]
            end
            if f._power and previewPowerValues[frameIdx] then
                f._power:SetValue(previewPowerValues[frameIdx])
                f._powerPct = previewPowerValues[frameIdx]
            end
            if u == 0 then firstFrame = f end
        end

        -- Group number label anchored to the first unit of each group
        local lbl = previewGroupLabels[g + 1]
        if not lbl then
            lbl = anchor:CreateFontString(nil, "OVERLAY")
            previewGroupLabels[g + 1] = lbl
        end
        ApplyFont(lbl, db.profile.groupNumberSize or 10)
        do
            -- Shared size/color with the real frames (group-number settings).
            -- Not gated by showGroupNumbers: the preview always shows numbers.
            local gc = db.profile.groupNumberColor or {}
            lbl:SetTextColor(gc.r or 1, gc.g or 1, gc.b or 1, gc.a or 0.75)
        end
        lbl:SetText(tostring(g + 1))
        lbl:ClearAllPoints()
        -- Anchor based on unit growth: label goes "before" the first unit.
        -- The X/Y offset (shared group-number setting) shifts it from there.
        local gnox = db.profile.groupNumberOffsetX or 0
        local gnoy = db.profile.groupNumberOffsetY or 0
        if unitGrowth == "DOWN" then
            lbl:SetPoint("BOTTOM", firstFrame, "TOP", gnox, 4 + gnoy)
        elseif unitGrowth == "UP" then
            lbl:SetPoint("TOP", firstFrame, "BOTTOM", gnox, -4 + gnoy)
        elseif unitGrowth == "RIGHT" then
            lbl:SetPoint("RIGHT", firstFrame, "LEFT", -3 + gnox, gnoy)
        else -- LEFT
            lbl:SetPoint("LEFT", firstFrame, "RIGHT", 3 + gnox, gnoy)
        end
        lbl:Show()
    end

    -- Reparent after all frames are created (first load creates them in the loop above)
    local reparentTo = isOverlay and overlayContainer or (previewContainer or containerFrame)
    for _, f in ipairs(previewFrames) do f:SetParent(reparentTo) end
    for _, lbl in ipairs(previewGroupLabels) do lbl:SetParent(reparentTo) end

    -- Container size (4 groups)
    local totalW, totalH
    if groupGrowth == "DOWN" or groupGrowth == "UP" then
        totalW = groupW
        totalH = MOVER_GROUPS * groupH + (MOVER_GROUPS - 1) * gs
    else
        totalW = MOVER_GROUPS * groupW + (MOVER_GROUPS - 1) * gs
        totalH = groupH
    end
    local snapW = PixelSnap(max(totalW, 1))
    local snapH = PixelSnap(max(totalH, 1))
    if previewContainer then
        previewContainer:SetSize(snapW, snapH)
        -- Snap TOPLEFT to pixel grid (same fix as containerFrame in LayoutGroups)
        local l = previewContainer:GetLeft()
        local t = previewContainer:GetTop()
        if l and t then
            local snappedL = PixelSnap(l)
            local snappedT = PixelSnap(t)
            if abs(l - snappedL) > 0.01 or abs(t - snappedT) > 0.01 then
                previewContainer:ClearAllPoints()
                previewContainer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", snappedL, snappedT)
            end
        end
    end

    -- Size and position overlay container
    if isOverlay and overlayContainer then
        overlayContainer:SetSize(totalW + anchorPad * 2, totalH + anchorPad * 2 + topExtra)
        if overlayContainer._title then
            ApplyFont(overlayContainer._title, 13)
            overlayContainer._title:SetText("Overlay Preview")
            overlayContainer._title:SetTextColor(1, 1, 1, 0.9)
            overlayContainer._title:Show()
        end
        if ns._testMode then
            -- Test mode: center on screen, above dimmer
            overlayContainer:SetFrameStrata("FULLSCREEN_DIALOG")
            overlayContainer:SetFrameLevel(55)
            overlayContainer:ClearAllPoints()
            overlayContainer:SetPoint("CENTER", UIParent, "CENTER", 80, 0)
        else
            overlayContainer:SetFrameStrata("FULLSCREEN_DIALOG")
            overlayContainer:SetFrameLevel(10)
            overlayContainer:ClearAllPoints()
            -- Hardcoded default position (not draggable, not saved): docked to
            -- the left edge of the options panel, screen center as a fallback.
            local sf = EllesmereUI._scrollFrame
            if sf then
                overlayContainer:SetPoint("BOTTOMRIGHT", sf, "BOTTOMLEFT", 0, 0)
            else
                overlayContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
        overlayContainer:Show()
    end
end

-- Mouse-blocking overlays + alpha-based real-frame hide for the options preview.
-- Wrapped in a do-block and exposed via ns so these helpers add NO persistent
-- main-chunk locals (this file sits at Lua 5.1's 200-local cap); rfMouseBlock /
-- partyMouseBlock survive as the closures' upvalues.
--
-- The overlays are OUR own non-secure frames, so EnableMouse on them is
-- taint-free and Hide() on them is combat-legal (no secure children) -- they are
-- torn down the instant combat starts, so they can never trap a healer's clicks
-- during a pull. They track the real containers directly (alpha-0 but still
-- correctly sized/positioned), covering the real, now-invisible unit buttons in
-- both preview and size preview.
--
-- The real containers are hidden via ALPHA (not protected) instead of
-- reparenting: they stay parented to UIParent at their saved position, so the
-- SetAlpha(1) restore is always legal and can never be deferred by combat -- the
-- root cause of "no party frames for the whole first pull" was the old hide
-- reparenting these secure-header containers (reparenting back is combat-blocked).
-- Preview frames are reparented to previewContainer/overlayContainer/partyOC/
-- UIParent by RefreshPreview/RefreshPartyPreview before display, so container
-- alpha 0 never hides the preview itself.
do
    local rfMouseBlock, partyMouseBlock
    local function setBlock(on)
        if on then
            if containerFrame then
                if not rfMouseBlock then
                    rfMouseBlock = CreateFrame("Frame", nil, UIParent)
                    rfMouseBlock:SetFrameStrata("MEDIUM")  -- above real buttons (LOW), below the options panel (DIALOG)
                    rfMouseBlock:EnableMouse(true)
                end
                rfMouseBlock:SetAllPoints(containerFrame)
                rfMouseBlock:Show()
            end
            if ns._partyContainerFrame then
                if not partyMouseBlock then
                    partyMouseBlock = CreateFrame("Frame", nil, UIParent)
                    partyMouseBlock:SetFrameStrata("MEDIUM")
                    partyMouseBlock:EnableMouse(true)
                end
                partyMouseBlock:SetAllPoints(ns._partyContainerFrame)
                partyMouseBlock:Show()
            end
        else
            if rfMouseBlock then rfMouseBlock:Hide() end
            if partyMouseBlock then partyMouseBlock:Hide() end
        end
    end
    ns._SetPreviewMouseBlock = setBlock
    function ns._SetRealFramesPreviewHidden(on)
        local a = on and 0 or 1
        if containerFrame then containerFrame:SetAlpha(a) end
        if ns._partyContainerFrame then ns._partyContainerFrame:SetAlpha(a) end
        setBlock(on)
    end
end

local function ShowPreview()
    -- Never engage the preview unless the options window is actually open (or
    -- test mode is active). A deferred C_Timer ShowPreview firing after the
    -- panel closed (combat auto-close, rapid close) would reparent the real
    -- containers under the hidden preview parent with nothing left to restore
    -- them -- the root cause of "frames vanish after closing options".
    -- Reparenting secure-header containers is also blocked/taint-prone in
    -- combat, so bail there too.
    if not ns._testMode and not (EllesmereUI.IsShown and EllesmereUI:IsShown()) then return end
    if InCombatLockdown() then return end
    -- Kill any active size preview
    if ns._sizePreviewTier then
        ns._sizePreviewTier = nil
        if ns._HideSizePreview then ns._HideSizePreview() end
    end
    if previewActive then
        RefreshPreview()
        return
    end
    if not containerFrame then return end
    previewActive = true

    -- Preview container
    if not previewContainer then
        previewContainer = CreateFrame("Frame", nil, UIParent)
        previewContainer:SetFrameStrata("LOW")
    end
    local pos = db.profile.unlockPos
    previewContainer:ClearAllPoints()
    if pos then
        previewContainer:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        previewContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    previewContainer:SetSize(containerFrame:GetSize())
    previewContainer:Show()

    -- Hide the real containers for preview via alpha (combat-reversible) instead
    -- of reparenting. SetAlpha is not protected, so the restore can never be
    -- blocked or deferred by combat. The containers stay parented to UIParent at
    -- their saved position; preview frames are reparented out of the containers
    -- by RefreshPreview below, so container alpha 0 does not hide the preview.
    ns._SetRealFramesPreviewHidden(true)

    -- Initialize health values and role assignments
    InitPreviewHealthValues()
    BuildPreviewRoles()

    RefreshPreview()
    StartPvAuraTicker()
end

-- skipRestore: leave the real frames parented to the hidden frame instead of
-- restoring them. Used on tab swaps into the party tab, where ShowPartyPreview
-- re-hides them on the next frame -- restoring here would flash the real frames
-- for one frame first. Panel close restores explicitly.
local function HidePreview(skipRestore)
    if not previewActive then return end
    previewActive = false
    ns._previewInitialized = false
    previewRoles._randomized = nil  -- re-randomize on next preview open
    StopPvAuraTicker()
    ns.StopPvBuffTicker()
    -- Hide overlay container
    if overlayContainer then overlayContainer:Hide() end
    -- Hide preview container
    if previewContainer then previewContainer:Hide() end
    -- Reparent preview frames back to containerFrame
    for _, f in ipairs(previewFrames) do
        f:SetParent(containerFrame)
        f:Hide()
    end
    for _, lbl in ipairs(previewGroupLabels) do
        lbl:SetParent(containerFrame)
        lbl:Hide()
    end
    if skipRestore then return end
    -- The containers were only alpha-hidden (never reparented or moved), so the
    -- restore is a combat-legal SetAlpha(1) plus dropping the mouse blockers. No
    -- combat gate, no SetParent/SetPoint, no ns._restorePending deferral.
    ns._SetRealFramesPreviewHidden(false)
    -- Re-run layout out of combat in case frame sizes changed while previewing
    -- (LayoutGroups SetPoints secure headers, so out of combat only).
    if not InCombatLockdown() then LayoutGroups() end
    UpdateVisibility()
    if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
end

local function ApplyPreviewMode()
    local mode = db.profile.previewMode or "overlay"

    if mode == "none" then
        if previewActive then HidePreview() end
        return
    end
    if not previewActive then
        ShowPreview()
        return
    end
    local isOverlay = (mode == "overlay")
    if not isOverlay and overlayContainer then
        overlayContainer:Hide()
    end
    -- RefreshPreview handles reparenting, anchoring, and overlay sizing
    RefreshPreview()
end

ns.ApplyPreviewMode = ApplyPreviewMode

-- Expose for options panel
ns.ShowPreview = ShowPreview
ns.HidePreview = HidePreview
ns.previewActive = function() return previewActive end
ns.ResetPreviewRandomization = function() previewRoles._randomized = nil end
ns.GetFFD = GetFFD
ns.previewFrames = previewFrames
ns.previewHealthValues = previewHealthValues
ns.previewPowerValues = previewPowerValues

-- Active-preview accessors for the options eyeballs (resolve raid vs party at
-- call time so the health/power animations drive whichever preview is on screen).
ns.PvActiveFrames = PvFrames
ns.PvHealthValues = function() return (ns._partyPvActive and ns._partyPvHV) or previewHealthValues end
ns.PvPowerValues  = function() return (ns._partyPvActive and ns._partyPvPV) or previewPowerValues end
-- Re-render whichever preview is active (mirrors ShowPreview's refresh-if-active).
-- Uses the ns.* exports because ShowPartyPreview is declared later in the file.
ns.PvRefresh = function()
    if ns._partyPvActive then
        if ns.ShowPartyPreview then ns.ShowPartyPreview() end
    elseif ns.ShowPreview then
        ns.ShowPreview()
    end
end

-------------------------------------------------------------------------------
--  Size preview (simple: just health + power bars at the tier's dimensions)
--  Shows the correct number of frames for the tier (10/15/25/30).
--  Respects "real" vs "overlay" preview mode. No indicators, no randomization.
-------------------------------------------------------------------------------
ns._sizePreviewTier = nil
ns._sizePreviewFrames = {}
ns._sizePreviewContainer = nil

ns._ShowSizePreview = function(tier)
    -- Preview only ever runs out of combat. A mid-combat alpha-0 here could not
    -- be undone by the PLAYER_REGEN_DISABLED safety net (it already fired at
    -- combat start), and would strand the real frames invisible for the rest of
    -- the pull -- the same game-breaking outcome the alpha rework prevents.
    if InCombatLockdown() then return end
    local s = db.profile
    local overrides = s.raidSizeOverrides
    if not overrides or not overrides[tier] then return end

    -- Hide any active previews (both real and overlay mode)
    if previewActive then
        HidePreview()  -- cleans up real-mode preview frames
    end
    if ns._partyPvActive then
        HidePartyPreview()
    end
    -- Hide real raid + party frames during size preview via alpha so a combat
    -- start can re-show them (Hide/Show are protected and cannot be undone in
    -- combat; SetAlpha is not). The size-preview frames live in their own
    -- UIParent child (ns._sizePreviewContainer), so container alpha does not
    -- affect them. The mouse blocker keeps the now-invisible real unit buttons
    -- from catching clicks while configuring out of combat.
    if containerFrame then containerFrame:SetAlpha(0) end
    if ns._partyContainerFrame then ns._partyContainerFrame:SetAlpha(0) end
    ns._SetPreviewMouseBlock(true)

    local ov = overrides[tier]
    local bw = PixelSnap(ov.width or s.frameWidth or 125)
    local bh = PixelSnap(ov.height or s.frameHeight or 60)
    local cs = PixelSnap(s.cellSpacing or 2)
    local gs = PixelSnap(s.groupSpacing or 8)
    local unitGrowth  = ov.unitGrowth or s.unitGrowth or "DOWN"
    local groupGrowth = ov.groupGrowth or s.groupGrowth or "RIGHT"
    local frameCount  = tier
    local perGroup    = 5
    local numGroups   = math.ceil(frameCount / perGroup)

    local texPath = ResolveHealthTexture()
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - powerH)

    -- Group bounding box (same logic as LayoutGroups)
    local groupW, groupH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        groupW = perGroup * bw + (perGroup - 1) * cs
        groupH = bh
    else
        groupW = bw
        groupH = perGroup * bh + (perGroup - 1) * cs
    end

    -- Step between groups along groupGrowth axis
    local stepX, stepY = 0, 0
    if groupGrowth == "DOWN" then       stepY = -(groupH + gs)
    elseif groupGrowth == "UP" then     stepY = (groupH + gs)
    elseif groupGrowth == "RIGHT" then  stepX = (groupW + gs)
    else                                stepX = -(groupW + gs)
    end

    -- Unit step within a group along unitGrowth axis
    local uStepX, uStepY = 0, 0
    if unitGrowth == "DOWN" then        uStepY = -(bh + cs)
    elseif unitGrowth == "UP" then      uStepY = (bh + cs)
    elseif unitGrowth == "RIGHT" then   uStepX = (bw + cs)
    else                                uStepX = -(bw + cs)
    end

    -- Normalize unit positions within a group (matches RefreshPreview pattern)
    local minUX, maxUY = 0, 0
    for u = 0, perGroup - 1 do
        local px = u * uStepX
        local py = u * uStepY
        if px < minUX then minUX = px end
        if py > maxUY then maxUY = py end
    end

    -- Total bounding box (always 4 groups, matching real LayoutGroups container)
    local MOVER_GROUPS = 4
    local totalW = math.abs(stepX) > 0 and (MOVER_GROUPS * groupW + (MOVER_GROUPS - 1) * gs) or groupW
    local totalH = math.abs(stepY) > 0 and (MOVER_GROUPS * groupH + (MOVER_GROUPS - 1) * gs) or groupH

    -- Tier offset
    local tierOX = ov.offsetX or 0
    local tierOY = ov.offsetY or 0

    -- Create or reuse container
    local mode = s.previewMode or "overlay"
    local container = ns._sizePreviewContainer
    if not container then
        container = CreateFrame("Frame", nil, UIParent)
        container:SetFrameStrata("FULLSCREEN_DIALOG")
        container:SetFrameLevel(10)
        container:SetClampedToScreen(true)
        ns._sizePreviewContainer = container
    end

    -- Always use real positioning (where frames actually sit)
    local pad = 0
    container:SetSize(totalW, totalH)
    if container._bg then container._bg:Hide() end
    container:SetFrameStrata("LOW")
    container:ClearAllPoints()
    local unlockPos = s.unlockPos
    if unlockPos then
        container:SetPoint(unlockPos.point, UIParent, unlockPos.relPoint,
            unlockPos.x + tierOX, unlockPos.y + tierOY)
    else
        container:SetPoint("CENTER", UIParent, "CENTER", tierOX, tierOY)
    end

    -- Build role/class assignments: 2 tanks, scaled healers, rest DPS
    local TANK_CLS   = ns._PV_TANK_CLASSES or { "WARRIOR", "PALADIN", "DEATHKNIGHT" }
    local HEALER_CLS = ns._PV_HEALER_CLASSES or { "PRIEST", "PALADIN", "SHAMAN", "MONK", "DRUID", "EVOKER" }
    local DPS_CLS    = ns._PV_DPS_CLASSES or ns._PV_CLASS_TOKENS
    local NAMES      = ns._PV_NAMES or { "Player" }
    local CLASS_PWR  = ns._PV_CLASS_POWER or {}

    local nTanks = 2
    local nHealers = math.max(2, math.floor(frameCount / 5))
    local nDPS = frameCount - nTanks - nHealers

    local spRoles = {}
    local spClasses = {}
    local ti, hi, di = 1, 1, 1
    for i = 1, frameCount do
        if i <= nTanks then
            spRoles[i] = "TANK"
            spClasses[i] = TANK_CLS[ti]; ti = (ti % #TANK_CLS) + 1
        elseif i <= nTanks + nHealers then
            spRoles[i] = "HEALER"
            spClasses[i] = HEALER_CLS[hi]; hi = (hi % #HEALER_CLS) + 1
        else
            spRoles[i] = "DAMAGER"
            spClasses[i] = DPS_CLS[di]; di = (di % #DPS_CLS) + 1
        end
    end

    -- Power color lookup by token
    local PWR_COLORS = PowerBarColor or {}
    local function GetPowerColorByToken(pToken)
        if EllesmereUI.GetPowerColor then
            local info = EllesmereUI.GetPowerColor(pToken)
            if info then return info.r, info.g, info.b end
        end
        local pEnum = Enum and Enum.PowerType and Enum.PowerType[pToken]
        if pEnum and PWR_COLORS[pEnum] then
            local c = PWR_COLORS[pEnum]
            return c.r, c.g, c.b
        end
        return 0, 0.5, 1
    end

    -- Font for names
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
    local nameSize = s.nameSize or 10

    -- Normalize origin over MOVER_GROUPS (matching real LayoutGroups container)
    local minX, maxY = 0, 0
    for g = 0, MOVER_GROUPS - 1 do
        local gx = g * stepX
        local gy = g * stepY
        if gx < minX then minX = gx end
        if gy > maxY then maxY = gy end
    end

    -- Role icon settings
    local riStyle = s.roleIconStyle or "modern"
    local riSize = PixelSnap(s.roleIconSize or 14)
    local riPos = s.roleIconPosition or "bottomleft"
    local showRoleTank = s.showRoleForTank
    local showRoleHealer = s.showRoleForHealer
    local showRoleDPS = s.showRoleForDPS

    for i = 1, frameCount do
        local f = ns._sizePreviewFrames[i]
        if not f then
            f = CreateFrame("Frame", nil, container)
            local health = CreateFrame("StatusBar", nil, f)
            health:SetPoint("TOPLEFT")
            health:SetPoint("TOPRIGHT")
            health:SetMinMaxValues(0, 100)
            health:SetValue(100)
            if PP then PP.DisablePixelSnap(health) end
            f._health = health

            local bg = f:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if PP then PP.DisablePixelSnap(bg) end
            f._bg = bg

            local power = CreateFrame("StatusBar", nil, f)
            power:SetPoint("BOTTOMLEFT")
            power:SetPoint("BOTTOMRIGHT")
            power:SetMinMaxValues(0, 1)
            power:SetValue(1)
            if PP then PP.DisablePixelSnap(power) end
            f._power = power

            local bdr = CreateFrame("Frame", nil, f)
            bdr:SetAllPoints()
            bdr:SetFrameLevel(f:GetFrameLevel() + 2)
            if PP then PP.CreateBorder(bdr, 0, 0, 0, 1, 1) end
            f._border = bdr

            -- Name text
            local nameFS = health:CreateFontString(nil, "OVERLAY")
            nameFS:SetJustifyH("CENTER")
            nameFS:SetWordWrap(false)
            f._nameText = nameFS

            -- Role icon
            local roleIcon = health:CreateTexture(nil, "OVERLAY")
            roleIcon:Hide()
            f._roleIcon = roleIcon

            ns._sizePreviewFrames[i] = f
        end

        f:SetParent(container)
        f:SetSize(bw, bh)
        f._health:SetHeight(healthH)
        f._health:SetStatusBarTexture(texPath)
        f._health:GetStatusBarTexture():SetHorizTile(false)
        f._health:SetValue(100)

        -- Class color
        local ct = spClasses[i]
        local cc = EllesmereUI.GetClassColor(ct)
        if cc then f._health:SetStatusBarColor(cc.r, cc.g, cc.b) end

        -- Background
        local bgc = s.customBgColor or { r = 17/255, g = 17/255, b = 17/255 }
        f._bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)

        -- Power bar with class-accurate color
        if f._power then
            local role = spRoles[i]
            local showForRole = (role == "HEALER" and s.powerShowForHealer)
                or (role == "TANK" and s.powerShowForTank)
                or (role == "DAMAGER" and s.powerShowForDPS)
            if powerH > 0 and showForRole then
                f._power:SetHeight(powerH)
                f._power:SetStatusBarTexture(texPath)
                f._power:GetStatusBarTexture():SetHorizTile(false)
                local pwToken = CLASS_PWR[ct] or "MANA"
                local pr, pg, pb = GetPowerColorByToken(pwToken)
                f._power:SetStatusBarColor(pr, pg, pb)
                f._power:Show()
                -- Adjust health height for power bar
                f._health:SetHeight(healthH)
            else
                f._power:Hide()
                -- Expand health to full frame height
                f._health:SetHeight(bh)
            end
        end

        -- Name text
        if f._nameText then
            local name = NAMES[((i - 1) % #NAMES) + 1]
            f._nameText:SetFont(fontPath, nameSize, GetOutline())
            if GetOutline() == "" and GetUseShadow() then
                f._nameText:SetShadowOffset(1, -1)
                f._nameText:SetShadowColor(0, 0, 0, 1)
            else
                f._nameText:SetShadowOffset(0, 0)
            end
            f._nameText:SetText(name)
            f._nameText:SetWidth(bw * 0.75)
            -- Name color
            if cc then
                f._nameText:SetTextColor(cc.r, cc.g, cc.b)
            else
                f._nameText:SetTextColor(1, 1, 1)
            end
            f._nameText:ClearAllPoints()
            f._nameText:SetPoint("CENTER", f._health, "CENTER", 0, 0)
            f._nameText:Show()
        end

        -- Role icon
        if f._roleIcon then
            local role = spRoles[i]
            local showForRole = (role == "TANK" and showRoleTank)
                or (role == "HEALER" and showRoleHealer)
                or (role == "DAMAGER" and showRoleDPS)
            if riStyle ~= "none" and showForRole and ApplyRoleIcon(f._roleIcon, role, riStyle) then
                f._roleIcon:SetSize(riSize, riSize)
                f._roleIcon:ClearAllPoints()
                f._roleIcon:SetPoint(riPos:upper(), f._health, riPos:upper(), 0, 0)
                f._roleIcon:Show()
            else
                f._roleIcon:Hide()
            end
        end

        -- Border (style/size/texture/offsets via ApplyBorderStyle)
        if f._border and PP then
            local bs = s.borderSize or 1
            local bc = s.borderColor or { r = 0, g = 0, b = 0 }
            local pl = f:GetFrameLevel()
            f._border:SetFrameLevel(s.borderBehind and math.max(0, pl - 1) or (pl + 2))
            EllesmereUI.ApplyBorderStyle(f._border, bs, bc.r, bc.g, bc.b, s.borderAlpha or 1,
                s.borderTexture or "solid", s.borderTextureOffset, s.borderTextureOffsetY,
                s.borderTextureShiftX, s.borderTextureShiftY, "unitframes", bs)
        end

        -- Position: group index + unit index within group
        local groupIdx = math.ceil(i / perGroup) - 1
        local unitIdx  = (i - 1) % perGroup

        -- Group origin (TOPLEFT-relative, adjusted for growth direction)
        local gx = groupIdx * stepX - minX
        local gy = groupIdx * stepY - maxY

        -- Unit offset within group (TOPLEFT-normalized, matching RefreshPreview)
        local ux = unitIdx * uStepX - minUX
        local uy = unitIdx * uStepY - maxUY

        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", container, "TOPLEFT", pad + gx + ux, -pad + gy + uy)
        f:Show()
    end

    -- Hide excess frames
    for i = frameCount + 1, #ns._sizePreviewFrames do
        ns._sizePreviewFrames[i]:Hide()
    end

    container:Show()
end

ns._HideSizePreview = function()
    if ns._sizePreviewContainer then
        ns._sizePreviewContainer:Hide()
    end
    for _, f in ipairs(ns._sizePreviewFrames) do
        f:Hide()
    end
    -- Restore real frame opacity (size preview only changed alpha, never the
    -- Shown state) and drop the mouse blocker. SetAlpha(1) is always legal, in
    -- or out of combat, so the frames can never be stranded invisible.
    if containerFrame then containerFrame:SetAlpha(1) end
    if ns._partyContainerFrame then ns._partyContainerFrame:SetAlpha(1) end
    ns._SetPreviewMouseBlock(false)
    -- Recompute party visibility (only shows party frames if actually grouped /
    -- Show When Solo). Bails in combat; the alpha restore above suffices there.
    if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
end

-------------------------------------------------------------------------------
--  Party preview (5-player, 1 group)
--  Fully separate from raid preview -- shares CreatePreviewFrame and
--  ApplyPreviewData via temp-swap pattern but has its own frame pool,
--  health values, role assignments, layout, and overlay container.
-------------------------------------------------------------------------------
ns._partyPvFrames    = {}
ns._partyPvHV        = {}
ns._partyPvPV        = {}
ns._partyPvActive    = false
ns._partyPvInit      = false
ns.partyPvAbsorbValues     = {}
ns.partyPvHealAbsorbValues = {}
ns.partyPvHealPredValues   = {}
ns.partyPvReducedMaxHealth = {}
ns._partyPvRoles     = {}
ns._partyPvCT        = {}

local function BuildPartyPreviewRoles()
    for i = 1, 5 do ns._partyPvRoles[i] = nil end
    wipe(ns._partyPvCT)

    local playerRole = UnitGroupRolesAssigned("player")
    if playerRole ~= "TANK" and playerRole ~= "HEALER" then
        local specIdx = GetSpecialization()
        local specRole = specIdx and select(5, GetSpecializationInfo(specIdx))
        if specRole == "TANK" or specRole == "HEALER" then
            playerRole = specRole
        else
            playerRole = "DAMAGER"
        end
    end

    -- Slot 1 = player
    ns._partyPvRoles[1] = playerRole
    local _, pct = UnitClass("player")
    ns._partyPvCT[1] = pct or "WARRIOR"
    ns._partyPvRoles._playerSlot = 1

    -- Fill remaining: 1 tank, 1 healer, 3 DPS total
    local needTank   = (playerRole ~= "TANK")   and 1 or 0
    local needHealer = (playerRole ~= "HEALER") and 1 or 0
    local tankIdx, healerIdx, dpsIdx = 1, 1, 1

    for i = 2, 5 do
        if needTank > 0 then
            ns._partyPvRoles[i] = "TANK"
            ns._partyPvCT[i] = ns._PV_TANK_CLASSES[tankIdx]
            tankIdx = (tankIdx % #ns._PV_TANK_CLASSES) + 1
            needTank = needTank - 1
        elseif needHealer > 0 then
            ns._partyPvRoles[i] = "HEALER"
            ns._partyPvCT[i] = ns._PV_HEALER_CLASSES[healerIdx]
            healerIdx = (healerIdx % #ns._PV_HEALER_CLASSES) + 1
            needHealer = needHealer - 1
        else
            ns._partyPvRoles[i] = "DAMAGER"
            ns._partyPvCT[i] = ns._PV_DPS_CLASSES[dpsIdx]
            dpsIdx = (dpsIdx % #ns._PV_DPS_CLASSES) + 1
        end
    end

    -- Sort by role order + self-first (reads party-specific settings)
    local sortMode = db.profile.partySortMode or db.profile.sortMode or "INDEX"
    local showSelfFirst = db.profile.partyShowSelfFirst
    if showSelfFirst == nil then showSelfFirst = db.profile.showSelfFirst end
    local selfLast = db.profile.partySelfLast
    if selfLast == nil then selfLast = db.profile.showSelfLast end
    if selfLast then showSelfFirst = true end  -- self ordering active either way
    if sortMode == "ROLE" or showSelfFirst then
        local group = {}
        for u = 1, 5 do
            group[u] = {
                role = ns._partyPvRoles[u],
                classToken = ns._partyPvCT[u],
                isPlayer = (u == 1),
            }
        end
        if sortMode == "ROLE" then
            local roleOrder = db.profile.partyRoleOrder or db.profile.roleOrder or { "TANK", "HEALER", "DAMAGER" }
            local tmpGroup = {}
            for _, role in ipairs(roleOrder) do
                for _, entry in ipairs(group) do
                    if entry.role == role then tmpGroup[#tmpGroup + 1] = entry end
                end
            end
            for _, entry in ipairs(group) do
                local found = false
                for _, t in ipairs(tmpGroup) do if t == entry then found = true; break end end
                if not found then tmpGroup[#tmpGroup + 1] = entry end
            end
            group = tmpGroup
        end
        if showSelfFirst then
            local playerPos
            for i, entry in ipairs(group) do
                if entry.isPlayer then playerPos = i; break end
            end
            if playerPos then
                if selfLast and playerPos < #group then
                    local playerEntry = table.remove(group, playerPos)
                    group[#group + 1] = playerEntry
                elseif not selfLast and playerPos > 1 then
                    local playerEntry = table.remove(group, playerPos)
                    tinsert(group, 1, playerEntry)
                end
            end
        end
        for u = 1, 5 do
            ns._partyPvRoles[u] = group[u].role
            ns._partyPvCT[u] = group[u].classToken
            if group[u].isPlayer then ns._partyPvRoles._playerSlot = u end
        end
    end

    -- Random picks (only once per session)
    if not ns._partyPvRoles._randomized then
        ns._partyPvRoles._randomized = true
        local tanks = {}
        for i = 1, 5 do
            if ns._partyPvRoles[i] == "TANK" then tanks[#tanks + 1] = i end
        end
        ns._partyPvRoles._threatIndex = tanks[math.random(#tanks)] or 1
        -- Marker on the player (slot 1) so each of the four status indicators
        -- gets its own non-player frame (clean 1-per-frame showcase, no overlap).
        ns._partyPvRoles._markerSlot1 = 1
        ns._partyPvRoles._markerSlot2 = nil  -- only 1 marker in 5-man
        local dispelTypes = { "Magic", "Curse", "Disease", "Poison", "" }
        ns._partyPvRoles._dispelMap = {}
        for i, dt in ipairs(dispelTypes) do ns._partyPvRoles._dispelMap[i] = dt end
        -- Status showcase: 1 dead, 1 offline, 1 AFK, 1 summon-accepted, one each
        -- on the four non-player slots (2-5). No ready-check ticks.
        local statusSlots = { 2, 3, 4, 5 }
        for i = #statusSlots, 2, -1 do
            local j = math.random(i)
            statusSlots[i], statusSlots[j] = statusSlots[j], statusSlots[i]
        end
        ns._partyPvRoles._deadSlot    = statusSlots[1]
        ns._partyPvRoles._offlineSlot = statusSlots[2]
        ns._partyPvRoles._afkSlot     = statusSlots[3]
        ns._partyPvRoles._readyCheck  = { [statusSlots[4]] = "summon_accepted" }
    end
end

local function InitPartyPreviewHealthValues()
    if ns._partyPvInit then return end
    ns._partyPvInit = true
    for i = 1, 5 do
        ns._partyPvHV[i] = 40 + math.random(60)
        ns._partyPvPV[i] = 50 + math.random(50)
        ns.partyPvAbsorbValues[i] = 0
        ns.partyPvHealAbsorbValues[i] = 0
    end
    -- 1-2 shields
    local slot1 = math.random(5)
    ns.partyPvAbsorbValues[slot1] = 5 + math.random(25)
    if math.random() > 0.5 then
        local slot2 = math.random(5)
        if ns.partyPvAbsorbValues[slot2] == 0 then
            ns.partyPvAbsorbValues[slot2] = 3 + math.random(15)
        end
    end
    -- 1 heal absorb
    local haSlot = math.random(2, 5)
    ns.partyPvHealAbsorbValues[haSlot] = 20 + math.random(20)
    -- 1 heal prediction
    ns.partyPvHealPredValues = {}
    for i = 1, 5 do ns.partyPvHealPredValues[i] = 0 end
    for i = 1, 5 do
        if ns._partyPvHV[i] < 90 then
            ns.partyPvHealPredValues[i] = 10 + math.random(20)
            break
        end
    end
    -- 1 reduced max health
    ns.partyPvReducedMaxHealth = {}
    for i = 1, 5 do ns.partyPvReducedMaxHealth[i] = 0 end
    local rmhSlot = math.random(2, 5)
    ns.partyPvReducedMaxHealth[rmhSlot] = 0.10 + math.random() * 0.15
end

local function GetOrCreatePartyPvFrame(index)
    if ns._partyPvFrames[index] then return ns._partyPvFrames[index] end
    local f = CreatePreviewFrame(index)
    -- Reparent from raid preview container to party overlay container
    if ns._partyOC then f:SetParent(ns._partyOC) end
    ns._partyPvFrames[index] = f
    return f
end

-- Apply preview data with party-specific width/height override
local function ApplyPartyPreviewData(f, index)
    local s = db.profile
    -- Use party proxy so ApplyPreviewData reads party-specific settings
    ns._previewSettingsOverride = ns._scaledPartyProxy

    local origW, origH = s.frameWidth, s.frameHeight
    s.frameWidth  = s.partyFrameWidth  or s.frameWidth
    s.frameHeight = s.partyFrameHeight or s.frameHeight

    -- Temporarily swap preview value tables so ApplyPreviewData reads party data
    local origHealth = previewHealthValues
    local origPower  = previewPowerValues
    local origAbsorb = ns.previewAbsorbValues
    local origHA     = ns.previewHealAbsorbValues
    local origHP     = ns.previewHealPredValues
    local origRMH    = ns.previewReducedMaxHealth
    local origRoles  = previewRoles
    local origCT     = previewClassTokens

    for i = 1, 5 do
        previewHealthValues[i] = ns._partyPvHV[i]
        previewPowerValues[i]  = ns._partyPvPV[i]
    end
    ns.previewAbsorbValues     = ns.partyPvAbsorbValues
    ns.previewHealAbsorbValues = ns.partyPvHealAbsorbValues
    ns.previewHealPredValues   = ns.partyPvHealPredValues
    ns.previewReducedMaxHealth = ns.partyPvReducedMaxHealth
    previewRoles       = ns._partyPvRoles
    previewClassTokens = ns._partyPvCT

    ApplyPreviewData(f, index)

    -- Re-apply BM indicators with the party proxy so Auto Resize scales the
    -- preview indicators/auras live. CreatePreviewFrame applies them only once
    -- (at creation, with the raid proxy), so without this the party preview
    -- would never reflect the party scale. Index 1 matches the creation call.
    if f._bmIconPool and ns.BM_ApplyPreviewIndicators then
        ns.BM_ApplyPreviewIndicators(f, 1, ns._scaledPartyProxy)
    end

    -- Restore everything
    ns._previewSettingsOverride = nil
    s.frameWidth  = origW
    s.frameHeight = origH
    for i = 1, 5 do
        previewHealthValues[i] = origHealth[i]
        previewPowerValues[i]  = origPower[i]
    end
    ns.previewAbsorbValues     = origAbsorb
    ns.previewHealAbsorbValues = origHA
    ns.previewHealPredValues   = origHP
    ns.previewReducedMaxHealth = origRMH
    previewRoles       = origRoles
    previewClassTokens = origCT
end

-- Party overlay container (separate from raid overlay). Position is hardcoded
-- (see RefreshPartyPreview) -- not draggable, nothing saved to the profile.
ns._partyOC = nil

local function GetOrCreatePartyOverlayContainer()
    if ns._partyOC then return ns._partyOC end

    local oc = CreateFrame("Frame", nil, UIParent)
    oc:SetFrameStrata("FULLSCREEN_DIALOG")
    oc:SetFrameLevel(10)
    oc:SetClampedToScreen(true)
    oc:Hide()

    local bg = oc:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.9)
    oc._bg = bg

    -- Centered title at the top of the preview. Font/text/color/visibility are
    -- (re)applied each refresh in RefreshPartyPreview after ApplyFont (a
    -- fontstring with no font set errors on SetText).
    local title = oc:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", oc, "TOP", 0, -7)
    oc._title = title

    ns._partyOC = oc
    return oc
end

local function RefreshPartyPreview()
    if not ns._partyPvActive then return end
    -- Recompute party indicator/aura scale before applying preview data so the
    -- party preview reflects Auto Resize live (preview reads _scaledPartyProxy).
    if ns._UpdatePartyIndicatorScale then ns._UpdatePartyIndicatorScale() end
    local s = db.profile
    local w = PixelSnap(s.partyFrameWidth or s.frameWidth or 125)
    local h = PixelSnap(s.partyFrameHeight or s.frameHeight or 60)
    local spacing = PixelSnap(s.partyCellSpacing or s.cellSpacing or 2)
    local mode = s.previewMode or "overlay"

    BuildPartyPreviewRoles()

    -- "Hide Self": mirror the real party frames (showPlayer=false) by hiding the
    -- player's preview frame and reflowing the remaining members to fill the gap.
    -- The player's slot is whatever BuildPartyPreviewRoles resolved it to after
    -- Sort By + Self First/Last (NOT assumed to be slot 1).
    local hideSelf = s.partyHideSelf
    local playerSlot = ns._partyPvRoles._playerSlot or 1
    local shownCount = hideSelf and 4 or 5

    local isOverlay = (mode == "overlay")
    local anchorPad = isOverlay and 10 or 0
    local topExtra = isOverlay and 25 or 0   -- top space for the centered "Preview" title
    local unitGrowth = s.partyHorizontal and "RIGHT" or "DOWN"
    local isVert = (unitGrowth == "DOWN" or unitGrowth == "UP")
    local totalW, totalH
    if isVert then
        totalW = w
        totalH = h * shownCount + spacing * (shownCount - 1)
    else
        totalW = w * shownCount + spacing * (shownCount - 1)
        totalH = h
    end

    -- Determine parent frame: overlay container for overlay, UIParent for real
    local parentFrame
    if isOverlay then
        GetOrCreatePartyOverlayContainer()
        parentFrame = ns._partyOC
    else
        parentFrame = UIParent
        if ns._partyOC then ns._partyOC:Hide() end
    end

    local slot = 0  -- running layout position; skips the hidden player frame
    for i = 1, 5 do
        local f = GetOrCreatePartyPvFrame(i)
        if hideSelf and i == playerSlot then
            f:Hide()
        else
            if f:GetParent() ~= parentFrame then f:SetParent(parentFrame) end
            f:SetFrameStrata(isOverlay and "FULLSCREEN_DIALOG" or "LOW")
            f:ClearAllPoints()
            if isVert then
                local yOff = slot * (h + spacing)
                if unitGrowth == "UP" then yOff = -yOff end
                if unitGrowth == "DOWN" then
                    f:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", anchorPad, -anchorPad - topExtra - yOff)
                else
                    -- UP grows from the bottom; the container's extra top height
                    -- creates the title gap, so no per-frame offset is needed here.
                    f:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", anchorPad, anchorPad + yOff)
                end
            else
                local xOff = slot * (w + spacing)
                if unitGrowth == "LEFT" then xOff = -xOff end
                if unitGrowth == "RIGHT" then
                    f:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", anchorPad + xOff, -anchorPad - topExtra)
                else
                    f:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -anchorPad + xOff, -anchorPad - topExtra)
                end
            end
            ApplyPartyPreviewData(f, i)
            f:Show()
            slot = slot + 1
        end
    end

    -- Size and position overlay container
    if isOverlay and ns._partyOC then
        ns._partyOC:SetSize(totalW + anchorPad * 2, totalH + anchorPad * 2 + topExtra)
        ns._partyOC:SetFrameStrata("FULLSCREEN_DIALOG")
        ns._partyOC:SetFrameLevel(10)
        if ns._partyOC._title then
            ApplyFont(ns._partyOC._title, 13)
            ns._partyOC._title:SetText("Preview")
            ns._partyOC._title:SetTextColor(1, 1, 1, 0.9)
            ns._partyOC._title:Show()
        end
        -- Hardcoded default position (not draggable, not saved): docked to the
        -- left edge of the options panel, screen center as a fallback.
        ns._partyOC:ClearAllPoints()
        local sf = EllesmereUI._scrollFrame
        if sf then
            ns._partyOC:SetPoint("BOTTOMRIGHT", sf, "BOTTOMLEFT", 0, 0)
        else
            ns._partyOC:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        ns._partyOC:Show()
    end

    -- Real mode: anchor frames to the actual party container position
    if mode == "real" and ns._partyContainerFrame then
        local pos = s.partyUnlockPos
        if pos then
            local idx = 0  -- running position; skips the hidden player frame
            for i = 1, 5 do
                local f = ns._partyPvFrames[i]
                if f then
                    if hideSelf and i == playerSlot then
                        f:Hide()
                    else
                        f:ClearAllPoints()
                        local ox, oy = 0, 0
                        if isVert then
                            oy = idx * (h + spacing)
                            if unitGrowth == "UP" then oy = -oy end
                        else
                            ox = idx * (w + spacing)
                            if unitGrowth == "LEFT" then ox = -ox end
                        end
                        f:SetPoint("TOPLEFT", ns._partyContainerFrame, "TOPLEFT", ox, -oy)
                        idx = idx + 1
                    end
                end
            end
        end
    end
end

local function ShowPartyPreview()
    -- See ShowPreview: never engage the preview (which reparents the real
    -- containers under a hidden frame) unless the options window is open and we
    -- are out of combat. Guards against deferred post-close ShowPartyPreview.
    if not ns._testMode and not (EllesmereUI.IsShown and EllesmereUI:IsShown()) then return end
    if InCombatLockdown() then return end
    -- Kill any active size preview
    if ns._sizePreviewTier then
        ns._sizePreviewTier = nil
        if ns._HideSizePreview then ns._HideSizePreview() end
    end
    if ns._partyPvActive then
        RefreshPartyPreview()
        return
    end
    local mode = db.profile.previewMode or "overlay"
    if mode == "none" then return end

    ns._partyPvActive = true
    -- Hide the real containers via alpha (combat-reversible); see ShowPreview.
    -- Never reparent secure-header containers (the restore would be blocked in
    -- combat and strand the frames for the whole pull).
    ns._SetRealFramesPreviewHidden(true)
    if mode == "overlay" then
        GetOrCreatePartyOverlayContainer()
    end
    InitPartyPreviewHealthValues()
    BuildPartyPreviewRoles()
    RefreshPartyPreview()
end

-- skipRestore: leave the real frames parented to the hidden frame instead of
-- restoring them. Used on in-panel tab swaps where another preview shows on the
-- next frame -- restoring here would flash the real frames for one frame before
-- the deferred ShowPreview re-hides them. Panel close restores explicitly.
local function HidePartyPreview(skipRestore)
    if not ns._partyPvActive then return end
    -- Stop the aura ticker while still party-active so it clears the party aura
    -- icons (PvFrames resolves to the party set here), then deactivate.
    StopPvAuraTicker()
    ns._partyPvActive = false
    for i = 1, 5 do
        if ns._partyPvFrames[i] then ns._partyPvFrames[i]:Hide() end
    end
    if ns._partyOC then ns._partyOC:Hide() end
    if skipRestore then return end
    -- The containers were only alpha-hidden (never reparented or moved); restore
    -- is a combat-legal SetAlpha(1) plus dropping the mouse blockers. See
    -- HidePreview. No combat gate, no SetParent/SetPoint, no ns._restorePending.
    ns._SetRealFramesPreviewHidden(false)
    if not InCombatLockdown() then LayoutGroups() end
    UpdateVisibility()
    if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
end

ns.ShowPartyPreview = ShowPartyPreview
ns.HidePartyPreview = HidePartyPreview
ns.partyPvActive = function() return ns._partyPvActive end
ns.ResetPartyPreviewRandomization = function()
    ns._partyPvRoles._randomized = nil
    ns._partyPvInit = false
end

-- Guaranteed restore invariant. Ensures both real containers are parented to
-- UIParent and their visibility recomputed whenever no preview should be
-- active (e.g. the options panel just closed). Heals the "frames stuck hidden
-- under the preview parent" case even when the preview flags were left false by
-- a skip-restore tab swap or a post-close deferred ShowPreview. Defers to
-- PLAYER_REGEN_ENABLED in combat (reparenting secure-header containers is a
-- protected action).
function ns.EnsureRealFramesRestored()
    if not containerFrame then return end
    -- Tear down any genuinely-active preview FIRST. HidePreview/HidePartyPreview
    -- now restore container alpha and drop the mouse blockers via combat-legal
    -- ops only (SetAlpha on our containers; Hide/SetParent on our own non-secure
    -- preview frames), so they never defer anything.
    if previewActive then HidePreview() end
    if ns._partyPvActive then HidePartyPreview() end
    -- Hard guarantee: force both real containers fully opaque and drop any mouse
    -- blockers, unconditionally. SetAlpha is not protected, so this is valid in
    -- combat and heals the "left alpha-hidden with the flags already false" cases
    -- (skip-restore tab swap, combat-cancelled deferred Show). The containers are
    -- never reparented or moved anymore, so nothing protected needs deferral.
    ns._SetRealFramesPreviewHidden(false)
    -- The layout/visibility recompute below SetPoints/Shows secure headers, so
    -- out of combat only. The alpha restore above already makes the frames
    -- visible during combat.
    if InCombatLockdown() then return end
    UpdateVisibility()
    if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
end

-- Fade out overlay previews when entering unlock mode
do
    local FADE_DUR = 0.1
    local function FadeOutFrame(frame)
        if not frame or not frame:IsShown() then return end
        local startAlpha = frame:GetAlpha()
        local elapsed = 0
        frame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= FADE_DUR then
                self:SetAlpha(0)
                self:Hide()
                self:SetScript("OnUpdate", nil)
                self:SetAlpha(startAlpha)
                return
            end
            self:SetAlpha(startAlpha * (1 - elapsed / FADE_DUR))
        end)
    end
    _G._ERF_UnlockModeOpen = function()
        FadeOutFrame(overlayContainer)
        FadeOutFrame(ns._partyOC)
    end
end

-------------------------------------------------------------------------------
--  External tracker integration (frame-provider APIs)
-------------------------------------------------------------------------------
-- Some cooldown / defensive tracker addons anchor their icons onto party/raid
-- unit frames. They find frames either from a hardcoded list of frame addons or
-- from a public provider API. EUI frames are custom, so where a provider API
-- exists we hand it our buttons. The unit lives on the secure "unit" attribute
-- (read via GetAttribute), so no plain field on the button is required.

-- Currently-visible EUI party unit buttons that have a unit assigned. Party
-- only by design -- raid frames are intentionally not exposed to trackers.
ns._CollectTrackerFrames = function()
    local out = {}
    if ns._partyAllButtons then
        for _, btn in ipairs(ns._partyAllButtons) do
            if btn:IsVisible() and btn:GetAttribute("unit") then
                out[#out + 1] = btn
            end
        end
    end
    return out
end

-- Notifies subscribed providers that our frame set changed, debounced to one
-- refresh per frame. Driven from the visibility paths -- the one change a
-- provider cannot learn from its own roster events.
ns._NotifyTrackerProviders = function()
    local cb = ns._trackerRefreshCb
    if not cb or ns._trackerRefreshPending then return end
    ns._trackerRefreshPending = true
    C_Timer.After(0, function()
        ns._trackerRefreshPending = false
        pcall(cb)
    end)
end

-- Registers EUI as a frame provider with any installed, supported tracker.
-- Inert when none is present. Called once from OnEnable.
ns._RegisterTrackerProviders = function()
    -- MiniCC: stable public global MiniCCApi.v1, created at its file load and so
    -- present by PLAYER_LOGIN whenever MiniCC is enabled.
    if MiniCCApi and MiniCCApi.v1 and MiniCCApi.v1.RegisterFrameProvider then
        pcall(function()
            MiniCCApi.v1:RegisterFrameProvider({
                Name = "EllesmereUI",
                GetFrames = ns._CollectTrackerFrames,
                RegisterRefreshFrames = function(cb) ns._trackerRefreshCb = cb end,
            })
        end)
    end
end

-------------------------------------------------------------------------------
--  Lifecycle: OnInitialize (ADDON_LOADED - SavedVariables available)
-------------------------------------------------------------------------------
function ERF:OnInitialize()
    -- Detect first install before DB creation overwrites the raw SV
    local rawDB = EllesmereUIRaidFramesDB
    local isFirstInstall = not rawDB or not rawDB.profiles
        or (rawDB.profiles and not next(rawDB.profiles))

    self.db = EllesmereUI.Lite.NewDB("EllesmereUIRaidFramesDB", defaults, true)
    db = self.db
    ns.db = db

    -- Migration: the legacy "Threat Borders" toggle (showThreat) became the
    -- "threatBorderSize" slider. Preserve intent for users who turned it off
    -- (false -> 0); everyone else falls through to the default size. Run for
    -- every saved profile so switching profiles mid-session keeps the choice.
    if EllesmereUIDB and EllesmereUIDB.profiles then
        for _, pdata in pairs(EllesmereUIDB.profiles) do
            local pf = pdata.addons and pdata.addons.EllesmereUIRaidFrames
            if pf then
                if pf.showThreat ~= nil then
                    if pf.showThreat == false then pf.threatBorderSize = 0 end
                    pf.showThreat = nil
                end
                if pf.party_showThreat ~= nil then
                    if pf.party_showThreat == false then pf.party_threatBorderSize = 0 end
                    pf.party_showThreat = nil
                end
            end
        end
    end

    -- Mark if we need to snapshot Blizzard's raid frame position
    local sv = self.db.sv
    self._needsCapture = not sv._capturedOnce_RF

    InitHealthBarTextures()
end

-------------------------------------------------------------------------------
--  Lifecycle: OnEnable (PLAYER_LOGIN - game data available)
-------------------------------------------------------------------------------
function ERF:OnEnable()
    PP = EllesmereUI.PanelPP or EllesmereUI.PP

    -- First-install default position: left edge of frame at 200px from screen
    -- left, vertically centered.
    if self._needsCapture then
        db.profile.unlockPos = {
            point = "LEFT", relPoint = "LEFT",
            x = 200, y = 0,
        }
        if not db.profile.partyUnlockPos then
            db.profile.partyUnlockPos = {
                point = "LEFT", relPoint = "LEFT",
                x = 400, y = 0,
            }
        end
        self.db.sv._capturedOnce_RF = true
        self._needsCapture = false
    end

    -- Initialize click-cast engine (before CreateHeaders so ClickCastFrames hook is active)
    if ns.CC_Init then ns.CC_Init() end

    -- Create headers and style all buttons
    CreateHeaders()

    -- Initial full reload (sets _activeSizeW/H from group size + tier overrides)
    ReloadFrames()

    -- Build buff manager spell lookup from saved assignments
    if ns.BM_RebuildLookup then ns.BM_RebuildLookup(db) end

    -- Create party header + style buttons (after CC_Init so click-cast registers)
    ns._CreatePartyHeader()

    -- Size + position party container from profile
    do
        local s = db.profile
        local w = s.partyFrameWidth or s.frameWidth or 125
        local h = s.partyFrameHeight or s.frameHeight or 60
        local sp = s.cellSpacing or 2
        ns._partyContainerFrame:SetSize(w, h * 5 + sp * 4)
        local pos = s.partyUnlockPos
        if pos then
            ns._partyContainerFrame:ClearAllPoints()
            ns._partyContainerFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
        end
    end

    -- Apply party-specific sizing to party buttons
    ns.ReloadPartyFrames()

    -- Register with unlock mode
    RegisterWithUnlockMode()

    -- Profile-swap refresh: EllesmereUI.RefreshAllAddons calls this on a profile
    -- change so raid + party frames re-read the (now-swapped) profile live,
    -- instead of staying stale until /reload. Mirrors the reload sequence above.
    _G._ERF_RefreshAll = function()
        if not ns.db then return end
        -- Rebuild the buff-manager spell lookup for the new profile's per-spec
        -- indicators (and the Simple Setup whitelist) before frames re-render.
        if ns.BM_RebuildLookup then ns.BM_RebuildLookup(ns.db) end
        -- Raid frames: restyle + relayout + reposition from the new profile.
        if ns.ReloadFrames then ns.ReloadFrames() end
        -- Party container size + position, then the party buttons.
        if ns._partyContainerFrame then
            local s = ns.db.profile
            local w = s.partyFrameWidth or s.frameWidth or 125
            local h = s.partyFrameHeight or s.frameHeight or 60
            local sp = s.cellSpacing or 2
            ns._partyContainerFrame:SetSize(w, h * 5 + sp * 4)
            local pos = s.partyUnlockPos
            if pos then
                ns._partyContainerFrame:ClearAllPoints()
                ns._partyContainerFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
            end
        end
        if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
        -- Re-sync per-unit UNIT_POWER_UPDATE registration to the new profile's
        -- power role filters, so units that GAIN power across the swap get live
        -- updates instead of a frozen one-shot snapshot (rage/runic power would
        -- otherwise sit empty out of combat). Event registration is combat-safe.
        if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
        -- Re-apply click-cast / hovercast bindings for the new profile.
        if ns.CC_ApplyBindings then ns.CC_ApplyBindings() end
    end


    -- Expose EUI party frames to external trackers that support a provider
    -- API (e.g. MiniCC). No-op when none is installed.
    ns._RegisterTrackerProviders()

    -- Event frame: register global (non-unit) events
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    eventFrame:RegisterEvent("RAID_TARGET_UPDATE")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("READY_CHECK")
    eventFrame:RegisterEvent("READY_CHECK_CONFIRM")
    eventFrame:RegisterEvent("READY_CHECK_FINISHED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PARTY_MEMBER_ENABLE")
    eventFrame:RegisterEvent("PARTY_MEMBER_DISABLE")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("UNIT_PHASE")

    -- Per-unit event trackers: one frame per unit.
    -- RegisterUnitEvent only accepts 1-2 units per call, so each unit gets
    -- its own frame. Units that don't exist simply don't fire (zero cost).
    local UNIT_EVENTS_BASE = {
        "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_AURA",
        "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_PREDICTION",
        "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
        "UNIT_NAME_UPDATE", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
        "PLAYER_FLAGS_CHANGED", "UNIT_CONNECTION", "UNIT_IN_RANGE_UPDATE",
    }
    local function MakeUnitTracker(unit)
        local f = CreateFrame("Frame")
        for _, ev in ipairs(UNIT_EVENTS_BASE) do
            f:RegisterUnitEvent(ev, unit)
        end
        f:RegisterUnitEvent("UNIT_POWER_UPDATE", unit)
        f:SetScript("OnEvent", OnEvent)
        unitTrackers[unit] = f
    end
    MakeUnitTracker("player")
    for i = 1, 4 do MakeUnitTracker("party" .. i) end
    for i = 1, 40 do MakeUnitTracker("raid" .. i) end
    eventFrame:SetScript("OnEvent", OnEvent)

    -- Dynamically register/unregister UNIT_POWER_UPDATE per unit based on
    -- role and power display settings. Called after roster changes and
    -- when the user changes power bar role filters.
    local function UpdatePowerEventRegistration()
        local s = db.profile
        local anyPower = IsPowerBarEnabled(s)
        for unit, tracker in pairs(unitTrackers) do
            local wantPower = false
            if anyPower and UnitExists(unit) then
                local role = ns._ResolvePowerRole(unit)
                wantPower = (role == "HEALER" and s.powerShowForHealer)
                    or (role == "TANK" and s.powerShowForTank)
                    or (role == "DAMAGER" and s.powerShowForDPS)
                    or (role == "NONE" and s.powerShowForDPS)
            end
            if wantPower then
                tracker:RegisterUnitEvent("UNIT_POWER_UPDATE", unit)
            else
                tracker:UnregisterEvent("UNIT_POWER_UPDATE")
            end
        end
    end
    ns.UpdatePowerEventRegistration = UpdatePowerEventRegistration

    -- Initial update after a short delay
    C_Timer.After(0.5, function()
        UpdateVisibility()
        ns._UpdatePartyVisibility()
        if framesVisible then
            RebuildUnitMap()
            LayoutGroups()
            UpdateAllButtons()
        end
        if ns._partyFramesVisible then
            ns._LayoutPartyFrames()
        end
    end)

    -- Northern Sky Raid Tools (NSRT) nickname integration. When NSAPI is present
    -- the raid + party names use NSRT nicknames (see ResolveDisplayName). Two
    -- callbacks refresh names instantly without a /reload: NSRT_NICKNAME_UPDATED
    -- fires when a nickname is added/removed, and EUI_NICKNAME_TOGGLE fires when the
    -- user flips NSRT's dedicated EllesmereUI nicknames checkbox. NSRT may load after
    -- us, so registration retries on PLAYER_LOGIN / PLAYER_ENTERING_WORLD until it sticks.
    local function RegisterNSRTNicknames()
        if ns._nsrtNickHooked then return true end
        if NSAPI and NSAPI.RegisterCallback then
            local function onChange() if ns.RefreshAllNames then ns.RefreshAllNames() end end
            NSAPI:RegisterCallback("NSRT_NICKNAME_UPDATED", onChange, "EllesmereUI")
            NSAPI:RegisterCallback("EUI_NICKNAME_TOGGLE", onChange, "EllesmereUI")
            ns._nsrtNickHooked = true
            return true
        end
        return false
    end
    if not RegisterNSRTNicknames() then
        local nsrtFrame = CreateFrame("Frame")
        nsrtFrame:RegisterEvent("PLAYER_LOGIN")
        nsrtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        nsrtFrame:SetScript("OnEvent", function(self)
            if RegisterNSRTNicknames() then self:UnregisterAllEvents() end
        end)
    end

    -- Init options module if it loaded before us
    if ns._InitEUIModule then
        C_Timer.After(0, ns._InitEUIModule)
    end
end

-- Slash command registered in EUI_RaidFrames_Options.lua
