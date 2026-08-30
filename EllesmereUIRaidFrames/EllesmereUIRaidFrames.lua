if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIRaidFrames.lua
--  Custom raid frames built on SecureGroupHeaderTemplate.
--  8 per-group headers (separated mode) + 1 combined header (flat mode).
--  Secret-value-safe absorb shields matching UnitFrames visuals.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS[ADDON_NAME] = ns  -- LOD options files read this module ns via the registry

local ERF = EllesmereUI.Lite.NewAddon(ADDON_NAME)
ns.ERF = ERF
_G.EllesmereUIRaidFrames = ERF

-- Parent-addon table cached on ns: hot event paths (UNIT_AURA,
-- PLAYER_REGEN_DISABLED) reading the GLOBAL EllesmereUI from an event frame
-- still in a secure execution context raise benign self-taint; table-field
-- reads do not. On ns to spare the main-chunk 200-local cap.
ns.EllesmereUI = EllesmereUI

-- Addon name external nickname providers key us by. Suite = the brand
-- "EllesmereUI" (what providers register support for); standalone = our
-- renamed folder name (ADDON_NAME), the per-addon key. "Standalone" survives
-- the standalone token rename, so detection is rename-immune and the
-- "EllesmereUI" literal is only reached in the suite. On ns (200-local cap).
ns.NICK_ADDON = ADDON_NAME:find("Standalone") and ADDON_NAME or "EllesmereUI"

-------------------------------------------------------------------------------
--  Frame-level layout (offsets above the button / preview-frame level).
--  All aura VISUALS (debuffs, defensives/externals, private auras, dispel-type
--  icons, Buff Manager icons/squares/bars) share one band ABOVE the
--  threat/dispel/base border so the threat border renders behind them; each
--  aura unit renders children (cooldown/border/text) up to +5 above base.
--  Bottom to top: base border (+8/strips +9) -> hover/target raise (LVL_RAISE,
--  strips +11, covering base/threat/dispel border strips) -> text band
--  (LVL_TEXT: name/health text, role icon, leader crown) -> aura band ->
--  marker carrier (also hosts ready-check/summon/rez icons). The raise sits
--  BELOW text deliberately so borders never cover text and auras always draw
--  over text; it outranks only neighbor BORDERS, so with negative spacing a
--  neighbor's text/auras can clip it. Opt-out "Show Above Icons" (name cog)
--  lifts a button's text carrier to ns.LVL_AURA + 6, above the aura band's
--  children. On `ns` (local cap), shared with EUI_RaidFrames_BuffManager.lua.
-------------------------------------------------------------------------------
ns.LVL_DISPEL_OVERLAY = 7  -- Blizzard private-aura dispel gradient: below the border (+8) and name/health text (LVL_TEXT) so it renders BEHIND them (like the regular dispel overlay), but above the health bar so it stays visible. Per-slot private-aura icons stay above at LVL_AURA.
ns.LVL_RAISE  = 10   -- hover/target border (strips +11: above base strips +9;
                     -- ties threat/dispel strips +11 but the raise container is
                     -- created later so it wins). MUST stay below ns.LVL_TEXT:
                     -- UpdateBorder creates strips lazily AFTER the text
                     -- carriers, so a tie with text puts the border on top.
ns.LVL_TEXT   = 12   -- text band: name/health text, role icon, leader crown;
                     -- above every border incl. the raise, below the aura band
ns.LVL_AURA   = 13   -- base level for every aura icon/bar (children at +1..+5)
ns.LVL_MARKER = 26   -- raid marker icon (always on top -- above the dispel
                     -- type icon band at +21..+25, which itself sits above
                     -- the aura band so it wins a corner shared with debuffs)

-------------------------------------------------------------------------------
--  Leader-icon host strata: keep the host on the button's own strata in the
--  text band (ns.LVL_AURA - 1 = ns.LVL_TEXT) so the crown clears every border
--  incl. the hover/target raise while auras still draw over it. Re-applied on
--  reload to recover from container SetFrameStrata cascade resets.
-------------------------------------------------------------------------------
function ns.ApplyLeaderStrata(frame)
    local parent = frame:GetParent()
    if parent then
        frame:SetFrameStrata(parent:GetFrameStrata())
        frame:SetFrameLevel(parent:GetFrameLevel() + (ns.LVL_AURA - 1))
    end
end

-------------------------------------------------------------------------------
--  CPU-attribution shell pool. The engine bills a handler's ENTIRE call tree to
--  the addon whose execution context CREATED the frame it entered through;
--  OnEnable setup runs under the parent's lifecycle dispatch, so a frame born
--  there bills the PARENT forever (see EllesmereUI_Ticker.lua). These are born
--  in this file's main chunk; event hosts adopt one via ns.TakeShell() instead
--  of CreateFrame("Frame"). Plain unnamed Frames, persistent hosts only: no
--  release. Sized for per-unit trackers (40 raid + party + boss + extra) plus
--  standing watchers.
-------------------------------------------------------------------------------
do
    local pool = {}
    local n = 90
    for i = 1, n do pool[i] = CreateFrame("Frame") end
    ns.TakeShell = function()
        if n > 0 then
            local f = pool[n]
            pool[n] = nil
            n = n - 1
            return f
        end
        -- Pool exhausted (not expected): still works but bills the parent;
        -- bump the pool size if this ever happens.
        return CreateFrame("Frame")
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

-- Absorb shield textures (must match UnitFrames exactly)
local ABSORB_STYLE_TEX = {
    striped         = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-5.png",
    stripedReversed = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-5-reversed.png",
    stripedThick    = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-thick.png",
    stripedThickR   = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-thick-r.png",
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

-- Role icon definitions per style. _isTexture = true -> values are file paths
-- (SetTexture); otherwise atlas names (SetAtlas).
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
-- Read-only share with the options file's style preview (this file loads first).
ns.ROLE_ICON_STYLES = ROLE_ICON_STYLES

local function ApplyRoleIcon(texture, role, style)
    -- Caller supplies style from its own settings context (party proxy /
    -- preview override) so unsynced party roleIconStyle holds; raid profile only when omitted.
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

-- Threat: active aggro only (states 2/3); white border in the hover style.
local THREAT_ACTIVE = { [2] = true, [3] = true }

-- Combat indicator media + class sprite coords (shared with the Unit Frames
-- combat icon assets). Kept on `ns` to avoid the Lua 5.1 chunk local cap.
ns._COMBAT_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\combat\\"
ns._COMBAT_CLASS_COORDS = EllesmereUI.CLASS_ICON_SPRITE_COORDS

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
        unitGrowth       = "DOWN",   -- any direction; same-axis as groupGrowth = one continuous line
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
        frameStrata      = "LOW",

        -- Friendly Boss Frames (boss1-5 healable NPC frames; raid, plus party
        -- via the opt-in showInDungeons key -- absent = raid only, no default
        -- on purpose so existing users keep the raid-only behavior)
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
            -- growDirection / wrapDirection / freeRect: optional, no defaults.
            -- Unset, growth derives from freeHorizontal, wrap from the perpendicular
            -- default, anchoring from freePos. See XF.GrowInfo / XF.FreeAnchor.
        },

        -- Healer Mana Text Display (Extras): one text row per group healer.
        healerMana = {
            mode       = "none",   -- "none" | "party" | "raid" | "both"
            textSize   = 12,
            spacing    = 2,        -- vertical space between rows
            showNames  = true,     -- raid only; party shows the number alone
            classNames = true,     -- class colored names
            align      = "LEFT",   -- "LEFT" | "CENTER" | "RIGHT"
            growth     = "DOWN",   -- "DOWN" | "UP" (row stacking direction)
            colorMode  = "custom", -- "custom" | "power" (value text color)
            color      = { r = 1, g = 1, b = 1 },
            -- unlockPos: saved by unlock mode (RF_HealerMana element)
        },

        -- Position (saved by unlock mode)
        unlockPos        = nil,

        -- Health bar
        healthBarTexture = "atrocity",
        healthBarOpacity = 100,
        healthColorMode  = "class",  -- "class", "dark", "classic", "custom", "customDynamic", "classReactive"
        customFillColor  = { r = 37/255, g = 193/255, b = 29/255 },
        -- Custom Dynamic Colors: health-percent gradient stops; defaults match
        -- the Classic curve so switching from Classic looks identical at first.
        dynamicColor100  = { r = 0, g = 1, b = 0 },   -- full health
        dynamicColor50   = { r = 1, g = 1, b = 0 },   -- half health
        dynamicColor0    = { r = 1, g = 0, b = 0 },   -- empty health
        customBgColor    = { r = 17/255, g = 17/255, b = 17/255 },
        bgClassColored   = false,
        bgDarkness       = 50,
        -- Fill axis: off = left-to-right, on = bottom-to-top. Party can hold its own (key is in the healthBar override section).
        healthVerticalFill = false,

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
        -- Uniform Icon Anchoring: icons/text anchor as if no power bar existed, so per-role power bars never shift them.
        powerUniformAnchors = false,
        extendHealthBehindPower = false,  -- health spans full frame; power bar overlays it

        -- Top Name Bar: reserves height from the frame TOP (as the power bar does from the bottom); suppresses the in-frame Name.
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
        -- Heal Absorb Text (1:1 with Health Text): amount in short/full format, hidden at zero. Red default = healer-UI convention.
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
        -- Overshield = absorb exceeding empty health, backfilling over current health.
        -- Off: absorbs fill only the empty part (and on Default Blizz Frames the glow line stays pinned right).
        showOvershield   = true,
        healAbsorbStyle  = "clean",
        healAbsorbOpacity = 75,
        healAbsorbColor  = { r = 0.8, g = 0.15, b = 0.15 },
        healPrediction   = false,
        healPredOpacity  = 75,
        healPredColor    = { r = 102/255, g = 243/255, b = 102/255 },
        -- Absorb / heal absorb placement, independent per bar: "overlay" (over
        -- the health fill, default), "right" / "left" (from that frame edge).
        absorbEdgeMode     = "overlay",
        healAbsorbEdgeMode = "overlay",
        -- Lift the heal-absorb overlay above the dispel gradient (off = below dispel).
        healAbsorbOverDispel = false,
        -- Black backing behind the heal-absorb texture (all styles); 0 = off.
        healAbsorbBgOpacity = 25,
        -- Reduced max-health overlay: always right-anchored, styled like Heal
        -- Absorb but with a dedicated "Max Health Stripes" texture, no placement option.
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
        roleIconBehindBorder = false,  -- drop the carrier below the hover/target raise so borders draw over the icon
        showRoleForTank    = true,
        showRoleForHealer  = true,
        showRoleForDPS     = false,
        showRaidMarker   = true,
        raidMarkerSize   = 16,
        raidMarkerPosition = "center",  -- "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom"
        raidMarkerOffsetX  = 0,
        raidMarkerOffsetY  = 0,
        -- Ping marker: the mark a group member's ping puts on the pinged unit's frame (Blizzard art, 30 = native size)
        showPingMarker     = true,
        pingMarkerSize     = 30,
        pingMarkerPosition = "center",
        pingMarkerOffsetX  = 0,
        pingMarkerOffsetY  = 0,
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
        -- Group numbers (raid only). Size/color shared with the preview; the toggle gates only real frames (preview always shows them).
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
        -- 12.1 dispel ring thickness in physical pixels (-1 follows the icon's own
        -- Border, 0 hides it). Stored explicitly rather than left to the `or 2`
        -- read fallback: ReloadPartyFrames temp-swaps party values onto db.profile
        -- and restores from a table keyed by the raid value, so a key with no
        -- default is absent from that table and its party value would stick.
        dispelIconBorderSize = 2,
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

        -- Debuffs
        debuffFilter     = "all",  -- "none", "all", "raid", "dispellable"
        hideLustDebuff   = true,
        -- CC Debuff Glow: glow displayed debuff icons whose aura is crowd control
        -- (Blizzard CROWD_CONTROL filter); mirrors CDM Buff Glow. 0 = None; style 1 = Pixel Glow.
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

        -- Buff Manager "Simple Setup": isolated namespace sharing no keys with
        -- bmIndicators or def*. Mirrors the Defensives & Externals controls but drives the simple grid of the spec's tracked buffs.
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

        -- Range & misc
        oorAlpha         = 0.4,
        -- showTooltip is the on/off fallback the "Show Raid Frames Tooltip"
        -- dropdown derives from (ns._ResolveTooltipMode); picking an option writes
        -- tooltipMode = always|outOfCombat|outOfBossCombat|never. Raid/party only.
        showTooltip      = true,
        freeRightClickCamera = false,  -- right-click + drag over a raid/party frame turns the camera (mouselook)

        -- Preview mode: "real", "overlay", "none"
        previewMode       = "overlay",

        -- Raid size overrides: { [10] = { width=X, height=Y }, ... }
        raidSizeOverrides = nil,
        autoResizeIndicators = false,
        -- Tracked Buffs (Buff Manager) auto-resize ("Auto Resize Icons" dropdown); nil = on.
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
        partyFlipGrowth   = false,  -- false=default growth, true=DOWN->UP / RIGHT->LEFT flip, "centered"=stack centered in the 5-slot container
        partyHideSelf     = false,
        partyUnlockPos    = nil,
        -- Party mirror of autoResizeTrackedBuffs ("Auto Resize Icons", Party tab); nil = on.
        partyAutoResizeTrackedBuffs = true,
    }
}

-------------------------------------------------------------------------------
--  State tables
-------------------------------------------------------------------------------
local allButtons     = {}   -- flat list of all created buttons
local unitToButton   = {}   -- unitToken -> button map (rebuilt on roster change)
ns._xfUnitToButton   = {}   -- unitToken -> Extra Frames duplicate (XF.CAP-bounded;
                            -- owned by XF_Apply, never by the rebuild paths)
local separatedHdrs  = {}   -- [1..8] group headers
local containerFrame = nil  -- top-level positioning frame
ns._flatButtons      = {}   -- buttons owned by the flat (merged) header
ns._flatHeader       = nil  -- single header for merge-groups mode
ns._flatGfStr        = nil  -- merged groupFilter LayoutGroups would write (Self Position fallback)
local eventFrame     = CreateFrame("Frame")
local unitTrackers   = {}  -- [unitToken] = tracker frame
local inCombat       = false

-------------------------------------------------------------------------------
--  Tooltip mode resolver. tooltipMode = always | outOfCombat | outOfBossCombat
--  | never; governs ONLY raid/party frame tooltips (gated in their own OnEnter,
--  no global hook). Unset derives: showTooltip=false -> never; global "show in
--  combat" -> always; else outOfCombat. `s` = a scaled raid/party/extra proxy
--  or db.profile. On ns so OnEnter can reach it (local cap).
-------------------------------------------------------------------------------
ns._ResolveTooltipMode = function(s)
    if not s then return "outOfCombat" end
    local m = s.tooltipMode
    if m ~= nil then return m end
    if s.showTooltip == false then return "never" end
    if EllesmereUIDB and EllesmereUIDB.showUnitTooltipsInCombat then return "always" end
    return "outOfCombat"
end

-- Whether the frame's UNIT tooltip is allowed now (mode + combat state). Unit
-- tip only: aura-icon tips obey their own section's "Hide Tooltips" toggle.
function ns.RaidFrameTooltipAllowed(button)
    local fd = button and ns.GetFFD and ns.GetFFD(button)
    local s = (fd and (fd._isParty and ns._scaledPartyProxy
        or (fd._isExtra and ns._scaledExtraProxy) or ns._scaledProfile))
        or ns._scaledProfile
    -- The Blizz UI Enhanced peek modifier lifts the mode so a hidden tip can still be read on hover, matching the global tooltips.
    if EllesmereUI._tooltipPeekHeld and EllesmereUI._tooltipPeekHeld() then return true end
    local ttMode = ns._ResolveTooltipMode(s)
    if ttMode == "never" then return false end
    if ttMode == "outOfCombat" and inCombat then return false end
    if ttMode == "outOfBossCombat" and ns._inBossCombat then return false end
    return true
end

-------------------------------------------------------------------------------
--  Suppress Blizzard raid frames (zero CPU when ours are active). Raid
--  container unconditional here; party is conditional, from UpdateVisibility.
-------------------------------------------------------------------------------
ns._blizzHiddenParent = CreateFrame("Frame", nil, UIParent)
ns._blizzHiddenParent:SetAllPoints()
ns._blizzHiddenParent:Hide()

do
    local hookedFrames = {}
    local looseFrames = {}

    local watcher = ns.TakeShell()
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

    -- Suppress the Edit Mode selection overlay (mover box). Hide/reparent is NOT
    -- enough (Edit Mode force-shows registered systems): scale the system frame
    -- down so its Selection child renders invisibly small, plus alpha 0. SetScale
    -- is combat-blocked but Edit Mode is always entered OOC, so skip it when
    -- locked. pcall-wrapped: protected Blizzard frames.
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

    -- CONTAINER always suppressed (we replace the raid unit frames). The MANAGER
    -- (left sidebar: ready check / markers) is deliberately NOT touched; the
    -- shared "Hide Blizzard Party Panel" toggle (EllesmereUI_BlizzardParty.lua)
    -- owns it. OnShow re-asserts the scale-down: Edit Mode re-shows the system
    -- (and may reset its scale) on every entry.
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
            -- Party Edit Mode overlay: only while we own the party frames (from
            -- UpdateVisibility), so untouched Blizzard party frames keep movers.
            -- PartyFrame = standard; CompactPartyFrame = raid-style (may be absent).
            suppressEditModeOverlay(PartyFrame)
            suppressEditModeOverlay(_G["CompactPartyFrame"])
        end
    end

    -- Edit Mode re-shows registered systems (and can reset scale) on every entry,
    -- so one call at load is not enough: re-apply on PLAYER_ENTERING_WORLD,
    -- EDIT_MODE_LAYOUTS_UPDATED, EditModeManagerFrame show/hide, and the
    -- CompactRaidFrameManager_UpdateShown global.
    local function applyEditModeOverlaySuppression()
        -- Manager omitted on purpose: the shared "Hide Blizzard Party Panel" toggle owns it.
        suppressEditModeOverlay(CompactRaidFrameContainer)
        -- Party overlays unconditional: Blizzard's party frame is empty/hidden when solo, so no group gate is needed.
        suppressEditModeOverlay(PartyFrame)
        suppressEditModeOverlay(_G["CompactPartyFrame"])
    end
    ns._ApplyEditModeOverlaySuppression = applyEditModeOverlaySuppression

    local editModeWatcher = ns.TakeShell()
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
--  Physical pixel snapping. PP.Scale uses PanelPP.mult, which can be 1 even
--  when the frame's effective scale is not 1.0; this snaps to the container's
--  real physical pixel grid via EllesmereUI.PP.perfect (real PP, not PanelPP).
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
    -- Seed from the shared catalogue INTO the existing file-scope tables
    -- (their identity is load-bearing: resolver closures capture them).
    local t, n, o = EllesmereUI.BuildBarTextureTables(true)
    for k, v in pairs(t) do healthBarTextures[k] = v end
    for k, v in pairs(n) do healthBarTextureNames[k] = v end
    for i, k in ipairs(o) do healthBarTextureOrder[i] = k end
    -- RF-only divergence: "none" is a real solid texture here, not nil.
    healthBarTextures["none"] = "Interface\\Buttons\\WHITE8X8"

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

-- Vertical health fill: SetOrientation drives the fill AXIS. Raid and party
-- resolve through the caller's settings table (party gets its own when the
-- Health Bar section is unsynced). On ns (200-local cap).
ns.RF_IsVerticalFill = function(s)
    return ((s or db.profile).healthVerticalFill) and true or false
end

-- Fill-texture rotation, DERIVED (never set standalone) so it cannot go stale against
-- the bar axis or a texture swap. Stretch textures (shield.tga, striped3, blizzard,
-- WHITE8X8, every health texture) are one image scaled to the fill rect, drawn
-- wide-and-short, so a tall bar MUST rotate them or they smear. Tiled textures
-- (stripedReversed, the large* stripe sets, striped-maxhp, the modern absorb) repeat at
-- native size on BOTH axes and are correct at any bar shape -- rotating fights the
-- tiling and stretches them. Tiling is read off the LIVE fill texture, so this stays
-- correct no matter which style function last touched the bar.
ns.RF_ApplyFillRotation = function(bar)
    if not (bar and bar.SetRotatesTexture) then return end
    local vert = bar.GetOrientation and bar:GetOrientation() == "VERTICAL"
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local tiled = fill and ((fill.GetHorizTile and fill:GetHorizTile())
                         or (fill.GetVertTile and fill:GetVertTile()))
    bar:SetRotatesTexture((vert and not tiled) and true or false)
end

-------------------------------------------------------------------------------
--  Health-fill tint overlays
--
--  "Health Bar Color" indicators paint over the health FILL. A flat
--  SetColorTexture slab erases the bar's shading, so a tinted frame reads as a
--  solid block beside untinted ones; the overlay borrows the bar's own fill
--  texture instead and recolors it with a vertex color.
--
--  The overlay is anchored to the fill texture, so it inherits the bar's fill
--  geometry for free: these fills clip by resizing rather than by moving their
--  tex coords (measured -- identical coords at full and at half fill), so the
--  overlay stretches exactly as the bar art does with nothing to update per tick.
--  The coords are copied anyway so anything the orientation pass does to them
--  comes along, which is also why the refresh runs after that pass.
--
--  Live BM/DM slots register on the bar, so a Health Bar Texture change can
--  re-anchor them to the new fill object and repaint (ReanchorAbsorbToFill for
--  frames built through StyleButton, FB.ApplyStyle for Focus/Boss). The options
--  previews are rebuilt wholesale and need no refresh.
-------------------------------------------------------------------------------

-- host and owner are kept on the overlay rather than in the entry, so a cleared
-- entry can be rebuilt by the next paint without losing either. host is stored only
-- when it is NOT the overlay itself -- the Debuff Manager hangs its overlay off a
-- wrapper frame, and that wrapper is what a fill swap has to re-anchor.
ns.RF_RegisterBarTint = function(bar, tex, host, owner)
    if not (bar and tex) then return end
    if host and host ~= tex then tex._euiTintHost = host end
    if owner then tex._euiTintOwner = owner end
    local reg = bar._euiBarTints
    if not reg then
        reg = setmetatable({}, { __mode = "k" })
        bar._euiBarTints = reg
    end
    if reg[tex] == nil then reg[tex] = {} end
end

-- Called when a container that owned overlays on this bar is released. Engine aura
-- buttons are never freed, so their overlays would otherwise pile up one set per
-- rebuild -- an indicator edit or a spec change is enough -- and every later layout
-- pass would walk the dead ones. Entries are re-added by the next paint.
--
-- Scoped to the owner being released. Clearing the whole registry would also drop
-- a live overlay belonging to another owner, and an overlay that is displayed but
-- not repainted never re-registers -- the next Health Bar Texture change would
-- then skip it and leave it on the old art.
ns.RF_ClearBarTints = function(bar, owner)
    local reg = bar and bar._euiBarTints
    if not (reg and owner) then return end
    for tex in pairs(reg) do
        if tex._euiTintOwner == owner then reg[tex] = nil end
    end
end

ns.RF_TintOverBarFill = function(tex, bar, r, g, b, a)
    if not tex then return end
    ns.RF_RegisterBarTint(bar, tex)
    local reg = bar and bar._euiBarTints
    local ent = reg and reg[tex]
    -- Stored pre-multiply: the refresh path calls back in with these, so folding
    -- the fill opacity in here would compound it on every pass.
    if ent then ent.r, ent.g, ent.b, ent.a = r, g, b, a end
    -- Inherit the bar's configured Fill Opacity, so a tinted frame is as
    -- translucent as its untinted neighbours instead of the one solid bar in the
    -- group. Read from the stamp the style pass leaves, NOT from the live fill
    -- colour: _ApplyHealthBg drives that alpha down to 0.3 offline and 0.5 dead,
    -- and nothing repaints tints when a unit reconnects, so a tint painted during
    -- either would latch dimmed. Dark Mode is deliberately not inherited -- it
    -- dims the fill texture, and a colour the user picked should not be
    -- auto-dimmed.
    if bar then a = a * (bar._euiFillOpacity or 1) end
    local fill = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local path = fill and fill.GetTexture and fill:GetTexture()
    if not path then
        -- Reset both: a texcoord from the textured branch survives the swap, and
        -- SetColorTexture bakes the color into the texture rather than into the
        -- vertex color, so a stale vertex color would multiply it.
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetColorTexture(r, g, b, a)
        tex:SetVertexColor(1, 1, 1, 1)
        return
    end
    tex:SetTexture(path)
    if fill.GetTexCoord then tex:SetTexCoord(fill:GetTexCoord()) end
    tex:SetVertexColor(r, g, b, a)
end

-- Repaint BEFORE re-anchoring, and re-anchor with a bare SetAllPoints: the caller
-- isolates this, and a ClearAllPoints that succeeded ahead of a denied SetAllPoints
-- would strand the overlay with no anchor at all for the rest of the session.
ns.RF_RefreshOneBarTint = function(bar, tex, ent, fill)
    if ent.r then ns.RF_TintOverBarFill(tex, bar, ent.r, ent.g, ent.b, ent.a) end
    if fill then (tex._euiTintHost or tex):SetAllPoints(fill) end
end

-- Isolated per entry: the overlay can hang off an engine aura button, and this
-- runs from bare ReloadFrames calls where a throw would abort the styling loop
-- mid-iteration. RF_TintOverBarFill only ever rewrites an entry it was handed, so
-- the walk cannot gain keys mid-iteration.
ns.RF_RefreshBarTints = function(bar)
    local reg = bar and bar._euiBarTints
    if not reg then return end
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    for tex, ent in pairs(reg) do
        pcall(ns.RF_RefreshOneBarTint, bar, tex, ent, fill)
    end
end

ns.RF_ApplyHealthOrientation = function(bar, s)
    if not bar then return false end
    local vert = ns.RF_IsVerticalFill(s)
    bar:SetOrientation(vert and "VERTICAL" or "HORIZONTAL")
    ns.RF_ApplyFillRotation(bar)
    return vert
end

-- Resolve an absorb/heal/max-health style key to a texture path: built-ins from
-- ABSORB_STYLE_TEX, "sm:" SharedMedia keys through the health-bar lookup. Used
-- by live render AND preview so a saved SM key paints identically.
-- Caller-handled keys (blizzardModern / maxHealthStripes) never reach this.
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
-- health bar. On, returns _euiUniformRef (stamped at creation, spanning where
-- the bar would sit with NO power bar) so per-role power bars never shift
-- icons/text. Visuals (fills, absorbs, dispel) keep the real bar.
function ns.RF_AnchorHost(health, s)
    local ref = health and health._euiUniformRef
    if ref and s and s.powerUniformAnchors then return ref end
    return health
end

-- "Extend Health Bar Behind Power": the health-height inset layout sites subtract for
-- the power bar. On returns 0 -- health spans the full frame and the power bar (higher
-- frame level, own bg) draws over its bottom strip; off returns powerH untouched.
function ns.RF_HealthPowerInset(s, powerH)
    if s and s.extendHealthBehindPower then return 0 end
    return powerH
end

-- Live-render convenience: resolves the button's settings source (party/extra
-- proxies) before delegating to ns.RF_AnchorHost.
function ns.RF_AnchorHostFor(d)
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    return ns.RF_AnchorHost(d.health, s)
end

-- Role for POWER-BAR gating. Effective role (EllesmereUI.UnitEffectiveRole):
-- the player's spec wins over the assigned role, which covers both the solo
-- "NONE" case (a solo healer's mana bar must not fall through to the DPS
-- toggle) and a stale premade-listing role (listed as tank, playing dps).
-- Other units keep the assigned role.
ns._ResolvePowerRole = function(unit)
    return EllesmereUI.UnitEffectiveRole(unit)
end

-------------------------------------------------------------------------------
--  Raid size tier resolution: width/height for a group size from the defined
--  overrides, cascading toward 20-man (the base) when a tier is undefined.
--  Tiers: 10, 15, 20(base), 25, 30, 40
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

-- Effective raid head count for size breakpoints. With "Exclude Hidden Groups
-- from Size" on (default), members of subgroups hidden via Show Groups are not
-- counted, so the breakpoint reflects visible members only. Explicitly off:
-- returns GetNumGroupMembers() verbatim.
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
        -- Fail OPEN on nil subgroup: while the roster streams in after joining,
        -- GetRaidRosterInfo returns nil for unarrived members; dropping them
        -- undercounts the raid onto the wrong tier. Count unknowns as visible;
        -- the next roster pass refines downward.
        if not sub or vg[sub] ~= false then count = count + 1 end
    end
    -- Degenerate guard: every populated group hidden -> raw count, never a 0-man raid.
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

-- Classic health color curve: red (dead) -> yellow (mid) -> green (full). Built
-- once via C_CurveUtil and passed to UnitHealthPercent, which handles secret
-- values internally and returns a clean ColorMixin.
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

-- Custom Dynamic Colors: the Classic path with user-chosen stops. Live frames feed a C_CurveUtil
-- curve to UnitHealthPercent (secret-value safe); cached, rebuilt only when one of the three
-- colors changes. do-block keeps the cache state off the main-chunk local budget.
do
    local DEF100 = { r = 0, g = 1, b = 0 }
    local DEF50  = { r = 0xEC/255, g = 0xEC/255, b = 0x32/255 }
    local DEF0   = { r = 0xE3/255, g = 0x30/255, b = 0x30/255 }
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

    -- Clean-number interpolation matching the curve, for previews where the
    -- percent is a known fake (0-1): linear 0/50 below half, 50/100 above.
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

-- Class Color Reactive: the Custom Dynamic gradient whose 100% stop is the
-- unit's CLASS color -- full health reads as class identity, wounds bleed
-- into the reactive palette, fully reactive by 40%. One engine curve cached
-- per class token; the fingerprint names every input (0%/50% stops + the
-- class color, so Custom Class Colors edits rebuild too). Secret-safe: the
-- curve is evaluated inside UnitHealthPercent exactly like Classic/Dynamic.
do
    local DEF50 = { r = 0xEC/255, g = 0xEC/255, b = 0x32/255 }
    local DEF0  = { r = 0xE3/255, g = 0x30/255, b = 0x30/255 }
    local GRAY  = { r = 0.5, g = 0.5, b = 0.5 }
    local curves = {}   -- classToken -> { curve, r, g, b (class color used) }
    local r0, g0, b0, r50, g50, b50
    function ns.GetClassReactiveCurve(s, classToken)
        local EllesmereUI = ns.EllesmereUI  -- upvalue read, not a global read (see taint note at top)
        s = s or db.profile
        local c0  = s.dynamicColor0  or DEF0
        local c50 = s.dynamicColor50 or DEF50
        if not (r0 == c0.r and g0 == c0.g and b0 == c0.b
            and r50 == c50.r and g50 == c50.g and b50 == c50.b) then
            wipe(curves)
            r0, g0, b0    = c0.r, c0.g, c0.b
            r50, g50, b50 = c50.r, c50.g, c50.b
        end
        local cc = EllesmereUI.GetClassColor(classToken) or GRAY
        local e = curves[classToken]
        if not (e and e.r == cc.r and e.g == cc.g and e.b == cc.b) then
            local curve = C_CurveUtil.CreateColorCurve()
            curve:SetType(Enum.LuaCurveType.Linear)
            -- Front-loaded class return: full reactive at 40% health, and the
            -- 0.75 stop carries 75% class weight, so identity snaps back
            -- quickly (40->75% climbs 0->75% class, 75->100% eases the rest).
            curve:AddPoint(0,    CreateColor(c0.r,  c0.g,  c0.b,  1))
            curve:AddPoint(0.4,  CreateColor(c50.r, c50.g, c50.b, 1))
            curve:AddPoint(0.75, CreateColor(
                c50.r + (cc.r - c50.r) * 0.75,
                c50.g + (cc.g - c50.g) * 0.75,
                c50.b + (cc.b - c50.b) * 0.75, 1))
            curve:AddPoint(1,    CreateColor(cc.r,  cc.g,  cc.b,  1))
            e = { curve = curve, r = cc.r, g = cc.g, b = cc.b }
            curves[classToken] = e
        end
        return e.curve
    end

    -- Clean-number twin for previews (fake 0-1 percents), mirroring the curve
    -- above: reactive 0-stop -> mid-stop below 40% health, front-loaded class
    -- weight above (75% class by 75% health, easing in the rest to 100%).
    function ns.ResolveClassReactiveColor(s, classToken, pct01)
        local EllesmereUI = ns.EllesmereUI  -- upvalue read, not a global read (see taint note at top)
        s = s or db.profile
        local cc = (classToken and EllesmereUI.GetClassColor(classToken)) or GRAY
        local c0  = s.dynamicColor0  or DEF0
        local c50 = s.dynamicColor50 or DEF50
        if pct01 >= 0.4 then
            local w
            if pct01 >= 0.75 then
                w = 0.75 + (pct01 - 0.75)
            else
                w = (pct01 - 0.4) / 0.35 * 0.75
            end
            return c50.r + (cc.r - c50.r) * w,
                   c50.g + (cc.g - c50.g) * w,
                   c50.b + (cc.b - c50.b) * w
        end
        local t = pct01 / 0.4
        return c0.r + (c50.r - c0.r) * t,
               c0.g + (c50.g - c0.g) * t,
               c0.b + (c50.b - c0.b) * t
    end
end

-- Dark mode colors come from the global per-profile palette via GetDarkModeFill()/GetDarkModeBg(),
-- fetched live at each use so settings changes show on the next refresh. Opacity honored here
-- (RF + UF); only Resource Bars keep their own alpha.

-- Paints the health-bar background (and dims the fill) for life/connection state. Dead/offline:
-- bg covers the FULL bar (tint reads even at full last-known health), fill dims. Alive: bg covers
-- only the missing-health portion so it never bleeds behind the fill during the OOR fade.
-- Centralized so the full update and the lightweight UNIT_HEALTH update (which owns
-- death/resurrect transitions) stay in lockstep -- else a resurrect arriving only via UNIT_HEALTH
-- strands the tint. Colors overridable via the Status Colors swatch in Extras; inline fallbacks
-- allocate only when the DB key is missing. On ns (local cap).
function ns._ApplyHealthBg(d, health, s, unit, connected, deadOrGhost)
    local EllesmereUI = ns.EllesmereUI  -- upvalue read, not a global read (see taint note at top)
    local bg = d.bg
    if connected == nil then connected = UnitIsConnected(unit) end
    if deadOrGhost == nil then deadOrGhost = UnitIsDeadOrGhost(unit) end
    -- Dead/offline: bg covers the FULL bar, fill dims. State+color stamped so
    -- a repeated tick in the same state re-applies nothing; entering either
    -- state clears the alive-path anchor/color stamps AND the fill-color
    -- stamp in _UpdateButtonHealth (the tint here overwrote its work).
    if not connected or deadOrGhost then
        local c = (not connected) and (s.statusColorOffline or { r = 0x66/255, g = 0x66/255, b = 0x66/255 })
            or (s.statusColorDead or { r = 0x24/255, g = 0x17/255, b = 0x17/255 })
        local st = (not connected) and 3 or 2
        if d._bgSt ~= st or d._bgR ~= c.r or d._bgG ~= c.g or d._bgB ~= c.b then
            d._bgSt, d._bgR, d._bgG, d._bgB = st, c.r, c.g, c.b
            d._bgTex, d._bgA = nil, nil
            d._hcR = nil
            if bg then
                bg:ClearAllPoints(); bg:SetAllPoints(health)
                bg:SetColorTexture(c.r, c.g, c.b, 1)
            end
            if health then
                if st == 3 then health:SetStatusBarColor(0.3, 0.3, 0.3, 0.3)
                else health:SetStatusBarColor(0.3, 0.3, 0.3, 0.5) end
            end
        end
        return
    end
    if not bg then return end
    -- Alive: the bg covers only MISSING health, so it hangs off the far side of the
    -- fill: the fill's right edge normally, its top edge on a vertical bar. The
    -- anchor set only changes when the fill texture object or the axis does, so it
    -- is stamped instead of being re-cleared and re-set on every health tick.
    local vert = health.GetOrientation and health:GetOrientation() == "VERTICAL"
    local tex = health:GetStatusBarTexture()
    if d._bgSt ~= 1 or d._bgTex ~= tex or d._bgVert ~= vert then
        d._bgSt, d._bgTex, d._bgVert = 1, tex, vert
        d._bgA = nil
        bg:ClearAllPoints()
        if vert then
            bg:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
            bg:SetPoint("BOTTOMRIGHT", tex, "TOPRIGHT", 0, 0)
        else
            bg:SetPoint("TOPLEFT", tex, "TOPRIGHT", 0, 0)
            bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
        end
    end
    local br, bgr, bb, ba
    if s.healthColorMode == "dark" then
        br, bgr, bb, ba = EllesmereUI.GetDarkModeBg()
    else
        -- Class-colored when bgClassColored, else custom (GetBgColor handles the secret-value
        -- guard + alpha = bgDarkness). MUST match the layout-pass and preview paths or this
        -- refresh clobbers the class-colored bg.
        br, bgr, bb, ba = ns.GetBgColor(unit, s)
    end
    if d._bgR ~= br or d._bgG ~= bgr or d._bgB ~= bb or d._bgA ~= ba then
        d._bgR, d._bgG, d._bgB, d._bgA = br, bgr, bb, ba
        bg:SetColorTexture(br, bgr, bb, ba)
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
    elseif mode == "classReactive" then
        -- Class color at full health bleeding into the reactive palette as the
        -- unit takes damage (fully reactive by 40%); engine-evaluated per-class
        -- curve, so secret health never touches Lua.
        local _, classToken = UnitClass(unit)
        if classToken and not issecretvalue(classToken) then
            local color = UnitHealthPercent(unit, true, ns.GetClassReactiveCurve(s, classToken))
            if color and color.GetRGB then
                return color:GetRGB()
            end
        end
        return 0.5, 0.5, 0.5
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
-- live frames (via ResolveDisplayName) and every preview surface. Skips secret
-- strings entirely (#, string.byte and string.sub all throw on secrets), so a
-- secret name shows verbatim and uncapped. nameMaxLength 0 = off. On ns (local cap).
-- Takes the caller's settings table `s` so a party override applies correctly.
function ns.CapName(display, s)
    if type(display) ~= "string" then return display end
    if issecretvalue and issecretvalue(display) then return display end
    if display == "" then return display end
    s = s or (db and db.profile)
    local maxLen = s and s.nameMaxLength or 15
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

-- Fraction of the frame width the NAME text may fill before auto-truncating
-- (1.0 = full width). Every name-width SetWidth routes through this knob;
-- health text keeps its own inline budget. On ns (local cap).
ns.RF_NAME_WIDTH_FRACTION = 1.0

-- Display name for a unit. Nickname sources in order: Northern Sky Raid Tools (NSAPI), MethodInternal
-- (EasyNicknameAPI), TimelineReminders, the Liquid addon (LiquidAPI), then RakGaming Aliases
-- (RG_UnitName); falls back to the short character name. NSAPI
-- gets our addon key "EUI" (it has a dedicated per-addon setting + EUI_NICKNAME_TOGGLE callback):
-- NSAPI:GetName self-gates on its global nicknames toggle AND that checkbox and returns the short
-- name when unset, falling through to the next source. Every source gates itself entirely (no
-- EUI-side toggle); pcall keeps a misbehaving external API from breaking name rendering.
local function ResolveDisplayName(unit, applyCap, s)
    local name = UnitName(unit) or ""
    local display
    if NSAPI and NSAPI.GetName then
        local ok, dn = pcall(NSAPI.GetName, NSAPI, name, "EUI")
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" and dn ~= name then
            display = dn
        end
    end
    -- MethodInternal nicknames (EasyNicknameAPI), second source.
    if not display and EasyNicknameAPI and EasyNicknameAPI.GetNicknameForUnitForSurface then
        local ok, dn, handled = pcall(
            EasyNicknameAPI.GetNicknameForUnitForSurface, unit, "raidFrames")
        if ok and handled == true then
            if type(dn) == "string"
               and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
                display = dn
            else
                display = name
            end
        end
    end
    -- TimelineReminders, gated by its own EllesmereUI checkbox. GetNickname falls back to the
    -- plain unit name when none is set, so HasNickname is checked first to keep the Ambiguate path.
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
    -- The Liquid addon's LiquidAPI.GetNicknameForEllesmereUI takes the raw UnitName string and returns a nickname or
    -- nil (unset / disabled provider-side / secret or empty name) -- it gates itself. pcall-wrapped
    -- (dot call, single arg, not a method); result re-checked as a clean non-empty string.
    if not display and LiquidAPI and LiquidAPI.GetNicknameForEllesmereUI then
        local ok, dn = pcall(LiquidAPI.GetNicknameForEllesmereUI, name)
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
            display = dn
        end
    end
    -- Final alias source, RakGaming Aliases (RGA), gated on ns._rgaNick (maintained by
    -- RegisterRGALIASNicknames + RGA's module callbacks: true only while RGA is present AND its
    -- "ellesmereui" module is enabled), so this hot path costs one flag read and never dereferences
    -- RGA's settings shape. dn ~= name keeps the Ambiguate path for unaliased units.
    if not display and ns._rgaNick then
        local ok, dn = pcall(RG_UnitName, unit)
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" and dn ~= name then
            display = dn
        end
    end
    if not display then
        if Ambiguate then name = Ambiguate(name, "short") end
        display = name
    end
    -- Cap only the in-frame name (applyCap), not the top name bar banner.
    if applyCap then display = ns.CapName(display, s) end
    return display
end

-- Background color: class color when bgClassColored, else the custom bg color.
-- Returns r, g, b, a (alpha = bgDarkness). Mirrors the health-fill class option.
function ns.GetBgColor(unit, s)
    s = s or db.profile
    local a = (s.bgDarkness or 50) / 100
    if s.bgClassColored and unit and UnitExists(unit) then
        local _, classToken = UnitClass(unit)
        -- classToken can be secret (out-of-range/uninspectable units) and indexing GetClassColor's
        -- tables with one throws "table index is secret"; fall back to custom bg when secret/nil.
        if classToken and not issecretvalue(classToken) then
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then return cc.r, cc.g, cc.b, a end
        end
    end
    -- Partial/imported profiles can lack the key (field report 2026-08-16).
    local c = s.customBgColor or defaults.customBgColor
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
        if classToken and not issecretvalue(classToken) then
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
    if classToken and not issecretvalue(classToken) then
        local cc = EllesmereUI.GetClassColor(classToken)
        if cc then return cc.r, cc.g, cc.b end
    end
    return 1, 1, 1
end

-- Reserve the Top Name Bar's height from the TOP of a frame and style it. Shared by real buttons
-- and every preview so they never drift. Layout + appearance only; the caller sets name text +
-- color. Returns the reserved height (0 when disabled; health re-anchors flush to the top).
local function LayoutTopNameBar(s, baseH, powerH, healthBar, tnb, tnbBg, tnbText)
    local enabled = s.topNameBarEnabled
    local topBarH = enabled and PixelSnap(s.topNameBarHeight or 20) or 0
    if healthBar then
        local parent = healthBar:GetParent()
        healthBar:ClearAllPoints()
        healthBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -topBarH)
        healthBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -topBarH)
        healthBar:SetHeight(PixelSnap(baseH - ns.RF_HealthPowerInset(s, powerH) - topBarH))
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

