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
local InkyMapWatch = I.InkyMapWatch
local HideAllIcons, LayoutIcons, ShowIcon = I.HideAllIcons, I.LayoutIcons, I.ShowIcon
local SetCachedOutline, CursorAttachActive = I.SetCachedOutline, I.CursorAttachActive
local CachedGetItemCount, GetWeaponCategory = I.CachedGetItemCount, I.GetWeaponCategory

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
-- learned (LEARNED_SPELL_IN_SKILL_LINE sets _fvFamDirty), after any spellbook
-- change while the Action Picker listens (SPELLS_CHANGED: a respec can take a
-- spell away), when the picker is turned on or off, or when an ID joins the
-- list; the families then serve every refresh as they are. With the picker
-- on, a family's EABR._fvKnownFams entry is the list of its known ranks,
-- lowest first as the spellbook lists them (one list per name), else the last
-- rank found.
local function PickerEnabled()
    local fo = db.profile.forever
    return fo ~= nil and fo.pickerEnabled == true
end

function EABR.ForeverFamily(id)
    local fams = EABR._fvFams
    if not (fams and fams[id]) or EABR._fvFamDirty
        or EABR._fvRanksEnabled ~= PickerEnabled() then
        EABR.BuildForeverFamilies()
        fams = EABR._fvFams
    end
    return fams[id]
end

