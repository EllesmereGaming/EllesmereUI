-- Run from the repository root: lua .tools/tests/test_rb_swing_timer_conditions.lua
-- WoW Forever swing timer, Forms and Talents (the Visibility row's cog): a
-- druid form switched off (barDisabledForms, the per-form map the other bars
-- use) or talent conditions that do not hold for the player's class
-- (classTalentConditions[class], read by the shared EllesmereUI.TalentConditionsHold)
-- park the timer like switched off: no events, alpha 0, still laid out. A
-- shapeshift, or a talent edit, that moves the gate parks it or brings it back
-- through the visibility pass without restyling or re-placing it (only a row
-- that came back meanwhile is restyled); Unlock Mode still shows it;
-- conditions saved for another class change nothing; the apply after a
-- loading screen reads the talents again, a plain full apply leaves the cache
-- the Cooldown Manager shares alone. Section 4: the row height is the
-- profile's, a spec layout's stack height never sets it.
EUI_CLIENT_BLOCKED = false
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

-- Absorbs every call and index: the styling this harness does not test.
local U = setmetatable({}, { __index = function(t) return t end, __call = function(t) return t end })
local NOOP = function() return U end

-------------------------------------------------------------------------------
--  Frames: the shell's events and visibility are what the checks read
-------------------------------------------------------------------------------
local FRAMES = {}
local FRAME_MT = { __index = function(_, k)
    if type(k) == "string" and k:find("^%u") then return NOOP end
    return nil
end }
local function NewFrame(name, parent)
    local f = setmetatable({ _name = name, _parent = parent, _alpha = 1, _shown = true, _events = {},
                             _w = 0, _h = 0, _level = 5 }, FRAME_MT)
    function f:RegisterEvent(e) self._events[e] = true end
    function f:RegisterUnitEvent(e) self._events[e] = true end
    function f:UnregisterEvent(e) self._events[e] = nil end
    function f:UnregisterAllEvents() for k in pairs(self._events) do self._events[k] = nil end end
    function f:IsEventRegistered(e) return self._events[e] == true end
    function f:SetAlpha(a) self._alpha = a end
    function f:GetAlpha() return self._alpha end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:SetShown(v) self._shown = v and true or false end
    function f:IsShown() return self._shown end
    function f:IsVisible() return self._shown end
    function f:SetSize(w, h) self._w, self._h = w, h end
    function f:SetWidth(w) self._w = w end
    function f:SetHeight(h) self._h = h end
    function f:GetWidth() return self._w end
    function f:GetHeight() return self._h end
    function f:GetFrameLevel() return self._level end
    function f:SetFrameLevel(l) self._level = l end
    function f:GetEffectiveScale() return 1 end
    function f:GetScale() return 1 end
    function f:IsMouseEnabled() return false end
    function f:SetPoint(...) self._point = { ... } end
    function f:GetLeft() return self._point and 0 or nil end
    function f:GetObjectType() return "Frame" end
    if name then FRAMES[name] = f end
    return f
end
UIParent = NewFrame("UIParent")
CreateFrame = function(_, name, parent) return NewFrame(name, parent) end

-------------------------------------------------------------------------------
--  Game API stubs
-------------------------------------------------------------------------------
Enum = {
    PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 },
    StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 },
    StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 },
}
local RANGE = {}     -- swing type -> the range check last asked for
C_SwingTimer = {
    EnableRangeCheck = function(swingType, on) RANGE[swingType] = on end,
    IsTargetWithinSwingRange = function() return nil end,
}
C_DurationUtil = { CreateDuration = function() return U end, CreateDurationTextBinding = function() return U end }
C_Spell = { GetSpellName = function(id) return "Spell " .. id end, IsCurrentSpell = function() return false end }
C_ActionBar = { IsAutoRepeatAction = function() return false end }
C_Item = { GetItemInfoInstant = function() return nil end }
C_Timer = { After = function() end }
GetTime = function() return 100 end
GetUnitSpeed = function() return 0 end
GetNetStats = function() return 0, 0, 30, 30 end
local OH_SPEED = nil  -- an off hand weapon's speed, nil = none
UnitAttackSpeed = function() return 2.0, OH_SPEED end
GetInventoryItemID = function() return nil end
IsCurrentSpell = function() return false end
issecretvalue = function() return false end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local CLASS = "DRUID"
UnitClass = function() return CLASS, CLASS end

