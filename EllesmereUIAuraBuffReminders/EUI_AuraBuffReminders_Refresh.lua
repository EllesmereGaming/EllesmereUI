if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_AuraBuffReminders_Refresh.lua
--
--  The WoW Forever collectors, Refresh and its throttle, the Forever group
--  watch and the duration ticker.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._abrInternals
-- EllesmereUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local floor = math.floor

local CacheInstanceInfo, EABR, GetPlayerClass = I.CacheInstanceInfo, I.EABR, I.GetPlayerClass
local GetSpecID, InCombat, InMythicPlusKey = I.GetSpecID, I.InCombat, I.InMythicPlusKey
local InPvPInstance, InRealInstancedContent = I.InPvPInstance, I.InRealInstancedContent
local isSecret, Known, ShortLabel, SpellName = I.isSecret, I.Known, I.ShortLabel, I.SpellName
local Tex, _unitInRange, _unitOk = I.Tex, I._unitInRange, I._unitOk
local BuildPlayerAuraCache, PlayerHasAuraByID = I.BuildPlayerAuraCache, I.PlayerHasAuraByID
local PET_CLASSES, RAID_BUFFS, WARLOCK_PETS = I.PET_CLASSES, I.RAID_BUFFS, I.WARLOCK_PETS
local _dismissedUntilLoad, AcquireEntry = I._dismissedUntilLoad, I.AcquireEntry
local ApplyGlow, combatActiveIcons = I.ApplyGlow, I.combatActiveIcons
local cursorActiveIcons, FadeOutSecureIcons = I.cursorActiveIcons, I.FadeOutSecureIcons
local HideCombatIcons, HideCursorIcons = I.HideCombatIcons, I.HideCursorIcons
local ICON_SIZE, IsImportantBuff = I.ICON_SIZE, I.IsImportantBuff
local LayoutCombatIcons, LayoutCursorIcons = I.LayoutCombatIcons, I.LayoutCursorIcons
local ResetEntryPool, ShowCombatIcon = I.ResetEntryPool, I.ShowCombatIcon
local ShowCursorIcon, CollectAuras = I.ShowCursorIcon, I.CollectAuras
local CollectConsumables, CollectRaidBuffs = I.CollectConsumables, I.CollectRaidBuffs
local HideAllIcons, LayoutIcons, ShowIcon = I.HideAllIcons, I.LayoutIcons, I.ShowIcon
local SetCachedOutline, CursorAttachActive = I.SetCachedOutline, I.CursorAttachActive

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
local euiPanelOpen = false
I.panelOpenSetters[#I.panelOpenSetters + 1] = function(v) euiPanelOpen = v end
local iconAnchor
I.iconAnchorSetters[#I.iconAnchorSetters + 1] = function(v) iconAnchor = v end
local combatAnchor
I.combatAnchorSetters[#I.combatAnchorSetters + 1] = function(v) combatAnchor = v end
local cursorAnchor
I.cursorAnchorSetters[#I.cursorAnchorSetters + 1] = function(v) cursorAnchor = v end

local refreshQueued = false

-- Reusable tables wiped each Refresh() call to avoid per-call allocation.
local _refreshMissing = {}
local UpdateDurationTicker  -- forward-declare; defined after RequestRefresh

-- WoW Forever rank families of the custom spell IDs: an ID stands for itself,
-- every spellbook entry with its name (each rank the player knows is its own
-- spell there) and the shared buff family that lists it (every rank, the group
-- version, other casters' versions: EllesmereUI.FOREVER_BUFF_FAMILIES). One
-- spellbook pass resolves every tracked ID, run again only after a spell is
-- learned (LEARNED_SPELL_IN_SKILL_LINE sets _fvFamDirty) or when an ID joins
-- the list; the families then serve every refresh as they are.
function EABR.ForeverFamily(id)
    local fams = EABR._fvFams
    if not (fams and fams[id]) or EABR._fvFamDirty then
        EABR.BuildForeverFamilies()
        fams = EABR._fvFams
    end
    return fams[id]
end

function EABR.BuildForeverFamilies()
    EABR._fvFamDirty = false
    local fams = EABR._fvFams
    if fams then wipe(fams) else fams = {}; EABR._fvFams = fams end
    -- The families with a rank in this character's spellbook (spell groups:
    -- EABR.CollectForeverGroups), from the same pass.
    local known = EABR._fvKnownFams
    if known then wipe(known) else known = {}; EABR._fvKnownFams = known end
    local fo = db.profile.forever
    local custom = fo and fo.customIDs
    local groups = fo and fo.customGroups
    if not ((custom and custom[1]) or (groups and groups[1])) then return end
    local familyOf = EABR._fvFamilyOf
    if not familyOf then
        familyOf = {}
        for _, shared in pairs(EllesmereUI.FOREVER_BUFF_FAMILIES) do
            for _, sid in ipairs(shared.ids) do familyOf[sid] = shared end
        end
        EABR._fvFamilyOf = familyOf
    end
    -- name -> the families its spellbook entries join
    local byName = {}
    local function buildFamilyFor(spellID)
        if type(spellID) ~= "number" or fams[spellID] then return end
        local list = { spellID }
        local shared = familyOf[spellID]
        if shared then
            for _, sid in ipairs(shared.ids) do
                if sid ~= spellID then list[#list + 1] = sid end
            end
        end
        fams[spellID] = list
        local name = SpellName(spellID)
        if name then
            local into = byName[name]
            if not into then into = {}; byName[name] = into end
            into[#into + 1] = list
        end
    end
    if custom then
        for _, spellID in ipairs(custom) do buildFamilyFor(spellID) end
    end
    -- Group members get the same rank expansion, from the same spellbook pass.
    if groups then
        for _, group in ipairs(groups) do
            local groupSpellIDs = type(group) == "table" and group.ids
            if type(groupSpellIDs) == "table" then
                for _, spellID in ipairs(groupSpellIDs) do buildFamilyFor(spellID) end
            end
        end
    end
    if not next(byName) then return end
    local bank = Enum.SpellBookSpellBank.Player
    local SPELL = Enum.SpellBookItemType.Spell
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        local offset = info and info.itemIndexOffset or 0
        for slot = offset + 1, offset + (info and info.numSpellBookItems or 0) do
            local kind, _, sid = C_SpellBook.GetSpellBookItemType(slot, bank)
            local into = kind == SPELL and sid and byName[C_Spell.GetSpellName(sid)]
            if into then
                for _, list in ipairs(into) do
                    local listed = false
                    for k = 1, #list do
                        if list[k] == sid then listed = true; break end
                    end
                    if not listed then list[#list + 1] = sid end
                    known[list] = true
                end
            end
        end
    end
end

-- WoW Forever spell groups: one reminder per group while no aura from its
-- spells (or their ranks, EABR.ForeverFamily) is active, out of combat only.
-- While the client hides aura data from addons (AuraKit.AurasRestricted), a
-- group counts as having no active aura only if none of its spells is flagged
-- secret, so a hidden aura is not read as absent. A group shows only for a
-- character that knows one of its spells (a rank in the spellbook): groups are
-- profile settings, so one made on another class shows nothing here. The icon
-- is the first such spell's; the tooltip names the group (no spell on the
-- entry). Dismiss keys are per group table (weak), so removing or renaming a
-- group never hands its dismissal to another.
function EABR.CollectForeverGroups(missing, groups)
    local dismissKeys = EABR._fvGroupKeys
    if not dismissKeys then
        dismissKeys = setmetatable({}, { __mode = "k" })
        EABR._fvGroupKeys = dismissKeys
        EABR._fvGroupN = 0
    end
    local aurasRestricted = EllesmereUI.AuraKit and EllesmereUI.AuraKit.AurasRestricted()
    for _, group in ipairs(groups) do
        local spellIDs = type(group) == "table" and group.ids
        if type(spellIDs) == "table" then
            local iconSpellID, hasActiveAura
            local allAurasReadable = true
            for _, spellID in ipairs(spellIDs) do
                local rankSpellIDs = type(spellID) == "number" and SpellName(spellID)
                    and EABR.ForeverFamily(spellID)
                if rankSpellIDs then
                    if not iconSpellID and EABR._fvKnownFams[rankSpellIDs] then iconSpellID = spellID end
                    if PlayerHasAuraByID(rankSpellIDs) then hasActiveAura = true; break end
                    if aurasRestricted and not EABR.FvRanksReadable(rankSpellIDs) then
                        allAurasReadable = false
                    end
                end
            end
            if iconSpellID and allAurasReadable and not hasActiveAura then
                local dismissKey = dismissKeys[group]
                if not dismissKey then
                    EABR._fvGroupN = EABR._fvGroupN + 1
                    dismissKey = "forever:g" .. EABR._fvGroupN
                    dismissKeys[group] = dismissKey
                end
                local entry = AcquireEntry()
                entry.mode = "texture"
                entry.texture = Tex(iconSpellID)
                entry.label = type(group.name) == "string" and group.name
                    or ShortLabel(SpellName(iconSpellID))
                entry.cat = "forever"; entry.dismissKey = dismissKey
                missing[#missing+1] = entry
            end
        end
    end
end

-- WoW Forever collector: the Camp Benefits campfire buff, Well Fed (any food
-- buff: the shared Well Fed name, or one of EABR.FOOD_BUFFS), the user's spell
-- groups (EABR.CollectForeverGroups) and custom spell IDs, absence only (no
-- expiry thresholds). A custom ID counts as
-- up while any spell of its rank family is (EABR.ForeverFamily). Entries are
-- display-only textures carrying the spell for the tooltip; presence goes
-- through PlayerHasAuraByID, so combat falls back to the pre-pull snapshot
-- exactly like the Auras section. Camp Benefits and Well Fed are skipped under
-- the aura lock and in PvP. The one-slot id table, the cached families and the
-- dismiss-key memo keep the pass allocation-free.
function EABR.CollectForever(missing, inInstance, inPvP, restricted)
    local fo = db.profile.forever
    if not fo or not EABR.SectionShows(fo.whereToShow, inInstance) then return end
    local ids = EABR._foreverIDs
    if not ids then ids = {}; EABR._foreverIDs = ids end
    if fo.camp ~= false and not inPvP and not restricted then
        ids[1] = EABR.CAMP_BENEFITS
        if not PlayerHasAuraByID(ids) then
            local e = AcquireEntry()
            e.mode = "texture"; e.spellID = EABR.CAMP_BENEFITS
            e.texture = Tex(EABR.CAMP_BENEFITS)
            e.label = EllesmereUI.L("Camp")
            e.cat = "forever"; e.dismissKey = "forever:camp"
            missing[#missing+1] = e
        end
    end
    if fo.wellFed and not inPvP and not restricted then
        local name = SpellName(EABR.WELL_FED) or "Well Fed"
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
        if ok and not isSecret(aura) and not aura and not PlayerHasAuraByID(EABR.FOOD_BUFFS) then
            local e = AcquireEntry()
            e.mode = "texture"; e.spellID = EABR.WELL_FED
            e.texture = Tex(EABR.WELL_FED)
            e.label = name
            e.cat = "forever"; e.dismissKey = "forever:wellfed"
            missing[#missing+1] = e
        end
    end
    local groups = fo.customGroups
    if groups and groups[1] and not restricted then
        EABR.CollectForeverGroups(missing, groups)
    end
    local custom = fo.customIDs
    if not custom then return end
    local keys = EABR._foreverKeys
    if not keys then keys = {}; EABR._foreverKeys = keys end
    -- Out of combat under the aura lock a secret aura reads absent, so a custom
    -- spell shows only while none of its ranks is secret (combat reads the
    -- pre-pull snapshot instead).
    local auraLock = not restricted and EllesmereUI.AuraKit and EllesmereUI.AuraKit.AurasRestricted()
    for i = 1, #custom do
        local id = custom[i]
        local fam = EABR.ForeverFamily(id)
        if not PlayerHasAuraByID(fam) and not (auraLock and fam and not EABR.FvRanksReadable(fam)) then
            local dk = keys[id]
            if not dk then dk = "forever:" .. id; keys[id] = dk end
            local e = AcquireEntry()
            e.mode = "texture"; e.spellID = id
            e.texture = Tex(id)
            e.label = ShortLabel(SpellName(id) or tostring(id))
            e.cat = "forever"; e.dismissKey = dk
            missing[#missing+1] = e
        end
    end
end

-------------------------------------------------------------------------------
--  WoW Forever Raid Buffs: the retail section's two views over that client's
--  four buffs (RAID_BUFFS). A member has a buff while an aura with one of its
--  family's names is up (every rank, the group version, other casters'
--  versions). Under the game's aura restriction a buff is read only while none
--  of its ranks is secret (a secret aura would read absent while up), and
--  shows nothing otherwise rather than a false alarm. Absence only (no expiry
--  thresholds).
-------------------------------------------------------------------------------
-- Localized names of a family, cached per family (cold spell data stays uncached).
function EABR.FvNames(fam)
    local cache = EABR._fvNameCache
    if not cache then cache = {}; EABR._fvNameCache = cache end
    local names = cache[fam]
    if names then return names end
    names = {}
    for _, id in ipairs(fam.names) do
        local n = SpellName(id)
        if n then names[#names + 1] = n end
    end
    if names[1] then cache[fam] = names end
    return names
end

-- Whether a unit carries any rank of a family: true / false, or nil when the
-- answer cannot be read. rec (optional) collects the found aura's instance ID
-- for the group aura probe.
function EABR.FvUnitHas(u, fam, rec)
    local names = EABR.FvNames(fam)
    if not names[1] then return nil end
    for n = 1, #names do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, u, names[n], "HELPFUL")
        if not ok or isSecret(aura) then return nil end
        if aura then
            local iid = rec and aura.auraInstanceID
            if iid and not isSecret(iid) then rec[iid] = true end
            return true
        end
    end
    return false
end

-- The highest rank in a list (lowest first) the player knows, or nil.
function EABR.FvHighest(list)
    for i = #list, 1, -1 do
        if C_SpellBook.IsSpellKnown(list[i]) then return list[i] end
    end
end

-- Whether no rank in a list reads secret right now.
function EABR.FvRanksReadable(list)
    for i = 1, #list do
        if not EABR.IsRuntimeNonSecret(list[i]) then return false end
    end
    return true
end

-- Whether a family can be read now: always outside the aura restriction,
-- inside it only while none of its ranks is secret. The restricted answer is
-- kept for the frame (inputs: the family and the frame's time), since a burst
-- of unreadable group aura payloads asks it per event.
function EABR.FvReadable(fam, restricted)
    if not restricted then return true end
    local memo = EABR._fvReadMemo
    if not memo then memo = {}; EABR._fvReadMemo = memo end
    local now = GetTime()
    if memo.t ~= now then
        wipe(memo)
        memo.t = now
    end
    local v = memo[fam]
    if v == nil then
        v = EABR.FvRanksReadable(fam.single) and EABR.FvRanksReadable(fam.group)
        memo[fam] = v
    end
    return v
end

-- The group unit tokens, built once: party = the player and party1-4, raid =
-- raid1-40.
function EABR.FvTokens()
    local t = EABR._fvTokens
    if t then return t end
    t = { party = { "player" }, raid = {} }
    for i = 1, 4 do t.party[i + 1] = "party" .. i end
    for i = 1, 40 do t.raid[i] = "raid" .. i end
    EABR._fvTokens = t
    return t
end

-- In-range beneficiaries carrying a family vs all of them (the "12/15" badge),
-- plus the first one without it (the click's target). A member whose answer
-- cannot be read counts on neither side. The found aura instances
-- (EABR._fvInst, kept outside the watch so the pass that first builds it
-- records them too) feed the group aura probe (EABR.FvAuraRelevant).
function EABR.FvCoverage(fam, benefit)
    local inst = EABR._fvInst
    if not inst then inst = {}; EABR._fvInst = inst end
    local raid = IsInRaid()
    local tokens = EABR.FvTokens()
    local list = raid and tokens.raid or tokens.party
    local n = raid and GetNumGroupMembers() or (GetNumSubgroupMembers() + 1)
    local have, total, first = 0, 0, nil
    for i = 1, n do
        local u = list[i]
        if not u then break end
        local rec = inst[u]
        if rec then wipe(rec) end
        if _unitOk(u) and UnitIsPlayer(u) and _unitInRange(u) and EABR.UnitBenefits(u, benefit) then
            if not rec then rec = {}; inst[u] = rec end
            local has = EABR.FvUnitHas(u, fam, rec)
            if has ~= nil then
                total = total + 1
                if has then have = have + 1 elseif not first then first = u end
            end
        end
    end
    return have, total, first
end

-- The click's cast: the group version on the player while they know it and
-- could cast it now (its reagent in the bags; mana aside), else the highest
-- known rank on the member who lacks the buff (the player for a shout).
function EABR.FvPickCast(buff, unit)
    local fam = buff.fam
    local g = EABR.FvHighest(fam.group)
    if g then
        local usable, noMana = C_Spell.IsSpellUsable(g)
        if not isSecret(usable) and not isSecret(noMana) and (usable or noMana) then
            return g, "player"
        end
    end
    return EABR.FvHighest(fam.single), (not buff.selfCast and unit) or "player"
end

-- The collector. Provider: the player knows a rank (or the group version) of
-- their class's buff; with "Others are missing my buff" in a group it counts
-- the in-range members who benefit, otherwise the player alone. Receiver ("I
-- am missing others' buffs"): a buff of another class the player lacks while a
-- member of that class is in range (informational, no click). Out of combat
-- the pass also picks the provider's cast (EABR.SyncProviderCastSpell binds
-- it), and every pass syncs the group watch to what it read.
function EABR.CollectForeverRaidBuffs(missing, playerClass, inInstance)
    local rb = db.profile.raidBuffs
    local watch, roster = nil, false
    local castSpell, castUnit
    local lockdown = InCombatLockdown()
    if rb and EABR.SectionShows(rb.whereToShow, inInstance) then
        local sw = rb.showWhen
        local othersMissing = not sw or sw.othersMissing ~= false
        local iAmMissing = sw and sw.iAmMissing == true
        local grouped = IsInGroup()
        local groupClasses = iAmMissing and grouped and EABR.BuildGroupClassSet() or nil
        local restricted = EllesmereUI.AuraKit.AurasRestricted()
        for _, buff in ipairs(RAID_BUFFS) do
            if rb.enabled[buff.key] then
                local fam = buff.fam
                local iCast = buff.class == playerClass
                    and (EABR.FvHighest(fam.single) or EABR.FvHighest(fam.group)) ~= nil
                if iCast and othersMissing then watch = fam end
                if not iCast and iAmMissing then roster = true end
                local doReceiver = not iCast and groupClasses and groupClasses[buff.class]
                    and EABR.PlayerBenefitsFromBuff(buff)
                if (iCast or doReceiver) and EABR.FvReadable(fam, restricted) then
                    local isMissing, have, total, first
                    if iCast and othersMissing and grouped then
                        have, total, first = EABR.FvCoverage(fam, buff.benefit)
                        isMissing = total > 0 and have < total
                    else
                        isMissing = EABR.FvUnitHas("player", fam) == false
                    end
                    if iCast and not lockdown then
                        castSpell, castUnit = EABR.FvPickCast(buff, first)
                    end
                    if isMissing then
                        local e = AcquireEntry()
                        e.label = ShortLabel(SpellName(buff.castSpell) or buff.name)
                        e.cat = "raidbuff"; e.data = buff
                        e.dismissKey = buff.dismissKey
                        if total then
                            e.groupHave = have
                            e.groupTotal = total
                        end
                        if iCast then
                            -- The provider button casts it; in combat it keeps
                            -- the cast bound before the pull.
                            e.mode = "spell"
                            e.spellID = castSpell or EABR._providerCastSpell
                        else
                            e.mode = "texture"
                            e.spellID = buff.castSpell
                            e.texture = Tex(buff.castSpell)
                        end
                        missing[#missing+1] = e
                    end
                end
            end
        end
    end
    if not lockdown then EABR._fvCastSpell, EABR._fvCastUnit = castSpell, castUnit end
    EABR.FvSyncGroupWatch(watch, roster)
end

local function Refresh()
    SetCachedOutline(nil)
    EABR._nextDurationRefreshTime = nil
    if not db then return end
    -- Pooled reminder buttons are children of iconAnchor, built in OnEnable (PLAYER_LOGIN). File-scope events (SPELLS_CHANGED, PLAYER_TALENT_UPDATE,
    -- TRAIT_CONFIG_UPDATED, ...) can fire DURING loading before OnEnable runs; a reminder created then via GetOrCreateIcon gets a nil parent and renders oversized forever (scale 1.0, not UIParent scale -- pooled buttons are never re-parented). Wait for the anchor; OnEnable fires its own refresh.
    if not iconAnchor then return end
    -- WoW Forever: the returns below show nothing, so the Raid Buffs group
    -- watch stands down with them; the event that ends each state (panel
    -- close, vehicle exit, alive, rest ended) refreshes and re-arms it.
    if euiPanelOpen then
        HideCombatIcons(); HideAllIcons()
        if EABR.FOREVER then EABR.FvSyncGroupWatch(nil, false) end
        return
    end

    -- Hides all reminders while skyriding (mounted+flying) or in a vehicle; IsMounted/IsFlying/UnitInVehicle are combat-safe (no taint).
    if UnitInVehicle("player") or (IsMounted() and IsFlying()) then
        HideCombatIcons(); HideCursorIcons()
        if InCombat() then
            FadeOutSecureIcons()
        else
            HideAllIcons()
        end
        if EABR.FOREVER then EABR.FvSyncGroupWatch(nil, false) end
        return
    end

    -- Suppresses while dead or in a rested area (city/inn) -- rested areas
    -- always stay hidden, independent of every "Where to Show" setting.
    if UnitIsDeadOrGhost("player") then
        HideCombatIcons(); HideCursorIcons(); HideAllIcons()
        if EABR.FOREVER then EABR.FvSyncGroupWatch(nil, false) end
        return
    end
    if IsResting() then
        HideCombatIcons(); HideCursorIcons()
        if InCombat() then FadeOutSecureIcons() else HideAllIcons() end
        if EABR.FOREVER then EABR.FvSyncGroupWatch(nil, false) end
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

    -- WoW Forever: its Raid Buffs and the one Forever section stand in for the
    -- four collectors below (reminders off: the Raid Buffs group watch stands down).
    if EABR.FOREVER then
        if remindersOn then
            EABR.CollectForeverRaidBuffs(missing, playerClass, inInstance)
            EABR.CollectForever(missing, inInstance, inPvP, restricted)
        else
            EABR.FvSyncGroupWatch(nil, false)
        end
    end

    ---------------------------------------------------------------------------
    --  1) Raid Buffs (runs in and out of combat)
    ---------------------------------------------------------------------------
    if remindersOn and not EABR.FOREVER then
        CollectRaidBuffs(missing, playerClass, inInstance, inCombat)
    end

    ---------------------------------------------------------------------------
    --  2) Auras: OOC normally; in restricted contexts only reminders whose
    --  detection survives the aura lock (stances/forms + whitelisted IDs).
    ---------------------------------------------------------------------------
    if remindersOn and not EABR.FOREVER then
        CollectAuras(missing, playerClass, specID, inInstance, restricted)
    end

    ---------------------------------------------------------------------------
    --  3) Consumables: OOC (non-PvP) normally; in restricted contexts the
    --  trackable subset only. PvP stays fully suppressed.
    ---------------------------------------------------------------------------
    if remindersOn and not inPvP and not EABR.FOREVER then
        CollectConsumables(missing, playerClass, specID, inInstance, inKeystone, inCombat)
    end

    ---------------------------------------------------------------------------
    --  4) Pet Reminders (combat-safe: UnitExists/UnitIsDead unrestricted); suppressed for petless specs, Grimoire of Sacrifice, etc.
    ---------------------------------------------------------------------------
    if remindersOn and not EABR.FOREVER and PET_CLASSES[playerClass] then
        local co = db.profile.consumables
        if co and co.enabled and co.enabled.pet ~= false and EABR.SectionShows(co.specialsWhereToShow, inInstance) then
            local suppress = false
            local petIcon = 132161
            local petLabel = "Pet"
            local warlockEnforcedPets
            if playerClass == "HUNTER" then
                local spec = GetSpecialization and GetSpecialization()
                if spec then
                    local sid = GetSpecializationInfo(spec)
                    if sid == 254 and not Known(1223323) then suppress = true end
                end
            elseif playerClass == "WARLOCK" then
                petIcon = 136218
                if Known(108503) and PlayerHasAuraByID({196099}) then suppress = true end
                local allowed = co.wrongPetAllowed
                warlockEnforcedPets = {}
                if allowed then
                    for _, pet in ipairs(WARLOCK_PETS) do
                        if allowed[pet.key] and Known(pet.castSpell) then
                            warlockEnforcedPets[#warlockEnforcedPets+1] = pet
                        end
                    end
                end
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
                e.cat = "consumable"
                e.dismissKey = "consumable:pet"
                local n = warlockEnforcedPets and #warlockEnforcedPets or 0
                if n > 0 then
                    EABR.SetWarlockPetSpell(e, warlockEnforcedPets, petIcon)
                else
                    e.mode = "texture"
                    e.texture = petIcon
                    e.label = petLabel
                end
                missing[#missing+1] = e
            end
            if not suppress and playerClass == "WARLOCK"
               and co.enabled.wrong_pet ~= false
               and EABR.SectionShows(co.warlockWhereToShow, inInstance)
               and UnitExists("pet") and not UnitIsDead("pet") then
                local _, familyID = UnitCreatureFamily("pet")
                familyID = familyID and not (issecretvalue and issecretvalue(familyID)) and familyID or nil
                local isAllowed = false
                for _, pet in ipairs(warlockEnforcedPets) do
                    if familyID and pet.families[familyID] then isAllowed = true; break end
                end
                if #warlockEnforcedPets > 0 and not isAllowed then
                    local e = AcquireEntry()
                    EABR.SetWarlockPetSpell(e, warlockEnforcedPets, 136216, EllesmereUI.L("Wrong Demon"))
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
            local useCursor = CursorAttachActive(db.profile.display) and cursorAnchor
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
                            local p = db.profile.display
                            local baseScale = p.scale or 1.0
                            local sz = floor(ICON_SIZE * baseScale + 0.5)
                            ApplyGlow(f, p, sz)
                        end
                    end
                end
            end
            if providerEntry then
                EABR.SetProviderCastCombatVisible(true, providerEntry)
                local pBtn = EABR._providerCastBtn
                if pBtn then
                    local p = db.profile.display
                    local sz = pBtn:GetWidth() or ICON_SIZE
                    if pBtn._eabrGlowWrapper then pBtn._eabrGlowWrapper:Hide() end
                    ApplyGlow(pBtn, p, sz)
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
        -- provider button keeps sole ownership as before. Only on Cursor
        -- in Combat keeps everything at its normal spot out here.
        local useCursor = CursorAttachActive(db.profile.display) and cursorAnchor
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
                        local p = db.profile.display
                        local baseScale = p.scale or 1.0
                        local sz = floor(ICON_SIZE * baseScale + 0.5)
                        ApplyGlow(f, p, sz)
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
                local sz = pBtn:GetWidth() or ICON_SIZE
                if pBtn._eabrGlowWrapper then pBtn._eabrGlowWrapper:Hide() end
                ApplyGlow(pBtn, p, sz)
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

    if not EABR.FOREVER then UpdateDurationTicker() end  -- expiry thresholds are retail-only
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

-------------------------------------------------------------------------------
--  WoW Forever Raid Buffs group watch, synced by every collector pass to what
--  it read (fam = the provider's buff while its coverage counts the group,
--  roster = a receiver reminder is possible): GROUP_ROSTER_UPDATE while either
--  applies; while grouped also UNIT_IN_RANGE_UPDATE and UNIT_CONNECTION per
--  group token, plus UNIT_AURA for a provider, each aura event probing its own
--  added and removed auras before a refresh is asked (EABR.FvAuraRelevant).
--  Nothing is registered otherwise (Refresh also stands it down while it
--  shows nothing: the options panel open, a vehicle, dead, resting).
--  RegisterUnitEvent takes two units, so the tokens ride one frame per pair:
--  party1-4 in a party (the player's own auras come through the main frame),
--  raid1-40 in a raid.
-------------------------------------------------------------------------------
function EABR.FvSyncGroupWatch(fam, roster)
    local any = fam ~= nil or roster
    local W = EABR._fvWatch
    if not W then
        if not any then return end
        W = { ids = {}, frames = {} }
        -- With a refresh already queued there is nothing to probe.
        local function OnUnitEvent(_, event, unit, info)
            if refreshQueued then return end
            if event ~= "UNIT_AURA" or EABR.FvAuraRelevant(unit, info) then RequestRefresh() end
        end
        local tokens = EABR.FvTokens()
        for kind, from in pairs({ party = 2, raid = 1 }) do
            local list = tokens[kind]
            for i = from, #list, 2 do
                local f = CreateFrame("Frame")
                f.kind, f.u1, f.u2 = kind, list[i], list[i + 1]
                f:SetScript("OnEvent", OnUnitEvent)
                W.frames[#W.frames + 1] = f
            end
        end
        W.world = CreateFrame("Frame")
        W.world:SetScript("OnEvent", function() RequestRefresh() end)
        EABR._fvWatch = W
    end
    if W.fam ~= fam then
        W.fam = fam
        wipe(W.ids)
        if fam then
            for _, id in ipairs(fam.ids) do W.ids[id] = true end
        end
    end
    if W.any ~= any then
        W.any = any
        if any then
            W.world:RegisterEvent("GROUP_ROSTER_UPDATE")
        else
            W.world:UnregisterEvent("GROUP_ROSTER_UPDATE")
        end
    end
    local mode = any and IsInGroup() and (IsInRaid() and "raid" or "party") or nil
    local auraOn = mode ~= nil and fam ~= nil
    if W.mode ~= mode or W.auraOn ~= auraOn then
        W.mode, W.auraOn = mode, auraOn
        for _, f in ipairs(W.frames) do
            f:UnregisterAllEvents()
            if f.kind == mode then
                f:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", f.u1, f.u2)
                f:RegisterUnitEvent("UNIT_CONNECTION", f.u1, f.u2)
                if auraOn then f:RegisterUnitEvent("UNIT_AURA", f.u1, f.u2) end
            end
        end
        if not auraOn and EABR._fvInst then
            for _, rec in pairs(EABR._fvInst) do wipe(rec) end
        end
    end
end

-- One group aura event against the watched buff: an added aura of it, or the
-- removal of one the last pass found on that member, asks for a refresh; a
-- full update always does; a payload the restriction made unreadable does
-- while the buff itself stays readable.
function EABR.FvAuraRelevant(unit, info)
    local W = EABR._fvWatch
    local fam = W and W.fam
    if not fam then return false end
    if not info then return true end
    if isSecret(info) then return EABR.FvReadable(fam, true) end
    local full = info.isFullUpdate
    if isSecret(full) then return EABR.FvReadable(fam, true) end
    if full then return true end
    local added = info.addedAuras
    if added then
        if isSecret(added) then return EABR.FvReadable(fam, true) end
        for i = 1, #added do
            local aura = added[i]
            if isSecret(aura) then return EABR.FvReadable(fam, true) end
            local sid = aura.spellId
            if isSecret(sid) then return EABR.FvReadable(fam, true) end
            if sid and W.ids[sid] then return true end
        end
    end
    local removed, found = info.removedAuraInstanceIDs, EABR._fvInst and EABR._fvInst[unit]
    if removed and found and next(found) then
        if isSecret(removed) then return EABR.FvReadable(fam, true) end
        for i = 1, #removed do
            local iid = removed[i]
            if isSecret(iid) then return EABR.FvReadable(fam, true) end
            if found[iid] then return true end
        end
    end
    return false
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

-- Soulstone cooldown expiry: one refresh when the cooldown runs out while
-- nothing else fires. Re-armed (or cleared with nil) on every Soulstone
-- check, so a cooldown reset by a boss wipe leaves at most one stale, harmless
-- extra refresh behind. Exists only while a Warlock has the reminder on.
function EABR.ArmSoulstoneCooldownRefresh(remaining)
    if EABR._soulstoneCdTimer then
        EABR._soulstoneCdTimer:Cancel()
        EABR._soulstoneCdTimer = nil
    end
    if type(remaining) ~= "number" or remaining <= 0 then return end
    EABR._soulstoneCdTimer = C_Timer.NewTimer(remaining + 0.1, function()
        EABR._soulstoneCdTimer = nil
        RequestRefresh()
    end)
end

I.RequestRefresh = RequestRefresh
I.broken = false
