-- Does the release snippet choose the same entry the palette draws as selected?
--
-- Loads the REAL module against a stub client, then sweeps cursor positions
-- comparing PaletteView:HitTest (radians, math.atan2) with the extracted
-- SNIPPET_PRE (degrees, WoW's global atan2) fed from the very attributes
-- PushPalette writes. Those two have disagreed before over exactly this kind of
-- thing, and the symptom in game is "it fired the entry next to the one I aimed
-- at" -- easy to miss and hard to attribute.

local ADDON = arg[1] or "."
local unpackedAtan = math.atan
math.atan2 = math.atan2 or function(y, x) return unpackedAtan(y, x) end

----------------------------------------------------------------------------
--  Stub client
----------------------------------------------------------------------------
local CURSOR = { x = 0, y = 0 }
local byName = {}

local function NewFrame(kind, name)
    local f = { _kind = kind, _name = name, _w = 0, _h = 0, _shown = true,
                _attr = {}, _refs = {}, _cx = 0, _cy = 0 }

    function f:SetSize(w, h) self._w, self._h = w, h end
    function f:GetSize() return self._w, self._h end
    function f:GetWidth() return self._w end
    function f:GetHeight() return self._h end
    function f:GetCenter() return self._cx, self._cy end
    function f:SetCenter(x, y) self._cx, self._cy = x, y end
    function f:GetEffectiveScale() return 1 end
    function f:SetShown(v) self._shown = v and true or false end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:IsShown() return self._shown end
    function f:IsVisible() return self._shown end
    function f:SetAttribute(k, v) self._attr[k] = v end
    function f:GetAttribute(k) return self._attr[k] end
    function f:GetName() return self._name end
    function f:SetFrameRef(k, v) self._refs[k] = v end
    function f:GetFrameRef(k) return self._refs[k] end
    function f:CreateTexture() return NewFrame("texture") end
    function f:CreateFontString() return NewFrame("fontstring") end

    -- Real geometry and z-order, for the focus simulator below -- everything
    -- else in this file works from view.claims directly and never asked a
    -- frame handle where it actually sits, but the arming gates only exist as
    -- real anchored, leveled frames, and topmost-wins focus needs both.
    f._level = 0
    function f:SetFrameLevel(n) self._level = n end
    function f:GetFrameLevel() return self._level end
    function f:SetFrameStrata(s) self._strata = s end
    function f:GetFrameStrata() return self._strata end
    f._motion = false
    function f:SetMouseMotionEnabled(v) self._motion = v and true or false end
    function f:IsMouseMotionEnabled() return self._motion end
    function f:SetMouseClickEnabled(v) self._click = v and true or false end
    function f:SetWidth(w) self._w = w end
    function f:SetHeight(h) self._h = h end
    -- Only the one anchor shape the module itself ever uses on a gate:
    -- SetPoint("BOTTOMLEFT", rel, "BOTTOMLEFT", x, y). rel's own bottom-left
    -- is read off its centre when it has one (UIParent does), or off its own
    -- tracked position otherwise -- gates never anchor to one another, so one
    -- level of indirection is all this needs.
    function f:SetPoint(point, rel, relPoint, x, y)
        local blx, bly = 0, 0
        if rel then
            if rel._cx then
                blx, bly = rel._cx - rel._w * 0.5, rel._cy - rel._h * 0.5
            else
                blx, bly = rel._px or 0, rel._py or 0
            end
        end
        self._px, self._py = blx + (x or 0), bly + (y or 0)
        self._positioned = true
    end
    -- A frame with its points cleared and never re-anchored has no rect a
    -- real cursor could ever be inside -- exactly the state a stale gate
    -- ought to be in, and exactly what the hygiene fix restores it to.
    function f:ClearAllPoints() self._positioned = false end
    -- Normalised position within this frame, nil outside it -- the contract
    -- RestrictedFrames.lua:307 gives the sandbox.
    function f:GetMousePosition()
        local w, h = self._w, self._h
        local x = (CURSOR.x - (self._cx - w * 0.5)) / w
        local y = (CURSOR.y - (self._cy - h * 0.5)) / h
        if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
        return x, y
    end

    -- Anything else: a no-op METHOD only. Unknown lowercase keys stay nil, so a
    -- field the module expects to have set (widget.baseSize, widget.icon) is not
    -- silently answered with a function that then fails as a number.
    setmetatable(f, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return function() end end
        return nil
    end })

    if name then byName[name] = f end
    return f
end

