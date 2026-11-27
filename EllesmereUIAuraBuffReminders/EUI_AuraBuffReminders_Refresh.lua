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
                entry.cat = "forever"; entry.dismissKey = dismissKey; entry.fvSelf = true
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

-- Public player tracking state chooses a visibility row; the native widget
-- selects the target's column without Lua inspecting its restricted type.
local function HunterTrackingState()
    local needed = EABR._fvHunterMissingSpells
    if not needed then
        needed = {}; EABR._fvHunterMissingSpells = needed
        -- Beast, Dragonkin, Demon, Elemental, Giant, Undead, Humanoid.
        EABR._fvHunterTrackingTypes = { [1494]=1, [19879]=2, [19878]=3, [19880]=4,
            [19882]=5, [19884]=6, [19883]=7 }
    end
    if EABR._fvHunterMatchMask ~= nil then return needed, EABR._fvHunterMatchMask end
    wipe(needed)
    local types, mask, uncertain = EABR._fvHunterTrackingTypes, 0, false
    for spellID, creatureTypeID in pairs(types) do
        if not Known(spellID) then mask = bit.bor(mask, 2 ^ (creatureTypeID - 1)) end
    end
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        if info and info.type == "spell" then
            if isSecret(info.spellID) then
                if isSecret(info.active) or info.active then uncertain = true end
            else
                local creatureTypeID = types[info.spellID]
                if creatureTypeID then
                    if isSecret(info.active) then uncertain = true
                    elseif info.active then mask = bit.bor(mask, 2 ^ (creatureTypeID - 1))
                    elseif Known(info.spellID) then needed[creatureTypeID] = info.spellID end
                end
            end
        end
    end
    EABR._fvHunterMatchMask = uncertain and 127 or mask
    return needed, EABR._fvHunterMatchMask
end

function EABR.CollectHunterTracking(missing)
    local exists = UnitExists("target")
    if isSecret(exists) or not exists then return end
    local attackable = UnitCanAttack("player", "target")
    if isSecret(attackable) or not attackable then return end
    local dead = UnitIsDeadOrGhost("target")
    if isSecret(dead) or dead then return end
    local _, creatureTypeID = UnitCreatureType("target")
    local restricted = isSecret(creatureTypeID)
    if not restricted and (type(creatureTypeID) ~= "number"
        or creatureTypeID < 1 or creatureTypeID > 7) then return end
    local needed, mask = HunterTrackingState()
    local spellID
    if not restricted then
        spellID = needed[creatureTypeID]
        if not spellID then return end
    end
    local e = AcquireEntry()
    e.mode = "texture"; e.spellID = spellID
    e.cat = "forever"; e.dismissKey = "forever:huntertracking"; e.fvSelf = true
    e.hunterTrackingStatus = restricted
    e.hunterTargetTypeID = creatureTypeID
    e.hunterMatchMask = restricted and mask or 0
    missing[#missing+1] = e
end

-- A cast-on-click reminder for a WoW Forever spell (gathering, Find Treasure,
-- the mage armors, class buffs), labelled with the spell's name unless a
-- label is given.
function EABR.FvSpellEntry(missing, id, dismissKey, label)
    local e = AcquireEntry()
    e.mode = "spell"; e.spellID = id
    e.label = label or ShortLabel(SpellName(id) or tostring(id))
    e.cat = "forever"; e.dismissKey = dismissKey; e.fvSelf = true
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

do
    -- Use the client's localized name for the food family, shared by many spell IDs.
    local NUTRITIOUS_FOOD = 1248377
    local watch, watching, foods, pending, invalidated
    local isFood = {}  -- [itemID] = whether its use spell is the food family's, kept once its data has loaded
    local spare        -- the table of a bag scan that found nothing new

    function EABR.IsForeverFoodCurrent(snapshot)
        return snapshot == foods
    end

    -- true or false once the item's data has loaded (an item's use spell never
    -- changes), nil until then or while the family's name is missing.
    local function IsFood(id, name)
        local food = isFood[id]
        if food == nil and name then
            if select(6, C_Item.GetItemInfoInstant(id)) ~= Enum.ItemClass.Consumable then
                food = false
            elseif C_Item.IsItemDataCachedByID(id) then
                food = C_Item.GetItemSpell(id) == name
            end
            isFood[id] = food
        end
        return food
    end

    -- The bags' food into found, [itemID] = count. An item whose data has not
    -- loaded is asked for and left out until its answer.
    local function Scan(found, name)
        for bag = 0, NUM_BAG_SLOTS do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local id = C_Container.GetContainerItemID(bag, slot)
                if id and not pending[id] then
                    local food = IsFood(id, name)
                    if food then
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        found[id] = (found[id] or 0) + (info and info.stackCount or 1)
                    elseif food == nil then
                        if not next(pending) then watch:RegisterEvent("ITEM_DATA_LOAD_RESULT") end
                        pending[id] = true
                        C_Item.RequestLoadItemDataByID(id)
                    end
                end
            end
        end
    end

    local function Same(a, b)
        for id, n in pairs(a) do
            if b[id] ~= n then return false end
        end
        for id in pairs(b) do
            if a[id] == nil then return false end
        end
        return true
    end

    function EABR.GetForeverFood()
        if foods then return foods end
        local found = {}
        invalidated = false
        local name = SpellName(NUTRITIOUS_FOOD)
        if name then
            Scan(found, name)
        elseif not watch:IsEventRegistered("SPELL_DATA_LOAD_RESULT") then
            watch:RegisterEvent("SPELL_DATA_LOAD_RESULT")
            C_Spell.RequestLoadSpellData(NUTRITIOUS_FOOD)
        end
        -- A synchronous load result queues another refresh. Leave the cache empty for that pass.
        if not invalidated then foods = found end
        return found
    end

    local best, bestFoods, bestLevel, bestWaits
    local levelWatch = false

    -- The food a click eats: the picked one, else the one this character last ate, else the highest-level one usable.
    -- Second return: a bag food is above the character's level, so a level-up can change the answer.
    function EABR.PickForeverFood(foods, picked)
        if picked and foods[picked] then return picked, false end
        local char = EllesmereUI.CharEntry()
        local last = char and char.foreverFood
        if last and foods[last] then return last, false end
        local level = UnitLevel("player") or 0
        if bestFoods ~= foods or bestLevel ~= level then
            bestFoods, bestLevel, best, bestWaits = foods, level, nil, false
            local bestMin, bestIlvl = -1, -1
            for id in pairs(foods) do
                local _, _, _, ilvl, minLevel = C_Item.GetItemInfo(id)
                minLevel, ilvl = minLevel or 0, ilvl or 0
                if minLevel > level then
                    bestWaits = true
                elseif minLevel > bestMin or (minLevel == bestMin
                    and (ilvl > bestIlvl or (ilvl == bestIlvl and id > best))) then
                    best, bestMin, bestIlvl = id, minLevel, ilvl
                end
            end
        end
        return best, bestWaits
    end

    -- PLAYER_LEVEL_UP on the food watch, kept only while a bag food waits for a level.
    function EABR.SyncForeverFoodLevel(want)
        if want == levelWatch or not watching then return end
        levelWatch = want
        if want then watch:RegisterEvent("PLAYER_LEVEL_UP") else watch:UnregisterEvent("PLAYER_LEVEL_UP") end
    end

    function EABR.SyncForeverFoodWatch(want)
        if want == watching then return end
        watching = want
        foods = nil
        if not want then
            levelWatch = false
            if watch then watch:UnregisterAllEvents(); wipe(pending) end
            return
        end
        if not watch then
            pending = {}
            watch = CreateFrame("Frame")
            watch:SetScript("OnEvent", function(_, event, id, success)
                if event == "ITEM_DATA_LOAD_RESULT" then
                    if not pending[id] then return end
                    pending[id] = nil
                    if not next(pending) then watch:UnregisterEvent(event) end
                    if not success then return end
                    -- A loaded item that is no food changes nothing.
                    if IsFood(id, SpellName(NUTRITIOUS_FOOD)) == false then return end
                elseif event == "SPELL_DATA_LOAD_RESULT" then
                    if id ~= NUTRITIOUS_FOOD then return end
                    watch:UnregisterEvent(event)
                    if not success then return end
                elseif event == "PLAYER_LEVEL_UP" then
                    -- A food left out for its level may be usable now: the next pass reads the level again.
                    if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
                    return
                elseif foods then
                    -- A bag change: the reminders refresh only when the food itself changed.
                    local name = SpellName(NUTRITIOUS_FOOD)
                    if name then
                        local found = spare or {}
                        spare = nil
                        wipe(found)
                        invalidated = false
                        Scan(found, name)
                        if invalidated then
                            -- a load answered inside the scan and asked for the refresh itself
                            spare = found
                            return
                        end
                        if Same(found, foods) then
                            spare = found
                            return
                        end
                        for fid, n in pairs(foods) do
                            if (found[fid] or 0) < n then
                                local char = EllesmereUI.CharEntry(true)
                                if char then char.foreverFood = fid end
                                break
                            end
                        end
                        foods = found
                        if EABR.ValidateOpenPicker then EABR.ValidateOpenPicker() end
                        if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
                        return
                    end
                end
                invalidated = true
                foods = nil
                if EABR.ValidateOpenPicker then EABR.ValidateOpenPicker() end
                if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
            end)
        end
        watch:RegisterEvent("BAG_UPDATE_DELAYED")
    end