-- Live name refresh for every raid + party button. Fired by the external
-- nickname-provider callbacks so changes apply instantly without a /reload.
function ns.RefreshAllNames()
    local s = db and db.profile
    if not s then return end
    local function refresh(unit, btn)
        local d = GetFFD(btn)
        -- Party buttons read through the party proxy so a per-party cap applies.
        local bs = (d and d._isParty) and (ns._scaledPartyProxy or s) or s
        if d and d.nameText then
            d.nameText:SetText(ResolveDisplayName(unit, true, bs))
            local nr, ng, nb = GetNameColor(unit, bs)
            d.nameText:SetTextColor(nr, ng, nb)
        end
        if d and d.topNameBarText and bs.topNameBarEnabled then
            d.topNameBarText:SetText(ResolveDisplayName(unit, false, bs))
            local tr, tg, tb = GetTopNameBarColor(unit, bs)
            d.topNameBarText:SetTextColor(tr, tg, tb)
        end
    end
    for unit, btn in pairs(unitToButton) do refresh(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do refresh(unit, btn) end
end

-- Health text color (mirrors GetNameColor). Default mode "custom" = white.
local function GetHealthTextColor(unit, s)
    s = s or db.profile
    local mode = s.healthTextColorMode or "custom"
    if mode == "accent" then
        local r, g, b = EllesmereUI.ResolveActiveAccent()
        if r then return r, g, b end
        return 1, 1, 1
    elseif mode == "class" then
        local _, classToken = UnitClass(unit)
        if classToken and not issecretvalue(classToken) then
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
        if classToken and not issecretvalue(classToken) then
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

-- Anchor a FontString to the health bar using the shared 8-position scheme. Mirrors FB.AnchorText
-- (defined later, after the friendly-boss subsystem) so heal-absorb text in the early frame-build
-- path anchors identically. Optional width clamps long "amount"-mode values like health text.
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

-- Format a heal-absorb amount into a FontString. mode: "amount" (full), "short" (abbreviated like
-- 240k), "none"/nil (blank). C_StringUtil.TruncateWhenZero blanks at zero; its result (and GetText
-- after) is a SECRET string for a secret absorb, so ONLY feed it to SetText or test truthiness --
-- never compare it (== "" taints). "short" gates on GetText truthiness alone (non-nil exactly when
-- non-zero) before abbreviating.
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

-- Update one button's heal-absorb text with the correct scaled profile. Called from the
-- absorb-only event path (UNIT_HEAL_ABSORB_AMOUNT_CHANGED), which runs no full button update.
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

-- Resolve a dispel type's color: user value (via the proxy `s`) falling back to the DISPEL_COLORS
-- default. Returns nil for an unknown/nil type so callers keep their own fallback behavior.
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

-- Power type + color + bounds (+ the opt-in power-colored bg) for a button's
-- power bar: identity-class state that only moves on UNIT_DISPLAYPOWER, an
-- occupant change or a full paint -- Blizzard's CompactUnitFrame recolors
-- power on exactly those edges -- so the per-tick UNIT_POWER_UPDATE path pushes
-- the value alone. Stamps d._pwType (nil = not derived for this occupant).
-- force = full paint: settings may have changed, so the bg re-tints even when
-- the type/darken stamps still match. On ns (200-local cap).
ns._RFPowerTypeEdge = function(d, unit, force)
    local pType = UnitPowerType(unit) or 0
    local pr, pg, pb = GetPowerColor(unit)
    d._pwType = pType
    d.power:SetMinMaxValues(0, 100)
    d.power:SetStatusBarColor(pr, pg, pb, 1)
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    if s.powerBgPowerColored and d.powerBg then
        local f = ns.EllesmereUI.GetPowerBgDarkenFactor()
        if force or d._pwBgTintType ~= pType or d._pwBgTintF ~= f then
            d.powerBg:SetColorTexture(pr * f, pg * f, pb * f, (s.powerBgDarkness or 70) / 100)
            d._pwBgTintType = pType
            d._pwBgTintF = f
        end
    end
end

-------------------------------------------------------------------------------
--  Absorb style application. Single-fill styles match the unit-frame look; the
--  RF-only compound "Blizzard (Modern)" style layers a tiled stripe fill over a
--  solid base, diverging from UnitFrames (which offers only "Blizzard").
-------------------------------------------------------------------------------

-- Configure ONE absorb StatusBar for the compound "Blizzard (Modern)" style: tiled 9196ff striped
-- fill over an opaque c6c8ff base (._modernBase, colored once at creation). Re-establishes the
-- striped fill (the bar's fill is shared with other styles, so it must be restored) and anchors the
-- base to the fill rect so it rides the clip/mask geometry the secret SetValue drives -- no Lua
-- math on the secret. Colors hardcoded; ignores user color/opacity.
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
    ns.RF_ApplyFillRotation(bar)  -- tiled: stays unrotated on a vertical bar
end

-- Hide the modern solid base on any non-modern style, so switching away leaves no stale layer.
ns.HideModernAbsorbBase = function(bar)
    if bar and bar._modernBase then bar._modernBase:Hide() end
end

local function ApplyAbsorbStyle(absorbBar, style, settings)
    if not absorbBar then return end
    local mask = absorbBar._absorbMask
    local fw = absorbBar._forward

    -- "Default Blizz Frames": forward (missing-health shield) = compound modern texture;
    -- backfill (overshield over existing health) = flat 10% white overlay, not the texture.
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
    local tiled = (style == "striped" or style == "stripedReversed" or style == "stripedThick" or style == "stripedThickR" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR")
    local fill = absorbBar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 1)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
        if mask then fill:AddMaskTexture(mask) end
    end
    -- New fill object + new tiling state: re-derive rotation.
    ns.RF_ApplyFillRotation(absorbBar)
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
        ns.RF_ApplyFillRotation(fw)
    end
end

ns.ApplyHealAbsorbStyle = function(haBar, style, settings)
    if not haBar then return end
    local tex = ns.ResolveAbsorbStyleTex(style, "Interface\\Buttons\\WHITE8X8")
    local alpha = settings and (settings.healAbsorbOpacity or 75) / 100 or 0.65
    local hc = settings and settings.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
    -- "Default Blizz Frames" / "Large Outlined Stripes" heal styles are pre-colored: forced white tint (swatch disabled).
    if style == "healBlizzModern" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" then hc = { r = 1, g = 1, b = 1 } end
    local mask = haBar._absorbMask
    haBar:SetStatusBarTexture(tex)
    haBar:SetStatusBarColor(hc.r or 0.8, hc.g or 0.15, hc.b or 0.15, alpha)
    local tiled = (style == "striped" or style == "stripedReversed" or style == "stripedThick" or style == "stripedThickR" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR")
    local fill = haBar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 2)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
        if mask then fill:AddMaskTexture(mask) end
    end
    ns.RF_ApplyFillRotation(haBar)
end

-- Reduced max-health overlay style: the heal-absorb texture set plus a dedicated "Max Health
-- Stripes" texture; always right-anchored (caller sets ReverseFill). Swatch tints, slider =
-- texture opacity (backing opacity is the caller's). Pre-colored styles force white.
ns.ApplyMaxHealthStyle = function(bar, style, settings)
    if not bar then return end
    style = style or "maxHealthStripes"
    local tex, tiled
    if style == "maxHealthStripes" then
        tex = "Interface\\AddOns\\EllesmereUIRaidFrames\\Media\\striped-maxhp.png"
        tiled = true
    else
        tex = ns.ResolveAbsorbStyleTex(style, "Interface\\Buttons\\WHITE8X8")
        tiled = (style == "striped" or style == "stripedReversed" or style == "stripedThick" or style == "stripedThickR" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR")
    end
    local alpha = settings and (settings.maxHealthOpacity or 100) / 100 or 1
    local mc = settings and settings.maxHealthColor or { r = 0.7, g = 0.1, b = 0.1 }
    if style == "healBlizzModern" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" then mc = { r = 1, g = 1, b = 1 } end
    bar:SetStatusBarTexture(tex)
    bar:SetStatusBarColor(mc.r or 0.7, mc.g or 0.1, mc.b or 0.1, alpha)
    local fill = bar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 3)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
    end
    ns.RF_ApplyFillRotation(bar)
end

-------------------------------------------------------------------------------
--  Create absorb bar (dual clip-frame, secret-value safe). Matches UnitFrames
--  exactly. Clip frames do "min(absorb, curHealth)" and "max(0, absorb -
--  curHealth)" visually, so no Lua arithmetic on secret values.
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

    -- Filled-region bound for the backfill, as a MASK shadowing curClip's rect
    -- instead of scissor clipping: in restricted content the clip frame's
    -- secret-anchored scissor stops rendering its children entirely (bisect
    -- strips: a plain bar under curClip died while a masked twin on the health
    -- bar rendered), which is why the overshield vanished whenever a
    -- dispellable debuff -- restricted content's signature -- was up. The mask
    -- tracks curClip through every ReanchorAbsorbToFill re-anchor for free.
    -- CLAMPTOBLACKADDITIVE is what makes the mask a BOUND: the default wrap
    -- extends the white edge pixels past the mask's rect, so the backfill
    -- rendered unmasked over missing health (doubled onto the forward bar).
    -- NEAREST because WHITE8X8 is 8x8: stretched over the rect, bilinear blends
    -- the edge texel with the black border across the outer 1/16 of each side,
    -- and that alpha ramp read as a shadow along the overshield's edges.
    local curMask = healthBar:CreateMaskTexture()
    curMask:SetAllPoints(curClip)
    curMask:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")

    -- Backfill bar (overflow): grows into filled health from the right edge.
    -- Child of the HEALTH BAR, not curClip -- the filled-region bound rides
    -- curMask above (the scissor path is dead in restricted content).
    local backfillBar = CreateFrame("StatusBar", nil, healthBar)
    backfillBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local bfFill = backfillBar:GetStatusBarTexture()
    if bfFill then bfFill:SetDrawLayer("ARTWORK", 1); bfFill:AddMaskTexture(absorbMask); bfFill:AddMaskTexture(curMask) end
    -- Compound "Blizzard (Modern)" solid base (c6c8ff): BEHIND the striped fill (ARTWORK sublevel
    -- 0 < fill 1). Masked once here; shown only for that style, re-anchored to the fill each update.
    local bfBase = backfillBar:CreateTexture(nil, "ARTWORK", nil, 0)
    bfBase:SetColorTexture(0.776, 0.784, 1.0, 1)
    if absorbMask then bfBase:AddMaskTexture(absorbMask) end
    bfBase:AddMaskTexture(curMask)
    bfBase:Hide()
    backfillBar._modernBase = bfBase
    backfillBar:SetStatusBarColor(1, 1, 1, 0.8)
    backfillBar:SetReverseFill(true)
    backfillBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
    backfillBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    backfillBar:SetWidth(healthBar:GetWidth())
    backfillBar:SetHeight(healthBar:GetHeight())
    -- Absorb tops the HP cluster: above heal absorb/prediction (healthBar+1) and reduced max health (+2).
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

    -- "Default Blizz Frames" spark: fixed 16px soft glow (cast_spark.tga, ADD) centered on the
    -- shield's left edge (the current-HP seam), half over health, half over shield. Its own host
    -- above the shield keeps the health-side half out of missClip; CENTER pinned to the forward
    -- bar's LEFT edge tracks the seam. A StatusBar fed the absorb with a tiny max fills 100% on
    -- ANY shield -- self-gates off the secret absorb, no boolean/mask.
    local sparkHost = CreateFrame("Frame", nil, healthBar)
    sparkHost:SetAllPoints(healthBar)
    sparkHost:SetClipsChildren(true)
    sparkHost:SetFrameLevel(healthBar:GetFrameLevel() + 4)
    -- Invisible gate bar (16px on the seam): binary fill -- full with ANY shield, zero with none. Only its fill GEOMETRY is used.
    local gateBar = CreateFrame("StatusBar", nil, sparkHost)
    gateBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    gateBar:SetStatusBarColor(1, 1, 1, 0)
    gateBar:SetSize(16, healthBar:GetHeight())
    gateBar:SetMinMaxValues(0, 1)
    gateBar:SetValue(0)
    gateBar:SetPoint("CENTER", forwardBar, "LEFT", -1, 0)
    -- Visible spark over the gate's fill rect (cast_spark.tga renders as a plain texture but not as a StatusBar fill, hence the split).
    local edgeSpark = sparkHost:CreateTexture(nil, "OVERLAY")
    edgeSpark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    edgeSpark:SetBlendMode("ADD")
    edgeSpark:SetAllPoints(gateBar:GetStatusBarTexture())
    edgeSpark:Hide()
    forwardBar._edgeSpark = edgeSpark
    forwardBar._edgeGate = gateBar
    -- Overshield spark: rides the backfill's LEFT edge (the shield's inner edge) while
    -- overshielding; the seam spark hides then, so only one spark is ever visible. Re-anchored each update.
    local bfSpark = sparkHost:CreateTexture(nil, "OVERLAY")
    bfSpark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    bfSpark:SetBlendMode("ADD")
    bfSpark:SetSize(16, healthBar:GetHeight())
    bfSpark:SetPoint("CENTER", forwardBar, "LEFT", -1, 0)
    bfSpark:Hide()
    forwardBar._bfSpark = bfSpark

    -- Absorb Bar: solid bar above the frame showing the shield amount, filling from the right edge.
    -- Always created hidden so toggling it on later needs no rebuild; UpdateAbsorb drives it.
    local topBar = CreateFrame("StatusBar", nil, button)
    topBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    topBar:SetStatusBarColor(1, 1, 1, 1)
    topBar:SetReverseFill(true)
    topBar:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 0)
    topBar:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 0)
    topBar:SetHeight(4)
    topBar:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    topBar:Hide()

    -- Heal Absorb Bar: second strip mirroring the Absorb Bar. Always created hidden; UpdateAbsorb drives it.
    local healTopBar = CreateFrame("StatusBar", nil, button)
    healTopBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    healTopBar:SetStatusBarColor(200/255, 29/255, 29/255, 1)
    healTopBar:SetReverseFill(true)
    healTopBar:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 0)
    healTopBar:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 0)
    healTopBar:SetHeight(4)
    healTopBar:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    healTopBar:Hide()

    -- Forward-declared so ReanchorAbsorbToFill captures these as UPVALUES: an undeclared name in
    -- the closure resolves to a nil global and the bar silently never re-anchors. The bars are
    -- created further down; until then the nil guards inside ReanchorAbsorbToFill skip them.
    local healAbsorbBar, healPredBar, healClip, reducedBar

    -- Re-anchor clip frames and forward bar to the current health fill texture.
    -- Must be called whenever SetStatusBarTexture replaces the fill object.
    local function ReanchorAbsorbToFill()
        local fill = healthBar:GetStatusBarTexture()

        -- Vertical fill: the whole HP cluster rotates with the health bar -- every anchor below is
        -- the horizontal layout axis-swapped (the fill's RIGHT "HP edge" that shields/heal
        -- absorb/prediction hang off becomes its TOP edge; frame right/left become top/bottom).
        -- Resolved live off the button's settings source so party keeps its own Health Bar section.
        local vs = d._isParty and ns._scaledPartyProxy
            or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
        local isVert = ns.RF_ApplyHealthOrientation(healthBar, vs)
        backfillBar._axisVert = isVert  -- read by the blizzardModern spark block

        -- Health Bar Color overlays track this bar's fill, so they follow the swap
        -- for the same reason the absorb cluster below does. After the orientation
        -- call, not before: the repaint copies the fill's tex coords, and that call
        -- is what rotates them.
        healthBar._euiFillOpacity = (vs.healthBarOpacity or 100) / 100
        ns.RF_RefreshBarTints(healthBar)
        -- Indexed, not ipairs: the creation-time call runs before the heal/max bars exist, and ipairs stops at the first nil.
        local axisBars = { backfillBar, forwardBar, healAbsorbBar, healPredBar, reducedBar }
        for i = 1, 5 do
            local b = axisBars[i]
            if b then
                b:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
                ns.RF_ApplyFillRotation(b)  -- derived: rotate stretch styles only
            end
        end

        if isVert then
            curClip:ClearAllPoints()
            curClip:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
            curClip:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
            missClip:ClearAllPoints()
            missClip:SetPoint("BOTTOMLEFT", fill, "TOPLEFT", 0, -1)
            missClip:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            forwardBar:ClearAllPoints()
            forwardBar:SetPoint("BOTTOMLEFT", fill, "TOPLEFT", 0, 0)
            forwardBar:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT", 0, 0)
            if healPredBar then
                healPredBar:ClearAllPoints()
                healPredBar:SetPoint("BOTTOMLEFT", fill, "TOPLEFT", 0, 0)
                healPredBar:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT", 0, 0)
            end
            -- Edge modes keep their key names: "right" = the far edge of the fill axis (top when vertical), "left" = the near one (bottom).
            local vAbsorbMode = db.profile.absorbEdgeMode or "overlay"
            backfillBar:ClearAllPoints()
            if vAbsorbMode == "right" or vAbsorbMode == "left" then
                curClip:ClearAllPoints()
                curClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                curClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
                if vAbsorbMode == "left" then
                    backfillBar:SetReverseFill(false)
                    backfillBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                    backfillBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
                else
                    backfillBar:SetReverseFill(true)
                    backfillBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                    backfillBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                end
            elseif vAbsorbMode == "overlayReverse" then
                -- Overlay Reverse, vertical axis: whole absorb fills DOWN into
                -- the fill from its top edge; default filled-region clip masks
                -- any excess (see the horizontal branch).
                backfillBar:SetReverseFill(true)
                backfillBar:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
                backfillBar:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
            else
                -- Overshield "From Left" on the vertical axis: excess grows
                -- from the bar's bottom (origin) edge -- see the horizontal
                -- branch for the anchor mechanics.
                local osm = db.profile.overshieldMode
                if osm == nil then osm = (db.profile.showOvershield == false) and "never" or "always" end
                if osm == "fromleft" and db.profile.absorbStyle ~= "blizzardModern" then
                    backfillBar:SetReverseFill(false)
                    backfillBar:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
                    backfillBar:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
                else
                    backfillBar:SetReverseFill(true)
                    backfillBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                    backfillBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                end
            end

            if healAbsorbBar then
                local vHealMode = db.profile.healAbsorbEdgeMode or "overlay"
                if healClip then
                    healClip:ClearAllPoints()
                    if vHealMode == "right" or vHealMode == "left" then
                        healClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                        healClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
                    else
                        healClip:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                        healClip:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
                    end
                end
                healAbsorbBar:ClearAllPoints()
                if vHealMode == "right" then
                    healAbsorbBar:SetReverseFill(true)
                    healAbsorbBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                    healAbsorbBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                elseif vHealMode == "left" then
                    healAbsorbBar:SetReverseFill(false)
                    healAbsorbBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                    healAbsorbBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
                else
                    healAbsorbBar:SetReverseFill(true)
                    healAbsorbBar:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
                    healAbsorbBar:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
                end
            end
            return
        end

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
        -- Shield absorb placement (independent of heal absorb): overlay = backfill into filled
        -- health from the HP edge (default); right/left = full bar filling from that frame edge.
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
        elseif absorbMode == "overlayReverse" then
            -- Overlay Reverse: the WHOLE absorb backfills from the health
            -- fill's leading edge INTO the fill. curClip keeps the default
            -- filled-region clip from above, so a shield larger than current
            -- health is masked at the frame edge -- nothing ever renders over
            -- missing health (the forward bar is hidden by the value pass,
            -- same as the edge modes).
            backfillBar:SetReverseFill(true)
            backfillBar:ClearAllPoints()
            backfillBar:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
            backfillBar:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
        else
            -- Overlay: curClip already clipped to the fill above. Overshield "From Left" uses the
            -- Overlay Reverse anchors with FORWARD fill: the bar's origin end sits one bar-width
            -- left of the fill edge, so exactly the excess past missing health emerges from the
            -- frame's left edge (the clip masks the rest). Default = right-anchored reverse fill
            -- (excess hangs left off the fill edge). Default Blizz Frames keeps the classic
            -- backfill -- its overshield spark machinery rides those anchors.
            local osm = db.profile.overshieldMode
            if osm == nil then osm = (db.profile.showOvershield == false) and "never" or "always" end
            backfillBar:ClearAllPoints()
            if osm == "fromleft" and db.profile.absorbStyle ~= "blizzardModern" then
                backfillBar:SetReverseFill(false)
                backfillBar:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
                backfillBar:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
            else
                backfillBar:SetReverseFill(true)
                backfillBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                backfillBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            end
        end

        -- Heal absorb placement (independent of shield absorb). Its own clip frame spans the full bar for right/left, filled health for overlay.
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
            -- Missing Health clamp: GetDamageAbsorbs' 2nd return is then the standard "overshield"
            -- boolean (absorb exceeds empty health), consistent in and out of combat. Bars get the
            -- FULL absorb (UnitGetTotalAbsorbs) so overflow/backfill still renders.
            hpCalc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)
        end
    end

    -- Heal absorb has its OWN clip frame (not the shield's curClip) so its placement is
    -- independent: overlay clips to filled health, right/left span the FULL bar (filled +
    -- missing). Bounds set per healAbsorbEdgeMode in ReanchorAbsorbToFill (initial = overlay).
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

    -- Black backing behind the heal-absorb texture (all styles; opacity = healAbsorbBgOpacity).
    -- UNDER the fill (ARTWORK sublevel 1 < the fill's 2), masked + SetAllPoints'd to the fill rect
    -- each update so it tracks the secret heal-absorb amount and collapses to nothing at zero.
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

    -- Reduced max health bar: black bg + red striped overlay on the right side (forward-declared above for ReanchorAbsorbToFill).
    reducedBar = CreateFrame("StatusBar", nil, healthBar)
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
--  Absorb Bar position. Positions: none / aboveRight / aboveLeft / topRight /
--  topLeft / rightVertical / leftVertical (vertical side bar; fill direction
--  from the per-bar grow-direction setting, default up).
-------------------------------------------------------------------------------
-- Absorb / Heal Absorb Bar position resolvers + strip layout. On ns (local cap). The legacy
-- absorbBarEnabled boolean maps to "aboveRight"/"none"; absorbBarPosition wins once set.
ns.GetAbsorbBarPosition = function(s)
    local p = s and s.absorbBarPosition
    if p then return p end
    return (s and s.absorbBarEnabled) and "aboveRight" or "none"
end
ns.GetHealAbsorbBarPosition = function(s)
    return (s and s.healAbsorbBarPosition) or "none"
end

-- Anchor/orient a strip bar (Absorb or Heal Absorb) for a position. "above*" sit on top of the
-- frame; "top*" inside at the top of the health bar, just above the absorb-style texture.
-- "belowAbsorb" (heal bar only) sits flush below the Absorb Bar's bottom edge, derived from its
-- POSITION not live visibility, so it never shifts up. "*Right" fills from the right edge.
-- "*Vertical" hugs the health bar's left/right edge: "height" acts as width and vertGrowDir
-- ("up" default / "down") picks the fill direction.
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
        -- "above" absorb bottom = frame top edge (yOff 0); "top" (inside) = one absorb-height below the top edge.
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
    -- Heal absorb is independent of the shield absorb: keep going whenever its style is on.
    local healOn = (s.healAbsorbStyle or "clean") ~= "none"
    -- Heal prediction is also independent, and shares this frame, so it must keep the frame alive too.
    local predOn = s.healPrediction and true or false
    if not styleOn and not barOn and not healOn and not healBarOn and not predOn then
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
    -- One heal-absorb fetch serves both the strip bar AND the overlay below.
    local healAbsorbAmt = (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit)) or 0

    -- Incoming heals, fetched here so the short-circuit below sees it too.
    -- predOn-GATED: with prediction off this stays a constant 0, so the fetch
    -- never runs and the memo's _mPred compares 0==0 forever -- heal traffic
    -- must not break the short-circuit for users without the feature.
    -- Calculator is refreshed above; legacy global only as its fallback.
    local incomingHeals = 0
    if predOn then
        if calc and calc.GetIncomingHeals then
            incomingHeals = calc:GetIncomingHeals() or 0
        elseif UnitGetIncomingHeals then
            incomingHeals = UnitGetIncomingHeals(unit) or 0
        end
    end

    -- Identical-state short-circuit: absorbs re-flush far more often than values change and every
    -- paint below is idempotent. Skip when values, health-bar size and the settings generation all
    -- match the last paint. SECRET-SAFE: secrets cannot be compared, so any secret input fails
    -- open to painting and poisons the memo for the next plain pass.
    local hpW, hpH = hp:GetWidth(), hp:GetHeight()
    local isSec = issecretvalue
    local anySec = isSec and (isSec(absorbAmt) or isSec(maxHealth)
       or isSec(healAbsorbAmt) or isSec(isClamped) or isSec(incomingHeals))
    -- Absorb-active lean flag: the health ride repaints absorbs ONLY while
    -- this is set (clamp state can flip with health while shielded; with no
    -- absorb, a health change alters nothing this function paints). Event
    -- branches arm it; a fresh PLAIN all-zero read here disarms; secret reads
    -- keep it armed (fail-open = today's always-paint behavior in combat).
    ab._paintAt = GetTime()
    if anySec then
        if not d._absActive then ns._AbArm(button, unit, d) end
    elseif (absorbAmt or 0) > 0 or (healAbsorbAmt or 0) > 0
        or incomingHeals > 0 or isClamped == true then
        if not d._absActive then ns._AbArm(button, unit, d) end
    else
        d._absActive = false
        ns._abArmed[button] = nil
    end
    if anySec then
        ab._mAbs = nil
    elseif ab._mAbs == absorbAmt and ab._mHeal == healAbsorbAmt
       and ab._mMax == maxHealth and ab._mClamp == isClamped
       and ab._mW == hpW and ab._mH == hpH
       and ab._mPred == incomingHeals
       and ab._mGen == ns._absorbGen then
        return
    else
        ab._mAbs, ab._mHeal, ab._mMax = absorbAmt, healAbsorbAmt, maxHealth
        ab._mClamp, ab._mW, ab._mH = isClamped, hpW, hpH
        ab._mPred = incomingHeals
        ab._mGen = ns._absorbGen
    end

    -- Absorb Bar: fed raw values (secret-safe); a zero absorb renders as an empty bar.
    if topBar then
        if barOn then
            -- Settings-derived pushes are GEN-GATED: they change only on settings writes (every RF
            -- options write bumps ns._absorbGen, see _BumpAbsorbGen), and unlike the value memo
            -- this gate survives combat secrecy (gen + frame sizes are never secret).
            if topBar._sGen ~= ns._absorbGen then
                topBar._sGen = ns._absorbGen
                local bc = s.absorbBarColor or { r = 1, g = 1, b = 1 }
                local bh = s.absorbBarHeight or 4
                local gd = s.absorbBarGrowDir or "up"
                -- Re-layout only when position/height/direction changes (no per-update SetPoint churn).
                if topBar._lpPos ~= barPos or topBar._lpH ~= bh or topBar._lpGD ~= gd then
                    topBar._lpPos = barPos; topBar._lpH = bh; topBar._lpGD = gd
                    ns.ApplyStripBarLayout(topBar, ab, button, barPos, bh, nil, nil, gd)
                end
                topBar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a or 1)
            end
            topBar:SetMinMaxValues(0, maxHealth)
            topBar:SetValue(absorbAmt)
            topBar:Show()
        else
            topBar:Hide()
        end
    end

    -- Heal Absorb Bar: strip showing the heal-absorb amount, independent of the heal-absorb overlay
    -- style (mirrors the Absorb Bar). "Below Absorb Bar" positions it relative to the Absorb slot.
    if healTopBar then
        if healBarOn then
            -- Same gen gate as the Absorb Bar above: settings-only pushes.
            if healTopBar._sGen ~= ns._absorbGen then
                healTopBar._sGen = ns._absorbGen
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
            end
            healTopBar:SetMinMaxValues(0, maxHealth)
            healTopBar:SetValue(healAbsorbAmt)
            healTopBar:Show()
        else
            healTopBar:Hide()
        end
    end

    -- Heal absorb (independent) draws under the shield bars (heal level +1 < shield +3) and runs
    -- before the shield gate below so it survives when the shield style is off.
    if ha then
        -- Settings-derived style/level/color pushes gen-gated; per-paint work below is value/size only.
        if ha._sGen ~= ns._absorbGen then
            ha._sGen = ns._absorbGen
            local haStyle = s.healAbsorbStyle or "clean"
            ha._styleNone = (haStyle == "none")
            if not ha._styleNone then
                local hc = s.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
                local hcR, hcG, hcB = hc.r or 0.8, hc.g or 0.15, hc.b or 0.15
                local haKey = (haStyle or "") .. (s.healAbsorbOpacity or 75) .. hcR .. hcG .. hcB
                if ha._lastHaKey ~= haKey then
                    ha._lastHaKey = haKey
                    ns.ApplyHealAbsorbStyle(ha, haStyle, s)
                    -- Retexture REPLACES the fill object: re-arm the backing's one-time fill anchor.
                    if ha._bg then ha._bg._fillAnchored = nil end
                end
                -- "Show Over Dispels" (default off): lift the heal-absorb overlay above the dispel
                -- gradient (button + LVL_DISPEL_OVERLAY + 1), still below border/text/auras and
                -- masked to the bar. Per-bar tracked: level touched only when the toggle flips.
                local overDispel = s.healAbsorbOverDispel == true
                if ha._lastOverDispel ~= overDispel then
                    ha._lastOverDispel = overDispel
                    if overDispel then
                        ha:SetFrameLevel(button:GetFrameLevel() + ns.LVL_DISPEL_OVERLAY + 1)
                    else
                        ha:SetFrameLevel(hp:GetFrameLevel() + 1)
                    end
                end
                -- Black backing: color from settings (gen-gated); the fill-rect anchor is permanent
                -- -- the statusbar texture region persists across SetValue, so anchor once.
                local hbg = ha._bg
                if hbg then
                    hbg:SetColorTexture(0, 0, 0, (s.healAbsorbBgOpacity or 25) / 100)
                    if not hbg._fillAnchored then
                        hbg._fillAnchored = true
                        hbg:SetAllPoints(ha:GetStatusBarTexture())
                    end
                end
            end
        end
        if ha._styleNone then
            ha:Hide()
        else
            if ha._szW ~= hpW or ha._szH ~= hpH then
                ha._szW = hpW; ha._szH = hpH
                ha:SetWidth(hpW); ha:SetHeight(hpH)
            end
            ha:SetMinMaxValues(0, maxHealth)
            ha:SetValue(healAbsorbAmt)
            ha:Show()
            local hbg = ha._bg
            if hbg then hbg:Show() end
        end
    end

    -- Shield style off: hide the in-frame shield bars. Heal absorb paints earlier in this
    -- function so it's untouched either way; heal prediction paints later, so only stop
    -- here if that's off too, or its block below never runs.
    if not styleOn then
        ab:Hide()
        if fw then fw:Hide() end
        if fw and fw._edgeSpark then fw._edgeSpark:Hide() end
        if fw and fw._bfSpark then fw._bfSpark:Hide() end
        if not predOn then return end
    end

    -- Bars track the health-bar size; size-gated (frame sizes are never secret, so it holds in combat).
    if ab._szW ~= hpW or ab._szH ~= hpH then
        ab._szW = hpW; ab._szH = hpH
        ab:SetWidth(hpW); ab:SetHeight(hpH)
        if fw then fw:SetWidth(hpW); fw:SetHeight(hpH) end
    end

    -- Settings-derived style + mode flags, gen-gated (see the Absorb Bar note).
    if ab._sGen ~= ns._absorbGen then
        ab._sGen = ns._absorbGen
        -- Re-apply style when style, color, or opacity changes
        local absStyle = s.absorbStyle
        local ac = s.absorbColor or { r = 1, g = 1, b = 1 }
        local absKey = (absStyle or "") .. (s.absorbOpacity or 90) .. ac.r .. ac.g .. ac.b
        if absStyle and absStyle ~= "none" and ab._lastAbsKey ~= absKey then
            ab._lastAbsKey = absKey
            ApplyAbsorbStyle(ab, absStyle, s)
            -- Retexture REPLACES fw's fill object: re-arm the modern base's one-time fill anchor.
            -- The seam spark's target (the gate bar's texture) is creation-static and never re-arms.
            if fw and fw._modernBase then fw._modernBase._fillAnchored = nil end
        end
        ab._absStyle = absStyle
        -- Show Overshield (three-way; legacy boolean preserved): the absorb exceeding empty
        -- health, backfilling over current health -- drawn by the backfill bar (ab) in overlay +
        -- Default-Blizz modes. "never" (old toggle OFF) feeds the backfill 0 so only empty health
        -- fills; "always" (old ON, default) keeps the classic fill-edge backfill; "fromleft"
        -- re-anchors it in the reanchor pass so the excess grows from the bar's origin edge.
        -- nil overshieldMode falls back to the old showOvershield boolean, so saved toggles keep
        -- their meaning. Right/left edge modes draw the WHOLE absorb through ab (fw hidden
        -- below) and are untouched -- overshield is meaningless there.
        local osm = s.overshieldMode
        if osm == nil then osm = (s.showOvershield == false) and "never" or "always" end
        ab._overshieldOn = osm ~= "never"
        ab._overlayLike = absStyle == "blizzardModern" or (s.absorbEdgeMode or "overlay") == "overlay"
        ab._edgeOverlay = (s.absorbEdgeMode or "overlay") == "overlay"
    end
    local absStyle = ab._absStyle
    local abValue = absorbAmt
    if not ab._overshieldOn and ab._overlayLike then abValue = 0 end

    -- Both bars get the raw absorb value and maxHealth; clip frames do the visual math, so no secret comparisons.
    ab:SetMinMaxValues(0, maxHealth)
    ab:SetValue(abValue)
    ab:Show()

    if fw then
        fw:SetMinMaxValues(0, maxHealth)
        fw:SetValue(absorbAmt)
        fw:Show()
    end
    -- Edge modes (right/left): the full-bar backfill shows the whole absorb, so the overlay-only forward bar is not needed.
    if not ab._edgeOverlay and fw then fw:Hide() end

    -- "Default Blizz Frames": backfill = 10% white overshield, forward = modern texture. The spark
    -- always rides the shield's LEFT edge: the seam spark (current-HP edge) self-gates on "has
    -- shield" and hides while overshielding; the overshield spark rides the backfill's left edge
    -- and shows only then. isClamped (the Missing-Health-clamp overshield boolean) flips between
    -- them secret-safely, so exactly one is ever visible.
    if absStyle == "blizzardModern" then
        -- Vertical fill: the shield rotates, but these 16px edge glows are pinned to the shield's
        -- LEFT edge and cannot follow a vertical seam; hide them rather than render sideways.
        if ab._axisVert and fw then
            if fw._edgeSpark then fw._edgeSpark:Hide() end
            if fw._bfSpark then fw._bfSpark:Hide() end
        elseif fw then
            -- Fill-rect anchors are permanent (statusbar textures persist across SetValue); sizes
            -- size-gated; the overshield spark's anchor moves only when Show Overshield flips.
            local fmb = fw._modernBase
            if fmb and not fmb._fillAnchored then
                fmb._fillAnchored = true
                fmb:SetAllPoints(fw:GetStatusBarTexture())
            end
            -- Seam spark: full 16px when any shield (binary gate), hidden while overshielding.
            local g, sp = fw._edgeGate, fw._edgeSpark
            if g and sp then
                if g._szH ~= hpH then g._szH = hpH; g:SetHeight(hpH) end
                g:SetValue(absorbAmt)
                if not sp._fillAnchored then
                    sp._fillAnchored = true
                    sp:SetAllPoints(g:GetStatusBarTexture())
                end
                if sp.SetAlphaFromBoolean then sp:SetAlphaFromBoolean(isClamped, 0, 1) else sp:SetAlpha(1) end
                sp:Show()
            end
            -- Overshield spark rides the backfill's LEFT edge (slides left as the overshield grows);
            -- with Show Overshield OFF the backfill is suppressed, so pin it to the health-bar
            -- RIGHT edge instead. Shown only while overshielding.
            local bsp = fw._bfSpark
            if bsp then
                if bsp._szH ~= hpH then bsp._szH = hpH; bsp:SetSize(16, hpH) end
                if bsp._ovOn ~= ab._overshieldOn then
                    bsp._ovOn = ab._overshieldOn
                    bsp:ClearAllPoints()
                    if bsp._ovOn then
                        bsp:SetPoint("CENTER", ab:GetStatusBarTexture(), "LEFT", -1, 0)
                    else
                        bsp:SetPoint("CENTER", ab, "RIGHT", -1, 0)
                    end
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
        -- Toggle + color gen-gated; size size-gated; value pushes live.
        if hpd._sGen ~= ns._absorbGen then
            hpd._sGen = ns._absorbGen
            hpd._on = s.healPrediction and true or false
            if hpd._on then
                local pc = s.healPredColor or { r = 102/255, g = 243/255, b = 102/255 }
                hpd:SetStatusBarColor(pc.r, pc.g, pc.b, (s.healPredOpacity or 75) / 100)
            end
        end
        if not hpd._on then
            hpd:Hide()
        else
            if hpd._szW ~= hpW or hpd._szH ~= hpH then
                hpd._szW = hpW; hpd._szH = hpH
                hpd:SetWidth(hpW); hpd:SetHeight(hpH)
            end
            hpd:SetMinMaxValues(0, maxHealth)
            hpd:SetValue(incomingHeals)
            hpd:Show()
        end
    end

    -- Reduced max health: styled overlay anchored to the right side. Texture/color/opacity/backing
    -- mirror Heal Absorb; re-styled only on change.
    local rmh = ab._reducedMax
    if rmh then
        -- Style key + backing color gen-gated; the fill-rect anchor is permanent.
        if rmh._sGen ~= ns._absorbGen then
            rmh._sGen = ns._absorbGen
            local rmhStyle = s.maxHealthStyle or "maxHealthStripes"
            rmh._styleNone = (rmhStyle == "none")
            if not rmh._styleNone then
                local mc = s.maxHealthColor or { r = 0.7, g = 0.1, b = 0.1 }
                local mcR, mcG, mcB = mc.r or 0.7, mc.g or 0.1, mc.b or 0.1
                local rmhKey = rmhStyle .. (s.maxHealthOpacity or 100) .. mcR .. mcG .. mcB
                if rmh._lastRmhKey ~= rmhKey then
                    rmh._lastRmhKey = rmhKey
                    ns.ApplyMaxHealthStyle(rmh, rmhStyle, s)
                    -- Retexture replaced the fill object: re-arm the backing anchor (re-anchored just below).
                    if ab._reducedMaxBg then ab._reducedMaxBg._fillAnchored = nil end
                end
                local rmhBg = ab._reducedMaxBg
                if rmhBg then
                    rmhBg:SetColorTexture(0, 0, 0, (s.maxHealthBgOpacity or 100) / 100)
                    if not rmhBg._fillAnchored then
                        rmhBg._fillAnchored = true
                        rmhBg:SetAllPoints(rmh:GetStatusBarTexture())
                    end
                end
            end
        end
        local lossPct = GetUnitTotalModifiedMaxHealthPercent and GetUnitTotalModifiedMaxHealthPercent(unit) or 0
        if not rmh._styleNone and lossPct > 0 then
            rmh:SetValue(lossPct)
            rmh:Show()
        else
            rmh:Hide()
        end
    end
