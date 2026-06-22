-------------------------------------------------------------------------------
--  EllesmereUIAuraBuffReminders.lua
--  Complete AuraBuff Reminders: Raid Buffs, Auras, Consumables
--  Clickable SecureActionButton icons with combat-aware tracking
--  Blizzard 12.0 Midnight non-secret spell support
-------------------------------------------------------------------------------

local ADDON_NAME = ...

-- AceDB replaced by EllesmereUI.Lite.NewDB
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

-------------------------------------------------------------------------------
--  Profiler: zero cost when off, /eabrprof to toggle. debugprofilestop for
--  per-label timing + C_AddOnProfiler for whole-addon avg/peak. Mirrors the
--  RaidFrames /erfprof pattern. (do..end block adds no file-scope locals.)
-------------------------------------------------------------------------------
do
    local _profData, _profActive = {}, false
    local dps = debugprofilestop
    local _addonName = "EllesmereUIAuraBuffReminders"
    local _frameCount, _totalAddonMs, _peakAddonMs, _startTime = 0, 0, 0, 0
    local _curFrameLabels, _curFrameTotal, _curFrameTime = {}, 0, 0
    local _peakFrameLabels, _peakFrameTotal = {}, 0

    EABR.ProfBegin = function(label)
        if not _profActive then return 0 end
        return dps()
    end
    EABR.ProfEnd = function(label, t0)
        if not _profActive then return end
        local elapsed = dps() - t0
        local now = GetTime()
        if now ~= _curFrameTime then
            if _curFrameTotal > _peakFrameTotal then
                _peakFrameTotal = _curFrameTotal
                wipe(_peakFrameLabels)
                for k, v in pairs(_curFrameLabels) do _peakFrameLabels[k] = v end
            end
            wipe(_curFrameLabels); _curFrameTotal = 0; _curFrameTime = now
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
        local addonMs = C_AddOnProfiler.GetAddOnMetric(_addonName, Enum.AddOnProfilerMetric.LastTime) or 0
        _frameCount = _frameCount + 1
        _totalAddonMs = _totalAddonMs + addonMs
        if addonMs > _peakAddonMs then _peakAddonMs = addonMs end
    end)

    local function ResetProf()
        wipe(_profData); wipe(_curFrameLabels); wipe(_peakFrameLabels)
        _frameCount = 0; _totalAddonMs = 0; _peakAddonMs = 0
        _peakFrameTotal = 0; _curFrameTotal = 0; _curFrameTime = 0; _startTime = 0
    end

    SLASH_EABRPROF1 = "/eabrprof"
    SlashCmdList["EABRPROF"] = function(msg)
        if msg == "reset" then ResetProf(); print("|cff00ccffEABRProf:|r data cleared"); return end
        _profActive = not _profActive
        if _profActive then
            ResetProf(); _startTime = GetTime(); profFrame:Show()
            print("|cff00ccffEABRProf:|r ON -- type /eabrprof again to stop")
        else
            profFrame:Hide()
            if _curFrameTotal > _peakFrameTotal then
                _peakFrameTotal = _curFrameTotal
                wipe(_peakFrameLabels)
                for k, v in pairs(_curFrameLabels) do _peakFrameLabels[k] = v end
            end
            local dur = GetTime() - _startTime
            local avgAddon = _frameCount > 0 and (_totalAddonMs / _frameCount) or 0
            print("|cff00ccffEABRProf Report:|r  " .. _frameCount .. " frames, " .. format("%.1f", dur) .. "s")
            print(format("  |cff00ccffAddon Peak:|r  %.3f ms   |cff00ccffAvg:|r %.3f ms", _peakAddonMs, avgAddon))
            local scale = (_peakFrameTotal > 0) and (_peakAddonMs / _peakFrameTotal) or 1
            local sorted = {}
            for label, ms in pairs(_peakFrameLabels) do
                local d = _profData[label]
                local avg = (d and _frameCount > 0) and (d.total / _frameCount) or 0
                local n = d and d.n or 0
                local per = (n > 0) and (d.total / n) or 0
                sorted[#sorted + 1] = { label = label, peak = ms * scale, avg = avg, n = n, per = per }
            end
            table.sort(sorted, function(a, b) return a.avg > b.avg end)
            print(format("  %-20s %8s %8s %7s %8s", "Label", "avg ms", "peak ms", "calls", "ms/call"))
            for _, e in ipairs(sorted) do
                print(format("  %-20s %8.3f %8.3f %7d %8.4f", e.label, e.avg, e.peak, e.n, e.per))
            end
        end
    end
end

-- Hunter's Mark combat state: set true on PLAYER_REGEN_DISABLED, cleared on
-- cast or combat end. OOC falls back to target debuff check.
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
        return LABEL_CLASS_OVERRIDES[classOverride]
    end
    if LABEL_OVERRIDES[name] then return LABEL_OVERRIDES[name] end
    return name:match("^(%S+)") or name
end

-------------------------------------------------------------------------------
--  Instance / Difficulty helpers
--  Cached per-frame: call CacheInstanceInfo() at the start of Refresh()
-------------------------------------------------------------------------------
local _cachedIType, _cachedDiffID, _cachedMapID

local function CacheInstanceInfo()
    local _, iType, diffID = GetInstanceInfo()
    _cachedIType = iType
    _cachedDiffID = tonumber(diffID) or 0
    _cachedMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
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

local function InMythicZeroDungeon()
    if _cachedIType == "party" and (_cachedDiffID == 23 or _cachedDiffID == 8) then return true end
    return false
end

-- Mythic raid difficulty: fixed 20-player (16, PrimaryRaidMythic) or
-- flexible (233, RaidMythicFlexible, added in 12.0.x). Add future Mythic
-- raid difficulty IDs here so every gate below stays correct.
local function IsMythicRaidDiff(d)
    return d == 16 or d == 233
end

-- Mythic 0 dungeon (party, normal difficulty 1) or Mythic raid (fixed or flex)
local function InMythicZeroDungeonOrMythicRaid()
    if InMythicZeroDungeon() then return true end
    if IsInRaid() and IsMythicRaidDiff(_cachedDiffID) then return true end
    return false
end

-- Heroic+ content (heroic dungeon/raid or mythic dungeon/raid/M+)
local function InHeroicOrMythicContent()
    if _cachedIType == "party" and (_cachedDiffID == 2 or _cachedDiffID == 23 or _cachedDiffID == 8) then return true end
    if _cachedIType == "raid" and (_cachedDiffID == 5 or _cachedDiffID == 6 or _cachedDiffID == 15 or IsMythicRaidDiff(_cachedDiffID)) then return true end
    return false
end

local function InPvPInstance()
    return _cachedIType == "pvp" or _cachedIType == "arena"
end

-------------------------------------------------------------------------------
--  Midnight Season 1 Dungeon, Raid & PvP Instance Names
-------------------------------------------------------------------------------
-- Talent reminder zone data moved to EllesmereUIABR_TalentReminders.lua

-------------------------------------------------------------------------------
--  Talent query helpers
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Aura query helpers (secret-value safe, Midnight 12.0)
--  NON_SECRET_SPELL_IDS: whitelisted IDs readable via GetPlayerAuraBySpellID
--  even during combat lockdown.
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
    -- Also snapshot non-whitelisted auras (e.g. Devotion Aura) that become
    -- secret when a party member enters combat before the local player does.
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
--  Per-refresh aura helpers (zero-allocation where possible).
--  Instead of scanning all auras into a cache (which creates ~20-40 API
--  tables per refresh), we use targeted GetPlayerAuraBySpellID lookups
--  and only fall back to GetAuraDataByIndex for name-based checks.
-------------------------------------------------------------------------------
local _AC = { valid = false, nameScanned = false, byName = {} }

-- BuildPlayerAuraCache: lightweight reset. The expensive name scan is
-- deferred to the first function that actually needs it (lazy).
local function BuildPlayerAuraCache()
    _AC.valid = not InCombat()
    _AC.nameScanned = false
    -- srcByID is only needed by PlayerHasSelfCastAuraByID; wiped lazily there
end

-- Lazy name scan: only runs once per refresh, only when a name-based
-- check (PlayerHasWellFed, PlayerHasFlaskBuff, PlayerHasBuffByName) needs it.
function _AC.ensureNames()
    if _AC.nameScanned then return end
    _AC.nameScanned = true
    wipe(_AC.byName)
    if InCombat() then return end
    for i = 1, AURA_SCAN_LIMIT do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local aName = aura.name
        if aName and not isSecret(aName) then
            _AC.byName[aName] = true
        end
    end
end

local function IsUnderDuration(duration, expirationTime)
    if not (db and db.profile and db.profile.display and duration and expirationTime) then return false end

    local d = db.profile.display
    local thresholdSeconds
    if InMythicZeroDungeon() then
        thresholdSeconds = (d.showUnderDurationDungeon or 0) * 60
    elseif IsInRaid() then
        thresholdSeconds = (d.showUnderDurationRaid or 0) * 60
    end

    if thresholdSeconds and thresholdSeconds > 0 and duration >= thresholdSeconds then
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

local function PlayerHasAuraByID(spellIDs)
    if not spellIDs or not spellIDs[1] then return true end
    local inCombat = InCombat()
    -- Direct API lookup via GetPlayerAuraBySpellID (zero allocation, works OOC and
    -- in combat for whitelisted IDs). Non-whitelisted IDs fall back to snapshot.
    for j = 1, #spellIDs do
        local id = spellIDs[j]
        if NON_SECRET_SPELL_IDS[id] then
            local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
            if ok then
                if result ~= nil then 
                    if IsUnderDuration(result.duration, result.expirationTime) then
                        return false
                    end
                    return true 
                end
                if inCombat and _preCombatAuraCache[id] then return true end
            else
                if inCombat and _preCombatAuraCache[id] then return true end
            end
        elseif not inCombat then
            -- Non-whitelisted OOC: use GetPlayerAuraBySpellID anyway (may return
            -- secret values, but non-nil means the aura exists)
            local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
            if ok and result ~= nil then
                if IsUnderDuration(result.duration, result.expirationTime) then
                    return false
                end
                return true
            end
        else
            if _preCombatAuraCache[id] then return true end
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
                    if result ~= nil then return true end
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
                if ok and result ~= nil and not isSecret(result) then
                    return true
                end
            end
        end
    end
    -- Iterate auras for non-whitelisted IDs (only works out of combat)
    -- Skip iteration for player (GetPlayerAuraBySpellID above covers all IDs)
    if not inCombat and not UnitIsUnit(u, "player") then
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

-- Returns true if the buff's source is the player.
-- Non-player units: OOC iteration only; in combat returns false (caller uses snapshot).
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
        if not inCombat then
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
    -- Fast path: direct lookup for whitelisted IDs (1 API call per ID instead
    -- of scanning every aura on the unit via GetAuraDataByIndex).
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

-- Assign the SnapshotOwnOnRaidBuffs function (forward-declared earlier,
-- now that _unitHasBuffFromPlayer is defined).
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

-- Returns true only if the buff was cast by the player on themselves.
-- OOC only — combatOk must be false on any aura using this check.
local function PlayerHasSelfCastAuraByID(spellIDs)
    if not spellIDs or not spellIDs[1] then return true end
    if InCombat() then return false end  -- safety: can't read sourceUnit in combat
    -- Direct ID lookup: for whitelisted IDs, GetPlayerAuraBySpellID returns
    -- the full aura data including sourceUnit (zero iteration needed).
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

-- Group-member range check, mirroring the raid frames' range path:
-- UnitInRange (~40 yd helpful range, works in combat, not protected) is the
-- primary check. The raid frames never BRANCH on it though -- they feed the
-- result into SetAlphaFromBoolean because it can be a SECRET value in
-- instances, and Lua cannot branch on secrets. When that happens here we
-- fall back to UnitIsVisible (~100 yd, same phase/zone), which the raid
-- frames' ghost-aura sweep branches on in plain Lua -- proven clean in
-- instances. That still excludes the practical false-positive cases
-- (members parked in another wing, cross-zone, other phase), it is just
-- coarser than true cast range.
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

-- Returns true if any in-range group member is missing the buff.
local function AnyGroupMemberMissingBuff(spellIDs)
    if not IsInGroup() then return not _unitHasBuff("player", spellIDs) end
    if _unitOk("player") and not _unitHasBuff("player", spellIDs) then return true end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid"..i
            if _unitOk(u) and UnitIsPlayer(u) and not UnitIsUnit(u, "player")
               and _unitInRange(u) and not _unitHasBuff(u, spellIDs) then
                return true
            end
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            local u = "party"..i
            if _unitOk(u) and UnitIsPlayer(u)
               and _unitInRange(u) and not _unitHasBuff(u, spellIDs) then
                return true
            end
        end
    end
    return false
end

-- Returns true if the buff exists on any group member (any source).
-- Used for Symbiotic Relationship.
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

-- Returns true if the player's cast of spellIDs exists on any group member,
-- OR if no in-range member is a valid target (suppress reminder either way).
-- Used for Source of Magic, Blistering Scales.
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

-- Returns true if the target has the debuff. OOC only; suppresses in combat.

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


-------------------------------------------------------------------------------
--  SPELL DATA Raid Buffs (all non-secret in 12.0, work in combat)
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
    -- Hunter's Mark: disabled (under maintenance)
    -- { key="hmark",  class="HUNTER",  name="Hunter's Mark",          castSpell=257284, buffIDs={257284},  check="huntersMark" },
}