end

-- Mage armors (WoW Forever): one reminder while no rank of Frost Armor, Ice
-- Armor or Mage Armor is up; the line up is recorded in this character's
-- roster entry (mageArmor).
function EABR.CollectMageArmor(missing, auraLock, ids)
    local char = EllesmereUI.CharEntry()
    local last = char and char.mageArmor
    local up = CollectLines(missing, auraLock, ids, EABR.MAGE_ARMORS, last,
        "forever:magearmor", EllesmereUI.L("Armor"))
    if up and up ~= last then
        char = char or EllesmereUI.CharEntry(true)
        if char then char.mageArmor = up end
    end
end

-- Demonic Sacrifice: the click summons the chosen demon (Auto: the one out, else the Imp), then sacrifices it.
function EABR.CollectDemonicSacrifice(missing, fo, auraLock)
    local chosen = EABR.SACRIFICE_BUFFS[fo.sacrificeDemon] and fo.sacrificeDemon
    local wanted = EABR.SACRIFICE_BUFFS[chosen or "all"]
    if auraLock and not EABR.FvRanksReadable(wanted) then return end
    if PlayerHasAuraByID(wanted) then return end
    local petFamily
    if UnitExists("pet") and not UnitIsDead("pet") then
        local _, family = UnitCreatureFamily("pet")
        -- Unreadable: which demon is out is unknown, so nothing is offered (a summon would replace it).
        if isSecret(family) then return end
        petFamily = family
    end
    local demons = EABR.SACRIFICE_DEMONS
    local target = demons[1]
    for _, d in ipairs(demons) do
        if (chosen and d.key == chosen) or (not chosen and d.family == petFamily) then
            target = d
            break
        end
    end
    if petFamily == target.family then
        EABR.FvSpellEntry(missing, EABR.DEMONIC_SACRIFICE, "forever:demonicsacrifice")
    elseif Known(target.summon) then
        EABR.FvSpellEntry(missing, target.summon, "forever:demonicsacrifice")
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
    local rec = EllesmereUI.CharData("classBuff")
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
            if up and up ~= last and buff.lines[2] then
                rec = rec or EllesmereUI.CharData("classBuff", true)
                if rec then rec[buff.key] = up end
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
    if buff.create then return nil, nil, EABR.FvHighest(buff.create) end
end

local function FvPick(choice, isImbue, class, wcat, low)
    if choice == "off" then return nil end
    local auto = choice == nil or choice == "auto"
    local list = EABR.FV_WEAPON_BUFFS
    local creatable, createID
    for i = 1, #list do
        local buff = list[i]
        if (auto or choice == buff.key) and (buff.imbue == true) == isImbue
           and (not buff.class or buff.class == class)
           and (not buff.weapon or buff.weapon == wcat) then
            local spellID, itemID, create = FvAvailable(buff, low)
            if spellID or itemID or not auto then return buff, spellID or create, itemID end
            if create and not creatable then creatable, createID = buff, create end
        end
    end
    if creatable then return creatable, createID end
end

local function FvNeeds(left, warnSec)
    if not left then return true end
    if warnSec and left < warnSec then return true end
    local at = GetTime() + left - (warnSec or 0)
    local nextAt = EABR._nextDurationRefreshTime
    if not nextAt or at < nextAt then EABR._nextDurationRefreshTime = at end
    return false
end

-- When an aura runs out, where that can be read: nil for no aura, a secret aura or a
-- secret time, and for an aura that does not run out.
local function FvAuraExpiration(aura)
    if isSecret(aura) or not aura then return end
    local expiration = aura.expirationTime
    if not isSecret(expiration) and expiration and expiration > 0 then return expiration end
end

-- The latest known expiration, or an unreadable flag if we cannot determine it.
local function FvLatestAuraExpiration(ids)
    local latest
    for _, id in ipairs(ids) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if not ok or isSecret(aura) then return nil, true end
        if aura then
            local expiration = FvAuraExpiration(aura)
            if not expiration then return nil, true end
            if not latest or expiration > latest then latest = expiration end
        end
    end
    return latest
end

