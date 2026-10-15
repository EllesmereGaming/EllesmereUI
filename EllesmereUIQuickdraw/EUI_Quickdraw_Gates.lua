if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Quickdraw_Gates.lua
--
--  The arming gates: the enter and leave snippets, the claim gates and the
--  lattice gates.
--  Reads the earlier Quickdraw files through ns and ns._qdInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._qdInternals
-- EllesmereUIQuickdraw.lua or an earlier Quickdraw file failed to load.
if not I or I.broken then return end
I.broken = true

local LIVE_STRATA, MAX_LATTICE, REGION_MAX = I.LIVE_STRATA, I.MAX_LATTICE, I.REGION_MAX
local EnsureScrollCatcher, EnsureSecureHeader = I.EnsureScrollCatcher, I.EnsureSecureHeader
local ARM_CLAIM = I.ARM_CLAIM

-------------------------------------------------------------------------------
--  Arming gates -- the pass-through rule, and the exclusive-ground rule
--
--  A nest's cells only answer a release once the cursor has actually entered
--  the claim's own parent entry, and stop answering only once it has left
--  the claim's WHOLE ground -- parent cell, nest, and the corridor between --
--  not merely one rect of it. That is state that has to survive the entire
--  hold, which the release snippet cannot do on its own -- it only ever sees
--  the final position -- so it is kept on the secure button itself, as
--  eqdArmed, and maintained by protected frames per claim reacting to real
--  mouse movement:
--
--    PARENT gate    covers the claim's own entry. OnEnter arms the claim,
--                   hides every OTHER claim's parent gate (block layouts
--                   only -- see below), and shows this claim's REGION gates.
--    REGION gates    up to REGION_MAX rects covering the claim's ground -- see
--                   CorridorBox and CellChildGeom/ChildGeom for what
--                   they are. An arc's ground is a wedge rather than a set of
--                   rects, so there its rects are event surfaces only and the
--                   test below is polar. OnLeave of ANY of them does NOT blindly
--                   disarm: moving between two of a claim's own region rects
--                   also fires OnLeave (see below), so the snippet instead
--                   measures the cursor against the claim's FULL region,
--                   geometrically, and disarms only when it is genuinely
--                   outside all of it. Disarming re-shows every OTHER
--                   claim's parent gate and hides this claim's own regions.
--
--  Parent gates sit at a HIGHER frame level than region gates, and every
--  region gate of a claim sits at the SAME level as its siblings. WoW's mouse
--  focus is exclusive and topmost-wins -- exactly one frame holds it at a
--  time -- which is what both rules lean on:
--
--    Exclusive arming, in the BLOCK layouts.  While claim A is armed, every
--    OTHER claim's parent gate is hidden, so brushing past a neighbour's cell
--    cannot steal focus from A's own ground no matter how close the two sit.
--    A hidden gate cannot receive
--    OnEnter, so B stays unarmable until A's OnLeave test actually disarms it
--    and re-shows B's gate.
--
--    The ARC does the opposite and leaves them alight, because there the two
--    grounds do not interleave: a claim's children sit radially outside the
--    entry ring, and its ground clears the neighbouring entries' own centres
--    (see ChildGeom). What it cannot do is cover that ground with rects -- the
--    ground is a wedge -- so a cursor that has left every rect of A while
--    still on A's ground has nothing left to fire the leave test again, and
--    hiding B's gate as well would leave A armed over the entry the cursor
--    finally stopped on. That is also the one place the two layouts' promises
--    differ: on the arc a claim can stay armed over a PLAIN entry, which
--    leaves its nest drawn open a moment too long and costs the release
--    nothing (the release never consults eqdArmed inside the entry ring).
--
--    Geometric arming, at the two moments a gate is SHOWN. Show() does not
--    synthesise a motion event, so a gate that comes up under a cursor
--    already inside it raises no OnEnter at all until the cursor leaves and
--    comes back -- and both of the moments gates are shown are moments the
--    cursor is very likely already on one. In cursor mode the palette opens
--    centred on the pointer, so a middle cell's gate is under it at every
--    single press; and a disarm re-shows every parent gate, possibly beneath
--    a cursor that has already arrived on another claim's entry. Left to the
--    OnEnter edge alone, the nest was drawn and its children dead until the
--    user wiggled out and back. So both moments ask the same question
--    geometrically, in secure code, from the same pushed parent boxes the
--    gates themselves were placed from: the press branch of SNIPPET_PRE
--    after it places them, and LeaveSnippet's disarm path after it re-shows
--    them. Both then arm through ARM_CLAIM, the same fragment a parent
--    gate's own OnEnter uses, so there is only ever one meaning of "armed".
--
--    Same-claim focus hand-off.  Moving from one of a claim's own region
--    rects to a sibling rect of the SAME claim still fires the first one's
--    OnLeave (focus left THAT frame), which is why the geometric re-test
--    exists: it finds the cursor inside the sibling rect and answers "still
--    in", so nothing is disarmed and neither rect is hidden. Nothing needs a
--    reference to any gate but its own here, because the button (eqdArmed)
--    is the only shared state -- every gate reads and writes through it.
--
--  Built and positioned only out of combat, alongside PushPalette's geometry:
--  SecureHandlerSetFrameRef and SecureHandlerWrapScript are themselves
--  ordinary insecure calls, and PushPalette already refuses to run in combat
--  for the same reason. Positioning happens in the press branch of
--  SNIPPET_PRE instead, because only that branch knows where this particular
--  press's palette actually opened.
--
--  The scroll strip's HOVER channel arms through a third shape, the LATTICE
--  (see EnsureLatticeGates): one gate per drawn strip POSITION rather than
--  per claim, because the wheel decides which slot stands at a position and
--  can change it mid-hold -- the gates hold still, resolve position -> slot
--  at enter time from the accumulator, and the wheel snippet re-derives the
--  answer for a pointer the slide moved under without any motion. Entering a
--  position that nests nothing DISARMS; the ground beside the strip touches
--  no gate and so retains, which is the sticky reach for a nest's children.
-------------------------------------------------------------------------------

