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

-- Cache the parent-addon table on ns so hot, event-driven paths (UNIT_AURA,
-- PLAYER_REGEN_DISABLED) can read it as an upvalue field instead of a true
-- global. Reading the global EllesmereUI from an event frame that is still in a
-- secure execution context is what raised the benign "tainted while reading
-- global EllesmereUI" self-taint in the taint log; an upvalue/table-field read
-- does not trigger that. Stored on ns (not a new file-scope local) so the
-- main-chunk 200-local cap is untouched.
ns.EllesmereUI = EllesmereUI

-- The addon name external nickname providers (TimelineReminders, NSRT) key us by.
-- Full suite = the brand "EllesmereUI" (the parent addon they registered support
-- for). Standalone build = our own renamed folder name (ADDON_NAME, e.g.
-- "EUIStandaloneRaidFrames"), which is exactly the per-addon key TR fires for the
-- standalone. The word "Standalone" is never touched by the standalone token
-- rename, so this detection is rename-immune; the "EllesmereUI" literal is only
-- reached in the suite, where it is correct. On ns (not a new file-scope local)
-- since this file sits at the Lua 5.1 200-local cap.
ns.NICK_ADDON = ADDON_NAME:find("Standalone") and ADDON_NAME or "EllesmereUI"

-------------------------------------------------------------------------------
--  Frame-level layout (offsets above the button / preview-frame level).
--  All aura VISUALS share one band ABOVE the threat/dispel/base border so the
--  threat border renders behind them: debuffs, defensives/externals, private
--  auras, dispel-type icons, and Buff Manager icons/squares/bars. Each aura
--  unit renders its own children (cooldown/border/text) up to +5 above its base.
--  Ordering (bottom to top): base border (+8/strips +9) -> hover/target raise
--  (ns.LVL_RAISE, strips +11, covering the base/threat/dispel border strips) ->
--  the text band (ns.LVL_TEXT: name/health text, role icon, leader crown) ->
--  the aura band -> the marker carrier (also hosts ready-check / summon / rez
--  icons). The raise deliberately stays BELOW the text band, so the target /
--  hover border never covers text, and auras always draw over text -- in every
--  state. Consequence: with overlapping frames (negative spacing) a neighbor's
--  text/auras can clip the raised border; it only outranks neighbor BORDERS.
--  Opt-out: the per-profile "Show Above Icons" toggle (name cog) lifts a
--  button's text carrier to ns.LVL_AURA + 6, above the aura band's children.
--  Kept on `ns` (not file-scope locals) to avoid the Lua 5.1 local cap in this
--  large file, and shared with EUI_RaidFrames_BuffManager.lua.
-------------------------------------------------------------------------------
ns.LVL_DISPEL_OVERLAY = 7  -- Blizzard private-aura dispel gradient: below the border (+8) and name/health text (ns.LVL_TEXT) so it renders BEHIND them (like the regular dispel overlay), but above the health bar so it stays visible. Per-slot private-aura icons stay above at LVL_AURA.
ns.LVL_RAISE  = 10   -- main border while hovered/targeted (strips at +11: above
                     -- the base strips +9 and tie-above the threat/dispel strips
                     -- +11 -- the raise container is created later, ties render
                     -- later-created on top -- but strictly below the text band.
                     -- MUST stay below ns.LVL_TEXT: the main border's strips are
                     -- created lazily in UpdateBorder, AFTER the text carriers,
                     -- so a level tie with text would put the border on top)
ns.LVL_TEXT   = 12   -- text band: name/health text, role icon, leader crown --
                     -- above every border incl. the raise, below the aura band
ns.LVL_AURA   = 13   -- base level for every aura icon/bar (children at +1..+5)
ns.LVL_MARKER = 22   -- raid marker icon (always on top)

-------------------------------------------------------------------------------
--  Leader-icon host strata: keeps the leader/assistant icon host on the
--  button's own strata, in the text band (ns.LVL_AURA - 1 = ns.LVL_TEXT, same
--  as the name/health text) so the crown clears every border -- including the
--  hover/target raise, which stays below the band -- while auras still draw
--  over it. Re-applied on reload so it recovers if a container
--  SetFrameStrata cascade reset it. (Previously this lowered the host onto the
--  chat strata, which left the icon drawing BENEATH the border entirely.)
-------------------------------------------------------------------------------
function ns.ApplyLeaderStrata(frame)
    local parent = frame:GetParent()
    if parent then
        frame:SetFrameStrata(parent:GetFrameStrata())
        frame:SetFrameLevel(parent:GetFrameLevel() + (ns.LVL_AURA - 1))
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
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitThreatSituation   = UnitThreatSituation
local UnitIsUnit            = UnitIsUnit
local UnitInRange           = UnitInRange
local UnitGetTotalAbsorbs   = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local GetReadyCheckStatus   = GetReadyCheckStatus
local C_IncomingSummon      = C_IncomingSummon
local SUMMON_STATUS_PENDING  = Enum.SummonStatus and Enum.SummonStatus.Pending or 1
local SUMMON_STATUS_ACCEPTED = Enum.SummonStatus and Enum.SummonStatus.Accepted or 2
local SUMMON_STATUS_DECLINED = Enum.SummonStatus and Enum.SummonStatus.Declined or 3
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

-- Strata bump for the per-slot private aura ICON frames (workaround for 12.0.5
-- bug where private aura icons render behind the parent frame). The dispel
-- OVERLAY container does NOT use this -- it stays on the button's own strata at
-- a below-text frame level so it renders behind the text (see RegisterDispelContainer).
local PA_STRATA_FIX = {
    BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG",
}

-- Absorb shield textures (must match UnitFrames exactly)
local ABSORB_STYLE_TEX = {
    striped         = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-5.png",
    stripedReversed = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-5-reversed.png",
    clean           = "Interface\\Buttons\\WHITE8X8",
    blizzard        = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\blizzard.tga",
    healBlizzModern = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\louis-absorb.png",
    largeOutlinedStripes  = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-habsorb-left.png",
    largeOutlinedStripesR = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-habsorb-right.png",
    largeStripes          = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-absorb-left.png",
    largeStripesR         = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-absorb-right.png",
}
local ABSORB_STYLE_ALPHA = {
    striped         = 0.8,
    stripedReversed = 0.8,
    clean           = 0.3,
    blizzard        = 0.8,
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
    blizzLight = {
        _isTexture = true,
        TANK    = ROLE_MEDIA .. "tank.png",
        HEALER  = ROLE_MEDIA .. "healer.png",
        DAMAGER = ROLE_MEDIA .. "dps.png",
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

-- Combat indicator media + class sprite coords (shared with the Unit Frames
-- combat icon assets). Kept on `ns` to avoid the Lua 5.1 chunk local cap.
ns._COMBAT_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\combat\\"
ns._COMBAT_CLASS_COORDS = {
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
        hideEmptyGroups  = true,     -- collapse subgroups with no members (raid only, real frames)
        excludeHiddenGroupsFromSize = true, -- hidden Show Groups don't count toward the raid-size breakpoint

        -- Visibility
        showWhenSolo     = false,
        showWhenGroup    = false,
        showWhenRaid     = true,

        -- Friendly Boss Frames (boss1-5 healable NPC frames, raid only)
        friendlyBoss = {
            display  = "never",   -- "never" | "healers" | "always"
            position = "right",   -- "left" | "right" | "free"
            freePos  = { x = 100, y = 0 },
            freeHorizontal = false,
            healthColor = { r = 23/255, g = 172/255, b = 49/255 },
            extraWidth  = 0,      -- size offset on top of the raid frame size
            extraHeight = 0,
        },

        -- Extra Frames (duplicates of chosen raid members, raid only)
        extraFrames = {
            showTanks = false,    -- auto-include the raid's tanks
            position  = "right",  -- "left" | "right" | "free"
            freePos   = { x = 100, y = -120 },
            freeHorizontal = false,
            players   = {},       -- manually added names (hotkey toggle)
            extraWidth  = 0,      -- size offset on top of the raid frame size
            extraHeight = 0,
            wrapAfter = 0,        -- Free Move frames per row/column; 0 = single line
            -- growDirection / wrapDirection / freeRect are optional keys (no
            -- defaults): unset, growth derives from freeHorizontal, wrap from
            -- the perpendicular default, and anchoring from freePos. See
            -- XF.GrowInfo / XF.FreeAnchor.
        },

        -- Position (saved by unlock mode)
        unlockPos        = nil,

        -- Health bar
        healthBarTexture = "atrocity",
        healthBarOpacity = 100,
        healthColorMode  = "class",  -- "class", "dark", "classic", "custom", "customDynamic"
        customFillColor  = { r = 37/255, g = 193/255, b = 29/255 },
        -- Custom Dynamic Colors: user-chosen health-percent gradient stops. Defaults
        -- match the Classic curve so switching from Classic looks identical at first.
        dynamicColor100  = { r = 0, g = 1, b = 0 },   -- full health
        dynamicColor50   = { r = 1, g = 1, b = 0 },   -- half health
        dynamicColor0    = { r = 1, g = 0, b = 0 },   -- empty health
        customBgColor    = { r = 17/255, g = 17/255, b = 17/255 },
        bgClassColored   = false,
        bgDarkness       = 50,

        -- Power bar (on when any powerShowFor* role is true)
        showPowerBar     = true,
        powerHeight      = 4,
        powerBgDarkness  = 40,
        powerBgColor     = { r = 107/255, g = 107/255, b = 107/255 },
        powerBgPowerColored = false,
        powerBorderStyle = "eui",      -- "eui", "divider", "border"
        powerBorderSize  = 1,
        powerBorderColor = { r = 0, g = 0, b = 0 },
        powerBorderAlpha = 1,
        powerShowForHealer = true,
        powerShowForTank   = true,
        powerShowForDPS    = false,
        -- Uniform Icon Anchoring: icons/text anchor as if no power bar existed,
        -- so frames with and without a per-role power bar line up identically.
        powerUniformAnchors = false,

        -- Top Name Bar (reserves height from the TOP of the frame, the way the
        -- power bar reserves from the bottom; shows the unit name in a dedicated
        -- band. When enabled it suppresses the in-frame Name.)
        topNameBarEnabled       = false,
        topNameBarHeight        = 20,
        topNameBarBgColor       = { r = 17/255, g = 17/255, b = 17/255 },
        topNameBarBgOpacity     = 80,
        topNameBarTextSize      = 11,
        topNameBarTextColorMode = "class",  -- "class" or "custom"
        topNameBarTextColor     = { r = 1, g = 1, b = 1 },
        topNameBarTextOffsetX   = 0,
        topNameBarTextOffsetY   = 0,
        topNameBarTextAlign     = "center", -- "center", "left", "right"

        -- Text
        nameSize         = 10,
        nameMaxLength    = 15,  -- max characters shown for unit names (0 = off / no cap)
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
        -- Heal Absorb Text (1:1 with Health Text; shows the heal-absorb shield
        -- amount in short/full format, hidden at zero). Defaults to red to match
        -- how raid addons surface heal absorbs.
        healAbsorbTextMode   = "none",   -- "none", "amount", "short"
        healAbsorbTextColorMode   = "custom",  -- "class", "accent", "custom"
        healAbsorbTextCustomColor = { r = 1, g = 0.3, b = 0.3 },
        healAbsorbTextSize   = 9,
        healAbsorbTextPosition = "center",
        healAbsorbTextOffsetX  = 0,
        healAbsorbTextOffsetY  = 0,

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
        -- Show the "overshield" -- the part of an absorb that exceeds the empty
        -- health and backfills over your current health. When off, absorbs only
        -- fill the empty part of the health bar (and on Default Blizz Frames the
        -- glow line stays pinned at the right edge during overshields).
        showOvershield   = true,
        healAbsorbStyle  = "clean",
        healAbsorbOpacity = 75,
        healAbsorbColor  = { r = 0.8, g = 0.15, b = 0.15 },
        healPrediction   = false,
        healPredOpacity  = 75,
        healPredColor    = { r = 102/255, g = 243/255, b = 102/255 },
        -- Absorb / heal absorb placement, independent per bar.
        -- "overlay" = over the health fill (default), "right" = from the frame's
        -- right edge, "left" = from the frame's left edge. (Migrated from the old
        -- shared absorbFromRightEdge boolean.)
        absorbEdgeMode     = "overlay",
        healAbsorbEdgeMode = "overlay",
        -- Lift the heal-absorb overlay above the dispel gradient (default off).
        -- When off, the heal-absorb bar keeps its original level (below dispel).
        healAbsorbOverDispel = false,
        -- Black backing behind the heal-absorb texture (all styles); 0 = off.
        healAbsorbBgOpacity = 25,
        -- Reduced max-health overlay (always right-anchored). Styled like Heal
        -- Absorb but with a dedicated "Max Health Stripes" texture and no
        -- placement option.
        maxHealthStyle      = "maxHealthStripes",
        maxHealthColor      = { r = 0.7, g = 0.1, b = 0.1 },
        maxHealthOpacity    = 100,
        maxHealthBgOpacity  = 100,
        -- Absorb Bar: solid bar above the frame, fills from the right edge
        absorbBarEnabled = false,
        absorbBarHeight  = 4,
        absorbBarColor   = { r = 1, g = 1, b = 1 },
        -- Fill direction for the vertical (Right/Left Edge) positions.
        absorbBarGrowDir = "up",
        -- Heal Absorb Bar: separate strip showing the heal-absorb amount
        healAbsorbBarPosition = "none",
        healAbsorbBarHeight   = 4,
        healAbsorbBarColor    = { r = 200/255, g = 29/255, b = 29/255 },
        healAbsorbBarGrowDir  = "up",

        -- Indicators
        roleIconStyle    = "modern",  -- none/modern/modernCircle/styled/classicCircle/classic/blizzDefault/blizzLight
        roleIconSize     = 13,
        roleIconPosition = "bottomleft",  -- topleft/top/topright/left/center/right/bottomleft/bottom/bottomright
        roleIconOffsetX  = 0,
        roleIconOffsetY  = 0,
        roleIconHideInCombat = false,
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
        showIncomingRez  = true,
        readyCheckSize   = 20,
        readyCheckPosition = "center",  -- "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom"
        readyCheckOffsetX  = 0,
        readyCheckOffsetY  = 0,
        threatBorderSize = 2,    -- aggro warning border thickness; 0 = off
        showLeaderIcon   = false,
        showLeaderIconInCombat = true,  -- "Show In Combat" cog; off = hide in combat
        leaderIconPosition = "top",
        leaderIconSize   = 14,
        leaderIconOffsetX  = 0,
        leaderIconOffsetY  = 0,
        -- Combat icon: shown on members who are in combat (M+ skip awareness)
        showCombatIndicator = false,
        combatIndicatorStyle = "standard",   -- standard/class/combat0..5 (none handled by showCombatIndicator)
        combatIndicatorColor = "custom",      -- custom/classcolor (standard/class styles only)
        combatIndicatorCustomColor = { r = 1, g = 0.2, b = 0.2 },
        combatIndicatorSize  = 16,
        combatIndicatorPosition = "right",
        combatIndicatorOffsetX = 0,
        combatIndicatorOffsetY = 0,
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
        dispelOverlay    = "fill",   -- "none", "fill", "full", "gradient", "gradient_sharp"
        dispelOverlayOpacity = 100,
        dispelShowAll             = true,   -- true = highlight any dispellable debuff; false = only player-dispellable
        dispelOverlayPosition     = 0,      -- 0=Top, 1=Bottom, 2=Left (aura-organization-type for private aura dispel container)
        showDispelIcons       = false,
        dispelIconPosition = "right",
        dispelIconOffsetX  = 0,
        dispelIconOffsetY  = 0,
        dispelIconSize     = 16,
        dispelClockBorder  = false,  -- animated clock-style dispel border (erases clockwise) on dispellable debuff icons
        dispelClockExtraBorder = 0,  -- extra physical pixels added to the clock border thickness (on top of debuffBorderSize)
        dispellableDebuffLocation = "same",      -- "same" = use the main debuff layout; else a separate anchor for dispellable debuffs
        dispellableDebuffGrowDirection = "RIGHT",
        dispellableDebuffOffsetX = 0,
        dispellableDebuffOffsetY = 0,
        dispellableDebuffSize = 0,               -- icon size at the separate anchor (0 = match Debuff Size)
        -- Per-dispel-type colors (defaults mirror DISPEL_COLORS). "Bleed" is the
        -- no-dispelName/physical type (stored under the "" key in DISPEL_COLORS).
        dispelColorMagic   = { r = 0.349, g = 0.475, b = 1.0 },
        dispelColorCurse   = { r = 0.636, g = 0.0,   b = 0.64 },
        dispelColorDisease = { r = 0.671, g = 0.384, b = 0.098 },
        dispelColorPoison  = { r = 0.0,   g = 0.706, b = 0.286 },
        dispelColorBleed   = { r = 0.75,  g = 0.15,  b = 0.15 },
        -- Health background status tint (Status Colors swatch in Extras).
        statusColorOffline = { r = 0x66/255, g = 0x66/255, b = 0x66/255 },  -- #666666
        statusColorDead    = { r = 0x24/255, g = 0x17/255, b = 0x17/255 },  -- #241717

        -- Buff Manager (indicator-centric model)
        bmIndicators      = {},  -- { [specKey] = { indicator1, indicator2, ... } }

        -- Private Auras (Blizzard-rendered boss debuff icons)
        paSize           = 20,
        paShowCountdown  = false,
        paHideTooltip    = true,
        paPosition       = "center",
        paOffsetX        = 0,
        paOffsetY        = 0,
        paGrowDirection  = "RIGHT",
        paSpacing        = 0,

        -- Debuffs
        debuffFilter     = "all",  -- "none", "all", "raid", "dispellable"
        hideLustDebuff   = true,
        -- CC Debuff Glow: glow displayed debuff icons whose aura is crowd control
        -- (Blizzard CROWD_CONTROL aura filter). Mirrors CDM's Buff Glow control.
        -- 0 = None (default); style index 1 = Pixel Glow.
        debuffCCGlowType       = 0,
        debuffCCGlowClassColor = false,
        debuffCCGlowR = 1.0, debuffCCGlowG = 0.776, debuffCCGlowB = 0.376,
        debuffCCGlowLines = 8, debuffCCGlowThickness = 2, debuffCCGlowSpeed = 4,
        debuffCCGlowBackground = false,
        debuffCCGlowBackgroundR = 0, debuffCCGlowBackgroundG = 0, debuffCCGlowBackgroundB = 0,
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
            ownOnly         = true,
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
            showStacks      = true,
            stacksTextColor = { r = 1, g = 1, b = 1 },
            stacksTextSize  = 8,
            stacksOffsetX   = -1,
            stacksOffsetY   = 2,
        },

        buffHideTooltips = true,
        debuffSize       = 18,
        debuffCap        = 3,
        debuffHideTooltips = true,
        debuffPosition   = "bottomright",
        debuffOffsetX    = 0,
        debuffOffsetY    = 0,
        debuffGrowDirection = "LEFT",
        debuffPerRow     = 5,   -- icons per row (1 = single line, no wrap; >= 2 wraps)
        debuffWrapDirection = "UP",
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

        -- Targeted spells (see EUI_RF_TargetedSpells.lua). ts* = party,
        -- tsRaid* = raid. Independent on purpose: tsRaid* keys are NOT in
        -- PARTY_KEY_SECTION, so they stay outside the raid/party section
        -- sync system.
        tsEnabled   = true,   -- legacy boolean; superseded by tsMode (kept harmless)
        tsMode      = "whenHealing",  -- never | whenHealing | always
        tsIconSize  = 24,
        tsPosition  = "center",
        tsGrowDirection = "CENTER",
        tsOffsetX   = 0,
        tsOffsetY   = 0,
        tsMaxIcons  = 3,
        tsRaidEnabled   = true,   -- legacy boolean; superseded by tsRaidMode (kept harmless)
        tsRaidMode      = "never",  -- raid hard-defaults OFF (NOT migrated from tsRaidEnabled)
        tsRaidIconSize  = 24,
        tsRaidPosition  = "center",
        tsRaidGrowDirection = "CENTER",
        tsRaidOffsetX   = 0,
        tsRaidOffsetY   = 0,
        tsRaidMaxIcons  = 3,

        -- Range & misc
        oorAlpha         = 0.4,
        -- Raid frame tooltip visibility. showTooltip is the legacy on/off key,
        -- kept as the fallback the "Show Raid Frames Tooltip" dropdown derives
        -- from for existing users (see ns._ResolveTooltipMode). Picking a
        -- dropdown option writes tooltipMode = always | outOfCombat |
        -- outOfBossCombat | never (unset = derived, so legacy profiles see no
        -- change). Governs only the raid/party frame tooltips -- no other unit
        -- tooltips are touched.
        showTooltip      = true,
        freeRightClickCamera = false,  -- right-click + drag over a raid/party frame turns the camera (mouselook)

        -- Preview mode: "real", "overlay", "none"
        previewMode       = "overlay",

        -- Raid size overrides: { [10] = { width=X, height=Y }, ... }
        raidSizeOverrides = nil,
        autoResizeIndicators = false,
        -- Tracked Buffs (Buff Manager) auto-resize. Defaults ON because this was
        -- previously hardcoded always-on; the "Auto Resize Icons" dropdown now
        -- exposes it. nil (legacy profiles) is treated as on so nothing changes.
        autoResizeTrackedBuffs = true,

        -- Party frame overrides (sparse -- falls back to raid settings)
        partyFrameWidth   = 125,
        partyFrameHeight  = 60,
        partyShowWhenSolo = false,
        partyCenterWhenSolo = false,  -- center the lone player frame in the container when solo
        partySyncSections = nil,  -- nil = all synced; { healthBar=false } = healthBar custom
        partySortMode     = "ROLE",
        partyPrioritizeClass = false, -- sort by class within the main sort (party only)
        partyClassOrder    = nil,  -- nil = all 13 classes alphabetical by name
        partyShowSelfFirst = true,
        partySelfLast      = false,
        partyHorizontal   = false,
        partyFlipGrowth   = false,  -- DOWN->UP / RIGHT->LEFT growth flip
        partyHideSelf     = false,
        partyUnlockPos    = nil,
        -- Party Tracked Buffs (Buff Manager) auto-resize. Defaults ON (matching
        -- the prior hardcoded always-on behavior); nil is treated as on. The
        -- "Auto Resize Icons" dropdown on the Party tab exposes it. Mirrors the
        -- raid autoResizeTrackedBuffs key.
        partyAutoResizeTrackedBuffs = true,
    }
}

-------------------------------------------------------------------------------
--  State tables
-------------------------------------------------------------------------------
local allButtons     = {}   -- flat list of all created buttons
local unitToButton   = {}   -- unitToken -> button map (rebuilt on roster change)
ns._raidUnitToButton = unitToButton  -- ns alias for Targeted Spells (same table:
                            -- rebuilds wipe it in place, never replace it)
ns._xfUnitToButton   = {}   -- unitToken -> Extra Frames duplicate (bounded by
                            -- XF.CAP; owned by XF_Apply, never written by
                            -- the rebuild paths)
local separatedHdrs  = {}   -- [1..8] group headers
local containerFrame = nil  -- top-level positioning frame
ns._flatButtons      = {}   -- buttons owned by the flat (merged) header
ns._flatHeader       = nil  -- single header for merge-groups mode
local eventFrame     = CreateFrame("Frame")
local unitTrackers   = {}  -- [unitToken] = tracker frame
local inCombat       = false

-------------------------------------------------------------------------------
--  Tooltip visibility mode resolver. The "Show Raid Frames Tooltip" dropdown
--  stores tooltipMode = always | outOfCombat | outOfBossCombat | never and
--  governs ONLY the raid/party frame tooltips (gated in their own OnEnter --
--  no global hook; other unit tooltips are never touched). When unset (legacy
--  profiles), derive the mode from the old keys so existing users see no change:
--  showTooltip=false -> never; the old global "show in combat" flag on ->
--  always; otherwise the original out-of-combat default. `s` is a scaled raid/
--  party/extra proxy (or db.profile). Lives on ns (not a file local) so the
--  OnEnter handler can reach it; this file is at the Lua 5.1 local cap.
-------------------------------------------------------------------------------
ns._ResolveTooltipMode = function(s)
    if not s then return "outOfCombat" end
    local m = s.tooltipMode
    if m ~= nil then return m end
    if s.showTooltip == false then return "never" end
    if EllesmereUIDB and EllesmereUIDB.showUnitTooltipsInCombat then return "always" end
    return "outOfCombat"
end

-- Whether raid-frame hover tooltips are allowed right now, per the "Show Raid
-- Frames Tooltip" mode + current combat state. Shared by the unit tooltip and
-- the buff/debuff aura-icon tooltips so one setting governs every raid-frame
-- tip (an aura tip is still gated by its own "Hide Tooltips" toggle on top).
function ns.RaidFrameTooltipAllowed(button)
    local fd = button and ns.GetFFD and ns.GetFFD(button)
    local s = (fd and (fd._isParty and ns._scaledPartyProxy
        or (fd._isExtra and ns._scaledExtraProxy) or ns._scaledProfile))
        or ns._scaledProfile
    -- Holding the Blizz UI Enhanced peek modifier lifts the mode so a hidden
    -- tip can be read on hover (e.g. mid-combat), matching the global tooltips.
    if EllesmereUI._tooltipPeekHeld and EllesmereUI._tooltipPeekHeld() then return true end
    local ttMode = ns._ResolveTooltipMode(s)
    if ttMode == "never" then return false end
    if ttMode == "outOfCombat" and inCombat then return false end
    if ttMode == "outOfBossCombat" and ns._inBossCombat then return false end
    return true
end

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
    -- Epsilon-guarded round (matches PP.SnapForES): the CENTER->TOPLEFT
    -- derivation puts odd-footprint edges exactly on half-pixel boundaries,
    -- where uiScale float dust otherwise decides the direction per reload.
    return floor(value / onePixel + 0.5 + 0.001) * onePixel
end

-------------------------------------------------------------------------------
--  Font helper (matches UF/CDM pattern)
-------------------------------------------------------------------------------
local function GetOutline()
    -- Slug-gated at the source (GetFontOutlineFlag) by the global "Never Show Slug" toggle.
    return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("raidFrames")) or ""
end
local function GetUseShadow()
    return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow("raidFrames")
end
local function ApplyFont(fs, size)
    if not (fs and fs.SetFont) then return end
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    local outline = GetOutline()
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, outline == "" and GetUseShadow()) end
    fs:SetFont(fontPath, size, outline)
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
    healthBarTextures["blinkii-diamonds"] = TEX_BASE .. "blinkii-diamonds.tga"
    healthBarTextures["kringel-window"]   = TEX_BASE .. "kringel-window.tga"

    healthBarTextureNames["none"]             = "None"
    healthBarTextureNames["melli"]            = "Melli (ElvUI)"
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
    healthBarTextureNames["blinkii-diamonds"] = "Blinkii Diamonds"
    healthBarTextureNames["kringel-window"]   = "Kringel Window"

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
    healthBarTextureOrder[18] = "blinkii-diamonds"
    healthBarTextureOrder[19] = "kringel-window"

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

-- Resolve an absorb/heal/max-health style key to a texture path. Built-in
-- styles come from ABSORB_STYLE_TEX; "sm:" SharedMedia keys (shared with the
-- Bar Texture dropdown, appended into healthBarTextures) fall through to the
-- health-bar texture lookup. Used by the live render and the preview builder so
-- a saved SM key paints identically everywhere. Special keys handled by their
-- callers (blizzardModern / maxHealthStripes) never reach this.
function ns.ResolveAbsorbStyleTex(style, fallback)
    return ABSORB_STYLE_TEX[style]
        or (EllesmereUI.ResolveTexturePath and EllesmereUI.ResolveTexturePath(healthBarTextures, style, fallback))
        or fallback
end

-------------------------------------------------------------------------------
--  Power bar visibility (derived from role flags)
-------------------------------------------------------------------------------
local function IsPowerBarEnabled(s)
    return s.powerShowForHealer or s.powerShowForTank or s.powerShowForDPS
end

-- Uniform Icon Anchoring (powerUniformAnchors): decoration anchor host for a
-- health bar. Returns the full-height reference stamped on the bar at creation
-- (_euiUniformRef spans where the bar would sit with NO power bar) when the
-- toggle is on, so per-role power bars never shift icons/text between frames.
-- Health-bar visuals (fills, absorbs, dispel overlays) keep the real bar.
function ns.RF_AnchorHost(health, s)
    local ref = health and health._euiUniformRef
    if ref and s and s.powerUniformAnchors then return ref end
    return health
end

-- Live-render convenience: resolves the button's settings source (party/extra
-- proxies) before delegating to ns.RF_AnchorHost.
function ns.RF_AnchorHostFor(d)
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    return ns.RF_AnchorHost(d.health, s)
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
    -- Single cascade authority (ns._RFResolveTierOverride, defined in the
    -- growth-origin block): exact tier, then one step toward 20, then base.
    local _, ov = ns._RFResolveTierOverride(groupSize)
    if ov then return ov.width or baseW, ov.height or baseH end
    return baseW, baseH
end

-- Effective raid head count for size-breakpoint determination. By default (and
-- when "Exclude Hidden Groups from Size" is on) members sitting in subgroups
-- hidden via Show Groups are not counted while in a raid. This lets a user hide
-- groups 7/8 (or any groups) and have the raid-size breakpoint reflect only the
-- members they actually see, instead of the full roster bumping them into a
-- smaller-frame tier. Explicitly turned off: returns GetNumGroupMembers()
-- verbatim (counts the full roster).
ns._GetEffectiveRaidSize = function()
    local n = GetNumGroupMembers() or 0
    if n == 0 then return n end
    local s = db.profile
    if s.excludeHiddenGroupsFromSize == false then return n end
    -- Subgroups only exist in a raid; party/solo has nothing to exclude.
    if not IsInRaid() then return n end
    local vg = s.visibleGroups
    if not vg then return n end
    -- Skip the roster walk entirely when no group is actually hidden.
    local anyHidden = false
    for g = 1, 8 do
        if vg[g] == false then anyHidden = true; break end
    end
    if not anyHidden then return n end
    local count = 0
    for ri = 1, n do
        local _, _, sub = GetRaidRosterInfo(ri)
        -- Fail OPEN on nil subgroup: right after joining a raid the roster
        -- streams in and GetRaidRosterInfo returns nil for members whose
        -- data has not arrived -- dropping them undercounted the raid (a
        -- 35-man read as a handful and positioned on the base tier). Count
        -- unknowns as visible; once their subgroup arrives, the next roster
        -- pass refines the number downward.
        if not sub or vg[sub] ~= false then count = count + 1 end
    end
    -- Degenerate guard: if every populated group is hidden the filter excludes
    -- everyone. Fall back to the raw count so we never size for a 0-man raid
    -- (nothing is shown in that case anyway).
    if count == 0 then return n end
    return count
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

-- Custom Dynamic Colors: like Classic, but the three gradient stops (full / half /
-- empty health) are user-chosen. Live frames feed a C_CurveUtil curve to
-- UnitHealthPercent (secret-value safe, identical to the Classic path); the curve
-- is cached and rebuilt only when one of the three colors changes. Wrapped in a
-- do-block so the cache state does not consume main-chunk local slots (this file
-- is at the Lua 5.1 200-local cap).
do
    local DEF100 = { r = 0, g = 1, b = 0 }
    local DEF50  = { r = 1, g = 1, b = 0 }
    local DEF0   = { r = 1, g = 0, b = 0 }
    local dynCurve
    local r0, g0, b0, r50, g50, b50, r100, g100, b100
    function ns.GetCustomDynamicCurve(s)
        s = s or db.profile
        local c0   = s.dynamicColor0   or DEF0
        local c50  = s.dynamicColor50  or DEF50
        local c100 = s.dynamicColor100 or DEF100
        if not (dynCurve
            and r0   == c0.r   and g0   == c0.g   and b0   == c0.b
            and r50  == c50.r  and g50  == c50.g  and b50  == c50.b
            and r100 == c100.r and g100 == c100.g and b100 == c100.b) then
            dynCurve = C_CurveUtil.CreateColorCurve()
            dynCurve:SetType(Enum.LuaCurveType.Linear)
            dynCurve:AddPoint(0,   CreateColor(c0.r,   c0.g,   c0.b,   1))
            dynCurve:AddPoint(0.5, CreateColor(c50.r,  c50.g,  c50.b,  1))
            dynCurve:AddPoint(1,   CreateColor(c100.r, c100.g, c100.b, 1))
            r0, g0, b0       = c0.r, c0.g, c0.b
            r50, g50, b50    = c50.r, c50.g, c50.b
            r100, g100, b100 = c100.r, c100.g, c100.b
        end
        return dynCurve
    end

    -- Clean-number interpolation matching the curve above, for preview surfaces
    -- where the health percent is a known fake value (0-1). Linear between the
    -- 0%/50% stops below half, and the 50%/100% stops at or above half.
    function ns.ResolveDynamicColor(s, pct01)
        s = s or db.profile
        local c0   = s.dynamicColor0   or DEF0
        local c50  = s.dynamicColor50  or DEF50
        local c100 = s.dynamicColor100 or DEF100
        if pct01 >= 0.5 then
            local t = (pct01 - 0.5) * 2
            return c50.r + (c100.r - c50.r) * t,
                   c50.g + (c100.g - c50.g) * t,
                   c50.b + (c100.b - c50.b) * t
        end
        local t = pct01 * 2
        return c0.r + (c50.r - c0.r) * t,
               c0.g + (c50.g - c0.g) * t,
               c0.b + (c50.b - c0.b) * t
    end
end

-- Dark mode colours come from the global per-profile Dark Mode palette via
-- EllesmereUI.GetDarkModeFill() / GetDarkModeBg(), fetched live at each use so a
-- settings change shows on the next frame refresh -- and so no file-scope locals
-- are added (this file is at the 200 main-chunk local cap). Opacity is honoured
-- here (Raid Frames + Unit Frames); only Resource Bars keep their own alpha.

-- Paints the health-bar background (and dims the fill) for the unit's life and
-- connection state. Dead/offline: the bg covers the FULL bar so the tint reads
-- even at full last-known health, and the fill dims. Alive/online: the normal
-- background covers only the missing-health portion (anchored to the fill's
-- right edge) so it never bleeds behind the fill during the OOR range fade.
-- Centralized so the full update and the lightweight UNIT_HEALTH update (which
-- owns death/resurrect transitions) stay in lockstep -- otherwise a resurrect
-- arriving only via UNIT_HEALTH would strand the tint. Defaults: offline = dark
-- gray, dead = dark red (overridable via the Status Colors swatch in Extras);
-- the inline fallbacks only allocate if the DB key is missing. On ns (not a
-- local) to stay under the main-chunk 200-local cap.
function ns._ApplyHealthBg(d, health, s, unit)
    local EllesmereUI = ns.EllesmereUI  -- upvalue read, not a global read (see taint note at top)
    local bg = d.bg
    if UnitIsDeadOrGhost(unit) then
        if bg then
            local c = s.statusColorDead or { r = 0x24/255, g = 0x17/255, b = 0x17/255 }
            bg:ClearAllPoints(); bg:SetAllPoints(health)
            bg:SetColorTexture(c.r, c.g, c.b, 1)
        end
        if health then health:SetStatusBarColor(0.3, 0.3, 0.3, 0.5) end
        return
    elseif not UnitIsConnected(unit) then
        if bg then
            local c = s.statusColorOffline or { r = 0x66/255, g = 0x66/255, b = 0x66/255 }
            bg:ClearAllPoints(); bg:SetAllPoints(health)
            bg:SetColorTexture(c.r, c.g, c.b, 1)
        end
        if health then health:SetStatusBarColor(0.3, 0.3, 0.3, 0.3) end
        return
    end
    if not bg then return end
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    if s.healthColorMode == "dark" then
        bg:SetColorTexture(EllesmereUI.GetDarkModeBg())
    else
        -- Class-colored when bgClassColored is on, else the custom bg color
        -- (GetBgColor handles the secret-value guard + alpha = bgDarkness). Must
        -- match the layout-pass and preview paths so the per-unit UNIT_HEALTH
        -- refresh no longer clobbers the class-colored background back to custom.
        bg:SetColorTexture(ns.GetBgColor(unit, s))
    end
end

local function GetHealthColor(unit, s)
    local EllesmereUI = ns.EllesmereUI  -- upvalue read, not a global read (see taint note at top)
    s = s or db.profile
    local mode = s.healthColorMode or "class"

    if mode == "dark" then
        local dfr, dfg, dfb = EllesmereUI.GetDarkModeFill()
        return dfr, dfg, dfb
    elseif mode == "classic" then
        -- Native WoW health gradient via Blizzard's curve system (secret-value safe)
        local color = UnitHealthPercent(unit, true, GetClassicHealthCurve())
        if color and color.GetRGB then
            return color:GetRGB()
        end
        return 0, 1, 0
    elseif mode == "customDynamic" then
        -- User-customizable gradient via the same secret-safe curve path as Classic
        local color = UnitHealthPercent(unit, true, ns.GetCustomDynamicCurve(s))
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

-- UTF-8 aware character-count cap for an in-frame display name. Shared by the
-- live frames (via ResolveDisplayName) and every preview surface so they stay in
-- sync. Skips secret strings entirely (#, string.byte and string.sub all throw
-- on a secret value), so a secret name is shown verbatim and uncapped. The cap
-- reads db.profile.nameMaxLength (0 = off). On ns (not a file-scope local) to
-- stay clear of the main-chunk 200-local cap.
function ns.CapName(display)
    if type(display) ~= "string" then return display end
    if issecretvalue and issecretvalue(display) then return display end
    if display == "" then return display end
    local maxLen = db and db.profile and db.profile.nameMaxLength or 15
    if not maxLen or maxLen <= 0 then return display end
    local bytes = #display
    local i, chars, endByte = 1, 0, nil
    while i <= bytes do
        local b = string.byte(display, i)
        local sz = (b < 128 and 1) or (b < 224 and 2) or (b < 240 and 3) or 4
        chars = chars + 1
        if chars == maxLen then endByte = i + sz - 1; break end
        i = i + sz
    end
    if endByte and endByte < bytes then
        return string.sub(display, 1, endByte)
    end
    return display
end

-- Fraction of the frame width the NAME text may fill before it auto-truncates.
-- 1.0 = the full frame width (names truncate only at 100%). Every name-width
-- SetWidth routes through this single knob; health text keeps its own inline
-- budget. On ns (not a file-scope local) to stay clear of the 200-local cap.
ns.RF_NAME_WIDTH_FRACTION = 1.0

-- Resolve the display name for a unit. Nickname sources are consulted in order:
-- Northern Sky Raid Tools (NSAPI) first, then MethodInternal (EasyNicknameAPI),
-- then Timeline Reminders (TimelineReminders), then the Liquid addon (LiquidAPI),
-- falling back to the short character name. For
-- NSRT we pass our addon key "EUI" (NSRT added a dedicated per-addon setting +
-- EUI_NICKNAME_TOGGLE callback for us): NSAPI:GetName self-gates on NSRT's Global
-- Nicknames AND its EUI checkbox, so the user controls nicknames entirely through
-- NSRT (no EUI-side toggle). GetName returns the short name when no nickname is set,
-- which falls through to the next source. Each source is gated entirely by its own
-- addon (no EUI-side toggle), and pcall keeps a misbehaving external API from ever
-- breaking name rendering.
local function ResolveDisplayName(unit, applyCap)
    local name = UnitName(unit) or ""
    local display
    if NSAPI and NSAPI.GetName then
        local ok, dn = pcall(NSAPI.GetName, NSAPI, name, "EUI")
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" and dn ~= name then
            display = dn
        end
    end
    -- MethodInternal nicknames (EasyNicknameAPI), consulted after NSRT and before
    -- Timeline Reminders.
    if not display and EasyNicknameAPI and EasyNicknameAPI.GetNicknameForUnit then
        local ok, dn = pcall(EasyNicknameAPI.GetNicknameForUnit, unit)
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" and dn ~= name then
            display = dn
        end
    end
    -- Timeline Reminders nicknames (consulted when earlier sources did not
    -- produce a nickname). Gated by TR's own EllesmereUI checkbox, so the user
    -- controls these entirely through TR (no EUI-side toggle). GetNickname falls
    -- back to the plain unit name when no nickname is set, so HasNickname is
    -- checked first to keep the normal Ambiguate path for un-nicknamed units.
    if not display then
        local TR = TimelineReminders
        if TR and TR.GetNickname and TR.HasNickname and TR.NicknamesEnabledForAddOn then
            local okGate, enabled = pcall(TR.NicknamesEnabledForAddOn, TR, ns.NICK_ADDON)
            if okGate and enabled then
                local okHas, has = pcall(TR.HasNickname, TR, unit)
                if okHas and has then
                    local ok, dn = pcall(TR.GetNickname, TR, unit)
                    if ok and type(dn) == "string"
                       and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
                        display = dn
                    end
                end
            end
        end
    end
    -- Liquid addon nicknames (consulted when NSRT and TR did not produce one).
    -- LiquidAPI.GetNicknameForEllesmereUI takes the raw UnitName string and returns
    -- a nickname string, or nil for: no nickname set, nicknames disabled in the
    -- Liquid addon, a secret name, or an empty name. It does all of that gating
    -- itself, so we just pcall-wrap it (dot call, single arg -- not a method) and
    -- re-check the result is a clean, non-empty string as defense in depth.
    if not display and LiquidAPI and LiquidAPI.GetNicknameForEllesmereUI then
        local ok, dn = pcall(LiquidAPI.GetNicknameForEllesmereUI, name)
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
            display = dn
        end
    end
    if not display then
        if Ambiguate then name = Ambiguate(name, "short") end
        display = name
    end
    -- Cap only the in-frame name (applyCap), not the top name bar banner.
    if applyCap then display = ns.CapName(display) end
    return display
end

-- Background color: class color when bgClassColored, else the custom bg color.
-- Returns r, g, b, a (alpha = bgDarkness). Mirrors the health-fill class option.
function ns.GetBgColor(unit, s)
    s = s or db.profile
    local a = (s.bgDarkness or 50) / 100
    if s.bgClassColored and unit and UnitExists(unit) then
        local _, classToken = UnitClass(unit)
        -- classToken can be a secret value (out-of-range/uninspectable units);
        -- indexing GetClassColor's tables with a secret throws "table index is
        -- secret". Guard it and fall back to the custom bg color when secret/nil.
        if classToken and not issecretvalue(classToken) then
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then return cc.r, cc.g, cc.b, a end
        end
    end
    local c = s.customBgColor
    return c.r, c.g, c.b, a
end

local function GetNameColor(unit, s)
    local EllesmereUI = ns.EllesmereUI  -- upvalue read, not a global read (see taint note at top)
    s = s or db.profile
    local mode = s.nameColorMode or "class"
    if mode == "accent" then
        local r, g, b = EllesmereUI.ResolveActiveAccent()
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

-- Class/custom color resolution for the Top Name Bar text (no accent mode).
local function GetTopNameBarColor(unit, s)
    s = s or db.profile
    if (s.topNameBarTextColorMode or "class") == "custom" then
        local c = s.topNameBarTextColor or { r = 1, g = 1, b = 1 }
        return c.r, c.g, c.b
    end
    local _, classToken = UnitClass(unit)
    if classToken then
        local cc = EllesmereUI.GetClassColor(classToken)
        if cc then return cc.r, cc.g, cc.b end
    end
    return 1, 1, 1
end

-- Reserve the Top Name Bar's height from the TOP of a frame (the way the power
-- bar reserves from the bottom) and style the bar. Shared by the real buttons
-- and every preview surface so they never drift. Sets layout + appearance only;
-- the caller sets the unit-name text + color. Returns the reserved height (0 when
-- disabled). When disabled the health re-anchors flush to the top (offset 0), so
-- existing (top-bar-off) profiles are byte-identical to before.
local function LayoutTopNameBar(s, baseH, powerH, healthBar, tnb, tnbBg, tnbText)
    local enabled = s.topNameBarEnabled
    local topBarH = enabled and PixelSnap(s.topNameBarHeight or 20) or 0
    if healthBar then
        local parent = healthBar:GetParent()
        healthBar:ClearAllPoints()
        healthBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -topBarH)
        healthBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -topBarH)
        healthBar:SetHeight(PixelSnap(baseH - powerH - topBarH))
    end
    if not tnb then return topBarH end
    if not enabled then
        tnb:Hide()
        return topBarH
    end
    tnb:SetHeight(topBarH)
    if tnbBg then
        local bgc = s.topNameBarBgColor or {}
        tnbBg:SetColorTexture(bgc.r or 17/255, bgc.g or 17/255, bgc.b or 17/255, (s.topNameBarBgOpacity or 80) / 100)
    end
    if tnbText then
        ApplyFont(tnbText, s.topNameBarTextSize or 11)
        local align = s.topNameBarTextAlign or "center"
        local ox = s.topNameBarTextOffsetX or 0
        local oy = s.topNameBarTextOffsetY or 0
        tnbText:ClearAllPoints()
        if align == "left" then
            tnbText:SetPoint("LEFT", tnb, "LEFT", 4 + ox, oy); tnbText:SetJustifyH("LEFT")
        elseif align == "right" then
            tnbText:SetPoint("RIGHT", tnb, "RIGHT", -4 + ox, oy); tnbText:SetJustifyH("RIGHT")
        else
            tnbText:SetPoint("CENTER", tnb, "CENTER", ox, oy); tnbText:SetJustifyH("CENTER")
        end
        tnbText:SetJustifyV("MIDDLE")
        -- Force re-layout on a JustifyH change (WoW doesn't relayout otherwise)
        local cur = tnbText:GetText()
        if cur then tnbText:SetText(""); tnbText:SetText(cur) end
    end
    tnb:Show()
    return topBarH
end

-- Live name refresh for every raid + party button. Fired by the NSRT nickname
-- callback so added/removed nicknames apply instantly without a /reload.
function ns.RefreshAllNames()
    local s = db and db.profile
    if not s then return end
    local function refresh(unit, btn)
        local d = GetFFD(btn)
        if d and d.nameText then
            d.nameText:SetText(ResolveDisplayName(unit, true))
            local nr, ng, nb = GetNameColor(unit, s)
            d.nameText:SetTextColor(nr, ng, nb)
        end
        if d and d.topNameBarText and s.topNameBarEnabled then
            d.topNameBarText:SetText(ResolveDisplayName(unit))
            local tr, tg, tb = GetTopNameBarColor(unit, s)
            d.topNameBarText:SetTextColor(tr, tg, tb)
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
        local r, g, b = EllesmereUI.ResolveActiveAccent()
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

-- Heal absorb text color (mirrors GetHealthTextColor). Default mode "custom"
function ns.GetHealAbsorbTextColor(unit, s)
    s = s or db.profile
    local mode = s.healAbsorbTextColorMode or "custom"
    if mode == "accent" then
        local r, g, b = EllesmereUI.ResolveActiveAccent()
        if r then return r, g, b end
        return 1, 0.3, 0.3
    elseif mode == "class" then
        local _, classToken = UnitClass(unit)
        if classToken then
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then return cc.r, cc.g, cc.b end
        end
        return 1, 0.3, 0.3
    else -- "custom"
        local c = s.healAbsorbTextCustomColor
        if c then return c.r, c.g, c.b end
        return 1, 0.3, 0.3
    end
end

-- Anchor a FontString to the health bar using the shared 8-position scheme.
-- Mirrors FB.AnchorText (defined later, after the friendly-boss subsystem) so
-- heal-absorb text in the early frame-build path can anchor identically. An
-- optional width clamps long "amount"-mode values like the health text does.
function ns.AnchorRFText(fs, health, pos, ox, oy, width)
    if not fs or not health then return end
    fs:ClearAllPoints()
    if width then fs:SetWidth(width); fs:SetHeight(0) end
    ox = ox or 0; oy = oy or 0
    if pos == "topleft" then
        fs:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    elseif pos == "top" then
        fs:SetPoint("TOP", health, "TOP", ox, -2 + oy)
        fs:SetJustifyH("CENTER"); fs:SetJustifyV("TOP")
    elseif pos == "topright" then
        fs:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
        fs:SetJustifyH("RIGHT"); fs:SetJustifyV("TOP")
    elseif pos == "left" then
        fs:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("MIDDLE")
    elseif pos == "right" then
        fs:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
        fs:SetJustifyH("RIGHT"); fs:SetJustifyV("MIDDLE")
    elseif pos == "bottomleft" then
        fs:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("BOTTOM")
    elseif pos == "bottom" then
        fs:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
        fs:SetJustifyH("CENTER"); fs:SetJustifyV("BOTTOM")
    elseif pos == "bottomright" then
        fs:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
        fs:SetJustifyH("RIGHT"); fs:SetJustifyV("BOTTOM")
    else -- "center"
        fs:SetPoint("CENTER", health, "CENTER", ox, oy)
        fs:SetJustifyH("CENTER"); fs:SetJustifyV("MIDDLE")
    end
    -- Force re-render after a JustifyH change (mirrors the name/health text fns).
    local txt = fs:GetText()
    fs:SetText(""); fs:SetText(txt or "")
end

-- Format a heal-absorb amount into a FontString. mode: "amount" (full number),
-- "short" (abbreviated like 240k), "none"/nil (blank). Hidden at zero:
-- C_StringUtil.TruncateWhenZero blanks the value at zero. The amount it returns
-- (and thus GetText afterwards) is a SECRET string for a secret absorb, so we
-- may ONLY feed it to SetText or test its truthiness -- never compare it (== ""
-- taints). For "short" we read GetText back and gate on truthiness alone: it is
-- non-nil exactly when the absorb is non-zero, so we abbreviate only then.
function ns.FormatHealAbsorbInto(fs, amt, mode)
    if not fs then return end
    if not mode or mode == "none" then fs:SetText(""); return end
    fs:SetText(C_StringUtil.TruncateWhenZero(amt or 0))
    if mode == "short" and AbbreviateNumbers and fs:GetText() then
        fs:SetText(AbbreviateNumbers(amt or 0))
    end
end

-- Render the live heal-absorb text on a real frame (value from the unit).
function ns.SetHealAbsorbText(fs, unit, s)
    if not fs then return end
    local mode = s.healAbsorbTextMode or "none"
    ns.FormatHealAbsorbInto(fs, (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit)) or 0, mode)
    if mode ~= "none" then
        local r, g, b = ns.GetHealAbsorbTextColor(unit, s)
        fs:SetTextColor(r, g, b, 0.9)
    end
end

-- Update one button's heal-absorb text using the correct scaled profile. Called
-- from the absorb-only event path (UNIT_HEAL_ABSORB_AMOUNT_CHANGED), which does
-- NOT run a full button update, so the text would otherwise miss the change.
function ns.UpdateHealAbsorbTextFor(button, unit)
    local d = GetFFD(button)
    if not d.healAbsorbText then return end
    if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
        d.healAbsorbText:SetText("")
        return
    end
    local s = (d._isParty and ns._scaledPartyProxy)
        or (d._isExtra and ns._scaledExtraProxy)
        or ns._scaledProfile or db.profile
    ns.SetHealAbsorbText(d.healAbsorbText, unit, s)
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
--  Absorb style application
--  Single-fill styles match the unit-frame look. The RaidFrames-only compound
--  "Blizzard (Modern)" style layers a tiled stripe fill over a solid base, so
--  RF diverges from the UnitFrames module (which still offers only "Blizzard").
-------------------------------------------------------------------------------

-- Configure ONE absorb StatusBar for the compound "Blizzard (Modern)" style:
-- a tiled 9196ff striped fill over an opaque c6c8ff solid base. The base is our
-- own texture (._modernBase, colored once at creation); here we re-establish the
-- striped fill (the bar's fill is shared with the other styles, so it must be
-- restored when switching back to modern) and anchor the base to the fill rect
-- so it rides the same clip/mask geometry the secret SetValue drives -- no Lua
-- math on the secret. Colors are hardcoded; this style ignores user color/opacity.
ns.ApplyModernAbsorbBar = function(bar, mask)
    if not bar then return end
    bar:SetStatusBarTexture(ABSORB_STYLE_TEX.striped)
    bar:SetStatusBarColor(0.569, 0.588, 1.0, 1)
    local fill = bar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 1)
        fill:SetHorizTile(true)
        fill:SetVertTile(true)
        if mask then fill:AddMaskTexture(mask) end
        local base = bar._modernBase
        if base then base:SetAllPoints(fill); base:Show() end
    end
end

-- Hide the modern solid base whenever a non-modern style is applied so that
-- switching away from "Blizzard (Modern)" leaves no stale layer behind.
ns.HideModernAbsorbBase = function(bar)
    if bar and bar._modernBase then bar._modernBase:Hide() end
end

local function ApplyAbsorbStyle(absorbBar, style, settings)
    if not absorbBar then return end
    local mask = absorbBar._absorbMask
    local fw = absorbBar._forward

    -- "Default Blizz Frames": forward (missing-health shield) = compound modern
    -- texture (c6c8ff base + 9196ff stripes); backfill (overshield over existing
    -- health) = flat 10% white overlay instead of the texture.
    if style == "blizzardModern" then
        if fw then ns.ApplyModernAbsorbBar(fw, mask) end
        ns.HideModernAbsorbBase(absorbBar)
        absorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        absorbBar:SetStatusBarColor(1, 1, 1, 0.10)
        local bfFill = absorbBar:GetStatusBarTexture()
        if bfFill then
            bfFill:SetDrawLayer("ARTWORK", 1)
            bfFill:SetHorizTile(false); bfFill:SetVertTile(false)
            if mask then bfFill:AddMaskTexture(mask) end
        end
        return
    end

    -- Every other style is a single fill texture; ensure the modern base is off.
    ns.HideModernAbsorbBase(absorbBar)
    if fw then ns.HideModernAbsorbBase(fw) end

    local tex = ns.ResolveAbsorbStyleTex(style, "Interface\\Buttons\\WHITE8X8")
    local alpha = settings and (settings.absorbOpacity or 90) / 100 or (ABSORB_STYLE_ALPHA[style] or 0.8)
    local ac = settings and settings.absorbColor or { r = 1, g = 1, b = 1 }
    absorbBar:SetStatusBarTexture(tex)
    absorbBar:SetStatusBarColor(ac.r, ac.g, ac.b, alpha)
    local tiled = (style == "striped" or style == "stripedReversed" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR")
    local fill = absorbBar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 1)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
        if mask then fill:AddMaskTexture(mask) end
    end
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
    local tex = ns.ResolveAbsorbStyleTex(style, "Interface\\Buttons\\WHITE8X8")
    local alpha = settings and (settings.healAbsorbOpacity or 75) / 100 or 0.65
    local hc = settings and settings.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
    -- "Default Blizz Frames" and "Large Outlined Stripes" heal styles are
    -- pre-colored: hardcoded white tint (their color swatch is disabled).
    if style == "healBlizzModern" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" then hc = { r = 1, g = 1, b = 1 } end
    local mask = haBar._absorbMask
    haBar:SetStatusBarTexture(tex)
    haBar:SetStatusBarColor(hc.r, hc.g, hc.b, alpha)
    local tiled = (style == "striped" or style == "stripedReversed" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR")
    local fill = haBar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 2)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
        if mask then fill:AddMaskTexture(mask) end
    end
end

-- Reduced max-health overlay style. A 1:1 set of the heal-absorb textures plus
-- the dedicated "Max Health Stripes" texture; the bar is always right-anchored
-- (caller sets ReverseFill). Color swatch tints the texture, the slider drives
-- texture opacity (the backing opacity is applied by the caller, like heal
-- absorb). Pre-colored styles (Default Blizz Frames / Large Outlined) force white.
ns.ApplyMaxHealthStyle = function(bar, style, settings)
    if not bar then return end
    style = style or "maxHealthStripes"
    local tex, tiled
    if style == "maxHealthStripes" then
        tex = "Interface\\AddOns\\EllesmereUIRaidFrames\\Media\\striped-maxhp.png"
        tiled = true
    else
        tex = ns.ResolveAbsorbStyleTex(style, "Interface\\Buttons\\WHITE8X8")
        tiled = (style == "striped" or style == "stripedReversed" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR")
    end
    local alpha = settings and (settings.maxHealthOpacity or 100) / 100 or 1
    local mc = settings and settings.maxHealthColor or { r = 0.7, g = 0.1, b = 0.1 }
    if style == "healBlizzModern" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" then mc = { r = 1, g = 1, b = 1 } end
    bar:SetStatusBarTexture(tex)
    bar:SetStatusBarColor(mc.r, mc.g, mc.b, alpha)
    local fill = bar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 3)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
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
    -- Compound "Blizzard (Modern)" solid base (c6c8ff): drawn BEHIND the striped
    -- fill (ARTWORK sublevel 0 < fill sublevel 1). Masked once here; shown only
    -- when that style is active and re-anchored to the fill rect each update.
    local bfBase = backfillBar:CreateTexture(nil, "ARTWORK", nil, 0)
    bfBase:SetColorTexture(0.776, 0.784, 1.0, 1)
    if absorbMask then bfBase:AddMaskTexture(absorbMask) end
    bfBase:Hide()
    backfillBar._modernBase = bfBase
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
    -- Modern solid base (c6c8ff) for the forward bar (see backfill above).
    local fwBase = forwardBar:CreateTexture(nil, "ARTWORK", nil, 0)
    fwBase:SetColorTexture(0.776, 0.784, 1.0, 1)
    if absorbMask then fwBase:AddMaskTexture(absorbMask) end
    fwBase:Hide()
    forwardBar._modernBase = fwBase
    forwardBar:SetStatusBarColor(1, 1, 1, 0.8)
    forwardBar:SetReverseFill(false)
    forwardBar:SetWidth(healthBar:GetWidth())
    forwardBar:SetHeight(healthBar:GetHeight())
    -- Match backfill: absorb renders above heal absorb/heal prediction and max health.
    forwardBar:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    forwardBar:Hide()

    -- "Default Blizz Frames" spark: a fixed 16px soft glow (cast_spark.tga, ADD blend)
    -- centered on the shield's left edge (the current-HP seam) -- half over health, half
    -- over the shield. It lives on its own non-clipping host above the shield so the
    -- health-side half isn't clipped by missClip; its CENTER is pinned to the forward
    -- bar's LEFT edge so it tracks the seam. It is itself a StatusBar fed the absorb with
    -- a tiny max, so ANY shield fills it 100% and no shield collapses it to nothing --
    -- self-gating off the secret absorb just like the shield bars, no boolean/mask.
    local sparkHost = CreateFrame("Frame", nil, healthBar)
    sparkHost:SetAllPoints(healthBar)
    sparkHost:SetClipsChildren(true)
    sparkHost:SetFrameLevel(healthBar:GetFrameLevel() + 4)
    -- Invisible gate bar (16px, centered on the seam): fed the absorb with a tiny max so
    -- its fill is binary -- a full 16px when ANY shield exists, zero when none. Only its
    -- fill GEOMETRY is used; it self-gates off the secret absorb like the shield bars.
    local gateBar = CreateFrame("StatusBar", nil, sparkHost)
    gateBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    gateBar:SetStatusBarColor(1, 1, 1, 0)
    gateBar:SetSize(16, healthBar:GetHeight())
    gateBar:SetMinMaxValues(0, 1)
    gateBar:SetValue(0)
    gateBar:SetPoint("CENTER", forwardBar, "LEFT", -1, 0)
    -- The visible spark: a cast_spark glow laid over the gate's fill rect, so it shows at
    -- a full 16px with any shield and collapses to nothing without one (cast_spark.tga
    -- renders as a plain texture but not as a StatusBar fill, hence the split).
    local edgeSpark = sparkHost:CreateTexture(nil, "OVERLAY")
    edgeSpark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    edgeSpark:SetBlendMode("ADD")
    edgeSpark:SetAllPoints(gateBar:GetStatusBarTexture())
    edgeSpark:Hide()
    forwardBar._edgeSpark = edgeSpark
    forwardBar._edgeGate = gateBar
    -- Overshield spark: when the absorb overshields, the backfill spreads left over your
    -- existing health; this rides the backfill's LEFT edge (the inner edge of the whole
    -- shield). Shown only while overshielding; the seam spark hides then, so only one
    -- spark is ever visible. Re-anchored to the backfill fill each update.
    local bfSpark = sparkHost:CreateTexture(nil, "OVERLAY")
    bfSpark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    bfSpark:SetBlendMode("ADD")
    bfSpark:SetSize(16, healthBar:GetHeight())
    bfSpark:SetPoint("CENTER", forwardBar, "LEFT", -1, 0)
    bfSpark:Hide()
    forwardBar._bfSpark = bfSpark

    -- Absorb Bar: solid bar above the frame showing the shield amount,
    -- filling from the right edge. Always created (hidden) so toggling the
    -- setting on later needs no rebuild; UpdateAbsorb drives it.
    local topBar = CreateFrame("StatusBar", nil, button)
    topBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    topBar:SetStatusBarColor(1, 1, 1, 1)
    topBar:SetReverseFill(true)
    topBar:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 0)
    topBar:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 0)
    topBar:SetHeight(4)
    topBar:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    topBar:Hide()

    -- Heal Absorb Bar: a second strip (mirrors the Absorb Bar) showing the
    -- heal-absorb amount. Always created hidden; UpdateAbsorb drives it.
    local healTopBar = CreateFrame("StatusBar", nil, button)
    healTopBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    healTopBar:SetStatusBarColor(200/255, 29/255, 29/255, 1)
    healTopBar:SetReverseFill(true)
    healTopBar:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 0)
    healTopBar:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 0)
    healTopBar:SetHeight(4)
    healTopBar:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    healTopBar:Hide()

    -- Forward-declared so ReanchorAbsorbToFill (defined just below) captures
    -- these as upvalues. The bars are created further down; until then the
    -- nil guards inside ReanchorAbsorbToFill simply skip them. Without this,
    -- they resolved to globals (nil) inside the closure, so the heal absorb
    -- never re-anchored to the right edge in "Show Absorbs from Right Edge".
    local healAbsorbBar, healPredBar, healClip

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
        -- Shield absorb placement (independent of heal absorb).
        --   overlay = backfill into the filled health from the HP edge (default)
        --   right   = full bar, fill from the frame's right edge
        --   left    = full bar, fill from the frame's left edge
        local absorbMode = db.profile.absorbEdgeMode or "overlay"
        if absorbMode == "right" or absorbMode == "left" then
            curClip:ClearAllPoints()
            curClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            curClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            backfillBar:ClearAllPoints()
            if absorbMode == "left" then
                backfillBar:SetReverseFill(false)
                backfillBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                backfillBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
            else
                backfillBar:SetReverseFill(true)
                backfillBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                backfillBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            end
        else
            -- Overlay: curClip already clipped to the fill above. Restore the
            -- backfill's default right-anchored reverse fill (reset if the mode
            -- was previously left).
            backfillBar:SetReverseFill(true)
            backfillBar:ClearAllPoints()
            backfillBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            backfillBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        end

        -- Heal absorb placement (independent of shield absorb). Its own clip
        -- frame spans the full bar for right/left, filled health for overlay.
        if healAbsorbBar then
            local healMode = db.profile.healAbsorbEdgeMode or "overlay"
            if healClip then
                healClip:ClearAllPoints()
                if healMode == "right" or healMode == "left" then
                    healClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                    healClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
                else
                    healClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                    healClip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
                end
            end
            healAbsorbBar:ClearAllPoints()
            if healMode == "right" then
                healAbsorbBar:SetReverseFill(true)
                healAbsorbBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                healAbsorbBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            elseif healMode == "left" then
                healAbsorbBar:SetReverseFill(false)
                healAbsorbBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                healAbsorbBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
            else
                -- Overlay (default): eat into the filled health from the HP edge.
                healAbsorbBar:SetReverseFill(true)
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
            -- Missing Health clamp: GetDamageAbsorbs' 2nd return is then the standard
            -- "overshield" boolean (absorb exceeds your empty health) -- consistent in
            -- and out of combat. Bars are fed the FULL absorb (UnitGetTotalAbsorbs) so
            -- overflow/backfill still renders.
            hpCalc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)
        end
    end

    -- Heal absorb has its OWN clip frame (not the shield's curClip) so its
    -- placement is independent: overlay clips to the filled health, while
    -- right/left span the FULL bar (filled + missing health). Bounds are set
    -- per healAbsorbEdgeMode in ReanchorAbsorbToFill (initial = overlay).
    healClip = CreateFrame("Frame", nil, healthBar)
    healClip:SetClipsChildren(true)
    healClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
    healClip:SetPoint("BOTTOMRIGHT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    -- Heal absorb bar: red overlay eating into filled health
    healAbsorbBar = CreateFrame("StatusBar", nil, healClip)
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
    healAbsorbBar._lastOverDispel = false  -- "Show Over Dispels" applied state; off = created level
    healAbsorbBar:Hide()

    -- Black backing behind the heal-absorb texture (all styles; opacity user-set via
    -- healAbsorbBgOpacity). Drawn UNDER the fill (ARTWORK sublevel 1 < the fill's 2),
    -- masked + SetAllPoints'd to the fill rect each update so it tracks the secret
    -- heal-absorb amount and collapses to nothing when there is none.
    local haBg = healAbsorbBar:CreateTexture(nil, "ARTWORK", nil, 1)
    haBg:SetColorTexture(0, 0, 0, 0.25)
    if absorbMask then haBg:AddMaskTexture(absorbMask) end
    haBg:Hide()
    healAbsorbBar._bg = haBg

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
    backfillBar._topBar       = topBar
    backfillBar._healTopBar   = healTopBar
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
--  Absorb Bar position (replaces the old on/off toggle)
--  Positions: none / aboveRight / aboveLeft / topRight / topLeft /
--  rightVertical / leftVertical (vertical side bar; fill direction comes
--  from the per-bar grow-direction setting, default up).
--  Legacy: the old boolean (absorbBarEnabled) maps to "aboveRight" when on and
--  "none" when off. The new key (absorbBarPosition) takes precedence once the
--  user picks one, so existing settings carry over with no migration.
-------------------------------------------------------------------------------
-- Absorb / Heal Absorb Bar position resolvers + strip layout. Defined on ns (no
-- new file-scope locals -- this chunk is at Lua's 200-local cap).
-- Legacy: the old boolean (absorbBarEnabled) maps to "aboveRight" when on and
-- "none" when off; absorbBarPosition takes precedence once the user picks one.
ns.GetAbsorbBarPosition = function(s)
    local p = s and s.absorbBarPosition
    if p then return p end
    return (s and s.absorbBarEnabled) and "aboveRight" or "none"
end
ns.GetHealAbsorbBarPosition = function(s)
    return (s and s.healAbsorbBarPosition) or "none"
end

-- Anchor/orient a strip bar (Absorb Bar or Heal Absorb Bar) for a position.
-- "above*" sit on top of the frame (bottom edge on the button's top edge);
-- "top*" sit inside at the top of the health bar, drawn just above the
-- absorb-style texture. "belowAbsorb" (heal bar only) sits flush below the
-- Absorb Bar's bottom edge, derived from the Absorb Bar's POSITION -- not its
-- live visibility, so it never shifts up. "*Right" fills from the right edge.
-- "*Vertical" hug the health bar's left/right edge as a vertical bar
-- (Grid2-style side bar); "height" acts as its width and vertGrowDir
-- ("up" default / "down", per bar) picks the fill direction.
ns.ApplyStripBarLayout = function(stripBar, ab, button, position, height, absorbPos, absorbHeight, vertGrowDir)
    if not stripBar then return end
    local hp = ab._hpBar or button
    stripBar:ClearAllPoints()
    if position == "rightVertical" or position == "leftVertical" then
        stripBar:SetOrientation("VERTICAL")
        stripBar:SetReverseFill(vertGrowDir == "down")
        stripBar:SetWidth(PixelSnap(height or 4))
        if position == "rightVertical" then
            stripBar:SetPoint("TOPRIGHT", hp, "TOPRIGHT", 0, 0)
            stripBar:SetPoint("BOTTOMRIGHT", hp, "BOTTOMRIGHT", 0, 0)
        else
            stripBar:SetPoint("TOPLEFT", hp, "TOPLEFT", 0, 0)
            stripBar:SetPoint("BOTTOMLEFT", hp, "BOTTOMLEFT", 0, 0)
        end
        stripBar:SetFrameLevel(ab:GetFrameLevel() + 1)
        return
    end
    stripBar:SetOrientation("HORIZONTAL")
    stripBar:SetHeight(PixelSnap(height or 4))
    if position == "belowAbsorb" then
        absorbPos = absorbPos or "none"
        -- "above" absorb bottom = frame top edge (yOff 0); "top" (inside) absorb
        -- bottom = one absorb-height below the top edge.
        local yOff = 0
        if absorbPos == "topRight" or absorbPos == "topLeft" then
            yOff = -PixelSnap(absorbHeight or 4)
        end
        -- Match the Absorb Bar's fill direction so the pair lines up.
        stripBar:SetReverseFill(absorbPos ~= "aboveLeft" and absorbPos ~= "topLeft")
        stripBar:SetPoint("TOPLEFT", button, "TOPLEFT", 0, yOff)
        stripBar:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, yOff)
        stripBar:SetFrameLevel(ab:GetFrameLevel() + 1)
    elseif position == "topRight" or position == "topLeft" then
        stripBar:SetReverseFill(position == "topRight")
        stripBar:SetPoint("TOPLEFT", hp, "TOPLEFT", 0, 0)
        stripBar:SetPoint("TOPRIGHT", hp, "TOPRIGHT", 0, 0)
        stripBar:SetFrameLevel(ab:GetFrameLevel() + 1)
    else
        stripBar:SetReverseFill(position == "aboveRight")
        stripBar:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 0)
        stripBar:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 0)
        if ab._hpBar then stripBar:SetFrameLevel(ab._hpBar:GetFrameLevel() + 3) end
    end
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

    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    local topBar = ab._topBar
    local barPos = ns.GetAbsorbBarPosition(s)
    local barOn = topBar and barPos ~= "none"
    local healTopBar = ab._healTopBar
    local healBarPos = ns.GetHealAbsorbBarPosition(s)
    local healBarOn = healTopBar and healBarPos ~= "none"
    local styleOn = s.absorbStyle and s.absorbStyle ~= "none"
    -- Heal absorb is INDEPENDENT of the shield absorb (matches Unit Frames):
    -- it renders whenever its own style is on, so keep going if it is enabled
    -- even when both the shield style and the Absorb Bar are off.
    local healOn = (s.healAbsorbStyle or "clean") ~= "none"
    if not styleOn and not barOn and not healOn and not healBarOn then
        ab:Hide()
        if fw then fw:Hide() end
        if fw and fw._edgeSpark then fw._edgeSpark:Hide() end
        if fw and fw._bfSpark then fw._bfSpark:Hide() end
        if ha then ha:Hide() end
        if topBar then topBar:Hide() end
        if healTopBar then healTopBar:Hide() end
        return
    end

    local maxHealth, absorbAmt, isClamped
    if calc and UnitGetDetailedHealPrediction then
        UnitGetDetailedHealPrediction(unit, nil, calc)
        calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
        maxHealth = calc:GetMaximumHealth()
        -- 2nd return (Missing Health clamp) = secret-safe overshield boolean.
        local _, clampedBool = calc:GetDamageAbsorbs()
        isClamped = clampedBool
        -- Bars get the FULL absorb so the overflow/backfill renders correctly.
        absorbAmt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0
    else
        maxHealth = UnitHealthMax(unit) or 0
        absorbAmt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0
    end

    -- Absorb Bar: solid bar above the frame, fills from the right edge.
    -- Fed raw values (secret-safe); a zero absorb renders as an empty bar.
    if topBar then
        if barOn then
            local bc = s.absorbBarColor or { r = 1, g = 1, b = 1 }
            local bh = s.absorbBarHeight or 4
            local gd = s.absorbBarGrowDir or "up"
            -- Re-layout only when position/height/direction changes (no per-update SetPoint churn).
            if topBar._lpPos ~= barPos or topBar._lpH ~= bh or topBar._lpGD ~= gd then
                topBar._lpPos = barPos; topBar._lpH = bh; topBar._lpGD = gd
                ns.ApplyStripBarLayout(topBar, ab, button, barPos, bh, nil, nil, gd)
            end
            topBar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a or 1)
            topBar:SetMinMaxValues(0, maxHealth)
            topBar:SetValue(absorbAmt)
            topBar:Show()
        else
            topBar:Hide()
        end
    end

    -- Heal Absorb Bar: solid strip showing the heal-absorb amount, independent of
    -- the heal-absorb overlay style (mirrors the Absorb Bar). "Below Absorb Bar"
    -- positions it relative to the Absorb Bar's slot.
    if healTopBar then
        if healBarOn then
            local hbc = s.healAbsorbBarColor or { r = 200/255, g = 29/255, b = 29/255 }
            local hbh = s.healAbsorbBarHeight or 4
            local abh = s.absorbBarHeight or 4
            local hgd = s.healAbsorbBarGrowDir or "up"
            -- Re-layout only when its or the Absorb Bar's position/height changes.
            if healTopBar._lpPos ~= healBarPos or healTopBar._lpH ~= hbh
               or healTopBar._lpAP ~= barPos or healTopBar._lpAH ~= abh
               or healTopBar._lpGD ~= hgd then
                healTopBar._lpPos = healBarPos; healTopBar._lpH = hbh
                healTopBar._lpAP = barPos; healTopBar._lpAH = abh
                healTopBar._lpGD = hgd
                ns.ApplyStripBarLayout(healTopBar, ab, button, healBarPos, hbh, barPos, abh, hgd)
            end
            healTopBar:SetStatusBarColor(hbc.r, hbc.g, hbc.b, hbc.a or 1)
            healTopBar:SetMinMaxValues(0, maxHealth)
            healTopBar:SetValue((UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit)) or 0)
            healTopBar:Show()
        else
            healTopBar:Hide()
        end
    end

    -- Heal absorb renders INDEPENDENTLY of the shield absorb / Absorb Bar, so it
    -- shows whenever its own style is enabled (even with shield Absorb Style
    -- "none"). Drawn under the shield bars (heal level +1 < shield +3). Done
    -- before the shield gate below so it survives when the shield style is off.
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
            -- "Show Over Dispels" (default off): lift the heal-absorb overlay one
            -- level above the dispel gradient (button + LVL_DISPEL_OVERLAY = +7),
            -- staying below the border/text/auras and masked to the bar interior.
            -- Tracked per-bar so the level is only touched when the toggle flips;
            -- when off the bar stays at its created level, unchanged from before.
            local overDispel = s.healAbsorbOverDispel == true
            if ha._lastOverDispel ~= overDispel then
                ha._lastOverDispel = overDispel
                if overDispel then
                    ha:SetFrameLevel(button:GetFrameLevel() + ns.LVL_DISPEL_OVERLAY + 1)
                else
                    ha:SetFrameLevel(hp:GetFrameLevel() + 1)
                end
            end
            local healAbsorbAmt = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit) or 0
            ha:SetWidth(hp:GetWidth()); ha:SetHeight(hp:GetHeight())
            ha:SetMinMaxValues(0, maxHealth)
            ha:SetValue(healAbsorbAmt)
            ha:Show()
            -- Black backing: track the heal-absorb fill rect, opacity from settings.
            local hbg = ha._bg
            if hbg then
                hbg:SetColorTexture(0, 0, 0, (s.healAbsorbBgOpacity or 25) / 100)
                hbg:SetAllPoints(ha:GetStatusBarTexture())
                hbg:Show()
            end
        end
    end

    -- Absorb styles disabled: only the Absorb Bar is active. Keep the
    -- pre-existing behavior for the in-frame bars and stop here. Heal absorb is
    -- rendered above (independent), so this gate no longer hides it.
    if not styleOn then
        ab:Hide()
        if fw then fw:Hide() end
        if fw and fw._edgeSpark then fw._edgeSpark:Hide() end
        if fw and fw._bfSpark then fw._bfSpark:Hide() end
        return
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

    -- Show Overshield (opt-in, default ON). The "overshield" is the absorb that
    -- exceeds the empty health and backfills over current health -- drawn by the
    -- backfill bar (ab) in overlay + Default-Blizz modes. When the toggle is OFF
    -- we feed the backfill 0 so only the empty health fills; the forward bar (fw,
    -- clipped to the missing-health region) still caps exactly at the health-bar
    -- right edge. The right/left edge modes draw the WHOLE absorb through ab (fw
    -- is hidden below), so they are left untouched -- overshield is meaningless
    -- there. With the toggle ON this is byte-for-byte the previous behavior.
    local overshieldOn = s.showOvershield ~= false
    local overlayLike = absStyle == "blizzardModern" or (s.absorbEdgeMode or "overlay") == "overlay"
    local abValue = absorbAmt
    if not overshieldOn and overlayLike then abValue = 0 end

    -- Both bars get the raw absorb value and maxHealth.
    -- Clip frames do the visual math so we never compare secret values.
    ab:SetMinMaxValues(0, maxHealth)
    ab:SetValue(abValue)
    ab:Show()

    if fw then
        fw:SetMinMaxValues(0, maxHealth)
        fw:SetValue(absorbAmt)
        fw:Show()
    end
    -- Edge modes (right/left): the full-bar backfill shows the whole absorb, so
    -- the forward bar (overlay-only) is not needed.
    if (s.absorbEdgeMode or "overlay") ~= "overlay" and fw then fw:Hide() end

    -- "Default Blizz Frames": standard backfill + forward absorb (backfill = 10% white
    -- overshield, forward = modern texture). The spark always rides the LEFT edge of the
    -- shield: the seam spark (current-HP edge) self-gates on "has shield" and hides while
    -- overshielding; the overshield spark rides the backfill's left edge and shows only
    -- while overshielding. isClamped (the Missing-Health-clamp overshield boolean) flips
    -- between them secret-safely, so exactly one is ever visible.
    if absStyle == "blizzardModern" then
        if fw then
            local fmb = fw._modernBase
            if fmb then fmb:SetAllPoints(fw:GetStatusBarTexture()) end
            -- Seam spark: full 16px when any shield (binary gate), hidden while overshielding.
            local g, sp = fw._edgeGate, fw._edgeSpark
            if g and sp then
                g:SetHeight(hpH)
                g:SetValue(absorbAmt)
                sp:SetAllPoints(g:GetStatusBarTexture())
                if sp.SetAlphaFromBoolean then sp:SetAlphaFromBoolean(isClamped, 0, 1) else sp:SetAlpha(1) end
                sp:Show()
            end
            -- Overshield spark: normally rides the backfill's LEFT edge (slides
            -- left over the health fill as the overshield grows). With Show
            -- Overshield OFF the backfill is suppressed, so pin the glow to the
            -- health-bar RIGHT edge (ab spans the health bar) -- it stays put
            -- instead of sliding over the fill. Shown only while overshielding.
            local bsp = fw._bfSpark
            if bsp then
                bsp:SetSize(16, hpH)
                bsp:ClearAllPoints()
                if overshieldOn then
                    bsp:SetPoint("CENTER", ab:GetStatusBarTexture(), "LEFT", -1, 0)
                else
                    bsp:SetPoint("CENTER", ab, "RIGHT", -1, 0)
                end
                if bsp.SetAlphaFromBoolean then bsp:SetAlphaFromBoolean(isClamped, 1, 0) else bsp:SetAlpha(0) end
                bsp:Show()
            end
        end
    elseif fw and fw._edgeSpark then
        fw._edgeSpark:Hide()
        if fw._bfSpark then fw._bfSpark:Hide() end
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

    -- Reduced max health: styled overlay anchored to the right side. Texture /
    -- color / opacity / backing mirror Heal Absorb; re-styled only on change.
    local rmh = ab._reducedMax
    if rmh then
        local rmhStyle = s.maxHealthStyle or "maxHealthStripes"
        local lossPct = GetUnitTotalModifiedMaxHealthPercent and GetUnitTotalModifiedMaxHealthPercent(unit) or 0
        if rmhStyle ~= "none" and lossPct > 0 then
            local mc = s.maxHealthColor or { r = 0.7, g = 0.1, b = 0.1 }
            local rmhKey = rmhStyle .. (s.maxHealthOpacity or 100) .. mc.r .. mc.g .. mc.b
            if rmh._lastRmhKey ~= rmhKey then
                rmh._lastRmhKey = rmhKey
                ns.ApplyMaxHealthStyle(rmh, rmhStyle, s)
            end
            rmh:SetValue(lossPct)
            -- Backing: track the fill rect, opacity from settings (every update).
            local rmhBg = ab._reducedMaxBg
            if rmhBg then
                rmhBg:SetColorTexture(0, 0, 0, (s.maxHealthBgOpacity or 100) / 100)
                rmhBg:SetAllPoints(rmh:GetStatusBarTexture())
            end
            rmh:Show()
        else
            rmh:Hide()
        end
    end
end


-------------------------------------------------------------------------------
--  Debuff grid layout (shared by the live render and the options preview)
-------------------------------------------------------------------------------
-- Effective icon size for dispellable debuffs routed to their own anchor
-- ("Dispellable Debuff Location"): 0 = match the main Debuff Size. Reads
-- scaled proxies transparently (the key is in INDICATOR_SCALE_KEYS; 0 scales
-- to 0, so the match sentinel survives). On ns (200-local cap).
function ns.DispellableDebuffSize(s)
    local v = s.dispellableDebuffSize
    if v and v > 0 then return v end
    return s.debuffSize or 18
end

-- Mirrors the Buff Manager's AnchorSimpleGrid.
-- opts (optional) overrides pos/grow/ox/oy/size for a sub-group (e.g.
-- dispellable debuffs routed to their own anchor, which may carry its own
-- icon size); spacing/wrap/perRow stay shared.
function ns.DebuffGridPoint(s, idx0, total, opts)
    local pos    = (opts and opts.pos)  or s.debuffPosition or "bottomleft"
    local grow   = (opts and opts.grow) or s.debuffGrowDirection or "RIGHT"
    local sz     = (opts and opts.size) or s.debuffSize or 18
    local spc    = PixelSnap(s.debuffSpacing or 1)
    local step   = sz + spc
    local ox     = (opts and opts.ox) or s.debuffOffsetX or 0
    local oy     = (opts and opts.oy) or s.debuffOffsetY or 0
    local perRow = s.debuffPerRow or 1
    if perRow < 1 then perRow = 1 end

    -- Icon corner anchored to the same corner of the health bar. Every position
    -- is handled explicitly so the default fallback is only a safety net.
    local corner = "BOTTOMLEFT"
    if     pos == "topleft"     then corner = "TOPLEFT"
    elseif pos == "top"         then corner = "TOP"
    elseif pos == "topright"    then corner = "TOPRIGHT"
    elseif pos == "left"        then corner = "LEFT"
    elseif pos == "center"      then corner = "CENTER"
    elseif pos == "right"       then corner = "RIGHT"
    elseif pos == "bottomleft"  then corner = "BOTTOMLEFT"
    elseif pos == "bottom"      then corner = "BOTTOM"
    elseif pos == "bottomright" then corner = "BOTTOMRIGHT"
    end

    -- Growth vector (per column within a row), screen coords (+x right, +y up).
    -- CENTER grows horizontally like RIGHT but centers each row on the anchor.
    local horizontal = (grow ~= "UP" and grow ~= "DOWN")
    local gvx, gvy = 0, 0
    if     grow == "LEFT" then gvx = -1
    elseif grow == "UP"   then gvy = 1
    elseif grow == "DOWN" then gvy = -1
    else                       gvx = 1   -- RIGHT or CENTER
    end

    -- Row-stack vector (perpendicular). Explicit wrap direction wins; otherwise
    -- auto-derive away from the anchored edge.
    local svx, svy = 0, 0
    local wrap = s.debuffWrapDirection
    if     wrap == "UP"    then svy = 1
    elseif wrap == "DOWN"  then svy = -1
    elseif wrap == "RIGHT" then svx = 1
    elseif wrap == "LEFT"  then svx = -1
    elseif horizontal then
        if pos == "bottomleft" or pos == "bottom" or pos == "bottomright" then svy = 1 else svy = -1 end
    else
        if pos == "topright" or pos == "right" or pos == "bottomright" then svx = -1 else svx = 1 end
    end

    -- perRow == 1 is a single line ALONG the growth direction (no wrapping), so
    -- the growth control stays meaningful; >= 2 wraps into rows.
    local row, col
    if perRow <= 1 then
        row, col = 0, idx0
    else
        row = floor(idx0 / perRow)
        col = idx0 % perRow
    end
    local centerOff = 0
    if grow == "CENTER" then
        local rowCount = (perRow <= 1) and (total or 0) or min(perRow, max(0, (total or 0) - row * perRow))
        if rowCount > 0 then centerOff = -((rowCount - 1) * step) / 2 end
    end
    local along  = col * step
    local across = row * step
    local fx = ox + gvx * along + svx * across + centerOff
    local fy = oy + gvy * along + svy * across
    return corner, fx, fy
end

-------------------------------------------------------------------------------
--  Enable right-click camera movement over raid/party frames
--  A global mouse watcher: when the right button is pressed over 
--  one of our unit buttons and then dragged past a small threshold,
--  it starts mouselook (camera turn). It never touches the secure
--  buttons so it can't taint or interfere with click-casting.
--  A right-click tap is left alone, so the menu still opens.
-------------------------------------------------------------------------------
do
    local MOVE_THRESHOLD = 4
    local watcher = CreateFrame("Frame")
    local inLook = false
    local lastX, lastY = 0, 0

    local function stopLook()
        if inLook then MouselookStop(); inLook = false end
        watcher:SetScript("OnUpdate", nil)
    end

    -- True if the cursor is over one of our (visible) unit buttons. Uses a direct
    -- IsMouseOver test against our registry.
    local function overOwnFrame()
        local reg = ns._euiUnitButtons
        if not reg then return false end
        for btn in pairs(reg) do
            if btn:IsVisible() and btn:IsMouseOver() then return true end
        end
        return false
    end

    local function onUpdate()
        if not IsMouseButtonDown(2) then stopLook(); return end
        if inLook then return end
        local x, y = GetCursorPosition()
        if abs(x - lastX) > MOVE_THRESHOLD or abs(y - lastY) > MOVE_THRESHOLD then
            pcall(MouselookStart)
            inLook = true
        end
    end

    watcher:SetScript("OnEvent", function(_, event, button)
        if event == "GLOBAL_MOUSE_DOWN" then
            if button ~= "RightButton" then return end
            if not (db and db.profile and db.profile.freeRightClickCamera) then return end
            if not overOwnFrame() then return end
            inLook = false
            lastX, lastY = GetCursorPosition()
            watcher:SetScript("OnUpdate", onUpdate)
        elseif event == "GLOBAL_MOUSE_UP" then
            if button == "RightButton" then stopLook() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- safety: never leave mouselook stuck after a combat-state change
            if not IsMouseButtonDown(2) then stopLook() end
        elseif event == "PLAYER_LOGIN" then
            if ns.FRCM_Refresh then ns.FRCM_Refresh() end
        end
    end)
    watcher:RegisterEvent("PLAYER_LOGIN")

    -- Register the per-click global events only while the feature is on, so we
    -- don't run a handler on every click when it's disabled. Call on toggle.
    function ns.FRCM_Refresh()
        if db and db.profile and db.profile.freeRightClickCamera then
            watcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
            watcher:RegisterEvent("GLOBAL_MOUSE_UP")
            watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            watcher:UnregisterEvent("GLOBAL_MOUSE_DOWN")
            watcher:UnregisterEvent("GLOBAL_MOUSE_UP")
            watcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
            stopLook()
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

    -- Register our unit buttons so the free right-click camera watcher can tell
    -- when the cursor is over an EUI raid/party frame (direct IsMouseOver test).
    -- These are SecureGroupHeader/SecureUnitButton frames (Blizzard-owned), so
    -- membership is tracked in an external weak table, never a key on the button.
    ns._euiUnitButtons = ns._euiUnitButtons or setmetatable({}, { __mode = "k" })
    ns._euiUnitButtons[button] = true

    local s = db.profile
    -- The Anchor* closures below are stored on `d` and RE-CALLED after
    -- d._isParty / d._isExtra are set (StyleButton runs before that). They must
    -- resolve the settings source LIVE via LiveS() rather than capture this raid
    -- `s`, or party/extra frames would anchor every indicator, text and aura at
    -- the RAID position. The body keeps the raw `s` for creation-time sizing.
    local function LiveS()
        return d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    end
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

    -- Full-height anchor reference for Uniform Icon Anchoring: top tracks the
    -- health bar (so the Top Name Bar inset carries over), bottom pins to the
    -- button, i.e. exactly where the health bar sits when no power bar shows.
    -- ns.RF_AnchorHost swaps decorations onto it; _euiHealth points back for
    -- the few sites that must hug the real bar (full-overlay BM bars).
    d.uniformRef = CreateFrame("Frame", nil, button)
    d.uniformRef:SetFrameLevel(health:GetFrameLevel())
    d.uniformRef:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    d.uniformRef:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    health._euiUniformRef = d.uniformRef
    d.uniformRef._euiHealth = health

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

    -- Top Name Bar (ALWAYS created, hidden). The layout/refresh pass sizes it,
    -- reserves its height from the top of the health area, and shows it from the
    -- saved settings. The unit-name text is set in UpdateButton.
    do
        local tnb = CreateFrame("Frame", nil, button)
        tnb:SetFrameLevel(button:GetFrameLevel() + 4)
        tnb:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        tnb:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
        tnb:SetHeight(PixelSnap(s.topNameBarHeight or 20))
        local tnbBg = tnb:CreateTexture(nil, "BACKGROUND")
        tnbBg:SetAllPoints()
        if PP then PP.DisablePixelSnap(tnbBg) end
        local tnbText = tnb:CreateFontString(nil, "OVERLAY")
        ApplyFont(tnbText, s.topNameBarTextSize or 11)
        tnbText:SetWordWrap(false)
        d.topNameBar = tnb
        d.topNameBarBg = tnbBg
        d.topNameBarText = tnbText
        tnb:Hide()
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
    dispelIcon:SetSize(16, 16)
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
    -- Frame level sits BELOW the name/health text (LVL_DISPEL_OVERLAY = +7,
    -- text = +12) so the gradient renders behind text. RegisterDispelContainer
    -- re-applies this level and forces Blizzard to re-read it (no strata bump).
    if C_UnitAuras_AddPrivateAuraAnchor then
        local dcWrapper = CreateFrame("Frame", nil, button)
        dcWrapper:SetAllPoints(health)
        dcWrapper:SetFrameLevel(button:GetFrameLevel() + ns.LVL_DISPEL_OVERLAY)
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
        dcWrapper:SetAttribute("aura-organization-type", s.dispelOverlayPosition or 0)   -- 0=Top, 1=Bottom, 2=Left
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
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
        dispelIcon:ClearAllPoints()
        local sz = s.dispelIconSize or 16
        dispelIcon:SetSize(sz, sz)
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

    -- Text carrier: name + health text sit in the text band (ns.LVL_TEXT) --
    -- above every border including the hover/target raise, below the aura
    -- band so debuffs/BM icons draw over them.
    local textCarrier = CreateFrame("Frame", nil, button)
    textCarrier:SetAllPoints(health)
    textCarrier:SetFrameLevel(button:GetFrameLevel() + ns.LVL_TEXT)

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
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
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

    -- Heal absorb text (1:1 with health text; independent position/size/color).
    local healAbsorbFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(healAbsorbFS, s.healAbsorbTextSize or 9)
    healAbsorbFS:SetWordWrap(false)
    d.healAbsorbText = healAbsorbFS
    local function AnchorHealAbsorbText()
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
        ns.AnchorRFText(healAbsorbFS, health, s.healAbsorbTextPosition or "center",
            s.healAbsorbTextOffsetX or 0, s.healAbsorbTextOffsetY or 0, (s.frameWidth or 72) * 0.75)
    end
    AnchorHealAbsorbText()
    d.AnchorHealAbsorbText = AnchorHealAbsorbText

    -- Status text (DEAD / OFFLINE / AFK -- always shown, own position/size/color)
    local statusFS = health:CreateFontString(nil, "OVERLAY")
    local stc = s.statusTextColor or { r = 1, g = 1, b = 1 }
    ApplyFont(statusFS, s.statusTextSize or 14)
    statusFS:SetJustifyH("CENTER")
    statusFS:SetTextColor(stc.r, stc.g, stc.b)
    statusFS:Hide()
    d.statusText = statusFS

    local function AnchorStatusText()
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
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

    -- Role icon. Carrier sits in the text band (ns.LVL_AURA - 1 = ns.LVL_TEXT,
    -- same as the name/health text): above every border including the
    -- hover/target raise, while auras still draw over it.
    local roleCarrier = CreateFrame("Frame", nil, button)
    roleCarrier:SetAllPoints(health)
    roleCarrier:SetFrameLevel(button:GetFrameLevel() + (ns.LVL_AURA - 1))
    local roleIcon = roleCarrier:CreateTexture(nil, "OVERLAY")
    local riSz = PixelSnap(s.roleIconSize or 14)
    roleIcon:SetSize(riSz, riSz)
    roleIcon:Hide()
    d.roleIcon = roleIcon

    local function AnchorRoleIcon()
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
        roleIcon:ClearAllPoints()
        -- The position key (topleft/top/topright/left/center/right/bottomleft/
        -- bottom/bottomright) uppercases directly to a valid anchor point, so all
        -- 9 positions resolve like the Marker Position dropdown. The 4 corners
        -- produce identical anchors to the previous explicit branches.
        local pos = (s.roleIconPosition or "bottomleft"):upper()
        roleIcon:SetPoint(pos, health, pos, s.roleIconOffsetX or 0, s.roleIconOffsetY or 0)
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
    ns.ApplyLeaderStrata(d.leaderHost)

    local leaderIcon = d.leaderHost:CreateTexture(nil, "OVERLAY")
    local liSz = PixelSnap(s.leaderIconSize or 14)
    leaderIcon:SetSize(liSz, liSz)
    local liPos = (s.leaderIconPosition or "top"):upper()
    leaderIcon:SetPoint(liPos, ns.RF_AnchorHost(health, s), liPos, s.leaderIconOffsetX or 0, s.leaderIconOffsetY or 0)
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
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
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

    -- Ready check icon (shared with incoming-summon / incoming-rez; above name text)
    local readyCheck = markerCarrier:CreateTexture(nil, "OVERLAY")
    readyCheck:SetSize(PixelSnap(s.readyCheckSize or 20), PixelSnap(s.readyCheckSize or 20))
    readyCheck:Hide()
    d.readyCheck = readyCheck

    local function AnchorReadyCheck()
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
        readyCheck:ClearAllPoints()
        local pos = s.readyCheckPosition or "center"
        local ox = s.readyCheckOffsetX or 0
        local oy = s.readyCheckOffsetY or 0
        if pos == "topleft" then
            readyCheck:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
        elseif pos == "top" then
            readyCheck:SetPoint("TOP", health, "TOP", ox, -2 + oy)
        elseif pos == "topright" then
            readyCheck:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
        elseif pos == "left" then
            readyCheck:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
        elseif pos == "right" then
            readyCheck:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
        elseif pos == "bottomleft" then
            readyCheck:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
        elseif pos == "bottom" then
            readyCheck:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
        elseif pos == "bottomright" then
            readyCheck:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
        else -- center
            readyCheck:SetPoint("CENTER", health, "CENTER", ox, oy)
        end
    end
    AnchorReadyCheck()
    d.AnchorReadyCheck = AnchorReadyCheck

    -- Combat icon (on the marker carrier, above the border). Shows for members
    -- currently affecting combat; the 9-position anchor mirrors the role icon.
    local combatIcon = markerCarrier:CreateTexture(nil, "OVERLAY", nil, 1)
    local ciSz = PixelSnap(s.combatIndicatorSize or 16)
    combatIcon:SetSize(ciSz, ciSz)
    combatIcon:Hide()
    d.combatIcon = combatIcon

    local function AnchorCombatIcon()
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
        combatIcon:ClearAllPoints()
        local pos = (s.combatIndicatorPosition or "right"):upper()
        combatIcon:SetPoint(pos, health, pos, s.combatIndicatorOffsetX or 0, s.combatIndicatorOffsetY or 0)
    end
    AnchorCombatIcon()
    d.AnchorCombatIcon = AnchorCombatIcon

    -- Debuff icons (pre-created, anchored dynamically)
    d.debuffIcons = {}
    local cap = s.debuffCap or 3
    -- 12.1: engine containers own debuff rendering; the legacy pool would
    -- be dead frames built inside the login screen (every consumer
    -- iterates this table, so leaving it empty is safe).
    if ns.RFC_OwnsDebuffs then cap = 0 end
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

        -- Animated dispel clock border: TWO Cooldown frames at full icon size,
        -- parented to the button BELOW the icon. ApplyDebuffIcon insets the icon
        -- texture by the border thickness, so the icon occludes the center and only
        -- the inner margin -- a fixed-thickness ring INSIDE the icon -- shows. The
        -- BRIGHT one (reverse=false) shows the remaining time and erases clockwise;
        -- the DARK one (reverse=true) fills the exact complement (the already-
        -- elapsed arc) in the same hue at 50% brightness, so the ring is always
        -- whole. Solid white swipe texture so SetSwipeColor renders a flat ring.
        local function MakeClockRing(level, reverse)
            local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cd:SetFrameLevel(math.max(0, button:GetFrameLevel() + level))
            cd:SetReverse(reverse)
            cd:SetDrawEdge(false)
            cd:SetDrawBling(false)
            cd:SetDrawSwipe(true)
            cd:SetHideCountdownNumbers(true)
            cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
            -- Full icon size, BEHIND the icon texture. ApplyDebuffIcon INSETS the
            -- icon texture by the border thickness so only this ring's inner margin
            -- shows -- an inset border that stays within the icon's footprint.
            cd:SetAllPoints(icon)
            cd:Hide()
            return cd
        end
        icon._clockBorderDark = MakeClockRing(ns.LVL_AURA - 3, true)   -- elapsed arc, dark, below
        icon._clockBorder     = MakeClockRing(ns.LVL_AURA - 2, false)  -- remaining arc, bright, above

        -- Text carrier above cooldown swipe AND border
        local dbFontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        local dbTextLevel = math.max(cooldown:GetFrameLevel() + 2, dbBorder:GetFrameLevel() + 1)
        local dbDurCarrier = CreateFrame("Frame", nil, icon)
        dbDurCarrier:SetAllPoints()
        dbDurCarrier:SetFrameLevel(dbTextLevel)

        -- Stack count text
        local dbCountFS = dbDurCarrier:CreateFontString(nil, "OVERLAY")
        dbCountFS:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
        EllesmereUI.ApplyIconTextFont(dbCountFS, dbFontPath, 8, "raidFrames")
        dbCountFS:SetTextColor(1, 1, 1)
        icon._count = dbCountFS

        -- Duration text
        local dbDurFS = dbDurCarrier:CreateFontString(nil, "OVERLAY")
        dbDurFS:SetPoint("CENTER", icon, "CENTER", 0, 0)
        EllesmereUI.ApplyIconTextFont(dbDurFS, dbFontPath, 8, "raidFrames")
        dbDurFS:SetTextColor(1, 1, 1)
        dbDurFS:Hide()
        icon._durText = dbDurFS

        -- Hover tooltip support. Gated by the Debuff Display "Hide Tooltips"
        -- setting (default hidden): ApplyDebuffIcon toggles mouse interactivity to
        -- match. Default is fully mouse-transparent (EnableMouse false), like the
        -- defensive icons. Propagation is enabled so that when tooltips are
        -- shown, the icon can take the hover for its own tooltip yet still pass
        -- motion + clicks down to the button so casting keeps working.
        icon:EnableMouse(false)
        if icon.SetPropagateMouseMotion then icon:SetPropagateMouseMotion(true) end
        if icon.SetPropagateMouseClicks then icon:SetPropagateMouseClicks(true) end
        icon:SetScript("OnEnter", function(self)
            local u, iid = self._tipUnit, self._tipIID
            if not u or not iid then return end
            local b = self:GetParent()
            local fd = b and GetFFD(b)
            if fd then
                fd._hovered = true
                if fd.ApplyBorderColor then fd.ApplyBorderColor() end
            end
            -- Aura tooltip honors the same combat-visibility mode as the unit tip.
            if not ns.RaidFrameTooltipAllowed(b) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetUnitAuraByAuraInstanceID then
                GameTooltip:SetUnitAuraByAuraInstanceID(u, iid)
            elseif GameTooltip.SetUnitDebuffByAuraInstanceID then
                GameTooltip:SetUnitDebuffByAuraInstanceID(u, iid)
            end
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function(self)
            local b = self:GetParent()
            local fd = b and GetFFD(b)
            if fd then
                fd._hovered = false
                if fd.ApplyBorderColor then fd.ApplyBorderColor() end
            end
            GameTooltip:Hide()
        end)

        d.debuffIcons[i] = icon
    end

    -- Anchor debuff icons in a grid (position + growth + per-row wrap) via the
    -- shared DebuffGridPoint helper, which mirrors the Buff Manager's
    -- AnchorSimpleGrid. For CENTER growth, call with visibleCount so each row
    -- centers on how many icons are actually shown.
    local _dispOpts = {}
    local function AnchorDebuffs(visibleCount)
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
        local total = visibleCount or #d.debuffIcons
        local baseSz = s.debuffSize or 18

        -- Dispellable debuffs can be routed to their own anchor + growth + offsets
        -- ("Dispellable Debuff Location"); "same" keeps everything in one grid.
        if (s.dispellableDebuffLocation or "same") == "same" then
            for i, icon in ipairs(d.debuffIcons) do
                -- Undo any lingering per-icon dispellable size once the split
                -- is off (size writes are change-guarded via icon._euiSz).
                if icon._euiSz ~= baseSz then
                    icon._euiSz = baseSz
                    icon:SetSize(baseSz, baseSz)
                end
                icon:ClearAllPoints()
                local corner, fx, fy = ns.DebuffGridPoint(s, i - 1, total)
                icon:SetPoint(corner, health, corner, fx, fy)
            end
            return
        end

        local dispSz = ns.DispellableDebuffSize(s)
        _dispOpts.pos  = s.dispellableDebuffLocation
        _dispOpts.grow = s.dispellableDebuffGrowDirection or "RIGHT"
        _dispOpts.ox   = s.dispellableDebuffOffsetX or 0
        _dispOpts.oy   = s.dispellableDebuffOffsetY or 0
        _dispOpts.size = dispSz

        -- Per-group VISIBLE totals so CENTER growth centers each group correctly.
        local nTotal, dTotal = 0, 0
        for i = 1, total do
            local icon = d.debuffIcons[i]
            if icon then
                if icon._isDispellable then dTotal = dTotal + 1 else nTotal = nTotal + 1 end
            end
        end

        local nIdx, dIdx = 0, 0
        for _, icon in ipairs(d.debuffIcons) do
            icon:ClearAllPoints()
            if icon._isDispellable then
                -- Icons are pool-reused across groups, so the size rides the
                -- per-render classification (guarded: same value = no engine call).
                if icon._euiSz ~= dispSz then
                    icon._euiSz = dispSz
                    icon:SetSize(dispSz, dispSz)
                end
                local corner, fx, fy = ns.DebuffGridPoint(s, dIdx, dTotal, _dispOpts)
                icon:SetPoint(corner, health, corner, fx, fy)
                dIdx = dIdx + 1
            else
                if icon._euiSz ~= baseSz then
                    icon._euiSz = baseSz
                    icon:SetSize(baseSz, baseSz)
                end
                local corner, fx, fy = ns.DebuffGridPoint(s, nIdx, nTotal, nil)
                icon:SetPoint(corner, health, corner, fx, fy)
                nIdx = nIdx + 1
            end
        end
    end
    AnchorDebuffs()
    d.AnchorDebuffs = AnchorDebuffs

    -- Defensive/external icon pool (same structure as debuff icons)
    local DEF_CAP = 4
    -- 12.1: containers own defensives; skip the dead legacy pool (see the
    -- debuff pool note above).
    if ns.RFC_OwnsDefensives then DEF_CAP = 0 end
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
        local defDurFontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        local defDurFS = defDurCarrier:CreateFontString(nil, "OVERLAY")
        defDurFS:SetPoint("CENTER", defIcon, "CENTER", 0, 0)
        EllesmereUI.ApplyIconTextFont(defDurFS, defDurFontPath, 8, "raidFrames")
        defDurFS:SetTextColor(1, 1, 1)
        defDurFS:Hide()
        defIcon._durText = defDurFS

        d.defIcons[i] = defIcon
    end

    -- Anchor defensive icons. For CENTER growth, call with visibleCount
    -- to dynamically center the row based on how many are actually shown.
    local function AnchorDefensives(visibleCount)
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
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
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
        -- Text band level, re-applied on every reload; BEFORE the name-hidden
        -- early return because health text shares this carrier. Default sits
        -- under the aura band (ns.LVL_TEXT); the "Show Above Icons" opt-in
        -- (name cog) lifts the carrier above the band's children (+6 clears
        -- each aura unit's +1..+5), still below the marker carrier.
        textCarrier:SetFrameLevel(button:GetFrameLevel()
            + (s.nameTextAboveIcons and (ns.LVL_AURA + 6) or ns.LVL_TEXT))
        nameFS:ClearAllPoints()
        local pos = s.namePosition or "center"
        -- The Top Name Bar shows the unit name in its own band, so suppress the
        -- in-frame name entirely while it is enabled.
        if pos == "none" or s.topNameBarEnabled then
            nameFS:Hide()
            return
        end
        nameFS:Show()
        local ox = s.nameOffsetX or 0
        local oy = s.nameOffsetY or 0
        nameFS:SetWidth((s.frameWidth or 72) * ns.RF_NAME_WIDTH_FRACTION)
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
        -- Re-called on hover/target changes long after StyleButton: resolve
        -- LIVE (see the LiveS note above) so party overrides and profile
        -- swaps are honored -- the captured raid `s` goes stale (same fix as
        -- UpdatePowerBorder below).
        local s = LiveS()
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
        -- Re-called from ReloadFrames/ReloadPartyFrames long after StyleButton:
        -- resolve LIVE (see the LiveS note above), same fix as UpdatePowerBorder.
        local s = LiveS()
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
        -- Stored on `d` and re-called long after StyleButton, so resolve the
        -- settings source LIVE (see the LiveS note above): the captured raid
        -- `s` never sees party_ overrides on party frames and goes stale the
        -- moment db.profile is reassigned by a profile swap.
        local s = LiveS()
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
        -- Aura icons (buff/debuff) enable mouse and propagate motion up to this
        -- button, so a direct enter onto an icon fires the icon's OnEnter first
        -- (aura tooltip) then bubbles here -- which would clobber it with the unit
        -- tooltip. If the cursor is genuinely over one of our aura icons (marked by
        -- a stashed _tipIID), let that icon own the tooltip and bail here.
        local foci = (GetMouseFoci and GetMouseFoci()) or (GetMouseFocus and { GetMouseFocus() })
        if foci then
            for _, mf in ipairs(foci) do
                if mf ~= self and mf._tipIID ~= nil then return end
            end
        end
        -- Read through the party-aware proxy (like every other render path), not
        -- raw db.profile -- otherwise party_<key> overrides written by a custom
        -- party "Range & Tooltip" section are never seen and the tooltip mode
        -- dropdown appears to do nothing on party frames.
        local s = fd._isParty and ns._scaledPartyProxy or (fd._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
        -- Raid/party frame tooltips are governed by the "Show Raid Frames
        -- Tooltip" mode, and ONLY these frames -- no other unit tooltips are
        -- touched. never = no tooltip; outOfCombat = hidden in any combat;
        -- outOfBossCombat = hidden during an encounter; always = always shown.
        -- The peek modifier (Blizz UI Enhanced) lifts the mode while held so a
        -- hidden tip can be read on hover, in step with the global tooltips.
        if not (EllesmereUI._tooltipPeekHeld and EllesmereUI._tooltipPeekHeld()) then
            local ttMode = ns._ResolveTooltipMode(s)
            if ttMode == "never" then return end
            if ttMode == "outOfCombat" and inCombat then return end
            if ttMode == "outOfBossCombat" and ns._inBossCombat then return end
        end
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
            -- Extra Frames duplicates never enter the real routing maps (one
            -- button per unit); XF_Apply owns ns._xfUnitToButton instead. The
            -- repaint/range/private-aura work below applies to them 1:1.
            if d._isExtra then
                -- map owned by XF_Apply
            elseif d._isParty then ns._partyUnitToButton[u] = self
            else unitToButton[u] = self end
            -- Containers first: legacy refresh below still has restriction-era
            -- failure modes, and an error there must not starve the container
            -- of its unit assignment.
            if ns.RFC_OnUnitAssigned then ns.RFC_OnUnitAssigned(self, d, u) end
            if ns._RefreshAssignedButton then ns._RefreshAssignedButton(self, u) end
            if ns._UpdateButtonRange then ns._UpdateButtonRange(u, self) end
            -- Only re-register private aura anchors when the unit actually
            -- changed (same guard as RebuildUnitMap). OnAttributeChanged fires
            -- even when the header re-sets the SAME unit, which it does on
            -- every roster re-process -- an unguarded re-register tears down
            -- and recreates Blizzard's private aura anchors each time, making
            -- the Blizzard-rendered icons visibly blink.
            if C_UnitAuras_AddPrivateAuraAnchor and ns._RegisterPrivateAuras
                and (d.dispelContainerUnit ~= u or d.privateAuraUnit ~= u) then
                ns._RegisterPrivateAuras(self, u)
            end
        elseif ns._UnregisterPrivateAuras then
            ns._UnregisterPrivateAuras(self)
        end
    end)

    -- Secure click: left=target, right=menu
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("type1", "target")
    -- Wildcard fallback so left-click target always survives even if the
    -- click-cast engine later clears the explicit type1 (e.g. on a disable
    -- transition).
    button:SetAttribute("*type1", "target")
    -- 12.0.7 gates SecureUnitButton's togglemenu; route right-click securely
    -- through a SecureActionButton proxy so the menu (and its protected items
    -- like Set Focus) work without taint. (Sets *type2 = "click" -> proxy.)
    if EllesmereUI.AttachSecureUnitMenu then
        EllesmereUI.AttachSecureUnitMenu(button)
    else
        button:SetAttribute("type2", "togglemenu")
        button:SetAttribute("*type2", "togglemenu")
    end

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

    -- Buff manager indicators. 12.1: containers own ALL live BM rendering
    -- (custom slots/chains + simple grid); the legacy pools (8 icons +
    -- 4 bars + overlay/border + 10 simple-grid icons per button, with two
    -- font applies per icon) were ~160 dead frames/regions per button
    -- built inside the login screen -- the dominant raid-frame login
    -- spike. Options previews are unaffected: they build their OWN pools
    -- on dedicated preview frames (f._bm*), not these. Every d.bm* reader
    -- is nil-guarded.
    if ns.BM_CreateIndicators and not ns.RFC_OwnsBM then
        ns.BM_CreateIndicators(button, health, d, PP)
        if ns.BM_AnchorIndicators then
            ns.BM_AnchorIndicators(d, health, s)
        end
    end

    -- 12.1 aura containers (buttons are always created out of combat, so
    -- container creation here is safe by construction)
    if ns.RFC_SetupButton then
        ns.RFC_SetupButton(button, health, d)
    end
end

-------------------------------------------------------------------------------
--  Role icon show/hide decision. Shared by UpdateButton and the lightweight
--  ns._UpdateRoleIcons combat-transition updater so both stay in lockstep.
--  Honors the per-row "Hide In Combat" cog: when set, the icon is suppressed
--  for the duration of combat and restored on PLAYER_REGEN_ENABLED.
--  (Lives on ns, not a file local, to respect the chunk local cap.)
-------------------------------------------------------------------------------
ns._UpdateRoleIcon = function(d, s, unit)
    local roleIcon = d.roleIcon
    if not roleIcon then return end
    local style = s.roleIconStyle or "modern"
    if style == "none" then roleIcon:Hide(); return end
    if s.roleIconHideInCombat and inCombat then roleIcon:Hide(); return end
    local role = UnitGroupRolesAssigned(unit)
    if role and not issecretvalue(role) then
        local showForRole = (role == "TANK" and s.showRoleForTank)
            or (role == "HEALER" and s.showRoleForHealer)
            or (role == "DAMAGER" and s.showRoleForDPS)
        if showForRole and ApplyRoleIcon(roleIcon, role, style) then
            roleIcon:Show()
        else
            roleIcon:Hide()
        end
    else
        roleIcon:Hide()
    end
end

-------------------------------------------------------------------------------
--  Leader/assistant icon show/hide decision. Shared by UpdateButton and the
--  lightweight ns._UpdateLeaderIcons combat-transition updater so both stay in
--  lockstep. Honors the per-row "Show In Combat" cog (default on): when off,
--  the icon is suppressed for the duration of combat and restored on
--  PLAYER_REGEN_ENABLED. (Lives on ns, not a file local, to respect the chunk
--  local cap.)
-------------------------------------------------------------------------------
ns._UpdateLeaderIcon = function(d, s, unit)
    local leaderIcon = d.leaderIcon
    if not leaderIcon then return end
    if not s.showLeaderIcon then leaderIcon:Hide(); return end
    if s.showLeaderIconInCombat == false and inCombat then leaderIcon:Hide(); return end
    local isLeader = UnitIsGroupLeader(unit)
    local isAssist = UnitIsGroupAssistant(unit)
    if isLeader and not issecretvalue(isLeader) then
        leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        leaderIcon:SetTexCoord(0, 1, 0, 1)
        leaderIcon:Show()
    elseif isAssist and not issecretvalue(isAssist) then
        leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
        leaderIcon:SetTexCoord(0, 1, 0, 1)
        leaderIcon:Show()
    else
        leaderIcon:Hide()
    end
end

-------------------------------------------------------------------------------
--  Combat icon show/hide decision. Shows for group members who are currently
--  affecting combat (M+ skip awareness). Driven by UpdateButton and the
--  lightweight ns._UpdateCombatIcons updater (UNIT_FLAGS / regen transitions).
--  Texture Show/Hide is combat-legal. (Lives on ns to respect the chunk local
--  cap.)
-------------------------------------------------------------------------------
ns._UpdateCombatIcon = function(d, s, unit)
    local icon = d.combatIcon
    if not icon then return end
    if not s.showCombatIndicator then icon:Hide(); return end
    local c = UnitAffectingCombat(unit)
    if issecretvalue(c) or not c then icon:Hide(); return end

    local EllesmereUI = ns.EllesmereUI
    local style = s.combatIndicatorStyle or "standard"
    local MEDIA = ns._COMBAT_MEDIA
    if style:find("^combat%d") then
        icon:SetTexture(MEDIA .. style .. ".tga")
        icon:SetTexCoord(0, 1, 0, 1)
        if icon.SetDesaturated then icon:SetDesaturated(false) end
        icon:SetVertexColor(1, 1, 1, 1)
    else
        local classToken = d.classToken
        if not classToken then local _, ct = UnitClass(unit); classToken = ct end
        if classToken and issecretvalue(classToken) then classToken = nil end
        if style == "class" then
            icon:SetTexture(MEDIA .. "combat-indicator-class-custom.png")
            local coords = classToken and ns._COMBAT_CLASS_COORDS[classToken]
            if coords then
                icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            else
                icon:SetTexCoord(0, 1, 0, 1)
            end
        else
            icon:SetTexture(MEDIA .. "combat-indicator-custom.png")
            icon:SetTexCoord(0, 1, 0, 1)
        end
        local colorMode = s.combatIndicatorColor or "custom"
        if colorMode == "classcolor" then
            local cc = (classToken and EllesmereUI.GetClassColor and EllesmereUI.GetClassColor(classToken)) or { r = 1, g = 1, b = 1 }
            icon:SetVertexColor(cc.r, cc.g, cc.b, 1)
        else
            local cc = s.combatIndicatorCustomColor or { r = 1, g = 1, b = 1 }
            icon:SetVertexColor(cc.r, cc.g, cc.b, 1)
        end
    end
    icon:Show()
end

-------------------------------------------------------------------------------
--  Update all visual elements for a single button
-------------------------------------------------------------------------------
local function UpdateButton(button)
    local EllesmereUI = ns.EllesmereUI  -- upvalue read, not a global read (see taint note at top)
    local unit = button:GetAttribute("unit")
    if not unit or not UnitExists(unit) then
        button:SetAlpha(0)
        return
    end

    local d = GetFFD(button)
    if not d.styled then return end

    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
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
            -- 4th return of GetDarkModeFill() is the Dark Mode Fill Opacity.
            if fillTex then fillTex:SetAlpha(select(4, EllesmereUI.GetDarkModeFill())) end
        else
            if fillTex then fillTex:SetAlpha(1) end
            health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
        end
    end

    -- Background (+ dead/offline status tint). Centralized in ns._ApplyHealthBg
    -- so the lightweight UNIT_HEALTH path stays in lockstep on death/resurrect.
    ns._ApplyHealthBg(d, health, s, unit)

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

        -- The Top Name Bar always reserves its height from the top (its anchor is
        -- set by LayoutTopNameBar); subtract it here so this per-unit power
        -- show/hide doesn't expand health back over the bar.
        local tnbH = (s.topNameBarEnabled and PixelSnap(s.topNameBarHeight or 20)) or 0
        -- Extra Frames duplicates carry a per-group size offset (Extra Height);
        -- their authoritative height is the button itself, not the shared
        -- setting -- the base value here would shrink health back and leave a
        -- gap under the bar on every update.
        local frameH = d._isExtra and button:GetHeight() or (s.frameHeight or 46)
        if hidePower then
            power:Hide()
            if d.powerBorderFrame then d.powerBorderFrame:Hide() end
            -- Expand health bar to full frame height (minus the Top Name Bar)
            if d.health then
                d.health:SetHeight(PixelSnap(frameH - tnbH))
            end
        else
            -- Restore health bar height with power bar space (and Top Name Bar)
            local powerH = PixelSnap(s.powerHeight or 4)
            if d.health then
                d.health:SetHeight(PixelSnap(frameH - powerH - tnbH))
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
            -- Background: power-colored bg tracks this unit's power color
            -- (opt-in; the custom color is applied statically in ReloadFrames).
            if s.powerBgPowerColored and d.powerBg then
                local f = EllesmereUI.GetPowerBgDarkenFactor()
                d.powerBg:SetColorTexture(pr * f, pg * f, pb * f, (s.powerBgDarkness or 70) / 100)
                d._pwBgTintType = pType
                d._pwBgTintF = f
            end
        end
    end

    -- Absorb
    UpdateAbsorb(button, unit)

    -- Name (visibility owned by AnchorNameText, which hides it when the Top Name
    -- Bar is enabled; setting text/color on a hidden FS is harmless)
    if d.nameText then
        d.nameText:SetText(ResolveDisplayName(unit, true))
        local nr, ng, nb = GetNameColor(unit, s)
        d.nameText:SetTextColor(nr, ng, nb)
    end

    -- Top Name Bar text (unit name + class/custom color). The bar's
    -- size/anchor/visibility are handled by LayoutTopNameBar.
    if d.topNameBarText and s.topNameBarEnabled then
        d.topNameBarText:SetText(ResolveDisplayName(unit))
        local tr, tg, tb = GetTopNameBarColor(unit, s)
        d.topNameBarText:SetTextColor(tr, tg, tb)
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

    -- Heal absorb text
    if d.healAbsorbText then
        if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
            d.healAbsorbText:SetText("")
        else
            ns.SetHealAbsorbText(d.healAbsorbText, unit, s)
        end
    end

    -- Status text (DEAD / OFFLINE / AFK -- always shown, own position/size/color)
    if d.statusText then
        local stc = s.statusTextColor or { r = 1, g = 1, b = 1 }
        if s.statusTextPosition == "none" then
            d.statusText:Hide()
        elseif db.profile.showIncomingRez and UnitHasIncomingResurrection(unit) then
            -- Being resurrected: hide DEAD so the incoming-rez icon (shown in the same
            -- spot by UpdateReadyCheck) isn't covered by the status text.
            d.statusText:Hide()
        elseif UnitIsDeadOrGhost(unit) then
            d.statusText:SetText(EllesmereUI.L("DEAD"))
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            d.statusText:Show()
        elseif not UnitIsConnected(unit) then
            d.statusText:SetText(EllesmereUI.L("OFFLINE"))
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            d.statusText:Show()
        elseif s.statusShowAFK and UnitIsAFK and not issecretvalue(UnitIsAFK(unit)) and UnitIsAFK(unit) then
            d.statusText:SetText(EllesmereUI.L("AFK"))
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            d.statusText:Show()
        else
            d.statusText:Hide()
        end
    end

    -- Role icon
    ns._UpdateRoleIcon(d, s, unit)

    -- Leader/assistant icon (honors the "Show In Combat" cog)
    ns._UpdateLeaderIcon(d, s, unit)

    -- Combat icon (members currently in combat)
    ns._UpdateCombatIcon(d, s, unit)

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

-- Crowd-control aura filter (Blizzard 11.1+ CROWD_CONTROL filter, the same one
-- Grid2/Danders use to identify CC). An aura that is NOT filtered out by this
-- passes = it's a crowd-control debuff. Used by the CC Debuff Glow. Stored on ns
-- (not a file local) to stay under the Lua 200-local cap.
ns._ccDebuffFilter = "HARMFUL|" ..
    ((AuraUtil and AuraUtil.AuraFilters and AuraUtil.AuraFilters.CrowdControl) or "CROWD_CONTROL")

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
local function IsDisplayDebuff(unit, auraData, s)
    local iid = auraData.auraInstanceID
    if not iid then return false end
    -- Permanently hidden debuffs -- never shown, no toggle. Inlined (no file-scope
    -- table) to stay under the 200-local cap. Secret-safe: skip when spellId is
    -- secret. 1254550 = Arcane Empowerment, 308312 = Time Trial Practice.
    local hsid = auraData.spellId
    if hsid and not issecretvalue(hsid) and (hsid == 1254550 or hsid == 308312) then return false end
    s = s or (db and db.profile)
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
    local _z = s.debuffIconZoom or 0.08
    icon._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)

    -- A typed (dispellable) debuff carries a non-nil dispelName even when the
    -- name itself is a secret value (other players' debuffs inside instances);
    -- physical debuffs have a nil dispelName. So this nil check is the
    -- secret-safe "is it dispellable" test (used by the border AND clock border).
    local dispelName = auraData.dispelName
    local isDispellable = dispelName ~= nil
    icon._isDispellable = isDispellable   -- consumed by AnchorDebuffs for the split layout
    -- When on, dispellable debuffs swap their static colored border for the
    -- animated clock border (erases clockwise) and drop the face pie swipe.
    local wantClockBorder = isDispellable and s.dispelClockBorder == true

    -- Resolve the dispel-type color once (secret-safe); shared by the static
    -- border and the animated clock border. dcDark is the same hue at 50%
    -- brightness for the clock border's already-elapsed arc.
    local dc, dcDark
    if dispelName ~= nil then
        if not issecretvalue(dispelName) then
            -- Clean string: direct per-type color lookup.
            dc = GetDispelColor(dispelName, s)
            if dc then
                local sd = ns._dispelScratchDark
                sd.r, sd.g, sd.b = dc.r * 0.5, dc.g * 0.5, dc.b * 0.5
                dcDark = sd
            end
        else
            -- Secret dispel type: resolve through Blizzard's color curves so the
            -- user's custom dispel color still applies without ever reading the
            -- secret (same route as the health-bar dispel border). A parallel
            -- pre-darkened curve yields the 50%-blacker shade, also secret-safe.
            if not ns._dispelCurve then ns._RebuildDispelCurves() end
            local party = (s == ns._scaledPartyProxy)
            local curve     = party and ns._dispelCurveParty     or ns._dispelCurve
            local curveDark = party and ns._dispelCurveDarkParty or ns._dispelCurveDark
            local iid = auraData.auraInstanceID
            if iid and C_UnitAuras.GetAuraDispelTypeColor then
                if curve then
                    local col = C_UnitAuras.GetAuraDispelTypeColor(unit, iid, curve)
                    if col then
                        local sc = ns._dispelScratch
                        sc.r, sc.g, sc.b = col:GetRGB()
                        dc = sc
                    end
                end
                if curveDark then
                    local cold = C_UnitAuras.GetAuraDispelTypeColor(unit, iid, curveDark)
                    if cold then
                        local sd = ns._dispelScratchDark
                        sd.r, sd.g, sd.b = cold:GetRGB()
                        dcDark = sd
                    end
                end
            end
        end
    end

    -- Border (dispel-type colored or user default). Hidden when the animated
    -- clock border takes over for this dispellable debuff.
    local borderSz = s.debuffBorderSize or 1
    if icon._borderFrame and PP then
        if borderSz > 0 and not wantClockBorder then
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
        -- Border-only clock: suppress the face pie swipe when active so ONLY
        -- the perimeter ring animates for this dispellable debuff.
        local wantSwipe = s.debuffShowSwipe and not wantClockBorder
        local wantDurText = s.debuffShowDurText
        if wantSwipe or wantDurText then
            -- Permanent auras return a degenerate 0,0 duration object; a
            -- cooldown armed from one strobes -- the CLIENT shows the full
            -- reversed swipe then self-hides, an internal cycle that Lua-side
            -- show/hide gating cannot stop. Mask with ALPHA instead:
            -- durObj:IsZero() -> alpha 0. Secret-safe (works on other
            -- players' debuffs in instances) and orthogonal to the client's
            -- internal show/hide. Clear()+Hide() wipes stale reused frames.
            local applied = false
            local iid = auraData.auraInstanceID
            if iid and not issecretvalue(iid) and C_UnitAuras.GetAuraDuration then
                local durObj = C_UnitAuras.GetAuraDuration(unit, iid)
                if durObj then
                    icon._cooldown:SetCooldownFromDurationObject(durObj)
                    if durObj.IsZero and icon._cooldown.SetAlphaFromBoolean then
                        icon._cooldown:SetAlphaFromBoolean(durObj:IsZero(), 0, 1)
                    else
                        icon._cooldown:SetAlpha(1)
                    end
                    applied = true
                end
            else
                local dur = auraData.duration
                local exp = auraData.expirationTime
                if dur and exp and not issecretvalue(dur) and not issecretvalue(exp) and dur > 0 then
                    icon._cooldown:SetCooldown(exp - dur, dur)
                    icon._cooldown:SetAlpha(1)
                    applied = true
                end
            end
            if applied then
                icon._cooldown:SetDrawSwipe(wantSwipe)
                icon._cooldown:SetHideCountdownNumbers(not wantDurText)
                icon._cooldown:Show()
            else
                icon._cooldown:Clear()
                icon._cooldown:Hide()
            end
            -- Style the built-in countdown text via GetCountdownFontString
            if applied and wantDurText then
                local cdText = icon._cooldown.GetCountdownFontString and icon._cooldown:GetCountdownFontString()
                if cdText then
                    local dtc = s.debuffDurTextColor or { r = 1, g = 1, b = 1 }
                    local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
                    EllesmereUI.ApplyIconTextFont(cdText, fp, s.debuffDurTextSize or 8, "raidFrames")
                    cdText:SetTextColor(dtc.r, dtc.g, dtc.b)
                    cdText:ClearAllPoints()
                    cdText:SetPoint("CENTER", icon, "CENTER", s.debuffDurTextOffsetX or 0, s.debuffDurTextOffsetY or 0)
                end
            end
        else
            icon._cooldown:Hide()
        end
    end

    -- Animated dispel clock border: a fixed-thickness colored ring that starts
    -- fully drawn and erases clockwise as the debuff expires. The cooldown rings
    -- are full icon size BEHIND the texture; insetting the texture by the border
    -- thickness leaves only the inner margin (the ring) visible -- an INSET border
    -- that stays within the icon's footprint (no layout shift). Engine-driven
    -- (SetCooldownFromDurationObject), so it stays correct on secret-duration
    -- debuffs where a Lua timer cannot read the remaining time.
    if icon._clockBorder then
        if wantClockBorder then
            local cb, cbd = icon._clockBorder, icon._clockBorderDark
            -- Inset ring thickness = main debuff border size + extra, in physical
            -- pixels at the icon's effective scale (matches the static border).
            -- The rings are full icon size; shrinking the icon texture by `ring`
            -- exposes exactly that inner margin (and nothing outside the icon).
            local ringPx = (s.debuffBorderSize or 1) + (s.dispelClockExtraBorder or 0)
            local es = icon:GetEffectiveScale()
            local onePixel = (es and es > 0 and PP and PP.perfect) and (PP.perfect / es) or 1
            local ring = ringPx * onePixel
            local applied = false
            local iid = auraData.auraInstanceID
            if iid and not issecretvalue(iid) and C_UnitAuras.GetAuraDuration then
                local durObj = C_UnitAuras.GetAuraDuration(unit, iid)
                if durObj then
                    cb:SetCooldownFromDurationObject(durObj)
                    cbd:SetCooldownFromDurationObject(durObj)
                    if durObj.IsZero and cb.SetAlphaFromBoolean then
                        cb:SetAlphaFromBoolean(durObj:IsZero(), 0, 1)
                        cbd:SetAlphaFromBoolean(durObj:IsZero(), 0, 1)
                    else
                        cb:SetAlpha(1); cbd:SetAlpha(1)
                    end
                    applied = true
                end
            else
                local dur, exp = auraData.duration, auraData.expirationTime
                if dur and exp and not issecretvalue(dur) and not issecretvalue(exp) and dur > 0 then
                    cb:SetCooldown(exp - dur, dur)
                    cbd:SetCooldown(exp - dur, dur)
                    cb:SetAlpha(1); cbd:SetAlpha(1)
                    applied = true
                end
            end
            if applied then
                -- Tint each swipe; SetVertexColor accepts secret values and
                -- SetSwipeColor is assumed to behave the same. Bright ring shows
                -- the remaining time; the reversed dark ring fills the elapsed
                -- complement in the same hue at 50% brightness.
                local c  = dc     or s.debuffBorderColor or { r = 1, g = 1, b = 1 }
                local cd = dcDark or c
                cb:SetSwipeColor(c.r, c.g, c.b, 1)
                cbd:SetSwipeColor(cd.r, cd.g, cd.b, 1)
                -- Inset the icon texture so the rings show only as an inner margin.
                icon._tex:ClearAllPoints()
                icon._tex:SetPoint("TOPLEFT", icon, "TOPLEFT", ring, -ring)
                icon._tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -ring, ring)
                cb:Show(); cbd:Show()
            else
                cb:Clear(); cb:Hide()
                cbd:Clear(); cbd:Hide()
                icon._tex:ClearAllPoints(); icon._tex:SetAllPoints()
            end
        else
            icon._clockBorder:Hide()
            if icon._clockBorderDark then icon._clockBorderDark:Hide() end
            -- Clock border insets the icon texture; restore full size when off.
            icon._tex:ClearAllPoints()
            icon._tex:SetAllPoints()
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

    -- Hover tooltip target: stash the unit + aura instance for the icon's
    -- OnEnter, then toggle hover motion to match the Hide Tooltips setting (set
    -- up in StyleButton). Read live so a combat-time toggle applies on the next
    -- aura event even though ReloadFrames is deferred during combat.
    icon._tipUnit = unit
    icon._tipIID = auraData.auraInstanceID
    -- Tooltips show only when the setting is explicitly off; nil/true = hidden.
    -- When shown, make the icon mouse-aware for its OnEnter tooltip; motion and
    -- clicks still propagate to the parent button (set up in StyleButton) so
    -- hover/click-casting keep working underneath. When hidden, fully disable
    -- mouse so the icon is transparent and the button owns all hover/clicks.
    local wantTipMotion = (s.debuffHideTooltips == false)
    if icon._tipMotion ~= wantTipMotion then
        icon:EnableMouse(wantTipMotion)
        icon._tipMotion = wantTipMotion
    end

    icon:Show()
end

-- CC Debuff Glow: glow a displayed debuff icon when its aura is crowd control.
-- Mirrors CDM's Buff Glow (per-icon overlay + EllesmereUI.Glows.StartGlow). The
-- glow is restarted only when style/size/colour/pixel-params change so a steady
-- glow never resets on a plain aura tick. Secret-safe: the CC test uses the
-- Blizzard filter API, and we never read a secret aura field. Defined on ns (not
-- a file local) to stay under the Lua 200-local cap.
function ns.ApplyDebuffCCGlow(icon, auraData, unit, s)
    local Glows = EllesmereUI.Glows
    local gType = s.debuffCCGlowType or 0
    local iid = auraData and auraData.auraInstanceID
    local isCC = gType > 0 and iid and not issecretvalue(iid)
        and C_UnitAuras_IsAuraFilteredOutByInstanceID
        and not C_UnitAuras_IsAuraFilteredOutByInstanceID(unit, iid, ns._ccDebuffFilter)
    if isCC and Glows and Glows.StartGlow then
        local gov = icon._ccGlowOverlay
        if not gov then
            gov = CreateFrame("Frame", nil, icon)
            gov:SetAllPoints(icon)
            gov:SetFrameLevel(icon:GetFrameLevel() + 5)
            gov:EnableMouse(false)
            icon._ccGlowOverlay = gov
        end
        local cr, cg, cb = s.debuffCCGlowR or 1.0, s.debuffCCGlowG or 0.776, s.debuffCCGlowB or 0.376
        if s.debuffCCGlowClassColor then
            local _, classFile = UnitClass("player")
            local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
        end
        local sz = s.debuffSize or 18
        -- Dispellable icons routed to their own anchor may carry their own
        -- size; the glow geometry must match (icon._isDispellable is set by
        -- ApplyDebuffIcon just before this runs in the render pass).
        if icon._isDispellable and (s.dispellableDebuffLocation or "same") ~= "same" then
            sz = ns.DispellableDebuffSize(s)
        end
        local oN, oTh, oPer, oBgR, oBgG, oBgB
        if gType == 1 then  -- Pixel Glow uses the Lines/Thickness/Speed params
            oN, oTh, oPer = s.debuffCCGlowLines or 8, s.debuffCCGlowThickness or 2, s.debuffCCGlowSpeed or 4
            if s.debuffCCGlowBackground then
                oBgR, oBgG, oBgB = s.debuffCCGlowBackgroundR or 0, s.debuffCCGlowBackgroundG or 0, s.debuffCCGlowBackgroundB or 0
            end
        end
        if (not gov._euiGlowActive) or gov._ccStyle ~= gType or gov._ccW ~= sz
           or gov._ccCR ~= cr or gov._ccCG ~= cg or gov._ccCB ~= cb
           or gov._ccN ~= oN or gov._ccTh ~= oTh or gov._ccPer ~= oPer
           or gov._ccBgR ~= oBgR or gov._ccBgG ~= oBgG or gov._ccBgB ~= oBgB then
            Glows.StartGlow(gov, gType, sz, cr, cg, cb,
                oN and { N = oN, th = oTh, period = oPer, bg = oBgR and { r = oBgR, g = oBgG, b = oBgB } or nil } or nil)
            gov._ccStyle, gov._ccW = gType, sz
            gov._ccCR, gov._ccCG, gov._ccCB = cr, cg, cb
            gov._ccN, gov._ccTh, gov._ccPer = oN, oTh, oPer
            gov._ccBgR, gov._ccBgG, gov._ccBgB = oBgR, oBgG, oBgB
        end
    elseif icon._ccGlowOverlay and icon._ccGlowOverlay._euiGlowActive and Glows and Glows.StopGlow then
        Glows.StopGlow(icon._ccGlowOverlay)
    end
end

-- Stop a debuff icon's CC glow (pool reuse / hidden / filter off). On ns to stay
-- under the Lua 200-local cap.
function ns.StopDebuffCCGlow(icon)
    local gov = icon._ccGlowOverlay
    if gov and gov._euiGlowActive and EllesmereUI.Glows and EllesmereUI.Glows.StopGlow then
        EllesmereUI.Glows.StopGlow(gov)
    end
end

-- Render the cached debuff list to icon frames
local function RenderDebuffs(d, s, unit)
    local EllesmereUI = ns.EllesmereUI  -- upvalue read, not a global read (see taint note at top)
    local debuffCache = d.debuffCache
    local cap = s.debuffCap or 3
    local shown = 0

    -- Apply font/position settings once per render (not per-aura)
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    for _, icon in ipairs(d.debuffIcons) do
        -- Stacks font
        if icon._count and s.debuffShowStacks then
            local stc = s.debuffStacksTextColor or { r=1, g=1, b=1 }
            EllesmereUI.ApplyIconTextFont(icon._count, fontPath, s.debuffStacksTextSize or 8, "raidFrames")
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
                ns.ApplyDebuffCCGlow(icon, auraData, unit, s)
            end
        end
    end
    for j = shown + 1, #d.debuffIcons do
        local icon = d.debuffIcons[j]
        icon:Hide()
        icon._isDispellable = nil
        if icon._clockBorder then icon._clockBorder:Hide() end
        if icon._clockBorderDark then icon._clockBorderDark:Hide() end
        ns.StopDebuffCCGlow(icon)
        if icon._durText and ns.UnregisterDurText then ns.UnregisterDurText(icon._durText) end
    end

    -- Re-anchor when the layout depends on this render's composition: CENTER
    -- growth (needs the visible count) OR dispellable-debuff separation (needs to
    -- know which icons are dispellable, which changes every update).
    if d.AnchorDebuffs and ((s.debuffGrowDirection or "RIGHT") == "CENTER"
       or (s.dispellableDebuffLocation or "same") ~= "same") then
        d.AnchorDebuffs(shown)
    end
end

-- Full scan: rebuild debuff cache from scratch
local function FullScanDebuffs(d, unit, s)
    if not d.debuffCache then d.debuffCache = {} end
    wipe(d.debuffCache)
    d.debuffInstanceMap = d.debuffInstanceMap or {}
    wipe(d.debuffInstanceMap)
    local i = 1
    while true do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
        if not auraData then break end
        i = i + 1
        if IsDisplayDebuff(unit, auraData, s) then
            local idx = #d.debuffCache + 1
            d.debuffCache[idx] = auraData
            d.debuffInstanceMap[auraData.auraInstanceID] = idx
        end
    end
end

local function UpdateDebuffs(button, unit, updateInfo)
    -- 12.1: debuff rendering is container-owned (EUI_RaidFrames_AuraContainers).
    -- Single gate covering every call site (dispatch, drain, full-update
    -- loops, party, extra-frame tracker).
    if ns.RFC_OwnsDebuffs then return end
    local d = GetFFD(button)
    if not d.debuffIcons then return end
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile

    if s.debuffFilter == "none" then
        for _, icon in ipairs(d.debuffIcons) do icon:Hide(); ns.StopDebuffCCGlow(icon) end
        if d.debuffCache then wipe(d.debuffCache) end
        return
    end

    local needFullScan = not d.debuffCache
        or not updateInfo
        or (updateInfo.isFullUpdate)

    if needFullScan then
        FullScanDebuffs(d, unit, s)
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
                    and IsDisplayDebuff(unit, auraData, s) then
                    -- Blizzard re-announces an already-visible aura as "added"
                    -- when its visibility/classification is re-evaluated (duel
                    -- start/end, phasing, PvP flag changes). Appending it again
                    -- would render the same debuff twice -- the stale snapshot
                    -- (often still typed non-dispellable) next to the fresh
                    -- dispellable one -- and orphan the stale copy in the cache
                    -- until the next full scan. Refresh the existing slot in
                    -- place instead.
                    local existing = imap[iid]
                    if existing and cache[existing] then
                        cache[existing] = auraData
                    else
                        local idx = #cache + 1
                        cache[idx] = auraData
                        imap[auraData.auraInstanceID] = idx
                    end
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
    -- 12.1: defensive/external rendering is container-owned
    -- (EUI_RaidFrames_AuraContainers). Single gate for every call site.
    if ns.RFC_OwnsDefensives then return end
    local d = GetFFD(button)
    if not d.defIcons then return end
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile

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
            -- Blizzard's EXTERNAL_DEFENSIVE filter omits Blessing of Freedom (a
            -- movement utility, not a damage defensive), and Freedom is a secret
            -- aura so its spellId can't be read directly. Identify the player's
            -- OWN Freedom via the spec-scoped fingerprint and treat it as an
            -- external. Gated on Paladin class (only caster of Freedom) so other
            -- viewers never run the fingerprint. All three Paladin specs resolve
            -- here: Holy natively, Protection/Retribution via the Buff Manager
            -- borrow-spec entries that route them to the Holy spell table.
            if not isExternal and playerClassToken == "PALADIN"
                and ns.BM_IdentifySecretAura
                and ns.BM_IdentifySecretAura(unit, iid) == 1044 then
                isExternal = true
            end
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
                local _z = s.defIconZoom or 0.08
                icon._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)

                -- Duration swipe + text (secret-safe via DurationObject + GetCountdownFontString)
                local cd = icon._cooldown
                if cd then
                    local wantSwipe = s.defShowSwipe ~= false
                    local wantDurText = s.defShowDurText
                    if wantSwipe or wantDurText then
                        -- Permanent auras return a degenerate 0,0 duration object
                        -- whose armed cooldown strobes via an internal client
                        -- show/self-hide cycle; mask with alpha via durObj:IsZero()
                        -- (secret-safe, see ApplyDebuffIcon).
                        local applied = false
                        if C_UnitAuras_GetAuraDuration and cd.SetCooldownFromDurationObject then
                            local durObj = C_UnitAuras_GetAuraDuration(unit, iid)
                            if durObj then
                                cd:SetCooldownFromDurationObject(durObj)
                                if durObj.IsZero and cd.SetAlphaFromBoolean then
                                    cd:SetAlphaFromBoolean(durObj:IsZero(), 0, 1)
                                else
                                    cd:SetAlpha(1)
                                end
                                applied = true
                            else
                                cd:Clear()
                            end
                        end
                        if applied then
                            cd:SetDrawSwipe(wantSwipe)
                            cd:SetHideCountdownNumbers(not wantDurText)
                            cd:Show()
                        else
                            cd:Hide()
                        end
                        -- Style the built-in countdown text via GetCountdownFontString
                        if applied and wantDurText then
                            local cdText = cd.GetCountdownFontString and cd:GetCountdownFontString()
                            if cdText then
                                local dtc = s.defDurTextColor or { r = 1, g = 1, b = 1 }
                                local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
                                EllesmereUI.ApplyIconTextFont(cdText, fp, s.defDurTextSize or 8, "raidFrames")
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
    elseif mode == "gradient" or mode == "gradient_sharp" then
        -- Pre-baked vertical gradient texture (solid at the top, fading to
        -- transparent at the bottom; the sharp variant falls off faster) tinted
        -- with the dispel color. SetVertexColor passes the (secret) dispel-type
        -- color through natively; the texture's own alpha supplies the fade.
        -- WHITE8X8 + SetGradient + CreateColor errors here because CreateColor
        -- cannot wrap a secret color value.
        if health then
            olTex:SetAllPoints(health)
        end
        olTex:SetTexture(mode == "gradient_sharp"
            and "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-sharp.tga"
            or "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-tb.tga")
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
    wrapper:SetAttribute("aura-organization-type", s and s.dispelOverlayPosition or 0)   -- 0=Top, 1=Bottom, 2=Left
    wrapper:SetAttribute("update-settings", true)

    -- Pin to the button's OWN strata + a below-text frame level (NO strata bump)
    -- so the overlay renders BEHIND the name/health text. Re-applied here (not
    -- only at creation) so it survives any button-level change before register.
    wrapper:SetFrameStrata(button:GetFrameStrata())
    wrapper:SetFrameLevel(button:GetFrameLevel() + ns.LVL_DISPEL_OVERLAY)

    local ok, anchorID = pcall(function()
        return C_UnitAuras_AddPrivateAuraAnchor({
            unitToken     = unit,
            parent        = wrapper,
            isContainer   = true,
            auraIndex     = 1,
            -- 12.1 renamed this anchor key; retail keeps the old spelling.
            [EllesmereUI.IS_121 and "showCooldownFrame" or "showCountdownFrame"] = false,
            showCountdownNumbers = false,
        })
    end)
    if ok and anchorID then
        d.dispelContainerAnchorID = anchorID
        -- AddPrivateAuraAnchor caches the parent's frame level on first register
        -- and ignores later changes; toggling to 0 and back forces Blizzard to
        -- re-read it on the next paint so our below-text level actually applies
        -- (without this the overlay can render behind the whole frame).
        local lvl = wrapper:GetFrameLevel()
        wrapper:SetFrameLevel(0)
        wrapper:SetFrameLevel(lvl)
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

    -- Our custom visuals are active = we handle this debuff, suppress container.
    -- Must include the dispel-type ICON: with an icon-only setup (border 0,
    -- overlay "none") the border/overlay checks alone read false and Blizzard's
    -- container un-suppresses, drawing a second dispel indicator next to ours.
    local ourShowing = (d.dispelFrame and d.dispelFrame:IsShown())
        or (d.dispelOLTex and d.dispelOLTex:IsShown())
        or (d.dispelIcon and d.dispelIcon:IsShown())
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
            or (d2.dispelIcon and d2.dispelIcon:IsShown())
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

    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    local health = ns.RF_AnchorHost(d.health, s)
    if not health then return end
    local sz = s.paSize or 18
    local showCD = s.paShowCountdown ~= false

    -- Independent position/growth for private auras
    local pos = s.paPosition or "bottomleft"
    -- "None": private auras disabled. Old anchors were already removed above; hide
    -- the slot frames and skip registration so Blizzard's secure layer draws
    -- nothing for this unit. The dispel container is independent and unaffected.
    if pos == "none" then
        if d.privateAuraFrames then
            for _, f in ipairs(d.privateAuraFrames) do f:Hide() end
        end
        d.privateAuraUnit = unit
        return
    end
    local ox = s.paOffsetX or 0
    local oy = s.paOffsetY or 0
    local grow = s.paGrowDirection or "RIGHT"
    local spc = PixelSnap(s.paSpacing or 1)

    -- Hide Tooltips: Blizzard draws each private aura icon at iconInfo size
    -- centered on the slot frame, but the icon's HOVER area comes from the
    -- slot frame's own rect (the C-side icon ignores Lua mouse flags set on
    -- the parent). Collapsing each slot to a sub-pixel point leaves the icon
    -- rendering at full size with no surface left to hover, so the tooltip
    -- can never trigger. The offset shift below moves the point to where the
    -- full-size slot's CENTER used to sit, and the chain spacing regains the
    -- icon width the collapsed frames no longer contribute -- the rendered
    -- icons land pixel-identical to normal mode.
    local slotSz = sz
    if s.paHideTooltip then
        slotSz = 0.001
        local half = sz / 2
        if pos == "topleft" or pos == "left" or pos == "bottomleft" then
            ox = ox + half
        elseif pos == "topright" or pos == "right" or pos == "bottomright" then
            ox = ox - half
        end
        if pos == "topleft" or pos == "top" or pos == "topright" then
            oy = oy - half
        elseif pos == "bottomleft" or pos == "bottom" or pos == "bottomright" then
            oy = oy + half
        end
        spc = spc + sz
    end

    local parentStrata = button:GetFrameStrata()
    local fixedStrata = PA_STRATA_FIX[parentStrata] or "DIALOG"

    -- Countdown text scale-trick: Blizzard draws the timer/stack text as a child
    -- of the slot frame, so its on-screen size follows the frame's SCALE, not the
    -- iconInfo pixel size. With the frame left at scale 1 and only iconInfo driving
    -- the icon size, the text rendered at a fixed size regardless of icon size --
    -- huge on small icons, tiny on big ones (the "all over the place" sizing).
    -- Scaling the frame by (size / 32) makes the text track the icon size; the icon
    -- dimension is compensated back to a constant 32 local units so the rendered
    -- icon stays exactly paSize pixels. SetPoint offsets and spacing live in the
    -- frame's local (pre-scale) space, so they are divided by the same factor.
    local ts = sz / 32
    if ts <= 0 then ts = 1 end
    local comp = 32               -- icon size in local units; renders at comp*ts = paSize px
    local oxL, oyL, spcL = ox / ts, oy / ts, spc / ts

    for i, paFrame in ipairs(d.privateAuraFrames) do
        paFrame:SetScale(ts)
        paFrame:SetSize(slotSz / ts, slotSz / ts)
        paFrame:SetFrameStrata(fixedStrata)
        paFrame:SetFrameLevel(button:GetFrameLevel() + ns.LVL_AURA)
        paFrame:ClearAllPoints()

        if i == 1 then
            -- Private auras anchor flush to the health bar edge (no 1px inset),
            -- matching the debuff/role icon displays.
            if pos == "topleft" then
                paFrame:SetPoint("TOPLEFT", health, "TOPLEFT", oxL, oyL)
            elseif pos == "top" then
                paFrame:SetPoint("TOP", health, "TOP", oxL, oyL)
            elseif pos == "topright" then
                paFrame:SetPoint("TOPRIGHT", health, "TOPRIGHT", oxL, oyL)
            elseif pos == "left" then
                paFrame:SetPoint("LEFT", health, "LEFT", oxL, oyL)
            elseif pos == "center" then
                paFrame:SetPoint("CENTER", health, "CENTER", oxL, oyL)
            elseif pos == "right" then
                paFrame:SetPoint("RIGHT", health, "RIGHT", oxL, oyL)
            elseif pos == "bottomright" then
                paFrame:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", oxL, oyL)
            elseif pos == "bottom" then
                paFrame:SetPoint("BOTTOM", health, "BOTTOM", oxL, oyL)
            else
                paFrame:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", oxL, oyL)
            end
        else
            local prev = d.privateAuraFrames[i - 1]
            if grow == "RIGHT" then
                paFrame:SetPoint("LEFT", prev, "RIGHT", spcL, 0)
            elseif grow == "LEFT" then
                paFrame:SetPoint("RIGHT", prev, "LEFT", -spcL, 0)
            elseif grow == "UP" then
                paFrame:SetPoint("BOTTOM", prev, "TOP", 0, spcL)
            elseif grow == "DOWN" then
                paFrame:SetPoint("TOP", prev, "BOTTOM", 0, -spcL)
            end
        end

        paFrame:Show()

        -- Register per-slot anchor
        local iconInfoTbl = {
            iconWidth  = comp,
            iconHeight = comp,
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
        -- only appears when Blizzard actually renders an icon there. Divide by the
        -- frame scale (ts) so the visible border stays identical to the pre-scale-
        -- trick size -- otherwise the frame scaling would enlarge it on top.
        iconInfoTbl.borderScale = (sz / 32 * 2) / ts
        local ok, anchorID = pcall(function()
            return C_UnitAuras_AddPrivateAuraAnchor({
                unitToken     = unit,
                auraIndex     = i,
                parent        = paFrame,
                isContainer   = false,
                -- 12.1 renamed this anchor key; retail keeps the old spelling.
                [EllesmereUI.IS_121 and "showCooldownFrame" or "showCountdownFrame"] = true,
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
ns._dispelScratchDark = ns._dispelScratchDark or {}

-- Build the dispel-type -> color curves from the user's custom colors. Blizzard's
-- GetAuraDispelTypeColor evaluates this curve against an aura's (secret) dispel
-- type internally and hands back the matching color, so we never need to read
-- the secret dispelName/dispelType ourselves. Indices are Blizzard's dispel-type
-- enum: 1 Magic, 2 Curse, 3 Disease, 4 Poison, 9 Enrage, 11 Bleed (0 = none).
-- Rebuilt on every ReloadFrames so custom-color edits take effect. Stored on ns
-- (not file locals) to respect the 200-local main-chunk cap.
function ns._RebuildDispelCurves()
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return end
    local function build(profile, mult)
        local c = C_CurveUtil.CreateColorCurve()
        c:SetType(Enum.LuaCurveType.Step)
        local function add(idx, key, dr, dg, db)
            local col = profile and profile[key]
            c:AddPoint(idx, CreateColor((col and col.r or dr) * mult, (col and col.g or dg) * mult, (col and col.b or db) * mult))
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
    -- Bright (full) curves + parallel 50%-darkened curves for the clock border's
    -- already-elapsed arc. Darkening is applied here to the user's CLEAN color
    -- values at build time, never to a secret per-frame color.
    ns._dispelCurve          = build(ns._scaledProfile,    1)
    ns._dispelCurveParty     = build(ns._scaledPartyProxy, 1)
    ns._dispelCurveDark      = build(ns._scaledProfile,    0.5)
    ns._dispelCurveDarkParty = build(ns._scaledPartyProxy, 0.5)
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
    -- 12.1: dispel display is container-slot-owned
    -- (EUI_RaidFrames_AuraContainers). Single gate for every call site.
    if ns.RFC_OwnsDispel then return end
    local d = GetFFD(button)
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
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

-- The d.readyCheck texture is shared between the ready-check, incoming-summon and
-- incoming-resurrection indicators (they almost never overlap -- rez only shows on
-- dead units, the other two on living ones). Priority: an active ready check wins,
-- then a pending summon, then an incoming rez.
local function UpdateReadyCheck(button, unit)
    local d = GetFFD(button)
    local tex = d.readyCheck
    if not tex then return end

    local sz = PixelSnap(db.profile.readyCheckSize or 20)
    tex:SetSize(sz, sz)

    -- Ready check (priority)
    if db.profile.showReadyCheck and readyCheckActive then
        local status = GetReadyCheckStatus(unit)
        if status == "ready" then
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            tex:Show()
            return
        elseif status == "notready" then
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
            tex:Show()
            return
        elseif status == "waiting" then
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
            tex:Show()
            return
        end
    end

    -- Incoming summon
    if db.profile.showSummonPending and unit and C_IncomingSummon.HasIncomingSummon(unit) then
        local sStatus = C_IncomingSummon.IncomingSummonStatus(unit)
        if sStatus == SUMMON_STATUS_PENDING then
            tex:SetAtlas("RaidFrame-Icon-SummonPending")
            tex:Show()
            return
        elseif sStatus == SUMMON_STATUS_ACCEPTED then
            tex:SetAtlas("RaidFrame-Icon-SummonAccepted")
            tex:Show()
            return
        elseif sStatus == SUMMON_STATUS_DECLINED then
            tex:SetAtlas("RaidFrame-Icon-SummonDeclined")
            tex:Show()
            return
        end
    end

    -- Incoming resurrection ("someone is casting a rez / rez waiting to be
    -- accepted"). Lowest priority; only meaningful on a dead unit. Lets healers
    -- see a body is already being picked up so they don't all rez the same one.
    if db.profile.showIncomingRez and unit and UnitHasIncomingResurrection(unit) then
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
        tex:Show()
        return
    end

    tex:Hide()
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
                local d = GetFFD(btn)
                -- Extra Frames duplicates stay out of the routing map (one
                -- button per unit; the real frame owns the slot). Everything
                -- else here -- class cache, private auras -- applies to them.
                if not d._isExtra then unitToButton[u] = btn end
                -- Cache class token for power border (avoids UnitClass in hot path)
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
    -- Party / Extra / Boss frames are NOT in `allButtons`, so UpdateAllButtons
    -- misses them. Repaint their health (fill + background) too, so colour and
    -- Dark Mode changes pushed through ApplyColorsToOUF reach every frame type,
    -- not just raid. _UpdateButtonHealth is lightweight + combat-safe and self-
    -- guards on unstyled / non-existent units.
    if ns._UpdateButtonHealth then
        if ns._partyUnitToButton then
            for _, btn in pairs(ns._partyUnitToButton) do ns._UpdateButtonHealth(btn) end
        end
        if ns._xfUnitToButton then
            for _, btn in pairs(ns._xfUnitToButton) do ns._UpdateButtonHealth(btn) end
        end
        if ns._FB and ns._FB.buttons then
            for _, btn in ipairs(ns._FB.buttons) do ns._UpdateButtonHealth(btn) end
        end
    end
end

-- Lightweight: only toggle raid markers on each button (for RAID_TARGET_UPDATE)
ns._UpdateRaidMarkers = function()
    local function updateMarker(unit, btn)
        local d = GetFFD(btn)
        local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
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
    for unit, btn in pairs(ns._xfUnitToButton) do updateMarker(unit, btn) end
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
    for unit, btn in pairs(ns._xfUnitToButton) do updateTarget(unit, btn) end
end

-- Lightweight: only refresh role icons on each button. Driven by combat
-- transitions so the "Hide In Combat" cog can suppress/restore the icons
-- without a full per-button repaint. Texture Show/Hide is combat-legal (not a
-- protected frame op), so this is safe to run from PLAYER_REGEN_DISABLED.
ns._UpdateRoleIcons = function()
    local function updateRole(unit, btn)
        local d = GetFFD(btn)
        if not d.roleIcon then return end
        local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
        ns._UpdateRoleIcon(d, s, unit)
    end
    for unit, btn in pairs(unitToButton) do updateRole(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do updateRole(unit, btn) end
    for unit, btn in pairs(ns._xfUnitToButton) do updateRole(unit, btn) end
end

-- Lightweight: only refresh leader/assistant icons on each button. Driven by
-- combat transitions so the "Show In Combat" cog can suppress/restore the icon
-- without a full per-button repaint. Texture Show/Hide is combat-legal.
ns._UpdateLeaderIcons = function()
    local function updateLeader(unit, btn)
        local d = GetFFD(btn)
        if not d.leaderIcon then return end
        local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
        ns._UpdateLeaderIcon(d, s, unit)
    end
    for unit, btn in pairs(unitToButton) do updateLeader(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do updateLeader(unit, btn) end
    for unit, btn in pairs(ns._xfUnitToButton) do updateLeader(unit, btn) end
end

-- Lightweight: only refresh combat icons on each button. Driven by UNIT_FLAGS
-- (per-unit combat flag flips) and combat transitions. Texture Show/Hide is
-- combat-legal, so this is safe to run from PLAYER_REGEN_DISABLED.
ns._UpdateCombatIcons = function()
    local function updateCombat(unit, btn)
        local d = GetFFD(btn)
        if not d.combatIcon then return end
        local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
        ns._UpdateCombatIcon(d, s, unit)
    end
    for unit, btn in pairs(unitToButton) do updateCombat(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do updateCombat(unit, btn) end
    for unit, btn in pairs(ns._xfUnitToButton) do updateCombat(unit, btn) end
end

-- Single-unit combat icon refresh for UNIT_FLAGS routing (raid + party).
ns._UpdateCombatIconFor = function(unit, btn)
    local d = GetFFD(btn)
    if not d.combatIcon then return end
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    ns._UpdateCombatIcon(d, s, unit)
end

-- True when the combat icon is enabled anywhere (raid or effective party). Used
-- to skip all combat-icon work while the feature is off.
ns._CombatIconEnabled = function()
    if not (db and db.profile) then return false end
    if db.profile.showCombatIndicator then return true end
    if ns._partyProxy.showCombatIndicator then return true end
    return false
end

-- Register UNIT_FLAGS on the per-unit trackers ONLY while the combat icon is
-- enabled (raid uses its own key; party its effective key). When the option is
-- off, no tracker listens for UNIT_FLAGS, so the disabled feature runs no event
-- code at all. Event (un)registration is combat-legal. Extra Frames trackers
-- are gated separately inside XF_Apply. Called from ReloadFrames and once after
-- the trackers are built.
ns.UpdateCombatEventRegistration = function()
    if not (db and db.profile) then return end
    local raidWant  = db.profile.showCombatIndicator and true or false
    local partyWant = ns._partyProxy.showCombatIndicator and true or false
    for unit, tracker in pairs(unitTrackers) do
        local want
        if unit == "player" then
            want = raidWant or partyWant
        elseif unit:find("^party%d") then
            want = partyWant
        else
            want = raidWant
        end
        if want then
            tracker:RegisterUnitEvent("UNIT_FLAGS", unit)
        else
            tracker:UnregisterEvent("UNIT_FLAGS")
        end
    end
end

-- Lightweight: health-only update for UNIT_HEALTH / UNIT_MAXHEALTH.
-- Skips power, name, role, leader, marker, target, threat -- those don't
-- change on health events and are handled by their own event paths.
ns._UpdateButtonHealth = function(button)
    local unit = button:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end
    local d = GetFFD(button)
    if not d.styled then return end
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile

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
            -- 4th return of GetDarkModeFill() is the Dark Mode Fill Opacity.
            if fillTex then fillTex:SetAlpha(select(4, EllesmereUI.GetDarkModeFill())) end
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

    -- Heal absorb text
    if d.healAbsorbText then
        if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
            d.healAbsorbText:SetText("")
        else
            ns.SetHealAbsorbText(d.healAbsorbText, unit, s)
        end
    end

    -- Status text (dead/ghost state changes with health)
    if d.statusText then
        local stc = s.statusTextColor or { r = 1, g = 1, b = 1 }
        if s.statusTextPosition == "none" then
            d.statusText:Hide()
        elseif db.profile.showIncomingRez and UnitHasIncomingResurrection(unit) then
            -- Being resurrected: hide DEAD so the incoming-rez icon isn't covered.
            d.statusText:Hide()
        elseif UnitIsDeadOrGhost(unit) then
            d.statusText:SetText(EllesmereUI.L("DEAD"))
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            d.statusText:Show()
        elseif not UnitIsConnected(unit) then
            d.statusText:SetText(EllesmereUI.L("OFFLINE"))
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            d.statusText:Show()
        elseif s.statusShowAFK and UnitIsAFK and not issecretvalue(UnitIsAFK(unit)) and UnitIsAFK(unit) then
            d.statusText:SetText(EllesmereUI.L("AFK"))
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            d.statusText:Show()
        else
            d.statusText:Hide()
        end
    end

    -- Background + dead/offline status tint. This path owns death/resurrect
    -- transitions arriving via UNIT_HEALTH, so it restores the bg when alive.
    ns._ApplyHealthBg(d, health, s, unit)
end

-------------------------------------------------------------------------------
--  Friendly Boss Frames (raid only)
--  Five standalone secure unit buttons for boss1-boss5. Encounters expose
--  healable friendly NPCs as boss units, so a secure visibility driver on
--  [@bossN,help] is the entire detection -- no NPC database, fully combat
--  safe. The buttons render ONLY a health bar, name text and health text,
--  all following the raid-frame settings for those elements. Deliberately
--  excluded from the preview system and unlock mode; the Free Move position
--  uses its own drag overlay. Display "healers" activates the feature only
--  while the player is on a healer spec (nothing is even built otherwise).
-------------------------------------------------------------------------------
-- Scope block: the file is at Lua 5.1's 200-local cap for the main chunk, so
-- FB must not occupy a main-chunk slot. Inside do/end its register frees at
-- the block close; the closures below keep it alive as an upvalue.
do
local FB = { buttons = {}, trackers = {} }
ns._FB = FB

-- Baseline heal per healer class for NPC range checks. Boss units sit outside
-- UnitInRange's group-member domain and never fire UNIT_IN_RANGE_UPDATE, so
-- range is measured against a known helpful spell instead -- healer specs
-- only; everyone else keeps full alpha (no range checking at all).
FB.RANGE_HEAL = {
    PRIEST  = 2061,   -- Flash Heal
    PALADIN = 19750,  -- Flash of Light
    SHAMAN  = 8004,   -- Healing Surge
    DRUID   = 8936,   -- Regrowth
    MONK    = 116670, -- Vivify
    EVOKER  = 361469, -- Living Flame (25yd: native Evoker range)
}

-- Secret-safe alpha application (result may be secret in instances, which
-- SetAlphaFromBoolean accepts natively). The result can also be NIL (unit not
-- range-checkable right now / spell momentarily not evaluable), which it
-- rejects -- treat that as in range. issecretvalue runs first so the nil
-- check never touches a secret.
FB.ApplyRange = function(b)
    if not FB.rangeSpell then return end
    local s = ns._scaledProfile or db.profile
    local inRange = C_Spell.IsSpellInRange(FB.rangeSpell, FB.UnitOf(b))
    if issecretvalue(inRange) or inRange ~= nil then
        b:SetAlphaFromBoolean(inRange, 1, s.oorAlpha or 0.4)
    else
        b:SetAlpha(1)
    end
end

FB.RangeTick = function()
    for _, b in ipairs(FB.buttons) do
        if b:IsVisible() then FB.ApplyRange(b) end
    end
end

-- The ticker exists only while a range spell is resolved AND at least one
-- boss button is actually visible (specific encounters only) -- zero idle cost.
FB.UpdateRangeTicker = function()
    local want = FB.rangeSpell and (FB.visCount or 0) > 0
    if want and not FB.rangeTicker then
        FB.rangeTicker = C_Timer.NewTicker(0.4, FB.RangeTick)
    elseif not want and FB.rangeTicker then
        FB.rangeTicker:Cancel()
        FB.rangeTicker = nil
    end
end

-- Current unit for a button. The slot controller reassigns units so friendly
-- bosses collapse into the FIRST slots (boss2 friendly while boss1 is the
-- enemy -> slot 1 shows boss2); the live truth is the secure "unit"
-- attribute. _fbUnit is only the build-time default.
FB.UnitOf = function(b)
    return b:GetAttribute("unit") or b._fbUnit
end

FB.Settings = function()
    return db and db.profile and db.profile.friendlyBoss
end

FB.ShouldBeActive = function()
    local fb = FB.Settings()
    if not fb then return false end
    if fb.display == "always" then return true end
    if fb.display == "healers" then
        local spec = GetSpecialization and GetSpecialization()
        local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
        return role == "HEALER"
    end
    return false
end

-- Anchor a FontString using the same position vocabulary as the raid frames'
-- name/health text anchors (AnchorNameText/AnchorHealthText).
FB.AnchorText = function(fs, health, pos, ox, oy)
    fs:ClearAllPoints()
    if pos == "topleft" then
        fs:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    elseif pos == "top" then
        fs:SetPoint("TOP", health, "TOP", ox, -2 + oy)
        fs:SetJustifyH("CENTER"); fs:SetJustifyV("TOP")
    elseif pos == "topright" then
        fs:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
        fs:SetJustifyH("RIGHT"); fs:SetJustifyV("TOP")
    elseif pos == "left" then
        fs:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("MIDDLE")
    elseif pos == "right" then
        fs:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
        fs:SetJustifyH("RIGHT"); fs:SetJustifyV("MIDDLE")
    elseif pos == "bottomleft" then
        fs:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("BOTTOM")
    elseif pos == "bottom" then
        fs:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
        fs:SetJustifyH("CENTER"); fs:SetJustifyV("BOTTOM")
    elseif pos == "bottomright" then
        fs:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
        fs:SetJustifyH("RIGHT"); fs:SetJustifyV("BOTTOM")
    else -- "center"
        fs:SetPoint("CENTER", health, "CENTER", ox, oy)
        fs:SetJustifyH("CENTER"); fs:SetJustifyV("MIDDLE")
    end
    -- Force re-render after a JustifyH change
    local txt = fs:GetText()
    fs:SetText("")
    fs:SetText(txt or "")
end

-- Recolor the border for the current state. Mirrors the raid buttons' single
-- recolored border: hover (raised) > target (raised) > normal, using the same
-- raid border settings -- nothing is configurable separately here.
FB.ApplyBorderColor = function(b)
    if not PP or not b._borderFrame or not db then return end
    local s = ns._scaledProfile or db.profile
    if (s.borderSize or 1) <= 0 then return end
    local r, g, bcol, a
    local raised = false
    if b._fbHovered and s.hoverBorderEnabled ~= false then
        local c = s.hoverBorderColor or { r = 1, g = 1, b = 1 }
        r, g, bcol, a = c.r, c.g, c.b, s.hoverBorderAlpha or 1
        raised = true
    elseif UnitIsUnit(FB.UnitOf(b), "target") and s.targetBorderEnabled ~= false then
        local c = s.targetBorderColor or { r = 1, g = 1, b = 1 }
        r, g, bcol, a = c.r, c.g, c.b, s.targetBorderAlpha or 1
        raised = true
    else
        local c = s.borderColor or { r = 0, g = 0, b = 0 }
        r, g, bcol, a = c.r, c.g, c.b, s.borderAlpha or 1
    end
    -- Raise above neighboring frames while highlighted (same reasoning as the
    -- raid buttons: overlapping frames would cover the highlight otherwise).
    local pl = b:GetFrameLevel()
    local lvl = s.borderBehind and math.max(0, pl - 1) or (pl + (raised and ns.LVL_RAISE or 8))
    if b._borderFrame:GetFrameLevel() ~= lvl then
        b._borderFrame:SetFrameLevel(lvl)
        local container = PP.GetBorders(b._borderFrame)
        if container then container:SetFrameLevel(lvl + 1) end
    end
    EllesmereUI.SetBorderStyleColor(b._borderFrame, r, g, bcol, a)
end

-- Apply the raid border style (size/color/texture/offsets) to one button.
FB.StyleBorder = function(b)
    if not PP or not b._borderFrame then return end
    local s = ns._scaledProfile or db.profile
    local bs = s.borderSize or 1
    local bc = s.borderColor or { r = 0, g = 0, b = 0 }
    local pl = b:GetFrameLevel()
    b._borderFrame:SetFrameLevel(s.borderBehind and math.max(0, pl - 1) or (pl + 8))
    EllesmereUI.ApplyBorderStyle(b._borderFrame, bs, bc.r, bc.g, bc.b, s.borderAlpha or 1,
        s.borderTexture or "solid", s.borderTextureOffset, s.borderTextureOffsetY,
        s.borderTextureShiftX, s.borderTextureShiftY, "unitframes", bs)
    FB.ApplyBorderColor(b)
end

-- Refresh one boss button: health bar value/color, health text, name text.
-- Mirrors the corresponding slices of UpdateButton/_UpdateButtonHealth; boss
-- units are not group units, so this never touches the roster hot paths.
FB.Update = function(b)
    local unit = FB.UnitOf(b)
    if not db or not UnitExists(unit) then return end
    local s = ns._scaledProfile or db.profile
    local health = b._health

    local pct = GetSafeHealthPercent(unit)
    health:SetMinMaxValues(0, 100)
    local smooth = s.smoothBars and Enum and Enum.StatusBarInterpolation
        and Enum.StatusBarInterpolation.ExponentialEaseOut
    if smooth then health:SetValue(pct, smooth) else health:SetValue(pct) end
    -- Own color setting (defaults #17AC31). The raid color modes mislead
    -- here: gradient modes read as damage states and many NPCs carry real
    -- class tokens (a friendly add can come out Rogue-yellow).
    local fbc = FB.Settings()
    fbc = fbc and fbc.healthColor
    local fillTex = health:GetStatusBarTexture()
    if fillTex then fillTex:SetAlpha(1) end
    health:SetStatusBarColor(fbc and fbc.r or 23/255, fbc and fbc.g or 172/255,
        fbc and fbc.b or 49/255, (s.healthBarOpacity or 100) / 100)

    if b._nameText then
        b._nameText:SetText(ResolveDisplayName(unit, true))
        local nr, ng, nb = GetNameColor(unit, s)
        b._nameText:SetTextColor(nr, ng, nb)
    end

    if b._healthText then
        local mode = s.healthTextMode or "none"
        if UnitIsDeadOrGhost(unit) then
            b._healthText:SetText("")
        elseif mode == "percent" then
            b._healthText:SetFormattedText("%.0f%%", pct)
        elseif mode == "percentNoSign" then
            b._healthText:SetFormattedText("%.0f", pct)
        elseif mode == "number" then
            local curr = UnitHealth(unit, true)
            if curr and AbbreviateNumbers then
                b._healthText:SetText(AbbreviateNumbers(curr))
            elseif curr then
                b._healthText:SetFormattedText("%s", curr)
            end
        elseif mode == "numberPercent" then
            local curr = UnitHealth(unit, true)
            local numStr = (curr and AbbreviateNumbers) and AbbreviateNumbers(curr) or tostring(curr or 0)
            b._healthText:SetFormattedText("%s | %.0f%%", numStr, pct)
        elseif mode == "percentNumber" then
            local curr = UnitHealth(unit, true)
            local numStr = (curr and AbbreviateNumbers) and AbbreviateNumbers(curr) or tostring(curr or 0)
            b._healthText:SetFormattedText("%.0f%% | %s", pct, numStr)
        else
            b._healthText:SetText("")
        end
        if mode ~= "none" then
            local htr, htg, htb = GetHealthTextColor(unit, s)
            b._healthText:SetTextColor(htr, htg, htb, 0.9)
        end
    end

    if b._healAbsorbText then
        if UnitIsDeadOrGhost(unit) then b._healAbsorbText:SetText("")
        else ns.SetHealAbsorbText(b._healAbsorbText, unit, s) end
    end

    FB.ApplyBorderColor(b)
end

-- One-time construction of the container, the five buttons, click-cast
-- registration and per-unit event trackers. Buttons are created hidden;
-- the secure visibility drivers own show/hide from then on.
FB.EnsureBuilt = function()
    if FB.built then return end
    FB.built = true

    local container = CreateFrame("Frame", "ERFFriendlyBossContainer", UIParent)
    container:Hide()
    FB.container = container

    for i = 1, 5 do
        local b = CreateFrame("Button", "ERFFriendlyBoss" .. i, container, "SecureUnitButtonTemplate")
        b._fbUnit = "boss" .. i
        b:SetAttribute("unit", b._fbUnit)
        b:SetAttribute("*type1", "target")
        b:RegisterForClicks("AnyUp")
        -- 12.0.7 gates SecureUnitButton's togglemenu; route right-click securely
        -- through a SecureActionButton proxy so the menu works without taint.
        if EllesmereUI.AttachSecureUnitMenu then
            EllesmereUI.AttachSecureUnitMenu(b)
        else
            b:SetAttribute("*type2", "togglemenu")
        end
        b:Hide()

        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if PP then PP.DisablePixelSnap(bg) end
        b._bg = bg

        local health = CreateFrame("StatusBar", nil, b)
        health:SetFrameLevel(b:GetFrameLevel() + 2)
        health:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        health:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
        if PP then PP.DisablePixelSnap(health) end
        health:SetMinMaxValues(0, 100)
        health:SetValue(100)
        b._health = health

        local carrier = CreateFrame("Frame", nil, b)
        carrier:SetAllPoints(health)
        carrier:SetFrameLevel(b:GetFrameLevel() + ns.LVL_TEXT)
        local nameFS = carrier:CreateFontString(nil, "OVERLAY")
        nameFS:SetWordWrap(false)
        b._nameText = nameFS
        local healthFS = carrier:CreateFontString(nil, "OVERLAY")
        healthFS:SetWordWrap(false)
        b._healthText = healthFS
        local healAbsorbFS = carrier:CreateFontString(nil, "OVERLAY")
        healAbsorbFS:SetWordWrap(false)
        b._healAbsorbText = healAbsorbFS

        -- Border frame (same construction as the raid buttons; styled via the
        -- shared raid border settings in FB.StyleBorder)
        local bdr = CreateFrame("Frame", nil, b)
        bdr:SetAllPoints(b)
        bdr:SetFrameLevel(b:GetFrameLevel() + 8)
        b._borderFrame = bdr

        -- Refresh as soon as the driver shows the button (initial spawn state);
        -- visible-count drives the range ticker lifecycle.
        b:HookScript("OnShow", function(self)
            FB.visCount = (FB.visCount or 0) + 1
            -- Containers first: the legacy refresh below still has
            -- restriction-era failure modes, and an error there must not
            -- starve the container of its unit assignment.
            if ns.RFC_OnUnitAssigned then
                local d = GetFFD(self)
                local unit = FB.UnitOf(self)
                if d and unit then ns.RFC_OnUnitAssigned(self, d, unit) end
            end
            FB.Update(self)
            FB.ApplyRange(self)
            FB.UpdateRangeTicker()
        end)
        b:HookScript("OnHide", function(self)
            FB.visCount = math.max(0, (FB.visCount or 0) - 1)
            FB.UpdateRangeTicker()
        end)

        -- Hover highlight (these are our own buttons; hooks are safe)
        b:HookScript("OnEnter", function(self)
            self._fbHovered = true
            FB.ApplyBorderColor(self)
        end)
        b:HookScript("OnLeave", function(self)
            self._fbHovered = nil
            FB.ApplyBorderColor(self)
        end)

        -- Re-render when the slot controller reassigns this slot's unit
        -- mid-combat (a friendly boss spawning/despawning reflows the slots
        -- without an OnShow on already-visible buttons).
        b:HookScript("OnAttributeChanged", function(self, name)
            if name == "unit" and self:IsVisible() then
                -- Containers first (same rationale as the OnShow hook).
                if ns.RFC_OnUnitAssigned then
                    local d = GetFFD(self)
                    local unit = FB.UnitOf(self)
                    if d and unit then ns.RFC_OnUnitAssigned(self, d, unit) end
                end
                FB.Update(self)
                FB.ApplyRange(self)
            end
        end)

        -- Full click-cast / hovercast binding suite (mouseover heals included)
        if ns.CC_RegisterFrame then ns.CC_RegisterFrame(b) end

        -- Boss units are outside the roster trackers; track them here. The
        -- slot controller may have assigned this boss unit to ANY slot, so
        -- route the event to whichever button currently shows it.
        local unitId = "boss" .. i
        local t = CreateFrame("Frame")
        t:RegisterUnitEvent("UNIT_HEALTH", unitId)
        t:RegisterUnitEvent("UNIT_MAXHEALTH", unitId)
        t:RegisterUnitEvent("UNIT_NAME_UPDATE", unitId)
        t:SetScript("OnEvent", function()
            for _, btn in ipairs(FB.buttons) do
                if btn:IsVisible() and btn:GetAttribute("unit") == unitId then
                    FB.Update(btn)
                    break
                end
            end
        end)
        FB.trackers[i] = t

        FB.buttons[i] = b

        if ns.RFC_SetupButton then
            local d = GetFFD(b)
            ns.RFC_SetupButton(b, b._health, d)
        end
    end

    -- Slot controller: collapses friendly bosses into the FIRST slots. Button
    -- positions stay fixed; the controller assigns boss units to slots in
    -- bossN order and shows/hides the buttons. Runs in the restricted
    -- environment so mid-combat spawns/despawns reflow safely (insecure code
    -- cannot Show/Hide or re-unit protected buttons in combat). Drivers are
    -- registered in FB_Apply; they feed state-inraid / state-fb1..5 here.
    -- One shared body bound per attribute (no wildcard handler, no reliance
    -- on the snippet's `name` local); FB_Apply also force-runs it via
    -- SecureHandlerExecute because the driver manager skips the attribute
    -- handler when a re-registered driver's value is unchanged.
    FB.RELAYOUT = [[
        local inraid = self:GetAttribute("state-inraid")
        local slot = 0
        if inraid == 1 or inraid == "1" then
            for i = 1, 5 do
                local v = self:GetAttribute("state-fb" .. i)
                if v == 1 or v == "1" then
                    slot = slot + 1
                    local b = self:GetFrameRef("slot" .. slot)
                    if b then
                        b:SetAttribute("unit", "boss" .. i)
                        b:Show()
                    end
                end
            end
        end
        for j = slot + 1, 5 do
            local b = self:GetFrameRef("slot" .. j)
            if b then b:Hide() end
        end
    ]]
    local controller = CreateFrame("Frame", "ERFFriendlyBossController", nil, "SecureHandlerAttributeTemplate")
    for i = 1, 5 do
        controller:SetFrameRef("slot" .. i, FB.buttons[i])
    end
    -- The template's handler attribute is "_onattributechanged" (single
    -- wildcard receiving name/value -- same idiom as the Action Bars
    -- controllers). The relayout body lives in its own attribute so the
    -- handler and FB_Apply's force-run share one definition.
    controller:SetAttributeNoHandler("fb_relayout", FB.RELAYOUT)
    controller:SetAttributeNoHandler("_onattributechanged", [[
        if name == "state-inraid" or name == "state-fb1" or name == "state-fb2"
           or name == "state-fb3" or name == "state-fb4" or name == "state-fb5" then
            self:RunAttribute("fb_relayout")
        end
    ]])
    FB.controller = controller
end

-- Re-apply all setting-derived properties (size, slots, texture, fonts,
-- text anchors). Out-of-combat only; callers gate. The owner parameter lets
-- the Extra Frames duplicates (ns._XF) share this verbatim: an owner carries
-- buttons/container/Settings and defaults to FB itself.
FB.ApplyStyle = function(owner)
    owner = owner or FB
    if not owner.built then return end
    local s = ns._scaledProfile or db.profile
    local fbset = owner.Settings()
    -- Per-group size offset on top of the shared raid frame size (Extra
    -- Width/Height sliders; clamped so a negative offset can't invert a
    -- small frame).
    local w = PixelSnap(math.max(10, (s.frameWidth or 125) + ((fbset and fbset.extraWidth) or 0)))
    local h = PixelSnap(math.max(10, (s.frameHeight or 60) + ((fbset and fbset.extraHeight) or 0)))
    local sp = s.cellSpacing or -1
    -- Free Move ignores the raid growth settings entirely: simple vertical
    -- stack by default, horizontal via the Horizontal Frames cog toggle.
    -- Attached modes keep stacking like a real group (unitGrowth).
    local grow
    if fbset and fbset.position == "free" then
        grow = fbset.freeHorizontal and "RIGHT" or "DOWN"
    else
        grow = s.unitGrowth or "DOWN"
    end
    local texPath = ResolveHealthTexture()
    local bgc = s.customBgColor or { r = 17/255, g = 17/255, b = 17/255 }

    local stepW, stepH = 0, 0
    if grow == "DOWN" or grow == "UP" then
        owner.container:SetSize(w, h * 5 + sp * 4)
        stepH = h + sp
    else
        owner.container:SetSize(w * 5 + sp * 4, h)
        stepW = w + sp
    end

    for i, b in ipairs(owner.buttons) do
        b:SetSize(w, h)
        b:ClearAllPoints()
        local off = i - 1
        if grow == "UP" then
            b:SetPoint("BOTTOMLEFT", owner.container, "BOTTOMLEFT", 0, off * stepH)
        elseif grow == "LEFT" then
            b:SetPoint("TOPRIGHT", owner.container, "TOPRIGHT", -off * stepW, 0)
        elseif grow == "RIGHT" then
            b:SetPoint("TOPLEFT", owner.container, "TOPLEFT", off * stepW, 0)
        else -- DOWN
            b:SetPoint("TOPLEFT", owner.container, "TOPLEFT", 0, -off * stepH)
        end

        b._bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
        b._health:SetStatusBarTexture(texPath)
        local ft = b._health:GetStatusBarTexture()
        if ft then ft:SetHorizTile(false) end
        -- No power bar / top name bar here: health fills the button.
        b._health:SetHeight(h)

        ApplyFont(b._nameText, s.nameSize or 10)
        ApplyFont(b._healthText, s.healthTextSize or 9)
        b._nameText:SetWidth(w * ns.RF_NAME_WIDTH_FRACTION)
        b._nameText:SetHeight(0)
        b._healthText:SetWidth(w * 0.75)
        b._healthText:SetHeight(0)
        local namePos = s.namePosition or "center"
        if namePos == "none" then
            b._nameText:Hide()
        else
            b._nameText:Show()
            FB.AnchorText(b._nameText, b._health, namePos, s.nameOffsetX or 0, s.nameOffsetY or 0)
        end
        FB.AnchorText(b._healthText, b._health, s.healthTextPosition or "center",
            s.healthTextOffsetX or 0, s.healthTextOffsetY or 0)
        if b._healAbsorbText then
            ApplyFont(b._healAbsorbText, s.healAbsorbTextSize or 9)
            b._healAbsorbText:SetWidth(w * 0.75)
            b._healAbsorbText:SetHeight(0)
            FB.AnchorText(b._healAbsorbText, b._health, s.healAbsorbTextPosition or "center",
                s.healAbsorbTextOffsetX or 0, s.healAbsorbTextOffsetY or 0)
        end
        FB.StyleBorder(b)
    end
end

-- Position the container per the position setting. The container effectively
-- inherits protection from its secure children, so SetPoint is OOC-only.
-- Owner-parameterized like ApplyStyle (Extra Frames share the exact
-- left/right/free slotting behavior).
FB.Anchor = function(owner)
    owner = owner or FB
    if not owner.built then return end
    if InCombatLockdown() then owner.anchorDirty = true; return end
    local s = db.profile
    local fb = owner.Settings()
    local c = owner.container
    c:ClearAllPoints()

    if fb.position ~= "free" then
        local anchorHdr
        -- Chain rule: when the boss group (owner == FB) and the Extra Frames
        -- group are attached to the SAME side, the boss group anchors to the
        -- extra container instead of the raid -- order along the growth axis
        -- is raid -> extra frames -> boss frames (mirrored on "left").
        -- Extra Frames always anchor to the raid itself; ns.XF_Apply re-runs
        -- this anchor whenever that container shows, hides or moves.
        if owner == FB then
            local xf = ns._XF
            local xs = xf and xf.Settings and xf.Settings()
            if xs and xs.position == fb.position and xf.built
               and xf.container and xf.container:IsShown() then
                anchorHdr = xf.container
            end
        end
        if not anchorHdr and s.mergeGroups then
            anchorHdr = ns._flatHeader
        elseif not anchorHdr then
            -- The boss group behaves like one more raid group: it slots in
            -- before the first / after the last group that is BOTH enabled
            -- in Show Groups AND currently has players in it. When no group
            -- is populated (not in a raid yet), fall back to the Show Groups
            -- bounds alone so the position is still sane.
            local vg = s.visibleGroups or {}
            local occupied = {}
            for ri = 1, GetNumGroupMembers() or 0 do
                local _, _, sub = GetRaidRosterInfo(ri)
                if sub then occupied[sub] = true end
            end
            local first, last
            for gi = 1, 8 do
                if vg[gi] ~= false and separatedHdrs[gi] and occupied[gi] then
                    if not first then first = separatedHdrs[gi] end
                    last = separatedHdrs[gi]
                end
            end
            if not first then
                for gi = 1, 8 do
                    if vg[gi] ~= false and separatedHdrs[gi] then
                        if not first then first = separatedHdrs[gi] end
                        last = separatedHdrs[gi]
                    end
                end
            end
            anchorHdr = (fb.position == "left") and first or last
        end
        if anchorHdr then
            -- Slot in along the group growth axis exactly like a real group.
            local gap = s.groupSpacing or -1
            local grow = s.groupGrowth or "RIGHT"
            local before = (fb.position == "left")
            if grow == "RIGHT" then
                if before then c:SetPoint("TOPRIGHT", anchorHdr, "TOPLEFT", -gap, 0)
                else c:SetPoint("TOPLEFT", anchorHdr, "TOPRIGHT", gap, 0) end
            elseif grow == "LEFT" then
                if before then c:SetPoint("TOPLEFT", anchorHdr, "TOPRIGHT", gap, 0)
                else c:SetPoint("TOPRIGHT", anchorHdr, "TOPLEFT", -gap, 0) end
            elseif grow == "DOWN" then
                if before then c:SetPoint("BOTTOMLEFT", anchorHdr, "TOPLEFT", 0, gap)
                else c:SetPoint("TOPLEFT", anchorHdr, "BOTTOMLEFT", 0, -gap) end
            else -- UP
                if before then c:SetPoint("TOPLEFT", anchorHdr, "BOTTOMLEFT", 0, -gap)
                else c:SetPoint("BOTTOMLEFT", anchorHdr, "TOPLEFT", 0, gap) end
            end
            return
        end
        -- No usable group header: fall through to the free position.
    end

    -- Owner-specific free anchoring (Extra Frames pins the grid's growth
    -- corner so the group grows away from it); legacy CENTER pin otherwise.
    if owner.FreeAnchor and owner.FreeAnchor(c, fb) then return end
    local p = fb.freePos or {}
    c:SetPoint("CENTER", UIParent, "CENTER", p.x or 100, p.y or 0)
end

-- Master apply: activates, deactivates and refreshes the whole feature.
-- Called from OnEnable, the options dropdowns, spec changes, profile swaps
-- (_ERF_RefreshAll) and the post-combat dirty pass.
function ns.FB_Apply()
    if not db or not db.profile then return end
    local fb = FB.Settings()
    if not fb then return end
    if InCombatLockdown() then FB.applyDirty = true; return end

    if not FB.ShouldBeActive() then
        if FB.built then
            if FB.controller then
                UnregisterAttributeDriver(FB.controller, "state-inraid")
                for i = 1, 5 do
                    UnregisterAttributeDriver(FB.controller, "state-fb" .. i)
                end
            end
            for _, b in ipairs(FB.buttons) do
                b:Hide()
            end
            FB.container:Hide()
        end
        if FB.mover then FB.mover:Hide() end
        FB.rangeSpell = nil
        FB.UpdateRangeTicker()
        return
    end

    FB.EnsureBuilt()
    FB.ApplyStyle()
    FB.Anchor()
    FB.container:Show()
    -- Drivers feed the slot controller, which assigns friendly bosses to the
    -- first slots in bossN order and shows/hides the buttons securely.
    RegisterAttributeDriver(FB.controller, "state-inraid", "[@raid1,exists] 1; 0")
    for i = 1, 5 do
        RegisterAttributeDriver(FB.controller, "state-fb" .. i, "[@boss" .. i .. ",help] 1; 0")
    end
    -- Force one relayout now: the driver manager only fires the attribute
    -- handlers on VALUE CHANGES, so a (re)apply with unchanged states would
    -- otherwise never run the initial layout. FB_Apply is OOC-only, so the
    -- insecure Execute is always legal here.
    if SecureHandlerExecute then
        SecureHandlerExecute(FB.controller, FB.RELAYOUT)
    end
    for _, b in ipairs(FB.buttons) do
        if b:IsVisible() then FB.Update(b) end
    end

    -- Range dimming: healer specs only (regardless of display mode).
    local spec = GetSpecialization and GetSpecialization()
    local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
    local _, pClass = UnitClass("player")
    FB.rangeSpell = (role == "HEALER") and FB.RANGE_HEAL[pClass] or nil
    if not FB.rangeSpell then
        for _, b in ipairs(FB.buttons) do b:SetAlpha(1) end
    else
        for _, b in ipairs(FB.buttons) do
            if b:IsVisible() then FB.ApplyRange(b) end
        end
    end
    FB.UpdateRangeTicker()
end

function ns.FB_IsMoverShown()
    return FB.mover and FB.mover:IsShown() or false
end

-- Free Move drag overlay (unlock-mode look, TOOLTIP strata so it floats
-- above the options panel). Deliberately independent of unlock mode.
-- Owner-parameterized: the Extra Frames group builds its own mover through
-- this exact code with its own name/label (mover stored at owner.mover).
FB.SetMoverShown = function(owner, show, frameName, labelText)
    if not show then
        if owner.mover then owner.mover:Hide() end
        return
    end
    local fb = owner.Settings()
    if not fb or fb.position ~= "free" then return end
    owner.EnsureBuilt()
    -- Owners with their own geometry pass (Extra Frames) restyle through it;
    -- FB-built buttons go through the FB styler.
    if owner.Layout then owner.Layout() else FB.ApplyStyle(owner) end
    FB.Anchor(owner)

    if not owner.mover then
        local m = CreateFrame("Frame", frameName, UIParent)
        m:SetFrameStrata("TOOLTIP")
        m:SetClampedToScreen(true)
        m:SetMovable(true)
        m:EnableMouse(true)
        m:RegisterForDrag("LeftButton")
        local mbg = m:CreateTexture(nil, "BACKGROUND")
        mbg:SetAllPoints()
        mbg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
        local ar, ag, ab = EllesmereUI.ResolveActiveAccent()
        if EllesmereUI.MakeBorder then
            EllesmereUI.MakeBorder(m, ar or 1, ag or 1, ab or 1, 0.6)
        end
        local lbl = m:CreateFontString(nil, "OVERLAY")
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(lbl, true) end
        lbl:SetFont(EllesmereUI.GetFontPath("raidFrames"), 11, "")
        lbl:SetTextColor(1, 1, 1, 0.75)
        lbl:SetPoint("CENTER", m, "CENTER")
        lbl:SetWordWrap(false)
        lbl:SetText(labelText)
        m:SetScript("OnDragStart", function(self) self:StartMoving() end)
        m:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local cx, cy = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if cx and ux then
                local set = owner.Settings()
                if set then
                    set.freePos = {
                        x = math.floor(cx - ux + 0.5),
                        y = math.floor(cy - uy + 0.5),
                    }
                end
            end
            -- Corner-pinned owners also capture the dropped rect
            if owner.SaveFreeRect then owner.SaveFreeRect(self) end
            FB.Anchor(owner)
        end)
        owner.mover = m
        -- Close the mover with the options panel so it can't be stranded.
        if EllesmereUI._mainFrame then
            EllesmereUI._mainFrame:HookScript("OnHide", function() m:Hide() end)
        end
    end

    owner.mover:SetSize(owner.container:GetWidth(), owner.container:GetHeight())
    owner.mover:ClearAllPoints()
    local oset = owner.Settings() or {}
    if owner.FreeAnchor and oset.freeRect then
        -- Corner-pinned owners: mirror the container's placement exactly so
        -- the overlay always covers the live grid (FB.Anchor just ran above).
        owner.mover:SetPoint("CENTER", owner.container, "CENTER")
    else
        local p = oset.freePos or {}
        owner.mover:SetPoint("CENTER", UIParent, "CENTER", p.x or 100, p.y or 0)
    end
    owner.mover:Show()
end

function ns.FB_SetMoverShown(show)
    FB.SetMoverShown(FB, show, "ERFFriendlyBossMover", "Friendly Boss Frames")
end

-- Standing event frame: exists even while the feature is inactive so a spec
-- change can activate display="healers" without a /reload.
do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:SetScript("OnEvent", function(_, event)
        if not db then return end
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            ns.FB_Apply()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if FB.applyDirty then FB.applyDirty = nil; ns.FB_Apply() end
            if FB.anchorDirty then FB.anchorDirty = nil; FB.Anchor() end
        elseif not FB.built or not FB.container or not FB.container:IsShown() then
            return
        elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
            for _, b in ipairs(FB.buttons) do
                if b:IsVisible() then FB.Update(b) end
            end
        elseif event == "PLAYER_TARGET_CHANGED" then
            -- Lightweight: only the border state can change here
            for _, b in ipairs(FB.buttons) do
                if b:IsVisible() then FB.ApplyBorderColor(b) end
            end
        elseif event == "GROUP_ROSTER_UPDATE" then
            -- First/last visible group (and the size tier) can shift with
            -- the roster; restyle + re-anchor, deferred through combat.
            if InCombatLockdown() then
                FB.applyDirty = true
            else
                FB.ApplyStyle()
                FB.Anchor()
            end
        end
    end)
    FB.eventFrame = ev
end

-- Temporary diagnostic: /euifb dumps the slot controller's driver states and
-- the per-button layout. Remove once friendly boss frames are confirmed live.
SLASH_EUIFB1 = "/euifb"
SlashCmdList.EUIFB = function()
    print("|cff00d2ffFB|r active:", FB.ShouldBeActive(), "built:", FB.built or false,
        "rangeSpell:", FB.rangeSpell or "none")
    if not FB.built then return end
    local c = FB.controller
    print("  container shown:", FB.container:IsShown(),
        "inraid:", c and tostring(c:GetAttribute("state-inraid")) or "no controller")
    for i = 1, 5 do
        local b = FB.buttons[i]
        print(("  slot%d shown=%s unit=%s | fb%d=%s"):format(
            i, tostring(b:IsShown()), tostring(b:GetAttribute("unit")),
            i, c and tostring(c:GetAttribute("state-fb" .. i)) or "?"))
    end
end
end -- FB scope block

-------------------------------------------------------------------------------
--  Extra Frames (raid only)
--  1:1 duplicate frames for chosen raid members: the raid's tanks (Show
--  Tanks toggle) plus players toggled in with a hotkey while hovering their
--  raid frame. Holds up to XF.CAP members: attached positions stack them in
--  group-sized runs of 5 like additional raid groups; Free Move lays them
--  out on its own grow/wrap axes with optional row/column wrapping and a
--  growth-corner pin (XF.GrowInfo / XF.FreeAnchor). Each duplicate is built
--  through the SAME StyleButton
--  pipeline as the real header children -- power bar, absorbs, auras,
--  defensives, dispel visuals, private auras, BM indicators, role/leader/
--  marker icons, click-cast, ping -- and joins allButtons so every bulk
--  restyle/update pass (ReloadFrames, UpdateAllButtons, ready checks, the
--  in-combat roster repaint, BM spec rescans) covers it automatically.
--
--  Event routing: duplicates must NOT enter unitToButton (one button per
--  unit; the real frame owns the slot -- d._isExtra guards every rebuild).
--  Instead each slot has a tracker frame with RegisterUnitEvent for its
--  assigned unit, mirroring the central hub's per-unit reactions, and the
--  duplicates live in ns._xfUnitToButton which the broadcast passes (target
--  border, raid markers, range seed/refine, ghost-aura sweep) also iterate.
--  Cost is bounded to the duplicated units and is zero when inactive
--  (no registrations, empty map). Container position via the shared
--  FB.Anchor; unit assignment is OOC attribute writes, dirty-deferred
--  through combat. Excluded from preview and unlock mode like FB.
-------------------------------------------------------------------------------
-- Scope block: the file is at Lua 5.1's 200-local cap for the main chunk
-- (see the FB block above for the full rationale).
do
local XF = { buttons = {}, trackers = {} }
ns._XF = XF
local FB = ns._FB

XF.Settings = function()
    return db and db.profile and db.profile.extraFrames
end

XF.ShouldBeActive = function()
    local set = XF.Settings()
    if not set then return false end
    return set.showTanks or #(set.players or {}) > 0
end

-- Hard selection bound (internal, no user setting): enough for a full
-- mythic roster's worth of duplicates while keeping the per-unit event
-- mirroring bounded.
XF.CAP = 20

-- Effective growth axes: primary run direction + perpendicular wrap
-- direction. Attached modes stack group-sized runs of 5 exactly like
-- additional raid groups: units along the raid unit growth, each full run
-- slotting further out along the group growth axis, extending AWAY from the
-- raid ("left" attaches before the first group, so runs extend against the
-- group growth there). Free Move reads the Grow Direction setting, falling
-- back to the legacy Horizontal toggle, and wraps new rows/columns along
-- Wrap Direction. Wrap values that are not perpendicular to the primary run
-- (stale after a direction change, or a parallel group growth) fall back to
-- the default.
XF.GrowInfo = function(set, s)
    local grow, wrap
    if set and set.position == "free" then
        grow = set.growDirection or (set.freeHorizontal and "RIGHT" or "DOWN")
        wrap = set.wrapDirection
    else
        grow = (s and s.unitGrowth) or "DOWN"
        wrap = (s and s.groupGrowth) or "RIGHT"
        if set and set.position == "left" then
            wrap = (wrap == "RIGHT" and "LEFT") or (wrap == "LEFT" and "RIGHT")
                or (wrap == "DOWN" and "UP") or "DOWN"
        end
    end
    local horizontal = (grow == "LEFT" or grow == "RIGHT")
    if horizontal then
        if wrap ~= "UP" and wrap ~= "DOWN" then wrap = "DOWN" end
    else
        if wrap ~= "LEFT" and wrap ~= "RIGHT" then wrap = "RIGHT" end
    end
    return grow, wrap, horizontal
end

-- Free Move anchoring: pin the grid's growth corner to the rect captured at
-- the last mover drag, so the container grows away from that corner and
-- frame 1 never shifts as players enter or leave the selection (the
-- container is sized to the live selection, so a CENTER pin would drift).
-- Falls back to the legacy CENTER anchor (freePos) until the user drags the
-- mover once. Called by FB.Anchor through the owner hook.
XF.FreeAnchor = function(c, set)
    local r = set and set.freeRect
    if not r then return false end
    local grow, wrap, horizontal = XF.GrowInfo(set, db and db.profile)
    local hDir = horizontal and grow or wrap
    local vDir = horizontal and wrap or grow
    local corner = (vDir == "UP" and "BOTTOM" or "TOP")
        .. (hDir == "LEFT" and "RIGHT" or "LEFT")
    c:SetPoint(corner, UIParent, "CENTER",
        (hDir == "LEFT") and r.right or r.left,
        (vDir == "UP") and r.bottom or r.top)
    return true
end

-- Called by the shared mover on drag stop: capture the dropped rect
-- (relative to the UIParent center) for the corner pin above.
XF.SaveFreeRect = function(mover)
    local set = XF.Settings()
    if not set then return end
    local ux, uy = UIParent:GetCenter()
    local l, b, mw, mh = mover:GetRect()
    if not (ux and l) then return end
    set.freeRect = { left = l - ux, right = l + mw - ux,
                     bottom = b - uy, top = b + mh - uy }
end

-- Ordered raid units to duplicate (bounded by XF.CAP): tanks in roster
-- order first (when Show Tanks is on), then the manually added names that are
-- currently in the raid. Names are stored and matched in GetRaidRosterInfo's
-- format on both sides so realm suffixes always agree; names not in the
-- roster are skipped but kept in the list (they reappear when that player
-- rejoins).
XF.ResolveUnits = function()
    local set = XF.Settings()
    local units = {}
    if not set or not IsInRaid() then return units end
    local cap = XF.CAP
    local seen = {}
    local n = GetNumGroupMembers() or 0
    if set.showTanks then
        for i = 1, n do
            if #units >= cap then break end
            local name = GetRaidRosterInfo(i)
            if name and not seen[name]
               and UnitGroupRolesAssigned("raid" .. i) == "TANK" then
                seen[name] = true
                units[#units + 1] = "raid" .. i
            end
        end
    end
    for _, mname in ipairs(set.players or {}) do
        if #units >= cap then break end
        if not seen[mname] then
            for i = 1, n do
                if (GetRaidRosterInfo(i)) == mname then
                    seen[mname] = true
                    units[#units + 1] = "raid" .. i
                    break
                end
            end
        end
    end
    return units
end

-- Geometry only: container size, button stacking, per-button size including
-- the Extra Width/Height offsets, and the height-derived inner corrections
-- (mirrors ns._ResizeButtons). All VISUALS come from the shared StyleButton /
-- ReloadFrames pipeline -- the buttons are in allButtons and restyle with
-- everything else; ReloadFrames tail-calls XF_Apply so this offset pass
-- always runs after the bulk base-size pass.
XF.Layout = function()
    if not XF.built then return end
    local s = ns._scaledProfile or db.profile
    local set = XF.Settings()
    local w = PixelSnap(math.max(10, (ns._activeSizeW or s.frameWidth or 72)
        + ((set and set.extraWidth) or 0)))
    local h = PixelSnap(math.max(10, (ns._activeSizeH or s.frameHeight or 46)
        + ((set and set.extraHeight) or 0)))
    -- Indicator/aura/BM auto-resize: ratio of the custom size to what the
    -- real frames currently render at (clamped like the tier scales). The
    -- extra proxy and ns._xfBmScale pick this up everywhere a duplicate
    -- renders, composing with the raid tier scales.
    local aw = PixelSnap(ns._activeSizeW or s.frameWidth or 72)
    local ah = PixelSnap(ns._activeSizeH or s.frameHeight or 46)
    local ratio = 1
    if aw > 0 and ah > 0 then
        ratio = math.max(math.min(math.min(w / aw, h / ah), 1.3), 0.7)
    end
    ns._xfExtraRatio = ratio
    ns._xfBmScale = (ns._bmScale or 1) * ratio
    local sp = s.cellSpacing or 2
    -- Free Move lays out on its own axes (Grow/Wrap Direction, legacy
    -- Horizontal fallback); attached modes stack group-sized runs of 5 like
    -- additional raid groups (unitGrowth within a run, group growth across).
    local grow, wrap, horizontal = XF.GrowInfo(set, s)
    -- Grid size = the live selection; when the mover is shown outside a raid
    -- there is no selection yet, so estimate from the configuration.
    local count = XF.activeCount or 0
    if count < 1 then
        count = ((set and set.showTanks) and 2 or 0)
            + ((set and set.players) and #set.players or 0)
        if count < 1 then count = 1 end
        if count > XF.CAP then count = XF.CAP end
    end
    -- Frames per run: attached always uses full group-sized runs of 5 (a
    -- partially filled run still spans 5, exactly like a real group); Free
    -- Move wraps at Wrap After (0/unset = one single run).
    local per
    if set and set.position == "free" then
        local wa = tonumber(set.wrapAfter) or 0
        per = (wa > 0) and wa or count
        if per > count then per = count end
    else
        per = 5
    end
    local lines = math.ceil(count / per)

    -- The container spans the occupied grid. Its anchor corner (FB.Anchor's
    -- attached slotting, XF.FreeAnchor's free pin) is the corner the grid
    -- grows away from, so frame 1 holds position as the selection changes.
    local runW, runH = w * per + sp * (per - 1), h * per + sp * (per - 1)
    if horizontal then
        XF.container:SetSize(runW, h * lines + sp * (lines - 1))
    else
        XF.container:SetSize(w * lines + sp * (lines - 1), runH)
    end

    local stepW, stepH = w + sp, h + sp
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local topBarH = (s.topNameBarEnabled and PixelSnap(s.topNameBarHeight or 20)) or 0
    for i, b in ipairs(XF.buttons) do
        b:SetSize(w, h)
        b:ClearAllPoints()
        local off = i - 1
        local line = math.floor(off / per)
        local pos = off - line * per
        -- Map the (run, wrap) grid coordinate onto screen axes: the primary
        -- run carries pos, the wrap axis carries line. The anchor corner is
        -- the one both directions grow away from, so the first frame sits in
        -- that corner of the container exactly like the legacy single run.
        local hUnits, vUnits, hDir, vDir
        if horizontal then
            hUnits, vUnits, hDir, vDir = pos, line, grow, wrap
        else
            hUnits, vUnits, hDir, vDir = line, pos, wrap, grow
        end
        local corner = (vDir == "UP" and "BOTTOM" or "TOP")
            .. (hDir == "LEFT" and "RIGHT" or "LEFT")
        b:SetPoint(corner, XF.container, corner,
            (hDir == "LEFT" and -hUnits or hUnits) * stepW,
            (vDir == "UP" and vUnits or -vUnits) * stepH)
        -- The bulk passes size inner elements for the BASE frame size;
        -- correct the height/width-derived pieces for the offset size.
        local d = GetFFD(b)
        if d.health then
            d.health:SetHeight(((d.power and d.power:IsShown()) and PixelSnap(h - powerH) or h) - topBarH)
        end

        -- Scaled visual pass: re-apply every ratio-affected element through
        -- the extra proxy (mirrors the ReloadFrames per-button styling, so
        -- texts, indicators, auras and BM buffs auto-resize with the custom
        -- size). Bounded to the built slots; runs after the bulk base pass.
        local xs = ns._scaledExtraProxy
        if d.nameText then
            ApplyFont(d.nameText, xs.nameSize or 10)
            if d.AnchorNameText then d.AnchorNameText() end
            -- AnchorNameText derives width from the BASE frame width; the
            -- offset width is authoritative here.
            d.nameText:SetWidth(w * ns.RF_NAME_WIDTH_FRACTION)
        end
        if d.healthText then
            ApplyFont(d.healthText, xs.healthTextSize or 9)
            if d.AnchorHealthText then d.AnchorHealthText() end
        end
        if d.healAbsorbText then
            ApplyFont(d.healAbsorbText, xs.healAbsorbTextSize or 9)
            if d.AnchorHealAbsorbText then d.AnchorHealAbsorbText() end
        end
        if d.statusText then
            ApplyFont(d.statusText, xs.statusTextSize or 14)
            if d.AnchorStatusText then d.AnchorStatusText() end
        end
        if d.roleIcon then
            local riSz = PixelSnap(xs.roleIconSize or 14)
            d.roleIcon:SetSize(riSz, riSz)
            if d.AnchorRoleIcon then d.AnchorRoleIcon() end
        end
        if d.leaderIcon then
            local liSz = PixelSnap(xs.leaderIconSize or 14)
            d.leaderIcon:SetSize(liSz, liSz)
            d.leaderIcon:ClearAllPoints()
            local liPos = (xs.leaderIconPosition or "top"):upper()
            d.leaderIcon:SetPoint(liPos, ns.RF_AnchorHost(d.health, xs), liPos, xs.leaderIconOffsetX or 0, xs.leaderIconOffsetY or 0)
        end
        if d.raidMarker then
            local rmSz = PixelSnap(xs.raidMarkerSize or 16)
            d.raidMarker:SetSize(rmSz, rmSz)
            if d.AnchorRaidMarker then d.AnchorRaidMarker() end
        end
        if d.readyCheck then
            local rcSz = PixelSnap(xs.readyCheckSize or 20)
            d.readyCheck:SetSize(rcSz, rcSz)
            if d.AnchorReadyCheck then d.AnchorReadyCheck() end
        end
        if d.combatIcon then
            local cciSz = PixelSnap(xs.combatIndicatorSize or 16)
            d.combatIcon:SetSize(cciSz, cciSz)
            if d.AnchorCombatIcon then d.AnchorCombatIcon() end
        end
        if d.debuffIcons then
            for _, icon in ipairs(d.debuffIcons) do
                icon:SetSize(xs.debuffSize or 18, xs.debuffSize or 18)
                icon._euiSz = xs.debuffSize or 18
            end
            if d.AnchorDebuffs then d.AnchorDebuffs() end
        end
        if d.defIcons then
            for _, icon in ipairs(d.defIcons) do
                icon:SetSize(xs.defSize or 22, xs.defSize or 22)
            end
            if d.AnchorDefensives then d.AnchorDefensives() end
        end
        if d.AnchorDispelIcon then d.AnchorDispelIcon() end
        if d.privateAuraFrames then
            for _, paFrame in ipairs(d.privateAuraFrames) do
                paFrame:SetSize(xs.debuffSize or 18, xs.debuffSize or 18)
            end
        end
        if d.bmIconPool and d.health and ns.BM_AnchorIndicators then
            ns.BM_AnchorIndicators(d, ns.RF_AnchorHost(d.health, xs), xs)
        end
    end
end

-- Per-unit events mirrored from the central hub for one duplicate's unit.
-- UNIT_* only (safe for RegisterUnitEvent's C-side filter); the two
-- unit-payload broadcast events (READY_CHECK_CONFIRM, PLAYER_FLAGS_CHANGED)
-- are plain registrations filtered in the handler.
XF.EVENTS = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_AURA", "UNIT_POWER_UPDATE",
    "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_PREDICTION", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
    "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
    "UNIT_NAME_UPDATE", "UNIT_CONNECTION", "UNIT_IN_RANGE_UPDATE",
}

-- Grow-on-demand construction: container + buttons through the full
-- real-frame StyleButton pipeline (every visual element, hover, tooltip,
-- click-cast, ping, BM indicators). The base 5 slots build on first
-- activation; Free Move caps above 5 build the extra slots only when the
-- selection actually reaches them (callers are all OOC paths). d._isExtra is
-- set BEFORE StyleButton so the OnAttributeChanged hook it installs never
-- writes the real routing maps. Buttons join allButtons so every bulk
-- restyle/update pass covers them.
XF.EnsureBuilt = function(count)
    if not XF.built then
        XF.built = true
        local container = CreateFrame("Frame", "ERFExtraFramesContainer", UIParent)
        container:Hide()
        XF.container = container
    end
    local want = count or 5
    if want < 5 then want = 5 end

    for i = #XF.buttons + 1, want do
        local b = CreateFrame("Button", "ERFExtraFrame" .. i, XF.container, "SecureUnitButtonTemplate")
        b:Hide()
        GetFFD(b)._isExtra = true
        StyleButton(b)
        allButtons[#allButtons + 1] = b

        -- Per-slot tracker: (re)registered for the assigned unit in XF_Apply,
        -- mirroring the central hub's per-unit reactions for this duplicate.
        -- Bounded to the built slots; zero registrations while a slot is empty.
        local t = CreateFrame("Frame")
        t:SetScript("OnEvent", function(_, event, unit, updateInfo)
            if not b:IsVisible() then return end
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                ns._UpdateButtonHealth(b)
            elseif event == "UNIT_AURA" then
                if EllesmereUI.IS_121 then
                    -- 12.1: aura displays are engine containers; only the
                    -- absorb overlay remains event-driven here.
                    UpdateAbsorb(b, unit)
                else
                    -- Mirror of the hub's UNIT_AURA branch without the budget
                    -- spill: work stays bounded to the duplicated units.
                    UpdateDispelBorder(b, unit, updateInfo)
                    UpdateDebuffs(b, unit, updateInfo)
                    UpdateDefensives(b, unit, updateInfo)
                    UpdateAbsorb(b, unit)
                    if ns.BM_UpdateIndicators then
                        ns.BM_UpdateIndicators(b, unit, db, updateInfo)
                    end
                end
            elseif event == "UNIT_POWER_UPDATE" then
                local d = GetFFD(b)
                if d.power and d.power:IsShown() then
                    local pType = UnitPowerType(unit) or 0
                    d.power:SetMinMaxValues(0, 100)
                    d.power:SetValue(UnitPowerPercent(unit, pType, true, CurveConstants.ScaleTo100))
                    local pr, pg, pb = GetPowerColor(unit)
                    d.power:SetStatusBarColor(pr, pg, pb, 1)
                    -- Power-colored bg: retint only when the power type or BG
                    -- darken changed; the stamps keep the hot path allocation-free.
                    local s = d._isExtra and ns._scaledExtraProxy or ns._scaledProfile
                    if s.powerBgPowerColored and d.powerBg then
                        local f = EllesmereUI.GetPowerBgDarkenFactor()
                        if d._pwBgTintType ~= pType or d._pwBgTintF ~= f then
                            d.powerBg:SetColorTexture(pr * f, pg * f, pb * f, (s.powerBgDarkness or 70) / 100)
                            d._pwBgTintType = pType
                            d._pwBgTintF = f
                        end
                    end
                end
            elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
                or event == "UNIT_HEAL_PREDICTION" or event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
                UpdateAbsorb(b, unit)
                if event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then ns.UpdateHealAbsorbTextFor(b, unit) end
            elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
                local d = GetFFD(b)
                if d.threatFrame then
                    local bs = db.profile.threatBorderSize or 0
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
            elseif event == "UNIT_IN_RANGE_UPDATE" then
                ns._UpdateButtonRange(unit, b)
            elseif event == "UNIT_FLAGS" then
                ns._UpdateCombatIconFor(unit, b)
            elseif event == "READY_CHECK_CONFIRM" then
                -- Plain registration; filter to this slot's unit here
                if unit and unit == b:GetAttribute("unit") then
                    UpdateReadyCheck(b, unit)
                end
            elseif event == "PLAYER_FLAGS_CHANGED" then
                if unit and unit == b:GetAttribute("unit") then
                    UpdateButton(b)
                end
            else -- UNIT_NAME_UPDATE / UNIT_CONNECTION
                UpdateButton(b)
                if event == "UNIT_CONNECTION" then ns._UpdateButtonRange(unit, b) end
            end
        end)
        XF.trackers[i] = t

        XF.buttons[i] = b
    end
end

-- Master apply: resolves the selection and assigns units to the five fixed
-- slots. Out-of-combat only (unit attributes and Show/Hide on protected
-- buttons); combat callers land on the dirty flag and replay on regen.
-- Called from OnEnable, the options widgets, the hotkey toggle, roster/role
-- events, ReloadFrames and profile swaps (_ERF_RefreshAll). The SetAttribute
-- write triggers the StyleButton OnAttributeChanged hook, which repaints the
-- button in full (UpdateButton + auras + dispel + BM), seeds range and
-- re-registers private auras -- the same path a real header assignment takes.
function ns.XF_Apply()
    if not db or not db.profile then return end
    local set = XF.Settings()
    if not set then return end
    if InCombatLockdown() then XF.applyDirty = true; return end

    local units = XF.ShouldBeActive() and XF.ResolveUnits() or {}
    XF.activeCount = #units
    if #units == 0 then
        if XF.built then
            for _, b in ipairs(XF.buttons) do b:Hide() end
            XF.container:Hide()
            for i = 1, #XF.trackers do XF.trackers[i]:UnregisterAllEvents() end
        end
        if XF.mover then XF.mover:Hide() end
        wipe(ns._xfUnitToButton)
        -- The boss group may have been chained behind this container;
        -- re-anchor it back onto the raid (no-op when FB is not built).
        FB.Anchor()
        return
    end

    XF.EnsureBuilt(#units)
    XF.Layout()
    FB.Anchor(XF)
    XF.container:Show()
    wipe(ns._xfUnitToButton)
    for i = 1, #XF.buttons do
        local b = XF.buttons[i]
        local unit = units[i]
        local t = XF.trackers[i]
        t:UnregisterAllEvents()
        if unit then
            -- Class token cache for the power border (mirrors RebuildUnitMap)
            local d = GetFFD(b)
            local _, classToken = UnitClass(unit)
            d.classToken = classToken
            b:SetAttribute("unit", unit)
            ns._xfUnitToButton[unit] = b
            for _, ev in ipairs(XF.EVENTS) do
                t:RegisterUnitEvent(ev, unit)
            end
            -- UNIT_FLAGS is opt-in: extra frames mirror the raid combat-icon toggle.
            if db.profile.showCombatIndicator then
                t:RegisterUnitEvent("UNIT_FLAGS", unit)
            end
            t:RegisterEvent("READY_CHECK_CONFIRM")
            t:RegisterEvent("PLAYER_FLAGS_CHANGED")
            b:Show()
        else
            b:Hide()
        end
    end
    -- Re-evaluate the boss group's chain now that this container is shown
    -- and (re)positioned: same-side boss frames hop behind it.
    FB.Anchor()
end

function ns.XF_IsMoverShown()
    return XF.mover and XF.mover:IsShown() or false
end

function ns.XF_SetMoverShown(show)
    FB.SetMoverShown(XF, show, "ERFExtraFramesMover", "Extra Frames")
end

-- Hidden bind target (pure Lua keybinding, no Bindings.xml -- same pattern
-- as the Party Mode toggle key). The options panel binds the saved key to
-- click this button; the click toggles the raid member under the mouse in
-- or out of the extra group.
local bindBtn = CreateFrame("Button", "ERFExtraFramesBindBtn", UIParent)
bindBtn:Hide()

XF.ToggleHovered = function()
    if not db or not db.profile then return end
    if not IsInRaid() then return end
    local set = XF.Settings()
    if not set then return end
    -- The real raid frame under the mouse, or one of our own duplicates
    -- (pressing the hotkey on a duplicate removes that player too).
    local unit
    for u, btn in pairs(unitToButton) do
        if btn:IsShown() and btn:IsMouseOver() then unit = u; break end
    end
    if not unit then
        for _, b in ipairs(XF.buttons) do
            if b:IsShown() and b:IsMouseOver() then unit = b:GetAttribute("unit"); break end
        end
    end
    if not unit then return end
    local idx = tonumber(unit:match("^raid(%d+)$"))
    local name = idx and GetRaidRosterInfo(idx)
    if not name then return end

    local players = set.players or {}
    set.players = players
    for k, v in ipairs(players) do
        if v == name then
            table.remove(players, k)
            ns.XF_Apply()
            return
        end
    end
    -- Already covered by Show Tanks: adding would be an invisible duplicate
    if set.showTanks and UnitGroupRolesAssigned(unit) == "TANK" then
        return
    end
    if #XF.ResolveUnits() >= XF.CAP then
        return
    end
    players[#players + 1] = name
    ns.XF_Apply()
end

bindBtn:SetScript("OnClick", function() XF.ToggleHovered() end)

-- Standing event frame: exists even while inactive so the tanks toggle or a
-- first hotkey add can activate the feature without a /reload, and so the
-- saved hotkey is re-bound every login.
do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- No PLAYER_TARGET_CHANGED / RAID_TARGET_UPDATE here: the duplicates ride
    -- the central broadcast closures via ns._xfUnitToButton.
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then
            local key = EllesmereUIDB and EllesmereUIDB.extraFramesKey
            if key then
                ClearOverrideBindings(bindBtn)
                SetOverrideBindingClick(bindBtn, true, key, "ERFExtraFramesBindBtn")
            end
            return
        end
        if not db then return end
        if event == "PLAYER_REGEN_ENABLED" then
            if XF.applyDirty then XF.applyDirty = nil; ns.XF_Apply() end
            if XF.anchorDirty then XF.anchorDirty = nil; FB.Anchor(XF) end
        else -- GROUP_ROSTER_UPDATE / PLAYER_ROLES_ASSIGNED
            -- Raid indices and the tank set both shift with the roster
            if XF.ShouldBeActive() or XF.built then ns.XF_Apply() end
        end
    end)
    XF.eventFrame = ev
end
end -- XF scope block

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
        -- A nil/placeholder name means the roster has not fully populated
        -- (zoning, mid-loadscreen join) -- and with a nil name the subgroup
        -- is not trustworthy either, so the whole list could silently omit
        -- a member and the header would hide their frame. Bail to nil
        -- (index-order fallback, everyone visible) until names resolve.
        if not name or name == UNKNOWNOBJECT then return nil end
        if subgroup == playerGroup then
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

-- Default class sort order: the real player classes only, alphabetical by
-- localized name. Enumerated via GetNumClasses + C_CreatureInfo.GetClassInfo so
-- non-class entries (e.g. Adventurer/Traveler in LOCALIZED_CLASS_NAMES_MALE) are
-- excluded. Also populates ns._classNameByToken (token -> localized name) for the
-- options list. Cached on the namespace (NOT a file-scope local -- this chunk is
-- at the Lua 5.1 200-local cap).
function ns._GetDefaultClassOrder()
    if ns._defaultClassOrderCache then return ns._defaultClassOrderCache end
    local list, names = {}, {}
    local n = (GetNumClasses and GetNumClasses()) or 0
    for i = 1, n do
        local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(i)
        if info and info.classFile then
            list[#list + 1] = info.classFile
            names[info.classFile] = info.className or info.classFile
        end
    end
    table.sort(list, function(a, b) return (names[a] or a) < (names[b] or b) end)
    ns._classNameByToken = names
    if #list > 0 then ns._defaultClassOrderCache = list end
    return list
end

-- Build a class-priority nameList for the party header. Lists the party members
-- the header shows (player only when includePlayer), ordered by role (optional
-- primary) -> class -> name. Names use the same UnitName + "-realm" format
-- Blizzard's GetGroupRosterInfo produces for party units, so the secure header
-- matches them. nameList is only honored when groupFilter is cleared.
function ns._BuildPartyClassNameList(includePlayer, sortByRole, roleOrder, classOrder)
    if not IsInGroup() then return nil end
    classOrder = classOrder or ns._GetDefaultClassOrder()
    local classPri = {}
    for i, c in ipairs(classOrder) do classPri[c] = i end
    local rolePri
    if sortByRole then
        rolePri = {}
        for i, r in ipairs(roleOrder) do rolePri[r] = i end
    end
    local members = {}
    local units = {}
    if includePlayer then units[#units + 1] = "player" end
    for i = 1, 4 do units[#units + 1] = "party" .. i end
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local name, server = UnitName(unit)
            -- A member that exists but whose name has not populated yet
            -- (zoning, mid-loadscreen join) cannot be listed: a nameList
            -- missing a member makes the secure header hide that frame
            -- entirely. Bail to nil so the caller falls back to the
            -- groupFilter path (everyone visible, index order) until
            -- UNIT_NAME_UPDATE rebuilds the list with real names.
            if not name or name == UNKNOWNOBJECT then return nil end
            if server and server ~= "" then name = name .. "-" .. server end
            local _, classToken = UnitClass(unit)
            members[#members + 1] = {
                name = name,
                rolePri = (rolePri and rolePri[UnitGroupRolesAssigned(unit)]) or 99,
                classPri = classPri[classToken] or 99,
            }
        end
    end
    if #members == 0 then return nil end
    table.sort(members, function(a, b)
        if sortByRole and a.rolePri ~= b.rolePri then return a.rolePri < b.rolePri end
        if a.classPri ~= b.classPri then return a.classPri < b.classPri end
        return a.name < b.name
    end)
    local names = {}
    for _, m in ipairs(members) do names[#names + 1] = m.name end
    return table.concat(names, ",")
end

-- Build the party header's nameList for ARENA, where the header is bound to
-- raid1-5. showPlayer cannot exclude the player in a raid group and the static
-- self button cannot reorder them, but a NAMELIST can do both: omit the player
-- (Hide Self) and order them first or last (Show Self First / Self Last). The
-- rest follow role order (ROLE mode) else raid index. Names come from
-- GetRaidRosterInfo, the same source the secure header matches against. Bails to
-- nil -- the index-order fallback with everyone visible -- while any name is
-- still unresolved, so a half-built roster never hides a teammate.
function ns._BuildArenaNameList(hideSelf, selfFirst, selfLast, sortByRole, roleOrder)
    if not IsInRaid() then return nil end
    local pri
    if sortByRole then
        pri = {}
        for p, r in ipairs(roleOrder) do pri[r] = p end
    end
    local members = {}
    local n = GetNumGroupMembers()
    for i = 1, n do
        local name = GetRaidRosterInfo(i)
        if not name or name == UNKNOWNOBJECT then return nil end
        local unit = "raid" .. i
        local isPlayer = UnitIsUnit(unit, "player")
        if not (hideSelf and isPlayer) then
            local rp = 99
            if pri then rp = pri[UnitGroupRolesAssigned(unit)] or 99 end
            members[#members + 1] = {
                name = name,
                isPlayer = isPlayer,
                rolePri = rp,
                index = i,
            }
        end
    end
    if #members == 0 then return nil end
    table.sort(members, function(a, b)
        -- Player to the top (self-first) or bottom (self-last) when either is
        -- set. Exactly one of a/b is the player in that branch, so XOR-ing with
        -- selfLast flips top vs bottom.
        if (selfFirst or selfLast) and a.isPlayer ~= b.isPlayer then
            return a.isPlayer ~= selfLast
        end
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
        -- 12.1: the header births an AuraContainer per child SECURE-SIDE --
        -- the only combat-legal container source (covers in-combat /reload
        -- and mid-combat roster growth). The containers file adopts it as
        -- the debuff shell.
        if EllesmereUI.IS_121 then
            hdr:SetAttribute("auraContainerTemplate", "CustomAuraContainerTemplate")
        end
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
        -- Overlay host kept at a high frame level so the labels draw ABOVE the
        -- raid buttons. The buttons are descendants of containerFrame, so labels
        -- parented straight to the container render BENEATH the bars; a high
        -- frame level within the same (LOW) strata lifts them on top.
        ns._groupNumberOverlay = CreateFrame("Frame", nil, containerFrame)
        ns._groupNumberOverlay:SetAllPoints(containerFrame)
        ns._groupNumberOverlay:SetFrameLevel(9000)
        ns._groupNumberLabels = {}
        for gi = 1, 8 do
            local lbl = ns._groupNumberOverlay:CreateFontString(nil, "OVERLAY")
            lbl:Hide()
            ns._groupNumberLabels[gi] = lbl
        end
    end

    -----------------------------------------------------------
    --  Flat header for merge-groups mode (all members in one grid)
    -----------------------------------------------------------
    ns._flatHeader = CreateFrame("Frame", "ERFFlatHeader", containerFrame, "SecureGroupHeaderTemplate")
    if EllesmereUI.IS_121 then
        ns._flatHeader:SetAttribute("auraContainerTemplate", "CustomAuraContainerTemplate")
    end
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

-- Real layout work. Call only through LayoutGroups() below, which wraps this in a
-- coalescing re-entrancy guard. Mutating secure group headers here (Hide/Show/
-- SetAttribute) and resizing the container makes Blizzard re-anchor their children
-- synchronously, which can re-enter layout through our own hooks. Stored on ns
-- (not a new file-scope local) because this chunk is at the 200-local cap.
ns._LayoutGroupsImpl = function()
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

        -- For UP/LEFT unit growth, pin each header by the corner its units
        -- grow away from: the offset moves (x, y) to that cell edge and the
        -- matching header corner anchors there, so the group fills its cell
        -- (the header rect grows away from the pinned corner as members join).
        -- Anchoring TOPLEFT for these directions displaced the real frames a
        -- full group height/width outside the container, mismatching the
        -- preview and unlock mover.
        local hdrAnchor = "TOPLEFT"
        local hdrOffX, hdrOffY = 0, 0
        if unitGrowth == "UP"   then hdrAnchor = "BOTTOMLEFT"; hdrOffY = -groupH end
        if unitGrowth == "LEFT" then hdrAnchor = "TOPRIGHT";   hdrOffX = groupW  end

        -- "Hide Empty Groups": collapse subgroups that currently have no
        -- members so the remaining groups close ranks (e.g. show 1/2/3/6
        -- instead of 1/2/3 then a gap where 4/5 would be then 6). Real frames
        -- only; needs live raid roster data, so it is skipped outside a raid
        -- (GetRaidRosterInfo returns nil there) to avoid hiding every group
        -- when solo or in a party.
        local occupied
        if s.hideEmptyGroups ~= false and IsInRaid() then
            occupied = {}
            for ri = 1, GetNumGroupMembers() or 0 do
                local _, _, sub = GetRaidRosterInfo(ri)
                if sub then occupied[sub] = true end
            end
        end

        local visSlot = 0  -- running counter for visible groups (collapses gaps)
        for group = 1, 8 do
            local hdr = separatedHdrs[group]
            if hdr then
                if vg[group] == false or (occupied and not occupied[group]) then
                    if hdr:IsShown() then hdr:Hide() end
                else
                    local x = PixelSnap(visSlot * stepX - minX + hdrOffX)
                    local y = PixelSnap(visSlot * stepY - maxY + hdrOffY)
                    visSlot = visSlot + 1

                    hdr:ClearAllPoints()
                    hdr:SetPoint(hdrAnchor, containerFrame, "TOPLEFT", x, y)
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

    -- Snap the container's screen position to the pixel grid. Skip when
    -- element-anchored: ApplyAnchorPosition already pixel-snaps, and a
    -- TOPLEFT re-anchor here would fight the anchor cascade.
    if not InCombatLockdown()
       and not (EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("RF_RaidFrames")) then
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

-- Coalescing re-entrancy guard around the secure-header relayout. A LayoutGroups()
-- call that arrives while a layout is already running is NOT dropped -- dropping it
-- would leave frames stale (a roster change or size flip mid-layout would be lost).
-- Instead the re-entrant call marks the pass dirty and the in-flight call re-runs
-- once it returns. Bounded to 3 passes so a non-converging header feedback loop
-- (our SetAttribute/SetSize -> Blizzard re-anchors children -> our hook -> here)
-- can never spin the CPU into a "script ran too long" watchdog kill. pcall keeps the
-- busy flag honest: if the body errors we clear the flag and rethrow, so a single
-- error can never freeze every future layout until /reload. State lives on ns to
-- avoid adding file-scope locals (this chunk is at the 200-local cap); the wrapper
-- reuses the slot the impl used to hold, so this adds no new main-chunk local.
local function LayoutGroups()
    if ns._inLayoutGroups then
        ns._layoutGroupsDirty = true
        return
    end
    ns._inLayoutGroups = true
    local passes = 0
    repeat
        ns._layoutGroupsDirty = false
        passes = passes + 1
        local ok, err = pcall(ns._LayoutGroupsImpl)
        if not ok then
            ns._inLayoutGroups = false
            return geterrorhandler()(err)
        end
    until (not ns._layoutGroupsDirty) or passes >= 3
    ns._inLayoutGroups = false
    -- Cap reached with work still pending: a genuine non-converging relayout loop.
    -- The guard kept it from freezing the client; surface it once (out of combat)
    -- so it stays diagnosable instead of silently masking a real bug.
    if ns._layoutGroupsDirty and not ns._layoutLoopWarned and not InCombatLockdown() then
        ns._layoutLoopWarned = true
        print("|cffff5555EllesmereUI Raid Frames:|r layout did not settle after 3 passes; " ..
            "a re-entrant loop was bounded. Please report this if frames look wrong.")
    end
end

local RangeUpdate  -- forward declaration (defined in Range fading section below)

-------------------------------------------------------------------------------
--  Reload: re-apply all settings to existing buttons
-------------------------------------------------------------------------------
local function ReloadFrames()
    local s = ns._scaledProfile
    -- Keep UNIT_FLAGS registration in lockstep with the combat-icon toggle so a
    -- disabled option listens for nothing (runs no event code).
    if ns.UpdateCombatEventRegistration then ns.UpdateCombatEventRegistration() end
    -- Rebuild dispel-color curves so custom-color edits take effect immediately.
    if ns._RebuildDispelCurves then ns._RebuildDispelCurves() end
    -- Recalculate active tier from current group size + overrides
    local numMembers = ns._GetEffectiveRaidSize()
    local prevW, prevH = ns._activeSizeW, ns._activeSizeH
    if numMembers > 0 then
        ns._activeSizeW, ns._activeSizeH = ns._GetRaidSizeFrameDimensions(numMembers)
        -- Resolve active tier override table (for per-tier growth directions)
        -- via the single cascade authority.
        local _, activeTierOv = ns._RFResolveTierOverride(numMembers)
        ns._activeTierOverride = activeTierOv
    else
        ns._activeSizeW, ns._activeSizeH = nil, nil
        ns._activeTierOverride = nil
    end
    local bw = PixelSnap(ns._activeSizeW or s.frameWidth or 72)
    local bh = PixelSnap(ns._activeSizeH or s.frameHeight or 46)

    -- Auto-resize indicators: scale factor based on active tier vs base 20-man
    -- Read base dimensions from raw db.profile (not proxy, which returns active tier)
    local sizeScale = 1
    if ns._activeSizeW and ns._activeSizeH then
        local baseW = db.profile.frameWidth or 72
        local baseH = db.profile.frameHeight or 46
        local scale = math.min(ns._activeSizeW / baseW, ns._activeSizeH / baseH)
        sizeScale = math.max(math.min(scale, 1.5), 0.7)
    end
    -- Auto Resize Icons (two independent checkboxes): Tracked Buffs gates the
    -- Buff Manager scale; Indicators & Auras gates indicator/aura/text sizes.
    -- Tracked Buffs defaults on (nil treated as on) to preserve the prior
    -- hardcoded always-on behavior.
    ns._bmScale = (db.profile.autoResizeTrackedBuffs ~= false) and sizeScale or 1
    ns._indicatorScale = db.profile.autoResizeIndicators and sizeScale or 1

    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - powerH)
    local texPath = ResolveHealthTexture()

    for _, btn in ipairs(allButtons) do
        local d = GetFFD(btn)
        if not d.styled then StyleButton(btn) end

        btn:SetSize(bw, bh)

        -- Background
        if d.bg then
            d.bg:SetColorTexture(ns.GetBgColor(btn:GetAttribute("unit"), s))
        end

        -- Health bar height/anchor + Top Name Bar. The helper reserves the top
        -- bar's height from the top of the health area and styles the bar.
        LayoutTopNameBar(s, bh, powerH, d.health, d.topNameBar, d.topNameBarBg, d.topNameBarText)
        if d.health then
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
            d._pwBgTintType = nil
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

        -- Heal absorb text
        if d.healAbsorbText then
            ApplyFont(d.healAbsorbText, s.healAbsorbTextSize or 9)
            if d.AnchorHealAbsorbText then d.AnchorHealAbsorbText() end
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
            d.leaderIcon:SetPoint(liPos, ns.RF_AnchorHost(d.health, s), liPos, s.leaderIconOffsetX or 0, s.leaderIconOffsetY or 0)
            -- Re-assert the host's strata/level above the border
            if d.leaderHost then ns.ApplyLeaderStrata(d.leaderHost) end
        end

        -- Raid marker size + position
        if d.raidMarker then
            local rmSz = PixelSnap(s.raidMarkerSize or 16)
            d.raidMarker:SetSize(rmSz, rmSz)
            if d.AnchorRaidMarker then d.AnchorRaidMarker() end
        end

        -- Ready check / summon size + position
        if d.readyCheck then
            local rcSz = PixelSnap(s.readyCheckSize or 20)
            d.readyCheck:SetSize(rcSz, rcSz)
            if d.AnchorReadyCheck then d.AnchorReadyCheck() end
        end

        -- Combat icon size + position
        if d.combatIcon then
            local cciSz = PixelSnap(s.combatIndicatorSize or 16)
            d.combatIcon:SetSize(cciSz, cciSz)
            if d.AnchorCombatIcon then d.AnchorCombatIcon() end
        end

        -- Border
        if d.UpdateBorder then d.UpdateBorder() end

        -- Debuff size + position
        if d.debuffIcons then
            for _, icon in ipairs(d.debuffIcons) do
                icon:SetSize(s.debuffSize or 18, s.debuffSize or 18)
                icon._euiSz = s.debuffSize or 18
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

        -- Dispel icon position
        if d.AnchorDispelIcon then d.AnchorDispelIcon() end

        -- Private aura per-slot frames (re-anchor for changed debuff settings)
        if d.privateAuraFrames then
            for _, paFrame in ipairs(d.privateAuraFrames) do
                paFrame:SetSize(s.debuffSize or 18, s.debuffSize or 18)
            end
        end

        -- Buff manager indicators
        if d.bmIconPool and d.health and ns.BM_AnchorIndicators then
            ns.BM_AnchorIndicators(d, ns.RF_AnchorHost(d.health, s), s)
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

    -- Friendly Boss Frames and Extra Frames inherit size/growth/spacing/
    -- border/text settings; restyle + re-anchor them with everything else
    -- (growth changes move the anchor points, not just the anchored-to header).
    if ns.FB_Apply then ns.FB_Apply() end
    if ns.XF_Apply then ns.XF_Apply() end

    -- 12.1 aura containers reload with every real pass (direct call inside
    -- the body -- immune to the Options file's setup-time capture of
    -- ns.ReloadFrames).
    if ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
end

ns.ReloadFrames = ReloadFrames
ns.PixelSnap = PixelSnap
ns._allButtons = allButtons

-- Global Dark Mode master: Raid Frames store Dark Mode as a fill-colour MODE
-- (healthColorMode == "dark"), not a boolean, so enabling remembers the prior
-- mode and disabling restores it -- the master must not silently clobber a
-- user's Classic/Custom fill choice. A party colour override (party_healthColorMode,
-- only present when the party colour section is decoupled) is flipped the same
-- way when it exists. db is set at PLAYER_LOGIN; the closures read it lazily.
if EllesmereUI.RegisterDarkModeToggle then
    EllesmereUI.RegisterDarkModeToggle({
        id = "raidFrames",
        isOn = function()
            return (db and db.profile and db.profile.healthColorMode == "dark") or false
        end,
        setOn = function(on)
            if not (db and db.profile) then return end
            local p = db.profile
            if on then
                if p.healthColorMode ~= "dark" then
                    p._darkPrevHealthColorMode = p.healthColorMode or "class"
                    p.healthColorMode = "dark"
                end
                if rawget(p, "party_healthColorMode") ~= nil and p.party_healthColorMode ~= "dark" then
                    p._darkPrevPartyHealthColorMode = p.party_healthColorMode
                    p.party_healthColorMode = "dark"
                end
            else
                if p.healthColorMode == "dark" then
                    p.healthColorMode = p._darkPrevHealthColorMode or "class"
                end
                p._darkPrevHealthColorMode = nil
                if rawget(p, "party_healthColorMode") == "dark" then
                    p.party_healthColorMode = p._darkPrevPartyHealthColorMode or "class"
                end
                p._darkPrevPartyHealthColorMode = nil
            end
            if ns.ReloadFrames then ns.ReloadFrames() end
            if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
        end,
    })
end

-- Lightweight resize: only changes button/health/power dimensions + layout.
-- No texture, border, font, or anchor changes. Safe for slider hot path.
ns._ResizeButtons = function(w, h)
    if InCombatLockdown() then return end
    local bw = PixelSnap(w)
    local bh = PixelSnap(h)
    local s = db.profile
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - powerH)
    local topBarH = (s.topNameBarEnabled and PixelSnap(s.topNameBarHeight or 20)) or 0
    local xfset = s.extraFrames
    for _, btn in ipairs(allButtons) do
        local d = GetFFD(btn)
        if d.styled then
            local xbw, xbh, xhealthH = bw, bh, healthH
            -- Extra Frames duplicates carry their size offset through the
            -- live slider path too (XF.Layout re-applies it on full reloads).
            if d._isExtra and xfset then
                xbw = PixelSnap(math.max(10, w + (xfset.extraWidth or 0)))
                xbh = PixelSnap(math.max(10, h + (xfset.extraHeight or 0)))
                xhealthH = PixelSnap(xbh - powerH)
            end
            btn:SetSize(xbw, xbh)
            -- Full height when the power bar is hidden for this button's role
            -- (mirrors _ResizePartyButtons); avoids a dark strip on OFF-role units
            -- now that d.power always exists. Top Name Bar always reserves its
            -- height from the top (the health top anchor is kept at -topBarH by the
            -- full refresh, so here we only correct the height).
            if d.health then
                d.health:SetHeight(((d.power and d.power:IsShown()) and xhealthH or xbh) - topBarH)
            end
            if d.nameText then d.nameText:SetWidth(xbw * ns.RF_NAME_WIDTH_FRACTION) end
        end
    end
    ns._activeSizeW = w
    ns._activeSizeH = h
    LayoutGroups()
    -- The container footprint may have just changed: re-derive the
    -- growth-corner anchor so the pinned corner holds during live slider
    -- drags, and so the unlock framework's OnSizeChanged notification can
    -- never leave a stale centered position as the final state.
    if ns._ApplyTierOffset then ns._ApplyTierOffset() end
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
    local topBarH = (s.topNameBarEnabled and PixelSnap(s.topNameBarHeight or 20)) or 0
    -- Auto Resize scale depends on frame size; recompute on this lightweight
    -- width/height slider path (which skips the full reload).
    if ns._UpdatePartyIndicatorScale then ns._UpdatePartyIndicatorScale() end
    local autoResize = s.partyAutoResizeIndicators
    for _, btn in ipairs(ns._partyAllButtons) do
        local d = GetFFD(btn)
        if d.styled then
            btn:SetSize(bw, bh)
            -- Use full height if power bar is hidden for this button's role; the
            -- Top Name Bar always reserves topBarH from the top.
            if d.health then
                local hh = ((d.power and d.power:IsShown()) and healthH or bh) - topBarH
                d.health:SetHeight(hh)
            end
            if d.nameText then d.nameText:SetWidth(bw * ns.RF_NAME_WIDTH_FRACTION) end
            -- Live-rescale indicators/auras. No-op for hidden buttons / no unit
            -- (e.g. options menu while not grouped), so cheap there.
            if autoResize then
                -- The scale derives from frame size (recomputed above), so the
                -- scaled sizes must re-apply during the drag -- same set the
                -- full reload scales through the party proxy.
                local pp = ns._scaledPartyProxy
                if d.roleIcon then
                    local riSz = PixelSnap(pp.roleIconSize or 14)
                    d.roleIcon:SetSize(riSz, riSz)
                    if d.AnchorRoleIcon then d.AnchorRoleIcon() end
                end
                if d.leaderIcon then
                    local liSz = PixelSnap(pp.leaderIconSize or 14)
                    d.leaderIcon:SetSize(liSz, liSz)
                end
                if d.raidMarker then
                    local rmSz = PixelSnap(pp.raidMarkerSize or 16)
                    d.raidMarker:SetSize(rmSz, rmSz)
                end
                if d.combatIcon then
                    local cciSz = PixelSnap(pp.combatIndicatorSize or 16)
                    d.combatIcon:SetSize(cciSz, cciSz)
                    if d.AnchorCombatIcon then d.AnchorCombatIcon() end
                end
                if d.debuffIcons then
                    for _, icon in ipairs(d.debuffIcons) do
                        icon:SetSize(pp.debuffSize or 18, pp.debuffSize or 18)
                        icon._euiSz = pp.debuffSize or 18
                    end
                end
                if d.defIcons then
                    for _, icon in ipairs(d.defIcons) do
                        icon:SetSize(pp.defSize or 22, pp.defSize or 22)
                    end
                end
                if d.nameText then ApplyFont(d.nameText, pp.nameSize or 10) end
                if d.healthText then ApplyFont(d.healthText, pp.healthTextSize or 9) end
                if d.healAbsorbText then ApplyFont(d.healAbsorbText, pp.healAbsorbTextSize or 9) end
                if d.statusText then ApplyFont(d.statusText, pp.statusTextSize or 14) end
            end
            -- BM buffs ALWAYS follow the size-derived scale (independent of
            -- the Auto Resize toggle), so re-render them on every size tick.
            if ns.BM_UpdateIndicators and btn:IsVisible() then
                local u = btn:GetAttribute("unit")
                if u then ns.BM_UpdateIndicators(btn, u, db) end
            end
        end
    end
    -- Targeted Spells icons read the same Auto Resize scale; one call
    -- restyles and relayouts every button's icons (and the preview).
    if autoResize and ns.TS_ApplySettings then ns.TS_ApplySettings() end
    -- Container resize deferred to drag end (SetSize on the container
    -- triggers SecureGroupHeaderTemplate to re-process children, causing blink).
    -- Slot offsets + the header's own size DO follow the live size: this keeps
    -- the self button aligned with the header stack (height) and the header's
    -- centered child anchors growing from the correct origin (width). Pure
    -- anchor tracking -- no secure re-process, no blink.
    if ns._PositionPartySlots then
        local cs2 = PixelSnap(s.partyCellSpacing or s.cellSpacing or 2)
        local growth2 = s.partyHorizontal and (s.partyFlipGrowth and "LEFT" or "RIGHT")
            or (s.partyFlipGrowth and "UP" or "DOWN")
        ns._PositionPartySlots(bw, bh, cs2, growth2)
    end
end

-- Convert a saved (point, relPoint, x, y) UIParent anchor to the TOPLEFT
-- screen coords (UIParent bottom-left space, same space GetLeft/GetTop use)
-- the frame would occupy at the given size.
ns._RFPosTopLeft = function(pos, w, h)
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local function frac(p)
        p = p or "CENTER"
        local fx = (p:find("LEFT") and 0) or (p:find("RIGHT") and 1) or 0.5
        local fy = (p:find("BOTTOM") and 0) or (p:find("TOP") and 1) or 0.5
        return fx, fy
    end
    local rfx, rfy = frac(pos.relPoint)
    local pfx, pfy = frac(pos.point)
    local ax = uw * rfx + (pos.x or 0)
    local ay = uh * rfy + (pos.y or 0)
    return ax - pfx * w, ay + (1 - pfy) * h
end

-- Footprint of the 4-group mover box for a frame size and growth pair.
ns._RFFootprint = function(bw, bh, unitGrowth, groupGrowth, cs, gs)
    bw, bh = PixelSnap(bw), PixelSnap(bh)
    local groupW, groupH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        groupW = 5 * bw + 4 * cs
        groupH = bh
    else
        groupW = bw
        groupH = 5 * bh + 4 * cs
    end
    if groupGrowth == "DOWN" or groupGrowth == "UP" then
        return PixelSnap(groupW), PixelSnap(MOVER_GROUPS * groupH + (MOVER_GROUPS - 1) * gs)
    end
    return PixelSnap(MOVER_GROUPS * groupW + (MOVER_GROUPS - 1) * gs), PixelSnap(groupH)
end

-- TOPLEFT of the BASE (20-man) footprint at the saved unlock position: the
-- shared growth origin for every size tier and the previews. Also returns
-- the base footprint's width/height so corner math never recomputes it
-- (extra return values -- existing two-value callers are unaffected).
-- Returns nil when no position has been saved yet.
ns._RFBaseTopLeft = function()
    local s = db.profile
    local pos = s.unlockPos
    if not pos then return nil end
    local cs = PixelSnap(s.cellSpacing or 2)
    local gs = PixelSnap(s.groupSpacing or 8)
    local w, h = ns._RFFootprint(s.frameWidth or 72, s.frameHeight or 46,
        s.unitGrowth or "DOWN", s.groupGrowth or "RIGHT", cs, gs)
    local l, t = ns._RFPosTopLeft(pos, w, h)
    return l, t, w, h
end

-- Pinned screen corner implied by a growth pair. Frames grow AWAY from this
-- corner, so it is the corner that stays fixed when a tier's footprint
-- differs from the base: the horizontal side comes from whichever growth is
-- horizontal (RIGHT grows rightward, so the LEFT edge pins; LEFT pins the
-- RIGHT edge) and the vertical side from whichever is vertical (DOWN pins
-- TOP; UP pins BOTTOM). Growths are perpendicular (the options UI enforces
-- it); degenerate imported data still resolves deterministically (any UP
-- wins BOTTOM, any LEFT wins RIGHT, defaults TOP + LEFT). Merged-groups
-- mode fills from the same corner (same two growth keys), no special case.
ns._RFGrowthCorner = function(unitGrowth, groupGrowth)
    local h = (unitGrowth == "LEFT" or groupGrowth == "LEFT") and "RIGHT" or "LEFT"
    local v = (unitGrowth == "UP" or groupGrowth == "UP") and "BOTTOM" or "TOP"
    return v .. h
end

-- Signed corner terms: how far a tier footprint's TOPLEFT shifts from the
-- base footprint's TOPLEFT so the growth-derived corner stays pinned. THE
-- single copy of the corner arithmetic -- the forward origin
-- (_RFTierTopLeft), the one-time offset rebase (conversion #2 in
-- _NormalizeTierOffsetAnchors) and the mover save-path inverse
-- (_RFRebaseSavedCenter) all read these two values. Both terms are zero
-- when the footprints match, so the base tier is exact by arithmetic.
ns._RFCornerTerms = function(tw, th, bw, bh, unitGrowth, groupGrowth)
    local corner = ns._RFGrowthCorner(unitGrowth, groupGrowth)
    local kx = (corner:find("RIGHT") and (bw - tw)) or 0
    local ky = (corner:find("BOTTOM") and -(bh - th)) or 0
    return kx, ky
end

-- THE centralized growth-corner origin. Returns the TOPLEFT (UIParent
-- bottom-left space) for a tier footprint of size (tw, th) whose
-- growth-derived corner is pinned at the BASE footprint's same corner,
-- plus the tier's saved offsets. Every consumer (live _ApplyTierOffset and
-- the size previews) anchors through this one function, so the previews
-- land exactly where the live frames land. For the base footprint with
-- zero offsets every corner term cancels and this returns the plain base
-- top-left -- profiles without raidSizeOverrides behave identically.
-- Returns nil when no unlock position has been saved yet.
ns._RFTierTopLeft = function(tw, th, unitGrowth, groupGrowth, ox, oy)
    local bl, bt, bw, bh = ns._RFBaseTopLeft()
    if not bl then return nil end
    local kx, ky = ns._RFCornerTerms(tw, th, bw, bh, unitGrowth, groupGrowth)
    return bl + (ox or 0) + kx, bt + (oy or 0) + ky
end

-- Resolve the active size tier bucket and its override table, cascading
-- toward 20 (10 falls back to 15, 30 falls back to 25). The single copy of
-- the cascade -- _GetRaidSizeFrameDimensions, ReloadFrames and
-- _ApplyTierOffset all route through here. Returns tier, override; the
-- override is nil for the base 20 tier or when none is defined.
ns._RFResolveTierOverride = function(numMembers)
    local overrides = db.profile.raidSizeOverrides
    if not overrides or not numMembers or numMembers <= 0 then return 20, nil end
    local tier
    if numMembers <= 10 then     tier = 10
    elseif numMembers <= 15 then tier = 15
    elseif numMembers <= 20 then tier = 20
    elseif numMembers <= 25 then tier = 25
    else                         tier = 30
    end
    if tier == 20 then return 20, nil end
    local ov
    if tier < 20 then
        ov = overrides[tier] or (tier == 10 and overrides[15]) or nil
    else
        ov = overrides[tier] or (tier == 30 and overrides[25]) or nil
    end
    return tier, ov or nil
end

-- Inverse of the corner scheme, for the unlock mover SAVE path only. The
-- framework measures a dragged container's CENTER from its LIVE bounds --
-- i.e. on the ACTIVE tier's footprint -- but every apply interprets
-- unlockPos as the BASE footprint's center. Convert a live-measured center
-- to its base-footprint equivalent so the next _ApplyTierOffset reproduces
-- the drop position (within one physical pixel of snapping). With the base
-- tier active, or no overrides defined, every term cancels and the center
-- passes through unchanged -- zero behavior change for base saves.
ns._RFRebaseSavedCenter = function(cx, cy)
    local s = db.profile
    local _, ov = ns._RFResolveTierOverride(ns._GetEffectiveRaidSize())
    if not ov then return cx, cy end
    local cs = PixelSnap(s.cellSpacing or 2)
    local gs = PixelSnap(s.groupSpacing or 8)
    local bw, bh = ns._RFFootprint(s.frameWidth or 72, s.frameHeight or 46,
        s.unitGrowth or "DOWN", s.groupGrowth or "RIGHT", cs, gs)
    local ug = ov.unitGrowth or s.unitGrowth or "DOWN"
    local gg = ov.groupGrowth or s.groupGrowth or "RIGHT"
    local tw, th = ns._RFFootprint(ov.width or s.frameWidth or 72,
        ov.height or s.frameHeight or 46, ug, gg, cs, gs)
    local kx, ky = ns._RFCornerTerms(tw, th, bw, bh, ug, gg)
    return cx - (ov.offsetX or 0) - kx - (tw - bw) / 2,
        cy - (ov.offsetY or 0) - ky - (bh - th) / 2
end

-- Owned creation point for raidSizeOverrides: fresh tables are ALREADY in
-- the current offset scheme, so both one-time conversion markers are
-- stamped at birth -- otherwise the next _NormalizeTierOffsetAnchors pass
-- would "convert" (and silently shift) offsets that were never old-scheme.
ns._EnsureRaidSizeOverrides = function()
    local s = db.profile
    if not s.raidSizeOverrides then
        s.raidSizeOverrides = { _topLeftAnchored = true, _cornerAnchored = true }
    else
        -- Existing table: run any pending conversion now so edits that
        -- follow operate on post-conversion values.
        ns._NormalizeTierOffsetAnchors()
    end
    return s.raidSizeOverrides
end

-- One-time conversions (the markers travel INSIDE raidSizeOverrides, so
-- imported/swapped profiles self-convert -- no migration-flag inheritance
-- trap). Each conversion applies at most once, in order, and rebases
-- offsets against the PREVIOUS scheme's post-conversion values, preserving
-- every tier's CURRENT on-screen position (within one physical pixel of
-- rounding).
--   #1 (_topLeftAnchored, June 2026): offsets saved under the old
--      "re-anchor the container at unlockPos.point" scheme -> offsets
--      relative to the base footprint's TOPLEFT.
--   #2 (_cornerAnchored, July 2026): TOPLEFT-relative offsets -> offsets
--      relative to the growth-derived pinned corner (ns._RFGrowthCorner).
--      Only tiers whose effective growth pins RIGHT and/or BOTTOM change;
--      DOWN+RIGHT tiers keep identical offsets.
ns._NormalizeTierOffsetAnchors = function()
    local s = db and db.profile
    if not s then return end
    local ov = s.raidSizeOverrides
    if not ov then return end
    if ov._topLeftAnchored and ov._cornerAnchored then return end
    local cs = PixelSnap(s.cellSpacing or 2)
    local gs = PixelSnap(s.groupSpacing or 8)
    local pos = s.unlockPos
    local bl, bt, bw, bh = ns._RFBaseTopLeft()
    if not ov._topLeftAnchored then
        ov._topLeftAnchored = true
        if pos and bl then
            for _, o in pairs(ov) do
                if type(o) == "table" then
                    local tw, th = ns._RFFootprint(
                        o.width or s.frameWidth or 72, o.height or s.frameHeight or 46,
                        o.unitGrowth or s.unitGrowth or "DOWN",
                        o.groupGrowth or s.groupGrowth or "RIGHT", cs, gs)
                    local tl, tt = ns._RFPosTopLeft(pos, tw, th)
                    o.offsetX = math.floor((o.offsetX or 0) + (tl - bl) + 0.5)
                    o.offsetY = math.floor((o.offsetY or 0) + (tt - bt) + 0.5)
                end
            end
        end
    end
    if not ov._cornerAnchored then
        ov._cornerAnchored = true
        if pos and bl then
            for _, o in pairs(ov) do
                if type(o) == "table" then
                    local ug = o.unitGrowth or s.unitGrowth or "DOWN"
                    local gg = o.groupGrowth or s.groupGrowth or "RIGHT"
                    local tw, th = ns._RFFootprint(
                        o.width or s.frameWidth or 72, o.height or s.frameHeight or 46,
                        ug, gg, cs, gs)
                    local kx, ky = ns._RFCornerTerms(tw, th, bw, bh, ug, gg)
                    if kx ~= 0 then
                        o.offsetX = math.floor((o.offsetX or 0) - kx + 0.5)
                    end
                    if ky ~= 0 then
                        o.offsetY = math.floor((o.offsetY or 0) - ky + 0.5)
                    end
                end
            end
        end
    end
end

-- Apply tier-based position to the container frame.
-- The active tier's 4-group footprint pins its growth-derived corner
-- (ns._RFGrowthCorner, from the tier's EFFECTIVE unit + group growth) at
-- the BASE (20-man) footprint's same corner, plus the tier's saved
-- offsets, via the shared ns._RFTierTopLeft origin. A tier whose frames
-- are larger or smaller than the base therefore grows/shrinks AWAY from
-- the pinned corner: group growth RIGHT + unit growth DOWN pins the
-- top-left, LEFT + UP pins the bottom-right, and so on. unlockPos itself
-- is untouched (only the origin derivation changed; saved tier offsets
-- were rebased once per scheme by _NormalizeTierOffsetAnchors). For the
-- base tier or no overrides every corner term cancels, reproducing the
-- plain base top-left -- identical behavior for no-override profiles.
ns._ApplyTierOffset = function()
    if not containerFrame or InCombatLockdown() then return end
    -- Element-anchored container: the unlock anchor system owns the position
    -- (absolute coords recomputed from the anchor target), so repositioning
    -- from unlockPos here would clobber it on every roster/tier pass. The
    -- anchor's edge-to-edge offsets keep the near edge flush across tier
    -- size changes; per-tier offsets do not apply while anchored.
    if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("RF_RaidFrames") then return end
    local s = db.profile
    if not s.unlockPos then return end
    local _, ov = ns._RFResolveTierOverride(ns._GetEffectiveRaidSize())
    local cs = PixelSnap(s.cellSpacing or 2)
    local gs = PixelSnap(s.groupSpacing or 8)
    local fw = (ov and ov.width) or s.frameWidth or 72
    local fh = (ov and ov.height) or s.frameHeight or 46
    local ug = (ov and ov.unitGrowth) or s.unitGrowth or "DOWN"
    local gg = (ov and ov.groupGrowth) or s.groupGrowth or "RIGHT"
    local tw, th = ns._RFFootprint(fw, fh, ug, gg, cs, gs)
    local x, y = ns._RFTierTopLeft(tw, th, ug, gg,
        (ov and ov.offsetX) or 0, (ov and ov.offsetY) or 0)
    if not x then return end
    containerFrame:ClearAllPoints()
    containerFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", PixelSnap(x), PixelSnap(y))
end

-- TEMP DEBUG (read-only, prints only): diagnose the vertical-group-growth
-- stacking bug. Reproduce (25/30-man, group growth DOWN/UP), then run:
--   /run EllesmereUI._RF_DumpLayout()
-- It reports each visible group header's anchor + on-screen top-left and the
-- first two units' on-screen positions, so we can tell whether the GROUPS
-- overlap or the UNITS within a group stack, and at what coordinates. Remove
-- once the root cause is found.
function EllesmereUI._RF_DumpLayout()
    local s = db.profile
    local function r(v) if v then return floor(v + 0.5) else return "nil" end end
    print("|cff66ccffEUI RF Layout Dump|r")
    print(("  members=%s activeSize=%sx%s group=%s unit=%s tierOv=%s merge=%s"):format(
        tostring(GetNumGroupMembers()), tostring(ns._activeSizeW), tostring(ns._activeSizeH),
        tostring(s.groupGrowth), tostring(s.unitGrowth),
        ns._activeTierOverride and "yes" or "no", s.mergeGroups and "yes" or "no"))
    if containerFrame then
        print(("  container LT=(%s,%s) size=%sx%s"):format(
            r(containerFrame:GetLeft()), r(containerFrame:GetTop()),
            r(containerFrame:GetWidth()), r(containerFrame:GetHeight())))
    end
    for g = 1, 8 do
        local hdr = separatedHdrs[g]
        if hdr and hdr:IsShown() then
            local pt, _, _, hx, hy = hdr:GetPoint(1)
            print(("  G%d pt=%s off=(%s,%s) hdrLT=(%s,%s)"):format(
                g, tostring(pt), r(hx), r(hy), r(hdr:GetLeft()), r(hdr:GetTop())))
            local b1, b2 = hdr[1], hdr[2]
            if b1 then print(("     u1=%s LT=(%s,%s)"):format(tostring(b1:GetAttribute("unit")), r(b1:GetLeft()), r(b1:GetTop()))) end
            if b2 then print(("     u2 LT=(%s,%s)"):format(r(b2:GetLeft()), r(b2:GetTop()))) end
        end
    end
end

-- TEMP DEBUG: diagnose per-tier offset application.
-- /run EllesmereUI._RF_DumpOffset()
function EllesmereUI._RF_DumpOffset()
    local s = db.profile
    local r = function(v) if v then return floor(v + 0.5) else return "nil" end end
    print("|cff66ccffEUI RF Offset Dump|r")
    print(("  unlockPos: %s"):format(s.unlockPos and ("%s/%s x=%s y=%s"):format(
        s.unlockPos.point, s.unlockPos.relPoint, r(s.unlockPos.x), r(s.unlockPos.y)) or "|cffff6666nil|r"))
    local eff = ns._GetEffectiveRaidSize()
    local tier, ov = ns._RFResolveTierOverride(eff)
    print(("  effectiveSize=%s  resolvedTier=%s  hasOverride=%s"):format(
        tostring(eff), tostring(tier), ov and "yes" or "no"))
    if ov then
        print(("  override: w=%s h=%s offsetX=%s offsetY=%s ug=%s gg=%s"):format(
            tostring(ov.width), tostring(ov.height), tostring(ov.offsetX), tostring(ov.offsetY),
            tostring(ov.unitGrowth), tostring(ov.groupGrowth)))
    end
    print(("  _activeSizeW=%s _activeSizeH=%s _activeTierOv=%s"):format(
        tostring(ns._activeSizeW), tostring(ns._activeSizeH),
        ns._activeTierOverride and "yes" or "no"))
    local bl, bt, bw, bh = ns._RFBaseTopLeft()
    print(("  baseTL: l=%s t=%s bw=%s bh=%s"):format(r(bl), r(bt), r(bw), r(bh)))
    if ov then
        local cs = PixelSnap(s.cellSpacing or 2)
        local gs = PixelSnap(s.groupSpacing or 8)
        local fw = ov.width or s.frameWidth or 72
        local fh = ov.height or s.frameHeight or 46
        local ug = ov.unitGrowth or s.unitGrowth or "DOWN"
        local gg = ov.groupGrowth or s.groupGrowth or "RIGHT"
        local tw, th = ns._RFFootprint(fw, fh, ug, gg, cs, gs)
        local kx, ky = ns._RFCornerTerms(tw, th, bw or 0, bh or 0, ug, gg)
        local x, y = ns._RFTierTopLeft(tw, th, ug, gg, ov.offsetX or 0, ov.offsetY or 0)
        print(("  tierFootprint: tw=%s th=%s  corner=%s kx=%s ky=%s"):format(
            r(tw), r(th), ns._RFGrowthCorner(ug, gg), r(kx), r(ky)))
        print(("  computed TL: x=%s y=%s"):format(r(x), r(y)))
    end
    if containerFrame then
        print(("  container actual: L=%s T=%s W=%s H=%s"):format(
            r(containerFrame:GetLeft()), r(containerFrame:GetTop()),
            r(containerFrame:GetWidth()), r(containerFrame:GetHeight())))
        local anchored = EllesmereUI.IsUnlockAnchored
            and EllesmereUI.IsUnlockAnchored("RF_RaidFrames")
        print(("  isAnchored=%s"):format(anchored and "yes" or "no"))
    end
    local ovs = s.raidSizeOverrides
    if ovs then
        local tiers = {}
        for k, v in pairs(ovs) do
            if type(v) == "table" then tiers[#tiers + 1] = k end
        end
        table.sort(tiers)
        for _, t in ipairs(tiers) do
            local o = ovs[t]
            print(("  tier[%d]: w=%s h=%s ox=%s oy=%s ug=%s gg=%s"):format(
                t, tostring(o.width), tostring(o.height),
                tostring(o.offsetX), tostring(o.offsetY),
                tostring(o.unitGrowth), tostring(o.groupGrowth)))
        end
    else
        print("  raidSizeOverrides: nil")
    end
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
    local rs = rd._isParty and ns._scaledPartyProxy or (rd._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    local oorAlpha = rs.oorAlpha or 0.4
    if UnitIsUnit(unit, "player") or not UnitExists(unit) then
        ApplyRangeAlpha(btn, 1)
    elseif not UnitIsConnected(unit) then
        -- Offline units take a fixed 80% alpha, never the out-of-range fade --
        -- an offline player isn't "out of range", and a steady alpha reads
        -- better alongside the offline status tint. Overrides oorAlpha entirely.
        ApplyRangeAlpha(btn, 0.8)
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
    for unit, btn in pairs(ns._xfUnitToButton) do UpdateButtonRange(unit, btn) end
    ns.ProfEnd("RangeUpdate", t0)
end
ns._RangeSeedAll = RangeUpdate

local function RangeRefineAll()
    local t0 = ns.ProfBegin("RangeRefine")
    for unit, btn in pairs(unitToButton) do RefineButtonRange(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do RefineButtonRange(unit, btn) end
    for unit, btn in pairs(ns._xfUnitToButton) do RefineButtonRange(unit, btn) end
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
    for _, btn in pairs(ns._xfUnitToButton) do ApplyRangeAlpha(btn, 1) end
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
                        ns.StopDebuffCCGlow(icon)
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
    for unit, btn in pairs(ns._xfUnitToButton) do checkUnit(unit, btn) end
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
    for _, btn in pairs(ns._xfUnitToButton) do
        local d = GetFFD(btn)
        d.ghostCleared = nil
    end
end

-------------------------------------------------------------------------------
--  Visibility: show/hide based on solo/group/raid setting
-------------------------------------------------------------------------------
local framesVisible = false

-- True when the player is inside an arena instance. Arena puts you in a RAID
-- group, but we deliberately show our PARTY frames there (the party header is
-- bound to raid1-5 via showRaid=true) so small-group styling applies and
-- external trackers that anchor to our party frames keep working. Detection is
-- by instance type and must be checked BEFORE any IsInRaid() branch, since
-- arena makes IsInRaid() return true.
ns._InArena = function()
    local _, instanceType = IsInInstance()
    return instanceType == "arena"
end

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
    -- Arena hides the raid frames. The player is in a raid group there, but
    -- arena shows our party frames instead (see _UpdatePartyVisibility), so the
    -- raid container must stay hidden even though IsInRaid() returns true.
    local inArena = ns._InArena()
    local visible = false
    if IsInRaid() and not inArena then
        visible = true
    elseif IsInGroup() then
        visible = false  -- party frames handle group visibility (incl. arena)
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
        -- Combat starting: hide role/leader icons on frames using the in-combat cogs.
        if ns._UpdateRoleIcons then ns._UpdateRoleIcons() end
        if ns._UpdateLeaderIcons then ns._UpdateLeaderIcons() end
        if ns._CombatIconEnabled() and ns._UpdateCombatIcons then ns._UpdateCombatIcons() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        -- Combat ended: restore any role/leader icons suppressed during combat.
        if ns._UpdateRoleIcons then ns._UpdateRoleIcons() end
        if ns._UpdateLeaderIcons then ns._UpdateLeaderIcons() end
        if ns._CombatIconEnabled() and ns._UpdateCombatIcons then ns._UpdateCombatIcons() end
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
                -- Same-dimension tier changes take the LayoutGroups branch;
                -- reapply offset so the container lands at the correct tier.
                if ns._ApplyTierOffset then ns._ApplyTierOffset() end
            end
            if ns._partyFramesVisible then
                ns._LayoutPartyFrames()
            end
        end
    elseif event == "ENCOUNTER_START" then
        -- Drives the raid/party frame "Out of Boss Combat" tooltip mode (read in
        -- the frame OnEnter via ns._inBossCombat).
        ns._inBossCombat = true
    elseif event == "ENCOUNTER_END" then
        ns._inBossCombat = false
    elseif event == "PLAYER_ROLES_ASSIGNED" then
        -- Roles changed: refresh raid sort so the player's-group nameList
        -- (Show Self First) re-orders the rest by the new roles. The other
        -- groups re-sort natively. Out of combat only; no-op if order unchanged.
        if not inCombat and framesVisible and ns._ApplySortToHeaders then
            ns._ApplySortToHeaders()
        end
        -- Party Prioritize Class and the arena self-order nameList are both
        -- role-aware, so a role change must rebuild them (native role sort
        -- updates itself; these do not).
        if not inCombat and ns._partyFramesVisible
            and (db.profile.partyPrioritizeClass or ns._InArena())
            and ns._LayoutPartyFrames then
            ns._LayoutPartyFrames()
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
        if inCombat then
            ns._rosterDirtyInCombat = true
            -- Check if size tier changed during combat (deferred to REGEN)
            local numMembers = ns._GetEffectiveRaidSize()
            if numMembers > 0 then
                local newW, newH = ns._GetRaidSizeFrameDimensions(numMembers)
                if newW ~= ns._activeSizeW or newH ~= ns._activeSizeH then
                    ns._sizeTierDirtyInCombat = true
                end
                local newTier, newOv = ns._RFResolveTierOverride(numMembers)
                if newOv ~= ns._activeTierOverride then
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
                            local d = GetFFD(btn)
                            -- Extra Frames duplicates never own a map slot
                            if not d._isExtra then unitToButton[u] = btn end
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
            local numMembers = ns._GetEffectiveRaidSize()
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
                -- Re-derive the growth-corner anchor after any roster-driven
                -- layout. tierChanged above compares frame DIMENSIONS, so two
                -- tiers sharing a size (fresh tiers copy the base 20-man size)
                -- take the bare-LayoutGroups branches even when their offsets
                -- or growth differ -- without this, a roster that refined from
                -- an early undercount (streaming subgroup data at join) left
                -- the container stuck on the small-tier position until the
                -- next full reload. Cheap, idempotent, self-gates on combat.
                if ns._ApplyTierOffset then ns._ApplyTierOffset() end
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
            -- Power-colored bg: retint only when the power type or BG darken
            -- changed; the stamps keep the hot path allocation-free.
            local s = d._isParty and ns._scaledPartyProxy or ns._scaledProfile
            if s.powerBgPowerColored and d.powerBg then
                local f = EllesmereUI.GetPowerBgDarkenFactor()
                if d._pwBgTintType ~= pType or d._pwBgTintF ~= f then
                    d.powerBg:SetColorTexture(pr * f, pg * f, pb * f, (s.powerBgDarkness or 70) / 100)
                    d._pwBgTintType = pType
                    d._pwBgTintF = f
                end
            end
            ns.ProfEnd("PowerUpdate", t0)
        end
    elseif event == "UNIT_AURA" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            if EllesmereUI.IS_121 then
                -- 12.1: aura displays are engine-driven containers; the absorb
                -- overlay (aura-granted shields) is the only consumer left here.
                local t0 = ns.ProfBegin("UpdateAbsorb:AURA"); UpdateAbsorb(btn, arg1); ns.ProfEnd("UpdateAbsorb:AURA", t0)
            else
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
        end
    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
        or event == "UNIT_HEAL_PREDICTION" or event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            local t0 = ns.ProfBegin("UpdateAbsorb:OTHER"); UpdateAbsorb(btn, arg1); ns.ProfEnd("UpdateAbsorb:OTHER", t0)
            if event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then ns.UpdateHealAbsorbTextFor(btn, arg1) end
        end
    elseif event == "UNIT_NAME_UPDATE" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then UpdateButton(btn) end
        -- NAMELIST-driven headers (party Prioritize Class, raid Show Self
        -- First) are built from member names. A member whose name populated
        -- late was unListable when the list was built -- the secure header
        -- hides their frame entirely, which is also why btn is nil for them
        -- here. Rebuild the lists now that the real name exists (debounced:
        -- names resolve in bursts after a loading screen). The builders bail
        -- to the groupFilter fallback while any name is still unresolved, so
        -- this also restores the proper order once the last name lands.
        if inCombat then
            ns._rosterDirtyInCombat = true
        else
            if ns._nameUpdateTimer then ns._nameUpdateTimer:Cancel() end
            ns._nameUpdateTimer = C_Timer.NewTimer(0.1, function()
                ns._nameUpdateTimer = nil
                if InCombatLockdown() then
                    ns._rosterDirtyInCombat = true
                    return
                end
                if ns._partyFramesVisible
                    and (db.profile.partyPrioritizeClass or ns._InArena())
                    and ns._LayoutPartyFrames then
                    ns._LayoutPartyFrames()
                end
                if framesVisible and ns._ApplySortToHeaders then
                    ns._ApplySortToHeaders()
                end
            end)
        end
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
    elseif event == "UNIT_FLAGS" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then ns._UpdateCombatIconFor(arg1, btn) end
    elseif event == "PLAYER_FLAGS_CHANGED" or event == "UNIT_CONNECTION" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            UpdateButton(btn)
            -- Connection changes don't fire UNIT_IN_RANGE_UPDATE; re-evaluate
            -- range so offline units take their fixed alpha and reconnecting
            -- units return to the normal out-of-range fade.
            if event == "UNIT_CONNECTION" then ns._UpdateButtonRange(arg1, btn) end
        end
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
                -- Re-evaluate rather than force-hide: a unit may have an incoming
                -- summon active that shares the same texture.
                for _, btn in ipairs(allButtons) do
                    local u = btn:GetAttribute("unit")
                    if u and btn:IsVisible() then UpdateReadyCheck(btn, u) end
                end
                for _, btn in ipairs(ns._partyAllButtons) do
                    local u = btn:GetAttribute("unit")
                    if u and btn:IsVisible() then UpdateReadyCheck(btn, u) end
                end
            end
        end)
    elseif event == "INCOMING_SUMMON_CHANGED" then
        -- Broadcast event (no unit payload); re-evaluate every visible button.
        for _, btn in ipairs(allButtons) do
            local u = btn:GetAttribute("unit")
            if u and btn:IsVisible() then UpdateReadyCheck(btn, u) end
        end
        for _, btn in ipairs(ns._partyAllButtons) do
            local u = btn:GetAttribute("unit")
            if u and btn:IsVisible() then UpdateReadyCheck(btn, u) end
        end
    elseif event == "INCOMING_RESURRECT_CHANGED" then
        -- Fires with a unit payload when a rez starts/stops on that unit. Refresh the
        -- status text (so DEAD hides while rezzing / reappears after) as well as the
        -- shared rez icon.
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn and btn:IsVisible() then
            if ns._UpdateButtonHealth then ns._UpdateButtonHealth(btn) end
            UpdateReadyCheck(btn, arg1)
        end
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
        -- Re-sync the boss-combat flag on load. IsEncounterInProgress() still
        -- reports an active encounter after a mid-fight /reload or zone (where
        -- ENCOUNTER_START already fired and will not fire again), so "Out of Boss
        -- Combat" keeps suppressing; otherwise this clears a stale flag from a
        -- missed ENCOUNTER_END so tooltips are not stuck hidden.
        ns._inBossCombat = (IsEncounterInProgress and IsEncounterInProgress()) or false
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
                -- Full party reload (not just layout), mirroring the raid
                -- branch above: private aura anchors registered during the
                -- loading screen can carry stale geometry (icon size /
                -- border scale are baked in at registration), and the
                -- unit-guarded rebuild paths skip re-registration when
                -- units are unchanged. ReloadPartyFrames recomputes the
                -- Auto Resize scale and re-registers every anchor.
                ns.ReloadPartyFrames()
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
    "healthBar", "absorbs", "powerBar", "textDisplay", "indicators", "dispels", "topNameBar",
    "rangeTooltip", "defensives", "privateAuras", "debuffDisplay", "debuffStyle",
}
ns._PARTY_SECTION_LABELS = {
    healthBar     = "Health Bar",
    absorbs       = "Absorbs",
    powerBar      = "Power Bar",
    textDisplay   = "Text Display",
    indicators    = "Indicators",
    dispels       = "Dispels",
    topNameBar    = "Top Name Bar",
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
            "customFillColor", "dynamicColor100", "dynamicColor50", "dynamicColor0",
            "customBgColor", "bgClassColored", "bgDarkness", "smoothBars",
            "healPrediction", "healPredOpacity", "healPredColor",
        },
        absorbs = {
            "absorbStyle", "absorbOpacity", "absorbColor", "absorbEdgeMode", "showOvershield",
            "absorbBarEnabled", "absorbBarPosition", "absorbBarHeight", "absorbBarColor",
            "absorbBarGrowDir",
            "healAbsorbBarPosition", "healAbsorbBarHeight", "healAbsorbBarColor",
            "healAbsorbBarGrowDir",
            "healAbsorbStyle", "healAbsorbOpacity", "healAbsorbColor", "healAbsorbEdgeMode",
            "healAbsorbBgOpacity",
            "maxHealthStyle", "maxHealthOpacity", "maxHealthColor", "maxHealthBgOpacity",
        },
        powerBar = {
            "showPowerBar", "powerHeight", "powerBgDarkness", "powerBgColor", "powerBgPowerColored",
            "powerBorderStyle", "powerBorderSize", "powerBorderColor", "powerBorderAlpha",
            "powerShowForHealer", "powerShowForTank", "powerShowForDPS", "smoothPowerBars",
            "powerUniformAnchors",
        },
        textDisplay = {
            "nameSize", "nameColorMode", "nameCustomColor",
            "namePosition", "nameOffsetX", "nameOffsetY",
            "healthTextMode", "healthTextColorMode", "healthTextCustomColor",
            "healthTextSize", "healthTextPosition", "healthTextOffsetX", "healthTextOffsetY",
            "healAbsorbTextMode", "healAbsorbTextColorMode", "healAbsorbTextCustomColor",
            "healAbsorbTextSize", "healAbsorbTextPosition", "healAbsorbTextOffsetX", "healAbsorbTextOffsetY",
        },
        indicators = {
            "roleIconStyle", "roleIconSize", "roleIconPosition", "roleIconOffsetX", "roleIconOffsetY", "roleIconHideInCombat",
            "showRoleForTank", "showRoleForHealer", "showRoleForDPS",
            "showRaidMarker", "raidMarkerSize", "raidMarkerPosition", "raidMarkerOffsetX", "raidMarkerOffsetY",
            "showReadyCheck", "showSummonPending", "showIncomingRez",
            "readyCheckSize", "readyCheckPosition", "readyCheckOffsetX", "readyCheckOffsetY",
            "statusTextPosition", "statusTextOffsetX", "statusTextOffsetY", "statusTextSize", "statusTextColor",
            "showLeaderIcon", "showLeaderIconInCombat", "leaderIconPosition", "leaderIconSize", "leaderIconOffsetX", "leaderIconOffsetY",
            "showCombatIndicator", "combatIndicatorStyle", "combatIndicatorColor", "combatIndicatorCustomColor",
            "combatIndicatorSize", "combatIndicatorPosition", "combatIndicatorOffsetX", "combatIndicatorOffsetY",
            "borderSize", "borderColor", "borderAlpha", "borderTexture",
            "borderBehind", "borderTextureOffset", "borderTextureOffsetY",
            "borderTextureShiftX", "borderTextureShiftY",
            "hoverBorderEnabled", "hoverBorderSize", "hoverBorderColor", "hoverBorderAlpha",
            "targetBorderEnabled", "targetBorderSize", "targetBorderColor", "targetBorderAlpha", "threatBorderSize",
        },
        dispels = {
            "dispelBorderSize", "dispelOverlay", "dispelOverlayOpacity", "dispelShowAll",
            "showDispelIcons", "dispelIconPosition", "dispelIconOffsetX", "dispelIconOffsetY", "dispelIconSize",
            "dispelColorMagic", "dispelColorCurse", "dispelColorDisease",
            "dispelColorPoison", "dispelColorBleed",
        },
        topNameBar = {
            "topNameBarEnabled", "topNameBarHeight",
            "topNameBarBgColor", "topNameBarBgOpacity",
            "topNameBarTextSize", "topNameBarTextColorMode", "topNameBarTextColor",
            "topNameBarTextOffsetX", "topNameBarTextOffsetY", "topNameBarTextAlign",
        },
        rangeTooltip = {
            "oorAlpha", "showTooltip", "tooltipMode",
        },
        defensives = {
            "showDefensives", "showExternals",
            "defPosition", "defOffsetX", "defOffsetY", "defGrowDirection",
            "defSize", "defIconZoom", "defSpacing", "defBorderSize", "defBorderColor",
            "defShowSwipe", "defShowDurText", "defDurTextColor", "defDurTextSize", "defDurTextOffsetX", "defDurTextOffsetY",
        },
        privateAuras = {
            "paSize", "paShowCountdown", "paHideTooltip",
            "paPosition", "paOffsetX", "paOffsetY", "paGrowDirection", "paSpacing",
        },
        debuffDisplay = {
            "debuffFilter", "hideLustDebuff",
            "debuffPosition", "debuffOffsetX", "debuffOffsetY",
            "debuffGrowDirection", "debuffPerRow", "debuffWrapDirection",
            "debuffCap", "debuffHideTooltips",
            "dispellableDebuffLocation", "dispellableDebuffGrowDirection",
            "dispellableDebuffOffsetX", "dispellableDebuffOffsetY", "dispellableDebuffSize",
        },
        debuffStyle = {
            "debuffSize", "debuffIconZoom", "debuffBorderSize", "debuffBorderColor", "debuffSpacing",
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

-- The Absorbs section was split out of Health Bar: profiles saved before the
-- split carry no "absorbs" sync state, so they inherit the Health Bar state
-- that governed those settings at the time. Idempotent (only fills a nil key)
-- and runs on every enable/profile swap, so imported profiles are covered too.
ns._NormalizePartySyncSections = function()
    if not (db and db.profile) then return end
    local ss = db.profile.partySyncSections
    if ss and ss.absorbs == nil and ss.healthBar == false then
        ss.absorbs = false
    end
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
-- Buff Manager scales: identical formulas but NOT gated on the Auto Resize
-- toggles -- BM indicators always track frame size (raid tier / party size).
ns._bmScale = 1
ns._partyBmScale = 1
-- Extra Frames duplicates: scale ratio from the Extra Width/Height offsets,
-- relative to the size the real raid frames currently render at. ALWAYS on
-- (not gated by Auto Resize): a custom-sized duplicate scales its texts,
-- indicators, auras and BM buffs to match. Composes with the raid tier
-- scales -- the extra proxy chains through ns._scaledProfile, and the BM
-- scale multiplies ns._bmScale. Both set by XF.Layout.
ns._xfExtraRatio = 1
ns._xfBmScale = 1

local INDICATOR_SCALE_KEYS = {}
for _, k in ipairs({
    -- Font sizes
    "nameSize", "healthTextSize", "healAbsorbTextSize", "statusTextSize",
    "debuffStacksTextSize", "debuffDurTextSize", "defDurTextSize",
    -- Icon sizes
    "roleIconSize", "leaderIconSize", "raidMarkerSize", "combatIndicatorSize",
    "debuffSize", "defSize", "paSize", "dispellableDebuffSize",
    -- Offsets
    "nameOffsetX", "nameOffsetY",
    "healthTextOffsetX", "healthTextOffsetY",
    "healAbsorbTextOffsetX", "healAbsorbTextOffsetY",
    "statusTextOffsetX", "statusTextOffsetY",
    "roleIconOffsetX", "roleIconOffsetY",
    "leaderIconOffsetX", "leaderIconOffsetY",
    "raidMarkerOffsetX", "raidMarkerOffsetY",
    "combatIndicatorOffsetX", "combatIndicatorOffsetY",
    "debuffOffsetX", "debuffOffsetY",
    "dispellableDebuffOffsetX", "dispellableDebuffOffsetY",
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

-- Extra Frames proxy: chains through ns._scaledProfile (so the raid tier
-- indicator scale still applies) and multiplies the scale keys by the Extra
-- Width/Height offset ratio on top. Selected wherever rendering picks a
-- settings source for a d._isExtra button.
ns._scaledExtraProxy = setmetatable({}, { __index = function(_, key)
    local val = ns._scaledProfile[key]
    if INDICATOR_SCALE_KEYS[key] and type(val) == "number" and ns._xfExtraRatio ~= 1 then
        return val * ns._xfExtraRatio
    end
    return val
end })

ns._scaledPartyProxy = setmetatable({}, { __index = function(_, key)
    -- Return party dimensions for frameWidth/frameHeight reads. The real-
    -- preview effective overlay (ns._pvOverlayProxy) shadows live while a
    -- panel view swap is active; it falls through to db.profile itself.
    if key == "frameWidth" then
        local p = ns._pvOverlayProxy or (db and db.profile)
        return p and (p.partyFrameWidth or p.frameWidth)
    end
    if key == "frameHeight" then
        local p = ns._pvOverlayProxy or (db and db.profile)
        return p and (p.partyFrameHeight or p.frameHeight)
    end
    local val
    local resolved = false
    -- Effective overlay first (preview-scoped ONLY -- ns._partyProxy also
    -- serves the REAL party frames and must never consult it): party_
    -- variant wins over the base key, mirroring _partyProxy's precedence.
    -- Sentinel deletions resolve to nil WITHOUT falling through to the
    -- live view value.
    local ov = ns._pvOverlayProxy and ns._pvOverlay
    if ov then
        local pv
        local section = ns._PARTY_KEY_SECTION[key]
        if section and ns._IsPartySectionCustom(section) then
            pv = ov["party_" .. key]
        end
        if pv == nil then pv = ov[key] end
        if pv ~= nil then
            resolved = true
            if pv ~= EllesmereUI.SPECOV_NIL then val = pv end
        end
    end
    if not resolved then val = ns._partyProxy[key] end
    if INDICATOR_SCALE_KEYS[key] and type(val) == "number" and ns._partyIndicatorScale ~= 1 then
        return val * ns._partyIndicatorScale
    end
    return val
end })

-- Compute the party indicator/aura scale (mirrors the raid auto-resize in
-- ReloadFrames). Party frames have a fixed size (no tiers), so the scale is the
-- party frame size relative to the configured raid base, clamped to [0.7, 1.5].
-- Independent of raid: gated on partyAutoResizeIndicators (default off).
ns._UpdatePartyIndicatorScale = function()
    if not (db and db.profile) then return end
    local s = db.profile
    local baseW = s.frameWidth or 72
    local baseH = s.frameHeight or 46
    local pw = s.partyFrameWidth or s.frameWidth or 125
    local ph = s.partyFrameHeight or s.frameHeight or 60
    local scale = math.max(math.min(math.min(pw / baseW, ph / baseH), 1.3), 0.7)
    -- Auto Resize Icons (two independent checkboxes): Tracked Buffs gates the
    -- Buff Manager scale; Indicators & Auras gates indicator/aura/text sizes.
    -- Tracked Buffs defaults on (nil treated as on) to preserve the prior
    -- hardcoded always-on behavior.
    ns._partyBmScale = (s.partyAutoResizeTrackedBuffs ~= false) and scale or 1
    ns._partyIndicatorScale = s.partyAutoResizeIndicators and scale or 1
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
    if EllesmereUI.IS_121 then
        hdr:SetAttribute("auraContainerTemplate", "CustomAuraContainerTemplate")
    end
    hdr:SetAttribute("template", "SecureUnitButtonTemplate")
    hdr:SetAttribute("templateType", "Button")
    hdr:SetAttribute("initialConfigFunction", initConfig)
    hdr:SetAttribute("point", "TOP")
    hdr:SetAttribute("xOffset", 0)
    hdr:SetAttribute("yOffset", -cs)
    hdr:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8")
    -- showRaid=true so the header binds raid1-5 inside an arena, where the team
    -- is a raid group. Inert in a normal 5-man party (no raid units exist), so
    -- it only takes effect when the header is actually shown in a raid group --
    -- which we do only for arena (see _UpdatePartyVisibility). Outside arena the
    -- header is hidden in a real raid, so this never shows 40 raid units.
    hdr:SetAttribute("showRaid", true)
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

-- Position the self button + party header at their slot offsets, sized from
-- the CURRENT frame dimensions. Shared by the full layout pass and the
-- width/height slider hot path (_ResizePartyButtons): the slot offsets and
-- the header's own size both derive from the frame size, so a live resize
-- must re-apply them or the self button drifts from the header stack and the
-- header's centered child anchors keep growing around the stale width.
-- Returns useSelf for the caller's showPlayer attribute logic.
ns._PositionPartySlots = function(bw, bh, cs, unitGrowth)
    if not ns._partyHeader then return false end
    local s = db.profile
    local pSelfFirst = s.partyShowSelfFirst
    if pSelfFirst == nil then pSelfFirst = s.showSelfFirst end
    local pSelfLast = s.partySelfLast
    if pSelfLast == nil then pSelfLast = s.showSelfLast end
    local hideSelf = s.partyHideSelf
    -- Arena binds the header to raid1-5, which always includes the player, and
    -- showPlayer=false cannot exclude the player in a raid group. The static
    -- self button would then duplicate the player, so disable it in arena and
    -- let the header show the player natively (in arena showPlayer reduces to
    -- "not hideSelf" in _LayoutPartyFrames; the arena nameList -- not showPlayer
    -- -- is what omits the player when Hide Self is on).
    local useSelf = (pSelfFirst or pSelfLast) and not hideSelf and IsInGroup() and not ns._InArena()

    -- The header's own size feeds the first child's centered anchor
    -- (point=TOP centers on header width; point=LEFT centers on height).
    -- Anchors track size changes live, so this re-centers the stack with NO
    -- secure child re-process (and therefore no blink) during slider drags.
    -- The header re-derives the same size on its next natural child pass.
    ns._partyHeader:SetSize(bw, bh)

    -- Step between adjacent unit slots along the growth axis. Slot 0 sits at
    -- the container corner the growth direction moves AWAY from (Flip Frame
    -- Growth turns DOWN into UP and RIGHT into LEFT), so the container always
    -- bounds the visual stack.
    local slotStepX, slotStepY = 0, 0
    local basePoint = "TOPLEFT"
    if unitGrowth == "RIGHT" then
        slotStepX = bw + cs
    elseif unitGrowth == "LEFT" then
        slotStepX = -(bw + cs); basePoint = "TOPRIGHT"
    elseif unitGrowth == "UP" then
        slotStepY = bh + cs; basePoint = "BOTTOMLEFT"
    else -- DOWN
        slotStepY = -(bh + cs)
    end

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
            sb:SetPoint(basePoint, ns._partyContainerFrame, basePoint, PixelSnap(slotStepX * selfSlot), PixelSnap(slotStepY * selfSlot))
            if not InCombatLockdown() then sb:Show() end
        end
        ns._partyHeader:ClearAllPoints()
        ns._partyHeader:SetPoint(basePoint, ns._partyContainerFrame, basePoint, PixelSnap(slotStepX * hdrSlot), PixelSnap(slotStepY * hdrSlot))
    else
        if sb and not InCombatLockdown() then sb:Hide() end
        ns._partyHeader:ClearAllPoints()
        -- Center When Solo: when not in a group, center the lone player frame in
        -- the container by offsetting the header 2 slots along the growth axis
        -- ((5-1)/2 = 2). The container is always sized for 5 slots, so a single
        -- frame at slot 2 sits centered.
        local cOffX, cOffY = 0, 0
        if s.partyCenterWhenSolo and not IsInGroup() then
            cOffX = slotStepX * 2
            cOffY = slotStepY * 2
        end
        ns._partyHeader:SetPoint(basePoint, ns._partyContainerFrame, basePoint, PixelSnap(cOffX), PixelSnap(cOffY))
    end
    return useSelf
end

-- Layout party frames: apply unitGrowth direction and cell spacing to the header.
ns._LayoutPartyFrames = function()
    if not ns._partyHeader then return end
    if InCombatLockdown() then return end

    local s = db.profile
    local bw = PixelSnap(s.partyFrameWidth or s.frameWidth or 125)
    local bh = PixelSnap(s.partyFrameHeight or s.frameHeight or 60)
    local cs = PixelSnap(s.partyCellSpacing or s.cellSpacing or 2)
    local unitGrowth = s.partyHorizontal and (s.partyFlipGrowth and "LEFT" or "RIGHT")
        or (s.partyFlipGrowth and "UP" or "DOWN")

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

    -- Self button + header slot positioning (also sets the header's own size,
    -- which drives the children's centered anchors). Shared with the slider
    -- hot path; returns useSelf for the showPlayer attribute logic below.
    -- Self-first via composition: a static unit="player" self button owns
    -- slot 0 and the party header excludes the player (showPlayer=false);
    -- self ordering only matters in a group (see ns._PositionPartySlots).
    local useSelf = ns._PositionPartySlots(bw, bh, cs, unitGrowth)
    local hideSelf = s.partyHideSelf

    -- Size container for unlock mode mover (always sized for 5 units)
    local containerW, containerH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        containerW = 5 * bw + 4 * cs
        containerH = bh
    else
        containerW = bw
        containerH = 5 * bh + 4 * cs
    end
    local newCW, newCH = PixelSnap(containerW), PixelSnap(containerH)
    local curCW, curCH = ns._partyContainerFrame:GetSize()
    if math.abs((curCW or 0) - newCW) > 0.01 or math.abs((curCH or 0) - newCH) > 0.01 then
        -- Resizing the container triggers an implicit SecureGroupHeader child
        -- re-process, and that implicit pass has been observed landing with
        -- units unassigned (NAMELIST sort especially): children left hidden
        -- with unit=nil until the next clean re-process. Bracket the resize
        -- with an explicit header Hide/Show -- the implicit pass runs while
        -- hidden (inert) and the Show() performs a clean, reliable re-process.
        -- Skipping the resize entirely when unchanged also avoids pointless
        -- re-processes on every settings reload.
        local hdrWasShown = ns._partyHeader:IsShown()
        if hdrWasShown then ns._partyHeader:Hide() end
        ns._partyContainerFrame:SetSize(newCW, newCH)
        if hdrWasShown then ns._partyHeader:Show() end
    end

    -- Apply sort attributes + player visibility to the party header
    if not InCombatLockdown() then
        local pSortMode = s.partySortMode or s.sortMode
        local sortByRole = pSortMode == "ROLE"
        local roleOrder = s.partyRoleOrder or s.roleOrder or { "TANK", "HEALER", "DAMAGER" }
        -- showPlayer is false when the self button owns the player (useSelf) or
        -- when hiding self; true only for a normal in-header player frame. In
        -- arena useSelf is forced false (no self button), so this reduces to
        -- "show the player unless Hide Self" -- and the arena nameList below
        -- keeps membership consistent by omitting the player when Hide Self.
        local wantShowPlayer = not hideSelf and not useSelf

        -- Prioritize Class drives the header with an explicit nameList ordered by
        -- role (optional primary) -> class -> name. nameList is honored only when
        -- groupFilter is cleared, so we clear it and let showParty/showPlayer pick
        -- members. When off, fall back to the native groupBy/sortMethod path.
        local wantGroupBy, wantSortMethod, wantGroupingOrder, wantNameList, wantGroupFilter
        if ns._InArena() then
            -- Arena runs on raid1-5, where Prioritize Class cannot work (it
            -- iterates party1-4) and neither the self button nor showPlayer can
            -- order or hide the player. A raid-token nameList does both: it
            -- honors Show Self First / Self Last / Hide Self and still shows
            -- every teammate (bailing to native order until names resolve).
            local pSelfFirst = s.partyShowSelfFirst
            if pSelfFirst == nil then pSelfFirst = s.showSelfFirst end
            local pSelfLast = s.partySelfLast
            if pSelfLast == nil then pSelfLast = s.showSelfLast end
            wantNameList = ns._BuildArenaNameList(hideSelf, pSelfFirst, pSelfLast, sortByRole, roleOrder)
        elseif s.partyPrioritizeClass then
            wantNameList = ns._BuildPartyClassNameList(wantShowPlayer, sortByRole, roleOrder, s.partyClassOrder)
        end
        if wantNameList then
            wantGroupBy = nil
            wantSortMethod = "NAMELIST"
            wantGroupingOrder = ""
            wantGroupFilter = nil
        else
            wantNameList = nil
            wantGroupBy = sortByRole and "ASSIGNEDROLE" or nil
            wantSortMethod = sortByRole and "NAME" or "INDEX"
            wantGroupingOrder = sortByRole and (table.concat(roleOrder, ",") .. ",NONE") or ""
            wantGroupFilter = "1,2,3,4,5,6,7,8"
        end

        local function ApplyAttrs()
            ns._partyHeader:SetAttribute("groupFilter", wantGroupFilter)
            ns._partyHeader:SetAttribute("nameList", wantNameList)
            ns._partyHeader:SetAttribute("groupingOrder", wantGroupingOrder)
            ns._partyHeader:SetAttribute("groupBy", wantGroupBy)
            ns._partyHeader:SetAttribute("sortMethod", wantSortMethod)
            ns._partyHeader:SetAttribute("showPlayer", wantShowPlayer)
        end
        local needsHideShow = (ns._partyHeader:GetAttribute("groupBy") ~= wantGroupBy)
            or (ns._partyHeader:GetAttribute("sortMethod") ~= wantSortMethod)
            or (ns._partyHeader:GetAttribute("groupingOrder") ~= wantGroupingOrder)
            or (ns._partyHeader:GetAttribute("showPlayer") ~= wantShowPlayer)
            or (ns._partyHeader:GetAttribute("nameList") ~= wantNameList)
            or (ns._partyHeader:GetAttribute("groupFilter") ~= wantGroupFilter)
        if needsHideShow and ns._partyHeader:IsShown() then
            ns._partyHeader:Hide()
            ApplyAttrs()
            ns._partyHeader:Show()
        elseif needsHideShow then
            ApplyAttrs()
        end
    end

    -- Self button + header slot positioning ran above (ns._PositionPartySlots),
    -- before the attribute pass so a header Hide/Show re-process anchors the
    -- children against the already-correct header position and size.
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
    -- Arena shows party frames even though IsInRaid() is true (the team is a
    -- raid group). The header binds raid1-5 via showRaid=true; the raid
    -- container is hidden in arena by UpdateVisibility.
    local inArena = ns._InArena()
    local visible = false
    if IsInGroup() and (inArena or not IsInRaid()) then
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
    -- Re-evaluate UNIT_FLAGS registration before the temp-swap below (which
    -- overwrites db.profile), so a section sync/unsync that flips the party's
    -- effective combat-icon state turns the party trackers on/off in step.
    if ns.UpdateCombatEventRegistration then ns.UpdateCombatEventRegistration() end
    local p = ns._partyProxy  -- reads party_ keys with fallthrough
    local raw = db.profile
    -- Scaled reads for everything in INDICATOR_SCALE_KEYS (role/leader/marker
    -- icons, aura icon sizes, text sizes): mirrors the raid loop, which reads
    -- through ns._scaledProfile. Non-scale keys pass through unchanged.
    local pp = ns._scaledPartyProxy

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
            d.bg:SetColorTexture(ns.GetBgColor(btn:GetAttribute("unit"), raw))
        end

        -- Health bar height/anchor + Top Name Bar (reads party-resolved `raw`)
        LayoutTopNameBar(raw, bh, powerH, d.health, d.topNameBar, d.topNameBarBg, d.topNameBarText)
        if d.health then
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
            d._pwBgTintType = nil
        end
        if d.UpdatePowerBorder then d.UpdatePowerBorder() end

        -- Name text
        if d.nameText then
            ApplyFont(d.nameText, pp.nameSize or 10)
            if d.AnchorNameText then d.AnchorNameText() end
            -- Override width constraint for party button dimensions
            d.nameText:SetWidth(bw * ns.RF_NAME_WIDTH_FRACTION)
        end

        -- Health text
        if d.healthText then
            ApplyFont(d.healthText, pp.healthTextSize or 9)
            if d.AnchorHealthText then d.AnchorHealthText() end
        end

        -- Heal absorb text
        if d.healAbsorbText then
            ApplyFont(d.healAbsorbText, pp.healAbsorbTextSize or 9)
            if d.AnchorHealAbsorbText then d.AnchorHealAbsorbText() end
        end

        -- Status text
        if d.statusText then
            local stc = raw.statusTextColor or { r = 1, g = 1, b = 1 }
            ApplyFont(d.statusText, pp.statusTextSize or 14)
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            if d.AnchorStatusText then d.AnchorStatusText() end
        end

        -- Role icon
        if d.roleIcon then
            local riSz = PixelSnap(pp.roleIconSize or 14)
            d.roleIcon:SetSize(riSz, riSz)
            if d.AnchorRoleIcon then d.AnchorRoleIcon() end
        end

        -- Leader icon
        if d.leaderIcon then
            local liSz = PixelSnap(pp.leaderIconSize or 14)
            d.leaderIcon:SetSize(liSz, liSz)
            d.leaderIcon:ClearAllPoints()
            local liPos = (raw.leaderIconPosition or "top"):upper()
            d.leaderIcon:SetPoint(liPos, ns.RF_AnchorHost(d.health, pp), liPos, pp.leaderIconOffsetX or 0, pp.leaderIconOffsetY or 0)
            -- Re-assert the host's strata/level above the border
            if d.leaderHost then ns.ApplyLeaderStrata(d.leaderHost) end
        end

        -- Raid marker
        if d.raidMarker then
            local rmSz = PixelSnap(pp.raidMarkerSize or 16)
            d.raidMarker:SetSize(rmSz, rmSz)
            if d.AnchorRaidMarker then d.AnchorRaidMarker() end
        end

        -- Ready check / summon
        if d.readyCheck then
            local rcSz = PixelSnap(pp.readyCheckSize or 20)
            d.readyCheck:SetSize(rcSz, rcSz)
            if d.AnchorReadyCheck then d.AnchorReadyCheck() end
        end

        -- Combat icon
        if d.combatIcon then
            local cciSz = PixelSnap(pp.combatIndicatorSize or 16)
            d.combatIcon:SetSize(cciSz, cciSz)
            if d.AnchorCombatIcon then d.AnchorCombatIcon() end
        end

        -- Border
        if d.UpdateBorder then d.UpdateBorder() end

        -- Debuff icons
        if d.debuffIcons then
            for _, icon in ipairs(d.debuffIcons) do
                icon:SetSize(pp.debuffSize or 18, pp.debuffSize or 18)
                icon._euiSz = pp.debuffSize or 18
            end
            if d.AnchorDebuffs then d.AnchorDebuffs() end
        end

        -- Defensive icons
        if d.defIcons then
            for _, icon in ipairs(d.defIcons) do
                icon:SetSize(pp.defSize or 22, pp.defSize or 22)
            end
            if d.AnchorDefensives then d.AnchorDefensives() end
        end

        -- Dispel icon
        if d.AnchorDispelIcon then d.AnchorDispelIcon() end

        -- Private aura frames
        if d.privateAuraFrames then
            for _, paFrame in ipairs(d.privateAuraFrames) do
                paFrame:SetSize(pp.debuffSize or 18, pp.debuffSize or 18)
            end
        end

        -- Buff manager indicators (pass the scaled proxy: BM picks the party
        -- indicator scale by recognizing this exact table)
        if d.bmIconPool and d.health and ns.BM_AnchorIndicators then
            ns.BM_AnchorIndicators(d, ns.RF_AnchorHost(d.health, pp), pp)
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

    -- Targeted Spells icons scale through the party Auto Resize factor
    -- recomputed above; restyle them with everything else.
    if ns.TS_ApplySettings then ns.TS_ApplySettings() end

    -- Aura containers read the party class through its scaled proxy; the
    -- fingerprint guards make this near-free when nothing party-side changed.
    if ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
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
            noResize = true,
            -- RF positions its own container via _ApplyTierOffset (base 20-man
            -- top-left + per-tier offset, tier-footprint-INDEPENDENT), re-run on
            -- init / PEW / roster + tier changes / combat end. The centralized
            -- ApplySavedPositions init loop re-anchors at unlockPos.point using
            -- the CURRENT (per-tier) container size, which diverges from that
            -- scheme for every non-20 size (Y-only for side/bottom anchors) and
            -- clobbers the correct position ~0.6s after login. noInitHook keeps
            -- that loop from touching the container so _ApplyTierOffset stays the
            -- sole position authority. (Mover, save/load, anchors are unaffected.)
            noInitHook = true,

            getFrame = function() return containerFrame end,
            getSize  = function()
                return containerFrame:GetWidth(), containerFrame:GetHeight()
            end,

            savePos = function(_, point, relPoint, x, y, srcPoint, srcRelPoint)
                -- srcPoint/srcRelPoint: the PRE-conversion anchor the unlock
                -- framework received. Anything other than CENTER/CENTER means
                -- the CENTER coords were measured from the container's LIVE
                -- bounds -- the ACTIVE tier's footprint -- and must be rebased
                -- to the BASE footprint's equivalent center (the convention
                -- every apply reads), or a mover drag performed while a
                -- non-base tier is active lands off by a constant offset on
                -- the next _ApplyTierOffset pass. CENTER/CENTER or absent
                -- (revert / nudge / typed-edit callers) means the value is
                -- already stored-convention; rebasing again would corrupt it.
                if srcPoint and not (srcPoint == "CENTER" and (srcRelPoint or "CENTER") == "CENTER")
                    and ns._RFRebaseSavedCenter then
                    x, y = ns._RFRebaseSavedCenter(x, y)
                end
                db.profile.unlockPos = { point = point, relPoint = relPoint, x = snap(containerFrame, x), y = snap(containerFrame, y) }
            end,
            loadPos = function()
                return db.profile.unlockPos
            end,
            clearPos = function()
                db.profile.unlockPos = nil
            end,
            applyPos = function()
                -- Delegate to the tier-aware authority (base top-left + per-tier
                -- offset) so any framework apply matches _ApplyTierOffset instead
                -- of the old re-anchor-at-unlockPos.point scheme, which used the
                -- current tier's container size and mispositioned non-20 sizes.
                if ns._ApplyTierOffset then ns._ApplyTierOffset() end
            end,
        }),
        EllesmereUI.MakeUnlockElement({
            key   = "RF_PartyFrames",
            label = "Party Frames",
            group = "Raid Frames",
            order = 501,
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
                -- Element-anchored: the anchor system owns the position. Only
                -- apply the saved pos as a bootstrap while the frame has no
                -- resolved geometry yet (anchor pass corrects it after).
                if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("RF_PartyFrames")
                   and ns._partyContainerFrame and ns._partyContainerFrame:GetLeft() then
                    return
                end
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
-- Raid-preview state for the Targeted Spells module (previewActive /
-- previewFrames are file-locals; the closure tracks the live values)
ns._TSRaidPvState = function() return previewActive, previewFrames end
-- Party preview reads party-scaled / party-prefixed settings so aura icons match
-- the party frames (size, position, colors); raid preview reads the live profile
-- through the real-preview effective overlay (below) so an open panel's view
-- swap never leaks into the preview.
local function PvSettings()
    return (ns._partyPvActive and ns._scaledPartyProxy)
        or ns._pvOverlayProxy or db.profile
end
-- Class tokens for icon selection: the async ticker runs outside the synchronous
-- table swap in ApplyPartyPreviewData, so it must resolve party tokens itself.
local function PvClassTokens()
    return (ns._partyPvActive and ns._partyPvCT) or previewClassTokens
end

-------------------------------------------------------------------------------
--  Real-preview effective-value overlay
--  While the options panel holds a value-swapped VIEW (Default Editing Mode
--  or an editing-as session) and preview mode is "real", preview reads must
--  resolve the CURRENT SPEC's panel-closed effective values (spec override,
--  else the applied conditional, else defaults) -- never the view's swapped
--  live values. The overlay is a read-through proxy: captured RF keys
--  resolve from the override stores, everything else falls through to live
--  db.profile, so options widgets (which read live directly) keep showing
--  the view. Rebuilt event-driven at the preview refresh entry points and
--  the module-refresh tail; nil whenever no view swap is active, making
--  every read byte-identical to today outside editing views. ZERO writes
--  to live stores or override stores. (ns fields + do-end locals only:
--  this file sits at Lua 5.1's 200-local cap.)
-------------------------------------------------------------------------------
do
    local proxy
    local proxyMT = {
        __index = function(_, key)
            local ov = ns._pvOverlay
            if ov ~= nil then
                local v = ov[key]
                if v ~= nil then
                    if v == EllesmereUI.SPECOV_NIL then return nil end
                    return v
                end
            end
            return db.profile[key]
        end,
    }
    -- Segment-key resolution mirrors the value system's live walk: prefer
    -- the string key when the table holds it, else numeric.
    local function SegKey(t, seg)
        if t[seg] ~= nil then return seg end
        local n = tonumber(seg)
        if n ~= nil and t[n] ~= nil then return n end
        return seg
    end

    function ns._RebuildPvOverlay()
        local active = (db.profile.previewMode == "real")
            and EllesmereUI.SpecOverrides_ViewActive
            and EllesmereUI.SpecOverrides_ViewActive()
            and EllesmereUI.SpecOverrides_PeekEffectiveValues
        local flat, specSrc, condSrc
        if active then
            flat, specSrc, condSrc =
                EllesmereUI.SpecOverrides_PeekEffectiveValues("EllesmereUIRaidFrames")
        end
        if not flat then
            ns._pvOverlay = nil
            ns._pvOverlayProxy = nil
            ns._pvOverlaySrc = nil
            if ns._UpdatePvModeChrome then ns._UpdatePvModeChrome() end
            return
        end
        local NIL_SENT = EllesmereUI.SPECOV_NIL
        local overlay = {}
        for fkey, v in pairs(flat) do
            local path = fkey:match("^[^\31]+\31(.*)$")
            if path and path ~= "" then
                local segs = { strsplit("\30", path) }
                if #segs == 1 then
                    -- Depth-1: NIL_SENT stays encoded; the proxy decodes it.
                    overlay[SegKey(db.profile, segs[1])] = v
                else
                    -- Deeper path: shallow-clone the LIVE parent chain along
                    -- the path once, then set (or remove) the leaf -- sibling
                    -- keys inside the cloned subtable keep their live values.
                    local liveT = db.profile
                    local dstParent = overlay
                    local ok = true
                    for i = 1, #segs - 1 do
                        local k = SegKey(liveT, segs[i])
                        local liveChild = liveT[k]
                        if type(liveChild) ~= "table" then ok = false; break end
                        local dstChild = dstParent[k]
                        if type(dstChild) ~= "table" then
                            dstChild = {}
                            for ck, cv in pairs(liveChild) do dstChild[ck] = cv end
                            dstParent[k] = dstChild
                        end
                        dstParent = dstChild
                        liveT = liveChild
                    end
                    if ok then
                        local lk = SegKey(liveT, segs[#segs])
                        if v == NIL_SENT then
                            dstParent[lk] = nil
                        else
                            dstParent[lk] = v
                        end
                    end
                end
            end
        end
        ns._pvOverlay = overlay
        if not proxy then proxy = setmetatable({}, proxyMT) end
        ns._pvOverlayProxy = proxy
        ns._pvOverlaySrc = { spec = specSrc, cond = condSrc }
        if ns._UpdatePvModeChrome then ns._UpdatePvModeChrome() end
    end

    -- The preview-path settings accessor: overlay proxy while a view swap
    -- is active in real preview mode, else the live profile itself.
    function ns.PvEffectiveProfile()
        return ns._pvOverlayProxy or db.profile
    end

    -- Session unlock-layer element lookup: while an override session with a
    -- CUSTOM unlock mode is being edited in real preview mode, the preview
    -- mirrors that session's unlock positions -- the layer's recorded elem
    -- for the key, baseline fallback per element. nil in every other state
    -- (live positioning, today's behavior). Anchored containers resolve to
    -- their recorded bookkeeping coordinates, not a live anchor chain.
    function ns._PvSessionElem(key)
        if db.profile.previewMode ~= "real" then return nil end
        local layer, base
        local sfn = EllesmereUI.SpecOverrides_EditSessionUnlockLayer
        if sfn then layer, base = sfn() end
        if not layer then
            -- Default view: mirror the REAL spec's RESOLVED effective fork.
            -- Never the live pointer (s.active) -- it lags membership and
            -- unlock-mode edits made while the panel is open, and the
            -- preview must show the layer that WOULD apply on exit.
            -- Baseline-effective specs return nil here -> live positioning,
            -- byte-identical to before the feature.
            local vfn = EllesmereUI.SpecOverrides_ViewActive
            if vfn and vfn() and EllesmereUI.SpecOverrides_EffectiveUnlockLayer then
                layer, base = EllesmereUI.SpecOverrides_EffectiveUnlockLayer()
            end
        end
        if not layer then return nil end
        local e = layer.elems and layer.elems[key]
        if not e and base and base ~= layer then
            e = base.elems and base.elems[key]
        end
        return e
    end
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
	
    -- Debuffs use the shared grid layout (same DebuffGridPoint helper as the live
    -- frames) so the preview matches exactly -- including row wrapping and CENTER
    -- per-row centering. `slot` is the 0-based index among visible icons.
    if auraType ~= "def" and auraType ~= "pa" then
        local sz = s2.debuffSize or 18
        icon:SetSize(sz, sz)
        icon:ClearAllPoints()
        local corner, fx, fy = ns.DebuffGridPoint(s2, slot, totalShown)
        icon:SetPoint(corner, ns.RF_AnchorHost(f._health, s2), corner, fx, fy)
        return
    end

    -- Defensives / private auras: single-line relative chaining (no wrapping).
    local pos, ox, oy, grow, sz, spc
    if auraType == "def" then
        pos = s2.defPosition or "center"
        ox = s2.defOffsetX or 0
        oy = s2.defOffsetY or 0
        grow = s2.defGrowDirection or "CENTER"
        sz = s2.defSize or 22
        spc = PixelSnap(s2.defSpacing or 1)
    else -- pa
        pos = s2.paPosition or "bottomleft"
        ox = s2.paOffsetX or 0
        oy = s2.paOffsetY or 0
        grow = s2.paGrowDirection or "RIGHT"
        sz = s2.paSize or 18
        spc = PixelSnap(s2.paSpacing or 1)
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
        local pvHost = ns.RF_AnchorHost(f._health, s2)
        if pos == "topleft" then icon:SetPoint("TOPLEFT", pvHost, "TOPLEFT", fx, oy)
        elseif pos == "top" then icon:SetPoint("TOP", pvHost, "TOP", fx, oy)
        elseif pos == "topright" then icon:SetPoint("TOPRIGHT", pvHost, "TOPRIGHT", fx, oy)
        elseif pos == "left" then icon:SetPoint("LEFT", pvHost, "LEFT", fx, oy)
        elseif pos == "center" then icon:SetPoint("CENTER", pvHost, "CENTER", fx, oy)
        elseif pos == "right" then icon:SetPoint("RIGHT", pvHost, "RIGHT", fx, oy)
        elseif pos == "bottomright" then icon:SetPoint("BOTTOMRIGHT", pvHost, "BOTTOMRIGHT", fx, oy)
        elseif pos == "bottom" then icon:SetPoint("BOTTOM", pvHost, "BOTTOM", fx, oy)
        else icon:SetPoint("BOTTOMLEFT", pvHost, "BOTTOMLEFT", fx, oy)
        end
    else
        -- Chain from previous icon in same pool
        local pool = (auraType == "def") and f._pvDefs or f._pvPA
        local prev = pool[slot] -- slot is 0-based; current is slot+1, prev is pool[slot]
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
    -- Private auras keep the fixed crop: live PA icons are Blizzard-rendered
    -- and can't be zoomed, so the preview must not suggest otherwise.
    if auraType == "db" then
        local _z = s2.debuffIconZoom or 0.08
        icon._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)
    elseif auraType == "def" then
        local _z = s2.defIconZoom or 0.08
        icon._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)
    end
    if icon._cooldown then
        local showSwipe, showDurText, dtColor, dtSize, dtOX, dtOY
        if auraType == "pa" then
            -- Private auras: swipe always on, text controlled by paShowCountdown.
            -- Real frames now scale the slot frame by (paSize / 32) so Blizzard's
            -- countdown text tracks the icon size. The preview can't use Blizzard
            -- rendering, so mirror that proportionality: size the fake timer font
            -- to the same fraction of the icon (~0.44, calibrated so the default
            -- icon size keeps the prior ~8px look). Keeps preview and live frames
            -- visually matched as paSize changes. Centered, like Blizzard's text.
            showSwipe = true
            showDurText = s2.paShowCountdown ~= false
            dtColor = { r = 1, g = 1, b = 1 }
            local paSz = s2.paSize or 18
            dtSize = math.max(1, math.floor(paSz * 8 / 18 + 0.5))
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
                local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
                EllesmereUI.ApplyIconTextFont(cdText, fontPath, dtSize, "raidFrames")
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
            -- Pulse expired: hide slot 1 on all frames. While wrapping is on,
            -- skip the player frame (index 1) -- it's a dedicated full showcase
            -- (filled below) so its slots stay put instead of pulsing.
            local pf = PvFrames()
            for fi = (((s2.debuffPerRow or 1) > 1) and 2 or 1), #pf do
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
            -- Apply 10s debuff to all frames (skip the player showcase frame 1
            -- while wrapping is on; it owns its own debuff slots, filled below).
            local dur = 10
            local pf = PvFrames()
            for fi = (((s2.debuffPerRow or 1) > 1) and 2 or 1), #pf do
                local key = fi .. ":db:1"
                local f = pf[fi]
                if f and f._pvDebuffs and f._pvDebuffs[1] and f._health then
                    local icon = f._pvDebuffs[1]
                    icon._tex:SetTexture(5927657)
                    local _z = s2.debuffIconZoom or 0.08
                    icon._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)
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
                                local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
                                EllesmereUI.ApplyIconTextFont(cdText, fp, s2.debuffDurTextSize or 8, "raidFrames")
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
		
        -- Row-wrap showcase: when wrapping is enabled, fill the player frame
        -- (index 1) up to debuffCap so the full multi-row layout is actually
        -- visible -- the ambient pulse/random spawns only put 1-2 per frame,
        -- which can't demonstrate wrapping. Slots 2+ loop on their own (see the
        -- expiry pass); slot 1 is re-topped here since the pulse skips frame 1.
        if (s2.debuffPerRow or 1) > 1 then
            local cap = s2.debuffCap or 3
            local f1 = PvFrames()[1]
            if f1 and f1._pvDebuffs then
                local changed = false
                for slot = 1, cap do
                    if f1._pvDebuffs[slot] then
                        local key = "1:db:" .. slot
                        local info = ns._pvActiveAuras[key]
                        if not (info and info.expTime > now) then
                            PvAuraApply(1, "db", slot)
                            changed = true
                        end
                    end
                end
                if changed then PvAuraReanchorFrame(1, "db") end
            end
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
                        local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
                        EllesmereUI.ApplyIconTextFont(ic._count, fp, s2.debuffStacksTextSize or 8, "raidFrames")
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
    -- "None" position disables private auras entirely, so the preview hides them
    -- too (read from the same settings source the pa anchor renderer uses).
    local wantPA = ns._privateAurasPreviewVisible
        and (PvSettings().paPosition or "center") ~= "none"
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
    -- Untracked spec: preview only the class-fallback indicators flagged
    -- Show Own on All Specs (the ones that actually render live there).
    local flaggedOnly = false
    if not specKey then
        specKey = ns.BM_ClassFallbackSpecKey and ns.BM_ClassFallbackSpecKey()
        flaggedOnly = true
    end
    if not specKey then return {} end
    local indicators = db.profile.bmIndicators[specKey]
    if not indicators then return {} end
    local spells = {}
    local seen = {}
    for _, ind in ipairs(indicators) do
        if ind.enabled and ind.spells and (not flaggedOnly or ind.showOwnAllSpecs)
           and (ind.type == "icon" or ind.type == "square") then
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
                        color = (ind.spellColors and ind.spellColors[sid]) or ind.color,
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
        icon:SetPoint(pos, ns.RF_AnchorHost(f._health, PvSettings()), pos, ox, oy)
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
    local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"

    local dbZ = s2.debuffIconZoom or 0.08
    local defZ = s2.defIconZoom or 0.08
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
                    ic._tex:SetTexCoord(dbZ, 1 - dbZ, dbZ, 1 - dbZ)
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
                                EllesmereUI.ApplyIconTextFont(cdText, fp, dbDtSz, "raidFrames")
                                cdText:SetTextColor(dbDtC.r, dbDtC.g, dbDtC.b)
                                cdText:ClearAllPoints()
                                cdText:SetPoint("CENTER", ic, "CENTER", dbDtOX, dbDtOY)
                            end
                        end
                    end
                    if ic._count and ic._count:GetText() ~= "" then
                        EllesmereUI.ApplyIconTextFont(ic._count, fp, sSz, "raidFrames")
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
                    ic._tex:SetTexCoord(defZ, 1 - defZ, defZ, 1 - defZ)
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
                                EllesmereUI.ApplyIconTextFont(cdText, fp, defDtSz, "raidFrames")
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
    f:SetFrameStrata("HIGH")
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

    -- Full-height anchor reference (mirrors the live buttons' d.uniformRef so
    -- Uniform Icon Anchoring previews identically; see ns.RF_AnchorHost).
    f._uniformRef = CreateFrame("Frame", nil, f)
    f._uniformRef:SetFrameLevel(health:GetFrameLevel())
    f._uniformRef:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    f._uniformRef:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    health._euiUniformRef = f._uniformRef
    f._uniformRef._euiHealth = health

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
    -- Modern compound absorb base (preview): mirrors the live frame's solid c6c8ff
    -- base drawn under the striped fill. Anchored to the fill at render time.
    local bfBase = backfillBar:CreateTexture(nil, "ARTWORK", nil, 0)
    bfBase:SetColorTexture(0.776, 0.784, 1.0, 1)
    if absorbMask then bfBase:AddMaskTexture(absorbMask) end
    bfBase:Hide()
    backfillBar._modernBase = bfBase
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
    -- Modern compound absorb base (preview) for the forward bar.
    local fwBase = forwardBar:CreateTexture(nil, "ARTWORK", nil, 0)
    fwBase:SetColorTexture(0.776, 0.784, 1.0, 1)
    if absorbMask then fwBase:AddMaskTexture(absorbMask) end
    fwBase:Hide()
    forwardBar._modernBase = fwBase
    forwardBar:SetStatusBarColor(1, 1, 1, 0.3)
    forwardBar:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    forwardBar:SetPoint("BOTTOMLEFT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    forwardBar:SetWidth(health:GetWidth())
    forwardBar:SetHeight(health:GetHeight())
    -- Match backfill: absorb above heal absorb/heal pred and max health.
    forwardBar:SetFrameLevel(health:GetFrameLevel() + 3)
    forwardBar:SetMinMaxValues(0, 100)
    forwardBar:Hide()

    -- "Default Blizz Frames" spark (preview): mirrors live -- a fixed 16px cast_spark
    -- glow on a non-clipping host above the shield, CENTER pinned to the forward bar's
    -- LEFT edge (the seam). Gated by the preview's plain absorb compare in the renderer.
    local sparkHost = CreateFrame("Frame", nil, health)
    sparkHost:SetAllPoints(health)
    sparkHost:SetClipsChildren(true)
    sparkHost:SetFrameLevel(health:GetFrameLevel() + 4)
    local gateBar = CreateFrame("StatusBar", nil, sparkHost)
    gateBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    gateBar:SetStatusBarColor(1, 1, 1, 0)
    gateBar:SetSize(16, health:GetHeight())
    gateBar:SetMinMaxValues(0, 1)
    gateBar:SetValue(0)
    gateBar:SetPoint("CENTER", forwardBar, "LEFT", -1, 0)
    local edgeSpark = sparkHost:CreateTexture(nil, "OVERLAY")
    edgeSpark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    edgeSpark:SetBlendMode("ADD")
    edgeSpark:SetAllPoints(gateBar:GetStatusBarTexture())
    edgeSpark:Hide()
    forwardBar._edgeSpark = edgeSpark
    forwardBar._edgeGate = gateBar
    -- Overshield spark (preview): rides the backfill's left edge while overshielding.
    local bfSpark = sparkHost:CreateTexture(nil, "OVERLAY")
    bfSpark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    bfSpark:SetBlendMode("ADD")
    bfSpark:SetSize(16, health:GetHeight())
    bfSpark:SetPoint("CENTER", forwardBar, "LEFT", -1, 0)
    bfSpark:Hide()
    forwardBar._bfSpark = bfSpark

    -- Heal absorb bar (preview): red overlay eating into filled health from HP edge
    do
        -- Own clip frame (mirrors live): right/left span the full bar, overlay
        -- clips to filled health. Bounds set per healAbsorbEdgeMode in render.
        local healClip = CreateFrame("Frame", nil, health)
        healClip:SetClipsChildren(true)
        healClip:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        healClip:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        f._healClip = healClip
        local ha = CreateFrame("StatusBar", nil, healClip)
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
        -- Black backing behind the heal-absorb texture (preview; mirrors live).
        local haBg = ha:CreateTexture(nil, "ARTWORK", nil, 1)
        haBg:SetColorTexture(0, 0, 0, 0.25)
        if absorbMask then haBg:AddMaskTexture(absorbMask) end
        haBg:Hide()
        ha._bg = haBg
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
        f._reducedMaxHealthBg = rmhBg
    end

    -- Store absorb references on preview frame
    local absorbBar = backfillBar
    absorbBar._forward = forwardBar
    absorbBar._mask = absorbMask
    absorbBar._curClip = curClip
    absorbBar._missClip = missClip

    -- Absorb Bar (preview): solid bar above the frame, fills from the right
    do
        local tb = CreateFrame("StatusBar", nil, f)
        tb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        tb:SetStatusBarColor(1, 1, 1, 1)
        tb:SetReverseFill(true)
        tb:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0)
        tb:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 0)
        tb:SetHeight(4)
        tb:SetFrameLevel(health:GetFrameLevel() + 3)
        tb:SetMinMaxValues(0, 100)
        tb:Hide()
        absorbBar._topBar = tb
    end

    -- Heal Absorb Bar (preview): mirrors the Absorb Bar strip above.
    do
        local thb = CreateFrame("StatusBar", nil, f)
        thb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        thb:SetStatusBarColor(200/255, 29/255, 29/255, 1)
        thb:SetReverseFill(true)
        thb:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0)
        thb:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 0)
        thb:SetHeight(4)
        thb:SetFrameLevel(health:GetFrameLevel() + 3)
        thb:SetMinMaxValues(0, 100)
        thb:Hide()
        absorbBar._healTopBar = thb
    end

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
        -- Overlay ahead of _scaledProfile: border/hover/target keys are not
        -- tier-scaled, so the effective overlay may shadow them safely.
        local s = ns._previewSettingsOverride or (ns._partyPvActive and ns._scaledPartyProxy)
            or ns._pvOverlayProxy or ns._scaledProfile
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
    dispelIconFrame:SetSize(16, 16)
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

    -- Ready check icon (position/size re-applied in the preview indicator pass)
    local readyCheck = markerCarrier:CreateTexture(nil, "OVERLAY")
    readyCheck:SetSize(PixelSnap(s.readyCheckSize or 20), PixelSnap(s.readyCheckSize or 20))
    readyCheck:SetPoint("CENTER", health, "CENTER", 0, 0)
    readyCheck:Hide()

    -- Combat icon (position/size/style re-applied in the preview indicator pass)
    local combatIcon = markerCarrier:CreateTexture(nil, "OVERLAY", nil, 1)
    combatIcon:SetSize(PixelSnap(s.combatIndicatorSize or 16), PixelSnap(s.combatIndicatorSize or 16))
    combatIcon:Hide()

    -- Text carrier: text band (above every border incl. the raise, below auras).
    local textCarrier = CreateFrame("Frame", nil, f)
    textCarrier:SetAllPoints(health)
    textCarrier:SetFrameLevel(f:GetFrameLevel() + ns.LVL_TEXT)

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

    -- Heal absorb text (preview)
    local healAbsorbFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(healAbsorbFS, s.healAbsorbTextSize or 9)
    healAbsorbFS:SetWordWrap(false)
    healAbsorbFS:SetJustifyH("CENTER")
    healAbsorbFS:SetPoint("CENTER", health, "CENTER", 0, 0)

    -- Status text (DEAD / OFFLINE / AFK)
    local statusFS = textCarrier:CreateFontString(nil, "OVERLAY")
    local pvStc = s.statusTextColor or { r = 1, g = 1, b = 1 }
    ApplyFont(statusFS, s.statusTextSize or 14)
    statusFS:SetJustifyH("CENTER")
    statusFS:SetTextColor(pvStc.r, pvStc.g, pvStc.b)
    statusFS:Hide()

    -- Role icon. Carrier sits just BELOW the aura band and above the base border
    -- (mirrors the real frames): clears the general border while auras draw over
    -- it; the hover/target border raise intentionally covers it.
    local roleCarrier = CreateFrame("Frame", nil, f)
    roleCarrier:SetAllPoints(health)
    roleCarrier:SetFrameLevel(f:GetFrameLevel() + (ns.LVL_AURA - 1))
    local roleIcon = roleCarrier:CreateTexture(nil, "OVERLAY")
    local riSz = PixelSnap(s.roleIconSize or 14)
    roleIcon:SetSize(riSz, riSz)

    -- Leader icon: on the text carrier band (above the general border, below the
    -- aura layer) to mirror the real frames -- the hover/target raise covers it,
    -- the general border does not.
    local leaderIcon = textCarrier:CreateTexture(nil, "OVERLAY")
    local liSz = PixelSnap(s.leaderIconSize or 14)
    leaderIcon:SetSize(liSz, liSz)
    local liPos = (s.leaderIconPosition or "top"):upper()
    leaderIcon:SetPoint(liPos, ns.RF_AnchorHost(health, s), liPos, s.leaderIconOffsetX or 0, s.leaderIconOffsetY or 0)
    leaderIcon:Hide()

    -- Top Name Bar (preview; sized/styled by ApplyPreviewData)
    local tnb = CreateFrame("Frame", nil, f)
    tnb:SetFrameLevel(f:GetFrameLevel() + 4)
    tnb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    tnb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    tnb:SetHeight(PixelSnap(s.topNameBarHeight or 20))
    local tnbBg = tnb:CreateTexture(nil, "BACKGROUND")
    tnbBg:SetAllPoints()
    if PP then PP.DisablePixelSnap(tnbBg) end
    local tnbText = tnb:CreateFontString(nil, "OVERLAY")
    ApplyFont(tnbText, s.topNameBarTextSize or 11)
    tnbText:SetWordWrap(false)
    tnb:Hide()

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
    f._topNameBar = tnb
    f._topNameBarBg = tnbBg
    f._topNameBarText = tnbText
    f._healthText = healthFS
    f._healAbsorbText = healAbsorbFS
    f._statusText = statusFS
    f._roleIcon = roleIcon
    f._leaderIcon = leaderIcon
    f._combatIcon = combatIcon

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
        local fpInit = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        local countFS = countCarrier:CreateFontString(nil, "OVERLAY")
        countFS:SetPoint("BOTTOMRIGHT", di, "BOTTOMRIGHT", 1, -1)
        EllesmereUI.ApplyIconTextFont(countFS, fpInit, 8, "raidFrames")
        countFS:SetTextColor(1, 1, 1)
        countFS:SetText("")
        di._count = countFS
        -- Duration text (on same carrier above cooldown swipe)
        local durFS = countCarrier:CreateFontString(nil, "OVERLAY")
        durFS:SetPoint("CENTER", di, "CENTER", 0, 0)
        EllesmereUI.ApplyIconTextFont(durFS, fpInit, 8, "raidFrames")
        durFS:SetTextColor(1, 1, 1)
        durFS:Hide()
        di._durText = durFS
        return di
    end

    -- Debuff preview icons. Pool sized to the max debuffCap (8) so the player
    -- frame can showcase a full wrapping layout; only a few are shown otherwise.
    f._pvDebuffs = {}
    for i = 1, 8 do
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

        -- Dead/offline/rez: one of each, random non-player slots. Two of them are
        -- corpses -- a plain dead body and a separate one that's being resurrected --
        -- so the showcase shows both states side by side.
        local statePool = {}
        for i = 2, 20 do statePool[#statePool + 1] = i end
        for i = #statePool, 2, -1 do
            local j = math.random(i)
            statePool[i], statePool[j] = statePool[j], statePool[i]
        end
        previewRoles._deadSlot    = statePool[1]  -- plain corpse
        previewRoles._offlineSlot = statePool[2]
        previewRoles._rezSlot     = statePool[3]  -- corpse with an incoming-rez icon
        -- Plain dead + offline bodies carry no readycheck/summon icon (looks wrong there).
        if rcStatuses[statePool[1]] then rcStatuses[statePool[1]] = nil end
        if rcStatuses[statePool[2]] then rcStatuses[statePool[2]] = nil end
        -- The rez corpse gets the incoming-rez icon. But markers win the shared icon
        -- slot (same as the readycheck de-confliction above): if the rez slot landed
        -- on a marker slot, skip the icon (the frame is still shown as a dead body).
        if statePool[3] ~= ms1 and statePool[3] ~= ms2 then
            rcStatuses[statePool[3]] = "rez"
        else
            rcStatuses[statePool[3]] = nil
        end
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
    -- The real-preview effective overlay (when active) resolves captured keys
    -- to their panel-closed values; it is NOT tier-scaled, so the base-width
    -- contract above holds.
    local s = ns._previewSettingsOverride or ns._pvOverlayProxy or db.profile
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
    local topBarH = (s.topNameBarEnabled and PixelSnap(s.topNameBarHeight or 20)) or 0

    f:SetSize(w, h)

    -- Health bar height/anchor + Top Name Bar (helper re-anchors health top to
    -- -topBarH; the per-unit power block below re-sets only the height)
    LayoutTopNameBar(s, h, powerH, f._health, f._topNameBar, f._topNameBarBg, f._topNameBarText)

    -- Health bar
    if f._health then
        f._health:SetStatusBarTexture(ResolveHealthTexture())
        f._health:GetStatusBarTexture():SetHorizTile(false)
        f._health:SetMinMaxValues(0, 100)
        f._health:SetValue(healthPct)
        f._healthPct = healthPct
        f._classToken = classToken

        local mode = s.healthColorMode or "class"
        local fillTex = f._health:GetStatusBarTexture()
        if mode == "dark" then
            local dfr, dfg, dfb, dfa = EllesmereUI.GetDarkModeFill()
            f._health:SetStatusBarColor(dfr, dfg, dfb, 1)
            if fillTex then fillTex:SetAlpha(dfa) end
        elseif mode == "classic" then
            if fillTex then fillTex:SetAlpha(1) end
            local pct = healthPct / 100
            local r = pct < 0.5 and 1 or (1 - (pct - 0.5) * 2)
            local g = pct > 0.5 and 1 or (pct * 2)
            f._health:SetStatusBarColor(r, g, 0, (s.healthBarOpacity or 100) / 100)
        elseif mode == "customDynamic" then
            if fillTex then fillTex:SetAlpha(1) end
            local r, g, b = ns.ResolveDynamicColor(s, healthPct / 100)
            f._health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
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

    -- Top Name Bar text (preview unit name + class/custom color)
    if f._topNameBarText and s.topNameBarEnabled then
        f._topNameBarText:SetText(name)
        if (s.topNameBarTextColorMode or "class") == "custom" then
            local c = s.topNameBarTextColor or { r = 1, g = 1, b = 1 }
            f._topNameBarText:SetTextColor(c.r, c.g, c.b)
        else
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then f._topNameBarText:SetTextColor(cc.r, cc.g, cc.b)
            else f._topNameBarText:SetTextColor(1, 1, 1) end
        end
    end

    -- Background
    if f._bg then
        if s.healthColorMode == "dark" then
            f._bg:ClearAllPoints()
            f._bg:SetPoint("TOPLEFT", f._health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
            f._bg:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
            f._bg:SetColorTexture(EllesmereUI.GetDarkModeBg())
        else
            -- BG covers the missing-health portion only (never behind the fill),
            -- matching the real-frame themed branch + Dark mode. Keeps the preview
            -- a 1:1 replica for reduced-fill-opacity setups.
            f._bg:ClearAllPoints()
            f._bg:SetPoint("TOPLEFT", f._health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
            f._bg:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
            local bgA = (s.bgDarkness or 50) / 100
            local cc = s.bgClassColored and classToken and EllesmereUI.GetClassColor(classToken)
            if cc then
                f._bg:SetColorTexture(cc.r, cc.g, cc.b, bgA)
            else
                local bgc = s.customBgColor
                f._bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bgA)
            end
        end
    end

    -- Absorb shield preview (dual clip-frame: backfill + forward)
    if f._absorbBar then
        local absStyle = s.absorbStyle or "none"
        if ns._indicatorsVisible then absStyle = "none"
        elseif ns._testMode then
            if ns._testAbsorbs == false then absStyle = "none"
            elseif ns._testAbsorbs and absStyle == "none" then absStyle = "striped" end
        elseif not ns._absorbsPreviewVisible then absStyle = "none"
        end
        local absorbAmt = ns.previewAbsorbValues[index] or 0
        local fw = f._absorbBar._forward
        -- Absorb Bar (solid bar above the frame): same preview gating as the
        -- shield styles (indicators / test mode / absorbs eyeball).
        local topBar = f._absorbBar._topBar
        if topBar then
            local barPos = ns.GetAbsorbBarPosition(s)
            local barOn = barPos ~= "none"
            if ns._indicatorsVisible then barOn = false
            elseif ns._testMode then
                if ns._testAbsorbs == false then barOn = false end
            elseif not ns._absorbsPreviewVisible then barOn = false
            end
            if barOn and absorbAmt > 0 then
                local bc = s.absorbBarColor or { r = 1, g = 1, b = 1 }
                ns.ApplyStripBarLayout(topBar, f._absorbBar, f, barPos, s.absorbBarHeight or 4, nil, nil, s.absorbBarGrowDir or "up")
                topBar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a or 1)
                topBar:SetValue(absorbAmt)
                topBar:Show()
            else
                topBar:Hide()
            end
        end
        -- Heal Absorb Bar preview (mirrors the Absorb Bar; gated on the heal
        -- absorb preview toggles).
        do
            local healTopBarPv = f._absorbBar._healTopBar
            if healTopBarPv then
                local healBarPos = ns.GetHealAbsorbBarPosition(s)
                local healBarOn = healBarPos ~= "none"
                if ns._indicatorsVisible then healBarOn = false
                elseif ns._testMode then
                    if ns._testHealAbsorbs == false then healBarOn = false end
                elseif not ns._absorbsPreviewVisible then healBarOn = false
                end
                local haAmtPv = ns.previewHealAbsorbValues[index] or 0
                if healBarOn and haAmtPv > 0 then
                    local hbc = s.healAbsorbBarColor or { r = 200/255, g = 29/255, b = 29/255 }
                    ns.ApplyStripBarLayout(healTopBarPv, f._absorbBar, f, healBarPos, s.healAbsorbBarHeight or 4, ns.GetAbsorbBarPosition(s), s.absorbBarHeight or 4, s.healAbsorbBarGrowDir or "up")
                    healTopBarPv:SetStatusBarColor(hbc.r, hbc.g, hbc.b, hbc.a or 1)
                    healTopBarPv:SetValue(haAmtPv)
                    healTopBarPv:Show()
                else
                    healTopBarPv:Hide()
                end
            end
        end
        if absStyle ~= "none" and absorbAmt > 0 then
            local modern = (absStyle == "blizzardModern")
            local tex = ns.ResolveAbsorbStyleTex(absStyle, "Interface\\Buttons\\WHITE8X8")
            local alpha = (s.absorbOpacity or 90) / 100
            local tiled = (absStyle == "striped" or absStyle == "stripedReversed" or absStyle == "largeStripes" or absStyle == "largeStripesR" or absStyle == "largeOutlinedStripes" or absStyle == "largeOutlinedStripesR")
            local hpW = w
            local hpH = healthH
            local mask = f._absorbBar._mask
            local ac = s.absorbColor or { r = 1, g = 1, b = 1 }

            f._absorbBar:SetWidth(hpW)
            f._absorbBar:SetHeight(hpH)
            if fw then fw:SetWidth(hpW); fw:SetHeight(hpH) end

            if modern then
                -- Forward = modern texture; backfill = flat 10% white overshield (mirrors live).
                if fw then ns.ApplyModernAbsorbBar(fw, mask) end
                ns.HideModernAbsorbBase(f._absorbBar)
                f._absorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                f._absorbBar:SetStatusBarColor(1, 1, 1, 0.10)
                local bfFill = f._absorbBar:GetStatusBarTexture()
                if bfFill then
                    bfFill:SetDrawLayer("ARTWORK", 1)
                    bfFill:SetHorizTile(false); bfFill:SetVertTile(false)
                    if mask then bfFill:AddMaskTexture(mask) end
                end
            else
                ns.HideModernAbsorbBase(f._absorbBar)
                if fw then ns.HideModernAbsorbBase(fw) end

                -- Apply style to backfill bar
                f._absorbBar:SetStatusBarTexture(tex)
                f._absorbBar:SetStatusBarColor(ac.r, ac.g, ac.b, alpha)
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
                    local fwFill = fw:GetStatusBarTexture()
                    if fwFill then
                        fwFill:SetDrawLayer("ARTWORK", 1)
                        fwFill:SetHorizTile(tiled)
                        fwFill:SetVertTile(tiled)
                        if mask then fwFill:AddMaskTexture(mask) end
                    end
                end
            end

            -- Feed both bars with the same absorb value; clip frames do the visual math.
            -- Mirror the live Show Overshield gate: when off (overlay-like modes) feed
            -- the backfill 0 so the overshield does not render in the preview.
            local pvOvershieldOn = s.showOvershield ~= false
            local pvOverlayLike = modern or (s.absorbEdgeMode or "overlay") == "overlay"
            local pvAbValue = (not pvOvershieldOn and pvOverlayLike) and 0 or absorbAmt
            f._absorbBar:SetMinMaxValues(0, 100)
            f._absorbBar:SetValue(pvAbValue)
            f._absorbBar:Show()
            if fw then
                fw:SetMinMaxValues(0, 100)
                fw:SetValue(absorbAmt)
                fw:Show()
            end

            -- "Default Blizz Frames": seam spark + overshield spark (preview values are
            -- plain numbers, so overshield is a normal compare instead of isClamped).
            if modern then
                if fw then
                    local fmb = fw._modernBase
                    if fmb then fmb:SetAllPoints(fw:GetStatusBarTexture()) end
                    local previewOver = absorbAmt > (100 - (healthPct or 100))
                    local g, sp = fw._edgeGate, fw._edgeSpark
                    if g and sp then
                        g:SetHeight(hpH)
                        g:SetValue(absorbAmt)
                        sp:SetAllPoints(g:GetStatusBarTexture())
                        sp:SetAlpha(previewOver and 0 or 1)
                        sp:Show()
                    end
                    local bsp = fw._bfSpark
                    if bsp then
                        bsp:SetSize(16, hpH)
                        bsp:ClearAllPoints()
                        if pvOvershieldOn then
                            bsp:SetPoint("CENTER", f._absorbBar:GetStatusBarTexture(), "LEFT", -1, 0)
                        else
                            bsp:SetPoint("CENTER", f._absorbBar, "RIGHT", -1, 0)
                        end
                        bsp:SetAlpha(previewOver and 1 or 0)
                        bsp:Show()
                    end
                end
            elseif fw and fw._edgeSpark then
                fw._edgeSpark:Hide()
                if fw._bfSpark then fw._bfSpark:Hide() end
            end
        else
            f._absorbBar:Hide()
            if fw then fw:Hide() end
            ns.HideModernAbsorbBase(f._absorbBar)
            if fw then ns.HideModernAbsorbBase(fw) end
            if fw and fw._edgeSpark then fw._edgeSpark:Hide() end
            if fw and fw._bfSpark then fw._bfSpark:Hide() end
        end
        -- Position clip frames + backfill based on shield absorb placement
        -- (mirrors the live ReanchorAbsorbToFill).
        local cc = f._absorbBar._curClip
        local mc = f._absorbBar._missClip
        if cc and mc and f._health then
            local absorbMode = s.absorbEdgeMode or "overlay"
            if absorbMode == "right" or absorbMode == "left" then
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                cc:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                f._absorbBar:ClearAllPoints()
                if absorbMode == "left" then
                    f._absorbBar:SetReverseFill(false)
                    f._absorbBar:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    f._absorbBar:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                else
                    f._absorbBar:SetReverseFill(true)
                    f._absorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    f._absorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                end
                if fw then fw:Hide() end
            else
                local fill = f._health:GetStatusBarTexture()
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                cc:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
                mc:ClearAllPoints()
                mc:SetPoint("TOPLEFT", fill, "TOPRIGHT", -1, 0)
                mc:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                -- Restore overlay backfill (right-anchored reverse fill).
                f._absorbBar:SetReverseFill(true)
                f._absorbBar:ClearAllPoints()
                f._absorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                f._absorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
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
        elseif not ns._absorbsPreviewVisible then haStyle = "none"
        end
        local haAmt = ns.previewHealAbsorbValues[index] or 0
        if haStyle ~= "none" and haAmt > 0 then
            local haTex = ns.ResolveAbsorbStyleTex(haStyle, "Interface\\Buttons\\WHITE8X8")
            local haAlpha = (s.healAbsorbOpacity or 75) / 100
            local hc = s.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
            if haStyle == "healBlizzModern" or haStyle == "largeOutlinedStripes" or haStyle == "largeOutlinedStripesR" then hc = { r = 1, g = 1, b = 1 } end
            local tiled = (haStyle == "striped" or haStyle == "stripedReversed" or haStyle == "largeStripes" or haStyle == "largeStripesR" or haStyle == "largeOutlinedStripes" or haStyle == "largeOutlinedStripesR")
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
            local hbg = f._healAbsorbBar._bg
            if hbg then
                hbg:SetColorTexture(0, 0, 0, (s.healAbsorbBgOpacity or 25) / 100)
                hbg:SetAllPoints(f._healAbsorbBar:GetStatusBarTexture())
                hbg:Show()
            end
        else
            f._healAbsorbBar:Hide()
        end
        -- Heal absorb placement (independent of shield absorb; mirrors live).
        if f._health then
            local healMode = s.healAbsorbEdgeMode or "overlay"
            if f._healClip then
                f._healClip:ClearAllPoints()
                if healMode == "right" or healMode == "left" then
                    f._healClip:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    f._healClip:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                else
                    f._healClip:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    f._healClip:SetPoint("BOTTOMRIGHT", f._health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
                end
            end
            f._healAbsorbBar:ClearAllPoints()
            if healMode == "right" then
                f._healAbsorbBar:SetReverseFill(true)
                f._healAbsorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                f._healAbsorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
            elseif healMode == "left" then
                f._healAbsorbBar:SetReverseFill(false)
                f._healAbsorbBar:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                f._healAbsorbBar:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
            else
                local fill = f._health:GetStatusBarTexture()
                f._healAbsorbBar:SetReverseFill(true)
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
        local rmhStyle = s.maxHealthStyle or "maxHealthStripes"
        -- Show in the Full Preview (Reduced Max Health test toggle) AND in the
        -- Absorbs-section preview (the shield-effects eye), mirroring Heal Absorb.
        local rmhShow = ns._testReducedMaxHealth
            or (not ns._testMode and not ns._indicatorsVisible and ns._absorbsPreviewVisible)
        if rmhShow and rmhAmt > 0 and rmhStyle ~= "none" then
            ns.ApplyMaxHealthStyle(f._reducedMaxHealthBar, rmhStyle, s)
            f._reducedMaxHealthBar:SetValue(rmhAmt)
            local rmhBg = f._reducedMaxHealthBg
            if rmhBg then
                rmhBg:SetColorTexture(0, 0, 0, (s.maxHealthBgOpacity or 100) / 100)
                rmhBg:SetAllPoints(f._reducedMaxHealthBar:GetStatusBarTexture())
            end
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

    -- Expand health to full frame when power is hidden (still reserving the Top
    -- Name Bar's height from the top; its anchor was set by LayoutTopNameBar)
    if f._health then
        if hidePower then
            f._health:SetHeight(h - topBarH)
        else
            f._health:SetHeight(healthH - topBarH)
        end
    end

    if f._powerBg then
        if hidePower then
            f._powerBg:Hide()
        else
            local bgc = EllesmereUI.GetPowerColor and s.powerBgPowerColored
                and EllesmereUI.GetPowerColor(ns._PV_CLASS_POWER[classToken] or "MANA")
            local pf = bgc and EllesmereUI.GetPowerBgDarkenFactor() or 1
            bgc = bgc or s.powerBgColor
            f._powerBg:SetColorTexture(((bgc or {}).r or 0) * pf, ((bgc or {}).g or 0) * pf, ((bgc or {}).b or 0) * pf, (s.powerBgDarkness or 70) / 100)
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
            elseif olMode == "gradient" or olMode == "gradient_sharp" then
                -- Same pre-baked gradient textures as the live frames so the preview matches.
                olTex:SetAllPoints(f._health)
                olTex:SetTexture(olMode == "gradient_sharp"
                    and "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-sharp.tga"
                    or "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-tb.tga")
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
            f._dispelIcon:ClearAllPoints()
            local diSz = s.dispelIconSize or 16
            f._dispelIcon:SetSize(diSz, diSz)
            local diPos = s.dispelIconPosition or "center"
            local diOX = s.dispelIconOffsetX or 0
            local diOY = s.dispelIconOffsetY or 0
            -- Dispel icon anchors flush to the health bar edge (no 1px inset),
            -- matching the debuff/role icon displays.
            local diHost = ns.RF_AnchorHost(f._health, s)
            if diPos == "topleft" then
                f._dispelIcon:SetPoint("TOPLEFT", diHost, "TOPLEFT", diOX, diOY)
            elseif diPos == "top" then
                f._dispelIcon:SetPoint("TOP", diHost, "TOP", diOX, diOY)
            elseif diPos == "topright" then
                f._dispelIcon:SetPoint("TOPRIGHT", diHost, "TOPRIGHT", diOX, diOY)
            elseif diPos == "left" then
                f._dispelIcon:SetPoint("LEFT", diHost, "LEFT", diOX, diOY)
            elseif diPos == "right" then
                f._dispelIcon:SetPoint("RIGHT", diHost, "RIGHT", diOX, diOY)
            elseif diPos == "bottomleft" then
                f._dispelIcon:SetPoint("BOTTOMLEFT", diHost, "BOTTOMLEFT", diOX, diOY)
            elseif diPos == "bottom" then
                f._dispelIcon:SetPoint("BOTTOM", diHost, "BOTTOM", diOX, diOY)
            elseif diPos == "bottomright" then
                f._dispelIcon:SetPoint("BOTTOMRIGHT", diHost, "BOTTOMRIGHT", diOX, diOY)
            else -- center
                f._dispelIcon:SetPoint("CENTER", diHost, "CENTER", diOX, diOY)
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
            -- When dispellable debuffs are routed to their own anchor, the
            -- preview icon follows that location, its offsets and its size.
            local dispSplit = (s.dispellableDebuffLocation or "same") ~= "same"
            local dbSz
            if dispSplit then dbSz = ns.DispellableDebuffSize(s) else dbSz = s.debuffSize or 18 end
            ddi:SetSize(dbSz, dbSz)
            ddi._tex:SetTexture(ns._PV_DISPEL_DB_ICONS[dispelType])
            local _z = s.debuffIconZoom or 0.08
            ddi._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)

            -- Position using debuff settings
            ddi:ClearAllPoints()
            local dbPos, dbOX, dbOY
            if dispSplit then
                dbPos = s.dispellableDebuffLocation
                dbOX = s.dispellableDebuffOffsetX or 0
                dbOY = s.dispellableDebuffOffsetY or 0
            else
                dbPos = s.debuffPosition or "bottomright"
                dbOX = s.debuffOffsetX or 0
                dbOY = s.debuffOffsetY or 0
            end
            local ddHost = ns.RF_AnchorHost(f._health, s)
            if dbPos == "topleft" then
                ddi:SetPoint("TOPLEFT", ddHost, "TOPLEFT", dbOX, dbOY)
            elseif dbPos == "top" then
                ddi:SetPoint("TOP", ddHost, "TOP", dbOX, dbOY)
            elseif dbPos == "topright" then
                ddi:SetPoint("TOPRIGHT", ddHost, "TOPRIGHT", dbOX, dbOY)
            elseif dbPos == "left" then
                ddi:SetPoint("LEFT", ddHost, "LEFT", dbOX, dbOY)
            elseif dbPos == "center" then
                ddi:SetPoint("CENTER", ddHost, "CENTER", dbOX, dbOY)
            elseif dbPos == "right" then
                ddi:SetPoint("RIGHT", ddHost, "RIGHT", dbOX, dbOY)
            elseif dbPos == "bottomleft" then
                ddi:SetPoint("BOTTOMLEFT", ddHost, "BOTTOMLEFT", dbOX, dbOY)
            elseif dbPos == "bottom" then
                ddi:SetPoint("BOTTOM", ddHost, "BOTTOM", dbOX, dbOY)
            else -- bottomright
                ddi:SetPoint("BOTTOMRIGHT", ddHost, "BOTTOMRIGHT", dbOX, dbOY)
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
            local rmHost = ns.RF_AnchorHost(f._health, s)
            if pos == "topleft" then
                f._raidMarker:SetPoint("TOPLEFT", rmHost, "TOPLEFT", 2 + ox, -2 + oy)
            elseif pos == "top" then
                f._raidMarker:SetPoint("TOP", rmHost, "TOP", ox, -2 + oy)
            elseif pos == "topright" then
                f._raidMarker:SetPoint("TOPRIGHT", rmHost, "TOPRIGHT", -2 + ox, -2 + oy)
            elseif pos == "left" then
                f._raidMarker:SetPoint("LEFT", rmHost, "LEFT", 2 + ox, oy)
            elseif pos == "right" then
                f._raidMarker:SetPoint("RIGHT", rmHost, "RIGHT", -2 + ox, oy)
            elseif pos == "bottomleft" then
                f._raidMarker:SetPoint("BOTTOMLEFT", rmHost, "BOTTOMLEFT", 2 + ox, 2 + oy)
            elseif pos == "bottom" then
                f._raidMarker:SetPoint("BOTTOM", rmHost, "BOTTOM", ox, 2 + oy)
            elseif pos == "bottomright" then
                f._raidMarker:SetPoint("BOTTOMRIGHT", rmHost, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            else -- center
                f._raidMarker:SetPoint("CENTER", rmHost, "CENTER", ox, oy)
            end
            f._raidMarker:Show()
        else
            f._raidMarker:Hide()
        end
    end

    -- Ready check icon
    if f._readyCheck then
        local rcStatuses = previewRoles._readyCheck
        local rcStatus = rcStatuses and rcStatuses[index]
        local isSummon = rcStatus and rcStatus:sub(1, 6) == "summon"
        local isRez    = rcStatus == "rez"
        local showRC = indVis and rcStatus and (
            (isRez and s.showIncomingRez) or
            (isSummon and s.showSummonPending) or
            (not isSummon and not isRez and s.showReadyCheck)
        )
        if showRC then
            local rcSz = PixelSnap(s.readyCheckSize or 20)
            f._readyCheck:SetSize(rcSz, rcSz)
            -- Anchor based on ready-check position setting
            f._readyCheck:ClearAllPoints()
            local pos = s.readyCheckPosition or "center"
            local ox = s.readyCheckOffsetX or 0
            local oy = s.readyCheckOffsetY or 0
            local rcHost = ns.RF_AnchorHost(f._health, s)
            if pos == "topleft" then
                f._readyCheck:SetPoint("TOPLEFT", rcHost, "TOPLEFT", 2 + ox, -2 + oy)
            elseif pos == "top" then
                f._readyCheck:SetPoint("TOP", rcHost, "TOP", ox, -2 + oy)
            elseif pos == "topright" then
                f._readyCheck:SetPoint("TOPRIGHT", rcHost, "TOPRIGHT", -2 + ox, -2 + oy)
            elseif pos == "left" then
                f._readyCheck:SetPoint("LEFT", rcHost, "LEFT", 2 + ox, oy)
            elseif pos == "right" then
                f._readyCheck:SetPoint("RIGHT", rcHost, "RIGHT", -2 + ox, oy)
            elseif pos == "bottomleft" then
                f._readyCheck:SetPoint("BOTTOMLEFT", rcHost, "BOTTOMLEFT", 2 + ox, 2 + oy)
            elseif pos == "bottom" then
                f._readyCheck:SetPoint("BOTTOM", rcHost, "BOTTOM", ox, 2 + oy)
            elseif pos == "bottomright" then
                f._readyCheck:SetPoint("BOTTOMRIGHT", rcHost, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            else -- center
                f._readyCheck:SetPoint("CENTER", rcHost, "CENTER", ox, oy)
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
            elseif rcStatus == "rez" then
                f._readyCheck:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
                f._readyCheck:SetTexCoord(0, 1, 0, 1)
            end
            f._readyCheck:Show()
        else
            f._readyCheck:Hide()
        end
    end

    -- Name (re-anchor position every refresh, single-point + width constraint)
    if f._nameText then
        -- Text band level: mirrors AnchorNameText on the live buttons ("Show
        -- Above Icons" lifts the carrier over the aura band).
        local pvCarrier = f._nameText:GetParent()
        if pvCarrier and pvCarrier.SetFrameLevel then
            pvCarrier:SetFrameLevel(f:GetFrameLevel()
                + (s.nameTextAboveIcons and (ns.LVL_AURA + 6) or ns.LVL_TEXT))
        end
        f._nameText:ClearAllPoints()
        local pos = s.namePosition or "center"
        if pos == "none" or s.topNameBarEnabled then
            f._nameText:Hide()
        else
        f._nameText:Show()
        local ox = s.nameOffsetX or 0
        local oy = s.nameOffsetY or 0
        f._nameText:SetWidth((s.frameWidth or 72) * ns.RF_NAME_WIDTH_FRACTION)
        f._nameText:SetHeight(0)
        local ntHost = ns.RF_AnchorHost(f._health, s)
        if pos == "topleft" then
            f._nameText:SetPoint("TOPLEFT", ntHost, "TOPLEFT", 2 + ox, -2 + oy)
            f._nameText:SetJustifyH("LEFT"); f._nameText:SetJustifyV("TOP")
        elseif pos == "top" then
            f._nameText:SetPoint("TOP", ntHost, "TOP", ox, -2 + oy)
            f._nameText:SetJustifyH("CENTER"); f._nameText:SetJustifyV("TOP")
        elseif pos == "topright" then
            f._nameText:SetPoint("TOPRIGHT", ntHost, "TOPRIGHT", -2 + ox, -2 + oy)
            f._nameText:SetJustifyH("RIGHT"); f._nameText:SetJustifyV("TOP")
        elseif pos == "left" then
            f._nameText:SetPoint("LEFT", ntHost, "LEFT", 2 + ox, oy)
            f._nameText:SetJustifyH("LEFT"); f._nameText:SetJustifyV("MIDDLE")
        elseif pos == "right" then
            f._nameText:SetPoint("RIGHT", ntHost, "RIGHT", -2 + ox, oy)
            f._nameText:SetJustifyH("RIGHT"); f._nameText:SetJustifyV("MIDDLE")
        elseif pos == "bottomleft" then
            f._nameText:SetPoint("BOTTOMLEFT", ntHost, "BOTTOMLEFT", 2 + ox, 2 + oy)
            f._nameText:SetJustifyH("LEFT"); f._nameText:SetJustifyV("BOTTOM")
        elseif pos == "bottom" then
            f._nameText:SetPoint("BOTTOM", ntHost, "BOTTOM", ox, 2 + oy)
            f._nameText:SetJustifyH("CENTER"); f._nameText:SetJustifyV("BOTTOM")
        elseif pos == "bottomright" then
            f._nameText:SetPoint("BOTTOMRIGHT", ntHost, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            f._nameText:SetJustifyH("RIGHT"); f._nameText:SetJustifyV("BOTTOM")
        else -- center
            f._nameText:SetPoint("CENTER", ntHost, "CENTER", ox, oy)
            f._nameText:SetJustifyH("CENTER"); f._nameText:SetJustifyV("MIDDLE")
        end
        -- Force text re-render (WoW doesn't visually re-layout on JustifyH change alone)
        f._nameText:SetText("")
        f._nameText:SetText(ns.CapName(name))
        ApplyFont(f._nameText, s.nameSize or 10)
        local nameMode = s.nameColorMode or "class"
        if nameMode == "accent" then
            local ar, ag, ab = EllesmereUI.ResolveActiveAccent()
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
        end -- pos ~= "none"
    end

    -- Dead/offline/AFK states (only when indicators eyeball is on). The rez slot is
    -- a second corpse (dimmed, no "DEAD" text) that shows an incoming-rez icon in
    -- place of the status text -- mirrors the live "hide DEAD while rezzing" behavior.
    local isRezCorpse = indVis and index == previewRoles._rezSlot
    local isDead      = indVis and (index == previewRoles._deadSlot or isRezCorpse)
    local isOffline   = indVis and index == previewRoles._offlineSlot
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
        local htHost = ns.RF_AnchorHost(f._health, s)
        if htPos == "topleft" then
            f._healthText:SetPoint("TOPLEFT", htHost, "TOPLEFT", 2 + htOX, -2 + htOY)
            f._healthText:SetJustifyH("LEFT"); f._healthText:SetJustifyV("TOP")
        elseif htPos == "top" then
            f._healthText:SetPoint("TOP", htHost, "TOP", htOX, -2 + htOY)
            f._healthText:SetJustifyH("CENTER"); f._healthText:SetJustifyV("TOP")
        elseif htPos == "topright" then
            f._healthText:SetPoint("TOPRIGHT", htHost, "TOPRIGHT", -2 + htOX, -2 + htOY)
            f._healthText:SetJustifyH("RIGHT"); f._healthText:SetJustifyV("TOP")
        elseif htPos == "left" then
            f._healthText:SetPoint("LEFT", htHost, "LEFT", 2 + htOX, htOY)
            f._healthText:SetJustifyH("LEFT"); f._healthText:SetJustifyV("MIDDLE")
        elseif htPos == "right" then
            f._healthText:SetPoint("RIGHT", htHost, "RIGHT", -2 + htOX, htOY)
            f._healthText:SetJustifyH("RIGHT"); f._healthText:SetJustifyV("MIDDLE")
        elseif htPos == "bottomleft" then
            f._healthText:SetPoint("BOTTOMLEFT", htHost, "BOTTOMLEFT", 2 + htOX, 2 + htOY)
            f._healthText:SetJustifyH("LEFT"); f._healthText:SetJustifyV("BOTTOM")
        elseif htPos == "bottom" then
            f._healthText:SetPoint("BOTTOM", htHost, "BOTTOM", htOX, 2 + htOY)
            f._healthText:SetJustifyH("CENTER"); f._healthText:SetJustifyV("BOTTOM")
        elseif htPos == "bottomright" then
            f._healthText:SetPoint("BOTTOMRIGHT", htHost, "BOTTOMRIGHT", -2 + htOX, 2 + htOY)
            f._healthText:SetJustifyH("RIGHT"); f._healthText:SetJustifyV("BOTTOM")
        else
            f._healthText:SetPoint("CENTER", htHost, "CENTER", htOX, htOY)
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
            local ar, ag, ab = EllesmereUI.ResolveActiveAccent()
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

    -- Heal absorb text (preview): a representative value so the user can see
    -- and position it. Mirrors the health-text preview color resolution.
    if f._healAbsorbText then
        local haMode = s.healAbsorbTextMode or "none"
        ApplyFont(f._healAbsorbText, s.healAbsorbTextSize or 9)
        ns.AnchorRFText(f._healAbsorbText, ns.RF_AnchorHost(f._health, s), s.healAbsorbTextPosition or "center",
            s.healAbsorbTextOffsetX or 0, s.healAbsorbTextOffsetY or 0, (s.frameWidth or 72) * 0.75)
        if haMode ~= "none" and not isDead and not isOffline then
            ns.FormatHealAbsorbInto(f._healAbsorbText, math.floor(healthPct * 3000), haMode)
            local haCM = s.healAbsorbTextColorMode or "custom"
            local hr, hg, hb = 1, 0.3, 0.3
            if haCM == "accent" then
                local ar, ag, ab = EllesmereUI.ResolveActiveAccent()
                if ar then hr, hg, hb = ar, ag, ab end
            elseif haCM == "class" then
                local cc = EllesmereUI.GetClassColor(classToken)
                if cc then hr, hg, hb = cc.r, cc.g, cc.b end
            else
                local c = s.healAbsorbTextCustomColor
                if c then hr, hg, hb = c.r, c.g, c.b end
            end
            f._healAbsorbText:SetTextColor(hr, hg, hb, 0.9)
        else
            f._healAbsorbText:SetText("")
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
        local stHost = ns.RF_AnchorHost(f._health, s)
        if stPos == "topleft" then
            f._statusText:SetPoint("TOPLEFT", stHost, "TOPLEFT", 2 + stOX, -2 + stOY)
        elseif stPos == "top" then
            f._statusText:SetPoint("TOP", stHost, "TOP", stOX, -2 + stOY)
        elseif stPos == "topright" then
            f._statusText:SetPoint("TOPRIGHT", stHost, "TOPRIGHT", -2 + stOX, -2 + stOY)
        elseif stPos == "left" then
            f._statusText:SetPoint("LEFT", stHost, "LEFT", 2 + stOX, stOY)
        elseif stPos == "right" then
            f._statusText:SetPoint("RIGHT", stHost, "RIGHT", -2 + stOX, stOY)
        elseif stPos == "bottomleft" then
            f._statusText:SetPoint("BOTTOMLEFT", stHost, "BOTTOMLEFT", 2 + stOX, 2 + stOY)
        elseif stPos == "bottom" then
            f._statusText:SetPoint("BOTTOM", stHost, "BOTTOM", stOX, 2 + stOY)
        elseif stPos == "bottomright" then
            f._statusText:SetPoint("BOTTOMRIGHT", stHost, "BOTTOMRIGHT", -2 + stOX, 2 + stOY)
        else
            f._statusText:SetPoint("CENTER", stHost, "CENTER", stOX, stOY)
        end
        if isRezCorpse then
            -- Being resurrected: the rez icon takes this spot, so no DEAD text.
            f._statusText:Hide()
        elseif isDead then
            f._statusText:SetText(EllesmereUI.L("DEAD"))
            f._statusText:Show()
        elseif isOffline then
            f._statusText:SetText(EllesmereUI.L("OFFLINE"))
            f._statusText:Show()
        elseif isAfk then
            f._statusText:SetText(EllesmereUI.L("AFK"))
            f._statusText:Show()
        else
            f._statusText:Hide()
        end
    end

    -- Dead/DC overlay (mirror the live-frame status tint: full-cover bg)
    if isDead then
        if f._health then
            f._health:SetValue(0)
            local ft = f._health:GetStatusBarTexture()
            if ft then ft:SetAlpha(0) end
        end
        if f._bg then
            local c = s.statusColorDead or { r = 0x24/255, g = 0x17/255, b = 0x17/255 }
            f._bg:ClearAllPoints(); f._bg:SetAllPoints(f._health)
            f._bg:SetColorTexture(c.r, c.g, c.b, 1)
        end
        -- Hide shield on dead players
        if f._absorbBar then
            f._absorbBar:Hide()
            if f._absorbBar._forward then f._absorbBar._forward:Hide() end
            if f._absorbBar._topBar then f._absorbBar._topBar:Hide() end
        end
    elseif isOffline then
        if f._health then
            f._health:SetValue(0)
            local ft = f._health:GetStatusBarTexture()
            if ft then ft:SetAlpha(0) end
        end
        if f._bg then
            local c = s.statusColorOffline or { r = 0x66/255, g = 0x66/255, b = 0x66/255 }
            f._bg:ClearAllPoints(); f._bg:SetAllPoints(f._health)
            f._bg:SetColorTexture(c.r, c.g, c.b, 1)
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
                local pos = (s.roleIconPosition or "bottomleft"):upper()
                f._roleIcon:SetPoint(pos, ns.RF_AnchorHost(f._health, s), pos, s.roleIconOffsetX or 0, s.roleIconOffsetY or 0)
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
            f._leaderIcon:SetPoint(liPos, ns.RF_AnchorHost(f._health, s), liPos, s.leaderIconOffsetX or 0, s.leaderIconOffsetY or 0)
            f._leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
            f._leaderIcon:Show()
        else
            f._leaderIcon:Hide()
        end
    end

    -- Combat icon: on live alive members when the indicators eyeball is on.
    if f._combatIcon then
        if indVis and s.showCombatIndicator and not isDead and not isOffline then
            local cciSz = PixelSnap(s.combatIndicatorSize or 16)
            f._combatIcon:SetSize(cciSz, cciSz)
            f._combatIcon:ClearAllPoints()
            local ciPos = (s.combatIndicatorPosition or "right"):upper()
            f._combatIcon:SetPoint(ciPos, ns.RF_AnchorHost(f._health, s), ciPos, s.combatIndicatorOffsetX or 0, s.combatIndicatorOffsetY or 0)
            local style = s.combatIndicatorStyle or "standard"
            local MEDIA = ns._COMBAT_MEDIA
            if style:find("^combat%d") then
                f._combatIcon:SetTexture(MEDIA .. style .. ".tga")
                f._combatIcon:SetTexCoord(0, 1, 0, 1)
                if f._combatIcon.SetDesaturated then f._combatIcon:SetDesaturated(false) end
                f._combatIcon:SetVertexColor(1, 1, 1, 1)
            else
                if style == "class" then
                    f._combatIcon:SetTexture(MEDIA .. "combat-indicator-class-custom.png")
                    local coords = classToken and ns._COMBAT_CLASS_COORDS[classToken]
                    if coords then f._combatIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                    else f._combatIcon:SetTexCoord(0, 1, 0, 1) end
                else
                    f._combatIcon:SetTexture(MEDIA .. "combat-indicator-custom.png")
                    f._combatIcon:SetTexCoord(0, 1, 0, 1)
                end
                local colorMode = s.combatIndicatorColor or "custom"
                if colorMode == "classcolor" then
                    local cc = (classToken and EllesmereUI.GetClassColor(classToken)) or { r = 1, g = 1, b = 1 }
                    f._combatIcon:SetVertexColor(cc.r, cc.g, cc.b, 1)
                else
                    local cc = s.combatIndicatorCustomColor or { r = 1, g = 1, b = 1 }
                    f._combatIcon:SetVertexColor(cc.r, cc.g, cc.b, 1)
                end
            end
            f._combatIcon:Show()
        else
            f._combatIcon:Hide()
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
    if ns._RebuildPvOverlay then ns._RebuildPvOverlay() end
    BuildPreviewRoles()

    local s = ns._pvOverlayProxy or db.profile
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
        ApplyFont(lbl, s.groupNumberSize or 10)
        do
            -- Shared size/color with the real frames (group-number settings).
            -- Not gated by showGroupNumbers: the preview always shows numbers.
            local gc = s.groupNumberColor or {}
            lbl:SetTextColor(gc.r or 1, gc.g or 1, gc.b or 1, gc.a or 0.75)
        end
        lbl:SetText(tostring(g + 1))
        lbl:ClearAllPoints()
        -- Anchor based on unit growth: label goes "before" the first unit.
        -- The X/Y offset (shared group-number setting) shifts it from there.
        local gnox = s.groupNumberOffsetX or 0
        local gnoy = s.groupNumberOffsetY or 0
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
    -- Group-number labels go on a high-level overlay child of the same container
    -- so they draw ABOVE the preview bars (which are descendants of reparentTo);
    -- parenting them straight to reparentTo leaves them beneath the bars.
    if not ns._previewGroupNumberOverlay then
        ns._previewGroupNumberOverlay = CreateFrame("Frame", nil, reparentTo)
    end
    ns._previewGroupNumberOverlay:SetParent(reparentTo)
    ns._previewGroupNumberOverlay:SetAllPoints(reparentTo)
    ns._previewGroupNumberOverlay:SetFrameLevel(9000)
    ns._previewGroupNumberOverlay:Show()
    for _, lbl in ipairs(previewGroupLabels) do lbl:SetParent(ns._previewGroupNumberOverlay) end

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
        -- Re-anchor from the saved position on EVERY refresh (mirrors the
        -- real container and the size preview; preserving a stale TOPLEFT
        -- here left the real-mode preview stranded after a growth change
        -- until the panel reopened). Anchored at the base footprint's
        -- top-left so size changes grow down/right exactly like the real
        -- container's _ApplyTierOffset scheme.
        local se = ns._PvSessionElem and ns._PvSessionElem("RF_RaidFrames")
        local bl, bt = ns._RFBaseTopLeft()
        previewContainer:ClearAllPoints()
        if se and se.point then
            -- Editing an override with a custom unlock mode: place the
            -- preview at the LAYER's recorded container position.
            previewContainer:SetPoint(se.point, UIParent, se.relPoint or se.point,
                PixelSnap(se.x or 0), PixelSnap(se.y or 0))
        elseif bl then
            previewContainer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", PixelSnap(bl), PixelSnap(bt))
        else
            previewContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
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
    if ns.TS_RefreshRaidPreview then ns.TS_RefreshRaidPreview() end
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
        -- Overlay preview is a separate docked panel, so the real frames are NOT
        -- under it: leave them faintly visible (alpha 0.2) and DON'T mouse-block
        -- them. Real preview replaces the frames in place, so keep the original
        -- behavior there: hide fully (alpha 0) + block clicks.
        local isOverlay = (db.profile.previewMode == "overlay") or ns._testMode
        if isOverlay then
            local a = on and 0.2 or 1
            if containerFrame then containerFrame:SetAlpha(a) end
            if ns._partyContainerFrame then ns._partyContainerFrame:SetAlpha(a) end
            setBlock(false)
        else
            local a = on and 0 or 1
            if containerFrame then containerFrame:SetAlpha(a) end
            if ns._partyContainerFrame then ns._partyContainerFrame:SetAlpha(a) end
            setBlock(on)
        end
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
        previewContainer:SetFrameStrata("HIGH")
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
    -- Re-derive the growth-corner anchor after the relayout (self-gates on
    -- combat) so a size change made while previewing can never strand the
    -- container at a stale position.
    if ns._ApplyTierOffset then ns._ApplyTierOffset() end
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
    -- Re-apply the real-frame hide state for the (possibly just-changed) mode so a
    -- live Real<->Overlay switch updates alpha + mouse-block: overlay shows the
    -- real frames faintly with NO block; real hides them fully + blocks.
    ns._SetRealFramesPreviewHidden(true)
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
--  Always screen-anchored exactly where the live frames land (shared
--  growth-corner origin ns._RFTierTopLeft), regardless of preview mode.
--  No indicators, no randomization.
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

    -- Total bounding box: the 4-group mover footprint via the SAME
    -- ns._RFFootprint the live container sizing and the corner origin use
    -- (one formula, so preview and live can never drift). MOVER_GROUPS
    -- stays 4 for the group normalization below -- it must keep matching
    -- the real LayoutGroups container, which also normalizes over 4.
    local MOVER_GROUPS = 4
    local totalW, totalH = ns._RFFootprint(bw, bh, unitGrowth, groupGrowth, cs, gs)

    -- Tier offset
    local tierOX = ov.offsetX or 0
    local tierOY = ov.offsetY or 0

    -- Create or reuse container
    local container = ns._sizePreviewContainer
    if not container then
        container = CreateFrame("Frame", nil, UIParent)
        container:SetFrameStrata("FULLSCREEN_DIALOG")
        container:SetFrameLevel(10)
        -- Never clamp: the preview must land exactly where the live
        -- container lands, including partially off-screen positions.
        container:SetClampedToScreen(false)
        ns._sizePreviewContainer = container
    end

    -- Always use real positioning (where frames actually sit)
    local pad = 0
    container:SetSize(totalW, totalH)
    if container._bg then container._bg:Hide() end
    container:SetFrameStrata("HIGH")
    container:ClearAllPoints()
    -- Same growth-corner origin as the live container (_ApplyTierOffset):
    -- the tier footprint's growth-derived corner pins at the base
    -- footprint's same corner plus the tier offset, via the shared
    -- ns._RFTierTopLeft -- the preview lands exactly where live lands.
    local px, py = ns._RFTierTopLeft(totalW, totalH, unitGrowth, groupGrowth, tierOX, tierOY)
    if px then
        container:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", PixelSnap(px), PixelSnap(py))
    else
        container:SetPoint("CENTER", UIParent, "CENTER", tierOX, tierOY)
    end

    -- Font for the unit-number label
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    local nameSize = s.nameSize or 10

    -- Normalize origin over MOVER_GROUPS (matching real LayoutGroups container)
    local minX, maxY = 0, 0
    for g = 0, MOVER_GROUPS - 1 do
        local gx = g * stepX
        local gy = g * stepY
        if gx < minX then minX = gx end
        if gy > maxY then maxY = gy end
    end

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

            -- Top Name Bar
            local tnb = CreateFrame("Frame", nil, f)
            tnb:SetFrameLevel(f:GetFrameLevel() + 4)
            tnb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            tnb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            local tnbBg = tnb:CreateTexture(nil, "BACKGROUND")
            tnbBg:SetAllPoints()
            if PP then PP.DisablePixelSnap(tnbBg) end
            local tnbText = tnb:CreateFontString(nil, "OVERLAY")
            tnbText:SetWordWrap(false)
            tnb:Hide()
            f._topNameBar = tnb
            f._topNameBarBg = tnbBg
            f._topNameBarText = tnbText

            -- Role icon
            local roleIcon = health:CreateTexture(nil, "OVERLAY")
            roleIcon:Hide()
            f._roleIcon = roleIcon

            ns._sizePreviewFrames[i] = f
        end

        f:SetParent(container)
        f:SetSize(bw, bh)
        -- GENERIC SIZING PLACEHOLDER (NOT a style preview):
        -- The custom raid-size previews (10/15/25/30) deliberately do NOT mimic the
        -- user's real raid-frame style. They render as plain blocks that only show
        -- each frame's footprint at the chosen width/height/spacing, so the size
        -- preview can never be mistaken for a live style preview when it does not
        -- match the user's customized frames. No class colors, textures, power bars,
        -- names, role icons or custom border -- just a flat fill, a thin neutral
        -- outline and the unit number.
        f._health:ClearAllPoints()
        f._health:SetAllPoints(f)
        f._health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        if f._health:GetStatusBarTexture() then f._health:GetStatusBarTexture():SetHorizTile(false) end
        f._health:SetStatusBarColor(0.24, 0.26, 0.30, 1)
        f._health:SetValue(100)
        f._bg:SetColorTexture(0.09, 0.09, 0.11, 1)
        if f._power then f._power:Hide() end
        if f._topNameBar then f._topNameBar:Hide() end
        if f._roleIcon then f._roleIcon:Hide() end

        -- Thin neutral outline so each block and the spacing between them reads clearly.
        if f._border and PP then
            f._border:SetFrameLevel(f:GetFrameLevel() + 2)
            EllesmereUI.ApplyBorderStyle(f._border, 1, 0.7, 0.7, 0.75, 0.8,
                "solid", nil, nil, nil, nil, "unitframes", 1)
        end

        -- Centered unit number.
        if f._nameText then
            local nameOutline = GetOutline()
            if EllesmereUI and EllesmereUI.PrimeFontShadow then
                EllesmereUI.PrimeFontShadow(f._nameText, nameOutline == "" and GetUseShadow())
            end
            f._nameText:SetFont(fontPath, math.max(11, nameSize), nameOutline)
            f._nameText:SetText(tostring(i))
            f._nameText:SetTextColor(0.9, 0.9, 0.9)
            f._nameText:SetWidth(bw)
            f._nameText:ClearAllPoints()
            f._nameText:SetPoint("CENTER", f._health, "CENTER", 0, 0)
            f._nameText:Show()
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
    local prioritizeClass = db.profile.partyPrioritizeClass
    if sortMode == "ROLE" or showSelfFirst or prioritizeClass then
        local group = {}
        for u = 1, 5 do
            group[u] = {
                role = ns._partyPvRoles[u],
                classToken = ns._partyPvCT[u],
                isPlayer = (u == 1),
                idx = u,
            }
        end
        if sortMode == "ROLE" or prioritizeClass then
            -- Mirror the live header order: role (optional primary) -> class (when
            -- Prioritize Class is on) -> original slot. Comparator matches
            -- _BuildPartyClassNameList so the preview replicates the real frames.
            local sortByRole = (sortMode == "ROLE")
            local roleOrder = db.profile.partyRoleOrder or db.profile.roleOrder or { "TANK", "HEALER", "DAMAGER" }
            local rolePri = {}
            for i, r in ipairs(roleOrder) do rolePri[r] = i end
            local classPri
            if prioritizeClass then
                classPri = {}
                local co = db.profile.partyClassOrder or ns._GetDefaultClassOrder()
                for i, c in ipairs(co) do classPri[c] = i end
            end
            table.sort(group, function(a, b)
                if sortByRole then
                    local ra, rb = rolePri[a.role] or 99, rolePri[b.role] or 99
                    if ra ~= rb then return ra < rb end
                end
                if classPri then
                    local ca, cb = classPri[a.classToken] or 99, classPri[b.classToken] or 99
                    if ca ~= cb then return ca < cb end
                end
                return a.idx < b.idx
            end)
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
        -- Status showcase: 1 dead, 1 offline, 1 AFK, 1 summon-accepted, one each on
        -- the four non-player slots (2-5). No ready-check ticks. (Incoming-rez isn't
        -- previewed here: a 5-man has only four non-player slots and they're all
        -- taken, so there's no room for a separate rez corpse the way the raid
        -- preview has one. The live indicator still shows on party frames.)
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

    -- Sandwich values sourced through the effective overlay (panel-closed
    -- values while a view swap is active); s stays live db.profile so the
    -- mutation+restore semantics are unchanged.
    local eff = ns._pvOverlayProxy or db.profile
    local origW, origH = s.frameWidth, s.frameHeight
    s.frameWidth  = eff.partyFrameWidth  or eff.frameWidth
    s.frameHeight = eff.partyFrameHeight or eff.frameHeight

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
    if ns._RebuildPvOverlay then ns._RebuildPvOverlay() end
    -- Recompute party indicator/aura scale before applying preview data so the
    -- party preview reflects Auto Resize live (preview reads _scaledPartyProxy).
    if ns._UpdatePartyIndicatorScale then ns._UpdatePartyIndicatorScale() end
    local s = ns._pvOverlayProxy or db.profile
    local w = PixelSnap(s.partyFrameWidth or s.frameWidth or 125)
    local h = PixelSnap(s.partyFrameHeight or s.frameHeight or 60)
    local spacing = PixelSnap(s.partyCellSpacing or s.cellSpacing or 2)
    local mode = db.profile.previewMode or "overlay"

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
    local unitGrowth = s.partyHorizontal and (s.partyFlipGrowth and "LEFT" or "RIGHT")
        or (s.partyFlipGrowth and "UP" or "DOWN")
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
            f:SetFrameStrata(isOverlay and "FULLSCREEN_DIALOG" or "HIGH")
            f:ClearAllPoints()
            if isVert then
                local yOff = slot * (h + spacing)
                if unitGrowth == "DOWN" then
                    f:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", anchorPad, -anchorPad - topExtra - yOff)
                else
                    -- UP fills the same box from the bottom upward (positive
                    -- offsets); the container's extra top height creates the
                    -- title gap, so no per-frame correction is needed here.
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

    -- Real mode: anchor frames to the actual party container, mirroring the
    -- real layout's basePoint logic (_PositionPartySlots). Slot 0 sits at the
    -- container corner the growth direction moves AWAY from, so Flip Frame
    -- Growth keeps the stack bounded by the container instead of growing past
    -- it. A plain TOPLEFT anchor misaligned the flipped preview by a full
    -- stack height/width versus the edit-mode location.
    if mode == "real" and ns._partyContainerFrame then
        local pos = s.partyUnlockPos
        -- Editing an override with a custom unlock mode: anchor the preview
        -- at the LAYER's recorded party-container position (a lightweight
        -- proxy frame stands in for the real container, which sits at the
        -- REAL spec's position).
        local anchorTo = ns._partyContainerFrame
        local se = ns._PvSessionElem and ns._PvSessionElem("RF_PartyFrames")
        if se and se.point then
            local proxy = ns._pvSessionPartyAnchor
            if not proxy then
                proxy = CreateFrame("Frame", nil, UIParent)
                ns._pvSessionPartyAnchor = proxy
            end
            proxy:SetSize(ns._partyContainerFrame:GetSize())
            proxy:ClearAllPoints()
            proxy:SetPoint(se.point, UIParent, se.relPoint or se.point,
                PixelSnap(se.x or 0), PixelSnap(se.y or 0))
            anchorTo = proxy
            pos = pos or se
        end
        if pos then
            local stepX, stepY = 0, 0
            local basePoint = "TOPLEFT"
            if unitGrowth == "RIGHT" then
                stepX = w + spacing
            elseif unitGrowth == "LEFT" then
                stepX = -(w + spacing); basePoint = "TOPRIGHT"
            elseif unitGrowth == "UP" then
                stepY = h + spacing; basePoint = "BOTTOMLEFT"
            else -- DOWN
                stepY = -(h + spacing)
            end
            local idx = 0  -- running position; skips the hidden player frame
            for i = 1, 5 do
                local f = ns._partyPvFrames[i]
                if f then
                    if hideSelf and i == playerSlot then
                        f:Hide()
                    else
                        f:ClearAllPoints()
                        f:SetPoint(basePoint, anchorTo, basePoint,
                            PixelSnap(stepX * idx), PixelSnap(stepY * idx))
                        idx = idx + 1
                    end
                end
            end
        end
    end

    -- Targeted Spells preview icon: re-style with the scale recomputed above
    -- (also makes it appear/disappear with the party preview itself).
    if ns.TS_RefreshPreview then ns.TS_RefreshPreview() end
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
    if not InCombatLockdown() then
        LayoutGroups()
        if ns._ApplyTierOffset then ns._ApplyTierOffset() end
    end
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

    -- Inherit the Absorbs section's party-sync state from Health Bar for
    -- profiles saved before the section split (must precede any proxy reads).
    ns._NormalizePartySyncSections()

    -- Rebase pre-top-left-anchor tier offsets (marker travels in the data)
    ns._NormalizeTierOffsetAnchors()

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
        -- Skip the saved-pos SetPoint when element-anchored with resolved
        -- geometry: the unlock anchor system owns the position.
        local anchored = EllesmereUI.IsUnlockAnchored
            and EllesmereUI.IsUnlockAnchored("RF_PartyFrames")
            and ns._partyContainerFrame:GetLeft()
        if pos and not anchored then
            ns._partyContainerFrame:ClearAllPoints()
            ns._partyContainerFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
        end
    end

    -- Apply party-specific sizing to party buttons
    ns.ReloadPartyFrames()

    -- Register with unlock mode
    RegisterWithUnlockMode()

    -- Friendly Boss Frames: initial activation (raid-only boss1-5 frames)
    if ns.FB_Apply then ns.FB_Apply() end
    -- Extra Frames: initial activation (raid-only member duplicates)
    if ns.XF_Apply then ns.XF_Apply() end

    -- Profile-swap refresh: EllesmereUI.RefreshAllAddons calls this on a profile
    -- change so raid + party frames re-read the (now-swapped) profile live,
    -- instead of staying stale until /reload. Mirrors the reload sequence above.
    _G._ERF_RefreshAll = function()
        if not ns.db then return end
        -- Absorbs sync-state inheritance for swapped/imported profiles saved
        -- before the Absorbs section split (must precede party proxy reads).
        ns._NormalizePartySyncSections()
        -- Rebase old-scheme tier offsets on swapped/imported profiles too
        -- (the marker lives inside raidSizeOverrides, so this self-detects).
        ns._NormalizeTierOffsetAnchors()
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
            -- Skip the saved-pos SetPoint when element-anchored with resolved
            -- geometry: the unlock anchor system owns the position.
            local anchored = EllesmereUI.IsUnlockAnchored
                and EllesmereUI.IsUnlockAnchored("RF_PartyFrames")
                and ns._partyContainerFrame:GetLeft()
            if pos and not anchored then
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
        -- Friendly Boss Frames and Extra Frames re-read the swapped profile.
        if ns.FB_Apply then ns.FB_Apply() end
        if ns.XF_Apply then ns.XF_Apply() end
        -- Real-preview effective overlay: RunRefreshers reaches here
        -- synchronously from every view/spec/conditional transition, so the
        -- preview's value source is corrected in the SAME frame -- the
        -- shared tickers never render a stale overlay across a flip.
        -- Near-zero cost when the overlay gate is inactive.
        if ns._RebuildPvOverlay then ns._RebuildPvOverlay() end
    end

    -- Buff Manager LAYER swap refresh (spec-override BM forks): re-derives
    -- the spell lookup, then re-anchors + fully rescans BM indicators on
    -- every visible raid/party button. A layer swap can change bmSimple
    -- geometry AND the tracked spell set; a lookup rebuild alone leaves
    -- stale icons frozen (see the PLAYER_SPECIALIZATION_CHANGED handler).
    -- Deliberately BM-only: never calls ReloadFrames, so profile swaps
    -- (_ERF_RefreshAll above) are not doubled. Combat-safe: BM code only
    -- touches our own pooled child frames, never the secure buttons.
    -- noPage: skip the options-page repaint when the caller IS a page build.
    _G._ERF_BMRefresh = function(noPage)
        if not ns.db then return end
        if ns.BM_RebuildLookup then ns.BM_RebuildLookup(ns.db) end
        local function refreshButtons(list)
            for _, btn in ipairs(list) do
                local u = btn:GetAttribute("unit")
                if u and btn:IsVisible() then
                    -- Per-button state lives in the FFD side table, never on
                    -- the button frame itself; BM_AnchorIndicators takes the
                    -- FFD table (BM_UpdateIndicators takes the button).
                    local d = GetFFD(btn)
                    if d.bmIconPool and d.health and ns.BM_AnchorIndicators then
                        local s = d._isParty and ns._scaledPartyProxy
                            or (d._isExtra and ns._scaledExtraProxy)
                            or ns._scaledProfile
                        if s then ns.BM_AnchorIndicators(d, d.health, s) end
                    end
                    if ns.BM_UpdateIndicators then ns.BM_UpdateIndicators(btn, u, ns.db) end
                end
            end
        end
        if framesVisible then refreshButtons(allButtons) end
        if ns._partyFramesVisible and ns._partyAllButtons then
            refreshButtons(ns._partyAllButtons)
        end
        local pv = ns._bmPreviewFrame
        if pv and pv._health and ns.BM_ApplyPreviewIndicators then
            ns.BM_ApplyPreviewIndicators(pv, 1, ns.db.profile)
        end
        -- Open BM options page: force a rebuild so its widgets re-bind to
        -- the (identity-preserved, content-swapped) profile tables.
        if not noPage and ns._bmRoot and EllesmereUI and EllesmereUI.RefreshPage then
            EllesmereUI:RefreshPage(true)
        end
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
    eventFrame:RegisterEvent("INCOMING_SUMMON_CHANGED")
    eventFrame:RegisterEvent("INCOMING_RESURRECT_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PARTY_MEMBER_ENABLE")
    eventFrame:RegisterEvent("PARTY_MEMBER_DISABLE")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("UNIT_PHASE")
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("ENCOUNTER_END")

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

    -- UNIT_FLAGS is opt-in: only registered while the combat icon is enabled.
    if ns.UpdateCombatEventRegistration then ns.UpdateCombatEventRegistration() end

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
            -- Re-derive the growth-corner anchor: this can be the first
            -- sized pass when roster data arrives late, and its SetSize
            -- must not leave the container on a stale anchor.
            if ns._ApplyTierOffset then ns._ApplyTierOffset() end
            UpdateAllButtons()
        end
        if ns._partyFramesVisible then
            ns._LayoutPartyFrames()
        end
    end)

    -- Nickname integrations. When Northern Sky Raid Tools (NSAPI) or Timeline
    -- Reminders (TimelineReminders) is present, raid + party names use their
    -- nicknames (see ResolveDisplayName). Callbacks refresh names instantly
    -- without a /reload when nickname data changes or the user flips the addon's
    -- dedicated EllesmereUI nicknames checkbox. Both addons may load after us, so
    -- registration retries on PLAYER_LOGIN / PLAYER_ENTERING_WORLD until it sticks.
    -- All registrations are dot calls, NOT colon: the first argument is the unique
    -- registrant key (CallbackHandler keys registrations by it). A colon call would
    -- pass the API table itself as the key and collide with other addons doing the same.
    local function RegisterNSRTNicknames()
        if ns._nsrtNickHooked then return true end
        if NSAPI and NSAPI.RegisterCallback then
            local function onChange() if ns.RefreshAllNames then ns.RefreshAllNames() end end
            NSAPI.RegisterCallback("EllesmereUI", "NSRT_NICKNAME_UPDATED", onChange)
            NSAPI.RegisterCallback("EllesmereUI", "EUI_NICKNAME_TOGGLE", onChange)
            ns._nsrtNickHooked = true
            return true
        end
        return false
    end
    local function RegisterTRNicknames()
        if ns._trNickHooked then return true end
        local TR = TimelineReminders
        if TR and TR.RegisterCallback then
            -- CallbackHandler passes the event name as the first callback argument.
            -- Toggle fires for every addon checkbox in TR, so filter on ours.
            TR.RegisterCallback("EllesmereUI", "TimelineReminders_NicknameToggle", function(_, _, addOnName)
                if addOnName == ns.NICK_ADDON and ns.RefreshAllNames then ns.RefreshAllNames() end
            end)
            TR.RegisterCallback("EllesmereUI", "TimelineReminders_NicknameUpdate", function()
                if ns.RefreshAllNames then ns.RefreshAllNames() end
            end)
            ns._trNickHooked = true
            return true
        end
        return false
    end
    local nsrtHooked = RegisterNSRTNicknames()
    local trHooked = RegisterTRNicknames()
    if not (nsrtHooked and trHooked) then
        local nickFrame = CreateFrame("Frame")
        nickFrame:RegisterEvent("PLAYER_LOGIN")
        nickFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        nickFrame:SetScript("OnEvent", function(self, event)
            local a = RegisterNSRTNicknames()
            local b = RegisterTRNicknames()
            -- Anything not loaded by first PLAYER_ENTERING_WORLD is not coming.
            if (a and b) or event == "PLAYER_ENTERING_WORLD" then self:UnregisterAllEvents() end
        end)
    end

    -- Init options module if it loaded before us
    if ns._InitEUIModule then
        C_Timer.After(0, ns._InitEUIModule)
    end
end

-------------------------------------------------------------------------------
--  TEMP DEBUG: /euiparty -- dumps the live geometry/state of the party self
--  button and the five header children (shown, alpha, size, health bar shown/
--  height/value/texture, power shown). Run while frames look broken to
--  pinpoint whether the health bar is hidden, zero-height, textureless or
--  value-zero. Remove after the resize investigation.
-------------------------------------------------------------------------------
do
    local function SafeStr(v)
        if v == nil then return "nil" end
        if issecretvalue and issecretvalue(v) then return "SECRET" end
        return tostring(v)
    end
    SLASH_EUIPARTY1 = "/euiparty"
    SlashCmdList["EUIPARTY"] = function()
        print("|cff0cd29fEUI party debug|r pvActive=" .. tostring(ns._partyPvActive and true or false)
            .. "  visible=" .. tostring(ns._partyFramesVisible)
            .. "  inGroup=" .. tostring(IsInGroup()) .. "  members=" .. tostring(GetNumGroupMembers()))
        local hd = ns._partyHeader
        if hd then
            print(("  header shown=%s w=%.0f h=%.0f kids=%d | sortMethod=%s nameList=%s groupFilter=%s groupBy=%s")
                :format(tostring(hd:IsShown()), hd:GetWidth() or 0, hd:GetHeight() or 0,
                    hd:GetNumChildren() or 0,
                    tostring(hd:GetAttribute("sortMethod")), tostring(hd:GetAttribute("nameList")),
                    tostring(hd:GetAttribute("groupFilter")), tostring(hd:GetAttribute("groupBy"))))
            print(("  header showParty=%s showPlayer=%s showSolo=%s point=%s xOff=%s yOff=%s")
                :format(tostring(hd:GetAttribute("showParty")), tostring(hd:GetAttribute("showPlayer")),
                    tostring(hd:GetAttribute("showSolo")), tostring(hd:GetAttribute("point")),
                    tostring(hd:GetAttribute("xOffset")), tostring(hd:GetAttribute("yOffset"))))
        end
        local function dump(tag, btn)
            if not btn then return end
            local d = GetFFD(btn)
            local h = d and d.health
            local fill = h and h:GetStatusBarTexture()
            print(("  %s shown=%s alpha=%.2f w=%.0f h=%.0f | health shown=%s hh=%.1f val=%s tex=%s | power shown=%s")
                :format(tag, tostring(btn:IsShown()), btn:GetAlpha(),
                    btn:GetWidth() or 0, btn:GetHeight() or 0,
                    tostring(h and h:IsShown()), h and h:GetHeight() or -1,
                    SafeStr(h and h:GetValue()), SafeStr(fill and fill:GetTexture()),
                    tostring(d and d.power and d.power:IsShown())))
        end
        dump("self", ns._partySelfButton)
        if ns._partyHeader then
            for i = 1, 5 do
                local btn = ns._partyHeader[i]
                if btn then
                    dump("hdr" .. i .. " u=" .. tostring(btn:GetAttribute("unit")), btn)
                end
            end
        end
    end
end

-- Slash command registered in EUI_RaidFrames_Options.lua
