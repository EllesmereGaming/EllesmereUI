if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Quickdraw_Paint.lua
--
--  PaintCell, Layout, the marker pips, live and pending icons, CellSlot,
--  nest visibility and SetSelection.
--  Reads the earlier Quickdraw files through ns and ns._qdInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._qdInternals
-- EllesmereUIQuickdraw.lua or an earlier Quickdraw file failed to load.
if not I or I.broken then return end
I.broken = true

local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local sin, cos = math.sin, math.cos
local tonumber = tonumber
local tremove = table.remove
local InCombatLockdown = InCombatLockdown
-- Read every frame an open palette holds an entry whose icon can move under it
-- -- see AdvanceLiveIcons.
local IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown =
    IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown

local EnsurePalette, MAX_PALETTES, MAX_SLOTS = I.EnsurePalette, I.MAX_PALETTES, I.MAX_SLOTS
local PA, ReadPalette, SelectColor, CycleNext = I.PA, I.ReadPalette, I.SelectColor, I.CycleNext
local WORLD_MARKER_ENGINE, Rez, SlotCooldown = I.WORLD_MARKER_ENGINE, I.Rez, I.SlotCooldown
local SlotCount, SlotDisplay, SlotUsability = I.SlotCount, I.SlotDisplay, I.SlotUsability
local UsableSlots, ApplyIconCrop = I.UsableSlots, I.ApplyIconCrop
local ApplySlotVisual, PaletteView = I.ApplySlotVisual, I.PaletteView
local RefreshFonts, secureButtons = I.RefreshFonts, I.secureButtons

-- Paint one cell from its slot. Shared by the palette's own entries and by the
-- nested ones, which differ only in where they are placed and when they are
-- shown -- a second copy of this is how a nested entry ends up with no cooldown
-- swirl or the wrong label the first time either option moves.
-- iconSize is the size the LAYOUT gave this cell, before any falloff or
-- selection zoom: the corner count is sized off it, and reading the widget's
-- current size instead would make the number breathe with the entry.
-- Everything an open palette's icons can move under, as one number, so "has any
-- of it changed" is a single comparison. Read every frame while such a cell is
-- on screen, which is why it is five C calls and no allocation.
--
-- The three modifiers are what a macro's [mod] conditionals see. Combat and a
-- dead friendly target are what a Dynamic Rez branches on. Nothing else can
-- change what an entry draws.
local function IconState()
    return (IsShiftKeyDown() and 1 or 0)
         + (IsControlKeyDown() and 2 or 0)
         + (IsAltKeyDown() and 4 or 0)
         + (InCombatLockdown() and 8 or 0)
         + (Rez.HasDeadTarget() and 16 or 0)
end

-- Does this cell's icon depend on any of that? Two kinds do: a macro, whose
-- conditionals are evaluated at the release (see MacroIcon), and a Dynamic Rez,
-- which is three spells wearing one slot (see Rez.SpellNow). Every other kind
-- resolves to one fixed thing, and the built-in macrotext kinds -- markers,
-- world markers, the cycling pair -- carry an icon of their own that no
-- conditional can move.
local function HasLiveIcon(slot)
    if slot == nil then return false end
    return slot.kind == "macro" or slot.kind == "dynamicrez"
end

