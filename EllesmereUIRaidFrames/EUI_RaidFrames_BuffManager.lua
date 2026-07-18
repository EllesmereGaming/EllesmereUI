-------------------------------------------------------------------------------
--  EUI_RaidFrames_BuffManager.lua
--  Indicator-centric buff manager for EllesmereUI Raid Frames.
--  Users create indicators (icon/square/bar/healthcolor/border/framealpha),
--  assign one or more whitelisted healer spells, and configure position,
--  size, color, and growth direction. Up to 20 indicators per spec.
--
--  Performance model: event-driven UNIT_AURA, pre-built
--  spell-to-indicator hash lookup, no per-frame allocations, wipe() reuse.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local pairs    = pairs
local ipairs   = ipairs
local tinsert  = table.insert
local tremove  = table.remove
local wipe     = wipe
local floor    = math.floor
local max      = math.max
local min      = math.min
local tostring = tostring
local tonumber = tonumber
local type     = type
local CreateFrame   = CreateFrame
local issecretvalue = issecretvalue
local C_UnitAuras   = C_UnitAuras
local C_Spell       = C_Spell
local UnitExists    = UnitExists
local UnitIsUnit    = UnitIsUnit

local MAX_PER_SPEC = 20

-------------------------------------------------------------------------------
--  Indicator type definitions
-------------------------------------------------------------------------------
local INDICATOR_TYPES = {
    { key = "icon",        name = "Icon",             placed = true },
    { key = "square",      name = "Square",           placed = true },
    { key = "bar",         name = "Bar",              placed = true, singleSpell = true },
    -- divider
    { key = "healthcolor", name = "Health Bar Color",  placed = false },
    { key = "border",      name = "Frame Border",     placed = false },
    { key = "framealpha",  name = "Frame Alpha",      placed = false },
}

-- Quick lookup
local INDICATOR_TYPE_MAP = {}
for _, t in ipairs(INDICATOR_TYPES) do INDICATOR_TYPE_MAP[t.key] = t end

-- For dropdown
local INDICATOR_TYPE_VALUES = {}
local INDICATOR_TYPE_ORDER = {}
for _, t in ipairs(INDICATOR_TYPES) do
    INDICATOR_TYPE_VALUES[t.key] = t.name
    -- 12.1 only: Frame Border indicators cannot be created there (no
    -- aura-container equivalent); existing ones stay listed with a removal
    -- notice. On 12.0 the type remains fully creatable.
    if not (EllesmereUI.IS_121 and t.key == "border") then
        INDICATOR_TYPE_ORDER[#INDICATOR_TYPE_ORDER + 1] = t.key
    end
end
-- Insert divider after "bar"
tinsert(INDICATOR_TYPE_ORDER, 4, "---")

-- 12.1 PTR: gray blocking overlay with a red removal notice, for settings
-- whose backing machinery has no aura-container equivalent (styled after
-- the party-tab sync overlays). UI-only; the runtime side of these
-- settings is inert elsewhere. Callers anchor the returned frame.
local function BuildPTROverlay(parentFrame, label, fontSize)
    local ov = CreateFrame("Frame", nil, parentFrame)
    ov._searchIgnore = true -- inline search must never re-anchor/collapse it
    ov:SetFrameLevel(parentFrame:GetFrameLevel() + 60)
    ov:EnableMouse(true)
    local bg = ov:CreateTexture(nil, "OVERLAY")
    bg:SetAllPoints()
    bg:SetColorTexture(0.10, 0.10, 0.12, 0.95)
    local fs = ov:CreateFontString(nil, "OVERLAY")
    local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    fs:SetFont(fp, fontSize or 12, "")
    fs:SetPoint("LEFT", ov, "LEFT", 8, 0)
    fs:SetPoint("RIGHT", ov, "RIGHT", -8, 0)
    fs:SetJustifyH("CENTER")
    fs:SetTextColor(0.86, 0.24, 0.24, 0.95)
    fs:SetText(EllesmereUI.Lf("%1$s Removed in 12.1 Unless API Changes", EllesmereUI.L(label)))
    ov._msg = fs
    return ov
end

-- 9-position grid
local POSITION_VALUES = {
    TOPLEFT     = "Top Left",
    TOP         = "Top",
    TOPRIGHT    = "Top Right",
    LEFT        = "Left",
    CENTER      = "Center",
    RIGHT       = "Right",
    BOTTOMLEFT  = "Bottom Left",
    BOTTOM      = "Bottom",
    BOTTOMRIGHT = "Bottom Right",
}
local POSITION_ORDER = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

-- Growth directions
local GROW_VALUES = {
    RIGHT  = "Right",
    LEFT   = "Left",
    UP     = "Up",
    DOWN   = "Down",
    CENTER = "Center",
}
local GROW_ORDER = { "RIGHT", "LEFT", "UP", "DOWN", "CENTER" }

-- Bar orientation
local ORIENT_VALUES = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }
local ORIENT_ORDER = { "HORIZONTAL", "VERTICAL" }

-- Show when mode (for frame effects)
local SHOW_WHEN_VALUES = { present = "When Any Present", allPresent = "When All Present", anyMissing = "When Any Missing", missing = "When All Missing" }
local SHOW_WHEN_ORDER = { "present", "allPresent", "anyMissing", "missing" }

-- Indicator frame level (layering relative to the unit button). For Icon/Square
-- the indicator's own border sits at base + 1 and its count/duration text carrier
-- is pinned at +18 regardless of mode. Bars use the base only (no sub-frames).
local FRAMELVL_VALUES = {
    behindBorders = "Behind Borders",
    behindText    = "Behind Text",
    medium        = "Medium",
    high          = "High",
    highest       = "Highest",
}
local FRAMELVL_ORDER = { "behindBorders", "behindText", "medium", "high", "highest" }
local FRAMELVL_BASE = {
    behindBorders = 7,   -- below the main border (+8)
    behindText    = 11,  -- below the name/health text carrier (+12), above borders
    medium        = 13,  -- ns.LVL_AURA: the original/default band
    high          = 14,
    highest       = 15,
}
local FRAMELVL_TEXT = 18  -- fixed count/duration text-carrier offset (icon/square)

-------------------------------------------------------------------------------
--  Healer spell database
--  Spells marked secret = true are identified
--  via filter fingerprinting (future support), not direct spellId reading.
--  hide = true means alternate spell ID that maps to same aura (skip in UI).
-------------------------------------------------------------------------------
local HEALER_SPECS = {
    {
        key = "DRUID_RESTORATION",
        specID = 105,
        name = "Restoration Druid",
        classToken = "DRUID",
        spells = {
            { id = 774,    name = "Rejuvenation" },
            { id = 8936,   name = "Regrowth" },
            { id = 33763,  name = "Lifebloom" },
            { id = 155777, name = "Germination" },
            { id = 48438,  name = "Wild Growth" },
            { id = 439530, name = "Symbiotic Blooms" },
            { id = 102342, name = "Ironbark", secret = true, sig = "1:1:1:0" },
        },
    },
    {
        key = "PRIEST_DISCIPLINE",
        specID = 256,
        name = "Discipline Priest",
        classToken = "PRIEST",
        spells = {
            { id = 17,      name = "Power Word: Shield" },
            { id = 194384,  name = "Atonement" },
            { id = 1253593, name = "Void Shield" },
            { id = 41635,   name = "Prayer of Mending" },
            { id = 33206,   name = "Pain Suppression", secret = true, sig = "1:1:1:0" },
            { id = 10060,   name = "Power Infusion", secret = true, sig = "1:0:0:1" },
        },
    },
    {
        key = "PRIEST_HOLY",
        specID = 257,
        name = "Holy Priest",
        classToken = "PRIEST",
        spells = {
            { id = 139,   name = "Renew" },
            { id = 77489, name = "Echo of Light" },
            { id = 41635, name = "Prayer of Mending" },
            { id = 47788, name = "Guardian Spirit", secret = true, sig = "1:1:1:0" },
            { id = 10060, name = "Power Infusion", secret = true, sig = "1:0:0:1" },
        },
    },
    {
        key = "MONK_MISTWEAVER",
        specID = 270,
        name = "Mistweaver Monk",
        classToken = "MONK",
        spells = {
            { id = 119611, name = "Renewing Mist" },
            { id = 124682, name = "Enveloping Mist" },
            { id = 115175, name = "Soothing Mist" },
            { id = 450769, name = "Aspect of Harmony" },
            { id = 116849, name = "Life Cocoon", secret = true, sig = "1:1:1:0" },
            { id = 443113, name = "Strength of the Black Ox", secret = true, sig = "0:1:0:1" },
        },
    },
    {
        key = "SHAMAN_RESTORATION",
        specID = 264,
        name = "Restoration Shaman",
        classToken = "SHAMAN",
        spells = {
            { id = 61295,  name = "Riptide" },
            { id = 974,    name = "Earth Shield" },
            { id = 383648, name = "Earth Shield", hide = true },
            { id = 382024, name = "Earthliving Weapon" },
            { id = 207400, name = "Ancestral Vigor" },
            { id = 444490, name = "Hydrobubble" },
        },
    },
    {
        key = "PALADIN_HOLY",
        specID = 65,
        name = "Holy Paladin",
        classToken = "PALADIN",
        spells = {
            { id = 156910,  name = "Beacon of Faith" },
            { id = 156322,  name = "Eternal Flame" },
            { id = 53563,   name = "Beacon of Light" },
            { id = 1244893, name = "Beacon of the Savior" },
            { id = 200025,  name = "Beacon of Virtue" },
            { id = 1022,    name = "Blessing of Protection", secret = true, sig = "1:1:1:1" },
            { id = 432502,  name = "Holy Armaments", secret = true, sig = "0:1:0:0" },
            { id = 6940,    name = "Blessing of Sacrifice", secret = true, sig = "1:1:1:0" },
            { id = 1044,    name = "Blessing of Freedom", secret = true, sig = "1:0:0:1" },
            { id = 431381,  name = "Dawnlight", secret = true, sig = "0:1:0:0" },
        },
    },
    {
        key = "EVOKER_PRESERVATION",
        specID = 1468,
        name = "Preservation Evoker",
        classToken = "EVOKER",
        spells = {
            { id = 364343, name = "Echo" },
            { id = 366155, name = "Reversion" },
            { id = 367364, name = "Echo Reversion" },
            { id = 355941, name = "Dream Breath" },
            { id = 376788, name = "Echo Dream Breath" },
            { id = 363502, name = "Dream Flight" },
            { id = 373267, name = "Lifebind" },
            { id = 357170, name = "Time Dilation", secret = true, sig = "1:1:1:0" },
            { id = 363534, name = "Rewind", secret = true, sig = "1:1:0:0" },
        },
    },
    {
        key = "EVOKER_AUGMENTATION",
        specID = 1473,
        name = "Augmentation Evoker",
        classToken = "EVOKER",
        spells = {
            { id = 410089, name = "Prescience" },
            { id = 413984, name = "Shifting Sands" },
            { id = 360827, name = "Blistering Scales" },
            { id = 410263, name = "Infernos Blessing" },
            { id = 410686, name = "Symbiotic Bloom" },
            { id = 395152, name = "Ebon Might" },
            { id = 369459, name = "Source of Magic" },
            { id = 361022, name = "Sense Power", secret = true, sig = "0:1:0:0" },
        },
    },
}

ns.BM_HEALER_SPECS = HEALER_SPECS

-- Spec lookup by key, and by spec ID (the locale-independent identifier).
local SPEC_BY_KEY = {}
local SPEC_BY_ID  = {}
for _, spec in ipairs(HEALER_SPECS) do
    SPEC_BY_KEY[spec.key] = spec
    if spec.specID then SPEC_BY_ID[spec.specID] = spec end
end

-- Non-healer specs that can still cast a tracked buff. They reuse another spec's
-- indicator placements (source) but only ever display the listed spells. Earth
-- Shield is castable by every Shaman spec, so Enhancement and Elemental borrow
-- Restoration's setup and show only Earth Shield -- exactly where the player
-- positioned Restoration's Earth Shield indicator. Blessing of Freedom works
-- the same way for Protection/Retribution Paladins (this also lets the
-- defensives display's externals fingerprint resolve Freedom on every Paladin
-- spec, since BM_IdentifySecretAura keys off the resolved spec). Keyed by spec
-- ID; spells is a set keyed by the primary spell ID indicators reference.
local BORROW_SPECS = {
    [262] = { source = "SHAMAN_RESTORATION", spells = { [974] = true } },  -- Elemental
    [263] = { source = "SHAMAN_RESTORATION", spells = { [974] = true } },  -- Enhancement
    -- sigs: fingerprints can differ from the source spec because the
    -- RAID_PLAYER_DISPELLABLE probe reflects the PLAYER's dispel capability.
    -- Freedom reads 1:0:0:1 on Holy (magic dispel) but 1:0:0:0 on Prot/Ret
    -- (no magic dispel), so the borrow entries register their own variant.
    [66]  = { source = "PALADIN_HOLY", spells = { [1044] = true },
              sigs = { ["1:0:0:0"] = 1044 } }, -- Protection
    [70]  = { source = "PALADIN_HOLY", spells = { [1044] = true },
              sigs = { ["1:0:0:0"] = 1044 } }, -- Retribution
}

-- Resolve the player's CURRENT spec to a BM spec key. This MUST be done by spec
-- ID, never by spec name: GetSpecializationInfo() returns the spec ID (a stable,
-- non-localized number) as its first value and the LOCALIZED display name as its
-- second. Earlier code matched the localized name against the English spec.name,
-- which never matched on non-English clients -- so no spec key resolved and every
-- HoT indicator (and the simple grid, and secret-aura tracking) silently failed.
-- Returns nil when the current spec is not a tracked healer/support spec.
local function CurrentSpecKey()
    local specIdx = GetSpecialization and GetSpecialization()
    if not specIdx then return nil end
    local specID = GetSpecializationInfo and GetSpecializationInfo(specIdx)
    if not specID then return nil end
    -- Borrow specs (Enh/Ele) resolve to the spec whose indicators they reuse, so
    -- the options page and lookup tables operate on that shared configuration.
    local borrow = BORROW_SPECS[specID]
    if borrow then return borrow.source end
    local spec = SPEC_BY_ID[specID]
    return spec and spec.key or nil
end
ns.BM_CurrentSpecKey = CurrentSpecKey

-- Curated display names by spell ID (from the spec lists above)
local STORED_NAME_BY_ID = {}
for _, spec in ipairs(HEALER_SPECS) do
    for _, spell in ipairs(spec.spells) do
        if not spell.hide then
            STORED_NAME_BY_ID[spell.id] = spell.name
        end
    end
end
-- Display-name lookup. Curated names win: they distinguish variants the
-- client API cannot (e.g. "Echo Reversion" vs plain "Reversion") and
-- localize through L(). The client-localized spell name is the fallback
-- for IDs outside the curated lists. No caching: L() must stay live so a
-- language switch is honoured.
local SPELL_NAME_BY_ID = setmetatable({}, {
    __index = function(_, id)
        local nm = STORED_NAME_BY_ID[id]
        if nm then return EllesmereUI.L(nm) end
        return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    end,
})

-- Spec dropdown values/order
local SPEC_DD_VALUES = {}
local SPEC_DD_ORDER = {}
for _, spec in ipairs(HEALER_SPECS) do
    SPEC_DD_VALUES[spec.key] = spec.name
    SPEC_DD_ORDER[#SPEC_DD_ORDER + 1] = spec.key
end

-- Forward declarations for tables used by fingerprinting and scanner
local spellToIndicators = {}   -- [spellID] = { ind1, ind2, ... }
local trackedSpellIDs   = {}   -- set of all tracked spell IDs (including secret)
local allActiveIndicators = {} -- flat list of all enabled indicators

-- Simple Setup mode: the active spec's FULL tracked whitelist (every non-hidden
-- spell), independent of which spells the user assigned to indicators. Kept in
-- its own set so the simple grid and the custom indicator system never share
-- tracking state and can't cross-contaminate.
local simpleTrackedSpellIDs = {}

-- Alternate aura spell IDs that resolve to a primary tracked ID. Some buffs
-- land under a different spell ID than the one indicators reference:
--   Earth Shield applies 383648 (talented / Midnight) but indicators use 974.
--   Ebon Might's caster self-buff is 395296 while the ally buff is 395152.
-- Resolved at scan time so existing saved indicators (which reference the
-- primary ID) match without a config migration.
local PRIMARY_BY_ALT = {
    [383648] = 974,     -- Earth Shield
    [395296] = 395152,  -- Ebon Might (caster self-buff)
}

-------------------------------------------------------------------------------
--  Secret aura fingerprinting (4-filter signature method)
--  For auras where spellId is secret, we run 4 filter checks and build a
--  "1:1:0:0" signature. If it matches a known secret spell, we identify it.
--
--  Attribution: the four-filter fingerprinting idea and the measured
--  per-spell signature values originate with Harrek (Harrek's Advanced Raid
--  Frames). Harrek granted EllesmereUI permission to use them. Many thanks to
--  him for sharing the research that makes secret-aura tracking possible.
-------------------------------------------------------------------------------
local C_UnitAuras_IsAuraFilteredOutByInstanceID = C_UnitAuras.IsAuraFilteredOutByInstanceID

local function AuraPassesFilter(unit, instanceID, filter)
    return not C_UnitAuras_IsAuraFilteredOutByInstanceID(unit, instanceID, filter)
end

local function MakeSignature(unit, instanceID)
    local r   = AuraPassesFilter(unit, instanceID, "PLAYER|HELPFUL|RAID")
    local ric = AuraPassesFilter(unit, instanceID, "PLAYER|HELPFUL|RAID_IN_COMBAT")
    -- Early out: if neither RAID nor RIC passes, not a tracked healer buff
    if not r and not ric then return nil end
    local ext  = AuraPassesFilter(unit, instanceID, "PLAYER|HELPFUL|EXTERNAL_DEFENSIVE")
    local disp = AuraPassesFilter(unit, instanceID, "PLAYER|HELPFUL|RAID_PLAYER_DISPELLABLE")
    return (r and "1" or "0") .. ":" .. (ric and "1" or "0") .. ":"
        .. (ext and "1" or "0") .. ":" .. (disp and "1" or "0")
end

-- Per-spec signature -> spellID lookup (built lazily)
local specSignatures = {}  -- [specKey] = { ["1:1:1:0"] = spellID }

-- Try to match a secret aura against the player's own spec signatures.
-- Only track indicators for the player's active spec. Checking all specs of the
-- same class causes cross-spec bleed (e.g. Disc seeing Holy indicators).
-- Also prevents cross-class signature collisions for secret aura fingerprinting.
-- Declared BEFORE GetSpecSignatures so its borrow-variant merge captures these
-- as upvalues (a later declaration would resolve to nil globals inside it).
local activeSpecKey_BM = nil
-- When the active spec borrows another's indicators (Enh/Ele -> Resto, Prot/Ret
-- -> Holy), this holds that borrow config so tracking can be restricted to the
-- borrowed spells and the borrow's signature variants can merge in.
local activeBorrow_BM = nil