local FORM = 0
GetShapeshiftFormID = function() return FORM end

-- Talent data: one config, nodes taken by a committed rank.
local CONFIG = 1
local NODES = {}
local function Learn(nodeID, on)
    NODES[nodeID] = { entryIDsWithCommittedRanks = on and { nodeID * 10 } or {}, activeRank = on and 1 or 0,
                      ranksPurchased = on and 1 or 0 }
end
C_ClassTalents = { GetActiveConfigID = function() return CONFIG end }
C_Traits = { GetNodeInfo = function(_, nodeID) return NODES[nodeID] end }

-------------------------------------------------------------------------------
--  EllesmereUI: the shared talent check (the real block), the rest absorbed
-------------------------------------------------------------------------------
local VIS = {}
local invalidations = 0
local restyles, places = 0, 0   -- row restyles (each paints its border) and shell placements
EllesmereUI = {
    _unlockActive = false,
    L = function(s) return s end,
    FOREVER_NEXT_SWING = {},
    SetElementVisibility = function(f, on)
        VIS[f] = on and true or false
        f._alpha = on and 1 or 0
    end,
    IsUnlockAnchored = function() return false end,
    ApplyBorderStyle = function() restyles = restyles + 1 end,
    _TryOverrideAnchor = function() places = places + 1; return false end,
    NotifyElementResized = function() end,
    RegisterMouseoverTarget = function() end,
    RegisterUnlockModeListener = function() end,
    BorderPx = function() return 1 end,
    ResolveTexturePath = function() return "tex" end,
    PP = setmetatable({ Snap = function(v) return v end, Scale = function(v) return v end },
        { __index = function() return NOOP end }),
}
do
    local src = ReadSource("EllesmereUI_SharedHelpers.lua")
    local at = assert(src:find("%-%-  Talent Conditions: a list of"), "the Talent Conditions check is in the shared helpers")
    local block = src:sub((src:find("\ndo\r?\n", at)))
    assert(loadstring(block, "=talent conditions"))()
end
do
    local inv = EllesmereUI.TalentCondInvalidate
    EllesmereUI.TalentCondInvalidate = function() invalidations = invalidations + 1; return inv() end
end
setmetatable(EllesmereUI, { __index = function() return U end })

-- The druid per-form check (its bucket helper and the two hides), cut from the
-- Defaults file (its chain guard keeps the file itself from loading here).
do
    local src = ReadSource("EllesmereUIResourceBars/EUI_ResourceBars_Defaults.lua")
    local s = assert(src:find("local function FormBucket()", 1, true), "the shared form bucket")
    local b = assert(src:find("_G._ERB_BarHiddenByForm = function(cfg)", s, true))
    local e = assert(src:find("\nend", b, true))
    local chunk = "local playerClassFile = (select(2, UnitClass('player')))\n"
        .. "local GetShapeshiftFormID = GetShapeshiftFormID\n" .. src:sub(s, e + 3)
    _G._LoadFormCheck = assert(loadstring(chunk, "=form check"))
end

-------------------------------------------------------------------------------
--  The Resource Bars namespace the swing timer reads
-------------------------------------------------------------------------------
local cfg, ns, shell
local SHOW = true   -- what the shared Visibility checklist says
local function Load(class)
    CLASS = class
    _G._LoadFormCheck()
    cfg = { enabled = true }
    ns = setmetatable({
        ERB = { db = { profile = { swingTimer = cfg } }, _moEligible = {} },
        ShouldShowBar = function() return SHOW end,
        ERB_BarsStyle = function() return "eui" end,
        ERB_BarsClassic = function() return false end,
        GetRBFont = function() return "font" end,
        SnapXY = function(x, y) return x, y end,
        ERB_EuiBorderPad = function() return 0 end,
        CLASS_COLORS = {},
    }, { __index = function() return NOOP end })
    assert(loadfile(ROOT .. "/EllesmereUIResourceBars/EUI_ResourceBars_SwingTimer.lua"))("EllesmereUIResourceBars", ns)
    shell = assert(FRAMES.ERB_SwingTimerFrame, "the shell")
    assert(rawget(ns, "ST_Apply") and rawget(ns, "ST_UpdateVisibility") and rawget(ns, "ST_TalentChanged"),
        "the swing timer loaded")