_G.CreateFrame = function(kind, name) return NewFrame(kind, name) end
_G.UIParent = NewFrame("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
UIParent:SetCenter(960, 540)

_G.GetCursorPosition = function() return CURSOR.x, CURSOR.y end
_G.GetCursorInfo    = function() return nil end
_G.ClearCursor      = function() end
_G.GetBindingKey    = function() return nil end
_G.InCombatLockdown = function() return false end
_G.GetTime          = function() return 0 end
_G.CooldownFrame_Set = function() end

-- The sandbox's atan2 is WoW's GLOBAL one: degrees, same argument order as
-- math.atan2 (Compat.lua:25). Getting this wrong here would hide the very bug
-- the harness exists to catch, so it is spelled out rather than borrowed.
-- Defined up here, ahead of the module load, because SecureHandlerWrapScript
-- below needs it too: EnsureGates calls it for real, during the module's own
-- OnEnable, so the gate snippets have to be compilable from the moment the
-- module starts running rather than only once the click snippet is later
-- extracted by hand.
local sandbox = {
    tonumber = tonumber,
    floor = math.floor,
    abs = math.abs,
    atan2 = function(x, y) return math.deg(math.atan2(x, y)) end,
}

-- REAL SecureHandlerWrapScript, not an emulation of what it is supposed to
-- do: this is the gap the rest of this file's own StepArmed function leaves
-- open, and the one place a difference between "the file's comments describe
-- this" and "the file's code does this" can hide from every sweep below.
-- Mirrors SecureHandlers.lua's own Wrapped_OnEnter/Wrapped_OnLeave precisely,
-- "_wrapentered" included: that flag is raised only from INSIDE a wrapped
-- OnEnter, so a frame whose OnEnter was never wrapped can never satisfy
-- Wrapped_OnLeave's own guard, and its OnLeave preBody silently never runs at
-- all, however many times the frame's OnLeave itself fires. Getting this
-- wrong here -- treating "OnLeave was wrapped" as "the leave body runs" --
-- would hide exactly the bug this harness extension exists to catch.
local WRAP_SIG = {
    OnClick = { pre = "self,button,down", post = "self,message,button,down" },
    OnEnter = { pre = "self", post = "self,message" },
    OnLeave = { pre = "self", post = "self,message" },
}
local function CompileWrap(script, body)
    if body == nil then return nil end
    local sig = WRAP_SIG[script] or { pre = "self" }
    return assert(load("local " .. sig.pre .. " = ...\n" .. body, script, "t", sandbox))
end
-- Validates preBody/postBody exactly as SecureHandlers.lua's own
-- SecureHandlerWrapScript does (preBody a string always, postBody a string
-- OR nil, nothing else) and error()s the same way it does when they are
-- not -- deliberately NOT tolerant of a stray extra value here. One real
-- caller (EnsureGates, wrapping a claim's region gate's OnLeave) builds its
-- preBody with a chained ":gsub" and no parentheses around the return, so
-- gsub's OWN second return value -- a substitution count -- rides along as
-- an unintended fifth argument to THIS call, landing in postBody as a
-- number. Silently tolerating that (treating a non-string postBody as "no
-- postBody") would have hidden the very crash this bug causes in the real
-- game: every real call shaped like that one throws "Invalid post-handler
-- body" and aborts, right there, whatever EnsureGates was in the middle of
-- building.
_G.SecureHandlerWrapScript = function(frame, script, header, pre, post)
    if type(pre) ~= "string" then error("Invalid pre-handler body") end
    if post ~= nil and type(post) ~= "string" then error("Invalid post-handler body") end
    frame._wrap = frame._wrap or {}
    frame._wrap[script] = { pre = CompileWrap(script, pre), post = CompileWrap(script, post) }
end
-- self == frame that fired OnEnter/OnLeave; motion is always true here -- the
-- harness only ever drives this off a genuine cursor move (see MoveCursor).
local function FireOnEnter(frame, motion)
    local w = frame._wrap and frame._wrap.OnEnter
    if not w then return end
    if motion then
        frame._wrapentered = true
        if w.pre then w.pre(frame) end
    end
end
local function FireOnLeave(frame, motion)
    local w = frame._wrap and frame._wrap.OnLeave
    if not w then return end
    if motion and frame._wrapentered then
        frame._wrapentered = nil
        if w.pre then w.pre(frame) end
    end
end
_G.SecureHandlerSetFrameRef = function(f, k, v) f:SetFrameRef(k, v) end
_G.SetOverrideBindingClick = function() end
_G.ClearOverrideBindings   = function() end
_G.RAID_CLASS_COLORS = {}
_G.UnitClass  = function() return "Mage", "MAGE" end
_G.GetMacroInfo = function() return nil end
_G.C_Spell = { GetSpellInfo = function(id)
                   return { name = "Spell" .. tostring(id), iconID = 1 } end,
               GetSpellCooldownDuration = function() return nil end }
_G.C_Item = { GetItemInfoInstant = function() return nil end,
              GetItemInfo = function() return nil end,
              GetItemCooldown = function() return 0, 0, 0 end }
_G.C_ToyBox      = { GetToyInfo = function() return nil end }
_G.C_MountJournal = { GetMountInfoByID = function() return nil end }
_G.C_PetJournal  = { GetPetInfoByPetID = function() return nil end }
_G.SlashCmdList  = {}

local addonObj
local function DeepCopy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = (type(v) == "table") and DeepCopy(v) or v
    end
    return out
end

_G.EllesmereUI = {
    Lite = {
        NewAddon = function()
            addonObj = { RegisterEvent = function() end }
            return addonObj
        end,
        NewDB = function(_, defaults) return { profile = DeepCopy(defaults.profile) } end,
    },
    Print = function() end,
    MEDIA_PATH = "",
}

----------------------------------------------------------------------------
--  Load and start the module
----------------------------------------------------------------------------
local ns = {}
assert(loadfile(ADDON .. "/EllesmereUIActionPalette.lua"))("EUIActionPalette", ns)
addonObj:OnInitialize()
addonObj:OnEnable()   -- builds the live view PushPalette measures against

local p = ns.Profile()
p.layout     = "ARC"
p.centerMode = "SCREEN"     -- fixed centre: the snippet and the view agree on it
p.posX, p.posY, p.scale = 0, 0, 1
p.showNeedle = false

----------------------------------------------------------------------------
--  The snippet, compiled against its REAL signature
----------------------------------------------------------------------------
local src = io.open(ADDON .. "/EllesmereUIActionPalette.lua"):read("a")
local body = src:match("local SNIPPET_PRE = %[==%[(.-)%]==%]")
assert(body, "SNIPPET_PRE not found")
-- The real file bakes REGION_MAX into the loop bound in the press branch's
-- gate-placement loop by plain substitution rather than string.format (the
-- body is full of the modulo operator, which format chokes on) -- done here
-- too, so the extracted copy actually compiles.
body = body:gsub("__REGION_MAX__", tostring(ns.REGION_MAX))
-- The arm-effects fragment the real file interpolates into SNIPPET_PRE's press
-- branch (and into both gate snippets, which EnsureGates builds for real during
-- the module load above, so those already carry it). Extracted and substituted
-- the same way and in the same order, because the press-time geometric pre-arm
-- lives entirely inside it: an extracted copy without it would compile, run,
-- and quietly never arm anything at a press.
local armFragment = src:match("local ARM_CLAIM = %[==%[(.-)%]==%]")
assert(armFragment, "ARM_CLAIM not found")
armFragment = armFragment:gsub("__REGION_MAX__", tostring(ns.REGION_MAX))
body = body:gsub("__ARM_CLAIM__", function() return armFragment end)

-- sandbox is the one defined above, ahead of the module load -- reused here
-- rather than rebuilt, so the click snippet and the gate snippets can never
-- silently drift onto two different atan2 implementations.
local snippet = assert(load("local self, button, down = ...\n" .. body,
                            "SNIPPET_PRE", "t", sandbox))

----------------------------------------------------------------------------
--  Gate emulation
--
--  A geometric stand-in for the parent and region gate frames every claim
--  gets: StepArmed answers what eapArmed becomes after ONE more sample of
--  the cursor, given what it was before. This stub client cannot fire a real
--  OnEnter/OnLeave at all, so the rule the file's own EnsureGates/
--  EnterSnippet/LeaveSnippet comments describe is worked out here instead:
--
--    Exclusive arming.  While a claim is armed, every OTHER claim's parent
--    gate is hidden (see EnterSnippet), so it cannot steal focus just
--    because the cursor also happens to sit over it. The armed claim's own
--    TRUE region is therefore tested FIRST, and only once the cursor has
--    genuinely left it -- and the other parent gates are shown again -- do
--    the other parent boxes get a look at all. One StepArmed call is one
--    real cursor motion, so a call whose destination is simultaneously
--    outside the old claim's region and inside a new claim's parent box is
--    exactly what a single mouse-move landing there would do in game: it
--    disarms and re-arms in the same step, which is what LeaveSnippet's own
--    geometric re-arm makes true of the real thing as well. What this does
--    NOT model is the press-time pre-arm -- it has no press in it at all --
--    so the real-gate section at the bottom of this file is what holds that
--    path to account.
--
--    Geometric union, not "did I leave the rect".  A claim's true ground is
--    ClaimContains below: the parent box, plus either the polar wedge (ARC)
--    or the union of c.regions (every other layout) -- see CorridorBox and
--    CellChildGeom/ChildGeom in the file itself for what builds those.
----------------------------------------------------------------------------
local function InBox(b, dx, dy)
    return b ~= nil and math.abs(dx - b.x) <= b.hw and math.abs(dy - b.y) <= b.hh
end

-- The release branch's own ANGULAR test, worked in radians here since this
-- is plain Lua rather than the sandboxed snippet -- c.rows/c.band are
-- already in radians (ChildGeom builds them that way; PushPalette converts
-- to degrees only when writing the eapCR* attributes the real snippet reads).
local function InWedge(c, dx, dy)
    if InBox(c.parentBox, dx, dy) then return true end
    if not c.band then return false end
    local dist = (dx * dx + dy * dy) ^ 0.5
    if dist < c.band then return false end
    for _, row in ipairs(c.rows) do
        if dist >= row.lo and (not row.hi or dist < row.hi) then
            local theta = math.atan2(dx, dy)
            local startAngle = row.start - row.step * 0.5
            local crel = (theta - startAngle) % (2 * math.pi)
            return crel < row.n * row.step
        end
    end
    return false
end

local function ClaimContains(view, c, dx, dy)
    if view:LayoutMode() == "ARC" then return InWedge(c, dx, dy) end
    for _, r in ipairs(c.regions or {}) do
        if InBox(r, dx, dy) then return true end
    end
    return false
end

local function StepArmed(view, armed, dx, dy)
    local claims = view.claims
    if armed and claims and claims[armed]
       and ClaimContains(view, claims[armed], dx, dy) then
        return armed
    end
    for k = 1, (claims and #claims or 0) do
        if InBox(claims[k].parentBox, dx, dy) then return k end
    end
    return nil
end

-- What eapArmed is after a cursor that starts nowhere near any claim, passes
-- through claim k's own parent entry, and travels on to (dx, dy) -- the
-- shortest path that actually exercises the pass-through rule. Answers k only
-- if (dx, dy) is still somewhere in k's own region once it gets there;
-- answers whatever OTHER claim's parent box (dx, dy) itself lands on instead,
-- topmost-wins, same as a real cursor walking there would.
local function ArmedViaParent(view, k, dx, dy)
    local c = view.claims and view.claims[k]
    if not c or not c.parentBox then return nil end
    local armed = StepArmed(view, nil, 1e6, 1e6)
    armed = StepArmed(view, armed, c.parentBox.x, c.parentBox.y)
    return StepArmed(view, armed, dx, dy)
end

----------------------------------------------------------------------------
--  Sweep one configuration
----------------------------------------------------------------------------
local function Sweep(label, setup, step)
    setup()
    ns.Refresh()

    local btn = byName["EUIActionPaletteButton1"]
    assert(btn, "no secure button")
    btn:SetFrameRef("ui", UIParent)

    -- A view of our own, laid out from the same profile: the live one is a file
    -- local. Same class, same data, so its hit test is the live palette's.
    local view = ns.CreatePaletteView(UIParent, {})
    view:Layout(1)
    view:GetFrame():SetCenter(960, 540)
    view._steered = true

    -- Press edge, far from the palette, so the "cursor never moved" gate can
    -- never trip during the sweep itself.
    CURSOR.x, CURSOR.y = 20, 20
    snippet(btn, "LeftButton", true)

    local checked, mismatch, hard, first, nested = 0, 0, 0, nil, 0
    local reach = 420
    for dx = -reach, reach, step do
        for dy = -reach, reach, step do
            CURSOR.x, CURSOR.y = 960 + dx, 540 + dy
            -- Unarmed: this sample never passed through any claim's own
            -- parent entry to get here, so neither side may answer with one
            -- of its children -- the pass-through rule this whole harness
            -- extension exists to hold both sides to. See SweepArmed below
            -- for the path that DOES arm a claim.
            btn:SetAttribute("eapArmed", nil)
            local want = view:HitTest()
            snippet(btn, "LeftButton", false)
            local why = btn:GetAttribute("eapWhy")
            local got = (why ~= "deadzone" and why ~= "noidx" and why ~= "unmoved")
                        and btn:GetAttribute("eapIdx") or nil
            checked = checked + 1
            if want and want > view.shownCount then nested = nested + 1 end
            if want ~= got then
                -- A disagreement exactly ON a sector edge is float noise: the
                -- two do the same arithmetic in different units, and the file
                -- already documents that they land either side of the rounding
                -- there. One that survives a nudge in every direction is a real
                -- difference in the RULE, which is what this is hunting.
                local structural = true
                for _, d in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1} }) do
                    CURSOR.x, CURSOR.y = 960 + dx + d[1], 540 + dy + d[2]
                    local w2 = view:HitTest()
                    snippet(btn, "LeftButton", false)
                    local y2 = btn:GetAttribute("eapWhy")
                    local g2 = (y2 ~= "deadzone" and y2 ~= "noidx" and y2 ~= "unmoved")
                               and btn:GetAttribute("eapIdx") or nil
                    if w2 == g2 then structural = false break end
                end
                CURSOR.x, CURSOR.y = 960 + dx, 540 + dy
                mismatch = mismatch + 1
                if structural then
                    hard = hard + 1
                    first = first or ("  STRUCTURAL at dx=%d dy=%d  view=%s snippet=%s why=%s")
                        :format(dx, dy, tostring(want), tostring(got), tostring(why))
                end
            end
        end
    end
    -- Unarmed, a nest is no longer merely undrawn -- it is UNREACHABLE. Every
    -- one of these samples arrived with eapArmed cleared, so a claim that
    -- still answered here would mean the pass-through rule leaked: the
    -- release fired a child the cursor never earned by going through its
    -- parent first. That is a hard failure now, not a vacuous-sweep warning.
    local leaked = (nested > 0) and "  <-- ARMED WHILE UNARMED" or ""
    print(("%-34s %8d checked  %5d on an edge  %5d structural%s%s"):format(
        label, checked, mismatch - hard, hard, hard > 0 and "  <-- FAIL" or "", leaked))
    if first then print(first) end
    return hard + ((nested > 0) and 1 or 0)
end

local function Palette(i) return ns.EnsurePalette(i) end

local bad = 0
local step = tonumber(arg[2]) or 3

-- Palette 1 holds four spells; slot 3 opens palette 2, which holds five.
local function Base(nParent, nestAt, nChild)
    return function()
        local a = Palette(1)
        a.slots = {}
        for i = 1, nParent do a.slots[i] = { kind = "spell", id = 100 + i } end
        if nestAt then a.slots[nestAt] = { kind = "palette", palette = 2 } end
        local b = Palette(2)
        b.slots = {}
        for i = 1, nChild do b.slots[i] = { kind = "spell", id = 200 + i } end
        p.paletteCount = 2
    end
end

bad = bad + Sweep("flat, no nest", Base(4, nil, 0), step)

bad = bad + Sweep("full circle, contained", function()
    Base(4, 3, 5)()
    p.arcSpan, p.arcChildOverflow = 360, "NONE"
end, step)

bad = bad + Sweep("full circle, overflowing", function()
    Base(4, 3, 5)()
    p.arcSpan, p.arcChildOverflow, p.arcChildMaxSpan = 360, "MIDPOINT", 90
end, step)

bad = bad + Sweep("open arc 180, contained", function()
    Base(5, 2, 4)()
    p.arcSpan, p.arcRotation, p.arcChildOverflow = 180, 0, "NONE"
end, step)

bad = bad + Sweep("open arc 120 rotated, overflow", function()
    Base(5, 4, 8)()
    p.arcSpan, p.arcRotation = 120, -60
    p.arcChildOverflow, p.arcChildMaxSpan = "MIDPOINT", 120
end, step)

bad = bad + Sweep("two nests, adjacent", function()
    Base(4, 2, 6)()
    Palette(1).slots[3] = { kind = "palette", palette = 3 }
    local c = Palette(3)
    c.slots = {}
    for i = 1, 3 do c.slots[i] = { kind = "spell", id = 300 + i } end
    p.paletteCount = 3
    p.arcSpan, p.arcChildOverflow = 360, "MIDPOINT"
end, step)

bad = bad + Sweep("nest of one entry", function()
    Base(3, 2, 1)()
    p.arcSpan, p.arcChildOverflow = 360, "NONE"
end, step)

bad = bad + Sweep("twelve entries, eight children", function()
    Base(12, 7, 8)()
    p.arcSpan, p.arcChildOverflow = 360, "NONE"
end, step)

-- The parent sits at angle 0 -- straight up -- rather than off to a side.
-- Nothing in ChildGeom is supposed to treat that angle differently from any
-- other, but it is exactly where atan2's wrap from just-under-360 back to 0
-- would show up if it ever did.
bad = bad + Sweep("nest at top middle", function()
    Base(3, 1, 5)()
    p.arcSpan, p.arcChildOverflow = 360, "NONE"
end, step)

-- Eight children, a small radius and full-size child icons packed into a
-- sixty-degree sector: row 1 only has room for a handful of them, so this
-- claim spills into a second and third ring rather than growing the first
-- ring's radius without bound.
bad = bad + Sweep("crowded claim, spills into extra rings", function()
    Base(6, 1, 8)()
    p.arcSpan, p.arcChildOverflow = 360, "NONE"
    p.radius, p.iconSize, p.nestScale, p.nestBand = 60, 44, 1.0, 10
end, step)
-- Every other config in this file leans on the coded fallbacks (`p.radius or
-- 96` and the like) rather than setting these fields, so leaving them here
-- would silently shrink every ring in every config that follows -- including
-- the Crowding checks further down, which do not set them either.
p.radius, p.nestScale, p.nestBand = nil, nil, nil