end


-------------------------------------------------------------------------------
--  Debuff grid layout (shared by the live render and the options preview)
-------------------------------------------------------------------------------
-- Absorb paint coalescer (Blizzard's own CompactUnitFrame model: absorb /
-- heal-prediction repaints are "frequent and expensive, update once per frame
-- at most"). Event branches MARK; the flush paints each dirty button once,
-- at most a budget of them per render frame -- server batches land several
-- absorb-family events per button in one frame at raid scale, and only the
-- last paint renders. The budget is the backstop for a genuine event storm
-- (a raid-wide shield landing on everyone in one frame); the belt below
-- spreads its own marks across ticks so it never fills the budget itself.
-- The flush frame is hidden whenever the set is empty. On ns (200-local cap).
ns._abDirty = {}
ns._abFlushBudget = 20
ns._abFlush = CreateFrame("Frame")
ns._abFlush:Hide()
ns._abFlush:SetScript("OnUpdate", function(self)
    local dirty = ns._abDirty
    local left = ns._abFlushBudget
    for button in pairs(dirty) do
        dirty[button] = nil
        -- The button's CURRENT occupant, never the token captured at mark
        -- time: a header reassignment between mark and flush would paint the
        -- old occupant's absorb onto the new one.
        local unit = button:GetAttribute("unit")
        if unit then UpdateAbsorb(button, unit) end
        left = left - 1
        if left <= 0 then break end
    end
    -- Leftovers past the budget keep the frame shown for the next frame.
    if next(dirty) == nil then self:Hide() end
end)
function ns._MarkAbsorbDirty(button, unit)
    -- unit is kept for the callers' convenience; the flush re-reads the
    -- button's current occupant itself.
    ns._abDirty[button] = true
    ns._abFlush:Show()
end

-- Armed-members belt: covers the ONE transition with no event at all -- an
-- aura-granted shield expiring on its TIMER on an unhit, topped unit (VDH
-- Infernal Strike field report; damaged/healed units correct instantly via
-- the health/absorb events). One shared ticker exists only while some member
-- is armed and cancels itself when the armed set empties. Zero event
-- registrations, zero cost with no shields anywhere.
--
-- STAGGERED: the ticker runs at 0.1s and each tick visits one fifth of the
-- armed set (members whose ordinal in the walk matches the tick's phase), so
-- every member is still visited every 0.5s -- the accepted corner latency --
-- but the marks land in five different render frames instead of one. A
-- single 0.5s sweep re-marked the whole shielded roster at once, and because
-- that painted them together their stamps aged together, locking the burst
-- into a permanent 2 Hz rhythm no drain budget could break. Members painted
-- within 0.45s (event-active) are still skipped by the stamp compare.
-- Membership churn reshuffles the walk order harmlessly: a member is at worst
-- visited twice in a row or waits one extra sweep once.
ns._abArmed = ns._abArmed or {}
ns._abBeltPhase = 0
function ns._AbArm(button, unit, d)
    d._absActive = true
    ns._abArmed[button] = unit
    if not ns._abBelt and C_Timer then
        ns._abBelt = C_Timer.NewTicker(0.1, function()
            local now = GetTime()
            local phase = ns._abBeltPhase
            ns._abBeltPhase = (phase + 1) % 5
            local any = false
            local i = 0
            for btn, u in pairs(ns._abArmed) do
                any = true
                if i % 5 == phase then
                    local ab = GetFFD(btn).absorbBar
                    if not ab or (now - (ab._paintAt or 0)) > 0.45 then
                        ns._MarkAbsorbDirty(btn, u)
                    end
                end
                i = i + 1
            end
            if not any then
                ns._abBelt:Cancel()
                ns._abBelt = nil
            end
        end)
    end
end

-- Effective icon size for dispellable debuffs routed to their own anchor ("Dispellable Debuff
-- Location"): 0 = match the main Debuff Size. Reads scaled proxies transparently (the key is in
-- INDICATOR_SCALE_KEYS; 0 scales to 0, so the match sentinel survives). On ns (200-local cap).
function ns.DispellableDebuffSize(s)
    local v = s.dispellableDebuffSize
    if v and v > 0 then return v end
    return s.debuffSize or 18
end

-- Mirrors the Buff Manager's AnchorSimpleGrid. opts (optional) overrides pos/grow/ox/oy/size for a
-- sub-group (e.g. dispellable debuffs on their own anchor); spacing/wrap/perRow stay shared.
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

    -- Icon corner anchored to the same corner of the health bar. Every position is explicit, so the default fallback is only a safety net.
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

    -- Row-stack vector (perpendicular). CENTER growth stacks away from the
    -- position's own edge (ResolveFlowAnchor parity); wrap has no options
    -- setter and defaults to "UP", so letting it win here put this preview's
    -- rows on the opposite side from the live frame. Otherwise the explicit
    -- wrap direction wins, else derive away from the anchored edge.
    local svx, svy = 0, 0
    local wrap = s.debuffWrapDirection
    local centerSvy
    if grow == "CENTER" then
        if pos:find("top", 1, true) then centerSvy = -1
        elseif pos:find("bottom", 1, true) then centerSvy = 1 end
    end
    if     centerSvy       then svy = centerSvy
    elseif wrap == "UP"    then svy = 1
    elseif wrap == "DOWN"  then svy = -1
    elseif wrap == "RIGHT" then svx = 1
    elseif wrap == "LEFT"  then svx = -1
    elseif horizontal then
        if pos == "bottomleft" or pos == "bottom" or pos == "bottomright" then svy = 1 else svy = -1 end
    else
        if pos == "topright" or pos == "right" or pos == "bottomright" then svx = -1 else svx = 1 end
    end

    -- perRow == 1 is a single line ALONG the growth direction (no wrapping), keeping the growth control meaningful; >= 2 wraps into rows.
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
--  Right-click camera movement over raid/party frames: a global mouse watcher starts mouselook
--  when the right button is dragged past a small threshold over one of our unit buttons. It never
--  touches the secure buttons (no taint / click-cast interference); a right-click tap still menus.
-------------------------------------------------------------------------------
do
    local MOVE_THRESHOLD = 4
    local watcher = ns.TakeShell()
    local inLook = false
    local lastX, lastY = 0, 0

    local function stopLook()
        if inLook then MouselookStop(); inLook = false end
        watcher:SetScript("OnUpdate", nil)
    end

    -- True if the cursor is over one of our visible unit buttons (direct IsMouseOver test against the registry).
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

    -- Register the per-click global events only while the feature is on (zero cost when off). Call on toggle.
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

    -- Register our unit buttons so the free right-click camera watcher can tell when the cursor is
    -- over one. These are SecureGroupHeader/SecureUnitButton frames (Blizzard-owned), so membership
    -- lives in an external weak table, never a key on the button.
    ns._euiUnitButtons = ns._euiUnitButtons or setmetatable({}, { __mode = "k" })
    ns._euiUnitButtons[button] = true

    local s = db.profile
    -- The Anchor* closures below are stored on `d` and RE-CALLED after d._isParty / d._isExtra are
    -- set (StyleButton runs before that). They MUST resolve the settings source LIVE via LiveS()
    -- rather than capture this raid `s`, or party/extra frames would anchor every indicator, text
    -- and aura at the RAID position. The body keeps the raw `s` for creation-time sizing.
    local function LiveS()
        return d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    end
    local w = PixelSnap(s.frameWidth or 72)
    local h = PixelSnap(s.frameHeight or 46)
    -- The power bar is ALWAYS created (hidden) so a later swap into a power-enabled profile has a
    -- bar to show; UpdateButton drives per-role show/hide + matching health height. Health starts
    -- FULL height, else the bottom powerH strip shows dark bg as an "empty power bar" until the
    -- first UpdateButton (visible ~0.5s at login).
    local powerH = PixelSnap(s.powerHeight or 4)
    local healthH = h

    -- No SetSize here: sizing is window-phase work (combat-blocked), owned by
    -- ns._StyleButtonSecure below plus the header's initialConfigFunction.

    -- Background (visible behind the health bar where HP is missing)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local bgc = s.customBgColor or defaults.customBgColor
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
    -- Fill axis. StyleButton runs before d._isParty is set, so this uses the raid value;
    -- ReanchorAbsorbToFill re-resolves it against the button's real settings source each update.
    ns.RF_ApplyHealthOrientation(health, s)
    health:SetMinMaxValues(0, 100)
    health:SetValue(100)
    -- Pre-paint tint: a StatusBar texture renders WHITE (default vertex
    -- color) until the first content paint assigns the real class/reaction
    -- color a few frames after login (the styling drain). Start dark so the
    -- loading shell reads as calm empty frames instead of a flat white flash.
    health:SetStatusBarColor(0.12, 0.12, 0.12)
    d.health = health

    -- Full-height anchor reference for Uniform Icon Anchoring: top tracks the health bar (so the
    -- Top Name Bar inset carries over), bottom pins to the button -- exactly where the health bar
    -- sits with no power bar. ns.RF_AnchorHost swaps decorations onto it; _euiHealth points back
    -- for the few sites that must hug the real bar (full-overlay BM bars).
    d.uniformRef = CreateFrame("Frame", nil, button)
    d.uniformRef:SetFrameLevel(health:GetFrameLevel())
    d.uniformRef:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    d.uniformRef:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    health._euiUniformRef = d.uniformRef
    d.uniformRef._euiHealth = health

    -- Power bar: ALWAYS created, hidden, anchored to the button bottom for pixel alignment;
    -- UpdateButton's per-role gate shows/fills it. Unconditional creation is what lets a
    -- power-OFF login profile swap into a power-ON one.
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
        -- Pre-paint tint (see the health bar note above).
        power:SetStatusBarColor(0.12, 0.12, 0.12)
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

        -- Start hidden; UpdateButton shows it per role (wasShown=false there plain-snaps the first fill, no interpolation).
        power:Hide()
        pwBdrFrame:Hide()
    end

    -- Top Name Bar: ALWAYS created, hidden. The layout/refresh pass sizes, reserves and shows it from settings; UpdateButton sets the text.
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
    -- Styled via EllesmereUI.ApplyBorderStyle (PP or textured/SharedMedia) in UpdateBorder.
    -- Hover/Target are color states recolored onto this single border, not separate frames.

    -- Threat border
    local threatFrame = CreateFrame("Frame", nil, button)
    threatFrame:SetAllPoints(button)
    threatFrame:SetFrameLevel(button:GetFrameLevel() + 10)
    threatFrame:Hide()
    d.threatFrame = threatFrame
    if PP then PP.CreateBorder(threatFrame, 1, 0, 0, 1, 2) end

    -- Text carrier: name + health text in the text band (ns.LVL_TEXT) -- above every border incl. the raise, below the aura band.
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

    -- Role icon. Carrier sits in the text band (ns.LVL_AURA - 1 = ns.LVL_TEXT): above every border incl. the raise, auras still over it.
    -- Level is owned by AnchorRoleIcon (live-resolves the "Show Behind Border" option); this is just the initial value.
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
        -- "Show Behind Border": LVL_RAISE - 1 (9) sits just under the hover/target raise (+10,
        -- strips +11) and under the base border strips (+9 tie: strips are created after this
        -- carrier, so they win the tie and draw over the icon). Default: text band.
        roleCarrier:SetFrameLevel(button:GetFrameLevel()
            + (s.roleIconBehindBorder and (ns.LVL_RAISE - 1) or (ns.LVL_AURA - 1)))
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
        roleIcon:ClearAllPoints()
        -- The position key uppercases directly to a valid anchor point, so all
        -- 9 positions resolve like the Marker Position dropdown.
        local pos = (s.roleIconPosition or "bottomleft"):upper()
        roleIcon:SetPoint(pos, health, pos, s.roleIconOffsetX or 0, s.roleIconOffsetY or 0)
    end
    AnchorRoleIcon()
    d.AnchorRoleIcon = AnchorRoleIcon

    -- Marker carrier: above the frame border (incl. the hover/target raise) so the raid marker renders on top, not clipped behind it.
    local markerCarrier = CreateFrame("Frame", nil, button)
    markerCarrier:SetAllPoints(health)
    markerCarrier:SetFrameLevel(button:GetFrameLevel() + ns.LVL_MARKER)

    -- Leader/assistant icon. Own host frame (strata/level contract in ns.ApplyLeaderStrata) --
    -- NOT the marker carrier, whose high level keeps the raid marker always on top. Parented to
    -- the button so it tracks the frame; SetAllPoints(health) anchors it to the health bar.
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

    -- Combat icon (marker carrier, above the border): members currently affecting combat; 9-position anchor mirrors the role icon.
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

    -- Anchor name text: width-constrained region, position via a single anchor; JustifyH/V aligns within it.
    local function AnchorNameText()
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_AnchorHost(health, s)   -- Uniform Icon Anchoring host swap
        -- Text band level, re-applied on every reload; BEFORE the name-hidden early return because
        -- health text shares this carrier. Default sits under the aura band (ns.LVL_TEXT); "Show
        -- Above Icons" (name cog) lifts it above the band's children (+6 clears each aura unit's
        -- +1..+5), still below the marker carrier.
        textCarrier:SetFrameLevel(button:GetFrameLevel()
            + (s.nameTextAboveIcons and (ns.LVL_AURA + 6) or ns.LVL_TEXT))
        nameFS:ClearAllPoints()
        local pos = s.namePosition or "center"
        -- Top Name Bar enabled: it owns the unit name, suppress the in-frame name.
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

    -- Raise the border above neighbors while hovered/targeted: buttons share a frame level, so with
    -- small/negative Frame Spacing a neighbor's border would cover this frame's highlight.
    -- Highlight states bump it up, normal restores the base level. The PP container's level is
    -- fixed at creation, so it must be moved explicitly (borderFrame alone won't move it).
    local function ApplyBorderLevel(raised)
        if not (PP and d.borderFrame) then return end
        local pl = button:GetFrameLevel()
        local lvl = s.borderBehind and math.max(0, pl - 1) or (pl + (raised and ns.LVL_RAISE or 8))
        -- Hot path (every UpdateButton): skip the SetFrameLevel calls unless the level actually
        -- changes (hover/target transition or borderBehind toggle) -- common case is two getters.
        local container = PP.GetBorders(d.borderFrame)
        if d.borderFrame:GetFrameLevel() == lvl
           and (not container or container:GetFrameLevel() == lvl + 1) then
            return
        end
        d.borderFrame:SetFrameLevel(lvl)
        if container then container:SetFrameLevel(lvl + 1) end
    end

    -- Recolor the single border for the current state: hover > target > normal.
    local function ApplyBorderColor()
        if not (PP and d.borderFrame) then return end
        -- Re-called long after StyleButton: resolve LIVE (see LiveS note) so party overrides and profile swaps are honored.
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

    -- Apply border (style/size/texture/offsets via shared ApplyBorderStyle,
    -- then recolor for state). "Show Behind" lowers it below the frame; else +8.
    local function UpdateBorder()
        if not (PP and d.borderFrame) then return end
        -- Re-called from Reload paths long after StyleButton: resolve LIVE (see LiveS note).
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
        -- No-op while the power bar is hidden: the border frame always exists and unconditional
        -- callers must not draw over a hidden bar. UpdateButton calls this AFTER power:Show().
        if not PP or not d.powerBorderFrame or (d.power and not d.power:IsShown()) then return end
        -- Re-called long after StyleButton: resolve LIVE (see LiveS note) -- a captured `s` misses party overrides and profile swaps.
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
        -- Aura icons enable mouse and propagate motion up to this button, so entering an icon fires
        -- its OnEnter (aura tooltip) then bubbles here, clobbering it with the unit tooltip. Bail
        -- when the cursor is over one of our aura icons (stashed _tipIID).
        local foci = (GetMouseFoci and GetMouseFoci()) or (GetMouseFocus and { GetMouseFocus() })
        if foci then
            for _, mf in ipairs(foci) do
                if mf ~= self and mf._tipIID ~= nil then return end
            end
        end
        -- Unit-tooltip gating: see ns.RaidFrameTooltipAllowed. It reads through the party-aware
        -- proxy, NOT raw db.profile -- else party_<key> overrides from a custom party
        -- "Range & Tooltip" section are never seen.
        if not ns.RaidFrameTooltipAllowed(self) then return end
        local u = self:GetAttribute("unit")
        if u and UnitExists(u) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            -- Populate with a freshly-built clean literal token (GUID-matched) rather than the
            -- secure unit attribute: a literal "raidN"/"partyN"/"player" string lacks the
            -- secure-frame origin that makes GameTooltip:GetUnit() return a secret, so external
            -- tooltip addons can resolve the unit. Falls back to the attribute if no clean token.
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
            -- _G.RaiderIO resolves the tooltip unit via UnitTokenFromGUID(data.guid), which returns
            -- a SECRET token on our secure header frames, so its handler bails before drawing. When
            -- the tooltip unit is still secret, hand it our clean GUID-matched token via its public
            -- API. Gated on secret/absent GetUnit() so we never double-draw.
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

    -- Private auras: re-anchor whenever the secure header reassigns this button's unit. The engine
    -- drops private-aura anchors on unit reassignment (join/leave, sort, zone-in) even when the
    -- token string is unchanged, so the roster-event RebuildUnitMap path (which re-registers only
    -- when the token CHANGES) can leave the anchor dropped. OnAttributeChanged is the reliable
    -- per-button signal for exactly those reassignments. HookScript (NEVER SetScript) preserves the
    -- secure header's own handlers; helpers go through ns because they are defined later.
    button:HookScript("OnAttributeChanged", function(self, name)
        if name ~= "unit" then return end
        local u = self:GetAttribute("unit")
        if u and UnitExists(u) then
            -- Repaint + remap the instant the header (re)assigns this button, so a late assignment
            -- landing after the roster-timer rebuild can never leave it blank or route live events
            -- to a stale button.
            local d = GetFFD(self)
            -- Extra Frames duplicates never enter the real routing maps (one button per unit);
            -- XF_Apply owns ns._xfUnitToButton. The repaint/range work below is 1:1.
            if d._isExtra then
                -- map owned by XF_Apply
            elseif d._isParty then ns._partyUnitToButton[u] = self
            else unitToButton[u] = self end
            -- The secure header re-sets EVERY child's unit on EVERY re-process (each
            -- roster/name event, each sort attribute change), so most fires are a
            -- same-occupant re-confirm: same token AND same person as the last full
            -- paint. Nothing on the button changed -- its own unit events kept it
            -- current -- so only the routing write above and the container's
            -- assist gate run; the roster timer refreshes roster-derived state
            -- (leader/role/power layout) for unchanged occupants. A secret guid
            -- (never memoized) or a cleared/unstyled button takes the full path.
            local guid = UnitGUID(u)
            if issecretvalue(guid) then guid = nil end
            if guid and d._lastGuid == guid and d._lastUnit == u then
                if ns.RFC_OnUnitAssigned then ns.RFC_OnUnitAssigned(self, d, u) end
                return
            end
            -- Identity caches (class token, power type) drop on a real assignment:
            -- a different person can land on this button under the same token, and
            -- those derive again on the next tick for one cheap read each.
            d._clsTok = nil
            d._pwType = nil
            -- Drop the power-hide cache only on a token change -- else it forces an
            -- unconditional Show/Hide/SetHeight repaint, reintroducing the pop the
            -- deferred-power fix removed.
            if d._lastUnit ~= u then
                d._lastUnit = u
                d._appliedHidePower = nil
            end
            d._lastGuid = d.styled and guid or nil
            -- A ping marker belongs to the previous occupant; its pin-removed edge
            -- can no longer reach this button once the person moved.
            if d.pingFrame then d.pingFrame:Hide() end
            -- Containers first: the legacy refresh below still has restriction-era failure modes,
            -- and an error there must not starve the container of its unit assignment.
            if ns.RFC_OnUnitAssigned then ns.RFC_OnUnitAssigned(self, d, u) end
            if ns._RefreshAssignedButton then ns._RefreshAssignedButton(self, u) end
            if ns._UpdateButtonRange then ns._UpdateButtonRange(u, self) end
        else
            -- Cleared (button hidden by the header) or not yet resolvable: forget the
            -- painted occupant so the next assignment always takes the full path.
            GetFFD(self)._lastGuid = nil
        end
    end)

    -- 12.1 aura containers (container shell creation is combat-legal since
    -- 68914, so this rides the deferred styling pass with the rest of the body)
    if ns.RFC_SetupButton then
        ns.RFC_SetupButton(button, health, d)
    end
end

-------------------------------------------------------------------------------
--  Window-phase secure styling: everything on a fresh unit button that is
--  combat-blocked or writes secure state -- the size plus the click / ping /
--  click-cast tail (92 WrapScripts across the fleet live in CC_RegisterFrame).
--  Runs inside the login loading-screen window for every pre-spawned button;
--  the insecure visual body (StyleButton) runs in its own deferred
--  post-screen execution so the suite's shared login watchdog budget never
--  pays for it. Idempotent via d.securestyled, mirroring d.styled.
-------------------------------------------------------------------------------
ns._StyleButtonSecure = function(button)
    local d = GetFFD(button)
    if d.securestyled then return end
    d.securestyled = true
    local s = db.profile
    -- Raid sizes initially (party buttons get party sizing from ReloadPartyFrames).
    button:SetSize(PixelSnap(s.frameWidth or 72), PixelSnap(s.frameHeight or 46))

    -- Secure click: left=target, right=menu
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("type1", "target")
    -- Wildcard fallback so left-click target survives if the click-cast engine later clears type1.
    button:SetAttribute("*type1", "target")
    -- The engine gates SecureUnitButton's togglemenu; route right-click through a SecureActionButton
    -- proxy so the menu (and protected items like Set Focus) works without taint (*type2 = "click").
    if EllesmereUI.AttachSecureUnitMenu then
        EllesmereUI.AttachSecureUnitMenu(button)
    else
        button:SetAttribute("type2", "togglemenu")
        button:SetAttribute("*type2", "togglemenu")
    end

    -- Hover ping support, MIXIN-PURE: Blizzard's mixin methods run untouched
    -- (its GetTargetInfo resolves the unit from our "unit" attribute, which
    -- tracks the current occupant across sorts). Never override
    -- GetIsPingable/GetTargetInfo -- addon Lua in the ping path makes a
    -- secret GUID "inaccessible" to PingManager's securecopy (hard error +
    -- wedged listener), and a secrecy-guarded override deadens pings in all
    -- restricted content (both field-failed 2026-08-20). Writes are safe --
    -- our own spawned secure template, once per button, out of combat.
    if PingableType_UnitFrameMixin then
        Mixin(button, PingableType_UnitFrameMixin)
        button:SetAttribute("ping-receiver", true)
    end

    -- Register for click-casting (EUI built-in system)
    if ns.CC_RegisterFrame then
        ns.CC_RegisterFrame(button)
    elseif ClickCastFrames then
        ClickCastFrames[button] = true
    end
end

-------------------------------------------------------------------------------
--  Unit ping marker (parity with the default raid frames): when a group member
--  is pinged, the marker Blizzard draws on its compact frame appears on that
--  member's button here.
--
--  There is no direct channel: the pin events (UNIT_PING_PIN_ADDED / _REMOVED)
--  are restricted (addon RegisterEvent = forbidden, like the combat log) and
--  their only consumer template is forbidden to instantiate from addon code.
--  What IS reachable: the ping icon frame Blizzard already built on each of
--  its own compact frames is an ordinary object, and the raid module keeps
--  those frames alive -- the container is parked off-screen but the manager
--  still runs every roster layout through it (SetUpFrame fires per compact
--  frame per roster event). Blizzard's handler resolves the pinned GUID to a
--  frame and applies the showPingsOnRaidFrames CVar gate before it calls
--  ShowPing / ClearPing on that icon, so a secure post-hook on those two
--  methods hands us the texture kit and the owning compact frame's unit
--  token; the token maps to our button(s) and the same atlases go on our own
--  overlay. Hooks are installed per icon from a CompactUnitFrame_SetUpFrame
--  post-hook (once per icon object; nameplate compact frames are skipped for
--  good). Parity is total: same trigger, same CVar, same art. Zero work
--  between pings; overlays are built on first use.
--
--  Blizzard's own icon never clears when the pinged person moves to another
--  compact frame before the pin expires (the removed edge no longer matches
--  that frame), so a mirror needs two belts: our unit hook hides the overlay
--  on an occupant change, and a shown overlay expires on its own after the
--  longest a pin can live.
-------------------------------------------------------------------------------
ns._pingHooked  = setmetatable({}, { __mode = "k" })  -- Blizzard icon -> true (hooked) / false (never)
ns._pingLitBtn  = setmetatable({}, { __mode = "k" })  -- Blizzard icon -> our button it lit
ns._pingLitXf   = setmetatable({}, { __mode = "k" })  -- Blizzard icon -> Extra Frames duplicate it lit
ns.PING_EXPIRE  = 20

-- Position + size from the (party/extra-aware) settings: the same 9-point
-- anchor set as the raid marker, and the size as a factor of Blizzard's native
-- 30 so both atlases keep their proportions. Re-run by every reload path that
-- re-anchors the other indicators.
ns._RFAnchorPing = function(d)
    local pf = d.pingFrame
    if not pf then return end
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    local size = PixelSnap(s.pingMarkerSize or 30)
    pf:SetSize(size, size)
    pf._factor = size / 30
    local host = ns.RF_AnchorHost(d.health, s)
    local pos = s.pingMarkerPosition or "center"
    local ox = s.pingMarkerOffsetX or 0
    local oy = s.pingMarkerOffsetY or 0
    pf:ClearAllPoints()
    if pos == "topleft" then
        pf:SetPoint("TOPLEFT", host, "TOPLEFT", 2 + ox, -2 + oy)
    elseif pos == "top" then
        pf:SetPoint("TOP", host, "TOP", ox, -2 + oy)
    elseif pos == "topright" then
        pf:SetPoint("TOPRIGHT", host, "TOPRIGHT", -2 + ox, -2 + oy)
    elseif pos == "left" then
        pf:SetPoint("LEFT", host, "LEFT", 2 + ox, oy)
    elseif pos == "right" then
        pf:SetPoint("RIGHT", host, "RIGHT", -2 + ox, oy)
    elseif pos == "bottomleft" then
        pf:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 2 + ox, 2 + oy)
    elseif pos == "bottom" then
        pf:SetPoint("BOTTOM", host, "BOTTOM", ox, 2 + oy)
    elseif pos == "bottomright" then
        pf:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2 + ox, 2 + oy)
    else
        pf:SetPoint("CENTER", host, "CENTER", ox, oy)
    end
end

ns._RFPingOverlay = function(button, d)
    local pf = d.pingFrame
    if pf then return pf end
    pf = CreateFrame("Frame", nil, button)
    pf:SetFrameLevel(button:GetFrameLevel() + ns.LVL_MARKER + 1)
    pf:EnableMouse(false)
    pf.bg = pf:CreateTexture(nil, "BACKGROUND")
    pf.bg:SetPoint("CENTER")
    pf.icon = pf:CreateTexture(nil, "ARTWORK")
    pf.icon:SetPoint("CENTER")
    pf:Hide()
    d.pingFrame = pf
    ns._RFAnchorPing(d)
    return pf
end

ns._RFPingHide = function(button)
    if not button then return end
    local d = GetFFD(button)
    if d.pingFrame then d.pingFrame:Hide() end
end

-- Atlas at native size, then scaled by the configured factor (each texture
-- keeps its own native proportions). On ns (200-local cap).
ns._SetPingAtlas = function(tex, atlas, factor)
    tex:SetAtlas(atlas, true)
    if factor ~= 1 then
        local w, h = tex:GetSize()
        tex:SetSize(w * factor, h * factor)
    end
end

ns._RFPingLight = function(button, kit)
    local d = GetFFD(button)
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    if s.showPingMarker == false then return end
    local pf = ns._RFPingOverlay(button, d)
    local factor = pf._factor or 1
    ns._SetPingAtlas(pf.bg, "Ping_Frame_BG_" .. kit, factor)
    ns._SetPingAtlas(pf.icon, "Ping_Frame_" .. kit, factor)
    pf:Show()
    -- Expiry belt: a pin has a finite engine lifetime; if its removed edge can
    -- no longer reach this button (see header), the overlay still goes away.
    local stamp = (d._pingStamp or 0) + 1
    d._pingStamp = stamp
    C_Timer.After(ns.PING_EXPIRE, function()
        if d._pingStamp == stamp and d.pingFrame then d.pingFrame:Hide() end
    end)
end

ns._OnCufShowPing = function(icon, kit)
    if issecretvalue(kit) or type(kit) ~= "string" then return end
    local owner = icon:GetParent()
    local unit = owner and owner.unit
    if type(unit) ~= "string" then return end
    local btn = unitToButton[unit] or ns._partyUnitToButton[unit]
    local xf = ns._xfUnitToButton[unit]
    -- The icon re-lit for a different occupant: release what it lit before.
    local prevB, prevX = ns._pingLitBtn[icon], ns._pingLitXf[icon]
    if prevB and prevB ~= btn then ns._RFPingHide(prevB) end
    if prevX and prevX ~= xf then ns._RFPingHide(prevX) end
    if btn then ns._RFPingLight(btn, kit) end
    if xf then ns._RFPingLight(xf, kit) end
    ns._pingLitBtn[icon], ns._pingLitXf[icon] = btn, xf
end

ns._OnCufClearPing = function(icon)
    local b, x = ns._pingLitBtn[icon], ns._pingLitXf[icon]
    if not b and not x then return end
    ns._pingLitBtn[icon], ns._pingLitXf[icon] = nil, nil
    ns._RFPingHide(b)
    ns._RFPingHide(x)
end

ns._HookCufPingIcon = function(cuf)
    local icon = cuf and cuf.pingIconFrame
    if not icon then return end
    local state = ns._pingHooked[icon]
    if state ~= nil then return end
    -- Nameplate compact frames carry the same child; never ours to mirror.
    local okN, name = pcall(cuf.GetName, cuf)
    if okN and type(name) == "string" and name:find("^NamePlate") then
        ns._pingHooked[icon] = false
        return
    end
    local okF, forbidden = pcall(icon.IsForbidden, icon)
    if not okF or forbidden then
        ns._pingHooked[icon] = false
        return
    end
    ns._pingHooked[icon] = true
    hooksecurefunc(icon, "ShowPing", ns._OnCufShowPing)
    hooksecurefunc(icon, "ClearPing", ns._OnCufClearPing)
end

if type(CompactUnitFrame_SetUpFrame) == "function" then
    hooksecurefunc("CompactUnitFrame_SetUpFrame", ns._HookCufPingIcon)
end

-------------------------------------------------------------------------------
--  Role icon show/hide decision. Shared by UpdateButton and the lightweight
--  ns._UpdateRoleIcons combat-transition updater (lockstep). Honors the "Hide In
--  Combat" cog (hidden in combat, restored on PLAYER_REGEN_ENABLED). On ns (local cap).
-------------------------------------------------------------------------------
ns._UpdateRoleIcon = function(d, s, unit)
    local roleIcon = d.roleIcon
    if not roleIcon then return end
    local style = s.roleIconStyle or "modern"
    if style == "none" then roleIcon:Hide(); return end
    if s.roleIconHideInCombat and inCombat then roleIcon:Hide(); return end
    local role = EllesmereUI.UnitEffectiveRole(unit)
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
--  lightweight ns._UpdateLeaderIcons combat-transition updater (lockstep). Honors
--  the "Show In Combat" cog (default on; off = hidden in combat). On ns (local cap).
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
--  Combat icon show/hide decision: members currently affecting combat (M+ skip
--  awareness). Driven by UpdateButton and the lightweight ns._UpdateCombatIcons
--  updater (UNIT_FLAGS / regen). Texture Show/Hide is combat-legal. On ns (cap).
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
    -- Login gap guard: events registered in the loading-screen window can
    -- dispatch before the deferred styling pass builds this button's visual
    -- body; the pass ends with a full repaint, so skipping here loses nothing.
    if not d.styled then return end
    if not d.styled then return end

    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    -- Restore alpha respecting BM frame alpha + range alpha. nil rangeAlpha = managed by the
    -- secret-safe SetAlphaFromBoolean path; overriding it flashes full alpha until the next
    -- range ticker run (0.2s).
    if d.rangeAlpha then
        local baseA = button._bmSavedAlpha or 1
        button:SetAlpha(baseA * d.rangeAlpha)
    end

    -- Health: percent-based, secret-value safe; smooth interpolation optional.
    local smooth = s.smoothBars and Enum and Enum.StatusBarInterpolation
        and Enum.StatusBarInterpolation.ExponentialEaseOut

    local health = d.health
    -- Offline/dead units keep the gray tint _ApplyHealthBg owns. That tint is
    -- state-stamped there (applied on the transition, not on every call), so a
    -- full paint must never lay a class color over it -- the same split as
    -- Blizzard's UpdateHealthColor, which grays those units itself.
    local connected = UnitIsConnected(unit)
    local deadOrGhost = UnitIsDeadOrGhost(unit)
    if health then
        local pct = GetSafeHealthPercent(unit)
        health:SetMinMaxValues(0, 100)
        if smooth then
            health:SetValue(pct, smooth)
        else
            health:SetValue(pct)
        end

        if connected and not deadOrGhost then
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
    end

    -- Background (+ dead/offline status tint). Centralized in ns._ApplyHealthBg so the lightweight UNIT_HEALTH path stays in lockstep.
    ns._ApplyHealthBg(d, health, s, unit, connected, deadOrGhost)

    -- Power (filtered by role + hide if unit has no power)
    ns._PaintPower(button, d, s, unit)

    -- Absorb
    UpdateAbsorb(button, unit)

    ns._PaintButtonTail(button, d, s, unit)
end