-- self:GetFrameRef("btn") is the palette's own secure button; every gate
-- carries that one reference back, however many palettes and claims exist,
-- because the header they are all wrapped through is shared. k is baked into
-- the snippet text rather than read off an attribute: each gate only ever
-- needs to know its OWN claim index, never anyone else's, so there is nothing
-- for a shared body to look up. It goes into a LOCAL of that name, which is
-- what ARM_CLAIM reads -- the two sites that arm geometrically only know their
-- claim at run time, and one fragment serving all three is one definition of
-- what arming does.
--
-- Wrapped in parentheses for the same reason LeaveSnippet's return is; see
-- the note there.
-- Wrapped in a block so the two shared FRAGMENTS below cost no main-chunk
-- local: as one file the module sat within a couple of Lua's ceiling of 200.
local EnterSnippet, LeaveSnippet
do

-- Where the cursor is in the palette's own space, as cdx/cdy -- nil when there
-- was no reading to take. The maths mirrors the release branch of SNIPPET_PRE:
-- same origin, same scale, same units, because every one of these answers the
-- identical question from a different place and they must not drift apart. One
-- fragment is how they are kept from drifting.
local CURSOR_OFFSET = [==[
        local cdx, cdy
        do
            local ui = self:GetFrameRef("ui")
            if ui then
                local x, y = ui:GetMousePosition()
                if x then
                    local w, h = ui:GetWidth(), ui:GetHeight()
                    local cx, cy = x * w, y * h
                    local s = tonumber(btn:GetAttribute("eqdScale")) or 1
                    if s <= 0 then s = 1 end
                    local ox, oy
                    if btn:GetAttribute("eqdFixed") then
                        ox = w * 0.5 + (tonumber(btn:GetAttribute("eqdPosX")) or 0)
                        oy = h * 0.5 + (tonumber(btn:GetAttribute("eqdPosY")) or 0)
                    else
                        ox = tonumber(btn:GetAttribute("eqdGX"))
                        oy = tonumber(btn:GetAttribute("eqdGY"))
                    end
                    if ox then cdx, cdy = (cx - ox) / s, (cy - oy) / s end
                end
            end
        end
]==]