end

local function Live() return shell._events.PLAYER_SWING == true end
local function Shown() return VIS[shell] == true end
local function Parked() return not Live() and VIS[shell] == false end

-------------------------------------------------------------------------------
-- 1. No conditions: the timer runs as before, the talent cache is never touched.
-------------------------------------------------------------------------------
Load("DRUID")
FORM = 1
ns.ST_Apply()
assert(Live() and Shown(), "with nothing picked the timer runs")
assert(invalidations == 0, "nothing picked: the talent cache is left alone")
ns.ST_UpdateVisibility()
assert(Live() and Shown(), "a visibility pass with nothing picked changes nothing")

-------------------------------------------------------------------------------
-- 2. A druid's forms: Cat switched off parks it, Bear and Dire Bear bring it back.
-------------------------------------------------------------------------------
cfg.barDisabledForms = { energy = true, mana = true, moonkin = true }
restyles, places = 0, 0
ns.ST_Apply()
assert(Parked(), "in Cat Form, switched off: parked (no events, alpha 0)")
assert(shell._shown and shell._point, "parked but laid out: shown at alpha 0 with its spot")
assert(restyles > 0 and places > 0, "a full apply while parked still lays out and styles the rows")
for _, on in pairs(RANGE) do assert(on == false, "parked: every range check is off") end
-- A shift that moves the gate parks or resumes it: nothing restyled or re-placed.
restyles, places = 0, 0
FORM = 5
ns.ST_UpdateVisibility()
assert(Live() and Shown(), "a shift into Bear Form brings it back")
assert(restyles == 0 and places == 0, "resuming restyles and re-places nothing")
assert(RANGE[0] == true, "resuming turns the main hand's range check back on")
FORM = 8
ns.ST_UpdateVisibility()
assert(Live() and Shown(), "Dire Bear Form counts as Bear Form")
FORM = 1
ns.ST_UpdateVisibility()
assert(Parked(), "a shift back into Cat Form parks it again")
assert(restyles == 0 and places == 0, "parking restyles and re-places nothing")
-- An off hand weapon equipped while parked: the resume restyles that row alone.
OH_SPEED = 1.8
FORM = 5
ns.ST_UpdateVisibility()
assert(Live() and Shown(), "back in Bear Form")
assert(restyles == 1 and places == 0, "only the row that came back is restyled: " .. restyles)
OH_SPEED = nil
FORM = 1
ns.ST_UpdateVisibility()
assert(Parked(), "and parked again in Cat Form")
FORM = 0
ns.ST_UpdateVisibility()
assert(Parked(), "caster form is switched off too")
FORM = 31
ns.ST_UpdateVisibility()
assert(Parked(), "Moonkin Form is switched off too")
-- The Visibility checklist still decides while the form allows it.
FORM = 5
SHOW = false
ns.ST_UpdateVisibility()
assert(Live() and not Shown(), "in Bear Form the Visibility rules still hide it (events kept)")
SHOW = true
ns.ST_UpdateVisibility()
assert(Live() and Shown(), "and show it again")

-- Unlock Mode shows a ruled-out timer (its sample); leaving it parks it again.
FORM = 1
ns.ST_UpdateVisibility()
assert(Parked(), "parked in Cat Form")
EllesmereUI._unlockActive = true
ns.ST_Apply()
assert(Shown(), "Unlock Mode shows the parked timer")
EllesmereUI._unlockActive = false
ns.ST_Apply()
assert(Parked(), "leaving Unlock Mode parks it again")

-- Switched off and on: the gate is read again.
cfg.enabled = false
ns.ST_Apply()
assert(not Live() and not Shown(), "switched off")
ns.ST_UpdateVisibility()
assert(not Live(), "a visibility pass leaves a switched-off timer alone")
cfg.enabled = true
FORM = 5
ns.ST_Apply()
assert(Live() and Shown(), "switched on in Bear Form: it runs")
cfg.barDisabledForms = nil

