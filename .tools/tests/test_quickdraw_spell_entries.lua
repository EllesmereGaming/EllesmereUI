-- Stub harness: the Quickdraw options' Spells list (SpellEntries in
-- EUI_Quickdraw_Options.lua), cut out of the real file and run over a stubbed
-- spellbook on both clients. A flyout's known spells are offered as plain
-- entries with their own icon; C_Spell.GetSpellTexture returns two icon IDs,
-- and the second must never reach Add's rank parameter (website bug #189: the
-- list stopped with a Lua error). WoW Forever's rank rows stay as they are.
--   lua .tools/tests/test_quickdraw_spell_entries.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local SRC = ReadSource("EllesmereUIOptions/EUI_Quickdraw_Options.lua")
local s0 = assert(SRC:find("    local function SpellEntries()", 1, true), "SpellEntries missing")
local s1 = assert(SRC:find("\n    end\n", s0, true), "end of SpellEntries missing")
local FUNC = SRC:sub(s0, s1 + 8)

local FLYOUT = { { 701, true, "Portal: Stormwind" }, { 702, false, "Portal: Darnassus" }, { 703, true, "Portal: Ironforge" } }

-- One client's spellbook: a ranked spell on WoW Forever (top rank and one
-- lower rank), a plain spell on retail, a passive, and a flyout of portals.
local function Book(forever)
    local items = {}
    if forever then
        items[#items + 1] = { actionID = 100, name = "Frostbolt", iconID = 1001, subName = "Rank 2" }
        items[#items + 1] = { actionID = 99, name = "Frostbolt", iconID = 1001, subName = "Rank 1", lowRank = true }
    else
        items[#items + 1] = { actionID = 100, name = "Frostbolt", iconID = 1001, subName = "" }
    end
    items[#items + 1] = { actionID = 200, name = "Frost Armor", iconID = 2001, subName = "", isPassive = true }
    items[#items + 1] = { actionID = 500, name = "Portals", iconID = 5001, flyout = true }
    return items
end

local function Load(fn, forever)
    local items = Book(forever)
    local Enum = {
        SpellBookSpellBank = { Player = 0 },
        SpellBookItemType = { Spell = 1, Flyout = 2, FutureSpell = 3 },
    }
    local C_SpellBook = {
        GetNumSpellBookSkillLines = function() return 1 end,
        GetSpellBookSkillLineInfo = function(line)
            assert(line == 1)
            return { itemIndexOffset = 0, numSpellBookItems = #items, shouldHide = false }
        end,
        GetSpellBookItemInfo = function(i, bank)
            assert(bank == 0, "the Player bank")
            local it = items[i]
            return { actionID = it.actionID, name = it.name, iconID = it.iconID, subName = it.subName,
                     isPassive = it.isPassive, isOffSpec = false,
                     itemType = it.flyout and Enum.SpellBookItemType.Flyout or Enum.SpellBookItemType.Spell }
        end,
        IsSpellBookItemLowRank = function(i) return items[i].lowRank == true end,
    }
    local C_Spell = {
        GetSpellSubtext = function() return nil end,
        -- iconID, originalIconID (both always set), conditionalIconID (optional).
        GetSpellTexture = function(id) return id * 10, id * 10 + 1 end,
    }
    local function GetFlyoutInfo(id)
        assert(id == 500, "the flyout's own id")
        return "Portals", "", #FLYOUT, true
    end
    local function GetFlyoutSlotInfo(id, slot)
        assert(id == 500)
        local s = FLYOUT[slot]
        return s[1], s[1], s[2], s[3], 0
    end
    local ns = { HasRezKit = function() return false end }
    local EllesmereUI = { IS_FOREVER = forever }
    local chunk = assert(loadstring(
        "local ns, EllesmereUI, Enum, C_SpellBook, C_Spell, GetFlyoutInfo, GetFlyoutSlotInfo = ...\n"
        .. fn .. "\nreturn SpellEntries\n", "=SpellEntries"))
    return chunk(ns, EllesmereUI, Enum, C_SpellBook, C_Spell, GetFlyoutInfo, GetFlyoutSlotInfo)
end

local function Find(out, name)
    for _, e in ipairs(out) do if e.name == name then return e end end
end

local function Run(fn, forever)
    local ok, out = pcall(Load(fn, forever))
    assert(ok, (forever and "WoW Forever" or "retail") .. ": the Spells list raised: " .. tostring(out))
    return out
end

for _, forever in ipairs({ false, true }) do
    local label = forever and "WoW Forever" or "retail"
    local out = Run(FUNC, forever)

    -- The flyout's known spells, plain, with the first icon; the unknown one left out.
    for _, s in ipairs(FLYOUT) do
        local e = Find(out, s[3])
        if s[2] then
            assert(e, label .. ": " .. s[3] .. " missing")
            assert(e.icon == s[1] * 10, label .. ": " .. s[3] .. " takes icon " .. tostring(e.icon))
            assert(e.slot.kind == "spell" and e.slot.id == s[1], label .. ": " .. s[3] .. " slot")
            assert(not e.slot.rankPinned and e.sortName == nil and e.rankNum == nil,
                label .. ": " .. s[3] .. " was made a rank row")
        else
            assert(not e, label .. ": the unknown " .. s[3] .. " is offered")
        end
    end
    for _, e in ipairs(out) do
        assert(not e.name:find("%(%d+%)$"), label .. ": an entry named with an icon number: " .. e.name)
    end
    assert(not Find(out, "Frost Armor"), label .. ": a passive is offered")

    local plain = Find(out, "Frostbolt")
    assert(plain and plain.slot.id == 100 and not plain.slot.rankPinned, label .. ": the spell's own row")
    if forever then
        local r1, r2 = Find(out, "Frostbolt (Rank 1)"), Find(out, "Frostbolt (Rank 2)")
        assert(r1 and r1.slot.id == 99 and r1.slot.rankPinned and r1.rankNum == 1 and r1.sortName == "Frostbolt",
            "WoW Forever: the lower rank's row")
        assert(r2 and r2.slot.id == 100 and r2.slot.rankPinned and r2.rankNum == 2, "WoW Forever: the top rank's row")
        assert(#out == 5, "WoW Forever: " .. #out .. " entries")
    else
        for _, e in ipairs(out) do assert(not e.slot.rankPinned, "retail: a rank row " .. e.name) end
        assert(#out == 3, "retail: " .. #out .. " entries")
    end
end

-- Mutant: the flyout spell's icon passed without the parentheses.
do
    local from = "Add(spellID, spellName, (C_Spell.GetSpellTexture(spellID)))"
    local a, b = FUNC:find(from, 1, true)
    assert(a, "the flyout's Add call changed; update the mutant")
    local mutant = FUNC:sub(1, a - 1) .. "Add(spellID, spellName, C_Spell.GetSpellTexture(spellID))" .. FUNC:sub(b + 1)
    for _, forever in ipairs({ false, true }) do
        local ok = pcall(Load(mutant, forever))
        assert(not ok, "mutant survived on " .. (forever and "WoW Forever" or "retail"))
    end
end

print("PASS: the Spells list on both clients, flyout spells plain with their own icon, the mutant killed")
