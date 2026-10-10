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
            function UnitExists() return true end
            created, draws, pointWrites = 0, 0, 0
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
            function methods:SetPoint(...) assert(not self.secure); pointWrites = pointWrites + 1; self.points[#self.points + 1] = {...} end
            function methods:SetHeight(v) self.height = v end
            function methods:SetWidth(v) self.width = v end
            function methods:SetAllPoints(parent) self.points = {{'ALL', parent}} end
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
            function E.ApplyBorderStyle(host) draws = draws + 1; host:Show() end
            function E.HideBorderStyle() end
            function E.RegisterPxReapply(host, fn) host.reapply = fn end
            function E.PP.GetBorders(host) return host.strips end
            function E.PP.CreateBorder(host, r, g, b, a, size)
                host.strips = CreateFrame(nil, nil, host)
                host.strips:SetFrameLevel(host:GetFrameLevel() + 1)
                host.strips.color, host.strips.size = {r,g,b,a}, size
            end
            function E.PP.UpdateBorder(host, rsize, r, g, b, a)
                if not host.strips then E.PP.CreateBorder(host,r,g,b,a,rsize) end
                host.strips.color, host.strips.size = {r,g,b,a}, rsize
            end
            function E.PP.SetBorderSize(host, size) host.strips.size = size end
            function E.PP.SetBorderColor(host, ...) host.strips.color = {...} end
            function E.PP.ShowBorder(host) host.strips:Show() end
            C_Timer = {NewTimer = function(_, fn)
                timer = {fn = fn, Cancel = function(self) self.cancelled = true end}
                return timer
            end}
            ns = {_internals = {dbSetters = {}, containerFrameSetters = {}, framesVisibleSetters = {}, allButtons = {}}}
            function ns._internals.GetFFD(frame) return frame.data end
            ns.GetFFD = ns._internals.GetFFD
            ns.LVL_RAISE = 10
            function ns.RF_VisibleHighlight(s, r, g, b) return r,g,b end
            function ns.RF_CustomBorderOn(s) return s.borderTexture == 'pixels' end
            function ns.RF_Stock() return stock end
            function ns.RF_PartyKit() return false end
            function ns._IsPartySectionCustom() return customParty end
            ns._PARTY_KEY_SECTION = {borderTexture = 'border'}
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
                        f.unit, f.data, f.secure = 'raid' .. (#frames + 1), {_isRaid = true, _raidGroup = x + 1}, true
                        f._raidGroup = x + 1
                        frames[#frames + 1] = f
                    end
                end
                return frames
            end
            s = {raidCompactEnabled = true, raidCompactJoinGroups = true, borderTexture = 'pixels', borderSize = 2, cellSpacing = 1, groupSpacing = 1}
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
        targets = (ROOT / "EllesmereUIRaidFrames/EUI_RaidFrames_PartyTargets.lua").read_text()
        target_helpers = targets[targets.index("local function PT_Side("):targets.index("-- The reach of target frames")]
        target_pitch = targets[targets.index("function ns.PT_AlongStack("):targets.index("-- One target frame on its side")]
        self.lua.execute("local _, ns = ...; local PixelSnap = function(v) return v end; " + target_helpers + target_pitch,
                         "test", self.lua.globals().ns)
        stock = (ROOT / "EllesmereUIRaidFrames/EUI_RaidFrames_Stock.lua").read_text()
        dims = stock[stock.index("function ns.RF_PartyDims("):stock.index("-- Friendly Boss", stock.index("function ns.RF_PartyDims("))]
        self.lua.execute("local _, ns = ...; " + dims, "test", self.lua.globals().ns)
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
                            expected_y = 1
                            if vertical:
                                rect = point[2].rect
                                top = (rect[2] + rect[4]) * scale / perfect
                                expected_y = 1 if point[1] == "TOPLEFT" and top < host._raidT - 0.25 else 0
                            self.assertAlmostEqual(point[5] * scale / perfect, expected_y)
                    self.lua.execute("""
                        s.partyCompactEnabled = true
                        s.unitGrowth = 'RIGHT'
                        party = ns.RF_ApplyPartyBorder(nil, parent, grid(5, 1, 1, 1), s)
                    """)
                    for point in self.lua.globals().party._partySeps[1].points.values():
                        self.assertAlmostEqual(point[4] * scale / perfect, -1)
                        self.assertAlmostEqual(point[5], 0)

    def test_grid_junctions_cover_gap_once_and_handle_partial_groups(self):
        def vertical_intervals():
            host = self.lua.globals().pool.hosts[1]
            factor = self.lua.eval("UIParent.scale / EllesmereUI.PP.perfect")
            intervals = []
            for index in range(1, host._partyCount):
                if host._partyOrder[index + 1].growth != "RIGHT":
                    continue
                points = host._partySeps[index].points
                rect = points[1][2].rect
                intervals.append((round((rect[2] + points[2][5]) * factor, 6),
                                  round((rect[2] + rect[4] + points[1][5]) * factor, 6)))
            return sorted(intervals)

        for scale in (0.64, 1, 1.25):
            for perfect in (1, 768 / 1440):
                for flip_x in (False, True):
                    for flip_y in (False, True):
                        with self.subTest(scale=scale, perfect=perfect, flip_x=flip_x, flip_y=flip_y):
                            self.lua.globals().UIParent.scale = scale
                            self.lua.globals().EllesmereUI.PP.perfect = perfect
                            self.lua.globals().frames = self.lua.globals().grid(2, 3, 1, 1, flip_x, flip_y)
                            self.lua.execute("render(frames)")
                            intervals = vertical_intervals()
                            host = self.lua.globals().pool.hosts[1]
                            self.assertAlmostEqual(intervals[0][0], host._raidB)
                            self.assertAlmostEqual(intervals[-1][1], host._raidT)
                            for previous, current in zip(intervals, intervals[1:]):
                                self.assertEqual(previous[1], current[0])

                self.lua.execute("frames = grid(2,3,1,1); frames[4].shown = false; render(frames)")
                self.assertEqual(vertical_intervals(), [(-94, -47), (-47, 0)])
                self.lua.execute("frames[4].shown = true; frames[6].shown = false; render(frames)")
                self.assertEqual(vertical_intervals(), [(-48, 0), (0, 46)])
                self.lua.execute("frames[4].shown = false; render(frames)")
                self.assertEqual(vertical_intervals(), [(-48, 0)])
                self.lua.execute("""
                    for _, f in ipairs(frames) do f.shown = true; f.data._raidGroup = 1 end
                    s.raidCompactJoinGroups = false; render(frames)
                """)
                self.assertEqual(vertical_intervals(), [(-94, -48), (-47, -1), (0, 46)])
                self.lua.execute("s.raidCompactJoinGroups = true; render(frames)")
                self.assertEqual(vertical_intervals(), [(-94, -47), (-47, 0), (0, 46)])

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
        for assignment in ("s.raidCompactEnabled = false", "s.borderTexture = 'solid'", "stock = true", "s.borderSize = 0"):
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
        self.lua.execute("s.partyCompactEnabled = true; frames = grid(1, 5, 1, 1)")
        self.lua.execute("party = ns.RF_ApplyPartyBorder(nil, parent, frames, s)")
        self.assertEqual(self.lua.eval("party._partyCount"), 5)
        self.lua.execute("ns.RF_HidePartyBorder(party); party = ns.RF_ApplyPartyBorder(party, parent, frames, s)")
        self.assertTrue(self.lua.eval("party:IsShown() and party._partySeps[4]:IsShown()"))

    def test_disable_clears_art_and_pixel_callbacks(self):
        self.lua.execute("frames = grid(4, 5, 1, 1); render(frames); s.raidCompactEnabled = false")
        self.assertEqual(self.lua.execute("return render(frames)"), (0, 0))
        self.assertTrue(self.lua.eval("pool.hosts[1].reapply == nil"))
        self.lua.execute("s.raidCompactEnabled = true; before = created")
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
        self.lua.execute("s.raidCompactEnabled = false; ns.RF_RefreshRaidBorders()")
        self.assertTrue(self.lua.eval("firstTimer.cancelled and ns._raidBorderTimer == nil and not ns._raidCompactEnabledOn"))
        self.assertFalse(self.lua.eval("ns._raidBorders.hosts[1]:IsShown()"))

    def test_opt_in_preserves_spacing_and_survives_scale_changes(self):
        self.lua.execute("""
            s.partySharedBorder, s.raidSharedBorder = true, true
            s.partyCompactEnabled, s.raidCompactEnabled = false, false
            s.partyCellSpacing, s.cellSpacing, s.groupSpacing = -1, -1, 8
        """)
        self.assertFalse(self.lua.eval("ns.RF_PartySharedBorderOn(s)"))
        self.assertFalse(self.lua.eval("ns.RF_RaidSharedBorderOn(s)"))
        for scale in (0.64, 1, 1.75):
            self.lua.globals().UIParent.scale = scale
            self.lua.execute("s.partyCompactEnabled, s.raidCompactEnabled = true, true")
            self.assertAlmostEqual(self.lua.eval("ns.RF_PartySpacing(s) * UIParent.scale"), 1)
            self.assertAlmostEqual(self.lua.eval("ns.RF_RaidSpacing(s) * UIParent.scale"), 1)
            self.assertAlmostEqual(self.lua.eval("ns.RF_RaidSpacing(s, true) * UIParent.scale"), 1)
            self.lua.execute("s.partyCompactEnabled, s.raidCompactEnabled = false, false")
            self.assertEqual(self.lua.eval("ns.RF_PartySpacing(s)"), -1)
            self.assertEqual(self.lua.eval("ns.RF_RaidSpacing(s)"), -1)
            self.assertEqual(self.lua.eval("ns.RF_RaidSpacing(s, true)"), 8)

    def test_join_groups_requires_its_own_opt_in(self):
        self.lua.execute("s.groupSpacing = 1; s.raidCompactJoinGroups = false; frames = grid(4,5,1,1)")
        self.assertEqual(self.lua.execute("return render(frames)"), (4, 16))
        self.assertEqual(self.lua.execute("s.raidCompactJoinGroups = true; return render(frames)"), (1, 31))

    def test_options_style_and_spacing_never_opt_in(self):
        pages = (ROOT / "EllesmereUIOptions/RaidFrames_Options/FramesPages_Options.lua").read_text()
        self.lua.execute("""
            s = {borderTexture='solid',cellSpacing=-1,groupSpacing=-1}
            db = {profile=s}; y = 0; W = {}; rows = {}; cogs = {}
            function W:DualRow(parent,y,left,right)
                rows[#rows+1]={left,right}
                return {_leftRegion={},_rightRegion={}},1
            end
            function EllesmereUI.BuildInlineCog(region,cfg) cogs[#cogs+1]=cfg end
            function SGet(k) return s[k] end
            function SGetPx() end
            function SVal(k,default) if s[k] ~= nil then return s[k] end; return default end
            function SWrite(k,v) s[k]=v end
            SSet, PSSet = SWrite, SWrite
            function ReloadAndUpdate() end
            function EllesmereUI:RefreshPage() end
            function EllesmereUI.GetBorderStyleSelectDefaults() return {r=0,g=0,b=0}, false end
            function EllesmereUI.GetBorderDefaultSize() return 2 end
            function EllesmereUI.BlankRowCfg() return {type='label',text=''} end
        """)
        cfgs = pages[pages.index("    local function RaidPixelsBorder("):pages.index("    -- Border Style (+ options cog)")]
        self.lua.execute("local ns = ...; " + cfgs, self.lua.globals().ns)
        style_start = pages.index('          setValue=function(v)', pages.index('    local borderStyleRow'))
        style_end = pages.index('          end }),', style_start) + len('          end')
        setter = pages[style_start:style_end].strip().removeprefix("setValue=")
        self.lua.execute("pickStyle = " + setter)
        self.lua.execute("pickStyle('pixels')")
        self.assertTrue(self.lua.eval("s.cellSpacing == -1 and s.groupSpacing == -1 and s.partyCellSpacing == nil"))
        self.assertTrue(self.lua.eval("not s.partyCompactEnabled and not s.raidCompactEnabled"))
        self.assertEqual(self.lua.eval("#rows"), 1)
        self.assertEqual(self.lua.eval("cogs[1].rows[1].label"), "Compact Mode")
        self.assertEqual(self.lua.eval("cogs[2].rows[1].label"), "Grid Mode")
        self.lua.execute("rows[1][1].setValue(1); rows[1][2].setValue(1)")
        self.assertFalse(self.lua.eval("ns.RF_RaidSharedBorderOn(s)"))
        self.assertEqual(self.lua.eval("rows[1][1].min"), -1)
        self.lua.execute("cogs[1].rows[1].set(true)")
        self.assertTrue(self.lua.eval("rows[1][1].disabled()"))
        self.assertFalse(self.lua.eval("rows[1][2].disabled()"))
        self.assertFalse(self.lua.eval("cogs[1].rows[1].disabled() or cogs[2].rows[1].disabled()"))
        self.lua.execute("cogs[2].rows[1].set(true)")
        self.assertTrue(self.lua.eval("rows[1][2].disabled()"))
        self.lua.execute("pickStyle('solid')")
        self.assertFalse(self.lua.eval("rows[1][1].disabled() or rows[1][2].disabled()"))
        self.assertTrue(self.lua.eval("s.cellSpacing == 1 and s.groupSpacing == 1 and s.partyCellSpacing == nil"))

    def test_custom_party_border_eligibility_is_independent(self):
        self.lua.execute("""
            s.partyCompactEnabled, s.raidCompactEnabled = true, false
            s.borderTexture = 'solid'; s.party_borderTexture = 'pixels'; customParty = true
        """)
        self.assertTrue(self.lua.eval("ns.RF_PartySharedBorderOn(s)"))
        self.assertFalse(self.lua.eval("ns.RF_RaidSharedBorderOn(s)"))
        self.lua.execute("s.party_borderSize = 0")
        self.assertFalse(self.lua.eval("ns.RF_PartySharedBorderOn(s)"))

    def test_targets_suspend_compact_without_recursion_or_losing_preference(self):
        self.lua.execute("s.partyCompactEnabled = true; s.partyShowTargets = true; s.partyCellSpacing = -1")
        for horizontal in (False, True):
            self.lua.globals().s.partyHorizontal = horizontal
            for side in ("top", "bottom", "left", "right"):
                self.lua.globals().s.partyTargetPosition = side
                along = (side in ("left", "right")) if horizontal else (side in ("top", "bottom"))
                with self.subTest(horizontal=horizontal, side=side):
                    self.assertEqual(self.lua.eval("ns.RF_PartySharedBorderOn(s)"), not along)
                    self.assertEqual(self.lua.execute("local _,_,gap = ns.RF_PartyDims(s); return gap"), -1 if along else 1)
                    self.assertEqual(self.lua.eval("ns.PT_AlongPitch(s, true) > 0"), along)
        self.lua.execute("s.partyShowTargets = false")
        self.assertTrue(self.lua.eval("ns.RF_PartySharedBorderOn(s) and s.partyCompactEnabled"))

    def test_target_layout_transition_restores_individual_borders(self):
        self.lua.execute("""
            function UnitExists() return true end
            paints, restyles, auraRestyles = 0, 0, 0
            function ns.RF_PaintThreat() paints = paints + 1 end
            function ns.RFC_ReloadAll() auraRestyles = auraRestyles + 1 end
            s.partyCompactEnabled = true
            ns._scaledPartyProxy = s
            ns._partyContainerFrame = parent
            ns._partyAllButtons = grid(1,5,1,1)
            for _, frame in ipairs(ns._partyAllButtons) do
                local d = frame.data
                d._compactBorderApplied = true
                function d.UpdateBorder()
                    d._compactBorderApplied = ns.RF_PartySharedBorderOn(s)
                    restyles = restyles + 1
                end
            end
            ns.RF_RefreshPartyBorder()
            s.partyShowTargets, s.partyTargetPosition = true, 'top'
            ns.RF_QueuePartyBorder()
        """)
        self.assertTrue(self.lua.eval("not ns._partyBorder:IsShown()"))
        self.assertEqual(self.lua.eval("restyles"), 5)
        self.assertEqual(self.lua.eval("paints"), 5)
        self.assertEqual(self.lua.eval("auraRestyles"), 1)
        self.lua.execute("ns.RF_QueuePartyBorder()")
        self.assertEqual(self.lua.eval("restyles"), 5)
        self.lua.execute("s.partyShowTargets = false; ns.RF_QueuePartyBorder(); timer.fn()")
        self.assertTrue(self.lua.eval("ns._partyBorder:IsShown()"))
        self.assertEqual(self.lua.eval("restyles"), 10)

    def test_target_layout_invalidates_materialized_party_settings(self):
        layout = (ROOT / "EllesmereUIRaidFrames/EUI_RaidFrames_PartyLayout.lua").read_text()
        prefix = layout[layout.index("ns._LayoutPartyFrames = function()"):layout.index("    local pw, ph, pcs = ns.RF_PartyDims(s)")]
        self.lua.execute("""
            db = {profile=s}; s.partyCompactEnabled = true
            s.partyShowTargets, s.partyTargetPosition = true, 'top'
            ns._partyHeader = {}
            ns._scaledPartyProxy = {partyShowTargets=false,partyTargetPosition='right'}
            invalidations = 0
            function ns._RefreshProxyModes()
                invalidations = invalidations + 1
                ns._scaledPartyProxy.partyShowTargets = s.partyShowTargets
                ns._scaledPartyProxy.partyTargetPosition = s.partyTargetPosition
            end
        """)
        self.lua.execute("local ns,db = ns,db; local InCombatLockdown = function() return false end; " + prefix + " end")
        self.lua.execute("ns._LayoutPartyFrames(); ns._LayoutPartyFrames()")
        self.assertEqual(self.lua.eval("invalidations"), 1)

    def test_actual_divider_art_placement_mirrors_at_all_sizes(self):
        pixel = (ROOT / "EllesmereUI_PixelPerfect.lua").read_text()
        divider = pixel[pixel.index("    function EllesmereUI.PlaceBorderDividerV("):pixel.index("    -- The Pixels styles:")]
        self.lua.execute(divider)
        self.lua.execute("""
            function EllesmereUI.GetBorderCompanion(key,role)
                return role == 'sepSize' and 16 or key .. role
            end
            function EllesmereUI.BorderCompanionThickness() return edge / UIParent.scale end
            function EllesmereUI.PP.SnapForES(v,es) return math.floor(v*es+0.5)/es end
            s.partyCompactEnabled = true
            function seamOffset(direction)
                s.unitGrowth = direction
                local horizontal = direction == 'RIGHT' or direction == 'LEFT'
                local frames = grid(horizontal and 5 or 1,horizontal and 1 or 5,1,1,direction=='LEFT',direction=='UP')
                local h = ns.RF_ApplyPartyBorder(nil,parent,frames,s)
                local seam = h._partySeps[1]
                local t = seam._tex
                local sign = (direction=='RIGHT' or direction=='UP') and 1 or -1
                local size = horizontal and t.width or t.height
                local axis = horizontal and 4 or 5
                return (seam.points[1][axis] + t.points[1][axis] + sign*size*5/32) * UIParent.scale
            end
        """)
        for scale in (0.64, 1, 1.5):
            for edge in (4, 8, 11, 16, 24, 32):
                for texture in ("pixels", "pixels-textured"):
                    with self.subTest(scale=scale, edge=edge, texture=texture):
                        self.lua.globals().UIParent.scale = scale
                        self.lua.globals().edge = edge
                        self.lua.globals().s.borderTexture = texture
                        self.assertAlmostEqual(self.lua.eval("seamOffset('DOWN')"), -self.lua.eval("seamOffset('UP')"))
                        self.assertAlmostEqual(self.lua.eval("seamOffset('RIGHT')"), -self.lua.eval("seamOffset('LEFT')"))

    def test_unchanged_passes_do_not_reanchor_or_redraw(self):
        self.lua.execute("""
            frames = grid(4,5,1,1)
            render(frames)
            oldDraws, oldPoints = draws, pointWrites
            for i = 1, 12 do render(frames) end
        """)
        self.assertTrue(self.lua.eval("draws == oldDraws and pointWrites == oldPoints"))
        self.lua.execute("s.borderColor = {r=1,g=0,b=0}; render(frames); oldDraws = draws; s.borderColor.r = 0.5; render(frames)")
        self.assertEqual(self.lua.eval("draws - oldDraws"), 1)
        self.lua.execute("s.partyCompactEnabled = true; partyFrames = grid(1,5,1,1); party = ns.RF_ApplyPartyBorder(nil,parent,partyFrames,s)")
        self.lua.execute("oldDraws, oldPoints = draws, pointWrites; for i=1,12 do ns.RF_ApplyPartyBorder(party,parent,partyFrames,s) end")
        self.assertTrue(self.lua.eval("draws == oldDraws and pointWrites == oldPoints"))
        self.lua.execute("partyFrames[1].rect[3] = 90; ns.RF_ApplyPartyBorder(party,parent,partyFrames,s)")
        self.assertEqual(self.lua.eval("draws - oldDraws"), 1)

    def test_party_seams_mirror_toward_previous_frame(self):
        for direction, x, y in (("DOWN", 0, 1), ("UP", 0, -1), ("RIGHT", -1, 0), ("LEFT", 1, 0)):
            with self.subTest(direction=direction):
                self.lua.globals().s.unitGrowth = direction
                self.lua.execute("s.partyCompactEnabled = true; UIParent.scale = 0.64")
                horizontal = direction in ("LEFT", "RIGHT")
                frames = self.lua.globals().grid(5 if horizontal else 1, 1 if horizontal else 5, 1, 1, direction == "LEFT", direction == "UP")
                host = self.lua.globals().ns.RF_ApplyPartyBorder(None, self.lua.globals().parent, frames, self.lua.globals().s)
                for point in host._partySeps[1].points.values():
                    self.assertAlmostEqual(point[4] * 0.64, x)
                    self.assertAlmostEqual(point[5] * 0.64, y)

    def test_compact_dispel_border_uses_normal_size_and_ignores_custom_art(self):
        aura = (ROOT / "EllesmereUIRaidFrames/EUI_RaidFrames_AuraContainers.lua").read_text()
        dispel = aura[aura.index("    -- Type-colored border around the health bar."):aura.index("    -- Dispel type icon.")]
        self.lua.execute("local ns=ns; local PP=EllesmereUI.PP; function paintDispel(button,dd,style) local health,def=dd.rfHealth,dd.rfSlotDef; local r,g,b,typeA=0.2,0.6,1,0.5; " + dispel + " end")
        self.lua.execute("""
            function EllesmereUI.ApplySecretSafeBorderStyle(host,state,size,r,g,b,a,tex)
                host.customSize,host.customTex = size,tex
            end
        """)
        for party in (False, True):
            with self.subTest(party=party):
                self.lua.globals().party = party
                self.lua.execute("""
                    owner = grid(1,1,1,1)[1]
                    owner.data._isParty, owner.data._isRaid = party,not party
                    health = CreateFrame(nil,nil,owner); health:SetFrameLevel(owner:GetFrameLevel()+2)
                    border = CreateFrame(nil,nil,owner)
                    slot = CreateFrame(nil,nil,owner)
                    dd = {rfHealth=health,rfSlotDef={level=5},rfUnitBtn=owner,rfBorder=border}
                    ds = {borderSize=0,compactRaid=not party,compactParty=party,
                        customBorder={size=8,tex='pixels-textured',offX=3,offY=4,shX=5,shY=6}}
                    paintDispel(slot,dd,ds)
                """)
                self.assertTrue(self.lua.eval("dd.borderHost == nil and dd.cbHost == nil"))
                self.lua.execute("ds.compactRaid,ds.compactParty=false,false; paintDispel(slot,dd,ds)")
                self.assertTrue(self.lua.eval("dd.borderHost == nil and dd.cbHost:IsShown()"))
                self.assertEqual(self.lua.eval("dd.cbHost.customTex"), "pixels-textured")
                self.assertEqual(self.lua.eval("dd.cbHost.customSize"), 8)
                self.lua.execute("ds.compactRaid,ds.compactParty=not party,party; paintDispel(slot,dd,ds)")
                self.assertTrue(self.lua.eval("dd.borderHost == nil and not dd.cbHost:IsShown() and not dd.cbOn"))
                self.lua.execute("ds.borderSize=4; paintDispel(slot,dd,ds)")
                self.assertEqual(self.lua.eval("dd.borderHost.strips.size"), 4)
                self.assertEqual(self.lua.eval("dd.borderHost.strips.color[4]"), 0.5)
                self.assertTrue(self.lua.eval("dd.borderHost.points[1][2] == health"))
                self.lua.execute("ds.compactRaid,ds.compactParty=false,false; paintDispel(slot,dd,ds)")
                self.assertEqual(self.lua.eval("dd.borderHost.strips.size"), 4)
                self.assertTrue(self.lua.eval("dd.borderHost.points[1][2] == health"))
                self.lua.execute("ds.borderSize=0; ds.compactRaid,ds.compactParty=not party,party; paintDispel(slot,dd,ds)")
                self.assertFalse(self.lua.eval("dd.borderHost:IsShown()"))

    def test_compact_dispel_preview_uses_normal_size_and_ignores_custom_border_option(self):
        preview = (ROOT / "EllesmereUIRaidFrames/EUI_RaidFrames_Preview.lua").read_text()
        start = preview.index("    -- Color Custom Borders: the border takes")
        block = preview[start:preview.index("        -- Dispel overlay", start)]
        self.lua.execute("local ns=ns; local PP=EllesmereUI.PP; function paintPreview(f,s) local dispVis=true; local dispelDC={r=0.2,g=0.6,b=1}; " + block + " end end")
        self.lua.execute("""
            f = grid(1,1,1,1)[1]; f._raidFrame = true
            f._health=CreateFrame(nil,nil,f); f._border=CreateFrame(nil,nil,f)
            f._dispelBdrFrame=CreateFrame(nil,nil,f)
            s.dispelBorderSize=0; s.dispelCustomBorder=true
            paintPreview(f,s)
        """)
        self.assertTrue(self.lua.eval("not f._dispelBdrFrame:IsShown() and f._pvDispelBdrC == nil"))
        self.lua.execute("s.dispelBorderSize=3; paintPreview(f,s)")
        self.assertEqual(self.lua.eval("f._dispelBdrFrame.strips.size"), 3)
        self.assertTrue(self.lua.eval("f._dispelBdrFrame.points[1][2] == f._health"))
        self.lua.execute("s.dispelBorderSize=0")
        self.lua.execute("s.raidCompactEnabled=false; paintPreview(f,s)")
        self.assertTrue(self.lua.eval("not f._dispelBdrFrame:IsShown() and f._pvDispelBdrC ~= nil"))
        self.lua.execute("s.dispelBorderSize=6; paintPreview(f,s)")
        self.assertEqual(self.lua.eval("f._dispelBdrFrame.strips.size"), 6)
        self.assertTrue(self.lua.eval("f._dispelBdrFrame.points[1][2] == f._health"))

    def test_dispel_custom_border_option_is_disabled_only_for_active_compact_context(self):
        options = (ROOT / "EllesmereUIOptions/RaidFrames_Options/VisualIndicators_Options.lua").read_text()
        block = options[options.index("    -- Cog on the Dispel Border slider:"):options.index("    -- Dispel Colors:")]
        self.lua.execute("""
            row={_leftRegion={}}; optState={}; db={profile=s}
            ns._scaledPartyProxy=s
            function EllesmereUI.BuildInlineCog(region,cfg) dispelCog=cfg end
            function CustomBorderOff() return customOff end
            function CustomBorderOffTip() return 'Requires a custom border.' end
            function SVal(k,default) if s[k] ~= nil then return s[k] end; return default end
            function SSet(k,v) s[k]=v end
            s.dispelCustomBorder=true
        """)
        self.lua.execute("local ns=ns; " + block)
        self.assertTrue(self.lua.eval("dispelCog.rows[2].disabled()"))
        self.assertIn("Compact Mode", self.lua.eval("dispelCog.rows[2].disabledTooltip()"))
        self.lua.execute("optState._partyCtx=true")
        self.assertFalse(self.lua.eval("dispelCog.rows[2].disabled()"))
        self.lua.execute("s.partyCompactEnabled=true")
        self.assertTrue(self.lua.eval("dispelCog.rows[2].disabled()"))
        self.lua.execute("s.partyShowTargets=true; s.partyTargetPosition='top'")
        self.assertFalse(self.lua.eval("dispelCog.rows[2].disabled()"))
        self.lua.execute("customOff=true")
        self.assertTrue(self.lua.eval("dispelCog.rows[2].disabled()"))
        self.assertTrue(self.lua.eval("s.dispelCustomBorder"))

    def test_threat_levels_restore_when_leaving_compact_mode(self):
        style = (ROOT / "EllesmereUIRaidFrames/EUI_RaidFrames_Style.lua").read_text()
        helpers = style[style.index("function ns.RF_LayoutCompactThreat("):style.index("function ns.RF_ColorPowerDivider(")]
        self.lua.execute("local ns=ns; local PP=EllesmereUI.PP; " + helpers)
        for preview in (False, True):
            for lose_aggro_first in (False, True):
                with self.subTest(preview=preview, lose_aggro_first=lose_aggro_first):
                    self.lua.globals().preview = preview
                    self.lua.execute("""
                        owner = CreateFrame(nil,nil,parent); owner:SetFrameLevel(40)
                        threat = CreateFrame(nil,nil,owner)
                        threat:SetAllPoints(owner); threat:SetFrameLevel(50)
                        EllesmereUI.PP.CreateBorder(threat,1,0,0,1,2)
                        ns.RF_ApplyThreatBorder(threat,s,true,true,preview)
                    """)
                    self.assertEqual(self.lua.execute("return threat:GetFrameLevel(), threat.strips:GetFrameLevel()"), (48, 49))
                    if lose_aggro_first:
                        self.lua.execute("ns.RF_ApplyThreatBorder(threat,s,false,true,preview)")
                    self.lua.execute("ns.RF_ApplyThreatBorder(threat,s,false,false,preview)")
                    self.assertEqual(self.lua.execute("return threat:GetFrameLevel(), threat.strips:GetFrameLevel()"), (50, 51))
                    self.assertTrue(self.lua.eval("threat._threatInset == nil and threat.reapply == nil and not threat:IsShown()"))
                    self.assertTrue(self.lua.eval("#threat.points == 1 and threat.points[1][1] == 'ALL' and threat.points[1][2] == owner"))
                    self.lua.execute("ns.RF_ApplyThreatBorder(threat,s,true,false,preview)")
                    self.assertEqual(self.lua.execute("return threat:GetFrameLevel(), threat.strips:GetFrameLevel()"), (50, 51))
                    self.lua.execute("ns.RF_ApplyThreatBorder(threat,s,true,true,preview)")
                    self.assertEqual(self.lua.execute("return threat:GetFrameLevel(), threat.strips:GetFrameLevel()"), (48, 49))
                    self.lua.execute("ns.RF_ApplyThreatBorder(threat,s,true,false,preview)")
                    self.assertEqual(self.lua.execute("return threat:GetFrameLevel(), threat.strips:GetFrameLevel()"), (50, 51))
                    self.assertTrue(self.lua.eval("threat:IsShown() and threat._threatInset == nil and threat.reapply == nil"))

    def test_threat_and_selection_are_independent_above_dispels(self):
        style = (ROOT / "EllesmereUIRaidFrames/EUI_RaidFrames_Style.lua").read_text()
        helpers = style[style.index("function ns.RF_LayoutPartyInsetHighlight("):style.index("function ns.RF_ColorPowerDivider(")]
        self.lua.execute("local _,ns = ...; local PP = EllesmereUI.PP; " + helpers, "test", self.lua.globals().ns)
        main = (ROOT / "EllesmereUIRaidFrames/EllesmereUIRaidFrames.lua").read_text()
        threat = main[main.index("function ns.RF_PaintThreat("):main.index("-- Vertical health fill:")]
        self.lua.execute("local _,ns = ...; local PP = EllesmereUI.PP; local THREAT_ACTIVE = {[2]=true,[3]=true}; " + threat, "test", self.lua.globals().ns)
        self.lua.execute("""
            function UnitThreatSituation() return threatStatus end
            owner = grid(1,1,1,1)[1]
            border = CreateFrame(nil,nil,owner)
            threatFrame = CreateFrame(nil,nil,owner)
            d = owner.data; d.threatFrame = threatFrame
            s.targetBorderColor = {r=0,g=1,b=0}; s.threatBorderSize = 2
            ns.ApplyPartyInsetHighlight(border,s,false,true)
            threatStatus = 3; ns.RF_PaintThreat(d,s,'raid1')
        """)
        self.assertTrue(self.lua.eval("border._partyInsetHighlight:IsShown() and threatFrame:IsShown()"))
        self.assertTrue(self.lua.eval("border._partyInsetHighlight.strips.color[2] == 1 and threatFrame.strips.color[1] == 1"))
        self.assertEqual(self.lua.eval("threatFrame._threatInset"), 2)
        self.assertEqual(self.lua.eval("border._partyInsetHighlight:GetFrameLevel()"), 9)
        self.lua.execute("threatStatus = nil; ns.RF_PaintThreat(d,s,'raid1')")
        self.assertTrue(self.lua.eval("not threatFrame:IsShown() and border._partyInsetHighlight:IsShown()"))
        aura = (ROOT / "EllesmereUIRaidFrames/EUI_RaidFrames_AuraContainers.lua").read_text()
        dispel = aura[aura.index("    -- Type-colored border around the health bar."):aura.index("    -- Color Custom Borders:")]
        self.lua.execute("local _,ns = ...; local PP=EllesmereUI.PP; function paintDispel(button,dd,style) local health,def=dd.rfHealth,dd.rfSlotDef; local r,g,b,typeA=1,0,0,1; " + dispel + " end", "test", self.lua.globals().ns)
        self.lua.execute("""
            health = CreateFrame(nil,nil,owner); health:SetFrameLevel(owner:GetFrameLevel()+2)
            dd = {rfHealth=health,rfSlotDef={level=5},rfUnitBtn=owner}
            paintDispel(CreateFrame(),dd,{borderSize=2,compactRaid=true})
        """)
        self.assertTrue(self.lua.eval("dd.borderHost.strips:GetFrameLevel() < border._partyInsetHighlight.strips:GetFrameLevel()"))
        self.lua.execute("render(grid(2,2,1,1))")
        self.assertTrue(self.lua.eval("""
            border._partyInsetHighlight.strips:GetFrameLevel() < pool.hosts[1]:GetFrameLevel()
            and threatFrame.strips:GetFrameLevel() < pool.hosts[1]:GetFrameLevel()
            and pool.hosts[1]._partySeps[1]:GetFrameLevel() < owner:GetFrameLevel() + 12
        """))
        self.lua.execute("ns.ApplyPartyInsetHighlight(border,s,true,false)")
        self.assertTrue(self.lua.eval("dd.borderHost.strips:GetFrameLevel() < border._partyInsetHighlight.strips:GetFrameLevel()"))
        self.assertTrue(self.lua.eval("border._partyInsetHighlight.strips:GetFrameLevel() < pool.hosts[1]:GetFrameLevel()"))


if __name__ == "__main__":
    unittest.main()
