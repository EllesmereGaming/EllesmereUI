-- /euipaste runs only /way and /euiway lines, through whoever owns the command: another addon's handler
-- line by line, our own handler once with the whole list. Lines of a command nothing owns are reported,
-- other lines are skipped and counted. Its window is the import popup without the paste absorber, built
-- once and shown again with an empty box.
--   lua5.1 .tools/tests/test_qol_paste_waypoint_lines.lua   (from the repository root)
local ROOT = arg and arg[1] or "."

local failures, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

local function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function read(rel)
    local f = assert(io.open(ROOT .. "/" .. rel, "rb"))
    local s = f:read("*a")
    f:close()
    return (s:gsub("\r\n", "\n"))
end

-- env: secure (alias name -> true), SlashCmdList (commands not imported yet), hash_SlashCmdList and
-- hash_ChatTypeInfoList (imported ones), globals (the SLASH_ aliases), ns (the module's shared table).
local function Load(env)
    local timers, printed, popups = {}, {}, {}
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
            popups[#popups + 1] = { onImport = onImport, title = title, subtitle = subtitle, opts = opts }
        end,
    }
    for k, v in pairs(env.globals or {}) do G[k] = v end
    G._G = G
    local chunk = assert(loadstring(read("EllesmereUIQoL/EllesmereUIQoL_PasteCommands.lua"), "=EllesmereUIQoL_PasteCommands.lua"))
    setfenv(chunk, G)
    chunk("EllesmereUIQoL", env.ns or {})
    for _, fn in ipairs(timers) do fn() end
    return G, printed, popups
end

local SKIPPED = "EllesmereUI:|r Skipped %d of %d lines: only /way and /euiway waypoint lines can be pasted."
local UNOWNED = "EllesmereUI:|r Some waypoint lines could not run: nothing handles their command. Turn on Enable /way Command."
local function count(list, s)
    local n = 0
    for _, v in ipairs(list) do if v == s then n = n + 1 end end
    return n
end

-------------------------------------------------------------------------------
-- 1. Another addon owns /way (already imported by the chat code), /euiway is still pending, our own
--    handler is not published: every waypoint line is one call of its own.
-------------------------------------------------------------------------------
do
    local ran = {}
    local function Recorder(tag) return function(msg) ran[#ran + 1] = tag .. " " .. msg end end
    local env = {
        secure = { SLASH_RELOAD1 = true },
        SlashCmdList = { EUIWAY = Recorder("euiway"), OTHERCMD = Recorder("other"), RELOAD = Recorder("reload") },
        hash_SlashCmdList = { ["/WAY"] = Recorder("way") },
        hash_ChatTypeInfoList = { ["/WAY"] = "OTHERWAY" },
        globals = { SLASH_EUIWAY1 = "/euiway", SLASH_OTHERCMD1 = "/other", SLASH_RELOAD1 = "/reload", SLASH_OTHERWAY1 = "/way" },
    }
    local G, printed, popups = Load(env)

    check(G.SlashCmdList.EUIPASTE ~= nil, "1: /euipaste registered")
    check(G.SLASH_EUIPASTE1 == "/euipaste" and G.SLASH_EUIPASTE2 == "/paste", "1: /paste taken while nothing owns it")
    G.SlashCmdList.EUIPASTE("")
    local p = popups[1]
    check(p and p.opts and p.opts.rawPaste == true, "1: window opened without the paste absorber")
    check(p and p.opts and p.opts.confirmLabel == "Run", "1: confirm label is Run")
    check(p and p.opts and p.opts.keep == "pasteWaypoints", "1: the window is kept under one key")
    check(p and p.title == "Paste Waypoints", "1: title")

    local lines = {}
    for i = 1, 65 do
        lines[#lines + 1] = string.format("/way #2339 %d.%d %d.%d Treasure number %d near the long road", 10 + i % 80, i % 10, 20 + i % 70, i % 10, i)
    end
    lines[#lines + 1] = "/EUIWAY 41.2 60.5 Rare"
    lines[#lines + 1] = "/other pull 10"
    lines[#lines + 1] = "/reload"
    lines[#lines + 1] = "/p hello"
    lines[#lines + 1] = "plain text"
    lines[#lines + 1] = "/euipaste"
    lines[#lines + 1] = ""
    local text = table.concat(lines, "\r\n")
    check(#text > 2048, "1: the paste is larger than the absorber's cap (" .. #text .. " bytes)")

    p.onImport(text)
    local wayRuns, euiwayRuns, others = 0, 0, 0
    for _, r in ipairs(ran) do
        if r:sub(1, 4) == "way " then wayRuns = wayRuns + 1
        elseif r:sub(1, 7) == "euiway " then euiwayRuns = euiwayRuns + 1
        else others = others + 1 end
    end
    check(wayRuns == 65, "1: all 65 /way lines ran, one call each (got " .. wayRuns .. ")")
    check(euiwayRuns == 1, "1: the /euiway line ran")
    check(others == 0, "1: no other command ran (" .. others .. ")")
    check(ran[1] == "way #2339 11.1 21.1 Treasure number 1 near the long road", "1: arguments passed intact: " .. tostring(ran[1]))
    check(printed[#printed] == SKIPPED:format(5, 71), "1: skip message: " .. tostring(printed[#printed]))
    check(count(printed, UNOWNED) == 0, "1: no 'nothing handles' line while every waypoint line had an owner")

    -- A handler that errors is reported and the lines after it still run.
    ran = {}
    env.hash_SlashCmdList["/WAY"] = function(msg) if msg == "boom" then error("boom") end ran[#ran + 1] = msg end
    p.onImport("/way boom\n/way 1 2")
    check(ran[1] == "1 2", "1: the line after an erroring handler still ran")
end

-------------------------------------------------------------------------------
-- 2. Our own handler owns both commands: one call with the whole list, in order.
-------------------------------------------------------------------------------
do
    local calls = {}
    local ours = function(msg) calls[#calls + 1] = msg end
    local env = {
        secure = {},
        SlashCmdList = {},
        hash_SlashCmdList = { ["/WAY"] = ours, ["/EUIWAY"] = ours },
        hash_ChatTypeInfoList = { ["/WAY"] = "EUIWAY", ["/EUIWAY"] = "EUIWAY" },
        globals = { SLASH_EUIWAY1 = "/euiway", SLASH_EUIWAY2 = "/way" },
        ns = { WaypointHandle = ours },
    }
    local G, printed, popups = Load(env)
    G.SlashCmdList.EUIPASTE("")
    popups[1].onImport("/way #2339 41.2 60.5 Rare\r\n\r\n/WAY 52.8 33.1 Treasure\n/euiway Orgrimmar 50 50\nnot a command")
    check(#calls == 1, "2: our handler is called once for the whole list (got " .. #calls .. ")")
    check(calls[1] == "#2339 41.2 60.5 Rare ; 52.8 33.1 Treasure ; Orgrimmar 50 50", "2: the list, in order: " .. tostring(calls[1]))
    check(printed[#printed] == SKIPPED:format(1, 4), "2: skip message: " .. tostring(printed[#printed]))
    -- Nothing to hand over: no call.
    calls = {}
    popups[1].onImport("hello\n/reload")
    check(#calls == 0, "2: no call when no waypoint line was pasted")
end

-------------------------------------------------------------------------------
-- 3. Another addon owns /way and ours owns /euiway: its lines one by one, ours in one call.
-------------------------------------------------------------------------------
do
    local other, calls = {}, {}
    local ours = function(msg) calls[#calls + 1] = msg end
    local env = {
        secure = {},
        SlashCmdList = { EUIWAY = ours },
        hash_SlashCmdList = { ["/WAY"] = function(msg) other[#other + 1] = msg end },
        hash_ChatTypeInfoList = { ["/WAY"] = "OTHERWAY" },
        globals = { SLASH_EUIWAY1 = "/euiway", SLASH_OTHERWAY1 = "/way" },
        ns = { WaypointHandle = ours },
    }
    local G, _, popups = Load(env)
    G.SlashCmdList.EUIPASTE("")
    popups[1].onImport("/way 1 2 a\n/euiway 3 4 b\n/way 5 6 c\n/euiway 7 8 d")
    check(#other == 2 and other[1] == "1 2 a" and other[2] == "5 6 c", "3: the other addon's /way got its two lines, one call each")
    check(#calls == 1 and calls[1] == "3 4 b ; 7 8 d", "3: ours got its two lines in one call: " .. tostring(calls[1]))
end

-------------------------------------------------------------------------------
-- 4. Nothing owns the waypoint commands (our /way is off, no other addon has one), and a /way alias
--    the game itself owns is never called.
-------------------------------------------------------------------------------
do
    local env = { secure = {}, SlashCmdList = {}, hash_SlashCmdList = {}, hash_ChatTypeInfoList = {}, globals = {} }
    local G, printed, popups = Load(env)
    G.SlashCmdList.EUIPASTE("")
    popups[1].onImport("/way 1 2\n/euiway 3 4\nhello")
    check(count(printed, UNOWNED) == 1, "4: one 'nothing handles' line for the waypoint lines without an owner")
    check(printed[#printed] == SKIPPED:format(1, 3), "4: only the line that is no waypoint line counts as skipped: " .. tostring(printed[#printed]))

    local ran = 0
    local env2 = {
        secure = { SLASH_GAMEWAY1 = true },
        SlashCmdList = {},
        hash_SlashCmdList = { ["/WAY"] = function() ran = ran + 1 end },
        hash_ChatTypeInfoList = { ["/WAY"] = "GAMEWAY" },
        globals = { SLASH_GAMEWAY1 = "/way" },
    }
    local G2, printed2, popups2 = Load(env2)
    G2.SlashCmdList.EUIPASTE("")
    popups2[1].onImport("/way 1 2")
    check(ran == 0, "4: a command the game itself registered is never called")
    check(count(printed2, UNOWNED) == 1, "4: and its line is reported as having no owner")
end

-------------------------------------------------------------------------------
-- 5. /paste stays with an addon that owns it.
-------------------------------------------------------------------------------
do
    local env = {
        secure = {},
        SlashCmdList = { OTHERPASTE = function() end },
        hash_SlashCmdList = {}, hash_ChatTypeInfoList = {},
        globals = { SLASH_OTHERPASTE1 = "/Paste" },
    }
    local G = Load(env)
    check(G.SLASH_EUIPASTE1 == "/euipaste" and G.SLASH_EUIPASTE2 == nil, "5: only /euipaste while another addon owns /paste")
end

-------------------------------------------------------------------------------
-- 6. The import popup's keep option (the real function, cut from EllesmereUI_Profiles.lua): one build
--    per key for a rawPaste caller, shown again with an empty box; every other call builds its own.
-------------------------------------------------------------------------------
do
    local src = read("EllesmereUI_Profiles.lua")
    local a = src:find("local keptImportPopups = {}", 1, true)
    local tail = "    C_Timer.After(0.05, function() editBox:SetFocus() end)\nend\n"
    local b = a and src:find(tail, a, true)
    check(a and b, "6: the import popup function was found")
    if a and b then
        local builds, shows, cleared = {}, 0, 0
        local E = {}
        local env = {
            EllesmereUI = E,
            C_Timer = { After = function() end },
            BuildStringPopup = function(title, subtitle, readOnly, onConfirm, label, raw)
                local dimmer = { Show = function() shows = shows + 1 end }
                local box = { SetText = function(_, t) if t == "" then cleared = cleared + 1 end end, SetFocus = function() end }
                builds[#builds + 1] = { title = title, label = label, raw = raw, readOnly = readOnly, onConfirm = onConfirm }
                return dimmer, box
            end,
        }
        local chunk = assert(loadstring(src:sub(a, b + #tail - 1), "=ShowImportPopup"))
        setfenv(chunk, env)
        chunk()
        local got
        local function cb(s) got = s end
        for _ = 1, 3 do E:ShowImportPopup(cb, "T", "S", { confirmLabel = "Run", rawPaste = true, keep = "k" }) end
        check(#builds == 1, "6: three opens under one key build one popup (built " .. #builds .. ")")
        check(shows == 3, "6: and show it three times")
        check(cleared == 2, "6: the box is emptied on each reuse (" .. cleared .. ")")
        check(builds[1].label == "Run" and builds[1].raw == true and builds[1].readOnly == false, "6: built editable, without the absorber, with the caller's label")
        builds[1].onConfirm("text")
        check(got == "text", "6: the confirm reaches the caller's function")
        E:ShowImportPopup(cb, "T", "S", { rawPaste = true, keep = "other" })
        check(#builds == 2, "6: another key is another popup")
        E:ShowImportPopup(cb, "T", "S", { rawPaste = true })
        E:ShowImportPopup(cb, "T", "S", { rawPaste = true })
        check(#builds == 4, "6: without a key every open builds its own")
        E:ShowImportPopup(cb, nil, nil, { keep = "k2" })
        E:ShowImportPopup(cb, nil, nil, { keep = "k2" })
        check(#builds == 6, "6: a popup with the paste absorber is never kept (its captured paste would stay)")
        check(builds[5].title == "Import Profile" and builds[5].label == "Import" and not builds[5].raw, "6: the defaults of a plain import popup")
        E:ShowImportPopup(cb)
        check(#builds == 7, "6: a call without options still works")
    end
end

-- The Waypoint file publishes the handler the paste window compares with.
check(read("EllesmereUIQoL/EllesmereUIQoL_Waypoint.lua"):find("\nns.WaypointHandle = HandleWay", 1, true) ~= nil,
    "the /way file publishes its handler as ns.WaypointHandle")

if failures > 0 then
    print(failures .. " failure(s) of " .. checks .. " checks")
    os.exit(1)
end
print("OK (" .. checks .. " checks)")
