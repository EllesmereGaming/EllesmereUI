-- Run from the repository root: lua .tools/tests/test_uprank_pet.lua
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end
issecretvalue = function() return false end
Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 }, SpellBookItemType = { Spell = 1 } }
NUM_PET_ACTION_SLOTS = 10
local frame = { RegisterEvent = function() end, UnregisterEvent = function() end,
    UnregisterAllEvents = function() end, RegisterUnitEvent = function() end }
function frame:SetScript(_, fn) self.handler = fn end
CreateFrame = function() return frame end
local combat, cursor = false, nil
InCombatLockdown = function() return combat end
GetCursorInfo = function() return cursor end
UnitName = function(u) return u == "pet" and "Fizzbang" or "Direktsaft Traube" end
UnitCreatureFamily = function() return "Imp" end
local printed, queued = {}, {}
local cfg = { enabled = true }
EllesmereUI = { IS_FOREVER = true, COLOR_CODES = { BRAND = "" },
    Lf = function(s, ...) return (s:gsub("%%(%d)%$", "%%")):format(...) end, Print = function(s) printed[#printed + 1] = s end,
    CharKey = function(sep) return "Direktsaft Traube" .. sep .. "Forever" end,
    CombatQueue = { Defer = function(key, fn) queued[key] = fn end } }
local module = { Feature = function(_, defaults)
    return { Get = function(k) if cfg[k] == nil then return defaults[k] end return cfg[k] end,
        Cfg = function() return cfg end, Enabled = function() return cfg.enabled end,
        Start = function(apply) apply() end }
end }

-- Spells: Shadow Bolt 686/695/705 (player), Firebolt 3110/7799/7800 (imp).
local NAMES = { [686] = "Shadow Bolt", [695] = "Shadow Bolt", [705] = "Shadow Bolt",
    [3110] = "Firebolt", [7799] = "Firebolt", [7800] = "Firebolt", [7801] = "Firebolt" }
local player = { 686, 695 }
local pet = { 7799 } -- a Forever pet keeps only its highest rank
local function Book(bank) return bank == 1 and pet or player end
local function Top(list, slot)
    for i = slot + 1, #list do if NAMES[list[i]] == NAMES[list[slot]] then return false end end
    return true
end
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #player } end,
    GetSpellBookItemType = function(_, bank) return bank == 1 and 3 or 1 end, -- the pet's are PetAction
    IsSpellBookItemPassive = function() return false end,
    IsSpellBookItemLowRank = function(slot, bank) return not Top(Book(bank), slot) end,
    GetSpellBookItemInfo = function(slot, bank)
        local id = Book(bank)[slot]
        return id and { spellID = id, name = NAMES[id], itemType = bank == 1 and 3 or 1, isPassive = false }
    end,
    HasPetSpells = function() return #pet > 0 and #pet or nil end,
}
local held
C_SpellBook.PickupSpellBookItem = function(slot, bank) held = Book(bank)[slot] end
C_Spell = { GetSpellName = function(id) return NAMES[id] end, GetSpellSubtext = function() return "" end,
    GetSpellLink = function(id) return NAMES[id] end, PickupSpell = function(id) held = id end }
IsPlayerSpell = function(id) for _, s in ipairs(player) do if s == id then return true end end return false end
local bars, petBar, autocast = {}, {}, { [3110] = true }
GetActionInfo = function(a) if bars[a] then return "spell", bars[a] end end
PlaceAction = function(a) bars[a] = held end
ClearCursor = function() held = nil end
GetPetActionInfo = function(i)
    local id = petBar[i]
    if id then return NAMES[id], nil, false, false, true, autocast[id] == true, id end
end
PickupPetAction = function(i) petBar[i] = held end
local toggled = {}
C_SpellBook.ToggleSpellBookItemAutoCast = function(slot, bank)
    local id = Book(bank)[slot]
    autocast[id] = not autocast[id]
    toggled[#toggled + 1] = id
end

bars[1], bars[2], bars[3] = 686, 3110, 686
petBar[1], petBar[2] = 3110, 3110
assert(loadfile("EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_Uprank.lua"))("test", module)
local fire = function(e) frame.handler(frame, e) end
assert(#timers == 0 and bars[1] == 686, "nothing at login before the spellbook is ready, and no timers")
fire("SPELLS_CHANGED")
assert(bars[1] == 695 and bars[3] == 695, "a character's first check upranks the player's spells")
assert(bars[2] == 7799, "and the pet's, from the pet spellbook")
assert(petBar[1] == 3110 and #toggled == 0, "the pet bar is left to the game")

bars[1] = 686
fire("SPELLS_CHANGED")
assert(bars[1] == 686, "a lower rank placed on purpose later stays")

pet[1] = 7800
combat = true
fire("SPELLS_CHANGED")
assert(bars[2] == 7799, "nothing is placed in combat")
combat = false
assert(queued.SpellUprank, "the swap waits in the combat queue")
local after = queued.SpellUprank
queued.SpellUprank = nil
after()
assert(bars[2] == 7800, "the pet's new rank lands once combat ends")
assert(bars[1] == 686, "only the spell that went up is touched")

player[#player + 1] = 705
cursor = "spell"
fire("LEARNED_SPELL_IN_SKILL_LINE")
assert(bars[1] == 686, "nothing is placed while the cursor holds something")
cursor = nil
fire("CURSOR_CHANGED")
assert(bars[1] == 705 and bars[3] == 705, "a newly learned rank replaces every lower one")

local known = cfg.known["Direktsaft Traube - Forever"]
assert(known.player["Shadow Bolt"] == 705 and known.pets["Imp:Fizzbang"].Firebolt == 7800, "remembered per character and pet")
assert(#printed > 0, "reported in chat")
pet[1] = 7801
fire("UNIT_PET")
assert(bars[2] == 7801, "summoning a pet checks it at once")
assert(#timers == 0, "no timers at any point")
print("uprank pet spells OK")
