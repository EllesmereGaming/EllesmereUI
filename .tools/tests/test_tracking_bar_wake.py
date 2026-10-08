"""Run the Tracking Bars wake hooks with Lua 5.1 (requires lupa).

Run: python .tools/tests/test_tracking_bar_wake.py
"""
from pathlib import Path
import unittest

from lupa import lua51


ROOT = Path(__file__).resolve().parents[2] / "EllesmereUICooldownManager"


class TrackingBarWakeTests(unittest.TestCase):
    def setUp(self):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            ns = { bars = { { enabled = true, spellID = 12345 } } }
            ECME = { db = {} }
            EllesmereUI = {}
            C_UnitAuras = { GetPlayerAuraBySpellID = function() return nil end }
            C_Spell = { GetSpellName = function() return "Tracked Buff" end }
            function UnitExists() return false end
            function issecretvalue() return false end

            local methods = {}
            function methods:Hide() self.shown = false end
            function methods:Show()
                self.shown = true
                self.shows = self.shows + 1
            end
            function methods:IsShown() return self.shown end
            function methods:SetScript(event, callback) self.scripts[event] = callback end
            function methods:RegisterEvent(event) self.events[event] = true end
            function methods:RegisterUnitEvent(event) self:RegisterEvent(event) end
            function methods:UnregisterAllEvents()
                self.events = {}
                self.unregistrations = self.unregistrations + 1
            end
            function methods:IsActive() return self.active end
            function methods:OnActiveStateChanged() end
            function CreateFrame()
                return setmetatable({ shown = false, active = false, shows = 0,
                    unregistrations = 0, scripts = {}, events = {} }, { __index = methods })
            end
            function hooksecurefunc(object, method, callback)
                local original = object[method]
                object[method] = function(self)
                    local result = original(self)
                    callback(self)
                    return result
                end
            end
            function NewViewer()
                local frame = CreateFrame()
                local pool = { frames = { frame } }
                function pool:EnumerateActive()
                    local index = 0
                    return function()
                        index = index + 1
                        return self.frames[index]
                    end
                end
                function pool:Acquire()
                    local item = CreateFrame()
                    self.frames[#self.frames + 1] = item
                    return item
                end
                return { itemFramePool = pool }, frame
            end
            BuffBarCooldownViewer, ns.barItem = NewViewer()
            BuffIconCooldownViewer, ns.iconItem = NewViewer()
            ns.tick = CreateFrame()
            function ns.GetTrackedBuffBars() return { bars = ns.bars } end
        """)

        source = (ROOT / "EllesmereUICdmBuffBars.lua").read_text()
        start = source.index("local tbbFrames  = {}")
        end = source.index("function ns.GetTBBFrame", start)
        self.lua.execute(source[start:end] + """
            tbbTickFrame = ns.tick
            _tbbWake._enabled = true
            ns.sleeper = _tbbWake
            _tbbWake.Sleep()
        """)

        source = (ROOT / "EUI_CDM_HookViewers.lua").read_text()
        start = source.index('    local _activeStateHooked = setmetatable(')
        end = source.index('            -- Intercept newly acquired frames', start)
        self.lua.execute("""
            local function ReapplyPositions() end
            local function QueueReanchor() end
            local VIEWER_NAMES = { "MissingEssential", "MissingUtility",
                "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
        """ + source[start:end] + """
                end
            end
        """)
        self.ns = self.lua.globals().ns

    def activate_bar(self):
        self.lua.execute("ns.barItem.active = true; ns.barItem:OnActiveStateChanged()")

    def test_aura_event_before_viewer_activation_wakes_tick(self):
        self.lua.execute('ns.sleeper.scripts.OnEvent(ns.sleeper, "UNIT_AURA", "player")')
        self.assertFalse(self.ns.tick.shown, "the inactive viewer should miss the aura probe")
        self.activate_bar()
        self.assertTrue(self.ns.tick.shown, "a late viewer activation must wake Tracking Bars")
        self.assertTrue(self.ns.sleeper.events.UNIT_AURA)
        self.assertIsNone(self.ns.sleeper.events.UNIT_SPELLCAST_SUCCEEDED)

    def test_reused_viewer_item_wakes_tick_without_another_aura_event(self):
        self.activate_bar()
        self.assertTrue(self.ns.tick.shown)
        self.lua.execute("ns.barItem.active = false; ns.sleeper.Sleep()")
        self.activate_bar()
        self.assertTrue(self.ns.tick.shown)

    def test_newly_acquired_viewer_item_wakes_tick(self):
        self.lua.execute("ns.newItem = BuffBarCooldownViewer.itemFramePool:Acquire()")
        self.assertFalse(self.ns.tick.shown)
        self.lua.execute("ns.newItem.active = true; ns.newItem:OnActiveStateChanged()")
        self.assertTrue(self.ns.tick.shown)

    def test_pending_icon_reanchor_does_not_suppress_bar_wake(self):
        self.lua.execute("ns.iconItem.active = true; ns.iconItem:OnActiveStateChanged()")
        self.assertFalse(self.ns.tick.shown)
        self.activate_bar()
        self.assertTrue(self.ns.tick.shown)

    def test_icon_viewer_does_not_wake_tracking_bars(self):
        self.lua.execute("ns.iconItem.active = true; ns.iconItem:OnActiveStateChanged()")
        self.assertFalse(self.ns.tick.shown)
        self.assertEqual(self.ns.tick.shows, 0)

    def test_disabled_tracking_bars_do_not_wake(self):
        self.lua.execute("ns.sleeper._enabled = false; ns.sleeper:UnregisterAllEvents()")
        before = self.ns.sleeper.unregistrations
        self.activate_bar()
        self.assertFalse(self.ns.tick.shown)
        self.assertEqual(self.ns.sleeper.unregistrations, before)
        self.assertIsNone(self.ns.sleeper.events.UNIT_AURA)

    def test_awake_tick_is_not_reset_by_viewer_changes(self):
        self.lua.execute("ns.sleeper.Wake(); ns.sleeper._idleTicks = 17")
        before = self.ns.sleeper.unregistrations
        self.activate_bar()
        self.assertEqual(self.ns.sleeper.unregistrations, before)
        self.assertEqual(self.ns.sleeper._idleTicks, 17)
        self.assertEqual(self.ns.tick.shows, 1)

    def test_activation_burst_wakes_once(self):
        self.activate_bar()
        self.lua.execute("ns.barItem:OnActiveStateChanged(); ns.barItem:OnActiveStateChanged()")
        self.assertTrue(self.ns.tick.shown)
        self.assertEqual(self.ns.tick.shows, 1)
        self.assertEqual(self.ns.sleeper.unregistrations, 1)


if __name__ == "__main__":
    unittest.main()
