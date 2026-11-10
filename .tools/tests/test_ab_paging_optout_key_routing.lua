-- Stub harness: loads the Action Bars paging and keybind files outside the
-- game and checks how Action Bar 1's keys are bound under its auto-paging
-- opt-outs. A key bound to the native command (ACTIONBUTTON1) reaches the
-- game's own key path, the only one that gives Press and Hold Casting; a key
-- bound as a click of our button cannot. The opt-outs need the click route
-- (the native command would follow the bonus bar the icon no longer shows),
-- so Form Paging off costs Press and Hold Casting on bar 1 on every client.
-- WoW Forever has no skyriding and offers no Skyriding Paging, so a saved
-- disableSkyridingPaging is read as unset there: bar 1 keeps the native
-- route and the [bonusbar:5] clause, as a profile that never set it does.
--   lua .tools/tests/test_ab_paging_optout_key_routing.lua        (from the repository root)
-- AB_PAGING_PATH / AB_KEYBINDS_PATH point it at other copies of the files.
local ROOT = arg and arg[1] or "."
local PAGING_PATH = AB_PAGING_PATH or (ROOT .. "/EllesmereUIActionBars/EUI_ActionBars_Paging.lua")
local KEYBINDS_PATH = AB_KEYBINDS_PATH or (ROOT .. "/EllesmereUIActionBars/EUI_ActionBars_Keybinds.lua")