-------------------------------------------------------------------------------
-- 3. Talents, per class: a shaman's Stormstrike.
-------------------------------------------------------------------------------
Load("SHAMAN")
FORM = 0
Learn(17, false)
cfg.classTalentConditions = { SHAMAN = { { nodeID = 17, spellID = 17364, taken = true } } }
invalidations = 0
ns.ST_Apply()
assert(Parked(), "Stormstrike not taken: parked")
assert(invalidations == 0, "a full apply leaves the shared talent cache alone")
-- The talent is learned. The cache still says no until the talent event lands.
Learn(17, true)
ns.ST_UpdateVisibility()
assert(Parked(), "a visibility pass alone reads the cache")
ns.ST_TalentChanged()   -- Resource Bars' TRAIT_CONFIG_UPDATED / PLAYER_TALENT_UPDATE
ns.ST_UpdateVisibility() -- the debounced pass after it
assert(Live() and Shown(), "learned: the talent edit brings it back")
-- Unlearned (a respec).
Learn(17, false)
ns.ST_TalentChanged()
ns.ST_UpdateVisibility()
assert(Parked(), "unlearned: parked again")
-- "Not Taken": shown only without the talent.
cfg.classTalentConditions.SHAMAN[1].taken = false
ns.ST_Apply()
assert(Live() and Shown(), "Not Taken holds while the talent is not taken")
Learn(17, true)
ns.ST_TalentChanged()
ns.ST_UpdateVisibility()
assert(Parked(), "and fails once it is")
-- Conditions saved for another class change nothing for this one.
cfg.classTalentConditions = { WARRIOR = { { nodeID = 99, taken = true } } }
invalidations = 0
ns.ST_Apply()
assert(Live() and Shown(), "another class's conditions leave this class's timer alone")
ns.ST_TalentChanged()
assert(invalidations == 0, "and never wipe the talent cache")
-- No forms for a shaman: a saved per-form map is never read.
cfg.barDisabledForms = { mana = true }
ns.ST_UpdateVisibility()
assert(Live() and Shown(), "a shaman ignores the druid per-form map")
cfg.barDisabledForms = nil

-- Login before the talent data is in, with no active config yet: not taken,
-- parked; the read heals as the config arrives (a new config ID reads again).
Learn(17, true)
cfg.classTalentConditions = { SHAMAN = { { nodeID = 17, taken = true } } }
CONFIG = nil
ns.ST_Apply()
assert(Parked(), "no talent data yet: parked")
CONFIG = 1
ns.ST_UpdateVisibility()
assert(Live() and Shown(), "the config arriving reads the talent")
-- The config there but its ranks read before they arrived: a plain full apply
-- keeps that read; the apply after the loading screen reads it again.
Learn(17, false)
ns.ST_TalentChanged()
ns.ST_UpdateVisibility()
assert(Parked(), "parked without the talent")
Learn(17, true)
invalidations = 0
ns.ST_Apply()
assert(Parked() and invalidations == 0, "a plain full apply keeps the cached read")
ns.ST_TalentChanged()   -- Resource Bars' PLAYER_ENTERING_WORLD pass, then its ApplyAll
ns.ST_Apply()
assert(Live() and Shown(), "the apply after a loading screen reads the talents again")

-------------------------------------------------------------------------------
-- 4. The row height is the profile's: a spec layout's stack height (the rows
--    of the character that saved it) never sets it, while the mover, its size
--    rows and height matching still do, per shown row (PR #3200).
-------------------------------------------------------------------------------
Load("WARRIOR")
FORM = 0
cfg.rowSpacing, cfg.height = 1, 20
OH_SPEED = 1.8                      -- Main Hand and Off Hand rows
ns.ST_Apply()
assert(Live() and Shown(), "a two-row warrior's timer runs")
local rebuilds = 0
local elem = ns.ST_MakeUnlockElement(function(t) return t end, function() rebuilds = rebuilds + 1 end)
-- (The absorbing metatable answers any unset field, so the flag is set either way.)
EllesmereUI._unlockLayerApplying = true      -- a spec layout's flush
elem.setHeight(nil, 9)
assert(cfg.height == 20 and rebuilds == 0,
    "a layout's stack height changed the row height: " .. tostring(cfg.height))
EllesmereUI._unlockLayerApplying = false     -- the mover resizing the stack
elem.setHeight(nil, 9)
assert(cfg.height == 4 and rebuilds == 1,
    "a resize sets the row height from the shown rows: " .. tostring(cfg.height))
OH_SPEED = nil

print("test_rb_swing_timer_conditions: all checks passed")
