-- Stub harness: Gathering Skill in Tooltips (Forever Essentials) knows herb and
-- ore nodes by the names the game client shows, whatever EUI Options Language.
-- Loads the real locale engine, the real Gathering Skill file and the real
-- <code>_GameNames.lua files, picked the way the two TOCs that list them pick
-- them (a line loads when its AllowLoadTextLocale tag names the client
-- language), and counts every load of the locale addon. Node names are read
-- from the names files themselves, so this file holds no translated text.
--   lua .tools/tests/test_fe_gather_skill_names.lua        (from the repository root)
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

local function Read(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return s
end
local function Exists(path)
    local f = io.open(path, "rb")
    if f then f:close() end
    return f ~= nil
end
local FE_TOC = Read("EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_Camelot.toc")
local LOC_TOC = Read("EllesmereUILocales/EllesmereUILocales.toc")
local ENGINE = Read("EllesmereUI_Locale.lua")
local FEATURE = Read("EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_GatherSkill.lua")
local FE_MAIN = Read("EllesmereUIForeverEssentials/EllesmereUIForeverEssentials.lua")
local CODES = { "deDE", "esES", "esMX", "frFR", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

-- The tagged file lines of a TOC: { file (as written), path (from the repository root), tags = { code = true } }.
local function TaggedLines(toc, dir)
    local list = {}
    for line in (toc .. "\n"):gmatch("(.-)\n") do
        local file, tags = line:match("^([%w_%.\\]+%.lua)%s*%[AllowLoadTextLocale ([^%]]+)%]%s*$")
        if file then
            local e = { file = file, tags = {}, n = 0 }
            for code in tags:gmatch("%a+") do e.tags[code] = true; e.n = e.n + 1 end
            -- a path that climbs out of the addon's own folder is a sibling's
            e.path = file:find("^%.%.\\") and file:sub(4):gsub("\\", "/") or (dir .. "/" .. file:gsub("\\", "/"))
            list[#list + 1] = e
        end
    end
    return list
end
local FE_LINES = TaggedLines(FE_TOC, "EllesmereUIForeverEssentials")
local LOC_LINES = TaggedLines(LOC_TOC, "EllesmereUILocales")

-- What a names file holds: its table, read with a registry that accepts it.
local function Names(code)
    local t = {}
    local env = setmetatable({ EllesmereUI = { RegisterGameNames = function() return t end } }, { __index = _G })
    setfenv(assert(loadstring(Read("EllesmereUILocales/" .. code .. "_GameNames.lua"), "=" .. code .. " names")), env)()
    return t
end

-------------------------------------------------------------------------------
--  The world: one client
-------------------------------------------------------------------------------
-- o: client (the game's language), ui (EUI Options Language), enabled, tocNames
-- (false: the client did not load the names lines of the module's own TOC)
local function World(o)
    local w = { localeLoads = 0, posts = {}, ran = {} }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    local frames = {}
    env.CreateFrame = function()
        local f = { events = {} }
        function f:RegisterEvent(e) self.events[e] = true end
        function f:UnregisterEvent(e) self.events[e] = nil end
        function f:UnregisterAllEvents() self.events = {} end
        function f:SetScript(_, fn) self.onEvent = fn end
        frames[#frames + 1] = f
        return f
    end
    env.GetLocale = function() return o.client end
    env.issecretvalue = function() return false end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.UnitName = function() return "Tester" end
    env.EllesmereUIDB = { displayLocale = o.ui, gatherSkill = { enabled = o.enabled } }
    local function Run(src, name, ...)
        return setfenv(assert(loadstring(src, "=" .. name)), env)(...)
    end
    local function RunLines(list)
        for _, e in ipairs(list) do
            if e.tags[o.client] then
                w.ran[e.path] = (w.ran[e.path] or 0) + 1
                Run(Read(e.path), e.path, "addon", {})
            end
        end
    end
    local localesIn = false
    env.C_AddOns = {
        LoadAddOn = function(name)
            if name == "EllesmereUILocales" and not localesIn then
                localesIn = true
                w.localeLoads = w.localeLoads + 1
                RunLines(LOC_LINES)
            end
            return true
        end,
        IsAddOnLoaded = function(name)
            if name == "EllesmereUILocales" then return localesIn, localesIn end
            return false, false
        end,
        IsAddOnLoadable = function() return false end,
    }
    -- the parent: the locale engine and its ADDON_LOADED pass
    env.EllesmereUI = { IS_FOREVER = true, HELD_BACK_ADDONS = {} }
    Run(ENGINE, "EllesmereUI_Locale", "EllesmereUI", {})
    local localeFrame = frames[1]
    localeFrame.onEvent(localeFrame, "ADDON_LOADED", "EllesmereUI")
    w.loadsAtParent = w.localeLoads
    -- Forever Essentials loads: the names lines of its TOC, then the feature
    if o.tocNames ~= false then RunLines(FE_LINES) end
    env.C_Item = {
        GetItemNameByID = function(id) return "Herb" .. id end,
        RequestLoadItemDataByID = function() end,
    }
    env.GetProfessions = function() return 1, 2 end
    env.GetProfessionInfo = function(i)
        if i == 1 then return "Mining", 0, 50, 300, 0, 0, 186 end
        return "Herbalism", 0, 300, 300, 0, 0, 182
    end
    env.C_Spell = { GetSpellName = function(id) return id == 2575 and "Mining" or "Herbalism" end }
    env.Enum = { TooltipDataType = { Object = 33, MinimapMouseover = 34 } }
    env.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) w.posts[kind] = fn end }
    local lines = {}
    env.GameTooltip = { NumLines = function() return #lines end, Show = function() end }
    local apply
    local module = { Feature = function(_, defaults)
        local F = {}
        function F.Get(k)
            local v = env.EllesmereUIDB.gatherSkill[k]
            if v == nil then return defaults[k] end
            return v
        end
        function F.Enabled() return F.Get("enabled") == true end
        function F.Cfg() return env.EllesmereUIDB.gatherSkill end
        function F.Start(fn) apply = fn end
        w.defaults = defaults
        return F
    end }
    Run(FEATURE, "GatherSkill", "EllesmereUIForeverEssentials", module)
    apply()   -- the login boot
    w.env = env
    function w.Enable() env.EllesmereUIDB.gatherSkill.enabled = true; apply() end
    function w.Disable() env.EllesmereUIDB.gatherSkill.enabled = false; apply() end
    -- a names file run whatever its TOC tag says (a build that lists them untagged)
    function w.RunNames(code) Run(Read("EllesmereUILocales/" .. code .. "_GameNames.lua"), code .. " names", "addon", {}) end
    function w.Apply() apply() end
    function w.L(s) return env.EllesmereUI.L(s) end
    -- a node's tooltip: its name, then the game's requirement line; returns that line afterwards
    function w.Node(title, skill)
        local req = "Requires " .. skill
        lines = {}
        for i, text in ipairs({ title, req }) do
            local fs = { text = text }
            function fs:GetText() return self.text end
            function fs:SetText(t) self.text = t end
            function fs:SetTextColor() end
            lines[i] = fs
            env["GameTooltipTextLeft" .. i] = fs
        end
        if not w.posts[33] then return req end
        w.posts[33](env.GameTooltip, { lines = { { leftText = title } } })
        return lines[2]:GetText()
    end
    return w
end

-------------------------------------------------------------------------------
-- 1. The two TOCs and the files
-------------------------------------------------------------------------------
do
    local byCode = {}
    for _, e in ipairs(FE_LINES) do
        local code = e.file:match("([%a]+)_GameNames%.lua$")
        if check(code ~= nil, "a tagged line of the module's TOC that is not a names file: " .. e.file) then
            byCode[code] = e
            eq(e.file, "..\\EllesmereUILocales\\" .. code .. "_GameNames.lua", code .. ": the module's TOC points at the file in the locale folder")
            eq(e.n, 1, code .. ": the module's line names one language")
            check(e.tags[code], code .. ": its own")
            check(Exists(e.path), code .. ": the file is there (" .. e.path .. ")")
        end
    end
    for _, code in ipairs(CODES) do
        check(byCode[code] ~= nil, code .. ": listed in the module's TOC")
        local n, own = 0, false
        for _, e in ipairs(LOC_LINES) do
            if e.file == code .. "_GameNames.lua" then
                n = n + 1
                own = e.n == 1 and e.tags[code] or false
            end
        end
        eq(n, 1, code .. ": listed once in the locale addon's TOC")
        check(own, code .. ": tagged there with its own language alone")
        check(ENGINE:find(code .. " = true", 1, true), code .. ": the engine knows the language has a names file")
    end
    eq(#FE_LINES, #CODES, "the module's TOC lists nine names files and no other tagged file")
    -- the names lines come after the module's main file (its guard goes first)
    local main = FE_TOC:find("\nEllesmereUIForeverEssentials.lua\n", 1, true)
    local first = FE_TOC:find("..\\EllesmereUILocales\\", 1, true)
    check(main and first and main < first, "the names lines follow the module's main file")
    -- each file is game data for its own client language alone
    for _, code in ipairs(CODES) do
        local src = Read("EllesmereUILocales/" .. code .. "_GameNames.lua")
        check(src:find('EllesmereUI.RegisterGameNames("' .. code .. '")', 1, true), code .. ": registers under its own code")
        check(src:find("if EUI_CLIENT_BLOCKED then return end", 1, true) == 1, code .. ": starts with the client failsafe")
        check(next(Names(code)) ~= nil, code .. ": holds names")
    end
    check(FE_MAIN:find("EllesmereUI.LoadGameNames and EllesmereUI.GameName", 1, true), "the module's stale-parent guard names both parent functions")
end

-------------------------------------------------------------------------------
-- 2. A German client with English options: the names come in with the module
-------------------------------------------------------------------------------
local DE = Names("deDE")
do
    local w = World({ client = "deDE", ui = "enUS", enabled = true })
    eq(w.loadsAtParent, 0, "English options: the locale addon is not loaded at the parent's load")
    eq(w.localeLoads, 0, "and not for the names either: they came in with the module")
    eq(w.ran["EllesmereUILocales/deDE_GameNames.lua"], 1, "the German names file ran once")
    eq(w.ran["EllesmereUILocales/esES_GameNames.lua"], nil, "another language's did not")
    eq(w.Node(DE["Copper Vein"], "Mining"), "Requires Mining (1)", "the German Copper Vein gains its skill")
    eq(w.Node(DE["Dark Iron Deposit"], "Mining"), "Requires Mining (230)", "the German Dark Iron Deposit")
    eq(w.Node(DE["Mountain Silversage"], "Herbalism"), "Requires Herbalism (280)", "a herb node named unlike its herb")
    eq(w.Node("Herb13465", "Herbalism"), "Requires Herbalism (280)", "the herb's own item name still matches")
    eq(w.Node("Copper Vein", "Mining"), "Requires Mining (1)", "the English name matches too")
    eq(w.Node("Some Chest", "Mining"), "Requires Mining", "an object that is no node is left alone")
    eq(w.L("Coordinates"), "Coordinates", "the options stay English")
    w.Apply(); w.Apply()
    eq(w.localeLoads, 0, "later applies load nothing")
    eq(w.posts[34], nil, "no minimap tooltip post-call (the game keeps that text from addons)")
    check(w.posts[33] ~= nil, "the object tooltip post-call is in")
    eq(w.defaults.minimap, nil, "no minimap setting")

    -- another language's names file run on this client registers nothing
    eq(w.env.EllesmereUI.RegisterGameNames("frFR"), nil, "a German client hands no table to the French file")
    check(w.env.EllesmereUI.RegisterGameNames("deDE") ~= nil, "it hands one to its own")
    local FR = Names("frFR")
    w = World({ client = "deDE", ui = "enUS", enabled = false })
    w.RunNames("frFR")
    w.Enable()
    eq(w.Node(FR["Copper Vein"], "Mining"), "Requires Mining", "French names run on a German client are not known")
    eq(w.Node(DE["Copper Vein"], "Mining"), "Requires Mining (1)", "the German ones are")

    -- turned off again: the post-call stays and leaves the tooltip alone
    w.Disable()
    eq(w.Node(DE["Copper Vein"], "Mining"), "Requires Mining", "turned off again: the tooltip is the game's")
    w.Enable()
    eq(w.Node(DE["Copper Vein"], "Mining"), "Requires Mining (1)", "turned on again: the skill is back")
    eq(w.localeLoads, 0, "through all of it the locale addon was never loaded")
end

-------------------------------------------------------------------------------
-- 3. The same client where the module's names lines did not load: the locale
--    addon is loaded for them, once
-------------------------------------------------------------------------------
do
    local w = World({ client = "deDE", ui = "enUS", enabled = true, tocNames = false })
    eq(w.loadsAtParent, 0, "nothing at the parent's load")
    eq(w.localeLoads, 1, "the feature's first apply loads the locale addon for the names")
    eq(w.Node(DE["Copper Vein"], "Mining"), "Requires Mining (1)", "and the German Copper Vein gains its skill")
    eq(w.L("Coordinates"), "Coordinates", "the late load does not switch the options language")
    w.Apply()
    eq(w.localeLoads, 1, "a second apply does not load again")
end

-------------------------------------------------------------------------------
-- 4. German options: the locale addon is in already; nothing more is loaded
-------------------------------------------------------------------------------
do
    local w = World({ client = "deDE", ui = "deDE", enabled = true })
    eq(w.loadsAtParent, 1, "German options: the locale addon loads for the translations")
    eq(w.localeLoads, 1, "the names ask for no second load")
    eq(w.Node(DE["Copper Vein"], "Mining"), "Requires Mining (1)", "the node gains its skill")
    eq(w.L("Copper Vein"), "Copper Vein", "ore names are no longer in the translations")
    w = World({ client = "deDE", ui = "deDE", enabled = true, tocNames = false })
    eq(w.localeLoads, 1, "without the module's lines: still one load")
    eq(w.Node(DE["Copper Vein"], "Mining"), "Requires Mining (1)", "and the names came with it")
end

-------------------------------------------------------------------------------
-- 5. The feature off: nothing hooked or loaded until it is turned on
-------------------------------------------------------------------------------
do
    local w = World({ client = "deDE", ui = "enUS", enabled = false, tocNames = false })
    eq(w.localeLoads, 0, "off: no locale addon load")
    eq(w.posts[33], nil, "off: no tooltip post-call")
    eq(w.Node(DE["Copper Vein"], "Mining"), "Requires Mining", "off: the tooltip is the game's")
    w.Enable()
    eq(w.localeLoads, 1, "turned on: the names are fetched")
    eq(w.Node(DE["Copper Vein"], "Mining"), "Requires Mining (1)", "turned on: the node gains its skill")
end

-------------------------------------------------------------------------------
-- 6. English clients, and a language with no names file, load nothing for names
-------------------------------------------------------------------------------
do
    local w = World({ client = "enUS", ui = "enUS", enabled = true, tocNames = false })
    eq(w.localeLoads, 0, "an English client: no locale addon load")
    eq(w.Node("Copper Vein", "Mining"), "Requires Mining (1)", "English nodes match")
    eq(w.Node(DE["Copper Vein"], "Mining"), "Requires Mining", "German names are not known there")
    w = World({ client = "enGB", ui = "enUS", enabled = true, tocNames = false })
    eq(w.localeLoads, 0, "a British English client: no load")
    w = World({ client = "enUS", ui = "deDE", enabled = true, tocNames = false })
    eq(w.loadsAtParent, 1, "an English client with German options loads the translations")
    eq(w.localeLoads, 1, "and nothing more for names")
    eq(w.Node("Copper Vein", "Mining"), "Requires Mining (1)", "its nodes are English")
    w = World({ client = "itIT", ui = "enUS", enabled = true, tocNames = false })
    eq(w.localeLoads, 0, "a language with no names file: the locale addon is not loaded for nothing")
    eq(w.Node("Copper Vein", "Mining"), "Requires Mining (1)", "English names still match there")
end

-------------------------------------------------------------------------------
-- 7. Every language's own client; Mexican Spanish reads its own file alone
-------------------------------------------------------------------------------
for _, code in ipairs(CODES) do
    local names = Names(code)
    local w = World({ client = code, ui = "enUS", enabled = true })
    eq(w.localeLoads, 0, code .. " client, English options: no locale addon load")
    eq(w.Node(names["Copper Vein"], "Mining"), "Requires Mining (1)", code .. ": its Copper Vein gains the skill")
    local other = code == "deDE" and "frFR" or "deDE"
    eq(w.ran["EllesmereUILocales/" .. other .. "_GameNames.lua"], nil, code .. ": no other language's names file runs")
end
do
    local es, mx = Names("esES"), Names("esMX")
    local only
    for k, v in pairs(es) do
        if mx[k] == nil then only = v end
    end
    if check(only ~= nil, "the Spanish (Spain) file names a node the Mexican one does not") then
        local w = World({ client = "esMX", ui = "enUS", enabled = true })
        eq(w.Node(only, "Mining"), "Requires Mining", "a Mexican client does not read Spain's names")
    end
end

-------------------------------------------------------------------------------
-- 8. Source pins
-------------------------------------------------------------------------------
check(not FEATURE:find("MinimapMouseover", 1, true), "the feature file has no minimap tooltip path")
check(not FEATURE:find("SKILL_LINES_CHANGED", 1, true), "and no event for it")
check(FEATURE:find("EllesmereUI.LoadGameNames()", 1, true), "the feature asks for the names before its lookup is built")

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_fe_gather_skill_names (%d checks)"):format(count))
