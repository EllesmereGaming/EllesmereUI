-------------------------------------------------------------------------------
--  EllesmereUIAuraBuffReminders.lua
--  Complete AuraBuff Reminders: Raid Buffs, Auras, Consumables
--  Clickable SecureActionButton icons with combat-aware tracking
--  Blizzard 12.0 Midnight non-secret spell support
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-- AceDB replaced by EllesmereUI.Lite.NewDB

local Known = function(id) return id and (IsPlayerSpell(id) or IsSpellKnown(id)) end
local InCombat = function() return InCombatLockdown and InCombatLockdown() end
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local texCache = {}
local function Tex(id)
    local c = texCache[id]; if c then return c end
    local t = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or GetSpellTexture(id)
    if t then texCache[id] = t end; return t
end

local function GetPlayerClass()
    local _, cls = UnitClass("player"); return cls
end

local function GetSpecID()
    local s = GetSpecialization(); if not s then return nil end
    return GetSpecializationInfo(s)
end

-------------------------------------------------------------------------------
--  Font paths (shared with options for font dropdown)
-------------------------------------------------------------------------------
local FONT_DIR = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\"
local fontPaths = {
    ["Expressway"]          = FONT_DIR .. "Expressway.TTF",
    ["Avant Garde"]         = FONT_DIR .. "Avant Garde.ttf",
    ["Arial Bold"]          = FONT_DIR .. "Arial Bold.TTF",
    ["Poppins"]             = FONT_DIR .. "Poppins.ttf",
    ["Fira Sans Medium"]    = FONT_DIR .. "FiraSans Medium.ttf",
    ["Arial Narrow"]        = FONT_DIR .. "Arial Narrow.ttf",
    ["Changa"]              = FONT_DIR .. "Changa.ttf",
    ["Cinzel Decorative"]   = FONT_DIR .. "Cinzel Decorative.ttf",
    ["Exo"]                 = FONT_DIR .. "Exo.otf",
    ["Fira Sans Bold"]      = FONT_DIR .. "FiraSans Bold.ttf",
    ["Fira Sans Light"]     = FONT_DIR .. "FiraSans Light.ttf",
    ["Future X Black"]      = FONT_DIR .. "Future X Black.otf",
    ["Gotham Narrow Ultra"] = FONT_DIR .. "Gotham Narrow Ultra.otf",
    ["Gotham Narrow"]       = FONT_DIR .. "Gotham Narrow.otf",
    ["Russo One"]           = FONT_DIR .. "Russo One.ttf",
    ["Ubuntu"]              = FONT_DIR .. "Ubuntu.ttf",
    ["Friz Quadrata"]       = "Fonts\\FRIZQT__.TTF",
    ["Arial"]               = "Fonts\\ARIALN.TTF",
    ["Morpheus"]            = "Fonts\\MORPHEUS.TTF",
    ["Skurri"]              = "Fonts\\skurri.ttf",
}
local function ResolveFontPath(fontName)
    if EllesmereUI and EllesmereUI.GetFontPath then
        return EllesmereUI.GetFontPath("auraBuff")
    end
    return fontPaths[fontName or "Expressway"] or fontPaths["Expressway"]
end

-------------------------------------------------------------------------------
--  ShortLabel â€” shorten buff/aura names for icon text display
-------------------------------------------------------------------------------
local LABEL_OVERRIDES = {
    ["Defensive Stance"]        = "Stance",
    ["Berserker Stance"]        = "Stance",
    ["Devotion Aura"]           = "Aura",
    ["Power Word: Fortitude"]   = "Fortitude",
    ["Arcane Intellect"]        = "Intellect",
    ["Battle Shout"]            = "Shout",
}
local LABEL_CLASS_OVERRIDES = {
    ROGUE  = "Poison",
    SHAMAN_IMBUE  = "Weapon",
    SHAMAN_SHIELD = "Shield",
}
local function ShortLabel(name, classOverride)
    if classOverride and LABEL_CLASS_OVERRIDES[classOverride] then
        return LABEL_CLASS_OVERRIDES[classOverride]
    end
    if LABEL_OVERRIDES[name] then return LABEL_OVERRIDES[name] end
    return name:match("^(%S+)") or name
end

-------------------------------------------------------------------------------
--  Instance / Difficulty helpers
--  Cached per-frame: call CacheInstanceInfo() at the start of Refresh()
-------------------------------------------------------------------------------
local _cachedIType, _cachedDiffID

local function CacheInstanceInfo()
    local _, iType, diffID = GetInstanceInfo()
    _cachedIType = iType
    _cachedDiffID = tonumber(diffID) or 0
end

local function InRealInstancedContent()
    if _cachedDiffID == 0 then return false end
    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then return false end
    if _cachedIType == "party" or _cachedIType == "raid" or _cachedIType == "scenario" then return true end
    return false
end

local function InMythicPlusKey()
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
end

-- Mythic 0 dungeon (party, normal difficulty 1) or Mythic raid (difficulty 16)
local function InMythicZeroDungeonOrMythicRaid()
    if _cachedIType == "party" and (_cachedDiffID == 23 or _cachedDiffID == 8) then return true end
    if _cachedIType == "raid" and _cachedDiffID == 16 then return true end
    return false
end

-- Heroic+ content (heroic dungeon/raid or mythic dungeon/raid/M+)
local function InHeroicOrMythicContent()
    if _cachedIType == "party" and (_cachedDiffID == 2 or _cachedDiffID == 23 or _cachedDiffID == 8) then return true end
    if _cachedIType == "raid" and (_cachedDiffID == 5 or _cachedDiffID == 6 or _cachedDiffID == 15 or _cachedDiffID == 16) then return true end
    return false
end

-------------------------------------------------------------------------------
--  Midnight Season 1 â€” Dungeon & Raid Instance Names
-------------------------------------------------------------------------------
local TALENT_REMINDER_ZONES = {
    { name="The Voidspire",              type="raid" },
    { name="Magister's Terrace",         type="dungeon" },
    { name="Maisara Caverns",            type="dungeon" },
    { name="Nexus-Point Xenas",          type="dungeon" },
    { name="Windrunner Spire",           type="dungeon" },
    { name="Algeth'ar Academy",          type="dungeon" },
    { name="Seat of the Triumvirate",    type="dungeon" },
    { name="Skyreach",                   type="dungeon" },
    { name="Pit of Saron",              type="dungeon" },
}

-------------------------------------------------------------------------------
--  Talent query helpers
-------------------------------------------------------------------------------
local function GetCurrentInstanceName()
    local name = GetInstanceInfo()
    return name
end

-------------------------------------------------------------------------------
--  Aura query helpers (secret-value safe)
--  Uses C_UnitAuras.GetPlayerAuraBySpellID for player checks â€” takes a known
--  (non-secret) spell ID and returns nil or an AuraData table.  The table
--  reference itself is never secret, only its fields, so "if result then" is
--  safe even in combat.
--
--  NON_SECRET_SPELL_IDS: Blizzard-whitelisted spell IDs whose aura data
--  remains non-secret even during combat lockdown (Patch 12.0).
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
    -- Paladin Auras â€” Devotion Aura (465) is still ContextuallySecret as of
    -- Midnight 12.0; removed from whitelist so the reminder hides in combat.
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
}

-------------------------------------------------------------------------------
--  Pre-combat aura snapshot
--  Snapshots player aura state before entering combat so we have a reliable
--  fallback for any whitelisted spell whose live API returns nil in combat.
-------------------------------------------------------------------------------
local _preCombatAuraCache = {}  -- [spellID] = true/false, snapshotted at REGEN_DISABLED
local _eabrLogEnabled = false   -- toggled by /eabrlog

local function _isRuntimeNonSecret(id)
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        return not C_Secrets.ShouldSpellAuraBeSecret(id)
    end
    return true  -- if API missing, assume non-secret (pre-12.0 client)
end

local function SnapshotPlayerAuras()
    wipe(_preCombatAuraCache)
    -- Snapshot every whitelisted spell ID before entering combat.
    -- GetPlayerAuraBySpellID returns nil for everything during combat,
    -- and UNIT_AURA payload spell IDs are all secret values in combat,
    -- so this snapshot is the ONLY reliable source of aura state.
    for id in pairs(NON_SECRET_SPELL_IDS) do
        local result = C_UnitAuras.GetPlayerAuraBySpellID(id)
        _preCombatAuraCache[id] = (result ~= nil)
    end
end

-- Pre-combat snapshot for "ownOnRaid" buffs (Source of Magic, Beacon, etc.)
-- These are buffs the player casts on OTHER group members. sourceUnit is
-- unreadable in combat, so we snapshot the result of the full group scan
-- before entering combat.
local _preCombatOwnOnRaidCache = {}  -- [spellID] = true/false
local SnapshotOwnOnRaidBuffs  -- forward declaration; defined after _unitHasBuffFromPlayer

local function PlayerHasAuraByID(spellIDs)
    if not spellIDs or not spellIDs[1] then return true end
    local inCombat = InCombat()
    for j = 1, #spellIDs do
        local id = spellIDs[j]
        if NON_SECRET_SPELL_IDS[id] then
            -- Try the live API first.  Wrap in pcall to guard against any
            -- restricted-API edge cases.
            local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
            if ok then
                if result ~= nil then
                    -- Got something back from the API
                    local secret = issecretvalue(result)
                    if not secret then
                        return true   -- live non-secret data says buff is present
                    end
                    -- Secret value â€” API confirms aura exists but won't reveal data
                    return true
                end
                -- result == nil: API says "not found" OR spell is contextually
                -- secret and the API just returns nil.  During combat, consult
                -- the pre-combat snapshot as a fallback.
                if inCombat and _preCombatAuraCache[id] then return true end
            else
                -- pcall failed â€” API restricted; use snapshot in combat
                if inCombat and _preCombatAuraCache[id] then return true end
            end
        end
    end
    -- Fallback for non-whitelisted IDs: iterate auras (only works out of combat)
    if not inCombat then
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            local sid = aura.spellId
            if sid and not issecretvalue(sid) then
                for j = 1, #spellIDs do
                    if not NON_SECRET_SPELL_IDS[spellIDs[j]] and sid == spellIDs[j] then return true end
                end
            end
        end
    end
    return false
end

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
                    if result ~= nil then
                        local secret = issecretvalue(result)
                        if not secret then return true end
                        return true  -- secret value still means aura exists
                    end
                    if inCombat and _preCombatAuraCache[id] then return true end
                else
                    if inCombat and _preCombatAuraCache[id] then return true end
                end
            end
        end
    else
        -- Non-player units: use GetUnitAuraBySpellID for whitelisted IDs
        -- This works in combat for non-secret spell IDs.
        for j = 1, #spellIDs do
            local id = spellIDs[j]
            if NON_SECRET_SPELL_IDS[id] then
                local ok, result = pcall(C_UnitAuras.GetUnitAuraBySpellID, u, id)
                if ok and result ~= nil and not issecretvalue(result) then
                    return true
                end
            end
        end
    end
    -- Iterate auras for non-whitelisted IDs (only works out of combat)
    if not inCombat then
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex(u, i, "HELPFUL")
            if not aura then break end
            local sid = aura.spellId
            if sid and not issecretvalue(sid) then
                for j = 1, #spellIDs do if sid == spellIDs[j] then return true end end
            end
        end
    end
    return false
end

