-- Behavioral mocks, deliberately reject any write to a native chat frame/tab.
local F = {}
local function writable(f) assert(not f.native, "Attempt to modify native chat: " .. tostring(f.name)) end
function F:SetParent(v)
    writable(self)
    if self.parent~=v then self.parentChanges=(self.parentChanges or 0)+1 end
    self.parent = v
end
function F:GetParent() return self.parent end
function F:GetName() return self.name end
function F:SetSize(w,h)
    writable(self)
    local changed=self.w~=w or self.h~=h
    self.w,self.h = w,h
    if changed and self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self,w,h) end
end
function F:SetWidth(v) writable(self); self.w = v end
function F:SetHeight(v) writable(self); self.h = v end
function F:GetWidth() return self.w end
function F:GetHeight() return self.h end
function F:SetScale(v) writable(self); self.scale = v end
function F:GetScale() return self.scale end
function F:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
function F:SetFrameStrata(v) writable(self); self.strata = v end
function F:GetFrameStrata() return self.strata end
function F:SetFrameLevel(v) writable(self); self.level = v end
function F:GetFrameLevel() return self.level end
function F:SetAlpha(v) writable(self); self.alpha = v end
function F:GetAlpha() return self.alpha end
function F:SetClampedToScreen(v) writable(self); self.clamped = v end
function F:IsClampedToScreen() return self.clamped end
function F:IsProtected() return self.protected or false end
function F:SetPoint(...) writable(self); self.points[#self.points+1] = {...} end
function F:GetPoint(i) return unpack(self.points[i or 1] or {}) end
function F:GetNumPoints() return #self.points end
function F:ClearAllPoints() writable(self); self.points = {} end
function F:SetAllPoints() writable(self) end
function F:GetLeft() return self.left or 20 end
function F:GetRight() return self.right or (self:GetLeft()+self.w) end
function F:GetBottom() return self.bottom or 280 end
function F:Show() writable(self); self.shown = true end
function F:Hide()
    writable(self)
    local wasShown=self.shown
    self.shown = false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function F:SetShown(v) if v then self:Show() else self:Hide() end end
function F:IsShown() return self.shown end
function F:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function F:EnableMouse() writable(self) end
function F:EnableMouseWheel() writable(self) end
function F:RegisterForClicks() writable(self) end
function F:SetScript(k,v) writable(self); self.scripts[k] = v end
function F:HookScript(k,v)
    writable(self)
    local old=self.scripts[k]
    self.scripts[k]=function(...) if old then old(...) end; v(...) end
end
function F:GetScript(k) return self.scripts[k] end
function F:RegisterEvent(k) self.events[k] = true end
function F:SetText(v) writable(self); self.text = v end
function F:SetTextColor() writable(self) end
function F:SetColorTexture() writable(self) end
function F:SetFont() writable(self) end
function F:SetJustifyH() writable(self) end
function F:SetWordWrap() writable(self) end
function F:SetChecked(v) self.checked = v end
function F:GetChecked() return self.checked end
function F:CreateTexture() return CreateFrame("Texture",nil,self) end
function F:CreateFontString() return CreateFrame("FontString",nil,self) end
function F:SetOwner() end
function F:AddLine() end
FRAMES = {}
function CreateFrame(kind,name,parent,template)
    local f = setmetatable({kind=kind,name=name,parent=parent,points={},scripts={},events={},
        w=300,h=200,scale=1,strata="MEDIUM",level=1,alpha=1,shown=true,clamped=false}, {__index=F})
    if name then _G[name] = f end
    FRAMES[#FRAMES+1] = f
    if template == "InterfaceOptionsCheckButtonTemplate" then f.Text=f:CreateFontString() end
    return f
end
UIParent = CreateFrame("Frame","UIParent")
GameTooltip = CreateFrame("Frame")
ChatFrame1 = CreateFrame("Frame","ChatFrame1",UIParent)
ChatFrame1.native = true
ChatFrame2 = CreateFrame("Frame","ChatFrame2",UIParent)
ChatFrame2.native = true
ChatFrame1Tab = CreateFrame("Button","ChatFrame1Tab",UIParent)
ChatFrame1Tab.right = 120; ChatFrame1Tab.native = true
ChatFrame2Tab = CreateFrame("Button","ChatFrame2Tab",UIParent)
ChatFrame2Tab.right = 360; ChatFrame2Tab.native = true
GENERAL_CHAT_DOCK = { DOCKED_CHAT_FRAMES={ChatFrame1,ChatFrame2} }
SELECTED = ChatFrame1
function FCFDock_GetSelectedWindow() return SELECTED end
function FCFDock_SelectWindow() error("Must not select native chat") end
SECRET = {}
function issecretvalue(v) return v == SECRET end
function MouseIsOver(f) return f.mouseOver == true end
ZONE_KIND, ZONE_ID = "none", 0
function IsInInstance() return ZONE_KIND ~= "none", ZONE_KIND end
function GetInstanceInfo() return "Zone",ZONE_KIND,0,0,0,0,0,ZONE_ID end
Enum = { DamageMeterType = {DamageDone=0,HealingDone=2} }
SlashCmdList = {}
local pending = {}
C_Timer = {
    After=function(_,f) pending[#pending+1]=f end,
    NewTicker=function(_,f) return { callback=f, Cancel=function(s) s.cancelled=true end } end,
}
function Flush()
    local q=pending; pending={}
    for _,f in ipairs(q) do f() end
end
function Event(name,...)
    for _,f in ipairs(FRAMES) do if f.events[name] then f.scripts.OnEvent(f,name,...) end end
    Flush()
end
function hooksecurefunc(t,k,hook)
    assert(type(t)=="table" and not t.native, "Native hook")
    local old=t[k]
    t[k]=function(...) local result=old(...); hook(...); return result end
end
Settings = {
    RegisterCanvasLayoutCategory=function() return {GetID=function() return 123 end} end,
    RegisterAddOnCategory=function() end,
    OpenToCategory=function(id) OPENED_CATEGORY=id end,
}
CHAT_CONFIG = {enabled=true,tabHeight=24}
PANEL = CreateFrame("Frame",nil,UIParent); PANEL:SetSize(520,280)
CHAT_DATA = {bg=PANEL,_bgIns={b=-34}}
CHAT_DATA.sidebar=CreateFrame("Frame",nil,UIParent)
CHAT_DATA.portalBtn=CreateFrame("Button",nil,CHAT_DATA.sidebar)
CHAT_DATA.settingsBtn=CreateFrame("Button",nil,CHAT_DATA.sidebar)
CHAT_DATA.settingsBtn:SetSize(22,22)
CHAT_DATA.settingsBtn:SetPoint("TOP",CHAT_DATA.portalBtn,"BOTTOM",0,-10)
CHAT = { ECHAT={DB=function() return CHAT_CONFIG end, ResetIdleTimer=function() end} }
CHAT._chatWins={
    [ChatFrame1]={smf=CreateFrame("Frame",nil,PANEL),track=CreateFrame("Frame",nil,PANEL)},
    [ChatFrame2]={smf=CreateFrame("Frame",nil,PANEL),track=CreateFrame("Frame",nil,PANEL)},
}
ChatFrame2.FontStringContainer=CreateFrame("Frame",nil,UIParent)
ChatFrame2.ScrollBar={Track=CreateFrame("Frame",nil,UIParent)}
CombatLogQuickButtonFrame_Custom=CreateFrame("Frame",nil,UIParent)
DM = {_windows={}}
EllesmereUI = {
    _ModuleNS={EllesmereUIChat=CHAT,EllesmereUIDamageMeters=DM},
    _chatCFD=function() return CHAT_DATA end,
    GetFontPath=function() return "font.ttf" end,
    GetAccentColor=function() return 0,1,0 end,
}
SAVED = { width=375,height=180,position={x=1000,y=300} }
function NewWindow(kind)
    local w={curDMType=kind,windowLocked=false}
    w.frame=CreateFrame("Frame",nil,UIParent)
    w.frame:SetSize(SAVED.width,SAVED.height)
    w.frame:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",1000,300)
    w.frame:SetClampedToScreen(true)
    w.header=CreateFrame("Frame",nil,w.frame)
    w.frame._bg=w.frame:CreateTexture()
    w.header._hdrBg=w.header:CreateTexture()
    w.header:SetScript("OnMouseDown",function() w.dragAttempted=true end)
    w.header:SetScript("OnMouseUp",function() w.homeOpened=true end)
    w.titleText=w.header:CreateFontString()
    w.timerText=w.header:CreateFontString()
    w.hdrBtns={}
    for i=1,5 do
        w.hdrBtns[i]=CreateFrame("Button",nil,w.header)
        w.hdrBtns[i]:SetPoint("RIGHT",w.header,"RIGHT",-i*22,0)
    end
    w.segmentBtn=w.hdrBtns[2]
    w.resizeGrip=CreateFrame("Button",nil,w.frame)
    w.lockBtn=CreateFrame("Button",nil,w.frame)
    w.UpdateVisibility=function() if w.hideRule then w.frame:Hide() else w.frame:Show() end end
    w.Refresh=function() w.refreshes=(w.refreshes or 0)+1 end
    w.FitTitle=function() end
    w.ApplyPosition=function() end
    return w
end
DM._windows={NewWindow(0),NewWindow(2),NewWindow(5)}