----------------------------------------------------------------------------
--  Block layouts steer in AdvanceGrid rather than HitTest, so they get their
--  own sweep. Same question: does the release pick what the palette drew?
----------------------------------------------------------------------------
local function SweepCells(label, setup, step)
    setup()
    ns.Refresh()

    local btn = byName["EUIActionPaletteButton1"]
    btn:SetFrameRef("ui", UIParent)

    local view = ns.CreatePaletteView(UIParent, {})
    view:Layout(1)
    view:GetFrame():SetCenter(960, 540)
    view._steered = true
    view._gateX, view._gateY = 20, 20

    CURSOR.x, CURSOR.y = 20, 20
    snippet(btn, "LeftButton", true)

    local checked, edge, hard, first, nested = 0, 0, 0, nil, 0
    local reach = 380
    local function Pair(dx, dy)
        CURSOR.x, CURSOR.y = 960 + dx, 540 + dy
        -- Unarmed: see the same note in Sweep above. Every block-layout claim
        -- goes through ArmedClaim now, so a cold sample must never answer with
        -- one of its cells on either side.
        btn:SetAttribute("eapArmed", nil)
        view:AdvanceGrid()
        local want = view:GetSelection()
        snippet(btn, "LeftButton", false)
        local why = btn:GetAttribute("eapWhy")
        local got = (why ~= "outofreach" and why ~= "noidx" and why ~= "unmoved")
                    and btn:GetAttribute("eapIdx") or nil
        return want, got, why
    end

    for dx = -reach, reach, step do
        for dy = -reach, reach, step do
            local want, got, why = Pair(dx, dy)
            checked = checked + 1
            if want and want > view.shownCount then nested = nested + 1 end
            if want ~= got then
                local structural = true
                for _, d in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1} }) do
                    local w2, g2 = Pair(dx + d[1], dy + d[2])
                    if w2 == g2 then structural = false break end
                end
                if structural then
                    hard = hard + 1
                    first = first or ("  STRUCTURAL at dx=%d dy=%d  view=%s snippet=%s why=%s")
                        :format(dx, dy, tostring(want), tostring(got), tostring(why))
                else
                    edge = edge + 1
                end
            end
        end
    end
    -- Unarmed, a claim's cells are UNREACHABLE, not merely undrawn -- see the
    -- matching note in Sweep. A hit here means the pass-through rule leaked.
    local leaked = (nested > 0) and "  <-- ARMED WHILE UNARMED" or ""
    print(("%-34s %8d checked  %5d on an edge  %5d structural%s%s"):format(
        label, checked, edge, hard, hard > 0 and "  <-- FAIL" or "", leaked))
    if first then print(first) end
    return hard + ((nested > 0) and 1 or 0)
end

bad = bad + SweepCells("grid 3x3, nest on a corner", function()
    Base(9, 1, 5)()
    p.layout, p.gridAutoColumns = "GRID", true
end, step)

bad = bad + SweepCells("grid 3x3, nest in the middle", function()
    Base(9, 5, 4)()
    p.layout, p.gridAutoColumns = "GRID", true
end, step)

bad = bad + SweepCells("grid, two nests", function()
    Base(8, 1, 6)()
    Palette(1).slots[8] = { kind = "palette", palette = 3 }
    local c = Palette(3)
    c.slots = {}
    for i = 1, 5 do c.slots[i] = { kind = "spell", id = 300 + i } end
    p.paletteCount = 3
    p.layout, p.gridAutoColumns = "GRID", true
end, step)

bad = bad + SweepCells("grid, adjacent nests compete", function()
    Base(6, 1, 8)()
    Palette(1).slots[2] = { kind = "palette", palette = 3 }
    local c = Palette(3)
    c.slots = {}
    for i = 1, 8 do c.slots[i] = { kind = "spell", id = 300 + i } end
    p.paletteCount = 3
    p.layout, p.gridAutoColumns = "GRID", true
end, step)

bad = bad + SweepCells("grid halo, nest in the middle", function()
    Base(9, 5, 8)()
    p.layout, p.gridAutoColumns = "GRID", true
    p.gridNestStyle = "HALO"
end, step)

bad = bad + SweepCells("grid halo, two of them adjacent", function()
    Base(9, 4, 8)()
    Palette(1).slots[5] = { kind = "palette", palette = 3 }
    local c = Palette(3)
    c.slots = {}
    for i = 1, 8 do c.slots[i] = { kind = "spell", id = 300 + i } end
    p.paletteCount = 3
    p.layout, p.gridAutoColumns = "GRID", true
    p.gridNestStyle = "HALO"
end, step)

bad = bad + SweepCells("grid popout, nest on a corner", function()
    Base(9, 1, 6)()
    p.layout, p.gridAutoColumns = "GRID", true
    p.gridNestStyle = "POPOUT"
end, step)

bad = bad + SweepCells("grid popout, nest in the middle", function()
    Base(9, 5, 8)()
    p.layout, p.gridAutoColumns = "GRID", true
    p.gridNestStyle = "POPOUT"
end, step)

bad = bad + SweepCells("grid popout, side flipped", function()
    Base(9, 5, 4)()
    p.layout, p.gridAutoColumns = "GRID", true
    p.gridNestStyle, p.nestSide = "POPOUT", "NEGATIVE"
end, step)

-- A GRID reaches NestMetrics' forced STRIP style whenever it comes out one row
-- or one column deep, same as a pointer fan -- pinning gridColumns is the
-- other way in, and it is worth its own check because a GRID palette gets
-- there without ever touching FanHoriz.
bad = bad + SweepCells("grid single row, nest in the middle", function()
    Base(5, 3, 7)()
    p.layout, p.gridAutoColumns, p.gridColumns = "GRID", false, 5
end, step)
p.gridColumns = nil

bad = bad + SweepCells("grid single column, nest near an end", function()
    Base(5, 4, 6)()
    p.layout, p.gridAutoColumns, p.gridColumns = "GRID", false, 1
end, step)
p.gridColumns = nil

-- Two nests whose parents are neighbours, with eight children each: the two
-- t0s are barely a couple of child pitches apart, so the lane between them
-- genuinely runs out and PerimeterNest's room/cols arithmetic has to spill BOTH
-- of them into further rows rather than only one. The single-row case, where
-- the room is there and extending along the lane is the whole answer, is
-- checked for real in the lane placement section further down.
bad = bad + SweepCells("grid lane, two nests crowd into rows", function()
    Base(9, 1, 8)()
    Palette(1).slots[2] = { kind = "palette", palette = 3 }
    local c = Palette(3)
    c.slots = {}
    for i = 1, 8 do c.slots[i] = { kind = "spell", id = 300 + i } end
    p.paletteCount = 3
    p.layout, p.gridAutoColumns = "GRID", true
    p.nestScale, p.nestBand = 0.6, 14
end, step)
p.nestScale, p.nestBand = nil, nil

-- A strip ignores gridNestStyle: one entry deep, it has only ever the one
-- answer. Set to something else here so that claim is under test rather than
-- merely asserted in a comment.
bad = bad + SweepCells("pointer fan, horizontal", function()
    Base(5, 3, 6)()
    p.layout, p.fanInput, p.fanOrientation = "FAN", "CURSOR", "HORIZONTAL"
    p.gridNestStyle = "HALO"
end, step)

bad = bad + SweepCells("pointer fan, vertical", function()
    Base(5, 2, 6)()
    p.layout, p.fanInput, p.fanOrientation = "FAN", "CURSOR", "VERTICAL"
end, step)

bad = bad + SweepCells("pointer fan, nest side flipped", function()
    Base(5, 2, 6)()
    p.layout, p.fanInput, p.fanOrientation = "FAN", "CURSOR", "VERTICAL"
    p.nestSide = "NEGATIVE"
end, step)

----------------------------------------------------------------------------
--  A scroll-steered strip. The wheel picks the entry, so the sweep pins the
--  accumulator and moves only the cursor -- which in this layout says two
--  things and two only: which child of a nest, and whether the strip has been
--  left. Both are what this is checking.
----------------------------------------------------------------------------
local function SweepStrip(label, setup, target, step)
    setup()
    ns.Refresh()

    local btn = byName["EUIActionPaletteButton1"]
    btn:SetFrameRef("ui", UIParent)

    local view = ns.CreatePaletteView(UIParent, { live = false })
    view:Layout(1)
    view:GetFrame():SetCenter(960, 540)

    CURSOR.x, CURSOR.y = 960, 540
    snippet(btn, "LeftButton", true)
    -- Both ends steered to the same entry: the wheel snippet keeps this on the
    -- catcher, and the view reads it from there for a LIVE strip only.
    local catcher = btn:GetFrameRef("catcher")
    catcher:SetAttribute("eapFanTarget", target)
    view.fanTarget = target
    view._gateX, view._gateY = 960, 540

    local checked, edge, hard, first, nested = 0, 0, 0, nil, 0
    local reach = 260
    local function Pair(dx, dy)
        CURSOR.x, CURSOR.y = 960 + dx, 540 + dy
        view:AdvanceFan(0)
        local want = view:GetSelection()
        snippet(btn, "LeftButton", false)
        local why = btn:GetAttribute("eapWhy")
        local got = (why ~= "thrownclear" and why ~= "noidx" and why ~= "unmoved")
                    and btn:GetAttribute("eapIdx") or nil
        return want, got, why
    end

    for dx = -reach, reach, step do
        for dy = -reach, reach, step do
            local want, got, why = Pair(dx, dy)
            checked = checked + 1
            if want and want > view.shownCount then nested = nested + 1 end
            if want ~= got then
                local structural = true
                for _, d in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1} }) do
                    local w2, g2 = Pair(dx + d[1], dy + d[2])
                    if w2 == g2 then structural = false break end
                end
                if structural then
                    hard = hard + 1
                    first = first or ("  STRUCTURAL at dx=%d dy=%d  view=%s snippet=%s why=%s")
                        :format(dx, dy, tostring(want), tostring(got), tostring(why))
                else
                    edge = edge + 1
                end
            end
        end
    end
    local vacuous = (nested == 0) and "  <-- VACUOUS" or ""
    print(("%-34s %8d checked  %5d on an edge  %5d structural%s%s"):format(
        label, checked, edge, hard, hard > 0 and "  <-- FAIL" or "", vacuous))
    if first then print(first) end
    return hard + ((nested == 0) and 1 or 0)
end

bad = bad + SweepStrip("scroll fan horizontal, on the nest", function()
    Base(5, 3, 6)()
    p.layout, p.fanInput, p.fanOrientation = "FAN", "SCROLL", "HORIZONTAL"
end, 3, step)

bad = bad + SweepStrip("scroll fan vertical, on the nest", function()
    Base(5, 2, 8)()
    p.layout, p.fanInput, p.fanOrientation = "FAN", "SCROLL", "VERTICAL"
end, 2, step)

bad = bad + SweepStrip("scroll fan, side flipped", function()
    Base(5, 2, 4)()
    p.layout, p.fanInput, p.fanOrientation = "FAN", "SCROLL", "HORIZONTAL"
    p.nestSide = "NEGATIVE"
end, 2, step)

-- Back to the arc for the checks below.
p.layout, p.fanInput, p.nestSide = "ARC", "SCROLL", "POSITIVE"
p.gridNestStyle = "PERIMETER"

