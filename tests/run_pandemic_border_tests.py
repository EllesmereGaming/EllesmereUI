"""Focused production-source regression tests. Requires lupa (Lua 5.1)."""
from pathlib import Path
import sys
import re
from lupa.lua51 import LuaRuntime
ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
def source(pr, file):
    return (ROOT / file).read_text(encoding="utf-8-sig")
def between(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]
def runtime():
    return LuaRuntime(unpack_returned_tuples=True)

aura=source(2072,'EllesmereUIRaidFrames/EUI_RaidFrames_AuraContainers.lua')
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
lua.execute('BmChainMode=function() return "g" end; BmEffOwnOnly=function() return true end')
lua.execute(between(aura,'local function BmSignature(', '-- Candidate filters')+'\nSignature=BmSignature')
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
print('PASS: lazy pandemic regions, one registration, structural enable fingerprint')
