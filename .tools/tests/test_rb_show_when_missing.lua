-- Stub harness: loads the Resource Bars update file outside the game and checks
-- Show When Missing on the Health and Power bars and the WoW Forever druid mana
-- strip. A bar Show When Missing reveals shows at its normal opacity while the
-- resource is below full: a rule-hidden bar is hidden at full, one shown outright
-- and faded out of combat rests at the fade there. A lifted bar leaves the
-- Border Around All group, combat hands every bar back, curves are reused.
--   lua5.1 .tools/tests/test_rb_show_when_missing.lua      (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local SRC = ReadSource("EllesmereUIResourceBars/EUI_ResourceBars_Update.lua")

-- Absorbs every call and index: the file-scope work this harness does not test.
local U = setmetatable({}, { __index = function(t) return t end, __call = function(t) return t end })

-------------------------------------------------------------------------------
--  Game API stubs
-------------------------------------------------------------------------------
local curvesMade = 0
local function NewCurve()
    curvesMade = curvesMade + 1
    local c = { pts = {} }
    function c:SetType() end
    function c:AddPoint(x, y) self.pts[#self.pts + 1] = { x, y } end
    function c:ClearPoints() self.pts = {} end
    return c
end
-- A step curve: the value of the last point at or below x.
local function Eval(curve, x)
    local v
    for _, p in ipairs(curve.pts) do if x >= p[1] then v = p[2] end end
    return v
end
C_CurveUtil = { CreateCurve = NewCurve }
Enum = { LuaCurveType = { Step = 1 } }

local health = 1
local power = {}
UnitHealthPercent = function(_, _, curve) return Eval(curve, health) end
UnitPowerPercent = function(_, pt, _, curve) return Eval(curve, power[pt] or 1) end
UnitPowerMax = function() return 100 end
issecretvalue = function() return false end
GetTime = function() return 0 end
IsInRaid = function() return false end
IsInGroup = function() return false end
UnitExists = function() return false end
UnitCanAttack = function() return false end
InCombatLockdown = function() return false end

-- A widget method this harness does not model returns the absorbing stub (so
-- the file-scope animation groups build); any other field that was never set
-- reads nil, as on a real frame.
local NOOP = function() return U end
local FRAME_MT = { __index = function(_, k)
    if type(k) == "string" and k:find("^%u") then return NOOP end
    return nil
end }
local function NewFrame(name, parent)
    local f = setmetatable({ name = name, alpha = 1, level = 5, strata = "MEDIUM", shown = true, parent = parent }, FRAME_MT)
    function f:SetAlpha(a) self.alpha = a end
    function f:GetAlpha() return self.alpha end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetParent(p) self.parent = p end
    function f:GetParent() return self.parent end
    function f:GetFrameLevel() return self.level end
    function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameStrata() return self.strata end
    function f:SetFrameStrata(s) self.strata = s end
    function f:SetAllPoints() end
    return f
end
CreateFrame = function(_, _, parent) return NewFrame("created", parent) end

local shownVis = {}
EllesmereUI = {
    Tick = { NewAnimTicker = function() return U end },
    SetElementVisibility = function(f, on) shownVis[f] = on end,
    VisOverrideValue = function() return nil end,
    CheckVisibilityOptions = function() return false end,
}
-- Other fields absorb the file-scope calls, except those the tested paths
-- branch on, which read nil as on a client without them.
local NIL_FIELDS = { EvalVisibilityExtended = true, ManaRegenSpark = true, SpellCostPrediction = true }
setmetatable(EllesmereUI, { __index = function(_, k)
    if NIL_FIELDS[k] then return nil end
    return U
end })

local hp, pp
_G._ERB_ResolveHealthCfg = function() return hp end
_G._ERB_ResolvePowerCfg = function() return pp end
_G._ERB_ResolveSecondaryCfg = function() return nil end
_G._ERB_BarHiddenByForm = function() return false end

-------------------------------------------------------------------------------
--  The Resource Bars chain: the names the file imports, setter lists on demand
-------------------------------------------------------------------------------
local PT = { MANA = 0, RAGE = 1, FOCUS = 2, ENERGY = 3 }
local I = setmetatable({}, { __index = function(t, k)
    if type(k) == "string" and k:sub(-7) == "Setters" then
        local list = {}
        rawset(t, k, list)
        return list
    end
    return U
end })
rawset(I, "broken", false)
rawset(I, "PT", PT)
rawset(I, "ERB", { _moEligible = {}, db = { profile = { secondary = {} } } })
rawset(I, "IsSpecDisabled", function() return false end)
local ns = { _internals = I }

local inCombat = false
function ns.ResolveBarAlpha(cfg)
    if cfg and cfg.oocFadeEnabled and not inCombat then return cfg.oocAlpha or 0.5 end
    return (cfg and cfg.barAlpha) or 1
end
local groupEvals = 0
function ns.ERB_GroupEval() groupEvals = groupEvals + 1 end

assert(loadstring(SRC, "=EUI_ResourceBars_Update.lua"))("EllesmereUIResourceBars", ns)
assert(rawget(I, "broken") == false, "the file did not load to its end")
local UpdateVisibility = assert(rawget(I, "UpdateVisibility"))

local main = NewFrame("main")
local hb, pb = NewFrame("health", main), NewFrame("power", main)
local function Feed(name, v) for _, s in ipairs(I[name .. "Setters"]) do s(v) end end
Feed("mainFrame", main)
Feed("healthBar", hb)
Feed("primaryBar", pb)
local function SetCombat(v) inCombat = v; Feed("isInCombat", v) end
Feed("cachedPrimary", PT.ENERGY)
ns._erbGroupOn = true

-- What shows on screen: the bar's alpha times every wrapper above it.
local function Shown(bar)
    local a, p = bar.alpha, bar.parent
    while p and p ~= main do
        a = a * p.alpha
        p = p.parent
    end
    return a
end
local function Near(a, b) return math.abs(a - b) < 1e-9 end

-------------------------------------------------------------------------------
--  1. Health shown outright, faded to 0 out of combat: lifted below full
-------------------------------------------------------------------------------
hp = { enabled = true, visibility = "always", showWhenMissing = true,
       oocFadeEnabled = true, oocAlpha = 0, barAlpha = 1 }
pp = { enabled = true, visibility = "always" }
UpdateVisibility()
assert(hb._missLive and hb.parent == hb._missWrap, "the faded bar was not lifted")
assert(hb.alpha == 1, "a lifted bar is not at its normal opacity")
assert(Near(Shown(hb), 0), "at full health the lifted bar is not at its fade")
assert(ns._erbGrpH == false, "a lifted bar stayed a Border Around All member")
health = 0.5
ns.ERB_MissingPaint(hb)
assert(Near(Shown(hb), 1), "below full the lifted bar is not at its normal opacity")

-- a fade to 40% of a bar at 80%: rests at 40% at full, 80% below
hp.oocAlpha, hp.barAlpha = 0.4, 0.8
UpdateVisibility()
local liftCurve, made = hb._missLiftCurve, curvesMade
assert(Near(hb.alpha, 0.8) and Near(Shown(hb), 0.8), "below full: not the normal opacity")
health = 1
ns.ERB_MissingPaint(hb)
assert(Near(Shown(hb), 0.4), "at full: not the faded opacity")
-- another fade re-points the same curve
hp.oocAlpha = 0.2
UpdateVisibility()
assert(hb._missLiftCurve == liftCurve and curvesMade == made, "a new fade made a new curve")
assert(Near(Shown(hb), 0.2), "the re-pointed curve rests at the old fade")

-- combat hands the bar back
SetCombat(true)
UpdateVisibility()
assert(not hb._missLive and hb._missWrap.alpha == 1, "combat left the lift on")
assert(Near(hb.alpha, 0.8) and Near(Shown(hb), 0.8), "in combat the bar is not at its normal opacity")
assert(ns._erbGrpH == true, "back in combat the bar is no group member")
SetCombat(false)

-- a fade that does not dim below the normal opacity lifts nothing
hp.oocAlpha, hp.barAlpha = 1, 0.8
UpdateVisibility()
assert(not hb._missLive and hb.alpha == 1, "a fade above the normal opacity was lifted")
-- nor does the fade alone, without Show When Health Missing
hp.showWhenMissing, hp.oocAlpha, hp.barAlpha = false, 0, 1
UpdateVisibility()
assert(not hb._missLive and hb.alpha == 0 and ns._erbGrpH == true, "the fade alone changed")

-------------------------------------------------------------------------------
--  2. Health hidden by its Visibility rules: revealed below full at its normal
--     opacity, whatever the fade
-------------------------------------------------------------------------------
hp = { enabled = true, visibility = "in_combat", showWhenMissing = true,
       oocFadeEnabled = true, oocAlpha = 0, barAlpha = 1 }
health = 0.5
UpdateVisibility()
assert(hb._missLive and hb._missFloor == nil, "the rule-hidden bar was not revealed")
assert(shownVis[hb] == true and hb.alpha == 1, "the revealed bar took the fade")
assert(Near(Shown(hb), 1), "the revealed bar does not show below full")
assert(ns._erbGrpH == false, "a rule-hidden bar joined the group")
health = 1
ns.ERB_MissingPaint(hb)
assert(Near(Shown(hb), 0), "the revealed bar shows at full")

-------------------------------------------------------------------------------
--  3. Power: Show When Energy Missing lifts a faded bar, reveals a hidden one
-------------------------------------------------------------------------------
hp = { enabled = true, visibility = "always" }
pp = { enabled = true, visibility = "always", showWhenMissing = true,
       oocFadeEnabled = true, oocAlpha = 0, barAlpha = 1 }
power[PT.ENERGY] = 1
UpdateVisibility()
assert(pb._missLive and pb._missPower == PT.ENERGY, "the faded Power bar was not lifted")
assert(pb.alpha == 1 and Near(Shown(pb), 0) and ns._erbGrpP == false)
power[PT.ENERGY] = 0.3
ns.ERB_MissingPaint(pb)
assert(Near(Shown(pb), 1), "below full energy the Power bar does not show")
pp.visibility, pp.oocAlpha = "in_combat", 0.3
UpdateVisibility()
assert(pb._missLive and pb._missFloor == nil and pb.alpha == 1, "the revealed Power bar took the fade")
pp.showWhenMissing = false
UpdateVisibility()
assert(not pb._missLive, "the reveal stayed on with its toggle off")

-------------------------------------------------------------------------------
--  4. The WoW Forever druid mana strip: Show When Mana Missing lifts it on its
--     own mana curve while the Power bar shown outright is faded
-------------------------------------------------------------------------------
local strip = NewFrame("strip", pb)
local parked
ns.FDM_Host = function() return strip end
ns.FDM_Parked = function(v) parked = v end
ns.FDM_Visibility = function() end
pp = { enabled = true, visibility = "always", showManaWhenMissing = true,
       oocFadeEnabled = true, oocAlpha = 0, barAlpha = 1 }
power[PT.MANA], power[PT.ENERGY] = 0.5, 1
UpdateVisibility()
assert(strip._missLive and strip._missPower == PT.MANA and strip._missFloor == 0, "the strip was not lifted")
assert(strip.parent == strip._missWrap and strip.alpha == 1 and parked == false)
assert(Near(Shown(strip), 1), "the strip does not show below full mana")
assert(not pb._missLive and pb.alpha == 0, "the Power bar was lifted on its energy with that toggle off")
-- in combat it goes back under the Power bar
SetCombat(true)
UpdateVisibility()
assert(not strip._missLive and strip.parent == pb and strip.alpha == 1, "combat left the strip out")
SetCombat(false)
-- rule-hidden Power bar: the strip on its mana curve, hidden at full
pp.visibility = "in_combat"
UpdateVisibility()
assert(strip._missLive and strip._missFloor == nil and strip.alpha == 1, "the hidden bar's strip took the fade")
ns.FDM_Host = nil

assert(groupEvals > 0)
print("resource bars show when missing harness: ok")
