if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQuickdraw.lua  --  hold-to-open action palette for EllesmereUI
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
--  keybind is routed to it with SetOverrideBindingClick -- along with every
--  modifier combination of that key nothing else holds, so a modifier pressed
--  or let go during the hold still reaches the button (see "Modifier variants
--  of a palette's key") -- and it is registered for "AnyDown","AnyUp":
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
--  Protected calls in this module, all of them deferred to
--  PLAYER_REGEN_ENABLED when in combat: the override-binding updates, and
--  PushPalette's writes of a palette's contents onto the secure buttons.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EQD = EllesmereUI.Lite.NewAddon(ADDON_NAME)
if not (EllesmereUI and EllesmereUI._ModuleNS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS[ADDON_NAME] = select(2, ...)  -- LOD options files read this module ns via the registry

-- The live palette's frame. CreateLiveView fills it in, and this is the one
-- part of it that is not made there.
--
-- The engine bills a script handler's whole call tree to the addon whose
-- execution context called CreateFrame for the frame that carries the handler.
-- CreateLiveView is reached from OnEnable, which runs under the parent's
-- lifecycle dispatch, so a frame made there is stamped EllesmereUI for the
-- session. This frame carries OnPaletteUpdate. Made there, every frame of
-- steering and hit testing an open palette does was billed to the parent addon
-- instead of to this one, which hid the cost of the module that causes it. The
-- main chunk runs as this addon, so the frame is stamped correctly here.
--
-- The event frame in EllesmereUI_Lite.lua is created eagerly for this reason.
local liveFrame = CreateFrame("Frame", "EUIQuickdrawFrame", UIParent)
liveFrame:Hide()

-- Upvalues
local min, max = math.min, math.max
local pi = math.pi
local tonumber, type, select = tonumber, type, select
local tinsert, tremove = table.insert, table.remove

local TWO_PI = pi * 2
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Palette / slot limits. MAX_PALETTES must match the number of <Binding>
-- entries in Bindings.xml: every palette can carry a key of its own, so no
-- palette is ever reachable only by being nested inside another one. A key is
-- what builds a palette's secure button, so the ones left unbound cost nothing.
local MAX_PALETTES = 16

-- Entries one menu may hold. Twelve was what a ring of the SETTING'S OWN
-- radius could seat without its entries touching -- at the shipped 100 and a
-- 50-unit pitch, the thirteenth overlaps its neighbour. That is no longer the
-- constraint: Menu Radius is a minimum now and the ring grows with the count
-- (see PaletteView:Geom), so the cap answers to how many entries a person can
-- still aim at rather than to how many fit. Twenty, which is where a full
-- circle gives each entry 18 degrees.
local MAX_SLOTS = 20

-- Entries a nested palette contributes through a HALO, which is eight fixed
-- positions around a cell (see HALO_DIRS) and so cannot seat a ninth child
-- without a second ring it has no room for. This is a real limit of that one
-- shape, not a readability judgement.
--
-- The arc used to share it and no longer does: an arc claim RINGS its children
-- and spills into further rings as they crowd (see ChildGeom and
-- MAX_CHILD_ROWS), so its ground grows with the count exactly as the palette's
-- own ring does. It seats a nested palette whole, like every other layout.
-- See NestChildCap, which is where the per-layout answer lives.
local MAX_CHILDREN = 8

-- How many concentric rings a nested arc's children may spill into before a
-- crowded claim just packs its last ring tighter than one child pitch. More
-- children than the span cap can hold are answered by adding a ring one child
-- pitch further out (see ChildGeom), not by pushing the existing ring out to
-- some unbounded radius. The cap keeps that answer
-- bounded on both sides: the live view and the snippet only ever carry
-- MAX_CHILD_ROWS worth of ring attributes, so a claim that would need a fifth
-- ring degrades by crowding the fourth instead of drifting the two out of
-- step with each other.
local MAX_CHILD_ROWS = 4

-- How many rect gates a single claim's REGION may be built from. One box
-- (HALO, whose ring already sits close enough round its parent that the old
-- bounding box was the true shape), three for a nest that sits in one piece
-- off one side of the block (the parent's own cell, the nest's own tight box,
-- and a corridor one child cell wide connecting them), and five for a lane
-- with the block to itself: the parent's cell plus one box per side of the
-- block its run reached, and a full run can wrap onto all four. One
-- box across the lot instead would swallow the block's own corner ground --
-- see PerimeterNest, the "Arming gates" section and RunReach.
--
-- Fourteen is what a lane sharing the block with OTHER claims comes to. Each of
-- those has its own cell taken out of this claim's coverage (see ParentHoles),
-- which splits the side it falls on into at most a slab clear of it and one
-- interval reaching back to the parent -- the pieces past it are dropped, being
-- ground this claim cannot be armed on anyway.
--
-- Derived by running .tools/quickdraw-nest over every block layout at
-- MAX_SLOTS: 500,308 arrangements -- 2 to 20 entries, every arrangement of up
-- to four nesting ones (thinned evenly past 120 per shape), 1 to 16 children
-- each, auto and pinned columns, both nest styles. Fourteen covers all but 258
-- of them; the worst single claim in the sweep comes to eighteen, and spending
-- four more gates and eight more wrapped scripts on every claim to catch that
-- last 0.05 per cent is not the trade. Past the budget the tail is dropped,
-- child-bearing pieces being written first, so a claim that does overflow loses
-- ground between its entries rather than a child.
--
-- Re-run that sweep if MAX_SLOTS, MAX_CHILDREN or any nest geometry moves --
-- this number is an OUTPUT of the nest shapes, not a choice.
local REGION_MAX = 14

-- How many drawn positions the scroll strip's arming lattice may span each
-- side of its centre: the widest each-side window the "Visible Icons" slider
-- can ask for ((9 - 1) / 2). One motion gate per position -- see
-- EnsureLatticeGates -- and the snippets loop it as __LATTICE_MAX__.
local MAX_LATTICE = 4

-- The Nest Distance the profile ships with, named because the lane style
-- reads it as a baseline rather than as a distance: a lane hugs the block, and
-- what it takes off the slider is only whatever the user asked for BEYOND
-- this. Every other style measures its whole stand-off from the slider.
local NEST_BAND_DEFAULT = 40

-- The binding ACTION name, and it keeps the module's first name for good. WoW
-- stores a keybind against this string, so renaming it would unbind every
-- palette every user has set. The name is never shown: BINDING_NAME_<action>
-- (set in OnInitialize) is what the Keybindings page reads.
local BINDING_PREFIX = "EUI_RADIAL"

-- DIALOG is also the options window's strata (EllesmereUI.lua:7126), which is
-- fine: the palette only exists on screen while a key is held.
local LIVE_STRATA = "DIALOG"

-------------------------------------------------------------------------------
--  Database
--
--  Everything under DB_DEFAULTS.profile lives in the suite's central store, at
--  EllesmereUIDB.profiles[<name>].addons.EllesmereUIQuickdraw (see
--  EllesmereUI.Lite.NewDB). That placement is the whole profile integration:
--  the data follows whichever profile the character resolves to, a profile
--  swap or import repoints db.profile and reaches _EQD_Apply through
--  RefreshAllAddons (EllesmereUI_Profiles.lua:1433), and profile export and
--  import carry the table because the module is listed in ADDON_DB_MAP
--  (EllesmereUI_Profiles.lua:83). A new setting only needs a default here to
--  be per-profile and exportable -- there is nothing else to register.
--
--  Two kinds of state must NOT be added under profile: per-character or
--  account-wide state (keybinds, for example, stay in WoW's binding system),
--  and anything read outside db.profile through a cached reference (P() is
--  the accessor that stays correct across a swap). If the module ever grows
--  unlock-anchored elements, their key prefix must also be added to
--  KEY_PREFIX_FOLDER in EllesmereUI_Profiles.lua.
-------------------------------------------------------------------------------
local DB_DEFAULTS = {
    profile = {
        -- Off until the user asks for it: a palette needs a key bound to it
        -- before it can do anything, so shipping it on would only cost a
        -- session that never wanted it.
        enabled     = false,

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
        -- level further out, on ground reached through the parent entry itself
        -- -- see ChildGeom.
        -- A clear GAP between the parent's icon and its children, not a
        -- centre-to-centre radius: measured centre to centre it has to cover
        -- both icons' halves before it separates anything at all, and at any
        -- ordinary icon size the two rings came out touching.
        nestBand     = NEST_BAND_DEFAULT,
        nestScale    = 0.8,      -- child icon size, against the palette's own
        -- Which side of a block layout the nested entries hang off is FIXED
        -- at above/right (NestMetrics). Only the equidistant ties ever
        -- consulted it -- everywhere else the side NEAREST the parent cell
        -- wins -- and it stopped being a setting; a nestSide key left in
        -- stored profiles is never read.
        -- Where a GRID puts a nest. A strip ignores this: one row or column has
        -- no interior to lay a lane or halo into, so it always builds a small
        -- block of its own, centred on the parent and broken out across the
        -- strip.
        --   PERIMETER  a lane hugging the block, centred on the point of it
        --              nearest the parent and wrapping the corners when long
        --   HALO       the eight positions around the parent, block faded behind
        -- A retired POPOUT value -- the nested palette as a detached block --
        -- reads as PERIMETER; see NestMetrics.
        gridNestStyle    = "PERIMETER",
        -- How far along the arc a nest may spread. NONE stops at the midpoint
        -- with the next NEST either side, MIDPOINT spends the whole span cap
        -- whatever is out there; both may cross the plain entries in between.
        arcChildOverflow = "NONE",   -- NONE | MIDPOINT
        arcChildMaxSpan  = 90,       -- degrees, the widest a child arc may grow

        -- Geometry. The dead zone -- the arc's central cancel circle -- is
        -- FIXED at 24 (PaletteView:Geom): it stopped being a setting, and a
        -- deadZone key left in a stored profile is simply never read.
        radius      = 100,
        iconSize    = 40,
        scale       = 1.0,

        -- Fan geometry. The proximity SELECTION EFFECTS are HARDCODED OFF
        -- (their settings were removed pending the user's own animation
        -- pass): entries draw at flat size and full alpha everywhere, and
        -- the strip spaces itself at full pitch -- FalloffRatios and
        -- SelectedZoom are the two switches. falloff / fanScaleDecay /
        -- fanAlphaDecay / fanMinScale / fanMinAlpha / selectedZoom keys left
        -- in stored profiles are never read.
        -- Entries drawn each side of the centre. The "Visible Icons" slider
        -- shows the whole strip instead -- the odd total, window * 2 + 1 --
        -- and converts both ways, so this stays the number every window,
        -- hover and snippet test is written in.
        fanVisible    = 2,
        fanGap        = 10,
        -- The settle -- how long the strip takes to slide to a scrolled-to
        -- entry -- is FIXED at 0.1s in AdvanceFan (the Settle Time setting
        -- was removed); a fanAnimTime key left in stored profiles is never
        -- read.
        fanInvert     = false,       -- flip which way a scroll tick travels

        -- Steering is FIXED: a fan is always wheel-steered (the Steering
        -- setting was removed), with the hover channel below on top. The
        -- pointer-fan machinery stays dormant behind IsHoverFan; a fanInput
        -- key left in stored profiles is never read.

        -- The scroll strip's hover channel ("Select Action with Mouse"):
        -- pointing at a drawn entry makes IT the one a release fires, the
        -- wheel's entry standing wherever the pointer is not. The wheel keeps
        -- scrolling either way.
        fanMouseSelect = true,

        -- Flick-ahead (the arc drawn only after a moment's hold, so a fast
        -- gesture never summons a menu) is FIXED in FlickAlpha now -- it
        -- stopped being a setting, and flick* keys left in stored profiles
        -- are never read.

        -- Appearance. Hub art is HARDCODED (the logo settings were removed):
        -- the arc draws the logo at 40, full alpha (see Layout). hubIcon*
        -- keys left in stored profiles are never read.

        -- The caption ("Show Action Text Label"): the selected action's NAME
        -- beside the selection, one switch for every layout -- it took over
        -- the fan's own Show Action Text. Off by default: the icons read as
        -- a palette on their own, and the tooltip already names whatever is
        -- selected.
        showActionText = false,
        -- Per-slot labels are FIXED off, the arc's connector needle FIXED
        -- on, and the palette-name-and-keybind rest caption is simply gone
        -- (the Show Slot Labels, Show Direction Needle and Show Center Text
        -- settings were removed); showLabels, showNeedle, showHubText and
        -- fanShowText keys left in stored profiles are never read.
        showCooldowns = true,
        -- Tint an entry that would do nothing right now: red out of range,
        -- blue short of the resource, gray and desaturated for anything else
        -- the game refuses. The same three cues an action button gives.
        showUsability = true,
        -- Drop entries this character cannot use AT ALL -- another class's
        -- specializations and spells, macros it does not have -- from the
        -- drawn menu entirely, so one shared menu fits every character.
        -- Off draws them as the gray placeholders they always were.
        hideUnusable = true,
        -- The dark plate behind each entry's icon is FIXED at 0.65 opacity,
        -- 0.9 selected/armed (ApplySlotVisual): it stopped being a setting,
        -- and a bgAlpha key left in stored profiles is never read.
        -- ACCENT by default: selectColorCustom flips to the stored custom
        -- color below, and useClassColor -- the Class Color swatch --
        -- overrides both while it is on.
        selectColorCustom = false,
        selectColor   = { 0.047, 0.824, 0.624 },  -- the custom swatch's start
        useClassColor = false,

        -- Toggle Menu Open, per palette. Off keeps the model the module was
        -- built on: hold the key, release to fire. On latches the menu up when
        -- the key is let go, and the Select key below is what chooses an entry.
        --
        -- A palette latches only when there IS a Select key -- see SNIPPET_PRE.
        -- One with the switch on and no key set behaves exactly as it did
        -- before, which is the only sane reading of "you have not finished
        -- setting this up yet": the alternative is a menu that opens and cannot
        -- be answered.
        toggleMode = false,
        -- Toggle World Markers, per palette. On, a world marker entry answers
        -- for its own marker in both directions: place it if it is not down,
        -- pick it up if it is. Off places every press, which moves the marker
        -- to wherever the cursor is now.
        --
        -- On by default. The raid manager offers both halves -- left click
        -- places, right click picks up
        -- (Mainline/Blizzard_CompactRaidFrameManager.lua:1058-1067) -- and a
        -- menu entry has one press to spend rather than two mouse buttons, so
        -- alternating is how it reaches the same pair.
        --
        -- The clear-all entry is unaffected, and so are the cycling entries.
        -- See the worldmarker branch of ResolveAction for why.
        worldMarkerToggle = true,
        -- The placed-marker corner pip on live menus (see MarkerPip). On by
        -- default: it is what tells a toggled entry's press apart -- place or
        -- pick up -- before it is pressed.
        worldMarkerPip = true,
        -- The key that fires the hovered entry of a latched menu, as a binding
        -- chord. One key for every palette. Claimed as an override binding for
        -- exactly as long as a menu is up and handed straight back on close, so
        -- it keeps whatever it normally does the rest of the time -- which is
        -- what makes a plain mouse button a reasonable thing to put here.
        --
        -- Empty rather than nil: a nil in a defaults table is not merged, so
        -- there would be no key to write to.
        confirmKey = "",

        -- The key that backs OUT of an open menu without firing anything.
        -- ESCAPE always does this and is not configurable; this is a second
        -- key for it, and the reason it exists is that the hand holding the
        -- menu key is nowhere near ESCAPE. A plain mouse button is the point
        -- -- right-click is the one people reach for -- and, like the Select
        -- key, it is claimed only for as long as a menu is up. Empty for the
        -- same reason as confirmKey.
        cancelKey = "",

        paletteCount   = 1,
        -- palette.slots is a DENSE, ORDERED array: the palette auto-sizes to what the
        -- user has actually assigned, so three actions means three big entries
        -- rather than three icons and five dead gaps. Order is the entry order,
        -- clockwise from 12 o'clock, and is what the editor reorders.
        palettes = {
            [1] = { name = "Action Menu 1", slots = {} },
        },
    },
}
ns.DB_DEFAULTS = DB_DEFAULTS

-- The name a palette carries until the user types one of their own. It is also
-- what an emptied name box reverts to, and the only name the legacy rename
-- below may replace, so all three read it from here.
local function AutoPaletteName(index)
    return "Action Menu " .. index
end
ns.AutoPaletteName = AutoPaletteName

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
        if palette.name == "Ring " .. i then palette.name = AutoPaletteName(i) end
        if palette.name == "Palette " .. i then palette.name = AutoPaletteName(i) end
        -- A nested entry used to be handed a COPY of the palette's name when it
        -- was created, which then went stale the moment that palette was
        -- renamed. SlotDisplay reads the palette's own name whenever the entry
        -- carries none, so the copy is simply dropped.
        for _, slot in pairs(palette.slots or {}) do
            if slot.kind == "palette" then slot.name = nil end
            -- Toys dragged in from the Collections/Toy Box frame before
            -- SlotFromCursor reclassified them landed here as kind="item",
            -- which runs SlotUsability through C_Item.IsUsableItem -- always
            -- "unusable" for a toy -- instead of the toy path, which leaves
            -- them untinted. Same fix, applied to what was already saved.
            if slot.kind == "item" and type(slot.id) == "number"
               and PlayerHasToy(slot.id) then
                slot.kind = "toy"
            end
        end
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

-- Does a blob hold anything a user actually arranged? Only the profile that is
-- ALREADY LIVE needs asking: the login pass runs before the defaults are merged
-- and can simply test the destination for emptiness, while a live destination
-- always holds the whole defaults table and would never read as empty.
local function HasPalettes(blob)
    local palettes = type(blob) == "table" and blob.palettes
    if type(palettes) ~= "table" then return false end
    for _, palette in pairs(palettes) do
        if type(palette) == "table" and type(palette.slots) == "table"
            and next(palette.slots) ~= nil then
            return true
        end
    end
    return false
end

-- One profile's move off the pre-rename keys. See MigrateLegacySV for what the
-- renames were and why current data wins.
--
-- The keys the module's central-store blob has lived under before, NEWEST
-- first: the first key holding real palettes wins, and every legacy key is
-- dropped either way, which is what makes a second pass a no-op.
--
-- live is the table the module is already reading through, passed only for the
-- profile that is active right now: the blob is poured INTO it rather than the
-- key repointed, because a swap would strand db.profile and every other holder
-- of that reference on the table they were handed.
local LEGACY_ADDON_KEYS = { "EllesmereUIActionPalette", "EllesmereUIRadialWheel" }

local function MigrateLegacyProfile(prof, live)
    local addons = type(prof) == "table" and prof.addons
    if type(addons) ~= "table" then return end
    for _, key in ipairs(LEGACY_ADDON_KEYS) do
        local legacy = addons[key]
        if type(legacy) == "table" then
            if live then
                if HasPalettes(legacy) and not HasPalettes(live) then
                    wipe(live)
                    for k, v in pairs(legacy) do live[k] = v end
                    EllesmereUI.Lite.DeepMergeDefaults(live, DB_DEFAULTS.profile)
                    -- Converted by the next P(), like any switched-in profile:
                    -- what was just poured in may carry pre-rename field names.
                    migrated[live] = nil
                end
            else
                local dest = addons.EllesmereUIQuickdraw
                if type(dest) ~= "table" or next(dest) == nil then
                    addons.EllesmereUIQuickdraw = legacy
                end
            end
        end
        addons[key] = nil
    end
end

-- The same move for the profile in use, so a profile STRING imported from a
-- pre-rename build heals when it is applied rather than at the next login.
local function MigrateActiveProfile()
    local live = db and db.profile
    if not live then return end
    local profiles = EllesmereUIDB and EllesmereUIDB.profiles
    local prof = profiles and db._profileName and profiles[db._profileName]
    MigrateLegacyProfile(prof, live)
end

-- Palettes past the first are created on demand: the defaults table only seeds
-- palette 1, so DeepMergeDefaults never has to know how many the user wants.
local function EnsurePalette(index)
    local p = P()
    -- nil is an answer, not an error: ChildIndex hands one back for a
    -- nested-palette slot whose palette number is missing or out of range, and
    -- its callers pass it straight through on their way to the question-mark
    -- fallback. Comparing it would take the paint of the whole containing
    -- palette down with it.
    if not p or not index or index < 1 or index > MAX_PALETTES then return nil end
    if not p.palettes then p.palettes = {} end
    local palette = p.palettes[index]
    if not palette then
        palette = { name = AutoPaletteName(index), slots = {} }
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

-- A palette as it already stands, with no compaction and nothing created. For
-- the READERS on a steering path: EnsurePalette allocates a slot array and
-- writes it back into the profile on every call, which is the wrong thing to do
-- once per cursor movement. A palette that has never been ensured has no
-- entries to hand back anyway, and every write site still goes through
-- EnsurePalette, so what this reads is always compact by the time it exists.
local function ReadPalette(index)
    local p = P()
    if not p or not index or index < 1 or index > MAX_PALETTES then return nil end
    local palette = p.palettes and p.palettes[index]
    if type(palette) ~= "table" then return nil end
    if type(palette.slots) ~= "table" then return nil end
    return palette
end

-------------------------------------------------------------------------------
--  Per-palette appearance
--
--  EVERY setting is a palette's own: its shape and place (layout, where it
--  opens, its sizes), its nesting geometry, and its look (colors, cooldowns,
--  the caption). The options page's "Apply All Settings From" dropdown is the
--  bridge between menus -- it copies one menu's effective values onto another
--  wholesale.
--
--  Every one of these is an OVERRIDE, not a value: a palette that has never
--  been given one reads the profile's, which is what makes this change invisible
--  to a profile written before it existed. That is also the whole of the
--  saved-variables migration -- there is nothing to move, because the old flat
--  keys are exactly the fallback the new ones fall back to.
--
--  Stored under palette.appearance rather than flat on the palette. A palette
--  already carries name, icon and slots, and a flat store would put profile
--  keys in the same namespace as those -- fine for today's key set and a trap
--  for the first profile key ever named "icon".
-------------------------------------------------------------------------------
local APPEARANCE_KEYS = {
    layout = true, fanOrientation = true,
    centerMode = true, posX = true, posY = true, scale = true,
    gridAutoColumns = true, gridColumns = true,
    arcSpan = true, arcRotation = true,
    fanVisible = true, fanGap = true, fanInvert = true,
    fanMouseSelect = true,
    radius = true, iconSize = true,
    nestBand = true, nestScale = true, gridNestStyle = true,
    arcChildOverflow = true, arcChildMaxSpan = true,
    showCooldowns = true, showUsability = true, showActionText = true,
    hideUnusable = true,
    selectColorCustom = true, selectColor = true, useClassColor = true,
    -- Per palette on purpose: a marker ring wants the flick it has always had,
    -- while a mount menu is worth latching open and pointing at. The Select key
    -- the latched one answers to is NOT here -- it is one profile key, so the
    -- gesture means the same thing whichever menu is up.
    toggleMode = true,
    -- Per palette for the same reason: a pull-timer menu that drops the eight
    -- markers in one pass wants each press to place, and a menu kept open to
    -- tidy them up afterwards wants each press to answer for its own marker.
    worldMarkerToggle = true,
    worldMarkerPip = true,
}
ns.APPEARANCE_KEYS = APPEARANCE_KEYS

-- One READ-ONLY view per palette, with that palette's overrides in front of
-- the profile. Handing this back as `p` is what let the whole renderer stay
-- written as `p.layout`: the fallback lives in one metatable instead of at
-- sixty call sites, none of which could have been left out safely.
--
-- Keyed by the palette TABLE rather than by its index: deleting a palette
-- shifts every palette above it down one, and switching profile replaces the
-- lot. An override belongs to the palette, and so does its view.
--
-- Never pruned, and not bounded by MAX_PALETTES either: deleting a palette and
-- adding one leaves the deleted table in here, alive, for the rest of the
-- session. Each entry is one empty table and one metatable, and palettes are
-- added and deleted by hand on a settings page, so the ceiling is what a person
-- can be bothered to click.
local appearanceViews = {}

local function PA(paletteIndex)
    local p = P()
    if not p then return nil end
    -- Straight off p.palettes, NOT through EnsurePalette: this runs several
    -- times per frame on every steered layout, and EnsurePalette rebuilds the
    -- slot array to compact it. A palette that has never been ensured has no
    -- overrides to read anyway, so the profile is the whole answer.
    local palette = paletteIndex and p.palettes and p.palettes[paletteIndex]
    if type(palette) ~= "table" then return p end

    local view = appearanceViews[palette]
    if not view then
        view = setmetatable({}, {
            __index = function(_, key)
                if APPEARANCE_KEYS[key] then
                    local v = palette.appearance and palette.appearance[key]
                    if v ~= nil then return v end
                end
                -- P() rather than a captured profile: a palette table outlives
                -- nothing, but reading through the accessor keeps the migration
                -- on first touch running for whichever profile is current.
                local prof = P()
                return prof and prof[key]
            end,
            -- Nothing writes through this, and a write that slipped in would
            -- land on the view and be invisible to the saved variables.
            __newindex = function() error("Quickdraw appearance view is read-only", 2) end,
        })
        appearanceViews[palette] = view
    end
    return view
end
ns.PaletteProfile = PA

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

-- How many palettes EXIST. Each of them has a <Binding> entry of its own, so
-- this is also the range every loop that claims a key or pushes actions runs
-- over -- a palette can be opened by a key, nested inside another palette, or
-- both.
local function PaletteCount()
    local p = P()
    return min(MAX_PALETTES, max(1, (p and p.paletteCount) or 1))
end
ns.PaletteCount = PaletteCount

-------------------------------------------------------------------------------
--  Nesting
--
--  A slot of kind "palette" names another palette by index. The palette it
--  names is an ordinary one -- it may carry a keybind as well, or exist purely
--  to be nested.
--
--  ONE level. A claim's ground is measured from the parent entry it hangs off,
--  and a nested entry has no ground of its own for a further claim to be
--  measured from: a palette slot INSIDE a nested palette is drawn but fires
--  nothing.
--
--  A CLAIM's cells only answer at all once the cursor has gone through the
--  claim's own parent entry first, and stop answering once it leaves the
--  claim's ground -- see ArmedClaim, EnsureGates and the two gate frames every
--  claim gets. That is PATH-dependent, so the final cursor position alone is
--  no longer the whole answer: which claim, if any, is armed is state the
--  secure sandbox has to carry across the hold, which is what the gates are
--  for.
-------------------------------------------------------------------------------

-- The palette a slot opens, or nil for a slot that fires an action.
local function ChildIndex(slot)
    if not slot or slot.kind ~= "palette" then return nil end
    local idx = tonumber(slot.palette)
    if not idx or idx < 1 or idx > MAX_PALETTES then return nil end
    return idx
end
ns.ChildIndex = ChildIndex

-- Assigned with the usability filter in EUI_Quickdraw_Actions.lua (it needs
-- SpecIndexFor; see SetUsableSlots); ChildSlots reads through it so a nested
-- menu contributes only what this character can use, under the nested
-- palette's OWN setting.
local UsableSlots

-- The reachable entries of a nested palette. Capped rather than refused, so a
-- palette that is also bound to a key keeps all twelve of its slots when it is
-- opened directly and offers what its parent's layout can seat when it is
-- nested -- the caller says how many via cap, and MAX_CHILDREN is the floor
-- every layout can manage. See NestChildCap.
local function ChildSlots(paletteIndex, cap)
    local palette = paletteIndex and EnsurePalette(paletteIndex)
    if not palette then return nil end
    local slots = UsableSlots(palette, PA(paletteIndex))
    local out = {}
    for i = 1, min(cap or MAX_CHILDREN, #slots) do
        out[i] = slots[i]
    end
    return out, palette
end
ns.ChildSlots = ChildSlots

-- How many entries a nested palette may contribute on palette `parentIndex`,
-- read off the stored profile -- what the editor's tooltip answers with, and
-- what the live views answer too, their layout following the same profile.
--
-- Every layout but one seats a nested palette WHOLE. A lane runs along a
-- block's perimeter, a strip's row spreads as wide as it needs to, and an arc
-- claim rings its children and adds a ring as they crowd -- all three have
-- ground of their own to grow into. The halo does not: it is eight fixed
-- positions around one cell, and there is no ninth to put a child in.
local function NestChildCap(parentIndex)
    local p = PA(parentIndex)
    local layout = (p and p.layout) or "ARC"
    if layout == "GRID" and p and p.gridNestStyle == "HALO" then
        return MAX_CHILDREN
    end
    return MAX_SLOTS
end
ns.NestChildCap = NestChildCap

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

-------------------------------------------------------------------------------
--  Spec assignment ("Assign to Spec") and shared keys
--
--  palette.specs is a set of retail spec IDs ({ [specID] = true }); none (nil
--  or empty) is every spec. A palette LOADS -- its key opens it, and it shows
--  where it is nested -- only while the player counts as one of its specs
--  (EllesmereUI.IsPlayerSpec: on WoW Forever any spec of the class).
--
--  palette.keyShare is the index of the palette whose key this one shares.
--  WoW's binding system holds one action per key, so a shared key stays on its
--  holder's EUI_RADIAL binding, and the override bindings send it to whichever
--  of the two loads (see KeyTarget in EUI_Quickdraw_Runtime.lua). The options
--  page makes a share only between palettes that can never load together.
-------------------------------------------------------------------------------
-- A palette's spec set, or nil for every spec.
function ns.PaletteSpecs(index)
    local p = P()
    local palette = p and index and p.palettes and p.palettes[index]
    local specs = type(palette) == "table" and palette.specs
    if type(specs) ~= "table" or next(specs) == nil then return nil end
    return specs
end

function ns.PaletteActive(index)
    local specs = ns.PaletteSpecs(index)
    if not specs then return true end
    for id in pairs(specs) do
        if EllesmereUI.IsPlayerSpec(id) then return true end
    end
    return false
end

-- Can palettes a and b never load at the same time? Only when both name specs
-- and none could load both: on retail no spec in both sets, on WoW Forever no
-- class in both (the player counts as every spec of the class there).
function ns.PalettesExclusive(a, b)
    local sa, sb = ns.PaletteSpecs(a), ns.PaletteSpecs(b)
    if not sa or not sb then return false end
    if EllesmereUI.IS_FOREVER then
        for ida in pairs(sa) do
            local cls = EllesmereUI.SpecClassOf(ida)
            if cls then
                for idb in pairs(sb) do
                    if EllesmereUI.SpecClassOf(idb) == cls then return false end
                end
            end
        end
        return true
    end
    for id in pairs(sa) do
        if sb[id] then return false end
    end
    return true
end

-- The palette whose key palette `index` shares, or nil for its own. A share
-- always names the key's holder, never another palette sharing it.
function ns.ShareOwner(index)
    local p = P()
    local palettes = p and p.palettes
    local palette = palettes and palettes[index]
    local owner = type(palette) == "table" and tonumber(palette.keyShare)
    if not owner or owner == index or owner < 1 or owner > PaletteCount() then return nil end
    local held = palettes[owner]
    if type(held) == "table" and held.keyShare ~= nil then return nil end
    return owner
end

-- p is the palette view the caller draws from (self:P()) -- the color keys
-- are per-menu appearance. Falls back to the profile for a caller with none.
local function SelectColor(p)
    p = p or P()
    if p and p.useClassColor then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[select(2, UnitClass("player"))]
        if c then return c.r, c.g, c.b end
    end
    -- Accent unless a custom color has been chosen: the suite accent is the
    -- default, resolved live so theme and accent changes carry straight
    -- through.
    if not (p and p.selectColorCustom) and EllesmereUI.ResolveActiveAccent then
        return EllesmereUI.ResolveActiveAccent()
    end
    local sc = p and p.selectColor
    if sc then return sc[1] or 1, sc[2] or 1, sc[3] or 1 end
    return 0.047, 0.824, 0.624
end
ns.SelectColor = SelectColor
ns.MAX_SLOTS = MAX_SLOTS
ns.REGION_MAX = REGION_MAX
ns.MAX_PALETTES = MAX_PALETTES
ns.MAX_CHILDREN = MAX_CHILDREN

-- Main-chunk locals the EUI_Quickdraw_*.lua files re-import by name.
-- dbSetters and the three lists beside it: every file that reads one of
-- these keeps its own copy and adds a setter here; the one place that
-- assigns it writes through SetDB, SetLiveView, SetScrollCatcher or
-- SetCancelButton, which runs them all.
-- SetUsableSlots: EUI_Quickdraw_Actions.lua assigns the forward declaration.
-- broken: true while an EUI_Quickdraw_*.lua file loads; a file that fails
-- leaves it set, and the files behind it return at their first lines.
ns._qdInternals = {
    BINDING_PREFIX = BINDING_PREFIX, ChildIndex = ChildIndex, ChildSlots = ChildSlots,
    DB_DEFAULTS = DB_DEFAULTS, EnsurePalette = EnsurePalette, EQD = EQD,
    LIVE_STRATA = LIVE_STRATA, liveFrame = liveFrame, MAX_CHILD_ROWS = MAX_CHILD_ROWS,
    MAX_CHILDREN = MAX_CHILDREN, MAX_LATTICE = MAX_LATTICE, MAX_PALETTES = MAX_PALETTES,
    MAX_SLOTS = MAX_SLOTS, MigrateActiveProfile = MigrateActiveProfile,
    MigrateLegacyProfile = MigrateLegacyProfile, NEST_BAND_DEFAULT = NEST_BAND_DEFAULT, P = P,
    PA = PA, PaletteCount = PaletteCount, QUESTION_MARK = QUESTION_MARK,
    ReadPalette = ReadPalette, REGION_MAX = REGION_MAX, SelectColor = SelectColor,
    TWO_PI = TWO_PI,
    dbSetters = { function(v) db = v end },
    liveViewSetters = {},
    scrollCatcherSetters = {},
    cancelButtonSetters = {},
    SetUsableSlots = function(f) UsableSlots = f end,
    broken = false,
}
-- Set<Name> hands a new value to every copy registered in <name>Setters.
for setter, listName in pairs({ SetDB = "dbSetters", SetLiveView = "liveViewSetters",
        SetScrollCatcher = "scrollCatcherSetters", SetCancelButton = "cancelButtonSetters" }) do
    local list = ns._qdInternals[listName]
    ns._qdInternals[setter] = function(v)
        for i = 1, #list do list[i](v) end
    end
end
-- A re-import of a name this table lacks fails where the part file loads,
-- not later as a nil upvalue inside one of its functions.
setmetatable(ns._qdInternals, { __index = function(_, k)
    error("ns._qdInternals has no entry " .. tostring(k), 2)
end })
