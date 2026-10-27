if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_AuraBuffReminders_Auras.lua
--
--  The pre-combat aura snapshot, the per-refresh aura helpers, the tracker
--  of the player's own auras on group members, weapon types and the raid
--  buff beneficiaries.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._abrInternals
-- EllesmereUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local AURA_SCAN_LIMIT, EABR, GetSpecID = I.AURA_SCAN_LIMIT, I.EABR, I.GetSpecID
local InCombat, isSecret, NON_SECRET_SPELL_IDS = I.InCombat, I.isSecret, I.NON_SECRET_SPELL_IDS
local SpellName = I.SpellName

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-------------------------------------------------------------------------------
--  Pre-combat aura snapshot
-------------------------------------------------------------------------------
local _preCombatAuraCache = {}  -- [spellID] = true/false, snapshotted at REGEN_DISABLED

function EABR.IsRuntimeNonSecret(id)
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
        if not ok or isSecret(secret) then return false end
        return secret == false
    end
    return true  -- if API missing, assume non-secret (pre-12.0 client)
end

-- Soulstone is readable on clients/builds where Blizzard explicitly exposes
-- it. Do not hard-whitelist it on restricted builds: source ownership is the
-- defining part of this reminder and must never be guessed from secret data.
if EABR.IsRuntimeNonSecret(20707) then NON_SECRET_SPELL_IDS[20707] = true end

local function SnapshotPlayerAuras()
    wipe(_preCombatAuraCache)
    if EABR.FOREVER then
        -- WoW Forever: only the custom spell IDs read this snapshot in combat;
        -- with none tracked there is nothing to scan, and the retail whitelist
        -- below is dead there either way.
        local fo = db and db.profile.forever
        if not (fo and fo.customIDs and fo.customIDs[1]) then return end
    else
        for id in pairs(NON_SECRET_SPELL_IDS) do
            local result = C_UnitAuras.GetPlayerAuraBySpellID(id)
            _preCombatAuraCache[id] = (result ~= nil)
        end
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

-- Pre-combat snapshot for ownOnRaid buffs (Blistering Scales, Symbiotic
-- Relationship). Source of Magic
-- reads the targeted own-aura tracker instead.
local _preCombatOwnOnRaidCache = {}  -- [spellID] = true/false
local _ownOnRaidIDs = { 360827, 474754 }  -- Blistering Scales, Symbiotic Relationship
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

-- Food buffs share the Well Fed icon, not a spell ID.
local WELL_FED_ICON = 136000

-- Lazy: runs once per refresh, only when a name-based check (Flask/ByName) or the
-- Well Fed check needs it. One pass serves them all, so a refresh reads the aura
-- list once (each read can cost milliseconds right after an encounter): names
-- into byName, and the first aura wearing the Well Fed icon into wellFed.
function _AC.ensureNames()
    if _AC.nameScanned then return end
    _AC.nameScanned = true
    wipe(_AC.byName)
    _AC.wellFed, _AC.sawIcon = nil, false
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
        local ic = aura.icon
        if ic and not isSecret(ic) then
            _AC.sawIcon = true
            if ic == WELL_FED_ICON and not _AC.wellFed then _AC.wellFed = aura end
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
-- OOC-only scan checks AuraKit.AurasRestricted() inline (no helper local).

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

-- Strict ownership of one aura: true = the player cast it, false = someone else
-- did, nil = cannot tell (the caller suppresses rather than false-fires).
-- isFromPlayerOrPlayerPet is true for ANY player's (or player pet's) cast, so it
-- only rules an aura out (false = an NPC applied it); sourceUnit proves it.
function EABR._StrictAuraFromMe(aura)
    local fromPlayer = aura.isFromPlayerOrPlayerPet
    if not isSecret(fromPlayer) and fromPlayer == false then return false end
    local src = aura.sourceUnit
    if src == nil or isSecret(src) then return nil end
    return UnitIsUnit(src, "player") == true
end

-- Whether the player's OWN cast of `id` is on `unit`, for the in-combat cache
-- updates where sourceUnit is secret: the PLAYER filter returns only auras the
-- player applied, so another caster's copy never counts. Presence only.
function EABR._OwnCastOn(unit, id)
    local names = EABR._ownCastNames
    if not names then names = {}; EABR._ownCastNames = names end
    local name = names[id]
    if name == nil then
        name = C_Spell.GetSpellName(id) or false
        names[id] = name
    end
    if not name then return false end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HELPFUL|PLAYER")
    return ok and aura ~= nil and not isSecret(aura)
