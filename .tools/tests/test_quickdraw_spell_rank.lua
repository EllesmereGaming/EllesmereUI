-- Run from the repository root: lua .tools/tests/test_quickdraw_spell_rank.lua
local stub = function() end
local I = setmetatable({ broken = false, QUESTION_MARK = 134400 }, { __index = function() return stub end })
local ns = { _qdInternals = I }
EUI_CLIENT_BLOCKED = false
local any = setmetatable({}, { __call = stub })
getmetatable(any).__index = function() return any end
setmetatable(_G, { __index = function() return any end })

local known = { [686] = true, [695] = true }
local cachedAsk
local lookups, loaded = 0, true
C_Spell = {
    GetSpellInfo = function(spell)
        lookups = lookups + 1
        if spell == "Shadow Bolt" then return { spellID = 705, name = "Shadow Bolt", iconID = 136197 } end
        if loaded and (spell == 686 or spell == 695 or spell == 705) then
            return { spellID = spell, name = "Shadow Bolt", iconID = 136197 }
        end
    end,
    IsSpellDataCached = function(id) cachedAsk = id return true end,
}
-- the spellbook call itself: the IsPlayerSpell global exists only while the
-- loadDeprecationFallbacks CVar is on
C_SpellBook = { IsSpellKnown = function(id) return known[id] == true end }
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
EllesmereUI = { IS_FOREVER = true }

assert(loadfile("EllesmereUIQuickdraw/EUI_Quickdraw_Actions.lua"))("test", ns)
assert(ns.ResolveAction and ns.SlotDisplay and ns.SlotDataReady, "Actions.lua did not load")

local function Cast(id)
    local _, _, value = ns.ResolveAction({ kind = "spell", id = id })
    return value
end
local function LiveID(id)
    cachedAsk = nil
    ns.SlotDataReady({ kind = "spell", id = id })
    return cachedAsk
end

assert(Cast(686) == 686 and LiveID(686) == 686, "the top rank is unknown: the stored rank stays")
-- kept until the next push: no lookups for an id already resolved
lookups = 0
assert(Cast(686) == 686 and lookups == 0, "a resolved id is kept")
-- learning the rank fires SPELLS_CHANGED, whose push wipes what was kept
known[705] = true
assert(Cast(686) == 686, "the kept answer stands until the push")
ns.WipeRankCache()
assert(Cast(686) == 705, "an old rank casts the highest known one")
assert(LiveID(686) == 705, "cooldown and usability follow the highest known rank")
assert(select(2, ns.SlotDisplay({ kind = "spell", id = 686 })) == "Shadow Bolt", "the entry keeps its name")
assert(Cast(705) == 705, "the highest rank stays")
-- a lookup before the spell's data loaded is not kept
ns.WipeRankCache()
loaded = false
assert(Cast(695) == 695, "no data yet: the stored rank")
loaded = true
assert(Cast(695) == 705, "data loaded: the highest known rank")
EllesmereUI.IS_FOREVER = false
assert(Cast(686) == 686 and LiveID(686) == 686, "retail keeps the stored id")
print("quickdraw spell rank OK")
