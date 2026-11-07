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
-------------------------------------------------------------------------------
local _, module = ...

local MAX_ACTION_SLOT = 180
local PLAYER, PET = Enum.SpellBookSpellBank.Player, Enum.SpellBookSpellBank.Pet

-- Settings live in EllesmereUIDB.spellUprank (known: the highest ranks seen); unset keys read these.
local F = module.Feature("spellUprank", { enabled = false })

local events
local booted -- the login apply has run
local pending = { player = {}, pet = {} } -- spell names to uprank once out of combat with an empty cursor

local function Plain(v, kind)
    if not issecretvalue(v) and type(v) == (kind or "number") then return v end
end

-------------------------------------------------------------------------------
--  Spellbooks: the highest rank per spell name
-------------------------------------------------------------------------------
local function PlayerTop()
    local top = {}
    for line = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do
        local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if li and not li.offSpecID then
            for slot = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                if C_SpellBook.GetSpellBookItemType(slot, PLAYER) == Enum.SpellBookItemType.Spell
                   and not C_SpellBook.IsSpellBookItemPassive(slot, PLAYER)
                   and not C_SpellBook.IsSpellBookItemLowRank(slot, PLAYER) then
                    local info = C_SpellBook.GetSpellBookItemInfo(slot, PLAYER)
                    if info and info.spellID and info.name then top[info.name] = info.spellID end
                end
            end
        end
    end
    return top
end

-- The pet's highest rank per name, and the spellbook slot of every rank it knows.
local function PetTop()
    local n = C_SpellBook.HasPetSpells()
    if not n or n == 0 then return nil end
    local top, slots = {}, {}
    for slot = 1, n do
        -- Pet spells are PetAction items; the stances and commands among them carry no spell ID.
        local info = C_SpellBook.GetSpellBookItemInfo(slot, PET)
        if info and info.spellID and info.name and not info.isPassive then
            slots[info.spellID] = slot
            if not C_SpellBook.IsSpellBookItemLowRank(slot, PET) then top[info.name] = info.spellID end
        end
    end
    return top, slots
end

-- Family and name: a hunter's two cats stay apart, a warlock's demon keeps its own.
local function PetKey()
    local family, name = Plain(UnitCreatureFamily("pet"), "string"), Plain(UnitName("pet"), "string")
    if name == UNKNOWNOBJECT then return end -- the name loads a moment after the pet
    return family and name and (family .. ":" .. name)
end

local function Known()
    local cfg = F.Cfg()
    cfg.known = cfg.known or {}
    local key = EllesmereUI.CharKey(" - ", cfg.known) or UnitName("player") or "?"
    local mine = cfg.known[key] or {}
    cfg.known[key] = mine
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

-------------------------------------------------------------------------------
--  Swapping
-------------------------------------------------------------------------------
local function Report(counts)
    for id, count in pairs(counts) do
        local name = C_Spell.GetSpellName(id)
        local rank = C_Spell.GetSpellSubtext(id)
        local spell = (C_Spell.GetSpellLink(id) or name or "?") .. (rank and rank ~= "" and " (" .. rank .. ")" or "")
        local msg = count == 1 and EllesmereUI.Lf("Upranked %s on 1 action slot.", spell)
            or EllesmereUI.Lf("Upranked %1$s on %2$d action slots.", spell, count)
        EllesmereUI.Print(EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI:|r " .. msg)
    end
end

-- A pet keeps only its highest rank, so any other rank of its spell is an old one.
local function UprankPending()
    local playerTop = PlayerTop()
    local petTop, petSlots = PetTop()
    petTop, petSlots = petTop or {}, petSlots or {}
    local counts = {}
    local function Count(id) counts[id] = (counts[id] or 0) + 1 end

    for action = 1, MAX_ACTION_SLOT do
        local kind, id = GetActionInfo(action)
        id = kind == "spell" and Plain(id)
        local name = id and C_Spell.GetSpellName(id)
        if name then
            local petNew = pending.pet[name] and petTop[name]
            local playerNew = pending.player[name] and playerTop[name]
            if petNew and petNew ~= id and not IsPlayerSpell(id) then
                C_SpellBook.PickupSpellBookItem(petSlots[petNew], PET)
                PlaceAction(action)
                ClearCursor()
                Count(petNew)
            elseif playerNew and playerNew ~= id and IsPlayerSpell(id) then
                C_Spell.PickupSpell(playerNew)
                PlaceAction(action)
                ClearCursor()
                Count(playerNew)
            end
        end
    end

    pending = { player = {}, pet = {} }
    Report(counts)
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
--  Checks, straight from the events: a repeated event finds nothing new and costs a spellbook read
-------------------------------------------------------------------------------
local function Check(player, pet)
    local known = Known()
    if player then Diff(PlayerTop(), known.player, pending.player) end
    local key = pet and PetKey()
    local petTop = key and PetTop()
    if petTop then
        known.pets[key] = known.pets[key] or {}
        Diff(petTop, known.pets[key], pending.pet)
    end
    Flush()
end

local function OnEvent(_, event)
    if event == "CURSOR_CHANGED" then
        Flush()
    elseif event == "PET_BAR_UPDATE" or event == "UNIT_PET" then
        Check(false, true)
    else
        -- LEARNED_SPELL_IN_SKILL_LINE, SPELLS_CHANGED (a pet learning a rank fires only this)
        Check(true, true)
    end
end

local function Apply()
    if events then events:UnregisterAllEvents() end
    local login = not booted
    booted = true
    if not F.Enabled() then
        pending = { player = {}, pet = {} }
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
    -- At login the spellbook is not ready yet; the SPELLS_CHANGED that follows does the first check.
    if not login then Check(true, true) end
end

-- Options-page entry points.
EllesmereUI._SpellUprank = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
