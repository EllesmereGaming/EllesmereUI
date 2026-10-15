"""Exercise production counting, header rendering and settings callbacks with Lua 5.1."""
from pathlib import Path
import re
import sys
from lupa.lua51 import LuaRuntime

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
bag = (ROOT / 'EllesmereUIBags/EllesmereUIBags.lua').read_text(encoding='utf-8-sig')
options = (ROOT / 'EllesmereUIOptions/EUI_Bags_Options.lua').read_text(encoding='utf-8-sig')
def between(text, start, end):
    begin = text.index(start)
    return text[begin:text.index(end, begin)]

lua = LuaRuntime(unpack_returned_tuples=True)
helper = between(bag, 'local function FormatSlots(', 'local function FinishRefresh(')
header = between(bag, '    if EUI_Bags.Header and EUI_Bags.Header.itemCount then', '    UpdateBagMoneyDisplay()')
# Item metadata and rendering do not contribute to counts. Close only the
# production info condition and two bag/slot loops after the counter prefix.
scan = between(bag, '    local regularUsed, regularTotal = 0, 0', '                local itemLink =')
lua.execute('''
EllesmereUI={Lf=function(key,...) return string.format(key,...) end}
settings={}; BP=function() return settings end
specialBags=nil; ns={SpecialBags=function() return specialBags end}
EUI_Bags={Header={itemCount={SetText=function(_,text) result=text end}}}
sizes={}; used={}
C_Container={GetContainerNumSlots=function(b) return sizes[b] or 0 end,
 GetContainerItemInfo=function(b,s)
  if s <= (used[b] or 0) then return {stackCount=200} end
 end}
''')
lua.execute(helper + '\nfunction Render()\n' + scan + '\nend end end\n' + header + '\nend')
cases = [
    ({0:4,1:2,5:3}, {0:4,1:2}, None, None, '6 / 6 Bag slots\n0 / 3 Reagent slots'),
    ({0:4}, {}, None, None, '0 / 4 Bag slots'),
    ({0:4,5:3}, {0:2,5:1}, 'used_total', True, '2 / 4 Bag slots\n1 / 3 Reagent slots'),
    ({0:4,5:3}, {0:2,5:1}, 'free_total', True, '2 / 4 Bag slots free\n2 / 3 Reagent slots free'),
    ({0:4,5:3}, {0:2,5:1}, 'free', True, '2 Bag slots free\n2 Reagent slots free'),
    ({0:4,5:3}, {0:2,5:1}, 'used_total', False, '3 / 7 Bag slots'),
    ({0:4,5:3}, {0:2,5:1}, 'free_total', False, '4 / 7 Bag slots free'),
    ({0:4,5:3}, {0:2,5:1}, 'free', False, '4 Bag slots free'),
    ({0:4,5:3}, {0:4,5:3}, 'free', True, '0 Bag slots free\n0 Reagent slots free'),
    ({}, {}, 'unknown', None, '0 / 0 Bag slots'),
    ({0:4,5:3}, {0:2,5:1}, None, False, '3 / 7 Bag slots'),
]
checks=0
for sizes, used, mode, separate, expected in cases:
    lua.globals().sizes=lua.table_from(sizes)
    lua.globals().used=lua.table_from(used)
    lua.globals().settings=lua.table_from({'bagSlotCountFormat':mode,'bagSeparateReagentSlots':separate})
    for category in (0,-1,-2,7):
        lua.globals().selectedCategoryIndex=category
        lua.globals().Render()
        assert lua.globals().result==expected, (category,expected,lua.globals().result)
        checks+=1
assert len(set(re.findall(r'EllesmereUI\.Lf\("([^"]+)"',helper)))==6
lua.globals().sizes=lua.table_from({0:4,1:8,5:3})
lua.globals().used=lua.table_from({0:2,1:3,5:1})
lua.globals().specialBags=lua.table_from({1:True})
for separate, expected in [(True, '2 Bag slots free\n2 Reagent slots free'),
                           (False, '4 Bag slots free')]:
    lua.globals().settings=lua.table_from({'bagSlotCountFormat':'free','bagSeparateReagentSlots':separate})
    lua.globals().Render()
    assert lua.globals().result==expected, ('restricted bag capacity', expected, lua.globals().result)
print('PASS: restricted special bags excluded from separate and combined capacity')
row=between(options,'            -- Slot count format | Separate reagent slots','            -- Stack Splitter')
lua.execute('''
db={profile={}};y=0;refreshes=0
EUI_Bags.RefreshInventory=function() refreshes=refreshes+1 end
W={DualRow=function(_,parent,y,a,b) controls={a,b};return {},1 end}
'''+row)
lua.execute('''
assert(controls[1].getValue()=='used_total' and controls[2].getValue()==true)
controls[1].setValue('free');controls[2].setValue(false)
assert(db.profile.bagSlotCountFormat=='free' and db.profile.bagSeparateReagentSlots==false)
assert(refreshes==2)
''')
print(f'PASS: {checks} header checks across 11 capacity scenarios and four views; stack counting, defaults, six locale keys and settings callbacks')
