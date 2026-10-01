"""Update-safe companion behavior and packaging tests under Lua 5.1.

The simulated APIs cannot establish live-client security, layout or server
behavior. The canonical controller's full behavioral suite remains separate.
"""
from pathlib import Path
import hashlib
import subprocess
import sys
import tempfile
import unittest
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE / "dependencies"))
sys.path.insert(0, str(ROOT.parent / "tests" / "dependencies"))
from lupa.lua51 import LuaRuntime

MOCKS = (HERE / "mythic_start_mocks.lua").read_text(encoding="utf-8")
BOOTSTRAP_PATH = HERE / "companion_bootstrap.lua"
MODULE_PATH = ROOT / "EllesmereUIQoL" / "EllesmereUIQoL_MythicStart.lua"
BUILDER = HERE / "build_companion.py"
ADDON_NAME = "EllesmereUI_MythicStart"


class CompanionTests(unittest.TestCase):
    def lua(self, before="", login=True):
        vm = LuaRuntime(unpack_returned_tuples=True)
        vm.execute(MOCKS)
        vm.execute("""
            SlashCmdList = {}
            function IsLoggedIn() return false end
            addonRuntime = {}
        """)
        if before:
            vm.execute(before)
        load = vm.eval("function(source) assert(loadstring(source))('EllesmereUI_MythicStart', addonRuntime) end")
        load(BOOTSTRAP_PATH.read_text(encoding="utf-8"))
        load(MODULE_PATH.read_text(encoding="utf-8"))
        if login:
            vm.execute("Harness.emit('PLAYER_LOGIN')")
        return vm

    def test_defaults_enable_manual_controls_without_automation(self):
        vm = self.lua("EllesmereUIDB = nil")
        vm.execute("""
            assert(EllesmereUIMythicStartDB.mythicKeystoneControls == true)
            assert(EllesmereUIMythicStartDB.autoKeystoneReadyCheck == false)
            assert(EllesmereUIMythicStartDB.autoStartKeystone == false)
            assert(addonRuntime.GetOptions() == EllesmereUIMythicStartDB)
            assert(EllesmereUI._applyKeystoneStart == nil)
            Harness.open(); Harness.slot(); Harness.advance(40)
            assert(Harness.button('READY'):IsShown() and Harness.button('PULL'):IsShown())
            assert(Harness.readyRequests == 0 and #Harness.countdowns == 0 and Harness.startRequests == 0)
        """)

    def test_legacy_automation_migrates_once_and_preserves_explicit_false(self):
        for legacy in ("true", "false", "nil", "'true'"):
            with self.subTest(legacy=legacy):
                vm = self.lua(f"""
                    EllesmereUIDB.autoKeystoneReadyCheck = {legacy}
                    EllesmereUIDB.autoStartKeystone = {legacy}
                    EllesmereUIDB.mythicKeystoneControls = false
                """)
                vm.execute(f"""
                    assert(EllesmereUIMythicStartDB.mythicKeystoneControls == true)
                    assert(EllesmereUIMythicStartDB.autoKeystoneReadyCheck == {str(legacy == 'true').lower()})
                    assert(EllesmereUIMythicStartDB.autoStartKeystone == {str(legacy == 'true').lower()})
                    assert(EllesmereUIDB.autoStartKeystone == {legacy})
                """)
        vm = self.lua("""
            EllesmereUIDB.autoKeystoneReadyCheck = true; EllesmereUIDB.autoStartKeystone = true
            EllesmereUIMythicStartDB = {mythicKeystoneControls=false, autoKeystoneReadyCheck=false, autoStartKeystone=false}
        """)
        vm.execute("""
            assert(EllesmereUIMythicStartDB.mythicKeystoneControls == false)
            assert(EllesmereUIMythicStartDB.autoKeystoneReadyCheck == false and EllesmereUIMythicStartDB.autoStartKeystone == false)
            Harness.open(); Harness.slot(); Harness.emit('PLAYER_LOGIN')
            assert(Harness.button('READY') == nil and Harness.button('PULL') == nil)
        """)

    def test_private_settings_survive_core_profile_and_database_reset(self):
        vm = self.lua("EllesmereUIMythicStartDB = {mythicKeystoneControls=true, autoKeystoneReadyCheck=false, autoStartKeystone=true}")
        vm.execute("""
            local private = EllesmereUIMythicStartDB
            Harness.group = 'instance'; Harness.open(); Harness.slot()
            Harness.click('EllesmerePullButton'); Harness.advance(1)
            EllesmereUIDB = {mythicKeystoneControls=false, autoStartKeystone=false}
            EllesmereUI.RefreshAllAddons(); EllesmereUI.SwitchProfile(); EllesmereUI.ApplyProfileData()
            EllesmereUIDB = nil
            Harness.advance(4)
            assert(EllesmereUIMythicStartDB == private and addonRuntime.GetOptions() == private)
            assert(private.autoStartKeystone and private.mythicKeystoneControls)
            assert(Harness.startRequests == 1 and Harness.chat[#Harness.chat].message == 'GO!')
            for _, message in ipairs(Harness.chat) do assert(message.channel == 'INSTANCE_CHAT') end
        """)

    def test_ready_never_pulls_even_with_private_auto_start_enabled(self):
        vm = self.lua("EllesmereUIMythicStartDB = {mythicKeystoneControls=true, autoKeystoneReadyCheck=false, autoStartKeystone=true}")
        vm.execute("""
            Harness.open(); Harness.slot(); Harness.ready(); Harness.allReady(); Harness.advance(40)
            assert(Harness.readyRequests == 1 and #Harness.countdowns == 0 and Harness.startRequests == 0)
            assert(#Harness.localChat == 1)
            Harness.click('EllesmerePullButton', false, 'RightButton')
            assert(#Harness.countdowns == 1 and Harness.countdowns[1] == 10)
        """)

    def test_left_five_right_ten_emit_one_group_countdown(self):
        for mouse, seconds in (("LeftButton", 5), ("RightButton", 10)):
            with self.subTest(mouse=mouse):
                vm = self.lua()
                vm.execute(f"""
                    Harness.group = 'instance'; Harness.open(); Harness.slot()
                    Harness.click('EllesmerePullButton', false, '{mouse}'); Harness.advance({seconds})
                    assert(#Harness.countdowns == 1 and Harness.countdowns[1] == {seconds})
                    assert(#Harness.chat == {seconds + 2})
                    assert(Harness.chat[1].message == 'Pull in {seconds}' and Harness.chat[2].message == '{seconds}')
                    assert(Harness.chat[#Harness.chat].message == 'GO!')
                    for _, message in ipairs(Harness.chat) do assert(message.channel == 'INSTANCE_CHAT') end
                    assert(#Harness.localChat == 0 and Harness.startRequests == 0)
                """)

    def test_either_click_cancels_pull_and_private_auto_start(self):
        for start, seconds in (("LeftButton", 5), ("RightButton", 10)):
            for cancel in ("LeftButton", "RightButton"):
                with self.subTest(start=start, cancel=cancel):
                    vm = self.lua("EllesmereUIMythicStartDB = {mythicKeystoneControls=true, autoKeystoneReadyCheck=false, autoStartKeystone=true}")
                    vm.execute(f"""
                        Harness.group = 'instance'; Harness.open(); Harness.slot()
                        Harness.click('EllesmerePullButton', false, '{start}'); Harness.advance(1)
                        local ticker = Harness.timers[#Harness.timers]
                        Harness.click('EllesmerePullButton', false, '{cancel}')
                        local messages = #Harness.chat
                        ticker.fn(ticker); Harness.advance(20)
                        assert(#Harness.chat == messages and Harness.chat[messages].message == 'Pull cancelado!')
                        assert(Harness.chat[messages].channel == 'INSTANCE_CHAT')
                        assert(#Harness.countdowns == 2 and Harness.countdowns[1] == {seconds} and Harness.countdowns[2] == 0)
                        assert(Harness.startRequests == 0 and Harness.liveTimers() == 0)
                        assert(EllesmereUIMythicStartDB.autoStartKeystone == true)
                    """)

    def test_loading_defers_controller_and_settings_until_login(self):
        vm = self.lua("EllesmereUIDB = nil", login=False)
        vm.execute("""
            assert(EllesmereUIMythicStartDB == nil and addonRuntime.GetOptions() == nil)
            assert(type(addonRuntime.Apply) == 'function' and EllesmereUI._applyKeystoneStart == nil)
            assert(Harness.frameCreates == 3 and Harness.methodHooks == 0 and Harness.liveTimers() == 0)
            assert(Harness.button('READY') == nil and Harness.button('PULL') == nil)
            addonRuntime.Apply(); Harness.emit('CHALLENGE_MODE_KEYSTONE_SLOTTED')
            assert(Harness.frameCreates == 3)
        """)
        vm.execute("Harness.emit('PLAYER_LOGIN'); Harness.open(); Harness.slot(); assert(Harness.button('PULL'):IsShown())")

    def test_builtin_controller_takes_precedence_without_duplicates(self):
        vm = self.lua("""
            Harness.builtinCalls = 0
            builtin = function() Harness.builtinCalls = Harness.builtinCalls + 1 end
            EllesmereUI._applyKeystoneStart = builtin
        """)
        vm.execute("""
            assert(EllesmereUI._applyKeystoneStart == builtin and addonRuntime.GetOptions() == nil)
            Harness.open(); Harness.slot(); Harness.emit('ADDON_LOADED', 'OtherAddon')
            assert(Harness.button('READY') == nil and Harness.button('PULL') == nil)
            assert(Harness.methodHooks == 0 and Harness.liveTimers() == 0 and Harness.builtinCalls == 0)
            assert(#Harness.chat == 0 and #Harness.countdowns == 0)
        """)

    def test_late_builtin_yields_and_invalidates_pending_work(self):
        vm = self.lua("EllesmereUIMythicStartDB = {mythicKeystoneControls=true, autoKeystoneReadyCheck=false, autoStartKeystone=true}")
        vm.execute("""
            Harness.open(); Harness.slot(); Harness.click('EllesmerePullButton'); Harness.advance(1)
            local timer = Harness.timers[#Harness.timers]
            local builtin = function() error('companion must not invoke builtin') end
            EllesmereUI._applyKeystoneStart = builtin
            Harness.emit('ADDON_LOADED', 'FutureIntegratedModule')
            assert(EllesmereUI._applyKeystoneStart == builtin and addonRuntime.GetOptions() == nil)
            assert(not Harness.button('READY'):IsShown() and not Harness.button('PULL'):IsShown())
            local messages = #Harness.chat
            timer.fn(timer); Harness.advance(20)
            Harness.click('EllesmerePullButton', true)
            assert(#Harness.chat == messages and Harness.startRequests == 0 and Harness.liveTimers() == 0)
        """)

    def test_blocked_client_and_forever_allocate_no_addon_frames(self):
        for gate in ("EUI_CLIENT_BLOCKED = true", "EllesmereUI.IS_FOREVER = true"):
            with self.subTest(gate=gate):
                vm = self.lua(gate)
                vm.execute("""
                    assert(Harness.frameCreates == 2 and Harness.methodHooks == 0)
                    assert(EllesmereUIMythicStartDB == nil and addonRuntime.Apply == nil)
                    assert(EllesmereUI._applyKeystoneStart == nil and Harness.liveTimers() == 0)
                    assert(Harness.button('READY') == nil and Harness.button('PULL') == nil)
                """)

    def test_companion_sources_compile_as_lua51(self):
        vm = LuaRuntime(unpack_returned_tuples=True)
        compile_chunk = vm.eval("function(source) local chunk, err = loadstring(source); assert(chunk, err) end")
        for path in (BOOTSTRAP_PATH, MODULE_PATH):
            with self.subTest(path=path.name):
                compile_chunk(path.read_text(encoding="utf-8"))

    def test_package_reproduces_canonical_runtime_without_modifying_core(self):
        core = [ROOT / "EllesmereUIQoL" / "EllesmereUIQoL.lua",
                ROOT / "EllesmereUIQoL" / "EllesmereUIQoL.toc",
                ROOT / "EllesmereUIOptions" / "EUI_QoL_Options.lua",
                ROOT / "EllesmereUIOptions" / "EUI__General_Options.lua", MODULE_PATH]
        before = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in core}
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            outputs = []
            archives = []
            for n in (1, 2):
                destination, archive = directory / str(n), directory / f"{n}.zip"
                result = subprocess.run([sys.executable, str(BUILDER), "--root", str(ROOT),
                                         "--output-dir", str(destination), "--zip", str(archive)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                outputs.append(destination / ADDON_NAME)
                archives.append(archive)
            files = {path.name: path.read_bytes() for path in outputs[0].iterdir() if path.is_file()}
            self.assertEqual(set(files), {f"{ADDON_NAME}.toc", BOOTSTRAP_PATH.name, MODULE_PATH.name})
            self.assertEqual(files[MODULE_PATH.name], MODULE_PATH.read_bytes())
            self.assertEqual(files[BOOTSTRAP_PATH.name], BOOTSTRAP_PATH.read_bytes())
            toc = files[f"{ADDON_NAME}.toc"].decode("utf-8")
            self.assertIn("## Dependencies: EllesmereUI, EllesmereUIQoL", toc)
            self.assertIn("## SavedVariables: EllesmereUIMythicStartDB", toc)
            self.assertLess(toc.index(BOOTSTRAP_PATH.name), toc.index(MODULE_PATH.name))
            self.assertNotIn(str(ROOT), toc)
            self.assertEqual(files, {path.name: path.read_bytes() for path in outputs[1].iterdir() if path.is_file()})
            self.assertEqual(archives[0].read_bytes(), archives[1].read_bytes())
            with zipfile.ZipFile(archives[0]) as archive:
                self.assertEqual(set(archive.namelist()), {f"{ADDON_NAME}/{name}" for name in files})
                for name, data in files.items():
                    self.assertEqual(archive.read(f"{ADDON_NAME}/{name}"), data)
        self.assertEqual(before, {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in core})


if __name__ == "__main__":
    unittest.main(verbosity=2)