end

-- True if the buff's source is the player. Non-player units: OOC iteration only, false in combat (caller uses the snapshot).
local function _unitHasBuffFromPlayer(u, spellIDs, strictSource)
    local inCombat = InCombat()
    local restricted = EllesmereUI.AuraKit and EllesmereUI.AuraKit.AurasRestricted()
    local idLookup = _idLookupScratch
    wipe(idLookup)
    for j = 1, #spellIDs do idLookup[spellIDs[j]] = true end

    if UnitIsUnit(u, "player") then
        -- Player-self: GetPlayerAuraBySpellID for whitelisted IDs
        for id in pairs(idLookup) do
            if NON_SECRET_SPELL_IDS[id] or (strictSource and not restricted) then
                local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
                if strictSource and (not ok or isSecret(aura)) then return nil end
                if ok and aura ~= nil and not isSecret(aura) then
                    if strictSource then return EABR._StrictAuraFromMe(aura) end
                    local src = aura.sourceUnit
                    if src and not isSecret(src) then
                        if UnitIsUnit(src, "player") then return true end
                    else
                        -- Source unreadable: a player's cast is assumed ours (the
                        -- flag alone cannot tell whose).
                        local fromMe = aura.isFromPlayerOrPlayerPet
                        if not isSecret(fromMe) and fromMe == true then return true end
                    end
                end
            end
        end
        -- A strict targeted lookup is authoritative in an unrestricted
        -- context; avoid a 255-aura fallback scan for every group unit.
        if strictSource then return false end
        if not inCombat and not restricted then
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
        if NON_SECRET_SPELL_IDS[id] or (strictSource and not restricted) then
            local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, u, id)
            if strictSource and (not ok or isSecret(aura)) then return nil end
            if ok and aura and not isSecret(aura) then
                if strictSource then return EABR._StrictAuraFromMe(aura) end
                local src = aura.sourceUnit
                if src and not isSecret(src) then
                    if UnitIsUnit(src, "player") then return true end
                else
                    if strictSource then return nil end
                    return true  -- sourceUnit unavailable OOC, assume ours
                end
            end
        else
            needScan = true
        end
    end
    if not needScan then return false end
    -- Scan errors under restriction; skip (caller falls back to snapshot).
    if restricted then return false end
    -- Fallback: full scan for non-whitelisted IDs only
    for i = 1, AURA_SCAN_LIMIT do
        local aura = C_UnitAuras.GetAuraDataByIndex(u, i, "HELPFUL")
        if not aura then break end
        local sid = aura.spellId
        if sid and not isSecret(sid) and idLookup[sid] then
            if strictSource then return EABR._StrictAuraFromMe(aura) end
            local src = aura.sourceUnit
            if src and not isSecret(src) then
                if UnitIsUnit(src, "player") then return true end
            else
                if strictSource then return nil end
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

-- Generic event-driven tracker for player-owned targeted auras on OTHER group members.
-- Reminder-specific policy (which spell/class/talent/location enables tracking) stays
-- in UpdateGroupAuraRegistration; this block only owns lookup/cache/synchronization.
EABR._ownOtherAuraCache = {}
EABR._ownOtherAuraTargetGUID = {}
EABR._ownOtherAuraDuration = {}
EABR._ownOtherAuraExpiration = {}
EABR._ownOtherAuraStateVersion = 0
EABR._trackOwnOtherAuraID = nil
EABR._ownOtherAuraScanGeneration = 0

