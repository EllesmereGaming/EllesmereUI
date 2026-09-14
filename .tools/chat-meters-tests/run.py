"""Run with Python 3 + lupa. Uses the actual Lua 5.1 controller and core closures."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

here = Path(__file__).resolve().parent
root = here.parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
dm = (root / "EllesmereUIDamageMeters/EllesmereUIDamageMeters.lua").read_text(encoding="utf-8")
chat = (root / "EllesmereUIChat/EllesmereUIChat.lua").read_text(encoding="utf-8")
engine = (root / "EllesmereUIChat/EllesmereUIChat_Engine.lua").read_text(encoding="utf-8")

paths = ["EllesmereUIDamageMeters/EllesmereUIDamageMeters.lua",
         "EllesmereUIDamageMeters/EllesmereUIDamageMeters_Chat.lua",
         "EllesmereUIChat/EllesmereUIChat.lua",
         "EllesmereUIChat/EllesmereUIChat_Engine.lua",
         "EllesmereUIChat/EllesmereUIChat_Tabs.lua",
         "EllesmereUIOptions/EUI_DamageMeters_Options.lua"]
for path in paths:
    lua.execute("assert(loadstring(...))", (root / path).read_text(encoding="utf-8"))

def section(source, start, end):
    return source[source.index(start):source.index(end, source.index(start))]

lua.execute((here / "mock_wow.lua").read_text())
lua.execute((here / "setup.lua").read_text())
# Compile original function bodies against minimal module locals; guards are not
# reimplemented in the mock. This catches regressions in the production writers.
lua.execute("local ns, EUI, _windows, MIN_W, MIN_H, MAX_WINDOWS = DM, EllesmereUI, DM._windows, 150, 50, 5\n"
            "local function DB() return CONFIG end\nlocal function WinDB() return SAVED end\n"
            + section(dm, "ns.ApplyWinPosition = function", "-- Bookmarks are shared")
            + section(dm, "ns.RegisterDMUnlock = function", "local _combatEndTime")
            + section(dm, "ns.ApplyDMSize = function", "-- Standalone Combat Timer"))
lua.execute("local ns, EUI, ECHAT = CHAT, EllesmereUI, CHAT.ECHAT\nlocal CFD = EUI._chatCFD\n"
            "local _sidebarFadeTarget, _sidebarFadeAlpha = 1, 1\nlocal function GetTabAreaHeight() return 24 end\n"
            + section(chat, "function ECHAT.ApplySidebarIconVisibility()", "-- Map of sidebar-icon visibility key"))
lua.execute("local ns, ECHAT, WINS = CHAT, CHAT.ECHAT, CHAT._chatWins\n"
            "local function IsCombatLog(cf) return cf == ChatFrame2 end\n"
            "local function SetBarMouse() end\nlocal function RebuildWindowFromBuffer() end\n"
            + section(engine, "function ECHAT.EngineUpdateCombatLogHost()", "--  Mirrors, on our own standalone event frame"))
lua.execute("function InstallWindowWriters(W)\nlocal frame, wdb, EUI, ns = W.frame, SAVED, EllesmereUI, DM\n"
            "local function DB() return CONFIG end\n"
            + section(dm, "    function W.UpdateVisibility()", "    if EUI.RegisterVisibilityUpdater then EUI.RegisterVisibilityUpdater(W.UpdateVisibility)")
            + "\nW.ApplyPosition = function() DM.ApplyWinPosition(frame, wdb, W.idx) end\nend")
lua.execute("for i,w in ipairs(DM._windows) do w.idx=i; InstallWindowWriters(w) end")
lua.execute((root / paths[1]).read_text(), "EllesmereUIDamageMeters", lua.globals().DM)
lua.execute((here / "scenarios.lua").read_text())
print("PASS: Lua 5.1 syntax, lazy opt-in, native ownership, sidebar and lifecycle regressions")
