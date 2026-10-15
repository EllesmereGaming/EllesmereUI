if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Quickdraw_Secure.lua
--
--  Secure activation: the layout model, ARM_CLAIM, the press, release and
--  cancel snippets and the cancel button.
--  Reads the earlier Quickdraw files through ns and ns._qdInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._qdInternals
-- EllesmereUIQuickdraw.lua or an earlier Quickdraw file failed to load.
if not I or I.broken then return end
I.broken = true

local MAX_LATTICE, PA, REGION_MAX = I.MAX_LATTICE, I.PA, I.REGION_MAX
local CANCEL_BUTTON, CONFIRM_BUTTON = I.CANCEL_BUTTON, I.CONFIRM_BUTTON
local EnsureScrollCatcher, EnsureSecureHeader = I.EnsureScrollCatcher, I.EnsureSecureHeader
local SetCancelButton = I.SetCancelButton

local cancelButton
I.cancelButtonSetters[#I.cancelButtonSetters + 1] = function(v) cancelButton = v end

-------------------------------------------------------------------------------
--  Secure activation
-------------------------------------------------------------------------------

-- Which steering model the snippet must use, by the same reading of the profile
-- the live view does:
--
--   ANGULAR  ARC, whether it spans a full turn or a sector of one -- chosen
--            by the angle from the centre.
--   POINTER  GRID, and either fan on pointer input -- the entry nearest the
--            cursor wins. A pointer fan is a grid one entry deep, so it is the
--            same search and the same pushed cell positions.
--   SCROLL   a scroll-steered fan. Its selection is an accumulator driven by
--            the mouse wheel rather than anything derivable from the cursor,
--            so the snippet reads the index the wheel handler left behind.
local function LayoutModel(paletteIndex)
    local p = PA(paletteIndex)
    local layout = (p and p.layout) or "ARC"
    if layout == "ARC" then return "ANGULAR" end
    if layout == "GRID" then return "POINTER" end
    -- A fan is always wheel-steered now -- see IsHoverFan.
    return "SCROLL"
end

-- Everything ARMING a claim consists of, as one fragment of snippet text
-- interpolated into all three places that can decide it: a parent gate's own
-- OnEnter (EnterSnippet), the press branch's geometric pre-arm, and
-- LeaveSnippet's re-arm on the way out of another claim. See the "Arming
-- gates" section in EUI_Quickdraw_Gates.lua for what arming means. Three
-- hand-kept copies would only have to agree with each other, and the live
-- view reads eqdArmed and nothing else -- so a copy that forgot to hide a
-- neighbour's gate or to show its own regions would draw one claim while the
-- release fired from another.
--
-- Two locals have to be in scope where this is interpolated: `btn`, the
-- palette's secure button (which carries a reference to every gate, and holds
-- eqdArmed itself), and `k`, the claim to arm. Reading `k` as a local rather
-- than baking it in is what lets the two sites where the claim index is only
-- known at run time share the fragment with EnterSnippet, where it is a
-- literal.
local ARM_CLAIM = [==[
    btn:SetAttribute("eqdArmed", k)
    -- Exclusive ground: every OTHER claim's parent gate goes dark while
    -- this one is armed, so nothing but leaving this claim's own region
    -- (see LeaveSnippet) can hand focus to a neighbour. A block layout's
    -- nest reaches over other claims' own cells, and a gate left alight
    -- there would take every reach that has to cross one.
    --
    -- Not on the ARC, where they stay alight. A claim's children live
    -- radially outside the entry ring and its ground clears the
    -- neighbouring entries' centres, so no neighbour's gate stands on
    -- ground this claim holds. Leaving them up is what lets a glide from
    -- one entry straight onto another hand over at all: rect gates cannot
    -- cover a wedge, so a cursor that has left every rect of this claim
    -- while still on its ground has nothing left to fire the leave test
    -- again, and the claim would stay armed over the entry the cursor
    -- came to rest on. (A nest set to Overflowing can be spread far
    -- enough that the reach for its outermost children crosses a
    -- neighbouring CLAIM's entry, which hands over mid-reach; Contained,
    -- the default, stops at the midpoint between the two and cannot.)
    if btn:GetAttribute("eqdMode") ~= "ANGULAR" then
        local armGm = tonumber(btn:GetAttribute("eqdGateMax")) or 0
        for armI = 1, armGm do
            if armI ~= k then
                local other = btn:GetFrameRef("pgate" .. armI)
                if other then other:Hide() end
            end
        end
    end
    -- The floor goes under the claim's ground for as long as it is armed. Two
    -- of the three sites that reach this fragment arm GEOMETRICALLY, with the
    -- cursor already standing inside the gates rather than having walked into
    -- them, and a gate shown under a still cursor never runs Blizzard's own
    -- OnEnter wrap -- which is the only thing that raises "_wrapentered", and
    -- the only thing that lets a wrapped OnLeave pre-body run at all. The
    -- sandbox cannot raise that flag for itself: RestrictedFrames' SetAttribute
    -- refuses every name that begins with an underscore. So the disarm is hung
    -- off an OnENTER instead -- which runs on motion alone, flag or no flag --
    -- and the floor is the frame that is always there to be entered. See
    -- EnsureGates.
    local fgate = btn:GetFrameRef("fgate")
    if fgate then fgate:Show() end
    for armR = 1, __REGION_MAX__ do
        local region = btn:GetFrameRef("rgate" .. k .. "_" .. armR)
        -- Only a region this open actually pushed a box for: the press
        -- branch clears an unboxed rgate's points, but this is the loop
        -- that decides whether it is shown at all, and showing one anyway
        -- would put a live gate over whatever rect it was left at by an
        -- earlier, longer-lived open.
        if region and btn:GetAttribute("eqdROHW" .. k .. "_" .. armR) then
            region:Show()
        end
    end
]==]
-- Plain substitution rather than string.format, for the same reason the
-- snippets that take this do it: their bodies are full of the modulo operator.
ARM_CLAIM = ARM_CLAIM:gsub("__REGION_MAX__", tostring(REGION_MAX))

