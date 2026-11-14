-- /euipaste runs only /way and /euiway lines, whoever owns /way, and opens its
-- popup without the paste absorber so a long multi-line list reaches Run whole.
--   lua5.1 .tools/tests/test_qol_paste_waypoint_lines.lua   (from the repository root)
local ROOT = arg and arg[1] or "."

local failures = 0
local function check(cond, msg)
    if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

local function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function Load(env)
    local timers, printed, popup = {}, {}, nil
    local G = {
        EUI_CLIENT_BLOCKED = nil,
        EllesmereUIDB = { pasteCommands = true },
        strtrim = strtrim,
        pairs = pairs, ipairs = ipairs, type = type, tostring = tostring,
        -- WoW's xpcall passes extra arguments to the function; stock Lua 5.1's does not.
        xpcall = function(fn, eh, ...)
            local args, n = { ... }, select("#", ...)
            return xpcall(function() return fn(unpack(args, 1, n)) end, eh)
        end,
        string = string, table = table, select = select,
        geterrorhandler = function() return function(e) printed[#printed + 1] = "ERR " .. tostring(e) end end,
        issecurevariable = function(name) return env.secure[name] == true end,
        C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
        DEFAULT_CHAT_FRAME = { editBox = {} },
        SlashCmdList = env.SlashCmdList,
        hash_SlashCmdList = env.hash_SlashCmdList,
        hash_ChatTypeInfoList = env.hash_ChatTypeInfoList,
        InCombatLockdown = function() return false end,
    }
    G.EllesmereUI = {
        COLOR_CODES = { BRAND = "" },
        Print = function(msg) printed[#printed + 1] = msg end,
        L = function(s) return s end,
        Lf = function(fmt, ...)
            local args = { ... }
            return (fmt:gsub("%%(%d)%$d", function(i) return tostring(args[tonumber(i)]) end))
        end,
        ShowImportPopup = function(_, onImport, title, subtitle, opts)
            popup = { onImport = onImport, title = title, subtitle = subtitle, opts = opts }
        end,
    }
    for k, v in pairs(env.globals or {}) do G[k] = v end
    G._G = G
    local f = assert(io.open(ROOT .. "/EllesmereUIQoL/EllesmereUIQoL_PasteCommands.lua", "rb"))
    local chunk = assert(loadstring(f:read("*a"), "=EllesmereUIQoL_PasteCommands.lua"))
    f:close()
    setfenv(chunk, G)
    chunk()
    for _, fn in ipairs(timers) do fn() end
    return G, printed, function() return popup end
end

-- TomTom-style /way already imported into hash_SlashCmdList, /euiway still pending, plus other commands.
local ran = {}
local function Recorder(tag) return function(msg) ran[#ran + 1] = tag .. " " .. msg end end
local env = {
    secure = { SLASH_RELOAD1 = true },
    SlashCmdList = {
        EUIWAY = Recorder("euiway"),
        DEADLYBOSSMODS = Recorder("dbm"),
        RELOAD = Recorder("reload"),
    },
    hash_SlashCmdList = { ["/WAY"] = Recorder("way") },
    hash_ChatTypeInfoList = { ["/WAY"] = "TOMTOM_WAY" },
    globals = {
        SLASH_EUIWAY1 = "/euiway",
        SLASH_DEADLYBOSSMODS1 = "/dbm",
        SLASH_RELOAD1 = "/reload",
        SLASH_TOMTOM_WAY1 = "/way",
    },
}
local G, printed, popup = Load(env)

check(G.SlashCmdList.EUIPASTE ~= nil, "/euipaste registered")
G.SlashCmdList.EUIPASTE("")
local p = popup()
check(p and p.opts and p.opts.rawPaste == true, "popup opened with rawPaste")
check(p and p.opts and p.opts.confirmLabel == "Run", "popup confirm label is Run")

local lines = {}
for i = 1, 65 do
    lines[#lines + 1] = string.format("/way #2339 %d.%d %d.%d Treasure number %d near the long road", 10 + i % 80, i % 10, 20 + i % 70, i % 10, i)
end
lines[#lines + 1] = "/EUIWAY 41.2 60.5 Rare"
lines[#lines + 1] = "/dbm pull 10"
lines[#lines + 1] = "/reload"
lines[#lines + 1] = "/p hello"
lines[#lines + 1] = "plain text"
lines[#lines + 1] = "/euipaste"
lines[#lines + 1] = ""
local text = table.concat(lines, "\r\n")
check(#text > 2048, "paste is larger than the absorber cap (" .. #text .. " bytes)")

p.onImport(text)
local wayRuns, euiwayRuns = 0, 0
for _, r in ipairs(ran) do
    if r:sub(1, 4) == "way " then wayRuns = wayRuns + 1 end
    if r:sub(1, 7) == "euiway " then euiwayRuns = euiwayRuns + 1 end
    check(r:sub(1, 4) ~= "dbm " and r:sub(1, 7) ~= "reload ", "not run: " .. r)
end
check(wayRuns == 65, "all 65 /way lines ran (got " .. wayRuns .. ")")
check(euiwayRuns == 1, "/euiway line ran")
check(ran[1] == "way #2339 11.1 21.1 Treasure number 1 near the long road", "args passed intact: " .. tostring(ran[1]))
check(printed[#printed] == "EllesmereUI:|r Skipped 5 of 71 lines: only /way and /euiway waypoint lines can be pasted.",
    "skip message: " .. tostring(printed[#printed]))

-- A /way handler that errors is reported and the next lines still run.
ran = {}
env.hash_SlashCmdList["/WAY"] = function(msg) if msg == "boom" then error("boom") end ran[#ran + 1] = msg end
p.onImport("/way boom\n/way 1 2")
check(ran[1] == "1 2", "line after an erroring handler still ran")

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("OK")
