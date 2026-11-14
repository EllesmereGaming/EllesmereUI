-- Stub harness: Quality of Life, the Cast Bar Circle and GCD Circle set to Attach to Cursor
-- (EllesmereUIQoL_Cursor.lua).
-- Both circles are always registered with Unlock Mode, and its saved-positions pass (login, a
-- profile switch, a released Spec or Conditional Override layout, an Unlock Mode close) calls
-- every registered element's position function, mover or not. Ours moved an attached circle
-- off the cursor frame, to its old saved spot or to the middle of the screen, where it sat
-- until the feature was toggled. Both position functions now return while their circle is
-- attached: the cursor owns it.
-- Driven here: the real file, loaded whole over stubbed frames, and the position functions as
-- Unlock Mode reaches them (the registered elements' applyPosition).
--   lua .tools/tests/test_qol_cursor_attached_circle.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local SRC = ReadSource("EllesmereUIQoL/EllesmereUIQoL_Cursor.lua")

-- A fresh load of the module. setup(profile) runs between OnInitialize and OnEnable, as a
-- saved profile would stand; anchored: the keys Unlock Mode holds on an anchor link.
local function Load(setup, anchored)
    local timers, named = {}, {}
    local frameMT = {}
    frameMT.__index = function(_, k)
        local m = rawget(frameMT, k)
        if m then return m end
        if type(k) == "string" and k:sub(1, 1) == "_" then return nil end
        if k == "maxDur" or k == "dur" or k == "radius" then return nil end
        return function() end
    end
    function frameMT.SetPoint(self, point, rel, relPoint, x, y)
        if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil end
        self._pt = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        self._moves = (self._moves or 0) + 1
    end
    function frameMT.ClearAllPoints(self) self._pt = nil end
    function frameMT.SetAllPoints(self, rel) self._pt = { point = "ALL", rel = rel } end
    function frameMT.Show(self) self._shown = true end
    function frameMT.Hide(self) self._shown = false end
    function frameMT.IsShown(self) return self._shown end
    function frameMT.SetFrameLevel(self, l) self._lvl = l end
    function frameMT.GetFrameLevel(self) return self._lvl or 1 end
    function frameMT.SetSize(self, w, h) self._w, self._h = w, h end
    function frameMT.GetWidth(self) return self._w or 0 end
    function frameMT.GetHeight(self) return self._h or 0 end
    function frameMT.GetEffectiveScale() return 1 end
    function frameMT.GetLeft(self) return self._pt and 100 or nil end
    function frameMT.SetScript(self, k, fn) self._scripts = self._scripts or {}; self._scripts[k] = fn end
    function frameMT.GetScript(self, k) return self._scripts and self._scripts[k] end
    function frameMT.CreateTexture() return setmetatable({ _shown = true }, frameMT) end
    function frameMT.CreateMaskTexture() return setmetatable({ _shown = true }, frameMT) end

    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.UIParent = setmetatable({ _shown = true, _name = "UIParent" }, frameMT)
    env.CreateFrame = function(_, name, parent)
        local fr = setmetatable({ _shown = true, _name = name, _parent = parent }, frameMT)
        if name then named[name] = fr; env[name] = fr end
        return fr
    end
    env.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    env.C_Spell = { GetSpellCooldown = function() return nil end, GetSpellCooldownDuration = function() return nil end }
    env.GetCursorPosition = function() return 500, 400 end
    env.GetTime = function() return 1000 end
    env.InCombatLockdown = function() return false end
    env.GetInstanceInfo = function() return "Somewhere", "none", 0 end
    env.UnitClass = function() return "Mage", "MAGE" end
    env.IsInRaid = function() return false end
    env.IsInGroup = function() return false end
    env.issecretvalue = function() return false end
    env.hooksecurefunc = function() end
    env.UnitCastingInfo = function() return nil end
    env.UnitChannelInfo = function() return nil end
    env.GetUnitEmpowerHoldAtMaxTime = function() return 0 end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

    local addon
    local function Deep(v)
        if type(v) ~= "table" then return v end
        local o = {}
        for k, x in pairs(v) do o[k] = Deep(x) end
        return o
    end
    local elements = {}
    local EUI = {
        GCD_SPELL = 61304, _unlockActive = false,
        Lite = {
            NewAddon = function()
                addon = { RegisterEvent = function() end, UnregisterEvent = function() end }
                return addon
            end,
            NewDB = function(_, defaults) return { profile = Deep(defaults.profile) } end,
        },
        RegisterVisibilityUpdater = function() end,
        RegAccent = function() end,
        CheckVisibilityOptions = function() return false end,
        IsUnlockAnchored = function(key) return anchored and anchored[key] or false end,
        MakeUnlockElement = function(t) return t end,
        GetRawClassColor = function() return { r = 0.2, g = 0.4, b = 0.8 } end,
        GetAccentColor = function() return 0, 1, 0 end,
        PP = { SnapForES = function(v) return v end, SnapCenterForDim = function(v) return v end },
        Mouse = { Get = function() return 500, 400 end, SubscribeFrame = function() end, UnsubscribeFrame = function() end },
    }
    function EUI:RegisterUnlockElements(list)
        for _, e in ipairs(list) do
            if e.applyPos and not e.applyPosition then e.applyPosition = e.applyPos end
            elements[e.key] = e
        end
    end
    function EUI:RegisterUnlockModeListener() end
    env.EllesmereUI = EUI

    local chunk = assert(loadstring(SRC, "=EllesmereUIQoL_Cursor.lua"))
    setfenv(chunk, env)
    chunk("EllesmereUIQoL")
    addon:OnInitialize()
    local p = addon.db.profile
    setup(p)
    addon:OnEnable()
    while #timers > 0 do
        local list = timers
        timers = {}
        for _, fn in ipairs(list) do fn() end
    end
    return { env = env, elements = elements, p = p, cursor = named.EllesmereUICursorFrame,
             cast = named.ECL_CastRoot, gcd = named.ECL_GCDRoot }
end

local function Where(fr)
    local pt = fr and fr._pt
    if not pt then return "no point" end
    return ("%s -> %s %s (%s, %s)"):format(tostring(pt.point), pt.rel and (pt.rel._name or "?") or "nil",
        tostring(pt.relPoint), tostring(pt.x), tostring(pt.y))
end
local function On(fr, rel) return fr and fr._pt ~= nil and fr._pt.rel == rel end
-- Unlock Mode's saved-positions pass, for the two circles.
local function Pass(s)
    local ok1, e1 = pcall(s.elements.ECL_Cast.applyPosition, "ECL_Cast")
    local ok2, e2 = pcall(s.elements.ECL_GCD.applyPosition, "ECL_GCD")
    check(ok1 and ok2, "a circle's position function raised: " .. tostring(e1 or e2))
end

-------------------------------------------------------------------------------
-- 1. attached circles: the saved-positions pass leaves them on the cursor
-------------------------------------------------------------------------------
for _, attached in ipairs({ "true", "unset" }) do
    local s = Load(function(p)
        p.castCircle.enabled, p.gcd.enabled = true, true
        if attached == "true" then
            p.castCircle.attached, p.gcd.attached = true, true
        else
            p.castCircle.attached, p.gcd.attached = nil, nil
        end
        -- a spot saved while the cast circle was detached, in an earlier session; the GCD circle has none
        p.castCircle.pos = { point = "CENTER", relPoint = "CENTER", x = 120, y = -80 }
        p.gcd.pos = nil
    end)
    local tag = "attached " .. attached .. ": "
    check(s.cast ~= nil and s.gcd ~= nil and s.cursor ~= nil, tag .. "the circles were not built")
    check(s.elements.ECL_Cast ~= nil and s.elements.ECL_GCD ~= nil, tag .. "the circles are not registered with Unlock Mode")
    check(On(s.cast, s.cursor) and On(s.gcd, s.cursor), tag .. "the circles do not start on the cursor frame")
    check(s.elements.ECL_Cast.getFrame("ECL_Cast") == nil and s.elements.ECL_GCD.getFrame("ECL_GCD") == nil, tag .. "an attached circle offers a mover frame")
    local castMoves, gcdMoves = s.cast._moves, s.gcd._moves
    Pass(s)
    check(On(s.cast, s.cursor), tag .. "the pass moved the cast circle off the cursor: " .. Where(s.cast))
    check(On(s.gcd, s.cursor), tag .. "the pass moved the GCD circle off the cursor: " .. Where(s.gcd))
    check(s.cast._moves == castMoves and s.gcd._moves == gcdMoves, tag .. "the pass re-anchored an attached circle")
    Pass(s)
    check(On(s.cast, s.cursor) and On(s.gcd, s.cursor), tag .. "a second pass moved a circle off the cursor")
end

-------------------------------------------------------------------------------
-- 2. detached circles keep their saved spot, or the middle of the screen with none
-------------------------------------------------------------------------------
do
    local s = Load(function(p)
        p.castCircle.enabled, p.castCircle.attached = true, false
        p.castCircle.pos = { point = "CENTER", relPoint = "CENTER", x = 120, y = -80 }
        p.gcd.enabled, p.gcd.attached, p.gcd.pos = true, false, nil
    end)
    check(Where(s.cast) == "CENTER -> UIParent CENTER (120, -80)", "a detached cast circle is not at its saved spot: " .. Where(s.cast))
    check(Where(s.gcd) == "CENTER -> UIParent CENTER (0, 0)", "a detached GCD circle with no spot is not at the middle of the screen: " .. Where(s.gcd))
    -- moved by something else: the pass puts each back
    s.cast:ClearAllPoints(); s.cast:SetPoint("TOPLEFT", s.env.UIParent, "TOPLEFT", 5, -5)
    s.gcd:ClearAllPoints(); s.gcd:SetPoint("TOPLEFT", s.env.UIParent, "TOPLEFT", 5, -5)
    Pass(s)
    check(Where(s.cast) == "CENTER -> UIParent CENTER (120, -80)", "the pass does not put a detached cast circle back: " .. Where(s.cast))
    check(Where(s.gcd) == "CENTER -> UIParent CENTER (0, 0)", "the pass does not put a detached GCD circle back: " .. Where(s.gcd))
    check(s.elements.ECL_Cast.getFrame("ECL_Cast") == s.cast and s.elements.ECL_GCD.getFrame("ECL_GCD") == s.gcd, "a detached circle offers no mover frame")
    -- a saved spot on another point
    s.p.gcd.pos = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -40, y = -30 }
    Pass(s)
    check(Where(s.gcd) == "TOPRIGHT -> UIParent TOPRIGHT (-40, -30)", "a detached GCD circle does not take its saved spot: " .. Where(s.gcd))
    s.p.castCircle.pos = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 60, y = 90 }
    Pass(s)
    check(Where(s.cast) == "BOTTOMLEFT -> UIParent BOTTOMLEFT (60, 90)", "a detached cast circle does not take its saved spot: " .. Where(s.cast))
