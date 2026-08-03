-------------------------------------------------------------------------------
--  EllesmereUIRadialWheel.lua  --  radial action wheel for EllesmereUI
--
--  Hold a keybind -> a ring of slots fans out around the cursor. Steer the
--  mouse toward a slot to select it, release the key to fire it. Releasing
--  while the cursor is still inside the dead zone cancels.
--
--  Activation is fully secure and taint-free. Each ring owns one hidden
--  SecureActionButtonTemplate button; the ring's keybind is routed to that
--  button with SetOverrideBindingClick, and the button is registered for
--  "AnyDown","AnyUp":
--
--    key DOWN -> PreClick clears "type" (so the press itself fires nothing)
--                and opens the wheel
--    key UP   -> PreClick writes the hovered slot's action attributes, the
--                secure handler performs the cast, PostClick closes the wheel
--
--  Writing attributes from insecure code is unrestricted -- what matters is
--  that the click originates from hardware, which it does. Nothing in this
--  path calls a protected function, so it works identically in and out of
--  combat. The only protected calls in the file are the override-binding
--  updates, which are deferred to PLAYER_REGEN_ENABLED when in combat.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local ERW = EllesmereUI.Lite.NewAddon(ADDON_NAME)

-- Upvalues
local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
local sin, cos, atan2, sqrt, pi = math.sin, math.cos, math.atan2, math.sqrt, math.pi
local log = math.log
local tonumber, type, select = tonumber, type, select
local tinsert, tremove = table.insert, table.remove
local GetCursorInfo, ClearCursor = GetCursorInfo, ClearCursor
local GetCursorPosition = GetCursorPosition
local GetBindingKey = GetBindingKey
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime

local TWO_PI = pi * 2
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Ring / slot limits. MAX_RINGS must match the number of <Binding> entries in
-- Bindings.xml -- a ring with no declared binding can never be opened.
local MAX_RINGS = 6
local MAX_SLOTS = 12

local BINDING_PREFIX = "EUI_RADIAL"

-- DIALOG is also the options window's strata (EllesmereUI.lua:7126), which is
-- fine: the wheel only exists on screen while a key is held.
local LIVE_STRATA = "DIALOG"

