-- Run from the repository root: lua .tools/tests/test_new_internals.lua
-- Loads only the EllesmereUI.NewInternals block of EllesmereUI_SharedHelpers.lua.
local path = arg[1] or "EllesmereUI_SharedHelpers.lua"
local f = assert(io.open(path, "rb"))
local src = f:read("*a")
f:close()
local start = assert(src:find("%-%-  Guard table of a split module"), "helper block not found")
EllesmereUI, EUI_NS = {}, {}
assert(loadstring(src:sub(start), "=NewInternals"))()
assert(EUI_NS.NewInternals == EllesmereUI.NewInternals)

local ns, a, b = {}, nil, nil
local I = EllesmereUI.NewInternals(ns, "_t", {
    fls = false,
    aSetters = { function(v) a = v end }, bSetters = {},
}, { SetA = "aSetters", SetB = "bSetters" })
assert(ns._t == I and I.broken == false and I.fls == false)

local ok, err = pcall(function() return I.Missing end)
assert(not ok and err:find("ns._t has no entry Missing", 1, true), err)

-- No value before the first Set, then fan-out to prefilled and registered entries.
I.bSetters[#I.bSetters + 1] = function(v) b = v end
assert(b == nil)
I.SetA(5)
I.SetB("x")
assert(a == 5 and b == "x")

-- An entry added after a Set gets the last value at once, false and nil included.
local late, got = {}, {}
for i, v in ipairs({ "x", false, "nil" }) do
    if v == "nil" then I.SetB(nil) elseif v == false then I.SetB(false) end
    I.bSetters[#I.bSetters + 1] = function(nv)
        if not got[i] then got[i], late[i] = true, nv end
    end
end
assert(got[1] and got[2] and got[3])
assert(late[1] == "x" and late[2] == false and late[3] == nil)
assert(#I.bSetters == 4)

-- A last chain keeps its field; broken is set either way. label names the owner.
local J = EllesmereUI.NewInternals(ns, "_u", { last = "main" }, nil, "EUI_NS")
assert(J.last == "main" and J.broken == false)
ok, err = pcall(function() return J.Missing end)
assert(not ok and err:find("EUI_NS._u has no entry Missing", 1, true), err)

ok, err = pcall(EllesmereUI.NewInternals, ns, "_v", {}, { SetZ = "zSetters" })
assert(not ok and err:find("ns._v: SetZ has no list zSetters", 1, true), err)

print("test_new_internals: ok")
