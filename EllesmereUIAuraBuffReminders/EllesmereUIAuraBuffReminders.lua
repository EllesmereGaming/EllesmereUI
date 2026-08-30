if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIAuraBuffReminders.lua
--  Raid Buffs, Auras, and Consumables reminders: clickable SecureActionButton icons
--  with combat-aware, Midnight non-secret-spell tracking.
-------------------------------------------------------------------------------

local ADDON_NAME = ...
if not (EllesmereUI and EllesmereUI._ModuleNS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS[ADDON_NAME] = select(2, ...)  -- LOD options files read this module ns via the registry

local EABR = EllesmereUI.Lite.NewAddon("EllesmereUIAuraBuffReminders")


local _B = {}  -- beacon state table, populated later
local Known = function(id) return id and (IsPlayerSpell(id) or IsSpellKnown(id)) end
local _eabrInCombat = false
local _encounterSnapshotTime = nil
local _needGroupAura = false
local _isEvokerOwnOnRaid = false
local _groupAuraBroadActive = false
local _groupAuraDirty = false
local InCombat = function() return _eabrInCombat or (InCombatLockdown and InCombatLockdown()) end
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local isSecret = issecretvalue or function() return false end
local AURA_SCAN_LIMIT = 255  -- Midnight supports more than the legacy 40 buff limit
local DEFAULT_GLOW_COLOR = {r=1, g=0.776, b=0.376}
local DEFAULT_TEXT_COLOR = {r=1, g=1, b=1}

-- Per-profile fixups; runs at the read path since profile swaps skip OnInitialize. (1) Scale outside
-- [0.5, 3.0] (UI range) is corruption -> reset to 1.0, every call. (2) glowColorMode: one-time migration
-- per profile, never alters the stored color. (Kept here, not a new local -- file is near the Lua 200-local cap.)
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


-- Hunter's Mark combat state: true on REGEN_DISABLED, cleared on cast/combat end; OOC falls back to target debuff check.
local _huntersMarkNeeded = false

local db  -- set in EABR:OnInitialize()
-- Flask state snapshotted before PvP restriction activates (aura API locked in PvP).


local texCache = {}
local function Tex(id)
    local c = texCache[id]; if c then return c end
    local t = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or GetSpellTexture(id)
    if t then texCache[id] = t end; return t
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
    local s = GetSpecialization(); if not s then return nil end
    return GetSpecializationInfo(s)
end

-------------------------------------------------------------------------------
--  Font resolution (uses global font system)
-------------------------------------------------------------------------------
local function ResolveFontPath(fontName)
    if EllesmereUI and EllesmereUI.GetFontPath then
        return EllesmereUI.GetFontPath("auraBuff")
    end
    return "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
end
local function GetABROutline()
    return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("auraBuff")) or ""
end
local function GetABRUseShadow()
    return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow("auraBuff")
end
local _cachedOutline
local function SetABRFont(fs, font, size)
    if not (fs and fs.SetFont) then return end
    if not _cachedOutline then _cachedOutline = GetABROutline() end
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, _cachedOutline == "") end
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
    local _, iType, diffID = GetInstanceInfo()
    _cachedIType = iType
    _cachedDiffID = tonumber(diffID) or 0
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
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
end

-- Mythic raid diff IDs: 16 fixed-20p (PrimaryRaidMythic), 233 flex (RaidMythicFlexible). Add future IDs here so every gate below stays correct.
local function IsMythicRaidDiff(d)
    return d == 16 or d == 233
end

-- Mythic 0 dungeon (difficulty 23). A keyed M+ run is not M0.
-- Hung on EABR (this chunk sits at the Lua 5.1 200-local cap).
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

-- Mythic 0 dungeon or Mythic raid (fixed or flex)
local function InMythicZeroDungeonOrMythicRaid()
    if EABR.InMythicZeroDungeon() then return true end
    if IsInRaid() and IsMythicRaidDiff(_cachedDiffID) then return true end
    return false
end

local function InPvPInstance()
    return _cachedIType == "pvp" or _cachedIType == "arena"
end

-------------------------------------------------------------------------------
--  Per-section "Where to Show" visibility model. The stored table keeps only
--  unchecked buckets (value false); an absent/empty table shows everywhere.
--  All helpers hang on EABR (200-local cap).
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
    elseif it == "scenario" then
        if d == 208 then return "s_delve" end
    end
    return nil
end

-- Coarse buckets matching the options multi-select: open_world, raid_mythic,
-- raid_heroic, raid_normal_lfr, dungeon_mythic (Mythic + M+), dungeon_nonmythic
-- (Heroic / Normal / Follower), timewalking, delve. Returns nil for unmapped
-- instanced content (e.g. PvP) so reminders never silently vanish there.
function EABR.CurrentWhereBucket(inInstance)
    local cat = EABR.CurrentDifficultyCat()
    if cat == "d_mplus" or cat == "d_mythic" then return "dungeon_mythic" end
    if cat == "d_heroic" or cat == "d_normal" or cat == "d_follower" then return "dungeon_nonmythic" end
    if cat == "d_timewalking" then return "timewalking" end
    if cat == "r_mythic" then return "raid_mythic" end
    if cat == "r_heroic" then return "raid_heroic" end
    if cat == "r_normal" or cat == "r_lfr" then return "raid_normal_lfr" end
    if cat == "s_delve" then return "delve" end
    if not inInstance then return "open_world" end
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

-------------------------------------------------------------------------------
--  Pre-combat aura snapshot
-------------------------------------------------------------------------------
local _preCombatAuraCache = {}  -- [spellID] = true/false, snapshotted at REGEN_DISABLED

local function _isRuntimeNonSecret(id)
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        return not C_Secrets.ShouldSpellAuraBeSecret(id)
    end
    return true  -- if API missing, assume non-secret (pre-12.0 client)
end

local function SnapshotPlayerAuras()
    wipe(_preCombatAuraCache)
    for id in pairs(NON_SECRET_SPELL_IDS) do
        local result = C_UnitAuras.GetPlayerAuraBySpellID(id)
        _preCombatAuraCache[id] = (result ~= nil)
    end
    -- Also snapshots non-whitelisted auras (e.g. Devotion Aura) going secret when a
    -- partymate combats first. 12.1: index scan hard-errors under restrictions (M+/raid) even OOC; whitelisted lookups still work, extras skipped.
    if EllesmereUI.AuraKit and EllesmereUI.AuraKit.AurasRestricted() then return end
    for i = 1, AURA_SCAN_LIMIT do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local sid = aura.spellId
        if sid and not isSecret(sid) and not NON_SECRET_SPELL_IDS[sid] then
            _preCombatAuraCache[sid] = true
        end
    end
end

-- Pre-combat snapshot for ownOnRaid buffs (Source of Magic, Blistering Scales).
local _preCombatOwnOnRaidCache = {}  -- [spellID] = true/false
local _ownOnRaidIDs = { 369459, 360827, 474754 }  -- Source of Magic, Blistering Scales, Symbiotic Relationship
local SnapshotOwnOnRaidBuffs  -- forward declaration; defined after _unitHasBuffFromPlayer

-- Pre-allocated scratch tables for hot per-Refresh functions (avoids GC churn)
local _idLookupScratch  = {}
local _lookupScratch    = {}

-------------------------------------------------------------------------------
--  Per-refresh aura helpers: targeted GetPlayerAuraBySpellID lookups (zero-alloc)
--  instead of scanning ~20-40 aura tables per refresh; GetAuraDataByIndex only as a name-based-check fallback.
-------------------------------------------------------------------------------
local _AC = { valid = false, nameScanned = false, byName = {} }

-- Lightweight reset; the expensive name scan is deferred lazily to first use.
local function BuildPlayerAuraCache()
    _AC.valid = not InCombat()
    _AC.nameScanned = false
    -- srcByID is only needed by PlayerHasSelfCastAuraByID; wiped lazily there
end

-- Lazy: runs once per refresh, only when a name-based check (WellFed/Flask/ByName) needs it.
function _AC.ensureNames()
    if _AC.nameScanned then return end
    _AC.nameScanned = true
    wipe(_AC.byName)
    if InCombat() then return end
    -- 12.1: index scans hard-error under restrictions even out of combat.
    if EllesmereUI.AuraKit and EllesmereUI.AuraKit.AurasRestricted() then return end
    for i = 1, AURA_SCAN_LIMIT do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local aName = aura.name
        if aName and not isSecret(aName) then
            _AC.byName[aName] = true
        end
    end
end

local function IsUnderDuration(duration, expirationTime, sectionKey)
    return EABR.IsUnderDuration(duration, expirationTime, sectionKey)
end

local function PlayerHasAuraByID(spellIDs, sectionKey)
    if not spellIDs or not spellIDs[1] then return true end
    local inCombat = InCombat()
    -- Direct GetPlayerAuraBySpellID lookup (zero-alloc, OOC+combat for whitelisted IDs); non-whitelisted IDs fall back to the pre-combat snapshot.
    for j = 1, #spellIDs do
        local id = spellIDs[j]
        if NON_SECRET_SPELL_IDS[id] then
            local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
            if ok then
                if result ~= nil then
                    if sectionKey and IsUnderDuration(result.duration, result.expirationTime, sectionKey) then
                        return false
                    end
                    return true
                end
                if inCombat and _preCombatAuraCache[id] then return true end
            else
                if inCombat and _preCombatAuraCache[id] then return true end
            end
        elseif not inCombat then
            -- Non-whitelisted OOC: GetPlayerAuraBySpellID may return secret values, but non-nil still means the aura exists.
            local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
            if ok and result ~= nil then
                -- 12.1: fields can be secret even OOC in restricted content; math on secrets errors, so presence alone counts then.
                local dur, exp = result.duration, result.expirationTime
                if dur ~= nil and exp ~= nil and not isSecret(dur) and not isSecret(exp) then
                    if sectionKey and IsUnderDuration(dur, exp, sectionKey) then
                        return false
                    end
                end
                return true
            end
        else
            if _preCombatAuraCache[id] then return true end
        end
    end
    return false
end

-- Stances are shapeshift forms, not auras (GetPlayerAuraBySpellID can't see them); scan the stance bar instead. Returns (known-in-bar, currently-active).
local function GetStanceState(stanceSpellID)
    local numForms = GetNumShapeshiftForms()
    for i = 1, numForms do
        local _, isActive, _, spellID = GetShapeshiftFormInfo(i)
        if spellID == stanceSpellID then
            return true, isActive
        end
    end
    return false, false
end

-- Same idea, but checks a list of spellIDs instead of one fixed form index.
local function IsAnyShapeshiftFormActive(spellIDs)
    local numForms = GetNumShapeshiftForms()
    for i = 1, numForms do
        local _, isActive, _, spellID = GetShapeshiftFormInfo(i)
        if isActive then
            for _, id in ipairs(spellIDs) do
                if spellID == id then return true end
            end
        end
    end
    return false
end

-- 12.1: aura restrictions apply in M+/raids even OOC, and index scans HARD-ERROR there (not just secret results). Every
-- OOC-only scan checks AuraKit.AurasRestricted() inline (no helper local -- this chunk sits at the Lua 5.1 200-local cap).

-- Shared helpers for group aura scanning (hoisted to avoid per-call closure allocation)
local function _unitOk(u) return UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u) end
local function _unitHasBuff(u, spellIDs)
    local inCombat = InCombat()
    -- Fast path for player: use GetPlayerAuraBySpellID for whitelisted IDs
    if UnitIsUnit(u, "player") then
        for j = 1, #spellIDs do
            local id = spellIDs[j]
            if NON_SECRET_SPELL_IDS[id] then
                local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
                if ok then
                    if result ~= nil then return true end
                    if inCombat and _preCombatAuraCache[id] then return true end
                else
                    if inCombat and _preCombatAuraCache[id] then return true end
                end
            end
        end
    else
        -- Non-player units: GetUnitAuraBySpellID for whitelisted IDs; works in combat for non-secret IDs.
        for j = 1, #spellIDs do
            local id = spellIDs[j]
            if NON_SECRET_SPELL_IDS[id] then
                local ok, result = pcall(C_UnitAuras.GetUnitAuraBySpellID, u, id)
                if ok and result ~= nil and not isSecret(result) then
                    return true
                end
            end
        end
    end
    -- Iterate auras for non-whitelisted IDs: OOC and outside restricted content only (scan errors under restriction). Skipped for player (covered above).
    if not inCombat and not UnitIsUnit(u, "player")
        and not (EllesmereUI.AuraKit and EllesmereUI.AuraKit.AurasRestricted()) then
        for i = 1, AURA_SCAN_LIMIT do
            local aura = C_UnitAuras.GetAuraDataByIndex(u, i, "HELPFUL")
            if not aura then break end
            local sid = aura.spellId
            if sid and not isSecret(sid) then
                for j = 1, #spellIDs do if sid == spellIDs[j] then return true end end
            end
        end
    end
    return false
end

-- True if the buff's source is the player. Non-player units: OOC iteration only, false in combat (caller uses the snapshot).
local function _unitHasBuffFromPlayer(u, spellIDs)
    local inCombat = InCombat()
    local idLookup = _idLookupScratch
    wipe(idLookup)
    for j = 1, #spellIDs do idLookup[spellIDs[j]] = true end

    if UnitIsUnit(u, "player") then
        -- Player-self: GetPlayerAuraBySpellID for whitelisted IDs
        for id in pairs(idLookup) do
            if NON_SECRET_SPELL_IDS[id] then
                local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
                if ok and aura ~= nil and not isSecret(aura) then
                    local fromMe = aura.isFromPlayerOrPlayerPet
                    if fromMe and not isSecret(fromMe) and fromMe == true then
                        return true
                    end
                    local src = aura.sourceUnit
                    if src and not isSecret(src) and UnitIsUnit(src, "player") then
                        return true
                    end
                end
            end
        end
        if not inCombat and not (EllesmereUI.AuraKit and EllesmereUI.AuraKit.AurasRestricted()) then
            for i = 1, AURA_SCAN_LIMIT do
                local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                if not aura then break end
                local sid = aura.spellId
                if sid and not isSecret(sid) and idLookup[sid] then
                    local src = aura.sourceUnit
                    if src and not isSecret(src) and UnitIsUnit(src, "player") then
                        return true
                    end
                end
            end
        end
        return false
    end

    if inCombat then return false end  -- sourceUnit secret in combat, caller uses snapshot
    -- Fast path: 1 API call per whitelisted ID instead of scanning every aura on the unit via GetAuraDataByIndex.
    local needScan = false
    for id in pairs(idLookup) do
        if NON_SECRET_SPELL_IDS[id] then
            local aura = C_UnitAuras.GetUnitAuraBySpellID(u, id)
            if aura and not isSecret(aura) then
                local src = aura.sourceUnit
                if src and not isSecret(src) then
                    if UnitIsUnit(src, "player") then return true end
                else
                    return true  -- sourceUnit unavailable OOC, assume ours
                end
            end
        else
            needScan = true
        end
    end
    if not needScan then return false end
    -- Scan errors under restriction; skip (caller falls back to snapshot).
    if EllesmereUI.AuraKit and EllesmereUI.AuraKit.AurasRestricted() then return false end
    -- Fallback: full scan for non-whitelisted IDs only
    for i = 1, AURA_SCAN_LIMIT do
        local aura = C_UnitAuras.GetAuraDataByIndex(u, i, "HELPFUL")
        if not aura then break end
        local sid = aura.spellId
        if sid and not isSecret(sid) and idLookup[sid] then
            local src = aura.sourceUnit
            if src and not isSecret(src) then
                if UnitIsUnit(src, "player") then return true end
            else
                return true  -- sourceUnit unavailable OOC, assume ours
            end
        end
    end
    return false
end

-- Forward-declared earlier; assigned now that _unitHasBuffFromPlayer exists.
local _snapScratch = {}  -- reused for SnapshotOwnOnRaidBuffs
SnapshotOwnOnRaidBuffs = function()
    wipe(_preCombatOwnOnRaidCache)
    for _, id in ipairs(_ownOnRaidIDs) do
        local found = false
        _snapScratch[1] = id
        if _unitHasBuffFromPlayer("player", _snapScratch) then found = true end
        if not found then
            if IsInRaid() then
                for i = 1, GetNumGroupMembers() do
                    if _unitHasBuffFromPlayer("raid"..i, _snapScratch) then found = true; break end
                end
            elseif IsInGroup() then
                for i = 1, GetNumSubgroupMembers() do
                    if _unitHasBuffFromPlayer("party"..i, _snapScratch) then found = true; break end
                end
            end
        end
        _preCombatOwnOnRaidCache[id] = found
    end
end

-- True only if the player cast the buff on themselves. OOC only -- combatOk must be false for any aura using this check.
local function PlayerHasSelfCastAuraByID(spellIDs)
    if not spellIDs or not spellIDs[1] then return true end
    if InCombat() then return false end  -- safety: can't read sourceUnit in combat
    -- Direct lookup: for whitelisted IDs, GetPlayerAuraBySpellID returns full aura data incl. sourceUnit (zero iteration needed).
    for j = 1, #spellIDs do
        local id = spellIDs[j]
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if ok and aura ~= nil and not isSecret(aura) then
            local src = aura.sourceUnit
            if src and not isSecret(src) and UnitIsUnit(src, "player") then
                return true
            end
            -- If sourceUnit is unavailable OOC, assume ours
            if not src or isSecret(src) then return true end
        end
    end
    return false
end

-- Range check mirrors raid frames: UnitInRange (~40yd helpful, combat-safe, unprotected) is primary, but can be a SECRET
-- value in instances (raid frames feed it to SetAlphaFromBoolean instead of branching). When secret here, falls back to
-- UnitIsVisible (~100yd, same phase/zone) -- proven branch-safe by the raid frames' ghost-aura sweep; coarser than true cast range but excludes cross-wing/zone/phase false positives.
local function _unitInRange(u)
    if UnitIsUnit(u, "player") then return true end
    if not UnitExists(u) then return false end
    local inRange, checked = UnitInRange(u)
    if not (isSecret(inRange) or isSecret(checked)) and checked then
        return inRange == true
    end
    -- Secret or uncheckable: visibility fallback
    local vis = UnitIsVisible(u)
    if isSecret(vis) then return true end
    return vis == true
end

-- Counts how many in-range beneficiaries have the buff vs how many should
-- (the "12/15" coverage badge). `benefit` is the buff's benefit KEY
-- ("intellect"/"attackPower"/nil = everyone). EABR.UnitBenefits resolves it
-- spec-aware when comm data exists, class-level otherwise, and skips units
-- whose identity reads come back secret (teardown/restriction edges).
-- Returns have, total.
local function CountGroupBuffCoverage(spellIDs, benefit)
    local have, total = 0, 0
    if not IsInGroup() then
        if EABR.UnitBenefits("player", benefit) and _unitOk("player") then
            total = 1
            if _unitHasBuff("player", spellIDs) then have = 1 end
        end
        return have, total
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid"..i
            if _unitOk(u) and UnitIsPlayer(u) and _unitInRange(u) then
                if EABR.UnitBenefits(u, benefit) then
                    total = total + 1
                    if _unitHasBuff(u, spellIDs) then have = have + 1 end
                end
            end
        end
    else
        if EABR.UnitBenefits("player", benefit) and _unitOk("player") then
            total = total + 1
            if _unitHasBuff("player", spellIDs) then have = have + 1 end
        end
        for i = 1, GetNumSubgroupMembers() do
            local u = "party"..i
            if _unitOk(u) and UnitIsPlayer(u) and _unitInRange(u) then
                if EABR.UnitBenefits(u, benefit) then
                    total = total + 1
                    if _unitHasBuff(u, spellIDs) then have = have + 1 end
                end
            end
        end
    end
    return have, total
end

-- True if the buff exists on any group member, any source. Used for Symbiotic Relationship.
local function BuffExistsOnAnyGroupMember(spellIDs)
    if _unitHasBuff("player", spellIDs) then return true end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            if _unitHasBuff("raid"..i, spellIDs) then return true end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            if _unitHasBuff("party"..i, spellIDs) then return true end
        end
    end
    return false
end

-- True if the player's own cast exists on any group member, OR no in-range member is a valid target (suppress either way). Used for Source of Magic, Blistering Scales.
local function PlayerOwnBuffOnAnyGroupMember(spellIDs)
    if _unitHasBuffFromPlayer("player", spellIDs) then return true end
    local anyInRangeWithoutBuff = false
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid"..i
            if _unitOk(u) and not UnitIsUnit(u, "player") then
                if _unitHasBuffFromPlayer(u, spellIDs) then return true end
                if _unitInRange(u) then anyInRangeWithoutBuff = true end
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local u = "party"..i
            if _unitOk(u) then
                if _unitHasBuffFromPlayer(u, spellIDs) then return true end
                if _unitInRange(u) then anyInRangeWithoutBuff = true end
            end
        end
    end
    -- No reminder if nobody reachable is missing the buff.
    return not anyInRangeWithoutBuff
end

-------------------------------------------------------------------------------
--  Weapon type classification (for weapon enchant matching)
-------------------------------------------------------------------------------
local BLADED_SET, BLUNT_SET, RANGED_SET
do
    local W = (Enum and Enum.ItemWeaponSubclass) or {}
    local function setFrom(...)
        local t = {}
        for i = 1, select("#", ...) do local v = select(i, ...); if v ~= nil then t[v] = true end end
        return t
    end
    BLADED_SET = setFrom(W.Axe1H, W.Axe2H, W.Sword1H, W.Sword2H, W.Dagger, W.Polearm, W.Warglaive)
    BLUNT_SET  = setFrom(W.Mace1H, W.Mace2H, W.Staff, W.Fist)
    RANGED_SET = setFrom(W.Bow, W.Gun, W.Crossbow, W.Wand)
end