local function FvWeaponEntry(missing, hand, label, dismissKey, buff, spellID, itemID, hideNoItem, left)
    if buff.spells and not spellID then return end
    if buff.items and not itemID and not spellID and hideNoItem then return end
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
    e.cat = "forever"; e.dismissKey = dismissKey; e.fvSelf = dismissKey == hand.imbueKey
    missing[#missing+1] = e
end

-- Whether the class has a weapon imbue (rogue poisons, shaman imbues, warlock
-- stones): the options build Weapon Imbues only then, so a profile's
-- weaponImbue, shared with such a character, costs nothing on any other class.
do
    local hasImbue = {}
    function EABR.FvClassHasImbue(class)
        if not class then return false end
        local has = hasImbue[class]
        if has == nil then
            has = false
            for _, b in ipairs(EABR.FV_WEAPON_BUFFS or {}) do
                if b.imbue == true and (not b.class or b.class == class) then has = true; break end
            end
            hasImbue[class] = has
        end
        return has
    end
end

function EABR.CollectForeverWeapons(missing, fo, class, wantImbue, wantTemp)
    if not (wantImbue or wantTemp) then return end
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
            local buff, spellID, itemID
            if wantImbue then
                buff, spellID, itemID = FvPick(hands and hands[hand.imbue], true, class, wcat, low)
                if buff and FvNeeds(imbueLeft, warnSec) then
                    FvWeaponEntry(missing, hand, label, hand.imbueKey, buff, spellID, itemID, hideNoItem, imbueLeft)
                end
            end
            if wantTemp then
                buff, spellID, itemID = FvPick(hands and hands[hand.temp], false, class, wcat, low)
                if buff and FvNeeds(tempLeft, warnSec) then
                    FvWeaponEntry(missing, hand, label, hand.tempKey, buff, spellID, itemID, hideNoItem, tempLeft)
                end
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

local sleepStackBadges = { [0] = "0/3", "1/3", "2/3", "3/3" }
local function CollectSleepingBag(showBelow, resting, auraLock)
    local sleepIDs = EABR._fvSleepIDs
    if not sleepIDs then sleepIDs = { EABR.SLEEPING_BAG_BUFF }; EABR._fvSleepIDs = sleepIDs end
    if auraLock and not EABR.FvRanksReadable(sleepIDs) then return end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, EABR.SLEEPING_BAG_BUFF)
    local stacks = ok and not isSecret(aura) and (aura and aura.applications or 0)
    local expireAt, duration, stackText, swipe
    local expiration = ok and showBelow > 0 and EABR.ShowUnderThresholdApplies() and FvAuraExpiration(aura)
    if expiration then
        local left = expiration - GetTime()
        if left > 0 and FvNeeds(left, showBelow * 60) then
            expireAt, duration = expiration, left
        end
    end
    local readableStacks = stacks and not isSecret(stacks)
    local missingStacks = readableStacks and stacks < EABR.SLEEPING_BAG_STACKS
    if resting and EABR._fvSleepStartedAt and readableStacks then
        local previousStacks = EABR._fvSleepStacks
        EABR._fvSleepStacks = stacks
        local full = stacks >= EABR.SLEEPING_BAG_STACKS
        if previousStacks ~= nil and stacks ~= previousStacks then
            local savedEnd = EABR._fvSleepReloaded and EABR._fvSleepProgressEnd
            if type(savedEnd) == "number" and savedEnd > GetTime() and stacks > previousStacks and not full then
                -- A stack gained during reload belongs to the original countdown.
                EABR._fvSleepStartedAt = savedEnd - (EABR.SLEEPING_BAG_STACKS - stacks) * 60
            else
                EABR._fvSleepStartedAt = GetTime()
            end
            -- Reaching three stacks ends the timer. Entering at three starts a refresh timer.
            if full then
                EABR._fvSleepProgressEnd = false
            else
                EABR._fvSleepProgressEnd = nil
            end
        end
        if EABR._fvSleepProgressEnd ~= false then
            local total = math.max(1, EABR.SLEEPING_BAG_STACKS - stacks) * 60
            local progressEnd = EABR._fvSleepStartedAt + total
            EABR._fvSleepProgressEnd = progressEnd
            local left = progressEnd - GetTime()
            if left > 0 then
                FvNeeds(left)
                expireAt, duration, swipe = progressEnd, total, true
            end
        end
        EABR._fvSleepReloaded = nil
        stackText = sleepStackBadges[stacks]
    end
    if expireAt or stackText or (not resting and missingStacks) then
        local item = EABR.SLEEPING_BAG_ITEM
        local e = AcquireEntry()
        if resting then
            e.mode = "texture"; e.spellID = EABR.SLEEPING_BAG_BUFF
            e.texture = Tex(EABR.SLEEPING_BAG_BUFF)
        else
            e.mode = "item"; e.itemID = item
            e.texture = C_Item.GetItemIconByID(item) or Tex(EABR.SLEEPING_BAG_BUFF)
        end
        e.expireAt, e.expireTotal, e.expireSwipe = expireAt, duration, swipe
        e.stackText = stackText
        e.label = EllesmereUI.L("Sleeping")
        e.cat = "forever"; e.dismissKey = "forever:sleepingbag"
        return e
    end
end

-- The item ID of the Arcane Censer or Elemental Attractor in the bags, or false.
function EABR.FvCenserInBags()
    if (C_Item.GetItemCount(EABR.ARCANE_CENSER_ITEM) or 0) > 0 then return EABR.ARCANE_CENSER_ITEM end
    if (C_Item.GetItemCount(EABR.ELEMENTAL_ATTRACTOR_ITEM) or 0) > 0 then return EABR.ELEMENTAL_ATTRACTOR_ITEM end
    return false
end

-- The censer in the bags (EABR.FvCenserInBags): counted once and kept until a
-- bag change, a loading screen or a stand-down, as the Sleeping Bag is.
function EABR.FvCenserOwned()
    local owned = EABR._fvCenser
    if owned == nil then
        owned = EABR.FvCenserInBags()
        EABR._fvCenser = owned
    end
    return owned
end