----------------------------------------------------------------------------
--  The cell a hit test answers with must name the SAME action the button
--  would fire from that index. An off-by-one between the view's flattening
--  and the push would leave both sides agreeing on a number and firing the
--  wrong thing, which the sweep above cannot see.
----------------------------------------------------------------------------
do
    local a = Palette(1)
    a.slots = { { kind = "spell", id = 11 }, { kind = "palette", palette = 2 },
                { kind = "spell", id = 13 } }
    local b = Palette(2)
    b.slots = {}
    for i = 1, 5 do b.slots[i] = { kind = "spell", id = 20 + i } end
    p.paletteCount = 2
    p.arcSpan, p.arcChildOverflow = 360, "NONE"
    ns.Refresh()

    local btn  = byName["EUIActionPaletteButton1"]
    local view = ns.CreatePaletteView(UIParent, {})
    view:Layout(1)

    local wrong = 0
    for idx = 1, (btn:GetAttribute("eapTotal") or 0) do
        local slot = view:CellSlot(idx)
        local pushed = btn:GetAttribute("eapV" .. idx)
        local want = slot and select(3, ns.ResolveAction(slot)) or nil
        local isPal = btn:GetAttribute("eapPal" .. idx)
        if pushed ~= want then
            wrong = wrong + 1
            print(("  cell %d: view=%s pushed=%s"):format(idx, tostring(want), tostring(pushed)))
        end
        if (slot and slot.kind == "palette") ~= (isPal == true) then
            wrong = wrong + 1
            print(("  cell %d: palette marker disagrees"):format(idx))
        end
    end
    print(("cell -> action mapping            %8d cells   %5d wrong%s"):format(
        btn:GetAttribute("eapTotal") or 0, wrong, wrong > 0 and "  <-- FAIL" or ""))
    bad = bad + wrong
end