local function GetSpecSignatures(specKey)
    if specSignatures[specKey] then return specSignatures[specKey] end
    local sigs = {}
    local spec = SPEC_BY_KEY[specKey]
    if spec then
        for _, spell in ipairs(spec.spells) do
            if spell.secret and spell.sig then
                -- Note: signature collisions within a spec are possible
                -- (e.g. Verdant Embrace and Lifebind share 0:1:0:0 in Preservation)
                -- First registered wins; disambiguation is a future enhancement
                if not sigs[spell.sig] then
                    sigs[spell.sig] = spell.id
                end
            end
        end
    end
    -- Borrow specs can fingerprint a spell differently than the source spec
    -- (the dispellable probe tracks the player's own dispel kit), so merge the
    -- active borrow entry's signature variants in. Safe with the lazy cache:
    -- specSignatures is wiped on every RebuildLookup (login + spec change),
    -- so the merged table always reflects the current spec context.
    if activeBorrow_BM and activeBorrow_BM.source == specKey and activeBorrow_BM.sigs then
        for sig, sid in pairs(activeBorrow_BM.sigs) do
            if not sigs[sig] then sigs[sig] = sid end
        end
    end
    specSignatures[specKey] = sigs
    return sigs
end

local function DetectActiveSpecKey()
    -- Locale-independent: resolve by spec ID. nil for any non-tracked spec, which
    -- clears tracking so nothing is shown for non-healer/support specs.
    activeSpecKey_BM = CurrentSpecKey()
    -- Resolve the borrow config (Enh/Ele Shaman) so RebuildLookup can limit the
    -- borrowed spec's indicators to the spells this spec can actually cast.
    activeBorrow_BM = nil
    local specIdx = GetSpecialization and GetSpecialization()
    local specID  = specIdx and GetSpecializationInfo and GetSpecializationInfo(specIdx)
    if specID then activeBorrow_BM = BORROW_SPECS[specID] end
end

DetectActiveSpecKey()

local function MatchSecretAura(unit, instanceID)
    if not activeSpecKey_BM then return nil end
    local sig = MakeSignature(unit, instanceID)
    if not sig then return nil end
    local sigs = GetSpecSignatures(activeSpecKey_BM)
    local sid = sigs[sig]
    if sid and trackedSpellIDs[sid] then
        -- Sense Power (361022) and the Evoker's own Ebon Might self-buff share
        -- the 0:1:0:0 fingerprint. Sense Power only lands on allies, never the
        -- caster, so never report it on the player's own frame.
        if sid == 361022 and UnitIsUnit(unit, "player") then return nil end
        return sid
    end
    return nil
end

-- Simple Setup variant: identical fingerprint match, but validated against the
-- full-whitelist set instead of the indicator-tracked set.
local function MatchSecretAuraSimple(unit, instanceID)
    if not activeSpecKey_BM then return nil end
    local sig = MakeSignature(unit, instanceID)
    if not sig then return nil end
    local sigs = GetSpecSignatures(activeSpecKey_BM)
    local sid = sigs[sig]
    if sid and simpleTrackedSpellIDs[sid] then
        if sid == 361022 and UnitIsUnit(unit, "player") then return nil end
        return sid
    end
    return nil
end

-- Raw spec-scoped identify: returns the matched secret spellID for the player's
-- active spec, WITHOUT the indicator-config gate that MatchSecretAura applies.
-- Lets other modules recognize a specific player-cast secret aura regardless of
-- Buff Manager setup (e.g. the defensives display treating the player's own
-- Blessing of Freedom as an external). Player-cast only and spec-scoped by
-- construction (the four-filter signature uses PLAYER filters and the lookup is
-- keyed to the active spec), so it never reports another player's aura and never
-- collides across classes.
function ns.BM_IdentifySecretAura(unit, instanceID)
    if not activeSpecKey_BM then return nil end
    local sig = MakeSignature(unit, instanceID)
    if not sig then return nil end
    return GetSpecSignatures(activeSpecKey_BM)[sig]
end

-- Fallback icon textures for secret auras (icon field is also secret)
local SECRET_SPELL_ICONS = {
    [102342] = 136097,   -- Ironbark
    [33206]  = 135936,   -- Pain Suppression
    [10060]  = 135939,   -- Power Infusion
    [47788]  = 237542,   -- Guardian Spirit
    [116849] = 636288,   -- Life Cocoon
    [443113] = 615340,   -- Strength of the Black Ox
    [1022]   = 135964,   -- Blessing of Protection
    [432502] = 5927636,  -- Holy Armaments (bulwark icon)
    [6940]   = 135966,   -- Blessing of Sacrifice
    [1044]   = 135968,   -- Blessing of Freedom
    [431381] = 5927633,  -- Dawnlight
    [357170] = 4630500,  -- Time Dilation
    [363534] = 4630498,  -- Rewind
    [361022] = 132160,   -- Sense Power

}

-------------------------------------------------------------------------------
--  Default indicator factory
-------------------------------------------------------------------------------
local nextIndicatorId = 0

local function NewIndicatorId()
    nextIndicatorId = nextIndicatorId + 1
    return nextIndicatorId
end

local function NewIndicator(indType, spells)
    local t = INDICATOR_TYPE_MAP[indType]
    local ind = {
        id        = NewIndicatorId(),
        enabled   = true,
        type      = indType,
        spells    = spells or {},
        position  = "TOPLEFT",
        size      = (indType == "bar") and 4 or 18,
        offsetX   = 0,
        offsetY   = 0,
    }
    if indType == "icon" then
        ind.size             = 18
        ind.ownOnly          = true
        ind.showStacks       = true
        ind.showDuration     = true
        ind.showDurationText = false
        ind.durationTextColor  = { r = 1, g = 1, b = 1 }
        ind.durationTextSize   = 8
        ind.durationTextOffsetX = 0
        ind.durationTextOffsetY = 0
        ind.stacksTextColor  = { r = 1, g = 1, b = 1 }
        ind.stacksTextSize   = 8
        ind.stacksOffsetX    = -1
        ind.stacksOffsetY    = 2
        ind.iconOpacity      = 100
        ind.indBorderSize    = 1
        ind.indBorderColor   = { r = 0, g = 0, b = 0 }
        ind.hideIcon         = false
        ind.frameLevel       = "medium"
        ind.growDirection    = "RIGHT"
        ind.spacing          = 0
    elseif indType == "square" then
        ind.ownOnly          = true
        ind.showDuration     = true
        ind.color = { r = 0x0C/255, g = 0xD2/255, b = 0x9D/255 }
        ind.indBorderSize    = 1
        ind.indBorderColor   = { r = 0, g = 0, b = 0 }
        ind.frameLevel    = "medium"
        ind.growDirection = "RIGHT"
        ind.spacing      = 0
    elseif indType == "bar" then
        ind.ownOnly          = true
        ind.color = { r = 0x0C/255, g = 0xD2/255, b = 0x9D/255 }
        ind.barColorOpacity = 100
        ind.frameLevel = "behindBorders"
        ind.barWidth  = 30
        ind.barHeight = 4
        ind.barFullWidth = false
        ind.barFullHeight = false
        ind.orientation = "HORIZONTAL"
        ind.reverseFill = false
        ind.barBgOpacity = 50
        ind.barBgColor = { r = 0, g = 0, b = 0 }
    elseif indType == "healthcolor" then
        ind.ownOnly          = true
        ind.color    = { r = 0, g = 1, b = 0 }
        ind.opacity  = 100
        ind.showWhen = "present"
    elseif indType == "border" then
        ind.ownOnly          = true
        local _ac = EllesmereUI and EllesmereUI.ACCENT_COLOR
        ind.color       = _ac and { r = _ac.r, g = _ac.g, b = _ac.b } or { r = 0.05, g = 0.82, b = 0.62 }
        ind.borderWidth = 2
        ind.borderOpacity = 100
        ind.showWhen    = "present"
    elseif indType == "framealpha" then
        ind.ownOnly          = true
        ind.alpha    = 0.4
        ind.showWhen = "present"
    end
    return ind
end

-- Spells that should NOT show a cooldown swipe in preview (no meaningful duration)
local PREVIEW_NO_DURATION = {
    [53563]  = true,   -- Beacon of Light
    [156910] = true,   -- Beacon of Faith
    [369459] = true,   -- Source of Magic
    [974]    = true,   -- Earth Shield
}
ns.BM_PREVIEW_NO_DURATION = PREVIEW_NO_DURATION

-- Stable random preview cooldown seeds (keyed by "frameIdx:spellID")
-- Values are fraction remaining (0.2 - 0.9), generated once and reused
local pvCDSeeds = {}
local function GetPvCDSeed(frameIdx, spellID)
    local key = frameIdx .. ":" .. spellID
    if not pvCDSeeds[key] then
        pvCDSeeds[key] = 0.2 + math.random() * 0.7
    end
    return pvCDSeeds[key]
end

-------------------------------------------------------------------------------
--  Default indicator presets (populated on first load per spec)
-------------------------------------------------------------------------------
local DEFAULT_INDICATORS = {
    DRUID_RESTORATION = {
        { pos = "TOPLEFT",  spells = { 33763 } },                              -- Lifebloom
        { pos = "TOPRIGHT", spells = { 8936, 774, 155777, 48438, 439530 } },   -- Regrowth, Rejuv, Germination, Wild Growth, Symbiotic Blooms
    },
    PRIEST_DISCIPLINE = {
        { pos = "TOPLEFT",  spells = { 194384, 10060 } },                      -- Atonement, Power Infusion
        { pos = "TOPRIGHT", spells = { 17, 1253593, 41635 } },                 -- PW:S, Void Shield, Prayer of Mending
    },
    PRIEST_HOLY = {
        { pos = "TOPLEFT",  spells = { 139, 10060 } },                         -- Renew, Power Infusion
        { pos = "TOPRIGHT", spells = { 77489, 41635 } },                       -- Echo of Light, Prayer of Mending
    },
    MONK_MISTWEAVER = {
        { pos = "TOPLEFT",  spells = { 119611, 124682 } },                     -- Renewing Mist, Enveloping Mist
        { pos = "TOPRIGHT", spells = { 115175, 443113 } },                     -- Soothing Mist, Strength of the Black Ox
    },
    SHAMAN_RESTORATION = {
        { pos = "TOPLEFT",  spells = { 974 } },                                -- Earth Shield
        { pos = "TOPRIGHT", spells = { 61295, 207400, 444490 } },              -- Riptide, Ancestral Vigor, Hydrobubble
    },
    PALADIN_HOLY = {
        { pos = "TOPLEFT",  spells = { 53563, 156910, 200025, 1244893 } },      -- Beacon of Light, Beacon of Faith, Beacon of Virtue, Beacon of the Savior
        { pos = "TOPRIGHT", spells = { 431381, 156322, 432502 } },             -- Dawnlight, Eternal Flame, Holy Armaments
    },
    EVOKER_PRESERVATION = {
        { pos = "TOPLEFT",  spells = { 364343, 373267 } },                     -- Echo, Lifebind
        { pos = "TOPRIGHT", spells = { 366155, 367364, 355941, 376788, 363502 } }, -- Reversion, Echo Reversion, Dream Breath, Echo Dream Breath, Dream Flight
    },
    EVOKER_AUGMENTATION = {
        { pos = "TOPLEFT",  spells = { 410089, 360827, 369459 } },             -- Prescience, Blistering Scales, Source of Magic
        { pos = "TOPRIGHT", spells = { 413984, 410263, 410686, 395152, 361022 } }, -- Shifting Sands, Infernos Blessing, Symbiotic Bloom, Ebon Might, Sense Power
    },
}

local function PopulateDefaults(list, specKey)
    local presets = DEFAULT_INDICATORS[specKey]
    if not presets then return end
    for _, preset in ipairs(presets) do
        local ind = NewIndicator("icon", preset.spells)
        ind.position = preset.pos
        if preset.pos == "TOPRIGHT" then
            ind.growDirection = "LEFT"
        end
        tinsert(list, ind)
    end
end

-------------------------------------------------------------------------------
--  Assignment helpers
-------------------------------------------------------------------------------
local function GetSpecIndicators(db, specKey)
    if not db or not db.profile then return {} end
    if not db.profile.bmIndicators then db.profile.bmIndicators = {} end
    if not db.profile.bmIndicators[specKey] then
        db.profile.bmIndicators[specKey] = {}
        PopulateDefaults(db.profile.bmIndicators[specKey], specKey)
    end
    return db.profile.bmIndicators[specKey]
end
-- 12.1 aura containers read the indicator config to build slots.
ns.BM_GetSpecIndicators = GetSpecIndicators
ns.BM_PrimaryByAlt = PRIMARY_BY_ALT

-- Borrow specs (Enh/Ele -> Resto, Prot/Ret -> Holy) only track the spells
-- they can cast; the container slots apply the same restriction.
function ns.BM_BorrowSpellFilter()
    if activeBorrow_BM then return activeBorrow_BM.spells end
    return nil
end

-- "Show Own on All Specs" (Simple Setup > Buff Display): lifts the
-- tracked-spec restriction for the SIMPLE grid only.
local function SimpleShowOwnAllSpecs()
    local p = ns.db and ns.db.profile
    local bs = p and p.bmSimple
    return (bs and bs.showOwnAllSpecs) == true
end

-- First tracked spec of the player's class, or nil for untracked classes.
-- The all-specs fallbacks (simple grid toggle, per-indicator flag) resolve
-- their configuration through this.
local function ClassFallbackSpecKey()
    local _, classToken = UnitClass("player")
    if classToken then
        for _, spec in ipairs(HEALER_SPECS) do
            if spec.classToken == classToken then return spec.key end
        end
    end
    return nil
end
ns.BM_ClassFallbackSpecKey = ClassFallbackSpecKey

-- The spec key the SIMPLE grid tracks. Normally the player's resolved spec;
-- with Show Own on All Specs enabled, untracked specs fall back to the
-- class's first tracked spec so the player still sees their own class buffs.
-- Secret-aura fingerprints stay gated on the REAL resolved spec
-- (activeSpecKey_BM), so on fallback specs only plain non-secret spells can
-- match -- deliberate scope limit, not a bug.
local function SimpleSpecKey()
    if activeSpecKey_BM then return activeSpecKey_BM end
    if not SimpleShowOwnAllSpecs() then return nil end
    return ClassFallbackSpecKey()
end
ns.BM_SimpleSpecKey = SimpleSpecKey

-- Simple Setup whitelist for the container grid (rebuilt by RebuildLookup;
-- read-only for consumers -- the engine copies candidate tables on set).
function ns.BM_SimpleTrackedSpellIDs()
    return simpleTrackedSpellIDs
end

local function CountSpecIndicators(db, specKey)
    local list = GetSpecIndicators(db, specKey)
    return #list
end

-------------------------------------------------------------------------------
--  Reverse lookup: spellID -> list of indicator configs
--  Rebuilt whenever indicators change. Used by the UNIT_AURA scanner.
-------------------------------------------------------------------------------
local function RebuildLookup(db)
    wipe(spellToIndicators)
    wipe(trackedSpellIDs)
    wipe(allActiveIndicators)
    if not db or not db.profile then return end

    -- Ensure defaults are populated for all specs (triggers on first load)
    for _, spec in ipairs(HEALER_SPECS) do
        GetSpecIndicators(db, spec.key)
    end

    -- Only load indicators for the player's active spec. With no resolved
    -- spec (untracked class spec), indicators flagged Show Own on All Specs
    -- still load from the class-fallback spec so the player's own casts keep
    -- their indicators (non-secret spells only there: MatchSecretAura stays
    -- gated on activeSpecKey_BM).
    DetectActiveSpecKey()
    local loadKey = activeSpecKey_BM
    local flaggedOnly = false
    if not loadKey then
        loadKey = ClassFallbackSpecKey()
        flaggedOnly = true
    end
    if loadKey then
        local specData = db.profile.bmIndicators[loadKey]
        if specData and type(specData) == "table" then
            for _, ind in ipairs(specData) do
                if ind.enabled and ind.spells
                   and (not flaggedOnly or ind.showOwnAllSpecs) then
                    allActiveIndicators[#allActiveIndicators + 1] = ind
                    for _, sid in ipairs(ind.spells) do
                        -- Borrow specs (Enh/Ele) only track the spells they can
                        -- cast; the borrowed spec's other indicators stay inert
                        -- (never match an aura) so nothing else shows. An
                        -- indicator flagged Show Own on All Specs opts out of
                        -- that restriction.
                        if (not activeBorrow_BM) or ind.showOwnAllSpecs
                           or activeBorrow_BM.spells[sid] then
                            trackedSpellIDs[sid] = true
                            if not spellToIndicators[sid] then
                                spellToIndicators[sid] = {}
                            end
                            tinsert(spellToIndicators[sid], ind)
                        end
                    end
                end
            end
        end
    end

    -- Track alternate aura IDs whose primary is tracked, so the incremental
    -- scanner's early-out sees them (they resolve to the primary in the scan).
    for alt, primary in pairs(PRIMARY_BY_ALT) do
        if trackedSpellIDs[primary] then
            trackedSpellIDs[alt] = true
        end
    end

    -- Simple Setup whitelist: every non-hidden spell of the active spec,
    -- regardless of indicators (hidden entries are alternate IDs resolved via
    -- PRIMARY_BY_ALT during the scan). Borrow specs show only the borrowed
    -- spells. Show Own on All Specs lifts both restrictions: borrow specs get
    -- the source spec's full list, untracked specs get the class fallback.
    wipe(simpleTrackedSpellIDs)
    if activeBorrow_BM and not SimpleShowOwnAllSpecs() then
        for sid in pairs(activeBorrow_BM.spells) do
            simpleTrackedSpellIDs[sid] = true
        end
    else
        local simpleKey = SimpleSpecKey()
        local spec = simpleKey and SPEC_BY_KEY[simpleKey]
        if spec then
            for _, spell in ipairs(spec.spells) do
                if not spell.hide then
                    simpleTrackedSpellIDs[spell.id] = true
                end
            end
        end
    end
    for alt, primary in pairs(PRIMARY_BY_ALT) do
        if simpleTrackedSpellIDs[primary] then
            simpleTrackedSpellIDs[alt] = true
        end
    end

    -- Sync nextIndicatorId to highest existing id
    for _, specData in pairs(db.profile.bmIndicators) do
        if type(specData) == "table" then
            for _, ind in ipairs(specData) do
                if ind.id and ind.id >= nextIndicatorId then
                    nextIndicatorId = ind.id + 1
                end
            end
        end
    end

    -- Pre-build signature table for the player's active spec only
    wipe(specSignatures)
    if activeSpecKey_BM then
        GetSpecSignatures(activeSpecKey_BM)
    end
end

ns.BM_RebuildLookup = RebuildLookup

-------------------------------------------------------------------------------
--  Indicator frame creation (called from StyleButton)
--  Creates a pool of reusable indicator sub-frames on each button.
--  Icons and squares are small frames on the health bar.
--  Bars are thin StatusBars. Frame effects modify existing elements.
-------------------------------------------------------------------------------
local ICON_POOL_SIZE = 8   -- max placed indicators visible per button
local DD_SPELL_ICON_SIZE = 17  -- icon size in ability/own-only dropdown menus
local BAR_POOL_SIZE  = 4
local BMSIMPLE_CAP   = 10  -- max buffs the Simple Setup grid can show per button

-- Hover tooltips for BuffManager aura icons/bars. Mirrors the Debuff Display
-- tooltip pattern (see EllesmereUIRaidFrames StyleButton): OnEnter renders the
-- aura by its instance ID, which is secret-safe -- it works for fingerprinted
-- secret auras too (Blizzard renders the real name we can't read). Mouse is
-- enabled only when the buff "Hide Tooltips" setting is off; motion and clicks
-- propagate to the parent button so click-casting keeps working underneath.
local function BM_TooltipOnEnter(self)
    local u, iid = self._tipUnit, self._tipIID
    if not u or not iid or issecretvalue(iid) then return end
    -- Honor the same "Show Raid Frames Tooltip" combat-visibility mode as the
    -- unit/debuff tooltips so one setting governs every raid-frame hover tip.
    if ns.RaidFrameTooltipAllowed and not ns.RaidFrameTooltipAllowed(self._ownerButton) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetUnitAuraByAuraInstanceID then
        GameTooltip:SetUnitAuraByAuraInstanceID(u, iid)
    elseif GameTooltip.SetUnitBuffByAuraInstanceID then
        GameTooltip:SetUnitBuffByAuraInstanceID(u, iid)
    end
    GameTooltip:Show()
end

local function BM_TooltipOnLeave()
    GameTooltip:Hide()
end

-- Wire a pooled aura frame for hover tooltips once, at creation. Mouse starts
-- disabled (transparent); BM_SetTipTarget toggles it live per the setting.
local function BM_WireTooltip(f, button)
    f._ownerButton = button
    f:EnableMouse(false)
    if f.SetPropagateMouseMotion then f:SetPropagateMouseMotion(true) end
    if f.SetPropagateMouseClicks then f:SetPropagateMouseClicks(true) end
    f:SetScript("OnEnter", BM_TooltipOnEnter)
    f:SetScript("OnLeave", BM_TooltipOnLeave)
end

-- Stash the hover target (unit + aura instance) as a frame is assigned an aura,
-- and toggle mouse interactivity to match the buff "Hide Tooltips" setting. Read
-- live so a combat-time toggle applies on the next aura event. Default (nil) =
-- tooltips shown. A missing/secret instance id disables the hover.
local function BM_SetTipTarget(f, unit, iid)
    f._tipUnit = unit
    f._tipIID  = iid
    -- db is a per-call parameter elsewhere in this file, not a file upvalue;
    -- read the profile off the addon namespace so this file-scope helper is safe.
    local prof = ns.db and ns.db.profile
    local wantMouse = (not prof or prof.buffHideTooltips ~= true)
        and iid ~= nil and not issecretvalue(iid)
    if f._tipMouse ~= wantMouse then
        f:EnableMouse(wantMouse)
        f._tipMouse = wantMouse
    end
end

function ns.BM_CreateIndicators(button, health, d, PP)
    if not health then return end

    -- Icon/square pool
    local iconPool = {}
    for i = 1, ICON_POOL_SIZE do
        local f = CreateFrame("Frame", nil, health)
        f:SetFrameLevel(button:GetFrameLevel() + ns.LVL_AURA)
        f:SetSize(12, 12)
        f:Hide()

        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f._tex = tex

        -- Cooldown swipe (for duration display)
        local cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        cooldown:SetAllPoints()
        cooldown:SetDrawEdge(false)
        cooldown:SetDrawSwipe(true)
        cooldown:SetSwipeColor(0, 0, 0, 0.6)
        cooldown:SetReverse(true)
        cooldown:SetHideCountdownNumbers(true)
        cooldown:Hide()
        f._cooldown = cooldown

        if PP then
            local bdr = CreateFrame("Frame", nil, f)
            bdr:SetAllPoints()
            bdr:SetFrameLevel(f:GetFrameLevel() + 1)
            PP.CreateBorder(bdr, 0, 0, 0, 1, 1)
            f._bdr = bdr
        end

        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"

        -- Carrier frame above cooldown swipe AND border for text elements
        local textCarrier = CreateFrame("Frame", nil, f)
        textCarrier:SetAllPoints()
        textCarrier:SetFrameLevel(f:GetFrameLevel() + 5)
        f._textCarrier = textCarrier

        local countFS = textCarrier:CreateFontString(nil, "OVERLAY")
        countFS:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
        EllesmereUI.ApplyIconTextFont(countFS, fontPath, 8, "raidFrames")
        countFS:SetTextColor(1, 1, 1)
        f._count = countFS

        local durFS = textCarrier:CreateFontString(nil, "OVERLAY")
        durFS:SetPoint("CENTER", f, "CENTER", 0, 0)
        EllesmereUI.ApplyIconTextFont(durFS, fontPath, 8, "raidFrames")
        durFS:SetTextColor(1, 1, 1)
        durFS:Hide()
        f._durText = durFS

        BM_WireTooltip(f, button)
        iconPool[i] = f
    end

    -- Bar pool
    local barPool = {}
    for i = 1, BAR_POOL_SIZE do
        local bar = CreateFrame("StatusBar", nil, health)
        bar:SetFrameLevel(button:GetFrameLevel() + ns.LVL_AURA)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:Hide()

        local barBg = bar:CreateTexture(nil, "BACKGROUND")
        barBg:SetAllPoints()
        barBg:SetColorTexture(0, 0, 0, 0.5)
        bar._bg = barBg

        BM_WireTooltip(bar, button)
        barPool[i] = bar
    end

    -- Frame effect overlay (healthcolor) -- anchored to the fill texture so it
    -- only covers the filled portion, not the empty/missing health area.
    -- ARTWORK sublevel 2: sits below the dispel overlay (sublevel 3).
    local hcOverlay = health:CreateTexture(nil, "ARTWORK", nil, 2)
    local fillTex = health:GetStatusBarTexture()
    if fillTex then
        hcOverlay:SetAllPoints(fillTex)
    else
        hcOverlay:SetAllPoints(health)
    end
    hcOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    hcOverlay:Hide()

    -- Frame effect border
    local effectBorder = CreateFrame("Frame", nil, button)
    effectBorder:SetAllPoints(button)
    effectBorder:SetFrameLevel(button:GetFrameLevel() + 11)
    effectBorder:Hide()
    if PP then PP.CreateBorder(effectBorder, 0, 1, 0, 1, 2) end

    d.bmIconPool     = iconPool
    d.bmBarPool      = barPool
    d.bmHCOverlay    = hcOverlay
    d.bmEffectBorder = effectBorder

    -- Simple Setup grid pool: a separate, isolated set of icons (never reused
    -- by the custom indicator system above). Mirrors the defensive icon
    -- sub-structure (texture + reverse cooldown swipe + PP border).
    local simplePool = {}
    local fontPathS = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    for i = 1, BMSIMPLE_CAP do
        local f = CreateFrame("Frame", nil, health)
        f:SetFrameLevel(button:GetFrameLevel() + ns.LVL_AURA)
        f:SetSize(22, 22)
        f:Hide()

        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f._tex = tex

        local cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        cooldown:SetAllPoints()
        cooldown:SetDrawEdge(false)
        cooldown:SetDrawSwipe(true)
        cooldown:SetSwipeColor(0, 0, 0, 0.6)
        cooldown:SetReverse(true)
        cooldown:SetHideCountdownNumbers(true)
        cooldown:Hide()
        f._cooldown = cooldown

        if PP then
            local bdr = CreateFrame("Frame", nil, f)
            bdr:SetAllPoints()
            bdr:SetFrameLevel(f:GetFrameLevel() + 1)
            PP.CreateBorder(bdr, 0, 0, 0, 1, 1)
            f._borderFrame = bdr
        end

        -- Carrier frame above the cooldown swipe/border for the stack count
        -- (mirrors the custom-indicator pool's _textCarrier/_count above).
        local textCarrier = CreateFrame("Frame", nil, f)
        textCarrier:SetAllPoints()
        textCarrier:SetFrameLevel(f:GetFrameLevel() + 5)
        f._textCarrier = textCarrier

        local countFS = textCarrier:CreateFontString(nil, "OVERLAY")
        countFS:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
        EllesmereUI.ApplyIconTextFont(countFS, fontPathS, 8, "raidFrames")
        countFS:SetTextColor(1, 1, 1)
        f._count = countFS

        BM_WireTooltip(f, button)
        simplePool[i] = f
    end
    d.bmSimpleIcons = simplePool
end

-------------------------------------------------------------------------------
--  Anchor helper (no-op for now, anchoring done in UpdateIndicators)
-------------------------------------------------------------------------------
function ns.BM_AnchorIndicators(d, health, s)
    -- Re-anchor health color overlay to the current fill texture (may change
    -- when user swaps health bar texture in settings). Always hugs the REAL
    -- bar: `health` may be the Uniform Icon Anchoring reference (a plain
    -- Frame with no fill texture), so resolve through its back-pointer.
    local hcBar = health and (health._euiHealth or health)
    if d.bmHCOverlay and hcBar then
        local ft = hcBar.GetStatusBarTexture and hcBar:GetStatusBarTexture()
        d.bmHCOverlay:ClearAllPoints()
        if ft then
            d.bmHCOverlay:SetAllPoints(ft)
        else
            d.bmHCOverlay:SetAllPoints(hcBar)
        end
    end

    -- Simple grid: re-size + re-anchor on layout / scale changes (mirrors the
    -- defensive icon rebuild). Only when simple mode is active.
    if d.bmSimpleIcons and health and ns.db and ns.db.profile and ns.db.profile.bmDisplayMode == "simple" then
        local bs = ns.db.profile.bmSimple
        if bs then
            local iscale = (d._isParty and ns._partyBmScale or (d._isExtra and ns._xfBmScale) or ns._bmScale) or 1
            local sz = (bs.size or 22) * iscale
            for _, f in ipairs(d.bmSimpleIcons) do f:SetSize(sz, sz) end
            ns.BM_AnchorSimpleGrid(d, health, bs, iscale, nil)
        end
    end
end


-------------------------------------------------------------------------------
--  Shared bar drain ticker
--  One hidden frame drives all active indicator bars. Bars register themselves
--  when shown with a duration, unregister when hidden. Zero cost when idle.
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--  Smooth bar drain via StatusBar:SetTimerDuration (GPU-side, zero Lua cost)
--  GPU-side smooth drain: C_DurationUtil duration object drives the
--  StatusBar natively. No OnUpdate, no ticker.
-------------------------------------------------------------------------------
local C_DurationUtil = C_DurationUtil

local C_UnitAuras_GetAuraDuration = C_UnitAuras.GetAuraDuration

-- Max Duration override (per-indicator): rescale the buff's swipe / bar fill to a
-- fixed baseline instead of its actual duration. Active only when the toggle is on
-- AND a positive number was entered (blank = off). Returns M (seconds) or nil.
local function BM_EffectiveMaxDur(ind)
    if not ind or not ind.maxDurationEnabled then return nil end
    local m = tonumber(ind.maxDuration)
    if not m or m <= 0 then return nil end
    return m
end
ns.BM_EffectiveMaxDur = BM_EffectiveMaxDur

-- Bar Max-Duration self-drain. Blizzard's GPU-smooth SetTimerDuration takes no
-- custom max, so an overridden bar is drained here instead: one shared OnUpdate
-- (hidden when idle) sets each registered bar's fill to clamp(remaining / M, 0, 1).
-- Only overridden bars register, so it costs nothing for everyone else.
local barMaxDurActive = setmetatable({}, { __mode = "k" })  -- [bar] = { exp, m }
local barMaxDurTicker = CreateFrame("Frame")
barMaxDurTicker:Hide()
barMaxDurTicker:SetScript("OnUpdate", function()
    local now = GetTime()
    local anyActive = false
    for bar, st in pairs(barMaxDurActive) do
        if not bar:IsShown() then
            barMaxDurActive[bar] = nil
        else
            anyActive = true
            local frac = (st.exp - now) / st.m
            if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
            bar:SetValue(frac)
        end
    end
    if not anyActive then barMaxDurTicker:Hide() end
end)
local function RegisterBarMaxDur(bar, exp, m)
    local st = barMaxDurActive[bar]
    if not st then st = {}; barMaxDurActive[bar] = st end
    st.exp, st.m = exp, m
    barMaxDurTicker:Show()
end
local function UnregisterBarMaxDur(bar)
    barMaxDurActive[bar] = nil
end

local function ApplyBarDrain(bar, unit, auraInstanceID, duration, expirationTime, maxDur)
    -- Max Duration override: scale the fill to the fixed baseline (still ends at
    -- the real expiration). Needs a clean expirationTime; self-drained via the
    -- ticker above. A buff applied at < M starts partly drained; one longer than
    -- M shows full until it drops below M (the clamp).
    if maxDur and expirationTime and not issecretvalue(expirationTime) and expirationTime > 0 then
        bar:SetMinMaxValues(0, 1)
        local frac = (expirationTime - GetTime()) / maxDur
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        bar:SetValue(frac)
        RegisterBarMaxDur(bar, expirationTime, maxDur)
        return
    end
    UnregisterBarMaxDur(bar)
    -- Preferred: native Duration object from C_UnitAuras (GPU-side smooth drain)
    if auraInstanceID and not issecretvalue(auraInstanceID) and C_UnitAuras_GetAuraDuration and bar.SetTimerDuration then
        local durObj = C_UnitAuras_GetAuraDuration(unit, auraInstanceID)
        if durObj and not issecretvalue(durObj) then
            bar:SetTimerDuration(durObj,
                Enum.StatusBarInterpolation.Immediate,
                Enum.StatusBarTimerDirection.RemainingTime)
            return
        end
    end
    -- Fallback: static value
    bar:SetMinMaxValues(0, 1)
    if duration and expirationTime and duration > 0 then
        local rem = math.max(0, expirationTime - GetTime())
        bar:SetValue(rem / duration)
    else
        bar:SetValue(1)
    end
end

local function ClearBarDrain(bar)
    bar:Hide()
end

-- Size + anchor a bar indicator relative to its unit's health bar. Shared by
-- the live and preview renders so they stay a 1:1 replica. When Full Width /
-- Full Height are off it uses the slider size at the indicator's anchor point.
-- When on, it edge-pins to the health bar so the bar matches it pixel-for-pixel
-- on that axis; the indicator's anchor still drives placement on the free axis.
local function BM_PlaceBar(bar, health, ind, iscale)
    local w = ind.barWidth or 30
    local h = ind.barHeight or 4
    local isVert = (ind.orientation or "HORIZONTAL") == "VERTICAL"
    bar:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
    bar:ClearAllPoints()
    -- Full Width/Height follow the fill axis like barWidth/barHeight: when the
    -- bar is vertical they swap which screen edge they span, so the toggle whose
    -- label reads "Full Width" always spans the on-screen horizontal axis.
    -- (Explicit if/else, not `a and b or c` -- the values are booleans.)
    local fullW, fullH
    if isVert then
        fullW, fullH = ind.barFullHeight, ind.barFullWidth
    else
        fullW, fullH = ind.barFullWidth, ind.barFullHeight
    end
    -- Full Width/Height pins span the health bar itself, so they keep the real
    -- bar even when Uniform Icon Anchoring passed the full-height reference in
    -- (the reference carries a back-pointer to the bar it was stamped on).
    local hugBar = health._euiHealth or health
    if fullW and fullH then
        -- Exact overlay of the health bar.
        bar:SetAllPoints(hugBar)
    elseif fullW then
        -- Span the health bar's full width; thickness from the cross-axis
        -- slider; vertical placement follows the indicator's vertical edge.
        local pos = ind.position or "TOPLEFT"
        local vEdge = (pos:find("BOTTOM", 1, true) and "BOTTOM")
            or (pos:find("TOP", 1, true) and "TOP") or ""
        local oy = (ind.offsetY or 0) * iscale
        bar:SetPoint(vEdge .. "LEFT", health, vEdge .. "LEFT", 0, oy)
        bar:SetPoint(vEdge .. "RIGHT", health, vEdge .. "RIGHT", 0, oy)
        bar:SetHeight(isVert and w or h)
    elseif fullH then
        -- Span the health bar's full height; thickness from the cross-axis
        -- slider; horizontal placement follows the indicator's horizontal edge.
        local pos = ind.position or "TOPLEFT"
        local hEdge = (pos:find("RIGHT", 1, true) and "RIGHT")
            or (pos:find("LEFT", 1, true) and "LEFT") or ""
        local ox = (ind.offsetX or 0) * iscale
        bar:SetPoint("TOP" .. hEdge, hugBar, "TOP" .. hEdge, ox, 0)
        bar:SetPoint("BOTTOM" .. hEdge, hugBar, "BOTTOM" .. hEdge, ox, 0)
        bar:SetWidth(isVert and h or w)
    else
        if isVert then bar:SetSize(h, w) else bar:SetSize(w, h) end
        bar:SetPoint(ind.position or "TOPLEFT", health, ind.position or "TOPLEFT",
                     (ind.offsetX or 0) * iscale, (ind.offsetY or 0) * iscale)
    end
end

-- Re-level a pooled icon/square frame for its indicator's Frame Level mode.
-- The indicator's own border sits at base + 1; its count/duration text carrier
-- stays pinned at +18 regardless of mode. baseLvl = the unit button's level.
-- Called on every assignment because pool frames are reused across indicators
-- that may each pick a different mode.
local function BM_ApplyIconLevel(fr, ind, baseLvl)
    local off = FRAMELVL_BASE[ind.frameLevel or "medium"] or FRAMELVL_BASE.medium
    fr:SetFrameLevel(baseLvl + off)
    -- Swipe + border ride one above the icon; text carrier stays pinned on top.
    -- Set each explicitly rather than relying on child-level propagation.
    if fr._cooldown then fr._cooldown:SetFrameLevel(baseLvl + off + 1) end
    if fr._bdr then fr._bdr:SetFrameLevel(baseLvl + off + 1) end
    if fr._textCarrier then fr._textCarrier:SetFrameLevel(baseLvl + FRAMELVL_TEXT) end
end

-- Bars have no border/text sub-frames, so only the base applies. Bars default
-- to "Behind Borders" (a bar with no saved mode adopts that default).
local function BM_ApplyBarLevel(bar, ind, baseLvl)
    bar:SetFrameLevel(baseLvl + (FRAMELVL_BASE[ind.frameLevel or "behindBorders"] or FRAMELVL_BASE.behindBorders))
end

-------------------------------------------------------------------------------
--  Threshold "expiring soon" recolor -- secret-value-safe via C_CurveUtil.
--  A Step color curve maps remaining-seconds -> { threshold color below the set
--  seconds, normal color at/above }. WoW evaluates it C-side against the aura's
--  opaque DurationObject and hands back a Color object whose channels may be
--  SECRET -- we never read them, only pass GetRGBA() straight into a secret-safe
--  setter. Works on fingerprinted private auras (the instance ID is readable;
--  only the spell ID is secret). A shared ~4 FPS ticker re-applies as time
--  crosses the threshold; zero cost when nothing is registered.
-------------------------------------------------------------------------------
local _thresholdCurves = {}  -- [configHash] = color curve (rebuilt only on config change)
local function GetThresholdColorCurve(thresholdSec, ncR, ncG, ncB, ncA, tcR, tcG, tcB, tcA)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType) then return nil end
    local hash = string.format("%d|%.3f,%.3f,%.3f,%.3f|%.3f,%.3f,%.3f,%.3f",
        thresholdSec, ncR, ncG, ncB, ncA, tcR, tcG, tcB, tcA)
    local curve = _thresholdCurves[hash]
    if curve then return curve end
    curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, CreateColor(tcR, tcG, tcB, tcA))            -- remaining < threshold
    curve:AddPoint(thresholdSec, CreateColor(ncR, ncG, ncB, ncA)) -- remaining >= threshold
    curve:AddPoint(600, CreateColor(ncR, ncG, ncB, ncA))          -- 10-min cap
    _thresholdCurves[hash] = curve
    return curve
end

-- Scalar step curve for the Icon Glow gate: 1 below the threshold, 0 at/above,
-- evaluated against the aura's DurationObject (seconds remaining). Cached per
-- threshold value. Secret-safe -- the result only ever flows into widget APIs.
local _thresholdAlphaCurves = {}
local function GetThresholdAlphaCurve(thresholdSec)
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType) then return nil end
    local curve = _thresholdAlphaCurves[thresholdSec]
    if curve then return curve end
    curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, 1)              -- remaining below threshold -> glow on
    curve:AddPoint(thresholdSec, 0)   -- remaining at/above threshold -> glow off
    _thresholdAlphaCurves[thresholdSec] = curve
    return curve
end

-- Threshold sound cue -- rides the same ticker as the recolor, but unlike the
-- visual path it needs a plain Lua comparison, so it reads the aura timing
-- directly and skips silently whenever that timing is secret (private auras).
-- The cue therefore only fires for auras with readable timing. 12.0 only for
-- now; the 12.1 threshold section is inert pending engine bindings.
local THRESHOLD_SOUND_DIR = "Interface\\AddOns\\EllesmereUI\\media\\sounds\\"
local _thresholdSoundPaths, _thresholdSoundNames, _thresholdSoundOrder
-- Built lazily so SharedMedia sounds registered by other addons at login are
-- included; shared by the ticker (playback) and the options page (dropdown).
local function GetThresholdSoundTables()
    if _thresholdSoundPaths then
        return _thresholdSoundPaths, _thresholdSoundNames, _thresholdSoundOrder
    end
    _thresholdSoundPaths = {
        ["airhorn"]   = THRESHOLD_SOUND_DIR .. "AirHorn.ogg",
        ["banana"]    = THRESHOLD_SOUND_DIR .. "BananaPeelSlip.ogg",
        ["bikehorn"]  = THRESHOLD_SOUND_DIR .. "BikeHorn.ogg",
        ["bite"]      = THRESHOLD_SOUND_DIR .. "Bite.ogg",
        ["boxing"]    = THRESHOLD_SOUND_DIR .. "BoxingArenaSound.ogg",
        ["catmeow"]   = THRESHOLD_SOUND_DIR .. "CatMeow.ogg",
        ["catmeow2"]  = THRESHOLD_SOUND_DIR .. "CatMeow2.ogg",
        ["gunshot"]   = THRESHOLD_SOUND_DIR .. "FrontalsGunshot.wav",
        ["glass"]     = THRESHOLD_SOUND_DIR .. "Glass.mp3",
        ["kaching"]   = THRESHOLD_SOUND_DIR .. "Kaching.ogg",
        ["phone"]     = THRESHOLD_SOUND_DIR .. "Phone.ogg",
        ["robotblip"] = THRESHOLD_SOUND_DIR .. "RobotBlip.ogg",
        ["sonar"]     = THRESHOLD_SOUND_DIR .. "Sonar.ogg",
        ["siren"]     = THRESHOLD_SOUND_DIR .. "WarningSiren.ogg",
        ["water"]     = THRESHOLD_SOUND_DIR .. "WaterDrop.ogg",
        ["wilhelm"]   = THRESHOLD_SOUND_DIR .. "Wilhelm.ogg",
    }
    _thresholdSoundNames = {
        ["none"]      = "None",
        ["airhorn"]   = "Air Horn",
        ["banana"]    = "Banana Peel Slip",
        ["bikehorn"]  = "Bike Horn",
        ["bite"]      = "Bite",
        ["boxing"]    = "Boxing Arena",
        ["catmeow"]   = "Cat Meow",
        ["catmeow2"]  = "Cat Meow 2",
        ["gunshot"]   = "Frontals Gunshot",
        ["glass"]     = "Glass",
        ["kaching"]   = "Kaching",
        ["phone"]     = "Phone",
        ["robotblip"] = "Robot Blip",
        ["sonar"]     = "Sonar",
        ["siren"]     = "Warning Siren",
        ["water"]     = "Water Drop",
        ["wilhelm"]   = "Wilhelm",
    }
    _thresholdSoundOrder = {
        "none", "airhorn", "banana", "bikehorn", "bite", "boxing", "catmeow",
        "catmeow2", "gunshot", "glass", "kaching", "phone", "robotblip", "sonar",
        "siren", "water", "wilhelm",
    }
    if EllesmereUI.AppendSharedMediaSounds then
        EllesmereUI.AppendSharedMediaSounds(
            _thresholdSoundPaths, _thresholdSoundNames, _thresholdSoundOrder)
    end
    return _thresholdSoundPaths, _thresholdSoundNames, _thresholdSoundOrder
end

-- One shared throttle so a raid-wide expiry wave plays a single cue, not one
-- sound per frame that crossed the threshold in the same wave.
local _thresholdSoundLast = 0
local function PlayThresholdSound(key)
    local now = GetTime()
    if (now - _thresholdSoundLast) < 2 then return end
    local paths = GetThresholdSoundTables()
    local path = paths[key]
    if path then
        _thresholdSoundLast = now
        PlaySoundFile(path, "Master")
    end
end

-- [element] = { unit, iid, curve, apply, ind }; apply(element, colorResult)
local thresholdRegistry = {}
local thresholdTicker = CreateFrame("Frame")
thresholdTicker:Hide()
local thresholdElapsed = 0
local function EvalThreshold(element, e)
    -- Visual recolor: skipped for sound-only registrations (no curve/apply).
    if C_UnitAuras_GetAuraDuration and e.curve and e.apply then
        local durObj = C_UnitAuras_GetAuraDuration(e.unit, e.iid)
        if durObj and durObj.EvaluateRemainingDuration then
            -- pcall: the API can throw on a stale/invalid duration object mid-recycle.
            local ok, result = pcall(durObj.EvaluateRemainingDuration, durObj, e.curve)
            if ok and result and result.GetRGBA then
                e.apply(element, result)   -- result channels may be secret; never read here
            end
        end
    end
    -- Sound cue: plain-Lua edge detect, guarded so a secret value never enters
    -- a comparison -- if the timing is secret this whole block is a silent skip
    -- (visuals above keep working; they never needed the value). Rising-edge
    -- flag per element so each crossing fires once; refresh above the threshold
    -- re-arms it.
    local ind = e.ind
    local sKey = ind and ind.thresholdSound
    if sKey and sKey ~= "none" and not EllesmereUI.IS_121 then
        local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(e.unit, e.iid)
        local exp = aura and aura.expirationTime
        if exp and not issecretvalue(exp) then
            if (exp - GetTime()) <= (ind.threshold or 3) then
                if not e.soundFired then
                    e.soundFired = true
                    PlayThresholdSound(sKey)
                end
            else
                e.soundFired = nil
            end
        end
    end
end
thresholdTicker:SetScript("OnUpdate", function(_, dt)
    thresholdElapsed = thresholdElapsed + dt
    if thresholdElapsed < 0.25 then return end
    thresholdElapsed = 0
    local any = false
    for element, e in pairs(thresholdRegistry) do
        if element.IsShown and not element:IsShown() then
            thresholdRegistry[element] = nil   -- self-prune hidden / recycled pool frames
        else
            any = true
            EvalThreshold(element, e)
        end
    end
    if not any then thresholdTicker:Hide() end
end)

local function RegisterThreshold(element, unit, iid, curve, apply, ind)
    local e = thresholdRegistry[element]
    if not e then e = {}; thresholdRegistry[element] = e end
    -- New aura instance -> re-arm the sound edge flag (a reapplied buff is a
    -- fresh crossing); same instance keeps it so re-registers never double-fire.
    if e.iid ~= iid then e.soundFired = nil end
    e.unit, e.iid, e.curve, e.apply, e.ind = unit, iid, curve, apply, ind
    thresholdTicker:Show()
    EvalThreshold(element, e)   -- immediate, so we never flash the normal color for a tick
end

local function UnregisterThreshold(element)
    thresholdRegistry[element] = nil
end

-- Temporary diagnostic for the threshold sound: /rfthsdbg snapshots every
-- registered threshold element's sound-decision inputs as of right now.
SLASH_RFTHSDBG1 = "/rfthsdbg"
SlashCmdList.RFTHSDBG = function()
    local now = GetTime()
    local n = 0
    for element, e in pairs(thresholdRegistry) do
        n = n + 1
        local ind = e.ind
        local sKey = (ind and (ind.thresholdSound or "unset")) or "NIL-IND"
        local expInfo, remInfo = "no-aura", "?"
        local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(e.unit, e.iid)
        if aura then
            local exp = aura.expirationTime
            if exp == nil then expInfo = "nil-exp"
            elseif issecretvalue(exp) then expInfo = "SECRET"
            else
                expInfo = "ok"
                remInfo = string.format("%.1f", exp - now)
            end
        end
        print(("|cff0cd29f[THSND]|r unit=%s iid=%s key=%s exp=%s rem=%s thr=%s fired=%s shown=%s"):format(
            tostring(e.unit), tostring(e.iid), tostring(sKey), expInfo, remInfo,
            tostring(ind and (ind.threshold or 3) or "?"), tostring(e.soundFired or false),
            tostring(element.IsShown and element:IsShown() or false)))
    end
    print(("|cff0cd29f[THSND]|r entries=%d IS_121=%s tickerShown=%s throttleAgo=%.1f"):format(
        n, tostring(EllesmereUI.IS_121 or false), tostring(thresholdTicker:IsShown()),
        now - _thresholdSoundLast))
end

-- Per-type apply helpers. All push the (possibly secret) curve color straight
-- into a secret-safe setter via GetRGBA() -- the channels are never read.
local function ApplyBarThresholdColor(bar, colorResult)
    bar:SetStatusBarColor(colorResult:GetRGBA())
end
-- Icon/Square: the pool frame is the element; its texture carries the color.
local function ApplyTexThresholdColor(f, colorResult)
    if f._tex then f._tex:SetVertexColor(colorResult:GetRGBA()) end
end
-- Duration text: recolor the cooldown's countdown font string. Used when an
-- icon indicator has "Hide Icons" on, so the expiring color lands on the
-- visible duration text instead of the hidden icon texture.
local function ApplyDurTextThresholdColor(f, colorResult)
    local cd = f._cooldown
    local cdText = cd and cd.GetCountdownFontString and cd:GetCountdownFontString()
    if cdText then cdText:SetTextColor(colorResult:GetRGBA()) end
end
-- Health-color overlay: the overlay texture itself is the element.
local function ApplyOverlayThresholdColor(overlay, colorResult)
    overlay:SetVertexColor(colorResult:GetRGBA())
end
-- Frame-border effect: PP.SetBorderColor only forwards to SetVertexColor on the
-- border textures (no arithmetic), so a secret color is safe.
local function ApplyBorderThresholdColor(borderFrame, colorResult)
    local PP2 = EllesmereUI.PanelPP or EllesmereUI.PP
    if PP2 and PP2.SetBorderColor then PP2.SetBorderColor(borderFrame, colorResult:GetRGBA()) end
end

-------------------------------------------------------------------------------
--  Icon Glow -- threshold-gated glow for icon indicators. The shared glow
--  engine runs continuously while the buff is active; its overlay ALPHA is
--  driven by the DurationObject so the glow only shows once remaining drops
--  below the threshold. Fully secret-safe: the (possibly secret) curve value
--  and IsZero boolean flow straight into Blizzard widget APIs
--  (EvaluateColorValueFromBoolean, SetAlpha) and are never compared in Lua.
--  Mirrors the recolor ticker above; the ticker also stops the animation on
--  recycled/hidden pool frames so an inactive icon never leaks a running glow.
-------------------------------------------------------------------------------
local glowRegistry = {}  -- [overlay] = { unit, iid, curve }
local glowTicker = CreateFrame("Frame")
glowTicker:Hide()
local glowElapsed = 0
local function EvalGlow(overlay, e)
    if not (C_UnitAuras_GetAuraDuration and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean) then return end
    local durObj = C_UnitAuras_GetAuraDuration(e.unit, e.iid)
    if not (durObj and durObj.EvaluateRemainingDuration and durObj.IsZero) then return end
    -- pcall (method form, no closure): a recycled duration object can throw.
    local ok, val = pcall(durObj.EvaluateRemainingDuration, durObj, e.curve, 0)
    if not ok then return end
    local okz, isZero = pcall(durObj.IsZero, durObj)
    if not okz then return end
    -- val + isZero may be secret; they only ever flow into Blizzard widget APIs.
    overlay:SetAlpha(C_CurveUtil.EvaluateColorValueFromBoolean(isZero, 0, val))
end
glowTicker:SetScript("OnUpdate", function(_, dt)
    glowElapsed = glowElapsed + dt
    if glowElapsed < 0.2 then return end
    glowElapsed = 0
    local any = false
    for overlay, e in pairs(glowRegistry) do
        if overlay.IsShown and not overlay:IsShown() then
            glowRegistry[overlay] = nil
            if overlay._euiGlowActive and EllesmereUI.Glows and EllesmereUI.Glows.StopGlow then
                EllesmereUI.Glows.StopGlow(overlay)
            end
        else
            any = true
            EvalGlow(overlay, e)
        end
    end
    if not any then glowTicker:Hide() end
end)
local function RegisterGlow(overlay, unit, iid, curve)
    local e = glowRegistry[overlay]
    if not e then e = {}; glowRegistry[overlay] = e end
    e.unit, e.iid, e.curve = unit, iid, curve
    glowTicker:Show()
    EvalGlow(overlay, e)   -- immediate, so the gate is correct on the first frame
end
local function UnregisterGlow(overlay)
    glowRegistry[overlay] = nil
end

-------------------------------------------------------------------------------
--  Shared duration text ticker
--  One hidden frame drives all active duration text FontStrings. Pool frames
--  register their _durText + expiration time; the ticker updates the text
--  every 0.5s. Zero cost when no duration texts are active.
-------------------------------------------------------------------------------
local durTextActive = {}  -- [durFS] = expirationTime
local durTextTicker = CreateFrame("Frame")
durTextTicker:Hide()
local durTextElapsed = 0
durTextTicker:SetScript("OnUpdate", function(_, dt)
    durTextElapsed = durTextElapsed + dt
    if durTextElapsed < 0.5 then return end
    durTextElapsed = 0
    local now = GetTime()
    local anyActive = false
    for fs, exp in pairs(durTextActive) do
        local rem = max(0, exp - now)
        if rem <= 0 then
            fs:Hide()
            durTextActive[fs] = nil
        else
            anyActive = true
            if rem >= 60 then
                fs:SetFormattedText("%dm", floor(rem / 60))
            else
                fs:SetFormattedText("%d", floor(rem + 0.5))
            end
        end
    end
    if not anyActive then durTextTicker:Hide() end
end)