-- Like _unitHasBuff but only returns true if the buff's source is the player.
-- Used for Beacon of Light, Beacon of Faith, Earth Shield (orbit) â€” we need
-- to verify it's OUR buff, not another Paladin's/Shaman's.
-- Works in combat for non-secret spell IDs via GetUnitAuraBySpellID (direct
-- lookup, no iteration).  Falls back to GetAuraDataByIndex iteration OOC.
local function _unitHasBuffFromPlayer(u, spellIDs)
    local inCombat = InCombat()
    local idLookup = {}
    for j = 1, #spellIDs do idLookup[spellIDs[j]] = true end

    -- Fast path: direct lookup for whitelisted IDs
    for id in pairs(idLookup) do
        if NON_SECRET_SPELL_IDS[id] then
            -- Direct lookup â€” works on any unit, in or out of combat, for
            -- non-secret spell IDs.  Player uses GetPlayerAuraBySpellID
            -- (faster), everyone else uses GetUnitAuraBySpellID.
            local ok, aura
            if UnitIsUnit(u, "player") then
                ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
            else
                ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, u, id)
            end
            if ok and aura ~= nil and not issecretvalue(aura) then
                -- Check isFromPlayerOrPlayerPet first (simple boolean, always
                -- present).  Fall back to sourceUnit if available.
                local fromMe = aura.isFromPlayerOrPlayerPet
                if fromMe and not issecretvalue(fromMe) and fromMe == true then
                    return true
                end
                local src = aura.sourceUnit
                if src and not issecretvalue(src) and UnitIsUnit(src, "player") then
                    return true
                end
                -- Direct lookup found the aura but couldn't verify source.
                -- Fall through to iteration below (OOC only) which often
                -- populates sourceUnit when the direct API doesn't.
            end
        end
    end
    -- Iteration fallback (OOC): works for ALL spell IDs, including whitelisted
    -- ones where the direct lookup couldn't confirm source ownership.
    if not inCombat then
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex(u, i, "HELPFUL")
            if not aura then break end
            local sid = aura.spellId
            if sid and not issecretvalue(sid) and idLookup[sid] then
                local src = aura.sourceUnit
                if src and not issecretvalue(src) and UnitIsUnit(src, "player") then
                    return true
                end
            end
        end
    end
    return false
end

-- Assign the SnapshotOwnOnRaidBuffs function (forward-declared earlier,
-- now that _unitHasBuffFromPlayer is defined).
SnapshotOwnOnRaidBuffs = function()
    wipe(_preCombatOwnOnRaidCache)
    local ownOnRaidIDs = { 53563, 156910, 369459 }
    for _, id in ipairs(ownOnRaidIDs) do
        local found = false
        if _unitHasBuffFromPlayer("player", {id}) then found = true end
        if not found then
            if IsInRaid() then
                for i = 1, GetNumGroupMembers() do
                    if _unitHasBuffFromPlayer("raid"..i, {id}) then found = true; break end
                end
            elseif IsInGroup() then
                for i = 1, GetNumSubgroupMembers() do
                    if _unitHasBuffFromPlayer("party"..i, {id}) then found = true; break end
                end
            end
        end
        _preCombatOwnOnRaidCache[id] = found
    end
end

-- Like PlayerHasAuraByID but only returns true if the buff's source is the
-- player themselves.  Used for Devotion Aura â€” Holy Paladins need their OWN
-- aura active for Aura Mastery, and Lightsmith Prot Paladins need their own
-- aura for amplification.  Another paladin's Devotion Aura on the player
-- does NOT satisfy this check.
-- IMPORTANT: This only works out of combat (aura iteration).  The caller
-- must ensure combatOk=false on the aura entry so this is never called
-- during combat where aura data is secret/restricted.
local function PlayerHasSelfCastAuraByID(spellIDs)
    if not spellIDs or not spellIDs[1] then return true end
    if InCombat() then return false end  -- safety: can't read sourceUnit in combat
    local lookup = {}
    for j = 1, #spellIDs do lookup[spellIDs[j]] = true end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local sid = aura.spellId
        if sid and not issecretvalue(sid) and lookup[sid] then
            local src = aura.sourceUnit
            if src and not issecretvalue(src) and UnitIsUnit(src, "player") then
                return true
            end
        end
    end
    return false
end

-- Check if ANY group/raid member is missing a buff (for "show if others missing")
local function AnyGroupMemberMissingBuff(spellIDs)
    if not IsInGroup() then return not _unitHasBuff("player", spellIDs) end
    if _unitOk("player") and not _unitHasBuff("player", spellIDs) then return true end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid"..i
            if _unitOk(u) and not UnitIsUnit(u, "player") and not _unitHasBuff(u, spellIDs) then return true end
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            local u = "party"..i
            if _unitOk(u) and not _unitHasBuff(u, spellIDs) then return true end
        end
    end
    return false
end

-- Check if the buff exists on ANY group/raid member (any source).
-- Used for Symbiotic Relationship â€” just needs to exist on someone.
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

-- Check if the PLAYER'S buff exists on ANY group/raid member (source must be player).
-- Returns true if at least one member has the buff cast by the player.
-- Used for Beacon of Light, Beacon of Faith, Earth Shield (orbit other).
local function PlayerOwnBuffOnAnyGroupMember(spellIDs)
    if _unitHasBuffFromPlayer("player", spellIDs) then return true end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            if _unitHasBuffFromPlayer("raid"..i, spellIDs) then return true end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            if _unitHasBuffFromPlayer("party"..i, spellIDs) then return true end
        end
    end
    return false
end

-------------------------------------------------------------------------------
--  Weapon type classification (for weapon enchant matching)
-------------------------------------------------------------------------------
local WEAPON_CLASS_ID = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local W = (Enum and Enum.ItemWeaponSubclass) or {}

local function setFrom(...)
    local t = {}
    for i = 1, select("#", ...) do local v = select(i, ...); if v ~= nil then t[v] = true end end
    return t
end

local BLADED_SET = setFrom(W.Axe1H, W.Axe2H, W.Sword1H, W.Sword2H, W.Dagger, W.Polearm, W.Warglaive)
local BLUNT_SET  = setFrom(W.Mace1H, W.Mace2H, W.Staff, W.Fist)
local RANGED_SET = setFrom(W.Bow, W.Gun, W.Crossbow, W.Wand)

local function GetWeaponCategory(slotID)
    local itemID = GetInventoryItemID("player", slotID)
    if not itemID then return nil end
    local _, _, _, equipLoc, _, classID, subClassID
    if C_Item and C_Item.GetItemInfoInstant then
        _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    else
        _, _, _, equipLoc, _, classID, subClassID = GetItemInfoInstant(itemID)
    end
    if not classID or classID ~= WEAPON_CLASS_ID then return nil end
    if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then return nil end
    if subClassID and BLADED_SET[subClassID] then return "BLADED" end
    if subClassID and BLUNT_SET[subClassID]  then return "BLUNT" end
    if subClassID and RANGED_SET[subClassID] then return "RANGED" end
    return "NEUTRAL"
end


-------------------------------------------------------------------------------
--  SPELL DATA â€” Raid Buffs (all non-secret in 12.0, work in combat)
-------------------------------------------------------------------------------
local RAID_BUFFS = {
    { key="motw",   class="DRUID",   name="Mark of the Wild",       castSpell=1126,   buffIDs={1126,432661},    check="raid" },
    { key="bshout", class="WARRIOR", name="Battle Shout",           castSpell=6673,   buffIDs={6673},    check="raid" },
    { key="fort",   class="PRIEST",  name="Power Word: Fortitude",  castSpell=21562,  buffIDs={21562},   check="raid" },
    { key="ai",     class="MAGE",    name="Arcane Intellect",       castSpell=1459,   buffIDs={1459,432778},    check="raid" },
    { key="bronze", class="EVOKER",  name="Blessing of the Bronze", castSpell=364342,
      buffIDs={381732,381741,381746,381748,381749,381750,381751,381752,381753,381754,381756,381757,381758},
      check="raid" },
    { key="sky",    class="SHAMAN",  name="Skyfury",                castSpell=462854, buffIDs={462854},  check="raid" },
}

-------------------------------------------------------------------------------
--  SPELL DATA â€” Auras (some non-secret, some still OOC-only)
-------------------------------------------------------------------------------
local AURAS = {
    -- Symbiotic Relationship: non-secret (474754) â€” player-only check
    -- (applies to both player and target; if player has it, target does too)
    { key="symbiotic",  class="DRUID",   name="Symbiotic Relationship", castSpell=474750, buffIDs={474754},
      check="player", combatOk=true, requireInstanceGroup=true },
    -- Warrior stances: NOT on non-secret list, OOC only
    { key="def_stance",  class="WARRIOR", name="Defensive Stance",  castSpell=386208, buffIDs={386208},
      check="player", specs={73}, combatOk=false },
    { key="berserk_stance", class="WARRIOR", name="Berserker Stance", castSpell=386196, buffIDs={386196},
      check="player", specs={71, 72}, combatOk=false },
    -- Shadowform: NOT on non-secret list, OOC only
    { key="shadowform", class="PRIEST",  name="Shadowform",        castSpell=232698, buffIDs={232698},
      check="player", specs={258}, combatOk=false },
    -- Devotion Aura: still ContextuallySecret (465) â€” hide in combat
    -- Must check self-cast: Holy Paladins need their OWN aura for Aura Mastery,
    -- Lightsmith Prot Paladins need their own aura for amplification.
    -- Another paladin's Devotion Aura does NOT satisfy this.
    { key="devo_aura",  class="PALADIN", name="Devotion Aura",     castSpell=465,    buffIDs={465},
      check="playerSelfCast", combatOk=false },
    -- Beacon of Light: non-secret (53563) â€” must verify source is player
    { key="bol",        class="PALADIN", name="Beacon of Light",   castSpell=53563,  buffIDs={53563},
      check="ownOnRaid", combatOk=true },
    -- Beacon of Faith: non-secret (156910) â€” must verify source is player
    { key="bof",        class="PALADIN", name="Beacon of Faith",   castSpell=156910, buffIDs={156910},
      check="ownOnRaid", combatOk=true, requireInstanceGroup=true },
    -- Source of Magic: non-secret (369459) â€" applied to a specific healer,
    -- not the caster; check if player's cast exists on any group member.
    { key="som",        class="EVOKER",  name="Source of Magic",   castSpell=369459, buffIDs={369459},
      check="ownOnRaid", combatOk=true, requireInstanceGroup=true },
}

-------------------------------------------------------------------------------
--  SPELL DATA â€” Consumables (OOC only, not during keystones)
-------------------------------------------------------------------------------
-- Rogue Poisons (all non-secret in 12.0 but we treat as consumable = OOC check)
local ROGUE_POISONS = {
    { key="deadly",     name="Deadly Poison",     castSpell=2823,   buffIDs={2823} },
    { key="instant",    name="Instant Poison",    castSpell=315584, buffIDs={315584} },
    { key="wound",      name="Wound Poison",      castSpell=8679,   buffIDs={8679} },
    { key="amplifying", name="Amplifying Poison", castSpell=381664, buffIDs={381664} },
    { key="crippling",  name="Crippling Poison",  castSpell=3408,   buffIDs={3408} },
    { key="numbing",    name="Numbing Poison",    castSpell=5761,   buffIDs={5761} },
    { key="atrophic",   name="Atrophic Poison",   castSpell=381637, buffIDs={381637} },
}

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
    { key="tidecaller",  name="Tidecaller's Guard", castSpell=457496, buffIDs={457496, 457481}, wepEnchID={0} },
    { key="tstrike",     name="Thunderstrike Ward", castSpell=462757, buffIDs={462757, 462742}, wepEnchID={7587} },
}