-- Generic ownership lookup. The PLAYER filter is defined by Blizzard as auras
-- cast by the local player/pet/vehicle, so another Shaman/Evoker cannot satisfy
-- this lookup. Spell-name lookup remains usable for explicitly non-secret auras
-- when generic aura payloads are restricted.
function EABR.GetOwnOtherAuraData(unit, spellID)
    if not unit or not spellID then return nil, nil end
    if not (unit:match("^party%d+$") or unit:match("^raid%d+$")) then return nil, nil end
    -- A dead/ghost unit is not a reliable negative aura lookup. Preserve the
    -- last known state until the unit is alive again, leaves the group, or an
    -- authoritative aura update/rescan can establish a new state.
    if UnitIsDeadOrGhost(unit) then return nil, nil end
    -- Nor is an out-of-view member (another map or phase): the client holds no
    -- aura data for it.
    local vis = UnitIsVisible(unit)
    if not isSecret(vis) and not vis then return nil, nil end
    local name = SpellName(spellID)
    if not name or isSecret(name) then return nil, nil end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HELPFUL|PLAYER")
    if not ok or isSecret(aura) then return nil, nil end
    if aura == nil then
        -- A restricted lookup withholds a secret aura (nil while it is up). In
        -- combat a miss proves nothing; under restriction out of combat only a
        -- whitelisted non-secret id reads a trustworthy miss.
        if InCombat() then return nil, nil end
        if not NON_SECRET_SPELL_IDS[spellID] and EllesmereUI.AuraKit.AurasRestricted() then
            return nil, nil
        end
        return false, nil
    end
    return true, aura
end

-- One cache writer shared by live events and recovery scans. It deliberately
-- does not touch scan generations; callers decide whether their write is an
-- authoritative live update or the result of the currently valid scan.
function EABR.WriteOwnOtherAuraState(spellID, state, unit, aura)
    if state == nil then return end
    local old = EABR._ownOtherAuraCache[spellID]
    EABR._ownOtherAuraCache[spellID] = state
    if state then
        EABR._ownOtherAuraTargetGUID[spellID] = unit and UnitGUID(unit) or nil
        local dur = aura and aura.duration
        local exp = aura and aura.expirationTime
        EABR._ownOtherAuraDuration[spellID] = (type(dur) == "number" and not isSecret(dur)) and dur or nil
        EABR._ownOtherAuraExpiration[spellID] = (type(exp) == "number" and not isSecret(exp)) and exp or nil
    else
        EABR._ownOtherAuraTargetGUID[spellID] = nil
        EABR._ownOtherAuraDuration[spellID] = nil
        EABR._ownOtherAuraExpiration[spellID] = nil
    end
    if old ~= state and _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
end

-- Authoritative live updates invalidate older recovery work before publishing.
function EABR.SetOwnOtherAuraState(spellID, state, unit, aura)
    if state == nil then return end
    EABR._ownOtherAuraStateVersion = EABR._ownOtherAuraStateVersion + 1
    EABR._ownOtherAuraScanGeneration = EABR._ownOtherAuraScanGeneration + 1
    EABR.WriteOwnOtherAuraState(spellID, state, unit, aura)
end

-- Incremental recovery scan: one unit per frame. It never wins a race against
-- newer live data: any UNIT_AURA/cast state change bumps stateVersion/generation,
-- invalidating this scan before it can publish its result.
function EABR.RescanOwnOtherAura(spellID)
    if InCombat() or EABR._trackOwnOtherAuraID ~= spellID then return end

    EABR._ownOtherAuraScanGeneration = EABR._ownOtherAuraScanGeneration + 1
    local generation = EABR._ownOtherAuraScanGeneration
    local stateVersion = EABR._ownOtherAuraStateVersion
    local isRaid = IsInRaid()
    local count = isRaid and GetNumGroupMembers() or (IsInGroup() and GetNumSubgroupMembers() or 0)
    local index = 1
    local sawUnknown = false

    local function scanNext()
        if generation ~= EABR._ownOtherAuraScanGeneration
           or stateVersion ~= EABR._ownOtherAuraStateVersion then return end
        if InCombat() or EABR._trackOwnOtherAuraID ~= spellID then return end

        while index <= count do
            local u = (isRaid and "raid" or "party") .. index
            index = index + 1
            -- If our last known target is dead, its aura cannot be reliably
            -- disproved. Do not let a recovery scan publish false and flash the
            -- reminder while that target remains in the group.
            if UnitExists(u) and UnitIsConnected(u) and not UnitIsUnit(u, "player") then
                local guid = UnitGUID(u)
                if UnitIsDeadOrGhost(u) and guid
                   and EABR._ownOtherAuraCache[spellID] == true
                   and EABR._ownOtherAuraTargetGUID[spellID] == guid then
                    return
                end
                local state, aura = EABR.GetOwnOtherAuraData(u, spellID)
                if state == true then
                    -- The generation/version guards above prove this scan is still
                    -- current, so publish through the shared writer without
                    -- invalidating the scan that produced the result.
                    EABR.WriteOwnOtherAuraState(spellID, true, u, aura)
                    return
                elseif state == nil then
                    -- Unknown must never become "missing": the scan then ends
                    -- without a verdict and keeps the previous cache.
                    sawUnknown = true
                end
                C_Timer.After(0, scanNext)
                return
            end
        end

        if generation ~= EABR._ownOtherAuraScanGeneration
           or stateVersion ~= EABR._ownOtherAuraStateVersion then return end
        if sawUnknown then return end
        EABR.WriteOwnOtherAuraState(spellID, false)
    end

    scanNext()