-------------------------------------------------------------------------------
--  Database
-------------------------------------------------------------------------------
local DB_DEFAULTS = {
    profile = {
        enabled     = true,

        -- Placement. posX/posY are a UIParent-LOGICAL delta from UIParent's
        -- center, i.e. independent of the wheel's own scale -- the same
        -- convention MythicTimer's standalonePos uses
        -- (EllesmereUIMythicTimer.lua:2651). PositionWheel divides by scale at
        -- apply time, because SetPoint offsets live in the frame's own scaled
        -- space; without that, changing Scale would also move the wheel.
        centerMode  = "CURSOR",      -- CURSOR | SCREEN
        posX        = 0,
        posY        = 0,

        -- Layout. RADIAL steers with the cursor's angle; the two FAN modes are
        -- a coverflow strip scrubbed with the mouse wheel, which keeps working
        -- while the right button is held to steer the camera and the cursor is
        -- therefore frozen.
        layout      = "RADIAL",      -- RADIAL | FAN_H | FAN_V | GRID
        gridColumns = 4,

        -- Arc. 360 is the full wheel. Anything less fans the entries across a
        -- sector centred on arcRotation (0 = straight up, growing clockwise),
        -- which keeps a ring clear of a screen edge and gives a nested ring
        -- somewhere to open that does not cover its parent.
        arcSpan     = 360,           -- degrees, 30..360
        arcRotation = 0,             -- degrees, direction the arc is centred on

        -- Geometry
        radius      = 96,
        iconSize    = 44,
        deadZone    = 24,
        scale       = 1.0,

        -- Fan geometry. Both decays are per-step multipliers away from the
        -- centre, so one number describes the whole falloff. The floors keep
        -- distant entries legible instead of letting them vanish, and matter
        -- most on the options preview, which draws the whole ring at once.
        fanVisible    = 3,           -- entries drawn each side of the centre
        fanGap        = 10,
        fanScaleDecay = 0.72,
        fanAlphaDecay = 0.62,
        fanMinScale   = 0.30,
        fanMinAlpha   = 0.12,
        fanAnimTime   = 0.10,        -- seconds for the strip to settle
        fanInvert     = false,       -- flip which way a scroll tick travels

        -- How a fan is steered. SCROLL cycles a window of the ring past a fixed
        -- centre. CURSOR lays the WHOLE ring out at fixed positions and zooms
        -- whichever entry the pointer is nearest, so it needs no wheel at all.
        fanInput      = "SCROLL",    -- SCROLL | CURSOR

        -- Flick-ahead. The radial's wedges are unbounded in depth, so a gesture
        -- can be finished before the ring has even faded in. Holding it back for
        -- a moment lets an expert flick without a menu ever appearing, while a
        -- hesitant press still gets the full display. Selection is live the
        -- whole time -- only the drawing waits.
        flickAhead    = true,
        flickDelay    = 0.12,        -- seconds held before the ring fades in
        flickFade     = 0.10,        -- seconds the fade itself takes

        -- Appearance
        showLabels    = true,
        showHubText   = true,
        showNeedle    = true,
        showCooldowns = true,
        selectedZoom  = 1.15,
        bgAlpha       = 0.65,
        selectColor   = { 0.047, 0.824, 0.624 },  -- EllesmereUI teal (#0cd29f)
        useClassColor = false,

        ringCount   = 1,
        -- ring.slots is a DENSE, ORDERED array: the ring auto-sizes to what the
        -- user has actually assigned, so three actions means three big wedges
        -- rather than three icons and five dead gaps. Order is the wedge order,
        -- clockwise from 12 o'clock, and is what the editor reorders.
        rings = {
            [1] = { name = "Ring 1", slots = {} },
        },
    },
}
ns.DB_DEFAULTS = DB_DEFAULTS

local db
local function P()
    return db and db.profile
end

-- Rings past the first are created on demand: the defaults table only seeds
-- ring 1, so DeepMergeDefaults never has to know how many the user wants.
local function EnsureRing(index)
    local p = P()
    if not p or index < 1 or index > MAX_RINGS then return nil end
    if not p.rings then p.rings = {} end
    local ring = p.rings[index]
    if not ring then
        ring = { name = "Ring " .. index, slots = {} }
        p.rings[index] = ring
    end
    if type(ring.slots) ~= "table" then ring.slots = {} end

    -- Self-healing compaction. The array must have no holes for #slots to be
    -- meaningful, and a hole is exactly what a cleared slot used to leave
    -- behind under the old fixed-slot-count model. Also enforces MAX_SLOTS.
    local dense, n = {}, 0
    for i = 1, MAX_SLOTS do
        local slot = ring.slots[i]
        if slot and slot.kind then
            n = n + 1
            dense[n] = slot
        end
    end
    ring.slots = dense
    ring.slotCount = nil   -- retired: the count is now derived from #slots
    return ring
end
ns.EnsureRing = EnsureRing

-- Ordered mutations. All three keep the array dense so #slots stays the
-- authoritative wedge count.
function ns.AddSlot(ring, slot)
    if not ring or not slot then return nil end
    if #ring.slots >= MAX_SLOTS then return nil end
    ring.slots[#ring.slots + 1] = slot
    return #ring.slots
end

function ns.RemoveSlot(ring, index)
    if not ring or not ring.slots[index] then return false end
    tremove(ring.slots, index)
    return true
end

-- Move, not swap: dragging an icon between two others should insert it there
-- and shuffle the rest along, which is what a reorder is.
function ns.MoveSlot(ring, from, to)
    if not ring then return false end
    local n = #ring.slots
    if from == to or from < 1 or from > n or to < 1 or to > n then return false end
    tinsert(ring.slots, to, tremove(ring.slots, from))
    return true
end

local function RingCount()
    local p = P()
    return min(MAX_RINGS, max(1, (p and p.ringCount) or 1))
end
ns.RingCount = RingCount

local function SelectColor()
    local p = P()
    if p and p.useClassColor then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[select(2, UnitClass("player"))]
        if c then return c.r, c.g, c.b end
    end
    local sc = p and p.selectColor
    if sc then return sc[1] or 1, sc[2] or 1, sc[3] or 1 end
    return 0.047, 0.824, 0.624
end
ns.SelectColor = SelectColor
ns.MAX_SLOTS = MAX_SLOTS

-------------------------------------------------------------------------------
--  Slot model
--
--  A slot is { kind = <string>, ... }. Everything the secure button needs is
--  derived from the slot at click time by ResolveAction; everything the UI
--  needs is derived by SlotDisplay. Both are pure lookups over the stored
--  ids, so a slot never caches a stale icon or name across a patch.
-------------------------------------------------------------------------------

-- kind -> attribute triple for the secure button, plus an optional 4th value:
-- a sibling attribute key that must be cleared because the same action type
-- would otherwise read it in preference. Returns nil for kinds that have no
-- secure action type (battlepet), which FireInsecure handles instead.
local function ResolveAction(slot)
    if not slot or not slot.kind then return nil end
    local k = slot.kind

    if k == "spell" then
        if type(slot.id) ~= "number" then return nil end
        return "spell", "spell", slot.id

    elseif k == "item" then
        if type(slot.id) ~= "number" then return nil end
        return "item", "item", "item:" .. slot.id

    elseif k == "toy" then
        if type(slot.id) ~= "number" then return nil end
        return "toy", "toy", slot.id

    elseif k == "macro" then
        -- Stored by name so reordering the macro list doesn't repoint the
        -- slot. RunMacro accepts a name, so the name is what we hand over.
        -- The 4th return clears the sibling key: type="macro" reads "macro"
        -- first and only falls through to "macrotext" when it is unset
        -- (SecureTemplates.lua:441). The direction that matters is therefore
        -- the other branch -- a macrotext slot must clear a stale "macro", or
        -- the earlier slot's macro name wins. This branch clears macrotext for
        -- symmetry, so neither key can outlive the slot that set it.
        local nameOrIndex = slot.name or slot.id
        if not nameOrIndex then return nil end
        return "macro", "macro", nameOrIndex, "macrotext"

    elseif k == "macrotext" then
        if type(slot.macrotext) ~= "string" or slot.macrotext == "" then return nil end
        return "macro", "macrotext", slot.macrotext, "macro"

    elseif k == "mount" then
        -- C_MountJournal.SummonByID is protected, so the mount is summoned
        -- through its own summon spell instead.
        --
        -- By NAME, not by id: SECURE_ACTIONS.spell routes a numeric value to
        -- CastSpellByID and a string to CastSpellByName
        -- (SecureTemplates.lua:387-395). Mount summon spells do not live in the
        -- spellbook, and CastSpellByID does nothing for them; CastSpellByName is
        -- the path a plain "/cast <mount>" macro takes, which does work.
        local mountName, spellID = nil, slot.spellID
        if slot.id then
            mountName, spellID = C_MountJournal.GetMountInfoByID(slot.id)
            spellID = slot.spellID or spellID
        end
        -- The spell's own name over the journal's display name: it is what
        -- CastSpellByName resolves against.
        local info = type(spellID) == "number" and C_Spell.GetSpellInfo(spellID)
        local castName = (info and info.name) or mountName
        if type(castName) ~= "string" or castName == "" then return nil end
        return "spell", "spell", castName
    end

    return nil
end
ns.ResolveAction = ResolveAction

-- Kinds with no secure equivalent. Summoning a battle pet is not protected,
-- so it is safe to do straight from PostClick.
local function FireInsecure(slot)
    if not slot then return end
    if slot.kind == "battlepet" and slot.guid and C_PetJournal then
        C_PetJournal.SummonPetByGUID(slot.guid)
    end
end

-- icon, name for display. Never returns nil for icon so a slot whose target
-- has been removed from the game still renders as an occupied slot.
--
-- Note the deliberate absence of `C_Foo and C_Foo.Bar(x)` guards here: an
-- `and` expression is truncated to ONE value, which would silently drop every
-- return past the first and leave every icon nil.
local function SlotDisplay(slot)
    if not slot or not slot.kind then return nil, nil end
    local k = slot.kind

    if k == "spell" then
        local info = C_Spell.GetSpellInfo(slot.id)
        if info then return info.iconID or QUESTION_MARK, info.name end

    elseif k == "item" then
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(slot.id)
        local name = C_Item.GetItemInfo(slot.id)
        return icon or QUESTION_MARK, name or slot.name

    elseif k == "toy" then
        local _, name, icon = C_ToyBox.GetToyInfo(slot.id)
        return icon or QUESTION_MARK, name or slot.name

    elseif k == "macro" then
        local name, icon = GetMacroInfo(slot.name or slot.id)
        return icon or QUESTION_MARK, name or slot.name

    elseif k == "macrotext" then
        return slot.icon or QUESTION_MARK, slot.name or "Macro"

    elseif k == "mount" then
        local name, _, icon = C_MountJournal.GetMountInfoByID(slot.id)
        return icon or QUESTION_MARK, name or slot.name

    elseif k == "battlepet" then
        local _, _, _, _, _, _, _, name, icon = C_PetJournal.GetPetInfoByPetID(slot.guid)
        return icon or QUESTION_MARK, name or slot.name
    end

    return QUESTION_MARK, slot.name
end
ns.SlotDisplay = SlotDisplay

-- Cooldown source per kind. Returns start, duration, enable -- handed to
-- CooldownFrame_Set verbatim, never compared or arithmetic'd, so secret
-- cooldown values stay untouched.
local function SlotCooldown(slot)
    if not slot then return nil end
    local k = slot.kind
    if k == "spell" or k == "mount" then
        local id
        if k == "mount" then
            -- No falling back to slot.id here: that is a mountID, and looking
            -- a mountID up as a spellID reports some unrelated spell's cooldown.
            id = slot.spellID or select(2, C_MountJournal.GetMountInfoByID(slot.id))
        else
            id = slot.id
        end
        local info = id and C_Spell.GetSpellCooldown(id)
        if info then return info.startTime, info.duration, info.isEnabled end
    elseif k == "item" or k == "toy" then
        if slot.id and C_Item.GetItemCooldown then
            return C_Item.GetItemCooldown(slot.id)
        end
    end
    return nil
end

-- Build a slot table from whatever is on the cursor. Returns nil when the
-- cursor holds something the wheel can't fire.
local function SlotFromCursor()
    local cursorType, a, b, c = GetCursorInfo()
    if not cursorType then return nil end

    if cursorType == "spell" then
        -- Position 2 is the spellbook SLOT, not the spell -- Blizzard's own
        -- comment says so at SharedUIPanelTemplates.lua:1823, where it reads
        -- select(4, GetCursorInfo()) for the id. No fallback to position 2:
        -- that would store a slot number as a spellID and silently create a
        -- slot that casts the wrong thing.
        if type(c) ~= "number" then return nil end
        return { kind = "spell", id = c }

    elseif cursorType == "item" then
        local itemID = tonumber(a)
        if not itemID then return nil end
        return { kind = "item", id = itemID }

    elseif cursorType == "macro" then
        local name = GetMacroInfo(a)
        if not name then return nil end
        return { kind = "macro", id = a, name = name }

    elseif cursorType == "mount" then
        -- Position 2 is the mountID: Blizzard reads it exactly this way at
        -- SharedUIPanelTemplates.lua:1827. Guessing at other positions is
        -- unsafe here because display indices and mountIDs are both small
        -- integers, so a wrong guess resolves to a real but unrelated mount.
        local mountID = tonumber(a)
        if not mountID then return nil end
        local name, spellID = C_MountJournal.GetMountInfoByID(mountID)
        if not name then return nil end
        return { kind = "mount", id = mountID, spellID = spellID, name = name }

    elseif cursorType == "toy" then
        local itemID = tonumber(a)
        if not itemID then return nil end
        return { kind = "toy", id = itemID }

    elseif cursorType == "battlepet" then
        if not a then return nil end
        return { kind = "battlepet", guid = a }
    end

    return nil
end
ns.SlotFromCursor = SlotFromCursor

-------------------------------------------------------------------------------
--  Wheel view  --  the renderer, instanced
--
--  Two instances exist: the live wheel and the options-page preview. Sharing
--  one renderer is the whole point of the split -- the preview's wedge order,
--  angles and hit test ARE the live wheel's, so what the user arranges in the
--  panel is exactly what they steer at in play.
--
--  A view owns its container frame, the center hub, and a pool of MAX_SLOTS
--  slot widgets. It does NOT own interaction: the live wheel drives itself from
--  ns.Open/ns.Close, and the preview installs its own scripts on the widgets it
--  gets back from GetSlotWidget.
-------------------------------------------------------------------------------
local views = {}            -- every view, live and preview
local liveView              -- the wheel the keybinds open
local openedAt = 0

-- A held key whose up-event never reaches us (alt-tab, /reload prompt, a
-- taxi takeoff) would otherwise leave the wheel on screen forever.
local OPEN_TIMEOUT = 30

-- Selection is drawn with two cues only: the icon border takes the selection
-- color and thickens, and the wedge scales up. No additive glow -- at ring
-- scale it bloomed over the neighbouring wedges and made the border it was
-- supposed to emphasise harder to read.
local SEL_BORDER = 2
local IDLE_BORDER = 1

-- zoom overrides the selected-slot magnification. The fan modes pass 1: there
-- the centre entry is already the largest by construction, and scaling it
-- further would break the strip's spacing, which is measured in the parent's
-- unscaled space.
local function ApplySlotVisual(widget, selected, zoom)
    local p = P()
    local r, g, b = SelectColor()
    local t = selected and SEL_BORDER or IDLE_BORDER
    widget.border:SetPoint("TOPLEFT", widget, "TOPLEFT", -t, t)
    widget.border:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", t, -t)
    if selected then
        widget:SetScale(zoom or (p and p.selectedZoom) or 1.15)
        widget.border:SetVertexColor(r, g, b, 1)
        widget.bg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22, min(1, (p and p.bgAlpha or 0.65) + 0.25))
        widget.icon:SetVertexColor(1, 1, 1)
        widget.label:SetTextColor(r, g, b)
    else
        widget:SetScale(1)
        widget.border:SetVertexColor(0, 0, 0, 0.9)
        widget.bg:SetVertexColor(0.05, 0.05, 0.06, p and p.bgAlpha or 0.65)
        widget.icon:SetVertexColor(0.72, 0.72, 0.72)
        widget.label:SetTextColor(0.75, 0.75, 0.75)
    end
end

local function CreateSlotWidget(view, index)
    local w = CreateFrame("Button", nil, view.frame, "BackdropTemplate")
    w.index = index

    w.bg = w:CreateTexture(nil, "BACKGROUND")
    w.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    w.bg:SetAllPoints(w)

    w.border = w:CreateTexture(nil, "BORDER")
    w.border:SetTexture("Interface\\Buttons\\WHITE8X8")
    w.border:SetPoint("TOPLEFT", w, "TOPLEFT", -1, 1)
    w.border:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", 1, -1)

    -- The border texture sits behind bg, so it reads as a 1px outline.
    w.bg:SetDrawLayer("BACKGROUND", 1)
    w.border:SetDrawLayer("BACKGROUND", 0)

    w.icon = w:CreateTexture(nil, "ARTWORK")
    w.icon:SetPoint("TOPLEFT", w, "TOPLEFT", 2, -2)
    w.icon:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -2, 2)
    w.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    w.cd = CreateFrame("Cooldown", nil, w, "CooldownFrameTemplate")
    w.cd:SetAllPoints(w.icon)
    w.cd:SetHideCountdownNumbers(false)
    w.cd:SetDrawEdge(false)

    w.label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.label:SetPoint("TOP", w, "BOTTOM", 0, -2)
    w.label:SetWidth(96)
    w.label:SetWordWrap(false)

    -- The "+" affordance for an interactive view's trailing placeholder wedge.
    -- Created unconditionally; Layout is what decides whether it is ever shown.
    w.plus = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    w.plus:SetPoint("CENTER")
    w.plus:SetText("+")
    w.plus:Hide()

    w:EnableMouse(false)
    return w
