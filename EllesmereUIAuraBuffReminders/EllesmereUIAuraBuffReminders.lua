if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIAuraBuffReminders.lua
--  Raid Buffs, Auras, and Consumables reminders: clickable SecureActionButton icons
--  with combat-aware, Midnight non-secret-spell tracking.
-------------------------------------------------------------------------------

local ADDON_NAME = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI._Pool) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS[ADDON_NAME] = select(2, ...)  -- LOD options files read this module ns via the registry

local EABR = EllesmereUI.Lite.NewAddon("EllesmereUIAuraBuffReminders")

-- WoW Forever runs a reduced module: the Raid Buffs section over that client's
-- four buffs (EABR.CollectForeverRaidBuffs) and one Forever-only section (the
-- Camp Benefits campfire buff plus custom spell IDs) collected by
-- EABR.CollectForever, with every other retail collector, its events and its
-- options sections off. Both values live on EABR, where every split file
-- reads them; retail reads FOREVER as false at each gate and nothing else
-- changes there.
EABR.FOREVER = EllesmereUI.IS_FOREVER == true
EABR.CAMP_BENEFITS = 1229741
EABR.WELL_FED = 19705
-- Food buffs not named Well Fed (Grilled Squid, Nightfin Soup, Runn Tum Tuber Surprise,
-- Dirge's Chops, Blessed Sunfruit and its juice): counted by ID, since their names are
-- shared with other buffs (Mana Regeneration is also Mageblood Potion's).
EABR.FOOD_BUFFS = { 18192, 18194, 22730, 25661, 18125, 18141 }

local _B = {}  -- beacon state table, populated later
local Known = function(id) return id and (IsPlayerSpell(id) or IsSpellKnown(id)) end
local _eabrInCombat = false
local InCombat = function() return _eabrInCombat or (InCombatLockdown and InCombatLockdown()) end
-- Whether important buffs ride the cursor right now: Attach Important Buffs to
-- Cursor, and with its Only on Cursor in Combat option only while in combat.
-- p = the profile's display table. Every combat edge refreshes the reminders,
-- so their placement follows the moment combat starts or ends.
local CursorAttachActive = function(p)
    if not (p and p.cursorAttach) then return false end
    return not p.cursorAttachCombatOnly or InCombat()
end
local isSecret = issecretvalue or function() return false end
local AURA_SCAN_LIMIT = 255  -- Midnight supports more than the legacy 40 buff limit
local DEFAULT_GLOW_COLOR = {r=1, g=0.776, b=0.376}
local DEFAULT_TEXT_COLOR = {r=1, g=1, b=1}

-- Per-profile fixups; runs at the read path since profile swaps skip OnInitialize. (1) Scale outside
-- [0.5, 3.0] (UI range) is corruption -> reset to 1.0, every call. (2) glowColorMode: one-time migration
-- per profile, never alters the stored color.
local function EnsureGlowModeMigrated(p)
    if not p then return end
    local s = p.scale
    if type(s) == "number" and (s < 0.5 or s > 3.0) then
        p.scale = 1.0
    end
    if p.glowColorMode then return end
    local c = p.glowColor
    if c and not (c.r == 1 and c.g == 0.776 and c.b == 0.376) then
        p.glowColorMode = "custom"
    else
        p.glowColorMode = "default"
    end
end

local function ResolveGlowTint(p)
    if not p then return nil end
    EnsureGlowModeMigrated(p)
    if p.glowColorMode == "class" then
        local cc = EllesmereUI.GetClassColor(EllesmereUI._playerClass)
        return cc.r, cc.g, cc.b
    end
    if p.glowColorMode ~= "custom" then return nil end
    local c = p.glowColor
    if not c then return nil end
    return c.r or 1, c.g or 0.776, c.b or 0.376
end

local TEXT_ANCHOR_POINTS = {
    BOTTOM = { "TOP",    "BOTTOM" },
    TOP    = { "BOTTOM", "TOP"    },
    CENTER = { "CENTER", "CENTER" },
    LEFT   = { "RIGHT",  "LEFT"   },
    RIGHT  = { "LEFT",   "RIGHT"  },
}
-- Shared read-only with the options preview via _G._EABR_* (main loads first).
_G._EABR_TEXT_ANCHORS = TEXT_ANCHOR_POINTS
local function GetTextAnchorPoints(p)
    local m = TEXT_ANCHOR_POINTS[(p and p.textAnchor) or "BOTTOM"] or TEXT_ANCHOR_POINTS.BOTTOM
    return m[1], m[2]
end


local db  -- set in EABR:OnInitialize()
-- Flask state snapshotted before PvP restriction activates (aura API locked in PvP).


local texCache = {}
local function Tex(id)
    local c = texCache[id]; if c then return c end
    local t = C_Spell.GetSpellTexture(id)
    if t then texCache[id] = t end; return t
end

local spellNameCache = {}
local function SpellName(id)
    local c = spellNameCache[id]; if c then return c end
    local n = C_Spell.GetSpellName(id)
    if n then spellNameCache[id] = n end; return n
end

local _cachedPlayerClass
local function GetPlayerClass()
    if not _cachedPlayerClass then
        local _, cls = UnitClass("player")
        _cachedPlayerClass = cls
    end
    return _cachedPlayerClass
end

local function GetSpecID()
    if not GetSpecialization then return nil end  -- legacy global, not registered on WoW Forever
    local s = GetSpecialization(); if not s then return nil end
    return GetSpecializationInfo(s)
end

-------------------------------------------------------------------------------
--  Font resolution (uses global font system)
-------------------------------------------------------------------------------
local function ResolveFontPath(fontName)
    if fontName and fontName ~= "__global" and EllesmereUI and EllesmereUI.ResolveFontName then
        local path = EllesmereUI.ResolveFontName(fontName)
        if path and path ~= "" then return path end
    end
    if EllesmereUI and EllesmereUI.GetFontPath then
        return EllesmereUI.GetFontPath("auraBuff")
    end
    return "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
end
local _cachedOutline
local function SetABRFont(fs, font, size)
    if not (fs and fs.SetFont) then return end
    if not _cachedOutline then _cachedOutline = EllesmereUI.GetFontOutlineFlag("auraBuff") end
    EllesmereUI.PrimeFontShadow(fs, _cachedOutline == "" and EllesmereUI.GetFontUseShadow("auraBuff"))
    fs:SetFont(font, size, _cachedOutline)
end

-------------------------------------------------------------------------------
--  ShortLabel shorten buff/aura names for icon text display
-------------------------------------------------------------------------------
local LABEL_OVERRIDES = {
    ["Battle Stance"]           = "Stance",
    ["Defensive Stance"]        = "Stance",
    ["Berserker Stance"]        = "Stance",
    ["Devotion Aura"]           = "Aura",
    ["Power Word: Fortitude"]   = "Fortitude",
    ["Arcane Intellect"]        = "Intellect",
    ["Battle Shout"]            = "Shout",
    ["Hunter's Mark"]           = "Mark",
    ["Earth Shield (Ally)"]     = "Ally",
}
local LABEL_CLASS_OVERRIDES = {
    ROGUE  = "Poison",
    SHAMAN_IMBUE  = "Weapon",
    SHAMAN_SHIELD = "Shield",
}
local function ShortLabel(name, classOverride)
    if classOverride and LABEL_CLASS_OVERRIDES[classOverride] then
        return EllesmereUI.L(LABEL_CLASS_OVERRIDES[classOverride])
    end
    if LABEL_OVERRIDES[name] then return LABEL_OVERRIDES[name] end
    return name:match("^(%S+)") or name
end

-------------------------------------------------------------------------------
--  Instance / Difficulty helpers: cached per-frame, call CacheInstanceInfo() at the start of Refresh().
-------------------------------------------------------------------------------
local _cachedIType, _cachedDiffID, _cachedMapID

-- "Pre-pull" state for the elevated Mythic-0 / keystone-lobby threshold
-- (EABR.GetShowUnderMinutes' showUnderMPlus). True from the moment you zone
-- into a dungeon until you first engage combat there; false for the rest of
-- that dungeon visit so the wide top-up window doesn't keep re-triggering
-- between pulls (it would otherwise use the pre-key threshold, up to 40 min
-- by default, for the entire run instead of just the lobby). Reset whenever
-- the map changes (new dungeon / left the instance). Covers both real
-- Mythic 0 (diff 23) and the pre-key Mythic Keystone lobby (diff 8, before
-- the timer starts) -- see InPreKeyDungeon() below.
local _dungeonPrePull = true

local function CacheInstanceInfo()
    -- The eleventh return flags World Tier scaled content (Lairs, every tier).
    local _, iType, diffID, _, _, _, _, _, _, _, hasWorldTier = GetInstanceInfo()
    _cachedIType = iType
    _cachedDiffID = tonumber(diffID) or 0
    EABR._cachedDiffID = _cachedDiffID
    EABR._cachedWorldTier = hasWorldTier == true
    if EABR.FOREVER then return end  -- the map lookup only serves the pre-key threshold window
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    if mapID ~= _cachedMapID then
        _dungeonPrePull = true
    end
    _cachedMapID = mapID
end

-- Called from PLAYER_REGEN_DISABLED: once you've actually pulled, the
-- pre-key top-up window is over for the rest of this dungeon visit.
local function MarkDungeonPullStarted()
    _dungeonPrePull = false
end

local function InRealInstancedContent()
    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then
        return false
    end
    -- Housing plots report as "scenario"; they belong to the open world.
    if _cachedIType == "scenario" and C_Housing and C_Housing.IsInsideHouseOrPlot
        and C_Housing.IsInsideHouseOrPlot() then
        return false
    end

    if _cachedIType == "party"
    or _cachedIType == "raid"
    or _cachedIType == "scenario"
    or _cachedIType == "arena"
    or _cachedIType == "pvp"
    then
        return true
    end

    return false
end

local function InMythicPlusKey()
    if EABR.FOREVER then return false end  -- no keystones on WoW Forever
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
end

-- Mythic raid diff IDs: 16 fixed-20p (PrimaryRaidMythic), 233 flex (RaidMythicFlexible). Add future IDs here so every gate below stays correct.
local function IsMythicRaidDiff(d)
    return d == 16 or d == 233
end

-- Mythic 0 dungeon (difficulty 23). A keyed M+ run is not M0.
-- Hung on EABR.
function EABR.InMythicZeroDungeon()
    if InMythicPlusKey() then return false end
    return _cachedIType == "party" and _cachedDiffID == 23
end

-- True in a Mythic Keystone party (difficulty 8) before the key timer has
-- started -- the keystone lobby. Once InMythicPlusKey() flips true (key
-- inserted and started) this goes false; that run is governed by
-- ShowUnderThresholdApplies() instead (thresholds ignored, buff-gone only).
local function InPreKeyDungeon()
    if InMythicPlusKey() then return false end
    return _cachedIType == "party" and _cachedDiffID == 8
end

local function InPvPInstance()
    return _cachedIType == "pvp" or _cachedIType == "arena"
end

-------------------------------------------------------------------------------
--  Per-section "Where to Show" visibility model. The stored table keeps only
--  unchecked buckets (value false); an absent/empty table shows everywhere.
--  All helpers hang on EABR.
-------------------------------------------------------------------------------
-- Fine-grained instanced difficulty category, or nil outside mapped content.
function EABR.CurrentDifficultyCat()
    if InMythicPlusKey() then return "d_mplus" end
    local it, d = _cachedIType, _cachedDiffID
    if it == "party" then
        if d == 23 or d == 8 then return "d_mythic" end
        if d == 2 then return "d_heroic" end
        if d == 1 then return "d_normal" end
        if d == 24 then return "d_timewalking" end
        if d == 205 then return "d_follower" end
    elseif it == "raid" then
        if IsMythicRaidDiff(d) then return "r_mythic" end
        if d == 15 or d == 6 then return "r_heroic" end
        if d == 14 or d == 3 or d == 4 or d == 5 then return "r_normal" end
        if d == 17 or d == 7 then return "r_lfr" end
        if d == 33 then return "d_timewalking" end
        -- WoW Forever raids report the legacy 40- and 20-player ids; they feed
        -- the Forever section's "Raids" bucket. Retail leaves them unmapped.
        if EABR.FOREVER and (d == 9 or d == 148) then return "r_normal" end
    elseif it == "scenario" then
        if d == 208 then return "s_delve" end
    end
    return nil
end

-- Coarse buckets matching the options multi-select: open_world, raid_mythic,
-- raid_heroic, raid_normal_lfr, dungeon_mythic (Mythic + M+), dungeon_nonmythic
-- (Heroic / Normal / Follower), timewalking, delve, lair, scenario (any non-delve
-- scenario). Returns nil for unmapped instanced content (e.g. PvP) so reminders
-- never silently vanish there.
function EABR.CurrentWhereBucket(inInstance)
    -- Lairs carry the World Tier flag instead of a difficulty id the allowlist
    -- knows; the instance gate keeps the flag from ever reclassifying the
    -- open world, whatever else it may be set on.
    if inInstance and EABR._cachedWorldTier then return "lair" end
    local cat = EABR.CurrentDifficultyCat()
    if cat == "d_mplus" or cat == "d_mythic" then return "dungeon_mythic" end
    if cat == "d_heroic" or cat == "d_normal" or cat == "d_follower" then return "dungeon_nonmythic" end
    if cat == "d_timewalking" then return "timewalking" end
    if cat == "r_mythic" then return "raid_mythic" end
    if cat == "r_heroic" then return "raid_heroic" end
    if cat == "r_normal" or cat == "r_lfr" then return "raid_normal_lfr" end
    if cat == "s_delve" then return "delve" end
    if not inInstance then return "open_world" end
    if _cachedIType == "scenario" then return "scenario" end
    return nil
end

-- Per-section gate. "In Combat" is an orthogonal state gate layered on top of
-- the location buckets.
function EABR.SectionShows(whereToShow, inInstance)
    if whereToShow and whereToShow.in_combat == false and InCombat() then return false end
    local bucket = EABR.CurrentWhereBucket(inInstance)
    if not bucket then return true end
    if not whereToShow then return true end
    return whereToShow[bucket] ~= false
end

-- Bag/equip consumable call sites share the consumables section set; the key
-- arg is retained for call-site clarity.
function EABR.ConsumableShows(co, key, inInstance)
    return EABR.SectionShows(co.whereToShow, inInstance)
end

-- Global Display thresholds. "Show Below Pre-Key" is the Mythic 0 / keystone
-- lobby value so flasks and food are topped up before the key starts.
function EABR.GetShowUnderMinutes()
    if not (db and db.profile) then return 0 end
    local disp = db.profile.display or {}
    if (EABR.InMythicZeroDungeon() or InPreKeyDungeon()) and _dungeonPrePull then
        return disp.showUnderMPlus or 40
    end
    return disp.showUnder or 5
end

-- Thresholds apply everywhere except combat and active Mythic+ keys (there a
-- reminder means the buff is fully gone).
function EABR.ShowUnderThresholdApplies()
    if InCombat() or InMythicPlusKey() then return false end
    return true
end

function EABR.IsUnderDuration(duration, expirationTime, sectionKey)
    if not (db and db.profile and duration and expirationTime and sectionKey) then return false end
    if not EABR.ShowUnderThresholdApplies() then return false end
    local thresholdSeconds = EABR.GetShowUnderMinutes() * 60
    if thresholdSeconds > 0 and duration >= thresholdSeconds then
        local now = GetTime()
        if expirationTime - now < thresholdSeconds then
            return true
        end
        local refreshAt = expirationTime - thresholdSeconds
        if refreshAt > now and (not EABR._nextDurationRefreshTime or refreshAt < EABR._nextDurationRefreshTime) then
            EABR._nextDurationRefreshTime = refreshAt
        end
    end
    return false
end

-- Talent reminder zone data and query helpers live in EllesmereUIABR_TalentReminders.lua.

-------------------------------------------------------------------------------
--  Aura query helpers (secret-value safe, Midnight 12.0). NON_SECRET_SPELL_IDS: whitelisted IDs readable via GetPlayerAuraBySpellID even during combat lockdown.
-------------------------------------------------------------------------------
local NON_SECRET_SPELL_IDS = {
    -- Preservation Evoker
    [355941]=true, [363502]=true, [364343]=true, [366155]=true,
    [367364]=true, [373267]=true, [376788]=true,
    -- Augmentation Evoker
    [360827]=true, [395152]=true, [410089]=true, [410263]=true,
    [410686]=true, [413984]=true,
    -- Resto Druid
    [774]=true, [8936]=true, [33763]=true, [48438]=true, [155777]=true,
    -- Disc Priest
    [17]=true, [194384]=true, [1253593]=true,
    -- Holy Priest
    [139]=true, [41635]=true, [77489]=true,
    -- Mistweaver Monk
    [115175]=true, [119611]=true, [124682]=true, [450769]=true,
    -- Restoration Shaman
    [974]=true, [383648]=true, [61295]=true,
    -- Holy Paladin
    [53563]=true, [156322]=true, [156910]=true, [1244893]=true,
    -- Long-term Raid Buffs
    [1126]=true, [1459]=true, [6673]=true, [21562]=true, [369459]=true,
    [462854]=true, [474754]=true,
    -- Alternate buff IDs (talent variants that provide the same effect)
    [432661]=true, [432778]=true,
    -- Devotion Aura (465) is ContextuallySecret in Midnight 12.0; not whitelisted.
    -- Blessing of the Bronze Auras
    [381732]=true, [381741]=true, [381746]=true, [381748]=true,
    [381749]=true, [381750]=true, [381751]=true, [381752]=true,
    [381753]=true, [381754]=true, [381756]=true, [381757]=true,
    [381758]=true,
    -- Long-term Self Buffs (Paladin Rites)
    [433568]=true, [433583]=true,
    -- Rogue Poisons
    [2823]=true, [8679]=true, [3408]=true, [5761]=true,
    [315584]=true, [381637]=true, [381664]=true,
    -- Shaman Imbuements
    [319773]=true, [319778]=true, [382021]=true, [382022]=true,
    [457496]=true, [457481]=true, [462757]=true, [462742]=true,
    -- Resource-like Auras
    [205473]=true, [260286]=true,
    -- Cooldowns
    [8690]=true, [20608]=true,
    -- Midnight Flasks (PvE and PvP variants; non-secret in 12.0)
    [1235110]=true, [1235108]=true, [1235111]=true, [1235057]=true, [1239355]=true,
    [1235113]=true, [1235114]=true, [1235115]=true, [1235116]=true,
    -- Partnered Trinket (Emerald Coach's Whistle)
    [383798]=true, [389581]=true,
}

-- Main-chunk locals the EUI_AuraBuffReminders_*.lua files re-import by name.
-- dbSetters and the lists beside it: every file that reads one of these
-- keeps its own copy and adds a setter here; each place that assigns it
-- writes through the Set<Name> function built below, which runs them all.
-- broken: true while an EUI_AuraBuffReminders_*.lua file loads; a file that
-- fails leaves it set, and the files behind it return at their first lines.
local ns = select(2, ...)
ns._abrInternals = {
    _B = _B, AURA_SCAN_LIMIT = AURA_SCAN_LIMIT, CacheInstanceInfo = CacheInstanceInfo,
    CursorAttachActive = CursorAttachActive, DEFAULT_TEXT_COLOR = DEFAULT_TEXT_COLOR, EABR = EABR,
    EnsureGlowModeMigrated = EnsureGlowModeMigrated, GetPlayerClass = GetPlayerClass,
    GetSpecID = GetSpecID, GetTextAnchorPoints = GetTextAnchorPoints, InCombat = InCombat,
    InMythicPlusKey = InMythicPlusKey, InPvPInstance = InPvPInstance,
    InRealInstancedContent = InRealInstancedContent, isSecret = isSecret, Known = Known,
    MarkDungeonPullStarted = MarkDungeonPullStarted,
    NON_SECRET_SPELL_IDS = NON_SECRET_SPELL_IDS, ResolveFontPath = ResolveFontPath,
    ResolveGlowTint = ResolveGlowTint, SetABRFont = SetABRFont, ShortLabel = ShortLabel,
    SpellName = SpellName, Tex = Tex, texCache = texCache,
    dbSetters = { function(v) db = v end },
    inCombatSetters = { function(v) _eabrInCombat = v end },
    outlineSetters = { function(v) _cachedOutline = v end },
    huntersMarkSetters = {},
    panelOpenSetters = {},
    iconAnchorSetters = {},
    combatAnchorSetters = {},
    cursorAnchorSetters = {},
    broken = false,
}
-- Set<Name> hands a new value to every copy registered in <name>Setters.
for setter, listName in pairs({
    SetDB = "dbSetters", SetInCombat = "inCombatSetters", SetCachedOutline = "outlineSetters",
    SetHuntersMarkNeeded = "huntersMarkSetters", SetPanelOpen = "panelOpenSetters",
    SetIconAnchor = "iconAnchorSetters", SetCombatAnchor = "combatAnchorSetters",
    SetCursorAnchor = "cursorAnchorSetters",
}) do
    local list = ns._abrInternals[listName]
    ns._abrInternals[setter] = function(v)
        for i = 1, #list do list[i](v) end
    end
end
-- A re-import of a name this table lacks fails where the part file loads,
-- not later as a nil upvalue inside one of its functions.
setmetatable(ns._abrInternals, { __index = function(_, k)
    error("ns._abrInternals has no entry " .. tostring(k), 2)
end })