local function ReadSource(path)
    local f = assert(io.open(path, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local PAGING_SRC = ReadSource(PAGING_PATH)
local KEYBINDS_SRC = ReadSource(KEYBINDS_PATH)

-- Loads both files for one client with bar 1's settings. Returns the
-- override bindings table (key -> "cmd:<command>" or "click:<button>"), the
-- rebuild function and the paging condition builders.
local function Load(forever, mainBar)
    local T = { bound = {} }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.EUI_CLIENT_BLOCKED = nil
    env.issecretvalue = function() return false end
    env.InCombatLockdown = function() return false end
    env.UnitClass = function() return "Warrior", "WARRIOR" end
    env.GetNumShapeshiftForms = function() return 0 end
    env.GetShapeshiftFormInfo = function() return nil end
    env.RegisterAttributeDriver = function() end
    env.UnregisterAttributeDriver = function() end
    env.CreateFrame = function(_, name)
        local f = { name = name }
        function f:RegisterEvent() end
        function f:SetScript() end
        return f
    end
    env.UIParent = {}
    env.GetBindingKey = function(cmd)
        if cmd == "ACTIONBUTTON1" then return "1" end
        if cmd == "MULTIACTIONBAR1BUTTON1" then return "Q" end
    end
    env.HasAction = function() return true end
    env.GetActionInfo = function(slot) return "spell", 1000 + slot end
    env.C_Spell = { IsPressHoldReleaseSpell = function() return false end }
    env.GetTime = function() return 1 end
    env.GetCVarBool = function() return true end
    env.ClearOverrideBindings = function() T.bound = {} end
    env.SetOverrideBinding = function(_, _, key, cmd) T.bound[key] = "cmd:" .. cmd end
    env.SetOverrideBindingClick = function(_, _, key, name) T.bound[key] = "click:" .. name end
    env.EllesmereUI = {
        IS_FOREVER = forever,
        CLASS_PAGING_STATES = { WARRIOR = { { id = "battle", macro = "[bonusbar:1]" } } },
    }
    local function Button(slot)
        return {
            GetAttribute = function(_, k) if k == "action" then return slot end end,
            GetName = function() return "EABButton" .. slot end,
        }
    end
    local function BarFrame() return { SetAttribute = function() end } end
    local ns = {
        EFD = function() return {} end,
        EAB = { db = { profile = { bars = { MainBar = mainBar, Bar2 = {} } } } },
        EAB_VTABLE = {},
        barButtons = { MainBar = { Button(1) }, Bar2 = { Button(61) } },
        _eabBuildSkippedBars = function() end,
        CombatQueue = { Defer = function() end },
        RebuildBarPaging = function() end,
        _internals = {
            barBaseSize = {}, barFrames = { MainBar = BarFrame(), Bar2 = BarFrame() }, NUM_AB_PAGES = 6,
            SetPagingFrame = function() end, pagingFrameSetters = {},
            BAR_CONFIG = { { key = "MainBar" }, { key = "Bar2", nativeActionPage = 6 } },
            BAR_SLOT_OFFSETS = { MainBar = 0, Bar2 = 60 },
            BINDING_MAP = { MainBar = "ACTIONBUTTON", Bar2 = "MULTIACTIONBAR1BUTTON" },
        },
    }
    local paging = assert(loadstring(PAGING_SRC, "=EUI_ActionBars_Paging.lua"))
    setfenv(paging, env)
    paging("EllesmereUIActionBars", ns)
    local keybinds = assert(loadstring(KEYBINDS_SRC, "=EUI_ActionBars_Keybinds.lua"))
    setfenv(keybinds, env)
    keybinds("EllesmereUIActionBars", ns)
    T.Update = assert(ns._internals.UpdateKeybinds, "UpdateKeybinds is not published")
    T.Default = assert(ns._internals.GetClassPagingConditions, "GetClassPagingConditions is not published")
    T.Build = ns.EAB_VTABLE.BuildPagingConditions
    T.OptOuts = ns.EAB_VTABLE.GetAutoPagingOptOuts
    return T
end

local function Has(s, piece) return s:find(piece, 1, true) ~= nil end
local failures = 0
local function Check(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    end
end

for _, forever in ipairs({ false, true }) do
    local client = forever and "WoW Forever" or "retail"

    -- Nothing set: bar 1 and bar 2 keys ride their native commands.
    local T = Load(forever, {})
    T.Update()
    Check(T.bound["1"] == "cmd:ACTIONBUTTON1", client .. ", nothing set: key 1 is " .. tostring(T.bound["1"]))
    Check(T.bound["Q"] == "cmd:MULTIACTIONBAR1BUTTON1", client .. ", nothing set: key Q is " .. tostring(T.bound["Q"]))
    local plain = T.Default()

    -- Form Paging off: the click route on every client (the icon keeps page 1
    -- while the native command would follow the stance's bonus bar).
    T = Load(forever, { disableFormPaging = true })
    T.Update()
    Check(T.bound["1"] == "click:EABButton1", client .. ", Form Paging off: key 1 is " .. tostring(T.bound["1"]))
    Check(T.bound["Q"] == "cmd:MULTIACTIONBAR1BUTTON1", client .. ", Form Paging off: bar 2 left native")
    Check(not Has(T.Default(), "[bonusbar:1]"), client .. ", Form Paging off: the bar still follows the stance")

    -- Skyriding Paging off.
    T = Load(forever, { disableSkyridingPaging = true })
    T.Update()
    local noForm, noSky = T.OptOuts("MainBar")
    if forever then
        Check(T.bound["1"] == "cmd:ACTIONBUTTON1",
            "WoW Forever, saved Skyriding Paging off: key 1 must stay native, is " .. tostring(T.bound["1"]))
        Check(noForm == false and noSky == false, "WoW Forever reads a saved disableSkyridingPaging as unset")
        Check(T.Default() == plain, "WoW Forever: the page conditions equal a profile that never set it")
        Check(Has(T.Build("MainBar", { shift = 2 }, 1), "[bonusbar:5] 11"),
            "WoW Forever: custom paging keeps the [bonusbar:5] clause")
    else
        Check(T.bound["1"] == "click:EABButton1", "retail, Skyriding Paging off: key 1 is " .. tostring(T.bound["1"]))
        Check(noForm == false and noSky == true, "retail keeps the skyriding opt-out")
        Check(not Has(T.Default(), "[bonusbar:5]"), "retail, Skyriding Paging off: the bar still follows skyriding")
        Check(not Has(T.Build("MainBar", { shift = 2 }, 1), "[bonusbar:5]"),
            "retail, Skyriding Paging off: custom paging still adds [bonusbar:5]")
    end

    -- Both off: Form Paging alone still asks for the click route.
    T = Load(forever, { disableFormPaging = true, disableSkyridingPaging = true })
    T.Update()
    Check(T.bound["1"] == "click:EABButton1", client .. ", both off: key 1 is " .. tostring(T.bound["1"]))

    -- Custom paging: the click route on every client.
    T = Load(forever, { paging = { shift = 2 } })
    T.Update()
    Check(T.bound["1"] == "click:EABButton1", client .. ", Shift paging: key 1 is " .. tostring(T.bound["1"]))
end

if failures > 0 then
    error(("action bars paging opt-out key routing harness: %d failed"):format(failures))
end
print("action bars paging opt-out key routing harness: ok")