function EABR.BuildForeverFamilies()
    EABR._fvFamDirty = false
    local pickerEnabled = PickerEnabled()
    EABR._fvRanksEnabled = pickerEnabled
    local fams = EABR._fvFams
    if fams then wipe(fams) else fams = {}; EABR._fvFams = fams end
    -- The families with a rank in this character's spellbook (spell groups:
    -- EABR.CollectForeverGroups), from the same pass.
    local known = EABR._fvKnownFams
    if known then wipe(known) else known = {}; EABR._fvKnownFams = known end
    -- The rank each cast-by-name reminder resolves to is read again too.
    if EABR._fvTopRank then wipe(EABR._fvTopRank) end
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
                local cast = sid
                if pickerEnabled then
                    cast = known[into[1]] or {}
                    if not tContains(cast, sid) then cast[#cast + 1] = sid end
                end
                for _, list in ipairs(into) do
                    local listed = false
                    for k = 1, #list do
                        if list[k] == sid then listed = true; break end
                    end
                    if not listed then list[#list + 1] = sid end
                    known[list] = cast
                end
            end
        end
    end
end

function EABR.ForeverGroupCastSpell(group, spellID, family)
    local ranks
    if group.ranksBySpell then
        ranks = group.ranksBySpell[spellID]
    else
        family = family or (type(spellID) == "number" and SpellName(spellID) and EABR.ForeverFamily(spellID))
        ranks = family and EABR._fvKnownFams[family]
    end
    if type(ranks) ~= "table" then return end
    local settings = group.settings or group
    local pinned = settings.castRanks and settings.castRanks[spellID]
    if pinned then
        for i, id in ipairs(ranks) do
            if id == pinned then
                if i == #ranks then break end
                local _, rank = EABR.ForeverPickerSpellData(id, true)
                if rank then return id, ranks, i end
                break
            end
        end
    end
    return ranks[#ranks], ranks, #ranks
end

local function SetForeverPickerSpell(entry, group, id, ranks)
    local macro, rank = EABR.ForeverPickerSpellData(id, #ranks > 1)
    if not macro then return end
    entry.mode = "macro"
    entry.macro = macro
    entry.spellID = id
    entry.foreverGroup = group
    entry.spellRank = rank
end

-- The click of a WoW Forever reminder that casts its spell by name (a spell
-- group, or a custom spell the character knows): /cast [@player] <name>, which
-- casts the highest rank in the spellbook, and that rank for the tooltip, read
-- by name as /cast reads it (the rank lists are not in rank order: a stored ID
-- leads its list). Both are kept per name: the macro for the session, the rank
-- until the families are rebuilt (BuildForeverFamilies wipes EABR._fvTopRank).
-- The section never shows in combat, so the macro can always be set.
local castMacros = {}

local function CastByName(entry, castName, fallbackID)
    local macro = castMacros[castName]
    if not macro then
        macro = "/cast [@player] " .. castName
        castMacros[castName] = macro
    end
    local tops = EABR._fvTopRank
    if not tops then tops = {}; EABR._fvTopRank = tops end
    local top = tops[castName]
    if top == nil then
        -- By name the client answers the highest rank in the spellbook.
        local info = C_Spell.GetSpellInfo(castName)
        if info then
            top = C_SpellBook.IsSpellKnown(info.spellID) and info.spellID or false
            tops[castName] = top
        end
    end
    entry.mode = "macro"; entry.macro = macro
    entry.spellID = top or fallbackID
end

-- WoW Forever spell groups: one reminder per group while no aura from its
-- spells (or their ranks, EABR.ForeverFamily) is active, out of combat only.
-- While the client hides aura data from addons (AuraKit.AurasRestricted), a
-- group counts as having no active aura only if none of its spells is flagged
-- secret, so a hidden aura is not read as absent. A group shows only for a
-- character that knows one of its spells (a rank in the spellbook): groups are
-- profile settings, so one made on another class shows nothing here. The icon
-- uses the selected spell or the first known member. Groups covered by
-- enabled class buff reminders stand down.
local function GroupCovered(spellIDs, ids, names)
    local any = false
    for _, spellID in ipairs(spellIDs) do
        if type(spellID) == "number" then
            local name = SpellName(spellID)
            if not (ids[spellID] or (name and names[name])) then return false end
            any = true
        end
    end
    return any
end

function EABR.CollectForeverGroups(missing, groups, coveredIDs, coveredNames)
    local dismissKeys = EABR._fvGroupKeys
    if not dismissKeys then
        dismissKeys = setmetatable({}, { __mode = "k" })
        EABR._fvGroupKeys = dismissKeys
        EABR._fvGroupN = 0
    end
    local aurasRestricted = EllesmereUI.AuraKit and EllesmereUI.AuraKit.AurasRestricted()
    local pickerEnabled = PickerEnabled()
    for _, group in ipairs(groups) do
        local spellIDs = type(group) == "table" and group.ids
        if type(spellIDs) == "table" and not (coveredIDs and GroupCovered(spellIDs, coveredIDs, coveredNames)) then
            local iconSpellID, castSpellID, hasActiveAura
            local firstRanks, castRanks, hasChoices
            local allAurasReadable = true
            for _, spellID in ipairs(spellIDs) do
                local rankSpellIDs = type(spellID) == "number" and SpellName(spellID)
                    and EABR.ForeverFamily(spellID)
                if rankSpellIDs then
                    if pickerEnabled then
                        local knownSpellID, ranks = EABR.ForeverGroupCastSpell(group, spellID, rankSpellIDs)
                        if knownSpellID then
                            firstRanks = firstRanks or ranks
                            if ranks ~= firstRanks then hasChoices = true end
                            if not castSpellID or spellID == group.castSpellID then
                                iconSpellID, castSpellID, castRanks = knownSpellID, knownSpellID, ranks
                            end
                        end
                    elseif not iconSpellID and EABR._fvKnownFams[rankSpellIDs] then
                        iconSpellID = spellID
                    end
                    hasActiveAura = PlayerHasAuraByID(rankSpellIDs)
                    if hasActiveAura then break end
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
                local castName = SpellName(iconSpellID)
                entry.texture = Tex(iconSpellID)
                if castSpellID then
                    SetForeverPickerSpell(entry, hasChoices and group or nil, castSpellID, castRanks)
                else
                    CastByName(entry, castName, iconSpellID)
                end
                entry.label = type(group.name) == "string" and group.name
                    or ShortLabel(castName)
                entry.cat = "forever"; entry.dismissKey = dismissKey
                missing[#missing+1] = entry
            end
        end
    end
end

-- One pass over the minimap trackers, for those that are no auras there:
-- whether Find Treasure is up (it stacks with any other tracking) and whether
-- another spell tracking is (a class one: the gathering ones are already ruled
-- out by their aura when this runs, and those share one slot with it). The
-- answer is kept until the tracking can have changed (EABR._fvTrackDirty):
-- MINIMAP_UPDATE_TRACKING, a learned spell, a loading screen, and every new
-- registration of that event, since nothing is heard while it is off.
function EABR.FvTrackingState()
    if EABR._fvTrackDirty ~= false then
        EABR._fvTrackDirty = false
        local treasure, class = false, false
        for i = 1, C_Minimap.GetNumTrackingTypes() do
            local info = C_Minimap.GetTrackingInfo(i)
            if info and info.active and info.type == "spell" then
                if info.spellID == EABR.FIND_TREASURE then treasure = true else class = true end
            end
        end
        EABR._fvTreasureUp, EABR._fvClassUp = treasure, class
    end
    return EABR._fvTreasureUp, EABR._fvClassUp
end

-- A cast-on-click reminder for a WoW Forever spell (gathering, Find Treasure,
-- the mage armors, class buffs), labelled with the spell's name unless a
-- label is given.
function EABR.FvSpellEntry(missing, id, dismissKey, label)
    local e = AcquireEntry()
    e.mode = "spell"; e.spellID = id
    e.label = label or ShortLabel(SpellName(id) or tostring(id))
    e.cat = "forever"; e.dismissKey = dismissKey
    missing[#missing+1] = e
    return e
end

-- Whether the player's own aura of a spell is up: true, false (absent or
-- another caster's), or nil when a secret or unreadable answer cannot tell.
local function OwnAuraState(id)
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
    if not ok or isSecret(aura) then return nil end
    if aura == nil then return false end
    local okMine, mine = pcall(EABR._StrictAuraFromMe, aura)
    if not okMine or isSecret(mine) then return nil end
    return mine
end

-- Whether any rank in a list is up (ids: the one-slot lookup): true, false,
-- or nil while an own-only read cannot tell.
local function RanksState(ranks, ids, own)
    local unknown
    for j = 1, #ranks do
        if own then
            local state = OwnAuraState(ranks[j])
            if state then return true end
            if state == nil then unknown = true end
        else
            ids[1] = ranks[j]
            if PlayerHasAuraByID(ids) then return true end
        end
    end
    if unknown then return nil end
    return false
end

local function LineState(lines, i, ids, also, own)
    local state = RanksState(lines[i], ids, own)
    if state then return true end
    local extra = also and also[i]
    if extra then
        local extraState = RanksState(extra, ids, own)
        if extraState then return true end
        if extraState == nil then state = nil end
    end
    return state
end

local function LineReadable(lines, i, also)
    local extra = also and also[i]
    return EABR.FvRanksReadable(lines[i]) and not (extra and not EABR.FvRanksReadable(extra))
end

-- One reminder while no rank of any line is up (the mage armors, a class
-- buff). Returns the index of the line up, which the caller records for this
-- character (a profile is shared by every character on it), or false while
-- the reminder is held back without a line to record. The icon and the click
-- then follow the line last seen up, with no event of their own (the player's
-- UNIT_AURA already drives the refresh). Nothing up casts the strongest rank
-- known of that line, else the strongest line known. The recorded line (last)
-- is read first: the line up is nearly always it. own: only the player's own
-- aura is found and recorded; anyCounts: another caster's still holds the
-- reminder back, unrecorded.
local function CollectLines(missing, auraLock, ids, lines, last, dismissKey, label, also, own, anyCounts)
    local first = lines[last] and last
    local unknown = false
    if first then
        local state = LineState(lines, first, ids, also, own)
        if state then return first end
        if state == nil then unknown = true end
    end
    local readable = not (auraLock and first and not LineReadable(lines, first, also))
    for i = 1, #lines do
        if i ~= first then
            local state = LineState(lines, i, ids, also, own)
            if state then return i end
            if state == nil then unknown = true end
            if auraLock and not LineReadable(lines, i, also) then readable = false end
        end
    end
    -- Under the aura lock an unreadable rank would read absent: say nothing.
    if unknown or not readable then return false end
    if anyCounts then
        for i = 1, #lines do
            if LineState(lines, i, ids, also, false) then return false end
        end
    end
    local id = first and EABR.FvHighest(lines[first])
    if not id then
        for i = #lines, 1, -1 do
            id = EABR.FvHighest(lines[i])
            if id then break end
        end
    end
    if id then return nil, EABR.FvSpellEntry(missing, id, dismissKey, label) end
end

local function CharStore(field)
    local store = EllesmereUIDB[field]
    local keys = EABR._fvCharKeys
    if not keys then keys = {}; EABR._fvCharKeys = keys end
    local key = keys[field]
    if not key then
        key = EllesmereUI.CharKey("-", store)
        keys[field] = key
    end
    return store, key
end

-- Mage armors (WoW Forever): one reminder while no rank of Frost Armor, Ice
-- Armor or Mage Armor is up; the line up is recorded in
-- EllesmereUIDB.mageArmorByChar by EllesmereUI.CharKey.
function EABR.CollectMageArmor(missing, auraLock, ids)
    local store, key = CharStore("mageArmorByChar")
    local last = store and key and store[key]
    local up = CollectLines(missing, auraLock, ids, EABR.MAGE_ARMORS, last,
        "forever:magearmor", EllesmereUI.L("Armor"))
    if up and up ~= last and key then
        if not store then store = {}; EllesmereUIDB.mageArmorByChar = store end
        store[key] = up
    end
end

-- Whether a class buff is ticked: the user's pick, else its default (each
-- class's always-on buffs ticked; Thorns, Righteous Fury and Shadowform not).
local function ClassBuffOn(buff, picks)
    local v = picks and picks[buff.key]
    if v == nil then return buff.on == true end
    return v == true
end
EABR.FvClassBuffOn = ClassBuffOn

-- The spells the ticked class buffs track, by ID and by name (every rank, the
-- Greater Blessings and the up-only extras included). A custom spell, or a
-- spell group made only of them, stands down while Class Buffs covers it and
-- is back once that buff is unticked: a reminder the user made before Class
-- Buffs existed is never shown twice and never deleted. Rebuilt only when the
-- class or the ticked set changes; nil while none is ticked.
local coveredIDs, coveredNames, coveredMask, coveredClass = {}, {}, nil, nil
local function CoverLines(lines)
    if not lines then return end
    for i = 1, #lines do
        local ranks = lines[i]
        for j = 1, #ranks do
            local id = ranks[j]
            coveredIDs[id] = true
            local name = SpellName(id)
            if name then coveredNames[name] = true end
        end
    end
end
function EABR.FvClassTracked(fo, class)
    local list = EABR.FvClassBuffs()[class]
    if not list then return nil end
    local picks = fo.classBuffPicks
    local mask, bit = 0, 1
    for i = 1, #list do
        if ClassBuffOn(list[i], picks) then mask = mask + bit end
        bit = bit * 2
    end
    if mask == 0 then return nil end
    if mask ~= coveredMask or class ~= coveredClass then
        wipe(coveredIDs)
        wipe(coveredNames)
        for i = 1, #list do
            local buff = list[i]
            if ClassBuffOn(buff, picks) then
                CoverLines(buff.lines)
                CoverLines(buff.also)
            end
        end
        coveredMask, coveredClass = mask, class
    end
    return coveredIDs, coveredNames
end

local function BuildClassBuffPicker(buff, actions, settings)
    local group = { ids = {}, ranksBySpell = {}, actions = actions, key = buff.key, settings = settings }
    for _, line in ipairs(buff.lines) do
        local ranks = {}
        for _, id in ipairs(line) do
            if C_SpellBook.IsSpellKnown(id) and SpellName(id) then ranks[#ranks + 1] = id end
        end
        if ranks[1] then
            group.ids[#group.ids + 1] = line[1]
            group.ranksBySpell[line[1]] = ranks
        end
    end
    return group
end

local function ClassPickerSpell(group, defaultID)
    local settings = group.settings
    if settings then
        local id, ranks = EABR.ForeverGroupCastSpell(group, settings.castSpellID)
        if id then return id, ranks end
    end
    for _, spellID in ipairs(group.ids) do
        if tContains(group.ranksBySpell[spellID], defaultID) then
            return EABR.ForeverGroupCastSpell(group, spellID)
        end
    end
end

local function ApplyClassBuffPicker(entry, fo, buff)
    local actions = fo.classBuffActions
    local settings = actions[buff.key]
    local cache = EABR._fvClassPickerGroups
    if not cache then cache = {}; EABR._fvClassPickerGroups = cache end
    local group = cache[buff.key]
    local id, ranks
    if group and group.actions == actions and group.settings == settings then
        id, ranks = ClassPickerSpell(group, entry.spellID)
    end
    -- Talent changes can invalidate the cached choice without a spell-learned event.
    if not id or not C_SpellBook.IsSpellKnown(id) then
        group = BuildClassBuffPicker(buff, actions, settings)
        cache[buff.key] = group
        id, ranks = ClassPickerSpell(group, entry.spellID)
    end
    if id then SetForeverPickerSpell(entry, group.ids[2] and group or nil, id, ranks) end
end

function EABR.CollectClassBuffs(missing, fo, auraLock, ids, class)
    local list = EABR.FvClassBuffs()[class]
    if not list then return end
    local picks = fo.classBuffPicks
    local store, key = CharStore("classBuffByChar")
    local rec = store and key and store[key]
    for i = 1, #list do
        local buff = list[i]
        if ClassBuffOn(buff, picks) then
            local dk = buff.dismissKey
            if not dk then dk = "forever:class_" .. buff.key; buff.dismissKey = dk end
            local last = rec and rec[buff.key]
            local up, entry = CollectLines(missing, auraLock, ids, buff.lines, last, dk,
                buff.label, buff.also,
                buff.own or buff.ownMemory, buff.ownMemory)
            if entry and PickerEnabled() then ApplyClassBuffPicker(entry, fo, buff) end
            if up and up ~= last and key and buff.lines[2] then
                if not store then store = {}; EllesmereUIDB.classBuffByChar = store end
                rec = store[key]
                if not rec then rec = {}; store[key] = rec end
                rec[buff.key] = up
            end
        end
    end
end

local FV_HANDS = {
    { slot = 16, ws = "MainHand", imbue = "mhImbue", temp = "mhTemp", label = "Main Hand",
      imbueKey = "forever:weapon_mh_imbue", tempKey = "forever:weapon_mh_temp", macros = {} },
    { slot = 17, ws = "OffHand", imbue = "ohImbue", temp = "ohTemp", label = "Off Hand",
      imbueKey = "forever:weapon_oh_imbue", tempKey = "forever:weapon_oh_temp", macros = {} },
}
local FISHING_POLE = 20

local function FvWeaponCategory(slot)
    local cat = GetWeaponCategory(slot)
    if not cat or cat == "RANGED" then return nil end
    local _, _, _, _, _, _, sub = C_Item.GetItemInfoInstant(GetInventoryItemID("player", slot))
    if sub == FISHING_POLE then return nil end
    return cat
end

local function FvWeaponEnchants(ws)
    local list = C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot[ws])
    if isSecret(list) then return false end
    local imbueLeft, tempLeft
    if type(list) == "table" then
        local IMBUE, TEMPORARY = Enum.ItemEnchantType.Imbue, Enum.ItemEnchantType.Temporary
        for i = 1, #list do
            local e = list[i]
            local has, kind, left = e.hasEnchant, e.enchantType, e.timeLeft
            if isSecret(has) or isSecret(kind) or isSecret(left) then return false end
            if has and left and left > 0 then
                if kind == IMBUE then imbueLeft = left / 1000
                elseif kind == TEMPORARY then tempLeft = left / 1000 end
            end
        end
    end
    return true, imbueLeft, tempLeft
end

local function FvAvailable(buff, low)
    if buff.spells then return EABR.FvHighest(buff.spells), nil end
    local items = buff.items
    local first, last, step = #items, 1, -1
    if low then first, last, step = 1, #items, 1 end
    for i = first, last, step do
        if CachedGetItemCount(items[i]) > 0 then return nil, items[i] end
    end
end

local function FvPick(choice, isImbue, class, wcat, low)
    if choice == "off" then return nil end
    local auto = choice == nil or choice == "auto"
    local list = EABR.FV_WEAPON_BUFFS
    for i = 1, #list do
        local buff = list[i]
        if (auto or choice == buff.key) and (buff.imbue == true) == isImbue
           and (not buff.class or buff.class == class)
           and (not buff.weapon or buff.weapon == wcat) then
            local spellID, itemID = FvAvailable(buff, low)
            if spellID or itemID or not auto then return buff, spellID, itemID end
        end
    end
end

local function FvNeeds(left, warnSec)
    if not left then return true end
    if warnSec and left < warnSec then return true end
    local at = GetTime() + left - (warnSec or 0)
    local nextAt = EABR._nextDurationRefreshTime
    if not nextAt or at < nextAt then EABR._nextDurationRefreshTime = at end
    return false
end

local function FvWeaponEntry(missing, hand, label, dismissKey, buff, spellID, itemID, hideNoItem, left)
    if buff.spells and not spellID then return end
    if buff.items and not itemID and hideNoItem then return end
    local e = AcquireEntry()
    if spellID then
        e.mode = "spell"; e.spellID = spellID
    else
        local shown = itemID or buff.items[#buff.items]
        e.texture = C_Item.GetItemIconByID(shown) or 134400
        e.tooltipItem = shown
        e.bagCount = itemID and CachedGetItemCount(itemID) or 0
        e.desaturated = not itemID
        if itemID then
            local macro = hand.macros[itemID]
            if not macro then
                macro = "/use item:" .. itemID .. "\n/use " .. hand.slot
                hand.macros[itemID] = macro
            end
            e.mode = "macro"; e.macro = macro
        else
            e.mode = "texture"
        end
    end
    if left then e.expireAt = GetTime() + left; e.expireTotal = left end
    e.label = label
    e.cat = "forever"; e.dismissKey = dismissKey
    missing[#missing+1] = e
end

function EABR.CollectForeverWeapons(missing, fo, class)
    if not (C_Item.GetWeaponEnchantInfo and Enum.WeaponSlot and Enum.ItemEnchantType) then return end
    local hands = fo.weaponHands and fo.weaponHands[class]
    local low, hideNoItem = fo.weaponLowRank == true, fo.weaponHideNoItem ~= false
    local showBelow = fo.weaponShowBelow or 1
    local warnSec = showBelow > 0 and showBelow * 60 or nil
    local mhFull, ohFull = EllesmereUI.L(FV_HANDS[1].label), EllesmereUI.L(FV_HANDS[2].label)
    local mhLabel, ohLabel = ShortLabel(mhFull), ShortLabel(ohFull)
    if mhLabel == ohLabel then mhLabel, ohLabel = mhFull, ohFull end
    for i = 1, #FV_HANDS do
        local hand = FV_HANDS[i]
        local wcat = FvWeaponCategory(hand.slot)
        local ok, imbueLeft, tempLeft
        if wcat then ok, imbueLeft, tempLeft = FvWeaponEnchants(hand.ws) end
        if ok then
            local label = i == 1 and mhLabel or ohLabel
            local buff, spellID, itemID = FvPick(hands and hands[hand.imbue], true, class, wcat, low)
            if buff and FvNeeds(imbueLeft, warnSec) then
                FvWeaponEntry(missing, hand, label, hand.imbueKey, buff, spellID, itemID, hideNoItem, imbueLeft)
            end
            buff, spellID, itemID = FvPick(hands and hands[hand.temp], false, class, wcat, low)
            if buff and FvNeeds(tempLeft, warnSec) then
                FvWeaponEntry(missing, hand, label, hand.tempKey, buff, spellID, itemID, hideNoItem, tempLeft)
            end
        end
    end
end

local function FvAtMaxLevel()
    local level = UnitLevel("player") or 0
    if IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() then return true end
    local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
        or (GetMaxPlayerLevel and GetMaxPlayerLevel())
    return (maxLevel and level >= maxLevel) or false
end

function EABR.FvSleepingBagOwned()
    if EABR._fvMaxLevel then return false end
    if FvAtMaxLevel() then EABR._fvMaxLevel = true; return false end
    local owned = EABR._fvSleepBag
    if owned == nil then
        owned = (C_Item.GetItemCount(EABR.SLEEPING_BAG_ITEM) or 0) > 0
        EABR._fvSleepBag = owned
    end
    return owned
end

-- WoW Forever collector: the Camp Benefits campfire buff, the Sleeping Bag's
-- Well-Rested buff (missing or under its full stacks, while a Cozy Sleeping Bag
-- is in the bags below max level: EABR.FvSleepingBagOwned), Well Fed (any food
-- buff: the shared Well Fed name, or one of EABR.FOOD_BUFFS), the gathering
-- and Find Treasure trackers, a Mage's armors (EABR.CollectMageArmor), the
-- class buffs (EABR.CollectClassBuffs), the weapon buffs
-- (EABR.CollectForeverWeapons), the user's spell groups
-- (EABR.CollectForeverGroups) and custom spell IDs (each for the classes ticked
-- on it), those a ticked class buff covers standing down outside PvP. All are
-- absence only but
-- the weapon buffs, which also show their Show Below minutes before running
-- out (the one-shot duration refresh). A custom ID counts as up while any
-- spell of its rank family is (EABR.ForeverFamily). Entries are display-only
-- textures carrying the spell for the tooltip, except the Sleeping Bag, the two
-- trackers, the mage armors, the class buffs, the weapon buffs, the spell
-- groups and the custom spells the character knows, whose click casts the spell
-- or uses the item; presence goes through PlayerHasAuraByID. The section shows
-- nothing in combat (its Where to Show offers no In Combat entry: always
-- unchecked), and Camp Benefits, the Sleeping Bag, Well Fed, the mage armors,
-- the class buffs and the trackers nothing in PvP either. The one-slot id
-- table, the cached families, the kept minimap answer and the dismiss-key memo
-- keep the pass allocation-free; the weapon pass reads the game's enchant
-- lists, a table per weapon.
function EABR.CollectForever(missing, inInstance, inPvP)
    local fo = db.profile.forever
    local shows = fo and not InCombat() and EABR.SectionShows(fo.whereToShow, inInstance)
    -- Class trackers and Find Treasure are read from the minimap, whose event
    -- is listened to only while a reminder that reads it can show.
    EABR.FvSyncTrackingEvent(shows and not inPvP
        and ((fo.gather == true and fo.gatherClassTrack ~= false) or fo.treasure == true) or false)
    EABR.FvSyncWeaponEvents(shows and fo.weapon == true or false)
    local wantBag = shows and fo.sleepingBag == true and not inPvP
    local sleepBag = wantBag and EABR.FvSleepingBagOwned()
    -- No bag yet below max level: a light watcher hears one arrive, unless
    -- Weapon Buffs' bag listener (below) already hears every bag change.
    EABR.FvSyncSleepBagWatch(wantBag and not sleepBag and not EABR._fvMaxLevel
        and fo.weapon ~= true or false)
    EABR.FvSyncBagEvent(shows and (fo.weapon == true or sleepBag) or false)
    local watchPickerSpells = shows and PickerEnabled() or false
    if watchPickerSpells ~= (EABR._fvPickerSpellEvents or false) then
        EABR.FvSyncPickerSpellEvents(watchPickerSpells)
    end
    if not shows then return end
    local open = not inPvP
    -- Under the aura lock a secret aura reads absent, so an aura reminder
    -- shows only while none of its spells is secret.
    local auraLock = EllesmereUI.AuraKit.AurasRestricted()
    local ids = EABR._foreverIDs
    if not ids then ids = {}; EABR._foreverIDs = ids end
    if fo.camp ~= false and open then
        ids[1] = EABR.CAMP_BENEFITS
        if not PlayerHasAuraByID(ids) and not (auraLock and not EABR.FvRanksReadable(ids)) then
            local e = AcquireEntry()
            e.mode = "texture"; e.spellID = EABR.CAMP_BENEFITS
            e.texture = Tex(EABR.CAMP_BENEFITS)
            e.label = EllesmereUI.L("Camp")
            e.cat = "forever"; e.dismissKey = "forever:camp"
            missing[#missing+1] = e
        end
    end
    local sleepIDs = EABR._fvSleepIDs
    if not sleepIDs then sleepIDs = { EABR.SLEEPING_BAG_BUFF }; EABR._fvSleepIDs = sleepIDs end
    if sleepBag and not (auraLock and not EABR.FvRanksReadable(sleepIDs)) then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, EABR.SLEEPING_BAG_BUFF)
        local stacks = ok and not isSecret(aura) and (aura and aura.applications or 0)
        if stacks and not isSecret(stacks) and stacks < EABR.SLEEPING_BAG_STACKS then
            local item = EABR.SLEEPING_BAG_ITEM
            local e = AcquireEntry()
            e.mode = "item"; e.itemID = item
            e.texture = C_Item.GetItemIconByID(item) or Tex(EABR.SLEEPING_BAG_BUFF)
            e.label = EllesmereUI.L("Sleeping")
            e.cat = "forever"; e.dismissKey = "forever:sleepingbag"
            missing[#missing+1] = e
        end
    end
    -- Gathering tracking: shown while no tracker is up and the player knows
    -- one; the button casts the first one known. The aura read goes first, so
    -- the common case (a tracker up) skips the rest; class trackers are no
    -- auras there, so the minimap is asked only once a tracker is known.
    local scanned, treasureUp, classUp
    local list = EABR.GATHER_TRACKING
    if fo.gather and open and not PlayerHasAuraByID(list)
       and not (auraLock and not EABR.FvRanksReadable(list)) then
        local id
        for i = 1, #list do
            if Known(list[i]) then id = list[i] break end
        end
        if id then
            if fo.gatherClassTrack ~= false then
                scanned = true
                treasureUp, classUp = EABR.FvTrackingState()
            end
            if not classUp then EABR.FvSpellEntry(missing, id, "forever:gather") end
        end
    end
    -- Find Treasure (Dwarf racial): no aura there, so read from the same
    -- minimap pass when the gathering check already ran it.
    local tid = EABR.FIND_TREASURE
    if fo.treasure and open and Known(tid) then
        if not scanned then treasureUp = EABR.FvTrackingState() end
        if not treasureUp then EABR.FvSpellEntry(missing, tid, "forever:treasure") end
    end
    if fo.wellFed and open then
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
    if fo.mageArmor and open and GetPlayerClass() == "MAGE" then
        EABR.CollectMageArmor(missing, auraLock, ids)
    end
    -- The ticked class buffs, outside PvP; the custom spells and spell groups
    -- they cover stand down there (EABR.FvClassTracked).
    local coveredIDs, coveredNames
    if open then
        coveredIDs, coveredNames = EABR.FvClassTracked(fo, GetPlayerClass())
        if coveredIDs then EABR.CollectClassBuffs(missing, fo, auraLock, ids, GetPlayerClass()) end
    end
    if fo.weapon == true then
        EABR.CollectForeverWeapons(missing, fo, GetPlayerClass())
    end
    local groups = fo.customGroups
    if groups and groups[1] then
        EABR.CollectForeverGroups(missing, groups, coveredIDs, coveredNames)
    end
    local custom = fo.customIDs
    if not custom then return end
    local keys = EABR._foreverKeys
    if not keys then keys = {}; EABR._foreverKeys = keys end
    -- A custom spell reminds only the classes ticked on its options slot
    -- (forever.customClasses[id][CLASS] = false unticks one; unset: every class).
    local classOff, class = fo.customClasses, GetPlayerClass()
    for i = 1, #custom do
        local id = custom[i]
        local off = classOff and classOff[id]
        if not (off and off[class] == false) then
            local name = SpellName(id)
            if not (coveredIDs and (coveredIDs[id] or (name and coveredNames[name]))) then
                local fam = EABR.ForeverFamily(id)
                if not PlayerHasAuraByID(fam) and not (auraLock and fam and not EABR.FvRanksReadable(fam)) then
                    local dk = keys[id]
                    if not dk then dk = "forever:" .. id; keys[id] = dk end
                    local e = AcquireEntry()
                    -- A spell the character knows (a rank in the spellbook)
                    -- casts on click; any other (a buff someone else casts) is
                    -- only shown.
                    if name and fam and EABR._fvKnownFams[fam] then
                        CastByName(e, name, id)
                    else
                        e.mode = "texture"; e.spellID = id
                    end
                    e.texture = Tex(id)
                    e.label = ShortLabel(name or tostring(id))
                    e.cat = "forever"; e.dismissKey = dk
                    missing[#missing+1] = e
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  WoW Forever Raid Buffs: the retail section's two views over that client's
--  buffs (RAID_BUFFS). A member has a buff while an aura with one of its
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
-- records them too) feed the group aura probe (EABR.FvAuraRelevant); keep
-- adds them to the ones an earlier call of the same pass found (a class that
-- provides two buffs).
function EABR.FvCoverage(fam, benefit, keep)
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
        if rec and not keep then wipe(rec) end
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
-- member of that class is in range (informational, no click; never a talent
-- buff). Out of combat the pass also picks the provider's cast
-- (EABR.SyncProviderCastSpell binds it), and every pass syncs the group watch
-- to what it read. One button casts the provider's buffs, so a class that
-- provides two (a priest with Divine Spirit) shows one provider reminder at a
-- time: the first of its buffs in list order that is missing and not
-- dismissed, with the button bound to its cast; with none showing, the button
-- stays bound to the first buff it provides. Under lockdown the binding
-- cannot change, so only the buff the button casts shows there; another waits
-- for the end of combat.
function EABR.CollectForeverRaidBuffs(missing, playerClass, inInstance)
    local rb = db.profile.raidBuffs
    local watch = EABR._fvWatchFams
    if watch then wipe(watch) else watch = {}; EABR._fvWatchFams = watch end
    local roster = false
    local castSpell, castUnit
    local provided, covered, idle, idleFirst = false, false, nil, nil
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
                if iCast and othersMissing then watch[#watch + 1] = fam end
                if not iCast and iAmMissing and not buff.talent then roster = true end
                local doReceiver = not iCast and not buff.talent and groupClasses and groupClasses[buff.class]
                    and EABR.PlayerBenefitsFromBuff(buff)
                if (iCast or doReceiver) and EABR.FvReadable(fam, restricted) then
                    local isMissing, have, total, first
                    if iCast and othersMissing and grouped then
                        have, total, first = EABR.FvCoverage(fam, buff.benefit, covered)
                        covered = true
                        isMissing = total > 0 and have < total
                    else
                        isMissing = EABR.FvUnitHas("player", fam) == false
                    end
                    if iCast then
                        if not idle then idle, idleFirst = buff, first end
                        -- Under lockdown: the spell the button casts, a rank or
                        -- group version of the one buff that may show.
                        local bound = lockdown and EABR._providerCastSpell
                        isMissing = isMissing and not provided and not _dismissedUntilLoad[buff.dismissKey]
                            and not (bound and not (tContains(fam.single, bound) or tContains(fam.group, bound)))
                        if isMissing then
                            provided = true
                            if not lockdown then
                                castSpell, castUnit = EABR.FvPickCast(buff, first)
                            end
                        end
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
    if not lockdown then
        if not provided and idle then castSpell, castUnit = EABR.FvPickCast(idle, idleFirst) end
        EABR._fvCastSpell, EABR._fvCastUnit = castSpell, castUnit
    end
    EABR.FvSyncGroupWatch(watch, roster)
end

-- WoW Forever: what a pass that shows nothing stands down (the Raid Buffs group
-- watch and the minimap, weapon and bag events); the next pass that can show
-- re-arms them.
function EABR.FvStandDown()
    EABR.FvSyncGroupWatch(nil, false)
    EABR.FvSyncTrackingEvent(false)
    EABR.FvSyncWeaponEvents(false)
    EABR.FvSyncBagEvent(false)
    -- Bag changes go unheard while the section stands down (resting in a city,
    -- for one): the Sleeping Bag is counted again when it is back.
    EABR.FvSyncSleepBagWatch(false)
    EABR._fvSleepBag = nil
    if EABR._fvPickerSpellEvents then EABR.FvSyncPickerSpellEvents(false) end
    if EABR.ValidateOpenPicker then EABR.ValidateOpenPicker() end
    if EABR._durationTimer then
        EABR._durationTimer:Cancel()
        EABR._durationTimer = nil
    end
end

local function Refresh()
    SetCachedOutline(nil)
    EABR._nextDurationRefreshTime = nil
    if not db then return end
    -- Pooled reminder buttons are children of iconAnchor, built in OnEnable (PLAYER_LOGIN). File-scope events (SPELLS_CHANGED, PLAYER_TALENT_UPDATE,
    -- TRAIT_CONFIG_UPDATED, ...) can fire DURING loading before OnEnable runs; a reminder created then via GetOrCreateIcon gets a nil parent and renders oversized forever (scale 1.0, not UIParent scale -- pooled buttons are never re-parented). Wait for the anchor; OnEnable fires its own refresh.
    if not iconAnchor then return end
    -- WoW Forever: the returns below show nothing, so the Raid Buffs group
    -- watch and the tracking event stand down with them (EABR.FvStandDown);
    -- the event that ends each state (panel close, vehicle exit, alive, rest
    -- ended) refreshes and re-arms them.
    if euiPanelOpen then
        HideCombatIcons(); HideAllIcons()
        if EABR.FOREVER then EABR.FvStandDown() end
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
        if EABR.FOREVER then EABR.FvStandDown() end
        return
    end

    -- Suppresses while dead or in a rested area (city/inn) -- rested areas
    -- always stay hidden, independent of every "Where to Show" setting.
    if UnitIsDeadOrGhost("player") then
        HideCombatIcons(); HideCursorIcons(); HideAllIcons()
        if EABR.FOREVER then EABR.FvStandDown() end
        return
    end
    if IsResting() then
        HideCombatIcons(); HideCursorIcons()
        if InCombat() then FadeOutSecureIcons() else HideAllIcons() end
        if EABR.FOREVER then EABR.FvStandDown() end
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
    -- four collectors below (reminders off: their watch and event stand down).
    if EABR.FOREVER then
        if remindersOn then
            EABR.CollectForeverRaidBuffs(missing, playerClass, inInstance)
            EABR.CollectForever(missing, inInstance, inPvP)
        else
            EABR.FvStandDown()
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
    --  3) Consumables: OOC normally; in restricted contexts the trackable
    --  subset only. In a PvP instance the class specials (poisons, rites,
    --  imbues, shields) still run; the bag and equip items stay off there.
    ---------------------------------------------------------------------------
    if remindersOn and not EABR.FOREVER then
        CollectConsumables(missing, playerClass, specID, inInstance, inKeystone, inCombat, inPvP)
    else
        -- The Inky Black Potion map watch follows the collector that reads it
        InkyMapWatch(false)
    end

    ---------------------------------------------------------------------------
    --  4) Pet Reminders (combat-safe: UnitExists/UnitIsDead unrestricted); suppressed for petless specs, Grimoire of Sacrifice, etc.
    ---------------------------------------------------------------------------
    if remindersOn and not EABR.FOREVER and PET_CLASSES[playerClass] then
        local co = db.profile.consumables
        if co and co.enabled and co.enabled.pet ~= false and EABR.SectionShows(EABR.SpecialsWhere(co, EABR.SPECIALS.PET.where), inInstance) then
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
                            ShowCombatIcon(m)
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

    -- The pool is rebuilt above. A visible button can now represent another reminder.
    if EABR.ValidateOpenPicker then EABR.ValidateOpenPicker() end
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

-------------------------------------------------------------------------------
--  WoW Forever Raid Buffs group watch, synced by every collector pass to what
--  it read (fams = the list of the provider's buffs whose coverage counts the
--  group, or nil; roster = a receiver reminder is possible):
--  GROUP_ROSTER_UPDATE while either applies; while grouped also
--  UNIT_IN_RANGE_UPDATE and UNIT_CONNECTION per group token, plus UNIT_AURA
--  for a provider, each aura event probing its own added and removed auras
--  before a refresh is asked (EABR.FvAuraRelevant).
--  Nothing is registered otherwise (Refresh also stands it down while it
--  shows nothing: the options panel open, a vehicle, dead, resting).
--  RegisterUnitEvent takes two units, so the tokens ride one frame per pair:
--  party1-4 in a party (the player's own auras come through the main frame),
--  raid1-40 in a raid.
-------------------------------------------------------------------------------
function EABR.FvSyncGroupWatch(fams, roster)
    local n = fams and #fams or 0
    local any = n > 0 or roster
    local W = EABR._fvWatch
    if not W then
        if not any then return end
        W = { ids = {}, frames = {}, fams = {} }
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
    -- The watched buffs, copied (the collector reuses its list).
    local same = #W.fams == n
    for i = 1, n do
        if W.fams[i] ~= fams[i] then same = false end
    end
    if not same then
        wipe(W.fams)
        wipe(W.ids)
        for i = 1, n do
            local fam = fams[i]
            W.fams[i] = fam
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
    local auraOn = mode ~= nil and n > 0
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

-- Whether any watched buff stays readable under the restriction.
local function FvWatchReadable(W)
    local fams = W.fams
    for i = 1, #fams do
        if EABR.FvReadable(fams[i], true) then return true end
    end
    return false
end

-- One group aura event against the watched buffs: an added aura of one, or
-- the removal of one the last pass found on that member, asks for a refresh;
-- a full update always does; a payload the restriction made unreadable does
-- while a watched buff itself stays readable.
function EABR.FvAuraRelevant(unit, info)
    local W = EABR._fvWatch
    if not (W and W.fams[1]) then return false end
    if not info then return true end
    if isSecret(info) then return FvWatchReadable(W) end
    local full = info.isFullUpdate
    if isSecret(full) then return FvWatchReadable(W) end
    if full then return true end
    local added = info.addedAuras
    if added then
        if isSecret(added) then return FvWatchReadable(W) end
        for i = 1, #added do
            local aura = added[i]
            if isSecret(aura) then return FvWatchReadable(W) end
            local sid = aura.spellId
            if isSecret(sid) then return FvWatchReadable(W) end
            if sid and W.ids[sid] then return true end
        end
    end
    local removed, found = info.removedAuraInstanceIDs, EABR._fvInst and EABR._fvInst[unit]
    if removed and found and next(found) then
        if isSecret(removed) then return FvWatchReadable(W) end
        for i = 1, #removed do
            local iid = removed[i]
            if isSecret(iid) then return FvWatchReadable(W) end
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
