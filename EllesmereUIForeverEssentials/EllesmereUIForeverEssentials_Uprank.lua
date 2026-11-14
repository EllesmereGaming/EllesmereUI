if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_Uprank.lua  (WoW Forever only)
--  When you or your pet get a higher rank of a spell, swaps every lower rank
--  of that spell on the action bars for the new one and reports it in chat
--  (the pet bar follows the pet's spellbook by itself). The highest rank of
--  each spell is remembered per character and per pet, so a rank learned
--  while the option was off or the pet was away is caught at the next check.
--  A character's first check upranks everything; after that a lower rank
--  placed on purpose stays.
--
--  Cost: nothing while off. While on, every event only marks what to read and
--  one check per frame reads it: the player's whole spellbook at the first
--  check after login and when the option is turned on, otherwise just the
--  spells LEARNED_SPELL_IN_SKILL_LINE names; the pet's spellbook (a few slots)
--  on SPELLS_CHANGED (the only event a pet learning a rank fires), UNIT_PET and
--  PET_BAR_UPDATE. The 180 action slots are walked only when a rank went up.
-------------------------------------------------------------------------------
local _, module = ...

local MAX_ACTION_SLOT = 180
local PLAYER, PET = Enum.SpellBookSpellBank.Player, Enum.SpellBookSpellBank.Pet

-- Settings live in EllesmereUIDB.spellUprank; unset keys read these.
local F = module.Feature("spellUprank", { enabled = false })

local events, flusher
local booted        -- the login apply has run
local firstScan     -- the first SPELLS_CHANGED after login reads the player's spellbook whole
local wantPlayer, wantPet = false, false  -- what the next check reads
local learned = {}  -- spell IDs learned since the last check
local pending = { player = {}, pet = {} } -- spell names to uprank once out of combat with an empty cursor
-- Read tables, reused by every read
local playerTop, petTop, petSlots, counts = {}, {}, {}, {}

local function Plain(v, kind)
    if not issecretvalue(v) and type(v) == (kind or "number") then return v end
end

-------------------------------------------------------------------------------
--  Spellbooks: the highest rank per spell name
-------------------------------------------------------------------------------
local function ReadPlayerTop()
    wipe(playerTop)
    for line = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do
        local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if li and not li.offSpecID then
            for slot = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                if C_SpellBook.GetSpellBookItemType(slot, PLAYER) == Enum.SpellBookItemType.Spell
                   and not C_SpellBook.IsSpellBookItemPassive(slot, PLAYER)
                   and not C_SpellBook.IsSpellBookItemLowRank(slot, PLAYER) then
                    local info = C_SpellBook.GetSpellBookItemInfo(slot, PLAYER)
                    if info and info.spellID and info.name then playerTop[info.name] = info.spellID end
                end
            end
        end
    end
    return playerTop
end

-- The pet's highest rank per name, and the spellbook slot of every rank it
-- knows; false when the pet has no spells (none out, or not loaded yet).
local function ReadPetTop()
    wipe(petTop)
    wipe(petSlots)
    local n = C_SpellBook.HasPetSpells()
    if not n or n == 0 then return false end
    for slot = 1, n do
        -- Pet spells are PetAction items; the stances and commands among them carry no spell ID.
        local info = C_SpellBook.GetSpellBookItemInfo(slot, PET)
        if info and info.spellID and info.name and not info.isPassive then
            petSlots[info.spellID] = slot
            if not C_SpellBook.IsSpellBookItemLowRank(slot, PET) then petTop[info.name] = info.spellID end
        end
    end
    return true
end

-- Family and name: a hunter's two cats stay apart, a warlock's demon keeps its own.
local function PetKey()
    local family, name = Plain(UnitCreatureFamily("pet"), "string"), Plain(UnitName("pet"), "string")
    if name == UNKNOWNOBJECT then return end -- the name loads a moment after the pet
    return family and name and (family .. ":" .. name)
end

-- The highest ranks seen, per character (the roster's spellUprank) and per
-- pet: account data outside the settings, never exported.
local function Known()
    local mine = EllesmereUI.CharData("spellUprank", true)
    if not mine then return { player = {}, pets = {} } end -- GUID unread: a throwaway
    mine.player = mine.player or {}
    mine.pets = mine.pets or {}
    return mine
end

-- Marks every name whose highest rank is not the remembered one, then remembers it.
local function Diff(now, was, into)
    for name, id in pairs(now) do
        if was[name] ~= id then
            into[name] = true
            was[name] = id
        end
    end
end

-- The spells learned since the last check, each on its own; false when one is
-- not in the spellbook yet, so the check reads the whole book instead.
local function ProbeLearned(known)
    for id in pairs(learned) do
        local name = C_Spell.GetSpellName(id)
        local slot, bank = C_SpellBook.FindSpellBookSlotForSpell(id)
        if not (name and slot) then return false end
        if bank == PLAYER and not C_SpellBook.IsSpellBookItemPassive(slot, PLAYER)
           and not C_SpellBook.IsSpellBookItemLowRank(slot, PLAYER) and known.player[name] ~= id then
            known.player[name] = id
            pending.player[name] = true
        end
    end
    return true
end

-------------------------------------------------------------------------------
--  Swapping
-------------------------------------------------------------------------------
local function Report()
    for id, count in pairs(counts) do
        local name = C_Spell.GetSpellName(id)
        local rank = C_Spell.GetSpellSubtext(id)
        local spell = (C_Spell.GetSpellLink(id) or name or "?") .. (rank and rank ~= "" and " (" .. rank .. ")" or "")
        local msg = count == 1 and EllesmereUI.Lf("Upranked %s on 1 action slot.", spell)
            or EllesmereUI.Lf("Upranked %1$s on %2$d action slots.", spell, count)
        EllesmereUI.Print(EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI:|r " .. msg)
    end
end

-- A pet keeps only its highest rank, so any other rank of its spell is an old
-- one. A bar spell the player knows is the player's (a lower rank still reads
-- known); a pet spell reads unknown.
local function UprankPending()
    local hasPlayer = next(pending.player) ~= nil
    local hasPet = next(pending.pet) ~= nil and ReadPetTop()
    if hasPlayer then ReadPlayerTop() end
    wipe(counts)

    for action = 1, MAX_ACTION_SLOT do
        local kind, id = GetActionInfo(action)
        id = kind == "spell" and Plain(id)
        local name = id and C_Spell.GetSpellName(id)
        if name then
            local petNew = hasPet and pending.pet[name] and petTop[name]
            local playerNew = hasPlayer and pending.player[name] and playerTop[name]
            if petNew and petNew ~= id and not C_SpellBook.IsSpellKnown(id) then
                C_SpellBook.PickupSpellBookItem(petSlots[petNew], PET)
                PlaceAction(action)
                ClearCursor()
                counts[petNew] = (counts[petNew] or 0) + 1
            elseif playerNew and playerNew ~= id and C_SpellBook.IsSpellKnown(id) then
                C_Spell.PickupSpell(playerNew)
                PlaceAction(action)
                ClearCursor()
                counts[playerNew] = (counts[playerNew] or 0) + 1
            end
        end
    end

    wipe(pending.player)
    wipe(pending.pet)
    Report()
end

-- Placing actions needs no combat and an empty cursor; waits for both.
local function Flush()
    if not (next(pending.player) or next(pending.pet)) then return end
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer("SpellUprank", Flush)
        return
    end
    if GetCursorInfo() then
        events:RegisterEvent("CURSOR_CHANGED")
        return
    end
    events:UnregisterEvent("CURSOR_CHANGED")
    UprankPending()
end

-------------------------------------------------------------------------------
--  Checks: one per frame, reading only what the events asked for
-------------------------------------------------------------------------------
local function Check()
    flusher:Hide()
    local known = Known()
    if next(learned) then
        if not wantPlayer and not ProbeLearned(known) then wantPlayer = true end
        wipe(learned)
    end
    if wantPlayer then Diff(ReadPlayerTop(), known.player, pending.player) end
    if wantPet then
        local key = PetKey()
        if key and ReadPetTop() then
            local was = known.pets[key]
            if not was then
                was = {}
                known.pets[key] = was
            end
            Diff(petTop, was, pending.pet)
        end
    end
    wantPlayer, wantPet = false, false
    Flush()
end

-- The next frame runs one check for every event of this one.
local function Queue()
    if not flusher then
        flusher = CreateFrame("Frame")
        flusher:Hide()
        flusher:SetScript("OnUpdate", Check)
    end
    flusher:Show()
end

local function OnEvent(_, event, spellID)
    if event == "CURSOR_CHANGED" then
        Flush()
        return
    end
    if event == "LEARNED_SPELL_IN_SKILL_LINE" then
        spellID = Plain(spellID)
        if not spellID then return end
        learned[spellID] = true
    elseif event == "SPELLS_CHANGED" then
        if firstScan then
            firstScan = false
            wantPlayer = true
        end
        wantPet = true
    else
        -- UNIT_PET, PET_BAR_UPDATE: the pet came, went or filled its bar
        wantPet = true
    end
    Queue()
end

local function Apply()
    if events then events:UnregisterAllEvents() end
    if flusher then flusher:Hide() end
    local login = not booted
    booted = true
    wipe(learned)
    wantPlayer, wantPet, firstScan = false, false, false
    if not F.Enabled() then
        wipe(pending.player)
        wipe(pending.pet)
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    events:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
    events:RegisterEvent("SPELLS_CHANGED")
    events:RegisterEvent("PET_BAR_UPDATE")
    events:RegisterUnitEvent("UNIT_PET", "player")
    if login then
        -- At login the spellbook is not ready yet: the SPELLS_CHANGED that follows reads it.
        firstScan = true
    else
        wantPlayer, wantPet = true, true
        Queue()
    end
end

-- Options-page entry points.
EllesmereUI._SpellUprank = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
