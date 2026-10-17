if EUI_CLIENT_BLOCKED then return end
local frames = {}
local methods = {}
function methods:GetEffectiveScale() return 1 end
function methods:GetRect() return self.x or 100, 20, self.w or 500, 25 end
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
function methods:SetScript(k,v) assert(k ~= "OnUpdate", "polling is forbidden"); self[k]=v end
function methods:RegisterEvent(e) self.events=self.events or {}; self.events[e]=true end
function methods:UnregisterAllEvents() self.events={} end
local scheduled, deferred, callbacks = {}, {}, {}
C_Timer={After=function(delay,fn) assert(delay==0); scheduled[#scheduled+1]=fn end}
local function Flush()
    local work=scheduled; scheduled={}
    for _,fn in ipairs(work) do fn() end
    assert(#scheduled==0, "notification must not rearm itself")
end
EventRegistry={
 RegisterCallback=function(_,event,fn,owner) callbacks[event]={fn,owner} end,
 UnregisterCallback=function(_,event) callbacks[event]=nil end,
}
local function Fire(event,eb)
 local cb=callbacks["ChatFrame.OnEditBox"..event]
 if cb then cb[1](cb[2],eb) end
end
function CreateFrame() local f=setmetatable({points={}}, {__index=methods}); frames[#frames+1]=f; return f end
function wipe(t) for k in pairs(t) do t[k]=nil end end
local combat=false
function InCombatLockdown() return combat end
UIParent=CreateFrame(); ChatFrame1=CreateFrame(); ChatFrame1EditBox=CreateFrame(); ChatFrame1EditBox:Hide()
local bar=CreateFrame()
local cfg={dataBarDock=false,dataBarDockID='one',chatSize={w=400,h=200},chatPosition={x=50,y=60}}
local data={anchorGuarded=true,_bgIns={l=-10,r=10,b=-35},fvIn=CreateFrame(),inputDiv=CreateFrame()}
local available=true
EllesmereUI={_ModuleNS={EllesmereUIDataBars={GetChatDockBar=function(id) if available and id=='one' then return bar end end}},_chatCFD=function() return data end}
EllesmereUI.NewCombatQueue=function() return {Defer=function(key,fn) deferred[key]=fn end} end
local ns={ECHAT={DB=function() return cfg end},ChatStock=function() return false end,ChatForever=function() return false end}
local e=ns.ECHAT
local restored=0
e.ApplyInputPosition=function() e.ConfigureDataBarDock(); e.ApplyDataBarInputs() end
e.ApplyChatPosition=function() if not e.ApplyDataBarDock() then restored=restored+1 end end
assert(loadfile('EllesmereUIChat/EllesmereUIChat_DataBar.lua'))('test',ns)
local bars=EllesmereUI._ModuleNS.EllesmereUIDataBars
assert(not next(callbacks) and #scheduled==0 and not next(deferred))
e.ApplyInputPosition()
assert(not next(callbacks) and not bars.ChatDockChanged and #scheduled==0)
for _,f in ipairs(frames) do assert(not f.OnUpdate and not next(f.events or {})) end
cfg.dataBarDock=true; e.RefreshDataBarDock()
assert(next(callbacks) and bars.ChatDockChanged)
assert(ChatFrame1.points[1][4]==110 and ChatFrame1.points[1][5]==82)
assert(ChatFrame1.points[2][4]==590)
local cover=ChatFrame1EditBox.points[1][2]
assert(cover.width==500 and cover.height==25)
ChatFrame1EditBox:Show(); Fire("Show",ChatFrame1EditBox); Flush(); assert(not cover.shown)
ChatFrame1EditBox.focused=true; Fire("FocusGained",ChatFrame1EditBox); assert(cover.shown)
-- Focus-loss callbacks can run before Blizzard clears the focus flag.
Fire("FocusLost",ChatFrame1EditBox); assert(not cover.shown)
ChatFrame1EditBox.focused=false
ChatFrame1EditBox.parentHidden=true; Fire("Show",ChatFrame1EditBox); Flush(); assert(not cover.shown)
ChatFrame1EditBox.parentHidden=false; ChatFrame1EditBox.focused=true
Fire("FocusGained",ChatFrame1EditBox); assert(cover.shown)
Fire("Hide",ChatFrame1EditBox); assert(not cover.shown); ChatFrame1EditBox:Hide()
bar.w=600; bar.x=140
bars.ChatDockChanged("other"); assert(#scheduled==0)
bars.ChatDockChanged("one"); bars.ChatDockChanged("one"); assert(#scheduled==1); Flush()
assert(cover.width==600 and ChatFrame1.points[1][4]==150)
assert(cfg.chatSize.w==400 and cfg.chatPosition.x==50)
available=false; bars.ChatDockChanged(); Flush(); assert(not e.DataBarDockActive() and not cover.shown)
available=true; bars.ChatDockChanged(); Flush(); assert(e.DataBarDockActive())
combat=true; cfg.dataBarDock=false; e.RefreshDataBarDock()
assert(not cover.shown and not next(callbacks) and not bars.ChatDockChanged and next(deferred))
combat=false
local work=deferred; deferred={}; for _,fn in pairs(work) do fn() end
assert(restored>0 and ChatFrame1EditBox.level==1)
assert(#scheduled==0 and not next(callbacks) and not next(deferred))
-- A queued notification must not reactivate a disabled profile.
cfg.dataBarDock=true; e.RefreshDataBarDock(); bars.ChatDockChanged()
cfg.dataBarDock=false; e.ApplyInputPosition(); Flush()
assert(not next(callbacks) and not bars.ChatDockChanged and not cover.shown)
print("PASS: zero disabled subscriptions/polling, focus events, geometry notifications, coalescing, missing bar, combat queue, profile teardown")