-- An ARC claim's true ground, measured polar: does the offset dx/dy stand on
-- claim gk's own ground? Sets `inside`, which both callers declare.
--
-- The rects the gate frames use are event surfaces only and generous on purpose
-- (see CorridorBox); this is what actually decides the ground. Two pieces, both
-- sized by ChildGeom -- a BEAM out of the parent entry, and a WEDGE past the
-- entry ring's outer edge -- and nothing at all inward of the icon's inner face,
-- where a retreat toward the centre has to disarm so the other claims get their
-- parent gates back.
--
-- Neither piece is the release's own ring resolution, and both are supersets of
-- it. The beam is what the reach for a child actually travels through: a
-- straight line from the parent passes BESIDE its icon before it clears the
-- entry ring, and while that ground belonged to nothing the pgate's own OnLeave
-- -- fired a few units into every reach -- disarmed the claim and left its
-- children dead for the rest of the hold.
--
-- Asked at BOTH edges. The disarm has always asked it. The arm asks it too now:
-- a claim whose only way in was its parent's own icon could not be reached by
-- the one move a user actually makes, which is to head straight at the child
-- they can see. The icon is 40 units across at a radius of 100 -- about eleven
-- degrees -- while a claim's children spread up to forty-five degrees either
-- side of it, so most of a nest's children sit at angles whose straight reach
-- never crosses the icon at all.
local ARC_GROUND = [==[
                        local lo = tonumber(btn:GetAttribute("eqdCLo" .. gk))
                        -- Along the parent's own axis, and across it. The axis
                        -- is pushed as a vector because the sandbox has no
                        -- sin/cos to rebuild it from the angle.
                        local u = lo and (dx * (tonumber(btn:GetAttribute("eqdCAX" .. gk)) or 0)
                                        + dy * (tonumber(btn:GetAttribute("eqdCAY" .. gk)) or 0))
                        if u and u >= lo then
                            local v = dx * (tonumber(btn:GetAttribute("eqdCAY" .. gk)) or 0)
                                    - dy * (tonumber(btn:GetAttribute("eqdCAX" .. gk)) or 0)
                            if v < 0 then v = -v end
                            if v <= (tonumber(btn:GetAttribute("eqdCBeam" .. gk)) or 0)
                                    + u * (tonumber(btn:GetAttribute("eqdCSlope" .. gk)) or 0) then
                                inside = true
                            elseif (dx * dx + dy * dy) ^ 0.5
                                   >= (tonumber(btn:GetAttribute("eqdCEdge" .. gk)) or 0) then
                                local ad = (atan2(dx, dy)
                                    - (tonumber(btn:GetAttribute("eqdCAngle" .. gk)) or 0)) % 360
                                if ad > 180 then ad = 360 - ad end
                                inside = ad <= (tonumber(btn:GetAttribute("eqdCWedge" .. gk)) or 0)
                            end
                        end
]==]

-- self:GetFrameRef("btn") is the palette's own secure button; every gate
-- carries that one reference back, however many palettes and claims exist,
-- because the header they are all wrapped through is shared. k is baked into
-- the snippet text rather than read off an attribute: each gate only ever
-- needs to know its OWN claim index, never anyone else's, so there is nothing
-- for a shared body to look up. It goes into a LOCAL of that name, which is
-- what ARM_CLAIM reads -- the sites that arm geometrically only know their
-- claim at run time, and one fragment serving all of them is one definition of
-- what arming does.
--
-- `region` asks for the REGION gates' variant. A parent gate arms outright:
-- its rect IS the claim's own cell, so standing on it is standing on the claim.
-- A region gate's rects are not that -- they are generous event surfaces, and
-- on the arc they reach over ground belonging to other entries -- so that
-- variant arms only where the claim's true ground says so, which on the arc is
-- the polar test above and off it is nothing at all. The block layouts keep
-- their region gates dark until the claim is armed and reach their nests across
-- a corridor, so an arming edge there would only ever fire where the claim is
-- armed already.
--
-- Wrapped in parentheses for the same reason LeaveSnippet's return is; see
-- the note there.
function EnterSnippet(k, region)
    if region then
        return (([==[
        local btn = self:GetFrameRef("btn")
        if btn and btn:GetAttribute("eqdMode") == "ANGULAR" then
            local inside = false
__CURSOR_OFFSET__
            if cdx then
                local dx, dy = cdx, cdy
                -- WHOSE ground is this, rather than "is it mine". The gate that
                -- wins the cursor is not necessarily the gate of the claim
                -- whose ground it is on: the arc's region rects are generous,
                -- several claims' rects overlap around the ring, and mouse
                -- focus is topmost-wins among frames on one level.
                local armedNow = tonumber(btn:GetAttribute("eqdArmed"))
                -- The armed claim keeps the cursor while it still holds it.
                -- Claim grounds OVERLAP -- a wedge widens as it goes out, and
                -- one claim's beam crosses its neighbour's wedge near the ring
                -- -- so a rule that just picked a holder would hand a reach for
                -- a child over to whichever neighbour also covered that point.
                -- Reaching past a nest's own icons pulled the neighbouring nest
                -- open on top of it.
                local hold
                if armedNow then
                    local gk = armedNow
__ARC_GROUND__
                    hold = inside
                end
                if not hold then
                    -- Otherwise the claim whose own axis the cursor is nearest,
                    -- not the first one found: the claims are walked in index
                    -- order, and lowest-index-wins put 12 o'clock in front of
                    -- everything its wedge reached over.
                    local found, bestAd
                    local gm = tonumber(btn:GetAttribute("eqdGateMax")) or 0
                    for gk = 1, gm do
                        inside = false
__ARC_GROUND__
                        if inside then
                            local ad = (atan2(dx, dy)
                                - (tonumber(btn:GetAttribute("eqdCAngle" .. gk)) or 0)) % 360
                            if ad > 180 then ad = 360 - ad end
                            if not bestAd or ad < bestAd then
                                found, bestAd = gk, ad
                            end
                        end
                    end
                    if found and found ~= armedNow then
                        local k = found
                        __ARM_CLAIM__
                    end
                end
            end
        end
    ]==]):gsub("__CURSOR_OFFSET__", function() return CURSOR_OFFSET end)
          :gsub("__ARC_GROUND__", function() return ARC_GROUND end)
          :gsub("__ARM_CLAIM__", function() return ARM_CLAIM end))
    end
    return (([==[
        local btn = self:GetFrameRef("btn")
        if btn then
            local k = __CLAIM_K__
            __ARM_CLAIM__
        end
    ]==]):gsub("__CLAIM_K__", tostring(k))
          :gsub("__ARM_CLAIM__", function() return ARM_CLAIM end))
