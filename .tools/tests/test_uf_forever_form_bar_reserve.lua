-- Stub harness: the WoW Forever druid form power bar (Power Type Mana + Form
-- Power) and the player frame's bottom-anchored auras. The bar hangs under
-- the power bar, outside the frame box, so the auras' bottom reserve must
-- count it while it shows, and its showing, hiding and laying out must ask
-- for one re-anchor of the player auras.
--   lua .tools/tests/test_uf_forever_form_bar_reserve.lua        (from the repository root)
-- Globals FB_FORMBAR / FB_AURAS point the harness at other copies of
-- EUI_UnitFrames_ForeverFormBar.lua / EUI_UnitFrames_AuraContainers.lua.
local ROOT = (arg and arg[1]) or "."

local function ReadSource(override, name)
    local path = override or (ROOT .. "/" .. name)
    local f = assert(io.open(path, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local FORMBAR_SRC = ReadSource(FB_FORMBAR, "EllesmereUIUnitFrames/EUI_UnitFrames_ForeverFormBar.lua")
local AURAS_SRC = ReadSource(FB_AURAS, "EllesmereUIUnitFrames/EUI_UnitFrames_AuraContainers.lua")

local fails, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
issecretvalue = function(v) return v == SECRET end

-------------------------------------------------------------------------------
--  Widget mocks: methods (capitalised keys) not defined here are no-ops, and
--  any other field that was never set reads nil, as on a real frame.
-------------------------------------------------------------------------------
local created = {}
local function MakeObj(kind, parent)
    local o = { _kind = kind, _parent = parent, _shown = true, _scripts = {}, _events = {}, _level = 1 }
    created[#created + 1] = o
    setmetatable(o, { __index = function(_, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end
        if k == "Show" then return function(self) self._shown = true end end
        if k == "Hide" then return function(self) self._shown = false end end
        if k == "SetShown" then return function(self, v) self._shown = v and true or false end end
        if k == "IsShown" then return function(self) return self._shown end end
        if k == "GetParent" then return function(self) return self._parent end end
        if k == "SetParent" then return function(self, p) self._parent = p end end
        if k == "GetFrameLevel" then return function(self) return self._level end end
        if k == "SetFrameLevel" then return function(self, v) self._level = v end end
        if k == "GetFrameStrata" then return function() return "MEDIUM" end end
        if k == "GetHeight" then return function(self) return self._h or 10 end end
        if k == "SetHeight" then return function(self, v) self._h = v end end
        if k == "SetScript" then return function(self, name, fn) self._scripts[name] = fn end end
        if k == "GetScript" then return function(self, name) return self._scripts[name] end end
        if k == "RegisterEvent" or k == "RegisterUnitEvent" then
            return function(self, ev) self._events[ev] = true end
        end
        if k == "UnregisterEvent" then return function(self, ev) self._events[ev] = nil end end
        if k == "UnregisterAllEvents" then return function(self) self._events = {} end end
        if k == "CreateTexture" then return function(self) return MakeObj("Texture", self) end end
        if k == "CreateFontString" then return function(self) return MakeObj("FontString", self) end end
        if k == "GetEffectiveScale" then return function(self) return self._scale or 1 end end
        if k == "GetLeft" then return function(self) return self._l end end
        if k == "GetRight" then return function(self) return self._r end end
        if k == "GetTop" then return function(self) return self._t end end
        if k == "GetBottom" then return function(self) return self._b end end
        return function() end
    end })
    return o
end
CreateFrame = function(kind, _, parent) return MakeObj(kind, parent) end

-------------------------------------------------------------------------------
--  Game API and EllesmereUI stubs
-------------------------------------------------------------------------------
local G = { pt = 0, token = "MANA", arms = 0 }
Enum = { PowerType = { Mana = 0 } }
CurveConstants = { ScaleTo100 = 1 }
UnitClass = function() return "Druid", "DRUID" end
UnitPowerType = function() return G.pt, G.token end
UnitPower = function() return 50 end
UnitPowerMax = function() return 100 end
UnitPowerPercent = function() return 50 end

EllesmereUI = {
    IS_FOREVER = true,
    IsSecret = function(v) return v == SECRET end,
    PP = { mult = 1, CreateBorder = function() end, UpdateBorder = function() end },
    GetPowerColor = function() return { r = 1, g = 1, b = 0 } end,
    GetPowerBgDarkenFactor = function() return 0.3 end,
    ApplyModuleFont = function() end,
}

-------------------------------------------------------------------------------
--  Part A: the form bar asks for a re-anchor and reports itself while shown
-------------------------------------------------------------------------------
local NS = {
    UF_PowerPos = function() return "below" end,
    UF_Blizz = function() return false end,
    UF_Forever = function() return false end,
    UF_PowerBarDraws = function() return true end,
    UF_TexBgTint = function() end,
}
EllesmereUI.UF_RequestResourceReanchor = function() G.arms = G.arms + 1 end

local chunk = assert(loadstring(FORMBAR_SRC, "@EUI_UnitFrames_ForeverFormBar.lua"))
chunk("EllesmereUIUnitFrames", NS)
local evf = created[1]
check(evf and evf._kind == "Frame", "the file's event host is the first frame it makes")
local function Fire(event, token) evf._scripts.OnEvent(evf, event, "player", token) end

check(type(NS.UF_ForeverFormBarShown) == "function", "the form bar exports ns.UF_ForeverFormBarShown")
local Shown = NS.UF_ForeverFormBarShown or function() return nil end

local frame = MakeObj("Button", nil)
local power = MakeObj("StatusBar", frame)
local s = { powerTypeOverride = { foreverDruid = true }, foreverFormBar = true }

-- Caster form: the bar is built, stays hidden, and nothing is reserved.
NS.UF_ForeverFormBar(frame, power, s)
check(G.arms == 0, "caster form apply asks for no re-anchor (got " .. G.arms .. ")")
check(Shown() == nil, "caster form: no bar to reserve")

-- Cat Form: the bar shows and asks once.
G.pt, G.token = 3, "ENERGY"
Fire("UNIT_DISPLAYPOWER")
check(G.arms == 1, "shifting into Cat Form asks for one re-anchor (got " .. G.arms .. ")")
-- The bar the file built: the status bar it made on the player frame.
local bar
for i = 1, #created do
    local o = created[i]
    if o._kind == "StatusBar" and o._parent == frame and o ~= power then bar = o break end
end
check(bar ~= nil and bar._shown == true, "Cat Form: the bar shows")
check(bar ~= nil and Shown() == bar, "Cat Form: the shown bar is reported")
bar = bar or MakeObj("StatusBar", frame)

-- Power ticks never re-anchor.
Fire("UNIT_POWER_FREQUENT", "ENERGY")
Fire("UNIT_MAXPOWER", "ENERGY")
check(G.arms == 1, "power events ask for no re-anchor (got " .. G.arms .. ")")

-- The same form reported again changes nothing.
Fire("UNIT_DISPLAYPOWER")
check(G.arms == 1, "an unchanged form asks for no re-anchor (got " .. G.arms .. ")")

-- A restyle (reload pass) or a form bar option lays the shown bar out again.
NS.UF_ForeverFormBar(frame, power, s)
check(G.arms == 2, "re-applying a shown bar asks for a re-anchor (got " .. G.arms .. ")")
if NS.UF_ForeverFormBarRelayout then NS.UF_ForeverFormBarRelayout() end
check(G.arms == 3, "re-laying out a shown bar asks for a re-anchor (got " .. G.arms .. ")")

-- Back to caster form: the bar hides and asks once.
G.pt, G.token = 0, "MANA"
Fire("UNIT_DISPLAYPOWER")
check(G.arms == 4, "leaving Cat Form asks for one re-anchor (got " .. G.arms .. ")")
check(Shown() == nil, "caster form again: nothing reported")
check(bar._shown == false, "caster form again: the bar is hidden")

-- Re-applying the hidden bar asks nothing.
NS.UF_ForeverFormBar(frame, power, s)
if NS.UF_ForeverFormBarRelayout then NS.UF_ForeverFormBarRelayout() end
check(G.arms == 4, "re-applying a hidden bar asks for no re-anchor (got " .. G.arms .. ")")

-- Bear Form, then the option turned off while it shows.
G.pt, G.token = 1, "RAGE"
Fire("UNIT_DISPLAYPOWER")
check(G.arms == 5, "Bear Form asks for one re-anchor (got " .. G.arms .. ")")
s.foreverFormBar = nil
NS.UF_ForeverFormBar(frame, power, s)
check(G.arms == 6, "turning the option off under a shown bar asks for a re-anchor (got " .. G.arms .. ")")
check(Shown() == nil and bar._shown == false, "option off: the bar hides and nothing is reported")
NS.UF_ForeverFormBar(frame, power, s)
check(G.arms == 6, "an off option re-applied asks nothing (got " .. G.arms .. ")")
check(next(evf._events) == nil, "option off: no events registered")

-- On again in Bear Form, then a restricted power type read.
s.foreverFormBar = true
NS.UF_ForeverFormBar(frame, power, s)
check(G.arms == 7, "turning the option on in Bear Form asks for a re-anchor (got " .. G.arms .. ")")
G.pt, G.token = SECRET, SECRET
Fire("UNIT_DISPLAYPOWER")
check(G.arms == 7 and Shown() == bar, "a secret read keeps the bar and asks nothing (got " .. G.arms .. ")")
if NS.UF_ForeverFormBarRelayout then NS.UF_ForeverFormBarRelayout() end
check(G.arms == 8, "a re-layout under a secret read still asks for the shown bar (got " .. G.arms .. ")")

-------------------------------------------------------------------------------
--  Part B: ResourceStackBelowFrame (cut from the aura containers file)
-------------------------------------------------------------------------------
local function Cut(src, fromText, toText)
    local a = src:find(fromText, 1, true)
    assert(a, "anchor not found: " .. fromText)
    local b = src:find(toText, a, true)
    assert(b, "anchor not found: " .. toText)
    return src:sub(a, b - 1)
end

local NSB = {}
local EUI_B = {}
local function LoadReserve()
    local body = Cut(AURAS_SRC, "local CB_STRIP_SLACK = 8", "-- Blizzard Style: point the frame's aura block")
    local fn = assert(loadstring(body .. "\nreturn ResourceStackBelowFrame", "@ResourceStackBelowFrame"))
    setfenv(fn, setmetatable({ ns = NSB, EllesmereUI = EUI_B }, { __index = _G }))
    return fn()
end
local Reserve = LoadReserve()

local pf = MakeObj("Button", nil)
pf._l, pf._r, pf._t, pf._b = 0, 200, 140, 100
local fb = MakeObj("StatusBar", pf)
-- Docked under the power bar, sharing the border line (1 unit overlap), 10 tall.
fb._l, fb._r, fb._t, fb._b = 0, 200, 101, 91

local function Near(a, b) return math.abs(a - b) < 1e-6 end

check(Reserve("player", pf) == 0, "no stack and no form bar: no reserve")
NSB.UF_ForeverFormBarShown = function() return fb end
local r = Reserve("player", pf)
check(Near(r, 9), "a shown form bar docked under the frame is reserved without Resource Bars (got " .. tostring(r) .. ")")
check(Reserve("target", pf) == 0, "only the player frame reserves it")

NSB.UF_ForeverFormBarShown = function() return nil end
check(Reserve("player", pf) == 0, "a hidden form bar is not reserved")
NSB.UF_ForeverFormBarShown = function() return fb end

-- A Bottom Text Bar under the power bar: the form bar sits inside the frame box.
fb._t, fb._b = 117, 107
check(Reserve("player", pf) == 0, "a form bar inside the frame box is not reserved")
fb._t, fb._b = 101, 91

-- Geometry the game keeps secret degrades to no reserve.
fb._b = SECRET
check(Reserve("player", pf) == 0, "a secret form bar edge is skipped")
fb._b = 91

-- Effective scale: the reserve is in the frame's own units.
pf._scale, fb._scale = 0.5, 0.5
r = Reserve("player", pf)
check(Near(r, 9), "the reserve stays in frame units at another scale (got " .. tostring(r) .. ")")
pf._scale, fb._scale = 1, 1

-- With the Resource Bars stack: a bar docked under the form bar extends the chain;
-- a bar placed elsewhere is not reserved.
local stack = {}
EUI_B.ERB_PlayerStackBars = function()
    local out = {}
    for i = 1, #stack do out[i] = stack[i] end
    return out
end
stack[1] = { l = 0, r = 200, t = 91, b = 80 }
r = Reserve("player", pf)
check(Near(r, 20), "a Resource Bars bar docked under the form bar extends the reserve (got " .. tostring(r) .. ")")
stack[1] = { l = 0, r = 200, t = 40, b = 30 }
r = Reserve("player", pf)
check(Near(r, 9), "a Resource Bars bar elsewhere leaves the form bar's reserve alone (got " .. tostring(r) .. ")")
NSB.UF_ForeverFormBarShown = nil
stack[1] = { l = 0, r = 200, t = 100, b = 88 }
r = Reserve("player", pf)
check(Near(r, 12), "without the form bar the Resource Bars reserve is unchanged (got " .. tostring(r) .. ")")
EUI_B.ERB_PlayerStackBars = nil

-------------------------------------------------------------------------------
--  Part C: the re-anchor request is armed for the form bar without Resource Bars
-------------------------------------------------------------------------------
local NSC, EUI_C = {}, {}
local settings = { debuffAnchor = "bottomleft", buffAnchor = "topleft" }
local anchored = {}
local entryC = { frame = pf, buffs = MakeObj("Frame", pf), debuffs = MakeObj("Frame", pf) }
local throttle
local env = setmetatable({
    ns = NSC, EllesmereUI = EUI_C,
    SettingsFor = function(unit) if unit == "player" then return settings end end,
    registry = { player = entryC },
    AnchorContainer = function(container) anchored[#anchored + 1] = container end,
    CreateFrame = function(kind, name, parent)
        throttle = MakeObj(kind, parent)
        return throttle
    end,
}, { __index = _G })
local body = Cut(AURAS_SRC, "-- Resource-stack re-anchor (event-free).", "-- Dynamic unit tokens")
local fnC = assert(loadstring(body, "@ReanchorBlock"))
setfenv(fnC, env)
fnC()
local Request = EUI_C.UF_RequestResourceReanchor
check(type(Request) == "function", "the re-anchor request is published")

local function Flush()
    if throttle._shown and throttle._scripts.OnUpdate then throttle._scripts.OnUpdate(throttle) end
end

-- Retail (no form bar export) and no Resource Bars: nothing arms.
Request()
check(throttle._shown == false, "no reserve source: the request arms nothing")

-- A Forever druid without Resource Bars: the request arms one re-anchor.
NSC.UF_ForeverFormBarShown = function() return nil end
Request(); Request()
check(throttle._shown == true, "the form bar's request arms the re-anchor without Resource Bars")
Flush()
check(#anchored == 2 and anchored[1] == entryC.buffs and anchored[2] == entryC.debuffs,
    "one re-anchor of both player containers (got " .. #anchored .. ")")
check(throttle._shown == false, "the throttle hides after its one pass")

-- Auras not bottom-anchored: nothing arms.
settings.debuffAnchor = "topleft"
Request()
check(throttle._shown == false, "auras not bottom-anchored: the request arms nothing")

-- Resource Bars loaded, no form bar: unchanged behaviour.
NSC.UF_ForeverFormBarShown = nil
EUI_C.ERB_PlayerStackBars = function() return nil end
settings.debuffAnchor = "bottomright"
Request()
check(throttle._shown == true, "Resource Bars alone still arms the re-anchor")
Flush()

print(string.format("%d checks, %d failed", checks, fails))
if fails > 0 then error(fails .. " check(s) failed") end
