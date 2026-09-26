"""Focused production-source regression tests. Requires lupa (Lua 5.1)."""
from pathlib import Path
import sys
from lupa.lua51 import LuaRuntime
ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
def source(file):
    return (ROOT / file).read_text(encoding="utf-8-sig")
def between(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]
def runtime():
    return LuaRuntime(unpack_returned_tuples=True)

lua = runtime()
bag = source('EllesmereUIBags/EllesmereUIBags.lua')
lua.execute('''
local myth,hero={},{}
EUI={GetCraftedTrackColor=function(s) if s=='craft' then return myth end end}
_trackRank={[myth]=6,[hero]=5}
GetUpgradeTrack=function(s) return '1/6',s=='hero' and hero or myth end
C_Item={GetDetailedItemLevelInfo=function(s) return ({craft=331,upgraded=334,hero=340})[s] end}
GetItemInfo=function(s) return s,s,4,300,90,'Armor' end
IsGearCategory=function() return true end
wipe=function(t) for k in pairs(t) do t[k]=nil end end
BP=function() return {bagGearSortOrder='track'} end
''')
lua.execute(between(bag, 'local PreCacheSortFields\n', '--  Expansion nesting') + '\nCache=PreCacheSortFields; Compare=VisualSortCompare')
lua.execute('''
local items={{itemLink='craft',categoryIndex=1},{itemLink='upgraded',categoryIndex=1},{itemLink='hero',categoryIndex=1}}
Cache(items); table.sort(items,Compare)
assert(items[1].itemLink=='upgraded' and items[1]._sortIlvl==334, 'upgraded Myth must sort above lower craft')
assert(items[2].itemLink=='craft' and items[3].itemLink=='hero', 'track remains primary')
EUI.GetCraftedTrackColor=function() return {} end
Cache({{itemLink='unknown-colour',categoryIndex=1}})
''')
print('PASS: effective item-level sorting within track')
lua.execute('''
local myth, hero = {}, {}
_trackRank = {[myth]=6, [hero]=5}
local levels = {oldMyth=400, currentHero=321, currentMyth=318}
GetUpgradeTrack=function(s) return '1/6', s=='currentHero' and hero or myth end
C_Item.GetDetailedItemLevelInfo=function(s) return levels[s] end
EUI.GetCraftedTrackColor=function() return nil end
local calls = 0
EUI.GetSeasonItemLevelColor=function(s)
    calls = calls + 1
    return nil, s~='oldMyth'
end
local settings = {bagGearSortOrder='track'}
BP=function() return settings end
local function sorted(mode)
    settings.bagGearSortOrder=mode
    local items={}
    for _, link in ipairs({'oldMyth','currentHero','currentMyth'}) do
        items[#items+1]={itemLink=link,categoryIndex=1}
    end
    Cache(items); table.sort(items,Compare)
    return items
end
assert(sorted('track')[1].itemLink=='oldMyth')
assert(calls==0, 'default mode must not classify seasons')
local items=sorted('seasonTrack')
assert(items[1].itemLink=='currentMyth' and items[2].itemLink=='currentHero')
assert(items[3].itemLink=='oldMyth', 'season priority must beat higher old item level')
items=sorted('seasonIlvl')
assert(items[1].itemLink=='currentHero' and items[2].itemLink=='currentMyth')
assert(items[3].itemLink=='oldMyth')
assert(calls==3, 'warm season results must be reused')
assert(sorted('ilvl')[1].itemLink=='oldMyth', 'item-level mode ignores season')
assert(sorted('track')[1].itemLink=='oldMyth', 'switching back restores track priority')
''')
print('PASS: all four sort modes, season priority, cache reuse and mode changes')

# Non-gear links must not request effective item levels, even when white maps to a track.
lua.execute('''
local queries=0
C_Item.GetDetailedItemLevelInfo=function() queries=queries+1;return 331 end
IsGearCategory=function(c) return c==1 end
local settings={bagGearSortOrder='track'};BP=function() return settings end
Cache({{itemLink='reagent-new',categoryIndex=2}})
assert(queries==0,'non-gear queried detailed item level')
Cache({{itemLink='reagent-new',categoryIndex=1}})
assert(queries==1,'same link moved into gear category must resolve effective level')
Cache({{itemLink='reagent-new',categoryIndex=1}})
assert(queries==1,'effective gear level not cached')
''')
print('PASS: effective item-level queries limited to gear and cached across refreshes')