-- Which slot a release fires is decided by where the cursor is at that instant,
-- so the decision cannot be made in Lua. Writing the chosen action onto the
-- button from an insecure PreClick fails as soon as the player is in combat:
--
--   ADDON_ACTION_BLOCKED  tried to call the protected function
--   'EUIQuickdrawButton1:SetAttribute()'
--
-- Note that SimpleFrameAPIDocumentation.lua does NOT flag
-- SetAttribute with IsProtectedFunction the way it flags ClearAttribute: that
-- flag marks methods that are protected unconditionally, and says nothing about
-- the separate rule that bites here -- a protected frame, written by tainted
-- code, during combat. Do not move this back into Lua on the strength of it.
--
-- So the choosing happens inside a secure snippet. Code in the restricted
-- environment is secure, and its SetAttribute calls are not blocked. Everything
-- the snippet needs is pushed onto the button as ordinary attributes while out
-- of combat, including the arc geometry ArcGeom already works out -- the snippet
-- does no layout maths of its own, which is what stops it drifting away from
-- HitTest as the layout options change.
--
-- A snippet body is compiled against a fixed parameter list, not as a vararg
-- function: Wrapped_Click builds the pre-body with the signature
-- "self,button,down" and the post-body with "self,message,button,down"
-- (SecureHandlers.lua:275,287). So those names are already locals here, and
-- `local button, down = ...` is a compile error -- "cannot use '...' outside a
-- vararg function" -- which surfaces only when the snippet first runs in-game.
--
-- The sandbox has no GetCursorPosition, so the cursor is read with
-- GetMousePosition on a frame handle. That measures against UIParent, NOT
-- against the palette, for two independent reasons:
--
--   * GetMousePosition goes through GetHandleFrame, which refuses a handle to an
--     unprotected frame while in combat (RestrictedFrames.lua:84). The palette is
--     an ordinary addon frame, so its handle is rejected exactly when we need it.
--   * It returns nil when the cursor lies outside the frame's rect
--     (RestrictedFrames.lua:317). Layout sizes the palette to a finite box
--     around its entries, so measuring against it would put a hard edge on a
--     gesture that is deliberately unbounded in depth: a long flick would
--     highlight an entry and then fire nothing. Against a fixed-position
--     palette the cursor could
--     start outside that box entirely.
--
-- UIParent is protected, covers the screen, and never moves. The palette's centre
-- is therefore derived rather than measured: in fixed-position mode it is
-- UIParent's centre plus the configured offset, and in cursor mode it is
-- wherever the cursor was when the palette opened -- which is the position the
-- press captured, since PositionPalette ran in our PreClick just before this.
--
-- GetMousePosition reports a [0,1] fraction of the frame measured from its
-- bottom-left, so scaling by UIParent's size gives UIParent units, and dividing
-- by the palette's own scale converts to the units radius and deadZone use.
-- sqrt is not on the sandbox whitelist; ^0.5 is the same thing.
--
-- All angles in here are DEGREES, and the step and start are handed over
-- already converted. The sandbox's atan2 is WoW's global one, which answers in
-- degrees; math.atan2, which HitTest upvalues, answers in radians. Working in
-- degrees also means the wrap is an exact 360 rather than a written-out 2*pi
-- (`pi` is not on the whitelist), which removes a real trap: a 2*pi literal
-- short by 1e-13 disagrees with HitTest's math.pi*2 often enough to land the
-- other side of the +0.5 rounding on an entry boundary.
local SNIPPET_PRE = [==[
    local ui = self:GetFrameRef("ui")
    local mode = self:GetAttribute("eqdMode")
    local catcher = self:GetFrameRef("catcher")
    local cancel = self:GetFrameRef("cancel")

    -- The Select key of a latched menu, which the press below bound to THIS
    -- button under its own mouse-button token. `button` is the only thing that
    -- separates the two clicks in here -- the palette's own keybind arrives as
    -- "LeftButton", the token SetOverrideBindingClick defaults to.
    local isConfirm = (button == "__CONFIRM_BUTTON__")
    -- ESCAPE out of a latched menu, routed to this button so the teardown below
    -- is the same one every other close runs. Both tokens only ever exist while
    -- this palette is latched: the press binds them and the close drops them.
    local isEscape = (button == "__CANCEL_BUTTON__")
    local isMenuKey = isConfirm or isEscape

    -- One palette at a time owns the screen, and the sandbox has to enforce it
    -- for itself: the Lua PreClick that refuses the second key its live view
    -- runs BEFORE this, and cannot stop the snippet behind it. The catcher, the
    -- cancel button and the ESCAPE binding are shared by every palette, so a
    -- second key's press would re-seed the strip the first one is still
    -- steering, and its release would hide the catcher and drop ESCAPE out from
    -- under a hold that is still going. The stamp lives on the cancel button --
    -- one frame every palette already holds a reference to -- and is cleared by
    -- the owner's own release (SNIPPET_POST) or by a close that never saw one
    -- (ns.Close).
    if cancel then
        local owner = cancel:GetAttribute("eqdOwner")
        local me = self:GetAttribute("eqdPalette")
        if isMenuKey then
            -- Positive ownership for a latched menu's own keys too, and it is
            -- not the same test as the release below: both bindings are
            -- registered by this palette's own press and dropped on its close,
            -- so either one reaching a palette that does not hold the screen is
            -- a binding that outlived the menu it was made for. It does nothing.
            if owner ~= me then
                self:SetAttribute("eqdWhy", "taken")
                self:SetAttribute("type", nil)
                return nil, 1
            end
        elseif down then
            if owner and owner ~= me then
                self:SetAttribute("eqdWhy", "taken")
                self:SetAttribute("type", nil)
                return nil, 1
            end
            cancel:SetAttribute("eqdOwner", me)
        elseif owner ~= me then
            -- Positive ownership, not merely "nobody else": a release whose
            -- press was refused holds the geometry of some earlier hold, and
            -- resolving a cell out of that would fire an entry off a palette
            -- that was never on screen.
            self:SetAttribute("eqdWhy", "taken")
            self:SetAttribute("type", nil)
            return nil, 1
        end
    end

    -- Neither key does anything on its press: the acting edge is the release
    -- (useOnKeyDown is pinned false on this button), and choosing here would
    -- resolve a cell one edge before the click that performs it.
    if isMenuKey and down then
        self:SetAttribute("type", nil)
        return nil, 1
    end

    -- ESCAPE out of a latched menu. It closes and fires nothing, so it skips
    -- the choosing entirely -- but it drops the latch first, which is what puts
    -- the whole of SNIPPET_POST's teardown behind it.
    if isEscape then
        self:SetAttribute("eqdLatched", nil)
        self:SetAttribute("eqdIdx", nil)
        self:SetAttribute("eqdWhy", "escaped")
        self:SetAttribute("type", nil)
        return nil, 1
    end

    if down then
        -- A latched menu whose own key is pressed again is the toggle shutting
        -- it. Only the latch is dropped here; the teardown waits for this
        -- press's RELEASE, where SNIPPET_POST already does every part of it,
        -- and dropping the latch is exactly what lets that run.
        if self:GetAttribute("eqdLatched") then
            self:SetAttribute("eqdLatched", nil)
            self:SetAttribute("eqdWhy", "toggleclose")
            self:SetAttribute("eqdIdx", nil)
            self:SetAttribute("type", nil)
            return nil, 1
        end
        self:SetAttribute("eqdWhy", "pressed")
        self:SetAttribute("eqdIdx", nil)
        -- Claim ESCAPE for as long as this palette is up, and clear whatever a
        -- previous open left on the flag. The binding is owned by the cancel
        -- button, not by us: every palette binds the same key to the same button,
        -- and one owner means one binding to drop however the palette closes.
        -- Every layout gets this -- the flag is read before any of the steering
        -- below, so escaping out is one rule, not three.
        if catcher then catcher:SetAttribute("eqdCancel", nil) end
        self:SetAttribute("eqdLatched", nil)
        if cancel then
            -- Toggle Menu Open: the menu is about to outlive the key that
            -- opened it, so the key that chooses an entry has to be claimed for
            -- as long as it is up. Owned by the cancel button along with
            -- ESCAPE, so the one ClearBindings on close hands both back
            -- together -- which is what keeps a Select key bound to a plain
            -- mouse button usable for its ordinary purpose the rest of the time.
            --
            -- BOTH have to be there to latch. A palette with the switch on and
            -- no Select key set would otherwise open a menu with nothing able
            -- to answer it, so it keeps the hold-to-fire model instead.
            local confirm = self:GetAttribute("eqdConfirm")
            local latched
            if confirm and self:GetAttribute("eqdToggle") then
                latched = true
                self:SetAttribute("eqdLatched", 1)
                cancel:SetBindingClick(true, confirm, self, "__CONFIRM_BUTTON__")
                -- ESCAPE onto THIS button rather than the cancel button, which
                -- only raises a flag for a release that is never coming here.
                -- See CANCEL_BUTTON.
                cancel:SetBindingClick(true, "ESCAPE", self, "__CANCEL_BUTTON__")
            else
                cancel:SetBindingClick(true, "ESCAPE", cancel, "LeftButton")
            end
            -- The user's own cancel key, on whichever of those two routes this
            -- open is using: a latched menu has no release to read a flag on,
            -- so its cancel has to close the menu itself (see CANCEL_BUTTON),
            -- while a held one only raises the flag its own release reads.
            -- Bound through the SAME owner as everything above, so the one
            -- ClearBindings on close hands it back with the rest -- which is
            -- what lets a plain mouse button keep its ordinary use.
            --
            -- Never over the Select key. The two would be bound to one chord
            -- and the last binding written would decide, which is a menu that
            -- cancels when the user meant to fire.
            local cancelKey = self:GetAttribute("eqdCancelKey")
            if cancelKey and cancelKey ~= confirm then
                if latched then
                    cancel:SetBindingClick(true, cancelKey, self, "__CANCEL_BUTTON__")
                else
                    cancel:SetBindingClick(true, cancelKey, cancel, "LeftButton")
                end
            end
        end
        -- Kept on the button, not in a snippet global: every palette shares one
        -- header, so a global would let palette 2's press reset palette 1's origin.
        self:SetAttribute("eqdGX", nil)
        self:SetAttribute("eqdGY", nil)
        if ui then
            local x, y = ui:GetMousePosition()
            if x then
                self:SetAttribute("eqdGX", x * ui:GetWidth())
                self:SetAttribute("eqdGY", y * ui:GetHeight())
            end
        end

        -- Nothing armed yet -- whatever this press ends up arming, it arms
        -- from the boxes pushed for THIS open, further down. A fresh press has
        -- to start from scratch: an armed claim that survived
        -- from the previous open would let a release fire a nest the palette
        -- had not even drawn yet.
        self:SetAttribute("eqdArmed", nil)
        -- Place every gate this palette pushed a box for, in the same origin
        -- the release below measures against -- cursor mode takes the point
        -- just captured above, fixed mode UIParent's centre plus the offset.
        -- Parent gates go up shown, every claim's, and region gates go down
        -- hidden, because nothing is armed at this point. The geometric
        -- pre-arm at the end of the loop is what may then take one claim's
        -- side of that straight away, and it undoes exactly the two things
        -- arming always undoes. ArmedClaim and the gates' own
        -- OnEnter/OnLeave take it from there for as long as the key is held.
        if ui then
            local ox, oy
            if self:GetAttribute("eqdFixed") then
                ox = ui:GetWidth() * 0.5 + (tonumber(self:GetAttribute("eqdPosX")) or 0)
                oy = ui:GetHeight() * 0.5 + (tonumber(self:GetAttribute("eqdPosY")) or 0)
            else
                ox = tonumber(self:GetAttribute("eqdGX"))
                oy = tonumber(self:GetAttribute("eqdGY"))
            end
            if ox then
                local s = tonumber(self:GetAttribute("eqdScale")) or 1
                if s <= 0 then s = 1 end
                local gm = tonumber(self:GetAttribute("eqdGateMax")) or 0
                for k = 1, gm do
                    local phw = tonumber(self:GetAttribute("eqdPOHW" .. k))
                    local pgate = self:GetFrameRef("pgate" .. k)
                    if phw and pgate then
                        local pox = tonumber(self:GetAttribute("eqdPOX" .. k)) or 0
                        local poy = tonumber(self:GetAttribute("eqdPOY" .. k)) or 0
                        local phh = tonumber(self:GetAttribute("eqdPOHH" .. k)) or 0
                        pgate:ClearAllPoints()
                        pgate:SetPoint("BOTTOMLEFT", ui, "BOTTOMLEFT",
                            ox + (pox - phw) * s, oy + (poy - phh) * s)
                        pgate:SetWidth(phw * 2 * s)
                        pgate:SetHeight(phh * 2 * s)
                        pgate:Show()
                    elseif pgate then
                        -- No claim at this slot this open. Cleared, not just
                        -- hidden: EnterSnippet and LeaveSnippet both Show()
                        -- gates by claim index without re-checking that the
                        -- index still has a box, so a rect left anchored from
                        -- a longer set of nests would go on answering for
                        -- ground this open does not hold at all.
                        pgate:ClearAllPoints()
                        pgate:Hide()
                    end

                    for r = 1, __REGION_MAX__ do
                        local rgate = self:GetFrameRef("rgate" .. k .. "_" .. r)
                        local rhw = tonumber(self:GetAttribute("eqdROHW" .. k .. "_" .. r))
                        if rgate and rhw then
                            local rox = tonumber(self:GetAttribute("eqdROX" .. k .. "_" .. r)) or 0
                            local roy = tonumber(self:GetAttribute("eqdROY" .. k .. "_" .. r)) or 0
                            local rhh = tonumber(self:GetAttribute("eqdROHH" .. k .. "_" .. r)) or 0
                            rgate:ClearAllPoints()
                            rgate:SetPoint("BOTTOMLEFT", ui, "BOTTOMLEFT",
                                ox + (rox - rhw) * s, oy + (roy - rhh) * s)
                            rgate:SetWidth(rhw * 2 * s)
                            rgate:SetHeight(rhh * 2 * s)
                            -- Shown from the open on the ARC, where entering
                            -- one is how a claim is armed at all -- a nest
                            -- whose only way in was its parent's own icon
                            -- could not be reached by heading straight at the
                            -- child. Every other layout leaves them down until
                            -- the claim is armed: there the parent gate is the
                            -- way in, and a region gate alight before that
                            -- would answer for ground the claim does not hold
                            -- yet.
                            if mode == "ANGULAR" then
                                rgate:Show()
                            else
                                rgate:Hide()
                            end
                        elseif rgate then
                            -- Same hygiene as the parent gate above: this
                            -- claim has fewer regions this open than it once
                            -- did (or none at all), so nothing may answer for
                            -- the rect this rgate used to cover.
                            rgate:ClearAllPoints()
                            rgate:Hide()
                        end
                    end
                end

                -- Arming is otherwise purely an OnEnter edge, and a gate
                -- SHOWN under a cursor that is already inside it raises no
                -- such edge until the cursor leaves and comes back. In cursor
                -- mode that happens on every single press: the palette opens
                -- centred on the pointer, so a middle cell sits right under
                -- it, and a claim there would have been drawn but dead. So
                -- the press asks the question geometrically instead, once,
                -- against the same parent boxes the gates were just placed
                -- from -- the answer a real OnEnter would have given had the
                -- cursor arrived from outside.
                local cgx = tonumber(self:GetAttribute("eqdGX"))
                local cgy = tonumber(self:GetAttribute("eqdGY"))
                if cgx and cgy then
                    local dx, dy = (cgx - ox) / s, (cgy - oy) / s
                    local pre
                    for k = 1, gm do
                        local phw = tonumber(self:GetAttribute("eqdPOHW" .. k))
                        if phw then
                            local pox = tonumber(self:GetAttribute("eqdPOX" .. k)) or 0
                            local poy = tonumber(self:GetAttribute("eqdPOY" .. k)) or 0
                            local phh = tonumber(self:GetAttribute("eqdPOHH" .. k)) or 0
                            if abs(dx - pox) <= phw and abs(dy - poy) <= phh then
                                pre = k
                                break
                            end
                        end
                    end
                    if pre then
                        local btn, k = self, pre
                        __ARM_CLAIM__
                    end
                end

                -- The strip's arming lattice (see EnsureLatticeGates): one
                -- motion gate per drawn POSITION, placed here once and never
                -- moved for the rest of the hold -- the wheel changes only
                -- which slot a position maps to, and the gates resolve that
                -- at enter time. Placed over exactly the positions the draw
                -- cull can show; the rest are cleared like the block gates
                -- above, and every one of them whenever the layout or the
                -- hover channel stops wanting them.
                local lm = mode == "SCROLL" and self:GetAttribute("eqdFanMouse")
                local lpitch = tonumber(self:GetAttribute("eqdPitch")) or 0
                local lband = tonumber(self:GetAttribute("eqdFanBand")) or 0
                local lwin = tonumber(self:GetAttribute("eqdFanWin")) or 0
                local lhoriz = self:GetAttribute("eqdFanHoriz")
                local ln = tonumber(self:GetAttribute("eqdShown")) or 0
                for d = -__LATTICE_MAX__, __LATTICE_MAX__ do
                    local lg = self:GetFrameRef("lgate" .. d)
                    if lg then
                        if lm and lpitch > 0 and ln > 0 and abs(d) <= lwin + 0.5
                           and d * 2 <= ln and -d * 2 < ln then
                            local lx, ly = d * lpitch, 0
                            if not lhoriz then lx, ly = 0, -(d * lpitch) end
                            lg:ClearAllPoints()
                            lg:SetPoint("BOTTOMLEFT", ui, "BOTTOMLEFT",
                                ox + (lx - lband) * s, oy + (ly - lband) * s)
                            lg:SetWidth(lband * 2 * s)
                            lg:SetHeight(lband * 2 * s)
                            lg:Show()
                        else
                            lg:ClearAllPoints()
                            lg:Hide()
                        end
                    end
                end

                -- The lattice's own geometric pre-arm, the same reasoning as
                -- the block gates' above: in cursor mode the strip opens with
                -- the pointer already standing on its centre entry, and a
                -- gate shown under a still cursor raises no OnEnter.
                if lm and lpitch > 0 and ln > 0 then
                    local pgx = tonumber(self:GetAttribute("eqdGX"))
                    local pgy = tonumber(self:GetAttribute("eqdGY"))
                    if pgx then
                        local lalong = (pgx - ox) / s
                        local lacross = (pgy - oy) / s
                        if not lhoriz then lalong, lacross = -lacross, lalong end
                        local ld = floor(lalong / lpitch + 0.5)
                        if abs(lacross) <= lband
                           and abs(lalong - ld * lpitch) <= lband
                           and abs(ld) <= lwin + 0.5
                           and ld * 2 <= ln and -ld * 2 < ln then
                            self:SetAttribute("eqdArmed",
                                tonumber(self:GetAttribute("eqdClaimAt" .. ((ld % ln) + 1))))
                        end
                    end
                end
            end
        end

        if mode == "SCROLL" and catcher then
            -- Which button the wheel snippet re-derives the hover arming
            -- for; the catcher carries a ref per palette (GetSecureButton).
            catcher:SetAttribute("eqdOwnerIdx", self:GetAttribute("eqdPalette"))
            -- 1, not nil: the strip opens centred on its first entry and that
            -- entry is selected from the outset. See the wheel snippet.
            catcher:SetAttribute("eqdFanTarget", 1)
            catcher:SetAttribute("eqdShown", self:GetAttribute("eqdShown"))
            catcher:SetAttribute("eqdInvert", self:GetAttribute("eqdInvert"))
            catcher:SetAttribute("eqdOpen", 1)
            catcher:Show()
        end
        self:SetAttribute("type", nil)
        return nil, 1
    end

    self:SetAttribute("type", nil)

    -- The release of the press that LATCHED the menu open. It chooses nothing
    -- and tears nothing down -- SNIPPET_POST leaves on the same flag -- so the
    -- menu simply stays up, which is the whole of what Toggle Menu Open means.
    -- Every other way out of a latched menu clears the latch first: the Select
    -- key below, ESCAPE through the catcher's flag, and the second press of the
    -- palette's own key.
    if self:GetAttribute("eqdLatched") and not isConfirm then
        self:SetAttribute("eqdWhy", "latched")
        return nil, 1
    end
    -- The Select key ends the menu whatever it lands on: a click into the dead
    -- zone is a decision to take nothing, the same reading a held palette gives
    -- a release there. Dropped BEFORE the choosing below so every cancel path
    -- out of it still leaves SNIPPET_POST free to tear the menu down.
    self:SetAttribute("eqdLatched", nil)

    -- The release of the press that toggled a latched menu SHUT. Its own down
    -- edge dropped the latch, which is what lets the teardown run -- and which
    -- also means the guard above cannot catch this release. Without this it
    -- goes on to resolve a cell and fire it, so pressing the menu's key to put
    -- it away would also cast whatever the pointer happened to be resting on.
    --
    -- Safe to read eqdWhy for this: the only writer of "toggleclose" is that
    -- down edge, one edge earlier, and every fresh press overwrites it with
    -- "pressed" before any release can see it again.
    if self:GetAttribute("eqdWhy") == "toggleclose" then return nil, 1 end

    -- Escaped out while the key was still held. Checked before anything is
    -- steered, so it beats every layout's own cancel and cannot be undone by
    -- moving the pointer back onto the palette.
    if catcher and catcher:GetAttribute("eqdCancel") then
        self:SetAttribute("eqdWhy", "escaped") return nil, 1
    end

    local n = tonumber(self:GetAttribute("eqdShown")) or 0
    if n < 1 then self:SetAttribute("eqdWhy", "noslots") return nil, 1 end
    -- Every cell, the palette's own entries and the nested ones after them.
    -- Which of the nested ones, if any, may actually be picked below is
    -- eqdArmed's business -- see the ANGULAR and POINTER branches -- rather
    -- than something decided here.
    local total = tonumber(self:GetAttribute("eqdTotal")) or n

    local idx
    if mode == "SCROLL" then
        -- The wheel snippet has been keeping the accumulator; the cursor plays
        -- no part in this layout, so none of the pointer work below applies.
        if not catcher then
            self:SetAttribute("eqdWhy", "nocatcher") return nil, 1
        end
        local ft = tonumber(catcher:GetAttribute("eqdFanTarget"))
        if not ft then
            -- The press seeds the accumulator, so this can only mean the press
            -- never reached the catcher. Nothing was steered; cancel.
            self:SetAttribute("eqdWhy", "unscrolled") return nil, 1
        end

        idx = ((ft - 1) % n) + 1

        -- Offset from where the pointer was when the palette opened, which is
        -- what this layout measures both its cancel and its nests from. The
        -- absolute reading and the scale are kept too: the hover test below
        -- measures from the strip's own centre, which is a different origin
        -- in fixed mode.
        local gx = tonumber(self:GetAttribute("eqdGX"))
        local gy = tonumber(self:GetAttribute("eqdGY"))
        local dx, dy, cxa, cya, sca
        if gx and ui then
            local x, y = ui:GetMousePosition()
            if x then
                local s = tonumber(self:GetAttribute("eqdScale")) or 1
                if s <= 0 then s = 1 end
                cxa, cya, sca = x * ui:GetWidth(), y * ui:GetHeight(), s
                dx = (cxa - gx) / s
                dy = (cya - gy) / s
            end
        end

        -- Into a nest, if the pointer has gone there. Before the cancel
        -- below, and not only for speed: the children sit past the ordinary
        -- margin, so a release among them reads as thrown clear until this
        -- has had its say. ONLY the ARMED claim's cells answer -- the same
        -- eqdArmed the strip's lattice gates keep and the live view draws
        -- and selects by (drawn == fired) -- anchored to its parent's own
        -- fold offset on the strip. Wheel-only keeps the old rule: the
        -- wheel's entry alone, measured from the open point.
        local hit
        if dx and self:GetAttribute("eqdFanMouse") then
            local armed = tonumber(self:GetAttribute("eqdArmed"))
            local slotA = armed and tonumber(self:GetAttribute("eqdCSlot" .. armed))
            local base = slotA and tonumber(self:GetAttribute("eqdNBase" .. slotA))
            if base then
                local dp = (slotA - idx) % n
                if dp * 2 > n then dp = dp - n end
                if abs(dp) <= (tonumber(self:GetAttribute("eqdFanWin")) or 0) + 0.5 then
                    local npitch = tonumber(self:GetAttribute("eqdPitch")) or 0
                    local nhx, nhy = gx, gy
                    if self:GetAttribute("eqdFixed") and ui then
                        nhx = ui:GetWidth() * 0.5 + (tonumber(self:GetAttribute("eqdPosX")) or 0)
                        nhy = ui:GetHeight() * 0.5 + (tonumber(self:GetAttribute("eqdPosY")) or 0)
                    end
                    if nhx and cxa then
                        local ndx = (cxa - nhx) / sca
                        local ndy = (cya - nhy) / sca
                        local sx, sy = 0, 0
                        if self:GetAttribute("eqdFanHoriz") then
                            sx = dp * npitch
                        else
                            sy = -(dp * npitch)
                        end
                        local num = tonumber(self:GetAttribute("eqdNNum" .. slotA)) or 0
                        for j = 1, num do
                            local i2 = base + j
                            local bx = tonumber(self:GetAttribute("eqdBX" .. i2))
                            local by = tonumber(self:GetAttribute("eqdBY" .. i2))
                            if bx and abs(ndx - (bx + sx)) <= (tonumber(self:GetAttribute("eqdHW" .. i2)) or 0)
                                   and abs(ndy - (by + sy)) <= (tonumber(self:GetAttribute("eqdHH" .. i2)) or 0) then
                                idx = i2
                                hit = true
                                break
                            end
                        end
                    end
                end
            end
        elseif dx then
            local base = tonumber(self:GetAttribute("eqdNBase" .. idx))
            if base then
                local num = tonumber(self:GetAttribute("eqdNNum" .. idx)) or 0
                for j = 1, num do
                    local i2 = base + j
                    local bx = tonumber(self:GetAttribute("eqdBX" .. i2))
                    local by = tonumber(self:GetAttribute("eqdBY" .. i2))
                    if bx and abs(dx - bx) <= (tonumber(self:GetAttribute("eqdHW" .. i2)) or 0)
                           and abs(dy - by) <= (tonumber(self:GetAttribute("eqdHH" .. i2)) or 0) then
                        idx = i2
                        hit = true
                        break
                    end
                end
            end
        end

        -- Exclusive hover ("Select Action with Mouse"): the release fires the
        -- entry whose drawn box the pointer is inside, and NOTHING otherwise
        -- -- the wheel's entry has no standing of its own while the channel
        -- is on. AdvanceFan publishes its selection from this identical test,
        -- so a strip showing nothing selected fires nothing. After the nests
        -- (containment there outranks the strip behind it); a hover hit skips
        -- the thrown-clear test below, being on the strip by construction.
        -- Measured from the strip's own centre: the pinned point in fixed
        -- mode, the gate in cursor mode, where the two are one point.
        if not hit and self:GetAttribute("eqdFanMouse") then
            local pitch = tonumber(self:GetAttribute("eqdPitch")) or 0
            local band = tonumber(self:GetAttribute("eqdFanBand")) or 0
            local win = tonumber(self:GetAttribute("eqdFanWin")) or 0
            local hox, hoy = gx, gy
            if self:GetAttribute("eqdFixed") and ui then
                hox = ui:GetWidth() * 0.5 + (tonumber(self:GetAttribute("eqdPosX")) or 0)
                hoy = ui:GetHeight() * 0.5 + (tonumber(self:GetAttribute("eqdPosY")) or 0)
            end
            local hovered
            if pitch > 0 and cxa and hox then
                local along = (cxa - hox) / sca
                local across = (cya - hoy) / sca
                -- NEGATED dy: a vertical strip runs downward, so below the
                -- centre is positive d. Mirrors AdvanceFan's hover test.
                if not self:GetAttribute("eqdFanHoriz") then
                    along, across = -across, along
                end
                local d = floor(along / pitch + 0.5)
                -- Inside the icon's own box on BOTH axes -- the gaps between
                -- icons fire nothing -- and only a DRAWN entry: the window
                -- bound is the draw cull's own (k <= win + 0.5, which a
                -- fractional stored window needs to agree with the strip),
                -- and the fold bound is the drawing's asymmetric one --
                -- entries land in (-n/2, n/2], so the far side of an even
                -- fold is empty ground. Mirrors AdvanceFan exactly.
                if abs(across) <= band and abs(along - d * pitch) <= band
                   and abs(d) <= win + 0.5
                   and d * 2 <= n and -d * 2 < n then
                    hovered = ((ft - 1 + d) % n) + 1
                end
            end
            if not hovered then
                self:SetAttribute("eqdWhy", "nothover") return nil, 1
            end
            idx = hovered
            hit = true
        end

        -- Thrown clear of the strip -> cancel. This is the strip's counterpart
        -- to the grid's out-of-reach: past the strip in ANY direction, measured
        -- from where the pointer was when the palette opened. The box is as
        -- long as the strip is drawn and only a margin wide, because that is
        -- the shape of the thing being left. The live view applies exactly this
        -- rule, so a strip showing nothing selected fires nothing.
        --
        -- No geometry pushed -> no box to test against, so the release stands.
        -- Firing what the user steered to is the safer of the two failures.
        local margin = tonumber(self:GetAttribute("eqdFanMargin"))
        local half = tonumber(self:GetAttribute("eqdFanHalf"))
        if not hit and dx and margin and half then
            local along, across = dx, dy
            if not self:GetAttribute("eqdFanHoriz") then
                along, across = across, along
            end
            -- Reaching toward a nest is not leaving. Only on the side that
            -- nest is on, and only while its entry is the one the wheel is on.
            local am = margin
            local na = tonumber(self:GetAttribute("eqdNAcross" .. idx))
            local ns = tonumber(self:GetAttribute("eqdNSide" .. idx))
            if na and ns and (across > 0) == (ns > 0) and na > am then am = na end
            if abs(across) > am or abs(along) > half + margin then
                self:SetAttribute("eqdWhy", "thrownclear") return nil, 1
            end
        end
    else
        if not ui then self:SetAttribute("eqdWhy", "nohandle") return nil, 1 end
        local x, y = ui:GetMousePosition()
        if not x then self:SetAttribute("eqdWhy", "offscreen") return nil, 1 end
        local w, h = ui:GetWidth(), ui:GetHeight()
        local cx, cy = x * w, y * h

        local gx = tonumber(self:GetAttribute("eqdGX"))
        local gy = tonumber(self:GetAttribute("eqdGY"))

        -- SetPoint offsets are read in the palette's own scaled space, so the
        -- centre sits exactly posX/posY UIParent units from UIParent's centre;
        -- the scale only converts the distance from there.
        local s = tonumber(self:GetAttribute("eqdScale")) or 1
        if s <= 0 then s = 1 end

        -- Opening under the cursor would otherwise arrive with an entry already
        -- chosen; nothing counts until the pointer has actually moved.
        --
        -- Divided by the scale so this is one PALETTE unit, the same unit the live
        -- views measure their gate in. Comparing raw UIParent units against 1
        -- agreed with them only at scale 1: at scale 2 a move the palette still
        -- counted as stationary was already past the snippet's threshold, and
        -- the release fired an entry the palette was drawing as unselected.
        --
        -- This does not latch, where the live views set _steered on the first
        -- movement and never re-arm. The snippet only ever sees the release, so
        -- a gesture that wanders off and returns to within a unit of where it
        -- started cancels here while the palette still shows an entry selected.
        -- It errs toward cancelling rather than firing something unintended.
        if gx and abs(cx - gx) / s < 1 and abs(cy - gy) / s < 1 then
            self:SetAttribute("eqdWhy", "unmoved") return nil, 1
        end

        local ox, oy
        if self:GetAttribute("eqdFixed") then
            ox = w * 0.5 + (tonumber(self:GetAttribute("eqdPosX")) or 0)
            oy = h * 0.5 + (tonumber(self:GetAttribute("eqdPosY")) or 0)
        elseif gx then
            ox, oy = gx, gy
        else
            self:SetAttribute("eqdWhy", "noorigin") return nil, 1
        end
        local dx, dy = (cx - ox) / s, (cy - oy) / s

        if mode == "POINTER" then
            local pitch = tonumber(self:GetAttribute("eqdPitch")) or 1
            if pitch <= 0 then pitch = 1 end

            -- The armed claim's cells first, and by CONTAINMENT: a half-extent
            -- is what marks a cell as one. Inside a box, that child regardless
            -- of what the block holds underneath; outside every box, the block
            -- answers as though the nest were not there. eqdArmed is what a
            -- gate frame's OnEnter/OnLeave has kept current for as long as the
            -- key has been held -- see EnsureGates and the press branch above --
            -- so a claim the cursor never actually entered through its parent
            -- has no cells tested here at all, however close the pointer now
            -- sits to where they are drawn.
            local armed = tonumber(self:GetAttribute("eqdArmed"))
            if armed then
                local base = tonumber(self:GetAttribute("eqdGBase" .. armed)) or 0
                local num = tonumber(self:GetAttribute("eqdGNum" .. armed)) or 0
                for j = 1, num do
                    local i = base + j
                    local hw = tonumber(self:GetAttribute("eqdHW" .. i))
                    if hw then
                        local bx = tonumber(self:GetAttribute("eqdBX" .. i)) or 0
                        local by = tonumber(self:GetAttribute("eqdBY" .. i)) or 0
                        local hh = tonumber(self:GetAttribute("eqdHH" .. i)) or 0
                        if abs(dx - bx) <= hw and abs(dy - by) <= hh then
                            idx = i
                            break
                        end
                    end
                end
            end

            -- Nearest of the palette's own, by true 2D distance in cells. A grid
            -- has no privileged axis, so projecting onto one would let sideways
            -- movement change the choice. Past eqdReach cells from every entry
            -- nothing is selected -- that is this layout's cancel, and it has no
            -- dead zone: the centre of a grid can hold an entry, so cancelling
            -- there would make the middle of an odd-sized grid unfireable.
            if not idx then
                local bestK
                for i = 1, n do
                    local bx = tonumber(self:GetAttribute("eqdBX" .. i))
                    local by = tonumber(self:GetAttribute("eqdBY" .. i))
                    if bx then
                        local px, py = (dx - bx) / pitch, (dy - by) / pitch
                        local k = (px * px + py * py) ^ 0.5
                        if not bestK or k < bestK then idx, bestK = i, k end
                    end
                end
                if bestK and bestK > (tonumber(self:GetAttribute("eqdReach")) or 1) then
                    idx = nil
                end
            end
            if not idx then
                self:SetAttribute("eqdIdx", nil)
                self:SetAttribute("eqdWhy", "outofreach") return nil, 1
            end
        else
            local dist = (dx * dx + dy * dy) ^ 0.5
            local theta = atan2(dx, dy)
            if theta < 0 then theta = theta + 360 end

            -- The armed claim's rings, and no other's -- see the note above the
            -- POINTER branch's own use of eqdArmed, and ArmedClaim on the live
            -- side. A child sector reaches past its parent entry's own, which is
            -- exactly the ground a neighbouring claim could otherwise steal
            -- before the cursor had ever gone through its own parent to earn it.
            local armed = tonumber(self:GetAttribute("eqdArmed"))
            if armed then
                local band = tonumber(self:GetAttribute("eqdCBand" .. armed))
                if band and dist >= band then
                    -- Which ring dist falls in -- Lo/Hi partition the RADIUS,
                    -- not the angle, so a ring that matches the radius but
                    -- misses the angle is the claim missing outright, not a
                    -- reason to try the next ring out.
                    local rows = tonumber(self:GetAttribute("eqdCRows" .. armed)) or 0
                    for r = 1, rows do
                        local tag = "eqdCR" .. armed .. "_" .. r
                        local lo = tonumber(self:GetAttribute(tag .. "Lo"))
                        local hi = tonumber(self:GetAttribute(tag .. "Hi"))
                        if lo and dist >= lo and (not hi or dist < hi) then
                            local cstep = tonumber(self:GetAttribute(tag .. "StepDeg")) or 0
                            local cn = tonumber(self:GetAttribute(tag .. "N")) or 0
                            if cstep > 0 and cn > 0 then
                                local crel = (theta
                                    - (tonumber(self:GetAttribute(tag .. "StartDeg")) or 0)) % 360
                                if crel < cn * cstep then
                                    idx = (tonumber(self:GetAttribute(tag .. "Base")) or 0)
                                          + floor(crel / cstep) + 1
                                end
                            end
                            break
                        end
                    end
                end
            end

            if not idx then
                local dz = tonumber(self:GetAttribute("eqdDeadZone")) or 24
                if dist < dz then
                    self:SetAttribute("eqdWhy", "deadzone") return nil, 1
                end

                local step = tonumber(self:GetAttribute("eqdStepDeg")) or 0
                if step == 0 then
                    idx = 1
                else
                    local rel = theta - (tonumber(self:GetAttribute("eqdStartDeg")) or 0)
                    if self:GetAttribute("eqdFull") then
                        idx = (floor(rel / step + 0.5) % n) + 1
                    else
                        rel = rel % 360
                        if rel <= (n - 1) * step + step * 0.5 then
                            idx = floor(rel / step + 0.5) + 1
                            -- Exactly on the arc's outer boundary rounds up
                            -- past its last entry, and the bound below cannot
                            -- catch that once the palette nests anything: with
                            -- children pushed, total is larger than n, so n + 1
                            -- is the FIRST nested cell -- which would fire
                            -- without its claim ever having been armed. HitTest
                            -- guards the same rounding the same way.
                            if idx > n then idx = nil end
                        end
                    end
                end
            end
        end
    end

    self:SetAttribute("eqdIdx", idx)
    if not idx or idx < 1 or idx > total then
        self:SetAttribute("eqdWhy", "noidx") return nil, 1
    end

    -- Stopped on a slot that opens a palette rather than going through it.
    if self:GetAttribute("eqdPal" .. idx) then
        self:SetAttribute("eqdWhy", "palette") return nil, 1
    end

    local t = self:GetAttribute("eqdT" .. idx)
    if not t then self:SetAttribute("eqdWhy", "emptyslot") return nil, 1 end

    -- Clear every action key before writing this slot's, so no earlier slot's
    -- value can outlive it: type="macro" reads "macro" before it falls through
    -- to "macrotext", and type="spell" would reuse a stale "spell" happily.
    self:SetAttribute("spell", nil)
    self:SetAttribute("item", nil)
    self:SetAttribute("macro", nil)
    self:SetAttribute("macrotext", nil)
    self:SetAttribute("toy", nil)
    self:SetAttribute("outfit-index", nil)
    -- "action" is the marker sweep's key, and type="raidtarget" falls back to
    -- "toggle" when it is unset -- so a sweep left behind would turn the next
    -- raidtarget slot into a clear-all of the whole group.
    --
    -- "marker" is the other half of that pair, read by both raidtarget and
    -- worldmarker. Every cell that uses it writes it, so no stale value can
    -- reach one of those -- but clearing it is what keeps the fallback in
    -- SECURE_ACTIONS.worldmarker honest, and the pair is only safe cleared
    -- together.
    self:SetAttribute("action", nil)
    self:SetAttribute("marker", nil)
    -- Do not toggle the active outfit off on a second press.
    if t == "outfit" then self:SetAttribute("action", "change") end

    -- A cycling entry names a different marker on every press, and the position
    -- it has reached has to advance HERE: an insecure SetAttribute is refused
    -- in combat, which is the whole of when marking matters. eqdCycPos is the
    -- position last placed, so the step is taken before it is spent, and the
    -- Lua side reads it back off this button once the release is over.
    local v = self:GetAttribute("eqdV" .. idx)
    local cn = tonumber(self:GetAttribute("eqdCycN" .. idx))
    if cn and cn > 0 then
        local pos = (tonumber(self:GetAttribute("eqdCycPos" .. idx)) or 0) % cn + 1
        self:SetAttribute("eqdCycPos" .. idx, pos)
        v = self:GetAttribute("eqdCycV" .. idx .. "_" .. pos) or v
    end
    self:SetAttribute(self:GetAttribute("eqdK" .. idx), v)
    self:SetAttribute("type", t)
    self:SetAttribute("eqdWhy", "fire")
    return nil, 1
]==]
-- REGION_MAX is baked in by plain substitution rather than string.format:
-- the body above is full of %, the modulo operator, and format would choke
-- on every one of them that is not itself a substitution.
SNIPPET_PRE = SNIPPET_PRE:gsub("__REGION_MAX__", tostring(REGION_MAX))
SNIPPET_PRE = SNIPPET_PRE:gsub("__LATTICE_MAX__", tostring(MAX_LATTICE))
-- A FUNCTION replacement rather than a plain string: gsub reads "%" in a
-- replacement string as a capture reference, and a fragment that ever grows a
-- modulo would otherwise fail here rather than where it was written.
SNIPPET_PRE = SNIPPET_PRE:gsub("__ARM_CLAIM__", function() return ARM_CLAIM end)
-- Parenthesised: gsub returns the count as a second value, and an unparenthesised
-- call in a multiple-assignment or an argument list leaks it into the next slot.
SNIPPET_PRE = (SNIPPET_PRE:gsub("__CONFIRM_BUTTON__", CONFIRM_BUTTON))
SNIPPET_PRE = (SNIPPET_PRE:gsub("__CANCEL_BUTTON__", CANCEL_BUTTON))