end

-------------------------------------------------------------------------------
-- 3. switching between the two, as the options do
-------------------------------------------------------------------------------
do
    local s = Load(function(p)
        p.castCircle.enabled, p.castCircle.attached = true, true
        p.gcd.enabled, p.gcd.attached = true, true
    end)
    s.p.castCircle.attached = false
    s.env._ECL_ApplyCastCircle()
    check(On(s.cast, s.env.UIParent), "a cast circle switched to detached stays on the cursor: " .. Where(s.cast))
    Pass(s)
    check(On(s.cast, s.env.UIParent) and On(s.gcd, s.cursor), "the pass does not treat each circle by its own setting")
    s.p.castCircle.attached = true
    s.env._ECL_ApplyCastCircle()
    check(On(s.cast, s.cursor), "a cast circle switched back to attached is not on the cursor: " .. Where(s.cast))
    Pass(s)
    check(On(s.cast, s.cursor), "the pass moved a re-attached cast circle off the cursor")
    s.p.gcd.attached = false
    s.env._ECL_ApplyGCDCircle()
    check(On(s.gcd, s.env.UIParent), "a GCD circle switched to detached stays on the cursor: " .. Where(s.gcd))
end

-------------------------------------------------------------------------------
-- 4. a detached circle held by an Unlock Mode anchor link is left to the link;
--    a circle that was never built is no error
-------------------------------------------------------------------------------
do
    local s = Load(function(p)
        p.castCircle.enabled, p.castCircle.attached = true, false
        p.castCircle.pos = { point = "CENTER", relPoint = "CENTER", x = 120, y = -80 }
        p.gcd.enabled, p.gcd.attached = true, false
    end, { ECL_Cast = true })
    s.cast:ClearAllPoints(); s.cast:SetPoint("TOPLEFT", s.env.UIParent, "TOPLEFT", 5, -5)
    Pass(s)
    check(Where(s.cast) == "TOPLEFT -> UIParent TOPLEFT (5, -5)", "a linked cast circle was moved to its saved spot: " .. Where(s.cast))

    -- switched off and detached: nothing is built, and the pass has nothing to place
    local off = Load(function(p)
        p.castCircle.enabled, p.castCircle.attached = false, false
        p.gcd.enabled, p.gcd.attached = false, false
    end)
    check(off.cast == nil and off.gcd == nil, "a circle that is switched off was built")
    local ok1 = pcall(off.env._ECL_ApplyCastPosition)
    local ok2 = pcall(off.env._ECL_ApplyGCDPosition)
    check(ok1 and ok2, "placing a circle that was never built raised an error")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_qol_cursor_attached_circle (%d checks)"):format(count))
