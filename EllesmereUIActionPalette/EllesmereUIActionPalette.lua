-------------------------------------------------------------------------------
--  EllesmereUIActionPalette.lua  --  hold-to-open action palette for EllesmereUI
--
--  Hold a keybind -> a set of slots appears. Choose one, release the key to
--  fire it. Releasing without having chosen cancels, and so does ESCAPE, which
--  every layout answers to for as long as it is open.
--
--  One palette of actions, drawn and steered three ways:
--
--    ARC     entries spread over `arcSpan` degrees, steered by the ANGLE from
--            the centre. The sectors are unbounded in depth, so the gesture is
--            a flick rather than a click. A span of 360 is the whole turn.
--    FAN     a strip running along one axis, horizontal or vertical by
--            `fanOrientation`. Scroll-steered it cycles a compressed window
--            past a fixed centre; pointer-steered it is a GRID one entry deep.
--    GRID    every entry at a fixed cell, the nearest one zoomed.
--
--  The layouts differ in INPUT MODEL -- angle, scroll-cycle, pointer-nearest --
--  which is why they are separate rather than parameters of one another. The
--  span is the exception: it is a parameter of the angular model, so the full
--  turn the module opened life as is simply the arc's 360-degree case.
--
--  Each palette owns one hidden SecureActionButtonTemplate button; the palette's
--  keybind is routed to it with SetOverrideBindingClick, and it is registered
--  for "AnyDown","AnyUp":
--
--    key DOWN -> our PreClick opens the palette; a secure snippet wrapped around
--                OnClick clears "type", so the press itself fires nothing
--    key UP   -> the snippet works out which entry the cursor is on and writes
--                that slot's action attributes, the secure handler performs the
--                cast, and our PostClick closes the palette
--
--  The choosing has to happen inside the snippet because an addon may not write
--  attributes to a protected frame during combat -- see the Secure activation
--  section for the blocked-action this design was built around. Only the
--  angular layouts are steered in the snippet so far; the others still commit
--  from Lua and therefore only fire out of combat.
--
--  Protected calls in this file, all of them deferred to PLAYER_REGEN_ENABLED
--  when in combat: the override-binding updates, and PushPalette's writes of a
--  palette's contents onto the secure buttons.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EAP = EllesmereUI.Lite.NewAddon(ADDON_NAME)

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

-- Palette / slot limits. MAX_BOUND_PALETTES must match the number of <Binding>
-- entries in Bindings.xml -- a palette past that has no key to open it, and
-- exists to be NESTED inside another palette. Storage therefore runs further
-- than binding does.
local MAX_BOUND_PALETTES = 6
local MAX_PALETTES = 16
local MAX_SLOTS = 12

-- Entries a nested palette contributes. A palette that is also bound to a key
-- keeps all MAX_SLOTS of its own slots when it is opened directly; only the
-- first MAX_CHILDREN are reachable through a parent. Every layout has to fit
-- them into a region bounded by the parent's own -- a sector of the arc, a row
-- outside the grid -- and eight is where all of those stop being readable.
local MAX_CHILDREN = 8

-- How far past its own ring a nested arc may be pushed before the children are
-- left to overlap instead. A narrow parent sector is answered by moving the
-- children outward (see ChildGeom), which is unbounded arithmetic: twelve
-- entries each holding eight would otherwise land them off the screen.
local CHILD_RADIUS_MAX_K = 3

-- The binding ACTION name, and it keeps the module's first name for good. WoW
-- stores a keybind against this string, so renaming it would unbind every
-- palette every user has set. The name is never shown: BINDING_NAME_<action>
-- below is what the Keybindings page reads.
local BINDING_PREFIX = "EUI_RADIAL"

-- DIALOG is also the options window's strata (EllesmereUI.lua:7126), which is
-- fine: the palette only exists on screen while a key is held.
local LIVE_STRATA = "DIALOG"