end

local WheelView = {}
local WheelViewMeta = { __index = WheelView }

local function DefaultGeom()
    local p = P()
    if not p then return 96, 44, 24 end
    return p.radius or 96, p.iconSize or 44, p.deadZone or 24
end

-- radius, iconSize, deadZone for this view. Called through a plain function
-- call, never `opts.geom and opts.geom()` -- an `and` expression is truncated
-- to one value and would drop iconSize and deadZone on the floor.
function WheelView:Geom()
    return (self.opts.geom or DefaultGeom)()
end

function WheelView:GetFrame()     return self.frame end
function WheelView:GetRingIndex() return self.ringIndex end
function WheelView:GetSelection() return self.selection end
function WheelView:SlotCount()    return self.slotCount end
function WheelView:ShownCount()   return self.shownCount end
function WheelView:GetSlotWidget(index) return self.widgets[index] end

-- RADIAL | FAN_H | FAN_V. A view may pin its own mode (the options preview
-- pins one so the page can show either without changing what the user plays
-- with); everything else follows the profile.
function WheelView:LayoutMode()
    local p = P()
    return self.opts.layout or (p and p.layout) or "RADIAL"
end

function WheelView:IsFan()
    return self:LayoutMode() ~= "RADIAL"
end

function WheelView:IsGrid()
    return self:LayoutMode() == "GRID"
end

-- Angular step and starting angle for the radial layout, both clockwise from
-- straight up. Returns the step, the angle of slot 1, and whether this is a
-- full circle.
--
-- A full circle divides by the entry count and wraps: the last entry's far side
-- is the first entry's near side, so there is no seam. An arc divides by count
-- MINUS ONE instead, which puts the first and last entries ON its ends rather
-- than leaving a step-wide gap at the seam that belongs to no entry at all.
function WheelView:ArcGeom(shown)
    local p = P()
    local deg  = min(360, max(30, (p and p.arcSpan) or 360))
    local rot  = ((p and p.arcRotation) or 0) * pi / 180

    if deg >= 359.5 then
        return (shown > 0) and (TWO_PI / shown) or 0, rot, true
    end

    local span = deg * pi / 180
    local step = (shown > 1) and (span / (shown - 1)) or 0
    return step, rot - span * 0.5, false
end

-- A cursor-steered fan: every entry drawn at a fixed position, the nearest one
-- zoomed. The editor follows the profile here like everything else, so what it
-- lays out stays the arrangement the user actually plays with.
function WheelView:IsHoverFan()
    if self:IsGrid() or not self:IsFan() then return false end
    local p = P()
    return (p and p.fanInput or "SCROLL") == "CURSOR"
end

-- Everything steered by pointing at a fixed arrangement, as opposed to the
-- scroll fan's moving one. These all share the grid's geometry and its update.
function WheelView:IsPointerLayout()
    return self:IsGrid() or self:IsHoverFan()
