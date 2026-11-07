local profile = { meterDockBar = 'a' }
local button
local methods = {}
function methods:SetPoint(point, _, _, x, y) self.point, self.x, self.y = point, x, y end
function methods:Hide() self.shown = false end
function methods:SetShown(v) self.shown = v end
function methods:CreateTexture() return setmetatable({}, {__index=methods}) end
function methods:CreateFontString() return setmetatable({}, {__index=methods}) end
setmetatable(methods, {__index=function() return function() end end})
CreateFrame = function() button = setmetatable({}, {__index=methods}); return button end
hooksecurefunc = function() end
local bar = {}
function bar:GetRect() return 100, 20, 600, 24 end
function bar:GetEffectiveScale() return 1 end
function bar:IsShown() return true end
function bar:GetFrameStrata() return 'MEDIUM' end
function bar:GetFrameLevel() return 1 end
function bar:HookScript() end
UIParent = { GetEffectiveScale = function() return 1 end }
EllesmereUI = { _ModuleNS = {} }
local ns = { _live = { a = {enabled=true,bar=bar} } }
function ns.GetProfile() return profile end
function ns.GetBar() return {} end
assert(loadfile('EllesmereUIDataBars/EllesmereUIDataBars_MeterDock.lua'))('dock',ns)
ns.RefreshMeterDock()
assert(button.shown and button.point == 'BOTTOMRIGHT' and button.x == 700)
profile.meterDockButtonSide = 'left'
ns.RefreshMeterDock()
assert(button.shown and button.point == 'BOTTOMLEFT' and button.x == 100)
profile.meterDockShowButton = false
ns.RefreshMeterDock()
assert(not button.shown)
assert(ns.MeterDockState(1))
profile.meterDockShowButton = true
ns.RefreshMeterDock()
assert(button.shown and button.x == 100)
print('PASS: button right default, left position, hide and restore without disabling dock')
