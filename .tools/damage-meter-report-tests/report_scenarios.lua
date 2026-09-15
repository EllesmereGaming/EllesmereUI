-- Run with Lua 5.1 from EllesmereUIDamageMeters. No live chat is sent.
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end
local cfg, timers, sent, notices = {reportEnabled=true}, {}, {}, {}
local combat, instance, party, raid, guild = false, false, false, false, false
local hardware = true
local secret = setmetatable({}, {__tostring = function() error("Secret stringified") end})
function issecretvalue(v) return rawequal(v, secret) end
function InCombatLockdown() return combat end
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
function IsInInstance() return instance end
function IsInGroup(category) return category == 2 and instance or category == 1 and (party or raid) end
function IsInRaid() return raid end
function IsInGuild() return guild end
local customId = 7
function GetChannelList() return customId, "TestChannel", false, 2, "Unavailable", true end
function GetChannelName(name) return name == "TestChannel" and customId or 0 end
C_Timer = { NewTimer = function(delay, fn)
    check(delay >= 0.3, "throttled")
    local timer = {Cancel=function(self) self.cancelled=true end}
    timers[#timers + 1] = function() if not timer.cancelled then fn() end end
    return timer
end }
C_ChatInfo = { SendChatMessage = function(message, channel, ...)
    if not instance and (channel == "SAY" or channel == "CHANNEL") then
        assert(hardware, "Outdoor chat must remain on the click's call stack")
    end
    sent[#sent + 1] = {message, channel, ...}
end }
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) notices[#notices + 1] = text end }
local function drain()
    hardware=false
    while #timers > 0 do table.remove(timers, 1)() end
    hardware=true
end
Enum = { DamageMeterType = {DamageDone=0, HealingDone=1, DamageTaken=2, AvoidableDamageTaken=3,
    EnemyDamageTaken=4, Interrupts=5, Dispels=6, Deaths=7}, DamageMeterSessionType = {Current=0, Overall=1} }
local types = {[0]="Damage Done", "Healing Done", "Damage Taken", "Avoidable Damage Taken", "Enemy Damage Taken", "Interrupts", "Dispels", "Deaths"}
EllesmereUI = {
    L = function(s) return s end,
    Lf = function(s, ...) return string.format((s:gsub("%%[12]%$", "%%")), ...) end,
}
local lastMenu
local ns = { EDM = { DB = function() return cfg end }, ReportContext = {
    TypeNames=types, SessionNames={[0]="Current", [1]="Overall"},
    Timer=function(n) return string.format("%d:%02d", math.floor(n/60), math.floor(n%60)) end,
    Duration=function() return 100 end, Abbreviate=function(n) return tostring(n) end,
    HideMenu=function() lastMenu=nil end,
} }
local current = {totalAmount=1000, combatSources={}}
for i = 1, 6 do current.combatSources[i] = {name="Player"..i.."-Realm", totalAmount=(7-i)*40, amountPerSecond=(7-i)*0.4} end
local overall = {totalAmount=4000, combatSources={{name="Healer-Realm", totalAmount=2000, amountPerSecond=20}}}
local past = {totalAmount=800, combatSources={{name="BossPlayer", totalAmount=800, amountPerSecond=8}}}
local fetched
C_DamageMeter = {
    GetCombatSessionFromType=function(segment, metric) fetched={segment, metric}; return segment == 1 and overall or current end,
    GetCombatSessionFromID=function(id, metric) fetched={id, metric}; return past end,
    GetAvailableCombatSessions=function() return {{sessionID=42, name="Test Boss"}} end,
}
local W = {curDMType=0, curSession=0}
assert(loadfile("EllesmereUIDamageMeters_Report.lua"))("EllesmereUIDamageMeters", ns)
local R = ns.Report
local snapshot = assert(R.Snapshot(W))
local lines = R.Lines(snapshot, 5)
check(#lines == 6, "header plus top five")
check(lines[2]:find("Player1%-Realm: 240"), "rank and realm preserved")
check(lines[2]:find("24.0%%"), "percent uses entire segment, including rows outside top five")
check(lines[2]:find("DPS"), "damage rate")
check(lines[1]:find("Current %[1:40%]"), "current title and duration")
check(current.combatSources[1].name == "Player1-Realm", "source data untouched")
current.combatSources[1], current.combatSources[6] = current.combatSources[6], current.combatSources[1]
check(R.Lines(assert(R.Snapshot(W)), 1)[2]:find("Player1"), "sort all sources before truncation")
check(current.combatSources[1].name == "Player6-Realm", "sorting never mutates live source list")
W.curSession, W.curDMType = 1, 1
snapshot = assert(R.Snapshot(W))
check(fetched[1]==1 and fetched[2]==1, "healing window uses own overall selection")
check(R.Lines(snapshot,5)[2]:find("HPS") and R.Lines(snapshot,5)[1]:find("Overall"), "healing overall report")
W.curSessionID=42
snapshot=assert(R.Snapshot(W))
check(fetched[1]==42 and R.Lines(snapshot,5)[1]:find("Test Boss"), "historical session by ID")
W.curSessionID=nil; W.curDMType=5
check(not R.Lines(assert(R.Snapshot(W)),5)[2]:find("/s"), "interrupt counts have no rate")
W.curDMType=6
check(not R.Lines(assert(R.Snapshot(W)),5)[2]:find("HPS"), "dispel counts have no healing rate")
W.curDMType=0; W.curSession=0
combat=true
check(R.Snapshot(W)==nil, "combat rejected")
combat=false
for _, field in ipairs({"name","totalAmount","amountPerSecond"}) do
    local old=current.combatSources[1][field]; current.combatSources[1][field]=secret
    check(R.Snapshot(W)==nil, "secret source "..field.." rejected")
    current.combatSources[1][field]=old
end
current.totalAmount=secret; check(R.Snapshot(W)==nil, "secret denominator rejected"); current.totalAmount=1000
local saved=current.combatSources
current.combatSources={}; check(R.Snapshot(W)==nil, "empty report rejected"); current.combatSources=saved
W.curDMType=7
W.Refresh=function() W._barSources={{name="DeadPlayer", deathTimeSeconds=25}} end
check(R.Lines(assert(R.Snapshot(W)),5)[2]=="1. DeadPlayer: 0:25", "death report uses filtered chronological meter rows")
W.curDMType=0
snapshot=assert(R.Snapshot(W))
snapshot.rows[1].name=string.rep(string.char(195,169), 180)
local long=R.Lines(snapshot,5)[2]
check(#long<=255 and long:sub(-3)=="...", "UTF-8 chat byte cap")
check(long:sub(1, -4):match(string.char(195,169).."$") ~= nil, "truncation preserves UTF-8 character boundary")
check(R.Resolve("PARTY")==nil, "solo party unavailable")
party=true; check(R.Resolve("PARTY")=="PARTY", "home party route")
raid=true; check(R.Resolve("RAID")=="RAID", "raid route")
instance=true; check(R.Resolve("INSTANCE_CHAT")=="INSTANCE_CHAT", "explicit instance route")
guild=true; check(R.Resolve("GUILD")=="GUILD" and R.Resolve("OFFICER")=="OFFICER", "guild and officer routes")
local channel, target=R.Resolve("CHANNEL:TestChannel")
check(channel=="CHANNEL" and target==7, "custom channel ID resolved from current name")
channel,target=R.Resolve("WHISPER", " Friend-Realm ")
check(channel=="WHISPER" and target=="Friend-Realm", "whisper destination")
check(R.Resolve("WHISPER", "")==nil, "empty whisper rejected")
local done
sent={}; lines={"Header", "One", "Two"}
check(R.Send(lines,"PARTY",nil,function(message) done=message end), "send accepted")
check(#sent==1, "first line sent on click")
check(not R.Send(lines,"PARTY"), "overlapping reports blocked")
lines[2]="Mutated"; W.curDMType=1
drain()
check(#sent==3 and sent[2][1]=="One" and sent[3][2]=="PARTY", "queued immutable report")
check(done=="Report sent.", "completion callback")
sent={}; R.Send({"Header","One"},"GUILD"); combat=true; drain(); combat=false
check(#sent==1, "stop on combat")
sent={}; R.Send({"Header","One"},"PARTY"); party=false; raid=false; drain()
check(#sent==1, "stop when leaving party")
sent={}; R.Send({"Header","One"},"CHANNEL:TestChannel"); customId=9; drain()
check(#sent==1, "channel renumbering never sends to another channel")
sent={}; R.Send({"Header","One"},"GUILD"); R.Cancel(); drain()
check(#sent==1, "cancel stops pending lines")
local realSend=C_ChatInfo.SendChatMessage
C_ChatInfo.SendChatMessage=function() error("chat rejected") end
R.Send({"Header","One"},"GUILD",nil,function(message) done=message end)
check(done:find("could not send"), "chat errors handled")
C_ChatInfo.SendChatMessage=realSend

-- Minimal UI model: execute the actual dialog and click its controls.
local F={}
local noop=function() end
F.ClearAllPoints=noop
setmetatable(F,{__index=function(_,key)
    if not key:match("^[A-Z]") then return nil end
    if key:match("^Set") or key:match("^Register") or key=="EnableMouse" or key=="EnableMouseWheel" or key=="EnableKeyboard" or key=="ClearFocus" or key=="StartMoving" or key=="StopMovingOrSizing" then return noop end
    error("Unexpected frame method: "..key)
end})
function CreateFrame(kind,name,parent)
    local f=setmetatable({scripts={},shown=true,text="",enabled=true,parent=parent},{__index=F})
    if name then _G[name]=f end
    return f
end
function F:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function F:UnregisterAllEvents() self.events = {} end
function F:SetValue(value) self.value = value; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,value) end end
function F:GetValue() return self.value or 0 end
function F:CreateTexture() return CreateFrame() end
function F:CreateFontString() return CreateFrame() end
function F:SetScript(k,v) self.scripts[k]=v end
function F:SetText(text) self.text=text end
function F:GetText() return self.text end
function F:SetSize(w,h) self.width,self.height=w,h end
function F:SetHeight(h) self.height=h end
function F:SetWidth(w) self.width=w end
function F:GetHeight() return self.height or 100 end
function F:GetWidth() return self.width or 100 end
function F:GetFrameLevel() return 100 end
function F:SetVerticalScroll(value) self.scroll=value end
function F:GetVerticalScroll() return self.scroll or 0 end
function F:IsMouseOver() return false end
function F:SetColorTexture(...) self.color={...} end
function F:SetVertexColor(...) self.color={...} end
function F:SetScale(scale) self.scale=scale end
function F:GetStringHeight() local _, n=self.text:gsub("\n", ""); return (n+1)*14 end
function F:Show() local shown=self.shown; self.shown=true; if not shown and self.scripts.OnShow then self.scripts.OnShow(self) end end
function F:Hide() local shown=self.shown; self.shown=false; if shown and self.scripts.OnHide then self.scripts.OnHide(self) end end
function F:SetShown(v) if v then self:Show() else self:Hide() end end
function F:IsShown() return self.shown end
function F:Enable() self.enabled=true end
function F:Disable() self.enabled=false end
function F:Click() if self.enabled and self.scripts.OnClick then self.scripts.OnClick(self) end end
UIParent=CreateFrame(); UISpecialFrames={}
-- The real dropdown/styled-button factories live in the parent/options addon.
-- Stub only these primitives; the report panel's layout and handlers run above.
EllesmereUI._popupFrames={}
EllesmereUI.EXPRESSWAY="Expressway.ttf"
EllesmereUI.WB_COLOURS={}
EllesmereUI.BTN_TXT_A=0.9
EllesmereUI.DD_BG_R,EllesmereUI.DD_BG_G,EllesmereUI.DD_BG_B,EllesmereUI.DD_BG_A=0.075,0.113,0.141,0.7
local accent={0.1,0.7,0.9}
local accentCallback
function EllesmereUI.GetAccentColor() return unpack(accent) end
function EllesmereUI.GetPopupScale() return 1.25 end
function EllesmereUI.RegAccent(entry) accentCallback=entry.fn end
function EllesmereUI.MakeFont(parent) return parent:CreateFontString() end
function EllesmereUI.SolidTex(parent) return parent:CreateTexture() end
function EllesmereUI.MakeBorder() return {SetColor=function(self,...) self.color={...} end} end
function EllesmereUI.MakeStyledButton(b,text,size,colors,onclick)
    local label=CreateFrame(); label:SetText(text)
    b:SetScript("OnClick",onclick)
    return b:CreateTexture(),EllesmereUI.MakeBorder(),label
end
local dropdownBuilds=0
local function buildDropdown(parent,width,level,values,order,get,set,disabled)
    dropdownBuilds=dropdownBuilds+1
    local b=CreateFrame("Button",nil,parent); b.label=CreateFrame()
    b._refreshLabel=function() b.label:SetText(values[get()] or "") end
    b._invalidateMenu=b._refreshLabel
    b:SetScript("OnClick",function()
        lastMenu={}
        for _, key in ipairs(order) do
            local k=key
            lastMenu[#lastMenu+1]={text=values[k],onClick=function() if not disabled or not disabled(k) then set(k) end end}
        end
    end)
    return b
end
function EllesmereUI:EnsureLoaded() self.BuildDropdownControl=buildDropdown end
local function menuClick(key)
    for _, item in ipairs(lastMenu) do if item.text==key then item.onClick(); return end end
    error("Missing menu item: "..key)
end
cfg={}; W.curDMType=0; W.curSession=0
R.Open(W)
check(EllesmereUIDMReport==nil and dropdownBuilds==0, "disabled reports build no UI")
check(not R.Send({"Header","One"},"GUILD"), "disabled reports cannot send")
cfg.reportEnabled=true
R.Open(W)
local p=EllesmereUIDMReport
check(p:IsShown() and p.key=="INSTANCE_CHAT" and p.count==5, "dialog defaults to instance and five entries")
check(p.subtitle.text:find("Damage Done") and #p.lines==6, "dialog describes damage snapshot")
check(dropdownBuilds==2, "uses actual shared dropdown factory boundary for both controls")
check(p.events.PLAYER_REGEN_DISABLED and p.events.GROUP_ROSTER_UPDATE, "events registered only for visible dialog")
check(p.scale==1.25, "popup inherits panel scale")
check(#EllesmereUI._popupFrames==1, "registered for live panel-scale changes")
check(p.accent.color[3]==0.9, "profile accent applied on open")
accent={0.7,0.2,0.5}; accentCallback(unpack(accent))
check(p.accent.color[1]==0.7 and p.icon.color[3]==0.5, "live theme callback updates accent and report icon")
p.countBtn:Click(); menuClick("3")
check(p.count==3 and cfg.reportLines==3 and #p.lines==4, "entry selector updates preview and setting")
p.channelBtn:Click(); menuClick("Whisper")
check(p.whisper.shown, "recipient field shown for whisper")
p.whisper:SetText("Friend-Realm"); sent={}; p.sendBtn:Click(); drain()
check(#sent==4 and sent[1][2]=="WHISPER" and sent[1][4]=="Friend-Realm", "dialog sends preview to chosen recipient")
check(not p.sendBtn.enabled, "completed report cannot accidentally resend")
p.countBtn:Click(); menuClick("5")
check(p.sendBtn.enabled, "changing report options enables new report")
p.channelBtn:Click(); menuClick("Guild")
check(not p.whisper.shown, "recipient hidden for guild")
sent={}; p.sendBtn:Click(); p.closeBtn:Click(); drain()
check(#sent==1 and not p:IsShown(), "close cancels report")
check(next(p.events)==nil and p.snapshot==nil and p.window==nil, "closed dialog releases events and snapshot")
instance=false; cfg.reportChannel="SAY"; cfg.reportLines=1
R.Open(W); sent={}; p.sendBtn:Click()
check(#sent==2 and #timers==0, "one click sends header and single-player row to outdoor Say")
check(not p.sendBtn.enabled and p.sendBtn.label.text=="Send Report", "no send-next-line state")
local onePlayerHeight=p:GetHeight()
p.countBtn:Click(); menuClick("5"); sent={}; p.sendBtn:Click()
check(#sent==6 and #timers==0, "one click sends header plus five rows to outdoor Say")
check(p:GetHeight()>onePlayerHeight, "preview height follows row count")
for i=1,5 do check(sent[i+1][1]:find("^"..i.."%."), "ranked rows sent in order") end
p.channelBtn:Click(); menuClick("9. TestChannel"); sent={}; p.sendBtn:Click()
check(#sent==6 and sent[6][2]=="CHANNEL" and sent[6][4]==9 and #timers==0, "outdoor custom channel sends complete report on click")
p:Hide(); W.curDMType=1; W.curSession=1; R.Open(W)
check(p.subtitle.text:find("Healing Done %- Overall"), "second window uses healing overall")
combat=true; p.scripts.OnEvent(p,"PLAYER_REGEN_DISABLED"); combat=false
check(not p:IsShown(), "combat closes dialog")
check(#sent==6, "opening menus never sends chat")

R.Open(W)
cfg.reportEnabled=false
R.Close(W)
check(not p:IsShown() and next(p.events)==nil, "disabling reports closes dialog and releases events")
R.Open(W)
check(not p:IsShown() and dropdownBuilds==2, "disabled reopen cannot build or show UI")
cfg.reportEnabled=true
R.Open(W)
p.channelBtn:Click(); menuClick("Guild"); sent={}; p.sendBtn:Click()
cfg.reportEnabled=false; drain()
check(#sent==1, "disabling during a queued report stops unsent rows")
R.Close()
check(not p:IsShown() and next(p.events)==nil, "profile rebuild closes reports")
print("PASS: "..checks.." total report checks (Lua ".._VERSION..")")
