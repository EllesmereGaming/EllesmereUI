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

dm=source(2095,'EllesmereUIRaidFrames/EUI_RaidFrames_DebuffManager.lua')
lua=runtime()
lua.execute('''
ns={}; EllesmereUI={}; combat=false; created=0
InCombatLockdown=function() return combat end
local function nop() end
function Frame(x,y,w,h,level)
 local f={x=x,y=y,w=w,h=h,level=level or 0}
 f.GetSize=function(s) return s.w,s.h end
 f.GetRect=function(s) return s.x,s.y,s.w,s.h end
 f.GetFrameLevel=function(s) return s.level end
 f.SetFrameLevel=function(s,l) s.level=l end
 f.SetSize=function(s,w,h) s.w=w;s.h=h end
 f.SetPoint=function(s,p,host,c,x,y) s.x=host.x+(x or 0);s.y=host.y+(y or 0) end
 f.Show=function(s) s.shown=true end; f.Hide=function(s) s.shown=false end
 f.ClearAllPoints=nop;f.RegisterForClicks=nop;f.SetAttribute=nop;f.HookScript=nop
 return f
end
CreateFrame=function() created=created+1; return Frame(0,0,1,1) end
local tipModEaters={}
ForwardEnter=nop; ForwardLeave=nop
function ParkEater(e) e._euiActive=false;e:Hide() end
''')
lua.execute('local tipModEaters={}\n'+between(dm,'local tipEaterCount = 0','-- Per-unit ensure,') )
lua.execute('''
local host=Frame(100,100,100,40,10); local container=Frame(0,0,1,1,11); local d={}
local function oversized(e) e.x=75;e.y=90;e:SetSize(200,70) end
ns.DM_EnsureBuffTipEater(host,d,'bar',container,host,'CENTER','CENTER',0,0,1,1,oversized,'wide',18)
local e=d.tipModEaters[d.buffTipSlots.bar]
assert(e.x==100 and e.y==100 and e.w==100 and e.h==40,'final callback footprint must stay inside owning unit')
assert(e.level==18,'bar eater must follow visual layer, not blanket +30')
local old=created
ns.DM_EnsureBuffTipEater(host,d,'bar',container,host,'CENTER','CENTER',0,0,1,1,oversized,'wide',18)
assert(created==old)
host.w=80
ns.DM_EnsureBuffTipEater(host,d,'bar',container,host,'CENTER','CENTER',0,0,1,1,oversized,'wide',18)
assert(e.w==80,'unit resize must invalidate clipping')
combat=true
ns.DM_EnsureBuffTipEater(host,d,'new',container,host,'CENTER','CENTER',0,0,1,1,oversized,'new',18)
assert(created==old and d.rfcBmPending,'combat changes must defer')
combat=false
ns.DM_ParkBuffTipEaters(d)
assert(not e.shown and not e._euiActive)
''')
print('PASS: final tooltip clipping, layer, resize, combat deferral and retirement')
