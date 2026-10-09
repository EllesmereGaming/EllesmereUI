"""Exercise the shared raid/party border renderer with Lua 5.1 (requires lupa)."""
from pathlib import Path
import unittest

from lupa import lua51


ROOT = Path(__file__).resolve().parents[2]


class SharedBorderTests(unittest.TestCase):
    def setUp(self):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            function wipe(t) for k in pairs(t) do t[k] = nil end end
            secret = setmetatable({}, {
                __lt = function() error('secret comparison') end,
                __le = function() error('secret comparison') end,
                __mul = function() error('secret arithmetic') end,
                __add = function() error('secret arithmetic') end,
            })
            function issecretvalue(v) return rawequal(v, secret) end
            created = 0
            local methods = {}
            function methods:GetParent() return self.parent end
            function methods:SetParent(p) self.parent = p end
            function methods:GetEffectiveScale() return self.scale or (self.parent and self.parent:GetEffectiveScale()) or 1 end
            function methods:GetFrameLevel() return self.level or 1 end
            function methods:GetFrameStrata() return self.strata or 'MEDIUM' end
            function methods:SetFrameLevel(v) assert(not self.secure); self.level = v end
            function methods:SetFrameStrata(v) assert(not self.secure); self.strata = v end
            function methods:IsShown() return self.shown end
            function methods:IsVisible()
                if not self.shown then return false end
                return not self.parent or self.parent:IsVisible()
            end
            function methods:Show() assert(not self.secure); self.shown = true end
            function methods:Hide() assert(not self.secure); self.shown = false end
            function methods:GetAttribute() return self.unit end
            function methods:GetRect() return unpack(self.rect) end
            function methods:ClearAllPoints() assert(not self.secure); self.points = {} end
            function methods:SetPoint(...) assert(not self.secure); self.points[#self.points + 1] = {...} end
            function methods:SetHeight(v) self.height = v end
            function methods:SetTexture(v) self.texture = v end
            function methods:SetTexCoord(...) self.coords = {...} end
            function methods:SetVertexColor(...) self.color = {...} end
            function methods:HookScript(event, fn) self.hooks[event] = fn end
            function CreateFrame(_, _, parent)
                created = created + 1
                return setmetatable({parent = parent, shown = true, points = {}, hooks = {}}, {__index = methods})
            end
            function methods:CreateTexture() return CreateFrame(nil, nil, self) end
            UIParent = CreateFrame()
            parent = CreateFrame(nil, nil, UIParent)
            EllesmereUI = {PP = {perfect = 1}}
            local E = EllesmereUI
            function E.PP.ToPixels(v) return math.floor(v * UIParent:GetEffectiveScale() / E.PP.perfect + 0.5) end
            function E.PP.DisablePixelSnap() end
            function E.PP.SnapForES(v, es) return v end
            function E.BorderCompanionThickness() return 8 end
            function E.BorderPx(px, size) return px or size end
            function E.GetBorderCompanion(key, part) return key .. part end
            function E.PlaceBorderDividerV(tex) tex.vertical = true end
            function E.ApplyBorderStyle(host) host:Show() end
            function E.HideBorderStyle() end
            function E.RegisterPxReapply(host, fn) host.reapply = fn end
            C_Timer = {NewTimer = function(_, fn)
                timer = {fn = fn, Cancel = function(self) self.cancelled = true end}
                return timer
            end}
            ns = {_internals = {dbSetters = {}, containerFrameSetters = {}, framesVisibleSetters = {}, allButtons = {}}}
            function ns._internals.GetFFD(frame) return frame.data end
            function ns.RF_Stock() return stock end
            function ns._PartyGrowth(s) return s.unitGrowth or 'DOWN' end
            function grid(cols, rows, xgap, ygap, flipX, flipY)
                local frames = {}
                local scale = parent:GetEffectiveScale()
                local px = E.PP.perfect / scale
                for x = 0, cols - 1 do
                    for y = 0, rows - 1 do
                        local f = CreateFrame(nil, nil, parent)
                        f.rect = {(flipX and -x or x) * (72 + xgap) * px,
                            (flipY and y or -y) * (46 + ygap) * px, 72 * px, 46 * px}
                        f.unit, f.data, f.secure = 'raid' .. (#frames + 1), {_isRaid = true}, true
                        frames[#frames + 1] = f
                    end
                end
                return frames
            end
            s = {raidSharedBorder = true, borderTexture = 'pixels', borderSize = 2, cellSpacing = 1, groupSpacing = 1}
            function render(frames, preview)
                pool = ns.RF_ApplyRaidBorders(pool, parent, frames, s, preview)
                local hosts, seams = 0, 0
                for _, host in ipairs(pool.hosts) do
                    if host:IsShown() then
                        hosts, seams = hosts + 1, seams + host._partyCount - 1
                    end
                end
                return hosts, seams
            end
        """)
        source = (ROOT / "EllesmereUIRaidFrames/EUI_RaidFrames_PartyLayout.lua").read_text()
        source = source.split("-- Layout party frames: apply unitGrowth direction")[0]
        self.lua.execute(source, "EllesmereUIRaidFrames", self.lua.globals().ns)

    def test_grid_in_all_directions_and_pixel_scales(self):
        for scale in (0.64, 1, 1.25):
            for flip_x in (False, True):
                for flip_y in (False, True):
                    with self.subTest(scale=scale, flip_x=flip_x, flip_y=flip_y):
                        self.lua.globals().UIParent.scale = scale
                        self.lua.execute("s.cellSpacing = 1 / UIParent.scale; s.groupSpacing = s.cellSpacing")
                        frames = self.lua.globals().grid(4, 5, 1, 1, flip_x, flip_y)
                        self.assertEqual(self.lua.globals().render(frames), (1, 31))
                        host = self.lua.globals().pool.hosts[1]
                        self.assertAlmostEqual(host._raidR - host._raidL, 291)
                        self.assertAlmostEqual(host._raidT - host._raidB, 234)

    def test_independent_axes_and_wrapped_groups(self):
        self.assertEqual(self.lua.execute("s.groupSpacing = 8; return render(grid(4, 5, 8, 1))"), (4, 16))
        self.assertEqual(self.lua.execute("s.groupSpacing = 1; s.cellSpacing = 4; return render(grid(4, 5, 1, 4))"), (5, 15))
        self.assertEqual(self.lua.execute("s.cellSpacing = 1; return render(grid(2, 10, 1, 1))"), (1, 28))
        self.assertEqual(self.lua.execute("return render(grid(5, 4, 1, 1))"), (1, 31))

    def test_separator_alignment_uses_physical_pixels(self):
        for scale in (0.64, 1, 1.25):
            for perfect in (1, 768 / 1440):
                with self.subTest(scale=scale, perfect=perfect):
                    self.lua.globals().UIParent.scale = scale
                    self.lua.globals().EllesmereUI.PP.perfect = perfect
                    self.lua.execute("""
                        s.cellSpacing = EllesmereUI.PP.perfect / UIParent.scale
                        s.groupSpacing = s.cellSpacing
                        render(grid(4, 5, 1, 1))
                    """)
                    host = self.lua.globals().pool.hosts[1]
                    for index in range(1, host._partyCount):
                        vertical = host._partyOrder[index + 1].growth == "RIGHT"
                        for point in host._partySeps[index].points.values():
                            self.assertAlmostEqual(point[4] * scale / perfect, -1 if vertical else 0)
                            self.assertAlmostEqual(point[5] * scale / perfect, 0 if vertical else 1)
                    self.lua.execute("""
                        s.partySharedBorder = true
                        s.unitGrowth = 'RIGHT'
                        party = ns.RF_ApplyPartyBorder(nil, parent, grid(5, 1, 1, 1), s)
                    """)
                    for point in self.lua.globals().party._partySeps[1].points.values():
                        self.assertAlmostEqual(point[4], 0)
                        self.assertAlmostEqual(point[5] * scale / perfect, 1)

    def test_partial_roster_shrink_and_restore_reuses_hosts(self):
        self.lua.execute("frames = grid(4, 5, 1, 1)")
        self.assertEqual(self.lua.execute("return render(frames)"), (1, 31))
        self.assertEqual(self.lua.execute("for i = 6, 20 do frames[i].shown = false end; return render(frames)"), (1, 4))
        self.assertEqual(self.lua.execute("frames[5].shown = false; return render(frames)"), (1, 3))
        self.assertEqual(self.lua.execute("for i = 1, 20 do frames[i].shown = false end; return render(frames)"), (0, 0))
        self.lua.execute("before = created; for i = 1, 20 do frames[i].shown = true end")
        self.assertEqual(self.lua.execute("return render(frames)"), (1, 31))
        self.assertTrue(self.lua.eval("created == before"))

    def test_hidden_headers_extras_and_preview(self):
        self.lua.execute("frames = grid(4, 5, 1, 1); frames[20].data._isRaid = nil")
        self.assertEqual(self.lua.execute("return render(frames)"), (1, 29))
        self.assertEqual(self.lua.execute("frames[20].unit = nil; return render(frames, true)"), (1, 31))
        self.assertEqual(self.lua.execute("parent:Hide(); return render(frames)"), (0, 0))

    def test_opt_in_and_invalid_data(self):
        for assignment in ("s.raidSharedBorder = false", "s.borderTexture = 'solid'", "stock = true", "s.borderSize = 0"):
            with self.subTest(assignment=assignment):
                self.setUp()
                self.lua.execute(assignment)
                self.assertTrue(self.lua.execute("local before = created; local p = ns.RF_ApplyRaidBorders(nil, parent, {}, s); return p == nil and created == before"))
        self.setUp()
        self.lua.execute("frames = grid(4, 5, 1, 1); render(frames); frames[1].rect[1] = secret")
        self.assertEqual(self.lua.execute("return render(frames)"), (0, 0))
        self.lua.execute("frames[1].rect[1] = 0; frames[1].unit = secret")
        self.assertEqual(self.lua.execute("return render(frames)"), (0, 0))

    def test_party_renderer_still_reopens_after_disable(self):
        self.lua.execute("s.partySharedBorder = true; frames = grid(1, 5, 1, 1)")
        self.lua.execute("party = ns.RF_ApplyPartyBorder(nil, parent, frames, s)")
        self.assertEqual(self.lua.eval("party._partyCount"), 5)
        self.lua.execute("ns.RF_HidePartyBorder(party); party = ns.RF_ApplyPartyBorder(party, parent, frames, s)")
        self.assertTrue(self.lua.eval("party:IsShown() and party._partySeps[4]:IsShown()"))

    def test_disable_clears_art_and_pixel_callbacks(self):
        self.lua.execute("frames = grid(4, 5, 1, 1); render(frames); s.cellSpacing = 4; s.groupSpacing = 8")
        self.assertEqual(self.lua.execute("return render(frames)"), (0, 0))
        self.assertTrue(self.lua.eval("pool.hosts[1].reapply == nil"))
        self.lua.execute("s.cellSpacing = 1; s.groupSpacing = 1; before = created")
        self.assertEqual(self.lua.execute("return render(frames)"), (1, 31))
        self.assertTrue(self.lua.eval("created == before"))

    def test_roster_refresh_coalesces_and_cancels_on_disable(self):
        self.lua.execute("""
            ns._scaledProfile = s
            for _, setter in ipairs(ns._internals.containerFrameSetters) do setter(parent) end
            for _, frame in ipairs(grid(4, 5, 1, 1)) do
                table.insert(ns._internals.allButtons, frame)
            end
            ns.RF_RefreshRaidBorders()
            ns.RF_QueueRaidBorders()
            firstTimer = timer
            ns.RF_QueueRaidBorders()
        """)
        self.assertTrue(self.lua.eval("timer == firstTimer"))
        self.lua.execute("s.raidSharedBorder = false; ns.RF_RefreshRaidBorders()")
        self.assertTrue(self.lua.eval("firstTimer.cancelled and ns._raidBorderTimer == nil and not ns._raidSharedBorderOn"))
        self.assertFalse(self.lua.eval("ns._raidBorders.hosts[1]:IsShown()"))


if __name__ == "__main__":
    unittest.main()