local function GetWeaponCategory(slotID)
    local itemID = GetInventoryItemID("player", slotID)
    if not itemID then return nil end
    local _, _, _, equipLoc, _, classID, subClassID
    if C_Item and C_Item.GetItemInfoInstant then
        _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    else
        _, _, _, equipLoc, _, classID, subClassID = GetItemInfoInstant(itemID)
    end
    if not classID or classID ~= ((Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2) then return nil end
    if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then return nil end
    if subClassID and BLADED_SET[subClassID] then return "BLADED" end
    if subClassID and BLUNT_SET[subClassID]  then return "BLUNT" end
    if subClassID and RANGED_SET[subClassID] then return "RANGED" end
    return "NEUTRAL"
end

-- Off-hand slot holds a shield. Gates the shield-only imbue reminders
-- (requireShield rows); on EABR, not a local, since this file sits at the
-- 200-local cap. UNIT_INVENTORY_CHANGED already refreshes, so no new event.
function EABR.HasShieldEquipped()
    local itemID = GetInventoryItemID("player", 17)
    if not itemID then return false end
    local _, _, _, equipLoc
    if C_Item and C_Item.GetItemInfoInstant then
        _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
    else
        _, _, _, equipLoc = GetItemInfoInstant(itemID)
    end
    return equipLoc == "INVTYPE_SHIELD"
end

-------------------------------------------------------------------------------
--  Raid buff beneficiaries (class-level). Only Intellect/Attack Power are stat-restricted (versatility/stamina/
--  skyfury/bronze help everyone, no filter). A class is listed if ANY spec wants the stat -- hybrids may over-count, never under.
-------------------------------------------------------------------------------
local BUFF_BENEFICIARIES = {
    intellect = {
        MAGE = true, WARLOCK = true, PRIEST = true, DRUID = true,
        SHAMAN = true, MONK = true, EVOKER = true, PALADIN = true,
        DEMONHUNTER = true, -- Devourer (1480) is Intellect; Havoc/Vengeance are not
    },
    attackPower = {
        WARRIOR = true, ROGUE = true, HUNTER = true, DEATHKNIGHT = true,
        PALADIN = true, MONK = true, DRUID = true, DEMONHUNTER = true, SHAMAN = true,
    },
}

-- Set of player classes present in the group (online, alive, in range),
-- excluding the local player. Built on demand for the receiver view ("I am
-- missing others' buffs") so a buff is only flagged when someone who can
-- cast it is actually nearby. Secret class tokens are skipped (identity
-- restriction edges). Hung on EABR (200-local cap).
EABR._groupClassSet = EABR._groupClassSet or {}
function EABR.BuildGroupClassSet()
    local set = wipe(EABR._groupClassSet)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid"..i
            if _unitOk(u) and UnitIsPlayer(u) and not UnitIsUnit(u, "player") and _unitInRange(u) then
                local _, class = UnitClass(u)
                if class ~= nil and not isSecret(class) then set[class] = true end
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local u = "party"..i
            if _unitOk(u) and UnitIsPlayer(u) and _unitInRange(u) then
                local _, class = UnitClass(u)
                if class ~= nil and not isSecret(class) then set[class] = true end
            end
        end
    end
    return set
end

-------------------------------------------------------------------------------
--  Spec-aware beneficiaries. Group members' specs arrive over addon comms
--  (LibSpecialization, cached by player name in EABR._groupSpecs); when a
--  member's spec is unknown (no LibSpec-embedding addon) the class table
--  above is the fallback -- spec sharpens, class never under-counts. Only
--  the two stat-filtered buffs consult these sets.
-------------------------------------------------------------------------------
EABR.SPEC_BENEFITS = {
    intellect = {
        [62]=true, [63]=true, [64]=true,          -- Mage
        [265]=true, [266]=true, [267]=true,       -- Warlock
        [256]=true, [257]=true, [258]=true,       -- Priest
        [1467]=true, [1468]=true, [1473]=true,    -- Evoker
        [102]=true, [105]=true,                   -- Druid: Balance, Restoration
        [262]=true, [264]=true,                   -- Shaman: Elemental, Restoration
        [270]=true,                               -- Monk: Mistweaver
        [65]=true,                                -- Paladin: Holy
        [1480]=true,                               -- Demon Hunter: Devourer (Intellect, not Agility)
    },
    attackPower = {
        [71]=true, [72]=true, [73]=true,          -- Warrior
        [259]=true, [260]=true, [261]=true,       -- Rogue
        [253]=true, [254]=true, [255]=true,       -- Hunter
        [250]=true, [251]=true, [252]=true,       -- Death Knight
        [577]=true, [581]=true,                   -- Demon Hunter: Havoc, Vengeance
        [103]=true, [104]=true,                   -- Druid: Feral, Guardian
        [66]=true, [70]=true,                     -- Paladin: Protection, Retribution
        [268]=true, [269]=true,                   -- Monk: Brewmaster, Windwalker
        [263]=true,                               -- Shaman: Enhancement
    },
}

-- Name-keyed spec cache filled by the LibSpecialization group callback
-- (wired in OnEnable). Entries self-heal: a rejoining player rebroadcasts
-- on their own group-join, overwriting any stale spec. Bounded growth
-- (name -> number), so no pruning needed.
EABR._groupSpecs = EABR._groupSpecs or {}

-- Resolves a unit's specID: own spec directly (always readable), others
-- from the comm cache keyed the way the lib keys senders (Name for same
-- realm, Name-Realm cross-realm).
function EABR.GroupSpecFor(u)
    if UnitIsUnit(u, "player") then return GetSpecID() end
    local n, r = UnitNameUnmodified(u)
    if n == nil or isSecret(n) then return nil end
    if r ~= nil and not isSecret(r) and r ~= "" then
        n = n .. "-" .. r
    end
    return EABR._groupSpecs[n]
end

-- Whether a unit benefits from a stat-filtered buff. Resolution ladder:
-- (1) cached spec verdict when known and mapped (unknown/starter spec IDs
-- fall through); (2) assigned-ROLE refinement for combos the role alone
-- decides (no comms needed); (3) the class table. Unreadable class = not
-- counted (coverage skips the unit).
function EABR.UnitBenefits(u, benefit)
    if not benefit then return true end
    local specSet = EABR.SPEC_BENEFITS[benefit]
    if specSet then
        local spec = EABR.GroupSpecFor(u)
        if spec then
            if specSet[spec] then return true end
            -- A spec listed under any benefit set is a real, mapped spec:
            -- its absence here is a definitive no. Anything else (starter
            -- specs, future IDs) falls back to the checks below.
            for _, set in pairs(EABR.SPEC_BENEFITS) do
                if set[spec] then return false end
            end
        end
    end
    local classSet = BUFF_BENEFICIARIES[benefit]
    if not classSet then return true end
    local _, class = UnitClass(u)
    if class == nil or isSecret(class) then return false end
    if not classSet[class] then return false end
    -- Role refinement for members with no spec data: some class+benefit
    -- pairs are decided by the role alone -- Intellect only serves the
    -- HEALER spec of Paladin/Monk (and never a Druid tank); Attack Power
    -- never serves the healer spec of these hybrids. Ambiguous combos
    -- (e.g. a DAMAGER Druid: Balance wants int, Feral wants AP) and
    -- unassigned ("NONE") or secret roles fall through to the class answer.
    -- Effective role: the player's spec wins over a stale assigned role.
    local role = EllesmereUI.UnitEffectiveRole(u)
    if role ~= nil and not isSecret(role) then
        if benefit == "intellect" then
            if (class == "PALADIN" or class == "MONK") and (role == "DAMAGER" or role == "TANK") then
                return false
            end
            if class == "DRUID" and role == "TANK" then
                return false
            end
        elseif benefit == "attackPower" then
            if role == "HEALER" and (class == "PALADIN" or class == "MONK"
                or class == "DRUID" or class == "SHAMAN") then
                return false
            end
        end
    end
    return true
end

-- Whether the local player benefits from a raid buff (spec-aware; class
-- fallback). Buffs with no benefit key help everyone.
function EABR.PlayerBenefitsFromBuff(buff)
    return EABR.UnitBenefits("player", buff.benefit) and true or false
end

-------------------------------------------------------------------------------
--  SPELL DATA Raid Buffs (all non-secret in 12.0, work in combat)
-------------------------------------------------------------------------------
-- Resolves a spell's display name from ID in client locale (English fallback), so labels follow client language. Exposed as _G._EABR_SpellName for options.
_G._EABR_SpellName = function(spellID, fallback)
    local n = spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    return n or fallback
end

-- Returns the legacy GetWeaponEnchantInfo tuple shape (hasMH, mhExpireMs, mhCharges, mhEnchantID, hasOH,
-- ohExpireMs, ohCharges, ohEnchantID). Prefers C_PaperDollInfo.GetTemporaryEnchantmentInfo (12.1: GetWeaponEnchantInfo is a deprecation-CVar shim there); remainingTimeMs maps 1:1 to legacy ms values. On EABR -- 200-local cap.
EABR.WeaponEnchants = function()
    if C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo then
        local mh = C_PaperDollInfo.GetTemporaryEnchantmentInfo(INVSLOT_MAINHAND)
        local oh = C_PaperDollInfo.GetTemporaryEnchantmentInfo(INVSLOT_OFFHAND)
        return (mh and true or false), mh and mh.remainingTimeMs,
            mh and mh.chargesRemaining, mh and mh.enchantID,
            (oh and true or false), oh and oh.remainingTimeMs,
            oh and oh.chargesRemaining, oh and oh.enchantID
    end
    return GetWeaponEnchantInfo()
end

local RAID_BUFFS = {
    { key="motw",   class="DRUID",   name="Mark of the Wild",       castSpell=1126,   buffIDs={1126,432661},    check="raid" },
    { key="bshout", class="WARRIOR", name="Battle Shout",           castSpell=6673,   buffIDs={6673},    check="raid", benefit="attackPower" },
    { key="fort",   class="PRIEST",  name="Power Word: Fortitude",  castSpell=21562,  buffIDs={21562},   check="raid" },
    { key="ai",     class="MAGE",    name="Arcane Intellect",       castSpell=1459,   buffIDs={1459,432778},    check="raid", benefit="intellect" },
    { key="bronze", class="EVOKER",  name="Blessing of the Bronze", castSpell=364342,
      buffIDs={381732,381741,381746,381748,381749,381750,381751,381752,381753,381754,381756,381757,381758},
      check="raid" },
    { key="sky",    class="SHAMAN",  name="Skyfury",                castSpell=462854, buffIDs={462854},  check="raid" },
    -- Hunter's Mark: disabled (under maintenance); entry intentionally omitted.
}

-------------------------------------------------------------------------------
--  SPELL DATA Auras (some non-secret, some still OOC-only)
-------------------------------------------------------------------------------
local AURAS = {
    -- Symbiotic Relationship: player gets a buff when active (group only)
    { key="symbiotic",  class="DRUID",   name="Symbiotic Relationship", castSpell=474750, buffIDs={474754},
      check="player", combatOk=false, requireGroup=true },
    -- Warrior stances: shapeshift forms via stance bar (not auras), OOC only. Arms->Battle, Fury->Berserker, Prot->Defensive; reminder hides once active, suppressed if unknown.
    { key="battle_stance",  class="WARRIOR", name="Battle Stance",   castSpell=386164, buffIDs={386164},
      check="player", specs={71}, combatOk=false, isStance=true },
    { key="berserk_stance", class="WARRIOR", name="Berserker Stance", castSpell=386196, buffIDs={386196},
      check="player", specs={72}, combatOk=false, isStance=true },
    { key="def_stance",  class="WARRIOR", name="Defensive Stance",  castSpell=386208, buffIDs={386208},
      check="player", specs={73}, combatOk=false, isStance=true },
    -- Shadowform OOC only (Void Form 194249 also satisfies); formSpellIDs lists every form that counts as active,
    -- for the combat/PvP fallback where the aura API is restricted.
    { key="shadowform", class="PRIEST",  name="Shadowform",        castSpell=232698, buffIDs={232698, 194249},
      check="player", specs={258}, combatOk=false, formSpellIDs={232698, 194249, 185916} },
    -- Paladin Aura: only Devotion satisfies in dungeons/raids, any aura elsewhere; noPvP because Devotion Aura is ContextuallySecret in PvP even OOC.
    -- nameFallback: with a second Paladin's aura also active, the source is
    -- ambiguous and GetPlayerAuraBySpellID(465) can come back nil (fully
    -- withheld, not just secret) even though the buff is up -- a name scan
    -- catches it before the reminder false-fires.
    { key="devo_aura",  class="PALADIN", name="Devotion Aura",     castSpell=465,
      buffIDs={465, 32223, 317920}, instanceBuffIDs={465}, nameFallback="Devotion Aura",
      check="player", combatOk=false, noPvP=true },
    -- Beacon of Light: standalone IsSpellOverlayed system (not checked by CollectAuras)
    { key="bol",        class="PALADIN", name="Beacon of Light",   castSpell=53563,  buffIDs={53563},
      standalone=true, notIfKnown=200025 },
    -- Beacon of Faith: standalone IsSpellOverlayed system (not checked by CollectAuras)
    { key="bof",        class="PALADIN", name="Beacon of Faith",   castSpell=156910, buffIDs={156910},
      standalone=true },
    -- Source of Magic (369459, non-secret): applies to a healer target, not the caster -- check if player's cast exists on any group member.
    { key="som",        class="EVOKER",  name="Source of Magic",   castSpell=369459, buffIDs={369459},
      check="ownOnRaid", combatOk=true, requireInstanceGroup=true },
    -- Blistering Scales: requireTalent omitted (Regenerative Chitin is a passive modifier).
    { key="blistering_scales", class="EVOKER", name="Blistering Scales", castSpell=360827,
      buffIDs={360827}, check="ownOnRaid", combatOk=true,
      requireInstanceGroup=true },
    -- Bestow Weyrnstone: OOC only. Tracks target aura, not the one on self.
    { key="bestow_weyrnstone", class="EVOKER", name="Bestow Weyrnstone", castSpell=408233,
      buffIDs={410318}, check="ownOnRaid", combatOk=false,
      specs={1473}, requireInstanceGroup=true },
    -- Timelessness: OOC only.
    { key="timelessness", class="EVOKER", name="Timelessness", castSpell=412710,
      buffIDs={412710}, check="ownOnRaid", combatOk=false,
      specs={1473}, requireInstanceGroup=true },
}

-------------------------------------------------------------------------------
--  Healthstone / Soulstone / Partnered Trinket tracking
-------------------------------------------------------------------------------
local HEALTHSTONE_ITEM_IDS = { 5512, 224464 }  -- Healthstone, Demonic Healthstone

local PARTNERED_TRINKET = {
    key = "coaches_whistle", name = "Emerald Coach's Whistle",
    buffID = 389581, buffIDs = {389581, 383798}, icon = 134157, duration = 3600,
}

-- Pet tracking: classes that summon permanent pets
local PET_CLASSES = { HUNTER = true, WARLOCK = true, DEATHKNIGHT = true, MAGE = true }

-- If the player knows ANY of these, they use their own imbue system (not generic oils/stones), so the weapon-enchant reminder is suppressed.
local _IMBUE_EXCLUDE_SPELLS = {
    382021,  -- Earthliving Weapon (Shaman)
    318038,  -- Flametongue Weapon (Shaman)
    33757,   -- Windfury Weapon (Shaman)
    433583,  -- Rite of Adjuration (Paladin Lightsmith)
    433568,  -- Rite of Sanctification (Paladin Lightsmith)
}

-------------------------------------------------------------------------------
--  SPELL DATA Consumables (OOC only, not during keystones)
-------------------------------------------------------------------------------
-- Rogue Poisons: table drives options UI, detection uses the unified scan below; lethal/non-lethal categories match WoW's internal classification.
local ROGUE_POISONS = {
    -- Lethal poisons (mutually exclusive per slot): Deadly first (core Assa), then talented, then other base.
    { key="deadly",     name="Deadly Poison",     castSpell=2823,   cat="lethal" },
    { key="amplifying", name="Amplifying Poison", castSpell=381664, cat="lethal" },
    { key="instant",    name="Instant Poison",    castSpell=315584, cat="lethal" },
    { key="wound",      name="Wound Poison",      castSpell=8679,   cat="lethal" },
    -- Non-lethal poisons (mutually exclusive per slot).
    { key="numbing",    name="Numbing Poison",    castSpell=5761,   cat="nonlethal" },
    { key="atrophic",   name="Atrophic Poison",   castSpell=381637, cat="nonlethal" },
    { key="crippling",  name="Crippling Poison",  castSpell=3408,   cat="nonlethal" },
}
-- Dragon-Tempered Blades (381801): allows 2 of each poison category
local DTB_SPELL_ID = 381801

-- Paladin Rites (non-secret in 12.0)
local PALADIN_RITES = {
    { key="rite_adj",  name="Rite of Adjuration",     castSpell=433583, buffIDs={433583}, wepEnchID={7144} },
    { key="rite_sanc", name="Rite of Sanctification",  castSpell=433568, buffIDs={433568}, wepEnchID={7143} },
}



-- Shaman Imbues (non-secret in 12.0)
local SHAMAN_IMBUES = {
    { key="flametongue", name="Flametongue Weapon", castSpell=318038, buffIDs={319778}, wepEnchID={5400} },
    { key="windfury",    name="Windfury Weapon",    castSpell=33757,  buffIDs={319773},  wepEnchID={5401} },
    { key="earthliving", name="Earthliving Weapon", castSpell=382021, buffIDs={382021, 382022}, wepEnchID={6498} },
    { key="tidecaller",  name="Tidecaller's Guard", castSpell=457481, buffIDs={457496, 457481}, wepEnchID={7528}, requireShield=true },
    { key="tstrike",     name="Thunderstrike Ward", castSpell=462757, buffIDs={462757, 462742}, wepEnchID={7587}, requireShield=true },
}

-- Shaman Shields: 3 entries gated on Elemental Orbit (383010). With Orbit: Earth Shield self-buff (383648) + Lightning/Water Shield both required; without, any of the three. Cast spell by spec: Resto (264) -> Water Shield (52127), else Lightning Shield (192106).
local function ShamanShieldCastSpell()
    local specIdx = GetSpecialization and GetSpecialization() or 0
    local specID = specIdx and specIdx > 0 and GetSpecializationInfo(specIdx) or 0
    return (specID == 264) and 52127 or 192106
end

local SHAMAN_SHIELDS = {
    { key="es_orbit", name="Earth Shield (Self)",
      castSpell=974, buffIDs={383648}, requireTalent=383010,
      check="player" },
    { key="ls_ws_orbit", name="Lightning/Water Shield",
      castSpellFn=ShamanShieldCastSpell, buffIDs={192106, 52127}, requireTalent=383010,
      check="player" },
    { key="shield_basic", name="Shield",
      castSpellFn=ShamanShieldCastSpell, buffIDs={974, 192106, 52127}, excludeTalent=383010,
      check="player" },
}

-- Weapon Enchant Items (temporary weapon enchants applied from items). weaponType: BLADED, BLUNT, RANGED, NEUTRAL (NEUTRAL fits any weapon).
local WEAPON_ENCHANT_ITEMS = {
    -- Midnight
    {itemID=237367, name="Refulgent Weightstone",     weaponType="BLUNT",   icon=7548939},
    {itemID=237369, name="Refulgent Weightstone",     weaponType="BLUNT",   icon=7548939},
    {itemID=237370, name="Refulgent Whetstone",       weaponType="BLADED",  icon=7548942},
    {itemID=237371, name="Refulgent Whetstone",       weaponType="BLADED",  icon=7548942},
    {itemID=257749, name="Laced Zoomshots",           weaponType="RANGED",  icon=249176},
    {itemID=257750, name="Laced Zoomshots",           weaponType="RANGED",  icon=249176},
    {itemID=257751, name="Weighted Boomshots",        weaponType="RANGED",  icon=249175},
    {itemID=257752, name="Weighted Boomshots",        weaponType="RANGED",  icon=249175},
    {itemID=243733, name="Thalassian Phoenix Oil",    weaponType="NEUTRAL", icon=7548987},
    {itemID=243734, name="Thalassian Phoenix Oil",    weaponType="NEUTRAL", icon=7548987},
    {itemID=243735, name="Oil of Dawn",               weaponType="NEUTRAL", icon=7548985},
    {itemID=243736, name="Oil of Dawn",               weaponType="NEUTRAL", icon=7548985},
    {itemID=243737, name="Smuggler's Enchanted Edge", weaponType="NEUTRAL", icon=7548986},
    {itemID=243738, name="Smuggler's Enchanted Edge", weaponType="NEUTRAL", icon=7548986},
    -- TWW
    {itemID=222504, name="Ironclaw Whetstone",     weaponType="BLADED",  icon=3622195},
    {itemID=222503, name="Ironclaw Whetstone",     weaponType="BLADED",  icon=3622195},
    {itemID=222502, name="Ironclaw Whetstone",     weaponType="BLADED",  icon=3622195},
    {itemID=222510, name="Ironclaw Weightstone",   weaponType="BLUNT",   icon=3622199},
    {itemID=222509, name="Ironclaw Weightstone",   weaponType="BLUNT",   icon=3622199},
    {itemID=222508, name="Ironclaw Weightstone",   weaponType="BLUNT",   icon=3622199},
    {itemID=224107, name="Algari Mana Oil",        weaponType="NEUTRAL", icon=609892},
    {itemID=224106, name="Algari Mana Oil",        weaponType="NEUTRAL", icon=609892},
    {itemID=224105, name="Algari Mana Oil",        weaponType="NEUTRAL", icon=609892},
    {itemID=224113, name="Oil of Deep Toxins",     weaponType="NEUTRAL", icon=609897},
    {itemID=224112, name="Oil of Deep Toxins",     weaponType="NEUTRAL", icon=609897},
    {itemID=224111, name="Oil of Deep Toxins",     weaponType="NEUTRAL", icon=609897},
    {itemID=224110, name="Oil of Beledar's Grace", weaponType="NEUTRAL", icon=609896},
    {itemID=224109, name="Oil of Beledar's Grace", weaponType="NEUTRAL", icon=609896},
    {itemID=224108, name="Oil of Beledar's Grace", weaponType="NEUTRAL", icon=609896},
    {itemID=220156, name="Bubbling Wax",           weaponType="NEUTRAL", icon=133778},
}

-- Flask Items (Midnight) each flask has multiple item IDs across quality ranks + fleeting variants
local FLASK_ITEMS = {
    { key="blood_knights",         buffID=1235110, name="Flask of the Blood Knights",
      items={241324, 241325, 245931, 245930} },
    { key="magisters",             buffID=1235108, name="Flask of the Magisters",
      items={241322, 241323, 245933, 245932} },
    { key="shattered_sun",         buffID=1235111, name="Flask of the Shattered Sun",
      items={241326, 241327, 245929, 245928} },
    { key="thalassian_resistance", buffID=1235057, name="Flask of Thalassian Resistance",
      items={241320, 241321, 245926, 245927} },
    { key="thalassian_horror", buffID=1239355, name="Vicious Thalassian Flask of Honor",
      items={241334} },
}
local FLASK_BUFF_ID_SET = {}
local FLASK_NAME_SET = {}
for _, f in ipairs(FLASK_ITEMS) do
    FLASK_BUFF_ID_SET[f.buffID] = true
    -- Build name set from localized spell names (works in all languages)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(f.buffID)
    local locName = info and info.name
    if locName then FLASK_NAME_SET[locName] = true end
    FLASK_NAME_SET[f.name] = true  -- English fallback
end
-- TWW flask buff IDs (detection only, so we don't false-positive when a player still has a TWW flask active)
for _, id in ipairs({432473, 432021, 431974, 431973, 431972, 431971}) do
    FLASK_BUFF_ID_SET[id] = true
end
-- PvP-morphed Midnight flask buff IDs (Blizzard replaces the PvE buff ID with a separate PvP variant in arenas/battlegrounds)
for _, id in ipairs({1235113, 1235114, 1235115, 1235116}) do
    FLASK_BUFF_ID_SET[id] = true
end

-- Food Items (Midnight)
local FOOD_ITEMS = {
    { key="royal_roast",           itemID=242275, name="Royal Roast" },
    { key="impossibly_royal_roast", itemID=255847, name="Impossibly Royal Roast" },
    { key="flora_frenzy",          itemID=255848, name="Flora Frenzy" },
    { key="champions_bento",       itemID=242274, name="Champion's Bento" },
    { key="warped_wise_wings",     itemID=242285, name="Warped Wise Wings" },
    { key="void_kissed_fish_rolls", itemID=242284, name="Void-Kissed Fish Rolls" },
    { key="sun_seared_lumifin",    itemID=242283, name="Sun-Seared Lumifin" },
    { key="null_and_void_plate",   itemID=242282, name="Null and Void Plate" },
    { key="glitter_skewers",       itemID=242281, name="Glitter Skewers" },
    { key="fel_kissed_filet",      itemID=242286, name="Fel-Kissed Filet" },
    { key="buttered_root_crab",    itemID=242280, name="Buttered Root Crab" },
    { key="arcano_cutlets",        itemID=242287, name="Arcano Cutlets" },
    { key="tasty_smoked_tetra",    itemID=242278, name="Tasty Smoked Tetra" },
    { key="crimson_calamari",      itemID=242277, name="Crimson Calamari" },
    { key="braised_blood_hunter",  itemID=242276, name="Braised Blood Hunter" },
    { key="harandar_celebration",  itemID=255846, name="Harandar Celebration" },
    { key="silvermoon_parade",     itemID=255845, name="Silvermoon Parade" },
    { key="queldorei_medley",      itemID=242272, name="Quel'dorei Medley" },
    { key="blooming_feast",        itemID=242273, name="Blooming Feast" },
    { key="sunwell_delight",       itemID=242293, name="Sunwell Delight" },
    { key="hearthflame_supper",    itemID=242295, name="Hearthflame Supper" },
    { key="fried_bloomtail",       itemID=242291, name="Fried Bloomtail" },
    { key="felberry_figs",         itemID=242294, name="Felberry Figs" },
    { key="eversong_pudding",      itemID=242292, name="Eversong Pudding" },
    { key="bloodthistle_wrapped_cutlets", itemID=242296, name="Bloodthistle-wrapped Cutlets" },
    { key="wise_tails",            itemID=242290, name="Wise Tails" },
    { key="twilight_anglers_medley", itemID=242288, name="Twilight Angler's Medley" },
    { key="spellfire_filet",       itemID=242289, name="Spellfire Filet" },
    { key="spiced_biscuits",       itemID=242304, name="Spiced Biscuits" },
    { key="silvermoon_standard",   itemID=242305, name="Silvermoon Standard" },
    { key="quick_sandwich",        itemID=242307, name="Quick Sandwich" },
    { key="portable_snack",        itemID=242308, name="Portable Snack" },
    { key="mana_infused_stew",     itemID=242303, name="Mana-Infused Stew" },
    { key="foragers_medley",       itemID=242306, name="Forager's Medley" },
    { key="farstrider_rations",    itemID=242309, name="Farstrider Rations" },
    { key="bloom_skewers",         itemID=242302, name="Bloom Skewers" },
    -- Hearty Food Items
    { key="hearty_royal_roast",            itemID=242747, name="Hearty Royal Roast" },
    { key="hearty_impossibly_royal_roast",  itemID=268679, name="Hearty Impossibly Royal Roast" },
    { key="hearty_flora_frenzy",            itemID=268680, name="Hearty Flora Frenzy" },
    { key="hearty_champions_bento",         itemID=242746, name="Hearty Champion's Bento" },
    { key="hearty_warped_wise_wings",       itemID=242757, name="Hearty Warped Wise Wings" },
    { key="hearty_void_kissed_fish_rolls",  itemID=242756, name="Hearty Void-Kissed Fish Rolls" },
    { key="hearty_sun_seared_lumifin",      itemID=242755, name="Hearty Sun-Seared Lumifin" },
    { key="hearty_null_and_void_plate",     itemID=242754, name="Hearty Null and Void Plate" },
    { key="hearty_glitter_skewers",         itemID=242753, name="Hearty Glitter Skewers" },
    { key="hearty_fel_kissed_filet",        itemID=242758, name="Hearty Fel-Kissed Filet" },
    { key="hearty_buttered_root_crab",      itemID=242752, name="Hearty Buttered Root Crab" },
    { key="hearty_arcano_cutlets",          itemID=242759, name="Hearty Arcano Cutlets" },
    { key="hearty_tasty_smoked_tetra",      itemID=242750, name="Hearty Tasty Smoked Tetra" },
    { key="hearty_crimson_calamari",        itemID=242749, name="Hearty Crimson Calamari" },
    { key="hearty_braised_blood_hunter",    itemID=242748, name="Hearty Braised Blood Hunter" },
    { key="hearty_harandar_celebration",    itemID=266996, name="Hearty Harandar Celebration" },
    { key="hearty_silvermoon_parade",       itemID=266985, name="Hearty Silvermoon Parade" },
    { key="hearty_queldorei_medley",        itemID=242744, name="Hearty Quel'dorei Medley" },
    { key="hearty_blooming_feast",          itemID=242745, name="Hearty Blooming Feast" },
    { key="hearty_sunwell_delight",         itemID=242765, name="Hearty Sunwell Delight" },
    { key="hearty_hearthflame_supper",      itemID=242767, name="Hearty Hearthflame Supper" },
    { key="hearty_fried_bloomtail",         itemID=242763, name="Hearty Fried Bloomtail" },
    { key="hearty_felberry_figs",           itemID=242766, name="Hearty Felberry Figs" },
    { key="hearty_eversong_pudding",        itemID=242764, name="Hearty Eversong Pudding" },
    { key="hearty_bloodthistle_wrapped_cutlets", itemID=242768, name="Hearty Bloodthistle-Wrapped Cutlets" },
    { key="hearty_wise_tails",              itemID=242762, name="Hearty Wise Tails" },
    { key="hearty_twilight_anglers_medley", itemID=242760, name="Hearty Twilight Angler's Medley" },
    { key="hearty_spellfire_filet",         itemID=242761, name="Hearty Spellfire Filet" },
    { key="hearty_spiced_biscuits",         itemID=242771, name="Hearty Spiced Biscuits" },
    { key="hearty_silvermoon_standard",     itemID=242772, name="Hearty Silvermoon Standard" },
    { key="hearty_quick_sandwich",          itemID=242774, name="Hearty Quick Sandwich" },
    { key="hearty_portable_snack",          itemID=242775, name="Hearty Portable Snack" },
    { key="hearty_mana_infused_stew",       itemID=242770, name="Hearty Mana-Infused Stew" },
    { key="hearty_foragers_medley",         itemID=242773, name="Hearty Forager's Medley" },
    { key="hearty_farstrider_rations",      itemID=242776, name="Hearty Farstrider Rations" },
    { key="hearty_bloom_skewers",           itemID=242769, name="Hearty Bloom Skewers" },
}

-- Weapon Enchant dropdown choices (name best itemID lookup at runtime)
local WEAPON_ENCHANT_CHOICES = {
    { key="thalassian_phoenix_oil",  name="Thalassian Phoenix Oil" },
    { key="smugglers_enchanted_edge", name="Smuggler's Enchanted Edge" },
    { key="oil_of_dawn",             name="Oil of Dawn" },
    { key="refulgent_weightstone",   name="Refulgent Weightstone" },
    { key="refulgent_whetstone",     name="Refulgent Whetstone" },
    { key="laced_zoomshots",         name="Laced Zoomshots" },
    { key="weighted_boomshots",      name="Weighted Boomshots" },
}

-- Augment Runes (item IDs inlined at usage site in CollectConsumables)
local RUNE_BUFF_IDS = {1264426, 453250, 1234969, 1242347, 393438, 347901}

-- Inky Black Potion
local INKY_BLACK_ITEM = 124640
local INKY_BLACK_BUFF = 185394  -- "Inky Blackness" buff (icon 136122); detected by aura scan, see PlayerHasInkyBlackness

-------------------------------------------------------------------------------
--  Helpers: Well Fed / Flask buff detection (by name, not spell ID secret)
-------------------------------------------------------------------------------
-- Consumable aura presence is unverifiable in combat / active M+ (suppress,
-- never false-remind) and anywhere the 12.1 aura restriction is engaged --
-- AurasRestricted() is the authoritative probe (asymmetric per-frame cache;
-- index scans HARD-ERROR under restriction, even out of combat in raids).
-- Weapon enchants and raid buffs use other APIs and are not gated here.
function EABR.ConsumablePresenceUnverifiable()
    if InCombat() or InMythicPlusKey() then return true end
    return EllesmereUI.AuraKit and EllesmereUI.AuraKit.AurasRestricted() or false
end

-------------------------------------------------------------------------------
--  Eating-state tracker: the eating channel shares one aura icon (133950)
--  across all food. Tracked by auraInstanceID from the player UNIT_AURA
--  payload; the full scan runs only at enable/zone edges. Under restriction
--  the payload and index scans are secret/blocked -- the tracker simply
--  reports "not eating" there (the food reminder is suppressed anyway).
-------------------------------------------------------------------------------
function EABR.IsPlayerEating()
    return EABR._eatingIID ~= nil
end

function EABR.ScanEatingState()
    EABR._eatingIID = nil
    if EllesmereUI.AuraKit and EllesmereUI.AuraKit.AurasRestricted() then return end
    for i = 1, AURA_SCAN_LIMIT do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not aura then break end
        local ic = aura.icon
        if ic and not isSecret(ic) and ic == 133950 then
            local iid = aura.auraInstanceID
            if iid ~= nil and not isSecret(iid) then EABR._eatingIID = iid end
            return
        end
    end
end

function EABR.UpdateEatingState(updateInfo)
    -- 12.1: the whole payload and each list can be secret in restricted
    -- content; indexing a secret errors, so every layer is gated.
    if updateInfo == nil or isSecret(updateInfo) then return end
    local added = updateInfo.addedAuras
    if added ~= nil and not isSecret(added) then
        for _, aura in ipairs(added) do
            if aura ~= nil and not isSecret(aura) then
                local ic = aura.icon
                if ic and not isSecret(ic) and ic == 133950 then
                    local iid = aura.auraInstanceID
                    if iid ~= nil and not isSecret(iid) then
                        EABR._eatingIID = iid
                        break
                    end
                end
            end
        end
    end
    local removed = updateInfo.removedAuraInstanceIDs
    if removed ~= nil and not isSecret(removed) and EABR._eatingIID then
        for _, id in ipairs(removed) do
            if id ~= nil and not isSecret(id) and id == EABR._eatingIID then
                EABR._eatingIID = nil
                break
            end
        end
    end
end

function EABR.GetEatingExpirationTime()
    if not EABR._eatingIID then return nil end
    local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", EABR._eatingIID)
    if not ok or not auraData then return nil end
    local exp = auraData.expirationTime
    if exp == nil or isSecret(exp) or exp == 0 then return nil end
    return exp
end

local function PlayerHasBuffByName(buffName)
    -- Cannot verify -> treat as present so the reminder never false-fires.
    if EABR.ConsumablePresenceUnverifiable() then return true end
    if _AC.valid then
        _AC.ensureNames()
        return _AC.byName[buffName] or false
    end
    local sawReadableName = false
    for i = 1, AURA_SCAN_LIMIT do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then return true end -- can't verify absence
        if not aura then break end
        local aName = aura.name
        if aName and not isSecret(aName) then
            sawReadableName = true
            if aName == buffName then return true end
        end
    end
    if not sawReadableName then return true end -- names secret / empty: suppress
    return false
end

local function PlayerHasWellFed()
    if InPvPInstance() then return true end  -- food not trackable in PvP, suppress
    if EABR.ConsumablePresenceUnverifiable() then return true end
    -- Well Fed has no whitelisted spell ID (icon scan). If icons aren't
    -- readable, suppress rather than false-fire "missing".
    local sawReadableIcon = false
    for i = 1, AURA_SCAN_LIMIT do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then return true end -- can't verify absence
        if not aura then break end
        local ic = aura.icon
        if ic and not isSecret(ic) then
            sawReadableIcon = true
            if ic == 136000 then
                local dur, exp = aura.duration, aura.expirationTime
                if dur ~= nil and exp ~= nil and not isSecret(dur) and not isSecret(exp)
                   and IsUnderDuration(dur, exp, "consumable") then
                    return false
                end
                return true
            end
        end
    end
    if not sawReadableIcon then return true end -- icons secret: suppress
    return false
end

local function PlayerHasFlaskBuff()
    if InPvPInstance() then return true end
    if EABR.ConsumablePresenceUnverifiable() then return true end
    -- Direct ID lookup for known flask buff IDs (zero allocation)
    for id in pairs(FLASK_BUFF_ID_SET) do
        local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if ok and result ~= nil then
            local dur, exp = result.duration, result.expirationTime
            if dur ~= nil and exp ~= nil and not isSecret(dur) and not isSecret(exp)
               and IsUnderDuration(dur, exp, "consumable") then
                return false
            end
            return true
        end
    end
    -- Name-based fallback for flasks not in our ID set (lazy scan)
    if _AC.valid then
        _AC.ensureNames()
        for aName in pairs(_AC.byName) do
            if FLASK_NAME_SET[aName] then return true end
        end
    end
    return false
end

local function PlayerHasInkyBlackness()
    if InPvPInstance() then return true end
    if EABR.ConsumablePresenceUnverifiable() then return true end
    local sawReadable = false
    for i = 1, AURA_SCAN_LIMIT do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then return true end -- can't verify absence
        if not aura then break end
        local sid = aura.spellId
        local ic = aura.icon
        if (sid and not isSecret(sid)) or (ic and not isSecret(ic)) then
            sawReadable = true
        end
        if (sid and not isSecret(sid) and sid == INKY_BLACK_BUFF)
        or (ic and not isSecret(ic) and ic == 136122) then
            local dur, exp = aura.duration, aura.expirationTime
            if dur ~= nil and exp ~= nil and not isSecret(dur) and not isSecret(exp)
               and IsUnderDuration(dur, exp, "consumable") then
                return false
            end
            return true
        end
    end
    if not sawReadable then return true end -- fields secret: suppress
    return false
end

-------------------------------------------------------------------------------
--  Item count snapshot: GetItemCount is a per-item bag scan (~135-item consumable resolve was ~7ms cold).
--  Walks bags 0-4 ONCE into {itemID->count} (rebuilt only on bag change, consumables never in the reagent bag) so CachedGetItemCount is a hash lookup; DetectUsedItem shares it -- one bag walk per change, not two.
-------------------------------------------------------------------------------
local _bagCounts = {}
local _itemCountDirty = true

-- Resolved consumable cache: WHICH item to show per bag/equip-derived category, rebuilt only when bags/weapon/
-- preferred-item settings change (EABR.ResolveConsumables). Hung on EABR, not a local (200-local cap). Caches only
-- SELECTION state (itemID/cat/hasBags/availability); icon is derived at each emit site to stay byte-identical to per-refresh GetItemIcon calls. Defaults nil/false; dirty starts true so the first OOC CollectConsumables fully populates it.
EABR._resolved = {
    dirty = true,                   -- rebuild pending
    sig = {},                       -- last preferred-setting signature
    rune = {},                      -- {itemID, hasBags}
    flask = {},                     -- {itemID, hasBags}
    food = {},                      -- {itemID}
    inky = {},                      -- {hasPotion}
    healthstone = {},               -- {hasStone}
    we = { [16] = {}, [17] = {} },  -- per-slot {cat, itemID, hasBags}
}

local function InvalidateItemCountCache()
    _itemCountDirty = true
    EABR._resolved.dirty = true
end

local function RebuildBagCounts()
    wipe(_bagCounts)
    _itemCountDirty = false
    for bag = 0, 4 do
        local numSlots = C_Container and C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container and C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                _bagCounts[info.itemID] = (_bagCounts[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
end

local function CachedGetItemCount(itemID)
    if _itemCountDirty then RebuildBagCounts() end
    return _bagCounts[itemID] or 0
end

-------------------------------------------------------------------------------
--  Helpers: Find best item in bags for a preferred choice
-------------------------------------------------------------------------------
local function FindFlaskItem(preferredKey, lastUsedItemID)
    if preferredKey == "last_used" then
        if lastUsedItemID and CachedGetItemCount(lastUsedItemID) > 0 then
            return lastUsedItemID
        end
        -- Fallback: first flask found in bags
        for _, f in ipairs(FLASK_ITEMS) do
            for _, id in ipairs(f.items) do
                if CachedGetItemCount(id) > 0 then return id end
            end
        end
        return nil
    end
    for _, f in ipairs(FLASK_ITEMS) do
        if f.key == preferredKey then
            for _, id in ipairs(f.items) do
                if CachedGetItemCount(id) > 0 then return id end
            end
        end
    end
    return nil
end

local function FindFoodItem(preferredKey, lastUsedItemID)
    if preferredKey ~= "last_used" then
        for _, f in ipairs(FOOD_ITEMS) do
            if f.key == preferredKey and CachedGetItemCount(f.itemID) > 0 then return f.itemID end
        end
        -- Preferred food out of stock: try the base variant of the same food
        -- (e.g. "hearty_royal_roast" -> "royal_roast") before giving up on it.
        local baseKey = preferredKey:gsub("^hearty_", "")
        if baseKey ~= preferredKey then
            for _, f in ipairs(FOOD_ITEMS) do
                if f.key == baseKey and CachedGetItemCount(f.itemID) > 0 then return f.itemID end
            end
        end
    elseif lastUsedItemID and CachedGetItemCount(lastUsedItemID) > 0 then
        return lastUsedItemID
    end
    -- Fall back to the highest-quality food still in bags so the reminder
    -- stays clickable when the preferred/last food is gone but something
    -- edible remains. Runs only inside the resolve-on-change cache rebuild.
    local bestID, bestQ = nil, -1
    for _, f in ipairs(FOOD_ITEMS) do
        if CachedGetItemCount(f.itemID) > 0 then
            local q = 0
            if C_TradeSkillUI and C_TradeSkillUI.GetItemCraftedQualityByItemInfo then
                local ok, tier = pcall(C_TradeSkillUI.GetItemCraftedQualityByItemInfo, f.itemID)
                if ok and tier then q = tier end
            end
            if q > bestQ then bestID = f.itemID; bestQ = q end
        end
    end
    return bestID
end

local function FindWeaponEnchantItem(preferredKey, lastUsedItemID, targetCat)
    if preferredKey == "last_used" then
        if lastUsedItemID and CachedGetItemCount(lastUsedItemID) > 0 then
            return lastUsedItemID
        end
        -- Fallback: first matching weapon enchant in bags
        for _, we in ipairs(WEAPON_ENCHANT_ITEMS) do
            local wt = we.weaponType
            if ((wt == "NEUTRAL") or (wt == targetCat)) and CachedGetItemCount(we.itemID) > 0 then
                return we.itemID
            end
        end
        return nil
    end
    -- Find by name match (picks highest tier in bags)
    for _, choice in ipairs(WEAPON_ENCHANT_CHOICES) do
        if choice.key == preferredKey then
            for _, we in ipairs(WEAPON_ENCHANT_ITEMS) do
                if we.name == choice.name and CachedGetItemCount(we.itemID) > 0 then
                    return we.itemID
                end
            end
            break
        end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Resolves bag/equip-derived consumable display items -- the costly part of the consumable check (Find*Item walks
--  + GetWeaponCategory). Depends only on bags, equipped weapon, and preferred-item settings (+ lastUsed*); rebuilt
--  lazily on change, CollectConsumables reads resolved records each refresh and derives the icon at emit. NOTE: any FUTURE resolution input must also set _resolved.dirty (or join the signature below), or a stale item could show.
-------------------------------------------------------------------------------
function EABR.ResolveConsumables()
    if not db then return end
    local co = db.profile and db.profile.consumables
    if not co then return end

    local R = EABR._resolved
    local pf  = co.preferredFlask or "last_used"
    local pfd = co.preferredFood or "last_used"
    local pwe = co.preferredWeaponEnchant or "last_used"
    -- Lazy gate: rebuild only when dirty (bag/equip event) or a preferred-item setting changed -- options setters only RequestRefresh with no bag event, so a signature compare catches it here.
    local sig = R.sig
    if not R.dirty and sig.pf == pf and sig.pfd == pfd and sig.pwe == pwe then
        return
    end
    R.dirty = false
    sig.pf, sig.pfd, sig.pwe = pf, pfd, pwe

    local luf  = db.profile and db.profile.lastUsedFlask or nil
    local lufd = db.profile and db.profile.lastUsedFood or nil
    local luwe = db.profile and db.profile.lastUsedWeaponEnchant or nil

    -- Augment Rune: void preferred over ethereal; fall back to the current
    -- rune so an out-of-stock restock reminder can still render.
    local runeItem = nil
    if CachedGetItemCount(259085) > 0 then runeItem = 259085
    elseif CachedGetItemCount(243191) > 0 then runeItem = 243191 end
    R.rune.hasBags = (runeItem ~= nil)
    R.rune.itemID = runeItem or 259085

    -- Flask: resolve a display item even when out of stock (shown desaturated).
    local flaskItemID = FindFlaskItem(pf, luf)
    R.flask.hasBags = (flaskItemID ~= nil)
    if not flaskItemID then
        if pf == "last_used" then
            flaskItemID = luf
        else
            for _, f in ipairs(FLASK_ITEMS) do
                if f.key == pf then flaskItemID = f.items[1]; break end
            end
        end
        if not flaskItemID and FLASK_ITEMS[1] then
            flaskItemID = FLASK_ITEMS[1].items[1]
        end
    end
    R.flask.itemID = flaskItemID

    -- Food: resolve a display item even when out of stock (shown desaturated).
    local foodItemID = FindFoodItem(pfd, lufd)
    R.food.hasBags = (foodItemID ~= nil)
    if not foodItemID then
        if pfd == "last_used" then
            foodItemID = lufd
        else
            for _, f in ipairs(FOOD_ITEMS) do
                if f.key == pfd then foodItemID = f.itemID; break end
            end
        end
        if not foodItemID and FOOD_ITEMS[1] then
            foodItemID = FOOD_ITEMS[1].itemID
        end
    end
    R.food.itemID = foodItemID
    -- Amber-count flag when the shown food is a backup because the
    -- preferred/last pick ran out (but some other food is still owned).
    R.food.isSubstitute = false
    if foodItemID and R.food.hasBags then
        local foodKey
        for _, f in ipairs(FOOD_ITEMS) do
            if f.itemID == foodItemID then foodKey = f.key; break end
        end
        if pfd ~= "last_used" then
            R.food.isSubstitute = (foodKey ~= pfd)
        elseif lufd and foodItemID ~= lufd then
            R.food.isSubstitute = true
        end
    end

    -- Weapon enchant per slot: cat (equipped weapon type) gates the reminder in CollectConsumables and selects the item; resolves even out of stock (desaturated), same fallback order as inline code.
    for _, slot in ipairs({16, 17}) do
        local r = R.we[slot]
        local cat = GetWeaponCategory(slot)
        r.cat = cat
        local bestItemID = FindWeaponEnchantItem(pwe, luwe, cat)
        r.hasBags = (bestItemID ~= nil)
        if not bestItemID then
            if pwe == "last_used" then
                bestItemID = luwe
            else
                for _, choice in ipairs(WEAPON_ENCHANT_CHOICES) do
                    if choice.key == pwe then
                        for _, we in ipairs(WEAPON_ENCHANT_ITEMS) do
                            if we.name == choice.name then bestItemID = we.itemID; break end
                        end
                        break
                    end
                end
            end
            if not bestItemID then
                for _, we in ipairs(WEAPON_ENCHANT_ITEMS) do
                    if we.weaponType == "NEUTRAL" or we.weaponType == cat then
                        bestItemID = we.itemID; break
                    end
                end
            end
        end
        r.itemID = bestItemID
    end

    -- Inky Black Potion: constant item; only availability is bag-derived.
    R.inky.hasPotion = CachedGetItemCount(INKY_BLACK_ITEM) > 0

    -- Healthstone: constant texture; only availability is bag-derived.
    local hasStone = false
    for _, itemID in ipairs(HEALTHSTONE_ITEM_IDS) do
        if CachedGetItemCount(itemID) > 0 then hasStone = true; break end
    end
    R.healthstone.hasStone = hasStone
end

-------------------------------------------------------------------------------
--  Glow Types (shared with options)
-------------------------------------------------------------------------------
local GLOW_TYPES = {
    { name = "Action Button Glow",   buttonGlow = true },
    { name = "Pixel Glow",           procedural = true },
    { name = "Auto-Cast Shine",      autocast = true },
    { name = "GCD",                  atlas = "RotationHelper_Ants_Flipbook",  texPadding = 1.6 },
    { name = "Modern WoW Glow",      atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook",  texPadding = 1.4 },
    { name = "Classic WoW Glow",     texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
      rows = 5, columns = 5, frames = 25, duration = 0.3, frameW = 48, frameH = 48, texPadding = 1.25 },
}

local GLOW_VALUES = { [0] = "None" }
local GLOW_ORDER  = { 0 }
for i, entry in ipairs(GLOW_TYPES) do
    GLOW_VALUES[i] = entry.name
    GLOW_ORDER[#GLOW_ORDER + 1] = i
end

-------------------------------------------------------------------------------
--  Glow Engines provided by shared EllesmereUI_Glows.lua
-------------------------------------------------------------------------------
local StartPixelGlow, StopPixelGlow, StartButtonGlow, StopButtonGlow
local StartAutoCastShine, StopAutoCastShine, StartFlipBookGlow, StopFlipBookGlow, StopAllGlows
do
    local G = EllesmereUI.Glows
    StartPixelGlow = function(wrapper, sz, cr, cg, cb)
        local N, th, period = 8, 2, 4
        local lineLen = floor((sz+sz)*(2/N-0.1)); lineLen = min(lineLen, sz); if lineLen < 1 then lineLen = 1 end
        G.StartProceduralAnts(wrapper, N, th, period, lineLen, cr, cg, cb, sz)
    end
    StopPixelGlow = function(wrapper) G.StopProceduralAnts(wrapper) end
    StartButtonGlow = function(wrapper, sz, cr, cg, cb, scale) G.StartButtonGlow(wrapper, sz, cr, cg, cb, scale) end
    StopButtonGlow = function(wrapper) G.StopButtonGlow(wrapper) end
    StartAutoCastShine = function(wrapper, sz, cr, cg, cb, scale) G.StartAutoCastShine(wrapper, sz, cr, cg, cb, scale) end
    StopAutoCastShine = function(wrapper) G.StopAutoCastShine(wrapper) end
    StartFlipBookGlow = function(wrapper, sz, entry, cr, cg, cb) G.StartFlipBookGlow(wrapper, sz, entry, cr, cg, cb) end
    StopFlipBookGlow = function(wrapper) G.StopFlipBookGlow(wrapper) end
    StopAllGlows = function(wrapper) G.StopAllGlows(wrapper) end
end


-------------------------------------------------------------------------------
--  Defaults
-------------------------------------------------------------------------------
local defaults = {
    profile = {
        display = {
            remindersEnabled = true,
            glowType = 0,
            scale = 1.0,
            xOffset = 0,
            yOffset = 200,
            showText = true,
            showTooltips = true,
            textColor = {r=1, g=1, b=1},
            textSize = 12,
            textFont = "Expressway",
            textXOffset = 0,
            textYOffset = -5,
            textAnchor = "BOTTOM",
            showCount = true,
            countSize = 16,
            countXOffset = 0,
            countYOffset = 0,
            iconSpacing = 14,
            opacity = 1.0,
            frameStrata = "MEDIUM",
            cursorAttach = false,
            -- Global timing pair (minutes). showUnderMPlus is the pre-key
            -- (Mythic 0 / keystone lobby) threshold; active keys and combat
            -- ignore thresholds entirely (only fully-missing reminds there).
            showUnder = 5,
            showUnderMPlus = 40,
        },
        raidBuffs = {
            enabled = {
                motw=true, bshout=true, fort=true, ai=true, bronze=true, sky=true, hmark=true,
            },
            -- Per-section "Where to Show". Stores only unchecked buckets
            -- (value false); an absent bucket = shown. Open world defaults
            -- off for raid buffs. Buckets: open_world, raid_mythic,
            -- raid_heroic, raid_normal_lfr, dungeon_mythic,
            -- dungeon_nonmythic, timewalking, delve, in_combat.
            whereToShow = { open_world = false },
            -- Show When: othersMissing = remind when a groupmate lacks a
            -- buff I provide; iAmMissing = remind when I lack a buff a
            -- groupmate could give me (receiver view, off by default).
            showWhen = { othersMissing = true, iAmMissing = false },
            -- One reminder sound for the whole section (nil = silent),
            -- played once when a reminder newly appears.
        },
        auras = {
            enabled = {
                symbiotic=true, battle_stance=true, def_stance=true, berserk_stance=true, shadowform=true,
                devo_aura=true, bol=true, bof=true, som=true, blistering_scales=true,
                bestow_weyrnstone=true, timelessness=true,
            },
            -- All buckets (including open world) on by default.
            whereToShow = {},
        },
        consumables = {
            -- When false, bag/equip-derived consumables (rune/flask/food/weapon)
            -- are hidden entirely when the item isn't in bags, instead of
            -- showing a desaturated restock prompt.
            showWithoutItem = true,
            enabled = {
                deadly=true, instant=true, wound=true, amplifying=true,
                crippling=true, numbing=true, atrophic=true,
                rite_adj=true, rite_sanc=true,
                flametongue=true, windfury=true, earthliving=true, tidecaller=true, tstrike=true,
                ls=true, ws=true, es=true,
                augment_rune=true,
                weapon_enchant=true,
                inky_black=true,
                flask=true,
                food=true,
            },
            -- Bag/equip consumables (open world off) and a separate shared
            -- set for the class specials (open world on).
            whereToShow = { open_world = false },
            specialsWhereToShow = {},
            preferredFlask = "last_used",
            preferredFood = "last_used",
            preferredWeaponEnchant = "last_used",
            inkyBlackZones = "",
        },
        unlockPos = nil,
        talentReminders = {},  -- array of {zoneIDs={}, zoneNames={}, spellID=number, spellName=string, showNotNeeded=bool}
        talentReminderYOffset = -50,
    },
}

local euiPanelOpen = false

-------------------------------------------------------------------------------
--  Middle-click dismiss hide a reminder until the next loading screen
-------------------------------------------------------------------------------
local _dismissedUntilLoad = {}  -- [dismissKey] = true

-------------------------------------------------------------------------------
--  Per-section appear-sounds: one sound key per section (raid buffs / auras /
--  consumables / class specials), played once as a reminder NEWLY appears.
--  Two swapped sets avoid per-refresh allocation; the first primed pass is
--  skipped so login never replays a burst. Hung on EABR (200-local cap).
-------------------------------------------------------------------------------
-- Class-special keys (poisons/rites/imbues/shields) share one sound; built once.
function EABR.IsSpecialKey(key)
    local set = EABR._specialKeySet
    if not set then
        set = {}
        for _, tbl in ipairs({ _G._EABR_ROGUE_POISONS, _G._EABR_PALADIN_RITES,
                               _G._EABR_SHAMAN_IMBUES, _G._EABR_SHAMAN_SHIELDS }) do
            if type(tbl) == "table" then
                for _, it in ipairs(tbl) do if it.key then set[it.key] = true end end
            end
        end
        EABR._specialKeySet = set
    end
    return set[key]
end

-- Resolves the configured sound key for a reminder from its dismissKey.
function EABR.ResolveReminderSound(dk)
    local prefix, key = dk:match("^(%a+):(.+)$")
    if not prefix then return nil end
    local p = db.profile
    if prefix == "raidbuff" then
        return p.raidBuffs.sectionSound
    elseif prefix == "aura" then
        return p.auras.sectionSound
    elseif prefix == "consumable" then
        local co = p.consumables
        if EABR.IsSpecialKey(key) then return co.specialsSound end
        return co.sectionSound
    end
    return nil
end

function EABR.HandleAppearSounds(missing)
    local prev = EABR._soundPrev or {}
    local cur = EABR._soundCur or {}
    wipe(cur)
    local primed = EABR._soundPrimed
    for i = 1, #missing do
        local dk = missing[i].dismissKey
        if dk and not _dismissedUntilLoad[dk] then
            cur[dk] = true
            if primed and not prev[dk] then
                local skey = EABR.ResolveReminderSound(dk)
                if skey and skey ~= "none" then
                    local paths = EllesmereUI._groupDeathSoundPaths
                    local path = paths and paths[skey]
                    if path then PlaySoundFile(path, "Master") end
                end
            end
        end
    end
    EABR._soundPrev, EABR._soundCur, EABR._soundPrimed = cur, prev, true
end

-------------------------------------------------------------------------------
--  Icon Pool SecureActionButton based for click-to-cast
-------------------------------------------------------------------------------
local ICON_SIZE = 40
local iconAnchor
local iconPool = {}     -- all created icon buttons
local activeIcons = {}  -- currently visible icons

-- Talent icon state moved to EllesmereUIABR_TalentReminders.lua

-------------------------------------------------------------------------------
--  Combat Icon Pool -- non-secure frames for visual-only display during combat.
-------------------------------------------------------------------------------
local combatAnchor      -- created in OnEnable, follows iconAnchor position
local combatIconPool = {}
local combatActiveIcons = {}

-------------------------------------------------------------------------------
--  Cursor-attached combat icons -- shown at cursor when cursorAttach is enabled.
-------------------------------------------------------------------------------
local CURSOR_IMPORTANT = {
    -- PROVIDER raid buffs are important (cat == "raidbuff" + mode "spell" --
    -- see IsImportantBuff): a buff YOU can cast that the group is missing.
    -- Receiver-view reminders (a groupmate's buff the player lacks) never
    -- ride the cursor -- nothing there is actionable by the player's own
    -- hands. Beacon tracking uses its own independent system (_B); beacons
    -- are the player's own casts, so their cursor treatment already fits.
}
local cursorAnchor
local cursorIconPool = {}
local cursorActiveIcons = {}

local function GetStrata()
    return db and db.profile.display.frameStrata or "MEDIUM"
end

function EABR.GetIconTextOverlay(f)
    if f._textOverlay then return f._textOverlay end
    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(f:GetFrameLevel() + 5)
    f._textOverlay = overlay
    return overlay
end

local function GetOrCreateCombatIcon(index)
    if combatIconPool[index] then return combatIconPool[index] end
    local f = CreateFrame("Frame", "EABR_CombatIcon"..index, combatAnchor)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:SetFrameStrata(GetStrata())
    f:SetFrameLevel(120)
    f:Hide()
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f._icon = icon
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then PP.CreateBorder(f, 0, 0, 0, 1, 1, "OVERLAY", 7) end
    local text = EABR.GetIconTextOverlay(f):CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    SetABRFont(text, ResolveFontPath(), 11)
    text:SetTextColor(1, 1, 1, 1)
    f._text = text
    EABR.CreateIconCountOverlay(f)
    EABR.CreateIconQualityOverlay(f)
    EABR.CreateIconBagCountOverlay(f)
    EABR.AttachIconHover(f)
    EABR.AttachIconTooltip(f)
    EABR.AttachCombatClickHint(f)
    combatIconPool[index] = f
    return f
end

local function HideCombatIcons()
    for i = 1, #combatActiveIcons do
        local f = combatActiveIcons[i]
        if f then
            EABR.ClearEatingVisual(f)
            if f._eabrGlowWrapper then f._eabrGlowWrapper:Hide() end
            f._text:SetText(""); f:Hide()
        end
    end
    wipe(combatActiveIcons)
    if EABR.SetProviderCastCombatVisible then
        EABR.SetProviderCastCombatVisible(false)
    end
    if combatAnchor then EllesmereUI.SetElementVisibility(combatAnchor, false) end
end

local function ShowCombatIcon(iconIdx, m)
    local f = GetOrCreateCombatIcon(iconIdx)
    local spellID = m.spellID or (m.data and m.data.castSpell)
    f._icon:SetTexture(m.texture or (spellID and Tex(spellID)) or 134400)
    local p = db and db.profile.display
    if p and p.showText and not m.isEating then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        local fontPath = ResolveFontPath(p.textFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        SetABRFont(f._text, fontPath, textSize)
        f._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(p)
        f._text:SetPoint(tp, f, ip, xOff, yOff)
        f._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        f._text:SetText(m.label or "")
        f._text:Show()
    else
        f._text:SetText("")
        f._text:Hide()
    end
    EABR.ApplyEatingVisual(f, m)
    EABR.ApplyIconTooltipData(f, m)
    EABR.ApplyIconQuality(f, (not m.isEating) and m.qualityAtlas or nil)
    if m.groupTotal then
        EABR.ApplyIconGroupCoverage(f, m.groupHave, m.groupTotal)
    else
        EABR.ApplyIconBagCount(f, (not m.isEating) and m.bagCount or nil,
            (not m.isEating) and m.desaturated or nil,
            (not m.isEating) and m.substitute or nil)
    end
    f:Show()
    combatActiveIcons[#combatActiveIcons+1] = f
end

-- Left-aligned like the OOC row. Slot 0 is reserved while the provider
-- secure button is shown, and stays reserved after a mid-combat hide until
-- the OOC park -- its SetPoint/EnableMouse are protected under lockdown, so
-- other icons must never slide under it.
local function LayoutCombatIcons()
    local reserveSlot = EABR._providerCastVisible or EABR._providerCastCombatReserved
    local count = #combatActiveIcons
    if count == 0 and not reserveSlot then return end
    local p = db.profile.display
    local spacing = p.iconSpacing or 8
    local baseScale = p.scale or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    local xOff = reserveSlot and (sz + spacing) or 0
    for i, f in ipairs(combatActiveIcons) do
        f:SetSize(sz, sz)
        f:SetAlpha(p.opacity or 1.0)
        EABR.SizeIconQuality(f, sz)
        EABR.SizeIconBagCount(f, sz)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", combatAnchor, "TOPLEFT", xOff + (i-1)*(sz+spacing), 0)
    end
end

-------------------------------------------------------------------------------
--  Cursor Icon Pool: same visual style as combat icons, parented to cursorAnchor (follows the cursor frame).
-------------------------------------------------------------------------------
local function GetOrCreateCursorIcon(index)
    if cursorIconPool[index] then return cursorIconPool[index] end
    local f = CreateFrame("Frame", "EABR_CursorIcon"..index, cursorAnchor)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(9980)
    f:Hide()
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f._icon = icon
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then PP.CreateBorder(f, 0, 0, 0, 1, 1, "OVERLAY", 7) end
    local text = EABR.GetIconTextOverlay(f):CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    SetABRFont(text, ResolveFontPath(), 11)
    text:SetTextColor(1, 1, 1, 1)
    f._text = text
    EABR.CreateIconCountOverlay(f)
    EABR.CreateIconQualityOverlay(f)
    EABR.CreateIconBagCountOverlay(f)
    EABR.AttachIconHover(f)
    EABR.AttachIconTooltip(f)
    EABR.AttachCombatClickHint(f)
    cursorIconPool[index] = f
    return f
end

local function HideCursorIcons()
    for i = 1, #cursorActiveIcons do
        local f = cursorActiveIcons[i]
        if f then
            EABR.ClearEatingVisual(f)
            if f._eabrGlowWrapper then f._eabrGlowWrapper:Hide() end
            f._text:SetText(""); f:Hide()
        end
    end
    wipe(cursorActiveIcons)
    if cursorAnchor then EllesmereUI.SetElementVisibility(cursorAnchor, false) end
end

local function ShowCursorIcon(iconIdx, m)
    local f = GetOrCreateCursorIcon(iconIdx)
    local spellID = m.spellID or (m.data and m.data.castSpell)
    f._icon:SetTexture(m.texture or (spellID and Tex(spellID)) or 134400)
    local p = db and db.profile.display
    if p and p.showText and not m.isEating then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        local fontPath = ResolveFontPath(p.textFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        SetABRFont(f._text, fontPath, textSize)
        f._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(p)
        f._text:SetPoint(tp, f, ip, xOff, yOff)
        f._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        f._text:SetText(m.label or "")
        f._text:Show()
    else
        f._text:SetText("")
        f._text:Hide()
    end
    EABR.ApplyEatingVisual(f, m)
    EABR.ApplyIconTooltipData(f, m)
    EABR.ApplyIconQuality(f, (not m.isEating) and m.qualityAtlas or nil)
    if m.groupTotal then
        EABR.ApplyIconGroupCoverage(f, m.groupHave, m.groupTotal)
    else
        EABR.ApplyIconBagCount(f, (not m.isEating) and m.bagCount or nil,
            (not m.isEating) and m.desaturated or nil,
            (not m.isEating) and m.substitute or nil)
    end
    f:Show()
    cursorActiveIcons[#cursorActiveIcons+1] = f
end

local function LayoutCursorIcons()
    local count = #cursorActiveIcons; if count == 0 then return end
    local p = db.profile.display
    local spacing = p.iconSpacing or 8
    local baseScale = p.scale or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    local totalW = (count * sz) + ((count-1) * spacing)
    local startX = -(totalW/2) + (sz/2)
    for i, f in ipairs(cursorActiveIcons) do
        f:SetSize(sz, sz)
        f:SetAlpha(p.opacity or 1.0)
        EABR.SizeIconQuality(f, sz)
        EABR.SizeIconBagCount(f, sz)
        f:ClearAllPoints()
        f:SetPoint("CENTER", cursorAnchor, "CENTER", startX + (i-1)*(sz+spacing), 0)
    end
end

-------------------------------------------------------------------------------
--  Provider raid-buff cast button: a dedicated SecureActionButton pre-bound
--  OOC to the player's own raid buff, so the rebuff stays clickable through
--  combat (post-combat-res). Spell attributes, size and position are set out
--  of combat ONLY; in combat only alpha and child visuals change. Parented
--  to UIParent so anchor mouse states never swallow its clicks.
-------------------------------------------------------------------------------
function EABR.LayoutProviderCastHome()
    if InCombatLockdown() then return end
    local btn = EABR._providerCastBtn
    if not btn or not iconAnchor then return end
    local p = db and db.profile and db.profile.display
    local baseScale = (p and p.scale) or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    btn:SetSize(sz, sz)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", iconAnchor, "TOPLEFT", 0, 0)
    EABR.SizeIconQuality(btn, sz)
    EABR.SizeIconBagCount(btn, sz)
end

function EABR.ParkProviderCastButton()
    local btn = EABR._providerCastBtn
    if not btn then return end
    local wasVisible = EABR._providerCastVisible
    EABR._providerCastVisible = false
    btn:SetAlpha(0)
    if btn._text then btn._text:SetText(""); btn._text:Hide() end
    if btn._eabrGlowWrapper then btn._eabrGlowWrapper:Hide() end
    if InCombatLockdown() then
        -- Slot stays reserved; move/mouse changes are protected under lockdown.
        if wasVisible or EABR._providerCastCombatReserved then
            EABR._providerCastCombatReserved = true
        end
        return
    end
    EABR._providerCastCombatReserved = false
    btn:EnableMouse(false)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
end

function EABR.EnsureProviderCastButton()
    if EABR._providerCastBtn then return EABR._providerCastBtn end
    if not iconAnchor or InCombatLockdown() then return nil end
    local btn = CreateFrame("Button", "EABR_ProviderCast", UIParent, "SecureActionButtonTemplate")
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "MiddleButtonUp")
    securecallfunction(btn.SetPassThroughButtons, btn, "RightButton")
    btn:SetAttribute("useOnKeyDown", false)
    btn:SetFrameStrata(GetStrata())
    btn:SetFrameLevel(120)
    btn:HookScript("PostClick", function(self, button)
        if button == "MiddleButton" and self._dismissKey then
            _dismissedUntilLoad[self._dismissKey] = true
            if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
        end
    end)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn._icon = icon
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7) end
    local text = EABR.GetIconTextOverlay(btn):CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    SetABRFont(text, ResolveFontPath(), 11)
    text:SetTextColor(1, 1, 1, 1)
    btn._text = text
    EABR.CreateIconCountOverlay(btn)
    EABR.CreateIconQualityOverlay(btn)
    EABR.CreateIconBagCountOverlay(btn)
    EABR.AttachIconHover(btn)
    EABR.AttachIconTooltip(btn)
    btn:Show()
    EABR._providerCastBtn = btn
    EABR._providerCastVisible = false
    EABR.ParkProviderCastButton()
    return btn
end

-- Binds the player's own castable raid buff to the button (OOC only), so the
-- binding is already warm when combat starts.
function EABR.SyncProviderCastSpell()
    if InCombatLockdown() then return end
    local btn = EABR.EnsureProviderCastButton()
    if not btn then return end
    local playerClass = GetPlayerClass()
    local spellID
    for _, buff in ipairs(RAID_BUFFS) do
        if buff.class == playerClass and buff.check == "raid" and Known(buff.castSpell) then
            spellID = buff.castSpell
            break
        end
    end
    -- Attribute writes are skipped when the resolved spell is unchanged
    -- (this runs on every OOC refresh). Invalidation inputs: the resolved
    -- spellID (covers spec/known changes via SPELLS_CHANGED refreshes).
    if spellID == EABR._providerCastSpell then
        if not EABR._providerCastVisible then EABR.ParkProviderCastButton() end
        return
    end
    EABR._providerCastSpell = spellID
    if spellID then
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", spellID)
        btn:SetAttribute("item", nil)
        btn:SetAttribute("macrotext", nil)
        btn:SetAttribute("unit", "player") -- explicit unit so casting doesn't depend on your current target
        btn._icon:SetTexture(Tex(spellID) or 134400)
        btn._tooltipSpell = spellID
        btn._tooltipItem = nil
    end
    if not EABR._providerCastVisible then
        EABR.ParkProviderCastButton()
    end
end

-- Shows/hides the provider button. OOC: full place/mouse control. Combat:
-- alpha + child visuals only (EnableMouse/SetPoint are protected).
function EABR.SetProviderCastCombatVisible(visible, m)
    local btn = EABR._providerCastBtn
    if not btn then
        EABR._providerCastVisible = false
        return
    end
    if not visible or not m or not EABR._providerCastSpell then
        EABR.ParkProviderCastButton()
        return
    end
    EABR._providerCastVisible = true
    EABR._providerCastCombatReserved = true
    btn._dismissKey = m.dismissKey or nil
    local spellID = m.spellID or EABR._providerCastSpell
    btn._icon:SetTexture(m.texture or Tex(spellID) or 134400)
    EABR.ApplyIconTooltipData(btn, m)
    local p = db and db.profile and db.profile.display
    if p and p.showText then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        SetABRFont(btn._text, ResolveFontPath(p.textFont), p.textSize or 11)
        btn._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(p)
        btn._text:SetPoint(tp, btn, ip, p.textXOffset or 0, p.textYOffset or -2)
        btn._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        btn._text:SetText(m.label or "")
        btn._text:SetAlpha(1)
        btn._text:Show()
    else
        btn._text:SetText("")
        btn._text:Hide()
    end
    if m.groupTotal then
        EABR.ApplyIconGroupCoverage(btn, m.groupHave, m.groupTotal)
    else
        EABR.ApplyIconBagCount(btn, nil, nil, nil)
    end
    if not InCombatLockdown() then
        EABR.LayoutProviderCastHome()
        btn:EnableMouse(true)
    end
    btn:SetAlpha((p and p.opacity) or 1)
end

local function IsImportantBuff(m)
    -- Cursor-worthy = a buff YOU can cast that others are missing (provider
    -- entries, mode "spell"). The receiver view (mode "texture" -- a
    -- groupmate's buff the PLAYER lacks) stays on the normal rows.
    if m.cat == "raidbuff" then return m.mode == "spell" end
    local key = m.data and m.data.key
    return key and CURSOR_IMPORTANT[key] or false
end

-- Hides stale secure buttons via alpha=0 (safe in combat); also stops glow animations (glow wrappers are plain Frames, not secure).
local function FadeOutSecureIcons()
    for i = 1, #activeIcons do
        local btn = activeIcons[i]
        if btn then
            btn:SetAlpha(0)
            if btn._text then btn._text:SetAlpha(0) end
            if btn._eabrGlowWrapper then StopAllGlows(btn._eabrGlowWrapper); btn._eabrGlowWrapper:SetAlpha(0) end
        end
    end
end

local function ApplyGlow(btn, glowType, cr, cg, cb, overrideSz)
    if glowType == 0 then return end
    local entry = GLOW_TYPES[glowType]; if not entry then return end
    if cr == nil and (entry.procedural or entry.buttonGlow or entry.autocast) then
        cr, cg, cb = 1.0, 0.788, 0.137
    end
    if not btn._eabrGlowWrapper then
        local w = CreateFrame("Frame", nil, btn); w:SetAllPoints(btn); w:SetFrameLevel(btn:GetFrameLevel()+4)
        btn._eabrGlowWrapper = w
    end
    local wrapper = btn._eabrGlowWrapper; local sz = overrideSz or btn:GetWidth() or ICON_SIZE
    StopAllGlows(wrapper)
    if entry.procedural then StartPixelGlow(wrapper, sz, cr, cg, cb)
    elseif entry.buttonGlow then StartButtonGlow(wrapper, sz, cr, cg, cb, 1.36)
    elseif entry.autocast then StartAutoCastShine(wrapper, sz, cr, cg, cb, 1.0)
    else StartFlipBookGlow(wrapper, sz, entry, cr, cg, cb) end
    wrapper:SetAlpha(1)
    wrapper:Show()
end

local function RemoveGlow(btn)
    if btn._eabrGlowWrapper then StopAllGlows(btn._eabrGlowWrapper); btn._eabrGlowWrapper:Hide() end
end

-------------------------------------------------------------------------------
--  Shared icon decorations (all pools): hover highlight, tooltips, combat
--  click hint, bag-count / coverage / crafted-quality badges, and the eating
--  countdown. All frames here are OURS (field writes are safe). Every helper
--  hangs on EABR (200-local cap).
-------------------------------------------------------------------------------
function EABR.AttachIconHover(f)
    if f._eabrHoverAttached then return end
    local icon = f._icon
    if f:IsObjectType("Button") then
        local hl = f:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(icon)
        hl:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        hl:SetColorTexture(1, 1, 1, 0.2)
    else
        f:EnableMouse(true)
        local hl = f:CreateTexture(nil, "OVERLAY")
        hl:SetAllPoints(icon)
        hl:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        hl:SetColorTexture(1, 1, 1, 0.2)
        hl:Hide()
        f:HookScript("OnEnter", function() hl:Show() end)
        f:HookScript("OnLeave", function() hl:Hide() end)
    end
    f._eabrHoverAttached = true
end

function EABR.ApplyIconTooltipData(f, m)
    if not f then return end
    if not m then
        f._tooltipItem = nil
        f._tooltipSpell = nil
        f._tooltipLabel = nil
        return
    end
    f._tooltipItem = m.tooltipItem or m.itemID or nil
    f._tooltipSpell = m.spellID or (m.data and m.data.castSpell) or nil
    f._tooltipLabel = m.label or nil
end

function EABR.ShowIconTooltip(f)
    local d = db and db.profile and db.profile.display
    if not d or d.showTooltips == false then return end
    if not f then return end
    if f._tooltipItem or f._tooltipSpell then
        -- Item/spell data tooltips render through GameTooltip (the only
        -- game-data renderer). pcall-armored: 12.1 restricted-tooltip ACLs
        -- can deny frame-level calls when the content turns secret.
        local ok = pcall(function()
            GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
            if f._tooltipItem then
                GameTooltip:SetItemByID(f._tooltipItem)
            else
                GameTooltip:SetSpellByID(f._tooltipSpell)
            end
            if f._outOfStock then
                GameTooltip:AddLine(EllesmereUI.L("You don't have this item in your bags"), 1, 0.3, 0.3, true)
            elseif f._substitute then
                GameTooltip:AddLine(EllesmereUI.L("Your preferred food is out - using a backup you own"), 1, 0.82, 0, true)
            end
            GameTooltip:Show()
        end)
        if not ok then GameTooltip:Hide() end
    elseif f._tooltipLabel and f._tooltipLabel ~= "" then
        -- Plain-text reminders use the suite tooltip, never GameTooltip.
        EllesmereUI.ShowWidgetTooltip(f, tostring(f._tooltipLabel))
    end
end

function EABR.HideIconTooltip(f)
    if f and (f._tooltipItem or f._tooltipSpell) then
        GameTooltip:Hide()
    else
        EllesmereUI.HideWidgetTooltip()
    end
end

function EABR.AttachIconTooltip(f)
    if f._eabrTooltipAttached then return end
    f:EnableMouse(true)
    f:HookScript("OnEnter", function(self) EABR.ShowIconTooltip(self) end)
    f:HookScript("OnLeave", function(self) EABR.HideIconTooltip(self) end)
    f._eabrTooltipAttached = true
end

-- Visual-only combat/cursor icons: tell the player why left-click does nothing.
function EABR.NotifyCombatClickDisabled()
    local now = GetTime()
    if EABR._clickHintAt and now - EABR._clickHintAt < 2.5 then return end
    EABR._clickHintAt = now
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(EllesmereUI.L("Click-to-use is disabled in combat"), 1.0, 0.3, 0.3, 1.0)
    end
end

function EABR.AttachCombatClickHint(f)
    if f._eabrCombatClickHint then return end
    f:EnableMouse(true)
    f:HookScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            EABR.NotifyCombatClickDisabled()
        end
    end)
    f._eabrCombatClickHint = true
end

function EABR.CreateIconCountOverlay(f)
    if f._count then return f._count end
    local count = EABR.GetIconTextOverlay(f):CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    count:SetPoint("CENTER", f._icon, "CENTER", 0, 0)
    count:Hide()
    f._count = count
    return count
end

-- Crafted-quality badge (Professions Tier 1/2/3) for a consumable, or nil.
-- Crafted quality is immutable per item, so only positive hits are cached.
EABR._qualityAtlasCache = EABR._qualityAtlasCache or {}
function EABR.GetItemQualityAtlas(itemID)
    if not itemID then return nil end
    local cached = EABR._qualityAtlasCache[itemID]
    if cached then return cached end
    local atlas
    if C_TradeSkillUI and C_TradeSkillUI.GetItemCraftedQualityByItemInfo then
        local ok, q = pcall(C_TradeSkillUI.GetItemCraftedQualityByItemInfo, itemID)
        if ok and q and q > 0 then
            atlas = "Professions-Icon-Quality-Tier" .. q
        end
    end
    if not atlas then
        local link = select(2, C_Item.GetItemInfo(itemID))
        if link then
            local suffix = link:match("Quality%-[%w%-]*Tier%d")
            if suffix then atlas = "Professions-Icon-" .. suffix end
        end
    end
    if atlas then EABR._qualityAtlasCache[itemID] = atlas end
    return atlas
end

function EABR.CreateIconQualityOverlay(f)
    if f._quality then return f._quality end
    local q = f:CreateTexture(nil, "OVERLAY", nil, 7)
    q:Hide()
    f._quality = q
    return q
end

function EABR.SizeIconQuality(f, sz)
    local q = f._quality
    if not q or not f._qualityAtlas then return end
    local qs = max(10, floor(sz * 0.42))
    local off = floor(sz * 0.10)
    q:SetSize(qs, qs)
    q:ClearAllPoints()
    q:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -off, -off)
end

function EABR.ApplyIconQuality(f, atlas)
    if not f then return end
    EABR.CreateIconQualityOverlay(f)
    f._qualityAtlas = atlas or nil
    local q = f._quality
    if atlas then
        q:SetAtlas(atlas)
        EABR.SizeIconQuality(f, f:GetWidth() or ICON_SIZE)
        q:Show()
    else
        q:Hide()
    end
end

-- Bag-count badge (how many of the consumable remain), bottom-right corner.
function EABR.CreateIconBagCountOverlay(f)
    if f._bagCount then return f._bagCount end
    local fs = EABR.GetIconTextOverlay(f):CreateFontString(nil, "OVERLAY")
    SetABRFont(fs, ResolveFontPath(), 11)
    fs:Hide()
    f._bagCount = fs
    return fs
end

function EABR.SizeIconBagCount(f, sz)
    local fs = f._bagCount
    if not fs or not f._bagCountShown then return end
    local p = db and db.profile.display
    local base = (p and p.countSize) or 16
    local fsz = max(6, floor(base * (sz / ICON_SIZE) + 0.5))
    SetABRFont(fs, ResolveFontPath(p and p.textFont), fsz)
    local dx = (p and p.countXOffset) or 0
    local dy = (p and p.countYOffset) or 0
    fs:ClearAllPoints()
    fs:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", dx, dy)
end

function EABR.ApplyIconBagCount(f, count, outOfStock, substitute)
    if not f then return end
    EABR.CreateIconBagCountOverlay(f)
    f._outOfStock = outOfStock and true or nil
    f._substitute = (substitute and not outOfStock) and true or nil
    local fs = f._bagCount
    local p = db and db.profile.display
    local showCount = not p or p.showCount ~= false
    if showCount and outOfStock then
        f._bagCountShown = true
        fs:SetText("0")
        fs:SetTextColor(1, 0.2, 0.2, 1)
        EABR.SizeIconBagCount(f, f:GetWidth() or ICON_SIZE)
        fs:Show()
    elseif showCount and count and count > 0 then
        f._bagCountShown = true
        fs:SetText(count)
        if substitute then
            fs:SetTextColor(1, 0.82, 0, 1)
        else
            fs:SetTextColor(1, 1, 1, 1)
        end
        EABR.SizeIconBagCount(f, f:GetWidth() or ICON_SIZE)
        fs:Show()
    else
        f._bagCountShown = nil
        fs:SetText("")
        fs:Hide()
    end
end

-- Raid-buff group coverage ("12/15") on the same corner badge as item count.
function EABR.ApplyIconGroupCoverage(f, have, total)
    if not f then return end
    EABR.CreateIconBagCountOverlay(f)
    local fs = f._bagCount
    if have ~= nil and total and total > 0 then
        f._bagCountShown = true
        f._outOfStock = nil
        f._substitute = nil
        fs:SetText(have .. "/" .. total)
        fs:SetTextColor(1, 1, 1, 1)
        EABR.SizeIconBagCount(f, f:GetWidth() or ICON_SIZE)
        fs:Show()
    else
        f._bagCountShown = nil
        fs:SetText("")
        fs:Hide()
    end
end

-------------------------------------------------------------------------------
--  Eating countdown: while the eating channel runs, the food reminder shows
--  the eating icon with a centered countdown instead of nagging mid-meal.
--  The OnUpdate exists ONLY while eating and is throttled to ~5/sec with no
--  per-tick allocation (text only rewritten on change); it self-clears at
--  expiry and requests one refresh.
-------------------------------------------------------------------------------
function EABR.ClearEatingVisual(f)
    if f._eabrEatingOnUpdate then
        f:SetScript("OnUpdate", nil)
        f._eabrEatingOnUpdate = nil
    end
    if f._count then f._count:Hide() end
    f._eabrEatingIcon = nil
end

function EABR.EatingTick(self, elapsed)
    self._eatingAccum = (self._eatingAccum or 0) + elapsed
    if self._eatingAccum < 0.2 then return end
    self._eatingAccum = 0
    local rem = (self._eatingExp or 0) - GetTime()
    if rem > 0 then
        local txt
        local mins = math.ceil(rem / 60)
        if mins > 1 then
            txt = mins .. "m"
        else
            txt = math.ceil(rem) .. "s"
        end
        if txt ~= self._eatingText then
            self._eatingText = txt
            self._count:SetText(txt)
        end
        self._count:Show()
        if self._text then self._text:Hide() end
    else
        self._count:Hide()
        self:SetScript("OnUpdate", nil)
        self._eabrEatingOnUpdate = nil
        if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
    end
end

function EABR.ApplyEatingVisual(f, m)
    EABR.ClearEatingVisual(f)
    if not (m and m.isEating) then return end
    EABR.CreateIconCountOverlay(f)
    f._icon:SetDesaturated(false)
    f._icon:SetTexture(133950)
    f._eabrEatingIcon = true
    RemoveGlow(f)
    local expTime = m.eatingExpirationTime
    if not expTime then return end
    local p = db and db.profile.display
    local fontPath = ResolveFontPath(p and p.textFont)
    local textSize = max(14, floor(((p and p.textSize) or 11) * 1.15))
    SetABRFont(f._count, fontPath, textSize)
    f._count:SetTextColor(1, 1, 1, 1)
    f._eatingExp = expTime
    f._eatingText = nil
    f._eatingAccum = 1 -- force an immediate paint on the first tick
    EABR.EatingTick(f, 0)
    f._eabrEatingOnUpdate = true
    f:SetScript("OnUpdate", EABR.EatingTick)
end

local function GetOrCreateIcon(index)
    if iconPool[index] then return iconPool[index] end
    -- SecureActionButtonTemplate for click-to-cast in combat
    local btn = CreateFrame("Button", "EABR_Icon"..index, iconAnchor, "SecureActionButtonTemplate")
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "MiddleButtonUp")
    securecallfunction(btn.SetPassThroughButtons, btn, "RightButton")
    btn:SetFrameStrata(GetStrata())
    btn:Hide()

    -- Middle-click dismiss: hide this reminder until the next loading screen
    btn:HookScript("PostClick", function(self, button)
        if button == "MiddleButton" and self._dismissKey then
            _dismissedUntilLoad[self._dismissKey] = true
            if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
        end
    end)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn._icon = icon
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7) end

    local text = EABR.GetIconTextOverlay(btn):CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    SetABRFont(text, ResolveFontPath(), 11)
    text:SetTextColor(1, 1, 1, 1)
    btn._text = text

    EABR.CreateIconCountOverlay(btn)
    EABR.CreateIconQualityOverlay(btn)
    EABR.CreateIconBagCountOverlay(btn)
    EABR.AttachIconHover(btn)
    EABR.AttachIconTooltip(btn)

    iconPool[index] = btn
    return btn
end


-- Sets icon to a plain texture with no click action (clears cast attributes OOC).
local function SetIconTexture(btn, texture, label)
    if not InCombat() then
        btn:SetAttribute("type", nil)
        btn:SetAttribute("spell", nil)
        btn:SetAttribute("item", nil)
        btn:SetAttribute("macrotext", nil)
    end
    btn._icon:SetTexture(texture or 134400)
    btn._tooltipSpell = nil
    btn._tooltipItem = nil
end

local function SetIconSpell(btn, spellID, texture, label)
    if not InCombat() then
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", spellID)
        btn:SetAttribute("item", nil)
        btn:SetAttribute("macrotext", nil)
        btn:SetAttribute("unit", "player")
    end
    btn._icon:SetTexture(texture or Tex(spellID) or 134400)
    btn._tooltipSpell = spellID
    btn._tooltipItem = nil
end

local function SetIconItem(btn, itemID, texture, label)
    if not InCombat() then
        btn:SetAttribute("type", "item")
        btn:SetAttribute("item", "item:"..itemID)
        btn:SetAttribute("spell", nil)
        btn:SetAttribute("macrotext", nil)
        btn:SetAttribute("unit", nil)
    end
    btn._icon:SetTexture(texture or GetItemIcon(itemID) or 134400)
    btn._tooltipSpell = nil
    btn._tooltipItem = itemID
end

local function SetIconMacro(btn, macrotext, texture, spellID)
    if not InCombat() then
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macrotext", macrotext)
        btn:SetAttribute("spell", nil)
        btn:SetAttribute("item", nil)
        btn:SetAttribute("unit", nil)
    end
    btn._icon:SetTexture(texture or 134400)
    btn._tooltipSpell = spellID
    btn._tooltipItem = nil
end


-------------------------------------------------------------------------------
--  Data-driven setup: eliminates per-refresh closure + table allocations
-------------------------------------------------------------------------------
-- Pre-allocated entry pool + data-driven setup (eliminates per-refresh closures)
local AcquireEntry, ResetEntryPool, ApplySetup
do
    local pool = {}
    local inUse = 0

    AcquireEntry = function()
        inUse = inUse + 1
        local e = pool[inUse]
        if not e then
            e = {}
            pool[inUse] = e
        end
        e.mode = nil; e.spellID = nil; e.itemID = nil; e.macro = nil
        e.texture = nil; e.label = nil; e.unit = nil; e.desaturated = false
        e.tooltipItem = nil
        e.cat = nil; e.data = nil; e.dismissKey = nil
        e.isEating = nil; e.eatingExpirationTime = nil
        e.qualityAtlas = nil
        e.bagCount = nil
        e.substitute = nil
        e.groupHave = nil
        e.groupTotal = nil
        return e
    end

    ResetEntryPool = function()
        inUse = 0
    end

    ApplySetup = function(btn, m)
        local mode = m.mode
        if mode == "spell" then
            SetIconSpell(btn, m.spellID, m.texture or Tex(m.spellID), m.label)
            if m.unit and not InCombat() then
                btn:SetAttribute("unit", m.unit)
            end
        elseif mode == "item" then
            SetIconItem(btn, m.itemID, m.texture, m.label)
        elseif mode == "macro" then
            SetIconMacro(btn, m.macro, m.texture or (m.spellID and Tex(m.spellID)), m.spellID)
            btn._tooltipItem = m.tooltipItem
        else -- "texture"
            SetIconTexture(btn, m.texture, m.label)
            if m.spellID then btn._tooltipSpell = m.spellID end
        end
        btn._text:SetText(m.label or "")
        btn._icon:SetDesaturated(m.desaturated or false)
        btn._tooltipLabel = m.label or nil
    end
end

-------------------------------------------------------------------------------
--  Core Refresh Logic
-------------------------------------------------------------------------------
local refreshQueued = false
local pendingOOCRefresh = false

local function HideAllIcons()
    if InCombatLockdown() then return end  -- cannot hide SecureActionButtons after lockdown begins
    -- Sweep the WHOLE pool, never just activeIcons: a combat fade leaves icons
    -- shown at alpha 0, and any window where the list rebuilds without those
    -- frames orphans them -- shown, invisible, still hover/tooltip-live (field:
    -- an invisible stuck Augment Rune). The pool is a dozen frames and this
    -- runs on OOC edges only, so the sweep costs nothing; alpha resets here so
    -- a swept frame can never carry a stale fade into its next show.
    for _, btn in pairs(iconPool) do
        if btn then
            RemoveGlow(btn); EABR.ClearEatingVisual(btn)
            btn._text:SetText(""); btn._text:SetAlpha(1)
            btn._icon:SetDesaturated(false)
            btn:SetAlpha(1)
            btn:Hide()
        end
    end
    wipe(activeIcons)
end

local function ResizeAnchorCentered(newW, newH)
    if not iconAnchor or InCombatLockdown() then return end
    iconAnchor:SetSize(newW, newH)
end

local _layoutScratch = {}  -- reused each call
local function LayoutIcons()
    if InCombatLockdown() then return end
    -- Merges beacon icons into the layout (one continuous row); beacon logic itself is untouched, just included here for positioning.
    local allIcons = _layoutScratch
    wipe(allIcons)
    -- Provider raid-buff button is a separate UIParent secure button; slot 0
    -- of the row when shown.
    if EABR._providerCastVisible and EABR._providerCastBtn then
        allIcons[#allIcons+1] = EABR._providerCastBtn
    end
    for _, btn in ipairs(activeIcons) do allIcons[#allIcons+1] = btn end
    local beaconsOnCursor = db and db.profile.display.cursorAttach and cursorAnchor
    if _B.icons and not beaconsOnCursor then
        for _, id in ipairs(_B.ALL or {}) do
            if _B.iconState and _B.iconState[id] and _B.icons[id] then
                allIcons[#allIcons+1] = _B.icons[id]
            end
        end
    end
    local count = #allIcons; if count == 0 then return end
    local p = db.profile.display
    local spacing = p.iconSpacing or 8
    local baseScale = p.scale or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    local totalW = (count * sz) + ((count-1) * spacing)
    local textH = 0
    if p.showText then textH = (p.textSize or 11) + abs(p.textYOffset or -2) end
    -- Center-grow: icons pin to the anchor's CENTER and spread symmetrically so the row's center stays fixed as
    -- icons are added/removed, and resizing the anchor (unlock overlay) never shifts them; +textH/2 keeps the row at the icon+text box's top, matching the combat pool.
    local startX = -(totalW / 2) + (sz / 2)
    for i, btn in ipairs(allIcons) do
        btn:SetSize(sz, sz)
        btn:SetAlpha(p.opacity or 1.0)
        EABR.SizeIconQuality(btn, sz)
        EABR.SizeIconBagCount(btn, sz)
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", iconAnchor, "CENTER", startX + (i-1)*(sz+spacing), textH/2)
    end
    -- Size the anchor to the row so the unlock mode overlay covers it.
    ResizeAnchorCentered(totalW, sz + textH)
end

local function ShowIcon(iconIdx, m)
    local btn = GetOrCreateIcon(iconIdx)
    btn._dismissKey = m.dismissKey or nil
    ApplySetup(btn, m)
    local p = db.profile.display
    local glowType = p.glowType or 0
    local gr, gg, gb = ResolveGlowTint(p)
    local baseScale = p.scale or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    RemoveGlow(btn)
    ApplyGlow(btn, glowType, gr, gg, gb, sz)
    EABR.ApplyEatingVisual(btn, m)
    EABR.ApplyIconQuality(btn, (not m.isEating) and m.qualityAtlas or nil)
    if m.groupTotal then
        EABR.ApplyIconGroupCoverage(btn, m.groupHave, m.groupTotal)
    else
        EABR.ApplyIconBagCount(btn, (not m.isEating) and m.bagCount or nil,
            (not m.isEating) and m.desaturated or nil,
            (not m.isEating) and m.substitute or nil)
    end
    if p.showText and not m.isEating then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        local fontPath = ResolveFontPath(p.textFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        SetABRFont(btn._text, fontPath, textSize)
        btn._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(p)
        btn._text:SetPoint(tp, btn, ip, xOff, yOff)
        btn._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        btn._text:Show()
    else
        btn._text:SetText("")
        btn._text:Hide()
    end
    btn:Show()
    activeIcons[#activeIcons+1] = btn
end


local function CollectRaidBuffs(missing, playerClass, inInstance, inCombat)
local rb = db.profile.raidBuffs
do
    if not EABR.SectionShows(rb.whereToShow, inInstance) then return end
    local _, iType = IsInInstance()
    local inPvP = (iType == "pvp" or iType == "arena")
    local sw = rb.showWhen or {}
    local othersMissing = sw.othersMissing ~= false
    local iAmMissing = sw.iAmMissing == true
    -- Receiver view ("I am missing others' buffs") only scans group
    -- composition when opted in and actually grouped -- the default case
    -- stays allocation-free.
    local groupClasses
    if iAmMissing and (IsInGroup() or IsInRaid()) then
        groupClasses = EABR.BuildGroupClassSet()
    end
    for _, buff in ipairs(RAID_BUFFS) do
        if rb.enabled[buff.key] and not (buff.noPvP and inPvP) then
            local iCast = (buff.class == playerClass) and Known(buff.castSpell)
            -- Provider view when I can cast it; receiver view when I can't
            -- but a groupmate of the right class can (and my class benefits).
            local doReceiver = (not iCast) and iAmMissing and buff.check == "raid"
                and groupClasses and groupClasses[buff.class]
                and EABR.PlayerBenefitsFromBuff(buff)
            if iCast or doReceiver then
                -- In combat, skip buffs whose IDs are not all whitelisted
                local canCheck = true
                if inCombat then
                    if buff.check == "huntersMark" then
                        canCheck = true  -- uses state flag, no aura reading needed
                    else
                        for _, id in ipairs(buff.buffIDs) do
                            if not NON_SECRET_SPELL_IDS[id] then canCheck = false; break end
                        end
                    end
                end
                if canCheck then
                    local isMissing = false
                    local groupHave, groupTotal
                    if iCast then
                        if buff.check == "huntersMark" then
                            isMissing = inCombat and _huntersMarkNeeded
                        elseif othersMissing and buff.check == "raid" and (IsInGroup() or IsInRaid()) then
                            groupHave, groupTotal = CountGroupBuffCoverage(buff.buffIDs, buff.benefit)
                            isMissing = groupTotal > 0 and groupHave < groupTotal
                        else
                            isMissing = not PlayerHasAuraByID(buff.buffIDs, "raidbuff")
                        end
                    else
                        -- Receiver view: only whether the player personally lacks it.
                        isMissing = not PlayerHasAuraByID(buff.buffIDs, "raidbuff")
                    end
                    if isMissing then
                        local e = AcquireEntry()
                        e.spellID = buff.castSpell
                        e.label = ShortLabel(_G._EABR_SpellName(buff.castSpell, buff.name))
                        if buff.check == "huntersMark" then e.unit = "target" end
                        e.cat = "raidbuff"; e.data = buff
                        e.dismissKey = buff.key and ("raidbuff:" .. buff.key) or nil
                        if groupTotal then
                            e.groupHave = groupHave
                            e.groupTotal = groupTotal
                        end
                        if doReceiver then
                            -- Receiver reminders are informational: texture
                            -- mode, no click action.
                            e.mode = "texture"
                            e.texture = Tex(buff.castSpell)
                        else
                            e.mode = "spell"
                        end
                        missing[#missing+1] = e
                    end
                end
            end
        end
    end
end

end

local function CollectAuras(missing, playerClass, specID, inInstance, inCombat)
local au = db.profile.auras
do
    if not EABR.SectionShows(au.whereToShow, inInstance) then return end
    for _, aura in ipairs(AURAS) do
        if aura.standalone then
            -- Handled by standalone system, skip
        elseif au.enabled[aura.key] and (aura.class == playerClass)
           and ((aura.isStance and GetStanceState(aura.castSpell)) or (not aura.isStance and Known(aura.castSpell)))
           and not (aura.notIfKnown and Known(aura.notIfKnown))
           and not (aura.requireTalent and not Known(aura.requireTalent))
           and not (aura.noPvP and InPvPInstance()) then
            local specOk = true
            if aura.specs then
                specOk = false
                for _, s in ipairs(aura.specs) do if s == specID then specOk = true; break end end
            end
            if specOk then
                -- Skip auras that require instance + group when not in both
                if aura.requireInstanceGroup and (not inInstance or not (IsInGroup() or IsInRaid())) then
                    specOk = false
                end
                -- Skip auras that require a group when solo
                if aura.requireGroup and not (IsInGroup() or IsInRaid()) then
                    specOk = false
                end
            end
            if specOk then
                -- Restricted contexts (combat / M+): only track reminders
                -- whose detection survives the aura lock -- stances/forms
                -- (the shapeshift API is unrestricted) or auras whose buff
                -- IDs are all whitelisted. combatOk entries keep their own
                -- snapshot machinery. Everything else is skipped to avoid
                -- false flashes.
                local canCheck = true
                if inCombat then
                    if aura.isStance or aura.formSpellIDs then
                        canCheck = true
                    elseif aura.buffIDs and aura.buffIDs[1] then
                        for _, id in ipairs(aura.buffIDs) do
                            if not NON_SECRET_SPELL_IDS[id] then canCheck = false; break end
                        end
                    else
                        canCheck = false
                    end
                end
                if canCheck then
                    local isMissing = false
                    if aura.check == "mineOnRaid" then
                        if inCombat then
                            isMissing = false
                        else
                            isMissing = not BuffExistsOnAnyGroupMember(aura.buffIDs)
                            if not (IsInGroup() or IsInRaid()) then isMissing = false end
                        end
                    elseif aura.check == "ownOnRaid" then
                        if inCombat then
                            local cached = _preCombatOwnOnRaidCache[aura.buffIDs[1]]
                            isMissing = (cached == false)
                        else
                            isMissing = not PlayerOwnBuffOnAnyGroupMember(aura.buffIDs)
                        end
                        if not (IsInGroup() or IsInRaid()) then isMissing = false end
                    elseif aura.check == "playerSelfCast" then
                        isMissing = not PlayerHasSelfCastAuraByID(aura.buffIDs)
                    elseif aura.isStance then
                        -- Stance is a shapeshift form: hide once it's the active stance
                        local _, isActive = GetStanceState(aura.castSpell)
                        isMissing = not isActive
                    else
                        -- Use instance-specific buff list if available and in instance
                        local checkIDs = (inInstance and aura.instanceBuffIDs) or aura.buffIDs
                        -- When aura reads are restricted (PvP, combat, M+),
                        -- fall back to scanning the shapeshift form bar for
                        -- form-based auras whose buff IDs aren't readable.
                        if aura.formSpellIDs and (inCombat or InPvPInstance()) then
                            isMissing = not IsAnyShapeshiftFormActive(aura.formSpellIDs)
                        else
                            local hasIt = PlayerHasAuraByID(checkIDs, "aura")
                            -- Some auras (e.g. Devotion Aura) go fully secret
                            -- rather than merely duration/expiration-secret
                            -- when their source is ambiguous (another
                            -- provider of the same aura in the party); the ID
                            -- lookup then can't see it at all. Fall back to a
                            -- name scan before declaring it missing.
                            if not hasIt and aura.nameFallback then
                                hasIt = PlayerHasBuffByName(aura.nameFallback)
                            end
                            isMissing = not hasIt
                        end
                    end
                    if isMissing then
                        local e = AcquireEntry()
                        e.mode = "spell"; e.spellID = aura.castSpell
                        e.label = ShortLabel(_G._EABR_SpellName(aura.castSpell, aura.name))
                        e.cat = "aura"; e.data = aura
                        e.dismissKey = "aura:" .. aura.key
                        missing[#missing+1] = e
                    end
                end
            end
        end
    end
end

end

-- Weapon-enchant reminders shared by the OOC and restricted (M+/combat)
-- passes -- the enchant summary API is combat-safe. Hung on EABR (200-local
-- cap).
function EABR.EmitWeaponEnchantReminders(missing, co)
    local hasMH, mhExpire, _, _, hasOH, ohExpire = EABR.WeaponEnchants()
    for i = 1, 2 do
        local slot = (i == 1) and 16 or 17
        local has = (i == 1) and hasMH or hasOH
        local expire = (i == 1) and mhExpire or ohExpire
        local r = EABR._resolved.we[slot]
        local cat = r.cat
        local shouldRemind = false
        if cat and not has then
            shouldRemind = true
        elseif cat and has and expire and expire > 0 then
            local expireTime = expire / 1000 + GetTime()
            if IsUnderDuration(3600, expireTime, "consumable") then
                shouldRemind = true
            end
        end
        if shouldRemind and r.itemID and (co.showWithoutItem ~= false or r.hasBags) then
            local bestItemID = r.itemID
            local e = AcquireEntry()
            e.mode = "macro"
            e.macro = "/use item:" .. bestItemID .. "\n/use " .. slot
            e.texture = GetItemIcon(bestItemID) or 134400
            -- Localizes the full slot name THEN shortens: ShortLabel truncates on whitespace (English -> Main/Off, space-less locales like zhTW stay intact). L() on the pre-truncated word would collide with the generic Off (disabled) translation.
            e.label = ShortLabel(EllesmereUI.L(slot == 16 and "Main Hand" or "Off Hand"))
            e.tooltipItem = bestItemID
            e.qualityAtlas = EABR.GetItemQualityAtlas(bestItemID)
            e.bagCount = CachedGetItemCount(bestItemID)
            e.desaturated = not r.hasBags
            e.cat = "consumable"
            e.dismissKey = "consumable:weapon_enchant_" .. slot
            missing[#missing+1] = e
        end
    end
end

local function CollectConsumables(missing, playerClass, specID, inInstance, inKeystone, inCombat)
local co = db.profile.consumables
-- Class specials (poisons/rites/imbues/shields) share one "Where to Show"
-- set (they are class-exclusive; per-spell visibility would be meaningless).
local specialsActive = EABR.SectionShows(co.specialsWhereToShow, inInstance)
-- The trackable subset (weapon enchants, poisons, rites, imbues, Earth
-- Shield) runs in combat / M+ too; where reminders appear is governed
-- per-section by "Where to Show". Non-trackable emitters below either
-- self-suppress in restricted contexts (flask/food/inky/rune) or carry
-- their own combat gate.
    do

        -- Rebuilds the bag/equip-derived item cache only when inputs changed (bags, weapon, preferred-item setting); a clean refresh is 3 scalar compares. Resolved inside instances, or in the open world when the consumables section shows there; the dirty flag persists until the next eligible refresh consumes it.
        local needResolve = inInstance
        if not needResolve then
            local ow = co.whereToShow
            needResolve = (not ow) or (ow.open_world ~= false)
        end
        if needResolve then EABR.ResolveConsumables() end

        -- === SPECIALS (share the class-specials "Where to Show") ===
        if specialsActive then
            -- Rogue Poisons: unified scan counts active per category vs required (1 each, 2 with Dragon-Tempered Blades); shows the first enabled+known+missing poison per deficient category.
            if playerClass == "ROGUE" then
                local activeL, activeNL = 0, 0
                local knownL, knownNL = 0, 0
                local missingL, missingNL = nil, nil
                for _, poison in ipairs(ROGUE_POISONS) do
                    if Known(poison.castSpell) then
                        local isLethal = (poison.cat == "lethal")
                        if isLethal then knownL = knownL + 1 else knownNL = knownNL + 1 end
                        local aura = C_UnitAuras.GetPlayerAuraBySpellID(poison.castSpell)
                        local active = aura and not IsUnderDuration(aura.duration, aura.expirationTime, "special")
                        if active then
                            if isLethal then activeL = activeL + 1 else activeNL = activeNL + 1 end
                        elseif co.enabled[poison.key] then
                            if isLethal and not missingL then missingL = poison
                            elseif not isLethal and not missingNL then missingNL = poison end
                        end
                    end
                end
                local hasDTB = IsPlayerSpell(DTB_SPELL_ID)
                local reqL = min(knownL, hasDTB and 2 or 1)
                local reqNL = min(knownNL, hasDTB and 2 or 1)
                if missingL and activeL < reqL then
                    local e = AcquireEntry()
                    e.mode = "spell"; e.spellID = missingL.castSpell
                    e.label = ShortLabel(_G._EABR_SpellName(missingL.castSpell, missingL.name), "ROGUE")
                    e.cat = "consumable"; e.data = missingL
                    e.dismissKey = "consumable:rogue_lethal"
                    missing[#missing+1] = e
                end
                if missingNL and activeNL < reqNL then
                    local e = AcquireEntry()
                    e.mode = "spell"; e.spellID = missingNL.castSpell
                    e.label = ShortLabel(_G._EABR_SpellName(missingNL.castSpell, missingNL.name), "ROGUE")
                    e.cat = "consumable"; e.data = missingNL
                    e.dismissKey = "consumable:rogue_nonlethal"
                    missing[#missing+1] = e
                end
            end

            -- Paladin Rites
            if playerClass == "PALADIN" then
                for _, rite in ipairs(PALADIN_RITES) do
                    if co.enabled[rite.key] and Known(rite.castSpell) then
                        local hasMH, mhExpire = EABR.WeaponEnchants()
                        local show = false
                        if not hasMH then
                            show = true
                        elseif mhExpire and mhExpire > 0 and IsUnderDuration(3600, mhExpire / 1000 + GetTime(), "consumable") then
                            show = true
                        end
                        if show then
                            local e = AcquireEntry()
                            local spellName = _G._EABR_SpellName(rite.castSpell, rite.name)
                            e.mode = "macro"
                            e.spellID = rite.castSpell
                            e.macro = "/cast " .. spellName .. "\n/use 16"
                            e.label = ShortLabel(_G._EABR_SpellName(rite.castSpell, rite.name))
                            e.cat = "consumable"; e.data = rite
                            e.dismissKey = "consumable:" .. rite.key
                            missing[#missing+1] = e
                            break -- rites are mutually exclusive weapon enchants
                        end
                    end
                end
            end

            -- Shaman Imbues: matches each imbue's wepEnchID against both weapon slots; the enchant summary carries the specific enchant ID per hand (4th/8th return values).
            if playerClass == "SHAMAN" then
                local hasMH, mhExpire, _, mhEnchID, hasOH, ohExpire, _, ohEnchID = EABR.WeaponEnchants()
                for _, imbue in ipairs(SHAMAN_IMBUES) do
                    if co.enabled[imbue.key] and Known(imbue.castSpell)
                       and (not imbue.requireShield or EABR.HasShieldEquipped()) then
                        local found = false
                        if imbue.wepEnchID then
                            for _, eid in ipairs(imbue.wepEnchID) do
                                if eid > 0 and ((hasMH and mhEnchID == eid) or (hasOH and ohEnchID == eid)) then
                                    -- Uses the matched hand's expire time, not min of both -- an unenchanted hand returns 0, which would always trigger.
                                    local matchExpire
                                    if hasMH and mhEnchID == eid then
                                        matchExpire = mhExpire
                                    else
                                        matchExpire = ohExpire
                                    end
                                    if matchExpire and matchExpire > 0 and IsUnderDuration(3600, matchExpire / 1000 + GetTime(), "consumable") then
                                        found = false
                                    else
                                        found = true
                                    end
                                end
                            end
                        end
                        if not found then
                            local e = AcquireEntry()
                            e.mode = "spell"; e.spellID = imbue.castSpell
                            e.label = ShortLabel(_G._EABR_SpellName(imbue.castSpell, imbue.name), "SHAMAN_IMBUE")
                            e.cat = "consumable"; e.data = imbue
                            e.dismissKey = "consumable:" .. imbue.key
                            missing[#missing+1] = e
                        end
                    end
                end

                -- Shaman Shields: talent-gated entries. Earth Shield self-buff (383648) is handled separately below (also OOC-only despite being whitelisted -- see that block); other shields' IDs are not whitelisted either, so they stay OOC-only.
                for _, shield in ipairs(SHAMAN_SHIELDS) do
                    local castID = shield.castSpellFn and shield.castSpellFn() or shield.castSpell
                    if co.enabled[shield.key] ~= false and Known(castID) then
                        local ok = true
                        if shield.requireTalent and not Known(shield.requireTalent) then ok = false end
                        if shield.excludeTalent and Known(shield.excludeTalent) then ok = false end
                        -- es_orbit is combat-safe, handled below
                        if shield.key == "es_orbit" then ok = false end
                        if inCombat or inKeystone then ok = false end
                        if ok and not PlayerHasAuraByID(shield.buffIDs, "special") then
                            local e = AcquireEntry()
                            e.mode = "spell"; e.spellID = castID
                            e.label = ShortLabel(shield.name, "SHAMAN_SHIELD")
                            e.cat = "consumable"; e.data = shield
                            e.dismissKey = "consumable:" .. shield.key
                            missing[#missing+1] = e
                        end
                    end
                end

            end
        end -- end specialsActive

        -- === CONSUMABLES (visibility via the section "Where to Show") ===

        -- Augment Runes: presence unverifiable in combat/M+ (suppress);
        -- otherwise try the read and remind when missing.
        if co.enabled.augment_rune and EABR.ConsumableShows(co, "augment_rune", inInstance) then
            local hasRuneBuff = EABR.ConsumablePresenceUnverifiable() or PlayerHasAuraByID(RUNE_BUFF_IDS)
            if not hasRuneBuff then
                local rr = EABR._resolved.rune
                local runeItem = rr.itemID
                if runeItem and (co.showWithoutItem ~= false or rr.hasBags) then
                    local e = AcquireEntry()
                    e.mode = "item"; e.itemID = runeItem
                    e.texture = GetItemIcon(runeItem); e.label = EllesmereUI.L(ShortLabel("Augment Rune"))
                    e.qualityAtlas = EABR.GetItemQualityAtlas(runeItem)
                    e.bagCount = CachedGetItemCount(runeItem)
                    e.desaturated = not rr.hasBags
                    e.cat = "consumable"
                    e.dismissKey = "consumable:rune"
                    missing[#missing+1] = e
                end
            end
        end

        -- Weapon Enchants (temp enchant items; the enchant summary API is
        -- combat-safe). Skipped if the player knows any imbue spell (Shaman
        -- imbues, Paladin rites). Rogues/DKs NOT excluded -- poisons are
        -- temp enchants too, and DKs can use oils alongside runeforges.
        if co.enabled.weapon_enchant and EABR.ConsumableShows(co, "weapon_enchant", inInstance) then
            local _hasImbueSpell = false
            for _, sid in ipairs(_IMBUE_EXCLUDE_SPELLS) do
                if IsSpellKnown(sid) then _hasImbueSpell = true; break end
            end
            if not _hasImbueSpell then
                EABR.EmitWeaponEnchantReminders(missing, co)
            end
        end

        -- Flask / Food: remind only when absence is verifiable (the checks
        -- suppress under combat/M+/restriction instead of false-firing).
        if co.enabled.flask and EABR.ConsumableShows(co, "flask", inInstance) then
            if not PlayerHasFlaskBuff() then
                local rf = EABR._resolved.flask
                local flaskItemID = rf.itemID
                if flaskItemID and (co.showWithoutItem ~= false or rf.hasBags) then
                    local e = AcquireEntry()
                    e.mode = "item"; e.itemID = flaskItemID
                    e.texture = GetItemIcon(flaskItemID) or 134830
                    e.label = EllesmereUI.L("Flask")
                    e.qualityAtlas = EABR.GetItemQualityAtlas(flaskItemID)
                    e.bagCount = CachedGetItemCount(flaskItemID)
                    e.desaturated = not rf.hasBags
                    e.cat = "consumable"
                    e.dismissKey = "consumable:flask"
                    missing[#missing+1] = e
                end
            end
        end

        if co.enabled.food and EABR.ConsumableShows(co, "food", inInstance) then
            if not PlayerHasWellFed() then
                local foodItemID = EABR._resolved.food.itemID
                if foodItemID and (co.showWithoutItem ~= false or EABR._resolved.food.hasBags) then
                    local e = AcquireEntry()
                    e.mode = "item"; e.itemID = foodItemID
                    e.texture = GetItemIcon(foodItemID) or 134062
                    e.label = EllesmereUI.L("Food")
                    e.qualityAtlas = EABR.GetItemQualityAtlas(foodItemID)
                    e.bagCount = CachedGetItemCount(foodItemID)
                    e.desaturated = not EABR._resolved.food.hasBags
                    e.substitute = EABR._resolved.food.isSubstitute
                    e.cat = "consumable"
                    e.dismissKey = "consumable:food"
                    if EABR.IsPlayerEating() then
                        e.isEating = true
                        e.eatingExpirationTime = EABR.GetEatingExpirationTime()
                    end
                    missing[#missing+1] = e
                end
            end
        end

        -- Inky Black Potion (zone-specific)
        if co.enabled.inky_black and EABR.ConsumableShows(co, "inky_black", inInstance) then
            local zones = co.inkyBlackZones or ""
            if zones ~= "" then
                -- Cache parsed zone set on the string itself
                if not co._inkyZoneSet or co._inkyZoneSrc ~= zones then
                    local s = {}
                    for zid in zones:gmatch("[^,%s]+") do s[zid] = true end
                    co._inkyZoneSet = s
                    co._inkyZoneSrc = zones
                end
                local currentZone = tostring(C_Map.GetBestMapForUnit("player") or 0)
                if co._inkyZoneSet[currentZone] then
                    local hasPotion = EABR._resolved.inky.hasPotion
                    if not PlayerHasInkyBlackness() and hasPotion then
                        local e = AcquireEntry()
                        e.mode = "item"; e.itemID = INKY_BLACK_ITEM
                        e.texture = GetItemIcon(INKY_BLACK_ITEM)
                        e.label = EllesmereUI.L(ShortLabel("Inky Black Potion"))
                        e.qualityAtlas = EABR.GetItemQualityAtlas(INKY_BLACK_ITEM)
                        e.bagCount = CachedGetItemCount(INKY_BLACK_ITEM)
                        e.cat = "consumable"
                        e.dismissKey = "consumable:inky_black"
                        missing[#missing+1] = e
                    end
                end
            end
        end
    end -- consumables block

    -- Earth Shield self-buff (383648), only with Elemental Orbit. NOT
    -- actually combat-safe despite being whitelisted in NON_SECRET_SPELL_IDS:
    -- confirmed in-game that GetPlayerAuraBySpellID(383648) returns nothing
    -- readable in combat even while the buff is genuinely active, so a
    -- reminder already up when combat starts would get stuck (neither the
    -- live read nor the pre-combat snapshot can clear it) until combat ends.
    -- Suppress in combat/keystone instead, same as its ls_ws_orbit/
    -- shield_basic siblings just above.
    if specialsActive and playerClass == "SHAMAN" and not (inCombat or inKeystone) then
        local esOrbit = SHAMAN_SHIELDS[1]  -- es_orbit entry
        if co.enabled[esOrbit.key] ~= false and Known(esOrbit.castSpell)
           and esOrbit.requireTalent and Known(esOrbit.requireTalent) then
            if not PlayerHasAuraByID(esOrbit.buffIDs) then
                local e = AcquireEntry()
                e.mode = "spell"; e.spellID = esOrbit.castSpell
                e.label = ShortLabel(esOrbit.name, "SHAMAN_SHIELD")
                e.cat = "consumable"; e.data = esOrbit
                e.dismissKey = "consumable:" .. esOrbit.key
                missing[#missing+1] = e
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Healthstone in bags (group; "Where to Show" governs visibility). Bag
    --  state and class scans are combat-safe; secret class tokens skip units.
    --  In combat only the warlock is reminded: a non-warlock can't be handed
    --  a stone mid-fight, so for everyone else it is noise until the fight
    --  ends (the list rebuilds on both combat transitions).
    ---------------------------------------------------------------------------
    if (IsInGroup() or IsInRaid()) and EABR.ConsumableShows(co, "healthstone", inInstance)
       and not (InCombat() and GetPlayerClass() ~= "WARLOCK") then
        if co and co.enabled and co.enabled.healthstone ~= false then
            -- Only remind if a Warlock is in the group
            local hasWarlock = false
            if IsInRaid() then
                for i = 1, GetNumGroupMembers() do
                    local _, cls = UnitClass("raid"..i)
                    if cls ~= nil and not isSecret(cls) and cls == "WARLOCK" then hasWarlock = true; break end
                end
            else
                if GetPlayerClass() == "WARLOCK" then
                    hasWarlock = true
                else
                    for i = 1, GetNumSubgroupMembers() do
                        local _, cls = UnitClass("party"..i)
                        if cls ~= nil and not isSecret(cls) and cls == "WARLOCK" then hasWarlock = true; break end
                    end
                end
            end
            local hasHealthstone = EABR._resolved.healthstone.hasStone
            if hasWarlock and not hasHealthstone then
                local e = AcquireEntry()
                e.mode = "texture"; e.texture = 538745
                e.label = EllesmereUI.L("HS")
                e.cat = "consumable"
                e.dismissKey = "consumable:healthstone"
                missing[#missing+1] = e
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Partnered Trinket: Emerald Coach's Whistle (combat-safe via snapshot)
    ---------------------------------------------------------------------------
    do
        local co2 = db.profile.consumables
        if co2 and co2.enabled and co2.enabled.coaches_whistle ~= false
           and EABR.ConsumableShows(co2, "coaches_whistle", inInstance) and _cachedDiffID ~= 208
           and (IsInGroup() or IsInRaid())
           and (GetInventoryItemID("player", 13) == 193718 or GetInventoryItemID("player", 14) == 193718) then
            local hasBuff = PlayerHasAuraByID(PARTNERED_TRINKET.buffIDs)
            if not hasBuff then
                local e = AcquireEntry()
                e.mode = "texture"; e.texture = PARTNERED_TRINKET.icon
                e.label = EllesmereUI.L("Whistle")
                e.cat = "consumable"
                e.dismissKey = "consumable:coaches_whistle"
                missing[#missing+1] = e
            end
        end
    end

    ---------------------------------------------------------------------------
    --  DK Runeforging (OOC only, check permanent enchant via item link)
    ---------------------------------------------------------------------------
    if not inCombat and playerClass == "DEATHKNIGHT" then
        local co3 = db.profile.consumables
        if co3 and co3.enabled and co3.enabled.runeforge ~= false then
            local needsRune = false
            for i = 1, 2 do
                local slot = (i == 1) and 16 or 17
                local link = GetInventoryItemLink("player", slot)
                if link then
                    local ench = link:match("item:%d+:(-?%d+):")
                    local enchID = tonumber(ench) or 0
                    if enchID == 0 then needsRune = true; break end
                end
            end
            if needsRune then
                local e = AcquireEntry()
                e.mode = "texture"; e.texture = 135957
                e.label = EllesmereUI.L("Rune")
                e.cat = "consumable"
                e.dismissKey = "consumable:runeforge"
                missing[#missing+1] = e
            end
        end
    end

end

-- CollectTalentReminders moved to EllesmereUIABR_TalentReminders.lua

-- Reusable tables wiped each Refresh() call to avoid per-call allocation (wrapped to save file-scope local slots, 200 limit).
local _refreshMissing = {}
local UpdateDurationTicker  -- forward-declare; defined after RequestRefresh

local function Refresh()
    _cachedOutline = nil
    EABR._nextDurationRefreshTime = nil
    if not db then return end
    -- Pooled reminder buttons are children of iconAnchor, built in OnEnable (PLAYER_LOGIN). File-scope events (SPELLS_CHANGED, PLAYER_TALENT_UPDATE,
    -- TRAIT_CONFIG_UPDATED, ...) can fire DURING loading before OnEnable runs; a reminder created then via GetOrCreateIcon gets a nil parent and renders oversized forever (scale 1.0, not UIParent scale -- pooled buttons are never re-parented). Wait for the anchor; OnEnable fires its own refresh.
    if not iconAnchor then return end
    if euiPanelOpen then HideCombatIcons(); HideAllIcons(); return end

    -- Hides all reminders while skyriding (mounted+flying) or in a vehicle; IsMounted/IsFlying/UnitInVehicle are combat-safe (no taint).
    if UnitInVehicle("player") or (IsMounted() and IsFlying()) then
        HideCombatIcons(); HideCursorIcons()
        if InCombat() then
            FadeOutSecureIcons()
        else
            HideAllIcons()
        end
        return
    end

    -- Suppresses while dead or in a rested area (city/inn) -- rested areas
    -- always stay hidden, independent of every "Where to Show" setting.
    if UnitIsDeadOrGhost("player") then
        HideCombatIcons(); HideCursorIcons(); HideAllIcons(); return
    end
    if IsResting() then
        HideCombatIcons(); HideCursorIcons()
        if InCombat() then FadeOutSecureIcons() else HideAllIcons() end
        return
    end

    CacheInstanceInfo()

    BuildPlayerAuraCache()

    local playerClass = GetPlayerClass()
    local inCombat = InCombat()

    -- Collect missing reminders (reuse pooled entry tables)
    ResetEntryPool()
    local missing = _refreshMissing
    wipe(missing)

    local remindersOn = db.profile.display.remindersEnabled ~= false

    -- Instance/spec state (all combat-safe reads) -- needed even in
    -- restricted contexts so the trackable subset can still be collected.
    -- "restricted" = aura reads are locked (combat or an active keystone);
    -- the collectors self-limit under it, and where reminders may appear is
    -- governed per-section by "Where to Show".
    local specID = GetSpecID()
    local inInstance = InRealInstancedContent()
    local inKeystone = InMythicPlusKey()
    local inPvP = InPvPInstance()
    local restricted = inCombat or inKeystone

    ---------------------------------------------------------------------------
    --  1) Raid Buffs (runs in and out of combat)
    ---------------------------------------------------------------------------
    if remindersOn then
        CollectRaidBuffs(missing, playerClass, inInstance, inCombat)
    end

    ---------------------------------------------------------------------------
    --  2) Auras: OOC normally; in restricted contexts only reminders whose
    --  detection survives the aura lock (stances/forms + whitelisted IDs).
    ---------------------------------------------------------------------------
    if remindersOn then
        CollectAuras(missing, playerClass, specID, inInstance, restricted)
    end

    ---------------------------------------------------------------------------
    --  3) Consumables: OOC (non-PvP) normally; in restricted contexts the
    --  trackable subset only. PvP stays fully suppressed.
    ---------------------------------------------------------------------------
    if remindersOn and not inPvP then
        CollectConsumables(missing, playerClass, specID, inInstance, inKeystone, inCombat)
    end

    ---------------------------------------------------------------------------
    --  4) Pet Reminders (combat-safe: UnitExists/UnitIsDead unrestricted); suppressed for petless specs, Grimoire of Sacrifice, etc.
    ---------------------------------------------------------------------------
    if remindersOn and PET_CLASSES[playerClass] then
        local co = db.profile.consumables
        if co and co.enabled and co.enabled.pet ~= false and EABR.SectionShows(co.specialsWhereToShow, inInstance) then
            local suppress = false
            local petIcon = 132161
            local petLabel = "Pet"
            if playerClass == "HUNTER" then
                local spec = GetSpecialization and GetSpecialization()
                if spec then
                    local sid = GetSpecializationInfo(spec)
                    if sid == 254 and not Known(1223323) then suppress = true end
                end
            elseif playerClass == "WARLOCK" then
                petIcon = 136218
                if Known(108503) and PlayerHasAuraByID({196099}) then suppress = true end
            elseif playerClass == "DEATHKNIGHT" then
                petIcon = 1100170
                petLabel = "Ghoul"
                if specID ~= 252 then suppress = true end
            elseif playerClass == "MAGE" then
                petIcon = 135862
                petLabel = "Water Elemental"
                if specID ~= 64 or not Known(31687) then suppress = true end
            end
            -- Skipped while mounted, and for a beat after dismounting: mounting auto-dismisses the pet and the server resummons it on dismount a moment after the mount display drops, so the reminder is never actionable there (summoning would dismount you anyway). IsMounted()/GetTime() are combat-safe.
            if not suppress and not IsMounted()
               and not (EABR._petRemountGrace and GetTime() < EABR._petRemountGrace)
               and not (UnitExists("pet") and not UnitIsDead("pet")) then
                local e = AcquireEntry()
                e.mode = "texture"
                e.texture = petIcon
                e.label = petLabel
                e.cat = "consumable"
                e.dismissKey = "consumable:pet"
                missing[#missing+1] = e
            end
            if not suppress and playerClass == "WARLOCK" and specID == 266
               and co.enabled.wrong_pet ~= false
               and UnitExists("pet") and not UnitIsDead("pet") then
                local _, familyID = UnitCreatureFamily("pet")
                local isFelguard = familyID and not (issecretvalue and issecretvalue(familyID)) and familyID == 29
                if not isFelguard then
                    local e = AcquireEntry()
                    e.mode = "texture"
                    e.texture = 136216
                    e.label = EllesmereUI.L("Felguard")
                    e.cat = "consumable"
                    e.dismissKey = "consumable:wrong_pet"
                    missing[#missing+1] = e
                end
            end
            -- Pet on Passive: warns when an active pet is set to Passive stance. Combat-safe (pet command state isn't secret); skipped while mounted (pet is auto-forced to Passive).
            if not suppress and co.enabled.pet_passive ~= false
               and UnitExists("pet") and not UnitIsDead("pet")
               and not IsMounted() then
                local passiveActive, passiveTex, passiveIsToken
                for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
                    local nm, tx, tok, active = GetPetActionInfo(i)
                    if nm == "PET_MODE_PASSIVE" then
                        if not isSecret(active) then passiveActive = (active == true) end
                        passiveTex, passiveIsToken = tx, tok
                        break
                    end
                end
                if passiveActive then
                    local e = AcquireEntry()
                    e.mode = "texture"
                    e.texture = (passiveIsToken and _G[passiveTex]) or passiveTex or petIcon
                    e.label = PET_MODE_PASSIVE or "Passive"
                    e.cat = "consumable"
                    e.dismissKey = "consumable:pet_passive"
                    missing[#missing+1] = e
                end
            end
        end
    end

    -- Talent reminders handled by EllesmereUIABR_TalentReminders.lua

    -- Per-section sound alerts: fire once as each reminder newly appears.
    EABR.HandleAppearSounds(missing)

    ---------------------------------------------------------------------------
    --  Apply results
    ---------------------------------------------------------------------------
    if inCombat then
        -- Combat path: visual-only icons for most reminders. The player's
        -- own raid buff routes to the pre-bound provider SecureActionButton
        -- so rebuffing stays clickable under lockdown -- unless cursor
        -- attach is on, where it rides the cursor as a visual icon instead
        -- (see the provider peel below).
        FadeOutSecureIcons()
        HideCombatIcons()
        HideCursorIcons()
        local providerEntry
        if #missing > 0 then
            local useCursor = db.profile.display.cursorAttach and cursorAnchor
            local combatIdx, cursorIdx = 0, 0
            for _, m in ipairs(missing) do
                -- Skip middle-click dismissed reminders. The collectors are
                -- the restriction gate now (each emits only what its combat
                -- detection can verify), so no whitelist re-filter here.
                local dk = m.dismissKey or (m.data and m.data.key and (m.cat .. ":" .. m.data.key)) or nil
                if not (dk and _dismissedUntilLoad[dk]) then
                    -- With cursor attach ON the provider reminder rides the
                    -- cursor instead of the secure button (a cursor-chasing
                    -- icon could never be clicked anyway, and a protected
                    -- frame could not chase the cursor in combat at all).
                    -- Peel to the secure button ONLY while it holds its combat
                    -- slot (visible at pull, or shown earlier this combat). A
                    -- button that entered combat PARKED sits at -10000 and its
                    -- SetPoint is lockdown-protected, so a mid-combat first
                    -- show there is invisible (die -> combat res -> own buff
                    -- missing was the field case); fall through to a normal
                    -- pooled icon instead -- visual-only, like every other
                    -- combat entry. The button resumes ownership at the OOC
                    -- refresh.
                    if m.cat == "raidbuff" and m.mode == "spell" and not useCursor
                       and (EABR._providerCastVisible or EABR._providerCastCombatReserved) then
                        providerEntry = m
                    else
                        local f
                        if useCursor and IsImportantBuff(m) then
                            cursorIdx = cursorIdx + 1
                            ShowCursorIcon(cursorIdx, m)
                            f = cursorActiveIcons[#cursorActiveIcons]
                        else
                            combatIdx = combatIdx + 1
                            ShowCombatIcon(combatIdx, m)
                            f = combatActiveIcons[#combatActiveIcons]
                        end
                        if f and not m.isEating then
                            RemoveGlow(f)
                            local p = db.profile.display
                            local gr, gg, gb = ResolveGlowTint(p)
                            local baseScale = p.scale or 1.0
                            local sz = floor(ICON_SIZE * baseScale + 0.5)
                            ApplyGlow(f, p.glowType or 0, gr, gg, gb, sz)
                        end
                    end
                end
            end
            if providerEntry then
                EABR.SetProviderCastCombatVisible(true, providerEntry)
                local pBtn = EABR._providerCastBtn
                if pBtn then
                    local p = db.profile.display
                    local gr, gg, gb = ResolveGlowTint(p)
                    local sz = pBtn:GetWidth() or ICON_SIZE
                    if pBtn._eabrGlowWrapper then pBtn._eabrGlowWrapper:Hide() end
                    ApplyGlow(pBtn, p.glowType or 0, gr, gg, gb, sz)
                end
            end
            if (combatIdx > 0 or providerEntry) and combatAnchor then
                combatAnchor:Show()
                EllesmereUI.SetElementVisibility(combatAnchor, true)
                LayoutCombatIcons()
            end
            if cursorIdx > 0 and cursorAnchor then
                cursorAnchor:Show()
                EllesmereUI.SetElementVisibility(cursorAnchor, true)
                LayoutCursorIcons()
            end
        end
        return
    end

    -- OOC path: full secure button display
    EABR.SyncProviderCastSpell()
    HideCombatIcons()
    HideCursorIcons()
    HideAllIcons()

    if #missing > 0 then
        -- Cursor attach applies OOC too. Cursor icons are visual-only: an
        -- important buff routed here trades its secure click-to-cast for
        -- at-cursor placement, same as in combat -- no loss, since an icon
        -- chasing the cursor can never be clicked anyway. With cursor attach
        -- ON the player's own raid buff is the main case: it rides the
        -- cursor and the provider secure button parks; with it OFF the
        -- provider button keeps sole ownership as before.
        local useCursor = db.profile.display.cursorAttach and cursorAnchor
        local iconIdx, cursorIdx = 0, 0
        local providerEntry
        for _, m in ipairs(missing) do
            local dk = m.dismissKey or (m.data and m.data.key and (m.cat .. ":" .. m.data.key)) or nil
            if not dk or not _dismissedUntilLoad[dk] then
                if m.cat == "raidbuff" and m.mode == "spell" and not useCursor then
                    providerEntry = m
                elseif useCursor and IsImportantBuff(m) then
                    cursorIdx = cursorIdx + 1
                    ShowCursorIcon(cursorIdx, m)
                    local f = cursorActiveIcons[#cursorActiveIcons]
                    if f and not m.isEating then
                        RemoveGlow(f)
                        local p = db.profile.display
                        local gr, gg, gb = ResolveGlowTint(p)
                        local baseScale = p.scale or 1.0
                        local sz = floor(ICON_SIZE * baseScale + 0.5)
                        ApplyGlow(f, p.glowType or 0, gr, gg, gb, sz)
                    end
                else
                    iconIdx = iconIdx + 1
                    ShowIcon(iconIdx, m)
                end
            end
        end
        if providerEntry then
            EABR.SetProviderCastCombatVisible(true, providerEntry)
            local pBtn = EABR._providerCastBtn
            if pBtn then
                local p = db.profile.display
                local gr, gg, gb = ResolveGlowTint(p)
                local sz = pBtn:GetWidth() or ICON_SIZE
                if pBtn._eabrGlowWrapper then pBtn._eabrGlowWrapper:Hide() end
                ApplyGlow(pBtn, p.glowType or 0, gr, gg, gb, sz)
            end
        else
            EABR.ParkProviderCastButton()
        end
        if cursorIdx > 0 then
            cursorAnchor:Show()
            EllesmereUI.SetElementVisibility(cursorAnchor, true)
            LayoutCursorIcons()
        end
        if iconIdx > 0 or providerEntry then
            LayoutIcons()
            EllesmereUI.SetElementVisibility(iconAnchor, true)
        else
            EllesmereUI.SetElementVisibility(iconAnchor, false)
        end
    else
        EABR.ParkProviderCastButton()
        EllesmereUI.SetElementVisibility(iconAnchor, false)
    end

    UpdateDurationTicker()
end

local REFRESH_THROTTLE_COMBAT = 0.5
local REFRESH_THROTTLE_OOC    = 0.5
local _lastRefreshTime = 0
local _refreshTimerActive = false
local function _doRefresh()
    _refreshTimerActive = false
    refreshQueued = false
    _lastRefreshTime = GetTime()
    Refresh()
end
local function RequestRefresh()
    if refreshQueued then return end
    refreshQueued = true
    local throttle = InCombat() and REFRESH_THROTTLE_COMBAT or REFRESH_THROTTLE_OOC
    local elapsed = GetTime() - _lastRefreshTime
    if elapsed >= throttle then
        C_Timer.After(0, _doRefresh)
    elseif not _refreshTimerActive then
        _refreshTimerActive = true
        C_Timer.After(throttle - elapsed, _doRefresh)
    end
end

-- Duration-threshold timer: arms one refresh for the next known buff/enchant threshold crossing instead of polling while idle.
UpdateDurationTicker = function()
    if EABR._durationTimer then
        EABR._durationTimer:Cancel()
        EABR._durationTimer = nil
    end

    if not (EABR._nextDurationRefreshTime and db and EABR.ShowUnderThresholdApplies()) then
        return
    end

    local delay = EABR._nextDurationRefreshTime - GetTime() + 0.1
    if delay < 0.1 then delay = 0.1 end

    EABR._durationTimer = C_Timer.NewTimer(delay, function()
        EABR._durationTimer = nil
        if not EABR.ShowUnderThresholdApplies() then return end
        RequestRefresh()
    end)
end


-------------------------------------------------------------------------------
--  Unlock Mode
-------------------------------------------------------------------------------
local function ApplyUnlockPos()
    if not iconAnchor or not db then return end
    -- Skip for unlock-anchored elements (anchor system is authority)
    local anchored = EllesmereUI and EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("EABR_Reminders")
    if anchored and iconAnchor:GetLeft() then return end
    local pos = db.profile.unlockPos
    if pos and pos.point then
        local px, py = pos.x or 0, pos.y or 0
        local PPa = EllesmereUI and EllesmereUI.PP
        if PPa then
            local es = iconAnchor:GetEffectiveScale()
            -- For CENTER anchor, uses SnapCenterForDim with the frame's actual size so odd-pixel-dim frames get the +0.5 offset that places edges on whole pixels.
            local isCenterAnchor = (pos.point == "CENTER")
                and (pos.relPoint == "CENTER" or pos.relPoint == nil)
            if isCenterAnchor and PPa.SnapCenterForDim then
                px = PPa.SnapCenterForDim(px, iconAnchor:GetWidth() or 0, es)
                py = PPa.SnapCenterForDim(py, iconAnchor:GetHeight() or 0, es)
            elseif PPa.SnapForES then
                px = PPa.SnapForES(px, es)
                py = PPa.SnapForES(py, es)
            end
        end
        iconAnchor:ClearAllPoints()
        iconAnchor:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, px, py)
    else
        -- No saved position: centers the row on screen (+ configured offset). A CENTER anchor keeps the row's center fixed as icon count changes, same as above; LayoutIcons centers the row on this anchor and owns its size.
        local d = db.profile.display
        iconAnchor:ClearAllPoints()
        iconAnchor:SetPoint("CENTER", UIParent, "CENTER", d.xOffset or 0, d.yOffset or 0)
    end
end

local function RegisterUnlockElements()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement
    EllesmereUI:RegisterUnlockElements({
        MK({
            key = "EABR_Reminders",
            label = "AuraBuff Reminders",
            group = "AuraBuff Reminders",
            order = 600,
            noAnchorTarget = true,  -- icon count changes dynamically with auras
            -- Icon size is driven solely by the Scale slider. No drag-resize: row width is count-dependent, so restoring a stored width under a different count would corrupt the persisted scale (matches External Defensives).
            noResize = true,
            getFrame = function() return iconAnchor end,
            getSize = function()
                local p = db.profile.display
                local baseScale = p.scale or 1.0
                local sz = floor(ICON_SIZE * baseScale + 0.5)
                local spacing = p.iconSpacing or 8
                -- Fits all active icons (same set LayoutIcons places: reminders + merged beacon icons unless cursor-routed); falls back to a 2-wide grabbable box when empty so the mover overlay stays draggable.
                local count = #activeIcons
                local beaconsOnCursor = p.cursorAttach and cursorAnchor
                if _B.icons and not beaconsOnCursor then
                    for _, id in ipairs(_B.ALL or {}) do
                        if _B.iconState and _B.iconState[id] and _B.icons[id] then count = count + 1 end
                    end
                end
                if count < 1 then count = 2 end
                local w = count * sz + (count - 1) * spacing
                local textH = 0
                if p.showText then
                    textH = (p.textSize or 11) + abs(p.textYOffset or -2)
                end
                local h = sz + textH
                -- Resizes the anchor for the overlay; iconAnchor is CENTER-anchored and icons hang off its CENTER, so this never moves them.
                if iconAnchor then ResizeAnchorCentered(w, h) end
                return w, h
            end,
            savePos = function(key, point, relPoint, x, y)
                db.profile.unlockPos = {point=point, relPoint=relPoint, x=x, y=y}
                if not EllesmereUI._unlockActive then
                    ApplyUnlockPos()
                end
            end,
            loadPos = function()
                return db.profile.unlockPos
            end,
            clearPos = function()
                db.profile.unlockPos = nil
            end,
            applyPos = function()
                ApplyUnlockPos()
            end,
        }),
    })
end

-------------------------------------------------------------------------------
--  Last-Used Item Tracking (per-character)
-------------------------------------------------------------------------------
local TrackItemUse
do
    local flaskSet, foodSet, weSet = {}, {}, {}
    for _, f in ipairs(FLASK_ITEMS) do
        for _, id in ipairs(f.items) do flaskSet[id] = true end
    end
    for _, f in ipairs(FOOD_ITEMS) do foodSet[f.itemID] = true end
    for _, we in ipairs(WEAPON_ENCHANT_ITEMS) do weSet[we.itemID] = true end
    TrackItemUse = function(itemID)
        if not db or not db.profile then return end
        -- All persistent use-tracking lives in db.profile (this DB layer has no `char` namespace).
        if flaskSet[itemID] then db.profile.lastUsedFlask = itemID
        elseif foodSet[itemID] then db.profile.lastUsedFood = itemID
        elseif weSet[itemID] then db.profile.lastUsedWeaponEnchant = itemID end
    end
end

-------------------------------------------------------------------------------
--  Standalone Beacon Reminders -- IsSpellOverlayed-based, combat-safe, independent from the main aura/buff system.
-------------------------------------------------------------------------------
_B.frame = CreateFrame("Frame")
_B.isPaladin = false
_B.overlayRegistered = false
_B.anchor = nil
_B.icons = {}
_B.iconState = {}
_B.glowState = {}
_B.cachedInInstance = false
_B.refreshPending = false
_B.BOL = 53563
_B.BOF = 156910
_B.VIRTUE = 200025
_B.ALL = { _B.BOL, _B.BOF }
local IsSpellOverlayed = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) or IsSpellOverlayed

local function BeaconUpdateInstanceCache()
    local _, instanceType, difficultyID = GetInstanceInfo()
    difficultyID = tonumber(difficultyID) or 0
    -- PvP instances (arenas/BGs) have difficultyID 0 but are still valid
    if instanceType == "pvp" or instanceType == "arena" then
        _B.cachedInInstance = true; return
    end
    if difficultyID == 0 then _B.cachedInInstance = false; return end
    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then
        _B.cachedInInstance = false; return
    end
    _B.cachedInInstance = (instanceType == "party" or instanceType == "raid" or (instanceType == "scenario" and difficultyID == 208))
end

local function BeaconUpdateOverlayEvents()
    if _B.cachedInInstance and _B.isPaladin then
        if not _B.overlayRegistered then
            _B.frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
            _B.frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
            _B.overlayRegistered = true
        end
    else
        if _B.overlayRegistered then
            _B.frame:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
            _B.frame:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
            _B.overlayRegistered = false
        end
    end
end

local function BeaconMakeIcon(spellID)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(120)
    f:Hide()
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(Tex(spellID))
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f._icon = icon
    f._spellID = spellID
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then PP.CreateBorder(f, 0, 0, 0, 1, 1, "OVERLAY", 7) end
    local text = EABR.GetIconTextOverlay(f):CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    SetABRFont(text, ResolveFontPath(), 11)
    text:SetTextColor(1, 1, 1, 1)
    f._text = text
    return f
end

local function BeaconLayoutIcons()
    -- Beacon icons are merged into the main LayoutIcons row; the separate beacon anchor is hidden (unused).
    if _B.anchor then EllesmereUI.SetElementVisibility(_B.anchor, false) end

    -- When cursor-attached, position beacon icons at the cursor anchor
    local useCursor = db and db.profile.display.cursorAttach and cursorAnchor
    if useCursor then
        local visIcons = {}
        for _, id in ipairs(_B.ALL or {}) do
            if _B.iconState and _B.iconState[id] and _B.icons[id] then
                visIcons[#visIcons + 1] = _B.icons[id]
            end
        end
        if #visIcons > 0 then
            local p = db.profile.display
            local spacing = p.iconSpacing or 8
            local baseScale = p.scale or 1.0
            local sz = floor(ICON_SIZE * baseScale + 0.5)
            local totalW = (#visIcons * sz) + ((#visIcons - 1) * spacing)
            local startX = -(totalW / 2) + (sz / 2)
            for i, f in ipairs(visIcons) do
                f:SetSize(sz, sz)
                f:SetAlpha(p.opacity or 1.0)
                f:SetFrameStrata("TOOLTIP")
                f:SetFrameLevel(9980)
                f:ClearAllPoints()
                f:SetPoint("CENTER", cursorAnchor, "CENTER", startX + (i - 1) * (sz + spacing), -(sz + 8))
            end
            cursorAnchor:Show()
            EllesmereUI.SetElementVisibility(cursorAnchor, true)
        end
        return
    end

    -- Restore beacon icons to normal strata after leaving cursor mode
    for _, id in ipairs(_B.ALL or {}) do
        if _B.icons and _B.icons[id] then
            _B.icons[id]:SetFrameStrata("HIGH")
            _B.icons[id]:SetFrameLevel(120)
        end
    end
    -- Re-layout main icons to include/exclude beacon icons
    LayoutIcons()
end

local function BeaconApplyGlow(f, show)
    if show then
        local p = db and db.profile.display
        local glowType = p and p.glowType or 0
        if glowType > 0 then
            local gr, gg, gb = ResolveGlowTint(p)
            local baseScale = p and p.scale or 1.0
            local sz = floor(ICON_SIZE * baseScale + 0.5)
            ApplyGlow(f, glowType, gr, gg, gb, sz)
        end
        _B.glowState[f._spellID] = true
    else
        if _B.glowState[f._spellID] then
            RemoveGlow(f)
            _B.glowState[f._spellID] = false
        end
    end
end

local function BeaconApplyText(f)
    local p = db and db.profile.display
    if p and p.showText then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        local fontPath = ResolveFontPath(p.textFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        SetABRFont(f._text, fontPath, textSize)
        f._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(p)
        f._text:SetPoint(tp, f, ip, xOff, yOff)
        f._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        f._text:SetText(ShortLabel(f._spellID == _B.BOL and "Beacon of Light" or "Beacon of Faith"))
        f._text:Show()
    else
        f._text:SetText("")
        f._text:Hide()
    end
end

local function BeaconSetVisible(spellID, show)
    local f = _B.icons[spellID]
    if not f then return end
    local changed = false
    if show then
        if not _B.iconState[spellID] then
            BeaconApplyText(f)
            f:Show()
            _B.iconState[spellID] = true
            BeaconApplyGlow(f, true)
            changed = true
        end
    else
        if _B.iconState[spellID] then
            BeaconApplyGlow(f, false)
            f._text:SetText("")
            f:Hide()
            _B.iconState[spellID] = false
            changed = true
        end
    end
    if changed then BeaconLayoutIcons() end
end

local function BeaconRefresh()
    if not _B.isPaladin then return end
    if euiPanelOpen or not IsSpellOverlayed then
        BeaconSetVisible(_B.BOL, false)
        BeaconSetVisible(_B.BOF, false)
        return
    end
    if UnitInVehicle("player") or (IsMounted() and IsFlying()) then
        BeaconSetVisible(_B.BOL, false)
        BeaconSetVisible(_B.BOF, false)
        return
    end
    if not _B.cachedInInstance or not (IsInGroup() or IsInRaid()) then
        BeaconSetVisible(_B.BOL, false)
        BeaconSetVisible(_B.BOF, false)
        return
    end

    local au = db and db.profile.auras
    local enabled = au and au.enabled

    local trackBOL = enabled and enabled.bol ~= false
                     and Known(_B.BOL) and not Known(_B.VIRTUE)
    local trackBOF = enabled and enabled.bof ~= false
                     and Known(_B.BOF)

    BeaconSetVisible(_B.BOL, trackBOL and IsSpellOverlayed(_B.BOL))
    BeaconSetVisible(_B.BOF, trackBOF and IsSpellOverlayed(_B.BOF))
end

local function BeaconRefreshSoon()
    if _B.refreshPending then return end
    _B.refreshPending = true
    C_Timer.After(0, function()
        _B.refreshPending = false
        BeaconRefresh()
    end)
end

local function BeaconInit()
    local _, classFile = UnitClass("player")
    _B.isPaladin = (classFile == "PALADIN")
    if not _B.isPaladin then return end

    _B.icons[_B.BOL] = BeaconMakeIcon(_B.BOL)
    _B.icons[_B.BOF] = BeaconMakeIcon(_B.BOF)

    _B.anchor = CreateFrame("Frame", "EABR_BeaconAnchor", UIParent)
    _B.anchor:SetSize(1, 1)
    _B.anchor:SetFrameStrata("HIGH")
    _B.anchor:EnableMouse(false)
    _B.anchor:Show()
    EllesmereUI.SetElementVisibility(_B.anchor, false)
    -- Anchor to the combat anchor (created by OnEnable before this call)
    if combatAnchor then
        _B.anchor:SetPoint("CENTER", combatAnchor, "CENTER", 0, -60)
    else
        _B.anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end

    BeaconUpdateInstanceCache()
    BeaconUpdateOverlayEvents()
    BeaconRefresh()
end

-- Expose for options and anchor positioning
_G._EABR_BeaconRefresh = BeaconRefresh
_G._EABR_BeaconAnchor = function() return _B.anchor end

_B.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
_B.frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
_B.frame:RegisterEvent("SPELLS_CHANGED")
_B.frame:RegisterEvent("PLAYER_TALENT_UPDATE")
_B.frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
_B.frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
_B.frame:RegisterEvent("GROUP_ROSTER_UPDATE")
_B.frame:RegisterEvent("PLAYER_LEVEL_CHANGED")
_B.frame:SetScript("OnEvent", function(_, e, id)
    if not _B.isPaladin then return end
    if e == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or e == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if id == _B.BOL or id == _B.BOF then
            BeaconRefresh()
        end
        return
    end
    if e == "PLAYER_ENTERING_WORLD" or e == "ZONE_CHANGED_NEW_AREA" or e == "GROUP_ROSTER_UPDATE" then
        BeaconUpdateInstanceCache()
        BeaconUpdateOverlayEvents()
    end
    if e == "TRAIT_CONFIG_UPDATED" or e == "PLAYER_TALENT_UPDATE"
       or e == "SPELLS_CHANGED" or e == "PLAYER_SPECIALIZATION_CHANGED"
       or e == "PLAYER_LEVEL_CHANGED" then
        -- Invalidates cached spell textures for beacon spells so dynamic icon changes (e.g. BOL morphing to Virtue) pick up the new icon.
        if texCache then
            texCache[_B.BOL] = nil
            texCache[_B.BOF] = nil
        end
        for _, sid in ipairs(_B.ALL) do
            local f = _B.icons[sid]
            if f and f._icon then
                local t = Tex(sid)
                if t then f._icon:SetTexture(t) end
            end
        end
        BeaconRefreshSoon()
        return
    end
    BeaconRefresh()
end)

-------------------------------------------------------------------------------
--  MAIN EVENT FRAME (forward-declared so OnEnable can reference it)
-------------------------------------------------------------------------------
local mainFrame = CreateFrame("Frame")

-- Toggles broad vs player-only UNIT_AURA registration; file-scope so OnEnable and the event handler can both use it.
local function _setBroad(on)
    if on and not _groupAuraBroadActive then
        mainFrame:RegisterEvent("UNIT_AURA")
        _groupAuraBroadActive = true
    elseif not on and _groupAuraBroadActive then
        mainFrame:UnregisterEvent("UNIT_AURA")
        mainFrame:RegisterUnitEvent("UNIT_AURA", "player")
        _groupAuraBroadActive = false
    end
end

-------------------------------------------------------------------------------
--  Lifecycle: OnInitialize (fires at ADDON_LOADED time). Creates the DB early so EABR is in _dbRegistry before PreSeedSpecProfile.
-------------------------------------------------------------------------------
function EABR:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUIAuraBuffRemindersDB", defaults, true)

    ---------------------------------------------------------------------------
    --  Legacy visibility-model migration. Keyed off LEGACY field presence
    --  (the DB layer has already merged the new defaults, so nil checks on
    --  the new keys cannot detect an old profile); fresh installs carry no
    --  legacy keys and every block no-ops.
    ---------------------------------------------------------------------------
    local p = db.profile
    local co = p and p.consumables
    -- Old single Augment Rune dropdown -> the dormant per-item "Show In"
    -- tier set (kept for the future per-item conditions cog).
    if co and co.runeDisplayMode ~= nil then
        co.showIn = co.showIn or {}
        co.showIn.augment_rune = co.runeDisplayMode
        co.runeDisplayMode = nil
    end
    -- Old tiered "Show In" strings -> per-difficulty override sets. Absent
    -- category = on, so only unchecked difficulties store false ("all" =
    -- cleared entirely).
    if co and co.showIn then
        local function tierToSet(tier)
            if tier == "heroic_mythic" then
                return { d_normal=false, r_normal=false, r_lfr=false }
            elseif tier == "mythic" then
                return { d_normal=false, d_heroic=false, r_lfr=false, r_normal=false, r_heroic=false }
            end
            return nil  -- "all" or unknown => every difficulty on
        end
        for k, v in pairs(co.showIn) do
            if type(v) == "string" then
                co.showIn[k] = tierToSet(v)
            end
        end
    end
    -- Per-spell/open-world/others-missing model -> per-section "Where to
    -- Show" + "Show When". Open-world masters map to the open_world bucket;
    -- everything else is retired.
    local rb = p and p.raidBuffs
    if rb and (rb.showOthersMissing ~= nil or rb.showNonInstanced ~= nil) then
        rb.showWhen = { othersMissing = (rb.showOthersMissing ~= false), iAmMissing = false }
        rb.whereToShow = { open_world = (rb.showNonInstanced == true) }
        rb.showOthersMissing, rb.showNonInstanced = nil, nil
    end
    local au = p and p.auras
    if au and au.showNonInstanced ~= nil then
        au.whereToShow = { open_world = (au.showNonInstanced ~= false) }
        au.showNonInstanced = nil
    end
    if co and co.showSpecialsNonInstanced ~= nil then
        co.specialsWhereToShow = { open_world = (co.showSpecialsNonInstanced ~= false) }
        co.showSpecialsNonInstanced = nil
    end
    -- Old party/raid consumable thresholds -> the global timing pair.
    local disp = p and p.display
    if disp then
        if disp.showUnderDurationDungeon ~= nil or disp.showUnderDurationRaid ~= nil then
            if disp.showUnder == nil then disp.showUnder = disp.showUnderDurationRaid or 5 end
            if disp.showUnderMPlus == nil then disp.showUnderMPlus = disp.showUnderDurationDungeon or 40 end
            disp.showUnderDurationDungeon = nil
            disp.showUnderDurationRaid = nil
        end
        if disp.showUnder == nil then disp.showUnder = 5 end
        if disp.showUnderMPlus == nil then disp.showUnderMPlus = 40 end
    end
    -- Retired per-section scale keys (display scale is the one knob).
    if rb then rb.scale = nil end
    if au then au.scale = nil end
    if co then co.scale = nil end

    -- Migrates the login-active profile eagerly; profiles activated later are covered by the read-path call in ResolveGlowTint.
    EnsureGlowModeMigrated(db.profile.display)
end

-------------------------------------------------------------------------------
--  Lifecycle: OnEnable (fires at PLAYER_LOGIN time, after PreSeedSpecProfile). All UI creation and event wiring that depends on db being ready.
-------------------------------------------------------------------------------
function EABR:OnEnable()
    -- Expose globals for options
    _G._EABR_AceDB = db

    -- Talent reminder migration handled by EllesmereUIABR_TalentReminders.lua

    _G._EABR_RequestRefresh = RequestRefresh
    _G._EABR_HideAllIcons = HideAllIcons
    _G._EABR_GLOW_VALUES = GLOW_VALUES
    _G._EABR_GLOW_ORDER = GLOW_ORDER
    _G._EABR_GLOW_TYPES = GLOW_TYPES
    _G._EABR_StartPixelGlow = StartPixelGlow
    _G._EABR_StartButtonGlow = StartButtonGlow
    _G._EABR_StartAutoCastShine = StartAutoCastShine
    _G._EABR_StartFlipBookGlow = StartFlipBookGlow
    _G._EABR_StopAllGlows = StopAllGlows
    _G._EABR_ResolveGlowTint = ResolveGlowTint
    _G._EABR_EnsureGlowModeMigrated = EnsureGlowModeMigrated
    _G._EABR_RegisterUnlock = RegisterUnlockElements
    _G._EABR_ApplyUnlockPos = ApplyUnlockPos
    _G._EABR_RAID_BUFFS = RAID_BUFFS
    _G._EABR_AURAS = AURAS
    _G._EABR_ROGUE_POISONS = ROGUE_POISONS
    _G._EABR_PALADIN_RITES = PALADIN_RITES
    _G._EABR_SHAMAN_IMBUES = SHAMAN_IMBUES
    _G._EABR_SHAMAN_SHIELDS = SHAMAN_SHIELDS
    _G._EABR_WEAPON_ENCHANT_ITEMS = WEAPON_ENCHANT_ITEMS
    _G._EABR_Tex = Tex
    _G._EABR_ICON_SIZE = ICON_SIZE
    _G._EABR_FLASK_ITEMS = FLASK_ITEMS
    _G._EABR_FOOD_ITEMS = FOOD_ITEMS
    _G._EABR_WEAPON_ENCHANT_CHOICES = WEAPON_ENCHANT_CHOICES
    -- _EABR_TALENT_REMINDER_ZONES set by EllesmereUIABR_TalentReminders.lua

    local STRATA_VALUES = EllesmereUI.FRAME_STRATA_LABELS
    local STRATA_ORDER = EllesmereUI.FRAME_STRATA_ORDER_FULL
    _G._EABR_STRATA_VALUES = STRATA_VALUES
    _G._EABR_STRATA_ORDER = STRATA_ORDER

    iconAnchor = CreateFrame("Frame", "EABR_Anchor", UIParent)
    iconAnchor:SetSize(1, 1)
    iconAnchor:SetFrameStrata(GetStrata())
    iconAnchor:EnableMouse(false)
    ApplyUnlockPos()

    -- Combat anchor: non-secure, follows iconAnchor position; parented to UIParent so Show/Hide is never blocked by combat lockdown.
    combatAnchor = CreateFrame("Frame", "EABR_CombatAnchor", UIParent)
    combatAnchor:SetSize(1, 1)
    combatAnchor:SetFrameStrata(GetStrata())
    combatAnchor:SetFrameLevel(110)
    combatAnchor:EnableMouse(false)
    combatAnchor:SetAllPoints(iconAnchor)
    combatAnchor:Show()
    EllesmereUI.SetElementVisibility(combatAnchor, false)

    -- Cursor anchor: tracks cursor position via OnUpdate (same as CDM).
    cursorAnchor = CreateFrame("Frame", "EABR_CursorAnchor", UIParent)
    cursorAnchor:SetSize(1, 1)
    cursorAnchor:SetFrameStrata("TOOLTIP")
    cursorAnchor:SetFrameLevel(9980)
    cursorAnchor:EnableMouse(false)
    cursorAnchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    do
        -- Cursor glue on the suite's shared cursor service (Tier A motionOnly: fires per render frame while the cursor MOVES, parked at rest). Subscription follows the frame's own OnShow/OnHide; OnShow snaps once via M.Get() so a cursor that moved while hidden never shows stale.
        local lastMX, lastMY
        local function GlueBody(rawX, rawY)
            local s = UIParent:GetEffectiveScale()
            local cx = floor(rawX / s + 0.5)
            local cy = floor(rawY / s + 0.5)
            if cx ~= lastMX or cy ~= lastMY then
                lastMX, lastMY = cx, cy
                cursorAnchor:ClearAllPoints()
                cursorAnchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy + 60)
            end
        end
        cursorAnchor:SetScript("OnShow", function()
            local M = EllesmereUI.Mouse
            if M then
                GlueBody(M.Get())
                M.SubscribeFrame("abrCursor", GlueBody, true)
            end
        end)
        cursorAnchor:SetScript("OnHide", function()
            local M = EllesmereUI.Mouse
            if M then M.UnsubscribeFrame("abrCursor") end
        end)
    end
    -- Starts hidden: OnUpdate only runs while :IsShown(), saving CPU when no cursor-attached reminders are active.
    cursorAnchor:Hide()
    EllesmereUI.SetElementVisibility(cursorAnchor, false)

    -- Talent reminder anchor created by EllesmereUIABR_TalentReminders.lua (independent of iconAnchor so parent alpha doesn't hide it).

    local function ApplyStrata()
        local strata = GetStrata()
        iconAnchor:SetFrameStrata(strata)
        combatAnchor:SetFrameStrata(strata)
        for _, btn in pairs(iconPool) do btn:SetFrameStrata(strata) end
        for _, f in pairs(combatIconPool) do f:SetFrameStrata(strata) end
        if EABR._providerCastBtn and not InCombatLockdown() then
            EABR._providerCastBtn:SetFrameStrata(strata)
        end
    end
    _G._EABR_ApplyStrata = ApplyStrata

    -- Hook EUI panel show/hide
    if EllesmereUI then
        if EllesmereUI.RegisterOnShow then
            EllesmereUI:RegisterOnShow(function()
                euiPanelOpen = true; HideAllIcons(); BeaconRefresh()
            end)
        end
        if EllesmereUI.RegisterOnHide then
            EllesmereUI:RegisterOnHide(function()
                euiPanelOpen = false; RequestRefresh(); BeaconRefresh()
            end)
        end
    end

    -- Group spec intel over addon comms (LibSpecialization): the lib
    -- handles all transmission itself (request on group join, broadcast on
    -- spec change, chat-lockdown deferral); we only consume its callback.
    -- Never call its request functions -- registration is the whole
    -- integration. Cache writes fire one coalesced refresh on CHANGE only,
    -- so the join burst (one callback per responding member) costs table
    -- writes plus a single refresh.
    do
        local LS = LibStub and LibStub("LibSpecialization", true)
        if LS then
            LS.RegisterGroup(EABR, function(specID, _, _, playerName)
                if type(specID) == "number" and type(playerName) == "string" then
                    if EABR._groupSpecs[playerName] ~= specID then
                        EABR._groupSpecs[playerName] = specID
                        RequestRefresh()
                    end
                end
            end)
        end
    end

    EABR.ScanEatingState()
    EABR.SyncProviderCastSpell()
    RequestRefresh()
    BeaconInit()
    C_Timer.After(0.5, RegisterUnlockElements)

    -- Registers broad UNIT_AURA only when the class needs group aura tracking AND only OOC: it fires 100+/sec in a raid, but in-combat CollectRaidBuffs only checks the player's own auras (PlayerHasAuraByID), so group events are pure waste. Evoker keeps broad in combat for ownOnRaid cache updates but skips RequestRefresh on group events (handler below).
    local function UpdateGroupAuraRegistration()
        local playerClass = GetPlayerClass()
        _needGroupAura = false
        _isEvokerOwnOnRaid = false
        for _, buff in ipairs(RAID_BUFFS) do
            if buff.class == playerClass then _needGroupAura = true; break end
        end
        for _, aura in ipairs(AURAS) do
            if aura.class == playerClass and aura.check == "ownOnRaid" then
                _needGroupAura = true
                _isEvokerOwnOnRaid = true
                break
            end
        end
        if _needGroupAura then
            mainFrame:RegisterEvent("GROUP_JOINED")
            mainFrame:RegisterEvent("GROUP_LEFT")
            -- Start broad if OOC, player-only if in combat (Evoker excepted)
            if InCombat() and not _isEvokerOwnOnRaid then
                _setBroad(false)
            else
                _setBroad(true)
            end
        else
            _setBroad(false)
            mainFrame:UnregisterEvent("GROUP_JOINED")
            mainFrame:UnregisterEvent("GROUP_LEFT")
        end
    end
    _G._EABR_UpdateGroupAuraRegistration = UpdateGroupAuraRegistration
    UpdateGroupAuraRegistration()

    -- Register spellcast tracking for Hunters (combat reminder for Hunter's Mark)
    if GetPlayerClass() == "HUNTER" then
        mainFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    end

    ---------------------------------------------------------------------------
    --  Range updates: UNIT_IN_RANGE_UPDATE mirrors the raid frames' range path, so range changes retrigger group-buff evaluation without polling.
    ---------------------------------------------------------------------------
    local _lastRangeSet = {}   -- [unitToken] = true/false (last known in-range state)

    -- Pre-build unit token strings to avoid per-poll allocations
    local _raidTokens = {}
    local _partyTokens = {}
    for i = 1, 40 do _raidTokens[i] = "raid" .. i end
    for i = 1, 4 do _partyTokens[i] = "party" .. i end

    local rangeFrame = CreateFrame("Frame")
    local _rangeTrackers = {}
    local function _checkUnit(u)
        if not UnitExists(u) then
            if _lastRangeSet[u] ~= nil then
                _lastRangeSet[u] = nil
                return true
            end
            return false
        end
        local state = _unitInRange(u)
        if _lastRangeSet[u] ~= state then
            _lastRangeSet[u] = state
            return true
        end
        return false
    end

    local function _checkAllRangeUnits()
        local changed = false
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                if _checkUnit(_raidTokens[i]) then changed = true end
            end
        elseif IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do
                if _checkUnit(_partyTokens[i]) then changed = true end
            end
        end
        return changed
    end

    local function _onRangeEvent(_, event, unit)
        if event == "UNIT_PHASE" then
            if _checkAllRangeUnits() then RequestRefresh() end
        elseif unit and _checkUnit(unit) then
            RequestRefresh()
        end
    end

    local function _clearRangeTrackers()
        for _, tracker in pairs(_rangeTrackers) do
            tracker:UnregisterAllEvents()
        end
    end

    local function _trackRangeUnit(unit)
        if UnitIsUnit(unit, "player") then return end
        local tracker = _rangeTrackers[unit]
        if not tracker then
            tracker = CreateFrame("Frame")
            tracker:SetScript("OnEvent", _onRangeEvent)
            _rangeTrackers[unit] = tracker
        end
        tracker:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", unit)
        tracker:RegisterUnitEvent("UNIT_CONNECTION", unit)
    end

    local function _rebuildRangeTracking()
        _clearRangeTrackers()
        wipe(_lastRangeSet)
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do _trackRangeUnit(_raidTokens[i]) end
        elseif IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do _trackRangeUnit(_partyTokens[i]) end
        end
        if _checkAllRangeUnits() then RequestRefresh() end
    end

    rangeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    rangeFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    rangeFrame:RegisterEvent("UNIT_PHASE")
    rangeFrame:SetScript("OnEvent", function(_, event)
        if event == "UNIT_PHASE" then
            _onRangeEvent(nil, event)
        else
            _rebuildRangeTracking()
        end
    end)
    _rebuildRangeTracking()
end

-------------------------------------------------------------------------------
--  MAIN EVENT HANDLER (OnEvent script for runtime events)
-------------------------------------------------------------------------------
mainFrame:SetScript("OnEvent", function(_, e, arg1, arg2, arg3)
    if e == "ENCOUNTER_START" then
        SnapshotPlayerAuras()
        if _isEvokerOwnOnRaid then SnapshotOwnOnRaidBuffs() end
        _encounterSnapshotTime = GetTime()
        -- Marks combat immediately: ENCOUNTER_START fires before InCombatLockdown() returns true but aura APIs are already restricted; without this, non-whitelisted buffs flash "missing" for ~1s.
        _eabrInCombat = true
        RequestRefresh()
        return
    end

    if e == "PLAYER_REGEN_DISABLED" then
        -- First pull of this dungeon visit: the elevated pre-key/pre-pull
        -- threshold (EABR.GetShowUnderMinutes' showUnderMPlus) is over.
        MarkDungeonPullStarted()
        -- Drops broad UNIT_AURA in combat unless group tracking is needed: Evoker keeps broad for ownOnRaid cache updates; the provider view ("others missing") keeps it for timely group coverage refreshes.
        local rbSW = db and db.profile.raidBuffs and db.profile.raidBuffs.showWhen
        local keepBroad = _isEvokerOwnOnRaid or (rbSW and rbSW.othersMissing ~= false)
        if _needGroupAura and not keepBroad then _setBroad(false) end
        -- Only flag Hunter's Mark needed if the target doesn't already have it
        _huntersMarkNeeded = true
        if C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
            and UnitExists("target") and C_UnitAuras.GetUnitAuraBySpellID("target", 257284) then
            _huntersMarkNeeded = false
        end
        -- Hide secure buttons before lockdown. ENCOUNTER_START may already have
        -- set our combat flag, so HideAllIcons guards on InCombatLockdown itself.
        HideAllIcons()
        HideCursorIcons()
        -- Re-snapshots only if ENCOUNTER_START didn't just do it (fires ms before REGEN_DISABLED, producing a cleaner snapshot since the aura API is fully available pre-lockdown).
        -- Must snapshot before marking combat, or the group-buff lookup treats itself as restricted and reports nothing found.
        if not _encounterSnapshotTime or (GetTime() - _encounterSnapshotTime) > 1 then
            SnapshotPlayerAuras()
            if _isEvokerOwnOnRaid then SnapshotOwnOnRaidBuffs() end
        end
        _eabrInCombat = true
        _encounterSnapshotTime = nil
        RequestRefresh()
        return
    end

    -- A fast encounter reset can end without a player combat transition, so
    -- clear ENCOUNTER_START's synthetic flag when lockdown is already gone.
    if e == "PLAYER_REGEN_ENABLED" or (e == "ENCOUNTER_END" and not InCombatLockdown()) then
        _eabrInCombat = false
        -- Restore broad UNIT_AURA for OOC group buff tracking
        if _needGroupAura then _setBroad(true) end
        -- Leaving combat: clean up combat icons, do full OOC refresh with secure buttons
        _huntersMarkNeeded = false
        HideCombatIcons()
        HideCursorIcons()
        pendingOOCRefresh = false
        RequestRefresh()
        return
    end

    if e == "UNIT_SPELLCAST_SUCCEEDED" then
        -- arg1 = unit ("player"), arg2 = castGUID, arg3 = spellID
        if arg3 == 257284 then
            _huntersMarkNeeded = false
            RequestRefresh()
        end
        return
    end

    if e == "PLAYER_DEAD" then
        -- Inky Blackness (and other buffs) drop on death; refresh so aura-based reminders re-evaluate and reappear once lost.
        RequestRefresh()
        return
    end

    if e == "PLAYER_ENTERING_WORLD" then
        wipe(_dismissedUntilLoad)
        EABR.ScanEatingState()
        if not InCombatLockdown() then EABR.SyncProviderCastSpell() end
        -- GetInstanceInfo() can return stale data on the first frame after a loading screen (e.g. still
        -- reporting the previous zone on delve entry), which would show a reminder that "Where to Show"
        -- disables for the new location. Skip the immediate refresh and wait for the corrected one.
        C_Timer.After(0.5, RequestRefresh)
        return
    end

    if e == "UNIT_AURA" then
        -- arg1 = unit token. Player aura changes always refresh; group member changes only matter for Evoker ownOnRaid cache updates and OOC raid buff checks (broad UNIT_AURA is only registered for classes needing group tracking).
        if arg1 == "player" then
            EABR.UpdateEatingState(arg2)
            local isEvoker = _cachedPlayerClass == "EVOKER"
            if isEvoker and InCombat() and IsInGroup() then
                for _, id in ipairs(_ownOnRaidIDs) do
                    local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
                    if ok and result ~= nil and not isSecret(result) then
                        _preCombatOwnOnRaidCache[id] = true
                    end
                end
            end
            RequestRefresh()
        else
            -- Group member aura change (fast unit-type check via first byte). Broad UNIT_AURA stays registered in combat for Evoker ownOnRaid / provider-view coverage tracking; coalesces group events into one deferred refresh.
            local c = arg1 and arg1:byte(1)
            if c == 112 or c == 114 then  -- 'p' or 'r'
                if _isEvokerOwnOnRaid and InCombat() and IsInGroup() then
                    for _, id in ipairs(_ownOnRaidIDs) do
                        if not _preCombatOwnOnRaidCache[id] then
                            local ok, result = pcall(C_UnitAuras.GetUnitAuraBySpellID, arg1, id)
                            if ok and result ~= nil and not isSecret(result) then
                                _preCombatOwnOnRaidCache[id] = true
                            end
                        end
                    end
                end
                if not _groupAuraDirty then
                    _groupAuraDirty = true
                    C_Timer.After(0.3, function()
                        _groupAuraDirty = false
                        RequestRefresh()
                    end)
                end
            end
        end
        return
    end

    if e == "UNIT_ENTERED_VEHICLE" or e == "UNIT_EXITED_VEHICLE" then
        if arg1 == "player" then RequestRefresh() end
        return
    end

    -- Roster changes don't affect player buffs/consumables; skips the full
    -- refresh (which scans all group members via CountGroupBuffCoverage).
    -- Exception: the receiver view keys off which CLASSES are present, so a
    -- joiner/leaver must re-evaluate it.
    if e == "GROUP_ROSTER_UPDATE" then
        local rbSW = db and db.profile.raidBuffs and db.profile.raidBuffs.showWhen
        if rbSW and rbSW.iAmMissing == true then RequestRefresh() end
        return
    end

    -- Bag CONTENT changes (BAG_UPDATE/_DELAYED) alter item counts/resolution, so re-scan. BAG_UPDATE_COOLDOWN
    -- is intentionally NOT registered: it fires ~1/sec from cooldown ticks, changes nothing reminder-relevant, and would refresh every second and bust the resolved-item cache.
    if e == "BAG_UPDATE_DELAYED" or e == "BAG_UPDATE" then
        InvalidateItemCountCache()
    end

    -- Equipped-weapon changes alter weapon-enchant resolution (weapon type -> which enchant item/slots show). Item counts are unchanged, so only the resolved cache needs rebuilding.
    if e == "UNIT_INVENTORY_CHANGED" then
        -- UNIT_INVENTORY_CHANGED also fires for temp enchants, procs, durability, etc.; only the WEAPON TYPE feeds resolution, so re-resolves only when the category changed (vs the last-resolved cat).
        local R = EABR._resolved
        if GetWeaponCategory(16) ~= R.we[16].cat or GetWeaponCategory(17) ~= R.we[17].cat then
            R.dirty = true
        end
    end

    -- Dismount: the pet comes back a moment AFTER the mount display drops, so the "Pet" reminder would flash in that gap. Grace-window it, and schedule the refresh that closes the window (nothing else fires when the pet is genuinely absent, which would latch the reminder off).
    if e == "PLAYER_MOUNT_DISPLAY_CHANGED" and not IsMounted() then
        EABR._petRemountGrace = GetTime() + 2
        C_Timer.After(2.1, RequestRefresh)
    end

    -- All other events: just refresh
    RequestRefresh()
end)

-- Item use tracking: _bagCounts (built by RebuildBagCounts, shared with the consumable item-count cache) is the
-- single source of truth for bag contents. On BAG_UPDATE_DELAYED, rebuilds ONCE and diffs against the previous snapshot to detect dropped (used) items -- no second bag walk.
local _prevBagCounts = {}

local function DetectUsedItem()
    if not db then return end
    RebuildBagCounts()
    for itemID, oldCount in pairs(_prevBagCounts) do
        if (_bagCounts[itemID] or 0) < oldCount then
            TrackItemUse(itemID)
        end
    end
    wipe(_prevBagCounts)
    for k, v in pairs(_bagCounts) do _prevBagCounts[k] = v end
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(_, ev)
        if ev == "PLAYER_LOGIN" then
            C_Timer.After(1, function()
                RebuildBagCounts()
                wipe(_prevBagCounts)
                for k, v in pairs(_bagCounts) do _prevBagCounts[k] = v end
            end)
        elseif ev == "BAG_UPDATE_DELAYED" then
            DetectUsedItem()
        end
    end)
end

mainFrame:RegisterEvent("ENCOUNTER_START")
mainFrame:RegisterEvent("ENCOUNTER_END")
mainFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
mainFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
mainFrame:RegisterEvent("SPELLS_CHANGED")
mainFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
mainFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
mainFrame:RegisterEvent("PLAYER_LEVEL_CHANGED")
mainFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
mainFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
mainFrame:RegisterUnitEvent("UNIT_AURA", "player")
mainFrame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
mainFrame:RegisterEvent("CHALLENGE_MODE_START")
mainFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
mainFrame:RegisterEvent("CHALLENGE_MODE_RESET")
mainFrame:RegisterEvent("BAG_UPDATE_DELAYED")
mainFrame:RegisterEvent("WEAPON_ENCHANT_CHANGED")
mainFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
mainFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
mainFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
mainFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
mainFrame:RegisterEvent("PLAYER_DEAD")
mainFrame:RegisterEvent("PLAYER_ALIVE")
mainFrame:RegisterEvent("PLAYER_UNGHOST")
mainFrame:RegisterEvent("BAG_UPDATE")
mainFrame:RegisterUnitEvent("UNIT_PET", "player")
-- UNIT_PET fires on pet summon/dismiss, NOT stance changes. Pet on Passive reacts to the pet's command state via the pet action bar -- PET_BAR_UPDATE is that event; without it the reminder only re-evaluated on reload.
mainFrame:RegisterEvent("PET_BAR_UPDATE")

-------------------------------------------------------------------------------
--  Ready Check Mana Warning: centered text warning for ~10s when a ready check fires in a raid and the player is a healer under 80% mana. Out-of-combat only.
-------------------------------------------------------------------------------
local SetupReadyCheckManaWarning = function()
    local warnFrame, warnFS, warnTimer, warnCurve

    -- Helpers hang on EABR, not block locals (file's main chunk sits at Lua 5.1's 200-local cap); settings slice (db.profile.consumables, options "Ready Check Mana Warning" row) is fetched inline per helper for the same reason.

    -- Default ON: the warning predates its toggle, so a missing key = enabled.
    function EABR.RCWEnabled()
        local p = db and db.profile
        local c = p and p.consumables
        return not c or c.rcManaWarn ~= false
    end

    -- Custom swatch color, or the brightened mana color (the original look).
    function EABR.RCWColor()
        local p = db and db.profile
        local c = p and p.consumables
        local col = c and c.rcManaWarnColor
        if col and col.r then return col.r, col.g, col.b end
        local mc = EllesmereUI.GetPowerColor and EllesmereUI.GetPowerColor("MANA")
        if mc then
            return math.min(mc.r * 1.5, 1), math.min(mc.g * 1.5, 1), math.min(mc.b * 1.5, 1)
        end
        return 0, 0.825, 1
    end

    local function HideWarning()
        if warnFrame then
            if warnFrame._breathe then warnFrame._breathe:Stop() end
            warnFrame:Hide()
        end
        if warnTimer then warnTimer:Cancel(); warnTimer = nil end
    end

    -- Pushes position/size/color settings onto the built frame; the color curve is rebuilt here since colors bake in at AddPoint time, and an already-visible warning/preview is re-tinted so edits show live.
    function EABR.RCWApplySettings()
        if not warnFrame then return end
        local p = db and db.profile
        local c = p and p.consumables
        warnFrame:ClearAllPoints()
        warnFrame:SetPoint("CENTER", UIParent, "CENTER",
            (c and c.rcManaWarnX) or 0, 75 + ((c and c.rcManaWarnY) or 0))
        local font = ResolveFontPath()
        local outline = GetABROutline()
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(warnFS, outline == "" and GetABRUseShadow()) end
        warnFS:SetFont(font, (c and c.rcManaWarnSize) or 48, outline)
        -- Explicit white instance color: tinted purely via SetVertexColor (curve result); with no instance color it would inherit the primed shadow FontObject's color, which resolves BLACK.
        warnFS:SetTextColor(1, 1, 1, 1)
        local r, g, b = EABR.RCWColor()
        -- Curve: alpha 1 at/below 80%, alpha 0 above; colors the FontString directly via SetVertexColor, using alpha for visibility -- no secret value reads.
        if C_CurveUtil and C_CurveUtil.CreateColorCurve then
            warnCurve = C_CurveUtil.CreateColorCurve()
            warnCurve:AddPoint(0.0,    CreateColor(r, g, b, 1))
            warnCurve:AddPoint(0.80,   CreateColor(r, g, b, 1))
            warnCurve:AddPoint(0.8001, CreateColor(r, g, b, 0))
            warnCurve:AddPoint(1.0,    CreateColor(r, g, b, 0))
        end
        if warnFrame:IsShown() then
            warnFS:SetVertexColor(r, g, b, 1)
        end
    end

    local function BuildWarnFrame()
        if warnFrame then return end
        warnFrame = CreateFrame("Frame", nil, UIParent)
        warnFrame:SetSize(600, 60)
        warnFrame:SetFrameStrata("FULLSCREEN")
        warnFrame:SetFrameLevel(100)
        warnFrame:Hide()
        warnFS = warnFrame:CreateFontString(nil, "OVERLAY")
        warnFS:SetPoint("CENTER")
        -- Breathe animation: fade between 60% and 100% alpha
        local ag = warnFrame:CreateAnimationGroup()
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0.6)
        fadeOut:SetDuration(0.4)
        fadeOut:SetOrder(1)
        fadeOut:SetSmoothing("IN_OUT")
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.6)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.4)
        fadeIn:SetOrder(2)
        fadeIn:SetSmoothing("IN_OUT")
        ag:SetLooping("REPEAT")
        warnFrame._breathe = ag
        EABR.RCWApplySettings()
        warnFS:SetText(EllesmereUI.L("LOW MANA"))
    end

    -- Only listens for READY_CHECK OOC AND in a raid; GROUP_ROSTER_UPDATE/zone change track raid membership, PLAYER_REGEN toggles combat state.
    local rcFrame = CreateFrame("Frame")
    local _inRaid = false

    local function UpdateReadyCheckRegistration()
        local shouldListen = _inRaid and not InCombatLockdown() and EABR.RCWEnabled()
        if shouldListen then
            rcFrame:RegisterEvent("READY_CHECK")
        else
            rcFrame:UnregisterEvent("READY_CHECK")
            HideWarning()
        end
    end

    rcFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    rcFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    rcFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    rcFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    rcFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    rcFrame:SetScript("OnEvent", function(_, event)
        if event == "GROUP_ROSTER_UPDATE" or event == "ZONE_CHANGED_NEW_AREA"
           or event == "PLAYER_ENTERING_WORLD" then
            _inRaid = IsInRaid()
            UpdateReadyCheckRegistration()
            return
        end
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            UpdateReadyCheckRegistration()
            return
        end
        -- READY_CHECK (only fires when out of combat AND in raid)
        if not EABR.RCWEnabled() then return end
        local spec = GetSpecialization and GetSpecialization()
        if not spec then return end
        local role = GetSpecializationRole(spec)
        if role ~= "HEALER" then return end
        if not UnitPowerPercent then return end
        BuildWarnFrame()
        EABR.RCWApplySettings()
        if not warnCurve then return end
        -- Lets WoW's C side evaluate mana% against the curve: full alpha below 80%, zero above. SetVertexColor applies the secret RGBA directly -- no reads needed.
        local color = UnitPowerPercent("player", Enum.PowerType.Mana, false, warnCurve)
        if not color or not color.GetRGBA then return end
        warnFS:SetVertexColor(color:GetRGBA())
        warnFrame:Show()
        if warnFrame._breathe and not warnFrame._breathe:IsPlaying() then
            warnFrame._breathe:Play()
        end
        if warnTimer then warnTimer:Cancel() end
        warnTimer = C_Timer.NewTimer(10, HideWarning)
    end)

    -- Options hooks (Consumables -> Ready Check Mana Warning row).
    _G._EABR_RCWarnApply = function()
        BuildWarnFrame()
        EABR.RCWApplySettings()
    end
    -- Preview bypasses the curve (must be visible at any mana level), tinting with the plain configured color (readable constants, no secrets).
    _G._EABR_RCWarnPreview = function()
        BuildWarnFrame()
        EABR.RCWApplySettings()
        if warnTimer then warnTimer:Cancel(); warnTimer = nil end
        local r, g, b = EABR.RCWColor()
        warnFS:SetVertexColor(r, g, b, 1)
        warnFrame:Show()
        if warnFrame._breathe and not warnFrame._breathe:IsPlaying() then
            warnFrame._breathe:Play()
        end
    end
    _G._EABR_RCWarnHidePreview = HideWarning
    _G._EABR_RCWarnUpdateReg = UpdateReadyCheckRegistration
end
SetupReadyCheckManaWarning()

