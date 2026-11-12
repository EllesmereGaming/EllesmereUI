-- Stub harness: loads the Action Bars paging and bar files outside the game
-- and builds the bars the way a login or /reload does. A bar's paging state
-- driver resolves as its frame is made, before its buttons exist, so a bar
-- built while it is paged (a druid in a form, a warrior in a stance) must
-- start its buttons on the page the driver stands on, not on the bar's own
-- page. Models the secure state driver (evaluate on register and on every
-- poll, write only a changed value) and the bar's _onstate-page handler
-- (ChildUpdate of each button's _childupdate-eab-page).
--   lua .tools/tests/test_ab_paged_bar_build_page.lua        (from the repository root)
-- The bar file can be swapped through the global EUI_BARS_PATH.
local ROOT = arg and arg[1] or "."

local function ReadSource(path)
    local f = assert(io.open(path:find("^%a:") and path or (ROOT .. "/" .. path), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local PAGING_SRC = ReadSource("EllesmereUIActionBars/EUI_ActionBars_Paging.lua")
local BARS_SRC = ReadSource(rawget(_G, "EUI_BARS_PATH") or "EllesmereUIActionBars/EUI_ActionBars_Bars.lua")

local BEAR, AQUATIC, CAT = 5487, 1066, 768

-- A macro option evaluator for the conditions these bars carry: clauses split
-- by ";", each one or more [..] groups (any group), each group comma-separated
-- tests (every test).
local function Test(t, st)
    local name, val = t:match("^%s*([%a]+):?(%w*)%s*$")
    if name == "bonusbar" then return st.bonus == tonumber(val) end
    if name == "form" or name == "stance" then return st.form == tonumber(val) end
    if name == "bar" then return (st.bar or 1) == tonumber(val) end
    if name == "stealth" then return st.stealth and true or false end
    if name == "nostealth" then return not st.stealth end
    if name == "mod" then return st.mod == val end
    return false
end
local function Evaluate(conds, st)
    for clause in (conds .. ";"):gmatch("([^;]*);") do
        local groups = {}
        for g in clause:gmatch("%[([^%]]*)%]") do groups[#groups + 1] = g end
        local value = clause:gsub("%b[]", ""):match("^%s*(.-)%s*$")
        local hit = #groups == 0
        for _, g in ipairs(groups) do
            local all = true
            for t in (g .. ","):gmatch("([^,]*),") do
                if not Test(t, st) then all = false break end
            end
            if all then hit = true break end
        end
        if hit then return value end
    end
end

local CLASS_STATES = {
    DRUID = {
        { id = "prowl", macro = "[bonusbar:1,stealth]" },
        { id = "cat",   macro = "[bonusbar:1]" },
        { id = "bear",  macro = "[bonusbar:3]" },
    },
    WARRIOR = {
        { id = "battle",    macro = "[bonusbar:1]" },
        { id = "defensive", macro = "[bonusbar:2]" },
        { id = "berserker", macro = "[bonusbar:3]" },
    },
}

local BAR_CONFIG = {
    { key = "MainBar", count = 12, barID = 1, nativeMainBar = true },
    { key = "Bar2",    count = 12, barID = 2, nativeActionPage = 6 },
    { key = "Bar3",    count = 12, barID = 3, nativeActionPage = 5 },
    { key = "Bar9",    count = 12, barID = 0, customPage = 2 },
}
local BAR_SLOT_OFFSETS = { MainBar = 0, Bar2 = 60, Bar3 = 48, Bar9 = 12 }

-- Loads both files for one client, class, stance bar and client state, with
-- the given bar settings. opts.never: bars built with no buttons (a Never bar
-- with no key), as SetupBar does.
local function Load(opts)
    local T = {
        state = opts.state, drivers = {}, allButtons = {},
        refreshed = {}, attack = {}, border = {}, never = opts.never or {},
    }

    local function OnStatePage(frame, newstate)
        local page = tonumber(newstate) or 1
        frame.attrs.actionpage = page
        for _, child in ipairs(frame.children) do
            local body = child.attrs["_childupdate-eab-page"]
            if type(body) == "string" then
                local base = tonumber(body:match("local slot = (%d+) %+ %(page %- 1%) %* 12"))
                assert(base, "unrecognized page snippet")
                child:SetAttribute("action", base + (page - 1) * 12)
            end
        end
    end

    local function NewFrame(name)
        local f = { attrs = {}, children = {}, hooks = {}, name = name }
        function f:SetSize() end
        function f:SetPoint() end
        function f:GetFrameLevel() return 1 end
        function f:SetFrameLevel() end
        function f:SetMouseClickEnabled() end
        function f:SetClampedToScreen() end
        function f:SetFrameRef() end
        function f:RegisterEvent() end
        function f:SetScript() end
        function f:IsShown() return true end
        function f:HookScript(script, fn) self.hooks[#self.hooks + 1] = { script, fn } end
        function f:GetAttribute(k) return self.attrs[k] end
        function f:SetAttributeNoHandler(k, v) self.attrs[k] = v end
        function f:SetAttribute(k, v)
            self.attrs[k] = v
            if k == "state-page" and self.attrs["_onstate-page"] then OnStatePage(self, v) end
            for _, h in ipairs(self.hooks) do
                if h[1] == "OnAttributeChanged" then h[2](self, k, v) end
            end
        end
        function f:Execute(body)
            local p = body:match("SetAttribute%('actionpage', (%d+)%)")
            if p then self.attrs.actionpage = tonumber(p) end
        end
        return f
    end

    local function NewButton(slot)
        local b = { attrs = {}, name = "EABButton" .. slot }
        function b:GetAttribute(k) return self.attrs[k] end
        function b:SetAttribute(k, v) self.attrs[k] = v end
        function b:SetAttributeNoHandler(k, v) self.attrs[k] = v end
        function b:SetHitRectInsets() end
        function b:GetSize() return 45, 45 end
        function b:GetWidth() return 45 end
        function b:GetHeight() return 45 end
        function b:RegisterForClicks() end
        function b:EnableMouseWheel() end
        function b:GetName() return self.name end
        return b
    end

    -- SecureStateDriverManager: resolve at registration and on each poll,
    -- writing the attribute only when the value changed.
    local function Resolve(frame, state, values)
        local v = Evaluate(values, T.state)
        v = tonumber(v) or v
        if frame:GetAttribute("state-" .. state) ~= v then frame:SetAttribute("state-" .. state, v) end
    end
    function T.Poll()
        for frame, d in pairs(T.drivers) do
            for state, values in pairs(d) do Resolve(frame, state, values) end
        end
    end

    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.EUI_CLIENT_BLOCKED = nil
    env.issecretvalue = function() return false end
    env.InCombatLockdown = function() return false end
    env.GetTime = function() return 0 end
    env.GetCVarBool = function() return false end
    env.UnitClass = function() return opts.class, opts.class end
    env.GetNumShapeshiftForms = function() return #(opts.forms or {}) end
    env.GetShapeshiftFormInfo = function(i) return 136000 + i, false, true, opts.forms[i] end
    env.UIParent = NewFrame("UIParent")
    env.MainActionBar = NewFrame("MainActionBar")
    env.CreateFrame = function(_, name) return NewFrame(name) end
    env.RegisterAttributeDriver = function() end
    env.UnregisterAttributeDriver = function() end
    env.RegisterStateDriver = function(frame, state, values)
        T.drivers[frame] = T.drivers[frame] or {}
        T.drivers[frame][state] = values
        Resolve(frame, state, values)
    end
    env.UnregisterStateDriver = function(frame, state)
        if T.drivers[frame] then T.drivers[frame][state] = nil end
    end
    local states = { DRUID = CLASS_STATES.DRUID, WARRIOR = CLASS_STATES.WARRIOR }
    env.EllesmereUI = { IS_FOREVER = opts.forever, CLASS_PAGING_STATES = states }

    local efd = {}
    local barFrames, barButtons, buttonToBar = {}, {}, {}
    local I = {
        BAR_CONFIG = BAR_CONFIG, BAR_SLOT_OFFSETS = BAR_SLOT_OFFSETS, NUM_AB_PAGES = 6,
        barBaseSize = {}, barFrames = barFrames, buttonToBar = buttonToBar,
        BINDING_MAP = { MainBar = "ACTIONBUTTON", Bar2 = "MULTIACTIONBAR1BUTTON", Bar3 = "MULTIACTIONBAR2BUTTON" },
        RegisterBarWithOverrideController = function() end,
        ReRegisterButtonEvents = function() end,
        SecureSetupHandler_RegisterBarFrame = function() end,
        SetPagingFrame = function() end, pagingFrameSetters = {},
        GetEABFlyout = function() return { RegisterButton = function() end } end,
        GetOrCreateButton = function(slot, parent, _, _, skip)
            local btn = T.allButtons[slot]
            if not btn then
                btn = NewButton(slot)
                T.allButtons[slot] = btn
                parent.children[#parent.children + 1] = btn
            end
            if not skip then btn:SetAttribute("action", slot) end
            return btn
        end,
    }
    local EAB = { db = { profile = { bars = opts.bars } }, VisibilityCompat = { IsNever = function() return false end } }
    local ns = {
        EFD = function(btn)
            local t = efd[btn]
            if not t then t = {}; efd[btn] = t end
            return t
        end,
        EAB = EAB,
        EAB_VTABLE = { ForceButtonRefresh = function(btn, a) T.refreshed[btn] = a end },
        barButtons = barButtons,
        _internals = I,
        _eabBarNoButtons = {},
        CombatQueue = { Defer = function() end },
        IsNeverBar = function(info) return T.never[info.key] and true or false end,
        BarHasBoundKeys = function() return false end,
        AB_LayoutShape = function() return "none" end,
        AB_SyncAttackState = function(btn, a) T.attack[btn] = a end,
        AB_SyncEquippedBorder = function(btn, a) T.border[btn] = a end,
        ApplyBarDormancy = function() end,
    }
    for _, src in ipairs({ { PAGING_SRC, "=EUI_ActionBars_Paging.lua" }, { BARS_SRC, "=EUI_ActionBars_Bars.lua" } }) do
        local chunk = assert(loadstring(src[1], src[2]))
        setfenv(chunk, env)
        chunk("EllesmereUIActionBars", ns)
    end
    for _, info in ipairs(BAR_CONFIG) do I.SetupBar(info, false) end
    T.ns, T.frames, T.buttons = ns, barFrames, barButtons
    return T
end

local fails = 0
local function Check(cond, msg)
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end
-- True when every button of the bar holds its slot on the given page, and was
-- refreshed and reconciled against that slot.
local function OnPage(T, key, page, painted)
    local btns = T.buttons[key]
    if not btns or #btns == 0 then return false end
    for i, btn in ipairs(btns) do
        local want = i + (page - 1) * 12
        if btn:GetAttribute("action") ~= want then return false end
        if painted and (T.refreshed[btn] ~= want or T.attack[btn] ~= want or T.border[btn] ~= want) then
            return false
        end
    end
    return true
end
local function Page(T, key) return T.frames[key]:GetAttribute("state-page") end

-- The reporter's settings: Action Bar 2 pages to Action Bar 9 (page 2) for
-- Prowl and Cat Form and to Action Bar 10 (page 10) for Bear Form.
local function DruidBars()
    return {
        MainBar = {},
        Bar2 = { paging = { prowl = 2, cat = 2, bear = 10 }, modTargetPaging = false },
        Bar3 = {},
        Bar9 = {},
    }
end

-------------------------------------------------------------------------------
-- 1. the report: a WoW Forever druid reloads in Bear Form
-------------------------------------------------------------------------------
do
    local T = Load({ forever = true, class = "DRUID", forms = { BEAR, AQUATIC, CAT },
        state = { form = 1, bonus = 3 }, bars = DruidBars() })
    Check(Page(T, "Bar2") == 10, "bar 2's driver is not on the bear page")
    Check(OnPage(T, "Bar2", 10, true), "built in Bear Form, Action Bar 2 shows its own page, not the bear page")
    Check(OnPage(T, "Bar3", 5, true), "an unpaged bar left its own page")
    -- bar 1 after the load's own re-apply of its page (EAB:FinishSetup)
    local cur = tonumber(Page(T, "MainBar"))
    for i, btn in ipairs(T.buttons.MainBar) do btn:SetAttribute("action", i + (cur - 1) * 12) end
    Check(cur == 9 and OnPage(T, "MainBar", 9), "bar 1 is not on the bear page after the load")

    -- the following form changes page both bars as before
    T.state = { form = 0, bonus = 0 }
    T.Poll()
    Check(OnPage(T, "Bar2", 6), "caster: bar 2 not on its own page")
    T.state = { form = 1, bonus = 0 }  -- a powershift: the form reads, its bonus bar does not
    T.Poll()
    Check(OnPage(T, "Bar2", 10) and OnPage(T, "MainBar", 9), "after a powershift the bars left the bear pages")
    T.state = { form = 3, bonus = 1 }
    T.Poll()
    Check(OnPage(T, "Bar2", 2) and OnPage(T, "MainBar", 7), "cat: the bars are not on the cat pages")
end

-------------------------------------------------------------------------------
-- 2. built in caster form, in Cat Form and while prowling
-------------------------------------------------------------------------------
do
    local T = Load({ forever = true, class = "DRUID", forms = { BEAR, AQUATIC, CAT },
        state = { form = 0, bonus = 0 }, bars = DruidBars() })
    Check(OnPage(T, "Bar2", 6, true), "caster: bar 2 not on its own page")
    T = Load({ forever = true, class = "DRUID", forms = { BEAR, AQUATIC, CAT },
        state = { form = 3, bonus = 1 }, bars = DruidBars() })
    Check(OnPage(T, "Bar2", 2, true), "built in Cat Form, bar 2 not on the cat page")
    T = Load({ forever = true, class = "DRUID", forms = { BEAR, AQUATIC, CAT },
        state = { form = 3, bonus = 1, stealth = true }, bars = DruidBars() })
    Check(OnPage(T, "Bar2", 2, true), "built while prowling, bar 2 not on the prowl page")
end

-------------------------------------------------------------------------------
-- 3. a warrior: always in a stance, so every load builds the bar paged
-------------------------------------------------------------------------------
do
    local bars = { MainBar = {}, Bar2 = { paging = { battle = 2, defensive = 10 } }, Bar3 = {}, Bar9 = {} }
    local T = Load({ forever = true, class = "WARRIOR", forms = { 2457, 71 },
        state = { form = 2, bonus = 2 }, bars = bars })
    Check(OnPage(T, "Bar2", 10, true), "built in Defensive Stance, bar 2 not on its page")
    -- retail: the same build order, the same page
    T = Load({ forever = false, class = "WARRIOR", forms = { 2457, 71 },
        state = { form = 1, bonus = 1 }, bars = { MainBar = {}, Bar2 = { paging = { battle = 3 } }, Bar3 = {}, Bar9 = {} } })
    Check(OnPage(T, "Bar2", 3, true), "retail, built in Battle Stance: bar 2 not on its page")
end

-------------------------------------------------------------------------------
-- 4. a bar built with no buttons, then built later while paged
-------------------------------------------------------------------------------
do
    local bars = DruidBars()
    local T = Load({ forever = true, class = "DRUID", forms = { BEAR, AQUATIC, CAT },
        state = { form = 0, bonus = 0 }, bars = bars, never = { Bar2 = true } })
    Check(#T.buttons.Bar2 == 0, "the Never bar was built with buttons")
    T.state = { form = 1, bonus = 3 }
    T.Poll()
    Check(Page(T, "Bar2") == 10, "bar 2's driver did not follow the form")
    T.never.Bar2 = nil
    T.ns.BuildBarButtons({ key = "Bar2", count = 12, nativeActionPage = 6 }, T.frames.Bar2, false)
    Check(OnPage(T, "Bar2", 10, true), "built later in Bear Form, bar 2 not on the bear page")
end

-------------------------------------------------------------------------------
-- 5. a bar whose paging was taken off keeps its own page at a later build
-------------------------------------------------------------------------------
do
    local bars = DruidBars()
    local T = Load({ forever = true, class = "DRUID", forms = { BEAR, AQUATIC, CAT },
        state = { form = 1, bonus = 3 }, bars = bars, never = { Bar2 = true } })
    bars.Bar2.paging = {}
    T.ns.RebuildBarPaging("Bar2", true)
    Check(T.frames.Bar2._eabPagingConds == false, "the paging driver was not taken off")
    T.ns.BuildBarButtons({ key = "Bar2", count = 12, nativeActionPage = 6 }, T.frames.Bar2, false)
    Check(OnPage(T, "Bar2", 6, true), "an unpaged bar took a stale driver page")
end

print(fails == 0 and "action bars paged bar build page harness: ok"
    or ("action bars paged bar build page harness: " .. fails .. " failure(s)"))
if fails > 0 then error("failures") end