local function PaintCell(w, slot, placeholder, showLabels, showCooldowns, wantLabel,
                         iconSize, showUsability)
    w.isPlaceholder = placeholder

    -- Read once per paint, which is once per open: range and resources do move
    -- while a palette is up, but a hold lasts a fraction of a second and a tint
    -- that changed under a settled hand would read as a flicker rather than as
    -- information. ApplySlotVisual is what turns this into a colour.
    w.usability = (showUsability and not placeholder) and SlotUsability(slot) or nil

    local icon, name = SlotDisplay(slot)
    ns.SetIconTexture(w.icon, icon)
    -- Per paint: the widget is pooled, and the marker textures take the full
    -- rect where everything else takes the crop.
    ApplyIconCrop(w.icon, icon)
    w.icon:SetShown(not placeholder)
    w.plus:SetShown(placeholder)

    local labelled = showLabels and wantLabel and name ~= nil
    w.label:SetText((labelled and EllesmereUI.L(name)) or "")
    w.label:SetShown(labelled or false)

    -- A palette has no cooldown of its own, and borrowing its first entry's
    -- would be a lie the moment the user pointed at any of the others.
    if showCooldowns and slot and slot.kind ~= "palette" then
        local durObj, start, duration, enable = SlotCooldown(slot)
        if durObj then
            -- clearIfZero defaults true, so an idle spell clears itself.
            w.cd:SetCooldownFromDurationObject(durObj)
        elseif start then
            CooldownFrame_Set(w.cd, start, duration, enable)
        else
            w.cd:Clear()
        end
        w.cd:Show()
    else
        w.cd:Clear()
        w.cd:Hide()
    end

    -- The value is written and shown, never read back or tested -- not even
    -- for nil, which is why SlotCount answers WHETHER separately from WHAT. A
    -- placeholder has no slot to count, and a palette entry's count would be
    -- whichever of its children happened to be first.
    local hasCount, count = false, nil
    if not placeholder and slot and slot.kind ~= "palette" then
        hasCount, count = SlotCount(slot)
    end
    if hasCount then
        w.count:SetTextHeight(max(8, floor((iconSize or 40) * 0.34)))
        w.count:SetText(count)
    end
    w.count:SetShown(hasCount)

    -- Sized and placed per paint: an entry's icon size is a setting, and these
    -- have to stay legible at the small end without swallowing the icon at the
    -- large one. Physical pixels, like the borders.
    local nests = (not placeholder) and slot and slot.kind == "palette"
    if w.nestDots then
        local px = EllesmereUI.PP and EllesmereUI.PP.mult or 1
        local dot = max(px, floor((iconSize or 40) * 0.055 / px + 0.5) * px)
        for d = 1, 3 do
            local t = w.nestDots[d]
            t:SetSize(dot, dot)
            t:ClearAllPoints()
            t:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT",
                       dot + (d - 1) * dot * 2, dot)
            t:SetVertexColor(1, 1, 1, 0.85)
            t:SetShown(nests and true or false)
        end
    end

    -- Through the view because PaintCell is not a method and the pip needs one
    -- (see MarkerPip). Every open repaints every cell, so this is the reading
    -- that matters; the event below only keeps a menu left open honest.
    if w.view then w.view:MarkerPip(w, slot, iconSize) end

    ApplySlotVisual(w, false)
end

