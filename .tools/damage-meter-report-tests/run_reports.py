"""Run with Python + lupa. No interaction with the live WoW client."""
import os
from pathlib import Path

from lupa.lua51 import LuaRuntime

tests = Path(__file__).resolve().parent
root = tests.parents[1]
meter = root / "EllesmereUIDamageMeters"
os.chdir(meter)
lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval("function(source, name) local f, err = loadstring(source, name); assert(f, err) end")
for path in [*meter.glob("*.lua"), root / "EllesmereUIOptions/EUI_DamageMeters_Options.lua"]:
    compile_lua(path.read_text(encoding="utf-8-sig"), str(path))
print("PASS: meter and options files compile with Lua 5.1 (including local/upvalue limits)")
lua.execute((tests / "report_scenarios.lua").read_text(encoding="utf-8"))

source = (meter / "EllesmereUIDamageMeters.lua").read_text(encoding="utf-8-sig")
start = source.index("    function W.SyncReportButton()")
end = source.index("    W.SyncReportButton()", start)
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().REPORT_BUTTON_SOURCE = source[start:end]
lua.execute((tests / "header_scenarios.lua").read_text(encoding="utf-8"))
