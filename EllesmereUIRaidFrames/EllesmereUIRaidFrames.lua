if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIRaidFrames.lua
--  Custom raid frames built on SecureGroupHeaderTemplate.
--  8 per-group headers (separated mode) + 1 combined header (flat mode).
--  Secret-value-safe absorb shields matching UnitFrames visuals.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.NewCombatQueue) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
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

-- Keep subgroup identity separate from its visual slot. Invalid imported
-- orders fall back to the original layout without touching SavedVariables.
function ns._RFValidatedGroupOrder(order)
    if type(order) ~= "table" or #order ~= 8 then return nil end
    for i = 1, 8 do
        local group = order[i]
        if type(group) ~= "number" or group < 1 or group > 8 or group % 1 ~= 0 then
            return nil
        end
        for previous = 1, i - 1 do
            if order[previous] == group then return nil end
        end
    end
    return order
end

-------------------------------------------------------------------------------
--  Frame-level layout (offsets above the button / preview-frame level).
--  All aura VISUALS (debuffs, defensives/externals, private auras, dispel-type
--  icons, Buff Manager icons/squares/bars) share one band ABOVE the
--  threat/dispel/base border so the threat border renders behind them; each
--  aura unit renders children (cooldown/border/text) up to +5 above base.
--  Bottom to top: base border (+8/strips +9) -> hover/target/aggro raise (LVL_RAISE,
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
ns.LVL_RAISE  = 10   -- hover/target/aggro-recolor border (strips +11: above base strips +9;
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
--  release. Sized for per-unit trackers (40 raid + party + boss + extra + pets)
--  plus standing watchers.
-------------------------------------------------------------------------------
do
    local pool = {}
    local n = 120
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

-- "Run once after combat" for one-shot combat-gated deferrals. The shell is taken
-- in the main chunk, so drained work bills RaidFrames. Keys are per purpose.
ns.CombatQueue = EllesmereUI.NewCombatQueue(ns.TakeShell())

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
-- WoW Forever: no number under 10,000 abbreviates (EllesmereUI_NumberFormat.lua).
local AbbreviateNumbers     = (EllesmereUI.IS_FOREVER and EllesmereUI.ForeverAbbreviateNumbers) or AbbreviateNumbers
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
    pixelsShield          = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\pixels-shield.tga",
    pixelsShieldEdge      = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\pixels-shield-edge.tga",
    pixelsShieldFill      = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\pixels-shield-fill.tga",
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
    pixels = {
        _isTexture = true,
        TANK    = ROLE_MEDIA .. "pixels-tank.tga",
        HEALER  = ROLE_MEDIA .. "pixels-healer.tga",
        DAMAGER = ROLE_MEDIA .. "pixels-dps.tga",
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
-- Level Text's default position: attached to the name on WoW Forever, None on
-- retail (the per-client default rule; every fallback below reads it).
ns.RF_LEVEL_DEFAULT = (EllesmereUI.IS_FOREVER == true) and "name" or "none"
local defaults = {
    profile = {
        -- Size & layout
        frameWidth       = 125,
        frameHeight      = 60,
        cellSpacing      = -1,
        groupSpacing     = -1,
        groupGrowth      = "RIGHT",  -- "DOWN", "UP", "RIGHT", "LEFT", "DOWNRIGHT" (grid: ns._RF_GRID_ROWS per column)
        unitGrowth       = "DOWN",   -- any direction; same-axis as groupGrowth = one continuous line
        sortMode         = "ROLE",   -- "INDEX" (by group) or "ROLE" (by assigned role)
        roleOrder        = { "TANK", "HEALER", "DAMAGER" },
        prioritizeClass  = false,    -- sort by class within the main sort (raid)
        classOrder       = nil,      -- nil = all classes alphabetical by name
        showSelfFirst    = true,
        showSelfLast     = false,
        mergeGroups      = false,
        customGroupOrder = false,
        visibleGroups    = { true, true, true, true, true, true, false, false },
        hideEmptyGroups  = true,     -- collapse subgroups with no members (raid only, real frames)
        excludeHiddenGroupsFromSize = true, -- hidden Show Groups don't count toward the raid-size breakpoint
        mythicRaidHideGroups = false, -- Hide Groups 5-8 in Mythic Raid (on top of Show Groups)

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

        -- Pet Frames (party and raid pets, beside the groups). Each tab reads the placement
        -- (position, freePos, freeRect) and extra size here until it sets its own party_/raid_
        -- key (PF.View).
        petFrames = {
            party = false,
            raid  = false,
            position = "right",   -- "left" | "right" | "free" | "owner" (Beside Owner, Party tab)
            freePos  = { x = 100, y = -200 },
            healthColor = { r = 23/255, g = 172/255, b = 49/255 },
            extraWidth  = 0,      -- size offset on top of the party or raid frame size
            extraHeight = 0,
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
        -- Invert health fill: when true the bar is full at low health and empty at high health.
        healthInvertFill = false,

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
        topNameBarBottom        = false,    -- Show on Bottom: the bar takes the frame's bottom edge

        -- Text
        nameSize         = 10,
        nameMaxLength    = 15,  -- max characters shown for unit names (0 = off / no cap)
        nameColorMode    = "custom",  -- "class", "accent", "custom"
        nameCustomColor  = { r = 1, g = 1, b = 1 },
        namePosition     = "topleft", -- "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom"
        nameOffsetX      = 0,
        nameOffsetY      = 0,
        -- Level Text: the unit's level in front of the name, or on its own spot in the name's colour
        -- (Health Text's host). None = nothing built.
        levelTextSize      = 10,
        levelTextPosition  = ns.RF_LEVEL_DEFAULT,  -- "name" ("60 Name"), "nameDiv" ("60 | Name"), "none" or a 9-point spot
        levelTextOffsetX   = 0,
        levelTextOffsetY   = 0,
        healthTextMode   = "none",   -- "none", "percent", "number"
        healthTextColorMode   = "custom",  -- "class", "accent", "custom"
        healthTextCustomColor = { r = 1, g = 1, b = 1 },
        healthTextSize   = 9,
        healthTextPosition = "center",
        healthTextOffsetX  = 0,
        healthTextOffsetY  = 0,
        -- Power Text (Health Text's controls, on the same health bar host): shown only where the power bar shows. None = nothing built.
        powerTextMode   = "none",   -- "none", "percent", "percentNoSign", "number", "numberPercent", "percentNumber"
        powerTextColorMode   = "custom",  -- "custom", "class", "accent", "power"
        powerTextCustomColor = { r = 1, g = 1, b = 1 },
        powerTextSize   = 8,
        powerTextPosition = "bottom",
        powerTextOffsetX  = 0,
        powerTextOffsetY  = 0,
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
        -- Blizzard Glow Line (absorbGlowLine) has NO default on purpose: unset follows the
        -- style (on for Default Blizz Frames only); a default would switch the line off for
        -- every profile already on that style.
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
        roleIconStyle    = "modern",  -- none/modern/modernCircle/styled/classicCircle/classic/blizzDefault/blizzLight/pixels
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
        -- WoW Forever: Missing Buffs (EUI_RaidFrames_ForeverMissingBuffs.lua).
        -- Forever-only defaults, absent on every other client.
        showMissingBuffs     = (EllesmereUI.IS_FOREVER == true) and true or nil,
        missingBuffsSize     = (EllesmereUI.IS_FOREVER == true) and 22 or nil,
        missingBuffsPosition = (EllesmereUI.IS_FOREVER == true) and "top" or nil,
        missingBuffsOffsetX  = (EllesmereUI.IS_FOREVER == true) and 0 or nil,
        missingBuffsOffsetY  = (EllesmereUI.IS_FOREVER == true) and 0 or nil,
        -- Its icons' glow (shared prefix schema; 2 = Action Button Glow).
        missingBuffsGlowType      = (EllesmereUI.IS_FOREVER == true) and 2 or nil,
        missingBuffsGlowColorMode = (EllesmereUI.IS_FOREVER == true) and "default" or nil,
        showReadyCheck   = true,
        showSummonPending = true,
        showIncomingRez  = true,
        readyCheckSize   = 20,
        readyCheckPosition = "center",  -- "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom"
        readyCheckOffsetX  = 0,
        readyCheckOffsetY  = 0,
        threatBorderSize = 2,    -- aggro warning border thickness; 0 = off
        threatCustomBorder = false,  -- Color Custom Borders: the frame border recolored for aggro instead of the inner border
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
        dispelCustomBorder = false,  -- Color Custom Borders: the frame border copied in the dispel type color
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

        -- Buff Manager "Simple Setup" (retired display): kept only as legacy
        -- input for the v2 conversion and spec-override banking; nothing renders it.
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
        partySmallRaid    = false,  -- raid under 10 players: group 1 as party frames, others hidden
        partyShowTargets  = false,  -- opt-in secure target buttons beside party frames
        -- Party target frames (Party tab PARTY TARGETS section): party only, one value under
        -- every style. partyTargetPosition nil = beside stacked frames, below horizontal ones.
        partyTargetIncludeSelf     = false,     -- your own target beside your frame too
        partyTargetHealthColorMode = "class",   -- "class" | "dark" | "classic" | "custom"
        partyTargetCustomFillColor = { r = 37/255, g = 193/255, b = 29/255 },
        partyTargetBgClassColored  = false,
        partyTargetCustomBgColor   = { r = 17/255, g = 17/255, b = 17/255 },
        partyTargetBgDarkness      = 50,
        partyTargetOffsetX         = 0,         -- -100..100
        partyTargetOffsetY         = 0,
        partyTargetWidth           = 70,
        partyTargetHeight          = 33,
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
        -- Party portrait (Party tab PORTRAIT section, EUI_RaidFrames_Portrait.lua):
        -- party only, one value under every style. Off by default.
        partyPortraitStyle       = "none",      -- "none" | "attached" | "detached"
        partyPortraitMode        = "2d",        -- Art Style: "2d" | "3d" | "class"
        partyPortraitClassStyle  = "modern",    -- class art set
        partyPortraitSide        = "left",      -- left|right|top|insideleft|insideright|insidecenter
        partyPortraitSize        = 0,           -- -50..100 (detached / inside)
        partyPortraitX           = 0,           -- -100..100 (detached)
        partyPortraitY           = 0,
        partyPortraitShape       = "portrait",  -- none|portrait|circle|square|csquare|diamond|hexagon|shield
        partyPortraitBorderColor = { r = 0, g = 0, b = 0 },
        partyPortraitBorderClassColor = true,
        partyPortraitBorderOpacity = 100,       -- 0..100
        partyPortraitBorderSize  = 7,           -- 1..7
        partyPortraitArtScale    = 100,         -- 2D Zoom 50..100
        partyPortrait3dZoom      = 100,         -- 3D Zoom 100..500 (above 300: whole character)
        partyPortraitCharScale   = 100,         -- Character Size % 50..200 (Inside, 3D)
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

    -- Callable from UpdateVisibility when "Show When: In a Group" is active.
    -- early (OnEnable, login window): takes PartyFrame itself down so Blizzard's
    -- party frames can never stand in for ours (a group joined in combat), without
    -- latching -- the member frames, which Edit Mode can build later (raid-style),
    -- are handled the first time our party frames show out of combat.
    ns._SuppressBlizzParty = function(early)
        if ns._blizzPartySuppressed then return end
        if not early then ns._blizzPartySuppressed = true end
        if PartyFrame then
            handleFrame(PartyFrame)
            if early then return end
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
local function ApplyFont(fs, size) EllesmereUI.ApplyModuleFont(fs, nil, size, "raidFrames") end

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
    -- The stock raid fills, as our own keys on the game files (the stock
    -- styles' first-visit defaults; no SharedMedia needed): the 12.1 flat
    -- fill (Blizzard Style) and the pre-10.0 gradient "Blizzard Raid Bar"
    -- (Classic WoW UI). The shared-media copy of the latter dedupes against
    -- this entry (same name and path).
    healthBarTextures.blizzardRaidModern = "Interface\\RaidFrame\\RaidFrameHPFill"
    healthBarTextureNames.blizzardRaidModern = "Default Blizz Frames"
    healthBarTextures.blizzardRaid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
    healthBarTextureNames.blizzardRaid = "Blizzard Raid Bar"
    table.insert(healthBarTextureOrder, 2, "blizzardRaid")
    table.insert(healthBarTextureOrder, 2, "blizzardRaidModern")

    -- Append SharedMedia textures after built-ins
    EllesmereUI.AppendSharedMediaTextures(
        healthBarTextureNames,
        healthBarTextureOrder,
        nil,
        healthBarTextures
    )
end

-- s: the settings to read (the profile when nil).
local function ResolveHealthTexture(s)
    local key = (s or db.profile).healthBarTexture or "atrocity"
    return EllesmereUI.ResolveTexturePath(healthBarTextures, key, healthBarTextures["atrocity"] or "Interface\\Buttons\\WHITE8X8")
end

-- Expose for options panel
ns.healthBarTextures     = healthBarTextures
ns.healthBarTextureNames = healthBarTextureNames
ns.healthBarTextureOrder = healthBarTextureOrder

-- Style page choice (Blizzard Style / Classic WoW UI, EUI_RaidFrames_Stock.lua):
-- "eui" | "blizzard" | "classic", read from the profile flags once and
-- latched for the session (every switch reloads). The runtime reads only
-- this, never the flags. On ns (200-local cap).
function ns.RF_Style()
    local v = ns._rfStyle
    if v then return v end
    local p = db and db.profile
    if not p then return "eui" end
    v = (p.useClassicStyle and "classic") or (p.useBlizzardStyle and "blizzard") or "eui"
    ns._rfStyle = v
    return v
end
function ns.RF_Stock() return ns.RF_Style() ~= "eui" end
function ns.RF_Classic() return ns.RF_Style() == "classic" end
-- Party page "Frame Style" under a stock style: the style key while the
-- party wears the stock portrait party frame ("Party Frames"), else false.
-- Latched like RF_Style (the choice reloads); the runtime reads only this.
-- The memo test is ~= nil: false is a real latched value.
function ns.RF_PartyKit()
    local v = ns._rfPartyKit
    if v ~= nil then return v end
    local p = db and db.profile
    if not p then return false end
    local st = ns.RF_Style()
    v = (st ~= "eui" and p.partyFrameStyle == "party") and st or false
    ns._rfPartyKit = v
    return v
end
-- Settings the Party Frames layout replaces (its rows are hidden on the
-- Party page): the party settings view reads them neutral while it is on
-- (with the kit's debuff row: ns.RF_KitViewKeys, EUI_RaidFrames_Stock.lua).
ns.RF_KIT_NEUTRAL = {
    healthVerticalFill = false, healthInvertFill = false, topNameBarEnabled = false,
    powerUniformAnchors = false, extendHealthBehindPower = false,
}
-- The EllesmereUI border's effective size (0 under a stock style, whose edge
-- replaces it).
function ns.RF_EffBorderSize(s)
    if ns.RF_Stock() then return 0 end
    return (s and s.borderSize) or 1
end
-- A custom border the Color Custom Borders options can recolor (Threat Borders
-- and Dispel Border cogs): a Border Style other than Solid with a size, under
-- the EllesmereUI style. Read from the saved keys, like the options gate.
function ns.RF_CustomBorderOn(s)
    local tex = s and s.borderTexture
    if tex == nil or tex == "" or tex == "solid" then return false end
    return ns.RF_EffBorderSize(s) > 0
end

-- Threat highlight (aggro: status 2-3; Threat Borders size 0 = off): the red
-- EllesmereUI border, or under a stock style the stock aggro rim. Color Custom
-- Borders (threatCustomBorder, over a custom border only) recolors the frame's
-- own border instead (ApplyBorderColor, below hover/target): no inner border is
-- drawn and the slider size does not gate it. The border repaints only when the
-- aggro state flips; d is the FFD table, never the Blizzard button.
function ns.RF_PaintThreat(d, s, unit)
    local tf = d.threatFrame
    if not tf then return end
    local bs = s.threatBorderSize or 0
    local rc = s.threatCustomBorder == true and ns.RF_CustomBorderOn(s)
    local status
    if bs > 0 or rc then
        status = UnitThreatSituation(unit)
        -- One group unit token reads plain (documented); a secret status still
        -- reads as no aggro rather than being indexed or compared.
        if issecretvalue(status) then status = nil end
    end
    local on = status and THREAT_ACTIVE[status] and PP and true or false
    if d.stockHl then
        tf:Hide()
        ns.RF_StockAggro(d, on and status or nil)
        return
    end
    local agg = (rc and on) or nil
    if d._aggroBdr ~= agg then
        d._aggroBdr = agg
        if d.ApplyBorderColor then d.ApplyBorderColor() end
    end
    if on and not rc then
        PP.UpdateBorder(tf, bs, 1, 0, 0, 1)
        tf:Show()
    else
        tf:Hide()
    end
end

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

-- Inverted health fill: SetReverseFill swaps which SIDE of the seam the fill
-- texture paints -- missing health takes the bar colour and current health is
-- left to the background. Raid and party resolve through the caller's settings
-- table (party gets its own when the Health Bar section is unsynced).
-- On ns (200-local cap).
ns.RF_IsInvertedFill = function(s)
    return ((s or db.profile).healthInvertFill) and true or false
end

-------------------------------------------------------------------------------
--  Health-fill tint overlays
--
--  "Health Bar Color" indicators paint over the health FILL. A flat
--  SetColorTexture slab erases the bar's shading, so a tinted frame reads as a
--  solid block beside untinted ones; the overlay borrows the bar's own fill
--  texture instead and recolors it with a vertex color.
--
--  The overlay is anchored to the current-health area (ns.RF_AnchorCurHealth:
--  the fill texture, or under Inverted Fill the rest of the bar up to the fill's
--  HP edge), so it inherits the bar's fill geometry for free: these fills clip
--  by resizing rather than by moving their tex coords (measured -- identical
--  coords at full and at half fill), so the overlay stretches exactly as the bar
--  art does with nothing to update per tick. The coords are copied anyway so
--  anything the orientation pass does to them comes along, which is also why
--  the refresh runs after that pass (the anchor reads the direction it set).
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

-- Repaint BEFORE re-anchoring, and re-anchor with no ClearAllPoints
-- (RF_AnchorCurHealth only rewrites one TOPLEFT/BOTTOMRIGHT pair): the caller
-- isolates this, and a ClearAllPoints that succeeded ahead of a denied anchor
-- write would strand the overlay with no anchor at all for the rest of the session.
ns.RF_RefreshOneBarTint = function(bar, tex, ent, fill)
    if ent.r then ns.RF_TintOverBarFill(tex, bar, ent.r, ent.g, ent.b, ent.a) end
    if fill then ns.RF_AnchorCurHealth(tex._euiTintHost or tex, bar, fill) end
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

-- Fill axis AND inversion, applied and returned together: axis via
-- SetOrientation, inversion via SetReverseFill. Sole owner of both -- callers
-- take the returns rather than re-reading the settings, so the flags and the
-- anchors derived from them cannot disagree. Restyle/style passes only
-- (StyleButton, ReanchorAbsorbToFill, FB.StyleVisuals for the boss and pet
-- frames, ApplyPreviewData); the per-tick value paths must never touch either
-- property. They read the _euiInv stamp left on the bar (always our own
-- StatusBar) instead of the settings, so the value they paint -- current or
-- missing health -- always matches the fill direction set here.
ns.RF_ApplyHealthOrientation = function(bar, s)
    if not bar then return false end
    local vert = ns.RF_IsVerticalFill(s)
    local invert = ns.RF_IsInvertedFill(s)
    bar:SetOrientation(vert and "VERTICAL" or "HORIZONTAL")
    bar:SetReverseFill(invert)
    bar._euiInv = invert
    ns.RF_ApplyFillRotation(bar)
    return vert, invert
end

-- The fill texture's two corners on its HP edge (the current-health seam) that
-- the absorb, heal and clip anchors hang off: its right edge, its top edge on a
-- vertical bar, and the opposite edge under Inverted Fill. Paired top then
-- bottom on the horizontal axis, left then right on the vertical one.
ns.RF_HpEdge = function(vert, invert)
    if vert then
        if invert then return "BOTTOMLEFT", "BOTTOMRIGHT" end
        return "TOPLEFT", "TOPRIGHT"
    end
    if invert then return "TOPLEFT", "BOTTOMLEFT" end
    return "TOPRIGHT", "BOTTOMRIGHT"
end

-- Anchors a tint or wash over the bar's CURRENT-health area: the fill texture,
-- or under Inverted Fill (the fill then paints missing health) the rest of the
-- bar up to the fill's HP edge, the rect the alive bg takes there
-- (ns._ApplyHealthBg). Region anchors only, so no health value is read, and one
-- TOPLEFT/BOTTOMRIGHT pair in every case, so a re-anchor overwrites both points
-- without a ClearAllPoints. vert/invert: the fill direction from the caller's
-- settings; omitted, it is read off the bar. Style passes only.
ns.RF_AnchorCurHealth = function(region, bar, fill, vert, invert)
    if invert == nil then invert = bar.GetReverseFill and bar:GetReverseFill() end
    if not (fill and invert) then
        region:SetAllPoints(fill or bar)
        return
    end
    if vert == nil then vert = bar.GetOrientation and bar:GetOrientation() == "VERTICAL" end
    if vert then
        region:SetPoint("TOPLEFT", fill, "BOTTOMLEFT", 0, 0)
        region:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    else
        region:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        region:SetPoint("BOTTOMRIGHT", fill, "BOTTOMLEFT", 0, 0)
    end
end

-- Resolve an absorb/heal/max-health style key to a texture path: built-ins from
-- ABSORB_STYLE_TEX, "sm:" SharedMedia keys through the health-bar lookup. Used
-- by live render AND preview so a saved SM key paints identically.
-- Caller-handled keys (blizzardModern / maxHealthStripes) never reach this.
function ns.ResolveAbsorbStyleTex(style, fallback)
    return ABSORB_STYLE_TEX[style]
        or (EllesmereUI.ResolveTexturePath(healthBarTextures, style, fallback))
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
-- Party Frames kit: the host is the visible party frame (_euiKitRef, our
-- frame at the art's rect), whatever Uniform Icon Anchoring says.
function ns.RF_AnchorHost(health, s)
    local kit = health and health._euiKitRef
    if kit then return kit end
    local ref = health and health._euiUniformRef
    if ref and s and s.powerUniformAnchors then return ref end
    return health
end
-- Bar-relative texts (health, heal-absorb and status text): on the kit's
-- health bar under the Party Frames kit, where the stock frame puts them.
function ns.RF_BarHost(health, s)
    if health and health._euiKitRef then return health end
    return ns.RF_AnchorHost(health, s)
end

-- "Extend Health Bar Behind Power": the health-height inset layout sites subtract for
-- the power bar. On returns 0 -- health spans the full frame and the power bar (higher
-- frame level, own bg) draws over its bottom strip; off returns powerH untouched.
function ns.RF_HealthPowerInset(s, powerH)
    if s and s.extendHealthBehindPower then return 0 end
    return powerH
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

-- Show Groups as the frames apply it; every Show Groups reader goes through
-- here. Hide Groups 5-8 in Mythic Raid (opt-in): inside a Mythic raid
-- (difficulty 16, groups 1-4 only) groups 5-8 hide on top of Show Groups.
-- The capped set is ONE reused table: read it at once, never hold it.
ns._mythicGroups = {}
ns._VisibleGroups = function()
    local s = db.profile
    local vg = s.visibleGroups
    if not s.mythicRaidHideGroups then return vg end
    local _, _, difficultyID = GetInstanceInfo()
    if difficultyID ~= 16 then return vg end
    local t = ns._mythicGroups
    for g = 1, 8 do t[g] = g <= 4 and not (vg and vg[g] == false) end
    return t
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
    local vg = ns._VisibleGroups()
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
-- Safe health percent: returns 0-100, no secret value arithmetic. inv: the
-- missing-health percent instead (100-0, the reversed curve), for a bar under
-- Inverted Fill.
local function GetSafeHealthPercent(unit, inv)
    if inv then return UnitHealthPercent(unit, true, CurveConstants.ReverseTo100) end
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
    -- Party Frames kit: the portrait greys out while offline, as stock does
    -- (every connection edge passes through here).
    local kp = d.kitPortrait
    if kp then
        local off = not connected
        if d._kitDesat ~= off then d._kitDesat = off; kp:SetDesaturated(off) end
    end
    -- Party portrait (EUI_RaidFrames_Portrait.lua): the same grey.
    local pt = d.pt
    if pt and pt._on and pt._desat ~= (not connected) then ns.RF_PtOffline(d, unit, connected) end
    -- Dead/offline: bg covers the FULL bar, fill dims. State+color stamped so
    -- a repeated tick in the same state re-applies nothing; entering either
    -- state clears the alive-path anchor/color stamps AND the fill-color
    -- stamp in _UpdateButtonHealth (the tint here overwrote its work).
    if not connected or deadOrGhost then
        local c = (not connected) and (s.statusColorOffline or { r = 0x66/255, g = 0x66/255, b = 0x66/255 })
            or (s.statusColorDead or { r = 0x24/255, g = 0x17/255, b = 0x17/255 })
        local st = (not connected) and 3 or 2
        -- Under Inverted Fill a corpse paints a full missing-health bar (UpdateButton):
        -- its own state, so that fill is hidden and the status colour shows undimmed.
        local hideFill = deadOrGhost and health and health._euiInv
        if hideFill then st = st + 2 end
        if d._bgSt ~= st or d._bgR ~= c.r or d._bgG ~= c.g or d._bgB ~= c.b then
            d._bgSt, d._bgR, d._bgG, d._bgB = st, c.r, c.g, c.b
            d._bgTex, d._bgA = nil, nil
            d._hcR = nil
            if bg then
                bg:ClearAllPoints(); bg:SetAllPoints(health)
                bg:SetColorTexture(c.r, c.g, c.b, 1)
            end
            if health then
                if hideFill then health:SetStatusBarColor(0.3, 0.3, 0.3, 0)
                elseif not connected then health:SetStatusBarColor(0.3, 0.3, 0.3, 0.3)
                else health:SetStatusBarColor(0.3, 0.3, 0.3, 0.5) end
            end
        end
        return
    end
    if not bg then return end
    -- Alive: the bg covers exactly the half of the bar the fill texture does NOT
    -- paint, so it hangs off the fill's leading edge -- the fill's right edge
    -- normally, its top edge on a vertical bar, and the opposite edge under
    -- Inverted Fill (where the fill paints missing health and the bg becomes the
    -- current-health surface). The anchor set changes only when the fill texture
    -- object, the axis, or the inversion does; all three change only in the
    -- restyle passes (ReloadFrames / ReloadPartyFrames), which clear d._bgSt right
    -- after, so the steady-state tick skips the reads and the anchor pass entirely.
    if d._bgSt ~= 1 then
        -- Axis and inversion both read off the bar, never the settings, so the
        -- bg follows the direction the fill actually paints.
        local vert = health.GetOrientation and health:GetOrientation() == "VERTICAL"
        local invert = health:GetReverseFill()
        local tex = health:GetStatusBarTexture()
        d._bgSt, d._bgTex, d._bgVert = 1, tex, vert
        d._bgA = nil
        bg:ClearAllPoints()
        if vert then
            if invert then
                bg:SetPoint("TOPLEFT", tex, "BOTTOMLEFT", 0, 0)
                bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            else
                bg:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
                bg:SetPoint("BOTTOMRIGHT", tex, "TOPRIGHT", 0, 0)
            end
        else
            if invert then
                bg:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
                bg:SetPoint("BOTTOMRIGHT", tex, "BOTTOMLEFT", 0, 0)
            else
                bg:SetPoint("TOPLEFT", tex, "TOPRIGHT", 0, 0)
                bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            end
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

-- WoW Forever Name Format (the Name Text cog, nameFormat): the character name's
-- first or last word; unset or "full" shows it whole. Nicknames are never
-- shortened. Defined only on Forever, so elsewhere a name pays one nil test.
-- On ns (local cap).
if ns.EllesmereUI.IS_FOREVER then
    function ns.RF_FormatName(display, s)
        local mode = s and s.nameFormat
        if not mode or mode == "full" then return display end
        return ns.EllesmereUI.ForeverShortName(display, mode)
    end
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
    local name, surname = UnitName(unit)
    name = name or ""
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
                display = EllesmereUI.WithSurname(name, surname)
                if ns.RF_FormatName then display = ns.RF_FormatName(display, s) end
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
        display = EllesmereUI.WithSurname(name, surname)
        if ns.RF_FormatName then display = ns.RF_FormatName(display, s) end
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
-- Show on Bottom (topNameBarBottom): the bar takes the frame's BOTTOM edge instead. Health starts
-- flush at the top (same height), and the power bar and the uniform anchor region (health +
-- power) end on the bar. Those two, and the bar's own edge, are re-anchored only while the option
-- is or just was on, so the top layout never touches them.
local function LayoutTopNameBar(s, baseH, powerH, healthBar, tnb, tnbBg, tnbText, powerBar)
    local enabled = s.topNameBarEnabled
    local topBarH = enabled and PixelSnap(s.topNameBarHeight or 20) or 0
    local bottomY = (enabled and s.topNameBarBottom == true) and topBarH or 0
    local parent
    if healthBar then
        -- A party portrait's bars' area (EUI_RaidFrames_Portrait.lua), else the frame.
        parent = healthBar._euiBarArea or healthBar:GetParent()
        local topY = (bottomY > 0) and 0 or -topBarH
        healthBar:ClearAllPoints()
        healthBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, topY)
        healthBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, topY)
        healthBar:SetHeight(PixelSnap(baseH - ns.RF_HealthPowerInset(s, powerH) - topBarH))
        if bottomY > 0 or (healthBar._euiTnbBottomY or 0) > 0 then
            local uref = healthBar._euiUniformRef
            -- Aura containers protect these once anchored: a combat pass leaves
            -- them for the next one (the stamp stays unchanged).
            if not (InCombatLockdown() and ((powerBar and powerBar:IsProtected())
                or (uref and uref:IsProtected()))) then
                if uref then
                    uref:ClearAllPoints()
                    uref:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                    uref:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, bottomY)
                end
                if powerBar then
                    powerBar:ClearAllPoints()
                    powerBar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, bottomY)
                    powerBar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, bottomY)
                end
                healthBar._euiTnbBottomY = bottomY
            end
        end
    end
    if not tnb then return topBarH end
    if not enabled then
        tnb:Hide()
        return topBarH
    end
    if parent and (bottomY > 0 or tnb._euiTnbBottom) then
        tnb:ClearAllPoints()
        if bottomY > 0 then
            tnb:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
            tnb:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
        else
            tnb:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
            tnb:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
        end
        tnb._euiTnbBottom = (bottomY > 0) or nil
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
        -- Level Position "Attach to Name" keeps the level in front of the name.
        local attach = ns.RF_LEVEL_ATTACH[bs.levelTextPosition or ns.RF_LEVEL_DEFAULT]
        if d and d.nameText then
            if attach then
                ns._RFNameWithLevel(d.nameText, ResolveDisplayName(unit, true, bs), unit, attach)
            else
                d.nameText:SetText(ResolveDisplayName(unit, true, bs))
            end
            local nr, ng, nb = GetNameColor(unit, bs)
            d.nameText:SetTextColor(nr, ng, nb)
        end
        if d and d.topNameBarText and bs.topNameBarEnabled then
            if attach then
                ns._RFNameWithLevel(d.topNameBarText, ResolveDisplayName(unit, false, bs), unit, attach)
            else
                d.topNameBarText:SetText(ResolveDisplayName(unit, false, bs))
            end
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

-- A preview text's colour for its colour mode: accent, class (classToken: the sample member's
-- class; none, as for a pet, reads white), power (pToken: the sample member's power type) or
-- custom (custom: the colour). r, g, b: the colour without one.
function ns.RF_PreviewTextColor(mode, custom, classToken, r, g, b, pToken)
    if mode == "accent" then
        local ar, ag, ab = EllesmereUI.ResolveActiveAccent()
        if ar then return ar, ag, ab end
    elseif mode == "class" then
        local cc = EllesmereUI.GetClassColor(classToken)
        return cc.r, cc.g, cc.b
    elseif mode == "power" then
        local pc = EllesmereUI.GetPowerColor(pToken or "MANA")
        if pc then return pc.r, pc.g, pc.b end
    elseif custom then
        return custom.r, custom.g, custom.b
    end
    return r, g, b
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

-- Health text in one of the health text modes. A unit's values are read only in the modes that
-- show them; a preview (unit nil) shows made-up ones, perPct per percent. Returns false for None or
-- an unknown mode, which blank the text.
function ns.RF_HealthTextInto(fs, mode, pct, unit, perPct)
    local v
    if mode == "percent" then
        fs:SetFormattedText("%.0f%%", pct)
    elseif mode == "percentNoSign" then
        fs:SetFormattedText("%.0f", pct)
    elseif mode == "number" then
        if unit then v = UnitHealth(unit, true) else v = pct * perPct end
        if v and AbbreviateNumbers then
            fs:SetText(AbbreviateNumbers(v))
        elseif v then
            fs:SetFormattedText("%s", v)
        end
    elseif mode == "numberPercent" or mode == "percentNumber" then
        if unit then v = UnitHealth(unit, true) else v = pct * perPct end
        local numStr = (v and AbbreviateNumbers) and AbbreviateNumbers(v) or tostring(v or 0)
        if mode == "numberPercent" then
            fs:SetFormattedText("%s | %.0f%%", numStr, pct)
        else
            fs:SetFormattedText("%.0f%% | %s", pct, numStr)
        end
    elseif mode == "missing" then
        if unit then v = UnitHealthMissing(unit, true) else v = (100 - pct) * perPct end
        fs:SetText(C_StringUtil.TruncateWhenZero(v))
        if fs:GetText() then
            if v and AbbreviateNumbers then
                fs:SetText(AbbreviateNumbers(v))
            elseif v then
                fs:SetFormattedText("%s", v)
            end
        end
    else
        fs:SetText("")
        return false
    end
    return true
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
    -- Power Text's colour is identity-class state too (its Power mode is this type's colour).
    if d._pwtMode then ns._RFPowerTextColor(d, unit, s, pr, pg, pb) end
end

-------------------------------------------------------------------------------
--  Power Text (opt-in, default None): the unit's power as text in Health Text's
--  9-point scheme on the same health bar host, shown only while the button's
--  power bar shows. Nothing exists while None: the FontString is built the first
--  time a shown power bar paints with a mode set. d._pwtMode (the mode, nil = no
--  text shown) is the one field the per-tick power paths and the UNIT_HEALTH
--  path test; the colour rides the identity edge above, the value rides every
--  power value push, and dead/offline blanks it as Health Text. On ns
--  (200-local cap).
-------------------------------------------------------------------------------

-- Power text in one of its modes (Health Text's minus Missing). pct: the bar's percent
-- (UnitPowerPercent, which can be secret in combat: it only ever reaches a format setter).
-- unit + pType: the live unit, blank while dead or offline like Health Text (both checks return
-- clean booleans for group units); its amount is read only in the modes that show it and goes
-- straight through AbbreviateNumbers into the setter, never compared. A preview (unit nil)
-- shows made-up amounts, perPct per percent. Returns false when it blanks the text (dead,
-- offline, None or an unknown mode).
function ns.RF_PowerTextInto(fs, mode, pct, unit, pType, perPct)
    if unit and (UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit)) then
        fs:SetText("")
        return false
    end
    if mode == "percent" then
        fs:SetFormattedText("%.0f%%", pct)
    elseif mode == "percentNoSign" then
        fs:SetFormattedText("%.0f", pct)
    elseif mode == "number" or mode == "numberPercent" or mode == "percentNumber" then
        local num
        if unit then num = AbbreviateNumbers(UnitPower(unit, pType)) else num = AbbreviateNumbers(pct * perPct) end
        if mode == "number" then
            fs:SetText(num)
        elseif mode == "numberPercent" then
            fs:SetFormattedText("%s | %.0f%%", num, pct)
        else
            fs:SetFormattedText("%.0f%% | %s", pct, num)
        end
    else
        fs:SetText("")
        return false
    end
    return true
end

-- Live Power Text colour for its colour mode. pr, pg, pb: the unit's power-type colour, already
-- resolved by the caller (the identity edge above, or the cross-module colour push).
ns._RFPowerTextColor = function(d, unit, s, pr, pg, pb)
    local mode = s.powerTextColorMode
    local r, g, b = 1, 1, 1
    if mode == "power" then
        r, g, b = pr, pg, pb
    elseif mode == "class" then
        local _, classToken = UnitClass(unit)
        if not issecretvalue(classToken) and classToken then
            local cc = ns.EllesmereUI.GetClassColor(classToken)
            if cc then r, g, b = cc.r, cc.g, cc.b end
        end
    elseif mode == "accent" then
        local ar, ag, ab = ns.EllesmereUI.ResolveActiveAccent()
        if ar then r, g, b = ar, ag, ab end
    else -- "custom"
        local c = s.powerTextCustomColor
        if c then r, g, b = c.r, c.g, c.b end
    end
    d.powerText:SetTextColor(r, g, b, 0.9)
end

-- Anchor on Health Text's host (the health bar, or the Party Frames kit's) with its width and
-- 9-point scheme. Party/extra-aware like the per-button anchor closures; re-run by every reload
-- pass and the Party Frames kit pass.
ns._RFAnchorPowerText = function(d)
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    ns.AnchorRFText(d.powerText, ns.RF_BarHost(d.health, s), s.powerTextPosition or "bottom",
        s.powerTextOffsetX or 0, s.powerTextOffsetY or 0,
        d.kitG and d.kitG.health.w or (s.frameWidth or 72) * 0.75)
end

-- Show or hide by mode for a button whose power bar shows (the full power paint, ahead of the
-- identity edge so a newly shown text takes its colour there); builds the FontString on the
-- text carrier the first time a mode needs it. Stamps d._pwtMode.
ns._RFPowerTextSetup = function(d, s)
    local mode = s.powerTextMode
    if mode == nil or mode == "none" then
        if d._pwtMode then d.powerText:Hide(); d._pwtMode = nil end
        return
    end
    local fs = d.powerText
    if not fs then
        fs = d.textCarrier:CreateFontString(nil, "OVERLAY")
        ApplyFont(fs, s.powerTextSize or 8)
        fs:SetWordWrap(false)
        fs:SetTextColor(1, 1, 1, 0.9)
        d.powerText = fs
        ns._RFAnchorPowerText(d)
    end
    if not d._pwtMode then fs:Show() end
    d._pwtMode = mode
end

-- Dead/offline edge, from the UNIT_HEALTH path that owns death, release and resurrection (none
-- of them has to move a power value): blank or refill once per transition. d._pwtGone stamps
-- the state last seen here (clean booleans); the full power paint clears it so a new occupant
-- is always re-checked on its next health tick.
ns._RFPowerTextLife = function(d, unit, gone)
    if d._pwtGone == gone then return end
    d._pwtGone = gone
    if gone then d.powerText:SetText(""); return end
    local pType = d._pwType or UnitPowerType(unit) or 0
    ns.RF_PowerTextInto(d.powerText, d._pwtMode,
        UnitPowerPercent(unit, pType, true, CurveConstants.ScaleTo100), unit, pType)
end

-------------------------------------------------------------------------------
--  Level Text: the unit's level in front of the name inside the name text itself
--  (Attach to Name, "60 Name", the WoW Forever default; or with a divider, "60 | Name"), or
--  on its own spot on Health Text's host in the name's colour. Nothing exists
--  while None or attached: the FontString is built the first time a full paint
--  runs with a spot set. d._lvlOn is true while it shows. UNIT_LEVEL (a level-only
--  repaint, ns._RFRepaintLevel) is registered only while some view shows the level.
--  The level is the effective one (scaled content), like the suite's other level
--  texts. On ns (200-local cap).
-------------------------------------------------------------------------------

-- The attached positions and their formats: known level, unknown ("??") level.
ns.RF_LEVEL_ATTACH = {
    name    = { "%d %s", "?? %s" },
    nameDiv = { "%d | %s", "?? | %s" },
}

-- True while the raid, party or extra-frames view shows Level Text.
function ns._RFLevelWanted()
    return (ns._scaledProfile.levelTextPosition or ns.RF_LEVEL_DEFAULT) ~= "none"
        or (ns._scaledPartyProxy.levelTextPosition or ns.RF_LEVEL_DEFAULT) ~= "none"
        or (ns._scaledExtraProxy.levelTextPosition or ns.RF_LEVEL_DEFAULT) ~= "none"
end

-- Anchor on Health Text's host with the 9-point scheme; party/extra-aware like the
-- Power Text anchor, and re-run by every reload pass and the Party Frames kit pass.
ns._RFAnchorLevelText = function(d)
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    local pos = s.levelTextPosition or ns.RF_LEVEL_DEFAULT
    if pos == "none" or ns.RF_LEVEL_ATTACH[pos] then return end
    ns.AnchorRFText(d.levelText, ns.RF_BarHost(d.health, s), pos,
        s.levelTextOffsetX or 0, s.levelTextOffsetY or 0)
end

-- The level as text: a secret level goes straight to the setter (never compared),
-- "??" for a unit too far above to read, blank while it is not known yet.
ns._RFLevelInto = function(fs, unit)
    local lvl = UnitEffectiveLevel(unit)
    if issecretvalue(lvl) then
        fs:SetFormattedText("%d", lvl)
    elseif not lvl or lvl == 0 then
        fs:SetText("")
    elseif lvl < 0 then
        fs:SetText("??")
    else
        fs:SetFormattedText("%d", lvl)
    end
end

-- The level the previews show on every sample member: the player's own.
ns._RFPreviewLevel = function()
    local lvl = UnitEffectiveLevel("player")
    if issecretvalue(lvl) or not lvl or lvl <= 0 then return 60 end
    return lvl
end

-- Attach to Name: the name text in an attached position's format (fmt, from
-- RF_LEVEL_ATTACH). The name (possibly secret) and the level only ever reach the
-- format setter; an unknown level, or a name not known yet (empty), leaves the
-- name alone.
ns._RFNameWithLevel = function(fs, name, unit, fmt)
    local lvl = UnitEffectiveLevel(unit)
    local nameKnown = issecretvalue(name) or (name ~= nil and name ~= "")
    if not nameKnown then
        fs:SetText(name)
    elseif issecretvalue(lvl) then
        fs:SetFormattedText(fmt[1], lvl, name)
    elseif not lvl or lvl == 0 then
        fs:SetText(name)
    elseif lvl < 0 then
        fs:SetFormattedText(fmt[2], name)
    else
        fs:SetFormattedText(fmt[1], lvl, name)
    end
end

-- The full paint's share for the own spot: shown or hidden by position (built on first
-- need), filled, and coloured as the name (r, g, b).
ns._RFLevelText = function(d, s, unit, r, g, b)
    local pos = s.levelTextPosition or ns.RF_LEVEL_DEFAULT
    if pos == "none" or ns.RF_LEVEL_ATTACH[pos] then
        if d._lvlOn then d.levelText:Hide(); d._lvlOn = nil end
        return
    end
    local fs = d.levelText
    if not fs then
        fs = d.textCarrier:CreateFontString(nil, "OVERLAY")
        ApplyFont(fs, s.levelTextSize or 10)
        fs:SetWordWrap(false)
        d.levelText = fs
        ns._RFAnchorLevelText(d)
    end
    if not d._lvlOn then fs:Show(); d._lvlOn = true end
    ns._RFLevelInto(fs, unit)
    fs:SetTextColor(r, g, b)
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
    absorbBar:SetStatusBarColor(ac.r or 1, ac.g or 1, ac.b or 1, alpha)
    local tiled = (style == "striped" or style == "stripedReversed" or style == "stripedThick" or style == "stripedThickR" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" or style == "pixelsShieldFill")
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
        fw:SetStatusBarColor(ac.r or 1, ac.g or 1, ac.b or 1, alpha)
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
    local tiled = (style == "striped" or style == "stripedReversed" or style == "stripedThick" or style == "stripedThickR" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" or style == "pixelsShieldFill")
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
        tiled = (style == "striped" or style == "stripedReversed" or style == "stripedThick" or style == "stripedThickR" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" or style == "pixelsShieldFill")
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

    -- Blizzard Glow Line (Default Blizz Frames' spark, any style when on): fixed 16px soft glow
    -- (cast_spark.tga, ADD) centered on the shield's edge next to current health, half over
    -- health, half over shield. Its own host above the shield keeps the health-side half out of
    -- missClip. Created on the forward bar's LEFT edge (the current-HP seam); UpdateAbsorb
    -- re-points it per placement. A StatusBar fed the absorb with a tiny max fills 100% on ANY
    -- shield -- self-gates off the secret absorb, no boolean/mask.
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
    -- Overshield spark: rides the overshield's edge next to current health while overshielding
    -- (the backfill's LEFT edge; its RIGHT edge with From Left). Anchored by UpdateAbsorb.
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
    -- created further down, before the first call (at the end of this function), so every
    -- button's first pass anchors them too, including buttons built mid-session.
    local healAbsorbBar, healPredBar, healClip, reducedBar

    -- Re-anchor clip frames and forward bar to the current health fill texture.
    -- Must be called whenever SetStatusBarTexture replaces the fill object.
    local function ReanchorAbsorbToFill()
        local fill = healthBar:GetStatusBarTexture()

        -- Vertical fill: the whole HP cluster rotates with the health bar -- every anchor below is
        -- the horizontal layout axis-swapped (the fill's RIGHT "HP edge" that shields/heal
        -- absorb/prediction hang off becomes its TOP edge; frame right/left become top/bottom).
        -- Resolved live off the button's settings source so party keeps its own Health Bar section.
        -- Inverted fill: the seam (the current-HP point) sits at the same coordinate
        -- either way -- only which side of it the fill texture paints changes. So the
        -- "HP edge" the cluster hangs off moves from the fill's RIGHT/TOP to its
        -- LEFT/BOTTOM and every anchor on it flips; anchors on the health FRAME's edges
        -- are unaffected and are deliberately left alone below.
        local vs = d._isParty and ns._scaledPartyProxy
            or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
        local isVert, isInvert = ns.RF_ApplyHealthOrientation(healthBar, vs)
        backfillBar._axisVert = isVert  -- read by the Blizzard Glow Line (hidden on a vertical fill)
        -- The fill's two HP-edge corners: every fill anchor below is on one of these.
        local hpA, hpB = ns.RF_HpEdge(isVert, isInvert)
        -- Overlay Reverse (Full): Overlay Reverse, plus the forward bar filling from the bar's
        -- ORIGIN edge (left; bottom when vertical -- frame edges, so Inverted Fill leaves them
        -- alone), so missClip shows the absorb exceeding current health past the seam instead
        -- of losing it. Its clip starts exactly at the seam: the 1px seal into the fill would
        -- double that pixel over the backfill. Default Blizz Frames keeps Overlay Reverse.
        local orFull = db.profile.absorbEdgeMode == "overlayReverseFull"
            and db.profile.absorbStyle ~= "blizzardModern"

        -- Health Bar Color overlays track this bar's fill, so they follow the swap
        -- for the same reason the absorb cluster below does. After the orientation
        -- call, not before: the repaint copies the fill's tex coords, and that call
        -- is what rotates them.
        healthBar._euiFillOpacity = (vs.healthBarOpacity or 100) / 100
        ns.RF_RefreshBarTints(healthBar)
        -- Indexed, not ipairs: a nil entry must not end the walk early.
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
            curClip:SetPoint("TOPRIGHT", fill, hpB, 0, 0)
            missClip:ClearAllPoints()
            missClip:SetPoint("BOTTOMLEFT", fill, hpA, 0, orFull and 0 or -1)
            missClip:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            forwardBar:ClearAllPoints()
            if orFull then
                forwardBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                forwardBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            else
                forwardBar:SetPoint("BOTTOMLEFT", fill, hpA, 0, 0)
                forwardBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
            end
            if healPredBar then
                healPredBar:ClearAllPoints()
                healPredBar:SetPoint("BOTTOMLEFT", fill, hpA, 0, 0)
                healPredBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
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
            elseif vAbsorbMode == "overlayReverse" or vAbsorbMode == "overlayReverseFull" then
                -- Overlay Reverse, vertical axis: whole absorb fills DOWN into the fill from
                -- its top edge (UP from its bottom edge under Inverted Fill); default
                -- filled-region clip masks any excess (see the horizontal branch; Full draws
                -- it through the forward bar).
                backfillBar:SetReverseFill(true)
                backfillBar:SetPoint("TOPLEFT", fill, hpA, 0, 0)
                backfillBar:SetPoint("TOPRIGHT", fill, hpB, 0, 0)
            else
                -- Overshield "From Left" on the vertical axis: excess grows
                -- from the bar's bottom (origin) edge -- see the horizontal
                -- branch for the anchor mechanics.
                local osm = db.profile.overshieldMode
                if osm == nil then osm = (db.profile.showOvershield == false) and "never" or "always" end
                if osm == "fromleft" and db.profile.absorbStyle ~= "blizzardModern" then
                    backfillBar:SetReverseFill(false)
                    backfillBar:SetPoint("TOPLEFT", fill, hpA, 0, 0)
                    backfillBar:SetPoint("TOPRIGHT", fill, hpB, 0, 0)
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
                        healClip:SetPoint("TOPRIGHT", fill, hpB, 0, 0)
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
                    healAbsorbBar:SetPoint("TOPLEFT", fill, hpA, 0, 0)
                    healAbsorbBar:SetPoint("TOPRIGHT", fill, hpB, 0, 0)
                end
            end
            return
        end

        curClip:ClearAllPoints()
        curClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        curClip:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
        missClip:ClearAllPoints()
        missClip:SetPoint("TOPLEFT", fill, hpA, orFull and 0 or -1, 0)
        missClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        forwardBar:ClearAllPoints()
        if orFull then
            forwardBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            forwardBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
        else
            forwardBar:SetPoint("TOPLEFT", fill, hpA, 0, 0)
            forwardBar:SetPoint("BOTTOMLEFT", fill, hpB, 0, 0)
        end
        if healPredBar then
            healPredBar:ClearAllPoints()
            healPredBar:SetPoint("TOPLEFT", fill, hpA, 0, 0)
            healPredBar:SetPoint("BOTTOMLEFT", fill, hpB, 0, 0)
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
        elseif absorbMode == "overlayReverse" or absorbMode == "overlayReverseFull" then
            -- Overlay Reverse: the WHOLE absorb backfills from the health
            -- fill's leading edge INTO the fill. curClip keeps the default
            -- filled-region clip from above, so a shield larger than current
            -- health is masked at the frame edge -- nothing ever renders over
            -- missing health (the forward bar is hidden by the value pass,
            -- same as the edge modes). Full shows that excess through the
            -- origin-edge forward bar instead.
            backfillBar:SetReverseFill(true)
            backfillBar:ClearAllPoints()
            backfillBar:SetPoint("TOPRIGHT", fill, hpA, 0, 0)
            backfillBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
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
                backfillBar:SetPoint("TOPRIGHT", fill, hpA, 0, 0)
                backfillBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
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
                    healClip:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
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
                healAbsorbBar:SetPoint("TOPRIGHT", fill, hpA, 0, 0)
                healAbsorbBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
            end
        end
    end

    -- Per-button calculator for reading absorb value (secret-safe)
    local hpCalc
    if CreateUnitHealPredictionCalculator then
        hpCalc = CreateUnitHealPredictionCalculator()
        if hpCalc.SetMaximumHealthMode then
            -- Configured ONCE: modes persist on the calculator across fills, and
            -- UpdateAbsorb reads the Default (base) maximum every paint.
            hpCalc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
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
    -- Health-bar size for the absorb paint: stamped by the bar's own resize edge
    -- instead of two reads per paint (the bar resizes only on reload/tier
    -- passes; the next paint reads the stamp). 0 until the first layout, which
    -- the paint treats as "read it".
    backfillBar._hpW, backfillBar._hpH = healthBar:GetWidth(), healthBar:GetHeight()
    healthBar:HookScript("OnSizeChanged", function(_, w, h)
        backfillBar._hpW, backfillBar._hpH = w, h
    end)
    backfillBar._curClip      = curClip
    backfillBar._missClip     = missClip
    backfillBar._absorbMask   = absorbMask

    d.absorbBar = backfillBar
    -- First pass here, after every bar it anchors exists: a button built mid-session
    -- (Extra Frames) may get no restyle pass, and its heal bars would keep their
    -- creation anchors (horizontal, not inverted).
    ReanchorAbsorbToFill()
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
    -- Party Frames kit: the strips that hang off the frame edge use the
    -- visible party frame, not the whole button box; a party portrait's
    -- frame, the bars beside it.
    button = hp._euiKitRef or hp._euiBarArea or button
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
-- Absorb paint helpers (on ns: this file sits at the 200-local cap). Every
-- absorb child is toggled by UpdateAbsorb alone -- creation hides them and the
-- style appliers never touch visibility -- so a stamped Show/Hide is exact:
-- nil = fresh frame, always pushes. Ranges: max health reads PLAIN for group
-- members, so a per-bar stamp skips the identical re-push; a secret max always
-- pushes and clears the stamp (today's behavior in every restricted context).
function ns._RFShow(f)
    if f._vis ~= true then f._vis = true; f:Show() end
end
function ns._RFHide(f)
    if f._vis ~= false then f._vis = false; f:Hide() end
end
function ns._RFPushRange(bar, maxHealth, maxPlain)
    if maxPlain and bar._rMax == maxHealth then return end
    bar:SetMinMaxValues(0, maxHealth)
    bar._rMax = maxPlain and maxHealth or nil
end

-- now: the caller's frame clock when it has one (the flush paints a batch on
-- one read); nil = read it here.
local function UpdateAbsorb(button, unit, now)
    local d = GetFFD(button)
    local ab = d.absorbBar
    if not ab then return end
    local fw = ab._forward
    local hp = ab._hpBar
    local ha = ab._healAbsorb
    local calc = ab._hpCalculator
    if not hp then return end
    local RFShow, RFHide, PushRange = ns._RFShow, ns._RFHide, ns._RFPushRange

    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    local topBar = ab._topBar
    local barPos = ns.GetAbsorbBarPosition(s)
    local barOn = topBar and barPos ~= "none"
    local healTopBar = ab._healTopBar
    local healBarPos = ns.GetHealAbsorbBarPosition(s)
    local healBarOn = healTopBar and healBarPos ~= "none"
    local styleOn = s.absorbStyle and s.absorbStyle ~= "none"
    local modern = s.absorbStyle == "blizzardModern"
    -- Blizzard Glow Line, settings-derived and gen-gated (an unset key would otherwise fall
    -- through the proxy chain on every paint). Unset follows the style: on for Default Blizz
    -- Frames only. _glowEdge = where the line sits on the drawn layout:
    --   1 = the current-HP seam, moving to the overshield's LEFT edge while overshielding
    --       (Overlay; Default Blizz Frames in every stored placement, as it always drew);
    --   2 = Overlay with From Left: the seam, moving to the from-left overshield's RIGHT
    --       edge while overshielding;
    --   3 = Overlay Reverse: the shield's LEFT edge, which always meets current health;
    --   5 = From Right Edge: the shield's LEFT edge, shown only while the shield reaches
    --       current health (exactly the overshield boolean).
    -- From Left Edge draws no line: no secret-safe test tells whether its edge meets current
    -- health. Vertical fill hides it too: these 16px glows cannot follow a vertical edge.
    if ab._glowGen ~= ns._absorbGen then
        ab._glowGen = ns._absorbGen
        local gl = s.absorbGlowLine
        ab._glowOn = gl == true or (gl == nil and modern)
        local em = s.absorbEdgeMode or "overlay"
        if modern then
            ab._glowEdge = 1
        elseif em == "overlay" then
            local osm = s.overshieldMode
            if osm == nil then osm = (s.showOvershield == false) and "never" or "always" end
            ab._glowEdge = (osm == "fromleft") and 2 or 1
        elseif em == "right" then
            ab._glowEdge = 5
        elseif em == "left" then
            ab._glowOn = false
            ab._glowEdge = 4
        else
            ab._glowEdge = 3
        end
    end
    local glowOn = styleOn and ab._glowOn and not ab._axisVert
    -- The seam/overshield flip (placements 1-2) and the From Right Edge gate (5) read the
    -- overshield boolean; Overlay Reverse (3) needs none.
    local needClamp = glowOn and ab._glowEdge ~= 3
    -- Heal absorb is independent of the shield absorb: keep going whenever its style is on.
    local healOn = (s.healAbsorbStyle or "clean") ~= "none"
    -- Heal prediction is also independent, and shares this frame, so it must keep the frame alive too.
    local predOn = s.healPrediction and true or false
    -- Reduced max health is independent too (a max-HP-loss debuff has nothing to do with
    -- shield absorbs) -- without this the whole overlay frame bails out below whenever
    -- Absorb Style is "none", even with Max Health Style on, so it never gets to paint.
    local maxHealthOn = (s.maxHealthStyle or "maxHealthStripes") ~= "none"
    if not styleOn and not barOn and not healOn and not healBarOn and not predOn and not maxHealthOn then
        RFHide(ab)
        if fw then RFHide(fw) end
        if fw and fw._edgeSpark then RFHide(fw._edgeSpark) end
        if fw and fw._bfSpark then RFHide(fw._bfSpark) end
        if ha then RFHide(ha) end
        if topBar then RFHide(topBar) end
        if healTopBar then RFHide(healTopBar) end
        return
    end

    local maxHealth, absorbAmt, isClamped
    -- The calculator serves exactly two consumers: the Blizzard Glow Line's
    -- seam/overshield flip (the Missing-Health clamp boolean) and the
    -- incoming-heal amount (its heal-absorb-reduced form). Anything else with
    -- prediction off reads nothing it adds, so it skips the fill and takes the
    -- range from the plain max. Max mode is configured once at creation.
    if calc and UnitGetDetailedHealPrediction and (needClamp or predOn) then
        UnitGetDetailedHealPrediction(unit, nil, calc)
        maxHealth = calc:GetMaximumHealth()
        if needClamp then
            -- 2nd return (Missing Health clamp) = secret-safe overshield boolean.
            local _, clampedBool = calc:GetDamageAbsorbs()
            isClamped = clampedBool
        end
    else
        maxHealth = UnitHealthMax(unit) or 0
    end
    -- Bars get the FULL absorb so the overflow/backfill renders correctly.
    absorbAmt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0
    local maxPlain = not issecretvalue(maxHealth)
    -- One heal-absorb fetch serves both the strip bar AND the overlay below.
    local healAbsorbAmt = (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit)) or 0

    -- Incoming heals, fetched here so the short-circuit below sees it too.
    -- predOn-GATED: with prediction off this stays a constant 0, so the fetch
    -- never runs and the memo's _mPred compares 0==0 forever -- heal traffic
    -- must not break the short-circuit for users without the feature.
    -- Calculator is refreshed above; legacy global only as its fallback.
    local incomingHeals = 0
    if predOn then
        if calc and UnitGetDetailedHealPrediction and calc.GetIncomingHeals then
            incomingHeals = calc:GetIncomingHeals() or 0
        elseif UnitGetIncomingHeals then
            incomingHeals = UnitGetIncomingHeals(unit) or 0
        end
    end

    -- Identical-state short-circuit: absorbs re-flush far more often than values change and every
    -- paint below is idempotent. Skip when values, health-bar size and the settings generation all
    -- match the last paint. SECRET-SAFE: secrets cannot be compared, so any secret input fails
    -- open to painting and poisons the memo for the next plain pass.
    -- Health-bar size from the resize stamp (CreateAbsorbBar hooks the bar's
    -- own OnSizeChanged); the read is the fallback until the first layout.
    local hpW, hpH = ab._hpW, ab._hpH
    if not hpW or hpW == 0 then hpW, hpH = hp:GetWidth(), hp:GetHeight() end
    local isSec = issecretvalue
    local anySec = isSec and (isSec(absorbAmt) or isSec(maxHealth)
       or isSec(healAbsorbAmt) or isSec(isClamped) or isSec(incomingHeals))
    -- Absorb-active lean flag: the health ride repaints absorbs ONLY while
    -- this is set (clamp state can flip with health while shielded; with no
    -- absorb, a health change alters nothing this function paints). Event
    -- branches arm it; a fresh PLAIN all-zero read here disarms; secret reads
    -- keep it armed (fail-open = today's always-paint behavior in combat).
    ab._paintAt = now or GetTime()
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
            PushRange(topBar, maxHealth, maxPlain)
            topBar:SetValue(absorbAmt)
            RFShow(topBar)
        else
            RFHide(topBar)
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
            PushRange(healTopBar, maxHealth, maxPlain)
            healTopBar:SetValue(healAbsorbAmt)
            RFShow(healTopBar)
        else
            RFHide(healTopBar)
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
            RFHide(ha)
        else
            if ha._szW ~= hpW or ha._szH ~= hpH then
                ha._szW = hpW; ha._szH = hpH
                ha:SetWidth(hpW); ha:SetHeight(hpH)
            end
            PushRange(ha, maxHealth, maxPlain)
            ha:SetValue(healAbsorbAmt)
            RFShow(ha)
            local hbg = ha._bg
            if hbg then RFShow(hbg) end
        end
    end

    -- Shield style off: hide the in-frame shield bars. Heal absorb paints earlier in this
    -- function so it's untouched either way; heal prediction and reduced max health both
    -- paint later, so only stop here if those are off too, or their blocks below never run.
    if not styleOn then
        RFHide(ab)
        if fw then RFHide(fw) end
        if fw and fw._edgeSpark then RFHide(fw._edgeSpark) end
        if fw and fw._bfSpark then RFHide(fw._bfSpark) end
        if not predOn and not maxHealthOn then return end
    end

    -- Bars track the health-bar size; size-gated (frame sizes are never secret, so it holds in combat).
    if ab._szW ~= hpW or ab._szH ~= hpH then
        ab._szW = hpW; ab._szH = hpH
        ab:SetWidth(hpW); ab:SetHeight(hpH)
        if fw then fw:SetWidth(hpW); fw:SetHeight(hpH) end
    end

    -- Shield absorb bar painting (ab/fw + the Default Blizz spark decoration below) is scoped to
    -- styleOn only -- with it off, execution still reaches this point (Heal Prediction/Max Health
    -- Style may need to run past here), but must not re-Show() the shield bars styleOn already
    -- asked to hide above.
    if styleOn then
    -- Settings-derived style + mode flags, gen-gated (see the Absorb Bar note).
    if ab._sGen ~= ns._absorbGen then
        ab._sGen = ns._absorbGen
        -- Re-apply style when style, color, or opacity changes
        local absStyle = s.absorbStyle
        local ac = s.absorbColor or { r = 1, g = 1, b = 1 }
        local acR, acG, acB = ac.r or 1, ac.g or 1, ac.b or 1
        local absKey = (absStyle or "") .. (s.absorbOpacity or 90) .. acR .. acG .. acB
        if absStyle and absStyle ~= "none" and ab._lastAbsKey ~= absKey then
            ab._lastAbsKey = absKey
            ApplyAbsorbStyle(ab, absStyle, s)
            -- Retexture REPLACES the fill objects: re-arm the modern base's one-time fill anchor
            -- and the glow anchors that can ride ab's fill (the gate, the overshield spark). The
            -- seam spark's target (the gate bar's texture) is creation-static and never re-arms.
            if fw and fw._modernBase then fw._modernBase._fillAnchored = nil end
            if fw and fw._edgeGate then fw._edgeGate._ge = nil end
            if fw and fw._bfSpark then fw._bfSpark._anc = nil end
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
        -- Forward bar on: Overlay, and Overlay Reverse (Full) for its excess (Default Blizz
        -- Frames keeps that placement as plain Overlay Reverse, see ReanchorAbsorbToFill).
        ab._edgeOverlay = (s.absorbEdgeMode or "overlay") == "overlay"
            or (s.absorbEdgeMode == "overlayReverseFull" and absStyle ~= "blizzardModern")
    end
    local absStyle = ab._absStyle
    local abValue = absorbAmt
    if not ab._overshieldOn and ab._overlayLike then abValue = 0 end

    -- Both bars get the raw absorb value and maxHealth; clip frames do the visual math, so no secret comparisons.
    PushRange(ab, maxHealth, maxPlain)
    ab:SetValue(abValue)
    RFShow(ab)

    if fw then
        PushRange(fw, maxHealth, maxPlain)
        fw:SetValue(absorbAmt)
        -- Edge modes (right/left): the full-bar backfill shows the whole absorb, so the
        -- overlay-only forward bar is not needed.
        if ab._edgeOverlay then RFShow(fw) else RFHide(fw) end
    end

    -- "Default Blizz Frames": backfill = 10% white overshield, forward = modern texture, whose
    -- solid base rides the forward fill (one-time anchor, re-armed by a retexture).
    if absStyle == "blizzardModern" and fw and not ab._axisVert then
        local fmb = fw._modernBase
        if fmb and not fmb._fillAnchored then
            fmb._fillAnchored = true
            fmb:SetAllPoints(fw:GetStatusBarTexture())
        end
    end

    -- Blizzard Glow Line (placements at the settings stamp above). The seam spark sits on its
    -- invisible gate bar, which self-gates on "has shield". Placements 1-2: the seam spark hides
    -- while overshielding and the overshield spark shows only then (1: the backfill's LEFT edge,
    -- or the health-bar RIGHT edge with Show Overshield off; 2: the from-left overshield's RIGHT
    -- edge) -- isClamped (the Missing-Health-clamp overshield boolean) flips between them
    -- secret-safely, so exactly one is visible. Placements 3 and 5: the gate moves to the
    -- shield's inner edge, one spark; 5 shows it only while isClamped. Anchors move only when
    -- the placement changes or a retexture re-arms them; sizes are size-gated.
    if glowOn and fw then
        local ge = ab._glowEdge or 1
        local g, sp = fw._edgeGate, fw._edgeSpark
        if g and sp then
            if g._szH ~= hpH then g._szH = hpH; g:SetHeight(hpH) end
            if g._ge ~= ge then
                g._ge = ge
                g:ClearAllPoints()
                if ge >= 3 then
                    g:SetPoint("CENTER", ab:GetStatusBarTexture(), "LEFT", -1, 0)
                else
                    g:SetPoint("CENTER", fw, "LEFT", -1, 0)
                end
                if ge == 3 then sp:SetAlpha(1) end
            end
            g:SetValue(absorbAmt)
            if not sp._fillAnchored then
                sp._fillAnchored = true
                sp:SetAllPoints(g:GetStatusBarTexture())
            end
            if ge <= 2 then
                if sp.SetAlphaFromBoolean then sp:SetAlphaFromBoolean(isClamped, 0, 1) else sp:SetAlpha(1) end
            elseif ge == 5 then
                if sp.SetAlphaFromBoolean then sp:SetAlphaFromBoolean(isClamped, 1, 0) else sp:SetAlpha(0) end
            end
            RFShow(sp)
        end
        local bsp = fw._bfSpark
        if bsp then
            if ge <= 2 then
                if bsp._szH ~= hpH then bsp._szH = hpH; bsp:SetSize(16, hpH) end
                -- 0 = health-bar RIGHT (Show Overshield off), 1 = backfill LEFT, 2 = backfill RIGHT.
                local anc = ab._overshieldOn and ge or 0
                if bsp._anc ~= anc then
                    bsp._anc = anc
                    bsp:ClearAllPoints()
                    if anc == 1 then
                        bsp:SetPoint("CENTER", ab:GetStatusBarTexture(), "LEFT", -1, 0)
                    elseif anc == 2 then
                        bsp:SetPoint("CENTER", ab:GetStatusBarTexture(), "RIGHT", 1, 0)
                    else
                        bsp:SetPoint("CENTER", ab, "RIGHT", -1, 0)
                    end
                end
                if bsp.SetAlphaFromBoolean then bsp:SetAlphaFromBoolean(isClamped, 1, 0) else bsp:SetAlpha(0) end
                RFShow(bsp)
            else
                RFHide(bsp)
            end
        end
    elseif fw and fw._edgeSpark then
        RFHide(fw._edgeSpark)
        if fw._bfSpark then RFHide(fw._bfSpark) end
    end
    end -- styleOn

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
            RFHide(hpd)
        else
            if hpd._szW ~= hpW or hpd._szH ~= hpH then
                hpd._szW = hpW; hpd._szH = hpH
                hpd:SetWidth(hpW); hpd:SetHeight(hpH)
            end
            PushRange(hpd, maxHealth, maxPlain)
            hpd:SetValue(incomingHeals)
            RFShow(hpd)
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
        -- Loss percent is cached per occupant: it moves only on
        -- UNIT_MAX_HEALTH_MODIFIERS_CHANGED (both dispatchers clear the stamp
        -- there), on occupant change (the assignment hook's full path) and on
        -- a full paint (UpdateButton clears it) -- never on an absorb tick.
        local lossPct = d._rmhPct
        if lossPct == nil then
            lossPct = GetUnitTotalModifiedMaxHealthPercent and GetUnitTotalModifiedMaxHealthPercent(unit) or 0
            d._rmhPct = lossPct
        end
        if not rmh._styleNone and lossPct > 0 then
            if rmh._rv ~= lossPct then rmh._rv = lossPct; rmh:SetValue(lossPct) end
            RFShow(rmh)
        else
            RFHide(rmh)
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
    local now = GetTime()
    for button in pairs(dirty) do
        dirty[button] = nil
        -- The button's CURRENT occupant, never the token captured at mark
        -- time: a header reassignment between mark and flush would paint the
        -- old occupant's absorb onto the new one.
        local unit = button:GetAttribute("unit")
        if unit then UpdateAbsorb(button, unit, now) end
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

-- Grid placement for debuff icons. opts (optional) overrides pos/grow/ox/oy/size for a
-- sub-group (e.g. dispellable debuffs on their own anchor); spacing/wrap/perRow stay shared.
function ns.DebuffGridPoint(s, idx0, total, opts)
    local pos    = (opts and opts.pos)  or s.debuffPosition or "bottomleft"
    local grow   = (opts and opts.grow) or s.debuffGrowDirection or "RIGHT"
    local sz     = PixelSnap((opts and opts.size) or s.debuffSize or 18)
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

-- Hover/target highlight on a BORDERLESS frame (Border Size 0): the highlight recolors the
-- frame's own border, and with none drawn there is nothing to recolor, so it draws its own at
-- hoverBorderSize/targetBorderSize in the configured border style. `size` nil/0 = not
-- highlighted. `px` = that size's exact pixels (EllesmereUI.BorderPx of the hover/target
-- companion key against `size` and the drawn texture), nil = the legacy size. The drawn size
-- (and px) is cached on the border frame so a group-wide target swap is a color write per
-- button rather than a restyle; callers clear it when the base border returns.
function ns.ApplyHighlightBorder(bf, s, size, r, g, b, a, px)
    if not (PP and bf) then return end
    local texKey = s.borderTexture or "solid"
    if not size or size <= 0 then
        if bf._hlBorderSize then
            EllesmereUI.ApplyBorderStyle(bf, 0, r, g, b, a, texKey)
            -- Keep the cache when the style call bailed (still shown) so the next one retries the hide.
            if not bf:IsShown() then bf._hlBorderSize = nil end
        end
        return
    end
    -- IsShown: a base restyle to Border Size 0 hides the frame without clearing the cache,
    -- so the size alone would let a hover/target repaint after one land on a hidden border.
    if bf._hlBorderSize == size and bf._hlBorderPx == px and bf:IsShown() then
        EllesmereUI.SetBorderStyleColor(bf, r, g, b, a)
        return
    end
    EllesmereUI.ApplyBorderStyle(bf, size, r, g, b, a, texKey,
        s.borderTextureOffset, s.borderTextureOffsetY,
        s.borderTextureShiftX, s.borderTextureShiftY, "unitframes", size, nil, px)
    bf._hlBorderSize = size
    bf._hlBorderPx = px
end

-- Hover/target on a drawn border recolors that same border, so a highlight
-- color (nearly) equal to the border's own shows no change at all: every
-- textured style but Pixels seeds a white border and the highlight defaults
-- to white. Such a highlight draws gold instead (white on a gold border).
function ns.RF_VisibleHighlight(s, r, g, b)
    local c = s.borderColor
    local br, bg, bb = 0, 0, 0
    if c then br, bg, bb = c.r, c.g, c.b end
    if math.abs(r - br) + math.abs(g - bg) + math.abs(b - bb) >= 0.15 then return r, g, b end
    if math.abs(1 - br) + math.abs(0.82 - bg) + math.abs(bb) >= 0.15 then return 1, 0.82, 0 end
    return 1, 1, 1
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
    -- Fill axis + inversion. StyleButton runs before d._isParty is set, so these use
    -- the raid values; ReanchorAbsorbToFill re-resolves both against the button's real
    -- settings source each update.
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

    -- Party Frames kit (the stock portrait party frame, latched): built here,
    -- before every anchor closure below and before the aura containers, so
    -- each of them takes the kit's host and spots from its first call.
    if d._isParty and ns.RF_PartyKit() then
        ns.RF_KitBuild(button, d, health, d.power, bdrFrame)
    end

    -- Text carrier: name + health text in the text band (ns.LVL_TEXT) -- above every border incl. the raise, below the aura band.
    local textCarrier = CreateFrame("Frame", nil, button)
    textCarrier:SetAllPoints(health)
    textCarrier:SetFrameLevel(button:GetFrameLevel() + ns.LVL_TEXT)
    -- Kept for Power Text, whose FontString is built on it only when a mode first needs it.
    d.textCarrier = textCarrier

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
        local health = ns.RF_BarHost(health, s)   -- Uniform Icon Anchoring host swap / kit bar
        healthFS:ClearAllPoints()
        local pos = s.healthTextPosition or "center"
        local ox = s.healthTextOffsetX or 0
        local oy = s.healthTextOffsetY or 0
        healthFS:SetWidth(d.kitG and d.kitG.health.w or (s.frameWidth or 72) * 0.75)
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
        local health = ns.RF_BarHost(health, s)   -- Uniform Icon Anchoring host swap / kit bar
        ns.AnchorRFText(healAbsorbFS, health, s.healAbsorbTextPosition or "center",
            s.healAbsorbTextOffsetX or 0, s.healAbsorbTextOffsetY or 0,
            d.kitG and d.kitG.health.w or (s.frameWidth or 72) * 0.75)
    end
    AnchorHealAbsorbText()
    d.AnchorHealAbsorbText = AnchorHealAbsorbText

    -- Status text (DEAD / OFFLINE / AFK -- always shown, own position/size/color).
    -- Party Frames kit: in the text band, so the Classic art (drawn over the
    -- bars) never covers it; it still anchors to the kit health bar.
    local statusFS = (d.kit and textCarrier or health):CreateFontString(nil, "OVERLAY")
    local stc = s.statusTextColor or { r = 1, g = 1, b = 1 }
    ApplyFont(statusFS, s.statusTextSize or 14)
    statusFS:SetJustifyH("CENTER")
    statusFS:SetTextColor(stc.r, stc.g, stc.b)
    statusFS:Hide()
    d.statusText = statusFS

    local function AnchorStatusText()
        local s = LiveS()   -- party/extra-aware (see LiveS note above)
        local health = ns.RF_BarHost(health, s)   -- Uniform Icon Anchoring host swap / kit bar
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
        -- Party Frames kit: the stock spot plus the user's offsets.
        if d.kitG then
            ns.RF_KitSpot(d.kitG.role, roleIcon, button, s.roleIconOffsetX, s.roleIconOffsetY)
            return
        end
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
    -- Party Frames kit: the stock spot (re-seated by the party reload pass).
    if d.kitG then ns.RF_KitLeader(d, LiveS()) end

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
        -- Party Frames kit: centred on the portrait, as stock.
        if d.kitG and d.kitPortrait then
            ns.RF_KitSpot(d.kitG.rc, readyCheck, d.kitPortrait, ox, oy)
            return
        end
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
        -- Party Frames kit: the stock name spot and width plus the user's
        -- offsets ("None" still hides it; the kit has no Top Name Bar).
        local g = d.kitG
        if g then
            if pos == "none" then nameFS:Hide(); return end
            nameFS:Show()
            nameFS:SetWidth(g.name.w)
            nameFS:SetHeight(0)
            ns.RF_KitSpot(g.name, nameFS, button, s.nameOffsetX, s.nameOffsetY)
            nameFS:SetJustifyH("LEFT"); nameFS:SetJustifyV(g.name.jv)
            local txt = nameFS:GetText()
            nameFS:SetText("")
            nameFS:SetText(txt or "")
            return
        end
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

    -- Raise the border above neighbors while hovered/targeted (or recolored for aggro): buttons share a frame level, so with
    -- small/negative Frame Spacing a neighbor's border would cover this frame's highlight.
    -- Highlight states bump it up, normal restores the base level. The PP container's level is
    -- fixed at creation, so it must be moved explicitly (borderFrame alone won't move it).
    local function ApplyBorderLevel(raised, s)
        if not (PP and d.borderFrame) then return end
        local pl = button:GetFrameLevel()
        -- Under a stock style the EllesmereUI border is stood down, so Show
        -- Behind has nothing to lower (the hover border must stay on top).
        -- Resolved LIVE like UpdateBorder (the caller passes its own LiveS()), so a
        -- party that keeps its own Show Behind (and the Color Custom Borders copy that
        -- follows it) stays in step.
        s = s or LiveS()
        local lvl = (s.borderBehind and not d.stockEdge and not d.kit) and math.max(0, pl - 1)
            or (pl + (raised and ns.LVL_RAISE or 8))
        -- Runs on hover/target transitions and restyles: skip the SetFrameLevel calls unless
        -- the level actually changes -- the common case is two getters.
        local container = PP.GetBorders(d.borderFrame)
        if d.borderFrame:GetFrameLevel() == lvl
           and (not container or container:GetFrameLevel() == lvl + 1) then
            return
        end
        d.borderFrame:SetFrameLevel(lvl)
        if container then container:SetFrameLevel(lvl + 1) end
        -- A textured style draws on a backdrop child levelled only at style time: carry
        -- it too, so the raise also clears the Color Custom Borders copies (base + 1).
        local bd = EllesmereUI._bdBorderData and EllesmereUI._bdBorderData[d.borderFrame]
        if bd then bd:SetFrameLevel(lvl) end
    end

    -- Recolor the single border for the current state: hover > target > aggro (Threat
    -- Borders' Color Custom Borders, flagged by ns.RF_PaintThreat) > normal. A borderless
    -- frame has nothing to recolor, so the highlight draws its own (ns.ApplyHighlightBorder).
    local function ApplyBorderColor()
        if not (PP and d.borderFrame) then return end
        -- Re-called long after StyleButton: resolve LIVE (see LiveS note) so party overrides and profile swaps are honored.
        local s = LiveS()
        -- Party Frames kit: hover and target glow along the frame art.
        if d.kit then
            ApplyBorderLevel(false, s)
            ns.RF_KitHighlight(d, d.borderFrame, s, d._hovered and s.hoverBorderEnabled ~= false,
                d._isTarget and s.targetBorderEnabled ~= false)
            return
        end
        -- Stock styles: the stock selection ring for the target, the hover
        -- border on the stood-down border frame.
        if d.stockEdge then
            local hover = d._hovered and s.hoverBorderEnabled ~= false
            ApplyBorderLevel(hover, s)
            ns.RF_StockHighlight(d, d.borderFrame, s, hover, d._isTarget and s.targetBorderEnabled ~= false)
            return
        end
        local r, g, b, a
        local raised, hlSize, hlPx = false, nil, nil
        if d._hovered and s.hoverBorderEnabled ~= false then
            local c = s.hoverBorderColor or { r = 1, g = 1, b = 1 }
            r, g, b, a = c.r, c.g, c.b, s.hoverBorderAlpha or 1
            raised, hlSize = true, s.hoverBorderSize or 1
            hlPx = EllesmereUI.BorderPx(s.hoverBorderSizePx, hlSize, s.borderTexture or "solid")
        elseif d._isTarget and s.targetBorderEnabled ~= false then
            local c = s.targetBorderColor or { r = 1, g = 1, b = 1 }
            r, g, b, a = c.r, c.g, c.b, s.targetBorderAlpha or 1
            raised, hlSize = true, s.targetBorderSize or 1
            hlPx = EllesmereUI.BorderPx(s.targetBorderSizePx, hlSize, s.borderTexture or "solid")
        elseif d._aggroBdr and s.threatCustomBorder == true and ns.RF_CustomBorderOn(s) then
            -- The threat color, raised like hover/target so it also covers the dispel
            -- Color Custom Borders copies (base + 9). Settings re-checked live: a
            -- restyle can run before the next threat paint clears the flag.
            r, g, b, a = 1, 0, 0, 1
            raised = true
        else
            local c = s.borderColor or { r = 0, g = 0, b = 0 }
            r, g, b, a = c.r, c.g, c.b, s.borderAlpha or 1
        end
        ApplyBorderLevel(raised, s)
        if (s.borderSize or 1) <= 0 then
            ns.ApplyHighlightBorder(d.borderFrame, s, hlSize, r, g, b, a, hlPx)
            return
        end
        if hlSize then r, g, b = ns.RF_VisibleHighlight(s, r, g, b) end
        d.borderFrame._hlBorderSize = nil
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
        -- Stock styles: the EllesmereUI border stands down for the stock edge
        -- (for the art under the Party Frames kit).
        if d.kit then
            d.borderFrame:SetFrameLevel(pl + 8)
            EllesmereUI.ApplyBorderStyle(d.borderFrame, 0, 0, 0, 0, 0, "solid")
            d.borderFrame._hlBorderSize = nil
            ApplyBorderColor()
            return
        end
        if d.stockEdge then
            d.borderFrame:SetFrameLevel(pl + 8)
            EllesmereUI.ApplyBorderStyle(d.borderFrame, 0, 0, 0, 0, 0, "solid")
            d.borderFrame._hlBorderSize = nil
            ns.RF_StockSeat(d)
            ApplyBorderColor()
            return
        end
        d.borderFrame:SetFrameLevel(s.borderBehind and math.max(0, pl - 1) or (pl + 8))
        EllesmereUI.ApplyBorderStyle(d.borderFrame, bs, bc.r, bc.g, bc.b, s.borderAlpha or 1,
            texKey, s.borderTextureOffset, s.borderTextureOffsetY,
            s.borderTextureShiftX, s.borderTextureShiftY, "unitframes", bs, nil,
            EllesmereUI.BorderPx(s.borderSizePx, bs, texKey))
        ApplyBorderColor()
    end
    if ns.RF_Stock() and not d.kit then ns.RF_StockBuild(button, d, d.power) end
    UpdateBorder()
    d.UpdateBorder = UpdateBorder

    -- Apply power border
    local function UpdatePowerBorder()
        -- Party Frames kit: the mana bar sits in the art's own track.
        if d.kit then
            if d.powerBorderFrame then d.powerBorderFrame:Hide() end
            return
        end
        -- No-op while the power bar is hidden: the border frame always exists and unconditional
        -- callers must not draw over a hidden bar. UpdateButton calls this AFTER power:Show().
        if not PP or not d.powerBorderFrame or (d.power and not d.power:IsShown()) then return end
        -- Classic WoW UI: the stock health/power divider in place of the power border.
        if d.stockDiv then
            d.powerBorderFrame:Hide()
            ns.RF_StockDivider(d)
            return
        end
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
        local foci = GetMouseFoci()
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
            -- A set flagged hidden stays out of the maps: its headers can still
            -- re-process until the visibility driver hides them (the next tick), and
            -- a hidden button would win the routing over the set actually shown.
            if d._isExtra then
                -- map owned by XF_Apply
            elseif d._isParty then
                if ns._partyFramesVisible then ns._partyUnitToButton[u] = self end
            elseif ns._raidFramesVisible then unitToButton[u] = self end
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
            d._rmhPct = nil
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
            -- Party Frames kit / party portrait: the new occupant's portrait
            -- (ahead of the legacy refresh for the same reason as the containers).
            if d.kitPortrait or d.pt then ns.RF_PtPaint(d, u, "UnitChanged") end
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
    -- Party buttons take the party box (their creator stamps _isParty
    -- first); everything else the raid size.
    if d._isParty then
        local pw, ph = ns.RF_PartyDims(s)
        button:SetSize(PixelSnap(pw), PixelSnap(ph))
    else
        button:SetSize(PixelSnap(s.frameWidth or 72), PixelSnap(s.frameHeight or 46))
    end

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
    if not issecretvalue(isLeader) and isLeader then
        leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        leaderIcon:SetTexCoord(0, 1, 0, 1)
        leaderIcon:Show()
    elseif not issecretvalue(isAssist) and isAssist then
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
            local cc = (classToken and EllesmereUI.GetClassColor(classToken)) or { r = 1, g = 1, b = 1 }
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
        local pd = GetFFD(button)
        if pd.pt and pd.pt._3dOn then ns.RF_PtModelAlpha(pd, 0) end
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
        if d.pt and d.pt._3dOn then ns.RF_PtModelAlpha(d, baseA * d.rangeAlpha) end
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
        -- Inverted Fill (the bar's _euiInv stamp) paints missing health for every
        -- unit, so the current-health area the Health Bar Color tints and the dispel
        -- wash cover (ns.RF_AnchorCurHealth) is the unit's own, last-known while
        -- offline. A corpse paints a full missing bar, the empty current-health area
        -- of a normal bar at 0%; _ApplyHealthBg hides that fill over the Dead colour.
        local pct
        if health._euiInv then
            pct = deadOrGhost and 100 or GetSafeHealthPercent(unit, true)
        else
            pct = GetSafeHealthPercent(unit)
        end
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

    -- Absorb (full paint: re-read the reduced-max percent too)
    d._rmhPct = nil
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

        -- Party Frames kit: the mana bar is part of the stock frame and always
        -- shows (an empty track reads as no mana); the kit owns the bar rects.
        if d.kit then d._appliedHidePower = false; hidePower = false end

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
                    if d._pwtMode then d.powerText:Hide(); d._pwtMode = nil end
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
            -- Power Text: shown/hidden (built on first need) by mode ahead of the edge below,
            -- which colours it. None and never shown = two field reads, no call.
            if d._pwtMode or s.powerTextMode ~= "none" then ns._RFPowerTextSetup(d, s) end
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
            -- Power Text rides the same value; clearing the dead/offline stamp makes the next
            -- health tick re-check a possibly new occupant.
            local pwtMode = d._pwtMode
            if pwtMode then
                d._pwtGone = nil
                ns.RF_PowerTextInto(d.powerText, pwtMode, ppct, unit, pType)
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
    -- Level Position "Attach to Name" (either format) puts the level in front of the name,
    -- in both name texts.
    local lvlPos = s.levelTextPosition or ns.RF_LEVEL_DEFAULT
    local lvlAttach = ns.RF_LEVEL_ATTACH[lvlPos]
    if d.nameText then
        if lvlAttach then
            ns._RFNameWithLevel(d.nameText, ResolveDisplayName(unit, true, s), unit, lvlAttach)
        else
            d.nameText:SetText(ResolveDisplayName(unit, true, s))
        end
        local nr, ng, nb = GetNameColor(unit, s)
        d.nameText:SetTextColor(nr, ng, nb)
    end

    -- Level Text on its own spot, in the name's colour. None or attached, never shown = no call.
    if d._lvlOn or (lvlPos ~= "none" and not lvlAttach) then
        ns._RFLevelText(d, s, unit, GetNameColor(unit, s))
    end

    -- Top Name Bar text (unit name + class/custom color); size/anchor/visibility are LayoutTopNameBar's.
    if d.topNameBarText and s.topNameBarEnabled then
        if lvlAttach then
            ns._RFNameWithLevel(d.topNameBarText, ResolveDisplayName(unit, false, s), unit, lvlAttach)
        else
            d.topNameBarText:SetText(ResolveDisplayName(unit, false, s))
        end
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
        local newTarget = (not issecretvalue(isTarget) and isTarget) and true or false
        if newTarget ~= d._isTarget then
            d._isTarget = newTarget
            if d.ApplyBorderColor then d.ApplyBorderColor() end
        end
    end

    -- Threat highlight (aggro): the inner border (size 0 = off) or the Color Custom Borders recolor
    ns.RF_PaintThreat(d, s, unit)
end

-- UNIT_LEVEL: only the level repaints -- in front of the name (both name texts)
-- or on its own spot, colours untouched; a button whose view shows no level is
-- left alone. On ns (200-local cap).
ns._RFRepaintLevel = function(button)
    local unit = button:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end
    local d = GetFFD(button)
    if not d.styled then return end
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    local lvlAttach = ns.RF_LEVEL_ATTACH[s.levelTextPosition or ns.RF_LEVEL_DEFAULT]
    if lvlAttach then
        if d.nameText then
            ns._RFNameWithLevel(d.nameText, ResolveDisplayName(unit, true, s), unit, lvlAttach)
        end
        if d.topNameBarText and s.topNameBarEnabled then
            ns._RFNameWithLevel(d.topNameBarText, ResolveDisplayName(unit, false, s), unit, lvlAttach)
        end
    elseif d._lvlOn then
        ns._RFLevelInto(d.levelText, unit)
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
-- Public accessor: unitToButton/ns._partyUnitToButton stay private otherwise (every
-- other reader in this file is a raid-frame-internal event handler), but another
-- addon in the suite (NaowhUI_SmartReminders' raid-frame glow reminder) needs a way
-- to find the actual button for a unit without reaching into this file's own locals.
-- Same combined-lookup shape every internal reader already uses.
function EllesmereUI.RaidFrames_GetFrameForUnit(unit)
    if not unit then return nil end
    return unitToButton[unit] or ns._partyUnitToButton[unit]
end

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
            for u, btn in pairs(ns._partyUnitToButton) do
                ns._UpdateButtonHealth(btn)
                -- Power Text's accent/power colour moves with these pushes too (raid and extra
                -- buttons take it from the full paint above): one field read while it is off.
                local pd = GetFFD(btn)
                if pd._pwtMode then ns._RFPowerTextColor(pd, u, ns._scaledPartyProxy, GetPowerColor(u)) end
            end
        end
        if ns._xfUnitToButton then
            for _, btn in pairs(ns._xfUnitToButton) do ns._UpdateButtonHealth(btn) end
        end
    end
    -- Boss and pet frames paint through their own painter (names and their colours included).
    local FB = ns._FB
    for _, btn in ipairs(FB.buttons) do
        if btn:IsVisible() then FB.Update(btn) end
    end
    ns._PF_RefreshVisible()
    -- Party target frames: their fill and background read the Dark Mode and class palettes too.
    ns._PT_RepaintVisible()
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
        d._isTarget = (not issecretvalue(isTarget) and isTarget) and true or false
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
    -- Dispatchers pass the event's unit token (a unit that just fired an event
    -- exists -- no probe); rare callers omit it and pay the existence check.
    if not unit then
        unit = button:GetAttribute("unit")
        if not unit or not UnitExists(unit) then return end
    end
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
        -- Missing health under Inverted Fill, every unit (see UpdateButton).
        local barPct = pct
        if health._euiInv then
            barPct = deadOrGhost and 100 or GetSafeHealthPercent(unit, true)
        end
        if smooth then
            health:SetValue(barPct, smooth)
        else
            health:SetValue(barPct)
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

    -- Power Text blanks and refills on the same dead/offline edge (death and resurrection need
    -- not move a power value): one field read while it is off.
    if d._pwtMode then ns._RFPowerTextLife(d, unit, deadOrGhost or not connected) end

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

-- Settings source per button for the other groups these helpers style (the pet frames beside the
-- party frames read the party settings). Unregistered buttons, the boss group's own among them,
-- read the raid settings.
FB.src = setmetatable({}, { __mode = "k" })
FB.Source = function(b)
    local get = FB.src[b]
    return (get and get()) or ns._scaledProfile or db.profile
end

-- Target store: true while a button shows your target, read by the border painter. Re-read by the
-- full paint and on target changes, so a target change repaints only the buttons that flipped.
-- UnitIsUnit can be secret: read as not targeted. Returns true when the button's state flipped.
FB.tgt = setmetatable({}, { __mode = "k" })
FB.ReadTarget = function(b, unit)
    local t = unit and UnitIsUnit(unit, "target")
    if issecretvalue(t) then t = false end
    t = t and true or nil
    if FB.tgt[b] == t then return false end
    FB.tgt[b] = t
    return true
end

-- Hover store: true while the mouse is over a button, read by the border painter.
FB.hov = setmetatable({}, { __mode = "k" })

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

-- WoW Forever: the class's best heal the spellbook holds (EllesmereUI.FOREVER_HEAL_SPELLS, best
-- first); nil when the class has none or has not learned one yet.
FB.ForeverKnownHeal = function(pClass)
    local list = EllesmereUI.FOREVER_HEAL_SPELLS[pClass]
    if not list then return nil end
    local bank = C_SpellBook and C_SpellBook.IsSpellInSpellBook and Enum.SpellBookSpellBank
    for i = 1, #list do
        local id = list[i]
        local known
        if bank then
            known = C_SpellBook.IsSpellInSpellBook(id, bank.Player, true)
        else
            known = IsSpellKnown and IsSpellKnown(id)
        end
        if known then return id end
    end
    return nil
end

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
        -- WoW Forever: a class that can heal counts as its healing spec.
        if EllesmereUI.IS_FOREVER then
            local _, pClass = UnitClass("player")
            return EllesmereUI.FOREVER_HEAL_SPELLS[pClass] ~= nil
        end
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
-- hover (raised) > target (raised) > normal, using the button's border settings (FB.Source: the raid
-- ones for the boss group) -- nothing separate.
FB.ApplyBorderColor = function(b)
    if not PP or not b._borderFrame or not db then return end
    local s = FB.Source(b)
    local targeted = FB.tgt[b] and s.targetBorderEnabled ~= false
    if b.stockEdge then
        local hover = FB.hov[b] and s.hoverBorderEnabled ~= false
        local lvl = b:GetFrameLevel() + (hover and ns.LVL_RAISE or 8)
        if b._borderFrame:GetFrameLevel() ~= lvl then
            b._borderFrame:SetFrameLevel(lvl)
            local container = PP.GetBorders(b._borderFrame)
            if container then container:SetFrameLevel(lvl + 1) end
        end
        ns.RF_StockHighlight(b, b._borderFrame, s, hover, targeted)
        return
    end
    local r, g, bcol, a
    local raised, hlSize, hlPx = false, nil, nil
    if FB.hov[b] and s.hoverBorderEnabled ~= false then
        local c = s.hoverBorderColor or { r = 1, g = 1, b = 1 }
        r, g, bcol, a = c.r, c.g, c.b, s.hoverBorderAlpha or 1
        raised, hlSize = true, s.hoverBorderSize or 1
        hlPx = EllesmereUI.BorderPx(s.hoverBorderSizePx, hlSize, s.borderTexture or "solid")
    elseif targeted then
        local c = s.targetBorderColor or { r = 1, g = 1, b = 1 }
        r, g, bcol, a = c.r, c.g, c.b, s.targetBorderAlpha or 1
        raised, hlSize = true, s.targetBorderSize or 1
        hlPx = EllesmereUI.BorderPx(s.targetBorderSizePx, hlSize, s.borderTexture or "solid")
    else
        local c = s.borderColor or { r = 0, g = 0, b = 0 }
        r, g, bcol, a = c.r, c.g, c.b, s.borderAlpha or 1
    end
    -- Raise above neighbors while highlighted (as the raid buttons: overlapping frames would cover it).
    local pl = b:GetFrameLevel()
    local lvl = s.borderBehind and math.max(0, pl - 1) or (pl + (raised and ns.LVL_RAISE or 8))
    -- The container too, like ApplyBorderLevel: FB.StyleBorder moves only the border
    -- frame, so a Show Behind flip would otherwise leave the strips on the old level.
    local container = PP.GetBorders(b._borderFrame)
    if b._borderFrame:GetFrameLevel() ~= lvl
       or (container and container:GetFrameLevel() ~= lvl + 1) then
        b._borderFrame:SetFrameLevel(lvl)
        if container then container:SetFrameLevel(lvl + 1) end
        -- Textured styles: the backdrop child too (see ApplyBorderLevel).
        local bd = EllesmereUI._bdBorderData and EllesmereUI._bdBorderData[b._borderFrame]
        if bd then bd:SetFrameLevel(lvl) end
    end
    if (s.borderSize or 1) <= 0 then
        ns.ApplyHighlightBorder(b._borderFrame, s, hlSize, r, g, bcol, a, hlPx)
        return
    end
    if hlSize then r, g, bcol = ns.RF_VisibleHighlight(s, r, g, bcol) end
    b._borderFrame._hlBorderSize = nil
    EllesmereUI.SetBorderStyleColor(b._borderFrame, r, g, bcol, a)
end

-- Apply the border style (size/color/texture/offsets) to one button, from its FB.Source.
FB.StyleBorder = function(b)
    if not PP or not b._borderFrame then return end
    local s = FB.Source(b)
    local bs = s.borderSize or 1
    local bc = s.borderColor or { r = 0, g = 0, b = 0 }
    local pl = b:GetFrameLevel()
    if b.stockEdge then
        b._borderFrame:SetFrameLevel(pl + 8)
        EllesmereUI.ApplyBorderStyle(b._borderFrame, 0, 0, 0, 0, 0, "solid")
        b._borderFrame._hlBorderSize = nil
        ns.RF_StockSeat(b)
        FB.ApplyBorderColor(b)
        return
    end
    b._borderFrame:SetFrameLevel(s.borderBehind and math.max(0, pl - 1) or (pl + 8))
    EllesmereUI.ApplyBorderStyle(b._borderFrame, bs, bc.r, bc.g, bc.b, s.borderAlpha or 1,
        s.borderTexture or "solid", s.borderTextureOffset, s.borderTextureOffsetY,
        s.borderTextureShiftX, s.borderTextureShiftY, "unitframes", bs, nil,
        EllesmereUI.BorderPx(s.borderSizePx, bs, s.borderTexture or "solid"))
    FB.ApplyBorderColor(b)
end

-- Bar colour: the owner's own colour setting (default #17AC31). The raid color modes mislead here:
-- gradient modes read as damage states, and many NPCs carry real class tokens (a friendly add can
-- come out yellow).
FB.PaintBarColor = function(b, owner, s)
    local health = b._health
    local fbc = (owner.ColorSettings or owner.Settings)()
    fbc = fbc and fbc.healthColor
    local fillTex = health:GetStatusBarTexture()
    if fillTex then fillTex:SetAlpha(1) end
    health:SetStatusBarColor(fbc and fbc.r or 23/255, fbc and fbc.g or 172/255,
        fbc and fbc.b or 49/255, (s.healthBarOpacity or 100) / 100)
end

FB.PaintName = function(b, unit, s)
    local fs = b._nameText
    if not fs then return end
    fs:SetText(ResolveDisplayName(unit, true, s))
    local nr, ng, nb = GetNameColor(unit, s)
    fs:SetTextColor(nr, ng, nb)
end

-- Health value, health text and heal absorb text. A text set to None is blank: the full paint (full)
-- clears it, and the health events after it skip it.
FB.PaintHealth = function(b, unit, s, full)
    local health = b._health
    local pct = GetSafeHealthPercent(unit)
    health:SetMinMaxValues(0, 100)
    local smooth = s.smoothBars and Enum and Enum.StatusBarInterpolation
        and Enum.StatusBarInterpolation.ExponentialEaseOut
    -- Missing health under Inverted Fill (the _euiInv stamp FB.StyleVisuals leaves);
    -- the texts keep the current-health pct. Dead units are not special-cased: there
    -- is no status colour here, so a full bar is what tells a dead unit apart.
    local barPct = pct
    if health._euiInv then barPct = GetSafeHealthPercent(unit, true) end
    if smooth then health:SetValue(barPct, smooth) else health:SetValue(barPct) end

    local ht, hat = b._healthText, b._healAbsorbText
    local mode = s.healthTextMode or "none"
    if ht and mode == "none" then
        if full then ht:SetText("") end
        ht = nil
    end
    if hat and (s.healAbsorbTextMode or "none") == "none" then
        if full then hat:SetText("") end
        hat = nil
    end
    if not (ht or hat) then return end
    local dead = UnitIsDeadOrGhost(unit)

    if ht then
        if dead then
            ht:SetText("")
        else
            ns.RF_HealthTextInto(ht, mode, pct, unit)
        end
        local htr, htg, htb = GetHealthTextColor(unit, s)
        ht:SetTextColor(htr, htg, htb, 0.9)
    end

    if hat then
        if dead then hat:SetText("")
        else ns.SetHealAbsorbText(hat, unit, s) end
    end
end

-- Refresh one boss button: health value/color, health text, name text, target state and border.
-- Mirrors the corresponding slices of UpdateButton/_UpdateButtonHealth; boss units are not group
-- units, so no roster paths. Returns true when it painted (border included); without a unit only a
-- flipped target state repaints the border.
FB.Update = function(b, owner)
    local unit = FB.UnitOf(b)
    local flipped = FB.ReadTarget(b, unit)
    if not db or not UnitExists(unit) then
        if flipped then FB.ApplyBorderColor(b) end
        return
    end
    local s = FB.Source(b)
    FB.PaintBarColor(b, owner or FB, s)
    FB.PaintName(b, unit, s)
    FB.PaintHealth(b, unit, s, true)
    FB.ApplyBorderColor(b)
    return true
end

-- Background, health bar, the three texts and the border frame of one button, kept on the button
-- itself with the stock styles' edge and highlight state. Shared with the pet frames and their
-- preview. The pet header's buttons are made by the pet header, not by us: these keys on them are
-- the one known exception to keeping state off header buttons (the rest lives in weak tables and
-- GetFFD).
FB.BuildVisuals = function(b)
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
    -- Stock styles: the stock edge and highlights.
    if ns.RF_Stock() then ns.RF_StockBuild(b, b) end
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
        FB.BuildVisuals(b)

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
            FB.hov[self] = true
            FB.ApplyBorderColor(self)
        end)
        b:HookScript("OnLeave", function(self)
            FB.hov[self] = nil
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

        FB.StyleVisuals(b, s, w, h, texPath, bgc)
    end
end

-- The size-dependent part of FB.StyleVisuals (the health bar's height, the text widths): all a
-- resize of an already styled button needs.
FB.SizeVisuals = function(b, w, h)
    -- No power bar / top name bar here: health fills the button.
    b._health:SetHeight(h)
    b._nameText:SetWidth(w * ns.RF_NAME_WIDTH_FRACTION)
    b._healthText:SetWidth(w * 0.75)
    if b._healAbsorbText then b._healAbsorbText:SetWidth(w * 0.75) end
end

-- Texture, fonts, text anchors and border of one button at w x h. Shared with the pet frames.
FB.StyleVisuals = function(b, s, w, h, texPath, bgc)
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
    FB.SizeVisuals(b, w, h)

    ApplyFont(b._nameText, s.nameSize or 10)
    ApplyFont(b._healthText, s.healthTextSize or 9)
    b._nameText:SetHeight(0)
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
        b._healAbsorbText:SetHeight(0)
        FB.AnchorText(b._healAbsorbText, b._health, s.healAbsorbTextPosition or "center",
            s.healAbsorbTextOffsetX or 0, s.healAbsorbTextOffsetY or 0)
    end
    FB.StyleBorder(b)
end

-- A container's one anchor point, left alone when it already sits exactly there: the roster and
-- layout passes re-anchor with unchanged targets, and rewriting a protected frame's point re-lays
-- it and every button under it. A secret point always rewrites.
FB.Pin = function(c, point, rel, relPoint, x, y)
    if c:GetNumPoints() == 1 then
        local p, r, rp, px, py = c:GetPoint(1)
        if not (issecretvalue(p) or issecretvalue(r) or issecretvalue(rp)
                or issecretvalue(px) or issecretvalue(py))
           and p == point and r == rel and rp == relPoint and px == x and py == y then
            return
        end
    end
    c:ClearAllPoints()
    c:SetPoint(point, rel, relPoint, x, y)
end

-- Position the container per the position setting. The container inherits protection from its
-- secure children, so SetPoint is OOC-only. Owner-parameterized like ApplyStyle. Every placement
-- goes through FB.Pin (owner.FreeAnchor included).
FB.Anchor = function(owner)
    owner = owner or FB
    if not owner.built then return end
    if InCombatLockdown() then owner.anchorDirty = true; return end
    local s = db.profile
    local fb = owner.Settings()
    local c = owner.container

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
        -- Owners placed after other attached groups on the same side (the pet frames), which
        -- remember the group they followed (owner.chainTgt).
        if not anchorHdr and owner.ChainAnchor then
            anchorHdr = owner.ChainAnchor(fb)
            owner.chainTgt = anchorHdr or false
            -- Beside the party frames the chain runs on the party attach axis, not the raid growth,
            -- with the same kit side and clearance, and the corner the party stack grows from.
            if anchorHdr and owner.attachParty then
                local gap = s.groupSpacing or -1
                local before = (fb.position == "left")
                if ns.RF_PartyKit() then
                    local extra
                    before, extra = ns.RF_KitAttach(s, before)
                    gap = gap + extra
                end
                local grow = ns._PartyGrowth(s)
                if grow == "UP" then
                    if before then FB.Pin(c, "BOTTOMRIGHT", anchorHdr, "BOTTOMLEFT", -gap, 0)
                    else FB.Pin(c, "BOTTOMLEFT", anchorHdr, "BOTTOMRIGHT", gap, 0) end
                elseif grow == "LEFT" then
                    if before then FB.Pin(c, "BOTTOMRIGHT", anchorHdr, "TOPRIGHT", 0, gap)
                    else FB.Pin(c, "TOPRIGHT", anchorHdr, "BOTTOMRIGHT", 0, -gap) end
                elseif s.partyHorizontal then
                    if before then FB.Pin(c, "BOTTOMLEFT", anchorHdr, "TOPLEFT", 0, gap)
                    else FB.Pin(c, "TOPLEFT", anchorHdr, "BOTTOMLEFT", 0, -gap) end
                else
                    if before then FB.Pin(c, "TOPRIGHT", anchorHdr, "TOPLEFT", -gap, 0)
                    else FB.Pin(c, "TOPLEFT", anchorHdr, "TOPRIGHT", gap, 0) end
                end
                return
            end
        end
        -- Party/dungeon: every raid group header is hidden there, so the boss group slots in beside
        -- the party container as if it were the next group -- along the axis the party frames do NOT
        -- stack on, the way "before first / after last group" reads in a raid. Extra Frames is raid
        -- only and keeps the raid path. Party frames off screen leaves nothing to attach to: this
        -- branch anchors nothing and the free position below takes over.
        if not anchorHdr and (not IsInRaid() or ns._PartyInRaid())
           and ((owner == FB and fb.showInDungeons == true) or owner.attachParty) then
            local pc = ns._partyContainerFrame
            if pc and pc:IsShown() then
                local gap = s.groupSpacing or -1
                local before = (fb.position == "left")
                -- Party Frames kit: clear the auras it draws outside the frames.
                if ns.RF_PartyKit() then
                    local extra
                    before, extra = ns.RF_KitAttach(s, before)
                    gap = gap + extra
                end
                -- The group clears the party target frames on its side, and the boss group the
                -- Beside Owner pets there too (the pet header is down while those are up).
                gap = gap + ns.PT_Reserve(s.partyHorizontal, before,
                    (owner == FB) and ns.PF_OwnerReserve(s.partyHorizontal, before) or nil)
                -- Pets line up with the first party frame: Flip Frame Growth and Centered start
                -- the stack away from the container's top-left.
                if owner ~= FB then
                    local first = ns._partyFirstSlot or pc
                    local grow = ns._PartyGrowth(s)
                    if grow == "UP" then
                        if before then FB.Pin(c, "BOTTOMRIGHT", first, "BOTTOMLEFT", -gap, 0)
                        else FB.Pin(c, "BOTTOMLEFT", first, "BOTTOMRIGHT", gap, 0) end
                        return
                    elseif grow == "LEFT" then
                        if before then FB.Pin(c, "BOTTOMRIGHT", first, "TOPRIGHT", 0, gap)
                        else FB.Pin(c, "TOPRIGHT", first, "BOTTOMRIGHT", 0, -gap) end
                        return
                    end
                    pc = first
                end
                -- Party growth axis comes from partyHorizontal alone (_LayoutPartyFrames): the flip
                -- and "centered" variants only reverse it, and the container spans all five slots
                -- either way, so the perpendicular attach point is the same.
                if s.partyHorizontal then
                    if before then FB.Pin(c, "BOTTOMLEFT", pc, "TOPLEFT", 0, gap)
                    else FB.Pin(c, "TOPLEFT", pc, "BOTTOMLEFT", 0, -gap) end
                else
                    if before then FB.Pin(c, "TOPRIGHT", pc, "TOPLEFT", -gap, 0)
                    else FB.Pin(c, "TOPLEFT", pc, "TOPRIGHT", gap, 0) end
                end
                return
            end
        elseif not anchorHdr and s.mergeGroups then
            anchorHdr = ns._flatHeader
        elseif not anchorHdr then
            -- The boss group slots in before the first / after the last group that is BOTH enabled
            -- in Show Groups AND populated. With none populated (not in a raid yet), fall back to
            -- the Show Groups bounds alone.
            local vg = ns._VisibleGroups() or {}
            -- One reused set across calls (the roster edges anchor every group).
            local occupied = FB.occ
            if occupied then wipe(occupied) else occupied = {}; FB.occ = occupied end
            for ri = 1, GetNumGroupMembers() or 0 do
                local _, _, sub = GetRaidRosterInfo(ri)
                if sub then occupied[sub] = true end
            end
            local first, last
            local groupOrder = s.customGroupOrder and ns._RFValidatedGroupOrder(s.groupOrder)
            for slot = 1, 8 do
                local gi = groupOrder and groupOrder[slot] or slot
                if vg[gi] ~= false and separatedHdrs[gi] and occupied[gi] then
                    if not first then first = separatedHdrs[gi] end
                    last = separatedHdrs[gi]
                end
            end
            if not first then
                for slot = 1, 8 do
                    local gi = groupOrder and groupOrder[slot] or slot
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
            if grow == "RIGHT" or grow == "DOWNRIGHT" then
                -- The grid flow's last group also ends in the rightmost column,
                -- so it slots in along the same edge as a plain RIGHT run.
                if before then FB.Pin(c, "TOPRIGHT", anchorHdr, "TOPLEFT", -gap, 0)
                else FB.Pin(c, "TOPLEFT", anchorHdr, "TOPRIGHT", gap, 0) end
            elseif grow == "LEFT" then
                if before then FB.Pin(c, "TOPLEFT", anchorHdr, "TOPRIGHT", gap, 0)
                else FB.Pin(c, "TOPRIGHT", anchorHdr, "TOPLEFT", -gap, 0) end
            elseif grow == "DOWN" then
                if before then FB.Pin(c, "BOTTOMLEFT", anchorHdr, "TOPLEFT", 0, gap)
                else FB.Pin(c, "TOPLEFT", anchorHdr, "BOTTOMLEFT", 0, -gap) end
            else -- UP
                if before then FB.Pin(c, "TOPLEFT", anchorHdr, "BOTTOMLEFT", 0, -gap)
                else FB.Pin(c, "BOTTOMLEFT", anchorHdr, "TOPLEFT", 0, gap) end
            end
            return
        end
        -- No usable group header: fall through to the free position.
    end

    -- Owner-specific free anchoring (Extra Frames pins the grid's growth corner so the group grows away from it); CENTER pin otherwise.
    if owner.FreeAnchor and owner.FreeAnchor(c, fb) then return end
    local p = fb.freePos or {}
    FB.Pin(c, "CENTER", UIParent, "CENTER", p.x or 100, p.y or 0)
end

-- Re-anchor only (no restyle): the party visibility pass calls this on the party container's
-- show/hide edge, since attached positions hang off that container outside a raid. Gated on
-- the Show in Dungeons opt-in: with it off the party attach branch is inert, so the party
-- layout/visibility hooks skip the re-anchor entirely (zero added work for raid-only users).
function ns.FB_ReAnchor()
    ns.PF_PartyRelayout()
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
    -- WoW Forever: a healing class range-checks with its best known heal.
    if EllesmereUI.IS_FOREVER then FB.rangeSpell = FB.ForeverKnownHeal(pClass) end
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

-- Free Move corner pin (Extra Frames, Pet Frames): the corner a grid grows from (hDir, vDir: its
-- horizontal and vertical growth), so its first frame stays put as frames come and go, and with a
-- saved rect r (FB.SaveMoverRect) that corner's offset from UIParent's centre.
FB.CornerPin = function(hDir, vDir, r)
    local corner
    if vDir == "UP" then
        corner = (hDir == "LEFT") and "BOTTOMRIGHT" or "BOTTOMLEFT"
    else
        corner = (hDir == "LEFT") and "TOPRIGHT" or "TOPLEFT"
    end
    if not r then return corner end
    return corner, (hDir == "LEFT") and r.right or r.left, (vDir == "UP") and r.bottom or r.top
end

-- The shared mover's drag stop, for corner-pinned owners: the dropped rect, relative to UIParent's
-- centre, into set.freeRect.
FB.SaveMoverRect = function(mover, set)
    if not set then return end
    local ux, uy = UIParent:GetCenter()
    local l, b, mw, mh = mover:GetRect()
    if not (ux and l) then return end
    set.freeRect = { left = l - ux, right = l + mw - ux, bottom = b - uy, top = b + mh - uy }
end

-- Free Move drag overlay (unlock-mode look, TOOLTIP strata so it floats above the options panel).
-- Deliberately independent of unlock mode. Owner-parameterized: the Extra Frames and pet groups
-- build their own movers through this exact code with their own name/label (stored at owner.mover).
FB.SetMoverShown = function(owner, show, frameName, labelText)
    if not show then
        if owner.mover then owner.mover:Hide() end
        return
    end
    -- Owners whose overlay can place another context's spot (the pet frames' Party and Raid tabs)
    -- read the overlay's settings, and bring their live group up to date themselves.
    local moverSettings = owner.MoverSettings or owner.Settings
    local fb = moverSettings()
    if not fb or fb.position ~= "free" then return end
    if owner.MoverPrep then
        owner.MoverPrep()
    else
        owner.EnsureBuilt()
        -- Owners with their own geometry pass (Extra Frames) restyle through it; FB-built buttons use the FB styler.
        if owner.Layout then owner.Layout() else FB.ApplyStyle(owner) end
        FB.Anchor(owner)
    end

    if not owner.mover then
        local m = CreateFrame("Frame", frameName, UIParent)
        m:SetFrameStrata("TOOLTIP")
        m:SetClampedToScreen(true)
        m:SetMovable(true)
        m:EnableMouse(true)
        m:RegisterForDrag("LeftButton")
        local mbg = m:CreateTexture(nil, "BACKGROUND")
        mbg:SetAllPoints()
        mbg:SetColorTexture(0.103, 0.095, 0.088, 0.95)
        local ar, ag, ab = EllesmereUI.ResolveActiveAccent()
        EllesmereUI.MakeBorder(m, ar or 1, ag or 1, ab or 1, 0.6)
        local lbl = m:CreateFontString(nil, "OVERLAY")
        EllesmereUI.PrimeFontShadow(lbl, true)
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
                local set = (owner.MoverSettings or owner.Settings)()
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

    owner.mover:ClearAllPoints()
    local oset = moverSettings() or {}
    if owner.PlaceMover then
        owner.PlaceMover(owner.mover, oset)
    else
        owner.mover:SetSize(owner.container:GetWidth(), owner.container:GetHeight())
        if owner.FreeAnchor and oset.freeRect then
            -- Corner-pinned owners: mirror the container's placement so the overlay always covers the live grid (FB.Anchor just ran).
            owner.mover:SetPoint("CENTER", owner.container, "CENTER")
        else
            local p = oset.freePos or {}
            owner.mover:SetPoint("CENTER", UIParent, "CENTER", p.x or 100, p.y or 0)
        end
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
            -- Only the border state can change here, and only on the buttons that flipped
            for _, b in ipairs(FB.buttons) do
                if b:IsVisible() and FB.ReadTarget(b, FB.UnitOf(b)) then FB.ApplyBorderColor(b) end
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
        -- Attached runs wrap along the frames' group axis, and the grid flow's
        -- column advance runs right like a plain RIGHT run (FB.Anchor reads it
        -- the same way). Read raw it would miss every branch below: the left
        -- flip falls through to DOWN and the perpendicular check picks the
        -- RIGHT default by luck.
        if wrap == "DOWNRIGHT" then wrap = "RIGHT" end
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
    local corner, x, y = FB.CornerPin(horizontal and grow or wrap, horizontal and wrap or grow, r)
    FB.Pin(c, corner, UIParent, "CENTER", x, y)
    return true
end

-- Called by the shared mover on drag stop: capture the dropped rect for the corner pin above.
XF.SaveFreeRect = function(mover)
    FB.SaveMoverRect(mover, XF.Settings())
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
        if d.powerText then
            ApplyFont(d.powerText, xs.powerTextSize or 8)
            ns._RFAnchorPowerText(d)
        end
        if d.levelText then
            ApplyFont(d.levelText, xs.levelTextSize or 10)
            ns._RFAnchorLevelText(d)
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
        if ns.RF_FvMissingAnchor then ns.RF_FvMissingAnchor(b, d) end
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
                    local ppct = UnitPowerPercent(unit, pType, true, CurveConstants.ScaleTo100)
                    d.power:SetValue(ppct)
                    -- Power Text rides the same value (nil = off: this one field test).
                    local pwtMode = d._pwtMode
                    if pwtMode then ns.RF_PowerTextInto(d.powerText, pwtMode, ppct, unit, pType) end
                end
            elseif event == "UNIT_DISPLAYPOWER" then
                local d = GetFFD(b)
                if d.power and d.power:IsShown() then
                    ns._RFPowerTypeEdge(d, unit)
                    local ppct = UnitPowerPercent(unit, d._pwType, true, CurveConstants.ScaleTo100)
                    d.power:SetValue(ppct)
                    local pwtMode = d._pwtMode
                    if pwtMode then ns.RF_PowerTextInto(d.powerText, pwtMode, ppct, unit, d._pwType) end
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
                    dd._rmhPct = nil -- reduced-max cache: this is its only value edge
                    ns._UpdateButtonHealth(b, unit)
                    ns._ResettleButtonHealth(b)
                end
                end -- prediction view-gate else
            elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
                local d = GetFFD(b)
                ns.RF_PaintThreat(d, d._isExtra and ns._scaledExtraProxy or ns._scaledProfile, unit)
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
            elseif event == "UNIT_LEVEL" then
                ns._RFRepaintLevel(b)
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
        if ns._NotifyTrackerProviders then ns._NotifyTrackerProviders() end
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
            -- UNIT_LEVEL is opt-in too: only while a view shows Level Text.
            if ns._RFLevelWanted() then
                t:RegisterUnitEvent("UNIT_LEVEL", unit)
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
    -- Extra frames are excluded from _CollectTrackerFrames (duplicates), but
    -- name-scanning trackers do index them, and PLAYER_ROLES_ASSIGNED reshuffles
    -- them with no event those trackers listen for.
    if ns._NotifyTrackerProviders then ns._NotifyTrackerProviders() end
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
--  Pet Frames: party and raid pets in one Blizzard pet header, beside the
--  groups like Friendly Boss, or (Party tab, Beside Owner) one pet button
--  beside each party frame. Health, name, range, hover/target borders and
--  click-cast only, on the FB visuals, painter and anchor; out of the raid
--  routing maps, trackers of their own. Built on first Show Pets.
-------------------------------------------------------------------------------
-- Scope block: 200-local main-chunk cap (see the FB block above).
do
local FB = ns._FB
local PF = { buttons = {}, trackers = {}, byUnit = {}, ownerButtons = {}, ownerByUnit = {}, watching = false,
             shownEv = false, tgtEv = false, petEv = false, tgtWanted = false }
ns._PF = PF

PF.MAX = 40
PF.UNITS = { "pet" }
for i = 1, 4 do PF.UNITS[#PF.UNITS + 1] = "partypet" .. i end
for i = 1, 40 do PF.UNITS[#PF.UNITS + 1] = "raidpet" .. i end
-- Tracker frames (two tokens each): every token, or while raid pets are off the first seven, which
-- hold your pet, the party pets and raidpet1-9 (inside a raid the party frames run below ten
-- members).
PF.ALL_TRACKERS = math.ceil(#PF.UNITS / 2)
PF.SMALL_TRACKERS = 7
PF.EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE" }
-- A party frame's token -> its pet's token.
PF.PET_OF = { player = "pet" }
for i = 1, 4 do PF.PET_OF["party" .. i] = "partypet" .. i end
for i = 1, 40 do PF.PET_OF["raid" .. i] = "raidpet" .. i end
PF.DEFAULT_BG = { r = 17/255, g = 17/255, b = 17/255 }
-- Beside Owner pet -> the party frame it sits beside (your own pet has none); header button -> the
-- style generation it was last styled at; Beside Owner pet -> its preview mouse blocker.
PF.ownerOf = setmetatable({}, { __mode = "k" })
PF.styledGen = setmetatable({}, { __mode = "k" })
PF.pvBlock = setmetatable({}, { __mode = "k" })

PF.Raw = function()
    return db and db.profile and db.profile.petFrames
end
-- The painter's Pet Health Color read (one setting for both tabs, off the per-tab view).
PF.ColorSettings = PF.Raw

-- The Party and Raid tabs each keep their own Position, Extra Width/Height and Free Move spot. A tab
-- reads the shared key until it sets its own: a view over the saved table that never writes on
-- read. Every other key (the tab toggles, Pet Health Color, Pet Side) is the saved one.
PF.TAB_KEY = {
    party = { position = "party_position", extraWidth = "party_extraWidth", extraHeight = "party_extraHeight",
              freePos = "party_freePos", freeRect = "party_freeRect" },
    raid  = { position = "raid_position", extraWidth = "raid_extraWidth", extraHeight = "raid_extraHeight",
              freePos = "raid_freePos", freeRect = "raid_freeRect" },
}
PF.views = {}
PF.View = function(ctx)
    local v = PF.views[ctx]
    if v then return v end
    local keys = PF.TAB_KEY[ctx]
    v = setmetatable({}, {
        __index = function(_, k)
            local raw = PF.Raw()
            if not raw then return nil end
            local tk = keys[k]
            if tk then
                local val = raw[tk]
                if val ~= nil then return val end
            end
            return raw[k]
        end,
        __newindex = function(_, k, val)
            local raw = PF.Raw()
            if raw then raw[keys[k] or k] = val end
        end,
    })
    PF.views[ctx] = v
    return v
end
ns.PF_View = PF.View

-- The toggle that counts is the one for the frames on screen: the party frames also run inside
-- small raids and arenas.
PF.PartyMode = function()
    return not IsInRaid() or ns._PartyInRaid()
end

PF.Ctx = function()
    return PF.PartyMode() and "party" or "raid"
end

-- The live tab's view.
PF.Settings = function()
    return PF.Raw() and PF.View(PF.Ctx())
end

-- Beside Owner: Show Pets on the Party tab with its Position on Beside Owner, while the party frames
-- are the ones on screen.
PF.OwnerChosen = function()
    local raw = PF.Raw()
    return (raw and raw.party == true and PF.PartyMode() and PF.View("party").position == "owner") or false
end

-- The pet header (Beside Owner leaves it down).
PF.Wanted = function()
    local raw = PF.Raw()
    if not raw then return false end
    if PF.PartyMode() then return raw.party == true and PF.View("party").position ~= "owner" end
    return raw.raid == true
end

-- Settings the pets are styled from: the party settings beside the party frames, else the raid's.
-- The header's follows the mode PF.Layout last laid it out for (PF.styleCtx), so the paint path
-- never re-derives the mode.
PF.PartySource = function()
    return ns._scaledPartyProxy
end
PF.StyleSource = function()
    if PF.styleCtx == "party" then return ns._scaledPartyProxy end
    return ns._scaledProfile or db.profile
end

-- Beside Owner pets ignore their party frame's alpha (its range, offline and Buff Manager fades
-- are the owner's), so the party container's own dims (the options previews) apply here instead.
PF.ContainerAlpha = function()
    local a = ns._partyContainerFrame:GetAlpha()
    if issecretvalue(a) then return 1 end
    return a
end

-- As the raid buttons: UnitInRange's first return straight into SetAlphaFromBoolean, which takes
-- a secret. Its unchecked case is your own units, so your pet stays at full alpha like you do.
PF.ApplyRange = function(b)
    local unit = FB.UnitOf(b)
    if not unit then return end
    local ca = PF.ownerOf[b] and PF.ContainerAlpha() or 1
    local own = UnitIsUnit(unit, "pet")
    if issecretvalue(own) then own = false end
    if not UnitExists(unit) or own then
        b:SetAlpha(ca)
        return
    end
    local s = FB.Source(b)
    b:SetAlphaFromBoolean(UnitInRange(unit), ca, (s.oorAlpha or 0.4) * ca)
end

-- fn(b, unit) on every pet button on screen: the header's, and beside the party frames the Beside
-- Owner pets and your own pet button.
PF.EachShown = function(fn)
    if PF.active then
        for u, b in pairs(PF.byUnit) do
            if b:IsVisible() then fn(b, u) end
        end
    end
    if PF.ownerActive then
        for u, b in pairs(PF.ownerByUnit) do
            if b:IsVisible() then fn(b, u) end
        end
        local sp = PF.selfPet
        if sp:IsVisible() then fn(sp, "pet") end
    end
end

-- Whether a target change can repaint anything: Target Border on in the settings the pets that are
-- up are styled from. Re-read by every apply and party restyle (PF.SyncListeners).
PF.TargetWanted = function()
    local s = PF.active and PF.StyleSource()
    if s and s.targetBorderEnabled ~= false then return true end
    s = PF.ownerActive and PF.PartySource()
    return (s and s.targetBorderEnabled ~= false) and true or false
end

-- Every pet listener runs only while a pet button is on screen (the header hidden solo or in a pet
-- battle, or the party frames down, leaves none): the trackers' health, name and range, the vehicle
-- edges, UNIT_PET beside the party frames, and target changes while a Target Border can show. A
-- button coming on screen paints in full, which covers whatever it missed.
PF.SyncShownEvents = function()
    local want = (PF.tracking and (PF.visCount or 0) > 0) and true or false
    local ev = PF.eventFrame
    local tgt = want and PF.tgtWanted
    if PF.tgtEv ~= tgt then
        PF.tgtEv = tgt
        if tgt then ev:RegisterEvent("PLAYER_TARGET_CHANGED") else ev:UnregisterEvent("PLAYER_TARGET_CHANGED") end
    end
    local pet = (want and PF.ownerActive) and true or false
    if PF.petEv ~= pet then
        PF.petEv = pet
        if pet then ev:RegisterEvent("UNIT_PET") else ev:UnregisterEvent("UNIT_PET") end
    end
    if PF.shownEv == want then return end
    PF.shownEv = want
    if want then
        ev:RegisterEvent("UNIT_ENTERED_VEHICLE")
        ev:RegisterEvent("UNIT_EXITED_VEHICLE")
    else
        ev:UnregisterEvent("UNIT_ENTERED_VEHICLE")
        ev:UnregisterEvent("UNIT_EXITED_VEHICLE")
    end
    for _, tr in ipairs(PF.trackers) do PF.TrackerEvents(tr, want) end
end

-- The listeners after an apply or a party restyle, which can change the pets that are up and the
-- Target Border setting.
PF.SyncListeners = function()
    PF.tgtWanted = PF.TargetWanted()
    PF.SyncShownEvents()
end

-- One tracker's health, name and range listeners. Your own pet takes no range fade, so its token is
-- left out of range.
PF.TrackerEvents = function(tr, on)
    local f = tr.frame
    if not on then
        f:UnregisterAllEvents()
        return
    end
    for _, ev in ipairs(PF.EVENTS) do f:RegisterUnitEvent(ev, tr.u1, tr.u2) end
    if tr.u1 == "pet" then
        f:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", tr.u2)
    else
        f:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", tr.u1, tr.u2)
    end
end

-- Range re-read with no range update behind it (phasing, the Out of Range Alpha slider, roster
-- passes): the tail of the raid frames' own range seed.
function ns._PF_RangeSeed()
    if PF.shownEv then PF.EachShown(PF.ApplyRange) end
end

-- A group member's connection changed: re-read its pet's range.
function ns._PF_OwnerRange(owner)
    local pt = PF.shownEv and PF.PET_OF[owner]
    if not pt then return end
    local b = PF.active and PF.byUnit[pt]
    if b and b:IsVisible() then PF.ApplyRange(b) end
    b = PF.ownerActive and PF.ownerByUnit[pt]
    if b and b:IsVisible() then PF.ApplyRange(b) end
end

-- A target change repaints only the pets whose target state flipped (the old and new target).
PF.TargetFlip = function(b, u)
    if FB.ReadTarget(b, u) then FB.ApplyBorderColor(b) end
end

-- The full paint, which stamps the occupant it painted (unit + GUID, a secret GUID never stored) so
-- a re-assignment of the same pet can skip it. A pet that does not exist yet still gets its border.
PF.Refresh = function(b)
    if not FB.Update(b, PF) then FB.ApplyBorderColor(b) end
    PF.ApplyRange(b)
    local u = FB.UnitOf(b)
    local g = u and UnitGUID(u)
    if issecretvalue(g) then g = nil end
    local d = GetFFD(b)
    d.pfPaintUnit, d.pfGuid = u, g
end

-- Repaints a shown button only when its occupant differs from the stamped one (a secret or missing
-- GUID always repaints).
PF.Revalidate = function(b)
    if not (b and b:IsVisible()) then return end
    local u = FB.UnitOf(b)
    local d = GetFFD(b)
    if u and u == d.pfPaintUnit then
        local g = UnitGUID(u)
        if issecretvalue(g) then g = nil end
        if g and g == d.pfGuid then return end
    end
    PF.Refresh(b)
end

-- Every pet button on screen (cross-module colour and name pushes).
function ns._PF_RefreshVisible()
    PF.EachShown(PF.Refresh)
end

-- The buttons of one list that are on screen (PF.buttons or PF.ownerButtons), after a settings
-- reload or a party/raid flip.
PF.RepaintShown = function(list)
    for _, b in ipairs(list) do
        if b:IsVisible() then PF.Refresh(b) end
    end
end

-- The pet behind one owner's token may have changed while its button kept the same unit attribute:
-- a new pet (UNIT_PET, Beside Owner only: the pet header re-assigns its own buttons on it), or the
-- owner entering or leaving a vehicle, which the pet token then stands for. Only that owner's pet
-- buttons are re-checked. owner: the event's unit.
PF.OnPetChanged = function(owner)
    local pt = owner and PF.PET_OF[owner]
    if not pt then return end
    if PF.active then PF.Revalidate(PF.byUnit[pt]) end
    if PF.ownerActive then
        PF.Revalidate(PF.ownerByUnit[pt])
        if pt == "pet" then PF.Revalidate(PF.selfPet) end
    end
end

-- The party container's alpha changed (the options previews): re-apply the Beside Owner pets'.
function ns._PF_AlphaSync()
    if not PF.ownerActive then return end
    for _, b in ipairs(PF.ownerButtons) do
        if PF.ownerOf[b] and b:IsVisible() then PF.ApplyRange(b) end
    end
end

-- The side a group attached beside the party frames takes, the Party Frames kit's flip included.
PF.KitSide = function(pos)
    local before = pos == "left"
    if ns.RF_PartyKit() then before = ns.RF_KitAttach(db.profile, before) end
    return before
end

-- The pet group goes after Friendly Boss and Extra Frames when they sit on the same side. Beside
-- the party frames only a Show in Dungeons boss group is attached there to follow, and Extra
-- Frames (raid only) never is.
PF.ChainAnchor = function(pset)
    if pset.position == "free" or pset.position == "owner" then return end
    local party = PF.PartyMode()
    local fs = FB.Settings()
    if fs and FB.built and FB.container:IsShown() then
        if party then
            if fs.position ~= "free" and fs.showInDungeons == true
               and PF.KitSide(fs.position) == PF.KitSide(pset.position) then
                return FB.container
            end
        elseif fs.position == pset.position then
            return FB.container
        end
    end
    if party then return end
    local xf = ns._XF
    local xs = xf.Settings()
    if xs and xs.position == pset.position and xf.built and xf.container and xf.container:IsShown() then
        return xf.container
    end
end

-- map: the unit -> button map the button keeps itself in (none for your own Beside Owner pet).
PF.StyleButton = function(b, map)
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("*type1", "target")
    -- The engine gates SecureUnitButton's togglemenu; route right-click through a SecureActionButton proxy so the menu works without taint.
    EllesmereUI.AttachSecureUnitMenu(b)
    FB.BuildVisuals(b)

    b:HookScript("OnShow", function(self)
        PF.visCount = (PF.visCount or 0) + 1
        -- A button showing again holds its unit's map entry, which another button may have taken
        -- and dropped while this one was off screen with the same unit.
        if map then
            local u = self:GetAttribute("unit")
            local d = GetFFD(self)
            local old = d.pfUnit
            if old and old ~= u and map[old] == self then map[old] = nil end
            if u then map[u] = self end
            d.pfUnit = u
        end
        -- Header buttons hidden at the last restyle catch up as they show.
        local g = PF.styledGen[self]
        if g and g ~= PF.styleGen then PF.StyleHeaderButton(self) end
        PF.Refresh(self)
        PF.SyncShownEvents()
    end)
    b:HookScript("OnHide", function(self)
        PF.visCount = math.max(0, (PF.visCount or 0) - 1)
        local d = GetFFD(self)
        d.pfPaintUnit, d.pfGuid = nil, nil
        PF.SyncShownEvents()
    end)
    b:HookScript("OnEnter", function(self)
        FB.hov[self] = true
        FB.ApplyBorderColor(self)
    end)
    b:HookScript("OnLeave", function(self)
        FB.hov[self] = nil
        FB.ApplyBorderColor(self)
    end)
    -- The header (or, beside the party frames, the party frame's unit snippet) re-units buttons as
    -- pets come and go, in combat too. Both re-set every button's unit on each re-process (roster,
    -- name and pet events), so most fires re-confirm the pet already painted: those keep only the
    -- map write. A hidden button paints as it shows.
    b:HookScript("OnAttributeChanged", function(self, name, value)
        if name ~= "unit" then return end
        local d = GetFFD(self)
        if map then
            local old = d.pfUnit
            if old and map[old] == self then map[old] = nil end
            if value then map[value] = self end
            d.pfUnit = value
        end
        if not value or not self:IsVisible() then
            d.pfPaintUnit, d.pfGuid = nil, nil
            if not value then FB.tgt[self] = nil end
            return
        end
        if value == d.pfPaintUnit then
            local g = UnitGUID(value)
            if issecretvalue(g) then g = nil end
            if g and g == d.pfGuid then return end
        end
        PF.Refresh(self)
    end)

    -- Full click-cast / hovercast binding suite (mouseover heals included)
    if ns.CC_RegisterFrame then ns.CC_RegisterFrame(b) end
end

-- One header button at the header's current size and style.
PF.StyleHeaderButton = function(b)
    if not PF.w then return end
    local s = PF.StyleSource()
    FB.StyleVisuals(b, s, PF.w, PF.h, ResolveHealthTexture(s), s.customBgColor or PF.DEFAULT_BG)
    PF.styledGen[b] = PF.styleGen
end

-- Every setting the button styler reads (FB.StyleVisuals with FB.StyleBorder; the size is checked on
-- its own), plus the UI scale its pixel-sized borders follow, gathered into a reused list, so a
-- reload that changed none of them leaves the pets' fonts, textures and borders alone. The hover and
-- target borders are painted, not styled.
PF.STYLE_N = 35
PF.fp = {}
PF.fpNew = {}
PF.StyleInputs = function(t, s, texPath)
    local bgc = s.customBgColor or PF.DEFAULT_BG
    local bc = s.borderColor
    t[1], t[2], t[3], t[4], t[5] = bgc.r, bgc.g, bgc.b, s.bgDarkness, texPath
    t[6], t[7] = s.healthVerticalFill, s.healthBarOpacity
    t[8], t[9] = EllesmereUI.GetFontPath("raidFrames"), EllesmereUI.GetFontOutlineFlag("raidFrames")
    t[10], t[11], t[12] = s.nameSize, s.healthTextSize, s.healAbsorbTextSize
    t[13], t[14], t[15] = s.namePosition, s.nameOffsetX, s.nameOffsetY
    t[16], t[17], t[18] = s.healthTextPosition, s.healthTextOffsetX, s.healthTextOffsetY
    t[19], t[20], t[21] = s.healAbsorbTextPosition, s.healAbsorbTextOffsetX, s.healAbsorbTextOffsetY
    t[22], t[23], t[24], t[25], t[26] = s.borderSize, bc and bc.r, bc and bc.g, bc and bc.b, s.borderAlpha
    t[27], t[28], t[29] = s.borderTexture, s.borderSizePx, s.borderBehind
    t[30], t[31] = s.borderTextureOffset, s.borderTextureOffsetY
    t[32], t[33] = s.borderTextureShiftX, s.borderTextureShiftY
    t[34] = UIParent:GetEffectiveScale()
    t[35] = s.healthInvertFill
end

-- True when the inputs differ from the ones last styled under key ("hdr": the header, "owner": the
-- Beside Owner pets, "pt": the party target frames), which they then become (two lists trade
-- places, nothing allocated). extra(t), when given, writes the key's own inputs after the shared
-- ones, n slots in all (the party target frames' colour settings). The second return is the first
-- slot that differs (0 with nothing styled yet), so a key with extra slots can tell a change to
-- its own inputs alone (past PF.STYLE_N) from one the styler reads.
PF.StyleChanged = function(key, s, texPath, extra, n)
    local new = PF.fpNew
    PF.StyleInputs(new, s, texPath)
    if extra then extra(new) end
    local old, at = PF.fp[key], 0
    if old then
        for i = 1, n or PF.STYLE_N do
            if old[i] ~= new[i] then at = i; break end
        end
        if at == 0 then return false end
    end
    PF.fp[key] = new
    PF.fpNew = old or {}
    return true, at
end

-- Header buttons: five in one column beside the party frames, all forty (eight columns) once raid
-- pets are on. The column count caps what the header shows, so it never makes a button itself.
PF.Capacity = function()
    local raw = PF.Raw()
    return (raw and raw.raid == true) and PF.MAX or 5
end

-- A header makes children only while visible, so the buttons up to the capacity are made up front
-- (the raid headers' startingIndex pass, its parent shown for it) and set up once; the header then
-- assigns pets to them. The pass leaves the header hidden for the apply to show laid out. With the
-- UI hidden (a cinematic, Alt-Z) nothing is made and the next apply tries again. OOC only.
PF.EnsureBuilt = function()
    local cap = PF.Capacity()
    local have = #PF.buttons
    if have >= cap then return true end
    local hdr = PF.container
    if not hdr then
        -- The header's parent carries its pet-battle and solo hide (see PF.SetHider).
        local hider = CreateFrame("Frame", nil, UIParent)
        hider:SetAllPoints(UIParent)
        PF.hider = hider
        hdr = CreateFrame("Frame", "ERFPetHeader", hider, "SecureGroupPetHeaderTemplate")
        hdr:SetAttribute("template", "SecureUnitButtonTemplate")
        hdr:SetAttribute("templateType", "Button")
        hdr:SetAttribute("showRaid", true)
        hdr:SetAttribute("showParty", true)
        hdr:SetAttribute("showPlayer", true)
        hdr:SetAttribute("sortMethod", "INDEX")
        hdr:SetAttribute("unitsPerColumn", 5)
        -- The forty-button pass lays its buttons out in columns, which needs a column anchor;
        -- PF.Layout sets the real one.
        hdr:SetAttribute("columnAnchorPoint", "LEFT")
        PF.container = hdr
        -- Switched on with a preview up: dim it like the other real frames.
        if ns.previewActive() or ns._partyPvActive then ns._SetRealFramesPreviewHidden(true) end
    end
    if not hdr[cap] then
        local hider = PF.hider
        local hid = not hider:IsShown()
        hdr:Hide()
        if hid then hider:Show() end
        hdr:SetAttribute("maxColumns", cap > 5 and 8 or 1)
        hdr:SetAttribute("startingIndex", 1 - cap)
        hdr:Show()
        hdr:SetAttribute("startingIndex", 1)
        hdr:Hide()
        if hid then hider:Hide() end
    end
    for i = have + 1, cap do
        local b = hdr[i]
        if not b then break end
        PF.StyleButton(b, PF.byUnit)
        FB.src[b] = PF.StyleSource
        PF.styledGen[b] = 0
        PF.buttons[i] = b
    end
    local n = #PF.buttons
    if n == 0 then return false end
    -- New buttons take their size on the next layout.
    if n > have then PF.w = nil end
    PF.EnsureTrackers(n >= PF.MAX and PF.ALL_TRACKERS or PF.SMALL_TRACKERS)
    PF.built = true
    return true
end

-- Per-event slices of the full paint (PF.Refresh): health events repaint the health value and texts,
-- name events the name, range updates the range fade.
PF.PaintHealth = function(b, u)
    if UnitExists(u) then FB.PaintHealth(b, u, FB.Source(b)) end
end
PF.PaintName = function(b, u)
    if UnitExists(u) then FB.PaintName(b, u, FB.Source(b)) end
end

-- The event's pet is on the header button holding it, and beside the party frames on its Beside
-- Owner pet (your pet on your own pet button or on the party frame showing you: one of them shows).
PF.OnTrackerEvent = function(_, event, u)
    local paint = PF.PaintHealth
    if event == "UNIT_IN_RANGE_UPDATE" then
        paint = PF.ApplyRange
    elseif event == "UNIT_NAME_UPDATE" then
        paint = PF.PaintName
    end
    local b = PF.byUnit[u]
    if b and b:IsVisible() then paint(b, u) end
    if PF.ownerActive then
        b = PF.ownerByUnit[u]
        if b and b:IsVisible() then paint(b, u) end
        b = PF.selfPet
        if u == "pet" and b:IsVisible() then paint(b, u) end
    end
end

-- Up to n tracker frames, two pet tokens each (RegisterUnitEvent takes two units), from the shell
-- pool. Frames added while pets are on screen listen at once (the listeners switch on edges).
PF.EnsureTrackers = function(n)
    for k = #PF.trackers + 1, n do
        local i = 2 * k - 1
        local t = ns.TakeShell()
        t:SetScript("OnEvent", PF.OnTrackerEvent)
        local tr = { frame = t, u1 = PF.UNITS[i], u2 = PF.UNITS[i + 1] }
        PF.trackers[k] = tr
        if PF.shownEv then PF.TrackerEvents(tr, true) end
    end
end

-------------------------------------------------------------------------------
--  Beside Owner (Party tab): a pet button beside each party frame. The party
--  header's children carry them as children, so they follow every re-sort and
--  hide with their frame (Hide Self included). Each party frame's unit snippet
--  (refreshUnitChange, run by the header right after it assigns the frame's
--  unit, in combat too) writes the pet's own unit, so mouseover, click-cast
--  and the target and menu proxies see the pet token itself. It writes on
--  every pass, the same token included: tokens are positional, so a member
--  leaving hands a frame's token to the next member, and the pet's unit hook
--  then re-checks the occupant. Your own pet has a button of its own on the
--  party container: beside the self button, or with Hide Self in your frame's
--  empty slot after the last party frame.
--  The same snippet carries the party target frames' Include Own Target gate:
--  with it off (pt-noself), the frame holding you drops its target frame's
--  unit (the restricted environment has no UnitIsUnit, so your raid token is
--  compared as pt-me). The pet part runs only while the pets are up (pf-on).
--  Limitation: pt-me is written out of combat. A raid index shift in combat
--  (arena, Small Raid: a lower-index member leaves) leaves it stale until the
--  combat-end reseed (ns._ptSelfDirty -> ns._PT_SyncSelf): your own target
--  shows, and the member now on your old token loses theirs, until then.
-------------------------------------------------------------------------------
PF.OWNER_SNIPPET = [[
    local u = self:GetAttribute("unit")
    if self:GetAttribute("pf-on") then
        local pu
        if u == "player" then
            pu = "pet"
        elseif u then
            local k, n = strmatch(u, "^(%a+)(%d+)$")
            if k then pu = k .. "pet" .. n end
        end
        local pet = self:GetFrameRef("pfpet")
        if pet then pet:SetAttribute("unit", pu) end
        local sp = self:GetFrameRef("pfself")
        if sp and sp:GetAttribute("pf-hs") then
            sp:ClearAllPoints()
            sp:SetPoint(sp:GetAttribute("pf-pt"), self, sp:GetAttribute("pf-rp"), sp:GetAttribute("pf-x"), sp:GetAttribute("pf-y"))
        end
    end
    local pt = self:GetFrameRef("ptframe")
    if pt then
        local show = not (pt:GetAttribute("pt-noself") and u and (u == "player" or u == pt:GetAttribute("pt-me")))
        if pt:GetAttribute("useparent-unit") ~= show then pt:SetAttribute("useparent-unit", show) end
    end
]]

-- OOC only.
PF.EnsureOwnerBuilt = function()
    if PF.ownerBuilt then return end
    PF.ownerBuilt = true
    -- Your pet hangs off the container, not the self button, so it can outlive Hide Self.
    local sp = CreateFrame("Button", nil, ns._partyContainerFrame, "SecureUnitButtonTemplate")
    sp:SetAttribute("unit", "pet")
    sp:Hide()
    PF.StyleButton(sp)
    FB.src[sp] = PF.PartySource
    PF.selfPet = sp
    PF.ownerButtons[1] = sp
    for _, owner in ipairs(ns._partyAllButtons) do
        if owner ~= ns._partySelfButton then
            local b = CreateFrame("Button", nil, owner, "SecureUnitButtonTemplate")
            b:Hide()
            b:SetIgnoreParentAlpha(true)
            PF.ownerOf[b] = owner
            PF.StyleButton(b, PF.ownerByUnit)
            FB.src[b] = PF.PartySource
            PF.ownerButtons[#PF.ownerButtons + 1] = b
            SecureHandlerSetFrameRef(owner, "pfpet", b)
            SecureHandlerSetFrameRef(owner, "pfself", sp)
        end
    end
    PF.EnsureTrackers(PF.SMALL_TRACKERS)
end

-- The party frames' one unit snippet, installed while the Beside Owner pets or the party target
-- frames' Include Own Target gate (ns._ptNoSelf) need it, with the pet part switched by pf-on.
-- Only changed attributes are written. OOC only.
PF.SyncUnitSnippet = function()
    local pets = PF.ownerActive and true or nil
    local code = (pets or ns._ptNoSelf) and PF.OWNER_SNIPPET or nil
    for _, o in ipairs(ns._partyAllButtons) do
        if o ~= ns._partySelfButton then
            if o:GetAttribute("pf-on") ~= pets then o:SetAttribute("pf-on", pets) end
            if o:GetAttribute("refreshUnitChange") ~= code then o:SetAttribute("refreshUnitChange", code) end
        end
    end
end
ns.PF_SyncUnitSnippet = PF.SyncUnitSnippet

-- Switches the snippet's pet part on or off; on, seeds each pet's unit from its frame's current one
-- (written as the snippet does, the same token included). OOC only.
PF.SetOwnerLinks = function(on)
    if on then
        for _, b in ipairs(PF.ownerButtons) do
            local o = PF.ownerOf[b]
            if o then
                local u = o:GetAttribute("unit")
                b:SetAttribute("unit", u and PF.PET_OF[u])
            end
        end
    end
    PF.SyncUnitSnippet()
end

-- Unit watches on the Beside Owner pets run only while the party frames are on screen. OOC only.
PF.SetOwnerWatch = function()
    local want = (PF.ownerActive and ns._partyContainerFrame:IsShown()) and true or false
    if PF.watching ~= want then
        PF.watching = want
        for _, b in ipairs(PF.ownerButtons) do
            if PF.ownerOf[b] then
                if want then
                    RegisterUnitWatch(b)
                else
                    UnregisterUnitWatch(b)
                    b:Hide()
                end
            end
        end
    end
    PF.PlaceSelfPet()
end

-- Party frame size (the raid frame size under the Party Frames layout, whose size is its portrait
-- box, as Friendly Boss does).
PF.PartySize = function(s)
    local w, h, sp = ns.RF_PartyDims(db.profile)
    if ns.RF_PartyKit() then
        w, h, sp = s.frameWidth or 125, s.frameHeight or 60, s.cellSpacing or -1
    end
    return w, h, sp
end

-- A tab's pet size (its frames' size plus that tab's Extra Width/Height), spacing and growth: the
-- party frames' size and stacking on the Party tab, the raid frame size and growth on the Raid tab.
PF.Geometry = function(ctx)
    local s = ns._scaledProfile or db.profile
    local w, h, sp, unitGrowth, groupGrowth
    if ctx == "party" then
        w, h, sp = PF.PartySize(s)
        unitGrowth = ns._PartyGrowth(db.profile)
        groupGrowth = (unitGrowth == "RIGHT" or unitGrowth == "LEFT") and "DOWN" or "RIGHT"
    else
        w, h, sp = s.frameWidth or 125, s.frameHeight or 60, s.cellSpacing or -1
        unitGrowth, groupGrowth = ns._RFEffectiveGrowth(s.unitGrowth or "DOWN", s.groupGrowth or "RIGHT", true)
    end
    local v = PF.View(ctx)
    w = PixelSnap(math.max(10, w + (v.extraWidth or 0)))
    h = PixelSnap(math.max(10, h + (v.extraHeight or 0)))
    return w, h, sp, unitGrowth, groupGrowth
end

-- Pet Side, fitted to the party frames' orientation: across the stack only (Left/Right beside
-- stacked frames, Above/Below horizontal ones), so a pet never lands on the next frame. A choice
-- that no longer fits reads as the default until it fits again. s: the profile (or preview view).
PF.OwnerSide = function(s)
    local raw = PF.Raw()
    local side = raw and raw.ownerSide
    if s.partyHorizontal then
        if side ~= "above" and side ~= "below" then side = "below" end
    elseif side ~= "left" and side ~= "right" then
        side = "right"
    end
    return side
end
function ns.PF_OwnerSide()
    return PF.OwnerSide(db.profile)
end

-- The side the pets take and the extra gap: the Party Frames kit moves them off its outside auras
-- as it does the Friendly Boss group.
PF.ResolveOwnerSide = function(s)
    local side = PF.OwnerSide(s)
    local extra = 0
    if ns.RF_PartyKit() then
        local before = side == "left" or side == "above"
        before, extra = ns.RF_KitAttach(s, before)
        if s.partyHorizontal then side = before and "above" or "below"
        else side = before and "left" or "right" end
    end
    return side, extra
end

PF.OwnerPoint = function(b, owner, side, gap)
    if side == "left" then
        b:SetPoint("TOPRIGHT", owner, "TOPLEFT", -gap, 0)
    elseif side == "below" then
        b:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -gap)
    elseif side == "above" then
        b:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, gap)
    else
        b:SetPoint("TOPLEFT", owner, "TOPRIGHT", gap, 0)
    end
end

-- Size, side and style of the Beside Owner pets: only what changed is touched (the party layout pass
-- runs this on every roster edge). restyle (a settings reload) checks the style inputs, and restyles
-- the fonts, textures and borders only when they changed; a size change alone resizes. OOC only.
PF.OwnerLayout = function(restyle)
    local w, h, sp = PF.Geometry("party")
    local side, extra = PF.ResolveOwnerSide(db.profile)
    local baseGap = PixelSnap(sp)
    local gap = baseGap + PixelSnap(extra)
    local resized = w ~= PF.ownerW or h ~= PF.ownerH
    local moved = side ~= PF.ownerSideCur or gap ~= PF.ownerGap
    PF.ownerW, PF.ownerH, PF.ownerSideCur, PF.ownerGap, PF.ownerBaseGap = w, h, side, gap, baseGap
    local s, texPath
    local restyled = false
    if restyle then
        s = PF.PartySource()
        texPath = ResolveHealthTexture(s)
        restyled = PF.StyleChanged("owner", s, texPath)
    end
    if restyled then
        local bgc = s.customBgColor or PF.DEFAULT_BG
        for _, b in ipairs(PF.ownerButtons) do
            b:SetSize(w, h)
            FB.StyleVisuals(b, s, w, h, texPath, bgc)
        end
    elseif resized then
        for _, b in ipairs(PF.ownerButtons) do
            b:SetSize(w, h)
            FB.SizeVisuals(b, w, h)
        end
    end
    if moved then
        for _, b in ipairs(PF.ownerButtons) do
            local o = PF.ownerOf[b]
            if o then
                b:ClearAllPoints()
                PF.OwnerPoint(b, o, side, gap)
            end
        end
    end
    if resized or moved then
        PF.PlaceSelfPet(true)
        PF.NotifyReserve()
    end
end

-- Your own pet: beside the self button while that shows you. With Hide Self (in a group), in your
-- frame's empty slot after the last party frame: seated here, then re-seated by the party frames'
-- unit snippet after whichever frame the header fills last, so joins, leaves and re-sorts in combat
-- carry it along. While the party header shows you, that frame's own pet has it and this one stays
-- hidden. Repeat calls with nothing changed return at once. OOC only.
PF.PlaceSelfPet = function(force)
    local b = PF.selfPet
    if not b then return end
    if InCombatLockdown() then PF.anchorDirty = true; return end
    local mode = "off"
    if PF.watching then
        local m = ns._partySelfMode
        if m == "button" or (m == "hidden" and IsInGroup()) then mode = m end
    end
    if mode == "off" then
        if force or PF.spMode ~= "off" then
            PF.spMode = "off"
            b:SetAttribute("pf-hs", nil)
            UnregisterUnitWatch(b)
            b:Hide()
        end
        return
    end
    local grow = ns._PartyGrowth(db.profile)
    local _, _, psp = ns.RF_PartyDims(db.profile)
    -- The party frames' pitch: spacing, plus the room party target frames along the stack take.
    local slotGap = PixelSnap(psp) + ns.PT_AlongPitch(db.profile)
    if not force and mode == PF.spMode and PF.ownerSideCur == PF.spSide and PF.ownerGap == PF.spGap
       and grow == PF.spGrow and slotGap == PF.spSlotGap then
        return
    end
    PF.spMode, PF.spSide, PF.spGap, PF.spGrow, PF.spSlotGap = mode, PF.ownerSideCur, PF.ownerGap, grow, slotGap
    if mode == "hidden" then
        local pt, rp, x, y, base
        if grow == "UP" then
            pt, rp, x, y, base = "BOTTOMLEFT", "TOPLEFT", 0, slotGap, "BOTTOMLEFT"
        elseif grow == "RIGHT" then
            pt, rp, x, y, base = "TOPLEFT", "TOPRIGHT", slotGap, 0, "TOPLEFT"
        elseif grow == "LEFT" then
            pt, rp, x, y, base = "TOPRIGHT", "TOPLEFT", -slotGap, 0, "TOPRIGHT"
        else
            pt, rp, x, y, base = "TOPLEFT", "BOTTOMLEFT", 0, -slotGap, "TOPLEFT"
        end
        b:SetAttribute("pf-pt", pt)
        b:SetAttribute("pf-rp", rp)
        b:SetAttribute("pf-x", x)
        b:SetAttribute("pf-y", y)
        b:SetAttribute("pf-hs", true)
        local hdr = ns._partyHeader
        local last
        for i = 1, 5 do
            local c = hdr[i]
            if c and c:IsShown() and c:GetAttribute("unit") then last = c end
        end
        b:ClearAllPoints()
        if last then
            b:SetPoint(pt, last, rp, x, y)
        else
            b:SetPoint(base, hdr, base, 0, 0)
        end
    else
        b:SetAttribute("pf-hs", nil)
        b:ClearAllPoints()
        PF.OwnerPoint(b, ns._partySelfButton, PF.ownerSideCur, PF.ownerGap)
    end
    RegisterUnitWatch(b)
end

-- A Show in Dungeons boss group beside the party frames clears the Beside Owner pets' column, and
-- the party target frames follow the pets on their side.
PF.NotifyReserve = function()
    ns._PT_Layout()
    local fs = FB.Settings()
    if FB.built and fs and fs.showInDungeons == true then FB.Anchor() end
end

-- The room the Beside Owner pets take on the side a group attaches to the party frames (horizontal:
-- the party frames' orientation; before: left, or above horizontal frames).
function ns.PF_OwnerReserve(horizontal, before)
    local side = PF.ownerActive and PF.ownerSideCur
    if not side then return 0 end
    if horizontal then
        if (before and side == "above") or (not before and side == "below") then
            return PF.ownerH + PF.ownerBaseGap
        end
    elseif (before and side == "left") or (not before and side == "right") then
        return PF.ownerW + PF.ownerBaseGap
    end
    return 0
end

-- Whether either kind of pet is up. Its listeners follow the pets on screen (PF.SyncShownEvents),
-- the vehicle edges among them: an owner entering or leaving a vehicle swaps what its pet token
-- stands for without touching any unit attribute (PF.OnPetChanged re-checks that owner's pet).
PF.SetTracking = function(on)
    if PF.tracking == on then return end
    PF.tracking = on
    PF.SyncShownEvents()
end

-- One write of a batch on the header: the batch's first change sets _ignore, so the header skips its
-- update per attribute; the caller clears it and re-runs the header once. changed: whether the
-- batch has changed anything yet; returns the same for after this write.
local function SetAttr(hdr, key, value, changed)
    if hdr:GetAttribute(key) == value then return changed end
    if not changed then hdr:SetAttribute("_ignore", "attributeChanges") end
    hdr:SetAttribute(key, value)
    return true
end

-- The pet header's parent hides it in pet battles and, unless your pet shows solo, outside a group.
-- A visibility driver writes the statehidden attribute on its frame every 0.2 s; on the header that
-- attribute change re-runs its whole update, so the driver sits on this plain parent. Re-registered
-- only when the macro changes. Grouped = a raid1/party1 unit exists, which stays live in combat
-- (see ns._RF_VIS_MACROS).
-- solo: the header's showSolo. OOC only.
PF.SetHider = function(solo)
    local m = solo and "[petbattle] hide; show" or "[petbattle] hide; [@raid1,exists][@party1,exists][group] show; hide"
    if PF.hiderMacro ~= m then
        RegisterStateDriver(PF.hider, "visibility", m)
        PF.hiderMacro = m
    end
end

-- Teardown, after the header is hidden: the driver goes and the parent shows again, so a later build
-- makes its buttons under a shown parent. OOC only.
PF.ClearHider = function()
    if not PF.hiderMacro then return end
    UnregisterStateDriver(PF.hider, "visibility")
    PF.hiderMacro = nil
    PF.hider:Show()
end

-- Show Groups as a groupFilter: nil with every group on, one cached string per group set.
PF.gf = {}
PF.RaidGroupFilter = function()
    local vg = ns._VisibleGroups()  -- Mythic 5-8 aware (read-only)
    if not vg then return nil end
    local mask = 0
    for gi = 1, 8 do
        if vg[gi] ~= false then mask = mask + 2 ^ (gi - 1) end
    end
    if mask == 255 then return nil end
    local str = PF.gf[mask]
    if not str then
        str = ""
        for gi = 1, 8 do
            if vg[gi] ~= false then str = (str == "") and tostring(gi) or (str .. "," .. gi) end
        end
        PF.gf[mask] = str
    end
    return str
end

-- Size and growth follow the frames on screen (the party frames' in party mode, else the raid
-- frames'), plus that tab's size offsets. Roster edges come through here too, so only what changed
-- is touched: restyle (a settings or profile reload) and a party/raid flip restyle only when the
-- style inputs changed, a size change alone resizes, and buttons off screen catch up as they show.
-- Both also repaint the pets on screen, whose paint reads the settings too. OOC only.
PF.Layout = function(restyle)
    local ctx = PF.Ctx()
    local party = ctx == "party"
    local w, h, sp, unitGrowth, groupGrowth = PF.Geometry(ctx)
    local hdr = PF.container
    local resized = w ~= PF.w or h ~= PF.h
    PF.w, PF.h, PF.sp, PF.unitGrowth, PF.groupGrowth = w, h, sp, unitGrowth, groupGrowth
    local flipped = PF.styleCtx ~= ctx
    local restyled = false
    if restyle or flipped then
        PF.styleCtx = ctx
        local ss = PF.StyleSource()
        restyled = PF.StyleChanged("hdr", ss, ResolveHealthTexture(ss))
    end
    if resized then
        for _, b in ipairs(PF.buttons) do b:SetSize(w, h) end
    end
    if restyled or resized then
        PF.styleGen = (PF.styleGen or 0) + 1
        for _, b in ipairs(PF.buttons) do
            if b:IsVisible() then
                if restyled then
                    PF.StyleHeaderButton(b)
                else
                    FB.SizeVisuals(b, w, h)
                    PF.styledGen[b] = PF.styleGen
                end
            end
        end
    end
    -- Before the header re-runs below: the pets it re-assigns paint in their unit hook, and the
    -- ones it shows as they show.
    if restyle or flipped then PF.RepaintShown(PF.buttons) end

    local s = ns._scaledProfile or db.profile
    -- Party: Small Raid mode shows only group 1 in the party frames, and your pet shows solo while
    -- the party frames do. Raid: the groups Show Groups keeps.
    local group
    if party then
        local g = ns._SmallRaidGroup()
        group = g and tostring(g) or nil
    else
        group = PF.RaidGroupFilter()
    end
    -- Beside the party frames the pets keep the party frames' pitch, which party target frames along
    -- the stack open (the kit's pets take the raid frame size, which never lines up with them).
    local pitch = sp
    if party and not ns.RF_PartyKit() and PF.View("party").position ~= "free" then
        pitch = sp + ns.PT_AlongPitch(db.profile)
    end
    local point, xOff, yOff = ns._RFHeaderPoint(unitGrowth, pitch)
    local solo = (party and db.profile.partyShowWhenSolo) and true or nil
    -- One batch: the header re-runs once below, not per attribute.
    local changed = SetAttr(hdr, "groupFilter", group, false)
    changed = SetAttr(hdr, "showSolo", solo, changed)
    changed = SetAttr(hdr, "point", point, changed)
    changed = SetAttr(hdr, "xOffset", xOff, changed)
    changed = SetAttr(hdr, "yOffset", yOff, changed)
    changed = SetAttr(hdr, "columnSpacing", PixelSnap(s.groupSpacing or 8), changed)
    changed = SetAttr(hdr, "columnAnchorPoint", ns._RFColAnchor(unitGrowth, groupGrowth), changed)
    changed = SetAttr(hdr, "maxColumns", #PF.buttons >= PF.MAX and 8 or 1, changed)
    if changed then hdr:SetAttribute("_ignore", nil) end
    -- Blizzard never clears a shown button's anchors, and a leftover column anchor pins button 1 to
    -- the header's old size, so a new size or layout re-lays from cleared anchors (as the merged raid
    -- header does). One write of a spare attribute then re-runs the header once on the final
    -- attributes (clearing _ignore runs nothing, and a new size alone changes no attribute), with
    -- no pet hidden and re-shown. A header not on screen re-runs as it shows.
    if resized or changed then
        for _, b in ipairs(PF.buttons) do b:ClearAllPoints() end
        hdr:SetAttribute("pf-relayout", not hdr:GetAttribute("pf-relayout"))
    end
    -- Last, so a parent that shows here runs the header once on the final attributes.
    PF.SetHider(solo)
end

-- Free Move: the header is pinned at the corner its pets grow from, so pet 1 stays put as pets come
-- and go. The overlay covers five pets; until its first drag they are centred on freePos. ctx: the
-- tab whose spot and size this is.
PF.FreeCorner = function(set, ctx)
    local w, h, sp, unitGrowth, groupGrowth = PF.Geometry(ctx)
    local vertical = unitGrowth ~= "RIGHT" and unitGrowth ~= "LEFT"
    local hDir = vertical and groupGrowth or unitGrowth
    local vDir = vertical and unitGrowth or groupGrowth
    if vertical then h = 5 * h + 4 * sp else w = 5 * w + 4 * sp end
    local r = set.freeRect
    local corner, x, y = FB.CornerPin(hDir, vDir, r)
    if not r then
        local p = set.freePos
        local cx, cy = p and p.x or 100, p and p.y or 0
        x = (hDir == "LEFT") and (cx + w / 2) or (cx - w / 2)
        y = (vDir == "UP") and (cy - h / 2) or (cy + h / 2)
    end
    return corner, x, y, w, h
end

PF.FreeAnchor = function(c, set)
    local corner, x, y = PF.FreeCorner(set, PF.Ctx())
    FB.Pin(c, corner, UIParent, "CENTER", x, y)
    return true
end

-- The Move Frames overlay places the spot of the tab it was opened on, which need not be the live one.
PF.MoverSettings = function()
    return PF.Raw() and PF.View(PF.moverCtx or PF.Ctx())
end

-- Before the overlay shows: the live header, when up, takes the current settings.
PF.MoverPrep = function()
    if PF.active and not InCombatLockdown() then
        PF.Layout()
        PF.Anchor()
    end
end

PF.PlaceMover = function(m, set)
    local corner, x, y, w, h = PF.FreeCorner(set, PF.moverCtx or PF.Ctx())
    m:SetSize(w, h)
    m:SetPoint(corner, UIParent, "CENTER", x, y)
end

PF.SaveFreeRect = function(mover)
    FB.SaveMoverRect(mover, PF.MoverSettings())
end

-- ctx: "party" or "raid", the tab the overlay is for (the live one when nil).
function ns.PF_SetMoverShown(show, ctx)
    if show then PF.moverCtx = ctx or PF.Ctx() end
    FB.SetMoverShown(PF, show, "ERFPetFramesMover", "Pet Frames")
end

-- ctx: true only when the overlay is up for that tab (any tab when nil).
function ns.PF_IsMoverShown(ctx)
    return (PF.mover and PF.mover:IsShown() and (ctx == nil or PF.moverCtx == ctx)) or false
end

-- A size change on the tab whose overlay is up: the overlay takes the new size (the apply before
-- this has already re-laid the live group).
function ns.PF_PlaceMover(ctx)
    local m = PF.mover
    if not (m and m:IsShown() and PF.moverCtx == ctx) then return end
    local set = PF.MoverSettings()
    if not set then return end
    m:ClearAllPoints()
    PF.PlaceMover(m, set)
end

-- Options preview: made-up pets beside the preview frames, on the same visuals. Plain frames, built
-- the first time a preview shows with Show Pets on; the preview code makes room and places them.
PF.PV_PETS = {
    { name = "Felhunter", hp = 100 },
    { name = "Ghoul", hp = 64 },
    { name = "Spirit Beast", hp = 100 },
    { name = "Water Elemental", hp = 38 },
    { name = "Imp", hp = 85 },
}
PF.OPPOSITE = { RIGHT = "LEFT", LEFT = "RIGHT", DOWN = "UP", UP = "DOWN" }
PF.pv = {}

-- The settings the preview pets are painted with (their border reads it through FB.Source).
PF.PvStyle = function()
    return PF.pvStyle
end

-- One preview pass's shared paint values (reused table). Pets have no class: a class colour mode
-- reads white.
PF.pvc = {}
PF.PvColors = function(s)
    local c = PF.pvc
    PF.pvStyle = s
    c.texPath = ResolveHealthTexture(s)
    c.bgc = s.customBgColor or PF.DEFAULT_BG
    local raw = PF.Raw()
    c.hc = raw and raw.healthColor
    c.opacity = (s.healthBarOpacity or 100) / 100
    c.nr, c.ng, c.nb = ns.RF_PreviewTextColor(s.nameColorMode or "class", s.nameCustomColor, nil, 1, 1, 1)
    c.tr, c.tg, c.tb = ns.RF_PreviewTextColor(s.healthTextColorMode or "custom",
        s.healthTextCustomColor, nil, 1, 1, 1)
    c.ar, c.ag, c.ab = ns.RF_PreviewTextColor(s.healAbsorbTextColorMode or "custom",
        s.healAbsorbTextCustomColor, nil, 1, 0.3, 0.3)
    c.mode = s.healthTextMode or "none"
    c.haMode = s.healAbsorbTextMode or "none"
    return c
end

-- Preview pet i at w x h, styled and painted (the caller places it).
PF.PvFrame = function(i, parent, s, w, h, c)
    local f = PF.pv[i]
    if not f then
        f = CreateFrame("Frame", nil, parent)
        FB.BuildVisuals(f)
        FB.src[f] = PF.PvStyle
        PF.pv[i] = f
    elseif f:GetParent() ~= parent then
        f:SetParent(parent)
    end
    f:SetFrameStrata(parent == UIParent and "HIGH" or parent:GetFrameStrata())
    f:SetSize(w, h)
    FB.StyleVisuals(f, s, w, h, c.texPath, c.bgc)

    local pet = PF.PV_PETS[i]
    local pct = pet.hp
    local hc = c.hc
    f._health:SetMinMaxValues(0, 100)
    -- pet.hp is a made-up plain number (PF.PV_PETS), so it is flipped here for an
    -- inverted fill (the _euiInv stamp FB.StyleVisuals just left).
    f._health:SetValue(f._health._euiInv and (100 - pct) or pct)
    f._health:SetStatusBarColor(hc and hc.r or 23/255, hc and hc.g or 172/255, hc and hc.b or 49/255, c.opacity)
    f._nameText:SetText(pet.name)
    f._nameText:SetTextColor(c.nr, c.ng, c.nb)
    -- Made-up health (3000 per percent) and a heal absorb of a quarter of it, in the raid preview's
    -- proportions.
    ns.RF_HealthTextInto(f._healthText, c.mode, pct, nil, 3000)
    f._healthText:SetTextColor(c.tr, c.tg, c.tb, 0.9)
    ns.FormatHealAbsorbInto(f._healAbsorbText, pct * 750, c.haMode)
    f._healAbsorbText:SetTextColor(c.ar, c.ag, c.ab, 0.9)
    f:Show()
    return f
end

-- Beside Owner preview: the pet size, side and gap as the real pets take them, the room it needs
-- around the party frames (pads), and with Hide Self the slot after the last frame (sp: the party
-- frames' spacing). s: the preview's view; w, h, sp: its party frame size and spacing.
PF.OwnerPreviewSpec = function(s, w, h, sp)
    local pw, ph, gap = w, h, sp
    if ns.RF_PartyKit() then
        pw, ph, gap = PixelSnap(s.frameWidth or 125), PixelSnap(s.frameHeight or 60), PixelSnap(s.cellSpacing or -1)
    end
    local v = PF.View("party")
    pw = PixelSnap(math.max(10, pw + (v.extraWidth or 0)))
    ph = PixelSnap(math.max(10, ph + (v.extraHeight or 0)))
    local side, extra = PF.ResolveOwnerSide(s)
    gap = gap + PixelSnap(extra)
    local max = math.max
    local spec = { owner = true, w = pw, h = ph, side = side, gap = gap, padL = 0, padT = 0, padR = 0, padB = 0 }
    if side == "right" then
        spec.padR, spec.padB = gap + pw, max(0, ph - h)
    elseif side == "left" then
        spec.padL, spec.padB = gap + pw, max(0, ph - h)
    elseif side == "below" then
        spec.padB, spec.padR = gap + ph, max(0, pw - w)
    else
        spec.padT, spec.padR = gap + ph, max(0, pw - w)
    end
    if s.partyHideSelf then
        local grow = ns._PartyGrowth(s)
        spec.selfSlot = true
        -- The next slot: the party frames' pitch, party target frames along the stack included.
        sp = sp + ns.PT_AlongPitch(s, s.partyShowTargets == true)
        if grow == "UP" then
            spec.sPt, spec.sRp, spec.sX, spec.sY = "BOTTOMLEFT", "TOPLEFT", 0, sp
            spec.padT, spec.padR = max(spec.padT, sp + ph), max(spec.padR, pw - w)
        elseif grow == "RIGHT" then
            spec.sPt, spec.sRp, spec.sX, spec.sY = "TOPLEFT", "TOPRIGHT", sp, 0
            spec.padR, spec.padB = max(spec.padR, sp + pw), max(spec.padB, ph - h)
        elseif grow == "LEFT" then
            spec.sPt, spec.sRp, spec.sX, spec.sY = "TOPRIGHT", "TOPLEFT", -sp, 0
            spec.padL, spec.padB = max(spec.padL, sp + pw), max(spec.padB, ph - h)
        else
            spec.sPt, spec.sRp, spec.sX, spec.sY = "TOPLEFT", "BOTTOMLEFT", 0, -sp
            spec.padB, spec.padR = max(spec.padB, sp + ph), max(spec.padR, pw - w)
        end
    end
    return spec
end

-- The pet group beside a preview, or nil without Show Pets on that tab or on Free Move: button size,
-- count and growth, the group's size, and its top-left offset from the top-left of the boxW x boxH
-- box it attaches to (the party frames, or the first or last preview group), by the FB.Anchor rules.
-- Beside Owner (Party tab) returns its own spec instead (spec.owner, see PF.OwnerPreviewSpec).
-- w, h, sp: the preview's frame size and spacing; ptSpec: the preview's party target frames
-- (ns.PT_PreviewSpec), whose room the pets clear as the real ones do.
function ns.PF_PreviewSpec(party, s, w, h, sp, boxW, boxH, ptSpec)
    local raw = PF.Raw()
    if not raw or raw[party and "party" or "raid"] ~= true then return end
    local set = PF.View(party and "party" or "raid")
    if set.position == "free" then return end
    if set.position == "owner" then
        if party then return PF.OwnerPreviewSpec(s, w, h, sp) end
        return
    end
    local before = set.position == "left"
    local gap, grow, side
    if party then
        gap = s.groupSpacing or -1
        if ns.RF_PartyKit() then
            local extra
            before, extra = ns.RF_KitAttach(s, before)
            gap = gap + extra
        end
        gap = gap + ns.PT_PreviewReserve(ptSpec, s.partyHorizontal, before)
        grow = ns._PartyGrowth(s)
        if ns.RF_PartyKit() then
            w, h, sp = PixelSnap(s.frameWidth or 125), PixelSnap(s.frameHeight or 60), PixelSnap(s.cellSpacing or -1)
        else
            -- The party frames' pitch, party target frames along the stack included (PF.Layout's).
            sp = sp + ns.PT_AlongPitch(s, s.partyShowTargets == true)
        end
        if s.partyHorizontal then side = before and "UP" or "DOWN"
        else side = before and "LEFT" or "RIGHT" end
    else
        gap = PixelSnap(s.groupSpacing or 8)
        grow = s.unitGrowth or "DOWN"
        side = s.groupGrowth or "RIGHT"
        -- The grid flow ends in the rightmost column too, so the pets hang off
        -- the same edge a plain RIGHT run uses -- FB.Anchor agrees. Read raw,
        -- PF.OPPOSITE would return nil for it and the side would fall through
        -- to the vertical branch, drawing the pets above the groups.
        if side == "DOWNRIGHT" then side = "RIGHT" end
        if before then side = PF.OPPOSITE[side] end
    end

    local spec = { n = party and 3 or 5, sp = sp, grow = grow, before = before }
    spec.w = PixelSnap(math.max(10, w + (set.extraWidth or 0)))
    spec.h = PixelSnap(math.max(10, h + (set.extraHeight or 0)))
    if grow == "RIGHT" or grow == "LEFT" then
        spec.bw, spec.bh = spec.n * spec.w + (spec.n - 1) * sp, spec.h
    else
        spec.bw, spec.bh = spec.w, spec.n * spec.h + (spec.n - 1) * sp
    end
    spec.ox, spec.oy = 0, 0
    -- Party stacks that grow up or left start at the box's bottom or right edge.
    if party and grow == "UP" then spec.oy = spec.bh - boxH end
    if party and grow == "LEFT" then spec.ox = boxW - spec.bw end
    if side == "RIGHT" then spec.ox = boxW + gap
    elseif side == "LEFT" then spec.ox = -gap - spec.bw
    elseif side == "DOWN" then spec.oy = -(boxH + gap)
    else spec.oy = gap + spec.bh end
    return spec
end

-- Shows the spec's pets with the group's top-left at x, y from rel's top-left. s: the settings they
-- are styled from.
function ns.PF_ShowPreview(spec, s, parent, rel, x, y)
    local c = PF.PvColors(s)
    for i = 1, spec.n do
        local f = PF.PvFrame(i, parent, s, spec.w, spec.h, c)
        local off = i - 1
        local fx, fy = x, y
        if spec.grow == "RIGHT" then
            fx = x + off * (spec.w + spec.sp)
        elseif spec.grow == "LEFT" then
            fx = x + spec.bw - spec.w - off * (spec.w + spec.sp)
        elseif spec.grow == "UP" then
            fy = y - spec.bh + spec.h + off * (spec.h + spec.sp)
        else
            fy = y - off * (spec.h + spec.sp)
        end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", rel, "TOPLEFT", fx, fy)
    end
    for i = spec.n + 1, #PF.pv do PF.pv[i]:Hide() end
end

-- Beside Owner preview: a pet beside each shown party preview frame, and with Hide Self one after
-- lastF (the last frame along the growth). s: the settings they are styled from.
function ns.PF_ShowOwnerPreview(spec, s, parent, lastF)
    local c = PF.PvColors(s)
    local n = 0
    for i = 1, 5 do
        local o = ns._partyPvFrames[i]
        if o and o:IsShown() then
            n = n + 1
            local f = PF.PvFrame(n, parent, s, spec.w, spec.h, c)
            f:ClearAllPoints()
            PF.OwnerPoint(f, o, spec.side, spec.gap)
        end
    end
    if spec.selfSlot and lastF and n < #PF.PV_PETS then
        n = n + 1
        local f = PF.PvFrame(n, parent, s, spec.w, spec.h, c)
        f:ClearAllPoints()
        f:SetPoint(spec.sPt, lastF, spec.sRp, spec.sX, spec.sY)
    end
    for i = n + 1, #PF.pv do PF.pv[i]:Hide() end
end

function ns.PF_HidePreview()
    for _, f in ipairs(PF.pv) do f:Hide() end
end

-- Real-frame previews hide the real frames by alpha; while they do, our own mouse blockers keep the
-- invisible pet buttons from taking clicks: one over the pet header, and one on each Beside Owner
-- pet (they sit outside the party frames' blocker). Our frames, so Hide() is combat-legal.
PF.SetPreviewBlock = function(on)
    PF.pvBlockOn = on or nil
    local hdr = PF.container
    if on and PF.active and hdr then
        local blk = PF.hdrBlock
        if not blk then
            -- Under the header's parent, so it hides with the header's pet-battle and solo hide.
            blk = CreateFrame("Frame", nil, PF.hider)
            blk:EnableMouse(true)
            PF.hdrBlock = blk
        end
        blk:SetAllPoints(hdr)
        blk:SetFrameStrata(hdr:GetFrameStrata())
        blk:SetFrameLevel(hdr:GetFrameLevel() + 50)
        blk:Show()
    elseif PF.hdrBlock then
        PF.hdrBlock:Hide()
    end
    for _, b in ipairs(PF.ownerButtons) do
        local blk = PF.pvBlock[b]
        if on and PF.ownerActive then
            if not blk then
                blk = CreateFrame("Frame", nil, b)
                blk:SetAllPoints(b)
                blk:EnableMouse(true)
                PF.pvBlock[b] = blk
            end
            blk:SetFrameLevel(b:GetFrameLevel() + 50)
            blk:Show()
        elseif blk then
            blk:Hide()
        end
    end
end
ns._PF_SetPreviewBlock = PF.SetPreviewBlock

-- A frame strata change while blocked: re-seat the blockers.
function ns._PF_RefreshPreviewBlock()
    if PF.pvBlockOn then PF.SetPreviewBlock(true) end
end

-- The header's placement. FB.Anchor remembers the group it followed in PF.chainTgt (none on Free
-- Move), which the Friendly Boss / Extra Frames probe compares against. A combat call is deferred
-- to the combat-end flush by FB.Anchor.
PF.Anchor = function()
    PF.attachParty = PF.PartyMode()
    if not InCombatLockdown() then PF.chainTgt = false end
    FB.Anchor(PF)
end

function ns.PF_ReAnchor()
    if not InCombatLockdown() then PF.anchorDirty = nil end
    PF.PlaceSelfPet()
    if PF.active then PF.Anchor() end
end

-- Friendly Boss and Extra Frames can appear, move or go away without a roster change. A group that
-- moves carries the pets chained after it along, so the header re-anchors only when the group it
-- follows changes.
PF.ProbeChain = function()
    if not PF.active then return end
    local set = PF.Settings()
    if not set or set.position == "free" then return end
    if (PF.ChainAnchor(set) or false) ~= PF.chainTgt then PF.Anchor() end
end

-- The party layout pass (size, growth, spacing, orientation, the party frames' show/hide edge, the
-- kit's clearance): re-lays the pets and the party target frames that sit beside the party frames,
-- delta-gated. The target frames go after the Beside Owner pets they follow and before any
-- anchoring, so the attached groups are pinned once, on the new reserve.
function ns.PF_PartyRelayout()
    if not InCombatLockdown() then
        if PF.active and PF.PartyMode() then PF.Layout() end
        if PF.ownerActive then
            PF.OwnerLayout()
            PF.SetOwnerWatch()
        end
    end
    ns._PT_Layout()
    ns.PF_ReAnchor()
end

-- A party settings reload, which owns the pets styled from the party settings (the Beside Owner pets,
-- and the header beside the party frames): they check their style (restyled only when it changed)
-- and repaint. Deferred through combat to the combat-end flush.
function ns.PF_PartyRestyle()
    local header = PF.active and PF.PartyMode()
    if not (header or PF.ownerActive) then
        PF.partyRestyleDirty = nil
        return
    end
    if InCombatLockdown() then
        PF.partyRestyleDirty = true
        return
    end
    PF.partyRestyleDirty = nil
    if PF.ownerActive then
        PF.OwnerLayout(true)
        PF.RepaintShown(PF.ownerButtons)
    end
    if header then PF.Layout(true) end
    PF.SyncListeners()
end

-- Master apply: the options, the raid frames' reloads and the roster flush (below). OOC only;
-- deferred through combat like the other groups. restyle: a raid settings or profile reload, which
-- restyles only the pets styled from the raid settings (the party reload that follows it restyles
-- the others, see ns.PF_PartyRestyle).
function ns.PF_Apply(restyle)
    if not db or not db.profile then return end
    local raw = PF.Raw()
    if not raw then return end
    if InCombatLockdown() then
        PF.applyDirty = true
        PF.restyleDirty = PF.restyleDirty or restyle
        return
    end
    -- This pass covers a roster change or a combat-deferred apply still waiting for the flush.
    restyle = restyle or PF.restyleDirty
    PF.dirty, PF.applyDirty, PF.restyleDirty = nil, nil, nil

    -- Beside Owner. Chosen before the party frames exist (early login), neither kind comes up: the
    -- next apply brings the pets up. Only their activation edge checks their style here, before
    -- they show (and paint as they do).
    local chosen = PF.OwnerChosen()
    local owner = chosen and ns._partySelfButton ~= nil
    if owner then
        local edge = not PF.ownerActive
        if edge then
            PF.EnsureOwnerBuilt()
            PF.ownerActive = true
            PF.SetOwnerLinks(true)
        end
        PF.OwnerLayout(edge)
        PF.SetOwnerWatch()
        PF.SetTracking(true)
        if edge then PF.NotifyReserve() end
    elseif PF.ownerActive then
        PF.ownerActive = nil
        PF.SetOwnerLinks(false)
        PF.SetOwnerWatch()
        PF.NotifyReserve()
    end

    if chosen or not PF.Wanted() or not PF.EnsureBuilt() then
        PF.active = nil
        PF.chainTgt = nil
        if PF.built then PF.container:Hide() end
        PF.ClearHider()
        if not owner then PF.SetTracking(false) end
        if PF.pvBlockOn then PF.SetPreviewBlock(true) end
        PF.SyncListeners()
        return
    end

    -- The activation edge checks the style too: settings can change while the header is down.
    local edge = not PF.active
    PF.active = true
    PF.SetTracking(true)
    -- Layout also registers the parent's hide (PF.SetHider) and repaints the pets on screen on a
    -- restyle; the header shows last, laid out, its pets painting as they show. The roster's own
    -- re-assignments paint in the buttons' unit hook.
    PF.Layout((restyle and PF.Ctx() == "raid") or edge)
    ns.PF_ReAnchor()
    if not PF.container:IsShown() then PF.container:Show() end
    if PF.pvBlockOn then PF.SetPreviewBlock(true) end
    PF.SyncListeners()
end

-- Roster and zoning edges, folded into the raid frames' own passes: the roster change and the zone-in
-- mark the pets dirty (in combat too), and the raid frames' roster pass, zone-in settle and combat
-- end each flush once, after their own layout. Both toggles off, nothing is marked.
function ns.PF_MarkDirty()
    local raw = PF.Raw()
    if raw and (raw.party == true or raw.raid == true) then PF.dirty = true end
end

-- Runs what is waiting: a marked or combat-deferred apply, a combat-deferred party restyle, then a
-- combat-deferred placement. OOC only; in combat everything stays marked for the combat-end flush.
function ns.PF_Flush()
    if InCombatLockdown() then return end
    if PF.dirty or PF.applyDirty then ns.PF_Apply() end
    if PF.partyRestyleDirty then ns.PF_PartyRestyle() end
    -- A combat-deferred party target include edge or attribute seed (secure writes), then a
    -- combat-deferred party target layout (a kit clearance edge in combat), before the anchor.
    if ns._ptSelfDirty then ns._PT_SyncSelf() end
    if ns._ptLayoutDirty then ns._PT_Layout() end
    if PF.anchorDirty then ns.PF_ReAnchor() end
end

hooksecurefunc(ns, "FB_Apply", PF.ProbeChain)
hooksecurefunc(ns, "XF_Apply", PF.ProbeChain)

-- Target, pet and vehicle listeners; each is registered only while pets that need it are on screen
-- (PF.SyncShownEvents).
do
    local ev = ns.TakeShell()
    ev:SetScript("OnEvent", function(_, event, unit)
        if not db then return end
        if event == "PLAYER_TARGET_CHANGED" then
            PF.EachShown(PF.TargetFlip)
        else -- UNIT_PET / UNIT_ENTERED_VEHICLE / UNIT_EXITED_VEHICLE
            PF.OnPetChanged(unit)
        end
    end)
    PF.eventFrame = ev
end

end -- PF scope block

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

-- A nameList is a FILTER as much as an order: the secure header re-matches
-- every member's CURRENT name against the list on its own, in combat too,
-- and a member whose name is not listed is hidden outright. Names are not
-- stable: the UNKNOWNOBJECT placeholder stands in while a roster entry has
-- not populated yet (zoning, mid-loadscreen join) AND whenever a rename
-- effect resolves a unit to it mid-fight, when the attribute cannot be
-- rewritten. Every list therefore ends with the placeholder token, so a
-- member carrying it stays visible (sorted last) until the next rebuild
-- re-lists them under their real name. Builders skip in-set placeholders
-- (the token covers them) and bail to nil when a placeholder exists OUTSIDE
-- their set: the token would pull that member into a header that must not
-- show them, so the engine path (everyone visible, native order) runs until
-- names resolve. Pass the sorted member entries (each carrying .name).
-- noToken: per-group lists that cover EVERY separated header (Prioritize
-- Class, FrameSort) leave the token off -- it would pull a placeholder that
-- appears mid-fight into all of those headers at once; such a member waits
-- for the regen rebuild instead, and the builders drop a group whose own
-- roster holds a placeholder to its native path.
function ns._FinishNameList(members, noToken)
    local names = ns._nlBuf
    if names then wipe(names) else names = {}; ns._nlBuf = names end
    for i = 1, #members do names[i] = members[i].name end
    if not noToken then names[#names + 1] = UNKNOWNOBJECT end
    return table.concat(names, ",")
end

-- Reused member records and per-group buckets for the list builders, which
-- run on every LayoutGroups pass (options slider drags included). One builder
-- runs at a time and returns finished strings, so the pool is free again when
-- it returns; each builder writes every field its comparator reads.
function ns._NLRec(i)
    local pool = ns._nlPool
    if not pool then pool = {}; ns._nlPool = pool end
    local m = pool[i]
    if not m then m = {}; pool[i] = m end
    return m
end

function ns._NLGroups()
    local groups, bad = ns._nlGroups, ns._nlBad
    if groups then
        for g = 1, 8 do wipe(groups[g]) end
        wipe(bad)
    else
        groups, bad = {}, {}
        for g = 1, 8 do groups[g] = {} end
        ns._nlGroups, ns._nlBad = groups, bad
    end
    return groups, bad
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
        -- A nil name = roster not populated at all; the subgroup is not
        -- trustworthy either. Bail (see ns._FinishNameList).
        if not name then return nil end
        if subgroup == playerGroup then
            if name ~= UNKNOWNOBJECT then
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
        elseif name == UNKNOWNOBJECT then
            return nil
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
    return ns._FinishNameList(members)
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
            if not name then return nil end
            -- Every unit here is in the header's set: a placeholder name is
            -- covered by the trailing token (see ns._FinishNameList).
            if name ~= UNKNOWNOBJECT then
                if server and server ~= "" then name = name .. "-" .. server end
                local _, classToken = UnitClass(unit)
                members[#members + 1] = {
                    name = name,
                    rolePri = (rolePri and rolePri[EllesmereUI.UnitEffectiveRole(unit)]) or 99,
                    classPri = classPri[classToken] or 99,
                }
            end
        end
    end
    if #members == 0 then return nil end
    table.sort(members, function(a, b)
        if sortByRole and a.rolePri ~= b.rolePri then return a.rolePri < b.rolePri end
        if a.classPri ~= b.classPri then return a.classPri < b.classPri end
        return a.name < b.name
    end)
    return ns._FinishNameList(members)
end

-- Party header nameList for ARENA, where the header is bound to raid1-5.
-- showPlayer cannot exclude the player in a raid group and the static self
-- button cannot reorder them; a NAMELIST does both (Hide Self; Self
-- First/Last). Rest follow role order (ROLE mode) else raid index. Names come
-- from GetRaidRosterInfo (what the header matches against). Placeholder
-- names follow the ns._FinishNameList rules (a hidden self is out of set).
function ns._BuildArenaNameList(hideSelf, selfFirst, selfLast, sortByRole, roleOrder, onlyGroup)
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
        if not name then return nil end
        -- Small Raid mode: members outside the kept subgroup are simply not
        -- listed (the header hides them); the player included.
        if not (onlyGroup and subgroup ~= onlyGroup) then
            local unit = "raid" .. i
            local isPlayer = UnitIsUnit(unit, "player")
            if not (hideSelf and isPlayer) then
                if name ~= UNKNOWNOBJECT then
                    local rp = 99
                    if pri then rp = pri[EllesmereUI.UnitEffectiveRole(unit)] or 99 end
                    members[#members + 1] = {
                        name = name,
                        isPlayer = isPlayer,
                        rolePri = rp,
                        index = i,
                    }
                end
            elseif name == UNKNOWNOBJECT then
                return nil
            end
        elseif name == UNKNOWNOBJECT then
            -- Outside the kept subgroup: the token would pull them in.
            return nil
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
    return ns._FinishNameList(members)
end

-- Whole-raid nameList for Merge Groups + Self Position: player pinned first
-- (or last), everyone else in the active sort (role blocks in ROLE mode, raid
-- index otherwise). Replaces the flat header's groupFilter, so members of
-- groups hidden via Show Groups are simply not listed. Placeholder names
-- follow the ns._FinishNameList rules (hidden groups are out of set); the
-- caller falls back to the engine path on a bail.
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
        if not name then return nil end
        if not visibleGroups or visibleGroups[subgroup] ~= false then
            if name ~= UNKNOWNOBJECT then
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
        elseif name == UNKNOWNOBJECT then
            return nil
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
    return ns._FinishNameList(members)
end

-------------------------------------------------------------------------------
--  Raid Prioritize Class lists: role (Sort By = Role) -> class (the Class
--  Order list) -> name, the same order as the party header's
--  ns._BuildPartyClassNameList, with Self Position pinning the player first
--  or last. Group sort + Prioritize Class needs no list at all (the headers'
--  own CLASS grouping gives this order and stays live in combat, see
--  ApplySortToHeaders); lists serve Role + Class (a header groups by one key
--  only), Self Position's group, and merged mode. Separated mode returns one
--  list per subgroup, without the placeholder token (see ns._FinishNameList),
--  and leaves out any group whose roster holds a placeholder (native path).
--  onlyGroup (Self Position's one header) and merged mode return a single
--  list WITH the token, under the ns._FinishNameList rules: a placeholder in
--  the set rides the token, one outside it bails. Names come from
--  GetRaidRosterInfo (what the header matches against).
-------------------------------------------------------------------------------
function ns._RCLess(a, b)
    -- Exactly one of a/b is the player here, so the XOR with the Self Last
    -- flag sends them to the top (Self First) or the bottom (Self Last).
    if a.isPlayer ~= b.isPlayer then return a.isPlayer ~= ns._rcSelfLast end
    if a.rolePri ~= b.rolePri then return a.rolePri < b.rolePri end
    if a.classPri ~= b.classPri then return a.classPri < b.classPri end
    return a.name < b.name
end

function ns._BuildRaidClassLists(merged, visibleGroups, sortByRole, roleOrder, classOrder, selfFirst, selfLast, onlyGroup)
    if not IsInRaid() then return nil end
    local classPri = ns._rcClassPri
    if classPri then wipe(classPri) else classPri = {}; ns._rcClassPri = classPri end
    for i, c in ipairs(classOrder or ns._GetDefaultClassOrder()) do classPri[c] = i end
    local rolePri = ns._rcRolePri
    if rolePri then wipe(rolePri) else rolePri = {}; ns._rcRolePri = rolePri end
    if sortByRole then
        for i, r in ipairs(roleOrder) do rolePri[r] = i end
    end
    ns._rcSelfLast = selfLast == true
    local pin = (selfFirst or selfLast) and true or false
    local tok = ns._FsRaidTok()
    local groups, bad = ns._NLGroups()
    local used = 0
    local n = GetNumGroupMembers()
    for i = 1, n do
        local name, _, subgroup, _, _, classToken = GetRaidRosterInfo(i)
        if not name or not subgroup then return nil end
        local skip = (merged and visibleGroups and visibleGroups[subgroup] == false)
            or (onlyGroup ~= nil and subgroup ~= onlyGroup)
        if name == UNKNOWNOBJECT then
            if merged or onlyGroup then
                -- One header carrying the token: a placeholder in its set
                -- rides it, one outside would be pulled in.
                if skip then return nil end
            elseif not skip then
                bad[subgroup] = true
            end
        elseif not skip then
            used = used + 1
            local m = ns._NLRec(used)
            local unit = tok[i]
            m.name = name
            m.isPlayer = pin and UnitIsUnit(unit, "player") == true
            m.rolePri = (sortByRole and rolePri[EllesmereUI.UnitEffectiveRole(unit)]) or 99
            m.classPri = classPri[classToken] or 99
            local g = groups[merged and 1 or subgroup]
            g[#g + 1] = m
        end
    end
    if merged then
        local list = groups[1]
        if #list == 0 then return nil end
        table.sort(list, ns._RCLess)
        return ns._FinishNameList(list)
    end
    if onlyGroup then
        local list = groups[onlyGroup]
        if not list or #list == 0 then return nil end
        table.sort(list, ns._RCLess)
        return ns._FinishNameList(list)
    end
    local out = ns._rcOut
    if out then wipe(out) else out = {}; ns._rcOut = out end
    for g = 1, 8 do
        local list = groups[g]
        if #list > 0 and not bad[g] then
            table.sort(list, ns._RCLess)
            out[g] = ns._FinishNameList(list, true)
        end
    end
    return out
end

-------------------------------------------------------------------------------
--  FrameSort provider (compatibility shim for the FrameSort addon). With
--  Sort By = FrameSort the headers take their order from FrameSort's sorted
--  friendly unit list through a nameList built from OUR roster: every member
--  a header shows is listed (a nameList is a filter), members the list does
--  not rank sort last by index, and the ns._FinishNameList placeholder rules
--  apply. FrameSort never reads or moves our frames (self-managed provider);
--  its list is read in place, never modified. Everything below costs nothing
--  unless the mode is picked, and nothing at all when FrameSort is absent.
-------------------------------------------------------------------------------
function ns._FrameSortApi()
    local api = _G.FrameSortApi
    api = api and api.v3
    if api and api.Sorting and api.Sorting.GetFriendlyUnits then return api end
    return nil
end

-- The party mode is live only while FrameSort is loaded: a saved choice with
-- the addon gone runs the native order, and the self button keeps its job.
function ns._FsPartyMode()
    local p = db and db.profile
    return p ~= nil and (p.partySortMode or p.sortMode) == "FRAMESORT" and ns._FrameSortApi() ~= nil
end

-- rank[token] = position in FrameSort's list, players only (pets and the
-- tank-target tokens are not header members), in a reused map. nil when
-- FrameSort is absent or the list ranks no player. `fresh` drops FrameSort's
-- cache first: our own roster handlers can run before its invalidation and
-- would otherwise read the previous roster's order.
function ns._FrameSortRanks(fresh)
    local api = ns._FrameSortApi()
    if not api then return nil end
    if fresh and api.Caching and api.Caching.Invalidate then api.Caching:Invalidate() end
    local units = api.Sorting:GetFriendlyUnits()
    if type(units) ~= "table" then return nil end
    local ok = ns._fsTokenOK
    if not ok then
        ok = { player = true }
        for i = 1, 4 do ok["party" .. i] = true end
        for i = 1, 40 do ok["raid" .. i] = true end
        ns._fsTokenOK = ok
    end
    local rank = ns._fsRank
    if rank then wipe(rank) else rank = {}; ns._fsRank = rank end
    local n = 0
    for i = 1, #units do
        local tok = units[i]
        if type(tok) == "string" and ok[tok] and not rank[tok] then
            n = n + 1
            rank[tok] = n
        end
    end
    if n == 0 then return nil end
    return rank
end

function ns._FsMemberLess(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.index < b.index
end

function ns._FsRaidTok()
    local tok = ns._raidTok
    if not tok then
        tok = {}
        for i = 1, 40 do tok[i] = "raid" .. i end
        ns._raidTok = tok
    end
    return tok
end

-- Raid: separated mode returns one nameList per subgroup, without the
-- placeholder token (see ns._FinishNameList); a group missing from the result
-- (none of its members listed, or a placeholder in its roster) keeps the
-- native path. Merged mode returns the whole-raid list for the visible groups:
-- a placeholder in a hidden group bails, one in a visible group rides the
-- token. Names come from GetRaidRosterInfo (what the header matches against).
function ns._BuildFrameSortRaidLists(rank, merged, visibleGroups)
    if not IsInRaid() then return nil end
    local tok = ns._FsRaidTok()
    local groups, bad = ns._NLGroups()
    local used = 0
    local n = GetNumGroupMembers()
    for i = 1, n do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if not name or not subgroup then return nil end
        local hidden = merged and visibleGroups and visibleGroups[subgroup] == false
        if name == UNKNOWNOBJECT then
            if merged then
                if hidden then return nil end
            else
                bad[subgroup] = true
            end
        elseif not hidden then
            used = used + 1
            local m = ns._NLRec(used)
            m.name, m.rank, m.index = name, rank[tok[i]] or 99, i
            local g = groups[merged and 1 or subgroup]
            g[#g + 1] = m
        end
    end
    if merged then
        local list = groups[1]
        if #list == 0 then return nil end
        table.sort(list, ns._FsMemberLess)
        return ns._FinishNameList(list)
    end
    local out = ns._fsGroupLists
    if out then wipe(out) else out = {}; ns._fsGroupLists = out end
    for g = 1, 8 do
        local list = groups[g]
        if #list > 0 and not bad[g] then
            table.sort(list, ns._FsMemberLess)
            out[g] = ns._FinishNameList(list, true)
        end
    end
    return out
end

-- Party header on party units: the same UnitName + "-realm" form as
-- ns._BuildPartyClassNameList. Names can be secret in restricted content:
-- a secret or missing name bails to the native path.
function ns._BuildFrameSortPartyNameList(rank, includePlayer)
    if not IsInGroup() then return nil end
    local members = {}
    for i = includePlayer and 0 or 1, 4 do
        local unit = (i == 0) and "player" or ("party" .. i)
        if UnitExists(unit) then
            local name, server = UnitName(unit)
            if (issecretvalue and (issecretvalue(name) or issecretvalue(server)))
                or type(name) ~= "string" then
                return nil
            end
            if name ~= UNKNOWNOBJECT then
                if server and server ~= "" then name = name .. "-" .. server end
                members[#members + 1] = { name = name, rank = rank[unit] or 99, index = i }
            end
        end
    end
    if #members == 0 then return nil end
    table.sort(members, ns._FsMemberLess)
    return ns._FinishNameList(members)
end

-- Party header bound to raid units (arena, Small Raid): the arena builder's
-- membership rules (Hide Self, one kept subgroup) in FrameSort's order.
function ns._BuildFrameSortRaidPartyNameList(rank, hideSelf, onlyGroup)
    if not IsInRaid() then return nil end
    local tok = ns._FsRaidTok()
    local members = {}
    local n = GetNumGroupMembers()
    for i = 1, n do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if not name then return nil end
        if not (onlyGroup and subgroup ~= onlyGroup) then
            local unit = tok[i]
            if not (hideSelf and UnitIsUnit(unit, "player")) then
                if name ~= UNKNOWNOBJECT then
                    members[#members + 1] = { name = name, rank = rank[unit] or 99, index = i }
                end
            elseif name == UNKNOWNOBJECT then
                return nil
            end
        elseif name == UNKNOWNOBJECT then
            -- Outside the kept subgroup: the token would pull them in.
            return nil
        end
    end
    if #members == 0 then return nil end
    table.sort(members, ns._FsMemberLess)
    return ns._FinishNameList(members)
end

-- FrameSort's sort request (and its settings-changed callback): re-apply the
-- headers from its list. Out of combat only (attribute writes); a request in
-- combat rides the regen flush. Returns whether any header attribute changed,
-- which FrameSort's post-sort callbacks key on.
function ns._FrameSortApply()
    -- Zero cost unless the mode is picked (FrameSort calls in on its own runs
    -- and settings edits whatever our choice).
    local p = db and db.profile
    if not (p and (p.sortMode == "FRAMESORT" or (p.partySortMode or p.sortMode) == "FRAMESORT")) then
        return false
    end
    if InCombatLockdown() then
        ns._rosterDirtyInCombat = true
        return false
    end
    if not ns._FrameSortApi() then return false end
    ns._fsChanged = false
    ns._fsFromProvider = true
    if ns._raidFramesVisible and ns._ApplySortToHeaders then ns._ApplySortToHeaders() end
    if ns._partyFramesVisible and ns._LayoutPartyFrames then ns._LayoutPartyFrames() end
    ns._fsFromProvider = nil
    return ns._fsChanged == true
end

-- Registers once FrameSort's API exists (FrameSort loads after this addon).
-- A provider registered before FrameSort's own init is asked for Init, so
-- one is supplied; Containers is read on every provider at combat start.
-- Name is spliced into a secure attribute key and Enabled is written as an
-- attribute value, so both return plain values only.
function ns._FrameSortRegister()
    if ns._fsRegistered then return end
    local api = ns._FrameSortApi()
    if not (api and api.Sorting.RegisterFrameProvider) then return end
    local none = {}
    local provider = {
        Name = function() return "EllesmereUI" end,
        Enabled = function()
            local p = db and db.profile
            return p ~= nil and (p.sortMode == "FRAMESORT" or (p.partySortMode or p.sortMode) == "FRAMESORT")
        end,
        IsVisible = function()
            return ns._raidFramesVisible == true or ns._partyFramesVisible == true
        end,
        IsSelfManaged = true,
        Containers = function() return none end,
        Init = function() end,
        Sort = function() return ns._FrameSortApply() end,
    }
    if api.Sorting:RegisterFrameProvider(provider) then
        ns._fsRegistered = true
        if api.Options and api.Options.RegisterConfigurationChangedCallback then
            api.Options:RegisterConfigurationChangedCallback(function() ns._FrameSortApply() end)
        end
    end
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
    -- A raid set the group state hides takes no nameList (FrameSort, Role +
    -- Class, Self Position): a nameList is also a filter, and the visibility
    -- driver can show the set mid-fight, when no list can be rebuilt, so a stale
    -- list would drop every member it does not name. The shown pass applies them.
    local live = ns._RFVisWanted()
    -- Sort By = FrameSort: its list owns the order (Self Position included);
    -- with FrameSort absent, or no list yet, the Group sort runs (Prioritize
    -- Class and Self Position included).
    local fsRank = live and (s.sortMode == "FRAMESORT") and ns._FrameSortRanks(not ns._fsFromProvider) or nil
    -- Prioritize Class (FrameSort's list wins). Group sort + class runs on the
    -- headers' own CLASS grouping (Class Order, then name), so membership
    -- stays live in combat. A header groups by one key only, so Role + Class
    -- takes nameLists on every header instead: like Self Position's list, a
    -- member who joins mid-fight appears at the regen rebuild.
    local classOn = s.prioritizeClass == true and not fsRank and IsInRaid()
    local classNative = classOn and not sortByRole
    local classLists = live and classOn and sortByRole
    local selfOn = live and (s.showSelfFirst or s.showSelfLast) and IsInRaid()
    local selfLast = s.showSelfLast

    local baseGroupBy, baseSortMethod, baseGroupingOrder
    if classNative then
        baseGroupBy = "CLASS"
        baseSortMethod = "NAME"
        baseGroupingOrder = table.concat(s.classOrder or ns._GetDefaultClassOrder(), ",")
    else
        baseGroupBy = sortByRole and "ASSIGNEDROLE" or nil
        baseSortMethod = sortByRole and "NAME" or "INDEX"
        baseGroupingOrder = sortByRole and (table.concat(roleOrder, ",") .. ",NONE") or ""
    end

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
            ns._fsChanged = true
            -- Hide/Show makes a shown header re-read the set; one LayoutGroups
            -- hid (a hidden or empty group, the idle flat header) stays hidden
            -- and reads it when LayoutGroups shows it.
            local shown = hdr:IsShown()
            if shown then hdr:Hide() end
            hdr:SetAttribute("groupFilter", gf)
            hdr:SetAttribute("groupBy", gb)
            hdr:SetAttribute("sortMethod", sm)
            hdr:SetAttribute("groupingOrder", go)
            hdr:SetAttribute("nameList", nl)
            if shown then hdr:Show() end
        end
    end

    if s.mergeGroups and ns._flatHeader then
        -- Self Position in merged mode: a whole-raid nameList owns the order
        -- (player pinned, rest by the active sort), so groupFilter must be
        -- CLEARED -- the list itself only names visible groups' members --
        -- and groupBy nil so the list order is what the header uses (same
        -- combo as the non-merged player's-group path). While names are
        -- unresolved (builder bailed) the engine path runs instead, with
        -- LayoutGroups' groupFilter restored from ns._flatGfStr. FrameSort
        -- mode and Prioritize Class (Role + Class, or with Self Position) use
        -- the same whole-raid list shape; Group + Class alone runs native.
        local mergedList
        if fsRank then
            mergedList = ns._BuildFrameSortRaidLists(fsRank, true, ns._VisibleGroups())
        end
        if not mergedList and (classLists or (classNative and selfOn)) then
            mergedList = ns._BuildRaidClassLists(true, ns._VisibleGroups(), sortByRole, roleOrder,
                s.classOrder, s.showSelfFirst, selfLast)
        end
        if not mergedList and selfOn then
            mergedList = ns._BuildMergedSelfNameList(sortByRole, roleOrder, selfLast, ns._VisibleGroups())
        end
        if mergedList then
            applySortTo(ns._flatHeader, nil, "NAMELIST", "", mergedList, nil)
        else
            applySortTo(ns._flatHeader, baseGroupBy, baseSortMethod, baseGroupingOrder, nil,
                ns._flatGfStr or ns._flatHeader:GetAttribute("groupFilter"))
        end
    else
        local groupLists
        if fsRank then
            groupLists = ns._BuildFrameSortRaidLists(fsRank, false)
        elseif classLists then
            groupLists = ns._BuildRaidClassLists(false, nil, true, roleOrder,
                s.classOrder, s.showSelfFirst, selfLast)
        end
        -- Self Position: the player's group takes a player-pinned nameList
        -- (Class Order under Group + Class) whenever no per-group list covers
        -- it -- also the fallback while a list builder waits on names.
        local playerGroup = selfOn and ns._GetPlayerSubgroup() or nil
        if playerGroup and groupLists and groupLists[playerGroup] then playerGroup = nil end
        local selfNameList
        if playerGroup then
            if classOn then
                selfNameList = ns._BuildRaidClassLists(false, nil, sortByRole, roleOrder,
                    s.classOrder, s.showSelfFirst, selfLast, playerGroup)
            end
            selfNameList = selfNameList or ns._BuildSelfFirstNameList(playerGroup, sortByRole, roleOrder, selfLast)
            if not selfNameList then playerGroup = nil end
        end
        for group = 1, 8 do
            local hdr = separatedHdrs[group]
            if not hdr then break end
            local groupList = groupLists and groupLists[group]
            if groupList then
                applySortTo(hdr, nil, "NAMELIST", "", groupList, nil)
            elseif playerGroup and group == playerGroup then
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

    -- A header makes children only while visible (IsVisible walks the parent
    -- chain): a set built with the container hidden (a Merge Groups flip while
    -- solo or in a party) shows the container around the pre-spawn below.
    local hid = not containerFrame:IsShown()
    if hid then containerFrame:Show() end

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
    if hid then containerFrame:Hide() end

    -- Freshly built headers need the current sort attributes.
    ApplySortToHeaders()
end

local function CreateHeaders()
    if containerFrame then return end

    local s = db.profile

    -- Container frame for positioning (not secure, just holds headers)
    containerFrame = CreateFrame("Frame", "EllesmereUIRaidFrameContainer", UIParent)
    ns._PreviewBind(db, PP, containerFrame)
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
--  unitGrowth (where next unit within a group goes). groupGrowth also accepts
--  the grid flow "DOWNRIGHT" (ns._RFGroupFlow): ns._RF_GRID_ROWS groups stack
--  down one column before the next column starts to the right, instead of one
--  continuous run.
-------------------------------------------------------------------------------
local MOVER_GROUPS = 4

-- The separated layout's group slot origins, refilled by every pass
-- (ns._RFGroupFlow's out table).
local groupFlowSlots = {}

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
    local vg = ns._VisibleGroups() or { true, true, true, true, true, true, false, false }
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
    local vg = ns._VisibleGroups() or { true, true, true, true, true, true, false, false }
    -- Whether this layout applied the Mythic cap (the zone and difficulty checks compare against it).
    ns._rfLaidMythic = vg == ns._mythicGroups

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
            -- nameList bails on unresolved names. Role + Prioritize Class and
            -- Sort By = FrameSort own it the same way.
            ns._flatGfStr = gfStr
            local selfOwnsHeader = (s.showSelfFirst or s.showSelfLast
                or (s.prioritizeClass == true and s.sortMode == "ROLE")
                or s.sortMode == "FRAMESORT") and IsInRaid()
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

        -- Group slot origins along the growth flow: a plain direction is one
        -- continuous run, the grid flow ("Down and then Right") stacks
        -- ns._RF_GRID_ROWS groups per column. Eight slots are generated (up to
        -- 8 visible groups) but only the four the box is sized for
        -- (MOVER_GROUPS) set the normalization origin, so a group past the box
        -- keeps the same per-slot step instead of rescaling everything in front
        -- of it.
        local slots, minX, maxY = ns._RFGroupFlow(groupGrowth, groupW, groupH, gs, 8, groupFlowSlots)

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
        -- Skipped while the group state hides the set too: a hidden header
        -- ignores the roster, so one hidden here would stay empty if the
        -- visibility driver shows the set mid-fight (the shown pass collapses).
        local occupied
        if s.hideEmptyGroups ~= false and IsInRaid() and ns._RFVisWanted() then
            occupied = {}
            for ri = 1, GetNumGroupMembers() or 0 do
                local _, _, sub = GetRaidRosterInfo(ri)
                if sub then occupied[sub] = true end
            end
        end

        local visSlot = 0  -- running counter for visible groups (collapses gaps)
        local groupOrder = s.customGroupOrder and ns._RFValidatedGroupOrder(s.groupOrder)
        for slot = 1, 8 do
            local group = groupOrder and groupOrder[slot] or slot
            local hdr = separatedHdrs[group]
            if hdr then
                if vg[group] == false or (occupied and not occupied[group]) then
                    if hdr:IsShown() then hdr:Hide() end
                else
                    local x = PixelSnap(slots[visSlot][1] - minX + hdrOffX)
                    local y = PixelSnap(slots[visSlot][2] - maxY + hdrOffY)
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
    -- Which layout the headers now carry (shown: full; hidden: native), for
    -- UpdateVisibility to re-lay them when the set shows or hides.
    ns._rfRaidLaidVis = ns._RFVisWanted()

    -- Container size for unlock mode's mover. Merged mode's
    -- columnAnchorPoint is always perpendicular to unitGrowth (colAnchor above),
    -- so its actual render axis follows unitGrowth, not the literal groupGrowth
    -- (which can share unitGrowth's axis; Blizzard's header can't express that as
    -- a column direction). Keying the box off groupGrowth there mismatches the
    -- box against what merged mode really renders. Separated mode has no such
    -- header constraint and renders along groupGrowth literally, so it reads the
    -- same formula every other size consumer uses (ns._RFFootprint).
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
        totalW, totalH = ns._RFFootprint(bw, bh, unitGrowth, groupGrowth, cs, gs)
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
    -- Hide Groups 5-8 in Mythic Raid hears difficulty switches only while on.
    if db.profile.mythicRaidHideGroups then eventFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
    else eventFrame:UnregisterEvent("PLAYER_DIFFICULTY_CHANGED") end
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
        LayoutTopNameBar(s, bh, powerH, d.health, d.topNameBar, d.topNameBarBg, d.topNameBarText, d.power)
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

        -- Power text (exists once a mode has needed it): hidden with the bar above until
        -- UpdateAllButtons below shows it again, and restyled.
        if d.powerText then
            d.powerText:Hide(); d._pwtMode = nil
            ApplyFont(d.powerText, s.powerTextSize or 8)
            ns._RFAnchorPowerText(d)
        end

        -- Level text (exists once a position has needed it): restyled; the full paint
        -- that follows shows or hides it by position.
        if d.levelText then
            ApplyFont(d.levelText, s.levelTextSize or 10)
            ns._RFAnchorLevelText(d)
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
        if ns.RF_FvMissingAnchor then ns.RF_FvMissingAnchor(btn, d) end

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
    -- Pet frames (the ones styled from the raid settings restyle here, the rest in the party
    -- reload): the login window's pass skips them (OnEnable builds them once the party frames
    -- exist, which the Beside Owner pets need).
    if not skipButtons then ns.PF_Apply(true) end

    -- 12.1 aura containers reload with every real pass (direct call inside
    -- the body -- immune to the Options file's setup-time capture of ns.ReloadFrames).
    if ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
end

ns.ReloadFrames = ReloadFrames
ns.PixelSnap = PixelSnap
ns._allButtons = allButtons
-- The raid unit map (RebuildUnitMap wipes it in place, so this stays live).
ns._raidUnitToButton = unitToButton

-- Global Dark Mode master: RF stores Dark Mode as a fill-color MODE
-- (healthColorMode == "dark"), not a boolean -- enabling remembers the prior
-- mode, disabling restores it, never clobbering a Classic/Custom choice. The
-- party override (party_healthColorMode, present only when the party color
-- section is decoupled) flips the same way. db is set at PLAYER_LOGIN; the
-- closures read it lazily.
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
            -- The party target frames' own Fill Color flips the same way.
            if p.partyTargetHealthColorMode ~= "dark" then
                p._darkPrevPartyTargetHealthColorMode = p.partyTargetHealthColorMode or "class"
                p.partyTargetHealthColorMode = "dark"
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
            if p.partyTargetHealthColorMode == "dark" then
                p.partyTargetHealthColorMode = p._darkPrevPartyTargetHealthColorMode or "class"
            end
            p._darkPrevPartyTargetHealthColorMode = nil
        end
        if ns.ReloadFrames then ns.ReloadFrames() end
        if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
    end,
})

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
    -- The bars' width: an attached portrait takes its share of the box.
    local _, _, _, pres = ns.RF_PartyDims(s)
    local barW = bw - ((pres and pres > 0) and PixelSnap(pres) or 0)
    for _, btn in ipairs(ns._partyAllButtons) do
        local d = GetFFD(btn)
        if d.styled then
            btn:SetSize(bw, bh)
            if d.kit then
                -- Party Frames kit: its own bar rects, spots and name width
                -- (Frame Scale drags land here).
                ns.RF_ApplyPartyKit(btn, d, ns._scaledPartyProxy)
            else
                -- Use full height if power bar is hidden for this button's role; the
                -- Top Name Bar always reserves topBarH from the top.
                if d.health then
                    local hh = ((d.power and d.power:IsShown()) and healthH or bh) - topBarH
                    d.health:SetHeight(hh)
                end
                if d.nameText then d.nameText:SetWidth(barW * ns.RF_NAME_WIDTH_FRACTION) end
                -- Party portrait: the attached square follows the height.
                if d.pt then ns.RF_PtApply(btn, d, ns._scaledPartyProxy, bw, bh, nil) end
            end
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
                if d.powerText then ApplyFont(d.powerText, pp.powerTextSize or 8) end
                if d.levelText then ApplyFont(d.levelText, pp.levelTextSize or 10) end
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
        local _, _, pcs = ns.RF_PartyDims(s)
        ns._PositionPartySlots(bw, bh, PixelSnap(pcs) + ns.PT_AlongPitch(s), ns._PartyGrowth(s))
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

-- Groups stacked in one column before the flow steps to the next column, for
-- the grid group growth ("Down and then Right"): G1/G2 fill the first column
-- top to bottom, G3/G4 the column to its right. Fixed at 2 so a 20-man raid
-- lands on the classic 2x2 block; a plain direction is the same flow with one
-- group per column (every other value below).
ns._RF_GRID_ROWS = 2

-- Group slot origins (relative to the growth corner, before normalization) for a
-- group growth direction, plus the origin those slots normalize against (min x,
-- max y) so slot 0 always sits at the growth corner whichever way the flow runs.
-- THE single copy of the per-slot step math -- the live layout, the 20-player
-- preview and the size preview all place groups through it, so they cannot drift.
-- `count` slots are generated (LayoutGroups can place up to 8 visible groups
-- into the 4-group box) but only the first MOVER_GROUPS of them -- what the box
-- is actually sized for -- set the origin, so a group past the box keeps the
-- same per-slot step instead of rescaling the box in front of it. `out`, when
-- given, is refilled in place (its slot pairs reused) and returned instead of a
-- new table.
ns._RFGroupFlow = function(groupGrowth, groupW, groupH, gs, count, out)
    local n = count or MOVER_GROUPS
    local stepX, stepY = 0, 0
    if groupGrowth == "DOWNRIGHT" then
        -- Column advance is horizontal; the rows inside a column run down.
        stepX, stepY = (groupW + gs), -(groupH + gs)
    elseif groupGrowth == "DOWN" then   stepY = -(groupH + gs)
    elseif groupGrowth == "UP" then     stepY =  (groupH + gs)
    elseif groupGrowth == "RIGHT" then  stepX =  (groupW + gs)
    else                                stepX = -(groupW + gs)   -- LEFT
    end
    local slots, minX, maxY = out or {}, 0, 0
    for i = 0, n - 1 do
        local px, py
        if groupGrowth == "DOWNRIGHT" then
            px = floor(i / ns._RF_GRID_ROWS) * stepX
            py = (i % ns._RF_GRID_ROWS) * stepY
        else
            px, py = i * stepX, i * stepY
        end
        local p = slots[i]
        if p then
            p[1], p[2] = px, py
        else
            slots[i] = { px, py }
        end
    end
    local nc = min(MOVER_GROUPS, n)
    for i = 0, nc - 1 do
        local px, py = slots[i][1], slots[i][2]
        if px < minX then minX = px end
        if py > maxY then maxY = py end
    end
    return slots, minX, maxY
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
    if groupGrowth == "DOWNRIGHT" then
        -- Grid flow: one column of ns._RF_GRID_ROWS groups, then the next
        -- column to its right (see ns._RFGroupFlow). MOVER_GROUPS (4) fills
        -- two columns at any row count that divides it.
        local rows = ns._RF_GRID_ROWS
        local cols = floor((MOVER_GROUPS + rows - 1) / rows)
        return PixelSnap(cols * groupW + (cols - 1) * gs),
               PixelSnap(rows * groupH + (rows - 1) * gs)
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
-- Growth dropdown, which deliberately lets Unit Growth win instead. Also maps the
-- grid flow ("Down and then Right") onto the single column axis the flat header
-- can render; no-op if not merged.
ns._RFEffectiveGrowth = function(unitGrowth, groupGrowth, merged)
    if not merged then return unitGrowth, groupGrowth end
    -- The grid flow needs two axes; Blizzard's flat header only has one column
    -- axis, so merged mode degrades it to the plain RIGHT run it CAN render --
    -- same shape as the same-axis fallback below.
    if groupGrowth == "DOWNRIGHT" then groupGrowth = "RIGHT" end
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
-- (merged=false is a no-op for _RFEffectiveGrowth), where every combination of the two
-- axes is legitimate -- including the grid flow, whose column advance is horizontal (so
-- it pins LEFT like RIGHT) and whose rows run down (so it pins TOP like DOWN). This
-- tie-break (UP beats BOTTOM, LEFT beats RIGHT, default TOP+LEFT) is what existing
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

-- Apply tier-based position to the container frame. The active tier's 4-group
-- footprint pins its growth-derived corner (ns._RFGrowthCorner, from the tier's
-- EFFECTIVE unit + group growth) at the BASE (20-man) footprint's same corner, plus the tier's saved
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
    -- A 3D party portrait does not take the button's alpha: mirror it.
    if d.pt and d.pt._3dOn then ns.RF_PtModelAlpha(d, bmA * rangeAlpha) end
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
    local d = GetFFD(btn)
    d.rangeAlpha = nil
    -- A 3D party portrait does not take the button's alpha: mirror it.
    if d.pt and d.pt._3dOn then ns.RF_PtModelAlphaSecret(d, inRange, bmA * inAlpha, bmA * outAlpha) end
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
        -- Ghost units need to be checked using a rez-spell because UnitInRange checks the ghost's range, not the corpse's.
        -- We want to provide rez-range feedback based on the corpse's position.
        if playerHasRez then
            local r = C_Spell_IsSpellInRange(playerRezSpell, unit)
            if r == true then
                ApplyRangeAlpha(btn, 1)
            elseif r == false then
                ApplyRangeAlpha(btn, oorAlpha)
            else
                -- Use the standard ~40yd interact range (UnitInRange) as fallback
                ApplyRangeAlphaSecret(btn, UnitInRange(unit), 1, oorAlpha)
            end
        else
            -- Use the standard ~40yd interact range (UnitInRange) when player has no rez spell
            ApplyRangeAlphaSecret(btn, UnitInRange(unit), 1, oorAlpha)
        end
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
    ns._PF_RangeSeed()
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
--  the assist gate uses on its own false->true edge). The same pass audits each
--  container's own unit binding, which nothing else re-drives once the header
--  stops re-asserting the token.
-------------------------------------------------------------------------------
local ghostTicker = nil

local function GhostAuraCheck()
    local function checkUnit(unit, btn)
        local d = GetFFD(btn)
        -- unitToButton et al. only ever gain entries on reassignment, never drop
        -- the old one, so unit/btn here can be a stale pairing; re-confirm against
        -- the button's own live attribute before writing to it.
        if btn:GetAttribute("unit") == unit and ns.RFC_RepointStale then
            ns.RFC_RepointStale(d, unit)
        end
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

-- Party frames while IsInRaid() is true: arena (the whole team, above) or the
-- opt-in Small Raid setting, which shows group 1 as party frames and hides
-- every other member while the raid holds fewer than 10 players. Every
-- "party or raid frames" decision reads this, never ns._InArena directly;
-- the group-1 filter itself lives in _LayoutPartyFrames (ns._SmallRaidGroup).
ns._PartyInRaid = function()
    if ns._InArena() then return true end
    return db.profile.partySmallRaid == true and IsInRaid() and GetNumGroupMembers() < 10
end

-- The subgroup the party header is limited to in Small Raid mode; nil in
-- arena (whole team) and outside party-in-raid mode.
ns._SmallRaidGroup = function()
    if ns._InArena() or not ns._PartyInRaid() then return nil end
    return 1
end

-- Which set the group state shows (raid, party): raid frames in a raid, party
-- frames in a party (arena and Small Raid included), each set's Show When Solo
-- outside a group. ns._RF_VIS_MACROS spells the same rule as macro conditions.
ns._RFVisWanted = function()
    local s = db.profile
    if not IsInGroup() then
        return s.showWhenSolo and true or false, s.partyShowWhenSolo and true or false
    end
    if IsInRaid() and not ns._PartyInRaid() then return true, false end
    return false, true
end

-- Secure visibility drivers on both containers: the containers are implicitly
-- protected (secure headers inside), so only secure code can show or hide them
-- in combat, and a driver re-checks its macro every 0.2 s on its own. A group
-- joined, or a party turned raid, mid-fight then shows its frames at once.
-- Macro per [mode][that set's Show When Solo]; the mode is fixed out of combat.
-- Group state reads unit existence: the [group] conditions keep the state from
-- before combat until combat ends, so a group joined mid-fight reads as solo
-- there, while unit tokens follow the roster at once. raid1 exists exactly in
-- a raid; party1 in a party with another member; [group] stays OR'd in so a
-- group with no other member counts as grouped, as IsInGroup() does.
-- Small Raid: raid tokens run contiguously from raid1 and exist only in a raid,
-- so raid10 exists exactly when a raid holds 10 or more members (the
-- GetNumGroupMembers() < 10 rule); a party never reaches it.
-- Arena has no macro condition: it is taken at the zone-in pass.
ns._RF_VIS_MACROS = {
    raid = {
        group = { [true] = "[@raid1,exists] show; [@party1,exists][group] hide; show", [false] = "[@raid1,exists] show; hide" },
        small = { [true] = "[@raid10,exists] show; [@raid1,exists][@party1,exists][group] hide; show", [false] = "[@raid10,exists] show; hide" },
        arena = { [true] = "[@raid1,exists][@party1,exists][group] hide; show", [false] = "hide" },
    },
    party = {
        group = { [true] = "[@raid1,exists] hide; show", [false] = "[@raid1,exists] hide; [@party1,exists][group] show; hide" },
        small = { [true] = "[@raid10,exists] hide; show", [false] = "[@raid10,exists] hide; [@raid1,exists][@party1,exists][group] show; hide" },
        arena = { [true] = "show", [false] = "[@raid1,exists][@party1,exists][group] show; hide" },
    },
}

-- Registers each container's macro, only when its text changes (driver
-- registration is a protected action: out of combat, or the login window).
ns._RFSyncVisDrivers = function()
    local pc = ns._partyContainerFrame
    if not containerFrame or not pc or InCombatLockdown() then return end
    local s = db.profile
    local M = ns._RF_VIS_MACROS
    local mode = (ns._InArena() and "arena") or ((s.partySmallRaid == true) and "small") or "group"
    local r = M.raid[mode][s.showWhenSolo and true or false]
    local p = M.party[mode][s.partyShowWhenSolo and true or false]
    if ns._rfRaidVisMacro ~= r then
        RegisterStateDriver(containerFrame, "visibility", r)
        ns._rfRaidVisMacro = r
    end
    if ns._rfPartyVisMacro ~= p then
        RegisterStateDriver(pc, "visibility", p)
        ns._rfPartyVisMacro = p
    end
end

-- A set that hides keeps its buttons' units (a hidden header ignores the
-- roster) while its events stop routing: forget each painted occupant so the
-- next assignment, in combat too, takes the full repaint.
ns._RFForgetOccupants = function(list)
    for i = 1, #list do
        local d = FFD[list[i]]
        if d then d._lastGuid = nil end
    end
end

local function UpdateVisibility()
    if not containerFrame then return end
    if InCombatLockdown() then return end

    -- Preview overrides all visibility logic -- real buttons stay suppressed
    -- (alpha), no state changes; the preview close re-runs this.
    if previewActive then return end

    -- Defensive: re-assert full opacity unless a preview is intentionally
    -- dimming the real frames. The preview system is the only thing that lowers
    -- container alpha; this runs out of combat only (the function bails in combat
    -- above) and heals any case where alpha was left at 0 with the flags cleared.
    -- Gated on the party-preview flag too so a raid-visibility recompute never
    -- un-hides the raid container behind an active party preview.
    if not ns._sizePreviewTier and not ns._partyPvActive then containerFrame:SetAlpha(1) end

    local s = db.profile
    -- Arena and Small Raid mode hide the raid frames. The player is in a raid
    -- group there, but we show our party frames instead (see
    -- _UpdatePartyVisibility), so the raid container must stay hidden even
    -- though IsInRaid() returns true.
    local visible = ns._RFVisWanted()
    local wasVisible = framesVisible
    framesVisible = visible
    ns._raidFramesVisible = visible  -- mirror for readers outside this file (the FrameSort provider)
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

    -- The driver decides the same way; synced first so the two agree this frame
    -- (readers such as the tier offset check IsShown right after).
    ns._RFSyncVisDrivers()
    containerFrame:SetShown(visible)
    if visible then
        -- Suppress Blizzard party frames when we're showing for groups
        if (IsInGroup() and not IsInRaid()) and ns._SuppressBlizzParty then
            ns._SuppressBlizzParty()
        end
        -- Headers last laid out hidden (native order) take the shown layout
        -- before the rebuild reads their buttons.
        if ns._rfRaidLaidVis ~= true then LayoutGroups() end
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
        StopRangeTicker()
        StopGhostTicker()
        if wasVisible then ns._RFForgetOccupants(allButtons) end
        wipe(unitToButton)
        -- A hidden set runs native order and keeps every group header up, so the
        -- driver can show it mid-fight with every member in place.
        if ns._rfRaidLaidVis ~= false then
            LayoutGroups()
            -- The dormant container's footprint (see _ApplyTierOffset).
            if ns._ApplyTierOffset then ns._ApplyTierOffset() end
        end
    end
end
ns.UpdateVisibility = UpdateVisibility

-------------------------------------------------------------------------------
--  Event handlers
-------------------------------------------------------------------------------
local function OnEvent(self, event, arg1, ...)
    -- Hot per-unit branches FIRST (thousands per pull); everything below them
    -- is rare. Order is semantics-free -- event names are distinct -- and a
    -- hidden frame set has empty routing maps, so these no-op there exactly as
    -- they did behind the visibility guard further down.
    if event == "UNIT_HEALTH" then
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
                dd._rmhPct = nil -- reduced-max cache: this is its only value edge
                ns._UpdateButtonHealth(btn, arg1)
                ns._ResettleButtonHealth(btn)
            end
            end -- prediction view-gate else
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
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
        -- Restore child frame levels after a deferred strata change. A Party
        -- Frames kit or party portrait geometry write blocked in combat (a
        -- Frame Scale or portrait change through a combat-time refresh) needs
        -- the same full party pass: it re-sizes the buttons, re-runs the kit
        -- and portrait passes and relays the slots.
        local kitDirty = ns._partyKitDirtyInCombat
        ns._partyKitDirtyInCombat = nil
        if frameStrataDirty then
            if not (sizeTierDirty and framesVisible) then ReloadFrames() end
            if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
            -- The re-stack reset the child levels the Color Custom Borders copies took at
            -- their last restyle, which ran in combat before the strata applied; the
            -- fingerprint-gated reload above will not restyle them again.
            local AK = EllesmereUI.AuraKit
            if AK and AK.RestyleSoon then
                AK.RestyleSoon("rf:dispel:raid")
                AK.RestyleSoon("rf:dispel:party")
                AK.RestyleSoon("rf:dispel:extra")
            end
        elseif kitDirty and ns.ReloadPartyFrames then
            ns.ReloadPartyFrames()
        end
        -- Pet frames: the roster changes and applies deferred through combat, after the layout above.
        ns.PF_Flush()
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
        -- updates itself; these do not). FrameSort's list is role-aware too.
        if not inCombat and ns._partyFramesVisible
            and (db.profile.partyPrioritizeClass or ns._PartyInRaid() or ns._FsPartyMode())
            and ns._LayoutPartyFrames then
            ns._LayoutPartyFrames()
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
        -- Unit tokens reindex on roster changes; a latched rez offer keyed by the
        -- old token would paint on the wrong player, so drop them all.
        if event == "GROUP_ROSTER_UPDATE" then
            wipe(ns._rezPend)
            -- Pet frames: flushed once by the roster pass below, or at combat end.
            ns.PF_MarkDirty()
        end
        -- InCombatLockdown too: a /reload in combat never sees PLAYER_REGEN_DISABLED.
        if inCombat or InCombatLockdown() then
            ns._rosterDirtyInCombat = true
            -- The visibility drivers show and hide the containers on their own;
            -- bring the Lua side (event gates, maps, tickers) in step first.
            ns._RFCombatVisEdge()
            -- Check if size tier changed during combat (deferred to REGEN)
            local numMembers = ns._GetEffectiveRaidSize()
            if numMembers > 0 then
                local newW, newH = ns._GetRaidSizeFrameDimensions(numMembers)
                if newW ~= ns._activeSizeW or newH ~= ns._activeSizeH then
                    ns._sizeTierDirtyInCombat = true
                end
                local _, newOv = ns._RFResolveTierOverride(numMembers)
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
                -- The self button's unit never changes, so no assignment remaps it
                -- when the driver shows the container a tick after this pass; its
                -- own shown flag (set out of combat) says whether it owns the player.
                local sb = ns._partySelfButton
                if sb and sb:IsShown() then ns._partyUnitToButton.player = sb end
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
            -- A hidden->visible transition needs nothing more here: UpdateVisibility
            -- already laid the headers out and ran the full rebuild (RebuildUnitMap +
            -- UpdateAllButtons).
            if framesVisible then
                if tierChanged then
                    -- Tier changed: full reload (recalculates _activeSizeW/H, restyles).
                    ReloadFrames()
                    if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
                elseif wasVis then
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
            -- Pet frames: once per roster pass, after the groups they attach to are laid out.
            ns.PF_Flush()
        end)
    elseif event == "UNIT_PORTRAIT_UPDATE" or event == "PORTRAITS_UPDATED" or event == "UNIT_MODEL_CHANGED" then
        -- Party Frames kit / party portrait only (registered while the party
        -- frames are shown with a portrait that needs them; the model event
        -- for a 3D portrait alone). Matched on each party button's unit
        -- attribute, never the routing map: a portrait is a sticky paint,
        -- and the map keeps stale tokens.
        local list = ns._partyAllButtons
        for i = 1, #list do
            local b = list[i]
            local u = b:GetAttribute("unit")
            if u and (arg1 == nil or u == arg1) then
                local bd = GetFFD(b)
                if (bd.kitPortrait or bd.pt) and UnitExists(u) then ns.RF_PtPaint(bd, u, event) end
            end
        end
    elseif not framesVisible and not ns._partyFramesVisible then
        -- Skip all per-unit event processing when no frames are visible
        return
    elseif event == "UNIT_IN_RANGE_UPDATE" then
        -- Standard ~40yd range change for this unit (event-driven, debounced).
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            ns._UpdateButtonRange(arg1, btn)
            -- A 3D party portrait showing the out-of-sight question mark:
            -- a member coming into range is in sight again.
            if ns._ptModelEv then
                local bd = GetFFD(btn)
                local pt = bd.pt
                if pt and pt._state == false then ns.RF_PtPaint(bd, arg1, "Probe") end
            end
        end
    elseif event == "UNIT_PHASE" then
        -- Phasing doesn't fire UNIT_IN_RANGE_UPDATE; re-evaluate all (rare).
        if ns._RangeSeedAll then ns._RangeSeedAll() end
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
            local ppct = UnitPowerPercent(arg1, pType, true, CurveConstants.ScaleTo100)
            d.power:SetValue(ppct)
            -- Power Text rides the same value (nil = off: this one field test).
            local pwtMode = d._pwtMode
            if pwtMode then ns.RF_PowerTextInto(d.powerText, pwtMode, ppct, arg1, pType) end
        end
    elseif event == "UNIT_DISPLAYPOWER" then
        -- The displayed power type changed (forms, spec swaps, vehicles):
        -- re-derive type + color + bounds once (Power Text's colour too), then push the value.
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn and GetFFD(btn).power then
            local d = GetFFD(btn)
            ns._RFPowerTypeEdge(d, arg1)
            local ppct = UnitPowerPercent(arg1, d._pwType, true, CurveConstants.ScaleTo100)
            d.power:SetValue(ppct)
            local pwtMode = d._pwtMode
            if pwtMode then ns.RF_PowerTextInto(d.powerText, pwtMode, ppct, arg1, d._pwType) end
        end
    elseif event == "UNIT_NAME_UPDATE" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        -- The name arriving is also when the class becomes known (Blizzard's
        -- own comment on this edge): drop the cached class token first.
        if btn then GetFFD(btn)._clsTok = nil; UpdateButton(btn) end
        -- NAMELIST-driven headers (party Prioritize Class, raid Show Self
        -- First) are built from member names. A member whose name populated
        -- late, or changed since the build, sits under the trailing
        -- placeholder token (sorted last) or, when the builder bailed, in
        -- native order. Rebuild the lists now that the real name exists
        -- (debounced: names resolve in bursts after a loading screen) so the
        -- proper order returns once the last name lands.
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
                    and (db.profile.partyPrioritizeClass or ns._PartyInRaid() or ns._FsPartyMode())
                    and ns._LayoutPartyFrames then
                    ns._LayoutPartyFrames()
                end
                if framesVisible and ns._ApplySortToHeaders then
                    ns._ApplySortToHeaders()
                end
            end)
        end
    elseif event == "UNIT_LEVEL" then
        -- Level Text only (registered while a view shows it): the level alone repaints,
        -- on its spot or in front of the name.
        local btn = unitToButton[arg1]
        if btn then ns._RFRepaintLevel(btn) end
        btn = ns._partyUnitToButton[arg1]
        if btn then ns._RFRepaintLevel(btn) end
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            local d = GetFFD(btn)
            ns.RF_PaintThreat(d, d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile, arg1)
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
        -- The member's pet frame, when one shows.
        if event == "UNIT_CONNECTION" then ns._PF_OwnerRange(arg1) end
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
                and (db.profile.partyPrioritizeClass or ns._PartyInRaid() or ns._FsPartyMode())
                and ns._LayoutPartyFrames then
                ns._LayoutPartyFrames()
            end
            if ns._UpdateRoleIcons then ns._UpdateRoleIcons() end
        end
    elseif event == "PLAYER_DIFFICULTY_CHANGED" then
        -- Hide Groups 5-8 in Mythic Raid (heard only while on): a switch inside
        -- the raid (e.g. Heroic -> Mythic) against the set the layout applied.
        if (ns._VisibleGroups() == ns._mythicGroups) ~= (ns._rfLaidMythic == true) then
            if InCombatLockdown() then
                ns._sizeTierDirtyInCombat = true  -- REGEN runs the full reload
            elseif framesVisible then
                ReloadFrames()
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Re-sync the boss-combat flag on load. IsEncounterInProgress() still
        -- reports an active encounter after a mid-fight /reload or zone (where
        -- ENCOUNTER_START already fired and will not fire again), so "Out of Boss
        -- Combat" keeps suppressing; otherwise this clears a stale flag from a
        -- missed ENCOUNTER_END so tooltips are not stuck hidden.
        ns._inBossCombat = (IsEncounterInProgress and IsEncounterInProgress()) or false
        -- 3D party portraits: a world transition can reset a model at the
        -- same guid.
        if ns._ptModelEv and ns.RF_PtRepaintAll then ns.RF_PtRepaintAll("PLAYER_ENTERING_WORLD") end
        C_Timer.After(0.5, function()
            -- Pet frames: flushed at the end of this settle, or at combat end.
            ns.PF_MarkDirty()
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
            -- Entering or leaving a Mythic raid with Hide Groups 5-8 on changes which groups
            -- show even when the tier holds; read before UpdateVisibility can re-lay them.
            local mythicChanged = (ns._VisibleGroups() == ns._mythicGroups) ~= (ns._rfLaidMythic == true)
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
                if tierChanged or mythicChanged then
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
            -- A tier reload above has already applied the pets; otherwise they apply once here.
            ns.PF_Flush()
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
            "healthVerticalFill", "healthInvertFill",
            -- Drawn as "Threat Borders" (and its cog) on the Health Bar row, so they file here.
            "threatBorderSize", "threatCustomBorder",
        },
        absorbs = {
            "absorbStyle", "absorbOpacity", "absorbColor", "absorbEdgeMode", "showOvershield",
            "overshieldMode", "absorbGlowLine",
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
            "nameSize", "nameMaxLength", "nameFormat", "nameColorMode", "nameCustomColor",
            "namePosition", "nameOffsetX", "nameOffsetY",
            "levelTextSize", "levelTextPosition", "levelTextOffsetX", "levelTextOffsetY",
            "healthTextMode", "healthTextColorMode", "healthTextCustomColor",
            "healthTextSize", "healthTextPosition", "healthTextOffsetX", "healthTextOffsetY",
            "healAbsorbTextMode", "healAbsorbTextColorMode", "healAbsorbTextCustomColor",
            "healAbsorbTextSize", "healAbsorbTextPosition", "healAbsorbTextOffsetX", "healAbsorbTextOffsetY",
            "powerTextMode", "powerTextColorMode", "powerTextCustomColor",
            "powerTextSize", "powerTextPosition", "powerTextOffsetX", "powerTextOffsetY",
        },
        indicators = {
            "roleIconStyle", "roleIconSize", "roleIconPosition", "roleIconOffsetX", "roleIconOffsetY", "roleIconHideInCombat",
            "roleIconBehindBorder",
            "showRoleForTank", "showRoleForHealer", "showRoleForDPS",
            "showRaidMarker", "raidMarkerSize", "raidMarkerPosition", "raidMarkerOffsetX", "raidMarkerOffsetY",
            "showPingMarker", "pingMarkerSize", "pingMarkerPosition", "pingMarkerOffsetX", "pingMarkerOffsetY",
            "showMissingBuffs", "missingBuffsSize", "missingBuffsPosition", "missingBuffsOffsetX", "missingBuffsOffsetY",
            "missingBuffsFort", "missingBuffsMark", "missingBuffsSpirit", "missingBuffsThorns", "missingBuffsBlessing",
            "missingBuffsGlowType", "missingBuffsGlowColorMode", "missingBuffsGlowR", "missingBuffsGlowG", "missingBuffsGlowB",
            "missingBuffsGlowLines", "missingBuffsGlowThickness", "missingBuffsGlowSpeed", "missingBuffsGlowBackground",
            "missingBuffsGlowBackgroundR", "missingBuffsGlowBackgroundG", "missingBuffsGlowBackgroundB",
            "showReadyCheck", "showSummonPending", "showIncomingRez",
            "readyCheckSize", "readyCheckPosition", "readyCheckOffsetX", "readyCheckOffsetY",
            "statusTextPosition", "statusTextOffsetX", "statusTextOffsetY", "statusTextSize", "statusTextColor",
            "statusShowAFK",
            "showLeaderIcon", "showLeaderIconInCombat", "leaderIconPosition", "leaderIconSize", "leaderIconOffsetX", "leaderIconOffsetY",
            "showCombatIndicator", "combatIndicatorStyle", "combatIndicatorColor", "combatIndicatorCustomColor",
            "combatIndicatorSize", "combatIndicatorPosition", "combatIndicatorOffsetX", "combatIndicatorOffsetY",
            "borderSize", "borderColor", "borderAlpha", "borderTexture",
            "borderBehind", "borderTextureOffset", "borderTextureOffsetY",
            "borderTextureShiftX", "borderTextureShiftY",
            "hoverBorderEnabled", "hoverBorderSize", "hoverBorderColor", "hoverBorderAlpha",
            "targetBorderEnabled", "targetBorderSize", "targetBorderColor", "targetBorderAlpha",
            -- Exact-size companions (see ns._PARTY_PX_SIBLING): same section as their siblings.
            "borderSizePx", "hoverBorderSizePx", "targetBorderSizePx",
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
            "dispelIconBorderSize", "dispelOverlayPosition", "dispelCustomBorder",
            "dispelClockBorder", "dispelClockExtraBorder",
            "dispellableDebuffLocation", "dispellableDebuffGrowDirection",
            "dispellableDebuffOffsetX", "dispellableDebuffOffsetY", "dispellableDebuffSize",
        },
        topNameBar = {
            "topNameBarEnabled", "topNameBarHeight",
            "topNameBarBgColor", "topNameBarBgOpacity",
            "topNameBarTextSize", "topNameBarTextColorMode", "topNameBarTextColor",
            "topNameBarTextOffsetX", "topNameBarTextOffsetY", "topNameBarTextAlign",
            "topNameBarBottom",
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

-- A border's exact-size companion ("<key>Px", read through EllesmereUI.BorderPx)
-- is ONE setting with its legacy sibling: wherever the party reads a stored
-- party_<sibling>, the companion resolves ONLY to party_<companion> (nil
-- included), never through to the raid companion. Applied by the proxy
-- __index, the materializer and the ReloadPartyFrames temp-swap. The Blizzard
-- Glow Line pairs with Absorb Style the same way: unset, it follows the style
-- it is read with, so a party that keeps its own style never takes the raid's.
ns._PARTY_PX_SIBLING = {
    borderSizePx       = "borderSize",
    hoverBorderSizePx  = "hoverBorderSize",
    targetBorderSizePx = "targetBorderSize",
    absorbGlowLine     = "absorbStyle",
}

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
            local sib = ns._PARTY_PX_SIBLING[key]
            if sib and rawget(db.profile, "party_" .. sib) ~= nil then
                return rawget(db.profile, "party_" .. key)
            end
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
    "nameSize", "healthTextSize", "healAbsorbTextSize", "statusTextSize", "powerTextSize", "levelTextSize",
    "debuffStacksTextSize", "debuffDurTextSize", "defDurTextSize",
    -- Icon sizes
    "roleIconSize", "leaderIconSize", "raidMarkerSize", "combatIndicatorSize", "pingMarkerSize",
    "missingBuffsSize",
    "debuffSize", "defSize", "dispellableDebuffSize",
    -- Offsets
    "nameOffsetX", "nameOffsetY",
    "healthTextOffsetX", "healthTextOffsetY",
    "healAbsorbTextOffsetX", "healAbsorbTextOffsetY",
    "powerTextOffsetX", "powerTextOffsetY",
    "levelTextOffsetX", "levelTextOffsetY",
    "statusTextOffsetX", "statusTextOffsetY",
    "roleIconOffsetX", "roleIconOffsetY",
    "leaderIconOffsetX", "leaderIconOffsetY",
    "raidMarkerOffsetX", "raidMarkerOffsetY",
    "missingBuffsOffsetX", "missingBuffsOffsetY",
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
    if key == "frameWidth" or key == "frameHeight" then
        local p = ns._pvOverlayProxy or (db and db.profile)
        if not p then return nil end
        -- The bars' width: an attached portrait's share of the box is not theirs.
        local w, h, _, res = ns.RF_PartyDims(p)
        if key == "frameWidth" then return w - (res or 0) end
        return h
    end
    -- Party Frames kit: the settings its layout decides (neutral keys, the
    -- debuff row under the frame) read the kit's values. Only the overlay
    -- view reaches here for them: otherwise the materializer holds them.
    local ovp = ns._pvOverlayProxy
    if ovp and ns.RF_PartyKit() then
        local kv = ns.RF_KitViewKeys(ovp)
        if kv and kv[key] ~= nil then return kv[key] end
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
        if pv == nil then
            -- An exact-size companion whose party sibling is stored, and whose
            -- raid sibling the overlay does not own, stays unresolved so the
            -- party rule in _partyProxy decides (never the raid companion).
            local sib = ns._PARTY_PX_SIBLING and ns._PARTY_PX_SIBLING[key]
            if not (sib and section and ns._IsPartySectionCustom(section)
                    and rawget(db.profile, "party_" .. sib) ~= nil and ov[sib] == nil) then
                pv = ov[key]
            end
        end
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
    local pxSib = ns._PARTY_PX_SIBLING
    if keySection and ns._IsPartySectionCustom then
        for k, section in pairs(keySection) do
            if ns._IsPartySectionCustom(section) then
                local pv = rawget(p, "party_" .. k)
                local sib = pxSib[k]
                if sib and rawget(p, "party_" .. sib) ~= nil then
                    -- Companion of a stored party sibling: the party value only
                    -- (a nil unsets the raid copy; the __index rule answers nil too).
                    rawset(pp, k, pv)
                elseif pv ~= nil then
                    rawset(pp, k, pv)
                end
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
        local pw, ph, _, pres = ns.RF_PartyDims(pp)
        rawset(spp, "frameWidth", pw - (pres or 0))
        rawset(spp, "frameHeight", ph)
        if ns.RF_PartyKit() then
            local kv = ns.RF_KitViewKeys(pp)
            if kv then
                for k, v in pairs(kv) do rawset(spp, k, v) end
            end
        end
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
    -- Level Text's event follows the views (defined once the unit trackers exist).
    if ns._RFSyncLevelRegistration then ns._RFSyncLevelRegistration() end
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
    local scale
    if ns.RF_PartyKit() then
        -- Party Frames kit: its Frame Scale is the frame size (at 100% the
        -- user's own icon and text sizes apply, whatever the raid size), and
        -- icons follow it over its whole range.
        scale = s.partyKitScale or ns.RF_KIT_SCALE or 1.2
    else
        local baseW = s.frameWidth or 72
        local baseH = s.frameHeight or 46
        -- The bars' size (an attached portrait does not enlarge the icons).
        local pw, ph, _, pres = ns.RF_PartyDims(s)
        pw = pw - (pres or 0)
        scale = math.max(math.min(math.min(pw / baseW, ph / baseH), 1.3), 0.7)
    end
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
    local pw, ph, pcs = ns.RF_PartyDims(s)
    local bw, bh, cs = PixelSnap(pw), PixelSnap(ph), PixelSnap(pcs)

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
    -- showRaid=true so the header binds raid units inside an arena, where the
    -- team is a raid group, and in Small Raid mode (group 1 only, via the
    -- groupFilter / nameList set in _LayoutPartyFrames). Inert in a normal
    -- 5-man party (no raid units exist), so it only takes effect when the
    -- header is actually shown in a raid group -- which we do only for those
    -- two modes (see _UpdatePartyVisibility). Otherwise the header is hidden
    -- in a real raid, so this never shows 40 raid units.
    hdr:SetAttribute("showRaid", true)
    hdr:SetAttribute("showParty", true)
    hdr:SetAttribute("showPlayer", true)
    hdr:SetAttribute("showSolo", s.partyShowWhenSolo or false)
    hdr:SetAttribute("maxColumns", 1)
    hdr:SetAttribute("unitsPerColumn", 5)

    -- Pre-create 5 buttons. Container must be visible for SecureGroupHeaderTemplate to
    -- process children (IsVisible checks parent chain). Show temporarily, then hide.
    -- The header itself stays shown from here on: only the container hides (its
    -- visibility driver can then show the party frames in combat, the header
    -- re-reading the roster on that show).
    ns._partyContainerFrame:Show()
    hdr:SetAttribute("startingIndex", -4)
    hdr:Show()
    hdr:SetAttribute("startingIndex", 1)
    ns._partyContainerFrame:Hide()

    -- Window-phase secure styling; insecure bodies run in the deferred pass.
    -- _isParty goes first: the secure pass sizes party buttons to the party
    -- box (the header's own initConfig size would otherwise be overwritten
    -- with the raid size).
    for i = 1, 5 do
        local btn = hdr[i]
        if btn then
            GetFFD(btn)._isParty = true
            ns._StyleButtonSecure(btn)
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
    local sd = GetFFD(selfBtn)
    sd._isParty = true
    sd._isSelf = true
    ns._StyleButtonSecure(selfBtn)
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
    -- Party-in-raid mode (arena, Small Raid) binds the header to raid units,
    -- which include the player, and showPlayer=false cannot exclude the player
    -- in a raid group. The static self button would then duplicate the player,
    -- so disable it there and let the header show the player natively (there
    -- showPlayer reduces to "not hideSelf" in _LayoutPartyFrames; the raid
    -- nameList -- not showPlayer -- is what omits the player when Hide Self is on).
    -- Sort By = FrameSort: its list places the player, so the self button
    -- stands down and the player stays inside the header.
    -- A party set the group state hides is laid out native (no self button, no
    -- centering): the visibility driver can show it mid-fight, when neither can
    -- be placed, and the header alone then shows every member from the first slot.
    local _, live = ns._RFVisWanted()
    local useSelf = live and (pSelfFirst or pSelfLast) and not hideSelf and IsInGroup() and not ns._PartyInRaid()
        and not ns._FsPartyMode()

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
    if not live then
        -- Hidden set: the stack starts at the first slot (see useSelf above).
    elseif not IsInGroup() then
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
    -- The pet frames line up with whichever frame holds slot 0, and your own pet (Beside Owner)
    -- goes with whichever frame shows you.
    local first = (useSelf and not pSelfLast and sb) or ns._partyHeader
    local selfMode = (useSelf and "button") or (hideSelf and "hidden") or "header"
    if first ~= ns._partyFirstSlot or selfMode ~= ns._partySelfMode then
        ns._partyFirstSlot, ns._partySelfMode = first, selfMode
        ns.PF_ReAnchor()
    end
    return useSelf
end

-- Party growth direction. Explicit true only: "centered" keeps the default
-- direction.
ns._PartyGrowth = function(s)
    -- (Party Frames kit: horizontal frames carry their buffs above each
    -- frame -- ns.RF_KitBmView -- so the next frame beside it stays clear.)
    if s.partyHorizontal then return (s.partyFlipGrowth == true) and "LEFT" or "RIGHT" end
    return (s.partyFlipGrowth == true) and "UP" or "DOWN"
end

-- Size the party container (the unlock mover's rect: always 5 slots) from
-- snapped slot dimensions. Every sizer goes through here so they all agree.
-- Resizing the container triggers an implicit SecureGroupHeader child
-- re-process, and that implicit pass has been observed landing with units
-- unassigned (NAMELIST sort especially): children left hidden with unit=nil
-- until the next clean re-process. The resize is bracketed with an explicit
-- header Hide/Show -- the implicit pass runs while hidden (inert) and the
-- Show() performs a clean, reliable re-process -- and skipped when unchanged.
-- Out of combat only (callers gate).
ns._SizePartyContainer = function(bw, bh, cs, unitGrowth)
    local c = ns._partyContainerFrame
    if not c then return end
    local cw, ch
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        cw, ch = 5 * bw + 4 * cs, bh
    else
        cw, ch = bw, 5 * bh + 4 * cs
    end
    cw, ch = PixelSnap(cw), PixelSnap(ch)
    local curW, curH = c:GetSize()
    if math.abs((curW or 0) - cw) > 0.01 or math.abs((curH or 0) - ch) > 0.01 then
        local hdr = ns._partyHeader
        local shown = hdr and hdr:IsShown()
        if shown then hdr:Hide() end
        c:SetSize(cw, ch)
        if shown then hdr:Show() end
    end
end

-------------------------------------------------------------------------------
-- Party Targets (opt-in, Party-only)
--
-- Secure buttons attached to party-header children and (Include Own Target
-- with Show Self First / Last) the self button. Their unit resolves as the
-- owner's current target at click time, so no protected unit mutation is
-- needed in combat.
-- Placement: the Position setting (unset: beside stacked frames, below
-- horizontal ones) plus its offsets. Across the stack (left/right of stacked
-- frames, above/below horizontal ones) the frames move off the Party Frames
-- kit's outside auras and follow the Beside Owner pets on that side, as the
-- pets do, and the groups attached beside the party frames (Friendly Boss,
-- the pet header) reserve the reach through ns.PT_Reserve. Along the stack
-- the chosen side is kept exactly and the party frames' pitch opens by the
-- frames' room (ns.PT_AlongPitch), so they sit between two party frames.
-- Look: a health bar on the Friendly Boss visuals (the stock edge under a
-- stock style) with the party texture, name font and border, and their own
-- Fill Color and Background.
-- Updates: a party member's target has no unit events, so one hidden 0.5 s
-- ticker reads the values while such a frame shows, and re-checks a mob's
-- tap and reaction (its colour); your own target is evented. Names and
-- colours otherwise repaint on target changes, unit re-assignments, roster
-- edges and settings pushes only.
-------------------------------------------------------------------------------
ns._partyTargetFrames = ns._partyTargetFrames or {}
ns._ptEnabled = false
ns._ptDesired = false
ns._ptInclDesired = false

-- Scope block: 200-local main-chunk cap.
do
local EUI = ns.EllesmereUI
-- Layout state (the last applied size, side, gaps and offsets: the layout's delta gate and the
-- reserve's source), the colour settings the paint reads (cached by the restyle), the listeners,
-- and the owner bookkeeping: owner token -> "<token>target", header button -> its target frame.
local PT = { tgtOf = {}, frameOf = setmetatable({}, { __mode = "k" }), tgtEv = {}, tgtWant = {}, acc = 0,
             DEF_FILL = { r = 37/255, g = 193/255, b = 29/255 } }
-- The shared style inputs plus the target frames' own ten (PT_FpExtra).
PT.FP_N = ns._PF.STYLE_N + 10

-- Owner unit -> its target frame, for UNIT_TARGET. Frames showing your own target stay out: they
-- read "target" and follow PLAYER_TARGET_CHANGED.
local PT_BY_UNIT = {}

-- The settings the target frames are styled from: the party ones, as the Beside Owner pets.
local function PT_Source()
    return ns._scaledPartyProxy
end

-- "party1" -> "party1target", built once per token.
local function PT_TargetOf(u)
    local t = PT.tgtOf[u]
    if not t then
        t = u .. "target"
        PT.tgtOf[u] = t
    end
    return t
end

-- Your raid token while the party frames run on raid units (arena, Small Raid), else nil.
local function PT_Me()
    if not IsInRaid() then return nil end
    local idx = UnitInRaid("player")
    if issecretvalue(idx) or not idx then return nil end
    return "raid" .. idx
end

-- The unit a frame reads, from its owner's current unit: your own target reads "target" (the token
-- your target's events carry), anyone else's "<owner>target". Keeps PT_BY_UNIT current. Returns
-- true when the frame's owner changed.
local function PT_Classify(frame)
    local ou, own
    if frame == PT.selfFrame then
        own = true
    else
        ou = frame._ptOwner:GetAttribute("unit")
        own = ou ~= nil and (ou == "player" or ou == PT.me)
    end
    local key = (not own) and ou or nil
    local old = frame._ptOwnerUnit
    local changed = old ~= key or frame._ptOwn ~= own
    if old ~= key then
        if old and PT_BY_UNIT[old] == frame then PT_BY_UNIT[old] = nil end
        if key then PT_BY_UNIT[key] = frame end
        frame._ptOwnerUnit = key
    end
    frame._ptOwn = own
    frame._ptUnit = (own and "target") or (ou and PT_TargetOf(ou)) or nil
    return changed
end

-- Class colour for players and party AI (the custom one where a restricted token still allows it),
-- grey for a tapped mob, the reaction colour for other NPCs. Returns ok, r, g, b; r/g/b may be
-- SECRET on the restricted path: only ever handed to a setter, never compared. A mob's tap and
-- reaction (neither secret) are kept on frame, for the ticker's re-check.
local function PT_ClassRGB(u, frame)
    if UnitIsPlayer(u) or (UnitInPartyIsAI and UnitInPartyIsAI(u)) then
        local _, ct = UnitClass(u)
        if issecretvalue(ct) then
            local ok, r, g, b = EUI.GetClassColorForRestrictedUnit(u, ct)
            if ok then return true, r, g, b end
            local c = C_ClassColor.GetClassColor(ct)
            if c then return true, c.r, c.g, c.b end
            return false
        end
        local cc = ct and EUI.GetClassColor(ct)
        if cc then return true, cc.r, cc.g, cc.b end
        return false
    end
    local tap = UnitIsTapDenied(u)
    local re = UnitReaction(u, "player")
    if issecretvalue(re) then re = nil end
    if frame then frame._ptNpc, frame._ptTap, frame._ptRe = true, tap, re end
    if tap then return true, 0.6, 0.6, 0.6 end
    local c = re and FACTION_BAR_COLORS[re]
    if c then return true, c.r, c.g, c.b end
    return false
end

-- The Classic gradient at the unit's current health (the engine evaluates the curve, secret-safe).
local function PT_PaintClassic(health, u)
    local c = UnitHealthPercent(u, true, GetClassicHealthCurve())
    if c and c.GetRGB then health:SetStatusBarColor(c:GetRGB()) end
end

-- Identity paint: name, fill and background colours, and the value, which jumps (a new unit). Runs
-- on target, unit and settings edges only. Names and colours can be secret: setters only.
local function PT_Paint(frame)
    local u = frame._ptUnit
    -- Set again below only for a mob whose colour reads its tap and reaction.
    frame._ptNpc = nil
    if not (u and UnitExists(u)) then return end
    frame._nameText:SetText(UnitName(u))
    local health, bg, mode = frame._health, frame._bg, PT.mode
    local fillTex = health:GetStatusBarTexture()
    if mode == "dark" then
        local r, g, b, a = EUI.GetDarkModeFill()
        health:SetStatusBarColor(r, g, b, 1)
        if fillTex then fillTex:SetAlpha(a) end
        bg:SetColorTexture(EUI.GetDarkModeBg())
    else
        if fillTex then fillTex:SetAlpha(1) end
        local ok, r, g, b = false
        if (mode ~= "classic" and mode ~= "custom") or PT.bgClass then ok, r, g, b = PT_ClassRGB(u, frame) end
        if mode == "classic" then
            PT_PaintClassic(health, u)
        elseif mode == "custom" then
            health:SetStatusBarColor(PT.fr, PT.fg, PT.fb, 1)
        elseif ok then
            health:SetStatusBarColor(r, g, b, 1)
        else
            health:SetStatusBarColor(0.5, 0.5, 0.5, 1)
        end
        if ok and PT.bgClass then
            bg:SetColorTexture(r, g, b, PT.bgA)
        else
            bg:SetColorTexture(PT.br, PT.bgg, PT.bb, PT.bgA)
        end
    end
    health:SetValue(GetSafeHealthPercent(u))
end

-- Value paint (the ticker and your target's health events), smoothed per Smooth Bars; the Classic
-- gradient follows the value.
local function PT_PaintValue(frame, u)
    local health = frame._health
    local smooth = PT.smooth
    if smooth then
        health:SetValue(GetSafeHealthPercent(u), smooth)
    else
        health:SetValue(GetSafeHealthPercent(u))
    end
    if PT.mode == "classic" then PT_PaintClassic(health, u) end
end

-- Every target frame on screen, in full (settings pushes: a restyle, Dark Mode and class colours
-- through ERF:UpdateAllFrames, roster edges). Nothing while off.
ns._PT_RepaintVisible = function()
    if not ns._ptEnabled then return end
    for _, frame in ipairs(ns._partyTargetFrames) do
        if frame:IsVisible() then PT_Paint(frame) end
    end
end

-- The frames on screen drive every per-unit listener. Polled frames (a party member's target):
-- UNIT_TARGET on their owners' units only (listener k covers frames 2k-1 and 2k, so a frame
-- showing or hiding re-registers its own listener alone; a target appearing shows its frame
-- through the unit watch), and the ticker while one shows. Own frames (your target): your target's
-- events while one shows with Include Own Target on. Nameplates and every other unit stay out.
-- except: a frame on its way off screen.
local function PT_Recount(except)
    local want, poll, own = PT.tgtWant, 0, 0
    wipe(want)
    if ns._ptEnabled then
        for i, f in ipairs(ns._partyTargetFrames) do
            if f ~= except and f:IsVisible() then
                if f._ptOwn then
                    own = own + 1
                elseif f._ptOwnerUnit then
                    poll = poll + 1
                    want[i] = f._ptOwnerUnit
                end
            end
        end
    end
    for k = 1, #PT.tgtEv do
        local ev = PT.tgtEv[k]
        local u1, u2 = want[2 * k - 1], want[2 * k]
        if ev.ptU1 ~= u1 or ev.ptU2 ~= u2 then
            ev.ptU1, ev.ptU2 = u1, u2
            ev:UnregisterEvent("UNIT_TARGET")
            if u1 and u2 then
                ev:RegisterUnitEvent("UNIT_TARGET", u1, u2)
            elseif u1 or u2 then
                ev:RegisterUnitEvent("UNIT_TARGET", u1 or u2)
            end
        end
    end
    local tk = PT.ticker
    if tk then
        if poll > 0 then
            if not tk:IsShown() then
                PT.acc = 0
                tk:Show()
            end
        elseif tk:IsShown() then
            tk:Hide()
        end
    end
    local ownOn = (own > 0 and PT.include) and true or false
    local ev = PT.ownFrame
    if ev and PT.ownEv ~= ownOn then
        PT.ownEv = ownOn
        if ownOn then
            ev:RegisterEvent("PLAYER_TARGET_CHANGED")
            ev:RegisterUnitEvent("UNIT_HEALTH", "target")
            ev:RegisterUnitEvent("UNIT_MAXHEALTH", "target")
            ev:RegisterUnitEvent("UNIT_FACTION", "target")
        else
            ev:UnregisterAllEvents()
        end
    end
end

-- The ticker (hidden while idle): every 0.5 s, the values of the polled frames on screen. A mob's
-- colour follows its tap and reaction, which raise no events on these units: a change repaints.
local function PT_Tick(_, elapsed)
    local acc = PT.acc + elapsed
    if acc < 0.5 then
        PT.acc = acc
        return
    end
    PT.acc = 0
    for _, f in ipairs(ns._partyTargetFrames) do
        local u = f._ptUnit
        if u and not f._ptOwn and f:IsVisible() and UnitExists(u) then
            PT_PaintValue(f, u)
            if f._ptNpc then
                local re = UnitReaction(u, "player")
                if issecretvalue(re) then re = nil end
                if UnitIsTapDenied(u) ~= f._ptTap or re ~= f._ptRe then PT_Paint(f) end
            end
        end
    end
end

-- Your target: a new target (or a faction change) repaints in full, its health events the value.
local function PT_OnOwnEvent(_, event)
    local full = event == "PLAYER_TARGET_CHANGED" or event == "UNIT_FACTION"
    for _, f in ipairs(ns._partyTargetFrames) do
        if f._ptOwn and f:IsVisible() then
            if full then
                PT_Paint(f)
            elseif UnitExists("target") then
                PT_PaintValue(f, "target")
            end
        end
    end
end

-- Include Own Target off: the header frame showing you drops its target frame's unit. Written here
-- out of combat by the rule the party frames' unit snippet applies in combat (PF.OWNER_SNIPPET).
local function PT_SeedAttrs()
    local noself = (ns._ptEnabled and not PT.include) and true or nil
    local me = PT.me
    for _, frame in ipairs(ns._partyTargetFrames) do
        if frame ~= PT.selfFrame then
            if frame:GetAttribute("pt-noself") ~= noself then frame:SetAttribute("pt-noself", noself) end
            if frame:GetAttribute("pt-me") ~= me then frame:SetAttribute("pt-me", me) end
            local u = frame._ptOwner:GetAttribute("unit")
            local show = not (noself and u ~= nil and (u == "player" or u == me))
            if frame:GetAttribute("useparent-unit") ~= show then frame:SetAttribute("useparent-unit", show) end
        end
    end
end

-- Full refresh (roster, zoning, the enable edge): your raid token, every frame's unit, the
-- listeners, and a repaint of the frames on screen (a token can pass to another member). The
-- attribute seed is a secure write: in combat it waits for the combat-end flush.
ns._PT_RefreshAll = function()
    if not ns._ptEnabled then return end
    PT.me = PT_Me()
    for _, frame in ipairs(ns._partyTargetFrames) do PT_Classify(frame) end
    if InCombatLockdown() then
        ns._ptSelfDirty = true
    else
        PT_SeedAttrs()
    end
    PT_Recount()
    ns._PT_RepaintVisible()
end

-- Roster and zoning storms: one refresh on the next frame, after the header re-assigned its buttons.
-- Nothing while the party frames are hidden (a raid): their show edge refreshes once instead
-- (ns._UpdatePartyVisibility).
PT.Flush = function()
    PT.flushQueued = nil
    ns._PT_RefreshAll()
end

local function PT_OnEvent(_, event, unit)
    if event == "UNIT_TARGET" then
        local frame = PT_BY_UNIT[unit]
        if frame and frame:IsVisible() then PT_Paint(frame) end
    elseif ns._partyFramesVisible and not PT.flushQueued then
        PT.flushQueued = true
        C_Timer.After(0, PT.Flush)
    end
end

-- The side (top/bottom read as above/below), the extra clearance there, and whether it runs across
-- the stack. Across, the side resolves through the Party Frames kit, as the Beside Owner pets
-- resolve theirs; along the stack it is kept as chosen, above stacked kit frames past the buff
-- lines the kit keeps in the party spacing there (RF_PartyDims). auto: the side an unset Position
-- takes, whatever is stored.
local function PT_Side(s, auto)
    local pos = (not auto and s.partyTargetPosition) or (s.partyHorizontal and "bottom" or "right")
    local side = (pos == "top" and "above") or (pos == "bottom" and "below") or (pos == "left" and "left") or "right"
    local vert = side == "above" or side == "below"
    local extra = 0
    if (vert and not s.partyHorizontal) or (not vert and s.partyHorizontal) then
        if side == "above" and ns.RF_PartyKit() then
            local _, _, cs = ns.RF_PartyDims(s)
            extra = cs - (s.partyKitSpacing or ns.RF_KIT_SPACING)
            if extra < 0 then extra = 0 end
        end
        return side, extra, false
    end
    if ns.RF_PartyKit() then
        local before = side == "left" or side == "above"
        before, extra = ns.RF_KitAttach(s, before)
        if s.partyHorizontal then
            side = before and "above" or "below"
        else
            side = before and "left" or "right"
        end
    end
    return side, extra, true
end

-- The gap to the frame: the party frames' spacing (under the kit its frame gap, without the buff
-- lines RF_PartyDims adds above stacked frames).
local function PT_Gap(s)
    if ns.RF_PartyKit() then return s.partyKitSpacing or ns.RF_KIT_SPACING end
    local _, _, sp = ns.RF_PartyDims(s)
    return sp
end

-- The reach of target frames laid out as st (the live layout state PT, or a preview spec) past the
-- party frames on the side a group attaches to (horizontal: the party frames' orientation; before:
-- left, or above horizontal frames), offsets included. Across the stack: their room there, past
-- the kit's clearance (the caller adds it) and any Beside Owner pets. Along the stack:
-- how far they overhang the party frame's edge (a Width or Height past the frame's, an offset).
local function PT_ReserveOf(st, horizontal, before)
    local side, r = st.side, 0
    if st.across then
        if horizontal then
            if before and side == "above" then
                r = st.h + st.gap + st.y
            elseif not before and side == "below" then
                r = st.h + st.gap - st.y
            end
        elseif before and side == "left" then
            r = st.w + st.gap - st.x
        elseif not before and side == "right" then
            r = st.w + st.gap + st.x
        end
    elseif horizontal then
        r = (st.h - st.ph) / 2 + (before and st.y or -st.y)
    else
        r = (st.w - st.pw) / 2 + (before and -st.x or st.x)
    end
    return r > 0 and PixelSnap(r) or 0
end

-- None until the frames are laid out (PT.w is cleared for a full layout). pets: the Beside Owner
-- pets' room on that side, for a caller that clears them too: across the stack the target frames
-- sit past them, along it level with them, so there the farther reach counts.
function ns.PT_Reserve(horizontal, before, pets)
    pets = pets or 0
    if not (ns._ptEnabled and PT.w) then return pets end
    local r = PT_ReserveOf(PT, horizontal, before)
    if PT.across then return r + pets end
    return (r > pets) and r or pets
end

-- The Position the frames actually take (the options dropdown's value): under the Party Frames kit
-- a side across the stack can move off the kit's buff run. auto: the one an unset setting takes
-- (beside stacked frames, below horizontal ones, then that kit move); the dropdown stores a pick
-- of it as unset, so the default keeps following the orientation and the frame style.
function ns.PT_ShownSide(auto)
    local side = PT_Side(db.profile, auto)
    return (side == "above" and "top") or (side == "below" and "bottom") or side
end

-- The room target frames along the stack (Top/Bottom beside stacked frames, Left/Right beside
-- horizontal ones) add to the party frames' pitch, so they sit between two frames: their length
-- on the stacking axis plus the gap past them. From the settings, so every slot placer agrees
-- whichever runs first. on: the enable state to read (the live one unless given; previews pass
-- the setting).
function ns.PT_AlongPitch(s, on)
    if on == nil then on = ns._ptEnabled end
    if not on then return 0 end
    local _, _, across = PT_Side(s)
    if across then return 0 end
    return PixelSnap(s.partyHorizontal and (s.partyTargetWidth or 70) or (s.partyTargetHeight or 33))
        + PixelSnap(PT_Gap(s))
end

-- One target frame on its side of owner o: off from the owner's edge, then the offsets.
local function PT_Place(frame, o, side, off, x, y)
    frame:ClearAllPoints()
    if side == "left" then
        frame:SetPoint("RIGHT", o, "LEFT", x - off, y)
    elseif side == "below" then
        frame:SetPoint("TOP", o, "BOTTOM", x, y - off)
    elseif side == "above" then
        frame:SetPoint("BOTTOM", o, "TOP", x, y + off)
    else
        frame:SetPoint("LEFT", o, "RIGHT", x + off, y)
    end
end

-- The reserve changed: re-anchor the groups that can attach beside the party frames (a Show in
-- Dungeons boss group, the pet header). Both only move when their spot changed. OOC only.
local function PT_NotifyReserve()
    local FB = ns._FB
    local fs = FB.Settings()
    if FB.built and fs and fs.showInDungeons == true then FB.Anchor() end
    ns.PF_ReAnchor()
end

-- Size and placement, delta-gated: every party layout pass (ns.PF_PartyRelayout, which the kit
-- clearance edge reaches through ns.FB_ReAnchor), every Beside Owner pet change (ns._PF's
-- NotifyReserve) and the Width, Height, Position and offset settings run it. The size is absolute
-- (never the kit's Frame Scale). A combat call is marked for the combat-end flush (ns.PF_Flush).
ns._PT_Layout = function()
    if not ns._ptEnabled then return end
    if InCombatLockdown() then
        ns._ptLayoutDirty = true
        return
    end
    ns._ptLayoutDirty = nil
    local s = db.profile
    -- The party frames' pitch holds the frames along the stack: a change there re-lays the party
    -- frames first, and their pass ends back here.
    if ns._partyHeader and ns.PT_AlongPitch(s) ~= (ns._ptPitchApplied or 0) then
        ns._LayoutPartyFrames()
        return
    end
    local w = PixelSnap(s.partyTargetWidth or 70)
    local h = PixelSnap(s.partyTargetHeight or 33)
    local x = PixelSnap(s.partyTargetOffsetX or 0)
    local y = PixelSnap(s.partyTargetOffsetY or 0)
    local pw, ph = ns.RF_PartyDims(s)
    pw, ph = PixelSnap(pw), PixelSnap(ph)
    local horiz = s.partyHorizontal and true or false
    local gap = PixelSnap(PT_Gap(s))
    local side, extra, across = PT_Side(s)
    local off = gap + PixelSnap(extra)
    -- Beside Owner pets on this side of the stack: after them (their gap already clears the kit).
    local pf = ns._PF
    if across and pf.ownerActive and pf.ownerSideCur == side then
        off = pf.ownerGap + ((side == "above" or side == "below") and pf.ownerH or pf.ownerW) + gap
    end
    local resized = w ~= PT.w or h ~= PT.h
    -- The reserve's inputs (PT_ReserveOf): beside stacked frames the width and X offset, beside
    -- horizontal ones the height and Y offset, and along the stack the party frame's size too. A
    -- full layout (PT.w cleared) re-pins the attached groups, which read none meanwhile.
    local reserve = PT.w == nil or side ~= PT.side or across ~= PT.across or gap ~= PT.gap
        or horiz ~= PT.horiz
    if not reserve then
        if horiz then
            reserve = h ~= PT.h or y ~= PT.y or (not across and ph ~= PT.ph)
        else
            reserve = w ~= PT.w or x ~= PT.x or (not across and pw ~= PT.pw)
        end
    end
    PT.pw, PT.ph, PT.horiz = pw, ph, horiz
    if not (reserve or resized) and off == PT.off and x == PT.x and y == PT.y then return end
    PT.w, PT.h, PT.side, PT.gap, PT.off, PT.across, PT.x, PT.y = w, h, side, gap, off, across, x, y
    local sizeVisuals = ns._FB.SizeVisuals
    for _, frame in ipairs(ns._partyTargetFrames) do
        if resized then
            frame:SetSize(w, h)
            sizeVisuals(frame, w, h)
            frame._nameText:SetWidth(max(1, w - 6))
        end
        PT_Place(frame, frame._ptOwner, side, off, x, y)
    end
    if reserve then PT_NotifyReserve() end
end

-- The target frames' own style inputs after the shared ones: Fill Color and its custom colour,
-- Background (class or custom colour, darkness) and Smooth Bars.
local function PT_FpExtra(t)
    local p, n = db.profile, ns._PF.STYLE_N
    local fc = p.partyTargetCustomFillColor or PT.DEF_FILL
    local bc = p.partyTargetCustomBgColor or ns._PF.DEFAULT_BG
    t[n + 1], t[n + 2], t[n + 3], t[n + 4] = p.partyTargetHealthColorMode, fc.r, fc.g, fc.b
    t[n + 5], t[n + 6], t[n + 7], t[n + 8] = p.partyTargetBgClassColored, bc.r, bc.g, bc.b
    t[n + 9], t[n + 10] = p.partyTargetBgDarkness, PT_Source().smoothBars
end

-- Texture, name font and border from the party settings (the stock edge under a stock style), and
-- the colour settings the paint reads, fingerprinted together: a reload or setting that changed
-- none of them touches nothing; one that did repaints the frames on screen, restyling them only
-- when a shared input changed (a colour setting alone re-reads the colours). A change made while
-- off lands on the enable edge. Combat-legal: nothing here touches the secure buttons.
ns._PT_Restyle = function()
    if not ns._ptEnabled then return end
    local s = PT_Source()
    local texPath = ResolveHealthTexture(s)
    local changed, at = ns._PF.StyleChanged("pt", s, texPath, PT_FpExtra, PT.FP_N)
    if not changed then return end
    local p = db.profile
    local fc = p.partyTargetCustomFillColor or PT.DEF_FILL
    local bc = p.partyTargetCustomBgColor or ns._PF.DEFAULT_BG
    PT.mode = p.partyTargetHealthColorMode or "class"
    PT.fr, PT.fg, PT.fb = fc.r, fc.g, fc.b
    PT.bgClass = p.partyTargetBgClassColored and true or nil
    PT.br, PT.bgg, PT.bb = bc.r, bc.g, bc.b
    PT.bgA = (p.partyTargetBgDarkness or 50) / 100
    local interp = Enum.StatusBarInterpolation
    PT.smooth = (s.smoothBars and interp and interp.ExponentialEaseOut) or nil
    -- 0: nothing styled yet (new frames); up to STYLE_N: a shared input changed.
    if at <= ns._PF.STYLE_N then
        local nameSize = s.nameSize or 10
        local styleBorder = ns._FB.StyleBorder
        for _, frame in ipairs(ns._partyTargetFrames) do
            local health, bg = frame._health, frame._bg
            health:SetStatusBarTexture(texPath)
            local tex = health:GetStatusBarTexture()
            bg:ClearAllPoints()
            if tex then
                tex:SetHorizTile(false)
                -- The background covers the missing health only, off the fill's far edge.
                bg:SetPoint("TOPLEFT", tex, "TOPRIGHT", 0, 0)
                bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            else
                bg:SetAllPoints(health)
            end
            ApplyFont(frame._nameText, nameSize)
            styleBorder(frame)
        end
    end
    ns._PT_RepaintVisible()
end

-- Hover border, as the pets and the boss group.
local function PT_Enter(self)
    ns._FB.hov[self] = true
    ns._FB.ApplyBorderColor(self)
end
local function PT_Leave(self)
    ns._FB.hov[self] = nil
    ns._FB.ApplyBorderColor(self)
end

-- A frame coming on screen (its unit appeared, or its party frame showed): its unit re-read and a
-- full paint. Going off screen: the listeners follow.
local function PT_OnShow(self)
    if not ns._ptEnabled then return end
    PT_Classify(self)
    PT_Paint(self)
    PT_Recount()
end
local function PT_OnHide(self)
    PT_Recount(self)
end

-- The party header re-assigned an owner's unit (in combat too): its target frame follows at once.
-- The same unit set again (every header pass) returns after the compare.
local function PT_OwnerAttr(owner, name)
    if name ~= "unit" or not ns._ptEnabled then return end
    local frame = PT.frameOf[owner]
    if frame and PT_Classify(frame) and frame:IsVisible() then
        PT_Paint(frame)
        PT_Recount()
    end
end

-- Real-frame previews hide the real frames by alpha; while they do, a mouse blocker on each target
-- frame (they sit outside the party frames' blocker) keeps the invisible buttons from taking
-- clicks. Our frames, so Hide() is combat-legal; each blocker hides with its target frame.
ns._PT_SetPreviewBlock = function(on)
    PT.pvBlockOn = on or nil
    for _, frame in ipairs(ns._partyTargetFrames) do
        local blk = frame._ptBlock
        if on and ns._ptEnabled then
            if not blk then
                blk = CreateFrame("Frame", nil, frame)
                blk:SetAllPoints(frame)
                blk:EnableMouse(true)
                frame._ptBlock = blk
            end
            blk:SetFrameLevel(frame:GetFrameLevel() + 50)
            blk:Show()
        elseif blk then
            blk:Hide()
        end
    end
end

-- The enable/disable edges, a new frame and a frame strata change while blocked: re-seat the
-- blockers.
ns._PT_RefreshPreviewBlock = function()
    if PT.pvBlockOn then ns._PT_SetPreviewBlock(true) end
end

local function PT_Build(owner, globalName)
    local frame = CreateFrame("Button", globalName, owner, "SecureUnitButtonTemplate")
    frame:SetAttribute("useparent-unit", true)
    frame:SetAttribute("unitsuffix", "target")
    frame:SetAttribute("*type1", "target")
    frame:RegisterForClicks("AnyUp")
    frame:Hide()

    -- Background, health bar, texts and border frame (the stock edge under a stock style). The
    -- font comes with the next restyle, before the frame can show. Name only: no health texts.
    local FB = ns._FB
    FB.BuildVisuals(frame)
    local name = frame._nameText
    name:SetPoint("CENTER", frame._health, "CENTER", 0, 0)
    name:SetJustifyH("CENTER")
    name:SetJustifyV("MIDDLE")
    name:SetTextColor(1, 1, 1, 1)
    frame._healthText:Hide()
    frame._healAbsorbText:Hide()

    frame._ptOwner = owner
    FB.src[frame] = PT_Source
    frame:HookScript("OnShow", PT_OnShow)
    frame:HookScript("OnHide", PT_OnHide)
    frame:HookScript("OnEnter", PT_Enter)
    frame:HookScript("OnLeave", PT_Leave)
    -- Header buttons: the unit snippet reaches the frame through a frame ref, and a unit
    -- re-assignment re-reads it (a lookup table, never a key on the header's button).
    if owner ~= ns._partySelfButton then
        PT.frameOf[owner] = frame
        SecureHandlerSetFrameRef(owner, "ptframe", frame)
        owner:HookScript("OnAttributeChanged", PT_OwnerAttr)
    end
    table.insert(ns._partyTargetFrames, frame)
    return frame
end

-- The self button's frame (Show Self First / Last: its unit is "player", so it shows your target;
-- it hides with the self button while that is unused), built the first time Include Own Target is
-- on. True when built now. OOC only.
local function PT_EnsureSelf()
    if PT.selfFrame or not ns._partySelfButton then return false end
    PT.selfFrame = PT_Build(ns._partySelfButton, "ERFPartyTargetSelf")
    -- New frames take the next restyle in full.
    ns._PF.fp.pt = nil
    return true
end

-- One per party header button, built on the first enable. OOC only.
ns._PT_Create = function()
    if not ns._ptCreated and ns._partyHeader then
        ns._ptCreated = true
        for i = 1, 5 do
            local owner = ns._partyHeader[i]
            if owner then PT_Build(owner, "ERFPartyTarget" .. i) end
        end
        ns._PF.fp.pt = nil
    end
    if ns._ptInclDesired then PT_EnsureSelf() end
end

-- Include Own Target, applied: the self button's frame (built on first use) watched only while on,
-- the attributes and unit snippet that gate the header frame showing you, and your target's
-- listeners. Secure writes: out of combat; a combat call waits for the combat-end flush.
local function PT_ApplyInclude()
    if InCombatLockdown() then
        ns._ptSelfDirty = true
        return
    end
    ns._ptSelfDirty = nil
    local inc = (ns._ptEnabled and ns._ptInclDesired) and true or nil
    PT.include = inc
    if inc and PT_EnsureSelf() then
        -- Sized, placed and styled before it can show.
        PT.w = nil
        ns._PT_Layout()
        ns._PT_Restyle()
        ns._PT_RefreshPreviewBlock()
    end
    local sf = PT.selfFrame
    if sf and PT.selfWatched ~= inc then
        PT.selfWatched = inc
        if inc then
            PT_Classify(sf)
            RegisterUnitWatch(sf)
        else
            UnregisterUnitWatch(sf)
            sf:Hide()
        end
    end
    ns._ptNoSelf = (ns._ptEnabled and not inc) and true or nil
    PT_SeedAttrs()
    ns.PF_SyncUnitSnippet()
    PT_Recount()
end

-- The combat-end flush (ns.PF_Flush) of a deferred include edge or attribute seed.
ns._PT_SyncSelf = function()
    ns._ptSelfDirty = nil
    if ns._ptEnabled then PT_ApplyInclude() end
end

ns._PT_Apply = function()
    if ns._ptDesired == ns._ptEnabled then return end
    if InCombatLockdown() then
        ns.CombatQueue.Defer("PT_Apply", ns._PT_Apply)
        return
    end
    if ns._ptDesired then
        ns._PT_Create()
        -- The listeners, made once: roster and zoning, UNIT_TARGET (three, two units each), your
        -- target's events, and the hidden value ticker.
        if not ns._ptEventFrame then
            local f = ns.TakeShell()
            f:SetScript("OnEvent", PT_OnEvent)
            ns._ptEventFrame = f
            for k = 1, 3 do
                f = ns.TakeShell()
                f:SetScript("OnEvent", PT_OnEvent)
                PT.tgtEv[k] = f
            end
            f = ns.TakeShell()
            f:SetScript("OnEvent", PT_OnOwnEvent)
            PT.ownFrame = f
            f = ns.TakeShell()
            f:Hide()
            f:SetScript("OnUpdate", PT_Tick)
            PT.ticker = f
        end
        local events = ns._ptEventFrame
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        ns._ptEnabled = true
        PT.include = ns._ptInclDesired or nil
        -- A full layout (the attached groups gain the reserve), a style check and the units, then
        -- the frames come up: the attributes gating yours are set before the watches.
        PT.w = nil
        ns._PT_Layout()
        ns._PT_Restyle()
        ns._PT_RefreshAll()
        PT_ApplyInclude()
        for _, frame in ipairs(ns._partyTargetFrames) do
            if frame ~= PT.selfFrame then RegisterUnitWatch(frame) end
        end
    else
        ns._ptEnabled = false
        ns._ptEventFrame:UnregisterAllEvents()
        for _, frame in ipairs(ns._partyTargetFrames) do
            UnregisterUnitWatch(frame)
            frame:Hide()
        end
        PT.include, PT.selfWatched, ns._ptNoSelf = nil, nil, nil
        ns._ptLayoutDirty, ns._ptSelfDirty = nil, nil
        -- Every listener and the ticker off; the gate attributes cleared, so a unit snippet kept for
        -- the pets leaves the target frames alone.
        PT_Recount()
        PT_SeedAttrs()
        ns.PF_SyncUnitSnippet()
        -- The party frames close the pitch the frames held along the stack, and the attached
        -- groups take the room back.
        if (ns._ptPitchApplied or 0) ~= 0 then ns._LayoutPartyFrames() end
        PT_NotifyReserve()
    end
    ns._PT_RefreshPreviewBlock()
end

ns.PT_SetEnabled = function(on)
    ns._ptDesired = on and true or false
    ns._PT_Apply()
end

-- Include Own Target (options, profile swaps): applied now while on, else on the enable edge.
ns.PT_SetIncludeSelf = function(on)
    ns._ptInclDesired = on and true or false
    if ns._ptEnabled then PT_ApplyInclude() end
end

-- A Fill Color or Background setting changed (the options): the fingerprint-gated restyle, which
-- repaints the frames on screen when anything it reads changed. Nothing while off.
ns.PT_Refresh = function()
    if ns._ptEnabled then ns._PT_Restyle() end
end

-- Options preview: a made-up target beside each party preview frame while Party Targets is on, on
-- the real frames' visuals and with their size, side, offsets and colours. Plain frames, built the
-- first time a preview shows them; ns.PT_PreviewSpec measures them and the room they need.
PT.pv, PT.pvSpec = {}, {}
PT.PV = {
    { name = "Gnoll Brute", hp = 72, re = 2 },
    { name = "Kobold Miner", hp = 100, re = 4 },
    { name = "Defias Thug", hp = 38, re = 2 },
    { name = "Murloc Raider", hp = 85, re = 2 },
    { name = "Bristleback Boar", hp = 55, re = 4 },
}

-- The preview's target layout, or nil while Party Targets is off: as the real frames take it
-- (after the Beside Owner pets on their side: petSpec, the pets' preview spec), plus how far a
-- frame reaches past its party frame's edges (pads). s: the preview's view; pw, ph: its party
-- frame size. One reused table.
function ns.PT_PreviewSpec(s, pw, ph, petSpec)
    if s.partyShowTargets ~= true then return nil end
    local t = PT.pvSpec
    local w, h = PixelSnap(s.partyTargetWidth or 70), PixelSnap(s.partyTargetHeight or 33)
    local x, y = PixelSnap(s.partyTargetOffsetX or 0), PixelSnap(s.partyTargetOffsetY or 0)
    local gap = PixelSnap(PT_Gap(s))
    local side, extra, across = PT_Side(s)
    local off = gap + PixelSnap(extra)
    if across and petSpec and petSpec.owner and petSpec.side == side then
        off = petSpec.gap + ((side == "above" or side == "below") and petSpec.h or petSpec.w) + gap
    end
    t.w, t.h, t.x, t.y, t.gap, t.off, t.side, t.across, t.pw, t.ph = w, h, x, y, gap, off, side, across, pw, ph
    -- The frame's box from its party frame's centre.
    local l, b
    if side == "left" then
        l, b = x - off - pw / 2 - w, y - h / 2
    elseif side == "right" then
        l, b = x + off + pw / 2, y - h / 2
    elseif side == "below" then
        l, b = x - w / 2, y - off - ph / 2 - h
    else
        l, b = x - w / 2, y + off + ph / 2
    end
    t.padL, t.padR = max(0, -pw / 2 - l), max(0, l + w - pw / 2)
    t.padB, t.padT = max(0, -ph / 2 - b), max(0, b + h - ph / 2)
    return t
end

-- The room a preview spec takes beside the preview's party frames (the pets beside them), as
-- ns.PT_Reserve gives the real frames'.
function ns.PT_PreviewReserve(spec, horizontal, before)
    return spec and PT_ReserveOf(spec, horizontal, before) or 0
end

-- Preview target i at the spec's size: styled from the party settings, painted from the view s
-- (made-up mobs: Class Color reads their reaction).
local function PT_PvFrame(i, parent, s, spec)
    local FB = ns._FB
    local f = PT.pv[i]
    if not f then
        f = CreateFrame("Frame", nil, parent)
        FB.BuildVisuals(f)
        FB.src[f] = PT_Source
        local name = f._nameText
        name:SetPoint("CENTER", f._health, "CENTER", 0, 0)
        name:SetJustifyH("CENTER")
        name:SetJustifyV("MIDDLE")
        name:SetTextColor(1, 1, 1, 1)
        f._healthText:Hide()
        f._healAbsorbText:Hide()
        PT.pv[i] = f
    elseif f:GetParent() ~= parent then
        f:SetParent(parent)
    end
    f:SetFrameStrata(parent == UIParent and "HIGH" or parent:GetFrameStrata())
    local w, h = spec.w, spec.h
    f:SetSize(w, h)
    FB.SizeVisuals(f, w, h)
    local st = PT_Source()
    local health, bg, name = f._health, f._bg, f._nameText
    health:SetStatusBarTexture(ResolveHealthTexture(st))
    local tex = health:GetStatusBarTexture()
    bg:ClearAllPoints()
    if tex then
        tex:SetHorizTile(false)
        bg:SetPoint("TOPLEFT", tex, "TOPRIGHT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    else
        bg:SetAllPoints(health)
    end
    ApplyFont(name, st.nameSize or 10)
    name:SetWidth(max(1, w - 6))
    FB.StyleBorder(f)
    local mock = PT.PV[i]
    health:SetMinMaxValues(0, 100)
    health:SetValue(mock.hp)
    name:SetText(mock.name)
    local mode = s.partyTargetHealthColorMode or "class"
    if mode == "dark" then
        local r, g, b, a = EUI.GetDarkModeFill()
        health:SetStatusBarColor(r, g, b, 1)
        if tex then tex:SetAlpha(a) end
        bg:SetColorTexture(EUI.GetDarkModeBg())
    else
        if tex then tex:SetAlpha(1) end
        local rc = FACTION_BAR_COLORS[mock.re]
        if mode == "classic" then
            local p = mock.hp / 100
            health:SetStatusBarColor(p < 0.5 and 1 or (1 - (p - 0.5) * 2), p > 0.5 and 1 or (p * 2), 0, 1)
        elseif mode == "custom" then
            local c = s.partyTargetCustomFillColor or PT.DEF_FILL
            health:SetStatusBarColor(c.r, c.g, c.b, 1)
        else
            health:SetStatusBarColor(rc.r, rc.g, rc.b, 1)
        end
        local a = (s.partyTargetBgDarkness or 50) / 100
        if s.partyTargetBgClassColored then
            bg:SetColorTexture(rc.r, rc.g, rc.b, a)
        else
            local c = s.partyTargetCustomBgColor or ns._PF.DEFAULT_BG
            bg:SetColorTexture(c.r, c.g, c.b, a)
        end
    end
    f:Show()
    return f
end

-- The preview targets beside the party preview frames on screen, parented to parent (skip: your
-- own frame's index, without Include Own Target), or none without a spec.
function ns.PT_ShowPreview(spec, s, parent, skip)
    local n = 0
    if spec then
        for i = 1, 5 do
            local o = ns._partyPvFrames[i]
            if o and o:IsShown() and i ~= skip then
                n = n + 1
                PT_Place(PT_PvFrame(n, parent, s, spec), o, spec.side, spec.off, spec.x, spec.y)
            end
        end
    end
    for i = n + 1, #PT.pv do PT.pv[i]:Hide() end
end

function ns.PT_HidePreview()
    for _, f in ipairs(PT.pv) do f:Hide() end
end
end -- Party Targets scope block

-- Layout party frames: apply unitGrowth direction and cell spacing to the header.
ns._LayoutPartyFrames = function()
    if not ns._partyHeader then return end
    if InCombatLockdown() then return end

    local s = db.profile
    local pw, ph, pcs = ns.RF_PartyDims(s)
    local bw, bh, cs = PixelSnap(pw), PixelSnap(ph), PixelSnap(pcs)
    -- Party target frames along the stack sit between the frames: the pitch opens by their room.
    local along = ns.PT_AlongPitch(s)
    ns._ptPitchApplied = along
    cs = cs + along
    local unitGrowth = ns._PartyGrowth(s)

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
    ns._SizePartyContainer(bw, bh, cs, unitGrowth)

    -- Apply sort attributes + player visibility to the party header
    if not InCombatLockdown() then
        local pSortMode = s.partySortMode or s.sortMode
        local sortByRole = pSortMode == "ROLE"
        local roleOrder = s.partyRoleOrder or s.roleOrder or { "TANK", "HEALER", "DAMAGER" }
        -- A party set the group state hides takes no nameList: a nameList is also
        -- a filter, and the visibility driver can show the set mid-fight, when no
        -- list can be rebuilt, so a stale one would drop the new members. The
        -- shown pass (_UpdatePartyVisibility) applies the lists.
        local _, live = ns._RFVisWanted()
        -- Sort By = FrameSort: a nameList in FrameSort's order (native index
        -- order while FrameSort is absent or its list is empty).
        local fsRank = live and (pSortMode == "FRAMESORT") and ns._FrameSortRanks(not ns._fsFromProvider) or nil
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
        local smallRaidGroup = ns._SmallRaidGroup()
        if not live then
            -- Hidden set: the native path below.
        elseif ns._PartyInRaid() then
            -- Party-in-raid runs on raid units, where Prioritize Class cannot
            -- work (it iterates party1-4) and neither the self button nor
            -- showPlayer can order or hide the player. A raid-token nameList
            -- does both: it honors Show Self First / Self Last / Hide Self and
            -- still shows every teammate -- the whole team in arena, group 1
            -- only in Small Raid mode (bailing to native order until names
            -- resolve; the fallback groupFilter below keeps the group limit).
            if fsRank then
                wantNameList = ns._BuildFrameSortRaidPartyNameList(fsRank, hideSelf, smallRaidGroup)
            end
            if not wantNameList then
                local pSelfFirst = s.partyShowSelfFirst
                if pSelfFirst == nil then pSelfFirst = s.showSelfFirst end
                local pSelfLast = s.partySelfLast
                if pSelfLast == nil then pSelfLast = s.showSelfLast end
                wantNameList = ns._BuildArenaNameList(hideSelf, pSelfFirst, pSelfLast, sortByRole, roleOrder, smallRaidGroup)
            end
        elseif fsRank then
            wantNameList = ns._BuildFrameSortPartyNameList(fsRank, wantShowPlayer)
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
            -- Small Raid keeps its group-1 limit in a party too (every party member
            -- is subgroup 1 there), so a party the driver keeps shown as it turns
            -- into a small raid mid-fight shows group 1, not the first five raiders.
            local fGroup = smallRaidGroup or ((s.partySmallRaid == true and not ns._InArena()) and 1) or nil
            wantGroupFilter = fGroup and tostring(fGroup) or "1,2,3,4,5,6,7,8"
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
        if needsHideShow then ns._fsChanged = true end
        if needsHideShow and ns._partyHeader:IsShown() then
            ns._partyHeader:Hide()
            ApplyAttrs()
            ns._partyHeader:Show()
        elseif needsHideShow then
            ApplyAttrs()
        end
        -- Which layout the header now carries (shown: full; hidden: native), for
        -- _UpdatePartyVisibility to re-lay it when the set hides.
        ns._partyLaidVis = live
    end

    -- Self button + header slot positioning ran above (ns._PositionPartySlots),
    -- before the attribute pass so a header Hide/Show re-process anchors the
    -- children against the already-correct header position and size.

    -- The friendly boss group attaches to this container (and to the growth axis derived above)
    -- while not in a raid, so every layout pass -- Horizontal Frames, Flip Growth, party size,
    -- cell spacing -- has to move it too. OOC only (this function bails in combat). In a raid the
    -- boss group hangs off the raid headers instead, so skip the re-anchor scan there.
    if (not IsInRaid() or ns._PartyInRaid()) and ns.FB_ReAnchor then ns.FB_ReAnchor() end
    -- The party target frames ride FB_ReAnchor above; this covers the raid branch that skips it
    -- (delta-gated, a no-op after it).
    ns._PT_Layout()
end

-- Party visibility: show/hide based on group state.
-- Party portraits (the Party Frames kit's socket, or the PORTRAIT section):
-- the portrait events, registered only while the party frames are shown
-- with a portrait that needs them (nothing runs while they are hidden, the
-- portrait is off or it shows class art; UNIT_MODEL_CHANGED for a 3D model
-- alone). Tokens a party button can hold: player/party1-4 in a party,
-- raid1-9 in arena and Small Raid mode (group 1 of a raid under 10 members
-- can sit at any raid index up to 9). Turning them on repaints every
-- portrait once, which covers any change made while the frames were hidden.
-- Called on the visibility edges and after every party reload (settings).
ns._kitPortraitUnits = { "player", "party1", "party2", "party3", "party4",
    "raid1", "raid2", "raid3", "raid4", "raid5", "raid6", "raid7", "raid8", "raid9" }
ns.RF_KitPortraitEvents = function(on)
    -- Before the unit trackers exist there is nothing to register yet.
    if not unitTrackers.player then return end
    local kit = ns.RF_PartyKit()
    on = on and true or false
    -- Kit hide edge: its always-on power registrations go too.
    if kit and ns._kitShownEv ~= on then
        ns._kitShownEv = on
        if not on and ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
    end
    local art = on and ns.RF_PtEventMode and ns.RF_PtEventMode(kit) or nil
    local want, wantModel = art ~= nil, art == "3d"
    local was, wasModel = ns._kitPortraitEv or false, ns._ptModelEv or false
    if was == want and wasModel == wantModel then return end
    ns._kitPortraitEv, ns._ptModelEv = want, wantModel
    local units = ns._kitPortraitUnits
    for i = 1, #units do
        local u = units[i]
        local t = unitTrackers[u]
        if t then
            if want ~= was then
                if want then t:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", u)
                else t:UnregisterEvent("UNIT_PORTRAIT_UPDATE") end
            end
            if wantModel ~= wasModel then
                if wantModel then t:RegisterUnitEvent("UNIT_MODEL_CHANGED", u)
                else t:UnregisterEvent("UNIT_MODEL_CHANGED") end
            end
        end
    end
    if want and not was then
        eventFrame:RegisterEvent("PORTRAITS_UPDATED")
        -- 2D art and the kit socket repaint; a 3D model repaints on its own
        -- show edge (and on a settings swap through its cleared memos).
        if ns.RF_PtRepaintAll then ns.RF_PtRepaintAll("Resync") end
    elseif was and not want then
        eventFrame:UnregisterEvent("PORTRAITS_UPDATED")
    end
end

ns._UpdatePartyVisibility = function()
    if not ns._partyHeader then return end
    if InCombatLockdown() then return end
    if ns._partyPvActive then return end
    if previewActive then return end
    -- Defensive: re-assert full opacity unless a size preview is dimming the
    -- real frames (see UpdateVisibility). Out of combat only (bails above).
    if not ns._sizePreviewTier and ns._partyContainerFrame then
        local dimmed = ns._partyContainerFrame:GetAlpha() ~= 1
        ns._partyContainerFrame:SetAlpha(1)
        if ns._ptModelOn then ns.RF_PtContainerAlpha(1) end
        if dimmed then ns._PF_AlphaSync() end
    end

    local s = db.profile
    -- Profile and spec-override swaps: Include Own Target first, so an enable edge below takes it.
    if ns._ptInclDesired ~= (s.partyTargetIncludeSelf == true) then
        ns.PT_SetIncludeSelf(s.partyTargetIncludeSelf)
    end
    -- An enable edge here refreshes the target frames itself (the show edge below then skips it).
    local ptWas = ns._ptEnabled
    if ns._ptDesired ~= (s.partyShowTargets == true) then
        ns.PT_SetEnabled(s.partyShowTargets)
    end
    -- Arena and Small Raid mode show party frames even though IsInRaid() is
    -- true. The header binds raid units via showRaid=true; the raid container
    -- is hidden there by UpdateVisibility.
    local _, visible = ns._RFVisWanted()
    local wasVisible = ns._partyFramesVisible
    ns._partyFramesVisible = visible
    if ns._NotifyTrackerProviders then ns._NotifyTrackerProviders() end

    -- Update showSolo attribute, but only when it changed -- re-setting a
    -- SecureGroupHeader attribute re-triggers a full child re-process even when
    -- unchanged (see UpdateVisibility's showSolo guard).
    local wantPartySolo = s.partyShowWhenSolo or false
    if ns._partyHeader and ns._partyHeader:GetAttribute("showSolo") ~= wantPartySolo then
        ns._partyHeader:SetAttribute("showSolo", wantPartySolo)
    end

    -- Only the container shows and hides (the header stays shown inside it);
    -- the driver decides the same way, synced first so the two agree this frame.
    ns._RFSyncVisDrivers()
    ns._partyContainerFrame:SetShown(visible)
    if visible then
        -- Suppress Blizzard party frames
        if ns._SuppressBlizzParty then
            ns._SuppressBlizzParty()
        end

        ns._LayoutPartyFrames()
        ns._RebuildPartyUnitMap()
        if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
        ns._UpdateAllPartyButtons()
        ns.RF_KitPortraitEvents(true)

        if IsInGroup() then
            StartRangeTicker()
            StartGhostTicker()
        end
    else
        if not framesVisible then
            StopRangeTicker()
            StopGhostTicker()
        end

        if wasVisible then ns._RFForgetOccupants(ns._partyAllButtons) end
        wipe(ns._partyUnitToButton)
        ns.RF_KitPortraitEvents(false)
        -- A hidden set runs native (see _LayoutPartyFrames), so the driver can
        -- show it mid-fight with every member in place.
        if ns._partyLaidVis ~= false then ns._LayoutPartyFrames() end
    end

    -- Attach-point edges the layout pass above cannot cover: the boss group's own roster pass can
    -- run before the party frames are up, and the hidden branch lays out only when the set hides
    -- (the group then falls back to its free position). EDGE only -- this recompute runs on every
    -- roster event.
    if ns._fbPartyAttachState ~= visible then
        ns._fbPartyAttachState = visible
        if ns.FB_ReAnchor then ns.FB_ReAnchor() end
    end
    -- Party target frames skip roster refreshes while the party frames are hidden: their show edge
    -- takes one (units, your raid token, the listeners). EDGE only.
    if ns._ptVisState ~= visible then
        ns._ptVisState = visible
        if visible and ptWas then ns._PT_RefreshAll() end
    end
end

-- Combat half of the two passes above. In combat the visibility drivers show
-- and hide the containers themselves; this keeps the Lua side in step with no
-- protected call: the flags that gate unit events, the routing maps, the range
-- and ghost tickers, the power and portrait registrations, the tracker
-- providers. The shown set's header re-reads the roster as it shows, and each
-- assignment remaps and repaints its button. Edge-gated (a roster storm with no
-- set change costs two compares); an edge marks the roster dirty so combat end
-- runs the full passes (layout, sort, sizes).
ns._RFCombatVisEdge = function()
    local raid, party = ns._RFVisWanted()
    local raidEdge = raid ~= (framesVisible == true)
    local partyEdge = party ~= (ns._partyFramesVisible == true)
    if not raidEdge and not partyEdge then return end
    ns._rosterDirtyInCombat = true
    if raidEdge then
        framesVisible = raid
        ns._raidFramesVisible = raid
        if not raid then
            ns._RFForgetOccupants(allButtons)
            wipe(unitToButton)
        end
    end
    if partyEdge then
        ns._partyFramesVisible = party
        if not party then
            ns._RFForgetOccupants(ns._partyAllButtons)
            wipe(ns._partyUnitToButton)
        end
        ns.RF_KitPortraitEvents(party)
    end
    if raid or party then
        if IsInGroup() then
            StartRangeTicker()
            StartGhostTicker()
        end
    else
        StopRangeTicker()
        StopGhostTicker()
    end
    if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
    if ns._NotifyTrackerProviders then ns._NotifyTrackerProviders() end
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
    local pxSib = ns._PARTY_PX_SIBLING
    for key, section in pairs(ns._PARTY_KEY_SECTION) do
        if ns._IsPartySectionCustom(section) then
            local pv = rawget(raw, "party_" .. key)
            -- An exact-size companion swaps whenever its sibling does (its party
            -- value may be nil): recorded in `swapped` so the restore writes it back.
            local sib = pxSib[key]
            if pv ~= nil or (sib and rawget(raw, "party_" .. sib) ~= nil) then
                swapped[#swapped + 1] = key
                saved[key] = raw[key]
                raw[key] = pv
            end
        end
    end

    -- Now db.profile has party values in place. Read from it directly for
    -- sizing (which also needs party width/height overrides).
    local pw, ph, _, pres = ns.RF_PartyDims(raw)
    local bw, bh = PixelSnap(pw), PixelSnap(ph)
    -- The bars' width (an attached portrait takes its share of the box).
    local barW = bw - ((pres and pres > 0) and PixelSnap(pres) or 0)
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

        -- Party portrait (EUI_RaidFrames_Portrait.lua; the kit keeps its own):
        -- ahead of the bar layout below, which hangs the bars off its area.
        if not d.kit then
            local pu = btn:GetAttribute("unit")
            ns.RF_PtApply(btn, d, pp, bw, bh, pu and UnitExists(pu) and pu or nil)
        end

        -- Health bar height/anchor + Top Name Bar (reads party-resolved `raw`).
        -- The Party Frames kit owns its bar rects (its pass runs below, after
        -- the texture swaps, so its masks seat on the new fills).
        if not d.kit then
            LayoutTopNameBar(raw, bh, powerH, d.health, d.topNameBar, d.topNameBarBg, d.topNameBarText, d.power)
        end
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
        if d.kit then
            -- Party Frames kit: the mana bar always shows in the art's track
            -- (no role gate, no height); then the kit pass itself.
            if d.power then
                d.power:SetStatusBarTexture(texPath)
                d.power:GetStatusBarTexture():SetHorizTile(false)
            end
            local u = btn:GetAttribute("unit")
            ns.RF_ApplyPartyKit(btn, d, pp, u and UnitExists(u) and u or nil)
        else
            d._appliedHidePower = nil
            if d.power then
                d.power:Hide()
                if powerH > 0 then
                    d.power:SetHeight(powerH)
                    d.power:SetStatusBarTexture(texPath)
                    d.power:GetStatusBarTexture():SetHorizTile(false)
                end
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
            -- Override width constraint for party button dimensions (the
            -- kit's name width is its closure's own).
            if not d.kit then d.nameText:SetWidth(barW * ns.RF_NAME_WIDTH_FRACTION) end
        end

        -- Health text
        if d.healthText then
            ApplyFont(d.healthText, pp.healthTextSize or 9)
            if d.AnchorHealthText then d.AnchorHealthText() end
        end

        -- Power text: hidden with the bar above (not under the kit, whose mana bar stays shown)
        -- until _UpdateAllPartyButtons below shows it again, and restyled.
        if d.powerText then
            if not d.kit then d.powerText:Hide(); d._pwtMode = nil end
            ApplyFont(d.powerText, pp.powerTextSize or 8)
            ns._RFAnchorPowerText(d)
        end

        -- Level text: restyled; _UpdateAllPartyButtons below shows or hides it by position.
        if d.levelText then
            ApplyFont(d.levelText, pp.levelTextSize or 10)
            ns._RFAnchorLevelText(d)
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
            if d.kitG then
                ns.RF_KitLeader(d, pp)
            else
                d.leaderIcon:ClearAllPoints()
                local liPos = (raw.leaderIconPosition or "top"):upper()
                d.leaderIcon:SetPoint(liPos, ns.RF_AnchorHost(d.health, pp), liPos, pp.leaderIconOffsetX or 0, pp.leaderIconOffsetY or 0)
            end
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
        if ns.RF_FvMissingAnchor then ns.RF_FvMissingAnchor(btn, d) end

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
    -- Party Frames kit: an attached Friendly Boss group clears the kit's
    -- outside auras, which these settings move (out of combat only).
    if ns.RF_PartyKit() and ns.FB_ReAnchor and not InCombatLockdown() then ns.FB_ReAnchor() end
    -- Portrait events follow the portrait settings (a no-op when unchanged).
    ns.RF_KitPortraitEvents(ns._partyFramesVisible)
    -- Pets and target frames beside the party frames are styled from the party settings.
    if not skipButtons then
        ns.PF_PartyRestyle()
        ns._PT_Restyle()
    end
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
        local fontPath = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        local outline = (EllesmereUI.GetFontOutlineFlag("raidFrames")) or "OUTLINE"
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
                    local col = token and ((EllesmereUI.GetClassColor(token))
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
                    nameFS:SetFormattedText("%s", (unit and EllesmereUI.WithSurname(UnitName(unit))) or "")
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

ns.GetFFD = GetFFD
-- Main-chunk locals EUI_RaidFrames_Preview.lua re-imports by name.
ns._internals = {
    ApplyFont = ApplyFont, ApplyRoleIcon = ApplyRoleIcon, DISPEL_ICON_ATLAS = DISPEL_ICON_ATLAS,
    GetDispelColor = GetDispelColor, IsPowerBarEnabled = IsPowerBarEnabled, LayoutGroups = LayoutGroups,
    LayoutTopNameBar = LayoutTopNameBar, MOVER_GROUPS = MOVER_GROUPS,
    ResolveHealthTexture = ResolveHealthTexture, defaults = defaults,
}

-------------------------------------------------------------------------------
--  External tracker integration (frame-provider APIs)
-------------------------------------------------------------------------------
-- Some cooldown/defensive tracker addons anchor icons onto party/raid unit
-- frames, found via a hardcoded addon list or a public provider API. EUI
-- frames are custom, so where a provider API exists we hand it our buttons;
-- the unit lives on the secure "unit" attribute (GetAttribute), so no plain
-- field on the button is needed. Name-scanning trackers (LibGetFrame) match our
-- button names from that library's default priority list, but the match only runs
-- against a frame list it caches (see ns._NotifyTrackerProviders).

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

-- Public unit -> frame lookup for any addon wanting our raid or party frame.
-- LibGetFrame cannot answer on an addon-restricted map: it keeps a cached frame
-- only when UnitIsUnit(frameUnit, target) is non-secret, and that call is
-- SecretWhenUnitComparisonRestricted, so every frame is skipped there however
-- fresh the cache. This compares nothing -- it reads the secure "unit"
-- attribute the header wrote. Extra frames answer last: they duplicate a unit
-- already on a real raid button.
function EllesmereUI.GetUnitFrame(unit)
    if type(unit) ~= "string" then return nil end
    local function Find(list)
        if not list then return nil end
        for _, btn in ipairs(list) do
            if btn:IsVisible() then
                local u = btn:GetAttribute("unit")
                -- type() reports a secret's underlying type, so a secret
                -- attribute would pass as a string and the compare would throw:
                -- probe for secrecy first, never compare a secret.
                if type(u) == "string" and not (issecretvalue and issecretvalue(u)) then
                    if u == unit then return btn end
                    -- The header gives the player's own button a raidN token, so
                    -- a literal compare never finds "player". UnitIsUnit answers
                    -- a SECRET boolean for a restricted pairing (or nil when the
                    -- compare is refused); only a plain true counts, and a secret
                    -- is never looked at.
                    if unit == "player" then
                        local ok, same = pcall(UnitIsUnit, u, "player")
                        if ok and not (issecretvalue and issecretvalue(same)) and same == true then
                            return btn
                        end
                    end
                end
            end
        end
        return nil
    end
    return Find(ns._partyAllButtons) or Find(allButtons) or ns._xfUnitToButton[unit]
end

-- Notifies subscribed providers that our frame set changed, debounced to one
-- refresh per frame. Driven from the visibility paths -- the one change a
-- provider cannot learn from its own roster events.
--
-- LibGetFrame resolves units against a frame list it caches, rebuilt only on its
-- own six events and recording only buttons visible at that instant. Our header
-- set builds lazily and defers combat-time changes to regen, so the cache can
-- miss the whole set with no event left to correct it; consumers then read nil
-- and silently do nothing. ScanForUnitFrames is its public invalidation (queued
-- and time-sliced). Resolved per call, not cached: either provider may load late.
-- Never asked for in combat: the library's walk reads every frame bare and our
-- aura containers deny tainted reads while auras are secret, so a mid-fight
-- scan can drop every EUI frame for the rest of the fight. The library
-- rescans on its own at PLAYER_REGEN_ENABLED, so the regen pass covers it.
ns._NotifyTrackerProviders = function()
    if ns._trackerRefreshPending then return end
    local cb = ns._trackerRefreshCb
    local lgf = LibStub and LibStub("LibGetFrame-1.0", true)
    if not cb and not (lgf and lgf.ScanForUnitFrames) then return end
    ns._trackerRefreshPending = true
    C_Timer.After(0, function()
        ns._trackerRefreshPending = false
        if cb then pcall(cb) end
        if lgf and not InCombatLockdown() then pcall(lgf.ScanForUnitFrames) end
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
    ns._PreviewBind(db, PP, containerFrame)

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
    ns._PreviewBind(db, PP, containerFrame)

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

    -- Stock styles: a profile that arrives already switched (an import, an
    -- older build) gets the style's first-visit defaults once, before the
    -- proxies below materialize them.
    if ns.RF_Stock() then ns.RF_SeedStock(db.profile, ns.RF_Style()) end
    ns.RF_MigrateSmRaidBar(db.profile)
    ns._FrameSortRegister()

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

    -- Both containers show and hide through their visibility drivers from here
    -- on, registered in the login window so a /reload in combat has them too.
    -- Blizzard's PartyFrame goes down here too, so it can never stand in for
    -- ours (a group joined in combat).
    ns._RFSyncVisDrivers()
    ns._SuppressBlizzParty(true)

    -- Size + position party container from profile
    do
        local s = db.profile
        local pw, ph, pcs = ns.RF_PartyDims(s)
        ns._SizePartyContainer(PixelSnap(pw), PixelSnap(ph), PixelSnap(pcs) + ns.PT_AlongPitch(s), ns._PartyGrowth(s))
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
    -- Pet frames: built and styled here, once (in the login window, so a combat /reload has them);
    -- the deferred reloads below find their style unchanged.
    ns.PF_Apply(true)

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
        local pw, ph, pcs = ns.RF_PartyDims(s)
        ns._SizePartyContainer(PixelSnap(pw), PixelSnap(ph), PixelSnap(pcs) + ns.PT_AlongPitch(s), ns._PartyGrowth(s))
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
        -- Friendly Boss Frames and Extra Frames re-read the swapped profile (the pet frames did at
        -- the tails of the raid and party reloads above).
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

    -- Level Text's UNIT_LEVEL: registered on every tracker only while a view shows the
    -- level. Called from _RefreshProxyModes (every settings write, reload and profile
    -- swap); the stamp keeps the 45-tracker walk to real flips.
    local lvlRegistered = false
    function ns._RFSyncLevelRegistration()
        local want = ns._RFLevelWanted()
        if want == lvlRegistered then return end
        lvlRegistered = want
        for unit, tracker in pairs(unitTrackers) do
            if want then
                tracker:RegisterUnitEvent("UNIT_LEVEL", unit)
            else
                tracker:UnregisterEvent("UNIT_LEVEL")
            end
        end
    end
    ns._RFSyncLevelRegistration()

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
                if not wantPower and (unit == "player" or unit:match("^party%d$")
                        or (ns._partyUnitToButton and ns._partyUnitToButton[unit])) then
                    if ns.RF_PartyKit() then
                        -- Party Frames kit: the stock mana bar always shows
                        -- (while the party frames are shown; the hide edge
                        -- re-runs this through RF_KitPortraitEvents).
                        wantPower = ns._partyFramesVisible and true or false
                    elseif IsPowerBarEnabled(ps) then
                        wantPower = wantsPower(ps, role)
                    end
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
        -- A /reload in combat never sees PLAYER_REGEN_DISABLED: take the combat
        -- state from the lockdown, and let the combat edge set the visibility
        -- flags the two passes below skip in combat.
        if InCombatLockdown() then
            inCombat = true
            ns._RFCombatVisEdge()
            -- Members assigned while the flag was still down (the first half
            -- second) were kept out of the map; the raid branch below rebuilds too.
            if ns._partyFramesVisible then ns._RebuildPartyUnitMap() end
        end
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

-------------------------------------------------------------------------------
--  Party Mode: spinning party and raid frames (EllesmereUI.PartySpin_Create).
--  Each set's shown buttons orbit the centre of its container, so the 5-slot
--  party box turns around its third frame. homeInCombat puts the secure
--  buttons back on the header layout for each fight.
--  do/end scope: 200-local main-chunk cap.
-------------------------------------------------------------------------------
do
    -- A header's shown buttons, in child order.
    local function AddShown(hdr, list)
        if not (hdr and hdr:IsVisible()) then return end
        local i, b = 1, hdr:GetAttribute("child1")
        while b do
            if b:IsVisible() then list[#list + 1] = b end
            i = i + 1
            b = hdr:GetAttribute("child" .. i)
        end
    end

    local partyList = {}
    local partyGroup = { frames = partyList }
    local partyGroups = {}
    EllesmereUI.PartySpin_Create({
        target = "partyFrames",
        homeInCombat = true,
        collect = function()
            wipe(partyList); wipe(partyGroups)
            local box = ns._partyContainerFrame
            if box and box:IsVisible() then
                AddShown(ns._partyHeader, partyList)
                local sb = ns._partySelfButton
                if sb and sb:IsVisible() then partyList[#partyList + 1] = sb end
                partyGroup.pivot = box
                partyGroups[1] = partyGroup
            end
            return partyGroups
        end,
    })

    local raidList = {}
    local raidGroup = { frames = raidList }
    local raidGroups = {}
    EllesmereUI.PartySpin_Create({
        target = "raidFrames",
        homeInCombat = true,
        collect = function()
            wipe(raidList); wipe(raidGroups)
            if containerFrame and containerFrame:IsVisible() then
                for g = 1, 8 do AddShown(separatedHdrs[g], raidList) end
                AddShown(ns._flatHeader, raidList)
                raidGroup.pivot = containerFrame
                raidGroups[1] = raidGroup
            end
            return raidGroups
        end,
    })
end
