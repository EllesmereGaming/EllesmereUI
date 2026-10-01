"""Offline tests for official nameplate threat positioning. Python 3 + lupa.
No game input, saved data, timers or network access.
"""
from pathlib import Path
from lupa.lua51 import LuaRuntime
ROOT = Path(__file__).resolve().parents[2]
def source(n): return (ROOT/n).read_text(encoding='utf-8-sig')
lua=LuaRuntime(unpack_returned_tuples=True)
main=source('EllesmereUINameplates/EllesmereUINameplates.lua')
options=source('EllesmereUIOptions/EUI_Nameplates_Options.lua')
assert options.count('text="Show Threat % on Nameplates"')==1
start=main.index('ns._npTptOn = false')
end=main.index('ns.EnsureHoverOverlay',start)
# Run the real official painter and nameplate lifecycle, with an opaque numeric
# token. Only native mock sinks unwrap it; Lua math/comparison/stringify fail.
lua.execute(r"""
local baseType=type
secret=setmetatable({}, {__tostring=function() error('secret stringify') end,
 __lt=function() error('secret compare') end,__le=function() error('secret compare') end,
 __add=function() error('secret arithmetic') end})
function type(v) if rawequal(v,secret) then return 'number' end; return baseType(v) end
function issecretvalue(v) return rawequal(v,secret) end
function GetThreatStatusColor(status) return status/3,0.5,0 end
C_CurveUtil={EvaluateColorValueFromBoolean=function(b,t,f) return b and t or f end}
EllesmereUI={IS_FOREVER=true};ns={plates={}}; p={threatPctEnabled=true,threatPctColorByThreat=true}
defaults={threatPctPosition='CENTER',threatPctSize=10,threatPctXOffset=0,threatPctYOffset=0}
HP_BAR_SLOTS={{anchor='RIGHT',point='LEFT',xOff=-5},{anchor='LEFT',point='RIGHT',xOff=5},{anchor='CENTER'}}
function GetFont() return 'font' end; function GetNPOutline() return 'outline' end
function SetFSFont(fs,size) fs.size=size end
PP={Point=function(fs,...) fs:SetPoint(...) end}
queries=0; pct=75; status=1; tank=false
function UnitDetailedThreatSituation() queries=queries+1; return tank,status,pct end
allocations=0
function fsNew()
 allocations=allocations+1
 return {SetWordWrap=function() end,Hide=function(s) s.shown=false end,
 SetShown=function(s,v) s.shown=v end,ClearAllPoints=function() end,
 SetPoint=function(s,...) s.point={...} end,SetJustifyH=function() end,
 SetFormattedText=function(s,format,v) s.value=v end,
 SetTextColor=function(s,...) s.color={...} end}
end
plate={health={},unit='nameplate1',healthTextFrame={CreateFontString=fsNew}};ns.plates[1]=plate
""")
paint=source('EllesmereUI_UICore.lua')
startp=paint.index('if EllesmereUI.IS_FOREVER then',paint.index('--  Threat % text paint'))
endp=paint.index('end -- IS_FOREVER',startp)+len('end -- IS_FOREVER')
lua.execute(paint[startp:endp]);lua.execute(main[start:end])
lua.execute(r"""
ns.RefreshThreatPct(); assert(plate.threatPctText.shown and plate.threatPctText.value==75 and allocations==1)
pct=secret;status=secret;tank=true; ns.RefreshThreatPct();assert(rawequal(plate.threatPctText.value,secret))
p.threatPctColorByThreat=false;ns.RefreshThreatPct();assert(plate.threatPctText.color[1]==1)
p.threatPctEnabled=false; local count=queries;ns.RefreshThreatPct();assert(not plate.threatPctText.shown and queries==count)
p.threatPctEnabled=true;pct=nil;ns.RefreshThreatPct();assert(not plate.threatPctText.shown)
pct=55;p.threatPctPosition='RIGHT';p.threatPctSize=16;ns.RefreshThreatPct();assert(plate.threatPctText.size==16 and allocations==1)
plate.unit='nameplate2';pct=20;ns.RefreshThreatPct();assert(plate.threatPctText.value==20 and allocations==1)
EllesmereUI.IS_FOREVER=false;ns.RefreshThreatPct();assert(not plate.threatPctText.shown)
""")
assert 'if self._tptShown then self.threatPctText:Hide() end' in main
print('PASS: official painter, opaque percentage sink, toggles, missing data, profile layout, pooled reuse and retail gate')

