"""Raid Frames Buff Manager Pandemic Border: runs the shipped Lua against mocks.

Checks that disabled displays allocate nothing, each button registers its region
once, the enable toggle changes the container signature and pool key, and a
restyle keeps a shared pool's registration for buttons made after it; on WoW
Forever a saved choice reads as off.

Run: python .tools/tests/test_rf_pandemic_border.py [repo root]  (needs lupa)
"""
from pathlib import Path
import sys
from lupa.lua51 import LuaRuntime
ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
def source(file):
    return (ROOT / file).read_text(encoding="utf-8-sig")
def between(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]
def runtime():
    return LuaRuntime(unpack_returned_tuples=True)

aura=source('EllesmereUIRaidFrames/EUI_RaidFrames_AuraContainers.lua')
lua=runtime()
lua.execute('''
made=0
function CreateFrame()
 made=made+1
 local f={}
 for _,key in ipairs({'SetAllPoints','EnableMouse','Hide','SetFrameLevel','SetPoint','SetHeight','SetWidth','SetColorTexture'}) do f[key]=function() end end
 f.CreateTexture=function() made=made+1; return f end
 return f
end
BmColor=function() return 1,0,0 end
''')
lua.execute(between(aura,'local function ApplyBmPandemicBorder(', 'local function ApplyBmIconExtra(')+'\nApply=ApplyBmPandemicBorder')
lua.execute('''
local button={AddPandemicRegion=function() bound=(bound or 0)+1 end}
local d={stackCarrier={GetFrameLevel=function() return 20 end}}
Apply(button,d,{bmPandemicEnabled=false}); assert(made==0,'disabled icons allocate no pandemic regions')
Apply(button,d,{bmPandemicEnabled=true}); assert(made==5 and bound==1)
d.bmRegistered=true
Apply(button,d,{bmPandemicEnabled=true,bmPandemicWidth=4}); assert(made==5 and bound==1)
Apply(button,d,{bmPandemicEnabled=false}); assert(made==5 and bound==1)
local pooled={stackCarrier=d.stackCarrier}
Apply(button,pooled,{bmPandemicEnabled=false,bmPandemicRegister=true})
assert(made==10 and bound==2,'all buttons in an opted-in shared pool register')
pooled.bmRegistered=true
Apply(button,pooled,{bmPandemicEnabled=true,bmPandemicRegister=true})
assert(made==10 and bound==2,'a reused disabled-member button can show the border')
''')
lua.execute('BmChainMode=function() return "g" end; BmEffOwnOnly=function() return true end; EllesmereUI={IS_FOREVER=false}')
lua.execute(between(aura,'local function BmPandemicOn(', '-- Candidate filters')+'\nSignature=BmSignature\n_G.BmPandemicOn=BmPandemicOn')
lua.execute('''
local ind={id=1,type='icon',enabled=true,spells={774}}
local off=Signature({ind},1,'custom')
ind.pandemicBorderEnabled=true
assert(Signature({ind},1,'custom')~=off,'enable must select a new creation variant')
ind.type=nil; ind.pandemicBorderEnabled=false
off=Signature({ind},1,'custom'); ind.pandemicBorderEnabled=true
assert(Signature({ind},1,'custom')~=off,'default icon type also selects a creation variant')
''')
key = between(aura, '    local ck = kind ..', '    if anySegs then')
lua.execute('function PoolKey(a,b) local kind="icon"; local ownPat={"o","o"}; local members={{ind={pandemicBorderEnabled=a}},{ind={pandemicBorderEnabled=b}}}\n'+key+'\nreturn ck end')
lua.execute('assert(PoolKey(true,false)==PoolKey(false,true)); assert(PoolKey(true,true)==PoolKey(true,false)); assert(PoolKey(false,false)~=PoolKey(true,false))')
lua.execute('''
EllesmereUI.IS_FOREVER=true
local ind={id=1,type='icon',enabled=true,spells={774}}
local off=Signature({ind},1,'custom')
ind.pandemicBorderEnabled=true
assert(Signature({ind},1,'custom')==off,'WoW Forever: a saved choice reads as off')
assert(PoolKey(true,true)==PoolKey(false,false),'WoW Forever: no opted-in pool variant')
EllesmereUI.IS_FOREVER=false
''')
print('PASS: lazy pandemic regions, one registration, structural enable fingerprint, off on WoW Forever')

lua.execute('''
bmStyleFP = {}; bmOwnFP = {}
EllesmereUI = {GetFontPath = function() return 'font' end}
AK = {styles = {pooled = {bmPandemicRegister = true}}, RestyleSoon = function() end}
BmVisualKey = function() return 'changed' end
BuildBmStyleFor = function() return {bmPandemicEnabled = false} end
BmOwnKey = function() return 'own' end
''')
lua.execute(between(aura, 'local function BmCheckStyles(', 'local function ReloadBm(') + '\nCheckStyles = BmCheckStyles')
lua.execute('''
local cls = {styleKey = 'test', iscale = 1}
CheckStyles(cls, {{styleKey = 'pooled', kind = 'icon', ind = {}, size = 18},
                  {styleKey = 'standalone', kind = 'icon', ind = {}, size = 18}})
assert(AK.styles.pooled.bmPandemicRegister == true, 'restyle preserves shared-pool registration')
assert(AK.styles.standalone.bmPandemicRegister == nil, 'restyle does not opt in standalone icons')
local d = {stackCarrier = {GetFrameLevel = function() return 20 end}}
local button = {AddPandemicRegion = function() bound = bound + 1 end}
local before = made
Apply(button, d, AK.styles.pooled)
assert(made == before + 5 and d.bmPandemicBound, 'new disabled-member buttons register after restyle')
d.bmRegistered = true
Apply(button, d, {bmPandemicEnabled = true})
assert(made == before + 5 and d.bmPandemicBound, 'enabled reuse retains the registered region')
''')
print('PASS: restyle preserves pool registration for newly initialized buttons')
