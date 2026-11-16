-- Player Aura Bars: the Visibility section of the default Buffs and Debuffs bars.
-- Loads the real EllesmereUI_VisibilityRules.lua and EllesmereUI_Visibility.lua (the shared
-- dispatcher and mouseover scan) and the real EUI_PlayerAuraBars_Bars.lua and
-- EUI_PlayerAuraBars_Visibility.lua over stubs, with bar parents that refuse Show and Hide in
-- combat (as a parent of the engine's aura container does) and a stand-in for the secure state
-- driver that evaluates its macro string. What a player gets is read as "seen" (shown, alpha
-- above 0), "hidden" (really hidden: no mouse) or "ghost" (shown at alpha 0).
--   A  a selection made only of combat conditions is a driver that shows and hides
--   B  a condition that changes during combat shows the bar at once (target, mount)
--   C  an option beside a combat condition counts
--   D  settings changed in combat
--   E  Mouseover reveals in combat too
--   F  suppression wins over the escape driver
--   G  nothing set costs nothing; Hidden Opacity above 0 only dims
--   H  the sync reaches the Bars file through a setter; the TOC and the standalone list
--   I  the options rows run the visibility pass alone
-- What no harness can show: that the game's own state driver may show and hide this parent
-- in combat. Run from the repository root.
-- World state the stubs read, and a state driver that evaluates its macro string the way the
-- secure driver does: clauses split by ";", each "[a,b][c] action" (bracket groups are OR, the
-- terms inside one are AND; no brackets = always), the first true clause decides show / hide.
WORLD = { target = false, mounted = false, raid = false, party = false }
local combatNow = function() return false end
function SetCombatReader(fn) combatNow = fn end
DRIVERS = {}          -- frame -> its registered string
DRIVER_LOG = {}       -- every register / unregister, in order
local function Term(t)
    if t == "combat" then return combatNow() end
    if t == "nocombat" then return not combatNow() end
    if t == "mounted" then return WORLD.mounted end
    if t == "nomounted" then return not WORLD.mounted end
    if t == "exists" or t == "@target,exists" then return WORLD.target end
    if t == "noexists" then return not WORLD.target end
    if t == "group:raid" then return WORLD.raid end
    if t == "nogroup:raid" then return not WORLD.raid end
    if t == "group:party" then return WORLD.party or WORLD.raid end
    if t == "nogroup" then return not WORLD.party and not WORLD.raid end
    error("the stub driver does not know the macro term " .. tostring(t))
end
local function Eval(str)
    for clause in (str .. ";"):gmatch("([^;]*);") do
        clause = clause:gsub("^%s+", ""):gsub("%s+$", "")
        if clause ~= "" then
            local action = clause:match("([%a]+)$")
            local groups, any = {}, false
            for g in clause:gmatch("%[([^%]]*)%]") do groups[#groups + 1] = g end
            if #groups == 0 then
                any = true
            else
                for _, g in ipairs(groups) do
                    local all = true
                    for term in (g .. ","):gmatch("([^,]*),") do
                        if term ~= "" and not Term(term) then all = false end
                    end
                    if all then any = true end
                end
            end
            if any then return action end
        end
    end
end
function RunDrivers()
    for frame, str in pairs(DRIVERS) do
        local a = Eval(str)
        if a == "show" then frame._shown = true elseif a == "hide" then frame._shown = false end
    end
end
function RegisterStateDriver(frame, state, str)
    assert(state == "visibility")
    assert(not combatNow(), "RegisterStateDriver called in combat")
    DRIVERS[frame] = str
    DRIVER_LOG[#DRIVER_LOG + 1] = "register " .. str
    RunDrivers()
end
function UnregisterStateDriver(frame, state)
    assert(not combatNow(), "UnregisterStateDriver called in combat")
    if DRIVERS[frame] then DRIVER_LOG[#DRIVER_LOG + 1] = "unregister" end
    DRIVERS[frame] = nil
end
issecretvalue = function() return false end
local function Read(p) local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s end
local function Load(p, ...) return assert(loadstring(Read(p), "=" .. p))(...) end

local results = {}
local function check(name, cond, extra)
    results[#results + 1] = (cond and "ok   " or "FAIL ") .. name .. (extra and ("  [" .. tostring(extra) .. "]") or "")
    if not cond then results.failed = true end
end

-- ---------------------------------------------------------------- stubs
local combat = false
local timers = {}
_G.InCombatLockdown = function() return combat end
_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function Flush()
    for _ = 1, 5 do
        local t = timers; timers = {}
        if #t == 0 then return end
        for i = 1, #t do t[i]() end
    end
end
local allFrames = {}
local function NewFrame(name)
    local f = { _name = name, _shown = true, _alpha = 1, _events = {}, _scripts = {}, setAlphaCalls = 0,
        rect = { 100, 100, 200, 40 }, scale = 1 }
    function f:RegisterEvent(e) self._events[e] = true end
    function f:RegisterUnitEvent(e) self._events[e] = true end
    function f:UnregisterAllEvents() self._events = {} end
    function f:SetScript(k, fn) self._scripts[k] = fn end
    function f:IsShown() return self._shown end
    function f:SetShown(v) self._shown = v and true or false end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:GetAlpha() return self._alpha end
    function f:SetAlpha(a) self._alpha = a; self.setAlphaCalls = self.setAlphaCalls + 1 end
    function f:GetRect() return self.rect[1], self.rect[2], self.rect[3], self.rect[4] end
    function f:GetEffectiveScale() return self.scale end
    allFrames[#allFrames + 1] = f
    return f
end
_G.CreateFrame = function(_, name) return NewFrame(name) end
_G.C_EventUtils = { IsEventValid = function() return true end }
_G.IsInGroup = function() return false end
_G.IsInRaid = function() return false end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.IsFlying = function() return false end
_G.IsMounted = function() return WORLD.mounted end
_G.UnitExists = function(u) return u == "target" and WORLD.target or false end
_G.IsResting = function() return false end
_G.UnitInVehicle = function() return false end
local ticks = {}
_G.EllesmereUI = {
    Mouse = {
        SubscribeTick = function(k, _, fn) ticks[k] = fn end,
        UnsubscribeTick = function(k) ticks[k] = nil end,
    },
}
local EUI = _G.EllesmereUI

Load("EllesmereUI_VisibilityRules.lua")
Load("EllesmereUI_Visibility.lua")
local visFrame = allFrames[1]
assert(visFrame and visFrame._scripts.OnEvent, "dispatcher frame not captured")

-- Count updater and mouseover registrations (the PAB file calls these at run time).
local regUpd, unregUpd, regMo, unregMo = 0, 0, 0, 0
do
    local r, u, rm, um = EUI.RegisterVisibilityUpdater, EUI.UnregisterVisibilityUpdater,
        EUI.RegisterMouseoverTarget, EUI.UnregisterMouseoverTarget
    EUI.RegisterVisibilityUpdater = function(fn) regUpd = regUpd + 1; return r(fn) end
    EUI.UnregisterVisibilityUpdater = function(fn) unregUpd = unregUpd + 1; return u(fn) end
    EUI.RegisterMouseoverTarget = function(...) regMo = regMo + 1; return rm(...) end
    EUI.UnregisterMouseoverTarget = function(...) unregMo = unregMo + 1; return um(...) end
end

-- ---------------------------------------------------------------- PAB chain
local function NewChain(strictAfterLoad, withVisFile)
    local s = { enabled = true, defaultBuffs = {}, defaultDebuffs = {} }
    local strict = false
    local raw = {
        broken = false,
        PAB = function() return s end,
        DefaultBuffsCfg = function(st) return st.defaultBuffs end,
        DefaultDebuffsCfg = function(st) return st.defaultDebuffs end,
        buffsParentSetters = {}, debuffsParentSetters = {}, pabSuppressedSetters = {},
        syncVisibilitySetters = {},
    }
    local function Fan(listName) return function(v) local l = raw[listName]; for i = 1, #l do l[i](v) end end end
    raw.SetBuffsParent = Fan("buffsParentSetters")
    raw.SetDebuffsParent = Fan("debuffsParentSetters")
    raw.SetPabSuppressed = Fan("pabSuppressedSetters")
    raw.SetSyncVisibility = Fan("syncVisibilitySetters")
    local I = setmetatable(raw, { __index = function(t, k)
        if strict then error("ns._pabInternals has no entry " .. tostring(k), 2) end
        local v = (type(k) == "string" and k:match("Setters$")) and {} or function() end
        rawset(t, k, v)
        return v
    end })
    local queued = {}
    local ns = { _pabInternals = I, CombatQueue = { Defer = function(k, fn) queued[k] = fn end } }
    Load("EllesmereUIUnitFrames/EUI_PlayerAuraBars_Bars.lua", "EllesmereUIUnitFrames", ns)
    assert(I.broken == false, "Bars did not finish loading")
    if withVisFile then
        Load("EllesmereUIUnitFrames/EUI_PlayerAuraBars_Visibility.lua", "EllesmereUIUnitFrames", ns)
        assert(I.broken == false, "Visibility did not finish loading")
    end
    if strictAfterLoad then strict = true end
    local bp, dp = NewFrame("buffs"), NewFrame("debuffs")
    I.SetBuffsParent(bp); I.SetDebuffsParent(dp)
    return { s = s, I = I, ns = ns, bp = bp, dp = dp, queued = queued }
end

local function Apply(c) c.I.ApplyDefaultBarShown(true); c.I.ApplyDefaultBarShown(false) end
local function Event(e)
    if e == "PLAYER_REGEN_DISABLED" then combat = true elseif e == "PLAYER_REGEN_ENABLED" then combat = false end
    visFrame._scripts.OnEvent(visFrame, e)
    Flush()
end

SetCombatReader(function() return combat end)

-- A chain whose bar parents refuse Show / Hide in combat, as a parent of the engine's aura
-- container does (the refusals are counted), and whose deferred work runs at combat end.
local function Chain()
    local c = NewChain(true, true)
    c.blocked = 0
    for _, p in ipairs({ c.bp, c.dp }) do
        function p:Show() if combat then c.blocked = c.blocked + 1 return end self._shown = true end
        function p:Hide() if combat then c.blocked = c.blocked + 1 return end self._shown = false end
        function p:SetShown(v) if v then self:Show() else self:Hide() end end
    end
    return c
end
local function Combat(c, on)
    Event(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    RunDrivers()
    if not on then
        for _ = 1, 3 do
            local q = c.queued
            local list = {}
            for k, fn in pairs(q) do list[#list + 1] = fn; q[k] = nil end
            for _, fn in ipairs(list) do fn() end
        end
        RunDrivers()
    end
end
-- What the player gets: "seen" (shown at alpha > 0), "hidden" (really hidden: no mouse),
-- or "ghost" (shown at alpha 0: invisible but takes the mouse).
local function State(p)
    if not p._shown then return "hidden" end
    if p._alpha == 0 then return "ghost" end
    return "seen"
end
local function Fire(e) visFrame._scripts.OnEvent(visFrame, e); Flush(); RunDrivers() end
local function Registers(str)
    local n = 0
    for i = 1, #DRIVER_LOG do if DRIVER_LOG[i] == "register " .. str then n = n + 1 end end
    return n
end
local ESCAPE = "[combat] show"

print("--- A. a selection made only of combat conditions: the driver shows and hides")
do
    local c = Chain()
    c.s.defaultBuffs.visibility = "in_combat"
    Apply(c)
    check("A1 In Combat at 0, out of combat: really hidden", State(c.bp) == "hidden", State(c.bp))
    check("A1 the exact driver owns it", DRIVERS[c.bp] == "[combat] show; hide", tostring(DRIVERS[c.bp]))
    Combat(c, true)
    check("A1 in combat: seen", State(c.bp) == "seen", State(c.bp))
    Combat(c, false)
    check("A1 after combat: really hidden again", State(c.bp) == "hidden", State(c.bp))
    check("A1 no Show / Hide refused in combat", c.blocked == 0, c.blocked)

    c = Chain()
    c.s.defaultBuffs.visibility = "out_of_combat"
    Apply(c)
    check("A2 Out of Combat at 0: seen out of combat", State(c.bp) == "seen", State(c.bp))
    check("A2 the exact driver owns it", DRIVERS[c.bp] == "[nocombat] show; hide", tostring(DRIVERS[c.bp]))
    Combat(c, true)
    check("A2 in combat: really hidden (the driver hides it)", State(c.bp) == "hidden", State(c.bp))
    Combat(c, false)
    check("A2 after combat: seen", State(c.bp) == "seen", State(c.bp))

    local r0, m0 = regUpd, regMo
    c = Chain()
    c.s.defaultBuffs.visibility = "in_combat"
    c.s.defaultBuffs.enabled = false
    Apply(c)
    check("A3 switched-off bar: no updater, no driver", regUpd == r0 and DRIVERS[c.bp] == nil, (regUpd - r0) .. " " .. tostring(DRIVERS[c.bp]))
    check("A3 switched-off bar: parent hidden", State(c.bp) == "hidden", State(c.bp))
    c = Chain()
    c.s.defaultBuffs.visHideNoTarget = true
    c.s.defaultBuffs.enabled = false
    WORLD.target = false
    Apply(c)
    check("A3 switched-off bar with an option: no driver either", DRIVERS[c.bp] == nil, tostring(DRIVERS[c.bp]))
    c = Chain()
    c.s.defaultBuffs.visibility = "mouseover"
    c.s.enabled = false
    Apply(c)
    check("A4 Player Aura Bars off: no updater, no mouseover target", regUpd == r0 and regMo == m0, (regUpd - r0) .. " " .. (regMo - m0))
    c = Chain()
    c.s.defaultBuffs.visibility = "in_combat"
    c.s.useBlizzardBuffs = true
    Apply(c)
    check("A5 Use Blizzard Buffs: no updater, no driver", regUpd == r0 and DRIVERS[c.bp] == nil, (regUpd - r0) .. " " .. tostring(DRIVERS[c.bp]))
end

print("--- B. a condition that changes DURING combat, at Hidden Opacity 0 (the default)")
do
    -- Hide Without Target: no target at the pull, then the player targets the boss
    local c = Chain()
    c.s.defaultBuffs.visHideNoTarget = true
    WORLD.target = false
    local reg0 = Registers(ESCAPE)
    Apply(c)
    check("B1 Hide Without Target, no target, out of combat: really hidden", State(c.bp) == "hidden", State(c.bp))
    check("B1 the escape driver is registered", DRIVERS[c.bp] == ESCAPE, tostring(DRIVERS[c.bp]))
    check("B1 the Debuffs bar, with nothing set, has no driver", DRIVERS[c.dp] == nil, tostring(DRIVERS[c.dp]))
    Combat(c, true)
    check("B1 at the pull the parent is shown but invisible", State(c.bp) == "ghost", State(c.bp))
    WORLD.target = true
    Fire("PLAYER_TARGET_CHANGED")
    check("B1 in combat, target taken: the Buffs bar is seen", State(c.bp) == "seen", State(c.bp))
    WORLD.target = false
    Fire("PLAYER_TARGET_CHANGED")
    check("B1 in combat, target lost: invisible again", State(c.bp) == "ghost", State(c.bp))
    WORLD.target = true
    Fire("PLAYER_TARGET_CHANGED")
    check("B1 in combat, target taken again: seen", State(c.bp) == "seen", State(c.bp))
    check("B1 nothing was refused in combat", c.blocked == 0, c.blocked)
    WORLD.target = false
    Fire("PLAYER_TARGET_CHANGED")
    Combat(c, false)
    check("B1 combat ends with no target: really hidden", State(c.bp) == "hidden", State(c.bp))
    WORLD.target = true
    Fire("PLAYER_TARGET_CHANGED")
    check("B1 out of combat, target taken: seen", State(c.bp) == "seen", State(c.bp))
    WORLD.target = false
    Fire("PLAYER_TARGET_CHANGED")
    check("B1 out of combat, target lost: really hidden", State(c.bp) == "hidden", State(c.bp))
    check("B1 the escape driver was registered once through all of it", Registers(ESCAPE) == reg0 + 1, Registers(ESCAPE) - reg0)
    check("B1 nothing was refused at all", c.blocked == 0, c.blocked)

    -- a target at the pull, lost in the fight, the fight ends without one
    c = Chain()
    c.s.defaultBuffs.visHideNoTarget = true
    WORLD.target = true
    Apply(c)
    check("B2 a target, out of combat: seen", State(c.bp) == "seen", State(c.bp))
    Combat(c, true)
    WORLD.target = false
    Fire("PLAYER_TARGET_CHANGED")
    check("B2 in combat, target lost: invisible", State(c.bp) == "ghost", State(c.bp))
    Combat(c, false)
    check("B2 after combat with no target: really hidden", State(c.bp) == "hidden", State(c.bp))

    -- no target for the whole fight: the parent the escape driver showed is hidden again
    c = Chain()
    c.s.defaultBuffs.visHideNoTarget = true
    WORLD.target = false
    Apply(c)
    Combat(c, true)
    check("B5 no target through the fight: invisible", State(c.bp) == "ghost", State(c.bp))
    check("B5 nothing is waiting for combat to end", next(c.queued) == nil)
    Combat(c, false)
    check("B5 after the fight: really hidden", State(c.bp) == "hidden", State(c.bp))

    -- a condition with no combat part and no option (In Raid Group, while solo)
    c = Chain()
    c.s.defaultBuffs.visibility = "in_raid"
    Apply(c)
    check("B6 In Raid Group while solo: really hidden behind the escape driver",
        State(c.bp) == "hidden" and DRIVERS[c.bp] == ESCAPE, State(c.bp) .. " " .. tostring(DRIVERS[c.bp]))
    Combat(c, true)
    check("B6 in combat: still not seen", State(c.bp) == "ghost", State(c.bp))
    Combat(c, false)
    check("B6 after combat: really hidden", State(c.bp) == "hidden", State(c.bp))

    -- the same at Hidden Opacity 10 (the alpha path): no driver, never hidden
    c = Chain()
    c.s.defaultBuffs.visHideNoTarget = true
    c.s.defaultBuffs.hiddenOpacity = 10
    WORLD.target = false
    Apply(c)
    check("B3 at Hidden Opacity 10: dimmed, shown, no driver", math.abs(c.bp._alpha - 0.1) < 1e-9 and c.bp._shown and DRIVERS[c.bp] == nil,
        tostring(c.bp._alpha) .. " " .. tostring(DRIVERS[c.bp]))
    Combat(c, true)
    WORLD.target = true
    Fire("PLAYER_TARGET_CHANGED")
    check("B3 in combat with a target: full alpha", State(c.bp) == "seen" and c.bp._alpha == 1, State(c.bp) .. " " .. tostring(c.bp._alpha))
    Combat(c, false)
    WORLD.target = false

    -- Hide While Mounted: mounted at the pull, dismounted by the fight
    c = Chain()
    c.s.defaultBuffs.visHideMounted = true
    WORLD.mounted, WORLD.target = true, false
    Apply(c)
    check("B4 Hide While Mounted, mounted: really hidden", State(c.bp) == "hidden", State(c.bp))
    Combat(c, true)
    WORLD.mounted = false
    Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    check("B4 in combat, dismounted: the Buffs bar is seen", State(c.bp) == "seen", State(c.bp))
    Combat(c, false)
    check("B4 after combat, on foot: seen", State(c.bp) == "seen", State(c.bp))
    WORLD.mounted = true
    Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    check("B4 mounted again out of combat: really hidden", State(c.bp) == "hidden", State(c.bp))
    WORLD.mounted = false
end

print("--- C. a combat condition together with an option, at Hidden Opacity 0")
do
    local c = Chain()
    c.s.defaultBuffs.visibility = "in_combat"
    c.s.defaultBuffs.visHideNoTarget = true
    WORLD.target = false
    Apply(c)
    check("C1 In Combat + Hide Without Target: the escape driver, not the combat string", DRIVERS[c.bp] == ESCAPE, tostring(DRIVERS[c.bp]))
    check("C1 out of combat: really hidden", State(c.bp) == "hidden", State(c.bp))
    Combat(c, true)
    check("C1 in combat with NO target: not seen", State(c.bp) == "ghost", State(c.bp))
    WORLD.target = true
    Fire("PLAYER_TARGET_CHANGED")
    check("C1 in combat with a target: seen", State(c.bp) == "seen", State(c.bp))
    Combat(c, false)
    check("C1 after combat: really hidden", State(c.bp) == "hidden", State(c.bp))
    WORLD.target = false

    c = Chain()
    c.s.defaultBuffs.visibility = "in_combat"
    c.s.defaultBuffs.visHideNoTarget = true
    c.s.defaultBuffs.hiddenOpacity = 10
    Apply(c)
    Combat(c, true)
    check("C2 the same at Hidden Opacity 10: dimmed in combat with no target", math.abs(c.bp._alpha - 0.1) < 1e-9, c.bp._alpha)
    Combat(c, false)

    c = Chain()
    c.s.defaultBuffs.visibility = "out_of_combat"
    c.s.defaultBuffs.visHideMounted = true
    WORLD.mounted = true
    Apply(c)
    check("C3 Out of Combat + Hide While Mounted, mounted out of combat: really hidden", State(c.bp) == "hidden", State(c.bp))
    WORLD.mounted = false
    Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    check("C3 on foot out of combat: seen", State(c.bp) == "seen", State(c.bp))
    Combat(c, true)
    check("C3 in combat: not seen", State(c.bp) ~= "seen", State(c.bp))
    Combat(c, false)
    check("C3 after combat: seen", State(c.bp) == "seen", State(c.bp))
    check("C3 nothing was refused", c.blocked == 0, c.blocked)
end

print("--- D. settings changed in combat")
do
    local c = Chain()
    c.s.defaultBuffs.visibility = "in_combat"
    Apply(c)
    Combat(c, true)
    c.s.defaultBuffs.visibility = "always"      -- a profile or override flip mid-fight
    local ok, err = pcall(Apply, c)
    check("D1 a selection change in combat raises nothing", ok, err)
    check("D1 the driver is still registered until combat ends", DRIVERS[c.bp] ~= nil)
    Combat(c, false)
    check("D1 after combat the driver is gone and the bar is seen", DRIVERS[c.bp] == nil and State(c.bp) == "seen", tostring(DRIVERS[c.bp]) .. " " .. State(c.bp))
    check("D1 nothing was refused in combat", c.blocked == 0, c.blocked)

    -- an option ticked mid-fight on a bar with nothing set: alpha now, the real hide at combat end
    c = Chain()
    WORLD.target = false
    Apply(c)
    Combat(c, true)
    c.s.defaultBuffs.visHideNoTarget = true
    ok, err = pcall(Apply, c)
    check("D2 an option ticked in combat raises nothing", ok, err)
    check("D2 no driver is registered in combat", DRIVERS[c.bp] == nil, tostring(DRIVERS[c.bp]))
    check("D2 the bar is invisible at once", State(c.bp) == "ghost", State(c.bp))
    Combat(c, false)
    check("D2 after combat: the escape driver is in and the bar really hidden", DRIVERS[c.bp] == ESCAPE and State(c.bp) == "hidden",
        tostring(DRIVERS[c.bp]) .. " " .. State(c.bp))

    -- back to nothing set: the driver goes, the bar is handed back
    c.s.defaultBuffs.visHideNoTarget = nil
    Apply(c)
    check("D3 the option unticked: no driver, seen, full alpha", DRIVERS[c.bp] == nil and State(c.bp) == "seen" and c.bp._alpha == 1,
        tostring(DRIVERS[c.bp]) .. " " .. State(c.bp))
end

print("--- E. Mouseover at Hidden Opacity 0")
do
    local c = Chain()
    c.s.defaultBuffs.visibility = "mouseover"
    Apply(c)
    local scan = ticks.visMouseover
    scan(10, 10)
    check("E1 not hovered, out of combat: really hidden", State(c.bp) == "hidden", State(c.bp))
    check("E1 the escape driver is registered", DRIVERS[c.bp] == ESCAPE, tostring(DRIVERS[c.bp]))
    scan(150, 120)
    check("E1 hovered out of combat: seen", State(c.bp) == "seen", State(c.bp))
    scan(10, 10)
    check("E1 left: really hidden", State(c.bp) == "hidden", State(c.bp))
    Combat(c, true)
    scan(10, 10)
    check("E2 in combat, not hovered: invisible", State(c.bp) == "ghost", State(c.bp))
    scan(150, 120)
    check("E2 in combat, hovered: seen", State(c.bp) == "seen", State(c.bp))
    scan(10, 10)
    check("E2 in combat, left: invisible", State(c.bp) == "ghost", State(c.bp))
    check("E2 nothing was refused in combat", c.blocked == 0, c.blocked)
    Combat(c, false)
    scan(10, 10)
    check("E2 after combat: really hidden", State(c.bp) == "hidden", State(c.bp))
    c.s.defaultBuffs.visibility = nil
    Apply(c)

    -- Mouseover ticked together with In Combat: hover decides, so no combat string
    c = Chain()
    c.s.defaultBuffs.visibilityModes = { mouseover = true, in_combat = true }
    Apply(c)
    scan = ticks.visMouseover
    scan(10, 10)
    check("E3 Mouseover with In Combat: the escape driver, never a combat string", DRIVERS[c.bp] == ESCAPE, tostring(DRIVERS[c.bp]))
    Combat(c, true)
    scan(150, 120)
    check("E3 in combat, hovered: seen", State(c.bp) == "seen", State(c.bp))
    check("E3 nothing was refused", c.blocked == 0, c.blocked)
    scan(10, 10)
    Combat(c, false)
    c.s.defaultBuffs.visibilityModes = nil
    Apply(c)
end

print("--- F. suppression (a vehicle ride) wins over the escape driver's Show")
do
    local c = Chain()
    c.s.defaultBuffs.visHideNoTarget = true
    WORLD.target = true
    Apply(c)
    c.I.SetPabSuppressed(true)
    Apply(c)
    check("F1 suppressed out of combat: invisible", c.bp._alpha == 0, c.bp._alpha)
    Combat(c, true)
    check("F1 suppressed in combat: still invisible", c.bp._alpha == 0, c.bp._alpha)
    Combat(c, false)
    c.I.SetPabSuppressed(false)
    Apply(c)
    check("F1 lifted: seen", State(c.bp) == "seen", State(c.bp))
    WORLD.target = false
end


print("--- G. the basics: nothing set costs nothing; Hidden Opacity above 0 only dims")
do
    local r0, u0, m0, um0 = regUpd, unregUpd, regMo, unregMo
    local c = Chain()
    Apply(c)
    check("G1 nothing set: full alpha, shown", c.bp._alpha == 1 and c.bp._shown, c.bp._alpha)
    check("G1 nothing set: no updater, no mouseover target, no driver",
        regUpd == r0 and regMo == m0 and DRIVERS[c.bp] == nil and DRIVERS[c.dp] == nil, (regUpd - r0) .. " " .. (regMo - m0))

    c.s.defaultBuffs.visibility = "in_combat"
    c.s.defaultBuffs.hiddenOpacity = 10
    Apply(c)
    check("G2 In Combat at 10, out of combat: alpha 0.1, still shown, no driver",
        math.abs(c.bp._alpha - 0.1) < 1e-9 and c.bp._shown and DRIVERS[c.bp] == nil, c.bp._alpha)
    check("G2 the Debuffs bar is untouched", c.dp._alpha == 1 and c.dp._shown, c.dp._alpha)
    check("G2 the updater is registered once", regUpd == r0 + 1, regUpd - r0)
    Apply(c)
    check("G2 a second apply registers nothing more", regUpd == r0 + 1, regUpd - r0)
    Combat(c, true)
    check("G2 in combat: full alpha", c.bp._alpha == 1, c.bp._alpha)
    Combat(c, false)
    check("G2 after combat: 0.1 again", math.abs(c.bp._alpha - 0.1) < 1e-9, c.bp._alpha)

    c.I.SetPabSuppressed(true)
    Apply(c)
    check("G3 suppressed: alpha 0", c.bp._alpha == 0, c.bp._alpha)
    Combat(c, true)
    check("G3 suppressed in combat: still 0", c.bp._alpha == 0, c.bp._alpha)
    Combat(c, false)
    c.I.SetPabSuppressed(false)
    Apply(c)
    check("G3 lifted: back to 0.1", math.abs(c.bp._alpha - 0.1) < 1e-9, c.bp._alpha)

    c.s.defaultBuffs.visibility = "mouseover"
    c.s.defaultBuffs.hiddenOpacity = 20
    Apply(c)
    local scan = ticks.visMouseover
    scan(10, 10)
    check("G4 Mouseover at 20: one target, dimmed, shown, no driver",
        regMo == m0 + 1 and math.abs(c.bp._alpha - 0.2) < 1e-9 and c.bp._shown and DRIVERS[c.bp] == nil, c.bp._alpha)
    scan(150, 120)
    check("G4 hovered: full alpha", c.bp._alpha == 1, c.bp._alpha)
    scan(10, 10)
    check("G4 left: 0.2 again", math.abs(c.bp._alpha - 0.2) < 1e-9, c.bp._alpha)

    c.s.defaultBuffs.visibility = nil
    c.s.defaultBuffs.hiddenOpacity = nil
    Apply(c)
    check("G5 back to nothing set: full alpha, updater and target unregistered",
        c.bp._alpha == 1 and unregUpd == u0 + 1 and unregMo == um0 + 1, (unregUpd - u0) .. " " .. (unregMo - um0))

    -- a bar switched off in combat keeps alpha 0 whatever the dim says
    c.s.defaultBuffs.visibility = "in_combat"
    c.s.defaultBuffs.hiddenOpacity = 50
    Apply(c)
    combat = true
    c.s.useBlizzardBuffs = true
    Apply(c)
    check("G6 Use Blizzard Buffs turned on in combat: alpha 0", c.bp._alpha == 0, c.bp._alpha)
    combat = false
    c.s.useBlizzardBuffs = nil
    c.s.defaultBuffs.visibility = nil
    c.s.defaultBuffs.hiddenOpacity = nil
    Apply(c)
end

print("--- H. the files hand the sync over through a setter")
do
    -- the Bars file alone (a build without the Visibility file): the bars still apply
    local c = NewChain(true, false)
    local ok, err = pcall(c.I.ApplyDefaultBarShown, true)
    check("H1 without the Visibility file, the default bars still apply", ok, err)
    check("H1 and nothing is registered", DRIVERS[c.bp] == nil)

    local main = Read("EllesmereUIUnitFrames/EllesmereUIUnitFrames_PlayerAuraBars.lua")
    check("H2 the internals table holds the setter list", main:find("syncVisibilitySetters = {}", 1, true) ~= nil)
    check("H2 and builds its fan-out", main:find('SetSyncVisibility = "syncVisibilitySetters"', 1, true) ~= nil)
    local bars = Read("EllesmereUIUnitFrames/EUI_PlayerAuraBars_Bars.lua")
    check("H2 the Bars file never reads the sync off the internals table", bars:find("I.SyncVisibility", 1, true) == nil)

    local c3 = Chain()
    Apply(c3)
    check("H4 the options' entry point is published", type(c3.ns.PAB_SyncVisibility) == "function")
    c3.s.defaultBuffs.visibility = "in_combat"
    c3.s.defaultBuffs.hiddenOpacity = 10
    c3.ns.PAB_SyncVisibility()
    check("H4 and it applies a changed selection by itself", math.abs(c3.bp._alpha - 0.1) < 1e-9, c3.bp._alpha)
    c3.s.defaultBuffs.visibility = nil
    c3.s.defaultBuffs.hiddenOpacity = nil
    c3.ns.PAB_SyncVisibility()
    check("H4 and hands the bar back", c3.bp._alpha == 1, c3.bp._alpha)

    local toc = Read("EllesmereUIUnitFrames/EllesmereUIUnitFrames.toc"):gsub("\r", "")
    check("H3 the TOC loads the Visibility file right after the Bars file",
        toc:find("\nEUI_PlayerAuraBars_Bars.lua\nEUI_PlayerAuraBars_Visibility.lua\n", 1, true) ~= nil)
    local f = io.open("build-standalone.ps1", "rb")
    if f then
        local ps = f:read("*a"); f:close()
        check("H3 the standalone build ships it, in the same place",
            ps:find('"EUI_PlayerAuraBars_Bars.lua", "EUI_PlayerAuraBars_Visibility.lua", "EUI_PlayerAuraBars_Filters.lua"', 1, true) ~= nil)
    end
end

print("--- I. the options rows run the visibility pass alone")
do
    local src = Read("EllesmereUIOptions/EUI_PlayerAuraBars_ManagerPages.lua"):gsub("\r", "")
    local a = src:find("local function BuildVisibilityFields(", 1, true)
    local b = a and src:find("\n    return sy\nend\n", a, true)
    check("I0 the section builder is found", a and b)
    local body = src:sub(a, b + #"\n    return sy\nend")
    local chunk = assert(loadstring("local ns = ...\n" .. body .. "\nreturn BuildVisibilityFields", "=BuildVisibilityFields"))
    local calls = { sync = 0, restyle = 0, live = 0 }
    local nsO = {
        PAB_SyncVisibility = function() calls.sync = calls.sync + 1 end,
        PAB_Restyle = function() calls.restyle = calls.restyle + 1 end,
        PAB_ApplyLiveConfig = function() calls.live = calls.live + 1 end,
    }
    local got = {}
    local keepW, keepRow = EUI.Widgets, EUI.BuildVisibilityRow
    EUI.Widgets = { SectionHeader = function(_, _, title) got.header = title; return nil, 30 end }
    EUI.BuildVisibilityRow = function(_, _, _, opts, right) got.opts, got.right = opts, right; return nil, 50 end
    local Build = chunk(nsO)
    local cfg = {}
    local sy = Build({}, "font", -100, cfg)
    EUI.Widgets, EUI.BuildVisibilityRow = keepW, keepRow
    check("I1 the section is VISIBILITY and takes its two rows' height", got.header == "VISIBILITY" and sy == -180, tostring(sy))
    check("I1 the row edits the bar's own table under the key visibility",
        got.opts and got.opts.getStore() == cfg and got.opts.legacyKey == "visibility")
    got.opts.onChanged()
    got.opts.onOptionChanged()
    check("I2 a Visibility pick runs the visibility pass, twice for two writes", calls.sync == 2, calls.sync)
    check("I3 Hidden Opacity reads 0 while unset", got.right.getValue() == 0, got.right.getValue())
    got.right.setValue(35)
    check("I3 the slider writes the bar's table and runs the pass", cfg.hiddenOpacity == 35 and calls.sync == 3, calls.sync)
    check("I4 no row restyles the bar", calls.restyle == 0 and calls.live == 0, calls.restyle .. " " .. calls.live)
    nsO.PAB_SyncVisibility = nil
    check("I5 with the runtime file missing a write raises nothing", pcall(got.right.setValue, 40) and cfg.hiddenOpacity == 40)
end

for i = 1, #results do print(results[i]) end
if results.failed then error("a check failed") end