local function RegisterDurText(fs, expirationTime)
    durTextActive[fs] = expirationTime
    durTextTicker:Show()
end

local function UnregisterDurText(fs)
    durTextActive[fs] = nil
end
ns.RegisterDurText = RegisterDurText
ns.UnregisterDurText = UnregisterDurText

-------------------------------------------------------------------------------
--  Update all buff indicators for a single button (called on UNIT_AURA)
-------------------------------------------------------------------------------
-- Reusable tables (allocate once, wipe per call -- zero-alloc pattern)
local activeSpells = {}       -- [spellID] = auraData (any source)
local activePlayerSpells = {} -- [spellID] = auraData (player-cast only)
local placedQueue  = {}       -- sorted list of {ind, auraData} for placed types
local iconPoolIdx, barPoolIdx -- counters reset per call

-- Clear all BM visuals for a button (ghost aura safety, unit gone, etc.)
function ns.BM_ClearIndicators(button)
    local GetFFD = ns.GetFFD
    if not GetFFD then return end
    local d = GetFFD(button)
    if not d.bmIconPool then return end
    for _, f in ipairs(d.bmIconPool) do
        f:Hide()
    end
    for _, b in ipairs(d.bmBarPool) do ClearBarDrain(b); b:Hide() end
    if d.bmHCOverlay then d.bmHCOverlay:Hide() end
    if d.bmEffectBorder then d.bmEffectBorder:Hide() end
    if d.bmSimpleIcons then
        for _, f in ipairs(d.bmSimpleIcons) do
            if f._cooldown then f._cooldown:Hide() end
            f:Hide()
        end
        d.bmSimpleActiveIDs = nil
    end
    d.bmActiveInstanceIDs = nil
    button._bmSavedAlpha = nil
    -- Restore to range-only alpha. If rangeAlpha is nil the range ticker
    -- already set the correct secret-safe alpha via SetAlphaFromBoolean.
    if d.rangeAlpha then
        button:SetAlpha(d.rangeAlpha)
    end
end

-------------------------------------------------------------------------------
--  SIMPLE SETUP MODE: isolated buff grid
--  Shows ALL of the active spec's tracked buffs (the full whitelist) in a grid
--  laid out by position + growth direction + icons-per-row. Completely separate
--  from the custom indicator system: its own pool (d.bmSimpleIcons), its own
--  whitelist (simpleTrackedSpellIDs), and its own update path. The two never
--  run together -- BM_UpdateIndicators gates on db.profile.bmDisplayMode.
-------------------------------------------------------------------------------

-- Grid anchor. Every icon is positioned by an absolute offset from the anchor
-- corner (not chained) so multi-row layout is unambiguous. The row axis is
-- perpendicular to the icon-growth axis and stacks away from the anchored edge.
local function AnchorSimpleGrid(d, health, bs, iscale, visibleCount)
    if not d.bmSimpleIcons or not health then return end
    local pos    = bs.position or "topright"
    local grow   = bs.growDirection or "LEFT"
    local sz     = (bs.size or 22) * iscale
    local spc    = (ns.PixelSnap or function(v) return v end)((bs.spacing or 1) * iscale)
    local perRow = bs.iconsPerRow or 4
    if perRow < 1 then perRow = 1 end
    local ox     = (bs.offsetX or 0) * iscale
    local oy     = (bs.offsetY or 0) * iscale
    local step   = sz + spc

    -- Icon corner anchored to the same corner of the health bar.
    local corner = "TOPRIGHT"
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

    -- Row-stack vector (perpendicular), pointing away from the anchored edge.
    local svx, svy = 0, 0
    if horizontal then
        if pos == "bottomleft" or pos == "bottom" or pos == "bottomright" then svy = 1 else svy = -1 end
    else
        if pos == "topright" or pos == "right" or pos == "bottomright" then svx = -1 else svx = 1 end
    end

    local total = visibleCount or #d.bmSimpleIcons
    for i, icon in ipairs(d.bmSimpleIcons) do
        icon:ClearAllPoints()
        local idx0 = i - 1
        -- perRow == 1 is a single line ALONG the growth direction (no wrapping),
        -- so the Growth Direction control stays meaningful; otherwise wrap into rows.
        local row, col
        if perRow <= 1 then
            row, col = 0, idx0
        else
            row = floor(idx0 / perRow)
            col = idx0 % perRow
        end
        local centerOff = 0
        if grow == "CENTER" then
            local rowCount = (perRow <= 1) and total or min(perRow, max(0, total - row * perRow))
            if rowCount > 0 then centerOff = -((rowCount - 1) * step) / 2 end
        end
        local along  = col * step
        local across = row * step
        local fx = ox + gvx * along + svx * across + centerOff
        local fy = oy + gvy * along + svy * across
        icon:SetPoint(corner, health, corner, fx, fy)
    end
end
ns.BM_AnchorSimpleGrid = AnchorSimpleGrid

-- Scan HELPFUL auras, match against the active spec's full whitelist (secret
-- auras via fingerprint), and render the matches in the grid. Secret-safe:
-- icon via SetTexture, duration via DurationObject, never reads raw numbers.
function ns.BM_UpdateSimpleGrid(button, unit, db, updateInfo)
    local GetFFD = ns.GetFFD
    if not GetFFD then return end
    local d = GetFFD(button)
    if not d.bmSimpleIcons then return end
    local health = ns.RF_AnchorHostFor and ns.RF_AnchorHostFor(d) or d.health
    if not health then return end

    local bs = db and db.profile and db.profile.bmSimple

    local function HideAll()
        for _, f in ipairs(d.bmSimpleIcons) do
            if f._cooldown then f._cooldown:Hide() end
            f:Hide()
        end
        d.bmSimpleActiveIDs = nil
    end

    if not bs or not bs.showBuffs or not UnitExists(unit) then
        HideAll()
        return
    end

    -- Incremental quick-skip: only rescan when a tracked buff actually changed.
    if updateInfo and not updateInfo.isFullUpdate and d.bmSimpleActiveIDs then
        local needScan = false
        if updateInfo.addedAuras then
            for _, ad in ipairs(updateInfo.addedAuras) do
                local sid = ad.spellId
                if sid and not issecretvalue(sid) then
                    if simpleTrackedSpellIDs[PRIMARY_BY_ALT[sid] or sid] then needScan = true; break end
                elseif sid then
                    needScan = true; break
                end
            end
        end
        if not needScan and updateInfo.removedAuraInstanceIDs then
            for _, iid in ipairs(updateInfo.removedAuraInstanceIDs) do
                if d.bmSimpleActiveIDs[iid] then needScan = true; break end
            end
        end
        if not needScan and updateInfo.updatedAuraInstanceIDs then
            for _, iid in ipairs(updateInfo.updatedAuraInstanceIDs) do
                if d.bmSimpleActiveIDs[iid] then needScan = true; break end
            end
        end
        if not needScan then return end
    end

    local iscale = (d._isParty and ns._partyBmScale or (d._isExtra and ns._xfBmScale) or ns._bmScale) or 1
    local PP = EllesmereUI.PanelPP or EllesmereUI.PP
    local sz = (bs.size or 22) * iscale
    local bdrSz = bs.borderSize or 1
    local bdrC = bs.borderColor or { r = 0, g = 0, b = 0 }
    local wantSwipe = bs.showSwipe ~= false
    local wantDurText = bs.showDurText
    local cap = #d.bmSimpleIcons
    local maxBuffs = bs.maxBuffs or 10
    if maxBuffs > cap then maxBuffs = cap end
    local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"

    if not d.bmSimpleActiveIDs then d.bmSimpleActiveIDs = {} else wipe(d.bmSimpleActiveIDs) end
    local seen = d._bmSimpleSeen
    if not seen then seen = {}; d._bmSimpleSeen = seen else wipe(seen) end

    local ownOnly = bs.ownOnly ~= false

    local shown = 0
    local idx = 1
    while true do
        if shown >= maxBuffs then break end
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, idx, "HELPFUL")
        if not auraData then break end
        idx = idx + 1

        local sid = auraData.spellId
        local iid = auraData.auraInstanceID
        local tex = auraData.icon
        local matched = false
        if sid and iid then
            if not issecretvalue(sid) then
                local psid = PRIMARY_BY_ALT[sid] or sid
                if simpleTrackedSpellIDs[psid] and not seen[psid] then
                    -- Own Only: same PLAYER filter the custom path uses; secret
                    -- auras below are always player-cast so they skip this check.
                    local pass = true
                    if ownOnly and C_UnitAuras_IsAuraFilteredOutByInstanceID then
                        pass = not C_UnitAuras_IsAuraFilteredOutByInstanceID(unit, iid, "PLAYER|HELPFUL")
                    end
                    if pass then
                        matched = true
                        seen[psid] = true
                    end
                end
            else
                local matchedSid = MatchSecretAuraSimple(unit, iid)
                if matchedSid and not seen[matchedSid] then
                    matched = true
                    seen[matchedSid] = true
                    if not tex then tex = SECRET_SPELL_ICONS[matchedSid] or 136243 end
                end
            end
        end

        if matched then
            shown = shown + 1
            d.bmSimpleActiveIDs[iid] = true
            local icon = d.bmSimpleIcons[shown]
            BM_SetTipTarget(icon, unit, iid)
            icon:SetSize(sz, sz)
            icon._tex:SetTexture(tex or 136243)
            local _z = bs.iconZoom or 0.08
            icon._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)

            local cd = icon._cooldown
            if cd then
                if wantSwipe or wantDurText then
                    -- Permanent auras return a degenerate 0,0 duration object
                    -- whose armed cooldown strobes via an internal client
                    -- show/self-hide cycle; mask with alpha via durObj:IsZero()
                    -- (secret-safe, see custom-indicator path).
                    local applied = false
                    if C_UnitAuras.GetAuraDuration and cd.SetCooldownFromDurationObject then
                        local durObj = C_UnitAuras.GetAuraDuration(unit, iid)
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
                    if applied and wantDurText then
                        local cdText = cd.GetCountdownFontString and cd:GetCountdownFontString()
                        if cdText then
                            local dtc = bs.durTextColor or { r = 1, g = 1, b = 1 }
                            EllesmereUI.ApplyIconTextFont(cdText, fp, bs.durTextSize or 8, "raidFrames")
                            cdText:SetTextColor(dtc.r, dtc.g, dtc.b)
                            cdText:ClearAllPoints()
                            cdText:SetPoint("CENTER", icon, "CENTER", bs.durTextOffsetX or 0, bs.durTextOffsetY or 0)
                        end
                    end
                else
                    cd:Hide()
                end
            end

            if icon._borderFrame and PP then
                if bdrSz > 0 then
                    PP.UpdateBorder(icon._borderFrame, bdrSz, bdrC.r, bdrC.g, bdrC.b, 1)
                    icon._borderFrame:Show()
                else
                    icon._borderFrame:Hide()
                end
            end

            -- Stack count (secret-safe via Blizzard API; mirrors the custom-
            -- indicator system's stack text).
            if icon._count then
                if bs.showStacks and C_UnitAuras.GetAuraApplicationDisplayCount and iid then
                    local stackText = C_UnitAuras.GetAuraApplicationDisplayCount(unit, iid, 2, 99)
                    if stackText then
                        local sc = bs.stacksTextColor or { r = 1, g = 1, b = 1 }
                        EllesmereUI.ApplyIconTextFont(icon._count, fp, bs.stacksTextSize or 8, "raidFrames")
                        icon._count:SetTextColor(sc.r, sc.g, sc.b)
                        icon._count:ClearAllPoints()
                        icon._count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT",
                            bs.stacksOffsetX or -1, bs.stacksOffsetY or 2)
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
    end

    for j = shown + 1, cap do
        local icon = d.bmSimpleIcons[j]
        if icon._cooldown then icon._cooldown:Hide() end
        icon:Hide()
    end

    AnchorSimpleGrid(d, health, bs, iscale, shown)
end

function ns.BM_UpdateIndicators(button, unit, db, updateInfo)
    -- 12.1 migration scaffolding: skip silently while auras are secret so the
    -- restriction error cannot abort shared handler chains. Removed when the
    -- BuffManager migrates to container slots.
    if ns.RFC_LegacyAuraGuard and ns.RFC_LegacyAuraGuard() then return end
    local GetFFD = ns.GetFFD
    if not GetFFD then return end
    local d = GetFFD(button)
    if not d.bmIconPool then return end

    -- 12.1: BOTH display modes render via aura containers now (custom mode
    -- as slots/chains, Simple Setup as a grid group). Hide any lingering
    -- legacy visuals from either mode and hand off entirely.
    if ns.RFC_OwnsBM then
        for _, f in ipairs(d.bmIconPool) do f:Hide() end
        if d.bmBarPool then for _, b in ipairs(d.bmBarPool) do ClearBarDrain(b); b:Hide() end end
        if d.bmHCOverlay then d.bmHCOverlay:Hide() end
        if d.bmEffectBorder then d.bmEffectBorder:Hide() end
        d.bmActiveInstanceIDs = nil
        button._bmSavedAlpha = nil
        if d.rangeAlpha then button:SetAlpha(d.rangeAlpha) end
        if d.bmSimpleIcons and d.bmSimpleActiveIDs then
            for _, f in ipairs(d.bmSimpleIcons) do
                if f._cooldown then f._cooldown:Hide() end
                f:Hide()
            end
            d.bmSimpleActiveIDs = nil
        end
        return
    end

    -- Simple Setup mode takes over entirely: hide every custom-indicator visual
    -- and render the isolated buff grid instead. The two systems never coexist.
    if db and db.profile and db.profile.bmDisplayMode == "simple" then
        for _, f in ipairs(d.bmIconPool) do f:Hide() end
        if d.bmBarPool then for _, b in ipairs(d.bmBarPool) do ClearBarDrain(b); b:Hide() end end
        if d.bmHCOverlay then d.bmHCOverlay:Hide() end
        if d.bmEffectBorder then d.bmEffectBorder:Hide() end
        d.bmActiveInstanceIDs = nil
        -- Clear any leftover custom frame-alpha dim so it can't persist in simple
        -- mode (the range ticker keeps multiplying by _bmSavedAlpha otherwise).
        button._bmSavedAlpha = nil
        if d.rangeAlpha then button:SetAlpha(d.rangeAlpha) end
        ns.BM_UpdateSimpleGrid(button, unit, db, updateInfo)
        return
    end
    -- Custom mode: make sure a previously-active simple grid never lingers.
    if d.bmSimpleIcons and d.bmSimpleActiveIDs then
        for _, f in ipairs(d.bmSimpleIcons) do
            if f._cooldown then f._cooldown:Hide() end
            f:Hide()
        end
        d.bmSimpleActiveIDs = nil
    end

    -- Party buttons use the party scale (Auto Resize); raid buttons use theirs.
    local iscale = (d._isParty and ns._partyBmScale or (d._isExtra and ns._xfBmScale) or ns._bmScale) or 1
    -- Base level for the Frame Level setting (re-applied per indicator below).
    local buttonLvl = button:GetFrameLevel()

    if not UnitExists(unit) then
        ns.BM_ClearIndicators(button)
        return
    end
    if #allActiveIndicators == 0 then
        -- No indicators configured for the current spec. If this button still has
        -- BM visuals from a previous spec that DID have indicators (e.g. switching
        -- from a healer spec to a non-healer one), hide them -- otherwise those
        -- icons stay stuck on the frame until /reload. BM_ClearIndicators also
        -- resets _bmSavedAlpha and restores range alpha. Guard on the per-button
        -- cache so steady-state UNIT_AURA traffic on a no-indicator spec does not
        -- re-hide already-hidden frames on every event (the cache is nil'd by the
        -- clear, so only the first post-transition event does the work).
        if d.bmActiveInstanceIDs then
            ns.BM_ClearIndicators(button)
        else
            button._bmSavedAlpha = nil
            if d.rangeAlpha then button:SetAlpha(d.rangeAlpha) end
        end
        return
    end

    local health = ns.RF_AnchorHostFor and ns.RF_AnchorHostFor(d) or d.health
    if not health then return end
    local PP = EllesmereUI.PanelPP or EllesmereUI.PP

    -- Quick skip: if incremental update has no HELPFUL changes that could
    -- affect our tracked spells, don't rescan (keep current visuals).
    if updateInfo and not updateInfo.isFullUpdate then
        local needScan = false
        if updateInfo.addedAuras then
            for _, ad in ipairs(updateInfo.addedAuras) do
                -- Skip isHelpful check (secret on other players, and harmful
                -- spell IDs won't match tracked buff IDs anyway)
                local sid = ad.spellId
                if sid and not issecretvalue(sid) then
                    if trackedSpellIDs[sid] then needScan = true; break end
                elseif sid then
                    -- Secret spellId: could be a tracked secret buff
                    needScan = true; break
                end
            end
        end
        if not needScan and updateInfo.removedAuraInstanceIDs and d.bmActiveInstanceIDs then
            for _, iid in ipairs(updateInfo.removedAuraInstanceIDs) do
                if d.bmActiveInstanceIDs[iid] then needScan = true; break end
            end
        end
        if not needScan and updateInfo.updatedAuraInstanceIDs and d.bmActiveInstanceIDs then
            for _, iid in ipairs(updateInfo.updatedAuraInstanceIDs) do
                if d.bmActiveInstanceIDs[iid] then needScan = true; break end
            end
        end
        if not needScan then return end
    end

    -- Hide everything before rescan
    for _, f in ipairs(d.bmIconPool) do
        f:Hide()
    end
    for _, b in ipairs(d.bmBarPool) do ClearBarDrain(b); b:Hide() end
    if d.bmHCOverlay then d.bmHCOverlay:Hide() end
    if d.bmEffectBorder then d.bmEffectBorder:Hide() end
    button._bmSavedAlpha = nil
    local GetFFD2 = ns.GetFFD
    local d2 = GetFFD2 and GetFFD2(button)
    if d2 and d2.rangeAlpha then
        button:SetAlpha(d2.rangeAlpha)
    end

    -- 1. Scan HELPFUL auras, build activeSpells + activePlayerSpells sets
    --    Non-secret: direct spellId lookup + PLAYER filter check.
    --    Secret: fingerprint matching (always player-cast by definition).
    wipe(activeSpells)
    wipe(activePlayerSpells)
    if not d.bmActiveInstanceIDs then d.bmActiveInstanceIDs = {} end
    wipe(d.bmActiveInstanceIDs)
    local idx = 1
    while true do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, idx, "HELPFUL")
        if not auraData then break end
        idx = idx + 1
        local sid = auraData.spellId
        if sid then
            if not issecretvalue(sid) then
                -- Normal path: direct spell ID check. Resolve alternate aura IDs
                -- (e.g. Earth Shield 383648, Ebon Might self-buff 395296) to the
                -- primary ID the indicators reference, then key by the primary.
                local psid = PRIMARY_BY_ALT[sid] or sid
                if trackedSpellIDs[psid] and not activeSpells[psid] then
                    activeSpells[psid] = auraData
                    if auraData.auraInstanceID then
                        d.bmActiveInstanceIDs[auraData.auraInstanceID] = true
                    end
                    -- Player-only check via filter API (avoids secret isFromPlayerOrPlayerPet)
                    local iid = auraData.auraInstanceID
                    if iid and C_UnitAuras_IsAuraFilteredOutByInstanceID then
                        if not C_UnitAuras_IsAuraFilteredOutByInstanceID(unit, iid, "PLAYER|HELPFUL") then
                            activePlayerSpells[psid] = auraData
                        end
                    end
                end
            else
                -- Secret path: fingerprint matching
                -- Secret auras identified by our fingerprint are always from
                -- the player's own spells (the signature table only contains
                -- spells the player's class can cast).
                local iid = auraData.auraInstanceID
                if iid then
                    local matchedSid = MatchSecretAura(unit, iid)
                    if matchedSid and not activeSpells[matchedSid] then
                        local entry = {
                            spellId = matchedSid,
                            icon = SECRET_SPELL_ICONS[matchedSid] or 136243,
                            duration = auraData.duration,
                            expirationTime = auraData.expirationTime,
                            applications = auraData.applications,
                            auraInstanceID = iid,
                        }
                        activeSpells[matchedSid] = entry
                        activePlayerSpells[matchedSid] = entry
                        d.bmActiveInstanceIDs[iid] = true
                    end
                end
            end
        end
    end


    -- 2. Process each active indicator
    iconPoolIdx = 0
    barPoolIdx  = 0

    for _, ind in ipairs(allActiveIndicators) do
        local indType = ind.type
        local typeInfo = INDICATOR_TYPE_MAP[indType]
        if not typeInfo then break end

        -- Per-spell own-only lookup: checks ownOnlySpells table, falls back to ownOnly boolean.
        -- Uses explicit if/else, NOT the "a and b or c" idiom: both the per-spell value and
        -- activePlayerSpells[sid] can legitimately be false/nil. With the idiom, an Own Only
        -- buff cast by someone else (activePlayerSpells[sid] == nil) would fall through to
        -- activeSpells[sid] and show the other player's buff, defeating the filter entirely.
        local ownSpells = ind.ownOnlySpells
        local ownFallback = ind.ownOnly ~= false
        local function GetAura(sid)
            local isOwn
            if ownSpells and ownSpells[sid] ~= nil then
                isOwn = ownSpells[sid]
            else
                isOwn = ownFallback
            end
            if isOwn then
                -- Own Only: return ONLY the player-cast aura (nil if we did not cast it).
                return activePlayerSpells[sid]
            end
            return activeSpells[sid]
        end

        if typeInfo.placed then
            -- Placed indicators: icon, square, bar
            if indType == "bar" then
                -- Bar: single spell
                local sid = ind.spells[1]
                local aura = sid and GetAura(sid)
                if aura then
                    barPoolIdx = barPoolIdx + 1
                    local bar = d.bmBarPool[barPoolIdx]
                    if bar then
                        BM_SetTipTarget(bar, unit, aura.auraInstanceID)
                        BM_ApplyBarLevel(bar, ind, buttonLvl)
                        bar:SetReverseFill(ind.reverseFill or false)
                        local c = ind.color or { r=0, g=1, b=0 }
                        bar:SetStatusBarColor(c.r, c.g, c.b, (ind.barColorOpacity or 100) / 100)
                        -- Background
                        if bar._bg then
                            local bgc = ind.barBgColor or { r=0, g=0, b=0 }
                            bar._bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (ind.barBgOpacity or 50) / 100)
                        end
                        -- Duration fill (smooth drain via native SetTimerDuration,
                        -- or a fixed-baseline self-drain when Max Duration is set)
                        local dur = aura.duration
                        local exp = aura.expirationTime
                        local iid = aura.auraInstanceID
                        local maxDur = BM_EffectiveMaxDur(ind)
                        if dur and exp and not issecretvalue(dur) and not issecretvalue(exp) and dur > 0 then
                            ApplyBarDrain(bar, unit, iid, dur, exp, maxDur)
                        else
                            ApplyBarDrain(bar, unit, iid, nil, nil, maxDur)
                        end
                        -- Threshold "expiring" recolor (secret-safe curve + ticker).
                        -- While enabled the ticker owns the bar color and reverts to
                        -- the normal color above the threshold; the immediate eval in
                        -- RegisterThreshold avoids a one-tick flash of the normal color.
                        if ind.thresholdEnabled and iid and not issecretvalue(iid) then
                            local tc = ind.thresholdColor or { r=1, g=0.2, b=0.2 }
                            local curve = GetThresholdColorCurve(
                                ind.threshold or 3,
                                c.r, c.g, c.b, (ind.barColorOpacity or 100) / 100,
                                tc.r, tc.g, tc.b, (ind.thresholdColorOpacity or 100) / 100)
                            if curve then
                                RegisterThreshold(bar, unit, iid, curve, ApplyBarThresholdColor, ind)
                            else
                                UnregisterThreshold(bar)
                            end
                        else
                            UnregisterThreshold(bar)
                        end
                        BM_PlaceBar(bar, health, ind, iscale)
                        bar:Show()
                    end
                end
            else
                -- Icon or Square: multi-spell with growth
                local growDir = ind.growDirection or "RIGHT"
                local sz = (ind.size or 12) * iscale
                local snap = ns.PixelSnap or function(v) return v end
                local gap = snap((ind.spacing or 1) * iscale)
                -- Running cursor: each icon advances the next by its OWN size, so a
                -- per-spell size offset reflows its neighbors instead of overlapping.
                -- CENTER needs the total run width up front to center it. (Computed
                -- only for CENTER; the common linear case skips this pre-pass.)
                local cursor = 0
                if growDir == "CENTER" then
                    local totalW, cnt = 0, 0
                    for _, sid2 in ipairs(ind.spells) do
                        if GetAura(sid2) then
                            local so2 = ind.sizeOffsets and ind.sizeOffsets[sid2] or 0
                            local s2 = sz + so2 * iscale
                            if s2 < 1 then s2 = 1 end
                            totalW = totalW + s2; cnt = cnt + 1
                        end
                    end
                    if cnt > 1 then totalW = totalW + gap * (cnt - 1) end
                    cursor = -totalW / 2
                end
                local spellIdx = 0
                for _, sid in ipairs(ind.spells) do
                    local aura = GetAura(sid)
                    if aura then
                        iconPoolIdx = iconPoolIdx + 1
                        local f = d.bmIconPool[iconPoolIdx]
                        if f then
                            BM_SetTipTarget(f, unit, aura.auraInstanceID)
                            BM_ApplyIconLevel(f, ind, buttonLvl)
                            -- Per-spell size offset (right-click in preview): base
                            -- size + this spell's offset, clamped to >= 1px.
                            local soff = ind.sizeOffsets and ind.sizeOffsets[sid] or 0
                            local iconSz = sz + soff * iscale
                            if iconSz < 1 then iconSz = 1 end
                            f:SetSize(iconSz, iconSz)
                            f:ClearAllPoints()
                            -- Cumulative growth by actual icon size (see cursor note).
                            -- All four directions share one structure: place the icon
                            -- at the accumulated size of the PREVIOUS icons (cursor),
                            -- then advance by this icon's OWN size. LEFT/UP just negate
                            -- the axis. (cursor starts at 0 so icon 1 lands flush at the
                            -- anchor with no special-case guard.)
                            local gx, gy = 0, 0
                            if growDir == "RIGHT" or growDir == "CENTER" then
                                gx = cursor; cursor = cursor + iconSz + gap
                            elseif growDir == "DOWN" then
                                gy = -cursor; cursor = cursor + iconSz + gap
                            elseif growDir == "LEFT" then
                                gx = -cursor; cursor = cursor + iconSz + gap
                            elseif growDir == "UP" then
                                gy = cursor; cursor = cursor + iconSz + gap
                            end
                            f:SetPoint(ind.position or "TOPLEFT", health, ind.position or "TOPLEFT",
                                       (ind.offsetX or 0) * iscale + gx, (ind.offsetY or 0) * iscale + gy)


                            -- Apply stacks font + position once per assignment
                            if f._count and ind.showStacks then
                                local sc2 = ind.stacksTextColor or { r=1, g=1, b=1 }
                                local sSz = (ind.stacksTextSize or 8) * iscale
                                local sOX = (ind.stacksOffsetX or 0) * iscale
                                local sOY = (ind.stacksOffsetY or 0) * iscale
                                local fontPath3 = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
                                EllesmereUI.ApplyIconTextFont(f._count, fontPath3, sSz, "raidFrames")
                                f._count:SetTextColor(sc2.r, sc2.g, sc2.b)
                                f._count:ClearAllPoints()
                                f._count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1 + sOX, -1 + sOY)
                            end

                            -- "Hide Icons" (icon type only) forces the icon
                            -- texture, border, and duration swipe off, leaving
                            -- just the stack count. Overrides the per-indicator
                            -- opacity/border/swipe inputs below.
                            local hideIcon = (indType == "icon") and ind.hideIcon == true
                            -- Icon opacity (affects texture + swipe, not text)
                            local iconAlpha = hideIcon and 0 or (ind.iconOpacity or 100) / 100

                            -- Normal color the threshold curve reverts to above the
                            -- cutoff: white tint for icons, the square's own color.
                            local ncR, ncG, ncB, ncA
                            if indType == "icon" then
                                local icon = aura.icon
                                if icon and not issecretvalue(icon) then
                                    f._tex:SetTexture(icon)
                                else
                                    f._tex:SetTexture(136243)
                                end
                                local _z = db.profile.bmIconZoom or 0.08
                                f._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)
                                f._tex:SetVertexColor(1, 1, 1, iconAlpha)
                                ncR, ncG, ncB, ncA = 1, 1, 1, iconAlpha
                            else -- square
                                -- Per-ability color: this spell's own color, falling
                                -- back to the legacy single ind.color, then default.
                                local c = (ind.spellColors and ind.spellColors[sid])
                                    or ind.color or { r=0, g=1, b=0 }
                                -- White texture + vertex color (not SetColorTexture) so the
                                -- threshold can recolor via secret-safe SetVertexColor, and a
                                -- reused icon's tint can't leak through.
                                f._tex:SetColorTexture(1, 1, 1, 1)
                                f._tex:SetVertexColor(c.r, c.g, c.b, iconAlpha)
                                f._tex:SetTexCoord(0, 1, 0, 1)
                                ncR, ncG, ncB, ncA = c.r, c.g, c.b, iconAlpha
                            end
                            -- Threshold expiring recolor (secret-safe curve + ticker).
                            -- For the "icon" indicator type the expiring color ALWAYS
                            -- targets the duration text (never the icon texture), whether
                            -- or not Hide Icons is on. That registration is deferred to the
                            -- duration-text block below (so the countdown font string
                            -- already exists). The "square" type still recolors its texture.
                            local textThresholdMode = (indType == "icon")
                            do
                                local tiid = aura.auraInstanceID
                                if textThresholdMode then
                                    -- Icon type: the expiring recolor targets the duration
                                    -- text, registered in the text block below -- but ONLY
                                    -- when duration text is shown. Seed a sound-only
                                    -- registration (no curve/apply) here so the threshold
                                    -- sound also works for glow-only / no-text setups; the
                                    -- text block upgrades this entry with the recolor curve
                                    -- when it runs. Registering fresh either way clears any
                                    -- stale prior curve, matching the old Unregister.
                                    if ind.thresholdEnabled and tiid and not issecretvalue(tiid)
                                       and ind.thresholdSound and ind.thresholdSound ~= "none" then
                                        RegisterThreshold(f, unit, tiid, nil, nil, ind)
                                    else
                                        UnregisterThreshold(f)
                                    end
                                elseif ind.thresholdEnabled and tiid and not issecretvalue(tiid) then
                                    local tc = ind.thresholdColor or { r=1, g=0.2, b=0.2 }
                                    local curve = GetThresholdColorCurve(
                                        ind.threshold or 3, ncR, ncG, ncB, ncA,
                                        tc.r, tc.g, tc.b, (ind.thresholdColorOpacity or 100) / 100)
                                    if curve then
                                        RegisterThreshold(f, unit, tiid, curve, ApplyTexThresholdColor, ind)
                                    else
                                        UnregisterThreshold(f)
                                    end
                                else
                                    UnregisterThreshold(f)
                                end
                            end

                            -- Icon Glow (icon type only): a glow that plays while
                            -- the buff is within the threshold window. The engine
                            -- glow runs while the icon is shown; the glow ticker
                            -- drives its overlay alpha so it only appears below the
                            -- threshold. Restart the animation only when style/
                            -- size/color changed so a steady glow never resets on a
                            -- rescan. Secret-safe (see the glow ticker above).
                            do
                                local gType = (indType == "icon") and (ind.iconGlowType or 0) or 0
                                local giid = aura.auraInstanceID
                                local Glows = EllesmereUI.Glows
                                if gType > 0 and ind.thresholdEnabled and giid
                                   and not issecretvalue(giid) and Glows and Glows.StartGlow then
                                    local gov = f._bmGlowOverlay
                                    if not gov then
                                        gov = CreateFrame("Frame", nil, f)
                                        gov:SetAllPoints(f)
                                        gov:SetFrameLevel(f:GetFrameLevel() + 6)
                                        gov:EnableMouse(false)
                                        f._bmGlowOverlay = gov
                                    end
                                    local cr, cg, cb = ind.iconGlowR or 1.0, ind.iconGlowG or 0.776, ind.iconGlowB or 0.376
                                    if ind.iconGlowClassColor then
                                        local _, classFile = UnitClass("player")
                                        local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                                        if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                                    end
                                    if (not gov._euiGlowActive) or gov._bmGlowStyle ~= gType
                                       or gov._bmGlowW ~= iconSz or gov._bmGlowCR ~= cr
                                       or gov._bmGlowCG ~= cg or gov._bmGlowCB ~= cb then
                                        Glows.StartGlow(gov, gType, iconSz, cr, cg, cb)
                                        gov._bmGlowStyle, gov._bmGlowW = gType, iconSz
                                        gov._bmGlowCR, gov._bmGlowCG, gov._bmGlowCB = cr, cg, cb
                                    end
                                    local gcurve = GetThresholdAlphaCurve(ind.threshold or 3)
                                    if gcurve then RegisterGlow(gov, unit, giid, gcurve) end
                                elseif f._bmGlowOverlay then
                                    UnregisterGlow(f._bmGlowOverlay)
                                    if f._bmGlowOverlay._euiGlowActive and Glows and Glows.StopGlow then
                                        Glows.StopGlow(f._bmGlowOverlay)
                                    end
                                end
                            end

                            -- Stack count (secret-safe via Blizzard API)
                            if ind.showStacks and C_UnitAuras.GetAuraApplicationDisplayCount
                                and aura.auraInstanceID then
                                local stackText = C_UnitAuras.GetAuraApplicationDisplayCount(
                                    unit, aura.auraInstanceID, 2, 99)
                                f._count:SetText(stackText or "")
                            else
                                f._count:SetText("")
                            end

                            -- Indicator border
                            if f._bdr and PP then
                                local ibs = hideIcon and 0 or (ind.indBorderSize or 1)
                                if ibs > 0 then
                                    local ibc = ind.indBorderColor or { r=0, g=0, b=0 }
                                    PP.UpdateBorder(f._bdr, ibs, ibc.r, ibc.g, ibc.b, 1)
                                    f._bdr:Show()
                                else
                                    f._bdr:Hide()
                                end
                            end

                            -- Duration swipe + text (secret-safe via DurationObject + GetCountdownFontString)
                            if f._cooldown then
                                -- Hide Icons zeroes the icon texture but keeps the
                                -- cooldown layer at full alpha so the duration text
                                -- still shows; only the swipe is forced off below.
                                f._cooldown:SetAlpha(hideIcon and 1 or iconAlpha)
                                local wantSwipe = (not hideIcon) and (ind.showDuration ~= false)
                                local wantDurText = ind.showDurationText
                                if wantSwipe or wantDurText then
                                    -- Only Show the cooldown when a cooldown was actually
                                    -- applied. A no-duration aura (e.g. a beacon) has nothing
                                    -- to set; showing the empty cooldown anyway draws its full
                                    -- reversed swipe for a frame or two before the frame
                                    -- self-hides, strobing the icon dark on every rescan.
                                    -- Clear() also wipes any stale swipe a reused pool frame
                                    -- inherited from its previous occupant.
                                    -- Permanent auras return a degenerate 0,0 duration object;
                                    -- a cooldown armed from one strobes -- the CLIENT shows the
                                    -- full reversed swipe then self-hides, an internal cycle
                                    -- that Lua-side show/hide gating cannot stop. Mask with
                                    -- ALPHA instead: durObj:IsZero() -> alpha 0. Secret-safe
                                    -- and orthogonal to the client's internal show/hide.
                                    local applied = false
                                    local iid = aura.auraInstanceID
                                    local cdBaseA = hideIcon and 1 or iconAlpha
                                    local mdMax = BM_EffectiveMaxDur(ind)
                                    local mdExp = aura.expirationTime
                                    if mdMax and mdExp and not issecretvalue(mdExp) and mdExp > 0 then
                                        -- Max Duration override: scale the swipe to the fixed
                                        -- baseline (still ends at the real expiration). A buff
                                        -- applied at < M shows a partly-drained swipe from the
                                        -- start; one longer than M shows full until it drops
                                        -- below M.
                                        f._cooldown:SetCooldown(mdExp - mdMax, mdMax)
                                        f._cooldown:SetAlpha(cdBaseA)
                                        applied = true
                                    elseif iid and not issecretvalue(iid) and C_UnitAuras.GetAuraDuration then
                                        local durObj = C_UnitAuras.GetAuraDuration(unit, iid)
                                        if durObj then
                                            f._cooldown:SetCooldownFromDurationObject(durObj)
                                            if durObj.IsZero and f._cooldown.SetAlphaFromBoolean then
                                                f._cooldown:SetAlphaFromBoolean(durObj:IsZero(), 0, cdBaseA)
                                            else
                                                f._cooldown:SetAlpha(cdBaseA)
                                            end
                                            applied = true
                                        end
                                    else
                                        local dur = aura.duration
                                        local exp = aura.expirationTime
                                        if dur and exp and not issecretvalue(dur) and not issecretvalue(exp) and dur > 0 then
                                            f._cooldown:SetCooldown(exp - dur, dur)
                                            f._cooldown:SetAlpha(cdBaseA)
                                            applied = true
                                        end
                                    end
                                    if applied then
                                        f._cooldown:SetDrawSwipe(wantSwipe)
                                        f._cooldown:SetHideCountdownNumbers(not wantDurText)
                                        f._cooldown:Show()
                                    else
                                        f._cooldown:Clear()
                                        f._cooldown:Hide()
                                    end
                                    -- Style the built-in countdown text via GetCountdownFontString
                                    if applied and wantDurText then
                                        local cdText = f._cooldown.GetCountdownFontString and f._cooldown:GetCountdownFontString()
                                        if cdText then
                                            local tc = ind.durationTextColor or { r=1, g=1, b=1 }
                                            local fontPath2 = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
                                            EllesmereUI.ApplyIconTextFont(cdText, fontPath2, ind.durationTextSize or 8, "raidFrames")
                                            cdText:SetTextColor(tc.r, tc.g, tc.b)
                                            cdText:ClearAllPoints()
                                            cdText:SetPoint("CENTER", f, "CENTER", ind.durationTextOffsetX or 0, ind.durationTextOffsetY or 0)
                                            -- Icon indicator threshold: drive the expiring color
                                            -- onto the duration text (always, for the icon type).
                                            -- The curve reverts to the duration text color above
                                            -- the threshold, so the static color set just above is
                                            -- the baseline and the immediate eval here overrides it
                                            -- without a flash.
                                            if textThresholdMode then
                                                local tiid = aura.auraInstanceID
                                                if ind.thresholdEnabled and tiid and not issecretvalue(tiid) then
                                                    local thc = ind.thresholdColor or { r=1, g=0.2, b=0.2 }
                                                    local curve = GetThresholdColorCurve(
                                                        ind.threshold or 3, tc.r, tc.g, tc.b, 1,
                                                        thc.r, thc.g, thc.b, (ind.thresholdColorOpacity or 100) / 100)
                                                    if curve then
                                                        RegisterThreshold(f, unit, tiid, curve, ApplyDurTextThresholdColor, ind)
                                                    end
                                                end
                                            end
                                        end
                                    end
                                else
                                    f._cooldown:Hide()
                                end
                            end

                            f:Show()
                            spellIdx = spellIdx + 1
                        end
                    end
                end
            end
        else
            -- Frame effects
            local anyPresent = false
            local allPresent = #ind.spells > 0
            local presentAura = nil
            for _, sid in ipairs(ind.spells) do
                local a = GetAura(sid)
                if a then anyPresent = true; presentAura = presentAura or a
                else allPresent = false end
            end

            local showWhen = ind.showWhen or "present"
            local shouldShow = (showWhen == "present" and anyPresent)
                            or (showWhen == "missing" and not anyPresent)
                            or (showWhen == "allPresent" and allPresent)
                            or (showWhen == "anyMissing" and not allPresent)

            -- Threshold drives off the first present tracked aura (present mode
            -- only -- a missing aura has no remaining time to watch). Secret-safe.
            local presentIid
            if showWhen == "present" and presentAura then presentIid = presentAura.auraInstanceID end
            local threshOK = ind.thresholdEnabled and presentIid and not issecretvalue(presentIid)

            if shouldShow then
                if indType == "healthcolor" then
                    if d.bmHCOverlay then
                        local c = ind.color or { r=0, g=1, b=0 }
                        local op = (ind.opacity or 100) / 100
                        -- White texture + vertex so the threshold can recolor via
                        -- secret-safe SetVertexColor.
                        d.bmHCOverlay:SetColorTexture(1, 1, 1, 1)
                        d.bmHCOverlay:SetVertexColor(c.r, c.g, c.b, op)
                        d.bmHCOverlay:Show()
                        local curve
                        if threshOK then
                            local tc = ind.thresholdColor or { r=1, g=0.2, b=0.2 }
                            curve = GetThresholdColorCurve(ind.threshold or 3,
                                c.r, c.g, c.b, op, tc.r, tc.g, tc.b, (ind.thresholdColorOpacity or 100) / 100)
                        end
                        if curve then RegisterThreshold(d.bmHCOverlay, unit, presentIid, curve, ApplyOverlayThresholdColor, ind)
                        else UnregisterThreshold(d.bmHCOverlay) end
                    end
                elseif indType == "border" then
                    if d.bmEffectBorder and PP then
                        local c = ind.color or { r=0, g=1, b=0 }
                        local op = (ind.borderOpacity or 100) / 100
                        local bw = ind.borderWidth or 2
                        PP.UpdateBorder(d.bmEffectBorder, bw, c.r, c.g, c.b, op)
                        d.bmEffectBorder:Show()
                        local curve
                        if threshOK then
                            local tc = ind.thresholdColor or { r=1, g=0.2, b=0.2 }
                            curve = GetThresholdColorCurve(ind.threshold or 3,
                                c.r, c.g, c.b, op, tc.r, tc.g, tc.b, (ind.thresholdColorOpacity or 100) / 100)
                        end
                        if curve then RegisterThreshold(d.bmEffectBorder, unit, presentIid, curve, ApplyBorderThresholdColor, ind)
                        else UnregisterThreshold(d.bmEffectBorder) end
                    end
                elseif indType == "framealpha" then
                    local bmA = ind.alpha or 0.4
                    button._bmSavedAlpha = bmA
                    -- Multiply with range alpha so both effects coexist.
                    -- If rangeAlpha is nil (secret-managed), just store bmA
                    -- and let the range ticker apply the combined value.
                    local GetFFD = ns.GetFFD
                    local d3 = GetFFD and GetFFD(button)
                    if d3 and d3.rangeAlpha then
                        button:SetAlpha(bmA * d3.rangeAlpha)
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Reload (settings changed)
-------------------------------------------------------------------------------
function ns.BM_ReloadIndicators(db)
    RebuildLookup(db)
