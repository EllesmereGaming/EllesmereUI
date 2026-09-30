"""Behavioral tests for the isolated Retail Mythic+ Start block under Lua 5.1.

Run with the bundled Python after installing lupa into tests/dependencies.
Mocks model API events explicitly; they cannot establish live-client secure-call,
visual, addon-interaction, or server behavior.
"""
from pathlib import Path
import os
import re
import sys
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent if HERE.parent.name == ".tools" else HERE.parent
sys.path.insert(0, str(HERE / "dependencies"))
sys.path.insert(0, str(ROOT.parent / "tests" / "dependencies"))
from lupa.lua51 import LuaRuntime

ADDON = Path(os.environ.get("ELLESMERE_TEST_ADDON_ROOT", ROOT))
SOURCE_PATH = ADDON / "EllesmereUIQoL" / "EllesmereUIQoL.lua"
SOURCE = SOURCE_PATH.read_text(encoding="utf-8-sig")
MATCH = re.search(r"^    --  Auto Insert Keystone.*?(?=^    --  Quick Signup)", SOURCE, re.M | re.S)
if not MATCH:
    raise RuntimeError("Cannot locate Mythic+ Start block in addon source")
BLOCK = MATCH.group(0)
FEATURE_MATCH = re.search(r"^[ \t]*--  Mythic\+ Start", BLOCK, re.M)
if not FEATURE_MATCH:
    raise RuntimeError("Cannot locate opt-in Mythic+ Start block")
# The opt-in controller shares the original outer Forever guard. Close that
# guard when running the unchanged Auto Insert prefix as our baseline.
AUTO_INSERT_BLOCK = BLOCK[:FEATURE_MATCH.start()] + '\n    end\n'
MOCKS = (HERE / "mythic_start_mocks.lua").read_text(encoding="utf-8")