end

-------------------------------------------------------------------------------
--  Fan layout
--
--  A coverflow strip: the selected entry sits at the centre at full size, and
--  its neighbours shrink and fade by a fixed per-step ratio. Selection is
--  whatever is centred, so there is no hit test at all -- the mouse wheel
--  scrubs the strip and the centre is the answer.
--
--  Distance from the centre is the INTEGRAL of the scale curve plus a constant
--  gap rather than a sum of discrete steps. Two reasons: the spacing then
--  derives from the sizes it separates, so the strip tapers instead of leaving
--  shrunken icons floating in dead space; and it stays defined for fractional
--  offsets, which is what lets the strip slide smoothly between slots.
-------------------------------------------------------------------------------

-- Editor floors. The options preview draws the whole ring at once and every
-- entry in it is a drag target, so the live floors -- which are tuned to let
-- distant entries fade away -- would leave the ends of a long strip both
-- unreadable and hard to hit.
local FAN_EDIT_MIN_SCALE = 0.45
local FAN_EDIT_MIN_ALPHA = 0.45

-- Signed distance is applied by the caller; k is always >= 0 here.
--
-- minScale is not optional cosmetics: scale stops shrinking at the floor, so
-- spacing has to stop shrinking there too. Integrating the raw curve past that
-- point keeps closing the gaps under icons that have stopped getting smaller,
-- and they overlap. Past the knee the strip is therefore evenly spaced at the
-- floored size.
local function FanOffset(k, size, gap, decay, minScale)
    -- decay ~= 1 makes the integral degenerate (and 1 means "no falloff", so
    -- even spacing is the right answer anyway).
    if decay >= 0.999 then return (size + gap) * k end
    local lnd = -log(decay)

    minScale = minScale or 0
    if minScale <= 0 then return size * (1 - decay ^ k) / lnd + gap * k end

    -- decay ^ knee == minScale, which is what makes the two branches meet.
    local knee = log(minScale) / log(decay)
    if k <= knee then return size * (1 - decay ^ k) / lnd + gap * k end
    return size * (1 - minScale) / lnd + gap * knee
           + (size * minScale + gap) * (k - knee)
end

-- Half-length of the editor's strip: centre to the outer edge of the last
-- entry, at the editor's own floors. Exported so the options preview can fit a
-- strip to the panel without duplicating any of the constants above.
function ns.FanReach(count, iconSize, gap, decay)
    return FanOffset(count, iconSize, gap, decay, FAN_EDIT_MIN_SCALE) + iconSize
end

-- The same measurement for a hover fan, which is evenly spaced at full pitch
-- because its zoomed entry is drawn at 1.0 and must not overlap its neighbours.
function ns.FanHoverReach(count, iconSize, gap)
    return count * 0.5 * (iconSize + gap) + iconSize * 0.5
end

-- Position every widget from self.fanVisual, the CONTINUOUS centre. Called
-- from Layout and from every animation step; it never repaints icons, so it is
-- cheap enough to run each frame while the strip settles.
function WheelView:ApplyFanGeometry()
    local p = P()
    if not p or not self:IsFan() then return end

    local shown = self.shownCount
    if shown < 1 then return end

    local _, iconSize = self:Geom()
    local gap    = p.fanGap or 10
    -- Clamped away from 0: FanOffset takes log(decay), which a saved value of
    -- zero would turn into a division by negative infinity.
    local decay  = min(1, max(0.05, p.fanScaleDecay or 0.72))
    local aDecay = min(1, max(0.05, p.fanAlphaDecay or 0.62))
    local minS   = p.fanMinScale or 0.30
    local minA   = p.fanMinAlpha or 0.12
    if self.opts.interactive then
        minS = max(minS, FAN_EDIT_MIN_SCALE)
        minA = max(minA, FAN_EDIT_MIN_ALPHA)
    end
    local horiz  = self:LayoutMode() == "FAN_H"
    -- An interactive view draws the whole ring: the editor cannot let a slot
    -- be unreachable, so nothing is culled there and the floors carry it.
    local window = self.opts.interactive and shown or (p.fanVisible or 3)

    local frame  = self.frame
    local center = self.fanVisual or 1
    local half   = shown / 2

    for i = 1, shown do
        local w = self.widgets[i]
        -- Shortest cyclic path, so wrapping past the end slides forward
        -- instead of rewinding the whole strip.
        local d = (i - center) % shown
        if d > half then d = d - shown end

        local k = abs(d)
        if k > window + 0.5 then
            w:Hide()
        else
            local s   = max(minS, decay ^ k)
            local off = FanOffset(k, iconSize, gap, decay, minS)
            if d < 0 then off = -off end

            w:SetAlpha(max(minA, aDecay ^ k))
            -- Depth is size, not scale: SetPoint offsets are read in the
            -- widget's own scaled space, so scaling here would silently
            -- multiply the spacing computed above.
            w:SetSize(iconSize * s, iconSize * s)
            w:ClearAllPoints()
            if horiz then
                w:SetPoint("CENTER", frame, "CENTER", off, 0)
            else
                w:SetPoint("CENTER", frame, "CENTER", 0, -off)
            end
            w:Show()
        end
    end
end

-------------------------------------------------------------------------------
--  Grid
--
--  Every entry at a fixed cell, the one nearest the pointer zoomed, everything
--  else falling off by distance. A pointer-steered FAN is this same layout one
--  entry deep -- FAN_H is a single row, FAN_V a single column -- so both route
--  here rather than into a parallel 1D implementation. This is
--  the mode that scales -- pointer travel to the worst entry grows with the
--  SQUARE ROOT of the count rather than linearly, and a fixed 2D arrangement is
--  far easier to build muscle memory against than a position along a line.
--
--  Rows are centred individually, so a short final row sits under the middle of
--  the one above it instead of hanging off the left edge.
-------------------------------------------------------------------------------

-- How far from EVERY entry, in cells, the pointer may stray before the grid
-- deselects. This is the grid's cancel: it has no dead zone to release inside.
local GRID_REACH = 1.0

-- A pointer-steered fan IS a grid one entry deep, so it resolves here rather
-- than in a parallel 1D implementation: FAN_H is a single row, FAN_V a single
-- column. Only the scroll-steered fan needs geometry of its own, because it
-- cycles a compressed window rather than showing fixed positions.
function WheelView:GridDims()
    local p = P()
    local shown = max(1, self.shownCount)

    local mode = self:LayoutMode()
    if mode == "FAN_H" then return shown, 1 end
    if mode == "FAN_V" then return 1, shown end

    local cols = min(MAX_SLOTS, max(1, floor((p and p.gridColumns) or 4)))
    if cols > shown then cols = shown end
    return cols, ceil(shown / cols)
end

-- Centre-relative position of slot i, in the frame's own units.
function WheelView:GridBase(i, cols, rows, pitch)
    local r = floor((i - 1) / cols)
    local c = (i - 1) % cols
    local inRow = min(cols, self.shownCount - r * cols)
    return (c - (inRow - 1) * 0.5) * pitch, -(r - (rows - 1) * 0.5) * pitch
end