-- Power bar layout + value: role-gated show/hide, health-height reflow, then the
-- value/color push. Split out of UpdateButton so the roster-state refresh
-- (ns._RefreshRosterState) can re-evaluate the role gate without a full paint.
-- On ns (200-local cap).
ns._PaintPower = function(button, d, s, unit)
    local power = d.power
    if power then
        local role = ns._ResolvePowerRole(unit)
        local showForRole = (role == "HEALER" and s.powerShowForHealer)
            or (role == "TANK" and s.powerShowForTank)
            or (role == "DAMAGER" and s.powerShowForDPS)
            or (role == "NONE" and s.powerShowForDPS)
        local pType = UnitPowerType(unit) or 0
        -- maxPower can be a secret number in group context; NEVER compare it in Lua. Treat the unit as powerless only on a CLEAN zero max.
        local pmx = UnitPowerMax(unit, pType)
        local cleanNoPower = (not issecretvalue(pmx)) and (not pmx or pmx == 0)
        local hidePower = not showForRole or cleanNoPower

        -- The Top Name Bar always reserves height from the top (anchor set by LayoutTopNameBar);
        -- subtract it so this per-unit power show/hide never expands health back over the bar.
        local tnbH = (s.topNameBarEnabled and PixelSnap(s.topNameBarHeight or 20)) or 0
        -- Extra Frames duplicates carry a per-group size offset (Extra Height), so the BUTTON is
        -- authoritative -- the shared setting would shrink health and leave a gap every update.
        local frameH = d._isExtra and button:GetHeight() or (s.frameHeight or 46)

        -- power:Show()/Hide() and the two SetHeight branches below reflow every decoration
        -- anchored to health (RF_AnchorHost anchors to the live health frame, not a stable
        -- ref). Applying that transition on every call lets an in-combat identity/roster event
        -- (role resync race, a GROUP_ROSTER_UPDATE storm at pull start) pop the whole button's
        -- content stack mid-fight. Only run the transition when hidePower actually changes, and
        -- defer it to combat end if combat is up; flushed from PLAYER_REGEN_ENABLED alongside
        -- the existing _rosterDirtyInCombat/_sizeTierDirtyInCombat deferrals. nil (fresh occupant,
        -- see the OnAttributeChanged reset) applies immediately so a first paint never inherits
        -- a stale layout -- EXCEPT when the health bar is already protected in combat: aura
        -- containers born in the secure environment anchor to it, and a mid-pull header
        -- reassignment (new occupant on a built button) would then write SetHeight under lockdown
        -- and be blocked. A first paint after a mid-combat reload has nothing anchored yet, so
        -- IsProtected is false there and it still applies.
        if d._appliedHidePower ~= hidePower then
            if inCombat and (d._appliedHidePower ~= nil or (d.health and d.health:IsProtected())) then
                d._powerDirtyInCombat = true
                ns._powerDirtyInCombat = true
            else
                d._appliedHidePower = hidePower
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
                        d.health:SetHeight(PixelSnap(frameH - ns.RF_HealthPowerInset(s, powerH) - tnbH))
                    end
                end
            end
        end

        -- Value/color refresh for the power bar in its last APPLIED shown state (not the
        -- freshly computed one), so a deferred transition keeps rendering the old state
        -- instead of updating a bar whose show/hide hasn't actually changed yet.
        if d._appliedHidePower == false then
            -- Smooth interpolation only animates correctly on a bar already shown last frame; on a
            -- fresh hidden->shown transition (profile swap replacing the fill texture) it leaves
            -- the fill at 0. Snap plainly on first show, smooth only after that.
            local wasShown = power:IsShown()
            power:Show()
            if d.UpdatePowerBorder then d.UpdatePowerBorder() end
            local smoothPower = wasShown and s.smoothPowerBars and Enum
                and Enum.StatusBarInterpolation
                and Enum.StatusBarInterpolation.ExponentialEaseOut
            -- Percent-based, secret-safe (mirrors health). UnitPower/UnitPowerMax can be secret in
            -- group context and cannot feed SetMinMaxValues; UnitPowerPercent evaluates the secret
            -- C-side against ScaleTo100 and returns a clean 0-100.
            -- Type + color + bounds (+ power-colored bg) through the shared edge,
            -- which stamps d._pwType for the per-tick value path; forced so a
            -- settings-driven full paint always re-tints.
            ns._RFPowerTypeEdge(d, unit, true)
            local ppct = UnitPowerPercent(unit, pType, true, CurveConstants.ScaleTo100)
            if smoothPower then
                power:SetValue(ppct, smoothPower)
            else
                power:SetValue(ppct)
            end
        end
    end
end

-- Roster-derived state only, for a button whose OCCUPANT did not change across a
-- roster event: leader/assist flag, assigned role (icon + role-gated power layout).
-- Everything else on the button is driven by its own unit events and was current
-- before the roster event, so the full paint (name resolution, absorb, texts,
-- marker, threat) is skipped. On ns (200-local cap).
ns._RefreshRosterState = function(button, d, s, unit)
    if not d.styled then return end
    ns._UpdateRoleIcon(d, s, unit)
    ns._UpdateLeaderIcon(d, s, unit)
    ns._PaintPower(button, d, s, unit)
end