end

-- Runs on the OnLeave of any one of claim k's region rects. Does not trust
-- "I lost focus" to mean "the claim is left" -- a claim can own several of
-- these rects, and moving between two of its own fires this too -- so it
-- re-measures the cursor against the claim's WHOLE region before deciding.
-- Built with plain substitution rather than string.format: the body below
-- has a real modulo operator in it (`% 360`), which format would choke on
-- as an invalid conversion.
--
-- The whole chain is wrapped in its own parentheses, not merely the string
-- literal at its head: gsub returns the substitution count as a SECOND
-- value, and an unparenthesised tail call in a return statement hands both
-- of them back. EnsureGates calls this as the LAST argument to
-- SecureHandlerWrapScript, so that stray count would have landed in
-- postBody -- which SecureHandlerWrapScript rejects outright unless it is a
-- string or nil, aborting the wrap (and, uncaught, the rest of EnsureGates'
-- loop past it) with "Invalid post-handler body" the moment any claim's
-- first region gate was ever built.
--
-- k is nil for the FLOOR gate, which belongs to no one claim and runs the same
-- test for whichever claim is armed at the moment it is entered. Only the "is
-- this gate still the armed claim's" prologue differs, and the rest of the
-- body already reads `armed` at run time rather than through the baked-in
-- literal, so both variants measure the identical ground the identical way.
--
-- `region` again marks the REGION gates' variant, and changes one thing: a
-- stale gate is put away, EXCEPT on the arc, where the region gates are up from
-- the open precisely so that entering one can arm the claim. Hiding those the
-- first time the cursor crossed one unarmed would take that way in away again.
function LeaveSnippet(k, region)
    return (([==[
        local btn = self:GetFrameRef("btn")
        local armed = btn and tonumber(btn:GetAttribute("eqdArmed"))
        if __STALE_TEST__ then
            __STALE_KEEP__
            self:Hide()
            return
        end
        -- Past here armed == this claim's own index, so every attribute
        -- lookup below reads THROUGH the runtime value rather than through
        -- another baked-in literal -- one less place for a claim's own
        -- number to have to agree with itself.

        local inside = false
        -- The cursor offset, kept out here rather than in the block that
        -- works it out: the disarm path at the bottom re-uses it to ask
        -- whether the cursor has landed on ANOTHER claim's entry, and it is
        -- the same reading either way. nil when there was no reading to take.
__CURSOR_OFFSET__
        if cdx then
            local dx, dy = cdx, cdy

                    -- No inflation HERE, and none needed: the overshoot grace
                    -- a fast reach wants is built into the eqdRO* rects
                    -- themselves, by CellChildGeom, so the gate FRAMES the
                    -- press branch sizes from those numbers already carry it
                    -- and this test consumes the identical rects. That is the
                    -- whole reason it belongs there rather than here. A margin
                    -- applied only in this test would instead create a dead
                    -- zone: the cursor crossing the frame's own smaller edge
                    -- fires this, the margin answers "still inside", and no
                    -- gate is left under the cursor to fire a SECOND OnLeave
                    -- once it clears the wider boundary -- so that verdict is
                    -- never revisited and the claim stays armed however far
                    -- the cursor drifts on.

                    -- The parent's own cell always counts.
                    local phw = tonumber(btn:GetAttribute("eqdPOHW" .. armed))
                    if phw then
                        local pox = tonumber(btn:GetAttribute("eqdPOX" .. armed)) or 0
                        local poy = tonumber(btn:GetAttribute("eqdPOY" .. armed)) or 0
                        local phh = tonumber(btn:GetAttribute("eqdPOHH" .. armed)) or 0
                        if abs(dx - pox) <= phw and abs(dy - poy) <= phh then
                            inside = true
                        end
                    end

                    if not inside and btn:GetAttribute("eqdMode") == "ANGULAR" then
                        local gk = armed
__ARC_GROUND__
                    elseif not inside then
                        for r = 1, __REGION_MAX__ do
                            local rhw = tonumber(btn:GetAttribute("eqdROHW" .. armed .. "_" .. r))
                            if rhw then
                                local rox = tonumber(btn:GetAttribute("eqdROX" .. armed .. "_" .. r)) or 0
                                local roy = tonumber(btn:GetAttribute("eqdROY" .. armed .. "_" .. r)) or 0
                                local rhh = tonumber(btn:GetAttribute("eqdROHH" .. armed .. "_" .. r)) or 0
                                if abs(dx - rox) <= rhw and abs(dy - roy) <= rhh then
                                    inside = true
                                    break
                                end
                            end
                        end
                    end
        end

        if not inside then
            btn:SetAttribute("eqdArmed", nil)
            local gm = tonumber(btn:GetAttribute("eqdGateMax")) or 0
            for i = 1, gm do
                local other = btn:GetFrameRef("pgate" .. i)
                -- Only a slot that still has a claim this open: see the
                -- matching note in EnterSnippet's own Show() loop.
                if other and btn:GetAttribute("eqdPOHW" .. i) then other:Show() end
            end
            -- The arc's region gates stay up: they are this layout's way IN,
            -- and a disarmed claim has to be armable again without the cursor
            -- going back to the parent icon it did not touch in the first
            -- place. Every other layout puts them away, arming there being the
            -- parent gate's own business.
            if btn:GetAttribute("eqdMode") ~= "ANGULAR" then
                for r = 1, __REGION_MAX__ do
                    local region = btn:GetFrameRef("rgate" .. armed .. "_" .. r)
                    if region then region:Hide() end
                end
            end

            -- Those parent gates went back up under wherever the cursor
            -- happens to be right now, which on a quick move from one claim's
            -- entry to another's is that other entry itself. Show() raises no
            -- OnEnter, so the claim the user has already reached would stay
            -- unarmed until they moved off it and back on. Asked
            -- geometrically instead, from the boxes the gates were placed
            -- from -- the same thing the press branch does for the same
            -- reason. Skipped when there was no cursor reading to take:
            -- nothing to test against, and the disarm above already stands.
            if cdx then
                local reArm
                local rgm = tonumber(btn:GetAttribute("eqdGateMax")) or 0
                for i = 1, rgm do
                    if i ~= armed then
                        local phw2 = tonumber(btn:GetAttribute("eqdPOHW" .. i))
                        if phw2 then
                            local pox2 = tonumber(btn:GetAttribute("eqdPOX" .. i)) or 0
                            local poy2 = tonumber(btn:GetAttribute("eqdPOY" .. i)) or 0
                            local phh2 = tonumber(btn:GetAttribute("eqdPOHH" .. i)) or 0
                            if abs(cdx - pox2) <= phw2 and abs(cdy - poy2) <= phh2 then
                                reArm = i
                                break
                            end
                        end
                    end
                end
                if reArm then
                    local k = reArm
                    __ARM_CLAIM__
                end
            end
        end
    ]==]):gsub("__STALE_TEST__", k and ("armed ~= " .. k) or "not armed")
         -- Nothing at all for the gates that have no reason to ask: the
         -- substitution leaves the line out rather than baking in a test that
         -- is always false.
         :gsub("__STALE_KEEP__", region
               and 'if btn and btn:GetAttribute("eqdMode") == "ANGULAR" then return end'
               or "")
         :gsub("__CURSOR_OFFSET__", function() return CURSOR_OFFSET end)
         :gsub("__ARC_GROUND__", function() return ARC_GROUND end)
         :gsub("__REGION_MAX__", tostring(REGION_MAX))
         :gsub("__ARM_CLAIM__", function() return ARM_CLAIM end))