----------------------------------------------------------------------------
--  No two cells may sit on top of each other. The sweep cannot see this: both
--  sides run the SAME nearest-cell rule, so they would agree happily about an
--  overlap that leaves the palette unreadable and one of the two entries
--  unreachable.
----------------------------------------------------------------------------
do
    local fails = 0
    local function Crowding(label, setup)
        setup()
        ns.Refresh()
        local view = ns.CreatePaletteView(UIParent, {})
        view:Layout(1)

        local pitch = view:Pitch()
        local cells = {}
        local shown = view:ShownCount()
        if view:LayoutMode() == "ARC" then
            local radius = select(1, view:Geom())
            local st, a0 = view:ArcGeom(shown)
            for i = 1, shown do
                local ang = a0 + (i - 1) * st
                cells[#cells + 1] = { x = radius * math.sin(ang),
                                      y = radius * math.cos(ang),
                                      what = "entry " .. i }
            end
        else
            local cols, rows = view:GridDims()
            for i = 1, shown do
                local x, y = view:GridBase(i, cols, rows, pitch)
                cells[#cells + 1] = { x = x, y = y, what = "entry " .. i }
            end
        end
        for _, c in ipairs(view.claims or {}) do
            for j = 1, c.n do
                local x, y
                if c.cells then
                    x, y = c.cells[j].x, c.cells[j].y
                else
                    -- An arc claim is polar, and now possibly several rings
                    -- deep; the same crowding question needs it in the
                    -- frame's own units like everything else.
                    local r, ang = view:ChildRingPos(c, j)
                    x, y = r * math.sin(ang), r * math.cos(ang)
                end
                cells[#cells + 1] = { x = x, y = y,
                                      what = "nest of " .. c.parent .. " #" .. j }
            end
        end

        -- Two icons may not sit closer than the smaller of them is wide.
        local floorGap = view.claims and view.claims[1]
            and math.min(pitch, view.claims[1].icon) or pitch
        local worst, worstPair = math.huge, nil
        for i = 1, #cells do
            for j = i + 1, #cells do
                local dx = cells[i].x - cells[j].x
                local dy = cells[i].y - cells[j].y
                local d = (dx * dx + dy * dy) ^ 0.5
                if d < worst then
                    worst, worstPair = d, cells[i].what .. " / " .. cells[j].what
                end
            end
        end
        local ok = worst >= floorGap * 0.99
        if not ok then
            fails = fails + 1
            print(("  %s: closest pair %.1f (floor %.1f) -- %s")
                :format(label, worst, floorGap, worstPair))
        end
    end

    Crowding("grid, adjacent nests", function()
        Base(6, 1, 8)()
        Palette(1).slots[2] = { kind = "palette", palette = 3 }
        local c = Palette(3)
        c.slots = {}
        for i = 1, 8 do c.slots[i] = { kind = "spell", id = 300 + i } end
        p.paletteCount = 3
        p.layout, p.gridAutoColumns = "GRID", true
    end)
    Crowding("grid, three nests in a row", function()
        Base(9, 1, 6)()
        Palette(1).slots[2] = { kind = "palette", palette = 3 }
        Palette(1).slots[3] = { kind = "palette", palette = 4 }
        for _, i in ipairs({ 3, 4 }) do
            local c = Palette(i)
            c.slots = {}
            for j = 1, 6 do c.slots[j] = { kind = "spell", id = 400 + j } end
        end
        p.paletteCount = 4
        p.layout, p.gridAutoColumns = "GRID", true
    end)
    Crowding("pointer fan, two nests", function()
        Base(6, 2, 6)()
        Palette(1).slots[5] = { kind = "palette", palette = 3 }
        local c = Palette(3)
        c.slots = {}
        for i = 1, 6 do c.slots[i] = { kind = "spell", id = 300 + i } end
        p.paletteCount = 3
        p.layout, p.fanInput = "FAN", "CURSOR"
    end)
    Crowding("grid single row, two nests", function()
        Base(6, 3, 6)()
        Palette(1).slots[4] = { kind = "palette", palette = 3 }
        local c = Palette(3)
        c.slots = {}
        for i = 1, 6 do c.slots[i] = { kind = "spell", id = 300 + i } end
        p.paletteCount = 3
        p.layout, p.gridAutoColumns, p.gridColumns = "GRID", false, 6
    end)
    p.gridColumns = nil
    Crowding("arc, two nests", function()
        Base(4, 2, 6)()
        Palette(1).slots[3] = { kind = "palette", palette = 3 }
        local c = Palette(3)
        c.slots = {}
        for i = 1, 6 do c.slots[i] = { kind = "spell", id = 300 + i } end
        p.paletteCount = 3
        p.layout = "ARC"
    end)

    print(("no two cells overlap                              %5d wrong%s"):format(
        fails, fails > 0 and "  <-- FAIL" or ""))
    bad = bad + fails
    p.layout, p.fanInput = "ARC", "SCROLL"
end

----------------------------------------------------------------------------
--  Lane placement. The sweeps above prove the two sides agree about where a
--  lane's cells are; they cannot see whether that is where the cells BELONG,
--  both of them reading the one table. These check the three reads the style
--  exists for -- a run centred on the point of the perimeter nearest the entry
--  that opens it, hugging the block, extending ALONG the lane rather than
--  stacking outward while there is lane still to be had -- and the regions a
--  run that wrapped a corner comes out with.
----------------------------------------------------------------------------
do
    local fails = 0
    local function Bad(label, what)
        fails = fails + 1
        print(("  %s: %s"):format(label, what))
    end

    -- Everything a lane check measures against, laid out from the same profile
    -- the live palette reads.
    local function Lane(setup)
        setup()
        p.layout, p.gridAutoColumns, p.gridNestStyle = "GRID", true, "PERIMETER"
        ns.Refresh()
        local view = ns.CreatePaletteView(UIParent, {})
        view:Layout(1)
        local cols, rows = view:GridDims()
        local pitch = view:Pitch()
        local centres = {}
        for i = 1, view:ShownCount() do
            local x, y = view:GridBase(i, cols, rows, pitch)
            centres[i] = { x = x, y = y }
        end
        return view, view:NestMetrics(view:ShownCount()), centres
    end

    -- How far outside the block's own outer edge a cell's box begins, measured
    -- ACROSS the run it sits on -- along the run the same subtraction says only
    -- how far round the block the cell has travelled. A cell in the FIRST row of
    -- the lane reaches back to that edge exactly -- one round a corner stops a
    -- few units short of it, the turn cutting in -- while a second row sits a
    -- whole child pitch further out. That is what tells the two apart here
    -- without keeping a second copy of the placement maths.
    local function Standoff(b, axis, m)
        if axis == "X" then
            return (math.abs(b.y) - b.hh) - (m.halfY + m.icon * 0.5)
        end
        return (math.abs(b.x) - b.hw) - (m.halfX + m.icon * 0.5)
    end

    -- No nested cell's box may hold one of the palette's OWN cell centres: a
    -- lane hugs the block, and a box that reached over an entry's centre would
    -- leave that entry unselectable for as long as the nest was up. Reported as
    -- the tightest margin over every case below rather than as a bare pass, the
    -- number being the whole question.
    local tightest, tightWhere = math.huge, "nothing"
    local function ClearOfCentres(label, view, centres)
        for _, c in ipairs(view.claims) do
            for j = 1, c.n do
                local b = c.cells[j]
                for i, q in ipairs(centres) do
                    local margin = math.max(math.abs(q.x - b.x) - b.hw,
                                            math.abs(q.y - b.y) - b.hh)
                    if margin < tightest then
                        tightest, tightWhere =
                            margin, ("%s, cell %d of %d over entry %d")
                                :format(label, j, c.parent, i)
                    end
                    if margin <= 0 then
                        Bad(label, ("cell %d of claim on %d covers entry %d's centre")
                            :format(j, c.parent, i))
                    end
                end
            end
        end
    end

    local function SingleRow(label, view, m)
        for _, c in ipairs(view.claims) do
            for _, g in ipairs(c.groups) do
                for j, b in ipairs(g.cells) do
                    local out = Standoff(b, g.axis, m)
                    if out > (m.childIcon + m.gap) * 0.5 then
                        Bad(label, ("cell %d on the %s%+d side of the claim on %d sits in a second row (%.1f out)")
                            :format(j, g.axis, g.sign, c.parent, out))
                    end
                end
            end
        end
    end

    -- Snug: a first-row child ICON stands one gap outside the block's own outer
    -- edge, which is what makes the lane read as a halo on the grid rather than
    -- a second block floating off it. Nest Distance is honoured on top of that,
    -- so what to expect is the gap plus whatever extra was asked for. Read at
    -- the cells FURTHEST out -- the ones on the straight stretches -- because a
    -- cell round a corner comes nearer than that, the turn cutting in; what
    -- those have to answer for is only that they never come inside the block.
    local function Snug(label, view, m)
        for _, c in ipairs(view.claims) do
            local lo, hi = math.huge, -math.huge
            for _, g in ipairs(c.groups) do
                for _, b in ipairs(g.cells) do
                    if Standoff(b, g.axis, m) <= (m.childIcon + m.gap) * 0.5 then
                        local across = (g.axis == "X") and b.y or b.x
                        local half = (g.axis == "X") and m.halfY or m.halfX
                        local d = (math.abs(across) - m.childIcon * 0.5)
                                  - (half + m.icon * 0.5)
                        lo, hi = math.min(lo, d), math.max(hi, d)
                    end
                end
            end
            local want = m.gap + m.bandExtra
            if math.abs(hi - want) > 0.01 or lo < 0 then
                Bad(label, ("claim on %d stands %.1f..%.1f off the block, want %.1f at the furthest and nothing inside")
                    :format(c.parent, lo, hi, want))
            end
        end
    end

    local function MeanX(c)
        local sum = 0
        for j = 1, c.n do sum = sum + c.cells[j].x end
        return sum / c.n
    end

    -- 1. A parent in the middle of the block is the same distance from all four
    -- edges, so there is no lean to read and nestSide answers: the middle of the
    -- POSITIVE edge, which is the top.
    do
        local label = "centre parent"
        local view, m, centres = Lane(Base(9, 5, 4))
        local c = view.claims[1]
        if c.axis ~= "X" or c.sign ~= 1 or #c.groups ~= 1 then
            Bad(label, ("run on %s%+d in %d pieces, want one on X+1")
                :format(tostring(c.axis), c.sign, #c.groups))
        end
        if math.abs(MeanX(c)) > 0.01 then
            Bad(label, ("run centred on x=%.1f, want the middle of the edge")
                :format(MeanX(c)))
        end
        SingleRow(label, view, m)
        Snug(label, view, m)
        ClearOfCentres(label, view, centres)
    end

    -- 2. A parent on an edge, and NOT on the middle of it: the run centres just
    -- outside that parent's own cell rather than on the edge it lies on. Slot 10
    -- of a 4x3 grid is on the bottom edge, one half pitch left of centre.
    do
        local label = "edge parent"
        local view, m, centres = Lane(Base(12, 10, 3))
        local c = view.claims[1]
        if c.axis ~= "X" or c.sign ~= -1 or #c.groups ~= 1 then
            Bad(label, ("run on %s%+d in %d pieces, want one on X-1")
                :format(tostring(c.axis), c.sign, #c.groups))
        end
        if math.abs(MeanX(c) - c.parentBox.x) > 0.01 then
            Bad(label, ("run centred on x=%.1f, parent cell at x=%.1f")
                :format(MeanX(c), c.parentBox.x))
        end
        SingleRow(label, view, m)
        Snug(label, view, m)
        ClearOfCentres(label, view, centres)
    end

    -- 3. A CORNER parent is exactly as far from both of the edges that meet at
    -- its corner, so the run centres on the corner itself and wraps its L around
    -- it: half the children down each of the two sides, and one box per side --
    -- never one box across the pair, which would swallow the block's own corner
    -- ground and bring the dim-never-backs-out complaint straight back.
    do
        local label = "corner parent"
        local view, m, centres = Lane(Base(9, 1, 6))
        local cols = view:GridDims()
        local c = view.claims[1]
        local sides = {}
        for _, g in ipairs(c.groups) do sides[g.axis .. g.sign] = #g.cells end
        -- Slot 1 of a 3x3 is the top-left cell: the top edge and the left one.
        if #c.groups ~= 2 or sides["X1"] ~= 3 or sides["Y-1"] ~= 3 then
            local shape = ""
            for _, g in ipairs(c.groups) do
                shape = shape .. (" %s%+d x%d"):format(g.axis, g.sign, #g.cells)
            end
            Bad(label, "run came out as" .. shape .. ", want three on X+1 and three on Y-1")
        end
        if #c.regions > ns.REGION_MAX then
            Bad(label, ("%d regions, only %d gates to put them in")
                :format(#c.regions, ns.REGION_MAX))
        end
        -- Every region past the parent's own cell is a side of the run with the
        -- parent's own cell folded in (see RunReach), so it sweeps the ground
        -- between the two: a parent on the block's edge sweeps along its own row
        -- or its own column, and nothing else. Whatever entries stand in that
        -- sweep stay selectable, they simply do not back the nest out -- but an
        -- entry OFF it, the block's whole diagonal interior included, must be
        -- outside every region, which is exactly what one box across the L
        -- would not leave it.
        local pr, pc = math.floor((c.parent - 1) / cols), (c.parent - 1) % cols
        for r = 2, #c.regions do
            local b = c.regions[r]
            for i, q in ipairs(centres) do
                local ir, ic = math.floor((i - 1) / cols), (i - 1) % cols
                if InBox(b, q.x, q.y) and ir ~= pr and ic ~= pc then
                    Bad(label, ("region %d covers entry %d's centre, off the parent's own row and column")
                        :format(r, i))
                end
            end
        end
        SingleRow(label, view, m)
        Snug(label, view, m)
        ClearOfCentres(label, view, centres)
    end

    -- 4. Two nests with room between them: the lane splits at the midpoint of
    -- the two, and each run EXTENDS along its own half rather than giving up
    -- cells per row and stacking outward. Three children each in a 3x3 is well
    -- within what half the lane holds, so a second row here would mean the
    -- crowding rule fired when nothing was crowded.
    do
        local label = "two nests, room to spare"
        local view, m, centres = Lane(function()
            Base(9, 1, 3)()
            Palette(1).slots[3] = { kind = "palette", palette = 3 }
            local c = Palette(3)
            c.slots = {}
            for i = 1, 3 do c.slots[i] = { kind = "spell", id = 300 + i } end
            p.paletteCount = 3
        end)
        SingleRow(label, view, m)
        Snug(label, view, m)
        ClearOfCentres(label, view, centres)
        -- And the two runs keep off each other: a claim may extend into the
        -- lane only as far as the halfway point with its neighbour.
        local c1, c2 = view.claims[1], view.claims[2]
        local worst = math.huge
        for i = 1, c1.n do
            for j = 1, c2.n do
                local dx = c1.cells[i].x - c2.cells[j].x
                local dy = c1.cells[i].y - c2.cells[j].y
                worst = math.min(worst, (dx * dx + dy * dy) ^ 0.5)
            end
        end
        if worst < m.childPitch * 0.99 then
            Bad(label, ("the two runs come within %.1f, a child pitch is %.1f")
                :format(worst, m.childPitch))
        end
    end

    -- 5. Nest Distance below the value the profile ships with buys a lane
    -- nothing: it already hugs the block, and the slider only ever adds. So
    -- moving it there must change NOTHING -- not the cells, and not the arming
    -- slack around them either, which is invisible and would otherwise be the
    -- one thing the bottom quarter of that slider still moved. Above it, the
    -- geometry has to answer.
    do
        local label = "nest distance below the default"
        local function Shape(band)
            local view = Lane(function()
                Base(9, 1, 6)()
                p.nestBand = band
            end)
            local c = view.claims[1]
            local out = {}
            for _, set in ipairs({ c.cells, c.regions }) do
                for _, b in ipairs(set) do
                    out[#out + 1] = ("%.3f,%.3f,%.3f,%.3f"):format(b.x, b.y, b.hw, b.hh)
                end
            end
            return table.concat(out, " ")
        end
        local at0, at20, at40, at120 = Shape(0), Shape(20), Shape(40), Shape(120)
        p.nestBand = nil
        if at0 ~= at40 or at20 ~= at40 then
            Bad(label, "0, 20 and 40 do not all lay the same claim out")
        end
        if at120 == at40 then
            Bad(label, "120 lays out exactly as 40 does, so the slider does nothing at all")
        end
    end

    print(("lane placement                                    %5d wrong%s"):format(
        fails, fails > 0 and "  <-- FAIL" or ""))
    print(("  nearest a lane cell comes to an entry's centre: %.1f  (%s)")
        :format(tightest, tightWhere))
    bad = bad + fails
    p.layout, p.gridNestStyle = "ARC", "PERIMETER"
end

----------------------------------------------------------------------------
--  Armed sweeps: the sweeps above prove UNARMED never answers with a nested
--  cell. This proves the other half -- that ARMED does, and that it is
--  specifically the claim the cursor walked through that answers, at the
--  SAME screen point a moment ago proved unreachable cold. Two configs, both
--  chosen to overlap ground: two arc nests sharing an overflowed sector, and
--  two grid halos sitting next to each other -- the exact shape reported
--  in-game as "the drawn nest swaps back and forth".
----------------------------------------------------------------------------
do
    local fails = 0

    local function CheckClaim(label, view, btn, isBlock)
        local c = view.claims[1]
        local dx, dy
        if c.cells then
            dx, dy = c.cells[1].x, c.cells[1].y
        else
            local r, a = view:ChildRingPos(c, 1)
            dx, dy = r * math.sin(a), r * math.cos(a)
        end
        local wantIdx = c.base + 1

        local function Selection(armed)
            btn:SetAttribute("eapArmed", armed)
            CURSOR.x, CURSOR.y = 960 + dx, 540 + dy
            local want
            if isBlock then
                view:AdvanceGrid()
                want = view:GetSelection()
            else
                want = view:HitTest()
            end
            snippet(btn, "LeftButton", false)
            local why = btn:GetAttribute("eapWhy")
            local got = (why ~= "deadzone" and why ~= "outofreach"
                         and why ~= "noidx" and why ~= "unmoved")
                        and btn:GetAttribute("eapIdx") or nil
            return want, got
        end

        -- Walked through claim 1's own parent: both sides land on its first
        -- child.
        local armed = ArmedViaParent(view, 1, dx, dy)
        local want, got = Selection(armed)
        if armed ~= 1 or want ~= wantIdx or got ~= wantIdx then
            fails = fails + 1
            print(("  %s (armed): armed=%s want=%s got=%s wantIdx=%s"):format(
                label, tostring(armed), tostring(want), tostring(got), tostring(wantIdx)))
        end

        -- The IDENTICAL screen point, never armed: neither side may answer
        -- with that child -- proof that arming, not proximity, is what
        -- decided the case just above.
        want, got = Selection(nil)
        if want == wantIdx or got == wantIdx then
            fails = fails + 1
            print(("  %s (unarmed): want=%s got=%s (must not be %s)"):format(
                label, tostring(want), tostring(got), tostring(wantIdx)))
        end
    end

    local function Run(label, setup, isBlock)
        setup()
        ns.Refresh()
        local btn = byName["EUIActionPaletteButton1"]
        btn:SetFrameRef("ui", UIParent)
        local view = ns.CreatePaletteView(UIParent, {})
        view:Layout(1)
        view:GetFrame():SetCenter(960, 540)
        view._steered = true
        view._gateX, view._gateY = 20, 20
        CURSOR.x, CURSOR.y = 20, 20
        snippet(btn, "LeftButton", true)
        CheckClaim(label, view, btn, isBlock)
    end

    -- ARC: two adjacent nests with room borrowed from the plain entries
    -- between them, the same overflow shape used above to sweep for
    -- structural disagreement -- now used to prove one claim's arming does
    -- not bleed into the other's.
    Run("arc, two nests adjacent", function()
        Base(4, 2, 6)()
        Palette(1).slots[3] = { kind = "palette", palette = 3 }
        local c = Palette(3)
        c.slots = {}
        for i = 1, 6 do c.slots[i] = { kind = "spell", id = 300 + i } end
        p.paletteCount = 3
        p.layout, p.arcSpan, p.arcChildOverflow = "ARC", 360, "MIDPOINT"
    end, false)

    -- GRID HALO: two adjacent halos -- the in-game report this whole feature
    -- answers, where two parents' rings occupied the same ground.
    Run("grid halo, two adjacent", function()
        Base(9, 4, 8)()
        Palette(1).slots[5] = { kind = "palette", palette = 3 }
        local c = Palette(3)
        c.slots = {}
        for i = 1, 8 do c.slots[i] = { kind = "spell", id = 300 + i } end
        p.paletteCount = 3
        p.layout, p.gridAutoColumns, p.gridNestStyle = "GRID", true, "HALO"
    end, true)

    print(("armed pass-through actually reaches through        %5d wrong%s"):format(
        fails, fails > 0 and "  <-- FAIL" or ""))
    bad = bad + fails
    p.layout, p.gridNestStyle = "ARC", "PERIMETER"
end

----------------------------------------------------------------------------
--  Exclusive arming and true-shape regions: the two live complaints these
--  fixes answer. Each check drives StepArmed through a short path of real
--  cursor samples -- exactly what a hand actually crossing this ground would
--  produce -- and, at the point that matters, cross-checks the live view and
--  the real snippet against each other too, so a bug that only shows up in
--  the SELECTION (rather than in eapArmed) cannot hide behind an armed-state
--  assertion that happens to pass.
----------------------------------------------------------------------------
do
    local fails = 0

    local function Prep(setup)
        setup()
        ns.Refresh()
        local btn = byName["EUIActionPaletteButton1"]
        btn:SetFrameRef("ui", UIParent)
        local view = ns.CreatePaletteView(UIParent, {})
        view:Layout(1)
        view:GetFrame():SetCenter(960, 540)
        view._steered = true
        view._gateX, view._gateY = 20, 20
        CURSOR.x, CURSOR.y = 20, 20
        snippet(btn, "LeftButton", true)
        return view, btn
    end

    -- Both sides told the SAME armed claim and the SAME cursor point: do they
    -- pick the same entry? isBlock chooses AdvanceGrid (block layouts) over
    -- HitTest (ARC).
    local function CheckSelection(label, view, btn, isBlock, armed, dx, dy, wantIdx)
        btn:SetAttribute("eapArmed", armed)
        CURSOR.x, CURSOR.y = 960 + dx, 540 + dy
        local want
        if isBlock then
            view:AdvanceGrid()
            want = view:GetSelection()
        else
            want = view:HitTest()
        end
        snippet(btn, "LeftButton", false)
        local why = btn:GetAttribute("eapWhy")
        local got = (why ~= "deadzone" and why ~= "outofreach"
                     and why ~= "noidx" and why ~= "unmoved")
                    and btn:GetAttribute("eapIdx") or nil
        if want ~= wantIdx or got ~= wantIdx then
            fails = fails + 1
            print(("  %s: want=%s got=%s wantIdx=%s"):format(
                label, tostring(want), tostring(got), tostring(wantIdx)))
        end
    end

    -- 1. Exclusive arming: a HALO 3x3 with two ADJACENT sub-palettes, slots 4
    -- and 5, exactly the shape reported in-game as "the drawn nest swaps back
    -- and forth". Claim 1's ring reaches past the midpoint into claim 2's own
    -- cell -- HaloNest only promises the NEIGHBOUR's CENTRE stays clear of
    -- it, not its whole cell -- so brushing that overlap used to re-arm
    -- claim 2 outright. It must not any more: claim 2's parent gate is
    -- hidden the whole time claim 1 is armed.
    do
        local view, btn = Prep(function()
            Base(9, 4, 8)()
            Palette(1).slots[5] = { kind = "palette", palette = 3 }
            local c = Palette(3)
            c.slots = {}
            for i = 1, 8 do c.slots[i] = { kind = "spell", id = 300 + i } end
            p.paletteCount = 3
            p.layout, p.gridAutoColumns, p.gridNestStyle = "GRID", true, "HALO"
        end)
        local c1, c2 = view.claims[1], view.claims[2]

        -- The one ring cell of claim 1 nearest claim 2's own parent box --
        -- found rather than assumed, since HALO_DIRS' screen orientation is
        -- an implementation detail this test has no business knowing.
        local overlap, overlapJ, bestD
        for j = 1, c1.n do
            local cell = c1.cells[j]
            local d = (cell.x - c2.parentBox.x) ^ 2 + (cell.y - c2.parentBox.y) ^ 2
            if not bestD or d < bestD then overlap, overlapJ, bestD = cell, j, d end
        end

        local armed = StepArmed(view, nil, 1e6, 1e6)
        armed = StepArmed(view, armed, c1.parentBox.x, c1.parentBox.y)
        if armed ~= 1 then
            fails = fails + 1
            print("  halo exclusive arming: walking onto claim 1's parent did not arm it")
        end

        -- Brush the overlap. Still armed 1 -- claim 2's parent gate is dark,
        -- so it cannot steal focus no matter how close the cursor sits to it.
        local stillA = StepArmed(view, armed, overlap.x, overlap.y)
        if stillA ~= 1 then
            fails = fails + 1
            print(("  halo exclusive arming: brushing claim 2's ground while armed 1 gave %s, want 1")
                :format(tostring(stillA)))
        end
        CheckSelection("halo exclusive arming (still on claim 1's ring)", view, btn, true,
            stillA, overlap.x, overlap.y, c1.base + overlapJ)

        -- Now go all the way onto claim 2's own parent cell -- past claim 1's
        -- true region (its own single bounding box stops short of a
        -- neighbour's CENTRE by construction). This is one continuous
        -- cursor move, so it disarms 1 and arms 2 in the one step, same as a
        -- real mouse motion landing there would.
        local b = StepArmed(view, stillA, c2.parentBox.x, c2.parentBox.y)
        if b ~= 2 then
            fails = fails + 1
            print(("  halo exclusive arming: reaching claim 2's own parent gave %s, want 2")
                :format(tostring(b)))
        end
        CheckSelection("halo exclusive arming (on claim 2's own parent)", view, btn, true,
            b, c2.parentBox.x, c2.parentBox.y, c2.parent)
    end

    -- 2. True-shape regions, HALO: arm the one nest in a 3x3, then move onto
    -- a PLAIN neighbouring entry a full pitch away -- outside even the old
    -- single bounding box, which only ever reached a little past the
    -- half-pitch mark. Disarmed, and the plain entry is what is selected.
    do
        local view, btn = Prep(function()
            Base(9, 4, 8)()
            p.layout, p.gridAutoColumns, p.gridNestStyle = "GRID", true, "HALO"
        end)
        local c1 = view.claims[1]
        local cols, rows = view:GridDims()
        local pitch = view:Pitch()
        -- Slot 1 sits directly above slot 4 in a 3-wide grid -- a full pitch
        -- away, axis-aligned, and no part of any nest.
        local nx, ny = view:GridBase(1, cols, rows, pitch)

        local armed = StepArmed(view, nil, 1e6, 1e6)
        armed = StepArmed(view, armed, c1.parentBox.x, c1.parentBox.y)
        local disarmed = StepArmed(view, armed, nx, ny)
        if armed ~= 1 or disarmed ~= nil then
            fails = fails + 1
            print(("  halo plain neighbour: armed=%s then %s, want 1 then nil")
                :format(tostring(armed), tostring(disarmed)))
        end
        CheckSelection("halo plain neighbour (disarmed, on slot 1)", view, btn, true,
            disarmed, nx, ny, 1)
    end

    -- 3. True-shape regions, POPOUT and PERIMETER: a corner parent, so its
    -- nest breaks out through the block's own edge with no interior cell in
    -- the way -- the clean case for telling "on the corridor" apart from
    -- "elsewhere in the block". Wandering onto a plain entry on the far side
    -- of the block disarms; wandering out along the corridor to a child
    -- keeps the nest live the whole way.
    for _, style in ipairs({ "POPOUT", "PERIMETER" }) do
        local view, btn = Prep(function()
            Base(9, 1, 6)()
            p.layout, p.gridAutoColumns, p.gridNestStyle = "GRID", true, style
        end)
        local c1 = view.claims[1]
        local cols, rows = view:GridDims()
        local pitch = view:Pitch()
        -- Slot 9, the opposite corner: clear of both the parent (slot 1) and
        -- whichever edge this style broke the nest out through.
        local farX, farY = view:GridBase(9, cols, rows, pitch)

        local armed = StepArmed(view, nil, 1e6, 1e6)
        armed = StepArmed(view, armed, c1.parentBox.x, c1.parentBox.y)
        local offCorridor = StepArmed(view, armed, farX, farY)
        if armed ~= 1 or offCorridor ~= nil then
            fails = fails + 1
            print(("  %s off corridor: armed=%s then %s, want 1 then nil")
                :format(style, tostring(armed), tostring(offCorridor)))
        end
        CheckSelection(style .. " off corridor (disarmed, on slot 9)", view, btn, true,
            offCorridor, farX, farY, 9)

        -- Back through the parent, out across the ground between it and the
        -- nest, and on to the nest's first child -- three samples, never
        -- leaving claim 1's true ground. The midpoint rather than a named
        -- region: POPOUT connects the two with a corridor of its own and a
        -- lane folds that connection into the run's own rect (see RunReach),
        -- and what both have to answer for is the same reach.
        local a2 = StepArmed(view, armed,
                             (c1.parentBox.x + c1.cells[1].x) * 0.5,
                             (c1.parentBox.y + c1.cells[1].y) * 0.5)
        local a3 = StepArmed(view, a2, c1.cells[1].x, c1.cells[1].y)
        if a2 ~= 1 or a3 ~= 1 then
            fails = fails + 1
            print(("  %s along corridor: got %s then %s, want 1 throughout")
                :format(style, tostring(a2), tostring(a3)))
        end
        CheckSelection(style .. " along corridor (child selected)", view, btn, true,
            a3, c1.cells[1].x, c1.cells[1].y, c1.base + 1)
    end

    print(("exclusive arming / true-shape regions              %5d wrong%s"):format(
        fails, fails > 0 and "  <-- FAIL" or ""))
    bad = bad + fails
    p.layout, p.gridNestStyle = "ARC", "PERIMETER"
end

----------------------------------------------------------------------------
--  Cycle guard
----------------------------------------------------------------------------
do
    local fails = 0
    local function Check(what, got, want)
        if got ~= want then
            fails = fails + 1
            print(("  %s: got %s want %s"):format(what, tostring(got), tostring(want)))
        end
    end

    p.paletteCount = 4
    for i = 1, 4 do Palette(i).slots = {} end
    Check("a palette inside itself", ns.CanNest(1, 1), false)
    Check("a fresh palette", ns.CanNest(1, 2), true)

    -- 2 holds 3: nesting 2 inside 1 is fine, nesting 1 inside 3 closes a loop.
    Palette(2).slots = { { kind = "palette", palette = 3 } }
    Check("through one level", ns.CanNest(1, 2), true)
    Palette(3).slots = { { kind = "palette", palette = 1 } }
    -- 1 -> 2 -> 3 -> 1 would close the loop.
    Check("two-step loop", ns.CanNest(1, 2), false)
    -- 3 already holds 1, and 1 holds nothing, so 3 -> 1 closes nothing: a
    -- duplicate is not a cycle, and refusing it would be wrong.
    Check("duplicate is not a loop", ns.CanNest(3, 1), true)
    -- The direct case: 1 holds 2, so 2 may not hold 1.
    Palette(1).slots = { { kind = "palette", palette = 2 } }
    Check("direct loop", ns.CanNest(2, 1), false)
    Palette(1).slots = {}

    -- Data that is ALREADY cyclic must not hang the walk.
    Palette(4).slots = { { kind = "palette", palette = 4 } }
    Check("walking existing cycle", ns.CanNest(1, 4), true)

    print(("cycle guard                                       %5d wrong%s"):format(
        fails, fails > 0 and "  <-- FAIL" or ""))
    bad = bad + fails
end

----------------------------------------------------------------------------
--  Real gates: everything above drives StepArmed, a geometric stand-in for
--  what the file's own comments say EnsureGates/EnterSnippet/LeaveSnippet
--  do. This section instead executes those THREE THINGS -- the real
--  compiled snippet bodies, wrapped exactly as SecureHandlers.lua wraps
--  them, on real frame handles with real anchored rects and real frame
--  levels. SecureHandlerWrapScript (see near the top of this file) and the
--  frame stub's SetFrameLevel/SetPoint/ClearAllPoints family are what make
--  that possible; FireOnEnter/FireOnLeave there are Wrapped_OnEnter/
--  Wrapped_OnLeave, "_wrapentered" included.
--
--  A cursor PATH is a list of points. MoveCursor re-evaluates topmost focus
--  after every one of them -- exclusive, topmost SHOWN motion-enabled frame
--  wins, pgates (level 20) over rgates (level 10) -- and fires the losing
--  frame's OnLeave before the gaining frame's OnEnter, exactly the order the
--  task's own focus rules describe. Nothing here consults view.claims for
--  what eapArmed OUGHT to be; it only reads what the button says it IS.
----------------------------------------------------------------------------
local function GateFrames(index)
    local list = {}
    for k = 1, ns.MAX_SLOTS do
        local pg = byName["EUIActionPaletteButton" .. index .. "PGate" .. k]
        if pg then list[#list + 1] = pg end
        for r = 1, ns.REGION_MAX do
            local rg = byName["EUIActionPaletteButton" .. index .. "RGate" .. k .. "_" .. r]
            if rg then list[#list + 1] = rg end
        end
    end
    return list
end

local function TopmostAt(frames, x, y)
    local best, bestLevel
    for _, f in ipairs(frames) do
        if f._shown and f._motion and f._positioned
           and x >= f._px and x <= f._px + f._w
           and y >= f._py and y <= f._py + f._h then
            local lvl = f._level or 0
            if not best or lvl > bestLevel then best, bestLevel = f, lvl end
        end
    end
    return best
end

-- One mover per open palette: it owns "who has focus right now", which is
-- state that belongs to the whole hold, not to any one sample.
local function NewMover(index)
    local frames = GateFrames(index)
    local focus
    return function(x, y)
        CURSOR.x, CURSOR.y = x, y
        local top = TopmostAt(frames, x, y)
        if top ~= focus then
            if focus then FireOnLeave(focus, true) end
            focus = top
            if focus then FireOnEnter(focus, true) end
        end
        return focus
    end
end

do
    local fails, offline = 0, {}

    local function OpenAt(index, x, y)
        local btn = byName["EUIActionPaletteButton" .. index]
        btn:SetFrameRef("ui", UIParent)
        CURSOR.x, CURSOR.y = x, y
        snippet(btn, "LeftButton", true)
        return btn, NewMover(index)
    end

    local function ReleaseAt(btn, mover, x, y)
        mover(x, y)
        snippet(btn, "LeftButton", false)
        local why = btn:GetAttribute("eapWhy")
        local got = (why ~= "deadzone" and why ~= "outofreach"
                     and why ~= "noidx" and why ~= "unmoved")
                    and btn:GetAttribute("eapIdx") or nil
        return got, why
    end

    -- An opening offset, diagonal from the palette's centre, that lands on
    -- NO claim's parent cell. The checks that walk a cursor onto a claim are
    -- about what the walk does, and a press that already stands on a claim's
    -- entry now arms it there and then (the press branch's geometric
    -- pre-arm) -- which would answer the question before the walk started,
    -- and in one config here really did: a 3x3 grid whose middle column
    -- nests puts a claim's own cell over the old fixed offset of 20,20.
    -- Check 5 below is where the pre-arm is under test on purpose.
    local function ClearOpen(view)
        for off = 20, 4000, 7 do
            local clear = true
            for _, c in ipairs(view.claims or {}) do
                local b = c.parentBox
                if b and math.abs(off - b.x) <= b.hw
                     and math.abs(off - b.y) <= b.hh then
                    clear = false
                    break
                end
            end
            if clear then return off end
        end
        error("no opening offset clear of every claim")
    end

    -- Walk a straight line from (x0,y0) to (x1,y1) in a handful of real
    -- motion samples, each one re-evaluating focus -- a diagonal reach
    -- crosses a narrow corridor's own side for real this way, rather than
    -- landing past it in a single StepArmed jump.
    local function Walk(mover, x0, y0, x1, y1, steps)
        for i = 0, steps do
            local t = i / steps
            mover(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
        end
    end

    -- 1. HALO: open, onto the parent, outward onto a child, release -- want
    -- the child. This is the harness's own claims[1], which the crash this
    -- session found (LeaveSnippet handing SecureHandlerWrapScript a stray
    -- second return value as postBody) never actually touches, since it
    -- fires on claim 1's own FIRST region gate; a HALO nest further down a
    -- palette's slot order is where that crash would have mattered, so this
    -- path alone under-tests it -- see check 4 below for that shape instead.
    do
        local view, btn = nil, nil
        Base(9, 4, 8)()
        p.layout, p.gridAutoColumns, p.gridNestStyle = "GRID", true, "HALO"
        ns.Refresh()
        view = ns.CreatePaletteView(UIParent, {})
        view:Layout(1)
        view:GetFrame():SetCenter(960, 540)
        local off = ClearOpen(view)
        view._steered, view._gateX, view._gateY = true, off + 960, off + 540
        local c1 = view.claims[1]
        local mover
        btn, mover = OpenAt(1, off + 960, off + 540)
        mover(c1.parentBox.x + 960, c1.parentBox.y + 540)
        local armedAfterParent = tonumber(btn:GetAttribute("eapArmed"))
        Walk(mover, c1.parentBox.x + 960, c1.parentBox.y + 540,
                    c1.cells[1].x + 960, c1.cells[1].y + 540, 6)
        local got, why = ReleaseAt(btn, mover, c1.cells[1].x + 960, c1.cells[1].y + 540)
        local want = c1.base + 1
        if armedAfterParent ~= 1 or got ~= want then
            fails = fails + 1
            offline[#offline + 1] = ("  HALO onto a child: armed-after-parent=%s got=%s want=%s why=%s")
                :format(tostring(armedAfterParent), tostring(got), tostring(want), tostring(why))
        end
    end

    -- 2. POPOUT, diagonal reach onto a child: open, onto the parent, then a
    -- straight DIAGONAL line toward the nest's own centre rather than along
    -- either axis -- the path the corridor-width fix exists for. Wants the
    -- nest still live at the far end.
    for _, style in ipairs({ "POPOUT", "PERIMETER" }) do
        Base(9, 5, 8)()
        p.layout, p.gridAutoColumns, p.gridNestStyle = "GRID", true, style
        ns.Refresh()
        local view = ns.CreatePaletteView(UIParent, {})
        view:Layout(1)
        view:GetFrame():SetCenter(960, 540)
        local off = ClearOpen(view)
        view._steered, view._gateX, view._gateY = true, off + 960, off + 540
        local c1 = view.claims[1]
        local btn, mover = OpenAt(1, off + 960, off + 540)
        mover(c1.parentBox.x + 960, c1.parentBox.y + 540)
        local armedAfterParent = tonumber(btn:GetAttribute("eapArmed"))
        -- Straight line, parent to child 1's own centre -- diagonal unless
        -- they happen to share an axis, which PerimeterNest/PopoutNest do
        -- not promise and this does not assume.
        Walk(mover, c1.parentBox.x + 960, c1.parentBox.y + 540,
                    c1.cells[1].x + 960, c1.cells[1].y + 540, 10)
        local got, why = ReleaseAt(btn, mover, c1.cells[1].x + 960, c1.cells[1].y + 540)
        local want = c1.base + 1
        if armedAfterParent ~= 1 or got ~= want then
            fails = fails + 1
            offline[#offline + 1] = ("  %s diagonal reach: armed-after-parent=%s got=%s want=%s why=%s")
                :format(style, tostring(armedAfterParent), tostring(got), tostring(want), tostring(why))
        end
    end

    -- 3. Dim clears the same frame it should: arm, then wander onto a PLAIN
    -- neighbour a full pitch away -- clear of every claim's ground -- and
    -- read the live drawing's own idea of what is open, from the SAME
    -- AdvanceGrid call a real frame update would make. No release: this is
    -- about what is drawn while the button is still held.
    do
        Base(9, 4, 8)()
        p.layout, p.gridAutoColumns, p.gridNestStyle = "GRID", true, "HALO"
        ns.Refresh()
        local view = ns.CreatePaletteView(UIParent, {})
        view:Layout(1)
        view:GetFrame():SetCenter(960, 540)
        view._steered = true
        local c1 = view.claims[1]
        local cols, rows = view:GridDims()
        local pitch = view:Pitch()
        local nx, ny = view:GridBase(1, cols, rows, pitch) -- slot 1: clear of claim 1's own ring
        local off = ClearOpen(view)
        local btn, mover = OpenAt(1, off + 960, off + 540)
        view._gateX, view._gateY = off + 960, off + 540
        mover(c1.parentBox.x + 960, c1.parentBox.y + 540)
        local armedAtParent = tonumber(btn:GetAttribute("eapArmed"))
        view:AdvanceGrid()
        local openAtParent = view._openClaim
        Walk(mover, c1.parentBox.x + 960, c1.parentBox.y + 540, nx + 960, ny + 540, 8)
        view:AdvanceGrid()
        local armedAfter = tonumber(btn:GetAttribute("eapArmed"))
        local openAfter = view._openClaim
        if armedAtParent ~= 1 or openAtParent ~= c1 or armedAfter ~= nil or openAfter ~= nil then
            fails = fails + 1
            offline[#offline + 1] = ("  dim clears: armed %s->%s  open %s->%s (want 1->nil, claim->nil)")
                :format(tostring(armedAtParent), tostring(armedAfter),
                        tostring(openAtParent and "claim") or "nil", tostring(openAfter and "claim") or "nil")
        end
        snippet(btn, "LeftButton", false)
    end

    -- 4. Every claim, not only the first: a palette with THREE separate
    -- nested slots. EnsureGates builds every claim's gates in one pass the
    -- first time this palette is ever pushed -- a Lua error partway through
    -- that pass (the crash this session found) would abort it, leaving every
    -- claim after the one it died on with no pgate at all, however far from
    -- angle zero or however many nests came before it. This is the direct
    -- test for that: arm and select from claim 2 and claim 3 in the SAME
    -- palette that already proved claim 1 fine above.
    do
        Base(9, 2, 5)()
        Palette(1).slots[5] = { kind = "palette", palette = 3 }
        Palette(1).slots[8] = { kind = "palette", palette = 4 }
        local c3, c4 = Palette(3), Palette(4)
        c3.slots, c4.slots = {}, {}
        for i = 1, 4 do c3.slots[i] = { kind = "spell", id = 500 + i } end
        for i = 1, 4 do c4.slots[i] = { kind = "spell", id = 600 + i } end
        p.paletteCount = 4
        p.layout, p.gridAutoColumns, p.gridNestStyle = "GRID", true, "PERIMETER"
        ns.Refresh()
        local view = ns.CreatePaletteView(UIParent, {})
        view:Layout(1)
        view:GetFrame():SetCenter(960, 540)
        view._steered = true
        local off = ClearOpen(view)
        for _, claimIdx in ipairs({ 2, 3 }) do
            local c = view.claims[claimIdx]
            local btn, mover = OpenAt(1, off + 960, off + 540)
            view._gateX, view._gateY = off + 960, off + 540
            mover(c.parentBox.x + 960, c.parentBox.y + 540)
            local armed = tonumber(btn:GetAttribute("eapArmed"))
            Walk(mover, c.parentBox.x + 960, c.parentBox.y + 540,
                        c.cells[1].x + 960, c.cells[1].y + 540, 6)
            local got, why = ReleaseAt(btn, mover, c.cells[1].x + 960, c.cells[1].y + 540)
            local want = c.base + 1
            if armed ~= claimIdx or got ~= want then
                fails = fails + 1
                offline[#offline + 1] = ("  claim %d of 3: armed=%s got=%s want=%s why=%s")
                    :format(claimIdx, tostring(armed), tostring(got), tostring(want), tostring(why))
            end
        end
    end

    -- 5. Press-time pre-arm. Cursor mode opens the palette centred on the
    -- pointer, so a 3x3 grid whose MIDDLE slot nests has that claim's own
    -- parent gate placed exactly under the cursor and shown there -- with no
    -- OnEnter ever raised, since the cursor was already inside it. The claim
    -- used to be drawn with dead children for the whole hold. The armed state
    -- is read BEFORE any cursor motion at all, so nothing but the press
    -- itself can account for it, and the trace is read there too: "P1;" and
    -- nothing else.
    do
        Base(9, 5, 6)()
        p.layout, p.gridAutoColumns, p.gridNestStyle = "GRID", true, "POPOUT"
        p.centerMode = "CURSOR"
        ns.Refresh()
        local view = ns.CreatePaletteView(UIParent, {})
        view:Layout(1)
        view:GetFrame():SetCenter(960, 540)
        view._steered, view._gateX, view._gateY = true, 960, 540
        local c1 = view.claims[1]
        local btn, mover = OpenAt(1, 960, 540)
        local armedAtPress = tonumber(btn:GetAttribute("eapArmed"))
        local trace = btn:GetAttribute("eapGTrace")
        -- The other half of arming, which the live view never reads but every
        -- later cursor sample depends on: this claim's region gates are up,
        -- so there is something to fire the leave test when it is left.
        local rg = byName["EUIActionPaletteButton1RGate1_2"]
        local rgUp = rg and rg:IsShown() and rg._positioned
        -- And the payoff: the nest's first child actually fires.
        Walk(mover, 960, 540, c1.cells[1].x + 960, c1.cells[1].y + 540, 8)
        local got, why = ReleaseAt(btn, mover, c1.cells[1].x + 960, c1.cells[1].y + 540)
        local want = c1.base + 1
        if armedAtPress ~= 1 or trace ~= "P1;" or not rgUp or got ~= want then
            fails = fails + 1
            offline[#offline + 1] = ("  press pre-arm: armed=%s trace=%s regions-up=%s got=%s want=%s why=%s")
                :format(tostring(armedAtPress), tostring(trace), tostring(rgUp),
                        tostring(got), tostring(want), tostring(why))
        end
        p.centerMode = "SCREEN"
    end

    -- 6. Disarm-time re-arm. Two claims on adjacent cells: walk onto claim
    -- 1's entry, which arms it through its own gate's OnEnter, then move in
    -- ONE sample onto claim 2's entry. Claim 2's parent gate is dark for as
    -- long as claim 1 is armed, so it raises no OnEnter of its own when the
    -- disarm puts it back up under the cursor -- claim 1's own leave test,
    -- asking geometrically after it re-shows the gates, is the only thing
    -- that can arm claim 2 here. Without it the user has to move off that
    -- entry and back on.
    do
        Base(9, 4, 6)()
        Palette(1).slots[5] = { kind = "palette", palette = 3 }
        local c3 = Palette(3)
        c3.slots = {}
        for i = 1, 6 do c3.slots[i] = { kind = "spell", id = 300 + i } end
        p.paletteCount = 3
        p.layout, p.gridAutoColumns, p.gridNestStyle = "GRID", true, "POPOUT"
        ns.Refresh()
        local view = ns.CreatePaletteView(UIParent, {})
        view:Layout(1)
        view:GetFrame():SetCenter(960, 540)
        view._steered = true
        local c1, c2 = view.claims[1], view.claims[2]
        local off = ClearOpen(view)
        local btn, mover = OpenAt(1, off + 960, off + 540)
        view._gateX, view._gateY = off + 960, off + 540
        mover(c1.parentBox.x + 960, c1.parentBox.y + 540)
        local armed1 = tonumber(btn:GetAttribute("eapArmed"))
        mover(c2.parentBox.x + 960, c2.parentBox.y + 540)
        local armed2 = tonumber(btn:GetAttribute("eapArmed"))
        if armed1 ~= 1 or armed2 ~= 2 then
            fails = fails + 1
            offline[#offline + 1] = ("  leave re-arm: armed %s then %s, want 1 then 2 (trace %s)")
                :format(tostring(armed1), tostring(armed2),
                        tostring(btn:GetAttribute("eapGTrace")))
        end
        snippet(btn, "LeftButton", false)
    end

    -- 7. Overshoot grace. Reaching fast for a small child icon overruns the
    -- nest's own edge, and one sample past it used to disarm the claim and
    -- take the nest off the screen mid-reach. CellChildGeom builds the grace
    -- into the nest RECT, so the gate frames sized from it carry the same
    -- slack the leave test does. Probed either side of it, on the outward
    -- side where the grace covers empty screen: within the grace the claim
    -- is still armed, past the grace the disarm still happens.
    local function TightNest(cells)
        local x0, x1 = cells[1].x - cells[1].hw, cells[1].x + cells[1].hw
        local y0, y1 = cells[1].y - cells[1].hh, cells[1].y + cells[1].hh
        for j = 2, #cells do
            local b = cells[j]
            x0, x1 = math.min(x0, b.x - b.hw), math.max(x1, b.x + b.hw)
            y0, y1 = math.min(y0, b.y - b.hh), math.max(y1, b.y + b.hh)
        end
        return { x = (x0 + x1) * 0.5, y = (y0 + y1) * 0.5,
                 hw = (x1 - x0) * 0.5, hh = (y1 - y0) * 0.5 }
    end

    for _, case in ipairs({
        { label = "popout 3x3", setup = function()
            Base(9, 1, 6)()
            p.layout, p.gridAutoColumns, p.gridNestStyle = "GRID", true, "POPOUT"
        end },
        -- A 1xN strip, the shape the complaint was reported on: its nest is
        -- one small block broken out across the strip, so the reach for it is
        -- short and the overshoot is most of it.
        { label = "strip 1x5", setup = function()
            Base(5, 3, 6)()
            p.layout, p.gridAutoColumns, p.gridColumns = "GRID", false, 5
        end },
    }) do
        case.setup()
        ns.Refresh()
        local view = ns.CreatePaletteView(UIParent, {})
        view:Layout(1)
        view:GetFrame():SetCenter(960, 540)
        view._steered = true
        local c1 = view.claims[1]
        local tight = TightNest(c1.cells)
        -- The grace CellChildGeom is supposed to have applied, worked out
        -- from the same metrics rather than read back off the region: the
        -- probe points have to be the SAME two screen points whether the
        -- region carries the grace or not, or a missing inflation would only
        -- move the probes in with it and prove nothing.
        local m = view:NestMetrics(view:ShownCount())
        local grace = math.max(m.band, 0.75 * m.childPitch)
        local applied = c1.regions[2].hw - tight.hw
        -- The away axis is the one the nest lies OUT along; c.axis is the one
        -- its cells spread along.
        local away, hAway = "y", "hh"
        if c1.axis ~= "X" then away, hAway = "x", "hw" end
        local function Probe(mult)
            local pt = { x = tight.x, y = tight.y }
            pt[away] = tight[away] + c1.sign * (tight[hAway] + grace * mult)
            return pt
        end
        local within, past = Probe(0.5), Probe(1.5)

        local off = ClearOpen(view)
        local btn, mover = OpenAt(1, off + 960, off + 540)
        view._gateX, view._gateY = off + 960, off + 540
        mover(c1.parentBox.x + 960, c1.parentBox.y + 540)
        local armed = tonumber(btn:GetAttribute("eapArmed"))
        Walk(mover, c1.parentBox.x + 960, c1.parentBox.y + 540,
                    tight.x + 960, tight.y + 540, 6)
        mover(within.x + 960, within.y + 540)
        local stillArmed = tonumber(btn:GetAttribute("eapArmed"))
        mover(past.x + 960, past.y + 540)
        local nowClear = tonumber(btn:GetAttribute("eapArmed"))
        if grace <= 1 or math.abs(applied - grace) > 0.01
           or armed ~= 1 or stillArmed ~= 1 or nowClear ~= nil then
            fails = fails + 1
            offline[#offline + 1] = ("  %s grace: grace=%.1f applied=%.1f armed=%s within=%s past=%s (want 1, 1, nil)")
                :format(case.label, grace, applied, tostring(armed),
                        tostring(stillArmed), tostring(nowClear))
        end
        snippet(btn, "LeftButton", false)
    end
    p.gridColumns, p.gridAutoColumns = nil, true

    -- 8. EVERY child of a lane, not just the first, and by a slow deliberate
    -- reach rather than a jump: open, walk onto the parent, then a straight line
    -- of twelve samples to that child's own centre and release there. A run
    -- wrapped around a corner is the case this exists for -- its far ends sit
    -- back beside the parent rather than out in front of it, so the reach for one
    -- of them leaves the parent's cell through an edge no corridor was laid
    -- across, and the claim used to disarm a unit or two short of the run's own
    -- rect. That is not a cancel: the release goes on to fire whichever PLAIN
    -- entry the cursor came to rest over, so the palette silently casts the wrong
    -- spell. Samples matter here -- a two-sample jump steps clean over the gap
    -- and passes.
    for _, case in ipairs({
        { label = "lane corner parent, 8 children", setup = Base(9, 1, 8) },
        { label = "lane corner parent, 6 children", setup = Base(9, 1, 6) },
        { label = "lane edge parent, 6 children",   setup = Base(12, 10, 6) },
        { label = "lane centre parent, 8 children", setup = Base(9, 5, 8) },
    }) do
        case.setup()
        p.layout, p.gridAutoColumns, p.gridNestStyle = "GRID", true, "PERIMETER"
        ns.Refresh()
        local view = ns.CreatePaletteView(UIParent, {})
        view:Layout(1)
        view:GetFrame():SetCenter(960, 540)
        local off = ClearOpen(view)
        view._steered, view._gateX, view._gateY = true, off + 960, off + 540
        local c1 = view.claims[1]
        local unreachable, misfired = {}, {}
        for j = 1, c1.n do
            local btn, mover = OpenAt(1, off + 960, off + 540)
            mover(c1.parentBox.x + 960, c1.parentBox.y + 540)
            local armed = tonumber(btn:GetAttribute("eapArmed"))
            Walk(mover, c1.parentBox.x + 960, c1.parentBox.y + 540,
                        c1.cells[j].x + 960, c1.cells[j].y + 540, 12)
            local heldOn = tonumber(btn:GetAttribute("eapArmed"))
            local got = ReleaseAt(btn, mover, c1.cells[j].x + 960, c1.cells[j].y + 540)
            if armed ~= 1 or heldOn ~= 1 then
                unreachable[#unreachable + 1] = j
            end
            if got ~= c1.base + j then
                misfired[#misfired + 1] = ("%d fired %s"):format(j, tostring(got))
            end
        end
        if #unreachable > 0 or #misfired > 0 then
            fails = fails + 1
            offline[#offline + 1] = ("  %s: reach broke on children [%s]; releases wrong [%s]")
                :format(case.label, table.concat(unreachable, ","),
                        table.concat(misfired, "; "))
        end
    end

    print(("real-gate focus paths                               %5d wrong%s"):format(
        fails, fails > 0 and "  <-- FAIL" or ""))
    for _, line in ipairs(offline) do print(line) end
    bad = bad + fails
    p.layout, p.gridNestStyle = "ARC", "PERIMETER"
end

print(bad == 0 and "\nALL AGREE" or ("\n" .. bad .. " DISAGREEMENTS"))
os.exit(bad == 0 and 0 or 1)
