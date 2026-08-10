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
-- A secure button is built only for a palette that HAS a key, and every sweep
-- reads the pushed attributes off one, so each palette answers a key here. What
-- a palette needs a key FOR is not what this harness measures -- it reads the
-- geometry the push writes, and an unbound palette is never pushed at all.
_G.GetBindingKey    = function(action)
    local n = tostring(action or ""):match("^EUI_RADIAL(%d+)$")
    return n and ("F" .. n) or nil
end
_G.InCombatLockdown = function() return false end
_G.GetTime          = function() return 0 end
-- ns.Refresh coalesces its push behind a timer, so a sweep that pushed and
-- then read the attributes back in the same breath would be reading the
-- PREVIOUS push. Fired inline, which collapses the coalescing to nothing and
-- leaves Refresh exactly as synchronous as it has to be here. There is no
-- frame loop to drive a real one from anyway.
_G.C_Timer = { After = function(_, fn) fn() end }
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
_G.UnitClass  = function() return "Mage", "MAGE", 8 end
_G.GetMacroInfo = function() return nil end
-- The usability and count getters answer "nothing to say" rather than a state:
-- what they return decides a tint and a corner number, neither of which this
-- harness compares. What matters is that they EXIST, so PaintCell takes the
-- same path it does in game.
_G.C_Spell = { GetSpellInfo = function(id)
                   return { name = "Spell" .. tostring(id), iconID = 1 } end,
               GetSpellCooldownDuration = function() return nil end,
               GetSpellCharges = function() return nil end,
               IsSpellUsable = function() return true end,
               IsSpellInRange = function() return nil end }
_G.C_Item = { GetItemInfoInstant = function() return nil end,
              GetItemInfo = function() return nil end,
              GetItemCount = function() return 0 end,
              ItemHasRange = function() return false end,
              IsItemInRange = function() return nil end,
              IsUsableItem = function() return true end,
              GetItemCooldown = function() return 0, 0, 0 end }
_G.C_SpecializationInfo = {
    GetNumSpecializationsForClassID = function() return 0 end,
    GetSpecializationInfo = function() return nil end,
    SetSpecialization = function() end,
}
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
-- The module ships switched OFF and OnEnable does nothing at all until it is
-- switched on, so this is part of the setup rather than part of the test.
ns.Profile().enabled = true
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

-- LeaveSnippet's own ANGULAR ground test -- c.ground's beam and wedge, NOT
-- the release's per-ring resolution: the ground a claim stays armed on has to
-- include the sides of its parent's icon and the entry ring's own radius,
-- which answer to no ring at all. Worked in radians here since this is plain
-- Lua rather than the sandboxed snippet; ChildGeom builds c.ground in radians
-- and PushPalette converts only when writing the eapC* attributes.
local function InWedge(c, dx, dy)
    if InBox(c.parentBox, dx, dy) then return true end
    local g = c.ground
    if not g then return false end
    local u = dx * g.ax + dy * g.ay
    if u < g.lo then return false end
    local v = math.abs(dx * g.ay - dy * g.ax)
    if v <= g.beam + u * g.slope then return true end
    if (dx * dx + dy * dy) ^ 0.5 < g.edge then return false end
    local ad = (math.atan2(dx, dy) - c.angle) % (2 * math.pi)
    if ad > math.pi then ad = 2 * math.pi - ad end
    return ad <= g.half
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

-- The retired POPOUT style: a stored profile may still carry the value, and it
-- has to read as PERIMETER everywhere -- NestMetrics folds it there, and this
-- sweep holds the fold to the same agreement as a lane asked for by name.
bad = bad + SweepCells("grid legacy popout value, reads as lane", function()
    Base(9, 1, 6)()
    p.layout, p.gridAutoColumns = "GRID", true
    p.gridNestStyle = "POPOUT"
end, step)

-- A nested palette's full MAX_SLOTS through a lane, which seats them whole --
-- the cap that stops at MAX_CHILDREN is for the nests bounded by their
-- parent's own region. See NestChildCap.
bad = bad + SweepCells("grid lane, nested palette of twelve", function()
    Base(9, 5, ns.MAX_SLOTS or 12)()
    p.layout, p.gridAutoColumns = "GRID", true
end, step)