-- Leaves nothing armed: the next press has to choose again from scratch.
local SNIPPET_POST = [==[
    if down then return end
    self:SetAttribute("type", nil)
    -- A latched menu keeps everything standing -- the ownership stamp, the
    -- ESCAPE and Select bindings, the catcher, every gate. This is the release
    -- of the key that opened it, and the menu is meant to outlive that key.
    -- Whatever ends the menu clears the latch first, so the run that really
    -- does close it reaches the teardown below (see SNIPPET_PRE).
    if self:GetAttribute("eqdLatched") then return end
    -- Only the palette that owns the screen may put any of this away: all of it
    -- is shared, and a second key pressed during another palette's hold was
    -- refused its press (see SNIPPET_PRE), so its release has nothing of its
    -- own to tear down and would otherwise tear down the hold still in
    -- progress.
    local cancel = self:GetFrameRef("cancel")
    if cancel and cancel:GetAttribute("eqdOwner") ~= self:GetAttribute("eqdPalette") then
        return
    end
    if cancel then cancel:SetAttribute("eqdOwner", nil) end
    -- Every close funnels through here, including the cancels that returned
    -- early above, so the catcher stops eating camera zoom on all of them.
    local catcher = self:GetFrameRef("catcher")
    if catcher then
        catcher:SetAttribute("eqdOpen", nil)
        catcher:Hide()
    end
    -- Hand ESCAPE back to the game menu.
    if cancel then cancel:ClearBindings() end

    -- Every gate this palette owns, hidden and disarmed on every close --
    -- including the cancels above, for the same reason the catcher is handled
    -- unconditionally here. Nothing may leak into the next press: a region
    -- gate left shown from this hold would still be over its old ground the
    -- next time the palette opens somewhere else entirely, at least until the
    -- press branch repositions it, and eqdArmed itself would let a release on
    -- the very next open fire a claim the cursor never went near this time.
    self:SetAttribute("eqdArmed", nil)
    -- The floor first: it is the one gate that covers the whole screen, and a
    -- hold that ended with a claim armed would otherwise leave it there taking
    -- the cursor's hover away from everything under it.
    local fgate = self:GetFrameRef("fgate")
    if fgate then fgate:Hide() end
    local gm = tonumber(self:GetAttribute("eqdGateMax")) or 0
    for k = 1, gm do
        local pgate = self:GetFrameRef("pgate" .. k)
        if pgate then pgate:Hide() end
        for r = 1, __REGION_MAX__ do
            local rgate = self:GetFrameRef("rgate" .. k .. "_" .. r)
            if rgate then rgate:Hide() end
        end
    end
    -- The strip's arming lattice goes down with the rest.
    for d = -__LATTICE_MAX__, __LATTICE_MAX__ do
        local lgate = self:GetFrameRef("lgate" .. d)
        if lgate then lgate:Hide() end
    end
]==]
SNIPPET_POST = SNIPPET_POST:gsub("__REGION_MAX__", tostring(REGION_MAX))
SNIPPET_POST = SNIPPET_POST:gsub("__LATTICE_MAX__", tostring(MAX_LATTICE))