end

-------------------------------------------------------------------------------
--  Preview indicator creation
-------------------------------------------------------------------------------
-- Forward-declare so preview click handler can set it (defined further down)
local selectedIndicator = nil

-- Shared hover/click handlers for preview indicator frames.
-- On hover: show 2px accent border. On click: select that indicator.
local function PvInd_OnEnter(self)
    if not self._bmIndId then return end
    if self._hoverBdr then
        local lPP = EllesmereUI.PanelPP or EllesmereUI.PP
        if lPP then
            local ac = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
            lPP.UpdateBorder(self._hoverBdr, 2, ac.r, ac.g, ac.b, 1)
            self._hoverBdr:Show()
        end
    end
end

local function PvInd_OnLeave(self)
    if self._hoverBdr then self._hoverBdr:Hide() end
end

-- Resolve the indicator table for a preview frame's stored indicator id.
local function BM_FindIndicatorById(indId)
    local specKey = ns._bmSelectedSpecKey
    if not specKey or not ns.db or not ns.db.profile then return nil end
    local specData = ns.db.profile.bmIndicators and ns.db.profile.bmIndicators[specKey]
    if not specData then return nil end
    for _, ind in ipairs(specData) do
        if ind.id == indId then return ind end
    end
    return nil
end

-- Per-spell "Size Offset" right-click popup. Built once; retargeted each click
-- via _bmSizeOffsetTarget so the slider's get/set always read the clicked spell.
local _bmSizeOffsetTarget = {}
local function BM_ShowSizeOffsetPopup(anchorFrame)
    if not ns._bmSizeOffsetPopupShow then
        local _, showFn = EllesmereUI.BuildCogPopup({
            title = "Size Offset",
            -- Anchor is the preview icon, not a cog button, so don't fade it on close.
            noOwnerDim = true,
            rows = {
                { type = "slider", label = "Size Offset", min = -20, max = 20, step = 1,
                  get = function()
                      local ind = _bmSizeOffsetTarget.ind
                      local sid = _bmSizeOffsetTarget.sid
                      if ind and sid and ind.sizeOffsets then return ind.sizeOffsets[sid] or 0 end
                      return 0
                  end,
                  set = function(v)
                      local ind = _bmSizeOffsetTarget.ind
                      local sid = _bmSizeOffsetTarget.sid
                      if not ind or not sid then return end
                      v = tonumber(v) or 0
                      if v == 0 then
                          if ind.sizeOffsets then ind.sizeOffsets[sid] = nil end
                      else
                          ind.sizeOffsets = ind.sizeOffsets or {}
                          ind.sizeOffsets[sid] = v
                      end
                      -- Rebuild the spell lookup, re-render live frames, and
                      -- refresh the options preview (mirrors the sidebar sliders'
                      -- ReloadAndUpdate path).
                      if ns.BM_ReloadIndicators then ns.BM_ReloadIndicators(ns.db) end
                      if ns.ReloadFrames then ns.ReloadFrames() end
                      if ns._bmPreviewFrame and ns._bmPreviewFrame._health and ns.BM_ApplyPreviewIndicators then
                          ns.BM_ApplyPreviewIndicators(ns._bmPreviewFrame, 1, ns.db.profile)
                      end
                  end },
            },
        })
        ns._bmSizeOffsetPopupShow = showFn
    end
    ns._bmSizeOffsetPopupShow(anchorFrame)
end

local function PvInd_OnClick(self, button)
    if not self._bmIndId then return end
    local ind = BM_FindIndicatorById(self._bmIndId)
    if not ind then return end

    -- Right-click an icon/square: per-spell size offset popup (other spells in
    -- the same indicator keep the group's base size).
    if button == "RightButton" then
        if (self._bmIndType == "icon" or self._bmIndType == "square") and self._bmSpellId then
            _bmSizeOffsetTarget.ind = ind
            _bmSizeOffsetTarget.sid = self._bmSpellId
            BM_ShowSizeOffsetPopup(self)
        end
        return
    end

    -- Left-click: select the indicator for editing in the sidebar.
    selectedIndicator = ind
    EllesmereUI:RefreshPage(true)
end

local function AttachPvIndHover(fr, PP)
    if PP then
        local hb = CreateFrame("Frame", nil, fr)
        hb:SetAllPoints()
        hb:SetFrameLevel(fr:GetFrameLevel() + 8)
        hb:EnableMouse(false)
        PP.CreateBorder(hb, 0, 0, 0, 0, 2)
        hb:Hide()
        fr._hoverBdr = hb
    end
    fr:EnableMouse(true)
    fr:SetScript("OnEnter", PvInd_OnEnter)
    fr:SetScript("OnLeave", PvInd_OnLeave)
    fr:SetScript("OnMouseUp", PvInd_OnClick)
end

function ns.BM_CreatePreviewIndicators(f, health, PP)
    if not health then return end

    local iconPool = {}
    for i = 1, ICON_POOL_SIZE do
        local fr = CreateFrame("Frame", nil, health)
        fr:SetFrameLevel(f:GetFrameLevel() + ns.LVL_AURA)
        fr:SetSize(12, 12)
        fr:Hide()

        local tex = fr:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        fr._tex = tex

        local cooldown = CreateFrame("Cooldown", nil, fr, "CooldownFrameTemplate")
        cooldown:SetAllPoints()
        cooldown:SetDrawEdge(false)
        cooldown:SetDrawSwipe(true)
        cooldown:SetSwipeColor(0, 0, 0, 0.6)
        cooldown:SetReverse(true)
        cooldown:SetHideCountdownNumbers(true)
        cooldown:EnableMouse(false)
        cooldown:Hide()
        fr._cooldown = cooldown

        if PP then
            local bdr = CreateFrame("Frame", nil, fr)
            bdr:SetAllPoints()
            bdr:SetFrameLevel(fr:GetFrameLevel() + 1)
            bdr:EnableMouse(false)
            PP.CreateBorder(bdr, 0, 0, 0, 1, 1)
            fr._bdr = bdr
        end

        local textCarrier = CreateFrame("Frame", nil, fr)
        textCarrier:SetAllPoints()
        textCarrier:SetFrameLevel(fr:GetFrameLevel() + 5)
        textCarrier:EnableMouse(false)
        fr._textCarrier = textCarrier
        local countFS = textCarrier:CreateFontString(nil, "OVERLAY")
        countFS:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT", 1, -1)
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        EllesmereUI.ApplyIconTextFont(countFS, fontPath, 8, "raidFrames")
        countFS:SetTextColor(1, 1, 1)
        fr._count = countFS

        local durFS = textCarrier:CreateFontString(nil, "OVERLAY")
        durFS:SetPoint("CENTER", fr, "CENTER", 0, 0)
        EllesmereUI.ApplyIconTextFont(durFS, fontPath, 8, "raidFrames")
        durFS:SetTextColor(1, 1, 1)
        durFS:Hide()
        fr._durText = durFS

        AttachPvIndHover(fr, PP)
        iconPool[i] = fr
    end

    local barPool = {}
    for i = 1, BAR_POOL_SIZE do
        local bar = CreateFrame("StatusBar", nil, health)
        bar:SetFrameLevel(f:GetFrameLevel() + ns.LVL_AURA)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0.6)
        bar:Hide()

        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.5)
        bar._bg = bg

        AttachPvIndHover(bar, PP)
        barPool[i] = bar
    end

    -- Frame effect overlays for preview
    -- ARTWORK sublevel 2: sits below the dispel overlay (sublevel 3), matching
    -- the real frames.
    local hcOverlay = health:CreateTexture(nil, "ARTWORK", nil, 2)
    local pvFillTex = health:GetStatusBarTexture()
    if pvFillTex then
        hcOverlay:SetAllPoints(pvFillTex)
    else
        hcOverlay:SetAllPoints(health)
    end
    hcOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    hcOverlay:Hide()

    local effectBorder = CreateFrame("Frame", nil, f)
    effectBorder:SetAllPoints(f)
    effectBorder:SetFrameLevel(f:GetFrameLevel() + 11)
    effectBorder:Hide()
    if PP then PP.CreateBorder(effectBorder, 0, 1, 0, 1, 2) end

    f._bmIconPool      = iconPool
    f._bmBarPool       = barPool
    f._bmHCOverlay     = hcOverlay
    f._bmEffectBorder  = effectBorder
end

-------------------------------------------------------------------------------
--  Preview data application
--  Shows indicators for the player (slot 1) using actual saved configs.
-------------------------------------------------------------------------------
local previewSpellIcons = {}

local function GetSpellIcon(spellID)
    if previewSpellIcons[spellID] then return previewSpellIcons[spellID] end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    -- Secret auras (e.g. Sense Power) often have no resolvable spell-info icon;
    -- fall back to the known fingerprint icon before the generic question mark.
    local icon = (info and info.iconID) or SECRET_SPELL_ICONS[spellID] or 136243
    previewSpellIcons[spellID] = icon
    return icon
end

function ns.BM_ApplyPreviewIndicators(f, index, s)
    local iconPool = f._bmIconPool
    local barPool  = f._bmBarPool
    if not iconPool then return end
    -- Party preview passes the party proxy as `s`; use the party scale then.
    local iscale = ((s == ns._scaledPartyProxy) and ns._partyBmScale or ns._bmScale) or 1

    -- Hide all first (reset cooldowns so they re-apply fresh)
    for _, fr in ipairs(iconPool) do
        if fr._cooldown then fr._cooldown:SetCooldown(0, 0); fr._cooldown:Hide() end
        if fr._durText then fr._durText:Hide() end
        if fr._hoverBdr then fr._hoverBdr:Hide() end
        fr._bmIndId = nil
        fr._bmSpellId = nil
        fr._bmIndType = nil
        fr:Hide()
    end
    if barPool then
        for _, b in ipairs(barPool) do
            if b._hoverBdr then b._hoverBdr:Hide() end
            b._bmIndId = nil
            b:Hide()
        end
    end
    if f._bmHCOverlay then f._bmHCOverlay:Hide() end
    if f._bmEffectBorder then f._bmEffectBorder:Hide() end
    f:SetAlpha(1)

    -- Only show on slot 1 (player) for the preview
    if index ~= 1 then return end

    local db = ns.db
    if not db or not db.profile or not db.profile.bmIndicators then return end
    local health = ns.RF_AnchorHost and ns.RF_AnchorHost(f._health, s) or f._health
    if not health then return end
    local PP = EllesmereUI.PanelPP or EllesmereUI.PP
    -- Base level for the Frame Level setting (mirrors the live render).
    local pvBaseLvl = f:GetFrameLevel()

    -- Show only the selected spec's indicators
    local iPoolIdx = 0
    local bPoolIdx = 0

    local activeSpecKey = ns._bmSelectedSpecKey
    local specList = activeSpecKey and db.profile.bmIndicators[activeSpecKey]
    for _, specData in pairs(specList and { specList } or db.profile.bmIndicators) do
        if type(specData) == "table" then
            for _, ind in ipairs(specData) do
                if ind.enabled and ind.spells and #ind.spells > 0 then
                    local indType = ind.type
                    local typeInfo = INDICATOR_TYPE_MAP[indType]

                    -- Frame effects: show when selected or when all-indicators eyeball is on
                    if not typeInfo or not typeInfo.placed then
                        local isSelected = ns._bmSelectedIndId and ind.id == ns._bmSelectedIndId
                        local wantShow = isSelected or ns._bmAllIndicatorsVisible
                        if wantShow then
                            if indType == "healthcolor" and f._bmHCOverlay then
                                local c = ind.color or { r=0, g=1, b=0 }
                                f._bmHCOverlay:SetColorTexture(c.r, c.g, c.b, (ind.opacity or 100) / 100)
                                f._bmHCOverlay:Show()
                            elseif indType == "border" and f._bmEffectBorder and PP then
                                local c = ind.color or { r=0, g=1, b=0 }
                                local bw = ind.borderWidth or 2
                                PP.UpdateBorder(f._bmEffectBorder, bw, c.r, c.g, c.b, (ind.borderOpacity or 100) / 100)
                                f._bmEffectBorder:Show()
                            elseif indType == "framealpha" then
                                f:SetAlpha(ind.alpha or 0.4)
                            end
                        end
                    end

                    if typeInfo and typeInfo.placed then
                        if indType == "bar" then
                            bPoolIdx = bPoolIdx + 1
                            local bar = barPool and barPool[bPoolIdx]
                            if bar then
                                BM_ApplyBarLevel(bar, ind, pvBaseLvl)
                                bar:SetReverseFill(ind.reverseFill or false)
                                local c = ind.color or { r=0, g=1, b=0 }
                                bar:SetStatusBarColor(c.r, c.g, c.b, (ind.barColorOpacity or 100) / 100)
                                if bar._bg then
                                    local bgc = ind.barBgColor or { r=0, g=0, b=0 }
                                    bar._bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (ind.barBgOpacity or 50) / 100)
                                end
                                local barSid = ind.spells and ind.spells[1]
                                if barSid and not PREVIEW_NO_DURATION[barSid] then
                                    bar:SetValue(GetPvCDSeed(index, barSid))
                                else
                                    bar:SetValue(1)
                                end
                                BM_PlaceBar(bar, health, ind, iscale)
                                bar._bmIndId = ind.id
                                bar:Show()
                            end
                        else
                            local growDir = ind.growDirection or "RIGHT"
                            local sz = (ind.size or 12) * iscale
                            local snap = ns.PixelSnap or function(v) return v end
                            local gap = snap((ind.spacing or 1) * iscale)
                            local isSelected = ns._bmSelectedIndId and ind.id == ns._bmSelectedIndId
                            local maxShow = (isSelected or ns._bmAllIndicatorsVisible) and #ind.spells or 2
                            local previewTotal = math.min(maxShow, #ind.spells)
                            -- Running cursor (matches live render): each icon advances
                            -- the next by its own size so size offsets reflow neighbors.
                            local cursor = 0
                            if growDir == "CENTER" then
                                local totalW = 0
                                for si2 = 1, previewTotal do
                                    local so2 = ind.sizeOffsets and ind.sizeOffsets[ind.spells[si2]] or 0
                                    local s2 = sz + so2 * iscale
                                    if s2 < 1 then s2 = 1 end
                                    totalW = totalW + s2
                                end
                                if previewTotal > 1 then totalW = totalW + gap * (previewTotal - 1) end
                                cursor = -totalW / 2
                            end
                            for si, sid in ipairs(ind.spells) do
                                if si > maxShow then break end
                                iPoolIdx = iPoolIdx + 1
                                local fr = iconPool[iPoolIdx]
                                if fr then
                                    BM_ApplyIconLevel(fr, ind, pvBaseLvl)
                                    -- Per-spell size offset (right-click to set):
                                    -- base size + this spell's offset, clamped >= 1px.
                                    local soff = ind.sizeOffsets and ind.sizeOffsets[sid] or 0
                                    local iconSz = sz + soff * iscale
                                    if iconSz < 1 then iconSz = 1 end
                                    fr:SetSize(iconSz, iconSz)
                                    fr:ClearAllPoints()
                                    -- Matches BM_UpdateIndicators: place at accumulated
                                    -- previous sizes, then advance by own size (LEFT/UP
                                    -- negate the axis; no first-icon guard needed).
                                    local gx, gy = 0, 0
                                    if growDir == "RIGHT" or growDir == "CENTER" then
                                        gx = cursor; cursor = cursor + iconSz + gap
                                    elseif growDir == "DOWN" then
                                        gy = -cursor; cursor = cursor + iconSz + gap
                                    elseif growDir == "LEFT" then
                                        gx = -cursor; cursor = cursor + iconSz + gap
                                    elseif growDir == "UP" then
                                        gy = cursor; cursor = cursor + iconSz + gap
                                    end
                                    fr:SetPoint(ind.position or "TOPLEFT", health, ind.position or "TOPLEFT",
                                                (ind.offsetX or 0) * iscale + gx, (ind.offsetY or 0) * iscale + gy)
                                    -- "Hide Icons" (icon type only): keep the frame
                                    -- alpha (so the stack count still previews) but
                                    -- zero the icon texture, swipe, and border below.
                                    local pvHideIcon = (indType == "icon") and ind.hideIcon == true
                                    local pvAlpha = pvHideIcon and 1 or (ind.iconOpacity or 100) / 100
                                    if ns._bmAllIndicatorsVisible then
                                        pvAlpha = 1
                                    elseif not isSelected then
                                        pvAlpha = pvAlpha * 0.5
                                    end
                                    fr:SetAlpha(pvAlpha)
                                    if indType == "icon" then
                                        fr._tex:SetTexture(GetSpellIcon(sid))
                                        local _z = s.bmIconZoom or 0.08
                                        fr._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)
                                        fr._tex:SetVertexColor(1, 1, 1, pvHideIcon and 0 or 1)
                                    else
                                        -- Per-ability color (preview): this spell's
                                        -- color, then legacy ind.color, then default.
                                        local c = (ind.spellColors and ind.spellColors[sid])
                                            or ind.color or { r=0, g=1, b=0 }
                                        -- Reset vertex first (see live render): a frame
                                        -- reused from an icon can carry a faded vertex
                                        -- tint that would blank the square.
                                        fr._tex:SetVertexColor(1, 1, 1, 1)
                                        fr._tex:SetColorTexture(c.r, c.g, c.b, 1)
                                        fr._tex:SetTexCoord(0, 1, 0, 1)
                                    end
                                    -- Blistering Scales (360827): show hardcoded "8" stacks in preview
                                    local previewStacks = (sid == 360827 and "8") or (sid == 33763 and "2")
                                    if ind.showStacks and previewStacks then
                                        local sSz = (ind.stacksTextSize or 8) * iscale
                                        local sc = ind.stacksTextColor or { r=1, g=1, b=1 }
                                        local sOX = (ind.stacksOffsetX or 0) * iscale
                                        local sOY = (ind.stacksOffsetY or 0) * iscale
                                        local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
                                        EllesmereUI.ApplyIconTextFont(fr._count, fp, sSz, "raidFrames")
                                        fr._count:SetTextColor(sc.r, sc.g, sc.b)
                                        fr._count:ClearAllPoints()
                                        fr._count:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT", 1 + sOX, -1 + sOY)
                                        fr._count:SetText(previewStacks)
                                    else
                                        fr._count:SetText("")
                                    end
                                    fr._bmIndId = ind.id
                                    fr._bmSpellId = sid
                                    fr._bmIndType = indType
                                    fr:Show()
                                    -- Preview cooldown swipe (frame must be visible first)
                                    if fr._cooldown then
                                        if not PREVIEW_NO_DURATION[sid] then
                                            local seed = GetPvCDSeed(index, sid)
                                            local fakeDisplay = math.floor(3 + seed * 17)
                                            -- Use a long future expiry so swipe barely moves
                                            local now = GetTime()
                                            local dur = 3600
                                            local elapsed = dur * (1 - seed)
                                            fr._cooldown:SetCooldown(now - elapsed, dur)
                                            fr._cooldown:SetDrawSwipe((not pvHideIcon) and (ind.showDuration ~= false))
                                            fr._cooldown:SetHideCountdownNumbers(true)
                                            -- Manual duration text (static, not countdown).
                                            -- Stays visible under Hide Icons (frame alpha is
                                            -- kept; only the icon texture/swipe are zeroed).
                                            if ind.showDurationText and fr._durText then
                                                local dtc = ind.durationTextColor or { r=1, g=1, b=1 }
                                                local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
                                                EllesmereUI.ApplyIconTextFont(fr._durText, fp, ind.durationTextSize or 8, "raidFrames")
                                                fr._durText:SetTextColor(dtc.r, dtc.g, dtc.b)
                                                fr._durText:ClearAllPoints()
                                                fr._durText:SetPoint("CENTER", fr, "CENTER",
                                                    ind.durationTextOffsetX or 0, ind.durationTextOffsetY or 0)
                                                fr._durText:SetText(fakeDisplay)
                                                fr._durText:Show()
                                            elseif fr._durText then
                                                fr._durText:Hide()
                                            end
                                            fr._cooldown:Show()
                                        else
                                            fr._cooldown:Hide()
                                            if fr._durText then fr._durText:Hide() end
                                        end
                                    end
                                    if fr._bdr and PP then
                                        local ibs = pvHideIcon and 0 or (ind.indBorderSize or 1)
                                        if ibs > 0 then
                                            local ibc = ind.indBorderColor or { r=0, g=0, b=0 }
                                            PP.UpdateBorder(fr._bdr, ibs, ibc.r, ibc.g, ibc.b, 1)
                                            fr._bdr:Show()
                                        else
                                            fr._bdr:Hide()
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Options page builder
--  Layout: 70/30 vertical split for the full page height.
--  Left column: creation row at top, then indicator settings below.
--  Right column: sidebar with indicator tiles spanning full page height.
-------------------------------------------------------------------------------
-- Page-level state (persists across setting changes within same page open)
local selectedSpecKey = nil
-- selectedIndicator: forward-declared near preview hover/click handlers
local selectedSpells = {}      -- temp table for creation spell selection
local selectedType = "icon"

local function AutoDetectSpec()
    -- Exact spec match (locale-independent, by spec ID).
    local key = CurrentSpecKey()
    if key then return key end

    -- Fallback for the options UI: pick the first tracked spec for the player's
    -- class so a non-tracked spec (e.g. a DPS spec) still opens on something sane.
    local _, classToken = UnitClass("player")
    if classToken then
        for _, spec in ipairs(HEALER_SPECS) do
            if spec.classToken == classToken then
                return spec.key
            end
        end
    end
    -- Class has no tracked spec at all (e.g. Warrior): open on Holy Paladin
    -- instead of a blank page.
    return "PALADIN_HOLY"
end