-- Lay the grid out and select the entry nearest the pointer. noPointer draws it
-- evenly with nothing selected, which is what Layout and the editor want.
function WheelView:AdvanceGrid(noPointer)
    local p = P()
    local shown = self.shownCount
    if not p or shown < 1 then
        self:SetSelection(nil)
        return
    end

    local _, iconSize = self:Geom()
    local pitch  = iconSize + (p.fanGap or 10)
    local decay  = min(1, max(0.05, p.fanScaleDecay or 0.72))
    local aDecay = min(1, max(0.05, p.fanAlphaDecay or 0.62))
    local minS   = p.fanMinScale or 0.30
    local minA   = p.fanMinAlpha or 0.12
    if self.opts.interactive then
        minS = max(minS, FAN_EDIT_MIN_SCALE)
        minA = max(minA, FAN_EDIT_MIN_ALPHA)
    end

    local cols, rows = self:GridDims()
    local frame = self.frame

    -- Pointer offset from the grid's centre, or nil while the movement gate is
    -- still armed -- without it an entry is selected the instant the grid opens
    -- and "open and release" would fire instead of cancelling.
    local dx, dy
    local fx, fy = frame:GetCenter()
    if fx and not noPointer then
        local es = frame:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        mx, my = mx / es, my / es
        if not self._steered
           and (abs(mx - self._gateX) >= 1 or abs(my - self._gateY) >= 1) then
            self._steered = true
        end
        if self._steered then dx, dy = mx - fx, my - fy end
    end

    local best, bestK
    for i = 1, shown do
        local w = self.widgets[i]
        local bx, by = self:GridBase(i, cols, rows, pitch)

        -- Falloff is the true 2D distance, in cells. A grid has no privileged
        -- axis, so projecting onto one -- as the strip does -- would make the
        -- zoom respond to sideways movement it should ignore.
        local s, a = max(minS, decay), 1
        if dx then
            local ox, oy = (dx - bx) / pitch, (dy - by) / pitch
            local k = sqrt(ox * ox + oy * oy)
            s = max(minS, decay ^ k)
            a = max(minA, aDecay ^ k)
            if not bestK or k < bestK then best, bestK = i, k end
        end

        w:SetAlpha(a)
        w:SetSize(iconSize * s, iconSize * s)
        w:ClearAllPoints()
        w:SetPoint("CENTER", frame, "CENTER", bx, by)
        w:Show()
    end

    if bestK and bestK > GRID_REACH then best = nil end
    self:SetSelection(best)
end

-- Centre the strip on a slot with no animation. The options preview uses this
-- to follow the entry the user has clicked.
function WheelView:SetFanCenter(index)
    if not index or self.shownCount < 1 then return end
    self.fanTarget = index
    self.fanVisual = index
    self:ApplyFanGeometry()
    self:SetSelection(index)
end

-- One scroll tick. delta is +1 toward later slots, -1 toward earlier ones.
function WheelView:FanScroll(delta)
    local shown = self.shownCount
    if shown < 1 then return end

    if not self.fanTarget then
        -- The strip opens with NOTHING selected, and the first tick is what
        -- enters it. That preserves the radial's contract exactly: release
        -- without steering cancels. Wrapping afterwards cycles real entries
        -- only, so the cancel state is never scrolled back into.
        --
        -- fanVisual is left alone: it already sits on entry 1 from Open, so a
        -- forward tick just lights that entry up rather than shunting the
        -- strip a step and sliding it back.
        -- 0, not `shown`, for a backward first tick: fanTarget is an unbounded
        -- accumulator that the animation follows literally, and 0 is one step
        -- back from entry 1, where `shown` would be a full lap forward. The
        -- selection modulo below maps 0 onto the last entry either way.
        self.fanTarget = (delta > 0) and 1 or 0
    else
        self.fanTarget = self.fanTarget + delta
    end
end

-- Advance the settle animation and publish the centred entry as the selection.
-- The LOGICAL index moves the instant the tick arrives; only the geometry is
-- interpolated. A release mid-animation therefore always fires what the user
-- last scrolled to, never whatever the strip happens to be sliding past.
function WheelView:AdvanceFan(elapsed)
    local shown = self.shownCount
    if shown < 1 then
        self:SetSelection(nil)
        return
    end

    local target = self.fanTarget or 1
    local cur    = self.fanVisual or target
    if cur ~= target then
        local p = P()
        local t = (p and p.fanAnimTime) or 0.10
        if t <= 0 then
            cur = target
        else
            cur = cur + (target - cur) * min(1, (elapsed or 0) / t)
            -- Snap the tail: an asymptote would keep this view dirty forever.
            if abs(target - cur) < 0.001 then cur = target end
        end
        self.fanVisual = cur
        self:ApplyFanGeometry()
    end

    if self.fanTarget then
        self:SetSelection(((self.fanTarget - 1) % shown) + 1)
    else
        self:SetSelection(nil)
    end
end

-- This view's centre as a delta from UIParent's centre, in UIParent-logical
-- units. Both sides are converted through their effective scales because the
-- strip carries the user's own Scale setting while UIParent carries the game's.
function WheelView:ScreenOffset()
    local frame = self.frame
    local cx, cy = frame:GetCenter()
    if not cx then return 0, 0 end
    local ux, uy = UIParent:GetCenter()
    if not ux then return 0, 0 end

    local k = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return cx * k - ux, cy * k - uy
end

-- Hang the caption on the side that faces the middle of the screen, so a strip
-- opened near an edge writes inward -- where there is room -- instead of off
-- the edge. Justification follows, always hugging the icon it belongs to: the
-- text grows away from the strip, never back across it.
--
-- Called after the frame is POSITIONED, not from Layout alone: in cursor mode
-- the strip lands somewhere new on every open, so the quadrant is only known
-- once PositionWheel has run.
function WheelView:PlaceHubText()
    local hub  = self.hub
    local mode = self:LayoutMode()
    local _, iconSize = self:Geom()

    hub.text:ClearAllPoints()
    hub.hint:ClearAllPoints()

    if mode == "RADIAL" then
        hub.text:SetJustifyH("CENTER")
        hub.text:SetPoint("CENTER", hub, "CENTER", 0, 0)
        hub.hint:SetPoint("TOP", hub.text, "BOTTOM", 0, -2)
        return
    end

    -- Half the extent the caption has to clear on its own axis. A strip is one
    -- entry deep, but a grid is as deep as it has rows.
    local pad = iconSize * 0.5 + 14
    if mode == "GRID" then
        local p = P()
        local _, rows = self:GridDims()
        pad = rows * (iconSize + ((p and p.fanGap) or 10)) * 0.5 + 14
    end
    -- The editor is pinned rather than quadrant-tested: its block sits wherever
    -- the options page happens to be scrolled to, and a caption that jumped
    -- sides as the user scrolled would read as a glitch.
    local dx, dy = 0, 0
    if not self.opts.interactive then dx, dy = self:ScreenOffset() end

    -- A grid captions like a horizontal strip: it is as wide as it is tall, so
    -- there is no side with obviously more room, and above/below keeps the text
    -- clear of every cell rather than only of the middle column.
    if mode == "FAN_H" or mode == "GRID" then
        -- Below the middle of the screen -> caption above the strip.
        hub.text:SetJustifyH("CENTER")
        if dy < 0 then
            hub.text:SetPoint("BOTTOM", hub, "CENTER", 0, pad)
            hub.hint:SetPoint("BOTTOM", hub.text, "TOP", 0, 2)
        else
            hub.text:SetPoint("TOP", hub, "CENTER", 0, -pad)
            hub.hint:SetPoint("TOP", hub.text, "BOTTOM", 0, -2)
        end
    else
        -- Right of the middle of the screen -> caption to the LEFT, right
        -- justified so its last character sits against the icon.
        if dx > 0 then
            hub.text:SetJustifyH("RIGHT")
            hub.text:SetPoint("RIGHT", hub, "CENTER", -pad, 0)
            hub.hint:SetPoint("TOPRIGHT", hub.text, "BOTTOMRIGHT", 0, -2)
        else
            hub.text:SetJustifyH("LEFT")
            hub.text:SetPoint("LEFT", hub, "CENTER", pad, 0)
            hub.hint:SetPoint("TOPLEFT", hub.text, "BOTTOMLEFT", 0, -2)
        end
    end
end

