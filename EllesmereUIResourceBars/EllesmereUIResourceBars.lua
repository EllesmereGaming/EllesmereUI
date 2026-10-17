if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIResourceBars.lua
--  Health bar, primary resource bar (mana/rage/energy/etc), secondary
--  resource display (combo points, holy power, runes, etc), smooth
--  animations, combat fade, low-resource alerts, class-colored bars
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.NewCombatQueue and EllesmereUI.SetFrameScale and EllesmereUI._Pool) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (the Call Totem Bar scales its Edit Mode system through the parent's SetFrameScale)
EllesmereUI._ModuleNS[ADDON_NAME] = ns  -- LOD options files read this module ns via the registry
local ERB = EllesmereUI.Lite.NewAddon(ADDON_NAME)
ns.ERB = ERB

-- Per-addon border texture defaults (size key = borderSize 0-4); shared by
-- TBB, class/power/health bars, and cast bar
EllesmereUI.RegisterBorderDefaults("resourcebars", EllesmereUI.BORDER_DEFAULTS_BARS)

-- Snap x/y to the physical pixel grid. Optional `pos` (CENTER/CENTER anchor)
-- gets dim-aware snapping, preserving the +0.5 offset odd-pixel-dim frames
-- need to land edges on whole physical pixels.
local function SnapXY(x, y, frame, pos)
    local PPa = EllesmereUI and EllesmereUI.PP
    if not (PPa and x and y and frame) then return x or 0, y or 0 end
    local es = frame:GetEffectiveScale()
    local isCenterAnchor = pos and (pos.point == "CENTER")
        and (pos.relPoint == "CENTER" or pos.relPoint == nil)
    if isCenterAnchor and PPa.SnapCenterForDim then
        return PPa.SnapCenterForDim(x, frame:GetWidth() or 0, es),
               PPa.SnapCenterForDim(y, frame:GetHeight() or 0, es)
    elseif PPa.SnapForES then
        return PPa.SnapForES(x, es), PPa.SnapForES(y, es)
    end
    return x, y
end

local UnitHealthMax = UnitHealthMax
local UnitPowerMax = UnitPowerMax
local UnitClass = UnitClass
-- Vanilla-based clients (WoW Forever) have no specialization API: every
-- reader then sees "no spec", the state a fresh character is in anyway.
local GetSpecialization = GetSpecialization or function() return nil end
local GetShapeshiftFormID = GetShapeshiftFormID

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local function GetRBFont() return EllesmereUI.GetFontPath("resourceBars") end
local function SetRBFont(fs, font, size) EllesmereUI.ApplyModuleFont(fs, font, size, "resourceBars") end
-- Shared with EUI_ResourceBars_SwingTimer.lua (same font lane as the cast bar text).
ns.GetRBFont = GetRBFont
ns.SetRBFont = SetRBFont

-- Cast-bar text side anchoring (mirrors nameplate/unit-frame cast text). Spell text
-- and duration share one line; duration reserves a slot on its side and pushes spell
-- text inward when they share a side; center is never pushed. On ns not a file
-- local. side "left"|"right"|"center"; pushed = duration shares
-- this side; reserve = duration's reserved width (used only when pushed).
-- Returns: point (anchor), xOff (base, before user X offset), justify
function ns.GetCastTextAnchor(side, pushed, reserve)
    if side == "center" then
        return "CENTER", 0, "CENTER"
    elseif side == "left" then
        local base = 4
        if pushed then base = base + reserve end
        return "LEFT", base, "LEFT"
    else -- "right"
        local base = -4
        if pushed then base = base - reserve end
        return "RIGHT", base, "RIGHT"
    end
end

-- A FontString does not re-layout on SetJustifyH alone; clear-then-reset forces it
-- (must be a real change, or the identical-string set is deduped and skipped).
-- GetText may return a secret cast name; SetText accepts secrets untouched, so the
-- round-trip is safe.
function ns.ReflowFontString(fs)
    if not fs then return end
    local t = fs:GetText()
    fs:SetText("")
    fs:SetText(t or "")
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
--  Channel tick data: spellID -> { ticks, [modSpell, modTicks] } or { tickInterval }
--  ticks = fixed tick count (haste speeds ticks up, count unchanged).
--  tickInterval = fixed seconds/tick (haste extends duration, adds ticks).
--  missiles = fencepost count: first missile AT channel start, last AT the
--  channel end, so M missiles span M-1 intervals (interior marks at
--  i/(M-1)); addMissiles = { [spellID] = extra } raises M while the player
--  knows the spell or carries the aura, and a recast during a running
--  channel keeps the outgoing cast's schedule -- see ShowChannelTicks.
--  modSpell/modTicks: use modTicks if player knows modSpell (talent).
--  Spell IDs verified against Wowhead/Warcraft Wiki; add a row when a spell
--  reworks or a new channeled spell is added.
-------------------------------------------------------------------------------
local CHANNEL_TICK_DATA = {
    -- Evoker
    -- Disintegrate deals damage ON channel start and then once per interval
    -- (3 intervals base; Azure Celerity shortens the interval ONLY -> 4), so
    -- its interior marks sit at i/N of the ACTUAL duration and a chained
    -- recast keeps the outgoing cast's damage cadence -- see the
    -- intervalCount model in ShowChannelTicks.
    -- Cadence and talent behavior credited to Xephyris -- thanks!
    [356995]  = { intervalCount = 3, modSpell = 1219723, modIntervalCount = 4 },
    -- Priest
    [15407]   = { ticks = 6 },                                     -- Mind Flay
    [48045]   = { ticks = 6 },                                     -- Mind Sear
    [64843]   = { ticks = 4 },                                     -- Divine Hymn
    -- Penance hits 3 times over 2s with the first at the cast (ticks = 2);
    -- Castigation (193134) adds a hit (ticks = 3).
    [47757]   = { ticks = 2, modSpell = 193134, modTicks = 3 },    -- Penance (Heal)
    [47758]   = { ticks = 2, modSpell = 193134, modTicks = 3 },    -- Penance (DPS)
    [373129]  = { ticks = 2, modSpell = 193134, modTicks = 3 },    -- Penance / Dark Reprimand (DPS)
    [400171]  = { ticks = 2, modSpell = 193134, modTicks = 3 },    -- Penance / Dark Reprimand (Heal)
    -- Mage
    -- Arcane Missiles: 5 missiles, fenceposted (see the missiles model
    -- above), so only 3 interior marks base. Amplification (236628) adds 2
    -- missiles and the tier set 2pc (1296581) adds 1.
    [5143]    = { missiles = 5, addMissiles = { [236628] = 2, [1296581] = 1 } },
    [12051]   = { ticks = 6 },                                     -- Evocation
    [205021]  = { ticks = 5 },                                     -- Ray of Frost
    -- Druid
    [740]     = { ticks = 4 },                                     -- Tranquility
    -- Hunter
    -- Rapid Fire shoots once at channel start and once at channel end. Quick
    -- Draw (459794) adds three shots without changing the channel duration.
    [257044]  = { missiles = 7, addMissiles = { [459794] = 3 } },  -- Rapid Fire
    -- Demon Hunter
    [198013]  = { tickInterval = 0.2 },                            -- Eye Beam
    [473728]  = { tickInterval = 0.2 },                            -- Void Ray (Devourer)
    [212084]  = { ticks = 10 },                                    -- Fel Devastation
    -- Warlock
    [198590]  = { ticks = 5 },                                     -- Drain Soul
    [755]     = { ticks = 5 },                                     -- Health Funnel
    [234153]  = { ticks = 5 },                                     -- Drain Life
    -- Death Knight
    [206931]  = { ticks = 3 },                                     -- Blooddrinker
    -- Monk
    [113656]  = { ticks = 4 },                                     -- Fists of Fury
    [115175]  = { ticks = 12 },                                     -- Soothing Mist
    [443028]  = { ticks = 4 },                                     -- Celestial Conduit
    -- Racial
    [291944]  = { ticks = 6 },                                     -- Regeneratin (Zandalari)
}

-- WoW Forever: every rank is its own spell ID. Mind Flay channels for 3s and
-- ticks every second, none at the cast (ticks = 3). Penance channels for 2s and
-- fires a bolt at the cast and every second after (ticks = 2), as on retail;
-- the cast bar shows the damage or heal channel the cast triggers, so each rank
-- lists both, plus its channeled cast spell.
if EllesmereUI.IS_FOREVER then
    for _, id in ipairs({ 15407, 17311, 17312, 17313, 17314, 18807 }) do
        CHANNEL_TICK_DATA[id] = { ticks = 3 }                      -- Mind Flay
    end
    for _, id in ipairs({
        402261, 402277, 402174,                                    -- Penance rank 1: damage, heal, cast
        1240734, 1240732, 1240720,                                 -- rank 2
        1240736, 1240733, 1240721,                                 -- rank 3
        1316994, 1316992, 1316995,                                 -- rank 4
    }) do
        CHANNEL_TICK_DATA[id] = { ticks = 2 }                      -- Penance
    end
end


-------------------------------------------------------------------------------
--  Class/Spec resource mapping
-------------------------------------------------------------------------------
-- Class/power colors route through EllesmereUI.GetClassColor/GetPowerColor so
-- General Options overrides apply. Metatable converts {r=,g=,b=} to {r,g,b} arrays.
local CLASS_COLORS = setmetatable({}, { __index = function(_, classFile)
    if not EllesmereUI or not EllesmereUI.GetClassColor then return nil end
    local c = EllesmereUI.GetClassColor(classFile)
    if c then return { c.r, c.g, c.b } end
    return nil
end })

-- Power type enum -> EUI power key string mapping for GetPowerColor lookup
local POWER_ENUM_TO_KEY = {
    [PT.MANA]        = "MANA",
    [PT.RAGE]        = "RAGE",
    [PT.FOCUS]       = "FOCUS",
    [PT.ENERGY]      = "ENERGY",
    [PT.RUNIC_POWER] = "RUNIC_POWER",
    [PT.LUNAR_POWER] = "LUNAR_POWER",
    [PT.MAELSTROM]   = "MAELSTROM",
    [PT.INSANITY]    = "INSANITY",
    [PT.FURY]        = "FURY",
    [PT.PAIN]        = "PAIN",
}

-- Resolve any power key (enum number, string, or _BAR variant) to the
-- canonical string key used by EllesmereUI.GetPowerColor.
local POWER_KEY_ALIAS = {
    ["FOCUS_BAR"]       = "FOCUS",
    ["INSANITY_BAR"]    = "INSANITY",
    ["LUNAR_POWER_BAR"] = "LUNAR_POWER",
    ["MAELSTROM_BAR"]   = "MAELSTROM",
    ["MAELSTROM_WEAPON"] = "MAELSTROM",
}

local function ResolvePowerKey(powerKey)
    if type(powerKey) == "number" then return POWER_ENUM_TO_KEY[powerKey] end
    return POWER_KEY_ALIAS[powerKey] or powerKey
end

-- Power color lookup through EUI's color system, falling back to class color. MEMOIZED
-- (rule 6): an uncached __index rebuilt {r,g,b} on every bar-update lookup (~170KB/min
-- churn for palette-stable values). Resolved entries are rawset so hits skip this
-- function; nil results (parent not ready) are NOT cached, so early-login lookups
-- retry. One memo input: parent palette (invalidation hook below).
local POWER_COLORS = setmetatable({}, { __index = function(t, powerKey)
    -- nil lookups are LEGAL here and must answer nil, never cache: BM/MM
    -- hunters have no primary power (GetPrimaryPowerType returns nil by
    -- design -- Focus is the class resource bar), and the options swatches
    -- index this memo with that result. rawset with a nil key throws.
    if powerKey == nil then return nil end
    if not EllesmereUI then return nil end
    local key = ResolvePowerKey(powerKey)
    if key and EllesmereUI.GetPowerColor then
        local c = EllesmereUI.GetPowerColor(key)
        if c then
            local v = { c.r, c.g, c.b }
            rawset(t, powerKey, v)
            return v
        end
    end
    if EllesmereUI.GetClassColor then
        local _, classFile = UnitClass("player")
        local cc = classFile and EllesmereUI.GetClassColor(classFile)
        if cc then
            local v = { cc.r, cc.g, cc.b }
            rawset(t, powerKey, v)
            return v
        end
    end
    return nil
end })
-- ApplyColorsToOUF is the parent's universal "colours changed" entry point (swatch
-- edits, resets, global-mode toggle, Pull Colors From, profile switches), so wiping
-- the memo there covers every palette edge; bars simply recolor next tick.
if EllesmereUI and hooksecurefunc then
    hooksecurefunc(EllesmereUI, "ApplyColorsToOUF", function()
        table.wipe(POWER_COLORS)
    end)
