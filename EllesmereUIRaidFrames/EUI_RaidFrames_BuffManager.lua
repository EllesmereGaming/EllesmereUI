if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_BuffManager.lua
--  Indicator-centric buff manager: icon/square/bar/healthcolor/border/framealpha
--  indicators take whitelisted healer spells + position/size/color/growth (max
--  20/spec). Rendered by the aura containers (EUI_RaidFrames_AuraContainers.lua)
--  from the indicator config; no per-frame allocs (wipe + reuse).
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
    { key = "bgcolor",     name = "Background Color", placed = false },
    { key = "border",      name = "Frame Border",     placed = false },
    { key = "framealpha",  name = "Frame Alpha",      placed = false },
}

local INDICATOR_TYPE_MAP = {}
for _, t in ipairs(INDICATOR_TYPES) do INDICATOR_TYPE_MAP[t.key] = t end

local INDICATOR_TYPE_VALUES = {}
local INDICATOR_TYPE_ORDER = {}
for _, t in ipairs(INDICATOR_TYPES) do
    INDICATOR_TYPE_VALUES[t.key] = t.name
    -- Frame Alpha cannot be created: fading the frame needs per-aura presence, which is secret in combat. Existing ones stay listed.
    local skipType = (t.key == "framealpha")
    if not skipType then
        INDICATOR_TYPE_ORDER[#INDICATOR_TYPE_ORDER + 1] = t.key
    end
end
-- Insert divider after "bar"
tinsert(INDICATOR_TYPE_ORDER, 4, "---")

-- Gray blocking overlay + red removal notice for settings whose backing
-- machinery has no aura-container equivalent (styled after the party-tab sync
-- overlays). UI-only (the runtime side of these settings is inert elsewhere);
-- callers anchor the returned frame.
local function BuildPTROverlay(parentFrame, label, fontSize)
    local ov = CreateFrame("Frame", nil, parentFrame)
    ov._searchIgnore = true -- inline search must never re-anchor/collapse it
    ov:SetFrameLevel(parentFrame:GetFrameLevel() + 60)
    ov:EnableMouse(true)
    local bg = ov:CreateTexture(nil, "OVERLAY")
    bg:SetAllPoints()
    bg:SetColorTexture(0.10, 0.10, 0.12, 0.95)
    local fs = ov:CreateFontString(nil, "OVERLAY")
    local fp = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
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

local GROW_VALUES = {
    RIGHT  = "Right",
    LEFT   = "Left",
    UP     = "Up",
    DOWN   = "Down",
    CENTER = "Center",
}
local GROW_ORDER = { "RIGHT", "LEFT", "UP", "DOWN", "CENTER" }

local ORIENT_VALUES = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }
local ORIENT_ORDER = { "HORIZONTAL", "VERTICAL" }

-- Show when mode (for frame effects)
local SHOW_WHEN_VALUES = { present = "When Any Present", allPresent = "When All Present", anyMissing = "When Any Missing", missing = "When All Missing" }
local SHOW_WHEN_ORDER = { "present", "allPresent", "anyMissing", "missing" }
-- Effect indicators (healthcolor/bgcolor/border) on 12.1 support ONLY the
-- presence-driven mode. The engine renders present auras; absence logic would
-- need visibility hooks on its buttons, which it forbids (secret SetShown
-- throws on scripted buttons -- field, 2026-08-14). The full four-mode list
-- previously offered here made the other modes silently render NOTHING.
-- Stale saved modes render presence-driven via the runtime heal in
-- EUI_RaidFrames_AuraContainers.lua's effect branch.
local SHOW_WHEN_VALUES_EFFECT = { present = "When Any Present" }
local SHOW_WHEN_ORDER_EFFECT = { "present" }
local SHOW_WHEN_EFFECT_TIP = "Effect indicators show while a tracked buff is present. Absence-based modes are not available in 12.1."

-- Indicator frame level, relative to the unit button. Icon/Square: own border at base+1, count/duration text carrier pinned at +18 regardless of mode; bars use the base only (no sub-frames).
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
--  Healer spell database. hide=true: alt spell ID for the same aura, UI-skipped.
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
            { id = 102342, name = "Ironbark" },
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
            { id = 33206,   name = "Pain Suppression" },
            { id = 10060,   name = "Power Infusion" },
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
            { id = 47788, name = "Guardian Spirit" },
            { id = 10060, name = "Power Infusion" },
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
            { id = 116849, name = "Life Cocoon" },
            { id = 443113, name = "Strength of the Black Ox" },
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
            { id = 1022,    name = "Blessing of Protection" },
            { id = 432502,  name = "Holy Armaments" },
            { id = 6940,    name = "Blessing of Sacrifice" },
            { id = 1044,    name = "Blessing of Freedom" },
            { id = 431381,  name = "Dawnlight" },
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
            { id = 357170, name = "Time Dilation" },
            { id = 363534, name = "Rewind" },
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
            { id = 361021, name = "Sense Power" },
            -- 361021 is the caster's own permanent toggle buff; 361022 is the
            -- effect that lands on whichever ally triggers Sense Power's
            -- "powerful ability" detection. Distinct spell IDs, same client
            -- display name -- kept as separate entries so both are
            -- selectable (see SPELL_NAME_BY_ID for how the UI tells them apart).
            { id = 361022, name = "Sense Power (Ally)" },
        },
    },
}

ns.BM_HEALER_SPECS = HEALER_SPECS

-- Spec lookup by key and by spec ID (locale-independent identifier).
local SPEC_BY_KEY = {}
local SPEC_BY_ID  = {}
for _, spec in ipairs(HEALER_SPECS) do
    SPEC_BY_KEY[spec.key] = spec
    if spec.specID then SPEC_BY_ID[spec.specID] = spec end
end

-- Non-healer specs that can cast a tracked buff borrow a healer spec's
-- indicator placements but show only their own spells: Ele/Enh -> Resto
-- (Earth Shield); Prot/Ret -> Holy (Freedom). Keyed by spec ID; spells = the
-- primary spell IDs indicators reference.
local BORROW_SPECS = {
    [262] = { source = "SHAMAN_RESTORATION", spells = { [974] = true } },  -- Elemental
    [263] = { source = "SHAMAN_RESTORATION", spells = { [974] = true } },  -- Enhancement
    [66]  = { source = "PALADIN_HOLY", spells = { [1044] = true } },       -- Protection
    [70]  = { source = "PALADIN_HOLY", spells = { [1044] = true } },       -- Retribution
}

