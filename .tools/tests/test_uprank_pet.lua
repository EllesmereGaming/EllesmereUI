-- Stub harness: Forever Essentials' Auto Uprank Spells on Bars
-- (EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_Uprank.lua): the
-- player's and the pet's new ranks on the action bars, the rank memory per
-- character and pet, the combat and cursor waits, and the cost rules: one check
-- per frame, the player's whole spellbook read only at the first check after
-- login and when the option is turned on, no timers, no deprecated globals.
--   lua .tools/tests/test_uprank_pet.lua        (from the repository root)
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
issecretvalue = function() return false end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 }, SpellBookItemType = { Spell = 1 } }
UNKNOWNOBJECT = "Unknown"
EllesmereUIDB = {}

-- Frames: the module makes an event frame and a hidden one-frame flusher
local frames = {}
CreateFrame = function()
    local f = { scripts = {}, events = {}, shown = true }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:RegisterUnitEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:UnregisterAllEvents() wipe(self.events) end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    frames[#frames + 1] = f
    return f
end
local function EventFrame()
    for _, f in ipairs(frames) do if f.scripts.OnEvent then return f end end
end
local function Flusher()
    for _, f in ipairs(frames) do if f.scripts.OnUpdate then return f end end
end
-- A frame passes: a shown flusher runs its one check
local function NextFrame()
    local fl = Flusher()
    if fl and fl.shown then fl.scripts.OnUpdate(fl, 0.016) end
end
local function Fire(e, ...)
    local ef = EventFrame()
    assert(ef and ef.events[e], e .. " is not registered")
    ef.scripts.OnEvent(ef, e, ...)
end

local combat, cursor = false, nil
InCombatLockdown = function() return combat end
GetCursorInfo = function() return cursor end
UnitName = function(u) return u == "pet" and "Fizzbang" or "Direktsaft" end
UnitCreatureFamily = function() return "Imp" end
UnitGUID = function(u) assert(u == "player"); return "Player-1" end
local printed, queued = {}, {}
local cfg = { enabled = true }
EllesmereUI = { IS_FOREVER = true, COLOR_CODES = { BRAND = "" },
    Lf = function(s, ...) return (s:gsub("%%(%d)%$", "%%")):format(...) end,
    Print = function(s) printed[#printed + 1] = s end,
    CombatQueue = { Defer = function(key, fn) queued[key] = fn end } }
local module = { Feature = function(_, defaults)
    return { Get = function(k) if cfg[k] == nil then return defaults[k] end return cfg[k] end,
        Cfg = function() return cfg end, Enabled = function() return cfg.enabled end,
        Start = function(apply) apply() end }
end }

-- Spells: Shadow Bolt 686 / 695 / 705 / 1088 (player), Firebolt 3110 / 7799 / 7800 / 7801 (imp).
local NAMES = { [686] = "Shadow Bolt", [695] = "Shadow Bolt", [705] = "Shadow Bolt", [1088] = "Shadow Bolt",
    [3110] = "Firebolt", [7799] = "Firebolt", [7800] = "Firebolt", [7801] = "Firebolt", [9999] = "Fear" }
local player = { 686, 695 }
local pet = { 7799 } -- a Forever pet keeps only its highest rank
local function Book(bank) return bank == 1 and pet or player end
local function Top(list, slot)
    for i = slot + 1, #list do if NAMES[list[i]] == NAMES[list[slot]] then return false end end
    return true
end
local playerReads = 0 -- whole reads of the player's spellbook
C_SpellBook = {
    GetNumSpellBookSkillLines = function() playerReads = playerReads + 1; return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #player } end,
    GetSpellBookItemType = function(_, bank) return bank == 1 and 3 or 1 end, -- the pet's are PetAction
    IsSpellBookItemPassive = function() return false end,
    IsSpellBookItemLowRank = function(slot, bank) return not Top(Book(bank), slot) end,
    GetSpellBookItemInfo = function(slot, bank)
        local id = Book(bank)[slot]
        return id and { spellID = id, name = NAMES[id], itemType = bank == 1 and 3 or 1, isPassive = false }
    end,
    HasPetSpells = function() return #pet > 0 and #pet or nil end,
    FindSpellBookSlotForSpell = function(id)
        for i, s in ipairs(player) do if s == id then return i, 0 end end
    end,
    IsSpellKnown = function(id, bank)
        assert(bank == nil or bank == 0, "asked about another bank than the player's")
        for _, s in ipairs(player) do if s == id then return true end end
        return false
    end,
}
local held
C_SpellBook.PickupSpellBookItem = function(slot, bank) held = Book(bank)[slot] end
C_Spell = { GetSpellName = function(id) return NAMES[id] end, GetSpellSubtext = function() return "" end,
    GetSpellLink = function(id) return NAMES[id] end, PickupSpell = function(id) held = id end }
local bars, petBar = {}, {}
GetActionInfo = function(a) if bars[a] then return "spell", bars[a] end end
PlaceAction = function(a) bars[a] = held end
ClearCursor = function() held = nil end
PickupPetAction = function(i) petBar[i] = held end

bars[1], bars[2], bars[3] = 686, 3110, 686
petBar[1], petBar[2] = 3110, 3110
assert(loadfile("EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_Uprank.lua"))("test", module)
assert(IsPlayerSpell == nil and IsSpellKnown == nil, "the deprecated spell globals exist here")

-- 1. login: nothing is read before the spellbook is ready; the first SPELLS_CHANGED reads it whole once,
--    however many events the frame brings
assert(playerReads == 0 and bars[1] == 686 and not Flusher(), "something was read at login")
Fire("SPELLS_CHANGED")
Fire("SPELLS_CHANGED")
Fire("PET_BAR_UPDATE")
Fire("SPELLS_CHANGED")
assert(bars[1] == 686, "a check ran inside the event, not on the next frame")
NextFrame()
assert(playerReads == 2, "one check for the burst: one read to find the ranks, one to swap them (got " .. playerReads .. ")")
assert(bars[1] == 695 and bars[3] == 695, "a character's first check upranks the player's spells")
assert(bars[2] == 7799, "and the pet's, from the pet spellbook")
assert(petBar[1] == 3110, "the pet bar is left to the game")
assert(not Flusher().shown, "the flusher stays shown")

-- 2. later SPELLS_CHANGED read the pet's spellbook only; a lower rank placed on purpose stays
bars[1] = 686
local reads = playerReads
Fire("SPELLS_CHANGED")
NextFrame()
assert(playerReads == reads, "a later SPELLS_CHANGED read the player's whole spellbook")
assert(bars[1] == 686, "a lower rank placed on purpose later stays")

-- 3. a pet rank learned in combat waits for the combat queue
pet[1] = 7800
combat = true
Fire("SPELLS_CHANGED")
NextFrame()
assert(bars[2] == 7799, "something was placed in combat")
combat = false
assert(queued.SpellUprank, "the swap does not wait in the combat queue")
local after = queued.SpellUprank
queued.SpellUprank = nil
after()
assert(bars[2] == 7800, "the pet's new rank did not land once combat ended")
assert(bars[1] == 686, "a spell whose rank did not go up was touched")

-- 4. a player rank learned: just that spell is checked; the swap waits for an empty cursor
player[#player + 1] = 705
cursor = "spell"
reads = playerReads
Fire("LEARNED_SPELL_IN_SKILL_LINE", 705)
NextFrame()
assert(playerReads == reads, "a learned spell read the player's whole spellbook")
assert(bars[1] == 686, "something was placed while the cursor held something")
cursor = nil
Fire("CURSOR_CHANGED")
assert(bars[1] == 705 and bars[3] == 705, "a newly learned rank did not replace every lower one")

-- 5. a learned spell not in the spellbook yet: the check reads the whole book instead
reads = playerReads
Fire("LEARNED_SPELL_IN_SKILL_LINE", 9999)
NextFrame()
assert(playerReads == reads + 1, "a learned spell missing from the spellbook was not read whole")

-- 6. the memory: per character by GUID and per pet, outside the settings
local mine = EllesmereUIDB.spellUprankChars and EllesmereUIDB.spellUprankChars["Player-1"]
assert(mine and mine.player["Shadow Bolt"] == 705 and mine.pets["Imp:Fizzbang"].Firebolt == 7800,
    "the highest ranks are not remembered per character and pet")
assert(cfg.known == nil, "the memory went into the settings")
assert(#printed > 0, "nothing was reported in chat")

-- 7. summoning a pet checks it on the next frame
pet[1] = 7801
Fire("UNIT_PET", "player")
NextFrame()
assert(bars[2] == 7801, "summoning a pet did not check it")

-- 8. off: nothing is registered and nothing runs; a rank learned meanwhile is caught when it is turned on
cfg.enabled = false
EllesmereUI._SpellUprank.Apply()
assert(next(EventFrame().events) == nil and not Flusher().shown, "the option off left something running")
player[#player + 1] = 1088
bars[1] = 705
cfg.enabled = true
EllesmereUI._SpellUprank.Apply()
assert(bars[1] == 705, "turning it on swapped inside the click, not on the next frame")
NextFrame()
assert(bars[1] == 1088, "a rank learned while the option was off was not caught when it was turned on")

assert(#timers == 0, "a timer was used")
print("uprank pet spells OK")