# Exercise the actual parser and both colour call sites, not a season-classifier stub.
core=source('EllesmereUI.lua')
lua=runtime()
lua.execute('''
EllesmereUI={};EUI=EllesmereUI
W={r=1,g=1,b=1};GR={r=.5,g=.5,b=.5};VE={r=0,g=1,b=0}
CH={r=0,g=0,b=1};HE={r=1,g=0,b=1};MY={r=1,g=.5,b=0}
wipes=0;wipe=function(t) wipes=wipes+1;for k in pairs(t) do t[k]=nil end end
parses=0;local gmatch=string.gmatch
string.gmatch=function(...) parses=parses+1;return gmatch(...) end
function Link(bonuses,tail,id)
 local fields={tostring(id or 1)}
 for i=2,12 do fields[i]='0' end
 fields[13]=tostring(#bonuses)
 for _,bonus in ipairs(bonuses) do fields[#fields+1]=tostring(bonus) end
 if tail then fields[#fields+1]=tostring(tail) end
 return '|Hitem:'..table.concat(fields,':')..'|h[test]|h'
end
''')
lua.execute(between(core,'        local craftedColors =','        -- Item-level text color:'))
lua.execute('''
local color,current
for first,hue in pairs({[12817]=W,[12825]=VE,[12833]=CH,[12841]=HE,[12849]=MY}) do
 for rank=0,5 do
  color,current=EUI.GetSeasonItemLevelColor(Link({first+rank}))
  assert(color==hue and current==true)
 end
end
assert(EUI.GetSeasonItemLevelColor(Link({13835}))==HE)
assert(EUI.GetSeasonItemLevelColor(Link({13836}))==MY)
for _,bonus in ipairs({13621,13622,12769,12777,12785,12793,12801}) do
 local link=Link({bonus})
 color,current=EUI.GetSeasonItemLevelColor(link,true)
 assert(color==GR and current==false)
 local before=parses
 color,current=EUI.GetSeasonItemLevelColor(link,false)
 assert(color==nil and current==false and parses==before,'grey preference must not be cached')
 assert(EUI.GetSeasonItemLevelColor(link,true)==GR)
end
for _,bonuses in ipairs({{13621,13836},{13836,13621},{13621,13751},{13751,13621}}) do
 color,current=EUI.GetSeasonItemLevelColor(Link(bonuses),true)
 assert(current==true and color~=GR,'current season must win over old bonus')
end
color,current=EUI.GetSeasonItemLevelColor(Link({},13836))
assert(color==W and current==false,'parser must respect bonus count')
assert(EUI.GetSeasonItemLevelColor(nil)==nil)
assert(EUI.GetSeasonItemLevelColor(123)==nil)
assert(EUI.GetSeasonItemLevelColor('invalid')==nil)
for i=1,4001 do EUI.GetSeasonItemLevelColor(Link({13835},nil,i)) end
assert(wipes>0,'season cache must be bounded')
settings={bagSeasonColors=true,bagGreyPreviousSeason=true}
BP=function() return settings end
GetUpgradeTrack=function() return '',W end
itemLink=Link({13621});isGear=true;d={_giIlvl=300}
''')
paint=between(bag,'                    if isGear and GetUpgradeTrack then','                    -- Warbound check')
lua.execute(paint)
assert lua.eval('d._giTrackColor==GR')
lua.execute('settings.bagGreyPreviousSeason=false;d={_giIlvl=300}')
lua.execute(paint)
assert lua.eval('d._giTrackColor==nil')
bank=source('EllesmereUIBags/EllesmereUIBags_Bank.lua')
bank_paint=between(bank,'            -- Item level (gear only)','            if btn.Cooldown then')
lua.execute('''
settings.bagGreyPreviousSeason=true;showIlvl=true;giIlvl=300;quality=4
GetItemQualityColor=function() return .6,0,1 end
btn={ItemLevelText={SetText=function() end,SetTextColor=function(_,r,g,b) painted={r,g,b} end}}
''')
lua.execute(bank_paint)
assert lua.eval('painted[1]==GR.r and painted[2]==GR.g and painted[3]==GR.b')
lua.execute('settings.itemlevelUseCustomColor=true;settings.itemlevelCustomColor={r=.2,g=.3,b=.4}')
lua.execute(bank_paint)
assert lua.eval('painted[1]==.2 and painted[2]==.3 and painted[3]==.4')
lua.execute('d={_giIlvl=300}')
lua.execute(paint)
assert lua.eval('d._giTrackColor==nil'), 'inventory must leave custom colour priority intact'
print('PASS: real season parser, bonus bounds, recrafts, grey toggles, bounded cache, inventory/bank colour paths and custom priority')

options=source('EllesmereUIOptions/EUI_Bags_Options.lua')
cog=between(options,'                EllesmereUI.BuildInlineCog(sortRow._leftRegion,','                    title = "Sort Options"')
assert 'disabled' not in cog, 'gear sorting must remain accessible with sort icon hidden'
print('PASS: sort cog remains accessible without the sort icon')