-- Item ID, stat bonus, and aura spell ID, strongest first; an item that gives two
-- stats is listed under both. Checked against the game's item and spell effect
-- tables for WoW Forever 1.60.1.71037.
local intellectConsumables = {
    label = "Intellect", dismissKey = "forever:intellect", iconSpell = 1459,
    setting = "intellectConsumableByClass", family = "ai",
    items = {
        { 9179, 25, 11396 }, { 250328, 25, 1250918 }, { 13447, 18, 17535 }, { 10308, 16, 12176 },
        { 4419, 12, 8098 }, { 250354, 10, 1250989 }, { 2290, 8, 8097 }, { 250353, 6, 1250988 },
        { 955, 4, 8096 }, { 3383, 3, 3166 },
    },
}
local strengthConsumables = {
    label = "Strength", dismissKey = "forever:strength", iconSpell = 8118,
    setting = "strengthConsumableByClass",
    items = {
        { 250351, 25, 1250986 }, { 9206, 25, 11405 }, { 250350, 18, 1250985 },
        { 10310, 17, 12179 }, { 4426, 13, 8120 }, { 250349, 10, 1250984 }, { 2289, 9, 8119 },
        { 3391, 8, 3164 }, { 6662, 8, 8212 }, { 954, 5, 8118 }, { 2454, 4, 2367 },
    },
}
local agilityConsumables = {
    label = "Agility", dismissKey = "forever:agility", iconSpell = 8115,
    setting = "agilityConsumableByClass",
    items = {
        { 13452, 25, 17538 }, { 250328, 25, 1250918 }, { 9187, 25, 11334 }, { 250350, 18, 1250985 },
        { 10309, 17, 12174 }, { 8949, 15, 11328 }, { 4425, 13, 8117 }, { 1477, 9, 8116 },
        { 3390, 8, 3160 }, { 3012, 5, 8115 }, { 2457, 4, 2374 },
    },
}
local staminaConsumables = {
    label = "Stamina", dismissKey = "forever:stamina", iconSpell = 8099,
    setting = "staminaConsumableByClass", family = "fort",
    items = { { 10307, 16, 12178 }, { 4422, 12, 8101 }, { 1711, 8, 8100 }, { 1180, 4, 8099 } },
    -- Max-health bonuses stack with Stamina, so check their auras separately.
    health = {
        items = { { 250335, 400, 1250931 }, { 250334, 200, 1250928 }, { 3825, 120, 3593 }, { 2458, 27, 2378 } },
    },
}
local spiritConsumables = {
    label = "Spirit", dismissKey = "forever:spirit", iconSpell = 8112,
    setting = "spiritConsumableByClass", family = "spirit",
    items = {
        { 250348, 25, 1250981 }, { 250338, 25, 1250941 }, { 13447, 18, 17535 }, { 250347, 18, 1250979 },
        { 10306, 15, 12177 }, { 4424, 11, 8114 }, { 250346, 10, 1250978 }, { 1712, 7, 8113 },
        { 250345, 6, 1250976 }, { 1181, 3, 8112 }, { 250344, 3, 1250974 },
    },
}
local protectionConsumables = {
    label = "Protection", dismissKey = "forever:protection", iconSpell = 8091,
    setting = "protectionConsumableByClass",
    items = {
        { 250329, 500, 1250920 }, { 13445, 450, 11348 }, { 8951, 250, 11349 }, { 10305, 240, 12175 },
        { 4421, 180, 8095 }, { 3389, 150, 3220 }, { 1478, 120, 8094 }, { 3013, 60, 8091 }, { 5997, 50, 673 },
    },
}
-- The single reminder uses the first eligible stat in dropdown order.
local statConsumables = {
    intellectConsumables, strengthConsumables, agilityConsumables, staminaConsumables, spiritConsumables, protectionConsumables,
}
local statBonusesToBeat = {}
local statExpirations = {}
local statConsumableDismissKey = "forever:scrollsAndElixirs"
local statConsumableChoices, statConsumableMacros
local statConsumableBuffClasses = { ai = "MAGE", fort = "PRIEST", spirit = "PRIEST" }
local campStatAuraID, campStatExpiration, campIntellectAmount, campFirstAidKit

function EABR.FvInvalidateCampStats(info)
    if not campStatAuraID then return end
    if isSecret(info) or not info or isSecret(info.isFullUpdate) or info.isFullUpdate then
        campStatAuraID = nil
        return
    end
    local updated = info.updatedAuraInstanceIDs
    if isSecret(updated) then
        campStatAuraID = nil
    elseif updated then
        for _, id in ipairs(updated) do
            if isSecret(id) or id == campStatAuraID then
                campStatAuraID = nil
                break
            end
        end
    end
end

local function FvCampStatBonuses()
    -- Camp Benefits exposes its individual bonuses in the aura tooltip.
    local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, "player", EABR.CAMP_BENEFITS)
    if not ok or isSecret(aura) then return 0 end
    if not aura then
        campStatAuraID = nil
        return 0
    end
    local id, expiration = aura.auraInstanceID, aura.expirationTime
    if isSecret(id) or not id or isSecret(expiration) then return 0 end
    if id == campStatAuraID and expiration == campStatExpiration then return campIntellectAmount, campFirstAidKit end

    local candle = C_Spell.GetSpellName(1229705) -- Incense Candle
    local kit = C_Spell.GetSpellName(1307244) -- First Aid Kit
    if isSecret(candle) then candle = nil end
    if isSecret(kit) then kit = nil end
    if not candle and not kit then return 0 end
    local hasTooltip, tooltip = pcall(C_TooltipInfo.GetUnitAuraByAuraInstanceID, "player", id)
    if not hasTooltip or isSecret(tooltip) or not tooltip then return 0 end
    local lines = tooltip.lines
    if isSecret(lines) or not lines then return 0 end
    local amount, hasKit = 0, false
    for _, line in ipairs(lines) do
        if isSecret(line) then return 0 end
        local text = line.leftText
        if isSecret(text) then return 0 end
        if text then
            for entry in text:gmatch("[^\r\n]+") do
                local start, last
                if candle then start, last = entry:find(candle, 1, true) end
                if start and entry:sub(1, start - 1):match("^%s*$") then
                    amount = tonumber(entry:match("(%d+)%D*$", last + 1)) or amount
                end
                if kit and not hasKit then
                    start = entry:find(kit, 1, true)
                    hasKit = start ~= nil and entry:sub(1, start - 1):match("^%s*$") ~= nil
                end
            end
        end
    end
    if candle and kit then
        campStatAuraID, campStatExpiration = id, expiration
        campIntellectAmount, campFirstAidKit = amount, hasKit
    end
    return amount, hasKit
end

function ns.FvStatConsumableLocked(family, class)
    local buffClass = family and statConsumableBuffClasses[family]
    if not buffClass or buffClass ~= class then return false, false end
    local ranks = EllesmereUI.FOREVER_BUFF_FAMILIES[family].single
    return EABR.FvHighest(ranks) ~= nil, true
end

local function StatConsumableAuraState(items, watchExpiration)
    local strongest, latest, unknownExpiration = 0
    for _, item in ipairs(items) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, item[3])
        if not ok or isSecret(aura) then return end
        if aura then
            if strongest == 0 then strongest = item[2] end
            if not watchExpiration then return strongest end
            local expiration = FvAuraExpiration(aura)
            if not expiration then unknownExpiration = true
            elseif not latest or expiration > latest then latest = expiration end
        end
    end
    return strongest, not unknownExpiration and latest or nil
end

local function ItemsOwned(items)
    for _, item in ipairs(items) do
        if CachedGetItemCount(item[1]) > 0 then return true end
    end
    return false
end

local function StatBonusToBeat(stat, restricted, warnSec, showUpgrades, campIntellect, firstAidKit)
    if stat == staminaConsumables and firstAidKit then return end
    local amount = 0
    if stat.family then
        local family = EllesmereUI.FOREVER_BUFF_FAMILIES[stat.family]
        if not EABR.FvReadable(family, restricted) then return end
        local aura = EllesmereUI.ForeverFamilyAura("player", family)
        if isSecret(aura) or aura == nil then return end
        if aura then
            if not showUpgrades then return end
            local spellID = aura.spellId
            if isSecret(spellID) then return end
            amount = family.amounts and family.amounts[spellID]
            if not amount then return end
        end
    end
    if stat == intellectConsumables then amount = math.max(amount, campIntellect or 0) end
    local items = stat.items
    if (amount > 0 and not showUpgrades) or amount >= items[1][2] then return end
    if restricted then
        for _, item in ipairs(items) do
            if not EABR.IsRuntimeNonSecret(item[3]) then return end
        end
    end
    local active, expiration = StatConsumableAuraState(items, warnSec)
    if not active then return end
    if active == 0 then return amount end
    if expiration then
        local remaining = expiration - GetTime()
        if remaining > 0 and FvNeeds(remaining, warnSec) then return amount, expiration end
    end
    if showUpgrades and active < items[1][2] then return math.max(amount, active) end