-------------------------------------------------------------------------------
--  SPELL DATA Auras (some non-secret, some still OOC-only)
-------------------------------------------------------------------------------
local AURAS = {
    -- Symbiotic Relationship: player gets a buff when active (group only)
    { key="symbiotic",  class="DRUID",   name="Symbiotic Relationship", castSpell=474750, buffIDs={474754},
      check="player", combatOk=false, requireGroup=true },
    -- Warrior stances: NOT on non-secret list, OOC only
    { key="def_stance",  class="WARRIOR", name="Defensive Stance",  castSpell=386208, buffIDs={386208},
      check="player", specs={73}, combatOk=false },
    { key="berserk_stance", class="WARRIOR", name="Berserker Stance", castSpell=386196, buffIDs={386196},
      check="player", specs={71, 72}, combatOk=false },
    -- Shadowform: OOC only. Void Form (194249) also satisfies the check.
    -- shapeshiftIndex=1: fallback for PvP instances where aura API is restricted.
    { key="shadowform", class="PRIEST",  name="Shadowform",        castSpell=232698, buffIDs={232698, 194249},
      check="player", specs={258}, combatOk=false, shapeshiftIndex=1 },
    -- Paladin Aura: in dungeons/raids only Devotion satisfies; elsewhere any aura works
    -- noPvP: Devotion Aura is ContextuallySecret in PvP even out of combat
    { key="devo_aura",  class="PALADIN", name="Devotion Aura",     castSpell=465,
      buffIDs={465, 32223, 317920}, instanceBuffIDs={465},
      check="player", combatOk=false, noPvP=true },
    -- Beacon of Light: standalone IsSpellOverlayed system (not checked by CollectAuras)
    { key="bol",        class="PALADIN", name="Beacon of Light",   castSpell=53563,  buffIDs={53563},
      standalone=true, notIfKnown=200025 },
    -- Beacon of Faith: standalone IsSpellOverlayed system (not checked by CollectAuras)
    { key="bof",        class="PALADIN", name="Beacon of Faith",   castSpell=156910, buffIDs={156910},
      standalone=true },
    -- Source of Magic: non-secret (369459) applied to a specific healer,
    -- not the caster; check if player's cast exists on any group member.
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
-- Healthstone: check if player has one in bags (itemID 5512)
local HEALTHSTONE_ITEM_IDS = { 5512, 224464 }  -- Healthstone, Demonic Healthstone

-- Partnered Trinket: Emerald Coaches Whistle (buff 383798, icon 134157, 60 min)
local PARTNERED_TRINKET = {
    key = "coaches_whistle", name = "Emerald Coach's Whistle",
    buffID = 389581, buffIDs = {389581, 383798}, icon = 134157, duration = 3600,
}

-- Pet tracking: classes that summon permanent pets
local PET_CLASSES = { HUNTER = true, WARLOCK = true, DEATHKNIGHT = true, MAGE = true }

-- Spells whose presence means the player uses their own imbue system
-- instead of generic weapon oils/stones. If the player knows ANY of these,
-- the weapon enchant reminder is suppressed for them.
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
-- Rogue Poisons: data table drives options UI; detection uses unified scan below.
-- Lethal and non-lethal categories match WoW's internal classification.
local ROGUE_POISONS = {
    -- Lethal poisons (mutually exclusive per slot).
    -- Deadly first (core Assa poison), then talented, then other base.
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
    { key="tidecaller",  name="Tidecaller's Guard", castSpell=457496, buffIDs={457496, 457481}, wepEnchID={7528} },
    { key="tstrike",     name="Thunderstrike Ward", castSpell=462757, buffIDs={462757, 462742}, wepEnchID={7587} },
}

-- Shaman Shields: three entries based on Elemental Orbit (383010) talent.
-- With Orbit: Earth Shield self-buff (383648) + Lightning/Water Shield both needed.
-- Without Orbit: any of Earth/Lightning/Water Shield on self.
-- Resolve the correct shield cast spell based on spec.
-- Resto (264) -> Water Shield (52127), others -> Lightning Shield (192106).
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
-- TWW flask buff IDs (detection only, so we don't false-positive when a
-- player still has a TWW flask active)
for _, id in ipairs({432473, 432021, 431974, 431973, 431972, 431971}) do
    FLASK_BUFF_ID_SET[id] = true
end
-- PvP-morphed Midnight flask buff IDs (Blizzard replaces the PvE buff ID with
-- a separate PvP variant inside arenas and battlegrounds)
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
    { key="hearty_flora_frenzy",            itemID=267000, name="Hearty Flora Frenzy" },
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
local INKY_BLACK_BUFF = 242783  -- buff applied by Inky Black Potion

-------------------------------------------------------------------------------
--  Helpers: Well Fed / Flask buff detection (by name, not spell ID secret)
-------------------------------------------------------------------------------
local function PlayerHasBuffByName(buffName)
    if _AC.valid then
        _AC.ensureNames()
        return _AC.byName[buffName] or false
    end
    for i = 1, AURA_SCAN_LIMIT do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local aName = aura.name
        if aName and not isSecret(aName) and aName == buffName then return true end
    end
    return false
end

local function PlayerHasWellFed()
    if InCombat() then return true end  -- never show food reminder in combat
    if InMythicPlusKey() then return true end  -- can't act on it during M+, suppress
    if InPvPInstance() then return true end  -- food not trackable in PvP, suppress
    for i = 1, AURA_SCAN_LIMIT do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local ic = aura.icon
        if ic and not isSecret(ic) and ic == 136000 then 
            if IsUnderDuration(aura.duration, aura.expirationTime) then
                return false
            end
            return true
        end
    end
    return false
end

local function PlayerHasFlaskBuff()
    -- Aura API is restricted in PvP and M+ keystones; suppress since player can't act on it.
    if InPvPInstance() then return true end
    if InMythicPlusKey() then return true end
    -- Direct ID lookup for known flask buff IDs (zero allocation)
    for id in pairs(FLASK_BUFF_ID_SET) do
        local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if ok and result ~= nil then 
            if IsUnderDuration(result.duration, result.expirationTime) then
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

-------------------------------------------------------------------------------
--  Item count snapshot: GetItemCount is a per-item bag scan, and the consumable
--  resolve queries ~135 items -- doing that cold was ~7ms. Instead walk all bags
--  ONCE into an {itemID -> count} table (rebuilt only when bags change) so every
--  CachedGetItemCount is a hash lookup. Bags 0-4 only; consumables never live in
--  the reagent bag. The item-use tracker (DetectUsedItem) shares this exact
--  snapshot, so there is one bag walk per bag change, not two.
-------------------------------------------------------------------------------
local _bagCounts = {}
local _itemCountDirty = true

-- Resolved consumable cache: WHICH item to show for each bag/equip-derived
-- category. Rebuilt only when bags, the equipped weapon, or a preferred-item
-- setting changes (see EABR.ResolveConsumables). Hung on EABR to avoid new
-- file-scope locals (200 cap). Only SELECTION state is cached (itemID / cat /
-- hasBags / availability booleans); the icon is derived at each emit site so it
-- stays byte-identical to the per-refresh GetItemIcon calls. Records default to
-- nil/false = no reminder until the first resolve. dirty starts true so the
-- first out-of-combat CollectConsumables fully populates the cache.
EABR._resolved = {
    dirty = true,                   -- rebuild pending
    sig = {},                       -- last preferred-setting signature
    rune = {},                      -- {itemID}
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
    if preferredKey == "last_used" then
        if lastUsedItemID and CachedGetItemCount(lastUsedItemID) > 0 then
            return lastUsedItemID
        end
        for _, f in ipairs(FOOD_ITEMS) do
            if CachedGetItemCount(f.itemID) > 0 then return f.itemID end
        end
        return nil
    end
    for _, f in ipairs(FOOD_ITEMS) do
        if f.key == preferredKey and CachedGetItemCount(f.itemID) > 0 then return f.itemID end
    end
    return nil
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
--  Resolve bag/equip-derived consumable display items. This is the costly part
--  of the consumable check (Find*Item data-table walks + GetWeaponCategory) and
--  depends ONLY on bags, equipped weapon type, and the preferred-item settings
--  (+ db.char.lastUsed*), none of which change between refreshes. Rebuilt lazily
--  when one of those changes; CollectConsumables reads the resolved records each
--  refresh and derives the icon at emit. Preserves every branch's exact item
--  selection, fallback ordering, and hasBags/desaturated behavior.
--  NOTE: any FUTURE input added to resolution must also set _resolved.dirty (or
--  be added to the signature below), or a stale item could be shown.
-------------------------------------------------------------------------------
function EABR.ResolveConsumables()
    if not db then return end
    local co = db.profile and db.profile.consumables
    if not co then return end

    local R = EABR._resolved
    local pf  = co.preferredFlask or "last_used"
    local pfd = co.preferredFood or "last_used"
    local pwe = co.preferredWeaponEnchant or "last_used"
    -- Lazy gate: rebuild only when a bag/equip event marked us dirty, or when a
    -- preferred-item setting changed. The options setters only RequestRefresh
    -- with no bag event, so a cheap signature compare catches that here.
    local sig = R.sig
    if not R.dirty and sig.pf == pf and sig.pfd == pfd and sig.pwe == pwe then
        return
    end
    R.dirty = false
    sig.pf, sig.pfd, sig.pwe = pf, pfd, pwe

    local luf  = db.char and db.char.lastUsedFlask or nil
    local lufd = db.char and db.char.lastUsedFood or nil
    local luwe = db.char and db.char.lastUsedWeaponEnchant or nil

    -- Augment Rune: void preferred over ethereal; nil if neither in bags.
    local runeItem = nil
    if CachedGetItemCount(259085) > 0 then runeItem = 259085
    elseif CachedGetItemCount(243191) > 0 then runeItem = 243191 end
    R.rune.itemID = runeItem

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

    -- Food: resolve a display item even when out of stock (never desaturated).
    local foodItemID = FindFoodItem(pfd, lufd)
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

    -- Weapon enchant: per slot. cat (equipped weapon type) gates the reminder in
    -- CollectConsumables and selects the item; resolve a display item even when
    -- out of stock (shown desaturated). Same fallback order as the inline code.
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
            frameStrata = "MEDIUM",
            cursorAttach = false,
            showUnderDurationDungeon = 20,
            showUnderDurationRaid = 10,
        },
        raidBuffs = {
            showNonInstanced = false,
            showOthersMissing = true,
            scale = 1.0,
            enabled = {
                motw=true, bshout=true, fort=true, ai=true, bronze=true, sky=true, hmark=true,
            },
        },
        auras = {
            showNonInstanced = true,
            scale = 1.0,
            enabled = {
                symbiotic=true, def_stance=true, berserk_stance=true, shadowform=true,
                devo_aura=true, bol=true, bof=true, som=true, blistering_scales=true, 
                bestow_weyrnstone=true, timelessness=true,
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

local euiPanelOpen = false

-------------------------------------------------------------------------------
--  Middle-click dismiss hide a reminder until the next loading screen
-------------------------------------------------------------------------------
local _dismissedUntilLoad = {}  -- [dismissKey] = true

-------------------------------------------------------------------------------
--  Icon Pool SecureActionButton based for click-to-cast
-------------------------------------------------------------------------------
local ICON_SIZE = 40
local iconAnchor
local iconPool = {}     -- all created icon buttons
local activeIcons = {}  -- currently visible icons

-- Talent icon state moved to EllesmereUIABR_TalentReminders.lua

-------------------------------------------------------------------------------
--  Combat Icon Pool — non-secure frames for visual-only display during combat.
-------------------------------------------------------------------------------
local combatAnchor      -- created in OnEnable, follows iconAnchor position
local combatIconPool = {}
local combatActiveIcons = {}

-------------------------------------------------------------------------------
--  Cursor-attached combat icons — shown at cursor when cursorAttach is enabled.
-------------------------------------------------------------------------------
local CURSOR_IMPORTANT = {
    -- All raid buffs are important (checked by cat == "raidbuff")
    -- Beacon tracking uses its own independent system (_B)
}
local cursorAnchor
local cursorIconPool = {}
local cursorActiveIcons = {}

local function GetStrata()
    return db and db.profile.display.frameStrata or "MEDIUM"
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
    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    SetABRFont(text, ResolveFontPath(), 11)
    text:SetTextColor(1, 1, 1, 1)
    f._text = text
    combatIconPool[index] = f
    return f
end

local function HideCombatIcons()
    for i = 1, #combatActiveIcons do
        local f = combatActiveIcons[i]
        if f then
            if f._eabrGlowWrapper then f._eabrGlowWrapper:Hide() end
            f._text:SetText(""); f:Hide()
        end
    end
    wipe(combatActiveIcons)
    if combatAnchor then EllesmereUI.SetElementVisibility(combatAnchor, false) end
end

local function ShowCombatIcon(iconIdx, spellID, texture, label)
    local f = GetOrCreateCombatIcon(iconIdx)
    f._icon:SetTexture(texture or Tex(spellID) or 134400)
    local p = db and db.profile.display
    if p and p.showText then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        local fontPath = ResolveFontPath(p.textFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        SetABRFont(f._text, fontPath, textSize)
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
--  Cursor Icon Pool same visual style as combat icons, parented to
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
    if PP then PP.CreateBorder(f, 0, 0, 0, 1, 1, "OVERLAY", 7) end
    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    SetABRFont(text, ResolveFontPath(), 11)
    text:SetTextColor(1, 1, 1, 1)
    f._text = text
    cursorIconPool[index] = f
    return f
end

local function HideCursorIcons()
    for i = 1, #cursorActiveIcons do
        local f = cursorActiveIcons[i]
        if f then
            if f._eabrGlowWrapper then f._eabrGlowWrapper:Hide() end
            f._text:SetText(""); f:Hide()
        end
    end
    wipe(cursorActiveIcons)
    if cursorAnchor then EllesmereUI.SetElementVisibility(cursorAnchor, false) end
end

local function ShowCursorIcon(iconIdx, spellID, texture, label)
    local f = GetOrCreateCursorIcon(iconIdx)
    f._icon:SetTexture(texture or Tex(spellID) or 134400)
    local p = db and db.profile.display
    if p and p.showText then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        local fontPath = ResolveFontPath(p.textFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        SetABRFont(f._text, fontPath, textSize)
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
end

local function ApplyGlow(btn, glowType, cr, cg, cb, overrideSz)
    if glowType == 0 then return end
    local entry = GLOW_TYPES[glowType]; if not entry then return end
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

    -- Text label below icon
    local text = btn:CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    SetABRFont(text, ResolveFontPath(), 11)
    text:SetTextColor(1, 1, 1, 1)
    btn._text = text



    iconPool[index] = btn
    return btn
end


-- Configure a button for spell casting
-- Set icon to a plain texture (no click action)
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
        e.cat = nil; e.data = nil; e.scale = 1.0; e.dismissKey = nil
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
            SetIconMacro(btn, m.macro, m.texture, nil)
            btn._tooltipItem = m.tooltipItem
        else -- "texture"
            SetIconTexture(btn, m.texture, m.label)
            if m.spellID then btn._tooltipSpell = m.spellID end
        end
        btn._text:SetText(m.label or "")
        btn._icon:SetDesaturated(m.desaturated or false)
    end
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
        if btn then RemoveGlow(btn); btn._text:SetText(""); btn._icon:SetDesaturated(false); btn:Hide() end
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
    -- Merge beacon icons into the layout so everything is one continuous row.
    -- Beacon logic is untouched; we just include visible beacon frames in positioning.
    local allIcons = _layoutScratch
    wipe(allIcons)
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
    for i, btn in ipairs(allIcons) do
        btn:SetSize(sz, sz)
        btn:SetAlpha(p.opacity or 1.0)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", iconAnchor, "TOPLEFT", (i-1)*(sz+spacing), 0)
    end
    -- Size the anchor to the grid so the unlock mode mover covers it correctly
    local textH = 0
    if p.showText then textH = (p.textSize or 11) + abs(p.textYOffset or -2) end
    ResizeAnchorCentered(totalW, sz + textH)
end

local function ShowIcon(iconIdx, m)
    local btn = GetOrCreateIcon(iconIdx)
    btn._dismissKey = m.dismissKey or nil
    ApplySetup(btn, m)
    local p = db.profile.display
    local glowType = p.glowType or 0
    local gc = p.glowColor or DEFAULT_GLOW_COLOR
    local baseScale = p.scale or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    RemoveGlow(btn)
    ApplyGlow(btn, glowType, gc.r, gc.g, gc.b, sz)
    if p.showText then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        local fontPath = ResolveFontPath(p.textFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        SetABRFont(btn._text, fontPath, textSize)
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


local function CollectRaidBuffs(missing, playerClass, inInstance, inCombat)
local rb = db.profile.raidBuffs
if inInstance or rb.showNonInstanced then
    local _, iType = IsInInstance()
    local inPvP = (iType == "pvp" or iType == "arena")
    for _, buff in ipairs(RAID_BUFFS) do
        if rb.enabled[buff.key] and (buff.class == playerClass) and Known(buff.castSpell)
           and not (buff.noPvP and inPvP) then
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
                if buff.check == "huntersMark" then
                    isMissing = inCombat and _huntersMarkNeeded
                elseif rb.showOthersMissing and buff.check == "raid" and (IsInGroup() or IsInRaid()) then
                    isMissing = AnyGroupMemberMissingBuff(buff.buffIDs)
                else
                    isMissing = not PlayerHasAuraByID(buff.buffIDs)
                end
                if isMissing then
                    local e = AcquireEntry()
                    e.mode = "spell"; e.spellID = buff.castSpell
                    e.label = ShortLabel(buff.name)
                    if buff.check == "huntersMark" then e.unit = "target" end
                    e.cat = "raidbuff"; e.data = buff; e.scale = rb.scale or 1.0
                    e.dismissKey = buff.key and ("raidbuff:" .. buff.key) or nil
                    missing[#missing+1] = e
                end
            end
        end
    end
end

end

local function CollectAuras(missing, playerClass, specID, inInstance, inCombat)
local au = db.profile.auras
if inInstance or au.showNonInstanced then
    for _, aura in ipairs(AURAS) do
        if aura.standalone then
            -- Handled by standalone system, skip
        elseif au.enabled[aura.key] and (aura.class == playerClass) and Known(aura.castSpell)
           and not (aura.notIfKnown and Known(aura.notIfKnown))
           and not (aura.requireTalent and not Known(aura.requireTalent))
           and not (aura.noPvP and InPvPInstance()) then
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
                -- Skip auras that require a group when solo
                if aura.requireGroup and not (IsInGroup() or IsInRaid()) then
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
                        -- Use instance-specific buff list if available and in instance
                        local checkIDs = (inInstance and aura.instanceBuffIDs) or aura.buffIDs
                        -- In PvP instances the aura API is restricted; fall back to shapeshift
                        -- form index for form-based auras (e.g. Shadowform) where available.
                        if InPvPInstance() and aura.shapeshiftIndex then
                            isMissing = (GetShapeshiftForm() ~= aura.shapeshiftIndex)
                        else
                            isMissing = not PlayerHasAuraByID(checkIDs)
                        end
                    end
                    if isMissing then
                        local e = AcquireEntry()
                        e.mode = "spell"; e.spellID = aura.castSpell
                        e.label = ShortLabel(aura.name)
                        e.cat = "aura"; e.data = aura; e.scale = au.scale or 1.0
                        e.dismissKey = "aura:" .. aura.key
                        missing[#missing+1] = e
                    end
                end
            end
        end
    end
end

end

local function CollectConsumables(missing, playerClass, specID, inInstance, inKeystone, inCombat)
local co = db.profile.consumables
local specialsActive = inInstance or co.showSpecialsNonInstanced
    -- Only check consumables out of combat (secret value protection)
    if not inCombat then

        -- Rebuild the bag/equip-derived item cache only when its inputs changed
        -- (bags, equipped weapon, or a preferred-item setting). Lazy: a clean
        -- refresh just does three scalar compares and returns. Gated on inInstance
        -- because EVERY bag-derived reminder (rune/flask/food/weapon-enchant/inky/
        -- healthstone) is instance-only, so the open world never resolves. The
        -- dirty flag persists until the next in-instance refresh consumes it.
        if inInstance then EABR.ResolveConsumables() end

        -- === SPECIALS (respect showSpecialsNonInstanced) ===
        if specialsActive then
            -- Rogue Poisons: unified scan counts active per category,
            -- compares against required (1 each, or 2 each with Dragon-Tempered Blades).
            -- Shows one reminder per deficient category using the first enabled+known+missing poison.
            if playerClass == "ROGUE" then
                local activeL, activeNL = 0, 0
                local knownL, knownNL = 0, 0
                local missingL, missingNL = nil, nil
                for _, poison in ipairs(ROGUE_POISONS) do
                    if Known(poison.castSpell) then
                        local isLethal = (poison.cat == "lethal")
                        if isLethal then knownL = knownL + 1 else knownNL = knownNL + 1 end
                        local aura = C_UnitAuras.GetPlayerAuraBySpellID(poison.castSpell)
                        if aura then
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
                    e.label = ShortLabel(missingL.name, "ROGUE")
                    e.cat = "consumable"; e.data = missingL; e.scale = co.scale or 1.0
                    e.dismissKey = "consumable:rogue_lethal"
                    missing[#missing+1] = e
                end
                if missingNL and activeNL < reqNL then
                    local e = AcquireEntry()
                    e.mode = "spell"; e.spellID = missingNL.castSpell
                    e.label = ShortLabel(missingNL.name, "ROGUE")
                    e.cat = "consumable"; e.data = missingNL; e.scale = co.scale or 1.0
                    e.dismissKey = "consumable:rogue_nonlethal"
                    missing[#missing+1] = e
                end
            end

            -- Paladin Rites
            if playerClass == "PALADIN" then
                for _, rite in ipairs(PALADIN_RITES) do
                    if co.enabled[rite.key] and Known(rite.castSpell) then
                        local hasMH, mhExpire = GetWeaponEnchantInfo()
                        local show = false
                        if not hasMH then
                            show = true
                        elseif mhExpire and mhExpire > 0 and IsUnderDuration(3600, mhExpire / 1000 + GetTime()) then
                            show = true
                        end
                        if show then
                            local e = AcquireEntry()
                            e.mode = "spell"; e.spellID = rite.castSpell
                            e.label = ShortLabel(rite.name)
                            e.cat = "consumable"; e.data = rite; e.scale = co.scale or 1.0
                            e.dismissKey = "consumable:" .. rite.key
                            missing[#missing+1] = e
                            break -- rites are mutually exclusive weapon enchants
                        end
                    end
                end
            end

            -- Shaman Imbues: match each imbue by its wepEnchID against
            -- both weapon slots. GetWeaponEnchantInfo returns the specific
            -- enchant ID on each hand (4th and 8th return values).
            if playerClass == "SHAMAN" then
                local hasMH, mhExpire, _, mhEnchID, hasOH, ohExpire, _, ohEnchID = GetWeaponEnchantInfo()
                for _, imbue in ipairs(SHAMAN_IMBUES) do
                    if co.enabled[imbue.key] and Known(imbue.castSpell) then
                        local found = false
                        if imbue.wepEnchID then
                            for _, eid in ipairs(imbue.wepEnchID) do
                                if eid > 0 and ((hasMH and mhEnchID == eid) or (hasOH and ohEnchID == eid)) then
                                    -- Use the matched hand's expire time, not min of both.
                                    -- Unenchanted hand returns 0, which would always trigger.
                                    local matchExpire
                                    if hasMH and mhEnchID == eid then
                                        matchExpire = mhExpire
                                    else
                                        matchExpire = ohExpire
                                    end
                                    if matchExpire and matchExpire > 0 and IsUnderDuration(3600, matchExpire / 1000 + GetTime()) then
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
                            e.label = ShortLabel(imbue.name, "SHAMAN_IMBUE")
                            e.cat = "consumable"; e.data = imbue; e.scale = co.scale or 1.0
                            e.dismissKey = "consumable:" .. imbue.key
                            missing[#missing+1] = e
                        end
                    end
                end

                -- Shaman Shields: talent-gated entries.
                -- Earth Shield self-buff (383648) is combat-safe and handled
                -- separately below. Other shields are OOC only.
                for _, shield in ipairs(SHAMAN_SHIELDS) do
                    local castID = shield.castSpellFn and shield.castSpellFn() or shield.castSpell
                    if co.enabled[shield.key] ~= false and Known(castID) then
                        local ok = true
                        if shield.requireTalent and not Known(shield.requireTalent) then ok = false end
                        if shield.excludeTalent and Known(shield.excludeTalent) then ok = false end
                        -- es_orbit is combat-safe, handled below
                        if shield.key == "es_orbit" then ok = false end
                        if ok and not PlayerHasAuraByID(shield.buffIDs) then
                            local e = AcquireEntry()
                            e.mode = "spell"; e.spellID = castID
                            e.label = ShortLabel(shield.name, "SHAMAN_SHIELD")
                            e.cat = "consumable"; e.data = shield; e.scale = co.scale or 1.0
                            e.dismissKey = "consumable:" .. shield.key
                            missing[#missing+1] = e
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
                local hasRuneBuff = InMythicPlusKey() or PlayerHasAuraByID(RUNE_BUFF_IDS)
                if not hasRuneBuff then
                    local runeItem = EABR._resolved.rune.itemID
                    if runeItem then
                        local e = AcquireEntry()
                        e.mode = "item"; e.itemID = runeItem
                        e.texture = GetItemIcon(runeItem); e.label = ShortLabel("Augment Rune")
                        e.cat = "consumable"; e.scale = co.scale or 1.0
                        e.dismissKey = "consumable:rune"
                        missing[#missing+1] = e
                    end
                end
            end
        end

        -- Consumables (weapon enchants, flask, food) only in Mythic dungeons
        -- (M0/M+) and Normal/Heroic/Mythic raids (fixed 16 or flex 233).
        if inInstance and (InMythicPlusKey()
            or (_cachedIType == "party" and (_cachedDiffID == 23 or _cachedDiffID == 8))
            or (_cachedIType == "raid" and (_cachedDiffID == 14 or _cachedDiffID == 15 or IsMythicRaidDiff(_cachedDiffID)))) then

        -- Weapon Enchants (temp weapon enchant items)
        -- Skip if the player knows any imbue spell (Shaman imbues, Paladin rites).
        -- Rogues and DKs are NOT excluded: rogue poisons are temp enchants
        -- (detected by GetWeaponEnchantInfo), and DKs can use oils alongside runeforges.
        local _hasImbueSpell = false
        for _, sid in ipairs(_IMBUE_EXCLUDE_SPELLS) do
            if IsSpellKnown(sid) then _hasImbueSpell = true; break end
        end
        if co.enabled.weapon_enchant and not _hasImbueSpell then
            local hasMH, mhExpire, _, _, hasOH, ohExpire = GetWeaponEnchantInfo()

            -- Check each weapon slot independently (both can show at once).
            -- Remind if: no enchant, OR enchant is under the duration threshold.
            -- Item / category / hasBags are resolved off the hot path; the icon is
            -- derived here at emit so it matches the per-refresh result exactly.
            for _, si in ipairs({{slot=16, has=hasMH, expire=mhExpire}, {slot=17, has=hasOH, expire=ohExpire}}) do
                local r = EABR._resolved.we[si.slot]
                local cat = r.cat
                local shouldRemind = false
                if cat and not si.has then
                    shouldRemind = true
                elseif cat and si.has and si.expire and si.expire > 0 then
                    local expireTime = si.expire / 1000 + GetTime()
                    if IsUnderDuration(3600, expireTime) then
                        shouldRemind = true
                    end
                end
                if shouldRemind and r.itemID then
                    local bestItemID = r.itemID
                    local e = AcquireEntry()
                    e.mode = "macro"
                    e.macro = "/use item:" .. bestItemID .. "\n/use " .. si.slot
                    e.texture = GetItemIcon(bestItemID) or 134400
                    e.label = ShortLabel(si.slot == 16 and "Main Hand" or "Off Hand")
                    e.tooltipItem = bestItemID
                    e.desaturated = not r.hasBags
                    e.cat = "consumable"; e.scale = co.scale or 1.0
                    e.dismissKey = "consumable:weapon_enchant_" .. si.slot
                    missing[#missing+1] = e
                end
            end
        end

        -- Flask (OOC only; detection uses snapshot during keystones and PvP)
        if co.enabled.flask then
            if not PlayerHasFlaskBuff() then
                local rf = EABR._resolved.flask
                local flaskItemID = rf.itemID
                if flaskItemID then
                    local e = AcquireEntry()
                    e.mode = "item"; e.itemID = flaskItemID
                    e.texture = GetItemIcon(flaskItemID) or 134830
                    e.label = "Flask"
                    e.desaturated = not rf.hasBags
                    e.cat = "consumable"; e.scale = co.scale or 1.0
                    e.dismissKey = "consumable:flask"
                    missing[#missing+1] = e
                end
            end
        end

        -- Food / Well Fed (OOC only; detection uses snapshot during keystones)
        if co.enabled.food then
            if not PlayerHasWellFed() then
                local foodItemID = EABR._resolved.food.itemID
                if foodItemID then
                    local e = AcquireEntry()
                    e.mode = "item"; e.itemID = foodItemID
                    e.texture = GetItemIcon(foodItemID) or 134062
                    e.label = "Food"
                    e.cat = "consumable"; e.scale = co.scale or 1.0
                    e.dismissKey = "consumable:food"
                    missing[#missing+1] = e
                end
            end
        end
        end -- InConsumableContent

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
                    local hasPotion = EABR._resolved.inky.hasPotion
                    local hasBuff = PlayerHasAuraByID({INKY_BLACK_BUFF})
                    if not hasBuff and hasPotion then
                        local e = AcquireEntry()
                        e.mode = "item"; e.itemID = INKY_BLACK_ITEM
                        e.texture = GetItemIcon(INKY_BLACK_ITEM)
                        e.label = ShortLabel("Inky Black Potion")
                        e.cat = "consumable"; e.scale = co.scale or 1.0
                        e.dismissKey = "consumable:inky_black"
                        missing[#missing+1] = e
                    end
                end
            end
        end
        end -- end inInstance
    end -- end not inCombat

    -- Earth Shield self-buff (383648): combat-safe, only with Elemental Orbit.
    if specialsActive and playerClass == "SHAMAN" then
        local esOrbit = SHAMAN_SHIELDS[1]  -- es_orbit entry
        if co.enabled[esOrbit.key] ~= false and Known(esOrbit.castSpell)
           and esOrbit.requireTalent and Known(esOrbit.requireTalent) then
            if not PlayerHasAuraByID(esOrbit.buffIDs) then
                local e = AcquireEntry()
                e.mode = "spell"; e.spellID = esOrbit.castSpell
                e.label = ShortLabel(esOrbit.name, "SHAMAN_SHIELD")
                e.cat = "consumable"; e.data = esOrbit; e.scale = co.scale or 1.0
                e.dismissKey = "consumable:" .. esOrbit.key
                missing[#missing+1] = e
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Healthstone in bags (OOC only, instance + group)
    ---------------------------------------------------------------------------
    if not inCombat and inInstance and (IsInGroup() or IsInRaid()) then
        local co = db.profile.consumables
        if co and co.enabled and co.enabled.healthstone ~= false then
            -- Only remind if a Warlock is in the group
            local hasWarlock = false
            if IsInRaid() then
                for i = 1, GetNumGroupMembers() do
                    local _, cls = UnitClass("raid"..i)
                    if cls == "WARLOCK" then hasWarlock = true; break end
                end
            else
                if GetPlayerClass() == "WARLOCK" then
                    hasWarlock = true
                else
                    for i = 1, GetNumSubgroupMembers() do
                        local _, cls = UnitClass("party"..i)
                        if cls == "WARLOCK" then hasWarlock = true; break end
                    end
                end
            end
            local hasHealthstone = EABR._resolved.healthstone.hasStone
            if hasWarlock and not hasHealthstone then
                local e = AcquireEntry()
                e.mode = "texture"; e.texture = 538745
                e.label = "HS"
                e.cat = "consumable"; e.scale = co.scale or 1.0
                e.dismissKey = "consumable:healthstone"
                missing[#missing+1] = e
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Partnered Trinket: Emerald Coach's Whistle (combat-safe via snapshot)
    ---------------------------------------------------------------------------
    do
        local co = db.profile.consumables
        if co and co.enabled and co.enabled.coaches_whistle ~= false
           and inInstance and _cachedDiffID ~= 208
           and (IsInGroup() or IsInRaid())
           and (GetInventoryItemID("player", 13) == 193718 or GetInventoryItemID("player", 14) == 193718) then
            local hasBuff = PlayerHasAuraByID(PARTNERED_TRINKET.buffIDs)
            if not hasBuff then
                local e = AcquireEntry()
                e.mode = "texture"; e.texture = PARTNERED_TRINKET.icon
                e.label = "Whistle"
                e.cat = "consumable"; e.scale = co.scale or 1.0
                e.dismissKey = "consumable:coaches_whistle"
                missing[#missing+1] = e
            end
        end
    end

    ---------------------------------------------------------------------------
    --  DK Runeforging (OOC only, check permanent enchant via item link)
    ---------------------------------------------------------------------------
    if not inCombat and playerClass == "DEATHKNIGHT" then
        local co = db.profile.consumables
        if co and co.enabled and co.enabled.runeforge ~= false then
            local needsRune = false
            for _, slot in ipairs({16, 17}) do
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
                e.label = "Rune"
                e.cat = "consumable"; e.scale = co.scale or 1.0
                e.dismissKey = "consumable:runeforge"
                missing[#missing+1] = e
            end
        end
    end

end

-- CollectTalentReminders moved to EllesmereUIABR_TalentReminders.lua

-- Reusable tables wiped each Refresh() call to avoid per-call allocation.
-- Wrapped to save file-scope local slots (200 limit).
local _refreshMissing, _wasResting = {}, false
local UpdateDurationTicker  -- forward-declare; defined after RequestRefresh

local function Refresh()
    _cachedOutline = nil
    EABR._nextDurationRefreshTime = nil
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

    -- Suppress while dead or in a rested area (city/inn).
    -- Track rested state so combat at training dummies doesn't re-enable reminders.
    if UnitIsDeadOrGhost("player") then
        HideCombatIcons(); HideCursorIcons(); HideAllIcons(); return
    end
    if IsResting() then
        _wasResting = true
        HideCombatIcons(); HideCursorIcons()
        if InCombat() then FadeOutSecureIcons() else HideAllIcons() end
        return
    end
    _wasResting = false

    CacheInstanceInfo()

    -- MEMORY PROBES (temporary -- remove after diagnosis)
    local _memProbe = _G._EABR_MemProbe
    local _m0, _m1, _m2, _m3, _m4, _m5, _m6, _m7
    if _memProbe then collectgarbage("stop"); _m0 = collectgarbage("count") end

    local _pt = EABR.ProfBegin("AuraCache")
    BuildPlayerAuraCache()
    EABR.ProfEnd("AuraCache", _pt)
    if _memProbe then _m1 = collectgarbage("count") end

    local playerClass = GetPlayerClass()
    local inCombat = InCombat()

    -- Collect missing reminders (reuse pooled entry tables)
    ResetEntryPool()
    local missing = _refreshMissing
    wipe(missing)

    local remindersOn = db.profile.display.remindersEnabled ~= false

    ---------------------------------------------------------------------------
    --  1) Raid Buffs (runs in and out of combat)
    ---------------------------------------------------------------------------
    if remindersOn then
        local inInstance = InRealInstancedContent()
        _pt = EABR.ProfBegin("RaidBuffs")
        CollectRaidBuffs(missing, playerClass, inInstance, inCombat)
        EABR.ProfEnd("RaidBuffs", _pt)
    end
    if _memProbe then _m2 = collectgarbage("count") end

    ---------------------------------------------------------------------------
    --  OOC-only sections: skip entirely during combat (only raid buffs
    --  and pet reminders can display in combat).
    ---------------------------------------------------------------------------
    local specID, inInstance, inKeystone, inPvP
    if not inCombat then
        specID = GetSpecID()
        inInstance = inInstance or InRealInstancedContent()
        inKeystone = InMythicPlusKey()
        inPvP = InPvPInstance()
    end

    ---------------------------------------------------------------------------
    --  2) Auras (suppressed in M+ keystones and combat)
    ---------------------------------------------------------------------------
    if remindersOn and not inCombat and not inKeystone then
        _pt = EABR.ProfBegin("Auras")
        CollectAuras(missing, playerClass, specID, inInstance, inCombat)
        EABR.ProfEnd("Auras", _pt)
    end
    if _memProbe then _m3 = collectgarbage("count") end

    ---------------------------------------------------------------------------
    --  3) Consumables (suppressed in M+ keystones, combat, and PvP)
    ---------------------------------------------------------------------------
    if remindersOn and not inCombat and not inKeystone and not inPvP then
        _pt = EABR.ProfBegin("Consumables")
        CollectConsumables(missing, playerClass, specID, inInstance, inKeystone, inCombat)
        EABR.ProfEnd("Consumables", _pt)
    end
    if _memProbe then _m4 = collectgarbage("count") end

    ---------------------------------------------------------------------------
    --  4) Pet Reminders (combat-safe: UnitExists/UnitIsDead are not restricted)
    --  Suppressed for petless specs, Grimoire of Sacrifice, etc.
    ---------------------------------------------------------------------------
    if remindersOn and PET_CLASSES[playerClass] then
        local co = db.profile.consumables
        if co and co.enabled and co.enabled.pet ~= false then
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
            if not suppress and not (UnitExists("pet") and not UnitIsDead("pet")) then
                local e = AcquireEntry()
                e.mode = "texture"
                e.texture = petIcon
                e.label = petLabel
                e.cat = "consumable"; e.scale = co.scale or 1.0
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
                    e.label = "Felguard"
                    e.cat = "consumable"; e.scale = co.scale or 1.0
                    e.dismissKey = "consumable:wrong_pet"
                    missing[#missing+1] = e
                end
            end
        end
    end

    -- Talent reminders handled by EllesmereUIABR_TalentReminders.lua
    if _memProbe then _m5 = collectgarbage("count") end


    ---------------------------------------------------------------------------
    --  Apply results
    ---------------------------------------------------------------------------
    if inCombat then
        _pt = EABR.ProfBegin("Display")
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
                    -- Only show reminders with all-whitelisted buff IDs.
                    -- huntersMark uses a state flag, always safe.
                    local safe = false
                    if m.mode == "texture" then
                        safe = true  -- texture-mode entries (pets) use no aura API
                    elseif m.data and m.data.check == "huntersMark" then
                        safe = true
                    elseif m.data and m.data.buffIDs then
                        safe = true
                        for _, id in ipairs(m.data.buffIDs) do
                            if not NON_SECRET_SPELL_IDS[id] then safe = false; break end
                        end
                    end
                    if safe then
                        local spellID = m.data and m.data.castSpell
                        local texture = m.texture or (spellID and Tex(spellID)) or 134400
                        local label = m.label or (m.data and ShortLabel(m.data.name)) or ""
                        local f
                        if useCursor and IsImportantBuff(m) then
                            cursorIdx = cursorIdx + 1
                            ShowCursorIcon(cursorIdx, spellID, texture, label)
                            f = cursorActiveIcons[#cursorActiveIcons]
                        else
                            combatIdx = combatIdx + 1
                            ShowCombatIcon(combatIdx, spellID, texture, label)
                            f = combatActiveIcons[#combatActiveIcons]
                        end
                        if f then
                            RemoveGlow(f)
                            local p = db.profile.display
                            local gc = p.glowColor or DEFAULT_GLOW_COLOR
                            local baseScale = p.scale or 1.0
                            local sz = floor(ICON_SIZE * baseScale + 0.5)
                            ApplyGlow(f, p.glowType or 0, gc.r, gc.g, gc.b, sz)
                        end
                    end
                end
            end
            if combatIdx > 0 then EllesmereUI.SetElementVisibility(combatAnchor, true); LayoutCombatIcons() end
            if cursorIdx > 0 then cursorAnchor:Show(); EllesmereUI.SetElementVisibility(cursorAnchor, true); LayoutCursorIcons() end
        end
        EABR.ProfEnd("Display", _pt)
        return
    end

    -- OOC path: full secure button display
    _pt = EABR.ProfBegin("Display")
    HideCombatIcons()
    HideCursorIcons()
    HideAllIcons()

    if #missing > 0 then
        -- Cursor attach applies OOC too (it only routed in the combat path
        -- before, which read as "works only in combat"). Cursor icons are
        -- visual-only: an important buff routed here trades its secure
        -- click-to-cast for the at-cursor placement, same as in combat.
        local useCursor = db.profile.display.cursorAttach and cursorAnchor
        local iconIdx, cursorIdx = 0, 0
        for _, m in ipairs(missing) do
            local dk = m.dismissKey or (m.data and m.data.key and (m.cat .. ":" .. m.data.key)) or nil
            if not dk or not _dismissedUntilLoad[dk] then
                if useCursor and IsImportantBuff(m) then
                    local spellID = m.data and m.data.castSpell
                    local texture = m.texture or (spellID and Tex(spellID)) or 134400
                    local label = m.label or (m.data and ShortLabel(m.data.name)) or ""
                    cursorIdx = cursorIdx + 1
                    ShowCursorIcon(cursorIdx, spellID, texture, label)
                    local f = cursorActiveIcons[#cursorActiveIcons]
                    if f then
                        RemoveGlow(f)
                        local p = db.profile.display
                        local gc = p.glowColor or DEFAULT_GLOW_COLOR
                        local baseScale = p.scale or 1.0
                        local sz = floor(ICON_SIZE * baseScale + 0.5)
                        ApplyGlow(f, p.glowType or 0, gc.r, gc.g, gc.b, sz)
                    end
                else
                    iconIdx = iconIdx + 1
                    ShowIcon(iconIdx, m)
                end
            end
        end
        if cursorIdx > 0 then
            cursorAnchor:Show()
            EllesmereUI.SetElementVisibility(cursorAnchor, true)
            LayoutCursorIcons()
        end
        if iconIdx > 0 then
            LayoutIcons()
            EllesmereUI.SetElementVisibility(iconAnchor, true)
        else
            EllesmereUI.SetElementVisibility(iconAnchor, false)
        end
    else
        EllesmereUI.SetElementVisibility(iconAnchor, false)
    end

    EABR.ProfEnd("Display", _pt)

    -- MEMORY PROBE REPORT (temporary)
    if _memProbe then
        _m6 = collectgarbage("count")
        collectgarbage("restart")
        _memProbe.n = (_memProbe.n or 0) + 1
        _memProbe.auraCache  = (_memProbe.auraCache  or 0) + (_m1 - _m0)
        _memProbe.raidBuffs  = (_memProbe.raidBuffs  or 0) + (_m2 - _m1)
        _memProbe.auras      = (_memProbe.auras      or 0) + (_m3 - _m2)
        _memProbe.consumables= (_memProbe.consumables or 0) + (_m4 - _m3)
        _memProbe.talents    = (_memProbe.talents    or 0) + (_m5 - _m4)
        _memProbe.display    = (_memProbe.display    or 0) + (_m6 - _m5)
        _memProbe.total      = (_memProbe.total      or 0) + (_m6 - _m0)
        if _memProbe.n >= 20 then
            _memProbe.n = 0; _memProbe.auraCache = 0; _memProbe.raidBuffs = 0
            _memProbe.auras = 0; _memProbe.consumables = 0; _memProbe.talents = 0
            _memProbe.display = 0; _memProbe.total = 0
        end
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

-- Duration-threshold timer: arm one refresh for the next known buff/enchant
-- threshold crossing instead of polling while idle.
UpdateDurationTicker = function()
    if EABR._durationTimer then
        EABR._durationTimer:Cancel()
        EABR._durationTimer = nil
    end

    if not (EABR._nextDurationRefreshTime and db and not InCombat() and not InMythicPlusKey()) then
        return
    end

    local delay = EABR._nextDurationRefreshTime - GetTime() + 0.1
    if delay < 0.1 then delay = 0.1 end

    EABR._durationTimer = C_Timer.NewTimer(delay, function()
        EABR._durationTimer = nil
        if InCombat() or InMythicPlusKey() then return end
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
            -- For CENTER anchor, use SnapCenterForDim with the frame's
            -- actual size so odd-pixel-dim frames get the +0.5 center
            -- offset that places their edges on whole pixels.
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
        -- Convert legacy CENTER offset to TOPLEFT
        local d = db.profile.display
        local baseScale = d.scale or 1.0
        local sz = floor(ICON_SIZE * baseScale + 0.5)
        local spacing = d.iconSpacing or 8
        local count = max(#activeIcons, 2)
        local w = count * sz + (count - 1) * spacing
        local textH = 0
        if d.showText then
            textH = (d.textSize or 11) + abs(d.textYOffset or -2)
        end
        local h = sz + textH
        iconAnchor:SetSize(w, h)
        local uiW = UIParent:GetWidth()
        local uiH = UIParent:GetHeight()
        local cx = uiW * 0.5 + (d.xOffset or 0)
        local cy = uiH * 0.5 + (d.yOffset or 0)
        iconAnchor:ClearAllPoints()
        iconAnchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", cx - w * 0.5, cy - uiH + h * 0.5)
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
            getFrame = function() return iconAnchor end,
            getSize = function()
                local p = db.profile.display
                local baseScale = p.scale or 1.0
                local sz = floor(ICON_SIZE * baseScale + 0.5)
                local spacing = p.iconSpacing or 8
                local count = max(#activeIcons, 2)
                local w = count * sz + (count - 1) * spacing
                local textH = 0
                if p.showText then
                    textH = (p.textSize or 11) + abs(p.textYOffset or -2)
                end
                local h = sz + textH
                -- Keep iconAnchor sized correctly so Sync() never sees it as a tiny anchor
                if iconAnchor then ResizeAnchorCentered(w, h) end
                return w, h
            end,
            linkedDimensions = true,
            setWidth = function(_, newW)
                if not EllesmereUI._unlockActive then return end
                local p = db.profile.display
                local spacing = p.iconSpacing or 8
                local count = max(#activeIcons, 2)
                local sz = (newW - (count - 1) * spacing) / count
                if sz < 8 then sz = 8 end
                p.scale = sz / ICON_SIZE
                if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
            end,
            setHeight = function(_, newH)
                if not EllesmereUI._unlockActive then return end
                local p = db.profile.display
                local textH = 0
                if p.showText then
                    textH = (p.textSize or 11) + abs(p.textYOffset or -2)
                end
                local sz = newH - textH
                if sz < 8 then sz = 8 end
                p.scale = sz / ICON_SIZE
                if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
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
        if not db or not db.char then return end
        if flaskSet[itemID] then db.char.lastUsedFlask = itemID
        elseif foodSet[itemID] then db.char.lastUsedFood = itemID
        elseif weSet[itemID] then db.char.lastUsedWeaponEnchant = itemID end
    end
end

-------------------------------------------------------------------------------
--  Standalone Beacon Reminders — IsSpellOverlayed-based, combat-safe.
--  Independent from the main aura/buff system.
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
    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    SetABRFont(text, ResolveFontPath(), 11)
    text:SetTextColor(1, 1, 1, 1)
    f._text = text
    return f
end

local function BeaconLayoutIcons()
    -- Beacon icons are now merged into the main LayoutIcons row.
    -- Just trigger a main refresh so they appear in the unified line.
    -- Hide the separate beacon anchor since we don't use it anymore.
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
            local gc = p and p.glowColor or DEFAULT_GLOW_COLOR
            local baseScale = p and p.scale or 1.0
            local sz = floor(ICON_SIZE * baseScale + 0.5)
            ApplyGlow(f, glowType, gc.r, gc.g, gc.b, sz)
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
        f._text:SetPoint("TOP", f, "BOTTOM", xOff, yOff)
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

    -- Anchor follows the main combat anchor position
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
        -- Invalidate cached spell textures for beacon spells so dynamic
        -- icon changes (e.g. BOL morphing to Virtue) pick up the new icon.
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

-- Toggle broad vs player-only UNIT_AURA registration.
-- Defined at file scope so both OnEnable and the event handler can use it.
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
--  Lifecycle: OnInitialize (fires at ADDON_LOADED time)
--  Creates the DB early so EABR is in _dbRegistry before PreSeedSpecProfile.
-------------------------------------------------------------------------------
function EABR:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUIAuraBuffRemindersDB", defaults, true)
end

-------------------------------------------------------------------------------
--  Lifecycle: OnEnable (fires at PLAYER_LOGIN time, after PreSeedSpecProfile)
--  All UI creation and event wiring that depends on db being ready.
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

    local STRATA_VALUES = {
        BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium",
        HIGH = "High", DIALOG = "Dialog", FULLSCREEN = "Fullscreen",
        FULLSCREEN_DIALOG = "Fullscreen Dialog", TOOLTIP = "Tooltip",
    }
    local STRATA_ORDER = {
        "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG",
        "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP",
    }
    _G._EABR_STRATA_VALUES = STRATA_VALUES
    _G._EABR_STRATA_ORDER = STRATA_ORDER

    -- Create anchor
    iconAnchor = CreateFrame("Frame", "EABR_Anchor", UIParent)
    iconAnchor:SetSize(1, 1)
    iconAnchor:SetFrameStrata(GetStrata())
    iconAnchor:EnableMouse(false)
    ApplyUnlockPos()

    -- Create combat anchor (non-secure, follows iconAnchor position)
    -- Parented to UIParent so Show/Hide is never blocked by combat lockdown.
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
        local lastMX, lastMY
        cursorAnchor:SetScript("OnUpdate", function()
            local s = UIParent:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx = floor(cx / s + 0.5)
            cy = floor(cy / s + 0.5)
            if cx ~= lastMX or cy ~= lastMY then
                lastMX, lastMY = cx, cy
                cursorAnchor:ClearAllPoints()
                cursorAnchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy + 60)
            end
        end)
    end
    -- Start hidden: OnUpdate only runs while :IsShown(), saving CPU
    -- when no cursor-attached reminders are active.
    cursorAnchor:Hide()
    EllesmereUI.SetElementVisibility(cursorAnchor, false)

    -- Create talent reminder anchor (independent of iconAnchor so parent alpha doesn't hide it)
    -- Talent anchor created by EllesmereUIABR_TalentReminders.lua

    local function ApplyStrata()
        local strata = GetStrata()
        iconAnchor:SetFrameStrata(strata)
        combatAnchor:SetFrameStrata(strata)
        for _, btn in pairs(iconPool) do btn:SetFrameStrata(strata) end
        for _, f in pairs(combatIconPool) do f:SetFrameStrata(strata) end
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

    RequestRefresh()
    BeaconInit()
    C_Timer.After(0.5, RegisterUnlockElements)

    -- Register broad UNIT_AURA only when the player's class actually needs
    -- group aura tracking AND only while out of combat.  Broad UNIT_AURA
    -- fires 100+ times/sec in a raid; in combat, CollectRaidBuffs only
    -- checks the player's own auras (PlayerHasAuraByID), so group events
    -- are pure waste.  Evoker keeps broad in combat for ownOnRaid cache
    -- updates but skips RequestRefresh on group events (handler below).
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
    --  Range updates. UNIT_IN_RANGE_UPDATE mirrors the raid frames' range
    --  path, so range changes retrigger group-buff evaluation without polling.
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
        -- Mark combat immediately: ENCOUNTER_START fires before
        -- InCombatLockdown() returns true, but aura APIs are already
        -- restricted. Without this, all non-whitelisted buffs flash
        -- as "missing" for ~1s until PLAYER_REGEN_DISABLED fires.
        _eabrInCombat = true
        RequestRefresh()
        return
    end

    if e == "PLAYER_REGEN_DISABLED" then
        -- Drop broad UNIT_AURA during combat unless we need group tracking.
        -- Evoker keeps broad for ownOnRaid cache updates; showOthersMissing
        -- keeps broad so AnyGroupMemberMissingBuff gets timely refreshes.
        local keepBroad = _isEvokerOwnOnRaid or (db and db.profile.raidBuffs and db.profile.raidBuffs.showOthersMissing)
        if _needGroupAura and not keepBroad then _setBroad(false) end
        -- Only flag Hunter's Mark needed if the target doesn't already have it
        _huntersMarkNeeded = true
        if C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
            and UnitExists("target") and C_UnitAuras.GetUnitAuraBySpellID("target", 257284) then
            _huntersMarkNeeded = false
        end
        -- Hide secure buttons BEFORE setting combat flag (HideAllIcons
        -- checks InCombat and returns early if true). PLAYER_REGEN_DISABLED
        -- fires before InCombatLockdown() returns true, so Hide() is safe.
        HideAllIcons()
        HideCursorIcons()
        _eabrInCombat = true
        -- Only re-snapshot if ENCOUNTER_START didn't just snapshot (it fires
        -- milliseconds before REGEN_DISABLED and produces a cleaner snapshot
        -- since the aura API is fully available pre-lockdown).
        if not _encounterSnapshotTime or (GetTime() - _encounterSnapshotTime) > 1 then
            SnapshotPlayerAuras()
            if _isEvokerOwnOnRaid then SnapshotOwnOnRaidBuffs() end
        end
        _encounterSnapshotTime = nil
        RequestRefresh()
        return
    end

    if e == "PLAYER_REGEN_ENABLED" then
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

    if e == "PLAYER_ENTERING_WORLD" then
        wipe(_dismissedUntilLoad)
        RequestRefresh()
        -- Deferred refresh: GetInstanceInfo() can return stale data on the
        -- first frame after a loading screen. A second refresh after 0.5s
        -- picks up the correct zone for talent reminders and consumables.
        C_Timer.After(0.5, RequestRefresh)
        return
    end

    if e == "UNIT_AURA" then
        -- arg1 = unit token. Player aura changes always refresh.
        -- Group member aura changes only matter for Evoker ownOnRaid
        -- cache updates and OOC raid buff checks. The broad UNIT_AURA
        -- event is only registered for classes that need group tracking
        -- (see UpdateGroupAuraRegistration).
        if arg1 == "player" then
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
            -- Group member aura change. Fast unit-type check via first byte.
            -- Broad UNIT_AURA stays registered in combat for Evoker ownOnRaid
            -- and for showOthersMissing raid buff tracking. Coalesce group
            -- events into a single deferred refresh to avoid per-event spam.
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

    -- Roster changes don't affect player buffs/consumables. Skip the
    -- full refresh (which scans all group members via AnyGroupMemberMissingBuff).
    if e == "GROUP_ROSTER_UPDATE" then return end

    -- Bag CONTENT changes (BAG_UPDATE/_DELAYED) change item counts and which item
    -- we resolve, so re-scan. BAG_UPDATE_COOLDOWN is intentionally NOT handled (or
    -- registered): it fires ~1/sec from item cooldown ticks, changes neither
    -- counts nor any reminder, and was both refreshing every second and busting
    -- the resolved-item cache (re-running the ~1ms resolve on every refresh).
    if e == "BAG_UPDATE_DELAYED" or e == "BAG_UPDATE" then
        InvalidateItemCountCache()
    end

    -- Equipped-weapon changes alter weapon-enchant resolution (weapon type ->
    -- which enchant item and which slots can show). Item counts are unchanged,
    -- so only the resolved cache needs rebuilding; the next refresh re-resolves.
    if e == "UNIT_INVENTORY_CHANGED" then
        -- UNIT_INVENTORY_CHANGED also fires for temp weapon enchants, trinket
        -- procs, durability, etc. Only the equipped WEAPON TYPE feeds resolution,
        -- so re-resolve only when a weapon category actually changed (vs the last
        -- resolved cat, which ResolveConsumables keeps current).
        local R = EABR._resolved
        if GetWeaponCategory(16) ~= R.we[16].cat or GetWeaponCategory(17) ~= R.we[17].cat then
            R.dirty = true
        end
    end

    -- All other events: just refresh
    RequestRefresh()
end)

-- Item use tracking: _bagCounts (built by RebuildBagCounts, shared with the
-- consumable item-count cache) is the single source of truth for bag contents.
-- On BAG_UPDATE_DELAYED rebuild it ONCE and diff against the previous snapshot
-- to detect items whose count dropped (used) -- no second bag walk. The main
-- handler's InvalidateItemCountCache runs first (sets _itemCountDirty), so the
-- rebuild here also serves the deferred consumable refresh that follows.
local _prevBagCounts = {}

local function DetectUsedItem()
    if not db or not db.char then return end
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

-------------------------------------------------------------------------------
--  Ready Check Mana Warning
--  Shows a centered text warning for ~10 seconds when a ready check fires
--  in a raid group and the player is a healer with < 80% mana.
--  Out-of-combat only.
-------------------------------------------------------------------------------
do
    local warnFrame, warnFS, warnTimer, warnCurve

    local function HideWarning()
        if warnFrame then
            if warnFrame._breathe then warnFrame._breathe:Stop() end
            warnFrame:Hide()
        end
        if warnTimer then warnTimer:Cancel(); warnTimer = nil end
    end

    local function BuildWarnFrame()
        if warnFrame then return end
        warnFrame = CreateFrame("Frame", nil, UIParent)
        warnFrame:SetSize(600, 60)
        warnFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 75)
        warnFrame:SetFrameStrata("FULLSCREEN")
        warnFrame:SetFrameLevel(100)
        warnFrame:Hide()
        warnFS = warnFrame:CreateFontString(nil, "OVERLAY")
        local font = ResolveFontPath()
        local outline = GetABROutline()
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(warnFS, outline == "" and GetABRUseShadow()) end
        warnFS:SetFont(font, 48, outline)
        warnFS:SetPoint("CENTER")
        warnFS:SetText("LOW MANA")
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
        -- Curve: alpha 1 at/below 80%, alpha 0 above.
        -- The curve colors the FontString directly via SetVertexColor,
        -- using alpha to control visibility -- no secret value reads.
        if C_CurveUtil and C_CurveUtil.CreateColorCurve then
            warnCurve = C_CurveUtil.CreateColorCurve()
            local mc = EllesmereUI.GetPowerColor("MANA")
            local r = math.min(mc.r * 1.5, 1)
            local g = math.min(mc.g * 1.5, 1)
            local b = math.min(mc.b * 1.5, 1)
            warnCurve:AddPoint(0.0,    CreateColor(r, g, b, 1))
            warnCurve:AddPoint(0.80,   CreateColor(r, g, b, 1))
            warnCurve:AddPoint(0.8001, CreateColor(r, g, b, 0))
            warnCurve:AddPoint(1.0,    CreateColor(r, g, b, 0))
        end
    end

    -- Only listen for READY_CHECK when out of combat AND in a raid.
    -- GROUP_ROSTER_UPDATE / zone change track raid membership.
    -- PLAYER_REGEN toggles combat state.
    local rcFrame = CreateFrame("Frame")
    local _inRaid = false

    local function UpdateReadyCheckRegistration()
        local shouldListen = _inRaid and not InCombatLockdown()
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
        local spec = GetSpecialization and GetSpecialization()
        if not spec then return end
        local role = GetSpecializationRole(spec)
        if role ~= "HEALER" then return end
        if not UnitPowerPercent then return end
        BuildWarnFrame()
        if not warnCurve then return end
        -- Let WoW's C side evaluate mana % against the curve.
        -- Result: mana color at full alpha if below 80%, zero alpha if above.
        -- SetVertexColor applies the secret RGBA directly -- no reads needed.
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
end