# Exercise actual cast layout and its existing show/hide callback: positioning
# must follow resolved geometry immediately, without a second threat query/loop.
assert 'BELOW = "Below Health Bar"' in options
cast_start=main.index('function ns.LayoutCastBar(')
cast_end=main.index('-- Size + anchor the cast spell icon',cast_start)
callback_start=main.index('local function OnCastVisibilityChanged(self)')
callback_end=main.index('    plate.cast:HookScript("OnShow"',callback_start)
lua.execute(r"""
EllesmereUI.IS_FOREVER=true;pct=50;p.threatPctPosition='BELOW'
p.threatPctXOffset=4;p.threatPctYOffset=-2
classic=false; layoutReads=0
ns.NP_Classic=function() return classic end
ns.NP_ClassicCastLayout=function(w,h,ch) return 9,w+8,-5 end
ns.NP_ApplyClassicCastArt=function() end
ns.GetWrapBorderCastbar=function() return false end
function GetHealthBarHeight() return 20 end
function GetShowCastIcon() return false end
defaults.castBarOffsetY=0
PP.perfect=1
plate.GetEffectiveScale=function() return 1 end
plate.cast={shown=false,_timerPlate=plate,IsShown=function(s) return s.shown end,
 ClearAllPoints=function() end,SetSize=function(s,w,h) s.height=h end,
 SetPoint=function(s,...) s.point={...} end,
 GetHeight=function(s) layoutReads=layoutReads+1;return s.height end,GetPoint=function(s) return unpack(s.point) end}
""")
lua.execute(main[cast_start:cast_end])
lua.execute(main[callback_start:callback_end]+'\nCastVisibilityChanged=OnCastVisibilityChanged')
lua.execute(r"""
ns.LayoutCastBar(plate,150,17);ns.RefreshThreatPct()
local fs=plate.threatPctText
assert(fs.point[1]=='TOP' and fs.point[2]==plate.health and fs.point[3]=='BOTTOM')
assert(fs.point[4]==4 and fs.point[5]==-5 and allocations==1)
local count=queries
plate.cast.shown=true;CastVisibilityChanged(plate.cast);assert(fs.point[5]==-22)
p.castBarOffsetY=-6;ns.LayoutCastBar(plate,150,25);assert(fs.point[5]==-36)
classic=true;ns.LayoutCastBar(plate,150,25);assert(fs.point[5]==-41)
plate.cast.shown=false;CastVisibilityChanged(plate.cast);assert(fs.point[5]==-5)
assert(queries==count and allocations==1)
-- Cast above health must never pull the text into the health bar.
classic=false;p.castBarOffsetY=40;plate.cast.shown=true
ns.LayoutCastBar(plate,150,17);assert(fs.point[5]==-5)
plate.cast.shown=secret;CastVisibilityChanged(plate.cast);assert(fs.point[5]==-5)
plate.cast.shown=false;p.threatPctSize=20;p.threatPctXOffset=-7;p.threatPctYOffset=8
ns.RefreshThreatPct();assert(fs.size==20 and fs.point[4]==-7 and fs.point[5]==5)
for _,position in ipairs({'LEFT','RIGHT','CENTER'}) do
 p.threatPctPosition=position;ns.RefreshThreatPct()
 assert(fs.point[1]==position and fs.point[5]==8)
end
p.threatPctEnabled=false;ns.RefreshThreatPct();assert(not fs.shown)
local reads=layoutReads
plate.cast.shown=true;CastVisibilityChanged(plate.cast);ns.LayoutCastBar(plate,150,17)
assert(layoutReads==reads)
plate.unit='nameplate3';p.threatPctPosition='BELOW';p.threatPctEnabled=true
pct=secret;ns.RefreshThreatPct();assert(rawequal(fs.value,secret) and allocations==1 and fs.point[1]=='TOP')
""")
print('PASS: Below option, offsets/font size, cast start/end/layout/Classic/focus clearance, opaque state, all inside positions and pooled reuse')

# The Essentials page offers BELOW only for nameplates, not target/focus frames.
essentials=source('EllesmereUIOptions/EUI_ForeverEssentials_Threat_Options.lua')
assert 'nil, nil, NP_PCT_POSITIONS, NP_PCT_POSITION_ORDER)' in essentials
assert 'values = positions or PCT_POSITIONS, order = positionOrder or PCT_POSITION_ORDER' in essentials
assert 'local PCT_POSITION_ORDER = { "RIGHT", "LEFT", "CENTER" }' in essentials
compile_lua=lua.eval('function(s,n) local f,e=loadstring(s,n); assert(f,e) end')
for name in ['EllesmereUINameplates/EllesmereUINameplates.lua','EllesmereUIOptions/EUI_Nameplates_Options.lua','EllesmereUIOptions/EUI_ForeverEssentials_Threat_Options.lua']:
    compile_lua(source(name),name)
lua.execute(r"""
-- Unreadable geometry is never compared or subtracted.
plate.cast.shown=true;plate.cast.height=secret
ns.ApplyThreatPctPos(plate);assert(plate.threatPctText.point[5]==5)
plate.cast.height=17;plate.cast.point[5]=secret
ns.ApplyThreatPctPos(plate);assert(plate.threatPctText.point[5]==5)
-- Fractional offsets follow the cast bar's pixel-snapped local anchor.
plate.GetEffectiveScale=function() return 2 end
p.castBarOffsetY=-2.3;ns.LayoutCastBar(plate,150,17)
assert(plate.threatPctText.point[5]==8-17-2.5-3)
""")
print('PASS: shared options scope, disabled geometry reads, opaque layout inputs, pixel snapping and Lua 5.1 compilation')