end

local function PickStatConsumable(stat, activeBonus, level, choices, low)
    local watchLevel = false
    local firstID
    local first, last, step = 1, #stat.items, 1
    if low then first, last, step = last, first, -1 end
    for i = first, last, step do
        local consumable = stat.items[i]
        local itemID, bonus = consumable[1], consumable[2]
        if not low and bonus <= activeBonus then break end
        local count = bonus > activeBonus and CachedGetItemCount(itemID) or 0
        if count > 0 then
            local requiredLevel = EABR.FvConsumableItemLevel(itemID)
            if requiredLevel then
                if level >= requiredLevel then
                    if not choices then return itemID, watchLevel end
                    choices[itemID] = count
                    firstID = firstID or itemID
                else
                    watchLevel = true
                end
            end
        end
    end
    return firstID, watchLevel
end

local function AddStatConsumableEntry(missing, stat, itemID, expiration, choices, separate, automaticItemID)
    if not statConsumableMacros then statConsumableMacros = {} end
    local macro = statConsumableMacros[itemID]
    if not macro then
        macro = "/use [@player,nocombat] item:" .. itemID
        statConsumableMacros[itemID] = macro
    end
    local e = AcquireEntry()
    e.mode = "macro"
    e.macro = macro
    e.texture = C_Item.GetItemIconByID(itemID) or Tex(stat.iconSpell)
    e.tooltipItem = itemID
    e.label = EllesmereUI.L(stat.label)
    e.cooldownItemID = itemID
    e.cat = "forever"
    e.dismissKey = separate and stat.dismissKey or statConsumableDismissKey
    e.foreverStatItems = choices
    e.foreverStatAutomaticItem = choices and automaticItemID or nil
    e.foreverStatFamily = separate and stat.dismissKey or nil
    if expiration then e.expireAt, e.expireTotal = expiration, expiration - GetTime() end
    missing[#missing + 1] = e
end

-- WoW Forever collector: the Camp Benefits campfire buff, the Sleeping Bag's
-- Well-Rested buff (missing or under its full stacks, or inside its cog's Show
-- Below minutes of running out, then with the countdown; while a Cozy Sleeping
-- Bag is in the bags below max level: EABR.FvSleepingBagOwned), the Arcane
-- Censer's Magical Awareness (in dungeons, while a censer is in the bags:
-- EABR.FvCenserOwned), Well Fed (any food
-- buff: the shared Well Fed name, or one of EABR.FOOD_BUFFS), the gathering
-- and Find Treasure trackers, a Mage's armors (EABR.CollectMageArmor), the
-- class buffs (EABR.CollectClassBuffs), the weapon buffs
-- (EABR.CollectForeverWeapons), the Scrolls and Elixirs reminder (the ticked
-- stats of the class, while an item of the stat is in the bags and its buff
-- is missing or, with Show Stronger Buffs, weaker), the user's spell groups
-- (EABR.CollectForeverGroups) and custom spell IDs (each for the classes ticked
-- on it), those a ticked class buff covers standing down outside PvP. All are
-- absence only but the weapon buffs, the Sleeping Bag and Well Fed, which also
-- show their Show Below minutes before running out, with a countdown (FvNeeds
-- arms the one-shot duration refresh for that moment). A custom ID counts as up while any
-- spell of its rank family is (EABR.ForeverFamily). Entries are display-only
-- textures carrying the spell for the tooltip, except the Sleeping Bag, the
-- Arcane Censer, the two trackers, the mage armors, the class buffs, the weapon buffs, the spell
-- groups and the custom spells the character knows, whose click casts the spell
-- or uses the item; presence goes through PlayerHasAuraByID. Hunter target
-- tracking is a visual-only combat reminder; every other reminder here is
-- out of combat. Camp Benefits, the Sleeping Bag, Well Fed, the mage armors,
-- the class buffs and the trackers nothing in PvP either. The one-slot id
-- table, the cached families, the kept minimap answer and the dismiss-key memo
-- keep the pass allocation-free; the weapon pass reads the game's enchant
-- lists, a table per weapon. Two sections, each gated by its own Where to
-- Show: Self Buffs (fo.selfWhereToShow: the trackers, Mage Armors, class
-- buffs, Weapon Imbues for a class that has one, hunter Target Tracking,
-- spell groups and custom spells, each entry marked fvSelf, which picks the
-- Self Buffs sound in ResolveReminderSound) and Consumables (fo.whereToShow:
-- the rest, Weapon Stones and Oils included). Refresh then puts the fvSelf
-- entries first (EABR.FvSelfFirst).
function EABR.CollectForever(missing, inInstance, inPvP, playerClass)
    local fo = db.profile.forever
    local itemShows = fo and not InCombat() and EABR.SectionShows(fo.whereToShow, inInstance)
    local selfShows = fo and not InCombat() and EABR.SectionShows(fo.selfWhereToShow, inInstance)
    local hunterTracking = fo and fo.hunterTracking == true and GetPlayerClass() == "HUNTER"
        and InCombat() and EABR.SectionShows(fo.selfWhereToShow, inInstance) or false
    EABR.FvSyncHunterTrackingEvents(hunterTracking)
    if hunterTracking then EABR.CollectHunterTracking(missing) end
    -- Class trackers and Find Treasure are read from the minimap, whose event
    -- is listened to only while a reminder that reads it can show.
    EABR.FvSyncTrackingEvent(hunterTracking or (selfShows and not inPvP
        and ((fo.gather == true and fo.gatherClassTrack ~= false) or fo.treasure == true)) or false)
    local wantImbue = selfShows and fo.weaponImbue == true and EABR.FvClassHasImbue(GetPlayerClass()) or false
    local wantTemp = itemShows and fo.weapon == true or false
    EABR.FvSyncWeaponEvents(wantImbue or wantTemp)
    local wantBag = itemShows and fo.sleepingBag == true and not inPvP
    local sleepBag = wantBag and EABR.FvSleepingBagOwned()
    -- The Arcane Censer, in dungeons only: its buff is read first, and the
    -- censer is counted only while the buff is missing (counted again the
    -- next time it goes missing), so a dungeon run with the buff up costs no
    -- bag work at all.
    local censerIDs = EABR._fvCenserIDs
    if not censerIDs then censerIDs = { EABR.ARCANE_CENSER_BUFF }; EABR._fvCenserIDs = censerIDs end
    local wantCenser = itemShows and fo.arcaneCenser == true and EllesmereUI.IsInDungeon()
    local censerMissing = wantCenser and not PlayerHasAuraByID(censerIDs)
        and not (EllesmereUI.AuraKit.AurasRestricted() and not EABR.FvRanksReadable(censerIDs))
    if wantCenser and not censerMissing then EABR._fvCenser = nil end
    local censer = censerMissing and EABR.FvCenserOwned() or false
    local statConsumableNeeded = false
    local statWaitsForItem = false
    local watchStatSpells = false
    local healthBonus, healthExpiration
    local separate = fo and fo.statConsumableSeparateReminders == true
    if itemShows and not inPvP and playerClass and (separate or not _dismissedUntilLoad[statConsumableDismissKey]) then
        local restricted, campIntellect, firstAidKit
        local minutes = fo.statConsumableShowBelow or 0
        local warnSec = minutes > 0 and EABR.ShowUnderThresholdApplies() and minutes * 60 or nil
        local showUpgrades = fo.statConsumableShowUpgrades == true
        for i, stat in ipairs(statConsumables) do
            local picks = fo[stat.setting]
            local enabled = picks and picks[playerClass]
            local bonus, expiration
            if enabled == true and not (separate and _dismissedUntilLoad[stat.dismissKey]) then
                local locked, tracksSpell = ns.FvStatConsumableLocked(stat.family, playerClass)
                if tracksSpell then watchStatSpells = true end
                if not locked then
                    -- The bags first (a hash lookup per item): a stat with none of its
                    -- items owned cannot show, so its buffs are not read; the bag
                    -- listener stays on to hear one arrive.
                    local own = ItemsOwned(stat.items)
                    local ownHealth = stat.health and ItemsOwned(stat.health.items)
                    if own or ownHealth then
                        if restricted == nil then restricted = EllesmereUI.AuraKit.AurasRestricted() end
                        if own and not restricted and campIntellect == nil and (stat == intellectConsumables or stat == staminaConsumables) then
                            campIntellect, firstAidKit = FvCampStatBonuses()
                        end
                        if own then
                            bonus, expiration = StatBonusToBeat(stat, restricted, warnSec, showUpgrades, campIntellect, firstAidKit)
                        end
                        if ownHealth then
                            healthBonus, healthExpiration = StatBonusToBeat(stat.health, restricted, warnSec, showUpgrades)
                        end
                        if bonus ~= nil or (ownHealth and healthBonus ~= nil) then statConsumableNeeded = true end
                    else
                        statWaitsForItem = true
                    end
                end
            end
            statBonusesToBeat[i] = bonus
            statExpirations[i] = expiration
        end
    end
    -- A plain boolean: censer is the item ID, and the listener's sync compares by value.
    local bagListen = (wantImbue or wantTemp or sleepBag or (censer and true) or statConsumableNeeded
        or statWaitsForItem) or false
    EABR.FvSyncSleepBagWatch(wantBag and not sleepBag and not EABR._fvMaxLevel
        and not bagListen or false)
    EABR.FvSyncCenserWatch(censerMissing and not censer and not bagListen or false)
    EABR.FvSyncBagEvent(bagListen)
    local anyShows = selfShows or itemShows
    local pickerEnabled = anyShows and PickerEnabled() or false
    -- The spellbook feeds the families and the class buff choices, both Self Buffs.
    local watchSpellbook = (selfShows and pickerEnabled) or watchStatSpells
    if watchSpellbook ~= (EABR._fvSpellbookEvents or false) then
        EABR.FvSyncSpellbookEvents(watchSpellbook)
    end
    local watchFood = itemShows and not inPvP and fo.wellFed or false
    if not anyShows then
        EABR.FvSyncConsumableItemEvents(false, false)
        EABR.SyncForeverFoodWatch(false)
        EABR.FvSyncPetEvent(false)
        return
    end
    local open = not inPvP
    -- Under the aura lock a secret aura reads absent, so an aura reminder
    -- shows only while none of its spells is secret.
    local auraLock = EllesmereUI.AuraKit.AurasRestricted()
    local ids = EABR._foreverIDs
    if not ids then ids = {}; EABR._foreverIDs = ids end
    if itemShows and fo.camp ~= false and open then
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
    if sleepBag then
        local e = CollectSleepingBag(fo.sleepingBagShowBelow or 0, false, auraLock)
        if e then missing[#missing+1] = e end
    end
    local watchLevel = false
    local beforeStatCount = #missing
    if statConsumableNeeded then
        local level = UnitLevel("player")
        local sharedChoices, preferred, familyPicks
        if pickerEnabled then
            if separate then
                familyPicks = fo.statConsumablePickerByFamily and fo.statConsumablePickerByFamily[playerClass]
            else
                if not statConsumableChoices then statConsumableChoices = {} end
                sharedChoices = statConsumableChoices
                wipe(sharedChoices)
                preferred = fo.statConsumablePickerByClass and fo.statConsumablePickerByClass[playerClass]
            end
        end
        local chosenID, chosenIndex, chosenExpiration, automaticItemID
        local low = fo.statConsumableLowRank == true
        for i, stat in ipairs(statConsumables) do
            local bonus = statBonusesToBeat[i]
            local canUseHealth = stat.health and healthBonus ~= nil
            if bonus or canUseHealth then
                local choices = sharedChoices
                if separate and pickerEnabled then
                    if not stat.choices then stat.choices = {} end
                    choices = stat.choices
                    wipe(choices)
                end
                local itemID, blockedByLevel
                local expiration = statExpirations[i]
                local pinned = separate and familyPicks and familyPicks[stat.dismissKey] or preferred
                if bonus then
                    itemID, blockedByLevel = PickStatConsumable(stat, bonus, level, choices, low)
                    if blockedByLevel then watchLevel = true end
                end
                local pinnedScroll = pinned and choices[pinned]
                -- Prefer a scroll automatically. A pinned elixir uses its own aura timer.
                if canUseHealth and (choices or not itemID) then
                    local healthID
                    healthID, blockedByLevel = PickStatConsumable(stat.health, healthBonus, level, choices, low)
                    if blockedByLevel then watchLevel = true end
                    if not itemID then
                        itemID, expiration = healthID, healthExpiration
                    elseif pinned and choices[pinned] and not pinnedScroll then
                        expiration = healthExpiration
                    end
                end
                local automatic = itemID
                if pinned and choices[pinned] then itemID = pinned end
                if separate then
                    if itemID then AddStatConsumableEntry(missing, stat, itemID, expiration, choices, true, automatic) end
                else
                    automaticItemID = automaticItemID or automatic
                    if itemID and not chosenID then
                        chosenID, chosenIndex, chosenExpiration = itemID, i, expiration
                        if not choices then break end
                    end
                    if preferred and choices[preferred] then
                        chosenID, chosenIndex, chosenExpiration = preferred, i, expiration
                        preferred = nil
                    end
                end
            end
        end
        if chosenID then
            AddStatConsumableEntry(missing, statConsumables[chosenIndex], chosenID, chosenExpiration, sharedChoices, false, automaticItemID)
        end
    end
    EABR.FvSyncConsumableItemEvents(statConsumableNeeded, watchLevel, #missing > beforeStatCount)
    -- Arcane Censer: its buff missing and a censer in the bags (read above);
    -- the click uses the censer.
    if censer then
        local item = censer
        local e = AcquireEntry()
        e.mode = "item"; e.itemID = item
        e.texture = C_Item.GetItemIconByID(item) or Tex(EABR.ARCANE_CENSER_BUFF)
        e.label = EllesmereUI.L("Censer")
        e.cat = "forever"; e.dismissKey = "forever:censer"
        missing[#missing+1] = e
    end
    -- Gathering tracking: shown while no tracker is up and the player knows
    -- one; the button casts the first one known. The aura read goes first, so
    -- the common case (a tracker up) skips the rest; class trackers are no
    -- auras there, so the minimap is asked only once a tracker is known.
    local scanned, treasureUp, classUp
    local list = EABR.GATHER_TRACKING
    if selfShows and fo.gather and open and not PlayerHasAuraByID(list)
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
    if selfShows and fo.treasure and open and Known(tid) then
        if not scanned then treasureUp = EABR.FvTrackingState() end
        if not treasureUp then EABR.FvSpellEntry(missing, tid, "forever:treasure") end
    end
    if itemShows and fo.wellFed and open and not _dismissedUntilLoad["forever:wellfed"] then
        local name = SpellName(EABR.WELL_FED) or "Well Fed"
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
        -- Shown while no food buff is up and, with Show Below set, that many minutes before
        -- the one that is up runs out (the buff named Well Fed, else the last of the foods
        -- with a name of their own), then with its countdown.
        local show, expireAt, remaining
        local warnSec = (fo.wellFedShowBelow or 0) * 60
        if ok and not isSecret(aura) then
            local fallback = not aura and PlayerHasAuraByID(EABR.FOOD_BUFFS)
            show = not aura and not fallback
            if not show and warnSec > 0 and EABR.ShowUnderThresholdApplies() then
                expireAt = aura and FvAuraExpiration(aura) or (fallback and FvLatestAuraExpiration(EABR.FOOD_BUFFS))
                if expireAt then
                    remaining = expireAt - GetTime()
                    show = remaining > 0 and FvNeeds(remaining, warnSec)
                end
            end
        end
        EABR.SyncForeverFoodWatch(watchFood and show == true)
        if show then
            local e = AcquireEntry()
            e.mode = "texture"; e.spellID = EABR.WELL_FED
            e.texture = Tex(EABR.WELL_FED)
            e.label = name
            e.cat = "forever"; e.dismissKey = "forever:wellfed"
            if expireAt then e.expireAt, e.expireTotal = expireAt, remaining end
            if watchFood then
                local foods = EABR.GetForeverFood()
                if pickerEnabled and next(foods) then e.foreverFood = foods end
                local id, waits = EABR.PickForeverFood(foods, pickerEnabled and fo.wellFedItem)
                EABR.SyncForeverFoodLevel(waits)
                if id then
                    e.mode = "macro"
                    e.macro = EABR.ForeverFoodMacro(id)
                    e.spellID = nil
                    e.tooltipItem = id
                    e.texture = C_Item.GetItemIconByID(id) or e.texture
                    e.bagCount = foods[id]
                end
            end
            missing[#missing+1] = e
        end
    else
        EABR.SyncForeverFoodWatch(false)
    end
    if selfShows and fo.mageArmor and open and GetPlayerClass() == "MAGE" then
        EABR.CollectMageArmor(missing, auraLock, ids)
    end
    local watchPet = selfShows and fo.demonicSacrifice and open and GetPlayerClass() == "WARLOCK"
        and Known(EABR.DEMONIC_SACRIFICE) or false
    EABR.FvSyncPetEvent(watchPet)
    if watchPet then
        EABR.CollectDemonicSacrifice(missing, fo, auraLock)
    end
    -- The ticked class buffs, outside PvP; the custom spells and spell groups
    -- they cover stand down there (EABR.FvClassTracked).
    local coveredIDs, coveredNames
    if selfShows and open then
        coveredIDs, coveredNames = EABR.FvClassTracked(fo, GetPlayerClass())
        if coveredIDs then EABR.CollectClassBuffs(missing, fo, auraLock, ids, GetPlayerClass()) end
    end
    EABR.CollectForeverWeapons(missing, fo, GetPlayerClass(), wantImbue, wantTemp)
    if not selfShows then return end
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
        -- A custom Magical Awareness stands down while the Arcane Censer
        -- reminder shows for it.
        if not (censer and id == EABR.ARCANE_CENSER_BUFF) and not (off and off[class] == false) then
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
                    e.cat = "forever"; e.dismissKey = dk; e.fvSelf = true
                    missing[#missing+1] = e
                end
            end
        end
    end
end

-- Self Buffs ahead of Consumables from missing[first] on, each keeping its own order.
do
    local items = {}
    function EABR.FvSelfFirst(missing, first)
        local w, n = first, 0
        for i = first, #missing do
            local e = missing[i]
            if e.fvSelf then
                missing[w] = e; w = w + 1
            else
                n = n + 1; items[n] = e
            end
        end
        for i = 1, n do
            missing[w] = items[i]; w = w + 1
            items[i] = nil
        end
    end
end

-------------------------------------------------------------------------------
--  WoW Forever Raid Buffs: the retail section's two views over that client's
--  buffs (RAID_BUFFS). A member has a buff while an aura of its family is up
--  (every rank, the group version, other casters' versions: the parent's
--  ForeverFamilyAura). Under the game's aura restriction a buff is read only while none
--  of its ranks is secret (a secret aura would read absent while up), and
--  shows nothing otherwise rather than a false alarm. Absence only (no expiry
--  thresholds).
-------------------------------------------------------------------------------
-- Whether a unit carries any rank of a family: true / false, or nil when the
-- answer cannot be read. rec (optional) collects the found aura's instance ID
-- for the group aura probe.
function EABR.FvUnitHas(u, fam, rec)
    local aura = EllesmereUI.ForeverFamilyAura(u, fam)
    if not aura then return aura end
    local iid = rec and aura.auraInstanceID
    if iid and not isSecret(iid) then rec[iid] = true end
    return true
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
-- to what it read. A class that provides two buffs (a priest with Divine
-- Spirit) shows, out of combat, every one that is missing and not dismissed:
-- the first in list order on the provider button, bound to its cast, each
-- further one on a secure icon of its own (fvExtra, its own cast and member);
-- with none showing, the button stays bound to the first buff it provides. In
-- combat (ABR's own flag too, set at ENCOUNTER_START before the lockdown) only
-- the buff the button casts shows.
function EABR.CollectForeverRaidBuffs(missing, playerClass, inInstance)
    local rb = db.profile.raidBuffs
    local watch = EABR._fvWatchFams
    if watch then wipe(watch) else watch = {}; EABR._fvWatchFams = watch end
    local roster = false
    local castSpell, castUnit
    local provided, covered, idle, idleFirst = false, false, nil, nil
    local lockdown = InCombatLockdown()
    local noExtras = lockdown or InCombat()
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
                    local isMissing, have, total, first, extraCast, extraUnit, isExtra
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
                        isMissing = isMissing and not (provided and noExtras)
                            and not _dismissedUntilLoad[buff.dismissKey]
                            and not (bound and not (tContains(fam.single, bound) or tContains(fam.group, bound)))
                        if isMissing and provided then
                            -- A further buff: its own icon, never the provider's.
                            isExtra = true
                            extraCast, extraUnit = EABR.FvPickCast(buff, first)
                            if not extraCast then isMissing = false end
                        elseif isMissing then
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
                            if isExtra then
                                e.spellID, e.unit, e.fvExtra = extraCast, extraUnit, true
                            else
                                e.spellID = castSpell or EABR._providerCastSpell
                            end
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
-- watch and the minimap, target, weapon, pet and bag events); the next pass that can show
-- re-arms them.
function EABR.FvStandDown(keepSleepProgress)
    EABR.SyncForeverFoodWatch(false)
    EABR.FvSyncGroupWatch(nil, false)
    EABR.FvSyncTrackingEvent(false)
    EABR.FvSyncHunterTrackingEvents(false)
    EABR.FvSyncWeaponEvents(false)
    EABR.FvSyncPetEvent(false)
    EABR.FvSyncConsumableItemEvents(false, false)
    EABR.FvSyncBagEvent(false)
    EABR.FvSyncSleepBagWatch(false)
    EABR.FvSyncCenserWatch(false)
    EABR._fvCenser = nil
    if not keepSleepProgress and EABR._fvSleepStartedAt then EABR.ClearSleepProgress() end
    -- Bag changes go unheard while these listeners are off, so the bag is
    -- counted again later; a running sleep timer keeps the answer (the bag is
    -- in use, and every pass of the timer would count it again).
    if not keepSleepProgress then EABR._fvSleepBag = nil end
    if EABR._fvSpellbookEvents then EABR.FvSyncSpellbookEvents(false) end
    if EABR.ValidateOpenPicker then EABR.ValidateOpenPicker() end
    if EABR._durationTimer then
        EABR._durationTimer:Cancel()
        EABR._durationTimer = nil
    end
end

local function SyncSleepProgress()
    local fo = db.profile.forever
    local want = fo and fo.sleepingBag == true and fo.sleepingBagShowProgress ~= false
        and db.profile.display.remindersEnabled ~= false and not InCombat() and not UnitIsDeadOrGhost("player")
        and not UnitInVehicle("player") and not (IsMounted() and IsFlying())
    if want then
        CacheInstanceInfo()
        want = not InPvPInstance() and EABR.SectionShows(fo.whereToShow, InRealInstancedContent())
    end
    if not want then
        if EABR._fvSleepStartedAt then EABR.ClearSleepProgress() end
        return
    end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, EABR.SLEEPING_BAG_TRACKING)
    -- A restricted or failed read cannot establish either entry or exit.
    if not ok or isSecret(aura) then return end
    if not aura or not EABR.FvSleepingBagOwned() then
        if EABR._fvSleepStartedAt then EABR.ClearSleepProgress() end
        return
    end
    local instanceID = aura.auraInstanceID
    if isSecret(instanceID) then instanceID = nil end
    if not EABR._fvSleepStartedAt
        or (instanceID and EABR._fvSleepAuraInstance and instanceID ~= EABR._fvSleepAuraInstance) then
        EABR.StartSleepProgress(instanceID)
    else
        EABR._fvSleepAuraInstance = instanceID
    end
end

local function RefreshRestedSleepingBag()
    EABR.FvStandDown(EABR._fvSleepStartedAt ~= nil)
    -- With no timer the rested branch has already hidden the reminders, and the
    -- anchor is left as it is: it holds the secure reminder buttons, so its
    -- mouse cannot change in combat (SetElementVisibility calls EnableMouse).
    -- A timer never runs in combat (SyncSleepProgress ends it there).
    if not EABR._fvSleepStartedAt or InCombat() then return end

    local entry
    if not _dismissedUntilLoad["forever:sleepingbag"] then
        ResetEntryPool()
        entry = CollectSleepingBag(0, true, EllesmereUI.AuraKit.AurasRestricted())
        if entry then
            ShowIcon(1, entry)
            LayoutIcons()
        end
    end
    EllesmereUI.SetElementVisibility(iconAnchor, entry ~= nil)
    UpdateDurationTicker()
end

local function Refresh()
    SetCachedOutline(nil)
    EABR._nextDurationRefreshTime = nil
    if not db then return end
    -- Pooled reminder buttons are children of iconAnchor, built in OnEnable (PLAYER_LOGIN). File-scope events (SPELLS_CHANGED, PLAYER_TALENT_UPDATE,
    -- TRAIT_CONFIG_UPDATED, ...) can fire DURING loading before OnEnable runs; a reminder created then via GetOrCreateIcon gets a nil parent and renders oversized forever (scale 1.0, not UIParent scale -- pooled buttons are never re-parented). Wait for the anchor; OnEnable fires its own refresh.
    if not iconAnchor then return end
    if EABR._fvSleepProfile and EABR._fvSleepProfile ~= db.profile then
        EABR.ClearSleepProgress()
    end
    if EABR.FOREVER then SyncSleepProgress() end
    -- WoW Forever: the returns below show nothing, so the Raid Buffs group
    -- watch and the tracking event stand down with them (EABR.FvStandDown);
    -- the event that ends each state (panel close, vehicle exit, alive, rest
    -- ended) refreshes and re-arms them.
    if euiPanelOpen then
        HideCombatIcons(); HideAllIcons()
        if EABR.FOREVER then
            EABR.FvStandDown(EABR._fvSleepStartedAt ~= nil)
        end
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

    -- Suppress normal reminders while dead or in a rested area.
    if UnitIsDeadOrGhost("player") then
        HideCombatIcons(); HideCursorIcons(); HideAllIcons()
        if EABR.FOREVER then EABR.FvStandDown() end
        return
    end
    if IsResting() or (EABR.FOREVER and EABR._fvSleepStartedAt) then
        HideCombatIcons(); HideCursorIcons()
        if InCombat() then FadeOutSecureIcons() else HideAllIcons() end
        if EABR.FOREVER then RefreshRestedSleepingBag() end
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

    -- WoW Forever: its Raid Buffs, Self Buffs and Consumables sections stand in for
    -- the four collectors below (reminders off: their watch and event stand down).
    if EABR.FOREVER then
        if remindersOn then
            EABR.CollectForeverRaidBuffs(missing, playerClass, inInstance)
            local first = #missing + 1
            EABR.CollectForever(missing, inInstance, inPvP, playerClass)
            EABR.FvSelfFirst(missing, first)
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
                    if m.cat == "raidbuff" and m.mode == "spell" and not m.fvExtra and not useCursor
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
                        if f and not m.isEating and not m.hunterTrackingStatus then
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
                if m.cat == "raidbuff" and m.mode == "spell" and not m.fvExtra and not useCursor then
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
            -- A stronger buff of the same stat changes the answer too.
            if fam.stronger then
                for id in pairs(fam.stronger) do W.ids[id] = true end
            end
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
