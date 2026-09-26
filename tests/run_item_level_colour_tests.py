"""Shared item-level colour regressions using production code and Lua 5.1."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / 'EllesmereUI.lua'
CHAR = ROOT / 'EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin_CharacterSheet.lua'
INSPECT = ROOT / 'EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin_InspectSheet.lua'

def between(text, start, end):
    begin = text.index(start)
    return text[begin:text.index(end, begin)]

def runtime(core):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
EllesmereUI={}; HE={r=1,g=.3,b=1}; MY={r=1,g=.5,b=0}
track={r=0,g=.4,b=.8}; custom={r=.2,g=.4,b=.6}
trackCalls=0
EllesmereUI.GetUpgradeTrack=function(link)
 trackCalls=trackCalls+1
 if link and link:find('tracked',1,true) then return '6/6',track end
 return '',{r=1,g=1,b=1}
end
C_Item={GetItemQualityColor=function(q) return q/10,.2,.9 end}
wipe=function(t) for k in pairs(t) do t[k]=nil end end
function Link(bonus) return 'item:237831::::::::::::1:'..bonus end
function Expect(c,r,g,b) assert(c.r==r and c.g==g and c.b==b,'unexpected colour') end
''')
    fragment = between(core, '        local craftedColors =', '\n    end\nend\n')
    lua.execute(fragment)
    return lua

core = CORE.read_text(encoding='utf-8-sig')
lua = runtime(core)
lua.execute('''
local Color=EllesmereUI.GetItemLevelColor
Expect(Color(Link(13836),4),1,.5,0)
Expect(Color(Link(13835),4),1,.3,1)
assert(Color(Link(13836)..':tracked',4)==track,'real track must win')
Expect(Color(Link(99999),4),.4,.2,.9)
Expect(Color(nil,nil),1,1,1)
Expect(Color('invalid',nil),1,1,1)
Expect(Color(Link(99999),0),0,.2,.9)
Expect(Color(Link(13836),nil),1,.5,0)
-- A crest-shaped value outside the declared bonus list is not a crest.
Expect(Color('item:237831::::::::::::0:13836',4),.4,.2,.9)
EllesmereUIDB={charSheetColorItemLevel=false}
Expect(Color(Link(13836),4),1,.5,0)
Expect(Color(Link(99999),4),1,1,1)
assert(Color('tracked',4)==track)
EllesmereUIDB={charSheetItemLevelUseColor=true,charSheetItemLevelColor=custom}
assert(Color(Link(13836),4)==custom)
assert(Color('tracked',4)==custom)
EllesmereUIDB={charSheetItemLevelUseColor=false,charSheetItemLevelColor=custom}
Expect(Color(Link(13836),4),1,.5,0)
local before=trackCalls
assert(Color(Link(13836),4,'6/6',track)==track)
Expect(Color(Link(13836),4,'',{r=1,g=1,b=1}),1,.5,0)
assert(trackCalls==before,'cached rank input must avoid another upgrade query')
''')
print('PASS: Myth/Hero, bonus bounds, actual-track/custom priority, rarity toggle and nil fallbacks')

char = CHAR.read_text(encoding='utf-8-sig')
inspect = INSPECT.read_text(encoding='utf-8-sig')
char_fragment = between(char, '        local ilvlColor =', '        if GetFFD(slot).itemLevelLabel then')
inspect_fragment = between(inspect, '            local _, _, quality = GetItemInfo(itemLink)', '            ilvlText:SetTextColor(')
lua.execute('function CharacterColor(itemLink,itemQuality,upgradeTrackText,upgradeTrackColor)\n'
            +char_fragment+'return ilvlColor,upgradeTrackText end')
lua.execute('GetItemInfo=function(link) return nil,nil,testQuality end\n'
            +'function InspectColor(itemLink)\n'+inspect_fragment+'return displayColor end')
qol = (ROOT / 'EllesmereUIQoL/EllesmereUIQoL.lua').read_text(encoding='utf-8-sig')
flyout = between(qol, '    local function PaintButton(button, useItemLocation)', '\n    end\n') + '\n    end\n'
lua.execute('''
_flyoutFS={}
FlyoutEnabled=function() return true end
ButtonItemInfo=function() return 331,testQuality,testLink end
label={SetText=function() end,SetTextColor=function(_,r,g,b) painted={r=r,g=g,b=b} end}
EnsureText=function() return label end
'''+flyout+'PaintFlyout=PaintButton')
merchant_source = (ROOT / 'EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin_WindowPacks.lua').read_text(encoding='utf-8-sig')
merchant_fragment = between(merchant_source, '                            local quality = select(3, C_Item.GetItemInfo(link))', '                            fs:SetTextColor(r, g, b, 1)')
lua.execute('C_Item.GetItemInfo=GetItemInfo\nfunction MerchantColor(link)\n'
            +merchant_fragment+'return {r=r,g=g,b=b} end')
lua.execute('''
for _,db in ipairs({{}, {charSheetColorItemLevel=false},
 {charSheetItemLevelUseColor=true,charSheetItemLevelColor=custom}}) do
 EllesmereUIDB=db
 for _,link in ipairs({Link(13836),Link(13835),Link(99999),Link(13836)..':tracked'}) do
  testQuality=4
  local text,color=EllesmereUI.GetUpgradeTrack(link)
  local c,rank=CharacterColor(link,4,text,color)
  local i=InspectColor(link)
  local merchant=MerchantColor(link)
  testLink=link; PaintFlyout({IsShown=function() return true end})
  Expect(i,c.r,c.g,c.b); Expect(merchant,c.r,c.g,c.b)
  Expect(painted,c.r,c.g,c.b)
  assert(rank==text,'crafted fallback must not invent upgrade rank text')
 end
end
''')
for path in (CORE, CHAR, INSPECT):
    lua.execute('assert(loadstring(...))', path.read_text(encoding='utf-8-sig'))
print('PASS: production Character/Inspect/flyout/merchant callers agree; no invented rank; Lua 5.1 compile')
