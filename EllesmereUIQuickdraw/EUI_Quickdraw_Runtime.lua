if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Quickdraw_Runtime.lua
--
--  ReleaseSecureState, the click handlers and secure buttons, the push
--  onto the buttons, the override bindings, the events, ns.Refresh and
--  the lifecycle.
--  Reads the earlier Quickdraw files through ns and ns._qdInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._qdInternals
-- EllesmereUIQuickdraw.lua or an earlier Quickdraw file failed to load.
if not I or I.broken then return end
I.broken = true

local min, max = math.min, math.max
local pi = math.pi
local tonumber, type = tonumber, type
local GetBindingKey = GetBindingKey
local InCombatLockdown = InCombatLockdown

local BINDING_PREFIX, ChildIndex, DB_DEFAULTS = I.BINDING_PREFIX, I.ChildIndex, I.DB_DEFAULTS
local EnsurePalette, EQD, MAX_CHILD_ROWS = I.EnsurePalette, I.EQD, I.MAX_CHILD_ROWS
local MAX_LATTICE, MAX_PALETTES, MAX_SLOTS = I.MAX_LATTICE, I.MAX_PALETTES, I.MAX_SLOTS
local MigrateActiveProfile = I.MigrateActiveProfile
local MigrateLegacyProfile, P, PA = I.MigrateLegacyProfile, I.P, I.PA
local PaletteCount, REGION_MAX, CyclePosBack = I.PaletteCount, I.REGION_MAX, I.CyclePosBack
local CycleSteps, FireInsecure, ResolveAction = I.CycleSteps, I.FireInsecure, I.ResolveAction
local usableMemo, UsableSlots, CANCEL_BUTTON = I.usableMemo, I.UsableSlots, I.CANCEL_BUTTON
local CONFIRM_BUTTON, RefreshFonts = I.CONFIRM_BUTTON, I.RefreshFonts
local secureButtons, views, FAN_CANCEL_REACH = I.secureButtons, I.views, I.FAN_CANCEL_REACH
local GRID_REACH, CreateLiveView = I.GRID_REACH, I.CreateLiveView
local EnsureScrollCatcher, EnsureSecureHeader = I.EnsureScrollCatcher, I.EnsureSecureHeader
local ReleaseEscape, EnsureCancelButton = I.ReleaseEscape, I.EnsureCancelButton
local LayoutModel, SNIPPET_POST, SNIPPET_PRE = I.LayoutModel, I.SNIPPET_POST, I.SNIPPET_PRE
local EnsureGates, EnsureLatticeGates = I.EnsureGates, I.EnsureLatticeGates
local gatePools, SetDB, SetReleaseSecureState = I.gatePools, I.SetDB, I.SetReleaseSecureState

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
local liveView
I.liveViewSetters[#I.liveViewSetters + 1] = function(v) liveView = v end
local scrollCatcher
I.scrollCatcherSetters[#I.scrollCatcherSetters + 1] = function(v) scrollCatcher = v end
local cancelButton
I.cancelButtonSetters[#I.cancelButtonSetters + 1] = function(v) cancelButton = v end

-- Assigned below; EUI_Quickdraw_Live.lua holds the forward declaration
-- ns.Close calls through.
local ReleaseSecureState
local secureCloseDirty
local bindOwner

-- Declared beside ns.Close (EUI_Quickdraw_Live.lua): the closes that never
-- see a key-up -- the open timeout, a zone change -- have to do here everything
-- SNIPPET_POST would have done at a release, or the hold's state outlives the
-- palette. The gates are the part that shows: a parent gate left up is a
-- mouse-motion rect parked over whatever was under the palette, taking hover
-- and tooltips from it until that key is next pressed. (The floor gate heals
-- itself once eqdArmed is clear, since its own leave test then hides it, but
-- only if the cursor happens to cross it.)
--
-- Everything here is a protected frame, so a close mid-fight may touch none of
-- it. The palette is remembered instead and PLAYER_REGEN_ENABLED comes back
-- for it. Clearing the accumulator matters as much as hiding the catcher: the
-- strip opens with entry 1 seeded, so a key-up arriving after an unattended
-- close would otherwise fire that entry with nothing on screen.
function ReleaseSecureState(index)
    if InCombatLockdown() then
        -- 0 for a close with no palette of its own to put away -- the catcher
        -- and the stamp still have to be retried.
        secureCloseDirty = index or 0
        return
    end
    secureCloseDirty = nil
    if scrollCatcher then
        scrollCatcher:SetAttribute("eqdFanTarget", nil)
        scrollCatcher:SetAttribute("eqdOpen", nil)
        scrollCatcher:Hide()
    end
    -- The screen is free again, so the next press of any key may take it. See
    -- the ownership test in SNIPPET_PRE.
    if cancelButton then cancelButton:SetAttribute("eqdOwner", nil) end

    local btn = index and secureButtons[index]
    if btn then
        btn:SetAttribute("eqdArmed", nil)
        -- With this left standing the next press of the key would read as the
        -- toggle shutting a menu that is no longer on screen, and be swallowed.
        -- Refused in combat like every other write here, which is what
        -- secureCloseDirty hands to PLAYER_REGEN_ENABLED.
        btn:SetAttribute("eqdLatched", nil)
    end
    local pool = index and gatePools[index]
    if not pool then return end
    if pool.fgate then pool.fgate:Hide() end
    for k = 1, pool.built do
        local pgate = pool.pgate[k]
        if pgate then pgate:Hide() end
        local rgates = pool.rgate[k]
        for r = 1, REGION_MAX do
            local rgate = rgates and rgates[r]
            if rgate then rgate:Hide() end
        end
    end
    if pool.lattice then
        for d = -MAX_LATTICE, MAX_LATTICE do
            local lg = pool.lattice[d]
            if lg then lg:Hide() end
        end
    end
end
SetReleaseSecureState(ReleaseSecureState)

-- Defined with the push coalescer it belongs to, further down; declared here
-- because the press below has to be able to land a pending push before it
-- opens anything.
local FlushPendingPush

-- Is the live view drawing the palette this button pushed? There is one view
-- for every bound key, and only the button whose palette it is currently laid
-- out on may read a cell out of it or close it.
local function OwnsLiveView(self)
    return liveView and liveView:GetPaletteIndex() == self._palette
end

local function OnPreClick(self, button, down)
    -- A latched menu's own two keys open nothing: the menu they answer is
    -- already up. Everything they do happens in the snippet and in OnPostClick.
    if button == CONFIRM_BUTTON or button == CANCEL_BUTTON then return end
    if down then
        -- A latched menu whose key is pressed again is toggling shut, not
        -- opening. Read before the snippet, which runs after this and is what
        -- clears the flag -- so this is the last moment it still says which of
        -- the two a press is.
        if self:GetAttribute("eqdLatched") then return end
        -- Between an edit and the coalescer's timer the palette DRAWS the new
        -- contents while the button would still fire the old ones. A press is
        -- the moment that stops being tolerable, so it lands the push itself.
        -- One boolean when nothing is pending, which is every press but the
        -- one that follows an edit.
        FlushPendingPush()
        -- A second palette key pressed while the first is still HELD leaves the
        -- screen to the one already on it. The two keys' secure buttons each
        -- resolve their own release from their own pushed geometry, and there
        -- is only one live view to draw either of them with: re-laying it onto
        -- this palette would leave the held key steering a palette that is no
        -- longer drawn, and its release reading its chosen cell out of this
        -- one -- a different slot list, so a different pet, mount or spec than
        -- the one under the cursor.
        --
        -- Both halves of the button refuse it, and both have to: this one runs
        -- before the snippets and cannot stop them. Here the press that finds
        -- the screen taken opens nothing, and its own release then fires
        -- nothing insecure and closes nothing (see OnPostClick). In the
        -- sandbox the press stamps eqdOwner on the shared cancel button, and
        -- SNIPPET_PRE turns away the press and the release of any button whose
        -- eqdPalette is not that owner -- eqdWhy "taken", and no type written,
        -- so nothing fires -- while SNIPPET_POST leaves on the same test
        -- rather than hiding the catcher and dropping ESCAPE out from under
        -- the hold still going. The held key keeps the palette it opened until
        -- it is let go.
        if liveView and liveView:GetFrame():IsShown() and not OwnsLiveView(self) then
            return
        end
        ns.Open(self._palette)
        return
    end
    -- Nothing to commit here any more: all three steering models are resolved
    -- by the snippet, which is the only place allowed to write these attributes
    -- once the player is in combat.
end

local function OnPostClick(self, _, down)
    if down then return end
    -- Some kinds have no secure action type at all and fire from here. WHICH
    -- cell fires is the SNIPPET's answer, read back off the button, not the
    -- selection the live view happens to be drawing: the two part company on
    -- every cancel the snippet makes for itself. Escaping out of an open
    -- palette leaves an entry selected on screen and fires nothing, and a pet
    -- summoned out of a cancelled palette is the bug that reading the
    -- selection here produced.
    --
    -- Two of the eqdWhy steps mean "this cell was chosen": "fire", and
    -- "emptyslot" -- which is exactly what a kind with no secure action type
    -- looks like from inside the sandbox, ResolveAction having answered it
    -- nothing. Every other value is a cancel. Reading an attribute is
    -- unrestricted, so this works in combat as well as out.
    --
    -- The view has to be drawing THIS button's palette for either half of that
    -- to mean anything. CellSlot maps the snippet's index through whichever
    -- palette the view is laid out on, and a second key pressed during this
    -- hold is refused the screen rather than allowed to move it (see
    -- OnPreClick) -- so a release that does not own the view is the second
    -- key's, and it neither fires a cell of somebody else's palette nor tears
    -- down a palette its owner is still holding.
    local why = self:GetAttribute("eqdWhy")
    if not OwnsLiveView(self) then return end
    -- The release that latched the menu open closes nothing. Every other value
    -- reaching here ends it, including "toggleclose" -- the second press of the
    -- palette's own key -- which fires nothing on its way out.
    if why == "latched" then return end
    if why == "fire" or why == "emptyslot" then
        local idx = tonumber(self:GetAttribute("eqdIdx"))
        local slot = liveView:CellSlot(idx)
        FireInsecure(slot)
        -- Only "fire" moved a cycle on: "emptyslot" is a kind the sandbox has
        -- no action type for, and it never reached the snippet's step.
        if why == "fire" then CyclePosBack(self, idx, slot) end
    end
    ns.Close()
end

local function GetSecureButton(index)
    local btn = secureButtons[index]
    if btn then return btn end

    btn = CreateFrame("Button", "EUIQuickdrawButton" .. index, UIParent,
        "SecureActionButtonTemplate")
    btn._palette = index
    -- The same number the sandbox can read: the ownership test in SNIPPET_PRE
    -- and SNIPPET_POST needs to know which palette it is running for, and a
    -- plain field is invisible from inside the restricted environment. Written
    -- here, where the button is built, which is out of combat by construction
    -- -- UpdateBindings, the only caller, defers the whole rebind to
    -- PLAYER_REGEN_ENABLED while the player is fighting.
    btn:SetAttribute("eqdPalette", index)
    btn:RegisterForClicks("AnyDown", "AnyUp")

    -- SecureActionButton_OnClick performs the action on exactly one edge
    -- (SecureTemplates.lua:786-793):
    --
    --   clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)
    --
    -- Left unset, useOnKeyDown follows the ActionButtonUseKeyDown CVar, which
    -- is on by default -- so the DOWN edge would be the acting one. DOWN is
    -- where we open the palette and clear "type", so it fires nothing, and UP is
    -- then skipped entirely: PreClick and PostClick still run, so the palette
    -- opens and closes normally while no action is ever performed. Pinning the
    -- attribute keeps the acting edge on UP whatever the CVar says.
    btn:SetAttribute("useOnKeyDown", false)
    -- Parked off-screen and invisible, but shown: an override-binding click
    -- has to reach a live button, and the suite's click-cast proxies use the
    -- same shape (EUI_RaidFrames_ClickCast.lua).
    btn:EnableMouse(false)
    btn:SetSize(1, 1)
    btn:SetAlpha(0)
    btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -300 - index * 4, 100)
    btn:Show()
    btn:SetScript("PreClick", OnPreClick)
    btn:SetScript("PostClick", OnPostClick)

    -- The snippet measures the cursor against the palette, so it needs a handle to
    -- it. Wrapped around OnClick rather than PreClick: PreClick is ours, and the
    -- wrap has to run inside the very click that goes on to fire the action.
    SecureHandlerSetFrameRef(btn, "ui", UIParent)
    SecureHandlerSetFrameRef(btn, "catcher", EnsureScrollCatcher())
    SecureHandlerSetFrameRef(btn, "cancel", EnsureCancelButton())
    -- The other direction too: the wheel snippet re-derives the hover-armed
    -- nest and needs this button's geometry to do it; the press stamps
    -- eqdOwnerIdx on the catcher so it knows which ref to read.
    SecureHandlerSetFrameRef(EnsureScrollCatcher(), "btn" .. index, btn)
    SecureHandlerWrapScript(btn, "OnClick", EnsureSecureHeader(),
        SNIPPET_PRE, SNIPPET_POST)

    secureButtons[index] = btn
    return btn
end

-- Hand the sandbox everything it needs to choose a entry. Out of combat only:
-- these are ordinary insecure writes to a protected frame, which is precisely
-- what combat forbids. A palette edited mid-fight keeps firing its previous
-- contents until the fight ends -- the same bargain the override bindings make.
-- How many cells each button was last given, so a palette that loses a nest
-- clears the entries that nest used to occupy.
local pushedCells = {}

-- The most claims this button has ever been pushed, per palette. Never
-- shrinks: see the eqdGateMax write below.
local pushedClaims = {}

-- One cell's action. Both the palette's own entries and the cells its nests
-- contribute are pushed through here, under the cell index the snippet will
-- resolve a release to -- which is what lets the snippet fire either without
-- knowing which of the two it landed on.
local function PushCell(btn, i, slot, p)
    local aType, aKey, aVal = ResolveAction(slot, p)
    btn:SetAttribute("eqdT" .. i, aType)
    btn:SetAttribute("eqdK" .. i, aKey)
    btn:SetAttribute("eqdV" .. i, aVal)
    -- A palette resolves to no action, same as an empty slot. Marked so the
    -- trace can tell "you stopped on the door" from "that slot is empty".
    btn:SetAttribute("eqdPal" .. i, ChildIndex(slot) and true or nil)

    -- A cycling entry's whole run, one step per attribute, plus the position it
    -- is up to. Written out rather than parsed in the snippet: the marker order
    -- and the engine's numbering already live up in the slot model, and the
    -- restricted environment is the last place to restate either of them.
    --
    -- eqdCycN is what marks the cell as cycling, so a cell that has stopped
    -- being one has to lose it -- and the steps under it, which are read by
    -- position and would otherwise outlive a shorter run.
    local steps = CycleSteps(slot and slot.kind)
    local had = tonumber(btn:GetAttribute("eqdCycN" .. i)) or 0
    for s = 1, max(had, steps and #steps or 0) do
        btn:SetAttribute("eqdCycV" .. i .. "_" .. s, steps and steps[s] or nil)
    end
    btn:SetAttribute("eqdCycN" .. i, steps and #steps or nil)
    btn:SetAttribute("eqdCycPos" .. i, steps and tonumber(slot.cyclePos) or nil)
end

local function PushPalette(index)
    if InCombatLockdown() then return end
    local p = PA(index)
    local btn = secureButtons[index]
    local palette = EnsurePalette(index)
    if not p or not btn or not palette then return end

    -- Every measurement below is the live view's, and a keybound palette is
    -- pushed long before it is ever opened, so the view has to exist by here
    -- rather than by the first Open. Past the button guard above, so a module
    -- switched off -- which registers no bindings and therefore builds no
    -- buttons -- still builds no frames at all.
    CreateLiveView()

    -- The view is laid out for whatever was last DRAWN, which on a push over
    -- every bound palette in turn is almost never this one -- and appearance
    -- is per palette, so every measurement it makes below would otherwise be
    -- taken against some other palette's layout. appIndex points its own
    -- profile accessor at this palette for the length of the push. There is no
    -- early return past here; the clear at the bottom is unconditional.
    liveView.appIndex = index

    -- The usable view, same as the live drawing reads (Hide Unusable
    -- Entries): what a cell index fires and what it draws have to come off
    -- the same list, and the memo behind UsableSlots is what pins the two
    -- together between this push and any open that follows it.
    local slotsEff = UsableSlots(palette, p)
    for i = 1, MAX_SLOTS do
        PushCell(btn, i, slotsEff[i], p)
        -- Ahead of the first open rather than at it: a load is a server round
        -- trip, and this runs at login and on every spellbook or macro change,
        -- so the palette has its icons long before anyone holds the key.
        ns.WarmSlot(slotsEff[i])
    end

    -- The live palette draws exactly what the palette holds -- the trailing "+"
    -- entry is the editor's -- so #slots is the count the snippet divides by, and
    -- ArcGeom is asked for the geometry rather than the snippet re-deriving it.
    local n = #slotsEff
    local step, arcStart, full = liveView:ArcGeom(n)
    local _, _, deadZone = liveView:Geom()
    -- Where the palette's centre will be, so the snippet can work in UIParent
    -- units without a handle to the palette itself. Cursor mode has no fixed
    -- centre, so the snippet takes the opening cursor position instead.
    btn:SetAttribute("eqdFixed", p.centerMode == "SCREEN")
    btn:SetAttribute("eqdPosX", p.posX or 0)
    btn:SetAttribute("eqdPosY", p.posY or 0)
    btn:SetAttribute("eqdScale", p.scale or 1)

    local model = LayoutModel(index)
    btn:SetAttribute("eqdMode", model)
    btn:SetAttribute("eqdShown", n)
    btn:SetAttribute("eqdInvert", p.fanInvert == true)

    -- Toggle Menu Open, and the key a latched menu answers to. Both are read by
    -- the press branch of SNIPPET_PRE, which latches only when it has the two of
    -- them -- so a palette left half-configured keeps the hold-to-fire model
    -- rather than opening a menu nothing can choose from.
    --
    -- The Select key comes off the profile rather than the palette: p is the
    -- appearance view, and a key that is not an APPEARANCE_KEY falls through it
    -- to the profile, which is where this one lives.
    btn:SetAttribute("eqdToggle", p.toggleMode == true or nil)
    local confirmKey = p.confirmKey
    btn:SetAttribute("eqdConfirm",
        (type(confirmKey) == "string" and confirmKey ~= "") and confirmKey or nil)
    -- Same story for the cancel key, and from the same place in the profile.
    local cancelKey = p.cancelKey
    btn:SetAttribute("eqdCancelKey",
        (type(cancelKey) == "string" and cancelKey ~= "") and cancelKey or nil)

    -- Pointer layouts: the cell centres, worked out here rather than in the
    -- snippet. GridDims and GridBase already encode the auto-column rule and the
    -- short-final-row centring, and re-deriving either in the sandbox would give
    -- the palette a second, drifting copy of the layout -- the same mistake the
    -- angular path avoids by pushing ArcGeom's answer.
    if model == "POINTER" then
        local _, iconSize = liveView:Geom()
        local pitch = iconSize + (p.fanGap or 10)
        local cols, rows = liveView:GridDims(n)
        for i = 1, MAX_SLOTS do
            if i <= n then
                local bx, by = liveView:GridBase(i, cols, rows, pitch, n)
                btn:SetAttribute("eqdBX" .. i, bx)
                btn:SetAttribute("eqdBY" .. i, by)
            else
                btn:SetAttribute("eqdBX" .. i, nil)
                btn:SetAttribute("eqdBY" .. i, nil)
            end
            -- A half-extent is what marks a cell as a nest, and the nests are
            -- written after this. Cleared over the palette's OWN range too: a
            -- longer set of nests last time would otherwise leave half-extents
            -- on indices that are now ordinary entries, and those entries would
            -- answer to containment instead of taking their turn at nearness.
            btn:SetAttribute("eqdHW" .. i, nil)
            btn:SetAttribute("eqdHH" .. i, nil)
        end
        btn:SetAttribute("eqdPitch", pitch)
        btn:SetAttribute("eqdReach", GRID_REACH)
    end

    -- The scroll fan's cancel box: a margin across, the drawn strip plus that
    -- same margin along, and the axis it runs on. Three numbers rather than the
    -- pointer layouts' table of cells, the strip having only one axis to steer.
    if model == "SCROLL" then
        local _, iconSize = liveView:Geom()
        btn:SetAttribute("eqdFanMargin",
                         FAN_CANCEL_REACH * (iconSize + (p.fanGap or 10)))
        btn:SetAttribute("eqdFanHalf", liveView:FanHalfLength())
        btn:SetAttribute("eqdFanHoriz", liveView:FanHoriz())
        -- The hover channel ("Select Action with Mouse"): the snippet re-runs
        -- AdvanceFan's arithmetic at release, so it needs the same numbers --
        -- the strip's pitch, the on-strip band (half an icon), and the drawn
        -- window it must not pick beyond. nil when the channel is off, so the
        -- snippet's gate is one attribute read.
        if p.fanMouseSelect ~= false then
            btn:SetAttribute("eqdFanMouse", 1)
            btn:SetAttribute("eqdPitch", iconSize + (p.fanGap or 10))
            btn:SetAttribute("eqdFanBand", iconSize * 0.5)
            btn:SetAttribute("eqdFanWin", p.fanVisible or 2)
        else
            btn:SetAttribute("eqdFanMouse", nil)
        end
    end
    btn:SetAttribute("eqdDeadZone", deadZone)
    -- Degrees, not the radians ArcGeom deals in. The sandbox whitelists WoW's
    -- GLOBAL atan2 (RestrictedEnvironment.lua:60), which answers in DEGREES --
    -- where HitTest upvalues math.atan2, which answers in radians. Treating the
    -- sandbox's as radians silently rotated every selection: a release aimed at
    -- one entry fired its neighbour, and a release near the arc's edge missed
    -- entirely. Converting here keeps the one conversion in Lua, where the unit
    -- is named, and lets the snippet wrap on an exact 360.
    btn:SetAttribute("eqdStepDeg", step * 180 / pi)
    btn:SetAttribute("eqdStartDeg", arcStart * 180 / pi)
    btn:SetAttribute("eqdFull", full)

    -- Nested entries. They are appended to the SAME action table the palette's
    -- own entries use, starting past the last of them, so the firing end of the
    -- snippet needs no idea that nesting exists: a child is a cell with a higher
    -- index. Only the claim geometry that maps an angle onto one of those
    -- indices is new.
    --
    -- The loop above has already cleared indices n+1 .. MAX_SLOTS, which is
    -- where these land, so the writes must come after it.
    local claims = liveView:ChildGeom(n, slotsEff)

    -- How far every claim-indexed loop below, and every snippet loop that
    -- reads eqdGateMax, runs. MAX_SLOTS is what a palette could hold; this is
    -- what one has actually held at some point this session, and a palette
    -- that nests nothing keeps it at zero -- which is the common case and the
    -- difference between a few hundred attribute writes per push and none.
    --
    -- MONOTONIC, and that is the whole of its correctness. Every snippet that
    -- clears, hides or re-shows gates walks 1..eqdGateMax, so an index that
    -- was ever pushed a box or a gate for has to stay inside the bound for the
    -- rest of the session; the loops below then nil that index's attributes
    -- and the press branch clears its gate's points, exactly as they did when
    -- the bound was MAX_SLOTS. Lowering it to today's claim count instead
    -- would strand a live gate at yesterday's rect with nothing left to clear
    -- it.
    local gateMax = max(pushedClaims[index] or 0, claims and #claims or 0)
    pushedClaims[index] = gateMax
    -- The arming gates. Built out of combat like everything else here, grown
    -- to the same mark, and reused and merely repositioned afterwards. See the
    -- "Arming gates" section in EUI_Quickdraw_Gates.lua for what they are for.
    EnsureGates(index, btn, gateMax)
    btn:SetAttribute("eqdGateMax", gateMax)

    local total = n
    for k = 1, (claims and #claims or 0) do
        local c = claims[k]
        c.base = total
        for j = 1, c.n do
            total = total + 1
            PushCell(btn, total, c.slots[j], p)
            -- A palette reached only by being nested carries no keybind, so it
            -- gets no push of its own and this is the only warm its entries see.
            ns.WarmSlot(c.slots[j])
            -- A block layout's nests carry a BOX. Half-extents are what tells
            -- the snippet these cells are tested by containment rather than by
            -- nearness -- the palette's own entries have no half-extents, and
            -- fall to the nearest-cell search below.
            if c.cells then
                local b = c.cells[j]
                btn:SetAttribute("eqdBX" .. total, b.x)
                btn:SetAttribute("eqdBY" .. total, b.y)
                btn:SetAttribute("eqdHW" .. total, b.hw)
                btn:SetAttribute("eqdHH" .. total, b.hh)
            end
        end
    end
    -- Whatever a longer set of nests left behind last time. Bounded by what was
    -- actually written rather than by the theoretical maximum, so an ordinary
    -- palette does not pay a hundred attribute writes on every options tick.
    for i = max(total, MAX_SLOTS) + 1, (pushedCells[index] or 0) do
        -- nil for the slot, which is also how PushCell clears a cycle's steps.
        PushCell(btn, i, nil, p)
        btn:SetAttribute("eqdBX" .. i, nil)
        btn:SetAttribute("eqdBY" .. i, nil)
        btn:SetAttribute("eqdHW" .. i, nil)
        btn:SetAttribute("eqdHH" .. i, nil)
    end
    pushedCells[index] = total
    btn:SetAttribute("eqdTotal", total)

    -- One claim-index -> cell-range mapping, the parent's own arming box, and
    -- up to REGION_MAX region boxes, for every possible claim slot -- cleared
    -- past #claims the same way the gates themselves get cleared, so a claim
    -- that stopped nesting cannot leave its gate armable over ground that no
    -- longer holds anything. Keyed by CLAIM INDEX rather than by parent slot,
    -- the same index eqdCBand and friends already use below, so eqdArmed
    -- means one thing everywhere it is read regardless of layout.
    for k = 1, gateMax do
        local c = claims and claims[k]
        btn:SetAttribute("eqdGBase" .. k, c and c.base)
        btn:SetAttribute("eqdGNum" .. k, c and c.n)
        local pb = c and c.parentBox
        btn:SetAttribute("eqdPOX" .. k, pb and pb.x)
        btn:SetAttribute("eqdPOY" .. k, pb and pb.y)
        btn:SetAttribute("eqdPOHW" .. k, pb and pb.hw)
        btn:SetAttribute("eqdPOHH" .. k, pb and pb.hh)
        for r = 1, REGION_MAX do
            local rb = c and c.regions and c.regions[r]
            btn:SetAttribute("eqdROX" .. k .. "_" .. r, rb and rb.x)
            btn:SetAttribute("eqdROY" .. k .. "_" .. r, rb and rb.y)
            btn:SetAttribute("eqdROHW" .. k .. "_" .. r, rb and rb.hw)
            btn:SetAttribute("eqdROHH" .. k .. "_" .. r, rb and rb.hh)
        end
    end

    -- A scroll-steered strip reaches its nests through the entry the WHEEL is
    -- on in wheel-only steering, and through the ARMED claim under the hover
    -- channel; the cursor only ever says which of the children. One lookup per
    -- entry that nests, so the snippet goes straight from either answer to
    -- that nest's boxes -- eqdClaimAt maps a slot to its claim (what the
    -- lattice gates arm), eqdCSlot maps a claim back to its slot (what the
    -- release reads the boxes through).
    if model == "SCROLL" then
        for i = 1, MAX_SLOTS do
            btn:SetAttribute("eqdNBase" .. i, nil)
            btn:SetAttribute("eqdNNum" .. i, nil)
            btn:SetAttribute("eqdNAcross" .. i, nil)
            btn:SetAttribute("eqdNSide" .. i, nil)
            btn:SetAttribute("eqdClaimAt" .. i, nil)
        end
        for k = 1, gateMax do
            btn:SetAttribute("eqdCSlot" .. k, nil)
        end
        for k = 1, (claims and #claims or 0) do
            local c = claims[k]
            btn:SetAttribute("eqdNBase" .. c.parent, c.base)
            btn:SetAttribute("eqdNNum" .. c.parent, c.n)
            btn:SetAttribute("eqdNAcross" .. c.parent, c.across)
            btn:SetAttribute("eqdNSide" .. c.parent, c.sign)
            btn:SetAttribute("eqdClaimAt" .. c.parent, k)
            btn:SetAttribute("eqdCSlot" .. k, c.parent)
        end
        if claims then EnsureLatticeGates(index, btn) end
    end

    -- One ANGULAR claim per slot that opens a palette, and one RING per claim
    -- past MAX_CHILD_ROWS never happens (ChildGeom caps there too), so every
    -- claim's rings fit in this fixed span of attributes. Angles in degrees,
    -- and a ring's start is the EDGE of its first child's sector rather than
    -- its centre, so the snippet's test is a plain division with no half-step
    -- to remember.
    --
    -- A block layout's nests need none of this: they were pushed as ordinary
    -- cells above, and the nearest-cell search finds them without being told
    -- that they are nests at all.
    local angular = (model == "ANGULAR") and claims or nil
    for k = 1, gateMax do
        local c = angular and angular[k]
        btn:SetAttribute("eqdCBand" .. k, c and c.band)
        btn:SetAttribute("eqdCRows" .. k, c and #c.rows)
        -- The claim's own ground -- the beam and the wedge ChildGeom sized --
        -- for the DISARM test only. LeaveSnippet asks "is the cursor still on
        -- this claim" and never walks the rings the release below does: the
        -- ground has to include the ring's own radius and the sides of the
        -- parent's icon, which answer to no ring at all, and while they
        -- belonged to nothing every reach for a child disarmed the claim a few
        -- units into itself.
        local g = c and c.ground
        btn:SetAttribute("eqdCAngle" .. k, g and ((c.angle * 180 / pi) % 360))
        btn:SetAttribute("eqdCAX" .. k, g and g.ax)
        btn:SetAttribute("eqdCAY" .. k, g and g.ay)
        btn:SetAttribute("eqdCLo" .. k, g and g.lo)
        btn:SetAttribute("eqdCEdge" .. k, g and g.edge)
        btn:SetAttribute("eqdCBeam" .. k, g and g.beam)
        btn:SetAttribute("eqdCSlope" .. k, g and g.slope)
        btn:SetAttribute("eqdCWedge" .. k, g and (g.half * 180 / pi))
        for r = 1, MAX_CHILD_ROWS do
            local row = c and c.rows[r]
            local tag = "eqdCR" .. k .. "_" .. r
            btn:SetAttribute(tag .. "Lo", row and row.lo)
            btn:SetAttribute(tag .. "Hi", row and row.hi)
            btn:SetAttribute(tag .. "N", row and row.n)
            -- Absolute: the cell index this ring's first child lands on, so the
            -- snippet adds nothing but the local offset it works out itself.
            btn:SetAttribute(tag .. "Base", row and (c.base + row.base))
            btn:SetAttribute(tag .. "StepDeg", row and (row.step * 180 / pi))
            btn:SetAttribute(tag .. "StartDeg",
                row and ((((row.start - row.step * 0.5) * 180 / pi) % 360)))
        end
    end
    btn:SetAttribute("eqdClaims", angular and #angular or 0)

    -- Back to whatever the view is actually drawing.
    liveView.appIndex = nil
end

-- Raised whenever a push was wanted and combat refused it, cleared by the push
-- that finally lands. PLAYER_REGEN_ENABLED reads it rather than pushing
-- unconditionally, the same bargain bindingsDirty makes below.
local pushDirty = false

-- Bound palettes only: nested ones have no button of their own, and their
-- entries are pushed as part of whichever palette nests them.
local function PushAllPalettes()
    if InCombatLockdown() then
        pushDirty = true
        return
    end
    pushDirty = false
    -- The one place usability answers are allowed to change -- see usableMemo.
    wipe(usableMemo)
    -- Same lifecycle, same reason -- see the Dynamic Profession section.
    if ns.WipeProfessionCache then ns.WipeProfessionCache() end
    for i = 1, PaletteCount() do PushPalette(i) end
end

-- A push is on the order of a thousand attribute writes per bound palette, and
-- the options panel reaches Refresh on every slider tick -- so a drag would pay
-- for one per frame while the sandbox only ever reads the last of them. One
-- deferred push serves the whole drag: the first request in a quiet window
-- schedules the run, and every request inside that window folds into it.
--
-- Only the pushed geometry is deferred. UpdateBindings and the redraw of any
-- view on screen stay where Refresh calls them, so the preview still tracks the
-- slider live.
local PUSH_DELAY = 0.15
local pushQueued = false

local function RequestPush()
    -- Nothing to schedule: the writes are refused for as long as the fight
    -- lasts, and PLAYER_REGEN_ENABLED is what picks this up.
    if InCombatLockdown() then
        pushDirty = true
        return
    end
    if pushQueued then return end
    pushQueued = true
    C_Timer.After(PUSH_DELAY, function()
        -- A press already landed this one. The timer is left to run into the
        -- lowered flag rather than cancelled: that costs one comparison and
        -- keeps no timer handle anywhere for a later request to have to
        -- reason about.
        if not pushQueued then return end
        pushQueued = false
        PushAllPalettes()
    end)
end

-- Land a pending push NOW rather than at the end of its window. Called by the
-- press, so a key can never fire geometry the palette has stopped drawing --
-- and so an edit followed straight into a fight cannot strand the old actions
-- for the whole of it, which waiting out the window could.
--
-- In combat PushAllPalettes refuses as it always has and raises pushDirty
-- instead, so the pending state is handed to PLAYER_REGEN_ENABLED rather than
-- dropped.
FlushPendingPush = function()
    if not pushQueued then return end
    pushQueued = false
    PushAllPalettes()
end

local bindingsDirty = false
local bindingSig = nil

-------------------------------------------------------------------------------
--  Modifier variants of a palette's key
--
--  A keybind matches ONE modifier combination exactly, and the palette performs
--  its action on the RELEASE edge. With only the configured combination bound,
--  the modifiers held at that release are therefore pinned to whatever the bind
--  itself requires -- shift is down for the whole of a SHIFT- bind, and an
--  unmodified bind is only reachable with nothing held at all.
--
--  That decides what a macro fires. SECURE_ACTIONS.macro hands the name to
--  RunMacro (SecureTemplates.lua:441-455), which evaluates the body's
--  conditionals live at that moment -- as does the macrotext branch beside it
--  -- so a slot holding
--
--      /cast [nomod] Anu'relos, Flame's Guidance; Alabaster Stormtalon
--
--  can only ever take one of its two branches: the [nomod] one on an unmodified
--  bind, the other on a modified one. Nothing here caches or flattens the
--  macro -- the pinned modifier state is the whole of it.
--
--  So every combination of the key is bound to the same button, and the player
--  can press or let go of a modifier during the hold. Only combinations nothing
--  else holds are taken: this hands the palette keys that were going spare, it
--  does not take keys away.
-------------------------------------------------------------------------------

-- The combinations, written the way the client composes a key string
-- (Blizzard_SharedXML/KeyCommand.lua:9-25 -- ALT, then CTRL, then SHIFT).
local MOD_COMBOS = {
    "", "ALT-", "CTRL-", "ALT-CTRL-",
    "SHIFT-", "ALT-SHIFT-", "CTRL-SHIFT-", "ALT-CTRL-SHIFT-",
}

-- The same prefixes plus META, to take back off a key the player bound with
-- one. META is stripped but never re-added: a macro's [mod] conditionals know
-- shift, ctrl and alt only, so the eight combinations above are the whole of
-- what changes what a slot fires. The gap that leaves is the Command key on a
-- Mac -- pressed during a hold, it still costs that hold its release.
local MOD_STRIP = { "ALT-", "CTRL-", "SHIFT-", "META-" }

local function BaseKey(key)
    for i = 1, #MOD_STRIP do
        local m = MOD_STRIP[i]
        if key:sub(1, #m) == m then key = key:sub(#m + 1) end
    end
    return key
end

-- Held by nothing the player would miss. GetBindingAction answers the BASE
-- binding, leaving override bindings out -- ours and any other addon's alike --
-- which is what this wants: our own overrides are the thing being decided here,
-- so counting them would make the answer depend on whether this had already run
-- once, and the last writer wins between addons either way.
--
-- A CLICK binding onto one of our own buttons is answered as free rather than
-- taken, for the case where that is wrong. It only reaches this line at all if
-- overrides ARE counted, and the cost of assuming they are not would be a key
-- the player takes back in the Keybindings panel and never gets: the signature
-- would already read it as taken, so nothing would rebuild and the override
-- would keep shadowing their new binding until a reload.
local function KeyIsFree(key)
    local action = GetBindingAction(key)
    if action == nil or action == "" then return true end
    return action:find("^CLICK EUIQuickdrawButton") ~= nil
end

-- Which combinations of a key are ours to take, as eight characters of the
-- binding signature. They belong in it: a combination the player later binds to
-- something else has to be handed straight back, and UPDATE_BINDINGS is the
-- only notice of that arriving.
local function ModifierSig(key)
    if not key then return "" end
    local base, out = BaseKey(key), "|"
    for i = 1, #MOD_COMBOS do
        out = out .. (KeyIsFree(MOD_COMBOS[i] .. base) and "1" or "0")
    end
    return out
end

-- `claimed` carries the keys already spoken for across the whole pass, so no
-- palette's variant can land on top of a key another palette was given.
local function BindWithModifiers(name, key, claimed)
    if not key then return end
    local base = BaseKey(key)
    -- What the player is already holding to press this key at all. Only
    -- combinations that keep ALL of it are ours: the point of the variants is
    -- that a hold survives a modifier picked up DURING it, and dropping one the
    -- binding requires is a different gesture entirely. Without this, a palette
    -- on SHIFT-T also took plain T whenever T was free -- an opening the player
    -- never asked for, on a key they left alone.
    local mods = key:sub(1, #key - #base)
    -- META is in MOD_STRIP but not in MOD_COMBOS, so a key bound with it has no
    -- variant that keeps it. Pass 1 has already bound the key itself; leave it
    -- at that rather than hand out combinations that all drop the Command key.
    if mods:find("META-", 1, true) then return end
    local alt   = mods:find("ALT-",   1, true) ~= nil
    local ctrl  = mods:find("CTRL-",  1, true) ~= nil
    local shift = mods:find("SHIFT-", 1, true) ~= nil
    for i = 1, #MOD_COMBOS do
        local combo = MOD_COMBOS[i]
        if (not alt   or combo:find("ALT-",   1, true))
           and (not ctrl  or combo:find("CTRL-",  1, true))
           and (not shift or combo:find("SHIFT-", 1, true)) then
            local k = combo .. base
            if not claimed[k] and KeyIsFree(k) then
                SetOverrideBindingClick(bindOwner, false, k, name)
                claimed[k] = true
            end
        end
    end
end

-- ClearOverrideBindings / SetOverrideBindingClick are protected, so a combat
-- refresh is deferred to PLAYER_REGEN_ENABLED. Nothing is lost by waiting:
-- the bindings already in place keep working until then.
--
-- The signature guard is required for correctness, not an optimisation.
-- Registering an override binding itself fires UPDATE_BINDINGS, and
-- UPDATE_BINDINGS is what brings us here -- so an unconditional rewrite feeds
-- itself forever. Action Bars hit exactly this and solved it the same way (see
-- the note at EllesmereUIActionBars.lua:10486). It also makes the call free for
-- the options panel, which reaches Refresh on every slider tick.
function ns.UpdateBindings()
    local p = P()
    if not p then return end

    local sig = p.enabled and "on" or "off"
    local count = PaletteCount()
    for i = 1, count do
        local k1, k2 = GetBindingKey(BINDING_PREFIX .. i)
        sig = sig .. "|" .. (k1 or "") .. "/" .. (k2 or "")
        sig = sig .. ModifierSig(k1) .. ModifierSig(k2)
    end
    if sig == bindingSig then return end

    if InCombatLockdown() then
        bindingsDirty = true
        return
    end
    bindingsDirty = false
    bindingSig = sig

    -- No owner means nothing has ever been bound through one, so there is
    -- nothing to clear -- and building one anyway is the single frame that
    -- would keep a never-enabled session from costing nothing at all.
    if bindOwner then ClearOverrideBindings(bindOwner) end
    if not p.enabled then return end
    if not bindOwner then bindOwner = CreateFrame("Frame") end

    -- A button is built only for a palette that has a key, so a profile that
    -- binds two of its sixteen pays for two. PushPalette skips an index with no
    -- button, so the ones left unbound cost no attribute writes either -- their
    -- entries still reach the sandbox through whichever palette nests them.
    --
    -- Two passes, and the order is what makes them right: every key the player
    -- actually chose is placed first, so a modifier variant one palette would
    -- like can never land on top of a key another palette was GIVEN, whichever
    -- order the two palettes come in.
    --
    -- `claimed` is built here rather than kept and wiped: every
    -- SetOverrideBindingClick below fires UPDATE_BINDINGS, which re-enters this
    -- function, and a table shared with that call is one the re-entry could
    -- clear halfway through the loop reading it. The signature it computes is
    -- the one just stored -- GetBindingAction answers base bindings, which none
    -- of these writes touch -- so it turns back at the guard and this stays the
    -- only pass; the table is what makes that true by construction rather than
    -- by argument. One per rebind, and a rebind is a keybind change.
    local built = false
    local claimed = {}
    for i = 1, count do
        local k1, k2 = GetBindingKey(BINDING_PREFIX .. i)
        if k1 or k2 then
            built = built or not secureButtons[i]
            local name = GetSecureButton(i):GetName()
            if k1 then
                SetOverrideBindingClick(bindOwner, false, k1, name)
                claimed[k1] = true
            end
            if k2 then
                SetOverrideBindingClick(bindOwner, false, k2, name)
                claimed[k2] = true
            end
        end
    end
    for i = 1, count do
        local k1, k2 = GetBindingKey(BINDING_PREFIX .. i)
        if k1 or k2 then
            local name = secureButtons[i]:GetName()
            BindWithModifiers(name, k1, claimed)
            BindWithModifiers(name, k2, claimed)
        end
    end

    -- A button built just now holds none of its palette's geometry yet, and the
    -- binding change that built it is not itself a reason for anything else to
    -- ask for a push. Without this, the first hold on a freshly bound key would
    -- open an empty palette.
    if built then RequestPush() end
end

-------------------------------------------------------------------------------
--  Events
--
--  Registered only while the module is switched ON. A session that never
--  enables it dispatches nothing: UPDATE_BINDINGS alone fires on every keybind
--  save and on every override binding registered anywhere in the UI.
--
--  The switch is followed rather than read once at load, so switching the
--  module on mid-session brings the three handlers up with it -- ns.Refresh is
--  what the enable checkbox, a profile switch and a spec switch all reach, and
--  it is where the transition is noticed.
-------------------------------------------------------------------------------
local eventsOn = false
-- Declared ahead of the handlers, which reach both of them once the work a
-- fight deferred has been paid off.
local EventsWanted, SetEventsEnabled

local function OnUpdateBindings()
    ns.UpdateBindings()
end

local function OnRegenEnabled()
    if bindingsDirty then ns.UpdateBindings() end
    -- Only when the fight actually refused one: a palette edited during it
    -- was skipped by PushPalette and the sandbox is still holding the old
    -- contents, but a fight nobody edited anything through needs nothing.
    if pushDirty then PushAllPalettes() end
    -- A palette that closed unattended mid-fight could not give ESCAPE
    -- back at the time. Now it can. No live view means none was ever
    -- opened, which is still a reason to try: the binding belongs to the
    -- cancel button rather than to the view.
    local idle = not liveView or not liveView:GetFrame():IsShown()
    if idle then ReleaseEscape() end
    -- Same story for the catcher, the ownership stamp and the arming
    -- gates: a close the fight refused left them exactly as the hold had
    -- them, and a shown catcher goes on eating camera zoom until this runs.
    -- Only with nothing on screen: a key held as the fight ends owns all
    -- of that state, and tearing it down under the hold would kill its
    -- steering. The flag stands until then, and the next unattended close
    -- out of combat does the work anyway.
    if secureCloseDirty and idle then
        local index = secureCloseDirty
        secureCloseDirty = nil
        ReleaseSecureState(index ~= 0 and index or nil)
    end
    -- A disable that landed mid-fight left this handler standing precisely so
    -- the work above could happen; now that it has, the handlers may go.
    SetEventsEnabled(EventsWanted())
end

-- A zone change while the key is held (portals, taxi) can swallow the
-- key-up; drop the palette rather than leave it stuck.
local function OnEnteringWorld()
    ns.Close()
end

-- Switched off, the module wants none of these -- except while something is
-- still owed to PLAYER_REGEN_ENABLED. Every one of those debts is work a fight
-- refused: override bindings that could not be cleared, a push that could not
-- land, a palette the fight left on screen. Dropping the handler that pays them
-- would strand the bindings live for the rest of the session.
function EventsWanted()
    local p = P()
    if p and p.enabled then return true end
    return bindingsDirty or pushDirty or secureCloseDirty ~= nil
end

function SetEventsEnabled(on)
    on = on and true or false
    if on == eventsOn then return end
    eventsOn = on
    if on then
        EQD:RegisterEvent("UPDATE_BINDINGS", OnUpdateBindings)
        EQD:RegisterEvent("PLAYER_REGEN_ENABLED", OnRegenEnabled)
        EQD:RegisterEvent("PLAYER_ENTERING_WORLD", OnEnteringWorld)
        -- The usability filter's inputs (Hide Unusable Entries): the
        -- spellbook and the macro set. A change re-pushes -- deferred and
        -- coalesced by RequestPush, refused in combat and paid off by
        -- PLAYER_REGEN_ENABLED like every other push.
        EQD:RegisterEvent("SPELLS_CHANGED", RequestPush)
        EQD:RegisterEvent("UPDATE_MACROS", RequestPush)
        -- Re-resolve player-facing indexes after outfits change order.
        EQD:RegisterEvent("TRANSMOG_OUTFITS_CHANGED", RequestPush)
        -- Which world markers are down, for a menu that is open while they
        -- move. That is SOMEBODY ELSE's doing: firing an entry closes the menu,
        -- so the presser never sees their own pip change. It is worth the one
        -- registration anyway -- a menu latched open sits there for as long as
        -- the user leaves it, and marking is something a group does together.
        --
        -- Refreshed on the event rather than polled by the live-icon tick: that
        -- tick costs its API calls every frame, and this cue moves a handful of
        -- times a pull. RAID_TARGET_UPDATE is what Blizzard's own manager
        -- refreshes its marker buttons on
        -- (Mainline/Blizzard_CompactRaidFrameManager.lua:282-283).
        --
        -- Inline rather than a named handler, unlike every registration above
        -- it: as one file the module's main chunk was at Lua's ceiling of 200
        -- locals.
        EQD:RegisterEvent("RAID_TARGET_UPDATE", function()
            if liveView and liveView:GetFrame():IsShown() then
                liveView:RefreshMarkerPips()
            end
        end)
        -- What the "Last Used Mount" entry summons. Blizzard records no such
        -- thing -- the whole C_MountJournal surface answers only what is
        -- summoned RIGHT NOW -- so it is observed. Every successful player cast
        -- is offered to GetMountFromSpell, which answers with a mountID for a
        -- mount summon and nil for everything else, so the filter and the
        -- answer are one call; Blizzard's own mount UI watches this same event
        -- (Blizzard_MountCollection.lua:1022). Documented
        -- SecretArguments = "AllowedWhenTainted", so a tainted addon may call
        -- it (MountJournalDocumentation.lua:249-262).
        --
        -- Ignored outright in combat. This fires for every cast the player
        -- makes, and a payload read there may be a secret value; nothing is
        -- missed by skipping it, because no mount can be summoned in combat
        -- anyway.
        --
        -- Stored on the profile, so the entry is not blank at the start of a
        -- session. A profile shared between characters shares the memory too,
        -- and the game refuses a summon the character cannot make, with its own
        -- message -- the same answer a mount entry picked on another character
        -- already gives.
        --
        -- Inline for the reason the registration above it is: as one file the
        -- module's main chunk was at Lua's ceiling of 200 locals.
        EQD:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, _, unit, _, spellID)
            if unit ~= "player" or InCombatLockdown() then return end
            if type(spellID) ~= "number" or not C_MountJournal.GetMountFromSpell then
                return
            end
            local mountID = C_MountJournal.GetMountFromSpell(spellID)
            local pf = P()
            if mountID and pf and pf.lastMountID ~= mountID then
                pf.lastMountID = mountID
                -- Only a palette actually holding one of these has anything to
                -- redraw, and RequestPush coalesces and defers like every other
                -- push, so the cost of a mount cast is one comparison for
                -- everyone else.
                RequestPush()
            end
        end)
    else
        EQD:UnregisterEvent("UPDATE_BINDINGS")
        EQD:UnregisterEvent("PLAYER_REGEN_ENABLED")
        EQD:UnregisterEvent("PLAYER_ENTERING_WORLD")
        EQD:UnregisterEvent("SPELLS_CHANGED")
        EQD:UnregisterEvent("UPDATE_MACROS")
        EQD:UnregisterEvent("TRANSMOG_OUTFITS_CHANGED")
        EQD:UnregisterEvent("RAID_TARGET_UPDATE")
        EQD:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
end

-- Re-read everything from the DB. Safe to call at any time; only redraws views
-- that are actually on screen.
function ns.Refresh()
    -- Ahead of everything that reads the profile: a profile imported from a
    -- pre-rename build carries its palettes under the dead key until this
    -- runs, and applying such a profile is exactly what reaches here.
    MigrateActiveProfile()

    ns.UpdateBindings()
    SetEventsEnabled(EventsWanted())

    -- After UpdateBindings, which is what a DISABLE has to reach to take the
    -- override bindings back down, and before anything that costs something:
    -- switched off, this module draws nothing, pushes nothing and schedules
    -- nothing at all.
    local p = P()
    if not p or not p.enabled then return end

    RefreshFonts()
    RequestPush()

    if liveView and liveView:GetFrame():IsShown() then
        -- Read the selection before Layout, which clears it.
        local keep = liveView:GetSelection()
        liveView:Layout(liveView:GetPaletteIndex())
        local n = liveView:SlotCount()
        liveView:SetSelection(keep and n > 0 and min(keep, n) or nil)
    end

    -- Non-live views (the options preview) follow the same data, so a slider
    -- tick or a slot mutation has to repaint them too. IsVisible, not IsShown:
    -- the options page's wrapper is torn down and re-parented around them.
    for i = 1, #views do
        local v = views[i]
        if v ~= liveView and v:GetFrame():IsVisible() then
            v:Layout(v:GetPaletteIndex())
        end
    end
end

-- Options-panel entry point, matching the suite's _G._<PREFIX>_ convention.
_G._EQD_Apply = ns.Refresh

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
-- This module has carried two names before this one -- Radial Wheel, then
-- Action Palette -- and its data has always lived in the suite's central
-- store, under the addons key NewDB derives from the saved variable name. A
-- rename therefore moves the module's home and leaves every configured
-- palette behind under an old key, invisible to the module and to profile
-- export alike. Move each profile's blob to the current key HERE, before
-- NewDB runs. A moved blob may still carry pre-rename field names (ringCount,
-- rings); P() converts those on the profile's first touch, so the raw move is
-- enough. Current data wins: a profile that already holds palette settings
-- under the current key keeps them. One blind spot: logout StripDefaults
-- leaves an all-defaults profile as an EMPTY table, which reads as "no data"
-- here, so such a profile takes a legacy blob -- once, since the old keys are
-- removed either way. That cleanup is what makes this run once, and what
-- stops the orphans riding along in every profile forever.
--
-- The old CHILD SavedVariables globals (EllesmereUIRadialWheelDB,
-- EllesmereUIActionPaletteDB) need no handling and are deliberately NOT
-- declared in the TOC: they belonged to the old FOLDER names, and a WTF file
-- whose addon no longer exists is never loaded -- it just sits inert.
local function MigrateLegacySV()
    local profiles = EllesmereUIDB and EllesmereUIDB.profiles
    if type(profiles) ~= "table" then return end
    -- No live table to pour into at this point: NewDB has not run, so nothing
    -- holds a reference to any of these yet and the key may be repointed.
    for _, prof in pairs(profiles) do MigrateLegacyProfile(prof) end
end

function EQD:OnInitialize()
    MigrateLegacySV()
    SetDB(EllesmereUI.Lite.NewDB("EllesmereUIQuickdrawDB", DB_DEFAULTS))
    -- The profile itself is converted by P(), on first touch, so that switching
    -- profile mid-session converts the incoming one too. See MigrateNames.
    _G._EQD_AceDB = db
    ns.db = db

    _G.BINDING_HEADER_EUI_RADIAL = "EllesmereUI Quickdraw"
    for i = 1, MAX_PALETTES do
        _G["BINDING_NAME_" .. BINDING_PREFIX .. i] = "Open Action Menu " .. i
    end
end

function EQD:OnEnable()
    local p = P()
    if not p then return end

    -- Switched off, this is the whole of what the module does for the session.
    -- The three handlers, the secure buttons, the scroll catcher and the arming
    -- gates are all brought up by ns.Refresh instead, which is what the enable
    -- checkbox, a profile switch and a spec switch all reach -- so switching the
    -- module on mid-session still gets combat-deferred rebinding and
    -- stuck-palette cleanup, without a session that never enables it paying for
    -- any of them. All it holds is the one empty frame the main file makes.
    if not p.enabled then return end

    for i = 1, PaletteCount() do EnsurePalette(i) end
    ns.UpdateBindings()
    PushAllPalettes()
    SetEventsEnabled(true)
end

I.broken = false