-- One button's share of the coalesced roster pass (both roster timers). A paint
-- stamped at or after the cycle's arm time came from the assignment hook (the
-- occupant changed) or a full pass inside the cycle: nothing left to do. A stable
-- occupant (same guid as the hook's last full paint) gets the roster-state refresh.
-- Anything else -- no painted occupant on record, secret guid -- takes the full
-- paint, exactly the old pass. On ns (200-local cap).
ns._RosterPassPaint = function(button, unit)
    local d = GetFFD(button)
    local armAt = ns._rosterArmAt
    if armAt and d._fpAt and d._fpAt >= armAt and d._fpUnit == unit then return end
    local guid = d._lastGuid and UnitGUID(unit)
    if guid and not issecretvalue(guid) and d._lastGuid == guid and d._lastUnit == unit then
        local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
        ns._RefreshRosterState(button, d, s, unit)
    else
        UpdateButton(button)
    end
end

-- Second half of the full paint (after power + absorb). On ns (200-local cap).
ns._PaintButtonTail = function(button, d, s, unit)
    local EllesmereUI = ns.EllesmereUI  -- upvalue read, not a global read (see taint note at top)

    -- Name (visibility owned by AnchorNameText, which hides it when the Top Name Bar is enabled)
    if d.nameText then
        d.nameText:SetText(ResolveDisplayName(unit, true, s))
        local nr, ng, nb = GetNameColor(unit, s)
        d.nameText:SetTextColor(nr, ng, nb)
    end

    -- Top Name Bar text (unit name + class/custom color); size/anchor/visibility are LayoutTopNameBar's.
    if d.topNameBarText and s.topNameBarEnabled then
        d.topNameBarText:SetText(ResolveDisplayName(unit, false, s))
        local tr, tg, tb = GetTopNameBarColor(unit, s)
        d.topNameBarText:SetTextColor(tr, tg, tb)
    end

    -- Health text
    if d.healthText then
        local mode = s.healthTextMode or "none"
        -- Hide health %/value while dead/offline (status text shows DEAD/OFFLINE). UnitIsDeadOrGhost
        -- /UnitIsConnected return clean booleans for group units (only UnitIsAFK can be secret).
        if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
            d.healthText:SetText("")
        elseif mode == "percent" then
            local pct = GetSafeHealthPercent(unit)
            d.healthText:SetFormattedText("%.0f%%", pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "percentNoSign" then
            local pct = GetSafeHealthPercent(unit)
            d.healthText:SetFormattedText("%.0f", pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "number" then
            local curr = UnitHealth(unit, true)
            if curr and AbbreviateNumbers then
                d.healthText:SetText(AbbreviateNumbers(curr))
            elseif curr then
                d.healthText:SetFormattedText("%s", curr)
            end
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "numberPercent" then
            local curr = UnitHealth(unit, true)
            local pct = GetSafeHealthPercent(unit)
            local numStr = (curr and AbbreviateNumbers) and AbbreviateNumbers(curr) or tostring(curr or 0)
            d.healthText:SetFormattedText("%s | %.0f%%", numStr, pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "percentNumber" then
            local curr = UnitHealth(unit, true)
            local pct = GetSafeHealthPercent(unit)
            local numStr = (curr and AbbreviateNumbers) and AbbreviateNumbers(curr) or tostring(curr or 0)
            d.healthText:SetFormattedText("%.0f%% | %s", pct, numStr)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "missing" then
            local curr = UnitHealthMissing(unit, true)
            d.healthText:SetText(C_StringUtil.TruncateWhenZero(curr))
            if d.healthText:GetText() then
                if curr and AbbreviateNumbers then
                    d.healthText:SetText(AbbreviateNumbers(curr))
                elseif curr then
                    d.healthText:SetFormattedText("%s", curr)
                end
            end
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
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

    -- Status text (DEAD / OFFLINE / AFK). The SAME stamped painter as the
    -- UNIT_HEALTH path: the stamp records what is on screen, so a full paint
    -- that shows DEAD on a freshly assigned corpse leaves a stamp the later
    -- resurrect tick can see as a transition.
    ns._PaintStatusText(d, s, unit, UnitIsConnected(unit), UnitIsDeadOrGhost(unit))

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

    -- Target state: recolor the single border ONLY on a real target transition (hover takes
    -- priority in ApplyBorderColor), keeping recolor + level work off the per-update hot path.
    -- Both operands are clean booleans, so the compare never touches a secret value.
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
--  Dispel detection (secret-value safe). Handles border, overlay
--  (fill/full/gradient), and type icon.
-------------------------------------------------------------------------------

-- "By Me" dispel selection: UpdateDispelBorder queries auras with the
-- "HARMFUL|RAID_PLAYER_DISPELLABLE" filter directly, so the engine returns only
-- player-dispellable auras. Never branch on a (possibly secret) auraInstanceID:
-- negating IsAuraFilteredOutByInstanceID on it is nondeterministic for secret
-- boss debuffs (intermittent highlight).

-- Scratch color reused for dispel overlays (avoids a per-call table alloc).
ns._dispelScratch = ns._dispelScratch or {}
ns._dispelScratchDark = ns._dispelScratchDark or {}

-- Build the dispel-type -> color curves from the user's custom colors.
-- GetAuraDispelTypeColor evaluates the curve against an aura's (secret) dispel type internally, so
-- we never read the secret dispelName/dispelType. Indices are the engine dispel-type enum: 1 Magic,
-- 2 Curse, 3 Disease, 4 Poison, 9 Enrage, 11 Bleed (0 = none). Rebuilt every ReloadFrames.
function ns._RebuildDispelCurves()
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return end
    local function build(profile, mult, alphaMult)
        local c = C_CurveUtil.CreateColorCurve()
        c:SetType(Enum.LuaCurveType.Step)
        local function add(idx, key, dr, dg, db)
            local col = profile and profile[key]
            -- Per-type alpha rides the curve too (0 = type opted out of the dispel border/overlay). Never darkened by mult.
            c:AddPoint(idx, CreateColor((col and col.r or dr) * mult, (col and col.g or dg) * mult,
                (col and col.b or db) * mult, ((col and col.a) or 1) * (alphaMult or 1)))
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
    -- Bright (full) curves + parallel 50%-darkened curves for the clock border's already-elapsed
    -- arc. Darkening applies to the user's CLEAN colors at build time, never a secret per-frame one.
    ns._dispelCurve          = build(ns._scaledProfile,    1)
    ns._dispelCurveParty     = build(ns._scaledPartyProxy, 1)
    ns._dispelCurveDark      = build(ns._scaledProfile,    0.5)
    ns._dispelCurveDarkParty = build(ns._scaledPartyProxy, 0.5)
    -- Overlay curves: per-type alpha premultiplied by the overlay opacity HERE, on plain saved
    -- numbers. The evaluated per-frame alpha is SECRET and arithmetic on it is a hard error --
    -- it may only ever flow straight into setters.
    local rOp = ((ns._scaledProfile    and ns._scaledProfile.dispelOverlayOpacity)    or 100) / 100
    local pOp = ((ns._scaledPartyProxy and ns._scaledPartyProxy.dispelOverlayOpacity) or 100) / 100
    ns._dispelCurveOL      = build(ns._scaledProfile,    1, rOp)
    ns._dispelCurveOLParty = build(ns._scaledPartyProxy, 1, pOp)
end

-------------------------------------------------------------------------------
--  Ready check handling
-------------------------------------------------------------------------------
local readyCheckActive = false

-- Incoming-rez indicator state. UnitHasIncomingResurrection covers only the CAST
-- window: it drops to false the moment the cast lands, while the target still has
-- the accept dialog up. ns._rezPend carries the unit across that edge: true while
-- a cast has been seen, then a GetTime() expiry latched when the flag falls on a
-- still-dead unit (the offer window). Cleared on accept (alive read), a fresh
-- cast, roster shifts (unit tokens move), or the 60s offer expiry. A cancelled
-- cast latches too -- the completion and cancel edges are indistinguishable
-- without a combat log; the alive-clear and expiry bound the miss.
ns._rezPend = {}

-- Shared predicate for the rez icon and the DEAD-text suppression at all paint
-- sites. Writes the casting mark itself so a cast already in flight at paint
-- time (login, roster reassignment) still latches when its completion edge fires.
-- PURE otherwise: it must NEVER clear the latch -- many painters call it (status
-- text, Extra Frames duplicates, full passes) and whichever read first would
-- consume the entry before the icon's own repaint, stranding the icon shown.
-- Clearing belongs to the owners: the INCOMING edges, the UNIT_HEALTH alive
-- edge, the expiry timer, and the roster wipe -- each repaints what it clears.
ns._RFRezShown = function(unit)
    if UnitHasIncomingResurrection(unit) then
        ns._rezPend[unit] = true
        return true
    end
    local exp = ns._rezPend[unit]
    if type(exp) ~= "number" then return false end
    if GetTime() >= exp or not UnitIsDeadOrGhost(unit) then
        return false
    end
    return true
end

-- d.readyCheck is shared by the ready-check, incoming-summon and incoming-rez indicators (rez only
-- on dead units). Priority: active ready check > pending summon > incoming rez.
local function UpdateReadyCheck(button, unit)
    local d = GetFFD(button)
    local tex = d.readyCheck
    if not tex then return end

    -- Party/extra-aware settings source, same as every other indicator updater.
    -- AnchorReadyCheck already resolves LIVE this way, so a raw db.profile read
    -- here re-sized the shared texture back to the RAID value on every paint.
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile

    local sz = PixelSnap(s.readyCheckSize or 20)
    tex:SetSize(sz, sz)

    -- Ready check (priority)
    if s.showReadyCheck and readyCheckActive then
        local status = GetReadyCheckStatus(unit)
        if status == "ready" then
            tex:SetAtlas("UI-LFG-ReadyMark-Raid")
            tex:Show()
            return
        elseif status == "notready" then
            tex:SetAtlas("UI-LFG-DeclineMark-Raid")
            tex:Show()
            return
        elseif status == "waiting" then
            tex:SetAtlas("UI-LFG-PendingMark-Raid")
            tex:Show()
            return
        end
    end

    -- Incoming summon
    if s.showSummonPending and unit and C_IncomingSummon.HasIncomingSummon(unit) then
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

    -- Incoming resurrection (cast in flight, or the latched unaccepted-offer window
    -- -- see ns._RFRezShown). Lowest priority; shows a body is already being picked up.
    if s.showIncomingRez and unit and ns._RFRezShown(unit) then
        tex:SetAtlas("RaidFrame-Icon-Rez")
        tex:Show()
        return
    end

    tex:Hide()
end

-------------------------------------------------------------------------------
--  Unit-to-button mapping
-------------------------------------------------------------------------------
local function RebuildUnitMap()
    wipe(unitToButton)
    for _, btn in ipairs(allButtons) do
        if btn:IsVisible() then
            local u = btn:GetAttribute("unit")
            if u then
                local d = GetFFD(btn)
                -- Extra Frames duplicates stay out of the routing map (one button per unit; the
                -- real frame owns the slot). Everything else here applies to them.
                if not d._isExtra then unitToButton[u] = btn end
                -- Cache class token for power border (avoids UnitClass in hot path)
                local _, classToken = UnitClass(u)
                d.classToken = classToken
                -- Repair a container binding the OnAttributeChanged hook dropped because
                -- UnitExists(u) was false at the moment the header assigned it (roster still
                -- streaming in on a zone/group transition). Nothing else re-drives this once
                -- the header stops re-asserting the same token, so aura containers can stay
                -- bound to a stale unit indefinitely.
                if d.rfcUnit ~= u and UnitExists(u) and ns.RFC_OnUnitAssigned then
                    ns.RFC_OnUnitAssigned(btn, d, u)
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Full update for all visible buttons
-------------------------------------------------------------------------------
-- Full-pass paint stamp. The login/zone window runs several IDENTICAL full passes in one frame
-- (assignment paints, the OnEnable reload pass, the visibility rebuild + follow-up). Each full-pass
-- paint stamps the button with (frame time, unit, paint gen); a later identical-body pass in the
-- same frame skips stamped buttons -- same frame + unit + gen reads the same state, so the skipped
-- repaint is provably the same pixels. Targeted event repaints (health, aura singles) neither check
-- nor set the stamp. The gen breaks the window whenever paint INPUTS change mid-frame: settings
-- writes (_BumpAbsorbGen), profile swaps (_ERF_RefreshAll) and cross-module pushes (UpdateAllFrames).
ns._paintGen = 0
local function UpdateAllButtons()
    if previewActive then return end  -- real buttons hidden during preview
    local now, gen = GetTime(), ns._paintGen
    for _, btn in ipairs(allButtons) do
        local u = btn:GetAttribute("unit")
        if u and btn:IsVisible() then
            local d = GetFFD(btn)
            if not (d._fpAt == now and d._fpUnit == u and d._fpGen == gen) then
                d._fpAt = now; d._fpUnit = u; d._fpGen = gen
                UpdateButton(btn)
                UpdateReadyCheck(btn, u)
            end
        end
    end
end

-- Full per-button refresh for a freshly (re)assigned unit; mirrors the per-button work in
-- UpdateAllButtons. On ns so the OnAttributeChanged("unit") watch in StyleButton (created before
-- these locals exist) can repaint the instant the secure header assigns a unit.
ns._RefreshAssignedButton = function(button, unit)
    local d = GetFFD(button)
    if not d.styled then return end  -- not built yet; init paint handles it
    -- Same stamp as UpdateAllButtons (identical body): the assignment paint and a same-frame full pass collapse to one paint.
    local now = GetTime()
    if d._fpAt == now and d._fpUnit == unit and d._fpGen == ns._paintGen then return end
    d._fpAt = now; d._fpUnit = unit; d._fpGen = ns._paintGen
    UpdateButton(button)
    UpdateReadyCheck(button, unit)
end

function ERF:UpdateAllFrames()
    -- Cross-module pushes (Dark Mode master, accent) change paint inputs outside the RF options
    -- funnel: break the same-frame paint-stamp window.
    ns._paintGen = (ns._paintGen or 0) + 1
    UpdateAllButtons()
    -- Party and Boss frames are NOT in `allButtons` (Extra frames ARE, see XF.EnsureBuilt), so
    -- repaint their health too, or Dark Mode / color pushes (ApplyColorsToOUF) miss those frame
    -- types. _UpdateButtonHealth is lightweight, combat-safe and self-guarding.
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

-- Lightweight: role icons only. Driven by combat transitions so the "Hide In Combat" cog
-- suppresses/restores without a full repaint. Texture Show/Hide is combat-legal.
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

-- Lightweight: refresh leader/assistant icons only (combat transitions; "Show
-- In Combat" cog) without a full repaint. Texture Show/Hide is combat-legal.
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

-- Lightweight: refresh combat icons only (UNIT_FLAGS flips + combat
-- transitions). Texture Show/Hide is combat-legal, safe from PLAYER_REGEN_DISABLED.
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

-- True when the combat icon is enabled anywhere (raid or effective party); skips all combat-icon work while off.
ns._CombatIconEnabled = function()
    if not (db and db.profile) then return false end
    if db.profile.showCombatIndicator then return true end
    if ns._partyProxy.showCombatIndicator then return true end
    return false
end

-- Register UNIT_FLAGS on the per-unit trackers ONLY while the combat icon is enabled (raid key;
-- party effective key): off = no tracker listens, zero event code for a disabled feature. Event
-- (un)registration is combat-legal. Extra Frames trackers gate separately in XF_Apply. Called
-- from ReloadFrames and once after the trackers are built.
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

-- Lightweight health-only update for UNIT_HEALTH / UNIT_MAXHEALTH. Skips power/name/role/leader/marker/target/threat -- each has its own event path.
-- Status text (DEAD / OFFLINE / AFK), the ONE painter for both the full paint and
-- the UNIT_HEALTH path. State + color stamped: text/color/visibility re-apply
-- only on a real transition (0 hidden, 1 offline, 2 dead, 3 AFK); the stamp is
-- the on-screen state, so it stays valid across occupants and across the two
-- paths. The rez check runs only for dead units: a live unit can never carry an
-- incoming resurrection (the offer latch also requires dead), so the C probe is
-- skipped for the alive majority -- the same shape as Blizzard's
-- CompactUnitFrame, which never probes rez from its UNIT_HEALTH path. On ns
-- (200-local cap).
ns._PaintStatusText = function(d, s, unit, connected, deadOrGhost)
    local statusText = d.statusText
    if not statusText then return end
    local stc = s.statusTextColor or { r = 1, g = 1, b = 1 }
    local st
    if s.statusTextPosition == "none" then
        st = 0
    elseif deadOrGhost and s.showIncomingRez and ns._RFRezShown(unit) then
        -- Being resurrected: hide the status text so the incoming-rez icon isn't covered.
        st = 0
    elseif not connected then
        st = 1
    elseif deadOrGhost then
        st = 2
    else
        local afk
        if s.statusShowAFK and UnitIsAFK then
            afk = UnitIsAFK(unit)
            if issecretvalue(afk) then afk = nil end
        end
        st = afk and 3 or 0
    end
    if d._stSt ~= st or d._stR ~= stc.r or d._stG ~= stc.g or d._stB ~= stc.b then
        d._stSt, d._stR, d._stG, d._stB = st, stc.r, stc.g, stc.b
        if st == 0 then
            statusText:Hide()
        else
            local L = ns.EllesmereUI.L
            statusText:SetText(st == 1 and L("OFFLINE") or st == 2 and L("DEAD") or L("AFK"))
            statusText:SetTextColor(stc.r, stc.g, stc.b)
            statusText:Show()
        end
    end
end

ns._UpdateButtonHealth = function(button, unit)
    -- Dispatchers pass the event's unit token; rare callers omit it.
    unit = unit or button:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end
    local d = GetFFD(button)
    if not d.styled then return end
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile

    local health = d.health
    local pct = GetSafeHealthPercent(unit)
    local connected = UnitIsConnected(unit)
    local deadOrGhost = UnitIsDeadOrGhost(unit)

    -- Health bar
    if health then
        -- The bar is always a percent bar; its range never changes after the
        -- first application.
        if not d._hb100 then d._hb100 = true; health:SetMinMaxValues(0, 100) end
        local smooth = s.smoothBars and Enum and Enum.StatusBarInterpolation
            and Enum.StatusBarInterpolation.ExponentialEaseOut
        if smooth then
            health:SetValue(pct, smooth)
        else
            health:SetValue(pct)
        end
        -- Fill color: dead/offline ticks skip this entirely (_ApplyHealthBg
        -- owns the gray tint and clears the stamp on the transition). The
        -- curve modes recolor with health, so they apply every tick; static
        -- modes stamp the applied color and re-run only on a real change
        -- (every static-mode component is a plain value by construction).
        if connected and not deadOrGhost then
            local mode = s.healthColorMode
            local r, g, b
            if mode == nil or mode == "class" then
                -- Class color is identity, not health: resolve the class token
                -- once per occupant and reuse it per tick. Cleared on unit
                -- assignment, UNIT_NAME_UPDATE and UNIT_CONNECTION -- the edges
                -- Blizzard's CompactUnitFrame recolors on -- so it can never
                -- outlive the person behind the token. A secret token (identity
                -- restricted) is never cached: fail open to the per-tick read
                -- and the neutral gray, exactly as before.
                local tok = d._clsTok
                if not tok then
                    local _, ct = UnitClass(unit)
                    if ct and not issecretvalue(ct) then
                        tok = ct
                        d._clsTok = ct
                    end
                end
                local cc = tok and ns.EllesmereUI.GetClassColor(tok)
                if cc then r, g, b = cc.r, cc.g, cc.b else r, g, b = 0.5, 0.5, 0.5 end
            else
                r, g, b = GetHealthColor(unit, s)
            end
            if mode == "classic" or mode == "customDynamic" or mode == "classReactive" then
                local fillTex = health:GetStatusBarTexture()
                if fillTex then fillTex:SetAlpha(1) end
                health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
            else
                local a = (mode == "dark") and 1 or (s.healthBarOpacity or 100) / 100
                if d._hcR ~= r or d._hcG ~= g or d._hcB ~= b or d._hcA ~= a or d._hcM ~= mode then
                    d._hcR, d._hcG, d._hcB, d._hcA, d._hcM = r, g, b, a, mode
                    local fillTex = health:GetStatusBarTexture()
                    if mode == "dark" then
                        health:SetStatusBarColor(r, g, b, 1)
                        -- 4th return of GetDarkModeFill() is the Dark Mode Fill Opacity.
                        if fillTex then fillTex:SetAlpha(select(4, EllesmereUI.GetDarkModeFill())) end
                    else
                        if fillTex then fillTex:SetAlpha(1) end
                        health:SetStatusBarColor(r, g, b, a)
                    end
                end
            end
        end
    end

    -- Health text
    if d.healthText then
        local mode = s.healthTextMode or "none"
        -- Hide health text while dead/offline (see UpdateButton; matches preview).
        if deadOrGhost or not connected then
            d.healthText:SetText("")
        elseif mode == "percent" then
            d.healthText:SetFormattedText("%.0f%%", pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "percentNoSign" then
            d.healthText:SetFormattedText("%.0f", pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "number" then
            local curr = UnitHealth(unit, true)
            if curr and AbbreviateNumbers then
                d.healthText:SetText(AbbreviateNumbers(curr))
            elseif curr then
                d.healthText:SetFormattedText("%s", curr)
            end
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "numberPercent" then
            local curr = UnitHealth(unit, true)
            local numStr = (curr and AbbreviateNumbers) and AbbreviateNumbers(curr) or tostring(curr or 0)
            d.healthText:SetFormattedText("%s | %.0f%%", numStr, pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "percentNumber" then
            local curr = UnitHealth(unit, true)
            local numStr = (curr and AbbreviateNumbers) and AbbreviateNumbers(curr) or tostring(curr or 0)
            d.healthText:SetFormattedText("%.0f%% | %s", pct, numStr)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "missing" then
            local curr = UnitHealthMissing(unit, true)
            d.healthText:SetText(C_StringUtil.TruncateWhenZero(curr))
            if d.healthText:GetText() then
                if curr and AbbreviateNumbers then
                    d.healthText:SetText(AbbreviateNumbers(curr))
                elseif curr then
                    d.healthText:SetFormattedText("%s", curr)
                end
            end
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        else
            d.healthText:SetText("")
        end
    end

    -- Heal absorb text
    if d.healAbsorbText then
        if deadOrGhost or not connected then
            d.healAbsorbText:SetText("")
        else
            ns.SetHealAbsorbText(d.healAbsorbText, unit, s)
        end
    end

    -- Status text (dead/ghost state changes with health)
    ns._PaintStatusText(d, s, unit, connected, deadOrGhost)

    -- Background + dead/offline tint. This path owns death/resurrect transitions
    -- arriving via UNIT_HEALTH, so it runs per tick (state-stamped inside).
    ns._ApplyHealthBg(d, health, s, unit, connected, deadOrGhost)

    -- Debuff Manager dead-corpse swap rides the same ownership: one field read
    -- for every button without a qualifying config.
    if d.dmDeadSwap then ns.DM_DeadEdge(d, unit) end
end

-- Two-step max-health landing (max first, value after): one next-frame re-read
-- settles torn numbers; the flag collapses a raid-wide change to one pass per
-- button (canonical story: UF engine RESETTLE_EVENTS). Flag lives in FFD --
-- header children never carry insecure keys.
ns._ResettleButtonHealth = function(button)
    local d = GetFFD(button)
    if d.hpResettle then return end
    d.hpResettle = true
    C_Timer.After(0, function()
        d.hpResettle = nil
        if button:IsVisible() then ns._UpdateButtonHealth(button) end
    end)
end

-------------------------------------------------------------------------------
--  Friendly Boss Frames (any group): five standalone secure unit buttons for
--  boss1-boss5. A secure visibility driver on [@bossN,help] is the entire
--  detection (encounters expose healable friendly NPCs as boss units) -- no
--  NPC database, fully combat safe. Dungeon encounters use the same boss unit
--  tokens as raids, so the group gate can cover party too -- behind the Show
--  in Dungeons opt-in (fb.showInDungeons, default off); attached positions
--  slot in beside the party container there. Buttons render ONLY health bar +
--  name/health text, following the RAID frame settings in a party too (one
--  styled group, and the indicator containers are built once). Excluded from preview and
--  unlock mode (Free Move uses its own drag overlay). Display "healers"
--  builds/activates only on a healer spec.
-------------------------------------------------------------------------------
-- do/end scope keeps FB off the main chunk's 200-local cap; closures below keep it alive after the block closes.
do
local FB = { buttons = {}, trackers = {} }
ns._FB = FB

-- Baseline heal per healer class for NPC range checks. Boss units sit outside UnitInRange's
-- group-member domain and never fire UNIT_IN_RANGE_UPDATE, so range is measured against a known
-- helpful spell instead -- healer specs only; everyone else keeps full alpha (no range check).
FB.RANGE_HEAL = {
    PRIEST  = 2061,   -- Flash Heal
    PALADIN = 19750,  -- Flash of Light
    SHAMAN  = 8004,   -- Healing Surge
    DRUID   = 8936,   -- Regrowth
    MONK    = 116670, -- Vivify
    EVOKER  = 361469, -- Living Flame (25yd: native Evoker range)
}

-- Secret-safe alpha application (result may be secret in instances, which SetAlphaFromBoolean
-- accepts natively). The result can also be NIL (unit not range-checkable / spell momentarily not
-- evaluable), which it rejects -- treat NIL as in range. issecretvalue runs FIRST so the nil check
-- never touches a secret.
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

-- The ticker exists only while a range spell is resolved AND at least one boss button is visible -- zero idle cost.
FB.UpdateRangeTicker = function()
    local want = FB.rangeSpell and (FB.visCount or 0) > 0
    if want and not FB.rangeTicker then
        FB.rangeTicker = C_Timer.NewTicker(0.4, FB.RangeTick)
    elseif not want and FB.rangeTicker then
        FB.rangeTicker:Cancel()
        FB.rangeTicker = nil
    end
end

-- Current unit for a button. The slot controller collapses friendly bosses into the FIRST slots
-- (slot 1 may show boss2), so the secure "unit" attribute is truth; _fbUnit is the build default.
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

-- Anchor a FontString using the same position vocabulary as AnchorNameText/AnchorHealthText.
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

-- Recolor the border for the current state. Mirrors the raid buttons' single recolored border:
-- hover (raised) > target (raised) > normal, using the raid border settings -- nothing separate.
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
    -- Raise above neighbors while highlighted (as the raid buttons: overlapping frames would cover it).
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

-- Refresh one boss button: health value/color, health text, name text. Mirrors the corresponding
-- slices of UpdateButton/_UpdateButtonHealth; boss units are not group units, so no roster paths.
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
    -- Own color setting (default #17AC31). The raid color modes mislead here: gradient modes read
    -- as damage states, and many NPCs carry real class tokens (a friendly add can come out yellow).
    local fbc = FB.Settings()
    fbc = fbc and fbc.healthColor
    local fillTex = health:GetStatusBarTexture()
    if fillTex then fillTex:SetAlpha(1) end
    health:SetStatusBarColor(fbc and fbc.r or 23/255, fbc and fbc.g or 172/255,
        fbc and fbc.b or 49/255, (s.healthBarOpacity or 100) / 100)

    if b._nameText then
        b._nameText:SetText(ResolveDisplayName(unit, true, s))
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
        elseif mode == "missing" then
            local curr = UnitHealthMissing(unit, true)
            b._healthText:SetText(C_StringUtil.TruncateWhenZero(curr))
            if b._healthText:GetText() then
                if curr and AbbreviateNumbers then
                    b._healthText:SetText(AbbreviateNumbers(curr))
                elseif curr then
                    b._healthText:SetFormattedText("%s", curr)
                end
            end
            local htr, htg, htb = GetHealthTextColor(unit, s)
            b._healthText:SetTextColor(htr, htg, htb, 0.9)
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

-- One-time construction of the container, the five buttons, click-cast registration and per-unit
-- trackers. Buttons are created hidden; the secure visibility drivers own show/hide after that.
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
        -- The engine gates SecureUnitButton's togglemenu; route right-click through a SecureActionButton proxy so the menu works without taint.
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

        -- Border frame (same construction as the raid buttons; styled from the shared raid border settings in FB.StyleBorder)
        local bdr = CreateFrame("Frame", nil, b)
        bdr:SetAllPoints(b)
        bdr:SetFrameLevel(b:GetFrameLevel() + 8)
        b._borderFrame = bdr

        -- Refresh as soon as the driver shows the button; visible-count drives the ticker lifecycle.
        b:HookScript("OnShow", function(self)
            FB.visCount = (FB.visCount or 0) + 1
            -- Containers first: an error in the legacy refresh must not starve the unit assignment.
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

        -- Re-render when the slot controller reassigns this slot's unit mid-combat (a boss
        -- spawning/despawning reflows the slots without an OnShow on already-visible buttons).
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

        -- Boss units are outside the roster trackers; track here. The slot controller may have
        -- assigned this unit to ANY slot, so route the event to whichever button shows it.
        local unitId = "boss" .. i
        local t = ns.TakeShell()
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

    -- Slot controller: collapses friendly bosses into the FIRST slots (button positions fixed;
    -- units assigned in bossN order, buttons shown/hidden). Runs in the restricted environment so
    -- mid-combat spawns/despawns reflow safely (insecure code cannot Show/Hide or re-unit protected
    -- buttons in combat). Drivers registered in FB_Apply feed state-ingroup / state-fb1..5. One
    -- shared body per attribute; FB_Apply also force-runs it via SecureHandlerExecute because the
    -- driver manager skips the handler when a re-registered driver's value is unchanged.
    FB.RELAYOUT = [[
        local ingroup = self:GetAttribute("state-ingroup")
        local slot = 0
        if ingroup == 1 or ingroup == "1" then
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
    -- The template's handler attribute is "_onattributechanged" (wildcard receiving name/value).
    -- The relayout body lives in its own attribute so the handler and the force-run share it.
    controller:SetAttributeNoHandler("fb_relayout", FB.RELAYOUT)
    controller:SetAttributeNoHandler("_onattributechanged", [[
        if name == "state-ingroup" or name == "state-fb1" or name == "state-fb2"
           or name == "state-fb3" or name == "state-fb4" or name == "state-fb5" then
            self:RunAttribute("fb_relayout")
        end
    ]])
    FB.controller = controller
end

-- Re-apply all setting-derived properties (size, slots, texture, fonts, text anchors). OOC only;
-- callers gate. The owner parameter lets the Extra Frames duplicates (ns._XF) share this verbatim:
-- an owner carries buttons/container/Settings and defaults to FB itself.
FB.ApplyStyle = function(owner)
    owner = owner or FB
    if not owner.built then return end
    local s = ns._scaledProfile or db.profile
    local fbset = owner.Settings()
    -- Per-group size offset on the shared raid frame size (Extra Width/Height sliders; clamped so a negative offset can't invert a small frame).
    local w = PixelSnap(math.max(10, (s.frameWidth or 125) + ((fbset and fbset.extraWidth) or 0)))
    local h = PixelSnap(math.max(10, (s.frameHeight or 60) + ((fbset and fbset.extraHeight) or 0)))
    local sp = s.cellSpacing or -1
    -- Free Move ignores the raid growth settings: vertical stack by default, horizontal via the
    -- Horizontal Frames cog. Attached modes keep stacking like a real group (unitGrowth).
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
        -- Fill axis follows the raid Health Bar setting. The bg is a full-button texture (not fill-tracking), so nothing else re-anchors.
        ns.RF_ApplyHealthOrientation(b._health, s)
        -- These carry aura containers (RFC_SetupButton below) and so can carry
        -- Health Bar Color overlays, but they have no absorb cluster and never
        -- build ReanchorAbsorbToFill, where every other frame picks the swap up.
        b._health._euiFillOpacity = (s.healthBarOpacity or 100) / 100
        ns.RF_RefreshBarTints(b._health)
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

-- Position the container per the position setting. The container inherits protection from its
-- secure children, so SetPoint is OOC-only. Owner-parameterized like ApplyStyle.
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
        -- Chain rule: when the boss group (owner == FB) and Extra Frames attach to the SAME side,
        -- the boss group anchors to the extra container instead of the raid -- order raid -> extra
        -- -> boss (mirrored on "left"). Extra Frames always anchor to the raid; ns.XF_Apply re-runs
        -- this anchor when that container shows/hides/moves.
        if owner == FB then
            local xf = ns._XF
            local xs = xf and xf.Settings and xf.Settings()
            if xs and xs.position == fb.position and xf.built
               and xf.container and xf.container:IsShown() then
                anchorHdr = xf.container
            end
        end
        -- Party/dungeon: every raid group header is hidden there, so the boss group slots in beside
        -- the party container as if it were the next group -- along the axis the party frames do NOT
        -- stack on, the way "before first / after last group" reads in a raid. Extra Frames is raid
        -- only and keeps the raid path. Party frames off screen leaves nothing to attach to: this
        -- branch anchors nothing and the free position below takes over.
        if owner == FB and not anchorHdr and not IsInRaid()
           and fb.showInDungeons == true then
            local pc = ns._partyContainerFrame
            if pc and pc:IsShown() then
                local gap = s.groupSpacing or -1
                local before = (fb.position == "left")
                -- Party growth axis comes from partyHorizontal alone (_LayoutPartyFrames): the flip
                -- and "centered" variants only reverse it, and the container spans all five slots
                -- either way, so the perpendicular attach point is the same.
                if s.partyHorizontal then
                    if before then c:SetPoint("BOTTOMLEFT", pc, "TOPLEFT", 0, gap)
                    else c:SetPoint("TOPLEFT", pc, "BOTTOMLEFT", 0, -gap) end
                else
                    if before then c:SetPoint("TOPRIGHT", pc, "TOPLEFT", -gap, 0)
                    else c:SetPoint("TOPLEFT", pc, "TOPRIGHT", gap, 0) end
                end
                return
            end
        elseif not anchorHdr and s.mergeGroups then
            anchorHdr = ns._flatHeader
        elseif not anchorHdr then
            -- The boss group slots in before the first / after the last group that is BOTH enabled
            -- in Show Groups AND populated. With none populated (not in a raid yet), fall back to
            -- the Show Groups bounds alone.
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

    -- Owner-specific free anchoring (Extra Frames pins the grid's growth corner so the group grows away from it); CENTER pin otherwise.
    if owner.FreeAnchor and owner.FreeAnchor(c, fb) then return end
    local p = fb.freePos or {}
    c:SetPoint("CENTER", UIParent, "CENTER", p.x or 100, p.y or 0)
end

-- Re-anchor only (no restyle): the party visibility pass calls this on the party container's
-- show/hide edge, since attached positions hang off that container outside a raid. Gated on
-- the Show in Dungeons opt-in: with it off the party attach branch is inert, so the party
-- layout/visibility hooks skip the re-anchor entirely (zero added work for raid-only users).
function ns.FB_ReAnchor()
    if not FB.built then return end
    local fb = FB.Settings and FB.Settings()
    if fb and fb.showInDungeons == true then FB.Anchor() end
end

-- Master apply: activates, deactivates and refreshes the whole feature. Called from OnEnable, the
-- options dropdowns, spec changes, profile swaps (_ERF_RefreshAll) and the post-combat dirty pass.
function ns.FB_Apply()
    if not db or not db.profile then return end
    local fb = FB.Settings()
    if not fb then return end
    if InCombatLockdown() then FB.applyDirty = true; return end

    if not FB.ShouldBeActive() then
        if FB.built then
            if FB.controller then
                UnregisterAttributeDriver(FB.controller, "state-ingroup")
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
    -- Drivers feed the slot controller, which assigns bosses to the first slots in bossN order and shows/hides buttons securely.
    -- Group gate: raid only by default; raid OR party with Show in Dungeons on (the cog on
    -- Add Friendly Boss Group -- opt-in, so existing users keep raid-only behavior). Dungeon
    -- encounters expose the same healable bossN tokens. The toggle's setter re-runs FB_Apply,
    -- so re-registering here applies the flip live in either direction.
    local groupCond = (fb.showInDungeons == true)
        and "[@raid1,exists][@party1,exists] 1; 0"
        or "[@raid1,exists] 1; 0"
    RegisterAttributeDriver(FB.controller, "state-ingroup", groupCond)
    for i = 1, 5 do
        RegisterAttributeDriver(FB.controller, "state-fb" .. i, "[@boss" .. i .. ",help] 1; 0")
    end
    -- Force one relayout now: the driver manager fires attribute handlers only on VALUE CHANGES, so
    -- a (re)apply with unchanged states would never run the initial layout. FB_Apply is OOC-only,
    -- so the insecure Execute is always legal here.
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

-- Free Move drag overlay (unlock-mode look, TOOLTIP strata so it floats above the options panel).
-- Deliberately independent of unlock mode. Owner-parameterized: the Extra Frames group builds its
-- own mover through this exact code with its own name/label (stored at owner.mover).
FB.SetMoverShown = function(owner, show, frameName, labelText)
    if not show then
        if owner.mover then owner.mover:Hide() end
        return
    end
    local fb = owner.Settings()
    if not fb or fb.position ~= "free" then return end
    owner.EnsureBuilt()
    -- Owners with their own geometry pass (Extra Frames) restyle through it; FB-built buttons use the FB styler.
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
        -- Corner-pinned owners: mirror the container's placement so the overlay always covers the live grid (FB.Anchor just ran).
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

-- Standing event frame: exists even while inactive so a spec change can activate display="healers" without a /reload.
do
    local ev = ns.TakeShell()
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

end -- FB scope block

-------------------------------------------------------------------------------
--  Extra Frames (raid only): 1:1 duplicates of chosen raid members (Show
--  Tanks + hotkey-toggled players, up to XF.CAP). Attached positions stack
--  group-sized runs of 5 like extra raid groups; Free Move uses its own
--  grow/wrap axes (XF.GrowInfo/XF.FreeAnchor) with a growth-corner pin. Each
--  duplicate runs the SAME StyleButton pipeline as real header children
--  (power/absorbs/auras/BM/icons/click-cast/ping) and joins allButtons.
--
--  Duplicates stay OUT of unitToButton (d._isExtra guards every rebuild);
--  each slot has its own tracker + RegisterUnitEvent and lives in
--  ns._xfUnitToButton, which the broadcast passes (target border, markers,
--  range, ghost-aura sweep) also iterate -- zero cost when inactive. Position
--  via shared FB.Anchor; unit assignment is OOC, dirty-deferred through
--  combat. Excluded from preview/unlock mode like FB.
-------------------------------------------------------------------------------
-- Scope block: 200-local main-chunk cap (see the FB block above).
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

-- Hard selection bound (internal, no user setting): a full mythic roster's
-- worth of duplicates while keeping per-unit event mirroring bounded.
XF.CAP = 20

-- Effective growth axes: primary run direction + perpendicular wrap.
-- Attached modes stack group-sized runs of 5 like additional raid groups:
-- units along the raid unit growth, each full run slotting further out along
-- the group growth axis AWAY from the raid ("left" attaches before the first
-- group, so runs extend against the group growth). Free Move reads Grow
-- Direction (falling back to the legacy Horizontal toggle) and wraps along
-- Wrap Direction. Wrap values not perpendicular to the primary run (stale
-- after a direction change, or a parallel group growth) fall back to the default.
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
-- the last mover drag so frame 1 never shifts as players enter/leave the
-- selection (the container is sized to the live selection; a CENTER pin
-- would drift). Falls back to the legacy CENTER anchor (freePos) until the
-- user drags the mover once. Called by FB.Anchor through the owner hook.
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

-- Ordered raid units to duplicate (bounded by XF.CAP): tanks in roster order first
-- (Show Tanks on), then manually added names currently in the raid. Names are stored
-- AND matched in GetRaidRosterInfo's format so realm suffixes always agree; names not
-- in the roster are skipped but kept (they reappear when that player rejoins).
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
               and EllesmereUI.UnitEffectiveRole("raid" .. i) == "TANK"
               -- Exclude Myself (Show Tanks cog): the tanks auto-include
               -- skips the player's own frame; explicit hotkey picks below
               -- still add it.
               and not (set.excludeSelfTank and UnitIsUnit("raid" .. i, "player")) then
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

-- Geometry only: container size, button stacking, per-button size (Extra
-- Width/Height offsets) and height-derived inner corrections (mirrors
-- ns._ResizeButtons). All VISUALS come from the shared StyleButton /
-- ReloadFrames pipeline (buttons are in allButtons); ReloadFrames tail-calls
-- XF_Apply so this offset pass always runs after the bulk base-size pass.
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
    -- Auto Resize Indicators cog toggle (nil = ON, additive key): off keeps
    -- indicators/auras/BM at the real frames' base scale regardless of the
    -- extra frames' custom size.
    if aw > 0 and ah > 0 and (not set or set.autoResizeIndicators ~= false) then
        ratio = math.max(math.min(math.min(w / aw, h / ah), 1.3), 0.7)
    end
    ns._xfExtraRatio = ratio
    if ns._RefreshProxyModes then ns._RefreshProxyModes() end
    ns._xfBmScale = (ns._bmScale or 1) * ratio
    local sp = s.cellSpacing or 2
    -- Free Move lays out on its own axes; attached modes stack group-sized
    -- runs of 5 (unitGrowth within a run, group growth across).
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
        -- run carries pos, the wrap axis carries line; the anchor corner is
        -- the one both directions grow away from (frame 1 sits there).
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
            d.health:SetHeight(((d.power and d.power:IsShown()) and PixelSnap(h - ns.RF_HealthPowerInset(s, powerH)) or h) - topBarH)
        end

        -- Scaled visual pass: re-apply every ratio-affected element through
        -- the extra proxy (mirrors ReloadFrames per-button styling) so texts/
        -- indicators/auras/BM buffs auto-resize. Bounded to the built slots.
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
        if d.pingFrame then ns._RFAnchorPing(d) end
    end
end

-- Per-unit events mirrored from the central hub for one duplicate's unit.
-- UNIT_* only (safe for RegisterUnitEvent's C-side filter); the two
-- unit-payload broadcast events (READY_CHECK_CONFIRM, PLAYER_FLAGS_CHANGED)
-- are plain registrations filtered in the handler.
XF.EVENTS = {
    -- UNIT_AURA deliberately absent (Blizzard parity: their CompactUnitFrame
    -- repaints prediction from health/absorb events only). The one gap -- an
    -- aura-granted shield expiring on its TIMER on an unhit, topped unit
    -- (field report: VDH Infernal Strike) fires NO event at all -- is covered
    -- by the armed-members belt next to the absorb coalescer.
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_DISPLAYPOWER",
    "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_PREDICTION", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
    "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
    "UNIT_NAME_UPDATE", "UNIT_CONNECTION", "UNIT_IN_RANGE_UPDATE",
}

-- Grow-on-demand construction: container + buttons through the full real-frame
-- StyleButton pipeline. The base 5 slots build on first activation; slots above 5 build
-- only when the selection reaches them (callers are all OOC). d._isExtra is set BEFORE
-- StyleButton so the OnAttributeChanged hook it installs never writes the real routing
-- maps. Buttons join allButtons so every bulk restyle/update pass covers them.
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
        ns._StyleButtonSecure(b)
        StyleButton(b)
        allButtons[#allButtons + 1] = b

        -- Per-slot tracker: (re)registered for the assigned unit in XF_Apply,
        -- mirroring the central hub's per-unit reactions for this duplicate.
        -- Bounded to the built slots; zero registrations while a slot is empty.
        local t = ns.TakeShell()
        t:SetScript("OnEvent", function(_, event, unit, updateInfo)
            if not b:IsVisible() then return end
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                ns._UpdateButtonHealth(b, unit)
                if event == "UNIT_MAXHEALTH" then
                    ns._ResettleButtonHealth(b)
                    -- Max moves the absorb bars' range; value-only health
                    -- changes touch nothing UpdateAbsorb paints (overlays are
                    -- clip-anchored; the missing-health clamp edge rides the
                    -- armed belt / next absorb event instead).
                    local d = GetFFD(b)
                    if d._absActive then ns._MarkAbsorbDirty(b, unit) end
                end
            elseif event == "UNIT_POWER_UPDATE" then
                local d = GetFFD(b)
                if d.power and d.power:IsShown() then
                    -- Value only; type/color/bounds ride the UNIT_DISPLAYPOWER
                    -- edge (see the header dispatcher's branch).
                    local pType = d._pwType
                    if pType == nil then
                        ns._RFPowerTypeEdge(d, unit)
                        pType = d._pwType
                    end
                    d.power:SetValue(UnitPowerPercent(unit, pType, true, CurveConstants.ScaleTo100))
                end
            elseif event == "UNIT_DISPLAYPOWER" then
                local d = GetFFD(b)
                if d.power and d.power:IsShown() then
                    ns._RFPowerTypeEdge(d, unit)
                    d.power:SetValue(UnitPowerPercent(unit, d._pwType, true, CurveConstants.ScaleTo100))
                end
            elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
                or event == "UNIT_HEAL_PREDICTION" or event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
                -- The event IS the arm: plainly observable even while the
                -- values are secret. Paint coalesces to once per render frame.
                -- Prediction is view-gated: with the feature off for this
                -- button's view the event changes no pixel and must not arm.
                local dd = GetFFD(b)
                if event == "UNIT_HEAL_PREDICTION" then
                    local sv = dd._isParty and ns._scaledPartyProxy
                        or (dd._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
                    if sv.healPrediction then
                        ns._AbArm(b, unit, dd)
                        ns._MarkAbsorbDirty(b, unit)
                    end
                else
                if event ~= "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then ns._AbArm(b, unit, dd) end
                ns._MarkAbsorbDirty(b, unit)
                if event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then ns.UpdateHealAbsorbTextFor(b, unit) end
                if event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
                    ns._UpdateButtonHealth(b, unit)
                    ns._ResettleButtonHealth(b)
                end
                end -- prediction view-gate else
            elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
                local d = GetFFD(b)
                if d.threatFrame then
                    local s = d._isExtra and ns._scaledExtraProxy or ns._scaledProfile
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

-- Master apply: resolves the selection and assigns units to slots. OOC only
-- (unit attributes and Show/Hide on protected buttons); combat callers land
-- on the dirty flag and replay on regen. Called from OnEnable, options
-- widgets, the hotkey toggle, roster/role events, ReloadFrames and profile
-- swaps. The SetAttribute write triggers the StyleButton OnAttributeChanged
-- hook, which repaints in full (UpdateButton + auras + dispel + BM), seeds
-- range and re-registers private auras -- same path as a real header assignment.
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
            -- Fail-open backstop for a mid-raid reconnect: the roster can still be
            -- streaming, so UnitName(unit) may be nil at this first paint and the
            -- slot commits a blank name (field report: blank until /reload even
            -- though UNIT_NAME_UPDATE and the roster re-apply are both wired).
            -- Re-arms until the name resolves, bounded, and only repaints while
            -- this slot still holds the same unit. No-op when the name is cached.
            if not UnitName(unit) then
                local tries = 0
                local function RetryName()
                    if b:GetAttribute("unit") ~= unit then return end
                    if UnitName(unit) then UpdateButton(b); return end
                    tries = tries + 1
                    if tries < 5 then C_Timer.After(2, RetryName) end
                end
                C_Timer.After(2, RetryName)
            end
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

-- Hidden bind target (pure Lua keybinding, no Bindings.xml; same pattern as
-- the Party Mode toggle key). The options panel binds the saved key to click
-- this button; the click toggles the hovered raid member in/out of the group.
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
    -- Already covered by Show Tanks: adding would be an invisible duplicate.
    -- An Exclude-Myself'd player tank is NOT covered, so their manual add
    -- stays legitimate.
    if set.showTanks and EllesmereUI.UnitEffectiveRole(unit) == "TANK"
       and not (set.excludeSelfTank and UnitIsUnit(unit, "player")) then
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
    local ev = ns.TakeShell()
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
--  Show Self First (raid, OOC only): the player's subgroup header sorts via a
--  per-group nameList listing every member with the player first, so the
--  secure header orders natively -- no SetPoint override, no flicker.
--  showPlayer can't exclude the player in a raid, so the party-style self
--  button doesn't apply here. Merged mode pins the player via a whole-raid
--  nameList instead (ns._BuildMergedSelfNameList below).
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

-- Build a "player first" nameList for the player's raid subgroup. Names come from
-- GetRaidRosterInfo (same source the secure header matches against, range-independent),
-- so nothing can vanish. Others follow the active sort: role order (ROLE mode, via
-- EllesmereUI.UnitEffectiveRole) else raid index. selfLast orders the player LAST instead.
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
        -- A nil/placeholder name = roster not fully populated (zoning,
        -- mid-loadscreen join); the subgroup is not trustworthy either, and an
        -- omitted member's frame would be HIDDEN by the header. Bail to nil
        -- (index-order fallback, everyone visible) until names resolve.
        if not name or name == UNKNOWNOBJECT then return nil end
        if subgroup == playerGroup then
            local unit = "raid" .. i
            local rp = 99
            if pri then rp = pri[EllesmereUI.UnitEffectiveRole(unit)] or 99 end
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

-- Default class sort order: real player classes only, alphabetical by
-- localized name, enumerated via GetNumClasses + C_CreatureInfo.GetClassInfo
-- so non-class entries (Adventurer/Traveler in LOCALIZED_CLASS_NAMES_MALE) are
-- excluded. Also populates ns._classNameByToken (token -> localized name) for
-- the options list. Cached on ns (local cap).
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
            -- An unpopulated name (zoning, mid-loadscreen join) cannot be
            -- listed: a nameList missing a member HIDES that frame. Bail to
            -- nil so the caller falls back to the groupFilter path (everyone
            -- visible) until UNIT_NAME_UPDATE rebuilds with real names.
            if not name or name == UNKNOWNOBJECT then return nil end
            if server and server ~= "" then name = name .. "-" .. server end
            local _, classToken = UnitClass(unit)
            members[#members + 1] = {
                name = name,
                rolePri = (rolePri and rolePri[EllesmereUI.UnitEffectiveRole(unit)]) or 99,
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

-- Party header nameList for ARENA, where the header is bound to raid1-5.
-- showPlayer cannot exclude the player in a raid group and the static self
-- button cannot reorder them; a NAMELIST does both (Hide Self; Self
-- First/Last). Rest follow role order (ROLE mode) else raid index. Names come
-- from GetRaidRosterInfo (what the header matches against). Bails to nil
-- (index-order fallback, everyone visible) while any name is unresolved.
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
            if pri then rp = pri[EllesmereUI.UnitEffectiveRole(unit)] or 99 end
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
        -- Player to top (self-first) or bottom (self-last); exactly one of a/b
        -- is the player in this branch, so the XOR with selfLast flips it.
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

-- Whole-raid nameList for Merge Groups + Self Position: player pinned first
-- (or last), everyone else in the active sort (role blocks in ROLE mode, raid
-- index otherwise). Replaces the flat header's groupFilter, so members of
-- groups hidden via Show Groups are simply not listed. Bails to nil while any
-- name is unresolved (a nameList missing a member HIDES that frame); the
-- caller falls back to the engine path until names resolve.
function ns._BuildMergedSelfNameList(sortByRole, roleOrder, selfLast, visibleGroups)
    if not IsInRaid() then return nil end
    local pri
    if sortByRole then
        pri = {}
        for p, r in ipairs(roleOrder) do pri[r] = p end
    end
    local members = {}
    local n = GetNumGroupMembers()
    for i = 1, n do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if not name or name == UNKNOWNOBJECT then return nil end
        if not visibleGroups or visibleGroups[subgroup] ~= false then
            local unit = "raid" .. i
            local rp = 99
            if pri then rp = pri[EllesmereUI.UnitEffectiveRole(unit)] or 99 end
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
        -- Player to top (self-first) or bottom (self-last); exactly one of a/b
        -- is the player in this branch, so the XOR with selfLast flips it.
        if a.isPlayer ~= b.isPlayer then return a.isPlayer ~= selfLast end
        if sortByRole and a.rolePri ~= b.rolePri then return a.rolePri < b.rolePri end
        return a.index < b.index
    end)
    local names = {}
    for _, m in ipairs(members) do names[#names + 1] = m.name end
    return table.concat(names, ",")
end

-------------------------------------------------------------------------------
--  Apply sort attributes to all headers. Show Self First (raid) uses the
--  per-group nameList (see the Show Self First banner above); merged mode
--  uses the whole-raid nameList (ns._BuildMergedSelfNameList). Expensive
--  Hide/Show runs only when an attribute actually changed.
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

    -- gf = desired groupFilter. nameList is only honored when groupFilter is
    -- CLEARED (with one present the engine ignores nameList and uses
    -- roster/index order); the nameList lists every group member, so clearing
    -- groupFilter shows the same members in nameList order.
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
        -- Self Position in merged mode: a whole-raid nameList owns the order
        -- (player pinned, rest by the active sort), so groupFilter must be
        -- CLEARED -- the list itself only names visible groups' members --
        -- and groupBy nil so the list order is what the header uses (same
        -- combo as the non-merged player's-group path). While names are
        -- unresolved (builder bailed) the engine path runs instead, with
        -- LayoutGroups' groupFilter restored from ns._flatGfStr.
        local mergedSelf = (s.showSelfFirst or s.showSelfLast) and IsInRaid()
        local mergedList = mergedSelf
            and ns._BuildMergedSelfNameList(sortByRole, roleOrder, selfLast, s.visibleGroups) or nil
        if mergedList then
            applySortTo(ns._flatHeader, nil, "NAMELIST", "", mergedList, nil)
        else
            applySortTo(ns._flatHeader, baseGroupBy, baseSortMethod, baseGroupingOrder, nil,
                ns._flatGfStr or ns._flatHeader:GetAttribute("groupFilter"))
        end
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
-- One SecureGroupHeader set per layout mode: 8 separated group headers, or a
-- single flat header for Merge Groups (only structure that can fill/sort across
-- group boundaries). Only the ACTIVE mode builds at login (full-set build/style
-- dominates login cost); the other materializes on the first mode flip via
-- ReloadFrames/_ERF_RefreshAll. Combat blocks secure creation -- a combat-time
-- flip flags the REGEN reload path to build there instead.
ns._BuildHeaderSet = function(merge)
    if not containerFrame then return end
    if merge and ns._flatHeader then return end
    if not merge and separatedHdrs[1] then return end
    if InCombatLockdown() then
        ns._sizeTierDirtyInCombat = true
        return
    end

    local s = db.profile

    -- Button dimensions passed to headers via attributes (pixel-snapped):
    -- active tier dims when a tier is live (late build inside a raid), else base.
    local bw = PixelSnap(ns._activeSizeW or s.frameWidth or 72)
    local bh = PixelSnap(ns._activeSizeH or s.frameHeight or 46)

    -- initialConfigFunction: runs in restricted env when header creates a button
    local initConfig = ([[
        self:SetWidth(%d)
        self:SetHeight(%d)
    ]]):format(bw, bh)

    -- Compute correct initial point/offset from saved growth direction. Self-heal
    -- a same-axis pair (see ns._RFEffectiveGrowth) before deriving anything from
    -- it -- this bootstrap runs from the raw profile, ahead of _LayoutGroupsImpl's
    -- own per-tier resolution and self-heal.
    local initUnitGrowth, initGroupGrowth = ns._RFEffectiveGrowth(
        s.unitGrowth or "DOWN", s.groupGrowth or "RIGHT", merge)
    local csInit = PixelSnap(s.cellSpacing or 2)
    local initPoint, initXOff, initYOff = ns._RFHeaderPoint(initUnitGrowth, csInit)

    if not merge then
        -----------------------------------------------------------
        --  8 separated group headers (one per raid group)
        -----------------------------------------------------------
        for group = 1, 8 do
            local hdr = CreateFrame("Frame", "ERFGroupHeader" .. group, containerFrame, "SecureGroupHeaderTemplate")
            -- the header births an AuraContainer per child SECURE-SIDE -- the only
            -- combat-legal container source (covers in-combat /reload and mid-combat
            -- roster growth). The containers file adopts it as the debuff shell.
                hdr:SetAttribute("auraContainerTemplate", "CustomAuraContainerTemplate")
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

            -- Window-phase secure styling only; the insecure visual bodies run
            -- in the deferred login pass (or the restyle-loop fallback).
            for i = 1, 5 do
                local btn = hdr[i]
                if btn then
                    ns._StyleButtonSecure(btn)
                    allButtons[#allButtons + 1] = btn
                end
            end

            separatedHdrs[group] = hdr
        end
    else
        -----------------------------------------------------------
        --  Flat header for merge-groups mode (all members in one grid)
        -----------------------------------------------------------
        ns._flatHeader = CreateFrame("Frame", "ERFFlatHeader", containerFrame, "SecureGroupHeaderTemplate")
            ns._flatHeader:SetAttribute("auraContainerTemplate", "CustomAuraContainerTemplate")
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
        ns._flatHeader:SetAttribute("columnAnchorPoint", ns._RFColAnchor(initUnitGrowth, initGroupGrowth))
        ns._flatHeader:SetAttribute("sortMethod", "INDEX")

        -- Pre-create 40 buttons
        ns._flatHeader:SetAttribute("startingIndex", -39)
        ns._flatHeader:Show()
        ns._flatHeader:SetAttribute("startingIndex", 1)
        ns._flatHeader:Hide()  -- start hidden; LayoutGroups shows the right headers

        -- Window-phase secure styling only; bodies run in the deferred pass.
        for i = 1, 40 do
            local btn = ns._flatHeader[i]
            if btn then
                ns._StyleButtonSecure(btn)
                allButtons[#allButtons + 1] = btn
                ns._flatButtons[#ns._flatButtons + 1] = btn
            end
        end
    end

    -- Freshly built headers need the current sort attributes.
    ApplySortToHeaders()
end

local function CreateHeaders()
    if containerFrame then return end

    local s = db.profile

    -- Container frame for positioning (not secure, just holds headers)
    containerFrame = CreateFrame("Frame", "EllesmereUIRaidFrameContainer", UIParent)
    containerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    containerFrame:SetSize(1, 1)
    containerFrame:SetFrameStrata(ns._ResolveFrameStrata(false))
    containerFrame:Show()

    -- Group-number labels (1-8) for the real raid frames. Own (non-secure)
    -- FontStrings parented to the container; they track each group's first unit
    -- via relative anchoring (no SetPoint is ever issued on the secure headers).
    -- Shown only when showGroupNumbers is on (see ns._UpdateGroupNumbers).
    if not ns._groupNumberLabels then
        -- Overlay host at a high frame level: labels parented straight to the
        -- container render BENEATH the bars (buttons are its descendants); a
        -- high level within the same (LOW) strata lifts them on top.
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

    -- Build ONLY the active mode's header set; the inactive one materializes
    -- on the first Merge Groups flip (see ns._BuildHeaderSet above).
    ns._BuildHeaderSet((s.mergeGroups and true) or false)
end

-------------------------------------------------------------------------------
--  Layout groups
--  Two perpendicular axes: groupGrowth (where next group goes) and
--  unitGrowth (where next unit within a group goes).
--  Container sized for 4 groups (standard 20-player raid).
-------------------------------------------------------------------------------
local MOVER_GROUPS = 4

-- Real-frame group numbers (1-8): mirror the preview labels onto the actual
-- frames when showGroupNumbers is on, anchoring each group's label to its
-- first populated unit (shared groupNumberSize/Color). Raid + separated-groups
-- only (merged has no per-group first unit). Combat-safe: called only from
-- LayoutGroups (early-returns in combat), SetPoints only our own FontStrings.
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
    -- Belt: any path that flips the mode without passing through ReloadFrames
    -- still gets its header set built before this tries to show it.
    ns._BuildHeaderSet((merged and true) or false)
    local groupGrowth = s.groupGrowth or "RIGHT"
    local unitGrowth  = s.unitGrowth or "DOWN"
    -- Per-tier growth overrides
    local activeOv = ns._activeTierOverride
    if activeOv then
        groupGrowth = activeOv.groupGrowth or groupGrowth
        unitGrowth  = activeOv.unitGrowth or unitGrowth
    end
    -- Backstop: self-heal a same-axis pair that reached here without going
    -- through a guarded write site (see ns._RFEffectiveGrowth).
    unitGrowth, groupGrowth = ns._RFEffectiveGrowth(unitGrowth, groupGrowth, merged)
    local bw = PixelSnap(ns._activeSizeW or s.frameWidth or 72)
    local bh = PixelSnap(ns._activeSizeH or s.frameHeight or 46)
    local cs = PixelSnap(s.cellSpacing or 2)
    local gs = PixelSnap(s.groupSpacing or 8)

    -- Header attributes for unit growth direction
    local hdrPoint, hdrXOff, hdrYOff = ns._RFHeaderPoint(unitGrowth, cs)

    -- Column anchor: where next column of 5 goes (perpendicular to unit growth)
    local colAnchor = ns._RFColAnchor(unitGrowth, groupGrowth)

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
            -- Blizzard's header anchors its first button at the corner where
            -- "point" and "columnAnchorPoint" meet, then grows away from it --
            -- same corner ns._RFGrowthCorner names for separated headers. A
            -- fixed TOPLEFT here left the rendered grid offset from the
            -- container/mover box whenever growth pinned a different corner.
            local hdrCorner = ns._RFGrowthCorner(unitGrowth, groupGrowth)
            ns._flatHeader:ClearAllPoints()
            ns._flatHeader:SetPoint(hdrCorner, containerFrame, hdrCorner, 0, 0)
            local layoutChanged = false
            -- While Self Position owns the merged header (whole-raid nameList,
            -- applied by ApplySortToHeaders at the end of this pass), a
            -- groupFilter write here would fight its clear on every pass. Cache
            -- the string instead -- ApplySortToHeaders restores it whenever the
            -- nameList bails on unresolved names.
            ns._flatGfStr = gfStr
            local selfOwnsHeader = (s.showSelfFirst or s.showSelfLast) and IsInRaid()
            if not selfOwnsHeader and ns._flatHeader:GetAttribute("groupFilter") ~= gfStr then
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
        -- matching corner anchors there, so the group fills its cell. A
        -- TOPLEFT anchor for these directions displaces the frames a full
        -- group height/width outside the container, mismatching preview/mover.
        local hdrAnchor = "TOPLEFT"
        local hdrOffX, hdrOffY = 0, 0
        if unitGrowth == "UP"   then hdrAnchor = "BOTTOMLEFT"; hdrOffY = -groupH end
        if unitGrowth == "LEFT" then hdrAnchor = "TOPRIGHT";   hdrOffX = groupW  end

        -- "Hide Empty Groups": collapse memberless subgroups so the remaining
        -- groups close ranks (1/2/3/6 instead of a gap at 4/5). Real frames
        -- only; needs live raid roster data, so skipped outside a raid
        -- (GetRaidRosterInfo returns nil there -> would hide every group).
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

    -- Container size based on 4 groups for unlock mode mover. Merged mode's
    -- columnAnchorPoint is always perpendicular to unitGrowth (colAnchor above),
    -- so its actual render axis follows unitGrowth, not the literal groupGrowth
    -- (which can share unitGrowth's axis; Blizzard's header can't express that as
    -- a column direction). Keying the box off groupGrowth there mismatches the
    -- box against what merged mode really renders. Separated mode has no such
    -- header constraint and renders along groupGrowth literally, so it keeps the
    -- original formula.
    local totalW, totalH
    if merged then
        if unitGrowth == "DOWN" or unitGrowth == "UP" then
            totalW = MOVER_GROUPS * groupW + (MOVER_GROUPS - 1) * gs
            totalH = groupH
        else
            totalW = groupW
            totalH = MOVER_GROUPS * groupH + (MOVER_GROUPS - 1) * gs
        end
    else
        if groupGrowth == "DOWN" or groupGrowth == "UP" then
            totalW = groupW
            totalH = MOVER_GROUPS * groupH + (MOVER_GROUPS - 1) * gs
        else
            totalW = MOVER_GROUPS * groupW + (MOVER_GROUPS - 1) * gs
            totalH = groupH
        end
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

-- Coalescing re-entrancy guard: a re-entrant LayoutGroups() call is NOT dropped
-- (would strand stale frames) -- it marks the pass dirty and the in-flight call
-- re-runs on return, bounded to 3 passes so a non-converging header feedback
-- loop (SetAttribute/SetSize -> engine re-anchors children -> our hook -> here)
-- can't spin into a watchdog kill. pcall clears the busy flag on error and
-- rethrows, so one error can't freeze every future layout. State on ns (local cap).
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
-- skipButtons (login window only): run the layout/tier/proxy machinery but
-- skip the per-button restyle loop -- the insecure styling bodies run in the
-- deferred login pass, which then calls this again in full.
ns._emptyList = ns._emptyList or {}
local function ReloadFrames(skipButtons)
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
        -- Active tier override (per-tier growth) via the single cascade authority.
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
    if ns._RefreshProxyModes then ns._RefreshProxyModes() end

    -- Mode flips (Merge Groups toggle, profile swaps) can need a header set
    -- that was not built at login; materialize it before the restyle loop so
    -- the new buttons take this reload's styling like everything else.
    ns._BuildHeaderSet((db.profile.mergeGroups and true) or false)

    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - powerH)
    local texPath = ResolveHealthTexture()

    for _, btn in ipairs(skipButtons and ns._emptyList or allButtons) do
        local d = GetFFD(btn)
        if not d.styled then
            ns._StyleButtonSecure(btn)
            StyleButton(btn)
        end

        -- Window/initialConfigFunction own sizes in combat; skipping here is
        -- safe (out of combat the resize applies normally).
        if not InCombatLockdown() then
            btn:SetSize(bw, bh)
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

        -- Background: through its stamped owner (dark-mode aware), AFTER the
        -- fill texture swap so the anchors bind the new fill edge. Stamps are
        -- cleared first so the restyle re-applies anchors + color; a direct
        -- SetColorTexture here is never overwritten by the stamped health tick.
        if d.bg then
            d._bgSt, d._bgA = nil, nil
            local u = btn:GetAttribute("unit")
            if u and UnitExists(u) then ns._ApplyHealthBg(d, d.health, s, u) end
        end

        -- Power bar (always hide here; UpdateButton handles per-role show). This is a
        -- second writer of health height alongside UpdateButton's own cached transition
        -- (LayoutTopNameBar above sized health assuming power reserved), so drop the
        -- cache or UpdateAllButtons below sees applied == computed and never corrects it.
        d._appliedHidePower = nil
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

        -- Ping marker size + position (overlay exists only after a first ping)
        if d.pingFrame then ns._RFAnchorPing(d) end

        -- Border
        if d.UpdateBorder then d.UpdateBorder() end
    end

    -- Re-layout headers (may switch between flat/grouped)
    LayoutGroups()
    -- Apply tier-based position offset
    if ns._ApplyTierOffset then ns._ApplyTierOffset() end
    RebuildUnitMap()
    UpdateAllButtons()
    -- Immediate range update so new buttons don't flash full alpha
    RangeUpdate()

    -- Friendly Boss Frames and Extra Frames inherit size/growth/spacing/
    -- border/text settings; restyle + re-anchor them with everything else
    -- (growth changes move the anchor points, not just the anchored-to header).
    if ns.FB_Apply then ns.FB_Apply() end
    if ns.XF_Apply then ns.XF_Apply() end

    -- 12.1 aura containers reload with every real pass (direct call inside
    -- the body -- immune to the Options file's setup-time capture of ns.ReloadFrames).
    if ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
end

ns.ReloadFrames = ReloadFrames
ns.PixelSnap = PixelSnap
ns._allButtons = allButtons

-- Global Dark Mode master: RF stores Dark Mode as a fill-color MODE
-- (healthColorMode == "dark"), not a boolean -- enabling remembers the prior
-- mode, disabling restores it, never clobbering a Classic/Custom choice. The
-- party override (party_healthColorMode, present only when the party color
-- section is decoupled) flips the same way. db is set at PLAYER_LOGIN; the
-- closures read it lazily.
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
    local healthH = PixelSnap(bh - ns.RF_HealthPowerInset(s, powerH))
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
                xhealthH = PixelSnap(xbh - ns.RF_HealthPowerInset(s, powerH))
            end
            btn:SetSize(xbw, xbh)
            -- Full height when the power bar is hidden for this role (mirrors
            -- _ResizePartyButtons; avoids a dark strip on OFF-role units since
            -- d.power always exists). Top Name Bar reserves its height from the
            -- top (health top anchor stays -topBarH; only correct height here).
            if d.health then
                d.health:SetHeight(((d.power and d.power:IsShown()) and xhealthH or xbh) - topBarH)
            end
            if d.nameText then d.nameText:SetWidth(xbw * ns.RF_NAME_WIDTH_FRACTION) end
        end
    end
    ns._activeSizeW = w
    ns._activeSizeH = h
    if ns._RefreshProxyModes then ns._RefreshProxyModes() end
    LayoutGroups()
    -- Container footprint may have changed: re-derive the growth-corner anchor
    -- so the pinned corner holds during live slider drags and the unlock
    -- framework's OnSizeChanged can never leave a stale centered position.
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
    local healthH = PixelSnap(bh - ns.RF_HealthPowerInset(s, powerH))
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
                -- Scale derives from frame size (recomputed above): re-apply
                -- the scaled sizes during the drag (same set as the full reload).
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
                if d.nameText then ApplyFont(d.nameText, pp.nameSize or 10) end
                if d.healthText then ApplyFont(d.healthText, pp.healthTextSize or 9) end
                if d.healAbsorbText then ApplyFont(d.healAbsorbText, pp.healAbsorbTextSize or 9) end
                if d.statusText then ApplyFont(d.statusText, pp.statusTextSize or 14) end
            end
        end
    end
    -- Container resize deferred to drag end (SetSize on the container makes
    -- SecureGroupHeaderTemplate re-process children -> blink). Slot offsets +
    -- the header's own size DO follow the live size: keeps the self button
    -- aligned with the stack and the centered child anchors growing from the
    -- correct origin. Pure anchor tracking -- no secure re-process, no blink.
    if ns._PositionPartySlots then
        local cs2 = PixelSnap(s.partyCellSpacing or s.cellSpacing or 2)
        -- Explicit true only: "centered" keeps the default direction.
        local growth2 = s.partyHorizontal and (s.partyFlipGrowth == true and "LEFT" or "RIGHT")
            or (s.partyFlipGrowth == true and "UP" or "DOWN")
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

-- Footprint of the 4-group mover box for a frame size and growth pair. Callers
-- that also derive a corner from the same pair (ns._RFCornerTerms/_RFGrowthCorner)
-- must self-heal (ns._RFEffectiveGrowth) BEFORE calling either, so the size and
-- the corner agree -- this function does not self-heal internally to avoid a
-- caller healing one but not the other.
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

-- TOPLEFT of the BASE (20-man) footprint at the saved unlock position: the shared
-- growth origin for every size tier and the previews. Also returns the base footprint's
-- width/height so corner math never recomputes it (extra return values -- existing
-- two-value callers are unaffected). Returns nil when no position has been saved yet.
ns._RFBaseTopLeft = function()
    local s = db.profile
    local pos = s.unlockPos
    if not pos then return nil end
    local cs = PixelSnap(s.cellSpacing or 2)
    local gs = PixelSnap(s.groupSpacing or 8)
    local ug, gg = ns._RFEffectiveGrowth(s.unitGrowth or "DOWN", s.groupGrowth or "RIGHT", s.mergeGroups)
    local w, h = ns._RFFootprint(s.frameWidth or 72, s.frameHeight or 46, ug, gg, cs, gs)
    local l, t = ns._RFPosTopLeft(pos, w, h)
    return l, t, w, h
end

-- Shared growth-direction helpers. A single source of truth for "is this
-- direction vertical" and for deriving the flat header's point/xOffset/yOffset
-- and columnAnchorPoint from a growth pair -- both _LayoutGroupsImpl and
-- _BuildHeaderSet's header-creation bootstrap need the identical derivation,
-- and previously hand-duplicated it.
ns._RFGrowthIsVertical = function(g)
    return g == "DOWN" or g == "UP"
end

-- First-button point/xOffset/yOffset for a header growing along unitGrowth.
ns._RFHeaderPoint = function(unitGrowth, cs)
    if unitGrowth == "DOWN" then
        return "TOP", 0, -cs
    elseif unitGrowth == "UP" then
        return "BOTTOM", 0, cs
    elseif unitGrowth == "RIGHT" then
        return "LEFT", cs, 0
    else -- LEFT
        return "RIGHT", -cs, 0
    end
end

-- Blizzard's flat header can only wrap into columns when columnAnchorPoint runs
-- perpendicular to unitGrowth -- see ns._RFEffectiveGrowth below for why merged
-- mode never actually reaches a same-axis pair here in practice.
ns._RFColAnchor = function(unitGrowth, groupGrowth)
    if groupGrowth == "DOWN" or groupGrowth == "RIGHT" then
        if ns._RFGrowthIsVertical(unitGrowth) then return "LEFT" end
        return "TOP"
    else -- UP or LEFT
        if ns._RFGrowthIsVertical(unitGrowth) then return "RIGHT" end
        return "BOTTOM"
    end
end

-- Self-heals a same-axis Group/Unit Growth pair when Merge Groups is on (see
-- _RFColAnchor above), applied as a read-time backstop for a pair that reached
-- here without a guarded write (a stale per-tier override, a spec override,
-- hand-edited SavedVariables). Group Growth wins here; the options UI's
-- write-time KeepGrowthPerpendicular uses the same resolution EXCEPT its Unit
-- Growth dropdown, which deliberately lets Unit Growth win instead. No-op if
-- not merged.
ns._RFEffectiveGrowth = function(unitGrowth, groupGrowth, merged)
    if not merged then return unitGrowth, groupGrowth end
    if ns._RFGrowthIsVertical(unitGrowth) == ns._RFGrowthIsVertical(groupGrowth) then
        unitGrowth = ns._RFGrowthIsVertical(unitGrowth) and "RIGHT" or "DOWN"
    end
    return unitGrowth, groupGrowth
end

-- Pinned screen corner implied by a growth pair: frames grow AWAY from this corner, so
-- it stays fixed when a tier's footprint differs from the base. Horizontal side = whichever
-- growth is horizontal (RIGHT pins LEFT edge, LEFT pins RIGHT edge); vertical side likewise
-- (DOWN pins TOP, UP pins BOTTOM). Every ns._RFEffectiveGrowth caller heals a same-axis pair
-- before reaching here whenever merged is true, so this only ever sees one for separated mode
-- (merged=false is a no-op for _RFEffectiveGrowth), where all 16 combinations are legitimate
-- and this tie-break (UP beats BOTTOM, LEFT beats RIGHT, default TOP+LEFT) is what existing
-- per-tier offsets are calibrated against -- matching Blizzard's own same-axis corner instead
-- would be dead code here for merged and a silent position-shift regression for separated.
ns._RFGrowthCorner = function(unitGrowth, groupGrowth)
    local h = (unitGrowth == "LEFT" or groupGrowth == "LEFT") and "RIGHT" or "LEFT"
    local v = (unitGrowth == "UP" or groupGrowth == "UP") and "BOTTOM" or "TOP"
    return v .. h
end

-- Signed corner terms: how far a tier footprint's TOPLEFT shifts from the base
-- footprint's TOPLEFT so the growth-derived corner stays pinned. THE single copy of the
-- corner arithmetic -- the forward origin (_RFTierTopLeft), the one-time offset rebase
-- (conversion #2 in _NormalizeTierOffsetAnchors) and the mover save-path inverse
-- (_RFRebaseSavedCenter) all read these two values. Both terms are zero when the
-- footprints match, so the base tier is exact by arithmetic.
ns._RFCornerTerms = function(tw, th, bw, bh, unitGrowth, groupGrowth)
    local corner = ns._RFGrowthCorner(unitGrowth, groupGrowth)
    local kx = (corner:find("RIGHT") and (bw - tw)) or 0
    local ky = (corner:find("BOTTOM") and -(bh - th)) or 0
    return kx, ky
end

-- THE centralized growth-corner origin: returns the TOPLEFT (UIParent bottom-left space)
-- for a tier footprint (tw, th) whose growth-derived corner is pinned at the BASE
-- footprint's same corner, plus the tier's saved offsets. Every consumer (live
-- _ApplyTierOffset, size previews) anchors through this one function so previews land
-- exactly where live frames land. Base footprint / zero offsets: every corner term
-- cancels, plain base top-left -- profiles without raidSizeOverrides unaffected. Returns
-- nil with no saved unlock position.
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
    -- User-tunable switch boundaries (per-tier cog sliders): the LOWER tiers
    -- store the highest count they COVER (sizeCap), the UPPER tiers the
    -- count they ENGAGE at (sizeMin). Absent keys reproduce the classic
    -- cascade exactly (10/15/20, 25 engaging at 21, 30 at 26, 40 at 31), so
    -- profiles that never touch the sliders resolve byte-identically.
    local o10, o15, o25, o30, o40 = overrides[10], overrides[15], overrides[25], overrides[30], overrides[40]
    local b10 = (o10 and o10.sizeCap) or 10
    local b15 = (o15 and o15.sizeCap) or 15
    local b25 = (o25 and o25.sizeMin) or 21
    local b30 = (o30 and o30.sizeMin) or 26
    local b40 = (o40 and o40.sizeMin) or 31
    local tier
    if numMembers <= b10 then    tier = 10
    elseif numMembers <= b15 then tier = 15
    elseif numMembers < b25 then tier = 20
    elseif numMembers < b30 then tier = 25
    elseif numMembers < b40 then tier = 30
    else                         tier = 40
    end
    if tier == 20 then return 20, nil end
    local ov
    if tier < 20 then
        ov = overrides[tier] or (tier == 10 and overrides[15]) or nil
    else
        ov = overrides[tier]
        if not ov and tier == 30 then ov = overrides[25] end
        if not ov and tier == 40 then ov = overrides[30] or overrides[25] end
    end
    return tier, ov or nil
end

-- Inverse of the corner scheme, for the unlock mover SAVE path only. The framework
-- measures a dragged container's CENTER from its LIVE bounds -- i.e. on the ACTIVE
-- tier's footprint -- but every apply interprets unlockPos as the BASE footprint's
-- center. Convert a live-measured center to its base-footprint equivalent so the next
-- _ApplyTierOffset reproduces the drop position (within one physical pixel of
-- snapping). With the base tier active, or no overrides defined, every term cancels and
-- the center passes through unchanged -- zero behavior change for base saves.
ns._RFRebaseSavedCenter = function(cx, cy)
    local s = db.profile
    local _, ov = ns._RFResolveTierOverride(ns._GetEffectiveRaidSize())
    if not ov then return cx, cy end
    local cs = PixelSnap(s.cellSpacing or 2)
    local gs = PixelSnap(s.groupSpacing or 8)
    local bug, bgg = ns._RFEffectiveGrowth(s.unitGrowth or "DOWN", s.groupGrowth or "RIGHT", s.mergeGroups)
    local bw, bh = ns._RFFootprint(s.frameWidth or 72, s.frameHeight or 46, bug, bgg, cs, gs)
    local ug, gg = ns._RFEffectiveGrowth(
        ov.unitGrowth or s.unitGrowth or "DOWN", ov.groupGrowth or s.groupGrowth or "RIGHT", s.mergeGroups)
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

-- One-time conversions (markers travel INSIDE raidSizeOverrides, so imported/swapped
-- profiles self-convert -- no migration-flag inheritance trap). Each applies at most
-- once, in order, rebasing offsets against the PREVIOUS scheme's post-conversion values
-- so every tier's on-screen position is preserved (within one physical pixel of rounding).
--   #1 (_topLeftAnchored): old "re-anchor container at unlockPos.point" offsets ->
--      offsets relative to the base footprint's TOPLEFT.
--   #2 (_cornerAnchored): TOPLEFT-relative offsets -> offsets relative to the
--      growth-derived pinned corner (ns._RFGrowthCorner). Only tiers whose effective
--      growth pins RIGHT and/or BOTTOM change; DOWN+RIGHT tiers keep identical offsets.
ns._NormalizeTierOffsetAnchors = function()
    local s = db and db.profile
    if not s then return end
    local ov = s.raidSizeOverrides
    if not ov then return end
    -- Heal string-keyed numeric tiers ("25" beside 25): planted by the spec
    -- override system's container fabrication before it learned to use the numeric
    -- form. The module reads tiers numerically, so a phantom never renders yet
    -- captures every override read/write for its tier. With a numeric twin the
    -- phantom is dropped (the twin is the rendered truth; override values re-apply
    -- from their store at the next boundary); without one it becomes the numeric
    -- tier it was meant to be. Must run BEFORE the markers early-return below:
    -- converted profiles are the common carriers.
    local phantoms
    for k, v in pairs(ov) do
        if type(k) == "string" and tonumber(k) ~= nil and type(v) == "table" then
            phantoms = phantoms or {}
            phantoms[#phantoms + 1] = k
        end
    end
    if phantoms then
        for i = 1, #phantoms do
            local k = phantoms[i]
            local n = tonumber(k)
            if ov[n] == nil then ov[n] = ov[k] end
            ov[k] = nil
        end
    end
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
                    local ug, gg = ns._RFEffectiveGrowth(
                        o.unitGrowth or s.unitGrowth or "DOWN",
                        o.groupGrowth or s.groupGrowth or "RIGHT", s.mergeGroups)
                    local tw, th = ns._RFFootprint(
                        o.width or s.frameWidth or 72, o.height or s.frameHeight or 46, ug, gg, cs, gs)
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
                    local ug, gg = ns._RFEffectiveGrowth(
                        o.unitGrowth or s.unitGrowth or "DOWN",
                        o.groupGrowth or s.groupGrowth or "RIGHT", s.mergeGroups)
                    local tw, th = ns._RFFootprint(
                        o.width or s.frameWidth or 72, o.height or s.frameHeight or 46, ug, gg, cs, gs)
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

-- Apply tier-based position to the container frame. The active tier's 4-group footprint
-- pins its growth-derived corner (ns._RFGrowthCorner, from the tier's EFFECTIVE unit +
-- group growth) at the BASE (20-man) footprint's same corner, plus the tier's saved
-- offsets, via the shared ns._RFTierTopLeft origin -- so a larger/smaller tier grows away
-- from the pinned corner (e.g. RIGHT+DOWN pins top-left, LEFT+UP pins bottom-right).
-- unlockPos itself is untouched (saved tier offsets were rebased once per scheme by
-- _NormalizeTierOffsetAnchors). Base tier or no overrides: every corner term cancels,
-- identical to the plain base top-left.
--
-- While anchored, the unlock anchor system owns the container's position, so the tier
-- offset is folded into the position IT computes rather than applied on top afterwards --
-- applying it after would sit outside the anchor's idempotent guard and reposition every pass forever.
EllesmereUI._anchorExtraOffset = EllesmereUI._anchorExtraOffset or {}
EllesmereUI._anchorExtraOffset["RF_RaidFrames"] = function()
    local _, ov = ns._RFResolveTierOverride(ns._GetEffectiveRaidSize())
    return (ov and ov.offsetX) or 0, (ov and ov.offsetY) or 0
end

ns._ApplyTierOffset = function()
    if not containerFrame or InCombatLockdown() then return end
    -- Element-anchored container: the unlock anchor system owns the POSITION
    -- (absolute coords recomputed from the anchor target), so repositioning
    -- from unlockPos here would clobber it on every roster/tier pass.
    --
    -- The per-tier offset still applies, though: it is added ON TOP of whatever the
    -- anchor computed, rather than replacing it. Skipping it outright is what made the
    -- per-tier offset fields silently inert for anyone who anchored the raid frames to
    -- another element -- the setting was saved, shown in the options, and did nothing.
    if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("RF_RaidFrames") then
        -- The anchor owns the position and now folds the tier offset into it
        -- (see _anchorExtraOffset above), so a tier change just needs the
        -- anchor re-run; moving the container from here would fight it.
        if EllesmereUI.ReapplyUnlockAnchor then
            EllesmereUI.ReapplyUnlockAnchor("RF_RaidFrames")
        end
        return
    end
    local s = db.profile
    if not s.unlockPos then return end
    local _, ov = ns._RFResolveTierOverride(ns._GetEffectiveRaidSize())
    local cs = PixelSnap(s.cellSpacing or 2)
    local gs = PixelSnap(s.groupSpacing or 8)
    local fw = (ov and ov.width) or s.frameWidth or 72
    local fh = (ov and ov.height) or s.frameHeight or 46
    local ug, gg = ns._RFEffectiveGrowth(
        (ov and ov.unitGrowth) or s.unitGrowth or "DOWN",
        (ov and ov.groupGrowth) or s.groupGrowth or "RIGHT", s.mergeGroups)
    local tw, th = ns._RFFootprint(fw, fh, ug, gg, cs, gs)
    local x, y = ns._RFTierTopLeft(tw, th, ug, gg,
        (ov and ov.offsetX) or 0, (ov and ov.offsetY) or 0)
    if not x then return end
    containerFrame:ClearAllPoints()
    containerFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", PixelSnap(x), PixelSnap(y))
    -- Hidden container (frames not shown -- solo, party, or just left the raid):
    -- LayoutGroups no longer runs for it, so re-derive the SIZE here too. Left alone,
    -- the dormant container keeps the LAST raid tier's footprint, and unlock mode's
    -- mover reads live container geometry: the control appears at a stale spot with a
    -- stale box, and a drag-save there stores a center measured on the wrong footprint
    -- (off by half the width delta -- the "whole layout drifted left after a raid"
    -- corruption). While shown, LayoutGroups owns the size as before.
    if not containerFrame:IsShown() then
        containerFrame:SetSize(tw, th)
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
        -- secret-safe path living non-spell-range units take, so corpses fade with
        -- distance. (A rez-spell-only check would force full alpha for players with
        -- no rez or an indeterminate rez range.)
        ApplyRangeAlphaSecret(btn, UnitInRange(unit), 1, oorAlpha)
    elseif usesSpellRange then
        local r = C_Spell_IsSpellInRange(playerFriendlySpell, unit)
        if r == true then
            ApplyRangeAlpha(btn, 1)
        elseif r == false then
            ApplyRangeAlpha(btn, oorAlpha)
        else
            -- r == nil: no range relationship to this unit (unit-targeted spell, so a
            -- same-zone out-of-range target already returned false above) -- almost
            -- always a different zone (or a brief untargetable/LOS blip). Resolve via
            -- the secret-safe ~40yd UnitInRange (false -> faded) rather than holding the
            -- last alpha, which stranded a zone-departed unit at its old in-range alpha.
            -- Cannot reintroduce the 25-vs-40yd boundary flicker: that needed the spell
            -- check to return nil AT the boundary, which a stable far same-zone target does not.
            ApplyRangeAlphaSecret(btn, UnitInRange(unit), 1, oorAlpha)
        end
    else
        ApplyRangeAlphaSecret(btn, UnitInRange(unit), 1, oorAlpha)
    end
end
ns._UpdateButtonRange = UpdateButtonRange

-- Refiner handles only what UNIT_IN_RANGE_UPDATE cannot: the tighter friendly-spell
-- range (Evoker/Rogue). Dead units use the event-driven UnitInRange path like living
-- units, but are still polled so a spell-range class hands a revived unit back to its
-- tight spell range (one-shot resync via _rangeWasDead). Living, non-spell-range units
-- are owned by the event and skipped here, so the poll does ~no work for a stable raid.
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
    for unit, btn in pairs(unitToButton) do UpdateButtonRange(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do UpdateButtonRange(unit, btn) end
    for unit, btn in pairs(ns._xfUnitToButton) do UpdateButtonRange(unit, btn) end
end
ns._RangeSeedAll = RangeUpdate

local function RangeRefineAll()
    for unit, btn in pairs(unitToButton) do RefineButtonRange(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do RefineButtonRange(unit, btn) end
    for unit, btn in pairs(ns._xfUnitToButton) do RefineButtonRange(unit, btn) end
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
--  Throttled 1s ticker: UNIT_AURA stops firing for invisible/DC'd units and the
--  render-visibility edge has no event, so a unit that ghosts (loadscreen, out
--  of render range, disconnect) keeps whatever its containers last parsed. On
--  regain the containers are re-parsed in place (the same UpdateAllAuras lever
--  the assist gate uses on its own false->true edge).
-------------------------------------------------------------------------------
local ghostTicker = nil

local function GhostAuraCheck()
    local function checkUnit(unit, btn)
        local d = GetFFD(btn)
        if not UnitIsVisible(unit) or not UnitIsConnected(unit) then
            if not d.ghostCleared then
                d.ghostCleared = true
                -- Binding at ghost time: a reassignment inside the window already
                -- re-parsed the containers (RFC_OnUnitAssigned), so the regain pass
                -- skips a button whose binding moved.
                d.ghostUnit = d.rfcUnit
            end
        else
            if d.ghostCleared then
                d.ghostCleared = false
                -- unitToButton only ever gains entries, so unit/btn can be a stale
                -- pairing: re-parse only containers still bound to this unit.
                if d.rfcUnit == unit and d.ghostUnit == unit then
                    if d.rfcDebuffs then d.rfcDebuffs:UpdateAllAuras() end
                    if d.rfcDispLoc then d.rfcDispLoc:UpdateAllAuras() end
                    if d.rfcDispel then d.rfcDispel:UpdateAllAuras() end
                    if d.rfcBm then d.rfcBm:UpdateAllAuras() end
                    if d.rfcBmChain then
                        for _, cc in pairs(d.rfcBmChain) do cc:UpdateAllAuras() end
                    end
                    if d.rfcBmSimple then d.rfcBmSimple:UpdateAllAuras() end
                    if d.dmTiles then
                        for _, c in pairs(d.dmTiles) do c:UpdateAllAuras() end
                    end
                end
                d.ghostUnit = nil
            end
        end
    end
    for unit, btn in pairs(unitToButton) do checkUnit(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do checkUnit(unit, btn) end
    for unit, btn in pairs(ns._xfUnitToButton) do checkUnit(unit, btn) end
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
    -- Raid frames coming or going is the one change a tracker cannot learn from
    -- its own roster events (mirrors the party call in _UpdatePartyVisibility).
    if ns._NotifyTrackerProviders then ns._NotifyTrackerProviders() end

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
        -- Skip heavy refresh at combat end if roster didn't change. Per-unit events
        -- (UNIT_HEALTH, UNIT_AURA, etc.) kept buttons in sync during combat, so a full
        -- rebuild is only needed when the roster changed or we transition from hidden
        -- to visible. Heavy content rebuild ONLY when it could actually be stale: a
        -- real hidden->visible transition (unitToButton was wiped on hide) or a caller
        -- that flagged a roster/size change. Re-checking visibility while already shown
        -- and unchanged skips the 40-button rebuild -- the live per-unit events kept
        -- every button current the whole time. This generalizes the old combat-exit
        -- "lightweight" skip to every caller (preview restore,
        -- EnsureRealFramesRestored, etc.) so a redundant visibility recompute can never
        -- trigger a full refresh spike.
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
        wipe(unitToButton)
    end
end
ns.UpdateVisibility = UpdateVisibility

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
        local frameStrataDirty = ns._frameStrataDirty
        if frameStrataDirty and ns.ApplyFrameStrata then ns.ApplyFrameStrata() end
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
        UpdateVisibility()
        ns._UpdatePartyVisibility()
        if rosterDirty or sizeTierDirty then
            if framesVisible then
                if sizeTierDirty then
                    -- Size tier crossed during combat: full reload now safe
                    ReloadFrames()
                else
                    LayoutGroups()
                end
            end
            -- Same-dimension tier changes take the LayoutGroups branch; reapply offset
            -- so the container lands at the correct tier. Outside the framesVisible
            -- gate for the same reason as the roster path: a raid left mid-combat must
            -- still re-base the now-hidden container once combat ends.
            if ns._ApplyTierOffset then ns._ApplyTierOffset() end
            if ns._partyFramesVisible then
                ns._LayoutPartyFrames()
            end
        end
        -- Party container geometry deferred by a combat-time _ERF_RefreshAll.
        if ns._partyGeomDirtyInCombat then
            ns._partyGeomDirtyInCombat = nil
            if ns._ApplyPartyContainerGeometry then ns._ApplyPartyContainerGeometry() end
        end
        -- Flush any power show/hide transitions deferred during combat (see UpdateButton);
        -- only the buttons actually marked dirty get a repaint.
        if ns._powerDirtyInCombat then
            ns._powerDirtyInCombat = nil
            for _, btn in ipairs(allButtons) do
                local d = GetFFD(btn)
                if d._powerDirtyInCombat then
                    d._powerDirtyInCombat = nil
                    UpdateButton(btn)
                end
            end
            if ns._partyAllButtons then
                for _, btn in ipairs(ns._partyAllButtons) do
                    local d = GetFFD(btn)
                    if d._powerDirtyInCombat then
                        d._powerDirtyInCombat = nil
                        UpdateButton(btn)
                    end
                end
            end
        end
        -- Restore child frame levels after a deferred strata change.
        if frameStrataDirty then
            if not (sizeTierDirty and framesVisible) then ReloadFrames() end
            if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
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
        -- Unit tokens reindex on roster changes; a latched rez offer keyed by the
        -- old token would paint on the wrong player, so drop them all.
        if event == "GROUP_ROSTER_UPDATE" then wipe(ns._rezPend) end
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
            end
            -- Party frames: rebuild unit map during combat
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
            end
            -- Combat zone-ins deliver GROUP_ROSTER_UPDATE in storms; unit maps stay
            -- per-fire (routing must be correct immediately) but the paint coalesces to
            -- one next-frame pass reading the storm's FINAL state (same NewTimer(0)
            -- shape as the OOC branch). Paint work is unprotected, so this is combat-safe.
            if not ns._crPaintTimer and (framesVisible or ns._partyFramesVisible) then
                ns._rosterArmAt = GetTime()
                ns._crPaintTimer = C_Timer.NewTimer(0, function()
                    ns._crPaintTimer = nil
                    if framesVisible then
                        for _, btn in ipairs(allButtons) do
                            local u = btn:GetAttribute("unit")
                            if u and btn:IsVisible() then
                                ns._RosterPassPaint(btn, u)
                                ns._UpdateButtonRange(u, btn)
                            end
                        end
                    end
                    if ns._partyFramesVisible then
                        for _, btn in ipairs(ns._partyAllButtons) do
                            local u = btn:GetAttribute("unit")
                            if u and btn:IsVisible() then
                                ns._RosterPassPaint(btn, u)
                                ns._UpdateButtonRange(u, btn)
                            end
                        end
                    end
                end)
            end
            return
        end
        if ns._rosterUpdateTimer then
            ns._rosterUpdateTimer:Cancel()
        else
            -- First event of this cycle: paints stamped at or after this instant
            -- came from the assignment hook (or a full pass) inside the cycle.
            ns._rosterArmAt = GetTime()
        end
        ns._rosterUpdateTimer = C_Timer.NewTimer(0, function()
            ns._rosterUpdateTimer = nil
            -- Roster changed (OOC): never force UpdateVisibility's full 40-button
            -- rebuild. The per-button OnAttributeChanged hook already fully repainted
            -- (incl. auras) every reassigned button, so a blanket x40 aura re-scan is
            -- redundant; react per-unit instead. UpdateButton still runs on every visible
            -- button (no aura rescan) so leader/role/marker/health stay correct for
            -- UNCHANGED-token units (e.g. a new leader whose token didn't change).
            local numMembers = ns._GetEffectiveRaidSize()
            local newW, newH = ns._GetRaidSizeFrameDimensions(numMembers > 0 and numMembers or 1)
            local tierChanged = (newW ~= ns._activeSizeW or newH ~= ns._activeSizeH)
            local wasVis = framesVisible
            ns._visForceRebuild = nil
            UpdateVisibility()
            ns._UpdatePartyVisibility()
            if framesVisible then
                if tierChanged then
                    -- Tier changed: full reload (recalculates _activeSizeW/H, restyles).
                    ReloadFrames()
                    if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
                elseif not wasVis then
                    -- Hidden->visible transition: UpdateVisibility already ran the
                    -- full rebuild (RebuildUnitMap + UpdateAllButtons); just lay out.
                    LayoutGroups()
                else
                    -- Already visible, same tier: light refresh only. Aura
                    -- full-rescans are intentionally skipped (hook + UNIT_AURA
                    -- keep them current); the per-button pass repaints only what
                    -- the roster can change (see ns._RosterPassPaint).
                    RebuildUnitMap()
                    if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
                    for _, btn in ipairs(allButtons) do
                        local u = btn:GetAttribute("unit")
                        if u and btn:IsVisible() then ns._RosterPassPaint(btn, u) end
                    end
                    LayoutGroups()
                end
            end
            -- Re-derive the growth-corner anchor after any roster-driven layout.
            -- tierChanged only compares frame DIMENSIONS, so two same-sized tiers (fresh
            -- tiers copy the base 20-man size) take the bare-LayoutGroups branches even
            -- with different offsets/growth -- without this, a roster that refined from
            -- an early undercount (streaming subgroup data at join) stuck the container on
            -- the small-tier position until the next full reload. Cheap, idempotent,
            -- self-gates on combat. Deliberately OUTSIDE framesVisible: a raid left mid-
            -- combat still needs the dormant container re-based (it re-derives its own
            -- size while hidden) or unlock mode saves against stale raid-tier geometry.
            if ns._ApplyTierOffset then ns._ApplyTierOffset() end
            if ns._partyFramesVisible then
                ns._LayoutPartyFrames()
            end
            -- Healer Mana Display: its rebuild normally rides the raid/party
            -- frame paths above (UpdatePowerEventRegistration tails). A roster
            -- change that lands with BOTH frame sets hidden -- leaving a raid
            -- to solo, or to a party while EUI party frames are disabled --
            -- skipped every rebuild, so the display kept its last group's
            -- content (raid-mode names included) indefinitely.
            if not framesVisible and not ns._partyFramesVisible then
                if ns.HM_Rebuild then ns.HM_Rebuild() end
            end
        end)
    elseif not framesVisible and not ns._partyFramesVisible then
        -- Skip all per-unit event processing when no frames are visible
        return
    elseif event == "UNIT_IN_RANGE_UPDATE" then
        -- Standard ~40yd range change for this unit (event-driven, debounced).
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            ns._UpdateButtonRange(arg1, btn)
        end
    elseif event == "UNIT_PHASE" then
        -- Phasing doesn't fire UNIT_IN_RANGE_UPDATE; re-evaluate all (rare).
        if ns._RangeSeedAll then ns._RangeSeedAll() end
    elseif event == "UNIT_HEALTH" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            -- Latched rez offer: the accept lands as a health edge (no further
            -- INCOMING_RESURRECT_CHANGED). This edge OWNS the alive-clear (the
            -- predicate is deliberately pure), then repaints the shared icon.
            -- Clearing here also stops a lingering offer window from painting a
            -- fresh, unrezzed corpse if the unit dies again. Nil lookup for
            -- everyone else.
            local hadRez = ns._rezPend[arg1]
            if hadRez ~= nil and hadRez ~= true and not UnitIsDeadOrGhost(arg1) then
                ns._rezPend[arg1] = nil
            end
            ns._UpdateButtonHealth(btn, arg1)
            if hadRez then UpdateReadyCheck(btn, arg1) end
        end
    elseif event == "UNIT_MAXHEALTH" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            -- Same latch ownership as UNIT_HEALTH: on accept both fire in
            -- unguaranteed order, and whichever runs first must fix the icon.
            local hadRez = ns._rezPend[arg1]
            if hadRez ~= nil and hadRez ~= true and not UnitIsDeadOrGhost(arg1) then
                ns._rezPend[arg1] = nil
            end
            ns._UpdateButtonHealth(btn, arg1)
            ns._ResettleButtonHealth(btn)
            -- Max moves the absorb bars' range (see the header dispatcher's
            -- UNIT_MAXHEALTH branch for the full rationale).
            local dmx = GetFFD(btn)
            if dmx._absActive then ns._MarkAbsorbDirty(btn, arg1) end
            if hadRez then UpdateReadyCheck(btn, arg1) end
        end
    elseif event == "UNIT_POWER_UPDATE" then
        -- Healer Mana Display rides the same per-unit registration: one hash
        -- lookup when off/empty, one text repaint when this unit has a row.
        local hmRows = ns._hmUnitRows
        if hmRows and hmRows[arg1] then ns._HMUpdateValue(arg1) end
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn and GetFFD(btn).power then
            local d = GetFFD(btn)
            -- Value only (Blizzard's CompactUnitFrame_UpdatePower shape): type,
            -- color and bounds belong to the UNIT_DISPLAYPOWER edge below; nil
            -- = not derived yet for this occupant, derive once.
            local pType = d._pwType
            if pType == nil then
                ns._RFPowerTypeEdge(d, arg1)
                pType = d._pwType
            end
            -- Percent-based, secret-safe (see UpdateButton power block).
            d.power:SetValue(UnitPowerPercent(arg1, pType, true, CurveConstants.ScaleTo100))
        end
    elseif event == "UNIT_DISPLAYPOWER" then
        -- The displayed power type changed (forms, spec swaps, vehicles):
        -- re-derive type + color + bounds once, then push the value.
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn and GetFFD(btn).power then
            local d = GetFFD(btn)
            ns._RFPowerTypeEdge(d, arg1)
            d.power:SetValue(UnitPowerPercent(arg1, d._pwType, true, CurveConstants.ScaleTo100))
        end
    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
        or event == "UNIT_HEAL_PREDICTION" or event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            -- The event IS the arm: plainly observable even while the values
            -- are secret. Paint coalesces to once per render frame.
            -- Prediction is view-gated: with the feature off for this button's
            -- view the event changes no pixel and must not arm.
            local dd = GetFFD(btn)
            if event == "UNIT_HEAL_PREDICTION" then
                local sv = dd._isParty and ns._scaledPartyProxy
                    or (dd._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
                if sv.healPrediction then
                    ns._AbArm(btn, arg1, dd)
                    ns._MarkAbsorbDirty(btn, arg1)
                end
            else
            if event ~= "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then ns._AbArm(btn, arg1, dd) end
            ns._MarkAbsorbDirty(btn, arg1)
            if event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then ns.UpdateHealAbsorbTextFor(btn, arg1) end
            if event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
                ns._UpdateButtonHealth(btn, arg1)
                ns._ResettleButtonHealth(btn)
            end
            end -- prediction view-gate else
        end
    elseif event == "UNIT_NAME_UPDATE" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        -- The name arriving is also when the class becomes known (Blizzard's
        -- own comment on this edge): drop the cached class token first.
        if btn then GetFFD(btn)._clsTok = nil; UpdateButton(btn) end
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
            local d = GetFFD(btn)
            if d.threatFrame then
                local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
                local bs = s.threatBorderSize or 0
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
        end
    elseif event == "UNIT_FLAGS" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then ns._UpdateCombatIconFor(arg1, btn) end
    elseif event == "PLAYER_FLAGS_CHANGED" or event == "UNIT_CONNECTION" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            if event == "UNIT_CONNECTION" then GetFFD(btn)._clsTok = nil end
            UpdateButton(btn)
            -- Connection changes don't fire UNIT_IN_RANGE_UPDATE; re-evaluate
            -- range so offline units take their fixed alpha and reconnecting
            -- units return to the normal out-of-range fade.
            if event == "UNIT_CONNECTION" then ns._UpdateButtonRange(arg1, btn) end
        end
    elseif event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE" then
        -- Only status text / health color changes (online/offline). The payload
        -- names the unit: repaint its button(s) alone. The full sweeps remain the
        -- fallback for a unit no button maps yet (token shape we do not route).
        local btn = arg1 and (unitToButton[arg1] or ns._partyUnitToButton[arg1])
        if btn then
            local pv = GetFFD(btn)._isParty and ns._partyPvActive or previewActive
            if not pv and btn:IsVisible() then UpdateButton(btn) end
            local xf = ns._xfUnitToButton[arg1]
            if xf and not previewActive and xf:IsVisible() then UpdateButton(xf) end
        else
            if not previewActive then
                for _, b in ipairs(allButtons) do
                    local u = b:GetAttribute("unit")
                    if u and b:IsVisible() then UpdateButton(b) end
                end
            end
            if not ns._partyPvActive then
                for _, b in ipairs(ns._partyAllButtons) do
                    local u = b:GetAttribute("unit")
                    if u and b:IsVisible() then UpdateButton(b) end
                end
            end
        end
    elseif event == "RAID_TARGET_UPDATE" then
        ns._UpdateRaidMarkers()
    elseif event == "PLAYER_TARGET_CHANGED" then
        ns._UpdateTargetBorders()
    elseif event == "READY_CHECK" then
        readyCheckActive = true
        for _, btn in ipairs(allButtons) do
            local u = btn:GetAttribute("unit")
            if u and btn:IsVisible() then UpdateReadyCheck(btn, u) end
        end
        for _, btn in ipairs(ns._partyAllButtons) do
            local u = btn:GetAttribute("unit")
            if u and btn:IsVisible() then UpdateReadyCheck(btn, u) end
        end
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
        -- Fires with a unit payload when a rez starts/stops on that unit. The stop
        -- edge on a still-dead unit that was being cast on latches the offer window
        -- (ns._RFRezShown keeps the icon up until accept/expiry); the single-shot
        -- timer is the only thing that repaints an untouched corpse at expiry.
        if arg1 then
            if UnitHasIncomingResurrection(arg1) then
                ns._rezPend[arg1] = true
            elseif ns._rezPend[arg1] == true then
                if UnitIsDeadOrGhost(arg1) then
                    local exp = GetTime() + 60
                    ns._rezPend[arg1] = exp
                    local unit = arg1
                    C_Timer.After(60.1, function()
                        if ns._rezPend[unit] ~= exp then return end
                        ns._rezPend[unit] = nil
                        local b = unitToButton[unit] or ns._partyUnitToButton[unit]
                        if b and b:IsVisible() then
                            if ns._UpdateButtonHealth then ns._UpdateButtonHealth(b) end
                            UpdateReadyCheck(b, unit)
                        end
                    end)
                else
                    ns._rezPend[arg1] = nil
                end
            end
        end
        -- Refresh the status text (so DEAD hides while rezzing / reappears after)
        -- as well as the shared rez icon.
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn and btn:IsVisible() then
            if ns._UpdateButtonHealth then ns._UpdateButtonHealth(btn) end
            UpdateReadyCheck(btn, arg1)
        end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if ns.BM_RebuildLookup then ns.BM_RebuildLookup(db) end
        -- The player's effective role is spec-derived (EllesmereUI.UnitEffectiveRole),
        -- so the player's own spec swap is a role change for every role consumer:
        -- mirror the PLAYER_ROLES_ASSIGNED refresh and repaint role icons. The
        -- event also fires for other units' spec updates; only the player's
        -- changes our answers.
        if arg1 == "player" and not inCombat then
            if framesVisible and ns._ApplySortToHeaders then
                ns._ApplySortToHeaders()
            end
            if ns._partyFramesVisible
                and (db.profile.partyPrioritizeClass or ns._InArena())
                and ns._LayoutPartyFrames then
                ns._LayoutPartyFrames()
            end
            if ns._UpdateRoleIcons then ns._UpdateRoleIcons() end
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
            UpdateVisibility()
            ns._UpdatePartyVisibility()
            if framesVisible then
                -- Full reload ONLY when the size tier actually changed across the zone
                -- -- recalculating tier dimensions is this call's whole purpose, and
                -- with the tier unchanged the restyle would re-derive identical values
                -- on every button. The unchanged path heals just what zoning can
                -- invalidate: private-aura anchor geometry (baked in at registration;
                -- the unit-guarded rebuild paths skip re-registration when tokens are
                -- unchanged), range alpha, and the boss/extra inheritors. Content
                -- staleness is covered by the per-unit event storm that follows every
                -- zone-in (the same model the roster path documents above).
                local numMembers = ns._GetEffectiveRaidSize()
                local newW, newH = ns._GetRaidSizeFrameDimensions(numMembers > 0 and numMembers or 1)
                local tierChanged = (newW ~= ns._activeSizeW or newH ~= ns._activeSizeH)
                if not tierChanged and numMembers > 0 then
                    local _, newOv = ns._RFResolveTierOverride(numMembers)
                    if newOv ~= ns._activeTierOverride then tierChanged = true end
                end
                if tierChanged then
                    ReloadFrames()
                else
                    RangeUpdate()
                    if ns.FB_Apply then ns.FB_Apply() end
                    if ns.XF_Apply then ns.XF_Apply() end
                end
            end
            if ns._partyFramesVisible then
                -- Full party reload (not just layout), mirroring the raid branch above:
                -- private aura anchors registered during the loading screen can carry
                -- stale geometry (icon size / border scale are baked in at
                -- registration), and the unit-guarded rebuild paths skip
                -- re-registration when units are unchanged. ReloadPartyFrames
                -- recomputes the Auto Resize scale and re-registers every anchor.
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
-- File-scope creation: ns._ResolveFrameStrata is not defined yet here. The
-- saved strata lands via OnEnable's ApplyFrameStrata call every login.
ns._partyContainerFrame:SetFrameStrata("LOW")
ns._partyContainerFrame:Hide()

-------------------------------------------------------------------------------
--  Party frames: real SecureGroupHeader (5 buttons, reuses all raid rendering)
--  Minimal infrastructure -- StyleButton, UpdateButton, etc.
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

ns._PARTY_SECTION_ORDER = {
    "healthBar", "absorbs", "powerBar", "textDisplay", "indicators", "dispels", "topNameBar",
    "rangeTooltip",
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
}

do
    local map = {
        healthBar = {
            "healthBarTexture", "healthBarOpacity", "healthColorMode",
            "customFillColor", "dynamicColor100", "dynamicColor50", "dynamicColor0",
            "customBgColor", "bgClassColored", "bgDarkness", "smoothBars",
            "healPrediction", "healPredOpacity", "healPredColor",
            "healthVerticalFill",
            -- Drawn as "Threat Borders" on the Health Bar row, so it files here.
            "threatBorderSize",
        },
        absorbs = {
            "absorbStyle", "absorbOpacity", "absorbColor", "absorbEdgeMode", "showOvershield",
            "overshieldMode",
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
            "powerUniformAnchors", "extendHealthBehindPower",
        },
        textDisplay = {
            "nameSize", "nameMaxLength", "nameColorMode", "nameCustomColor",
            "namePosition", "nameOffsetX", "nameOffsetY",
            "healthTextMode", "healthTextColorMode", "healthTextCustomColor",
            "healthTextSize", "healthTextPosition", "healthTextOffsetX", "healthTextOffsetY",
            "healAbsorbTextMode", "healAbsorbTextColorMode", "healAbsorbTextCustomColor",
            "healAbsorbTextSize", "healAbsorbTextPosition", "healAbsorbTextOffsetX", "healAbsorbTextOffsetY",
        },
        indicators = {
            "roleIconStyle", "roleIconSize", "roleIconPosition", "roleIconOffsetX", "roleIconOffsetY", "roleIconHideInCombat",
            "roleIconBehindBorder",
            "showRoleForTank", "showRoleForHealer", "showRoleForDPS",
            "showRaidMarker", "raidMarkerSize", "raidMarkerPosition", "raidMarkerOffsetX", "raidMarkerOffsetY",
            "showPingMarker", "pingMarkerSize", "pingMarkerPosition", "pingMarkerOffsetX", "pingMarkerOffsetY",
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
            "targetBorderEnabled", "targetBorderSize", "targetBorderColor", "targetBorderAlpha",
        },
        -- Must list every key the DISPELS section of the options page draws:
        -- the party tab's blocking overlay is sized from that section's y-range,
        -- so a control there is editable whenever "dispels" is unsynced. A key
        -- filed under another section (or missing) is still editable but writes
        -- the shared raid value.
        dispels = {
            "dispelBorderSize", "dispelOverlay", "dispelOverlayOpacity", "dispelShowAll",
            "showDispelIcons", "dispelIconPosition", "dispelIconOffsetX", "dispelIconOffsetY", "dispelIconSize",
            "dispelColorMagic", "dispelColorCurse", "dispelColorDisease",
            "dispelColorPoison", "dispelColorBleed",
            "dispelIconBorderSize", "dispelOverlayPosition",
            "dispelClockBorder", "dispelClockExtraBorder",
            "dispellableDebuffLocation", "dispellableDebuffGrowDirection",
            "dispellableDebuffOffsetX", "dispellableDebuffOffsetY", "dispellableDebuffSize",
        },
        topNameBar = {
            "topNameBarEnabled", "topNameBarHeight",
            "topNameBarBgColor", "topNameBarBgOpacity",
            "topNameBarTextSize", "topNameBarTextColorMode", "topNameBarTextColor",
            "topNameBarTextOffsetX", "topNameBarTextOffsetY", "topNameBarTextAlign",
        },
        rangeTooltip = {
            "oorAlpha", "showTooltip", "tooltipMode", "frameStrata",
        },
    }
    for section, keys in pairs(map) do
        for _, k in ipairs(keys) do
            ns._PARTY_KEY_SECTION[k] = section
        end
    end
end

ns._IsPartySectionCustom = function(section)
    if not db or not db.profile then return false end
    local ss = db.profile.partySyncSections
    if not ss then return false end
    return ss[section] == false
end

-- Party inherits raid strata unless its Extras section is unsynced.
function ns._ResolveFrameStrata(isParty)
    local strata
    if isParty and ns._IsPartySectionCustom("rangeTooltip") then
        strata = db.profile.party_frameStrata
    end
    strata = strata or db.profile.frameStrata or "LOW"
    if strata ~= "BACKGROUND" and strata ~= "LOW" and strata ~= "MEDIUM"
        and strata ~= "HIGH" and strata ~= "DIALOG" then
        strata = "LOW"
    end
    return strata
end

function ns.ApplyFrameStrata()
    if not db or not db.profile then return false end
    if InCombatLockdown() then
        ns._frameStrataDirty = true
        return false
    end

    ns._frameStrataDirty = nil
    local raidStrata = ns._ResolveFrameStrata(false)
    local partyStrata = ns._ResolveFrameStrata(true)
    local changed = false

    if containerFrame and containerFrame:GetFrameStrata() ~= raidStrata then
        containerFrame:SetFrameStrata(raidStrata)
        changed = true
    end
    if ns._partyContainerFrame and ns._partyContainerFrame:GetFrameStrata() ~= partyStrata then
        ns._partyContainerFrame:SetFrameStrata(partyStrata)
        changed = true
    end
    if changed and ns._RefreshPreviewMouseBlockStrata then
        ns._RefreshPreviewMouseBlockStrata()
    end

    return changed
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
    -- Enable/profile-swap chokepoint: recompute the proxy fast modes against
    -- the (possibly new) profile table and section state.
    if ns._RefreshProxyModes then ns._RefreshProxyModes() end
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
-- Extra Frames duplicates: scale ratio from the Extra Width/Height offsets, relative to
-- the size the real raid frames currently render at. ALWAYS on (not gated by Auto
-- Resize): a custom-sized duplicate scales its texts, indicators, auras and BM buffs to
-- match. Composes with the raid tier scales -- the extra proxy chains through
-- ns._scaledProfile, and the BM scale multiplies ns._bmScale. Both set by XF.Layout.
ns._xfExtraRatio = 1
ns._xfBmScale = 1

local INDICATOR_SCALE_KEYS = {}
for _, k in ipairs({
    -- Font sizes
    "nameSize", "healthTextSize", "healAbsorbTextSize", "statusTextSize",
    "debuffStacksTextSize", "debuffDurTextSize", "defDurTextSize",
    -- Icon sizes
    "roleIconSize", "leaderIconSize", "raidMarkerSize", "combatIndicatorSize", "pingMarkerSize",
    "debuffSize", "defSize", "dispellableDebuffSize",
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
    -- Effective overlay first (preview-scoped ONLY -- ns._partyProxy also serves the
    -- REAL party frames and must never consult it): party_ variant wins over the base
    -- key, mirroring _partyProxy's precedence. Sentinel deletions resolve to nil
    -- WITHOUT falling through to the live view value.
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

-- MATERIALIZED effective settings: every render-path read goes through the four proxies,
-- whose __index closures (section checks, overlay checks, scale multiplies) were
-- per-read Lua dispatch on the hottest path in group combat. Since the transforms'
-- INPUTS only change on discrete edges (settings writes, scale recompute, section sync
-- flips, overlay set/clear, spec/profile swaps), effective values are computed ONCE per
-- edge and rawset INTO the proxy tables: reads between edges are raw C-speed table hits.
-- The original full-chain closures REMAIN as each proxy's permanent metatable -- identity
-- compares still work, and any key the materializer misses falls through to the live
-- chain (a gap costs dispatch, never correctness). While the real-preview overlay is
-- active, _scaledPartyProxy stays EMPTY so every read falls through to the full chain
-- (overlay values are panel-scoped and edit live). Rebuilt by every _RefreshProxyModes
-- caller (scales, tier size, sync sections, overlay, enable/profile swap) plus
-- _BumpAbsorbGen (the SSet/SWrite options funnel).
function ns._RefreshProxyModes()
    local p = db and db.profile
    if not p then return end
    local scaleKeys = INDICATOR_SCALE_KEYS

    -- _partyProxy: base profile + party_ overrides for custom sections.
    local pp = ns._partyProxy
    wipe(pp)
    for k, v in pairs(p) do rawset(pp, k, v) end
    local keySection = ns._PARTY_KEY_SECTION
    if keySection and ns._IsPartySectionCustom then
        for k, section in pairs(keySection) do
            if ns._IsPartySectionCustom(section) then
                local pv = rawget(p, "party_" .. k)
                if pv ~= nil then rawset(pp, k, pv) end
            end
        end
    end

    -- _scaledProfile: raid tier dimensions + indicator scale.
    local sp = ns._scaledProfile
    wipe(sp)
    local iScale = ns._indicatorScale or 1
    for k, v in pairs(p) do
        if iScale ~= 1 and scaleKeys[k] and type(v) == "number" then
            rawset(sp, k, v * iScale)
        else
            rawset(sp, k, v)
        end
    end
    if ns._activeSizeW then rawset(sp, "frameWidth", ns._activeSizeW) end
    if ns._activeSizeH then rawset(sp, "frameHeight", ns._activeSizeH) end

    -- _scaledPartyProxy: party view + party dimensions + party scale.
    -- Overlay active = stay empty (full-chain fallthrough serves the panel).
    local spp = ns._scaledPartyProxy
    wipe(spp)
    if not ns._pvOverlayProxy then
        local pScale = ns._partyIndicatorScale or 1
        for k, v in pairs(pp) do
            if pScale ~= 1 and scaleKeys[k] and type(v) == "number" then
                rawset(spp, k, v * pScale)
            else
                rawset(spp, k, v)
            end
        end
        rawset(spp, "frameWidth", pp.partyFrameWidth or pp.frameWidth)
        rawset(spp, "frameHeight", pp.partyFrameHeight or pp.frameHeight)
    end

    -- _scaledExtraProxy: the scaled view with the extra-frames ratio on top.
    local sep = ns._scaledExtraProxy
    wipe(sep)
    local xRatio = ns._xfExtraRatio or 1
    for k, v in pairs(sp) do
        if xRatio ~= 1 and scaleKeys[k] and type(v) == "number" then
            rawset(sep, k, v * xRatio)
        else
            rawset(sep, k, v)
        end
    end

    -- Any pass through here can mean absorb-relevant settings changed:
    -- invalidate every button's absorb value-memo (and the gen-gated
    -- settings pushes inside UpdateAbsorb).
    ns._absorbGen = (ns._absorbGen or 0) + 1
end
ns._RefreshProxyModes()

-- Options-funnel invalidation: SSet/SWrite call this on EVERY profile write
-- (colors, styles, heights...). It now rebuilds the materialized tables too,
-- so an options write can never leave a stale effective value behind.
ns._BumpAbsorbGen = function()
    ns._RefreshProxyModes()
    -- Settings writes also break the same-frame paint-stamp window: a full pass after
    -- an options write must never dedupe against a paint from before the write.
    ns._paintGen = (ns._paintGen or 0) + 1
    -- Heal-prediction toggles ride this same funnel: re-sync the conditional
    -- UNIT_HEAL_PREDICTION registrations (idempotent, 45 trackers).
    if ns._RFSyncPredRegistration then ns._RFSyncPredRegistration() end
end

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
    if ns._RefreshProxyModes then ns._RefreshProxyModes() end
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
        hdr:SetAttribute("auraContainerTemplate", "CustomAuraContainerTemplate")
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

    -- Pre-create 5 buttons. Container must be visible for SecureGroupHeaderTemplate to
    -- process children (IsVisible checks parent chain). Show temporarily, then hide.
    ns._partyContainerFrame:Show()
    hdr:SetAttribute("startingIndex", -4)
    hdr:Show()
    hdr:SetAttribute("startingIndex", 1)
    hdr:Hide()
    ns._partyContainerFrame:Hide()

    -- Window-phase secure styling (raid sizes initially; ReloadPartyFrames
    -- applies party-specific sizing); insecure bodies run in the deferred pass.
    for i = 1, 5 do
        local btn = hdr[i]
        if btn then
            ns._StyleButtonSecure(btn)
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
    ns._StyleButtonSecure(selfBtn)
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
            UpdateReadyCheck(btn, u)
        end
    end
end

-- Position the self button + party header at their slot offsets, sized from the CURRENT
-- frame dimensions. Shared by the full layout pass and the width/height slider hot path
-- (_ResizePartyButtons): the slot offsets and the header's own size both derive from
-- the frame size, so a live resize must re-apply them or the self button drifts from
-- the header stack and the header's centered child anchors keep growing around the
-- stale width. Returns useSelf for the caller's showPlayer attribute logic.
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

    -- Centered growth shifts the whole stack (self button + header) so the
    -- shown frames sit centered in the always-5-slot container: (5 - shown)/2
    -- slots along the growth axis. Solo is the shown=1 case of the same math,
    -- and the Center When Solo cog forces it while solo regardless of the growth mode.
    local centerShift = 0
    local centered = (s.partyFlipGrowth == "centered")
    if not IsInGroup() then
        if centered or s.partyCenterWhenSolo then centerShift = 2 end
    elseif centered then
        local shown = GetNumGroupMembers() or 0
        if shown > 5 then shown = 5 end
        if hideSelf then shown = shown - 1 end
        if shown < 1 then shown = 1 end
        centerShift = (5 - shown) / 2
    end
    local cShiftX = PixelSnap(slotStepX * centerShift)
    local cShiftY = PixelSnap(slotStepY * centerShift)

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
            sb:SetPoint(basePoint, ns._partyContainerFrame, basePoint, PixelSnap(slotStepX * selfSlot) + cShiftX, PixelSnap(slotStepY * selfSlot) + cShiftY)
            if not InCombatLockdown() then sb:Show() end
        end
        ns._partyHeader:ClearAllPoints()
        ns._partyHeader:SetPoint(basePoint, ns._partyContainerFrame, basePoint, PixelSnap(slotStepX * hdrSlot) + cShiftX, PixelSnap(slotStepY * hdrSlot) + cShiftY)
    else
        if sb and not InCombatLockdown() then sb:Hide() end
        ns._partyHeader:ClearAllPoints()
        ns._partyHeader:SetPoint(basePoint, ns._partyContainerFrame, basePoint, cShiftX, cShiftY)
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
    -- Explicit true only: "centered" keeps the default direction.
    local unitGrowth = s.partyHorizontal and (s.partyFlipGrowth == true and "LEFT" or "RIGHT")
        or (s.partyFlipGrowth == true and "UP" or "DOWN")

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

    -- The friendly boss group attaches to this container (and to the growth axis derived above)
    -- while not in a raid, so every layout pass -- Horizontal Frames, Flip Growth, party size,
    -- cell spacing -- has to move it too. OOC only (this function bails in combat). In a raid the
    -- boss group hangs off the raid headers instead, so skip the re-anchor scan there.
    if not IsInRaid() and ns.FB_ReAnchor then ns.FB_ReAnchor() end
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

        wipe(ns._partyUnitToButton)
    end

    -- Attach-point edges the layout pass above cannot cover: the boss group's own roster pass can
    -- run before the party frames are up, and the hidden branch never lays out at all (the group
    -- then falls back to its free position). EDGE only -- this recompute runs on every roster event.
    if ns._fbPartyAttachState ~= visible then
        ns._fbPartyAttachState = visible
        if ns.FB_ReAnchor then ns.FB_ReAnchor() end
    end
end

-- Reload party frames: apply party-specific sizing then shared rendering.
-- Uses ns._partyProxy for all reads so party overrides take effect.
-- Anchor closures (captured db.profile at StyleButton time) need a temp-swap:
-- we write party_ values onto db.profile, call the closures, then restore.
ns.ReloadPartyFrames = function(skipButtons)
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
    -- section is custom (unsynced). `swapped` records WHICH keys were swapped:
    -- a key whose raid value is nil (no default, never set on raid) stores
    -- nothing in `saved`, so restoring from `saved` alone would skip it and
    -- leave the party value on the shared raid key permanently.
    local saved, swapped = {}, {}
    for key, section in pairs(ns._PARTY_KEY_SECTION) do
        if ns._IsPartySectionCustom(section) then
            local pv = rawget(raw, "party_" .. key)
            if pv ~= nil then
                swapped[#swapped + 1] = key
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

    for _, btn in ipairs(skipButtons and ns._emptyList or ns._partyAllButtons) do
        local d = GetFFD(btn)
        if not d.styled then
            -- _isParty BEFORE StyleButton: the container setup inside it
            -- resolves the style key and settings proxy from this flag, and
            -- the dispel slots BIND that key permanently. Styling first
            -- registered party dispel slots under the RAID key -- party
            -- dispel mode/icons/colors never applied (8.8.3 field reports).
            d._isParty = true
            ns._StyleButtonSecure(btn)
            StyleButton(btn)
        end

        -- Window/initialConfigFunction own sizes in combat (see raid loop).
        if not InCombatLockdown() then
            btn:SetSize(bw, bh)
        end

        -- Health bar height/anchor + Top Name Bar (reads party-resolved `raw`)
        LayoutTopNameBar(raw, bh, powerH, d.health, d.topNameBar, d.topNameBarBg, d.topNameBarText)
        if d.health then
            d.health:SetStatusBarTexture(texPath)
            d.health:GetStatusBarTexture():SetHorizTile(false)
            if d.ReanchorAbsorbToFill then d.ReanchorAbsorbToFill() end
        end

        -- Background: through its stamped owner (dark-mode aware), AFTER the
        -- fill texture swap (see the raid loop).
        if d.bg then
            d._bgSt, d._bgA = nil, nil
            local u = btn:GetAttribute("unit")
            if u and UnitExists(u) then ns._ApplyHealthBg(d, d.health, raw, u) end
        end

        -- Power bar (always hide here; UpdateButton handles per-role show). This is a
        -- second writer of health height alongside UpdateButton's own cached transition
        -- (LayoutTopNameBar above sized health assuming power reserved), so drop the
        -- cache or UpdateAllButtons below sees applied == computed and never corrects it.
        d._appliedHidePower = nil
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

        -- Ping marker
        if d.pingFrame then ns._RFAnchorPing(d) end

        -- Border
        if d.UpdateBorder then d.UpdateBorder() end
    end

    -- Restore db.profile to raid values (via `swapped`, so a nil raid value
    -- is written back as nil rather than skipped)
    for _, key in ipairs(swapped) do
        raw[key] = saved[key]
    end

    -- Re-layout header
    ns._LayoutPartyFrames()
    ns._RebuildPartyUnitMap()
    -- Re-sync UNIT_POWER_UPDATE registration: a Power Bar section sync/unsync
    -- (or a party-side role-flag edit) changes the party's effective power
    -- gating, same reasoning as UpdateCombatEventRegistration above. Must run
    -- after the temp-swap restore so raid reads see raid values.
    if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
    ns._UpdateAllPartyButtons()

    -- Aura containers read the party class through its scaled proxy; the
    -- fingerprint guards make this near-free when nothing party-side changed.
    if ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
end

local function RegisterWithUnlockMode()
    if not (EllesmereUI and EllesmereUI.RegisterUnlockElements) then return end
    if not containerFrame then return end

    -- Snap saved positions to the physical pixel grid using each container's own
    -- effective scale, via the REAL PP (EllesmereUI.PP) -- the file-local PP is
    -- PanelPP, which has no .Snap (`PP.Snap or floor` would fall through to plain
    -- integer rounding, not physical pixels). Matches the SnapForES pattern every
    -- other unlock element uses (and RF's own PixelSnap), keeping the container crisp.
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
            -- RF positions its own container via _ApplyTierOffset (base 20-man top-left
            -- + per-tier offset, tier-footprint-INDEPENDENT), re-run on init/PEW/roster+
            -- tier changes/combat end. The centralized ApplySavedPositions init loop
            -- re-anchors at unlockPos.point using the CURRENT (per-tier) container size,
            -- which diverges from that scheme for every non-20 size and clobbers the
            -- correct position ~0.6s after login. noInitHook keeps that loop off the
            -- container so _ApplyTierOffset stays sole authority (mover/save/anchors unaffected).
            noInitHook = true,

            getFrame = function() return containerFrame end,
            getSize  = function()
                return containerFrame:GetWidth(), containerFrame:GetHeight()
            end,

            savePos = function(_, point, relPoint, x, y, srcPoint, srcRelPoint)
                -- srcPoint/srcRelPoint: the PRE-conversion anchor the unlock framework
                -- received. Anything other than CENTER/CENTER means the CENTER coords were
                -- measured from the container's LIVE (ACTIVE-tier) bounds and must be
                -- rebased to the BASE footprint's equivalent center (the convention every
                -- apply reads), or a mover drag during a non-base tier lands off by a
                -- constant offset on the next _ApplyTierOffset pass. CENTER/CENTER or
                -- absent (revert/nudge/typed-edit) means already stored-convention; rebasing again would corrupt it.
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
        EllesmereUI.MakeUnlockElement({
            key   = "RF_HealerMana",
            label = "Healer Mana Display",
            group = "Raid Frames",
            order = 502,
            noResize = true,
            -- Disabled feature = no mover. Gates on the SETTING (mode none),
            -- not on the group-type activity gate: an enabled display should
            -- stay positionable while solo. The options mode setter
            -- re-registers via ns._RFRegisterUnlock so an open unlock session
            -- gains or loses the mover live in both directions.
            isHidden = function()
                local hm = ns._HMSet and ns._HMSet()
                return not hm or (hm.mode or "none") == "none"
            end,
            getFrame = function()
                return ns._hmContainer or (ns._HMEnsureContainer and ns._HMEnsureContainer())
            end,
            getSize = function()
                local c = ns._hmContainer
                if c then return c:GetWidth(), c:GetHeight() end
                return 50, 25
            end,
            savePos = function(_, point, relPoint, x, y)
                local hm = ns._HMSet()
                hm.unlockPos = { point = point, relPoint = relPoint,
                    x = snap(ns._hmContainer, x), y = snap(ns._hmContainer, y) }
            end,
            loadPos = function()
                return ns._HMSet().unlockPos
            end,
            clearPos = function()
                ns._HMSet().unlockPos = nil
            end,
            applyPos = function()
                local c = ns._hmContainer
                local pos = ns._HMSet().unlockPos
                if c and pos and pos.point then
                    c:ClearAllPoints()
                    c:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                end
            end,
        }),
    })
end
-- Options-side re-registration seam (the function above is a file-scope local
-- the options file cannot reach): setting changes that flip an element's
-- isHidden verdict re-register so an open unlock session updates live.
ns._RFRegisterUnlock = RegisterWithUnlockMode

-------------------------------------------------------------------------------
--  Healer Mana Text Display (Extras): one text row per group healer, riding
--  the EXISTING per-unit trackers. UpdatePowerEventRegistration keeps
--  UNIT_POWER_UPDATE registered for healers while enabled (same loop, same
--  role reads), the shared OnEvent feeds the rows, and the healer set
--  rebuilds on the same roster/roles cadence. Zero cost while disabled:
--  no rows map (the OnEvent tail is one nil test), no extra registrations,
--  container never built.
-------------------------------------------------------------------------------
do
    local container
    local rows = {}   -- i -> { nameFS, valFS, unit }

    local function HMSet()
        local prof = db.profile
        local hm = prof.healerMana
        if not hm then
            hm = { mode = "none" }
            prof.healerMana = hm
        end
        return hm
    end
    ns._HMSet = HMSet

    -- The display's mode gates on the CURRENT group type; solo counts as
    -- neither (the preview eyeball still works ungrouped).
    function ns._HMActive()
        local mode = HMSet().mode or "none"
        if mode == "none" then return false end
        if IsInRaid() then return mode == "raid" or mode == "both" end
        if IsInGroup() then return mode == "party" or mode == "both" end
        return false
    end

    local function EnsureContainer()
        if container then return container end
        container = CreateFrame("Frame", "ERF_HealerMana", UIParent)
        container:SetSize(50, 25)
        container:Hide()
        ns._hmContainer = container
        local pos = HMSet().unlockPos
        if pos and pos.point then
            container:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
        else
            container:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
        end
        return container
    end
    ns._HMEnsureContainer = EnsureContainer

    -- Value repaint: the engine percent object straight into the display
    -- sink -- secret-safe, no Lua math (same source as the power bars).
    function ns._HMUpdateValue(unit)
        local r = ns._hmUnitRows and ns._hmUnitRows[unit]
        if not r then return end
        r.valFS:SetFormattedText("%d", UnitPowerPercent(unit, 0, true, CurveConstants.ScaleTo100))
    end

    -- Full rebuild: healer set, names, colors, layout. Runs on the roster/
    -- roles cadence (UpdatePowerEventRegistration tail) + settings changes.
    function ns.HM_Rebuild()
        local hm = HMSet()
        local preview = ns._hmPreview
        if not ns._HMActive() and not preview then
            if container then container:Hide() end
            ns._hmUnitRows = nil
            return
        end
        EnsureContainer()
        local size     = hm.textSize or 12
        local spacing  = hm.spacing or 2
        local alignR   = hm.align == "RIGHT"
        local alignC   = hm.align == "CENTER"
        local growUp   = hm.growth == "UP"
        local inRaid   = IsInRaid()
        local showNames = (hm.showNames ~= false) and (inRaid or preview)
        local classNames = hm.classNames ~= false
        local powerMode  = hm.colorMode == "power"
        local cc = hm.color
        local cr, cg, cb = (cc and cc.r) or 1, (cc and cc.g) or 1, (cc and cc.b) or 1
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        local outline = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("raidFrames")) or "OUTLINE"
        local rowH = size + spacing
        local map = {}
        local count, widest = 0, 40

        local function addRow(unit, fakeName, fakeClass, fakeVal)
            count = count + 1
            local r = rows[count]
            if not r then
                r = { nameFS = container:CreateFontString(nil, "OVERLAY"),
                      valFS  = container:CreateFontString(nil, "OVERLAY") }
                rows[count] = r
            end
            r.unit = unit
            local nameFS, valFS = r.nameFS, r.valFS
            nameFS:SetFont(fontPath, size, outline)
            valFS:SetFont(fontPath, size, outline)
            -- Value color: power color per unit, or the custom color.
            if powerMode then
                local pr, pg, pb
                if unit then pr, pg, pb = GetPowerColor(unit) end
                valFS:SetTextColor(pr or 0.3, pg or 0.5, pb or 0.85, 1)
            else
                valFS:SetTextColor(cr, cg, cb, 1)
            end
            -- Name first (colors + text), so center alignment can measure it.
            local nameW = 0
            if showNames then
                local nr, ng, nb = cr, cg, cb
                if classNames then
                    local token = fakeClass
                    if not token and unit then
                        token = select(2, UnitClass(unit))
                        if issecretvalue and issecretvalue(token) then token = nil end
                    end
                    local col = token and ((EllesmereUI.GetClassColor and EllesmereUI.GetClassColor(token))
                        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]))
                    if col then nr, ng, nb = col.r, col.g, col.b end
                elseif powerMode then
                    nr, ng, nb = 1, 1, 1
                end
                nameFS:SetTextColor(nr, ng, nb, 1)
                if fakeName then
                    nameFS:SetText(fakeName)
                else
                    -- Display sink: a secret name renders raw, never inspected.
                    nameFS:SetFormattedText("%s", (unit and UnitName(unit)) or "")
                end
                nameFS:Show()
                local w = nameFS:GetStringWidth()
                if w and not (issecretvalue and issecretvalue(w)) then
                    nameW = w
                else
                    nameW = size * 5  -- secret name: estimated width
                end
            else
                nameFS:SetText("")
                nameFS:Hide()
            end
            -- Fixed value-width estimate: centering on the live value's real
            -- width would shift the row every tick.
            local valEst = size * 2.2
            local rowW = (showNames and (nameW + 4) or 0) + valEst
            if rowW > widest then widest = rowW end
            -- Growth: rows stack down from the top edge, or up from the
            -- bottom edge (anchor family flips with it).
            local yOff = (growUp and 1 or -1) * (count - 1) * rowH
            local pCorner = growUp and "BOTTOMLEFT" or "TOPLEFT"
            local pCornerR = growUp and "BOTTOMRIGHT" or "TOPRIGHT"
            local pEdge = growUp and "BOTTOM" or "TOP"
            nameFS:ClearAllPoints(); valFS:ClearAllPoints()
            if alignC then
                if showNames then
                    nameFS:SetPoint(pCorner, container, pEdge, -rowW / 2, yOff)
                    valFS:SetPoint("LEFT", nameFS, "RIGHT", 4, 0)
                    valFS:SetJustifyH("LEFT")
                else
                    valFS:SetPoint(pEdge, container, pEdge, 0, yOff)
                    valFS:SetJustifyH("CENTER")
                end
            elseif alignR then
                valFS:SetPoint(pCornerR, container, pCornerR, 0, yOff)
                valFS:SetJustifyH("RIGHT")
                if showNames then nameFS:SetPoint("RIGHT", valFS, "LEFT", -4, 0) end
            else
                if showNames then
                    nameFS:SetPoint(pCorner, container, pCorner, 0, yOff)
                    valFS:SetPoint("LEFT", nameFS, "RIGHT", 4, 0)
                else
                    valFS:SetPoint(pCorner, container, pCorner, 0, yOff)
                end
                valFS:SetJustifyH("LEFT")
            end
            if fakeVal then
                valFS:SetFormattedText("%d", fakeVal)
            end
            valFS:Show()
            if unit then map[unit] = r end
        end

        if preview then
            addRow(nil, "Thaldris", "PRIEST", 84)
            addRow(nil, "Kaelyra", "SHAMAN", 67)
            addRow(nil, "Morwenn", "DRUID", 92)
        else
            -- Ordered walk, roster order; the role read is the same cached
            -- resolver the power-bar registration uses.
            if inRaid then
                for i = 1, 40 do
                    local unit = "raid" .. i
                    if UnitExists(unit) and ns._ResolvePowerRole(unit) == "HEALER" then
                        addRow(unit)
                    end
                end
            else
                if ns._ResolvePowerRole("player") == "HEALER" then addRow("player") end
                for i = 1, 4 do
                    local unit = "party" .. i
                    if UnitExists(unit) and ns._ResolvePowerRole(unit) == "HEALER" then
                        addRow(unit)
                    end
                end
            end
        end

        -- Retire surplus rows from a previous, larger set.
        for i = count + 1, #rows do
            rows[i].nameFS:Hide()
            rows[i].valFS:Hide()
            rows[i].unit = nil
        end

        ns._hmUnitRows = (not preview and count > 0) and map or nil
        if count > 0 then
            -- Content-sized, with unlock-mover minimums (50x25).
            container:SetSize(math.max(widest, 50), math.max(count * rowH - spacing, 25))
            container:Show()
            -- Seed live values (the event path keeps them current after).
            if not preview then
                for unit in pairs(map) do ns._HMUpdateValue(unit) end
            end
        else
            container:Hide()
        end
    end

    -- Options preview (eyeball): fake rows at the saved position.
    function ns.HM_SetPreview(on)
        ns._hmPreview = on and true or nil
        ns.HM_Rebuild()
    end
end

-------------------------------------------------------------------------------
--  Options preview (fake raid members when options panel is open)
--  Shows 20 buttons with randomized class colors and names so the user
--  can see their settings applied without needing a real group.
-------------------------------------------------------------------------------
local previewActive = false
ns._PV_CLASS_TOKENS = EllesmereUI.CLASS_TOKEN_ORDER
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
-- EUI LEGENDS event roster (PERMANENT): the event winners + team members who
-- earned a spot on the raid preview, with class-balancing filler names.
-- Preview slot 1 is always the player; entries 1-19 fill slots 2-20. Name,
-- class and role travel together through the role sort (ns._pvNames).
ns._PV_ROSTER = {
    { name = "Xeno",          class = "MONK",        role = "TANK" },
    { name = "Grimjaw",       class = "WARRIOR",     role = "TANK" },
    { name = "Stickymittens", class = "PALADIN",     role = "HEALER", hpal = true },
    { name = "Toxik",         class = "MONK",        role = "HEALER" },
    { name = "Delasteve",     class = "PALADIN",     role = "HEALER", hpal = true },
    { name = "Burne",         class = "DRUID",       role = "HEALER" },
    { name = "Lily",          class = "PALADIN",     role = "HEALER", hpal = true },
    { name = "Kulia",         class = "PALADIN",     role = "HEALER", hpal = true },
    { name = "Thiaspriest",   class = "PRIEST",      role = "DAMAGER" },
    { name = "Pelleas",       class = "SHAMAN",      role = "DAMAGER" },
    { name = "Khardi",        class = "HUNTER",      role = "DAMAGER" },
    { name = "Morgath",       class = "DEATHKNIGHT", role = "DAMAGER" },
    { name = "Drakmoor",      class = "DEMONHUNTER", role = "DAMAGER" },
    { name = "Embertide",     class = "EVOKER",      role = "DAMAGER" },
    { name = "Elyndra",       class = "MAGE",        role = "DAMAGER" },
    { name = "Fenwick",       class = "ROGUE",       role = "DAMAGER" },
    { name = "Zulkhar",       class = "WARLOCK",     role = "DAMAGER" },
    { name = "Luneth",        class = "DRUID",       role = "DAMAGER" },
    { name = "Stormhelm",     class = "SHAMAN",      role = "DAMAGER" },
}
ns._PV_DISPEL_DB_ICONS = {
    Magic = 135735, Curse = 132291, Disease = 237535, Poison = 132106, [""] = 4547635,
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
--  Real-preview effective-value overlay: while the options panel holds a
--  value-swapped VIEW (Default Editing Mode or an editing-as session) and
--  preview mode is "real", preview reads must resolve the CURRENT SPEC's
--  panel-closed effective values (spec override, else applied conditional,
--  else defaults) -- never the view's swapped live values. The overlay is a
--  read-through proxy: captured RF keys resolve from the override stores,
--  everything else falls through to live db.profile, so options widgets
--  (which read live directly) keep showing the view. Rebuilt event-driven at
--  preview refresh entry points and the module-refresh tail; nil when no view
--  swap is active (byte-identical reads outside editing views). ZERO writes to
--  live/override stores. (ns fields + do-end locals only: 200-local cap.)
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
            if ns._RefreshProxyModes then ns._RefreshProxyModes() end
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
        if ns._RefreshProxyModes then ns._RefreshProxyModes() end
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
            -- Default view: mirror the REAL spec's RESOLVED effective fork. Never the
            -- live pointer (s.active) -- it lags membership and unlock-mode edits made
            -- while the panel is open, and the preview must show the layer that WOULD
            -- apply on exit. Baseline-effective specs return nil here -> live
            -- positioning, byte-identical to before the feature.
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
    if auraType ~= "def" then
        local sz = s2.debuffSize or 18
        icon:SetSize(sz, sz)
        icon:ClearAllPoints()
        local corner, fx, fy = ns.DebuffGridPoint(s2, slot, totalShown)
        icon:SetPoint(corner, ns.RF_AnchorHost(f._health, s2), corner, fx, fy)
        return
    end

    -- Defensives: single-line relative chaining (no wrapping).
    local pos, ox, oy, grow, sz, spc
    pos = s2.defPosition or "center"
    ox = s2.defOffsetX or 0
    oy = s2.defOffsetY or 0
    grow = s2.defGrowDirection or "CENTER"
    sz = s2.defSize or 22
    spc = PixelSnap(s2.defSpacing or 1)
    local spacing = sz + spc
    local centerOff = 0
    if grow == "CENTER" and totalShown > 0 then
        centerOff = -((totalShown - 1) * spacing) / 2
    end
    icon:SetSize(sz, sz)
    icon:ClearAllPoints()
    if slot == 0 then
        local fx = ox + (grow == "CENTER" and centerOff or 0)
        -- All aura icon previews (debuffs, defensives) anchor flush
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
        local pool = f._pvDefs
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
        or f._pvDebuffs
    local icon = pool and pool[slotIndex]
    if not icon then return end

    local tex = PvAuraPickIcon(auraType, frameIndex)
    if not tex then icon:Hide(); return end

    local s2 = PvSettings()
    local dur = 8 + math.random() * 4  -- 8-12 seconds
    local startTime = GetTime()

    icon._tex:SetTexture(tex)
    if auraType == "db" then
        local _z = s2.debuffIconZoom or 0.08
        icon._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)
    elseif auraType == "def" then
        local _z = s2.defIconZoom or 0.08
        icon._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)
    end
    if icon._cooldown then
        local showSwipe, showDurText, dtColor, dtSize, dtOX, dtOY
        if auraType == "db" then
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
    if auraType == "def" then
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
    -- (defensives and random debuffs in slot 2+) loop on the SAME frame with a fresh
    -- duration instead of being removed -- otherwise the per-group top-up below
    -- re-picks a new random player every cycle, so icons appear to "jump" between
    -- players. Full Preview (test mode) keeps rotating. The raid-wide pulse debuff (db
    -- slot 1) is never looped here; it hits every frame at once on its own pulse cycle.
    local loopSame = not ns._testMode
    for key, info in pairs(ns._pvActiveAuras) do
        if key ~= "_stackKey" and key ~= "raidwide:db" and info.expTime and info.expTime <= now then
            local isRandom = info.auraType == "def"
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
    if PvActive() and (ns._defensivesPreviewVisible or ns._debuffsPreviewVisible) then
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
    local healthH = PixelSnap(h - ns.RF_HealthPowerInset(s, powerH))

    local f = CreateFrame("Frame", nil, previewContainer or containerFrame)
    f:SetSize(w, h)
    f:SetFrameStrata("HIGH")
    f:Hide()

    -- Background
    local bgc = s.customBgColor or defaults.customBgColor
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

    -- Dispel type icon. Preview parity with the real frames' dispel icon
    -- band: above the aura band so it covers debuff icons sharing its
    -- corner, below the marker band.
    local dispelIconFrame = CreateFrame("Frame", nil, f)
    dispelIconFrame:SetFrameLevel(f:GetFrameLevel() + ns.LVL_MARKER - 1)
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

    -- Effective role: the player's spec wins over a stale assigned role
    local playerRole = EllesmereUI.UnitEffectiveRole("player")
    if playerRole ~= "TANK" and playerRole ~= "HEALER" then
        playerRole = "DAMAGER"
    end
    previewRoles[1] = playerRole
    local _, pct = UnitClass("player")
    previewClassTokens[1] = pct or "WARRIOR"

    -- EUI LEGENDS: slots 2-20 come from the permanent named roster (event
    -- winners + team) -- fixed name/class/role triples instead of the old
    -- round-robin class pools. ns._pvNames rides along through the sort.
    --
    -- The Holy Paladin problem (user design): of the four hpal Legends, TWO
    -- stay Holy Paladins and TWO re-roll to a random non-paladin DPS class
    -- (names kept). Rolled once per preview session -- the pick lives on
    -- previewRoles so it resets exactly with the other random picks.
    if not previewRoles._hpalPick then
        local hpals = {}
        for ri = 1, #ns._PV_ROSTER do
            if ns._PV_ROSTER[ri].hpal then hpals[#hpals + 1] = ri end
        end
        for i = #hpals, 2, -1 do
            local j = math.random(i)
            hpals[i], hpals[j] = hpals[j], hpals[i]
        end
        local pick = {}
        for k = 3, #hpals do
            local pool = {}
            for _, c in ipairs(ns._PV_DPS_CLASSES) do
                if c ~= "PALADIN" then pool[#pool + 1] = c end
            end
            pick[hpals[k]] = pool[math.random(#pool)]
        end
        previewRoles._hpalPick = pick
    end
    ns._pvNames = ns._pvNames or {}
    ns._pvNames[1] = nil  -- slot 1 = the player's real name
    for i = 2, 20 do
        local e = ns._PV_ROSTER[i - 1]
        local role, class = e.role, e.class
        local reroll = previewRoles._hpalPick[i - 1]
        if reroll then
            role, class = "DAMAGER", reroll
        end
        previewRoles[i] = role
        previewClassTokens[i] = class
        ns._pvNames[i] = e.name
    end

    -- Sort within each group based on sort settings
    local sortMode = db.profile.sortMode or "INDEX"
    -- Self ordering pins the player first (or last). Separated mode moves the
    -- player within each preview group; merged mode flows the whole grid in
    -- one sort, which the per-group preview approximates with the player at
    -- the first cell. showSelfFirst here means "self ordering active";
    -- selfLast picks the end.
    local selfLast = db.profile.showSelfLast
    local showSelfFirst = db.profile.showSelfFirst or db.profile.showSelfLast
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
                    name = ns._pvNames and ns._pvNames[idx],
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
                if ns._pvNames then ns._pvNames[idx] = group[u].name end
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
    -- The main raid preview is a base "20 Man" mockup: RefreshPreview lays out from the
    -- base frameWidth and CreatePreviewFrame sizes from it too, so per-button sizing here
    -- must also read the base profile. ns._scaledProfile would return the active raid-size
    -- tier override for frameWidth, freezing buttons at override size while layout used
    -- base width (the 20 Man Width slider would re-space without resizing whenever a
    -- custom raid size was active). Party preview passes its own override via
    -- _previewSettingsOverride. The real-preview effective overlay (when active) resolves
    -- captured keys to panel-closed values and is NOT tier-scaled, so this holds.
    local s = ns._previewSettingsOverride or ns._pvOverlayProxy or db.profile
    local classToken = previewClassTokens[index] or ns._PV_CLASS_TOKENS[((index - 1) % #ns._PV_CLASS_TOKENS) + 1]
    local playerSlot = previewRoles._playerSlot or 1
    local name
    if index == playerSlot then
        name = UnitName("player") or "Player"
        if Ambiguate then name = Ambiguate(name, "short") end
    else
        -- Legends roster names are RAID-preview-only (user directive): the
        -- party preview (which sandwiches this fn with _previewSettingsOverride
        -- set and its own class tokens) keeps the generic name pool.
        local legend = not ns._partyPvActive and not ns._previewSettingsOverride
            and ns._pvNames and ns._pvNames[index]
        name = legend or ns._PV_NAMES[((index - 1) % #ns._PV_NAMES) + 1]
    end
    local healthPct = previewHealthValues[index] or (40 + math.random(60))

    local w = PixelSnap(s.frameWidth or 72)
    local h = PixelSnap(s.frameHeight or 46)
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(h - ns.RF_HealthPowerInset(s, powerH))
    local topBarH = (s.topNameBarEnabled and PixelSnap(s.topNameBarHeight or 20)) or 0

    f:SetSize(w, h)

    -- Health bar height/anchor + Top Name Bar (helper re-anchors health top to
    -- -topBarH; the per-unit power block below re-sets only the height)
    LayoutTopNameBar(s, h, powerH, f._health, f._topNameBar, f._topNameBarBg, f._topNameBarText)

    -- Health bar
    if f._health then
        f._health:SetStatusBarTexture(ResolveHealthTexture())
        f._health:GetStatusBarTexture():SetHorizTile(false)
        ns.RF_ApplyHealthOrientation(f._health, s)
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
        elseif mode == "classReactive" then
            if fillTex then fillTex:SetAlpha(1) end
            local r, g, b = ns.ResolveClassReactiveColor(s, classToken, healthPct / 100)
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
        -- BG covers the missing-health portion only (never behind the fill), so
        -- it hangs off the far side of the fill -- its right edge normally, its
        -- top edge on a vertical bar. Mirrors the live UpdateHealthBg.
        local pvVert = ns.RF_IsVerticalFill(s)
        local function AnchorPreviewBg()
            f._bg:ClearAllPoints()
            if pvVert then
                f._bg:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                f._bg:SetPoint("BOTTOMRIGHT", f._health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
            else
                f._bg:SetPoint("TOPLEFT", f._health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
                f._bg:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
            end
        end
        if s.healthColorMode == "dark" then
            AnchorPreviewBg()
            f._bg:SetColorTexture(EllesmereUI.GetDarkModeBg())
        else
            -- Matches the real-frame themed branch + Dark mode. Keeps the preview
            -- a 1:1 replica for reduced-fill-opacity setups.
            AnchorPreviewBg()
            local bgA = (s.bgDarkness or 50) / 100
            local cc = s.bgClassColored and classToken and EllesmereUI.GetClassColor(classToken)
            if cc then
                f._bg:SetColorTexture(cc.r, cc.g, cc.b, bgA)
            else
                local bgc = s.customBgColor or defaults.customBgColor
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
            local tiled = (absStyle == "striped" or absStyle == "stripedReversed" or absStyle == "stripedThick" or absStyle == "stripedThickR" or absStyle == "largeStripes" or absStyle == "largeStripesR" or absStyle == "largeOutlinedStripes" or absStyle == "largeOutlinedStripesR")
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
            local pvOsm = s.overshieldMode
            if pvOsm == nil then pvOsm = (s.showOvershield == false) and "never" or "always" end
            local pvOvershieldOn = pvOsm ~= "never"
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
                -- Vertical fill hides the two edge glows (see the live path).
                if ns.RF_IsVerticalFill(s) and fw then
                    if fw._edgeSpark then fw._edgeSpark:Hide() end
                    if fw._bfSpark then fw._bfSpark:Hide() end
                elseif fw then
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
            -- Vertical fill: same layout with the axis swapped (the fill's right
            -- edge becomes its top edge). Mirrors the live vertical branch.
            local pvAbVert = ns.RF_IsVerticalFill(s)
            local pvAxisBars = { f._absorbBar, fw }
            for i = 1, 2 do
                local b = pvAxisBars[i]
                if b then
                    b:SetOrientation(pvAbVert and "VERTICAL" or "HORIZONTAL")
                    ns.RF_ApplyFillRotation(b)
                end
            end
            if pvAbVert then
                local vfill = f._health:GetStatusBarTexture()
                if absorbMode == "right" or absorbMode == "left" then
                    cc:ClearAllPoints()
                    cc:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    cc:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                    f._absorbBar:ClearAllPoints()
                    if absorbMode == "left" then
                        f._absorbBar:SetReverseFill(false)
                        f._absorbBar:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                        f._absorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                    else
                        f._absorbBar:SetReverseFill(true)
                        f._absorbBar:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                        f._absorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    end
                    if fw then fw:Hide() end
                elseif absorbMode == "overlayReverse" then
                    -- Whole absorb fills DOWN into the fill from its top edge;
                    -- the filled-region clip masks excess (mirrors live).
                    cc:ClearAllPoints()
                    cc:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                    cc:SetPoint("TOPRIGHT", vfill, "TOPRIGHT", 0, 0)
                    f._absorbBar:SetReverseFill(true)
                    f._absorbBar:ClearAllPoints()
                    f._absorbBar:SetPoint("TOPLEFT", vfill, "TOPLEFT", 0, 0)
                    f._absorbBar:SetPoint("TOPRIGHT", vfill, "TOPRIGHT", 0, 0)
                    if fw then fw:Hide() end
                else
                    cc:ClearAllPoints()
                    cc:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                    cc:SetPoint("TOPRIGHT", vfill, "TOPRIGHT", 0, 0)
                    mc:ClearAllPoints()
                    mc:SetPoint("BOTTOMLEFT", vfill, "TOPLEFT", 0, -1)
                    mc:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    f._absorbBar:ClearAllPoints()
                    local pvOsm2 = s.overshieldMode
                    if pvOsm2 == nil then pvOsm2 = (s.showOvershield == false) and "never" or "always" end
                    if pvOsm2 == "fromleft" and s.absorbStyle ~= "blizzardModern" then
                        f._absorbBar:SetReverseFill(false)
                        f._absorbBar:SetPoint("TOPLEFT", vfill, "TOPLEFT", 0, 0)
                        f._absorbBar:SetPoint("TOPRIGHT", vfill, "TOPRIGHT", 0, 0)
                    else
                        f._absorbBar:SetReverseFill(true)
                        f._absorbBar:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                        f._absorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    end
                end
                if fw then
                    fw:ClearAllPoints()
                    fw:SetPoint("BOTTOMLEFT", vfill, "TOPLEFT", 0, 0)
                    fw:SetPoint("BOTTOMRIGHT", vfill, "TOPRIGHT", 0, 0)
                end
            elseif absorbMode == "right" or absorbMode == "left" then
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
            elseif absorbMode == "overlayReverse" then
                -- Whole absorb backfills from the fill's leading edge INTO the
                -- fill; the filled-region clip masks excess (mirrors live).
                local fill = f._health:GetStatusBarTexture()
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                cc:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
                f._absorbBar:SetReverseFill(true)
                f._absorbBar:ClearAllPoints()
                f._absorbBar:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
                f._absorbBar:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
                if fw then fw:Hide() end
            else
                local fill = f._health:GetStatusBarTexture()
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                cc:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
                mc:ClearAllPoints()
                mc:SetPoint("TOPLEFT", fill, "TOPRIGHT", -1, 0)
                mc:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                -- Overlay backfill: overshield "From Left" mirrors the live
                -- anchors (fill-edge + forward fill); else the classic
                -- right-anchored reverse fill.
                f._absorbBar:ClearAllPoints()
                local pvOsm2 = s.overshieldMode
                if pvOsm2 == nil then pvOsm2 = (s.showOvershield == false) and "never" or "always" end
                if pvOsm2 == "fromleft" and s.absorbStyle ~= "blizzardModern" then
                    f._absorbBar:SetReverseFill(false)
                    f._absorbBar:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
                    f._absorbBar:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
                else
                    f._absorbBar:SetReverseFill(true)
                    f._absorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    f._absorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                end
            end
            -- Restore the forward bar's horizontal anchors (the vertical branch
            -- above re-points it, and these are otherwise only set at creation).
            if not pvAbVert and fw then
                local hfill = f._health:GetStatusBarTexture()
                fw:ClearAllPoints()
                fw:SetPoint("TOPLEFT", hfill, "TOPRIGHT", 0, 0)
                fw:SetPoint("BOTTOMLEFT", hfill, "BOTTOMRIGHT", 0, 0)
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
            local tiled = (haStyle == "striped" or haStyle == "stripedReversed" or haStyle == "stripedThick" or haStyle == "stripedThickR" or haStyle == "largeStripes" or haStyle == "largeStripesR" or haStyle == "largeOutlinedStripes" or haStyle == "largeOutlinedStripesR")
            local hpW = w
            local hpH = healthH
            local mask = f._healAbsorbBar._mask
            f._healAbsorbBar:SetStatusBarTexture(haTex)
            f._healAbsorbBar:SetStatusBarColor(hc.r or 0.8, hc.g or 0.15, hc.b or 0.15, haAlpha)
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
            -- Vertical fill: same layout, axis swapped (mirrors the live branch).
            local pvHaVert = ns.RF_IsVerticalFill(s)
            f._healAbsorbBar:SetOrientation(pvHaVert and "VERTICAL" or "HORIZONTAL")
            ns.RF_ApplyFillRotation(f._healAbsorbBar)
            if pvHaVert then
                local vfill = f._health:GetStatusBarTexture()
                if f._healClip then
                    f._healClip:ClearAllPoints()
                    if healMode == "right" or healMode == "left" then
                        f._healClip:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                        f._healClip:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                    else
                        f._healClip:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                        f._healClip:SetPoint("TOPRIGHT", vfill, "TOPRIGHT", 0, 0)
                    end
                end
                f._healAbsorbBar:ClearAllPoints()
                if healMode == "right" then
                    f._healAbsorbBar:SetReverseFill(true)
                    f._healAbsorbBar:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    f._healAbsorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                elseif healMode == "left" then
                    f._healAbsorbBar:SetReverseFill(false)
                    f._healAbsorbBar:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                    f._healAbsorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                else
                    f._healAbsorbBar:SetReverseFill(true)
                    f._healAbsorbBar:SetPoint("TOPLEFT", vfill, "TOPLEFT", 0, 0)
                    f._healAbsorbBar:SetPoint("TOPRIGHT", vfill, "TOPRIGHT", 0, 0)
                end
            else
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
            -- Grows from the HP edge into the missing health: the fill's right
            -- edge normally, its top edge on a vertical bar. Only set at creation
            -- otherwise, so both axes are re-applied here.
            do
                local pvPredVert = ns.RF_IsVerticalFill(s)
                local pFill = f._health and f._health:GetStatusBarTexture()
                f._healPredBar:SetOrientation(pvPredVert and "VERTICAL" or "HORIZONTAL")
                ns.RF_ApplyFillRotation(f._healPredBar)
                if pFill then
                    f._healPredBar:ClearAllPoints()
                    if pvPredVert then
                        f._healPredBar:SetPoint("BOTTOMLEFT", pFill, "TOPLEFT", 0, 0)
                        f._healPredBar:SetPoint("BOTTOMRIGHT", pFill, "TOPRIGHT", 0, 0)
                    else
                        f._healPredBar:SetPoint("TOPLEFT", pFill, "TOPRIGHT", 0, 0)
                        f._healPredBar:SetPoint("BOTTOMLEFT", pFill, "BOTTOMRIGHT", 0, 0)
                    end
                end
            end
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
            do  -- eats the far end of the bar: the right edge, or the top when vertical
                local pvRmhVert = ns.RF_IsVerticalFill(s)
                f._reducedMaxHealthBar:SetOrientation(pvRmhVert and "VERTICAL" or "HORIZONTAL")
                ns.RF_ApplyFillRotation(f._reducedMaxHealthBar)
            end
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
            local pwToken = EllesmereUI.CLASS_POWER_MAP[classToken] or "MANA"
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
                and EllesmereUI.GetPowerColor(EllesmereUI.CLASS_POWER_MAP[classToken] or "MANA")
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
        -- Per-type alpha (plain saved value in the preview path)
        local dcA = dispelDC.a or 1
        -- Dispel border (PP.UpdateBorder handles physical pixel sizing internally)
        local dbs = s.dispelBorderSize or 2
        if f._dispelBdrFrame and PP and dbs > 0 then
            PP.UpdateBorder(f._dispelBdrFrame, dbs, dispelDC.r, dispelDC.g, dispelDC.b, dcA)
            f._dispelBdrFrame:Show()
        elseif f._dispelBdrFrame then
            f._dispelBdrFrame:Hide()
        end
        -- Dispel overlay
        local olMode = s.dispelOverlay or "fill"
        if olMode ~= "none" and f._dispelOLTex and f._health then
            local olAlpha = (s.dispelOverlayOpacity or 100) / 100 * dcA
            local olTex = f._dispelOLTex
            olTex:ClearAllPoints()
            -- Reset any prior vertex tint so fill/full render their explicit color cleanly.
            olTex:SetVertexColor(1, 1, 1, 1)
            if olMode == "fill" then
                local fillTex = f._health:GetStatusBarTexture()
                if fillTex then
                    olTex:SetAllPoints(fillTex)
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
                f._readyCheck:SetAtlas("UI-LFG-ReadyMark-Raid")
            elseif rcStatus == "notready" then
                f._readyCheck:SetAtlas("UI-LFG-DeclineMark-Raid")
            elseif rcStatus == "pending" then
                f._readyCheck:SetAtlas("UI-LFG-PendingMark-Raid")
            elseif rcStatus == "summon_pending" then
                f._readyCheck:SetAtlas("RaidFrame-Icon-SummonPending")
            elseif rcStatus == "summon_accepted" then
                f._readyCheck:SetAtlas("RaidFrame-Icon-SummonAccepted")
            elseif rcStatus == "summon_declined" then
                f._readyCheck:SetAtlas("RaidFrame-Icon-SummonDeclined")
            elseif rcStatus == "rez" then
                f._readyCheck:SetAtlas("RaidFrame-Icon-Rez")
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
        f._nameText:SetText(ns.CapName(name, s))
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
        elseif mode == "missing" then
            local fakeHP = (100 - healthPct) * 12000
            f._healthText:SetText(C_StringUtil.TruncateWhenZero(fakeHP))
            if f._healthText:GetText() then
                if AbbreviateNumbers then
                    f._healthText:SetText(AbbreviateNumbers(fakeHP))
                end
            end
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
        if stPos == "none" then
            -- Status text display is turned off
            f._statusText:Hide()
        elseif isRezCorpse then
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
            -- No status to show
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
                -- Mirror the live carrier's "Show Behind Border" level (see AnchorRoleIcon).
                local rc = f._roleIcon:GetParent()
                if rc then
                    rc:SetFrameLevel(f:GetFrameLevel()
                        + (s.roleIconBehindBorder and (ns.LVL_RAISE - 1) or (ns.LVL_AURA - 1)))
                end
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
        -- Re-anchor from the saved position on EVERY refresh (mirrors the real
        -- container and the size preview; preserving a stale TOPLEFT here left the
        -- real-mode preview stranded after a growth change until the panel reopened).
        -- Anchored at the base footprint's top-left so size changes grow down/right
        -- exactly like the real container's _ApplyTierOffset scheme.
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
end

-- Mouse-blocking overlays + alpha-based real-frame hide for the options preview.
-- Wrapped in a do-block, exposed via ns, so these add NO persistent main-chunk
-- locals (200-local cap); rfMouseBlock/partyMouseBlock survive as closure upvalues.
--
-- The overlays are OUR OWN non-secure frames, so EnableMouse is taint-free and
-- Hide() is combat-legal (no secure children) -- torn down instantly at combat
-- start, so they can never trap a healer's clicks during a pull. They track the
-- real containers directly (alpha-0 but correctly sized/positioned), covering
-- the now-invisible real unit buttons in both preview and size preview.
--
-- Real containers hide via ALPHA, not reparenting: they stay parented to
-- UIParent at their saved position, so SetAlpha(1) restore is always legal and
-- can never be deferred by combat (reparenting secure-header containers back
-- is combat-blocked -- the old cause of "no party frames for the whole first
-- pull"). Preview frames reparent to previewContainer/overlayContainer/partyOC/
-- UIParent before display, so container alpha 0 never hides the preview itself.
do
    local rfMouseBlock, partyMouseBlock
    local function setBlock(on)
        if on then
            if containerFrame then
                if not rfMouseBlock then
                    rfMouseBlock = CreateFrame("Frame", nil, UIParent)
                    rfMouseBlock:EnableMouse(true)
                end
                rfMouseBlock:SetAllPoints(containerFrame)
                rfMouseBlock:SetFrameStrata(containerFrame:GetFrameStrata())
                rfMouseBlock:SetFrameLevel(containerFrame:GetFrameLevel() + 50)
                rfMouseBlock:Show()
            end
            if ns._partyContainerFrame then
                if not partyMouseBlock then
                    partyMouseBlock = CreateFrame("Frame", nil, UIParent)
                    partyMouseBlock:EnableMouse(true)
                end
                partyMouseBlock:SetAllPoints(ns._partyContainerFrame)
                partyMouseBlock:SetFrameStrata(ns._partyContainerFrame:GetFrameStrata())
                partyMouseBlock:SetFrameLevel(ns._partyContainerFrame:GetFrameLevel() + 50)
                partyMouseBlock:Show()
            end
        else
            if rfMouseBlock then rfMouseBlock:Hide() end
            if partyMouseBlock then partyMouseBlock:Hide() end
        end
    end
    ns._SetPreviewMouseBlock = setBlock
    ns._RefreshPreviewMouseBlockStrata = function()
        if rfMouseBlock and rfMouseBlock:IsShown() and containerFrame then
            rfMouseBlock:SetFrameStrata(containerFrame:GetFrameStrata())
            rfMouseBlock:SetFrameLevel(containerFrame:GetFrameLevel() + 50)
        end
        if partyMouseBlock and partyMouseBlock:IsShown() and ns._partyContainerFrame then
            partyMouseBlock:SetFrameStrata(ns._partyContainerFrame:GetFrameStrata())
            partyMouseBlock:SetFrameLevel(ns._partyContainerFrame:GetFrameLevel() + 50)
        end
    end
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
    -- Never engage the preview unless the options window is actually open (or test mode
    -- is active). A deferred C_Timer ShowPreview firing after the panel closed (combat
    -- auto-close, rapid close) would reparent the real containers under the hidden
    -- preview parent with nothing left to restore them -- the root cause of "frames
    -- vanish after closing options". Reparenting secure-header containers is also
    -- blocked/taint-prone in combat, so bail there too.
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
    previewRoles._hpalPick = nil    -- re-roll the hpal Legends next open
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
ns.ResetPreviewRandomization = function()
    previewRoles._randomized = nil
    previewRoles._hpalPick = nil
end
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
--  Shows the correct number of frames for the tier (10/15/25/30/40).
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
    local unitGrowth, groupGrowth = ns._RFEffectiveGrowth(
        ov.unitGrowth or s.unitGrowth or "DOWN", ov.groupGrowth or s.groupGrowth or "RIGHT", s.mergeGroups)
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

    -- Total bounding box: the 4-group mover footprint via the SAME ns._RFFootprint the
    -- live container sizing and the corner origin use (one formula, so preview and live
    -- can never drift). MOVER_GROUPS stays 4 for the group normalization below -- it
    -- must keep matching the real LayoutGroups container, which also normalizes over 4.
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
            -- Pre-paint tint (see StyleButton's health bar note).
            health:SetStatusBarColor(0.12, 0.12, 0.12)
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

    -- Effective role: the player's spec wins over a stale assigned role
    local playerRole = EllesmereUI.UnitEffectiveRole("player")
    if playerRole ~= "TANK" and playerRole ~= "HEALER" then
        playerRole = "DAMAGER"
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
    -- Explicit true only: "centered" keeps the default direction.
    local unitGrowth = s.partyHorizontal and (s.partyFlipGrowth == true and "LEFT" or "RIGHT")
        or (s.partyFlipGrowth == true and "UP" or "DOWN")
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
        -- Editing an override with a custom unlock mode: anchor the preview at the
        -- LAYER's recorded party-container position (a lightweight proxy frame stands
        -- in for the real container, which sits at the REAL spec's position).
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

-- Guaranteed restore invariant. Ensures both real containers are parented to UIParent
-- and their visibility recomputed whenever no preview should be active (e.g. the
-- options panel just closed). Heals the "frames stuck hidden under the preview parent"
-- case even when the preview flags were left false by a skip-restore tab swap or a
-- post-close deferred ShowPreview. Defers to PLAYER_REGEN_ENABLED in combat
-- (reparenting secure-header containers is a protected action).
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
-- Some cooldown/defensive tracker addons anchor icons onto party/raid unit
-- frames, found via a hardcoded addon list or a public provider API. EUI
-- frames are custom, so where a provider API exists we hand it our buttons;
-- the unit lives on the secure "unit" attribute (GetAttribute), so no plain
-- field on the button is needed. Name-scanning trackers (LibGetFrame) need
-- nothing from us: our name patterns are already in that library's default priority list.

-- Currently-visible EUI unit buttons with a unit assigned (party AND raid). Both sets
-- are pre-created once (the startingIndex -4 / Show / 1 trick) and never destroyed or
-- recycled -- the secure header only reassigns "unit" and shows/hides -- so a collected
-- list is exactly as stable for raid as for party; IsVisible + unit is what excludes a
-- button the header has parked.
--
-- Extra frames are skipped (deliberate DUPLICATES of units already on a real raid
-- button -- handing a tracker both leaves it choosing between two frames for one unit).
-- Boss frames never join allButtons for the same reason: not party/raid unit frames.
ns._CollectTrackerFrames = function()
    local out = {}
    local function Collect(list)
        if not list then return end
        for _, btn in ipairs(list) do
            if btn:IsVisible() and btn:GetAttribute("unit")
               and not GetFFD(btn)._isExtra then
                out[#out + 1] = btn
            end
        end
    end
    Collect(ns._partyAllButtons)
    Collect(allButtons)
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
    -- MiniAuras: stable public global MiniAurasApi.v1, created at its file load and so
    -- present by PLAYER_LOGIN whenever MiniAuras is enabled. MiniCCApi is the
    -- pre-rename global (same v1 contract), kept as a fallback for older installs.
    local api = MiniAurasApi or MiniCCApi
    if api and api.v1 and api.v1.RegisterFrameProvider then
        pcall(function()
            api.v1:RegisterFrameProvider({
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

    -- Set party strata before creating its secure header.
    if ns.ApplyFrameStrata then ns.ApplyFrameStrata() end

    -- Create headers; buttons get window-phase secure styling only
    CreateHeaders()

    -- Initial reload minus the restyle loop (sets _activeSizeW/H from group
    -- size + tier overrides, lays out headers) -- the insecure styling bodies
    -- run in the deferred pass below
    ReloadFrames(true)

    -- Create party header (after CC_Init so click-cast registers)
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

    -- Party layout minus the restyle loop (bodies deferred)
    ns.ReloadPartyFrames(true)

    -- Friendly Boss Frames: initial activation (raid-only boss1-5 frames)
    if ns.FB_Apply then ns.FB_Apply() end
    -- Extra Frames: initial activation (raid-only member duplicates)
    if ns.XF_Apply then ns.XF_Apply() end

    -- DEFERRED LOGIN PASS, BUDGET-FRAGMENTED. Starts on the first frame
    -- after the loading screen (timers never fire during it). Everything
    -- here is combat-legal: the insecure styling bodies for every
    -- pre-spawned button (~80% of this module's login CPU), then the full
    -- reload passes, whose protected ops self-gate in combat and heal on the
    -- regen dirty-flag path. Order is load-bearing and preserved by C_Timer
    -- FIFO: BM lookup before the bodies (aura shell pools size from the
    -- indicator lists), bodies before the restyle loops.
    --
    -- WHY FRAGMENTED: each C_Timer callback is its own execution and so its
    -- own 12.1 script-watchdog budget -- but a budget is a fixed slice, and
    -- this pass's cost scales with button count x profile size. As ONE tick
    -- it exceeded its own budget on slower machines (field: watchdog kill
    -- inside _RefreshProxyModes at the TAIL of the tick -- the named line is
    -- just where the budget died, not the culprit). Now the styling loop
    -- self-limits with debugprofilestop and re-queues, and each reload pass
    -- runs as its own execution, so no single execution here scales with
    -- data size. Fast machines still finish styling in one tick; slow ones
    -- style progressively over a few frames instead of erroring. Buttons
    -- created between slices (roster spawns) are healed by the restyle-loop
    -- fallbacks and the 0.5s safety pass, same as the existing one-tick gap;
    -- UpdateButton's `not d.styled` guard covers event dispatch in the gap.
    C_Timer.After(0, function()
        -- Invalidate the frame's paint stamps so the deferred repaint can
        -- never be deduped away (mirrors _ERF_RefreshAll). Re-bumped in each
        -- later stage: every stage is a new frame with its own stamps.
        ns._paintGen = (ns._paintGen or 0) + 1
        if ns.BM_RebuildLookup then ns.BM_RebuildLookup(db) end
        local queue = {}
        for _, btn in ipairs(allButtons) do queue[#queue + 1] = btn end
        for _, btn in ipairs(ns._partyAllButtons) do queue[#queue + 1] = btn end
        local idx = 1
        local function drain()
            local deadline = debugprofilestop() + 8
            while idx <= #queue do
                StyleButton(queue[idx])
                idx = idx + 1
                if idx <= #queue and debugprofilestop() > deadline then
                    C_Timer.After(0, drain)
                    return
                end
            end
            -- Styling complete: each remaining pass gets a whole budget.
            C_Timer.After(0, function()
                ns._paintGen = (ns._paintGen or 0) + 1
                ReloadFrames()
            end)
            C_Timer.After(0, function()
                ns._paintGen = (ns._paintGen or 0) + 1
                ns.ReloadPartyFrames()
            end)
            C_Timer.After(0, RegisterWithUnlockMode)
        end
        drain()
    end)

    -- Party container size + saved position. The container is implicitly
    -- protected (the secure party header is parented to it), so under combat
    -- lockdown the write is deferred to the PLAYER_REGEN_ENABLED flush instead
    -- of tripping ADDON_ACTION_BLOCKED: _ERF_RefreshAll is a public entry point
    -- (profiles, spec overrides, third-party installers) and not every caller
    -- is out of combat.
    function ns._ApplyPartyContainerGeometry()
        local c = ns._partyContainerFrame
        if not c or not ns.db then return end
        if InCombatLockdown() then ns._partyGeomDirtyInCombat = true; return end
        local s = ns.db.profile
        local w = s.partyFrameWidth or s.frameWidth or 125
        local h = s.partyFrameHeight or s.frameHeight or 60
        local sp = s.cellSpacing or 2
        c:SetSize(w, h * 5 + sp * 4)
        local pos = s.partyUnlockPos
        -- Skip the saved-pos SetPoint when element-anchored with resolved
        -- geometry: the unlock anchor system owns the position.
        local anchored = EllesmereUI.IsUnlockAnchored
            and EllesmereUI.IsUnlockAnchored("RF_PartyFrames")
            and c:GetLeft()
        if pos and not anchored then
            c:ClearAllPoints()
            c:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
        end
    end

    -- Profile-swap refresh: EllesmereUI.RefreshAllAddons calls this on a profile
    -- change so raid + party frames re-read the (now-swapped) profile live,
    -- instead of staying stale until /reload. Mirrors the reload sequence above.
    _G._ERF_RefreshAll = function()
        if not ns.db then return end
        -- Profile/view swaps break the same-frame paint-stamp window: the
        -- repaint of the new profile must never dedupe against a paint made
        -- under the old one earlier this frame.
        ns._paintGen = (ns._paintGen or 0) + 1
        -- Absorbs sync-state inheritance for swapped/imported profiles saved
        -- before the Absorbs section split (must precede party proxy reads).
        ns._NormalizePartySyncSections()
        -- Rebase old-scheme tier offsets on swapped/imported profiles too
        -- (the marker lives inside raidSizeOverrides, so this self-detects).
        ns._NormalizeTierOffsetAnchors()
        -- Rebuild the buff-manager spell lookup for the new profile's per-spec
        -- indicators (and the Simple Setup whitelist) before frames re-render.
        if ns.BM_RebuildLookup then ns.BM_RebuildLookup(ns.db) end
        -- Apply strata first; reload restores child frame levels.
        if ns.ApplyFrameStrata then ns.ApplyFrameStrata() end
        -- Raid frames: restyle + relayout + reposition from the new profile.
        if ns.ReloadFrames then ns.ReloadFrames() end
        -- Party container size + position (combat-deferred inside), then the party buttons.
        ns._ApplyPartyContainerGeometry()
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
        -- Real-preview effective overlay: RunRefreshers reaches here synchronously from
        -- every view/spec/conditional transition, so the preview's value source is
        -- corrected in the SAME frame -- the shared tickers never render a stale
        -- overlay across a flip. Near-zero cost when the overlay gate is inactive.
        if ns._RebuildPvOverlay then ns._RebuildPvOverlay() end
        -- Solo-visibility recompute: override/profile transitions can flip showWhenSolo
        -- (e.g. a healer solo-frames spec override), and the DB restore alone never
        -- re-derives container visibility or the secure showSolo header attributes, so
        -- frames kept the state of whichever override page was viewed last. Both
        -- recomputes no-op via change guards when nothing moved. OOC-gated: override
        -- refreshers are REGEN-stashed, but direct callers may not be, and secure
        -- attribute writes are combat-blocked; a combat-time skip self-heals on the
        -- existing combat-exit visibility pass.
        if not InCombatLockdown() then
            if ns.UpdateVisibility then ns.UpdateVisibility() end
            if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
        end
    end

    -- Buff Manager LAYER swap refresh (spec-override BM forks): re-derives
    -- the spell lookup, then re-drives the aura containers that render BM.
    -- Deliberately BM-only: never calls ReloadFrames, so profile swaps
    -- (_ERF_RefreshAll above) are not doubled. Combat-safe: BM code only
    -- touches our own pooled child frames, never the secure buttons.
    -- noPage: skip the options-page repaint when the caller IS a page build.
    _G._ERF_BMRefresh = function(noPage)
        if not ns.db then return end
        if ns.BM_RebuildLookup then ns.BM_RebuildLookup(ns.db) end
        local pv = ns._bmPreviewFrame
        if pv and pv._health and ns.BM_ApplyPreviewIndicators then
            ns.BM_ApplyPreviewIndicators(pv, 1, ns.db.profile)
        end
        -- Aura containers own BM rendering on 12.1: re-drive them so a
        -- swapped-in override fork repaints (fingerprint guards make this
        -- near-free when nothing actually changed).
        if ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
        -- Open BM options page: force a rebuild so its widgets re-bind to
        -- the (identity-preserved, content-swapped) profile tables.
        if not noPage and ns._bmRoot and EllesmereUI and EllesmereUI.RefreshPage then
            EllesmereUI:RefreshPage(true)
        end
    end


    -- Expose EUI party frames to external trackers that support a provider
    -- API (e.g. MiniAuras). No-op when none is installed.
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

    -- Heal prediction feeds ONLY the incoming-heal display, never absorbs.
    -- Any view rendering it keeps the event; the default (all off) never
    -- registers it at all. Materialized proxies = plain table reads.
    function ns._RFPredWanted()
        return (ns._scaledProfile.healPrediction
            or ns._scaledPartyProxy.healPrediction
            or ns._scaledExtraProxy.healPrediction) and true or false
    end
    -- Idempotent toggle sync, called from the _BumpAbsorbGen options funnel.
    function ns._RFSyncPredRegistration()
        local want = ns._RFPredWanted()
        for unit, tracker in pairs(unitTrackers) do
            if want then
                tracker:RegisterUnitEvent("UNIT_HEAL_PREDICTION", unit)
            else
                tracker:UnregisterEvent("UNIT_HEAL_PREDICTION")
            end
        end
    end

    -- Per-unit event trackers: one frame per unit.
    -- RegisterUnitEvent only accepts 1-2 units per call, so each unit gets
    -- its own frame. Units that don't exist simply don't fire (zero cost).
    local UNIT_EVENTS_BASE = {
        -- UNIT_AURA deliberately absent (Blizzard parity: their CompactUnitFrame
        -- repaints prediction from health/absorb events only). The one gap --
        -- an aura-granted shield expiring on its TIMER on an unhit, topped
        -- unit (field report: VDH Infernal Strike) fires NO event at all --
        -- is covered by the armed-members belt next to the absorb coalescer.
        -- UNIT_HEAL_PREDICTION absent: it feeds ONLY the incoming-heal
        -- display (never absorbs) and fires on every healer cast at every
        -- target -- registered conditionally in MakeUnitTracker, synced by
        -- ns._RFSyncPredRegistration on options writes.
        "UNIT_HEALTH", "UNIT_MAXHEALTH",
        "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
        "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
        "UNIT_NAME_UPDATE", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
        "PLAYER_FLAGS_CHANGED", "UNIT_CONNECTION", "UNIT_IN_RANGE_UPDATE",
    }
    local function MakeUnitTracker(unit)
        -- Shell-pool adoption: the initial roster build runs from OnEnable
        -- (parent lifecycle context), which would bill every tracker's
        -- event tree to the parent addon for the whole session.
        local f = ns.TakeShell()
        for _, ev in ipairs(UNIT_EVENTS_BASE) do
            f:RegisterUnitEvent(ev, unit)
        end
        if ns._RFPredWanted() then
            f:RegisterUnitEvent("UNIT_HEAL_PREDICTION", unit)
        end
        f:RegisterUnitEvent("UNIT_POWER_UPDATE", unit)
        f:RegisterUnitEvent("UNIT_DISPLAYPOWER", unit)
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
    -- when the user changes power bar role filters. The trackers are shared
    -- by raid AND party frames: player/party1-4 tokens also drive the party
    -- buttons, whose Power Bar section can be unsynced from raid -- those
    -- must consult the party proxy too, or raid-off/party-on would strip
    -- their events and freeze the party power bars mid-combat.
    local function UpdatePowerEventRegistration()
        local rs = db.profile
        local ps = ns._partyProxy
        local function wantsPower(s, role)
            return (role == "HEALER" and s.powerShowForHealer)
                or (role == "TANK" and s.powerShowForTank)
                or (role == "DAMAGER" and s.powerShowForDPS)
                or (role == "NONE" and s.powerShowForDPS)
        end
        -- Healer Mana Display rides these registrations: healers keep their
        -- power events while its mode matches the current group type,
        -- whatever the power bar settings.
        local hmOn = ns._HMActive and ns._HMActive()
        for unit, tracker in pairs(unitTrackers) do
            local wantPower = false
            if UnitExists(unit) then
                local role = ns._ResolvePowerRole(unit)
                wantPower = (IsPowerBarEnabled(rs) and wantsPower(rs, role))
                    or (hmOn and role == "HEALER")
                -- player/party tokens always count as party-displayable; the
                -- routing-map check additionally covers arena, where the party
                -- header binds raid1-5.
                if not wantPower and IsPowerBarEnabled(ps)
                    and (unit == "player" or unit:match("^party%d$")
                        or (ns._partyUnitToButton and ns._partyUnitToButton[unit])) then
                    wantPower = wantsPower(ps, role)
                end
            end
            if wantPower then
                tracker:RegisterUnitEvent("UNIT_POWER_UPDATE", unit)
                tracker:RegisterUnitEvent("UNIT_DISPLAYPOWER", unit)
            else
                tracker:UnregisterEvent("UNIT_POWER_UPDATE")
                tracker:UnregisterEvent("UNIT_DISPLAYPOWER")
            end
        end
        -- Same cadence as the registrations (roster/roles/settings changes).
        if ns.HM_Rebuild then ns.HM_Rebuild() end
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
    local function RegisterMethodInternalNicknames()
        if ns._methodInternalSurfaceNickHooked then return end
        if EasyNicknameAPI and EasyNicknameAPI.RegisterCallback then
            EasyNicknameAPI.RegisterCallback("SurfaceNicknamesChanged", function()
                if ns.RefreshAllNames then ns.RefreshAllNames() end
            end, "EllesmereUIRaidFrames")
            ns._methodInternalSurfaceNickHooked = true
        end
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
    local function RegisterRGALIASNicknames()
        if ns._rgaliasNickHooked then return true end
        local RGA = _G.RG_ALIAS
        if RGA and RGA.RegisterCallback and _G.RG_UnitName then
            -- ns._rgaNick gates the ResolveDisplayName consult. The settings
            -- shape is nil-guarded and only read here and in callbacks, never
            -- per name resolve; a fresh RGA install with no settings table
            -- yet simply reads as module-off.
            local function SyncRGAFlag()
                local s = RG_ALTS_SETTINGS and RG_ALTS_SETTINGS.settings
                ns._rgaNick = (s and s["ellesmereui"]) and true or nil
                if ns.RefreshAllNames then ns.RefreshAllNames() end
            end
            -- pcall: RGA owns its RegisterCallback signature; a mismatch or
            -- future change must not error our OnEnable. If registration
            -- fails, the flag is still seeded once below -- module toggles
            -- then need a /reload to be noticed (degraded, never broken).
            pcall(RGA.RegisterCallback, "DbUpdated", SyncRGAFlag)
            pcall(RGA.RegisterCallback, "ModuleEnabled", function(event, moduleName)
                if moduleName == "ellesmereui" then SyncRGAFlag() end
            end)
            pcall(RGA.RegisterCallback, "ModuleDisabled", function(event, moduleName)
                if moduleName == "ellesmereui" then SyncRGAFlag() end
            end)
            local s = RG_ALTS_SETTINGS and RG_ALTS_SETTINGS.settings
            ns._rgaNick = (s and s["ellesmereui"]) and true or nil
            ns._rgaliasNickHooked = true
            return true
        end
        return false
    end

    local nsrtHooked = RegisterNSRTNicknames()
    local trHooked = RegisterTRNicknames()
    local rgaliasHooked = RegisterRGALIASNicknames()
    if not (nsrtHooked and trHooked and rgaliasHooked) then
        local nickFrame = ns.TakeShell()
        nickFrame:RegisterEvent("PLAYER_LOGIN")
        nickFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        nickFrame:SetScript("OnEvent", function(self, event)
            local a = RegisterNSRTNicknames()
            local b = RegisterTRNicknames()
            local c = RegisterRGALIASNicknames()
            -- Anything not loaded by first PLAYER_ENTERING_WORLD is not coming.
            if (a and b and c) or event == "PLAYER_ENTERING_WORLD" then self:UnregisterAllEvents() end
        end)
    end
    EventUtil.ContinueOnAddOnLoaded("MethodInternal", RegisterMethodInternalNicknames)

    -- Init options module if it loaded before us
    if ns._InitEUIModule then
        C_Timer.After(0, ns._InitEUIModule)
    end
end

-- Slash command registered in EUI_RaidFrames_Options.lua
