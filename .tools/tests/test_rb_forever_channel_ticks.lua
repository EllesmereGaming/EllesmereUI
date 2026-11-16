-- Stub harness: the cast bar's channel tick table on each client.
--   lua .tools/tests/test_rb_forever_channel_ticks.lua        (from the repository root)
-- The table and its WoW Forever block are cut from EllesmereUIResourceBars.lua and built
-- under each client. On WoW Forever every rank of a spell is a spell ID of its own, so the
-- block lists each rank a class learns; a row's tick count is the channel's length over
-- its tick interval. Retail's table holds none of those rank IDs and is the same whether
-- or not the block is there.
local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 40 then print("  FAIL: " .. tostring(msg)) end
    end
    return cond
end
local function eq(a, b, msg)
    return check(a == b, tostring(msg) .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

local f = assert(io.open("EllesmereUIResourceBars/EllesmereUIResourceBars.lua", "rb"))
local SRC = f:read("*a"):gsub("\r\n", "\n")
f:close()
local a = assert(SRC:find("local CHANNEL_TICK_DATA = {", 1, true), "the channel tick table was not found")
local b = assert(SRC:find("\n%-%-%-%-%-%-%-%-+\n%-%-  Class/Spec resource mapping", a), "the end of the channel tick block was not found")
local BLOCK = SRC:sub(a, b) .. "\nreturn CHANNEL_TICK_DATA\n"

local function Build(forever)
    local chunk = assert(loadstring(BLOCK, "=the channel tick block"))
    return setfenv(chunk, setmetatable({ EllesmereUI = { IS_FOREVER = forever } }, { __index = _G }))()
end
local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
-- a row as text: every field, sorted
local function Row(r)
    if type(r) ~= "table" then return tostring(r) end
    local parts = {}
    for k, v in pairs(r) do
        parts[#parts + 1] = k .. "=" .. (type(v) == "table" and "{" .. Count(v) .. "}" or tostring(v))
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local retail, noFlag, forever = Build(false), Build(nil), Build(true)

-- What the WoW Forever block lists: the tick count of every rank ID.
local FOREVER_ROWS = {
    -- Priest
    [3]  = { 15407, 17311, 17312, 17313, 17314, 18807 },                                    -- Mind Flay (3s / 1s)
    [2]  = { 402261, 402277, 402174, 1240734, 1240732, 1240720, 1240736, 1240733, 1240721,
             1316994, 1316992, 1316995 },                                                    -- Penance (2s, one bolt at the cast)
    -- Warlock
    [5]  = { 689, 699, 709, 7651, 11699, 11700,                                              -- Drain Life (5s / 1s)
             1120, 8288, 8289, 11675,                                                        -- Drain Soul (15s / 3s)
             5138, 6226, 11703, 11704 },                                                     -- Drain Mana (5s / 1s)
    [15] = { 403677, 403685, 403686, 403687, 403688, 403689,                                 -- Drain Life, the 15s version
             1949, 11683, 11684 },                                                           -- Hellfire (15s / 1s)
    [4]  = { 5740, 6219, 11677, 11678 },                                                     -- Rain of Fire (8s / 2s)
    [6]  = { 1316697 },                                                                      -- Wrack (6s / 1s)
}
local listed, total = {}, 0
for ticks, ids in pairs(FOREVER_ROWS) do
    for _, id in ipairs(ids) do
        check(listed[id] == nil, "the harness lists spell " .. id .. " twice")
        listed[id] = ticks
        total = total + 1
    end
end
eq(total, 46, "rank IDs the harness expects on WoW Forever")

-- 1. retail: the same table with or without a client flag, and none of the rank IDs
eq(Count(retail), Count(noFlag), "retail rows with no client flag")
for id, row in pairs(retail) do
    eq(Row(noFlag[id]), Row(row), "retail row " .. id .. " with no client flag")
end
for id in pairs(listed) do
    if id ~= 15407 then check(retail[id] == nil, "WoW Forever's rank " .. id .. " is in retail's table") end
end
eq(Row(retail[15407]), "ticks=6", "retail's Mind Flay")
eq(Row(retail[755]) .. "|" .. Row(retail[234153]) .. "|" .. Row(retail[198590]), "ticks=5|ticks=5|ticks=5", "retail's warlock channels")

-- 2. WoW Forever: every listed rank, with its tick count and nothing else in the row
for id, ticks in pairs(listed) do
    eq(Row(forever[id]), "ticks=" .. ticks, "WoW Forever, spell " .. id)
end
-- 3. nothing else differs from retail: no other row added, changed or dropped
local extra = 0
for id, row in pairs(forever) do
    if listed[id] == nil then
        if retail[id] == nil then extra = extra + 1 end
        eq(Row(row), Row(retail[id]), "WoW Forever row " .. id .. " that the block does not list")
    end
end
eq(extra, 0, "rows on WoW Forever that are neither retail's nor listed")
for id in pairs(retail) do
    check(forever[id] ~= nil, "retail's row " .. id .. " is gone on WoW Forever")
end
eq(Count(forever), Count(retail) + total - 1, "rows on WoW Forever (retail's, the listed ranks, Mind Flay's first rank shared)")

-- 4. the marks a row draws: one per tick but the last, evenly spaced over the channel
for _, c in ipairs({ { "Drain Life", 689, 5, 4 }, { "Drain Soul", 1120, 15, 4 }, { "Drain Mana", 5138, 5, 4 }, { "the 15s Drain Life", 403677, 15, 14 },
                     { "Hellfire", 1949, 15, 14 }, { "Rain of Fire", 5740, 8, 3 }, { "Wrack", 1316697, 6, 5 } }) do
    local row = forever[c[2]]
    eq(row and row.ticks - 1, c[4], c[1] .. ": interior marks")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_rb_forever_channel_ticks (%d checks)"):format(count))