end

-- Blizzard player-frame power-bar atlas per power token, validated at runtime via
-- GetAtlasInfo: unknown tokens (Stagger/Ironfur) or missing atlases fall back to
-- the regular bar texture, so an atlas rename never renders broken art. On ns.
ns._crAtlasSuffix = {
    MANA = "Mana", RAGE = "Rage", FOCUS = "Focus", ENERGY = "Energy",
    RUNIC_POWER = "RunicPower", LUNAR_POWER = "AstralPower",
    MAELSTROM = "Maelstrom", INSANITY = "Insanity", FURY = "Fury",
    PAIN = "Pain",
}
-- Tint sink for atlas-mode fills: stands in for the fill texture at live recolor
-- sites so threshold/band/base tints go nowhere while the surrounding logic
-- (text recoloring, curve evaluation) keeps running.
ns._atlasNoTint = { SetVertexColor = function() end }
ns._crAtlasClass = {
    DEATHKNIGHT = "DeathKnight", DEMONHUNTER = "DemonHunter",
    DRUID = "Druid", EVOKER = "Evoker", HUNTER = "Hunter", MAGE = "Mage",
    MONK = "Monk", PALADIN = "Paladin", PRIEST = "Priest", ROGUE = "Rogue",
    SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior",
}
function ns.GetBlizzardPowerAtlas(powerKey)
    local resolved = ResolvePowerKey(powerKey) or powerKey
    local suffix = ns._crAtlasSuffix[resolved]
    if not suffix or not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
    -- Try Midnight family first (e.g. "Unit_Druid_AstralPower_Fill"), then classless
    -- and legacy HUD spellings; each candidate is validated, so a miss falls back.
    local _, classFile = UnitClass("player")
    local classToken = classFile and ns._crAtlasClass[classFile]
    local candidates = {}
    if classToken then
        candidates[#candidates + 1] = "Unit_" .. classToken .. "_" .. suffix .. "_Fill"
    end
    candidates[#candidates + 1] = "Unit_" .. suffix .. "_Fill"
    candidates[#candidates + 1] = "UI-HUD-UnitFrame-Player-PortraitOff-Bar-" .. suffix
    candidates[#candidates + 1] = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-" .. suffix
    for i = 1, #candidates do
        local name = candidates[i]
        if C_Texture.GetAtlasInfo(name) then
            return name
        end
    end
    return nil
end

-- Dark theme fill/bg COLOUR comes from the per-profile Dark Mode palette
-- (GetDarkModeFill/GetDarkModeBg), fetched live; alpha stays local since the
-- Dark Mode opacity sliders apply to Unit/Raid Frames only.
local DARK_FILL_A = 0.90
local DARK_BG_A = 1


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
    -- WoW Forever: the class table below is retail's (hunters use mana
    -- there, not Focus), so ask the client what the player uses. Covers
    -- every class and druid forms with no second table to maintain.
    if EllesmereUI.IS_FOREVER then
        -- Druid "Power Type: Mana" keeps Mana in every form. Its own string
        -- key (no specs there), so it never meets the spec IDs keyed below.
        local pp = ERB.db and ERB.db.profile and ERB.db.profile.primary
        local ov = pp and pp.powerTypeOverride
        if ov and ov.foreverDruid then
            local _, cf = UnitClass("player")
            if cf == "DRUID" then return PT.MANA end
        end
        local live = UnitPowerType("player")
        if type(live) == "number" then return live end
    end
    local _, classFile = UnitClass("player")
    local spec = GetSpecialization()
    local form = GetShapeshiftFormID()
    -- powerTypeOverride is keyed by SPEC ID, never by the GetSpecialization()
    -- index: one profile holds one set, so an index key collides across classes
    -- and the same flag means opposite things per class (slot 3 is Guardian,
    -- Shadow and Augmentation, wanting Mana, Insanity and Ebon Might). Cached, so
    -- this is one table read after the first call per spec.
    local ovSpec = _G._ERB_ResolveSpecIDCached and _G._ERB_ResolveSpecIDCached() or nil

    -- Druid form handling
    if classFile == "DRUID" then
        local pp = ERB.db and ERB.db.profile and ERB.db.profile.primary
        local ov = pp and pp.powerTypeOverride
        if ovSpec and ov and ov[ovSpec] then
            if spec == 1 then return PT.LUNAR_POWER end  -- Balance alt: Astral Power
            return PT.MANA                                -- Feral/Guardian alt: Mana
        end
        if form == 1 then return PT.ENERGY end
        if form == 5 then return PT.RAGE end
        return PT.MANA
    end

    if classFile == "SHAMAN" and spec == 1 then
        local pp = ERB.db and ERB.db.profile and ERB.db.profile.primary
        local ov = pp and pp.powerTypeOverride
        if ovSpec and ov and ov[ovSpec] then return PT.MAELSTROM end  -- Elemental alt: Maelstrom
    end
    if classFile == "PRIEST" and spec == 3 then
        local pp = ERB.db and ERB.db.profile and ERB.db.profile.primary
        local ov = pp and pp.powerTypeOverride
        if ovSpec and ov and ov[ovSpec] then return PT.INSANITY end   -- Shadow alt: Insanity
    end
    if classFile == "HUNTER" then
        -- BM/MM show Focus as the class resource bar, not power; Survival keeps
        -- it as power. Override: hunterFocusAsPower.
        if spec == 1 or spec == 2 then
            local pp = ERB.db and ERB.db.profile and ERB.db.profile.secondary
            if pp and pp.hunterFocusAsPower then return PT.FOCUS end
            return nil
        end
    end
    if classFile == "MONK" then
        if spec == 1 then return PT.ENERGY end  -- Brewmaster
        if spec == 2 then return PT.MANA end    -- Mistweaver
        if spec == 3 then return PT.ENERGY end  -- Windwalker
    end
    if classFile == "DEMONHUNTER" then
        return PT.FURY
    end
    if classFile == "EVOKER" and spec == 3 then
        local pp = ERB.db and ERB.db.profile and ERB.db.profile.primary
        local ov = pp and pp.powerTypeOverride
        -- Inverted against the others: Augmentation's DEFAULT is Ebon Might and
        -- the override opts into plain Mana. Same spec-ID key either way.
        if not (ovSpec and ov and ov[ovSpec]) then return "EBON_MIGHT" end
        return PT.MANA
    end

    return PRIMARY_CLASS_MAP[classFile] or PT.MANA
end

-- Ebon Might (Augmentation Evoker) -- aura-based countdown on the power bar
local EBON_MIGHT_SPELL_ID = 395296
local EBON_MIGHT_DURATION = 20

local ICICLES_SPELL_ID = 205473

-- Prot Warrior Ignore Pain: stacking buff 190456 (0-100 stacks). ALL player aura fields
-- are SECRET even out of combat (field-confirmed: spellId, name, applications) and the
-- id is restriction-flagged, so the aura API gives nothing; Blizzard's tracked-buff icon
-- is the only stack source. IP caps at 30% max health (CAP), so stacks and absorbs-vs-
-- cap are the same 0-100% fullness -- see UpdateSecondaryResource. DURATION drives the
-- moving hash line, reset on cast since aura expiry is secret (same approach as Ironfur
-- ticks). One namespace table for the feature.
local IP = {
    SPELL = 190456,
    -- Violent Outburst consumption: Shield Slam with the proc up refreshes Ignore
    -- Pain's duration WITHOUT an Ignore Pain cast event, so the hash line needs the
    -- indirect edge too. IDs are game data, field-verify on change: Shield Slam
    -- 23922 (stable since classic), Violent Outburst proc aura 386478.
    SHIELD_SLAM = 23922,
    VO_PROC = 386478,
    CAP = 0.30,
    DURATION = 12,
    hashEndTime = 0,
    hookedFS = {},
    nextScan = 0,
}

-- Pooled scratch for the Ignore Pain overlay layer list (rebuilt every absorb tick):
-- reuse one array + sub-tables. UpdateSecondaryResource is not re-entrant, so a
-- shared counter is safe. On IP, not new locals.
IP.layers = {}
IP.layerN = 0
function IP.push(step, r, g, b, a)
    IP.layerN = IP.layerN + 1
    local t = IP.layers[IP.layerN]
    if not t then t = {}; IP.layers[IP.layerN] = t end
    t.step, t.r, t.g, t.b, t.a = step, r, g, b, a
end

local function GetIcicleCount()
    local _, classFile = UnitClass("player")
    local spec = GetSpecialization()
    if classFile ~= "MAGE" or spec ~= 3 then
        return 0
    end

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(ICICLES_SPELL_ID)
        if aura then
            local count = aura.applications or aura.charges or aura.points or 0
            if count > 5 then count = 5 end
            return count
        end
        return 0
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 255 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            if aura.spellId == ICICLES_SPELL_ID then
                local count = aura.applications or aura.charges or aura.points or 0
                if count > 5 then count = 5 end
                return count
            end
        end
    end

    return 0
end

-------------------------------------------------------------------------------
--  Guardian Druid Ironfur tracker (bar-based, moving hash lines). Each cast adds a
--  tick moving right->left as its buff decays. Duration is talent-aware (Ursoc's
--  Endurance 9s base else 7s; Guardian of Elune adds +3s to the next cast after
--  Mangle). Driven by UNIT_SPELLCAST_SUCCEEDED so secret-value aura restrictions
--  can't cause drift.
-------------------------------------------------------------------------------
local IRONFUR_SPELL       = 192081
local URSOCS_ENDURANCE    = 393611  -- base 9s vs 7s
local GUARDIAN_OF_ELUNE   = 155578  -- talent: Mangle -> next Ironfur +3s
local MANGLE_SPELL        = 33917
local FRENZIED_REGEN      = 22842
local IRONFUR_GOE_BONUS   = 3
local IRONFUR_GOE_WINDOW  = 15
local ironfurTicks        = {}   -- array of { endTime=, duration= }

local function IronfurBaseDuration()
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(URSOCS_ENDURANCE) then
        return 9
    end
    return 7
end

local function GetSecondaryResource()
    local _, classFile = UnitClass("player")
    local spec = GetSpecialization()
    local form = GetShapeshiftFormID()
    -- WoW Forever: combo points are the only class resource there (Rogue, and
    -- Druid in Cat Form); every other class has none.
    if EllesmereUI.IS_FOREVER == true and classFile ~= "ROGUE" and not (classFile == "DRUID" and form == 1) then return nil end

    if classFile == "PALADIN" then
        local mx = UnitPowerMax("player", PT.HOLY_POWER)
        return { power = PT.HOLY_POWER, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points" }
    elseif classFile == "ROGUE" then
        local mx = UnitPowerMax("player", PT.COMBO)
        -- onTarget: WoW Forever keeps combo points on the target, so the count is
        -- read with GetComboPoints and repainted on a target swap.
        return { power = PT.COMBO, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points",
                 onTarget = (EllesmereUI.IS_FOREVER == true and GetComboPoints ~= nil) or nil }
    elseif classFile == "DRUID" and spec == 3 and form == 5
           and ERB.db and ERB.db.profile and ERB.db.profile.secondary
           and ERB.db.profile.secondary.guardianIronfurBar then
        -- Guardian Ironfur duration bar, Bear Form only; other forms fall through
        -- to their default (combo points in Cat, nothing in caster/moonkin/travel).
        -- max is a normalized fraction (0..1).
        ns._internals.SetIronfurBaseDur(IronfurBaseDuration())
        return { power = "IRONFUR_BAR", max = 1, type = "bar" }
    elseif classFile == "DRUID" and form == 1 then
        local mx = UnitPowerMax("player", PT.COMBO)
        return { power = PT.COMBO, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points",
                 onTarget = (EllesmereUI.IS_FOREVER == true and GetComboPoints ~= nil) or nil }
    elseif classFile == "DRUID" and spec == 1 then
        -- Balance: Astral Power as a class resource bar (like Elemental maelstrom)
        local mx = UnitPowerMax("player", PT.LUNAR_POWER)
        if issecretvalue and issecretvalue(mx) then mx = 100 end
        if not mx or mx <= 0 then mx = 100 end
        return { power = "LUNAR_POWER_BAR", max = mx, type = "bar" }
    elseif classFile == "DRUID" and spec == 3 then
        -- Guardian, Ironfur bar disabled: no class resource (form==1 branch
        -- above already handled the cat-form combo swap).
        return nil
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
        -- frac: renders SUB-UNIT values so the value moves without the whole-unit
        -- count changing. Destruction (spec index 3, same spec the partial-pip
        -- render checks) spends/gains shard FRAGMENTS in tenths; the flag makes
        -- UpdateSecondaryResource's value guard compare the fragment read and keeps
        -- ArmTick/PollTick polling, since out-of-combat fragment decay has no event.
        return { power = PT.SOUL_SHARDS, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5,
                 type = "points", frac = (spec == 3) or nil }
    elseif classFile == "DEATHKNIGHT" then
        return { power = PT.RUNES, max = 6, type = "runes" }
    elseif classFile == "EVOKER" then
        local mx = UnitPowerMax("player", PT.ESSENCE)
        return { power = PT.ESSENCE, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points" }
    elseif classFile == "MAGE" and spec == 1 then
        local mx = UnitPowerMax("player", PT.ARCANE)
        return { power = PT.ARCANE, max = (not issecretvalue or not issecretvalue(mx)) and mx or 4, type = "points" }
    elseif classFile == "MAGE" and spec == 3 then
        return { power = "ICICLES", max = 5, type = "custom" }
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
        -- BM and MM: Focus as a class resource bar (unless overridden)
        local pp = ERB.db and ERB.db.profile and ERB.db.profile.secondary
        if pp and pp.hunterFocusAsPower then return nil end
        local mx = UnitPowerMax("player", PT.FOCUS)
        if issecretvalue and issecretvalue(mx) then mx = 100 end
        if not mx or mx <= 0 then mx = 100 end
        return { power = "FOCUS_BAR", max = mx, type = "bar" }
    elseif classFile == "WARRIOR" and spec == 3
           and ERB.db and ERB.db.profile and ERB.db.profile.secondary
           and ERB.db.profile.secondary.protIgnorePainBar then
        -- Protection Ignore Pain bar: total absorbs vs the IP cap (30% max health,
        -- see IP.CAP); stacks are unreadable (aura data fully secret). Toggle-gated,
        -- existing users pinned OFF via migration "resourcebars_protwar_ignorepain_existing_off_v1".
        local mx = UnitHealthMax("player") or 1
        if issecretvalue and issecretvalue(mx) then mx = 1 end
        if mx <= 0 then mx = 1 end
        return { power = "IGNOREPAIN_BAR", max = mx * IP.CAP, type = "bar" }
    elseif classFile == "WARRIOR" and spec == 2 then
        return { power = "WHIRLWIND_STACKS", max = 4, type = "custom" }
    elseif classFile == "WARRIOR" and spec == 1
           and ERB.db and ERB.db.profile and ERB.db.profile.secondary
           and ERB.db.profile.secondary.armsSweepingStrikesBar then
        -- Arms Sweeping Strikes charges: flat 18 cap since 12.1 (12 from the ability +
        -- 6 from Broad Strokes). Base max here; BuildBars refreshes from the tracker.
        -- Opt-in, default off; Unit Frames/personal Nameplate readouts ignore the toggle.
        return { power = "SWEEPING_STRIKES", max = 18, type = "custom" }
    end

    return nil
end

-- Main-chunk locals the EUI_ResourceBars_*.lua files re-import by name.
-- mainFrameSetters and the lists beside it: every file that reads one of
-- these keeps its own copy and adds a setter here; a place that assigns it
-- writes through the Set<Name> function built below, which runs them all
-- (a file that holds the only copy of a name assigns its local directly).
-- broken: true while an EUI_ResourceBars_*.lua file loads; a file that
-- fails leaves it set, and the files behind it return at their first lines.
ns._internals = {
    CHANNEL_TICK_DATA = CHANNEL_TICK_DATA, CLASS_COLORS = CLASS_COLORS, DARK_BG_A = DARK_BG_A,
    DARK_FILL_A = DARK_FILL_A, EBON_MIGHT_DURATION = EBON_MIGHT_DURATION,
    EBON_MIGHT_SPELL_ID = EBON_MIGHT_SPELL_ID, ERB = ERB, FRENZIED_REGEN = FRENZIED_REGEN,
    GetIcicleCount = GetIcicleCount, GetPrimaryPowerType = GetPrimaryPowerType,
    GetRBFont = GetRBFont, GetSecondaryResource = GetSecondaryResource,
    GetSpecialization = GetSpecialization, GUARDIAN_OF_ELUNE = GUARDIAN_OF_ELUNE, IP = IP,
    IRONFUR_GOE_BONUS = IRONFUR_GOE_BONUS, IRONFUR_GOE_WINDOW = IRONFUR_GOE_WINDOW,
    IRONFUR_SPELL = IRONFUR_SPELL, IronfurBaseDuration = IronfurBaseDuration,
    ironfurTicks = ironfurTicks, MANGLE_SPELL = MANGLE_SPELL, POWER_COLORS = POWER_COLORS,
    POWER_ENUM_TO_KEY = POWER_ENUM_TO_KEY, PT = PT, SetRBFont = SetRBFont, SnapXY = SnapXY,
    ironfurBaseDurSetters = {}, ironfurGoEUntilSetters = {}, mainFrameSetters = {},
    healthBarSetters = {}, primaryBarSetters = {}, secondaryFrameSetters = {},
    secondaryBarSetters = {}, castBarFrameSetters = {}, gcdBarFrameSetters = {},
    totemBarFrameSetters = {}, isInCombatSetters = {}, cachedClassSetters = {},
    cachedPrimarySetters = {}, cachedSecondarySetters = {}, ebonMightExpirySetters = {},
    UpdateCastBarSetters = {}, UpdateGCDBarSetters = {}, stageThresholdsSetters = {},
    essenceNextTickSetters = {}, essenceLastCountSetters = {}, essenceTickDurSetters = {},
    broken = false,
}
-- Set<Name> hands a new value to every copy registered in <name>Setters.
for setter, listName in pairs({
    SetIronfurBaseDur = "ironfurBaseDurSetters", SetIronfurGoEUntil = "ironfurGoEUntilSetters",
    SetMainFrame = "mainFrameSetters", SetHealthBar = "healthBarSetters",
    SetPrimaryBar = "primaryBarSetters", SetSecondaryFrame = "secondaryFrameSetters",
    SetSecondaryBar = "secondaryBarSetters", SetCastBarFrame = "castBarFrameSetters",
    SetGCDBarFrame = "gcdBarFrameSetters", SetTotemBarFrame = "totemBarFrameSetters",
    SetInCombat = "isInCombatSetters", SetCachedClass = "cachedClassSetters",
    SetCachedPrimary = "cachedPrimarySetters", SetCachedSecondary = "cachedSecondarySetters",
    SetEbonMightExpiry = "ebonMightExpirySetters", SetUpdateCastBar = "UpdateCastBarSetters",
    SetUpdateGCDBar = "UpdateGCDBarSetters", SetStageThresholds = "stageThresholdsSetters",
    SetEssenceNextTick = "essenceNextTickSetters",
    SetEssenceLastCount = "essenceLastCountSetters",
    SetEssenceTickDur = "essenceTickDurSetters",
}) do
    local list = ns._internals[listName]
    ns._internals[setter] = function(v)
        for i = 1, #list do list[i](v) end
    end
end
-- A re-import of a name this table lacks fails where the part file loads,
-- not later as a nil upvalue inside one of its functions.
setmetatable(ns._internals, { __index = function(_, k)
    error("ns._internals has no entry " .. tostring(k), 2)
end })
