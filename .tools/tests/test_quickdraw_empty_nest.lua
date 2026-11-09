-- Stub harness: a Quickdraw nested menu shows on its parent only while it offers an
-- entry this character can use under its own Hide Unavailable Actions (nests inside
-- it do not count, and a menu never set up offers nothing).
-- Run from the repository root: lua .tools/tests/test_quickdraw_empty_nest.lua
local stub = function() end
local palettes = {}
local appearance = {}
local usable
local I = setmetatable({
    broken = false, QUESTION_MARK = 134400,
    ChildIndex = function(slot) return slot.kind == "palette" and slot.palette or nil end,
    ReadPalette = function(i) return palettes[i] end,
    PA = function(i) return appearance[i] or {} end,
    SetUsableSlots = function(f) usable = f end,
}, { __index = function() return stub end })
local ns = { _qdInternals = I, PaletteActive = function() return true end }
EUI_CLIENT_BLOCKED = false
local any = setmetatable({}, { __call = stub })
getmetatable(any).__index = function() return any end
setmetatable(_G, { __index = function() return any end })

local known = { [588] = true }
C_SpellBook = { IsSpellKnown = function(id) return known[id] == true end }
C_Spell = {}
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
EllesmereUI = { IS_FOREVER = true }

assert(loadfile("EllesmereUIQuickdraw/EUI_Quickdraw_Actions.lua"))("test", ns)
assert(usable, "Actions.lua did not register UsableSlots")

local function Count(parent)
    wipe(I.usableMemo)
    local slots = usable(parent, {})
    local n = 0
    for _, slot in ipairs(slots) do
        if slot.kind == "palette" then n = n + 1 end
    end
    return n
end

local parent = { slots = { { kind = "palette", palette = 2 } } }
palettes[2] = { slots = { { kind = "spell", id = 172 } } }
assert(Count(parent) == 0, "a nest with none of its spells known is hidden")

palettes[2].slots[2] = { kind = "spell", id = 588 }
assert(Count(parent) == 1, "a nest with one known spell stays")

palettes[2] = { slots = { { kind = "spell", id = 172 } } }
appearance[2] = { hideUnusable = false }
assert(Count(parent) == 1, "a nest that shows unavailable actions stays")

appearance[2] = nil
palettes[2] = { slots = { { kind = "palette", palette = 3 } } }
palettes[3] = { slots = { { kind = "spell", id = 588 } } }
assert(Count(parent) == 0, "a nest holding only further nests opens nothing and is hidden")

palettes[2] = nil
assert(Count(parent) == 0, "a nest whose palette was never set up is hidden")

print("quickdraw empty nest OK")