-- Shaman Shields (elemental orbit support)
local SHAMAN_SHIELDS = {
    { key="ls", name="Lightning Shield", castSpell=192106, buffIDs={192106}, specs={262} },
    { key="ws", name="Water Shield",     castSpell=52127,  buffIDs={52127},  specs={264} },
    { key="es", name="Earth Shield",     castSpell=974,    buffIDs={974}, specs={264},
      orbitTalent=383010, selfOrbitBuff={383648}, otherBuff={974} },
}

-- Weapon Enchant Items (temporary weapon enchants applied from items)
-- weaponType: BLADED, BLUNT, RANGED, NEUTRAL (NEUTRAL fits any weapon)
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

-- Flask Items (Midnight) â€” each flask has multiple item IDs across quality ranks + fleeting variants
local FLASK_ITEMS = {
    { key="blood_knights",         buffID=1235110, name="Flask of the Blood Knights",
      items={241324, 241325, 245931, 245930} },
    { key="magisters",             buffID=1235108, name="Flask of the Magisters",
      items={241322, 241323, 245933, 245932} },
    { key="shattered_sun",         buffID=1235111, name="Flask of the Shattered Sun",
      items={241326, 241327, 245929, 245928} },
    { key="thalassian_resistance", buffID=1235057, name="Flask of Thalassian Resistance",
      items={241320, 241321, 245926, 245927} },
}
local FLASK_BUFF_IDS = {}
local FLASK_BUFF_ID_SET = {}
local FLASK_NAME_SET = {}
for _, f in ipairs(FLASK_ITEMS) do
    FLASK_BUFF_IDS[#FLASK_BUFF_IDS+1] = f.buffID
    FLASK_BUFF_ID_SET[f.buffID] = true
    FLASK_NAME_SET[f.name] = true
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
}

-- Weapon Enchant dropdown choices (name â†’ best itemID lookup at runtime)
local WEAPON_ENCHANT_CHOICES = {
    { key="thalassian_phoenix_oil",  name="Thalassian Phoenix Oil" },
    { key="smugglers_enchanted_edge", name="Smuggler's Enchanted Edge" },
    { key="oil_of_dawn",             name="Oil of Dawn" },
    { key="refulgent_weightstone",   name="Refulgent Weightstone" },
    { key="refulgent_whetstone",     name="Refulgent Whetstone" },
    { key="laced_zoomshots",         name="Laced Zoomshots" },
    { key="weighted_boomshots",      name="Weighted Boomshots" },
}

-- Augment Runes
local AUGMENT_RUNE_VOID   = 259085  -- Void-Touched Augment Rune (Midnight)
local AUGMENT_RUNE_ETHER  = 243191  -- Ethereal Augment Rune (TWW)
local RUNE_BUFF_IDS = {1264426, 453250, 1234969, 1242347, 393438, 347901}

-- Inky Black Potion
local INKY_BLACK_ITEM = 124640
local INKY_BLACK_BUFF = {124640}  -- The buff from Inky Black Potion

-------------------------------------------------------------------------------
--  Helpers: Well Fed / Flask buff detection (by name, not spell ID â€” secret)
-------------------------------------------------------------------------------
local function PlayerHasBuffByName(buffName)
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local aName = aura.name
        if aName and not issecretvalue(aName) and aName == buffName then return true end
    end
    return false
end

local function PlayerHasWellFed()
    -- "Well Fed" and "Hearty Well Fed" are name-based checks since the buff
    -- spell IDs vary by food type.  Use name iteration (OOC only).
    -- Also try a broader check: any aura whose name contains "Well Fed".
    if InCombat() then return true end  -- never show food reminder in combat
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local aName = aura.name
        if aName and not issecretvalue(aName) then
            if aName == "Well Fed" or aName == "Hearty Well Fed" then return true end
        end
    end
    return false
end

local function PlayerHasFlaskBuff()
    -- Try direct API lookup for each known flask buff ID.
    -- GetPlayerAuraBySpellID works OOC for any spell ID and in combat for
    -- non-secret IDs.  Flask checks are gated to OOC in Refresh(), so this
    -- should always succeed when the buff is active.
    for _, id in ipairs(FLASK_BUFF_IDS) do
        local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if ok and result ~= nil then return true end
    end
    -- Fallback: iterate auras by name (only works out of combat)
    if not InCombat() then
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            local sid = aura.spellId
            if sid and not issecretvalue(sid) and FLASK_BUFF_ID_SET[sid] then return true end
            local aName = aura.name
            if aName and not issecretvalue(aName) and FLASK_NAME_SET[aName] then return true end
        end
    end
    return false
end

-------------------------------------------------------------------------------
--  Helpers: Find best item in bags for a preferred choice
-------------------------------------------------------------------------------
local function FindFlaskItem(preferredKey, lastUsedItemID)
    if preferredKey == "last_used" then
        if lastUsedItemID and (GetItemCount(lastUsedItemID, false) or 0) > 0 then
            return lastUsedItemID
        end
        -- Fallback: first flask found in bags
        for _, f in ipairs(FLASK_ITEMS) do
            for _, id in ipairs(f.items) do
                if (GetItemCount(id, false) or 0) > 0 then return id end
            end
        end
        return nil
    end
    for _, f in ipairs(FLASK_ITEMS) do
        if f.key == preferredKey then
            for _, id in ipairs(f.items) do
                if (GetItemCount(id, false) or 0) > 0 then return id end
            end
        end
    end
    return nil
end

local function FindFoodItem(preferredKey, lastUsedItemID)
    if preferredKey == "last_used" then
        if lastUsedItemID and (GetItemCount(lastUsedItemID, false) or 0) > 0 then
            return lastUsedItemID
        end
        for _, f in ipairs(FOOD_ITEMS) do
            if (GetItemCount(f.itemID, false) or 0) > 0 then return f.itemID end
        end
        return nil
    end
    for _, f in ipairs(FOOD_ITEMS) do
        if f.key == preferredKey and (GetItemCount(f.itemID, false) or 0) > 0 then return f.itemID end
    end
    return nil
end

local function FindWeaponEnchantItem(preferredKey, lastUsedItemID, targetCat)
    if preferredKey == "last_used" then
        if lastUsedItemID and (GetItemCount(lastUsedItemID, false) or 0) > 0 then
            return lastUsedItemID
        end
        -- Fallback: first matching weapon enchant in bags
        for _, we in ipairs(WEAPON_ENCHANT_ITEMS) do
            local wt = we.weaponType
            if ((wt == "NEUTRAL") or (wt == targetCat)) and (GetItemCount(we.itemID, false) or 0) > 0 then
                return we.itemID
            end
        end
        return nil
    end
    -- Find by name match (picks highest tier in bags)
    for _, choice in ipairs(WEAPON_ENCHANT_CHOICES) do
        if choice.key == preferredKey then
            for _, we in ipairs(WEAPON_ENCHANT_ITEMS) do
                if we.name == choice.name and (GetItemCount(we.itemID, false) or 0) > 0 then
                    return we.itemID
                end
            end
            break
        end
    end
    return nil
end