-- ESCAPE while a palette is open. It cannot be an insecure key handler: the
-- release that follows is resolved inside the snippet, and only secure code may
-- leave it a flag to read once the player is in combat. So the press snippet
-- binds ESCAPE to this button, this button's snippet raises the flag, and the
-- release finds it and fires nothing.
--
-- The button performs no action of its own -- it never gets a "type" -- so the
-- click exists purely to run this.
local SNIPPET_CANCEL = [==[
    local catcher = self:GetFrameRef("catcher")
    if catcher then
        catcher:SetAttribute("eqdCancel", 1)
        -- A scroll fan's catcher is still eating the mouse wheel, and the key
        -- may be held for a while yet. Give camera zoom back now rather than at
        -- the release, which is the same thing the release itself would do.
        catcher:SetAttribute("eqdOpen", nil)
        catcher:Hide()
    end
]==]

-- Closing the palette on screen is insecure work, and none of it is protected:
-- the frame is an ordinary addon frame.
local function OnCancelClick()
    ns.Close()
end

local function EnsureCancelButton()
    if cancelButton then return cancelButton end

    local btn = CreateFrame("Button", "EUIQuickdrawCancel", UIParent,
        "SecureActionButtonTemplate")
    -- Down only: ESCAPE should take effect the instant it is pressed, and a
    -- second run on the up edge would only re-raise a flag that is already set.
    btn:RegisterForClicks("AnyDown")
    -- Parked like the palette buttons: invisible, unclickable by mouse, and shown,
    -- because an override-binding click has to reach a live button.
    btn:EnableMouse(false)
    btn:SetSize(1, 1)
    btn:SetAlpha(0)
    btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -400, 100)
    btn:Show()
    btn:SetScript("PostClick", OnCancelClick)

    SecureHandlerSetFrameRef(btn, "catcher", EnsureScrollCatcher())
    SecureHandlerWrapScript(btn, "OnClick", EnsureSecureHeader(), SNIPPET_CANCEL)

    SetCancelButton(btn)
    return btn
end

I.ARM_CLAIM, I.EnsureCancelButton, I.LayoutModel = ARM_CLAIM, EnsureCancelButton, LayoutModel
I.SNIPPET_POST, I.SNIPPET_PRE = SNIPPET_POST, SNIPPET_PRE
I.broken = false
