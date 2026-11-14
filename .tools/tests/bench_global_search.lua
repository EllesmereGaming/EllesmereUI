-- Run from the repository root: lua5.1 .tools/tests/bench_global_search.lua [scale] [GlobalSearch file]
-- Times EllesmereUI_GlobalSearch.lua's per-keystroke search over an index
-- built from every label/tooltip literal in EllesmereUIOptions (scale
-- repeats it to model a bigger index). Desktop Lua runs faster than the
-- game client: compare runs against each other, not against a frame budget.
local scale = tonumber(arg and arg[1]) or 1
local path = arg and arg[2] or "EllesmereUI_GlobalSearch.lua"

EllesmereUI = {
    L = function(s) return s end,
    GLOBAL_KEY = "_EUIGlobal",
    ADDON_GROUPS = {},
    IsDevModeActive = function() return false end,
}
local ns = { modules = { M = { title = "Module", pages = { "Page" } } } }
ns.GetTabLabel = function(_, p) return p end
local chunk = assert(loadstring(assert(io.open(path)):read("*a") .. "\nreturn SearchIndex", "GlobalSearch"))

-- The rows in source order, as a page build registers them: text= rows are
-- page rows, label= rows are cog popup rows hosted on the last text= row.
local rows = {}
local files = io.popen("git ls-files 'EllesmereUIOptions/*.lua'")
for file in files:lines() do
    local section = (file:match("([^/]+)_Options%.lua$") or file):upper()
    local host
    for line in io.lines(file) do
        local tip = line:match('tooltip%s*=%s*"([^"\\]*)"')
        for kind, label in line:gmatch('(%a+)%s*=%s*"([^"\\|%%]+)"') do
            if label:find("%a") and #label < 60 then
                if kind == "text" then
                    host = label
                    rows[#rows + 1] = { label, tip, section }
                elseif kind == "label" then
                    rows[#rows + 1] = { label, tip, section, host or "?", "Settings" }
                end
            end
        end
    end
end
files:close()

-- Indexing: every row registered into a fresh index (the file reloaded per
-- trial), best of 5. In game the pass spreads this, plus the page builders
-- themselves, across frames at a few ms each.
local SearchIndex, best = nil, math.huge
for _ = 1, 5 do
    SearchIndex = chunk("EllesmereUI", ns)
    local Register = EllesmereUI._RegisterSearchEntry
    local t0 = os.clock()
    for s = 1, scale do
        local suffix = s > 1 and (" " .. s) or ""
        for _, r in ipairs(rows) do
            Register(r[1] .. suffix, nil, r[2], "M", "Page", r[3], nil, nil, nil, r[4], r[5])
        end
    end
    best = math.min(best, os.clock() - t0)
end
local n = #rows * scale
print(("index: %d entries, %.2f ms to register (%.2f us each)"):format(n, best * 1000, best * 1e6 / n))

-- Every keystroke of a few typed queries, as the search box sees them.
local typed = { "character sheet mana", "bar texture", "cast bar size", "show", "zzzz" }
local total, keys = 0, 0
for _, q in ipairs(typed) do
    local t0 = os.clock()
    for i = 1, #q do
        for _ = 1, 10 do SearchIndex(q:sub(1, i), 12) end
    end
    local ms = (os.clock() - t0) * 1000 / (#q * 10)
    total, keys = total + ms * #q, keys + #q
    print(("%-22s %6.2f ms/keystroke"):format(q, ms))
end
print(("mean %.2f ms/keystroke"):format(total / keys))