-------------------------------------------------------------------------------
--  Glow Types (shared with options)
-------------------------------------------------------------------------------
local GLOW_TYPES = {
    { name = "Action Button Glow",   buttonGlow = true },
    { name = "Pixel Glow",           procedural = true },
    { name = "Auto-Cast Shine",      autocast = true },
    { name = "GCD",                  atlas = "RotationHelper_Ants_Flipbook",  scale = 1.6 },
    { name = "Modern WoW Glow",      atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook",  scale = 1.6 },
    { name = "Classic WoW Glow",     texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
      rows = 5, columns = 5, frames = 25, duration = 0.3, frameW = 48, frameH = 48, scale = 1.09 },
}

local GLOW_VALUES = { [0] = "None" }
local GLOW_ORDER  = { 0 }
for i, entry in ipairs(GLOW_TYPES) do
    GLOW_VALUES[i] = entry.name
    GLOW_ORDER[#GLOW_ORDER + 1] = i
end

-------------------------------------------------------------------------------
--  Glow Engines â€” provided by shared EllesmereUI_Glows.lua
-------------------------------------------------------------------------------
local _G_Glows = EllesmereUI.Glows

local function StartPixelGlow(wrapper, sz, cr, cg, cb)
    local N, th, period = 8, 2, 4
    local lineLen = floor((sz+sz)*(2/N-0.1)); lineLen = min(lineLen, sz); if lineLen < 1 then lineLen = 1 end
    _G_Glows.StartProceduralAnts(wrapper, N, th, period, lineLen, cr, cg, cb, sz)
end
local function StopPixelGlow(wrapper) _G_Glows.StopProceduralAnts(wrapper) end

local function StartButtonGlow(wrapper, sz, cr, cg, cb, scale)
    _G_Glows.StartButtonGlow(wrapper, sz, cr, cg, cb, scale)
end
local function StopButtonGlow(wrapper) _G_Glows.StopButtonGlow(wrapper) end

local function StartAutoCastShine(wrapper, sz, cr, cg, cb, scale)
    _G_Glows.StartAutoCastShine(wrapper, sz, cr, cg, cb, scale)
end
local function StopAutoCastShine(wrapper) _G_Glows.StopAutoCastShine(wrapper) end

local function StartFlipBookGlow(wrapper, sz, entry, cr, cg, cb)
    _G_Glows.StartFlipBookGlow(wrapper, sz, entry, cr, cg, cb)
end
local function StopFlipBookGlow(wrapper) _G_Glows.StopFlipBookGlow(wrapper) end

local function StopAllGlows(wrapper)
    _G_Glows.StopAllGlows(wrapper)
end


-------------------------------------------------------------------------------
--  Defaults
-------------------------------------------------------------------------------
local defaults = {
    profile = {
        display = {
            glowType = 0,
            glowColor = {r=1, g=0.776, b=0.376},
            scale = 1.0,
            xOffset = 0,
            yOffset = 200,
            showText = true,
            textColor = {r=1, g=1, b=1},
            textSize = 12,
            textFont = "Expressway",
            textXOffset = 0,
            textYOffset = -5,
            iconSpacing = 14,
            opacity = 1.0,
            cursorAttach = false,
        },
        raidBuffs = {
            showNonInstanced = false,
            showOthersMissing = true,
            scale = 1.0,
            enabled = {
                motw=true, bshout=true, fort=true, ai=true, bronze=true, sky=true,
            },
        },
        auras = {
            showNonInstanced = true,
            scale = 1.0,
            enabled = {
                symbiotic=true, def_stance=true, berserk_stance=true, shadowform=true,
                devo_aura=true, bol=true, bof=true, som=true,
            },
        },
        consumables = {
            showSpecialsNonInstanced = true,
            scale = 1.0,
            enabled = {
                deadly=true, instant=true, wound=true, amplifying=true,
                crippling=true, numbing=true, atrophic=true,
                rite_adj=true, rite_sanc=true,
                flametongue=true, windfury=true, earthliving=true, tstrike=true,
                ls=true, ws=true, es=true,
                augment_rune=true,
                weapon_enchant=true,
                inky_black=true,
                flask=true,
                food=true,
            },
            preferredFlask = "last_used",
            preferredFood = "last_used",
            preferredWeaponEnchant = "last_used",
            runeDisplayMode = "mythic",
            inkyBlackZones = "",
        },
        unlockPos = nil,
        talentReminders = {},  -- array of {zoneIDs={}, zoneNames={}, spellID=number, spellName=string, showNotNeeded=bool}
        talentReminderYOffset = -50,
    },
    char = {
        lastUsedFlask = nil,
        lastUsedFood = nil,
        lastUsedWeaponEnchant = nil,
    },
}

local db  -- set at PLAYER_LOGIN
local euiPanelOpen = false

-------------------------------------------------------------------------------
--  Middle-click dismiss â€” hide a reminder until the next loading screen
-------------------------------------------------------------------------------
local _dismissedUntilLoad = {}  -- [dismissKey] = true

-------------------------------------------------------------------------------
--  Icon Pool â€” SecureActionButton based for click-to-cast
-------------------------------------------------------------------------------
local ICON_SIZE = 40
local iconAnchor
local iconPool = {}     -- all created icon buttons
local activeIcons = {}  -- currently visible icons

-- Separate anchor + pool for talent reminder icons (shown below main icons)
local talentIconAnchor
local talentIconPool = {}
local talentActiveIcons = {}

-------------------------------------------------------------------------------
--  Combat Icon Pool â€” non-secure frames for visual-only display during combat
--  Parented to a separate combatAnchor (not iconAnchor) so Show/Hide is
--  never blocked by combat lockdown.
-------------------------------------------------------------------------------
local combatAnchor      -- created at PLAYER_LOGIN, follows iconAnchor position
local combatIconPool = {}
local combatActiveIcons = {}

-------------------------------------------------------------------------------
--  Cursor-attached combat icons â€” "important" buffs shown at the cursor
--  when cursorAttach is enabled.  Anchors to EllesmereUICursorFrame
--  (the cursor circle addon's tracking frame) for zero-cost positioning.
-------------------------------------------------------------------------------
local CURSOR_IMPORTANT = {
    -- All raid buffs are important (checked by cat == "raidbuff")
    -- Specific aura/consumable keys:
    bol = true, bof = true, es = true, som = true,
}
local cursorAnchor
local cursorIconPool = {}
local cursorActiveIcons = {}

local function GetOrCreateCombatIcon(index)
    if combatIconPool[index] then return combatIconPool[index] end
    local f = CreateFrame("Frame", "EABR_CombatIcon"..index, combatAnchor)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(120)
    f:Hide()
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f._icon = icon
    local PP = EllesmereUI and EllesmereUI.PP
    local function mkBorder(a1, a2, isH)
        local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(0, 0, 0, 1)
        if PP then PP.DisablePixelSnap(t)
        elseif t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        PP.Point(t, a1, f, a1, 0, 0)
        PP.Point(t, a2, f, a2, 0, 0)
        if isH then PP.Height(t, 1) else PP.Width(t, 1) end
    end
    mkBorder("TOPLEFT","TOPRIGHT",true); mkBorder("BOTTOMLEFT","BOTTOMRIGHT",true)
    mkBorder("TOPLEFT","BOTTOMLEFT",false); mkBorder("TOPRIGHT","BOTTOMRIGHT",false)
    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    text:SetFont("Fonts\\ARIALN.TTF", 11)
    text:SetShadowOffset(1, -1)
    text:SetTextColor(1, 1, 1, 1)
    f._text = text
    combatIconPool[index] = f
    return f
end

local function HideCombatIcons()
    for i = 1, #combatActiveIcons do
        local f = combatActiveIcons[i]
        if f then f._text:SetText(""); f:Hide() end
    end
    wipe(combatActiveIcons)
    if combatAnchor then combatAnchor:Hide() end
end

local function ShowCombatIcon(iconIdx, spellID, texture, label)
    local f = GetOrCreateCombatIcon(iconIdx)
    f._icon:SetTexture(texture or Tex(spellID) or 134400)
    if db and db.profile.display.showText then
        local p = db.profile.display
        local tc = p.textColor or {r=1, g=1, b=1}
        local fontPath = ResolveFontPath(p.textFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        f._text:SetFont(fontPath, textSize, "")
        f._text:SetShadowOffset(1, -1)
        f._text:ClearAllPoints()
        f._text:SetPoint("TOP", f, "BOTTOM", xOff, yOff)
        f._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        f._text:SetText(label or "")
        f._text:Show()
    else
        f._text:SetText("")
        f._text:Hide()
    end
    f:Show()
    combatActiveIcons[#combatActiveIcons+1] = f
end

local function LayoutCombatIcons()
    local count = #combatActiveIcons; if count == 0 then return end
    local p = db.profile.display
    local spacing = p.iconSpacing or 8
    local baseScale = p.scale or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    local totalW = (count * sz) + ((count-1) * spacing)
    local startX = -(totalW/2) + (sz/2)
    for i, f in ipairs(combatActiveIcons) do
        f:SetSize(sz, sz)
        f:SetAlpha(p.opacity or 1.0)
        f:ClearAllPoints()
        f:SetPoint("CENTER", combatAnchor, "CENTER", startX + (i-1)*(sz+spacing), 0)
    end
end

-------------------------------------------------------------------------------
--  Cursor Icon Pool â€” same visual style as combat icons, parented to
--  cursorAnchor which follows the cursor frame.
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
    local function mkBorder(a1, a2, isH)
        local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(0, 0, 0, 1)
        if PP then PP.DisablePixelSnap(t)
        elseif t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        PP.Point(t, a1, f, a1, 0, 0)
        PP.Point(t, a2, f, a2, 0, 0)
        if isH then PP.Height(t, 1) else PP.Width(t, 1) end
    end
    mkBorder("TOPLEFT","TOPRIGHT",true); mkBorder("BOTTOMLEFT","BOTTOMRIGHT",true)
    mkBorder("TOPLEFT","BOTTOMLEFT",false); mkBorder("TOPRIGHT","BOTTOMRIGHT",false)
    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    text:SetFont("Fonts\\ARIALN.TTF", 11)
    text:SetShadowOffset(1, -1)
    text:SetTextColor(1, 1, 1, 1)
    f._text = text
    cursorIconPool[index] = f
    return f
end

local function HideCursorIcons()
    for i = 1, #cursorActiveIcons do
        local f = cursorActiveIcons[i]
        if f then f._text:SetText(""); f:Hide() end
    end
    wipe(cursorActiveIcons)
    if cursorAnchor then cursorAnchor:Hide() end
end

local function ShowCursorIcon(iconIdx, spellID, texture, label)
    local f = GetOrCreateCursorIcon(iconIdx)
    f._icon:SetTexture(texture or Tex(spellID) or 134400)
    if db and db.profile.display.showText then
        local p = db.profile.display
        local tc = p.textColor or {r=1, g=1, b=1}
        local fontPath = ResolveFontPath(p.textFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        f._text:SetFont(fontPath, textSize, "")
        f._text:SetShadowOffset(1, -1)
        f._text:ClearAllPoints()
        f._text:SetPoint("TOP", f, "BOTTOM", xOff, yOff)
        f._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        f._text:SetText(label or "")
        f._text:Show()
    else
        f._text:SetText("")
        f._text:Hide()
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
        f:ClearAllPoints()
        f:SetPoint("CENTER", cursorAnchor, "CENTER", startX + (i-1)*(sz+spacing), 0)
    end
end

local function IsImportantBuff(m)
    if m.cat == "raidbuff" then return true end
    local key = m.data and m.data.key
    return key and CURSOR_IMPORTANT[key] or false
end

-- Hide stale secure buttons by zeroing their alpha (safe during combat).
-- Also stops glow animations (glow wrappers are plain Frames, not secure).
local function FadeOutSecureIcons()
    for i = 1, #activeIcons do
        local btn = activeIcons[i]
        if btn then
            btn:SetAlpha(0)
            if btn._text then btn._text:SetAlpha(0) end
            if btn._eabrGlowWrapper then StopAllGlows(btn._eabrGlowWrapper); btn._eabrGlowWrapper:SetAlpha(0) end
        end
    end
    for i = 1, #talentActiveIcons do
        local btn = talentActiveIcons[i]
        if btn then
            btn:SetAlpha(0)
            if btn._text then btn._text:SetAlpha(0) end
            if btn._eabrGlowWrapper then StopAllGlows(btn._eabrGlowWrapper); btn._eabrGlowWrapper:SetAlpha(0) end
        end
    end
end

local function ApplyGlow(btn, glowType, cr, cg, cb)
    if glowType == 0 then return end
    local entry = GLOW_TYPES[glowType]; if not entry then return end
    if not btn._eabrGlowWrapper then
        local w = CreateFrame("Frame", nil, btn); w:SetAllPoints(btn); w:SetFrameLevel(btn:GetFrameLevel()+1)
        btn._eabrGlowWrapper = w
    end
    local wrapper = btn._eabrGlowWrapper; local sz = btn:GetWidth() or ICON_SIZE
    StopAllGlows(wrapper)
    if entry.procedural then StartPixelGlow(wrapper, sz, cr, cg, cb)
    elseif entry.buttonGlow then StartButtonGlow(wrapper, sz, cr, cg, cb, 1.36)
    elseif entry.autocast then StartAutoCastShine(wrapper, sz, cr, cg, cb, 1.0)
    else StartFlipBookGlow(wrapper, sz, entry, cr, cg, cb) end
    wrapper:Show()
end

local function RemoveGlow(btn)
    if btn._eabrGlowWrapper then StopAllGlows(btn._eabrGlowWrapper); btn._eabrGlowWrapper:Hide() end
end

local function GetOrCreateIcon(index)
    if iconPool[index] then return iconPool[index] end
    -- SecureActionButtonTemplate for click-to-cast in combat
    local btn = CreateFrame("Button", "EABR_Icon"..index, iconAnchor, "SecureActionButtonTemplate")
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "MiddleButtonUp")
    btn:SetPassThroughButtons("RightButton")
    btn:SetFrameStrata("HIGH")
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

    -- 1px black border
    local PP = EllesmereUI and EllesmereUI.PP
    local function mkBorder(a1, a2, isH)
        local t = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(0, 0, 0, 1)
        if PP then PP.DisablePixelSnap(t)
        elseif t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        PP.Point(t, a1, btn, a1, 0, 0)
        PP.Point(t, a2, btn, a2, 0, 0)
        if isH then PP.Height(t, 1) else PP.Width(t, 1) end
    end
    mkBorder("TOPLEFT","TOPRIGHT",true); mkBorder("BOTTOMLEFT","BOTTOMRIGHT",true)
    mkBorder("TOPLEFT","BOTTOMLEFT",false); mkBorder("TOPRIGHT","BOTTOMRIGHT",false)

    -- Text label below icon
    local text = btn:CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    text:SetFont("Fonts\\ARIALN.TTF", 11)
    text:SetShadowOffset(1, -1)
    text:SetTextColor(1, 1, 1, 1)
    btn._text = text



    iconPool[index] = btn
    return btn
end

local function GetOrCreateTalentIcon(index)
    if talentIconPool[index] then return talentIconPool[index] end
    local btn = CreateFrame("Button", "EABR_TalentIcon"..index, talentIconAnchor, "SecureActionButtonTemplate")
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    btn:SetPassThroughButtons("RightButton", "MiddleButton")
    btn:SetFrameStrata("HIGH")
    btn:Hide()
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn._icon = icon
    local PP = EllesmereUI and EllesmereUI.PP
    local function mkBorder(a1, a2, isH)
        local t = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(0, 0, 0, 1)
        if PP then PP.DisablePixelSnap(t)
        elseif t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        PP.Point(t, a1, btn, a1, 0, 0)
        PP.Point(t, a2, btn, a2, 0, 0)
        if isH then PP.Height(t, 1) else PP.Width(t, 1) end
    end
    mkBorder("TOPLEFT","TOPRIGHT",true); mkBorder("BOTTOMLEFT","BOTTOMRIGHT",true)
    mkBorder("TOPLEFT","BOTTOMLEFT",false); mkBorder("TOPRIGHT","BOTTOMRIGHT",false)
    local text = btn:CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    text:SetFont("Fonts\\ARIALN.TTF", 11)
    text:SetShadowOffset(1, -1)
    text:SetTextColor(1, 1, 1, 1)
    btn._text = text
    talentIconPool[index] = btn
    return btn
end

-- Configure a button for spell casting
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

-- Configure a button for item use
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

-- Configure a button for macro text
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
--  Core Refresh Logic
-------------------------------------------------------------------------------
local refreshQueued = false
local pendingOOCRefresh = false

local function HideAllIcons()
    if InCombat() then return end  -- cannot hide SecureActionButtons in combat
    for i = 1, #activeIcons do
        local btn = activeIcons[i]
        if btn then RemoveGlow(btn); btn._text:SetText(""); btn:Hide() end
    end
    wipe(activeIcons)
    for i = 1, #talentActiveIcons do
        local btn = talentActiveIcons[i]
        if btn then RemoveGlow(btn); btn._text:SetText(""); btn:Hide() end
    end
    wipe(talentActiveIcons)
    if talentIconAnchor then talentIconAnchor:Hide() end
end

local function LayoutIcons()
    local count = #activeIcons; if count == 0 then return end
    local p = db.profile.display
    local spacing = p.iconSpacing or 8
    local baseScale = p.scale or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    local totalW = (count * sz) + ((count-1) * spacing)
    local startX = -(totalW/2) + (sz/2)
    for i, btn in ipairs(activeIcons) do
        btn:SetSize(sz, sz)
        btn:SetAlpha(p.opacity or 1.0)
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", iconAnchor, "CENTER", startX + (i-1)*(sz+spacing), 0)
    end
end

local function ShowIcon(iconIdx, setupFn, dismissKey)
    local btn = GetOrCreateIcon(iconIdx)
    btn._dismissKey = dismissKey or nil
    setupFn(btn)
    local p = db.profile.display
    local glowType = p.glowType or 0
    local gc = p.glowColor or {r=1, g=0.776, b=0.376}
    RemoveGlow(btn)
    ApplyGlow(btn, glowType, gc.r, gc.g, gc.b)
    if p.showText then
        local tc = p.textColor or {r=1, g=1, b=1}
        local fontPath = ResolveFontPath(p.textFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        btn._text:SetFont(fontPath, textSize, "")
        btn._text:SetShadowOffset(1, -1)
        btn._text:ClearAllPoints()
        btn._text:SetPoint("TOP", btn, "BOTTOM", xOff, yOff)
        btn._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        btn._text:Show()
    else
        btn._text:SetText("")
        btn._text:Hide()
    end
    btn:Show()
    activeIcons[#activeIcons+1] = btn
end

local function LayoutTalentIcons()
    local count = #talentActiveIcons; if count == 0 then return end
    local p = db.profile.display
    local spacing = p.iconSpacing or 8
    local baseScale = p.scale or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    local totalW = (count * sz) + ((count-1) * spacing)
    local startX = -(totalW/2) + (sz/2)
    for i, btn in ipairs(talentActiveIcons) do
        btn:SetSize(sz, sz)
        btn:SetAlpha(p.opacity or 1.0)
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", talentIconAnchor, "CENTER", startX + (i-1)*(sz+spacing), 0)
    end
end

local function ShowTalentIcon(iconIdx, setupFn)
    local btn = GetOrCreateTalentIcon(iconIdx)
    setupFn(btn)
    local p = db.profile.display
    local glowType = p.glowType or 0
    local gc = p.glowColor or {r=1, g=0.776, b=0.376}
    RemoveGlow(btn)
    ApplyGlow(btn, glowType, gc.r, gc.g, gc.b)
    if p.showText then
        local tc = p.textColor or {r=1, g=1, b=1}
        local fontPath = ResolveFontPath(p.textFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        btn._text:SetFont(fontPath, textSize, "")
        btn._text:SetShadowOffset(1, -1)
        btn._text:ClearAllPoints()
        btn._text:SetPoint("TOP", btn, "BOTTOM", xOff, yOff)
        btn._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        btn._text:Show()
    else
        btn._text:SetText("")
        btn._text:Hide()
    end
    btn:Show()
    talentActiveIcons[#talentActiveIcons+1] = btn
end

local function Refresh()
    if not db then return end
    if euiPanelOpen then HideCombatIcons(); HideAllIcons(); return end

    -- Hide all reminders while skyriding (mounted + flying) or in a vehicle.
    -- Both IsMounted/IsFlying/UnitInVehicle are safe in combat (no taint).
    if UnitInVehicle("player") or (IsMounted() and IsFlying()) then
        HideCombatIcons(); HideCursorIcons()
        if InCombat() then
            FadeOutSecureIcons()
        else
            HideAllIcons()
        end
        return
    end

    CacheInstanceInfo()

    local playerClass = GetPlayerClass()
    local specID = GetSpecID()
    local inInstance = InRealInstancedContent()
    local inKeystone = InMythicPlusKey()
    local inCombat = InCombat()
    local iconIdx = 0

    -- Collect missing reminders
    local missing = {}

    ---------------------------------------------------------------------------
    --  1) Raid Buffs
    ---------------------------------------------------------------------------
    local rb = db.profile.raidBuffs
    if inInstance or rb.showNonInstanced then
        for _, buff in ipairs(RAID_BUFFS) do
            if rb.enabled[buff.key] and (buff.class == playerClass) and Known(buff.castSpell) then
                -- In combat, skip buffs whose IDs are not all whitelisted
                local canCheck = true
                if inCombat then
                    for _, id in ipairs(buff.buffIDs) do
                        if not NON_SECRET_SPELL_IDS[id] then canCheck = false; break end
                    end
                end
                if canCheck then
                    local isMissing = false
                    if rb.showOthersMissing and (IsInGroup() or IsInRaid()) then
                        isMissing = AnyGroupMemberMissingBuff(buff.buffIDs)
                    else
                        isMissing = not PlayerHasAuraByID(buff.buffIDs)
                    end
                    if isMissing then
                        missing[#missing+1] = {
                            cat = "raidbuff", data = buff, scale = rb.scale or 1.0,
                            setup = function(btn)
                                SetIconSpell(btn, buff.castSpell, Tex(buff.castSpell), buff.name)
                                btn._text:SetText(ShortLabel(buff.name))
                            end,
                        }
                    end
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    --  2) Auras
    ---------------------------------------------------------------------------
    local au = db.profile.auras
    if inInstance or au.showNonInstanced then
        for _, aura in ipairs(AURAS) do
            if au.enabled[aura.key] and (aura.class == playerClass) and Known(aura.castSpell) then
                -- Spec check
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
                end
                if specOk then
                    -- Combat: skip if not combatOk or buffIDs not all whitelisted
                    local canCheck = true
                    if inCombat then
                        if not aura.combatOk then
                            canCheck = false
                        else
                            for _, id in ipairs(aura.buffIDs) do
                                if not NON_SECRET_SPELL_IDS[id] then canCheck = false; break end
                            end
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
                                -- In combat, sourceUnit is unreliable; use pre-combat snapshot
                                local cached = _preCombatOwnOnRaidCache[aura.buffIDs[1]]
                                isMissing = (cached == false)
                            else
                                isMissing = not PlayerOwnBuffOnAnyGroupMember(aura.buffIDs)
                            end
                            if not (IsInGroup() or IsInRaid()) then isMissing = false end
                        elseif aura.check == "playerSelfCast" then
                            -- Player must have the buff from their OWN cast
                            isMissing = not PlayerHasSelfCastAuraByID(aura.buffIDs)
                        else
                            isMissing = not PlayerHasAuraByID(aura.buffIDs)
                        end
                        if isMissing then
                            missing[#missing+1] = {
                                cat = "aura", data = aura, scale = au.scale or 1.0,
                                setup = function(btn)
                                    SetIconSpell(btn, aura.castSpell, Tex(aura.castSpell), aura.name)
                                    btn._text:SetText(ShortLabel(aura.name))
                                end,
                            }
                        end
                    end
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    --  3) Consumables (mostly OOC only, not during keystones)
    --     "Specials" (poisons, rites, imbues) respect showSpecialsNonInstanced
    --     Shaman Shields run in AND out of combat (non-secret spell IDs)
    --     Everything else (runes, weapon enchants, flask, food) is instance-only
    ---------------------------------------------------------------------------
    local co = db.profile.consumables
    local specialsActive = inInstance or co.showSpecialsNonInstanced
    if not inKeystone then
        -- Only check consumables out of combat (secret value protection)
        if not inCombat then

            -- === SPECIALS (respect showSpecialsNonInstanced) ===
            if specialsActive then
                -- Rogue Poisons
                if playerClass == "ROGUE" then
                    for _, poison in ipairs(ROGUE_POISONS) do
                        if co.enabled[poison.key] and Known(poison.castSpell) then
                            if not PlayerHasAuraByID(poison.buffIDs) then
                                missing[#missing+1] = {
                                    cat = "consumable", data = poison, scale = co.scale or 1.0,
                                    setup = function(btn)
                                        SetIconSpell(btn, poison.castSpell, Tex(poison.castSpell), poison.name)
                                        btn._text:SetText(ShortLabel(poison.name, "ROGUE"))
                                    end,
                                }
                            end
                        end
                    end
                end

                -- Paladin Rites
                if playerClass == "PALADIN" then
                    for _, rite in ipairs(PALADIN_RITES) do
                        if co.enabled[rite.key] and Known(rite.castSpell) then
                            local hasMH = GetWeaponEnchantInfo()
                            if not hasMH then
                                missing[#missing+1] = {
                                    cat = "consumable", data = rite, scale = co.scale or 1.0,
                                    setup = function(btn)
                                        SetIconSpell(btn, rite.castSpell, Tex(rite.castSpell), rite.name)
                                        btn._text:SetText(ShortLabel(rite.name))
                                    end,
                                }
                            end
                        end
                    end
                end

                -- Shaman Imbues
                if playerClass == "SHAMAN" then
                    for _, imbue in ipairs(SHAMAN_IMBUES) do
                        if co.enabled[imbue.key] and Known(imbue.castSpell) then
                            local hasMH = GetWeaponEnchantInfo()
                            if not hasMH then
                                missing[#missing+1] = {
                                    cat = "consumable", data = imbue, scale = co.scale or 1.0,
                                    setup = function(btn)
                                        SetIconSpell(btn, imbue.castSpell, Tex(imbue.castSpell), imbue.name)
                                        btn._text:SetText(ShortLabel(imbue.name, "SHAMAN_IMBUE"))
                                    end,
                                }
                            end
                        end
                    end

                    -- Shaman Shields (OOC only â€” LS, WS are not non-secret)
                    -- Earth Shield is handled separately below (combat-safe).
                    for _, shield in ipairs(SHAMAN_SHIELDS) do
                        if shield.key ~= "es" and co.enabled[shield.key] and Known(shield.castSpell) then
                            local specOk = true
                            if shield.specs then
                                specOk = false
                                for _, s in ipairs(shield.specs) do if s == specID then specOk = true; break end end
                            end
                            if specOk then
                                if not PlayerHasAuraByID(shield.buffIDs) then
                                    missing[#missing+1] = {
                                        cat = "consumable", data = shield, scale = co.scale or 1.0,
                                        setup = function(btn)
                                            SetIconSpell(btn, shield.castSpell, Tex(shield.castSpell), shield.name)
                                            btn._text:SetText(ShortLabel(shield.name, "SHAMAN_SHIELD"))
                                        end,
                                    }
                                end
                            end
                        end
                    end

                end
            end -- end specialsActive

            -- === INSTANCE-ONLY CONSUMABLES (runes, weapon enchants, flask, food, inky black) ===
            if inInstance then

            -- Augment Runes (display mode: mythic, heroic_mythic, or all)
            if co.enabled.augment_rune then
                local runeMode = co.runeDisplayMode or "mythic"
                local showRune = false
                if runeMode == "mythic" then
                    showRune = InMythicZeroDungeonOrMythicRaid()
                elseif runeMode == "heroic_mythic" then
                    showRune = InHeroicOrMythicContent()
                elseif runeMode == "all" then
                    showRune = InRealInstancedContent()
                end
                if showRune then
                    local hasRuneBuff = PlayerHasAuraByID(RUNE_BUFF_IDS)
                    if not hasRuneBuff then
                        local voidCount = GetItemCount(AUGMENT_RUNE_VOID, false) or 0
                        local etherCount = GetItemCount(AUGMENT_RUNE_ETHER, false) or 0
                        local runeItem = nil
                        if voidCount > 0 then runeItem = AUGMENT_RUNE_VOID
                        elseif etherCount > 0 then runeItem = AUGMENT_RUNE_ETHER end
                        if runeItem then
                            missing[#missing+1] = {
                                cat = "consumable", dismissKey = "consumable:rune", scale = co.scale or 1.0,
                                setup = function(btn)
                                    SetIconItem(btn, runeItem, GetItemIcon(runeItem), "Augment Rune")
                                    btn._text:SetText(ShortLabel("Augment Rune"))
                                end,
                            }
                        end
                    end
                end
            end

            -- Weapon Enchants (temp weapon enchant items)
            if co.enabled.weapon_enchant then
                local hasMH, _, _, _, hasOH = GetWeaponEnchantInfo()
                local mhCat = GetWeaponCategory(16)
                local ohCat = GetWeaponCategory(17)

                -- Determine which slot needs an enchant: prefer MH, fall back to OH
                local targetSlot, targetCat
                if mhCat and not hasMH then
                    targetSlot = 16
                    targetCat = mhCat
                elseif ohCat and hasMH and not hasOH then
                    targetSlot = 17
                    targetCat = ohCat
                end

                if targetSlot and targetCat then
                    local preferredKey = co.preferredWeaponEnchant or "last_used"
                    local lastUsedID = db.char and db.char.lastUsedWeaponEnchant or nil
                    local bestItemID = FindWeaponEnchantItem(preferredKey, lastUsedID, targetCat)
                    if not bestItemID then
                        -- Fallback: any matching weapon enchant in bags
                        for _, we in ipairs(WEAPON_ENCHANT_ITEMS) do
                            local wt = we.weaponType
                            if ((wt == "NEUTRAL") or (wt == targetCat)) and (GetItemCount(we.itemID, false) or 0) > 0 then
                                bestItemID = we.itemID; break
                            end
                        end
                    end
                    if bestItemID then
                        local slot = targetSlot
                        local bestIcon = GetItemIcon(bestItemID) or 134400
                        missing[#missing+1] = {
                            cat = "consumable", dismissKey = "consumable:weapon_enchant", scale = co.scale or 1.0,
                            setup = function(btn)
                                local macro = "/use item:" .. bestItemID .. "\n/use " .. slot
                                SetIconMacro(btn, macro, bestIcon, nil)
                                btn._tooltipItem = bestItemID
                                btn._text:SetText(ShortLabel("Weapon Enchant"))
                            end,
                        }
                    end
                end
            end

            -- Flask (OOC only, not during keystones â€” buff is secret)
            if co.enabled.flask then
                if not PlayerHasFlaskBuff() then
                    local preferredKey = co.preferredFlask or "last_used"
                    local lastUsedID = db.char and db.char.lastUsedFlask or nil
                    local flaskItemID = FindFlaskItem(preferredKey, lastUsedID)
                    if flaskItemID then
                        local flaskIcon = GetItemIcon(flaskItemID) or 134830
                        missing[#missing+1] = {
                            cat = "consumable", dismissKey = "consumable:flask", scale = co.scale or 1.0,
                            setup = function(btn)
                                SetIconItem(btn, flaskItemID, flaskIcon, "Flask")
                                btn._text:SetText("Flask")
                            end,
                        }
                    end
                end
            end

            -- Food / Well Fed (OOC only, not during keystones â€” buff is secret)
            if co.enabled.food then
                if not PlayerHasWellFed() then
                    local preferredKey = co.preferredFood or "last_used"
                    local lastUsedID = db.char and db.char.lastUsedFood or nil
                    local foodItemID = FindFoodItem(preferredKey, lastUsedID)
                    if foodItemID then
                        local foodIcon = GetItemIcon(foodItemID) or 134062
                        missing[#missing+1] = {
                            cat = "consumable", dismissKey = "consumable:food", scale = co.scale or 1.0,
                            setup = function(btn)
                                SetIconItem(btn, foodItemID, foodIcon, "Food")
                                btn._text:SetText("Food")
                            end,
                        }
                    end
                end
            end

            -- Inky Black Potion (zone-specific)
            if co.enabled.inky_black then
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
                        local hasPotion = (GetItemCount(INKY_BLACK_ITEM, false) or 0) > 0
                        local hasBuff = PlayerHasBuffByName("Inky Black Potion")
                        if not hasBuff and hasPotion then
                            missing[#missing+1] = {
                                cat = "consumable", dismissKey = "consumable:inky_black", scale = co.scale or 1.0,
                                setup = function(btn)
                                    SetIconItem(btn, INKY_BLACK_ITEM, GetItemIcon(INKY_BLACK_ITEM), "Inky Black Potion")
                                    btn._text:SetText(ShortLabel("Inky Black Potion"))
                                end,
                            }
                        end
                    end
                end
            end
            end -- end inInstance
        end -- end not inCombat

        -- Earth Shield (elemental orbit) â€” safe in combat, spell IDs 974 and
        -- 383648 are non-secret.  Uses GetUnitAuraBySpellID for group checks.
        -- Other shaman shields (LS, WS) remain OOC-only above.
        if specialsActive and playerClass == "SHAMAN" then
            for _, shield in ipairs(SHAMAN_SHIELDS) do
                if shield.key == "es" and co.enabled[shield.key] and Known(shield.castSpell) then
                    local specOk = true
                    if shield.specs then
                        specOk = false
                        for _, s in ipairs(shield.specs) do if s == specID then specOk = true; break end end
                    end
                    if specOk then
                        local isMissing = false
                        if shield.orbitTalent and Known(shield.orbitTalent) then
                            local selfHas = PlayerHasAuraByID(shield.selfOrbitBuff)
                            local otherHas = PlayerOwnBuffOnAnyGroupMember(shield.otherBuff)
                            isMissing = not selfHas or (not otherHas and (IsInGroup() or IsInRaid()))
                        else
                            isMissing = not PlayerHasAuraByID(shield.buffIDs)
                        end
                        if isMissing then
                            missing[#missing+1] = {
                                cat = "consumable", data = shield, scale = co.scale or 1.0,
                                setup = function(btn)
                                    SetIconSpell(btn, shield.castSpell, Tex(shield.castSpell), shield.name)
                                    btn._text:SetText(ShortLabel(shield.name, "SHAMAN_SHIELD"))
                                end,
                            }
                        end
                    end
                end
            end
        end

    end -- end consumables

    ---------------------------------------------------------------------------
    --  4) Talent Reminders (OOC only, not during keystones)
    ---------------------------------------------------------------------------
    local talentMissing = {}
    if not inKeystone and not inCombat and inInstance then
        local reminders = db.profile.talentReminders
        if reminders and #reminders > 0 then
            local currentInstance = GetCurrentInstanceName()
            if currentInstance then
                for _, reminder in ipairs(reminders) do
                    -- Match by instance name
                    local zoneMatch = false
                    if reminder._nameSet then
                        zoneMatch = reminder._nameSet[currentInstance] or false
                    elseif reminder.zoneNames then
                        local s = {}
                        for _, zn in ipairs(reminder.zoneNames) do s[zn] = true end
                        reminder._nameSet = s
                        zoneMatch = s[currentInstance] or false
                    end

                    local hasTalent = IsPlayerSpell(reminder.spellID) or IsSpellKnown(reminder.spellID)

                    if zoneMatch and not hasTalent then
                        local rSpellID = reminder.spellID
                        local rSpellName = reminder.spellName or "Unknown"
                        local rIcon = Tex(rSpellID) or 134400
                        talentMissing[#talentMissing+1] = {
                            cat = "talent", scale = 1.0,
                            setup = function(btn)
                                if not InCombat() then
                                    btn:SetAttribute("type", nil)
                                    btn:SetAttribute("spell", nil)
                                    btn:SetAttribute("item", nil)
                                    btn:SetAttribute("macrotext", nil)
                                end
                                btn._icon:SetTexture(rIcon)
                                btn._tooltipSpell = rSpellID
                                btn._tooltipItem = nil
                                btn._text:SetText(rSpellName)
                            end,
                        }
                    elseif not zoneMatch and reminder.showNotNeeded and hasTalent then
                        local rSpellID = reminder.spellID
                        local rSpellName = (reminder.spellName or "Unknown")
                        local rIcon = Tex(rSpellID) or 134400
                        talentMissing[#talentMissing+1] = {
                            cat = "talent", scale = 1.0,
                            setup = function(btn)
                                if not InCombat() then
                                    btn:SetAttribute("type", nil)
                                    btn:SetAttribute("spell", nil)
                                    btn:SetAttribute("item", nil)
                                    btn:SetAttribute("macrotext", nil)
                                end
                                btn._icon:SetTexture(rIcon)
                                btn._tooltipSpell = rSpellID
                                btn._tooltipItem = nil
                                btn._text:SetText(rSpellName .. " (N/N)")
                            end,
                        }
                    end
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Apply results
    ---------------------------------------------------------------------------
    if inCombat then
        -- Combat path: use non-secure visual-only icons.
        -- Fade out stale secure buttons (SetAlpha is safe during combat).
        FadeOutSecureIcons()
        HideCombatIcons()
        HideCursorIcons()
        if #missing > 0 then
            local useCursor = db.profile.display.cursorAttach and cursorAnchor
            local combatIdx, cursorIdx = 0, 0
            for _, m in ipairs(missing) do
                -- Skip middle-click dismissed reminders
                local dk = m.dismissKey or (m.data and m.data.key and (m.cat .. ":" .. m.data.key)) or nil
                if not (dk and _dismissedUntilLoad[dk]) then
                    -- Only show reminders whose buff IDs are ALL whitelisted non-secret.
                    -- Anything else must never appear during combat.
                    local safe = false
                    if m.data and m.data.buffIDs then
                        safe = true
                        for _, id in ipairs(m.data.buffIDs) do
                            if not NON_SECRET_SPELL_IDS[id] then safe = false; break end
                        end
                    end
                    if safe then
                        local spellID = m.data and m.data.castSpell
                        local texture = spellID and Tex(spellID) or 134400
                        local label = m.data and ShortLabel(m.data.name) or ""
                        if useCursor and IsImportantBuff(m) then
                            cursorIdx = cursorIdx + 1
                            ShowCursorIcon(cursorIdx, spellID, texture, label)
                        else
                            combatIdx = combatIdx + 1
                            ShowCombatIcon(combatIdx, spellID, texture, label)
                        end
                    end
                end
            end
            if combatIdx > 0 then combatAnchor:Show(); LayoutCombatIcons() end
            if cursorIdx > 0 then cursorAnchor:Show(); LayoutCursorIcons() end
        end
        return
    end

    -- OOC path: full secure button display
    HideCombatIcons()
    HideCursorIcons()
    HideAllIcons()

    if #missing > 0 then
        local iconIdx = 0
        for _, m in ipairs(missing) do
            local dk = m.dismissKey or (m.data and m.data.key and (m.cat .. ":" .. m.data.key)) or nil
            if not dk or not _dismissedUntilLoad[dk] then
                iconIdx = iconIdx + 1
                ShowIcon(iconIdx, m.setup, dk)
            end
        end
        if iconIdx > 0 then
            LayoutIcons()
            iconAnchor:Show()
        end
    end

    -- Talent reminders on a separate anchor below the main icons
    if #talentMissing > 0 and talentIconAnchor then
        for i, m in ipairs(talentMissing) do
            ShowTalentIcon(i, m.setup)
        end
        LayoutTalentIcons()
        talentIconAnchor:Show()
    end
end

local function RequestRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        Refresh()
    end)
end


-------------------------------------------------------------------------------
--  Unlock Mode
-------------------------------------------------------------------------------
local function ApplyUnlockPos()
    if not iconAnchor or not db then return end
    local pos = db.profile.unlockPos
    if pos and pos.point then
        if pos.scale then pcall(function() iconAnchor:SetScale(pos.scale) end) end
        iconAnchor:ClearAllPoints()
        iconAnchor:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        local d = db.profile.display
        pcall(function() iconAnchor:SetScale(1) end)
        iconAnchor:ClearAllPoints()
        iconAnchor:SetPoint("CENTER", UIParent, "CENTER", d.xOffset or 0, d.yOffset or 0)
    end
end

local function RegisterUnlockElements()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    EllesmereUI:RegisterUnlockElements({
        {
            key = "EABR_Reminders",
            label = "AuraBuff Reminders",
            group = "AuraBuff Reminders",
            order = 600,
            getFrame = function() return iconAnchor end,
            getSize = function()
                local p = db.profile.display
                local baseScale = p.scale or 1.0
                local sz = floor(ICON_SIZE * baseScale + 0.5)
                local spacing = p.iconSpacing or 8
                -- Size to fit 3 icons wide (typical max visible)
                local count = max(#activeIcons, 3)
                local w = count * sz + (count - 1) * spacing
                -- Height: icon + gap + text line
                local textH = 0
                if p.showText then
                    textH = (p.textSize or 11) + abs(p.textYOffset or -2)
                end
                local h = sz + textH
                -- Offset mover center down by half the text overhang
                return w, h, -(textH / 2)
            end,
            savePosition = function(key, point, relPoint, x, y, scale)
                db.profile.unlockPos = {point=point, relPoint=relPoint, x=x, y=y, scale=scale}
                ApplyUnlockPos()
            end,
            loadPosition = function()
                return db.profile.unlockPos
            end,
            getScale = function()
                local pos = db.profile.unlockPos
                return pos and pos.scale or 1.0
            end,
            clearPosition = function()
                db.profile.unlockPos = nil
            end,
            applyPosition = function()
                ApplyUnlockPos()
            end,
        },
    })
end

-------------------------------------------------------------------------------
--  Last-Used Item Tracking (per-character)
-------------------------------------------------------------------------------
local FLASK_ITEM_SET = {}
for _, f in ipairs(FLASK_ITEMS) do
    for _, id in ipairs(f.items) do FLASK_ITEM_SET[id] = true end
end

local FOOD_ITEM_SET = {}
for _, f in ipairs(FOOD_ITEMS) do FOOD_ITEM_SET[f.itemID] = true end

local WEAPON_ENCHANT_ITEM_SET = {}
for _, we in ipairs(WEAPON_ENCHANT_ITEMS) do WEAPON_ENCHANT_ITEM_SET[we.itemID] = true end

local function TrackItemUse(itemID)
    if not db or not db.char then return end
    if FLASK_ITEM_SET[itemID] then
        db.char.lastUsedFlask = itemID
    elseif FOOD_ITEM_SET[itemID] then
        db.char.lastUsedFood = itemID
    elseif WEAPON_ENCHANT_ITEM_SET[itemID] then
        db.char.lastUsedWeaponEnchant = itemID
    end
end

-------------------------------------------------------------------------------
--  MAIN EVENT HANDLER
-------------------------------------------------------------------------------
local mainFrame = CreateFrame("Frame")

mainFrame:SetScript("OnEvent", function(_, e, arg1, arg2)
    -- Skip all processing if user has disabled this addon
    if EllesmereUIDB and EllesmereUIDB.disabledAddons and EllesmereUIDB.disabledAddons[ADDON_NAME] then return end

    if e == "PLAYER_LOGIN" then
        db = EllesmereUI.Lite.NewDB("EllesmereUIAuraBuffRemindersDB", defaults, true)

        -- Migration: Source of Magic moved from raidBuffs to auras
        if db.profile.raidBuffs and db.profile.raidBuffs.enabled and db.profile.raidBuffs.enabled.som ~= nil then
            if db.profile.auras and db.profile.auras.enabled then
                if db.profile.auras.enabled.som == nil then
                    db.profile.auras.enabled.som = db.profile.raidBuffs.enabled.som
                end
            end
            db.profile.raidBuffs.enabled.som = nil
        end

        -- Minimap button (shared across all Ellesmere addons â€” first to load wins)
        -- Minimap button (handled by parent addon)
        if not _EllesmereUI_MinimapRegistered and EllesmereUI and EllesmereUI.CreateMinimapButton then
            EllesmereUI.CreateMinimapButton()
        end

        -- Expose globals for options
        _G._EABR_AceDB = db
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
        _G._EABR_fontPaths = fontPaths
        _G._EABR_FLASK_ITEMS = FLASK_ITEMS
        _G._EABR_FOOD_ITEMS = FOOD_ITEMS
        _G._EABR_WEAPON_ENCHANT_CHOICES = WEAPON_ENCHANT_CHOICES
        _G._EABR_TALENT_REMINDER_ZONES = TALENT_REMINDER_ZONES

        -- Create anchor
        iconAnchor = CreateFrame("Frame", "EABR_Anchor", UIParent)
        iconAnchor:SetSize(1, 1)
        iconAnchor:SetFrameStrata("HIGH")
        iconAnchor:EnableMouse(false)
        ApplyUnlockPos()

        -- Create combat anchor (non-secure, follows iconAnchor position)
        -- Parented to UIParent so Show/Hide is never blocked by combat lockdown.
        combatAnchor = CreateFrame("Frame", "EABR_CombatAnchor", UIParent)
        combatAnchor:SetSize(1, 1)
        combatAnchor:SetFrameStrata("HIGH")
        combatAnchor:SetFrameLevel(110)
        combatAnchor:EnableMouse(false)
        combatAnchor:SetAllPoints(iconAnchor)
        combatAnchor:Hide()

        -- Create cursor-attached anchor for important buffs.
        -- Parents to EllesmereUICursorFrame if it exists (the cursor circle
        -- addon's tracking frame â€” already has an OnUpdate for cursor position).
        -- Falls back to UIParent center if cursor addon isn't loaded.
        local cursorParent = _G.EllesmereUICursorFrame or UIParent
        cursorAnchor = CreateFrame("Frame", "EABR_CursorAnchor", cursorParent)
        cursorAnchor:SetSize(1, 1)
        cursorAnchor:SetFrameStrata("TOOLTIP")
        cursorAnchor:SetFrameLevel(9980)
        cursorAnchor:EnableMouse(false)
        cursorAnchor:SetPoint("CENTER", cursorParent, "CENTER", 0, 60)
        cursorAnchor:Hide()

        -- Create talent reminder anchor (offset below main anchor)
        talentIconAnchor = CreateFrame("Frame", "EABR_TalentAnchor", iconAnchor)
        talentIconAnchor:SetSize(1, 1)
        talentIconAnchor:SetFrameStrata("HIGH")
        talentIconAnchor:EnableMouse(false)
        talentIconAnchor:SetPoint("CENTER", iconAnchor, "CENTER", 0, db.profile.talentReminderYOffset or -50)
        talentIconAnchor:Hide()

        -- Hook EUI panel show/hide
        if EllesmereUI then
            if EllesmereUI.RegisterOnShow then
                EllesmereUI:RegisterOnShow(function() euiPanelOpen = true; HideAllIcons() end)
            end
            if EllesmereUI.RegisterOnHide then
                EllesmereUI:RegisterOnHide(function() euiPanelOpen = false; RequestRefresh() end)
            end
        end

        RequestRefresh()
        C_Timer.After(0.5, RegisterUnlockElements)
        return
    end

    if e == "PLAYER_REGEN_DISABLED" then
        -- Entering combat: snapshot aura state, then refresh to switch to combat icons
        SnapshotPlayerAuras()
        SnapshotOwnOnRaidBuffs()
        RequestRefresh()
        return
    end

    if e == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat: clean up combat icons, do full OOC refresh with secure buttons
        HideCombatIcons()
        HideCursorIcons()
        pendingOOCRefresh = false
        RequestRefresh()
        return
    end

    if e == "PLAYER_ENTERING_WORLD" then
        -- Loading screen completed: clear middle-click dismissed reminders
        wipe(_dismissedUntilLoad)
        RequestRefresh()
        return
    end

    if e == "UNIT_AURA" then
        if arg1 == "player" then
            RequestRefresh()
        elseif type(arg1) == "string" and (arg1:match("^party") or arg1:match("^raid")) then
            RequestRefresh()
        end
        return
    end

    if e == "UNIT_ENTERED_VEHICLE" or e == "UNIT_EXITED_VEHICLE" then
        if arg1 == "player" then RequestRefresh() end
        return
    end

    -- All other events: just refresh
    RequestRefresh()
end)

-- Item use tracking via bag snapshot diffing on BAG_UPDATE_DELAYED
local lastBagSnapshot = {}

local function SnapshotBags()
    local snap = {}
    for bag = 0, 4 do
        local numSlots = C_Container and C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container and C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                snap[info.itemID] = (snap[info.itemID] or 0) + info.stackCount
            end
        end
    end
    return snap
end

local function DetectUsedItem()
    if not db or not db.char then return end
    local newSnap = SnapshotBags()
    for itemID, oldCount in pairs(lastBagSnapshot) do
        local newCount = newSnap[itemID] or 0
        if newCount < oldCount then
            TrackItemUse(itemID)
        end
    end
    lastBagSnapshot = newSnap
end

local bagTrackFrame = CreateFrame("Frame")
bagTrackFrame:RegisterEvent("BAG_UPDATE_DELAYED")
bagTrackFrame:RegisterEvent("PLAYER_LOGIN")
bagTrackFrame:SetScript("OnEvent", function(_, ev)
    if ev == "PLAYER_LOGIN" then
        C_Timer.After(1, function() lastBagSnapshot = SnapshotBags() end)
    elseif ev == "BAG_UPDATE_DELAYED" then
        DetectUsedItem()
    end
end)

mainFrame:RegisterEvent("PLAYER_LOGIN")
mainFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
mainFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
mainFrame:RegisterEvent("SPELLS_CHANGED")
mainFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
mainFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
mainFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
mainFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
mainFrame:RegisterUnitEvent("UNIT_AURA", "player")
mainFrame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
mainFrame:RegisterEvent("CHALLENGE_MODE_START")
mainFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
mainFrame:RegisterEvent("CHALLENGE_MODE_RESET")
mainFrame:RegisterEvent("BAG_UPDATE")
mainFrame:RegisterEvent("WEAPON_ENCHANT_CHANGED")
mainFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
mainFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
mainFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")

-------------------------------------------------------------------------------
--  /eabr debug â€” prints full diagnostic state to chat
-------------------------------------------------------------------------------
SLASH_EABRDEBUG1 = "/eabrdebug"
SlashCmdList["EABRDEBUG"] = function()

    local p = function(...) print("|cff0cd29f[EABR Debug]|r", ...) end
    p("--- AuraBuff Reminders Debug ---")

    if not db then p("|cffff4444db is nil â€” PLAYER_LOGIN never fired or AceDB failed|r"); return end

    local playerClass = GetPlayerClass()
    local specID = GetSpecID()
    local specIdx = GetSpecialization()
    local specName = specIdx and select(2, GetSpecializationInfo(specIdx)) or "?"
    CacheInstanceInfo()
    local inInstance = InRealInstancedContent()
    local inKeystone = InMythicPlusKey()
    local inCombat = InCombat()
    local inGroup = IsInGroup()
    local inRaid = IsInRaid()

    p("Class:", playerClass, "| Spec:", specID, "(" .. specName .. ")")
    p("InInstance:", tostring(inInstance), "| InKeystone:", tostring(inKeystone), "| InCombat:", tostring(inCombat))
    p("InGroup:", tostring(inGroup), "| InRaid:", tostring(inRaid))
    p("EUI panel open:", tostring(euiPanelOpen))
    p("iconAnchor:", iconAnchor and "exists" or "|cffff4444NIL|r",
      iconAnchor and ("shown=" .. tostring(iconAnchor:IsShown())) or "")
    p("Active icons:", #activeIcons)
    p("Combat icons:", #combatActiveIcons)

    -- Raid Buffs
    local rb = db.profile.raidBuffs
    p("--- Raid Buffs ---")
    p("  showNonInstanced:", tostring(rb.showNonInstanced), "| showOthersMissing:", tostring(rb.showOthersMissing))
    local rbActive = inInstance or rb.showNonInstanced
    p("  Category active (inInstance or showNonInstanced):", tostring(rbActive))
    if rbActive then
        for _, buff in ipairs(RAID_BUFFS) do
            local enabled = rb.enabled[buff.key]
            local classMatch = buff.class == playerClass
            local known = Known(buff.castSpell)
            local status = ""
            if not enabled then status = "DISABLED"
            elseif not classMatch then status = "wrong class (" .. buff.class .. ")"
            elseif not known then status = "spell not known"
            else
                local isMissing
                if rb.showOthersMissing and (inGroup or inRaid) then
                    isMissing = AnyGroupMemberMissingBuff(buff.buffIDs)
                else
                    isMissing = not PlayerHasAuraByID(buff.buffIDs)
                end
                status = isMissing and "|cffff4444MISSING|r" or "buff present"
            end
            p("  " .. buff.key .. " (" .. buff.name .. "): " .. status)
        end
    end

    -- Auras
    local au = db.profile.auras
    p("--- Auras ---")
    p("  showNonInstanced:", tostring(au.showNonInstanced))
    local auActive = inInstance or au.showNonInstanced
    p("  Category active:", tostring(auActive))
    if auActive then
        for _, aura in ipairs(AURAS) do
            local enabled = au.enabled[aura.key]
            local classMatch = aura.class == playerClass
            local known = Known(aura.castSpell)
            local specOk = true
            if aura.specs then
                specOk = false
                for _, s in ipairs(aura.specs) do if s == specID then specOk = true; break end end
            end
            local status = ""
            if not enabled then status = "DISABLED"
            elseif not classMatch then status = "wrong class (" .. aura.class .. ")"
            elseif not known then status = "spell not known"
            elseif not specOk then status = "wrong spec"
            elseif aura.requireInstanceGroup and (not inInstance or not (inGroup or inRaid)) then status = "skipped (requireInstanceGroup: not in instance+group)"
            elseif inCombat and not aura.combatOk then status = "skipped (in combat, not combatOk)"
            else
                local isMissing
                if aura.check == "mineOnRaid" then
                    if inCombat then
                        status = "skipped (in combat, mineOnRaid can't check others)"
                    else
                        isMissing = not BuffExistsOnAnyGroupMember(aura.buffIDs)
                        if not (inGroup or inRaid) then isMissing = false; status = "not in group"; end
                    end
                elseif aura.check == "ownOnRaid" then
                    if inCombat then
                        local cached = _preCombatOwnOnRaidCache[aura.buffIDs[1]]
                        isMissing = (cached == false)
                        status = "ownOnRaid (combat snapshot: " .. tostring(cached) .. ")"
                    else
                        isMissing = not PlayerOwnBuffOnAnyGroupMember(aura.buffIDs)
                    end
                    if not (inGroup or inRaid) then isMissing = false; status = "not in group"; end
                elseif aura.check == "playerSelfCast" then
                    isMissing = not PlayerHasSelfCastAuraByID(aura.buffIDs)
                end
                if status == "" then
                    if aura.check ~= "mineOnRaid" and aura.check ~= "ownOnRaid" and aura.check ~= "playerSelfCast" then
                        isMissing = not PlayerHasAuraByID(aura.buffIDs)
                    end
                    status = isMissing and "|cffff4444MISSING â€” should show icon|r" or "buff present"
                end
            end
            p("  " .. aura.key .. " (" .. aura.name .. "): " .. status)
        end
    end

    -- Consumables
    local co = db.profile.consumables
    p("--- Consumables ---")
    p("  inKeystone:", tostring(inKeystone), "| inInstance:", tostring(inInstance))
    p("  showSpecialsNonInstanced:", tostring(co.showSpecialsNonInstanced))
    local specialsActive = inInstance or co.showSpecialsNonInstanced
    local coActive = not inKeystone
    p("  Category active (not inKeystone):", tostring(coActive), "| Specials active:", tostring(specialsActive))
    if coActive and not inCombat then
        if playerClass == "ROGUE" then
            for _, poison in ipairs(ROGUE_POISONS) do
                local enabled = co.enabled[poison.key]
                local known = Known(poison.castSpell)
                local has = PlayerHasAuraByID(poison.buffIDs)
                p("  " .. poison.key .. ": enabled=" .. tostring(enabled) .. " known=" .. tostring(known) .. " hasBuff=" .. tostring(has))
            end
        end
        if playerClass == "SHAMAN" then
            for _, imbue in ipairs(SHAMAN_IMBUES) do
                p("  " .. imbue.key .. ": enabled=" .. tostring(co.enabled[imbue.key]) .. " known=" .. tostring(Known(imbue.castSpell)))
            end
        end
        p("  augment_rune enabled:", tostring(co.enabled.augment_rune), "| inM0/MythicRaid:", tostring(InMythicZeroDungeonOrMythicRaid()))
        p("  weapon_enchant enabled:", tostring(co.enabled.weapon_enchant))
        local hasMH = GetWeaponEnchantInfo()
        p("  MH enchant present:", tostring(hasMH))
    elseif inCombat then
        p("  (skipped â€” in combat)")
    end

    p("--- End Debug ---")
end

-------------------------------------------------------------------------------
--  /eabrcombat â€” targeted combat aura API debug
--  Run this IN COMBAT with Devotion Aura active to diagnose the issue.
-------------------------------------------------------------------------------
SLASH_EABRCOMBAT1 = "/eabrcombat"
SlashCmdList["EABRCOMBAT"] = function()
    local p = function(...) print("|cffff9900[EABR Combat]|r", ...) end
    p("--- Combat Aura Debug ---")
    p("InCombatLockdown:", tostring(InCombatLockdown()))
    p("issecretvalue global:", type(issecretvalue))

    -- Test specific whitelisted spell IDs
    local testIDs = {465, 1126, 1459, 6673, 21562, 462854, 474754, 369459}
    local testNames = {
        [465]="Devotion Aura", [1126]="Mark of the Wild", [1459]="Arcane Intellect", [6673]="Battle Shout",
        [21562]="Fortitude", [462854]="Skyfury", [474754]="Symbiotic", [369459]="Source of Magic",
    }

    for _, id in ipairs(testIDs) do
        local name = testNames[id] or tostring(id)

        -- 1) Secrecy level
        local secrecyStr = "API_MISSING"
        if C_Secrets and C_Secrets.GetSpellAuraSecrecy then
            local secOk, sec = pcall(C_Secrets.GetSpellAuraSecrecy, id)
            if secOk then
                if sec == 0 then secrecyStr = "NeverSecret"
                elseif sec == 1 then secrecyStr = "AlwaysSecret"
                elseif sec == 2 then secrecyStr = "ContextuallySecret"
                else secrecyStr = tostring(sec) end
            else
                secrecyStr = "ERROR:" .. tostring(sec)
            end
        end

        -- 2) ShouldSpellAuraBeSecret
        local shouldBeSecret = "API_MISSING"
        if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
            local sbsOk, sbsVal = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
            shouldBeSecret = sbsOk and tostring(sbsVal) or ("ERROR:" .. tostring(sbsVal))
        end

        -- 3) Raw API call
        local resultStr = "?"
        local resultType = "?"
        local isSecret = "?"
        local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if not ok then
            resultStr = "|cffff4444PCALL_ERROR: " .. tostring(result) .. "|r"
        else
            resultType = type(result)
            local isvOk, isvResult = pcall(issecretvalue, result)
            if not isvOk then
                isSecret = "ERROR:" .. tostring(isvResult)
            else
                isSecret = tostring(isvResult)
            end
            if result == nil then
                resultStr = "nil"
            elseif isvOk and isvResult then
                resultStr = "|cff00ff00SECRET (aura EXISTS)|r"
            elseif result then
                local fieldOk, fieldVal = pcall(function() return result.spellId end)
                if fieldOk then
                    resultStr = "|cff00ff00TABLE spellId=" .. tostring(fieldVal) .. "|r"
                else
                    resultStr = "|cff00ff00TABLE (field err)|r"
                end
            end
        end

        -- 4) Our wrapper
        local wrapperOk, wrapperResult = pcall(PlayerHasAuraByID, {id})
        local wrapperStr
        if not wrapperOk then
            wrapperStr = "|cffff4444ERROR: " .. tostring(wrapperResult) .. "|r"
        else
            wrapperStr = tostring(wrapperResult)
        end

        -- 5) Snapshot value
        local cached = _preCombatAuraCache[id]

        p(name .. " (" .. id .. "):")
        p("  Secrecy=" .. secrecyStr .. " ShouldBeSecret=" .. shouldBeSecret)
        p("  API: type=" .. resultType .. " isSecret=" .. isSecret .. " => " .. resultStr)
        p("  Snapshot=" .. tostring(cached) .. " | PlayerHasAuraByID=" .. wrapperStr)
    end

    p("--- Icon counts ---")
    p("  activeIcons:", #activeIcons, "combatActiveIcons:", #combatActiveIcons)
    p("  NON_SECRET_SPELL_IDS[465]:", tostring(NON_SECRET_SPELL_IDS[465]))

    p("--- End Combat Debug ---")
end

-------------------------------------------------------------------------------
--  /eabrlog â€” toggle live UNIT_AURA payload logging during combat
-------------------------------------------------------------------------------
SLASH_EABRLOG1 = "/eabrlog"
SlashCmdList["EABRLOG"] = function()
    _eabrLogEnabled = not _eabrLogEnabled
    print("|cffff9900[EABR]|r Combat aura logging " .. (_eabrLogEnabled and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
end