-- Lay the palette out and paint every widget from the stored slot data.
function PaletteView:Layout(paletteIndex)
    -- Clamped to what can be STORED rather than to what can be bound: a nested
    -- palette is opened through its parent and may well have no key of its own.
    paletteIndex = min(MAX_PALETTES, max(1, paletteIndex or self.paletteIndex or 1))
    -- PA(paletteIndex), not self:P(): this call is what MOVES the view onto a
    -- palette, so the index it was pointed at last says nothing about the
    -- appearance being laid out here.
    local p, palette = PA(paletteIndex), EnsurePalette(paletteIndex)
    if not p or not palette then return end

    local opts = self.opts
    -- Everything the steering passes read that is NOT the cursor is rewritten
    -- from here down -- the claim boxes, the entry count, every option a
    -- Refresh mid-hold can move -- so the snapshot SteerUnchanged took against
    -- the previous geometry says nothing about this one.
    self._steerX = nil
    self.paletteIndex = paletteIndex
    -- What this view draws: the stored slots for the editor -- assigning and
    -- arranging entries has to show all of them, whoever is logged in -- and
    -- the usable view for everything else (Hide Unusable Entries). Kept on
    -- the view so CellSlot maps a cell index through the SAME list this
    -- drawing was laid out from.
    local slots = opts.interactive and palette.slots
        or UsableSlots(palette, p)
    self._slots = slots
    -- Derived, never stored: the palette is exactly as big as what is on it.
    local n = #slots
    -- The editor's "+" add button. On the ARC it takes the CENTRE -- the
    -- ground the live menu spends on hub art, which the editor does not draw
    -- -- so the ring holds only real entries and the connector line runs out
    -- of the button to whatever is hovered. Block and strip layouts have no
    -- free centre (their middle is an entry), so there the button still
    -- takes the trailing slot, and adding an action visibly re-fans them.
    local isArc = self:LayoutMode() == "ARC"
    local arcCenter = opts.interactive and isArc
    -- The FAN editor's add button leaves the strip entirely -- above a
    -- horizontal strip (which drops a little to make the room), left of a
    -- vertical one -- so the strip holds only real entries and the editor
    -- windows and scrolls exactly the way the live strip does.
    local fanSide = opts.interactive and self:LayoutMode() == "FAN"
    self._fanCrossOff = (fanSide and self:FanHoriz()) and -14 or nil
    -- The caption ("Show Action Text Label"): the selected action's NAME and
    -- nothing else, on every layout -- no palette name at rest, no hint
    -- line, no center text, and no text at all while the switch is off.
    -- SetSelection writes the name and anchors it beside the selection. (It
    -- took over the fan's own Show Action Text; a fanShowText key left in
    -- stored profiles is never read.)
    self._hubNameOnly = p.showActionText == true
    local shown = (opts.interactive and not arcCenter and not fanSide
        and n < MAX_SLOTS) and (n + 1) or n
    self.slotCount, self.shownCount = n, shown

    local step, arcStart = self:ArcGeom(shown)
    local radius, iconSize = self:Geom(shown)
    local fan = self:IsFan()

    -- Worked out before the frame is sized, not with the entries it places: a
    -- nested arc reaches further out than the palette's own ring, and a frame
    -- sized to the ring alone would clip every child drawn beyond it.
    local claims = self:ChildGeom(shown, slots)
    local outer = radius
    -- Half-extents a block layout's nests reach to, in the frame's own units.
    local nestX, nestY = 0, 0
    for k = 1, (claims and #claims or 0) do
        local c = claims[k]
        if c.cells then
            for j = 1, c.n do
                local b = c.cells[j]
                -- The BOX, not the icon: it is the box a pointer has to be able
                -- to reach, and a frame sized to the icons alone would put part
                -- of a nest's own ground outside the palette.
                nestX = max(nestX, abs(b.x) + max(b.hw, c.icon * 0.5))
                nestY = max(nestY, abs(b.y) + max(b.hh, c.icon * 0.5))
            end
        else
            -- Plus the child's own half-width: a ring of icons reaches further
            -- than the circle their centres sit on, and that is what clips.
            outer = max(outer, c.radius + c.icon * 0.5 - iconSize * 0.5)
        end
    end

    local frame = self.frame
    -- p.scale is the user's live sizing; a fitted preview supplies its own
    -- geometry instead and must not be scaled a second time.
    if not opts.interactive then
        local sc = p.scale or 1
        frame:SetScale(sc)
        -- Every string on this palette is sized against its own effective
        -- scale (see ApplyModuleFont), so a scale change leaves all of them
        -- rasterised for the old one. Re-applied only when the scale actually
        -- moved, which is a settings change rather than an open.
        if self.eqdFontScale ~= sc then
            self.eqdFontScale = sc
            RefreshFonts()
        end
    end
    if self:IsPointerLayout() then
        -- One sizing rule for the grid and both pointer-steered strips: a strip
        -- is just a grid one entry deep, so GridDims has already reduced it to
        -- the same cols/rows the extent is measured from.
        local pitch = iconSize + (p.fanGap or 10)
        local cols, rows = self:GridDims()
        -- Whichever is wider: the block itself, or a nest hanging off it.
        frame:SetSize(max(cols * pitch, nestX * 2) + 40,
                      max(rows * pitch, nestY * 2) + 60)
    elseif fan then
        local along  = self:FanHalfLength() * 2 + 40
        local across = iconSize + 60      -- room for the hub caption
        -- Whichever is bigger: the strip, or a nest broken out across it.
        if self:FanHoriz() then
            frame:SetSize(max(along, nestX * 2 + 40), max(across, nestY * 2 + 40))
        else
            frame:SetSize(max(across, nestX * 2 + 40), max(along, nestY * 2 + 40))
        end
    else
        -- Sized generously so labels and the selected-slot zoom never clip.
        local span = (outer + iconSize) * 2 + 40
        frame:SetSize(span, span)
    end

    -- Per-slot labels are FIXED off (the Show Slot Labels setting was
    -- removed; a showLabels key left in stored profiles is never read).
    local showLabels = false
    local showCooldowns = opts.showCooldowns
    if showCooldowns == nil then showCooldowns = p.showCooldowns end
    -- ~= false, not == true: on by default, so a profile that has never seen
    -- the key gets the tint.
    local showUsability = opts.showUsability
    if showUsability == nil then showUsability = p.showUsability ~= false end

    -- The cells whose icon can move under them, collected as they are painted
    -- so an open with none of them leaves an empty list and AdvanceLiveIcons
    -- costs nothing at all. Reused rather than rebuilt: this runs on every open.
    local liveCells = self._liveCells
    if not liveCells then liveCells = {}; self._liveCells = liveCells end
    for k = #liveCells, 1, -1 do liveCells[k] = nil end

    -- The cells still waiting on their display data, collected the same way and
    -- kept the same way -- see ns.WarmSlot and AdvancePendingIcons.
    local pending = self._pendingCells
    if not pending then pending = {}; self._pendingCells = pending end
    for k = #pending, 1, -1 do pending[k] = nil end

    for i = 1, shown do
        local w = self.widgets[i]
        -- Switching modes leaves the other mode's depth cues behind.
        w:SetAlpha(1)
        w:SetScale(1)
        -- The size a selection zoom is measured from. Every steered layout
        -- publishes its own, entry by entry, in the geometry passes below.
        w.baseSize = iconSize
        if not fan then
            local a = arcStart + (i - 1) * step
            w:ClearAllPoints()
            w:SetPoint("CENTER", frame, "CENTER", radius * sin(a), radius * cos(a))
            w:SetSize(iconSize, iconSize)
        end
        w:EnableMouse(opts.interactive == true)

        -- A nil slot is only reachable on an interactive view, whose trailing
        -- "+" placeholder is drawn as a real entry: shown == n otherwise.
        -- The fan never labels its entries: at strip spacing the captions of
        -- neighbouring icons collide, and the centre entry -- the only one that
        -- can be fired -- is already named on the hub.
        PaintCell(w, slots[i], slots[i] == nil,
                  showLabels, showCooldowns, not fan, iconSize, showUsability)
        -- slots, not palette.slots: the same list the cell was just painted
        -- from. Once Hide Unusable Entries filters anything the two part
        -- company, and testing the stored array would collect the wrong cells.
        if HasLiveIcon(slots[i]) then liveCells[#liveCells + 1] = i end
        if ns.WarmSlot(slots[i]) then pending[#pending + 1] = i end
        w:Show()
    end

    -- Nested entries, laid out past the palette's own on the same index line, so
    -- a cell index is all the hit test and the secure push ever have to carry.
    local cells = shown
    if claims then
        for k = 1, #claims do
            local c = claims[k]
            c.base = cells
            for j = 1, c.n do
                cells = cells + 1
                local w = self:Widget(cells)
                w:SetAlpha(1)
                w:SetScale(1)
                w.baseSize = c.icon
                w:ClearAllPoints()
                if c.cells then
                    -- A block layout rewrites these every frame in AdvanceGrid,
                    -- along with the falloff; placing them here too is what a
                    -- view that never steers -- a static frame -- shows.
                    w:SetPoint("CENTER", frame, "CENTER", c.cells[j].x, c.cells[j].y)
                else
                    local r, a = self:ChildRingPos(c, j)
                    w:SetPoint("CENTER", frame, "CENTER", r * sin(a), r * cos(a))
                end
                w:SetSize(c.icon, c.icon)
                w:EnableMouse(false)
                PaintCell(w, c.slots[j], false, showLabels, showCooldowns,
                          c.label ~= false, c.icon, showUsability)
                if HasLiveIcon(c.slots[j]) then
                    liveCells[#liveCells + 1] = cells
                end
                if ns.WarmSlot(c.slots[j]) then
                    pending[#pending + 1] = cells
                end
                -- Hidden until its own claim is opened -- see UpdateNestShown.
                w:Hide()
            end
        end
    end
    self.claims = claims
    self.cellCount = cells
    -- The paint above already drew every macro cell for the modifiers held right
    -- now, so recording them here is what keeps the palette's first tick from
    -- repainting the lot for a state that has not moved.
    self._liveState = IconState()
    -- Every cell was just hidden and every entry repainted plain, so all three
    -- of these describe a drawing that no longer exists.
    self._openClaim, self._armedParent = nil, nil

    -- Which way the nests went, so the caption can hang on the other side. Taken
    -- from the first claim that placed: with several nests on different sides
    -- there is no one answer, and the first is the one the palette leads with.
    self.nestAxis, self.nestSign = nil, nil
    for k = 1, (claims and #claims or 0) do
        if claims[k].axis then
            self.nestAxis, self.nestSign = claims[k].axis, claims[k].sign
            break
        end
    end

    for i = cells + 1, #self.widgets do
        self.widgets[i]:Hide()
        self.widgets[i]:EnableMouse(false)
    end

    -- The ARC editor's centred add button, painted after the sweep above
    -- because it borrows the slot widget one past the palette's own entries
    -- (which that sweep just hid). Gone at the cap: a full menu has nothing
    -- to add. It stays outside shownCount, so the falloff and the hit test
    -- never see it -- only its own mouse scripts do.
    if arcCenter and n < MAX_SLOTS then
        local w = self:Widget(n + 1)
        -- Sized from the profile's icon size directly, NOT from this view's
        -- geom: the button is an editor affordance rather than a preview of
        -- an entry, so the preview's fit-to-block shrink does not apply --
        -- it paints at full scale whatever the ring around it is drawn at.
        local addSize = p.iconSize or 40
        w:SetAlpha(1)
        w:SetScale(1)
        w.baseSize = addSize
        w:ClearAllPoints()
        w:SetPoint("CENTER", frame, "CENTER", 0, 0)
        w:SetSize(addSize, addSize)
        w:EnableMouse(true)
        PaintCell(w, nil, true, showLabels, showCooldowns, not fan, addSize,
                  showUsability)
        w:Show()
    end

    -- The FAN editor's add button, off the strip's own line: above a
    -- horizontal strip (which _fanCrossOff dropped to make the room), left
    -- of a vertical one. Full scale for the same reason the arc's is --
    -- an editor affordance, never fitted -- and outside shownCount, so the
    -- window, the fold and the scroll never see it.
    if fanSide and n < MAX_SLOTS then
        local w = self:Widget(n + 1)
        local addSize = p.iconSize or 40
        local _, viewIcon = self:Geom()
        w:SetAlpha(1)
        w:SetScale(1)
        w.baseSize = addSize
        w:ClearAllPoints()
        if self:FanHoriz() then
            w:SetPoint("CENTER", frame, "CENTER", 0,
                (self._fanCrossOff or 0) + viewIcon * 0.5 + addSize * 0.5 + 20)
        else
            w:SetPoint("CENTER", frame, "CENTER",
                -(viewIcon * 0.5 + addSize * 0.5 + 20), 0)
        end
        w:SetSize(addSize, addSize)
        w:EnableMouse(true)
        PaintCell(w, nil, true, showLabels, showCooldowns, false, addSize,
                  showUsability)
        w:Show()
    end

    -- Every widget was just repainted unselected, so the recorded selection is
    -- stale by construction; callers that want it back re-apply it afterwards.
    self.selection = nil

    if self:IsPointerLayout() then
        self:AdvanceGrid(true)
        -- AdvanceGrid publishes a selection; Layout's contract is that it does
        -- not, and the caller re-applies one afterwards.
        self.selection = nil
    elseif fan then
        self:ApplyFanGeometry()
    end

    local hub = self.hub
    self:HideNeedle()
    -- In fan modes the centre of the frame is occupied by the selected entry,
    -- so the hub's disc would sit under it and its caption on top of it. Drop
    -- the disc and hang the caption clear of the strip instead.
    -- Exactly one piece of hub art, and only where the centre is empty.
    -- Hub art is HARDCODED (the logo settings were removed): the logo at its
    -- shipped size and opacity, scaled by whatever the view scaled its
    -- geometry by -- the options preview fits the palette to its panel, and
    -- a hub drawn at the profile's literal pixel size would swamp a palette
    -- shrunk to two-thirds. The ARC editor draws none at all: its centre
    -- belongs to the add button. hubIcon* keys left in stored profiles are
    -- never read.
    local drawHub = not fan and not arcCenter
    hub.logo:SetShown(drawHub)
    if drawHub then
        local _, viewIcon = self:Geom()
        local base = p.iconSize or 40
        local k = (base > 0) and (viewIcon / base) or 1
        local sz = max(8, 40 * k)
        -- Snapped to a WHOLE number of physical pixels: an addon PNG has no
        -- mipmaps, so WoW pure-bilinear-resamples it, and a fractional
        -- physical size guarantees off-grid sampling that turns the thin
        -- ring jagged. The other half of the fix is authoring the art near
        -- its display size rather than huge.
        local es = hub.logo:GetEffectiveScale()
        if es and es > 0 then
            sz = floor(sz * es + 0.5) / es
            if sz < 1 then sz = 1 end
        end
        hub.logo:SetSize(sz, sz)
        -- Tinted like the connector line (SelectColor), at full alpha in the
        -- same call -- a texture's vertex alpha and SetAlpha share one slot,
        -- so this single write owns both.
        local r, g, b = SelectColor(p)
        hub.logo:SetVertexColor(r, g, b, 1)
        -- The size the slam-open scales up to (AdvanceSlam).
        self._slamLogoSize = sz
    end
    self:PlaceHubText()
    -- Textless at rest on EVERY layout: the grid's palette-name-and-keybind
    -- rest caption went with the Show Center Text setting (a showHubText key
    -- left in stored profiles is never read), and in name-only mode a
    -- selection writes just the action's name -- see SetSelection.
    hub.text:SetText("")
    hub.hint:SetText("")
end

-- Redraw the cells whose icon can move, if anything they follow has moved since
-- the last time this asked.
--
-- The palette fires on the RELEASE, and both of these kinds decide what they
-- cast at that moment: a macro's conditionals are evaluated then, and a Dynamic
-- Rez picks its branch then. So the player can press a modifier, pull a boss or
-- click a corpse at any point during the hold and change what the entry under
-- the cursor is going to do. Without this the palette keeps drawing whichever
-- branch happened to be current when it opened, and the only way to find out
-- that it swapped is to fire it.
--
-- A latched menu makes this matter more than a hold does: it stays up across a
-- pull, which is exactly the transition the rez branches on.
--
-- ICON only, deliberately. The label stays the name the paint gave it -- for a
-- macro that is the macro's own name, which is what Blizzard's action buttons
-- show and what the player recognises -- and the usability tint stays where the
-- paint left it, for the reason PaintCell gives: a colour that moves under a
-- settled hand reads as a flicker.
--
-- Five C calls per frame for a palette holding one of these kinds, none for one
-- that is not (the list is empty and this returns on the first line), and
-- textures are touched only on the frames the state actually changes -- one
-- press of shift, not one per frame it stays down.
-- The pip that says this world marker is down right now, so an entry says
-- whether pressing it places the marker or picks it back up before it is
-- pressed. Blizzard's own manager draws the same distinction, swapping its
-- button art between "applied" and "available"
-- (Mainline/Blizzard_CompactRaidFrameManager.lua:1107-1112).
--
-- Read on every open, which is where nearly all of its value is: firing an
-- entry closes the menu (see the release handler), so a press never updates a
-- pip the presser can still see.
--
-- IsRaidMarkerActive answers a SECRET boolean during chat messaging lockdown
-- (SecretInChatMessagingLockdown in RaidMarkersDocumentation.lua): on every
-- dungeon and raid map, in or out of combat, and through boss encounters,
-- keystones and PvP matches -- which is where a marker menu does most of its
-- work. So the answer is never tested, compared or kept here. It goes
-- straight into SetAlphaFromBoolean on the pip's host frame, which takes a
-- secret from our code and lets the client resolve it; a plain answer takes
-- the same call, so the pip is right in both states on one path. Nothing
-- else about the pip (size, color, shown) depends on the answer.
--
-- Every other kind hides the pip rather than leaving it alone: one widget is
-- reused for whatever the next open puts in it, and a stale pip would claim a
-- spell was a marker that is on the ground.
--
-- A method rather than a local function, like MarkerPip's caller and
-- RefreshMarkerPips below: as one file the module's main chunk was at Lua's
-- ceiling of 200 locals and had no room for another name.
function PaletteView:MarkerPip(w, slot, iconSize)
    local pip = w.markerPip
    if not pip then return end
    -- Live menus only: the pip reads REAL marker state, which is noise on the
    -- options preview and the editor -- those show arrangement, not the
    -- battlefield. Hidden rather than skipped, so a reused widget never
    -- carries a stale pip across views.
    if not (self.opts and self.opts.live) then
        pip:Hide()
        return
    end
    -- Per-palette opt-out (Show Placed-Marker Pips, in the Toggle World
    -- Markers cog).
    local pp = self:P()
    if pp and pp.worldMarkerPip == false then
        pip:Hide()
        return
    end
    local id
    if slot then
        if slot.kind == "worldmarker" then
            id = tonumber(slot.id)
        elseif slot.kind == "cycleworldmarker" then
            -- The one the NEXT press places, which is the marker this entry is
            -- already drawing (SlotDisplay). Through CycleNext rather than off
            -- the stored position, so the pip and the icon cannot disagree
            -- about which marker the entry is currently offering.
            --
            -- The target-marker cycle is NOT this: raid targets sit on units,
            -- and IsRaidMarkerActive answers for world markers alone -- which
            -- Blizzard says in as many words at
            -- Mainline/Blizzard_CompactRaidFrameManager.lua:1088.
            id = CycleNext(slot)
        end
    end
    if not id or id < 1 or id > 8 then
        pip:Hide()
        return
    end
    -- The widget's own width when no size is passed: a nest scales its
    -- children as it opens, and the refresh below runs long after the paint
    -- that knew the unscaled figure.
    local s = max(3, floor((iconSize or w:GetWidth() or 40) * 0.18))
    pip:SetSize(s, s)
    local ar, ag, ab = 0.047, 0.824, 0.624
    if EllesmereUI.ResolveActiveAccent then
        ar, ag, ab = EllesmereUI.ResolveActiveAccent()
    end
    pip:SetVertexColor(ar, ag, ab, 1)
    -- Whether the marker is down reaches the screen through the host's alpha
    -- alone (see above); the pip itself is shown for every marker entry. The
    -- host is made the first time this widget holds a marker entry, at the
    -- default child level: under the border host, where the pip always drew.
    local host = w.markerPipHost
    if not host then
        host = CreateFrame("Frame", nil, w)
        host:SetAllPoints(w)
        w.markerPipHost = host
        pip:SetParent(host)
    end
    host:SetAlphaFromBoolean(IsRaidMarkerActive(WORLD_MARKER_ENGINE[id]), 1, 0)
    pip:Show()
end

-- Every drawn cell's pip, for a menu that is already up when the markers move.
-- Walks the cells rather than a collected list the way AdvanceLiveIcons does:
-- that list earns itself by being read every frame, and this runs a handful of
-- times a pull.
function PaletteView:RefreshMarkerPips()
    local n = self.cellCount
    if not n then return end
    for i = 1, n do
        local w = self.widgets[i]
        if w then
            -- Through a local, NOT straight into the call: CellSlot answers a
            -- nested cell with slot, claim, subIndex, and in final argument
            -- position all three would expand -- landing the claim table in
            -- MarkerPip's iconSize, which the size arithmetic there then
            -- multiplies. Top-level cells return one value and hid this.
            local slot = self:CellSlot(i)
            self:MarkerPip(w, slot)
        end
    end
end

function PaletteView:AdvanceLiveIcons()
    local cells = self._liveCells
    if not cells or #cells == 0 then return end
    local state = IconState()
    if state == self._liveState then return end
    self._liveState = state

    for k = 1, #cells do
        local index = cells[k]
        local w = self.widgets[index]
        local slot = self:CellSlot(index)
        if w and slot then
            local icon = SlotDisplay(slot)
            ns.SetIconTexture(w.icon, icon)
            ApplyIconCrop(w.icon, icon)
        end
    end
end

-- The entries that were drawn before the client had their data. Repainted as
-- each one's load lands, so a menu still on screen fills its own question marks
-- in rather than carrying them to the end of the hold. Cells leave the list as
-- they resolve, and an open with nothing outstanding -- which is every open once
-- the session has the data -- costs one length test a frame.
function PaletteView:AdvancePendingIcons()
    local cells = self._pendingCells
    if not cells or #cells == 0 then return end
    for k = #cells, 1, -1 do
        local index = cells[k]
        local slot = self:CellSlot(index)
        if ns.SlotDataReady(slot) then
            local w = self.widgets[index]
            if w then
                local icon = SlotDisplay(slot)
                ns.SetIconTexture(w.icon, icon)
                ApplyIconCrop(w.icon, icon)
            end
            tremove(cells, k)
        end
    end
end

-- The slot a cell index draws, and the claim it belongs to for a nested one.
-- Every cell past shownCount is somebody's child; the palette's own entries map
-- straight through.
function PaletteView:CellSlot(index)
    if not index then return nil end
    -- ReadPalette, not EnsurePalette: this is reached from every selection
    -- change, i.e. every time the cursor crosses an entry boundary during a
    -- hold, and compacting the slot array there would allocate and write into
    -- the profile for a pure read.
    local palette = ReadPalette(self.paletteIndex)
    if not palette then return nil end
    if index <= self.shownCount then
        -- The list this drawing was laid out from (Layout), which is the
        -- usable view on a live menu -- indexing the stored array here would
        -- hand back the wrong entry the moment anything was filtered.
        local slots = self._slots or palette.slots
        return slots[index]
    end
    local claims = self.claims
    for k = 1, (claims and #claims or 0) do
        local c = claims[k]
        if c.base and index > c.base and index <= c.base + c.n then
            return c.slots[index - c.base], c, index - c.base
        end
    end
    return nil
end

-- Which claim, if any, the secure button says a gate has armed -- the claim
-- index NestHit, HitTest and UpdateNestShown all key their nest off, and the
-- same index the release branch of SNIPPET_PRE tests against. Reading an
-- attribute off a protected frame is unrestricted even in combat, so this
-- works whether or not the player can currently write one.
--
-- nil for any view with no secure button of its own -- an interactive view
-- (the options preview) draws no nests at all (ChildGeom answers nil for it),
-- so the claims table this would index into does not exist regardless.
function PaletteView:ArmedClaim()
    local btn = not self.opts.interactive and secureButtons[self.paletteIndex]
    return btn and tonumber(btn:GetAttribute("eqdArmed")) or nil
end

-- Views whose nests open on selection alone, with no arming in the way: an
-- interactive view (the options preview), which has no secure button and fires
-- nothing at all, and the scroll fan in WHEEL-ONLY steering, whose nest is
-- picked with the wheel. The hover channel arms like every other steered
-- layout -- through gates, the strip's lattice (see EnsureLatticeGates) --
-- so its nests follow eqdArmed: ground where a nest is merely closed answers
-- nothing, on screen and at the release alike.
function PaletteView:NestsFollowSelection()
    if self.opts.interactive == true then return true end
    if self:IsFan() and not self:IsPointerLayout() then
        local p = self:P()
        return (p and p.fanMouseSelect) == false
    end
    return false
end

-- Repaint one of the palette's own entries in whatever state it is currently
-- in. Used when the armed claim moves: that changes how an entry is drawn
-- without the selection having moved at all.
function PaletteView:RepaintEntry(index)
    local w = index and self.widgets[index]
    if w then
        ApplySlotVisual(w, index == self.selection, index == self._armedParent)
    end
end

-- Which nest is open. One at a time -- every nest drawn at once would bury the
-- palette it hangs off.
--
-- A nest is OPEN when its claim is ARMED, which means the cursor has actually
-- passed through the entry that opens it -- see ArmedClaim and the gate frames
-- EnsureGates builds. That is what keeps a nest open across the ground between
-- its parent and its children without two neighbouring claims fighting over
-- ground they both think they own, and it is the same claim NestHit, HitTest
-- and the release branch of SNIPPET_PRE answer for, so what is drawn and what a
-- release fires cannot disagree about which nest is live.
--
-- Selection landing on a claim's parent is NOT that, and draws nothing: those
-- children would every one of them be dead. It used to draw them faintly, as a
-- preview, which put a second set of icons over the open nest's own -- worst on
-- the arc, where the two sit in the same ring. What an entry does is said on
-- the ENTRY now, by the corner dots every nesting entry carries (see PaintCell).
--
-- On a view with no arming of its own the selection is still the whole of the
-- answer -- see NestsFollowSelection.
function PaletteView:UpdateNestShown(index)
    local claims = self.claims
    if not claims then return end

    -- The claim the selection is standing on or inside.
    local touched
    for k = 1, #claims do
        local c = claims[k]
        if index and c.base
           and (index == c.parent or (index > c.base and index <= c.base + c.n)) then
            touched = c
        end
    end

    local open
    if self:NestsFollowSelection() then
        open = touched
    else
        local armed = self:ArmedClaim()
        open = armed and claims[armed] or nil
        if self:IsFan() and not self:IsPointerLayout() then
            -- The hover strip. A parent the window has culled has no drawn
            -- nest to hold open.
            if open and not self:FanSlotOffset(open.parent) then open = nil end
        end
    end

    -- Ahead of the unchanged check below, and off open rather than off the
    -- selection: the parent of an armed claim keeps its mark while the cursor
    -- moves on into the children.
    local armedParent = (not self:NestsFollowSelection()) and open and open.parent or nil
    if self._armedParent ~= armedParent then
        local previous = self._armedParent
        self._armedParent = armedParent
        self:RepaintEntry(previous)
        self:RepaintEntry(armedParent)
    end

    if self._openClaim == open then return end
    self._openClaim = open

    for k = 1, #claims do
        local c = claims[k]
        local shownNest = (c == open)
        for j = 1, c.n do
            local w = c.base and self.widgets[c.base + j]
            if w then
                if shownNest then w:SetAlpha(1) end
                w:SetShown(shownNest)
            end
        end
    end
end

-- Paint selection state. Called from OnUpdate whenever the hovered slot
-- changes, and once from Open so the initial state is drawn.
function PaletteView:SetSelection(index)
    -- Ahead of the unchanged-selection return: a claim can arm and disarm under
    -- a cursor that is holding still on one entry, and the nest state has to
    -- follow that. UpdateNestShown makes its own decision about whether there
    -- is anything left to draw.
    self:UpdateNestShown(index)
    if self.selection == index then return end

    local widgets = self.widgets
    if self.selection and widgets[self.selection] then
        ApplySlotVisual(widgets[self.selection], false,
                        self.selection == self._armedParent)
    end
    self.selection = index

    local hub = self.hub

    if index then
        local w = widgets[index]
        ApplySlotVisual(w, true, index == self._armedParent)

        -- The caption ("Show Action Text Label") rides the SELECTION on
        -- every layout: hover can select any drawn entry, so a name parked
        -- at a fixed point floated beside the wrong icon. Anchored to the
        -- selected entry's own widget -- which also carries it through the
        -- fan's settle slide -- UNDER the icon everywhere except a vertical
        -- strip, which captions LEFT of it; a nested child is captioned
        -- under the palette it came from and anchors beside the nest's
        -- PARENT, the fixed thing the eye tracks the nest by. The editor
        -- deviates only around its add button: a vertical strip's entries
        -- caption on the RIGHT (the "+" sits left), and the "+"'s own
        -- caption mirrors away from the entries. Off, the palette draws no
        -- text at all and none of this work is done.
        if self._hubNameOnly then
            local slot, claim = self:CellSlot(index)
            local _, name = SlotDisplay(slot)
            local r, g, b = SelectColor(self:P())
            if claim then
                local _, parentName = SlotDisplay(self:CellSlot(claim.parent))
                if parentName and name then
                    name = EllesmereUI.L(parentName) .. " \194\187 " .. EllesmereUI.L(name)
                end
            end
            hub.text:SetText((name and EllesmereUI.L(name)) or (w.isPlaceholder and EllesmereUI.L("Add Action")) or ("Slot " .. index))
            hub.text:SetTextColor(r, g, b)

            local aw = widgets[claim and claim.parent or index]
            if aw then
                hub.text:ClearAllPoints()
                if self:LayoutMode() ~= "FAN" or self:FanHoriz() then
                    hub.text:SetJustifyH("CENTER")
                    if aw.isPlaceholder then
                        hub.text:SetPoint("BOTTOM", aw, "TOP", 0, 6)
                    else
                        hub.text:SetPoint("TOP", aw, "BOTTOM", 0, -6)
                    end
                elseif not self.opts.interactive or aw.isPlaceholder then
                    hub.text:SetJustifyH("RIGHT")
                    hub.text:SetPoint("RIGHT", aw, "LEFT", -10, 0)
                else
                    hub.text:SetJustifyH("LEFT")
                    hub.text:SetPoint("LEFT", aw, "RIGHT", 10, 0)
                end
            end
        end

        -- The connector line to the chosen entry, always drawn where one is
        -- drawn at all (the Show Direction Needle setting was removed; a
        -- showNeedle key left in stored profiles is never read). Only the
        -- arc has one: everywhere else the selection has no fixed centre to
        -- connect a line to.
        if not self:IsFan() then
            self:ShowNeedle(index)
        else
            self:HideNeedle()
        end
    else
        if self._hubNameOnly then
            -- Nothing selected, nothing said: the caption carries only a
            -- selected action's name.
            hub.text:SetText("")
        end
        self:HideNeedle()
    end
end

I.broken = false
