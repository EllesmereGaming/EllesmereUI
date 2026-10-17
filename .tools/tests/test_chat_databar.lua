if EUI_CLIENT_BLOCKED then return end
local frames = {}
local methods = {}
function methods:GetEffectiveScale() return 1 end
function methods:GetRect() return 100, 20, 500, 25 end
function methods:HasFocus() return self.focused == true end
function methods:IsVisible() return self:IsShown() and self.parentHidden ~= true end
function methods:IsShown() return self.shown ~= false end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:SetShown(v) self.shown=v end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetFrameLevel(v) self.level=v end
function methods:GetFrameStrata() return self.strata or 'MEDIUM' end
function methods:SetFrameStrata(v) self.strata=v end
function methods:ClearAllPoints() self.points={} end
function methods:SetPoint(...) self.points[#self.points+1]={...} end
function methods:GetPoint(n) return unpack(self.points[n] or {}) end
function methods:GetNumPoints() return #self.points end
function methods:GetHeight() return 200 end
function methods:SetSize(w,h) self.width=w; self.height=h end
function methods:EnableMouse() end
function methods:SetAllPoints() end
function methods:SetColorTexture() end
function methods:CreateTexture() return CreateFrame() end
function methods:SetScript(k,v) self[k]=v end
function CreateFrame() local f=setmetatable({points={}}, {__index=methods}); frames[#frames+1]=f; return f end
function wipe(t) for k in pairs(t) do t[k]=nil end end
local combat=false
function InCombatLockdown() return combat end
UIParent=CreateFrame(); ChatFrame1=CreateFrame(); ChatFrame1EditBox=CreateFrame(); ChatFrame1EditBox:Hide()
local bar=CreateFrame()
local cfg={dataBarDock=true,dataBarDockID='one',chatSize={w=400,h=200},chatPosition={x=50,y=60}}
local data={anchorGuarded=true,_bgIns={l=-10,r=10,b=-35},fvIn=CreateFrame(),inputDiv=CreateFrame()}
local available=true
EllesmereUI={_ModuleNS={EllesmereUIDataBars={GetChatDockBar=function(id) if available and id=='one' then return bar end end}},_chatCFD=function() return data end}
local ns={ECHAT={DB=function() return cfg end},ChatStock=function() return false end,ChatForever=function() return false end}
local e=ns.ECHAT
local restored=0
e.ApplyInputPosition=function() if e.ApplyDataBarInputs then e.ApplyDataBarInputs() end end
e.ApplyChatPosition=function() if not e.ApplyDataBarDock() then restored=restored+1 end end
assert(loadfile('EllesmereUIChat/EllesmereUIChat_DataBar.lua'))('test',ns)
local driver=frames[#frames]
assert(e.DataBarDockActive())
assert(e.ApplyDataBarDock())
assert(ChatFrame1.points[1][4]==110 and ChatFrame1.points[1][5]==82)
assert(ChatFrame1.points[2][4]==590)
e.ApplyDataBarInputs()
local cover=ChatFrame1EditBox.points[1][2]
assert(cover.width==500 and cover.height==25)
ChatFrame1EditBox:Show(); driver.OnUpdate(driver,0.2); assert(not cover.shown)
ChatFrame1EditBox.focused=true; driver.OnUpdate(driver,0.2); assert(cover.shown)
ChatFrame1EditBox.focused=false; driver.OnUpdate(driver,0.2); assert(not cover.shown)
ChatFrame1EditBox.focused=true; ChatFrame1EditBox.parentHidden=true
 driver.OnUpdate(driver,0.2); assert(not cover.shown)
ChatFrame1EditBox.parentHidden=false; driver.OnUpdate(driver,0.2); assert(cover.shown)
ChatFrame1EditBox:Hide(); driver.OnUpdate(driver,0.2); assert(not cover.shown)
assert(cfg.chatSize.w==400 and cfg.chatPosition.x==50)
combat=true; cfg.dataBarDock=false; driver.OnUpdate(driver,0.2); assert(not cover.shown)
combat=false; driver.OnUpdate(driver,0.2); assert(restored>0 and ChatFrame1EditBox.level==1)
cfg.dataBarDock=true; e.RefreshDataBarDock(); available=false; driver.OnUpdate(driver,0.2)
assert(not e.DataBarDockActive() and not cover.shown)
print('PASS: geometry, input overlay, show/hide, saved layout, combat deferral, missing bar fallback')
