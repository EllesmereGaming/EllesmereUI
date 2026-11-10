-- The Group Finder results list harness again, in Blizzard's look: the one the
-- list takes while the Group Finder window skin is off. Every scenario of
-- test_gf_results_list.lua runs with the rows, the cancel button and the sign
-- up button built from Blizzard's art.
--   lua .tools/tests/test_gf_results_list_stock.lua   (from the repository root)
GF_LOOK = "stock"
local ROOT = arg and arg[1] or "."
local f = assert(io.open(ROOT .. "/.tools/tests/test_gf_results_list.lua", "rb"))
local src = f:read("*a")
f:close()
assert(loadstring(src, "=test_gf_results_list.lua"))()