class MythicStartTests(unittest.TestCase):
    def lua(self, setup="", before_load="", source=BLOCK):
        vm = LuaRuntime(unpack_returned_tuples=True)
        vm.execute(MOCKS)
        if before_load:
            vm.execute(before_load)
        vm.execute(source)
        if setup:
            vm.execute(setup)
        return vm

    def scenario(self, statements, setup="Harness.open(); Harness.slot()", before_load=""):
        vm = self.lua(setup, before_load)
        vm.execute(statements)
        return vm

    def test_01_original_solo_auto_insert_behavior_preserved(self):
        self.scenario("""
            assert(Harness.slotRequests == 2 and Harness.pickups == 2)
            assert(Harness.readyRequests == 0)
            Harness.emit('CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN')
            assert(Harness.slotRequests == 3)
            Harness.slot()
            assert(Harness.readyRequests == 0)
        """, "Harness.group = 'solo'; Harness.open()")

    def test_02_manual_slot_starts_optional_ready_once(self):
        self.scenario("""
            assert(Harness.slotRequests == 0 and Harness.readyRequests == 1)
            Harness.emit('CHALLENGE_MODE_KEYSTONE_SLOTTED')
            Harness.click('EllesmereReadyButton', true)
            assert(Harness.readyRequests == 1)
        """, "EllesmereUIDB.autoInsertKeystone = false; EllesmereUIDB.autoKeystoneReadyCheck = true; Harness.open(); Harness.slot()")

    def test_03_all_ready_requires_manual_pull(self):
        self.scenario("""
            EllesmereUIDB.autoKeystoneReadyCheck = true
            EllesmereUIDB.autoKeystoneCountdown = true -- stale legacy value must do nothing
            Harness.ready(); Harness.allReady(); Harness.advance(40)
            assert(#Harness.countdowns == 0 and Harness.startRequests == 0)
            assert(#Harness.localChat == 1 and Harness.localChat[1]:find('Everyone is ready', 1, true))
            Harness.click('EllesmerePullButton', false, 'RightButton')
            assert(#Harness.countdowns == 1 and Harness.countdowns[1] == 10)
        """)

    def test_04_not_ready_never_starts_countdown(self):
        self.scenario("""
            Harness.ready(); Harness.respond('party1', false); Harness.respond('party2', true)
            Harness.finish(false); Harness.advance(40)
            assert(#Harness.countdowns == 0 and #Harness.localChat == 0)
            Harness.click('EllesmereReadyButton'); assert(Harness.readyRequests == 2)
        """)

    def test_05_ready_expiration_fails_closed(self):
        self.scenario("""
            Harness.ready(); Harness.respond('party1', true); Harness.advance(30)
            Harness.finish(false)
            assert(#Harness.countdowns == 0 and #Harness.localChat == 0)
            assert(Harness.liveTimers() == 0)
            Harness.click('EllesmereReadyButton'); assert(Harness.readyRequests == 2)
        """)

    def test_06_manual_pull5_exact_chat(self):
        self.scenario("""
            Harness.click('EllesmerePullButton'); Harness.advance(5)
            local expected = {'Pull in 5', '5', '4', '3', '2', '1', 'GO!'}
            assert(#Harness.chat == #expected)
            for i, value in ipairs(expected) do assert(Harness.chat[i].message == value); assert(Harness.chat[i].channel == 'PARTY') end
            assert(#Harness.countdowns == 1 and Harness.countdowns[1] == 5)
            assert(#Harness.localChat == 0)
            assert(Harness.liveTimers() == 0)
        """)

    def test_07_manual_pull10_exact_chat(self):
        self.scenario("""
            Harness.click('EllesmerePullButton', false, 'RightButton'); Harness.advance(10)
            assert(#Harness.chat == 12 and Harness.chat[1].message == 'Pull in 10')
            for i = 10, 1, -1 do assert(Harness.chat[12-i].message == tostring(i)) end
            assert(Harness.chat[12].message == 'GO!')
            assert(#Harness.countdowns == 1 and Harness.countdowns[1] == 10)
            assert(#Harness.localChat == 0)
        """)

    def test_08_single_pull_and_ready_share_official_button_row(self):
        self.scenario("""
            local f = ChallengesKeystoneFrame
            assert(Harness.button('EllesmereReadyButton').text == 'READY')
            assert(Harness.button('EllesmerePullButton').text == 'PULL')
            assert(f.EllesmerePull5Button == nil and f.EllesmerePull10Button == nil)
            assert(f.EllesmereReadyButton == nil and f.EllesmerePullButton == nil)
            for _, key in ipairs({'EllesmereReadyButton', 'EllesmerePullButton'}) do
                local button = Harness.button(key)
                assert(button.parent == f and button.point[2] == f.StartButton)
                assert(button.point[5] == 0)
            end
            assert(Harness.button('EllesmereReadyButton').point[1] == 'RIGHT' and Harness.button('EllesmereReadyButton').point[3] == 'LEFT')
            assert(Harness.button('EllesmereReadyButton').point[4] == -8)
            assert(Harness.button('EllesmerePullButton').point[1] == 'LEFT' and Harness.button('EllesmerePullButton').point[3] == 'RIGHT')
            assert(Harness.button('EllesmerePullButton').point[4] == 8)
            assert(Harness.button('EllesmerePullButton').clicks[1] == 'LeftButtonUp' and Harness.button('EllesmerePullButton').clicks[2] == 'RightButtonUp')
        """)

    def test_09_either_click_cancels_active_pull_and_pending_auto_start(self):
        for start_button, seconds in [('LeftButton', 5), ('RightButton', 10)]:
            for cancel_button in ('LeftButton', 'RightButton'):
                with self.subTest(start=start_button, cancel=cancel_button):
                    self.scenario(f"""
                        EllesmereUIDB.autoStartKeystone = true
                        Harness.click('EllesmerePullButton', false, '{start_button}'); Harness.advance(2)
                        local oldTicker = Harness.timers[#Harness.timers]
                        Harness.click('EllesmerePullButton', false, '{cancel_button}')
                        local before = #Harness.chat
                        oldTicker.fn(oldTicker) -- a queued callback cannot revive a canceled pull
                        Harness.advance(20)
                        local expected = {{'Pull in {seconds}','{seconds}','{seconds-1}','{seconds-2}','Pull cancelado!'}}
                        assert(#Harness.chat == before and #Harness.chat == #expected)
                        for i, v in ipairs(expected) do assert(Harness.chat[i].message == v) end
                        assert(oldTicker.canceled and Harness.liveTimers() == 0 and Harness.startRequests == 0)
                        assert(#Harness.countdowns == 2 and Harness.countdowns[1] == {seconds} and Harness.countdowns[2] == 0)
                        assert(EllesmereUIDB.autoStartKeystone == true and #Harness.localChat == 0)
                    """)

    def test_10_close_cancels_chat_and_start(self):
        self.scenario("""
            EllesmereUIDB.autoStartKeystone = true
            Harness.click('EllesmerePullButton', false, 'RightButton'); Harness.advance(2)
            ChallengesKeystoneFrame:Hide(); local count = #Harness.chat
            Harness.emit('START_PLAYER_COUNTDOWN', UnitGUID('player'), 10)
            Harness.advance(20)
            assert(#Harness.chat == count and Harness.startRequests == 0 and Harness.liveTimers() == 0)
        """)

    def test_11_challenge_start_cancels_remaining_work(self):
        self.scenario("""
            EllesmereUIDB.autoStartKeystone = true
            Harness.click('EllesmerePullButton', false, 'RightButton'); Harness.advance(2)
            Harness.active = true; Harness.emit('CHALLENGE_MODE_START')
            local count = #Harness.chat; Harness.advance(20)
            Harness.click('EllesmereReadyButton', true); Harness.click('EllesmerePullButton', true)
            assert(#Harness.chat == count and Harness.startRequests == 0 and Harness.readyRequests == 0)
            assert(#Harness.countdowns == 1 and Harness.liveTimers() == 0)
        """)

    def test_12_normal_member_actions_are_inert(self):
        self.scenario("""
            local f = ChallengesKeystoneFrame
            assert(not Harness.button('EllesmereReadyButton'):IsEnabled() and not Harness.button('EllesmerePullButton'):IsEnabled())
            Harness.click('EllesmereReadyButton', true); Harness.click('EllesmerePullButton', true)
            assert(Harness.readyRequests == 0 and #Harness.countdowns == 0 and #Harness.localChat == 0)
        """, "Harness.leader = false; Harness.open(); Harness.slot()")

    def test_13_auto_start_off(self):
        self.scenario("Harness.click('EllesmerePullButton'); Harness.advance(10); assert(Harness.startRequests == 0)")

    def test_14_auto_start_allowed_once_and_rejection_safe(self):
        for result in ("true", "false", "nil", "'error'"):
            with self.subTest(result=result):
                self.scenario(f"""
                    EllesmereUIDB.autoStartKeystone = true
                    Harness.startReturn = {result}; Harness.startError = Harness.startReturn == 'error'
                    Harness.click('EllesmerePullButton'); Harness.advance(5)
                    assert(Harness.startRequests == 1)
                    Harness.click('EllesmerePullButton', true); Harness.advance(10)
                    assert(Harness.startRequests == 1)
                """)

    def test_15_settings_not_mutated_and_profile_refresh_cancels(self):
        self.scenario("""
            EllesmereUIDB.autoInsertKeystone = false; EllesmereUIDB.autoKeystoneReadyCheck = true
            EllesmereUIDB.autoStartKeystone = true
            Harness.click('EllesmerePullButton'); Harness.advance(1)
            EllesmereUI.RefreshAllAddons(); Harness.advance(10)
            assert(Harness.startRequests == 0 and Harness.liveTimers() == 0)
            assert(EllesmereUIDB.autoInsertKeystone == false and EllesmereUIDB.autoKeystoneReadyCheck == true and EllesmereUIDB.autoStartKeystone == true)
        """)

    def test_16_twenty_open_close_cycles_no_duplicate_buttons_hooks(self):
        self.scenario("""
            local f, created, hooks = ChallengesKeystoneFrame, Harness.frameCreates, Harness.methodHooks
            local ready, pull = Harness.button('EllesmereReadyButton'), Harness.button('EllesmerePullButton')
            for i = 1, 20 do f:Hide(); f:Show() end
            assert(Harness.frameCreates == created and Harness.methodHooks == hooks)
            assert(Harness.button('EllesmereReadyButton') == ready and Harness.button('EllesmerePullButton') == pull)
            assert(#f.hooks.OnShow == 2 and #f.hooks.OnHide == 1)
        """)

    def test_17_no_unrelated_frame_or_library_references_in_block(self):
        forbidden = ('RaiderIO', 'PVEFrame', 'GameTooltip', 'LFGList', 'LibMythicKeystone', 'LibKeystone')
        for name in forbidden:
            self.assertNotIn(name, BLOCK)

    def test_18_no_external_keystone_library_needed(self):
        self.scenario("Harness.click('EllesmerePullButton'); Harness.advance(5); assert(Harness.chat[#Harness.chat].message == 'GO!')", before_load="LibStub = nil; LibMythicKeystone = nil")

    def test_19_20_21_bossmods_never_called_official_api_once(self):
        for mod in ('DBM', 'BigWigs', 'none'):
            with self.subTest(mod=mod):
                setup = """local fail = function() error('must not call boss mod API') end
                    DBM = {CreatePizzaTimer = fail, StartPull = fail}; BigWigs = {SendMessage = fail}
                """ if mod != 'none' else 'DBM = nil; BigWigs = nil'
                self.scenario("""
                    Harness.countdownReturn = nil -- wrapped API need not forward return value
                    Harness.click('EllesmerePullButton', false, 'RightButton'); Harness.advance(10)
                    assert(#Harness.countdowns == 1 and Harness.chat[#Harness.chat].message == 'GO!')
                """, before_load=setup)

    def test_22_group_composition_change_aborts_ready_and_pull(self):
        for action in ('ready', 'pull'):
            with self.subTest(action=action):
                self.scenario(f"""
                    EllesmereUIDB.autoStartKeystone = true
                    {'Harness.ready()' if action == 'ready' else "Harness.click('EllesmerePullButton', false, 'RightButton')"}
                    Harness.guids.party1 = 'new-member'; Harness.emit('GROUP_ROSTER_UPDATE')
                    local count = #Harness.chat; Harness.allReady(); Harness.advance(40)
                    assert(#Harness.chat == count and Harness.startRequests == 0 and Harness.liveTimers() == 0)
                    assert(#Harness.localChat == 0)
                """)

    def test_23_losing_leadership_aborts_autostart(self):
        self.scenario("""
            EllesmereUIDB.autoStartKeystone = true
            Harness.click('EllesmerePullButton'); Harness.advance(2)
            Harness.leader = false; Harness.emit('PARTY_LEADER_CHANGED')
            Harness.advance(10); assert(Harness.startRequests == 0 and Harness.liveTimers() == 0)
        """)

    def test_24_removed_keystone_resets_everything(self):
        for removal in ("ChallengesKeystoneFrame:Reset()", "Harness.slotted = nil; Harness.emit('CHALLENGE_MODE_KEYSTONE_SLOTTED')"):
            with self.subTest(removal=removal):
                self.scenario(f"""
                    EllesmereUIDB.autoStartKeystone = true
                    Harness.click('EllesmerePullButton'); Harness.advance(1)
                    {removal}
                    local count = #Harness.chat; Harness.advance(10)
                    assert(Harness.startRequests == 0 and #Harness.chat == count and Harness.liveTimers() == 0)
                """)

    def test_25_existing_slot_skips_insertion(self):
        self.scenario("assert(Harness.slotRequests == 0 and Harness.pickups == 0)", "Harness.slotted = {399, {9}, 12}; Harness.open()")

    def test_26_countdown_requires_matching_official_ack(self):
        for ack in ('missing', 'other', 'wrong-duration'):
            with self.subTest(ack=ack):
                self.scenario(f"""
                    EllesmereUIDB.autoStartKeystone = true; Harness.autoAckCountdown = false
                    Harness.click('EllesmerePullButton'); assert(#Harness.chat == 0)
                    {"Harness.emit('START_PLAYER_COUNTDOWN', 'Player-other', 5, 5)" if ack == 'other' else "Harness.emit('START_PLAYER_COUNTDOWN', UnitGUID('player'), 10, 10)" if ack == 'wrong-duration' else ''}
                    Harness.advance(20)
                    assert(#Harness.chat == 0 and Harness.startRequests == 0 and Harness.liveTimers() == 0)
                """)

    def test_27_ready_missing_answers_preempted_or_ambiguous_never_reports_all_ready(self):
        for kind in ('missing', 'preempted', 'nil-finish', 'ambiguous'):
            with self.subTest(kind=kind):
                self.scenario(f"""
                    Harness.click('EllesmereReadyButton')
                    {'Harness.names.party1 = "Tester"; Harness.ackReady("Tester")' if kind == 'ambiguous' else 'Harness.ackReady()'}
                    Harness.respond('party1', true)
                    {"Harness.respond('party2', true)" if kind != 'missing' else ''}
                    Harness.finish({'true' if kind == 'preempted' else 'nil' if kind == 'nil-finish' else 'false'})
                    assert(#Harness.countdowns == 0 and #Harness.localChat == 0)
                """)

    def test_28_channel_selection_solo_instance_raid_party(self):
        for group, channel in [('solo', None), ('instance', 'INSTANCE_CHAT'), ('raid', 'RAID'), ('party', 'PARTY')]:
            with self.subTest(group=group):
                self.scenario(f"""
                    Harness.click('EllesmerePullButton'); Harness.advance(5)
                    {"assert(#Harness.chat == 0 and #Harness.localChat == 0)" if channel is None else f"assert(#Harness.chat == 7); for _, m in ipairs(Harness.chat) do assert(m.channel == '{channel}') end"}
                """, f"Harness.group = '{group}'; Harness.open(); Harness.slot()")

    def test_29_raid_assistant_allowed_party_assistant_denied(self):
        for group, count in [('raid', 1), ('party', 0)]:
            with self.subTest(group=group):
                self.scenario(f"Harness.click('EllesmerePullButton', true); assert(#Harness.countdowns == {count})", f"Harness.group = '{group}'; Harness.leader = false; Harness.assistant = true; Harness.open(); Harness.slot()")

    def test_30_combat_and_chat_lockdown_cancel_pending_work(self):
        for lock in ('combat', 'chatLocked'):
            with self.subTest(lock=lock):
                self.scenario(f"""
                    EllesmereUIDB.autoStartKeystone = true
                    Harness.click('EllesmerePullButton'); Harness.advance(1)
                    Harness.{lock} = true
                    {"Harness.emit('PLAYER_REGEN_DISABLED')" if lock == 'combat' else ''}
                    local count = #Harness.chat; Harness.advance(10)
                    Harness.click('EllesmerePullButton', true)
                    assert(Harness.startRequests == 0 and #Harness.chat == count and #Harness.countdowns == 1)
                """)

    def test_31_late_frame_loading_hooks_once(self):
        self.scenario("""
            Harness.makeKeystoneFrame(); Harness.emit('ADDON_LOADED', 'Unrelated')
            assert(Harness.button('EllesmereReadyButton') == nil)
            Harness.emit('ADDON_LOADED', 'Blizzard_ChallengesUI')
            Harness.open(); Harness.slot(); Harness.click('EllesmerePullButton'); Harness.advance(5)
            assert(#Harness.countdowns == 1 and #ChallengesKeystoneFrame.hooks.OnShow == 2)
        """, setup="", before_load="ChallengesKeystoneFrame = nil")

    def test_32_absent_apis_and_forever_are_safe(self):
        for before in ('C_ChallengeMode = nil', 'C_PartyInfo = nil', 'C_Container = nil', 'C_ChatInfo = nil', 'EllesmereUI.MakeStyledButton = nil'):
            with self.subTest(before=before):
                self.scenario('Harness.advance(10)', before_load=before + '; EllesmereUIDB.autoInsertKeystone = false')
        self.scenario("assert(EllesmereUI._applyKeystoneStart == nil and Harness.frameCreates == 2)", setup="", before_load="EllesmereUI.IS_FOREVER = true")

    def test_33_cancel_world_profile_and_disabled_official_start(self):
        for event in ('CANCEL_PLAYER_COUNTDOWN', 'PLAYER_ENTERING_WORLD', 'profile'):
            with self.subTest(event=event):
                self.scenario(f"""
                    EllesmereUIDB.autoStartKeystone = true
                    Harness.click('EllesmerePullButton'); Harness.advance(1)
                    {"EllesmereUI._applyKeystoneStart()" if event == 'profile' else f"Harness.emit('{event}', UnitGUID('player'))"}
                    local count = #Harness.chat; Harness.advance(10)
                    assert(#Harness.chat == count and Harness.startRequests == 0)
                """)
        self.scenario("""
            EllesmereUIDB.autoStartKeystone = true; ChallengesKeystoneFrame.StartButton:SetEnabled(false)
            Harness.click('EllesmerePullButton'); Harness.advance(5)
            assert(Harness.startRequests == 0 and #Harness.localChat == 1)
        """)

    def test_34_auto_start_setting_changes_are_conservative(self):
        for initially in ('true', 'false'):
            with self.subTest(initially=initially):
                self.scenario(f"""
                    EllesmereUIDB.autoStartKeystone = {initially}
                    Harness.click('EllesmerePullButton'); Harness.advance(2)
                    EllesmereUIDB.autoStartKeystone = not EllesmereUIDB.autoStartKeystone
                    Harness.advance(5); assert(Harness.startRequests == 0)
                """)

    def test_35_ready_external_or_ack_missing_does_not_create_pull(self):
        self.scenario("""
            Harness.click('EllesmereReadyButton'); Harness.advance(3)
            assert(Harness.liveTimers() == 0)
            Harness.ackReady('party1'); Harness.allReady(); Harness.advance(10)
            assert(#Harness.countdowns == 0 and #Harness.localChat == 0)
        """)

    def test_36_chat_api_error_aborts_autostart(self):
        self.scenario("""
            EllesmereUIDB.autoStartKeystone = true; Harness.chatError = true
            Harness.click('EllesmerePullButton'); Harness.advance(10)
            assert(Harness.startRequests == 0 and Harness.liveTimers() == 0)
        """)

    def test_37_toc_and_saved_variables_defaults_remain_in_existing_addon(self):
        toc = (ADDON / 'EllesmereUIQoL' / 'EllesmereUIQoL.toc').read_text(encoding='utf-8-sig')
        self.assertTrue('LibMythicKeystone' not in toc, 'No LibMythicKeystone dependency in QoL TOC')
        main_toc = (ADDON / 'EllesmereUI.toc').read_text(encoding='utf-8-sig')
        self.assertTrue('## SavedVariables: EllesmereUIDB' in main_toc, 'Existing EllesmereUIDB declaration must remain')
        expected_files = (
            SOURCE_PATH,
            ADDON / 'EllesmereUIOptions' / 'EUI_QoL_Options.lua',
            ADDON / 'EllesmereUIOptions' / 'EUI__General_Options.lua',
        )
        for path in expected_files:
            contents = path.read_text(encoding='utf-8-sig')
            for name in ('autoInsertKeystone', 'mythicKeystoneControls', 'autoKeystoneReadyCheck', 'autoStartKeystone'):
                self.assertTrue(name in contents, f'{name} must exist in {path.name}')
        self.assertTrue('autoKeystoneCountdown' not in BLOCK, 'Ready must not enable an automatic countdown')

    def test_38_fractional_official_timeleft_synchronizes_chat(self):
        self.scenario("""
            Harness.autoAckCountdown = false; EllesmereUIDB.autoStartKeystone = true
            Harness.click('EllesmerePullButton', false, 'RightButton')
            Harness.emit('START_PLAYER_COUNTDOWN', UnitGUID('player'), 9.8, 10)
            assert(Harness.chat[1].message == 'Pull in 10' and Harness.chat[2].message == '10')
            Harness.advance(0.801) -- allow one millisecond for binary rounding
            assert(Harness.chat[3].message == '9')
            Harness.advance(8.989); assert(Harness.startRequests == 0)
            Harness.advance(0.02)
            assert(Harness.chat[#Harness.chat].message == 'GO!' and Harness.startRequests == 1)
        """)

    def test_39_cancel_with_nil_or_other_guid_including_pending_ack(self):
        for guid in ('nil', "'Player-other'"):
            for pending in ('true', 'false'):
                with self.subTest(guid=guid, pending=pending):
                    self.scenario(f"""
                        EllesmereUIDB.autoStartKeystone = true; Harness.autoAckCountdown = not {pending}
                        Harness.click('EllesmerePullButton')
                        Harness.emit('CANCEL_PLAYER_COUNTDOWN', {guid})
                        local count = #Harness.chat
                        Harness.emit('START_PLAYER_COUNTDOWN', UnitGUID('player'), 5, 5)
                        Harness.advance(10)
                        assert(#Harness.chat == count and Harness.startRequests == 0 and Harness.liveTimers() == 0)
                    """)

    def test_40_profile_switch_and_apply_cancel_work_directly(self):
        for method in ('SwitchProfile', 'ApplyProfileData'):
            for action in ('ready', 'pull'):
                with self.subTest(method=method, action=action):
                    self.scenario(f"""
                        EllesmereUIDB.autoStartKeystone = true
                        {'Harness.ready()' if action == 'ready' else "Harness.click('EllesmerePullButton')"}
                        EllesmereUI.{method}()
                        local count = #Harness.chat; Harness.allReady(); Harness.advance(40)
                        assert(#Harness.chat == count and Harness.startRequests == 0 and Harness.liveTimers() == 0)
                        assert(#Harness.localChat == 0)
                    """)

    def test_41_either_click_cancels_pending_ack_and_ignores_late_response(self):
        for start_button, seconds in [('LeftButton', 5), ('RightButton', 10)]:
            for cancel_button in ('LeftButton', 'RightButton'):
                with self.subTest(start=start_button, cancel=cancel_button):
                    self.scenario(f"""
                        Harness.autoAckCountdown = false; EllesmereUIDB.autoStartKeystone = true
                        Harness.click('EllesmerePullButton', false, '{start_button}')
                        assert(Harness.button('EllesmerePullButton'):IsEnabled())
                        local oldRequest = Harness.timers[#Harness.timers]
                        Harness.click('EllesmerePullButton', false, '{cancel_button}')
                        assert(#Harness.countdowns == 2 and Harness.countdowns[1] == {seconds} and Harness.countdowns[2] == 0)
                        assert(oldRequest.canceled and Harness.liveTimers() == 1)
                        assert(not Harness.button('EllesmerePullButton'):IsEnabled())
                        Harness.emit('START_PLAYER_COUNTDOWN', UnitGUID('player'), {seconds}, {seconds})
                        oldRequest.fn(oldRequest)
                        Harness.click('EllesmerePullButton', false, '{start_button}')
                        assert(#Harness.countdowns == 2)
                        Harness.advance(20)
                        assert(#Harness.chat == 1 and Harness.chat[1].message == 'Pull cancelado!')
                        assert(Harness.startRequests == 0 and Harness.liveTimers() == 0 and #Harness.localChat == 0)
                    """)

    def test_42_modified_lua_files_compile_under_lua51(self):
        vm = LuaRuntime(unpack_returned_tuples=True)
        compile_lua = vm.eval('function(source, name) local fn, err = loadstring(source, name); return fn ~= nil, err end')
        paths = (
            SOURCE_PATH,
            ADDON / 'EllesmereUIOptions' / 'EUI_QoL_Options.lua',
            ADDON / 'EllesmereUIOptions' / 'EUI__General_Options.lua',
        )
        for path in paths:
            with self.subTest(file=path.name):
                ok, error = compile_lua(path.read_text(encoding='utf-8-sig'), '@' + str(path))
                self.assertTrue(ok, f'{path.name}: {error}')

    def test_43_secret_ready_and_countdown_event_arguments_fail_closed(self):
        before = """
            Harness.secret = {secret = true}
            issecretvalue = function(value) return type(value) == 'table' and value.secret == true end
        """
        cases = (
            ('ready', "Harness.secret, 30"),
            ('ready', "'Tester-TestRealm', Harness.secret"),
            ('countdown', "Harness.secret, 5, 5"),
            ('countdown', "UnitGUID('player'), Harness.secret, 5"),
            ('countdown', "UnitGUID('player'), 5, Harness.secret"),
        )
        for action, arguments in cases:
            with self.subTest(action=action, arguments=arguments):
                self.scenario(f"""
                    EllesmereUIDB.autoStartKeystone = true; Harness.autoAckCountdown = false
                    {"Harness.click('EllesmereReadyButton')" if action == 'ready' else "Harness.click('EllesmerePullButton')"}
                    Harness.emit('{'READY_CHECK' if action == 'ready' else 'START_PLAYER_COUNTDOWN'}', {arguments})
                    Harness.allReady(); Harness.advance(40)
                    assert(#Harness.chat == 0 and #Harness.localChat == 0 and Harness.startRequests == 0)
                    assert(Harness.liveTimers() == 0)
                """, before_load=before)

    def test_44_missing_active_challenge_api_blocks_actions_and_pending_start(self):
        self.scenario("""
            EllesmereUIDB.autoStartKeystone = true
            Harness.click('EllesmereReadyButton', true); Harness.click('EllesmerePullButton', true)
            Harness.advance(10)
            assert(Harness.readyRequests == 0 and #Harness.countdowns == 0 and Harness.startRequests == 0)
        """, before_load="C_ChallengeMode.IsChallengeModeActive = nil")
        self.scenario("""
            EllesmereUIDB.autoStartKeystone = true
            Harness.click('EllesmerePullButton'); Harness.advance(1)
            C_ChallengeMode.IsChallengeModeActive = nil
            local count = #Harness.chat; Harness.advance(10)
            assert(Harness.startRequests == 0 and #Harness.chat == count and Harness.liveTimers() == 0)
        """)

    def test_45_middle_click_neither_starts_nor_cancels_pull(self):
        self.scenario("""
            Harness.click('EllesmerePullButton', true, 'MiddleButton')
            assert(#Harness.countdowns == 0 and #Harness.chat == 0)
            Harness.click('EllesmerePullButton'); Harness.advance(1)
            Harness.click('EllesmerePullButton', true, 'MiddleButton')
            Harness.advance(5)
            assert(#Harness.countdowns == 1 and #Harness.chat == 7 and Harness.chat[7].message == 'GO!')
        """)

    def test_46_click_after_cancel_starts_fresh_and_old_callback_cannot_interfere(self):
        for button, seconds in [('LeftButton', 5), ('RightButton', 10)]:
            with self.subTest(button=button):
                self.scenario(f"""
                    EllesmereUIDB.autoStartKeystone = true
                    Harness.click('EllesmerePullButton', false, 'RightButton'); Harness.advance(1)
                    local oldTicker = Harness.timers[#Harness.timers]
                    Harness.click('EllesmerePullButton')
                    Harness.click('EllesmerePullButton', false, '{button}')
                    local before = #Harness.chat
                    oldTicker.fn(oldTicker)
                    assert(#Harness.chat == before)
                    Harness.advance({seconds})
                    assert(#Harness.countdowns == 3 and Harness.countdowns[1] == 10 and Harness.countdowns[2] == 0 and Harness.countdowns[3] == {seconds})
                    local canceled, go = 0, 0
                    for _, m in ipairs(Harness.chat) do
                        if m.message == 'Pull cancelado!' then canceled = canceled + 1 end
                        if m.message == 'GO!' then go = go + 1 end
                    end
                    assert(canceled == 1 and go == 1 and Harness.startRequests == 1 and Harness.liveTimers() == 0)
                    assert(Harness.chat[#Harness.chat].message == 'GO!')
                """)

    def test_47_cancel_announcement_uses_same_instance_raid_or_party_channel(self):
        for group, channel in [('solo', None), ('instance', 'INSTANCE_CHAT'), ('raid', 'RAID'), ('party', 'PARTY')]:
            with self.subTest(group=group):
                self.scenario(f"""
                    Harness.click('EllesmerePullButton')
                    Harness.click('EllesmerePullButton', false, 'RightButton')
                    Harness.advance(10)
                    {"assert(#Harness.chat == 0)" if channel is None else f"assert(#Harness.chat == 3 and Harness.chat[3].message == 'Pull cancelado!'); for _, m in ipairs(Harness.chat) do assert(m.channel == '{channel}') end"}
                    assert(#Harness.localChat == 0 and #Harness.countdowns == 2 and Harness.countdowns[2] == 0)
                """, f"Harness.group = '{group}'; Harness.open(); Harness.slot()")

    def test_48_cancel_invalidates_callbacks_before_official_api_even_if_rejected(self):
        for result in ('true', 'false', 'nil', "'error'"):
            with self.subTest(result=result):
                self.scenario(f"""
                    EllesmereUIDB.autoStartKeystone = true
                    Harness.click('EllesmerePullButton'); Harness.advance(1)
                    local oldTicker = Harness.timers[#Harness.timers]
                    local before = #Harness.chat
                    Harness.autoAckCountdown = false -- no cancellation event can clean up for us
                    Harness.countdownReturn = {result}; Harness.countdownError = Harness.countdownReturn == 'error'
                    Harness.onCountdown = function(seconds)
                        assert(seconds == 0 and oldTicker.canceled)
                        oldTicker.fn(oldTicker)
                        assert(#Harness.chat == before and Harness.startRequests == 0)
                    end
                    Harness.click('EllesmerePullButton', false, 'RightButton')
                    assert(Harness.liveTimers() == {0 if result in ('false', "'error'") else 1})
                    Harness.emit('START_PLAYER_COUNTDOWN', UnitGUID('player'), 5, 5)
                    Harness.advance(20)
                    assert(#Harness.countdowns == 2 and Harness.countdowns[2] == 0)
                    assert(#Harness.chat == before + 1 and Harness.chat[#Harness.chat].message == 'Pull cancelado!')
                    assert(Harness.startRequests == 0 and Harness.liveTimers() == 0)
                """)

    def test_49_waits_for_cancel_ack_before_fresh_pull_to_avoid_late_cancel_race(self):
        self.scenario("""
            EllesmereUIDB.autoStartKeystone = true
            Harness.click('EllesmerePullButton'); Harness.advance(1)
            Harness.autoAckCountdown = false
            Harness.click('EllesmerePullButton', false, 'RightButton')
            local cancelWait = Harness.timers[#Harness.timers]
            local count = #Harness.chat
            assert(Harness.liveTimers() == 1 and not cancelWait.canceled)
            assert(not Harness.button('EllesmerePullButton'):IsEnabled())
            assert(not Harness.button('EllesmereReadyButton'):IsEnabled())
            Harness.click('EllesmerePullButton', false, 'LeftButton')
            Harness.click('EllesmerePullButton', false, 'RightButton')
            Harness.click('EllesmereReadyButton')
            Harness.emit('START_PLAYER_COUNTDOWN', UnitGUID('player'), 5, 5)
            assert(#Harness.countdowns == 2 and Harness.readyRequests == 0 and #Harness.chat == count)
            Harness.emit('CANCEL_PLAYER_COUNTDOWN', UnitGUID('player'))
            assert(cancelWait.canceled and Harness.liveTimers() == 0)
            assert(Harness.button('EllesmerePullButton'):IsEnabled())
            assert(Harness.button('EllesmereReadyButton'):IsEnabled())
            Harness.click('EllesmerePullButton', false, 'RightButton')
            assert(#Harness.countdowns == 3 and Harness.countdowns[3] == 10)
            Harness.emit('START_PLAYER_COUNTDOWN', UnitGUID('player'), 10, 10)
            cancelWait.fn(cancelWait) -- queued cancellation timeout cannot reset the new pull
            Harness.advance(10)
            assert(Harness.startRequests == 1 and Harness.liveTimers() == 0)
            assert(Harness.chat[#Harness.chat].message == 'GO!')
            local canceled = 0
            for _, m in ipairs(Harness.chat) do
                if m.message == 'Pull cancelado!' then canceled = canceled + 1 end
            end
            assert(canceled == 1)
        """)

    def test_50_cancel_ack_timeout_releases_buttons_without_automatic_restart(self):
        for result in ('true', 'nil'):
            with self.subTest(result=result):
                self.scenario(f"""
                    EllesmereUIDB.autoStartKeystone = true
                    Harness.click('EllesmerePullButton')
                    Harness.autoAckCountdown = false; Harness.countdownReturn = {result}
                    Harness.click('EllesmerePullButton')
                    local count = #Harness.chat
                    Harness.advance(2.99)
                    assert(not Harness.button('EllesmerePullButton'):IsEnabled())
                    assert(not Harness.button('EllesmereReadyButton'):IsEnabled())
                    Harness.advance(0.02)
                    assert(Harness.button('EllesmerePullButton'):IsEnabled())
                    assert(Harness.button('EllesmereReadyButton'):IsEnabled())
                    Harness.advance(20)
                    assert(#Harness.chat == count and #Harness.countdowns == 2)
                    assert(Harness.startRequests == 0 and Harness.liveTimers() == 0)
                    Harness.autoAckCountdown = true; Harness.countdownReturn = true
                    Harness.click('EllesmerePullButton'); Harness.advance(5)
                    assert(#Harness.countdowns == 3 and Harness.countdowns[3] == 5 and Harness.startRequests == 1)
                """)

    def test_51_default_off_has_only_original_auto_insert_frames_events_and_hooks(self):
        setup = """
            Harness.open(); Harness.slot(); Harness.emit('GROUP_ROSTER_UPDATE')
            Harness.emit('START_PLAYER_COUNTDOWN', UnitGUID('player'), 5, 5)
            Harness.emit('CANCEL_PLAYER_COUNTDOWN', UnitGUID('player'))
            EllesmereUI.RefreshAllAddons(); Harness.advance(20)
        """
        snapshot = """function()
            local events, scripts, hooks = 0, 0, 0
            for _, frame in ipairs(Harness.frames) do
                for _ in pairs(frame.events) do events = events + 1 end
                for _ in pairs(frame.scripts) do scripts = scripts + 1 end
                for _, list in pairs(frame.hooks) do hooks = hooks + #list end
            end
            return Harness.frameCreates, Harness.methodHooks, events, scripts,
                hooks, Harness.slotRequests, Harness.pickups, Harness.liveTimers()
        end"""
        for master in ('nil', 'false'):
            with self.subTest(master=master):
                before = f'EllesmereUIDB.mythicKeystoneControls = {master}'
                baseline = self.lua(setup, before, source=AUTO_INSERT_BLOCK)
                enabled_block = self.lua(setup, before)
                self.assertEqual(baseline.eval(snapshot)(), enabled_block.eval(snapshot)())
                enabled_block.execute("""
                    assert(Harness.button('READY') == nil and Harness.button('PULL') == nil)
                    assert(Harness.readyRequests == 0 and #Harness.countdowns == 0 and Harness.startRequests == 0)
                    assert(#Harness.chat == 0 and #Harness.localChat == 0)
                    assert(ChallengesKeystoneFrame.EllesmereReadyButton == nil and ChallengesKeystoneFrame.EllesmerePullButton == nil)
                """)

    def test_52_enabling_master_creates_and_shows_controls_for_current_frame(self):
        self.scenario("""
            assert(Harness.button('READY') == nil and Harness.button('PULL') == nil)
            EllesmereUIDB.mythicKeystoneControls = true
            EllesmereUI._applyKeystoneStart()
            assert(Harness.button('READY'):IsShown() and Harness.button('PULL'):IsShown())
            assert(Harness.button('READY'):IsEnabled() and Harness.button('PULL'):IsEnabled())
            assert(Harness.readyRequests == 0 and #Harness.countdowns == 0)
            Harness.click('EllesmerePullButton'); Harness.advance(5)
            assert(#Harness.countdowns == 1 and Harness.countdowns[1] == 5)
            assert(Harness.chat[#Harness.chat].message == 'GO!')
        """, before_load="EllesmereUIDB.mythicKeystoneControls = nil")

    def test_53_child_settings_cannot_activate_disabled_master(self):
        self.scenario("""
            EllesmereUI._applyKeystoneStart()
            Harness.emit('CHALLENGE_MODE_KEYSTONE_SLOTTED')
            Harness.ackReady(); Harness.allReady(); Harness.advance(40)
            assert(Harness.button('READY') == nil and Harness.button('PULL') == nil)
            assert(Harness.readyRequests == 0 and #Harness.countdowns == 0 and Harness.startRequests == 0)
            assert(Harness.liveTimers() == 0 and #Harness.chat == 0 and #Harness.localChat == 0)
        """, before_load="""
            EllesmereUIDB.mythicKeystoneControls = false
            EllesmereUIDB.autoKeystoneReadyCheck = true
            EllesmereUIDB.autoStartKeystone = true
        """)

    def test_54_disabling_cancels_work_unregisters_controller_and_guards_old_hooks(self):
        actions = {
            'ready': 'Harness.ready()',
            'pending_pull': "Harness.autoAckCountdown = false; Harness.click('EllesmerePullButton')",
            'active_pull': "Harness.click('EllesmerePullButton'); Harness.advance(1)",
            'pending_cancel': "Harness.click('EllesmerePullButton'); Harness.autoAckCountdown = false; Harness.click('EllesmerePullButton')",
        }
        for phase, action in actions.items():
            with self.subTest(phase=phase):
                self.scenario(f"""
                    EllesmereUIDB.autoStartKeystone = true
                    {action}
                    local controller
                    for _, frame in ipairs(Harness.frames) do
                        if frame.events.CHALLENGE_MODE_KEYSTONE_SLOTTED then controller = frame end
                    end
                    assert(controller)
                    local oldTimers = {{}}
                    for _, timer in ipairs(Harness.timers) do
                        if not timer.canceled then oldTimers[#oldTimers + 1] = timer end
                    end
                    EllesmereUIDB.mythicKeystoneControls = false
                    EllesmereUI._applyKeystoneStart()
                    assert(next(controller.events) == nil and Harness.liveTimers() == 0)
                    assert(not Harness.button('READY'):IsShown() and not Harness.button('PULL'):IsShown())
                    local chat, countdowns, ready = #Harness.chat, #Harness.countdowns, Harness.readyRequests
                    for _, timer in ipairs(oldTimers) do assert(timer.canceled); timer.fn(timer) end
                    Harness.click('EllesmereReadyButton', true)
                    Harness.click('EllesmerePullButton', true)
                    Harness.allReady(); Harness.emit('START_PLAYER_COUNTDOWN', UnitGUID('player'), 5, 5)
                    Harness.emit('CANCEL_PLAYER_COUNTDOWN', UnitGUID('player'))
                    Harness.slotted = nil
                    local inserts = Harness.slotRequests
                    ChallengesKeystoneFrame:Hide(); ChallengesKeystoneFrame:Show()
                    Harness.emit('CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN')
                    assert(Harness.slotRequests > inserts) -- the original Auto Insert remains active
                    ChallengesKeystoneFrame:Reset()
                    EllesmereUI.RefreshAllAddons(); EllesmereUI.SwitchProfile(); EllesmereUI.ApplyProfileData()
                    Harness.advance(40)
                    assert(next(controller.events) == nil and Harness.liveTimers() == 0)
                    assert(not Harness.button('READY'):IsShown() and not Harness.button('PULL'):IsShown())
                    assert(#Harness.chat == chat and #Harness.countdowns == countdowns and Harness.readyRequests == ready)
                    assert(Harness.startRequests == 0 and #Harness.localChat == 0)
                """)

    def test_55_repeated_enable_disable_reuses_controls_and_hooks(self):
        self.scenario("""
            local frame = ChallengesKeystoneFrame
            local ready, pull = Harness.button('READY'), Harness.button('PULL')
            local frames, methods = Harness.frameCreates, Harness.methodHooks
            local showHooks, hideHooks = #frame.hooks.OnShow, #frame.hooks.OnHide
            for i = 1, 20 do
                EllesmereUIDB.mythicKeystoneControls = false; EllesmereUI._applyKeystoneStart()
                assert(not ready:IsShown() and not pull:IsShown())
                EllesmereUIDB.mythicKeystoneControls = true; EllesmereUI._applyKeystoneStart()
                assert(ready:IsShown() and pull:IsShown())
            end
            assert(Harness.button('READY') == ready and Harness.button('PULL') == pull)
            assert(Harness.frameCreates == frames and Harness.methodHooks == methods)
            assert(#frame.hooks.OnShow == showHooks and #frame.hooks.OnHide == hideHooks)
            assert(frame.EllesmereReadyButton == nil and frame.EllesmerePullButton == nil)
            Harness.click('EllesmerePullButton'); Harness.advance(5)
            assert(#Harness.countdowns == 1 and Harness.chat[#Harness.chat].message == 'GO!')
        """)


if __name__ == '__main__':
    unittest.main(verbosity=2)
