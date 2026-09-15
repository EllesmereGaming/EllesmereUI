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

bag = source(2074, 'EllesmereUIBags/EllesmereUIBags.lua')
fragment = between(bag, '        local function FormatSlots(', '        local countText')
keys=[]
for mode in ('used_total','free_total','free'):
    lua=runtime()
    lua.globals().mode=mode
    lua.execute('EllesmereUI={Lf=function(k,...) return string.format(k,...) end}')
    lua.execute('local format=mode\n'+fragment+'\nFormat=FormatSlots')
    for reagent in (False,True):
        text=lua.globals().Format(10,40,reagent)
        assert ('Reagent' in text)==reagent
        assert text.startswith('10 / 40' if mode=='used_total' else '30 / 40' if mode=='free_total' else '30 ')
import re
keys=re.findall(r'EllesmereUI\.Lf\("([^"]+)"',fragment)
assert len(set(keys))==6, 'all six strings must be statically extractable'
print('PASS: six slot count formats and static locale extraction')
