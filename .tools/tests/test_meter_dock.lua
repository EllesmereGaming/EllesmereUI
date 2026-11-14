local profile = {}
local bar = { shown = true, scale = 1, width = 600 }
function bar:GetRect() return 100, 20, self.width, 24 end
function bar:GetEffectiveScale() return self.scale end
function bar:IsShown() return self.shown end
local frame = { scale = 1 }
function frame:GetEffectiveScale() return self.scale end
function frame:ClearAllPoints() end
function frame:SetClampedToScreen(v) self.clamped = v end
function frame:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
function frame:SetSize(w, h) self.w, self.h = w, h end
UIParent = { GetEffectiveScale = function() return 1 end }
EllesmereUI = { _ModuleNS = {} }
local ns = { _live = { a = { enabled = true, bar = bar } } }
function ns.GetProfile() return profile end
function ns.GetBar(id) return id == 'a' and {} end
assert(loadfile('EllesmereUIDataBars/EllesmereUIDataBars_MeterDock.lua'))('dock', ns)

assert(not ns.MeterDockState(1))
profile.meterDockBar = 'a'
ns.PlaceDockMeter(frame, 1)
assert(frame.x == 100 and frame.y == 46 and frame.w == 299)
ns.PlaceDockMeter(frame, 2)
assert(frame.x == 401 and frame.x + frame.w == 700)
bar.width = 300
ns.PlaceDockMeter(frame, 1)
assert(frame.w == 149 and frame.y == 46)
ns.PlaceDockMeter(frame, 2)
assert(frame.x == 251 and frame.y == 46)
profile.meterDockCount = 1
ns.PlaceDockMeter(frame, 1)
assert(frame.w == 300 and frame.x == 100)
local docked, shown = ns.MeterDockState(2)
assert(docked and not shown)
profile.meterDockHasSecond = true
assert(ns.MeterDockState(3))
docked, shown = ns.MeterDockState(3)
assert(docked and not shown)
profile.meterDockCount = 2
bar.width = 600; bar.scale = 0.8; frame.scale = 0.5
ns.PlaceDockMeter(frame, 2)
assert(math.abs((frame.x + frame.w) * frame.scale - 560) < 0.001)
profile.meterDockShown = false
docked, shown = ns.MeterDockState(1)
assert(docked and shown)
Enum = { DamageMeterType = { DamageDone = 0, HealingDone = 1 } }
local cfg = { windowCount = 3, windows = { {curDMType=4}, {curDMType='threat'}, {curDMType=1} } }
local selected
local dm = { EDM = { DB = function() return cfg end }, _windows = {
    [1] = { SetDMType = function(value) selected = value end }
} }
EllesmereUI._ModuleNS.EllesmereUIDamageMeters = dm
_EDM_Apply = function() end
ns.RefreshMeterDock = function() end
ns.SetDockMeterCount(1)
assert(profile.meterDockCount == 1 and profile.meterDockShown == false)
ns.SetDockMeterType(1, 'threat')
ns.SetDockMeterType(2, 6)
ns.SetDockMeterCount(2)
assert(ns.GetDockMeterType(1) == 'threat' and ns.GetDockMeterType(2) == 6)
ns.SetDockMeterType(1, 0)
ns.SetDockMeterCount(1)
ns.SetDockMeterCount(2)
assert(ns.GetDockMeterType(1) == 0 and ns.GetDockMeterType(2) == 6)
assert(selected == 0)
profile.meterDockBar = nil
assert(not ns.MeterDockState(1))
print('PASS: full width, two columns on narrow bars, scale, hide, legacy third hidden, types preserved')

profile.meterDockBar = 'a'
local visible = false
local stub = { IsShown = function() return visible end }
dm._windows[1].frame = stub
ns.ToggleMeterDock()
assert(ns.MeterDockOverridesVisibility() and profile.meterDockShown)
visible = true
ns.ToggleMeterDock()
local docked, shown = ns.MeterDockState(1)
assert(docked and not shown and not profile.meterDockShown)
ns.SetMeterDock('a')
assert(not ns.MeterDockOverridesVisibility())
print('PASS: button toggles actual visibility and activates override; changing dock restores rules')

ns.BarsInOrder = function() return { {id='a', orientation='H'} } end
ns.SetMeterDockEnabled(false)
assert(not profile.meterDockBar and profile.meterDockSelectedBar == 'a')
ns.SetMeterDockEnabled(true)
assert(profile.meterDockBar == 'a')
ns.SetMeterDockEnabled(false)
ns.SelectDockBar('b')
assert(not profile.meterDockBar and profile.meterDockSelectedBar == 'b')
ns.SetMeterDockEnabled(true)
assert(profile.meterDockBar == 'b')
ns.SetMeterDockEnabled(false)
profile.meterDockSelectedBar = nil
ns.SetMeterDockEnabled(true)
assert(profile.meterDockBar == 'a')
print('PASS: enable toggle, remembered DataBar and selection while disabled')
