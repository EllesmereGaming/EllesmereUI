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
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local sin, cos, atan2, sqrt, pi = math.sin, math.cos, math.atan2, math.sqrt, math.pi
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

        -- Geometry
        radius      = 96,
        iconSize    = 44,
        deadZone    = 24,
        scale       = 1.0,

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
--  Ring view  --  the renderer, instanced
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

local function ApplySlotVisual(widget, selected)
    local p = P()
    local r, g, b = SelectColor()
    local t = selected and SEL_BORDER or IDLE_BORDER
    widget.border:SetPoint("TOPLEFT", widget, "TOPLEFT", -t, t)
    widget.border:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", t, -t)
    if selected then
        widget:SetScale(p and p.selectedZoom or 1.15)
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

local RingView = {}
local RingViewMeta = { __index = RingView }

local function DefaultGeom()
    local p = P()
    if not p then return 96, 44, 24 end
    return p.radius or 96, p.iconSize or 44, p.deadZone or 24
end

-- radius, iconSize, deadZone for this view. Called through a plain function
-- call, never `opts.geom and opts.geom()` -- an `and` expression is truncated
-- to one value and would drop iconSize and deadZone on the floor.
function RingView:Geom()
    return (self.opts.geom or DefaultGeom)()
end

function RingView:GetFrame()     return self.frame end
function RingView:GetRingIndex() return self.ringIndex end
function RingView:GetSelection() return self.selection end
function RingView:SlotCount()    return self.slotCount end
function RingView:ShownCount()   return self.shownCount end
function RingView:GetSlotWidget(index) return self.widgets[index] end

function ns.CreateRingView(parent, opts)
    local view = setmetatable({
        opts      = opts or {},
        widgets   = {},
        ringIndex = 1,
        slotCount = 0,
        shownCount = 0,
        -- Only the live wheel arms the movement gate (see HitTest); anything
        -- else is steered from the moment it exists.
        _steered  = true,
    }, RingViewMeta)

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
function RingView:Layout(ringIndex)
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

    local step = shown > 0 and (TWO_PI / shown) or 0
    local radius, iconSize = self:Geom()

    local frame = self.frame
    -- p.scale is the user's live sizing; a fitted preview supplies its own
    -- geometry instead and must not be scaled a second time.
    if not opts.interactive then frame:SetScale(p.scale or 1) end
    -- Sized generously so labels and the selected-slot zoom never clip.
    local span = (radius + iconSize) * 2 + 40
    frame:SetSize(span, span)

    local showLabels = opts.showLabels
    if showLabels == nil then showLabels = p.showLabels end
    local showCooldowns = opts.showCooldowns
    if showCooldowns == nil then showCooldowns = p.showCooldowns end

    for i = 1, MAX_SLOTS do
        local w = self.widgets[i]
        if i <= shown then
            local a = (i - 1) * step
            w:ClearAllPoints()
            w:SetPoint("CENTER", frame, "CENTER", radius * sin(a), radius * cos(a))
            w:SetSize(iconSize, iconSize)
            w:EnableMouse(opts.interactive == true)

            local slot = ring.slots[i]
            -- Only reachable on an interactive view: shown == n otherwise.
            local placeholder = (slot == nil)
            w.isPlaceholder = placeholder

            local icon, name = SlotDisplay(slot)
            w.icon:SetTexture(icon or QUESTION_MARK)
            w.icon:SetShown(not placeholder)
            w.plus:SetShown(placeholder)
            w.label:SetText((showLabels and name) or "")
            w.label:SetShown((showLabels and name ~= nil) or false)

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

    local hub = self.hub
    hub.needle:SetShown(false)
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
function RingView:SetSelection(index)
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
        ApplySlotVisual(w, true)

        local ring = EnsureRing(self.ringIndex)
        local slot = ring and ring.slots[index]
        local _, name = SlotDisplay(slot)
        local r, g, b = SelectColor()
        hub.text:SetText(name or (w.isPlaceholder and "Add Action") or ("Slot " .. index))
        hub.text:SetTextColor(r, g, b)

        if p and p.showNeedle then
            local radius, iconSize, deadZone = self:Geom()
            local a = (index - 1) * (TWO_PI / self.shownCount)
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
function RingView:ArmMovementGate()
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
function RingView:HitTest()
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

    local step = TWO_PI / shown
    return (floor(theta / step + 0.5) % shown) + 1
end

-------------------------------------------------------------------------------
--  The live wheel
-------------------------------------------------------------------------------
local function CreateWheel()
    if liveView then return liveView end
    liveView = ns.CreateRingView(UIParent, { frameName = "EUIRadialWheelFrame" })
    local f = liveView:GetFrame()
    f:SetFrameStrata(LIVE_STRATA)
    f:Hide()
    return liveView
end

local function OnWheelUpdate()
    if GetTime() - openedAt > OPEN_TIMEOUT then
        ns.Close()
        return
    end
    liveView:SetSelection(liveView:HitTest())
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

    openedAt = GetTime()
    liveView:ArmMovementGate()
    liveView:SetSelection(liveView:HitTest())

    local wheel = liveView:GetFrame()
    wheel:SetScript("OnUpdate", OnWheelUpdate)
    wheel:Show()
end

function ns.Close()
    if not liveView then return end
    local wheel = liveView:GetFrame()
    if not wheel:IsShown() then return end
    wheel:SetScript("OnUpdate", nil)
    wheel:Hide()
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