end

-- UNIT_AURA is only a trigger here. In restricted combat its updateInfo can be
-- fully secret, so do not depend on addedAuras/sourceUnit. Query exactly the
-- changed party/raid unit with HELPFUL|PLAYER instead. This same generic path is
-- used by Earth Shield and Source of Magic.
function EABR.UpdateOwnOtherAuraForUnit(unit)
    local spellID = EABR._trackOwnOtherAuraID
    if not spellID or not unit or UnitIsUnit(unit, "player") then return end
    if not (unit:match("^party%d+$") or unit:match("^raid%d+$")) then return end

    local state, aura = EABR.GetOwnOtherAuraData(unit, spellID)
    if state == true then
        EABR.SetOwnOtherAuraState(spellID, true, unit, aura)
        return
    end
    -- Unknown (secret, dead, out of view) never clears. A miss is authoritative only for
    -- the unit holding our cached aura; another unit's miss proves nothing, and
    -- recovery/roster scans establish a group-wide false.
    if state == nil then return end
    local guid = UnitGUID(unit)
    if guid and EABR._ownOtherAuraTargetGUID[spellID] == guid then
        EABR.SetOwnOtherAuraState(spellID, false)
    end
end

function EABR.RescanOwnOtherAuras()
    local spellID = EABR._trackOwnOtherAuraID
    if spellID then EABR.RescanOwnOtherAura(spellID) end
end

-- Registration pass for the roster, loading-screen and talent edges. A
-- tracking change clears or rescans inside the pass, so only an unchanged
-- tracker rescans here.
function EABR.ReevaluateOwnOtherAuraTracking()
    local before = EABR._trackOwnOtherAuraID
    if _G._EABR_UpdateGroupAuraRegistration then
        _G._EABR_UpdateGroupAuraRegistration()
    end
    if before and EABR._trackOwnOtherAuraID == before then
        EABR.RescanOwnOtherAuras()
    end
end

-- Early rebuff for a targeted aura follows the Display "Show Below" / "Show
-- Below Pre-Key" window (never in combat or an active key); sectionKey is the
-- owning section ("aura" / "special").
function EABR.OwnOtherAuraNeedsRebuff(spellID, sectionKey)
    if EABR._ownOtherAuraCache[spellID] ~= true then return false end
    local dur = EABR._ownOtherAuraDuration[spellID]
    local exp = EABR._ownOtherAuraExpiration[spellID]
    if type(dur) ~= "number" or type(exp) ~= "number" then return false end
    return EABR.IsUnderDuration(dur, exp, sectionKey)
end

-- True when another group member is alive, connected and in range: a targeted
-- buff reminder has nobody to go on otherwise.
function EABR.AnyReachableGroupMember()
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid"..i
            if _unitOk(u) and not UnitIsUnit(u, "player") and _unitInRange(u) then return true end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local u = "party"..i
            if _unitOk(u) and _unitInRange(u) then return true end
        end
    end
    return false
end

-- True if the player's own cast exists on any group member, OR no in-range member is a valid target (suppress either way). Used for the ownOnRaid auras other than Source of Magic.
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