-- Resolve the player's CURRENT spec to a BM spec key. MUST match by spec ID,
-- never name: GetSpecializationInfo() returns the stable non-localized ID first,
-- the LOCALIZED name second, so name-matching silently kills every indicator
-- on non-English clients. nil = not tracked.
-- Borrowing resolver (Ret/Prot -> Holy, Ele/Enh -> Resto): the v2 indicator
-- system must NEVER route through it -- v2's active bucket resolves borrow-free via BM2_SpecKey /
-- BM_SpecKeyForSpecID (maintainer ruling 2026-08-13: Ret/Prot/Ele/Enh edit and
-- render the shared All Non Healers/Aug bucket, not the borrowed healer's).
local function CurrentSpecKey()
    local specIdx = GetSpecialization and GetSpecialization()
    if not specIdx then return nil end
    local specID = GetSpecializationInfo and GetSpecializationInfo(specIdx)
    if not specID then return nil end
    -- Borrow specs resolve to the spec they reuse, so options + lookup tables operate on that shared configuration.
    local borrow = BORROW_SPECS[specID]
    if borrow then return borrow.source end
    local spec = SPEC_BY_ID[specID]
    return spec and spec.key or nil
end
ns.BM_CurrentSpecKey = CurrentSpecKey

-- Healer/support key for a specialization ID WITHOUT borrow resolution.
-- nil = not in the healer/Aug list (so the spec owns a "spec<ID>" bucket).
function ns.BM_SpecKeyForSpecID(specID)
    local spec = SPEC_BY_ID[specID]
    return spec and spec.key or nil
end

-- Role GROUP bucket for a specialization ID: membership in the healer/Aug
-- list wins ("healers" -- keeps the complement exactly equal to the All Non
-- Healers/Aug bucket), then TANK role -> "tanks", everything else -> "dps".
-- Shared by the Buff Manager v2 union, the Debuff Manager union and both
-- pages' editing-spec rosters. nil specID = no bucket (no spec yet).
function ns.BM_RoleBucketForSpecID(specID)
    if not specID then return nil end
    if SPEC_BY_ID[specID] then return "healers" end
    local role = GetSpecializationInfoByID and select(5, GetSpecializationInfoByID(specID))
    if role == "TANK" then return "tanks" end
    if role then return "dps" end
    -- Unknown spec/unavailable API: no role bucket at all beats silently
    -- classing a tank as DPS.
    return nil
end

-- Curated display names by spell ID (from the spec lists above)
local STORED_NAME_BY_ID = {}
for _, spec in ipairs(HEALER_SPECS) do
    for _, spell in ipairs(spec.spells) do
        if not spell.hide then
            STORED_NAME_BY_ID[spell.id] = spell.name
        end
    end
end
-- 212641 is Guardian of Ancient Kings with Glyph of the Queen applied; Blizzard's
-- client reports it under the same name as the base buff (86659).
STORED_NAME_BY_ID[212641] = "Guardian of Ancient Kings (Glyph of the Queen)"
-- Display-name lookup. Curated names win: they distinguish variants the client
-- API cannot ("Echo Reversion" vs "Reversion") and localize via L(); the client
-- name is the uncurated fallback. No cache -- L() must stay live for locale swaps.
local SPELL_NAME_BY_ID = setmetatable({}, {
    __index = function(_, id)
        local nm = STORED_NAME_BY_ID[id]
        if nm then return EllesmereUI.L(nm) end
        return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    end,
})
-- Shared with EllesmereUIOptions/EUI_RaidFrames_ManagerPages.lua (same ns):
-- the Filter Editor and its dropdowns build spell row labels off this too, so
-- curated names (e.g. distinguishing two client-side-identical spell names)
-- apply there as well, not just in this file's own dropdowns.
ns.SPELL_NAME_BY_ID = SPELL_NAME_BY_ID

local SPEC_DD_VALUES = {}
local SPEC_DD_ORDER = {}
for _, spec in ipairs(HEALER_SPECS) do
    SPEC_DD_VALUES[spec.key] = spec.name
    SPEC_DD_ORDER[#SPEC_DD_ORDER + 1] = spec.key
end

-- GROUP buckets of the editing-spec dropdown (core list, shared with the
-- Debuff Manager and Player Aura Bars rosters): shared unions whose
-- indicators render across every matching spec (concrete specs show them as
-- inherited tiles with a per-spec enable).
ns.BM_GROUP_BUCKET_INFO = EllesmereUI.SPEC_GROUP_BUCKET_INFO

-- Group buckets a CONCRETE bucket (healer spec key or "spec<ID>") inherits
-- from, in display order: All Specs always, All Non Healers/Aug for
-- non-healer specs, then the spec's role group. nil for group buckets and
-- unknown keys (nothing inherits there). Membership tests the SPEC (tracked
-- or not), never the key shape: the Debuff Manager views healer specs
-- through "spec<ID>" keys too.
function ns.BM_InheritedGroupsFor(bucketKey)
    local hs = bucketKey and SPEC_BY_KEY[bucketKey]
    local sid = hs and hs.specID
    if not sid then
        local m = type(bucketKey) == "string" and bucketKey:match("^spec(%d+)$")
        sid = m and tonumber(m)
    end
    if not sid then return nil end
    local out = { "allspecs" }
    if not SPEC_BY_ID[sid] then out[#out + 1] = "nonhealer" end
    local roleKey = ns.BM_RoleBucketForSpecID(sid)
    if roleKey then out[#out + 1] = roleKey end
    return out
end

-- Sidebar/preview id offsets per group bucket: every bucket allocates ids
-- from the same base, so unioned DISPLAY lists shift inherited entries into
-- unique ranges (the runtime union in BM2_SpecIndicators carries its own
-- offsets). Role groups never co-occur, so they share one slot.
ns.BM_INH_OFFSETS = {
    allspecs = 2000000, nonhealer = 4000000,
    tanks = 3000000, dps = 3000000, healers = 3000000,
}

-- Alternate aura spell IDs resolving to a primary tracked ID (Earth Shield applies 383648, indicators use 974; Ebon Might self-buff 395296 vs ally 395152). Resolved at scan time so saved indicators match with no migration.
local PRIMARY_BY_ALT = {
    [383648] = 974,     -- Earth Shield
    [395296] = 395152,  -- Ebon Might (caster self-buff)
}

-- Active spec only: checking every spec of the class causes cross-spec bleed
-- (Disc seeing Holy indicators) and cross-class collisions.
local activeSpecKey_BM = nil

local function DetectActiveSpecKey()
    -- By spec ID (locale-independent); nil for non-tracked specs clears tracking.
    activeSpecKey_BM = CurrentSpecKey()
end

DetectActiveSpecKey()

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
    elseif indType == "bgcolor" then
        ind.ownOnly          = true
        ind.color    = { r = 0, g = 1, b = 0 }
        ind.opacity  = 100
        ind.showWhen = "present"
    elseif indType == "border" then
        ind.ownOnly          = true
        local _ac = EllesmereUI and EllesmereUI.ACCENT_COLOR
        ind.color       = _ac and { r = _ac.r, g = _ac.g, b = _ac.b } or { r = 0.05, g = 0.82, b = 0.62 }
        ind.borderStyle = "solid"
        ind.borderWidth = 2
        ind.borderDashCount = 8
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

-- Preview cooldown seeds keyed "frameIdx:spellID": fraction remaining 0.2-0.9, generated once and reused.
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
        { pos = "TOPRIGHT", spells = { 413984, 410263, 410686, 395152, 361021 } }, -- Shifting Sands, Infernos Blessing, Symbiotic Bloom, Ebon Might, Sense Power
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

-- Legacy->v2 import inputs: preset table + factory, used to detect untouched default spec buckets.
ns.BM_DefaultIndicators = DEFAULT_INDICATORS
ns.BM_NewIndicator = NewIndicator

-------------------------------------------------------------------------------
--  Assignment helpers
-------------------------------------------------------------------------------
local function GetSpecIndicators(db, specKey)
    -- Buff Manager v2 (flag-gated): storage lives in p.bm2 spec tables
    -- (spell -> filter -> indicator), legacy-shaped plus a `filters` map, so
    -- the ENTIRE editor works on them unchanged through this one accessor.
    -- v2 keys by the CURRENT player spec (class:index); healer specKey ignored.
    if ns.BM2_SpecInds then
        -- Key routes: healer spec key = that set, "nonhealer" = shared bucket, nil = the active key.
        local inds = ns.BM2_SpecInds(specKey)
        if inds then return inds end
    end
    if not db or not db.profile then return {} end
    if not db.profile.bmIndicators then db.profile.bmIndicators = {} end
    if not db.profile.bmIndicators[specKey] then
        db.profile.bmIndicators[specKey] = {}
        PopulateDefaults(db.profile.bmIndicators[specKey], specKey)
    end
    return db.profile.bmIndicators[specKey]
end
ns.BM_PrimaryByAlt = PRIMARY_BY_ALT

-- First tracked spec of the player's class, nil for untracked classes; the per-indicator all-specs fallback resolves through it.
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

local function CountSpecIndicators(db, specKey)
    local list = GetSpecIndicators(db, specKey)
    return #list
end

-------------------------------------------------------------------------------
--  Lookup rebuild: per-spec defaults, the active spec and the indicator id
--  counter. Rebuilt whenever indicators change (login, spec change, editor
--  writes).
-------------------------------------------------------------------------------
local function RebuildLookup(db)
    if not db or not db.profile then return end

    -- Ensure defaults are populated for all specs (triggers on first load)
    for _, spec in ipairs(HEALER_SPECS) do
        GetSpecIndicators(db, spec.key)
    end

    DetectActiveSpecKey()

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
end

ns.BM_RebuildLookup = RebuildLookup

-------------------------------------------------------------------------------
--  Pool sizes
-------------------------------------------------------------------------------
local ICON_POOL_SIZE = 8   -- max placed indicators visible per button
local BAR_POOL_SIZE  = 4

-- Size + anchor a bar indicator to its unit's health bar; shared by live and
-- preview so they stay 1:1. Full Width/Height off = slider size at the anchor;
-- on = edge-pinned to the health bar (pixel-for-pixel), anchor still drives the free axis.
local function BM_PlaceBar(bar, health, ind, iscale)
    local w = ind.barWidth or 30
    local h = ind.barHeight or 4
    local isVert = (ind.orientation or "HORIZONTAL") == "VERTICAL"
    bar:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
    bar:ClearAllPoints()
    -- Full Width/Height follow the fill axis like barWidth/barHeight: vertical
    -- bars swap the spanned screen edge, so "Full Width" always spans horizontal.
    -- Explicit if/else, not `a and b or c` -- the values are booleans.
    local fullW, fullH
    if isVert then
        fullW, fullH = ind.barFullHeight, ind.barFullWidth
    else
        fullW, fullH = ind.barFullWidth, ind.barFullHeight
    end
    -- Full pins span the health bar itself, keeping the real bar even when Uniform Icon Anchoring passes the full-height reference (it back-points).
    local hugBar = health._euiHealth or health
    if fullW and fullH then
        -- Exact overlay of the health bar.
        bar:SetAllPoints(hugBar)
    elseif fullW then
        -- Full width; cross-axis slider sets thickness, vertical edge places it.
        local pos = ind.position or "TOPLEFT"
        local vEdge = (pos:find("BOTTOM", 1, true) and "BOTTOM")
            or (pos:find("TOP", 1, true) and "TOP") or ""
        local oy = (ind.offsetY or 0) * iscale
        bar:SetPoint(vEdge .. "LEFT", health, vEdge .. "LEFT", 0, oy)
        bar:SetPoint(vEdge .. "RIGHT", health, vEdge .. "RIGHT", 0, oy)
        bar:SetHeight(isVert and w or h)
    elseif fullH then
        -- Full height; cross-axis slider sets thickness, horizontal edge places it.
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

-- Re-level a pooled icon/square frame for its Frame Level mode. baseLvl = the
-- unit button's level; own border at base+1, count/duration text carrier pinned
-- at +18 regardless of mode. Runs per assignment: pool frames are reused across indicators with different modes.
local function BM_ApplyIconLevel(fr, ind, baseLvl)
    local off = FRAMELVL_BASE[ind.frameLevel or "medium"] or FRAMELVL_BASE.medium
    fr:SetFrameLevel(baseLvl + off)
    -- Swipe + border one above the icon, text carrier on top; set each explicitly, not by child-level propagation.
    if fr._cooldown then fr._cooldown:SetFrameLevel(baseLvl + off + 1) end
    if fr._bdr then fr._bdr:SetFrameLevel(baseLvl + off + 1) end
    if fr._textCarrier then fr._textCarrier:SetFrameLevel(baseLvl + FRAMELVL_TEXT) end
end

-- Bars have no border/text sub-frames: base only, defaulting to Behind Borders.
local function BM_ApplyBarLevel(bar, ind, baseLvl)
    bar:SetFrameLevel(baseLvl + (FRAMELVL_BASE[ind.frameLevel or "behindBorders"] or FRAMELVL_BASE.behindBorders))
end

-- Frame-Border effect. "dashed" = static procedural ants from the glow engine;
-- every other style (solid, textured glow/shadow/blizz/lightspark/dialog,
-- LibSharedMedia) goes through EllesmereUI.ApplyBorderStyle (PP-vs-
-- BackdropTemplate swap; one renderer active, style stamped on frame). r,g,b,a are non-secret configured values; callers Show().
local function ApplyEffectBorder(borderFrame, ind, r, g, b, a, w, h)
    local style = ind.borderStyle or "solid"
    -- Sweep is not offered: no secret-safe way to drive the perimeter reveal on containers, and a full ring duplicates Solid. Stale picks render Solid.
    if style == "sweepcw" or style == "sweepccw" then
        style = "solid"
    end
    local bw = ind.borderWidth or 2
    local Glows = EllesmereUI.Glows
    local parent = borderFrame:GetParent()
    local baseLvl = (parent and parent:GetFrameLevel()) or borderFrame:GetFrameLevel()
    borderFrame:SetFrameLevel(baseLvl + 11)   -- default border level (matches creation)
    if style == "dashed" and Glows and Glows.StartProceduralAnts then
        EllesmereUI.HideBorderStyle(borderFrame)
        Glows.StartProceduralAnts(borderFrame, ind.borderDashCount or 8, bw, nil, nil,
            r, g, b, nil, nil, nil, nil, nil, nil, true)
        Glows.SetProceduralAntsColor(borderFrame, r, g, b, a)
    else
        if Glows and Glows.StopProceduralAnts then Glows.StopProceduralAnts(borderFrame) end
        if EllesmereUI.ApplyBorderStyle then
            -- Solid takes width as literal pixels; textured styles index the edge-size map (steps 1-4 only), so cap to dodge the >4 fallback.
            local sz = (style == "solid") and bw or math.min(bw, 4)
            -- Exact size (borderWidthPx, against the step and style drawn): 15th argument.
            EllesmereUI.ApplyBorderStyle(borderFrame, sz, r, g, b, a, style,
                nil, nil, nil, nil, nil, nil, nil,
                EllesmereUI.BorderPx(ind.borderWidthPx, sz, style))
        end
    end
end

-- Containers path: same renderer on the effect slot's border host, same
-- styles/levels. Dashed diverges: the host sits on the forbidden slot-button
-- subtree where driver-ticked ants error outside sanctioned windows, so it uses
-- the C-side animated engine instead (identical in/out of secret; w/h come from OUR frame -- the engine never measures there).
function ns.BM_ApplyEffectBorder(borderFrame, ind, r, g, b, a, w, h)
    local Glows = EllesmereUI.Glows
    if w and (ind.borderStyle or "solid") == "dashed"
        and Glows and Glows.StartAnimatedAnts then
        EllesmereUI.HideBorderStyle(borderFrame)
        -- Same +11 as the static styles (this branch returns first): otherwise the host stays at slot+1, one level BELOW the health bar (unit+2).
        local parent = borderFrame:GetParent()
        local baseLvl = (parent and parent:GetFrameLevel()) or borderFrame:GetFrameLevel()
        borderFrame:SetFrameLevel(baseLvl + 11)
        Glows.StartAnimatedAnts(borderFrame, ind.borderDashCount or 8,
            ind.borderWidth or 2, nil, r, g, b, w, h, a)
        return
    end
    -- Leaving dashed tears the animated march down (no-op if never armed).
    if w and Glows and Glows.StopAnimatedAnts then
        Glows.StopAnimatedAnts(borderFrame)
    end
    ApplyEffectBorder(borderFrame, ind, r, g, b, a, w, h)
end

-------------------------------------------------------------------------------
--  Preview indicator creation
-------------------------------------------------------------------------------
-- Forward-declare so preview click handler can set it (defined further down)
local selectedIndicator = nil

-- Preview indicator handlers: hover shows a 2px accent border, click selects.
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
-- Second return = the owning GROUP bucket key when the id came from an
-- INHERITED preview copy (display-offset id ranges; see BM_INH_OFFSETS).
local function BM_FindIndicatorById(indId)
    local specKey = ns._bmSelectedSpecKey
    -- v2: resolve against the REAL store (legacy is stale/absent, preview ids come from v2 copies) -- selection must hit storage so edits stick.
    local inds = ns.BM2_SpecInds(specKey)
    if inds then
        for _, ind in ipairs(inds) do
            if ind.id == indId then return ind end
        end
    end
    -- Inherited copies carry their group's display offset: undo it and
    -- resolve in the owning group's store. Group-bucket ids always start
    -- at the 1000001 base (seeded buckets; legacy small ids exist only
    -- in healer-key OWN buckets), so a floor keeps a wrong-offset probe
    -- from landing in another bucket's small-id band.
    local groups = ns.BM_InheritedGroupsFor and ns.BM_InheritedGroupsFor(specKey)
    if groups then
        for gi = 1, #groups do
            local gkey = groups[gi]
            local off = ns.BM_INH_OFFSETS[gkey] or 0
            local rawId = indId - off
            if rawId >= 1000000 and rawId ~= indId then
                local ginds = ns.BM2_SpecInds(gkey)
                if ginds then
                    for _, ind in ipairs(ginds) do
                        if ind.id == rawId then return ind, gkey end
                    end
                end
            end
        end
    end
    return nil
end


local function PvInd_OnClick(self, button)
    if not self._bmIndId then return end
    local ind, inhGroup = BM_FindIndicatorById(self._bmIndId)
    if not ind then return end

    -- Right-click: deliberately no action.
    if button == "RightButton" then return end

    -- Left-click: select the indicator for editing in the sidebar. An
    -- inherited copy selects its read-only tile instead.
    if inhGroup then
        selectedIndicator = nil
        ns._bm2InhSel = { group = inhGroup, id = ind.id }
    else
        selectedIndicator = ind
        ns._bm2InhSel = nil
    end
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
    -- Pool is larger than per-group caps: every group must still get icons on
    -- specs with many groups (non-selected groups dim, never vanish). The
    -- extra headroom covers the editing-spec union too -- concrete views
    -- preview inherited group buckets on top of their own list, and overflow
    -- is a silent vanish.
    for i = 1, ICON_POOL_SIZE + 24 do
        local fr = CreateFrame("Frame", nil, health)
        fr:SetFrameLevel(f:GetFrameLevel() + ns.LVL_AURA)
        fr:SetSize(12, 12)
        fr:Hide()

        local tex = fr:CreateTexture(nil, "ARTWORK")
        if PP then PP.DisablePixelSnap(tex) end
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
        local fontPath = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
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
    -- +4: bar indicators inherited from group buckets preview alongside the
    -- edited bucket's own (same union-headroom reasoning as the icon pool).
    for i = 1, BAR_POOL_SIZE + 4 do
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

    -- Frame effect overlays for preview: ARTWORK sublevel 2 sits below the dispel overlay (sublevel 3), matching the real frames.
    local hcOverlay = health:CreateTexture(nil, "ARTWORK", nil, 2)
    local pvFillTex = health:GetStatusBarTexture()
    if pvFillTex then
        hcOverlay:SetAllPoints(pvFillTex)
    else
        hcOverlay:SetAllPoints(health)
    end
    hcOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    hcOverlay:Hide()

    -- Background Color: whole health area, BELOW the fill (ARTWORK -2) so the tint reads as the bar's background, matching the real frames.
    local bgOverlay = health:CreateTexture(nil, "ARTWORK", nil, -2)
    bgOverlay:SetAllPoints(health)
    bgOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    bgOverlay:Hide()

    local effectBorder = CreateFrame("Frame", nil, f)
    effectBorder:SetAllPoints(f)
    effectBorder:SetFrameLevel(f:GetFrameLevel() + 11)
    effectBorder:Hide()
    if PP then PP.CreateBorder(effectBorder, 0, 1, 0, 1, 2) end

    f._bmIconPool      = iconPool
    f._bmBarPool       = barPool
    f._bmHCOverlay     = hcOverlay
    f._bmHCBar         = health
    f._bmBGOverlay     = bgOverlay
    f._bmEffectBorder  = effectBorder
end

-------------------------------------------------------------------------------
--  Preview data application: player slot 1, using the real saved configs.
-------------------------------------------------------------------------------
local previewSpellIcons = {}

local function GetSpellIcon(spellID)
    if previewSpellIcons[spellID] then return previewSpellIcons[spellID] end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    local icon = (info and info.iconID) or 136243
    previewSpellIcons[spellID] = icon
    return icon
end

function ns.BM_ApplyPreviewIndicators(f, index, s)
    local iconPool = f._bmIconPool
    local barPool  = f._bmBarPool
    if not iconPool then return end
    -- Party preview passes the party proxy as `s`; use the party scale.
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
    if f._bmBGOverlay then f._bmBGOverlay:Hide() end
    if f._bmEffectBorder then f._bmEffectBorder:Hide() end
    f:SetAlpha(1)

    -- Only show on slot 1 (player) for the preview
    if index ~= 1 then return end

    local db = ns.db
    if not db or not db.profile then return end
    local health = ns.RF_AnchorHost and ns.RF_AnchorHost(f._health, s) or f._health
    if not health then return end
    local PP = EllesmereUI.PanelPP or EllesmereUI.PP
    -- Base level for the Frame Level setting (mirrors the live render).
    local pvBaseLvl = f:GetFrameLevel()

    -- Show only the selected spec's indicators
    local iPoolIdx = 0
    local bPoolIdx = 0

    local activeSpecKey = ns._bmSelectedSpecKey
    local specList
    -- Preview the SELECTED v2 bucket with RESOLVED spell unions.
    do
        -- Edited bucket's class: OWN-ONLY entries preview only this class's
        -- spells (a Holy Paladin editing Core Healing Buffs must not see Druid
        -- HoTs -- those can never be their own casts). Untagged/custom ids and
        -- ALL-class entries always pass; show-anyone entries are never class-filtered.
        local edClass
        for i = 1, #HEALER_SPECS do
            if HEALER_SPECS[i].key == activeSpecKey then
                edClass = HEALER_SPECS[i].classToken
                break
            end
        end
        -- Per-spec buckets: class from the spec ID in the key.
        if not edClass and type(activeSpecKey) == "string" then
            local sid = activeSpecKey:match("^spec(%d+)$")
            if sid and GetSpecializationInfoByID then
                local _, _, _, _, _, cf = GetSpecializationInfoByID(tonumber(sid))
                edClass = cf
            end
        end
        if not edClass then
            local _, cf = UnitClass("player")
            edClass = cf
        end
        local spellClass = ns.BM2_SpellClass
        local out = {}
        -- Shared per-indicator preview synthesis; idOffset shifts INHERITED
        -- copies into their display id range (BM_INH_OFFSETS) so ids stay
        -- unique for the anchor pass, selection highlight and click-resolve.
        local function AppendPv(ind, idOffset)
            local resolved
            if ns.BM2_ResolveSpells then
                resolved = ns.BM2_ResolveSpells(ind)
            end
            if not (resolved and #resolved > 0) then return end
            -- Own-only is per-indicator: preview only spells the edited class could have cast.
            local kept = {}
            for j = 1, #resolved do
                local sid = resolved[j]
                local c = spellClass and spellClass[sid]
                if not (ind.ownOnly == true) or c == nil or c == "ALL"
                    or c == edClass then
                    kept[#kept + 1] = sid
                end
            end
            if #kept == 0 then return end
            local v = {}
            for k, val in pairs(ind) do v[k] = val end
            -- Preview parity: per-filter square colors expand exactly like the
            -- live view assembly.
            if ns.BM2_SquareFilterColors then
                v.spellColors = ns.BM2_SquareFilterColors(ind) or ind.spellColors
            end
            -- Healing-preset groups preview stacked icons (HoTs coexist); others preview ONE. Read by the render cap.
            local multi = false
            if ind.filters and ns.BM2_GetFilter then
                for fid in pairs(ind.filters) do
                    local pf = ns.BM2_GetFilter(fid)
                    if pf and (pf.preset == "coreheals"
                        or pf.preset == "lesserheals") then
                        multi = true
                        break
                    end
                end
            end
            v._pvMulti = multi
            -- Lead with an edited-class spell so the single-icon preview shows something that spec could cast/receive.
            for j = 2, #kept do
                if spellClass and spellClass[kept[j]] == edClass then
                    kept[1], kept[j] = kept[j], kept[1]
                    break
                end
            end
            v.spells = kept
            if idOffset then
                if type(v.id) == "number" then v.id = v.id + idOffset end
                if type(v.anchorTo) == "number" then v.anchorTo = v.anchorTo + idOffset end
            end
            out[#out + 1] = v
        end
        local inds = ns.BM2_SpecInds(activeSpecKey)
        if inds then
            for i = 1, #inds do AppendPv(inds[i], nil) end
        end
        -- Concrete views union the inherited group buckets, so the preview
        -- matches what the spec actually renders; per-spec disabled entries
        -- are excluded (they do not render live either).
        local inhGroups = ns.BM_InheritedGroupsFor and ns.BM_InheritedGroupsFor(activeSpecKey)
        if inhGroups then
            for gi = 1, #inhGroups do
                local gkey = inhGroups[gi]
                local ginds = ns.BM2_SpecInds(gkey)
                if ginds then
                    local off = ns.BM_INH_OFFSETS[gkey] or 0
                    for i = 1, #ginds do
                        local gind = ginds[i]
                        if not (ns.BM2_InhDisabled
                            and ns.BM2_InhDisabled(activeSpecKey, gkey, gind.id)) then
                            AppendPv(gind, off)
                        end
                    end
                end
            end
        end
        -- Anchor To: stamp members with their terminal root and order them right after it, so the preview renders each set as one run.
        do
            local byId, isMember = {}, {}
            for i = 1, #out do
                if out[i].id ~= nil then byId[out[i].id] = out[i] end
            end
            for i = 1, #out do
                local v = out[i]
                local t = v.anchorTo and byId[v.anchorTo]
                if t and (t.type or "icon") == (v.type or "icon") then
                    local seen = { [v] = true }
                    local root = t
                    while root and root.anchorTo and not seen[root] do
                        seen[root] = true
                        root = byId[root.anchorTo]
                    end
                    if root and not root.anchorTo and root ~= v then
                        v._pvAnchorRoot = root.id
                        isMember[v] = true
                    end
                end
            end
            local ordered = {}
            for i = 1, #out do
                local v = out[i]
                if not isMember[v] then
                    ordered[#ordered + 1] = v
                    if v.id ~= nil then
                        for j = 1, #out do
                            if out[j]._pvAnchorRoot == v.id then
                                ordered[#ordered + 1] = out[j]
                            end
                        end
                    end
                end
            end
            out = ordered
        end
        specList = out
    end
    -- Anchor To continuation state: root id -> banked cursor/anchor, consumed by member indicators ordered right after their root.
    local pvChain = {}
    for _, specData in pairs({ specList }) do
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
                                ns.RF_TintOverBarFill(f._bmHCOverlay, f._bmHCBar,
                                    c.r, c.g, c.b, (ind.opacity or 100) / 100)
                                f._bmHCOverlay:Show()
                            elseif indType == "bgcolor" and f._bmBGOverlay then
                                local c = ind.color or { r=0, g=1, b=0 }
                                f._bmBGOverlay:SetColorTexture(c.r, c.g, c.b, (ind.opacity or 100) / 100)
                                f._bmBGOverlay:Show()
                            elseif indType == "border" and f._bmEffectBorder and PP then
                                local c = ind.color or { r=0, g=1, b=0 }
                                ApplyEffectBorder(f._bmEffectBorder, ind, c.r, c.g, c.b, (ind.borderOpacity or 100) / 100)
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
                                -- v2 only: non-selected groups dim like icons (legacy preview never dimmed bars).
                                local barSel = ns._bmSelectedIndId and ind.id == ns._bmSelectedIndId
                                bar:SetAlpha((barSel or ns._bmAllIndicatorsVisible) and 1 or 0.5)
                                bar._bmIndId = ind.id
                                bar:Show()
                            end
                        else
                            local growDir = ind.growDirection or "RIGHT"
                            local sz = (ind.size or 12) * iscale
                            local snap = ns.PixelSnap or function(v) return v end
                            local gap = snap((ind.spacing or 1) * iscale)
                            -- Anchor To: members continue the root's run with its growth/anchor/cursor (member wrap previews linear; live wraps properly).
                            local anchorPos = ind.position or "TOPLEFT"
                            local anchorOX = (ind.offsetX or 0) * iscale
                            local anchorOY = (ind.offsetY or 0) * iscale
                            local chainSt = ind._pvAnchorRoot and pvChain[ind._pvAnchorRoot]
                            if chainSt then
                                growDir = chainSt.grow
                                anchorPos, anchorOX, anchorOY = chainSt.posKey, chainSt.ox, chainSt.oy
                            end
                            local isSelected = ns._bmSelectedIndId and ind.id == ns._bmSelectedIndId
                            local maxShow
                            if ind._pvMulti ~= nil then
                                -- v2: healing-preset groups cap at 4 selected/2 unselected (uncapped unions drain the icon pool and hide other groups); others show ONE.
                                if ind._pvMulti then
                                    maxShow = (isSelected or ns._bmAllIndicatorsVisible) and 4 or 2
                                else
                                    maxShow = 1
                                end
                            else
                                maxShow = (isSelected or ns._bmAllIndicatorsVisible) and #ind.spells or 2
                            end
                            -- Grid preview (12.1): mirror the live wrap/cap.
                            local per, wrapUp, wrapLeft = 0, false, false
                                per = tonumber(ind.iconsPerRow) or 0
                                local pu = string.upper(ind.position or "TOPLEFT")
                                wrapUp = pu:find("BOTTOM", 1, true) ~= nil
                                wrapLeft = pu:find("RIGHT", 1, true) ~= nil
                                local maxI = tonumber(ind.maxIcons) or 0
                                if maxI > 0 and maxI < maxShow then maxShow = maxI end
                            local previewTotal = math.min(maxShow, #ind.spells)
                            -- Running cursor (matches live render): each icon advances the next by its own size so size offsets reflow neighbors.
                            local cursor = 0
                            local pvSelfPoint = ind.position or "TOPLEFT"
                            if growDir == "CENTER" then
                                -- A wrapped run centers by its first LINE (engine left-aligns continuation rows).
                                local lineCap = previewTotal
                                if per > 0 and per < lineCap then lineCap = per end
                                local totalW, firstSz = 0, nil
                                for si2 = 1, lineCap do
                                    local s2 = sz
                                    if s2 < 1 then s2 = 1 end
                                    if not firstSz then firstSz = s2 end
                                    totalW = totalW + s2
                                end
                                if lineCap > 1 then totalW = totalW + gap * (lineCap - 1) end
                                cursor = -totalW / 2
                                    -- Live parity: containers x-center the run ON the
                                    -- position point (vertical seat kept; chains pin
                                    -- x-center, slot mode uses symmetric offsets). A
                                    -- pos-corner anchor + -totalW/2 start would skew by
                                    -- the corner's x-alignment (half an icon at center),
                                    -- so anchor by the pos's vertical part + horizontal CENTER.
                                    local posU = string.upper(pvSelfPoint)
                                    if posU:find("TOP", 1, true) then
                                        pvSelfPoint = "TOP"
                                    elseif posU:find("BOTTOM", 1, true) then
                                        pvSelfPoint = "BOTTOM"
                                    else
                                        pvSelfPoint = "CENTER"
                                    end
                                    cursor = -totalW / 2 + (firstSz or sz) / 2
                            end
                            if chainSt then
                                cursor = chainSt.cursor
                                pvSelfPoint = chainSt.selfPoint
                                per = 0
                            end
                            local lineStart = cursor
                            for si, sid in ipairs(ind.spells) do
                                if si > maxShow then break end
                                iPoolIdx = iPoolIdx + 1
                                local fr = iconPool[iPoolIdx]
                                if fr then
                                    BM_ApplyIconLevel(fr, ind, pvBaseLvl)
                                    local iconSz = sz
                                    if iconSz < 1 then iconSz = 1 end
                                    fr:SetSize(iconSz, iconSz)
                                    fr:ClearAllPoints()
                                    -- Place at accumulated sizes, then advance by own
                                    -- size (LEFT/UP negate the axis, no first-icon guard).
                                    -- Grid: reset cursor per line break, shift lines away from the anchored edge (live wrap).
                                    local lineOff = 0
                                    if per > 0 then
                                        if si > 1 and (si - 1) % per == 0 then cursor = lineStart end
                                        lineOff = math.floor((si - 1) / per) * (iconSz + gap)
                                    end
                                    local gx, gy = 0, 0
                                    if growDir == "RIGHT" or growDir == "CENTER" then
                                        gx = cursor; cursor = cursor + iconSz + gap
                                        gy = wrapUp and lineOff or -lineOff
                                    elseif growDir == "DOWN" then
                                        gy = -cursor; cursor = cursor + iconSz + gap
                                        gx = wrapLeft and -lineOff or lineOff
                                    elseif growDir == "LEFT" then
                                        gx = -cursor; cursor = cursor + iconSz + gap
                                        gy = wrapUp and lineOff or -lineOff
                                    elseif growDir == "UP" then
                                        gy = cursor; cursor = cursor + iconSz + gap
                                        gx = wrapLeft and -lineOff or lineOff
                                    end
                                    fr:SetPoint(pvSelfPoint, health, anchorPos,
                                                anchorOX + gx, anchorOY + gy)
                                    -- "Hide Icons" (icon only): keep frame alpha so stacks preview; zero texture, swipe, border.
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
                                        -- Per-ability color (preview): this spell's color, then legacy ind.color, then default.
                                        local c = (ind.spellColors and ind.spellColors[sid])
                                            or ind.color or { r=0, g=1, b=0 }
                                        -- Reset vertex first (as live): a reused icon frame can carry a faded tint that blanks it.
                                        fr._tex:SetVertexColor(1, 1, 1, 1)
                                        fr._tex:SetColorTexture(c.r, c.g, c.b, 1)
                                        fr._tex:SetTexCoord(0, 1, 0, 1)
                                    end
                                    -- Fixed preview stacks: Blistering Scales 8, Lifebloom 2
                                    local previewStacks = (sid == 360827 and "8") or (sid == 33763 and "2")
                                    if ind.showStacks and previewStacks then
                                        local sSz = (ind.stacksTextSize or 8) * iscale
                                        local sc = ind.stacksTextColor or { r=1, g=1, b=1 }
                                        local sOX = (ind.stacksOffsetX or 0) * iscale
                                        local sOY = (ind.stacksOffsetY or 0) * iscale
                                        local fp = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
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
                                            -- Manual duration text (static, not a countdown); survives Hide Icons.
                                            if ind.showDurationText and fr._durText then
                                                local dtc = ind.durationTextColor or { r=1, g=1, b=1 }
                                                local fp = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
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
                                        local pandemicPreview = indType == "icon" and isSelected
                                            and ind.pandemicBorderEnabled and not pvHideIcon
                                        if pandemicPreview then ibs = ind.pandemicBorderWidth or 2 end
                                        if ibs > 0 then
                                            local ibc = pandemicPreview
                                                and (ind.pandemicBorderColor or { r=1, g=0.2, b=0.2 })
                                                or ind.indBorderColor or { r=0, g=0, b=0 }
                                            PP.UpdateBorder(fr._bdr, ibs, ibc.r, ibc.g, ibc.b, 1)
                                            fr._bdr:Show()
                                        else
                                            fr._bdr:Hide()
                                        end
                                    end
                                end
                            end
                            -- Anchor To: bank the run state under the ROOT id so the next member of the set keeps extending this run.
                            pvChain[ind._pvAnchorRoot or ind.id or 0] = {
                                cursor = cursor, grow = growDir,
                                selfPoint = pvSelfPoint, posKey = anchorPos,
                                ox = anchorOX, oy = anchorOY,
                            }
                        end
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Options page builder: 70/30 vertical split, full page height. Left = creation
--  row then indicator settings; right = sidebar of indicator tiles, full height.
-------------------------------------------------------------------------------
-- Page-level state (persists across setting changes within same page open)
local selectedSpecKey = nil

-- Class token of the EDITED bucket (dropdown selection): healer keys map
-- directly, "spec<ID>" keys resolve through the spec API, shared buckets
-- (allspecs/nonhealer) have no single class -> nil (player-class fallback).
local function SelectedBucketClass()
    local key = selectedSpecKey
    local hs = key and SPEC_BY_KEY[key]
    if hs then return hs.classToken end
    local sid = type(key) == "string" and key:match("^spec(%d+)$")
    if sid and GetSpecializationInfoByID then
        local _, _, _, _, _, cf = GetSpecializationInfoByID(tonumber(sid))
        return cf
    end
    return nil
end
-- selectedIndicator: forward-declared near preview hover/click handlers
local selectedType = "icon"

local function AutoDetectSpec()
    -- Exact spec match (locale-independent, by spec ID).
    local key = CurrentSpecKey()
    if key then return key end

    -- Fallback for the options UI: pick the first tracked spec for the player's class so a non-tracked spec (e.g. a DPS spec) still opens on something sane.
    local _, classToken = UnitClass("player")
    if classToken then
        for _, spec in ipairs(HEALER_SPECS) do
            if spec.classToken == classToken then
                return spec.key
            end
        end
    end
    -- Class with no tracked spec (e.g. Warrior): open on Holy Paladin, not blank.
    return "PALADIN_HOLY"
end

-------------------------------------------------------------------------------
--  Health-bar replica preview, shared by the Debuff Manager (draws its own
--  content on it) and the Buff Manager page. opts: previewClass (default:
--  the active spec's class), minH (150), noUniformRef. Returns pvFrame,
--  sectionH, scale.
function ns.BM_BuildSimplePreview(parent, s, fontPath, PP, centerX, topY, opts)
    opts = opts or {}
    local PV_SCALE = 1.5
    local rawW = s.frameWidth or 72
    local rawH = s.frameHeight or 46
    local previewPad = 20
    -- Cap on-screen height at 100px via uniform downscale (keeps rawW:rawH aspect).
    if rawH * PV_SCALE > 100 then PV_SCALE = 100 / rawH end
    local pvH = floor(rawH * PV_SCALE + 0.5)
    local sectionH = max(pvH + previewPad * 2, opts.minH or 150)

    local pvFrame = CreateFrame("Frame", nil, parent)
    pvFrame:SetSize(rawW, rawH)
    pvFrame:SetScale(PV_SCALE)
    pvFrame:SetPoint("TOP", parent, "TOPLEFT", floor(centerX / PV_SCALE), topY / PV_SCALE)

    local bgc = s.customBgColor or { r = 17/255, g = 17/255, b = 17/255 }
    local bg = pvFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()

    local rawPowerH = (s.powerShowForHealer or s.powerShowForTank or s.powerShowForDPS) and (s.powerHeight or 4) or 0
    local rawTopBarH = s.topNameBarEnabled and (s.topNameBarHeight or 20) or 0
    local healthH = rawH - rawPowerH - rawTopBarH

    -- Health bar (matches the custom preview build exactly)
    local texKey = s.healthBarTexture or "atrocity"
    local texPath = EllesmereUI.ResolveTexturePath(ns.healthBarTextures or {}, texKey, "Interface\\Buttons\\WHITE8X8")
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

    -- Full-height anchor reference (mirrors the live buttons' d.uniformRef so Uniform Icon Anchoring previews identically; see ns.RF_AnchorHost).
    if not opts.noUniformRef then
        local pvUniformRef = CreateFrame("Frame", nil, pvFrame)
        pvUniformRef:SetFrameLevel(health:GetFrameLevel())
        pvUniformRef:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        pvUniformRef:SetPoint("BOTTOMRIGHT", pvFrame, "BOTTOMRIGHT", 0, 0)
        health._euiUniformRef = pvUniformRef
        pvUniformRef._euiHealth = health
    end

    -- Preview class color from the player's active spec (falls back to class)
    local previewClass = opts.previewClass
    if not previewClass and activeSpecKey_BM and SPEC_BY_KEY[activeSpecKey_BM] then
        previewClass = SPEC_BY_KEY[activeSpecKey_BM].classToken
    end
    if not previewClass then
        local _, pc = UnitClass("player")
        previewClass = pc
    end
    local cc = EllesmereUI.GetClassColor(previewClass)
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
        local pInfo = EllesmereUI.GetPowerColor("MANA")
        if pInfo then power:SetStatusBarColor(pInfo.r, pInfo.g, pInfo.b, 1)
        else power:SetStatusBarColor(0, 0.5, 1, 1) end
        local pwBg = power:CreateTexture(nil, "BACKGROUND")
        pwBg:SetAllPoints()
        local pbc = (s.powerBgPowerColored and pInfo) or s.powerBgColor or { r=0, g=0, b=0 }
        local pbF = (s.powerBgPowerColored and pInfo) and EllesmereUI.GetPowerBgDarkenFactor() or 1
        pwBg:SetColorTexture(pbc.r * pbF, pbc.g * pbF, pbc.b * pbF, (s.powerBgDarkness or 70) / 100)
        -- Classic WoW UI: the stock edge and divider stand in (as live).
        if PP and ns.RF_Classic and ns.RF_Classic() then
            ns.RF_StockBuild(pvFrame, pvFrame, power)
            ns.RF_StockDivider(pvFrame)
        elseif PP and s.powerBorderStyle and s.powerBorderStyle ~= "none" then
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

    if PP then
        -- Stock styles: the stock edge stands in for the EllesmereUI border.
        if ns.RF_Stock and ns.RF_Stock() then ns.RF_StockBuild(pvFrame, pvFrame) end
        local bsz = ns.RF_EffBorderSize and ns.RF_EffBorderSize(s) or (s.borderSize or 1)
        if bsz > 0 then
            local bdr = CreateFrame("Frame", nil, pvFrame)
            bdr:SetAllPoints(pvFrame)
            bdr:SetFrameLevel(pvFrame:GetFrameLevel() + 8)
            PP.CreateBorder(bdr, 0, 0, 0, 1, 1)
            local bc = s.borderColor or { r=0, g=0, b=0 }
            PP.UpdateBorder(bdr, bsz, bc.r, bc.g, bc.b, s.borderAlpha or 1)
        end
    end

    -- Name text on a carrier in the live text band (ns.LVL_TEXT) so it draws above the +8 main border, exactly like real frames.
    local nameCarrier = CreateFrame("Frame", nil, pvFrame)
    nameCarrier:SetAllPoints(pvFrame)
    nameCarrier:SetFrameLevel(pvFrame:GetFrameLevel() + (ns.LVL_TEXT or 12))
    local nameFS = nameCarrier:CreateFontString(nil, "OVERLAY")
    local outline = (EllesmereUI.GetFontOutlineFlag("raidFrames")) or ""
    EllesmereUI.PrimeFontShadow(nameFS, outline == "" and EllesmereUI.GetFontUseShadow("raidFrames"))
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

    return pvFrame, sectionH, PV_SCALE
end

function ns.BM_BuildPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    if not W then return 0 end
    local db = ns.db
    if not db then return 0 end
    -- Override-session gate: heals a stale BM layer FIRST (renders the edited group's fork) and reports the end overlay; nil = normal WYSIWYG.
    local bmOverlayState = EllesmereUI.SpecOverrides_BmPagePrelude() or nil
    local PP = EllesmereUI.PanelPP

    -- Auto-detect spec on first open
    if not selectedSpecKey then
        selectedSpecKey = AutoDetectSpec()
    end

    -- Light update: rebuild lookup + refresh frames/preview, no page rebuild (sliders/settings that don't change structure).
    local function ReloadAndUpdate()
        RebuildLookup(db)
        if ns.ReloadFrames then ns.ReloadFrames() end
        local pv = ns._bmPreviewFrame
        if pv and pv._health and ns.BM_ApplyPreviewIndicators then
            ns.BM_ApplyPreviewIndicators(pv, 1, db.profile)
        end
    end

    -- Full update: also rebuilds the page (preview, sidebar, settings) -- used by create/delete/toggle/dropdown changes that alter structure.
    local function ReloadAndRebuild()
        RebuildLookup(db)
        if ns.ReloadFrames then ns.ReloadFrames() end
        EllesmereUI:RefreshPage(true)
    end

    local fontPath = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    local _, h
    local PAD = 20  -- consistent left/right padding for creation bar + settings
    local s = db.profile

    -- Current spec's indicators for the sidebar. v2: editing dropdown stays functional (healer specs + shared Non-Healer bucket); defaults to current spec on first page open each session.
    if ns.BM2_SpecKey and not ns._bm2SpecInited then
        ns._bm2SpecInited = true
        local landKey = ns.BM2_SpecKey()
        -- Non-healers land on their CONCRETE "spec<ID>" view, not the shared
        -- All Non Healers/Aug group: the concrete view is where inherited
        -- group tiles (All Specs / Non Healers / role) are visible, so the
        -- player sees everything their spec actually renders. The shared
        -- bucket stays one dropdown pick away.
        if landKey == "nonhealer" then
            local specIdx = GetSpecialization and GetSpecialization()
            local sid = specIdx and GetSpecializationInfo and GetSpecializationInfo(specIdx)
            if sid then landKey = "spec" .. sid end
        end
        selectedSpecKey = landKey
    end
    local specIndicators = selectedSpecKey and GetSpecIndicators(db, selectedSpecKey) or {}

    -- Group buckets this view INHERITS from (concrete spec views only):
    -- their indicators lead the sidebar as read-only tiles with a per-spec
    -- enable. nil on group-bucket views.
    local inheritedGroups = ns.BM_InheritedGroupsFor
        and ns.BM_InheritedGroupsFor(selectedSpecKey) or nil

    -- Inherited-tile selection (ns._bm2InhSel = { group, id }): resolve it
    -- against the owning group's store; drop it when the view no longer
    -- inherits that group or the indicator is gone. While valid it OWNS the
    -- left pane (read-only), so the indicator selection clears.
    local inhSelInd = nil
    if ns._bm2InhSel then
        local isel = ns._bm2InhSel
        for gi = 1, #(inheritedGroups or {}) do
            if inheritedGroups[gi] == isel.group then
                for _, gind in ipairs(GetSpecIndicators(db, isel.group) or {}) do
                    if gind.id == isel.id then inhSelInd = gind; break end
                end
                break
            end
        end
        if not inhSelInd then ns._bm2InhSel = nil end
    end
    if inhSelInd then selectedIndicator = nil end

    -- Validate selected indicator
    if not inhSelInd then
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
    end

    -- Expose selected spec + indicator ID for preview logic. An inherited
    -- selection exposes its DISPLAY id (group offset applied) so the preview
    -- highlight finds the unioned copy.
    ns._bmSelectedSpecKey = selectedSpecKey
    if inhSelInd then
        ns._bmSelectedIndId = ns._bm2InhSel.id + (ns.BM_INH_OFFSETS[ns._bm2InhSel.group] or 0)
    else
        ns._bmSelectedIndId = selectedIndicator and selectedIndicator.id or nil
    end

    -- Editing-spec roster lead (EllesmereUI.BuildSpecBucketRoster): the
    -- healer/Aug specs and a divider between the group buckets and every
    -- other spec in the game. Standard spec icons throughout.
    local function HealerRosterLead(values, order, icons)
        local inHealerList = {}
        for i = 1, #SPEC_DD_ORDER do
            local key = SPEC_DD_ORDER[i]
            values[key] = EllesmereUI.L(SPEC_DD_VALUES[key])
            order[#order + 1] = key
            local hs = SPEC_BY_KEY[key]
            if hs and hs.specID then
                inHealerList[hs.specID] = true
                if GetSpecializationInfoByID then
                    local _, _, _, sIcon = GetSpecializationInfoByID(hs.specID)
                    icons[key] = sIcon
                end
            end
        end
        order[#order + 1] = "---b"
        return inHealerList
    end

    -------------------------------------------------------------------
    --  FIXED LAYOUT: fills visible area, no outer scroll.
    --  Left column (72%): creation + preview (fixed) + settings (scroll)
    --  Right sidebar (28%): full height, own scroll, dark background
    -------------------------------------------------------------------
    -- Build on the scroll frame (not the scroll child) so content is fixed and non-scrollable; no outer scrollbar.
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
    if EllesmereUI._pickMenu then EllesmereUI._pickMenu:Hide() end
    ns._bmRoot = outerRoot

    -- Override-session full-page overlay (state from the prelude above).
    -- "activate" offers to fork a custom Buff Manager for the edited override
    -- group; "info" explains why editing is blocked (edits would land in
    -- whatever layer is actually live and bank to the wrong owner at the next
    -- harvest). Built BEFORE page content since the Simple Setup branch returns
    -- early and must still be covered; high frame level, child of outerRoot so every teardown path destroys it.
    if bmOverlayState then
        local st = bmOverlayState
        local ov, btn = EllesmereUI.BuildActivationOverlay(outerRoot, {
            fontPath = fontPath, width = parentW,
            title = EllesmereUI.L("Custom Buff Manager"), text = st.text, sub = st.sub,
            buttonLabel = st.mode == "activate" and EllesmereUI.L("Activate Custom Buff Manager") or nil,
        })
        if btn then
            -- Create popup: pick what the new Buff Manager starts from (main
            -- copy, another override's copy, or a preset), then Create. Child of
            -- the overlay so every page teardown destroys it with the overlay.
            local createPopup
            local chosen = "main"
            btn:SetScript("OnClick", function(self)
                if createPopup and createPopup:IsShown() then createPopup:Hide(); return end
                if not (EllesmereUI.SpecOverrides_ActivateBm and EllesmereUI.SpecOverrides_BmSeedSources
                        and EllesmereUI.BuildDropdownControl) then
                    EllesmereUI.SpecOverrides_ActivateBm(st.kind, st.gid)
                    return
                end
                local values, order = EllesmereUI.SpecOverrides_BmSeedSources(st.kind, st.gid)
                chosen = "main"
                if not createPopup then
                    local POPUP_W, POPUP_PAD, ROW_H, LABEL_H = 260, 10, 30, 14
                    local LBL_GAP, DD_GAP = 4, 11
                    local popup = CreateFrame("Frame", nil, ov)
                    popup:SetFrameStrata("DIALOG")
                    popup:SetFrameLevel(ov:GetFrameLevel() + 20)
                    popup:SetSize(POPUP_W, POPUP_PAD + LABEL_H + LBL_GAP + ROW_H + DD_GAP + ROW_H + POPUP_PAD)
                    popup:EnableMouse(true)
                    popup:SetClampedToScreen(true)
                    local pbg = popup:CreateTexture(nil, "BACKGROUND")
                    pbg:SetAllPoints()
                    pbg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
                    EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.2, PP)
                    -- Click-away close (not while the dropdown's own menu is open).
                    popup:SetScript("OnShow", function(p2)
                        p2:SetScript("OnUpdate", function(m)
                            if not self:IsMouseOver() and not m:IsMouseOver() then
                                local dd = m._srcDD
                                if dd and dd._ddMenu and dd._ddMenu:IsShown() and dd._ddMenu:IsMouseOver() then return end
                                if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                                    m:Hide()
                                end
                            end
                        end)
                    end)
                    popup:SetScript("OnHide", function(p2) p2:SetScript("OnUpdate", nil) end)
                    local ddW = POPUP_W - POPUP_PAD * 2
                    local py = -POPUP_PAD
                    local srcLbl = popup:CreateFontString(nil, "OVERLAY")
                    srcLbl:SetFont(fontPath, 11, "")
                    srcLbl:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                    srcLbl:SetText(EllesmereUI.L("Start From"))
                    srcLbl:SetTextColor(1, 1, 1, 0.6)
                    py = py - LABEL_H - LBL_GAP
                    popup._srcValues, popup._srcOrder = values, order
                    local srcDD = EllesmereUI.BuildDropdownControl(
                        popup, ddW, popup:GetFrameLevel() + 2,
                        popup._srcValues, popup._srcOrder,
                        function() return chosen end,
                        function(v) chosen = v end)
                    srcDD:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                    popup._srcDD = srcDD
                    py = py - ROW_H - DD_GAP
                    local ac = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
                    local cBtn = CreateFrame("Button", nil, popup)
                    cBtn:SetSize(ddW, ROW_H)
                    cBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                    cBtn:SetFrameLevel(popup:GetFrameLevel() + 1)
                    local cBg = cBtn:CreateTexture(nil, "BACKGROUND")
                    cBg:SetAllPoints()
                    cBg:SetColorTexture(ac.r, ac.g, ac.b, 0.8)
                    local cLbl = cBtn:CreateFontString(nil, "OVERLAY")
                    EllesmereUI.PrimeFontShadow(cLbl, true)
                    cLbl:SetFont(fontPath, 12, "")
                    cLbl:SetPoint("CENTER")
                    cLbl:SetText(EllesmereUI.L("Create Custom Buff Manager"))
                    cLbl:SetTextColor(1, 1, 1)
                    cBtn:SetScript("OnEnter", function() cBg:SetColorTexture(ac.r, ac.g, ac.b, 1) end)
                    cBtn:SetScript("OnLeave", function() cBg:SetColorTexture(ac.r, ac.g, ac.b, 0.8) end)
                    cBtn:SetScript("OnClick", function()
                        popup:Hide()
                        EllesmereUI.SpecOverrides_ActivateBm(st.kind, st.gid, chosen)
                    end)
                    createPopup = popup
                else
                    -- Refresh the source list in place (other overrides may have
                    -- gained or lost a Buff Manager since the popup was built).
                    wipe(createPopup._srcValues); wipe(createPopup._srcOrder)
                    for k, v in pairs(values) do createPopup._srcValues[k] = v end
                    for i = 1, #order do createPopup._srcOrder[i] = order[i] end
                    local dd = createPopup._srcDD
                    if dd._invalidateMenu then dd._invalidateMenu() end
                    if dd._refreshLabel then dd._refreshLabel() end
                end
                createPopup:ClearAllPoints()
                createPopup:SetPoint("TOP", self, "BOTTOM", 0, -6)
                createPopup:Show()
            end)
        end
    end

    local HEADER_H = 0

    -- Custom Buff Display: the full buff manager builds into the content area below the header; existing layout below uses `root` + `visibleH`.
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

    local tileY = 0

    -------------------------------------------------------------------
    --  INHERITED group indicators lead concrete spec views: read-only
    --  here (edit them in their group), marked by a blue edge strip +
    --  blue group-name subtitle; the pill toggles ONLY the per-spec
    --  disable (BM2_SetInhDisabled) -- other specs are never affected.
    -------------------------------------------------------------------
    if inheritedGroups then
        for gi = 1, #inheritedGroups do
            local gkey = inheritedGroups[gi]
            local ginfo = ns.BM_GROUP_BUCKET_INFO[gkey]
            local gname = ginfo and EllesmereUI.L(ginfo.name) or gkey
            for _, gind in ipairs(GetSpecIndicators(db, gkey) or {}) do
                local gSpells = ns.BM2_ResolveSpells and ns.BM2_ResolveSpells(gind) or gind.spells
                local face = 136243
                if gSpells and #gSpells > 0 then
                    face = GetSpellIcon((ns.BM2_PreferredSpell
                        and ns.BM2_PreferredSpell(gind, SelectedBucketClass())) or gSpells[1])
                end
                local gTypeInfo = INDICATOR_TYPE_MAP[gind.type]
                local gTypeName = gTypeInfo and gTypeInfo.name or gind.type
                local posText
                if gTypeInfo and gTypeInfo.placed and gind.position then
                    posText = "(" .. EllesmereUI.L(POSITION_VALUES[gind.position] or gind.position) .. ")"
                end
                -- Pill: the PER-SPEC enable ONLY; a group-level disable dims
                -- the tile instead (the control can never look dead).
                tileY = tileY - EllesmereUI.BuildManagerTile(sidebarFrame, tileY, {
                    width = sidebarW, fontPath = fontPath, icon = face,
                    title = gind.name and EllesmereUI.L(gind.name) or EllesmereUI.L(gTypeName),
                    titleUnclamped = true, posText = posText, subtitle = gname,
                    inheritedTooltip = EllesmereUI.Lf("Inherited from %1$s. Editable only there.", gname),
                    selected = ns._bm2InhSel and ns._bm2InhSel.group == gkey
                        and ns._bm2InhSel.id == gind.id,
                    dimmed = not gind.enabled,
                    enabled = not ns.BM2_InhDisabled(selectedSpecKey, gkey, gind.id),
                    showToggle = true,
                    onSelect = function()
                        selectedIndicator = nil
                        ns._bm2InhSel = { group = gkey, id = gind.id }
                        EllesmereUI:RefreshPage(true)
                    end,
                    onToggle = function()
                        ns.BM2_SetInhDisabled(selectedSpecKey, gkey, gind.id,
                            not ns.BM2_InhDisabled(selectedSpecKey, gkey, gind.id))
                        RebuildLookup(db)
                        if ns.ReloadFrames then ns.ReloadFrames() end
                        EllesmereUI:RefreshPage(true)
                    end,
                })
            end
        end
    end
    for _, ind in ipairs(specIndicators) do
        -- v2: tiles render the RESOLVED spell union (assigned filters + direct spells) -- the raw list is empty for filter-driven groups.
        local tileSpells = ind.spells
        if ns.BM2_ResolveSpells then
            tileSpells = ns.BM2_ResolveSpells(ind)
        end
        local face = 136243
        local subtitle = EllesmereUI.L("(no spells)")
        if tileSpells and #tileSpells > 0 then
            -- v2: prefer a spell the EDITED bucket's spec/class actually uses as the tile's face (known spell > class-tagged > all-class).
            face = GetSpellIcon((ns.BM2_PreferredSpell
                and ns.BM2_PreferredSpell(ind, SelectedBucketClass())) or tileSpells[1])
            local names = {}
            for _, sid in ipairs(tileSpells) do
                names[#names + 1] = SPELL_NAME_BY_ID[sid]
                    or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid))
                    or tostring(sid)
            end
            subtitle = table.concat(names, ", ")
        end

        local typeInfo2 = INDICATOR_TYPE_MAP[ind.type]
        local typeName = typeInfo2 and typeInfo2.name or ind.type
        local posText
        if typeInfo2 and typeInfo2.placed and ind.position then
            posText = "(" .. EllesmereUI.L(POSITION_VALUES[ind.position] or ind.position) .. ")"
        end

        local tileH, tile = EllesmereUI.BuildManagerTile(sidebarFrame, tileY, {
            width = sidebarW, fontPath = fontPath, icon = face,
            -- v2: named indicators (the seeded filter groups) show their name.
            title = ind.name and EllesmereUI.L(ind.name) or EllesmereUI.L(typeName),
            titleUnclamped = true, posText = posText, subtitle = subtitle,
            selected = selectedIndicator and selectedIndicator.id == ind.id,
            enabled = ind.enabled,
            showToggle = true,
            onSelect = function()
                ns._bm2InhSel = nil
                selectedIndicator = ind
                EllesmereUI:RefreshPage(true)
            end,
            -- Right-click: "Add To" context menu -- copies this indicator into
            -- another editing-spec bucket (full clone, fresh id; source stays).
            onContext = function(tileFrame)
                if not EllesmereUI.ShowPickMenu then return end
                EllesmereUI.ShowPickMenu(tileFrame, {
                    title = EllesmereUI.L("Add To"),
                    fontPath = fontPath,
                    items = EllesmereUI.SpecBucketMenuItems(selectedSpecKey, HealerRosterLead),
                    onPick = function(key)
                        -- Target cap: silently blocked at the limit (house
                        -- silent-correction pattern; CountSpecIndicators
                        -- seeds only the picked bucket).
                        if CountSpecIndicators(db, key) >= MAX_PER_SPEC then return end
                        if ns.BM2_CopyIndicator and ns.BM2_CopyIndicator(ind, key) then
                            RebuildLookup(db)
                            if ns.ReloadFrames then ns.ReloadFrames() end
                            EllesmereUI:RefreshPage(true)
                        end
                    end,
                })
            end,
            onToggle = function()
                ind.enabled = not ind.enabled
                RebuildLookup(db)
                if ns.ReloadFrames then ns.ReloadFrames() end
                EllesmereUI:RefreshPage(true)
            end,
            onDelete = function()
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
                        -- Deleting a GROUP indicator sweeps its per-spec disable
                        -- keys from every concrete bucket (stale keys are inert
                        -- but would leak forever).
                        if ns.BM2_SweepInhDis and ns.BM_GROUP_BUCKET_INFO
                            and ns.BM_GROUP_BUCKET_INFO[selectedSpecKey] then
                            ns.BM2_SweepInhDis(selectedSpecKey, ind.id)
                        end
                        RebuildLookup(db)
                        if ns.ReloadFrames then ns.ReloadFrames() end
                        EllesmereUI:RefreshPage(true)
                    end,
                })
            end,
            -- Rename: the name is display-only, so a rename never touches
            -- spells/signature -- page refresh suffices.
            editTooltip = EllesmereUI.L("Rename Indicator"),
            onEdit = function()
                local cur = ind.name or typeName
                EllesmereUI:ShowInputPopup({
                    title = EllesmereUI.L("Rename Indicator"),
                    message = EllesmereUI.L("Enter a new name for this indicator:"),
                    placeholder = cur,
                    confirmText = EllesmereUI.L("Rename"),
                    cancelText = EllesmereUI.L("Cancel"),
                    onConfirm = function(text)
                        text = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
                        -- Empty reverts to the type-name default.
                        ind.name = (text ~= "") and text or nil
                        EllesmereUI:RefreshPage(true)
                    end,
                })
            end,
        })

        -- Frame Alpha is removed: the notice covers the tile body but leaves the right controls usable so it can still be toggled off or deleted.
        if ind.type == "framealpha" then
            local ov = BuildPTROverlay(tile, "Frame Alpha", 10)
            ov:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
            ov:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -52, 1)
        end

        tileY = tileY - tileH
    end

    -------------------------------------------------------------------
    --  Empty-override hint: an override Buff Manager shows ONLY what it
    --  contains, so a spec with no indicators in it renders nothing. Say so
    --  in place of the blank tile list (fork live on this page only).
    -------------------------------------------------------------------
    if #specIndicators == 0 and EllesmereUI.SpecOverrides_BmActiveInfo() then
        local inhCount = 0
        if inheritedGroups then
            for gi = 1, #inheritedGroups do
                inhCount = inhCount + #(GetSpecIndicators(db, inheritedGroups[gi]) or {})
            end
        end
        if inhCount == 0 then
            local hint = sidebarFrame:CreateFontString(nil, "OVERLAY")
            hint:SetFont(fontPath, 11, "")
            hint:SetPoint("TOP", sidebarFrame, "TOPLEFT", floor(sidebarW / 2), tileY - 8)
            hint:SetWidth(sidebarW - 24)
            hint:SetJustifyH("CENTER")
            hint:SetWordWrap(true)
            hint:SetTextColor(1, 0.75, 0.35, 0.9)
            hint:SetText(EllesmereUI.L("This override has no indicators for this spec, so nothing shows here until you add some."))
            tileY = tileY - hint:GetStringHeight() - 16
        end
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
        -- Drop shadow via the shadow FontObject, primed BEFORE SetFont (SetShadowOffset alone does not render).
        EllesmereUI.PrimeFontShadow(addLabel, true)
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
                -- Three label+dropdown pairs: Indicator, Filters, Extra Spells.
                popup:SetSize(POPUP_W, POPUP_PAD
                    + 3 * (LABEL_H + LBL_GAP + ROW_H + DD_GAP)
                    + ROW_H + POPUP_PAD)
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
                            local indDD2 = m._indDD
                            if indDD2 and indDD2._ddMenu and indDD2._ddMenu:IsShown() and indDD2._ddMenu:IsMouseOver() then return end
                            local fltDD2 = m._fltDD
                            if fltDD2 and fltDD2._ddMenu and fltDD2._ddMenu:IsShown() and fltDD2._ddMenu:IsMouseOver() then return end
                            local exDD2 = m._exDD
                            if exDD2 and exDD2._ddMenu and exDD2._ddMenu:IsShown() and exDD2._ddMenu:IsMouseOver() then return end
                            -- Modal children own the mouse: the Custom Spell ID
                            -- input and the Filter Editor open from these.
                            local ip = _G.EUIInputPopup
                            if ip and ip:IsShown() then return end
                            if ns._bm2FilterEditor then return end
                            if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                                m:Hide()
                            end
                        end
                    end)
                end)
                popup:SetScript("OnHide", function(p)
                    p:SetScript("OnUpdate", nil)
                    -- Clear spell selections so reopening starts fresh
                    if p._v2Filters then wipe(p._v2Filters) end
                    if p._v2NegFilters then wipe(p._v2NegFilters) end
                    if p._v2Extras then wipe(p._v2Extras) end
                end)

                local py = -POPUP_PAD
                local ddW = POPUP_W - POPUP_PAD * 2

                -- v2 creation flow: Indicator type, then the SAME Filters and
                -- Extra Spells dropdowns as Assigned Buffs; picks apply to the new indicator on Create.
                popup._v2Filters = {}
                popup._v2NegFilters = {}
                popup._v2Extras = {}

                local indLbl2 = popup:CreateFontString(nil, "OVERLAY")
                indLbl2:SetFont(fontPath, 11, "")
                indLbl2:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                indLbl2:SetText(EllesmereUI.L("Indicator"))
                indLbl2:SetTextColor(1, 1, 1, 0.6)
                py = py - LABEL_H - LBL_GAP

                local indDD = EllesmereUI.BuildDropdownControl(
                    popup, ddW, popup:GetFrameLevel() + 2,
                    INDICATOR_TYPE_VALUES, INDICATOR_TYPE_ORDER,
                    function() return selectedType end,
                    function(v) selectedType = v end)
                indDD:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                popup._indDD = indDD
                py = py - ROW_H - DD_GAP

                local fltLbl = popup:CreateFontString(nil, "OVERLAY")
                fltLbl:SetFont(fontPath, 11, "")
                fltLbl:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                fltLbl:SetText(EllesmereUI.L("Filters"))
                fltLbl:SetTextColor(1, 1, 1, 0.6)
                py = py - LABEL_H - LBL_GAP
                local fltDDY = py
                py = py - ROW_H - DD_GAP

                local exLbl = popup:CreateFontString(nil, "OVERLAY")
                exLbl:SetFont(fontPath, 11, "")
                exLbl:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
                exLbl:SetText(EllesmereUI.L("Extra Spells"))
                exLbl:SetTextColor(1, 1, 1, 0.6)
                py = py - LABEL_H - LBL_GAP
                local exDDY = py
                py = py - ROW_H - DD_GAP

                -- Rebuilt per open (filter list / Selected grouping go stale); pending picks survive rebuilds, wiped on hide.
                local function BuildV2DDs()
                    if popup._fltDD then popup._fltDD:Hide(); popup._fltDD:SetParent(nil) end
                    if popup._exDD then popup._exDD:Hide(); popup._exDD:SetParent(nil) end
                    popup._fltDD, popup._exDD = nil, nil

                    -- Dynamic items: fresh per menu open (adds/renames live).
                    -- Two-lane rows: Show picks (popup._v2Filters) and Hide picks
                    -- (popup._v2NegFilters), applied to the new indicator on Create.
                    local function FItems()
                        local filters = (ns.BM2_Filters and ns.BM2_Filters()) or {}
                        local fItems = {
                            { isTopAction = true, label = "Edit Filters", onClick = function()
                                if ns.BMP_ShowFilterEditor then ns.BMP_ShowFilterEditor() end
                            end },
                            { isHeader = true, label = "Show", rightLabel = "Hide" },
                        }
                        for i = 1, #filters do
                            fItems[#fItems + 1] = { key = filters[i].id, label = filters[i].name, dual = true }
                        end
                        return fItems
                    end
                    local fltDD = EllesmereUI.BuildVisOptsCBDropdown(
                        popup, ddW, popup:GetFrameLevel() + 2,
                        FItems,
                        function(k, neg)
                            if neg then return popup._v2NegFilters[k] and true or false end
                            return popup._v2Filters[k] and true or false
                        end,
                        function(k, v, neg)
                            if neg then
                                popup._v2NegFilters[k] = v and true or nil
                                if v then popup._v2Filters[k] = nil end
                            else
                                popup._v2Filters[k] = v and true or nil
                                if v then popup._v2NegFilters[k] = nil end
                            end
                        end,
                        nil, 12)
                    fltDD:SetSize(ddW, ROW_H)
                    fltDD:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, fltDDY)
                    popup._fltDD = fltDD

                    local function SpellEntry(id)
                        -- Curated name first (distinguishes variants the client
                        -- API can't, e.g. two spell IDs both named "Sense Power"
                        -- by Blizzard); SPELL_NAME_BY_ID already falls back to
                        -- the live API internally when no curated name exists.
                        local name = SPELL_NAME_BY_ID[id]
                        local label = name or ("Spell " .. tostring(id))
                        -- Truncated rows still need to be told apart on hover.
                        return { key = id, label = label, tooltip = label,
                            icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) }
                    end
                    -- Dynamic items: fresh per menu open. Spells already supplied by
                    -- CHECKED filters are excluded from Presets (redundant as extras); picked extras always show under Selected.
                    local function ByLabel(a, b) return a.label < b.label end
                    local function EItems()
                        local covered = {}
                        if ns.BM2_GetFilter then
                            for fid in pairs(popup._v2Filters) do
                                local f = ns.BM2_GetFilter(fid)
                                if f then
                                    for id, on in pairs(f.spells) do
                                        if on then covered[id] = true end
                                    end
                                end
                            end
                        end
                        local universe = (ns.BM2_AllPresetSpells and ns.BM2_AllPresetSpells()) or {}
                        local selList, rest = {}, {}
                        local seen = {}
                        for id in pairs(popup._v2Extras) do
                            seen[id] = true
                            selList[#selList + 1] = SpellEntry(id)
                        end
                        for i = 1, #universe do
                            local id = universe[i]
                            if not seen[id] and not covered[id] then rest[#rest + 1] = SpellEntry(id) end
                        end
                        table.sort(selList, ByLabel)
                        table.sort(rest, ByLabel)
                        local eItems = {
                            { isTopAction = true, label = "Custom Spell ID", onClick = function()
                                EllesmereUI:ShowInputPopup({
                                    title = EllesmereUI.L("Add Spell ID"),
                                    message = EllesmereUI.L("Enter the spell ID to track on this indicator."),
                                    confirmText = EllesmereUI.L("Add"),
                                    cancelText = EllesmereUI.L("Cancel"),
                                    onConfirm = function(text)
                                        local id = tonumber(text or "")
                                        if id and id > 0 and not popup._v2Extras[id] then
                                            popup._v2Extras[id] = true
                                        end
                                    end,
                                })
                            end },
                        }
                        if #selList > 0 then
                            eItems[#eItems + 1] = { isHeader = true, label = "Selected" }
                            for i = 1, #selList do eItems[#eItems + 1] = selList[i] end
                        end
                        eItems[#eItems + 1] = { isHeader = true, label = "Presets" }
                        for i = 1, #rest do eItems[#eItems + 1] = rest[i] end
                        return eItems
                    end
                    local exDD = EllesmereUI.BuildVisOptsCBDropdown(
                        popup, ddW, popup:GetFrameLevel() + 2,
                        EItems,
                        function(k) return popup._v2Extras[k] and true or false end,
                        function(k, v) popup._v2Extras[k] = v and true or nil end,
                        nil, 10, true)
                    exDD:SetSize(ddW, ROW_H)
                    exDD:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, exDDY)
                    popup._exDD = exDD
                end
                BuildV2DDs()
                popup._rebuildSpells = BuildV2DDs

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
                    -- v2: create through the v2 store (correct id namespace, edited bucket),
                    -- then assign picked filters/extra spells as Assigned Buffs does (incl. presets' own-only default).
                    local newInd = ns.BM2_AddIndicator(selectedType, selectedSpecKey)
                    if newInd then
                        for fid in pairs(popup._v2Filters or {}) do
                            newInd.filters[fid] = true
                        end
                        if popup._v2NegFilters and next(popup._v2NegFilters) then
                            newInd.negFilters = {}
                            for fid in pairs(popup._v2NegFilters) do
                                newInd.negFilters[fid] = true
                            end
                        end
                        local exList = {}
                        for sid in pairs(popup._v2Extras or {}) do
                            exList[#exList + 1] = sid
                        end
                        table.sort(exList)
                        for i = 1, #exList do
                            newInd.spells[#newInd.spells + 1] = exList[i]
                        end
                        selectedIndicator = newInd
                    end
                    ns._bm2InhSel = nil
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
    local CLASS_SPRITE_COORDS = EllesmereUI.CLASS_ICON_SPRITE_COORDS
    local SPEC_CLASS_MAP = {}
    for _, spec in ipairs(HEALER_SPECS) do
        SPEC_CLASS_MAP[spec.key] = spec.classToken
    end

    do
        local pvSplitW = floor(leftW * 0.65)   -- left 65% for preview
        local specSplitW = leftW - pvSplitW     -- right 35% for editing spec

        -- Roster shared with the right-click "Add To" menu (built once per
        -- page build here; the menu rebuilds it lazily per open).
        local specDDValues, specDDOrder, specDDIcons, specDDClass = EllesmereUI.BuildSpecBucketRoster(HealerRosterLead)

        ---------------------------------------------------------------
        --  LEFT 65%: Preview frame (centered). Health color class =
        --  selected spec's (per-spec buckets via the roster map), else
        --  player's.
        ---------------------------------------------------------------
        local previewClass
        if selectedSpecKey and SPEC_BY_KEY[selectedSpecKey] then
            previewClass = SPEC_BY_KEY[selectedSpecKey].classToken
        end
        if not previewClass and specDDClass then
            previewClass = specDDClass[selectedSpecKey]
        end
        if not previewClass then
            local _, pc = UnitClass("player")
            previewClass = pc
        end
        local pvFrame, sectionH, PV_SCALE = ns.BM_BuildSimplePreview(leftFrame, s, fontPath, PP, pvSplitW / 2, ly - 20,
            { previewClass = previewClass, minH = 120, noUniformRef = true })
        local health = pvFrame._health

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
        -- Per-spec buckets resolve their class through the roster map.
        if not selClass and specDDClass then
            selClass = specDDClass[selectedSpecKey]
        end
        local selCoords = selClass and CLASS_SPRITE_COORDS[selClass]
        local selGroup = selectedSpecKey and ns.BM_GROUP_BUCKET_INFO
            and ns.BM_GROUP_BUCKET_INFO[selectedSpecKey]
        if selCoords then
            classIconBg:SetTexCoord(selCoords[1], selCoords[2], selCoords[3], selCoords[4])
        elseif selGroup then
            -- Group buckets wear their roster icon.
            classIconBg:SetTexture(selGroup.icon)
            classIconBg:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            classIconBg:Hide()
        end

        -- Label + dropdown vertically centered: 14 + 7 gap + 30 = 51 tall.
        local groupH = 14 + 7 + 30
        local groupTopY = ly - (sectionH - groupH) / 2

        local specLabel = leftFixed:CreateFontString(nil, "OVERLAY")
        specLabel:SetFont(fontPath, 12, "")
        specLabel:SetPoint("TOP", leftFixed, "TOPLEFT", specCenterX, groupTopY)
        specLabel:SetJustifyH("CENTER")
        specLabel:SetText(EllesmereUI.L("Editing Spec"))
        specLabel:SetTextColor(1, 1, 1, 0.75)

        specDDValues._menuOpts = {
            maxHeight = 300,
            icon = function(key)
                -- Standard spec icons; group buckets wear their roster
                -- icon.
                local g = ns.BM_GROUP_BUCKET_INFO and ns.BM_GROUP_BUCKET_INFO[key]
                if g then return g.icon end
                local ic = specDDIcons and specDDIcons[key]
                if ic then return ic end
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
            specDDValues, specDDOrder,
            function() return selectedSpecKey or "" end,
            function(v)
                selectedSpecKey = v
                selectedIndicator = nil
                ns._bm2InhSel = nil
                EllesmereUI:RefreshPage(true)
            end)
        specDD:SetPoint("TOP", specLabel, "BOTTOM", 0, -7)

        -- Buff manager indicators on the preview
        if ns.BM_CreatePreviewIndicators then
            ns.BM_CreatePreviewIndicators(pvFrame, health, PP)
        end
        if ns.BM_ApplyPreviewIndicators then
            ns.BM_ApplyPreviewIndicators(pvFrame, 1, s)
        end

        -- Eyeball toggle: show all indicators at full opacity
        do
            local EYE_VIS = EllesmereUI.EYE_VISIBLE_ICON
            local EYE_INVIS = EllesmereUI.EYE_INVISIBLE_ICON
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

        -- Small helper subtitle under the preview explaining icon interactions; click
        -- to dismiss permanently (EllesmereUIDB.bmIconHintDismissed). When dismissed it is not built and the extra 10px gap below collapses to 0.
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

    -- Settings area below the fixed top. DualRow subtracts CONTENT_PAD*2 from parent
    -- width and offsets by CONTENT_PAD, so to align with our PAD (20px): width = leftW + (CONTENT_PAD - PAD)*2, offset = -(CONTENT_PAD - PAD).
    local contentPad = EllesmereUI.CONTENT_PAD or 45
    local padDiff = contentPad - PAD
    local viewportH = max(10, visibleH - fixedH)
    local settingsW = leftW + padDiff * 2

    -- Smooth-scrolling viewport (mirrors the main options page): rows build into the
    -- scroll child, sized to content after building. The smooth frame is parented to the scroll frame, so it stops on page rebuild.
    local settingsScroll = CreateFrame("ScrollFrame", nil, root)
    -- +5 raises the settings panel (CORE section first) 5px into the fixed area's bottom spacing, tightening the gap above CORE for every indicator.
    settingsScroll:SetPoint("TOPLEFT", leftFixed, "BOTTOMLEFT", -padDiff, 5)
    settingsScroll:SetSize(settingsW, viewportH)
    settingsScroll:SetFrameLevel(root:GetFrameLevel() + 1)
    settingsScroll:SetClipsChildren(true)

    local settingsChild = CreateFrame("Frame", nil, settingsScroll)
    settingsChild:SetSize(settingsW, viewportH)
    settingsScroll:SetScrollChild(settingsChild)

    -- Scrollbar: thin track + thumb at the viewport's right edge (shown only on overflow).
    local UpdateThumb = EllesmereUI.AttachSmoothScrollbar(settingsScroll, {
        step = 60, width = 5, rightInset = 31, topInset = 12, level = 20,
        trackAlpha = 0.05, thumbAlpha = 0.22, child = settingsChild })

    -- From here, DualRows build inside the scroll child
    leftFrame = settingsChild
    leftFrame._showRowDivider = true
    local sy = 0  -- Y within settings scroll child

    if inhSelInd then
        -------------------------------------------------------------------
        --  Read-only pane for an INHERITED group indicator: explains where
        --  it lives, links to the owning group, and points at the tile
        --  toggle for the per-spec enable. No settings render -- edits
        --  belong to the group.
        -------------------------------------------------------------------
        local ind = inhSelInd
        local gkey = ns._bm2InhSel.group
        local ginfo = ns.BM_GROUP_BUCKET_INFO[gkey]
        local gname = ginfo and EllesmereUI.L(ginfo.name) or gkey
        local inhTypeName = INDICATOR_TYPE_MAP[ind.type]
            and INDICATOR_TYPE_MAP[ind.type].name or ind.type
        settingsTitle:SetTextColor(0.55, 0.72, 1)
        settingsTitle:SetText(ind.name and EllesmereUI.L(ind.name)
            or EllesmereUI.L(inhTypeName .. " Indicator"))
        spellsTitle:SetText("(" .. EllesmereUI.Lf("Inherited from %1$s", gname) .. ")")

        -- Child x = padDiff + PAD aligns with the PAD margin (the scroll
        -- child is widened by padDiff each side and shifted left, so x = 0
        -- sits OFF the visible column and clips).
        local info = leftFrame:CreateFontString(nil, "OVERLAY")
        info:SetFont(fontPath, 12, "")
        info:SetPoint("TOPLEFT", leftFrame, "TOPLEFT", padDiff + PAD, sy - 14)
        info:SetPoint("RIGHT", leftFrame, "RIGHT", -(padDiff + PAD), 0)
        info:SetJustifyH("LEFT")
        info:SetWordWrap(true)
        info:SetText(EllesmereUI.Lf("Inherited from %1$s. Edit it there, or use the tile toggle to enable or disable it for this spec.", gname))
        info:SetTextColor(0.65, 0.65, 0.65)
        sy = sy - 64

        local link = CreateFrame("Button", nil, leftFrame)
        link:SetPoint("TOPLEFT", leftFrame, "TOPLEFT", padDiff + PAD, sy - 4)
        link:SetFrameLevel(leftFrame:GetFrameLevel() + 2)
        local linkFS = link:CreateFontString(nil, "OVERLAY")
        linkFS:SetFont(fontPath, 12, "")
        linkFS:SetPoint("TOPLEFT")
        linkFS:SetText(EllesmereUI.Lf("Edit in %1$s", gname))
        local lac = EllesmereUI.ELLESMERE_GREEN
        if lac then
            linkFS:SetTextColor(lac.r, lac.g, lac.b, 0.85)
        else
            linkFS:SetTextColor(0.05, 0.82, 0.62, 0.85)
        end
        link:SetSize(linkFS:GetStringWidth() + 4, 18)
        link:SetScript("OnEnter", function() linkFS:SetAlpha(1) end)
        link:SetScript("OnLeave", function() linkFS:SetAlpha(0.85) end)
        link:SetScript("OnClick", function()
            selectedSpecKey = gkey
            selectedIndicator = ind
            ns._bm2InhSel = nil
            EllesmereUI:RefreshPage(true)
        end)
        sy = sy - 30
    elseif selectedIndicator then
        local ind = selectedIndicator
        local indType = ind.type
        local typeInfo = INDICATOR_TYPE_MAP[indType]

        -- v2: Assigned Filters section leads the settings (built by the manager-pages
        -- file; returns the new y cursor); the rest of the legacy per-type settings apply to the same v2 indicator table.
        if ns.BMP_BuildAssignedFilters then
            sy = ns.BMP_BuildAssignedFilters(leftFrame, sy, ind, fontPath)
        end

        -- Build title: accent "Icon Indicator: " + white "Rejuvenation, Lifebloom"
        local typeName = INDICATOR_TYPE_MAP[indType] and INDICATOR_TYPE_MAP[indType].name or indType
        local ac2 = EllesmereUI.ELLESMERE_GREEN
        if ac2 then
            settingsTitle:SetTextColor(ac2.r, ac2.g, ac2.b)
        else
            settingsTitle:SetTextColor(0.05, 0.82, 0.62)
        end
        settingsTitle:SetText(EllesmereUI.L(typeName .. " Indicator"))

        -- v2: named filter-driven groups head their settings with the group name; spell-driven indicators keep the legacy name list.
        if ind.name then
            spellsTitle:SetText("(" .. EllesmereUI.L(ind.name) .. ")")
        else
            local spellNames = {}
            if ind.spells then
                for _, sid in ipairs(ind.spells) do
                    spellNames[#spellNames + 1] = SPELL_NAME_BY_ID[sid]
                        or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid))
                        or tostring(sid)
                end
            end
            spellsTitle:SetText(#spellNames > 0 and ("(" .. table.concat(spellNames, ", ") .. ")") or EllesmereUI.L("(no spells)"))
        end

        -- Helper: build a DualRow inside leftFrame
        local function SettingsRow(leftCfg, rightCfg)
            local row
            row, h = W:DualRow(leftFrame, sy, leftCfg, rightCfg)
            sy = sy - h
            return row
        end

        -- Own Only is per-INDICATOR (no per-source dropdown).
        local function BuildOwnOnlyRow()
            SettingsRow(
                { type="toggle", text="Own Only",
                  tooltip="Only show buffs cast by you.",
                  getValue=function() return ind.ownOnly == true end,
                  setValue=function(v) ind.ownOnly = v and true or false; ReloadAndUpdate() end },
                { type="label", text="" })
        end

        -- Auto-default growth direction based on position
        local function GetDefaultGrow(pos)
            if pos == "RIGHT" or pos == "TOPRIGHT" or pos == "BOTTOMRIGHT" then return "LEFT" end
            if pos == "LEFT" or pos == "TOPLEFT" or pos == "BOTTOMLEFT" then return "RIGHT" end
            if pos == "TOP" then return "DOWN" end
            if pos == "BOTTOM" then return "UP" end
            return "RIGHT"
        end

        -- THRESHOLD TEXT (after DISPLAY, for placed types icon/square/bar): recolors
        -- duration text below the threshold via the engine color curve (secret-safe);
        -- default OFF so existing indicators are unchanged.
        local function BuildThresholdRow()
            _, h = W:SectionHeader(leftFrame, "THRESHOLD TEXT", sy); sy = sy - h

            -- Sub-settings are interactive only while Enable Threshold is on.
            local thOff = function() return not ind.thresholdEnabled end

            -- The engine color curve is the only threshold display the duration bindings support.
            local thRow = SettingsRow(
                { type="toggle", text="Enable Threshold Text",
                  getValue=function() return ind.thresholdEnabled or false end,
                  setValue=function(v) ind.thresholdEnabled = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                { type="slider", text="Threshold (sec)", min=1, max=10, step=1, trackWidth=120,
                  disabled=thOff, disabledTooltip="Enable Threshold Text",
                  getValue=function() return ind.threshold or 3 end,
                  setValue=function(v) ind.threshold = v; ReloadAndUpdate() end })

            -- Inline swatch on the toggle: threshold text color; dimmed and inert while the threshold is off.
            do
                local rgn = thRow._leftRegion
                local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, thRow:GetFrameLevel() + 3,
                    function()
                        local c = ind.thresholdColor or { r=1, g=0.2, b=0.2 }
                        return c.r, c.g, c.b
                    end,
                    function(r, g, b)
                        ind.thresholdColor = { r=r, g=g, b=b }
                        ReloadAndUpdate()
                    end, false, 20)
                swatch:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
                -- Click-gate while the threshold is off (dimmed swatch).
                local origClick = swatch:GetScript("OnClick")
                swatch:SetScript("OnClick", function(self, ...)
                    if thOff() then return end
                    if origClick then origClick(self, ...) end
                end)
                swatch:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(swatch, thOff()
                        and EllesmereUI.DisabledTooltip("Enable Threshold Text")
                        or "Threshold Text Color")
                end)
                swatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function SwatchState()
                    swatch:SetAlpha(thOff() and 0.3 or 1)
                end
                EllesmereUI.RegisterWidgetRefresh(function() updateSwatch(); SwatchState() end)
                SwatchState()
                rgn._lastInline = swatch
            end

        end

        if indType == "icon" or indType == "square" then
            -----------------------------------------------------------
            --  CORE
            -----------------------------------------------------------
            _, h = W:SectionHeader(leftFrame, "CORE", sy); sy = sy - h

            -- Assignment lives in ASSIGNED BUFFS: rows are Position | Growth
            -- Direction, then Own Only.
            -- Own Only is per-INDICATOR (no per-source dropdown).
            local ownCfg =
                { type="toggle", text="Own Only",
                  tooltip="Only show buffs cast by you.",
                  getValue=function() return ind.ownOnly == true end,
                  setValue=function(v) ind.ownOnly = v and true or false; ReloadAndUpdate() end }
            -- Position gains an "Anchor To" subnav (v2): picking another indicator
            -- of the SAME type continues its run; anchored position/growth/wrap come from the target.
            local posValues, posOrder = {}, {}
            for _, k in ipairs(POSITION_ORDER) do
                posOrder[#posOrder + 1] = k
                posValues[k] = POSITION_VALUES[k]
            end
            local anchorVals = {}
            local list = GetSpecIndicators(db, selectedSpecKey) or {}
            local byId = {}
            for i = 1, #list do
                if list[i].id ~= nil then byId[list[i].id] = list[i] end
            end
            -- Following the candidate's own anchor links must never reach back to this indicator (no cycles).
            local function WouldCycle(target)
                local seen, cur = {}, target
                while cur do
                    if cur == ind or seen[cur] then return true end
                    seen[cur] = true
                    cur = cur.anchorTo and byId[cur.anchorTo] or nil
                end
                return false
            end
            local ao = {}
            for i = 1, #list do
                local t = list[i]
                if t ~= ind and t.id ~= nil and t.enabled
                    and (t.type or "icon") == (indType or "icon")
                    and not WouldCycle(t) then
                    local key = "@" .. t.id
                    local label = (t.name and t.name ~= "" and t.name) or nil
                    if not label then
                        local sid = ns.BM2_PreferredSpell and ns.BM2_PreferredSpell(t, SelectedBucketClass())
                        local nm = sid and C_Spell and C_Spell.GetSpellName
                            and C_Spell.GetSpellName(sid)
                        label = nm or ("Indicator " .. t.id)
                    end
                    anchorVals[key] = label
                    ao[#ao + 1] = key
                end
            end
            if #ao > 0 then
                -- Subnav children report through onSelect (they never
                -- reach the dropdown's setValue); route both paths into
                -- the shared setter below. "Anchor To" leads the list.
                posValues["__anchor"] = { text = "Anchor To", subnav = {
                    values = anchorVals, order = ao,
                    onSelect = function(childKey)
                        local tid = type(childKey) == "string"
                            and string.match(childKey, "^@(%d+)$")
                        if tid then
                            ind.anchorTo = tonumber(tid)
                            ReloadAndUpdate()
                            EllesmereUI:RefreshPage()
                        end
                    end,
                    icon = function(key)
                        local id = tonumber(string.match(key, "^@(%d+)$"))
                        local t = id and byId[id]
                        local sid = t and ns.BM2_PreferredSpell and ns.BM2_PreferredSpell(t, SelectedBucketClass())
                        return sid and C_Spell and C_Spell.GetSpellTexture
                            and C_Spell.GetSpellTexture(sid) or nil
                    end,
                } }
                tinsert(posOrder, 1, "__anchor")
            end
            local Anchored = function() return ind.anchorTo ~= nil end
            local posCfg =
                { type="dropdown", text="Position", values=posValues, order=posOrder,
                  getValue=function()
                      local ak = ind.anchorTo and ("@" .. ind.anchorTo)
                      if ak and anchorVals[ak] then return ak end
                      return ind.position or "TOPLEFT"
                  end,
                  setValue=function(v)
                      local tid = type(v) == "string" and string.match(v, "^@(%d+)$")
                      if tid then
                          ind.anchorTo = tonumber(tid)
                      else
                          ind.anchorTo = nil
                          ind.position = v
                          ind.growDirection = GetDefaultGrow(v)
                      end
                      ReloadAndUpdate()
                      EllesmereUI:RefreshPage()
                  end }
            local growCfg =
                { type="dropdown", text="Growth Direction", values=GROW_VALUES, order=GROW_ORDER,
                  disabled=Anchored, disabledTooltip="Remove the Anchor To position",
                  getValue=function() return ind.growDirection or "RIGHT" end,
                  setValue=function(v) ind.growDirection = v; ReloadAndUpdate() end }
            -- Grid wrap+cap is a container capability (chain groups wrap natively; live
            -- indicators are linear runs). Icons Per Row rides row 2's right slot (v2 keeps it blank otherwise); Max Icons sits on an inline cog beside it.
            local perRowCfg
                perRowCfg =
                    { type="slider", text="Icons Per Row", min=0, max=20, step=1, trackWidth=120,
                      tooltip="Wraps into a new row (or column for vertical growth) after this many icons; 0 keeps one continuous run.",
                      disabled=Anchored, disabledTooltip="Remove the Anchor To position",
                      getValue=function() return ind.iconsPerRow or 0 end,
                      setValue=function(v)
                          ind.iconsPerRow = (v and v > 0) and v or nil
                          ReloadAndUpdate()
                      end }
            local row1, posRow, perRgn
            posRow = SettingsRow(posCfg, growCfg)
            row1 = SettingsRow(ownCfg, perRowCfg or { type="label", text="" })
            if perRowCfg then perRgn = row1._rightRegion end
            if perRgn then
                EllesmereUI.BuildInlineCog(perRgn, {
                    tip = "Max Icons",
                    title = "Max Icons",
                    rows = {
                        { type="slider", label="Max Icons", min=0, max=40, step=1,
                          get=function() return ind.maxIcons or 0 end,
                          set=function(v)
                              ind.maxIcons = (v and v > 0) and v or nil
                              ReloadAndUpdate()
                          end },
                    },
                })
            end

            -- Cog for position offset X/Y (rides the Position slot, LEFT in both modes)
            do
                local rgn = posRow._leftRegion
                -- Anchored: only the ALONG-RUN offset does anything (cross-axis
                -- has no engine expression in a shared flow); Frame Level is inert
                -- on continuation groups. Run axis comes from the anchor target's growth (terminal root).
                local function AnchorRunVertical()
                    if not ind.anchorTo then return nil end
                    local list = GetSpecIndicators(db, selectedSpecKey) or {}
                    local byId2 = {}
                    for i = 1, #list do
                        if list[i].id ~= nil then byId2[list[i].id] = list[i] end
                    end
                    local seen, cur = {}, byId2[ind.anchorTo]
                    while cur and cur.anchorTo and not seen[cur] do
                        seen[cur] = true
                        cur = byId2[cur.anchorTo]
                    end
                    if not cur then return nil end
                    local g = cur.growDirection or "RIGHT"
                    return g == "UP" or g == "DOWN"
                end
                EllesmereUI.BuildInlineCog(rgn, {
                    icon = EllesmereUI.DIRECTIONS_ICON,
                    title = "Position Offset",
                    rows = {
                        { type="slider", label="Offset X", min=-50, max=50, step=1,
                          disabled=function() return AnchorRunVertical() == true end,
                          disabledTooltip="A Horizontally Growing Anchor Target",
                          get=function() return ind.offsetX or 0 end,
                          set=function(v) ind.offsetX = v; ReloadAndUpdate() end },
                        { type="slider", label="Offset Y", min=-50, max=50, step=1,
                          disabled=function() return AnchorRunVertical() == false end,
                          disabledTooltip="A Vertically Growing Anchor Target",
                          get=function() return ind.offsetY or 0 end,
                          set=function(v) ind.offsetY = v; ReloadAndUpdate() end },
                        { type="dropdown", label="Frame Level", values=FRAMELVL_VALUES, order=FRAMELVL_ORDER,
                          disabled=function() return ind.anchorTo ~= nil end,
                          disabledTooltip="An Unanchored Position",
                          get=function() return ind.frameLevel or "medium" end,
                          set=function(v) ind.frameLevel = v; ReloadAndUpdate() end },
                    },
                })
            end

            -----------------------------------------------------------
            --  DISPLAY
            -----------------------------------------------------------
            _, h = W:SectionHeader(leftFrame, "DISPLAY", sy); sy = sy - h

            local IconHidden = function() return indType == "icon" and ind.hideIcon == true end
            local sizeRow = SettingsRow(
                { type="slider", text="Size", min=4, max=80, step=1,
                  getValue=function() return ind.size or 12 end,
                  setValue=function(v) ind.size = v; ReloadAndUpdate() end },
                { type="slider", pixel=true, text="Spacing", min=-1, max=10, step=1,
                  getValue=function() return ind.spacing or 1 end,
                  setValue=function(v) ind.spacing = v; ReloadAndUpdate() end })

            -- Icon Zoom cog (icon type only): one profile-wide value shared by all icon indicators.
            if indType == "icon" then
                local rgn = sizeRow._leftRegion
                EllesmereUI.BuildInlineCog(rgn, {
                    disabled = IconHidden, disabledTooltip = "Hide Icons", requireState = "disabled",
                    title = "Icon Zoom",
                    rows = {
                        { type="slider", label="Zoom", min=0, max=0.20, step=0.01,
                          get=function() return ns.db.profile.bmIconZoom or 0.08 end,
                          set=function(v) ns.db.profile.bmIconZoom = v; ReloadAndUpdate() end },
                    },
                })
            end

            local bdrRow = SettingsRow(
                { type="slider", text="Opacity", min=0, max=100, step=1,
                  disabled=IconHidden, disabledTooltip="Hide Icons",
                  getValue=function() return ind.iconOpacity or 100 end,
                  setValue=function(v) ind.iconOpacity = v; ReloadAndUpdate() end },
                { type="slider", text="Border", min=0, max=4, step=1, trackWidth=120,
                  disabled=IconHidden, disabledTooltip="Hide Icons",
                  getValue=function() return ind.indBorderSize or 1 end,
                  setValue=function(v) ind.indBorderSize = v; ReloadAndUpdate() end })
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

            local durRow = SettingsRow(
                { type="toggle", text="Duration Swipe",
                  disabled=IconHidden, disabledTooltip="Hide Icons",
                  getValue=function() return ind.showDuration ~= false end,
                  setValue=function(v) ind.showDuration = v; ReloadAndUpdate() end },
                { type="toggle", text="Duration Text",
                  getValue=function() return ind.showDurationText or false end,
                  setValue=function(v) ind.showDurationText = v; ReloadAndUpdate() end })
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

                EllesmereUI.BuildInlineCog(rgn, {
                    icon = EllesmereUI.RESIZE_ICON,
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
            end

            local stacksRow = SettingsRow(
                { type="toggle", text="Show Stacks",
                  getValue=function() return ind.showStacks ~= false end,
                  setValue=function(v) ind.showStacks = v; ReloadAndUpdate() end },
                (indType == "square") and { type="label", text="Colors" }
                  or { type="toggle", text="Hide Icons",
                       tooltip="Hide the icon texture, border, and duration swipe, leaving only the stack count. Forces icon opacity, border, and duration swipe off.",
                       getValue=function() return ind.hideIcon == true end,
                       setValue=function(v) ind.hideIcon = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end })
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
                EllesmereUI.BuildInlineCog(rgn, {
                    icon = EllesmereUI.RESIZE_ICON,
                    disabled = function() return ind.showStacks == false end,
                    disabledTooltip = "Show Stacks",
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
            end
            -- Per-ability color swatches (square only), right-to-left like every inline
            -- swatch row (ability 1 at the right edge); no per-spell color falls back to ind.color, then the default.
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
                -- One swatch per ASSIGNED FILTER, continuing the chain: colors
                -- every spell that filter shows (direct per-spell swatches
                -- above win on overlap -- BM2_SquareFilterColors doctrine).
                -- Ascending fid order matches the runtime's overlap resolution.
                if ind.filters then
                    local fids = {}
                    for fid in pairs(ind.filters) do fids[#fids + 1] = fid end
                    table.sort(fids)
                    for _, fid in ipairs(fids) do
                        local myFid = fid
                        local swatch = EllesmereUI.BuildColorSwatch(
                            rgn, stacksRow:GetFrameLevel() + 3,
                            function()
                                local c = (ind.filterColors and ind.filterColors[myFid])
                                    or ind.color or DEFAULT_SQ
                                return c.r, c.g, c.b, 1
                            end,
                            function(r, g, b)
                                if not ind.filterColors then ind.filterColors = {} end
                                ind.filterColors[myFid] = { r=r, g=g, b=b }
                                ReloadAndUpdate()
                            end, false, 20)
                        if prev then
                            swatch:SetPoint("RIGHT", prev, "LEFT", -8, 0)
                        else
                            swatch:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
                        end
                        prev = swatch
                        local f = ns.BM2_GetFilter and ns.BM2_GetFilter(myFid)
                        local fname = (f and f.name) or ("Filter " .. tostring(myFid))
                        swatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(swatch, fname) end)
                        swatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    end
                end
                rgn._lastInline = prev
            end

            -- Display-level Icon Glow (v2): permanent, every visible icon of the
            -- group glows while shown. No Max Duration setting by design: the
            -- engine offers no baseline/cap on its duration bindings.
            local GLOW_VALUES = { [0] = "None" }
            local GLOW_ORDER = { 0 }
            local Styles = EllesmereUI.Glows and EllesmereUI.Glows.STYLES
            if Styles then
                for i, entry in ipairs(Styles) do
                    -- Auto-Cast Shine and Shape Glow excluded: they live on the forbidden
                    -- slot-button subtree with no C-side equivalent to render there (stale saved picks fall back to Modern WoW Glow).
                    if not (entry.shapeGlow or entry.autocast) then
                        GLOW_VALUES[i] = entry.name
                        GLOW_ORDER[#GLOW_ORDER + 1] = i
                    end
                end
            end
            local mdRow = SettingsRow(
                { type="dropdown", text="Icon Glow",
                  values=GLOW_VALUES, order=GLOW_ORDER,
                  getValue=function() return ind.displayGlowType or 0 end,
                  setValue=function(v) ind.displayGlowType = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                { type="label", text="" })
            -- Inline class + custom color swatches, left of the dropdown.
            local PPl = EllesmereUI.PanelPP or EllesmereUI.PP
            local rightRgn = mdRow._leftRegion
            local ctrl = rightRgn._control

            local classSwatch, updateClassSwatch = EllesmereUI.BuildColorSwatch(
                rightRgn, mdRow:GetFrameLevel() + 3,
                function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 0.82, 0
                end,
                function() end,
                false, 20)
            PPl.Point(classSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            classSwatch:SetScript("OnClick", function()
                ind.displayGlowClassColor = true; ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end)
            classSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Colored")
            end)
            classSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local glowSwatch, updateGlowSwatch = EllesmereUI.BuildColorSwatch(
                rightRgn, mdRow:GetFrameLevel() + 3,
                function() return ind.displayGlowR or 1.0, ind.displayGlowG or 0.776, ind.displayGlowB or 0.376 end,
                function(r, g, b)
                    ind.displayGlowR, ind.displayGlowG, ind.displayGlowB = r, g, b
                    ReloadAndUpdate()
                end,
                false, 20)
            PPl.Point(glowSwatch, "RIGHT", classSwatch, "LEFT", -8, 0)
            glowSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(glowSwatch, "Custom Colored")
            end)
            glowSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            -- Click the dimmed custom swatch to switch back from class color.
            local origGlowClick = glowSwatch:GetScript("OnClick")
            glowSwatch:SetScript("OnClick", function(self, ...)
                if ind.displayGlowClassColor then
                    ind.displayGlowClassColor = false; ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    return
                end
                if (ind.displayGlowType or 0) == 0 then return end
                if origGlowClick then origGlowClick(self, ...) end
            end)

            local function UpdateDispGlowState()
                local noGlow = (ind.displayGlowType or 0) == 0
                local isClassColored = ind.displayGlowClassColor
                glowSwatch:SetAlpha((isClassColored or noGlow) and 0.3 or 1)
                classSwatch:SetAlpha((isClassColored and not noGlow) and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateGlowSwatch(); updateClassSwatch(); UpdateDispGlowState() end)
            UpdateDispGlowState()

            if indType == "icon" then
                _, h = W:SectionHeader(leftFrame, "PANDEMIC BORDER", sy); sy = sy - h
                local pandemicOff = function() return not ind.pandemicBorderEnabled end
                local pandemicRow = SettingsRow(
                    { type="toggle", text="Enable Pandemic Border",
                      tooltip="Highlights this indicator's icons during Blizzard's refresh window. Requires pandemic-region support from the game. The selected indicator previews the active border. Use a Lifebloom-only indicator to highlight only Lifebloom.",
                      getValue=function() return ind.pandemicBorderEnabled or false end,
                      setValue=function(v) ind.pandemicBorderEnabled = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                    { type="slider", text="Border Size", min=1, max=5, step=1,
                      disabled=pandemicOff, disabledTooltip="Enable Pandemic Border",
                      getValue=function() return ind.pandemicBorderWidth or 2 end,
                      setValue=function(v) ind.pandemicBorderWidth = v; ReloadAndUpdate() end })
                local rgn = pandemicRow._leftRegion
                local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, pandemicRow:GetFrameLevel() + 3,
                    function()
                        local c = ind.pandemicBorderColor or { r=1, g=0.2, b=0.2 }
                        return c.r, c.g, c.b
                    end,
                    function(r, g, b)
                        ind.pandemicBorderColor = { r=r, g=g, b=b }
                        ReloadAndUpdate()
                    end, false, 20)
                swatch:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
                local origClick = swatch:GetScript("OnClick")
                swatch:SetScript("OnClick", function(self, ...)
                    if pandemicOff() then return end
                    if origClick then origClick(self, ...) end
                end)
                swatch:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(swatch, pandemicOff()
                        and EllesmereUI.DisabledTooltip("Enable Pandemic Border") or "Pandemic Border Color")
                end)
                swatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function UpdatePandemicSwatch()
                    updateSwatch(); swatch:SetAlpha(pandemicOff() and 0.3 or 1)
                end
                EllesmereUI.RegisterWidgetRefresh(UpdatePandemicSwatch)
                UpdatePandemicSwatch()
            end

            -- Threshold text remains independent of the pandemic border.
            BuildThresholdRow()

        elseif typeInfo and typeInfo.placed then

            if indType == "bar" then
                -----------------------------------------------------------
                --  BAR: CORE
                -----------------------------------------------------------
                _, h = W:SectionHeader(leftFrame, "CORE", sy); sy = sy - h

                SettingsRow(
                    { type="dropdown", text="Orientation", values=ORIENT_VALUES, order=ORIENT_ORDER,
                      getValue=function() return ind.orientation or "HORIZONTAL" end,
                      -- RefreshPage(true) = full rebuild so the Width/Height + Full
                      -- Width/Height labels re-evaluate isVert and flip live (fast path only re-reads values, not static labels).
                      setValue=function(v) ind.orientation = v; ReloadAndUpdate(); EllesmereUI:RefreshPage(true) end },
                    { type="toggle", text="Own Only",
                      tooltip="Only show buffs cast by you.",
                      getValue=function() return ind.ownOnly == true end,
                      setValue=function(v) ind.ownOnly = v and true or false; ReloadAndUpdate() end })

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
                do
                    local rgn = posRow._leftRegion
                    EllesmereUI.BuildInlineCog(rgn, {
                        icon = EllesmereUI.DIRECTIONS_ICON,
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
                end

                -----------------------------------------------------------
                --  BAR: DISPLAY
                -----------------------------------------------------------
                _, h = W:SectionHeader(leftFrame, "DISPLAY", sy); sy = sy - h

                local isVert = (ind.orientation or "HORIZONTAL") == "VERTICAL"

                -- Labels flip with orientation so each slot always names the
                -- on-screen axis; each slider disables while its Full toggle is on.
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

                -- Labels flip with orientation like the sliders above; RefreshPage()
                -- so the Width/Height disabled state updates live.
                SettingsRow(
                    { type="toggle", text=isVert and "Full Height Bar" or "Full Width Bar",
                      getValue=function() return ind.barFullWidth or false end,
                      setValue=function(v) ind.barFullWidth = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                    { type="toggle", text=isVert and "Full Width Bar" or "Full Height Bar",
                      getValue=function() return ind.barFullHeight or false end,
                      setValue=function(v) ind.barFullHeight = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end })

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

                -- THRESHOLD section
                BuildThresholdRow()

            elseif indType == "square" then
                -- Unreachable: square is handled by the icon/square path above.

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
                    EllesmereUI.BuildInlineCog(rgn, {
                        icon = EllesmereUI.DIRECTIONS_ICON,
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

                SettingsRow(
                    { type="dropdown", text="Show When", values=SHOW_WHEN_VALUES_EFFECT, order=SHOW_WHEN_ORDER_EFFECT,
                      tooltip=SHOW_WHEN_EFFECT_TIP,
                      getValue=function() return "present" end,
                      setValue=function(v) ind.showWhen = "present"; ReloadAndUpdate() end },
                    { type="toggle", text="Own Only",
                      tooltip="Only show buffs cast by you.",
                      getValue=function() return ind.ownOnly == true end,
                      setValue=function(v) ind.ownOnly = v and true or false; ReloadAndUpdate() end })

                -----------------------------------------------------------
                --  FRAME BORDER: DISPLAY
                -----------------------------------------------------------
                _, h = W:SectionHeader(leftFrame, "DISPLAY", sy); sy = sy - h

                -- Offered styles: shared border-texture set minus "shadow" (identical
                -- to glow without behind/black handling) and "lightspark" (oversized
                -- outward halo), plus "Dashed" (static ants) after Solid. LibSharedMedia
                -- kept; built per-render so newly registered ones appear without a reload.
                local EXCLUDED_BORDER_STYLES = { shadow = true, lightspark = true }
                local allVals, allOrder = EllesmereUI.GetBorderTextureDropdown()
                local bsVals, bsOrder = {}, {}
                for _, k in ipairs(allOrder) do
                    if not EXCLUDED_BORDER_STYLES[k] then
                        bsVals[k] = allVals[k]
                        bsOrder[#bsOrder + 1] = k
                        if k == "solid" then
                            bsVals.dashed = "Dashed"
                            bsOrder[#bsOrder + 1] = "dashed"
                        end
                    end
                end

                -- Border Width: the dashed ants keep their 1-6 width; every other style
                -- takes an exact pixel size (borderWidthPx beside borderWidth). The step
                -- read here is the one ApplyEffectBorder draws (a textured width caps at 4).
                local bwSlot
                if (ind.borderStyle or "solid") == "dashed" then
                    bwSlot = { type="slider", text="Border Width", min=1, max=6, step=1, trackWidth=120,
                      getValue=function() return ind.borderWidth or 2 end,
                      setValue=function(v) ind.borderWidth = v; ReloadAndUpdate() end }
                else
                    local function BwStyle()
                        local s = ind.borderStyle or "solid"
                        if s == "sweepcw" or s == "sweepccw" then s = "solid" end
                        return s
                    end
                    bwSlot = EllesmereUI.BorderPxSliderCfg({
                        text = "Border Width", trackWidth = 120,
                        getStep = function()
                            local bw = ind.borderWidth or 2
                            return (BwStyle() == "solid") and bw or math.min(bw, 4)
                        end,
                        setStep = function(v) ind.borderWidth = v end,
                        getTex = BwStyle,
                        getPx = function() return ind.borderWidthPx end,
                        setPx = function(v) ind.borderWidthPx = v end,
                        apply = ReloadAndUpdate,
                    })
                    -- This surface never allowed 0 (the dashed style would inherit it).
                    bwSlot.min = 1
                end
                SettingsRow(
                    { type="dropdown", text="Border Style", values=bsVals, order=bsOrder,
                      -- Fall back to Solid if the stored style is no longer offered.
                      getValue=function()
                          local s = ind.borderStyle or "solid"
                          return bsVals[s] and s or "solid"
                      end,
                      setValue=function(v) ind.borderStyle = v; ReloadAndRebuild() end },
                    bwSlot)

                -- Dashes slot applies only to the dashed style; blank label otherwise (allowed on a section's last row).
                local ac = EllesmereUI.ACCENT_COLOR or { r = 0.05, g = 0.82, b = 0.62 }
                local dashesSlot
                if (ind.borderStyle or "solid") == "dashed" then
                    dashesSlot = { type="slider", text="Dashes", min=4, max=16, step=1, trackWidth=120,
                      getValue=function() return ind.borderDashCount or 8 end,
                      setValue=function(v) ind.borderDashCount = v; ReloadAndUpdate() end }
                else
                    dashesSlot = { type="label", text="" }
                end
                local bdrColorRow = SettingsRow(
                    { type="slider", text="Color", min=0, max=100, step=1, trackWidth=120,
                      getValue=function() return ind.borderOpacity or 100 end,
                      setValue=function(v) ind.borderOpacity = v; ReloadAndUpdate() end },
                    dashesSlot)
                do
                    local rgn = bdrColorRow._leftRegion
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

            elseif indType == "healthcolor" or indType == "bgcolor" then
                -----------------------------------------------------------
                --  HEALTH BAR COLOR / BACKGROUND COLOR: CORE
                --  (identical settings; bgcolor tints the health bar's
                --  background area instead of the fill)
                -----------------------------------------------------------
                _, h = W:SectionHeader(leftFrame, "CORE", sy); sy = sy - h

                SettingsRow(
                    { type="dropdown", text="Show When", values=SHOW_WHEN_VALUES_EFFECT, order=SHOW_WHEN_ORDER_EFFECT,
                      tooltip=SHOW_WHEN_EFFECT_TIP,
                      getValue=function() return "present" end,
                      setValue=function(v) ind.showWhen = "present"; ReloadAndUpdate() end },
                    { type="toggle", text="Own Only",
                      tooltip="Only show buffs cast by you.",
                      getValue=function() return ind.ownOnly == true end,
                      setValue=function(v) ind.ownOnly = v and true or false; ReloadAndUpdate() end })

                -----------------------------------------------------------
                --  HEALTH BAR COLOR: DISPLAY
                -----------------------------------------------------------
                _, h = W:SectionHeader(leftFrame, "DISPLAY", sy); sy = sy - h

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

            else
                -- framealpha
                -----------------------------------------------------------
                --  FRAME ALPHA: CORE
                -----------------------------------------------------------
                _, h = W:SectionHeader(leftFrame, "CORE", sy); sy = sy - h

                SettingsRow(
                    { type="dropdown", text="Show When", values=SHOW_WHEN_VALUES, order=SHOW_WHEN_ORDER,
                      getValue=function() return ind.showWhen or "present" end,
                      setValue=function(v) ind.showWhen = v; ReloadAndUpdate() end },
                    { type="toggle", text="Own Only",
                      tooltip="Only show buffs cast by you.",
                      getValue=function() return ind.ownOnly == true end,
                      setValue=function(v) ind.ownOnly = v and true or false; ReloadAndUpdate() end })

                -----------------------------------------------------------
                --  FRAME ALPHA: DISPLAY
                -----------------------------------------------------------
                _, h = W:SectionHeader(leftFrame, "DISPLAY", sy); sy = sy - h

                SettingsRow(
                    { type="slider", text="Alpha", min=5, max=100, step=1,
                      getValue=function() return floor((ind.alpha or 0.4) * 100) end,
                      setValue=function(v) ind.alpha = v / 100; ReloadAndUpdate() end },
                    { type="label", text="" })
                -- Frame Alpha has no Threshold section: its alpha multiplies with the range-fade alpha and two secret values can't be combined.
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

    -- Return 0: content lives on scrollFrame directly, so no outer scroll range.
    return 0
end