bad = bad + SweepCells("grid lane, side flipped", function()
    Base(9, 5, 4)()
    p.layout, p.gridAutoColumns = "GRID", true
    p.nestSide = "NEGATIVE"
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

-- Two nests whose parents are neighbours, with eight children each: their two
-- runs lie over each other along the lane for most of their length, which is
-- allowed -- only one of them is ever drawn and only one is ever armed. What
-- this asks is that the two sides still agree about which cell is where when
-- they do. Small children on purpose, so both runs are long. Whether each run
-- gets its full length, and whether it stays in ONE row, is the lane placement
-- section's question further down.
bad = bad + SweepCells("grid lane, two nests share the lane", function()
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

-- A nested palette's full MAX_SLOTS: the strip's nest is one row that spreads
-- as wide as it needs to, so it seats them whole -- see NestChildCap.
bad = bad + SweepStrip("scroll fan vertical, nest of twelve", function()
    Base(5, 2, ns.MAX_SLOTS or 12)()
    p.layout, p.fanInput, p.fanOrientation = "FAN", "SCROLL", "VERTICAL"
end, 2, step)

bad = bad + SweepStrip("scroll fan, side flipped", function()
    Base(5, 2, 4)()
    p.layout, p.fanInput, p.fanOrientation = "FAN", "SCROLL", "HORIZONTAL"
    p.nestSide = "NEGATIVE"
end, 2, step)

----------------------------------------------------------------------------
--  Appearance is PER PALETTE: a palette's own override is what both the
--  drawing and the push must read, not the profile's value. These two sweeps
--  set the profile to one layout and the palette to the other, so a read that
--  went to the profile on either side would draw one layout and fire from the
--  geometry of a completely different one -- which is not an off-by-one the
--  sweeps above could ever produce, and would be silent everywhere else.
----------------------------------------------------------------------------
bad = bad + Sweep("override: profile FAN, palette ARC", function()
    Base(5, 3, 5)()
    p.layout, p.fanInput = "FAN", "CURSOR"
    Palette(1).appearance = { layout = "ARC", arcSpan = 360 }
    p.arcChildOverflow = "NONE"
end, step)
Palette(1).appearance = nil

bad = bad + SweepCells("override: profile ARC, palette GRID", function()
    Base(6, 2, 4)()
    p.layout = "ARC"
    Palette(1).appearance = { layout = "GRID", gridAutoColumns = false,
                              gridColumns = 3 }
end, step)
Palette(1).appearance = nil

-- Back to the arc for the checks below.
p.layout, p.fanInput, p.nestSide = "ARC", "SCROLL", "POSITIVE"
p.gridNestStyle = "PERIMETER"

----------------------------------------------------------------------------
--  PushPalette measures through the LIVE view, which is laid out for whatever
--  was drawn last -- palette 1 here, and never palette 2. So every number it
--  writes onto palette 2's button has to come from palette 2's appearance
--  while the view still holds palette 1's, which is the whole job of
--  liveView.appIndex and of PushPalette reading PA(index) rather than P().
--
--  This is the one place either of those can be caught. The sweeps only ever
--  drive palette 1, where the view's own index already equals the pushed one
--  and both are no-ops.
----------------------------------------------------------------------------
do
    local a = Palette(1)
    a.slots = {}
    for i = 1, 4 do a.slots[i] = { kind = "spell", id = 400 + i } end
    -- An OPEN arc, so its own step is nothing like the full circle palette 2
    -- inherits. eapStepDeg is pushed from the view for every layout, grid
    -- included, so this is what catches a push that measured through the view
    -- while the view was still holding the other palette.
    a.appearance = { layout = "ARC", arcSpan = 120, arcRotation = 0, scale = 1,
                     centerMode = "SCREEN", posX = 0, posY = 0 }
    local b = Palette(2)
    b.slots = {}
    for i = 1, 4 do b.slots[i] = { kind = "spell", id = 500 + i } end
    -- Four columns where auto-columns would pick two, so the block is one row
    -- rather than a square. Palette 1 does not override the column settings,
    -- so a view left on palette 1 answers the auto shape instead.
    b.appearance = { layout = "GRID", gridAutoColumns = false, gridColumns = 4,
                     scale = 1.5, centerMode = "SCREEN", posX = 120, posY = -80,
                     fanGap = 20 }
    -- The profile says something different from BOTH of them, so a read that
    -- fell back to it is a wrong answer rather than an accidentally right one.
    p.paletteCount = 2
    p.layout, p.scale, p.centerMode = "FAN", 0.5, "CURSOR"
    p.posX, p.posY, p.fanGap = -999, -999, 3
    p.arcSpan, p.arcRotation, p.gridAutoColumns = 360, 0, true
    ns.Refresh()

    local wrong = 0
    local function Want(btn, key, want)
        local got = btn:GetAttribute(key)
        if got ~= want then
            wrong = wrong + 1
            print(("  %s %s: pushed=%s wanted=%s"):format(
                btn:GetName(), key, tostring(got), tostring(want)))
        end
    end

    local b1 = byName["EUIActionPaletteButton1"]
    local b2 = byName["EUIActionPaletteButton2"]
    assert(b1 and b2, "both palettes need a secure button")

    Want(b1, "eapMode",  "ANGULAR")
    -- An open arc of four entries divides by count MINUS ONE; a full circle
    -- divides by the count. 120/3 against 360/4.
    Want(b1, "eapStepDeg", 40)
    Want(b1, "eapFull",    false)
    Want(b2, "eapStepDeg", 90)
    Want(b2, "eapFull",    true)
    Want(b1, "eapScale", 1)
    Want(b1, "eapPosX",  0)
    Want(b2, "eapMode",  "POINTER")
    Want(b2, "eapScale", 1.5)
    Want(b2, "eapFixed", true)
    Want(b2, "eapPosX",  120)
    Want(b2, "eapPosY",  -80)

    -- And the cell centres, which are the numbers the release actually
    -- resolves against: a push that measured through palette 1's arc would
    -- write no eapBX at all, and one that measured a grid at the profile's own
    -- gap would write the right shape at the wrong pitch.
    local view = ns.CreatePaletteView(UIParent, {})
    view:Layout(2)
    local cols, rows = view:GridDims(4)
    if cols ~= 4 or rows ~= 1 then
        wrong = wrong + 1
        print(("  palette 2 draws %dx%d, wanted 4x1"):format(cols, rows))
    end
    local _, iconSize = view:Geom()
    local pitch = iconSize + 20
    for i = 1, 4 do
        local bx, by = view:GridBase(i, cols, rows, pitch, 4)
        Want(b2, "eapBX" .. i, bx)
        Want(b2, "eapBY" .. i, by)
    end
    Want(b2, "eapPitch", pitch)

    print(("push reads the pushed palette's own appearance   %5d wrong%s"):format(
        wrong, wrong > 0 and "  <-- FAIL" or ""))
    bad = bad + wrong

    Palette(1).appearance, Palette(2).appearance = nil, nil
    p.layout, p.scale, p.centerMode = "ARC", 1, "SCREEN"
    p.posX, p.posY, p.fanGap = 0, 0, nil
    p.gridAutoColumns = nil
    ns.Refresh()
end

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
        for ci, c in ipairs(view.claims or {}) do
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
                cells[#cells + 1] = { x = x, y = y, claim = ci,
                                      what = "nest of " .. c.parent .. " #" .. j }
            end
        end

        -- Two icons may not sit closer than the smaller of them is wide.
        --
        -- Two DIFFERENT claims' children are exempt: exactly one nest is drawn
        -- and exactly one is armed at any moment, so two runs sharing ground is
        -- not a crowd -- the other one is not on the screen to crowd anything.
        -- Two nests near each other used to divide the lane between them, which
        -- kept them apart here and cost them their runs: neighbouring claims got
        -- room for one cell each and stacked the rest outward into rows.
        local floorGap = view.claims and view.claims[1]
            and math.min(pitch, view.claims[1].icon) or pitch
        local worst, worstPair = math.huge, nil
        for i = 1, #cells do
            for j = i + 1, #cells do
                local sameClaim = cells[i].claim == cells[j].claim
                if sameClaim or not cells[i].claim or not cells[j].claim then
                    local dx = cells[i].x - cells[j].x
                    local dy = cells[i].y - cells[j].y
                    local d = (dx * dx + dy * dy) ^ 0.5
                    if d < worst then
                        worst, worstPair = d, cells[i].what .. " / " .. cells[j].what
                    end
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

    -- 4. Two nests on the SAME lane, and neighbours at that: each still gets the
    -- whole run it asked for, laid along the lane in one row. The lane used to be
    -- divided up between the claims on it -- out to the midpoint with the nearest
    -- other one -- which left two claims in adjacent cells with three quarters of
    -- a pitch each: room for a single cell per row, so eight children came out as
    -- eight rows stacked outward from the block. Nothing needed the division:
    -- only one nest is ever drawn and only one is ever armed, so two runs may lie
    -- over each other on the lane without either becoming ambiguous.
    --
    -- Full runs are the whole point of the check, so it asks for MAX_CHILDREN of
    -- them on both claims, and asks each claim for as many cells along the lane
    -- as it has children -- which is the number the old rule could not deliver.
    for _, case in ipairs({
        { label = "two nests side by side on the lane", at = { 7, 8 } },
        { label = "two nests, a corner and its neighbour", at = { 1, 2 } },
        { label = "two nests facing each other", at = { 2, 8 } },
    }) do
        local label = case.label
        local view, m, centres = Lane(function()
            Base(9, case.at[1], ns.MAX_CHILDREN)()
            Palette(1).slots[case.at[2]] = { kind = "palette", palette = 3 }
            local c = Palette(3)
            c.slots = {}
            for i = 1, ns.MAX_CHILDREN do c.slots[i] = { kind = "spell", id = 300 + i } end
            p.paletteCount = 3
        end)
        SingleRow(label, view, m)
        Snug(label, view, m)
        ClearOfCentres(label, view, centres)
        for _, c in ipairs(view.claims) do
            -- How far the run REACHES along the lane, side by side: a run that
            -- stacked outward into rows holds the same cells at a handful of
            -- along positions, so its reach collapses to a couple of pitches
            -- however many children it has. Measured a side at a time, since a
            -- run wrapped round a corner travels on two axes. The allowance is
            -- for the corners themselves: a turn advances the along coordinate
            -- less than it advances the perimeter the cells were spaced on.
            local along = 0
            for _, g in ipairs(c.groups) do
                local lo, hi = math.huge, -math.huge
                for _, b in ipairs(g.cells) do
                    local v = (g.axis == "X") and b.x or b.y
                    local h = (g.axis == "X") and b.hw or b.hh
                    lo, hi = math.min(lo, v - h), math.max(hi, v + h)
                end
                along = along + (hi - lo)
            end
            if along < c.n * m.childPitch * 0.85 then
                Bad(label, ("the claim on %d runs %.1f along the lane, %d children want %.1f")
                    :format(c.parent, along, c.n, c.n * m.childPitch))
            end
            if #c.regions > ns.REGION_MAX then
                Bad(label, ("the claim on %d wants %d regions, only %d gates to put them in")
                    :format(c.parent, #c.regions, ns.REGION_MAX))
            end
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
--  Icon overlap. The crowding check further up measures CENTRES against a
--  floor, which is the right question for two round-ish things but not for
--  what actually gets drawn: a child is a SQUARE of c.icon on a side, and two
--  squares clear each other only when one axis alone separates them by a whole
--  icon. Around a lane's rounded corner the two readings part company -- the
--  straight-line distance holds up while the axis-by-axis one collapses, so a
--  pair that passes the crowding floor still overlaps on screen by a quarter
--  of an icon.
--
--  Swept over block shapes, over EVERY parent position in each of them, over
--  child counts and over nest scales, since which pairs land either side of a
--  corner depends on all four. Only the block styles: an arc nest is polar and
--  its children are not rows of squares at all, which is the crowding check's
--  business rather than this one's.
----------------------------------------------------------------------------
do
    local fails = 0
    local worst, worstWhere = math.huge, "nothing"

    local function Icons(label, view)
        for _, c in ipairs(view.claims or {}) do
            for a = 1, (c.cells and c.n or 0) - 1 do
                for b = a + 1, c.n do
                    local pa, pb = c.cells[a], c.cells[b]
                    local sep = math.max(math.abs(pa.x - pb.x),
                                         math.abs(pa.y - pb.y))
                    local margin = sep - c.icon
                    if margin < worst then
                        worst, worstWhere = margin,
                            ("%s, children %d and %d of the claim on %d")
                                :format(label, a, b, c.parent)
                    end
                    -- Exact touching is allowed; the tolerance is for the
                    -- float noise a turn's sin/cos leaves behind.
                    if margin < -0.01 then
                        fails = fails + 1
                        print(("  %s: children %d and %d of the claim on %d overlap by %.1f of a %.1f icon")
                            :format(label, a, b, c.parent, -margin, c.icon))
                    end
                end
            end
        end
    end

    for _, style in ipairs({ "PERIMETER", "HALO" }) do
        for _, shape in ipairs({ { n = 9 }, { n = 12 }, { n = 6 },
                                 { n = 5, cols = 5 }, { n = 4, cols = 1 } }) do
            -- MAX_SLOTS children only reach a lane whole -- a halo's cap trims
            -- them back to MAX_CHILDREN (see NestChildCap), so that pass runs
            -- the halo at its own full house rather than not at all.
            for _, nChild in ipairs({ 2, 5, ns.MAX_CHILDREN, ns.MAX_SLOTS }) do
                for _, scale in ipairs({ 0.4, 0.6, 0.8, 1.0 }) do
                    for at = 1, shape.n do
                        Base(shape.n, at, nChild)()
                        p.layout, p.gridNestStyle = "GRID", style
                        p.gridAutoColumns = (shape.cols == nil)
                        p.gridColumns = shape.cols
                        p.nestScale = scale
                        ns.Refresh()
                        local view = ns.CreatePaletteView(UIParent, {})
                        view:Layout(1)
                        Icons(("%s %d slots%s, nest of %d on %d at %.1f"):format(
                            style, shape.n,
                            shape.cols and (" in " .. shape.cols .. " columns") or "",
                            nChild, at, scale), view)
                    end
                end
            end
        end
    end
    p.gridColumns, p.nestScale = nil, nil

    print(("no two icons of one nest overlap                  %5d wrong%s"):format(
        fails, fails > 0 and "  <-- FAIL" or ""))
    print(("  tightest pair, icon widths clear:               %.1f  (%s)")
        :format(worst, worstWhere))
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

    -- 3. True-shape regions: a corner parent, so its nest breaks out through
    -- the block's own edge with no interior cell in the way -- the clean case
    -- for telling "on the claim's ground" apart from "elsewhere in the
    -- block". Wandering onto a plain entry on the far side of the block
    -- disarms; wandering out across the gap to a child keeps the nest live
    -- the whole way. POPOUT is the retired style value a stored profile may
    -- still carry -- it reads as PERIMETER now, and this holds its arming to
    -- the same answers as the lane asked for by name.
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
        -- region: the lane folds the way back to the parent into the run's
        -- own rect (see RunReach), and the reach is what has to answer.
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
        -- The gate transcript several checks below read is kept only while the
        -- button carries this flag -- "/euiap gates" is what raises it in game,
        -- and the appends are skipped entirely without it.
        btn:SetAttribute("eapGDebug", 1)
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

    -- Does a straight reach from claim k's parent to (x1,y1) leave the claim's
    -- own coverage over ANOTHER claim's entry? Other claims' cells are taken out
    -- of a claim's regions on purpose (see ParentHoles), so a reach across one of
    -- those holes is a HANDOFF: the leave test answers "outside", the claim
    -- disarms, and the claim the cursor has arrived at arms in its place. That is
    -- the swap the whole carve exists for, so a walk across one has to be held to
    -- a different promise than a walk that stays covered.
    --
    -- Asked of the claim's own rects rather than of the grid: not every
    -- neighbouring claim's cell IS a hole -- one standing between a parent and its
    -- own run keeps the nest reachable instead (see BlocksReach) -- and a check
    -- that assumed otherwise would demand a handoff where the module rightly
    -- refuses one. Sampled rather than solved, since samples are what the gates
    -- see.
    local function HandsOffAlong(view, k, x1, y1)
        local c = view.claims[k]
        local x0, y0 = c.parentBox.x, c.parentBox.y
        for i = 0, 48 do
            local t = i / 48
            local x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            if not ClaimContains(view, c, x, y) then
                for j, o in ipairs(view.claims) do
                    if j ~= k and InBox(o.parentBox, x, y) then return j end
                end
            end
        end
        return nil
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

    -- 2. Diagonal reach onto a child from a MIDDLE parent: open, onto the
    -- parent, then a straight diagonal line toward the nest's own centre
    -- rather than along either axis -- the reach RunReach's convex rect
    -- exists for. Wants the nest still live at the far end. POPOUT is the
    -- retired style value, held to the same answers as the lane.
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
        -- they happen to share an axis, which PerimeterNest does not promise
        -- and this does not assume.
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
            -- A child this claim can be reached WITHOUT crossing another
            -- claim's entry: three claims on one block leave some of each
            -- run's children behind a neighbour's cell, and reaching across
            -- one of those hands the claim over by design. What is under test
            -- here is that claim 2 and claim 3 have working gates at all, so
            -- it asks the question where the answer is not a handoff.
            local target
            for j = 1, c.n do
                if not HandsOffAlong(view, claimIdx,
                                          c.cells[j].x, c.cells[j].y) then
                    target = j
                    break
                end
            end
            local btn, mover = OpenAt(1, off + 960, off + 540)
            view._gateX, view._gateY = off + 960, off + 540
            mover(c.parentBox.x + 960, c.parentBox.y + 540)
            local armed = tonumber(btn:GetAttribute("eapArmed"))
            local cell = c.cells[target or 1]
            Walk(mover, c.parentBox.x + 960, c.parentBox.y + 540,
                        cell.x + 960, cell.y + 540, 6)
            local got, why = ReleaseAt(btn, mover, cell.x + 960, cell.y + 540)
            local want = c.base + (target or 1)
            if armed ~= claimIdx or not target or got ~= want then
                fails = fails + 1
                offline[#offline + 1] = ("  claim %d of 3: armed=%s target=%s got=%s want=%s why=%s")
                    :format(claimIdx, tostring(armed), tostring(target),
                            tostring(got), tostring(want), tostring(why))
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
        -- A bottom-edge parent with a short run, so the nest is one group on
        -- one side and the outward edge under the probe is the run's own.
        { label = "lane 3x3", setup = function()
            Base(9, 8, 3)()
            p.layout, p.gridAutoColumns = "GRID", true
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
        -- move the probes in with it and prove nothing. c.standoff is the
        -- lane's own answer, exactly as CellChildGeom reads it.
        local m = view:NestMetrics(view:ShownCount())
        local grace = math.max(c1.standoff or m.band, 0.75 * m.childPitch)
        -- The away axis is the one the nest lies OUT along; c.axis is the one
        -- its cells spread along.
        local away, hAway = "y", "hh"
        if c1.axis ~= "X" then away, hAway = "x", "hw" end
        -- Measured at the OUTWARD edge, which every region shape moves by
        -- exactly the grace: a corridor style's rect is the nest box itself,
        -- and a lane's folds the parent cell in on the INWARD side (see
        -- RunReach), so a half-extent difference would read the fold as grace.
        local r2 = c1.regions[2]
        local applied
        if c1.sign > 0 then
            applied = (r2[away] + r2[hAway]) - (tight[away] + tight[hAway])
        else
            applied = (tight[away] - tight[hAway]) - (r2[away] - r2[hAway])
        end
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
    --
    -- Where another claim's entry stands in the way the promise changes rather
    -- than lapses: that cell is a hole in this claim's coverage on purpose, so
    -- the reach across it must HAND OVER -- disarm this claim and arm the one the
    -- cursor is on -- and the check holds it to that instead. Every case here has
    -- at least one child of each kind, which is what makes both halves real.
    for _, case in ipairs({
        { label = "lane corner parent, 8 children", setup = Base(9, 1, 8) },
        { label = "lane corner parent, 6 children", setup = Base(9, 1, 6) },
        { label = "lane edge parent, 6 children",   setup = Base(12, 10, 6) },
        { label = "lane centre parent, 8 children", setup = Base(9, 5, 8) },
        -- Two claims on adjacent cells of the bottom row, both with a full run
        -- along the same lane. The children out past the neighbour's own cell are
        -- the handoff half; the ones over the parent's own end of the lane are
        -- the half that must survive the whole reach, neighbour or no neighbour.
        { label = "lane, two adjacent claims", handoff = true, setup = function()
            Base(9, 7, 8)()
            Palette(1).slots[8] = { kind = "palette", palette = 3 }
            local c = Palette(3)
            c.slots = {}
            for i = 1, 8 do c.slots[i] = { kind = "spell", id = 300 + i } end
            p.paletteCount = 3
        end },
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
        local unreachable, misfired, handedOff = {}, {}, {}
        for j = 1, c1.n do
            local across = HandsOffAlong(view, 1, c1.cells[j].x, c1.cells[j].y)
            local btn, mover = OpenAt(1, off + 960, off + 540)
            mover(c1.parentBox.x + 960, c1.parentBox.y + 540)
            local armed = tonumber(btn:GetAttribute("eapArmed"))
            Walk(mover, c1.parentBox.x + 960, c1.parentBox.y + 540,
                        c1.cells[j].x + 960, c1.cells[j].y + 540, 12)
            local heldOn = tonumber(btn:GetAttribute("eapArmed"))
            local got = ReleaseAt(btn, mover, c1.cells[j].x + 960, c1.cells[j].y + 540)
            if armed ~= 1 then
                unreachable[#unreachable + 1] = j
            elseif across then
                -- Handed over to SOME other claim, not necessarily the one the
                -- line crossed: past the hole the cursor goes on travelling, and
                -- whichever claim it ends on is the one that answers. What must
                -- not happen is this claim staying armed over ground it does not
                -- hold.
                if heldOn == 1 then
                    handedOff[#handedOff + 1] = ("%d stayed armed across claim %d")
                        :format(j, across)
                end
            else
                if heldOn ~= 1 then unreachable[#unreachable + 1] = j end
                if got ~= c1.base + j then
                    misfired[#misfired + 1] = ("%d fired %s"):format(j, tostring(got))
                end
            end
        end
        -- Vacuous either way is a failure of the case, not a pass: a config where
        -- nothing crosses a neighbour proves nothing about the handoff, and one
        -- where everything does proves nothing about the reach.
        local crossings = 0
        for j = 1, c1.n do
            if HandsOffAlong(view, 1, c1.cells[j].x, c1.cells[j].y) then
                crossings = crossings + 1
            end
        end
        local shape = (case.handoff and (crossings == 0 or crossings == c1.n))
            and ("only %d of %d children cross a neighbour"):format(crossings, c1.n)
            or (not case.handoff and crossings > 0)
            and ("%d children cross a neighbour in a one-claim config"):format(crossings)
            or nil
        if #unreachable > 0 or #misfired > 0 or #handedOff > 0 or shape then
            fails = fails + 1
            offline[#offline + 1] = ("  %s: reach broke on children [%s]; releases wrong [%s]; %s%s")
                :format(case.label, table.concat(unreachable, ","),
                        table.concat(misfired, "; "),
                        table.concat(handedOff, "; "), shape and ("; " .. shape) or "")
        end
    end

    -- 9. Swapping between two claims WITHOUT leaving the row. A lane's region
    -- sweeps its parent's own row (see RunReach), so while claim 1 is armed its
    -- coverage used to stand over claim 2's entry as well -- and claim 2's own
    -- parent gate is dark for as long as claim 1 is armed. Gliding from one entry
    -- straight onto the other therefore left no gate of claim 1's, fired no
    -- OnLeave, disarmed nothing, and armed nothing: the user had to leave the
    -- whole row and come back before the second nest would open. Claim 2's cell
    -- is now a hole in claim 1's coverage, so the glide crosses a real boundary.
    -- The trace is read too, because "armed 2" alone would also be satisfied by a
    -- press-time pre-arm or by never having armed 1 in the first place: L1:out is
    -- claim 1's own leave test answering, and R2 is its re-arm handing over.
    for _, style in ipairs({ "PERIMETER", "POPOUT", "HALO" }) do
        Base(9, 7, 8)()
        Palette(1).slots[8] = { kind = "palette", palette = 3 }
        local c3 = Palette(3)
        c3.slots = {}
        for i = 1, 8 do c3.slots[i] = { kind = "spell", id = 300 + i } end
        p.paletteCount = 3
        p.layout, p.gridAutoColumns, p.gridNestStyle = "GRID", true, style
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
        -- A glide, not a jump: the samples between the two entries are where the
        -- boundary has to be, and a two-sample hop over it would pass either way.
        Walk(mover, c1.parentBox.x + 960, c1.parentBox.y + 540,
                    c2.parentBox.x + 960, c2.parentBox.y + 540, 10)
        local armed2 = tonumber(btn:GetAttribute("eapArmed"))
        local trace = btn:GetAttribute("eapGTrace") or ""
        -- And the second nest is really open: its own first child fires from
        -- where the swap left the cursor.
        Walk(mover, c2.parentBox.x + 960, c2.parentBox.y + 540,
                    c2.cells[1].x + 960, c2.cells[1].y + 540, 8)
        local got, why = ReleaseAt(btn, mover, c2.cells[1].x + 960, c2.cells[1].y + 540)
        if armed1 ~= 1 or armed2 ~= 2 or got ~= c2.base + 1
           or not trace:find("L1:out;", 1, true) or not trace:find("R2;", 1, true) then
            fails = fails + 1
            offline[#offline + 1] = ("  %s swap along the row: armed %s->%s trace=%s got=%s want=%s why=%s")
                :format(style, tostring(armed1), tostring(armed2), trace,
                        tostring(got), tostring(c2.base + 1), tostring(why))
        end
    end

    -- 10. THE ARC, through the same real gates. Every check above it is a
    -- block layout, and the arc's gate path had no offline check at all -- so
    -- the one thing no block layout has went untested: the polar ground test
    -- LeaveSnippet makes for an ANGULAR claim. A rect layout's regions cover
    -- their own children by construction, but an arc's do not, and the ground
    -- between a parent's icon and its rings used to belong to nothing at all:
    -- the pgate's OnLeave fired a few units into every reach for a child, the
    -- test answered "outside", the claim disarmed, and the nest went dim with
    -- dead children for the rest of the hold. In game that reads as "the
    -- nested entries are drawn but cannot be picked" -- the release goes on to
    -- fire whichever plain entry the angle lands on.
    --
    -- The walks are SAMPLED, twelve at a time: the ground that used to be
    -- missing is a band a few units wide, and a two-sample jump steps clean
    -- over it.
    local function ArcClaimAngleOffsets(view, c)
        local mx = 0
        for j = 1, c.n do
            local _, a = view:ChildRingPos(c, j)
            mx = math.max(mx, math.abs(a - c.angle))
        end
        return mx
    end

    for _, case in ipairs({
        -- Children that fit in one ring, and a parent sector wide enough that
        -- the ring stays inside it: the plainest shape there is.
        { label = "arc, one ring inside its sector", rings = 1,
          setup = Base(6, 1, 5) },
        -- Eight children on a twelve-entry palette: 30 degrees of parent
        -- sector, and a first ring that now spreads to 90 -- so the reach for
        -- an edge child leaves the parent's icon already well outside the
        -- sector the entry itself owns, and spills a second ring on top.
        { label = "arc, ring wider than its sector", rings = 2, widened = true,
          setup = Base(12, 1, 8) },
        -- A small radius, full-size child icons and a hair of nest distance:
        -- the rings come out crowded and close together, and the band between
        -- the parent's icon and the first of them is five units wide.
        { label = "arc, crowded rings, thin band", rings = 2,
          setup = function()
              Base(6, 1, 8)()
              p.radius, p.iconSize, p.nestScale, p.nestBand = 60, 44, 1.0, 10
          end },
        -- Two claims two entries apart, each spread wider than its own sector,
        -- so their grounds meet over the plain entry between them. Only one of
        -- them is ever armed, which is what makes that legal -- and the entry
        -- between them still fires when neither is.
        { label = "arc, two widened nests", rings = 2, overlap = true,
          setup = function()
              Base(8, 1, 8)()
              Palette(1).slots[3] = { kind = "palette", palette = 3 }
              local c = Palette(3)
              c.slots = {}
              for i = 1, 8 do c.slots[i] = { kind = "spell", id = 300 + i } end
              p.paletteCount = 3
              p.arcChildOverflow = "MIDPOINT"
          end },
    }) do
        case.setup()
        -- Spelled out rather than inherited: an earlier sweep leaves this at
        -- whatever it last needed, and every ring count asserted below is a
        -- count at THIS span.
        p.layout, p.arcSpan, p.arcChildMaxSpan = "ARC", 360, 90
        ns.Refresh()
        local view = ns.CreatePaletteView(UIParent, {})
        view:Layout(1)
        view:GetFrame():SetCenter(960, 540)
        local off = ClearOpen(view)
        view._steered, view._gateX, view._gateY = true, off + 960, off + 540
        local shown = view:ShownCount()
        local step = view:ArcGeom(shown)
        local c1 = view.claims[1]
        local report = {}

        -- (a) The press branch's own geometric pre-arm, on an arc: a press
        -- with the cursor already standing on the claim's entry raises no
        -- OnEnter of its own, so nothing but the press can account for the
        -- claim being armed. Read before any cursor motion at all.
        do
            local btn = OpenAt(1, c1.parentBox.x + 960, c1.parentBox.y + 540)
            local armed = tonumber(btn:GetAttribute("eapArmed"))
            local trace = btn:GetAttribute("eapGTrace")
            if armed ~= 1 or trace ~= "P1;" then
                report[#report + 1] = ("press pre-arm armed=%s trace=%s (want 1, P1;)")
                    :format(tostring(armed), tostring(trace))
            end
            snippet(btn, "LeftButton", false)
        end

        -- (b) Out to EVERY child, one straight reach each, and the claim has
        -- to survive every sample of it. "Survive" is asked of the model's own
        -- idea of the claim's ground rather than assumed: a sample the ground
        -- does not cover is a sample the claim is entitled to disarm on, and
        -- the count of those is reported too, because a reach that leaves the
        -- ground it was widened to cover is itself the bug.
        local strayed, lost, misfired, sawLeave = {}, {}, {}, 0
        for j = 1, c1.n do
            local r, a = view:ChildRingPos(c1, j)
            local cx, cy = r * math.sin(a), r * math.cos(a)
            local btn, mover = OpenAt(1, off + 960, off + 540)
            mover(c1.parentBox.x + 960, c1.parentBox.y + 540)
            if tonumber(btn:GetAttribute("eapArmed")) ~= 1 then
                lost[#lost + 1] = ("%d never armed"):format(j)
            end
            local x0, y0 = c1.parentBox.x, c1.parentBox.y
            for i = 1, 12 do
                local t = i / 12
                local x, y = x0 + (cx - x0) * t, y0 + (cy - y0) * t
                mover(x + 960, y + 540)
                local armed = tonumber(btn:GetAttribute("eapArmed"))
                if not ClaimContains(view, c1, x, y) then
                    strayed[#strayed + 1] = ("%d@%.2f"):format(j, t)
                elseif armed ~= 1 then
                    lost[#lost + 1] = ("%d@%.2f armed=%s"):format(j, t, tostring(armed))
                end
            end
            if (btn:GetAttribute("eapGTrace") or ""):find("L1:in;", 1, true) then
                sawLeave = sawLeave + 1
            end
            local got, why = ReleaseAt(btn, mover, cx + 960, cy + 540)
            if got ~= c1.base + j then
                misfired[#misfired + 1] = ("%d fired %s (%s)")
                    :format(j, tostring(got), tostring(why))
            end
        end
        -- A reach that never left a gate never asked the leave test anything,
        -- and a check that only ever exercised the arming half would pass
        -- with the ground test deleted. At least one of these reaches has to
        -- have crossed a real gate boundary and been answered "still inside".
        if sawLeave == 0 then
            report[#report + 1] = "no reach ever put the leave test to the question"
        end
        if #strayed > 0 or #lost > 0 or #misfired > 0 then
            report[#report + 1] = ("reaches off the claim's ground [%s]; disarmed [%s]; wrong release [%s]")
                :format(table.concat(strayed, ","), table.concat(lost, "; "),
                        table.concat(misfired, "; "))
        end

        -- (c) Sideways instead, onto the PLAIN entry next door. The entry ring
        -- belongs to the entries however wide a nest's children spread over
        -- it, so both sides must answer with that entry and neither with a
        -- child of the nest -- and the leave test must have been asked, which
        -- is what says the claim's ground was measured rather than missed.
        --
        -- The claim is NOT required to have disarmed by the last sample. A
        -- plain entry carries no gate of its own, so once the cursor is off
        -- every rect of the claim there is nothing left to fire the leave test
        -- again, and the claim can stay armed over an entry that is not its
        -- own -- which costs the drawing (the nest stays open) and nothing
        -- else, since the release below never consults it inside the ring. The
        -- claim-to-claim glide, where it WOULD cost something, is check (d).
        do
            local radius = select(1, view:Geom())
            local na = c1.angle + step
            local nx, ny = radius * math.sin(na), radius * math.cos(na)
            local btn, mover = OpenAt(1, off + 960, off + 540)
            mover(c1.parentBox.x + 960, c1.parentBox.y + 540)
            local armed = tonumber(btn:GetAttribute("eapArmed"))
            Walk(mover, c1.parentBox.x + 960, c1.parentBox.y + 540,
                        nx + 960, ny + 540, 12)
            local trace = btn:GetAttribute("eapGTrace") or ""
            CURSOR.x, CURSOR.y = nx + 960, ny + 540
            local want = view:HitTest()
            local got, why = ReleaseAt(btn, mover, nx + 960, ny + 540)
            if armed ~= 1 or got ~= c1.parent + 1 or want ~= c1.parent + 1
               or got > shown or not trace:find("L1", 1, true) then
                report[#report + 1] = ("sideways onto entry %d: armed=%s trace=%s view=%s got=%s why=%s")
                    :format(c1.parent + 1, tostring(armed), trace,
                            tostring(want), tostring(got), tostring(why))
            end
        end

        -- (d) The same glide, but onto ANOTHER CLAIM's entry: that one has to
        -- hand over, or its own nest is unreachable for the rest of the hold.
        -- An arc claim's ground never covers a neighbouring entry's centre, so
        -- the leave test answers "outside" there -- and the neighbour's parent
        -- gate is left alight on the arc precisely so that something fires it.
        if case.overlap then
            local c2 = view.claims[2]
            local btn, mover = OpenAt(1, off + 960, off + 540)
            mover(c1.parentBox.x + 960, c1.parentBox.y + 540)
            local armed = tonumber(btn:GetAttribute("eapArmed"))
            Walk(mover, c1.parentBox.x + 960, c1.parentBox.y + 540,
                        c2.parentBox.x + 960, c2.parentBox.y + 540, 12)
            local after = tonumber(btn:GetAttribute("eapArmed"))
            local trace = btn:GetAttribute("eapGTrace") or ""
            -- And the second nest really is live: its own first child fires
            -- from a reach that starts where the swap left the cursor.
            local r, a = view:ChildRingPos(c2, 1)
            local cx, cy = r * math.sin(a), r * math.cos(a)
            Walk(mover, c2.parentBox.x + 960, c2.parentBox.y + 540,
                        cx + 960, cy + 540, 12)
            local got, why = ReleaseAt(btn, mover, cx + 960, cy + 540)
            if armed ~= 1 or after ~= 2 or got ~= c2.base + 1
               or not trace:find("L1:out;", 1, true) then
                report[#report + 1] = ("glide onto claim 2: armed %s->%s trace=%s got=%s want=%s why=%s")
                    :format(tostring(armed), tostring(after), trace,
                            tostring(got), tostring(c2.base + 1), tostring(why))
            end
        end

        -- Shape guards. Each case is here for a geometry, and a change that
        -- quietly stopped producing it would leave the case passing about
        -- nothing: the ring count is what makes the multi-ring cases multi-ring,
        -- and the angular spread is what makes the widened ones widened.
        if #c1.rows ~= case.rings then
            report[#report + 1] = ("%d rings, expected %d"):format(#c1.rows, case.rings)
        end
        local spread = ArcClaimAngleOffsets(view, c1)
        if case.widened and spread <= step * 0.5 then
            report[#report + 1] = ("children span %.1f deg, inside the entry's own %.1f")
                :format(spread * 180 / math.pi, step * 0.5 * 180 / math.pi)
        end
        -- Two claims whose grounds do not actually meet would prove nothing
        -- about overlap being safe.
        if case.overlap then
            local c2 = view.claims[2]
            local mid = (c1.angle + c2.angle) * 0.5
            local rr = c1.rows[1].radius
            local mx, my = rr * math.sin(mid), rr * math.cos(mid)
            if not (ClaimContains(view, c1, mx, my)
                    and ClaimContains(view, c2, mx, my)) then
                report[#report + 1] = "the two nests' grounds do not overlap"
            end
        end

        if #report > 0 then
            fails = fails + 1
            offline[#offline + 1] = ("  %s: %s"):format(case.label,
                table.concat(report, "; "))
        end
        p.radius, p.iconSize, p.nestScale, p.nestBand = nil, nil, nil, nil
        p.arcChildOverflow = "NONE"
    end

    print(("real-gate focus paths                               %5d wrong%s"):format(
        fails, fails > 0 and "  <-- FAIL" or ""))
    for _, line in ipairs(offline) do print(line) end
    bad = bad + fails
    p.layout, p.gridNestStyle = "ARC", "PERIMETER"
end

----------------------------------------------------------------------------
--  Cycling marker entries
--
--  The position one of these has reached is stepped inside the snippet, so
--  only a real press can say what the next release fires. Ten presses round an
--  eight-step cycle: every marker in its turn, and the wrap back to the first.
--
--  The world numbers below are stated outright rather than read back out of
--  the module. They ARE the assertion: Blizzard's WORLD_RAID_MARKER_ORDER runs
--  skull to star, and a copy of it read the other way round places the marker
--  mirrored about the middle -- star puts down the skull -- which is a bug no
--  amount of internal agreement can see.
----------------------------------------------------------------------------
do
    local fails = 0

    local function RunCycle(label, kind, wantText, wantName)
        local a = Palette(1)
        a.slots = { { kind = kind } }
        p.paletteCount = 1
        p.layout, p.arcSpan, p.arcChildOverflow = "ARC", 360, "NONE"
        ns.Refresh()

        local btn = byName["EUIActionPaletteButton1"]
        btn:SetFrameRef("ui", UIParent)
        local view = ns.CreatePaletteView(UIParent, {})
        view:Layout(1)
        view:GetFrame():SetCenter(960, 540)
        view._steered = true

        local report = {}
        for press = 1, #wantText do
            -- What the entry ADVERTISES, read before the press that spends it:
            -- in a radial the icon is what the hand picks by, so the name it
            -- draws has to be the marker that then lands.
            local _, name = ns.SlotDisplay(a.slots[1])
            CURSOR.x, CURSOR.y = 20, 20
            snippet(btn, "LeftButton", true)
            -- One entry in a full circle: every angle outside the dead zone
            -- resolves to it, so straight up needs no geometry of its own.
            CURSOR.x, CURSOR.y = 960, 540 + 200
            snippet(btn, "LeftButton", false)

            local why = btn:GetAttribute("eapWhy")
            local text = btn:GetAttribute("macrotext")
            if why ~= "fire" then
                report[#report + 1] = ("press %d: %s, not a fire"):format(press, tostring(why))
            elseif text ~= wantText[press] then
                report[#report + 1] = ("press %d: fired %s, wanted %s"):format(
                    press, tostring(text), wantText[press])
            elseif name ~= wantName[press] then
                report[#report + 1] = ("press %d: drawn as %s, fired %s"):format(
                    press, tostring(name), wantText[press])
            end

            -- OnPostClick's mirror-back, which is what carries the snippet's
            -- answer into the next push and into every icon drawn before it.
            a.slots[1].cyclePos = tonumber(btn:GetAttribute("eapCycPos1"))
            ns.Refresh()
        end

        if #report > 0 then
            fails = fails + 1
            print(("  %s: %s"):format(label, table.concat(report, "; ")))
        end
    end

    local ORDER = { "Star", "Circle", "Diamond", "Triangle",
                    "Moon", "Square", "Cross", "Skull" }
    -- Icon position -> the number /wm takes. Blue, green, purple, red, yellow,
    -- orange, silver, white is the engine's own run.
    local WM = { 5, 6, 3, 2, 7, 1, 4, 8 }

    local tmText, tmName, wmText, wmName = {}, {}, {}, {}
    for press = 1, 10 do
        local i = (press - 1) % 8 + 1
        tmText[press] = "/tm " .. i
        tmName[press] = "Cycle Target Marker: " .. ORDER[i]
        wmText[press] = "/wm " .. WM[i]
        wmName[press] = "Cycle World Marker: " .. ORDER[i]
    end

    RunCycle("cycle target marker", "cycleraidtarget", tmText, tmName)
    RunCycle("cycle world marker", "cycleworldmarker", wmText, wmName)

    print(("marker cycles step and wrap                        %5d wrong%s"):format(
        fails, fails > 0 and "  <-- FAIL" or ""))
    bad = bad + fails
end

----------------------------------------------------------------------------
--  One palette at a time owns the shared secure state
--
--  The scroll catcher, the cancel button and the ESCAPE binding belong to
--  every palette at once, so a second key pressed while the first is still
--  HELD must change none of them -- and its own release must put none of them
--  away. The Lua PreClick that refuses the second key runs before the snippet
--  and cannot stop it, so the test that matters is the one inside SNIPPET_PRE
--  and SNIPPET_POST, which is what this executes: both real bodies, on the
--  real buttons, in the order a real pair of keys would run them.
----------------------------------------------------------------------------
do
    local fails, report = 0, {}

    local postBody = src:match("local SNIPPET_POST = %[==%[(.-)%]==%]")
    assert(postBody, "SNIPPET_POST not found")
    postBody = postBody:gsub("__REGION_MAX__", tostring(ns.REGION_MAX))
    -- Wrapped_Click builds the post-body against "self,message,button,down",
    -- one argument more than the pre-body -- see SecureHandlers.lua.
    local post = assert(load("local self, message, button, down = ...\n" .. postBody,
                             "SNIPPET_POST", "t", sandbox))

    local function Want(label, got, want)
        if got ~= want then
            report[#report + 1] = ("%s: got %s, wanted %s"):format(
                label, tostring(got), tostring(want))
        end
    end

    -- A scroll fan, so the shared catcher is actually in play: it is the frame
    -- the strip is steered through, and the one a stray release would hide.
    Base(4, nil, 0)()
    p.layout, p.fanInput = "FAN", "SCROLL"
    ns.Refresh()

    local b1 = byName["EUIActionPaletteButton1"]
    local b2 = byName["EUIActionPaletteButton2"]
    local catcher = byName["EUIActionPaletteScrollCatcher"]
    local cancel  = byName["EUIActionPaletteCancel"]
    assert(b1 and b2 and catcher and cancel, "both buttons, the catcher and the cancel button")
    -- Nothing holds the screen at this point: every earlier check presses
    -- through the pre-body only, which leaves the stamp standing.
    cancel:SetAttribute("eapOwner", nil)

    CURSOR.x, CURSOR.y = 20, 20
    snippet(b1, "LeftButton", true)
    Want("palette 1 steers a scroll strip", b1:GetAttribute("eapMode"), "SCROLL")
    Want("palette 1 owns the screen", cancel:GetAttribute("eapOwner"), 1)
    Want("the catcher is open", catcher:GetAttribute("eapOpen"), 1)
    -- Somewhere along the strip, so a re-seed by the second key would show.
    catcher:SetAttribute("eapFanTarget", 3)

    snippet(b2, "LeftButton", true)
    Want("palette 2's press is refused", b2:GetAttribute("eapWhy"), "taken")
    Want("the strip is where palette 1 left it", catcher:GetAttribute("eapFanTarget"), 3)
    Want("the owner is unchanged", cancel:GetAttribute("eapOwner"), 1)

    post(b2, nil, "LeftButton", false)
    Want("palette 2's release leaves the catcher open", catcher:GetAttribute("eapOpen"), 1)
    Want("palette 2's release leaves the catcher shown", catcher:IsShown(), true)
    Want("palette 2's release leaves the owner alone", cancel:GetAttribute("eapOwner"), 1)

    post(b1, nil, "LeftButton", false)
    Want("palette 1's own release closes the catcher", catcher:GetAttribute("eapOpen"), nil)
    Want("palette 1's own release hides the catcher", catcher:IsShown(), false)
    Want("palette 1's own release frees the screen", cancel:GetAttribute("eapOwner"), nil)

    fails = #report
    print(("one palette at a time owns the shared state        %5d wrong%s"):format(
        fails, fails > 0 and "  <-- FAIL" or ""))
    for _, line in ipairs(report) do print("  " .. line) end
    bad = bad + fails
    p.layout, p.fanInput = "ARC", nil
end

print(bad == 0 and "\nALL AGREE" or ("\n" .. bad .. " DISAGREEMENTS"))
os.exit(bad == 0 and 0 or 1)