-------------------------------------------------------------------------------
--  Simple Setup preview: a self-contained raid-frame health-bar replica plus a
--  live preview of the simple buff grid. Mirrors the custom preview's health
--  bar 1:1 but has NO spec picker / indicator pools, and is kept fully separate
--  so the two preview systems never interact.
--  Returns: pvFrame, sectionH, RefreshFn
-------------------------------------------------------------------------------
function ns.BM_BuildSimplePreview(parent, s, fontPath, PP, centerX, topY)
    local PV_SCALE = 1.5
    local rawW = s.frameWidth or 72
    local rawH = s.frameHeight or 46
    local previewPad = 20
    -- Cap the preview's on-screen height at 100px via a uniform downscale, which
    -- keeps the frame's aspect ratio (rawW:rawH) intact. Simple + custom use the
    -- same value -- adjust both together.
    if rawH * PV_SCALE > 100 then PV_SCALE = 100 / rawH end
    local pvH = floor(rawH * PV_SCALE + 0.5)
    local sectionH = max(pvH + previewPad * 2, 150)

    local pvFrame = CreateFrame("Frame", nil, parent)
    pvFrame:SetSize(rawW, rawH)
    pvFrame:SetScale(PV_SCALE)
    pvFrame:SetPoint("TOP", parent, "TOPLEFT", floor(centerX / PV_SCALE), topY / PV_SCALE)

    -- Background
    local bgc = s.customBgColor or { r = 17/255, g = 17/255, b = 17/255 }
    local bg = pvFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()

    local rawPowerH = (s.powerShowForHealer or s.powerShowForTank or s.powerShowForDPS) and (s.powerHeight or 4) or 0
    local rawTopBarH = s.topNameBarEnabled and (s.topNameBarHeight or 20) or 0
    local healthH = rawH - rawPowerH - rawTopBarH

    -- Health bar (matches the custom preview build exactly)
    local texKey = s.healthBarTexture or "atrocity"
    local texPath = EllesmereUI.ResolveTexturePath and
        EllesmereUI.ResolveTexturePath(ns.healthBarTextures or {}, texKey, "Interface\\Buttons\\WHITE8X8")
        or "Interface\\Buttons\\WHITE8X8"
    local health = CreateFrame("StatusBar", nil, pvFrame)
    health:SetFrameLevel(pvFrame:GetFrameLevel() + 2)
    health:SetPoint("TOPLEFT", pvFrame, "TOPLEFT", 0, -rawTopBarH)
    health:SetPoint("TOPRIGHT", pvFrame, "TOPRIGHT", 0, -rawTopBarH)
    health:SetHeight(healthH)
    health:SetStatusBarTexture(texPath)
    health:GetStatusBarTexture():SetHorizTile(false)
    health:SetMinMaxValues(0, 100)
    health:SetValue(85)

    -- Full-height anchor reference (mirrors the live buttons' d.uniformRef so
    -- Uniform Icon Anchoring previews identically; see ns.RF_AnchorHost).
    local pvUniformRef = CreateFrame("Frame", nil, pvFrame)
    pvUniformRef:SetFrameLevel(health:GetFrameLevel())
    pvUniformRef:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    pvUniformRef:SetPoint("BOTTOMRIGHT", pvFrame, "BOTTOMRIGHT", 0, 0)
    health._euiUniformRef = pvUniformRef
    pvUniformRef._euiHealth = health

    -- Preview class color from the player's active spec (falls back to class)
    local previewClass
    if activeSpecKey_BM and SPEC_BY_KEY[activeSpecKey_BM] then
        previewClass = SPEC_BY_KEY[activeSpecKey_BM].classToken
    end
    if not previewClass then
        local _, pc = UnitClass("player")
        previewClass = pc
    end
    local cc = EllesmereUI.GetClassColor and EllesmereUI.GetClassColor(previewClass)
    local mode = s.healthColorMode or "class"
    local fillTex = health:GetStatusBarTexture()
    if mode == "dark" then
        local dfr, dfg, dfb, dfa = EllesmereUI.GetDarkModeFill()
        health:SetStatusBarColor(dfr, dfg, dfb, 1)
        if fillTex then fillTex:SetAlpha(dfa) end
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
        bg:SetColorTexture(EllesmereUI.GetDarkModeBg())
    elseif mode == "classic" then
        local pct = 0.85
        local r = pct < 0.5 and 1 or (1 - (pct - 0.5) * 2)
        local g = pct > 0.5 and 1 or (pct * 2)
        health:SetStatusBarColor(r, g, 0, (s.healthBarOpacity or 100) / 100)
        if fillTex then fillTex:SetAlpha(1) end
        bg:SetAllPoints()
        bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
    elseif mode == "custom" then
        local cfc = s.customFillColor or { r = 37/255, g = 193/255, b = 29/255 }
        health:SetStatusBarColor(cfc.r, cfc.g, cfc.b, (s.healthBarOpacity or 100) / 100)
        if fillTex then fillTex:SetAlpha(1) end
        bg:SetAllPoints()
        bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
    else
        if cc then
            health:SetStatusBarColor(cc.r, cc.g, cc.b, (s.healthBarOpacity or 100) / 100)
        end
        if fillTex then fillTex:SetAlpha(1) end
        bg:SetAllPoints()
        bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
    end

    -- Power bar
    if rawPowerH > 0 then
        local power = CreateFrame("StatusBar", nil, pvFrame)
        power:SetFrameLevel(pvFrame:GetFrameLevel() + 3)
        power:SetPoint("BOTTOMLEFT", pvFrame, "BOTTOMLEFT", 0, 0)
        power:SetPoint("BOTTOMRIGHT", pvFrame, "BOTTOMRIGHT", 0, 0)
        power:SetHeight(rawPowerH)
        power:SetStatusBarTexture(texPath)
        power:GetStatusBarTexture():SetHorizTile(false)
        power:SetMinMaxValues(0, 100)
        power:SetValue(72)
        local pInfo = EllesmereUI.GetPowerColor and EllesmereUI.GetPowerColor("MANA")
        if pInfo then power:SetStatusBarColor(pInfo.r, pInfo.g, pInfo.b, 1)
        else power:SetStatusBarColor(0, 0.5, 1, 1) end
        local pwBg = power:CreateTexture(nil, "BACKGROUND")
        pwBg:SetAllPoints()
        local pbc = (s.powerBgPowerColored and pInfo) or s.powerBgColor or { r=0, g=0, b=0 }
        local pbF = (s.powerBgPowerColored and pInfo) and EllesmereUI.GetPowerBgDarkenFactor() or 1
        pwBg:SetColorTexture(pbc.r * pbF, pbc.g * pbF, pbc.b * pbF, (s.powerBgDarkness or 70) / 100)
        if PP and s.powerBorderStyle and s.powerBorderStyle ~= "none" then
            local pbSize = s.powerBorderSize or 1
            if pbSize > 0 then
                local pwBdr = CreateFrame("Frame", nil, pvFrame)
                pwBdr:SetAllPoints(power)
                pwBdr:SetFrameLevel(power:GetFrameLevel() + 1)
                PP.CreateBorder(pwBdr, 0, 0, 0, 1, 1)
                local pBc = s.powerBorderColor or { r=0, g=0, b=0 }
                PP.UpdateBorder(pwBdr, pbSize, pBc.r, pBc.g, pBc.b, s.powerBorderAlpha or 1)
                local ppC = PP.GetBorders(pwBdr)
                if ppC and s.powerBorderStyle == "divider" then
                    if ppC._bottom then ppC._bottom:SetAlpha(0) end
                    if ppC._left then ppC._left:SetAlpha(0) end
                    if ppC._right then ppC._right:SetAlpha(0) end
                end
            end
        end
    end

    -- Main border
    if PP then
        local bsz = s.borderSize or 1
        if bsz > 0 then
            local bdr = CreateFrame("Frame", nil, pvFrame)
            bdr:SetAllPoints(pvFrame)
            bdr:SetFrameLevel(pvFrame:GetFrameLevel() + 8)
            PP.CreateBorder(bdr, 0, 0, 0, 1, 1)
            local bc = s.borderColor or { r=0, g=0, b=0 }
            PP.UpdateBorder(bdr, bsz, bc.r, bc.g, bc.b, s.borderAlpha or 1)
        end
    end

    -- Name text. Hosted on a carrier in the live text band (ns.LVL_TEXT) so
    -- the name draws above the +8 main border, exactly like real frames.
    local nameCarrier = CreateFrame("Frame", nil, pvFrame)
    nameCarrier:SetAllPoints(pvFrame)
    nameCarrier:SetFrameLevel(pvFrame:GetFrameLevel() + (ns.LVL_TEXT or 12))
    local nameFS = nameCarrier:CreateFontString(nil, "OVERLAY")
    local outline = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("raidFrames")) or ""
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(nameFS, outline == "" and (not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow("raidFrames"))) end
    nameFS:SetFont(fontPath, s.nameSize or 10, outline)
    nameFS:SetWordWrap(false)
    local npos = s.namePosition or "center"
    nameFS:SetShown(npos ~= "none" and not s.topNameBarEnabled)
    local nox = s.nameOffsetX or 0
    local noy = s.nameOffsetY or 0
    nameFS:SetPoint("LEFT", health, "LEFT", 2 + nox, 0)
    nameFS:SetPoint("RIGHT", health, "RIGHT", -floor(rawW * 0.25) + nox, 0)
    if npos == "topleft" then
        nameFS:SetPoint("TOP", health, "TOP", 0, -2 + noy); nameFS:SetJustifyH("LEFT"); nameFS:SetJustifyV("TOP")
    elseif npos == "top" then
        nameFS:SetPoint("TOP", health, "TOP", 0, -2 + noy); nameFS:SetJustifyH("CENTER"); nameFS:SetJustifyV("TOP")
    elseif npos == "topright" then
        nameFS:SetPoint("TOP", health, "TOP", 0, -2 + noy); nameFS:SetJustifyH("RIGHT"); nameFS:SetJustifyV("TOP")
    elseif npos == "left" then
        nameFS:SetPoint("CENTER", health, "CENTER", 0, noy); nameFS:SetJustifyH("LEFT"); nameFS:SetJustifyV("MIDDLE")
    elseif npos == "right" then
        nameFS:SetPoint("CENTER", health, "CENTER", 0, noy); nameFS:SetJustifyH("RIGHT"); nameFS:SetJustifyV("MIDDLE")
    elseif npos == "bottomleft" then
        nameFS:SetPoint("BOTTOM", health, "BOTTOM", 0, 2 + noy); nameFS:SetJustifyH("LEFT"); nameFS:SetJustifyV("BOTTOM")
    elseif npos == "bottom" then
        nameFS:SetPoint("BOTTOM", health, "BOTTOM", 0, 2 + noy); nameFS:SetJustifyH("CENTER"); nameFS:SetJustifyV("BOTTOM")
    else
        nameFS:SetPoint("CENTER", health, "CENTER", 0, noy); nameFS:SetJustifyH("CENTER"); nameFS:SetJustifyV("MIDDLE")
    end
    local playerName = UnitName("player") or "Player"
    if Ambiguate then playerName = Ambiguate(playerName, "short") end
    nameFS:SetText(playerName)
    local nameMode = s.nameColorMode or "class"
    if nameMode == "accent" then
        local ar, ag, ab = EllesmereUI.ResolveActiveAccent()
        if ar then nameFS:SetTextColor(ar, ag, ab) else nameFS:SetTextColor(1, 1, 1) end
    elseif nameMode == "custom" then
        local c = s.nameCustomColor or { r=1, g=1, b=1 }
        nameFS:SetTextColor(c.r, c.g, c.b)
    else
        if cc then nameFS:SetTextColor(cc.r, cc.g, cc.b) else nameFS:SetTextColor(1, 1, 1) end
    end

    -- Top Name Bar band (preview replica)
    if s.topNameBarEnabled then
        local tnb = CreateFrame("Frame", nil, pvFrame)
        tnb:SetFrameLevel(pvFrame:GetFrameLevel() + 4)
        tnb:SetPoint("TOPLEFT", pvFrame, "TOPLEFT", 0, 0)
        tnb:SetPoint("TOPRIGHT", pvFrame, "TOPRIGHT", 0, 0)
        tnb:SetHeight(rawTopBarH)
        local tnbBg = tnb:CreateTexture(nil, "BACKGROUND")
        tnbBg:SetAllPoints()
        local tbgc = s.topNameBarBgColor or { r=17/255, g=17/255, b=17/255 }
        tnbBg:SetColorTexture(tbgc.r, tbgc.g, tbgc.b, (s.topNameBarBgOpacity or 80) / 100)
        local tnbText = tnb:CreateFontString(nil, "OVERLAY")
        tnbText:SetFont(fontPath, s.topNameBarTextSize or 11, outline)
        tnbText:SetWordWrap(false)
        tnbText:SetText(playerName)
        local talign = s.topNameBarTextAlign or "center"
        local tox = s.topNameBarTextOffsetX or 0
        local toy = s.topNameBarTextOffsetY or 0
        if talign == "left" then
            tnbText:SetPoint("LEFT", tnb, "LEFT", 4 + tox, toy); tnbText:SetJustifyH("LEFT")
        elseif talign == "right" then
            tnbText:SetPoint("RIGHT", tnb, "RIGHT", -4 + tox, toy); tnbText:SetJustifyH("RIGHT")
        else
            tnbText:SetPoint("CENTER", tnb, "CENTER", tox, toy); tnbText:SetJustifyH("CENTER")
        end
        tnbText:SetJustifyV("MIDDLE")
        if (s.topNameBarTextColorMode or "class") == "custom" then
            local c = s.topNameBarTextColor or { r=1, g=1, b=1 }
            tnbText:SetTextColor(c.r, c.g, c.b)
        elseif cc then
            tnbText:SetTextColor(cc.r, cc.g, cc.b)
        else
            tnbText:SetTextColor(1, 1, 1)
        end
    end

    -- Health text
    local htMode = s.healthTextMode or "none"
    if htMode ~= "none" then
        local htFS = health:CreateFontString(nil, "OVERLAY")
        htFS:SetFont(fontPath, s.healthTextSize or 9, outline)
        htFS:SetTextColor(1, 1, 1, 0.9)
        local htPos = s.healthTextPosition or "center"
        local htOX = s.healthTextOffsetX or 0
        local htOY = s.healthTextOffsetY or 0
        htFS:SetWidth(rawW * 0.75); htFS:SetHeight(0)
        if htPos == "topleft" then
            htFS:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + htOX, -2 + htOY); htFS:SetJustifyH("LEFT"); htFS:SetJustifyV("TOP")
        elseif htPos == "top" then
            htFS:SetPoint("TOP", health, "TOP", htOX, -2 + htOY); htFS:SetJustifyH("CENTER"); htFS:SetJustifyV("TOP")
        elseif htPos == "topright" then
            htFS:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + htOX, -2 + htOY); htFS:SetJustifyH("RIGHT"); htFS:SetJustifyV("TOP")
        elseif htPos == "left" then
            htFS:SetPoint("LEFT", health, "LEFT", 2 + htOX, htOY); htFS:SetJustifyH("LEFT"); htFS:SetJustifyV("MIDDLE")
        elseif htPos == "right" then
            htFS:SetPoint("RIGHT", health, "RIGHT", -2 + htOX, htOY); htFS:SetJustifyH("RIGHT"); htFS:SetJustifyV("MIDDLE")
        elseif htPos == "bottomleft" then
            htFS:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + htOX, 2 + htOY); htFS:SetJustifyH("LEFT"); htFS:SetJustifyV("BOTTOM")
        elseif htPos == "bottom" then
            htFS:SetPoint("BOTTOM", health, "BOTTOM", htOX, 2 + htOY); htFS:SetJustifyH("CENTER"); htFS:SetJustifyV("BOTTOM")
        else
            htFS:SetPoint("CENTER", health, "CENTER", htOX, htOY); htFS:SetJustifyH("CENTER"); htFS:SetJustifyV("MIDDLE")
        end
        if htMode == "percent" then htFS:SetText("85%")
        elseif htMode == "percentNoSign" then htFS:SetText("85")
        elseif htMode == "number" then htFS:SetText("1.02M") end
    end

    pvFrame._health = health

    -- Example buff icons for the simple grid preview (active spec's whitelist;
    -- falls back to the first healer spec so the preview is never empty).
    local exampleIcons = {}
    local previewSpecKey = activeSpecKey_BM or (HEALER_SPECS[1] and HEALER_SPECS[1].key)
    local spec = previewSpecKey and SPEC_BY_KEY[previewSpecKey]
    if spec then
        for _, spell in ipairs(spec.spells) do
            if not spell.hide then
                exampleIcons[#exampleIcons + 1] = GetSpellIcon(spell.id)
            end
        end
    end

    -- Preview grid pool (isolated; created on this preview frame only).
    local previewIcons = {}
    local fakeD = { bmSimpleIcons = previewIcons }
    local function RefreshSimplePreview()
        local bs = s.bmSimple or {}
        local showBuffs = bs.showBuffs ~= false
        local maxB = bs.maxBuffs or 10
        local sz = bs.size or 22
        local count = (showBuffs and #exampleIcons > 0) and min(maxB, #exampleIcons) or 0
        for i = 1, count do
            local icon = previewIcons[i]
            if not icon then
                icon = CreateFrame("Frame", nil, health)
                icon:SetFrameLevel(health:GetFrameLevel() + 6)
                local tex = icon:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints(); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                icon._tex = tex
                local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
                cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetReverse(true)
                cd:SetSwipeColor(0, 0, 0, 0.6); cd:SetHideCountdownNumbers(true)
                cd:Hide()
                icon._cooldown = cd
                if PP then
                    local b = CreateFrame("Frame", nil, icon)
                    b:SetAllPoints(); b:SetFrameLevel(icon:GetFrameLevel() + 1)
                    PP.CreateBorder(b, 0, 0, 0, 1, 1)
                    icon._borderFrame = b
                end
                -- Carrier frame above the cooldown swipe/border so the stack
                -- count preview isn't hidden behind them (mirrors the live
                -- grid's _textCarrier in ns.BM_CreateIndicators).
                local textCarrier = CreateFrame("Frame", nil, icon)
                textCarrier:SetAllPoints()
                textCarrier:SetFrameLevel(icon:GetFrameLevel() + 5)
                local countFS = textCarrier:CreateFontString(nil, "OVERLAY")
                countFS:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
                icon._count = countFS
                previewIcons[i] = icon
            end
            icon:SetSize(sz, sz)
            icon._tex:SetTexture(exampleIcons[i] or 136243)
            local _z = bs.iconZoom or 0.08
            icon._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)
            if icon._borderFrame and PP then
                local bdrSz = bs.borderSize or 1
                local bc = bs.borderColor or { r=0, g=0, b=0 }
                if bdrSz > 0 then
                    PP.UpdateBorder(icon._borderFrame, bdrSz, bc.r, bc.g, bc.b, 1)
                    icon._borderFrame:Show()
                else
                    icon._borderFrame:Hide()
                end
            end
            -- Duration swipe + text preview (faked duration so those controls show).
            local cd = icon._cooldown
            if cd then
                local wantSwipe = bs.showSwipe ~= false
                local wantDurText = bs.showDurText
                if wantSwipe or wantDurText then
                    cd:SetCooldown(GetTime(), 24)
                    cd:SetDrawSwipe(wantSwipe)
                    cd:SetHideCountdownNumbers(not wantDurText)
                    cd:Show()
                    if wantDurText then
                        local cdText = cd.GetCountdownFontString and cd:GetCountdownFontString()
                        if cdText then
                            local dtc = bs.durTextColor or { r=1, g=1, b=1 }
                            EllesmereUI.ApplyIconTextFont(cdText, fontPath, bs.durTextSize or 8, "raidFrames")
                            cdText:SetTextColor(dtc.r, dtc.g, dtc.b)
                            cdText:ClearAllPoints()
                            cdText:SetPoint("CENTER", icon, "CENTER", bs.durTextOffsetX or 0, bs.durTextOffsetY or 0)
                        end
                    end
                else
                    cd:Hide()
                end
            end
            -- Stack count preview (fake example count so the color/size/offset
            -- controls have something visible to preview against).
            if icon._count then
                if bs.showStacks then
                    local sc = bs.stacksTextColor or { r = 1, g = 1, b = 1 }
                    EllesmereUI.ApplyIconTextFont(icon._count, fontPath, bs.stacksTextSize or 8, "raidFrames")
                    icon._count:SetTextColor(sc.r, sc.g, sc.b)
                    icon._count:ClearAllPoints()
                    icon._count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT",
                        bs.stacksOffsetX or -1, bs.stacksOffsetY or 2)
                    icon._count:SetText("3")
                else
                    icon._count:SetText("")
                end
            end
            icon:Show()
        end
        for i = count + 1, #previewIcons do
            if previewIcons[i]._cooldown then previewIcons[i]._cooldown:Hide() end
            previewIcons[i]:Hide()
        end
        ns.BM_AnchorSimpleGrid(fakeD, ns.RF_AnchorHost(health, s), bs, 1, count)
    end
    RefreshSimplePreview()

    return pvFrame, sectionH, RefreshSimplePreview
end