end

end

-- One parent gate and up to REGION_MAX region gates per possible claim,
-- pooled per palette. MAX_SLOTS of each is the most a palette could ever
-- need -- one claim per slot -- but that is 1 + REGION_MAX frames and twice
-- as many wrapped scripts for every one of them, paid at login by palettes
-- that nest nothing at all, which is most of them. So the pool grows to
-- whatever PushPalette asks for and never shrinks: the snippets clear and
-- re-show gates by index up to eqdGateMax, which is the same high-water mark
-- (see PushPalette), so a claim that stops nesting keeps a real gate to be
-- cleared through for the rest of the session. Growth only ever appends --
-- PushPalette repositions and re-shows or hides what is already there.
local gatePools = {}

-- The gate builders share GateMouse and LatticeSnippet, and nothing outside
-- them uses either. Wrapped in a block so those two cost no main-chunk local:
-- as one file the module sat within a couple of Lua's ceiling of 200.
local EnsureGates, EnsureLatticeGates
do
-- Every gate wants MOTION and nothing else: it is a hover detector, and it must
-- never be the frame that ANSWERS a mouse button. Gates are under the cursor for
-- the whole of an open -- the floor gate covers the screen -- and a Select key
-- bound to a mouse button reaches the palette through an override binding, which
-- the client runs only when nothing under the cursor has claimed that button.
--
-- SetMouseClickEnabled(false) alone was not enough. With it, a latched menu's
-- mouse Select key did nothing for as long as any claim was armed: nested
-- entries could not be picked at all, and the next top-level entry stayed dead
-- until a retreat through the centre disarmed and took the floor gate down with
-- it. A keyboard Select key was unaffected throughout, which is what identified
-- the gates as the thing in the way. (Confirmed in game, 2026-08-11.)
--
-- So the buttons are declared not ours OUTRIGHT rather than merely left
-- unhandled: clicks are enabled, and every button is passed through. This is the
-- shape Blizzard's own map pins use to let a button reach the canvas beneath
-- them (MapCanvas_DataProviderBase.lua:288-301). SetPassThroughButtons carries
-- IsProtectedFunction, exactly like the SetMouseClickEnabled and EnableMouse
-- calls this file already makes on these same frames, and every gate is built
-- out of combat.
--
-- Without the method -- an older client -- clicks stay off, which is where this
-- began: hover-driven nesting works and a mouse Select key does not.
-- EVERY button the client knows, not the five a common mouse carries: an MMO
-- mouse reports its side buttons as BUTTON6 and up, and Blizzard names them
-- through BUTTON31 (SecureTemplates.lua:90-93). A Select key bound to one left
-- off this list is a key the gates swallow, which is the very failure the note
-- above describes.
-- Built on the first gate rather than at load: a session that never opens a
-- palette builds no gates, and this module costs nothing while switched off.
local PASS_BUTTONS

