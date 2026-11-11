-- Stub harness: loads the Action Bars paging file outside the game and checks
-- the paging conditions of a WoW Forever druid. After a powershift the client
-- reports the form but not its bonus bar, so each druid form with a bonus bar
-- also gets a [form:i] clause, after the bonus bar clauses; every other
-- client and class keeps its conditions as they were.
--   lua .tools/tests/test_ab_forever_form_paging.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local SRC = ReadSource("EllesmereUIActionBars/EUI_ActionBars_Paging.lua")

local BEAR, DIRE_BEAR, CAT, AQUATIC, TRAVEL, MOONKIN = 5487, 9634, 768, 1066, 783, 24858
local SECRET = {}

-- Loads the file for one client and class. opts: forever, class, forms (the
-- stance bar's spell IDs in order), mainBar (bar 1 settings).
local function Load(opts)
    local T = { forms = opts.forms or {}, combat = false, rebuilt = {}, deferred = {}, frames = {} }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.EUI_CLIENT_BLOCKED = nil
    env.issecretvalue = function(v) return v == SECRET end
    env.InCombatLockdown = function() return T.combat end
    env.UnitClass = function() return opts.class, opts.class end
    env.GetNumShapeshiftForms = function() return #T.forms end
    env.GetShapeshiftFormInfo = function(i) return 136000 + i, false, true, T.forms[i] end
    env.RegisterAttributeDriver = function() end
    env.UnregisterAttributeDriver = function() end
    env.CreateFrame = function()
        local f = { events = {} }
        function f:RegisterEvent(e) self.events[e] = true end
        function f:SetScript(_, fn) self.handler = fn end
        T.frames[#T.frames + 1] = f
        return f
    end
    local druid = {
        { id = "prowl", macro = "[bonusbar:1,stealth]" },
        { id = "cat",   macro = "[bonusbar:1]" },
        { id = "bear",  macro = "[bonusbar:3]" },
    }
    if not opts.forever then druid[#druid + 1] = { id = "moonkin", macro = "[bonusbar:4]" } end
    env.EllesmereUI = {
        IS_FOREVER = opts.forever or false,
        CLASS_PAGING_STATES = { DRUID = druid, WARRIOR = { { id = "battle", macro = "[bonusbar:1]" } } },
    }
    local ns = {
        EFD = function() return {} end,
        EAB = { db = { profile = { bars = { MainBar = opts.mainBar or {}, Bar2 = {} } } } },
        EAB_VTABLE = {},
        _internals = {
            barBaseSize = {}, barFrames = { MainBar = {}, Bar2 = {} }, NUM_AB_PAGES = 6,
            SetPagingFrame = function() end, pagingFrameSetters = {},
        },
        CombatQueue = { Defer = function(key, fn) T.deferred[key] = fn end },
        RebuildBarPaging = function(barKey, onlyIfChanged)
            assert(onlyIfChanged == true, "the form rebuild must leave unchanged bars alone")
            T.rebuilt[#T.rebuilt + 1] = barKey
        end,
    }
    local chunk = assert(loadstring(SRC, "=EUI_ActionBars_Paging.lua"))
    setfenv(chunk, env)
    chunk("EllesmereUIActionBars", ns)
    T.ns, T.Default, T.Build = ns, ns._internals.GetClassPagingConditions, ns.EAB_VTABLE.BuildPagingConditions
    return T
end

local function Has(s, piece) return s:find(piece, 1, true) ~= nil end
local function Before(s, a, b)
    local i, j = s:find(a, 1, true), s:find(b, 1, true)
    return i ~= nil and j ~= nil and i < j
end

-------------------------------------------------------------------------------
-- 1. a WoW Forever druid: Bear, Aquatic, Cat on the stance bar
-------------------------------------------------------------------------------
local T = Load({ forever = true, class = "DRUID", forms = { BEAR, AQUATIC, CAT } })
local s = T.Default()
assert(Has(s, "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; [form:1] 9; [form:3,nostealth] 7; "),
    "the form clauses must follow the bonus bar clauses: " .. s)
assert(Before(s, "[bar:6] 6", "[form:1] 9") and s:sub(-1) == "1", "manual pages first, the default page last: " .. s)
assert(not Has(s, "[form:2]"), "Aquatic Form has no bonus bar and takes no clause")

-- Dire Bear Form takes Bear Form's spot and page; Travel and Moonkin take none
T.forms = { DIRE_BEAR, AQUATIC, CAT, TRAVEL, MOONKIN }
s = T.Default()
assert(Has(s, "[form:1] 9; [form:3,nostealth] 7; ") and not Has(s, "[form:4]") and not Has(s, "[form:5]"), s)

-- no forms known yet, or a spell ID that cannot be read: the old conditions
T.forms = {}
local bare = T.Default()
assert(not Has(bare, "[form:"), bare)
T.forms = { SECRET, CAT }
s = T.Default()
assert(Has(s, "[form:2,nostealth] 7") and not Has(s, "[form:1]"), s)

-------------------------------------------------------------------------------
-- 2. the watcher: a changed stance bar rebuilds the drivers, out of combat
-------------------------------------------------------------------------------
assert(#T.frames == 1 and T.frames[1].events.UPDATE_SHAPESHIFT_FORMS and T.frames[1].events.PLAYER_ENTERING_WORLD,
    "a Forever druid listens for the stance bar's forms")
local fire = T.frames[1].handler
T.forms = { BEAR }
fire()
assert(#T.rebuilt == 2, "each bar frame is offered the rebuild")
fire()
assert(#T.rebuilt == 2, "an unchanged stance bar rebuilt the drivers again")
T.forms = { BEAR, CAT }
T.combat = true
fire()
assert(#T.rebuilt == 2 and T.deferred.FormPaging, "a change in combat must wait for its end")
T.combat = false
T.deferred.FormPaging()
assert(#T.rebuilt == 4, "the deferred rebuild did not run")

-------------------------------------------------------------------------------
-- 3. Form Paging off: no bonus bar clauses and no form clauses
-------------------------------------------------------------------------------
T = Load({ forever = true, class = "DRUID", forms = { BEAR, CAT }, mainBar = { disableFormPaging = true } })
s = T.Default()
assert(not Has(s, "[bonusbar:3]") and not Has(s, "[form:"), s)

-------------------------------------------------------------------------------
-- 4. picked pages: a form's picked page is its form clause's page too
-------------------------------------------------------------------------------
T = Load({ forever = true, class = "DRUID", forms = { BEAR, AQUATIC, CAT } })
s = T.Build("MainBar", { shift = 2, bear = 4 }, 1)
assert(Has(s, "[bonusbar:3] 4") and Has(s, "[form:1] 4; [form:3,nostealth] 7"), s)
assert(Before(s, "[bonusbar:4] 10", "[form:1] 4") and Before(s, "[form:3,nostealth] 7", "[bar:2] 2"), s)
-- another bar: only the picked form, with its page
s = T.Build("Bar2", { cat = 5 }, 6)
assert(Has(s, "[bonusbar:1] 5; [form:3,nostealth] 5; 6") and not Has(s, "[form:1]"), s)
-- bar 1 with Form Paging off: a picked form still pages, the others do not
T = Load({ forever = true, class = "DRUID", forms = { BEAR, CAT }, mainBar = { disableFormPaging = true } })
s = T.Build("MainBar", { cat = 3 }, 1)
assert(Has(s, "[bonusbar:1] 3") and Has(s, "[form:2,nostealth] 3") and not Has(s, "[form:1]") and not Has(s, "[bonusbar:3]"), s)

-------------------------------------------------------------------------------
-- 5. every other class and client: nothing added, nothing listening
-------------------------------------------------------------------------------
T = Load({ forever = true, class = "WARRIOR", forms = { 2457, 71 } })
s = T.Default()
assert(not Has(s, "[form:") and Has(s, "[bonusbar:3] 9") and #T.frames == 0, s)
assert(not Has(T.Build("MainBar", { battle = 3 }, 1), "[form:"))
T = Load({ forever = false, class = "DRUID", forms = { BEAR, CAT, TRAVEL, MOONKIN } })
s = T.Default()
assert(not Has(s, "[form:") and #T.frames == 0, s)
assert(Has(s, "[bonusbar:1,stealth] 7; [bonusbar:1] 7; [bonusbar:3] 9; [bonusbar:4] 10; [bonusbar:5] 11; 1"), s)
assert(not Has(T.Build("MainBar", { bear = 4 }, 1), "[form:"))

print("forever druid conditions: " .. bare)
print("action bars forever form paging harness: ok")