function ns.CreateWheelView(parent, opts)
    local view = setmetatable({
        opts      = opts or {},
        widgets   = {},
        ringIndex = 1,
        slotCount = 0,
        shownCount = 0,
        -- Only the live wheel arms the movement gate (see HitTest); anything
        -- else is steered from the moment it exists.
        _steered  = true,
    }, WheelViewMeta)

    local frame = CreateFrame("Frame", view.opts.frameName, parent)
    frame:SetSize(1, 1)
    frame:EnableMouse(false)
    view.frame = frame

    -- Hub: the center disc. Shows the selected action's name, or the ring
    -- name when nothing is selected, which is also the "release now cancels"
    -- signal.
    local hub = CreateFrame("Frame", nil, frame)
    hub:SetSize(2, 2)
    hub:SetPoint("CENTER")
    view.hub = hub

    hub.dot = hub:CreateTexture(nil, "ARTWORK")
    hub.dot:SetTexture("Interface\\Cooldown\\star4")
    hub.dot:SetBlendMode("ADD")
    hub.dot:SetPoint("CENTER")
    hub.dot:SetSize(26, 26)
    hub.dot:SetAlpha(0.5)

    -- Needle: a thin bar whose center is placed halfway out along the
    -- selected direction and rotated to match it, so it reads as a pointer
    -- emanating from the hub.
    hub.needle = hub:CreateTexture(nil, "OVERLAY")
    hub.needle:SetTexture("Interface\\Buttons\\WHITE8X8")
    hub.needle:SetSize(3, 30)
    hub.needle:Hide()

    hub.text = hub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hub.text:SetPoint("CENTER", hub, "CENTER", 0, 0)
    hub.text:SetWidth(150)
    hub.text:SetWordWrap(false)

    hub.hint = hub:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hub.hint:SetPoint("TOP", hub.text, "BOTTOM", 0, -2)

    for i = 1, MAX_SLOTS do view.widgets[i] = CreateSlotWidget(view, i) end

    views[#views + 1] = view
    return view
end

-- Lay the ring out and paint every widget from the stored slot data.
function WheelView:Layout(ringIndex)
    -- Clamped because a view's ring index outlives a decrease of ringCount, and
    -- EnsureRing would otherwise re-create a ring the user can no longer bind.
    ringIndex = min(RingCount(), max(1, ringIndex or self.ringIndex or 1))
    local p, ring = P(), EnsureRing(ringIndex)
    if not p or not ring then return end

    local opts = self.opts
    self.ringIndex = ringIndex
    -- Derived, never stored: the ring is exactly as big as what is on it.
    local n = #ring.slots
    -- An interactive view draws one wedge more than the ring holds: the "+"
    -- placeholder. It is a real wedge, so adding an action visibly re-fans the
    -- ring instead of filling a gap that was reserved for it all along.
    local shown = (opts.interactive and n < MAX_SLOTS) and (n + 1) or n
    self.slotCount, self.shownCount = n, shown

    local step, arcStart = self:ArcGeom(shown)
    local radius, iconSize = self:Geom()
    local fan = self:IsFan()

    local frame = self.frame
    -- p.scale is the user's live sizing; a fitted preview supplies its own
    -- geometry instead and must not be scaled a second time.
    if not opts.interactive then frame:SetScale(p.scale or 1) end
    if self:IsPointerLayout() then
        -- One sizing rule for the grid and both pointer-steered strips: a strip
        -- is just a grid one entry deep, so GridDims has already reduced it to
        -- the same cols/rows the extent is measured from.
        local pitch = iconSize + (p.fanGap or 10)
        local cols, rows = self:GridDims()
        frame:SetSize(cols * pitch + 40, rows * pitch + 60)
    elseif fan then
        local window = opts.interactive and shown or (p.fanVisible or 3)
        local reach = FanOffset(window, iconSize, p.fanGap or 10,
                                p.fanScaleDecay or 0.72,
                                opts.interactive and FAN_EDIT_MIN_SCALE
                                                  or (p.fanMinScale or 0.30)) + iconSize
        local along  = reach * 2 + 40
        local across = iconSize + 60      -- room for the hub caption
        if self:LayoutMode() == "FAN_H" then
            frame:SetSize(along, across)
        else
            frame:SetSize(across, along)
        end
    else
        -- Sized generously so labels and the selected-slot zoom never clip.
        local span = (radius + iconSize) * 2 + 40
        frame:SetSize(span, span)
    end

    local showLabels = opts.showLabels
    if showLabels == nil then showLabels = p.showLabels end
    local showCooldowns = opts.showCooldowns
    if showCooldowns == nil then showCooldowns = p.showCooldowns end

    for i = 1, MAX_SLOTS do
        local w = self.widgets[i]
        if i <= shown then
            -- Switching modes leaves the other mode's depth cues behind.
            w:SetAlpha(1)
            w:SetScale(1)
            if not fan then
                local a = arcStart + (i - 1) * step
                w:ClearAllPoints()
                w:SetPoint("CENTER", frame, "CENTER", radius * sin(a), radius * cos(a))
                w:SetSize(iconSize, iconSize)
            end
            w:EnableMouse(opts.interactive == true)

            local slot = ring.slots[i]
            -- Only reachable on an interactive view: shown == n otherwise.
            local placeholder = (slot == nil)
            w.isPlaceholder = placeholder

            local icon, name = SlotDisplay(slot)
            w.icon:SetTexture(icon or QUESTION_MARK)
            w.icon:SetShown(not placeholder)
            w.plus:SetShown(placeholder)
            -- The fan never labels its entries: at strip spacing the captions
            -- of neighbouring icons collide, and the centre entry -- the only
            -- one that can be fired -- is already named on the hub.
            local wantLabel = showLabels and not fan and name ~= nil
            w.label:SetText((wantLabel and name) or "")
            w.label:SetShown(wantLabel or false)

            if showCooldowns and slot then
                local start, duration, enable = SlotCooldown(slot)
                if start then
                    CooldownFrame_Set(w.cd, start, duration, enable)
                else
                    w.cd:Clear()
                end
                w.cd:Show()
            else
                w.cd:Clear()
                w.cd:Hide()
            end

            ApplySlotVisual(w, false)
            w:Show()
        else
            w:Hide()
            w:EnableMouse(false)
        end
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
    hub.needle:SetShown(false)
    -- In fan modes the centre of the frame is occupied by the selected entry,
    -- so the hub's disc would sit under it and its caption on top of it. Drop
    -- the disc and hang the caption clear of the strip instead.
    hub.dot:SetShown(not fan)
    self:PlaceHubText()
    hub.text:SetText(ring.name or ("Ring " .. ringIndex))
    hub.text:SetTextColor(0.8, 0.8, 0.8)

    if opts.hintText then
        hub.hint:SetText(opts.hintText(n) or "")
    elseif n == 0 then
        -- An empty ring is a real state now, and a bare hub with no explanation
        -- looks like a bug rather than "you haven't filled this in yet".
        hub.hint:SetText("no actions assigned")
    else
        local k1 = GetBindingKey(BINDING_PREFIX .. ringIndex)
        hub.hint:SetText(p.showHubText and (k1 or "") or "")
    end
end

-- Paint selection state. Called from OnUpdate whenever the hovered slot
-- changes, and once from Open so the initial state is drawn.
function WheelView:SetSelection(index)
    if self.selection == index then return end

    local widgets = self.widgets
    if self.selection and widgets[self.selection] then
        ApplySlotVisual(widgets[self.selection], false)
    end
    self.selection = index

    local p = P()
    local hub = self.hub

    if index then
        local w = widgets[index]
        ApplySlotVisual(w, true, self:IsFan() and 1 or nil)

        local ring = EnsureRing(self.ringIndex)
        local slot = ring and ring.slots[index]
        local _, name = SlotDisplay(slot)
        local r, g, b = SelectColor()
        hub.text:SetText(name or (w.isPlaceholder and "Add Action") or ("Slot " .. index))
        hub.text:SetTextColor(r, g, b)

        -- The needle points along a wedge angle; the fan has no angles.
        if p and p.showNeedle and not self:IsFan() then
            local radius, iconSize, deadZone = self:Geom()
            local step, arcStart = self:ArcGeom(self.shownCount)
            local a = arcStart + (index - 1) * step
            local mid = (deadZone + radius - iconSize * 0.5) * 0.5
            hub.needle:ClearAllPoints()
            hub.needle:SetPoint("CENTER", hub, "CENTER", mid * sin(a), mid * cos(a))
            hub.needle:SetRotation(-a)
            hub.needle:SetVertexColor(r, g, b, 0.9)
            hub.needle:Show()
        end
    else
        local ring = EnsureRing(self.ringIndex)
        hub.text:SetText((ring and ring.name) or "")
        hub.text:SetTextColor(0.8, 0.8, 0.8)
        hub.needle:Hide()
    end
end

-- Baseline for the movement gate in HitTest. Read AFTER the frame is placed so
-- the scale used here is the one the hit test will use.
function WheelView:ArmMovementGate()
    local es = self.frame:GetEffectiveScale()
    local x, y = GetCursorPosition()
    self._gateX, self._gateY = x / es, y / es
    self._steered = false
end

-- Cursor -> wedge index. nil inside the dead zone, and -- while the movement
-- gate is armed -- until the cursor has actually moved. The gate is what makes
-- "open and release without moving" a cancel in FIXED-POSITION mode, where the
-- cursor starts at some arbitrary point on the ring rather than at the center
-- and would otherwise have a slot pre-selected the instant the wheel opens.
function WheelView:HitTest()
    local shown = self.shownCount
    if shown < 1 then return nil end
    local _, _, deadZone = self:Geom()

    local frame = self.frame
    local es = frame:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    mx, my = mx / es, my / es

    if not self._steered then
        if abs(mx - self._gateX) < 1 and abs(my - self._gateY) < 1 then return nil end
        self._steered = true
    end

    local cx, cy = frame:GetCenter()
    if not cx then return nil end

    local dx, dy = mx - cx, my - cy
    local dist = sqrt(dx * dx + dy * dy)
    if dist < deadZone then return nil end

    -- atan2(dx, dy) measures clockwise from straight up, matching the layout
    -- (slot 1 at 12 o'clock, index increasing clockwise).
    local theta = atan2(dx, dy)
    if theta < 0 then theta = theta + TWO_PI end

    local step, arcStart, full = self:ArcGeom(shown)
    if step == 0 then return 1 end

    local rel = theta - arcStart
    if full then return (floor(rel / step + 0.5) % shown) + 1 end

    -- Resolved into [0, TWO_PI) from the arc's start, NOT into (-pi, pi]: an arc
    -- may span up to a full turn, so an offset of more than half a turn is a
    -- legitimate position near its end rather than a negative one near its
    -- start. Folding it would silently amputate everything past 180 degrees.
    rel = rel % TWO_PI

    -- The arc owns half a step past its last entry, the same width every
    -- interior entry gets. Beyond that is a miss, not a clamp: outside the arc
    -- is the only place its cancel can live once the dead zone has been left.
    if rel > (shown - 1) * step + step * 0.5 then return nil end

    local idx = floor(rel / step + 0.5) + 1
    if idx < 1 or idx > shown then return nil end
    return idx
end

-------------------------------------------------------------------------------
--  The live wheel
-------------------------------------------------------------------------------
local function CreateWheel()
    if liveView then return liveView end
    liveView = ns.CreateWheelView(UIParent, { frameName = "EUIRadialWheelFrame" })
    local f = liveView:GetFrame()
    f:SetFrameStrata(LIVE_STRATA)
    f:Hide()
    return liveView
end

-- Scroll capture. The wheel is camera zoom by default, so the fan modes have
-- to take it while the strip is open. A frame only sees OnMouseWheel when the
-- cursor is over it, and in CURSOR mode the strip is drawn AT the cursor -- but
-- the cursor can also be parked anywhere in SCREEN mode, so the catcher is
-- full-screen rather than the strip itself.
--
-- An override binding on MOUSEWHEELUP/DOWN would be the other way to do this,
-- and is not an option: those are protected and could not be claimed at open
-- time in combat, which is exactly when the wheel gets used.
--
-- Mouse WHEEL only, never EnableMouse: a full-screen mouse-enabled frame would
-- sit between the player and the world, and would swallow the very button
-- presses the secure activation path depends on.
local scrollCatcher
local function EnsureScrollCatcher()
    if scrollCatcher then return scrollCatcher end
    local f = CreateFrame("Frame", "EUIRadialWheelScrollCatcher", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata(LIVE_STRATA)
    f:SetFrameLevel(1)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        if not liveView or not liveView:IsFan() then return end
        local p = P()
        if p and p.fanInvert then delta = -delta end
        -- Scrolling up travels toward earlier entries, which is the direction
        -- they are drawn in for FAN_V and the natural reading order for FAN_H.
        liveView:FanScroll(delta > 0 and -1 or 1)
    end)
    f:Hide()
    scrollCatcher = f
    return f
end

-- Flick-ahead. The ring is held invisible for a moment after the key goes down
-- and then fades in, so a gesture finished inside that window never summons a
-- menu at all. It is a DRAWING delay only: the frame is shown and its OnUpdate
-- is running the whole time, so the selection a fast flick lands on is exactly
-- the one a slow one would have.
--
-- Radial only. A fan has to be read before it can be steered, and a scroll fan
-- cannot even be entered without seeing where the strip starts.
local function UpdateFlickAlpha()
    local p = P()
    local frame = liveView:GetFrame()
    if not p or not p.flickAhead or liveView:IsFan() then
        frame:SetAlpha(1)
        return
    end

    local delay = p.flickDelay or 0.12
    local fade  = p.flickFade or 0.10
    local t = GetTime() - openedAt
    if t <= delay then
        frame:SetAlpha(0)
    elseif fade <= 0 or t >= delay + fade then
        frame:SetAlpha(1)
    else
        frame:SetAlpha((t - delay) / fade)
    end
end

local function OnWheelUpdate(_, elapsed)
    if GetTime() - openedAt > OPEN_TIMEOUT then
        ns.Close()
        return
    end
    UpdateFlickAlpha()
    if liveView:IsPointerLayout() then
        liveView:AdvanceGrid()
    elseif liveView:IsFan() then
        liveView:AdvanceFan(elapsed)
    else
        liveView:SetSelection(liveView:HitTest())
    end
end

-- forceFixed: ignore CURSOR mode and place the wheel at its fixed position.
-- Nothing passes it since the full-screen editor was retired; it stays because
-- on-screen drag positioning is being reworked and needs exactly this. Fixed
-- Position mode itself goes through the same branch via p.centerMode.
local function PositionWheel(forceFixed)
    local p = P()
    local wheel = liveView:GetFrame()
    wheel:ClearAllPoints()
    if forceFixed or p.centerMode == "SCREEN" then
        local s = p.scale or 1
        if s == 0 then s = 1 end
        wheel:SetPoint("CENTER", UIParent, "CENTER", (p.posX or 0) / s, (p.posY or 0) / s)
    else
        local es = wheel:GetEffectiveScale()
        local x, y = GetCursorPosition()
        wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / es, y / es)
    end
end

function ns.Open(ringIndex)
    local p = P()
    if not p or not p.enabled then return end

    CreateWheel()
    liveView:Layout(ringIndex)
    PositionWheel()
    -- After PositionWheel, never before: which side the caption hangs on is
    -- decided by where on the screen this open actually landed, and in cursor
    -- mode that is different every time.
    liveView:PlaceHubText()

    openedAt = GetTime()

    if liveView:IsPointerLayout() then
        -- Nothing selected until the pointer moves, and straying more than a
        -- cell from every entry deselects again -- these layouts' dead zone.
        liveView:ArmMovementGate()
        liveView:AdvanceGrid(true)
        liveView:SetSelection(nil)
    elseif liveView:IsFan() then
        -- Open with no selection at all: the first scroll tick is what enters
        -- the strip, so releasing without scrolling cancels, exactly as
        -- releasing inside the dead zone does in RADIAL.
        liveView.fanTarget = nil
        liveView.fanVisual = 1
        liveView:ApplyFanGeometry()
        liveView:SetSelection(nil)
        EnsureScrollCatcher():Show()
    else
        liveView:ArmMovementGate()
        liveView:SetSelection(liveView:HitTest())
    end

    local wheel = liveView:GetFrame()
    -- Applied before the first frame rather than left to OnUpdate: the wheel is
    -- shown on this one, and the previous open's alpha would flash through.
    UpdateFlickAlpha()
    wheel:SetScript("OnUpdate", OnWheelUpdate)
    wheel:Show()
end

function ns.Close()
    if not liveView then return end
    local wheel = liveView:GetFrame()
    if not wheel:IsShown() then return end
    wheel:SetScript("OnUpdate", nil)
    wheel:Hide()
    if scrollCatcher then scrollCatcher:Hide() end
    liveView.fanTarget = nil
    liveView:SetSelection(nil)
end

-- The slot the user is currently pointing at, or nil.
function ns.CurrentSlot()
    local selection = liveView and liveView:GetSelection()
    if not selection then return nil end
    local ring = EnsureRing(liveView:GetRingIndex())
    return ring and ring.slots[selection]
end

-------------------------------------------------------------------------------
--  Secure activation
-------------------------------------------------------------------------------
local secureButtons = {}
local bindOwner

local function OnPreClick(self, _, down)
    if down then
        -- The press must never fire an action: clear the type before the
        -- secure handler reads it, then open the wheel.
        self:SetAttribute("type", nil)
        ns.Open(self._ring)
    else
        -- The release is the activation. Commit the hovered slot so the
        -- secure handler picks it up on this very click.
        local slot = ns.CurrentSlot()
        local aType, aKey, aVal, clearKey = ResolveAction(slot)
        if aType then
            if clearKey then self:SetAttribute(clearKey, nil) end
            self:SetAttribute(aKey, aVal)
            self:SetAttribute("type", aType)
        else
            self:SetAttribute("type", nil)
        end
        self._pendingInsecure = (not aType) and slot or nil
    end
end

local function OnPostClick(self, _, down)
    if down then return end
    if self._pendingInsecure then
        FireInsecure(self._pendingInsecure)
        self._pendingInsecure = nil
    end
    self:SetAttribute("type", nil)
    ns.Close()
end

local function GetSecureButton(index)
    local btn = secureButtons[index]
    if btn then return btn end

    btn = CreateFrame("Button", "EUIRadialWheelButton" .. index, UIParent,
        "SecureActionButtonTemplate")
    btn._ring = index
    btn:RegisterForClicks("AnyDown", "AnyUp")

    -- SecureActionButton_OnClick performs the action on exactly one edge
    -- (SecureTemplates.lua:786-793):
    --
    --   clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)
    --
    -- Left unset, useOnKeyDown follows the ActionButtonUseKeyDown CVar, which
    -- is on by default -- so the DOWN edge would be the acting one. DOWN is
    -- where we open the wheel and clear "type", so it fires nothing, and UP is
    -- then skipped entirely: PreClick and PostClick still run, so the wheel
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

    secureButtons[index] = btn
    return btn