local function GateMouse(gate)
    gate:SetMouseMotionEnabled(true)
    if gate.SetPassThroughButtons then
        if not PASS_BUTTONS then
            PASS_BUTTONS = { "LeftButton", "RightButton", "MiddleButton" }
            for n = 4, 31 do PASS_BUTTONS[#PASS_BUTTONS + 1] = "Button" .. n end
        end
        gate:SetMouseClickEnabled(true)
        gate:SetPassThroughButtons(unpack(PASS_BUTTONS))
    else
        gate:SetMouseClickEnabled(false)
    end
end

function EnsureGates(index, btn, need)
    local pool = gatePools[index]
    if not pool then
        pool = { pgate = {}, rgate = {}, built = 0 }
        gatePools[index] = pool

        -- The FLOOR. One per palette, under every other gate and over
        -- everything else, shown only while some claim is armed -- see
        -- ARM_CLAIM, which shows it, and SNIPPET_POST, which puts it away with
        -- the rest of them.
        --
        -- It exists because arming and disarming do not run off the same kind
        -- of edge. A claim can be armed with the cursor standing still -- the
        -- press branch's pre-arm, and LeaveSnippet's re-arm, both of which
        -- measure the cursor against the pushed boxes rather than waiting for
        -- an OnEnter that a gate shown under a still cursor never gets -- and
        -- Blizzard's own wrapper raises "_wrapentered" only from inside a
        -- MOTION OnEnter (SecureHandlers.lua, Wrapped_OnEnter), while its
        -- OnLeave refuses to run a pre-body without that flag. So a
        -- geometrically armed claim's parent gate has a dead OnLeave: the
        -- cursor steps off the cell through ground no region rect covers, and
        -- nothing disarms for the rest of the hold -- nest stuck open, block
        -- stuck dim, every other claim's parent gate stuck hidden. The sandbox
        -- cannot raise the flag itself either: RestrictedFrames' SetAttribute
        -- rejects every name beginning with an underscore.
        --
        -- An OnENTER pre-body has no such precondition -- motion is all it
        -- asks -- so the disarm is hung off entering the floor rather than
        -- leaving the cell. Screen-wide, because the one thing it must never
        -- do is leave a way off the ground that misses it; below the region
        -- gates (level 10) and the parent gates (20), so every rect of a
        -- claim's real ground still wins the cursor and the floor is only ever
        -- reached where the ground is not. Motion only: clicks -- the secure
        -- activation path itself, including a latched menu's Select key -- pass
        -- straight through it, exactly as they do through the gates it sits
        -- under. See GateMouse, which is what makes that true.
        local fgate = CreateFrame("Frame", "EUIQuickdrawButton" .. index .. "FGate",
            UIParent, "SecureHandlerEnterLeaveTemplate")
        fgate:SetAllPoints(UIParent)
        fgate:SetFrameStrata(LIVE_STRATA)
        fgate:SetFrameLevel(5)
        GateMouse(fgate)
        fgate:Hide()

        SecureHandlerSetFrameRef(fgate, "btn", btn)
        SecureHandlerSetFrameRef(fgate, "ui", UIParent)
        -- Both edges, for the same reason a region gate wraps both: the OnEnter
        -- is the test that matters, and the OnLeave is what raising the flag on
        -- that entry buys -- a screen-wide gate is only ever left for another
        -- gate, and re-testing there costs one geometric measurement.
        SecureHandlerWrapScript(fgate, "OnEnter", EnsureSecureHeader(), LeaveSnippet(nil))
        SecureHandlerWrapScript(fgate, "OnLeave", EnsureSecureHeader(), LeaveSnippet(nil))
        SecureHandlerSetFrameRef(btn, "fgate", fgate)
        pool.fgate = fgate
    end
    if pool.built >= need then return pool end

    for k = pool.built + 1, need do
        local pgate = CreateFrame("Frame", "EUIQuickdrawButton" .. index .. "PGate" .. k,
            UIParent, "SecureHandlerEnterLeaveTemplate")
        pgate:SetFrameStrata(LIVE_STRATA)
        pgate:SetFrameLevel(20)
        GateMouse(pgate)
        pgate:Hide()

        SecureHandlerSetFrameRef(pgate, "btn", btn)
        SecureHandlerSetFrameRef(pgate, "ui", UIParent)
        SecureHandlerWrapScript(pgate, "OnEnter", EnsureSecureHeader(), EnterSnippet(k))
        -- The parent gate's own rect is exactly the claim's own cell, and it
        -- outranks every region gate of the same claim (level 20 against 10),
        -- so wherever a region reaches over that cell -- all of it, as an
        -- uncarved one does, or whatever part of it a carve left -- this gate
        -- is the one with focus there, and a region gate is only ever the
        -- topmost alongside or beyond the cell. Wherever a region does not
        -- extend past the parent cell at all -- HALO skipping a ring
        -- position a plain neighbour already occupies is the everyday case
        -- of this -- leaving the parent cell in exactly that direction
        -- leaves NO gate underneath at all, and the topmost-wins focus
        -- model this depends on hands focus straight to nothing without
        -- ever touching a region gate's own OnLeave. Wrapping this gate's
        -- OnLeave with the identical true-ground re-test closes that gap:
        -- every way OUT of the claim now runs the same check, whether the
        -- last gate under the cursor was the parent's or one of its
        -- regions'.
        SecureHandlerWrapScript(pgate, "OnLeave", EnsureSecureHeader(), LeaveSnippet(k))

        -- The button carries its own reference to every gate too, so the press
        -- branch of SNIPPET_PRE -- which only knows claim indices and boxes,
        -- never the frames themselves until it asks -- can place and size them.
        SecureHandlerSetFrameRef(btn, "pgate" .. k, pgate)

        pool.pgate[k] = pgate
        pool.rgate[k] = {}
        for r = 1, REGION_MAX do
            local rgate = CreateFrame("Frame", "EUIQuickdrawButton" .. index .. "RGate" .. k .. "_" .. r,
                UIParent, "SecureHandlerEnterLeaveTemplate")
            rgate:SetFrameStrata(LIVE_STRATA)
            rgate:SetFrameLevel(10)
            GateMouse(rgate)
            rgate:Hide()

            SecureHandlerSetFrameRef(rgate, "btn", btn)
            SecureHandlerSetFrameRef(rgate, "ui", UIParent)
            -- OnEnter carries the ARC's way in, and nothing at all off it --
            -- see EnterSnippet's `region` variant. It would still have to be
            -- wrapped here even when it carried nothing: SecureHandlers.lua's
            -- own OnEnter/OnLeave wrapper only ever raises "_wrapentered" from
            -- INSIDE the OnEnter wrap (Wrapped_OnEnter), and Wrapped_OnLeave
            -- refuses to run LeaveSnippet at all unless that flag is already
            -- up. Left unwrapped, the flag stays permanently down and the
            -- disarm test never runs -- a claim that ever armed stays armed for
            -- the rest of the hold, nest stuck open and block stuck dim.
            SecureHandlerWrapScript(rgate, "OnEnter", EnsureSecureHeader(), EnterSnippet(k, true))
            SecureHandlerWrapScript(rgate, "OnLeave", EnsureSecureHeader(), LeaveSnippet(k, true))

            SecureHandlerSetFrameRef(btn, "rgate" .. k .. "_" .. r, rgate)
            pool.rgate[k][r] = rgate
        end
        pool.built = k
    end
    return pool
end

-- The scroll strip's hover channel arms through a LATTICE instead of the
-- per-claim gates above: one motion gate per drawn strip POSITION. The wheel
-- decides which slot stands at a position and can change it mid-hold, so the
-- gates hold still for the whole hold and resolve position -> slot at enter
-- time from the accumulator; only the MAPPING ever moves, which is what
-- spares the sandbox any gate repositioning per tick. Entering a position
-- whose slot nests arms that slot's claim; entering one that nests nothing
-- DISARMS -- that is the strip's whole disarm, "the user specifically
-- hovered another option" -- and the empty ground beside the strip touches
-- no gate at all, which is the sticky reach. No region gates and no floor:
-- the release only fires a child while the pointer is inside its cell, so a
-- claim left armed costs a release nothing anywhere else.
local function LatticeSnippet(d)
    return (([==[
        local btn = self:GetFrameRef("btn")
        local catcher = self:GetFrameRef("catcher")
        if not btn or not catcher then return end
        if btn:GetAttribute("eqdMode") ~= "SCROLL"
           or not btn:GetAttribute("eqdFanMouse") then return end
        local n = tonumber(btn:GetAttribute("eqdShown")) or 0
        if n < 1 then return end
        local t = tonumber(catcher:GetAttribute("eqdFanTarget")) or 1
        local slot = ((t - 1 + (__D__)) % n) + 1
        btn:SetAttribute("eqdArmed",
            tonumber(btn:GetAttribute("eqdClaimAt" .. slot)))
    ]==]):gsub("__D__", tostring(d)))
end

-- Grown once to the full span rather than claim by claim: the lattice is
-- sized by the window, not by how many entries nest, and nine lean frames is
-- what the whole thing costs. Only a strip that actually nests something
-- ever builds it -- see the call in PushPalette.
function EnsureLatticeGates(index, btn)
    local pool = gatePools[index]
    if not pool or pool.lattice then return end
    pool.lattice = {}
    for d = -MAX_LATTICE, MAX_LATTICE do
        -- Named by 0-based position rather than by the signed offset, so the
        -- global name carries no minus sign; the frame REFS keep the signed
        -- offset, which is what the snippets loop.
        local g = CreateFrame("Frame",
            "EUIQuickdrawButton" .. index .. "LGate" .. (d + MAX_LATTICE),
            UIParent, "SecureHandlerEnterLeaveTemplate")
        g:SetFrameStrata(LIVE_STRATA)
        g:SetFrameLevel(20)
        GateMouse(g)
        g:Hide()
        SecureHandlerSetFrameRef(g, "btn", btn)
        SecureHandlerSetFrameRef(g, "catcher", EnsureScrollCatcher())
        -- OnEnter only: the lattice never disarms on leaving -- empty ground
        -- retains, per the sticky -- so there is no OnLeave body and the
        -- "_wrapentered" precondition the region gates work around never
        -- comes up.
        SecureHandlerWrapScript(g, "OnEnter", EnsureSecureHeader(), LatticeSnippet(d))
        SecureHandlerSetFrameRef(btn, "lgate" .. d, g)
        pool.lattice[d] = g
    end
end
end

I.EnsureGates, I.EnsureLatticeGates, I.gatePools = EnsureGates, EnsureLatticeGates, gatePools
I.broken = false
