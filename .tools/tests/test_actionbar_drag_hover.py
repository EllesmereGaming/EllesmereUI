"""Check Masque pickup preserves interaction opacity (requires lupa)."""
from pathlib import Path
import unittest

from lupa import lua51

ROOT = Path(__file__).resolve().parents[2]


class MasqueDragHighlightTests(unittest.TestCase):
    def setUp(self):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            ns = {}
            function EFD(btn) return btn.fd end
            function NewTexture()
                local t = { alpha = 1, shown = true }
                function t:SetAlpha(value) self.alpha = value end
                function t:SetBlendMode() end
                function t:Show() self.shown = true end
                function t:Hide() self.shown = false end
                return t
            end
            function hooksecurefunc(obj, key, callback)
                local original = obj[key]
                obj[key] = function(self, ...)
                    original(self, ...)
                    callback(self, ...)
                end
            end
            function NewButton()
                local b = { fd = {}, scripts = {}, HighlightTexture = NewTexture(),
                    PushedTexture = NewTexture() }
                function b:CreateTexture(_, layer)
                    local t = NewTexture()
                    t.layer = layer
                    return t
                end
                function b:HookScript(event, callback)
                    local handlers = self.scripts[event] or {}
                    self.scripts[event] = handlers
                    handlers[#handlers + 1] = callback
                end
                function b:Fire(event)
                    for _, callback in ipairs(self.scripts[event] or {}) do callback(self) end
                end
                return b
            end
            btn = NewButton()
        ''')
        text = (ROOT / 'EllesmereUIActionBars/EUI_ActionBars_Pushed.lua').read_text()
        start = text.index('local function ClearDrag')
        end = text.index('function ns.AnchorMasqueInteraction', start)
        self.lua.execute(text[start:end])
        self.lua.execute('''
            highlight = ns.MasqueInteractionTexture(btn, "HighlightTexture")
            pushed = ns.MasqueInteractionTexture(btn, "PushedTexture")
        ''')
        self.g = self.lua.globals()

    def test_pickup_does_not_make_source_highlight_transparent(self):
        self.lua.execute('btn:Fire("OnDragStart")')
        self.assertEqual(self.g.highlight.alpha, 1)
        self.assertEqual(self.g.highlight.layer, 'HIGHLIGHT')
        self.assertTrue(self.g.highlight.shown)

    def test_repeated_pickups_preserve_configured_opacity(self):
        self.lua.execute('highlight:SetAlpha(0.4); btn:Fire("OnDragStart"); btn:Fire("OnDragStart")')
        self.assertEqual(self.g.highlight.alpha, 0.4)

    def test_disabled_highlight_stays_disabled(self):
        self.lua.execute('highlight:SetAlpha(0); btn:Fire("OnDragStart")')
        self.assertEqual(self.g.highlight.alpha, 0)

    def test_pickup_hides_press_without_breaking_next_press(self):
        self.lua.execute('btn:Fire("OnMouseDown"); btn:Fire("OnDragStart")')
        self.assertFalse(self.g.pushed.shown)
        self.assertEqual(self.g.pushed.alpha, 1)
        self.lua.execute('btn:Fire("OnMouseDown")')
        self.assertTrue(self.g.pushed.shown)
        self.assertEqual(self.g.pushed.alpha, 1)
        self.lua.execute('btn:Fire("OnMouseUp")')
        self.assertFalse(self.g.pushed.shown)

    def test_native_masque_texture_stays_suppressed(self):
        self.lua.execute('btn.HighlightTexture:SetAlpha(1); btn:Fire("OnDragStart")')
        self.assertEqual(self.g.btn.HighlightTexture.alpha, 0)
        self.assertEqual(self.g.highlight.alpha, 1)

    def test_reskin_does_not_duplicate_pickup_hook(self):
        self.lua.execute('ns.MasqueInteractionTexture(btn, "HighlightTexture"); ns.MasqueInteractionTexture(btn, "PushedTexture")')
        self.assertEqual(len(self.g.btn.scripts.OnDragStart), 1)


if __name__ == '__main__':
    unittest.main()