end

local bindingsDirty = false
local bindingSig = nil

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
    local count = RingCount()
    for i = 1, count do
        local k1, k2 = GetBindingKey(BINDING_PREFIX .. i)
        sig = sig .. "|" .. (k1 or "") .. "/" .. (k2 or "")
    end
    if sig == bindingSig then return end

    if InCombatLockdown() then
        bindingsDirty = true
        return
    end
    bindingsDirty = false
    bindingSig = sig

    if not bindOwner then bindOwner = CreateFrame("Frame") end
    ClearOverrideBindings(bindOwner)
    if not p.enabled then return end

    for i = 1, count do
        local btn = GetSecureButton(i)
        local k1, k2 = GetBindingKey(BINDING_PREFIX .. i)
        if k1 then SetOverrideBindingClick(bindOwner, false, k1, btn:GetName()) end
        if k2 then SetOverrideBindingClick(bindOwner, false, k2, btn:GetName()) end
    end
end

-- Re-read everything from the DB. Safe to call at any time; only redraws views
-- that are actually on screen.
function ns.Refresh()
    ns.UpdateBindings()

    if liveView and liveView:GetFrame():IsShown() then
        -- Read the selection before Layout, which clears it.
        local keep = liveView:GetSelection()
        liveView:Layout(liveView:GetRingIndex())
        local n = liveView:SlotCount()
        liveView:SetSelection(keep and n > 0 and min(keep, n) or nil)
    end

    -- Non-live views (the options preview) follow the same data, so a slider
    -- tick or a slot mutation has to repaint them too. IsVisible, not IsShown:
    -- the options page's wrapper is torn down and re-parented around them.
    for i = 1, #views do
        local v = views[i]
        if v ~= liveView and v:GetFrame():IsVisible() then
            v:Layout(v:GetRingIndex())
        end
    end