-------------------------------------------------------------------------------
--  Database
-------------------------------------------------------------------------------
local DB_DEFAULTS = {
    profile = {
        enabled     = true,

        -- Placement. posX/posY are a UIParent-LOGICAL delta from UIParent's
        -- center, i.e. independent of the palette's own scale -- the same
        -- convention MythicTimer's standalonePos uses
        -- (EllesmereUIMythicTimer.lua:2651). PositionPalette divides by scale at
        -- apply time, because SetPoint offsets live in the frame's own scaled
        -- space; without that, changing Scale would also move the palette.
        centerMode  = "CURSOR",      -- CURSOR | SCREEN
        posX        = 0,
        posY        = 0,

        -- Layout. ARC steers with the cursor's angle; FAN is a coverflow
        -- strip scrubbed with the mouse wheel, which keeps working while the
        -- right button is held to steer the camera and the cursor is therefore
        -- frozen. Orientation is a property of the strip, not a layout of its
        -- own: the two axes differ only in which way the entries run.
        layout          = "ARC",  -- ARC | FAN | GRID
        fanOrientation  = "HORIZONTAL",  -- HORIZONTAL | VERTICAL
        gridAutoColumns = true,      -- near-square, sized to what the palette holds
        gridColumns     = 4,         -- used only when gridAutoColumns is off

        -- Arc. 360 is a full turn. Anything less fans the entries across a
        -- sector centred on arcRotation (0 = straight up, growing clockwise),
        -- which keeps a palette clear of a screen edge and gives a nested palette
        -- somewhere to open that does not cover its parent.
        arcSpan     = 360,           -- degrees, 30..360
        arcRotation = 0,             -- degrees, direction the arc is centred on

        -- Nesting. A slot of kind "palette" opens another palette's entries one
        -- level further out, in a region carved out of the parent entry's own --
        -- see ChildGeom for why it has to be the parent's own.
        -- A clear GAP between the parent's icon and its children, not a
        -- centre-to-centre radius: measured centre to centre it has to cover
        -- both icons' halves before it separates anything at all, and at any
        -- ordinary icon size the two rings came out touching.
        nestBand     = 40,
        nestScale    = 0.8,      -- child icon size, against the palette's own
        -- Which side of a block layout the nested entries hang off. Only
        -- consulted where the sides are equidistant -- a strip is one entry
        -- deep, so both of its long sides are -- because otherwise the side
        -- NEAREST the parent cell wins, and that is decided by the cell's
        -- position rather than by anything the user has to think about.
        nestSide         = "POSITIVE", -- POSITIVE | NEGATIVE (above/right, below/left)
        -- Where a GRID puts a nest. A strip ignores this: one entry deep, it has
        -- only ever one answer, which is to break out across itself.
        --   PERIMETER  a lane just outside the block, shared by every nest
        --   HALO       the eight positions around the parent, block faded behind
        --   POPOUT     the nested palette as a block of its own, alongside
        gridNestStyle    = "PERIMETER",
        arcChildOverflow = "NONE",   -- NONE | MIDPOINT
        arcChildMaxSpan  = 90,       -- degrees, the widest a child arc may grow

        -- Geometry
        radius      = 96,
        iconSize    = 44,
        deadZone    = 24,
        scale       = 1.0,

        -- Fan geometry. Both decays are per-step multipliers away from the
        -- centre, so one number describes the whole falloff. The floors keep
        -- distant entries legible instead of letting them vanish, and matter
        -- most on the options preview, which draws the whole palette at once.
        fanVisible    = 3,           -- entries drawn each side of the centre
        fanGap        = 10,
        fanScaleDecay = 0.72,
        fanAlphaDecay = 0.62,
        fanMinScale   = 0.30,
        fanMinAlpha   = 0.12,
        fanAnimTime   = 0.10,        -- seconds for the strip to settle
        fanInvert     = false,       -- flip which way a scroll tick travels

        -- How a fan is steered. SCROLL cycles a window of the palette past a fixed
        -- centre. CURSOR lays the WHOLE palette out at fixed positions and zooms
        -- whichever entry the pointer is nearest, so it needs no wheel at all.
        fanInput      = "SCROLL",    -- SCROLL | CURSOR

        -- Flick-ahead. The arc's entries are unbounded in depth, so a gesture
        -- can be finished before the palette has even faded in. Holding it back for
        -- a moment lets an expert flick without a menu ever appearing, while a
        -- hesitant press still gets the full display. Selection is live the
        -- whole time -- only the drawing waits.
        flickAhead    = true,
        flickDelay    = 0.12,        -- seconds held before the palette fades in
        flickFade     = 0.10,        -- seconds the fade itself takes

        -- Appearance
        -- Hub art. The default is a small additive star; hubIcon swaps it for
        -- the EllesmereUI logo. Arc only -- the fan and grid layouts put a
        -- real entry at the centre, so the hub draws no art there at all.
        hubIcon       = false,
        hubIconSize   = 46,
        hubIconAlpha  = 0.55,

        showLabels    = true,
        showHubText   = true,
        showNeedle    = true,
        showCooldowns = true,
        selectedZoom  = 1.15,
        bgAlpha       = 0.65,
        selectColor   = { 0.047, 0.824, 0.624 },  -- EllesmereUI teal (#0cd29f)
        useClassColor = false,

        paletteCount   = 1,
        -- palette.slots is a DENSE, ORDERED array: the palette auto-sizes to what the
        -- user has actually assigned, so three actions means three big entries
        -- rather than three icons and five dead gaps. Order is the entry order,
        -- clockwise from 12 o'clock, and is what the editor reorders.
        palettes = {
            [1] = { name = "Palette 1", slots = {} },
        },
    },
}
ns.DB_DEFAULTS = DB_DEFAULTS

-- Names the module has outgrown, converted in place. The defaults have already
-- been merged in by the time this runs, so each of these takes the old value
-- wholesale rather than merging it: whatever the defaults seeded under the new
-- name is a fresh empty, never something to keep. Clearing the old key is what
-- makes a second run a no-op.
local function MigrateNames(p)
    -- The horizontal and vertical strips were once two layouts. They differed
    -- only in which axis they ran along, so they are one layout with an
    -- orientation now.
    if p.layout == "FAN_H" or p.layout == "FAN_V" then
        p.fanOrientation = p.layout == "FAN_V" and "VERTICAL" or "HORIZONTAL"
        p.layout = "FAN"
    end

    -- RADIAL was what the arc was called while a full circle was the only thing
    -- it could draw. The layout is unchanged; only the word for it is.
    if p.layout == "RADIAL" then p.layout = "ARC" end

    -- A set of actions was a "ring" for the same reason, and stopped being one
    -- the moment it could be drawn as a strip or a grid.
    if p.rings then p.palettes, p.rings = p.rings, nil end
    if p.ringCount then p.paletteCount, p.ringCount = p.ringCount, nil end
    -- Auto-generated names only. A palette the user has named keeps its name.
    for i, palette in pairs(p.palettes or {}) do
        if palette.name == "Ring " .. i then palette.name = "Palette " .. i end
    end
end

local db

-- Every profile is converted on FIRST TOUCH rather than once at load. Switching
-- profile repoints db.profile at a different table without reloading the UI
-- (EllesmereUI_Profiles.lua:745), and a per-spec profile is resolved only after
-- OnInitialize has run -- so migrating "the profile that was active at load"
-- would leave both of those unconverted, reading the default-seeded empty
-- palette while the user's own sat under the old key. Worse, the next login
-- would then migrate over the top of whatever they had edited in the meantime.
--
-- Weak keys: the memo must not keep a profile table alive after the profile
-- itself is deleted.
local migrated = setmetatable({}, { __mode = "k" })
local function P()
    local p = db and db.profile
    if p and not migrated[p] then
        migrated[p] = true
        MigrateNames(p)
    end
    return p
end
-- Exported so the options page reads the profile through the same accessor
-- rather than reaching into db.profile itself, which would skip the migration
-- above on whichever side happened to touch a switched-in profile first.
ns.Profile = P

-- Palettes past the first are created on demand: the defaults table only seeds
-- palette 1, so DeepMergeDefaults never has to know how many the user wants.
local function EnsurePalette(index)
    local p = P()
    if not p or index < 1 or index > MAX_PALETTES then return nil end
    if not p.palettes then p.palettes = {} end
    local palette = p.palettes[index]
    if not palette then
        palette = { name = "Palette " .. index, slots = {} }
        p.palettes[index] = palette
    end
    if type(palette.slots) ~= "table" then palette.slots = {} end

    -- Self-healing compaction. The array must have no holes for #slots to be
    -- meaningful, and a hole is exactly what a cleared slot used to leave
    -- behind under the old fixed-slot-count model. Also enforces MAX_SLOTS.
    local dense, n = {}, 0
    for i = 1, MAX_SLOTS do
        local slot = palette.slots[i]
        if slot and slot.kind then
            n = n + 1
            dense[n] = slot
        end
    end
    palette.slots = dense
    palette.slotCount = nil   -- retired: the count is now derived from #slots
    return palette
end
ns.EnsurePalette = EnsurePalette

-- Ordered mutations. All three keep the array dense so #slots stays the
-- authoritative entry count.
function ns.AddSlot(palette, slot)
    if not palette or not slot then return nil end
    if #palette.slots >= MAX_SLOTS then return nil end
    palette.slots[#palette.slots + 1] = slot
    return #palette.slots
end

function ns.RemoveSlot(palette, index)
    if not palette or not palette.slots[index] then return false end
    tremove(palette.slots, index)
    return true
end

-- Move, not swap: dragging an icon between two others should insert it there
-- and shuffle the rest along, which is what a reorder is.
function ns.MoveSlot(palette, from, to)
    if not palette then return false end
    local n = #palette.slots
    if from == to or from < 1 or from > n or to < 1 or to > n then return false end
    tinsert(palette.slots, to, tremove(palette.slots, from))
    return true
end

-- How many palettes EXIST. Not the same as how many can be opened by a key:
-- everything past MAX_BOUND_PALETTES has no <Binding> entry and is reachable
-- only by being nested inside another palette.
local function PaletteCount()
    local p = P()
    return min(MAX_PALETTES, max(1, (p and p.paletteCount) or 1))
end
ns.PaletteCount = PaletteCount

-- How many have a keybind, and therefore a secure button of their own. Every
-- loop that pushes actions or claims a key runs over THIS, not PaletteCount.
local function BoundPaletteCount()
    return min(MAX_BOUND_PALETTES, PaletteCount())
end
ns.BoundPaletteCount = BoundPaletteCount

-------------------------------------------------------------------------------
--  Nesting
--
--  A slot of kind "palette" names another palette by index. The palette it
--  names is an ordinary one -- it may carry a keybind as well, or exist purely
--  to be nested.
--
--  ONE level. The child region is carved out of the parent entry's own region,
--  and there is no second region to carve out of that: a release is resolved
--  from the final cursor position alone, so parents and children have to
--  partition the plane between them. A palette slot INSIDE a nested palette is
--  therefore drawn but fires nothing.
-------------------------------------------------------------------------------

-- The palette a slot opens, or nil for a slot that fires an action.
local function ChildIndex(slot)
    if not slot or slot.kind ~= "palette" then return nil end
    local idx = tonumber(slot.palette)
    if not idx or idx < 1 or idx > MAX_PALETTES then return nil end
    return idx
end
ns.ChildIndex = ChildIndex

-- The reachable entries of a nested palette. Capped rather than refused, so a
-- palette that is also bound to a key keeps all twelve of its slots when it is
-- opened directly and offers its first eight when it is nested.
local function ChildSlots(paletteIndex)
    local palette = paletteIndex and EnsurePalette(paletteIndex)
    if not palette then return nil end
    local out = {}
    for i = 1, min(MAX_CHILDREN, #palette.slots) do out[i] = palette.slots[i] end
    return out, palette
end
ns.ChildSlots = ChildSlots

-- May `child` be nested inside `parent`? No for a palette inside itself, and no
-- for any chain that would close a loop -- A holding B holding A. Checked when
-- the slot is CREATED rather than when it is walked: a stored cycle would send
-- every push and every draw of that palette round until the client gave out.
function ns.CanNest(parentIndex, childIndex)
    if not parentIndex or not childIndex then return false end
    if parentIndex == childIndex then return false end

    -- Walk down from the candidate child. Reaching the parent means the parent
    -- already sits somewhere below it, so nesting it would close the loop. The
    -- seen set also bounds the walk over data that is ALREADY cyclic, which a
    -- profile edited by hand or carried over from an older build may be.
    local seen, stack = { [childIndex] = true }, { childIndex }
    while #stack > 0 do
        local idx = tremove(stack)
        if idx == parentIndex then return false end
        local palette = EnsurePalette(idx)
        for i = 1, (palette and #palette.slots or 0) do
            local c = ChildIndex(palette.slots[i])
            if c and not seen[c] then
                seen[c] = true
                stack[#stack + 1] = c
            end
        end
    end
    return true
end

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
ns.MAX_PALETTES = MAX_PALETTES
ns.MAX_BOUND_PALETTES = MAX_BOUND_PALETTES
ns.MAX_CHILDREN = MAX_CHILDREN

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

    -- A palette opens entries; it never fires one. Returning nothing is what
    -- makes a release on the parent itself a cancel, which is the only sensible
    -- reading of "you stopped on the door rather than going through it".
    if k == "palette" then return nil end

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

    elseif k == "palette" then
        local palette = EnsurePalette(ChildIndex(slot))
        -- The user's own choice first, then the palette's first entry, so a
        -- "Mounts" palette looks like a mount without anyone having to pick an
        -- icon for it. Only one level down: a first entry that is itself a
        -- palette would send this round its own loop.
        local icon = slot.icon
        local first = palette and palette.slots[1]
        if not icon and first and first.kind ~= "palette" then
            icon = SlotDisplay(first)
        end
        return icon or QUESTION_MARK,
               slot.name or (palette and palette.name) or "Palette"
    end

    return QUESTION_MARK, slot.name
end
ns.SlotDisplay = SlotDisplay

-- Cooldown source per kind. Returns start, duration, enable -- handed to
-- CooldownFrame_Set verbatim, never compared or arithmetic'd, so secret
-- cooldown values stay untouched.
-- Returns EITHER a duration object (spells, mounts) OR start, duration, enable
-- (items, toys). Two shapes because only spells have a secret-safe getter.
--
-- Spell cooldowns must not go through C_Spell.GetSpellCooldown: it is flagged
-- SecretWhenCooldownsRestricted (SpellDocumentation.lua:252), so once cooldowns
-- are restricted its startTime and duration come back as SECRET numbers. Our
-- execution is an addon's and therefore tainted, and CooldownFrame_Set opens with
-- `start > 0 and duration > 0` (Cooldown.lua:3) -- comparing a secret from
-- tainted execution throws, which is what filled the log with 17 errors on the
-- first in-combat open. C_Spell.GetSpellCooldownDuration returns an opaque
-- duration object instead: it is AllowedWhenTainted, and it goes straight into
-- the widget C-side, so nothing here ever reads a secret.
--
-- Items keep the plain numeric path -- C_Item.GetItemCooldown carries no secret
-- flag and there is no duration-object equivalent for items.
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
        if id and C_Spell.GetSpellCooldownDuration then
            return C_Spell.GetSpellCooldownDuration(id)
        end
    elseif k == "item" or k == "toy" then
        if slot.id and C_Item.GetItemCooldown then
            return nil, C_Item.GetItemCooldown(slot.id)
        end
    end
    return nil
end

-- Build a slot table from whatever is on the cursor. Returns nil when the
-- cursor holds something the palette can't fire.
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
--  Palette view  --  the renderer, instanced
--
--  Two instances exist: the live palette and the options-page preview. Sharing
--  one renderer is the whole point of the split -- the preview's entry order,
--  angles and hit test ARE the live palette's, so what the user arranges in the
--  panel is exactly what they steer at in play.
--
--  A view owns its container frame, the center hub, and a pool of MAX_SLOTS
--  slot widgets. It does NOT own interaction: the live palette drives itself from
--  ns.Open/ns.Close, and the preview installs its own scripts on the widgets it
--  gets back from GetSlotWidget.
-------------------------------------------------------------------------------
local views = {}            -- every view, live and preview
local liveView              -- the palette the keybinds open
-- Declared up here, not beside EnsureScrollCatcher: AdvanceFan reads the fan
-- index straight off it, and that is defined long before the catcher is built.
local scrollCatcher
local secureHeader
-- The button ESCAPE is bound to while a palette is open. Declared here for the
-- same reason: ns.Close drops its binding, and that is defined long before the
-- secure activation section builds it.
local cancelButton
local openedAt = 0

-- A held key whose up-event never reaches us (alt-tab, /reload prompt, a
-- taxi takeoff) would otherwise leave the palette on screen forever.
local OPEN_TIMEOUT = 30

-- Selection is drawn with two cues only: the icon border takes the selection
-- color and thickens, and the entry grows. No additive glow -- at palette scale
-- it bloomed over the neighbouring entries and made the border it was supposed
-- to emphasise harder to read.
local SEL_BORDER = 2
local IDLE_BORDER = 1

-- The magnification a selected entry is drawn at.
local function SelectedZoom()
    local p = P()
    return max(1, (p and p.selectedZoom) or 1.15)
end

-- Magnification is applied to the entry's SIZE, never its scale. SetPoint
-- offsets are read in the widget's own scaled space, so scaling an entry also
-- multiplies the offset it is anchored at -- and in the arc that offset carries
-- the radius, so selecting an entry threw it outward, out from under the very
-- cursor that had selected it, and the two states then flickered against each
-- other. Growing it in place moves nothing.
--
-- widget.baseSize is the unzoomed size the layout wants, published by whichever
-- geometry pass last placed the entry. The strip and the grid rewrite their
-- sizes every frame, so they apply the zoom themselves as they go; this is what
-- carries it across a selection CHANGE, which is all the arc ever needs.
local function ApplySlotVisual(widget, selected)
    local p = P()
    local r, g, b = SelectColor()
    local t = selected and SEL_BORDER or IDLE_BORDER
    widget.border:SetPoint("TOPLEFT", widget, "TOPLEFT", -t, t)
    widget.border:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", t, -t)
    local base = widget.baseSize
    if base then
        local z = selected and SelectedZoom() or 1
        widget:SetSize(base * z, base * z)
    end
    if selected then
        widget.border:SetVertexColor(r, g, b, 1)
        widget.bg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22, min(1, (p and p.bgAlpha or 0.65) + 0.25))
        widget.icon:SetVertexColor(1, 1, 1)
        widget.label:SetTextColor(r, g, b)
    else
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

    -- The "+" affordance for an interactive view's trailing placeholder entry.
    -- Created unconditionally; Layout is what decides whether it is ever shown.
    w.plus = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    w.plus:SetPoint("CENTER")
    w.plus:SetText("+")
    w.plus:Hide()

    w:EnableMouse(false)
    return w
end

local PaletteView = {}
local PaletteViewMeta = { __index = PaletteView }

local function DefaultGeom()
    local p = P()
    if not p then return 96, 44, 24 end
    return p.radius or 96, p.iconSize or 44, p.deadZone or 24
end

-- radius, iconSize, deadZone for this view. Called through a plain function
-- call, never `opts.geom and opts.geom()` -- an `and` expression is truncated
-- to one value and would drop iconSize and deadZone on the floor.
function PaletteView:Geom()
    return (self.opts.geom or DefaultGeom)()
end

function PaletteView:GetFrame()     return self.frame end
function PaletteView:GetPaletteIndex() return self.paletteIndex end
function PaletteView:GetSelection() return self.selection end
function PaletteView:SlotCount()    return self.slotCount end
function PaletteView:ShownCount()   return self.shownCount end
function PaletteView:GetSlotWidget(index) return self.widgets[index] end

-- ARC | FAN | GRID. A view may pin its own mode (the options preview
-- pins one so the page can show either without changing what the user plays
-- with); everything else follows the profile.
function PaletteView:LayoutMode()
    local p = P()
    return self.opts.layout or (p and p.layout) or "ARC"
end

-- Which way a fan runs. Every axis-dependent decision in the file reads this
-- one predicate, so a strip is one layout with an orientation rather than two
-- layouts that happen to share every setting. Meaningless outside a fan, where
-- callers do not ask.
function PaletteView:FanHoriz()
    local p = P()
    return not p or p.fanOrientation ~= "VERTICAL"
end

function PaletteView:IsFan()
    return self:LayoutMode() ~= "ARC"
end

function PaletteView:IsGrid()
    return self:LayoutMode() == "GRID"
end

-- The lattice spacing entries are placed on: one icon plus the gap between two
-- of them. The grid, both strips and a nested arc all measure from this.
function PaletteView:Pitch()
    local p = P()
    local _, iconSize = self:Geom()
    return iconSize + ((p and p.fanGap) or 10)
end

-- Nested geometry for one palette. Returns an array of CLAIMS -- one per slot
-- that opens a palette -- or nil when nothing in it nests:
--
--   parent   the slot index the children hang off
--   palette  the palette index they come from
--   slots    the child slots themselves, already capped at MAX_CHILDREN
--   n        how many
--   angle    the parent entry's own angle          } arc only
--   start    the angle of child 1 (the CENTRE of its sector)
--   step     one child sector, radians
--   radius   where the children are drawn
--   band     the distance at which the children take over from the parent
--   cells    one box per child, { x, y, hw, hh }   } block layouts only
--   axis     the axis its run travels on, X or Y
--   sign     which side of the block it came out on, +1 up/right
--   dim      whether the block behind it is pushed back while it is open
--
-- ONE allocator, read by the drawing, by the hit test and by the push onto the
-- secure button. A second copy of any of this inside the snippet would drift
-- from what the palette draws the first time an option moved -- the same reason
-- the grid's cell centres are pushed rather than re-derived.
--
-- Why the children subdivide their PARENT'S sector rather than taking a fixed
-- span of their own: nothing runs between the press and the release, so the
-- release has only the final cursor position to go on. Parent regions and child
-- regions must therefore partition the plane. Two neighbouring parents each
-- claiming a quarter turn would overlap, and the overlap would be unresolvable.
--
-- A sector too narrow for its children is answered by pushing them further OUT,
-- where the same angle buys more room, rather than by widening into a
-- neighbour's sector. arcChildOverflow = MIDPOINT trades that away: the arc
-- grows to the midpoint between this claim and the next one either side, which
-- borrows depth from the plain entries in between -- a long flick through the
-- borrowed angles then fires a child instead of the entry it points at.
function PaletteView:ChildGeom(shown, palette)
    local p = P()
    if not p or not palette or shown < 1 then return nil end
    -- An editor draws no nests. What a nested entry holds is that palette's own
    -- business -- switch to it and it is the whole preview -- and drawing every
    -- nest at once buries the palette actually being arranged. It would also
    -- make the preview budget space for a reach it is not showing, shrinking the
    -- palette under the cursor to leave room for entries that are not there.
    if self.opts.interactive then return nil end

    -- Claimants in entry order first: how much room each one may take depends
    -- on where the next one sits, so none of them can be sized on its own.
    local claims
    for i = 1, shown do
        local kids = ChildSlots(ChildIndex(palette.slots[i]))
        if kids and #kids > 0 then
            claims = claims or {}
            claims[#claims + 1] = { parent = i, n = #kids, slots = kids,
                                    palette = ChildIndex(palette.slots[i]) }
        end
    end
    if not claims then return nil end

    -- Placement is per layout; the claims themselves are not. An arc carves
    -- sectors out of its parent's own, so its children are found by angle; a
    -- block layout gives every child a box and finds them by containment. The
    -- two answer the same question -- which region of the plane is this? -- in
    -- the terms their own layout is already steered in.
    if self:IsPointerLayout() then return self:CellChildGeom(claims, shown) end
    if self:IsFan() then return self:StripNest(claims, shown) end
    if self:LayoutMode() ~= "ARC" then return nil end

    local step, arcStart, full = self:ArcGeom(shown)
    local radius, iconSize = self:Geom()
    local pitch  = self:Pitch()
    -- Scaled by whatever this view scaled its geometry by, recovered from the
    -- icon size Geom handed back -- the same recovery the hub logo makes. The
    -- radius and the pitch already carry that factor; a band read at its literal
    -- profile size would not, and the options preview would then draw its nests
    -- at full distance around a palette fitted to two-thirds.
    local base = p.iconSize or 44
    local k = (base > 0) and (iconSize / base) or 1
    local band = max(0, p.nestBand or 40) * k
    local gap  = ((p and p.fanGap) or 10) * k
    -- Nested entries are drawn smaller than the palette's own, so a nest reads
    -- as subordinate to the entry it hangs off rather than as a second ring of
    -- equals. It costs nothing in the hit test: the sectors are angular, and an
    -- icon's size has no part in deciding which one the cursor is in.
    local childIcon = iconSize * min(1, max(0.4, p.nestScale or 0.8))
    local childPitch = childIcon + gap
    local capHalf = min(180, max(10, p.arcChildMaxSpan or 90)) * pi / 180 * 0.5
    local overflow = p.arcChildOverflow == "MIDPOINT"
    local count = #claims

    -- Angles for all of them before any of them is sized: an overflowing claim
    -- measures against the claim either side of it, and half of those sit later
    -- in the array.
    for k = 1, count do
        claims[k].angle = arcStart + (claims[k].parent - 1) * step
    end

    for k = 1, count do
        local c = claims[k]
        local half = step * 0.5
        if overflow then
            -- Out to the midpoint with the nearest claimant either side. A lone
            -- claimant on a full circle has no neighbour to meet, so only the
            -- cap stops it; on an open arc the ends are free space.
            half = capHalf
            if count > 1 then
                local nxt  = claims[k + 1] and claims[k + 1].angle
                    or (full and (claims[1].angle + TWO_PI))
                local prev = claims[k - 1] and claims[k - 1].angle
                    or (full and (claims[count].angle - TWO_PI))
                if nxt  then half = min(half, (nxt - c.angle) * 0.5) end
                if prev then half = min(half, (c.angle - prev) * 0.5) end
            end
            -- Never NARROWER than its own sector: overflow may only add room.
            half = max(half, step * 0.5)
        end

        c.step  = (half * 2) / c.n
        c.start = c.angle - half + c.step * 0.5
        c.icon  = childIcon
        -- Both icons' halves plus the gap, so the band the user sets is the
        -- space they actually see between the two rings.
        local inner = radius + iconSize * 0.5 + childIcon * 0.5 + band
        -- Far enough out that neighbouring children are a full pitch apart at
        -- this angular step. Clamped, because a narrow sector divided by eight
        -- is unbounded arithmetic and would put the children off the screen;
        -- past the clamp they overlap, and the answer is MIDPOINT or fewer
        -- entries rather than a palette drawn a thousand units wide.
        local want = (c.step > 0) and (childPitch / c.step) or inner
        c.radius = min(max(inner, want), inner * CHILD_RADIUS_MAX_K)
        -- Halfway across the gap: clear of the parent's own icon, short of its
        -- children. The parent entry keeps everything inside this.
        c.band = radius + iconSize * 0.5 + band * 0.5
    end

    return claims
end

-- Angular step and starting angle for the arc layout, both clockwise from
-- straight up. Returns the step, the angle of slot 1, and whether this is a
-- full circle.
--
-- A full circle divides by the entry count and wraps: the last entry's far side
-- is the first entry's near side, so there is no seam. An arc divides by count
-- MINUS ONE instead, which puts the first and last entries ON its ends rather
-- than leaving a step-wide gap at the seam that belongs to no entry at all.
function PaletteView:ArcGeom(shown)
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
function PaletteView:IsHoverFan()
    if self:IsGrid() or not self:IsFan() then return false end
    local p = P()
    return (p and p.fanInput or "SCROLL") == "CURSOR"
end

-- Everything steered by pointing at a fixed arrangement, as opposed to the
-- scroll fan's moving one. These all share the grid's geometry and its update.
function PaletteView:IsPointerLayout()
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

-- Editor floors. The options preview draws the whole palette at once and every
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
    return FanOffset(count, iconSize, gap, decay, FAN_EDIT_MIN_SCALE)
           + iconSize + iconSize * (SelectedZoom() - 1) * 0.5
end

-- The same measurement for a hover fan, which is evenly spaced at full pitch
-- because its zoomed entry is drawn at 1.0 and must not overlap its neighbours.
function ns.FanHoverReach(count, iconSize, gap)
    return count * 0.5 * (iconSize + gap) + iconSize * 0.5 * SelectedZoom()
end

-- Position every widget from self.fanVisual, the CONTINUOUS centre. Called
-- from Layout and from every animation step; it never repaints icons, so it is
-- cheap enough to run each frame while the strip settles.
function PaletteView:ApplyFanGeometry()
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
    local horiz  = self:FanHoriz()
    -- An interactive view draws the whole palette: the editor cannot let a slot
    -- be unreachable, so nothing is culled there and the floors carry it.
    local window = self.opts.interactive and shown or (p.fanVisible or 3)

    local frame  = self.frame
    local center = self.fanVisual or 1
    local half   = shown / 2

    -- Half the width the selected entry gains, added to every offset past the
    -- centre so magnifying it cannot close the gaps under its neighbours. A
    -- CONSTANT, applied whichever entry is selected: making it follow the
    -- selection would reflow the whole strip on every step.
    local zoom  = SelectedZoom()
    local extra = iconSize * (zoom - 1) * 0.5
    local sel   = self.selection

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
            if k > 0 then off = off + extra end
            if d < 0 then off = -off end

            w:SetAlpha(max(minA, aDecay ^ k))
            -- Depth is size, not scale: SetPoint offsets are read in the
            -- widget's own scaled space, so scaling here would silently
            -- multiply the spacing computed above. The selected entry is
            -- magnified in the same breath, because these sizes are rewritten
            -- on every animation step and would erase a zoom applied elsewhere.
            local z = (i == sel) and zoom or 1
            w.baseSize = iconSize * s
            w:SetSize(iconSize * s * z, iconSize * s * z)
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
--  entry deep -- a single row when it runs horizontally, a single column when
--  it runs vertically -- so it routes here rather than into a parallel 1D
--  implementation. This is the mode that scales -- pointer travel to the worst
--  entry grows with the SQUARE ROOT of the count rather than linearly, and a
--  fixed 2D arrangement is far easier to build muscle memory against than a
--  position along a line.
--
--  Rows are centred individually, so a short final row sits under the middle of
--  the one above it instead of hanging off the left edge.
-------------------------------------------------------------------------------

-- How far from EVERY entry, in cells, the pointer may stray before the grid
-- deselects. This is the grid's cancel: it has no dead zone to release inside.
local GRID_REACH = 1.0

-- What the block behind an open nest is pushed back to, for the styles that put
-- their children over it. Enough to read as "that layer is not the one you are
-- on" while still showing the shape of what you came from.
local NEST_DIM_ALPHA = 0.25
local NEST_DIM_SCALE = 0.8

-- The margin, in pitches, around a scroll-steered strip that the pointer may
-- travel inside before it deselects. This is that layout's cancel, and it is
-- the same gesture the grid cancels with -- throw the pointer clear of the
-- icons -- rather than a rule of its own to learn.
--
-- Clear in ANY direction, but not the same distance in each: the box is this
-- margin across the strip and the strip's own drawn length plus the margin
-- along it. A strip is long one way and thin the other, and leaving it means
-- passing its edge, wherever that edge happens to be.
--
-- Measured from where the pointer was when the palette opened, not from the
-- strip, so it means the same thing in Fixed Position mode, where the strip is
-- somewhere else on the screen entirely.
--
-- Note what this does NOT cover: while the right button holds the camera the
-- cursor is frozen, so it cannot travel and the strip cannot be cancelled --
-- and camera steering is the case this layout exists for. A player who wants
-- out of a strip opened mid-turn has to let the camera go first.
local FAN_CANCEL_REACH = 2.25

-- The strip dims as the pointer travels toward the edge of that box, so leaving
-- is something the player watches happen rather than a boundary they cross
-- blind. The fade starts part of the way out -- steering a strip means moving,
-- and a palette that dimmed on the first pixel would flicker on every gesture.
--
-- Eased rather than linear, and by a fair margin: the strip holds near full
-- brightness through most of the travel and then drops away over the last of
-- it. A linear ramp read as the palette dimming the moment the pointer moved,
-- when what it has to say is "still here" until leaving is actually imminent.
local FAN_FADE_START = 0.35
local FAN_FADE_MIN   = 0.25
local FAN_FADE_POWER = 3

-- Columns for a grid the user has not pinned. Near-square, because the whole
-- point of a grid is to shorten the WORST pointer travel, and that is minimised
-- when the two axes are balanced: nine entries want 3x3, not 4 + 4 + 1.
--
-- The remainder check is the one refinement on ceil(sqrt). A final row holding a
-- single entry reads as a mistake rather than a layout, and widening by one
-- column always absorbs it -- 3 becomes one row of three, 7 becomes 4 + 3.
local function AutoGridColumns(shown)
    local cols = ceil(sqrt(shown))
    if cols < shown and shown % cols == 1 then cols = cols + 1 end
    return min(MAX_SLOTS, max(1, cols))
end

-- A pointer-steered fan IS a grid one entry deep, so it resolves here rather
-- than in a parallel 1D implementation: a horizontal strip is a single row, a
-- vertical one a single column. Only the scroll-steered fan needs geometry of
-- its own, because it cycles a compressed window rather than showing fixed
-- positions.
-- shownOverride lets a caller ask what the grid WOULD be for some other entry
-- count. PushPalette needs exactly that: it runs while the palette is closed,
-- when shownCount still describes whatever was drawn last.
function PaletteView:GridDims(shownOverride)
    local p = P()
    local shown = max(1, shownOverride or self.shownCount)

    local mode = self:LayoutMode()
    if mode == "FAN" then
        if self:FanHoriz() then return shown, 1 end
        return 1, shown
    end

    local cols
    if not p or p.gridAutoColumns ~= false then
        -- Counted from the REAL entries, not from `shown`. An interactive view
        -- draws one extra entry for the trailing "+", and letting that tip the
        -- column count would make the editor lay a palette out differently from
        -- the way it is played -- six actions previewing as 4 + 3 while the
        -- live palette drew 3 + 3.
        cols = AutoGridColumns(max(1, shownOverride or self.slotCount or shown))
    else
        cols = min(MAX_SLOTS, max(1, floor(p.gridColumns or 4)))
    end
    if cols > shown then cols = shown end
    return cols, ceil(shown / cols)
end

-- Centre-relative position of slot i, in the frame's own units.
function PaletteView:GridBase(i, cols, rows, pitch, shownOverride)
    local r = floor((i - 1) / cols)
    local c = (i - 1) % cols
    local inRow = min(cols, (shownOverride or self.shownCount) - r * cols)
    return (c - (inRow - 1) * 0.5) * pitch, -(r - (rows - 1) * 0.5) * pitch
end

-------------------------------------------------------------------------------
--  Nested cells for a block layout
--
--  Every nested cell owns a BOX. Inside it, that child; outside every box, the
--  palette's own nearest-cell search, exactly as if the nest were not there.
--  That one rule is what makes a nest behave like a thing you are IN: leave the
--  run in ANY direction -- along it, across it, back over the parent -- and you
--  are out of it, because you are outside its boxes. Boxes are also what let a
--  nest sit over ground the block is using, which the styles below need and a
--  nearest-centre rule could never allow.
--
--  Boxes are tested in cell order and the FIRST hit wins, so two that overlap
--  still have exactly one answer. The drawing and the snippet walk them in the
--  same order, which is the whole requirement -- they need to agree, not to be
--  disjoint.
-------------------------------------------------------------------------------

-- Clockwise from straight up: the eight positions around a cell.
local HALO_DIRS = {
    { 0, 1 }, { 1, 1 }, { 1, 0 }, { 1, -1 },
    { 0, -1 }, { -1, -1 }, { -1, 0 }, { -1, 1 },
}

-- A point on the band that hugs the block, clockwise from the left end of its
-- top edge. Returns the point, the axis the run travels along there, and which
-- side of the block it is (+1 up/right). Wrapping a run around a corner costs
-- nothing in this form: it is one coordinate, and a corner is just a place where
-- the axis changes.
--
-- The corners are ROUNDED, and not for looks. Cells are spaced evenly along the
-- path, and around a square corner the straight-line distance between two of
-- them is shorter than the path between them by up to a third -- enough that two
-- icons either side of a corner overlap. An arc of the same radius as the band
-- is deep spends the path length the turn needs.
local function PerimeterSpan(HX, HY, R)
    local sx, sy = HX * 2 - R * 2, HY * 2 - R * 2
    local arc = pi * 0.5 * R
    return sx, sy, arc, 2 * (sx + sy) + 4 * arc
end

local function PerimeterPoint(t, HX, HY, R)
    local sx, sy, arc, L = PerimeterSpan(HX, HY, R)
    t = t % L
    if t < sx then return -HX + R + t, HY, "X", 1 end
    t = t - sx
    if t < arc then
        local a = t / R
        -- Half a turn each: a cell more than halfway round a corner belongs to
        -- the side it is heading onto, so its box lies across the run it is
        -- about to join rather than across the one it has left.
        local ax, sg = "X", 1
        if a >= pi * 0.25 then ax = "Y" end
        return HX - R + R * sin(a), HY - R + R * cos(a), ax, sg
    end
    t = t - arc
    if t < sy then return HX, HY - R - t, "Y", 1 end
    t = t - sy
    if t < arc then
        local a = t / R
        local ax, sg = "Y", 1
        if a >= pi * 0.25 then ax, sg = "X", -1 end
        return HX - R + R * cos(a), -HY + R - R * sin(a), ax, sg
    end
    t = t - arc
    if t < sx then return HX - R - t, -HY, "X", -1 end
    t = t - sx
    if t < arc then
        local a = t / R
        local ax, sg = "X", -1
        if a >= pi * 0.25 then ax = "Y" end
        return -HX + R - R * sin(a), -HY + R - R * cos(a), ax, sg
    end
    t = t - arc
    if t < sy then return -HX, -HY + R + t, "Y", -1 end
    t = t - sy
    local a = t / R
    local ax, sg = "Y", -1
    if a >= pi * 0.25 then ax, sg = "X", 1 end
    return -HX + R - R * cos(a), HY - R + R * sin(a), ax, sg
end

-- Everything the three styles measure from. Sizes are scaled by whatever this
-- view scaled its geometry by, recovered from the icon size Geom handed back --
-- the options preview fits a palette to its panel, and a band read at its
-- literal profile size would draw nests at full distance around a shrunken one.
function PaletteView:NestMetrics(shown)
    local p = P()
    local _, iconSize = self:Geom()
    local pitch = self:Pitch()
    local base = p.iconSize or 44
    local k = (base > 0) and (iconSize / base) or 1
    local cols, rows = self:GridDims(shown)

    local m = {
        icon  = iconSize,
        pitch = pitch,
        cols  = cols,
        rows  = rows,
        band  = max(0, p.nestBand or 40) * k,
        gap   = (p.fanGap or 10) * k,
        positive = (p.nestSide or "POSITIVE") == "POSITIVE",
        style = p.gridNestStyle or "PERIMETER",
    }
    m.halfX = (cols - 1) * 0.5 * pitch
    m.halfY = (rows - 1) * 0.5 * pitch
    -- Nested entries are drawn smaller than the palette's own, so a nest reads
    -- as subordinate to the entry it hangs off rather than as a second block of
    -- equals.
    m.childIcon  = iconSize * min(1, max(0.4, p.nestScale or 0.8))
    m.childPitch = m.childIcon + m.gap
    -- Across the run: how thick the band of boxes is. One icon plus the gap
    -- either side of it, so the box reaches back to the block's own edge and a
    -- pointer leaving the parent enters the nest without crossing dead ground.
    m.depth = m.childIcon + m.band
    -- A strip has no interior to displace and no corner to wrap, so the styles
    -- that rearrange a block have nothing to rearrange: it always breaks out
    -- perpendicular, which is the whole of what a strip's nest can be.
    if cols <= 1 or rows <= 1 then m.style = "PERIMETER" end
    return m
end

-- Box for one cell of a run travelling on `axis`.
local function RunBox(x, y, axis, along, across)
    if axis == "X" then
        return { x = x, y = y, hw = along * 0.5, hh = across * 0.5 }
    end
    return { x = x, y = y, hw = across * 0.5, hh = along * 0.5 }
end

-- (A) A single row or column just outside the block, shared by every nest on
-- that side. The band is ONE lane: two nests on the same edge sit side by side
-- along it rather than stacking outward, which is what the eye expects when only
-- one of them is ever drawn. Runs are packed along the perimeter as a single
-- circular coordinate, so a run longer than the edge it started on wraps around
-- the corner instead of shooting off into space.
function PaletteView:PerimeterNest(claims, shown, m)
    local HX = m.halfX + m.icon * 0.5 + m.band + m.childIcon * 0.5
    local HY = m.halfY + m.icon * 0.5 + m.band + m.childIcon * 0.5
    -- The turn is as wide as the band is deep, which is the largest radius that
    -- keeps the path clear of the block's own corner.
    local R = min(m.depth * 0.5, min(HX, HY) * 0.5)
    local sx, sy, arc, L = PerimeterSpan(HX, HY, R)

    -- Shrunk to fit rather than truncated if the nests together want more than
    -- the whole perimeter. Rare -- it takes several full nests on a small block
    -- -- and a crowded band still reaches everything, where a dropped run would
    -- leave entries with no way to be selected at all.
    local want = 0
    for i = 1, #claims do want = want + claims[i].n * m.childPitch end
    local childPitch, childIcon = m.childPitch, m.childIcon
    if want > L then
        local squeeze = L / want
        childPitch = childPitch * squeeze
        childIcon  = min(childIcon, childPitch - m.gap * squeeze)
    end

    local order = {}
    for i = 1, #claims do
        local c = claims[i]
        local r   = floor((c.parent - 1) / m.cols)
        local col = (c.parent - 1) % m.cols
        local bx, by = self:GridBase(c.parent, m.cols, m.rows, m.pitch, shown)

        -- The nearest edge, in CELLS, so nothing about the side depends on where
        -- the palette happens to sit on the screen -- which matters because the
        -- push runs long before the open that will use it, and the two have to
        -- agree. nestSide breaks the tie. A parent in the middle of a grid is
        -- served by the edge nearest it, which is the honest answer: there is no
        -- free ground inside a block for this style to use.
        local sides = {
            { d = r,                axis = "X", sign =  1,
              t = bx + HX - R },
            { d = m.cols - 1 - col, axis = "Y", sign =  1,
              t = sx + arc + (HY - R - by) },
            { d = m.rows - 1 - r,   axis = "X", sign = -1,
              t = sx + sy + 2 * arc + (HX - R - bx) },
            { d = col,              axis = "Y", sign = -1,
              t = 2 * sx + sy + 3 * arc + (by + HY - R) },
        }
        local pick
        for si = 1, 4 do
            local sd = sides[si]
            -- A strip breaks out ACROSS itself and only across itself: a row of
            -- entries has an edge at both ends, and a nest hung off one of those
            -- would run in line with the palette rather than out of it.
            local allowed = (m.rows <= 1 and sd.axis == "X")
                         or (m.cols <= 1 and sd.axis == "Y")
                         or (m.rows > 1 and m.cols > 1)
            if allowed then
                -- The tie-break folded into the key: the chosen side loses a
                -- hair of distance so it wins whenever the two are level.
                sd.order = sd.d * 4 + (((sd.sign > 0) == m.positive) and 0 or 1)
                         + ((sd.axis == "X") and 0 or 2)
                if not pick or sd.order < pick.order then pick = sd end
            end
        end

        c.icon = childIcon
        c.axis, c.sign = pick.axis, pick.sign
        c.w  = c.n * childPitch
        c.t0 = pick.t
        order[#order + 1] = c
    end

    -- Packed along the perimeter in the order they meet it, each preferring to
    -- sit centred on its own parent. Forward pass opens the overlaps, backward
    -- pass closes the wrap the forward pass may have pushed past the seam; with
    -- the total known to fit, one of each settles it.
    table.sort(order, function(a, b) return a.t0 < b.t0 end)
    local cur
    for i = 1, #order do
        local c = order[i]
        c.s = c.t0 - c.w * 0.5
        if cur and c.s < cur then c.s = cur end
        cur = c.s + c.w
    end
    if #order > 0 then
        local limit = order[1].s + L
        for i = #order, 1, -1 do
            local c = order[i]
            if c.s + c.w > limit then c.s = limit - c.w end
            limit = c.s
        end
    end

    for i = 1, #order do
        local c = order[i]
        c.cells = {}
        for j = 1, c.n do
            local x, y, axis = PerimeterPoint(c.s + (j - 0.5) * childPitch,
                                              HX, HY, R)
            c.cells[j] = RunBox(x, y, axis, childPitch, m.depth)
        end
    end
    return claims
end

-- (B) The eight positions around the parent's own cell, the block behind them
-- faded and shrunk. The neighbours keep their centres -- the halo is drawn tight
-- enough that they stay outside it -- so what they lose is the ground a pointer
-- could have approached them across, not the entries themselves.
function PaletteView:HaloNest(claims, shown, m)
    -- Three boxes across must stay inside one pitch either side, or a
    -- neighbouring entry's own centre would fall inside the halo and become
    -- unselectable while the halo is up.
    local hp = m.pitch * 0.5
    local icon = min(m.childIcon, hp - m.gap * 0.5)
    for i = 1, #claims do
        local c = claims[i]
        local bx, by = self:GridBase(c.parent, m.cols, m.rows, m.pitch, shown)
        -- No axis and no side: a halo surrounds its parent rather than coming
        -- out of one edge of the block, so there is no "other side" for the hub
        -- caption to move to and it keeps the placement it would have had.
        c.icon, c.dim = icon, true
        c.cells = {}
        for j = 1, min(c.n, #HALO_DIRS) do
            local d = HALO_DIRS[j]
            c.cells[j] = { x = bx + d[1] * hp, y = by + d[2] * hp,
                           hw = hp * 0.5, hh = hp * 0.5 }
        end
        -- The centre is left to the parent, which fires nothing: a pointer that
        -- comes to rest back on the entry it opened does nothing, rather than
        -- picking whichever child happened to be nearest.
        c.n = #c.cells
    end
    return claims
end

-- (C) The nested palette as a block of its own, set down just outside the parent
-- block on the side its parent entry leans toward, with the parent block faded
-- behind it. Closest of the three to "the sub-palette replaces this one", short
-- of actually replacing it -- which would need the release to know how the
-- pointer got where it is, and it never does.
function PaletteView:PopoutNest(claims, shown, m)
    for i = 1, #claims do
        local c = claims[i]
        local bx, by = self:GridBase(c.parent, m.cols, m.rows, m.pitch, shown)
        local ccols = min(MAX_SLOTS, max(1, ceil(sqrt(c.n))))
        local crows = ceil(c.n / ccols)

        -- Which way the parent entry leans, from its own cell rather than from
        -- the screen: the push has to agree with an open that has not happened
        -- yet. Dead centre has no lean, and nestSide answers for it.
        local axis, sign
        if abs(bx) > abs(by) then
            axis, sign = "Y", (bx > 0) and 1 or -1
        elseif abs(by) > 0 then
            axis, sign = "X", (by > 0) and 1 or -1
        else
            axis, sign = "X", m.positive and 1 or -1
        end

        local out = ((axis == "X") and m.halfY or m.halfX)
                    + m.icon * 0.5 + m.band + m.childIcon * 0.5
        c.icon, c.dim = m.childIcon, true
        c.axis, c.sign = axis, sign
        c.cells = {}
        for j = 1, c.n do
            local cr  = floor((j - 1) / ccols)
            local cc  = (j - 1) % ccols
            local row = min(ccols, c.n - cr * ccols)
            local a = (cc - (row - 1) * 0.5) * m.childPitch
            local d = out + cr * m.childPitch
            local x, y
            if axis == "X" then x, y = a, sign * d else x, y = sign * d, a end
            c.cells[j] = { x = x, y = y,
                           hw = m.childPitch * 0.5, hh = m.childPitch * 0.5 }
        end
    end
    return claims
end

-- A scroll-steered strip's nest. The wheel decides which entry is selected and
-- that entry is always the one drawn at the CENTRE, so its children break out
-- across the strip from there -- the same perpendicular row a pointer-steered
-- strip gets, at the one place this layout can put it.
--
-- Every nest is built at that same centre. Nothing is lost by it: only the entry
-- the wheel has landed on is ever live, so two nests can no more be reached at
-- once than two entries can.
--
-- Measured from where the palette was OPENED rather than from where the strip is
-- drawn, because that is what this layout's cancel is measured from and the two
-- have to be one geometry. The drawing takes the difference out again.
function PaletteView:StripNest(claims, shown)
    local m = self:NestMetrics(shown)
    local horiz = self:FanHoriz()
    local axis = horiz and "X" or "Y"
    local sign = m.positive and 1 or -1
    local out = m.icon * 0.5 + m.band + m.childIcon * 0.5

    for i = 1, #claims do
        local c = claims[i]
        c.icon = m.childIcon
        c.axis, c.sign = axis, sign
        c.cells = {}
        for j = 1, c.n do
            local a = (j - (c.n + 1) * 0.5) * m.childPitch
            local x, y
            if horiz then x, y = a, sign * out else x, y = sign * out, a end
            c.cells[j] = RunBox(x, y, axis, m.childPitch, m.depth)
        end
        -- How far across the strip the pointer may travel toward this nest
        -- before it counts as thrown clear. Without it the strip's own cancel
        -- sits in the gap between an entry and its children, and reaching for
        -- one of them closes the palette instead.
        c.across = out + m.depth * 0.5
    end
    return claims
end

-- Nested cells for a block layout: the grid, and a pointer-steered strip, which
-- is a grid one entry deep.
function PaletteView:CellChildGeom(claims, shown)
    local m = self:NestMetrics(shown)
    if m.style == "HALO"   then return self:HaloNest(claims, shown, m) end
    if m.style == "POPOUT" then return self:PopoutNest(claims, shown, m) end
    return self:PerimeterNest(claims, shown, m)
end

-- The nested cell whose box holds this offset, in cell order so that boxes which
-- overlap still answer once. Read by the drawing; the snippet carries the same
-- walk over the same numbers.
function PaletteView:NestHit(dx, dy)
    local claims = self.claims
    for k = 1, (claims and #claims or 0) do
        local c = claims[k]
        for j = 1, (c.cells and c.n or 0) do
            local b = c.cells[j]
            if abs(dx - b.x) <= b.hw and abs(dy - b.y) <= b.hh then
                return c.base + j, c
            end
        end
    end
end

-- Lay the grid out and select the entry nearest the pointer. noPointer draws it
-- evenly with nothing selected, which is what Layout and the editor want.
function PaletteView:AdvanceGrid(noPointer)
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

    -- Nested cells first, and by CONTAINMENT rather than by nearness: a nest is
    -- somewhere you are in or out of. Inside a box, that child regardless of
    -- what the block holds underneath -- which is what lets a halo sit over the
    -- entries around its parent. Outside every box, the block answers as though
    -- the nest were not there, so leaving a run in any direction leaves the nest.
    local best, bestK
    if dx then best = self:NestHit(dx, dy) end

    -- Nearest of the palette's own, once the nests have declined. Past
    -- GRID_REACH cells from every one of them nothing is selected -- this
    -- layout's cancel, and it has no dead zone, a grid's centre being an
    -- ordinary cell.
    if dx and not best then
        for i = 1, shown do
            local bx, by = self:GridBase(i, cols, rows, pitch)
            local ox, oy = (dx - bx) / pitch, (dy - by) / pitch
            -- ^0.5, not sqrt: the snippet has no sqrt and must use the power
            -- form, and the two are not bit-identical in Lua 5.1. Matching them
            -- keeps a cursor exactly on the reach boundary from selecting one
            -- entry on screen and firing another.
            local k = (ox * ox + oy * oy) ^ 0.5
            if not bestK or k < bestK then best, bestK = i, k end
        end
        if bestK and bestK > GRID_REACH then best = nil end
    end

    -- Which nest is open, settled before anything is drawn: a style that fades
    -- the block behind it has to know while the block is being painted, not a
    -- frame later. SetSelection's own call then finds nothing left to do.
    self:UpdateNestShown(best)
    local open = self._openClaim
    local dim = (open and open.dim) and NEST_DIM_ALPHA or 1
    local shrink = (open and open.dim) and NEST_DIM_SCALE or 1

    for i = 1, shown do
        local w = self.widgets[i]
        local bx, by = self:GridBase(i, cols, rows, pitch)

        -- Falloff is the true 2D distance, in cells. A grid has no privileged
        -- axis, so projecting onto one -- as the strip does -- would make the
        -- zoom respond to sideways movement it should ignore.
        local s, a = max(minS, decay), 1
        if dx then
            local ox, oy = (dx - bx) / pitch, (dy - by) / pitch
            local k = (ox * ox + oy * oy) ^ 0.5
            s = max(minS, decay ^ k)
            a = max(minA, aDecay ^ k)
        end
        -- The entry a nest hangs off keeps its own size and colour: it is what
        -- the nest is about, and dimming it would leave nothing on screen saying
        -- which entry was opened.
        if open and i ~= open.parent then s, a = s * shrink, a * dim end

        w:SetAlpha(a)
        w.baseSize = iconSize * s
        w:SetSize(iconSize * s, iconSize * s)
        w:ClearAllPoints()
        w:SetPoint("CENTER", frame, "CENTER", bx, by)
        w:Show()
    end

    -- Nested cells are drawn at a flat size. They live inside boxes rather than
    -- on a falloff, and a child shrinking as the pointer crossed its own box
    -- would suggest a nearness that decides nothing here.
    local claims = self.claims
    for ck = 1, (claims and #claims or 0) do
        local c = claims[ck]
        for j = 1, c.n do
            local cell = c.cells and c.cells[j]
            local w = c.base and self.widgets[c.base + j]
            if cell and w then
                w:SetAlpha(1)
                w.baseSize = c.icon
                w:SetSize(c.icon, c.icon)
                w:ClearAllPoints()
                w:SetPoint("CENTER", frame, "CENTER", cell.x, cell.y)
            end
        end
    end

    -- Magnify the chosen cell where it stands. Applied here rather than left to
    -- the selection paint because the sizes above are rewritten every frame,
    -- which would erase a zoom applied only when the selection changed.
    if best then
        local w = self.widgets[best]
        local z = SelectedZoom()
        w:SetSize(w.baseSize * z, w.baseSize * z)
    end
    self:SetSelection(best)
end

-- Centre the strip on a slot with no animation. The options preview uses this
-- to follow the entry the user has clicked.
function PaletteView:SetFanCenter(index)
    if not index or self.shownCount < 1 then return end
    self.fanTarget = index
    self.fanVisual = index
    self:ApplyFanGeometry()
    self:SetSelection(index)
end

-- Half the drawn strip, along its own axis, out to the far edge of the last
-- visible entry. Sizes the frame and bounds the cancel, from one number: a
-- second copy of this would drift the moment either falloff setting moved.
function PaletteView:FanHalfLength()
    local p = P()
    local _, iconSize = self:Geom()
    local shown = self.shownCount
    -- The editor culls nothing, so its strip is as long as the palette is.
    local window = self.opts.interactive and shown or ((p and p.fanVisible) or 3)
    local minS = self.opts.interactive and FAN_EDIT_MIN_SCALE
                                        or ((p and p.fanMinScale) or 0.30)
    -- Plus the room ApplyFanGeometry leaves for the selected entry to grow into,
    -- which every offset past the centre carries. Left out, the frame would be
    -- narrower than the strip drawn in it and the cancel box would sit inside
    -- the last entry rather than beyond it.
    return FanOffset(window, iconSize, (p and p.fanGap) or 10,
                     (p and p.fanScaleDecay) or 0.72, minS)
           + iconSize + iconSize * (SelectedZoom() - 1) * 0.5
end

-- How far the pointer has been carried toward leaving the strip: 0 while it is
-- still on it, 1 at the edge of the cancel box and beyond. Answers 0 for any
-- view with no gate origin -- the options preview, which has no pointer gesture
-- at all -- so only the live palette can be cancelled this way.
--
-- The cancel and the fade read this one number, so the strip is at its dimmest
-- exactly where a release stops firing anything.
-- Pointer offset from the point the palette was opened at, which is what the
-- strip's cancel and its nests are both measured from.
function PaletteView:StripOffset()
    if not self._gateX then return nil end
    local es = self.frame:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    return mx / es - self._gateX, my / es - self._gateY
end

-- The nest the entry at `index` opens, if it opens one.
function PaletteView:ClaimFor(index)
    local claims = self.claims
    for k = 1, (index and claims and #claims or 0) do
        if claims[k].parent == index then return claims[k] end
    end
end

-- Which entry the wheel has landed on, folded into range.
function PaletteView:StripTarget()
    local shown = self.shownCount
    if not self.fanTarget or shown < 1 then return nil end
    return ((self.fanTarget - 1) % shown) + 1
end

function PaletteView:FanCancelProgress()
    if not self._gateX then return 0 end
    local p = P()
    local _, iconSize = self:Geom()
    local along, across = self:StripOffset()
    if not self:FanHoriz() then along, across = across, along end

    local margin = FAN_CANCEL_REACH * (iconSize + ((p and p.fanGap) or 10))
    -- Travel toward the nest the selected entry opens does not count as leaving:
    -- its children sit past the ordinary margin, so measuring them by it would
    -- cancel the palette on the way to reaching them. Only on the side the nest
    -- is on, and only while that entry is the one the wheel is on.
    local acrossMargin = margin
    local claim = self:ClaimFor(self:StripTarget())
    if claim and claim.across and (across > 0) == (claim.sign > 0) then
        acrossMargin = max(margin, claim.across)
    end

    return max(abs(across) / acrossMargin,
               abs(along) / (self:FanHalfLength() + margin))
end

-- Has the pointer been thrown clear of the strip?
function PaletteView:FanCancelled()
    return self:FanCancelProgress() > 1
end

-- The strip's own alpha, fading toward FAN_FADE_MIN as the pointer approaches
-- the cancel box. It never reaches zero: a strip the player has left still has
-- to be findable, because bringing the pointer back re-selects the entry it is
-- centred on.
function PaletteView:FanCancelAlpha()
    local k = self:FanCancelProgress()
    if k <= FAN_FADE_START then return 1 end
    if k >= 1 then return FAN_FADE_MIN end
    local t = (k - FAN_FADE_START) / (1 - FAN_FADE_START)
    return 1 - (1 - FAN_FADE_MIN) * t ^ FAN_FADE_POWER
end

-- Advance the settle animation and publish the centred entry as the selection.
-- The LOGICAL index moves the instant the tick arrives; only the geometry is
-- interpolated. A release mid-animation therefore always fires what the user
-- last scrolled to, never whatever the strip happens to be sliding past.
function PaletteView:AdvanceFan(elapsed)
    local shown = self.shownCount
    if shown < 1 then
        self:SetSelection(nil)
        return
    end

    -- The live strip's index is owned by the secure snippet: an addon may not
    -- write a secure button's attributes in combat, so the mouse wheel is
    -- handled in the sandbox and left here to be read. Reading an attribute
    -- from Lua is unrestricted, so this works in combat and out. Other views
    -- (the options preview) keep driving fanTarget themselves.
    if self.opts.live and scrollCatcher then
        self.fanTarget = tonumber(scrollCatcher:GetAttribute("eapFanTarget"))
    end

    -- Published BEFORE the geometry below, which magnifies whichever entry is
    -- selected as it places it. The strip keeps sliding to wherever the wheel
    -- has left it while the pointer is clear of it, so bringing the pointer back
    -- shows the entry that would fire, already settled.
    local target = self:StripTarget()
    local claim  = self:ClaimFor(target)
    local sel
    -- Into the nest the wheel's entry opens, if the pointer has gone there. The
    -- wheel says WHICH nest; the pointer only says which of its children, and
    -- says nothing at all when the entry the wheel is on does not nest.
    local dx, dy = self:StripOffset()
    if claim and dx and claim.base then
        for j = 1, claim.n do
            local b = claim.cells[j]
            if abs(dx - b.x) <= b.hw and abs(dy - b.y) <= b.hh then
                sel = claim.base + j
                break
            end
        end
    end
    if not sel and target and not self:FanCancelled() then sel = target end
    self:SetSelection(sel)

    -- Nested cells, placed against the point the palette was opened at rather
    -- than against the frame -- the difference is nothing when the palette opens
    -- under the cursor and everything when it is pinned to the screen.
    local claims = self.claims
    if claims and dx then
        local fx, fy = self.frame:GetCenter()
        local ox, oy = 0, 0
        if fx then ox, oy = self._gateX - fx, self._gateY - fy end
        for k = 1, #claims do
            local c = claims[k]
            for j = 1, c.n do
                local w = c.base and self.widgets[c.base + j]
                if w then
                    w:ClearAllPoints()
                    w:SetPoint("CENTER", self.frame, "CENTER",
                               ox + c.cells[j].x, oy + c.cells[j].y)
                end
            end
        end
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
end

-- This view's centre as a delta from UIParent's centre, in UIParent-logical
-- units. Both sides are converted through their effective scales because the
-- strip carries the user's own Scale setting while UIParent carries the game's.
function PaletteView:ScreenOffset()
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
-- once PositionPalette has run.
function PaletteView:PlaceHubText()
    local hub  = self.hub
    local mode = self:LayoutMode()
    local _, iconSize = self:Geom()

    hub.text:ClearAllPoints()
    hub.hint:ClearAllPoints()

    if mode == "ARC" then
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

    -- A nest has already claimed one side of the block, so the caption takes the
    -- other -- overriding the quadrant test below, which is about screen room
    -- rather than about what is already sitting there. Written as a nudge to
    -- dx/dy so there is still ONE placement rule underneath: the nest simply
    -- decides which way the block is "facing".
    -- Read against the tests below, which are the other way round from how they
    -- sound: dy < 0 puts the caption ABOVE, so a nest above wants dy positive.
    if self.nestAxis == "X" then
        dy = (self.nestSign > 0) and 1 or -1
    elseif self.nestAxis == "Y" then
        dx = (self.nestSign > 0) and 1 or -1
    end

    -- A grid captions like a horizontal strip: it is as wide as it is tall, so
    -- there is no side with obviously more room, and above/below keeps the text
    -- clear of every cell rather than only of the middle column.
    if mode == "GRID" or (mode == "FAN" and self:FanHoriz()) then
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

function ns.CreatePaletteView(parent, opts)
    local view = setmetatable({
        opts      = opts or {},
        widgets   = {},
        paletteIndex = 1,
        slotCount = 0,
        shownCount = 0,
        -- Only the live palette arms the movement gate (see HitTest); anything
        -- else is steered from the moment it exists.
        _steered  = true,
    }, PaletteViewMeta)

    local frame = CreateFrame("Frame", view.opts.frameName, parent)
    frame:SetSize(1, 1)
    frame:EnableMouse(false)
    view.frame = frame

    -- Hub: the center disc. Shows the selected action's name, or the palette
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

    -- The logo alternative to the star. Left on the default blend mode, unlike
    -- the star: this is real artwork with its own alpha, and ADD would wash out
    -- its dark areas into whatever is behind the palette. It stays on ARTWORK so
    -- the hub's OVERLAY text still reads on top of it.
    hub.logo = hub:CreateTexture(nil, "ARTWORK")
    hub.logo:SetTexture((EllesmereUI.MEDIA_PATH or "Interface\\AddOns\\EllesmereUI\\media\\")
                        .. "eg-logo.tga")
    hub.logo:SetPoint("CENTER")
    hub.logo:Hide()

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

    -- The palette's own entries exist from the outset; nested ones are made on
    -- demand, because most palettes hold none and a full set would be another
    -- ninety-six frames per view.
    for i = 1, MAX_SLOTS do view.widgets[i] = CreateSlotWidget(view, i) end

    views[#views + 1] = view
    return view
end

-- A cell's widget, created if this view has never drawn a cell that far out.
function PaletteView:Widget(index)
    local w = self.widgets[index]
    if not w then
        w = CreateSlotWidget(self, index)
        self.widgets[index] = w
    end
    return w
end

-- Paint one cell from its slot. Shared by the palette's own entries and by the
-- nested ones, which differ only in where they are placed and when they are
-- shown -- a second copy of this is how a nested entry ends up with no cooldown
-- swirl or the wrong label the first time either option moves.
local function PaintCell(w, slot, placeholder, showLabels, showCooldowns, wantLabel)
    w.isPlaceholder = placeholder

    local icon, name = SlotDisplay(slot)
    w.icon:SetTexture(icon or QUESTION_MARK)
    w.icon:SetShown(not placeholder)
    w.plus:SetShown(placeholder)

    local labelled = showLabels and wantLabel and name ~= nil
    w.label:SetText((labelled and name) or "")
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

    ApplySlotVisual(w, false)
end

-- Lay the palette out and paint every widget from the stored slot data.
function PaletteView:Layout(paletteIndex)
    -- Clamped to what can be STORED rather than to what can be bound: a nested
    -- palette is opened through its parent and may well have no key of its own.
    paletteIndex = min(MAX_PALETTES, max(1, paletteIndex or self.paletteIndex or 1))
    local p, palette = P(), EnsurePalette(paletteIndex)
    if not p or not palette then return end

    local opts = self.opts
    self.paletteIndex = paletteIndex
    -- Derived, never stored: the palette is exactly as big as what is on it.
    local n = #palette.slots
    -- An interactive view draws one entry more than the palette holds: the "+"
    -- placeholder. It is a real entry, so adding an action visibly re-fans the
    -- palette instead of filling a gap that was reserved for it all along.
    local shown = (opts.interactive and n < MAX_SLOTS) and (n + 1) or n
    self.slotCount, self.shownCount = n, shown

    local step, arcStart = self:ArcGeom(shown)
    local radius, iconSize = self:Geom()
    local fan = self:IsFan()

    -- Worked out before the frame is sized, not with the entries it places: a
    -- nested arc reaches further out than the palette's own ring, and a frame
    -- sized to the ring alone would clip every child drawn beyond it.
    local claims = self:ChildGeom(shown, palette)
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
    if not opts.interactive then frame:SetScale(p.scale or 1) end
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

    local showLabels = opts.showLabels
    if showLabels == nil then showLabels = p.showLabels end
    local showCooldowns = opts.showCooldowns
    if showCooldowns == nil then showCooldowns = p.showCooldowns end

    for i = 1, shown do
        local w = self.widgets[i]
        -- Switching modes leaves the other mode's depth cues behind.
        w:SetAlpha(1)
        w:SetScale(1)
        -- The size a selection zoom is measured from. The strip and the grid
        -- publish their own, entry by entry, in the geometry passes below.
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
        PaintCell(w, palette.slots[i], palette.slots[i] == nil,
                  showLabels, showCooldowns, not fan)
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
                    local a = c.start + (j - 1) * c.step
                    w:SetPoint("CENTER", frame, "CENTER",
                               c.radius * sin(a), c.radius * cos(a))
                end
                w:SetSize(c.icon, c.icon)
                w:EnableMouse(false)
                PaintCell(w, c.slots[j], false, showLabels, showCooldowns, true)
                -- Hidden until its parent is pointed at -- see UpdateNestShown.
                w:Hide()
            end
        end
    end
    self.claims = claims
    self.cellCount = cells
    self._openClaim = nil

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
    -- Exactly one piece of hub art, and only where the centre is empty.
    local useLogo = p.hubIcon == true
    hub.dot:SetShown(not fan and not useLogo)
    hub.logo:SetShown(not fan and useLogo)
    if not fan and useLogo then
        -- Scaled by whatever the view scaled its geometry by, recovered from
        -- the icon size Geom actually handed back. The options preview fits the
        -- palette to its panel, and a hub drawn at the profile's literal pixel
        -- size would swamp a palette that had been shrunk to two-thirds.
        local _, viewIcon = self:Geom()
        local base = p.iconSize or 44
        local k = (base > 0) and (viewIcon / base) or 1
        local sz = max(8, (p.hubIconSize or 46) * k)
        hub.logo:SetSize(sz, sz)
        hub.logo:SetAlpha(min(1, max(0, p.hubIconAlpha or 0.55)))
    end
    self:PlaceHubText()
    hub.text:SetText(palette.name or ("Palette " .. paletteIndex))
    hub.text:SetTextColor(0.8, 0.8, 0.8)

    if opts.hintText then
        hub.hint:SetText(opts.hintText(n) or "")
    elseif n == 0 then
        -- An empty palette is a real state now, and a bare hub with no explanation
        -- looks like a bug rather than "you haven't filled this in yet".
        hub.hint:SetText("no actions assigned")
    else
        local k1 = GetBindingKey(BINDING_PREFIX .. paletteIndex)
        hub.hint:SetText(p.showHubText and (k1 or "") or "")
    end
end

-- The slot a cell index draws, and the claim it belongs to for a nested one.
-- Every cell past shownCount is somebody's child; the palette's own entries map
-- straight through.
function PaletteView:CellSlot(index)
    if not index then return nil end
    local palette = EnsurePalette(self.paletteIndex)
    if not palette then return nil end
    if index <= self.shownCount then return palette.slots[index] end
    local claims = self.claims
    for k = 1, (claims and #claims or 0) do
        local c = claims[k]
        if c.base and index > c.base and index <= c.base + c.n then
            return c.slots[index - c.base], c, index - c.base
        end
    end
    return nil
end

-- Which nest is open. One at a time, and only while the cursor is on its parent
-- or on one of its own entries -- every nest drawn at once would bury the
-- palette it hangs off. The hit test does NOT consult this: a release is
-- resolved from the cursor alone, so a flick that outruns the drawing still
-- fires the child it pointed at. Same bargain flick-ahead already makes.
function PaletteView:UpdateNestShown(index)
    local claims = self.claims
    if not claims then return end

    local open
    for k = 1, #claims do
        local c = claims[k]
        if index and c.base
           and (index == c.parent or (index > c.base and index <= c.base + c.n)) then
            open = c
        end
    end
    if self._openClaim == open then return end
    self._openClaim = open

    for k = 1, #claims do
        local c = claims[k]
        for j = 1, c.n do
            local w = c.base and self.widgets[c.base + j]
            if w then w:SetShown(c == open) end
        end
    end
end

-- Paint selection state. Called from OnUpdate whenever the hovered slot
-- changes, and once from Open so the initial state is drawn.
function PaletteView:SetSelection(index)
    if self.selection == index then return end
    self:UpdateNestShown(index)

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

        local slot, claim, childIndex = self:CellSlot(index)
        local _, name = SlotDisplay(slot)
        local r, g, b = SelectColor()
        -- A nested entry is captioned under the palette it came from, so the
        -- hub still says where in the palette the cursor actually is.
        if claim then
            local _, parentName = SlotDisplay(self:CellSlot(claim.parent))
            if parentName and name then
                name = parentName .. " \194\187 " .. name
            end
        end
        hub.text:SetText(name or (w.isPlaceholder and "Add Action") or ("Slot " .. index))
        hub.text:SetTextColor(r, g, b)

        -- The needle points along a entry angle; the fan has no angles.
        if p and p.showNeedle and not self:IsFan() then
            local radius, iconSize, deadZone = self:Geom()
            local step, arcStart = self:ArcGeom(self.shownCount)
            local a = arcStart + (index - 1) * step
            if claim then a = claim.start + (childIndex - 1) * claim.step end
            local mid = (deadZone + radius - iconSize * 0.5) * 0.5
            hub.needle:ClearAllPoints()
            hub.needle:SetPoint("CENTER", hub, "CENTER", mid * sin(a), mid * cos(a))
            hub.needle:SetRotation(-a)
            hub.needle:SetVertexColor(r, g, b, 0.9)
            hub.needle:Show()
        end
    else
        local palette = EnsurePalette(self.paletteIndex)
        hub.text:SetText((palette and palette.name) or "")
        hub.text:SetTextColor(0.8, 0.8, 0.8)
        hub.needle:Hide()
    end
end

-- Baseline for the movement gate in HitTest. Read AFTER the frame is placed so
-- the scale used here is the one the hit test will use.
function PaletteView:ArmMovementGate()
    local es = self.frame:GetEffectiveScale()
    local x, y = GetCursorPosition()
    self._gateX, self._gateY = x / es, y / es
    self._steered = false
end

-- Cursor -> entry index. nil inside the dead zone, and -- while the movement
-- gate is armed -- until the cursor has actually moved. The gate is what makes
-- "open and release without moving" a cancel in FIXED-POSITION mode, where the
-- cursor starts at some arbitrary point on the palette rather than at the center
-- and would otherwise have a slot pre-selected the instant the palette opens.
function PaletteView:HitTest()
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

    -- atan2(dx, dy) measures clockwise from straight up, matching the layout
    -- (slot 1 at 12 o'clock, index increasing clockwise).
    local theta = atan2(dx, dy)
    if theta < 0 then theta = theta + TWO_PI end

    -- Nested entries before anything else. With overflow allowed a child sector
    -- reaches past its parent's own, so answering the parent first would settle
    -- the question before the child was ever considered. The claims are
    -- disjoint, so at most one of them can match.
    local claims = self.claims
    for k = 1, (claims and #claims or 0) do
        local c = claims[k]
        if c.base and dist >= c.band and c.step > 0 then
            local rel = (theta - c.start + c.step * 0.5) % TWO_PI
            if rel < c.n * c.step then
                return c.base + floor(rel / c.step) + 1
            end
        end
    end

    if dist < deadZone then return nil end

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
--  The live palette
-------------------------------------------------------------------------------
local function CreateLiveView()
    if liveView then return liveView end
    liveView = ns.CreatePaletteView(UIParent, { frameName = "EUIActionPaletteFrame", live = true })
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
-- time in combat, which is exactly when the palette gets used.
--
-- Mouse WHEEL only, never EnableMouse: a full-screen mouse-enabled frame would
-- sit between the player and the world, and would swallow the very button
-- presses the secure activation path depends on.
local function EnsureSecureHeader()
    if not secureHeader then
        secureHeader = CreateFrame("Frame", "EUIActionPaletteSecureHeader",
            UIParent, "SecureHandlerBaseTemplate")
    end
    return secureHeader
end

-- One wheel tick. This is the ONLY place the strip's index is advanced: the Lua
-- handler that used to do it is gone, because an addon may not write these
-- attributes once the player is in combat. The options preview does not scroll
-- at all -- it jumps with SetFanCenter -- so nothing else needs the old path.
local SNIPPET_WHEEL = [==[
    if not self:GetAttribute("eapOpen") then
        -- Nothing has this open, so it must stop eating camera zoom. This is the
        -- self-heal for a palette that never saw its key-up -- a zone change or
        -- a taxi swallowing the release -- and it costs one notch of zoom.
        self:Hide()
        return false
    end
    local n = tonumber(self:GetAttribute("eapShown")) or 0
    if n < 1 then return false end

    local delta = offset
    if self:GetAttribute("eapInvert") then delta = -delta end
    -- Scrolling up travels toward earlier entries, the direction they are drawn
    -- in for a vertical strip, and the natural reading order for a horizontal
    -- one.
    local step = -1
    if delta <= 0 then step = 1 end

    -- The press seeds this at 1, the entry the strip opens centred on, so every
    -- tick is a plain step from wherever the strip already is. The `or 1` is for
    -- a tick that arrives with no press behind it at all.
    local t = (tonumber(self:GetAttribute("eapFanTarget")) or 1) + step
    self:SetAttribute("eapFanTarget", t)
    return false
]==]

local function EnsureScrollCatcher()
    if scrollCatcher then return scrollCatcher end
    local f = CreateFrame("Frame", "EUIActionPaletteScrollCatcher", UIParent,
        "SecureHandlerBaseTemplate")
    f:SetAllPoints(UIParent)
    f:SetFrameStrata(LIVE_STRATA)
    f:SetFrameLevel(1)
    f:EnableMouseWheel(true)
    SecureHandlerWrapScript(f, "OnMouseWheel", EnsureSecureHeader(), SNIPPET_WHEEL)
    f:Hide()
    scrollCatcher = f
    return f
end

-- Flick-ahead. The palette is held invisible for a moment after the key goes down
-- and then fades in, so a gesture finished inside that window never summons a
-- menu at all. It is a DRAWING delay only: the frame is shown and its OnUpdate
-- is running the whole time, so the selection a fast flick lands on is exactly
-- the one a slow one would have.
--
-- Arc only. A fan has to be read before it can be steered, and a scroll fan
-- cannot even be entered without seeing where the strip starts.
local function FlickAlpha()
    local p = P()
    if not p or not p.flickAhead or liveView:IsFan() then return 1 end

    local delay = p.flickDelay or 0.12
    local fade  = p.flickFade or 0.10
    local t = GetTime() - openedAt
    if t <= delay then return 0 end
    if fade <= 0 or t >= delay + fade then return 1 end
    return (t - delay) / fade
end

-- One alpha for the whole palette, so the flick-ahead fade-in and the
-- cancel fade cannot fight over the frame. Only the scroll-steered strip has a
-- cancel box to approach; the others answer 1.
local function UpdatePaletteAlpha()
    local a = FlickAlpha()
    if liveView:IsFan() and not liveView:IsPointerLayout() then
        a = a * liveView:FanCancelAlpha()
    end
    liveView:GetFrame():SetAlpha(a)
end

local function OnPaletteUpdate(_, elapsed)
    if GetTime() - openedAt > OPEN_TIMEOUT then
        ns.Close()
        return
    end
    if liveView:IsPointerLayout() then
        liveView:AdvanceGrid()
    elseif liveView:IsFan() then
        liveView:AdvanceFan(elapsed)
    else
        liveView:SetSelection(liveView:HitTest())
    end
    -- After the steering, not before: the cancel fade reads the same pointer
    -- position the selection was just decided from.
    UpdatePaletteAlpha()
end

-- forceFixed: ignore CURSOR mode and place the palette at its fixed position.
-- Nothing passes it since the full-screen editor was retired; it stays because
-- on-screen drag positioning is being reworked and needs exactly this. Fixed
-- Position mode itself goes through the same branch via p.centerMode.
local function PositionPalette(forceFixed)
    local p = P()
    local palette = liveView:GetFrame()
    palette:ClearAllPoints()
    if forceFixed or p.centerMode == "SCREEN" then
        local s = p.scale or 1
        if s == 0 then s = 1 end
        palette:SetPoint("CENTER", UIParent, "CENTER", (p.posX or 0) / s, (p.posY or 0) / s)
    else
        local es = palette:GetEffectiveScale()
        local x, y = GetCursorPosition()
        palette:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / es, y / es)
    end
end

function ns.Open(paletteIndex)
    local p = P()
    if not p or not p.enabled then return end

    CreateLiveView()
    liveView:Layout(paletteIndex)
    PositionPalette()
    -- After PositionPalette, never before: which side the caption hangs on is
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
        -- Open with the centred entry ALREADY selected, so the entry the strip
        -- opens on costs no ticks at all and the first tick moves by one. The
        -- strip used to open on nothing and be entered by that first tick, which
        -- made its own starting entry the one entry that could not be chosen
        -- without scrolling off it and back. Cancelling is FanCancelled's job
        -- now -- throw the pointer clear of the strip.
        liveView:ArmMovementGate()
        liveView.fanTarget = 1
        liveView.fanVisual = 1
        liveView:ApplyFanGeometry()
        -- Guarded: an empty palette has no entry 1 to select, and painting one
        -- would caption the hub with a slot that is not drawn.
        liveView:SetSelection(liveView:ShownCount() > 0 and 1 or nil)
    else
        liveView:ArmMovementGate()
        liveView:SetSelection(liveView:HitTest())
    end

    local palette = liveView:GetFrame()
    -- Applied before the first frame rather than left to OnUpdate: the palette is
    -- shown on this one, and the previous open's alpha would flash through.
    UpdatePaletteAlpha()
    palette:SetScript("OnUpdate", OnPaletteUpdate)
    palette:Show()
end

-- ESCAPE belongs to the game menu again. The release snippet drops this binding
-- on every ordinary close; this is for the closes that never see a release --
-- the open timeout, a zone change -- and it runs whether or not the palette is
-- still up, because the press that finds ESCAPE still bound is exactly the one
-- that has to hand it back.
--
-- Protected in combat, so a close mid-fight leaves the binding standing. That is
-- why PLAYER_REGEN_ENABLED tries again: ESCAPE bound to a palette that closed
-- half an hour ago is a dead key, with no gesture left to free it.
local function ReleaseEscape()
    if cancelButton and not InCombatLockdown() then
        ClearOverrideBindings(cancelButton)
    end
end

function ns.Close()
    if not liveView then return end
    local palette = liveView:GetFrame()
    if not palette:IsShown() then
        ReleaseEscape()
        return
    end
    palette:SetScript("OnUpdate", nil)
    palette:Hide()
    -- The PostClick snippet hides this on every normal close. This covers the
    -- ones that never get a key-up at all -- the open timeout, a zone change --
    -- and only out of combat, the frame being protected. In combat the palette
    -- snippet hides it on the next stray tick instead.
    -- Clearing the accumulator matters as much as hiding it. The strip now
    -- opens with entry 1 seeded, so a key-up that arrives after one of these
    -- unattended closes -- the open timeout, a zone change -- would otherwise
    -- fire that entry with nothing on screen. In combat the write is not
    -- allowed and the seed stands; the release is still bounded by the palette
    -- that was pushed, and the timeout is long enough that a key held that far
    -- past a close is not an ordinary gesture.
    if scrollCatcher and not InCombatLockdown() then
        scrollCatcher:SetAttribute("eapFanTarget", nil)
        scrollCatcher:Hide()
    end
    ReleaseEscape()
    liveView.fanTarget = nil
    liveView:SetSelection(nil)
end

-- The slot the user is currently pointing at, or nil.
function ns.CurrentSlot()
    local selection = liveView and liveView:GetSelection()
    if not selection then return nil end
    -- Through the cell map, so a nested entry answers with its OWN slot rather
    -- than with whatever the parent palette happens to hold at that index.
    return (liveView:CellSlot(selection))
end

-------------------------------------------------------------------------------
--  Secure activation
-------------------------------------------------------------------------------
local secureButtons = {}
local bindOwner

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
local function LayoutModel()
    local p = P()
    local layout = (p and p.layout) or "ARC"
    if layout == "ARC" then return "ANGULAR" end
    if layout == "GRID" then return "POINTER" end
    return ((p and p.fanInput) or "SCROLL") == "CURSOR" and "POINTER" or "SCROLL"
end

-- Which slot a release fires is decided by where the cursor is at that instant,
-- so the decision cannot be made in Lua. Writing the chosen action onto the
-- button from an insecure PreClick fails as soon as the player is in combat:
--
--   ADDON_ACTION_BLOCKED  tried to call the protected function
--   'EUIActionPaletteButton1:SetAttribute()'
--
-- Confirmed in-game. Note that SimpleFrameAPIDocumentation.lua does NOT flag
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
-- other side of the +0.5 rounding on a entry boundary -- 735 disagreements
-- across a 2.7M-position sweep, all of them exactly on an edge.
local SNIPPET_PRE = [==[
    local ui = self:GetFrameRef("ui")
    local mode = self:GetAttribute("eapMode")
    local catcher = self:GetFrameRef("catcher")
    local cancel = self:GetFrameRef("cancel")

    if down then
        self:SetAttribute("eapWhy", "pressed")
        self:SetAttribute("eapIdx", nil)
        -- Claim ESCAPE for as long as this palette is up, and clear whatever a
        -- previous open left on the flag. The binding is owned by the cancel
        -- button, not by us: every palette binds the same key to the same button,
        -- and one owner means one binding to drop however the palette closes.
        -- Every layout gets this -- the flag is read before any of the steering
        -- below, so escaping out is one rule, not three.
        if catcher then catcher:SetAttribute("eapCancel", nil) end
        if cancel then
            cancel:SetBindingClick(true, "ESCAPE", cancel, "LeftButton")
        end
        -- Kept on the button, not in a snippet global: every palette shares one
        -- header, so a global would let palette 2's press reset palette 1's origin.
        self:SetAttribute("eapGX", nil)
        self:SetAttribute("eapGY", nil)
        if ui then
            local x, y = ui:GetMousePosition()
            if x then
                self:SetAttribute("eapGX", x * ui:GetWidth())
                self:SetAttribute("eapGY", y * ui:GetHeight())
            end
        end
        if mode == "SCROLL" and catcher then
            -- 1, not nil: the strip opens centred on its first entry and that
            -- entry is selected from the outset. See the wheel snippet.
            catcher:SetAttribute("eapFanTarget", 1)
            catcher:SetAttribute("eapShown", self:GetAttribute("eapShown"))
            catcher:SetAttribute("eapInvert", self:GetAttribute("eapInvert"))
            catcher:SetAttribute("eapOpen", 1)
            catcher:Show()
        end
        self:SetAttribute("type", nil)
        return nil, 1
    end

    self:SetAttribute("type", nil)

    -- Escaped out while the key was still held. Checked before anything is
    -- steered, so it beats every layout's own cancel and cannot be undone by
    -- moving the pointer back onto the palette.
    if catcher and catcher:GetAttribute("eapCancel") then
        self:SetAttribute("eapWhy", "escaped") return nil, 1
    end

    local n = tonumber(self:GetAttribute("eapShown")) or 0
    if n < 1 then self:SetAttribute("eapWhy", "noslots") return nil, 1 end
    -- Every cell, the palette's own entries and the nested ones after them. The
    -- nested ones are always live, whether or not the palette has drawn them --
    -- there is no state here to say which nest was open, and the drawing is a
    -- consequence of the cursor rather than a gate on it.
    local total = tonumber(self:GetAttribute("eapTotal")) or n

    local idx
    if mode == "SCROLL" then
        -- The wheel snippet has been keeping the accumulator; the cursor plays
        -- no part in this layout, so none of the pointer work below applies.
        if not catcher then
            self:SetAttribute("eapWhy", "nocatcher") return nil, 1
        end
        local ft = tonumber(catcher:GetAttribute("eapFanTarget"))
        self:SetAttribute("eapRel", ft)
        if not ft then
            -- The press seeds the accumulator, so this can only mean the press
            -- never reached the catcher. Nothing was steered; cancel.
            self:SetAttribute("eapWhy", "unscrolled") return nil, 1
        end

        idx = ((ft - 1) % n) + 1

        -- Offset from where the pointer was when the palette opened, which is
        -- what this layout measures both its cancel and its nests from.
        local gx = tonumber(self:GetAttribute("eapGX"))
        local gy = tonumber(self:GetAttribute("eapGY"))
        local dx, dy
        if gx and ui then
            local x, y = ui:GetMousePosition()
            if x then
                local s = tonumber(self:GetAttribute("eapScale")) or 1
                if s <= 0 then s = 1 end
                dx = (x * ui:GetWidth() - gx) / s
                dy = (y * ui:GetHeight() - gy) / s
            end
        end

        -- Into the nest the wheel's entry opens, if the pointer has gone there.
        -- Before the cancel below, and not only for speed: the children sit
        -- past the ordinary margin, so a release among them reads as thrown
        -- clear until this has had its say.
        local base = tonumber(self:GetAttribute("eapNBase" .. idx))
        local hit
        if base and dx then
            local num = tonumber(self:GetAttribute("eapNNum" .. idx)) or 0
            for j = 1, num do
                local i2 = base + j
                local bx = tonumber(self:GetAttribute("eapBX" .. i2))
                local by = tonumber(self:GetAttribute("eapBY" .. i2))
                if bx and abs(dx - bx) <= (tonumber(self:GetAttribute("eapHW" .. i2)) or 0)
                       and abs(dy - by) <= (tonumber(self:GetAttribute("eapHH" .. i2)) or 0) then
                    idx = i2
                    hit = true
                    break
                end
            end
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
        local margin = tonumber(self:GetAttribute("eapFanMargin"))
        local half = tonumber(self:GetAttribute("eapFanHalf"))
        if not hit and dx and margin and half then
            local along, across = dx, dy
            if not self:GetAttribute("eapFanHoriz") then
                along, across = across, along
            end
            -- Reaching toward a nest is not leaving. Only on the side that
            -- nest is on, and only while its entry is the one the wheel is on.
            local am = margin
            local na = tonumber(self:GetAttribute("eapNAcross" .. idx))
            local ns = tonumber(self:GetAttribute("eapNSide" .. idx))
            if na and ns and (across > 0) == (ns > 0) and na > am then am = na end
            if abs(across) > am or abs(along) > half + margin then
                self:SetAttribute("eapWhy", "thrownclear") return nil, 1
            end
        end
    else
        if not ui then self:SetAttribute("eapWhy", "nohandle") return nil, 1 end
        local x, y = ui:GetMousePosition()
        if not x then self:SetAttribute("eapWhy", "offscreen") return nil, 1 end
        local w, h = ui:GetWidth(), ui:GetHeight()
        local cx, cy = x * w, y * h

        local gx = tonumber(self:GetAttribute("eapGX"))
        local gy = tonumber(self:GetAttribute("eapGY"))

        -- SetPoint offsets are read in the palette's own scaled space, so the
        -- centre sits exactly posX/posY UIParent units from UIParent's centre;
        -- the scale only converts the distance from there.
        local s = tonumber(self:GetAttribute("eapScale")) or 1
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
            self:SetAttribute("eapWhy", "unmoved") return nil, 1
        end

        local ox, oy
        if self:GetAttribute("eapFixed") then
            ox = w * 0.5 + (tonumber(self:GetAttribute("eapPosX")) or 0)
            oy = h * 0.5 + (tonumber(self:GetAttribute("eapPosY")) or 0)
        elseif gx then
            ox, oy = gx, gy
        else
            self:SetAttribute("eapWhy", "noorigin") return nil, 1
        end
        local dx, dy = (cx - ox) / s, (cy - oy) / s
        self:SetAttribute("eapDX", dx)
        self:SetAttribute("eapDY", dy)

        if mode == "POINTER" then
            local pitch = tonumber(self:GetAttribute("eapPitch")) or 1
            if pitch <= 0 then pitch = 1 end

            -- Nested cells first, and by CONTAINMENT: a half-extent is what
            -- marks a cell as one. Inside a box, that child regardless of what
            -- the block holds underneath; outside every box, the block answers
            -- as though the nest were not there. In index order, so two boxes
            -- that overlap still have one answer -- the same walk the palette
            -- draws with, which is the requirement, disjointness not being one.
            for i = n + 1, total do
                local hw = tonumber(self:GetAttribute("eapHW" .. i))
                if hw then
                    local bx = tonumber(self:GetAttribute("eapBX" .. i)) or 0
                    local by = tonumber(self:GetAttribute("eapBY" .. i)) or 0
                    local hh = tonumber(self:GetAttribute("eapHH" .. i)) or 0
                    if abs(dx - bx) <= hw and abs(dy - by) <= hh then
                        idx = i
                        break
                    end
                end
            end

            -- Nearest of the palette's own, by true 2D distance in cells. A grid
            -- has no privileged axis, so projecting onto one would let sideways
            -- movement change the choice. Past eapReach cells from every entry
            -- nothing is selected -- that is this layout's cancel, and it has no
            -- dead zone: the centre of a grid can hold an entry, so cancelling
            -- there would make the middle of an odd-sized grid unfireable.
            if not idx then
                local bestK
                for i = 1, n do
                    local bx = tonumber(self:GetAttribute("eapBX" .. i))
                    local by = tonumber(self:GetAttribute("eapBY" .. i))
                    if bx then
                        local px, py = (dx - bx) / pitch, (dy - by) / pitch
                        local k = (px * px + py * py) ^ 0.5
                        if not bestK or k < bestK then idx, bestK = i, k end
                    end
                end
                self:SetAttribute("eapRel", bestK)
                if bestK and bestK > (tonumber(self:GetAttribute("eapReach")) or 1) then
                    idx = nil
                end
            end
            if not idx then
                self:SetAttribute("eapIdx", nil)
                self:SetAttribute("eapWhy", "outofreach") return nil, 1
            end
        else
            local dist = (dx * dx + dy * dy) ^ 0.5
            local theta = atan2(dx, dy)
            if theta < 0 then theta = theta + 360 end
            self:SetAttribute("eapTheta", theta)

            -- Nested entries first. A child sector can reach past its parent's
            -- own when overflow is allowed, so answering the parent first would
            -- settle the question before the child was ever considered. The
            -- claims are disjoint, so at most one of them can match.
            local claims = tonumber(self:GetAttribute("eapClaims")) or 0
            for k = 1, claims do
                local band = tonumber(self:GetAttribute("eapCBand" .. k))
                local cstep = tonumber(self:GetAttribute("eapCStepDeg" .. k)) or 0
                local cn = tonumber(self:GetAttribute("eapCN" .. k)) or 0
                if band and dist >= band and cstep > 0 and cn > 0 then
                    local crel = (theta
                        - (tonumber(self:GetAttribute("eapCStartDeg" .. k)) or 0)) % 360
                    if crel < cn * cstep then
                        idx = (tonumber(self:GetAttribute("eapCBase" .. k)) or 0)
                              + floor(crel / cstep) + 1
                        break
                    end
                end
            end

            if not idx then
                local dz = tonumber(self:GetAttribute("eapDeadZone")) or 24
                if dist < dz then
                    self:SetAttribute("eapWhy", "deadzone") return nil, 1
                end

                local step = tonumber(self:GetAttribute("eapStepDeg")) or 0
                if step == 0 then
                    idx = 1
                else
                    local rel = theta - (tonumber(self:GetAttribute("eapStartDeg")) or 0)
                    self:SetAttribute("eapRel", rel)
                    if self:GetAttribute("eapFull") then
                        idx = (floor(rel / step + 0.5) % n) + 1
                    else
                        rel = rel % 360
                        if rel <= (n - 1) * step + step * 0.5 then
                            idx = floor(rel / step + 0.5) + 1
                        end
                    end
                end
            end
        end
    end

    self:SetAttribute("eapIdx", idx)
    if not idx or idx < 1 or idx > total then
        self:SetAttribute("eapWhy", "noidx") return nil, 1
    end

    -- Stopped on a slot that opens a palette rather than going through it.
    if self:GetAttribute("eapPal" .. idx) then
        self:SetAttribute("eapWhy", "palette") return nil, 1
    end

    local t = self:GetAttribute("eapT" .. idx)
    if not t then self:SetAttribute("eapWhy", "emptyslot") return nil, 1 end

    -- Clear every action key before writing this slot's, so no earlier slot's
    -- value can outlive it: type="macro" reads "macro" before it falls through
    -- to "macrotext", and type="spell" would reuse a stale "spell" happily.
    self:SetAttribute("spell", nil)
    self:SetAttribute("item", nil)
    self:SetAttribute("macro", nil)
    self:SetAttribute("macrotext", nil)
    self:SetAttribute("toy", nil)

    self:SetAttribute(self:GetAttribute("eapK" .. idx), self:GetAttribute("eapV" .. idx))
    self:SetAttribute("type", t)
    self:SetAttribute("eapWhy", "fire")
    return nil, 1
]==]

-- Leaves nothing armed: the next press has to choose again from scratch.
local SNIPPET_POST = [==[
    if down then return end
    self:SetAttribute("type", nil)
    -- Every close funnels through here, including the cancels that returned
    -- early above, so the catcher stops eating camera zoom on all of them.
    local catcher = self:GetFrameRef("catcher")
    if catcher then
        catcher:SetAttribute("eapOpen", nil)
        catcher:Hide()
    end
    -- Hand ESCAPE back to the game menu.
    local cancel = self:GetFrameRef("cancel")
    if cancel then cancel:ClearBindings() end
]==]

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
        catcher:SetAttribute("eapCancel", 1)
        -- A scroll fan's catcher is still eating the mouse wheel, and the key
        -- may be held for a while yet. Give camera zoom back now rather than at
        -- the release, which is the same thing the release itself would do.
        catcher:SetAttribute("eapOpen", nil)
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

    local btn = CreateFrame("Button", "EUIActionPaletteCancel", UIParent,
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

    cancelButton = btn
    return btn
end

local function OnPreClick(self, _, down)
    if down then
        ns.Open(self._palette)
        return
    end
    -- Nothing to commit here any more: all three steering models are resolved
    -- by the snippet, which is the only place allowed to write these attributes
    -- once the player is in combat.
end

local function OnPostClick(self, _, down)
    if down then return end
    -- Battle pets have no secure action type at all, so they still fire from
    -- here, off the Lua-side selection. Summoning one is not protected.
    local slot = ns.CurrentSlot()
    if slot and slot.kind == "battlepet" then FireInsecure(slot) end
    ns.Close()
end

local function GetSecureButton(index)
    local btn = secureButtons[index]
    if btn then return btn end

    btn = CreateFrame("Button", "EUIActionPaletteButton" .. index, UIParent,
        "SecureActionButtonTemplate")
    btn._palette = index
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

local function PushPalette(index)
    if InCombatLockdown() then return end
    local p = P()
    local btn = secureButtons[index]
    local palette = EnsurePalette(index)
    if not p or not btn or not palette or not liveView then return end

    for i = 1, MAX_SLOTS do
        local slot = palette.slots[i]
        local aType, aKey, aVal = ResolveAction(slot)
        btn:SetAttribute("eapT" .. i, aType)
        btn:SetAttribute("eapK" .. i, aKey)
        btn:SetAttribute("eapV" .. i, aVal)
        -- A palette resolves to no action, same as an empty slot. Marked so the
        -- trace can tell "you stopped on the door" from "that slot is empty".
        btn:SetAttribute("eapPal" .. i, ChildIndex(slot) and true or nil)
    end

    -- The live palette draws exactly what the palette holds -- the trailing "+"
    -- entry is the editor's -- so #slots is the count the snippet divides by, and
    -- ArcGeom is asked for the geometry rather than the snippet re-deriving it.
    local n = #palette.slots
    local step, arcStart, full = liveView:ArcGeom(n)
    local _, _, deadZone = liveView:Geom()
    -- Where the palette's centre will be, so the snippet can work in UIParent
    -- units without a handle to the palette itself. Cursor mode has no fixed
    -- centre, so the snippet takes the opening cursor position instead.
    btn:SetAttribute("eapFixed", p.centerMode == "SCREEN")
    btn:SetAttribute("eapPosX", p.posX or 0)
    btn:SetAttribute("eapPosY", p.posY or 0)
    btn:SetAttribute("eapScale", p.scale or 1)

    local model = LayoutModel()
    btn:SetAttribute("eapMode", model)
    btn:SetAttribute("eapShown", n)
    btn:SetAttribute("eapInvert", p.fanInvert == true)

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
                btn:SetAttribute("eapBX" .. i, bx)
                btn:SetAttribute("eapBY" .. i, by)
            else
                btn:SetAttribute("eapBX" .. i, nil)
                btn:SetAttribute("eapBY" .. i, nil)
            end
            -- A half-extent is what marks a cell as a nest, and the nests are
            -- written after this. Cleared over the palette's OWN range too: a
            -- longer set of nests last time would otherwise leave half-extents
            -- on indices that are now ordinary entries, and those entries would
            -- answer to containment instead of taking their turn at nearness.
            btn:SetAttribute("eapHW" .. i, nil)
            btn:SetAttribute("eapHH" .. i, nil)
        end
        btn:SetAttribute("eapPitch", pitch)
        btn:SetAttribute("eapReach", GRID_REACH)
    end

    -- The scroll fan's cancel box: a margin across, the drawn strip plus that
    -- same margin along, and the axis it runs on. Three numbers rather than the
    -- pointer layouts' table of cells, the strip having only one axis to steer.
    if model == "SCROLL" then
        local _, iconSize = liveView:Geom()
        btn:SetAttribute("eapFanMargin",
                         FAN_CANCEL_REACH * (iconSize + (p.fanGap or 10)))
        btn:SetAttribute("eapFanHalf", liveView:FanHalfLength())
        btn:SetAttribute("eapFanHoriz", liveView:FanHoriz())
    end
    btn:SetAttribute("eapDeadZone", deadZone)
    -- Degrees, not the radians ArcGeom deals in. The sandbox whitelists WoW's
    -- GLOBAL atan2 (RestrictedEnvironment.lua:60), which answers in DEGREES --
    -- where HitTest upvalues math.atan2, which answers in radians. Treating the
    -- sandbox's as radians silently rotated every selection: a release aimed at
    -- one entry fired its neighbour, and a release near the arc's edge missed
    -- entirely. Converting here keeps the one conversion in Lua, where the unit
    -- is named, and lets the snippet wrap on an exact 360.
    btn:SetAttribute("eapStepDeg", step * 180 / pi)
    btn:SetAttribute("eapStartDeg", arcStart * 180 / pi)
    btn:SetAttribute("eapFull", full)

    -- Nested entries. They are appended to the SAME action table the palette's
    -- own entries use, starting past the last of them, so the firing end of the
    -- snippet needs no idea that nesting exists: a child is a cell with a higher
    -- index. Only the claim geometry that maps an angle onto one of those
    -- indices is new.
    --
    -- The loop above has already cleared indices n+1 .. MAX_SLOTS, which is
    -- where these land, so the writes must come after it.
    local claims = liveView:ChildGeom(n, palette)
    local total = n
    for k = 1, (claims and #claims or 0) do
        local c = claims[k]
        c.base = total
        for j = 1, c.n do
            total = total + 1
            local aType, aKey, aVal = ResolveAction(c.slots[j])
            btn:SetAttribute("eapT" .. total, aType)
            btn:SetAttribute("eapK" .. total, aKey)
            btn:SetAttribute("eapV" .. total, aVal)
            btn:SetAttribute("eapPal" .. total, ChildIndex(c.slots[j]) and true or nil)
            -- A block layout's nests carry a BOX. Half-extents are what tells
            -- the snippet these cells are tested by containment rather than by
            -- nearness -- the palette's own entries have no half-extents, and
            -- fall to the nearest-cell search below.
            if c.cells then
                local b = c.cells[j]
                btn:SetAttribute("eapBX" .. total, b.x)
                btn:SetAttribute("eapBY" .. total, b.y)
                btn:SetAttribute("eapHW" .. total, b.hw)
                btn:SetAttribute("eapHH" .. total, b.hh)
            end
        end
    end
    -- Whatever a longer set of nests left behind last time. Bounded by what was
    -- actually written rather than by the theoretical maximum, so an ordinary
    -- palette does not pay a hundred attribute writes on every options tick.
    for i = max(total, MAX_SLOTS) + 1, (pushedCells[index] or 0) do
        btn:SetAttribute("eapT" .. i, nil)
        btn:SetAttribute("eapK" .. i, nil)
        btn:SetAttribute("eapV" .. i, nil)
        btn:SetAttribute("eapPal" .. i, nil)
        btn:SetAttribute("eapBX" .. i, nil)
        btn:SetAttribute("eapBY" .. i, nil)
        btn:SetAttribute("eapHW" .. i, nil)
        btn:SetAttribute("eapHH" .. i, nil)
    end
    pushedCells[index] = total
    btn:SetAttribute("eapTotal", total)

    -- A scroll-steered strip reaches its nests through the entry the WHEEL is
    -- on, not through the cursor: the wheel says which nest, and the cursor only
    -- says which of its children. One lookup per entry that nests, so the
    -- snippet goes straight from the wheel's answer to that nest's boxes.
    if model == "SCROLL" then
        for i = 1, MAX_SLOTS do
            btn:SetAttribute("eapNBase" .. i, nil)
            btn:SetAttribute("eapNNum" .. i, nil)
            btn:SetAttribute("eapNAcross" .. i, nil)
            btn:SetAttribute("eapNSide" .. i, nil)
        end
        for k = 1, (claims and #claims or 0) do
            local c = claims[k]
            btn:SetAttribute("eapNBase" .. c.parent, c.base)
            btn:SetAttribute("eapNNum" .. c.parent, c.n)
            btn:SetAttribute("eapNAcross" .. c.parent, c.across)
            btn:SetAttribute("eapNSide" .. c.parent, c.sign)
        end
    end

    -- One ANGULAR claim per slot that opens a palette. Angles in degrees, and
    -- the start is the EDGE of child 1's sector rather than its centre, so the
    -- snippet's test is a plain division with no half-step to remember.
    --
    -- A block layout's nests need none of this: they were pushed as ordinary
    -- cells above, and the nearest-cell search finds them without being told
    -- that they are nests at all.
    local angular = (model == "ANGULAR") and claims or nil
    for k = 1, MAX_SLOTS do
        local c = angular and angular[k]
        btn:SetAttribute("eapCBase" .. k, c and c.base)
        btn:SetAttribute("eapCN" .. k, c and c.n)
        btn:SetAttribute("eapCBand" .. k, c and c.band)
        btn:SetAttribute("eapCStepDeg" .. k, c and (c.step * 180 / pi))
        btn:SetAttribute("eapCStartDeg" .. k,
            c and ((((c.start - c.step * 0.5) * 180 / pi) % 360)))
    end
    btn:SetAttribute("eapClaims", angular and #angular or 0)
end

-- Bound palettes only: nested ones have no button of their own, and their
-- entries are pushed as part of whichever palette nests them.
local function PushAllPalettes()
    for i = 1, BoundPaletteCount() do PushPalette(i) end
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
    local count = BoundPaletteCount()
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
    PushAllPalettes()

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
_G._EAP_Apply = ns.Refresh

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
-- This module was called Radial Wheel until it grew layouts that are not
-- wheels. Adopt the old saved variable wholesale before AceDB ever sees the new
-- name: handing over the TABLE keeps profiles, per-character selection and
-- every palette exactly as they were, where copying only the profile would drop
-- the rest. Clearing the old global afterwards is what makes this run once.
local function MigrateLegacySV()
    if _G.EllesmereUIActionPaletteDB or not _G.EllesmereUIRadialWheelDB then return end
    _G.EllesmereUIActionPaletteDB = _G.EllesmereUIRadialWheelDB
    _G.EllesmereUIRadialWheelDB = nil
end

function EAP:OnInitialize()
    MigrateLegacySV()
    db = EllesmereUI.Lite.NewDB("EllesmereUIActionPaletteDB", DB_DEFAULTS)
    -- The profile itself is converted by P(), on first touch, so that switching
    -- profile mid-session converts the incoming one too. See MigrateNames.
    _G._EAP_AceDB = db
    ns.db = db

    _G.BINDING_HEADER_EUI_RADIAL = "EllesmereUI Action Palette"
    for i = 1, MAX_BOUND_PALETTES do
        _G["BINDING_NAME_" .. BINDING_PREFIX .. i] = "Open Action Palette " .. i
    end
end

function EAP:OnEnable()
    local p = P()
    if not p then return end

    -- Deliberately NOT gated on p.enabled. The module can be switched on from
    -- the options panel mid-session, and if the palette and these three
    -- handlers only existed for a session that started enabled, that session
    -- would run without combat-deferred rebinding or stuck-palette cleanup
    -- until a reload. Disabled costs nothing: UpdateBindings registers no
    -- keys, so nothing can open the palette.
    for i = 1, PaletteCount() do EnsurePalette(i) end
    CreateLiveView()
    EnsureScrollCatcher()
    ns.UpdateBindings()
    PushAllPalettes()

    self:RegisterEvent("UPDATE_BINDINGS", function() ns.UpdateBindings() end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if bindingsDirty then ns.UpdateBindings() end
        -- Unconditional: any palette edited during the fight was skipped by
        -- PushPalette, and the sandbox is still holding the old contents.
        PushAllPalettes()
        -- A palette that closed unattended mid-fight could not give ESCAPE
        -- back at the time. Now it can.
        if not liveView:GetFrame():IsShown() then ReleaseEscape() end
    end)
    -- A zone change while the key is held (portals, taxi) can swallow the
    -- key-up; drop the palette rather than leave it stuck.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() ns.Close() end)
end

-------------------------------------------------------------------------------
--  Slash command
-------------------------------------------------------------------------------
-- Palettes are built in the options page's own preview now, so there is nothing
-- left for the command to toggle -- it just points the way.
-- The two arc-era commands stay registered as aliases: they are muscle
-- memory by now, and a slash command that silently stops existing after a
-- rename reads as the module having been removed.
_G.SLASH_EUIACTIONPALETTE1 = "/euiap"
_G.SLASH_EUIACTIONPALETTE2 = "/euipalette"
_G.SLASH_EUIACTIONPALETTE3 = "/euirw"
_G.SLASH_EUIACTIONPALETTE4 = "/euiradial"
-- "/euiap trace" reports what the snippet decided on the last release. The
-- snippet cannot print -- there is no output in the restricted environment --
-- so it leaves its reasoning in attributes, which Lua may read at any time,
-- combat included. eapWhy is the step it stopped at:
--
--   pressed     the release never ran at all
--   escaped     ESCAPE was pressed while the palette was open
--   unscrolled  a scroll fan whose accumulator was never seeded by the press
--   thrownclear a scroll fan whose pointer was carried clear of the strip
--   nocatcher   a scroll fan with no scroll catcher reachable
--   noslots     the palette was pushed as empty
--   nohandle    no UIParent handle
--   offscreen   GetMousePosition returned nil
--   unmoved     the cursor never left the opening point
--   noorigin    cursor mode with no captured origin
--   deadzone    inside the dead zone
--   noidx       an angle outside the arc
--   outofreach  pointer layouts: further than eapReach cells from every entry
--   palette     stopped on an entry that OPENS a palette rather than going
--               through it into one of the entries beyond
--   emptyslot   that entry has no action pushed
--   fire        attributes were written; anything wrong past here is Blizzard's
--               side of the click
SlashCmdList.EUIACTIONPALETTE = function(msg)
    if type(msg) == "string" and msg:lower():find("trace") then
        for i = 1, BoundPaletteCount() do
            local btn = secureButtons[i]
            if btn then
                -- Degrees, because the arc is configured in degrees: whether a
                -- miss was legitimate is only obvious next to the arc's own
                -- extent, and radians make that a mental conversion.
                local function deg(key)
                    local v = tonumber(btn:GetAttribute(key))
                    return v and string.format("%.1f", v) or "nil"
                end
                local n     = tonumber(btn:GetAttribute("eapShown")) or 0
                local step  = tonumber(btn:GetAttribute("eapStepDeg")) or 0
                local full  = btn:GetAttribute("eapFull")
                -- The far edge the arc branch tests against.
                local bound = full and "n/a"
                    or string.format("%.1f", (n - 1) * step + step * 0.5)

                EllesmereUI.Print(("|cff0cd29fPalette %d|r why=%s idx=%s shown=%s mode=%s"):format(
                    i, tostring(btn:GetAttribute("eapWhy")),
                    tostring(btn:GetAttribute("eapIdx")), n,
                    tostring(btn:GetAttribute("eapMode"))))
                EllesmereUI.Print(("  full=%s step=%s start=%s theta=%s rel=%s bound=%s"):format(
                    tostring(full), deg("eapStepDeg"), deg("eapStartDeg"),
                    deg("eapTheta"), deg("eapRel"), bound))
                EllesmereUI.Print(("  dx=%s dy=%s fixed=%s scale=%s type1=%s val1=%s"):format(
                    tostring(btn:GetAttribute("eapDX")),
                    tostring(btn:GetAttribute("eapDY")),
                    tostring(btn:GetAttribute("eapFixed")),
                    tostring(btn:GetAttribute("eapScale")),
                    tostring(btn:GetAttribute("eapT1")),
                    tostring(btn:GetAttribute("eapV1"))))
            else
                EllesmereUI.Print(("|cff0cd29fPalette %d|r no secure button"):format(i))
            end
        end
        return
    end
    EllesmereUI.Print("|cff0cd29fAction Palette:|r configure palettes on the "
        .. "|cffffd100Action Palette|r options page -- pick the palette, then drag "
        .. "actions onto the preview.")
end
