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
    GetSpellSubtext = function(id)
        return ({ [686] = "Rank 1", [695] = "Rank 2", [705] = "Rank 3" })[id]
    end,
}
local cursor
GetCursorInfo = function() if cursor then return "spell", 1, nil, cursor end end
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

-- a pinned lower rank casts, shows and is named as exactly that rank
local pinned = { kind = "spell", id = 686, rankPinned = true }
assert(select(3, ns.ResolveAction(pinned)) == 686, "a pinned rank casts that rank")
cachedAsk = nil
ns.SlotDataReady(pinned)
assert(cachedAsk == 686, "a pinned rank's cooldown and usability are its own")
assert(select(2, ns.SlotDisplay(pinned)) == "Shadow Bolt (Rank 1)", "a pinned rank is named with its rank")
assert(select(2, ns.SlotDisplay({ kind = "spell", id = 705 })) == "Shadow Bolt", "the top rank entry has no rank text")
-- dragging a lower rank keeps it; dragging the top rank follows the highest
cursor = 695
local dropped = ns.SlotFromCursor()
assert(dropped.id == 695 and dropped.rankPinned == true, "a dragged lower rank is pinned")
cursor = 705
assert(ns.SlotFromCursor().rankPinned == nil, "a dragged top rank is not pinned")

EllesmereUI.IS_FOREVER = false
assert(Cast(686) == 686 and LiveID(686) == 686, "retail keeps the stored id")
assert(select(2, ns.SlotDisplay(pinned)) == "Shadow Bolt", "retail never shows a rank")
cursor = 686
assert(ns.SlotFromCursor().rankPinned == nil, "retail never pins")
print("quickdraw spell rank OK")