end

-- Options-panel entry point, matching the suite's _G._<PREFIX>_ convention.
_G._ERW_Apply = ns.Refresh

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
function ERW:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUIRadialWheelDB", DB_DEFAULTS)
    _G._ERW_AceDB = db
    ns.db = db

    _G.BINDING_HEADER_EUI_RADIAL = "EllesmereUI Radial Wheel"
    for i = 1, MAX_RINGS do
        _G["BINDING_NAME_" .. BINDING_PREFIX .. i] = "Open Radial Wheel " .. i
    end
end

function ERW:OnEnable()
    local p = P()
    if not p then return end

    -- Deliberately NOT gated on p.enabled. The module can be switched on from
    -- the options panel mid-session, and if the wheel and these three
    -- handlers only existed for a session that started enabled, that session
    -- would run without combat-deferred rebinding or stuck-wheel cleanup
    -- until a reload. Disabled costs nothing: UpdateBindings registers no
    -- keys, so nothing can open the wheel.
    for i = 1, RingCount() do EnsureRing(i) end
    CreateWheel()
    ns.UpdateBindings()

    self:RegisterEvent("UPDATE_BINDINGS", function() ns.UpdateBindings() end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if bindingsDirty then ns.UpdateBindings() end
    end)
    -- A zone change while the key is held (portals, taxi) can swallow the
    -- key-up; drop the wheel rather than leave it stuck.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() ns.Close() end)
end

-------------------------------------------------------------------------------
--  Slash command
-------------------------------------------------------------------------------
-- Rings are built in the options page's own preview now, so there is nothing
-- left for the command to toggle -- it just points the way.
_G.SLASH_EUIRADIALWHEEL1 = "/euirw"
_G.SLASH_EUIRADIALWHEEL2 = "/euiradial"
SlashCmdList.EUIRADIALWHEEL = function()
    EllesmereUI.Print("|cff0cd29fRadial Wheel:|r configure rings on the "
        .. "|cffffd100Radial Wheel|r options page -- pick the ring, then drag "
        .. "actions onto the preview.")
end
