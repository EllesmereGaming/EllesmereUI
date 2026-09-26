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