function ns.BM_BuildPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    if not W then return 0 end
    local db = ns.db
    if not db then return 0 end
    -- Override-session gate: heals a stale Buff Manager layer FIRST (so the
    -- page content below renders the edited group's fork) and reports the
    -- full-page overlay to build at the end. nil = normal WYSIWYG page.
    local bmOverlayState = EllesmereUI.SpecOverrides_BmPagePrelude
        and EllesmereUI.SpecOverrides_BmPagePrelude() or nil
    local PP = EllesmereUI.PanelPP

    -- Auto-detect spec on first open
    if not selectedSpecKey then
        selectedSpecKey = AutoDetectSpec()
    end

    -- Light update: rebuild lookup + refresh real frames + refresh BM preview.
    -- No page rebuild. Used by sliders and settings that don't change page structure.
    local function ReloadAndUpdate()
        RebuildLookup(db)
        if ns.ReloadFrames then ns.ReloadFrames() end
        -- Refresh the inline BM preview
        local pv = ns._bmPreviewFrame
        if pv and pv._health and ns.BM_ApplyPreviewIndicators then
            ns.BM_ApplyPreviewIndicators(pv, 1, db.profile)
        end
    end

    -- Full update: also rebuilds the page (preview, sidebar, settings).
    -- Used by create, delete, toggle, dropdown changes that alter structure.
    local function ReloadAndRebuild()
        RebuildLookup(db)
        if ns.ReloadFrames then ns.ReloadFrames() end
        EllesmereUI:RefreshPage(true)
    end

    -- Inline cog on each indicator's Own Only control: per-indicator
    -- Show Own on All Specs (the indicator keeps rendering the player's own
    -- casts on every spec of the class, bypassing the borrow restriction).
    local function AttachOwnAllSpecsCog(rgn, ind)
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Own Only",
            rows = {
                { type = "toggle", label = "Show Own on All Specs",
                  tooltip = "Show this indicator's buffs on every spec of your class, not only this spec.",
                  get = function() return ind.showOwnAllSpecs == true end,
                  set = function(v)
                      ind.showOwnAllSpecs = v and true or false
                      ReloadAndUpdate()
                  end },
            },
        })
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
        cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        rgn._lastInline = cogBtn
    end

    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    local _, h
    local PAD = 20  -- consistent left/right padding for creation bar + settings
    local s = db.profile

    -- Get current spec's indicators for the sidebar
    local specIndicators = selectedSpecKey and GetSpecIndicators(db, selectedSpecKey) or {}

    -- Validate selected indicator
    if not selectedIndicator and #specIndicators > 0 then
        selectedIndicator = specIndicators[1]
    end
    if selectedIndicator then
        local found = false
        for _, ind in ipairs(specIndicators) do
            if ind.id == selectedIndicator.id then found = true; break end
        end
        if not found then selectedIndicator = specIndicators[1] or nil end
    end

    -- Expose selected spec + indicator ID for preview logic
    ns._bmSelectedSpecKey = selectedSpecKey
    ns._bmSelectedIndId = selectedIndicator and selectedIndicator.id or nil

    -------------------------------------------------------------------
    --  FIXED LAYOUT: fills visible area, no outer scroll.
    --  Left column (72%): creation + preview (fixed) + settings (scroll)
    --  Right sidebar (28%): full height, own scroll, dark background
    -------------------------------------------------------------------
    -- Build directly on the scroll frame (not the scroll child) so
    -- the content is fixed and non-scrollable. No outer scrollbar.
    local scrollFrame = EllesmereUI._scrollFrame
    if not scrollFrame then return 0 end

    local parentW = scrollFrame:GetWidth()
    local fullH = scrollFrame:GetHeight()
    local sidebarW = floor(parentW * 0.28)
    local leftW = parentW - sidebarW

    -- Outer container: parented to scrollFrame, fills entire viewport
    local outerRoot = CreateFrame("Frame", nil, scrollFrame)
    outerRoot:SetAllPoints(scrollFrame)
    outerRoot:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)

    -- Store reference so we can clean up on page switch
    if ns._bmRoot then ns._bmRoot:Hide(); ns._bmRoot:SetParent(nil) end
    if ns._addNewPopup then ns._addNewPopup:Hide() end
    ns._bmRoot = outerRoot

    -- Override-session full-page overlay (state decided by the prelude at
    -- the top). "activate" offers to fork a custom Buff Manager for the
    -- edited override group; "info" explains why editing here is blocked
    -- (edits would land in whatever layer is actually live and be banked
    -- to the wrong owner at the next harvest). Built BEFORE the page
    -- content on purpose: the Simple Setup branch returns early and must
    -- still be covered. High frame level keeps it above everything built
    -- below; child of outerRoot so every teardown path destroys it.
    if bmOverlayState then
        local st = bmOverlayState
        local ov = CreateFrame("Frame", nil, outerRoot)
        ov:SetAllPoints(outerRoot)
        ov:SetFrameLevel(outerRoot:GetFrameLevel() + 60)
        ov:EnableMouse(true)
        ov._searchIgnore = true
        local bg = ov:CreateTexture(nil, "OVERLAY")
        bg:SetAllPoints()
        bg:SetColorTexture(13/255, 17/255, 25/255, 0.98)
        local title = ov:CreateFontString(nil, "OVERLAY")
        title:SetFont(fontPath, 15, "")
        title:SetPoint("CENTER", ov, "CENTER", 0, 60)
        title:SetTextColor(1, 1, 1, 0.9)
        title:SetText(EllesmereUI.L("Custom Buff Manager"))
        local body = ov:CreateFontString(nil, "OVERLAY")
        body:SetFont(fontPath, 13, "")
        body:SetPoint("TOP", title, "BOTTOM", 0, -14)
        body:SetWidth(floor(parentW * 0.7))
        body:SetJustifyH("CENTER")
        body:SetTextColor(1, 1, 1, 0.56)
        body:SetText(st.text or "")
        local sub
        if st.sub then
            sub = ov:CreateFontString(nil, "OVERLAY")
            sub:SetFont(fontPath, 12, "")
            sub:SetPoint("TOP", body, "BOTTOM", 0, -8)
            sub:SetWidth(floor(parentW * 0.7))
            sub:SetJustifyH("CENTER")
            sub:SetTextColor(1, 1, 1, 0.45)
            sub:SetText(st.sub)
        end
        if st.mode == "activate" then
            local btn = CreateFrame("Button", nil, ov)
            btn:SetSize(240, 28)
            btn:SetPoint("TOP", sub or body, "BOTTOM", 0, -22)
            EllesmereUI.SolidTex(btn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
            local brd = EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.22)
            local lbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1, 0.85)
            lbl:SetPoint("CENTER")
            lbl:SetText(EllesmereUI.L("Activate Custom Buff Manager"))
            local eg = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.83, b = 0.62 }
            btn:SetScript("OnEnter", function()
                if brd and brd.SetColor then brd:SetColor(eg.r, eg.g, eg.b, 0.9) end
            end)
            btn:SetScript("OnLeave", function()
                if brd and brd.SetColor then brd:SetColor(1, 1, 1, 0.22) end
            end)
            btn:SetScript("OnClick", function()
                if EllesmereUI.SpecOverrides_ActivateBm then
                    EllesmereUI.SpecOverrides_ActivateBm(st.kind, st.gid)
                end
            end)
        end
    end

    -------------------------------------------------------------------
    --  BUFF DISPLAY MODE HEADER (always visible)
    --  Segmented toggle swaps between the full custom buff manager and a
    --  simpler setup page. The mode is stored per-profile; switching rebuilds
    --  the page (same RefreshPage model the rest of the page uses).
    -------------------------------------------------------------------
    local HEADER_H = 80
    local displayMode = (s.bmDisplayMode == "simple") and "simple" or "custom"

    do
        local card = CreateFrame("Frame", nil, outerRoot)
        card:SetPoint("TOPLEFT", outerRoot, "TOPLEFT", 0, 0)
        card:SetPoint("TOPRIGHT", outerRoot, "TOPRIGHT", 0, 0)
        card:SetHeight(HEADER_H - 16)
        card:SetFrameLevel(outerRoot:GetFrameLevel() + 2)
        local cardBg = card:CreateTexture(nil, "BACKGROUND")
        cardBg:SetAllPoints()
        cardBg:SetColorTexture(1, 1, 1, 0.02)
        if PP then PP.CreateBorder(card, 1, 1, 1, 0.08, 1) end

        local title = card:CreateFontString(nil, "OVERLAY")
        title:SetFont(fontPath, 15, "")
        title:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -16)
        title:SetText(EllesmereUI.L("Buff Display Mode"))
        title:SetTextColor(1, 1, 1, 0.95)

        local desc = card:CreateFontString(nil, "OVERLAY")
        desc:SetFont(fontPath, 12, "")
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        desc:SetText(EllesmereUI.L("Choose how buffs are displayed on raid frames."))
        desc:SetTextColor(1, 1, 1, 0.5)

        -- Segmented two-button toggle (active = green, inactive = dark).
        local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
        local BTN_W, BTN_H = 162, 31
        local toggleWrap = CreateFrame("Frame", nil, card)
        toggleWrap:SetSize(BTN_W * 2, BTN_H)
        toggleWrap:SetPoint("RIGHT", card, "RIGHT", -16, 0)
        toggleWrap:SetFrameLevel(card:GetFrameLevel() + 1)
        if PP then PP.CreateBorder(toggleWrap, 1, 1, 1, 0.10, 1) end

        local MODES = { { key = "simple", label = "Simple Setup" }, { key = "custom", label = "Custom Buff Display" } }
        for i, m in ipairs(MODES) do
            local btn = CreateFrame("Button", nil, toggleWrap)
            btn:SetSize(BTN_W, BTN_H)
            btn:SetPoint("LEFT", toggleWrap, "LEFT", (i - 1) * BTN_W, 0)
            local active = (displayMode == m.key)
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            local lbl = btn:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(fontPath, 13, "")
            lbl:SetPoint("CENTER")
            lbl:SetText(EllesmereUI.L(m.label))
            if active then
                bg:SetColorTexture(EG.r, EG.g, EG.b, 0.85)
                lbl:SetTextColor(1, 1, 1, 1)
            else
                bg:SetColorTexture(0.10, 0.10, 0.11, 0.85)
                lbl:SetTextColor(1, 1, 1, 0.55)
                btn:SetScript("OnEnter", function() bg:SetColorTexture(0.16, 0.16, 0.17, 0.9); lbl:SetTextColor(1, 1, 1, 0.85) end)
                btn:SetScript("OnLeave", function() bg:SetColorTexture(0.10, 0.10, 0.11, 0.85); lbl:SetTextColor(1, 1, 1, 0.55) end)
                btn:SetScript("OnClick", function()
                    s.bmDisplayMode = m.key
                    -- Re-render live frames so the buff display swaps modes now.
                    if ns.ReloadFrames then ns.ReloadFrames() end
                    EllesmereUI:RefreshPage(true)
                end)
            end
        end

        -- Centered active-override indicator: everything on this page edits
        -- THAT group's custom Buff Manager, not the default one.
        local ovName = EllesmereUI.SpecOverrides_BmActiveInfo
            and EllesmereUI.SpecOverrides_BmActiveInfo()
        if ovName then
            local ovTop = card:CreateFontString(nil, "OVERLAY")
            ovTop:SetFont(fontPath, 11, "")
            ovTop:SetPoint("CENTER", card, "CENTER", 0, 10)
            ovTop:SetText(EllesmereUI.L("Override Active:"))
            ovTop:SetTextColor(1, 1, 1, 0.6)
            local ovBottom = card:CreateFontString(nil, "OVERLAY")
            ovBottom:SetFont(fontPath, 13, "")
            ovBottom:SetPoint("CENTER", card, "CENTER", 0, -7)
            ovBottom:SetText(ovName)
            local ar, ag, ab = 1, 0.82, 0.30
            if EllesmereUI.GetAccentColor then ar, ag, ab = EllesmereUI.GetAccentColor() end
            ovBottom:SetTextColor(ar, ag, ab, 1)
        end
    end

    if displayMode == "simple" then
        -- The custom indicator preview frame is not used in simple mode.
        ns._bmPreviewFrame = nil

        local bs = s.bmSimple
        if not bs then bs = {}; s.bmSimple = bs end

        -- Content root below the header (full width; simple mode has no sidebar).
        local root = CreateFrame("Frame", nil, outerRoot)
        root:SetPoint("TOPLEFT", outerRoot, "TOPLEFT", 0, -HEADER_H)
        root:SetPoint("BOTTOMRIGHT", outerRoot, "BOTTOMRIGHT", 0, 0)
        root:SetFrameLevel(outerRoot:GetFrameLevel() + 1)

        -- Preview (health-bar replica + live simple grid; no spec picker).
        local PREVIEW_TOP = -16
        local _pv, pvSectionH, RefreshSimplePreview =
            ns.BM_BuildSimplePreview(root, s, fontPath, PP, parentW / 2, PREVIEW_TOP)

        -- Isolated get/set helpers (read/write db.profile.bmSimple only).
        local function BVal(key, default) local v = bs[key]; if v == nil then return default end; return v end
        local function BApply()
            if ns.ReloadFrames then ns.ReloadFrames() end
            if RefreshSimplePreview then RefreshSimplePreview() end
        end
        local function BSet(key, v) bs[key] = v; BApply() end
        local function BuffsOff() return not (bs.showBuffs ~= false) end

        local function GetDefaultGrow(pos)
            if pos == "right" or pos == "topright" or pos == "bottomright" then return "LEFT" end
            if pos == "left" or pos == "topleft" or pos == "bottomleft" then return "RIGHT" end
            if pos == "top" then return "DOWN" end
            if pos == "bottom" then return "UP" end
            return "CENTER"
        end

        local POS_VALUES = { topleft="Top Left", top="Top", topright="Top Right", left="Left",
            center="Center", right="Right", bottomleft="Bottom Left", bottom="Bottom", bottomright="Bottom Right" }
        local POS_ORDER = { "topleft","top","topright","left","center","right","bottomleft","bottom","bottomright" }
        local GROW_VALUES = { RIGHT="Right", LEFT="Left", UP="Up", DOWN="Down", CENTER="Center" }
        local GROW_ORDER = { "RIGHT","LEFT","UP","DOWN","CENTER" }

        -- Options below the preview.
        local PADX = 20
        local optsFrame = CreateFrame("Frame", nil, root)
        optsFrame:SetPoint("TOPLEFT", root, "TOPLEFT", PADX, PREVIEW_TOP - pvSectionH - 4)
        optsFrame:SetPoint("TOPRIGHT", root, "TOPRIGHT", -PADX, PREVIEW_TOP - pvSectionH - 4)
        optsFrame:SetHeight(400)
        optsFrame._showRowDivider = true

        local sy, hh = 0, 0

        -- Row: Show Buffs | Max Buffs
        _, hh = W:DualRow(optsFrame, sy,
            { type="toggle", text="Show Buffs",
              getValue=function() return bs.showBuffs ~= false end,
              setValue=function(v) bs.showBuffs = v; BApply(); EllesmereUI:RefreshPage() end },
            { type="slider", text="Max Buffs", min=1, max=10, step=1,
              disabled=BuffsOff, disabledTooltip="Show Buffs",
              getValue=function() return BVal("maxBuffs", 10) end,
              setValue=function(v) BSet("maxBuffs", v) end });  sy = sy - hh

        _, hh = W:SectionHeader(optsFrame, "BUFF DISPLAY", sy);  sy = sy - hh

        -- Row 1: Icons Per Row | Position (+ offset cog)
        local row1
        row1, hh = W:DualRow(optsFrame, sy,
            { type="slider", text="Icons Per Row", min=1, max=8, step=1,
              disabled=BuffsOff, disabledTooltip="Show Buffs",
              getValue=function() return BVal("iconsPerRow", 4) end,
              setValue=function(v) BSet("iconsPerRow", v) end },
            { type="dropdown", text="Position", values=POS_VALUES, order=POS_ORDER,
              disabled=BuffsOff, disabledTooltip="Show Buffs",
              getValue=function() return BVal("position", "topright") end,
              setValue=function(v)
                  bs.position = v
                  bs.growDirection = GetDefaultGrow(v)
                  BApply()
                  EllesmereUI:RefreshPage()
              end });  sy = sy - hh
        do
            local rgn = row1._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Buff Offset",
                rows = {
                    { type="slider", label="Offset X", min=-50, max=50, step=1,
                      get=function() return BVal("offsetX", 0) end, set=function(v) BSet("offsetX", v) end },
                    { type="slider", label="Offset Y", min=-50, max=50, step=1,
                      get=function() return BVal("offsetY", 0) end, set=function(v) BSet("offsetY", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            local function UpdCog() local off = BuffsOff(); cogBtn:SetAlpha(off and 0.15 or 0.4); cogBtn:EnableMouse(not off) end
            cogBtn:SetScript("OnEnter", function(self) if not BuffsOff() then self:SetAlpha(0.7) end end)
            cogBtn:SetScript("OnLeave", function(self) UpdCog() end)
            cogBtn:SetScript("OnClick", function(self) if not BuffsOff() then cogShow(self) end end)
            UpdCog(); EllesmereUI.RegisterWidgetRefresh(UpdCog)
        end

        -- Row 2: Growth Direction | Size (+ icon zoom cog)
        local row2
        row2, hh = W:DualRow(optsFrame, sy,
            { type="dropdown", text="Growth Direction", values=GROW_VALUES, order=GROW_ORDER,
              disabled=BuffsOff, disabledTooltip="Show Buffs",
              getValue=function() return BVal("growDirection", "LEFT") end,
              setValue=function(v) BSet("growDirection", v) end },
            { type="slider", text="Size", min=10, max=40, step=1,
              disabled=BuffsOff, disabledTooltip="Show Buffs",
              getValue=function() return BVal("size", 22) end,
              setValue=function(v) BSet("size", v) end });  sy = sy - hh
        do
            local rgn = row2._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Icon Zoom",
                rows = {
                    { type="slider", label="Zoom", min=0, max=0.20, step=0.01,
                      get=function() return BVal("iconZoom", 0.08) end,
                      set=function(v) BSet("iconZoom", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
            local function UpdCog() local off = BuffsOff(); cogBtn:SetAlpha(off and 0.15 or 0.4); cogBtn:EnableMouse(not off) end
            cogBtn:SetScript("OnEnter", function(self) if not BuffsOff() then self:SetAlpha(0.7) end end)
            cogBtn:SetScript("OnLeave", function(self) UpdCog() end)
            cogBtn:SetScript("OnClick", function(self) if not BuffsOff() then cogShow(self) end end)
            UpdCog(); EllesmereUI.RegisterWidgetRefresh(UpdCog)
        end

        -- Row 3: Spacing | Border Size (+ swatch)
        local row3
        row3, hh = W:DualRow(optsFrame, sy,
            { type="slider", pixel=true, text="Spacing", min=-1, max=10, step=1,
              disabled=BuffsOff, disabledTooltip="Show Buffs",
              getValue=function() return BVal("spacing", 1) end,
              setValue=function(v) BSet("spacing", v) end },
            { type="slider", text="Border Size", min=0, max=4, step=1, trackWidth=120,
              disabled=BuffsOff, disabledTooltip="Show Buffs",
              getValue=function() return BVal("borderSize", 1) end,
              setValue=function(v) BSet("borderSize", v) end });  sy = sy - hh
        do
            local rgn = row3._rightRegion
            local swatch = EllesmereUI.BuildColorSwatch(rgn, row3:GetFrameLevel() + 3,
                function() local c = bs.borderColor or { r=0, g=0, b=0 }; return c.r, c.g, c.b, 1 end,
                function(r, g, b) bs.borderColor = { r=r, g=g, b=b }; BApply() end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
        end

        -- Row 4: Show Duration Swipe | Show Duration Text (+ swatch + cog)
        local row4
        row4, hh = W:DualRow(optsFrame, sy,
            { type="toggle", text="Show Duration Swipe",
              disabled=BuffsOff, disabledTooltip="Show Buffs",
              getValue=function() return BVal("showSwipe", true) end,
              setValue=function(v) BSet("showSwipe", v) end },
            { type="toggle", text="Show Duration Text",
              disabled=BuffsOff, disabledTooltip="Show Buffs",
              getValue=function() return BVal("showDurText", false) end,
              setValue=function(v) BSet("showDurText", v) end });  sy = sy - hh
        do
            local rgn = row4._rightRegion
            local swatch = EllesmereUI.BuildColorSwatch(rgn, row4:GetFrameLevel() + 3,
                function() local c = bs.durTextColor or { r=1, g=1, b=1 }; return c.r, c.g, c.b, 1 end,
                function(r, g, b) bs.durTextColor = { r=r, g=g, b=b }; BApply() end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch

            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Duration Text",
                rows = {
                    { type="slider", label="Text Size", min=6, max=26, step=1,
                      get=function() return BVal("durTextSize", 8) end, set=function(v) BSet("durTextSize", v) end },
                    { type="slider", label="Offset X", min=-20, max=20, step=1,
                      get=function() return BVal("durTextOffsetX", 0) end, set=function(v) BSet("durTextOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-20, max=20, step=1,
                      get=function() return BVal("durTextOffsetY", 0) end, set=function(v) BSet("durTextOffsetY", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end

        -- Row 5: Show Stacks (+ swatch + cog)
        local row5
        row5, hh = W:DualRow(optsFrame, sy,
            { type="toggle", text="Show Stacks",
              disabled=BuffsOff, disabledTooltip="Show Buffs",
              getValue=function() return BVal("showStacks", true) end,
              setValue=function(v) BSet("showStacks", v) end },
            { type="toggle", text="Own Only", tooltip="Shows only the buffs you apply",
              disabled=BuffsOff, disabledTooltip="Show Buffs",
              getValue=function() return BVal("ownOnly", true) end,
              setValue=function(v) BSet("ownOnly", v) end });  sy = sy - hh
        do
            local rgn = row5._leftRegion
            local swatch = EllesmereUI.BuildColorSwatch(rgn, row5:GetFrameLevel() + 3,
                function() local c = bs.stacksTextColor or { r=1, g=1, b=1 }; return c.r, c.g, c.b, 1 end,
                function(r, g, b) bs.stacksTextColor = { r=r, g=g, b=b }; BApply() end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch

            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Stacks Text",
                rows = {
                    { type="slider", label="Text Size", min=6, max=26, step=1,
                      get=function() return BVal("stacksTextSize", 8) end, set=function(v) BSet("stacksTextSize", v) end },
                    { type="slider", label="Offset X", min=-20, max=20, step=1,
                      get=function() return BVal("stacksOffsetX", -1) end, set=function(v) BSet("stacksOffsetX", v) end },
                    { type="slider", label="Offset Y", min=-20, max=20, step=1,
                      get=function() return BVal("stacksOffsetY", 2) end, set=function(v) BSet("stacksOffsetY", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            local function UpdateStacksCog()
                local off = BuffsOff() or not BVal("showStacks", true)
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                cogBtn:EnableMouse(not off)
            end
            cogBtn:SetScript("OnEnter", function(self) if not (BuffsOff() or not BVal("showStacks", true)) then self:SetAlpha(0.7) end end)
            cogBtn:SetScript("OnLeave", function(self) UpdateStacksCog() end)
            cogBtn:SetScript("OnClick", function(self) if not (BuffsOff() or not BVal("showStacks", true)) then cogShow(self) end end)
            UpdateStacksCog()
            EllesmereUI.RegisterWidgetRefresh(UpdateStacksCog)
        end

        -- Row 6: Show Own on All Specs | (empty)
        _, hh = W:DualRow(optsFrame, sy,
            { type="toggle", text="Show Own on All Specs",
              tooltip="Show your own class buffs on every spec, not only on the tracked healer spec.",
              disabled=BuffsOff, disabledTooltip="Show Buffs",
              getValue=function() return BVal("showOwnAllSpecs", false) end,
              setValue=function(v)
                  bs.showOwnAllSpecs = v and true or false
                  -- The simple whitelist is spec-resolved inside the lookup
                  -- build, so the toggle re-runs it before the re-render.
                  if ns.BM_RebuildLookup then ns.BM_RebuildLookup(ns.db) end
                  BApply()
              end },
            { type="label", text="" });  sy = sy - hh

        return 0
    end

    -- Custom Buff Display: the full buff manager builds into the content area
    -- below the header. Existing layout below uses `root` + `visibleH`.
    local root = CreateFrame("Frame", nil, outerRoot)
    root:SetPoint("TOPLEFT", outerRoot, "TOPLEFT", 0, -HEADER_H)
    root:SetPoint("BOTTOMRIGHT", outerRoot, "BOTTOMRIGHT", 0, 0)
    root:SetFrameLevel(outerRoot:GetFrameLevel() + 1)
    local visibleH = fullH - HEADER_H

    -------------------------------------------------------------------
    --  RIGHT SIDEBAR (full visible height, own scroll, dark bg)
    -------------------------------------------------------------------
    local sidebarOuter = CreateFrame("Frame", nil, root)
    sidebarOuter:SetSize(sidebarW, visibleH)
    sidebarOuter:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -1)
    sidebarOuter:SetFrameLevel(root:GetFrameLevel() + 1)

    -- Background on the outer container (renders behind the scroll frame and its child)
    local sbBg = sidebarOuter:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints()
    sbBg:SetColorTexture(0, 0, 0, 0.25)

    -- Sidebar scroll frame
    local sidebarScroll = CreateFrame("ScrollFrame", nil, sidebarOuter)
    sidebarScroll:SetAllPoints()
    sidebarScroll:SetFrameLevel(sidebarOuter:GetFrameLevel() + 1)

    local sidebarChild = CreateFrame("Frame", nil, sidebarScroll)
    sidebarChild:SetWidth(sidebarW)
    sidebarScroll:SetScrollChild(sidebarChild)

    sidebarScroll:EnableMouseWheel(true)
    sidebarScroll:SetScript("OnMouseWheel", function(self, delta)
        local scroll = self:GetVerticalScroll()
        local maxS = max(0, sidebarChild:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(max(0, min(maxS, scroll - delta * 30)))
    end)

    local sidebarFrame = sidebarChild  -- alias for tile building code below

    local TILE_H = 66
    local ICON_SZ = 36
    local tileY = 0
    for _, ind in ipairs(specIndicators) do
        local tile = CreateFrame("Button", nil, sidebarFrame)
        tile:SetSize(sidebarW, TILE_H)
        tile:SetPoint("TOPLEFT", sidebarFrame, "TOPLEFT", 0, tileY)
        tile:SetFrameLevel(sidebarFrame:GetFrameLevel() + 1)

        -- Tile background
        local tileBg = tile:CreateTexture(nil, "BACKGROUND")
        tileBg:SetAllPoints()
        local isSelected = selectedIndicator and selectedIndicator.id == ind.id
        tileBg:SetColorTexture(1, 1, 1, isSelected and 0.06 or 0)

        -- Selected accent bar on left edge
        if isSelected then
            local accent = tile:CreateTexture(nil, "ARTWORK", nil, 2)
            accent:SetSize(2, TILE_H)
            accent:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
            local ac = EllesmereUI.ELLESMERE_GREEN
            if ac then
                accent:SetColorTexture(ac.r, ac.g, ac.b, 1)
            else
                accent:SetColorTexture(0.05, 0.82, 0.62, 1)
            end
        end

        -- Spell icon (left side, top-aligned with title text)
        local iconFrame = CreateFrame("Frame", nil, tile)
        iconFrame:SetSize(ICON_SZ, ICON_SZ)
        iconFrame:SetPoint("TOPLEFT", tile, "TOPLEFT", 8, -8)
        iconFrame:SetFrameLevel(tile:GetFrameLevel() + 1)

        local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if ind.spells and #ind.spells > 0 then
            iconTex:SetTexture(GetSpellIcon(ind.spells[1]))
        else
            iconTex:SetTexture(136243)
        end

        -- Icon border
        if PP then
            local iconBdr = CreateFrame("Frame", nil, iconFrame)
            iconBdr:SetAllPoints()
            iconBdr:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
            PP.CreateBorder(iconBdr, 0, 0, 0, 0.6, 1)
        end

        -- Middle text area
        local textX = 8 + ICON_SZ + 8
        local textRight = -52  -- room for toggle + delete

        -- Title: indicator type name + position subtitle
        local typeName = INDICATOR_TYPE_MAP[ind.type] and INDICATOR_TYPE_MAP[ind.type].name or ind.type
        local titleFS = tile:CreateFontString(nil, "OVERLAY")
        titleFS:SetPoint("TOPLEFT", tile, "TOPLEFT", textX, -8)
        titleFS:SetFont(fontPath, 13, "")
        titleFS:SetJustifyH("LEFT")
        titleFS:SetWordWrap(false)
        titleFS:SetText(EllesmereUI.L(typeName))
        titleFS:SetTextColor(1, 1, 1)

        -- Position subtitle (smaller, grayer, inline after type name)
        local typeInfo2 = INDICATOR_TYPE_MAP[ind.type]
        if typeInfo2 and typeInfo2.placed and ind.position then
            local posText = POSITION_VALUES[ind.position] or ind.position
            local posFS = tile:CreateFontString(nil, "OVERLAY")
            posFS:SetPoint("LEFT", titleFS, "RIGHT", 4, 0)
            posFS:SetPoint("RIGHT", tile, "RIGHT", textRight, 0)
            posFS:SetFont(fontPath, 11, "")
            posFS:SetJustifyH("LEFT")
            posFS:SetWordWrap(false)
            posFS:SetText("(" .. EllesmereUI.L(posText) .. ")")
            posFS:SetTextColor(0.75, 0.75, 0.75, 0.65)
        end

        -- Spell names (all spells, 11px)
        local spellFS = tile:CreateFontString(nil, "OVERLAY")
        spellFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -4)
        spellFS:SetPoint("RIGHT", tile, "RIGHT", textRight, 0)
        spellFS:SetFont(fontPath, 11, "")
        spellFS:SetJustifyH("LEFT")
        spellFS:SetWordWrap(false)
        if ind.spells and #ind.spells > 0 then
            local names = {}
            for _, sid in ipairs(ind.spells) do
                names[#names + 1] = SPELL_NAME_BY_ID[sid] or tostring(sid)
            end
            spellFS:SetText(table.concat(names, ", "))
        else
            spellFS:SetText(EllesmereUI.L("(no spells)"))
        end
        spellFS:SetTextColor(0.4, 0.4, 0.4)

        -- Right side controls

        -- Enable/disable toggle (styled pill toggle)
        local toggleW, toggleH = 32, 16
        local toggleBtn = CreateFrame("Button", nil, tile)
        toggleBtn:SetSize(toggleW, toggleH)
        toggleBtn:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -8, -8)
        toggleBtn:SetFrameLevel(tile:GetFrameLevel() + 2)

        local toggleBg = toggleBtn:CreateTexture(nil, "BACKGROUND")
        toggleBg:SetAllPoints()

        local toggleKnob = toggleBtn:CreateTexture(nil, "ARTWORK")
        toggleKnob:SetSize(toggleH - 4, toggleH - 4)

        local function UpdateToggleVisual()
            toggleKnob:ClearAllPoints()
            if ind.enabled then
                local acr, acg, acb = EllesmereUI.ResolveActiveAccent()
                toggleBg:SetColorTexture(acr, acg, acb, 1)
                toggleKnob:SetPoint("RIGHT", toggleBtn, "RIGHT", -2, 0)
                toggleKnob:SetColorTexture(1, 1, 1, 1)
            else
                toggleBg:SetColorTexture(0.25, 0.25, 0.25, 1)
                toggleKnob:SetPoint("LEFT", toggleBtn, "LEFT", 2, 0)
                toggleKnob:SetColorTexture(0.5, 0.5, 0.5, 1)
            end
        end
        UpdateToggleVisual()

        toggleBtn:SetScript("OnClick", function()
            ind.enabled = not ind.enabled
            UpdateToggleVisual()
            RebuildLookup(db)
            if ns.ReloadFrames then ns.ReloadFrames() end
            EllesmereUI:RefreshPage(true)
        end)

        -- Delete button (common-icon-delete, desaturated, 25% black vertex)
        local delBtn = CreateFrame("Button", nil, tile)
        delBtn:SetSize(16, 16)
        delBtn:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -8, 6)
        delBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
        local delTex = delBtn:CreateTexture(nil, "OVERLAY")
        delTex:SetAllPoints()
        delTex:SetAtlas("common-icon-delete")
        delTex:SetDesaturated(true)
        delTex:SetVertexColor(0.75, 0.75, 0.75)
        delBtn:SetAlpha(0.5)
        delBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
        delBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
        delBtn:SetScript("OnClick", function()
            local spellName = ind.spells and #ind.spells > 0
                and (SPELL_NAME_BY_ID[ind.spells[1]] or tostring(ind.spells[1]))
                or "this indicator"
            EllesmereUI:ShowConfirmPopup({
                title = "Delete Indicator",
                message = "Are you sure you want to delete the indicator for " .. spellName .. "?",
                confirmText = "Delete",
                cancelText = "Cancel",
                onConfirm = function()
                    local list = GetSpecIndicators(db, selectedSpecKey)
                    for i = #list, 1, -1 do
                        if list[i].id == ind.id then tremove(list, i); break end
                    end
                    if selectedIndicator and selectedIndicator.id == ind.id then
                        selectedIndicator = nil
                    end
                    RebuildLookup(db)
                    if ns.ReloadFrames then ns.ReloadFrames() end
                    EllesmereUI:RefreshPage(true)
                end,
            })
        end)

        -- Click tile to select
        tile:SetScript("OnClick", function()
            selectedIndicator = ind
            EllesmereUI:RefreshPage(true)
        end)

        -- Hover highlight
        tile:SetScript("OnEnter", function()
            if not isSelected then tileBg:SetColorTexture(1, 1, 1, 0.04) end
        end)
        tile:SetScript("OnLeave", function()
            if not isSelected then tileBg:SetColorTexture(1, 1, 1, 0) end
        end)

        -- Thin separator line at bottom of tile
        local sep = tile:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 0, 0)
        sep:SetColorTexture(1, 1, 1, 0.04)

        -- 12.1: Frame Border indicators are removed; the notice covers the
        -- tile body but leaves the right controls column usable so the
        -- indicator can still be toggled off or deleted.
        if EllesmereUI.IS_121 and ind.type == "border" then
            local ov = BuildPTROverlay(tile, "Frame Border", 10)
            ov:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
            ov:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -52, 1)
        end

        tileY = tileY - TILE_H
    end

    -------------------------------------------------------------------
    --  "Add New" button at bottom of sidebar tiles
    -------------------------------------------------------------------
    local ADD_BTN_H = 30
    local ADD_BTN_PAD = 10  -- vertical padding above button
    do
        local btnW = floor(sidebarW * 0.6)
        local addBtn = CreateFrame("Button", nil, sidebarFrame)
        addBtn:SetSize(btnW, ADD_BTN_H)
        addBtn:SetPoint("TOP", sidebarFrame, "TOPLEFT", floor(sidebarW / 2), tileY - ADD_BTN_PAD)
        addBtn:SetFrameLevel(sidebarFrame:GetFrameLevel() + 1)

        local accentColor = EllesmereUI.ELLESMERE_GREEN
        local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
        addBg:SetAllPoints()
        addBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)

        local addLabel = addBtn:CreateFontString(nil, "OVERLAY")
        addLabel:SetFont(fontPath, 12, "")
        addLabel:SetPoint("CENTER")
        addLabel:SetText(EllesmereUI.L("Add New"))
        addLabel:SetTextColor(1, 1, 1)

        addBtn:SetScript("OnEnter", function()
            addBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 1)
        end)
        addBtn:SetScript("OnLeave", function()
            addBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
        end)

        addBtn:SetScript("OnClick", function(self)
            -- Toggle popup
            local popup = ns._addNewPopup
            if popup and popup:IsShown() then popup:Hide(); return end

            if not selectedSpecKey then return end

            -- Rebuild spell items for the (possibly changed) spec
            if popup and popup._rebuildSpells then
                popup._rebuildSpells()
            end

            if not popup then
                local POPUP_W = 220
                local POPUP_PAD = 10
                local ROW_H = 30
                local LABEL_H = 14
                local GAP = 6

                popup = CreateFrame("Frame", nil, UIParent)
                popup:SetFrameStrata("DIALOG")
                popup:SetFrameLevel(200)
                local LBL_GAP = 4   -- label to dropdown
                local DD_GAP = 11  -- dropdown to next label/button
                popup:SetSize(POPUP_W, POPUP_PAD + LABEL_H + LBL_GAP + ROW_H + DD_GAP + LABEL_H + LBL_GAP + ROW_H + DD_GAP + ROW_H + POPUP_PAD)
                popup:EnableMouse(true)
                popup:SetClampedToScreen(true)

                local bg = popup:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
                EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.2, PP)

                -- Auto-close when clicking outside (but not on child dropdown menus)
                popup:SetScript("OnShow", function(p)
                    p:SetScript("OnUpdate", function(m)
                        if not self:IsMouseOver() and not m:IsMouseOver() then
                            -- Check if any child dropdown menu is open and mouse is over it
                            local spDD = m._spellDD
                            if spDD and spDD._ddMenu and spDD._ddMenu:IsShown() and spDD._ddMenu:IsMouseOver() then return end
                            local indDD2 = m._indDD
                            if indDD2 and indDD2._ddMenu and indDD2._ddMenu:IsShown() and indDD2._ddMenu:IsMouseOver() then return end
                            if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                                m:Hide()
                            end
                        end
                    end)
                end)
                popup:SetScript("OnHide", function(p)
                    p:SetScript("OnUpdate", nil)
                    -- Clear spell selections so reopening starts fresh
                    wipe(selectedSpells)
                    -- Refresh the abilities dropdown label + checkboxes
                    if p._spellDDRefresh then p._spellDDRefresh() end
                end)

                local py = -POPUP_PAD
                local ddW = POPUP_W - POPUP_PAD * 2

                -- Abilities label + CB dropdown
                local abLbl = popup:CreateFontString(nil, "OVERLAY")
                abLbl:SetFont(fontPath, 11, "")
                abLbl:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                abLbl:SetText(EllesmereUI.L("Abilities"))
                abLbl:SetTextColor(1, 1, 1, 0.6)
                py = py - LABEL_H - LBL_GAP

                -- Build spell items for the selected spec
                local function RebuildSpellItems()
                    local items = {}
                    if selectedSpecKey then
                        local spec = SPEC_BY_KEY[selectedSpecKey]
                        if spec then
                            for _, spell in ipairs(spec.spells) do
                                if not spell.hide then
                                    items[#items + 1] = { key = tostring(spell.id), label = SPELL_NAME_BY_ID[spell.id] or spell.name, icon = GetSpellIcon(spell.id), iconSize = DD_SPELL_ICON_SIZE }
                                end
                            end
                            table.sort(items, function(a, b) return a.label < b.label end)
                            local function AllSel()
                                for _, item in ipairs(items) do
                                    if not item.isAction and not selectedSpells[item.key] then return false end
                                end
                                return true
                            end
                            tinsert(items, 1, {
                                key = "__all", isAction = true,
                                labelFn = function() return AllSel() and "None" or "All" end,
                            })
                        end
                    end
                    return items
                end

                local spellDDY = py  -- save Y for rebuild
                local mFS = popup:CreateFontString(nil, "OVERLAY")
                mFS:SetFont(fontPath, 13, "")
                mFS:Hide()

                local function BuildSpellDD()
                    -- Destroy previous
                    if popup._spellDD then popup._spellDD:Hide(); popup._spellDD:SetParent(nil) end
                    popup._spellDD = nil
                    popup._spellDDRefresh = nil
                    wipe(selectedSpells)

                    local spellItems = RebuildSpellItems()
                    local maxTW = 0
                    for _, item in ipairs(spellItems) do
                        mFS:SetText(item.labelFn and item.labelFn() or item.label)
                        local tw = mFS:GetStringWidth()
                        if tw > maxTW then maxTW = tw end
                    end
                    local menuW = max(ddW, maxTW + 60)

                    if #spellItems > 0 then
                        local spellDD, spellDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                            popup, menuW, popup:GetFrameLevel() + 2,
                            spellItems,
                            function(k) return selectedSpells[k] or false end,
                            function(k, v)
                                if k == "__all" then
                                    local allOn = true
                                    for _, item in ipairs(spellItems) do
                                        if not item.isAction and not selectedSpells[item.key] then allOn = false; break end
                                    end
                                    for _, item in ipairs(spellItems) do
                                        if not item.isAction then selectedSpells[item.key] = not allOn or nil end
                                    end
                                else
                                    selectedSpells[k] = v or nil
                                end
                            end,
                            nil, nil, nil, true)  -- closeButton = "Okay"
                        spellDD:SetSize(ddW, ROW_H)
                        spellDD:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, spellDDY)
                        popup._spellDD = spellDD
                        popup._spellDDRefresh = spellDDRefresh
                    end
                end
                BuildSpellDD()
                popup._rebuildSpells = BuildSpellDD
                py = py - ROW_H - DD_GAP

                -- Indicator label + dropdown
                local indLbl = popup:CreateFontString(nil, "OVERLAY")
                indLbl:SetFont(fontPath, 11, "")
                indLbl:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                indLbl:SetText(EllesmereUI.L("Indicator"))
                indLbl:SetTextColor(1, 1, 1, 0.6)
                py = py - LABEL_H - LBL_GAP

                local indDD = EllesmereUI.BuildDropdownControl(
                    popup, ddW, popup:GetFrameLevel() + 2,
                    INDICATOR_TYPE_VALUES, INDICATOR_TYPE_ORDER,
                    function() return selectedType end,
                    function(v) selectedType = v end)
                indDD:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                popup._indDD = indDD
                py = py - ROW_H - DD_GAP

                -- Create button
                local cBtn = CreateFrame("Button", nil, popup)
                cBtn:SetSize(ddW, ROW_H)
                cBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                cBtn:SetFrameLevel(popup:GetFrameLevel() + 1)
                local cBg = cBtn:CreateTexture(nil, "BACKGROUND")
                cBg:SetAllPoints()
                cBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
                local cTx = cBtn:CreateFontString(nil, "OVERLAY")
                cTx:SetPoint("CENTER")
                cTx:SetFont(fontPath, 12, "")
                cTx:SetText(EllesmereUI.L("Create"))
                cTx:SetTextColor(1, 1, 1)
                cBtn:SetScript("OnEnter", function() cBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 1) end)
                cBtn:SetScript("OnLeave", function() cBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8) end)
                cBtn:SetScript("OnClick", function()
                    if not selectedSpecKey then return end
                    if CountSpecIndicators(db, selectedSpecKey) >= MAX_PER_SPEC then return end
                    local spells = {}
                    for k, v in pairs(selectedSpells) do
                        if v then tinsert(spells, tonumber(k)) end
                    end
                    if #spells == 0 then return end
                    local tInfo = INDICATOR_TYPE_MAP[selectedType]
                    local lastCreated
                    if tInfo and tInfo.singleSpell and #spells > 1 then
                        local list = GetSpecIndicators(db, selectedSpecKey)
                        for _, sid in ipairs(spells) do
                            if #list < MAX_PER_SPEC then
                                local newInd = NewIndicator(selectedType, { sid })
                                tinsert(list, newInd)
                                lastCreated = newInd
                            end
                        end
                    else
                        local list = GetSpecIndicators(db, selectedSpecKey)
                        local newInd = NewIndicator(selectedType, spells)
                        tinsert(list, newInd)
                        lastCreated = newInd
                    end
                    if lastCreated then selectedIndicator = lastCreated end
                    wipe(selectedSpells)
                    RebuildLookup(db)
                    if ns.ReloadFrames then ns.ReloadFrames() end
                    popup:Hide()
                    EllesmereUI:RefreshPage(true)
                end)

                ns._addNewPopup = popup
            end

            -- Position below the Add New button, centered on sidebar
            popup:ClearAllPoints()
            local sc = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            popup:SetScale(sc)
            popup:SetPoint("TOP", self, "BOTTOM", 0, -12)
            popup:Show()
        end)

        tileY = tileY - ADD_BTN_PAD - ADD_BTN_H - ADD_BTN_PAD
    end

    -------------------------------------------------------------------
    --  LEFT COLUMN (72%): Fixed top area + scrollable settings below
    -------------------------------------------------------------------
    -- Fixed top container (creation row + preview + title)
    local leftFixed = CreateFrame("Frame", nil, root)
    leftFixed:SetSize(leftW, 10)  -- height set after content
    leftFixed:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)

    local ly = 0  -- local Y within leftFixed
    local leftFrame = leftFixed  -- alias, reassigned to scroll child later

    -------------------------------------------------------------------
    --  1. SPEC SELECTOR + PREVIEW (35/65 split)
    --  Left 35%: label, spec dropdown, class icon
    --  Right 65%: centered raid frame replica
    -------------------------------------------------------------------
    -- Class icon sprite sheet (shared by spec dropdown icons + class icon display)
    local CLASS_SPRITE_TEX = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\modern.tga"
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
    local SPEC_CLASS_MAP = {}
    for _, spec in ipairs(HEALER_SPECS) do
        SPEC_CLASS_MAP[spec.key] = spec.classToken
    end

    do
        local PV_SCALE = 1.5
        local rawW = s.frameWidth or 72
        local rawH = s.frameHeight or 46
        local previewPad = 20
        -- Cap the preview's on-screen height at 100px via a uniform downscale, which
        -- keeps the frame's aspect ratio (rawW:rawH) intact. Simple + custom use the
        -- same value -- adjust both together.
        if rawH * PV_SCALE > 100 then PV_SCALE = 100 / rawH end
        -- Scaled dimensions for layout spacing (frame is real size but SetScale'd)
        local pvW = floor(rawW * PV_SCALE + 0.5)
        local pvH = floor(rawH * PV_SCALE + 0.5)

        -- Section height: max of preview height or spec selector content
        local sectionH = max(pvH + previewPad * 2, 120)
        local pvSplitW = floor(leftW * 0.65)   -- left 65% for preview
        local specSplitW = leftW - pvSplitW     -- right 35% for editing spec

        ---------------------------------------------------------------
        --  LEFT 65%: Preview frame (centered)
        ---------------------------------------------------------------
        local pvFrame = CreateFrame("Frame", nil, leftFrame)
        pvFrame:SetSize(rawW, rawH)
        pvFrame:SetScale(PV_SCALE)
        local pvCenterX = pvSplitW / 2
        pvFrame:SetPoint("TOP", leftFrame, "TOPLEFT", floor(pvCenterX / PV_SCALE), (ly - previewPad) / PV_SCALE)

        -- Vertical divider between preview and editing spec
        local splitDiv = leftFixed:CreateTexture(nil, "ARTWORK")
        splitDiv:SetWidth(1)
        splitDiv:SetPoint("TOP", leftFixed, "TOPLEFT", pvSplitW, ly - 10)
        splitDiv:SetPoint("BOTTOM", leftFixed, "TOPLEFT", pvSplitW, ly - sectionH + 10)
        splitDiv:SetColorTexture(1, 1, 1, 0.08)

        ---------------------------------------------------------------
        --  RIGHT 35%: Background class icon + centered label + dropdown
        ---------------------------------------------------------------
        local specCenterX = pvSplitW + specSplitW / 2

        -- Background class icon (covers right section, faded)
        local classIconBg = leftFixed:CreateTexture(nil, "BACKGROUND", nil, 1)
        classIconBg:SetTexture(CLASS_SPRITE_TEX)
        local iconSz = sectionH * 0.7 + 10
        classIconBg:SetSize(iconSz, iconSz)
        classIconBg:SetPoint("CENTER", leftFixed, "TOPLEFT", specCenterX, ly - sectionH / 2)
        classIconBg:SetAlpha(0.10)
        classIconBg:SetDesaturated(true)
        classIconBg:SetDesaturation(0.5)
        local selClass = selectedSpecKey and SPEC_CLASS_MAP[selectedSpecKey]
        local selCoords = selClass and CLASS_SPRITE_COORDS[selClass]
        if selCoords then
            classIconBg:SetTexCoord(selCoords[1], selCoords[2], selCoords[3], selCoords[4])
        end

        -- Label + dropdown as a vertically centered group
        -- Total height: label(14) + gap(7) + dropdown(30) = 51
        local groupH = 14 + 7 + 30
        local groupTopY = ly - (sectionH - groupH) / 2

        local specLabel = leftFixed:CreateFontString(nil, "OVERLAY")
        specLabel:SetFont(fontPath, 12, "")
        specLabel:SetPoint("TOP", leftFixed, "TOPLEFT", specCenterX, groupTopY)
        specLabel:SetJustifyH("CENTER")
        specLabel:SetText(EllesmereUI.L("Editing Spec"))
        specLabel:SetTextColor(1, 1, 1, 0.75)

        local specDDValues = {}
        for k, v in pairs(SPEC_DD_VALUES) do specDDValues[k] = EllesmereUI.L(v) end
        specDDValues._menuOpts = {
            maxHeight = 300,
            icon = function(key)
                local ct = SPEC_CLASS_MAP[key]
                local coords = ct and CLASS_SPRITE_COORDS[ct]
                if coords then
                    return CLASS_SPRITE_TEX, coords[1], coords[2], coords[3], coords[4]
                end
            end,
        }

        local specDDW = specSplitW - PAD - 50
        local specDD = EllesmereUI.BuildDropdownControl(
            leftFixed, specDDW, leftFixed:GetFrameLevel() + 2,
            specDDValues, SPEC_DD_ORDER,
            function() return selectedSpecKey or "" end,
            function(v)
                selectedSpecKey = v
                selectedIndicator = nil
                wipe(selectedSpells)
                EllesmereUI:RefreshPage(true)
            end)
        specDD:SetPoint("TOP", specLabel, "BOTTOM", 0, -7)

        -- Background (match user's bg settings)
        local bgc = s.customBgColor or { r = 17/255, g = 17/255, b = 17/255 }
        local bg = pvFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()

        -- Health bar sizing (real sizes, not scaled)
        local rawPowerH = (s.powerShowForHealer or s.powerShowForTank or s.powerShowForDPS) and (s.powerHeight or 4) or 0
        local rawTopBarH = s.topNameBarEnabled and (s.topNameBarHeight or 20) or 0
        local healthH = rawH - rawPowerH - rawTopBarH

        -- Health bar
        local texKey = s.healthBarTexture or "atrocity"
        local texPath = EllesmereUI.ResolveTexturePath and
            EllesmereUI.ResolveTexturePath(ns.healthBarTextures or {}, texKey, "Interface\\Buttons\\WHITE8X8")
            or "Interface\\Buttons\\WHITE8X8"
        local health = CreateFrame("StatusBar", nil, pvFrame)
        health:SetFrameLevel(pvFrame:GetFrameLevel() + 2)
        health:SetPoint("TOPLEFT", pvFrame, "TOPLEFT", 0, -rawTopBarH)
        health:SetPoint("TOPRIGHT", pvFrame, "TOPRIGHT", 0, -rawTopBarH)
        health:SetHeight(healthH)
        health:SetStatusBarTexture(texPath)
        health:GetStatusBarTexture():SetHorizTile(false)
        health:SetMinMaxValues(0, 100)
        health:SetValue(85)

        -- Health color (match all 4 modes)
        -- Use selected spec's class for preview color (falls back to player class)
        local previewClass
        if selectedSpecKey and SPEC_BY_KEY[selectedSpecKey] then
            previewClass = SPEC_BY_KEY[selectedSpecKey].classToken
        end
        if not previewClass then
            local _, pc = UnitClass("player")
            previewClass = pc
        end
        local cc = EllesmereUI.GetClassColor and EllesmereUI.GetClassColor(previewClass)
        local mode = s.healthColorMode or "class"
        local fillTex = health:GetStatusBarTexture()
        if mode == "dark" then
            local dfr, dfg, dfb, dfa = EllesmereUI.GetDarkModeFill()
            health:SetStatusBarColor(dfr, dfg, dfb, 1)
            if fillTex then fillTex:SetAlpha(dfa) end
            bg:ClearAllPoints()
            bg:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
            bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            bg:SetColorTexture(EllesmereUI.GetDarkModeBg())
        elseif mode == "classic" then
            local pct = 0.85
            local r = pct < 0.5 and 1 or (1 - (pct - 0.5) * 2)
            local g = pct > 0.5 and 1 or (pct * 2)
            health:SetStatusBarColor(r, g, 0, (s.healthBarOpacity or 100) / 100)
            if fillTex then fillTex:SetAlpha(1) end
            bg:SetAllPoints()
            bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
        elseif mode == "custom" then
            local cfc = s.customFillColor or { r = 37/255, g = 193/255, b = 29/255 }
            health:SetStatusBarColor(cfc.r, cfc.g, cfc.b, (s.healthBarOpacity or 100) / 100)
            if fillTex then fillTex:SetAlpha(1) end
            bg:SetAllPoints()
            bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
        else -- class
            if cc then
                health:SetStatusBarColor(cc.r, cc.g, cc.b, (s.healthBarOpacity or 100) / 100)
            end
            if fillTex then fillTex:SetAlpha(1) end
            bg:SetAllPoints()
            bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
        end

        -- Power bar
        if rawPowerH > 0 then
            local power = CreateFrame("StatusBar", nil, pvFrame)
            power:SetFrameLevel(pvFrame:GetFrameLevel() + 3)
            power:SetPoint("BOTTOMLEFT", pvFrame, "BOTTOMLEFT", 0, 0)
            power:SetPoint("BOTTOMRIGHT", pvFrame, "BOTTOMRIGHT", 0, 0)
            power:SetHeight(rawPowerH)
            power:SetStatusBarTexture(texPath)
            power:GetStatusBarTexture():SetHorizTile(false)
            power:SetMinMaxValues(0, 100)
            power:SetValue(72)
            -- Power color: use MANA for healer specs (all healer specs use mana)
            local pToken = "MANA"
            local pInfo = EllesmereUI.GetPowerColor and EllesmereUI.GetPowerColor(pToken)
            if pInfo then
                power:SetStatusBarColor(pInfo.r, pInfo.g, pInfo.b, 1)
            else
                power:SetStatusBarColor(0, 0.5, 1, 1)
            end
            local pwBg = power:CreateTexture(nil, "BACKGROUND")
            pwBg:SetAllPoints()
            local pbc = (s.powerBgPowerColored and pInfo) or s.powerBgColor or { r=0, g=0, b=0 }
            local pbF = (s.powerBgPowerColored and pInfo) and EllesmereUI.GetPowerBgDarkenFactor() or 1
            pwBg:SetColorTexture(pbc.r * pbF, pbc.g * pbF, pbc.b * pbF, (s.powerBgDarkness or 70) / 100)

            -- Power border
            if PP and s.powerBorderStyle and s.powerBorderStyle ~= "none" then
                local pbSize = s.powerBorderSize or 1
                if pbSize > 0 then
                    local pwBdr = CreateFrame("Frame", nil, pvFrame)
                    pwBdr:SetAllPoints(power)
                    pwBdr:SetFrameLevel(power:GetFrameLevel() + 1)
                    PP.CreateBorder(pwBdr, 0, 0, 0, 1, 1)
                    local pBc = s.powerBorderColor or { r=0, g=0, b=0 }
                    PP.UpdateBorder(pwBdr, pbSize, pBc.r, pBc.g, pBc.b, s.powerBorderAlpha or 1)
                    local ppC = PP.GetBorders(pwBdr)
                    if ppC and s.powerBorderStyle == "divider" then
                        if ppC._bottom then ppC._bottom:SetAlpha(0) end
                        if ppC._left then ppC._left:SetAlpha(0) end
                        if ppC._right then ppC._right:SetAlpha(0) end
                    end
                end
            end
        end

        -- Border
        if PP then
            local bs = s.borderSize or 1
            if bs > 0 then
                local bdr = CreateFrame("Frame", nil, pvFrame)
                bdr:SetAllPoints(pvFrame)
                bdr:SetFrameLevel(pvFrame:GetFrameLevel() + 8)
                PP.CreateBorder(bdr, 0, 0, 0, 1, 1)
                local bc = s.borderColor or { r=0, g=0, b=0 }
                PP.UpdateBorder(bdr, bs, bc.r, bc.g, bc.b, s.borderAlpha or 1)
            end
        end

        -- Name text (real sizes, SetScale handles the magnification).
        -- Hosted on a carrier in the live text band (ns.LVL_TEXT) so the name
        -- draws above the +8 main border, exactly like real frames.
        local nameCarrier = CreateFrame("Frame", nil, pvFrame)
        nameCarrier:SetAllPoints(pvFrame)
        nameCarrier:SetFrameLevel(pvFrame:GetFrameLevel() + (ns.LVL_TEXT or 12))
        local nameFS = nameCarrier:CreateFontString(nil, "OVERLAY")
        local outline = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("raidFrames")) or ""
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(nameFS, outline == "" and (not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow("raidFrames"))) end
        nameFS:SetFont(fontPath, s.nameSize or 10, outline)
        nameFS:SetWordWrap(false)

        -- Name position (exact match of AnchorNameText logic)
        local pos = s.namePosition or "center"
        nameFS:SetShown(pos ~= "none" and not s.topNameBarEnabled)
        local ox = s.nameOffsetX or 0
        local oy = s.nameOffsetY or 0
        nameFS:SetPoint("LEFT", health, "LEFT", 2 + ox, 0)
        nameFS:SetPoint("RIGHT", health, "RIGHT", -floor(rawW * 0.25) + ox, 0)
        if pos == "topleft" then
            nameFS:SetPoint("TOP", health, "TOP", 0, -2 + oy)
            nameFS:SetJustifyH("LEFT"); nameFS:SetJustifyV("TOP")
        elseif pos == "top" then
            nameFS:SetPoint("TOP", health, "TOP", 0, -2 + oy)
            nameFS:SetJustifyH("CENTER"); nameFS:SetJustifyV("TOP")
        elseif pos == "topright" then
            nameFS:SetPoint("TOP", health, "TOP", 0, -2 + oy)
            nameFS:SetJustifyH("RIGHT"); nameFS:SetJustifyV("TOP")
        elseif pos == "left" then
            nameFS:SetPoint("CENTER", health, "CENTER", 0, oy)
            nameFS:SetJustifyH("LEFT"); nameFS:SetJustifyV("MIDDLE")
        elseif pos == "right" then
            nameFS:SetPoint("CENTER", health, "CENTER", 0, oy)
            nameFS:SetJustifyH("RIGHT"); nameFS:SetJustifyV("MIDDLE")
        elseif pos == "bottomleft" then
            nameFS:SetPoint("BOTTOM", health, "BOTTOM", 0, 2 + oy)
            nameFS:SetJustifyH("LEFT"); nameFS:SetJustifyV("BOTTOM")
        elseif pos == "bottom" then
            nameFS:SetPoint("BOTTOM", health, "BOTTOM", 0, 2 + oy)
            nameFS:SetJustifyH("CENTER"); nameFS:SetJustifyV("BOTTOM")
        else -- center
            nameFS:SetPoint("CENTER", health, "CENTER", 0, oy)
            nameFS:SetJustifyH("CENTER"); nameFS:SetJustifyV("MIDDLE")
        end

        -- Name color (match all modes)
        local playerName = UnitName("player") or "Player"
        if Ambiguate then playerName = Ambiguate(playerName, "short") end
        nameFS:SetText(playerName)
        local nameMode = s.nameColorMode or "class"
        if nameMode == "accent" then
            local ar, ag, ab = EllesmereUI.ResolveActiveAccent()
            if ar then nameFS:SetTextColor(ar, ag, ab)
            else nameFS:SetTextColor(1, 1, 1) end
        elseif nameMode == "custom" then
            local c = s.nameCustomColor or { r=1, g=1, b=1 }
            nameFS:SetTextColor(c.r, c.g, c.b)
        else -- class
            if cc then nameFS:SetTextColor(cc.r, cc.g, cc.b)
            else nameFS:SetTextColor(1, 1, 1) end
        end

        -- Top Name Bar band (preview replica)
        if s.topNameBarEnabled then
            local tnb = CreateFrame("Frame", nil, pvFrame)
            tnb:SetFrameLevel(pvFrame:GetFrameLevel() + 4)
            tnb:SetPoint("TOPLEFT", pvFrame, "TOPLEFT", 0, 0)
            tnb:SetPoint("TOPRIGHT", pvFrame, "TOPRIGHT", 0, 0)
            tnb:SetHeight(rawTopBarH)
            local tnbBg = tnb:CreateTexture(nil, "BACKGROUND")
            tnbBg:SetAllPoints()
            local tbgc = s.topNameBarBgColor or { r=17/255, g=17/255, b=17/255 }
            tnbBg:SetColorTexture(tbgc.r, tbgc.g, tbgc.b, (s.topNameBarBgOpacity or 80) / 100)
            local tnbText = tnb:CreateFontString(nil, "OVERLAY")
            tnbText:SetFont(fontPath, s.topNameBarTextSize or 11, outline)
            tnbText:SetWordWrap(false)
            tnbText:SetText(playerName)
            local talign = s.topNameBarTextAlign or "center"
            local tox = s.topNameBarTextOffsetX or 0
            local toy = s.topNameBarTextOffsetY or 0
            if talign == "left" then
                tnbText:SetPoint("LEFT", tnb, "LEFT", 4 + tox, toy); tnbText:SetJustifyH("LEFT")
            elseif talign == "right" then
                tnbText:SetPoint("RIGHT", tnb, "RIGHT", -4 + tox, toy); tnbText:SetJustifyH("RIGHT")
            else
                tnbText:SetPoint("CENTER", tnb, "CENTER", tox, toy); tnbText:SetJustifyH("CENTER")
            end
            tnbText:SetJustifyV("MIDDLE")
            if (s.topNameBarTextColorMode or "class") == "custom" then
                local c = s.topNameBarTextColor or { r=1, g=1, b=1 }
                tnbText:SetTextColor(c.r, c.g, c.b)
            elseif cc then
                tnbText:SetTextColor(cc.r, cc.g, cc.b)
            else
                tnbText:SetTextColor(1, 1, 1)
            end
        end

        -- Health text
        local htMode = s.healthTextMode or "none"
        if htMode ~= "none" then
            local htFS = health:CreateFontString(nil, "OVERLAY")
            htFS:SetFont(fontPath, s.healthTextSize or 9, outline)
            htFS:SetTextColor(1, 1, 1, 0.9)
            local htPos = s.healthTextPosition or "center"
            local htOX = s.healthTextOffsetX or 0
            local htOY = s.healthTextOffsetY or 0
            htFS:SetWidth(rawW * 0.75)
            htFS:SetHeight(0)
            if htPos == "topleft" then
                htFS:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + htOX, -2 + htOY)
                htFS:SetJustifyH("LEFT"); htFS:SetJustifyV("TOP")
            elseif htPos == "top" then
                htFS:SetPoint("TOP", health, "TOP", htOX, -2 + htOY)
                htFS:SetJustifyH("CENTER"); htFS:SetJustifyV("TOP")
            elseif htPos == "topright" then
                htFS:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + htOX, -2 + htOY)
                htFS:SetJustifyH("RIGHT"); htFS:SetJustifyV("TOP")
            elseif htPos == "left" then
                htFS:SetPoint("LEFT", health, "LEFT", 2 + htOX, htOY)
                htFS:SetJustifyH("LEFT"); htFS:SetJustifyV("MIDDLE")
            elseif htPos == "right" then
                htFS:SetPoint("RIGHT", health, "RIGHT", -2 + htOX, htOY)
                htFS:SetJustifyH("RIGHT"); htFS:SetJustifyV("MIDDLE")
            elseif htPos == "bottomleft" then
                htFS:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + htOX, 2 + htOY)
                htFS:SetJustifyH("LEFT"); htFS:SetJustifyV("BOTTOM")
            elseif htPos == "bottom" then
                htFS:SetPoint("BOTTOM", health, "BOTTOM", htOX, 2 + htOY)
                htFS:SetJustifyH("CENTER"); htFS:SetJustifyV("BOTTOM")
            else
                htFS:SetPoint("CENTER", health, "CENTER", htOX, htOY)
                htFS:SetJustifyH("CENTER"); htFS:SetJustifyV("MIDDLE")
            end
            if htMode == "percent" then
                htFS:SetText("85%")
            elseif htMode == "percentNoSign" then
                htFS:SetText("85")
            elseif htMode == "number" then
                htFS:SetText("1.02M")
            end
        end

        -- Buff manager indicators on the preview
        pvFrame._health = health
        if ns.BM_CreatePreviewIndicators then
            ns.BM_CreatePreviewIndicators(pvFrame, health, PP)
        end
        if ns.BM_ApplyPreviewIndicators then
            ns.BM_ApplyPreviewIndicators(pvFrame, 1, s)
        end

        -- Eyeball toggle: show all indicators at full opacity
        do
            local EYE_VIS = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
            local EYE_INVIS = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
            ns._bmAllIndicatorsVisible = ns._bmAllIndicatorsVisible or false

            local eyeBtn = CreateFrame("Button", nil, leftFrame)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetPoint("LEFT", pvFrame, "RIGHT", 18 / PV_SCALE, 0)
            eyeBtn:SetFrameLevel(leftFrame:GetFrameLevel() + 5)

            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            eyeTex:SetTexture(ns._bmAllIndicatorsVisible and EYE_INVIS or EYE_VIS)
            eyeBtn:SetAlpha(0.4)

            eyeBtn:SetScript("OnClick", function()
                ns._bmAllIndicatorsVisible = not ns._bmAllIndicatorsVisible
                eyeTex:SetTexture(ns._bmAllIndicatorsVisible and EYE_INVIS or EYE_VIS)
                if ns.BM_ApplyPreviewIndicators then
                    ns.BM_ApplyPreviewIndicators(pvFrame, 1, db.profile)
                end
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, "Toggle All Indicators")
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                self:SetAlpha(0.4)
                EllesmereUI.HideWidgetTooltip()
            end)
        end

        -- Store reference so ReloadAndUpdate can refresh preview live
        ns._bmPreviewFrame = pvFrame

        -- Small helper subtitle under the preview explaining icon interactions.
        -- Click to dismiss permanently (EllesmereUIDB.bmIconHintDismissed). When
        -- dismissed it is not built and the extra 10px gap below collapses to 0.
        if not (EllesmereUIDB and EllesmereUIDB.bmIconHintDismissed) then
            -- Clickable button (FontStrings can't take clicks); label is its child.
            local hintBtn = CreateFrame("Button", nil, leftFrame)
            hintBtn:SetPoint("TOP", pvFrame, "BOTTOM", 0, -8)
            local hintFS = hintBtn:CreateFontString(nil, "OVERLAY")
            hintFS:SetFont(fontPath, 11, "")
            hintFS:SetAllPoints(hintBtn)
            hintFS:SetJustifyH("CENTER")
            hintFS:SetWordWrap(false)
            hintFS:SetTextColor(0.75, 0.75, 0.75, 0.65)
            hintFS:SetText(EllesmereUI.L("For Icons: Left click to edit group, Right click to custom size individual"))
            hintBtn:SetSize(hintFS:GetStringWidth() + 8, 14)
            hintBtn:SetScript("OnEnter", function() hintFS:SetTextColor(1, 1, 1, 0.85) end)
            hintBtn:SetScript("OnLeave", function() hintFS:SetTextColor(0.75, 0.75, 0.75, 0.65) end)
            hintBtn:SetScript("OnClick", function()
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.bmIconHintDismissed = true
                EllesmereUI:RefreshPage(true)
            end)
            -- Extra 10px below the subtitle before the divider/settings.
            ly = ly - sectionH - 10
        else
            ly = ly - sectionH
        end
    end

    -------------------------------------------------------------------
    --  DIVIDER (below spec/preview, above settings title)
    -------------------------------------------------------------------
    local div1 = leftFixed:CreateTexture(nil, "ARTWORK")
    div1:SetHeight(1)
    div1:SetPoint("TOPLEFT", leftFixed, "TOPLEFT", PAD, ly)
    div1:SetPoint("TOPRIGHT", leftFixed, "TOPRIGHT", -PAD, ly)
    div1:SetColorTexture(1, 1, 1, 0.08)

    -------------------------------------------------------------------
    --  LEFT COLUMN: Accent title + settings
    -------------------------------------------------------------------
    ly = ly - 25  -- 25px spacing above title

    -- Accent-colored title (on fixed area)
    local settingsTitle = leftFixed:CreateFontString(nil, "OVERLAY")
    settingsTitle:SetFont(fontPath, 18, "")
    settingsTitle:SetPoint("TOPLEFT", leftFixed, "TOPLEFT", PAD, ly)
    settingsTitle:SetJustifyH("LEFT")
    settingsTitle:SetWordWrap(false)

    -- Spell names as a separate white 75% opacity font string (inline after title)
    local spellsTitle = leftFixed:CreateFontString(nil, "OVERLAY")
    spellsTitle:SetFont(fontPath, 13, "")
    spellsTitle:SetPoint("LEFT", settingsTitle, "RIGHT", 4, 0)
    spellsTitle:SetPoint("RIGHT", leftFixed, "RIGHT", -PAD, 0)
    spellsTitle:SetJustifyH("LEFT")
    spellsTitle:SetWordWrap(false)
    spellsTitle:SetTextColor(0.75, 0.75, 0.75, 0.65)

    ly = ly - 18 - 10  -- title + spacing

    -- Finalize fixed top area height
    local fixedH = math.abs(ly)
    leftFixed:SetHeight(fixedH)

    -- Settings area below the fixed top
    -- DualRow internally subtracts CONTENT_PAD*2 from parent width and offsets
    -- by CONTENT_PAD. We want the resulting content to align with our PAD (20px).
    -- So: container width = leftW + (CONTENT_PAD - PAD)*2
    --     container offset = -(CONTENT_PAD - PAD)
    local contentPad = EllesmereUI.CONTENT_PAD or 45
    local padDiff = contentPad - PAD
    local viewportH = max(10, visibleH - fixedH)
    local settingsW = leftW + padDiff * 2

    -- Smooth-scrolling viewport (mirrors the main options page). Rows build into
    -- the scroll child; its height + the scrollbar are sized to the content after
    -- building. The OnUpdate smooth frame is a child of root, so it stops when the
    -- page is rebuilt (the old root is hidden).
    local settingsScroll = CreateFrame("ScrollFrame", nil, root)
    -- +5 raises the settings panel (CORE section first) 5px into the fixed area's
    -- bottom spacing, tightening the gap above the CORE header for every indicator.
    settingsScroll:SetPoint("TOPLEFT", leftFixed, "BOTTOMLEFT", -padDiff, 5)
    settingsScroll:SetSize(settingsW, viewportH)
    settingsScroll:SetFrameLevel(root:GetFrameLevel() + 1)
    settingsScroll:SetClipsChildren(true)

    local settingsChild = CreateFrame("Frame", nil, settingsScroll)
    settingsChild:SetSize(settingsW, viewportH)
    settingsScroll:SetScrollChild(settingsChild)

    -- Scrollbar: thin track + thumb at the viewport's right edge (shown only on overflow).
    local SBAR_W = 5
    local sbTrack = CreateFrame("Frame", nil, settingsScroll)
    sbTrack:SetPoint("TOPRIGHT", settingsScroll, "TOPRIGHT", -31, -12)
    sbTrack:SetPoint("BOTTOMRIGHT", settingsScroll, "BOTTOMRIGHT", -31, 12)
    sbTrack:SetWidth(SBAR_W)
    sbTrack:SetFrameLevel(settingsScroll:GetFrameLevel() + 20)
    do local t = sbTrack:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(); t:SetColorTexture(1, 1, 1, 0.05) end
    local sbThumb = CreateFrame("Frame", nil, sbTrack)
    sbThumb:SetWidth(SBAR_W); sbThumb:SetHeight(30)
    sbThumb:SetPoint("TOP", sbTrack, "TOP", 0, 0)
    sbThumb:EnableMouse(true)
    do local t = sbThumb:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(); t:SetColorTexture(1, 1, 1, 0.22) end
    sbTrack:Hide()

    local SCROLL_STEP, SMOOTH_SPEED = 60, 12
    local scrollTarget = 0
    local function MaxScroll() return max(0, settingsChild:GetHeight() - settingsScroll:GetHeight()) end
    local function UpdateThumb()
        local ms = MaxScroll()
        if ms <= 0 then sbTrack:Hide(); return end
        sbTrack:Show()
        local trackH = sbTrack:GetHeight()
        local visH = settingsScroll:GetHeight()
        local thumbH = max(30, trackH * (visH / (visH + ms)))
        sbThumb:SetHeight(thumbH)
        local ratio = (settingsScroll:GetVerticalScroll() or 0) / ms
        sbThumb:ClearAllPoints()
        sbThumb:SetPoint("TOP", sbTrack, "TOP", 0, -(ratio * (trackH - thumbH)))
    end
    local smoothFrame = CreateFrame("Frame", nil, root)
    smoothFrame:Hide()
    smoothFrame:SetScript("OnUpdate", function(_, elapsed)
        local cur = settingsScroll:GetVerticalScroll()
        local ms = MaxScroll()
        scrollTarget = max(0, min(ms, scrollTarget))
        local diff = scrollTarget - cur
        if math.abs(diff) < 0.3 then
            settingsScroll:SetVerticalScroll(scrollTarget); UpdateThumb(); smoothFrame:Hide(); return
        end
        local nv = max(0, min(ms, cur + diff * min(1, SMOOTH_SPEED * elapsed)))
        settingsScroll:SetVerticalScroll(nv); UpdateThumb()
    end)
    local function SmoothTo(t)
        scrollTarget = max(0, min(MaxScroll(), t))
        smoothFrame:Show()
    end
    settingsScroll:EnableMouseWheel(true)
    settingsScroll:SetScript("OnMouseWheel", function(_, delta)
        if MaxScroll() <= 0 then return end
        local base = smoothFrame:IsShown() and scrollTarget or settingsScroll:GetVerticalScroll()
        SmoothTo(base - delta * SCROLL_STEP)
    end)
    sbThumb:SetScript("OnMouseDown", function()
        smoothFrame:Hide()
        local _, cy0 = GetCursorPosition()
        local startY = cy0 / settingsScroll:GetEffectiveScale()
        local startScroll = settingsScroll:GetVerticalScroll()
        sbThumb:SetScript("OnUpdate", function(self)
            if not IsMouseButtonDown("LeftButton") then self:SetScript("OnUpdate", nil); return end
            local ms = MaxScroll()
            local travel = sbTrack:GetHeight() - sbThumb:GetHeight()
            if travel <= 0 then return end
            local _, cy = GetCursorPosition(); cy = cy / settingsScroll:GetEffectiveScale()
            local nv = max(0, min(ms, startScroll + ((startY - cy) / travel) * ms))
            scrollTarget = nv
            settingsScroll:SetVerticalScroll(nv); UpdateThumb()
        end)
    end)

    -- From here, DualRows build inside the scroll child
    leftFrame = settingsChild
    leftFrame._showRowDivider = true
    local sy = 0  -- Y within settings scroll child

    if selectedIndicator then
        local ind = selectedIndicator
        local indType = ind.type
        local typeInfo = INDICATOR_TYPE_MAP[indType]

        -- Build title: accent "Icon Indicator: " + white "Rejuvenation, Lifebloom"
        local typeName = INDICATOR_TYPE_MAP[indType] and INDICATOR_TYPE_MAP[indType].name or indType
        local ac2 = EllesmereUI.ELLESMERE_GREEN
        if ac2 then
            settingsTitle:SetTextColor(ac2.r, ac2.g, ac2.b)
        else
            settingsTitle:SetTextColor(0.05, 0.82, 0.62)
        end
        settingsTitle:SetText(EllesmereUI.L(typeName .. " Indicator"))

        local spellNames = {}
        if ind.spells then
            for _, sid in ipairs(ind.spells) do
                spellNames[#spellNames + 1] = SPELL_NAME_BY_ID[sid] or tostring(sid)
            end
        end
        spellsTitle:SetText(#spellNames > 0 and ("(" .. table.concat(spellNames, ", ") .. ")") or EllesmereUI.L("(no spells)"))

        -- Helper: build a DualRow inside leftFrame
        local function SettingsRow(leftCfg, rightCfg)
            local row
            row, h = W:DualRow(leftFrame, sy, leftCfg, rightCfg)
            sy = sy - h
            return row
        end

        -- 12.1 removal overlays (BuildPTROverlay): section variant spans a
        -- y-range of leftFrame (header left visible, like the party sync
        -- overlays); slot variant covers one DualRow region.
        local function PTRSectionOverlay(label, startY, endY)
            local ov = BuildPTROverlay(leftFrame, label, 12)
            ov:SetPoint("TOPLEFT", leftFrame, "TOPLEFT", 0, startY)
            ov:SetPoint("TOPRIGHT", leftFrame, "TOPRIGHT", 0, startY)
            ov:SetHeight(math.abs(endY - startY))
        end

        local function PTRSlotOverlay(label, region)
            if not region then return end
            local ov = BuildPTROverlay(region, label, 11)
            ov:SetAllPoints(region)
        end

        -- Own Only checkbox dropdown (per-spell) builder
        local function BuildOwnOnlyRow()
            if not ind.spells or #ind.spells == 0 then return end
            local ownItems = {}
            for _, sid in ipairs(ind.spells) do
                ownItems[#ownItems + 1] = {
                    key = tostring(sid),
                    label = SPELL_NAME_BY_ID[sid] or tostring(sid),
                    icon = GetSpellIcon(sid), iconSize = DD_SPELL_ICON_SIZE,
                }
            end
            table.sort(ownItems, function(a, b) return a.label < b.label end)
            -- Measure own items for dynamic width
            local ownMeasure = leftFrame:CreateFontString(nil, "OVERLAY")
            ownMeasure:SetFont(fontPath, 13, "")
            local ownMaxW = 0
            for _, item in ipairs(ownItems) do
                ownMeasure:SetText(item.label)
                local tw = ownMeasure:GetStringWidth()
                if tw > ownMaxW then ownMaxW = tw end
            end
            ownMeasure:Hide()
            local ownMenuW = max(170, ownMaxW + 60)
            local ownRow = SettingsRow(
                { type="dropdown", text="Own Only",
                  values={ __placeholder = "All" }, order={ "__placeholder" },
                  getValue=function() return "__placeholder" end,
                  setValue=function() end },
                { type="label", text="" })
            local rgn = ownRow._leftRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, ownMenuW, rgn:GetFrameLevel() + 2,
                ownItems,
                function(k)
                    local sid = tonumber(k)
                    if ind.ownOnlySpells and ind.ownOnlySpells[sid] ~= nil then
                        return ind.ownOnlySpells[sid]
                    end
                    return ind.ownOnly ~= false
                end,
                function(k, v)
                    local sid = tonumber(k)
                    if not ind.ownOnlySpells then ind.ownOnlySpells = {} end
                    ind.ownOnlySpells[sid] = v
                    ReloadAndUpdate()
                end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            AttachOwnAllSpecsCog(rgn, ind)
        end

        -- Auto-default growth direction based on position
        local function GetDefaultGrow(pos)
            if pos == "RIGHT" or pos == "TOPRIGHT" or pos == "BOTTOMRIGHT" then return "LEFT" end
            if pos == "LEFT" or pos == "TOPLEFT" or pos == "BOTTOMLEFT" then return "RIGHT" end
            if pos == "TOP" then return "DOWN" end
            if pos == "BOTTOM" then return "UP" end
            return "RIGHT"
        end

        -- THRESHOLD section  rendered after every indicator's DISPLAY section.
        -- Drives an "expiring soon" recolor (curve route, secret-safe). Default
        -- OFF so existing indicators are unchanged until enabled.
        --   Row 1: Enable Threshold (toggle) | Threshold (sec) slider (1-10s).
        --   Row 2: Color (picker) | Opacity (full slider).
        -- Frame Alpha (useAlpha) has no colour, so Row 2 is a single Alpha slider.
        local function BuildThresholdRow(useAlpha)
            _, h = W:SectionHeader(leftFrame, "THRESHOLD", sy); sy = sy - h
            local thContentStart = sy -- overlay spans content below the header

            -- Sub-settings are interactive only while Enable Threshold is on.
            local thOff = function() return not ind.thresholdEnabled end

            -- Row 1: Enable Threshold | Threshold (sec)
            SettingsRow(
                { type="toggle", text="Enable Threshold",
                  getValue=function() return ind.thresholdEnabled or false end,
                  setValue=function(v) ind.thresholdEnabled = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                { type="slider", text="Threshold (sec)", min=1, max=10, step=1, trackWidth=120,
                  disabled=thOff, disabledTooltip="Enable Threshold",
                  getValue=function() return ind.threshold or 3 end,
                  setValue=function(v) ind.threshold = v; ReloadAndUpdate() end })

            -- Row 2: Color | Opacity  (Frame Alpha: single full-width Alpha slider)
            if useAlpha then
                SettingsRow(
                    { type="slider", text="Alpha", min=0, max=100, step=1,
                      disabled=thOff, disabledTooltip="Enable Threshold",
                      getValue=function() return ind.thresholdAlpha or 100 end,
                      setValue=function(v) ind.thresholdAlpha = v; ReloadAndUpdate() end },
                    { type="label", text="" })
            else
                SettingsRow(
                    -- Icon indicators recolor the duration text (not the icon), so
                    -- the label reads "Text Color" for that type specifically.
                    { type="colorpicker", text=(indType == "icon") and "Text Color" or "Color", hasAlpha=false,
                      disabled=thOff, disabledTooltip="Enable Threshold",
                      getValue=function()
                          local c = ind.thresholdColor or { r=1, g=0.2, b=0.2 }
                          return c.r, c.g, c.b
                      end,
                      setValue=function(r, g, b)
                          ind.thresholdColor = { r=r, g=g, b=b }
                          ReloadAndUpdate()
                      end },
                    { type="slider", text="Opacity", min=0, max=100, step=1,
                      disabled=thOff, disabledTooltip="Enable Threshold",
                      getValue=function() return ind.thresholdColorOpacity or 100 end,
                      setValue=function(v) ind.thresholdColorOpacity = v; ReloadAndUpdate() end })
            end

            -- Threshold Sound dropdown config (built once, placed below):
            -- plays once when the buff crosses the threshold. Shallow-copy the
            -- runtime name table so _menuOpts (preview icon) doesn't pollute
            -- the shared tables. Icon indicators seat it beside Icon Glow
            -- (row 3 slot 2); other types give it its own row.
            local soundCfg
            do
                local sPaths, sNames, sOrder = GetThresholdSoundTables()
                local soundValues = {}
                for k, v in pairs(sNames) do soundValues[k] = v end
                soundValues._menuOpts = {
                    itemHeight = 26,
                    maxTextWidthPct = 0.8,
                    searchable = true,
                    iconAtlas = function(key)
                        if key == "none" then return nil end
                        if not sPaths[key] then return nil end
                        return "common-icon-sound"
                    end,
                    iconPressedAtlas = function(key)
                        if key == "none" then return nil end
                        return "common-icon-sound-pressed"
                    end,
                    iconOnClick = function(key)
                        local path = sPaths[key]
                        if path then PlaySoundFile(path, "Master") end
                    end,
                    iconTooltip = function() return "Preview Sound" end,
                }
                soundCfg = { type="dropdown", text="Threshold Sound",
                    values=soundValues, order=sOrder,
                    tooltip="Only works for Blizzard's whitelisted healer spell IDs (non-private auras).",
                    disabled=thOff, disabledTooltip="Enable Threshold",
                    getValue=function() return ind.thresholdSound or "none" end,
                    setValue=function(v) ind.thresholdSound = v; ReloadAndUpdate() end }
            end

            -- Icon Glow (icon indicator only): a glow that plays while the buff
            -- is within the threshold window. Replicates CDM's Buff Glow control
            -- (style dropdown + inline class/custom color swatches).
            if indType == "icon" then
                local GLOW_VALUES = { [0] = "None" }
                local GLOW_ORDER = { 0 }
                local Styles = EllesmereUI.Glows and EllesmereUI.Glows.STYLES
                if Styles then
                    for i, entry in ipairs(Styles) do
                        if not entry.shapeGlow then
                            GLOW_VALUES[i] = entry.name
                            GLOW_ORDER[#GLOW_ORDER + 1] = i
                        end
                    end
                end
                local glowRow = SettingsRow(
                    { type="dropdown", text="Icon Glow",
                      values=GLOW_VALUES, order=GLOW_ORDER,
                      disabled=thOff, disabledTooltip="Enable Threshold",
                      getValue=function() return ind.iconGlowType or 0 end,
                      setValue=function(v) ind.iconGlowType = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                    soundCfg)
                -- Inline class + custom color swatches, left of the dropdown.
                do
                    local PP = EllesmereUI.PanelPP or EllesmereUI.PP
                    local leftRgn = glowRow._leftRegion
                    local ctrl = leftRgn._control

                    local classSwatch, updateClassSwatch = EllesmereUI.BuildColorSwatch(
                        leftRgn, glowRow:GetFrameLevel() + 3,
                        function()
                            local _, classFile = UnitClass("player")
                            local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                            if cc then return cc.r, cc.g, cc.b end
                            return 1, 0.82, 0
                        end,
                        function() end,
                        false, 20)
                    PP.Point(classSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                    classSwatch:SetScript("OnClick", function()
                        if not ind.thresholdEnabled then return end
                        ind.iconGlowClassColor = true; ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end)
                    classSwatch:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Colored")
                    end)
                    classSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                    local glowSwatch, updateGlowSwatch = EllesmereUI.BuildColorSwatch(
                        leftRgn, glowRow:GetFrameLevel() + 3,
                        function() return ind.iconGlowR or 1.0, ind.iconGlowG or 0.776, ind.iconGlowB or 0.376 end,
                        function(r, g, b)
                            ind.iconGlowR, ind.iconGlowG, ind.iconGlowB = r, g, b
                            ReloadAndUpdate()
                        end,
                        false, 20)
                    PP.Point(glowSwatch, "RIGHT", classSwatch, "LEFT", -8, 0)
                    glowSwatch:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(glowSwatch, "Custom Colored")
                    end)
                    glowSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    -- Click the dimmed custom swatch to switch back from class color.
                    local origGlowClick = glowSwatch:GetScript("OnClick")
                    glowSwatch:SetScript("OnClick", function(self, ...)
                        if not ind.thresholdEnabled then return end
                        if ind.iconGlowClassColor then
                            ind.iconGlowClassColor = false; ReloadAndUpdate(); EllesmereUI:RefreshPage()
                            return
                        end
                        if (ind.iconGlowType or 0) == 0 then return end
                        if origGlowClick then origGlowClick(self, ...) end
                    end)

                    local function UpdateGlowState()
                        local gt = ind.iconGlowType or 0
                        local noGlow = gt == 0 or not ind.thresholdEnabled
                        local isClassColored = ind.iconGlowClassColor
                        glowSwatch:SetAlpha((isClassColored or noGlow) and 0.3 or 1)
                        classSwatch:SetAlpha((isClassColored and not noGlow) and 1 or 0.3)
                    end
                    EllesmereUI.RegisterWidgetRefresh(function() updateGlowSwatch(); updateClassSwatch(); UpdateGlowState() end)
                    UpdateGlowState()
                end
            end

            -- Non-icon types: Threshold Sound gets its own row (odd last item,
            -- so the blank right slot is allowed).
            if indType ~= "icon" then
                SettingsRow(soundCfg, { type="label", text="" })
            end

            -- 12.1: no engine binding for threshold recolors/glows yet; the
            -- whole section is inert there until the upstream APIs land.
            -- Fully functional on 12.0.
            if EllesmereUI.IS_121 then
                PTRSectionOverlay("Threshold", thContentStart, sy)
            end
        end

        -- Abilities CB dropdown builder (shared by icon/square, used in row 1)
        local abItems = {}
        if not (typeInfo and typeInfo.singleSpell) and selectedSpecKey then
            local spec = SPEC_BY_KEY[selectedSpecKey]
            if spec then
                for _, spell in ipairs(spec.spells) do
                    if not spell.hide then
                        abItems[#abItems + 1] = {
                            key = tostring(spell.id),
                            label = SPELL_NAME_BY_ID[spell.id] or spell.name,
                            icon = GetSpellIcon(spell.id), iconSize = DD_SPELL_ICON_SIZE,
                        }
                    end
                end
                table.sort(abItems, function(a, b) return a.label < b.label end)
                -- All/None action at top
                local function AbAllSelected()
                    if not ind.spells then return false end
                    for _, item in ipairs(abItems) do
                        if not item.isAction then
                            local sid = tonumber(item.key)
                            local found = false
                            for _, id in ipairs(ind.spells) do
                                if id == sid then found = true; break end
                            end
                            if not found then return false end
                        end
                    end
                    return true
                end
                tinsert(abItems, 1, {
                    key = "__all", isAction = true,
                    labelFn = function() return AbAllSelected() and "None" or "All" end,
                })
            end
        end

        -- Measure longest spell name for dynamic dropdown widths
        local abMenuW = 170  -- fallback
        if #abItems > 0 then
            local measureFS = leftFrame:CreateFontString(nil, "OVERLAY")
            measureFS:SetFont(fontPath, 13, "")
            local maxTW = 0
            for _, item in ipairs(abItems) do
                measureFS:SetText(item.labelFn and item.labelFn() or item.label)
                local tw = measureFS:GetStringWidth()
                if tw > maxTW then maxTW = tw end
            end
            measureFS:Hide()
            abMenuW = max(170, maxTW + 60)
        end

        if indType == "icon" or indType == "square" then
            -----------------------------------------------------------
            --  CORE
            -----------------------------------------------------------
            _, h = W:SectionHeader(leftFrame, "CORE", sy); sy = sy - h

            -- Row 1: Abilities | Own Only
            local row1 = SettingsRow(
                #abItems > 0 and
                { type="dropdown", text="Abilities",
                  values={ __placeholder = "All Spells" }, order={ "__placeholder" },
                  getValue=function() return "__placeholder" end,
                  setValue=function() end }
                or { type="label", text="" },
                { type="dropdown", text="Own Only",
                  values={ __placeholder = "All" }, order={ "__placeholder" },
                  getValue=function() return "__placeholder" end,
                  setValue=function() end })
            -- Replace left with abilities CB dropdown
            if #abItems > 0 then
                local rgn = row1._leftRegion
                if rgn._control then rgn._control:Hide() end
                local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                    rgn, abMenuW, rgn:GetFrameLevel() + 2,
                    abItems,
                    function(k)
                        local sid = tonumber(k)
                        if ind.spells then
                            for _, id in ipairs(ind.spells) do
                                if id == sid then return true end
                            end
                        end
                        return false
                    end,
                    function(k, v)
                        if not ind.spells then ind.spells = {} end
                        if k == "__all" then
                            local allOn = true
                            for _, item in ipairs(abItems) do
                                if not item.isAction then
                                    local sid = tonumber(item.key)
                                    local found = false
                                    for _, id in ipairs(ind.spells) do
                                        if id == sid then found = true; break end
                                    end
                                    if not found then allOn = false; break end
                                end
                            end
                            if allOn then
                                wipe(ind.spells)
                            else
                                for _, item in ipairs(abItems) do
                                    if not item.isAction then
                                        local sid = tonumber(item.key)
                                        local found = false
                                        for _, id in ipairs(ind.spells) do
                                            if id == sid then found = true; break end
                                        end
                                        if not found then tinsert(ind.spells, sid) end
                                    end
                                end
                            end
                        else
                            local sid = tonumber(k)
                            if v then
                                local found = false
                                for _, id in ipairs(ind.spells) do
                                    if id == sid then found = true; break end
                                end
                                if not found then tinsert(ind.spells, sid) end
                            else
                                for i = #ind.spells, 1, -1 do
                                    if ind.spells[i] == sid then tremove(ind.spells, i) end
                                end
                            end
                        end
                        RebuildLookup(db)
                        if ns.ReloadFrames then ns.ReloadFrames() end
                        local names = {}
                        for _, id in ipairs(ind.spells) do
                            names[#names + 1] = SPELL_NAME_BY_ID[id] or tostring(id)
                        end
                        spellsTitle:SetText(#names > 0 and ("(" .. table.concat(names, ", ") .. ")") or EllesmereUI.L("(no spells)"))
                        local pv = ns._bmPreviewFrame
                        if pv and pv._health and ns.BM_ApplyPreviewIndicators then
                            ns.BM_ApplyPreviewIndicators(pv, 1, db.profile)
                        end
                    end)
                PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
                rgn._control = cbDD
                rgn._lastInline = nil
            end
            -- Replace right with own only CB dropdown
            do
                local ownItems = {}
                if ind.spells then
                    for _, sid in ipairs(ind.spells) do
                        ownItems[#ownItems + 1] = {
                            key = tostring(sid),
                            label = SPELL_NAME_BY_ID[sid] or tostring(sid),
                    icon = GetSpellIcon(sid), iconSize = DD_SPELL_ICON_SIZE,
                        }
                    end
                end
                table.sort(ownItems, function(a, b) return a.label < b.label end)
                if #ownItems > 0 then
                    local ownMeasure = leftFrame:CreateFontString(nil, "OVERLAY")
                    ownMeasure:SetFont(fontPath, 13, "")
                    local ownMaxW2 = 0
                    for _, item in ipairs(ownItems) do
                        ownMeasure:SetText(item.label)
                        local tw = ownMeasure:GetStringWidth()
                        if tw > ownMaxW2 then ownMaxW2 = tw end
                    end
                    ownMeasure:Hide()
                    local ownMenuW2 = max(170, ownMaxW2 + 60)
                    local rgn = row1._rightRegion
                    if rgn._control then rgn._control:Hide() end
                    local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                        rgn, ownMenuW2, rgn:GetFrameLevel() + 2,
                        ownItems,
                        function(k)
                            local sid = tonumber(k)
                            if ind.ownOnlySpells and ind.ownOnlySpells[sid] ~= nil then
                                return ind.ownOnlySpells[sid]
                            end
                            return ind.ownOnly ~= false
                        end,
                        function(k, v)
                            local sid = tonumber(k)
                            if not ind.ownOnlySpells then ind.ownOnlySpells = {} end
                            ind.ownOnlySpells[sid] = v
                            ReloadAndUpdate()
                        end)
                    PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
                    rgn._control = cbDD
                    rgn._lastInline = nil
                    AttachOwnAllSpecsCog(rgn, ind)
                end
            end

            -- Row 2: Position (+ cog) | Growth Direction
            local posRow = SettingsRow(
                { type="dropdown", text="Position", values=POSITION_VALUES, order=POSITION_ORDER,
                  getValue=function() return ind.position or "TOPLEFT" end,
                  setValue=function(v)
                      ind.position = v
                      ind.growDirection = GetDefaultGrow(v)
                      ReloadAndUpdate()
                      EllesmereUI:RefreshPage()
                  end },
                { type="dropdown", text="Growth Direction", values=GROW_VALUES, order=GROW_ORDER,
                  getValue=function() return ind.growDirection or "RIGHT" end,
                  setValue=function(v) ind.growDirection = v; ReloadAndUpdate() end })
            -- Cog for position offset X/Y
            do
                local rgn = posRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Position Offset",
                    rows = {
                        { type="slider", label="Offset X", min=-50, max=50, step=1,
                          get=function() return ind.offsetX or 0 end,
                          set=function(v) ind.offsetX = v; ReloadAndUpdate() end },
                        { type="slider", label="Offset Y", min=-50, max=50, step=1,
                          get=function() return ind.offsetY or 0 end,
                          set=function(v) ind.offsetY = v; ReloadAndUpdate() end },
                        { type="dropdown", label="Frame Level", values=FRAMELVL_VALUES, order=FRAMELVL_ORDER,
                          get=function() return ind.frameLevel or "medium" end,
                          set=function(v) ind.frameLevel = v; ReloadAndUpdate() end },
                    },
                })
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                cogBtn:SetAlpha(0.4)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
                cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            end

            -----------------------------------------------------------
            --  DISPLAY
            -----------------------------------------------------------
            _, h = W:SectionHeader(leftFrame, "DISPLAY", sy); sy = sy - h

            -- Row 1: Size (+ icon zoom cog) | Spacing
            local IconHidden = function() return indType == "icon" and ind.hideIcon == true end
            local sizeRow = SettingsRow(
                { type="slider", text="Size", min=4, max=40, step=1,
                  getValue=function() return ind.size or 12 end,
                  setValue=function(v) ind.size = v; ReloadAndUpdate() end },
                { type="slider", pixel=true, text="Spacing", min=-1, max=10, step=1,
                  getValue=function() return ind.spacing or 1 end,
                  setValue=function(v) ind.spacing = v; ReloadAndUpdate() end })

            -- Inline cog on Size: Icon Zoom (icon type only). One
            -- profile-wide value shared by all icon indicators.
            if indType == "icon" then
                local rgn = sizeRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Icon Zoom",
                    rows = {
                        { type="slider", label="Zoom", min=0, max=0.20, step=0.01,
                          get=function() return ns.db.profile.bmIconZoom or 0.08 end,
                          set=function(v) ns.db.profile.bmIconZoom = v; ReloadAndUpdate() end },
                    },
                })
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
                local function UpdCog() local off = IconHidden(); cogBtn:SetAlpha(off and 0.15 or 0.4); cogBtn:EnableMouse(not off) end
                cogBtn:SetScript("OnEnter", function(self) if not IconHidden() then self:SetAlpha(0.7) end end)
                cogBtn:SetScript("OnLeave", function(self) UpdCog() end)
                cogBtn:SetScript("OnClick", function(self) if not IconHidden() then cogShow(self) end end)
                UpdCog(); EllesmereUI.RegisterWidgetRefresh(UpdCog)
            end

            -- Row 2: Opacity | Border (+ inline color swatch)
            local bdrRow = SettingsRow(
                { type="slider", text="Opacity", min=0, max=100, step=1,
                  disabled=IconHidden, disabledTooltip="Hide Icons",
                  getValue=function() return ind.iconOpacity or 100 end,
                  setValue=function(v) ind.iconOpacity = v; ReloadAndUpdate() end },
                { type="slider", text="Border", min=0, max=4, step=1, trackWidth=120,
                  disabled=IconHidden, disabledTooltip="Hide Icons",
                  getValue=function() return ind.indBorderSize or 1 end,
                  setValue=function(v) ind.indBorderSize = v; ReloadAndUpdate() end })
            -- Inline swatch for border color
            do
                local rgn = bdrRow._rightRegion
                local swatch = EllesmereUI.BuildColorSwatch(
                    rgn, bdrRow:GetFrameLevel() + 3,
                    function()
                        local c = ind.indBorderColor or { r=0, g=0, b=0 }
                        return c.r, c.g, c.b, 1
                    end,
                    function(r, g, b)
                        ind.indBorderColor = { r=r, g=g, b=b }
                        ReloadAndUpdate()
                    end, false, 20)
                swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = swatch
            end

            -- Duration Swipe | Duration Text (+ swatch + cog)
            local durRow = SettingsRow(
                { type="toggle", text="Duration Swipe",
                  disabled=IconHidden, disabledTooltip="Hide Icons",
                  getValue=function() return ind.showDuration ~= false end,
                  setValue=function(v) ind.showDuration = v; ReloadAndUpdate() end },
                { type="toggle", text="Duration Text",
                  getValue=function() return ind.showDurationText or false end,
                  setValue=function(v) ind.showDurationText = v; ReloadAndUpdate() end })
            -- Inline swatch + cog for text color/size
            do
                local rgn = durRow._rightRegion
                local swatch = EllesmereUI.BuildColorSwatch(
                    rgn, durRow:GetFrameLevel() + 3,
                    function()
                        local c = ind.durationTextColor or { r=1, g=1, b=1 }
                        return c.r, c.g, c.b, 1
                    end,
                    function(r, g, b)
                        ind.durationTextColor = { r=r, g=g, b=b }
                        ReloadAndUpdate()
                    end, false, 20)
                swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = swatch

                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Duration Text",
                    rows = {
                        { type="slider", label="Text Size", min=6, max=26, step=1,
                          get=function() return ind.durationTextSize or 8 end,
                          set=function(v) ind.durationTextSize = v; ReloadAndUpdate() end },
                        { type="slider", label="Offset X", min=-20, max=20, step=1,
                          get=function() return ind.durationTextOffsetX or 0 end,
                          set=function(v) ind.durationTextOffsetX = v; ReloadAndUpdate() end },
                        { type="slider", label="Offset Y", min=-20, max=20, step=1,
                          get=function() return ind.durationTextOffsetY or 0 end,
                          set=function(v) ind.durationTextOffsetY = v; ReloadAndUpdate() end },
                    },
                })
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                cogBtn:SetAlpha(0.4)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
                cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            end

            -- Row 4: Show Stacks (+ swatch + cog) | Color (square only) / Hide Icons (icon only)
            local stacksRow = SettingsRow(
                { type="toggle", text="Show Stacks",
                  getValue=function() return ind.showStacks ~= false end,
                  setValue=function(v) ind.showStacks = v; ReloadAndUpdate() end },
                (indType == "square") and { type="label", text="Colors" }
                  or { type="toggle", text="Hide Icons",
                       tooltip="Hide the icon texture, border, and duration swipe, leaving only the stack count. Forces icon opacity, border, and duration swipe off.",
                       getValue=function() return ind.hideIcon == true end,
                       setValue=function(v) ind.hideIcon = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end })
            -- Inline swatch for stacks color
            do
                local rgn = stacksRow._leftRegion
                local swatch = EllesmereUI.BuildColorSwatch(
                    rgn, stacksRow:GetFrameLevel() + 3,
                    function()
                        local c = ind.stacksTextColor or { r=1, g=1, b=1 }
                        return c.r, c.g, c.b, 1
                    end,
                    function(r, g, b)
                        ind.stacksTextColor = { r=r, g=g, b=b }
                        ReloadAndUpdate()
                    end, false, 20)
                swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = swatch
            end
            do
                local rgn = stacksRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Stacks Text",
                    rows = {
                        { type="slider", label="Text Size", min=6, max=26, step=1,
                          get=function() return ind.stacksTextSize or 8 end,
                          set=function(v) ind.stacksTextSize = v; ReloadAndUpdate() end },
                        { type="slider", label="Offset X", min=-20, max=20, step=1,
                          get=function() return ind.stacksOffsetX or 0 end,
                          set=function(v) ind.stacksOffsetX = v; ReloadAndUpdate() end },
                        { type="slider", label="Offset Y", min=-20, max=20, step=1,
                          get=function() return ind.stacksOffsetY or 0 end,
                          set=function(v) ind.stacksOffsetY = v; ReloadAndUpdate() end },
                    },
                })
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                cogBtn:SetAlpha(0.15)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
                cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                cogBtn:SetScript("OnLeave", function(self)
                    self:SetAlpha((ind.showStacks ~= false) and 0.4 or 0.15)
                end)
                cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
                local function UpdateStacksCog()
                    local off = not (ind.showStacks ~= false)
                    cogBtn:SetAlpha(off and 0.15 or 0.4)
                    cogBtn:EnableMouse(not off)
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateStacksCog)
                UpdateStacksCog()
            end
            -- Per-ability color swatches in the right slot (square only). Each
            -- ability in the group gets its own swatch (tooltip = ability name).
            -- Abilities without a per-spell color fall back to the legacy single
            -- ind.color, then the default. Laid out right-to-left like every other
            -- inline swatch row; the first ability's swatch sits at the right edge.
            if indType == "square" then
                local rgn = stacksRow._rightRegion
                local DEFAULT_SQ = { r=0.05, g=0.82, b=0.62 }
                local prev = nil
                for _, sid in ipairs(ind.spells or {}) do
                    local mySid = sid
                    local swatch = EllesmereUI.BuildColorSwatch(
                        rgn, stacksRow:GetFrameLevel() + 3,
                        function()
                            local c = (ind.spellColors and ind.spellColors[mySid])
                                or ind.color or DEFAULT_SQ
                            return c.r, c.g, c.b, 1
                        end,
                        function(r, g, b)
                            if not ind.spellColors then ind.spellColors = {} end
                            ind.spellColors[mySid] = { r=r, g=g, b=b }
                            ReloadAndUpdate()
                        end, false, 20)
                    if prev then
                        swatch:SetPoint("RIGHT", prev, "LEFT", -8, 0)
                    else
                        swatch:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
                    end
                    prev = swatch
                    -- Tooltip: ability name so each swatch is identifiable.
                    local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(mySid)
                    if nm then
                        swatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(swatch, nm) end)
                        swatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    end
                end
                rgn._lastInline = prev
            end

            -- Max Duration: rescale the cooldown swipe to a fixed baseline (input =
            -- seconds) so buffs applied at varying durations are comparable. Inline
            -- toggle enables it; off by default, and off until a number is entered.
            local mdRow = SettingsRow(
                { type="input", text="Max Duration", inputWidth=56,
                  getValue=function() return ind.maxDuration and tostring(ind.maxDuration) or "" end,
                  setValue=function(txt)
                      local n = tonumber(txt)
                      ind.maxDuration = (n and n > 0) and n or nil
                      ReloadAndUpdate()
                  end },
                { type="label", text="" })
            EllesmereUI.BuildInlineToggle({
                region = mdRow._leftRegion,
                getValue = function() return ind.maxDurationEnabled == true end,
                setValue = function(v) ind.maxDurationEnabled = v end,
                onToggle = function() ReloadAndUpdate() end,
            })
            -- 12.1: no baseline/cap option on the engine duration bindings.
            if EllesmereUI.IS_121 then
                PTRSlotOverlay("Max Duration", mdRow._leftRegion)
            end

            -- THRESHOLD section (Enable, seconds, color, opacity)
            BuildThresholdRow(false)

        elseif typeInfo and typeInfo.placed then

            if indType == "bar" then
                -----------------------------------------------------------
                --  BAR: CORE
                -----------------------------------------------------------
                _, h = W:SectionHeader(leftFrame, "CORE", sy); sy = sy - h

                -- Row 1: Orientation | Own Only
                local oriRow = SettingsRow(
                    { type="dropdown", text="Orientation", values=ORIENT_VALUES, order=ORIENT_ORDER,
                      getValue=function() return ind.orientation or "HORIZONTAL" end,
                      -- RefreshPage(true) = full rebuild so the Width/Height +
                      -- Full Width/Height labels re-evaluate isVert and flip live
                      -- (the fast path only re-reads values, not static labels).
                      setValue=function(v) ind.orientation = v; ReloadAndUpdate(); EllesmereUI:RefreshPage(true) end },
                    { type="dropdown", text="Own Only",
                      values={ __placeholder = "All" }, order={ "__placeholder" },
                      getValue=function() return "__placeholder" end,
                      setValue=function() end })
                -- Replace right with own only CB dropdown
                do
                    local ownItems = {}
                    if ind.spells then
                        for _, sid in ipairs(ind.spells) do
                            ownItems[#ownItems + 1] = {
                                key = tostring(sid),
                                label = SPELL_NAME_BY_ID[sid] or tostring(sid),
                    icon = GetSpellIcon(sid), iconSize = DD_SPELL_ICON_SIZE,
                            }
                        end
                    end
                    table.sort(ownItems, function(a, b) return a.label < b.label end)
                    if #ownItems > 0 then
                        local ownMeasure = leftFrame:CreateFontString(nil, "OVERLAY")
                        ownMeasure:SetFont(fontPath, 13, "")
                        local ownMaxW3 = 0
                        for _, item in ipairs(ownItems) do
                            ownMeasure:SetText(item.label)
                            local tw = ownMeasure:GetStringWidth()
                            if tw > ownMaxW3 then ownMaxW3 = tw end
                        end
                        ownMeasure:Hide()
                        local ownMenuW3 = max(170, ownMaxW3 + 60)
                        local rgn = oriRow._rightRegion
                        if rgn._control then rgn._control:Hide() end
                        local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                            rgn, ownMenuW3, rgn:GetFrameLevel() + 2,
                            ownItems,
                            function(k)
                                local sid = tonumber(k)
                                if ind.ownOnlySpells and ind.ownOnlySpells[sid] ~= nil then
                                    return ind.ownOnlySpells[sid]
                                end
                                return ind.ownOnly ~= false
                            end,
                            function(k, v)
                                local sid = tonumber(k)
                                if not ind.ownOnlySpells then ind.ownOnlySpells = {} end
                                ind.ownOnlySpells[sid] = v
                                ReloadAndUpdate()
                            end)
                        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
                        rgn._control = cbDD
                        rgn._lastInline = nil
                        AttachOwnAllSpecsCog(rgn, ind)
                    end
                end

                -- Row 2: Position (+ cog) | Reverse Fill
                local posRow = SettingsRow(
                    { type="dropdown", text="Position", values=POSITION_VALUES, order=POSITION_ORDER,
                      getValue=function() return ind.position or "TOPLEFT" end,
                      setValue=function(v)
                          ind.position = v
                          ReloadAndUpdate()
                          EllesmereUI:RefreshPage()
                      end },
                    { type="toggle", text="Reverse Fill",
                      getValue=function() return ind.reverseFill or false end,
                      setValue=function(v) ind.reverseFill = v; ReloadAndUpdate() end })
                -- Cog for offset X/Y
                do
                    local rgn = posRow._leftRegion
                    local _, cogShow = EllesmereUI.BuildCogPopup({
                        title = "Position Offset",
                        rows = {
                            { type="slider", label="Offset X", min=-50, max=50, step=1,
                              get=function() return ind.offsetX or 0 end,
                              set=function(v) ind.offsetX = v; ReloadAndUpdate() end },
                            { type="slider", label="Offset Y", min=-50, max=50, step=1,
                              get=function() return ind.offsetY or 0 end,
                              set=function(v) ind.offsetY = v; ReloadAndUpdate() end },
                            { type="dropdown", label="Frame Level", values=FRAMELVL_VALUES, order=FRAMELVL_ORDER,
                              get=function() return ind.frameLevel or "behindBorders" end,
                              set=function(v) ind.frameLevel = v; ReloadAndUpdate() end },
                        },
                    })
                    local cogBtn = CreateFrame("Button", nil, rgn)
                    cogBtn:SetSize(26, 26)
                    cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                    rgn._lastInline = cogBtn
                    cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                    cogBtn:SetAlpha(0.4)
                    local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                    cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
                    cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                    cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                    cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
                end

                -----------------------------------------------------------
                --  BAR: DISPLAY
                -----------------------------------------------------------
                _, h = W:SectionHeader(leftFrame, "DISPLAY", sy); sy = sy - h

                local isVert = (ind.orientation or "HORIZONTAL") == "VERTICAL"

                -- Row 1: Width | Height (labels flip with orientation so each
                -- slot always names the on-screen axis being edited). Each slider
                -- is disabled while its matching Full toggle is on.
                SettingsRow(
                    { type="slider", text=isVert and "Height" or "Width", min=5, max=200, step=1,
                      disabled=function() return ind.barFullWidth end,
                      disabledTooltip=isVert and "Full Height Bar" or "Full Width Bar", requireState="disabled",
                      getValue=function() return ind.barWidth or 30 end,
                      setValue=function(v) ind.barWidth = v; ReloadAndUpdate() end },
                    { type="slider", text=isVert and "Width" or "Height", min=1, max=100, step=1,
                      disabled=function() return ind.barFullHeight end,
                      disabledTooltip=isVert and "Full Width Bar" or "Full Height Bar", requireState="disabled",
                      getValue=function() return ind.barHeight or 4 end,
                      setValue=function(v) ind.barHeight = v; ReloadAndUpdate() end })

                -- Row 1b: Full Width | Full Height (labels flip with orientation,
                -- matching the sliders; the render spans the matching screen axis).
                -- RefreshPage() so the Width/Height disabled state updates live.
                SettingsRow(
                    { type="toggle", text=isVert and "Full Height Bar" or "Full Width Bar",
                      getValue=function() return ind.barFullWidth or false end,
                      setValue=function(v) ind.barFullWidth = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                    { type="toggle", text=isVert and "Full Width Bar" or "Full Height Bar",
                      getValue=function() return ind.barFullHeight or false end,
                      setValue=function(v) ind.barFullHeight = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end })

                -- Row 2: Color | Background (both: opacity slider + inline swatch)
                local barBgRow = SettingsRow(
                    { type="slider", text="Color", min=0, max=100, step=1, trackWidth=120,
                      getValue=function() return ind.barColorOpacity or 100 end,
                      setValue=function(v) ind.barColorOpacity = v; ReloadAndUpdate() end },
                    { type="slider", text="Background", min=0, max=100, step=1, trackWidth=120,
                      getValue=function() return ind.barBgOpacity or 50 end,
                      setValue=function(v) ind.barBgOpacity = v; ReloadAndUpdate() end })
                do
                    local rgn = barBgRow._leftRegion
                    local colorSwatch = EllesmereUI.BuildColorSwatch(
                        rgn, barBgRow:GetFrameLevel() + 3,
                        function()
                            local c = ind.color or { r=0x0C/255, g=0xD2/255, b=0x9D/255 }
                            return c.r, c.g, c.b, 1
                        end,
                        function(r, g, b)
                            ind.color = { r=r, g=g, b=b }
                            ReloadAndUpdate()
                        end, false, 20)
                    colorSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                    rgn._lastInline = colorSwatch
                end
                do
                    local rgn = barBgRow._rightRegion
                    local bgSwatch = EllesmereUI.BuildColorSwatch(
                        rgn, barBgRow:GetFrameLevel() + 3,
                        function()
                            local c = ind.barBgColor or { r=0, g=0, b=0 }
                            return c.r, c.g, c.b, 1
                        end,
                        function(r, g, b)
                            ind.barBgColor = { r=r, g=g, b=b }
                            ReloadAndUpdate()
                        end, false, 20)
                    bgSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                    rgn._lastInline = bgSwatch
                end

                -- Max Duration: rescale the bar fill to a fixed baseline (input =
                -- seconds) so buffs applied at varying durations are comparable.
                -- Inline toggle enables it; off by default, off until a number is set.
                local mdRow = SettingsRow(
                    { type="input", text="Max Duration", inputWidth=56,
                      getValue=function() return ind.maxDuration and tostring(ind.maxDuration) or "" end,
                      setValue=function(txt)
                          local n = tonumber(txt)
                          ind.maxDuration = (n and n > 0) and n or nil
                          ReloadAndUpdate()
                      end },
                    { type="label", text="" })
                EllesmereUI.BuildInlineToggle({
                    region = mdRow._leftRegion,
                    getValue = function() return ind.maxDurationEnabled == true end,
                    setValue = function(v) ind.maxDurationEnabled = v end,
                    onToggle = function() ReloadAndUpdate() end,
                })
                -- 12.1: no baseline/cap option on the engine duration bindings.
                if EllesmereUI.IS_121 then
                    PTRSlotOverlay("Max Duration", mdRow._leftRegion)
                end

                -- THRESHOLD section (Enable, seconds, color, opacity)
                BuildThresholdRow(false)

            elseif indType == "square" then
                -- Square uses icon/square path above (handled in the if block)
                -- This branch shouldn't be reached for square since it's handled above

            else
                -- Other placed types (future): Position + cog
                local posRow = SettingsRow(
                    { type="dropdown", text="Position", values=POSITION_VALUES, order=POSITION_ORDER,
                      getValue=function() return ind.position or "TOPLEFT" end,
                      setValue=function(v)
                          ind.position = v
                          ReloadAndUpdate()
                          EllesmereUI:RefreshPage()
                      end },
                    { type="label", text="" })
                do
                    local rgn = posRow._leftRegion
                    local _, cogShow = EllesmereUI.BuildCogPopup({
                        title = "Position Offset",
                        rows = {
                            { type="slider", label="Offset X", min=-50, max=50, step=1,
                              get=function() return ind.offsetX or 0 end,
                              set=function(v) ind.offsetX = v; ReloadAndUpdate() end },
                            { type="slider", label="Offset Y", min=-50, max=50, step=1,
                              get=function() return ind.offsetY or 0 end,
                              set=function(v) ind.offsetY = v; ReloadAndUpdate() end },
                        },
                    })
                    local cogBtn = CreateFrame("Button", nil, rgn)
                    cogBtn:SetSize(26, 26)
                    cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                    rgn._lastInline = cogBtn
                    cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                    cogBtn:SetAlpha(0.4)
                    local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                    cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
                    cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                    cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                    cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
                end
                BuildOwnOnlyRow()
            end

        else
            -- Frame effects: healthcolor, border, framealpha

            if indType == "border" then
                -----------------------------------------------------------
                --  FRAME BORDER: CORE
                -----------------------------------------------------------
                _, h = W:SectionHeader(leftFrame, "CORE", sy); sy = sy - h

                -- Row 1: Show When | Own Only
                local swRow = SettingsRow(
                    { type="dropdown", text="Show When", values=SHOW_WHEN_VALUES, order=SHOW_WHEN_ORDER,
                      getValue=function() return ind.showWhen or "present" end,
                      setValue=function(v) ind.showWhen = v; ReloadAndUpdate() end },
                    { type="dropdown", text="Own Only",
                      values={ __placeholder = "All" }, order={ "__placeholder" },
                      getValue=function() return "__placeholder" end,
                      setValue=function() end })
                -- Replace right with own only CB dropdown
                do
                    local ownItems = {}
                    if ind.spells then
                        for _, sid in ipairs(ind.spells) do
                            ownItems[#ownItems + 1] = {
                                key = tostring(sid),
                                label = SPELL_NAME_BY_ID[sid] or tostring(sid),
                    icon = GetSpellIcon(sid), iconSize = DD_SPELL_ICON_SIZE,
                            }
                        end
                    end
                    table.sort(ownItems, function(a, b) return a.label < b.label end)
                    if #ownItems > 0 then
                        local ownMeasure = leftFrame:CreateFontString(nil, "OVERLAY")
                        ownMeasure:SetFont(fontPath, 13, "")
                        local ownMaxW4 = 0
                        for _, item in ipairs(ownItems) do
                            ownMeasure:SetText(item.label)
                            local tw = ownMeasure:GetStringWidth()
                            if tw > ownMaxW4 then ownMaxW4 = tw end
                        end
                        ownMeasure:Hide()
                        local ownMenuW4 = max(170, ownMaxW4 + 60)
                        local rgn = swRow._rightRegion
                        if rgn._control then rgn._control:Hide() end
                        local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                            rgn, ownMenuW4, rgn:GetFrameLevel() + 2,
                            ownItems,
                            function(k)
                                local sid = tonumber(k)
                                if ind.ownOnlySpells and ind.ownOnlySpells[sid] ~= nil then
                                    return ind.ownOnlySpells[sid]
                                end
                                return ind.ownOnly ~= false
                            end,
                            function(k, v)
                                local sid = tonumber(k)
                                if not ind.ownOnlySpells then ind.ownOnlySpells = {} end
                                ind.ownOnlySpells[sid] = v
                                ReloadAndUpdate()
                            end)
                        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
                        rgn._control = cbDD
                        rgn._lastInline = nil
                        AttachOwnAllSpecsCog(rgn, ind)
                    end
                end

                -----------------------------------------------------------
                --  FRAME BORDER: DISPLAY
                -----------------------------------------------------------
                _, h = W:SectionHeader(leftFrame, "DISPLAY", sy); sy = sy - h

                -- Row 1: Border Width | Color (opacity slider + inline swatch)
                local ac = EllesmereUI.ACCENT_COLOR or { r = 0.05, g = 0.82, b = 0.62 }
                local bdrColorRow = SettingsRow(
                    { type="slider", text="Border Width", min=1, max=6, step=1, trackWidth=120,
                      getValue=function() return ind.borderWidth or 2 end,
                      setValue=function(v) ind.borderWidth = v; ReloadAndUpdate() end },
                    { type="slider", text="Color", min=0, max=100, step=1, trackWidth=120,
                      getValue=function() return ind.borderOpacity or 100 end,
                      setValue=function(v) ind.borderOpacity = v; ReloadAndUpdate() end })
                do
                    local rgn = bdrColorRow._rightRegion
                    local colorSwatch = EllesmereUI.BuildColorSwatch(
                        rgn, bdrColorRow:GetFrameLevel() + 3,
                        function()
                            local c = ind.color or { r=ac.r, g=ac.g, b=ac.b }
                            return c.r, c.g, c.b, 1
                        end,
                        function(r, g, b)
                            ind.color = { r=r, g=g, b=b }
                            ReloadAndUpdate()
                        end, false, 20)
                    colorSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                    rgn._lastInline = colorSwatch
                end

                -- THRESHOLD section (Enable, seconds, color, opacity)
                BuildThresholdRow(false)

            elseif indType == "healthcolor" then
                -----------------------------------------------------------
                --  HEALTH BAR COLOR: CORE
                -----------------------------------------------------------
                _, h = W:SectionHeader(leftFrame, "CORE", sy); sy = sy - h

                -- Row 1: Show When | Own Only
                local hcSwRow = SettingsRow(
                    { type="dropdown", text="Show When", values=SHOW_WHEN_VALUES, order=SHOW_WHEN_ORDER,
                      getValue=function() return ind.showWhen or "present" end,
                      setValue=function(v) ind.showWhen = v; ReloadAndUpdate() end },
                    { type="dropdown", text="Own Only",
                      values={ __placeholder = "All" }, order={ "__placeholder" },
                      getValue=function() return "__placeholder" end,
                      setValue=function() end })
                -- Replace right with own only CB dropdown
                do
                    local ownItems = {}
                    if ind.spells then
                        for _, sid in ipairs(ind.spells) do
                            ownItems[#ownItems + 1] = {
                                key = tostring(sid),
                                label = SPELL_NAME_BY_ID[sid] or tostring(sid),
                    icon = GetSpellIcon(sid), iconSize = DD_SPELL_ICON_SIZE,
                            }
                        end
                    end
                    table.sort(ownItems, function(a, b) return a.label < b.label end)
                    if #ownItems > 0 then
                        local ownMeasure = leftFrame:CreateFontString(nil, "OVERLAY")
                        ownMeasure:SetFont(fontPath, 13, "")
                        local ownMaxW5 = 0
                        for _, item in ipairs(ownItems) do
                            ownMeasure:SetText(item.label)
                            local tw = ownMeasure:GetStringWidth()
                            if tw > ownMaxW5 then ownMaxW5 = tw end
                        end
                        ownMeasure:Hide()
                        local ownMenuW5 = max(170, ownMaxW5 + 60)
                        local rgn = hcSwRow._rightRegion
                        if rgn._control then rgn._control:Hide() end
                        local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                            rgn, ownMenuW5, rgn:GetFrameLevel() + 2,
                            ownItems,
                            function(k)
                                local sid = tonumber(k)
                                if ind.ownOnlySpells and ind.ownOnlySpells[sid] ~= nil then
                                    return ind.ownOnlySpells[sid]
                                end
                                return ind.ownOnly ~= false
                            end,
                            function(k, v)
                                local sid = tonumber(k)
                                if not ind.ownOnlySpells then ind.ownOnlySpells = {} end
                                ind.ownOnlySpells[sid] = v
                                ReloadAndUpdate()
                            end)
                        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
                        rgn._control = cbDD
                        rgn._lastInline = nil
                        AttachOwnAllSpecsCog(rgn, ind)
                    end
                end

                -----------------------------------------------------------
                --  HEALTH BAR COLOR: DISPLAY
                -----------------------------------------------------------
                _, h = W:SectionHeader(leftFrame, "DISPLAY", sy); sy = sy - h

                -- Row 1: Color | Opacity
                SettingsRow(
                    { type="colorpicker", text="Color", hasAlpha=false,
                      getValue=function()
                          local c = ind.color or { r=0x0C/255, g=0xD2/255, b=0x9D/255 }
                          return c.r, c.g, c.b
                      end,
                      setValue=function(r, g, b)
                          ind.color = { r=r, g=g, b=b }
                          ReloadAndUpdate()
                      end },
                    { type="slider", text="Opacity", min=5, max=100, step=1,
                      getValue=function() return ind.opacity or 100 end,
                      setValue=function(v) ind.opacity = v; ReloadAndUpdate() end })

                -- THRESHOLD section (Enable, seconds, color, opacity)
                BuildThresholdRow(false)

            else
                -- framealpha
                -----------------------------------------------------------
                --  FRAME ALPHA: CORE
                -----------------------------------------------------------
                _, h = W:SectionHeader(leftFrame, "CORE", sy); sy = sy - h

                -- Row 1: Show When | Own Only
                local faSwRow = SettingsRow(
                    { type="dropdown", text="Show When", values=SHOW_WHEN_VALUES, order=SHOW_WHEN_ORDER,
                      getValue=function() return ind.showWhen or "present" end,
                      setValue=function(v) ind.showWhen = v; ReloadAndUpdate() end },
                    { type="dropdown", text="Own Only",
                      values={ __placeholder = "All" }, order={ "__placeholder" },
                      getValue=function() return "__placeholder" end,
                      setValue=function() end })
                -- Replace right with own only CB dropdown
                do
                    local ownItems = {}
                    if ind.spells then
                        for _, sid in ipairs(ind.spells) do
                            ownItems[#ownItems + 1] = {
                                key = tostring(sid),
                                label = SPELL_NAME_BY_ID[sid] or tostring(sid),
                    icon = GetSpellIcon(sid), iconSize = DD_SPELL_ICON_SIZE,
                            }
                        end
                    end
                    table.sort(ownItems, function(a, b) return a.label < b.label end)
                    if #ownItems > 0 then
                        local ownMeasure = leftFrame:CreateFontString(nil, "OVERLAY")
                        ownMeasure:SetFont(fontPath, 13, "")
                        local ownMaxW6 = 0
                        for _, item in ipairs(ownItems) do
                            ownMeasure:SetText(item.label)
                            local tw = ownMeasure:GetStringWidth()
                            if tw > ownMaxW6 then ownMaxW6 = tw end
                        end
                        ownMeasure:Hide()
                        local ownMenuW6 = max(170, ownMaxW6 + 60)
                        local rgn = faSwRow._rightRegion
                        if rgn._control then rgn._control:Hide() end
                        local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                            rgn, ownMenuW6, rgn:GetFrameLevel() + 2,
                            ownItems,
                            function(k)
                                local sid = tonumber(k)
                                if ind.ownOnlySpells and ind.ownOnlySpells[sid] ~= nil then
                                    return ind.ownOnlySpells[sid]
                                end
                                return ind.ownOnly ~= false
                            end,
                            function(k, v)
                                local sid = tonumber(k)
                                if not ind.ownOnlySpells then ind.ownOnlySpells = {} end
                                ind.ownOnlySpells[sid] = v
                                ReloadAndUpdate()
                            end)
                        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
                        rgn._control = cbDD
                        rgn._lastInline = nil
                        AttachOwnAllSpecsCog(rgn, ind)
                    end
                end

                -----------------------------------------------------------
                --  FRAME ALPHA: DISPLAY
                -----------------------------------------------------------
                _, h = W:SectionHeader(leftFrame, "DISPLAY", sy); sy = sy - h

                -- Row 1: Alpha | empty
                SettingsRow(
                    { type="slider", text="Alpha", min=5, max=100, step=1,
                      getValue=function() return floor((ind.alpha or 0.4) * 100) end,
                      setValue=function(v) ind.alpha = v / 100; ReloadAndUpdate() end },
                    { type="label", text="" })
                -- Frame Alpha has no Threshold section: its alpha multiplies with
                -- the range-fade alpha and two secret values can't be combined.
            end
        end
    else
        if selectedSpecKey then
            settingsTitle:SetText(EllesmereUI.L("Create an indicator to get started."))
        else
            settingsTitle:SetText(EllesmereUI.L("Select a spec above."))
        end
        settingsTitle:SetTextColor(0.4, 0.4, 0.4)
        spellsTitle:SetText("")
    end

    -- Size the settings scroll child to its built content + sync the scrollbar.
    settingsChild:SetHeight(max(viewportH, math.abs(sy) + 12))
    UpdateThumb()

    -- Size the sidebar scroll child to its content (tiles + Add New button)
    local sidebarContentH = max(10, math.abs(tileY))
    sidebarChild:SetHeight(sidebarContentH)

    -- Return exactly the visible height so the outer scroll frame has no scroll range
    -- Return 0: content lives on scrollFrame directly, not scroll child
    return 0