-- Soulstone differs from targeted maintenance buffs: self is always a valid
-- destination, and an existing cast on an out-of-range group member still
-- satisfies the reminder. Returns nil when restricted aura data cannot prove
-- ownership, allowing the caller to suppress rather than false-fire.
function EABR.PlayerOwnBuffOnGroupOrSelf(spellIDs)
    if not spellIDs or not spellIDs[1] then return true end
    if EllesmereUI.AuraKit and EllesmereUI.AuraKit.AurasRestricted() then
        for i = 1, #spellIDs do
            if not NON_SECRET_SPELL_IDS[spellIDs[i]] then return nil end
        end
    end
    local uncertain = false
    local state = _unitHasBuffFromPlayer("player", spellIDs, true)
    if state == true then return true elseif state == nil then uncertain = true end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid" .. i
            if not UnitIsUnit(u, "player") and UnitExists(u) and UnitIsConnected(u) and UnitIsPlayer(u) then
                state = _unitHasBuffFromPlayer(u, spellIDs, true)
                if state == true then return true elseif state == nil then uncertain = true end
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local u = "party" .. i
            if UnitExists(u) and UnitIsConnected(u) and UnitIsPlayer(u) then
                state = _unitHasBuffFromPlayer(u, spellIDs, true)
                if state == true then return true elseif state == nil then uncertain = true end
            end
        end
    end
    if uncertain then return nil end
    return false
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
        _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    end
    if not classID or classID ~= ((Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2) then return nil end
    if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then return nil end
    if subClassID and BLADED_SET[subClassID] then return "BLADED" end
    if subClassID and BLUNT_SET[subClassID]  then return "BLUNT" end
    if subClassID and RANGED_SET[subClassID] then return "RANGED" end
    return "NEUTRAL"
end

-- Off-hand slot holds a shield. Gates the shield-only imbue reminders
-- (requireShield rows); on EABR, not a local.
-- UNIT_INVENTORY_CHANGED already refreshes, so no new event.
function EABR.HasShieldEquipped()
    local itemID = GetInventoryItemID("player", 17)
    if not itemID then return false end
    local _, _, _, equipLoc
    if C_Item and C_Item.GetItemInfoInstant then
        _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
    else
        _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
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
-- WoW Forever: Intellect serves every mana user (hunters included) and Battle
-- Shout raises melee attack power only (a hunter shoots with ranged).
if EABR.FOREVER then
    BUFF_BENEFICIARIES.intellect = {
        DRUID = true, HUNTER = true, MAGE = true, PALADIN = true, PRIEST = true, SHAMAN = true, WARLOCK = true,
    }
    BUFF_BENEFICIARIES.attackPower = {
        DRUID = true, PALADIN = true, ROGUE = true, SHAMAN = true, WARRIOR = true,
    }
end

-- Set of player classes present in the group (online, alive, in range),
-- excluding the local player. Built on demand for the receiver view ("I am
-- missing others' buffs") so a buff is only flagged when someone who can
-- cast it is actually nearby. Secret class tokens are skipped (identity
-- restriction edges). Hung on EABR.
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
    -- WoW Forever has no spec data to look up (no comms cache, no specs).
    local specSet = not EABR.FOREVER and EABR.SPEC_BENEFITS[benefit]
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
    -- Effective role: the player's spec wins over a stale assigned role. On
    -- WoW Forever every mana user wants Intellect, whatever the role.
    local role = EllesmereUI.UnitEffectiveRole(u)
    if role ~= nil and not isSecret(role) then
        if benefit == "intellect" and not EABR.FOREVER then
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

I._AC, I._ownOnRaidIDs = _AC, _ownOnRaidIDs
I._preCombatOwnOnRaidCache, I._unitInRange = _preCombatOwnOnRaidCache, _unitInRange
I._unitOk, I.BuffExistsOnAnyGroupMember = _unitOk, BuffExistsOnAnyGroupMember
I.BuildPlayerAuraCache, I.CountGroupBuffCoverage = BuildPlayerAuraCache, CountGroupBuffCoverage
I.GetStanceState, I.GetWeaponCategory = GetStanceState, GetWeaponCategory
I.IsAnyShapeshiftFormActive, I.IsUnderDuration = IsAnyShapeshiftFormActive, IsUnderDuration
I.PlayerHasAuraByID, I.PlayerHasSelfCastAuraByID = PlayerHasAuraByID, PlayerHasSelfCastAuraByID
I.PlayerOwnBuffOnAnyGroupMember = PlayerOwnBuffOnAnyGroupMember
I.SnapshotOwnOnRaidBuffs, I.SnapshotPlayerAuras = SnapshotOwnOnRaidBuffs, SnapshotPlayerAuras
I.broken = false