end

-------------------------------------------------------------------------------
--  TEMP DEBUG: /euifreedom [unit]  (default target, falls back to player)
--  Prints every HELPFUL aura's id/name (SECRET when hidden), its four-filter
--  fingerprint, what BM_IdentifySecretAura resolves it to, and whether the
--  EXTERNAL_DEFENSIVE filter passes -- plus the active spec key and its
--  registered signature table. Remove after the Freedom investigation.
-------------------------------------------------------------------------------
do
    local function SafeStr(v)
        if v == nil then return "nil" end
        if issecretvalue and issecretvalue(v) then return "SECRET" end
        return tostring(v)
    end
    SLASH_EUIFREEDOM1 = "/euifreedom"
    SlashCmdList["EUIFREEDOM"] = function(msg)
        local unit = (msg and msg ~= "" and msg) or "target"
        if not UnitExists(unit) then unit = "player" end
        print("|cff0cd29fEUI Freedom debug|r unit=" .. unit
            .. "  specKey=" .. tostring(activeSpecKey_BM)
            .. "  borrow=" .. tostring(activeBorrow_BM and "yes" or "no"))
        if activeSpecKey_BM then
            local sigs = GetSpecSignatures(activeSpecKey_BM)
            local parts = {}
            for k, v in pairs(sigs) do parts[#parts + 1] = k .. "->" .. tostring(v) end
            print("  registered sigs: " .. (next(parts) and table.concat(parts, "  ") or "none"))
        end
        local i = 1
        while true do
            local ad = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not ad then break end
            local iid = ad.auraInstanceID
            local sig = iid and MakeSignature(unit, iid) or "noIID"
            local ident = iid and ns.BM_IdentifySecretAura and ns.BM_IdentifySecretAura(unit, iid)
            local ext = iid and not C_UnitAuras_IsAuraFilteredOutByInstanceID(unit, iid, "HELPFUL|EXTERNAL_DEFENSIVE")
            print(("  #%d id=%s name=%s sig=%s ident=%s extFilter=%s"):format(
                i, SafeStr(ad.spellId), SafeStr(ad.name), tostring(sig),
                tostring(ident), tostring(ext)))
            i = i + 1
        end
    end
end
